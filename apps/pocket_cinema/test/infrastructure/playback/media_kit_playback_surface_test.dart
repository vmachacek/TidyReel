import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_domain/media_domain.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:pocket_cinema/features/catalog/catalog_library.dart';
import 'package:pocket_cinema/features/catalog/cinema_player.dart';
import 'package:pocket_cinema/features/risk_spike/playback_session_coordinator.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_controller.dart';
import 'package:pocket_cinema/infrastructure/playback/media_kit_playback_engine.dart';
import 'package:pocket_cinema/infrastructure/playback/media_kit_playback_surface.dart';
import 'package:pocket_cinema/l10n/app_localizations.dart';

import '../../features/risk_spike/playback_session_coordinator_test.dart'
    show FakePlaybackEngineFactory;
import '../../features/risk_spike/risk_spike_screen_test.dart'
    show filesAvailableState;

const _duration = Duration(minutes: 2);

Future<void> _settleNativeFutures(WidgetTester tester) async {
  // Platform channels and real stream cancellation may complete outside the
  // test's fake clock. Allow their event-loop work to finish before pumping UI.
  await tester.runAsync(() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  });
}

// Use the real engine, surface and media_kit Video widget while replacing only
// the native decoder and texture bridge. In particular, Video's subscriptions
// to a player's dimension streams are exercised rather than imitated.
class _PlatformPlayer extends PlatformPlayer {
  _PlatformPlayer() : super(configuration: const PlayerConfiguration());

  int disposals = 0;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    final media = playable as Media;
    update(position: media.start ?? Duration.zero, playing: play);
    state = state.copyWith(duration: _duration);
    durationController.add(_duration);
  }

  void update({Duration? position, bool? playing, bool? completed}) {
    state = state.copyWith(
      position: position,
      playing: playing,
      completed: completed,
    );
    if (position != null) positionController.add(position);
    if (playing != null) playingController.add(playing);
    if (completed != null) completedController.add(completed);
  }

  void showFrame({int width = 1280, int height = 720}) {
    state = state.copyWith(width: width, height: height);
    widthController.add(width);
    heightController.add(height);
  }

  @override
  Future<void> stop() async {
    state = const PlayerState();
    playingController.add(false);
    widthController.add(null);
    heightController.add(null);
  }

  @override
  Future<void> play() async => update(playing: true);

  @override
  Future<void> pause() async => update(playing: false);

  @override
  Future<void> seek(Duration position) async => update(position: position);

  @override
  Future<void> dispose() async {
    disposals++;
    await super.dispose();
  }
}

class _PlatformVideoController extends PlatformVideoController {
  _PlatformVideoController(Player player, int textureId)
    : super(player, const VideoControllerConfiguration()) {
    id.value = textureId;
    rect.value = const Rect.fromLTWH(0, 0, 1280, 720);
  }

  @override
  Future<void> setSize({int? width, int? height}) async {}
}

class _VideoController implements VideoController {
  _VideoController(this.player, int textureId) {
    final output = _PlatformVideoController(player, textureId);
    platform.complete(output);
    notifier.value = output;
  }

  @override
  final Player player;

  @override
  final platform = Completer<PlatformVideoController>();

  @override
  final notifier = ValueNotifier<PlatformVideoController?>(null);

  @override
  final id = ValueNotifier<int?>(null);

  @override
  final rect = ValueNotifier<Rect?>(null);

  @override
  Future<void> setSize({int? width, int? height}) async {}

  @override
  Future<void> get waitUntilFirstFrameRendered async {}
}

class _Storage implements LibraryStorageGateway {
  final openedKeys = <String>[];
  final releasedIds = <String>[];

  @override
  Future<AppResult<MediaSourceLease>> openPlaybackSource({
    required LibraryRootLocator root,
    required String storageKey,
    required PlaybackSourceStrategy strategy,
  }) async {
    openedKeys.add(storageKey);
    return Success(
      MediaSourceLease(
        leaseId: 'lease-${openedKeys.length}',
        sourceUri: 'content://test/video-${openedKeys.length}',
        strategy: strategy,
      ),
    );
  }

