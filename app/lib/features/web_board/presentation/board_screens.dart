import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/format/money.dart';
import '../../../core/layout/pane_scope.dart';
import '../../../core/sync/model.dart';
import '../../../core/theme/occasion_theme.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/desktop_add_gift_button.dart';
import '../../../core/widgets/header_button.dart';
import '../../../core/widgets/person_avatar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/picker_field.dart';
import '../../../core/widgets/release_text_focus.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_controller.dart';
import '../../family/application/family_providers.dart';
import '../../family/application/gift_logic.dart';
import '../../family/domain/next_occasion.dart';
import '../../family/presentation/family_texts.dart';
import '../../family/presentation/occasion_sheet.dart';
import '../../gifts/presentation/gift_editor_screen.dart';
import '../../gifts/presentation/person_list_screen.dart';
import '../../occasions/application/occasion_rows.dart';
import '../../occasions/presentation/budget_parts.dart';
import '../../occasions/presentation/occasion_garland.dart';
import '../../settings/application/appearance_provider.dart';
import '../application/board_lanes.dart';
import '../application/board_occasion_order.dart';
import '../application/board_metrics.dart';
import 'board_budget_view.dart';
import 'board_lanes_view.dart';
import 'board_occasion_strip.dart';
import 'board_page.dart';
import 'board_scope.dart';

/// El tablero «Hoy» (la guía de diseño de escritorio, A): arriba, las
/// próximas ocasiones; debajo, «Qué toca ahora», con los regalos repartidos
/// por lo que falta a cada uno.
class BoardHomeScreen extends ConsumerWidget {
  /// Crea la pantalla.
  const BoardHomeScreen({super.key});

  /// Cuántas ocasiones salen como mucho en la tira de «Hoy» (en una ventana
  /// estrecha caben menos, y una sola fila).
  static const int stripCount = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final count = ref.watch(boardCountProvider);
    final occasions = ref.watch(occasionsProvider);
    final upcoming = boardOccasionOrder(occasions, clock.now());
    final shown = upcoming.take(stripCount).toList();
    // Las que muestra Ocasiones, con las que ya pasaron: si son más que las de
    // la tira, «Ver todas» lleva a ellas.
    final total = boardOccasionOrder(
      occasions,
      clock.now(),
      includePassed: true,
    ).length;
    final date = DateFormat.MMMMEEEEd(l10n.localeName).format(clock.now());
    final people = ref.watch(recipientsProvider);
    // La persona elegida en el filtro; si ya no existe (se archivó o se
    // borró), se ven todas.
    final filter = ref.watch(boardPersonFilterProvider);
    final personId = people.any((p) => p.id == filter) ? filter : null;
    return BoardCoveredGuard(
      child: BoardPage(
        title: l10n.boardToday,
        subtitle: l10n.boardSubtitle(date, count.bought, count.total),
        actions: [
          // El filtro por persona sube a la fila del título, junto a «Añadir
          // regalo».
          if (people.length > 1)
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 200, maxWidth: 260),
              child: _PersonFilter(
                key: const ValueKey<String>('board-person-filter'),
                people: people,
                value: personId,
                onChanged: (id) =>
                    ref.read(boardPersonFilterProvider.notifier).choose(id),
              ),
            ),
          DesktopAddGiftButton(
            key: const ValueKey<String>('board-add-gift'),
            onPressed: () => openGiftEditor(context, chooseRecipient: true),
          ),
        ],
        body: BoardLanesView(
          personId: personId,
          onAdd: (lane) => openGiftEditor(
            context,
            chooseRecipient: true,
            status: lane.status,
          ),
        ),
        children: [
          BoardOccasionStrip(
            occasions: shown,
            onOpen: (o) => context.go('/occasions/${o.id}'),
            endAction: total > shown.length
                ? _SeeAllButton(
                    key: const ValueKey<String>('board-see-all'),
                    count: total,
                    onTap: () => context.go('/occasions'),
                  )
                : null,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// «Ver todas (N)» al final de la tira de «Hoy»: un botón de texto, no otra
/// tarjeta, que lleva a Ocasiones.
class _SeeAllButton extends StatelessWidget {
  const _SeeAllButton({super.key, required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      child: Text(l10n.boardSeeAll(count), maxLines: 1),
    );
  }
}

/// El selector de persona de «Hoy»: «Todas las personas» o una de la lista.
class _PersonFilter extends StatelessWidget {
  const _PersonFilter({
    super.key,
    required this.people,
    required this.value,
    required this.onChanged,
  });

  final List<Recipient> people;

  /// La persona elegida, o `null` si se ven todas.
  final String? value;
  final ValueChanged<String?> onChanged;

  /// El valor de «Todas las personas» (el selector no admite `null`).
  static const String _all = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // Del alto de los botones de la cabecera (48), no de un campo de formulario
    // (52).
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          constraints: const BoxConstraints(
            minHeight: DesktopAddGiftButton.height,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
        ),
      ),
      child: PickerField<String>(
        label: l10n.boardPersonFilter,
        value: value ?? _all,
        options: [
          PickerOption(value: _all, label: l10n.boardPersonFilterAll),
          for (final p in people)
            PickerOption(
              value: p.id,
              label: p.name,
              leading: PersonAvatar(
                name: p.name,
                colorIndex: p.colorIndex,
                size: 28,
              ),
            ),
        ],
        onChanged: (id) => onChanged(id == _all ? null : id),
      ),
    );
  }
}

