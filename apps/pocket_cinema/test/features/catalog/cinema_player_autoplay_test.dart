import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:media_playback/media_playback.dart';
import 'package:pocket_cinema/features/catalog/catalog_library.dart';
import 'package:pocket_cinema/features/catalog/cinema_player.dart';
import 'package:pocket_cinema/features/risk_spike/playback_session_coordinator.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_controller.dart';
import 'package:pocket_cinema/l10n/app_localizations.dart';

import '../risk_spike/playback_session_coordinator_test.dart'
    show FakePlaybackEngineFactory;
import '../risk_spike/risk_spike_screen_test.dart' show filesAvailableState;

const _duration = Duration(minutes: 2);
const _prompt = Key('next-episode-prompt');
const _playNow = Key('autoplay-play-now');
const _cancel = Key('autoplay-cancel');
const _pause = Key('autoplay-pause');

class _AutoplayStorage implements LibraryStorageGateway {
  final openedKeys = <String>[];
  final historiesAtOpen = <Map<String, int>>[];
  final releases = <String>[];
  Map<String, int> Function()? readHistory;
  Completer<void>? openingGate;

  @override
  Future<AppResult<MediaSourceLease>> openPlaybackSource({
    required LibraryRootLocator root,
    required String storageKey,
    required PlaybackSourceStrategy strategy,
  }) async {
    openedKeys.add(storageKey);
    historiesAtOpen.add(readHistory?.call() ?? {});
    final sequence = openedKeys.length;
    if (sequence > 1) await openingGate?.future;
    return Success(
      MediaSourceLease(
        leaseId: 'lease-$sequence',
        sourceUri: 'content://test/video-$sequence',
        strategy: strategy,
      ),
    );
  }

