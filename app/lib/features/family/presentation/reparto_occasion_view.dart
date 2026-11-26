import '../../web_device/application/web_app_provider.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/dates.dart';
import '../../../core/format/money.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/layout/large_text.dart';
import '../../../core/layout/pane_scope.dart';
import '../../../core/layout/window_class.dart';
import '../../../core/sync/model.dart';
import '../../../core/sync/protected_doc.dart' show ProtectedPersonException;
import '../../../core/theme/occasion_theme.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/dashed_box.dart';
import '../../../core/widgets/fit_text.dart';
import '../../../core/widgets/gift_status_l10n.dart';
import '../../../core/widgets/gift_status_map.dart';
import '../../../core/widgets/occasion_icons.dart';
import '../../../core/widgets/regalos_snack_bar.dart';
import '../../../core/widgets/settings_icons.dart';
import '../../../core/widgets/status_checkbox.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../gifts/presentation/gift_editor_screen.dart';
import '../application/family_controller.dart';
import '../application/family_providers.dart';
import '../application/wish_service.dart';
import '../../gifts/presentation/wish_editor.dart' show wishProblemText;
import '../application/self_recipient_provider.dart';
import '../domain/next_occasion.dart';
import 'family_texts.dart';
import 'giver_person_flow.dart';
import 'giver_picker.dart';
import 'reparto_flight.dart';
import 'reparto_fold.dart';
import 'reparto_grid.dart' show RepartoAvatar, RepartoBoardMode, RepartoLayout;
import 'reparto_outside.dart';
import 'secret_blocks.dart';
import 'self_tag.dart';

/// Clave de la fila de pestañas de ocasión de la vista por ocasión (para las
/// pruebas).
const Key kRepartoOccasionTabsKey = ValueKey<String>('repartoOccasionTabs');

/// El ancla de un regalo en la vista por ocasión (su fila).
String repartoGiftAnchor(String giftId) => 'gift:$giftId';

/// La vista C de Reparto, por ocasión: una pestaña por ocasión con su cuenta
/// atrás, la franja con la fecha, cuántos paquetes abre cada persona y una
/// tarjeta por persona con sus regalos. Cada regalo lleva un chip con quién lo
/// regala que se despliega en línea para cambiarlo.
///
/// En una ventana ancha (tablet) el contenido no se estira: en «medio» es
/// una columna de 640 y en «expandido», dos columnas de tarjetas de 560 como
/// máximo, con la franja y las casillas encima, a lo ancho de las dos. Las
/// casillas de «cuántos paquetes» miden entonces 140, las que quepan por fila.
class RepartoOccasionView extends ConsumerStatefulWidget {
  /// Crea la vista; [occasions] ya vienen por orden de próxima fecha.
  const RepartoOccasionView({
    super.key,
    required this.occasions,
    required this.selectedId,
    required this.onSelect,
    required this.stage,
    required this.onOpenPerson,
  });

  /// Las ocasiones, una pestaña cada una.
  final List<Occasion> occasions;

  /// La ocasión que se ve.
  final String selectedId;

  /// Se llama al tocar otra pestaña.
  final ValueChanged<String> onSelect;

  /// El escenario del vuelo entre vistas.
  final RepartoStage stage;

  /// Al tocar el nombre de una persona se abre su ficha, desde [Rect].
  final void Function(Recipient recipient, Rect from) onOpenPerson;

  /// El ancho de la columna de contenido de la vista en esta ventana: sin tope
  /// en el móvil, 640 en «medio» y, en dos paneles, lo que ocupan sus
  /// columnas de tarjetas (1400 como mucho). La cabecera de Reparto se alinea
  /// con él en escritorio.
  static double columnMaxOf(BuildContext context) {
    // En el tablero de la web de escritorio llena el ancho, desde el margen.
    if (RepartoBoardMode.of(context)) {
      return double.infinity;
    }
    final window = WindowClass.of(context);
    final columns = _columnsFor(window, PaneScope.widthOf(context));
    return !window.usesRail
        ? double.infinity
        : (columns == 1
              ? RegalosLayout.listColumn
              : math.min(
                  columns * _cardMaxWidth + _columnGap * (columns - 1) + 32,
                  RepartoLayout.desktopMaxWidth,
                ));
  }

  /// Cuántas columnas de tarjetas caben en un panel de [paneWidth].
  static int _columnsFor(WindowClass window, double paneWidth) =>
      window != WindowClass.expanded
      ? 1
      : (paneWidth >= _threeColumnsFrom
            ? 3
            : (paneWidth >= _twoColumnsFrom ? 2 : 1));

  /// Hueco entre las dos columnas de tarjetas.
  static const double _columnGap = 12;

  /// Ancho mínimo del panel para dos columnas de tarjetas…
  static const double _twoColumnsFrom = 1100;

  /// …y para tres.
  static const double _threeColumnsFrom = 1700;

  /// Ancho máximo de una tarjeta de persona en una ventana ancha.
  static const double _cardMaxWidth = 560;

  @override
  ConsumerState<RepartoOccasionView> createState() =>
      _RepartoOccasionViewState();
}