/// Ocasiones en el tablero: la tira con todas las ocasiones y, debajo, el mismo
/// tablero filtrado por la elegida, con su fecha editable. Sin ninguna
/// ocasión, su estado vacío. Con [kBudgetRowId] abre el presupuesto
/// ([BoardBudgetScreen]), que tiene su entrada propia en la barra lateral.
class BoardOccasionsScreen extends ConsumerWidget {
  /// Crea la pantalla; sin [selected] se elige la próxima ocasión.
  const BoardOccasionsScreen({super.key, this.selected});

  /// La fila elegida: una ocasión o [kBudgetRowId].
  final String? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (selected == kBudgetRowId) {
      return const BoardBudgetScreen();
    }
    final l10n = AppLocalizations.of(context);
    final occasions = ref.watch(occasionsProvider);
    final people = ref.watch(familyFullViewProvider).recipientsById;
    final now = clock.now();
    final byId = {for (final o in occasions) o.id: o};
    final order = boardOccasionOrder(occasions, now, includePassed: true);
    final chosenId = byId.containsKey(selected)
        ? selected
        : (nextOccasionRowId(occasions, now) ?? order.firstOrNull?.id);
    // El id de la URL vale aunque la ocasión esté archivada (se llega desde el
    // presupuesto): solo se sustituye por la próxima si ya no existe.
    final occasion =
        ref
            .watch(familyFullViewProvider)
            .occasions
            .where((o) => o.id == selected)
            .firstOrNull ??
        byId[chosenId];
    void open(String id) => context.go('/occasions/$id');

    Future<void> addOccasion() async {
      final result = await showOccasionSheet(context);
      if (result != null) {
        await ref
            .read(familyControllerProvider.notifier)
            .upsertOccasion(result);
      }
    }

    final Widget body = occasion != null
        ? BoardLanesView(
            occasionId: occasion.id,
            subtitle: BoardRowSubtitle.perOccasion,
            onAdd: (lane) => openGiftEditor(
              context,
              occasionId: occasion.id,
              chooseRecipient: true,
              status: lane.status,
            ),
          )
        // Sin ninguna ocasión: el estado vacío de siempre.
        : EmptyState(
            icon: AppIcons.occasions,
            title: l10n.emptyOccasionsTitle,
            message: l10n.emptyOccasionsMessage,
          );

    return BoardCoveredGuard(
      child: BoardPage(
        title: l10n.navOccasions,
        subtitle: l10n.boardOccasionsHint,
        actions: [
          HeaderIconButton(
            size: 48,
            icon: AppIcons.plus,
            label: l10n.occasionNew,
            onTap: addOccasion,
          ),
        ],
        body: body,
        children: [
          if (order.isNotEmpty)
            BoardOccasionStrip(
              occasions: order,
              selectedId: occasion?.id,
              onOpen: (o) => open(o.id),
            ),
          if (occasion == null)
            const SizedBox(height: 16)
          else
            _OccasionHeader(
              occasion: occasion,
              title: OccasionLabels(l10n, people).of(occasion),
            ),
        ],
      ),
    );
  }
}

