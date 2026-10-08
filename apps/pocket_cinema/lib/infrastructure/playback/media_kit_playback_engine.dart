import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:media_domain/media_domain.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_playback/media_playback.dart';

enum MediaKitOperation { initialize, open, play, pause, seek, subtitle, stop }

final class MediaKitPlaybackEngine implements PlaybackEngine {
  final StreamController<PlaybackEvent> _events =
      StreamController<PlaybackEvent>.broadcast(sync: true);
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];

  Player? _player;
  VideoController? _videoController;
  PlaybackSnapshot _current = const PlaybackSnapshot.closed();
  bool _disposed = false;

  Player? get player => _player;

  VideoController get videoController {
    final controller = _videoController;
    if (controller == null) {
      throw StateError('Playback has not been initialized.');
    }
    return controller;
  }

  @override
  PlaybackSnapshot get current => _current;

  @override
  Stream<PlaybackEvent> get events => _events.stream;

  @override
  Future<AppResult<void>> initialize() async {
    if (_disposed) {
      return FailureResult<void>(
        mapMediaKitFailure(
          StateError('Disposed player.'),
          operation: MediaKitOperation.initialize,
        ),
      );
    }
    if (_player != null) {
      return const Success<void>(null);
    }

    try {
      final player = Player();
      _player = player;
      _videoController = VideoController(player);
      _bindPlayerStreams(player);
      return const Success<void>(null);
    } on Object catch (error) {
      return FailureResult<void>(
        mapMediaKitFailure(error, operation: MediaKitOperation.initialize),
      );
    }
  }

  @override
  Future<AppResult<void>> open(PlaybackRequest request) => _run(
    MediaKitOperation.open,
    (player) => player.open(
      Media(
        request.sourceLease.sourceUri,
        start: request.startPosition > Duration.zero
            ? request.startPosition
            : null,
      ),
      play: request.autoplay,
    ),
    onSuccess: () => _setSnapshot(
      _current.copyWith(isOpen: true, isPlaying: request.autoplay),
    ),
  );

  @override
  Future<AppResult<void>> play() => _run(
    MediaKitOperation.play,
    (player) => player.play(),
    onSuccess: () => _updateSnapshot(isPlaying: true),
  );

  @override
  Future<AppResult<void>> pause() => _run(
    MediaKitOperation.pause,
    (player) => player.pause(),
    onSuccess: () => _updateSnapshot(isPlaying: false),
  );

  @override
  Future<AppResult<void>> seek(Duration position) => _run(
    MediaKitOperation.seek,
    (player) => player.seek(position),
    onSuccess: () => _updateSnapshot(position: position),
  );

  @override
  Future<AppResult<void>> attachSubtitleData(
    Uint8List bytes, {
    String? languageTag,
  }) => _run(
    MediaKitOperation.subtitle,
    (player) => player.setSubtitleTrack(
      SubtitleTrack.data(
        utf8.decode(bytes, allowMalformed: true),
        language: languageTag,
      ),
    ),
  );

  @override
  Future<AppResult<void>> stop() => _run(
    MediaKitOperation.stop,
    (player) => player.stop(),
    onSuccess: () => _setSnapshot(const PlaybackSnapshot.closed()),
  );

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    try {
      await _player?.dispose();
    } finally {
      _player = null;
      _videoController = null;
      _current = const PlaybackSnapshot.closed();
      await _events.close();
    }
  }

  void _bindPlayerStreams(Player player) {
    _subscriptions
      ..add(
        player.stream.playing.listen(
          (playing) => _updateSnapshot(isPlaying: playing),
        ),
      )
      ..add(
        player.stream.buffering.listen(
          (buffering) => _updateSnapshot(isBuffering: buffering),
        ),
      )
      ..add(
        player.stream.completed.listen(
          (completed) => _updateSnapshot(isCompleted: completed),
        ),
      )
      ..add(
        player.stream.position.listen(
          (position) => _setSnapshot(
            _current.copyWith(
              position: position,
              clearFailure: position > _current.position,
            ),
          ),
        ),
      )
      ..add(
        player.stream.duration.listen(
          (duration) => _updateSnapshot(duration: duration),
        ),
      )
      ..add(
        player.stream.log.listen((log) {
          // Decoder logs also report recoverable hardware fallback. Only the
          // player's terminal source-loading errors mean the file cannot play.
          if (!isTerminalMediaKitError(log)) return;
          final failure = mapMediaKitFailure(
            StateError(log.text),
            operation: MediaKitOperation.open,
          );
          _current = _current.copyWith(failure: failure);
          if (!_events.isClosed) {
            _events.add(PlaybackWarning(failure));
          }
        }),
      );
  }

  Future<AppResult<void>> _run(
    MediaKitOperation operation,
    Future<void> Function(Player player) action, {
    void Function()? onSuccess,
  }) async {
    final player = _player;
    if (_disposed || player == null) {
      return FailureResult<void>(
        mapMediaKitFailure(
          StateError('Player is unavailable.'),
          operation: operation,
        ),
      );
    }
    try {
      await action(player);
      onSuccess?.call();
      return const Success<void>(null);
    } on Object catch (error) {
      final failure = mapMediaKitFailure(error, operation: operation);
      if (!_events.isClosed) {
        _events.add(PlaybackWarning(failure));
      }
      return FailureResult<void>(failure);
    }
  }

  void _updateSnapshot({
    bool? isPlaying,
    bool? isBuffering,
    bool? isCompleted,
    Duration? position,
    Duration? duration,
  }) => _setSnapshot(
    _current.copyWith(
      isPlaying: isPlaying,
      isBuffering: isBuffering,
      isCompleted: isCompleted,
      position: position,
      duration: duration,
    ),
  );

  void _setSnapshot(PlaybackSnapshot snapshot) {
    _current = snapshot;
    if (!_events.isClosed) {
      _events.add(PlaybackSnapshotChanged(snapshot));
    }
  }
}

