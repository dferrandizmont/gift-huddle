import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/money.dart';
import '../../../core/layout/touch_targets.dart';
import '../../../core/motion/animated_rows.dart';
import '../../../core/motion/rect_flight.dart';
import '../../../core/sync/model.dart';
import '../../../core/theme/app_scrollbar.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/gift_status_map.dart';
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
import 'board_lane_drag.dart';
import 'board_lane_move.dart';

/// Lo que cuenta la segunda línea de cada fila del tablero.
enum BoardRowSubtitle {
  /// Persona, ocasión y quien regala (el tablero «Hoy»).
  all,

  /// Persona y quien regala (el tablero de una ocasión).
  perOccasion,

  /// Solo la ocasión («Hoy» con el filtro de una persona: ya se sabe para
  /// quién es).
  occasionOnly,
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
    this.personId,
    this.subtitle = BoardRowSubtitle.all,
    required this.onAdd,
  });

  /// La ocasión de la que se enseñan los regalos, o `null` para todos.
  final String? occasionId;

  /// La persona de la que se enseñan los regalos, o `null` para todas.
  final String? personId;

  /// Qué dice la segunda línea de las filas.
  final BoardRowSubtitle subtitle;

  /// Añade un regalo desde el «+» de la cabecera de un carril: el editor se
  /// abre con el estado de ese carril.
  final ValueChanged<BoardLane> onAdd;

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
  static const double gap = 12;

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
  final GlobalKey _viewKey = GlobalKey();
  late final ValueNotifier<Offset?> _pointer = ref.read(
    boardDragPointerProvider,
  );
  Timer? _autoScroll;
  late final ValueNotifier<BoardLane?> _reveal = ref.read(
    boardLaneRevealProvider,
  );

  // Si «Listo» va plegado en la última medida.
  bool _folded = false;

  @override
  void initState() {
    super.initState();
    _pointer.addListener(_onPointer);
    _reveal.addListener(_onReveal);
  }

  /// Un regalo pasa a «Listo» con el teclado: con el carril plegado, se abre su
  /// panel para que se vea y siga marcado.
  void _onReveal() {
    if (_reveal.value != BoardLane.ready) {
      return;
    }
    // Las ramas que no se ven (`Hoy` mientras se mira una ocasión) siguen
    // montadas con los relojes parados: no atienden la petición, que es del
    // tablero a la vista, y solo él la da por atendida.
    if (!TickerMode.valuesOf(context).enabled) {
      return;
    }
    _reveal.value = null;
    if (_folded && !_readyOpen) {
      setState(() => _readyOpen = true);
    }
  }

  @override
  void dispose() {
    _reveal.removeListener(_onReveal);
    _pointer.removeListener(_onPointer);
    _autoScroll?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// Mientras se arrastra una tarjeta, el tablero se desplaza solo si el
  /// puntero se acerca al borde de un lado y hay más carriles fuera.
  void _onPointer() {
    if (_pointer.value == null) {
      _autoScroll?.cancel();
      _autoScroll = null;
      return;
    }
    _autoScroll ??= Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _scrollTowardsPointer(),
    );
  }

  void _scrollTowardsPointer() {
    final pointer = _pointer.value;
    final box = _viewKey.currentContext?.findRenderObject();
    if (pointer == null ||
        !_scroll.hasClients ||
        box is! RenderBox ||
        !box.attached) {
      return;
    }
    const edge = 64.0;
    const fastest = 16.0;
    final x = box.globalToLocal(pointer).dx;
    final width = box.size.width;
    var step = 0.0;
    if (x < edge) {
      step = -fastest * (1 - x.clamp(0.0, edge) / edge);
    } else if (x > width - edge) {
      step = fastest * (1 - (width - x).clamp(0.0, edge) / edge);
    }
    if (step == 0) {
      return;
    }
    final position = _scroll.position;
    final to = (position.pixels + step).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (to != position.pixels) {
      _scroll.jumpTo(to);
    }
  }

  /// Suelta una tarjeta en «Listo» plegado.
  void _dropOnReady(BoardDragData data, Offset offset) {
    final size = data.size;
    moveGiftToLane(
      context,
      ref,
      data.gift,
      BoardLane.ready,
      from: size == null ? null : offset & size,
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(boardLanesProvider(widget.occasionId));
    final personId = widget.personId;
    // Con una persona elegida, la segunda línea dice solo la ocasión.
    final subtitle = personId != null && widget.subtitle == BoardRowSubtitle.all
        ? BoardRowSubtitle.occasionOnly
        : widget.subtitle;
    final groups = personId == null
        ? all
        : {
            for (final entry in all.entries)
              entry.key: [
                for (final gift in entry.value)
                  if (gift.recipientId == personId) gift,
              ],
          };
    return LayoutBuilder(
      builder: (context, box) {
        // Con la ventana más baja que los carriles, todo el tablero se
        // desplaza en vertical y su barra va a la derecha: se le deja sitio.
        final avail =
            box.maxWidth -
            (box.maxHeight < BoardLanesView.minHeight
                ? AppScrollbar.gutter
                : 0);
        final fold = BoardLanesLayout.of(avail).fold;
        // El orden de las flechas del teclado: carril a carril, sin los
        // regalos de un «Listo» que no se ve.
        _folded = fold;
        // (con el panel de «Listo» abierto, sí se ven y entran en el orden).
        ref.read(boardGiftCursorProvider).register([
          for (final lane in BoardLane.values)
            if (!(fold && lane == BoardLane.ready && !_readyOpen))
              for (final gift in groups[lane] ?? const <Gift>[]) gift.id,
        ]);
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: fold ? 1 : 0),
          // «Listo» se pliega con `snap`; con «Reducir movimiento», un fundido.
          duration: RegalosMotion.of(context)
              .duration(RegalosSprings.snapDuration),
          curve: RegalosMotion.of(context).curve(RegalosCurves.snap),
          builder: (context, rawPhase, _) {
            // `snap` pasa un 0,4 % de largo: el plegado no.
            final phase = rawPhase.clamp(0.0, 1.0);
            final layout = BoardLanesLayout.of(avail, foldPhase: phase);
            final height = math.max(BoardLanesView.minHeight, box.maxHeight);
            Widget lane(BoardLane l, double width) => SizedBox(
              width: width,
              child: BoardLaneColumn(
                lane: l,
                gifts: groups[l] ?? const <Gift>[],
                subtitle: subtitle,
                onAdd: () => widget.onAdd(l),
              ),
            );
            final ready = groups[BoardLane.ready] ?? const <Gift>[];
            final lanes = SizedBox(
              width: layout.total,
              // Con el tablero desplazándose, la barra va debajo de los
              // carriles: no los pisa.
              height: layout.scrolls ? height - AppScrollbar.gutter : height,
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
                            onDrop: _dropOnReady,
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
                                subtitle: subtitle,
                                onAdd: () => widget.onAdd(BoardLane.ready),
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
              content = SingleChildScrollView(
                padding: const EdgeInsets.only(right: AppScrollbar.gutter),
                child: content,
              );
            }
            return Stack(
              key: _viewKey,
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
                        subtitle: subtitle,
                        onAdd: () => widget.onAdd(BoardLane.ready),
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
    final motion = RegalosMotion.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: motion.duration(RegalosSprings.snapDuration),
      curve: motion.curve(RegalosCurves.snap),
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(
          // Con «Reducir movimiento» solo se funde, sin desplazarse.
          offset: Offset(motion.reduce ? 0 : 16 * (1 - v), 0),
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
    required this.onDrop,
  });

  final int count;
  final bool open;
  final VoidCallback onTap;

  /// Una tarjeta soltada encima (su posición al soltarla).
  final void Function(BoardDragData data, Offset offset) onDrop;

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
        child: DragTarget<BoardDragData>(
          onWillAcceptWithDetails: (d) =>
              d.data.gift.status != BoardLane.ready.status,
          onAcceptWithDetails: (d) => onDrop(d.data, d.offset),
          builder: (context, candidates, rejected) => AnimatedContainer(
            duration: RegalosMotion.of(context)
                .duration(RegalosSprings.snapDuration),
            curve: RegalosMotion.of(context).curve(RegalosCurves.snap),
            decoration: BoxDecoration(
              color: candidates.isNotEmpty ? t.soft : t.surface,
              borderRadius: RegalosShape.card,
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: RegalosShape.card,
              border: Border.all(
                color: candidates.isNotEmpty
                    ? t.ink
                    : t.ink.withValues(alpha: 0),
                width: 1.5,
              ),
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
            // Sitio debajo de los carriles para la barra: se dibuja encima
            // del borde y no ha de pisarlos.
            padding: const EdgeInsets.only(bottom: AppScrollbar.gutter),
            child: child,
          ),
        ),
        Positioned(
          top: 0,
          bottom: AppScrollbar.gutter,
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

/// Un carril: su cabecera fija (el nombre, cuántos y la suma) y sus filas, que
/// se desplazan dentro. El fondo llega hasta abajo.
///
/// Es también un destino: soltar aquí una tarjeta de otro carril le pone el
/// estado de este (`BoardLane.status`). Mientras se arrastra una tarjeta que
/// admite, el carril se tiñe con el tono suave del acento y se marca con un
/// filete de tinta.
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

  /// Si lleva el «+» de «Añadir regalo» en la cabecera.
  final VoidCallback? onAdd;

  /// Lo que ocupa la barra de desplazamiento, a la derecha: las filas miden
  /// el ancho del carril menos esto.
  static const double rowInset = AppScrollbar.gutter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final sum = centsOf(gifts);
    final motion = RegalosMotion.of(context);
    return DragTarget<BoardDragData>(
      onWillAcceptWithDetails: (d) => d.data.gift.status != lane.status,
      onAcceptWithDetails: (d) {
        final size = d.data.size;
        moveGiftToLane(
          context,
          ref,
          d.data.gift,
          lane,
          from: size == null ? null : d.offset & size,
        );
      },
      builder: (context, candidates, rejected) {
        final over = candidates.isNotEmpty;
        final title = boardLaneTitle(l10n, lane);
        return Semantics(
          container: true,
          label: title,
          child: AnimatedContainer(
            key: ValueKey<String>('board-lane-${lane.name}'),
            // Sin fondo gris: solo la cabecera con su filete. El carril se
            // tiñe con `snap` al llegarle una tarjeta.
            duration: motion.duration(RegalosSprings.snapDuration),
            curve: motion.curve(RegalosCurves.snap),
            decoration: BoxDecoration(
              color: over ? t.soft : t.soft.withValues(alpha: 0),
              borderRadius: RegalosShape.card,
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: RegalosShape.card,
              border: Border.all(
                color: over ? t.ink : t.ink.withValues(alpha: 0),
                width: 1.5,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // La cabecera: el nombre, cuántos, la suma a la derecha y el
                  // «+», sobre un filete de 1 px.
                  Padding(
                    padding: const EdgeInsets.only(right: AppScrollbar.gutter),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: t.separator)),
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 32),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(2, 0, 0, 4),
                          child: Row(
                            children: [
                              // El título y el recuento ocupan todo lo que
                              // dejan la suma y el «+»: el título solo se
                              // corta si de verdad no cabe.
                              Expanded(
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: t.styles.label,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${gifts.length}',
                                      style: t.styles.label.copyWith(
                                        fontWeight: FontWeight.w400,
                                        color: t.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (sum > 0)
                                Text(
                                  formatCents(sum, l10n.localeName),
                                  style: t.styles.caption.copyWith(
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              if (onAdd != null) ...[
                                const SizedBox(width: 4),
                                _LaneAddButton(
                                  label: l10n.boardLaneAdd(title),
                                  onTap: onAdd!,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: gifts.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(2, 10, 12, 12),
                            child: Text(
                              l10n.boardLaneEmpty,
                              style: t.styles.meta,
                            ),
                          )
                        : _LaneList(
                            gifts: gifts,
                            subtitle: subtitle,
                            // El carril sigue en pantalla cuando la fila ya se
                            // ha ido a otro: el aviso sale de aquí.
                            onMove: (gift, to) => moveGiftToLane(
                              context,
                              ref,
                              gift,
                              to,
                              reveal: true,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Las filas de un carril. Su barra de desplazamiento es la que Material
/// pone solo a cada lista vertical en escritorio y en la web, con el estilo de
/// la app (`AppScrollbar`): aquí no se añade otra, que saldrían dos. Se
/// dibuja encima del borde derecho, por eso el relleno de ese lado.
class _LaneList extends StatefulWidget {
  const _LaneList({
    required this.gifts,
    required this.subtitle,
    required this.onMove,
  });

  final List<Gift> gifts;
  final BoardRowSubtitle subtitle;
  final void Function(Gift gift, BoardLane to) onMove;

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
    return SingleChildScrollView(
      controller: _controller,
      padding: const EdgeInsets.only(bottom: 4, right: AppScrollbar.gutter),
      child: AnimatedRows(
        rows: [
          for (final gift in widget.gifts)
            AnimatedRowItem(
              id: gift.id,
              child: BoardGiftRow(
                gift: gift,
                subtitle: widget.subtitle,
                onMove: widget.onMove,
              ),
            ),
        ],
      ),
    );
  }
}

/// El «+» de la cabecera de un carril: añade un regalo. Lleva su ayuda con el
/// ratón y su etiqueta para el lector de pantalla («Añadir regalo en Por
/// decidir»).
class _LaneAddButton extends StatelessWidget {
  const _LaneAddButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final touchFirst = usesTouchTargets(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: PointerSurface(
          strength: 1.6,
          child: Material(
            key: const ValueKey<String>('board-lane-add'),
            color: Colors.transparent,
            borderRadius: RegalosShape.tiny,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              // El dibujo es de 28; con el dedo la zona de toque llega a 44 por
              // 44 (la cabecera crece lo justo), con el ratón no cambia nada.
              child: SizedBox.square(
                dimension: touchFirst ? StatusCheckbox.target : 28,
                child: Center(
                  child: StrokeIcon(
                    AppIcons.plus,
                    size: 16,
                    color: t.textSecondary,
                    strokeWidth: 1.9,
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

/// [line] con [hint] como ayuda y como lectura de pantalla, si lo hay.
Widget _withHint(String? hint, Widget line) => hint == null
    ? line
    : Semantics(
        label: hint,
        child: Tooltip(message: hint, excludeFromSemantics: true, child: line),
      );

/// La segunda línea de una fila: persona, ocasión y quien regala. Si entera no
/// cabe, quita quién regala; y si aun así no cabe, se corta con «…».
class _SecondLine extends StatelessWidget {
  const _SecondLine({
    required this.parts,
    required this.giverName,
    required this.style,
  });

  final List<String> parts;

  /// Quien regala, que se quita si no cabe; `null` si no se dice.
  final String? giverName;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final giver = giverName;
        if (giver == null) {
          return Text(
            parts.join(' · '),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
        }
        final full = [...parts, giver].join(' · ');
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

/// Con el teclado, la fila donde está el foco (el texto, la casilla de estado
/// o cualquier otro control de dentro) es la marcada: Ctrl o Cmd con ← y → mueven
/// esa y no otra. Con el ratón no marca nada (el clic ya lo hace).
class _MarkOnFocus extends ConsumerWidget {
  const _MarkOnFocus({
    required this.giftId,
    required this.enabled,
    required this.child,
  });

  final String giftId;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!enabled) {
      return child;
    }
    // El cursor se lee aquí: el aviso de foco puede llegar con la fila ya
    // desmontada y su `ref` ya no vale.
    final cursor = ref.read(boardGiftCursorProvider);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: (focused) {
        if (focused &&
            FocusManager.instance.highlightMode ==
                FocusHighlightMode.traditional) {
          cursor.set(giftId);
        }
      },
      child: child,
    );
  }
}

/// Una tarjeta de regalo del tablero, compacta: 52 de alto y dos líneas. A la
/// izquierda la casilla de estado (de 18, con su zona táctil); arriba el
/// título, cortado con «…», y el precio con cifras tabulares a la derecha;
/// debajo, en pequeño, persona y ocasión (solo la ocasión con el filtro de una
/// persona; en el tablero de una ocasión, persona y quien regala). Tocarla
/// abre el editor, que se queda a la derecha; la que se edita lleva el fondo
/// de la selección y el filete de tinta, y la marcada con el teclado, el borde
/// de control.
///
/// Con [onMove] la fila se puede pasar a otro carril: arrastrándola (con el
/// ratón, de inmediato; con el dedo, tras una pulsación larga), con
/// Ctrl o Cmd y las flechas ← y → (los atajos del tablero) o con las acciones
/// «Mover a…» que el lector de pantalla ofrece sobre ella.
class BoardGiftRow extends ConsumerWidget {
  /// Crea la fila.
  const BoardGiftRow({
    super.key,
    required this.gift,
    required this.subtitle,
    this.onMove,
  });

  /// El regalo.
  final Gift gift;

  /// Qué dice la segunda línea.
  final BoardRowSubtitle subtitle;

  /// Pasa el regalo al carril dado; sin él, la fila no se mueve de carril.
  final void Function(Gift gift, BoardLane to)? onMove;

  /// El alto de la tarjeta.
  static const double height = 52;

  /// El hueco entre dos tarjetas.
  static const double gap = 6;

  /// El lado de la casilla de estado.
  static const double glyph = 18;

  /// La clave con la que vuela la fila de un carril a otro.
  static Object flightKeyOf(String giftId) => boardGiftFlightKey(giftId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final view = ref.watch(familyViewProvider);
    final full = ref.watch(familyFullViewProvider);
    final person = full.recipientsById[gift.recipientId];
    final giver = view.resolveGiver(gift.giverId);
    final occasion = view.occasionsById[gift.occasionId];
    final labels = OccasionLabels(l10n, full.recipientsById);
    // Un regalo en secreto cambiado en la web que el móvil de su persona aún no
    // ha recogido (1.0.6): la marca va primero, para que no la corte el «…».
    final pending = ref
        .watch(webPendingSecretGiftIdsProvider)
        .contains(gift.id);
    final parts = <String>[
      if (pending) l10n.webSecretsPending,
      if (subtitle != BoardRowSubtitle.occasionOnly && person != null)
        person.name,
      if (subtitle != BoardRowSubtitle.perOccasion && occasion != null)
        labels.of(occasion),
    ];
    final giverName = subtitle != BoardRowSubtitle.perOccasion
        ? null
        : giverNameFor(l10n, giver);
    final cents = gift.actualCents ?? gift.plannedCents;
    final panel = ref.read(giftEditorPanelProvider);
    return LayoutBuilder(
      builder: (context, box) => _build(
        context,
        ref,
        panel: panel,
        width: box.maxWidth,
        t: t,
        l10n: l10n,
        parts: parts,
        giverName: giverName,
        cents: cents,
        pendingHint: pending ? l10n.webSecretsPendingLong : null,
      ),
    );
  }

  Widget _build(
    BuildContext context,
    WidgetRef ref, {
    required GiftEditorPanelController panel,
    required double width,
    required String? giverName,
    required RegalosTokens t,
    required AppLocalizations l10n,
    required List<String> parts,
    required int? cents,
    required String? pendingHint,
  }) {
    // El puntero compartido se toma ya: el arrastre puede seguir cuando la fila
    // se ha ido (el regalo se borra en otro móvil) y su `ref` ya no vale.
    final pointer = ref.read(boardDragPointerProvider);
    final lane = BoardLane.of(gift.status);
    final move = onMove;
    final movable = move != null && lane != null;
    // «Mover a Por comprar»… para el lector de pantalla: un carril cada vez,
    // salvo en el que ya está.
    final moveActions = <CustomSemanticsAction, VoidCallback>{
      if (movable)
        for (final to in BoardLane.values)
          if (to != lane)
            CustomSemanticsAction(
              label: l10n.boardMoveTo(boardLaneTitle(l10n, to)),
            ): () =>
                move(gift, to),
    };
    final titleStyle = t.styles.cardTitle;
    final priceStyle = t.styles.price;
    final lineStyle = t.styles.caption.copyWith(fontWeight: FontWeight.w400);
    return BoardCursorTarget(
      giftId: gift.id,
      builder: (context, marked) => ListenableBuilder(
        listenable: panel,
        builder: (context, _) {
          final editing = panel.request?.gift?.id == gift.id;
          // La tarjeta: la del carril o, con [floating], la que sigue al
          // puntero al arrastrarla (sin toques ni vuelo).
          Widget card({required bool floating}) => _MarkOnFocus(
            giftId: gift.id,
            enabled: !floating,
            child: Padding(
              padding: floating
                  ? EdgeInsets.zero
                  : const EdgeInsets.only(top: gap),
              child: Builder(
                builder: (rowContext) => ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: height),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: editing && !floating ? t.selection : t.cardFill,
                      borderRadius: RegalosShape.button,
                      border: Border.all(
                        color: floating
                            ? t.controlBorder
                            : (editing
                                  ? t.ink
                                  : (marked ? t.controlBorder : t.separator)),
                        width: editing && !floating ? 1.5 : 1,
                      ),
                    ),
                    child: PointerSurface(
                      strength: 2.2,
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: RegalosShape.button,
                        clipBehavior: Clip.antiAlias,
                        child: Row(
                          children: [
                            // La casilla con su zona táctil de 44 por 44 entera
                            // dentro de la fila: ahí cambia el estado; a su
                            // derecha, el texto abre el editor.
                            SizedBox.square(
                              dimension: StatusCheckbox.target,
                              child: StatusCheckbox(
                                status: gift.status.visualStatus,
                                itemName: gift.title,
                                glyphSize: glyph,
                                onTap: floating
                                    ? () {}
                                    : () {
                                        final rect = globalRectOf(rowContext);
                                        if (rect != null) {
                                          ref
                                              .read(flightRegistryProvider)
                                              .depart(
                                                flightKeyOf(gift.id),
                                                rect,
                                              );
                                        }
                                        advanceGiftStatus(context, ref, gift);
                                      },
                                onLongPress: floating
                                    ? null
                                    : () => showGiftStatusPicker(
                                        context,
                                        ref,
                                        gift,
                                      ),
                              ),
                            ),
                            Expanded(
                              child: Semantics(
                                customSemanticsActions: floating
                                    ? null
                                    : moveActions,
                                child: InkWell(
                                  onTap: floating
                                      ? null
                                      : () {
                                          ref
                                              .read(boardGiftCursorProvider)
                                              .set(gift.id);
                                          openGiftEditor(context, gift: gift);
                                        },
                                  child: Padding(
                                    // 5 + 1 del borde arriba y abajo: el
                                    // contenido (46) y el hueco de encima (6)
                                    // caben en los 52 del vuelo.
                                    padding: const EdgeInsets.fromLTRB(
                                      0,
                                      5,
                                      10,
                                      5,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                gift.title,
                                                maxLines: 1,
                                                softWrap: false,
                                                overflow: TextOverflow.ellipsis,
                                                style: titleStyle,
                                              ),
                                            ),
                                            if (cents != null) ...[
                                              const SizedBox(width: 8),
                                              Text(
                                                formatCents(
                                                  cents,
                                                  l10n.localeName,
                                                ),
                                                maxLines: 1,
                                                style: priceStyle,
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        // «Pendiente» es corto: el texto entero, en
                                        // la ayuda y para el lector de pantalla.
                                        _withHint(
                                          pendingHint,
                                          _SecondLine(
                                            parts: parts,
                                            giverName: giverName,
                                            style: lineStyle,
                                          ),
                                        ),
                                      ],
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
                ),
              ),
            ),
          );
          return FlightTarget(
            flightKey: flightKeyOf(gift.id),
            child: BoardRowAnchor(
              giftId: gift.id,
              child: movable
                  ? BoardCardDraggable(
                      gift: gift,
                      width: width,
                      card: (floating) => card(floating: floating),
                      onPointer: (p) => pointer.value = p,
                    )
                  : card(floating: false),
            ),
          );
        },
      ),
    );
  }
}
