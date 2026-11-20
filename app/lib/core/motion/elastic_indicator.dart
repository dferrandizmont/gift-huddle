import 'package:flutter/widgets.dart';

import '../theme/regalos_motion.dart';
import '../theme/regalos_shape.dart';
import '../theme/regalos_tokens.dart';

/// El recuadro pastel elástico de la navegación (§1+.1 de
/// la guía de movimiento y §4.1 de la guía de diseño para tablet):
/// un rectángulo de radio 8 entre dos bordes que no salen a la vez. En la barra
/// inferior viaja en horizontal; en el raíl lateral, en vertical.
///
/// Un solo controlador de 375 + 70 = 445 ms: el borde delantero (el del lado
/// al que va) sigue `snap` en el primer tramo y el trasero, `snap` en el
/// último. El recuadro se alarga hacia el destino y se recoge al llegar; en el
/// otro eje no cambia de medida, y nunca se redondea. Si se toca otro destino
/// a mitad de camino, parte desde donde está.
///
/// Va dentro de un `Stack` (devuelve un `Positioned`). En reposo se coloca
/// con las medidas que recibe, sin animar: cambiar el tamaño de la ventana no
/// lo hace viajar. Con «Reducir movimiento» no se monta: cada destino funde
/// su propio recuadro.
class ElasticIndicator extends StatefulWidget {
  const ElasticIndicator({
    super.key,
    required this.axis,
    required this.index,
    required this.origin,
    required this.pitch,
    required this.extent,
    required this.crossOffset,
    required this.crossExtent,
  });

  /// El eje por el que viaja: horizontal en la barra, vertical en el raíl.
  final Axis axis;

  /// El destino activo.
  final int index;

  /// Dónde empieza el recuadro del primer destino, en el eje del viaje
  /// (desde la izquierda o desde arriba).
  final double origin;

  /// Lo que hay de un destino al siguiente, en el eje del viaje.
  final double pitch;

  /// Lo que mide el recuadro en reposo, en el eje del viaje.
  final double extent;

  /// Dónde empieza el recuadro en el otro eje (desde arriba o desde la
  /// izquierda).
  final double crossOffset;

  /// Lo que mide el recuadro en el otro eje. No cambia nunca.
  final double crossExtent;

  /// Lo que el borde de atrás espera al de delante.
  static const Duration lag = Duration(milliseconds: 70);

  /// Lo que dura el viaje entero: el muelle más la espera del borde de atrás.
  static final Duration duration = RegalosSprings.snapDuration + lag;

  @override
  State<ElasticIndicator> createState() => _ElasticIndicatorState();
}

class _ElasticIndicatorState extends State<ElasticIndicator>
    with SingleTickerProviderStateMixin {
  static final int _total = ElasticIndicator.duration.inMicroseconds;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ElasticIndicator.duration,
    animationBehavior: AnimationBehavior.preserve,
  );
  late final Animation<double> _lead = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      0,
      RegalosSprings.snapDuration.inMicroseconds / _total,
      curve: RegalosCurves.snap,
    ),
  );
  late final Animation<double> _trail = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      ElasticIndicator.lag.inMicroseconds / _total,
      1,
      curve: RegalosCurves.snap,
    ),
  );

  // Los bordes de partida del viaje y si va hacia delante (a la derecha o
  // hacia abajo).
  double _fromStart = 0;
  double _fromEnd = 0;
  bool _forward = true;

  /// Los bordes ahora mismo, camino del destino de [w]: en reposo o a mitad
  /// del viaje.
  (double, double) _edges(ElasticIndicator w) {
    final toStart = w.origin + w.pitch * w.index;
    final toEnd = toStart + w.extent;
    if (!_controller.isAnimating) {
      return (toStart, toEnd);
    }
    final startT = _forward ? _trail.value : _lead.value;
    final endT = _forward ? _lead.value : _trail.value;
    return (
      _fromStart + (toStart - _fromStart) * startT,
      _fromEnd + (toEnd - _fromEnd) * endT,
    );
  }

  @override
  void didUpdateWidget(ElasticIndicator old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      // Parte de donde está ahora, también si el viaje anterior no acabó.
      final (start, end) = _edges(old);
      _fromStart = start;
      _fromEnd = end;
      _forward = widget.index > old.index;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return AnimatedBuilder(
      animation: _controller,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.selection,
          borderRadius: RegalosShape.chip,
        ),
      ),
      builder: (context, child) {
        final (start, end) = _edges(widget);
        return switch (widget.axis) {
          Axis.horizontal => Positioned(
            left: start,
            top: widget.crossOffset,
            width: end - start,
            height: widget.crossExtent,
            child: child!,
          ),
          Axis.vertical => Positioned(
            left: widget.crossOffset,
            top: start,
            width: widget.crossExtent,
            height: end - start,
            child: child!,
          ),
        };
      },
    );
  }
}
