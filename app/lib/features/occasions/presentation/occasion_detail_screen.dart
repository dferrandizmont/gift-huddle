import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/dates.dart';
import '../../../core/layout/content_gutter.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/motion/animated_rows.dart';
import '../../../core/motion/animated_status_glyph.dart';
import '../../../core/motion/delivered_sweep.dart';
import '../../../core/motion/highlight_flash.dart';
import '../../../core/motion/rolling_number.dart';
import '../../../core/layout/pane_scope.dart';
import '../../../core/layout/two_pane.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/sync/model.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/gift_status.dart' as visual;
import '../../../core/theme/occasion_theme.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/budget_meter.dart';
import '../../../core/widgets/countdown_card.dart';
import '../../../core/widgets/desktop_add_gift_button.dart';
import '../../../core/widgets/gift_status_l10n.dart';
import '../../../core/widgets/gift_status_map.dart';
import '../../../core/widgets/person_avatar.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_checkbox.dart';
import 'occasion_expand_route.dart';
import 'occasion_garland.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_controller.dart';
import '../../family/application/family_providers.dart';
import '../../family/application/gift_logic.dart';
import '../../family/application/remote_change.dart';
import '../../family/domain/next_occasion.dart';
import '../../family/presentation/family_texts.dart';
import '../../family/presentation/occasion_sheet.dart';
import '../../family/presentation/secret_blocks.dart';
import '../../gifts/application/delivered_arm.dart';
import '../../gifts/presentation/gift_actions.dart';
import '../../gifts/presentation/gift_editor_screen.dart';
import '../../settings/presentation/occasion_scope.dart';

/// El tema de una ocasión: el de su tipo (Papá Noel, Tió, Reyes, cumpleaños,
/// Año Nuevo Chino, boda...) o, en una ocasión «Otra», el de su color y su
/// icono.
OccasionTheme occasionThemeFor(Occasion occasion) =>
    OccasionTheme.forOccasion(occasion);

/// Si la ocasión es una de las tres entregas de Navidad, entre las que se
/// reparten los regalos.
bool isChristmasKind(Occasion o) =>
    o.kind == OccasionKind.tio ||
    o.kind == OccasionKind.santa ||
    o.kind == OccasionKind.kings;

/// La vista de una ocasión: cuenta atrás, qué recibe cada persona, lo que
/// falta por envolver y por llegar, y lo pendiente de comprar por tienda.
class OccasionDetailScreen extends ConsumerWidget {
  const OccasionDetailScreen({
    super.key,
    required this.occasionId,
    this.fromPeople = false,
  });

  final String occasionId;

