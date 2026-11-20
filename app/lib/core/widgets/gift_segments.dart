import 'package:flutter/material.dart';

import '../theme/regalos_shape.dart';
import '../theme/regalos_tokens.dart';

/// Barra segmentada de una persona: un segmento pequeño por regalo, relleno
/// con [color] cuando el regalo ya está comprado (o en un estado posterior) y
/// con la pista gris cuando todavía falta comprarlo.
///
/// Es decorativa: el resumen en texto va al lado y en la etiqueta de la fila.
class GiftSegments extends StatelessWidget {
  const GiftSegments({
    super.key,
    required this.total,
    required this.done,
    required this.color,
  });

  /// Número de regalos (segmentos).
  final int total;

  /// Cuántos están comprados o más allá; se rellenan los primeros.
  final int done;

  /// Color del relleno (la tinta de la persona).
  final Color color;

  /// El segmento más estrecho que se sigue distinguiendo; por debajo, la barra
  /// pasa a ser una sola, proporcional.
  static const double minSegmentWidth = 3;

  /// El ancho y el hueco de cada segmento con [total] segmentos en
  /// [available]: 18 y 3 si caben; si no, el hueco baja a 2 y a 1 y los
  /// segmentos se estrechan; y si ya no llegan a [minSegmentWidth], `null`
  /// (barra proporcional).
  static ({double width, double gap})? layoutFor(int total, double available) {
    if (total <= 0) {
      return (width: RegalosSizes.segmentWidth, gap: RegalosSizes.segmentGap);
    }
    final natural =
        total * RegalosSizes.segmentWidth +
        (total - 1) * RegalosSizes.segmentGap;
    if (natural <= available) {
      return (width: RegalosSizes.segmentWidth, gap: RegalosSizes.segmentGap);
    }
    for (final gap in const [2.0, 1.0]) {
      final width = (available - (total - 1) * gap) / total;
      if (width >= minSegmentWidth) {
        return (width: width, gap: gap);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return ExcludeSemantics(
      // Segmentos de 18 como mucho (la ficha): con muchos regalos se
      // estrechan, con el hueco calculado, para caber en el sitio; si ya no
      // se distinguen, una barra proporcional.
      child: LayoutBuilder(
        builder: (context, box) {
          final available = box.maxWidth.isFinite ? box.maxWidth : 1e9;
          final layout = layoutFor(total, available);
          if (layout == null) {
            final fraction = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
            return SizedBox(
              key: const ValueKey('segments-bar'),
              width: available,
              height: RegalosSizes.segmentHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: t.track,
                  borderRadius: RegalosShape.hairline,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FractionallySizedBox(
                    widthFactor: fraction,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: RegalosShape.hairline,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            );
          }
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < total; i++) ...[
                if (i > 0) SizedBox(width: layout.gap),
                SizedBox(
                  width: layout.width,
                  child: Container(
                    key: ValueKey(i < done ? 'segment-full' : 'segment-empty'),
                    height: RegalosSizes.segmentHeight,
                    decoration: BoxDecoration(
                      color: i < done ? color : t.track,
                      borderRadius: RegalosShape.hairline,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
