import 'package:flutter/material.dart';

import '../theme/regalos_tokens.dart';
import 'stroke_icon.dart';

/// Punto de color de quien regala (8 px). Sin [colorIndex] es un círculo
/// discontinuo: «sin asignar».
///
/// Junto al punto siempre va el nombre, así que por defecto no lo lee el lector
/// de pantalla; pasa [semanticLabel] si va solo.
class GiverDot extends StatelessWidget {
  const GiverDot({
    super.key,
    this.colorIndex,
    this.size = 8,
    this.semanticLabel,
  });

  final int? colorIndex;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final index = colorIndex;
    final dot = index == null
        ? CustomPaint(
            size: Size.square(size),
            painter: _DashedDotPainter(t.ideaStroke),
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              color: t.giver(index),
              shape: BoxShape.circle,
            ),
            child: SizedBox.square(dimension: size),
          );

    if (semanticLabel == null) return ExcludeSemantics(child: dot);
    return Semantics(label: semanticLabel, image: true, child: dot);
  }
}

class _DashedDotPainter extends CustomPainter {
  const _DashedDotPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 1.5;
    paintDashedCircle(
      canvas,
      center: size.center(Offset.zero),
      radius: (size.width - stroke) / 2,
      paint: Paint()
        ..style = PaintingStyle.stroke
        ..color = color
        ..strokeWidth = stroke,
      dash: 2.2,
      gap: 1.8,
    );
  }

  @override
  bool shouldRepaint(_DashedDotPainter old) => old.color != color;
}
