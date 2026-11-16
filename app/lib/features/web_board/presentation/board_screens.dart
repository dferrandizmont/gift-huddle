import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/format/money.dart';
import '../../../core/layout/pane_scope.dart';
import '../../../core/sync/model.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/desktop_add_gift_button.dart';
import '../../../core/widgets/header_button.dart';
import '../../../core/widgets/pointer_surface.dart';
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
import '../../occasions/presentation/budget_screen.dart';
import '../application/board_lanes.dart';
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
    final upcoming = ref.watch(upcomingOccasionsProvider);
    final date = DateFormat.MMMMEEEEd(l10n.localeName).format(clock.now());
    return BoardCoveredGuard(
      child: BoardPage(
        title: l10n.boardToday,
        subtitle: l10n.boardSubtitle(date, count.bought, count.total),
        actions: [
          DesktopAddGiftButton(
            key: const ValueKey<String>('board-add-gift'),
            onPressed: () => openGiftEditor(context, chooseRecipient: true),
          ),
        ],
        body: BoardLanesView(
          onAdd: () => openGiftEditor(context, chooseRecipient: true),
        ),
        children: [
          BoardOccasionStrip(
            occasions: [
              for (final next in upcoming.take(stripCount)) next.occasion,
            ],
            onOpen: (o) => context.go('/occasions/${o.id}'),
          ),
          BoardCaption(l10n.boardNowTitle),
        ],
      ),
    );
  }
}

/// Ocasiones en el tablero: la tira con todas las ocasiones (y el
/// presupuesto) y, debajo, el mismo tablero filtrado por la elegida, con su
/// fecha editable.
class BoardOccasionsScreen extends ConsumerWidget {
  /// Crea la pantalla; sin [selected] se elige la próxima ocasión.
  const BoardOccasionsScreen({super.key, this.selected});

  /// La fila elegida: una ocasión o [kBudgetRowId].
  final String? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final occasions = ref.watch(occasionsProvider);
    final people = ref.watch(familyFullViewProvider).recipientsById;
    final now = clock.now();
    final byId = {for (final o in occasions) o.id: o};
    final order = [
      for (final id in occasionRowIds(occasions, now))
        if (id != kBudgetRowId) byId[id]!,
    ];
    final chosenId = selected == kBudgetRowId
        ? kBudgetRowId
        : (byId.containsKey(selected)
              ? selected!
              : (nextOccasionRowId(occasions, now) ?? kBudgetRowId));
    final occasion = byId[chosenId];
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
            onAdd: () => openGiftEditor(
              context,
              occasionId: occasion.id,
              chooseRecipient: true,
            ),
          )
        // El presupuesto es una pantalla entera con su propio
        // desplazamiento: llena el alto que queda.
        : DecoratedBox(
            decoration: BoxDecoration(
              color: t.bg,
              border: Border.all(color: t.separator),
              borderRadius: RegalosShape.card,
            ),
            child: ClipRRect(
              borderRadius: RegalosShape.card,
              child: const PaneScope(
                role: PaneRole.detail,
                child: BudgetScreen(),
              ),
            ),
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
          BoardOccasionStrip(
            occasions: order,
            selectedId: chosenId,
            onOpen: (o) => open(o.id),
            trailing: _BudgetCard(
              selected: chosenId == kBudgetRowId,
              onTap: () => open(kBudgetRowId),
            ),
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

/// La tarjeta del presupuesto de la casa, al final de la tira de ocasiones.
class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final reduce = RegalosMotion.of(context).reduce;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: l10n.budgetCardTitle,
      excludeSemantics: true,
      onTap: onTap,
      child: AnimatedContainer(
        duration: reduce ? RegalosMotion.fade : RegalosSprings.snapDuration,
        curve: reduce ? Curves.linear : RegalosCurves.snap,
        decoration: BoxDecoration(
          color: t.soft,
          borderRadius: RegalosShape.card,
          boxShadow: selected
              ? [
                  // La tinta, la de fuera (4), y encima el fondo (2): un aro de
                  // 2 separado 2 de la tarjeta.
                  BoxShadow(color: t.ink, spreadRadius: 4),
                  BoxShadow(color: t.bg, spreadRadius: 2),
                ]
              : const <BoxShadow>[],
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
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      l10n.budgetCardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.styles.label.copyWith(color: t.ink),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.budgetCardHint,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.styles.caption.copyWith(color: t.ink),
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

  Future<void> _changeDate(BuildContext context, WidgetRef ref) async {
    final now = clock.now();
    final current =
        nextDateOf(occasion, now) ??
        DateTime(occasion.year ?? now.year, occasion.month, occasion.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (picked == null) {
      return;
    }
    await ref
        .read(familyControllerProvider.notifier)
        .upsertOccasion(
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
          ),
        );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final result = await showOccasionSheet(
      context,
      initial: occasion,
      initialName: title,
    );
    if (result != null) {
      await ref.read(familyControllerProvider.notifier).upsertOccasion(result);
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
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: t.styles.screenTitleSmall),
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
                OutlinedButton(
                  key: const ValueKey<String>('board-change-date'),
                  onPressed: () => _changeDate(context, ref),
                  child: Text(l10n.boardChangeDate),
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
      ),
    );
  }
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
