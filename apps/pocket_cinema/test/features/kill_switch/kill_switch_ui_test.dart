import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_cinema/app/pocket_cinema_app.dart';
import 'package:pocket_cinema/features/catalog/catalog_library.dart';
import 'package:pocket_cinema/features/catalog/catalog_screen.dart';
import 'package:pocket_cinema/features/kill_switch/kill_switch_controller.dart';
import 'package:pocket_cinema/features/kill_switch/kill_switch_radio.dart';
import 'package:pocket_cinema/features/kill_switch/kill_switch_settings.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_screen.dart';
import 'package:pocket_cinema/features/risk_spike/risk_spike_state.dart';

import '../../support/catalog_discovery.dart';
import '../risk_spike/risk_spike_screen_test.dart' as fixtures;

class _MemoryStore implements KillSwitchPreferencesStore {
  _MemoryStore({bool phone = false, bool active = true, bool paired = true})
    : value = jsonEncode({
        'version': 1,
        'enabled': paired,
        'isController': phone,
        'active': active,
      });

  String? value;
  @override
  Future<String?> load() async => value;
  @override
  Future<void> save(String value) async => this.value = value;
}

class _SilentRadio implements KillSwitchRadio {
  final stream = StreamController<KillSwitchSignal>.broadcast(
    onCancel: () async {},
  );
  @override
  Stream<KillSwitchSignal> get signals => stream.stream;
  @override
  Future<bool> requestPermissions() async => true;
  @override
  Future<void> startReceiving() async {}
  @override
  Future<void> stopReceiving() async {}
  @override
  Future<void> broadcast(bool active) async {}
  @override
  Future<void> stopBroadcast() async {}
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(CatalogLibrary.channel, (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(CatalogLibrary.channel, null);
  });

