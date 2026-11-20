import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/money.dart';
import '../../../core/motion/rolling_number.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/budget_meter.dart';
import '../../../core/widgets/pointer_surface.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_providers.dart';
import '../../occasions/presentation/budget_parts.dart';

/// La tarjeta de Presupuesto de arriba de Ocasiones en la web a ancho de móvil
/// (sin quinto destino en la barra inferior): el título, lo gastado del
/// presupuesto con su barra global, «Queda X €» y una flecha que dice que se
/// abre. Si se pasa, «Te pasas X €» con la tinta de aviso; sin presupuesto,
/// «Sin presupuesto». Al pulsarla abre [onTap]
/// (`/occasions/budget`).
class WebBudgetCard extends ConsumerWidget {
  /// Crea la tarjeta.
  const WebBudgetCard({super.key, required this.onTap});

  /// Al pulsarla.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final all = ref.watch(budgetProvider);
    // Con alguna ocasión con presupuesto, las cifras cuentan solo esas
    // ocasiones; sin ninguna, todo lo que paga la casa.
    final total = all.hasBudgeted ? all.budgeted : all.total;
    String money(int cents) => formatCents(cents, l10n.localeName);
    final budget = total.budgetCents;
    final nothing =
        budget == null && total.plannedCents == 0 && total.spentCents == 0;
    final status = budgetStatusText(l10n, money, total);
    final summary = nothing
        ? l10n.budgetCardHint
        : budget == null
        ? l10n.budgetNone
        : '${money(total.spentCents)} ${l10n.budgetOf} ${money(budget)}';
    return Semantics(
      container: true,
      button: true,
      label: [l10n.budgetTitle, summary, ?status].join(', '),
      excludeSemantics: true,
      onTap: onTap,
      child: PointerSurface(
        child: Material(
          color: t.surface,
          shape: const RoundedRectangleBorder(borderRadius: RegalosShape.card),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.budgetTitle,
                          style: t.styles.label.copyWith(color: t.text),
                        ),
                      ),
                      StrokeIcon(
                        AppIcons.chevronRight,
                        size: 18,
                        color: t.textSecondary,
                        strokeWidth: 2,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (nothing || budget == null)
                        Text(summary, style: t.styles.meta)
                      else
                        RollingNumber.text(
                          text: summary,
                          style: t.styles.statLarge,
                        ),
                      if (status != null)
                        BudgetStatus(text: status, over: total.isOver),
                    ],
                  ),
                  if (budget != null) ...[
                    const SizedBox(height: 10),
                    BudgetBar(
                      height: 8,
                      fraction: budgetFraction(total),
                      semanticLabel: l10n.budgetBarLabel(
                        money(total.spentCents),
                        money(budget),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
