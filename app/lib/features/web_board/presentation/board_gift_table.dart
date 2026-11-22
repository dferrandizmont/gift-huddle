import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/value_switcher.dart';
import '../../../core/platform/user_link.dart';
import '../../../core/theme/gift_status.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/gift_status_l10n.dart';
import '../../../core/widgets/giver_dot.dart';
import '../../../core/widgets/link_icon_button.dart';
import '../../../core/widgets/pointer_surface.dart';
import '../../../core/widgets/status_checkbox.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../core/widgets/tabler_icons.dart';
import '../../../core/widgets/tag_label.dart';
import '../../../l10n/app_localizations.dart';
import '../../gifts/presentation/gift_link_actions.dart';
import '../application/gift_editor_panel.dart';
import 'board_cursor.dart';

/// Las columnas opcionales de la tabla de regalos de una persona, por
/// prioridad (la casilla de estado y el título van siempre).
enum BoardColumn {
  /// El estado en texto (prioridad 2).
  statusText(120),

  /// El precio (3).
  price(104),

  /// Quién regala (4).
  giver(200),

  /// La tienda (5).
  store(180),

  /// La talla o la edad (6).
  size(120),

  /// La nota (7): de 240 a 480.
  note(240),

  /// El enlace (8).
  link(40);

  const BoardColumn(this.width);

  /// Su ancho (el mínimo, en la nota).
  final double width;
}

/// Qué columnas caben en un ancho dado
/// (la guía de diseño de escritorio, «Persona»): entran por
/// prioridad y la que no cabe pasa a la segunda línea del título. Puro Dart.
class BoardTableColumns {
  const BoardTableColumns._(this.shown, this.noteWidth);

  /// Las columnas opcionales que se ven.
  final Set<BoardColumn> shown;

  /// El ancho de la nota si se ve (de 240 a 480).
  final double noteWidth;

  /// El relleno de los lados de cada fila.
  static const double pad = 16;

  /// El ancho de la columna de la casilla de estado.
  static const double iconWidth = 44;

  /// El mínimo del título.
  static const double titleMin = 280;

  /// El hueco entre columnas.
  static const double gap = 32;

  /// El ancho máximo de la nota.
  static const double noteMax = 480;

  /// Si la columna [c] se ve.
  bool has(BoardColumn c) => shown.contains(c);

  /// El ancho de [c] (el de la nota es el calculado).
  double widthOf(BoardColumn c) => c == BoardColumn.note ? noteWidth : c.width;

  /// Las columnas que caben en [width] (el ancho de la tabla entera).
  ///
  /// Con [withData], las columnas de prioridad 5 o más (tienda, talla, nota y
  /// enlace) solo salen si alguna fila visible tiene ese dato: las que no, no
  /// cuentan y dejan sitio a la siguiente.
  static BoardTableColumns forWidth(
    double width, {
    Set<BoardColumn>? withData,
  }) {
    final avail = width - 2 * pad;
    var used = iconWidth + titleMin;
    final shown = <BoardColumn>{};
    for (final c in BoardColumn.values) {
      if (withData != null &&
          c.index >= BoardColumn.store.index &&
          !withData.contains(c)) {
        continue;
      }
      final need = gap + c.width;
      if (used + need > avail) {
        break;
      }
      used += need;
      shown.add(c);
    }
    var note = BoardColumn.note.width;
    if (shown.contains(BoardColumn.note)) {
      // Lo que sobra se reparte entre el título y la nota.
      note = math.min(noteMax, note + (avail - used) * 0.5);
    }
    return BoardTableColumns._(shown, note);
  }
}

/// Las columnas de la tabla de la pantalla, para que la cabecera y las filas
/// las lean.
class BoardTableScope extends InheritedWidget {
  /// Crea el ámbito.
  const BoardTableScope({
    super.key,
    required this.columns,
    required super.child,
  });

  /// Qué columnas se ven.
  final BoardTableColumns columns;

