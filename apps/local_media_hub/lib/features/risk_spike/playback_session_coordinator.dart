import 'dart:typed_data';

import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:media_playback/media_playback.dart';

abstract interface class PlaybackSession {
  PlaybackSnapshot get snapshot;

  Future<AppResult<void>> attachLease(MediaSourceLease lease);

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

  PlaybackEngine? get activeEngine => _engine;

  @override
  PlaybackSnapshot get snapshot =>
      _engine?.current ?? const PlaybackSnapshot.closed();

  @override
  Future<AppResult<void>> attachLease(MediaSourceLease lease) async {
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

      final opened = await engine.open(PlaybackRequest(sourceLease: lease));
      if (opened case FailureResult<void>(:final failure)) {
        await stop();
        return FailureResult<void>(failure);
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
  Future<void> handleLifecycleInactive() => stop();

  @override
  Future<void> stop() async {
    final engine = _engine;
    final lease = _lease;
    if (engine == null && lease == null) {
      return;
    }

    _engine = null;
    _lease = null;
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
  ) {
    final engine = _engine;
    if (engine == null) {
      return Future<AppResult<void>>.value(
        const FailureResult<void>(
          AppFailure(
            code: 'PLAYBACK_NOT_OPEN',
            messageKey: 'playbackNotOpen',
            retryable: true,
          ),
        ),
      );
    }
    return action(engine);
  }
}
