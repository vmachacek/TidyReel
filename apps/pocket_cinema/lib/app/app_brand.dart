import 'dart:async';

import 'package:flutter/material.dart';

import '../features/kill_switch/kill_switch_scope.dart';
import '../features/kill_switch/kill_switch_settings.dart';
import 'app_icon.dart';

class AppBrand extends StatefulWidget {
  const AppBrand({this.title = 'Pocket Cinema', super.key});
  final String title;

  @override
  State<AppBrand> createState() => _AppBrandState();
}

class _AppBrandState extends State<AppBrand> {
  Timer? _tapWindow;
  int _tapCount = 0;
  bool _settingsOpen = false;

  void _resetTaps() {
    _tapWindow?.cancel();
    _tapWindow = null;
    _tapCount = 0;
  }

  void _tap() {
    final controller = KillSwitchScope.maybeOf(context);
    if (controller == null || _settingsOpen) return;
    _tapWindow ??= Timer(const Duration(seconds: 2), _resetTaps);
    if (++_tapCount < 3) return;
    _resetTaps();
    _settingsOpen = true;
    unawaited(
      showKillSwitchSettings(context, controller).whenComplete(() {
        _settingsOpen = false;
      }),
    );
  }

  @override
  void dispose() {
    _resetTaps();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: KillSwitchScope.maybeOf(context) == null ? null : _tap,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AppIcon(),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFFFB4A3),
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
        ),
      ],
    ),
  );
}
