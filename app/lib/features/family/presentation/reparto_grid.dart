import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../../core/format/money.dart';
import '../../../core/layout/large_text.dart';
import '../../../core/layout/window_class.dart';
import '../../../core/sync/model.dart';
import '../../../core/theme/accent_palette.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/dashed_box.dart';
import '../../../core/widgets/fit_text.dart';
import '../../../core/widgets/giver_dot.dart';
import '../../../core/widgets/person_avatar.dart' show personPalette;
import '../../../core/widgets/spring_pulse.dart';
import '../../../core/widgets/secret_block.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import 'family_texts.dart';
import 'reparto_flight.dart';
import 'reparto_fold.dart';
import 'reparto_outside.dart';
import 'self_tag.dart';

/// Clave de la celda de quien no tiene regalador (`''`) o de una pareja
/// persona / quien regala. Es la misma en la rejilla, en los rebotes y en la
/// hoja.
String repartoCellKey(String recipientId, String? giverId) =>
    '$recipientId|${giverId ?? ''}';

/// El ancla de una celda en el vuelo entre vistas.
String repartoCellAnchor(String recipientId, String giverId) =>
    'cell:${repartoCellKey(recipientId, giverId)}';

/// El ancla de «n sin quién» bajo el nombre de una persona.
String repartoUnassignedAnchor(String recipientId) => 'unassigned:$recipientId';

/// Lo que cuenta una celda: cuántos regalos, cuántos ya comprados, cuánto
/// importan y cuáles son (para abrir la hoja).
class RepartoCellStats {
  /// Crea los datos de una celda.
  const RepartoCellStats({
    this.count = 0,
    this.bought = 0,
    this.cents = 0,
    this.ids = const <String>[],
  });

  /// Regalos de la celda.
  final int count;

  /// Los que ya están comprados (o más allá).
  final int bought;

  /// Importe: lo gastado o, si aún no se ha gastado, lo previsto.
  final int cents;

  /// Los ids de los regalos, por título.
  final List<String> ids;

  /// Vacía, o con todo comprado, o con algo por comprar.
  RepartoCellKind get kind => count == 0
      ? RepartoCellKind.nothing
      : (bought >= count ? RepartoCellKind.allBought : RepartoCellKind.toBuy);

  @override
  bool operator ==(Object other) =>
      other is RepartoCellStats &&
      other.count == count &&
      other.bought == bought &&
      other.cents == cents;

  @override
  int get hashCode => Object.hash(count, bought, cents);
}

/// Los tres estados de una celda, que se distinguen por la forma.
enum RepartoCellKind {
  /// Discontinua con «+».
  nothing,

  /// Número y barra de comprados.
  toBuy,

  /// Pastel de la persona con visto.
  allBought,
}

/// Las celdas que deben rebotar (en vez de fundirse) cuando cambian: las de
/// origen y destino de un regalo que cambia de quien regala.
class RepartoBumps {
  final Set<String> _keys = <String>{};

  /// Marca celdas para que su próximo cambio rebote.
  void mark(Iterable<String> keys) => _keys.addAll(keys);

  /// Si la celda estaba marcada (y la desmarca).
  bool consume(String key) => _keys.remove(key);

  /// Olvida las marcas que no llegaron a usarse.
  void clear() => _keys.clear();
}

/// Dice a Reparto que está en el tablero de la web de escritorio: la rejilla
/// va alineada a la izquierda y llena el ancho (`RepartoLayout`, `board`).
class RepartoBoardMode extends InheritedWidget {
  /// Crea la marca.
  const RepartoBoardMode({super.key, required super.child});

  /// Si [context] está en el tablero.
  static bool of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<RepartoBoardMode>() != null;

  @override
  bool updateShouldNotify(RepartoBoardMode old) => false;
}

/// Medidas de la rejilla para un ancho y un número de columnas.
///
/// De 1 a 4 columnas, celdas de hasta 68 × 48; desde 5, modo compacto (hasta
/// 44 × 44, cabecera con los nombres inclinados). Nunca se desborda a lo
/// ancho: las celdas se estrechan hasta caber.
///
/// Con `wide` (la ventana de una tablet, desde 600 dp) las celdas crecen
/// hasta 96 × 52, la columna de nombres mide entre 160 y 220 y la rejilla se
/// centra: lo que sobra va a los márgenes ([pad]). El modo compacto solo
/// entra si las celdas de 68 no caben, y entonces miden lo que quepa entre 44
/// y 68; si ni las de 44 caben, valen las medidas del móvil.
///
/// Con `desktop` (la ventana ya enseña dos paneles, desde 840 dp) la rejilla
/// crece con el ancho: celdas de hasta 120 × 56, nombres entre 180 y 280 y
/// 1400 de ancho como máximo, centrada. Si ni con eso caben las celdas de 68,
/// valen las medidas de `wide`.
///
/// Con `wide` o `desktop`, además, el tope de la celda sube con el ancho del
/// sitio, sin saltos ([wideCellMaxFor]): de 96 a 120 entre 520 y 760 dp y de
/// 120 a su tope (de 168 a 210 según cuántos regalan) entre 760 y 1286 dp. Cuando la celda pasa de 120 de ancho, todo
/// lo que la rodea crece en proporción ([scale], hasta 1,4): alto de la
/// celda, cifra, marca, barra, avatar, nombres, cabecera, totales y leyenda.
class RepartoLayout {
  /// Calcula las medidas.
  factory RepartoLayout({
    required double width,
    required int columns,
    required TextScaler scaler,
    bool wide = false,
    bool desktop = false,
    bool board = false,
  }) {
    const pad = 16.0;
    const gap = 3.0;
    final n = math.max(columns, 1);
    final factor = scaler.scale(1).clamp(1.0, 1.25);
    // Cuánto crece todo cuando la celda pasa de 120 de ancho (1 en el móvil).
    double growth(double cell) =>
        math.min(math.max(cell / desktopCellWidth, 1.0), maxScale);
    // La columna de nombres crece menos que la celda.
    double leftCap(double base, double s) => base * (1 + (s - 1) * 0.4);
    if (board) {
      // El tablero de la web de escritorio: alineada a la izquierda, con los
      // nombres a 220 y celdas de `clamp(…, 120, 280)` que crecen con el
      // ancho; sin tope de 1400 ni centrado.
      final room = (width - 2 * pad - boardLeftWidth) / n;
      if (room >= 68 + gap) {
        final slot = math.min(boardCellMax + gap, room);
        final cellH = desktopCellHeight * factor;
        return RepartoLayout._(
          compact: false,
          pad: pad,
          gap: gap,
          slot: slot,
          leftWidth: boardLeftWidth,
          cellHeight: cellH,
          rowHeight: cellH + 8,
          headerHeight: 58.0 * factor,
          width: width,
        );
      }
    }
    if (desktop && width > desktopMaxWidth) {
      // Por encima del tope se calcula con 1400 y se centra en el sitio.
      final inner = RepartoLayout(
        width: desktopMaxWidth,
        columns: columns,
        scaler: scaler,
        wide: true,
        desktop: true,
      );
      return inner._centeredIn(width);
    }
    final avail = width - 2 * pad;
    if (desktop) {
      final roomy = (avail - desktopLeftMin) / n;
      if (roomy >= 68 + gap) {
        final cellMax = math.max(desktopCellWidth, wideCellMaxFor(width, n));
        final slot = math.min(cellMax + gap, roomy);
        final s = growth(slot - gap);
        final left = (avail - slot * n)
            .clamp(desktopLeftMin, leftCap(desktopLeftMax, s))
            .toDouble();
        final cellH = desktopCellHeight * s * factor;
        // Alineada a la izquierda, con el margen de siempre: lo que sobra
        // queda a la derecha.
        return RepartoLayout._(
          compact: false,
          pad: pad,
          gap: gap,
          slot: slot,
          leftWidth: left,
          cellHeight: cellH,
          rowHeight: cellH + 8 * s,
          headerHeight: 58.0 * (1 + (s - 1) * 0.5) * factor,
          width: width,
          scale: s,
        );
      }
    }
    if (wide) {
      // El hueco de cada columna si los nombres se quedan en su mínimo.
      final roomy = (avail - wideLeftMin) / n;
      if (roomy >= 68 + gap) {
        final slot = math.min(wideCellMaxFor(width, n) + gap, roomy);
        final s = growth(slot - gap);
        final left = (avail - slot * n)
            .clamp(wideLeftMin, leftCap(wideLeftMax, s))
            .toDouble();
        final cellH = wideCellHeight * s * factor;
        return RepartoLayout._(
          compact: false,
          pad: (width - left - slot * n) / 2,
          gap: gap,
          slot: slot,
          leftWidth: left,
          cellHeight: cellH,
          rowHeight: cellH + 8 * s,
          headerHeight: 58.0 * (1 + (s - 1) * 0.5) * factor,
          width: width,
          scale: s,
        );
      }
      if (roomy >= 44 + gap) {
        final cellH = 44.0 * factor;
        return RepartoLayout._(
          compact: true,
          pad: pad,
          gap: gap,
          slot: roomy,
          leftWidth: wideLeftMin,
          cellHeight: cellH,
          rowHeight: cellH + 8,
          headerHeight: 88.0 * factor,
          width: width,
        );
      }
    }
    // En una ventana ancha solo se llega aquí si ni las celdas de 44 caben
    // con los nombres a 160: compacto, tenga las columnas que tenga.
    final compact = wide || columns >= 5;
    var leftMin = compact ? 96.0 : 112.0;
    var slot = math.min((compact ? 44.0 : 68.0) + gap, (avail - leftMin) / n);
    if (slot < 22) {
      leftMin = 72;
      slot = math.max((avail - leftMin) / n, 17);
    }
    final cellH = (compact ? 44.0 : 48.0) * factor;
    return RepartoLayout._(
      compact: compact,
      pad: pad,
      gap: gap,
      slot: slot,
      leftWidth: avail - slot * n,
      cellHeight: cellH,
      rowHeight: cellH + 8,
      headerHeight: (compact ? 88.0 : 58.0) * factor,
      width: width,
    );
  }

