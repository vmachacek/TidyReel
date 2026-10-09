import 'dart:async';

import 'package:flutter/foundation.dart';

/// Runs maintenance only after presentation and a quiet interval. All timers
/// are passive: they never request a frame or rebuild the catalog.
final class BackgroundRefreshScheduler {
  BackgroundRefreshScheduler({
    required this.needsRefresh,
    required this.refresh,
    required this.defer,
  });

  static const startupGrace = Duration(seconds: 15);
  static const idleDelay = Duration(seconds: 5);
  static const dueCheckInterval = Duration(minutes: 1);

  final bool Function() needsRefresh;
  final Future<void> Function() refresh;
  final void Function() defer;
  Timer? _graceTimer, _idleTimer, _checkTimer;
  bool _available = false, _started = false, _gracePassed = false;
  bool _quiet = false, _running = false, _disposed = false;

  void setAvailable(bool available) {
    if (_disposed || _available == available) return;
    _available = available;
    if (!available) {
      _idleTimer?.cancel();
      _checkTimer?.cancel();
      _quiet = false;
      defer();
      return;
    }
    if (!_started) {
      _started = true;
      _graceTimer = Timer(startupGrace, () {
        _gracePassed = true;
        _tryRefresh();
      });
    }
    activity();
  }

  void activity() {
    if (_disposed) return;
    _quiet = false;
    _idleTimer?.cancel();
    _checkTimer?.cancel();
    defer();
    if (_available) {
      _idleTimer = Timer(idleDelay, () {
        _quiet = true;
        _tryRefresh();
      });
    }
  }

  void reset() {
    if (_disposed) return;
    setAvailable(false);
    _graceTimer?.cancel();
    _started = false;
    _gracePassed = false;
  }

  void _checkLater() {
    if (!_disposed && _available) {
      _checkTimer?.cancel();
      _checkTimer = Timer(dueCheckInterval, _tryRefresh);
    }
  }

  void _tryRefresh() {
    if (_disposed || !_available || !_gracePassed || !_quiet || _running) {
      return;
    }
    if (!needsRefresh()) {
      _checkLater();
      return;
    }
    _running = true;
    unawaited(_runRefresh());
  }

  Future<void> _runRefresh() async {
    try {
      await refresh();
    } on Object catch (error) {
      debugPrint('Background library refresh could not finish: $error');
    } finally {
      _running = false;
      // User activity arms its own idle timer. If cancellation took longer
      // than that timer, retry on a later check instead of spinning immediately.
      _checkLater();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _graceTimer?.cancel();
    _idleTimer?.cancel();
    _checkTimer?.cancel();
    defer();
  }
}
