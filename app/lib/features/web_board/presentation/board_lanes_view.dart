import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/money.dart';
import '../../../core/motion/animated_rows.dart';
import '../../../core/motion/rect_flight.dart';
import '../../../core/sync/model.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/gift_status_map.dart';
import '../../../core/widgets/person_avatar.dart';
import '../../../core/widgets/pointer_surface.dart';
import '../../../core/widgets/status_checkbox.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_providers.dart';
import '../../family/presentation/family_texts.dart';
import '../../gifts/presentation/gift_actions.dart';
import '../../gifts/presentation/gift_editor_screen.dart';
import '../application/board_lanes.dart';
import '../application/board_metrics.dart';
import '../application/gift_editor_panel.dart';
import 'board_cursor.dart';

/// Lo que cuenta la segunda línea de cada fila del tablero.
enum BoardRowSubtitle {
  /// Persona, ocasión y quien regala (el tablero «Hoy»).
  all,

  /// Persona y quien regala (el tablero de una ocasión).
  perOccasion,
}

/// Cómo se reparten los carriles en un ancho dado
/// (la guía de diseño de escritorio, «Carriles»).
///
/// Siempre una sola fila, de 248 a 520 de ancho cada carril. Si los cinco no
/// caben cómodos, «Listo» se pliega en una columna de 56; si aún no caben los
/// otros cuatro, el tablero se desplaza en horizontal.
class BoardLanesLayout {
  const BoardLanesLayout._({
    required this.fold,
    required this.scrolls,
    required this.laneWidth,
    required this.readyWidth,
    required this.total,
  });

  /// Si «Listo» va plegado en su columna de [BoardLanesView.foldedWidth].
  final bool fold;

  /// Si el tablero se desplaza en horizontal.
  final bool scrolls;

  /// El ancho de cada uno de los cuatro primeros carriles.
  final double laneWidth;

  /// El ancho de «Listo» (el de un carril o el de la columna plegada).
  final double readyWidth;

  /// El ancho de toda la fila de carriles.
  final double total;

  /// El reparto para [width] de sitio. [foldPhase] (0 a 1) lleva «Listo» de su
  /// carril a la columna plegada al cambiar de forma.
  static BoardLanesLayout of(double width, {double? foldPhase}) {
    const gap = BoardLanesView.gap;
    const min = BoardLanesView.minLaneWidth;
    const max = BoardLanesView.maxLaneWidth;
    const comfy = BoardLanesView.comfortLaneWidth;
    const folded = BoardLanesView.foldedWidth;
    final five = (width - 4 * gap) / 5;
    final fold = five < comfy;
    final phase = foldPhase ?? (fold ? 1.0 : 0.0);
    final fiveClamped = math.min(five, max);
    final readyW = fiveClamped + (folded - fiveClamped) * phase;
    final four = (width - 4 * gap - readyW) / 4;
    final scrolls = fold && four < min;
    final lane = scrolls ? min : math.min(four, max);
    final ready = scrolls ? folded : readyW;
    return BoardLanesLayout._(
      fold: fold,
      scrolls: scrolls,
      laneWidth: lane,
      readyWidth: ready,
      total: 4 * lane + ready + 4 * gap,
    );
  }
}

/// Los carriles del tablero «Qué toca ahora»
/// (la guía de diseño de escritorio): una columna por lo que
/// le falta a cada regalo, siempre en una sola fila y con el alto de la
/// ventana. La cabecera de cada carril es fija y las filas se desplazan por
/// dentro. Si no caben los cinco, «Listo» se pliega en una columna de 56 (al
/// tocarla se abre encima) y, si aún no caben, el tablero se desplaza en
/// horizontal con un degradado en el borde.
///
/// Con [occasionId], solo los regalos de esa ocasión. Al marcar un regalo (la
/// casilla), la fila viaja a su carril nuevo.
class BoardLanesView extends ConsumerStatefulWidget {
  /// Crea los carriles.
  const BoardLanesView({
    super.key,
    this.occasionId,
    this.subtitle = BoardRowSubtitle.all,
    required this.onAdd,
  });