class _RepartoOccasionViewState extends ConsumerState<RepartoOccasionView>
    with SingleTickerProviderStateMixin {
  /// El regalo con la fila de chips desplegada.
  String? _openId;

  /// La elección hecha y aún sin guardar (el chip ya cambió de forma).
  ({String giftId, String? giverId})? _pending;
  Timer? _foldTimer;
  Timer? _applyTimer;

  final ScrollController _scroll = ScrollController();

  /// Las tarjetas que se ven, con las que se van plegándose (como las filas
  /// de la rejilla). Se reinicia al cambiar de pestaña: otra ocasión no pliega
  /// ni despliega nada, desliza todo el contenido.
  FoldTracker<_CardData>? _cards;
  String? _cardsFor;

  static const double _columnGap = RepartoOccasionView._columnGap;

  /// Ancho de una casilla de «cuántos paquetes» en una ventana ancha.
  static const double _packetWidth = 140;

  /// En dos columnas, la de cada tarjeta (por persona). Cada una conserva la
  /// suya mientras se ve la ocasión: si otra se pliega, las demás suben, pero
  /// ninguna salta de columna.
  final Map<String, int> _cardColumn = <String, int>{};

  /// Con cuántas columnas se repartieron las tarjetas por última vez.
  int _columnsFor = 1;

  /// Da columna a las tarjetas que aún no la tienen: la que tenga menos (la
  /// de más a la izquierda si empatan), así que de entrada se alternan. Si
  /// cambia el número de columnas (la ventana cruza un corte), se reparten de
  /// nuevo.
  void _assignColumns(List<FoldEntry<_CardData>> cards, int columns) {
    if (columns != _columnsFor) {
      _columnsFor = columns;
      _cardColumn.clear();
    }
    final ids = [for (final c in cards) c.item.recipient.id];
    _cardColumn.removeWhere((id, _) => !ids.contains(id));
    for (final id in ids) {
      if (_cardColumn.containsKey(id)) {
        continue;
      }
      final counts = List<int>.filled(columns, 0);
      for (final column in _cardColumn.values) {
        counts[math.min(column, columns - 1)]++;
      }
      var best = 0;
      for (var i = 1; i < columns; i++) {
        if (counts[i] < counts[best]) {
          best = i;
        }
      }
      _cardColumn[id] = best;
    }
  }

  /// Al cambiar de pestaña, el contenido entra deslizándose de lado con el
  /// muelle `snap` (de −1 a 0, hacia el lado de la pestaña nueva).
  late final AnimationController _slide = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  double _slideFrom = 0;

  @override
  void didUpdateWidget(RepartoOccasionView old) {
    super.didUpdateWidget(old);
    if (old.selectedId == widget.selectedId) {
      return;
    }
    flush();
    _openId = null;
    final from = old.occasions.indexWhere((o) => o.id == old.selectedId);
    final to = widget.occasions.indexWhere((o) => o.id == widget.selectedId);
    if (_scroll.hasClients) {
      _scroll.jumpTo(0);
    }
    if (RegalosMotion.of(context).reduce) {
      _slideFrom = 0;
      _slide
        ..stop()
        ..value = 0;
      _slide.animateTo(1, duration: RegalosMotion.fade, curve: Curves.linear);
      return;
    }
    _slideFrom = to >= from ? 40 : -40;
    _slide
      ..stop()
      ..value = 0;
    _slide.animateWith(SpringSimulation(RegalosSprings.snap, 0, 1, 0));
  }

  @override
  void dispose() {
    _foldTimer?.cancel();
    _applyTimer?.cancel();
    _scroll.dispose();
    _slide.dispose();
    super.dispose();
  }

  void _toggle(String giftId) {
    flush();
    setState(() => _openId = _openId == giftId ? null : giftId);
  }

  void _pick(Gift gift, String? giverId) {
    if (!ref.read(giftGiverEditableProvider(gift.id))) return;
    final view = ref.read(familyViewProvider);
    if (giverId == view.resolveGiver(gift.giverId)?.id &&
        view.giversByOriginalId[gift.giverId]?.archived != true) {
      setState(() => _openId = null);
      return;
    }
    flush();
    final motion = RegalosMotion.of(context);
    setState(() => _pending = (giftId: gift.id, giverId: giverId));
    // El chip cambia de forma (375 ms); luego la fila se pliega (180 ms) y
    // entonces se guarda.
    _foldTimer = Timer(
      motion.reduce ? Duration.zero : RegalosSprings.snapDuration,
      () {
        if (!mounted) {
          return;
        }
        setState(() => _openId = null);
        _applyTimer = Timer(
          motion.reduce ? Duration.zero : RegalosCurves.foldDuration,
          _apply,
        );
      },
    );
  }

  /// Asigna una persona de la familia como quién regala, al momento. En un
  /// regalo secreto pasa antes por el paso explícito.
  Future<void> _pickPerson(Gift gift, GiverPersonCandidate candidate) async {
    flush();
    WishResult? planFailure;
    final plan = ref.read(wishPlanOfGiftProvider(gift.id));
    final result = await assignGiftToPerson(
      context,
      ref,
      gift: gift,
      candidate: candidate,
      plan: plan,
      onPlanFailure: (r) => planFailure = r,
    );
    if (!mounted || result == null) {
      return;
    }
    final saved = result == GiftWriteResult.saved;
    setState(() => _openId = null);
    if (!saved) {
      showRegalosSnackBar(
        context,
        SnackBar(
          content: Text(
            planFailure != null
                ? wishProblemText(
                    AppLocalizations.of(context),
                    planFailure!,
                    name:
                        ref
                            .read(familyFullViewProvider)
                            .allRecipientsById[plan?.recipientId]
                            ?.name ??
                        '',
                    web: ref.read(webAppProvider),
                  )
                : giftWriteResultText(
                    AppLocalizations.of(context),
                    result,
                    web: ref.read(webAppProvider),
                  ),
          ),
        ),
      );
    }
  }

  /// Termina ya lo que esté a medias (un segundo toque, otra pestaña).
  void flush() {
    if (_pending == null) {
      return;
    }
    _foldTimer?.cancel();
    _applyTimer?.cancel();
    if (_openId != null && mounted) {
      setState(() => _openId = null);
    }
    _apply();
  }

  Future<void> _apply() async {
    final pending = _pending;
    if (pending == null) {
      return;
    }
    _pending = null;
    WishResult? planFailure;
    final result =
        await assignGiftGiver(
          controller: ref.read(familyControllerProvider.notifier),
          service: ref.read(wishServiceProvider),
          giftId: pending.giftId,
          giverId: pending.giverId,
          // Un deseo cogido cambia quién regala en su plan (ADR 0010).
          plan: ref.read(wishPlanOfGiftProvider(pending.giftId)),
          onPlanFailure: (r) => planFailure = r,
        ).onError<ProtectedPersonException>(
          (error, _) => error.savedLocally
              ? GiftWriteResult.saved
              : GiftWriteResult.giftUnavailable,
        );
    if (mounted) {
      setState(() {});
      if (result != GiftWriteResult.saved) {
        showRegalosSnackBar(
          context,
          SnackBar(
            content: Text(
              planFailure != null
                  ? wishProblemText(
                      AppLocalizations.of(context),
                      planFailure!,
                      name:
                          ref
                              .read(familyFullViewProvider)
                              .allRecipientsById[ref
                                  .read(wishPlanOfGiftProvider(pending.giftId))
                                  ?.recipientId]
                              ?.name ??
                          '',
                      web: ref.read(webAppProvider),
                    )
                  : giftWriteResultText(
                      AppLocalizations.of(context),
                      result,
                      web: ref.read(webAppProvider),
                    ),
            ),
          ),
        );
      }
    }
  }

  /// La tarjeta de [id] ya se ha plegado del todo.
  void _cardGone(String id) {
    if (!mounted) {
      return;
    }
    setState(() => _cards?.gone(id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final full = ref.watch(familyViewProvider);
    final occasions = widget.occasions;
    if (occasions.isEmpty) {
      return RepartoBlock(
        index: 0,
        child: _EmptyBlock(
          icon: AppIcons.occasions,
          title: l10n.emptyOccasionsTitle,
          message: l10n.emptyOccasionsMessage,
        ),
      );
    }
    final occasion =
        occasions.where((o) => o.id == widget.selectedId).firstOrNull ??
        occasions.first;
    final theme = OccasionTheme.forOccasion(occasion);
    // Solo lo que cuenta en Reparto: sin las personas que no salen y sin los
    // regalos de quien se salta esta ocasión.
    final view = ref.watch(repartoFamilyViewProvider(occasion.id));
    // «Yo»: la persona dueña de este móvil lleva su etiqueta en la tarjeta.
    final selfId = ref.watch(selfRecipientIdProvider);
    final skipping = [
      for (final r in view.recipients)
        if (r.skipsOccasion(occasion.id)) r,
    ];
    final people = [
      for (final r in view.recipients)
        if (!r.skipsOccasion(occasion.id)) r,
    ];
    // Quien tiene regalos en secreto que este móvil no ve no lleva tarjeta ni
    // cifras: sale con el bloque fijo.
    final locked = ref.watch(lockedPeopleProvider);
    final openPeople = [
      for (final r in people)
        if (!locked.contains(r.id)) r,
    ];
    // En el cumpleaños de otra persona no hay bloque para quien no recibe.
    final lockedPeople = lockedPeopleFor(occasion, people, locked);
    final gifts = [
      for (final g in view.gifts)
        if (g.occasionId == occasion.id) g,
    ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final byRecipient = <String, List<Gift>>{};
    for (final g in gifts) {
      byRecipient.putIfAbsent(g.recipientId, () => <Gift>[]).add(g);
    }
    // Las tarjetas: quien sale del reparto (o vuelve) las pliega (o las
    // despliega) como a las filas de la rejilla. Sin regalos no hay tarjetas.
    if (gifts.isEmpty) {
      _cards = null;
      _cardsFor = null;
      _cardColumn.clear();
    } else {
      final data = [
        for (final r in openPeople)
          _CardData(r, byRecipient[r.id] ?? const <Gift>[]),
      ];
      final tracker = _cards;
      if (tracker == null || _cardsFor != occasion.id) {
        _cards = FoldTracker<_CardData>((d) => d.recipient.id, data);
        _cardsFor = occasion.id;
        _cardColumn.clear();
      } else {
        tracker.update(data);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _cards?.settle());
    }
    final cards = _cards?.entries ?? const <FoldEntry<_CardData>>[];
    // La clase es la de la ventana; el ancho, el del panel. En el móvil
    // (también tumbado) no hay tope: todo mide lo de siempre. En «expandido»
    // (dos paneles) las tarjetas van en columnas de 360 a 560: dos desde 1100
    // de panel, tres desde 1700, con 1400 de ancho como máximo en total.
    final window = WindowClass.of(context);
    final wide = window.usesRail;
    final paneWidth = PaneScope.widthOf(context);
    final columns = RepartoOccasionView._columnsFor(window, paneWidth);
    _assignColumns(cards, columns);
    final columnMax = RepartoOccasionView.columnMaxOf(context);
    final gutter = ContentWidth.gutter(paneWidth, columnMax);
    final title = occasionTitle(
      l10n,
      occasion,
      personName: full.recipientsById[occasion.recipientId]?.name,
    );
    return Column(
      children: [
        RepartoBlock(
          index: 0,
          // En una ventana ancha las pestañas ocupan la columna entera:
          // empiezan donde empieza el contenido y la línea llega de lado a
          // lado, quepan o no. En el móvil, como siempre: lo que midan.
          child: ContentWidth(
            maxWidth: columnMax,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: wide ? double.infinity : 0),
              child: _Tabs(
                occasions: occasions,
                labels: [
                  for (final o in occasions)
                    occasionTitle(
                      l10n,
                      o,
                      personName: full.recipientsById[o.recipientId]?.name,
                    ),
                ],
                selectedId: occasion.id,
                onSelect: widget.onSelect,
              ),
            ),
          ),
        ),
        Expanded(
          child: AnimatedBuilder(
            animation: _slide,
            builder: (context, child) {
              final v = _slide.value;
              final reduce = RegalosMotion.of(context).reduce;
              if (!_slide.isAnimating) {
                return child!;
              }
              if (reduce) {
                return Opacity(opacity: v.clamp(0.0, 1.0), child: child);
              }
              return Opacity(
                opacity: v.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(_slideFrom * (1 - v), 0),
                  child: child,
                ),
              );
            },
            child: ListView(
              controller: _scroll,
              // El margen va en la lista (y no alrededor) para que se siga
              // desplazando al arrastrar por los lados.
              padding: EdgeInsets.only(left: gutter, right: gutter, bottom: 24),
              children: [
                RepartoBlock(
                  index: 1,
                  child: _Band(occasion: occasion, theme: theme, gifts: gifts),
                ),
                if (gifts.isEmpty)
                  RepartoBlock(
                    index: 2,
                    child: _EmptyBlock(
                      icon: null,
                      occasion: occasion,
                      theme: theme,
                      title: l10n.repartoOccasionEmptyTitle(title),
                      message: l10n.repartoOccasionEmptyMessage,
                      actionLabel: l10n.repartoSheetAddGift,
                      onAction: () =>
                          openGiftEditor(context, occasionId: occasion.id),
                    ),
                  )
                else ...[
                  RepartoBlock(
                    index: 2,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                      child: Text(
                        l10n.repartoOccasionPackets,
                        style: RegalosTokens.of(context).styles.caption
                            .copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ),
                  RepartoBlock(
                    index: 3,
                    child: _Packets(
                      recipients: people,
                      locked: locked,
                      counts: {
                        for (final e in byRecipient.entries)
                          e.key: e.value.length,
                      },
                      itemWidth: wide ? _packetWidth : null,
                    ),
                  ),
                  // Las tarjetas, en una columna o en dos: el mismo árbol en
                  // los dos casos, así que girar no las vuelve a montar.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _CardColumns(
                      columns: columns,
                      gap: _columnGap,
                      assignment: [
                        for (final c in cards)
                          _cardColumn[c.item.recipient.id] ?? 0,
                      ],
                      children: [
                        for (var i = 0; i < cards.length; i++)
                          FoldTransition(
                            key: ValueKey<String>(
                              'fold:${cards[i].item.recipient.id}',
                            ),
                            entering: cards[i].entering,
                            leaving: cards[i].leaving,
                            onGone: () => _cardGone(cards[i].item.recipient.id),
                            child: _RecipientCard(
                              index: 4 + i,
                              recipient: cards[i].item.recipient,
                              isSelf: cards[i].item.recipient.id == selfId,
                              occasion: occasion,
                              occasionTitle: title,
                              gifts: cards[i].item.gifts,
                              view: view,
                              stage: widget.stage,
                              openId: _openId,
                              pending: _pending,
                              onToggle: _toggle,
                              onPick: _pick,
                              onPickPerson: _pickPerson,
                              onOpenPerson: widget.onOpenPerson,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                // Regalos en secreto: el bloque fijo, sin cifras, haya o no
                // regalos a la vista.
                if (lockedPeople.isNotEmpty)
                  RepartoBlock(
                    index: 4 + openPeople.length,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: SecretBlockList(people: lockedPeople),
                    ),
                  ),
                // Quien no recibe nada en esta ocasión no tiene tarjeta: sale
                // aparte, sin hueco que rellenar.
                if (skipping.isNotEmpty)
                  RepartoBlock(
                    index: 5 + people.length,
                    child: _NotGivingBlock(
                      title: l10n.repartoOccasionNotGiving(title),
                      people: skipping,
                      onOpenPerson: widget.onOpenPerson,
                    ),
                  ),
                // «Fuera del reparto · N», plegado al final como en la
                // rejilla, con «Volver a incluir». Sin nadie fuera no hay
                // bloque: cuando vuelve a haber alguien, sale plegado (como
                // hasta ahora, cuando la tarjeta que volvía lo desplazaba en
                // la lista y perdía su estado).
                if (full.outsideReparto.isNotEmpty)
                  RepartoBlock(
                    index: 6 + people.length,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: OutsideBlock(
                        outside: full.outsideReparto,
                        onOpenPerson: widget.onOpenPerson,
                        onInclude: (r) => ref
                            .read(familyControllerProvider.notifier)
                            .setRecipientInReparto(r.id, true),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Las pestañas de ocasión, con un subrayado del color de la ocasión que se
/// desliza con el muelle `snap`. Se desplazan en horizontal si no caben.
class _Tabs extends StatefulWidget {
  const _Tabs({
    required this.occasions,
    required this.labels,
    required this.selectedId,
    required this.onSelect,
  });

  final List<Occasion> occasions;
  final List<String> labels;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> {
  static const double _gap = 22;
  static const double _height = 56;
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(_Tabs old) {
    super.didUpdateWidget(old);
    if (old.selectedId != widget.selectedId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Lleva la pestaña elegida al centro si no cabe entera.
  void _reveal() {
    if (!mounted || !_scroll.hasClients) {
      return;
    }
    final widths = _widths(context);
    final i = widget.occasions.indexWhere((o) => o.id == widget.selectedId);
    if (i < 0) {
      return;
    }
    final left = _left(widths, i);
    final viewport = _scroll.position.viewportDimension;
    final target = (left + widths[i] / 2 - viewport / 2).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    final motion = RegalosMotion.of(context);
    if (motion.reduce) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(
        target,
        duration: RegalosSprings.snapDuration,
        curve: RegalosCurves.snap,
      );
    }
  }

  /// El estilo de una pestaña, con la familia del tema (el
  /// `AnimatedDefaultTextStyle` no hereda la del `DefaultTextStyle` de arriba).
  TextStyle _style(BuildContext context) =>
      DefaultTextStyle.of(context).style.merge(
        RegalosTokens.of(context).styles.label
            .copyWith(fontSize: 15, fontWeight: FontWeight.w600, height: 1.2),
      );

  /// El ancho de cada texto.
  List<double> _widths(BuildContext context) {
    final style = _style(context);
    final scaler = MediaQuery.textScalerOf(context);
    return [
      for (final label in widget.labels)
        (TextPainter(
          text: TextSpan(text: label, style: style),
          textDirection: Directionality.of(context),
          textScaler: scaler,
          maxLines: 1,
        )..layout()).width,
    ];
  }

  /// Dónde empieza el texto de la pestaña [i] (el margen es [_gap] / 2 más 5).
  double _left(List<double> widths, int i) {
    var x = 16 - _gap / 2;
    for (var j = 0; j < i; j++) {
      x += widths[j] + _gap;
    }
    return x + _gap / 2;
  }

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final motion = RegalosMotion.of(context);
    final widths = _widths(context);
    final style = _style(context);
    final selected = widget.occasions.indexWhere(
      (o) => o.id == widget.selectedId,
    );
    final theme = OccasionTheme.forOccasion(
      widget.occasions[selected < 0 ? 0 : selected],
    );
    final underline = theme.mark(dark: t.isDark);
    final total =
        16 - _gap / 2 + widths.fold<double>(0, (a, w) => a + w + _gap);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: AppLocalizations.of(context).navOccasions,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.separator)),
        ),
        child: SizedBox(
          height: _height,
          child: SingleChildScrollView(
            key: kRepartoOccasionTabsKey,
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: total + 16 - _gap / 2,
              height: _height,
              child: Stack(
                children: [
                  Row(
                    children: [
                      SizedBox(width: 16 - _gap / 2),
                      for (var i = 0; i < widget.occasions.length; i++)
                        _Tab(
                          label: widget.labels[i],
                          width: widths[i] + _gap,
                          selected: i == selected,
                          style: style.copyWith(
                            color: i == selected ? t.text : t.textSecondary,
                          ),
                          onTap: () => widget.onSelect(widget.occasions[i].id),
                        ),
                    ],
                  ),
                  AnimatedPositioned(
                    key: const ValueKey<String>('repartoTabUnderline'),
                    duration: motion.reduce
                        ? Duration.zero
                        : RegalosSprings.snapDuration,
                    curve: RegalosCurves.snap,
                    left: selected < 0 ? 0 : _left(widths, selected),
                    bottom: 0,
                    width: selected < 0 ? 0 : widths[selected],
                    height: 3,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: underline,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(2),
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
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.width,
    required this.selected,
    required this.style,
    required this.onTap,
  });

  final String label;
  final double width;
  final bool selected;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    selected: selected,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: width,
        height: _TabsState._height,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: RegalosMotion.fade,
            style: style,
            child: Text(label, maxLines: 1, softWrap: false),
          ),
        ),
      ),
    ),
  );
}

/// La franja de la ocasión: su color, la fecha, los días que faltan y cuántos
/// regalos hay y cuántos faltan por comprar.
class _Band extends StatelessWidget {
  const _Band({
    required this.occasion,
    required this.theme,
    required this.gifts,
  });

  final Occasion occasion;
  final OccasionTheme theme;
  final List<Gift> gifts;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final now = clock.now();
    final day = occasionDayMonth(occasion, now);
    final next = nextDateOf(occasion, now);
    final days = next
        ?.difference(DateTime(now.year, now.month, now.day))
        .inDays;
    final colors = _bandColors(t, theme);
    final toBuy = gifts.where((g) => !g.status.isBoughtOrLater).length;
    final dateText = longDayMonth(day.month, day.day, l10n.localeName);
    final daysText = days == null ? null : l10n.occasionDaysLeft(days);
    final base = t.styles.body;
    // Con letra grande no queda ancho para la fecha y las cuentas lado a
    // lado: las cuentas bajan debajo de la fecha, sin partir ninguna palabra.
    final large = isLargeText(context);
    final counts = gifts.isEmpty
        ? null
        : Column(
            crossAxisAlignment: large
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.end,
            children: [
              FitText(
                l10n.giftCount(gifts.length),
                style: base.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colors.ink,
                ),
              ),
              FitText(
                l10n.repartoOccasionToBuy(toBuy),
                style: base.copyWith(
                  fontSize: 13,
                  color: colors.ink.withValues(alpha: 0.85),
                ),
              ),
            ],
          );
    final top = Row(
      children: [
        OccasionKindIcon(
          occasion.kind,
          customIcon: occasion.icon,
          size: 26,
          color: colors.ink,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FitText(
                dateText,
                style: base.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colors.ink,
                ),
              ),
              if (daysText != null)
                FitText(
                  daysText,
                  style: base.copyWith(
                    fontSize: 13,
                    color: colors.ink.withValues(alpha: 0.85),
                  ),
                ),
            ],
          ),
        ),
        if (counts != null && !large) counts,
      ],
    );
    return Semantics(
      container: true,
      label: [
        dateText,
        ?daysText,
        l10n.giftCount(gifts.length),
        if (gifts.isNotEmpty) l10n.repartoOccasionToBuy(toBuy),
      ].join(', '),
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 14, 16, 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colors.fill,
          borderRadius: RegalosShape.card,
        ),
        child: counts != null && large
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  top,
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 38),
                    child: counts,
                  ),
                ],
              )
            : top,
      ),
    );
  }
}

