import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../risk_spike_controller.dart';
import '../risk_spike_state.dart';

final class PlayerPanel extends StatelessWidget {
  const PlayerPanel({
    required this.state,
    required this.controller,
    this.playbackSurface,
    super.key,
  });

  final RiskSpikeState state;
  final RiskSpikeController controller;
  final Widget? playbackSurface;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final playback = state.playbackSnapshot;
    final isOpening = state.phase == RiskSpikePhase.openingPlayback;
    final status = isOpening
        ? l10n.openingPlayback
        : playback.isPlaying
        ? l10n.playerPlaying
        : state.selectedFile == null
        ? l10n.playerIdle
        : l10n.playerReady;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.playerSectionTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: ColoredBox(
                  color: Colors.black,
                  child: playback.isOpen && playbackSurface != null
                      ? playbackSurface!
                      : Center(
                          child: Icon(
                            playback.isOpen
                                ? Icons.play_circle_outline
                                : Icons.movie_filter_outlined,
                            size: 48,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(status),
            if (state.subtitleWarning != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.tertiaryContainer
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.subtitles_off_outlined),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_subtitleMessage(l10n, state))),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!playback.isOpen)
                  FilledButton.icon(
                    key: const Key('play-button'),
                    onPressed: state.selectedFile == null || isOpening
                        ? null
                        : controller.playSelected,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(l10n.play),
                  )
                else
                  FilledButton.icon(
                    key: const Key('pause-button'),
                    onPressed: controller.togglePlayPause,
                    icon: Icon(
                      playback.isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                    label: Text(playback.isPlaying ? l10n.pause : l10n.play),
                  ),
                IconButton.outlined(
                  key: const Key('rewind-10-button'),
                  onPressed: playback.isOpen
                      ? () => controller.seekBy(const Duration(seconds: -10))
                      : null,
                  tooltip: l10n.rewindTen,
                  icon: const Icon(Icons.replay_10),
                ),
                IconButton.outlined(
                  key: const Key('seek-start-button'),
                  onPressed: playback.isOpen ? controller.seekToStart : null,
                  tooltip: l10n.seekStart,
                  icon: const Icon(Icons.skip_previous),
                ),
                IconButton.outlined(
                  key: const Key('forward-10-button'),
                  onPressed: playback.isOpen
                      ? () => controller.seekBy(const Duration(seconds: 10))
                      : null,
                  tooltip: l10n.forwardTen,
                  icon: const Icon(Icons.forward_10),
                ),
                if (playback.isOpen)
                  OutlinedButton.icon(
                    key: const Key('close-player-button'),
                    onPressed: controller.closePlayer,
                    icon: const Icon(Icons.close),
                    label: Text(l10n.closePlayer),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _subtitleMessage(AppLocalizations l10n, RiskSpikeState state) =>
    state.subtitleWarning?.code == 'SMALL_FILE_LIMIT_EXCEEDED' ||
        state.subtitleWarning?.code == 'EXTERNAL_SUBTITLE_TOO_LARGE'
    ? l10n.subtitleTooLarge
    : l10n.externalSubtitleFailed;