bool isTerminalMediaKitError(PlayerLog log) {
  if (log.level != 'error' || log.prefix != 'cplayer') return false;
  final message = log.text.toLowerCase();
  return message.contains('failed to open') ||
      message.contains('loading failed') ||
      message.contains('unrecognized file format') ||
      message.contains('nothing to play');
}

AppFailure mapMediaKitFailure(
  Object error, {
  required MediaKitOperation operation,
}) {
  final evidence = error.toString().toLowerCase();
  if (evidence.contains('unsupported') ||
      evidence.contains('unrecognized file format') ||
      evidence.contains('codec') ||
      evidence.contains('decoder')) {
    return const AppFailure(
      code: 'PLAYBACK_UNSUPPORTED',
      messageKey: 'playbackUnsupported',
      retryable: false,
      safeDetail: 'The media format or codec is not supported.',
    );
  }

  return switch (operation) {
    MediaKitOperation.initialize => const AppFailure(
      code: 'PLAYBACK_INITIALIZATION_FAILED',
      messageKey: 'playbackInitializationFailed',
      retryable: true,
      safeDetail: 'The playback engine could not be initialized.',
    ),
    MediaKitOperation.open => const AppFailure(
      code: 'PLAYBACK_SOURCE_FAILED',
      messageKey: 'playbackSourceFailed',
      retryable: true,
      safeDetail: 'The selected media source could not be opened.',
    ),
    MediaKitOperation.seek => const AppFailure(
      code: 'PLAYBACK_SEEK_FAILED',
      messageKey: 'playbackSeekFailed',
      retryable: true,
      safeDetail: 'Playback could not seek to the requested position.',
    ),
    MediaKitOperation.subtitle => const AppFailure(
      code: 'EXTERNAL_SUBTITLE_FAILED',
      messageKey: 'externalSubtitleFailed',
      retryable: true,
      safeDetail: 'The external subtitle could not be attached.',
    ),
    MediaKitOperation.play ||
    MediaKitOperation.pause ||
    MediaKitOperation.stop => const AppFailure(
      code: 'PLAYBACK_CONTROL_FAILED',
      messageKey: 'playbackControlFailed',
      retryable: true,
      safeDetail: 'The requested playback action could not be completed.',
    ),
  };
}
