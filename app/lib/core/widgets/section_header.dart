import 'package:flutter/material.dart';

import '../layout/pane_scope.dart';
import '../theme/regalos_tokens.dart';

/// Cabecera de sección: título en negrita a la izquierda y un dato opcional a
/// la derecha («24 dic», «4 regalos»). Con [bordered] lleva el filete inferior
/// de las listas.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.bordered = true,
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 6),
  });

  final String title;
  final String? trailing;
  final bool bordered;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    // El ancho del panel, no el de la ventana (plan de tablet, norma 2).
    final width = PaneScope.widthOf(context);
    // Con letra muy grande el título y lo de la derecha no caben a la vez: se
    // apilan en vez de partir el título letra a letra.
    final stacked = MediaQuery.textScalerOf(context).scale(16) > 16 * 1.5;
    return Container(
      padding: padding,
      decoration: bordered
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: t.separator)),
            )
          : null,
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: t.styles.sectionTitle),
                ),
                if (trailing != null) Text(trailing!, style: t.styles.meta),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(title, style: t.styles.sectionTitle),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: width * 0.55),
                    child: Text(
                      trailing!,
                      style: t.styles.meta,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
