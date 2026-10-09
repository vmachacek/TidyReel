import 'dart:async';

import 'package:flutter/material.dart';

import 'kill_switch_controller.dart';

class KillSwitchGate extends StatefulWidget {
  const KillSwitchGate({
    required this.controller,
    required this.child,
    super.key,
  });

  final KillSwitchController controller;
  final Widget child;

  @override
  State<KillSwitchGate> createState() => _KillSwitchGateState();
}

class _KillSwitchGateState extends State<KillSwitchGate> {
  Timer? _hold;
  bool _recovering = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_modeChanged);
  }

  void _modeChanged() {
    if (widget.controller.isLoading) return;
    _hold?.cancel();
    if (mounted) {
      setState(() {
        _recovering = false;
        _error = null;
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_modeChanged);
    _hold?.cancel();
    super.dispose();
  }

  void _beginHold() {
    _hold?.cancel();
    _hold = Timer(const Duration(seconds: 5), () {
      if (mounted && widget.controller.isLoading) {
        setState(() => _recovering = true);
      }
    });
  }

  Future<void> _recover() async {
    setState(() => _saving = true);
    await widget.controller.restoreLocally();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = widget.controller.error;
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final loading = widget.controller.isLoading;
      return Stack(
        fit: StackFit.expand,
        children: [
          ExcludeFocus(
            excluding: loading,
            child: ExcludeSemantics(
              excluding: loading,
              child: AbsorbPointer(absorbing: loading, child: widget.child),
            ),
          ),
          if (loading)
            Positioned.fill(
              child: Material(
                key: const Key('kill-switch-loading-screen'),
                color: Theme.of(context).scaffoldBackgroundColor,
                child: SafeArea(
                  child: Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (_) => _beginHold(),
                      onTapUp: (_) => _hold?.cancel(),
                      onTapCancel: () => _hold?.cancel(),
                      child: const Padding(
                        padding: EdgeInsets.all(40),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 24),
                            Text('Loading…', style: TextStyle(fontSize: 18)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (loading && _recovering)
            Positioned.fill(
              child: Material(
                color: Colors.black54,
                child: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.viewInsetsOf(context).bottom,
                      ),
                      child: AlertDialog(
                        title: const Text('Parent recovery'),
                        content: SizedBox(
                          width: 360,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Restore this tablet and turn off nearby control. You can enable it again in Screen-time pause settings.',
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 16),
                                Text(
                                  _error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: _saving
                                ? null
                                : () => setState(() => _recovering = false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            key: const Key('kill-switch-recover-button'),
                            onPressed: _saving ? null : _recover,
                            child: const Text('Restore tablet'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
