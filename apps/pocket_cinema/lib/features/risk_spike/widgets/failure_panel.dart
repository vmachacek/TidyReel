import 'package:flutter/material.dart';
import 'package:media_domain/media_domain.dart';

import '../../../l10n/app_localizations.dart';
import '../risk_spike_controller.dart';

final class FailurePanel extends StatelessWidget {
  const FailurePanel({
    required this.failure,
    required this.controller,
    super.key,
  });

  final AppFailure failure;
  final RiskSpikeController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.failureSectionTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(_failureMessage(l10n, failure)),
            const SizedBox(height: 18),
            if (controller.state.canRepairRoot)
              Semantics(
                key: const Key('repair-root-button'),
                container: true,
                excludeSemantics: true,
                label: l10n.chooseFolderAgain,
                button: true,
                enabled: true,
                onTap: controller.repairRoot,
                child: FilledButton.icon(
                  onPressed: controller.repairRoot,
                  icon: const Icon(Icons.folder_open),
                  label: Text(l10n.chooseFolderAgain),
                ),
              )
            else if (controller.state.canRescan)
              FilledButton.icon(
                key: const Key('retry-scan-button'),
                onPressed: () => controller.scan(controller.state.root!),
                icon: const Icon(Icons.refresh),
                label: Text(l10n.retryScan),
              ),
          ],
        ),
      ),
    );
  }
}

String _failureMessage(AppLocalizations l10n, AppFailure failure) =>
    switch (failure.code) {
      'STORAGE_PERMISSION_REVOKED' => l10n.rootPermissionRevoked,
      'FILE_UNAVAILABLE' => l10n.fileUnavailable,
      'SCAN_FAILED' => l10n.scanFailed,
      'STORAGE_OPERATION_FAILED' => l10n.storageOperationFailed,
      'PROBE_FAILED' => l10n.probeFailed,
      'PROBE_UNSUPPORTED' => l10n.probeUnsupported,
      'PLAYBACK_SOURCE_FAILED' => l10n.playbackSourceFailed,
      'PLAYBACK_UNSUPPORTED' => l10n.playbackUnsupported,
      'PLAYBACK_CONTROL_FAILED' ||
      'PLAYBACK_SEEK_FAILED' => l10n.playbackControlFailed,
      _ => l10n.unknownFailure,
    };
