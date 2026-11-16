import 'package:flutter/material.dart';

import '../theme/regalos_motion.dart';
import 'sheen.dart';

/// Un aviso para [HighlightFlash]: «ilumina la fila [id]». [seq] distingue
/// dos avisos seguidos sobre la misma fila.
@immutable
class HighlightCue {
  /// Crea el aviso.
  const HighlightCue(this.id, this.seq);

  /// La fila a iluminar.
  final String id;

  /// Número de orden del aviso.
  final int seq;

  @override
  bool operator ==(Object other) =>
      other is HighlightCue && other.id == id && other.seq == seq;

  @override
  int get hashCode => Object.hash(id, seq);
}

/// El canal por el que una lista avisa a sus filas de cuál iluminar.
class HighlightSignal extends ValueNotifier<HighlightCue?> {
  /// Crea el canal vacío.
  HighlightSignal() : super(null);

  int _seq = 0;

  /// Pide iluminar la fila [id].
  void highlight(String id) => value = HighlightCue(id, ++_seq);
}

/// Una fila que se ilumina al guardarla (§2.2 y «2.1 y 2.2, más vistosos»):
/// el fondo pasa del pastel de la persona al fondo en 1200 ms con `easeOut`
/// y, a los 140 ms, una banda de luz cruza la fila ([Sheen]).
///
/// Si la fila no está a la vista, la lista se desplaza hasta ella con `snap`
/// (375 ms) antes del destello. Con «Reducir movimiento»: solo color, 150 ms
/// de subida y 600 ms de bajada, sin brillo ni desplazamiento animado.
class HighlightFlash extends StatefulWidget {
  /// Crea la fila.
  const HighlightFlash({
    super.key,
    required this.id,
    required this.signal,
    required this.color,
    required this.child,
    this.withSheen = true,
    this.reveal = true,
  });

  /// Identifica la fila (el id de su regalo).
  final String id;

  /// Por dónde llegan los avisos.
  final HighlightSignal signal;

  /// El pastel del destello.
  final Color color;

  /// Si pasa el brillo por encima.
  final bool withSheen;

  /// Si lleva la lista hasta la fila cuando no está a la vista. Una fila
  /// repetida en la misma pantalla (la misma persona en dos bloques) lo pone a
  /// `false` en las copias que no son la que se quiere ver.
  final bool reveal;

  /// La fila.
  final Widget child;

  @override
  State<HighlightFlash> createState() => _HighlightFlashState();
}

class _HighlightFlashState extends State<HighlightFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    animationBehavior: AnimationBehavior.preserve,
  );
  final GlobalKey<SheenState> _sheen = GlobalKey<SheenState>();
  bool _reduce = false;

  @override
  void initState() {
    super.initState();
    widget.signal.addListener(_onCue);
  }

  @override
  void didUpdateWidget(HighlightFlash oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.signal != widget.signal) {
      oldWidget.signal.removeListener(_onCue);
      widget.signal.addListener(_onCue);
    }
  }

  @override
  void dispose() {
    widget.signal.removeListener(_onCue);
    _controller.dispose();
    super.dispose();
  }

  void _onCue() {
    if (widget.signal.value?.id != widget.id) {
      return;
    }
    // Tras el fotograma: la fila nueva acaba de insertarse.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _reduce = RegalosMotion.of(context).reduce;
      if (widget.reveal) {
        Scrollable.ensureVisible(
          context,
          duration: _reduce ? Duration.zero : RegalosSprings.snapDuration,
          curve: RegalosCurves.snap,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
      _controller
        ..duration = _reduce
            ? const Duration(milliseconds: 750)
            : const Duration(milliseconds: 1200)
        ..forward(from: 0);
      if (widget.withSheen) {
        _sheen.currentState?.play(delay: const Duration(milliseconds: 140));
      }
    });
    // El primer fotograma puede no llegar si no hay nada que repintar.
    WidgetsBinding.instance.scheduleFrame();
  }

  /// Cuánto del pastel se ve (1 es entero).
  double _strength() {
    final v = _controller.value;
    if (_reduce) {
      // 150 ms de subida (20 %) y 600 ms de bajada.
      return v < 0.2 ? v / 0.2 : (1 - (v - 0.2) / 0.8);
    }
    return 1 - Curves.easeOut.transform(v);
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.withSheen
        ? Sheen(key: _sheen, child: widget.child)
        : widget.child;
    return AnimatedBuilder(
      animation: _controller,
      child: child,
      builder: (context, child) {
        // El envoltorio se queda siempre, para no reconstruir la fila.
        return ColoredBox(
          color: _controller.isAnimating
              ? widget.color.withValues(
                  alpha: widget.color.a * _strength().clamp(0.0, 1.0),
                )
              : const Color(0x00000000),
          child: child,
        );
      },
    );
  }
}
