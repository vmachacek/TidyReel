import 'dart:async';

import 'package:flutter/material.dart';

import '../features/risk_spike/risk_spike_controller.dart';
import '../features/risk_spike/risk_spike_screen.dart';
import '../l10n/app_localizations.dart';
import 'app_theme.dart';

final class LocalMediaHubApp extends StatefulWidget {
  const LocalMediaHubApp({
    required this.controller,
    this.playbackSurface,
    this.initializeOnStart = true,
    super.key,
  });

  final RiskSpikeController controller;
  final Widget? playbackSurface;
  final bool initializeOnStart;

  @override
  State<LocalMediaHubApp> createState() => _LocalMediaHubAppState();
}

final class _LocalMediaHubAppState extends State<LocalMediaHubApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.initializeOnStart) {
      unawaited(widget.controller.initialize());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(widget.controller.handleLifecycleInactive());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    home: RiskSpikeScreen(
      controller: widget.controller,
      playbackSurface: widget.playbackSurface,
    ),
  );
}
