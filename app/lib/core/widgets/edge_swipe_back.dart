import 'package:flutter/material.dart';

/// El gesto de volver de iOS (arrastrar desde el borde izquierdo hacia la
/// derecha) para una tarjeta que no es una página.
///
/// Las tarjetas de los editores (`CardSheetRoute`) son rutas emergentes y iOS
/// no les da su gesto de volver: el arrastre desde el borde no hacía nada, ni
/// siquiera avisaba de los cambios sin guardar (QA 1.0.7 de iOS, m1). Esta
/// franja de [edgeWidth] dp en el borde de inicio de la tarjeta lo recoge y
/// llama a [onBack], que es el mismo cierre que la flecha («¿Descartar los
/// cambios?» si hay cambios, y si no cierra).
///
/// Solo en iOS: en Android el gesto de volver del sistema ya pasa por
/// `PopScope`. La franja no recibe toques (solo arrastres horizontales), así
/// que no estorba a los campos ni a la lista, y no tiene semántica propia.
class EdgeSwipeBack extends StatefulWidget {
  /// Pone el gesto sobre [child].
  const EdgeSwipeBack({
    super.key,
    required this.onBack,
    required this.child,
    this.enabled = true,
  });

  /// Lo que se hace al completar el gesto.
  final VoidCallback onBack;

  /// La tarjeta.
  final Widget child;

  /// Si el gesto está activo (un editor que guarda no se cierra).
  final bool enabled;

  /// El ancho de la franja, como el del gesto del sistema.
  static const double edgeWidth = 24;

  /// Lo que hay que arrastrar para que cuente.
  static const double distance = 64;

  /// La velocidad que cuenta aunque se arrastre menos.
  static const double velocity = 700;

  @override
  State<EdgeSwipeBack> createState() => _EdgeSwipeBackState();
}

class _EdgeSwipeBackState extends State<EdgeSwipeBack> {
  double _dragged = 0;

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).platform != TargetPlatform.iOS || !widget.enabled) {
      return widget.child;
    }
    // Hacia dentro de la tarjeta: a la derecha en izquierda-a-derecha, a la
    // izquierda en derecha-a-izquierda.
    final sign = Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        PositionedDirectional(
          start: 0,
          top: 0,
          bottom: 0,
          width: EdgeSwipeBack.edgeWidth,
          child: ExcludeSemantics(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (_) => _dragged = 0,
              onHorizontalDragUpdate: (d) => _dragged += d.delta.dx * sign,
              onHorizontalDragEnd: (d) {
                final fast =
                    d.velocity.pixelsPerSecond.dx * sign >=
                    EdgeSwipeBack.velocity;
                final far = _dragged >= EdgeSwipeBack.distance;
                final forward = _dragged > 0;
                _dragged = 0;
                if (far || (fast && forward)) widget.onBack();
              },
              onHorizontalDragCancel: () => _dragged = 0,
            ),
          ),
        ),
      ],
    );
  }
}
