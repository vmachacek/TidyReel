import 'package:flutter/material.dart';

import 'catalog_library.dart';
import 'catalog_screen.dart' show VideoArtwork, coral, panel, peach;

class NextEpisodePrompt extends StatelessWidget {
  const NextEpisodePrompt({
    required this.video,
    required this.library,
    required this.secondsRemaining,
    required this.paused,
    required this.onPlay,
    required this.onCancel,
    required this.onTogglePlayback,
    super.key,
  });

  final CatalogVideo video;
  final CatalogLibrary library;
  final int secondsRemaining;
  final bool paused;
  final VoidCallback onPlay;
  final VoidCallback onCancel;
  final VoidCallback onTogglePlayback;

  @override
  Widget build(BuildContext context) => Material(
    color: panel,
    elevation: 8,
    borderRadius: BorderRadius.circular(8),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            fit: FlexFit.loose,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          width: 80,
                          height: 56,
                          child: VideoArtwork(
                            video: video,
                            library: library,
                            backdrop: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              video.episodeCode,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: peach,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              video.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Next episode in ${secondsRemaining}s',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (paused)
                              const Text(
                                'Paused',
                                style: TextStyle(color: peach, fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        key: const ValueKey('autoplay-pause'),
                        tooltip: 'Play or pause',
                        onPressed: onTogglePlayback,
                        color: Colors.white,
                        icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.end,
            children: [
              TextButton.icon(
                key: const ValueKey('autoplay-cancel'),
                onPressed: onCancel,
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
                icon: const Icon(Icons.close),
                label: const Text('Cancel'),
              ),
              FilledButton.icon(
                key: const ValueKey('autoplay-play-now'),
                onPressed: onPlay,
                style: FilledButton.styleFrom(
                  backgroundColor: coral,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play now'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
