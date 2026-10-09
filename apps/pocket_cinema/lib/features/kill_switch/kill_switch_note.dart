import 'package:flutter/material.dart';

/// Explains nearby screen-time control without exposing its hidden controls.
class KillSwitchNote extends StatelessWidget {
  const KillSwitchNote({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      key: const Key('kill-switch-info'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Screen-time breaks',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Screen-time pause helps parents curb kids’ viewing time by pausing Pocket Cinema on nearby tablets from their phone.',
        ),
        const SizedBox(height: 16),
        Semantics(
          key: const Key('kill-switch-info-graphic'),
          image: true,
          label: 'A parent’s phone sends a Bluetooth signal to a child’s tablet. Viewing pauses and the tablet shows Loading.',
          child: ExcludeSemantics(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _SignalGraphic(color: colors.primary),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'To set up, tap Pocket Cinema three times within two seconds on each device’s library screen. On your phone, choose My phone and enable phone control. On each tablet, choose Tablet and enable nearby control. Turn Bluetooth on and allow Android’s requested permissions.',
        ),
        const SizedBox(height: 12),
        const Text(
          'Turn on Pause viewing on your phone to pause videos and show Loading… on nearby enabled tablets. Your phone stays usable. Turn it off to restore the tablets; videos stay paused until Play is pressed.',
        ),
        const SizedBox(height: 12),
        const Text(
          'No Wi-Fi or pairing is needed. This controls Pocket Cinema only, so other apps remain available.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 8),
        const Text(
          'If your phone is unavailable, hold the Loading spinner for five seconds and choose Restore tablet. This also disables nearby control on that tablet.',
          key: Key('kill-switch-info-recovery'),
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}

class _SignalGraphic extends StatelessWidget {
  const _SignalGraphic({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final vertical =
          constraints.maxWidth < 280 &&
          MediaQuery.textScalerOf(context).scale(12) > 18;
      final phone = _Device(
        icon: Icons.smartphone,
        label: 'Parent’s phone',
        status: 'Pause viewing on',
        color: color,
      );
      final tablet = _Device(
        icon: Icons.tablet_android,
        label: 'Child’s tablet',
        status: 'Video paused\nLoading…',
        color: color,
        paused: true,
      );
      final signal = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bluetooth, color: color),
          const SizedBox(height: 4),
          const Text(
            'Bluetooth',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12),
          ),
          Icon(
            vertical ? Icons.arrow_downward : Icons.arrow_right_alt,
            color: color,
          ),
        ],
      );
      if (vertical) {
        return Column(
          children: [
            phone,
            const SizedBox(height: 12),
            signal,
            const SizedBox(height: 12),
            tablet,
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: phone),
          Expanded(child: signal),
          Expanded(child: tablet),
        ],
      );
    },
  );
}

class _Device extends StatelessWidget {
  const _Device({
    required this.icon,
    required this.label,
    required this.status,
    required this.color,
    this.paused = false,
  });

  final IconData icon;
  final String label, status;
  final Color color;
  final bool paused;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Stack(
        alignment: Alignment.center,
        children: [
          Icon(icon, size: 48, color: color),
          if (paused) Icon(Icons.pause, size: 20, color: color),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 4),
      Text(
        status,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12),
      ),
    ],
  );
}
