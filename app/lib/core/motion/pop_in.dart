import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../theme/regalos_motion.dart';

/// Entra al aparecer con un rebote pequeño: escala de [from] a 1 con `bounce`
/// y un fundido de 0 a 1. Con «Reducir movimiento» solo se funde, en 150 ms.
///
/// Se pinta ya en su punto de partida desde el primer fotograma (no hay un
/// fotograma a tamaño completo antes de empezar). Con `animate: false` se
/// pinta tal cual.
class PopIn extends StatefulWidget {
  /// Crea la entrada.
  const PopIn({
    super.key,
    required this.child,
    this.from = 0.9,
    this.animate = true,
    this.delay = Duration.zero,
  });

  /// Lo que entra.
  final Widget child;

  /// Cuánto espera, ya en su punto de partida (invisible), antes de rebotar.
  /// Va dentro de la propia simulación, sin temporizadores.
  final Duration delay;

  /// Escala de partida.
  final double from;

  /// Si entra animado.
  final bool animate;

  @override
  State<PopIn> createState() => _PopInState();
}

class _PopInState extends State<PopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this,
    value: widget.animate ? widget.from : 1,
  );
  bool _started = false;
  bool _fadeOnly = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || !widget.animate) {
      return;
    }
    _started = true;
    if (RegalosMotion.of(context).reduce) {
      _fadeOnly = true;
      _controller.value = 0;
      if (widget.delay == Duration.zero) {
        _controller.animateTo(
          1,
          duration: RegalosMotion.fade,
          curve: Curves.linear,
        );
      } else {
        // El retardo va en la curva: el valor se queda en 0 hasta entonces.
        _controller.animateTo(
          1,
          duration: widget.delay + RegalosMotion.fade,
          curve: Interval(
            widget.delay.inMicroseconds /
                (widget.delay + RegalosMotion.fade).inMicroseconds,
            1,
          ),
        );
      }
    } else {
      final spring = SpringSimulation(
        RegalosSprings.bounce,
        widget.from,
        1,
        0,
        snapToEnd: true,
      );
      _controller.animateWith(
        widget.delay == Duration.zero
            ? spring
            : _DelayedSimulation(spring, widget.delay, widget.from),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      final v = _controller.value;
      // El envoltorio se queda siempre, para no reconstruir al hijo al acabar.
      if (_fadeOnly) {
        return Opacity(opacity: v.clamp(0.0, 1.0), child: child);
      }
      final opacity = ((v - widget.from) / (1 - widget.from)).clamp(0.0, 1.0);
      return Opacity(
        opacity: opacity,
        child: Transform.scale(scale: v, child: child),
      );
    },
  );
}

/// Un muelle que espera [delay] en su punto de partida antes de empezar.
class _DelayedSimulation extends Simulation {
  _DelayedSimulation(this._inner, this.delay, this._start)
    : super(tolerance: _inner.tolerance);

  final Simulation _inner;
  final Duration delay;
  final double _start;

  double _shifted(double time) =>
      time - delay.inMicroseconds / Duration.microsecondsPerSecond;

  @override
  double x(double time) =>
      _shifted(time) <= 0 ? _start : _inner.x(_shifted(time));

  @override
  double dx(double time) => _shifted(time) <= 0 ? 0 : _inner.dx(_shifted(time));

  @override
  bool isDone(double time) =>
      _shifted(time) > 0 && _inner.isDone(_shifted(time));
}
