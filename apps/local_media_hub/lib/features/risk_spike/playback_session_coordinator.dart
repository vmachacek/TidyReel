import 'dart:typed_data';

import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:media_playback/media_playback.dart';

final class PlaybackSessionCoordinator {
  PlaybackSessionCoordinator({
    required this.engineFactory,
    required this.storage,
  });

  static const int maximumSubtitleBytes = 2 * 1024 * 1024;

  final PlaybackEngineFactory engineFactory;
  final LibraryStorageGateway storage;

  PlaybackEngine? _engine;
  MediaSourceLease? _lease;

  PlaybackSnapshot get snapshot =>
      _engine?.current ?? const PlaybackSnapshot.closed();

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

  Future<void> handleLifecycleInactive() => stop();

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
}