  const RepartoLayout._({
    required this.compact,
    required this.pad,
    required this.gap,
    required this.slot,
    required this.leftWidth,
    required this.cellHeight,
    required this.rowHeight,
    required this.headerHeight,
    required this.width,
    this.scale = 1,
    this.verticalNames = false,
    this.nameLines = const <int>[],
  });

  /// Ancho máximo de una celda en una ventana ancha de 520 dp (el más
  /// estrecho que se da).
  static const double wideCellWidth = 96;

  /// Cuánto puede crecer todo lo que rodea a la celda (la celda más grande
  /// es 1,4 veces la de 120).
  static const double maxScale = 1.4;

  /// El ancho máximo de una celda en un sitio de [width] dp con [columns]
  /// columnas: 96 hasta 520, 120 a 760 y, desde 1286, 210 (hasta tres
  /// columnas), 184 (cuatro) o 190 (más); sin saltos entre medias.
  static double wideCellMaxFor(double width, [int columns = 5]) {
    final mid =
        ((width - RegalosGridWidths.gridRampStart) /
                (RegalosGridWidths.gridRampMid -
                    RegalosGridWidths.gridRampStart))
            .clamp(0.0, 1.0);
    final big =
        ((width - RegalosGridWidths.gridRampMid) /
                (RegalosGridWidths.gridRampEnd - RegalosGridWidths.gridRampMid))
            .clamp(0.0, 1.0);
    final top = columns <= 3
        ? RegalosGridWidths.cellMaxFew
        : columns == 4
        ? RegalosGridWidths.cellMaxFour
        : RegalosGridWidths.cellMaxMany;
    return wideCellWidth +
        (desktopCellWidth - wideCellWidth) * mid +
        (top - desktopCellWidth) * big;
  }

  /// Alto de una celda en una ventana ancha (sin el modo compacto).
  static const double wideCellHeight = 52;

  /// Ancho mínimo de la columna de nombres en una ventana ancha…
  static const double wideLeftMin = 160;

  /// …y máximo.
  static const double wideLeftMax = 220;

  /// Ancho máximo de una celda en el escritorio (ventana de dos paneles).
  static const double desktopCellWidth = 120;

  /// Alto de una celda en el escritorio.
  static const double desktopCellHeight = 56;

  /// Ancho mínimo de la columna de nombres en el escritorio…
  static const double desktopLeftMin = 180;

  /// …y máximo.
  static const double desktopLeftMax = 280;

  /// Ancho de la columna de nombres en el tablero de la web de escritorio.
  static const double boardLeftWidth = 220;

  /// Ancho máximo de una celda en el tablero de la web de escritorio.
  static const double boardCellMax = 280;

  /// Ancho máximo de toda la rejilla en el escritorio; si el sitio es mayor,
  /// se centra.
  static const double desktopMaxWidth = 1400;

  /// La misma rejilla centrada en un sitio de [width] (más ancho que ella).
  RepartoLayout _centeredIn(double outer) => RepartoLayout._(
    compact: compact,
    pad: pad + (outer - width) / 2,
    gap: gap,
    slot: slot,
    leftWidth: leftWidth,
    cellHeight: cellHeight,
    rowHeight: rowHeight,
    headerHeight: headerHeight,
    width: outer,
    scale: scale,
  );

  /// Modo compacto: nombres de quienes regalan inclinados. En el móvil, con
  /// cinco columnas o más; en una ventana ancha, si las celdas de 68 no caben.
  final bool compact;

  /// Margen lateral. En una ventana ancha, el que centra la rejilla.
  final double pad;

  /// Hueco entre celdas.
  final double gap;

  /// Ancho de la zona táctil de una columna (celda más hueco).
  final double slot;

  /// Ancho de la columna de nombres.
  final double leftWidth;

  /// Alto de la celda.
  final double cellHeight;

  /// Alto mínimo de una fila.
  final double rowHeight;

  /// Alto de la cabecera fija.
  final double headerHeight;

  /// Ancho total.
  final double width;

  /// Cuánto crece todo lo que rodea a la celda cuando esta pasa de 120 de
  /// ancho en una ventana ancha: de 1 (el móvil y las celdas de hasta 120) a
  /// 1,4.
  final double scale;

  /// Cuánto crece el texto secundario (nombres, cabecera, totales, leyenda):
  /// la mitad que las cifras de las celdas (hasta 1,2), para que no se vea
  /// desproporcionado.
  double get textScale => 1 + (scale - 1) * 0.5;

  /// Lado del avatar de la fila: crece como los nombres.
  double get avatarSize => 22 * textScale;

  /// Tamaño de la cifra de una celda.
  double get numberSize => (compact ? 16.0 : 17.0) * scale;

  /// Tamaño de la marca de «todo comprado».
  double get checkSize => 13 * scale;

  /// Tamaño del «+» de una celda vacía.
  double get plusSize => 14 * scale;

  /// Alto de la barra de comprados.
  double get barHeight => 4 * scale;

  /// Con letra grande, los nombres de quienes regalan van girados a la
  /// vertical (de abajo arriba), hasta en dos líneas, y la cabecera es tan
  /// alta como el más largo (`fitGiverNames`).
  final bool verticalNames;

  /// Con los nombres en vertical, las líneas de cada uno (1 o 2): dos solo si
  /// cada palabra cabe entera en una línea.
  final List<int> nameLines;

  /// La misma rejilla con los nombres en vertical y la cabecera de [height].
  RepartoLayout _withVerticalNames(double height, List<int> lines) =>
      RepartoLayout._(
        compact: compact,
        pad: pad,
        gap: gap,
        slot: slot,
        leftWidth: leftWidth,
        cellHeight: cellHeight,
        rowHeight: rowHeight,
        headerHeight: height,
        width: width,
        scale: scale,
        verticalNames: true,
        nameLines: lines,
      );

  /// Esta misma medida con la cabecera a [height] (nombres en horizontal).
  RepartoLayout _withHeaderHeight(double height) => RepartoLayout._(
    compact: compact,
    pad: pad,
    gap: gap,
    slot: slot,
    leftWidth: leftWidth,
    cellHeight: cellHeight,
    rowHeight: rowHeight,
    headerHeight: height,
    width: width,
    scale: scale,
    verticalNames: verticalNames,
    nameLines: nameLines,
  );

  /// Ancho de la celda.
  double get cellWidth => slot - gap;

  /// Ancho de la barra de comprados de una celda: 28 (18 en compacto) y, en
  /// las celdas más anchas que las del móvil, en la misma proporción.
  double get barWidth {
    final base = compact ? 18.0 : 28.0;
    final reference = compact ? 44.0 : 68.0;
    return math.min(
      math.max(base, cellWidth * base / reference),
      cellWidth - 8,
    );
  }
}

