import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A finite cover flow, driven by Flutter's native drag and page-snap physics.
class JukeboxCarousel extends StatefulWidget {
  const JukeboxCarousel({
    required this.covers,
    required this.labels,
    required this.onSelected,
    this.onActivated,
    this.initialIndex = 0,
    super.key,
  }) : assert(covers.length == labels.length);

  final List<Widget> covers;
  final List<String> labels;
  final ValueChanged<int> onSelected;
  final ValueChanged<int>? onActivated;
  final int initialIndex;

  @override
  State<JukeboxCarousel> createState() => _JukeboxCarouselState();
}

class _JukeboxCarouselState extends State<JukeboxCarousel> {
  PageController? _controller;
  late int _selected = _bounded(widget.initialIndex);
  List<GlobalKey> _coverKeys = [];
  int? _pointer;
  Offset? _pointerStart;
  double _pointerTravel = 0;

  int _bounded(int index) =>
      widget.covers.isEmpty ? 0 : index.clamp(0, widget.covers.length - 1);

  @override
  void didUpdateWidget(JukeboxCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldLabel = oldWidget.labels.isEmpty
        ? null
        : oldWidget.labels[_selected.clamp(0, oldWidget.labels.length - 1)];
    final retained = oldLabel == null ? -1 : widget.labels.indexOf(oldLabel);
    final next = _bounded(retained < 0 ? _selected : retained);
    if (next != _selected || oldWidget.covers.length != widget.covers.length) {
      _selected = next;
      _retireController();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.covers.isNotEmpty) widget.onSelected(_selected);
      });
    }
  }

  void _retireController() {
    final previous = _controller;
    _controller = null;
    if (previous != null) {
      // The old PageView must detach before its controller is disposed.
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _select(int index) {
    final target = _bounded(index);
    final controller = _controller;
    if (widget.covers.isEmpty || controller == null || !controller.hasClients) {
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.jumpToPage(target);
    } else {
      unawaited(
        controller.animateToPage(
          target,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  void _changed(int index) {
    if (index == _selected) return;
    setState(() => _selected = _bounded(index));
    widget.onSelected(_selected);
  }

  void _activateSelected() {
    if (widget.covers.isNotEmpty && (_page - _selected).abs() < .01) {
      widget.onActivated?.call(_selected);
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _select(_selected - 1);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _select(_selected + 1);
    } else if (event.logicalKey == LogicalKeyboardKey.home) {
      _select(0);
    } else if (event.logicalKey == LogicalKeyboardKey.end) {
      _select(widget.covers.length - 1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _pointerDown(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _pointerStart = event.position;
    _pointerTravel = 0;
  }

  void _pointerMove(PointerMoveEvent event) {
    if (event.pointer == _pointer && _pointerStart != null) {
      _pointerTravel = math.max(
        _pointerTravel,
        (event.position - _pointerStart!).distance,
      );
    }
  }

  void _pointerUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _pointerStart = null;
    if (_pointerTravel > 8) return;
    final page = _page;
    final frontFirst = List<int>.generate(widget.covers.length, (i) => i)
      ..sort((a, b) => (a - page).abs().compareTo((b - page).abs()));
    for (final index in frontFirst) {
      final box = _coverKeys[index].currentContext?.findRenderObject();
      if (box is RenderBox &&
          box.hasSize &&
          (Offset.zero & box.size).contains(
            box.globalToLocal(event.position),
          )) {
        if (index == _selected && (page - index).abs() < .01) {
          _activateSelected();
        } else {
          _select(index);
        }
        return;
      }
    }
  }

  double get _page =>
      _controller?.hasClients == true &&
          _controller!.position.hasContentDimensions
      ? (_controller!.page ?? _selected.toDouble())
      : _selected.toDouble();

  @override
  Widget build(BuildContext context) {
    if (widget.covers.isEmpty) return const SizedBox.shrink();
    if (_coverKeys.length != widget.covers.length) {
      _coverKeys = List.generate(widget.covers.length, (_) => GlobalKey());
    }
    final last = widget.covers.length - 1;
    return Focus(
      onKeyEvent: _key,
      child: Semantics(
        label: 'Browse your library',
        hint: widget.onActivated == null
            ? null
            : 'Tap the centered cover to open details',
        onTap: widget.onActivated == null ? null : _activateSelected,
        value:
            '${_selected + 1} of ${widget.covers.length}: '
            '${widget.labels[_selected]}',
        increasedValue: _selected < last
            ? '${_selected + 2} of ${widget.covers.length}: '
                  '${widget.labels[_selected + 1]}'
            : null,
        decreasedValue: _selected > 0
            ? '$_selected of ${widget.covers.length}: '
                  '${widget.labels[_selected - 1]}'
            : null,
        onIncrease: _selected < last ? () => _select(_selected + 1) : null,
        onDecrease: _selected > 0 ? () => _select(_selected - 1) : null,
        child: Column(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final maxCoverSize = (MediaQuery.sizeOf(context).height * .36)
                    .clamp(160.0, 340.0);
                final coverSize = (width * (width < 600 ? .44 : .59)).clamp(
                  160.0,
                  maxCoverSize,
                );
                final spacing = coverSize * .60;
                final fraction = spacing / width;
                if (_controller == null ||
                    (_controller!.viewportFraction - fraction).abs() > .001) {
                  _retireController();
                  _controller = PageController(
                    initialPage: _selected,
                    viewportFraction: fraction,
                    keepPage: false,
                  );
                }
                final controller = _controller!;
                final height = coverSize + 60;
                return SizedBox(
                  height: height,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              colors: [
                                const Color(0xFFFF5A36).withValues(alpha: .18),
                                const Color(0xFFFF5A36).withValues(alpha: 0),
                              ],
                              radius: .7,
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Listener(
                          key: const Key('jukebox-stage'),
                          onPointerDown: _pointerDown,
                          onPointerMove: _pointerMove,
                          onPointerUp: _pointerUp,
                          onPointerCancel: (event) {
                            if (event.pointer == _pointer) {
                              _pointer = null;
                              _pointerStart = null;
                            }
                          },
                          child: Stack(
                            children: [
                              ScrollConfiguration(
                                behavior: ScrollConfiguration.of(context)
                                    .copyWith(
                                      dragDevices: {
                                        PointerDeviceKind.touch,
                                        PointerDeviceKind.mouse,
                                        PointerDeviceKind.stylus,
                                        PointerDeviceKind.invertedStylus,
                                        PointerDeviceKind.trackpad,
                                      },
                                      scrollbars: false,
                                      overscroll: false,
                                    ),
                                child: PageView.builder(
                                  controller: controller,
                                  physics: const ClampingScrollPhysics(),
                                  itemCount: widget.covers.length,
                                  onPageChanged: _changed,
                                  itemBuilder: (_, _) =>
                                      const SizedBox.expand(),
                                ),
                              ),
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: ExcludeSemantics(
                                    child: AnimatedBuilder(
                                      animation: controller,
                                      builder: (context, _) {
                                        final page = _page;
                                        // Draw nearby sleeves back to front;
                                        // distant titles do not build artwork.
                                        final indices =
                                            [
                                              for (
                                                var i = math.max(
                                                  0,
                                                  page.floor() - 5,
                                                );
                                                i <=
                                                    math.min(
                                                      last,
                                                      page.ceil() + 5,
                                                    );
                                                i++
                                              )
                                                i,
                                            ]..sort(
                                              (a, b) => (b - page)
                                                  .abs()
                                                  .compareTo((a - page).abs()),
                                            );
                                        return Stack(
                                          clipBehavior: Clip.hardEdge,
                                          children: [
                                            for (final index in indices)
                                              _cover(
                                                index,
                                                page,
                                                width,
                                                coverSize,
                                                spacing,
                                              ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: (height - 48) / 2,
                        child: _arrow(false, _selected > 0),
                      ),
                      Positioned(
                        right: 0,
                        top: (height - 48) / 2,
                        child: _arrow(true, _selected < last),
                      ),
                    ],
                  ),
                );
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.covers.length == 1
                      ? 'Only title'
                      : _selected == 0
                      ? 'Start of library'
                      : _selected == last
                      ? 'End of library'
                      : 'Flick to browse',
                  style: const TextStyle(
                    color: Color(0xFFAA8982),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  '${_selected + 1} / ${widget.covers.length}',
                  key: const Key('jukebox-position'),
                  style: const TextStyle(
                    color: Color(0xFFFFB4A3),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _arrow(bool next, bool enabled) => IconButton.filledTonal(
    key: Key(next ? 'jukebox-next' : 'jukebox-previous'),
    onPressed: enabled ? () => _select(_selected + (next ? 1 : -1)) : null,
    tooltip: next ? 'Next title' : 'Previous title',
    style: IconButton.styleFrom(
      backgroundColor: const Color(0xE60B0E16),
      disabledBackgroundColor: const Color(0x660B0E16),
      foregroundColor: const Color(0xFFE0E2ED),
      disabledForegroundColor: Colors.white24,
      side: const BorderSide(color: Color(0xFF32353D)),
    ),
    icon: Icon(next ? Icons.chevron_right : Icons.chevron_left),
  );

  Widget _cover(
    int index,
    double page,
    double width,
    double size,
    double spacing,
  ) {
    final offset = index - page;
    final distance = offset.abs();
    final turn = distance.clamp(0.0, 1.0);
    final scale = (1.03 - .23 * turn - .045 * math.max(0, distance - 1)).clamp(
      .66,
      1.03,
    );
    final sleeve = Matrix4.identity()
      ..setEntry(3, 2, .0012)
      ..rotateY(offset.sign * turn * .90)
      ..scaleByDouble(scale, scale, scale, 1);
    // Translate outside the perspective so distant covers keep a readable
    // face instead of converging to thin slivers at the stage edges.
    final x =
        offset.sign * (spacing * turn + size * .24 * math.max(0, distance - 1));
    final transform = Matrix4.translationValues(x, 0, 0)..multiply(sleeve);
    return Positioned(
      left: (width - size) / 2,
      top: 18,
      width: size,
      height: size,
      child: Transform(
        key: Key('jukebox-cover-$index'),
        alignment: Alignment.center,
        transform: transform,
        child: SizedBox(
          key: _coverKeys[index],
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Color.lerp(
                  const Color(0x99FFB4A3),
                  const Color(0xFF32353D),
                  turn,
                )!,
                width: 2 - turn,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF5A36)
                      .withValues(alpha: .22 * (1 - turn)),
                  blurRadius: 32,
                  offset: const Offset(0, 18),
                ),
                const BoxShadow(
                  color: Colors.black54,
                  blurRadius: 22,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Colors.black.withValues(
                      alpha: (distance * .17).clamp(0, .5),
                    ),
                    BlendMode.srcATop,
                  ),
                  child: widget.covers[index],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