  /// Abierta desde la cuenta atrás de Personas (con `push`): el atrás vuelve
  /// allí y su etiqueta lo dice.
  final bool fromPeople;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final occasion = ref
        .watch(familyFullViewProvider)
        .occasionsById[occasionId];
    final body = _Body(occasionId: occasionId, fromPeople: fromPeople);
    return occasion == null
        ? body
        : OccasionScope(occasion: occasionThemeFor(occasion), child: body);
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.occasionId, required this.fromPeople});

  final String occasionId;
  final bool fromPeople;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  String get occasionId => widget.occasionId;
  bool get fromPeople => widget.fromPeople;

  // Cuál iluminar al guardar un regalo desde esta pantalla.
  final HighlightSignal _highlight = HighlightSignal();

  // Para saber si lo que cambia en las filas llegó de otro móvil.
  int _seenRemote = 0;

  @override
  void dispose() {
    _highlight.dispose();
    super.dispose();
  }

  /// Abre el editor y, al volver, ilumina la fila guardada.
  Future<void> _openEditor({Gift? gift, String? recipientId}) async {
    final saved = await openGiftEditor(
      context,
      gift: gift,
      occasionId: occasionId,
      recipientId: recipientId,
    );
    if (saved != null && mounted) {
      _highlight.highlight(saved);
    }
  }

  void _back(BuildContext context) {
    // Abierto creciendo desde la tarjeta del carrusel: es una ruta del
    // `Navigator` raíz, no de go_router.
    if (OccasionExpandScope.peek(context) != null) {
      Navigator.of(context).pop();
      return;
    }
    context.canPop() ? context.pop() : context.go('/occasions');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final full = ref.watch(familyFullViewProvider);
    // Lo que cambia y llegó de otro móvil entra en silencio.
    final remote = ref.watch(remoteChangeProvider);
    final fromRemote = remote != _seenRemote;
    _seenRemote = remote;
    final view = ref.watch(familyViewProvider);
    final occasion = full.occasionsById[occasionId];
    // En tablet va en una columna de 640 centrada en el panel (o en la
    // ventana, si el detalle creció desde la cuenta atrás de Personas): el
    // margen es relleno de la lista (`ContentListView`). En el panel de
    // detalle de dos paneles, 720 u 880. En el móvil el margen es cero.
    final columnWidth = detailColumnWidth(context);
    // Con dos paneles el detalle es de escritorio: «Añadir regalo» va en la
    // cabecera (sin «+» flotante) y las casillas de resumen, en una fila.
    final panes = PaneScope.roleOf(context) == PaneRole.detail;
    if (occasion == null) {
      return Scaffold(
        body: SafeArea(
          child: ContentWidth(
            maxWidth: columnWidth,
            child: ScreenHeader(
              title: l10n.navOccasions,
              onBack: () => _back(context),
              backLabel: l10n.backTo(
                fromPeople ? l10n.navPeople : l10n.navOccasions,
              ),
            ),
          ),
        ),
      );
    }
    final now = clock.now();
    final locale = l10n.localeName;
    final days = daysUntil(occasion, now);
    final people = view.recipients;
    final peopleById = view.recipientsById;
    final givers = view.giversById;
    final mine = [
      for (final g in view.gifts)
        if (g.occasionId == occasion.id &&
            peopleById.containsKey(g.recipientId))
          g,
    ];
    final birthdayPerson = occasion.kind == OccasionKind.birthday
        ? peopleById[occasion.recipientId]
        : null;

    // Las tres entregas de Navidad, por orden del calendario de la fiesta.
    final group = isChristmasKind(occasion)
        ? ([
            for (final o in view.occasions)
              if (isChristmasKind(o) && !o.archived) o,
          ]..sort(
            (a, b) => ((a.month == 1 ? 13 : a.month) * 100 + a.day).compareTo(
              (b.month == 1 ? 13 : b.month) * 100 + b.day,
            ),
          ))
        : <Occasion>[];

    final toWrap = mine.where(needsWrapping).length;
    final toArrive = mine.where((g) => g.status == GiftStatus.bought).length;
    final decided = mine.where((g) => g.status == GiftStatus.decided).toList();
    final ideas = mine.where((g) => g.status == GiftStatus.idea).toList();
    // Quien tiene regalos en secreto que este móvil no ve no sale con cifras:
    // lleva el bloque fijo, en esta y en cualquier ocasión.
    final locked = ref.watch(lockedPeopleProvider);
    final lockedPeople = [
      for (final p in people)
        if (locked.contains(p.id)) p,
    ];
    // Con dos paneles, una ocasión sin regalos no enseña ceros ni secciones
    // vacías: un bloque arriba, a la izquierda, con lo que hacer. Si hay
    // personas en secreto, la ocasión no está vacía a la vista: lleva sus
    // bloques.
    final bare = mine.isEmpty && lockedPeople.isEmpty;

    // Pendiente de comprar, agrupado por tienda (sin tienda, al final).
    final byStore = <String, List<Gift>>{};
    for (final g in decided) {
      byStore.putIfAbsent(g.store?.trim() ?? '', () => <Gift>[]).add(g);
    }
    final stores = byStore.keys.toList()
      ..sort((a, b) {
        if (a.isEmpty != b.isEmpty) {
          return a.isEmpty ? 1 : -1;
        }
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    final dayMonth = occasionDayMonth(occasion, now);
    final dateText = longDayMonth(dayMonth.month, dayMonth.day, locale);
    final subtitle = birthdayPerson == null
        ? dateText
        : [
            dateText,
            [
              birthdayPerson.name,
              ?ageText(l10n, birthdayPerson, now),
            ].join(', '),
          ].join(' · ');

    final editButton = Semantics(
      button: true,
      label: l10n.occasionEdit,
      excludeSemantics: true,
      onTap: () => _edit(context, occasion),
      child: Tooltip(
        message: l10n.occasionEdit,
        excludeFromSemantics: true,
        child: SizedBox.square(
          dimension: 44,
          child: InkResponse(
            onTap: () => _edit(context, occasion),
            child: Center(
              child: StrokeIcon(AppIcons.edit, size: 22, color: t.text),
            ),
          ),
        ),
      ),
    );

    // Personas con regalos en la ocasión (y, en un cumpleaños, la propia).
    final shownPeople = [
      for (final p in people)
        if (!locked.contains(p.id) &&
            (mine.any((g) => g.recipientId == p.id) ||
                birthdayPerson?.id == p.id))
          p,
    ];

    // Los bloques entran de arriba abajo una sola vez por visita (§1.6). Si el
    // detalle crece desde la tarjeta del carrusel (momento K), la cabecera
    // (flecha, títulos, guirnalda y cuenta atrás) no se escalona: la pone el
    // vuelo, y las filas empiezan al 30 % de la ruta, a 24 ms entre bloques.
    final expand = OccasionExpandScope.maybeOf(context);
    final grows = expand != null && !expand.route.reduce;
    var order = 0;
    Widget block(Widget child) => StaggerItem(index: order++, child: child);
    Widget head(Widget child) => grows ? child : block(child);

    Scaffold scaffold({required bool flying}) {
      // Se llama una vez por fotograma de estado (`flying` cambia al acabar el
      // viaje): los bloques conservan su orden.
      order = 0;
      return Scaffold(
        // Mientras el detalle crece, el fondo lo pone el vuelo.
        backgroundColor: flying ? Colors.transparent : null,
        // El «+» se queda a 16 del borde derecho de la columna, no del panel.
        floatingActionButton: flying || panes
            ? null
            : ContentFloatingButton(
                maxWidth: columnWidth,
                child: FloatingActionButton(
                  tooltip: l10n.giftAdd,
                  onPressed: () => _openEditor(recipientId: birthdayPerson?.id),
                  child: StrokeIcon(
                    AppIcons.plus,
                    size: 26,
                    color: t.onFill,
                    strokeWidth: 2.4,
                  ),
                ),
              ),
        body: StaggerScope(
          // En dos paneles el detalle ya cambia con su propio eje: no repite
          // la entrada escalonada.
          animate: PaneScope.roleOf(context) != PaneRole.detail,
          delay: grows ? const Duration(milliseconds: 110) : Duration.zero,
          child: SafeArea(
            bottom: false,
            child: ContentListView(
              maxWidth: columnWidth,
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                OccasionExpandReveal(
                  child: ScreenHeader(
                    eyebrow: l10n.navOccasions,
                    title: occasionTitle(
                      l10n,
                      occasion,
                      personName: birthdayPerson?.name,
                    ),
                    subtitle: subtitle,
                    onBack: () => _back(context),
                    // Abierto creciendo desde la cuenta atrás de Personas es
                    // una pantalla encima, aunque ocupe el panel de detalle:
                    // la flecha es la salida.
                    keepBackInPane: expand != null,
                    backLabel: l10n.backTo(
                      fromPeople ? l10n.navPeople : l10n.navOccasions,
                    ),
                    actions: [
                      if (panes)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: DesktopAddGiftButton(
                            key: const ValueKey<String>('add-gift-header'),
                            onPressed: () =>
                                _openEditor(recipientId: birthdayPerson?.id),
                          ),
                        ),
                      editButton,
                    ],
                  ),
                ),
                if (GarlandMotif.forTheme(t.occasion) case final motif?)
                  head(
                    OccasionExpandReveal(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: DrawnGarland(motif: motif, tokens: t),
                      ),
                    ),
                  )
                else if (t.ornament != null)
                  head(OccasionExpandReveal(child: _Ornament(tokens: t))),
                head(
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: days == null
                        ? Text(l10n.occasionPassed, style: t.styles.body)
                        : CountdownCard(
                            days: days,
                            title: countdownTitleFor(
                              l10n,
                              occasion,
                              days,
                              peopleById,
                            ),
                            date: l10n.todayShort(now),
                            size: occasion.kind == OccasionKind.birthday
                                ? CountdownSize.large
                                : CountdownSize.medium,
                            flight: expand?.flight,
                          ),
                  ),
                ),
                if (bare)
                  block(
                    _NoGiftsBlock(
                      // En el móvil ya está el «+» flotante.
                      onAdd: panes
                          ? () => _openEditor(recipientId: birthdayPerson?.id)
                          : null,
                    ),
                  )
                else
                  block(
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: panes
                          ? _SummaryTiles(
                              ideas: ideas.length,
                              decided: decided.length,
                              toArrive: toArrive,
                              toWrap: toWrap,
                            )
                          // Las dos casillas en una fila, de 300 como mucho
                          // cada una: en una columna ancha no se estiran.
                          : Row(
                              children: [
                                Flexible(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 300,
                                    ),
                                    child: _StatCard(
                                      glyph: visual.GiftStatus.wrapped,
                                      count: toWrap,
                                      label: l10n.occasionToWrap,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 300,
                                    ),
                                    child: _StatCard(
                                      glyph: visual.GiftStatus.bought,
                                      count: toArrive,
                                      label: l10n.occasionToArrive,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                if (!bare) ...[
                  block(
                    SectionHeader(
                      title: l10n.occasionPeopleSection,
                      trailing: null,
                      bordered: false,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    ),
                  ),
                  if (group.length > 1)
                    block(
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 4,
                          children: [
                            for (var i = 0; i < group.length; i++)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: _segmentColor(t, i, group.length),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    occasionTitle(l10n, group[i]),
                                    style: t.styles.caption,
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (shownPeople.isEmpty && lockedPeople.isEmpty)
                    block(
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Text(l10n.occasionNoGifts, style: t.styles.meta),
                      ),
                    ),
                  AnimatedRows(
                    key: const ValueKey('people-rows'),
                    quiet: fromRemote,
                    rows: [
                      for (final p in shownPeople)
                        AnimatedRowItem(
                          id: 'person-${p.id}',
                          child: StaggerItem(
                            index: order++,
                            child: _PersonBlock(
                              person: p,
                              gifts: [
                                for (final g in mine)
                                  if (g.recipientId == p.id) g,
                              ],
                              group: group,
                              allGifts: view.gifts,
                              givers: givers,
                              highlight: _highlight,
                              fromRemote: fromRemote,
                              onOpen: (g) => _openEditor(gift: g),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (lockedPeople.isNotEmpty)
                    block(
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: SecretBlockList(people: lockedPeople),
                      ),
                    ),
                  block(
                    SectionHeader(
                      title: l10n.occasionPendingBuySection,
                      trailing: l10n.giftCount(decided.length),
                      bordered: false,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    ),
                  ),
                  if (decided.isEmpty)
                    block(
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Text(
                          l10n.occasionPendingEmpty,
                          style: t.styles.meta,
                        ),
                      ),
                    ),
                  // Lo pendiente de comprar, por tienda: al marcar uno como comprado
                  // su fila se pliega, y la tienda que se queda vacía con ella.
                  AnimatedRows(
                    key: const ValueKey('buy-rows'),
                    quiet: fromRemote,
                    // Al marcar uno como comprado, la fila enseña su casilla ya
                    // barrida y luego se pliega.
                    exitChildren: {
                      for (final g in mine)
                        if (g.status != GiftStatus.decided)
                          g.id: StaggerItem(
                            index: 0,
                            child: _GiftFx(
                              gift: g,
                              person: peopleById[g.recipientId],
                              highlight: _highlight,
                              reveal: false,
                              sweep: false,
                              child: _BuyRow(
                                gift: g,
                                person: peopleById[g.recipientId]?.name ?? '',
                                onOpen: () => _openEditor(gift: g),
                              ),
                            ),
                          ),
                    },
                    rows: [
                      for (final store in stores) ...[
                        AnimatedRowItem(
                          id: 'store-$store',
                          child: StaggerItem(
                            index: order++,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                              child: Semantics(
                                header: true,
                                child: Text(
                                  store.isEmpty
                                      ? l10n.occasionStoreNone
                                      : store,
                                  style: t.styles.label.copyWith(color: t.ink),
                                ),
                              ),
                            ),
                          ),
                        ),
                        for (final g in byStore[store]!)
                          AnimatedRowItem(
                            id: g.id,
                            child: StaggerItem(
                              index: order++,
                              child: _GiftFx(
                                gift: g,
                                person: peopleById[g.recipientId],
                                highlight: _highlight,
                                // La fila de abajo ya la lleva al verla; la
                                // copia de la persona es la que se enseña.
                                reveal: false,
                                sweep: false,
                                child: _BuyRow(
                                  gift: g,
                                  person: peopleById[g.recipientId]?.name ?? '',
                                  onOpen: () => _openEditor(gift: g),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                  AnimatedRows(
                    key: const ValueKey('idea-rows'),
                    quiet: fromRemote,
                    exitChildren: {
                      for (final g in mine)
                        if (g.status != GiftStatus.idea)
                          g.id: StaggerItem(
                            index: 0,
                            child: _GiftFx(
                              gift: g,
                              person: peopleById[g.recipientId],
                              highlight: _highlight,
                              reveal: false,
                              sweep: false,
                              child: _IdeaRow(
                                gift: g,
                                person: peopleById[g.recipientId]?.name ?? '',
                                giver: givers[g.giverId],
                                onOpen: () => _openEditor(gift: g),
                              ),
                            ),
                          ),
                    },
                    rows: [
                      if (ideas.isNotEmpty)
                        AnimatedRowItem(
                          id: 'ideas-header',
                          child: StaggerItem(
                            index: order++,
                            child: SectionHeader(
                              title: l10n.occasionIdeasSection,
                              trailing: l10n.giftCount(ideas.length),
                              bordered: false,
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                            ),
                          ),
                        ),
                      for (final g in ideas)
                        AnimatedRowItem(
                          id: g.id,
                          child: StaggerItem(
                            index: order++,
                            child: _GiftFx(
                              gift: g,
                              person: peopleById[g.recipientId],
                              highlight: _highlight,
                              reveal: false,
                              sweep: false,
                              child: _IdeaRow(
                                gift: g,
                                person: peopleById[g.recipientId]?.name ?? '',
                                giver: givers[g.giverId],
                                onOpen: () => _openEditor(gift: g),
                              ),
                            ),
                          ),
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

    if (expand == null) {
      return scaffold(flying: false);
    }
    return ValueListenableBuilder<bool>(
      valueListenable: expand.flying,
      builder: (context, flying, _) => scaffold(flying: flying),
    );
  }

  Future<void> _edit(BuildContext context, Occasion occasion) async {
    final l10n = AppLocalizations.of(context);
    final people = ref.read(familyFullViewProvider).recipientsById;
    final result = await showOccasionSheet(
      context,
      initial: occasion,
      initialName: OccasionLabels(l10n, people).of(occasion),
    );
    if (result != null) {
      await ref.read(familyControllerProvider.notifier).upsertOccasion(result);
    }
  }
}

/// Color de cada tramo del reparto: del pastel del acento a su tinta.
Color _segmentColor(RegalosTokens t, int index, int count) {
  final f = count <= 1 ? 1.0 : index / (count - 1);
  return Color.lerp(t.fill, t.ink, f * 0.9 + 0.1)!;
}

class _Ornament extends StatelessWidget {
  const _Ornament({required this.tokens});

  final RegalosTokens tokens;

  @override
  Widget build(BuildContext context) {
    final line = tokens.ornamentLine ?? tokens.separator;
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(
          children: [
            Expanded(child: Container(height: 1, color: line)),
            const SizedBox(width: 10),
            Transform.rotate(
              angle: 0.785398,
              child: Container(width: 8, height: 8, color: tokens.ornament),
            ),
            const SizedBox(width: 6),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: tokens.ornamentAlt,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Container(height: 1, color: line)),
          ],
        ),
      ),
    );
  }
}

/// Una ocasión sin regalos: arriba, a la izquierda y a 32 px de la cabecera
/// (no flotando en el centro), con la frase y, en dos paneles, el botón (en el
/// móvil ya está el «+» flotante).
class _NoGiftsBlock extends StatelessWidget {
  const _NoGiftsBlock({required this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 0),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.occasionNoGifts, style: t.styles.body),
              if (onAdd != null) ...[
                const SizedBox(height: 12),
                DesktopAddGiftButton(onPressed: onAdd!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Las cuatro casillas de resumen del detalle de dos paneles, en una fila que
/// llena la columna (de la idea a lo que falta por envolver): idea, decidido,
/// por llegar y por envolver. Si la columna es estrecha (menos de 600), dos
/// filas de dos.
class _SummaryTiles extends StatelessWidget {
  const _SummaryTiles({
    required this.ideas,
    required this.decided,
    required this.toArrive,
    required this.toWrap,
  });

  final int ideas;
  final int decided;
  final int toArrive;
  final int toWrap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String lower(String s) => s.toLowerCase();
    final tiles = [
      _StatCard(
        key: const ValueKey('tile-ideas'),
        glyph: visual.GiftStatus.idea,
        count: ideas,
        label: lower(l10n.statusIdea),
      ),
      _StatCard(
        key: const ValueKey('tile-decided'),
        glyph: visual.GiftStatus.decided,
        count: decided,
        label: lower(l10n.statusDecided),
      ),
      _StatCard(
        key: const ValueKey('tile-arrive'),
        glyph: visual.GiftStatus.bought,
        count: toArrive,
        label: l10n.occasionToArrive,
      ),
      _StatCard(
        key: const ValueKey('tile-wrap'),
        glyph: visual.GiftStatus.wrapped,
        count: toWrap,
        label: l10n.occasionToWrap,
      ),
    ];
    Widget row(List<Widget> items) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: items[i]),
          ],
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= 600
          ? row(tiles)
          : Column(
              children: [
                row(tiles.sublist(0, 2)),
                const SizedBox(height: 10),
                row(tiles.sublist(2)),
              ],
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    super.key,
    required this.glyph,
    required this.count,
    required this.label,
  });

  final visual.GiftStatus glyph;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Semantics(
      container: true,
      label: '$count $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: RegalosShape.card,
        ),
        child: Row(
          children: [
            StatusGlyph(status: glyph, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RollingNumber(
                    value: count,
                    style: t.styles.stat.copyWith(fontSize: 22, height: 1.1),
                  ),
                  Text(label, style: t.styles.meta),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonBlock extends ConsumerWidget {
  const _PersonBlock({
    required this.person,
    required this.gifts,
    required this.group,
    required this.allGifts,
    required this.givers,
    required this.highlight,
    required this.fromRemote,
    required this.onOpen,
  });

  final Recipient person;
  final List<Gift> gifts;
  final List<Occasion> group;
  final List<Gift> allGifts;
  final Map<String, Giver> givers;

  /// Por dónde llega el aviso de iluminar una fila.
  final HighlightSignal highlight;

  /// Si lo que cambia llegó de otro móvil (las filas entran en silencio).
  final bool fromRemote;

  /// Abre el editor de un regalo.
  final ValueChanged<Gift> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final counts = [
      for (final o in group)
        allGifts
            .where((g) => g.recipientId == person.id && g.occasionId == o.id)
            .length,
    ];
    final total = counts.fold<int>(0, (a, b) => a + b);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.separator)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PersonAvatar(
                name: person.name,
                colorIndex: person.colorIndex,
                size: 34,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  person.name,
                  style: t.styles.rowTitle.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(l10n.giftCount(gifts.length), style: t.styles.meta),
            ],
          ),
          const SizedBox(height: 4),
          if (gifts.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 44, top: 2, bottom: 6),
              child: Text(l10n.occasionNoGiftsYet, style: t.styles.meta),
            ),
          // Un regalo que llega a la persona se despliega; uno que se borra se
          // pliega. La casilla va de un estado al siguiente con su barrido.
          AnimatedRows(
            key: const ValueKey('gift-rows'),
            quiet: fromRemote,
            rows: [
              for (final g in gifts)
                AnimatedRowItem(
                  id: g.id,
                  child: _GiftFx(
                    gift: g,
                    person: person,
                    highlight: highlight,
                    child: Semantics(
                      container: true,
                      button: true,
                      label:
                          '${g.title}. ${giverNameFor(l10n, givers[g.giverId])}. '
                          '${g.status.visualStatus.label(l10n)}',
                      excludeSemantics: true,
                      onTap: () => onOpen(g),
                      child: InkWell(
                        onTap: () => onOpen(g),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 44),
                          child: Row(
                            children: [
                              const SizedBox(width: 44),
                              AnimatedStatusGlyph(
                                status: g.status.visualStatus,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(g.title, style: t.styles.body),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (group.length > 1 && total > 0) ...[
            const SizedBox(height: 4),
            Semantics(
              container: true,
              label: l10n.occasionSplitLabel(
                person.name,
                [
                  for (var i = 0; i < group.length; i++)
                    '${occasionTitle(l10n, group[i])} ${counts[i]}',
                ].join(', '),
              ),
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.only(left: 44),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          for (var i = 0; i < group.length; i++)
                            if (counts[i] > 0) ...[
                              if (i > 0 && counts.take(i).any((c) => c > 0))
                                const SizedBox(width: 2),
                              Expanded(
                                flex: counts[i],
                                child: Container(
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: _segmentColor(t, i, group.length),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(counts.join(' · '), style: t.styles.meta),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
          ] else if (gifts.isNotEmpty) ...[
            // Una sola ocasión: cuántos de sus regalos están comprados.
            Padding(
              padding: const EdgeInsets.fromLTRB(44, 6, 0, 4),
              child: BudgetBar(
                fraction:
                    gifts.where((g) => !needsBuying(g)).length / gifts.length,
                semanticLabel: l10n.occasionGiftsBought(
                  gifts.where((g) => !needsBuying(g)).length,
                  gifts.length,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BuyRow extends ConsumerWidget {
  const _BuyRow({
    required this.gift,
    required this.person,
    required this.onOpen,
  });

  final Gift gift;
  final String person;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    // Marcar como comprado es lo mismo que tocar su casilla en la lista de la
    // persona: avanza de estado con su toque (que llega cuando la casilla
    // termina de barrer), el aviso con «Deshacer» y la fila se pliega.
    void buy() => advanceGiftStatus(context, ref, gift);

    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.only(left: 4, right: 16),
      child: Row(
        children: [
          Semantics(
            container: true,
            button: true,
            label: l10n.occasionMarkBought(gift.title),
            excludeSemantics: true,
            onTap: buy,
            child: SizedBox.square(
              dimension: 44,
              child: InkResponse(
                onTap: buy,
                customBorder: const CircleBorder(),
                child: Center(
                  child: AnimatedStatusGlyph(
                    status: gift.status.visualStatus,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: LongPressAfter(
              duration: kStatusLongPress,
              onLongPress: () => showGiftStatusPicker(context, ref, gift),
              child: InkWell(
                onTap: onOpen,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(child: Text(gift.title, style: t.styles.body)),
                      const SizedBox(width: 8),
                      Text(person, style: t.styles.meta),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IdeaRow extends ConsumerWidget {
  const _IdeaRow({
    required this.gift,
    required this.person,
    required this.onOpen,
    this.giver,
  });

  final Gift gift;
  final String person;
  final Giver? giver;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = RegalosTokens.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.only(left: 4, right: 16),
      child: Row(
        children: [
          StatusCheckbox(
            status: gift.status.visualStatus,
            itemName: gift.title,
            onTap: () => advanceGiftStatus(context, ref, gift),
            onLongPress: () => showGiftStatusPicker(context, ref, gift),
          ),
          Expanded(
            child: LongPressAfter(
              duration: kStatusLongPress,
              onLongPress: () => showGiftStatusPicker(context, ref, gift),
              child: InkWell(
                onTap: onOpen,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(child: Text(gift.title, style: t.styles.body)),
                      const SizedBox(width: 8),
                      Text(person, style: t.styles.meta),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lo que se ve de un regalo al cambiar: el destello de «guardado» (con su
/// banda de luz) y la luz que barre la fila al entregarlo, ambos con el
/// pastel de su persona.
class _GiftFx extends ConsumerWidget {
  const _GiftFx({
    required this.gift,
    required this.person,
    required this.highlight,
    required this.child,
    this.reveal = true,
    this.sweep = true,
  });

  final Gift gift;
  final Recipient? person;
  final HighlightSignal highlight;
  final Widget child;

  /// Si el destello lleva la lista hasta la fila (solo en una copia por
  /// regalo: el regalo sale en el bloque de su persona y en «Por comprar» o
  /// «Ideas»).
  final bool reveal;

  /// Si la fila da luz al entregarse (solo en una copia, para no gastar el
  /// armado dos veces).
  final bool sweep;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = RegalosTokens.of(context);
    final palette = personPalette(person?.colorIndex ?? 0);
    final pastel = t.isDark ? palette.tintD : palette.pastel;
    return HighlightFlash(
      id: gift.id,
      signal: highlight,
      color: pastel,
      reveal: reveal,
      child: sweep
          ? DeliveredSweep(
              delivered: gift.status == GiftStatus.delivered,
              consumeArm: () =>
                  ref.read(deliveredArmsProvider).consume(gift.id),
              color: pastel,
              child: child,
            )
          : child,
    );
  }
}
