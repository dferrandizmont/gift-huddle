import 'package:flutter/material.dart';

import '../motion/haptics.dart';
import '../theme/regalos_motion.dart';
import '../theme/regalos_shape.dart';
import '../theme/regalos_tokens.dart';
import 'spring_pulse.dart';

/// Pinta el adorno de una celda de [ChoiceGrid] (un icono, la forma de un
/// estado). [color] es el del texto de la celda: `onFill` si está elegida.
typedef ChoiceLeadingBuilder = Widget Function(Color color, bool selected);

/// Una opción de [ChoiceGrid].
class ChoiceGridItem {
  /// Crea la opción.
  const ChoiceGridItem({
    required this.label,
    required this.leading,
    required this.selected,
    required this.onTap,
  });

  /// El nombre; también es la etiqueta de accesibilidad.
  final String label;

  /// El adorno de la izquierda.
  final ChoiceLeadingBuilder leading;

  /// Si es la elegida.
  final bool selected;

  /// Se llama al tocarla.
  final VoidCallback onTap;
}

/// Selector de una opción entre varias, en una rejilla de columnas del mismo
/// ancho: el tipo de una ocasión, el estado de un regalo.
///
/// Las celdas son rectángulos de radio 8 con el adorno a la izquierda y el
/// nombre, que pasa a otra línea si no cabe; las de una misma fila miden lo
/// mismo de alto. Lleva tantas columnas (hasta [maxColumns]) como dejen caber
/// todos los nombres en dos líneas sin partir ninguna palabra; si no, dos, y
/// con la letra muy grande, una.
///
/// La elegida se rellena con el acento y pasa a negrita, como los filtros
/// (§2.6 de la guía de movimiento): el relleno cambia con `snap`,
/// el color del texto con `soft` y el adorno rebota con `bounce`. El radio es
/// fijo. Con «Reducir movimiento» todo es un fundido de 150 ms.
class ChoiceGrid extends StatelessWidget {
  /// Crea la rejilla.
  const ChoiceGrid({
    super.key,
    required this.items,
    this.leadingSize = 20,
    this.leadingGap = 8,
    this.maxColumns = 3,
  });

  /// Las opciones, en orden de lectura.
  final List<ChoiceGridItem> items;

  /// Lado del adorno, para saber cuánto ancho le queda al nombre.
  final double leadingSize;

  /// Hueco entre el adorno y el nombre.
  final double leadingGap;

  /// Columnas como mucho.
  final int maxColumns;

  /// Hueco entre celdas, en los dos sentidos.
  static const double gap = 8;

  /// Alto mínimo de una celda: la zona táctil.
  static const double minCellHeight = 44;

  /// Margen interior a los lados: con el borde, el contenido queda a 8 px.
  static const double _padding = 7;

  /// Margen interior arriba y abajo: un nombre de dos líneas cabe justo en
  /// el alto mínimo, así que todas las filas miden lo mismo.
  static const double _paddingV = 3;

  /// El estilo del nombre; [selected] lo pone en negrita.
  static TextStyle labelStyle(RegalosTokens t, {required bool selected}) =>
      t.styles.metaStrong.copyWith(
        color: selected ? t.onFill : t.text,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      );