/// El presupuesto de la casa en el tablero (la entrada «Presupuesto» de la
/// barra lateral): su cabecera y, debajo, la pantalla de siempre.
class BoardBudgetScreen extends ConsumerWidget {
  /// Crea la pantalla.
  const BoardBudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return BoardCoveredGuard(
      child: BoardPage(
        title: l10n.budgetTitle,
        subtitle: budgetSubtitleText(l10n, ref.watch(budgetProvider)),
        // El presupuesto es una pantalla entera con su propio
        // desplazamiento: llena el alto que queda, pegada a la izquierda y
        // sin cabecera propia (la del tablero hace de título).
        body: const BoardBudgetView(),
      ),
    );
  }
}

/// La cabecera de la ocasión elegida: su nombre, cuánto falta, cuántos
/// regalos hay comprados y cuánto suman, y a la derecha cambiar la fecha,
/// editarla y añadir un regalo.
class _OccasionHeader extends ConsumerWidget {
  const _OccasionHeader({required this.occasion, required this.title});

  final Occasion occasion;
  final String title;

  /// Si la fecha de la ocasión se puede cambiar a mano: la del Año Nuevo Chino
  /// se calcula y la de un cumpleaños sale de la persona.
  bool get _dateEditable =>
      occasion.kind != OccasionKind.chineseNewYear &&
      occasion.kind != OccasionKind.birthday;

