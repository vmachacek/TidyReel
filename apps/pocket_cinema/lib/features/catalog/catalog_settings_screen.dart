import 'dart:async';

import 'package:flutter/material.dart';

import 'catalog_library.dart';
import 'catalog_metadata_settings.dart';

class CatalogSettingsScreen extends StatelessWidget {
  const CatalogSettingsScreen({
    required this.library,
    required this.openDiagnostics,
    super.key,
  });

  final CatalogLibrary library;
  final VoidCallback openDiagnostics;

  @override
  Widget build(BuildContext context) {
    final controller = library.controller;
    return Scaffold(
      key: const Key('library-settings-page'),
      appBar: AppBar(
        leading: BackButton(
          key: const Key('library-settings-back'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Library Settings'),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SingleChildScrollView(
              key: const Key('library-settings-scroll'),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListenableBuilder(
                    listenable: controller,
                    builder: (_, _) => Text(
                      controller.state.root?.displayName ??
                          'No folder connected',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      unawaited(controller.chooseRoot());
                    },
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Change media folder'),
                  ),
                  const SizedBox(height: 8),
                  ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) {
                      final state = controller.state;
                      final root = state.root;
                      return OutlinedButton.icon(
                        key: const Key('settings-rescan-library'),
                        onPressed: state.canRescan && root != null
                            ? () {
                                Navigator.of(context).pop();
                                unawaited(controller.scan(root));
                              }
                            : null,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Rescan library'),
                      );
                    },
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      openDiagnostics();
                    },
                    child: const Text('Open Diagnostics'),
                  ),
                  const Divider(height: 32),
                  const Text(
                    'Playback',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  ListenableBuilder(
                    listenable: library,
                    builder: (context, _) => SwitchListTile.adaptive(
                      key: const Key('lock-hardware-volume-buttons'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Lock hardware volume buttons'),
                      subtitle: const Text(
                        'When player controls are locked, also block the physical volume buttons. Turn off to keep volume buttons available.',
                      ),
                      value: library.lockHardwareVolumeButtons,
                      onChanged: (value) => unawaited(
                        library.setLockHardwareVolumeButtons(value),
                      ),
                    ),
                  ),
                  const Divider(height: 32),
                  CatalogMetadataSettings(library: library),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
