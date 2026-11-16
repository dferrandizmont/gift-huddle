import 'package:flutter/material.dart';

import '../layout/window_class.dart';
import '../motion/elastic_indicator.dart';
import '../motion/haptics.dart';
import '../theme/regalos_motion.dart';
import '../theme/regalos_shape.dart';
import '../theme/regalos_tokens.dart';
import 'regalos_nav_bar.dart';
import 'stroke_icon.dart';

/// Raíl lateral de la navegación principal (la guía de diseño para tablet,
/// §3.1): sustituye a la barra inferior desde 600 dp de ancho.
///
/// Mide 80 de ancho (más el margen seguro de su lado), con el fondo de la
/// pantalla y un filete de 1 px hacia el contenido. Los destinos empiezan a
/// 16 del margen seguro superior, separados 10. Cada uno es una zona táctil
/// de 72 × 56 (o más alta si el texto crece) con el icono de trazo sobre un
/// recuadro pastel de 56 × 30 y radio 8, y la etiqueta de 12 debajo, en
/// negrita y en tinta si está activo.
///
/// El recuadro es el mismo de la barra, viajando en vertical: se estira hacia
/// el destino nuevo y se recoge al llegar (el borde que va delante sale con
/// `snap` y el de atrás lo sigue 70 ms después), sin cambiar de ancho. Con
/// «Reducir movimiento» no viaja: cada destino lo funde en 150 ms.
///
/// Va al principio de la fila (a la izquierda; a la derecha en idiomas de
/// derecha a izquierda) y ocupa todo el alto que le dan.
///
/// En la web de escritorio por bandas (dentro de [DesktopBandsScope]) el raíl
/// forma una sola banda con la lista: fondo `t.surface` y sin filete. Un
/// [footer] (el estado de guardado de la web) va abajo, centrado.
class RegalosNavRail extends StatelessWidget {
  const RegalosNavRail({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.semanticLabel,
    this.footer,
  });

  /// Lo que va abajo del raíl, si hay algo.
  final Widget? footer;

  final List<NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final String semanticLabel;

  /// Ancho y alto del recuadro del destino activo.
  static const double boxWidth = 56;
  static const double boxHeight = RegalosNavBar.pillHeight;

  /// La zona táctil de un destino: ancho fijo y alto mínimo.
  static const double destinationWidth = 72;
  static const double destinationMinHeight = 56;

  /// Del margen seguro superior al primer destino, y de un destino al
  /// siguiente.
  static const double topInset = 16;
  static const double gap = 10;

  /// Espacio sobre el recuadro y bajo la etiqueta, dentro del destino.
  static const double _padding = 4;

  /// Del recuadro a la etiqueta.
  static const double _labelGap = 3;

  static const double _labelSize = 12;

  /// El alto de cada destino con el texto a escala [scaler]: los 56 de
  /// siempre o lo que pida la etiqueta. Todos miden lo mismo, y así el
  /// recuadro sabe dónde descansa cada uno.
  static double _destinationHeight(TextStyle label, TextScaler scaler) {
    final line = scaler.scale(_labelSize) * (label.height ?? 1.25);
    final needed = _padding + boxHeight + _labelGap + line + _padding;
    return needed <= destinationMinHeight
        ? destinationMinHeight
        : needed.ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final motion = RegalosMotion.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final banded = DesktopBands.maybeOf(context) != null;
    final height = _destinationHeight(
      t.styles.navLabel,
      MediaQuery.textScalerOf(context),
    );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: Material(
        color: banded ? t.surface : t.bg,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: banded
                ? null
                : BorderDirectional(end: BorderSide(color: t.separator)),
          ),
          child: SafeArea(
            // El lado del contenido no lleva margen: ahí va el filete.
            left: !rtl,
            right: rtl,
            child: SizedBox(
              width: RegalosLayout.railWidth,
              child: Padding(
                padding: const EdgeInsets.only(top: topInset),
                child: Stack(
                  children: [
                    if (!motion.reduce)
                      ElasticIndicator(
                        key: const ValueKey('nav-indicator'),
                        axis: Axis.vertical,
                        index: selectedIndex,
                        origin: _padding,
                        pitch: height + gap,
                        extent: boxHeight,
                        crossOffset: (RegalosLayout.railWidth - boxWidth) / 2,
                        crossExtent: boxWidth,
                      ),
                    Align(
                      alignment: Alignment.topCenter,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < destinations.length; i++) ...[
                            if (i > 0) const SizedBox(height: gap),
                            _RailItem(
                              destination: destinations[i],
                              selected: i == selectedIndex,
                              height: height,
                              onTap: () {
                                // El clic llega con el recuadro, no con el dedo.
                                if (i != selectedIndex) {
                                  context.haptics.selection(
                                    after: context.hapticArrival,
                                  );
                                }
                                onSelected(i);
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (footer != null)
                      Align(alignment: Alignment.bottomCenter, child: footer),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.height,
    required this.onTap,
  });

  final NavDestination destination;
  final bool selected;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final motion = RegalosMotion.of(context);
    final color = selected ? t.ink : t.textSecondary;
    final labelStyle = t.styles.navLabel.copyWith(
      fontSize: RegalosNavRail._labelSize,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      color: color,
    );

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: destination.label,
      onTap: onTap,
      excludeSemantics: true,
      child: SizedBox(
        width: RegalosNavRail.destinationWidth,
        height: height,
        child: InkWell(
          onTap: onTap,
          borderRadius: RegalosShape.chip,
          child: Padding(
            padding: const EdgeInsets.only(top: RegalosNavRail._padding),
            child: Column(
              children: [
                // Con «Reducir movimiento» el recuadro de cada destino se
                // funde; si no, lo pinta el raíl y viaja.
                AnimatedContainer(
                  duration: motion.reduce ? RegalosMotion.fade : Duration.zero,
                  width: RegalosNavRail.boxWidth,
                  height: RegalosNavRail.boxHeight,
                  decoration: BoxDecoration(
                    color: motion.reduce && selected
                        ? t.fill
                        : t.fill.withValues(alpha: 0),
                    borderRadius: RegalosShape.chip,
                  ),
                  alignment: Alignment.center,
                  child: StrokeIcon(
                    destination.icon,
                    size: RegalosSizes.navIconSize,
                    color: color,
                    strokeWidth: RegalosSizes.navIconStroke,
                  ),
                ),
                const SizedBox(height: RegalosNavRail._labelGap),
                // Una etiqueta que no cabe en los 72 se encoge entera en vez
                // de cortarse («Repartiment», o cualquiera con el texto al
                // 130 %).
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topCenter,
                    child: Text(
                      destination.label,
                      maxLines: 1,
                      softWrap: false,
                      textAlign: TextAlign.center,
                      style: labelStyle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
