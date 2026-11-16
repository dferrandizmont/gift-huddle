import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/regalos_motion.dart';

/// La física de los carruseles (§2.4 de la guía de movimiento):
/// una `PageScrollPhysics` cuyo asentamiento de página es el muelle `snap` de
/// toda la app.
///
/// Con [reduce] («Reducir movimiento») la página se asienta sin rebote y casi
/// de golpe: un muelle críticamente amortiguado que acaba en unos 150 ms.
class RegalosPagePhysics extends PageScrollPhysics {
  /// Crea la física.
  const RegalosPagePhysics({super.parent, this.reduce = false});

  /// Si el sistema pide reducir el movimiento.
  final bool reduce;

  /// El muelle crítico de «Reducir movimiento».
  static const SpringDescription reducedSpring = SpringDescription(
    mass: 1,
    stiffness: 1600,
    damping: 80,
  );

  @override
  RegalosPagePhysics applyTo(ScrollPhysics? ancestor) =>
      RegalosPagePhysics(parent: buildParent(ancestor), reduce: reduce);

  @override
  SpringDescription get spring => reduce ? reducedSpring : RegalosSprings.snap;
}

/// La física del carrusel de una tarjeta a la vista con la siguiente asomando
/// (`PageController.viewportFraction` menor que 1 y `padEnds` apagado).
///
/// Con esa configuración la última página no puede llegar al borde izquierdo
/// del visor: el desplazamiento se acaba antes y la última tarjeta se queda
/// pegada a la derecha, con la anterior asomando por la izquierda. Aquí el
/// visor tiene una página de más, vacía, que da el recorrido que falta, y esta
/// física no deja pasar de la última tarjeta real ([count] páginas): cada una,
/// también la primera y la última, se asienta con su borde izquierdo en el
/// margen.
class LeftAlignedPagePhysics extends RegalosPagePhysics {
  /// Crea la física de un carrusel de [count] tarjetas y [viewportFraction].
  const LeftAlignedPagePhysics({
    super.parent,
    super.reduce,
    required this.count,
    required this.viewportFraction,
  });

  /// Las tarjetas reales (sin la página vacía del final).
  final int count;

  /// La fracción del visor que ocupa cada página.
  final double viewportFraction;

  @override
  LeftAlignedPagePhysics applyTo(ScrollPhysics? ancestor) =>
      LeftAlignedPagePhysics(
        parent: buildParent(ancestor),
        reduce: reduce,
        count: count,
        viewportFraction: viewportFraction,
      );

  double _pageSize(ScrollMetrics position) =>
      position.viewportDimension * viewportFraction;

  /// El desplazamiento de la última tarjeta real.
  double _lastOffset(ScrollMetrics position) =>
      (count - 1).clamp(0, count) * _pageSize(position);

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    final upper = _lastOffset(position);
    if (value < position.pixels &&
        position.pixels <= position.minScrollExtent) {
      return value - position.pixels;
    }
    if (upper <= position.pixels && position.pixels < value) {
      return value - position.pixels;
    }
    if (position.pixels < upper && upper < value) {
      return value - upper;
    }
    if (value < position.minScrollExtent &&
        position.minScrollExtent < position.pixels) {
      return value - position.minScrollExtent;
    }
    return 0;
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final upper = _lastOffset(position);
    // Fuera del recorrido (por una fuerza que no es el dedo), a su sitio.
    if (position.pixels > upper) {
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        upper,
        math.min(0.0, velocity),
        tolerance: toleranceFor(position),
      );
    }
    final tolerance = toleranceFor(position);
    final size = _pageSize(position);
    var page = position.pixels / size;
    if (velocity < -tolerance.velocity) {
      page -= 0.5;
    } else if (velocity > tolerance.velocity) {
      page += 0.5;
    }
    final target = (page.roundToDouble() * size).clamp(
      position.minScrollExtent,
      upper,
    );
    if (target != position.pixels) {
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        target,
        velocity,
        tolerance: tolerance,
      );
    }
    return null;
  }
}
