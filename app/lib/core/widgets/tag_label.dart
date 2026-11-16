import 'package:flutter/material.dart';

import '../theme/regalos_tokens.dart';

/// Etiqueta pequeña con borde («Sorpresa», «Encargo», «Paga la casa»).
///
/// Es texto: no depende del color.
class TagLabel extends StatelessWidget {
  const TagLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: t.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: t.styles.meta),
    );
  }
}
