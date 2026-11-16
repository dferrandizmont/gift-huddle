import 'package:flutter/widgets.dart';

import '../theme/regalos_motion.dart';
import '../theme/regalos_shape.dart';
import '../theme/regalos_tokens.dart';
import 'pop_in.dart';

/// El visto que se dibuja (la guía de movimiento, «Visto que se
/// dibuja»): `PathMetric.extractPath(0, largo × t)`, en [duration] con
/// [curve] (220 ms `easeOut` en botones y sellos).
///
/// Con «Reducir movimiento» aparece entero, sin dibujarse.
class DrawnCheck extends StatefulWidget {
  /// Crea el visto.
  const DrawnCheck({
    super.key,
    required this.color,
    this.size = 20,
    this.strokeWidth = 2.6,
    this.duration = const Duration(milliseconds: 220),
    this.delay = Duration.zero,
    this.curve = Curves.easeOut,
    this.progress,
  });

  /// Color del trazo.
  final Color color;

  /// Lado del cuadro, en píxeles.
  final double size;

  /// Grosor del trazo en un cuadro de 24.
  final double strokeWidth;

  /// Lo que tarda en dibujarse.
  final Duration duration;

  /// Retardo antes de empezar a dibujarse.
  final Duration delay;

  /// La curva del dibujo.
  final Curve curve;

  /// Si se da, el visto sigue ese avance (0 a 1) en vez de animarse solo.
  final Animation<double>? progress;

  @override
  State<DrawnCheck> createState() => _DrawnCheckState();
}

class _DrawnCheckState extends State<DrawnCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    animationBehavior: AnimationBehavior.preserve,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || widget.progress != null) {
      return;
    }
    _started = true;
    if (RegalosMotion.of(context).reduce) {
      _controller.value = 1;
      return;
    }
    _controller
      ..duration = widget.delay + widget.duration
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listenable = widget.progress ?? _controller;
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: listenable,
        builder: (context, _) {
          double t;
          if (widget.progress != null) {
            t = widget.progress!.value;
          } else if (RegalosMotion.of(context).reduce) {
            t = 1;
          } else {
            final total = _controller.duration?.inMicroseconds ?? 1;
            t =
                ((_controller.value * total - widget.delay.inMicroseconds) /
                        widget.duration.inMicroseconds)
                    .clamp(0.0, 1.0);
            t = widget.curve.transform(t);
          }
          return CustomPaint(
            painter: _CheckPainter(widget.color, widget.strokeWidth, t),
          );
        },
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter(this.color, this.strokeWidth, this.t);

  final Color color;
  final double strokeWidth;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) {
      return;
    }
    final k = size.width / 24;
    final path = Path()
      ..moveTo(5 * k, 12.5 * k)
      ..lineTo(9.5 * k, 17 * k)
      ..lineTo(19 * k, 7 * k);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * t.clamp(0.0, 1.0)),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = color
        ..strokeWidth = strokeWidth * k
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.t != t || old.color != color || old.strokeWidth != strokeWidth;
}

/// El sello de éxito (§3.2 y «momento L» de la guía de movimiento):
/// un cuadro pastel de [size] con radio 8 y un visto de tinta.
///
/// - El cuadro entra con un rebote desde 0,8 ([PopIn]) a los [pulseDelay]
///   (60 ms).
/// - El visto se dibuja en [checkDuration] (300 ms) con `snap`, empezando a los
///   [checkDelay] (180 ms).
///
/// Con «Reducir movimiento» el cuadro se funde en 150 ms y el visto aparece
/// entero. Es decorativo: no lleva etiqueta de accesibilidad.
class SuccessMark extends StatelessWidget {
  /// Crea el sello.
  const SuccessMark({
    super.key,
    this.size = 64,
    this.pulseDelay = const Duration(milliseconds: 60),
    this.checkDelay = const Duration(milliseconds: 180),
    this.checkDuration = const Duration(milliseconds: 300),
  });

  /// Lado del cuadro: 64 en la hoja y 32 en el aviso.
  final double size;

  /// Cuándo empieza el rebote del cuadro.
  final Duration pulseDelay;

  /// Cuándo empieza a dibujarse el visto.
  final Duration checkDelay;

  /// Lo que tarda en dibujarse el visto.
  final Duration checkDuration;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return ExcludeSemantics(
      child: PopIn(
        from: 0.8,
        delay: pulseDelay,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.fill,
            borderRadius: RegalosShape.chip,
          ),
          child: DrawnCheck(
            color: t.ink,
            size: size * 0.55,
            delay: checkDelay,
            duration: checkDuration,
            curve: RegalosCurves.snap,
          ),
        ),
      ),
    );
  }
}