  /// Las columnas de [context].
  static BoardTableColumns of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BoardTableScope>()?.columns ??
      BoardTableColumns.forWidth(double.maxFinite);

  @override
  bool updateShouldNotify(BoardTableScope old) =>
      old.columns.shown.length != columns.shown.length ||
      old.columns.noteWidth != columns.noteWidth;
}

/// Una columna opcional: aparece y desaparece con un fundido de 150 ms (con
/// «Reducir movimiento», el mismo fundido sin deslizar el ancho).
class _Slot extends StatelessWidget {
  const _Slot({
    required this.visible,
    required this.width,
    required this.child,
  });

  final bool visible;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = RegalosMotion.of(context).reduce;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: visible ? 1 : 0),
      duration: RegalosMotion.fade,
      curve: Curves.easeOut,
      builder: (context, v, _) {
        if (v == 0) {
          return const SizedBox.shrink();
        }
        final content = Opacity(
          opacity: v,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(
              start: BoardTableColumns.gap,
            ),
            child: SizedBox(width: width, child: child),
          ),
        );
        // Al aparecer, la columna gana ancho y se funde a medida que cabe. Al
        // irse, ya no ocupa sitio (la fila no se desborda mientras otras
        // columnas siguen cabiendo) y se funde donde estaba.
        return visible
            ? ClipRect(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: reduce ? 1 : v,
                  child: content,
                ),
              )
            : Align(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: 0,
                child: content,
              );
      },
    );
  }
}

