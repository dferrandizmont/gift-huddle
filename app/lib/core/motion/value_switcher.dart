import 'package:flutter/widgets.dart';

import '../theme/regalos_motion.dart';

/// Cambia un valor que se lee (un texto, una cifra) con un fundido de 150 ms:
/// el nuevo entra subiendo [dy] píxeles y el viejo se va subiendo lo mismo.
///
/// El hijo lleva una clave que cambia con el valor (`ValueKey(texto)`). Con
/// «Reducir movimiento» solo hay fundido.
class ValueSwitcher extends StatelessWidget {
  /// Crea el cambiador.
  const ValueSwitcher({
    super.key,
    required this.child,
    this.dy = 4,
    this.alignment = Alignment.centerLeft,
  });

  /// El valor, con clave propia.
  final Widget child;

  /// Cuánto se desplaza, en píxeles.
  final double dy;

  /// Dónde se alinean el viejo y el nuevo mientras se cruzan.
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final move = RegalosMotion.of(context).reduce ? 0.0 : dy;
    return AnimatedSwitcher(
      duration: RegalosMotion.fade,
      layoutBuilder: (current, previous) =>
          Stack(alignment: alignment, children: [...previous, ?current]),
      transitionBuilder: (widget, animation) {
        final incoming = widget.key == child.key;
        return FadeTransition(
          opacity: animation,
          child: AnimatedBuilder(
            animation: animation,
            child: widget,
            builder: (context, w) => Transform.translate(
              offset: Offset(
                0,
                (incoming ? 1 : -1) * move * (1 - animation.value),
              ),
              child: w,
            ),
          ),
        );
      },
      child: child,
    );
  }
}
