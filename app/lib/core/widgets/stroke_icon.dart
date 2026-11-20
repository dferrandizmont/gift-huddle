import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Icono de trazo sobre una rejilla de 24 x 24, como los SVG de las maquetas.
typedef StrokeIconBuilder = void Function(Path path);

abstract final class AppIcons {
  static void back(Path p) {
    p
      ..moveTo(15, 5)
      ..relativeLineTo(-7, 7)
      ..relativeLineTo(7, 7);
  }

  static void chevronRight(Path p) {
    p
      ..moveTo(9, 5)
      ..relativeLineTo(7, 7)
      ..relativeLineTo(-7, 7);
  }

  static void chevronDown(Path p) {
    p
      ..moveTo(5, 9)
      ..relativeLineTo(7, 7)
      ..relativeLineTo(7, -7);
  }

  static void chevronUp(Path p) {
    p
      ..moveTo(5, 15)
      ..relativeLineTo(7, -7)
      ..relativeLineTo(7, 7);
  }

  static void people(Path p) {
    p
      ..addOval(Rect.fromCircle(center: const Offset(12, 8), radius: 3.5))
      ..moveTo(5, 20)
      ..relativeCubicTo(0, -3.9, 3.1, -7, 7, -7)
      ..relativeCubicTo(3.9, 0, 7, 3.1, 7, 7);
  }

  static void family(Path p) {
    p
      ..addOval(Rect.fromCircle(center: const Offset(9, 8.5), radius: 3))
      ..moveTo(3, 19.5)
      ..relativeCubicTo(0, -3.3, 2.7, -6, 6, -6)
      ..relativeCubicTo(3.3, 0, 6, 2.7, 6, 6)
      ..addOval(Rect.fromCircle(center: const Offset(17, 9.5), radius: 2.4))
      ..moveTo(17, 14.2)
      ..relativeCubicTo(2.4, 0, 4.2, 1.9, 4.2, 4.3);
  }

  static void occasions(Path p) {
    p
      ..addRRect(RRect.fromLTRBR(4, 5, 20, 20, const Radius.circular(2)))
      ..moveTo(4, 10)
      ..relativeLineTo(16, 0)
      ..moveTo(8, 3)
      ..relativeLineTo(0, 4)
      ..moveTo(16, 3)
      ..relativeLineTo(0, 4);
  }

  static void settings(Path p) {
    p
      ..moveTo(4, 7)
      ..relativeLineTo(9, 0)
      ..moveTo(17, 7)
      ..relativeLineTo(3, 0)
      ..moveTo(4, 17)
      ..relativeLineTo(3, 0)
      ..moveTo(11, 17)
      ..relativeLineTo(9, 0)
      ..addOval(Rect.fromCircle(center: const Offset(15, 7), radius: 2))
      ..addOval(Rect.fromCircle(center: const Offset(9, 17), radius: 2));
  }

  /// Cartera: el presupuesto (cuadrícula de 24).
  static void budget(Path p) {
    p
      ..addRRect(RRect.fromLTRBR(3.5, 6, 20.5, 19, const Radius.circular(2.5)))
      ..moveTo(6.5, 6)
      ..lineTo(15.5, 3.5)
      ..lineTo(16.5, 6)
      ..addRRect(
        RRect.fromLTRBR(14, 11.5, 20.5, 15.5, const Radius.circular(2)),
      );
  }

  /// Más (cuadrícula de 24).
  static void plus(Path p) {
    p
      ..moveTo(12, 5)
      ..relativeLineTo(0, 14)
      ..moveTo(5, 12)
      ..relativeLineTo(14, 0);
  }

  static void close(Path p) {
    p
      ..moveTo(6, 6)
      ..relativeLineTo(12, 12)
      ..moveTo(18, 6)
      ..relativeLineTo(-12, 12);
  }

  /// Triángulo de aviso con su exclamación.
  static void alert(Path p) {
    p
      ..moveTo(12, 3.5)
      ..lineTo(21.5, 20)
      ..lineTo(2.5, 20)
      ..close()
      ..moveTo(12, 9.5)
      ..relativeLineTo(0, 4.5)
      ..moveTo(12, 17)
      ..relativeLineTo(0, 0.01);
  }

