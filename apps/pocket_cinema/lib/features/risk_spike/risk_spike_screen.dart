import 'package:flutter/material.dart';

import '../../app/app_brand.dart';

import '../../l10n/app_localizations.dart';
import 'risk_spike_controller.dart';
import 'widgets/failure_panel.dart';
import 'widgets/media_list.dart';
import 'widgets/player_panel.dart';
import 'widgets/probe_panel.dart';
import 'widgets/root_panel.dart';
import 'widgets/scan_panel.dart';

final class RiskSpikeScreen extends StatelessWidget {
  const RiskSpikeScreen({
    required this.controller,
    this.playbackSurface,
    super.key,
  });

  final RiskSpikeController controller;
  final Widget? playbackSurface;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final state = controller.state;
      final l10n = AppLocalizations.of(context);
      final leftPanels = <Widget>[
        RootPanel(state: state, controller: controller),
        ScanPanel(state: state, controller: controller),
        MediaList(state: state, controller: controller),
      ];
      final rightPanels = <Widget>[
        if (state.failure != null)
          FailurePanel(failure: state.failure!, controller: controller),
        ProbePanel(state: state, controller: controller),
        PlayerPanel(
          state: state,
          controller: controller,
          playbackSurface: playbackSurface,
        ),
      ];

      return Scaffold(
        appBar: AppBar(
          toolbarHeight: 72,
          titleSpacing: 20,
          title: AppBrand(title: l10n.appTitle),
          actions: [
            TextButton.icon(
              key: const Key('diagnostics-home-button'),
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
              icon: const Icon(Icons.home_outlined),
              label: const Text('Home'),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    child: Text(
                      l10n.diagnosticBuild,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 600) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _spaced([...leftPanels, ...rightPanels]),
                  ),
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 16, 12, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _spaced(leftPanels),
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(12, 16, 24, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _spaced(rightPanels),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}

List<Widget> _spaced(List<Widget> children) => [
  for (var index = 0; index < children.length; index++) ...[
    if (index > 0) const SizedBox(height: 16),
    children[index],
  ],
];
