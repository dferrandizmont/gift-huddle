import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/pane_scope.dart';
import '../../../core/layout/pane_selection.dart';
import '../../../core/motion/rolling_number.dart';
import '../../../core/motion/value_switcher.dart';
import '../../../core/sync/model.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_controller.dart';
import '../../family/application/family_providers.dart';
import '../../family/presentation/occasion_sheet.dart';
import 'budget_sheet.dart';

/// Piezas que comparten las dos pantallas de Presupuesto (la nativa y la del
/// tablero de la web): lo que dice cada cifra, a dónde lleva cada tarjeta y el
/// botón que pone o cambia el presupuesto.

/// Cuánto del presupuesto está gastado, de 0 a 1 (más de 1 si se pasó). Sin
/// presupuesto, 0. Un presupuesto de 0 € con algo gastado cuenta como pasado.
double budgetFraction(BudgetTotals totals) {
  final budget = totals.budgetCents;
  if (budget == null) {
    return 0;
  }
  if (budget <= 0) {
    return totals.spentCents > 0 ? 1.5 : 0;
  }
  return totals.spentCents / budget;
}

/// «Si compras lo que falta, te quedarán 120 €» o, si no llega, «…te pasarás
/// 40 €». `null` si no hay presupuesto.
String? budgetIfBoughtText(
  AppLocalizations l10n,
  String Function(int cents) money,
  BudgetTotals totals,
) {
  final left = totals.leftIfBoughtCents;
  if (left == null) {
    return null;
  }
  return left < 0
      ? l10n.budgetOverIfBought(money(-left))
      : l10n.budgetLeftIfBought(money(left));
}

/// «Queda 120 €» o «Te pasas 40 €» de [totals]; `null` sin presupuesto.
String? budgetStatusText(
  AppLocalizations l10n,
  String Function(int cents) money,
  BudgetTotals totals,
) {
  final left = totals.leftCents;
  if (left == null) {
    return null;
  }
  return left < 0
      ? '${l10n.budgetOver} ${money(-left)}'
      : '${l10n.budgetLeft} ${money(left)}';
}

/// La línea «Si compras lo que falta…» bajo las cifras: la cifra rueda al
/// cambiar y, si no llega, se tiñe de aviso.
class BudgetIfBoughtLine extends StatelessWidget {
  /// Crea la línea.
  const BudgetIfBoughtLine({
    super.key,
    required this.totals,
    required this.money,
    this.style,
  });

  /// Los totales de los que sale.
  final BudgetTotals totals;

  /// Escribe un importe para el idioma.
  final String Function(int cents) money;

  /// El estilo base; por defecto, el del estado del presupuesto.
  final TextStyle? style;

  /// Marca el sitio de la cifra al partir la frase del idioma.
  static const String _mark = '⁣';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final left = totals.leftIfBoughtCents;
    final text = budgetIfBoughtText(l10n, money, totals);
    if (left == null || text == null) {
      return const SizedBox.shrink();
    }
    final warn = left < 0;
    final base = (style ?? t.styles.status).copyWith(
      color: warn ? t.danger : null,
    );
    // La frase se escribe una vez por idioma con la cifra dentro; aquí se parte
    // por la cifra para que solo ella ruede y el resto cruce con un fundido.
    final sentence = warn
        ? l10n.budgetOverIfBought(_mark)
        : l10n.budgetLeftIfBought(_mark);
    final at = sentence.indexOf(_mark);
    final before = at < 0 ? sentence : sentence.substring(0, at);
    final after = at < 0 ? '' : sentence.substring(at + _mark.length);
    return Semantics(
      container: true,
      label: text,
      excludeSemantics: true,
      child: ValueSwitcher(
        dy: 0,
        child: Wrap(
          key: ValueKey<bool>(warn),
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (before.isNotEmpty) Text(before, style: base),
            RollingNumber.text(text: money(warn ? -left : left), style: base),
            if (after.isNotEmpty) Text(after, style: base),
          ],
        ),
      ),
    );
  }
}

