import 'package:flutter/material.dart';

import '../theme/regalos_shape.dart';
import '../theme/regalos_tokens.dart';
import 'stroke_icon.dart';

/// Botón de la cabecera de una pantalla de pestaña (el «+» de Personas y de
/// Ocasiones): 40 × 40 con borde fino y radio 8, icono de trazo de 22.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.size = 44,
  });

  /// Lado de la zona que responde: 44 en el móvil, 48 en el tablero de la web.
  /// Con 48 el botón se dibuja de 48 (como «Añadir regalo» y «Cambiar fecha»,
  /// sus vecinos en la cabecera); con 44 o menos, de 40.
  final double size;

  final StrokeIconBuilder icon;

  /// Etiqueta accesible («Añadir persona»).
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      // Con el ratón, la ayuda de siempre: el mismo texto que dice el lector.
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: SizedBox.square(
          dimension: size,
          child: Center(
            child: Material(
              color: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: RegalosShape.button,
                side: BorderSide(color: t.chipBorder),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: SizedBox.square(
                  dimension: size >= 48 ? 48 : 40,
                  child: Center(
                    child: StrokeIcon(
                      icon,
                      size: 22,
                      color: t.text,
                      strokeWidth: RegalosSizes.navIconStroke,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
