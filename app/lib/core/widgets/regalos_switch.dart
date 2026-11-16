import 'package:flutter/material.dart';

import '../motion/haptics.dart';
import '../theme/regalos_motion.dart';
import '../theme/regalos_shape.dart';
import '../theme/regalos_tokens.dart';

/// Interruptor del diseño: pista rectangular de 48 x 28 (radio 8, nada de
/// píldoras) con borde de tinta, pastel dentro y pulgar cuadrado de tinta;
/// zona táctil de 52 x 44. Apagado: borde gris y pulgar gris a la izquierda
/// (la posición también dice el estado, no solo el color).
///
/// El pulgar se mueve con `snap` (375 ms) y los colores pasan con `soft`. Con
/// «Reducir movimiento» el sistema pide fundido, no corte: todo dura 150 ms
/// lineales. Los controladores conservan su duración con «Quitar animaciones»
/// (`AnimationBehavior.preserve`); los implícitos de Material la reducirían a
/// casi cero y sería un corte.
class RegalosSwitch extends StatefulWidget {
  const RegalosSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  State<RegalosSwitch> createState() => _RegalosSwitchState();
}

class _RegalosSwitchState extends State<RegalosSwitch>
    with TickerProviderStateMixin {
  /// Posición y tamaño del pulgar: 0 apagado, 1 encendido.
  late final AnimationController _move = AnimationController(
    vsync: this,
    value: widget.value ? 1 : 0,
    animationBehavior: AnimationBehavior.preserve,
  );

  /// Colores de la pista y del pulgar.
  late final AnimationController _color = AnimationController(
    vsync: this,
    value: widget.value ? 1 : 0,
    animationBehavior: AnimationBehavior.preserve,
  );

  /// Un toque del usuario: la vibración llega con el pulgar, no con el dedo.
  void _toggle() {
    final onChanged = widget.onChanged;
    if (onChanged == null) {
      return;
    }
    context.haptics.selection(after: context.hapticArrival);
    onChanged(!widget.value);
  }

  @override
  void didUpdateWidget(RegalosSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value) {
      return;
    }
    final motion = RegalosMotion.of(context);
    final target = widget.value ? 1.0 : 0.0;
    _move.animateTo(
      target,
      duration: motion.duration(RegalosSprings.snapDuration),
      curve: motion.curve(RegalosCurves.snap),
    );
    _color.animateTo(
      target,
      duration: motion.duration(RegalosSprings.softDuration),
      curve: motion.curve(RegalosCurves.soft),
    );
  }

  @override
  void dispose() {
    _move.dispose();
    _color.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final value = widget.value;
    final onChanged = widget.onChanged;
    // En oscuro encendido es un interruptor pleno (pista de relleno vivo y
    // pieza oscura); en claro, pista suave con borde y pieza de tinta.
    final onThumb = t.isDark ? t.onFill : t.ink;
    final onTrack = t.isDark ? t.fill : t.soft;
    final onEdge = t.isDark ? t.fill : t.ink;

    return Semantics(
      container: true,
      toggled: value,
      label: widget.semanticLabel,
      enabled: onChanged != null,
      onTap: onChanged == null ? null : _toggle,
      excludeSemantics: true,
      child: SizedBox(
        width: 52,
        height: 44,
        child: InkResponse(
          onTap: onChanged == null ? null : _toggle,
          customBorder: const RoundedRectangleBorder(
            borderRadius: RegalosShape.button,
          ),
          child: Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([_move, _color]),
              builder: (context, _) {
                final m = _move.value;
                final c = _color.value;
                final thumbSize = 16.0 + 4.0 * m;
                return Container(
                  width: 48,
                  height: 28,
                  decoration: BoxDecoration(
                    color: onTrack.withValues(alpha: onTrack.a * c),
                    borderRadius: RegalosShape.button,
                    border: Border.all(
                      color: Color.lerp(t.ideaStroke, onEdge, c)!,
                      width: 1.5,
                    ),
                  ),
                  child: Align(
                    alignment: Alignment(-1 + 2 * m, 0),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Container(
                        width: thumbSize,
                        height: thumbSize,
                        decoration: BoxDecoration(
                          color: Color.lerp(t.ideaStroke, onThumb, c),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
