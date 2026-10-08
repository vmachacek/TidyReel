import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../risk_spike_controller.dart';
import '../risk_spike_state.dart';

final class ScanPanel extends StatelessWidget {
  const ScanPanel({required this.state, required this.controller, super.key});

  final RiskSpikeState state;
  final RiskSpikeController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final root = state.root;
    final status = switch (state.phase) {
      RiskSpikePhase.checkingGrant => l10n.checkingAccess,
      _ when state.canCancel => l10n.scanInProgress,
      RiskSpikePhase.enumerating => l10n.scanInProgress,
      RiskSpikePhase.cancelled => l10n.scanCancelled,
      _ when state.scanCompleted => l10n.scanComplete,
      _ => l10n.scanIdle,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.scanSectionTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(status),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CountChip(
                  label: l10n.discoveredLabel,
                  value: state.discoveredCount,
                ),
                _CountChip(label: l10n.videosLabel, value: state.videoCount),
                _CountChip(
                  label: l10n.subtitlesLabel,
                  value: state.subtitleCount,
                ),
                _CountChip(label: l10n.ignoredLabel, value: state.ignoredCount),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  key: const Key('scan-button'),
                  onPressed: !state.canRescan || root == null
                      ? null
                      : () => controller.scan(root),
                  icon: const Icon(Icons.radar),
                  label: Text(l10n.scanMedia),
                ),
                if (state.canCancel)
                  OutlinedButton.icon(
                    key: const Key('cancel-scan-button'),
                    onPressed: controller.cancelScan,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(l10n.cancelScan),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text('$label  $value'),
  );
}
