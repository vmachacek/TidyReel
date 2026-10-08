import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'kill_switch_radio.dart';

/// Nearby control is opt-in. Receivers retain a durable loading latch when a
/// phone goes away; an OFF broadcast or local recovery releases it.
class KillSwitchController extends ChangeNotifier with WidgetsBindingObserver {
  KillSwitchController({
    KillSwitchPreferencesStore? store,
    KillSwitchRadio? radio,
  }) : _store = store ?? const PlatformKillSwitchPreferencesStore(),
       _radio = radio ?? PlatformKillSwitchRadio();

  final KillSwitchPreferencesStore _store;
  final KillSwitchRadio _radio;
  bool _enabled = false;
  bool _isController = false;
  bool _active = false;
  bool _ready = false;
  bool _busy = false;
  bool _disposed = false;
  bool _background = false;
  bool _observingLifecycle = false;
  bool _listening = false;
  bool _broadcasting = false;
  bool? _advertisedActive;
  String? _error;
  int _epoch = 0;
  int _receivingEpoch = -1;
  StreamSubscription<KillSwitchSignal>? _subscription;
  int _subscriptionEpoch = -1;
  final Map<String, (int, bool)> _seenRevisions = {};
  Future<void> _storeQueue = Future<void>.value();
  Future<void> _radioQueue = Future<void>.value();
  Future<void> _receiveQueue = Future<void>.value();
  Future<void>? _initialization;

