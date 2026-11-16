import 'package:flutter/material.dart';

/// Marco de trazo discontinuo («nada aún», «sin asignar»).
class DashedBox extends StatelessWidget {
  const DashedBox({
    super.key,
    required this.color,
    required this.child,
    this.radius = 8,
    this.strokeWidth = 1.5,
  });

  final Color color;
  final Widget child;
  final double radius;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _DashedBoxPainter(color, radius, strokeWidth),
    child: child,
  );
}

class _DashedBoxPainter extends CustomPainter {
  const _DashedBoxPainter(this.color, this.radius, this.strokeWidth);

  final Color color;
  final double radius;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            inset,
            inset,
            size.width - strokeWidth,
            size.height - strokeWidth,
          ),
          Radius.circular(radius),
        ),
      );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = color
      ..strokeWidth = strokeWidth;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = (d + 4).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d += 7;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBoxPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.strokeWidth != strokeWidth;
}
