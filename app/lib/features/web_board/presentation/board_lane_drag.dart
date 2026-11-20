import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../../core/motion/rect_flight.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/sync/model.dart';
import 'board_lane_move.dart';

/// Quien sigue al puntero mientras se arrastra una tarjeta (para que el
/// tablero se desplace solo cuando se acerca al borde).
typedef BoardDragPointer = void Function(Offset? globalPosition);

/// Hace arrastrable una fila de regalo de un carril a otro.
///
/// Con el ratón, de inmediato; con el dedo o el lápiz, con una pulsación larga
/// (así el dedo sigue desplazando la lista). Mientras se arrastra, la tarjeta
/// flota con una sombra suave y un 3 % más grande (con «Reducir movimiento»,
/// sin escalar), y en su sitio queda una copia tenue.
///
/// El teclado y los lectores de pantalla no arrastran: mueven la tarjeta con
/// su propia acción (ver `BoardGiftRow`).
class BoardCardDraggable extends StatefulWidget {
  /// Crea la tarjeta arrastrable de [gift].
  const BoardCardDraggable({
    super.key,
    required this.gift,
    required this.width,
    required this.card,
    this.onPointer,
  });

  /// El regalo que lleva.
  final Gift gift;

  /// El ancho de la fila.
  final double width;

  /// La tarjeta, para el sitio, la copia tenue y la que flota. Se construye
  /// con `floating` a verdadero para la que flota (sin toques ni vuelo).
  final Widget Function(bool floating) card;

  /// Avisa de dónde está el puntero (`null` al soltar).
  final BoardDragPointer? onPointer;

  /// La escala de la tarjeta alzada.
  static const double liftScale = 1.03;

  /// Cuánto se pulsa con el dedo antes de arrastrar (algo menos que los 500
  /// ms del sistema: el gesto es el de la app, no el de un menú contextual).
  static const Duration holdDelay = Duration(milliseconds: 350);

  @override
  State<BoardCardDraggable> createState() => _BoardCardDraggableState();
}

class _BoardCardDraggableState extends State<BoardCardDraggable> {
  late final BoardDragData _data = BoardDragData(widget.gift);
  double? _height;
  bool _measureScheduled = false;

  @override
  void didUpdateWidget(BoardCardDraggable oldWidget) {
    super.didUpdateWidget(oldWidget);
    _data.gift = widget.gift;
  }

  void _measureSoon() {
    if (_measureScheduled) {
      return;
    }
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) {
        return;
      }
      final box = context.findRenderObject();
      if (box is RenderBox && box.hasSize && box.size.height != _height) {
        setState(() => _height = box.size.height);
      }
    });
  }

  // Si hay un arrastre en curso que sale de esta tarjeta.
  bool _dragging = false;

  @override
  void dispose() {
    // La tarjeta puede desaparecer con el dedo aún pulsado (el regalo se borra
    // en otro móvil): Flutter ya no avisa del final y el puntero compartido se
    // quedaría fijo, con el tablero desplazándose solo.
    _clearDrag();
    super.dispose();
  }

  void _started() {
    if (!mounted) {
      return;
    }
    _dragging = true;
    final rect = globalRectOf(context);
    if (rect != null) {
      _data.size = rect.size;
    }
  }

  void _moved(DragUpdateDetails details) {
    if (mounted && _dragging) {
      widget.onPointer?.call(details.globalPosition);
    }
  }

  void _ended() => _clearDrag();

  void _clearDrag() {
    if (_dragging) {
      _dragging = false;
      widget.onPointer?.call(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    _measureSoon();
    final reduce = RegalosMotion.of(context).reduce;
    final t = RegalosTokens.of(context);
    final feedback = _Floating(
      width: widget.width,
      height: _height,
      reduce: reduce,
      shadow: t.shadow,
      child: widget.card(true),
    );
    final resting = widget.card(false);
    final ghost = Opacity(opacity: 0.4, child: widget.card(false));
    // Con el ratón, de inmediato; con el dedo y el lápiz, tras una pulsación
    // larga. Cada uno atiende solo a los suyos.
    return _TouchDraggable(
      data: _data,
      feedback: feedback,
      childWhenDragging: ghost,
      maxSimultaneousDrags: 1,
      onDragStarted: _started,
      onDragUpdate: _moved,
      onDragEnd: (_) => _ended(),
      onDraggableCanceled: (_, _) => _ended(),
      child: _MouseDraggable(
        data: _data,
        feedback: feedback,
        childWhenDragging: ghost,
        maxSimultaneousDrags: 1,
        onDragStarted: _started,
        onDragUpdate: _moved,
        onDragEnd: (_) => _ended(),
        onDraggableCanceled: (_, _) => _ended(),
        child: resting,
      ),
    );
  }
}

/// Arrastrable con el ratón, de inmediato.
class _MouseDraggable extends Draggable<BoardDragData> {
  const _MouseDraggable({
    required super.data,
    required super.feedback,
    required super.childWhenDragging,
    required super.maxSimultaneousDrags,
    required super.onDragStarted,
    required super.onDragUpdate,
    required super.onDragEnd,
    required super.onDraggableCanceled,
    required super.child,
  });

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) {
    return ImmediateMultiDragGestureRecognizer(
      supportedDevices: const <PointerDeviceKind>{PointerDeviceKind.mouse},
      allowedButtonsFilter: allowedButtonsFilter,
    )..onStart = onStart;
  }
}

/// Arrastrable con el dedo o el lápiz, tras una pulsación larga.
class _TouchDraggable extends LongPressDraggable<BoardDragData> {
  const _TouchDraggable({
    required super.data,
    required super.feedback,
    required super.childWhenDragging,
    required super.maxSimultaneousDrags,
    required super.onDragStarted,
    required super.onDragUpdate,
    required super.onDragEnd,
    required super.onDraggableCanceled,
    required super.child,
  }) : super(delay: BoardCardDraggable.holdDelay);

  @override
  DelayedMultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) {
    return DelayedMultiDragGestureRecognizer(
        delay: delay,
        supportedDevices: const <PointerDeviceKind>{
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
        },
        allowedButtonsFilter: allowedButtonsFilter,
      )
      ..onStart = (position) {
        final drag = onStart(position);
        if (drag != null && hapticFeedbackOnStart) {
          HapticFeedback.selectionClick();
        }
        return drag;
      };
  }
}

/// La tarjeta que sigue al puntero: se alza (escala y sombra) en 160 ms y
/// no recibe toques.
class _Floating extends StatelessWidget {
  const _Floating({
    required this.width,
    required this.height,
    required this.reduce,
    required this.shadow,
    required this.child,
  });

  final double width;
  final double? height;
  final bool reduce;
  final Color shadow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = RegalosMotion.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      // Se alza con `snap`; con «Reducir movimiento», la sombra se funde sin
      // escalar ni moverse.
      duration: motion.duration(RegalosSprings.snapDuration),
      curve: motion.curve(RegalosCurves.snap),
      builder: (context, v, child) => Transform.scale(
        scale: reduce ? 1 : 1 + (BoardCardDraggable.liftScale - 1) * v,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: RegalosShape.card,
            // La sombra del elemento alzado: `t.shadow`, como la celda que
            // vuela en Reparto.
            boxShadow: [
              BoxShadow(
                color: shadow.withValues(alpha: 0.16 * v.clamp(0.0, 1.0)),
                blurRadius: 24,
                offset: Offset(0, reduce ? 8 : 8 * v),
              ),
            ],
          ),
          child: child,
        ),
      ),
      child: SizedBox(width: width, height: height, child: child),
    );
  }
}
