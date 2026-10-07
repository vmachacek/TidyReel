import 'package:media_playback/media_playback.dart';

import 'media_kit_playback_engine.dart';

final class MediaKitPlaybackEngineFactory implements PlaybackEngineFactory {
  const MediaKitPlaybackEngineFactory();

  @override
  PlaybackEngine create() => MediaKitPlaybackEngine();
}
