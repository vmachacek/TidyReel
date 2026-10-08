import 'package:flutter/material.dart';

/// The decorative brand mark, drawn as vectors at any display size.
class AppIcon extends StatelessWidget {
  const AppIcon({this.size = 32, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: const CustomPaint(painter: _AppIconPainter()),
  );
}

class _AppIconPainter extends CustomPainter {
  const _AppIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Coordinates match assets/branding/pocket_play.svg and Android's vectors.
    canvas.save();
    canvas.scale(size.width / 108, size.height / 108);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 108, 108),
        const Radius.circular(24),
      ),
      Paint()..color = const Color(0xFF10131B),
    );
    canvas.drawPath(
      Path()
        ..moveTo(26, 43)
        ..quadraticBezierTo(54, 27, 82, 43)
        ..lineTo(82, 57)
        ..lineTo(26, 57)
        ..close(),
      Paint()..color = const Color(0xFFD9472B),
    );
    canvas.drawPath(
      Path()
        ..moveTo(45, 25)
        ..cubicTo(42, 23, 40, 24, 40, 28)
        ..lineTo(40, 58)
        ..cubicTo(40, 61, 43, 62, 46, 60)
        ..lineTo(68, 47)
        ..cubicTo(71, 45, 71, 42, 68, 40)
        ..close(),
      Paint()..color = const Color(0xFFFFB4A3),
    );
    canvas.drawPath(
      Path()
        ..moveTo(26, 43)
        ..quadraticBezierTo(54, 61, 82, 43)
        ..lineTo(82, 65)
        ..cubicTo(82, 71, 79, 75, 74, 78)
        ..lineTo(60, 86)
        ..quadraticBezierTo(54, 89, 48, 86)
        ..lineTo(34, 78)
        ..cubicTo(29, 75, 26, 71, 26, 65)
        ..close(),
      Paint()..color = const Color(0xFFFF5A36),
    );
    canvas.drawPath(
      Path()
        ..moveTo(34, 55)
        ..lineTo(49, 62)
        ..quadraticBezierTo(54, 65, 59, 62)
        ..lineTo(74, 55),
      Paint()
        ..color = const Color(0xFFFFB4A3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AppIconPainter oldDelegate) => false;
}
