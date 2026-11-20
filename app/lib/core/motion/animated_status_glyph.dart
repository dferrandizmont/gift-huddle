import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../theme/gift_status.dart';
import '../theme/regalos_motion.dart';
import '../theme/regalos_tokens.dart';
import '../widgets/spring_pulse.dart';
import '../widgets/status_checkbox.dart';

/// La casilla de estado de un regalo, que va de un estado al siguiente en vez
/// de cambiar de golpe (§1.3 de la guía de movimiento).
///
/// - El sector **barre** del valor viejo al nuevo con `snap` (0, ¼, ½, ¾, 1).
/// - De idea (discontinuo) a decidido (anillo): fundido cruzado de 200 ms.
/// - A entregado, el círculo lleno crece desde el centro con `snap` y el visto
///   se dibuja en 220 ms, empezando a los 120.
/// - Toda la casilla rebota (`SpringPulse` desde 0,78). Al volver atrás, la
///   misma animación al revés y sin rebote.
/// - Con «Reducir movimiento»: fundido cruzado de 150 ms entre la casilla vieja
///   y la nueva, sin barrido ni rebote.
///
/// Se construye ya en su estado, sin animar: solo anima cuando [status] cambia
/// en una casilla que ya está en pantalla. Por eso las filas que se animan
/// llevan clave estable (`ValueKey(gift.id)`).
class AnimatedStatusGlyph extends StatefulWidget {
  /// Crea la casilla.
  const AnimatedStatusGlyph({super.key, required this.status, this.size = 24});

  /// El estado que se dibuja.
  final GiftStatus status;

  /// Lado de la casilla.
  final double size;

  @override
  State<AnimatedStatusGlyph> createState() => _AnimatedStatusGlyphState();
}

class _AnimatedStatusGlyphState extends State<AnimatedStatusGlyph>
    with TickerProviderStateMixin {
  static const Duration _checkDuration = Duration(milliseconds: 340);

  /// El visto espera 120 ms y se dibuja en los 220 siguientes.
  static const Curve _checkCurve = Interval(
    120 / 340,
    1,
    curve: Curves.easeOut,
  );

  /// Fracción del sector, con muelle.
  late final AnimationController _sweep = AnimationController.unbounded(
    vsync: this,
    value: widget.status.fill,
  );

  /// 0 es el círculo lleno sin crecer; 1, entregado.
  late final AnimationController _grow = AnimationController.unbounded(
    vsync: this,
    value: _delivered(widget.status) ? 1 : 0,
  );

  /// 0 es el discontinuo de «idea»; 1, el anillo continuo.
  late final AnimationController _solid = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: widget.status == GiftStatus.idea ? 0 : 1,
  );

  /// El visto, de 0 a 1 en 340 ms (120 de espera y 220 de trazo).
  late final AnimationController _check = AnimationController(
    vsync: this,
    duration: _checkDuration,
    value: _delivered(widget.status) ? 1 : 0,
  );

  final GlobalKey<SpringPulseState> _pulse = GlobalKey<SpringPulseState>();

  static bool _delivered(GiftStatus s) => s == GiftStatus.delivered;

  @override
  void didUpdateWidget(AnimatedStatusGlyph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status == widget.status) {
      return;
    }
    if (RegalosMotion.of(context).reduce) {
      _jumpTo(widget.status);
    } else {
      _animateTo(oldWidget.status, widget.status);
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    _grow.dispose();
    _solid.dispose();
    _check.dispose();
    super.dispose();
  }

  /// Sin movimiento: solo deja los valores en su sitio (el fundido lo hace el
  /// `AnimatedSwitcher` de `build`).
  void _jumpTo(GiftStatus to) {
    _sweep
      ..stop()
      ..value = to.fill;
    _grow
      ..stop()
      ..value = _delivered(to) ? 1 : 0;
    _solid.value = to == GiftStatus.idea ? 0 : 1;
    _check.value = _delivered(to) ? 1 : 0;
  }

  void _animateTo(GiftStatus from, GiftStatus to) {
    final forward = to.index > from.index;

    // El sector barre con `snap`. Un segundo toque durante el barrido parte de
    // donde va: no espera ni salta.
    _sweep
      ..stop()
      ..animateWith(
        SpringSimulation(
          RegalosSprings.snap,
          _sweep.value,
          to.fill,
          0,
          snapToEnd: true,
        ),
      );

    // Idea <-> anillo continuo.
    _solid.animateTo(to == GiftStatus.idea ? 0 : 1, curve: Curves.linear);

    // Entregado: el círculo crece y se dibuja el visto.
    if (_delivered(to)) {
      _grow
        ..stop()
        ..animateWith(
          SpringSimulation(
            RegalosSprings.snap,
            _grow.value,
            1,
            0,
            snapToEnd: true,
          ),
        );
      _check.animateTo(1, duration: _checkDuration, curve: Curves.linear);
    } else if (_delivered(from)) {
      _grow
        ..stop()
        ..animateTo(
          0,
          duration: RegalosCurves.foldDuration,
          curve: RegalosCurves.fold,
        );
      _check.animateBack(
        0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.linear,
      );
    }

    // Rebote de toda la casilla; al volver atrás, un asiento sin rebote.
    _pulse.currentState?.play(
      from: forward ? 0.78 : 0.92,
      spring: forward ? RegalosSprings.bounce : RegalosSprings.snap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    if (RegalosMotion.of(context).reduce) {
      return AnimatedSwitcher(
        duration: RegalosMotion.fade,
        child: StatusGlyph(
          key: ValueKey(widget.status),
          status: widget.status,
          size: widget.size,
        ),
      );
    }
    return ExcludeSemantics(
      child: SpringPulse(
        key: _pulse,
        child: AnimatedBuilder(
          animation: Listenable.merge([_sweep, _grow, _solid, _check]),
          builder: (context, _) => CustomPaint(
            size: Size.square(widget.size),
            painter: StatusGlyphPainter(
              status: widget.status,
              stroke: Color.lerp(t.ideaStroke, t.ink, _solid.value)!,
              fill: t.statusFill(widget.status),
              checkColor: t.bg,
              sweep: _sweep.value.clamp(0.0, 1.0),
              solid: _solid.value,
              grow: _grow.value,
              check: _checkCurve.transform(_check.value),
            ),
          ),
        ),
      ),
    );
  }
}
