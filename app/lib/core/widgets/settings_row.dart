import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../layout/pane_scope.dart';
import '../layout/window_class.dart';
import '../motion/value_switcher.dart';
import '../theme/regalos_shape.dart';
import '../theme/regalos_tokens.dart';
import 'pane_list_row.dart';
import 'pointer_surface.dart';
import 'stroke_icon.dart';

/// Fila de lista de ajustes: icono opcional, título, descripción corta y, a
/// la derecha, el valor de ahora y una flecha, o el widget que se dé. Mide
/// 60 px o más (48 si no lleva descripción).
///
/// El [value] («3», «Sistema», «PIN») se cambia con un fundido en el que el
/// nuevo entra 8 px desde abajo; con «Reducir movimiento», solo el fundido.
///
/// Con [selected] (la fila elegida del panel de lista de Ajustes) pierde el
/// filete de debajo y se marca como elegida para los lectores de pantalla; el
/// fondo lo pone el recuadro que viaja por detrás (`SelectionScope`). Al pasar
/// el ratón se tiñe, y la mano sale en las que se pueden tocar. En el panel de
/// lista de un escritorio (desde 1280) las filas no llevan flecha.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.hint,
    this.value,
    this.onTap,
    this.trailing,
    this.leading,
    this.icon,
    this.danger = false,
    this.chevron = true,
    this.bordered = true,
    this.selected = false,
    this.hintMaxLines,
  });

  final String title;
  final String? hint;

  /// El valor de ahora, a la derecha y antes de la flecha.
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Widget? leading;

  /// Icono de trazo a la izquierda (si no se da [leading]).
  final StrokeIconBuilder? icon;

  /// Acción destructiva: título e icono en el rojo de aviso.
  final bool danger;

  /// Si una fila que se puede tocar lleva flecha.
  final bool chevron;
  final bool bordered;

  /// Si es la fila elegida de un panel de lista.
  final bool selected;

  /// Las líneas que ocupa [hint] como mucho; con las que no caben se acorta
  /// con puntos suspensivos (un enlace largo, en una sola línea). Sin valor,
  /// todas las que haga falta.
  final int? hintMaxLines;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final tappable = onTap != null;
    // En el panel de lista de un escritorio las filas son planas: la elegida
    // ya dice dónde se está, así que no llevan flecha (el valor se queda).
    final role = PaneScope.roleOf(context);
    final inList = role == PaneRole.list;
    // En el panel de detalle (la columna de Ajustes), los filetes y el
    // contenido van a 16 de cada borde, como el título y los botones.
    final inDetail = role == PaneRole.detail;
    final flat =
        inList && RegalosLayout.isDesktop(MediaQuery.sizeOf(context).width);
    final lead =
        leading ??
        (icon == null
            ? null
            : StrokeIcon(
                icon!,
                color: danger ? t.danger : t.textSecondary,
                strokeWidth: 1.9,
              ));
    // Con el texto muy grande el valor baja bajo el título: lado a lado se
    // quedaban sin sitio los dos («Aparie…» y el valor partido).
    final stacked =
        value != null && MediaQuery.textScalerOf(context).scale(14) >= 14 * 1.5;
    final row = Container(
      constraints: BoxConstraints(minHeight: hint == null ? 48 : 60),
      // En el panel de lista, el mismo relleno de lado que las filas de
      // Personas y Ocasiones (`PaneListRow`), sin filete de debajo.
      margin: inDetail ? const EdgeInsets.symmetric(horizontal: 16) : null,
      padding: inList
          ? const EdgeInsets.fromLTRB(12, 13, 12, 13)
          : inDetail
          ? const EdgeInsets.symmetric(vertical: 13)
          : const EdgeInsets.fromLTRB(16, 13, 12, 13),
      decoration: bordered && !selected && !inList
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: t.separator)),
            )
          : null,
      child: Row(
        children: [
          if (lead != null) ...[lead, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: inList
                      ? PaneListRow.nameStyle(t)
                            .copyWith(color: danger ? t.danger : null)
                      : danger
                      ? t.styles.rowTitle.copyWith(color: t.danger)
                      : t.styles.rowTitle,
                ),
                if (stacked)
                  ValueSwitcher(
                    dy: 8,
                    child: Text(
                      value!,
                      key: ValueKey<String>(value!),
                      style: t.styles.meta,
                    ),
                  ),
                if (hint != null)
                  Text(
                    hint!,
                    style: t.styles.meta,
                    maxLines: hintMaxLines,
                    overflow: hintMaxLines == null
                        ? null
                        : TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (value != null && !stacked) ...[
            const SizedBox(width: 12),
            // El valor ocupa lo suyo (como mucho media fila) y el título, el
            // resto. La fila mide lo que su panel (plan de tablet, norma 2) y
            // nunca más que la columna de Ajustes.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth:
                    math.min(
                      PaneScope.widthOf(context),
                      RegalosLayout.formColumn,
                    ) *
                    0.5,
              ),
              child: ValueSwitcher(
                dy: 8,
                alignment: Alignment.centerRight,
                child: Text(
                  value!,
                  key: ValueKey<String>(value!),
                  style: inList
                      ? t.styles.meta
                      : t.styles.meta.copyWith(fontSize: 14),
                  textAlign: TextAlign.end,
                ),
              ),
            ),
          ],
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          if (trailing == null && tappable && chevron && !flat) ...[
            if (value != null && !stacked) const SizedBox(width: 4),
            StrokeIcon(
              AppIcons.chevronRight,
              color: t.textSecondary,
              strokeWidth: 1.9,
            ),
          ],
        ],
      ),
    );
    if (!tappable) {
      return row;
    }
    return Semantics(
      container: true,
      button: true,
      selected: selected ? true : null,
      label: [title, ?value, ?hint].join('. '),
      excludeSemantics: true,
      onTap: onTap,
      child: PointerSurface(
        // El panel de lista de dos paneles lleva las filas con inset y el
        // recuadro de la elegida con esquinas: el tinte del ratón también,
        // elegida o no, para que no cambie de forma al elegirla. En el
        // móvil, filas de lado a lado y rectas.
        radius: selected || PaneScope.roleOf(context) == PaneRole.list
            ? RegalosShape.card
            : BorderRadius.zero,
        child: InkWell(onTap: onTap, child: row),
      ),
    );
  }
}
