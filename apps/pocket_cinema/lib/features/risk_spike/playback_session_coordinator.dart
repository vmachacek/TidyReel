import 'dart:typed_data';

import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:media_playback/media_playback.dart';

abstract interface class PlaybackSession {
  PlaybackSnapshot get snapshot;

  Future<AppResult<void>> attachLease(
    MediaSourceLease lease, {
    Duration startPosition = Duration.zero,
  });

  Future<AppResult<void>> attachSubtitle(
    Uint8List bytes, {
    String? languageTag,
  });

  Future<AppResult<void>> play();

  Future<AppResult<void>> pause();

  Future<AppResult<void>> seek(Duration position);

  Future<void> handleLifecycleInactive();

  Future<void> stop();
}

final class PlaybackSessionCoordinator implements PlaybackSession {
  PlaybackSessionCoordinator({
    required this.engineFactory,
    required this.storage,
  });

  static const int maximumSubtitleBytes = 2 * 1024 * 1024;

  final PlaybackEngineFactory engineFactory;
  final LibraryStorageGateway storage;

  PlaybackEngine? _engine;
  MediaSourceLease? _lease;
  Future<void>? _lifecyclePause;
  AppFailure? _lifecycleFailure;
  bool _playbackBlocked = false;
  int _playbackBlockGeneration = 0;

  PlaybackEngine? get activeEngine => _engine;

  void setPlaybackBlocked(bool blocked) {
    if (_playbackBlocked == blocked) return;
    _playbackBlocked = blocked;
    if (blocked) _playbackBlockGeneration++;
  }

  @override
  PlaybackSnapshot get snapshot {
    final current = _engine?.current ?? const PlaybackSnapshot.closed();
    final failure = _lifecycleFailure;
    return failure == null ? current : current.copyWith(failure: failure);
  }

  @override
  Future<AppResult<void>> attachLease(
    MediaSourceLease lease, {
    Duration startPosition = Duration.zero,
    bool autoplay = true,
  }) async {
    final blockGeneration = _playbackBlockGeneration;
    await stop();

    final PlaybackEngine engine;
    try {
      engine = engineFactory.create();
    } on Object {
      await storage.releasePlaybackSource(lease);
      return const FailureResult<void>(
        AppFailure(
          code: 'PLAYBACK_INITIALIZATION_FAILED',
          messageKey: 'playbackInitializationFailed',
          retryable: true,
          safeDetail: 'The playback engine could not be created.',
        ),
      );
    }

    _engine = engine;
    _lease = lease;

    try {
      final initialized = await engine.initialize();
      if (initialized case FailureResult<void>(:final failure)) {
        await stop();
        return FailureResult<void>(failure);
      }

      final opened = await engine.open(
        PlaybackRequest(
          sourceLease: lease,
          startPosition: startPosition,
          autoplay:
              autoplay &&
              !_playbackBlocked &&
              blockGeneration == _playbackBlockGeneration,
        ),
      );
      if (opened case FailureResult<void>(:final failure)) {
        await stop();
        return FailureResult<void>(failure);
      }
      if (_playbackBlocked || blockGeneration != _playbackBlockGeneration) {
        final paused = await engine.pause();
        if (paused is FailureResult<void> || engine.current.isPlaying) {
          await stop();
        }
      }
      return const Success<void>(null);
    } on Object {
      await stop();
      return const FailureResult<void>(
        AppFailure(
          code: 'PLAYBACK_SOURCE_FAILED',
          messageKey: 'playbackSourceFailed',
          retryable: true,
          safeDetail: 'The selected media source could not be opened.',
        ),
      );
    }
  }

  @override
  Future<AppResult<void>> attachSubtitle(
    Uint8List bytes, {
    String? languageTag,
  }) async {
    final engine = _engine;
    if (engine == null || !engine.current.isOpen) {
      return const FailureResult<void>(
        AppFailure(
          code: 'PLAYBACK_NOT_OPEN',
          messageKey: 'playbackNotOpen',
          retryable: true,
        ),
      );
    }
    if (bytes.lengthInBytes > maximumSubtitleBytes) {
      return const FailureResult<void>(
        AppFailure(
          code: 'EXTERNAL_SUBTITLE_TOO_LARGE',
          messageKey: 'subtitleTooLarge',
          retryable: false,
          safeDetail: 'The external subtitle exceeds the safe size limit.',
        ),
      );
    }
    return engine.attachSubtitleData(bytes, languageTag: languageTag);
  }

  @override
  Future<AppResult<void>> play() => _runControl((engine) => engine.play());

  @override
  Future<AppResult<void>> pause() => _runControl((engine) => engine.pause());

  @override
  Future<AppResult<void>> seek(Duration position) =>
      _runControl((engine) => engine.seek(position));

  @override
  Future<void> handleLifecycleInactive() {
    final engine = _engine;
    if (engine == null || !engine.current.isOpen) {
      return Future<void>.value();
    }
    final pending = _lifecyclePause;
    if (pending != null) return pending;
    if (!engine.current.isPlaying) return Future<void>.value();

    // Android can report both inactive and paused for a single interruption.
    // Keep the source available so the mounted player can still play and seek.
    late final Future<void> operation;
    operation = _pauseForLifecycle(engine).whenComplete(() {
      if (identical(_lifecyclePause, operation)) _lifecyclePause = null;
    });
    _lifecyclePause = operation;
    return operation;
  }

  Future<void> _pauseForLifecycle(PlaybackEngine engine) async {
    final result = await engine.pause();
    if (!identical(_engine, engine)) return;
    _lifecycleFailure = switch (result) {
      FailureResult<void>(:final failure) => failure,
      Success<void>() => null,
    };
  }

  @override
  Future<void> stop() async {
    final engine = _engine;
    final lease = _lease;
    if (engine == null && lease == null) {
      return;
    }

    _engine = null;
    _lease = null;
    _lifecyclePause = null;
    _lifecycleFailure = null;
    try {
      if (engine != null) {
        try {
          await engine.stop();
        } finally {
          await engine.dispose();
        }
      }
    } finally {
      if (lease != null) {
        await storage.releasePlaybackSource(lease);
      }
    }
  }

  Future<AppResult<void>> _runControl(
    Future<AppResult<void>> Function(PlaybackEngine engine) action,
  ) async {
    final engine = _engine;
    if (engine == null) {
      return const FailureResult<void>(
        AppFailure(
          code: 'PLAYBACK_NOT_OPEN',
          messageKey: 'playbackNotOpen',
          retryable: true,
        ),
      );
    }
    final result = await action(engine);
    if (identical(_engine, engine) && result is Success<void>) {
      _lifecycleFailure = null;
    }
    return result;
  }
}
