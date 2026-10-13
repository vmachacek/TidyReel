import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';

import 'catalog_library.dart';
import 'library_organization_plan.dart';
import 'library_organizer.dart';

class LibraryOrganizationScreen extends StatefulWidget {
  const LibraryOrganizationScreen({required this.library, super.key});
  final CatalogLibrary library;

  @override
  State<LibraryOrganizationScreen> createState() =>
      _LibraryOrganizationScreenState();
}

class _LibraryOrganizationScreenState extends State<LibraryOrganizationScreen> {
  final _organizer = LibraryOrganizer();
  final _cancellation = CancellationController();
  LibraryOrganizationPlan? _plan;
  List<CatalogTitle> _titles = const [];
  List<LibraryOrganizationResult>? _results;
  String? _error;
  bool _loading = true,
      _applying = false,
      _writeAccess = false,
      _ownsLock = false;
  late final AuthorizedLibraryRoot? _root;

  @override
  void initState() {
    super.initState();
    final controller = widget.library.controller;
    _root = controller.state.root;
    _ownsLock = controller.beginLibraryOrganization();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    try {
      if (!_ownsLock || _root == null) {
        throw StateError(
          'Wait for the library scan to finish, then try again.',
        );
      }
      _writeAccess = await _organizer.hasWriteAccess(_root.locator);
      final entries = <StorageEntrySnapshot>[];
      final scanId =
          'organize-preview-${DateTime.now().microsecondsSinceEpoch}';
      var complete = false;
      await for (final event
          in widget.library.controller.storage.enumerateRecursively(
            root: _root.locator,
            scanId: scanId,
            cancellationToken: _cancellation.token,
          )) {
        if (event.scanId != scanId) continue;
        switch (event) {
          case StorageScanBatch():
            entries.addAll(event.entries);
          case StorageScanCompleted():
            complete = true;
          case StorageScanWarning() ||
              StorageScanFailed() ||
              StorageScanCancelled():
            throw StateError(
              'Could not read the entire folder. Rescan the library and try again.',
            );
          default:
            break;
        }
      }
      if (!complete) {
        throw StateError('The folder scan did not finish. Try again.');
      }
      if (!mounted) return;
      final videos = entries
          .where(
            (entry) =>
                const FileClassifier()
                    .classify(entry.displayName, isDirectory: entry.isDirectory)
                    .kind ==
                LibraryFileKind.video,
          )
          .toList();
      final sidecars = entries
          .where(
            (entry) =>
                !entry.isDirectory &&
                !entry.displayName.startsWith('._') &&
                RegExp(
                  r'\.(srt|ass|ssa|vtt|sub|idx|nfo)$',
                  caseSensitive: false,
                ).hasMatch(entry.displayName),
          )
          .toList();
      _titles = groupCatalog(videos);
      await widget.library.load();
      await widget.library.matcher.enrich(_titles, _root.locator.opaqueValue);
      if (!mounted) return;
      _plan = buildLibraryOrganizationPlan(
        titles: _titles,
        matches: widget.library.matcher.matches,
        scope: _root.locator.opaqueValue,
        sidecars: sidecars,
      );
    } on Object catch (error) {
      if (mounted) _error = _message(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _message(Object error) => switch (error) {
    PlatformException() => error.message ?? 'Could not organize this folder.',
    MissingPluginException() => 'File organization is available on Android.',
    StateError() => error.message.toString(),
    _ => 'Could not organize the library. Rescan the folder and try again.',
  };

  Future<void> _apply() async {
    final plan = _plan, root = _root;
    if (_applying ||
        _results != null ||
        plan == null ||
        root == null ||
        !_writeAccess) {
      return;
    }
    setState(() {
      _applying = true;
      _error = null;
    });
    var attempted = false;
    try {
      final controller = widget.library.controller;
      if (controller.state.root?.locator.opaqueValue !=
          root.locator.opaqueValue) {
        throw StateError('The media folder changed. Open a new preview.');
      }
      await controller.closePlayer();
      attempted = true;
      final results = await _organizer.apply(root: root.locator, plan: plan);
      _results = results;
      final sources = {
        for (final item in plan.items) item.source.storageKey: item.source,
      };
      final replacements = <String, StorageEntrySnapshot>{};
      for (final result in results) {
        if (result.newStorageKey == null ||
            (!result.moved && result.actualRelativePath == null)) {
          continue;
        }
        final source = sources[result.storageKey]!;
        final actualPath =
            result.actualRelativePath ?? result.destinationRelativePath;
        replacements[result.storageKey] = StorageEntrySnapshot(
          storageKey: result.newStorageKey!,
          parentStorageKey: result.newParentStorageKey,
          relativePath: actualPath,
          displayName: actualPath.split('/').last,
          isDirectory: false,
          mimeType: source.mimeType,
          sizeBytes: source.sizeBytes,
          modifiedAtUtc: source.modifiedAtUtc,
          flags: source.flags,
        );
      }
      await widget.library.migrateOrganizedFiles(
        scope: root.locator.opaqueValue,
        previousTitles: _titles,
        replacements: replacements,
      );
      await controller.refreshAfterLibraryOrganization(root, replacements);
      await widget.library.waitForDiscovery();
      if (controller.state.libraryFailure != null) {
        _error = 'Files were processed, but the library rescan failed. Rescan from Settings.';
      }
    } on Object catch (error) {
      _error = _message(error);
      // The provider may have completed part of a batch before disconnecting.
      if (attempted) {
        _results ??= const [];
        await widget.library.controller.refreshAfterLibraryOrganization(
          root,
          const {},
        );
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  void dispose() {
    _cancellation.cancel();
    if (_ownsLock) widget.library.controller.endLibraryOrganization();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final resultsById = {
      for (final result in _results ?? <LibraryOrganizationResult>[])
        result.storageKey: result,
    };
    final finished = _results != null;
    return PopScope(
      canPop: !_applying,
      child: Scaffold(
        key: const Key('library-organization-page'),
        appBar: AppBar(
          leading: BackButton(
            onPressed: _applying ? null : () => Navigator.of(context).pop(),
          ),
          title: const Text('Rename & organize'),
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loading || _applying) const LinearProgressIndicator(),
              Expanded(
                child: ListView.builder(
                  key: const Key('organization-preview-list'),
                  itemCount: (plan?.items.length ?? 0) + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _root?.displayName ?? 'Media library',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Clean filenames and sort into TV/ and Movies/. Subtitles follow their video. Files needing review stay in place.',
                            ),
                            if (_loading) ...[
                              const SizedBox(height: 16),
                              const Text('Preparing rename preview…'),
                            ],
                            if (plan != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                finished
                                    ? '${_results!.where((r) => r.moved).length} moved · ${_results!.where((r) => r.failed).length} failed'
                                    : '${plan.plannedCount} to move · ${plan.unchangedCount} already organized · ${plan.reviewCount} need review',
                                key: const Key('organization-summary'),
                              ),
                            ],
                            if (!_loading &&
                                !_writeAccess &&
                                _error == null) ...[
                              const SizedBox(height: 12),
                              const Text(
                                'This folder has read access only. Go back to Settings → Change media folder and select the same folder to allow renaming and moving.',
                              ),
                            ],
                            if (plan != null &&
                                plan.reviewCount > 0 &&
                                !finished) ...[
                              const SizedBox(height: 8),
                              const Text(
                                'For missing metadata, use Fix Match on the title or configure TMDB in Settings, then open a new preview.',
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _error!,
                                key: const Key('organization-error'),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }
                    final item = plan!.items[index - 1];
                    final result = resultsById[item.source.storageKey];
                    final text = result?.failed == true
                        ? result!.message ?? 'Could not move this file.'
                        : result?.moved == true
                        ? 'Moved to ${result!.destinationRelativePath}'
                        : item.reason ??
                              (item.isUnchanged
                                  ? 'Already organized'
                                  : '→ ${item.destinationRelativePath}');
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 4,
                      ),
                      leading: Icon(
                        result?.failed == true || item.needsReview
                            ? Icons.info_outline
                            : result?.moved == true || item.isUnchanged
                            ? Icons.check_circle_outline
                            : Icons.drive_file_move_outline,
                      ),
                      title: Text(
                        item.source.relativePath,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      subtitle: Text(text),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: finished
                    ? FilledButton(
                        onPressed: _applying
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Done'),
                      )
                    : FilledButton.icon(
                        key: const Key('apply-library-organization'),
                        onPressed:
                            !_loading &&
                                !_applying &&
                                _writeAccess &&
                                (plan?.plannedCount ?? 0) > 0
                            ? _apply
                            : null,
                        icon: const Icon(Icons.drive_file_move_outline),
                        label: Text(
                          _applying
                              ? 'Renaming and moving…'
                              : 'Rename & move ${plan?.plannedCount ?? 0} files',
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
