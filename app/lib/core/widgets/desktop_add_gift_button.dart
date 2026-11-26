import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/regalos_tokens.dart';
import 'stroke_icon.dart';

/// El botón «Añadir regalo» de los dos paneles de escritorio: el mismo en la
/// cabecera de Personas y de Ocasiones y en sus vacíos.
///
/// Relleno pastel del acento con el texto en tinta (el mismo de «Guardar» y del
/// botón flotante del móvil; en oscuro, el pastel oscuro con su texto claro).
/// La tinta como relleno (casi negra) pesaba demasiado. El acento es el del
/// tema de quien lo pinta: en Ocasiones, el de la ocasión.
class DesktopAddGiftButton extends StatelessWidget {
  /// Crea el botón.
  const DesktopAddGiftButton({super.key, required this.onPressed, this.label});

  /// Lo que hace al pulsarlo (abre el editor).
  final VoidCallback onPressed;

  /// Otro texto en lugar de «Añadir regalo» («Añadir deseo»).
  final String? label;

  /// El alto de los botones de la cabecera de los paneles de escritorio: el de
  /// los botones rellenos del tema («Guardar», «Añadir persona»), el de
  /// «Cambiar fecha» y el de los botones de icono del tablero. Medía 40 y se
  /// veía más pequeño que todos ellos.
  static const double height = 48;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final background = t.fill;
    final foreground = t.onFill;
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        // 48 exactos también en Windows, macOS y Linux: su densidad compacta
        // le quitaba 8 al alto mínimo.
        visualDensity: VisualDensity.standard,
        minimumSize: const Size(44, height),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        textStyle: t.styles.label,
      ),
      icon: StrokeIcon(
        AppIcons.plus,
        size: 16,
        color: foreground,
        strokeWidth: 1.9,
      ),
      label: Text(label ?? l10n.giftAdd),
    );
  }
}