  Future<void> _changeDate(
    BuildContext context,
    WidgetRef ref,
    FocusNode focus,
  ) async {
    final controller = ref.read(familyControllerProvider.notifier);
    final now = clock.now();
    final current =
        nextDateOf(occasion, now) ??
        DateTime(occasion.year ?? now.year, occasion.month, occasion.day);
    final first = DateTime(now.year - 1);
    final last = DateTime(now.year + 10, 12, 31);
    releaseTextFocus(to: focus);
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: current.isBefore(first) ? current : first,
      lastDate: current.isAfter(last) ? current : last,
    );
    if (picked == null) {
      return;
    }
    await controller.upsertOccasion(
      Occasion(
        id: occasion.id,
        kind: occasion.kind,
        rawKind: occasion.rawKind,
        name: occasion.name,
        month: picked.month,
        day: picked.day,
        year: occasion.recurring ? occasion.year : picked.year,
        recurring: occasion.recurring,
        recipientId: occasion.recipientId,
        archived: occasion.archived,
        color: occasion.color,
        icon: occasion.icon,
        budgetCents: occasion.budgetCents,
      ),
      original: occasion,
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final result = await showOccasionSheet(
      context,
      initial: occasion,
      initialName: title,
    );
    if (result != null) {
      await ref
          .read(familyControllerProvider.notifier)
          .upsertOccasion(result, original: occasion);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final count = ref.watch(boardOccasionCountProvider(occasion.id));
    final gifts = ref.watch(boardGiftsProvider);
    final cents = centsOf([
      for (final g in gifts)
        if (g.occasionId == occasion.id) g,
    ]);
    final now = clock.now();
    final days = daysUntil(occasion, now);
    final date = nextDateOf(occasion, now);
    final parts = <String>[
      days == null ? l10n.occasionPassed : l10n.occasionDaysLeft(days),
      if (date != null)
        DateFormat.MMMMd(l10n.localeName).format(date)
      else
        DateFormat.MMMMd(l10n.localeName)
            .format(DateTime(2028, occasion.month, occasion.day)),
      if (count.total == 0)
        l10n.boardNoGiftsYet
      else
        l10n.occasionGiftsBoughtShort(count.bought, count.total),
      if (cents > 0) formatCents(cents, l10n.localeName),
    ];
    // La guirnalda de la ficha bajo la cabecera, en la tinta de la ocasión
    // (Navidad y Tió, Reyes y cumpleaños), que se dibuja pieza a pieza al
    // abrirla; con los temas de ocasión apagados, no sale.
    final themed = ref.watch(
      appearanceProvider.select((a) => a.occasionThemes),
    );
    final occasionTheme = OccasionTheme.forOccasion(occasion);
    final motif = themed ? GarlandMotif.forTheme(occasionTheme) : null;
    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: t.styles.screenTitle),
              ),
              const SizedBox(height: 4),
              Text(parts.join(' · '), style: t.styles.meta),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (_dateEditable)
              _ChangeDateButton(
                label: l10n.boardChangeDate,
                onPressed: (focus) => _changeDate(context, ref, focus),
              ),
            HeaderIconButton(
              size: 48,
              icon: AppIcons.edit,
              label: l10n.occasionEdit,
              onTap: () => _edit(context, ref),
            ),
            DesktopAddGiftButton(
              key: const ValueKey<String>('board-occasion-add-gift'),
              onPressed: () => openGiftEditor(
                context,
                occasionId: occasion.id,
                chooseRecipient: true,
              ),
            ),
          ],
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (motif != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: DrawnGarland(
                key: ValueKey<String>('board-garland-${occasion.id}'),
                motif: motif,
                tokens: RegalosTokens.resolve(
                  accent: t.accent,
                  brightness: t.brightness,
                  occasion: occasionTheme,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// «Cambiar fecha»: con su propio foco, que se libera con él, para que al
/// cerrar el calendario el foco vuelva al botón y Tab siga hacia «Editar».
class _ChangeDateButton extends StatefulWidget {
  const _ChangeDateButton({required this.label, required this.onPressed});

  final String label;
  final void Function(FocusNode focus) onPressed;

  @override
  State<_ChangeDateButton> createState() => _ChangeDateButtonState();
}

class _ChangeDateButtonState extends State<_ChangeDateButton> {
  final FocusNode _focus = FocusNode(debugLabel: 'BoardChangeDate');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OutlinedButton(
    key: const ValueKey<String>('board-change-date'),
    focusNode: _focus,
    // Del alto de «Añadir regalo» y de los botones de icono.
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(44, DesktopAddGiftButton.height),
    ),
    onPressed: () => widget.onPressed(_focus),
    child: Text(widget.label),
  );
}

/// La lista de una persona dentro del tablero: la de siempre, con el diseño
/// del panel de detalle (sin flecha de volver y con «Añadir regalo» en la
/// cabecera), que entra con un desplazamiento de 8 px y un fundido. Al llegar
/// desde la barra lateral, su avatar vuela hasta la cabecera.
class BoardPersonPage extends StatelessWidget {
  /// Crea la pantalla.
  const BoardPersonPage({
    super.key,
    required this.personId,
    this.fromFamily = false,
    this.initialFilter = const GiftFilter(),
  });

  /// La persona.
  final String personId;

  /// Si se llegó desde Reparto: la flecha de volver sigue.
  final bool fromFamily;

  /// Los filtros con que se abre.
  final GiftFilter initialFilter;

  @override
  Widget build(BuildContext context) {
    // La tabla llena el ancho, desde el mismo margen izquierdo que el título de
    // Hoy y de Ocasiones (la cabecera de la lista lleva 16 de relleno propio).
    // Con el editor superpuesto, el margen derecho reserva el sitio del editor
    // (la tabla pierde columnas en vez de quedar debajo).
    final margin = BoardScope.marginOf(context);
    final inset = BoardScope.overlayInsetOf(context);
    return Padding(
      padding: EdgeInsets.only(
        left: margin - 16,
        right: math.max(margin - 16, inset),
      ),
      child: PaneScope(
        role: PaneRole.detail,
        child: BoardEntrance(
          key: ValueKey<String>('board-person-$personId'),
          child: PersonListScreen(
            recipientId: personId,
            fromFamily: fromFamily,
            initialFilter: initialFilter,
            boardTable: true,
          ),
        ),
      ),
    );
  }
}

/// La entrada de una pantalla del tablero: un fundido y un desplazamiento de
/// 8 px en horizontal (eje compartido), en 220 ms. Con «Reducir movimiento»,
/// solo el fundido de 150 ms.
class BoardEntrance extends StatelessWidget {
  /// Crea la entrada.
  const BoardEntrance({super.key, required this.child});

  /// La pantalla.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = RegalosMotion.of(context).reduce;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: reduce ? RegalosMotion.fade : const Duration(milliseconds: 220),
      curve: reduce ? Curves.linear : Curves.easeOutCubic,
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(reduce ? 0 : 8 * (1 - value), 0),
          child: child,
        ),
      ),
    );
  }
}
