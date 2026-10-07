import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../risk_spike_controller.dart';
import '../risk_spike_state.dart';

final class ProbePanel extends StatelessWidget {
  const ProbePanel({required this.state, required this.controller, super.key});

  final RiskSpikeState state;
  final RiskSpikeController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final result = state.probeResult;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.probeSectionTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (state.selectedFile != null)
              Text(
                state.selectedFile!.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            if (result != null) ...[
              const SizedBox(height: 16),
              _DetailRow(
                label: l10n.durationLabel,
                value: _duration(result.duration) ?? l10n.notAvailable,
              ),
              _DetailRow(
                label: l10n.containerLabel,
                value: result.containerFormat ?? l10n.notAvailable,
              ),
              _DetailRow(
                label: l10n.resolutionLabel,
                value: result.width == null || result.height == null
                    ? l10n.notAvailable
                    : '${result.width} × ${result.height}',
              ),
              _DetailRow(
                label: l10n.videoCodecLabel,
                value: result.videoCodec ?? l10n.notAvailable,
              ),
              _DetailRow(
                label: l10n.audioCodecLabel,
                value: result.audioCodecSummary ?? l10n.notAvailable,
              ),
              _DetailRow(
                label: l10n.streamCountLabel,
                value: result.streamCount.toString(),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const Key('probe-button'),
              onPressed:
                  state.selectedFile == null ||
                      state.phase == RiskSpikePhase.probing
                  ? null
                  : controller.probeSelected,
              icon: const Icon(Icons.manage_search),
              label: Text(
                state.phase == RiskSpikePhase.probing
                    ? l10n.probingMedia
                    : l10n.runProbe,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String? _duration(Duration? duration) {
  if (duration == null) {
    return null;
  }
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

final class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