  Future<KillSwitchController> open(
    WidgetTester tester, {
    bool phone = false,
    bool active = true,
    bool paired = true,
    RiskSpikeState state = const RiskSpikeState(),
  }) async {
    final radio = _SilentRadio();
    addTearDown(radio.stream.close);
    final control = KillSwitchController(
      store: _MemoryStore(phone: phone, active: active, paired: paired),
      radio: radio,
    );
    final fixture = fixtures.testApp(state: state) as MaterialApp;
    final diagnostics = (fixture.home! as MediaQuery).child as RiskSpikeScreen;
    await tester.pumpWidget(
      PocketCinemaApp(
        controller: diagnostics.controller,
        killSwitch: control,
        initializeOnStart: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return control;
  }

  Future<void> openHiddenSettings(WidgetTester tester) async {
    for (var tap = 0; tap < 3; tap++) {
      await tester.tap(find.text('Pocket Cinema'));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('screen-time pause is hidden until the third brand tap', (
    tester,
  ) async {
    await open(tester, paired: false, active: false);
    expect(find.byTooltip('Screen-time pause'), findsNothing);
    expect(find.byIcon(Icons.power_settings_new), findsNothing);
    expect(find.byType(KillSwitchSettings), findsNothing);

    await tester.tap(find.text('Pocket Cinema'));
    await tester.pump();
    expect(find.byType(KillSwitchSettings), findsNothing);
    await tester.tap(find.text('Pocket Cinema'));
    await tester.pump();
    expect(find.byType(KillSwitchSettings), findsNothing);
    await tester.tap(find.text('Pocket Cinema'));
    await tester.pumpAndSettle();
    expect(find.byType(KillSwitchSettings), findsOneWidget);

    Navigator.of(tester.element(find.byType(KillSwitchSettings))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pocket Cinema'));
    await tester.pump();
    expect(find.byType(KillSwitchSettings), findsNothing);
    await tester.tap(find.text('Pocket Cinema'));
    await tester.pump();
    expect(find.byType(KillSwitchSettings), findsNothing);
    await tester.tap(find.text('Pocket Cinema'));
    await tester.pumpAndSettle();
    expect(find.byType(KillSwitchSettings), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('brand tap sequence expires two seconds after its first tap', (
    tester,
  ) async {
    await open(tester, paired: false, active: false);
    await tester.tap(find.text('Pocket Cinema'));
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.tap(find.text('Pocket Cinema'));
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.tap(find.text('Pocket Cinema'));
    await tester.pump();
    expect(find.byType(KillSwitchSettings), findsNothing);

    await tester.tap(find.text('Pocket Cinema'));
    await tester.pump();
    expect(find.byType(KillSwitchSettings), findsNothing);
    await tester.tap(find.text('Pocket Cinema'));
    await tester.pumpAndSettle();
    expect(find.byType(KillSwitchSettings), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('library settings keep screen-time pause controls hidden', (
    tester,
  ) async {
    await open(tester, active: false, state: fixtures.filesAvailableState);
    await settleCatalog(tester);
    expect(find.byTooltip('Screen-time pause'), findsNothing);
    expect(find.byIcon(Icons.power_settings_new), findsNothing);
    await tester.tap(find.byTooltip('Library settings'));
    await tester.pumpAndSettle();
    expect(find.text('Library Settings'), findsOneWidget);
    expect(find.text('Rescan library'), findsOneWidget);
    expect(find.byType(KillSwitchSettings), findsNothing);
    expect(find.text('Screen-time pause'), findsNothing);
    expect(find.text('Disable nearby control'), findsNothing);
    Navigator.of(tester.element(find.text('Library Settings'))).pop();
    await tester.pumpAndSettle();
    await openHiddenSettings(tester);
    expect(find.byType(KillSwitchSettings), findsOneWidget);
    expect(find.text('Listening for nearby Bluetooth control'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('loading covers routes and sheets and blocks touch and Back', (
    tester,
  ) async {
    final control = await open(tester);
    expect(find.text('Loading…'), findsOneWidget);
    final navigator = Navigator.of(tester.element(find.byType(CatalogScreen)));
    var taps = 0;
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => taps++,
              child: const Text('Underlying route'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Underlying route'), warnIfMissed: false);
    await tester.pump();
    expect(taps, 0);
    expect(await navigator.maybePop(), isTrue);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Underlying route'), findsOneWidget);
    unawaited(
      showModalBottomSheet<void>(
        context: tester.element(find.text('Underlying route')),
        builder: (_) => const Text('Underlying sheet'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Loading…'), findsOneWidget);
    expect(await navigator.maybePop(), isTrue);
    await tester.pump();
    expect(find.text('Underlying sheet'), findsOneWidget);
    // SDK stream cancellation can await a future from outside the fake clock.
    await tester.runAsync(control.restoreLocally);
    await tester.pump();
    expect(control.busy, isFalse);
    expect(find.text('Loading…'), findsNothing);
    expect(find.text('Underlying sheet'), findsOneWidget);
    expect(await navigator.maybePop(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Underlying sheet'), findsNothing);
    expect(find.text('Underlying route'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('offline parent recovery requires a five-second hold', (
    tester,
  ) async {
    final control = await open(tester);
    expect(find.text('Parent recovery'), findsNothing);
    final short = await tester.startGesture(
      tester.getCenter(find.text('Loading…')),
    );
    await tester.pump(const Duration(seconds: 2));
    await short.up();
    await tester.pump();
    expect(find.text('Parent recovery'), findsNothing);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Loading…')),
    );
    await tester.pump(const Duration(seconds: 6));
    await gesture.up();
    await tester.pump();
    expect(find.text('Parent recovery'), findsOneWidget);
    await tester.tap(find.byKey(const Key('kill-switch-recover-button')));
    await tester.pump();
    await tester.pump();
    expect(control.isConfigured, isFalse);
    expect(find.text('Loading…'), findsNothing);
    expect(find.byKey(const Key('folder-onboarding')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'phone can activate and restore without connecting a media folder',
    (tester) async {
      final control = await open(tester, phone: true, active: false);
      await openHiddenSettings(tester);
      await tester.ensureVisible(find.byKey(const Key('kill-switch-mode')));
      await tester.tap(find.byKey(const Key('kill-switch-mode')));
      await tester.pumpAndSettle();
      expect(control.active, isTrue);
      expect(find.text('Loading…'), findsNothing);
      expect(find.text('Pause viewing'), findsOneWidget);
      await tester.tap(find.byKey(const Key('kill-switch-mode')));
      await tester.pumpAndSettle();
      expect(control.active, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('tablet enables nearby control without any pairing step', (
    tester,
  ) async {
    final control = await open(tester, paired: false, active: false);
    await openHiddenSettings(tester);
    await tester.tap(find.text('Tablet'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byKey(const Key('kill-switch-enable-button')));
    await tester.pumpAndSettle();
    expect(control.enabled, isTrue);
    expect(control.isController, isFalse);
    expect(control.listening, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
