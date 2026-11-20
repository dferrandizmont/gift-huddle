import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/money.dart';
import '../../../core/layout/content_gutter.dart';
import '../../../core/motion/rolling_number.dart';
import '../../../core/layout/pane_scope.dart';
import '../../../core/layout/two_pane.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/motion/success_mark.dart';
import '../../../core/motion/value_switcher.dart';
import '../../../core/sync/model.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/budget_meter.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/pointer_surface.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_providers.dart';
import '../../family/presentation/family_texts.dart';
import 'budget_parts.dart';
import 'budget_sheet.dart';

/// Presupuesto de la casa: tres números grandes (el presupuesto que pone la
/// familia en cada ocasión, lo gastado y lo que queda) y una barra, y debajo
/// una tarjeta por ocasión y por persona. Solo cuenta lo que paga la casa.
///
/// Pulsar una ocasión o una persona abre sus regalos; el presupuesto de una
/// ocasión se pone o se cambia con el botón de su tarjeta.
class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final budget = ref.watch(budgetProvider);
    final view = ref.watch(familyViewProvider);
    final labels = OccasionLabels(
      l10n,
      ref.watch(familyFullViewProvider).recipientsById,
    );
    final locale = l10n.localeName;
    String money(int cents) => formatCents(cents, locale);

    // Con alguna ocasión con presupuesto, las tres cifras, la barra y «Si
    // compras lo que falta…» cuentan solo esas ocasiones; lo gastado fuera va
    // en una línea aparte. Sin ninguna, la tarjeta cuenta todo como siempre.
    final total = budget.total;
    final shown = budget.hasBudgeted ? budget.budgeted : total;
    final left = shown.leftCents;
    final over = shown.isOver;

    // Las tres cifras ruedan al cambiar. Pasarse del presupuesto tiñe la
    // tercera de aviso con `soft`; clavarlo justo añade un visto que se dibuja.
    // [small] es para un texto («Sin presupuesto»), que no rueda.
    Widget big(
      String label,
      String value, {
      Color? color,
      bool met = false,
      bool small = false,
    }) => Expanded(
      child: Semantics(
        container: true,
        label: '$label: $value',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: ValueSwitcher(
                    dy: 0,
                    child: Text(
                      label,
                      key: ValueKey(label),
                      style: t.styles.meta,
                    ),
                  ),
                ),
                _MetCheck(met: met, color: t.ink),
              ],
            ),
            if (small)
              ValueSwitcher(
                dy: 0,
                child: Padding(
                  key: ValueKey(value),
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    value,
                    style: t.styles.label.copyWith(color: t.textSecondary),
                  ),
                ),
              )
            else
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: color ?? t.styles.stat.color),
                  duration: RegalosMotion.of(context).reduce
                      ? RegalosMotion.fade
                      : RegalosSprings.softDuration,
                  curve: RegalosCurves.soft,
                  builder: (context, c, _) => RollingNumber.text(
                    text: value,
                    style: t.styles.statLarge.copyWith(color: c),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    // Las personas no tienen presupuesto: sin previsto, solo «Gastado 45 €»,
    // nunca «45 € de 0 €» ni una barra que no mide nada.
    BudgetMeter meter(String label, BudgetTotals totals) => BudgetMeter(
      label: label,
      valueText: (
        spent: money(totals.spentCents),
        planned: money(totals.plannedCents),
        ofWord: l10n.budgetOf,
      ),
      spentOnlyLabel: totals.plannedCents > 0 ? null : l10n.budgetSpent,
      // La barra no avisa de pasarse.
      fraction: totals.plannedCents > 0
          ? math.min(1.0, totals.spentCents / totals.plannedCents)
          : 0,
      semanticLabel: l10n.budgetBarLabel(
        money(totals.spentCents),
        money(totals.plannedCents),
      ),
    );

    final people = [
      for (final r in view.recipients)
        if (budget.byRecipient.containsKey(r.id)) r,
    ];
    final fullOccasions = ref.watch(familyFullViewProvider).occasions;
    final occasionRows = budgetOccasions(budget, view.occasions, fullOccasions);
    final noOccasion = budgetWithoutOccasion(budget);
    final hasOccasionCards = occasionRows.isNotEmpty || noOccasion != null;
    // Una archivada con cifras (también un presupuesto de 0 €) sigue teniendo
    // su fila aunque el total quede a cero: no es el estado vacío.
    final empty =
        total.budgetCents == null &&
        total.plannedCents == 0 &&
        total.spentCents == 0 &&
        !occasionRows.any((row) => row.occasion.archived);
    // Los bloques entran de arriba abajo una sola vez por visita (§1.6).
    var order = 0;
    Widget block(Widget child) => StaggerItem(index: order++, child: child);

    // En el panel de detalle de dos paneles, «Por persona» y «Por ocasión» van
    // una al lado de la otra si la columna da para dos (800 o más): sin
    // huecos en una columna ancha.
    final columnWidth = detailColumnWidth(context);
    final panes = PaneScope.roleOf(context) == PaneRole.detail;
    final sideBySide =
        panes &&
        people.isNotEmpty &&
        hasOccasionCards &&
        math.min(PaneScope.widthOf(context), columnWidth) >= 800;
    final personBlocks = <Widget>[
      if (people.isNotEmpty) ...[
        SectionHeader(
          title: l10n.budgetByPerson,
          bordered: false,
          padding: EdgeInsets.fromLTRB(16, sideBySide ? 4 : 20, 16, 8),
        ),
        for (final r in people)
          _TapRow(
            key: ValueKey<String>('budget-person-${r.id}'),
            semanticLabel: [
              r.name,
              if (budget.ofRecipient(r.id).plannedCents > 0)
                l10n.budgetBarLabel(
                  money(budget.ofRecipient(r.id).spentCents),
                  money(budget.ofRecipient(r.id).plannedCents),
                )
              else
                '${l10n.budgetSpent} ${money(budget.ofRecipient(r.id).spentCents)}',
            ].join(', '),
            onTap: () => openPersonGifts(context, ref, r.id),
            child: meter(r.name, budget.ofRecipient(r.id)),
          ),
      ],
    ];
    final occasionBlocks = <Widget>[
      if (hasOccasionCards) ...[
        SectionHeader(
          title: l10n.budgetByOccasion,
          bordered: false,
          padding: EdgeInsets.fromLTRB(16, sideBySide ? 4 : 20, 16, 8),
        ),
        for (final (:occasion, :totals) in occasionRows)
          _OccasionBudgetRow(
            key: ValueKey<String>('budget-occasion-${occasion.id}'),
            name: labels.of(occasion),
            archived: occasion.archived,
            totals: totals,
            money: money,
            onOpen: () => openOccasionGifts(context, ref, occasion.id),
            onEditBudget: () => editOccasionBudget(
              context,
              occasion: occasion,
              title: labels.of(occasion),
            ),
          ),
        if (noOccasion != null)
          // Los regalos sin ocasión no tienen presupuesto ni regalos que abrir
          // aparte: solo lo gastado.
          _OccasionBudgetRow(
            key: const ValueKey<String>('budget-occasion-none'),
            name: l10n.giftNoOccasion,
            totals: noOccasion,
            money: money,
          ),
      ],
    ];

    // En tablet, una columna de 640 centrada en el panel (720 u 880 en el
    // panel de detalle de dos paneles); el margen va como relleno de la lista.
    // En el móvil es cero.
    return Scaffold(
      body: StaggerScope(
        // En dos paneles el detalle ya cambia con su propio eje: no repite
        // la entrada escalonada.
        animate: PaneScope.roleOf(context) != PaneRole.detail,
        child: SafeArea(
          bottom: false,
          child: ContentListView(
            maxWidth: columnWidth,
            padding: EdgeInsets.only(
              bottom: 24 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              ScreenHeader(
                eyebrow: l10n.navOccasions,
                title: l10n.budgetTitle,
                subtitle: budgetSubtitleText(l10n, budget),
                backLabel: l10n.backTo(l10n.navOccasions),
                onBack: () =>
                    context.canPop() ? context.pop() : context.go('/occasions'),
              ),
              if (empty && panes)
                // En dos paneles, arriba y a la izquierda, no flotando en el
                // centro del panel.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 32, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.budgetTitle,
                            style: t.styles.rowTitle.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.budgetEmpty,
                            style: t.styles.body.copyWith(
                              color: t.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const BudgetTopAction(),
                        ],
                      ),
                    ),
                  ),
                )
              else if (empty)
                Padding(
                  padding: const EdgeInsets.only(top: 32),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 280,
                        child: EmptyState(
                          icon: AppIcons.occasions,
                          title: l10n.budgetTitle,
                          message: l10n.budgetEmpty,
                        ),
                      ),
                      const BudgetTopAction(),
                    ],
                  ),
                )
              else ...[
                block(
                  // Pasarse del presupuesto tiñe la tarjeta de aviso con un filete,
                  // como en la web.
                  AnimatedContainer(
                    duration: RegalosMotion.of(context).reduce
                        ? RegalosMotion.fade
                        : RegalosSprings.snapDuration,
                    curve: RegalosMotion.of(context).reduce
                        ? Curves.linear
                        : RegalosCurves.snap,
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    decoration: BoxDecoration(
                      color: over ? t.dangerSoft : t.surface,
                      borderRadius: RegalosShape.card,
                      border: over ? Border.all(color: t.danger) : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            big(
                              l10n.budgetFigure,
                              shown.budgetCents == null
                                  ? l10n.budgetNone
                                  : money(shown.budgetCents!),
                              small: shown.budgetCents == null,
                            ),
                            const SizedBox(width: 12),
                            big(l10n.budgetSpent, money(shown.spentCents)),
                            const SizedBox(width: 12),
                            big(
                              over ? l10n.budgetOver : l10n.budgetLeft,
                              left == null ? '–' : money(left.abs()),
                              color: over ? t.danger : null,
                              met: left == 0 && (shown.budgetCents ?? 0) > 0,
                            ),
                          ],
                        ),
                        if (shown.budgetCents != null) ...[
                          const SizedBox(height: 12),
                          BudgetBar(
                            height: 8,
                            fraction: budgetFraction(shown),
                            semanticLabel: l10n.budgetBarLabel(
                              money(shown.spentCents),
                              money(shown.budgetCents!),
                            ),
                          ),
                          const SizedBox(height: 8),
                          BudgetIfBoughtLine(totals: shown, money: money),
                          BudgetOutsideLine(budget: budget, money: money),
                        ] else ...[
                          const SizedBox(height: 4),
                          const BudgetTopAction(),
                        ],
                      ],
                    ),
                  ),
                ),
                if (sideBySide)
                  block(
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: personBlocks,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: occasionBlocks,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  for (final w in [...personBlocks, ...occasionBlocks])
                    block(w),
              ],
              block(
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(l10n.budgetNote, style: t.styles.meta),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El nombre de una ocasión y, si está archivada, su marca.
class _NameLine extends StatelessWidget {
  const _NameLine({required this.name, required this.archived});

  final String name;
  final bool archived;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 6,
      children: [
        Text(name, style: t.styles.meta),
        if (archived)
          Text(
            l10n.budgetArchivedTag,
            style: t.styles.meta.copyWith(fontStyle: FontStyle.italic),
          ),
      ],
    );
  }
}