  @override
  Future<void> releasePlaybackSource(MediaSourceLease lease) async {
    releases.add(lease.leaseId);
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

class _AutoplayEngine implements PlaybackEngine {
  PlaybackSnapshot snapshot = const PlaybackSnapshot.closed();
  PlaybackRequest? request;
  int playCalls = 0;
  int pauseCalls = 0;
  int disposals = 0;

  @override
  PlaybackSnapshot get current => snapshot;

  @override
  Stream<PlaybackEvent> get events => const Stream.empty();

  @override
  Future<AppResult<void>> initialize() async => const Success(null);

  @override
  Future<AppResult<void>> open(PlaybackRequest request) async {
    this.request = request;
    snapshot = PlaybackSnapshot(
      isOpen: true,
      isPlaying: request.autoplay,
      position: request.startPosition,
      duration: _duration,
    );
    return const Success(null);
  }

  @override
  Future<AppResult<void>> play() async {
    playCalls++;
    snapshot = snapshot.copyWith(isPlaying: true);
    return const Success(null);
  }

  @override
  Future<AppResult<void>> pause() async {
    pauseCalls++;
    snapshot = snapshot.copyWith(isPlaying: false);
    return const Success(null);
  }

  @override
  Future<AppResult<void>> seek(Duration position) async {
    snapshot = snapshot.copyWith(position: position, isCompleted: false);
    return const Success(null);
  }

  @override
  Future<AppResult<void>> attachSubtitleData(
    Uint8List bytes, {
    String? languageTag,
  }) async => const Success(null);

  @override
  Future<AppResult<void>> stop() async {
    snapshot = const PlaybackSnapshot.closed();
    return const Success(null);
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

class _Fixture {
  _Fixture({
    required this.tester,
    required this.controller,
    required this.library,
    required this.storage,
    required this.engines,
    required this.videos,
    required this.navigator,
  });

  final WidgetTester tester;
  final RiskSpikeController controller;
  final CatalogLibrary library;
  final _AutoplayStorage storage;
  final List<_AutoplayEngine> engines;
  final List<CatalogVideo> videos;
  final GlobalKey<NavigatorState> navigator;

  _AutoplayEngine get engine =>
      (controller.playback as PlaybackSessionCoordinator).activeEngine!
          as _AutoplayEngine;

  Future<void> poll() async {
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
  }

  Future<void> update({
    Duration? position,
    Duration? duration,
    bool? isPlaying,
    bool? isBuffering,
    bool? isCompleted,
    AppFailure? failure,
    bool clearFailure = false,
  }) async {
    engine.snapshot = engine.snapshot.copyWith(
      position: position,
      duration: duration,
      isPlaying: isPlaying,
      isBuffering: isBuffering,
      isCompleted: isCompleted,
      failure: failure,
      clearFailure: clearFailure,
    );
    controller.refreshPlaybackSnapshot();
    await poll();
  }
}

StorageEntrySnapshot _file(String name) => StorageEntrySnapshot(
  storageKey: name,
  parentStorageKey: 'test-folder',
  relativePath: name,
  displayName: name,
  isDirectory: false,
  mimeType: 'video/mp4',
  sizeBytes: 1024,
  modifiedAtUtc: DateTime.utc(2026),
  flags: const {StorageEntryFlag.supportsRead},
);

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

  Future<_Fixture> open(
    WidgetTester tester, {
    int currentIndex = 0,
    bool movies = false,
    int initialPosition = 0,
    int nextResume = 0,
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final storage = _AutoplayStorage();
    final engines = List.generate(3, (_) => _AutoplayEngine());
    final controller = RiskSpikeController(
      storage: storage,
      probe: _UnusedProbe(),
      playback: PlaybackSessionCoordinator(
        engineFactory: FakePlaybackEngineFactory(engines),
        storage: storage,
      ),
      initialState: filesAvailableState,
    );
    final library = CatalogLibrary(controller);
    await library.load();
    final videos = List.generate(
      3,
      (index) => CatalogVideo(
        _file(
          movies ? 'Movie.${index + 1}.mp4' : 'Test.Show.S01E0${index + 1}.mp4',
        ),
      ),
    );
    library.positions[videos[currentIndex].id] = initialPosition;
    if (currentIndex + 1 < videos.length) {
      library.positions[videos[currentIndex + 1].id] = nextResume;
      library.durations[videos[currentIndex + 1].id] = _duration.inSeconds;
    }
    storage.readHistory = () => Map.of(library.positions);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: ThemeData.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: const Scaffold(),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => CinemaPlayer(
          title: movies ? 'Movie' : 'Test Show',
          controller: controller,
          library: library,
          video: videos[currentIndex],
          queue: videos,
          playbackSurface: const ColoredBox(color: Colors.black),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      final gate = storage.openingGate;
      if (gate != null && !gate.isCompleted) gate.complete();
      storage.openingGate = null;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      library.dispose();
      controller.dispose();
    });
    return _Fixture(
      tester: tester,
      controller: controller,
      library: library,
      storage: storage,
      engines: engines,
      videos: videos,
      navigator: navigator,
    );
  }

  testWidgets(
    'countdown follows playback through pause, buffering and seeking',
    (tester) async {
      final fixture = await open(tester);
      await fixture.update(position: const Duration(milliseconds: 104200));
      expect(find.byKey(_prompt), findsNothing);
      await fixture.update(position: const Duration(milliseconds: 105010));
      expect(find.text('Next episode in 15s'), findsOneWidget);
      expect(find.text('Audio & Subs'), findsNothing);
      await tester.pump(const Duration(seconds: 20));
      expect(find.text('Next episode in 15s'), findsOneWidget);
      expect(fixture.storage.openedKeys, hasLength(1));

      await tester.tap(find.byKey(_pause));
      await tester.pump();
      expect(fixture.engine.pauseCalls, 1);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Next episode in 15s'), findsOneWidget);
      await tester.tap(find.byKey(_pause));
      await tester.pump();
      expect(fixture.engine.playCalls, 1);

      await fixture.update(
        position: const Duration(milliseconds: 106100),
        isBuffering: true,
      );
      expect(find.text('Next episode in 14s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 20));
      expect(find.text('Next episode in 14s'), findsOneWidget);
      await fixture.update(
        position: _duration,
        isPlaying: false,
        isCompleted: true,
      );
      expect(fixture.storage.openedKeys, hasLength(1));
      await fixture.update(
        position: const Duration(seconds: 90),
        isBuffering: false,
        isCompleted: false,
      );
      expect(find.byKey(_prompt), findsNothing);
      await fixture.update(position: const Duration(seconds: 110));
      expect(find.text('Next episode in 10s'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancel suppresses autoplay for the episode and manual next resets it',
    (tester) async {
      final fixture = await open(tester, initialPosition: 105);
      expect(find.byKey(_prompt), findsOneWidget);
      await tester.tap(find.byKey(_cancel));
      await tester.pump();
      expect(find.byKey(_prompt), findsNothing);
      expect(find.text('Audio & Subs'), findsOneWidget);
      await fixture.update(position: const Duration(seconds: 30));
      await fixture.update(position: const Duration(seconds: 115));
      expect(find.byKey(_prompt), findsNothing);
      await fixture.update(
        position: _duration,
        isCompleted: true,
        isPlaying: false,
      );
      expect(fixture.storage.openedKeys, hasLength(1));

      await tester.tap(find.byTooltip('Next Episode'));
      await tester.pumpAndSettle();
      expect(fixture.storage.openedKeys, [
        fixture.videos[0].id,
        fixture.videos[1].id,
      ]);
      await fixture.update(position: const Duration(seconds: 105));
      expect(find.byKey(_prompt), findsOneWidget);
      expect(find.text('Next episode in 15s'), findsOneWidget);
    },
  );

  testWidgets(
    'only completion advances, saves history first and opens next once',
    (tester) async {
      final fixture = await open(tester);
      await fixture.update(position: _duration);
      expect(fixture.storage.openedKeys, hasLength(1));
      final gate = Completer<void>();
      fixture.storage.openingGate = gate;
      await fixture.update(isCompleted: true, isPlaying: false);
      expect(fixture.storage.openedKeys, [
        fixture.videos[0].id,
        fixture.videos[1].id,
      ]);
      expect(fixture.storage.historiesAtOpen[1][fixture.videos[0].id], 120);
      expect(fixture.library.durations[fixture.videos[0].id], 120);
      await tester.pump(const Duration(seconds: 10));
      fixture.controller.refreshPlaybackSnapshot();
      await fixture.poll();
      expect(fixture.storage.openedKeys, hasLength(2));

      gate.complete();
      fixture.storage.openingGate = null;
      await tester.pumpAndSettle();
      expect(fixture.engine, same(fixture.engines[1]));
      expect(fixture.engine.request!.autoplay, isTrue);
      expect(fixture.engine.current.isPlaying, isTrue);
      expect(fixture.engine.current.position, Duration.zero);
      expect(fixture.engines[0].disposals, 1);
      expect(fixture.storage.releases, ['lease-1']);
      await tester.pump(const Duration(seconds: 10));
      expect(fixture.storage.openedKeys, hasLength(2));
      expect(fixture.library.positions[fixture.videos[0].id], 120);
    },
  );

  testWidgets('Play now records the current episode and resumes the next', (
    tester,
  ) async {
    final fixture = await open(tester, nextResume: 20);
    await fixture.update(position: const Duration(seconds: 112));
    await tester.tap(find.byKey(_playNow));
    await tester.pumpAndSettle();
    expect(fixture.storage.openedKeys, [
      fixture.videos[0].id,
      fixture.videos[1].id,
    ]);
    expect(fixture.storage.historiesAtOpen[1][fixture.videos[0].id], 112);
    expect(fixture.engine.request!.startPosition, const Duration(seconds: 20));
    expect(fixture.engine.current.isPlaying, isTrue);
    expect(find.byKey(_prompt), findsNothing);
    await fixture.poll();
    expect(fixture.storage.openedKeys, hasLength(2));
  });

  for (final movies in [false, true]) {
    testWidgets(
      movies
          ? 'movies do not display or trigger next episode autoplay'
          : 'final episode does not display or trigger autoplay',
      (tester) async {
        final fixture = await open(
          tester,
          movies: movies,
          currentIndex: movies ? 0 : 2,
        );
        await fixture.update(position: const Duration(seconds: 110));
        expect(find.byKey(_prompt), findsNothing);
        await fixture.update(
          position: _duration,
          isCompleted: true,
          isPlaying: false,
        );
        await tester.pump(const Duration(seconds: 20));
        expect(fixture.storage.openedKeys, hasLength(1));
        expect(find.byKey(_prompt), findsNothing);
      },
    );
  }

  testWidgets('completion waits until the player returns to the foreground', (
    tester,
  ) async {
    final fixture = await open(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await fixture.update(
      position: _duration,
      isCompleted: true,
      isPlaying: false,
    );
    await tester.pump(const Duration(seconds: 5));
    expect(fixture.storage.openedKeys, hasLength(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await fixture.poll();
    await tester.pumpAndSettle();
    expect(fixture.storage.openedKeys, hasLength(2));
  });

  testWidgets(
    'a covering route and playback failure prevent automatic transition',
    (tester) async {
      final fixture = await open(tester);
      fixture.navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Scaffold()),
      );
      await tester.pumpAndSettle();
      await fixture.update(
        position: _duration,
        isCompleted: true,
        isPlaying: false,
      );
      expect(fixture.storage.openedKeys, hasLength(1));
      await fixture.update(
        failure: const AppFailure(
          code: 'PLAYBACK_SOURCE_FAILED',
          messageKey: 'playbackSourceFailed',
          retryable: true,
        ),
      );
      fixture.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await fixture.poll();
      expect(fixture.storage.openedKeys, hasLength(1));
      await fixture.update(clearFailure: true);
      await tester.pumpAndSettle();
      expect(fixture.storage.openedKeys, hasLength(2));
    },
  );

  testWidgets('autoplay controls fit compact viewports with enlarged text', (
    tester,
  ) async {
    final fixture = await open(tester, textScaler: const TextScaler.linear(2));
    await fixture.update(position: const Duration(seconds: 105));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [const Size(640, 360), const Size(320, 640)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(find.byKey(_prompt), findsOneWidget);
      expect(find.text('Next episode in 15s'), findsOneWidget);
      final screen = Offset.zero & size;
      for (final key in [_playNow, _cancel, _pause]) {
        final rect = tester.getRect(find.byKey(key));
        expect(
          screen.contains(rect.topLeft),
          isTrue,
          reason: '$key starts outside $size: $rect',
        );
        expect(
          screen.contains(rect.bottomRight),
          isTrue,
          reason: '$key ends outside $size: $rect',
        );
        expect(find.byKey(key).hitTestable(), findsOneWidget);
      }
      final header = tester.getRect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text && (widget.data?.contains('S01E01') ?? false),
        ),
      );
      final prompt = tester.getRect(find.byKey(_prompt));
      expect(header.bottom <= prompt.top, isTrue);
      expect(tester.takeException(), isNull);
    }
  });
}
