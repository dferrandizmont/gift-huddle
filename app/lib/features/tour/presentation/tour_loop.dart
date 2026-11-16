import 'package:flutter/widgets.dart';

import '../../../core/theme/regalos_motion.dart';

/// El valor de [t] (de 0 a 1) dentro del tramo [from] a [to] de la línea de
/// tiempo, de 0 a 1 y con [curve]. Antes del tramo vale 0 y después, 1.
double tourSeg(
  double t,
  double from,
  double to, [
  Curve curve = Curves.linear,
]) {
  if (to <= from) {
    return t >= to ? 1 : 0;
  }
  return curve.transform(((t - from) / (to - from)).clamp(0.0, 1.0));
}

/// Lo que dura la parte de fundido de cada vuelta, como fracción de la vuelta.
const double kTourFadeShare = 0.04;

/// Reproduce una demostración de la guía en bucle tranquilo.
///
/// Da a [builder] el tiempo [t] de 0 a 1 de una vuelta de [duration]:
/// - Con [active] (la página a la vista) corre sola y, al acabar, vuelve a
///   empezar: la demostración se funde al final de cada vuelta y vuelve en el
///   primer fotograma de la siguiente, así que nunca hay un salto.
/// - Sin [active] (la página asoma o ya se fue) se queda quieta en `t = 0`, el
///   punto de partida, y arranca desde ahí al entrar.
/// - Con «Reducir movimiento» no corre nunca: se queda quieta en [rest], el
///   estado que explica la página.
class TourLoop extends StatefulWidget {
  /// Crea el bucle.
  const TourLoop({
    super.key,
    required this.active,
    required this.rest,
    required this.builder,
    this.duration = const Duration(milliseconds: 9000),
  });

  /// Si la página de la demostración es la que se ve.
  final bool active;

  /// El `t` del estado final estático (con «Reducir movimiento»).
  final double rest;

  /// Lo que dura una vuelta.
  final Duration duration;

  /// Pinta la demostración en el instante [t].
  final Widget Function(BuildContext context, double t) builder;

  @override
  State<TourLoop> createState() => _TourLoopState();
}

class _TourLoopState extends State<TourLoop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    // Con «Quitar animaciones» el controlador normal se acortaría a casi 0; no
    // corre en ese caso, pero así el comportamiento no depende del sistema.
    animationBehavior: AnimationBehavior.preserve,
  )..addStatusListener(_onStatus);

  /// Si ya ha dado una vuelta entera: desde entonces, cada vuelta entra con un
  /// fundido.
  bool _wrapped = false;

  bool get _reduce => RegalosMotion.of(context).reduce;

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted && widget.active) {
      _wrapped = true;
      _controller.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(TourLoop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (oldWidget.active != widget.active) {
      _sync();
    }
  }

  void _sync() {
    if (widget.active && !_reduce) {
      if (!_controller.isAnimating) {
        _wrapped = false;
        _controller.forward(from: 0);
      }
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduce) {
      return widget.builder(context, widget.rest);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (!widget.active) {
          return widget.builder(context, 0);
        }
        final t = _controller.value;
        var opacity = 1.0;
        if (t > 1 - kTourFadeShare) {
          opacity = (1 - t) / kTourFadeShare;
        } else if (_wrapped && t < kTourFadeShare) {
          opacity = t / kTourFadeShare;
        }
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: widget.builder(context, t),
        );
      },
    );
  }
}
