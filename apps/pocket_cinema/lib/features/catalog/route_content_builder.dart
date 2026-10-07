import 'package:flutter/material.dart';

/// Covered routes keep their existing content. Changes are read together when
/// the user returns, rather than rebuilding a media library behind playback.
class RouteContentBuilder extends StatefulWidget {
  const RouteContentBuilder({
    required this.animation,
    required this.builder,
    super.key,
  });
  final Listenable animation;
  final WidgetBuilder builder;

  @override
  State<RouteContentBuilder> createState() => _RouteContentBuilderState();
}

class _RouteContentBuilderState extends State<RouteContentBuilder> {
  Widget? _content;
  bool _current = true;

  @override
  void initState() {
    super.initState();
    widget.animation.addListener(_changed);
  }

  @override
  void didUpdateWidget(RouteContentBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeListener(_changed);
      widget.animation.addListener(_changed);
    }
  }

  void _changed() {
    if (_current) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    _current = ModalRoute.isCurrentOf(context) ?? true;
    if (!_current && _content != null) return _content!;
    return _content = widget.builder(context);
  }

  @override
  void dispose() {
    widget.animation.removeListener(_changed);
    super.dispose();
  }
}
