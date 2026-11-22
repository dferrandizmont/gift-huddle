import 'package:flutter/material.dart';

import '../theme/regalos_tokens.dart';

/// Etiqueta pequeña con borde («Sorpresa», «Encargo», «Paga la casa»).
///
/// Es texto: no depende del color.
class TagLabel extends StatelessWidget {
  const TagLabel(this.label, {super.key, this.hint});

  final String label;

  /// El texto largo de una etiqueta corta («Pendiente» → «Pendiente de tu
  /// móvil»): ayuda con el ratón y lo que lee el lector de pantalla.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final tag = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: t.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: t.styles.meta),
    );
    final long = hint;
    if (long == null) return tag;
    return Semantics(
      label: long,
      excludeSemantics: true,
      child: Tooltip(message: long, excludeFromSemantics: true, child: tag),
    );
  }
}
