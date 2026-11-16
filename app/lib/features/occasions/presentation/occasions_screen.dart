import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/dates.dart';
import '../../../core/layout/content_gutter.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/layout/pane_selection.dart';
import '../../../core/layout/pane_workspace.dart';
import '../../../core/layout/two_pane.dart';
import '../../../core/layout/window_class.dart';
import '../../../core/motion/animated_rows.dart';
import '../../../core/motion/highlight_flash.dart';
import '../../../core/motion/move_slide.dart';
import '../../../core/motion/rolling_number.dart';
import '../../../core/motion/shared_axis_switcher.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/motion/state_switcher.dart';
import '../../../core/motion/value_switcher.dart';
import '../../../core/sync/model.dart';
import '../../../core/theme/occasion_theme.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/header_button.dart';
import '../../../core/widgets/pane_list_row.dart';
import '../../../core/widgets/pointer_surface.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/settings_row.dart';
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
import '../../settings/application/appearance_provider.dart';
import '../../gifts/presentation/add_gift_button.dart';
import '../../gifts/presentation/gift_editor_screen.dart';
import '../application/occasion_rows.dart';
import 'budget_screen.dart';
import 'occasion_detail_screen.dart';
import 'occasion_garland.dart';

/// Lo que se ve en la pestaña Ocasiones, según la ventana.
///
/// - Con un panel y sin [selected] (`/occasions`): la lista de ocasiones.
/// - Con un panel y [selected] (`/occasions/:id` o `/occasions/budget`): el
///   detalle de la ocasión o el presupuesto.
/// - Con dos paneles: la lista a la izquierda, con la fila elegida marcada con
///   el pastel del acento (el recuadro viaja de una fila a otra), y a la
///   derecha el detalle, sin flecha de volver. «Presupuesto» es una fila más.
///   La elegida es la de la URL o, en `/occasions`, la última abierta o la
///   próxima ocasión.
///
/// El tema de color de la ocasión solo tiñe el panel de detalle.
class OccasionsWorkspace extends ConsumerWidget {
  /// Crea la pestaña.
  const OccasionsWorkspace({super.key, this.selected, this.fromPeople = false});

  /// La fila de la URL: el id de una ocasión o [kBudgetRowId].
  final String? selected;

  /// Si se llegó desde la cuenta atrás de Personas.
  final bool fromPeople;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final occasions = ref.watch(occasionsProvider);
    final panes = WindowClass.of(context).usesTwoPanes && occasions.isNotEmpty;
    final selection = ref.read(paneSelectionProvider);
    final now = clock.now();
    final ids = occasionRowIds(occasions, now);
    final String? shown;
    if (panes) {
      final id = selected;
      final last = selection.lastOf(PaneTab.occasions);
      shown = id != null && ids.contains(id)
          ? id
          : (last != null && ids.contains(last)
                ? last
                : nextOccasionRowId(occasions, now));
    } else {
      shown = selected;
    }
    final index = shown == null ? 0 : ids.indexOf(shown);

    void step(int delta) {
      final current = shown == null ? -1 : ids.indexOf(shown);
      final next = (current + delta).clamp(0, ids.length - 1);
      if (next == current) {
        return;
      }
      selection.choose(PaneTab.occasions, ids[next]);
      context.go('${PaneTab.occasions.root}/${ids[next]}');
    }

    return PaneRootGuard(
      panes: panes,
      routed: selected != null,
      exitOnBack: !fromPeople,
      child: PaneKeyboard(
        enabled: panes,
        onStep: step,
        onNew: (sheetContext) {
          final id = shown;
          if (id == null) {
            return;
          }
          unawaited(
            id == kBudgetRowId
                ? openGiftEditor(sheetContext, chooseRecipient: true)
                : openGiftEditor(sheetContext, occasionId: id),
          );
        },
        child: TwoPane(
          panes: panes,
          entrance: () => selection.takeEntrance(PaneTab.occasions),
          list: panes || selected == null
              ? PageStorage(
                  bucket: selection.listBucket,
                  child: OccasionsScreen(
                    selectedId: panes ? shown : null,
                    panes: panes,
                  ),
                )
              : null,
          detail: shown == null
              ? null
              : SharedAxisSwitcher(
                  index: index,
                  childKey: shown,
                  animate: panes,
                  fadeOnly: true,
                  child: shown == kBudgetRowId
                      ? const BudgetScreen()
                      : OccasionDetailScreen(
                          key: ValueKey('/occasions/$shown'),
                          occasionId: shown,
                          fromPeople: fromPeople,
                        ),
                ),
        ),
      ),
    );
  }
}

