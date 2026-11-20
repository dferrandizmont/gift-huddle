import 'package:flutter/material.dart';

import '../layout/pane_scope.dart';
import '../theme/regalos_tokens.dart';
import 'fit_text.dart';
import 'stroke_icon.dart';

/// Cabecera de pantalla de las maquetas.
///
/// - Pantalla de pestaña: solo [title] (y [subtitle] opcional).
/// - Pantalla de detalle: con [onBack] aparece el botón de volver (44 px) y,
///   si hay [eyebrow], el nombre de la pantalla anterior en pequeño encima.
/// - Panel de detalle de dos paneles (`PaneRole.detail`): ni flecha ni el
///   nombre de encima, porque la lista está a la vista; salvo con
///   [keepBackInPane]. Si lleva subtítulo, el título se queda en la misma
///   línea que el de la lista (que mide 44 con el título centrado) y el
///   subtítulo cuelga debajo. Mide [kDetailHeaderHeight] como mínimo, para que
///   el contenido de debajo empiece a la misma altura en Personas, Ocasiones y
///   Ajustes: el título se queda en la línea del de la lista y los botones, a
///   su altura; con un adorno a la izquierda (el avatar), todo va centrado.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.footer,
    this.eyebrow,
    this.onBack,
    this.backLabel,
    this.leading,
    this.actions = const <Widget>[],
    this.compactTitle = false,
    this.keepBackInPane = false,
  });

  final String title;
  final String? subtitle;

  /// Sustituye a [subtitle] cuando el subtítulo tiene algo vivo (una cifra
  /// que rueda).
  final Widget? subtitleWidget;

  /// Una línea más debajo del subtítulo (el progreso de «persona completa»).
  final Widget? footer;
  final String? eyebrow;
  final VoidCallback? onBack;

  /// Etiqueta accesible del botón de volver («Volver a Ajustes»).
  final String? backLabel;

  /// Adorno a la izquierda del título (por ejemplo, el avatar de una persona).
  final Widget? leading;

  /// Botones de 44 px a la derecha del título.
  final List<Widget> actions;

  /// Título de 22 px (el editor), en vez de los 24 de las pantallas.
  final bool compactTitle;

  /// Si la flecha de volver se queda aunque la pantalla sea un panel de
  /// detalle (vino de otra pestaña y el atrás tiene a dónde volver).
  final bool keepBackInPane;

  /// La altura mínima de la cabecera de un panel de detalle.
  static const double kDetailHeaderHeight = 88;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final inDetail =
        !keepBackInPane && PaneScope.roleOf(context) == PaneRole.detail;
    final onBack = inDetail ? null : this.onBack;
    final eyebrow = inDetail ? null : this.eyebrow;
    final hasBack = onBack != null;
    // El título de una pantalla de lista va centrado en una fila de 44. En un
    // panel de detalle con subtítulo la columna pasa de 44 y el título subiría
    // 7 px: se le deja ese aire encima para que quede en la misma línea.
    final extraLine =
        subtitle != null || subtitleWidget != null || footer != null;
    // En un panel de detalle sin adorno, el título y los botones van arriba, en
    // la línea del título de la lista, y la cabecera deja el resto de su alto
    // mínimo debajo.
    final topAligned = inDetail && leading == null;
    final titleAlign = inDetail && (extraLine || topAligned)
        ? (44 -
                  (compactTitle
                              ? t.styles.screenTitleSmall
                              : t.styles.screenTitle)
                          .fontSize! *
                      (compactTitle
                              ? t.styles.screenTitleSmall
                              : t.styles.screenTitle)
                          .height!) /
              2
        : 0.0;
    final body = Padding(
      padding: hasBack
          ? const EdgeInsets.fromLTRB(4, 8, 8, 4)
          : const EdgeInsets.fromLTRB(16, 8, 14, 6),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: hasBack ? 0 : 44),
        child: Row(
          crossAxisAlignment: topAligned
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            if (hasBack)
              Semantics(
                container: true,
                button: true,
                label: backLabel,
                excludeSemantics: true,
                onTap: onBack,
                child: SizedBox.square(
                  dimension: 44,
                  child: InkResponse(
                    onTap: onBack,
                    customBorder: const CircleBorder(),
                    child: Center(
                      child: StrokeIcon(
                        AppIcons.back,
                        color: t.text,
                        strokeWidth: 1.9,
                      ),
                    ),
                  ),
                ),
              ),
            if (hasBack) const SizedBox(width: 4),
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: titleAlign),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (eyebrow != null) Text(eyebrow, style: t.styles.caption),
                    Semantics(
                      header: true,
                      child: FitText(
                        title,
                        style: compactTitle
                            ? t.styles.screenTitleSmall
                            : t.styles.screenTitle,
                      ),
                    ),
                    if (subtitleWidget != null)
                      subtitleWidget!
                    else if (subtitle != null)
                      Text(subtitle!, style: t.styles.meta),
                    ?footer,
                  ],
                ),
              ),
            ),
            for (final action in actions)
              topAligned
                  ? SizedBox(height: 44, child: Center(child: action))
                  : action,
          ],
        ),
      ),
    );
    return inDetail
        ? ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kDetailHeaderHeight),
            child: body,
          )
        : body;
  }
}