  /// La ocasión de la que se enseñan los regalos, o `null` para todos.
  final String? occasionId;

  /// Qué dice la segunda línea de las filas.
  final BoardRowSubtitle subtitle;

  /// Añade un regalo (desde el carril «Por decidir»).
  final VoidCallback onAdd;

  /// El ancho mínimo de un carril.
  static const double minLaneWidth = 248;

  /// El ancho de un carril por debajo del cual los cinco no caben cómodos y
  /// «Listo» se pliega.
  static const double comfortLaneWidth = 280;

  /// El ancho máximo de un carril.
  static const double maxLaneWidth = 520;

  /// El ancho de «Listo» plegado.
  static const double foldedWidth = 56;

  /// El hueco entre carriles.
  static const double gap = 16;

  /// El alto mínimo de los carriles.
  static const double minHeight = 360;

  /// Cuántos carriles enteros caben en [width] (los cinco, o cuatro con
  /// «Listo» plegado).
  static int columnsFor(double width) =>
      BoardLanesLayout.of(width).fold ? BoardLane.values.length - 1 : 5;

  @override
  ConsumerState<BoardLanesView> createState() => _BoardLanesViewState();
}

class _BoardLanesViewState extends ConsumerState<BoardLanesView> {
  bool _readyOpen = false;
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(boardLanesProvider(widget.occasionId));
    final reduce = RegalosMotion.of(context).reduce;
    return LayoutBuilder(
      builder: (context, box) {
        final fold = BoardLanesLayout.of(box.maxWidth).fold;
        // El orden de las flechas del teclado: carril a carril, sin los
        // regalos de un «Listo» que no se ve.
        ref.read(boardGiftCursorProvider).register([
          for (final lane in BoardLane.values)
            if (!(fold && lane == BoardLane.ready))
              for (final gift in groups[lane] ?? const <Gift>[]) gift.id,
        ]);
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: fold ? 1 : 0),
          duration: reduce
              ? RegalosMotion.fade
              : const Duration(milliseconds: 280),
          curve: reduce ? Curves.linear : Curves.easeOutCubic,
          builder: (context, phase, _) {
            final layout = BoardLanesLayout.of(box.maxWidth, foldPhase: phase);
            final height = math.max(BoardLanesView.minHeight, box.maxHeight);
            Widget lane(BoardLane l, double width) => SizedBox(
              width: width,
              child: BoardLaneColumn(
                lane: l,
                gifts: groups[l] ?? const <Gift>[],
                subtitle: widget.subtitle,
                onAdd: l == BoardLane.decide ? widget.onAdd : null,
              ),
            );
            final ready = groups[BoardLane.ready] ?? const <Gift>[];
            final lanes = SizedBox(
              width: layout.total,
              height: height,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final l in BoardLane.values.take(4)) ...[
                    lane(l, layout.laneWidth),
                    const SizedBox(width: BoardLanesView.gap),
                  ],
                  SizedBox(
                    width: layout.readyWidth,
                    child: phase > 0.5
                        ? _FoldedReady(
                            count: ready.length,
                            open: _readyOpen,
                            onTap: () =>
                                setState(() => _readyOpen = !_readyOpen),
                          )
                        // Mientras se pliega, el carril sigue midiendo lo de
                        // un carril y se recorta: no se reparte en un hueco
                        // más estrecho que el mínimo.
                        : ClipRect(
                            child: OverflowBox(
                              alignment: Alignment.topLeft,
                              minWidth: math.max(
                                layout.readyWidth,
                                BoardLanesView.minLaneWidth,
                              ),
                              maxWidth: math.max(
                                layout.readyWidth,
                                BoardLanesView.minLaneWidth,
                              ),
                              child: BoardLaneColumn(
                                lane: BoardLane.ready,
                                gifts: ready,
                                subtitle: widget.subtitle,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            );
            final popover = _readyOpen && phase > 0.5;
            Widget content = layout.scrolls
                ? _HorizontalFade(controller: _scroll, child: lanes)
                : lanes;
            if (box.maxHeight < BoardLanesView.minHeight) {
              content = SingleChildScrollView(child: content);
            }
            return Stack(
              children: [
                Positioned.fill(
                  child: Align(alignment: Alignment.topLeft, child: content),
                ),
                if (popover) ...[
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => setState(() => _readyOpen = false),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    width: 300,
                    child: _ReadyPopover(
                      child: BoardLaneColumn(
                        lane: BoardLane.ready,
                        gifts: ready,
                        subtitle: widget.subtitle,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

/// El carril «Listo» abierto encima del tablero, con sombra.
class _ReadyPopover extends StatelessWidget {
  const _ReadyPopover({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: RegalosMotion.of(context)
          .duration(const Duration(milliseconds: 220)),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(16 * (1 - v), 0),
          child: child,
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.bg,
          borderRadius: RegalosShape.card,
          boxShadow: [
            BoxShadow(
              color: t.shadow,
              blurRadius: 28,
              offset: const Offset(-4, 4),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

/// «Listo» plegado: una columna de 56 con el número y el título girado.
class _FoldedReady extends StatelessWidget {
  const _FoldedReady({
    required this.count,
    required this.open,
    required this.onTap,
  });

  final int count;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return Semantics(
      button: true,
      expanded: open,
      label: '${l10n.boardLaneReady}, $count',
      excludeSemantics: true,
      onTap: onTap,
      child: Tooltip(
        message: l10n.boardLaneReady,
        excludeFromSemantics: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: RegalosShape.card,
          ),
          child: PointerSurface(
            strength: 1.6,
            child: Material(
              color: Colors.transparent,
              borderRadius: RegalosShape.card,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    children: [
                      Text('$count', style: t.styles.sectionTitle),
                      const SizedBox(height: 12),
                      Expanded(
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: Text(
                            l10n.boardLaneReady,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.styles.meta,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      StrokeIcon(
                        AppIcons.check,
                        size: 16,
                        color: t.textSecondary,
                        strokeWidth: 2,
                      ),
                    ],
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

/// Una fila de carriles que se desplaza en horizontal, con un degradado en el
/// borde mientras queda más por ver.
class _HorizontalFade extends StatelessWidget {
  const _HorizontalFade({required this.controller, required this.child});

  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Stack(
      children: [
        Scrollbar(
          controller: controller,
          child: SingleChildScrollView(
            controller: controller,
            scrollDirection: Axis.horizontal,
            child: child,
          ),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: 40,
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                final more =
                    !controller.hasClients ||
                    !controller.position.hasContentDimensions ||
                    controller.position.pixels <
                        controller.position.maxScrollExtent - 2;
                return AnimatedOpacity(
                  opacity: more ? 1 : 0,
                  duration: RegalosMotion.fade,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [t.bg.withValues(alpha: 0), t.bg],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

String _laneTitle(AppLocalizations l10n, BoardLane lane) => switch (lane) {
  BoardLane.decide => l10n.boardLaneDecide,
  BoardLane.buy => l10n.boardLaneBuy,
  BoardLane.arrive => l10n.boardLaneArrive,
  BoardLane.wrap => l10n.boardLaneWrap,
  BoardLane.ready => l10n.boardLaneReady,
};

/// Un carril: su cabecera fija (el nombre, cuántos y la suma) y sus filas, que
/// se desplazan dentro. El fondo llega hasta abajo.
class BoardLaneColumn extends ConsumerWidget {
  /// Crea el carril.
  const BoardLaneColumn({
    super.key,
    required this.lane,
    required this.gifts,
    required this.subtitle,
    this.onAdd,
  });

  /// El carril.
  final BoardLane lane;

  /// Sus regalos, ya por orden.
  final List<Gift> gifts;

  /// Qué dice la segunda línea de las filas.
  final BoardRowSubtitle subtitle;

  /// Si lleva «Añadir regalo» abajo.
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final sum = centsOf(gifts);
    return Semantics(
      container: true,
      label: _laneTitle(l10n, lane),
      child: DecoratedBox(
        key: ValueKey<String>('board-lane-${lane.name}'),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: RegalosShape.card,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(
                              _laneTitle(l10n, lane),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.styles.sectionTitle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('${gifts.length}', style: t.styles.meta),
                        ],
                      ),
                    ),
                    if (sum > 0)
                      Text(
                        formatCents(sum, l10n.localeName),
                        style: t.styles.meta,
                      ),
                  ],
                ),
              ),
              Expanded(
                child: gifts.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        child: Text(l10n.boardLaneEmpty, style: t.styles.meta),
                      )
                    : _LaneList(gifts: gifts, subtitle: subtitle),
              ),
              if (onAdd != null) _AddInline(onTap: onAdd!),
            ],
          ),
        ),
      ),
    );
  }
}

/// Las filas de un carril, con su propia barra de desplazamiento.
class _LaneList extends StatefulWidget {
  const _LaneList({required this.gifts, required this.subtitle});

  final List<Gift> gifts;
  final BoardRowSubtitle subtitle;

  @override
  State<_LaneList> createState() => _LaneListState();
}

class _LaneListState extends State<_LaneList> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      child: SingleChildScrollView(
        controller: _controller,
        padding: const EdgeInsets.only(bottom: 4),
        child: AnimatedRows(
          rows: [
            for (final gift in widget.gifts)
              AnimatedRowItem(
                id: gift.id,
                child: BoardGiftRow(gift: gift, subtitle: widget.subtitle),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddInline extends StatelessWidget {
  const _AddInline({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: PointerSurface(
        strength: 1.6,
        child: InkWell(
          onTap: onTap,
          borderRadius: RegalosShape.card,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                StrokeIcon(
                  AppIcons.plus,
                  size: 16,
                  color: t.textSecondary,
                  strokeWidth: 2,
                ),
                const SizedBox(width: 8),
                Text(l10n.giftAdd, style: t.styles.meta),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// La segunda línea de una fila: persona, ocasión y quien regala. Si entera no
/// cabe, quita quién regala; y si aun así no cabe, se corta con «…».
class _SecondLine extends StatelessWidget {
  const _SecondLine({
    required this.parts,
    required this.giverName,
    required this.style,
  });

  final List<String> parts;
  final String giverName;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final full = [...parts, giverName].join(' · ');
        final painter = TextPainter(
          text: TextSpan(text: full, style: style),
          textDirection: direction,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        final fits = painter.width <= box.maxWidth - 8;
        painter.dispose();
        return Text(
          fits ? full : parts.join(' · '),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: style,
        );
      },
    );
  }
}

/// Una fila de regalo del tablero, de 52 de alto y dos líneas: la casilla de
/// estado, quien lo recibe (el avatar solo desde 300 de carril), el título y,
/// debajo, persona, ocasión y quien regala (lo que se recorta es quien
/// regala), y el precio. Tocarla abre el editor, que se queda a la derecha; la
/// fila que se edita lleva el filete de tinta y la marcada con el teclado, el
/// fondo suave.
class BoardGiftRow extends ConsumerWidget {
  /// Crea la fila.
  const BoardGiftRow({super.key, required this.gift, required this.subtitle});

  /// El regalo.
  final Gift gift;

  /// Qué dice la segunda línea.
  final BoardRowSubtitle subtitle;

  /// El alto de la fila (con un título de dos líneas, más).
  static const double height = 52;

  /// Por debajo de este ancho de carril el título admite dos líneas.
  static const double twoLinesBelow = 320;

  /// El ancho de carril desde el que sale el avatar.
  static const double avatarFrom = 320;

  /// La clave con la que vuela la fila de un carril a otro.
  static Object flightKeyOf(String giftId) => ('board-gift', giftId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final view = ref.watch(familyViewProvider);
    final full = ref.watch(familyFullViewProvider);
    final person = full.recipientsById[gift.recipientId];
    final giver = view.giversById[gift.giverId];
    final occasion = view.occasionsById[gift.occasionId];
    final labels = OccasionLabels(l10n, full.recipientsById);
    final giverName = giver == null
        ? l10n.giverUnassigned
        : giverDisplayName(l10n, giver.name);
    final parts = <String>[
      if (person != null) person.name,
      if (subtitle == BoardRowSubtitle.all && occasion != null)
        labels.of(occasion),
    ];
    final cents = gift.actualCents ?? gift.plannedCents;
    final panel = ref.read(giftEditorPanelProvider);
    return LayoutBuilder(
      builder: (context, box) => _build(
        context,
        ref,
        panel: panel,
        // Sin avatar por debajo de 320 de carril (ya descontados los 16 del
        // relleno del carril): quien recibe ya va en la segunda línea.
        showAvatar: box.maxWidth >= avatarFrom - 16,
        // En un carril de menos de 320 el título admite dos líneas, con la
        // fila más alta.
        twoLineTitle: box.maxWidth < twoLinesBelow - 16,
        t: t,
        l10n: l10n,
        person: person,
        parts: parts,
        giverName: giverName,
        cents: cents,
      ),
    );
  }

  Widget _build(
    BuildContext context,
    WidgetRef ref, {
    required GiftEditorPanelController panel,
    required bool showAvatar,
    required bool twoLineTitle,
    required String giverName,
    required RegalosTokens t,
    required AppLocalizations l10n,
    required Recipient? person,
    required List<String> parts,
    required int? cents,
  }) {
    return BoardCursorTarget(
      giftId: gift.id,
      builder: (context, marked) => ListenableBuilder(
        listenable: panel,
        builder: (context, _) {
          final editing = panel.request?.gift?.id == gift.id;
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: FlightTarget(
              flightKey: flightKeyOf(gift.id),
              child: Builder(
                builder: (rowContext) => ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: height),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: editing ? t.soft : t.bg,
                      borderRadius: RegalosShape.card,
                      border: Border.all(
                        color: editing
                            ? t.ink
                            : (marked ? t.controlBorder : t.separator),
                        width: editing ? 1.5 : 1,
                      ),
                    ),
                    child: PointerSurface(
                      strength: 2.2,
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: RegalosShape.card,
                        clipBehavior: Clip.antiAlias,
                        child: Row(
                          children: [
                            StatusCheckbox(
                              status: gift.status.visualStatus,
                              itemName: gift.title,
                              onTap: () {
                                final rect = globalRectOf(rowContext);
                                if (rect != null) {
                                  ref
                                      .read(flightRegistryProvider)
                                      .depart(flightKeyOf(gift.id), rect);
                                }
                                advanceGiftStatus(context, ref, gift);
                              },
                              onLongPress: () =>
                                  showGiftStatusPicker(context, ref, gift),
                            ),
                            if (person != null && showAvatar) ...[
                              PersonAvatar(
                                name: person.name,
                                colorIndex: person.colorIndex,
                                size: 28,
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: InkWell(
                                onTap: () {
                                  ref
                                      .read(boardGiftCursorProvider)
                                      .set(gift.id);
                                  openGiftEditor(context, gift: gift);
                                },
                                child: Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text(
                                        gift.title,
                                        maxLines: twoLineTitle ? 2 : 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: t.styles.label,
                                      ),
                                      _SecondLine(
                                        parts: parts,
                                        giverName: giverName,
                                        style: t.styles.caption,
                                      ),
                                      const SizedBox(height: 4),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (cents != null)
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 8,
                                  right: 12,
                                ),
                                child: Text(
                                  formatCents(cents, l10n.localeName),
                                  style: t.styles.metaStrong,
                                ),
                              )
                            else
                              const SizedBox(width: 12),
                          ],
                        ),
                      ),
                    ),
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
