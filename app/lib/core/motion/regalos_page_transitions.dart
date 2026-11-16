import 'package:flutter/material.dart';

import '../layout/pane_scope.dart';
import '../theme/regalos_motion.dart';

/// La transición de pantallas de Android (§1.1 de
/// la guía de movimiento).
///
/// - Entra la pantalla nueva: sube desde el 25 % del ancho de su panel
///   (`PaneScope.widthOf`: la ventana en el móvil, el área de contenido junto
///   al raíl) hasta 0 con `snap` (375 ms) y se funde en el primer 45 %.
/// - La de debajo no retrocede (ni se mueve ni se encoge): solo se oscurece un
///   6 % con el velo.
/// - Al volver (220 ms) hace el mismo recorrido al revés, sin muelle, con
///   `fold`.
/// - Con «Reducir movimiento» solo hay un fundido de 150 ms: nada se traslada
///   ni se oscurece.
///
/// iOS sigue con `CupertinoPageTransitionsBuilder` (trae el gesto de volver
/// deslizando).
class RegalosPageTransitionsBuilder extends PageTransitionsBuilder {
  /// Crea el constructor de la transición.
  const RegalosPageTransitionsBuilder();

  @override
  Duration get transitionDuration => RegalosSprings.snapDuration;

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 220);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _RegalosTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      reduce: RegalosMotion.of(context).reduce,
      child: child,
    );
  }
}

class _RegalosTransition extends StatefulWidget {
  const _RegalosTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.reduce,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final bool reduce;
  final Widget child;

  @override
  State<_RegalosTransition> createState() => _RegalosTransitionState();
}

class _RegalosTransitionState extends State<_RegalosTransition> {
  late CurvedAnimation _primary;
  late CurvedAnimation _secondary;
  late CurvedAnimation _fade;

  @override
  void initState() {
    super.initState();
    _build();
  }

  void _build() {
    _primary = CurvedAnimation(
      parent: widget.animation,
      curve: RegalosCurves.snap,
      reverseCurve: RegalosCurves.fold,
    );
    _secondary = CurvedAnimation(
      parent: widget.secondaryAnimation,
      curve: RegalosCurves.snap,
      reverseCurve: RegalosCurves.fold,
    );
    // Entrando, en el primer 45 %; con reducir, 150 ms de los 375 (el 40 %). Al
    // volver, el fundido corre en la ida del recorrido para que dure lo mismo.
    _fade = CurvedAnimation(
      parent: widget.animation,
      curve: Interval(0, widget.reduce ? 0.4 : 0.45),
      reverseCurve: widget.reduce
          ? const Interval(0.32, 1)
          : const Interval(0, 1),
    );
  }

  void _dispose() {
    _primary.dispose();
    _secondary.dispose();
    _fade.dispose();
  }

  @override
  void didUpdateWidget(_RegalosTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation ||
        oldWidget.secondaryAnimation != widget.secondaryAnimation ||
        oldWidget.reduce != widget.reduce) {
      _dispose();
      _build();
    }
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reduce) {
      return FadeTransition(opacity: _fade, child: widget.child);
    }
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final sign = rtl ? -1.0 : 1.0;
    return AnimatedBuilder(
      animation: Listenable.merge([_primary, _secondary, _fade]),
      child: widget.child,
      builder: (context, child) {
        // El ancho del panel en el que entra (el área de contenido, sin el
        // raíl), no el de la ventana; sin panel por encima es la ventana.
        final width = PaneScope.widthOf(context);
        // Entrada: del 25 % del ancho a 0. La de debajo no se mueve ni se
        // encoge: solo se oscurece un 6 % con el velo.
        final enter = sign * 0.25 * width * (1 - _primary.value);
        final veil = 0.06 * _secondary.value.clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(enter, 0),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              FadeTransition(opacity: _fade, child: child),
              if (veil > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(color: Color.fromRGBO(0, 0, 0, veil)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
