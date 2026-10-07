import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_platform_storage/media_platform_storage.dart';
import 'package:pocket_cinema/features/catalog/catalog_library.dart';
import 'package:pocket_cinema/features/catalog/cinema_player.dart';
import 'package:pocket_cinema/features/catalog/hold_to_activate_button.dart';
import 'package:pocket_cinema/features/catalog/playback_stats_overlay.dart';
import 'package:pocket_cinema/features/risk_spike/playback_session_coordinator.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_controller.dart';

import '../risk_spike/playback_session_coordinator_test.dart'
    show FakeStorageGateway, FakePlaybackEngineFactory;
import '../risk_spike/risk_spike_screen_test.dart' show filesAvailableState;

class _UnusedProbe implements MediaProbe {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected probe');
}

void main() {
  const controlsChannel = MethodChannel('com.pocketcinema.app/player_controls');
  late List<MethodCall> controlsCalls;

  setUp(() {
    controlsCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(controlsChannel, (call) async {
          controlsCalls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(controlsChannel, null);
  });

  Future<void> open(WidgetTester tester) async {
    final storage = FakeStorageGateway();
    final controller = RiskSpikeController(
      storage: storage,
      probe: _UnusedProbe(),
      playback: PlaybackSessionCoordinator(
        engineFactory: FakePlaybackEngineFactory([]),
        storage: storage,
      ),
    );
    final library = CatalogLibrary(controller);
    addTearDown(() {
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
  }

  testWidgets(
    'Controls hide after inactivity and a video tap brings them back',
    (tester) async {
      await open(tester);
      expect(find.byKey(const Key('lock-player')), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.byKey(const Key('lock-player')), findsNothing);
      expect(find.byTooltip('Back to library'), findsNothing);
      expect(controlsCalls.map((call) => call.arguments), [false]);
      await tester.tapAt(const Offset(150, 150));
      await tester.pump();
      expect(find.byKey(const Key('lock-player')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Short taps cannot lock or unlock; locked player blocks taps and Back',
    (tester) async {
      await open(tester);
      final lock = find.byKey(const Key('lock-player'));
      await tester.tap(lock);
      await tester.pump();
      expect(find.byKey(const Key('unlock-player')), findsNothing);
      expect(controlsCalls.map((call) => call.arguments), [false]);
      final hold = await tester.startGesture(tester.getCenter(lock));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 2100));
      await hold.up();
      await tester.pump();
      expect(find.byKey(const Key('unlock-player')), findsOneWidget);
      expect(find.byType(IconButton), findsNothing);
      expect(find.byType(PlaybackStatsOverlay), findsNothing);
      expect(controlsCalls.map((call) => call.method), [
        'setLocked',
        'setLocked',
      ]);
      expect(controlsCalls.map((call) => call.arguments), [false, true]);
      await tester.tapAt(const Offset(150, 150));
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(CinemaPlayer), findsOneWidget);
      final unlock = find.byKey(const Key('unlock-player'));
      await tester.tap(unlock);
      await tester.pump();
      expect(unlock, findsOneWidget);
      expect(controlsCalls.map((call) => call.arguments), [false, true]);
      final release = await tester.startGesture(tester.getCenter(unlock));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 2100));
      await release.up();
      await tester.pump();
      expect(find.byKey(const Key('lock-player')), findsOneWidget);
      expect(find.byTooltip('Back to library'), findsOneWidget);
      expect(controlsCalls.map((call) => call.arguments), [false, true, false]);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Closing a locked player releases the native volume lock', (
    tester,
  ) async {
    await open(tester);
    final hold = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('lock-player'))),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 2100));
    await hold.up();
    await tester.pump();
    expect(controlsCalls.map((call) => call.arguments), [false, true]);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(controlsCalls.map((call) => call.arguments), [false, true, false]);

    await open(tester);
    expect(find.byKey(const Key('lock-player')), findsOneWidget);
    expect(controlsCalls.map((call) => call.arguments), [
      false,
      true,
      false,
      false,
    ]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Moving away cancels a hold', (tester) async {
    var activated = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.bottomLeft,
          child: HoldToActivateButton(
            label: 'Hold to lock',
            icon: Icons.lock,
            onActivate: () => activated++,
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldToActivateButton)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    final feedback = find.byKey(const Key('hold-progress'));
    expect(feedback, findsOneWidget);
    expect(tester.getRect(feedback).left, greaterThanOrEqualTo(16));
    expect(
      tester.getRect(feedback).bottom,
      lessThan(tester.getRect(find.byType(HoldToActivateButton)).top - 24),
    );
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump(const Duration(seconds: 3));
    expect(feedback, findsNothing);
    await gesture.up();
    expect(activated, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
