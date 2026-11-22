import 'package:flutter/material.dart';

import '../theme/regalos_shape.dart';
import '../theme/regalos_tokens.dart';
import 'stroke_icon.dart';

/// Una nota informativa: un icono y una frase sobre el fondo suave, con radio 8.
/// Para avisar de algo que no es un error (de quién es un móvil, qué verá una
/// web, qué pasa con unos regalos); los errores y los peligros van en
/// [WarningBox] (`sheet_parts.dart`).
///
/// El icono es de 18 y crece con la letra del sistema, para que siga junto a la
/// primera línea. Con [action] (un botón de texto, por ejemplo «Entendido») va
/// debajo de la frase. La nota es un solo nodo para el lector de pantalla.
class SoftNote extends StatelessWidget {
  /// Crea la nota.
  const SoftNote({
    super.key,
    required this.icon,
    required this.text,
    this.action,
  });

  /// El dibujo del icono (un `AppIcons.*` o `SettingsIcons.*`).
  final StrokeIconBuilder icon;

  /// Lo que dice.
  final String text;

  /// Un botón bajo la frase, si hace falta.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final iconSize = MediaQuery.textScalerOf(context).scale(18);
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: t.soft,
          borderRadius: RegalosShape.card,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: StrokeIcon(
                icon,
                size: iconSize,
                color: t.textOnSoft,
                strokeWidth: 1.9,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: t.styles.meta.copyWith(color: t.textOnSoft),
                  ),
                  if (action != null) ...[const SizedBox(height: 4), action!],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
