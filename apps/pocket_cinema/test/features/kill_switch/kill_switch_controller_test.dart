import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_cinema/features/kill_switch/kill_switch_controller.dart';
import 'package:pocket_cinema/features/kill_switch/kill_switch_radio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'disabled default never requests Bluetooth permission or starts radio',
    () async {
      final radio = _Radio();
      final store = _Store();
      final control = KillSwitchController(store: store, radio: radio);
      addTearDown(control.dispose);
      await control.initialize();
      expect(control.ready, isTrue);
      expect(control.enabled, isFalse);
      expect(control.isLoading, isFalse);
      expect(radio.permissionRequests, 0);
      expect(radio.scanStarts, 0);
      expect(radio.broadcasts, isEmpty);
      expect(store.value, isNull);
    },
  );

  test(
    'phone broadcasts OFF then ON and remains interactive in background',
    () async {
      final radio = _Radio();
      final control = KillSwitchController(store: _Store(), radio: radio);
      addTearDown(control.dispose);
      await control.enable(isController: true);
      expect(radio.broadcasts, [false]);
      expect(control.broadcasting, isTrue);
      await control.setActive(true);
      expect(radio.broadcasts, [false, true]);
      expect(control.active, isTrue);
      expect(control.isLoading, isFalse);
      control.didChangeAppLifecycleState(AppLifecycleState.paused);
      await _flush();
      expect(radio.broadcastStops, 0);
      expect(control.broadcasting, isTrue);
      await control.disable();
      expect(control.enabled, isTrue);
      expect(control.error, contains('Turn off Pause viewing before'));
      await control.setActive(false);
      expect(radio.broadcasts.last, isFalse);
      await control.disable();
      expect(control.enabled, isFalse);
      expect(control.broadcasting, isFalse);
      expect(radio.broadcastStops, 1);
    },
  );

  test(
    'receiver saves loading latch before exposing it and OFF releases it',
    () async {
      final store = _Store();
      final radio = _Radio();
      final control = KillSwitchController(store: store, radio: radio);
      addTearDown(control.dispose);
      await control.enable(isController: false);
      radio.emit(true, 1);
      await _flush();
      expect(control.isLoading, isTrue);
      expect(jsonDecode(store.value!)['active'], isTrue);
      radio.emit(false, 2);
      await _flush();
      expect(control.isLoading, isFalse);
      expect(jsonDecode(store.value!)['active'], isFalse);
    },
  );

  test('latch survives restart without prompting and local recovery disables receive', () async {
    final store = _Store()..value = _preferences(active: true);
    final radio = _Radio();
    final control = KillSwitchController(store: store, radio: radio);
    addTearDown(control.dispose);
    await control.initialize();
    expect(control.isLoading, isTrue);
    expect(radio.permissionRequests, 0);
    expect(radio.scanStarts, 1);
    await control.restoreLocally();
    expect(control.isLoading, isFalse);
    expect(control.enabled, isFalse);
    expect(radio.scanning, isFalse);
    radio.emit(true, 5);
    await _flush();
    expect(control.isLoading, isFalse);
    expect(jsonDecode(store.value!)['enabled'], isFalse);
  });

  test(
    'receiver pause keeps latch, resume listens and re-enable accepts signals',
    () async {
      final radio = _Radio();
      final control = KillSwitchController(store: _Store(), radio: radio);
      addTearDown(control.dispose);
      await control.enable(isController: false);
      radio.emit(true, 1);
      await _flush();
      control.didChangeAppLifecycleState(AppLifecycleState.paused);
      await _flush();
      expect(radio.scanning, isFalse);
      expect(control.isLoading, isTrue);
      control.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await _flush();
      expect(radio.scanning, isTrue);
      await control.enable(isController: false);
      radio.emit(false, 2);
      await _flush();
      expect(control.isLoading, isFalse);
    },
  );

  test(
    'older and conflicting same-revision BLE signals do not change latch',
    () async {
      final radio = _Radio();
      final control = KillSwitchController(store: _Store(), radio: radio);
      addTearDown(control.dispose);
      await control.enable(isController: false);
      radio.emit(true, 4);
      await _flush();
      radio.emit(false, 3);
      radio.emit(false, 4);
      await _flush();
      expect(control.isLoading, isTrue);
      radio.emit(false, 5);
      await _flush();
      expect(control.isLoading, isFalse);
    },
  );

  test(
    'failed durable latch save stays visible and duplicate signal can retry',
    () async {
      final store = _Store();
      final radio = _Radio();
      final control = KillSwitchController(store: store, radio: radio);
      addTearDown(control.dispose);
      await control.enable(isController: false);
      store.fail = true;
      radio.emit(true, 1);
      await _flush();
      expect(control.isLoading, isFalse);
      expect(control.error, contains('storage unavailable'));
      store.fail = false;
      radio.emit(true, 1);
      await _flush();
      expect(control.isLoading, isTrue);
      store.fail = true;
      await control.restoreLocally();
      expect(control.isLoading, isTrue);
      expect(control.enabled, isTrue);
    },
  );

  test(
    'denied permission does not enable control and failed radio is retryable',
    () async {
      final radio = _Radio()..permissionsGranted = false;
      final control = KillSwitchController(store: _Store(), radio: radio);
      addTearDown(control.dispose);
      await control.enable(isController: false);
      expect(control.enabled, isFalse);
      expect(control.error, contains('nearby devices permission'));
      radio.permissionsGranted = true;
      radio.failStart = true;
      await control.enable(isController: false);
      expect(control.enabled, isTrue);
      expect(control.listening, isFalse);
      expect(control.error, contains('Bluetooth unavailable'));
      radio.failStart = false;
      await control.retry();
      expect(control.error, isNull);
      expect(control.listening, isTrue);
    },
  );

  test(
    'pause and resume during startup converge and dispose cleans late scanner',
    () async {
      final radio = _Radio()..startGate = Completer<void>();
      final control = KillSwitchController(
        store: _Store()..value = _preferences(active: true),
        radio: radio,
      );
      final initialization = control.initialize();
      await _flush();
      control.didChangeAppLifecycleState(AppLifecycleState.paused);
      control.didChangeAppLifecycleState(AppLifecycleState.resumed);
      radio.startGate!.complete();
      await initialization;
      await _flush();
      expect(control.listening, isTrue);
      expect(control.isLoading, isTrue);
      control.dispose();
      await _flush();
      expect(radio.scanning, isFalse);
      final lateRadio = _Radio()..startGate = Completer<void>();
      final late = KillSwitchController(
        store: _Store()..value = _preferences(active: false),
        radio: lateRadio,
      );
      final lateInitialization = late.initialize();
      await _flush();
      late.dispose();
      lateRadio.startGate!.complete();
      await lateInitialization;
      await _flush();
      expect(lateRadio.scanning, isFalse);
    },
  );

  test(
    'duplicate OFF from another nearby phone does not repeatedly override ON',
    () async {
      final radio = _Radio();
      final control = KillSwitchController(store: _Store(), radio: radio);
      addTearDown(control.dispose);
      await control.enable(isController: false);
      const idlePhone = KillSwitchSignal(
        active: false,
        sender: 'other',
        session: 'other',
        revision: 1,
      );
      radio.incoming.add(idlePhone);
      radio.emit(true, 1);
      await _flush();
      expect(control.isLoading, isTrue);
      radio.incoming.add(idlePhone);
      await _flush();
      expect(control.isLoading, isTrue);
      radio.emit(false, 2);
      await _flush();
      expect(control.isLoading, isFalse);
    },
  );

  test(
    'radio errors invalidate phone broadcasting and receiver scan status',
    () async {
      final phoneRadio = _Radio();
      final phone = KillSwitchController(store: _Store(), radio: phoneRadio);
      addTearDown(phone.dispose);
      await phone.enable(isController: true);
      await phone.setActive(true);
      phoneRadio.incoming.addError(StateError('Bluetooth was turned off'));
      await _flush();
      expect(phone.broadcasting, isFalse);
      expect(phone.error, contains('Bluetooth was turned off'));
      await phone.setActive(true);
      expect(phoneRadio.broadcasts, [false, true, true]);
      expect(phone.broadcasting, isTrue);
      final tabletRadio = _Radio();
      final tablet = KillSwitchController(store: _Store(), radio: tabletRadio);
      addTearDown(tablet.dispose);
      await tablet.enable(isController: false);
      tabletRadio.incoming.addError(StateError('Bluetooth was turned off'));
      await _flush();
      expect(tablet.listening, isFalse);
      tablet.didChangeAppLifecycleState(AppLifecycleState.paused);
      tablet.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await _flush();
      expect(tablet.listening, isTrue);
      expect(tabletRadio.scanStarts, 2);
    },
  );

  test(
    'signal received during disabling cannot persist a re-enabled receiver',
    () async {
      final store = _Store();
      final radio = _Radio();
      final control = KillSwitchController(store: store, radio: radio);
      addTearDown(control.dispose);
      await control.enable(isController: false);
      store.nextSaveGate = Completer<void>();
      final disabling = control.disable();
      await _flush();
      radio.emit(true, 1);
      await _flush();
      store.nextSaveGate!.complete();
      await disabling;
      await _flush();
      expect(control.enabled, isFalse);
      expect(jsonDecode(store.value!)['enabled'], isFalse);
    },
  );
}