/// El subtítulo de Presupuesto: con alguna ocasión con presupuesto avisa de que
/// las tres cifras solo cuentan esas; sin ninguna, las cifras cuentan todo lo
/// que paga la casa y el aviso sería falso.
String budgetSubtitleText(AppLocalizations l10n, Budget budget) =>
    budget.hasBudgeted ? l10n.budgetSubtitleBudgeted : l10n.budgetSubtitle;

/// La línea «Además, la casa ha gastado 45 € fuera de las ocasiones con presupuesto.» bajo la tarjeta de arriba:
/// lo que paga la casa en ocasiones sin presupuesto y en regalos sin ocasión,
/// que las tres cifras no cuentan. No sale si no hay ocasión con presupuesto o
/// si fuera no se ha gastado nada.
class BudgetOutsideLine extends StatelessWidget {
  /// Crea la línea.
  const BudgetOutsideLine({
    super.key,
    required this.budget,
    required this.money,
  });

  /// El presupuesto de la casa.
  final Budget budget;

  /// Escribe un importe para el idioma.
  final String Function(int cents) money;

  @override
  Widget build(BuildContext context) {
    final outside = budget.spentOutsideBudgetCents;
    if (!budget.hasBudgeted || outside <= 0) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final text = l10n.budgetSpentOutside(money(outside));
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Semantics(
        container: true,
        label: text,
        excludeSemantics: true,
        child: Text(text, style: t.styles.meta),
      ),
    );
  }
}

/// El estado de un presupuesto, «Queda 120 €» o «Te pasas 40 €»: con el estilo
/// de estado de la app. Pasarse cambia el color a aviso y añade un triángulo
/// (no solo el color, por el daltonismo); el texto y el aviso se cruzan con un
/// fundido.
class BudgetStatus extends StatelessWidget {
  /// Crea el estado.
  const BudgetStatus({
    super.key,
    required this.text,
    required this.over,
    this.ink,
    this.danger,
  });

  /// «Queda 120 €» o «Te pasas 40 €».
  final String text;

  /// Si se pasó.
  final bool over;

  /// El color si no se pasó; por defecto el del texto de la app (una tarjeta
  /// pastel pasa su tinta).
  final Color? ink;