  @override
  Future<void> releasePlaybackSource(MediaSourceLease lease) async {
    releasedIds.add(lease.leaseId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected storage call: ${invocation.memberName}');
}

class _UnusedProbe implements MediaProbe {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected probe call');
}

void main() {
  const controlsChannel = MethodChannel('com.pocketcinema.app/player_controls');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(controlsChannel, (call) async {
          return call.method == 'beginWatching' ? 0.65 : null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(CatalogLibrary.channel, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(controlsChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(CatalogLibrary.channel, null);
  });

  Future<
    ({
      RiskSpikeController controller,
      List<_PlatformPlayer> players,
      _Storage storage,
    })
  >
  openPlayer(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final storage = _Storage();
    final players = List.generate(2, (_) => _PlatformPlayer());
    final engines = List.generate(
      2,
      (index) => MediaKitPlaybackEngine(
        playerFactory: () => Player(platformPlayer: players[index]),
        videoControllerFactory: (player) => _VideoController(player, index + 1),
      ),
    );
    final session = PlaybackSessionCoordinator(
      engineFactory: FakePlaybackEngineFactory(engines),
      storage: storage,
    );
    final controller = RiskSpikeController(
      storage: storage,
      probe: _UnusedProbe(),
      playback: session,
      initialState: filesAvailableState,
    );
    final library = CatalogLibrary(controller);
    final videos = List.generate(
      2,
      (index) => CatalogVideo(
        StorageEntrySnapshot(
          storageKey: 'Test.Show.S01E0${index + 1}.mp4',
          parentStorageKey: 'test-folder',
          relativePath: 'Test.Show.S01E0${index + 1}.mp4',
          displayName: 'Test.Show.S01E0${index + 1}.mp4',
          isDirectory: false,
          mimeType: 'video/mp4',
          sizeBytes: 1024,
          modifiedAtUtc: DateTime.utc(2026),
          flags: const {StorageEntryFlag.supportsRead},
        ),
      ),
    );
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: ThemeData.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => CinemaPlayer(
          title: 'Test Show',
          controller: controller,
          library: library,
          video: videos[0],
          queue: videos,
          playbackSurface: MediaKitPlaybackSurface(session: session),
        ),
      ),
    );
    await tester.pumpAndSettle();
    players[0].showFrame();
    await tester.pump();
    await tester.pump();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      library.dispose();
      controller.dispose();
    });
    return (controller: controller, players: players, storage: storage);
  }

  for (final playNow in [true, false]) {
    testWidgets(
      playNow
          ? 'fullscreen Play now displays frames from the replacement player'
          : 'fullscreen completion displays frames from the replacement player',
      (tester) async {
        final fixture = await openPlayer(tester);
        expect(tester.widget<Texture>(find.byType(Texture)).textureId, 1);
        final firstVideoState = tester.state<VideoState>(find.byType(Video));
        expect(tester.widget<Video>(find.byType(Video)).wakelock, isFalse);

        await tester.tap(find.byTooltip('Fullscreen'));
        await _settleNativeFutures(tester);
        await tester.pumpAndSettle();
        fixture.players[0].update(position: const Duration(seconds: 110));
        await tester.pump();
        fixture.controller.refreshPlaybackSnapshot();
        await tester.pump();
        expect(find.byKey(const Key('next-episode-prompt')), findsOneWidget);

        if (playNow) {
          await tester.tap(find.byKey(const Key('autoplay-play-now')));
        } else {
          fixture.players[0].update(
            position: _duration,
            completed: true,
            playing: false,
          );
          await tester.pump(const Duration(milliseconds: 500));
        }
        await _settleNativeFutures(tester);
        await tester.pumpAndSettle();
        expect(fixture.storage.openedKeys, hasLength(2));
        expect(fixture.players[0].disposals, 1);
        expect(fixture.storage.releasedIds, ['lease-1']);
        expect(fixture.controller.state.playbackSnapshot.isPlaying, isTrue);

        // The previous decoder clears its dimensions during stop. The new
        // decoder announces frames only after the replacement view is mounted.
        if (playNow) {
          fixture.players[1].showFrame();
        } else {
          fixture.players[1].showFrame(width: 1920, height: 1080);
        }
        await tester.pump();
        await tester.pump();
        expect(find.byType(Texture), findsOneWidget);
        expect(tester.widget<Texture>(find.byType(Texture)).textureId, 2);
        expect(
          tester.state<VideoState>(find.byType(Video)),
          isNot(same(firstVideoState)),
        );
        expect(firstVideoState.mounted, isFalse);
        expect(find.byKey(const Key('next-episode-prompt')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('ordinary rebuilds keep the active video surface mounted', (
    tester,
  ) async {
    final fixture = await openPlayer(tester);
    final videoState = tester.state<VideoState>(find.byType(Video));
    await tester.tap(find.byTooltip('Play or pause'));
    await tester.pump();
    expect(fixture.controller.state.playbackSnapshot.isPlaying, isFalse);
    expect(tester.state<VideoState>(find.byType(Video)), same(videoState));
    expect(tester.widget<Texture>(find.byType(Texture)).textureId, 1);

    await tester.tap(find.byTooltip('Play or pause'));
    await tester.pump();
    fixture.players[0].update(position: const Duration(seconds: 20));
    await tester.pump();
    fixture.controller.refreshPlaybackSnapshot();
    await tester.pump();
    expect(tester.state<VideoState>(find.byType(Video)), same(videoState));
    expect(tester.widget<Texture>(find.byType(Texture)).textureId, 1);
    expect(fixture.players[0].disposals, 0);

    await tester.tap(find.byTooltip('Fullscreen'));
    await _settleNativeFutures(tester);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Fullscreen').hitTestable(), findsNothing);
    expect(tester.state<VideoState>(find.byType(Video)), same(videoState));
    await tester.tapAt(tester.getCenter(find.byType(CinemaPlayer)));
    await tester.pump();
    expect(find.byIcon(Icons.fullscreen_exit), findsOneWidget);
    await tester.tap(find.byTooltip('Fullscreen'));
    await _settleNativeFutures(tester);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.fullscreen), findsOneWidget);
    expect(tester.state<VideoState>(find.byType(Video)), same(videoState));
    expect(tester.widget<Texture>(find.byType(Texture)).textureId, 1);
    expect(tester.takeException(), isNull);
  });
}
