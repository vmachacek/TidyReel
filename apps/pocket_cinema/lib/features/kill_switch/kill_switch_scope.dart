import 'package:flutter/material.dart';

import 'kill_switch_controller.dart';

class KillSwitchScope extends InheritedWidget {
  const KillSwitchScope({
    required this.controller,
    required super.child,
    super.key,
  });

  final KillSwitchController controller;

  static KillSwitchController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KillSwitchScope>()?.controller;

  @override
  bool updateShouldNotify(KillSwitchScope oldWidget) =>
      controller != oldWidget.controller;
}

/// Registers with each route so Android Back, including predictive Back,
/// cannot dismiss routes underneath the loading screen.
class KillSwitchNavigatorObserver extends NavigatorObserver {
  KillSwitchNavigatorObserver(this.controller) {
    controller.addListener(_update);
    _update();
  }

  final KillSwitchController controller;
  final _LoadingPopEntry _entry = _LoadingPopEntry();
  final _routes = <ModalRoute<dynamic>>{};

  void _update() => _entry.canPopNotifier.value = !controller.isLoading;

  void _register(Route<dynamic>? route) {
    if (route is ModalRoute && _routes.add(route)) {
      route.registerPopEntry(_entry);
    }
  }

  void _unregister(Route<dynamic>? route) {
    if (route is ModalRoute && _routes.remove(route)) {
      route.unregisterPopEntry(_entry);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _register(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _unregister(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _unregister(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _unregister(oldRoute);
    _register(newRoute);
  }

  void dispose() {
    controller.removeListener(_update);
    for (final route in _routes) {
      route.unregisterPopEntry(_entry);
    }
    _routes.clear();
    _entry.canPopNotifier.dispose();
  }
}

class _LoadingPopEntry extends PopEntry<Object?> {
  @override
  final ValueNotifier<bool> canPopNotifier = ValueNotifier(true);

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {}
}
