import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/money.dart';
import '../../../core/motion/rolling_number.dart';
import '../../../core/motion/value_switcher.dart';
import '../../../core/sync/model.dart';
import '../../../core/theme/accent_palette.dart';
import '../../../core/theme/occasion_theme.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/budget_meter.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/person_avatar.dart';
import '../../../core/widgets/pointer_surface.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_providers.dart';
import '../../family/presentation/family_texts.dart';
import '../../occasions/presentation/budget_parts.dart';
import '../../occasions/presentation/budget_sheet.dart';
import '../../settings/application/appearance_provider.dart';
import '../application/board_occasion_order.dart';
import 'board_occasion_strip.dart';

/// El presupuesto de la casa en el tablero de la web: tres cifras grandes
/// (presupuesto, gastado y lo que queda) y la barra global arriba; debajo,
/// «Por ocasión» como tarjetas pastel (en el orden de la tira, por días) y
/// «Por persona» como una rejilla compacta con la inicial de cada una. Solo
/// cuenta lo que paga la casa.
///
/// El presupuesto lo pone la familia en cada ocasión: pulsar una tarjeta de
/// ocasión o de persona abre sus regalos, y el botón del pie de la tarjeta de
/// ocasión pone o cambia su presupuesto.
///
/// Empieza en el margen de la cabecera y reparte el ancho en columnas; en una
/// ventana estrecha, una sola. Las barras crecen al entrar (con «Reducir
/// movimiento», aparecen enteras).
class BoardBudgetView extends ConsumerWidget {
  /// Crea la vista.
  const BoardBudgetView({super.key});

  /// El ancho mínimo de una tarjeta de ocasión y de persona.
  static const double occasionMinWidth = 240;
  static const double personMinWidth = 280;

  /// El ancho mínimo de una cifra del resumen.
  static const double statMinWidth = 200;

  /// El hueco entre tarjetas.
  static const double gap = 12;

  /// Cuántas columnas caben en [width] con tarjetas de al menos [minWidth].
  static int columnsFor(double width, double minWidth) =>
      math.max(1, ((width + gap) / (minWidth + gap)).floor());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final budget = ref.watch(budgetProvider);
    final view = ref.watch(familyViewProvider);
    final locale = l10n.localeName;
    String money(int cents) => formatCents(cents, locale);
    final total = budget.total;

    // Una archivada con cifras (también un presupuesto de 0 €) sigue teniendo
    // su fila aunque el total quede a cero: no es el estado vacío.
    final fullOccasions = ref.watch(familyFullViewProvider).occasions;
    if (total.budgetCents == null &&
        total.plannedCents == 0 &&
        total.spentCents == 0 &&
        !budgetOccasions(
          budget,
          view.occasions,
          fullOccasions,
        ).any((row) => row.occasion.archived)) {
      return Column(
        children: [
          Expanded(
            child: EmptyState(
              icon: AppIcons.budget,
              title: l10n.boardBudgetEmptyTitle,
              message: l10n.budgetEmpty,
            ),
          ),
          const BudgetTopAction(),
        ],
      );
    }

    // Con los nombres también de las personas archivadas: el cumpleaños de una
    // que ya no está sigue llamándose «Cumpleaños de Nora».
    final labels = OccasionLabels(
      l10n,
      ref.watch(familyFullViewProvider).recipientsById,
    );
    final themed = ref.watch(
      appearanceProvider.select((a) => a.occasionThemes),
    );
    // Las ocasiones con presupuesto o con regalos de la casa, en el orden de la
    // tira (por días), y al final los regalos sin ocasión.
    final occasions = [
      for (final (:occasion, :totals) in budgetOccasions(
        budget,
        boardOccasionOrder(view.occasions, clock.now(), includePassed: true),
        fullOccasions,
      ))
        _OccasionEntry(
          id: occasion.id,
          title: labels.of(occasion),
          totals: totals,
          palette: themed
              ? OccasionTheme.forOccasion(occasion).palette
              : t.accent,
          icon: themed ? OccasionTheme.forOccasion(occasion).icon : null,
          occasion: occasion,
          archived: occasion.archived,
        ),
      if (budgetWithoutOccasion(budget) case final none?)
        _OccasionEntry(
          id: Budget.noOccasion,
          title: l10n.giftNoOccasion,
          totals: none,
          palette: t.accent,
        ),
    ];
    // Las personas, en el orden de la barra lateral.
    final people = [
      for (final r in view.recipients)
        if (budget.byRecipient.containsKey(r.id)) r,
    ];

