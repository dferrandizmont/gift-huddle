import 'package:flutter/widgets.dart';

import '../theme/regalos_motion.dart';

/// El eje compartido horizontal entre los pasos del primer uso (§3.3 y
/// «momento M» de la guía de movimiento).
///
/// Al cambiar [index]:
/// - el paso que se va se desplaza 24 px hacia atrás (o hacia delante, al
///   volver) y se funde en 150 ms con `fold`;
/// - el que llega viene desde el lado contrario, a 24 px, con `snap`, y su
///   opacidad sube en `Interval(0, 0.5)`.
///
/// Con «Reducir movimiento» se cruzan con un fundido de 150 ms, sin
/// desplazarse. Cada paso necesita una clave distinta: la pone el widget con
/// el [index], o con [childKey] si el índice puede cambiar sin que cambie el
/// contenido (la persona elegida en dos paneles).
///
/// Con [travel] y [duration] se afina para otros usos. Con [fadeOnly] (el
/// detalle de dos paneles) no hay eje: el que se va desaparece en el acto y el
/// que llega se funde en 120 ms con `easeOut`, sin trasladarse, para que
/// elegir otra persona se note inmediato. Con [animate] en falso cambia de
/// contenido en el acto.
class SharedAxisSwitcher extends StatefulWidget {
  /// Crea el cambiador.
  const SharedAxisSwitcher({
    super.key,
    required this.index,
    required this.child,
    this.childKey,
    this.travel = defaultTravel,
    this.duration,
    this.animate = true,
    this.fadeOnly = false,
  });

  /// El paso actual; si sube, el eje avanza, y si baja, retrocede.
  final int index;

  /// El contenido del paso actual.
  final Widget child;

  /// La clave del paso, si no ha de ser el [index].
  final Object? childKey;

  /// Cuánto se desplazan los pasos.
  final double travel;

  /// Lo que dura el cambio; por defecto, `snap` al entrar y `fold` al salir.
  final Duration? duration;

  /// Si el cambio se anima. En falso, el contenido nuevo sustituye al viejo
  /// sin tiempo de por medio.
  final bool animate;

  /// Si el cambio es solo un fundido de lo que entra (sin eje ni traslación y
  /// sin fundir lo que sale): [fadeDuration].
  final bool fadeOnly;

  /// Lo que tarda en fundirse el contenido que entra con [fadeOnly].
  static const Duration fadeDuration = Duration(milliseconds: 120);

  /// Cuánto se desplazan los pasos del primer uso.
  static const double defaultTravel = 24;

  @override
  State<SharedAxisSwitcher> createState() => _SharedAxisSwitcherState();
}

class _SharedAxisSwitcherState extends State<SharedAxisSwitcher> {
  // Hacia dónde va el eje: 1 avanza (el actual sale a la izquierda).
  double _direction = 1;

  @override
  void didUpdateWidget(SharedAxisSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _direction = widget.index > oldWidget.index ? 1 : -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduce = RegalosMotion.of(context).reduce;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final custom = widget.duration;
    final fadeOnly = widget.fadeOnly;
    return AnimatedSwitcher(
      duration: !widget.animate
          ? Duration.zero
          : reduce
          ? RegalosMotion.fade
          : fadeOnly
          ? SharedAxisSwitcher.fadeDuration
          : custom ?? RegalosSprings.snapDuration,
      reverseDuration: !widget.animate
          ? Duration.zero
          : reduce
          ? RegalosMotion.fade
          : fadeOnly
          ? Duration.zero
          : custom ?? RegalosCurves.foldDuration,
      switchInCurve: reduce
          ? Curves.linear
          : fadeOnly
          ? Curves.easeOut
          : RegalosCurves.snap,
      switchOutCurve: reduce
          ? Curves.linear
          : fadeOnly
          ? Curves.linear
          : RegalosCurves.fold,
      // El que se va se queda arriba, pegado al borde; no se centra.
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) {
        if (reduce || fadeOnly) {
          // Solo se funde lo que entra; lo que sale ya no está (duración 0) o,
          // con «Reducir movimiento», se funde con él.
          return FadeTransition(opacity: animation, child: child);
        }
        return _AxisTransition(
          animation: animation,
          direction: rtl ? -_direction : _direction,
          travel: widget.travel,
          child: child,
        );
      },
      child: KeyedSubtree(
        key: widget.childKey != null
            ? ValueKey<Object>(widget.childKey!)
            : ValueKey<int>(widget.index),
        child: widget.child,
      ),
    );
  }
}

/// El eje de un paso: se desplaza [travel] píxeles y se funde. La opacidad va
/// con `FadeTransition` (sin reconstruir el paso) y mira el sentido de la
/// animación: al entrar sube en la primera mitad y al salir baja con ella.
class _AxisTransition extends StatefulWidget {
  const _AxisTransition({
    required this.animation,
    required this.direction,
    required this.travel,
    required this.child,
  });

  final Animation<double> animation;
  final double direction;
  final double travel;
  final Widget child;

  @override
  State<_AxisTransition> createState() => _AxisTransitionState();
}

class _AxisTransitionState extends State<_AxisTransition> {
  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _AxisOpacity(widget.animation),
    child: AnimatedBuilder(
      animation: widget.animation,
      child: widget.child,
      builder: (context, child) {
        final v = widget.animation.value;
        // Con la animación yendo hacia atrás, el paso se está yendo.
        final leaving = widget.animation.status == AnimationStatus.reverse;
        final dx =
            (leaving ? -widget.direction : widget.direction) *
            widget.travel *
            (1 - v);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
    ),
  );
}

/// La opacidad de un paso según el sentido de su animación: al entrar sube en
/// la primera mitad y al salir baja con ella. El valor del muelle puede pasarse
/// de 1 un instante: se recorta.
class _AxisOpacity extends Animation<double>
    with AnimationWithParentMixin<double> {
  _AxisOpacity(this.parent);

  @override
  final Animation<double> parent;

  @override
  double get value {
    final v = parent.value.clamp(0.0, 1.0);
    return parent.status == AnimationStatus.reverse
        ? v
        : const Interval(0, 0.5).transform(v);
  }
}
