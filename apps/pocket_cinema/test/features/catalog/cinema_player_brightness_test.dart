import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_domain/media_domain.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:pocket_cinema/features/catalog/catalog_library.dart';
import 'package:pocket_cinema/features/catalog/cinema_player.dart';
import 'package:pocket_cinema/features/risk_spike/playback_session_coordinator.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_controller.dart';

import '../risk_spike/playback_session_coordinator_test.dart'
    show directLease, FakePlaybackEngine, FakePlaybackEngineFactory;
import '../risk_spike/risk_spike_screen_test.dart' show filesAvailableState;

class _PlayerStorage implements LibraryStorageGateway {
  @override
  Future<AppResult<MediaSourceLease>> openPlaybackSource({
    required LibraryRootLocator root,
    required String storageKey,
    required PlaybackSourceStrategy strategy,
  }) async => const Success(directLease);

  @override
  Future<void> releasePlaybackSource(MediaSourceLease lease) async {}

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
  const brightnessKey = Key('player-brightness-slider');
  late List<MethodCall> controlsCalls;
  late double initialBrightness;
  Object? beginFailure;

  Iterable<MethodCall> callsTo(String method) =>
      controlsCalls.where((call) => call.method == method);

  setUp(() {
    controlsCalls = [];
    initialBrightness = 0.65;
    beginFailure = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(controlsChannel, (call) async {
          controlsCalls.add(call);
          if (call.method == 'beginWatching') {
            final failure = beginFailure;
            if (failure != null) throw failure;
            return initialBrightness;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(controlsChannel, null);
  });

  Future<RiskSpikeController> open(WidgetTester tester) async {
    final storage = _PlayerStorage();
    final controller = RiskSpikeController(
      storage: storage,
      probe: _UnusedProbe(),
      playback: PlaybackSessionCoordinator(
        engineFactory: FakePlaybackEngineFactory([
          FakePlaybackEngine(),
          FakePlaybackEngine(),
        ]),
        storage: storage,
      ),
      initialState: filesAvailableState,
    );
    final library = CatalogLibrary(controller);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      library.dispose();
      controller.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CinemaPlayer(
                    title: 'Movie',
                    controller: controller,
                    library: library,
                    video: CatalogVideo(filesAvailableState.entries.first),
                  ),
                ),
              ),
              child: const Text('Open player'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open player'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    return controller;
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets(
    'Brightness starts at the native level and adjusts from the dock',
    (tester) async {
      final controller = await open(tester);
      final sliderFinder = find.byKey(brightnessKey);
      final slider = tester.widget<Slider>(sliderFinder);
      expect(controller.playback.snapshot.isOpen, isTrue);
      expect(callsTo('beginWatching'), hasLength(1));
      expect(slider.value, initialBrightness);
      expect(slider.min, 0.01);
      expect(slider.max, 1);
      expect(slider.onChanged, isNotNull);
      expect(find.byTooltip('Brightness'), findsWidgets);
      expect(find.text('65%'), findsOneWidget);
      expect(find.semantics.byValue('Brightness 65 percent'), findsOneWidget);

      await tester.drag(sliderFinder, const Offset(40, 0));
      await tester.pump();
      final adjusted = tester.widget<Slider>(sliderFinder).value;
      expect(adjusted, greaterThan(initialBrightness));
      expect(adjusted, inInclusiveRange(0.01, 1.0));
      expect(callsTo('setBrightness'), isNotEmpty);
      expect(callsTo('setBrightness').last.arguments, adjusted);
      expect(find.text('${(adjusted * 100).round()}%'), findsOneWidget);
      expect(callsTo('beginWatching'), hasLength(1));
      await close(tester);
      expect(callsTo('endWatching'), hasLength(1));
    },
  );

  testWidgets('Holding the brightness slider keeps the dock visible', (
    tester,
  ) async {
    await open(tester);
    final sliderFinder = find.byKey(brightnessKey);
    final gesture = await tester.startGesture(tester.getCenter(sliderFinder));
    await tester.pump(const Duration(seconds: 1));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump(const Duration(seconds: 5));
    expect(sliderFinder, findsOneWidget);
    expect(callsTo('endWatching'), isEmpty);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 3900));
    expect(sliderFinder, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(sliderFinder, findsNothing);
    expect(callsTo('beginWatching'), hasLength(1));
    expect(callsTo('endWatching'), isEmpty);
    await close(tester);
  });

  testWidgets('Hiding or locking controls keeps the watching session active', (
    tester,
  ) async {
    final controller = await open(tester);
    await tester.tap(find.byTooltip('Hide controls'));
    await tester.pump();
    expect(find.byKey(brightnessKey), findsNothing);
    expect(callsTo('endWatching'), isEmpty);
    expect(controller.playback.snapshot.isOpen, isTrue);

    await tester.tapAt(const Offset(150, 150));
    await tester.pump();
    final hold = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('lock-player'))),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 2100));
    await hold.up();
    await tester.pump();
    expect(find.byKey(const Key('unlock-player')), findsOneWidget);
    expect(find.byKey(brightnessKey), findsNothing);
    expect(callsTo('beginWatching'), hasLength(1));
    expect(callsTo('endWatching'), isEmpty);
    expect(controller.playback.snapshot.isOpen, isTrue);

    await close(tester);
    expect(callsTo('endWatching'), hasLength(1));
  });

  testWidgets('Closing releases brightness and reopening reads it again', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('Back to library'));
    await tester.pumpAndSettle();
    expect(find.byType(CinemaPlayer), findsNothing);
    expect(callsTo('endWatching'), hasLength(1));

    initialBrightness = 0.37;
    await tester.tap(find.text('Open player'));
    await tester.pumpAndSettle();
    expect(callsTo('beginWatching'), hasLength(2));
    expect(callsTo('endWatching'), hasLength(1));
    expect(tester.widget<Slider>(find.byKey(brightnessKey)).value, 0.37);
    expect(find.text('37%'), findsOneWidget);
    await close(tester);
    expect(callsTo('endWatching'), hasLength(2));
  });

  for (final failure in <Object>[
    MissingPluginException('Brightness bridge unavailable'),
    PlatformException(code: 'BRIGHTNESS_UNAVAILABLE'),
  ]) {
    testWidgets('${failure.runtimeType} leaves playback usable', (
      tester,
    ) async {
      beginFailure = failure;
      final controller = await open(tester);
      expect(tester.takeException(), isNull);
      expect(controller.playback.snapshot.isOpen, isTrue);
      final sliderFinder = find.byKey(brightnessKey);
      if (sliderFinder.evaluate().isNotEmpty) {
        expect(tester.widget<Slider>(sliderFinder).onChanged, isNull);
      }
      expect(callsTo('setBrightness'), isEmpty);
      await tester.tap(find.byTooltip('Play or pause'));
      await tester.pump();
      expect(controller.playback.snapshot.isPlaying, isTrue);
      expect(tester.takeException(), isNull);
      await close(tester);
      expect(tester.takeException(), isNull);
    });
  }
}
