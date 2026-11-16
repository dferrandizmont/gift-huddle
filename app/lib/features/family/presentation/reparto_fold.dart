import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../../core/theme/regalos_motion.dart';

/// Un elemento de una lista que puede entrar o salir plegándose.
class FoldEntry<T> {
  /// Crea el elemento.
  FoldEntry(this.item, {this.entering = false, this.leaving = false});

  /// Lo que se pinta (el último valor que tuvo; un fantasma conserva el
  /// suyo mientras se pliega).
  T item;

  /// Llegó después de pintar la lista por primera vez: entra con muelle.
  bool entering;

  /// Ya no está en la lista y se está plegando.
  bool leaving;
}

/// Lleva la cuenta de qué filas entran y qué filas salen de una lista, para
/// que la que sale se pliegue en vez de desaparecer de golpe.
///
/// La que sale se conserva como fantasma (`leaving`) en su sitio hasta que su
/// [FoldTransition] termina y avisa con [gone].
class FoldTracker<T> {
  /// Crea el seguimiento con la lista de partida, sin animar nada.
  FoldTracker(this._id, Iterable<T> initial)
    : entries = [for (final item in initial) FoldEntry<T>(item)];

  final String Function(T) _id;

  /// Lo que se pinta ahora, con los fantasmas en su sitio.
  List<FoldEntry<T>> entries;

  /// Pone al día la lista: lo nuevo entra, lo que falta se pliega.
  void update(List<T> items) {
    final old = entries;
    final byId = {for (final e in old) _id(e.item): e};
    final fresh = {for (final i in items) _id(i)};
    final result = <FoldEntry<T>>[
      for (final item in items)
        (byId[_id(item)] ?? FoldEntry<T>(item, entering: true))
          ..item = item
          ..leaving = false,
    ];
    for (var k = 0; k < old.length; k++) {
      final e = old[k];
      if (fresh.contains(_id(e.item))) {
        continue;
      }
      e.leaving = true;
      e.entering = false;
      result.insert(math.min(k, result.length), e);
    }
    entries = result;
  }

  /// La entrada ya se pintó: no vuelve a animarse si se reconstruye.
  void settle() {
    for (final e in entries) {
      e.entering = false;
    }
  }

  /// Quita el fantasma de [id] cuando ya se ha plegado.
  void gone(String id) =>
      entries.removeWhere((e) => e.leaving && _id(e.item) == id);

  /// Si queda alguna fila plegándose.
  bool get hasLeaving => entries.any((e) => e.leaving);
}

/// Envuelve una fila para que entre y salga plegándose.
///
/// - Entra con el muelle `snap` (alto de 0 a 1) y el contenido crece de 0,9 a
///   1 con `bounce`: vuelve «con muelle».
/// - Sale en 180 ms con `fastOutSlowIn`, sin rebote, y avisa con [onGone].
/// - Con «Reducir movimiento» solo se funde, en 150 ms, sin tocar el alto.
class FoldTransition extends StatefulWidget {
  /// Crea la envoltura.
  const FoldTransition({
    super.key,
    required this.entering,
    required this.leaving,
    required this.onGone,
    required this.child,
  });

  /// Si la fila acaba de llegar.
  final bool entering;

  /// Si la fila se va.
  final bool leaving;

  /// Se llama cuando la fila ya se ha plegado del todo.
  final VoidCallback onGone;

  /// La fila.
  final Widget child;

  @override
  State<FoldTransition> createState() => _FoldTransitionState();
}

class _FoldTransitionState extends State<FoldTransition>
    with TickerProviderStateMixin {
  /// Alto visible y opacidad: 1 es la fila entera.
  late final AnimationController _size = AnimationController.unbounded(
    vsync: this,
    value: widget.entering ? 0 : 1,
  );

  /// Escala del contenido al volver (rebote).
  late final AnimationController _pop = AnimationController.unbounded(
    vsync: this,
    value: widget.entering ? 0.9 : 1,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;
    if (widget.leaving) {
      _leave();
    } else if (widget.entering) {
      _enter();
    }
  }

  @override
  void didUpdateWidget(FoldTransition old) {
    super.didUpdateWidget(old);
    if (widget.leaving && !old.leaving) {
      _leave();
    } else if (!widget.leaving && old.leaving) {
      _enter();
    }
  }

  @override
  void dispose() {
    _size.dispose();
    _pop.dispose();
    super.dispose();
  }

  void _enter() {
    if (RegalosMotion.of(context).reduce) {
      _pop.value = 1;
      _size.animateTo(1, duration: RegalosMotion.fade, curve: Curves.linear);
      return;
    }
    _size.animateWith(SpringSimulation(RegalosSprings.snap, _size.value, 1, 0));
    _pop
      ..stop()
      ..value = 0.9;
    _pop.animateWith(SpringSimulation(RegalosSprings.bounce, 0.9, 1, 0));
  }

  void _leave() {
    final reduce = RegalosMotion.of(context).reduce;
    _pop.value = 1;
    _size
        .animateTo(
          0,
          duration: reduce ? RegalosMotion.fade : RegalosCurves.foldDuration,
          curve: reduce ? Curves.linear : RegalosCurves.fold,
        )
        .then((_) {
          if (mounted && widget.leaving) {
            widget.onGone();
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    final reduce = RegalosMotion.of(context).reduce;
    return AnimatedBuilder(
      animation: Listenable.merge([_size, _pop]),
      child: widget.child,
      builder: (context, child) {
        final s = _size.value;
        final opacity = s.clamp(0.0, 1.0);
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: reduce ? 1 : math.max(s, 0),
            child: Opacity(
              opacity: opacity,
              child: reduce
                  ? child
                  : Transform.scale(
                      scale: _pop.value,
                      alignment: Alignment.topCenter,
                      child: child,
                    ),
            ),
          ),
        );
      },
    );
  }
}
