import 'package:flutter/material.dart';

import '../../../core/theme/regalos_tokens.dart';
import '../../../l10n/app_localizations.dart';

/// La etiqueta «Yo» que acompaña al nombre de la persona dueña de este móvil
/// (ADR 0004) en Reparto: la rejilla, la lista por ocasión y su ficha.
///
/// Es discreta: texto pequeño en gris dentro de un contorno fino de radio 4.
/// No oculta ni cambia nada; solo dice quién eres tú en la lista.
class SelfTag extends StatelessWidget {
  /// Crea la etiqueta; [compact] es la de la rejilla, más pequeña.
  const SelfTag({super.key, this.compact = false});

  /// Si es la versión pequeña (junto al nombre de una fila de la rejilla).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: t.chipBorder),
        borderRadius: const BorderRadius.all(Radius.circular(4)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 4 : 6,
          vertical: compact ? 0 : 1,
        ),
        child: Text(
          AppLocalizations.of(context).repartoSelfTag,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          style: t.styles.caption.copyWith(
            fontSize: compact ? 10.5 : 12,
            height: 1.25,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
