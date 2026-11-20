import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion/elastic_indicator.dart';
import '../motion/haptics.dart';
import '../theme/regalos_motion.dart';
import '../theme/regalos_shape.dart';
import '../theme/regalos_tokens.dart';
import 'stroke_icon.dart';

/// Un destino de la navegación principal: de la barra inferior o del raíl
/// lateral (`RegalosNavRail`).
class NavDestination {
  const NavDestination({required this.icon, required this.label});

  final StrokeIconBuilder icon;
  final String label;
}

/// Barra inferior del diseño (la de la maqueta de Reparto): 68 px (o más si
/// el texto crece), filete superior, icono de trazo y etiqueta. El destino
/// activo se lee por un recuadro pastel de radio 8 (64 × 30) detrás del icono,
/// que se estira hacia el destino nuevo y se recoge al llegar (el borde que va
/// delante sale con `snap` y el de atrás lo sigue 70 ms después), y por la
/// etiqueta en negrita y en tinta. Cada destino mide al menos 44 px.
///
/// Con el texto grande las cuatro etiquetas comparten el mismo tamaño: el
/// mayor con el que cabe entera la más larga, nunca cada una el suyo.
///
/// Con «Reducir movimiento» el recuadro no se desliza: cada destino lo funde
/// en 150 ms.
///
/// Es la navegación de la ventana compacta; desde 600 dp de ancho la sustituye
/// `RegalosNavRail`, con el mismo recuadro viajando en vertical.
class RegalosNavBar extends StatelessWidget {
  const RegalosNavBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.semanticLabel,
  });

  final List<NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final String semanticLabel;

  /// Alto y ancho del recuadro del destino activo.
  static const double pillHeight = 30;
  static const double pillWidth = 64;

  /// Espacio sobre el recuadro (el contenido va centrado en los 68 px).
  static const double _topInset = 9;

  /// Margen horizontal de cada destino (por lado).
  static const double _sidePad = 4;

  /// El estilo de la etiqueta, a tamaño 12 sin encoger.
  static TextStyle labelStyleOf(
    RegalosTokens t, {
    required bool selected,
    required Color color,
  }) => t.styles.navLabel.copyWith(
    fontSize: 12,
    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
    color: color,
  );

  /// El tamaño de fuente común a todas las etiquetas: 12, o el mayor menor
  /// que 12 con el que la más larga cabe entera en [slot]. Se mide con el
  /// tamaño real, en negrita (lo más ancho que llega a pintarse) y con el
  /// escalado de texto del sistema, y se repite hasta que cabe, porque el
  /// escalado no tiene por qué ser lineal. No hay suelo: nunca hace falta
  /// encoger una etiqueta por su cuenta ni cortarla.
  @visibleForTesting
  static double labelFontSize(
    BuildContext context,
    List<NavDestination> destinations,
    double slot,
  ) {
    final t = RegalosTokens.of(context);
    final base = DefaultTextStyle.of(context).style
        .merge(labelStyleOf(t, selected: true, color: t.ink));
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final bold = MediaQuery.boldTextOf(context);
    final room = slot - 2 * _sidePad - 1;
    double widest(double size) {
      var style = base.copyWith(fontSize: size);
      if (bold) {
        style = style.merge(const TextStyle(fontWeight: FontWeight.bold));
      }
      var w = 0.0;
      for (final d in destinations) {
        final painter = TextPainter(
          text: TextSpan(text: d.label, style: style),
          textDirection: direction,
          textScaler: scaler,
          locale: locale,
          maxLines: 1,
        )..layout();
        w = math.max(w, painter.width);
        painter.dispose();
      }
      return w;
    }

    var size = 12.0;
    if (room <= 0) {
      return size;
    }
    for (var i = 0; i < 24; i++) {
      final w = widest(size);
      if (w <= room) {
        break;
      }
      // Un poco por debajo de la proporción, para converger sin pasarse.
      size *= math.min(0.98, room / w);
    }
    return size;
  }

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final motion = RegalosMotion.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: Material(
        color: t.bg,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: t.separator)),
          ),
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: RegalosSizes.navBarHeight,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final slot = constraints.maxWidth / destinations.length;
                  final labelSize = labelFontSize(context, destinations, slot);
                  return Stack(
                    children: [
                      if (!motion.reduce)
                        ElasticIndicator(
                          key: const ValueKey('nav-indicator'),
                          axis: Axis.horizontal,
                          index: selectedIndex,
                          origin: (slot - pillWidth) / 2,
                          pitch: slot,
                          extent: pillWidth,
                          crossOffset: _topInset,
                          crossExtent: pillHeight,
                        ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < destinations.length; i++)
                            Expanded(
                              child: _NavItem(
                                destination: destinations[i],
                                selected: i == selectedIndex,
                                labelSize: labelSize,
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
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.labelSize,
    required this.onTap,
  });

  final NavDestination destination;
  final bool selected;

  /// Tamaño de fuente común de las etiquetas (12 si todas caben).
  final double labelSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final motion = RegalosMotion.of(context);
    final color = selected ? t.ink : t.textSecondary;
    final base = RegalosNavBar.labelStyleOf(
      t,
      selected: selected,
      color: color,
    );
    final labelStyle = base.copyWith(fontSize: labelSize);

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: destination.label,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: RegalosShape.chip,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: RegalosSizes.navBarHeight - 1,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              RegalosNavBar._sidePad,
              RegalosNavBar._topInset,
              RegalosNavBar._sidePad,
              RegalosNavBar._topInset,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Con «Reducir movimiento» el recuadro de cada destino se
                // funde; si no, lo pinta la barra y se desliza.
                AnimatedContainer(
                  duration: motion.reduce ? RegalosMotion.fade : Duration.zero,
                  width: RegalosNavBar.pillWidth,
                  height: RegalosNavBar.pillHeight,
                  decoration: BoxDecoration(
                    color: motion.reduce && selected
                        ? t.selection
                        : t.selection.withValues(alpha: 0),
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
                const SizedBox(height: 3),
                // Con el texto grande todas las etiquetas comparten el tamaño
                // que deja caber la más larga (`labelFontSize`): ninguna se
                // encoge por su cuenta ni se corta.
                Text(
                  destination.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: labelStyle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
