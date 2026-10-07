import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'catalog_library.dart';
import 'catalog_metadata.dart';

Future<void> openCatalogArtworkPicker(
  BuildContext context,
  CatalogLibrary library,
  CatalogTitle title, {
  VoidCallback? onReviewMatch,
}) => showDialog<void>(
  context: context,
  builder: (_) => CatalogArtworkPicker(
    library: library,
    title: title,
    onReviewMatch: onReviewMatch,
  ),
);

/// Fetching and previewing never change the artwork saved in the library.
class CatalogArtworkPicker extends StatefulWidget {
  const CatalogArtworkPicker({
    required this.library,
    required this.title,
    this.onReviewMatch,
    super.key,
  });

  final CatalogLibrary library;
  final CatalogTitle title;
  final VoidCallback? onReviewMatch;

  @override
  State<CatalogArtworkPicker> createState() => _CatalogArtworkPickerState();
}

class _CatalogArtworkPickerState extends State<CatalogArtworkPicker> {
  CatalogArtworkKind _kind = CatalogArtworkKind.poster;
  final _currentImages = <CatalogArtworkKind, Future<Uint8List?>>{};
  List<CatalogArtworkCandidate> _candidates = const [];
  final _selections = <CatalogArtworkKind, CatalogArtworkCandidate>{};
  bool _fetching = false;
  bool _saving = false;
  String? _fetchError;
  String? _saveError;

  bool get _enabled => widget.library.matcher.enabled;
  bool get _matched => widget.title.providerId?.isNotEmpty == true;
  bool get _canFetch => _enabled && _matched;
  CatalogArtworkCandidate? get _selected => _selections[_kind];
  List<CatalogArtworkCandidate> get _visibleCandidates =>
      _candidates.where((candidate) => candidate.kind == _kind).toList();

  @override
  void initState() {
    super.initState();
    for (final kind in CatalogArtworkKind.values) {
      _currentImages[kind] = widget.library.thumbnail(
        widget.title.first,
        backdrop: kind == CatalogArtworkKind.backdrop,
      );
    }
    if (_canFetch) unawaited(_refresh());
  }

  String _errorMessage(Object error, String fallback) =>
      error is CatalogMetadataException ? error.message : fallback;