  bool get enabled => _enabled;
  bool get isConfigured => _enabled;
  bool get isController => _isController;
  bool get active => _active;
  bool get isLoading => _enabled && !_isController && _active;
  bool get ready => _ready;
  bool get busy => _busy;
  bool get broadcasting => _broadcasting;
  bool get listening => _listening;
  String? get error => _error;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    _busy = true;
    _notify();
    try {
      final saved = await _store.load();
      if (_disposed) return;
      if (saved != null) {
        final preferences = jsonDecode(saved);
        if (preferences is! Map<String, dynamic> ||
            preferences['version'] != 1) {
          throw const FormatException(
            'Saved nearby control settings are invalid.',
          );
        }
        if (preferences['enabled'] != null) {
          if (preferences['enabled'] is! bool ||
              preferences['isController'] is! bool ||
              preferences['active'] is! bool) {
            throw const FormatException(
              'Saved nearby control settings are invalid.',
            );
          }
          _enabled = preferences['enabled'] as bool;
          _isController = preferences['isController'] as bool;
          _active = preferences['active'] as bool;
        }
      }
      WidgetsBinding.instance.addObserver(this);
      _observingLifecycle = true;
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      _background =
          lifecycle == AppLifecycleState.paused ||
          lifecycle == AppLifecycleState.detached;
      // Restoring an enabled installation never opens a permission prompt.
      if (_enabled) await _syncRadio();
    } catch (error) {
      _setError(error);
    } finally {
      _ready = true;
      _busy = false;
      _notify();
    }
  }

  Future<void> enable({required bool isController}) async {
    await initialize();
    if (_disposed || _busy) return;
    if (_enabled && _isController && _active && !isController) {
      _setError(
        StateError(
          'Turn Kill switch mode off before changing this phone’s role.',
        ),
      );
      return;
    }
    _busy = true;
    _error = null;
    _notify();
    try {
      if (!await _radio.requestPermissions()) {
        throw StateError(
          'Allow nearby devices permission to use Bluetooth control.',
        );
      }
      if (_disposed) return;
      final nextActive = _enabled && _isController == isController
          ? _active
          : false;
      await _savePreferences(
        enabled: true,
        isController: isController,
        active: nextActive,
      );
      if (_disposed) return;
      _epoch++;
      _seenRevisions.clear();
      _enabled = true;
      _isController = isController;
      _active = nextActive;
      await _syncRadio();
    } catch (error) {
      _setError(error);
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> disable() async {
    await initialize();
    if (_disposed || _busy) return;
    if (_enabled && _isController && _active) {
      _setError(
        StateError(
          'Turn Kill switch mode off before disabling nearby control.',
        ),
      );
      return;
    }
    _busy = true;
    _error = null;
    _notify();
    try {
      await _savePreferences(
        enabled: false,
        isController: _isController,
        active: false,
      );
      if (_disposed) return;
      _epoch++;
      _enabled = false;
      _active = false;
      _seenRevisions.clear();
      await _syncRadio();
    } catch (error) {
      _setError(error);
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> restoreLocally() => disable();

  Future<void> setActive(bool value) async {
    await initialize();
    if (_disposed || _busy) return;
    if (!_enabled || !_isController) {
      throw StateError('Enable this phone as the nearby controller first.');
    }
    _busy = true;
    _error = null;
    _notify();
    try {
      await _savePreferences(enabled: true, isController: true, active: value);
      if (_disposed) return;
      _active = value;
      await _syncRadio();
    } catch (error) {
      _setError(error);
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> retry() async {
    await initialize();
    if (_disposed || _busy || !_enabled) return;
    _busy = true;
    _error = null;
    _notify();
    try {
      await _queueRadio(() async {
        await _stopReceiving();
        await _stopBroadcast();
      });
      await _syncRadio();
    } catch (error) {
      _setError(error);
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> _syncRadio() => _queueRadio(() async {
    if (_disposed || !_enabled) {
      await _stopReceiving();
      await _stopBroadcast();
      return;
    }
    if (_isController) {
      if (_listening ||
          (_subscription != null && _subscriptionEpoch != _epoch)) {
        await _stopReceiving();
      }
      _subscribe(_epoch);
      if (_broadcasting && _advertisedActive == _active) return;
      _broadcasting = false;
      _advertisedActive = null;
      final epoch = _epoch;
      final advertisedActive = _active;
      await _radio.broadcast(advertisedActive);
      if (_disposed || epoch != _epoch || !_enabled || !_isController) {
        await _radio.stopBroadcast();
        return;
      }
      _broadcasting = true;
      _advertisedActive = advertisedActive;
      _notify();
      return;
    }
    await _stopBroadcast();
    if (_background) {
      await _stopReceiving();
      return;
    }
    if (_listening && _receivingEpoch == _epoch) return;
    if (_subscription != null) await _stopReceiving();
    final epoch = _epoch;
    _subscribe(epoch);
    try {
      await _radio.startReceiving();
      if (_disposed ||
          epoch != _epoch ||
          _background ||
          !_enabled ||
          _isController) {
        await _stopReceiving(force: true);
        return;
      }
      _listening = true;
      _receivingEpoch = epoch;
      _notify();
    } catch (_) {
      await _stopReceiving(force: true);
      rethrow;
    }
  });

  void _subscribe(int epoch) {
    if (_subscription != null) return;
    _subscriptionEpoch = epoch;
    _subscription ??= _radio.signals.listen(
      (signal) {
        _receiveQueue = _receiveQueue.then((_) => _receive(signal, epoch));
      },
      onError: (Object error) {
        if (_disposed || epoch != _epoch) return;
        _listening = false;
        _receivingEpoch = -1;
        _broadcasting = false;
        _advertisedActive = null;
        _setError(error);
      },
    );
  }

  Future<void> _receive(KillSwitchSignal signal, int epoch) async {
    if (_disposed ||
        _busy ||
        epoch != _epoch ||
        !_enabled ||
        _isController ||
        _background) {
      return;
    }
    if (signal.sender.isEmpty ||
        signal.session.isEmpty ||
        signal.revision < 0) {
      return;
    }
    final key = '${signal.sender}:${signal.session}';
    final previous = _seenRevisions[key];
    if (previous != null && signal.revision <= previous.$1) {
      return;
    }
    try {
      if (_active != signal.active) {
        await _savePreferences(
          enabled: true,
          isController: false,
          active: signal.active,
        );
        if (_disposed || epoch != _epoch || !_enabled || _isController) return;
        _active = signal.active;
      }
      if (_seenRevisions.length >= 64 && !_seenRevisions.containsKey(key)) {
        _seenRevisions.remove(_seenRevisions.keys.first);
      }
      _seenRevisions[key] = (signal.revision, signal.active);
      _notify();
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> _savePreferences({
    required bool enabled,
    required bool isController,
    required bool active,
  }) {
    final value = jsonEncode({
      'version': 1,
      'enabled': enabled,
      'isController': isController,
      'active': active,
    });
    final next = _storeQueue.then((_) => _store.save(value));
    _storeQueue = next.catchError((Object _) {});
    return next;
  }

  Future<void> _queueRadio(Future<void> Function() operation) {
    final next = _radioQueue.then((_) => operation());
    _radioQueue = next.catchError((Object _) {});
    return next;
  }

  Future<void> _stopReceiving({bool force = false}) async {
    final subscription = _subscription;
    _subscription = null;
    _subscriptionEpoch = -1;
    await subscription?.cancel();
    if (_listening || force) {
      _listening = false;
      _receivingEpoch = -1;
      await _radio.stopReceiving();
    }
  }

  Future<void> _stopBroadcast() async {
    if (!_broadcasting && _advertisedActive == null) return;
    _broadcasting = false;
    _advertisedActive = null;
    await _radio.stopBroadcast();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _background = true;
    } else if (state == AppLifecycleState.resumed) {
      _background = false;
    } else {
      return;
    }
    // Native advertisements remain alive while the phone is put away.
    if (_enabled && !_isController) {
      unawaited(_syncRadio().catchError((Object error) => _setError(error)));
    }
  }

  void _setError(Object error) {
    if (_disposed) return;
    if (error is PlatformException) {
      _error = error.message ?? 'Bluetooth control is unavailable.';
    } else if (error is StateError) {
      _error = error.message.toString();
    } else {
      _error = error.toString().replaceFirst(
        RegExp(r'^\w+(Exception|Error):\s*'),
        '',
      );
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    if (_observingLifecycle) WidgetsBinding.instance.removeObserver(this);
    unawaited(_syncRadio().catchError((Object _) {}));
    super.dispose();
  }
}