/// La cabecera fija de la tabla de una persona: el nombre de cada columna.
class BoardGiftTableHeader extends StatelessWidget {
  /// Crea la cabecera.
  const BoardGiftTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final cols = BoardTableScope.of(context);
    Widget label(String text, {TextAlign? align}) => Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: align,
      style: t.styles.caption.copyWith(fontWeight: FontWeight.w600),
    );
    // Las cifras van alineadas a la derecha, y su título con ellas.
    Widget slot(BoardColumn c, String text) => _Slot(
      visible: cols.has(c),
      width: cols.widthOf(c),
      child: label(text, align: c == BoardColumn.price ? TextAlign.end : null),
    );
    return Semantics(
      container: true,
      child: ColoredBox(
        color: t.bg,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: BoardTableColumns.pad,
          ),
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.separator)),
            ),
            child: Row(
              children: [
                const SizedBox(width: BoardTableColumns.iconWidth),
                Expanded(child: label(l10n.giftFieldTitle)),
                slot(BoardColumn.statusText, l10n.boardColStatus),
                slot(BoardColumn.price, l10n.giftPriceSection),
                slot(BoardColumn.giver, l10n.boardColGiver),
                slot(BoardColumn.store, l10n.giftFieldStore),
                slot(BoardColumn.size, l10n.boardColSize),
                slot(BoardColumn.note, l10n.giftFieldNote),
                slot(BoardColumn.link, ''),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// El importe de «49,99 € (previsto 55 €)».
String _amount(String price) {
  final at = price.indexOf(' (');
  return at < 0 ? price : price.substring(0, at);
}

/// Lo previsto de «49,99 € (previsto 55 €)», o `null`.
String? _planned(String price) {
  final at = price.indexOf(' (');
  if (at < 0) {
    return null;
  }
  final rest = price.substring(at + 2);
  return rest.endsWith(')') ? rest.substring(0, rest.length - 1) : rest;
}

/// Una fila de la tabla de regalos de una persona
/// (la guía de diseño de escritorio, «Persona»): casilla de
/// estado, título y las columnas que caben. Mide 48 (56 si lleva una segunda
/// línea con lo que no cabe en columnas). La fila que se edita se marca con el
/// fondo suave y un filete de tinta de 2 a la izquierda; la marcada con el
/// teclado, con el fondo suave y un filete gris.
class BoardGiftTableRow extends ConsumerWidget {
  /// Crea la fila.
  const BoardGiftTableRow({
    super.key,
    required this.giftId,
    required this.name,
    required this.status,
    required this.giverName,
    required this.giverColorIndex,
    this.price,
    this.store,
    this.size,
    this.note,
    this.url,
    this.tags = const <String>[],
    this.tagHints = const <String, String>{},
    this.onTap,
    this.onStatusTap,
    this.onStatusLongPress,
  });

  /// El regalo.
  final String giftId;

  /// El título.
  final String name;

  /// El estado.
  final GiftStatus status;

  /// Quién regala.
  final String giverName;

  /// El color de quién regala.
  final int? giverColorIndex;

  /// El precio ya formateado.
  final String? price;

  /// La tienda.
  final String? store;

  /// La talla o la edad, ya dicha («Talla o edad: 8»).
  final String? size;

  /// La nota.
  final String? note;

  /// El enlace.
  final String? url;

  /// Etiquetas pequeñas junto al título («Sorpresa»).
  final List<String> tags;

  /// El texto largo de las etiquetas que lo tienen (ayuda y lector).
  final Map<String, String> tagHints;

  /// Abre el regalo.
  final VoidCallback? onTap;

  /// Cambia de estado.
  final VoidCallback? onStatusTap;

  /// Abre el selector de estado.
  final VoidCallback? onStatusLongPress;

  /// El alto de una fila de una línea.
  static const double height = 48;

  /// El alto de una fila con segunda línea.
  static const double heightTwoLines = 56;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = RegalosTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final cols = BoardTableScope.of(context);
    final panel = ref.read(giftEditorPanelProvider);
    final link = url;
    final validatedUrl = link == null ? null : userLinkUri(link)?.toString();
    // Lo que no cabe en columnas pasa a la segunda línea del título.
    final second = <String>[
      if (!cols.has(BoardColumn.giver)) giverName,
      if (!cols.has(BoardColumn.store) && store != null) store!,
      if (!cols.has(BoardColumn.size) && size != null) size!,
      if (!cols.has(BoardColumn.note) && note != null) note!,
    ];
    final secondLine = second.join(' · ');
    return BoardCursorTarget(
      giftId: giftId,
      builder: (context, marked) => ListenableBuilder(
        listenable: panel,
        builder: (context, _) {
          final editing = panel.request?.gift?.id == giftId;
          // El fondo suave y el filete de tinta, solo mientras el editor
          // muestra este regalo; la marca del teclado, un borde de 1.
          final mark = editing ? t.ink : Colors.transparent;
          final markedOnly = marked && !editing;
          return AnimatedSize(
            duration: RegalosMotion.fade,
            alignment: Alignment.topCenter,
            child: Container(
              constraints: BoxConstraints(
                minHeight: secondLine.isEmpty ? height : heightTwoLines,
              ),
              // El filete, el fondo y el hover van de margen a margen, a la altura
              // del título de la pantalla, no de borde a borde de la tabla.
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: BoardTableColumns.pad,
                ),
                child: PointerSurface(
                  strength: 1.8,
                  radius: BorderRadius.zero,
                  child: Stack(
                    fit: StackFit.passthrough,
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: editing ? t.selection : null,
                            border: markedOnly
                                ? Border.all(color: t.controlBorder)
                                : Border(
                                    bottom: BorderSide(color: t.separator),
                                  ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: 2,
                        child: ColoredBox(color: mark),
                      ),
                      Row(
                        children: [
                          StatusCheckbox(
                            status: status,
                            itemName: name,
                            onTap: onStatusTap,
                            onLongPress: onStatusLongPress,
                          ),
                          Expanded(
                            child: InkWell(
                              onTap: onTap,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _TitleBlock(
                                        name: name,
                                        tags: tags,
                                        tagHints: tagHints,
                                        secondLine: secondLine,
                                      ),
                                    ),
                                    _Slot(
                                      visible: cols.has(BoardColumn.statusText),
                                      width: BoardColumn.statusText.width,
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
                                    _Slot(
                                      visible: cols.has(BoardColumn.price),
                                      width: BoardColumn.price.width,
                                      child: _Price(price: price),
                                    ),
                                    _Slot(
                                      visible: cols.has(BoardColumn.giver),
                                      width: BoardColumn.giver.width,
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
                                    _Slot(
                                      visible: cols.has(BoardColumn.store),
                                      width: BoardColumn.store.width,
                                      child: _Plain(text: store),
                                    ),
                                    _Slot(
                                      visible: cols.has(BoardColumn.size),
                                      width: BoardColumn.size.width,
                                      child: _Plain(text: size),
                                    ),
                                    _Slot(
                                      visible: cols.has(BoardColumn.note),
                                      width: cols.noteWidth,
                                      child: _Plain(text: note),
                                    ),
                                    _Slot(
                                      visible: cols.has(BoardColumn.link),
                                      width: BoardColumn.link.width,
                                      child: link == null
                                          ? const SizedBox.shrink()
                                          : Align(
                                              alignment: AlignmentDirectional
                                                  .centerStart,
                                              // Con un enlace https que vale, el
                                              // icono se pulsa y lo abre; con
                                              // otro texto, es solo la marca de
                                              // que hay enlace.
                                              child: validatedUrl == null
                                                  ? Tooltip(
                                                      message: link,
                                                      child: Semantics(
                                                        label:
                                                            '${l10n.giftFieldUrl}: $link',
                                                        child: StrokeIcon(
                                                          tablerLink,
                                                          size: 18,
                                                          color:
                                                              t.textSecondary,
                                                        ),
                                                      ),
                                                    )
                                                  // El dibujo de 18 queda a ras del
                                                  // principio de la columna, como el
                                                  // texto de las demás (la zona de
                                                  // 32 sobresale 7 a la izquierda).
                                                  : Transform.translate(
                                                      offset: const Offset(
                                                        -7,
                                                        0,
                                                      ),
                                                      child: LinkIconButton(
                                                        icon: tablerLink,
                                                        label:
                                                            '${l10n.giftLinkOpen}: $validatedUrl',
                                                        tooltip: validatedUrl,
                                                        onTap: () =>
                                                            openGiftLink(
                                                              context,
                                                              ref,
                                                              link,
                                                            ),
                                                      ),
                                                    ),
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({
    required this.name,
    required this.tags,
    required this.tagHints,
    required this.secondLine,
  });

  final String name;
  final List<String> tags;
  final Map<String, String> tagHints;
  final String secondLine;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: ValueSwitcher(
                child: Text(
                  name,
                  key: ValueKey(name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.styles.tableTitle,
                ),
              ),
            ),
            for (final tag in tags) ...[
              const SizedBox(width: 8),
              TagLabel(tag, hint: tagHints[tag]),
            ],
          ],
        ),
        if (secondLine.isNotEmpty)
          Text(
            secondLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.styles.meta,
          ),
      ],
    );
  }
}

class _Plain extends StatelessWidget {
  const _Plain({required this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    if (text == null) {
      return const SizedBox.shrink();
    }
    final t = RegalosTokens.of(context);
    return Text(
      text!,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: t.styles.meta,
    );
  }
}

class _Price extends StatelessWidget {
  const _Price({required this.price});

  final String? price;

  @override
  Widget build(BuildContext context) {
    final p = price;
    if (p == null) {
      return const SizedBox.shrink();
    }
    final t = RegalosTokens.of(context);
    final planned = _planned(p);
    return ValueSwitcher(
      // Cifras tabulares alineadas a la derecha (la ficha).
      alignment: AlignmentDirectional.centerEnd,
      child: Column(
        key: ValueKey(p),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _amount(p),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.styles.price,
          ),
          if (planned != null)
            Text(
              planned,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.styles.caption,
            ),
        ],
      ),
    );
  }
}