  Future<void> _refresh() async {
    if (_fetching || _saving || !_canFetch) return;
    setState(() {
      _fetching = true;
      _fetchError = null;
      _saveError = null;
    });
    try {
      final candidates = await widget.library.refreshArtwork(widget.title);
      if (!mounted) return;
      setState(() {
        _candidates = candidates;
        // A newly fetched list must be reviewed before anything is saved.
        _selections.clear();
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _fetchError = _errorMessage(
          error,
          'Artwork could not be refreshed. Check your connection and try again.',
        );
      });
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<void> _save() async {
    final candidate = _selected;
    if (candidate == null || _saving || _fetching) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.library.selectArtwork(widget.title, candidate);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _saveError = _errorMessage(
          error,
          'Artwork could not be saved. Your current artwork is still in use.',
        );
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _reviewMatch() {
    Navigator.of(context).pop();
    widget.onReviewMatch?.call();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 920,
          maxHeight: math.max(0.0, MediaQuery.sizeOf(context).height - 48),
        ),
        child: SizedBox(
          width: 920,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Artwork for ${widget.title.name}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Keep current artwork and close',
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Compare your current artwork with TMDB images. Use selected downloads a copy to this device.',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final kind in CatalogArtworkKind.values)
                            ChoiceChip(
                              key: Key('artwork-kind-${kind.name}'),
                              label: Text(
                                kind == CatalogArtworkKind.poster
                                    ? 'Poster'
                                    : 'Backdrop',
                              ),
                              selected: kind == _kind,
                              onSelected: _saving
                                  ? null
                                  : (_) => setState(() {
                                      _kind = kind;
                                      _saveError = null;
                                    }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _comparison(),
                      const SizedBox(height: 16),
                      if (!_enabled)
                        const Text(
                          'Enable TMDB in Library Settings to refresh artwork.',
                        )
                      else if (!_matched) ...[
                        const Text(
                          'Choose a TMDB match for this show before refreshing artwork.',
                        ),
                        if (widget.onReviewMatch != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: _reviewMatch,
                              icon: const Icon(Icons.manage_search),
                              label: const Text('Review match'),
                            ),
                          ),
                      ] else ...[
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            Text(
                              '${_visibleCandidates.length} ${_kind == CatalogArtworkKind.poster ? 'posters' : 'backdrops'} from TMDB',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            OutlinedButton.icon(
                              key: const Key('artwork-refresh'),
                              onPressed: _fetching || _saving
                                  ? null
                                  : () => unawaited(_refresh()),
                              icon: const Icon(Icons.refresh),
                              label: Text(
                                _fetchError == null ? 'Refresh again' : 'Retry',
                              ),
                            ),
                          ],
                        ),
                        if (_fetching) ...[
                          const SizedBox(height: 12),
                          const LinearProgressIndicator(),
                          const SizedBox(height: 8),
                          const Text('Fetching artwork from TMDB…'),
                        ],
                        if (_fetchError != null) ...[
                          const SizedBox(height: 12),
                          _error(_fetchError!),
                        ],
                        if (_visibleCandidates.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _gallery(),
                        ] else if (!_fetching && _fetchError == null) ...[
                          const SizedBox(height: 12),
                          Text(
                            'TMDB has no ${_kind == CatalogArtworkKind.poster ? 'posters' : 'backdrops'} for this show. Your current artwork is still in use.',
                          ),
                        ],
                      ],
                      if (_saveError != null) ...[
                        const SizedBox(height: 12),
                        _error(_saveError!),
                      ],
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      key: const Key('artwork-keep-current'),
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Keep current'),
                    ),
                    FilledButton.icon(
                      key: const Key('artwork-use-selected'),
                      onPressed: _selected == null || _saving || _fetching
                          ? null
                          : () => unawaited(_save()),
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download),
                      label: Text(_saving ? 'Saving…' : 'Use selected'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _error(String message) => Semantics(
    liveRegion: true,
    child: Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );

  Widget _comparison() => LayoutBuilder(
    builder: (context, constraints) {
      final aspect = _kind == CatalogArtworkKind.poster ? 2 / 3 : 16 / 9;
      final height = math.min(280.0, (constraints.maxWidth - 12) / 2 / aspect);
      Widget frame(Widget child) => SizedBox(
        height: height,
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: child,
          ),
        ),
      );
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Current artwork'),
                const SizedBox(height: 8),
                frame(
                  FutureBuilder<Uint8List?>(
                    future: _currentImages[_kind],
                    builder: (context, snapshot) {
                      final bytes = snapshot.data;
                      return bytes == null
                          ? const _ArtworkPlaceholder('No current artwork')
                          : Image.memory(
                              bytes,
                              key: Key('artwork-current-${_kind.name}'),
                              fit: BoxFit.contain,
                              semanticLabel: 'Current ${_kind.name}',
                              errorBuilder: (_, _, _) =>
                                  const _ArtworkPlaceholder(
                                    'Current preview unavailable',
                                  ),
                            );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Selected artwork'),
                const SizedBox(height: 8),
                frame(
                  _selected == null
                      ? const _ArtworkPlaceholder('Select an image below')
                      : _ArtworkPreview(candidate: _selected!),
                ),
                if (_selected != null) ...[
                  const SizedBox(height: 6),
                  Text(_description(_selected!)),
                ],
              ],
            ),
          ),
        ],
      );
    },
  );

  String _description(CatalogArtworkCandidate candidate) =>
      '${candidate.width} × ${candidate.height} · ${candidate.language ?? 'No language'}';

  Widget _gallery() => LayoutBuilder(
    builder: (context, constraints) {
      final visible = _visibleCandidates;
      final columns = _kind == CatalogArtworkKind.poster
          ? constraints.maxWidth < 500
                ? 3
                : 5
          : constraints.maxWidth < 500
          ? 2
          : 3;
      return SizedBox(
        height: _kind == CatalogArtworkKind.poster ? 260 : 220,
        child: GridView.builder(
          key: Key('artwork-gallery-${_kind.name}'),
          itemCount: visible.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: _kind == CatalogArtworkKind.poster ? 2 / 3 : 16 / 9,
          ),
          itemBuilder: (context, index) {
            final candidate = visible[index];
            final selected = _selected?.filePath == candidate.filePath;
            return Semantics(
              button: true,
              selected: selected,
              label: '${_kind.name} ${index + 1}, ${_description(candidate)}',
              child: Material(
                clipBehavior: Clip.antiAlias,
                borderRadius: BorderRadius.circular(8),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: InkWell(
                  key: Key('artwork-candidate-${candidate.kind.name}-$index'),
                  onTap: _saving || _fetching
                      ? null
                      : () => setState(() {
                          _selections[_kind] = candidate;
                          _saveError = null;
                        }),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _ArtworkPreview(candidate: candidate),
                      if (selected)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 3,
                            ),
                          ),
                          child: const Align(
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.check_circle),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

class _ArtworkPreview extends StatelessWidget {
  const _ArtworkPreview({required this.candidate});
  final CatalogArtworkCandidate candidate;

  @override
  Widget build(BuildContext context) => Image.network(
    candidate.previewUrl,
    fit: BoxFit.contain,
    semanticLabel: '${candidate.kind.name} from TMDB',
    loadingBuilder: (context, child, progress) => progress == null
        ? child
        : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    errorBuilder: (_, _, _) =>
        const _ArtworkPlaceholder('Preview unavailable'),
  );
}

class _ArtworkPlaceholder extends StatelessWidget {
  const _ArtworkPlaceholder(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}
