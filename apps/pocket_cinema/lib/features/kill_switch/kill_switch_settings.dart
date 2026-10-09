import 'dart:async';

import 'package:flutter/material.dart';

import 'kill_switch_controller.dart';

Future<void> showKillSwitchSettings(
  BuildContext context,
  KillSwitchController controller,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: KillSwitchSettings(controller: controller),
    ),
  ),
);

class KillSwitchSettings extends StatefulWidget {
  const KillSwitchSettings({required this.controller, super.key});

  final KillSwitchController controller;

  @override
  State<KillSwitchSettings> createState() => _KillSwitchSettingsState();
}

class _KillSwitchSettingsState extends State<KillSwitchSettings> {
  bool _phone = true;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final control = widget.controller;
      final available = control.ready && !control.busy;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Kill switch',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Use Bluetooth to make nearby Pocket Cinema apps appear stuck on Loading. No Wi-Fi or pairing needed.',
          ),
          const SizedBox(height: 16),
          if (!control.enabled) ...[
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.smartphone),
                  label: Text('My phone'),
                ),
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.tablet_android),
                  label: Text('Tablet'),
                ),
              ],
              selected: {_phone},
              onSelectionChanged: available
                  ? (values) => setState(() => _phone = values.single)
                  : null,
            ),
            const SizedBox(height: 12),
            Text(
              _phone
                  ? 'Control nearby tablets from this phone.'
                  : 'Allow this tablet to receive nearby kill switch signals.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('kill-switch-enable-button'),
              onPressed: available
                  ? () => control.enable(isController: _phone)
                  : null,
              icon: const Icon(Icons.bluetooth),
              label: Text(
                _phone ? 'Enable phone control' : 'Enable nearby control',
              ),
            ),
            const SizedBox(height: 8),
            const Text('Allow Nearby devices access when Android asks.'),
          ] else ...[
            if (control.isController) ...[
              SwitchListTile.adaptive(
                key: const Key('kill-switch-mode'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Kill switch mode'),
                subtitle: const Text(
                  'Your phone stays usable. Nearby enabled tablets show Loading and pause their video.',
                ),
                value: control.active,
                onChanged: available
                    ? (value) => unawaited(control.setActive(value))
                    : null,
              ),
              Text(
                !control.broadcasting
                    ? 'Bluetooth broadcast is unavailable'
                    : control.active
                    ? 'Broadcasting Loading mode over Bluetooth'
                    : 'Broadcasting normal mode over Bluetooth',
                key: const Key('kill-switch-radio-status'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Turn the mode off here to restore the tablets. Bluetooth range depends on distance and walls.',
              ),
            ] else ...[
              Text(
                control.listening
                    ? 'Listening for nearby Bluetooth control'
                    : 'Bluetooth listening is unavailable',
              ),
              const SizedBox(height: 8),
              const Text(
                'If the phone is unavailable, hold the Loading spinner for 5 seconds to restore this tablet.',
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: available ? control.disable : null,
              child: const Text('Disable nearby control'),
            ),
          ],
          if (control.error != null) ...[
            const SizedBox(height: 8),
            Text(
              control.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            if (control.enabled)
              TextButton(
                onPressed: available ? control.retry : null,
                child: const Text('Retry Bluetooth'),
              ),
          ],
        ],
      );
    },
  );
}
