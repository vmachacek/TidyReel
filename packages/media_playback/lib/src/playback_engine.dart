import 'dart:typed_data';

import 'package:media_domain/media_domain.dart';

import 'playback_models.dart';

abstract interface class PlaybackEngine {
  Stream<PlaybackEvent> get events;

  PlaybackSnapshot get current;

  Future<AppResult<void>> initialize();

  Future<AppResult<void>> open(PlaybackRequest request);

  Future<AppResult<void>> play();

  Future<AppResult<void>> pause();

  Future<AppResult<void>> seek(Duration position);

  Future<AppResult<void>> attachSubtitleData(
    Uint8List bytes, {
    String? languageTag,
  });

  Future<AppResult<void>> stop();

  Future<void> dispose();
}