  /// Cuántas columnas caben en [width]: las más posibles (hasta [maxColumns])
  /// con todos los [labels] en dos líneas como mucho y sin partir palabras.
  /// Si no hay ninguna así, dos mientras no se parta ninguna palabra; si no,
  /// una. Mide con [style], que debe ser el de la celda elegida (el más ancho).
  static int columnsFor({
    required double width,
    required List<String> labels,
    required TextStyle style,
    required TextScaler textScaler,
    required TextDirection textDirection,
    required double leadingSize,
    double leadingGap = 8,
    int maxColumns = 3,
  }) {
    // Lo que no es texto en una celda: márgenes, borde, adorno y su hueco.
    final chrome = _padding * 2 + 2 + leadingSize + leadingGap;
    final painters = [
      for (final label in labels)
        TextPainter(
          text: TextSpan(text: label, style: style),
          textDirection: textDirection,
          textScaler: textScaler,
        ),
    ];
    // La palabra más ancha de cada nombre. Se mide sin límite de ancho: con
    // él, una palabra ya partida cuenta como dos.
    final words = [
      for (final painter in painters) (painter..layout()).minIntrinsicWidth,
    ];
    // Cuántas líneas ocupa el nombre más largo con [columns] columnas, o
    // `null` si alguna palabra no cabe entera.
    int? linesWith(int columns) {
      final textWidth = (width - gap * (columns - 1)) / columns - chrome;
      if (textWidth <= 0) {
        return null;
      }
      var lines = 0;
      for (final (i, painter) in painters.indexed) {
        if (words[i] > textWidth) {
          return null;
        }
        painter.layout(maxWidth: textWidth);
        final count = painter.computeLineMetrics().length;
        if (count > lines) {
          lines = count;
        }
      }
      return lines;
    }

    try {
      for (var columns = maxColumns; columns >= 2; columns--) {
        final lines = linesWith(columns);
        if (lines != null && lines <= 2) {
          return columns;
        }
      }
      return maxColumns >= 2 && linesWith(2) != null ? 2 : 1;
    } finally {
      for (final painter in painters) {
        painter.dispose();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = columnsFor(
          width: constraints.maxWidth,
          labels: [for (final item in items) item.label],
          style: labelStyle(t, selected: true),
          textScaler: textScaler,
          textDirection: textDirection,
          leadingSize: leadingSize,
          leadingGap: leadingGap,
          maxColumns: maxColumns,
        );
        final rows = <Widget>[];
        for (var start = 0; start < items.length; start += columns) {
          if (start > 0) {
            rows.add(const SizedBox(height: gap));
          }
          rows.add(
            // Todas las celdas de la fila, tan altas como la más alta.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = start; i < start + columns; i++) ...[
                    if (i > start) const SizedBox(width: gap),
                    Expanded(
                      child: i < items.length
                          ? _ChoiceCell(item: items[i], leadingGap: leadingGap)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        return Column(mainAxisSize: MainAxisSize.min, children: rows);
      },
    );
  }
}

class _ChoiceCell extends StatefulWidget {
  const _ChoiceCell({required this.item, required this.leadingGap});

  final ChoiceGridItem item;
  final double leadingGap;

  @override
  State<_ChoiceCell> createState() => _ChoiceCellState();
}

class _ChoiceCellState extends State<_ChoiceCell> {
  final _pulse = GlobalKey<SpringPulseState>();

  @override
  void didUpdateWidget(_ChoiceCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // El adorno solo rebota al elegirla, no al dejar de estarlo.
    if (widget.item.selected && !oldWidget.item.selected) {
      _pulse.currentState?.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final motion = RegalosMotion.of(context);
    final item = widget.item;
    final selected = item.selected;
    final style = ChoiceGrid.labelStyle(t, selected: selected);
    // Elegir otra celda vibra con un clic; volver a tocar la elegida, no.
    void tap() {
      if (!selected) {
        context.haptics.selection();
      }
      item.onTap();
    }

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: item.label,
      onTap: tap,
      excludeSemantics: true,
      child: InkWell(
        onTap: tap,
        borderRadius: RegalosShape.chip,
        child: AnimatedContainer(
          duration: motion.duration(RegalosSprings.snapDuration),
          curve: motion.curve(RegalosCurves.snap),
          constraints: const BoxConstraints(
            minHeight: ChoiceGrid.minCellHeight,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: ChoiceGrid._padding,
            vertical: ChoiceGrid._paddingV,
          ),
          decoration: BoxDecoration(
            color: selected ? t.fill : t.fill.withValues(alpha: 0),
            border: Border.all(color: selected ? t.fill : t.chipBorder),
            borderRadius: RegalosShape.chip,
          ),
          child: Row(
            children: [
              SpringPulse(
                key: _pulse,
                child: item.leading(selected ? t.onFill : t.text, selected),
              ),
              SizedBox(width: widget.leadingGap),
              Expanded(
                child: Stack(
                  alignment: AlignmentDirectional.centerStart,
                  children: [
                    // Reserva el alto del nombre en negrita: elegir una celda
                    // no cambia el alto de su fila.
                    Opacity(
                      opacity: 0,
                      child: RichText(
                        text: TextSpan(
                          text: item.label,
                          style: ChoiceGrid.labelStyle(t, selected: true),
                        ),
                        textScaler: MediaQuery.textScalerOf(context),
                      ),
                    ),
                    Positioned.fill(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: AnimatedDefaultTextStyle(
                          duration: motion.duration(
                            RegalosSprings.softDuration,
                          ),
                          curve: motion.curve(RegalosCurves.soft),
                          style: style,
                          child: Text(item.label),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
