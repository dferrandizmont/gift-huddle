import 'package:flutter/material.dart';

import '../theme/regalos_motion.dart';
import '../theme/regalos_shape.dart';
import '../theme/regalos_tokens.dart';

/// Lo que dura el fundido del fondo al salir el ratón (al entrar es inmediato).
const Duration kHoverDuration = Duration(milliseconds: 120);

/// El estado de ratón de una fila o una tarjeta (plan de escritorio, §2.3):
/// al pasar el puntero se tiñe con la tinta del acento al 7 % (12 % en oscuro)
/// al instante, se destiñe en 120 ms al salir, y el cursor es una mano. No cambia de tamaño ni de sitio.
///
/// El tinte va por encima de [child] y no recibe toques. Con un dedo no hay
/// «pasar por encima», así que en el móvil y en la tablet táctil no se ve.
/// El foco con teclado no va aquí: lo pinta `FocusRingOverlay` para todos los
/// controles a la vez.
class PointerSurface extends StatefulWidget {
  /// Crea la superficie.
  const PointerSurface({
    super.key,
    this.radius = RegalosShape.card,
    this.enabled = true,
    this.strength = 1,
    required this.child,
  });

  /// Cuánto se nota el tinte: 1 es el de siempre; el tablero de la web de
  /// escritorio lo sube en sus filas (`reglas-escritorio.md`, L1).
  final double strength;

  /// Las esquinas del tinte.
  final BorderRadius radius;

  /// Si reacciona al puntero (una fila que no se puede tocar no lo hace).
  final bool enabled;

  final Widget child;

  @override
  State<PointerSurface> createState() => _PointerSurfaceState();
}

class _PointerSurfaceState extends State<PointerSurface> {
  bool _hover = false;

  void _set(bool value) {
    if (_hover != value && mounted) {
      setState(() => _hover = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }
    final t = RegalosTokens.of(context);
    final reduce = RegalosMotion.of(context).reduce;
    final tint = t.ink.withValues(
      alpha: ((t.isDark ? 0.12 : 0.07) * widget.strength).clamp(0.0, 1.0),
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _set(true),
      onExit: (_) => _set(false),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                // Entra en el acto y sale en 120 ms: la respuesta se nota y no
                // parpadea al cruzar filas.
                duration: _hover
                    ? Duration.zero
                    : (reduce ? RegalosMotion.fade : kHoverDuration),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: _hover ? tint : tint.withValues(alpha: 0),
                  borderRadius: widget.radius,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
