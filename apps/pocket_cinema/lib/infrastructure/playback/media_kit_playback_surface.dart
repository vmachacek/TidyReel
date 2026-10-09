import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../features/risk_spike/playback_session_coordinator.dart';
import 'media_kit_playback_engine.dart';

final class MediaKitPlaybackSurface extends StatelessWidget {
  const MediaKitPlaybackSurface({
    required this.session,
    this.wakelock = true,
    super.key,
  });

  final PlaybackSessionCoordinator session;
  final bool wakelock;

  @override
  Widget build(BuildContext context) {
    final engine = session.activeEngine;
    if (engine is! MediaKitPlaybackEngine) {
      return const SizedBox.expand();
    }
    final controller = engine.videoController;
    return Video(
      // Video binds its dimension streams in initState. Each episode gets a
      // new controller, so recreate the view instead of retaining old listeners.
      key: ObjectKey(controller),
      controller: controller,
      fit: BoxFit.contain,
      controls: NoVideoControls,
      wakelock: wakelock,
    );
  }
}
