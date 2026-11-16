import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../theme/regalos_motion.dart';

/// Un rebote de muelle: el hijo parte pequeño (escala [from]) y vuelve a su
/// tamaño. Se dispara solo cuando cambia [trigger], o a mano con
/// [SpringPulseState.play] (con una `GlobalKey<SpringPulseState>`).
///
/// Con «Reducir movimiento» no escala: solo funde de medio a opaco en 150 ms.
class SpringPulse extends StatefulWidget {
  const SpringPulse({
    super.key,
    required this.child,
    this.trigger,
    this.from = 0.78,
    this.spring = RegalosSprings.bounce,
  });

  final Widget child;

  /// Cuando cambia, el hijo rebota.
  final Object? trigger;

  /// Escala de partida.
  final double from;

  /// El muelle del rebote.
  final SpringDescription spring;

  @override
  State<SpringPulse> createState() => SpringPulseState();
}

class SpringPulseState extends State<SpringPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  double _from = 1;
  double _opacityFrom = 1;
  bool _fadeOnly = false;

  @override
  void didUpdateWidget(SpringPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger != widget.trigger) {
      play();
    }
  }

  /// Lanza el rebote. Con [opacityFrom] menor que 1 también aparece fundiendo
  /// (el cambio suave de un filtro).
  void play({double? from, SpringDescription? spring, double opacityFrom = 1}) {
    if (!mounted) {
      return;
    }
    _opacityFrom = opacityFrom;
    if (RegalosMotion.of(context).reduce) {
      _fadeOnly = true;
      _from = 0;
      _controller
        ..stop()
        ..value = 0;
      _controller.animateTo(
        1,
        duration: RegalosMotion.fade,
        curve: Curves.linear,
      );
      return;
    }
    _fadeOnly = false;
    _from = from ?? widget.from;
    _controller
      ..stop()
      ..value = _from;
    _controller.animateWith(
      SpringSimulation(spring ?? widget.spring, _from, 1, 0),
    );
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
      if (!_controller.isAnimating) {
        return child!;
      }
      final v = _controller.value;
      if (_fadeOnly) {
        return Opacity(opacity: 0.5 + 0.5 * v.clamp(0.0, 1.0), child: child);
      }
      Widget w = Transform.scale(scale: v, child: child);
      if (_opacityFrom < 1 && _from < 1) {
        final p = ((v - _from) / (1 - _from)).clamp(0.0, 1.0);
        w = Opacity(opacity: _opacityFrom + (1 - _opacityFrom) * p, child: w);
      }
      return w;
    },
  );
}
