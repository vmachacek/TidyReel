import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:media_playback/media_playback.dart';
import 'package:pocket_cinema/app/pocket_cinema_app.dart';
import 'package:pocket_cinema/features/catalog/catalog_library.dart';
import 'package:pocket_cinema/features/catalog/catalog_screen.dart';
import 'package:pocket_cinema/features/catalog/cinema_player.dart';
import 'package:pocket_cinema/features/risk_spike/playback_session_coordinator.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_controller.dart';

import '../../support/catalog_discovery.dart';
import '../risk_spike/playback_session_coordinator_test.dart'
    show directLease, FakePlaybackEngineFactory;
import '../risk_spike/risk_spike_screen_test.dart' show filesAvailableState;

class _PlayerStorage implements LibraryStorageGateway {
  int releases = 0;

  @override
  Future<AppResult<MediaSourceLease>> openPlaybackSource({
    required LibraryRootLocator root,
    required String storageKey,
    required PlaybackSourceStrategy strategy,
  }) async => const Success(directLease);

  @override
  Future<void> releasePlaybackSource(MediaSourceLease lease) async {
    releases++;
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

class _PlayerEngine implements PlaybackEngine {
  PlaybackSnapshot _current = const PlaybackSnapshot.closed();
  int disposals = 0;

  @override
  PlaybackSnapshot get current => _current;

  @override
  Stream<PlaybackEvent> get events => const Stream.empty();

  @override
  Future<AppResult<void>> initialize() async => const Success(null);

  @override
  Future<AppResult<void>> open(PlaybackRequest request) async {
    _current = PlaybackSnapshot(
      isOpen: true,
      isPlaying: request.autoplay,
      position: request.startPosition,
      duration: const Duration(minutes: 24),
    );
    return const Success(null);
  }

  @override
  Future<AppResult<void>> play() async {
    _current = _current.copyWith(isPlaying: true);
    return const Success(null);
  }

  @override
  Future<AppResult<void>> pause() async {
    _current = _current.copyWith(isPlaying: false);
    return const Success(null);
  }

  @override
  Future<AppResult<void>> seek(Duration position) async {
    _current = _current.copyWith(position: position);
    return const Success(null);
  }

  @override
  Future<AppResult<void>> attachSubtitleData(
    Uint8List bytes, {
    String? languageTag,
  }) async => const Success(null);

  @override
  Future<AppResult<void>> stop() async {
    _current = const PlaybackSnapshot.closed();
    return const Success(null);
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

void main() {
  const controlsChannel = MethodChannel('com.pocketcinema.app/player_controls');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(controlsChannel, (_) async => 0.65);
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
      _PlayerEngine engine,
      _PlayerStorage storage,
    })
  >
  open(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final storage = _PlayerStorage();
    final engine = _PlayerEngine();
    final controller = RiskSpikeController(
      storage: storage,
      probe: _UnusedProbe(),
      playback: PlaybackSessionCoordinator(
        engineFactory: FakePlaybackEngineFactory([engine]),
        storage: storage,
      ),
      initialState: filesAvailableState,
    );
    final library = CatalogLibrary(controller);
    addTearDown(library.dispose);
    final video = CatalogVideo(filesAvailableState.entries.first);
    library.positions[video.id] = 83;
    await tester.pumpWidget(
      PocketCinemaApp(controller: controller, initializeOnStart: false),
    );
    final navigator = Navigator.of(tester.element(find.byType(CatalogScreen)));
    // Cover the catalog first so this fixture tests lifecycle handling without
    // involving catalog rebuilds during the player route's initialization.
    navigator.push(MaterialPageRoute<void>(builder: (_) => const SizedBox()));
    await settleCatalog(tester);
    navigator.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => CinemaPlayer(
          title: 'Movie',
          controller: controller,
          library: library,
          video: video,
          playbackSurface: const ColoredBox(
            key: Key('test-video-surface'),
            color: Colors.black,
          ),
        ),
      ),
    );
    await settleCatalog(tester);
    return (controller: controller, engine: engine, storage: storage);
  }

  for (final background in [false, true]) {
    testWidgets(
      background
          ? 'Backgrounding and returning keeps the player usable at its position'
          : 'Opening and closing Quick Settings keeps the player usable',
      (tester) async {
        final fixture = await open(tester);
        expect(find.text('1:23 / 24:00'), findsOneWidget);
        expect(fixture.controller.state.playbackSnapshot.isPlaying, isTrue);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        if (background) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
        }
        await tester.pump();
        if (background) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
        }
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();

        expect(find.byType(CinemaPlayer), findsOneWidget);
        expect(find.byKey(const Key('test-video-surface')), findsOneWidget);
        expect(find.text('1:23 / 24:00'), findsOneWidget);
        expect(fixture.controller.state.playbackSnapshot.isOpen, isTrue);
        expect(fixture.controller.state.playbackSnapshot.isPlaying, isFalse);
        expect(fixture.engine.disposals, 0);
        expect(fixture.storage.releases, 0);
        expect(
          tester.widget<Slider>(find.byType(Slider).first).onChanged,
          isNotNull,
        );
        expect(
          tester
              .widget<TextButton>(
                find.widgetWithText(TextButton, 'Audio & Subs'),
              )
              .onPressed,
          isNotNull,
        );

        await tester.tap(find.byTooltip('Play or pause'));
        await tester.pump();
        expect(fixture.controller.state.playbackSnapshot.isPlaying, isTrue);
        await tester.tap(find.widgetWithIcon(IconButton, Icons.forward_10));
        await tester.pump();
        expect(find.text('1:33 / 24:00'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byTooltip('Back to library'));
        await settleCatalog(tester);
        expect(find.byType(CinemaPlayer), findsNothing);
        expect(fixture.engine.disposals, 1);
        expect(fixture.storage.releases, 1);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('Detaching still disposes the player and releases its source', (
    tester,
  ) async {
    final fixture = await open(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(fixture.controller.state.playbackSnapshot.isOpen, isFalse);
    expect(fixture.engine.disposals, 1);
    expect(fixture.storage.releases, 1);
    await tester.tap(find.byTooltip('Back to library'));
    await settleCatalog(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(fixture.engine.disposals, 1);
    expect(fixture.storage.releases, 1);
  });
}
