import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/layout/content_width.dart';
import '../../../core/layout/pane_scope.dart';
import '../../../core/layout/window_class.dart';
import '../../../core/theme/regalos_tokens.dart';

/// Lo que se separa del filete que parte los dos paneles la columna del
/// detalle de Ajustes en una tablet (hasta 1279 de ventana), cuando sobra
/// sitio.
const double kSettingsDetailLeading = 95;

/// El ancho de la columna de Ajustes en el panel de detalle de un escritorio
/// (desde 1280 de ventana), en vez de los 560 de `RegalosLayout.formColumn`.
const double kSettingsDesktopColumn = 640;

/// Lo que se separa del filete la columna del detalle de Ajustes en un
/// escritorio, cuando sobra sitio.
const double kSettingsDesktopLeading = 72;

/// Si [context] es el panel de detalle de un escritorio (desde 1280 de
/// ventana): la única situación en la que la columna mide 640 y va a la
/// izquierda con 72 px de margen.
bool _desktopDetail(BuildContext context) =>
    PaneScope.roleOf(context) == PaneRole.detail &&
    RegalosLayout.isDesktop(MediaQuery.sizeOf(context).width);

/// El ancho de la columna de Ajustes en el panel de [context]: 640 en el
/// detalle de un escritorio y 560 (`RegalosLayout.formColumn`) en cualquier
/// otro sitio.
double settingsColumnWidthOf(BuildContext context) =>
    _desktopDetail(context) ? kSettingsDesktopColumn : RegalosLayout.formColumn;

/// El margen que queda a cada lado de la columna de Ajustes centrada en su
/// panel (la guía de diseño para tablet, §2.2 y T2).
///
/// Cero mientras la columna quepa entera: en el móvil no cambia nada. El
/// sitio es el del panel (`PaneScope.widthOf`), no el de la ventana, menos
/// los márgenes seguros de los lados, que el `SafeArea` de la pantalla ya
/// quita.
double settingsGutterOf(BuildContext context) =>
    settingsGuttersOf(context).left;

/// Los márgenes izquierdo y derecho de la columna de Ajustes.
///
/// Centrada en su panel, salvo en el panel de detalle de dos paneles: ahí va
/// alineada a la izquierda y el resto del ancho queda a la derecha. En un
/// escritorio mide 640 y empieza a [kSettingsDesktopLeading] (72) px del
/// filete; en una tablet, 560 y [kSettingsDetailLeading] (95). En el móvil y
/// en un panel único, como siempre.
({double left, double right}) settingsGuttersOf(BuildContext context) {
  final available =
      PaneScope.widthOf(context) - MediaQuery.paddingOf(context).horizontal;
  final desktop = _desktopDetail(context);
  final column = settingsColumnWidthOf(context);
  final centered = ContentWidth.gutter(available, column);
  if (centered == 0 || PaneScope.roleOf(context) != PaneRole.detail) {
    return (left: centered, right: centered);
  }
  final left = math.min(
    centered,
    desktop ? kSettingsDesktopLeading : kSettingsDetailLeading,
  );
  return (left: left, right: available - column - left);
}

/// El `padding` de la lista de una pantalla de Ajustes: [top] y [bottom], y a
/// los lados [inset] más el margen que centra la columna.
///
/// Va en el `padding` de la lista y no en un envoltorio para que se siga
/// desplazando al arrastrar por los márgenes y para que el árbol sea el mismo
/// a cualquier ancho (girar no pierde la posición).
EdgeInsets settingsColumnPadding(
  BuildContext context, {
  double inset = 0,
  double top = 0,
  double bottom = 24,
}) {
  final gutters = settingsGuttersOf(context);
  return EdgeInsets.fromLTRB(
    inset + gutters.left,
    top,
    inset + gutters.right,
    bottom,
  );
}

/// La cabecera de un apartado de Ajustes cuando va apilado con los demás en
/// la columna del tablero de la web (no lleva flecha de volver): el título y,
/// si hay, una frase de apoyo.
class EmbeddedSectionHeader extends StatelessWidget {
  /// Crea la cabecera.
  const EmbeddedSectionHeader({super.key, required this.title, this.subtitle});

  /// El título del apartado.
  final String title;

  /// La frase de apoyo bajo el título.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: t.styles.screenTitleSmall),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: t.styles.meta),
          ],
        ],
      ),
    );
  }
}