/// El panel de lista de Ocasiones: el presupuesto de la casa y las fechas del
/// año por orden, cada una con sus días y sus regalos.
///
/// Con [panes] marca la fila de [selectedId] con el pastel del acento, tocar
/// una cambia la URL en vez de apilar y no lleva «Añadir regalo» (lo lleva el
/// detalle).
class OccasionsScreen extends ConsumerStatefulWidget {
  /// Crea la lista.
  const OccasionsScreen({super.key, this.selectedId, this.panes = false});

  /// La fila elegida, si hay dos paneles: una ocasión o [kBudgetRowId].
  final String? selectedId;

  /// Si es el panel de lista de dos paneles.
  final bool panes;

  @override
  ConsumerState<OccasionsScreen> createState() => _OccasionsScreenState();
}

class _OccasionsScreenState extends ConsumerState<OccasionsScreen> {
  String? get selectedId => widget.selectedId;
  bool get panes => widget.panes;

  // Para saber si lo que cambia en la lista llegó de otro móvil.
  int _seenRemote = 0;

  // Qué fila iluminar con suavidad al llegar a su nuevo puesto.
  final HighlightSignal _moved = HighlightSignal();

  @override
  void dispose() {
    _moved.dispose();
    super.dispose();
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final result = await showOccasionSheet(context);
    if (result != null) {
      await ref.read(familyControllerProvider.notifier).upsertOccasion(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final occasions = ref.watch(occasionsProvider);
    final view = ref.watch(familyViewProvider);
    final labels = OccasionLabels(
      l10n,
      ref.watch(familyFullViewProvider).recipientsById,
    );
    final now = clock.now();
    final ordered = occasionsByNextDate(occasions, now);

    final addButton = HeaderIconButton(
      icon: AppIcons.plus,
      label: l10n.occasionNew,
      onTap: () => _add(context, ref),
    );
    final celebrations = [
      for (final o in ordered)
        if (o.kind != OccasionKind.birthday) o,
    ];
    final birthdays = [
      for (final o in ordered)
        if (o.kind == OccasionKind.birthday) o,
    ];

    // Los bloques entran de arriba abajo una sola vez por visita (§1.6): la
    // fila del presupuesto, y luego cada cabecera de grupo y cada ocasión,
    // con la clave de su id. Las ocasiones viven en `AnimatedRows`: una que se
    // crea se despliega, una que se borra se pliega y una que cambia de fecha
    // se desliza hasta su nuevo puesto (`MoveSlide`).
    var order = 0;
    var slot = 0;
    List<AnimatedRowItem> group(
      String id,
      String title,
      List<Occasion> list, {
      required bool first,
    }) => [
      AnimatedRowItem(
        id: 'group-$id',
        child: MoveSlide(
          slot: slot++,
          child: RepaintBoundary(
            child: StaggerItem(
              index: order++,
              child: SectionHeader(
                title: title,
                trailing: '${list.length}',
                bordered: false,
                padding: EdgeInsets.fromLTRB(16, first ? 14 : 12, 16, 8),
              ),
            ),
          ),
        ),
      ),
      for (final o in list)
        AnimatedRowItem(
          id: o.id,
          // Al cambiar de puesto (su fecha cambió), la fila viaja y, si el
          // destino queda fuera de la vista, la lista la sigue y la ilumina
          // con suavidad al llegar.
          child: MoveSlide(
            slot: slot++,
            onMoved: () => _moved.highlight(o.id),
            child: RepaintBoundary(
              child: HighlightFlash(
                id: o.id,
                signal: _moved,
                color: t.soft,
                withSheen: false,
                child: StaggerItem(
                  index: order++,
                  child: _OccasionRow(
                    occasion: o,
                    title: labels.of(o),
                    giftCountValue: view.gifts
                        .where((g) => g.occasionId == o.id)
                        .length,
                    now: now,
                    panes: panes,
                    selected: panes && o.id == selectedId,
                  ),
                ),
              ),
            ),
          ),
        ),
    ];
    // Lo que cambia y llegó de otro móvil entra en silencio.
    final remote = ref.watch(remoteChangeProvider);
    final fromRemote = remote != _seenRemote;
    _seenRemote = remote;

    // El recuadro de la fila elegida lleva el color de su ocasión (con los
    // temas de ocasión activos); el de «Presupuesto», el del acento.
    final themed = ref.watch(
      appearanceProvider.select((a) => a.occasionThemes),
    );
    final selectedOccasion = panes && themed
        ? occasions.where((o) => o.id == selectedId).firstOrNull
        : null;
    final selectionPalette = selectedOccasion == null
        ? null
        : OccasionTheme.forOccasion(selectedOccasion).palette;

    void openBudget() {
      if (panes) {
        ref.read(paneSelectionProvider).choose(PaneTab.occasions, kBudgetRowId);
      }
      context.go('/occasions/budget');
    }

    final budgetRow = SettingsRow(
      title: l10n.budgetCardTitle,
      hint: l10n.budgetCardHint,
      // Con dos paneles, fila plana como las demás: sin flecha ni filete.
      chevron: !panes,
      bordered: !panes,
      selected: panes && selectedId == kBudgetRowId,
      onTap: openBudget,
    );

    // En tablet, una columna de 640 centrada en el panel: la lista lleva el
    // margen como relleno (se sigue desplazando al arrastrar por los lados).
    // En el móvil el margen es cero.
    return AddGiftFabScope(
      child: Scaffold(
        // Apuntar un regalo sin ir antes a la persona. Con dos paneles, el botón
        // es el del detalle (para esa ocasión).
        floatingActionButton: occasions.isEmpty || panes
            ? null
            : const AddGiftButton(),
        body: StaggerScope(
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                ContentWidth(
                  maxWidth: RegalosLayout.listColumn,
                  child: ScreenHeader(
                    title: l10n.navOccasions,
                    actions: [addButton],
                  ),
                ),
                Expanded(
                  child: StateSwitcher(
                    stateKey: occasions.isEmpty ? 'empty' : 'list',
                    child: occasions.isEmpty
                        ? EmptyState(
                            icon: AppIcons.occasions,
                            title: l10n.emptyOccasionsTitle,
                            message: l10n.emptyOccasionsMessage,
                          )
                        : ContentListView(
                            maxWidth: RegalosLayout.listColumn,
                            storageKey: const PageStorageKey<String>(
                              'occasions-list',
                            ),
                            padding: EdgeInsets.only(
                              top: 8,
                              bottom: addGiftButtonClearance(context),
                            ),
                            children: [
                              // El recuadro de la fila elegida viaja por detrás
                              // de las filas; las filas elegidas dejan su fondo
                              // transparente.
                              SelectionScope(
                                selectedId: panes ? selectedId : null,
                                // En oscuro, el 12 % del color de la ocasión (como
                                // el ratón) y su borde: el tono apagado se perdía
                                // sobre la banda de la lista.
                                fill: selectionPalette == null
                                    ? t.soft
                                    : (t.isDark
                                          ? selectionPalette.tintaD.withValues(
                                              alpha: 0.12,
                                            )
                                          : selectionPalette.pastel),
                                border: selectionPalette == null
                                    ? t.ink
                                    : (t.isDark
                                          ? selectionPalette.tintaD
                                          : selectionPalette.tinta),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    StaggerItem(
                                      index: order++,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          border: panes
                                              ? null
                                              : Border(
                                                  top: BorderSide(
                                                    color: t.separator,
                                                  ),
                                                ),
                                        ),
                                        child: panes
                                            ? Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: kPaneRowInset,
                                                    ),
                                                child: SelectionRow(
                                                  id: kBudgetRowId,
                                                  child: budgetRow,
                                                ),
                                              )
                                            : budgetRow,
                                      ),
                                    ),
                                    AnimatedRows(
                                      quiet: fromRemote,
                                      rows: [
                                        if (celebrations.isNotEmpty)
                                          ...group(
                                            'celebrations',
                                            l10n.occasionsGroupCelebrations,
                                            celebrations,
                                            first: true,
                                          ),
                                        if (birthdays.isNotEmpty)
                                          ...group(
                                            'birthdays',
                                            l10n.occasionsGroupBirthdays,
                                            birthdays,
                                            first: celebrations.isEmpty,
                                          ),
                                      ],
                                    ),
                                    // Regalos en secreto que este móvil no ve:
                                    // el bloque fijo, sin cifras.
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: SecretBlockList(
                                        people: ref.watch(
                                          lockedRecipientsProvider,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OccasionRow extends ConsumerWidget {
  const _OccasionRow({
    required this.occasion,
    required this.title,
    required this.giftCountValue,
    required this.now,
    this.panes = false,
    this.selected = false,
  });

  final Occasion occasion;
  final String title;
  final int giftCountValue;
  final DateTime now;

  /// Si es una fila del panel de lista de dos paneles: tocarla cambia la
  /// ocasión del detalle y, elegida, el fondo es transparente (detrás viaja el
  /// recuadro).
  final bool panes;

  /// Si es la ocasión elegida del panel de lista.
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final themed = ref.watch(
      appearanceProvider.select((a) => a.occasionThemes),
    );
    var t = RegalosTokens.of(context);
    final theme = themed ? OccasionTheme.forOccasion(occasion) : null;
    if (theme != null) {
      t = t.copyWith(occasion: theme);
    }
    final days = daysUntil(occasion, now);
    final dayMonth = occasionDayMonth(occasion, now);
    final date = longDayMonth(dayMonth.month, dayMonth.day, l10n.localeName);
    final daysText = days == null
        ? l10n.occasionPassed
        : (days == 0
              ? l10n.occasionDaysLeft(0)
              : '$days ${l10n.daysUnit(days)}');
    final giftsText = l10n.giftCount(giftCountValue);
    final spoken = [
      date,
      days == null ? l10n.occasionPassed : l10n.occasionDaysLeft(days),
      giftsText,
    ].join(' · ');
    final motif = GarlandMotif.forTheme(theme);
    void open() {
      if (panes) {
        ref.read(paneSelectionProvider).choose(PaneTab.occasions, occasion.id);
      }
      context.go('/occasions/${occasion.id}');
    }

    // El título con los días a la derecha y, debajo, la fecha y los regalos.
    // Un `Wrap` y no un `Row` para la segunda línea: con letra grande baja de
    // línea como lo haría un texto normal.
    final lines = [
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              title,
              style: panes
                  ? PaneListRow.nameStyle(t)
                  : t.styles.rowTitle.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          // El número de días rueda como un cuentakilómetros al cambiar (la
          // fecha se edita, o pasa la medianoche); «Hoy» y «Ya pasó» se
          // cruzan con un fundido.
          _Rolling(
            text: daysText,
            value: days != null && days > 0 ? days : null,
            style: t.styles.label.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: t.ink,
            ),
          ),
        ],
      ),
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ValueSwitcher(
            dy: 0,
            child: Text(date, key: ValueKey(date), style: t.styles.meta),
          ),
          Text(' · ', style: t.styles.meta),
          _Rolling(
            text: giftsText,
            value: giftCountValue > 0 ? giftCountValue : null,
            style: t.styles.meta,
            alignment: Alignment.centerLeft,
          ),
        ],
      ),
    ];

    if (panes) {
      // Fila plana de escritorio, la misma que la de Personas
      // (`PaneListRow`): sin tarjeta ni borde, con el pastel de la ocasión
      // cuando está elegida (lo pinta el recuadro que viaja por detrás) y sin
      // la guirnalda, que se queda en la cabecera del detalle.
      return PaneListRow(
        id: occasion.id,
        selected: selected,
        label: '$title. $spoken',
        onTap: open,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: lines,
        ),
      );
    }

    return Semantics(
      container: true,
      button: true,
      label: '$title. $spoken',
      excludeSemantics: true,
      onTap: open,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: SelectionRow(
          id: occasion.id,
          child: PointerSurface(
            child: Material(
              color: t.cardFill,
              shape: RoundedRectangleBorder(
                borderRadius: RegalosShape.card,
                side: BorderSide(color: t.cardBorder ?? t.separator),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: open,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    14,
                    12,
                    14,
                    motif == null ? 12 : 6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...lines,
                      if (motif != null) ...[
                        const SizedBox(height: 6),
                        OccasionGarland(
                          motif: motif,
                          color: t.ink,
                          background: t.cardFill,
                          height: 24,
                          iconSize: 18,
                        ),
                        const SizedBox(height: 2),
                      ],
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

/// Un texto con un número que rueda ([RollingCount]) o, sin número («Hoy»,
/// «Sin regalos»), una palabra que se cruza con las demás con un fundido: las
/// palabras no ruedan letra a letra.
class _Rolling extends StatelessWidget {
  const _Rolling({
    required this.text,
    required this.value,
    required this.style,
    this.alignment = Alignment.centerRight,
  });

  final String text;
  final int? value;
  final TextStyle style;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final n = value;
    return ValueSwitcher(
      dy: 0,
      alignment: alignment,
      child: n == null
          ? Text(text, key: ValueKey(text), style: style)
          : RollingCount(
              key: const ValueKey('number'),
              text: text,
              value: n,
              style: style,
            ),
    );
  }
}
