import 'package:flutter/material.dart';

/// A deliberate two-second hold, with feedback positioned clear of the thumb.
class HoldToActivateButton extends StatefulWidget {
  const HoldToActivateButton({
    required this.label,
    required this.icon,
    required this.onActivate,
    super.key,
  });
  final String label;
  final IconData icon;
  final VoidCallback onActivate;

  @override
  State<HoldToActivateButton> createState() => _HoldToActivateButtonState();
}

class _HoldToActivateButtonState extends State<HoldToActivateButton>
    with SingleTickerProviderStateMixin {
  final _link = LayerLink();
  OverlayEntry? _feedback;
  late final AnimationController _hold =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            _dismissFeedback();
            widget.onActivate();
          }
        });
  int? _pointer;
  Offset? _origin;

  void _showFeedback() {
    _dismissFeedback();
    final box = context.findRenderObject()! as RenderBox;
    final screen = MediaQuery.of(context);
    final width = (screen.size.width - screen.padding.horizontal - 32).clamp(
      0.0,
      190.0,
    );
    final buttonRight = box.localToGlobal(Offset.zero).dx + box.size.width;
    final panelRight = buttonRight.clamp(
      screen.padding.left + 16 + width,
      screen.size.width - screen.padding.right - 16,
    );
    _feedback = OverlayEntry(
      builder: (_) => Positioned(
        width: width,
        child: IgnorePointer(
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.topRight,
            followerAnchor: Alignment.bottomRight,
            offset: Offset(panelRight - buttonRight, -40),
            child: Material(
              color: const Color(0xF2181B24),
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: AnimatedBuilder(
                  animation: _hold,
                  builder: (_, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.label,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Text(
                            '${(_hold.value * 100).round()}%',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFFFB4A3),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        key: const Key('hold-progress'),
                        value: _hold.value,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                        color: const Color(0xFFFF5A36),
                        backgroundColor: Colors.white24,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_feedback!);
  }

  void _dismissFeedback() {
    _feedback?.remove();
    _feedback?.dispose();
    _feedback = null;
  }

  void _cancel() {
    if (!mounted) return;
    _pointer = null;
    _origin = null;
    _dismissFeedback();
    _hold.reset();
  }

  @override
  void dispose() {
    _pointer = null;
    _dismissFeedback();
    _hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CompositedTransformTarget(
    link: _link,
    child: Semantics(
      label: widget.label,
      button: true,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (_pointer != null) {
            _cancel();
            return;
          }
          _pointer = event.pointer;
          _origin = event.position;
          _showFeedback();
          _hold.forward(from: 0);
        },
        onPointerMove: (event) {
          if (event.pointer == _pointer &&
              (event.position - _origin!).distance > 18) {
            _cancel();
          }
        },
        onPointerUp: (event) {
          if (event.pointer == _pointer) _cancel();
        },
        onPointerCancel: (event) {
          if (event.pointer == _pointer) _cancel();
        },
        child: SizedBox(
          width: 52,
          height: 52,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: Color(0xCC181B24),
              shape: BoxShape.circle,
            ),
            child: Icon(widget.icon, color: Colors.white),
          ),
        ),
      ),
    ),
  );
}
