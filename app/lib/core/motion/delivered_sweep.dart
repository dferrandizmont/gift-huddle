import 'package:flutter/widgets.dart';

import '../theme/regalos_motion.dart';

/// La fila que da luz al llegar a «Entregado» (§1+.3 de
/// la guía de movimiento): una capa pastel barre la fila desde la
/// casilla hacia la derecha y se apaga. Va **debajo** del contenido.
///
/// - Es un [FractionallySizedBox] que crece de 0 a 1 de ancho con
///   `Cubic(0.2, 0.8, 0.2, 1)` durante el 30 % de [duration] y, luego, la
///   opacidad baja de [peak] a 0 en el 70 % restante con la misma curva.
/// - Solo si el cambio a «entregado» lo armó el usuario: [consumeArm] decide.
///   Un cambio que llega por sincronización no hace nada.
/// - Con «Reducir movimiento» no hay barrido.
class DeliveredSweep extends StatefulWidget {
  /// Crea la fila.
  const DeliveredSweep({
    super.key,
    required this.delivered,
    required this.consumeArm,
    required this.color,
    required this.child,
  });

  /// Si el regalo está entregado ahora.
  final bool delivered;

  /// Pregunta si este cambio lo hizo el usuario (y lo desarma).
  final bool Function() consumeArm;

  /// El pastel del barrido.
  final Color color;

  /// La fila.
  final Widget child;

  /// Lo que dura todo.
  static const Duration duration = Duration(milliseconds: 1300);

  /// La opacidad con la que arranca el barrido.
  static const double peak = 0.9;

  /// La curva del barrido y del apagado.
  static const Cubic curve = Cubic(0.2, 0.8, 0.2, 1);

  @override
  State<DeliveredSweep> createState() => DeliveredSweepState();
}

/// El estado de [DeliveredSweep].
class DeliveredSweepState extends State<DeliveredSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: DeliveredSweep.duration,
    animationBehavior: AnimationBehavior.preserve,
  );

  /// Si el barrido corre ahora mismo (para las pruebas).
  bool get sweeping => _controller.isAnimating;

  @override
  void didUpdateWidget(DeliveredSweep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.delivered && widget.delivered && widget.consumeArm()) {
      if (!RegalosMotion.of(context).reduce) {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                if (!_controller.isAnimating) {
                  return const SizedBox.shrink();
                }
                final v = _controller.value;
                final reveal = v < 0.3
                    ? DeliveredSweep.curve.transform(v / 0.3)
                    : 1.0;
                final fade = v < 0.3
                    ? 0.0
                    : DeliveredSweep.curve.transform((v - 0.3) / 0.7);
                final alpha = DeliveredSweep.peak * (1 - fade);
                return FractionallySizedBox(
                  key: const ValueKey('delivered-sweep'),
                  alignment: Alignment.centerLeft,
                  widthFactor: reveal.clamp(0.0, 1.0),
                  child: ColoredBox(
                    color: widget.color.withValues(
                      alpha: (widget.color.a * alpha).clamp(0.0, 1.0),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}
