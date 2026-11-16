import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../motion/value_switcher.dart';
import '../theme/gift_status.dart';
import '../theme/regalos_tokens.dart';
import 'gift_status_l10n.dart';
import 'giver_dot.dart';
import 'status_checkbox.dart';
import 'pointer_surface.dart';
import 'tag_label.dart';

/// Fila de regalo de la lista: casilla de estado, nombre y una línea con
/// quien regala, el precio y el estado en texto.
///
/// Con [columnsFrom], si la fila mide eso o más de ancho (el detalle de
/// escritorio) pasa a columnas: casilla, nombre (lo que sobre), quién regala
/// ([giverColumn]), precio a la derecha ([priceColumn]) y estado
/// ([statusColumn]). Por debajo, la fila de siempre.
class GiftRow extends StatelessWidget {
  const GiftRow({
    super.key,
    required this.name,
    required this.giverName,
    required this.status,
    this.giverColorIndex,
    this.price,
    this.note,
    this.onTap,
    this.onStatusTap,
    this.onStatusLongPress,
    this.tags = const <String>[],
    this.bordered = true,
    this.columnsFrom,
  });

  final String name;
  final String giverName;
  final int? giverColorIndex;
  final GiftStatus status;

  /// Precio ya formateado, o `null` si no hay.
  final String? price;

  /// Segunda línea opcional («Lo pidió Aritz»).
  final String? note;
  final VoidCallback? onTap;
  final VoidCallback? onStatusTap;
  final VoidCallback? onStatusLongPress;

  /// Etiquetas pequeñas junto al nombre («Sorpresa», «Encargo»).
  final List<String> tags;
  final bool bordered;

  /// El ancho de fila desde el que va en columnas; `null`, nunca.
  final double? columnsFrom;

  /// El ancho de la columna de quién regala.
  static const double giverColumn = 160;

  /// El ancho de la columna del precio (alineado a la derecha).
  static const double priceColumn = 112;

  /// El ancho de la columna del estado.
  static const double statusColumn = 120;

  /// El importe de [price] sin lo previsto: «49,99 €» de «49,99 € (previsto
  /// 55 €)».
  static String _amount(String price) {
    final at = price.indexOf(' (');
    return at < 0 ? price : price.substring(0, at);
  }

  /// Lo previsto de [price] («previsto 55 €», sin los paréntesis), o `null` si
  /// no lo lleva.
  static String? _planned(String price) {
    final at = price.indexOf(' (');
    if (at < 0) {
      return null;
    }
    final rest = price.substring(at + 2);
    return rest.endsWith(')') ? rest.substring(0, rest.length - 1) : rest;
  }

  @override
  Widget build(BuildContext context) {
    final from = columnsFrom;
    if (from == null) {
      return _build(context, columns: false);
    }
    return LayoutBuilder(
      builder: (context, box) => _build(context, columns: box.maxWidth >= from),
    );
  }

  Widget _build(BuildContext context, {required bool columns}) {
    final t = RegalosTokens.of(context);
    final l10n = AppLocalizations.of(context);

    final meta = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        GiverDot(colorIndex: giverColorIndex),
        // Al editar el regalo, lo que cambia (quién regala, el precio) se
        // cruza con un fundido corto en vez de saltar.
        ValueSwitcher(
          child: Text(
            giverName,
            key: ValueKey(giverName),
            style: t.styles.meta,
          ),
        ),
        if (price != null) ...[
          const Text('·', semanticsLabel: ''),
          ValueSwitcher(
            child: Text(price!, key: ValueKey(price), style: t.styles.meta),
          ),
        ],
        const Text('·', semanticsLabel: ''),
        ValueSwitcher(
          child: Text(
            status.label(l10n),
            key: ValueKey(status),
            style: t.styles.metaStrong,
          ),
        ),
      ],
    );

    final title = tags.isEmpty
        ? ValueSwitcher(
            child: Text(name, key: ValueKey(name), style: t.styles.rowTitle),
          )
        : Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              ValueSwitcher(
                child: Text(
                  name,
                  key: ValueKey(name),
                  style: t.styles.rowTitle,
                ),
              ),
              for (final tag in tags) TagLabel(tag),
            ],
          );

    final Widget body;
    if (columns) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  if (note != null) Text(note!, style: t.styles.meta),
                ],
              ),
            ),
            SizedBox(
              width: giverColumn,
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  children: [
                    GiverDot(colorIndex: giverColorIndex),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ValueSwitcher(
                        child: Text(
                          giverName,
                          key: ValueKey(giverName),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.styles.meta,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: priceColumn,
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: price == null
                      ? null
                      : ValueSwitcher(
                          child: Column(
                            key: ValueKey(price),
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              // «49,99 € (previsto 55 €)»: el importe arriba y
                              // lo previsto debajo, en pequeño y entero.
                              Text(
                                _amount(price!),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.styles.metaStrong,
                              ),
                              if (_planned(price!) != null)
                                Text(
                                  _planned(price!)!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.styles.caption,
                                ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
            SizedBox(
              width: statusColumn,
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: ValueSwitcher(
                  child: Text(
                    status.label(l10n),
                    key: ValueKey(status),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.styles.metaStrong,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            DefaultTextStyle.merge(style: t.styles.meta, child: meta),
            if (note != null) Text(note!, style: t.styles.meta),
          ],
        ),
      );
    }

    return Container(
      constraints: BoxConstraints(minHeight: columns ? 56 : 60),
      padding: const EdgeInsets.only(left: 4, right: 16),
      decoration: bordered
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: t.separator)),
            )
          : null,
      child: Row(
        children: [
          StatusCheckbox(
            status: status,
            itemName: name,
            onTap: onStatusTap,
            onLongPress: onStatusLongPress,
          ),
          const SizedBox(width: 2),
          Expanded(
            // Pulsar largo en cualquier parte de la fila abre el mismo selector
            // de estado que la casilla; el toque normal sigue abriendo el regalo.
            child: LongPressAfter(
              duration: kStatusLongPress,
              onLongPress: onStatusLongPress,
              child: PointerSurface(
                radius: BorderRadius.zero,
                child: InkWell(onTap: onTap, child: body),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