    // Con alguna ocasión con presupuesto, las cifras de arriba cuentan solo
    // esas ocasiones y lo gastado fuera va en una línea aparte; sin ninguna,
    // cuentan todo como siempre.
    final shown = budget.hasBudgeted ? budget.budgeted : total;
    final left = shown.leftCents;
    final over = shown.isOver;

    Widget section(String title) => Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 12),
      child: Semantics(
        header: true,
        child: Text(title, style: t.styles.sectionTitle),
      ),
    );

    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        Widget grid(double minWidth, List<Widget> children) {
          final columns = columnsFor(width, minWidth);
          final each = (width - (columns - 1) * gap) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final c in children) SizedBox(width: each, child: c),
            ],
          );
        }

        final statColumns = math.min(3, columnsFor(width, statMinWidth));
        final statWidth = (width - (statColumns - 1) * gap) / statColumns;
        Widget stat(
          String label,
          String value, {
          bool warn = false,
          bool text = false,
        }) => SizedBox(
          width: statWidth,
          child: _StatCard(label: label, value: value, warn: warn, text: text),
        );

        return ListView(
          padding: EdgeInsets.only(
            bottom: 24 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                stat(
                  l10n.budgetFigure,
                  shown.budgetCents == null
                      ? l10n.budgetNone
                      : money(shown.budgetCents!),
                  text: shown.budgetCents == null,
                ),
                stat(l10n.budgetSpent, money(shown.spentCents)),
                stat(
                  over ? l10n.budgetOver : l10n.budgetLeft,
                  left == null ? '–' : money(left.abs()),
                  warn: over,
                ),
              ],
            ),
            if (shown.budgetCents != null) ...[
              const SizedBox(height: 16),
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
              const Align(
                alignment: Alignment.centerLeft,
                child: BudgetTopAction(),
              ),
            ],
            if (occasions.isNotEmpty) ...[
              section(l10n.budgetByOccasion),
              grid(occasionMinWidth, [
                for (final o in occasions)
                  _OccasionCard(
                    key: ValueKey<String>('budget-occasion-${o.id}'),
                    entry: o,
                    money: money,
                    onOpen: o.occasion == null
                        ? null
                        : () => openOccasionGifts(context, ref, o.id),
                    onEditBudget: o.occasion == null
                        ? null
                        : () => editOccasionBudget(
                            context,
                            occasion: o.occasion,
                            title: o.title,
                          ),
                  ),
              ]),
            ],
            if (people.isNotEmpty) ...[
              section(l10n.budgetByPerson),
              grid(personMinWidth, [
                for (final r in people)
                  _PersonCard(
                    key: ValueKey<String>('budget-person-${r.id}'),
                    name: r.name,
                    colorIndex: r.colorIndex,
                    totals: budget.ofRecipient(r.id),
                    spent: money(budget.ofRecipient(r.id).spentCents),
                    planned: money(budget.ofRecipient(r.id).plannedCents),
                    ofWord: l10n.budgetOf,
                    onOpen: () => openPersonGifts(context, ref, r.id),
                  ),
              ]),
            ],
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text(l10n.budgetNote, style: t.styles.meta),
            ),
          ],
        );
      },
    );
  }
}

class _OccasionEntry {
  const _OccasionEntry({
    required this.id,
    required this.title,
    required this.totals,
    required this.palette,
    this.icon,
    this.occasion,
    this.archived = false,
  });

  /// Si la ocasión está archivada (no cuenta en el total).
  final bool archived;

  final String id;
  final String title;
  final BudgetTotals totals;
  final AccentPalette palette;
  final IconData? icon;

  /// La ocasión, o `null` para los regalos sin ocasión (sin presupuesto ni
  /// regalos que abrir aparte).
  final Occasion? occasion;
}

