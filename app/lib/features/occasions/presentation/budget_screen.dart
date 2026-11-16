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
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_providers.dart';
import '../../family/presentation/family_texts.dart';

/// Presupuesto de la casa: tres números grandes y una barra, por persona y
/// por ocasión. Solo cuenta lo que paga la casa.
class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final budget = ref.watch(budgetProvider);
    final view = ref.watch(familyViewProvider);
    final labels = OccasionLabels(l10n, view.recipientsById);
    final locale = l10n.localeName;
    String money(int cents) => formatCents(cents, locale);

    final total = budget.total;
    final left = total.plannedCents - total.spentCents;
    final over = left < 0;

    // Las tres cifras ruedan al cambiar. Pasarse del presupuesto tiñe la
    // tercera de aviso con `soft`; clavarlo justo añade un visto que se dibuja.
    Widget big(String label, String value, {Color? color, bool met = false}) =>
        Expanded(
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
                      style: t.styles.stat.copyWith(fontSize: 22, color: c),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

    BudgetMeter meter(String label, BudgetTotals totals) => BudgetMeter(
      label: label,
      valueText: (
        spent: money(totals.spentCents),
        planned: money(totals.plannedCents),
        ofWord: l10n.budgetOf,
      ),
      fraction: totals.plannedCents > 0
          ? totals.spentCents / totals.plannedCents
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
    final occasionRows = <(String, BudgetTotals)>[
      for (final o in view.occasions)
        if (budget.byOccasion.containsKey(o.id))
          (labels.of(o), budget.ofOccasion(o.id)),
      if (budget.byOccasion.containsKey(Budget.noOccasion))
        (l10n.giftNoOccasion, budget.ofOccasion(Budget.noOccasion)),
    ];
    final empty = total.plannedCents == 0 && total.spentCents == 0;
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
        occasionRows.isNotEmpty &&
        math.min(PaneScope.widthOf(context), columnWidth) >= 800;
    final personBlocks = <Widget>[
      if (people.isNotEmpty) ...[
        SectionHeader(
          title: l10n.budgetByPerson,
          bordered: false,
          padding: EdgeInsets.fromLTRB(16, sideBySide ? 4 : 20, 16, 8),
        ),
        for (final r in people)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: meter(r.name, budget.ofRecipient(r.id)),
          ),
      ],
    ];
    final occasionBlocks = <Widget>[
      if (occasionRows.isNotEmpty) ...[
        SectionHeader(
          title: l10n.budgetByOccasion,
          bordered: false,
          padding: EdgeInsets.fromLTRB(16, sideBySide ? 4 : 20, 16, 8),
        ),
        for (final (name, totals) in occasionRows)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: meter(name, totals),
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
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              ScreenHeader(
                eyebrow: l10n.navOccasions,
                title: l10n.budgetTitle,
                subtitle: l10n.budgetSubtitle,
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
                        ],
                      ),
                    ),
                  ),
                )
              else if (empty)
                Padding(
                  padding: const EdgeInsets.only(top: 32),
                  child: SizedBox(
                    height: 280,
                    child: EmptyState(
                      icon: AppIcons.occasions,
                      title: l10n.budgetTitle,
                      message: l10n.budgetEmpty,
                    ),
                  ),
                )
              else ...[
                block(
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    decoration: BoxDecoration(
                      color: t.surface,
                      borderRadius: RegalosShape.card,
                    ),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            big(l10n.budgetPlanned, money(total.plannedCents)),
                            const SizedBox(width: 12),
                            big(l10n.budgetSpent, money(total.spentCents)),
                            const SizedBox(width: 12),
                            big(
                              over ? l10n.budgetOver : l10n.budgetLeft,
                              money(left.abs()),
                              color: over ? t.danger : null,
                              met: left == 0 && total.plannedCents > 0,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        BudgetBar(
                          height: 8,
                          fraction: total.plannedCents > 0
                              ? total.spentCents / total.plannedCents
                              : 0,
                          semanticLabel: l10n.budgetBarLabel(
                            money(total.spentCents),
                            money(total.plannedCents),
                          ),
                        ),
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
