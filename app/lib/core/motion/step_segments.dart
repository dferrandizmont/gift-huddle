import 'package:flutter/widgets.dart';

import '../theme/regalos_motion.dart';
import '../theme/regalos_tokens.dart';

/// El indicador de pasos del primer uso (§3.3 y «momento M» de
/// la guía de movimiento): [count] segmentos rectos de 4 px de alto
/// y radio 2, con 4 px entre ellos.
///
/// El relleno de cada segmento es un `Transform.scale(scaleX)` desde la
/// izquierda: se llena con `snap` (375 ms) al llegar a su paso y se vacía en
/// 180 ms con `fold` al volver. Con «Reducir movimiento» el segmento cambia de
/// color con un fundido de 150 ms.
class StepSegments extends StatelessWidget {
  /// Crea el indicador. Están llenos los [filled] primeros segmentos.
  const StepSegments({
    super.key,
    required this.count,
    required this.filled,
    required this.semanticLabel,
  });

  /// Cuántos segmentos hay.
  final int count;

  /// Cuántos están llenos, de izquierda a derecha.
  final int filled;

  /// La etiqueta accesible («Paso 2 de 5»).
  final String semanticLabel;

  /// Alto de cada segmento.
  static const double height = 4;

  /// Radio de las esquinas de cada segmento.
  static const double radius = 2;

  /// Espacio entre un segmento y el siguiente.
  static const double gap = 4;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: gap),
            Expanded(child: _Segment(filled: i < filled)),
          ],
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.filled});

  final bool filled;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final reduce = RegalosMotion.of(context).reduce;
    final radius = BorderRadius.circular(StepSegments.radius);
    final track = DecoratedBox(
      decoration: BoxDecoration(color: t.track, borderRadius: radius),
      child: const SizedBox(
        height: StepSegments.height,
        width: double.infinity,
      ),
    );
    if (reduce) {
      return Stack(
        children: [
          track,
          AnimatedOpacity(
            duration: RegalosMotion.fade,
            opacity: filled ? 1 : 0,
            child: DecoratedBox(
              decoration: BoxDecoration(color: t.ink, borderRadius: radius),
              child: const SizedBox(
                height: StepSegments.height,
                width: double.infinity,
              ),
            ),
          ),
        ],
      );
    }
    return ClipRRect(
      borderRadius: radius,
      child: Stack(
        children: [
          track,
          TweenAnimationBuilder<double>(
            tween: Tween<double>(end: filled ? 1 : 0),
            // Se llena con `snap` y se vacía con `fold`, sin rebote.
            duration: filled
                ? RegalosSprings.snapDuration
                : RegalosCurves.foldDuration,
            curve: filled ? RegalosCurves.snap : RegalosCurves.fold,
            builder: (context, v, child) => Transform.scale(
              scaleX: v.clamp(0.0, 1.0),
              alignment: Alignment.centerLeft,
              child: child,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(color: t.ink),
              child: const SizedBox(
                height: StepSegments.height,
                width: double.infinity,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