/// Una fila pulsable del presupuesto (una persona): su contenido con el ratón
/// y el teclado como cualquier fila, y «abre sus regalos» para el lector.
class _TapRow extends StatelessWidget {
  const _TapRow({
    super.key,
    required this.child,
    required this.onTap,
    required this.semanticLabel,
  });

  final Widget child;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
      child: Semantics(
        container: true,
        button: true,
        label: semanticLabel,
        hint: l10n.budgetOpenGifts,
        excludeSemantics: true,
        onTap: onTap,
        child: PointerSurface(
          child: InkWell(
            onTap: onTap,
            borderRadius: RegalosShape.card,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Una ocasión del presupuesto. Con presupuesto: lo gastado de él, su barra y
/// «Queda X» o «Te pasas X». Sin él: «Sin presupuesto» y lo gastado, nunca «de
/// 0 €» ni «Te pasas». Pulsarla abre sus regalos; debajo, el botón que pone o
/// cambia el presupuesto. Sin [onOpen] (los regalos sin ocasión) no se pulsa.
class _OccasionBudgetRow extends StatelessWidget {
  const _OccasionBudgetRow({
    super.key,
    required this.name,
    required this.totals,
    required this.money,
    this.onOpen,
    this.onEditBudget,
    this.archived = false,
  });

  /// Si la ocasión está archivada (no cuenta en el total).
  final bool archived;

  final String name;
  final BudgetTotals totals;
  final String Function(int cents) money;
  final VoidCallback? onOpen;
  final VoidCallback? onEditBudget;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final budget = totals.budgetCents;
    final status = budgetStatusText(l10n, money, totals);
    final over = totals.isOver;
    final Widget body;
    if (budget == null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _NameLine(name: name, archived: archived),
          const SizedBox(height: 2),
          Text(
            l10n.budgetNone,
            style: t.styles.label.copyWith(color: t.textSecondary),
          ),
          if (totals.spentCents > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Wrap(
                spacing: 4,
                children: [
                  Text(l10n.budgetSpent, style: t.styles.meta),
                  RollingNumber.text(
                    text: money(totals.spentCents),
                    style: t.styles.amount,
                  ),
                ],
              ),
            ),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (archived) _NameLine(name: name, archived: true),
          BudgetMeter(
            label: archived ? '' : name,
            valueText: (
              spent: money(totals.spentCents),
              planned: money(budget),
              ofWord: l10n.budgetOf,
            ),
            fraction: budgetFraction(totals),
            semanticLabel: l10n.budgetBarLabel(
              money(totals.spentCents),
              money(budget),
            ),
          ),
          if (status != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: BudgetStatus(text: status, over: over),
            ),
        ],
      );
    }
    final label = [
      name,
      if (archived) l10n.budgetArchivedTag,
      if (budget == null) ...[
        l10n.budgetNone,
        if (totals.spentCents > 0)
          '${l10n.budgetSpent} ${money(totals.spentCents)}',
      ] else ...[
        l10n.budgetBarLabel(money(totals.spentCents), money(budget)),
        ?status,
      ],
    ].join(', ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onOpen == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
              child: Semantics(
                container: true,
                label: label,
                excludeSemantics: true,
                child: body,
              ),
            )
          else
            Semantics(
              container: true,
              button: true,
              label: label,
              hint: l10n.budgetOpenGifts,
              excludeSemantics: true,
              onTap: onOpen,
              child: PointerSurface(
                child: InkWell(
                  onTap: onOpen,
                  borderRadius: RegalosShape.card,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                    child: body,
                  ),
                ),
              ),
            ),
          if (onEditBudget != null)
            Align(
              alignment: Alignment.centerLeft,
              child: BudgetActionButton(
                name: name,
                hasBudget: budget != null,
                onPressed: onEditBudget!,
              ),
            ),
        ],
      ),
    );
  }
}

/// El visto de «presupuesto cumplido». Se dibuja solo cuando `met` pasa de
/// falso a verdadero con la pantalla ya abierta; si ya estaba cumplido al
/// abrirla, o llega de golpe, aparece entero.
class _MetCheck extends StatefulWidget {
  const _MetCheck({required this.met, required this.color});

  final bool met;
  final Color color;

  @override
  State<_MetCheck> createState() => _MetCheckState();
}

class _MetCheckState extends State<_MetCheck> {
  bool _draw = false;

  @override
  void didUpdateWidget(_MetCheck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.met && !oldWidget.met) {
      _draw = true;
    } else if (!widget.met) {
      _draw = false;
    }
  }

  @override
  Widget build(BuildContext context) => ValueSwitcher(
    dy: 0,
    child: widget.met
        ? Padding(
            key: const ValueKey('met'),
            padding: const EdgeInsets.only(left: 4),
            child: DrawnCheck(
              color: widget.color,
              size: 14,
              strokeWidth: 3,
              progress: _draw ? null : kAlwaysCompleteAnimation,
            ),
          )
        : const SizedBox(key: ValueKey('open')),
  );
}