/// La paleta de una persona, resuelta para el brillo: relleno y tinta.
({Color fill, Color ink}) repartoPersonColors(RegalosTokens t, int colorIndex) {
  final p = personPalette(colorIndex);
  return t.isDark
      ? (fill: p.tintD, ink: p.tintaD)
      : (fill: p.pastel, ink: p.tinta);
}

/// Avatar cuadrado de una persona: tamaño fijo, esquinas de 6 (nunca un
/// círculo ni una elipse).
class RepartoAvatar extends StatelessWidget {
  /// Crea el avatar.
  const RepartoAvatar({
    super.key,
    required this.name,
    required this.colorIndex,
    this.size = 22,
  });

  /// Nombre de la persona (sale su inicial).
  final String name;

  /// Su color.
  final int colorIndex;

  /// Lado, fijo.
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final c = repartoPersonColors(t, colorIndex);
    final trimmed = name.trim();
    final initial = trimmed.isEmpty
        ? '?'
        : String.fromCharCode(trimmed.runes.first).toUpperCase();
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.fill,
            borderRadius: const BorderRadius.all(Radius.circular(6)),
          ),
          child: Center(
            child: Text(
              initial,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: size * 0.45,
                height: 1,
                fontWeight: FontWeight.w700,
                color: c.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La rejilla de Reparto: personas que reciben en filas y quienes regalan en
/// columnas, con la cabecera fija, la fila de totales y la leyenda.
///
/// Es una sliver: va dentro del `CustomScrollView` de la pantalla, que solo
/// se desplaza en vertical.
///
/// La persona que sale del reparto se pliega y aparece en el bloque «Fuera
/// del reparto»; al volver a incluirla, vuelve con muelle.
class RepartoGrid extends StatefulWidget {
  /// Crea la rejilla.
  const RepartoGrid({
    super.key,
    required this.recipients,
    required this.givers,
    required this.stats,
    required this.duplicateCells,
    required this.marks,
    required this.bumps,
    required this.onOpenCell,
    required this.onOpenPerson,
    required this.onInclude,
    this.excluded = const <String>{},
    this.secret = const <String>{},
    this.skipLabels = const <String, String>{},
    this.excludedText = '',
    this.outside = const <Recipient>[],
    this.stage,
    this.filterKey,
    this.selfId,
  });

  /// La persona dueña de este móvil («Yo»), o `null`: su nombre lleva la
  /// etiqueta «Yo».
  final String? selfId;

  /// Las filas.
  final List<Recipient> recipients;

  /// Las columnas.
  final List<Giver> givers;

  /// Los datos de cada celda por [repartoCellKey]; sin entrada, vacía.
  final Map<String, RepartoCellStats> stats;

  /// Las celdas (`quien regala|persona`) con un posible duplicado.
  final Set<String> duplicateCells;

  /// Las ocasiones de cada celda (solo para el lector de pantalla).
  final Map<String, List<String>> marks;

  /// Para que las celdas rebotan o se fundan al cambiar.
  final RepartoBumps bumps;

  /// El escenario del vuelo entre la rejilla y la vista por ocasión.
  final RepartoStage? stage;

  /// El filtro de ocasión que se ve; al cambiar, la columna de nombres y
  /// avatares repite su entrada escalonada.
  final String? filterKey;

  /// Las personas (por id) a las que no se regala en la ocasión que se ve: su
  /// fila es una franja gris lisa.
  final Set<String> excluded;

  /// Las personas (por id) con regalos en secreto que este móvil no ve: su
  /// fila no lleva celdas ni cifras, solo la franja borrosa fija.
  final Set<String> secret;

  /// Bajo el nombre, «Sin Navidad», para quien se salta alguna ocasión.
  final Map<String, String> skipLabels;

  /// El texto de la franja gris («No le regaláis en Navidad»).
  final String excludedText;

  /// Las personas que no salen en Reparto, para el bloque plegable.
  final List<Recipient> outside;

  /// Se llama al tocar una celda (`giverId` nulo: los regalos sin quién
  /// regala de la persona).
  final void Function(
    Recipient recipient,
    Giver? giver,
    Rect from,
    Color fromColor,
  )
  onOpenCell;

  /// Se llama al tocar el nombre de una persona (o su franja): abre su ficha.
  final void Function(Recipient recipient, Rect from) onOpenPerson;

  /// Se llama al pulsar «Volver a incluir».
  final ValueChanged<Recipient> onInclude;

  @override
  State<RepartoGrid> createState() => _RepartoGridState();
}

class _RepartoGridState extends State<RepartoGrid> {
  late final FoldTracker<Recipient> _rows = FoldTracker<Recipient>(
    (r) => r.id,
    widget.recipients,
  );

  /// Mientras es el primer fotograma de la rejilla: las filas que se pintan
  /// ahora entran escalonadas (nombre y avatar incluidos).
  bool _fresh = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fresh = false);
  }

  @override
  void didUpdateWidget(RepartoGrid old) {
    super.didUpdateWidget(old);
    _rows.update(widget.recipients);
    WidgetsBinding.instance.addPostFrameCallback((_) => _rows.settle());
  }

  void _gone(String id) {
    if (!mounted) {
      return;
    }
    setState(() => _rows.gone(id));
  }

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context);
      final base = RepartoLayout(
        width: constraints.crossAxisExtent,
        columns: widget.givers.length,
        scaler: scaler,
        // La clase es la de la ventana; el ancho, el del sitio que le dan.
        wide: WindowClass.of(context).usesRail,
        desktop: WindowClass.of(context).usesTwoPanes,
        board: RepartoBoardMode.of(context),
      );
      final l10n = AppLocalizations.of(context);
      final names = [for (final g in widget.givers) giverNameFor(l10n, g)];
      var labelStyle = DefaultTextStyle.of(context).style
          .merge(_giverLabelStyle(RegalosTokens.of(context), base.textScale));
      if (MediaQuery.boldTextOf(context)) {
        labelStyle = labelStyle.merge(
          const TextStyle(fontWeight: FontWeight.bold),
        );
      }
      // Con letra grande, los nombres que no caben pasan a la vertical.
      final layout = fitGiverNames(
        layout: base,
        names: names,
        style: labelStyle,
        scaler: scaler,
        direction: Directionality.of(context),
        locale: Localizations.maybeLocaleOf(context),
      );
      final entries = _rows.entries;
      return SliverMainAxisGroup(
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _HeaderDelegate(
              layout: layout,
              givers: widget.givers,
              names: names,
              brightness: Theme.of(context).brightness,
              textScale: scaler.scale(10),
            ),
          ),
          SliverList.builder(
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final e = entries[i];
              return FoldTransition(
                key: ValueKey<String>('fold:${e.item.id}'),
                entering: e.entering,
                leaving: e.leaving,
                onGone: () => _gone(e.item.id),
                child: _RecipientRow(
                  index: i,
                  introOnMount: _fresh && !e.entering,
                  filterKey: widget.filterKey,
                  layout: layout,
                  recipient: e.item,
                  givers: widget.givers,
                  stats: widget.stats,
                  duplicateCells: widget.duplicateCells,
                  marks: widget.marks,
                  bumps: widget.bumps,
                  stage: widget.stage,
                  excluded: widget.excluded.contains(e.item.id),
                  secret: widget.secret.contains(e.item.id),
                  excludedText: widget.excludedText,
                  skipLabel: widget.skipLabels[e.item.id],
                  isSelf: e.item.id == widget.selfId,
                  onOpenCell: widget.onOpenCell,
                  onOpenPerson: widget.onOpenPerson,
                ),
              );
            },
          ),
          SliverToBoxAdapter(
            child: RepartoBlock(
              index: 5,
              child: _Footer(
                layout: layout,
                givers: widget.givers,
                recipients: widget.recipients,
                stats: widget.stats,
                outside: widget.outside,
                onOpenPerson: widget.onOpenPerson,
                onInclude: widget.onInclude,
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  _HeaderDelegate({
    required this.layout,
    required this.givers,
    required this.names,
    required this.brightness,
    required this.textScale,
  });

  final RepartoLayout layout;
  final List<Giver> givers;
  final List<String> names;
  final Brightness brightness;
  final double textScale;

  @override
  double get minExtent => layout.headerHeight;

  @override
  double get maxExtent => layout.headerHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => _Header(layout: layout, givers: givers, stuck: overlapsContent);

  @override
  bool shouldRebuild(_HeaderDelegate old) =>
      old.layout.width != layout.width ||
      old.layout.pad != layout.pad ||
      old.layout.slot != layout.slot ||
      old.layout.leftWidth != layout.leftWidth ||
      old.layout.compact != layout.compact ||
      old.layout.headerHeight != layout.headerHeight ||
      old.layout.verticalNames != layout.verticalNames ||
      old.givers != givers ||
      !_sameNames(old.names, names) ||
      old.brightness != brightness ||
      old.textScale != textScale;
}

bool _sameNames(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

const double _rotation = -58 * math.pi / 180;

/// [style] con el tamaño de letra multiplicado por [scale] (1 no lo toca).
TextStyle _scaled(TextStyle style, double scale) => scale == 1
    ? style
    : style.copyWith(fontSize: (style.fontSize ?? 14) * scale);

/// El estilo de la cabecera de quien regala.
TextStyle _giverLabelStyle(RegalosTokens t, [double scale = 1]) =>
    t.styles.caption.copyWith(
      fontSize: 12 * scale,
      fontWeight: FontWeight.w600,
      color: t.text,
      height: 1.2,
    );

/// Punto de color (10) y aire (5) bajo el nombre vertical.
const double _verticalDotSpace = 15;

/// Alto máximo de la cabecera con los nombres en vertical.
const double _verticalHeaderMax = 220;

/// Lo que sale de medir los nombres en vertical.
class _VerticalFit {
  const _VerticalFit(this.height, this.lines);

  /// Alto de la cabecera.
  final double height;

  /// Líneas de cada nombre.
  final List<int> lines;
}

/// Lo medido para una columna: la cabecera en vertical (`null` si no hace
/// falta) y, si no, el alto del texto de los nombres en horizontal.
class _FitResult {
  const _FitResult(this.vertical, this.horizontalTextHeight);

  final _VerticalFit? vertical;

  /// Alto de la línea o líneas más altas de los nombres en horizontal; solo se
  /// mide si no hay vertical y la columna no es compacta.
  final double horizontalTextHeight;
}

/// Medidas ya hechas: la cabecera se calcula en el `SliverLayoutBuilder` y se
/// repetiría al desplazar. Clave: columna, nombres, estilo, escala, idioma y
/// dirección. `null` si con esas medidas no hace falta la vertical.
final Map<Object, _FitResult> _fitCache = <Object, _FitResult>{};

/// Cuántas veces se ha medido de verdad (los aciertos de caché no cuentan).
@visibleForTesting
int fitGiverNamesMeasurements = 0;

/// Con letra grande (más del 105 %), ¿no caben los nombres de quienes regalan
/// en su columna sin partir palabras? Entonces todos pasan a la vertical: el
/// nombre girado, de abajo arriba, con la cabecera tan alta como el más largo
/// (hasta 220). Es lo más legible con columnas de ~70: no hay que cortar ni
/// abreviar, y el texto crece hacia arriba, donde sobra sitio. Un nombre va en
/// dos líneas (por los espacios) solo si cada una de sus palabras cabe entera
/// en una línea; si no, va en una sola acabada en «…», así nunca se parte una
/// palabra. Devuelve [layout] sin cambios si no hace falta (letra normal,
/// nombres que caben) o si ni una línea girada cabe en la columna.
@visibleForTesting
RepartoLayout fitGiverNames({
  required RepartoLayout layout,
  required List<String> names,
  required TextStyle style,
  required TextScaler scaler,
  required TextDirection direction,
  Locale? locale,
}) {
  if (names.isEmpty || scaler.scale(12) / 12 <= 1.05) {
    return layout;
  }
  final key = (
    layout.slot,
    layout.compact,
    names.join('\u0001'),
    style,
    scaler,
    locale,
    direction,
  );
  var result = _fitCache[key];
  if (result == null) {
    final vertical = _measureVertical(
      layout: layout,
      names: names,
      style: style,
      scaler: scaler,
      direction: direction,
      locale: locale,
    );
    result = _FitResult(
      vertical,
      vertical == null && !layout.compact
          ? _horizontalTextHeight(
              layout: layout,
              names: names,
              style: style,
              scaler: scaler,
              direction: direction,
              locale: locale,
            )
          : 0,
    );
    if (_fitCache.length >= 32) {
      _fitCache.remove(_fitCache.keys.first);
    }
    _fitCache[key] = result;
  }
  final fit = result.vertical;
  if (fit != null) {
    return layout._withVerticalNames(fit.height, fit.lines);
  }
  if (result.horizontalTextHeight == 0) {
    return layout;
  }
  // Punto (10), su aire, el texto de los nombres y los 6 que le quita la
  // cabecera a su alto: con letra grande un nombre pasa a dos líneas y la
  // cabecera crece lo que haga falta en vez de quedarse con el alto normal.
  final needed =
      10 + 4 * layout.textScale + result.horizontalTextHeight + 6 + 1;
  return needed > layout.headerHeight
      ? layout._withHeaderHeight(needed)
      : layout;
}

/// El alto del nombre más alto en horizontal, medido como lo pinta
/// [FittedGiverName]: al ancho de la columna, con el tamaño que elige y hasta
/// dos líneas (una con «…» si ni rebajándolo caben sus palabras).
double _horizontalTextHeight({
  required RepartoLayout layout,
  required List<String> names,
  required TextStyle style,
  required TextScaler scaler,
  required TextDirection direction,
  Locale? locale,
}) {
  var tallest = 0.0;
  final base = style.fontSize ?? 12;
  // Sin recortar: [FittedGiverName] mide y pinta el nombre tal cual.
  for (final name in names) {
    final factor = FittedGiverName.factorFor(
      name: name,
      effective: style,
      scaler: scaler,
      direction: direction,
      locale: locale,
      maxWidth: layout.slot,
    );
    final painter = TextPainter(
      text: TextSpan(
        text: name,
        style: factor == null ? style : style.copyWith(fontSize: base * factor),
      ),
      textDirection: direction,
      textScaler: scaler,
      locale: locale,
      textAlign: TextAlign.center,
      maxLines: factor == null ? 1 : 2,
    )..layout(maxWidth: layout.slot);
    tallest = math.max(tallest, painter.height);
    painter.dispose();
  }
  return tallest;
}

_VerticalFit? _measureVertical({
  required RepartoLayout layout,
  required List<String> names,
  required TextStyle style,
  required TextScaler scaler,
  required TextDirection direction,
  Locale? locale,
}) {
  fitGiverNamesMeasurements++;
  TextPainter paint(String text, {int? maxLines, double? maxWidth}) =>
      TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: scaler,
        locale: locale,
        maxLines: maxLines,
      )..layout(maxWidth: maxWidth ?? double.infinity);

  double widthOf(String text) {
    final p = paint(text, maxLines: 1);
    final w = p.width;
    p.dispose();
    return w;
  }

  // ¿Hace falta? En columnas anchas, si algún nombre no cabe en su sitio; en
  // el modo compacto (inclinado), si es más largo de lo que da el giro.
  final needed = layout.compact
      ? names.any((n) => widthOf(n.trim()) > 84)
      : names.any(
          (n) =>
              FittedGiverName.factorFor(
                name: n,
                effective: style,
                scaler: scaler,
                direction: direction,
                locale: locale,
                maxWidth: layout.slot,
              ) ==
              null,
        );
  if (!needed) {
    return null;
  }
  final probe = paint('Mg', maxLines: 1);
  final lineHeight = probe.height;
  probe.dispose();
  final room = layout.slot - 4;
  if (room < lineHeight) {
    return null;
  }
  final twoLines = room >= 2 * lineHeight;
  final cap = _verticalHeaderMax - _verticalDotSpace - 10;
  var longest = 0.0;
  final lines = <int>[];
  for (final raw in names) {
    final name = raw.trim();
    final single = widthOf(name);
    var count = 1;
    var width = single;
    if (twoLines && name.contains(RegExp(r'\s'))) {
      var lo = 0.0;
      for (final word in name.split(RegExp(r'\s+'))) {
        lo = math.max(lo, widthOf(word));
      }
      // Solo dos líneas si la palabra más larga cabe entera en una.
      if (lo <= cap) {
        count = 2;
        // La anchura mínima con la que el nombre cabe en dos líneas.
        var hi = single;
        for (var i = 0; i < 14 && hi - lo > 0.5; i++) {
          final mid = (lo + hi) / 2;
          final p = paint(name, maxLines: 2, maxWidth: mid);
          final fits = !p.didExceedMaxLines;
          p.dispose();
          if (fits) {
            hi = mid;
          } else {
            lo = mid;
          }
        }
        width = hi;
      }
    }
    lines.add(count);
    longest = math.max(longest, math.min(width, cap));
  }
  final text = math.min(longest + 1, cap);
  return _VerticalFit(text + _verticalDotSpace + 6 + 4, lines);
}

class _Header extends StatelessWidget {
  const _Header({
    required this.layout,
    required this.givers,
    required this.stuck,
  });

  final RepartoLayout layout;
  final List<Giver> givers;
  final bool stuck;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final labelStyle = _giverLabelStyle(t, layout.textScale);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(
          bottom: BorderSide(
            color: stuck ? t.separator : t.separator.withValues(alpha: 0),
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(left: layout.pad, bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: layout.leftWidth,
              child: Padding(
                // Con la rejilla grande, «Recibe» baja hasta la línea base de
                // los nombres de quienes regalan.
                padding: EdgeInsets.only(bottom: layout.scale > 1 ? 0 : 2),
                child: RepartoBlock(
                  index: 2,
                  child: FitText(
                    l10n.familyRecipientHeader,
                    style: t.styles.caption.copyWith(
                      fontSize: 13 * layout.textScale,
                    ),
                  ),
                ),
              ),
            ),
            // Quienes regalan entran uno tras otro, de izquierda a derecha,
            // un poco antes que las celdas de su columna.
            for (var i = 0; i < givers.length; i++)
              SizedBox(
                width: layout.slot,
                height: layout.headerHeight - 6,
                child: RepartoBlock(
                  index: 2 + i,
                  child: _GiverHeader(
                    layout: layout,
                    giver: givers[i],
                    name: giverNameFor(l10n, givers[i]),
                    style: labelStyle,
                    lines: layout.verticalNames ? layout.nameLines[i] : 1,
                    // Espacio que queda hasta el borde para el nombre inclinado.
                    roomRight:
                        layout.width -
                        (layout.pad + layout.leftWidth + layout.slot * i) -
                        layout.slot * 0.45,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GiverHeader extends StatelessWidget {
  const _GiverHeader({
    required this.layout,
    required this.giver,
    required this.name,
    required this.style,
    required this.lines,
    required this.roomRight,
  });

  final RepartoLayout layout;
  final Giver giver;
  final String name;
  final TextStyle style;

  /// Con los nombres en vertical, sus líneas (1 o 2).
  final int lines;
  final double roomRight;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    Widget tooltip(Widget child) => Tooltip(
      message: name,
      triggerMode: TooltipTriggerMode.tap,
      excludeFromSemantics: true,
      child: child,
    );
    if (layout.verticalNames) {
      // Letra grande: el nombre en vertical, de abajo arriba, con su punto al
      // pie; hasta dos líneas por los espacios, sin partir palabras.
      return tooltip(
        Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: RotatedBox(
                quarterTurns: 3,
                child: Text(
                  name.trim(),
                  maxLines: lines,
                  // Con una línea, ni una palabra larga se parte entre líneas.
                  softWrap: lines > 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
            ),
            const SizedBox(height: 5),
            GiverDot(colorIndex: giver.colorIndex, size: 10),
          ],
        ),
      );
    }
    if (!layout.compact) {
      return tooltip(
        Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            GiverDot(colorIndex: giver.colorIndex, size: 10),
            SizedBox(height: 4 * layout.textScale),
            FittedGiverName(name: name, style: style),
          ],
        ),
      );
    }
    // Con las columnas muy estrechas, solo la inicial.
    if (layout.cellWidth < 26) {
      final trimmed = name.trim();
      return tooltip(
        Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            GiverDot(colorIndex: giver.colorIndex),
            const SizedBox(height: 4),
            Text(
              trimmed.isEmpty
                  ? '?'
                  : String.fromCharCode(trimmed.runes.first).toUpperCase(),
              style: style,
            ),
          ],
        ),
      );
    }
    // Inclinado -58°, con el pie en la columna y sin salirse por la derecha.
    final maxLength = math.max(
      28.0,
      math.min(104.0, roomRight / math.cos(-_rotation) - 6),
    );
    return tooltip(
      Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: layout.cellWidth * 0.4,
            bottom: 2,
            child: Transform(
              alignment: Alignment.bottomLeft,
              transform: Matrix4.rotationZ(_rotation),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxLength),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GiverDot(colorIndex: giver.colorIndex),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: style.copyWith(color: t.text),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// El nombre de quien regala bajo su punto, en la columna estrecha.
///
/// Nunca parte una palabra por la mitad: pasa a dos líneas por los espacios; si
/// la palabra más larga no cabe, rebaja el tamaño un poco (hasta el 78 %) y, si
/// aun así no cabe, queda en una línea acabada en «…». El nombre entero sigue
/// en el aviso y en la etiqueta de accesibilidad.
@visibleForTesting
class FittedGiverName extends StatelessWidget {
  const FittedGiverName({super.key, required this.name, required this.style});

  final String name;
  final TextStyle style;

  /// Factores de tamaño que se prueban, de mayor a menor.
  static const List<double> shrink = [1, 0.92, 0.85, 0.78];

  /// El mayor de [shrink] con el que cada palabra de [name] cabe entera en
  /// [maxWidth], o `null` si con ninguno.
  static double? factorFor({
    required String name,
    required TextStyle effective,
    required TextScaler scaler,
    required TextDirection direction,
    required double maxWidth,
    Locale? locale,
  }) {
    final words = name.trim().split(RegExp(r'\s+'));
    final base = effective.fontSize ?? 12;
    double longest(double factor) {
      var widest = 0.0;
      for (final word in words) {
        final painter = TextPainter(
          text: TextSpan(
            text: word,
            style: effective.copyWith(fontSize: base * factor),
          ),
          textDirection: direction,
          textScaler: scaler,
          locale: locale,
          maxLines: 1,
        )..layout();
        widest = math.max(widest, painter.width);
        painter.dispose();
      }
      return widest;
    }

    for (final factor in shrink) {
      if (longest(factor) <= maxWidth) {
        return factor;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    // El mismo estilo que acaba pintando `Text`: el de por defecto, el
    // propio y la negrita de accesibilidad.
    var effective = DefaultTextStyle.of(context).style.merge(style);
    if (MediaQuery.boldTextOf(context)) {
      effective = effective.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    return LayoutBuilder(
      builder: (context, box) {
        final base = effective.fontSize ?? 12;
        final chosen = factorFor(
          name: name,
          effective: effective,
          scaler: scaler,
          direction: direction,
          locale: locale,
          maxWidth: box.maxWidth,
        );
        if (chosen == null) {
          // Ni así cabe: una sola línea y puntos suspensivos.
          return Text(
            name,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
        }
        return Text(
          name,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: style.copyWith(fontSize: base * chosen),
        );
      },
    );
  }
}

/// La parte izquierda de una fila de la rejilla: el avatar, el nombre y,
/// debajo del nombre, [extras] (el motivo de que no salga y el enlace de los
/// regalos sin quién). Con letra grande los [extras] bajan debajo del avatar y
/// ocupan todo el ancho: a su lado no caben ni sus palabras más largas.
class _LeftCell extends StatelessWidget {
  const _LeftCell({
    required this.gap,
    required this.large,
    required this.avatar,
    required this.name,
    required this.extras,
  });

  final double gap;
  final bool large;
  final Widget avatar;
  final Widget name;
  final List<Widget> extras;

  @override
  Widget build(BuildContext context) {
    if (large) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              avatar,
              SizedBox(width: gap),
              Expanded(child: name),
            ],
          ),
          ...extras,
        ],
      );
    }
    return Row(
      children: [
        avatar,
        SizedBox(width: gap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [name, ...extras],
          ),
        ),
      ],
    );
  }
}

class _RecipientRow extends StatelessWidget {
  const _RecipientRow({
    required this.index,
    required this.introOnMount,
    required this.filterKey,
    required this.layout,
    required this.recipient,
    required this.givers,
    required this.stats,
    required this.duplicateCells,
    required this.marks,
    required this.bumps,
    required this.stage,
    required this.excluded,
    required this.secret,
    required this.excludedText,
    required this.skipLabel,
    required this.isSelf,
    required this.onOpenCell,
    required this.onOpenPerson,
  });

  final int index;
  final bool introOnMount;
  final String? filterKey;
  final RepartoLayout layout;
  final Recipient recipient;
  final List<Giver> givers;
  final Map<String, RepartoCellStats> stats;
  final Set<String> duplicateCells;
  final Map<String, List<String>> marks;
  final RepartoBumps bumps;
  final RepartoStage? stage;
  final bool excluded;

  /// Si la persona tiene regalos en secreto que este móvil no ve.
  final bool secret;
  final String excludedText;
  final String? skipLabel;

  /// Si es la persona dueña de este móvil («Yo»).
  final bool isSelf;
  final void Function(Recipient, Giver?, Rect, Color) onOpenCell;
  final void Function(Recipient, Rect) onOpenPerson;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final colors = repartoPersonColors(t, recipient.colorIndex);
    final unassigned = stats[repartoCellKey(recipient.id, null)];
    final unassignedCount = unassigned?.count ?? 0;
    void openPerson(Rect from) => onOpenPerson(recipient, from);
    final openLabel = l10n.repartoPersonOpen(
      isSelf ? l10n.repartoSelfName(recipient.name) : recipient.name,
    );
    final Widget name = RepartoAnchor(
      stage: stage,
      id: repartoNameAnchor(recipient.id),
      child: FitText(
        recipient.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: _scaled(repartoGridNameStyle(t), layout.textScale),
      ),
    );
    return Padding(
      padding: EdgeInsets.only(left: layout.pad),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: layout.rowHeight),
        child: Row(
          children: [
            // Nombre y avatar entran escalonados con el resto de la rejilla;
            // si un vuelo los trae desde la lista por ocasión, el vuelo ya
            // los mueve y aquí no se tocan.
            RepartoRowIntro(
              index: index,
              trigger: filterKey,
              onMount:
                  introOnMount &&
                  !(stage?.hidden.value.contains(
                        repartoNameAnchor(recipient.id),
                      ) ??
                      false),
              child: SizedBox(
                width: layout.leftWidth,
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _LeftCell(
                    gap: 7 * layout.textScale,
                    large: isLargeText(context),
                    avatar: _PersonTap(
                      label: openLabel,
                      onOpen: openPerson,
                      child: RepartoAnchor(
                        stage: stage,
                        id: repartoAvatarAnchor(recipient.id),
                        child: RepartoAvatar(
                          name: recipient.name,
                          colorIndex: recipient.colorIndex,
                          size: layout.avatarSize,
                        ),
                      ),
                    ),
                    name: _PersonTap(
                      label: openLabel,
                      onOpen: openPerson,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        // «Yo» va a la derecha del nombre si cabe y,
                        // si no, debajo. No viaja en el cambio de
                        // vista: se funde cuando llega su nombre.
                        child: isSelf
                            ? Wrap(
                                spacing: 5,
                                runSpacing: 2,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  name,
                                  RepartoAnchor(
                                    stage: stage,
                                    id: repartoSelfAnchor(recipient.id),
                                    child: const SelfTag(compact: true),
                                  ),
                                ],
                              )
                            : name,
                      ),
                    ),
                    extras: [
                      if (skipLabel != null)
                        RepartoAnchor(
                          stage: stage,
                          id: repartoSkipAnchor(recipient.id),
                          child: Text(
                            skipLabel!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: t.styles.caption.copyWith(
                              fontSize: 11 * layout.textScale,
                              height: 1.2,
                            ),
                          ),
                        ),
                      if (unassignedCount > 0)
                        _UnassignedLink(
                          stage: stage,
                          anchor: repartoUnassignedAnchor(recipient.id),
                          text: l10n.familyNoGiverCount(unassignedCount),
                          color: colors.ink,
                          fontSize: 11 * layout.textScale,
                          onOpen: (from) =>
                              onOpenCell(recipient, null, from, t.surface),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(
              width: layout.slot * givers.length,
              height: layout.rowHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Con la ocasión excluida las celdas se funden y la franja
                  // gris ocupa su sitio; siguen montadas, sin tocarse.
                  Positioned.fill(
                    child: _CellsFade(
                      hidden: excluded || secret,
                      child: Row(
                        children: [
                          for (var c = 0; c < givers.length; c++)
                            _RepartoCell(
                              key: ValueKey<String>(
                                repartoCellKey(recipient.id, givers[c].id),
                              ),
                              row: index,
                              column: c,
                              filterKey: filterKey,
                              introOnMount: introOnMount,
                              layout: layout,
                              recipient: recipient,
                              giver: givers[c],
                              stats:
                                  stats[repartoCellKey(
                                    recipient.id,
                                    givers[c].id,
                                  )] ??
                                  const RepartoCellStats(),
                              duplicate: duplicateCells.contains(
                                '${givers[c].id}|${recipient.id}',
                              ),
                              occasions:
                                  marks[repartoCellKey(
                                    recipient.id,
                                    givers[c].id,
                                  )] ??
                                  const <String>[],
                              bumps: bumps,
                              stage: stage,
                              onOpen: onOpenCell,
                            ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: (layout.rowHeight - layout.cellHeight) / 2,
                    width: layout.slot * givers.length - layout.gap,
                    height: layout.cellHeight,
                    child: ExcludedStrip(
                      shown: excluded,
                      text: excludedText,
                      onOpen: openPerson,
                    ),
                  ),
                  // Regalos en secreto: el bloque fijo ocupa el sitio de las
                  // celdas, sin cifras.
                  if (secret)
                    Positioned(
                      left: 0,
                      top: (layout.rowHeight - layout.cellHeight) / 2,
                      width: layout.slot * givers.length - layout.gap,
                      height: layout.cellHeight,
                      child: SecretStrip(
                        key: ValueKey<String>('secret-strip:${recipient.id}'),
                        shown: !excluded,
                        name: recipient.name,
                        colorIndex: recipient.colorIndex,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Las celdas de una fila: se funden (suave, `soft`) cuando se ocultan y,
/// ocultas, no se tocan ni las lee el lector de pantalla.
class _CellsFade extends StatelessWidget {
  const _CellsFade({required this.hidden, required this.child});

  final bool hidden;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = RegalosMotion.of(context);
    return ExcludeSemantics(
      excluding: hidden,
      child: IgnorePointer(
        ignoring: hidden,
        child: AnimatedOpacity(
          opacity: hidden ? 0 : 1,
          duration: motion.duration(RegalosSprings.softDuration),
          curve: motion.curve(Curves.easeOut),
          child: child,
        ),
      ),
    );
  }
}

/// El nombre (o el avatar) de una persona: al tocarlo se abre su ficha desde
/// donde está.
class _PersonTap extends StatelessWidget {
  const _PersonTap({
    required this.label,
    required this.onOpen,
    required this.child,
  });

  final String label;
  final void Function(Rect from) onOpen;
  final Widget child;

  void _tap(BuildContext context) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) {
      return;
    }
    onOpen(box.localToGlobal(Offset.zero) & box.size);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: label,
    excludeSemantics: true,
    onTap: () => _tap(context),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _tap(context),
      child: child,
    ),
  );
}

/// La franja gris lisa de una persona a la que no se le regala en la
/// ocasión que se ve: ocupa el sitio de todas las celdas, sin «+» ni borde
/// discontinuo, para que no se confunda con un hueco vacío. Entra con
/// `scaleX` 0,9 → 1 y un fundido (`snap`); con «Reducir movimiento», solo
/// el fundido de 150 ms.
class ExcludedStrip extends StatefulWidget {
  /// Crea la franja; [shown] la enseña o la retira.
  const ExcludedStrip({
    super.key,
    required this.shown,
    required this.text,
    required this.onOpen,
  });

  /// Si hay que enseñarla.
  final bool shown;

  /// «No le regaláis en Navidad».
  final String text;

  /// Al tocarla se abre la ficha de la persona.
  final void Function(Rect from) onOpen;

  @override
  State<ExcludedStrip> createState() => _ExcludedStripState();
}

class _ExcludedStripState extends State<ExcludedStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(
    vsync: this,
    value: widget.shown ? 1 : 0,
  );

  @override
  void didUpdateWidget(ExcludedStrip old) {
    super.didUpdateWidget(old);
    if (old.shown == widget.shown) {
      return;
    }
    final reduce = RegalosMotion.of(context).reduce;
    if (!widget.shown || reduce) {
      _c.animateTo(
        widget.shown ? 1 : 0,
        duration: RegalosMotion.fade,
        curve: Curves.linear,
      );
      return;
    }
    _c.animateWith(SpringSimulation(RegalosSprings.snap, _c.value, 1, 0));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _tap() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) {
      return;
    }
    widget.onOpen(box.localToGlobal(Offset.zero) & box.size);
  }

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final reduce = RegalosMotion.of(context).reduce;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final v = _c.value;
        if (!widget.shown && v <= 0.001) {
          return const SizedBox.shrink();
        }
        final face = Semantics(
          container: true,
          button: true,
          label: widget.text,
          excludeSemantics: true,
          onTap: _tap,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _tap,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: RegalosShape.card,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StrokeIcon(AppIcons.ban, size: 16, color: t.ideaStroke),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          widget.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: t.styles.caption.copyWith(
                            fontSize: 12,
                            height: 1.2,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: reduce
              ? face
              : Transform.scale(
                  scaleX: 0.9 + 0.1 * v,
                  alignment: Alignment.centerLeft,
                  child: face,
                ),
        );
      },
    );
  }
}

// «2 sin quién» bajo el nombre: abre los regalos sin quién regala.
class _UnassignedLink extends StatelessWidget {
  const _UnassignedLink({
    required this.stage,
    required this.anchor,
    required this.text,
    required this.color,
    required this.fontSize,
    required this.onOpen,
  });

  final RepartoStage? stage;
  final String anchor;
  final String text;
  final Color color;
  final double fontSize;
  final void Function(Rect from) onOpen;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Semantics(
      container: true,
      button: true,
      label: text,
      excludeSemantics: true,
      onTap: () => _tap(context),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _tap(context),
        child: RepartoAnchor(
          stage: stage,
          id: anchor,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            // Con letra grande el número y las dos palabras no caben en dos
            // líneas del hueco de la columna: hasta tres, sin cortar.
            child: FitText(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: t.styles.caption.copyWith(
                fontSize: fontSize,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _tap(BuildContext context) {
    final box = context.findRenderObject()! as RenderBox;
    onOpen(box.localToGlobal(Offset.zero) & box.size);
  }
}

class _RepartoCell extends StatefulWidget {
  const _RepartoCell({
    super.key,
    required this.row,
    required this.column,
    required this.filterKey,
    required this.introOnMount,
    required this.layout,
    required this.recipient,
    required this.giver,
    required this.stats,
    required this.duplicate,
    required this.occasions,
    required this.bumps,
    required this.stage,
    required this.onOpen,
  });

  /// Fila y columna de la celda, para su sitio en la onda de entrada.
  final int row;
  final int column;

  /// El filtro de ocasión que se ve (al cambiar, la celda vuelve a entrar).
  final String? filterKey;

  /// Si la rejilla acaba de montarse y las celdas entran escalonadas.
  final bool introOnMount;
  final RepartoLayout layout;
  final Recipient recipient;
  final Giver giver;
  final RepartoCellStats stats;
  final bool duplicate;
  final List<String> occasions;
  final RepartoBumps bumps;
  final RepartoStage? stage;
  final void Function(Recipient, Giver?, Rect, Color) onOpen;

  @override
  State<_RepartoCell> createState() => _RepartoCellState();
}

class _RepartoCellState extends State<_RepartoCell> {
  final GlobalKey _visual = GlobalKey();
  final GlobalKey<SpringPulseState> _pulse = GlobalKey<SpringPulseState>();
  bool _down = false;

  String get _anchor => repartoCellAnchor(widget.recipient.id, widget.giver.id);

  @override
  void initState() {
    super.initState();
    // Cuando llega el último regalo de un vuelo, la celda rebota.
    widget.stage?.onLanding(
      _anchor,
      () =>
          _pulse.currentState?.play(from: 0.88, spring: RegalosSprings.bounce),
    );
  }

  @override
  void dispose() {
    widget.stage?.onLanding(_anchor, null);
    super.dispose();
  }

  @override
  void didUpdateWidget(_RepartoCell old) {
    super.didUpdateWidget(old);
    if (old.stats == widget.stats) {
      return;
    }
    final key = repartoCellKey(widget.recipient.id, widget.giver.id);
    final bumped = widget.bumps.consume(key);
    // Un filtro nuevo ya trae su entrada escalonada (`RepartoCellIntro`): el
    // pulso suave de la celda sería una segunda animación encima.
    if (!bumped && old.filterKey != widget.filterKey) {
      return;
    }
    // Un regalo que cambia de quien regala: la celda rebota con su número
    // nuevo. Un filtro: se funde con suavidad.
    _pulse.currentState?.play(
      from: bumped ? 0.78 : 0.9,
      spring: bumped ? RegalosSprings.bounce : RegalosSprings.soft,
      opacityFrom: bumped ? 1 : 0.3,
    );
  }

  void _open() {
    final t = RegalosTokens.of(context);
    final colors = repartoPersonColors(t, widget.recipient.colorIndex);
    final box = _visual.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) {
      return;
    }
    final from = box.localToGlobal(Offset.zero) & box.size;
    widget.onOpen(
      widget.recipient,
      widget.giver,
      from,
      widget.stats.kind == RepartoCellKind.allBought ? colors.fill : t.bg,
    );
  }

  String _semantics(AppLocalizations l10n) {
    final giverName = giverNameFor(l10n, widget.giver);
    final personName = widget.recipient.name;
    final s = widget.stats;
    if (s.count == 0) {
      return l10n.familyCellEmptyLabel(giverName, personName);
    }
    final price = s.cents > 0
        ? formatCents(s.cents, l10n.localeName)
        : l10n.familyNoPrice;
    final state = s.kind == RepartoCellKind.allBought
        ? l10n.familyLegendAllBought.toLowerCase()
        : l10n.familyLegendPending.toLowerCase();
    final label = StringBuffer(
      l10n.familyCellLabel(
        giverName,
        personName,
        l10n.giftCount(s.count),
        price,
        state,
      ),
    );
    if (widget.occasions.isNotEmpty) {
      label.write(', ${l10n.familyCellOccasions(widget.occasions.join(', '))}');
    }
    if (widget.duplicate) {
      label.write(', ${l10n.familyLegendDuplicate.toLowerCase()}');
    }
    return label.toString();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final layout = widget.layout;
    final motion = RegalosMotion.of(context);
    // Al abrir la pantalla, al cambiar el filtro y al volver de la lista, las
    // celdas entran en onda: tras el nombre de su fila y de izquierda a
    // derecha. Las que son destino de un vuelo esperan ocultas y no se mueven;
    // el último regalo que llega las hace rebotar.
    final awaitsFlight = widget.stage?.hidden.value.contains(_anchor) ?? false;
    return RepartoCellIntro(
      row: widget.row,
      column: widget.column,
      trigger: widget.filterKey,
      onMount:
          widget.introOnMount &&
          (widget.stats.kind == RepartoCellKind.nothing || !awaitsFlight),
      landing: widget.stats.kind != RepartoCellKind.nothing,
      child: Semantics(
        container: true,
        button: true,
        label: _semantics(l10n),
        excludeSemantics: true,
        onTap: _open,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: _open,
          child: SizedBox(
            width: layout.slot,
            height: layout.rowHeight,
            child: Center(
              child: SpringPulse(
                key: _pulse,
                child: AnimatedScale(
                  scale: _down && !motion.reduce ? 0.94 : 1,
                  duration: _down
                      ? const Duration(milliseconds: 90)
                      : RegalosSprings.bounceDuration,
                  curve: _down ? Curves.easeOut : RegalosCurves.bounce,
                  child: RepartoAnchor(
                    stage: widget.stage,
                    id: _anchor,
                    child: SizedBox(
                      key: _visual,
                      width: layout.cellWidth,
                      height: layout.cellHeight,
                      child: _CellFace(
                        layout: layout,
                        recipient: widget.recipient,
                        stats: widget.stats,
                        duplicate: widget.duplicate,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CellFace extends StatelessWidget {
  const _CellFace({
    required this.layout,
    required this.recipient,
    required this.stats,
    required this.duplicate,
  });

  final RepartoLayout layout;
  final Recipient recipient;
  final RepartoCellStats stats;
  final bool duplicate;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final motion = RegalosMotion.of(context);
    final colors = repartoPersonColors(t, recipient.colorIndex);
    final kind = stats.kind;
    final numberStyle = TextStyle(
      fontSize: layout.numberSize,
      height: 1,
      fontWeight: FontWeight.w700,
      color: kind == RepartoCellKind.allBought ? colors.ink : t.text,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2);
    final Widget face = switch (kind) {
      RepartoCellKind.nothing => DashedBox(
        key: const ValueKey<RepartoCellKind>(RepartoCellKind.nothing),
        color: t.outline,
        radius: RegalosShape.cardRadius,
        strokeWidth: 1.2,
        child: Center(
          child: StrokeIcon(
            AppIcons.plus,
            size: layout.plusSize,
            color: t.ideaStroke,
          ),
        ),
      ),
      _ => DecoratedBox(
        key: ValueKey<RepartoCellKind>(kind),
        decoration: BoxDecoration(
          color: kind == RepartoCellKind.allBought ? colors.fill : t.bg,
          borderRadius: RegalosShape.card,
          border: Border.all(
            color: kind == RepartoCellKind.allBought
                ? colors.fill
                : t.chipBorder,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRect(
              child: AnimatedSwitcher(
                duration: motion.duration(RegalosSprings.snapDuration),
                reverseDuration: RegalosMotion.fade,
                switchInCurve: motion.curve(RegalosCurves.snap),
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => motion.reduce
                    ? FadeTransition(opacity: animation, child: child)
                    : FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.8),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                child: Text(
                  '${stats.count}',
                  key: ValueKey<int>(stats.count),
                  textScaler: scaler,
                  style: numberStyle,
                ),
              ),
            ),
            SizedBox(
              height:
                  (kind == RepartoCellKind.allBought ? 3 : 5) * layout.scale,
            ),
            if (kind == RepartoCellKind.allBought)
              StrokeIcon(
                AppIcons.check,
                size: layout.checkSize,
                color: colors.ink,
                strokeWidth: 2.25 * layout.textScale,
              )
            else
              _ProgressBar(
                width: layout.barWidth,
                height: layout.barHeight,
                fraction: stats.count == 0 ? 0 : stats.bought / stats.count,
                color: colors.ink,
                track: t.track,
              ),
          ],
        ),
      ),
    };
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: motion.reduce
                ? RegalosMotion.fade
                : const Duration(milliseconds: 200),
            layoutBuilder: (current, previous) =>
                Stack(fit: StackFit.expand, children: [...previous, ?current]),
            child: face,
          ),
        ),
        if (duplicate)
          Positioned(
            top: -5,
            right: -5,
            child: _DuplicateMark(scale: layout.textScale),
          ),
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.width,
    required this.height,
    required this.fraction,
    required this.color,
    required this.track,
  });

  final double width;
  final double height;
  final double fraction;
  final Color color;
  final Color track;

  @override
  Widget build(BuildContext context) {
    final motion = RegalosMotion.of(context);
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.all(Radius.circular(height / 2)),
        child: ColoredBox(
          color: track,
          child: Align(
            alignment: Alignment.centerLeft,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: fraction),
              duration: motion.duration(RegalosSprings.snapDuration),
              curve: motion.curve(RegalosCurves.snap),
              builder: (context, value, _) => FractionallySizedBox(
                widthFactor: value.clamp(0.0, 1.0),
                heightFactor: 1,
                child: ColoredBox(color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La marca de posible duplicado en la esquina de la celda.
class _DuplicateMark extends StatelessWidget {
  const _DuplicateMark({this.scale = 1});

  /// Cuánto crece (1 en el móvil).
  final double scale;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final warn = AccentId.butter.palette;
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: warn.fillOf(t.isDark),
          borderRadius: const BorderRadius.all(Radius.circular(4)),
          border: Border.all(color: t.bg, width: 2),
        ),
        child: SizedBox.square(
          dimension: 16 * scale,
          child: Center(
            child: Text(
              '!',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 11 * scale,
                height: 1,
                fontWeight: FontWeight.w800,
                color: t.isDark ? warn.onFill : warn.tinta,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fila de totales y leyenda.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.layout,
    required this.givers,
    required this.recipients,
    required this.stats,
    required this.outside,
    required this.onOpenPerson,
    required this.onInclude,
  });

  final RepartoLayout layout;
  final List<Giver> givers;
  final List<Recipient> recipients;
  final Map<String, RepartoCellStats> stats;
  final List<Recipient> outside;
  final void Function(Recipient, Rect) onOpenPerson;
  final ValueChanged<Recipient> onInclude;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    var cents = 0;
    final perGiver = <String, int>{for (final g in givers) g.id: 0};
    for (final r in recipients) {
      for (final g in [...givers.map((g) => g.id), '']) {
        final s = stats[repartoCellKey(r.id, g.isEmpty ? null : g)];
        if (s == null) {
          continue;
        }
        cents += s.cents;
        if (perGiver.containsKey(g)) {
          perGiver[g] = perGiver[g]! + s.count;
        }
      }
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(layout.pad, 4, layout.pad, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.separator)),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: layout.rowHeight),
              child: Row(
                children: [
                  SizedBox(
                    width: layout.leftWidth,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.familyTotalRow,
                            style: _scaled(
                              t.styles.metaStrong.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              layout.textScale,
                            ),
                          ),
                          // Un importe no se corta con «…»: con letra grande
                          // se encoge hasta caber.
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              cents > 0
                                  ? formatCents(cents, l10n.localeName)
                                  : l10n.familyNoPrice,
                              maxLines: 1,
                              style: t.styles.caption.copyWith(
                                fontSize: 11 * layout.textScale,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  for (final g in givers)
                    SizedBox(
                      width: layout.slot,
                      child: Semantics(
                        label:
                            '${giverNameFor(l10n, g)}: ${l10n.giftCount(perGiver[g.id]!)}',
                        excludeSemantics: true,
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.only(right: layout.gap),
                            // Como las celdas de arriba: la cifra no pasa de
                            // 1,2 veces y, si aun así no cabe en la columna
                            // (320 px, seis columnas, dos cifras), se encoge.
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '${perGiver[g.id]}',
                                maxLines: 1,
                                softWrap: false,
                                textScaler: MediaQuery.textScalerOf(context)
                                    .clamp(maxScaleFactor: 1.2),
                                style: t.styles.metaStrong.copyWith(
                                  fontSize: math.min(
                                    15 * layout.textScale,
                                    layout.numberSize,
                                  ),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          OutsideBlock(
            outside: outside,
            onOpenPerson: onOpenPerson,
            onInclude: onInclude,
          ),
          _Legend(scale: layout.textScale),
        ],
      ),
    );
  }
}

/// La leyenda de los tres estados de una celda: Nada, Por comprar y Todo
/// comprado.
class _Legend extends StatelessWidget {
  const _Legend({this.scale = 1});

  /// Cuánto crece (1 en el móvil).
  final double scale;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final accent = repartoPersonColors(t, 0);
    Widget item(Widget mark, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(width: 6 * scale),
        Text(text, style: t.styles.caption.copyWith(fontSize: 12 * scale)),
      ],
    );
    final markWidth = 16 * scale;
    final markHeight = 12 * scale;
    // El móvil, con su 3 de siempre; con las marcas más grandes, el radio
    // pequeño del diseño.
    final markRadius = scale > 1 ? RegalosShape.tinyRadius : 3.0;
    return Padding(
      padding: EdgeInsets.only(top: 14 * scale),
      child: Wrap(
        spacing: 16 * scale,
        runSpacing: 6 * scale,
        children: [
          item(
            DashedBox(
              color: t.outline,
              radius: markRadius,
              strokeWidth: 1,
              child: SizedBox(width: markWidth, height: markHeight),
            ),
            l10n.familyLegendNothing,
          ),
          item(
            Container(
              width: markWidth,
              height: markHeight,
              decoration: BoxDecoration(
                color: t.bg,
                border: Border.all(color: t.chipBorder),
                borderRadius: BorderRadius.all(Radius.circular(markRadius)),
              ),
            ),
            l10n.familyLegendToBuy,
          ),
          item(
            Container(
              width: markWidth,
              height: markHeight,
              decoration: BoxDecoration(
                color: accent.fill,
                borderRadius: BorderRadius.all(Radius.circular(markRadius)),
              ),
            ),
            l10n.familyLegendAllBought,
          ),
          item(
            Container(
              width: markWidth,
              height: markHeight,
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.all(Radius.circular(markRadius)),
              ),
            ),
            l10n.familyLegendExcluded,
          ),
        ],
      ),
    );
  }
}
