import 'package:flutter/material.dart';

import '../motion/pop_in.dart';
import '../motion/stagger.dart';
import '../theme/regalos_shape.dart';
import '../theme/regalos_tokens.dart';
import 'stroke_icon.dart';

/// Estado vacío de una pantalla: icono en un cuadro pastel de radio 8, título
/// y una frase que dice qué aparecerá aquí.
///
/// Al aparecer, el cuadro entra con un rebote pequeño (`PopIn` desde 0,9)
/// y el título y la frase lo siguen, escalonados a 40 ms. Con «Reducir
/// movimiento» todo se funde en 150 ms.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final StrokeIconBuilder icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return StaggerScope(
      step: const Duration(milliseconds: 40),
      maxItems: 4,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PopIn(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: t.soft,
                      // Nada redondeado: un cuadro, no un círculo.
                      borderRadius: RegalosShape.card,
                    ),
                    child: SizedBox.square(
                      dimension: 64,
                      child: Center(
                        child: StrokeIcon(
                          icon,
                          size: 30,
                          color: t.ink,
                          strokeWidth: 1.7,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                StaggerItem(
                  index: 1,
                  dy: 8,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: t.styles.rowTitle.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                StaggerItem(
                  index: 2,
                  dy: 8,
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: t.styles.body.copyWith(color: t.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