({Color fill, Color ink}) _bandColors(RegalosTokens t, OccasionTheme theme) =>
    t.isDark
    ? (fill: theme.palette.tintD, ink: theme.palette.tintaD)
    : (fill: theme.palette.pastel, ink: theme.palette.tinta);

/// «Cuántos paquetes abre cada uno»: una casilla por persona, de tres en tres.
/// Con [itemWidth] (una ventana ancha) las casillas miden eso y van las que
/// quepan por fila.
class _Packets extends StatelessWidget {
  const _Packets({
    required this.recipients,
    required this.counts,
    this.locked = const <String>{},
    this.itemWidth,
  });

  final List<Recipient> recipients;
  final Map<String, int> counts;

  /// Las personas con regalos en secreto que este móvil no ve: en su casilla
  /// no hay cifra, solo un candado.
  final Set<String> locked;

  /// Ancho fijo de cada casilla; `null`: un tercio del ancho.
  final double? itemWidth;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 8.0;
          // Con letra grande, de dos en dos: en un tercio del ancho el nombre
          // se quedaba en dos letras y «…».
          final large = isLargeText(context);
          final perRow = large ? 2 : 3;
          final width =
              itemWidth ?? (constraints.maxWidth - (perRow - 1) * gap) / perRow;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final r in recipients)
                Semantics(
                  container: true,
                  label: locked.contains(r.id)
                      ? '${r.name}: ${l10n.secretBlockTitle(r.name)}'
                      : '${r.name}: ${l10n.giftCount(counts[r.id] ?? 0)}',
                  excludeSemantics: true,
                  child: SizedBox(
                    width: width,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: RegalosShape.card,
                        border: Border.all(color: t.separator),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            RepartoAvatar(
                              name: r.name,
                              colorIndex: r.colorIndex,
                              size: 26,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (locked.contains(r.id))
                                    SizedBox(
                                      height: 23,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: StrokeIcon(
                                          SettingsIcons.lock,
                                          size: 18,
                                          color: t.textSecondary,
                                          strokeWidth: 1.9,
                                        ),
                                      ),
                                    )
                                  else
                                    Text(
                                      '${counts[r.id] ?? 0}',
                                      style: t.styles.body.copyWith(
                                        fontSize: 20,
                                        height: 1.15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  // Un nombre largo con letra grande baja el
                                  // tamaño o pasa a dos líneas antes de
                                  // acabar en «…» (solo si una palabra sola
                                  // no cabe ni así).
                                  FitText(
                                    r.name,
                                    maxLines: large ? 2 : 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.styles.caption.copyWith(
                                      fontSize: 12,
                                      height: 1.15,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Reparte las tarjetas en [columns] columnas del mismo ancho, separadas por
/// [gap]. Cada tarjeta va a la columna que dice [assignment] (una por hijo) y
/// se apila bajo las anteriores de esa columna; con una sola columna es una
/// lista corriente.
///
/// Es un único widget para una y para dos columnas: al cruzar el corte (girar
/// la tablet) las tarjetas no cambian de padre y conservan su estado.
class _CardColumns extends MultiChildRenderObjectWidget {
  const _CardColumns({
    required this.columns,
    required this.gap,
    required this.assignment,
    super.children,
  }) : assert(columns >= 1);

  final int columns;
  final double gap;
  final List<int> assignment;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCardColumns(columns: columns, gap: gap, assignment: assignment);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCardColumns renderObject,
  ) {
    renderObject
      ..columns = columns
      ..gap = gap
      ..assignment = assignment;
  }
}

class _CardColumnsParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderCardColumns extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _CardColumnsParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _CardColumnsParentData> {
  _RenderCardColumns({
    required this._columns,
    required this._gap,
    required this._assignment,
  });

  int _columns;
  set columns(int value) {
    if (_columns != value) {
      _columns = value;
      markNeedsLayout();
    }
  }

  double _gap;
  set gap(double value) {
    if (_gap != value) {
      _gap = value;
      markNeedsLayout();
    }
  }

  List<int> _assignment;
  set assignment(List<int> value) {
    if (!listEquals(_assignment, value)) {
      _assignment = value;
      markNeedsLayout();
    }
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _CardColumnsParentData) {
      child.parentData = _CardColumnsParentData();
    }
  }

  /// Mide los hijos y, con [place], los coloca. Devuelve el tamaño.
  Size _layout(
    BoxConstraints constraints,
    ChildLayouter layoutChild, {
    required bool place,
  }) {
    final width = constraints.maxWidth;
    final columnWidth = (width - _gap * (_columns - 1)) / _columns;
    final inner = BoxConstraints.tightFor(width: math.max(columnWidth, 0));
    final heights = List<double>.filled(_columns, 0);
    var child = firstChild;
    var i = 0;
    while (child != null) {
      final column = math.min(
        math.max(i < _assignment.length ? _assignment[i] : 0, 0),
        _columns - 1,
      );
      final size = layoutChild(child, inner);
      final data = child.parentData! as _CardColumnsParentData;
      if (place) {
        data.offset = Offset(column * (columnWidth + _gap), heights[column]);
      }
      heights[column] += size.height;
      child = data.nextSibling;
      i++;
    }
    return constraints.constrain(Size(width, heights.reduce(math.max)));
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _layout(constraints, ChildLayoutHelper.dryLayoutChild, place: false);

  @override
  void performLayout() {
    size = _layout(constraints, ChildLayoutHelper.layoutChild, place: true);
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToFirstActualBaseline(baseline);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// Lo que pinta la tarjeta de una persona; un fantasma que se pliega
/// conserva el suyo hasta que desaparece.
class _CardData {
  const _CardData(this.recipient, this.gifts);

  final Recipient recipient;
  final List<Gift> gifts;
}

/// La tarjeta de una persona: su cabecera y una fila por regalo.
class _RecipientCard extends StatelessWidget {
  const _RecipientCard({
    required this.index,
    required this.recipient,
    required this.isSelf,
    required this.occasion,
    required this.occasionTitle,
    required this.gifts,
    required this.view,
    required this.stage,
    required this.openId,
    required this.pending,
    required this.onToggle,
    required this.onPick,
    required this.onPickPerson,
    required this.onOpenPerson,
  });

  final int index;
  final Recipient recipient;

  /// Si es la persona dueña de este móvil («Yo»).
  final bool isSelf;
  final Occasion occasion;
  final String occasionTitle;
  final List<Gift> gifts;
  final FamilyView view;
  final RepartoStage stage;
  final String? openId;
  final ({String giftId, String? giverId})? pending;
  final ValueChanged<String> onToggle;
  final void Function(Gift gift, String? giverId) onPick;
  final void Function(Gift gift, GiverPersonCandidate candidate) onPickPerson;
  final void Function(Recipient recipient, Rect from) onOpenPerson;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    var cents = 0;
    for (final g in gifts) {
      cents += g.actualCents ?? g.plannedCents ?? 0;
    }
    // Con letra grande el nombre y el resumen no caben lado a lado: el resumen
    // baja debajo del nombre, para que el nombre no se quede en dos letras.
    final large = isLargeText(context);
    final summary = gifts.isEmpty
        ? l10n.repartoOccasionNothingIn(occasionTitle)
        : '${gifts.length} · ${cents > 0 ? formatCents(cents, l10n.localeName) : l10n.familyNoPrice}';
    final Widget name = RepartoAnchor(
      stage: stage,
      id: repartoNameAnchor(recipient.id),
      child: FitText(
        recipient.name,
        maxLines: large ? 2 : 1,
        overflow: TextOverflow.ellipsis,
        style: repartoCardNameStyle(t),
      ),
    );
    // El margen lateral lo pone quien reparte las tarjetas en columnas.
    return Container(
      margin: const EdgeInsets.only(top: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: RegalosShape.card,
        border: Border.all(color: t.separator),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: t.surface,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: _CardHeaderLayout(
                  large: large,
                  identity: Builder(
                    builder: (context) {
                      void open() {
                        final box = context.findRenderObject();
                        if (box is RenderBox && box.attached) {
                          onOpenPerson(
                            recipient,
                            box.localToGlobal(Offset.zero) & box.size,
                          );
                        }
                      }

                      return Semantics(
                        header: true,
                        button: true,
                        label: l10n.repartoPersonOpen(
                          isSelf
                              ? l10n.repartoSelfName(recipient.name)
                              : recipient.name,
                        ),
                        excludeSemantics: true,
                        onTap: open,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: open,
                          child: Row(
                            children: [
                              RepartoAnchor(
                                stage: stage,
                                id: repartoAvatarAnchor(recipient.id),
                                child: RepartoAvatar(
                                  name: recipient.name,
                                  colorIndex: recipient.colorIndex,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  // «Yo» va a la derecha del nombre si
                                  // cabe y, si no, debajo. No viaja en
                                  // el cambio de vista: se funde cuando
                                  // llega su nombre.
                                  child: isSelf
                                      ? Wrap(
                                          spacing: 6,
                                          runSpacing: 2,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            name,
                                            RepartoAnchor(
                                              stage: stage,
                                              id: repartoSelfAnchor(
                                                recipient.id,
                                              ),
                                              child: const SelfTag(),
                                            ),
                                          ],
                                        )
                                      : name,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  // El avatar y el nombre son el destino (o el origen) del
                  // vuelo entre vistas: no entran escalonados, su rectángulo
                  // tiene que estar en su sitio desde el primer fotograma.
                  trailing: RepartoBlock(
                    index: index,
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: large ? double.infinity : 150,
                          ),
                          child: Text(
                            summary,
                            maxLines: large ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.styles.caption.copyWith(fontSize: 13),
                          ),
                        ),
                        if (gifts.isEmpty) ...[
                          _AddChip(
                            label: l10n.repartoOccasionAddShort,
                            semantics:
                                '${l10n.repartoSheetAddGift}: ${recipient.name}',
                            onTap: () => openGiftEditor(
                              context,
                              recipientId: recipient.id,
                              occasionId: occasion.id,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          for (final g in gifts)
            _GiftRow(
              key: ValueKey<String>(g.id),
              gift: g,
              view: view,
              stage: stage,
              open: openId == g.id,
              pickedGiverId: pending != null && pending!.giftId == g.id
                  ? (pending!.giverId, true)
                  : null,
              onToggle: () => onToggle(g.id),
              onPick: (id) => onPick(g, id),
              onPickPerson: (c) => onPickPerson(g, c),
            ),
        ],
      ),
    );
  }
}

/// La cabecera de una tarjeta de persona: quién es ([identity]) y el resumen
/// de sus regalos ([trailing]). Lado a lado, o con [large] (letra grande) el
/// resumen debajo del nombre y alineado con él.
class _CardHeaderLayout extends StatelessWidget {
  const _CardHeaderLayout({
    required this.large,
    required this.identity,
    required this.trailing,
  });

  final bool large;
  final Widget identity;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    if (large) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          identity,
          Padding(
            padding: const EdgeInsets.only(left: kAvatarIndent, top: 2),
            child: trailing,
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: identity),
        const SizedBox(width: 8),
        trailing,
      ],
    );
  }
}

/// «No les regaláis en Navidad»: las personas que se saltan la ocasión, en un
/// recuadro gris liso al final, con un chip cada una que abre su ficha.
class _NotGivingBlock extends StatelessWidget {
  const _NotGivingBlock({
    required this.title,
    required this.people,
    required this.onOpenPerson,
  });

  final String title;
  final List<Recipient> people;
  final void Function(Recipient recipient, Rect from) onOpenPerson;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: RegalosShape.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            container: true,
            header: true,
            child: Row(
              children: [
                StrokeIcon(AppIcons.ban, size: 14, color: t.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: t.styles.metaStrong.copyWith(
                      fontWeight: FontWeight.w700,
                      color: t.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            children: [
              for (final r in people)
                Builder(
                  builder: (context) {
                    void open() {
                      final box = context.findRenderObject();
                      if (box is RenderBox && box.attached) {
                        onOpenPerson(
                          r,
                          box.localToGlobal(Offset.zero) & box.size,
                        );
                      }
                    }

                    return Semantics(
                      container: true,
                      button: true,
                      label: l10n.repartoPersonOpen(r.name),
                      excludeSemantics: true,
                      onTap: open,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: open,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 44),
                          child: Center(
                            widthFactor: 1,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: t.bg,
                                borderRadius: RegalosShape.chip,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                child: Text(
                                  r.name,
                                  style: t.styles.metaStrong.copyWith(
                                    fontWeight: FontWeight.w600,
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
            ],
          ),
        ],
      ),
    );
  }
}

/// Un regalo: su casilla, su título, el chip de quién lo regala y, desplegada
/// debajo, la fila para cambiarlo.
class _GiftRow extends ConsumerWidget {
  const _GiftRow({
    super.key,
    required this.gift,
    required this.view,
    required this.stage,
    required this.open,
    required this.pickedGiverId,
    required this.onToggle,
    required this.onPick,
    required this.onPickPerson,
  });

  final Gift gift;
  final FamilyView view;
  final RepartoStage stage;
  final bool open;

  /// La elección pendiente de este regalo (`(giverId, true)`), o `null`.
  final (String?, bool)? pickedGiverId;
  final VoidCallback onToggle;
  final ValueChanged<String?> onPick;
  final ValueChanged<GiverPersonCandidate> onPickPerson;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final motion = RegalosMotion.of(context);
    final price = giftPriceText(l10n, gift) ?? l10n.familyNoPrice;
    final giver = view.resolveGiver(
      pickedGiverId == null ? gift.giverId : pickedGiverId!.$1,
    );
    final selectedId = giver?.id;
    // En el plan de un deseo que cogió otra persona, quién regala se ve y no
    // se cambia.
    final editable = ref.watch(giftGiverEditableProvider(gift.id));
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.separator)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RepartoAnchor(
            stage: stage,
            id: repartoGiftAnchor(gift.id),
            child: ColoredBox(
              color: t.bg,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 58),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
                  child: GiftRowLayout(
                    large: isLargeText(context),
                    indent: 32,
                    info: Semantics(
                      button: true,
                      label: gift.title,
                      excludeSemantics: true,
                      onTap: () => openGiftEditor(context, gift: gift),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => openGiftEditor(context, gift: gift),
                        child: Row(
                          children: [
                            StatusHoverTip(
                              status: gift.status.visualStatus,
                              child: StatusGlyph(
                                status: gift.status.visualStatus,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      gift.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: t.styles.rowTitleCompact.copyWith(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$price · ${gift.status.visualStatus.label(l10n)}',
                                      maxLines: isLargeText(context) ? 3 : 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: t.styles.caption,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    chip: GiverChip(
                      giver: giver,
                      onTap: editable ? onToggle : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // La fila de chips se despliega en línea con un muelle y se pliega
          // sin rebotar. Con «Reducir movimiento» aparece sin desplegarse: en
          // un fotograma y no con `Duration.zero`, que hace a `AnimatedSize`
          // marcarse para maquetar dentro de su propia maquetación cuando su
          // hijo cambia de tamaño (al girar la tablet, por ejemplo).
          AnimatedSize(
            duration: motion.reduce
                ? const Duration(milliseconds: 1)
                : (open
                      ? RegalosSprings.snapDuration
                      : RegalosCurves.foldDuration),
            curve: open ? RegalosCurves.snap : RegalosCurves.fold,
            alignment: Alignment.topCenter,
            child: open && editable
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(44, 2, 12, 12),
                    child: GiverPicker(
                      givers: view.selectableGiversFor(gift.recipientId),
                      selectedId: selectedId,
                      onPick: onPick,
                      people: personSectionOf(
                        ref.watch(giftGiverPersonCandidatesProvider(gift.id)),
                      ),
                      onPickPerson: onPickPerson,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// «+ Añadir» de una persona sin regalos en la ocasión: chip discontinuo.
class _AddChip extends StatelessWidget {
  const _AddChip({
    required this.label,
    required this.semantics,
    required this.onTap,
  });

  final String label;
  final String semantics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            widthFactor: 1,
            child: DashedBox(
              color: t.ink.withValues(alpha: 0.65),
              radius: RegalosShape.chipRadius,
              strokeWidth: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StrokeIcon(AppIcons.plus, size: 14, color: t.ink),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1,
                        fontWeight: FontWeight.w600,
                        color: t.ink,
                      ),
                    ),
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

/// El estado vacío: un recuadro de radio 8 con el icono, el título, la frase
/// y, si la hay, una llamada a la acción.
class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({
    this.icon,
    this.occasion,
    this.theme,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  /// Icono de trazo; si es `null` sale el de [occasion].
  final StrokeIconBuilder? icon;
  final Occasion? occasion;
  final OccasionTheme? theme;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final colors = theme == null
        ? (fill: t.soft, ink: t.ink)
        : _bandColors(t, theme!);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 40, 28, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.fill,
                  borderRadius: RegalosShape.card,
                ),
                child: SizedBox.square(
                  dimension: 60,
                  child: Center(
                    child: icon != null
                        ? StrokeIcon(icon!, size: 28, color: colors.ink)
                        : OccasionKindIcon(
                            occasion!.kind,
                            customIcon: occasion!.icon,
                            size: 28,
                            color: colors.ink,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: t.styles.rowTitle.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center, style: t.styles.meta),
              if (actionLabel != null) ...[
                const SizedBox(height: 16),
                Material(
                  color: t.fill,
                  shape: const RoundedRectangleBorder(
                    borderRadius: RegalosShape.button,
                  ),
                  child: InkWell(
                    onTap: onAction,
                    customBorder: const RoundedRectangleBorder(
                      borderRadius: RegalosShape.button,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: 44,
                        minWidth: math.min(
                          200,
                          PaneScope.widthOf(context) - 56,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              StrokeIcon(
                                AppIcons.plus,
                                size: 18,
                                color: t.onFill,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  actionLabel!,
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.styles.label.copyWith(
                                    color: t.onFill,
                                    fontWeight: FontWeight.w600,
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
              ],
            ],
          ),
        ),
      ),
    );
  }
}
