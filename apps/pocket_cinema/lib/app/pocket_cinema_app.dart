import 'dart:async';

import 'package:flutter/material.dart';

import '../features/kill_switch/kill_switch_controller.dart';
import '../features/kill_switch/kill_switch_gate.dart';
import '../features/kill_switch/kill_switch_scope.dart';
import '../features/risk_spike/risk_spike_controller.dart';
import '../features/catalog/catalog_screen.dart';
import '../l10n/app_localizations.dart';
import 'app_theme.dart';

final class PocketCinemaApp extends StatefulWidget {
  const PocketCinemaApp({
    required this.controller,
    this.playbackSurface,
    this.killSwitch,
    this.initializeOnStart = true,
    super.key,
  });

  final RiskSpikeController controller;
  final Widget? playbackSurface;
  final KillSwitchController? killSwitch;
  final bool initializeOnStart;

  @override
  State<PocketCinemaApp> createState() => _PocketCinemaAppState();
}

final class _PocketCinemaAppState extends State<PocketCinemaApp>
    with WidgetsBindingObserver {
  KillSwitchNavigatorObserver? _killSwitchObserver;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final killSwitch = widget.killSwitch;
    if (killSwitch != null) {
      _killSwitchObserver = KillSwitchNavigatorObserver(killSwitch);
      killSwitch.addListener(_killSwitchChanged);
      _killSwitchChanged();
      unawaited(killSwitch.initialize());
    }
    if (widget.initializeOnStart) {
      unawaited(widget.controller.initialize());
    }
  }

  void _killSwitchChanged() => widget.controller.setPlaybackBlocked(
    widget.killSwitch?.isLoading ?? false,
  );

  @override
  Future<bool> didPopRoute() async => widget.killSwitch?.isLoading ?? false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(widget.controller.handleLifecycleInactive());
    } else if (state == AppLifecycleState.detached) {
      unawaited(widget.controller.closePlayer());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.killSwitch?.removeListener(_killSwitchChanged);
    _killSwitchObserver?.dispose();
    widget.killSwitch?.dispose();
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
    theme: AppTheme.dark,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    navigatorObservers: [?_killSwitchObserver],
    builder: (context, child) {
      final killSwitch = widget.killSwitch;
      if (killSwitch == null) return child!;
      return KillSwitchScope(
        controller: killSwitch,
        child: KillSwitchGate(controller: killSwitch, child: child!),
      );
    },
    home: CatalogScreen(
      controller: widget.controller,
      playbackSurface: widget.playbackSurface,
    ),
  );
}