String _preferences({required bool active}) => jsonEncode({
  'version': 1,
  'enabled': true,
  'isController': false,
  'active': active,
});

class _Store implements KillSwitchPreferencesStore {
  String? value;
  bool fail = false;
  Completer<void>? nextSaveGate;
  @override
  Future<String?> load() async => value;
  @override
  Future<void> save(String value) async {
    if (fail) throw StateError('storage unavailable');
    await nextSaveGate?.future;
    this.value = value;
  }
}

class _Radio implements KillSwitchRadio {
  final StreamController<KillSwitchSignal> incoming =
      StreamController<KillSwitchSignal>.broadcast();
  bool permissionsGranted = true;
  bool failStart = false;
  bool scanning = false;
  int permissionRequests = 0;
  int scanStarts = 0;
  int broadcastStops = 0;
  final List<bool> broadcasts = [];
  Completer<void>? startGate;
  @override
  Stream<KillSwitchSignal> get signals => incoming.stream;
  @override
  Future<bool> requestPermissions() async {
    permissionRequests++;
    return permissionsGranted;
  }

  @override
  Future<void> startReceiving() async {
    scanStarts++;
    if (failStart) throw StateError('Bluetooth unavailable');
    await startGate?.future;
    scanning = true;
  }

  @override
  Future<void> stopReceiving() async {
    scanning = false;
  }

  @override
  Future<void> broadcast(bool active) async {
    broadcasts.add(active);
  }

  @override
  Future<void> stopBroadcast() async {
    broadcastStops++;
  }

  void emit(bool active, int revision) => incoming.add(
    KillSwitchSignal(
      active: active,
      sender: 'phone',
      session: 'session',
      revision: revision,
    ),
  );
}

Future<void> _flush() async {
  for (var index = 0; index < 12; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}