  static void edit(Path p) {
    p
      ..moveTo(4, 20)
      ..relativeLineTo(1, -4.5)
      ..relativeLineTo(10.5, -10.5)
      ..relativeLineTo(3.5, 3.5)
      ..relativeLineTo(-10.5, 10.5)
      ..close();
  }

  static void filter(Path p) {
    p
      ..moveTo(4, 7)
      ..relativeLineTo(16, 0)
      ..moveTo(7, 12)
      ..relativeLineTo(10, 0)
      ..moveTo(10, 17)
      ..relativeLineTo(4, 0);
  }

  static void share(Path p) {
    p
      ..moveTo(12, 15)
      ..lineTo(12, 4)
      ..moveTo(8, 8)
      ..lineTo(12, 4)
      ..lineTo(16, 8)
      ..moveTo(6, 12)
      ..lineTo(6, 19)
      ..lineTo(18, 19)
      ..lineTo(18, 12);
  }

  /// Candado cerrado.
  static void lock(Path p) {
    p
      ..addRRect(RRect.fromLTRBR(5, 11, 19, 20.5, const Radius.circular(2.5)))
      ..moveTo(8, 11)
      ..lineTo(8, 8)
      ..arcToPoint(
        const Offset(16, 8),
        radius: const Radius.circular(4),
        clockwise: true,
      )
      ..lineTo(16, 11);
  }

  /// Marca de verificación de las muestras de color (cuadrícula de 24).
  static void check(Path p) {
    p
      ..moveTo(5, 12.5)
      ..relativeLineTo(4.5, 4.5)
      ..lineTo(19, 7.5);
  }

  /// Raya (casilla a medias).
  static void minus(Path p) {
    p
      ..moveTo(6, 12)
      ..relativeLineTo(12, 0);
  }

  /// Círculo tachado (`ban` de Tabler): no se regala.
  static void ban(Path p) {
    p
      ..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 9))
      ..moveTo(5.7, 5.7)
      ..lineTo(18.3, 18.3);
  }

  /// Lupa: buscar.
  static void search(Path p) {
    p
      ..addOval(Rect.fromCircle(center: const Offset(10.5, 10.5), radius: 6.5))
      ..moveTo(15.5, 15.5)
      ..lineTo(20, 20);
  }

  /// Marco con la barra lateral a la izquierda: plegar o desplegar la barra.
  static void sidebar(Path p) {
    p
      ..addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(4, 5, 16, 14),
          const Radius.circular(2),
        ),
      )
      ..moveTo(9.5, 5)
      ..lineTo(9.5, 19);
  }

  /// Tres puntos en horizontal: más acciones.
  static void moreHorizontal(Path p) {
    for (final x in const [6.0, 12.0, 18.0]) {
      p
        ..addOval(Rect.fromCircle(center: Offset(x, 12), radius: 0.6))
        ..moveTo(x, 12);
    }
  }
}

/// Dibuja un [StrokeIconBuilder] con trazo redondeado. Es decorativo: quien lo
/// use pone la etiqueta accesible en el control que lo contiene.
class StrokeIcon extends StatelessWidget {
  const StrokeIcon(
    this.builder, {
    super.key,
    this.size = 22,
    this.color,
    this.strokeWidth = 1.8,
  });

  final StrokeIconBuilder builder;
  final double size;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? const Color(0xFF000000);
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _StrokeIconPainter(builder, c, strokeWidth),
      ),
    );
  }
}

class _StrokeIconPainter extends CustomPainter {
  _StrokeIconPainter(this.builder, this.color, this.strokeWidth);

  final StrokeIconBuilder builder;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    builder(path);
    final scale = size.width / 24;
    canvas
      ..save()
      ..scale(scale)
      ..drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = color
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_StrokeIconPainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.builder != builder;
}

/// Pinta un círculo de trazo discontinuo (3 y 3 unidades de una rejilla de 22),
/// como «Idea» y «sin asignar».
void paintDashedCircle(
  Canvas canvas, {
  required Offset center,
  required double radius,
  required Paint paint,
  required double dash,
  required double gap,
}) {
  final circle = Path()
    ..addArc(Rect.fromCircle(center: center, radius: radius), 0, 2 * math.pi);
  for (final metric in circle.computeMetrics()) {
    var d = 0.0;
    while (d < metric.length) {
      final end = (d + dash).clamp(0.0, metric.length);
      canvas.drawPath(metric.extractPath(d, end), paint);
      d += dash + gap;
    }
  }
}
