import '../../web_device/application/web_app_provider.dart';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/dates.dart';
import '../../../core/platform/gifts_secure_scope.dart';
import '../../../core/format/money.dart';
import '../../../core/layout/content_gutter.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/layout/pane_scope.dart';
import '../../../core/layout/two_pane.dart';
import '../../../core/motion/animated_rows.dart';
import '../../../core/motion/avatar_hero.dart';
import '../../../core/motion/completion_ring.dart';
import '../../../core/motion/delivered_sweep.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/motion/rect_flight.dart';
import '../../../core/motion/highlight_flash.dart';
import '../../../core/motion/sheen.dart';
import '../../../core/motion/sheet_motion.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/motion/state_switcher.dart';
import '../../../core/motion/value_switcher.dart';
import '../../../core/platform/user_link.dart';
import '../../../core/sync/model.dart';
import '../../../core/sync/wish.dart';
import '../../../core/sync/wish_plan.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/budget_meter.dart';
import '../../../core/widgets/choice_grid.dart';
import '../../../core/widgets/desktop_add_gift_button.dart';
import '../../../core/widgets/dot_line.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/filter_pill.dart';
import '../../../core/widgets/fold_box.dart';
import '../../../core/widgets/gift_row.dart';
import '../../../core/widgets/gift_status_map.dart';
import '../../../core/widgets/giver_dot.dart';
import '../../../core/widgets/occasion_icons.dart';
import '../../../core/theme/accent_palette.dart' show AccentPalette;
import '../../../core/widgets/person_avatar.dart'
    show PersonAvatar, personPalette;
import '../../../core/widgets/pointer_surface.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/secret_block.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/widgets/tabler_icons.dart';
import '../../../core/widgets/wish_row.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_actions.dart';
import '../../family/application/family_providers.dart';
import '../../family/application/gift_logic.dart';
import '../../family/application/remote_change.dart';
import '../../family/presentation/family_texts.dart';
import '../../family/presentation/pending_gifts_sheet.dart';
import '../../family/presentation/person_sheet.dart';
import '../../family/presentation/protection_sheet.dart';
import '../../family/presentation/secret_blocks.dart';
import '../application/delivered_arm.dart';
import '../application/person_completion.dart';
import '../../web_board/application/board_metrics.dart';
import '../../web_board/presentation/board_gift_table.dart';
import 'gift_actions.dart';
import 'wish_plan_note.dart';
import 'gift_editor_screen.dart';
import 'gift_link_actions.dart';
import 'wish_claim_problem.dart' show wishNoticeInsetProvider;
import 'wish_editor.dart';

/// La lista de regalos de una persona: secciones por ocasión, filtros, mini
/// presupuesto de la casa y botón para añadir.
class PersonListScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla. [initialFilter] llega desde la rejilla de la familia.
  const PersonListScreen({
    super.key,
    required this.recipientId,
    this.initialFilter = const GiftFilter(),
    this.fromFamily = false,
    this.boardTable = false,
  });

  /// Si es la tabla del tablero de la web de escritorio
  /// (la guía de diseño de escritorio, «Persona»): a todo el
  /// ancho, con cabecera de columnas y las columnas que caben.
  final bool boardTable;

  /// Persona de la lista.
  final String recipientId;

  /// Filtros con que se abre.
  final GiftFilter initialFilter;

  /// Si se abrió desde Reparto (con `push`): el botón de atrás y la
  /// miga de pan dicen entonces Reparto y no Personas.
  final bool fromFamily;

  @override
  ConsumerState<PersonListScreen> createState() => _PersonListScreenState();
}

