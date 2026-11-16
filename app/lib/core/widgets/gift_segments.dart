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

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return ExcludeSemantics(
      child: Row(
        children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: RegalosSizes.segmentGap),
            Expanded(
              child: Container(
                key: ValueKey(i < done ? 'segment-full' : 'segment-empty'),
                height: RegalosSizes.segmentHeight,
                decoration: BoxDecoration(
                  color: i < done ? color : t.track,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
