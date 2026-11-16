import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/regalos_tokens.dart';
import 'stroke_icon.dart';

/// El botón «Añadir regalo» de los dos paneles de escritorio: el mismo en la
/// cabecera de Personas y de Ocasiones y en sus vacíos.
///
/// Relleno con el acento sólido (la tinta con texto claro en claro; el pastel
/// con su texto oscuro en oscuro), no pastel con tinta, que parece apagado. El
/// acento es el del tema de quien lo pinta: en Ocasiones, el de la ocasión.
class DesktopAddGiftButton extends StatelessWidget {
  /// Crea el botón.
  const DesktopAddGiftButton({super.key, required this.onPressed});

  /// Lo que hace al pulsarlo (abre el editor).
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final background = t.isDark ? t.fill : t.ink;
    final foreground = t.isDark ? t.onFill : t.bg;
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        minimumSize: const Size(44, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      icon: StrokeIcon(
        AppIcons.plus,
        size: 18,
        color: foreground,
        strokeWidth: 2.2,
      ),
      label: Text(l10n.giftAdd),
    );
  }
}