class _PersonListScreenState extends ConsumerState<PersonListScreen>
    with SingleTickerProviderStateMixin {
  late GiftFilter _filter = widget.initialFilter;

  // La cabecera que se pliega al bajar por la lista (0 entera, 1 plegada):
  // la tarjeta de presupuesto, los filtros y el resumen de debajo del nombre
  // se van y quedan el avatar y el nombre; vuelven al subir.
  late final AnimationController _fold = AnimationController(vsync: this);
  final ScrollController _scroll = ScrollController();
  final GlobalKey _foldKey = GlobalKey();

  // Si el «+» flotante se esconde: al bajar por la lista se va y al subir
  // vuelve (lógica aparte de la cabecera plegable: vale también con la lista
  // sin cabecera que plegar).
  final ValueNotifier<bool> _fabHidden = ValueNotifier<bool>(false);
  double _lastPixels = 0;
  double _run = 0;
  bool _foldEnabled = true;

  /// Lo que hay que bajar en un sentido para plegar o desplegar la cabecera;
  /// así vale también el desplazamiento lento o el de la rueda del ratón.
  static const double _foldRun = 24;
  static const double _unfoldRun = 16;

  /// Lo que hay que bajar para esconder el «+» y lo que hay que subir para
  /// que vuelva.
  static const double _fabHideRun = 24;
  static const double _fabShowRun = 12;

  /// Cuánto margen de lista debe quedar al plegar: si no, al plegarse la lista
  /// dejaría de desplazarse y no se podría volver a desplegar.
  static const double _foldRoom = 96;

  // Avisos a las filas: cuál iluminar al guardar y por cuáles pasa la ola de
  // luz al completar a la persona.
  final HighlightSignal _highlight = HighlightSignal();
  final LightWaveSignal _wave = LightWaveSignal();
  final GlobalKey<SheenState> _budgetSheen = GlobalKey<SheenState>();

  // Se aumenta en cada celebración; el último cambio de «completa» llegó por
  // sincronización si `_quiet`.
  int _celebration = 0;
  bool _quiet = false;

  // Para saber si lo que cambia en la lista llegó de otro móvil.
  int _seenRemote = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScrollTick);
  }

  /// Pliega (`true`) o despliega la cabecera con un movimiento suave: al
  /// plegarse, sin rebote; al volver, con `snap`. Con «Reducir movimiento»,
  /// 150 ms de fundido.
  void _setFolded(bool folded) {
    if (!mounted || (_fold.value == (folded ? 1 : 0) && !_fold.isAnimating)) {
      return;
    }
    final reduce = RegalosMotion.of(context).reduce;
    if (folded) {
      _fold.animateTo(
        1,
        duration: reduce
            ? RegalosMotion.fade
            : const Duration(milliseconds: 240),
        curve: reduce ? Curves.linear : RegalosCurves.fold,
      );
    } else {
      _fold.animateTo(
        0,
        duration: reduce ? RegalosMotion.fade : RegalosSprings.snapDuration,
        curve: reduce ? Curves.linear : RegalosCurves.snap,
      );
    }
  }

  /// Lo que se pliega al bajar: la tarjeta de presupuesto y los filtros, más
  /// el resumen de debajo del nombre.
  double _foldedExtent() {
    final box = _foldKey.currentContext?.findRenderObject();
    final own = box is RenderBox && box.hasSize ? box.size.height : 240;
    return own + 48;
  }

  void _onScrollTick() {
    if (!_scroll.hasClients) {
      return;
    }
    final pos = _scroll.position;
    final delta = pos.pixels - _lastPixels;
    _lastPixels = pos.pixels;
    if (pos.pixels <= 0) {
      _run = 0;
      _fabHidden.value = false;
      if (_foldEnabled) {
        _setFolded(false);
      }
      return;
    }
    // Fuera de rango (el rebote de iOS al llegar al final) no cuenta: al
    // volver no despliega la cabecera ni devuelve el «+». Lo que la lista se
    // corrige sola al cambiar de alto no avisa, así que tampoco los mueve.
    if (delta == 0 || pos.outOfRange) {
      return;
    }
    if (delta.sign != _run.sign) {
      _run = 0;
    }
    _run += delta;
    // El «+»: se va al bajar (solo si la lista se desplaza), vuelve al subir
    // y al llegar al final, para poder pulsarlo.
    if (pos.maxScrollExtent <= 0 || pos.pixels >= pos.maxScrollExtent) {
      _fabHidden.value = false;
    } else if (_run > _fabHideRun) {
      _fabHidden.value = true;
    } else if (_run < -_fabShowRun) {
      _fabHidden.value = false;
    }
    if (!_foldEnabled) {
      return;
    }
    if (_run > _foldRun) {
      if (pos.maxScrollExtent >= _foldedExtent() + _foldRoom) {
        _setFolded(true);
      }
    } else if (_run < -_unfoldRun) {
      _setFolded(false);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _fold.dispose();
    _fabHidden.dispose();
    _highlight.dispose();
    _wave.dispose();
    super.dispose();
  }

  /// Abre el editor y, al volver, ilumina la fila guardada.
  Future<void> _openEditor({
    Gift? gift,
    String? recipientId,
    String? occasionId,
    String? giverId,
  }) async {
    final saved = await openGiftEditor(
      context,
      gift: gift,
      recipientId: recipientId,
      occasionId: occasionId,
      giverId: giverId,
    );
    if (saved != null && mounted) {
      _highlight.highlight(saved);
    }
  }

  /// Abre el editor de un deseo nuevo de [personId] (la persona de este
  /// dispositivo) y, al volver, ilumina la fila guardada.
  Future<void> _addWish(String personId) async {
    final saved = await openWishEditor(context, recipientId: personId);
    if (saved != null && mounted) {
      _highlight.highlight(saved);
    }
  }

  /// Abre el formulario de un deseo visible para [personId], cuyo bloque está
  /// cerrado en este móvil: «Visible para» fijo y la sorpresa apagada.
  Future<void> _suggestWish(String personId) async {
    final saved = await openGiftEditor(
      context,
      recipientId: personId,
      suggestVisible: true,
    );
    if (saved != null && mounted) {
      _highlight.highlight(saved);
    }
  }

  /// Abre el deseo propio [wish] para cambiarlo.
  Future<void> _editWish(Wish wish) async {
    final saved = await openWishEditor(
      context,
      wish: wish,
      recipientId: wish.recipientId,
    );
    if (saved != null && mounted) {
      _highlight.highlight(saved);
    }
  }

  /// Abre el editor para añadir un regalo a [personId], con la ocasión y quien
  /// regala de los filtros puestos (o con [occasionId], si se pide una).
  Future<void> _addGift(String personId, {String? occasionId}) async {
    // En el móvil de la propia persona no se apuntan regalos para ella, solo
    // deseos.
    if (ref.read(wishReaderProvider) == personId) {
      return _addWish(personId);
    }
    // Quien solo regala (1.0.6) no recibe regalos.
    if (ref.read(familyFullViewProvider).recipientsById[personId]?.noGifts ==
        true) {
      return;
    }
    return _openEditor(
      recipientId: personId,
      occasionId:
          occasionId ??
          (_filter.occasionId == null ||
                  _filter.occasionId == GiftFilter.kNoOccasion
              ? null
              : _filter.occasionId),
      giverId: _filter.giverId == null || _filter.giverId == kUnassignedGiver
          ? null
          : _filter.giverId,
    );
  }

  /// Cuando la persona pasa de incompleta a completa decide si celebra: solo
  /// si lo provocó una acción del usuario (la casilla, el selector o el
  /// editor armaron la celebración justo antes de guardar).
  void _onCompletion(PersonCompletion? before, PersonCompletion now) {
    final armed = ref
        .read(celebrationArmedProvider.notifier)
        .consume(widget.recipientId);
    final crossed = !(before?.complete ?? false) && now.complete;
    _quiet = !armed;
    if (!crossed || !armed || now.occasion == null) {
      return;
    }
    // La celebración: háptica, ola de luz por las filas de esa ocasión y
    // brillo sobre el presupuesto (el arco y el sello los pone el avatar).
    // La vibración llega con el sello (250 ms) y manda sobre la de la casilla
    // que aún espere su turno.
    ref
        .read(hapticsProvider)
        .play(HapticLevel.success, after: context.hapticSeal, supersede: true);
    final ids = <String>[
      for (final g in ref.read(familyViewProvider).giftsFor(widget.recipientId))
        if (g.occasionId == now.occasion!.id) g.id,
    ];
    _wave.wave(ids);
    _budgetSheen.currentState?.play(delay: const Duration(milliseconds: 410));
    _celebration++;
  }

  /// Nombre de la pestaña desde la que se llegó.
  String _originName(AppLocalizations l10n) =>
      widget.fromFamily ? l10n.navFamily : l10n.navPeople;

  void _back() => context.canPop() ? context.pop() : context.go('/people');

  Future<void> _editPerson(Recipient person) async {
    final l10n = AppLocalizations.of(context);
    final result = await showPersonSheet(
      context,
      initial: person,
      defaultColorIndex: person.colorIndex,
    );
    if (result != null && mounted) {
      await saveRecipient(ref, l10n, result);
    }
  }

  Future<void> _openFilters() async {
    await showRegalosSheet<void>(
      context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FiltersSheet(
        initial: _filter,
        onChanged: (f) => setState(() => _filter = f),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => GiftsSecureScope(
    // Una persona cuyos regalos este móvil no enseña (solo el bloque fijo) no
    // enseña regalos.
    enabled: !ref.watch(lockedPeopleProvider).contains(widget.recipientId),
    child: _buildScreen(context),
  );

  Widget _buildScreen(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final view = ref.watch(familyViewProvider);
    final full = ref.watch(familyFullViewProvider);
    final budget = ref.watch(budgetProvider);
    final person = full.recipientsById[widget.recipientId];
    // Persona con regalos en secreto que este móvil no puede ver: ni lista, ni
    // cifras, ni filtros; solo el bloque fijo.
    final locked = ref.watch(lockedPeopleProvider).contains(widget.recipientId);
    final web = ref.watch(webAppProvider);
    final ownHidden = ref
        .watch(ownHiddenPeopleProvider)
        .contains(widget.recipientId);
    // La persona de este dispositivo apunta deseos, no regalos para sí: lo
    // decide quién mira, no si sus regalos están ocultos (un móvil sin
    // emparejar aún no oculta nada y ya es el de su persona).
    final ownPerson = ref.watch(wishReaderProvider) == widget.recipientId;
    // Se repinta al recoger o cambiar los pendientes de la web.
    ref.watch(webPendingSecretGiftIdsProvider);
    // Quien solo regala (1.0.6) no recibe regalos: aquí no se añade ninguno.
    final canAdd = person?.noGifts != true;
    final canSuggest = ref.watch(canSuggestWishProvider(widget.recipientId));
    ref.listen<PersonCompletion>(
      personCompletionProvider(widget.recipientId),
      _onCompletion,
    );
    final completion = ref.watch(personCompletionProvider(widget.recipientId));
    // Lo que cambia en la lista y llegó de otro móvil entra en silencio.
    final remote = ref.watch(remoteChangeProvider);
    final fromRemote = remote != _seenRemote;
    _seenRemote = remote;
    // En tablet todo va en una columna de 640 centrada en el panel (720 o 880
    // si es el panel de detalle de dos paneles). La lista lleva el margen como
    // relleno (`ContentListView`), para que se siga desplazando al arrastrar
    // por los lados; lo demás se limita con `ContentWidth`. En el móvil el
    // margen es cero y nada cambia.
    final isDetail = PaneScope.roleOf(context) == PaneRole.detail;
    // Con dos paneles (escritorio): el botón de añadir va en la cabecera, las
    // filas en columnas si caben y la persona sin regalos lleva su bloque.
    final desktop = isDetail;
    // La cabecera solo se pliega en una sola columna (móvil y tablet
    // vertical) y con una lista que se desplace.
    _foldEnabled = !desktop && !locked;
    if (!_foldEnabled && _fold.value != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _setFolded(false));
    }
    final table = widget.boardTable && desktop;
    final columnWidth = table ? double.infinity : detailColumnWidth(context);
    // En la tabla del tablero, la tarjeta ocupa el ancho de la tabla (sus
    // bordes, con el mismo margen de 16, caen sobre los de la cabecera) hasta
    // un máximo de 1200 de tarjeta (más los dos márgenes), pegada a la
    // izquierda: en ventanas muy anchas las barras no se hacen eternas.
    Widget narrowColumn(Widget child) => table
        ? Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _kBudgetCardMax + 32),
              child: child,
            ),
          )
        : ContentWidth(maxWidth: columnWidth, child: child);
    // En el detalle de dos paneles la lista de la persona es la raíz: sin
    // flecha de volver (la lista de personas está a la vista), salvo que se
    // viniera de Reparto.
    final VoidCallback? onBack = isDetail && !widget.fromFamily ? null : _back;
    Widget column(Widget child) =>
        ContentWidth(maxWidth: columnWidth, child: child);
    if (person == null) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              column(
                ScreenHeader(
                  title: _originName(l10n),
                  onBack: _back,
                  backLabel: l10n.backTo(_originName(l10n)),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final now = clock.now();
    // Los deseos (ADR 0010): la persona los ve sin estado; quien abre su
    // bloque, con lo que han hecho los demás. Un deseo cogido se ve una vez,
    // como su plan (un regalo); la web no proyecta los planes como regalos y
    // se pintan desde las filas del motor.
    final planRows = ref.watch(wishPlanStateRowsProvider(person.id));
    final planRowOf = <String, WishPlanRow>{
      for (final row in planRows)
        for (final plan in row.plans) plan.planId: row,
    };
    final wishEntries = ref.watch(wishEntriesProvider(person.id));
    final freeWishes = ref.watch(freeWishCountsProvider).ofPerson(person.id);
    // Una persona cuyos regalos este móvil no enseña (solo su bloque) no
    // enseña ninguno: queda su lista de deseos.
    final gifts = locked
        ? const <Gift>[]
        : [
            ...view.giftsFor(person.id),
            if (web)
              for (final row in planRows)
                for (final plan in row.plans)
                  wishPlanAsGift(plan, wish: row.wish, year: now.year),
          ];
    final shown = [
      for (final g in gifts)
        if (_filter.matches(g, view: view)) g,
    ];
    final shownWishes = [
      for (final e in wishEntries)
        if ((e.actions.isOwner || e.actions.plans.isEmpty) &&
            _filter.matches(_wishAsGift(e.wish), view: view))
          e,
    ];
    // Hay algo que enseñar (aunque un filtro lo esconda).
    final hasAny = gifts.isNotEmpty || wishEntries.isNotEmpty;
    final entries = <_ListEntry>[
      for (final g in shown) _ListEntry.gift(g),
      for (final e in shownWishes) _ListEntry.wish(e),
    ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final reader = ref.watch(wishReaderProvider);
    final occasions = ref.watch(occasionsProvider);
    final occasionsById = {for (final o in occasions) o.id: o};
    final givers = view.giversById;
    final people = full.recipientsById;
    final labels = OccasionLabels(l10n, people);
    final age = ageText(l10n, person, now);
    final palette = personPalette(person.colorIndex);
    final pastel = palette.surfaceOf(t.isDark);

    // Secciones: una por ocasión, por orden de fecha, y al final «sin ocasión».
    final byOccasion = <String, List<_ListEntry>>{};
    for (final e in entries) {
      final key = occasionsById.containsKey(e.occasionId)
          ? e.occasionId!
          : GiftFilter.kNoOccasion;
      byOccasion.putIfAbsent(key, () => <_ListEntry>[]).add(e);
    }
    // Entran de arriba abajo (§1.6): la tarjeta de presupuesto es el 0, los
    // filtros el 1 y luego cada cabecera de sección y cada fila. Las filas
    // llevan clave estable (el id del regalo) para que el estado de su casilla
    // no salte de una a otra al filtrar.
    var order = 2;
    AnimatedRowItem giftRow(Gift g) => AnimatedRowItem(
      id: g.id,
      child: StaggerItem(
        index: order++,
        child: HighlightFlash(
          id: g.id,
          signal: _highlight,
          color: pastel,
          child: LightWave(
            id: g.id,
            signal: _wave,
            color: pastel.withValues(alpha: 0.4),
            // La casilla que da luz: al entregar por una acción del usuario,
            // el pastel barre la fila desde la casilla.
            child: DeliveredSweep(
              delivered: g.status == GiftStatus.delivered,
              consumeArm: () => ref.read(deliveredArmsProvider).consume(g.id),
              color: pastel,
              child: _row(
                context,
                g,
                givers,
                people,
                l10n,
                desktop,
                table: table,
                planRow: planRowOf[g.id],
                reader: reader,
              ),
            ),
          ),
        ),
      ),
    );
    AnimatedRowItem row(_ListEntry entry) {
      final wishEntry = entry.wish;
      if (wishEntry != null) {
        return AnimatedRowItem(
          id: wishEntry.wish.id,
          child: StaggerItem(
            index: order++,
            child: HighlightFlash(
              id: wishEntry.wish.id,
              signal: _highlight,
              color: pastel,
              child: _wishRow(
                context,
                wishEntry,
                l10n,
                table: table,
                palette: palette,
                columns: desktop && !table,
              ),
            ),
          ),
        );
      }
      return giftRow(entry.gift!);
    }

    final sections = <AnimatedRowItem>[];
    final ordered = occasionsByNextDate([
      for (final o in occasions)
        if (byOccasion.containsKey(o.id)) o,
    ], now);
    for (final o in ordered) {
      sections
        ..add(
          AnimatedRowItem(
            id: 'section-${o.id}',
            child: StaggerItem(
              index: order++,
              child: _sectionInset(
                table,
                SectionHeader(
                  title: labels.of(o),
                  trailing: shortDayMonth(o.month, o.day, l10n.localeName),
                  padding: table
                      ? const EdgeInsets.fromLTRB(0, 10, 0, 6)
                      : const EdgeInsets.fromLTRB(16, 10, 16, 6),
                ),
              ),
            ),
          ),
        )
        ..addAll(byOccasion[o.id]!.map(row));
    }
    final loose = byOccasion[GiftFilter.kNoOccasion];
    if (loose != null) {
      sections
        ..add(
          AnimatedRowItem(
            id: 'section-none',
            child: StaggerItem(
              index: order++,
              child: _sectionInset(
                table,
                SectionHeader(
                  title: l10n.giftNoOccasion,
                  padding: table
                      ? const EdgeInsets.fromLTRB(0, 10, 0, 6)
                      : const EdgeInsets.fromLTRB(16, 10, 16, 6),
                ),
              ),
            ),
          ),
        )
        ..addAll(loose.map(row));
    }

    if (table) {
      // El orden de las flechas del teclado: el de la tabla.
      ref.read(boardGiftCursorProvider).register([
        for (final s in sections)
          if (!s.id.startsWith('section-') && shown.any((g) => g.id == s.id))
            s.id,
      ]);
    }
    // Las dos tiras cuentan lo comprado sobre el total de los regalos (precio
    // real o, si falta, el previsto): la de la persona, de todos sus regalos
    // pague quien pague; la de la casa, de lo que cuenta como gasto de casa.
    // Sin presupuesto por persona, la barra nunca pasa a rojo.
    final personTotals = budget.ofRecipientAllGivers(person.id);
    final houseTotals = budget.total;
    double fraction(BudgetTotals totals) => totals.expectedCents > 0
        ? (totals.boughtCents / totals.expectedCents).clamp(0.0, 1.0)
        : 0;
    String money(int cents) => formatCents(cents, l10n.localeName);

    final editButton = Semantics(
      button: true,
      label: l10n.personEdit,
      excludeSemantics: true,
      onTap: () => _editPerson(person),
      child: Tooltip(
        message: l10n.personEdit,
        excludeFromSemantics: true,
        child: SizedBox.square(
          dimension: 44,
          child: InkResponse(
            onTap: () => _editPerson(person),
            child: Center(
              child: StrokeIcon(AppIcons.edit, size: 22, color: t.text),
            ),
          ),
        ),
      ),
    );

    // Con dos paneles, «Añadir regalo» va en la cabecera, relleno, junto a
    // «Editar»; no hay «+» flotante.
    final addButton = Padding(
      padding: const EdgeInsets.only(right: 4),
      child: DesktopAddGiftButton(
        key: const ValueKey<String>('add-gift-header'),
        onPressed: () => _addGift(person.id),
      ),
    );

    // El bloque fijo de una persona cuyos regalos este móvil no enseña.
    final lockedBlock = StaggerItem(
      index: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: SecretBlockCard(
          key: ValueKey<String>('secret-block:${person.id}'),
          name: person.name,
          colorIndex: person.colorIndex,
          web: web,
          // El bloque fijo de la propia persona (ADR 0010):
          // se llama «Sorpresas» y no dice nada de lo que
          // hay detrás.
          title: ownHidden ? l10n.surprisesTitle : null,
          // La persona de este móvil (1.0.6): en él no se
          // ven sus regalos y solo otra persona puede
          // cambiarlo. En la web, «este ordenador».
          note: ownHidden
              ? (web
                    ? l10n.ownGiftsHiddenBodyWeb(person.name)
                    : l10n.ownGiftsHiddenBody(person.name))
              : null,
        ),
      ),
    );

    // Con el bloque de la persona cerrado en este móvil (sin su clave) no se
    // le puede guardar una sorpresa, pero sí sugerirle un deseo visible: el
    // botón abre el formulario con «Visible para» fijo.
    final suggestOnly = locked && !ownPerson && canAdd && canSuggest;
    final suggestButton = Padding(
      padding: const EdgeInsets.only(right: 4),
      child: DesktopAddGiftButton(
        key: const ValueKey<String>('suggest-wish-header'),
        label: l10n.wishSuggest,
        onPressed: () => _suggestWish(person.id),
      ),
    );

    // La persona de este dispositivo apunta sus deseos con el mismo botón.
    final wishButton = Padding(
      padding: const EdgeInsets.only(right: 4),
      child: DesktopAddGiftButton(
        key: const ValueKey<String>('add-wish-header'),
        label: l10n.wishAdd,
        onPressed: () => _addWish(person.id),
      ),
    );

    String? occasionName(String? id) => id == null
        ? null
        : (id == GiftFilter.kNoOccasion
              ? l10n.giftNoOccasion
              : (occasionsById[id] == null
                    ? null
                    : labels.of(occasionsById[id]!)));

    return Scaffold(
      // El «+» se queda a 16 del borde derecho de la columna, no del panel.
      // Con dos paneles no hay «+»: «Añadir regalo» va en la cabecera.
      floatingActionButton:
          desktop || (locked && !ownPerson && !suggestOnly) || !canAdd
          ? null
          : ValueListenableBuilder<bool>(
              valueListenable: _fabHidden,
              builder: (context, hiddenByScroll, child) =>
                  ContentFloatingButton(
                    maxWidth: columnWidth,
                    // Con navegación accesible (lector de pantalla, teclado)
                    // el «+» no se esconde: tendría que aparecer para llegar
                    // a él.
                    hidden:
                        hiddenByScroll &&
                        !MediaQuery.accessibleNavigationOf(context),
                    child: child!,
                  ),
              // El nombre lo lleva el propio nodo del botón, no solo la ayuda
              // flotante: el lector de pantalla no debe oír «Botón» a secas
              // (QA 1.0.7, m4).
              child: Semantics(
                button: true,
                label: suggestOnly
                    ? l10n.wishSuggest
                    : (ownPerson ? l10n.wishAdd : l10n.giftAdd),
                excludeSemantics: true,
                onTap: () => suggestOnly
                    ? _suggestWish(person.id)
                    : (ownPerson ? _addWish(person.id) : _addGift(person.id)),
                child: FloatingActionButton(
                  tooltip: suggestOnly
                      ? l10n.wishSuggest
                      : (ownPerson ? l10n.wishAdd : l10n.giftAdd),
                  onPressed: () => suggestOnly
                      ? _suggestWish(person.id)
                      : (ownPerson ? _addWish(person.id) : _addGift(person.id)),
                  child: StrokeIcon(
                    AppIcons.plus,
                    size: 26,
                    color: t.onFill,
                    strokeWidth: 2.4,
                  ),
                ),
              ),
            ),
      body: StaggerScope(
        // En dos paneles el detalle ya cambia con su propio eje: no repite
        // la entrada escalonada.
        animate: PaneScope.roleOf(context) != PaneRole.detail,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              column(
                ScreenHeader(
                  eyebrow: onBack == null ? null : l10n.navPeople,
                  title: person.name,
                  folded: _fold,
                  subtitleWidget: locked
                      ? (age == null && wishEntries.isEmpty
                            ? null
                            : DotLine(
                                style: t.styles.meta,
                                parts: [
                                  if (age != null) DotPart(age),
                                  if (wishEntries.isNotEmpty)
                                    DotPart(l10n.wishCount(wishEntries.length)),
                                ],
                              ))
                      : !canAdd
                      // Quien solo regala (1.0.6): sin cuenta de regalos.
                      ? DotLine(
                          style: t.styles.meta,
                          parts: [
                            if (age != null) DotPart(age),
                            DotPart(l10n.personNoGiftsLabel),
                          ],
                        )
                      : _Subtitle(
                          age: age,
                          count: gifts.length,
                          text: l10n.giftCount(gifts.length),
                          // Los deseos sin coger, aparte de los regalos.
                          wishText: freeWishes == 0
                              ? null
                              : l10n.wishCount(freeWishes),
                        ),
                  footer: completion.total > 0 && completion.occasion != null
                      ? _CompletionLine(
                          completion: completion,
                          occasionName: labels.of(completion.occasion!),
                        )
                      : null,
                  onBack: onBack,
                  keepBackInPane: onBack != null,
                  backLabel: onBack == null
                      ? null
                      : l10n.backTo(_originName(l10n)),
                  // El avatar vuela desde la fila de Personas; la cabecera no se
                  // escalona (el título entra con la pantalla).
                  leading: CompletionAvatar(
                    avatarSize: 46,
                    fraction: completion.total == 0
                        ? 0
                        : completion.bought / completion.total,
                    complete: completion.complete,
                    celebration: _celebration,
                    quiet: _quiet,
                    showRing: completion.total > 0,
                    // En el tablero de la web, el avatar de la barra lateral
                    // vuela hasta aquí (`FlightTarget`); en el resto no hay
                    // salida pendiente y no hace nada.
                    child: FlightTarget(
                      flightKey: AvatarHero.flightKeyFor(person.id),
                      ghost: (context, size) => PersonAvatar(
                        name: person.name,
                        colorIndex: person.colorIndex,
                        size: size.shortestSide,
                      ),
                      child: AvatarHero(
                        personId: person.id,
                        name: person.name,
                        colorIndex: person.colorIndex,
                        size: 46,
                      ),
                    ),
                  ),
                  actions: [
                    if (desktop && !locked && !ownPerson && canAdd) addButton,
                    if (desktop && suggestOnly) suggestButton,
                    if (desktop && ownPerson && canAdd) wishButton,
                    editButton,
                  ],
                ),
              ),
              if (locked && entries.isEmpty && ownHidden)
                // La lista de deseos vacía de la propia persona: el bloque fijo
                // arriba y, debajo, el vacío de siempre con su acción. Todo en
                // una lista: con letra grande o en horizontal se desplaza.
                Expanded(
                  child: ContentListView(
                    maxWidth: columnWidth,
                    padding: const EdgeInsets.only(bottom: 88),
                    children: [
                      lockedBlock,
                      const SizedBox(height: 16),
                      StaggerItem(
                        index: 1,
                        child: EmptyState(
                          icon: tablerStar,
                          title: l10n.wishEmptyTitle,
                          message: l10n.wishEmptyMessage,
                          action: DesktopAddGiftButton(
                            key: const ValueKey<String>('empty-wish-add'),
                            label: l10n.wishAdd,
                            onPressed: () => _addWish(person.id),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else if (locked)
                Expanded(
                  child: ContentListView(
                    maxWidth: columnWidth,
                    padding: const EdgeInsets.only(bottom: 88),
                    children: [
                      lockedBlock,
                      if (entries.isNotEmpty)
                        AnimatedRows(
                          rows: sections,
                          deleted: ref.watch(recentlyDeletedProvider),
                          quiet: fromRemote,
                          onDeletedGone: (id) => ref
                              .read(recentlyDeletedProvider.notifier)
                              .clear(id),
                        ),
                    ],
                  ),
                )
              else ...[
                // Regalos en secreto de esta persona (el estado, si está
                // pedida o activa) y los pendientes de guardar.
                column(
                  ProtectionRow(
                    personId: person.id,
                    onlyWhenProtected: true,
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  ),
                ),
                column(PendingGiftsNotice(personId: person.id)),
                FoldBox(
                  key: _foldKey,
                  folded: _fold,
                  child: Column(
                    children: [
                      if (!(desktop && !hasAny))
                        narrowColumn(
                          StaggerItem(
                            index: 0,
                            child: Container(
                              margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                              decoration: BoxDecoration(
                                color: t.surface,
                                borderRadius: RegalosShape.card,
                              ),
                              child: Sheen(
                                key: _budgetSheen,
                                borderRadius: RegalosShape.card,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    11,
                                    14,
                                    13,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: BudgetMeter(
                                          label: person.name,
                                          leadLabel: l10n.budgetBought,
                                          valueText: (
                                            spent: money(
                                              personTotals.boughtCents,
                                            ),
                                            planned: money(
                                              personTotals.expectedCents,
                                            ),
                                            ofWord: l10n.budgetOf,
                                          ),
                                          spentOnlyLabel:
                                              personTotals.expectedCents > 0
                                              ? null
                                              : l10n.budgetBought,
                                          fraction: fraction(personTotals),
                                          semanticLabel: l10n
                                              .budgetBoughtBarLabel(
                                                money(personTotals.boughtCents),
                                                money(
                                                  personTotals.expectedCents,
                                                ),
                                              ),
                                          barHeight: table ? 10 : 4,
                                          barRadius: table ? 4 : null,
                                          entrance: table,
                                        ),
                                      ),
                                      const SizedBox(width: 20),
                                      Expanded(
                                        child: BudgetMeter(
                                          label: l10n.budgetHouseTotal,
                                          leadLabel: l10n.budgetBought,
                                          valueText: (
                                            spent: money(
                                              houseTotals.boughtCents,
                                            ),
                                            planned: money(
                                              houseTotals.expectedCents,
                                            ),
                                            ofWord: l10n.budgetOf,
                                          ),
                                          spentOnlyLabel:
                                              houseTotals.expectedCents > 0
                                              ? null
                                              : l10n.budgetBought,
                                          fraction: fraction(houseTotals),
                                          semanticLabel: l10n
                                              .budgetBoughtBarLabel(
                                                money(houseTotals.boughtCents),
                                                money(
                                                  houseTotals.expectedCents,
                                                ),
                                              ),
                                          barHeight: table ? 10 : 4,
                                          barRadius: table ? 4 : null,
                                          entrance: table,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (!(desktop && !hasAny))
                        column(
                          StaggerItem(
                            index: 1,
                            child: Padding(
                              // En la tabla del tablero, a 16 como el avatar, la
                              // tarjeta y la tabla.
                              padding: EdgeInsets.symmetric(
                                horizontal: table ? 16 : 12,
                              ),
                              child: SizedBox(
                                width: double.infinity,
                                child: Wrap(
                                  spacing: 8,
                                  children: [
                                    FilterPill(
                                      label: l10n.filtersButton,
                                      icon: AppIcons.filter,
                                      haptic: false,
                                      onTap: _openFilters,
                                    ),
                                    if (_filter.occasionId != null) ...[
                                      FilterPill(
                                        label:
                                            occasionName(_filter.occasionId) ??
                                            '',
                                        selected: true,
                                        trailingIcon: AppIcons.close,
                                        semanticLabel: l10n.filterRemove(
                                          occasionName(_filter.occasionId) ??
                                              '',
                                        ),
                                        onTap: () => setState(
                                          () => _filter = _filter.copyWith(
                                            clearOccasion: true,
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (_filter.giverId != null) ...[
                                      FilterPill(
                                        label: giverNameFor(
                                          l10n,
                                          givers[_filter.giverId],
                                        ),
                                        selected: true,
                                        trailingIcon: AppIcons.close,
                                        semanticLabel: l10n.filterRemove(
                                          giverNameFor(
                                            l10n,
                                            givers[_filter.giverId],
                                          ),
                                        ),
                                        onTap: () => setState(
                                          () => _filter = _filter.copyWith(
                                            clearGiver: true,
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (_filter.status != null) ...[
                                      StatusChip(
                                        status: _filter.status!.visualStatus,
                                        selected: true,
                                        onTap: () => setState(
                                          () => _filter = _filter.copyWith(
                                            clearStatus: true,
                                          ),
                                        ),
                                      ),
                                    ],
                                    FilterPill(
                                      label: l10n.filterNeedsBuy,
                                      selected: _filter.needsBuy,
                                      onTap: () => setState(
                                        () => _filter = _filter.copyWith(
                                          needsBuy: !_filter.needsBuy,
                                        ),
                                      ),
                                    ),
                                    FilterPill(
                                      label: l10n.filterNeedsWrap,
                                      selected: _filter.needsWrap,
                                      onTap: () => setState(
                                        () => _filter = _filter.copyWith(
                                          needsWrap: !_filter.needsWrap,
                                        ),
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
                Expanded(
                  child: StateSwitcher(
                    stateKey: !hasAny
                        ? 'empty'
                        : (entries.isEmpty ? 'no-results' : 'list'),
                    child: !hasAny
                        ? (desktop
                              ? column(
                                  _EmptyPerson(
                                    name: person.name,
                                    occasions: [
                                      for (final next
                                          in ref
                                              .watch(upcomingOccasionsProvider)
                                              .where(
                                                (n) =>
                                                    n.occasion.recipientId ==
                                                        null ||
                                                    n.occasion.recipientId ==
                                                        person.id,
                                              )
                                              .take(3))
                                        (
                                          id: next.occasion.id,
                                          label: labels.of(next.occasion),
                                          date: shortDate(
                                            next.date,
                                            l10n.localeName,
                                          ),
                                        ),
                                    ],
                                    onAdd: () => _addGift(person.id),
                                    onAddFor: (id) =>
                                        _addGift(person.id, occasionId: id),
                                  ),
                                )
                              : EmptyState(
                                  icon: AppIcons.people,
                                  title: l10n.giftsEmptyTitle(person.name),
                                  message: l10n.giftsEmptyMessage,
                                ))
                        : entries.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  l10n.filterNoResults,
                                  style: t.styles.body,
                                ),
                                TextButton(
                                  onPressed: () => setState(
                                    () => _filter = const GiftFilter(),
                                  ),
                                  child: Text(l10n.filterClear),
                                ),
                              ],
                            ),
                          )
                        : _TableFrame(
                            enabled: table,
                            withData: {
                              if (shown.any((g) => _filled(g.store)))
                                BoardColumn.store,
                              if (shown.any((g) => _filled(g.size)))
                                BoardColumn.size,
                              if (shown.any(
                                (g) =>
                                    _filled(g.note) ||
                                    _filled(g.requestNote) ||
                                    g.requestedBy != null,
                              ))
                                BoardColumn.note,
                              if (shown.any((g) => _filled(g.url)))
                                BoardColumn.link,
                            },
                            child: ContentListView(
                              controller: _scroll,
                              maxWidth: columnWidth,
                              padding: EdgeInsets.only(
                                bottom: 88 + ref.watch(wishNoticeInsetProvider),
                              ),
                              children: [
                                AnimatedRows(
                                  rows: sections,
                                  deleted: ref.watch(recentlyDeletedProvider),
                                  quiet: fromRemote,
                                  onDeletedGone: (id) => ref
                                      .read(recentlyDeletedProvider.notifier)
                                      .clear(id),
                                ),
                                if (desktop && canAdd && !ownPerson)
                                  _AddGiftInline(
                                    onTap: () => _addGift(person.id),
                                  ),
                              ],
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

  /// La fila de un deseo que nadie ha cogido (o de uno propio).
  Widget _wishRow(
    BuildContext context,
    WishEntry entry,
    AppLocalizations l10n, {
    required bool table,
    required AccentPalette palette,
    required bool columns,
  }) {
    final wish = entry.wish;
    final actions = entry.actions;
    final detail = [
      if (wish.size != null) l10n.giftSizeLine(wish.size!),
      ?wish.description,
    ].join(' · ');
    return Builder(
      builder: (rowContext) => WishRow(
        accent: palette,
        columnsFrom: columns ? kGiftColumnsFrom : null,
        title: wish.title,
        detail: detail.isEmpty ? null : detail,
        // La persona nunca ve estado; quien abre el bloque, que está libre.
        stateText: actions.isOwner || actions.state == null
            ? null
            : l10n.wishAvailableNote,
        actionLabel: actions.canClaim ? l10n.wishClaim : null,
        // El contexto de la fila: si el aviso de un fallo la taparía, la lista
        // sube hasta dejarla a la vista.
        onAction: actions.canClaim
            ? () => claimWishFlow(context, ref, wish, rowContext: rowContext)
            : null,
        onTap: actions.canEdit
            ? () => _editWish(wish)
            : () => openWishDetail(
                context,
                person: wish.recipientId,
                wishId: wish.id,
              ),
        table: table,
      ),
    );
  }

  Widget _row(
    BuildContext context,
    Gift gift,
    Map<String, Giver> givers,
    Map<String, Recipient> people,
    AppLocalizations l10n,
    bool desktop, {
    bool table = false,
    WishPlanRow? planRow,
    String? reader,
  }) {
    final giver = gift.giverId == null ? null : givers[gift.giverId];
    // Un deseo que alguien ha cogido: se marca como deseo y dice en qué
    // punto está (cogido, dos reservas o quitado de la lista).
    final planNote = wishPlanNoteText(l10n, planRow, gift.id, people, reader);
    final planWarning = planRow?.state == WishPlanState.conflictingClaims;
    final by = gift.requestedBy;
    // La web (1.0.6): cambios en un regalo en secreto que el móvil de su
    // persona aún no ha recogido. En el móvil, siempre vacío.
    final pending = ref.read(webPendingSecretGiftIdsProvider).contains(gift.id);
    final requester = switch (by) {
      RequestedByRecipient(:final recipientId) => people[recipientId]?.name,
      RequestedByName(:final name) => name,
      null => null,
    };
    final noteParts = <String>[
      ?planNote,
      if (requester != null) l10n.giftRequestedBy(requester),
      ?gift.requestNote,
      if (gift.size != null) l10n.giftSizeLine(gift.size!),
    ];
    if (table) {
      final noteTable = <String>[
        ?planNote,
        if (requester != null) l10n.giftRequestedBy(requester),
        ?gift.requestNote,
        ?gift.note,
      ];
      return BoardGiftTableRow(
        giftId: gift.id,
        name: gift.title,
        status: gift.status.visualStatus,
        giverName: giverNameFor(l10n, giver),
        giverColorIndex: giver?.colorIndex,
        price: giftPriceText(l10n, gift),
        store: gift.store,
        size: gift.size,
        note: noteTable.isEmpty ? null : noteTable.join(' · '),
        url: gift.url,
        tags: [
          if (planRow != null) l10n.wishTag,
          if (pending) l10n.webSecretsPending,
          // Un deseo cogido lleva solo «Deseo» (QA 1.0.7, m2).
          if (gift.surprise && planRow == null) l10n.giftTagSurprise,
          if (by != null) l10n.giftTagRequest,
        ],
        tagHints: {
          if (pending) l10n.webSecretsPending: l10n.webSecretsPendingLong,
        },
        onTap: () {
          ref.read(boardGiftCursorProvider).set(gift.id);
          _openEditor(gift: gift);
        },
        onStatusTap: () => advanceGiftStatus(context, ref, gift),
        onStatusLongPress: () => showGiftStatusPicker(context, ref, gift),
      );
    }
    final linkHost = gift.url == null ? null : userLinkHost(gift.url!);
    return GiftRow(
      columnsFrom: desktop ? kGiftColumnsFrom : null,
      name: gift.title,
      giverName: giverNameFor(l10n, giver),
      giverColorIndex: giver?.colorIndex,
      status: gift.status.visualStatus,
      price: giftPriceText(l10n, gift),
      note: noteParts.isEmpty ? null : noteParts.join(' · '),
      noteWarning: planWarning,
      tags: [
        if (planRow != null) l10n.wishTag,
        if (pending) l10n.webSecretsPending,
        if (gift.surprise && planRow == null) l10n.giftTagSurprise,
        if (by != null) l10n.giftTagRequest,
      ],
      tagHints: {
        if (pending) l10n.webSecretsPending: l10n.webSecretsPendingLong,
      },
      linkHost: linkHost,
      linkLabel: linkHost == null ? null : '${l10n.giftLinkOpen}: $linkHost',
      onLinkTap: gift.url == null
          ? null
          : () => openGiftLink(context, ref, gift.url!),
      onTap: () => _openEditor(gift: gift),
      onStatusTap: () => advanceGiftStatus(context, ref, gift),
      onStatusLongPress: () => showGiftStatusPicker(context, ref, gift),
    );
  }
}

bool _filled(String? text) => text != null && text.trim().isNotEmpty;

/// Una fila de la lista de la persona: un regalo o un deseo.
class _ListEntry {
  const _ListEntry.gift(Gift this.gift) : wish = null;
  const _ListEntry.wish(WishEntry this.wish) : gift = null;

  final Gift? gift;
  final WishEntry? wish;

  String get title => gift?.title ?? wish!.wish.title;

  String? get occasionId => gift?.occasionId ?? wish?.wish.occasionId;
}

/// Un deseo con la forma de un regalo sin estado propio, solo para pasar los
/// filtros de la lista (ocasión, y los demás como una idea sin asignar).
Gift _wishAsGift(Wish wish) => Gift(
  id: wish.id,
  recipientId: wish.recipientId,
  title: wish.title,
  occasionId: wish.occasionId,
  status: GiftStatus.idea,
  rawStatus: GiftStatus.idea.name,
  size: wish.size,
  surprise: false,
  year: wish.year,
);

/// En la tabla del tablero, las cabeceras de sección van inset 16 por cada
/// lado: su filete y su texto quedan a la altura de los de las filas y del
/// título de la pantalla.
Widget _sectionInset(bool table, Widget child) => table
    ? Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: child)
    : child;

/// El ancho máximo de la tarjeta de gastos sobre la tabla del tablero.
const double _kBudgetCardMax = 1200;

/// El ancho de fila de regalo desde el que el detalle de escritorio pone las
/// filas en columnas.
const double kGiftColumnsFrom = 720;

/// La última fila de la lista de regalos de escritorio: «Añadir regalo» en
/// línea.
class _AddGiftInline extends StatelessWidget {
  const _AddGiftInline({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return Semantics(
      button: true,
      label: l10n.giftAdd,
      excludeSemantics: true,
      onTap: onTap,
      child: PointerSurface(
        radius: BorderRadius.zero,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  StrokeIcon(
                    AppIcons.plus,
                    size: 18,
                    color: t.ink,
                    strokeWidth: 2.2,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    l10n.giftAdd,
                    style: t.styles.label.copyWith(color: t.ink),
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

/// El bloque de una persona sin regalos en el detalle de escritorio: arriba, a
/// la izquierda y a 32 de la cabecera (no flota en el centro del panel). El
/// título, una frase, «Añadir regalo» y sus próximas ocasiones como botones
/// que abren el editor con la ocasión puesta.
class _EmptyPerson extends StatelessWidget {
  const _EmptyPerson({
    required this.name,
    required this.occasions,
    required this.onAdd,
    required this.onAddFor,
  });

  final String name;
  final List<({String id, String label, String date})> occasions;
  final VoidCallback onAdd;
  final ValueChanged<String> onAddFor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 24),
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.giftsEmptyTitle(name),
                  style: t.styles.rowTitle.copyWith(
                    fontSize: 18,
                    height: 24 / 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.giftsEmptyMessage,
                style: t.styles.body.copyWith(color: t.textSecondary),
              ),
              const SizedBox(height: 16),
              DesktopAddGiftButton(onPressed: onAdd),
              if (occasions.isNotEmpty) ...[
                const SizedBox(height: 28),
                Text(l10n.giftsEmptyOccasionsHint, style: t.styles.meta),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final o in occasions)
                      OutlinedButton(
                        onPressed: () => onAddFor(o.id),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(44, 44),
                          foregroundColor: t.text,
                          side: BorderSide(color: t.controlBorder),
                          shape: const RoundedRectangleBorder(
                            borderRadius: RegalosShape.button,
                          ),
                        ),
                        child: Text('${o.label} · ${o.date}'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// El subtítulo de la cabecera («7 años · 4 regalos»), con la cifra de
/// regalos rodando cuando cambia.
class _Subtitle extends StatelessWidget {
  const _Subtitle({
    required this.age,
    required this.count,
    required this.text,
    this.wishText,
  });

  final String? age;
  final int count;
  final String text;

  /// «4 deseos», tras los regalos, o `null` si no hay ninguno sin coger.
  final String? wishText;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    // La primera línea del resumen: «3 años · 10 regalos · 5 deseos», con el
    // separador siempre al final de un trozo y nunca al principio de línea.
    return DotLine(
      style: t.styles.meta,
      parts: [
        if (age != null) DotPart(age!),
        // Sin regalos pero con deseos: solo «4 deseos», sin «Sin regalos ·»
        // (decisión de Daniel, 26-11, QA 1.0.7 m11).
        if (count == 0 && wishText != null)
          DotPart(wishText!)
        else ...[
          DotPart(text, rollValue: count),
          if (wishText != null) DotPart(wishText!),
        ],
      ],
    );
  }
}

/// «Reyes · 2 de 3 comprados», o «Todo comprado para Reyes» cuando la persona
/// está completa. Al completarse, el viejo sale subiendo y el nuevo entra.
class _CompletionLine extends StatelessWidget {
  const _CompletionLine({required this.completion, required this.occasionName});

  final PersonCompletion completion;
  final String occasionName;

  /// «Reyes · 2 de 3 comprados» en dos trozos (la ocasión y la cuenta), para
  /// que, si no cabe, corte entre ellos con el «·» al final del primero.
  Widget _progress(AppLocalizations l10n, RegalosTokens t) {
    final full = l10n.personCompletionProgress(
      occasionName,
      completion.bought,
      completion.total,
    );
    const separator = ' · ';
    final split =
        full.startsWith(occasionName) &&
        full.startsWith(separator, occasionName.length);
    return DotLine(
      style: t.styles.meta,
      parts: split
          ? [
              DotPart(occasionName),
              DotPart(
                full.substring(occasionName.length + separator.length),
                rollValue: completion.bought,
              ),
            ]
          : [
              DotPart(
                full,
                rollValue: completion.bought,
                rollSearchFrom: occasionName.length,
              ),
            ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final done = completion.complete;
    return ValueSwitcher(
      dy: 5,
      child: done
          ? Text(
              l10n.personCompletionDone(occasionName),
              key: const ValueKey('completion-done'),
              style: t.styles.metaStrong.copyWith(
                color: t.ink,
                fontWeight: FontWeight.w600,
              ),
            )
          : KeyedSubtree(
              key: const ValueKey('completion-progress'),
              child: _progress(l10n, t),
            ),
    );
  }
}

/// Hoja con los filtros de ocasión, quién regala y estado.
class _FiltersSheet extends ConsumerStatefulWidget {
  const _FiltersSheet({required this.initial, required this.onChanged});

  final GiftFilter initial;
  final ValueChanged<GiftFilter> onChanged;

  @override
  ConsumerState<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends ConsumerState<_FiltersSheet> {
  late GiftFilter _filter = widget.initial;

  void _set(GiftFilter f) {
    setState(() => _filter = f);
    widget.onChanged(f);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final occasions = ref.watch(occasionsProvider);
    final labels = OccasionLabels(
      l10n,
      ref.watch(familyFullViewProvider).recipientsById,
    );
    final view = ref.watch(familyViewProvider);
    final givers = view.givers;
    // Los adornos de las celdas: un icono, «cualquiera» y «sin».
    ChoiceLeadingBuilder icon(IconData data, double size) =>
        (color, _) => Icon(data, size: size, color: color);
    ChoiceLeadingBuilder any(double size) =>
        icon(Icons.grid_view_outlined, size);
    ChoiceLeadingBuilder none(double size) =>
        icon(Icons.horizontal_rule_rounded, size);
    Widget group(String title) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(header: true, child: Text(title, style: t.styles.label)),
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.filtersSheetTitle,
                style: t.styles.screenTitleSmall,
              ),
            ),
            const SizedBox(height: 12),
            // Tres rejillas como las del editor: una opción por celda, con su
            // adorno delante.
            group(l10n.fieldOccasion),
            ChoiceGrid(
              items: [
                ChoiceGridItem(
                  label: l10n.filterAnyOccasion,
                  leading: any(20),
                  selected: _filter.occasionId == null,
                  onTap: () => _set(_filter.copyWith(clearOccasion: true)),
                ),
                for (final o in occasions)
                  ChoiceGridItem(
                    label: labels.of(o),
                    leading: (color, _) => OccasionKindIcon(
                      o.kind,
                      customIcon: o.icon,
                      size: 20,
                      color: color,
                    ),
                    selected: _filter.occasionId == o.id,
                    onTap: () => _set(_filter.copyWith(occasionId: o.id)),
                  ),
                ChoiceGridItem(
                  label: l10n.giftNoOccasion,
                  leading: none(20),
                  selected: _filter.occasionId == GiftFilter.kNoOccasion,
                  onTap: () => _set(
                    _filter.copyWith(occasionId: GiftFilter.kNoOccasion),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            group(l10n.fieldGiver),
            ChoiceGrid(
              items: [
                ChoiceGridItem(
                  label: l10n.filterAnyGiver,
                  leading: any(20),
                  selected: _filter.giverId == null,
                  onTap: () => _set(_filter.copyWith(clearGiver: true)),
                ),
                for (final g in givers)
                  ChoiceGridItem(
                    label: giverNameFor(l10n, g),
                    leading: (_, _) => SizedBox.square(
                      dimension: 20,
                      child: Center(
                        child: GiverDot(colorIndex: g.colorIndex, size: 12),
                      ),
                    ),
                    selected: view.resolveGiver(_filter.giverId)?.id == g.id,
                    onTap: () => _set(_filter.copyWith(giverId: g.id)),
                  ),
                ChoiceGridItem(
                  label: l10n.giverUnassigned,
                  leading: none(20),
                  selected: _filter.giverId == kUnassignedGiver,
                  onTap: () =>
                      _set(_filter.copyWith(giverId: kUnassignedGiver)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            group(l10n.fieldStatus),
            ChoiceGrid(
              leadingSize: kStatusChoiceGlyph,
              leadingGap: kStatusChoiceGap,
              items: [
                ChoiceGridItem(
                  label: l10n.filterAnyStatus,
                  leading: any(kStatusChoiceGlyph),
                  selected: _filter.status == null,
                  onTap: () => _set(_filter.copyWith(clearStatus: true)),
                ),
                for (final s in GiftStatus.values)
                  statusChoice(
                    l10n,
                    s,
                    selected: _filter.status == s,
                    onTap: () => _set(_filter.copyWith(status: s)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _filter.isActive
                      ? () => _set(const GiftFilter())
                      : null,
                  child: Text(l10n.filterClear),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.actionDone),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// La tabla de regalos del tablero: la cabecera de columnas, fija, y la lista
/// debajo; las dos leen del mismo reparto de columnas, que sale del ancho. Con
/// [enabled] en falso (la lista de siempre) no hace nada.
class _TableFrame extends StatelessWidget {
  const _TableFrame({
    required this.enabled,
    required this.withData,
    required this.child,
  });

  final bool enabled;

  /// Las columnas opcionales de las que alguna fila visible tiene dato.
  final Set<BoardColumn> withData;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return child;
    }
    return LayoutBuilder(
      builder: (context, box) => BoardTableScope(
        columns: BoardTableColumns.forWidth(box.maxWidth, withData: withData),
        child: Column(
          children: [
            const BoardGiftTableHeader(),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