/// Una de las tres cifras del resumen. Pasarse del presupuesto cambia el título
/// («Te pasas») y la tiñe de aviso con un filete a la izquierda, no solo el
/// color.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    this.warn = false,
    this.text = false,
  });

  final String label;
  final String value;
  final bool warn;

  /// Si [value] es un texto («Sin presupuesto») y no una cifra que rueda.
  final bool text;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final reduce = RegalosMotion.of(context).reduce;
    return Semantics(
      container: true,
      label: '$label: $value',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: reduce ? RegalosMotion.fade : RegalosSprings.snapDuration,
        curve: reduce ? Curves.linear : RegalosCurves.snap,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: warn ? t.dangerSoft : t.surface,
          borderRadius: RegalosShape.card,
          border: warn ? Border.all(color: t.danger) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: t.styles.meta.copyWith(
                color: warn ? t.danger : null,
                fontWeight: warn ? FontWeight.w700 : null,
              ),
            ),
            const SizedBox(height: 2),
            if (text)
              ValueSwitcher(
                dy: 0,
                child: Padding(
                  key: ValueKey<String>(value),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    value,
                    style: t.styles.rowTitle.copyWith(color: t.textSecondary),
                  ),
                ),
              )
            else
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: RollingNumber.text(
                  text: value,
                  style: t.styles.statLarge.copyWith(
                    color: warn ? t.danger : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Una tarjeta pastel de ocasión. Con presupuesto: lo gastado de él, su barra y
/// «Queda X» o «Te pasas X». Sin él: «Sin presupuesto» y lo gastado, nunca «de
/// 0 €» ni «Te pasas». Pulsarla abre sus regalos; el botón del pie pone o
/// cambia el presupuesto. Sin [onOpen] (los regalos sin ocasión) no se pulsa.
class _OccasionCard extends StatelessWidget {
  const _OccasionCard({
    super.key,
    required this.entry,
    required this.money,
    this.onOpen,
    this.onEditBudget,
  });

  final _OccasionEntry entry;
  final String Function(int cents) money;
  final VoidCallback? onOpen;
  final VoidCallback? onEditBudget;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final colors = boardColorsOf(t, entry.palette);
    final totals = entry.totals;
    final budget = totals.budgetCents;
    final over = totals.isOver;
    final status = budgetStatusText(l10n, money, totals);
    final spent = money(totals.spentCents);
    final label = [
      entry.title,
      if (entry.archived) l10n.budgetArchivedTag,
      if (budget == null) ...[
        l10n.budgetNone,
        if (totals.spentCents > 0) '${l10n.budgetSpent} $spent',
      ] else ...[
        '$spent ${l10n.budgetOf} ${money(budget)}',
        ?status,
      ],
    ].join(', ');
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (entry.icon != null) ...[
                Icon(entry.icon, size: 18, color: colors.ink),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  entry.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.styles.label.copyWith(color: colors.ink),
                ),
              ),
            ],
          ),
          // La marca va debajo del nombre, con salto de línea: «Archived ·
          // not counted» no cabe al lado con la letra grande.
          if (entry.archived)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                l10n.budgetArchivedTag,
                style: t.styles.caption.copyWith(
                  color: colors.ink,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          const SizedBox(height: 6),
          if (budget == null) ...[
            Text(
              l10n.budgetNone,
              style: t.styles.amount.copyWith(color: colors.ink),
            ),
            if (totals.spentCents > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      l10n.budgetSpent,
                      style: t.styles.caption.copyWith(color: colors.ink),
                    ),
                    RollingNumber.text(
                      text: spent,
                      style: t.styles.amount.copyWith(color: colors.ink),
                    ),
                  ],
                ),
              ),
          ] else ...[
            _Amounts(
              spent: spent,
              planned: money(budget),
              ofWord: l10n.budgetOf,
              ink: colors.ink,
            ),
            const SizedBox(height: 10),
            _GrowBar(
              fraction: budgetFraction(totals),
              ink: colors.ink,
              over: over,
              danger: t.dangerOnTint,
            ),
            if (status != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: BudgetStatus(
                  text: status,
                  over: over,
                  ink: colors.ink,
                  danger: t.dangerOnTint,
                ),
              ),
          ],
        ],
      ),
    );
    return Material(
      color: colors.fill,
      shape: const RoundedRectangleBorder(borderRadius: RegalosShape.card),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onOpen == null)
            Semantics(
              container: true,
              label: label,
              excludeSemantics: true,
              child: content,
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
                child: InkWell(onTap: onOpen, child: content),
              ),
            ),
          if (onEditBudget != null)
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: BudgetActionButton(
                  name: entry.title,
                  hasBudget: budget != null,
                  color: colors.ink,
                  onPressed: onEditBudget!,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Una persona de la rejilla: su inicial en pastel, el nombre, lo gastado de lo
/// previsto y su barra. Las personas no tienen presupuesto. Pulsarla abre sus
/// regalos.
class _PersonCard extends StatelessWidget {
  const _PersonCard({
    super.key,
    required this.name,
    required this.colorIndex,
    required this.totals,
    required this.spent,
    required this.planned,
    required this.ofWord,
    required this.onOpen,
  });

  final String name;
  final int colorIndex;
  final BudgetTotals totals;
  final String spent;
  final String planned;
  final String ofWord;

  /// Abre sus regalos.
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final colors = boardColorsOf(t, personPalette(colorIndex));
    // Sin previsto, solo «Gastado 45 €»: nunca «45 € de 0 €» ni una barra que
    // no mide nada.
    final spentOnly = totals.plannedCents <= 0;
    return Semantics(
      container: true,
      button: true,
      label: spentOnly
          ? '$name, ${l10n.budgetSpent} $spent'
          : '$name, $spent $ofWord $planned',
      hint: l10n.budgetOpenGifts,
      excludeSemantics: true,
      onTap: onOpen,
      child: PointerSurface(
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: RegalosShape.card,
            side: BorderSide(color: t.separator),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PersonAvatar(name: name, colorIndex: colorIndex, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.styles.label.copyWith(color: t.text),
                        ),
                        const SizedBox(height: 4),
                        if (spentOnly)
                          Wrap(
                            spacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                l10n.budgetSpent,
                                style: t.styles.caption.copyWith(color: t.text),
                              ),
                              RollingNumber.text(
                                text: spent,
                                style: t.styles.amount.copyWith(color: t.text),
                              ),
                            ],
                          )
                        else ...[
                          _Amounts(
                            spent: spent,
                            planned: planned,
                            ofWord: ofWord,
                            ink: t.text,
                          ),
                          const SizedBox(height: 10),
                          _GrowBar(
                            fraction: totals.spentCents / totals.plannedCents,
                            // Las personas no tienen presupuesto: la barra no
                            // avisa de pasarse.
                            ink: colors.ink,
                            over: false,
                            danger: t.danger,
                            track: t.track,
                          ),
                        ],
                      ],
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

/// «72,94 € de 145 €»: la cifra rueda al cambiar y, si no cabe, baja de línea.
class _Amounts extends StatelessWidget {
  const _Amounts({
    required this.spent,
    required this.planned,
    required this.ofWord,
    required this.ink,
  });

  final String spent;
  final String planned;
  final String ofWord;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        RollingNumber.text(
          text: spent,
          style: t.styles.amount.copyWith(color: ink),
        ),
        Text('$ofWord $planned', style: t.styles.caption.copyWith(color: ink)),
      ],
    );
  }
}

/// La barra de una tarjeta: crece desde cero al entrar y al cambiar (con
/// «Reducir movimiento», entera). Pasarse la tiñe de aviso.
class _GrowBar extends StatelessWidget {
  const _GrowBar({
    required this.fraction,
    required this.ink,
    required this.over,
    required this.danger,
    this.track,
  });

  final double fraction;
  final Color ink;
  final bool over;
  final Color danger;

  /// El color de la pista; sin él, la tinta al 18 %.
  final Color? track;

  static const double height = 6;

  @override
  Widget build(BuildContext context) {
    final reduce = RegalosMotion.of(context).reduce;
    final value = (fraction.isNaN ? 0.0 : fraction).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: RegalosShape.bar,
      child: Container(
        height: height,
        color: track ?? ink.withValues(alpha: 0.18),
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: reduce ? value : 0, end: value),
          duration: reduce ? Duration.zero : RegalosSprings.snapDuration,
          curve: RegalosCurves.snap,
          builder: (context, v, _) => FractionallySizedBox(
            widthFactor: v.clamp(0.0, 1.0),
            child: ColoredBox(
              color: over ? danger : ink,
              child: const SizedBox(height: height),
            ),
          ),
        ),
      ),
    );
  }
}
