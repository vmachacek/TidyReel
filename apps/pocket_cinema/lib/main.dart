import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'app/pocket_cinema_app.dart';
import 'features/risk_spike/playback_session_coordinator.dart';
import 'features/risk_spike/risk_spike_controller.dart';
import 'infrastructure/android/android_media_probe.dart';
import 'infrastructure/android/android_storage_gateway.dart';
import 'infrastructure/android/pigeon_storage_platform_api.dart';
import 'infrastructure/playback/media_kit_playback_engine_factory.dart';
import 'infrastructure/playback/media_kit_playback_surface.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  MediaKit.ensureInitialized();
  final platformApi = PigeonStoragePlatformApi();
  final storage = AndroidStorageGateway(api: platformApi);
  final playback = PlaybackSessionCoordinator(
    engineFactory: const MediaKitPlaybackEngineFactory(),
    storage: storage,
  );
  final controller = RiskSpikeController(
    storage: storage,
    probe: AndroidMediaProbe(platformApi),
    playback: playback,
  );
  runApp(
    PocketCinemaApp(
      controller: controller,
      playbackSurface: MediaKitPlaybackSurface(session: playback),
    ),
  );
}
