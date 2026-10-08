import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';

final class PlaybackRequest {
  const PlaybackRequest({
    required this.sourceLease,
    this.autoplay = true,
    this.startPosition = Duration.zero,
  });

  final MediaSourceLease sourceLease;
  final bool autoplay;
  final Duration startPosition;
}

final class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.isOpen,
    this.isPlaying = false,
    this.isBuffering = false,
    this.isCompleted = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.failure,
  });

  const PlaybackSnapshot.closed()
    : isOpen = false,
      isPlaying = false,
      isBuffering = false,
      isCompleted = false,
      position = Duration.zero,
      duration = Duration.zero,
      failure = null;

  final bool isOpen;
  final bool isPlaying;
  final bool isBuffering;
  final bool isCompleted;
  final Duration position;
  final Duration duration;
  final AppFailure? failure;

  PlaybackSnapshot copyWith({
    bool? isOpen,
    bool? isPlaying,
    bool? isBuffering,
    bool? isCompleted,
    Duration? position,
    Duration? duration,
    AppFailure? failure,
    bool clearFailure = false,
  }) => PlaybackSnapshot(
    isOpen: isOpen ?? this.isOpen,
    isPlaying: isPlaying ?? this.isPlaying,
    isBuffering: isBuffering ?? this.isBuffering,
    isCompleted: isCompleted ?? this.isCompleted,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    failure: clearFailure ? null : failure ?? this.failure,
  );
}

sealed class PlaybackEvent {
  const PlaybackEvent();
}

final class PlaybackSnapshotChanged extends PlaybackEvent {
  const PlaybackSnapshotChanged(this.snapshot);

  final PlaybackSnapshot snapshot;
}

final class PlaybackWarning extends PlaybackEvent {
  const PlaybackWarning(this.failure);

  final AppFailure failure;
}