  /// El color del aviso; por defecto `danger` (sobre pastel, `dangerOnTint`).
  final Color? danger;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final color = over ? (danger ?? t.danger) : (ink ?? t.text);
    return ValueSwitcher(
      dy: 0,
      child: Row(
        key: ValueKey<bool>(over),
        mainAxisSize: MainAxisSize.min,
        children: [
          if (over) ...[
            StrokeIcon(AppIcons.alert, size: 14, color: color, strokeWidth: 2),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(text, style: t.styles.status.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}

/// El botón de una tarjeta que pone o cambia el presupuesto de su ocasión
/// («Poner presupuesto» sin él, «Cambiar presupuesto» con él): un botón
/// terciario del tema, con su icono delante, de 44 de alto también en
/// escritorio (sin la densidad compacta). Con ratón y teclado se llega a él
/// como a cualquier botón.
class BudgetActionButton extends StatelessWidget {
  /// Crea el botón.
  const BudgetActionButton({
    super.key,
    required this.hasBudget,
    required this.onPressed,
    this.name,
    this.color,
  });

  /// El nombre de la ocasión, para el lector de pantalla; sin él (el acceso
  /// general) la etiqueta es solo la del botón.
  final String? name;

  /// Si la ocasión ya tiene presupuesto.
  final bool hasBudget;

  /// Al pulsarlo.
  final VoidCallback onPressed;

  /// El color del texto y del icono; por defecto, el de los botones de texto
  /// del tema (una tarjeta pastel pasa su tinta).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final ink = color ?? t.ink;
    final label = hasBudget ? l10n.budgetEditAction : l10n.budgetSetAction;
    final spoken = name == null
        ? label
        : (hasBudget ? l10n.budgetEditFor(name!) : l10n.budgetSetFor(name!));
    return _TertiaryAction(
      label: label,
      spoken: spoken,
      icon: hasBudget ? AppIcons.edit : AppIcons.plus,
      color: ink,
      onPressed: onPressed,
    );
  }
}

/// El acceso general de arriba de Presupuesto: «Poner presupuesto» (elige la
/// ocasión en la hoja) y, si no hay ninguna ocasión activa, «Crear ocasión»,
/// que abre el editor de ocasión en vez de un selector vacío.
class BudgetTopAction extends ConsumerWidget {
  /// Crea el acceso.
  const BudgetTopAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    if (ref.watch(occasionsProvider).isNotEmpty) {
      return BudgetActionButton(
        key: const ValueKey<String>('budget-set-first'),
        hasBudget: false,
        onPressed: () => editOccasionBudget(context),
      );
    }
    return _TertiaryAction(
      key: const ValueKey<String>('budget-create-occasion'),
      label: l10n.budgetCreateOccasion,
      spoken: l10n.budgetCreateOccasion,
      icon: AppIcons.plus,
      color: t.ink,
      onPressed: () async {
        final result = await showOccasionSheet(context);
        if (result != null) {
          await ref
              .read(familyControllerProvider.notifier)
              .upsertOccasion(result);
        }
      },
    );
  }
}

class _TertiaryAction extends StatelessWidget {
  const _TertiaryAction({
    super.key,
    required this.label,
    required this.spoken,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final String spoken;
  final StrokeIconBuilder icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: spoken,
      excludeSemantics: true,
      onTap: onPressed,
      child: TextButton.icon(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: color,
          visualDensity: VisualDensity.standard,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          tapTargetSize: MaterialTapTargetSize.padded,
          alignment: Alignment.centerLeft,
        ),
        icon: StrokeIcon(icon, size: 16, color: color, strokeWidth: 2),
        label: Text(label),
      ),
    );
  }
}

/// Abre los regalos de una ocasión, como al elegirla en Ocasiones. En dos
/// paneles, además, la deja elegida en la lista.
void openOccasionGifts(BuildContext context, WidgetRef ref, String id) {
  if (PaneScope.roleOf(context) == PaneRole.detail) {
    ref.read(paneSelectionProvider).choose(PaneTab.occasions, id);
  }
  context.go('/occasions/$id');
}

/// Abre la ficha de una persona (sus regalos), como al elegirla en Personas.
void openPersonGifts(BuildContext context, WidgetRef ref, String id) {
  if (PaneScope.roleOf(context) == PaneRole.detail) {
    ref.read(paneSelectionProvider).userChose(id);
  }
  context.go('/people/${Uri.encodeComponent(id)}');
}

/// Las ocasiones con una tarjeta en Presupuesto, con sus totales: todas las
/// activas (también las vacías, para poner ahí su primer presupuesto) en el
/// orden de [order] y después las archivadas que tienen presupuesto o algún
/// importe por nombre: no suman en el total, pero su fila conserva sus cifras
/// históricas.
List<({Occasion occasion, BudgetTotals totals})> budgetOccasions(
  Budget budget,
  Iterable<Occasion> order,
  Iterable<Occasion> all,
) {
  // Las activas, en el orden dado; las archivadas (de [order] o de [all]) al
  // final, sin repetir, por nombre.
  final active = [
    for (final o in order)
      if (!o.archived) o,
  ];
  final archived =
      <String, Occasion>{
        for (final o in [...order, ...all])
          if (o.archived) o.id: o,
      }.values.toList()..sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : a.id.compareTo(b.id);
      });
  return [
    for (final o in [...active, ...archived])
      if (!o.archived || _hasAmount(budget.ofOccasion(o.id)))
        (occasion: o, totals: budget.ofOccasion(o.id)),
  ];
}

bool _hasAmount(BudgetTotals totals) =>
    totals.budgetCents != null ||
    totals.plannedCents > 0 ||
    totals.spentCents > 0 ||
    totals.pendingCents > 0;

/// Los totales de los regalos sin ocasión (también los de una ocasión que se
/// borró), o `null` si no tienen ningún importe.
BudgetTotals? budgetWithoutOccasion(Budget budget) {
  final totals = budget.byOccasion[Budget.noOccasion];
  return totals == null || !_hasAmount(totals) ? null : totals;
}
