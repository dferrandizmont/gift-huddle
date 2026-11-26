import '../../family/presentation/giver_person_flow.dart';
import '../../web_device/application/web_app_provider.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/haptics.dart';
import '../../../core/motion/sheet_motion.dart';
import '../../../core/sync/model.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/choice_grid.dart';
import '../../../core/widgets/gift_status_l10n.dart';
import '../../../core/widgets/gift_status_map.dart';
import '../../../core/widgets/regalos_snack_bar.dart';
import '../../../core/widgets/status_checkbox.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/sync/wish_plan.dart';
import '../../family/application/family_controller.dart';
import '../../family/application/family_providers.dart';
import '../../family/application/wish_service.dart';
import '../application/delivered_arm.dart';
import '../application/person_completion.dart';
import 'wish_editor.dart' show showWishProblem;

/// Lo que pasa al tocar la casilla de un regalo: avanza al siguiente estado y
/// avisa con un «Deshacer». Si ya está entregado, abre el selector.
Future<void> advanceGiftStatus(
  BuildContext context,
  WidgetRef ref,
  Gift gift,
) async {
  // Un deseo que alguien ha cogido se ve como un regalo, pero su estado vive
  // en su plan (ADR 0010).
  final plan = ref.read(wishPlanOfGiftProvider(gift.id));
  if (plan != null) return advancePlanStatus(context, ref, plan);
  final next = gift.status.next;
  if (next == null) {
    await showGiftStatusPicker(context, ref, gift);
    return;
  }
  final controller = ref.read(familyControllerProvider.notifier);
  final l10n = AppLocalizations.of(context);
  final previous = gift.status;
  // Solo lo que hace la persona lleva háptica: un toque ligero al avanzar y
  // uno medio al entregar, cuando el sector de la casilla termina de barrer.
  // El dato se guarda al momento; la animación solo lo cuenta.
  final haptics = ref.read(hapticsProvider);
  final arrival = context.hapticArrival;
  if (next == GiftStatus.delivered) {
    haptics.medium(after: arrival);
  } else {
    haptics.light(after: arrival);
  }
  // Una acción del usuario puede completar a la persona: arma la celebración
  // antes de guardar para que la cabecera la distinga de una sincronización.
  ref.read(celebrationArmedProvider.notifier).arm(gift.recipientId);
  if (next == GiftStatus.delivered) {
    ref.read(deliveredArmsProvider).arm(gift.id);
  }
  final saved = await controller.setGiftStatus(gift.id, next);
  if (!context.mounted) {
    return;
  }
  if (!saved) {
    // Otro móvil lo borró: se avisa en vez de contar un cambio que no existe.
    showRegalosSnackBar(
      context,
      SnackBar(
        content: Text(giftNotSavedText(l10n, web: ref.read(webAppProvider))),
      ),
    );
    return;
  }
  showRegalosSnackBar(
    context,
    SnackBar(
      // Con acción, Flutter la deja fija hasta que se toca: que se vaya sola.
      persist: false,
      duration: const Duration(seconds: 4),
      content: Text(
        l10n.giftStatusChanged(gift.title, next.visualStatus.label(l10n)),
      ),
      action: SnackBarAction(
        label: l10n.actionUndo,
        onPressed: () {
          haptics.light(after: arrival);
          controller.setGiftStatus(gift.id, previous);
        },
      ),
    ),
  );
}

/// Lado de la forma del estado en una celda de `ChoiceGrid`, y su hueco con
/// el nombre: los del editor.
const double kStatusChoiceGlyph = 16;
const double kStatusChoiceGap = 5;

/// La celda de [status] para un `ChoiceGrid` (con `leadingSize`
/// [kStatusChoiceGlyph] y `leadingGap` [kStatusChoiceGap]): su forma y su
/// nombre, como en el editor de regalo.
ChoiceGridItem statusChoice(
  AppLocalizations l10n,
  GiftStatus status, {
  required bool selected,
  required VoidCallback onTap,
}) => ChoiceGridItem(
  label: status.visualStatus.label(l10n),
  leading: (color, selected) => StatusGlyph(
    status: status.visualStatus,
    size: kStatusChoiceGlyph,
    // Sobre el relleno de la elegida el trazo de serie apenas se ve.
    stroke: selected ? color : null,
  ),
  selected: selected,
  onTap: onTap,
);

/// Abre el selector con los seis estados de [title] y devuelve el elegido.
Future<GiftStatus?> _pickStatus(
  BuildContext context,
  String title,
  GiftStatus current, {
  void Function(BuildContext sheetContext)? onBuilt,
  bool Function()? authorized,
}) {
  var dismissed = false;
  return showRegalosSheet<GiftStatus>(
    context,
    builder: (sheetContext) {
      // Si en el primer pintado ya no se puede enseñar (le quitaron el acceso
      // entre la pulsación larga y la hoja), no se pinta nada y se cierra.
      if (authorized != null && !authorized()) {
        if (!dismissed) {
          dismissed = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
          });
        }
        return const SizedBox.shrink();
      }
      onBuilt?.call(sheetContext);
      final l10n = AppLocalizations.of(sheetContext);
      final t = RegalosTokens.of(sheetContext);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.giftStatusPickerTitle(title),
                  style: t.styles.screenTitleSmall,
                ),
              ),
              const SizedBox(height: 12),
              // La misma rejilla que el estado en el editor.
              ChoiceGrid(
                leadingSize: kStatusChoiceGlyph,
                leadingGap: kStatusChoiceGap,
                items: [
                  for (final status in GiftStatus.values)
                    statusChoice(
                      l10n,
                      status,
                      selected: status == current,
                      onTap: () => Navigator.of(sheetContext).pop(status),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Si quien mira en este dispositivo es quien cogió el plan: solo esa persona
/// lo cambia (ADR 0010).
bool _isClaimant(WidgetRef ref, WishPlan plan) {
  final reader = ref.read(wishReaderProvider);
  return reader != null && reader == plan.claimantPersonId;
}

/// Lo que pasa al tocar la casilla de un deseo cogido: avanza el estado de su
/// plan y avisa con «Deshacer». Si ya está entregado, abre el selector.
Future<void> advancePlanStatus(
  BuildContext context,
  WidgetRef ref,
  WishPlan plan,
) async {
  // Solo quien lo ha cogido cambia su plan.
  if (!_isClaimant(ref, plan)) return;
  final next = plan.status.next;
  if (next == null) {
    await showPlanStatusPicker(context, ref, plan);
    return;
  }
  final l10n = AppLocalizations.of(context);
  final haptics = ref.read(hapticsProvider);
  final arrival = context.hapticArrival;
  if (next == GiftStatus.delivered) {
    haptics.medium(after: arrival);
  } else {
    haptics.light(after: arrival);
  }
  final service = ref.read(wishServiceProvider);
  final previous = plan.status;
  final result = await service.editPlan(
    plan.recipientId,
    plan.planId,
    PrivatePlanPatch(status: next),
  );
  if (!context.mounted) return;
  if (!result.ok) {
    showWishProblem(context, ref, result);
    return;
  }
  showRegalosSnackBar(
    context,
    SnackBar(
      persist: false,
      duration: const Duration(seconds: 4),
      content: Text(
        l10n.giftStatusChanged(plan.title, next.visualStatus.label(l10n)),
      ),
      action: SnackBarAction(
        label: l10n.actionUndo,
        onPressed: () {
          haptics.light(after: arrival);
          service.editPlan(
            plan.recipientId,
            plan.planId,
            PrivatePlanPatch(status: previous),
          );
        },
      ),
    ),
  );
}

/// Abre el selector de estado de un deseo cogido y aplica el que se toque.
Future<void> showPlanStatusPicker(
  BuildContext context,
  WidgetRef ref,
  WishPlan plan,
) async {
  if (!_isClaimant(ref, plan)) return;
  // El selector enseña el título y el estado del plan: si este dispositivo
  // deja de ver el plan (le quitan el acceso al bloque, o se soltó en otro
  // móvil) o no sabe si lo ve (la proyección se recalcula o falla), con el
  // selector abierto, se cierra sin aplicar nada. La web no depende de la
  // proyección del móvil.
  final container = ProviderScope.containerOf(context);
  final web = container.read(webAppProvider);
  bool uncertain() {
    final projection = container.read(authorizedProjectionProvider);
    return !web && (projection.isLoading || projection.hasError);
  }

  bool live() => container
      .read(wishPlanStateRowsProvider(plan.recipientId))
      .where((r) => r.sourceWishId == plan.sourceWishId)
      .any((r) => r.plans.any((p) => p.planId == plan.planId));
  if (uncertain()) return;
  bool authorized() => live() && !uncertain();
  BuildContext? sheetContext;
  void closeIfUnseen() {
    final sheet = sheetContext;
    if ((!live() || uncertain()) && sheet != null && sheet.mounted) {
      sheetContext = null;
      Navigator.of(sheet).pop();
    }
  }

  final rowsSubscription = container.listen<List<WishPlanRow>>(
    wishPlanStateRowsProvider(plan.recipientId),
    (_, _) => closeIfUnseen(),
  );
  final projectionSubscription = container.listen(
    authorizedProjectionProvider,
    (_, _) => closeIfUnseen(),
  );
  final GiftStatus? chosen;
  try {
    chosen = await _pickStatus(
      context,
      plan.title,
      plan.status,
      onBuilt: (c) => sheetContext = c,
      authorized: authorized,
    );
  } finally {
    rowsSubscription.close();
    projectionSubscription.close();
  }
  if (chosen == null || chosen == plan.status || !context.mounted) return;
  final result = await ref
      .read(wishServiceProvider)
      .editPlan(
        plan.recipientId,
        plan.planId,
        PrivatePlanPatch(status: chosen),
      );
  if (!result.ok && context.mounted) showWishProblem(context, ref, result);
}

/// Abre el selector con los seis estados y aplica el que se toque.
Future<void> showGiftStatusPicker(
  BuildContext context,
  WidgetRef ref,
  Gift gift,
) async {
  final plan = ref.read(wishPlanOfGiftProvider(gift.id));
  if (plan != null) return showPlanStatusPicker(context, ref, plan);
  final controller = ref.read(familyControllerProvider.notifier);
  final haptics = ref.read(hapticsProvider);
  final arrival = context.hapticArrival;
  final chosen = await _pickStatus(context, gift.title, gift.status);
  if (chosen != null && chosen != gift.status) {
    // Elegir en la rejilla ya dio su toque de selección: solo entregar,
    // que es lo importante, añade uno medio cuando la casilla termina de
    // barrer (el servicio se lee antes de esperar, no con `ref` después).
    if (chosen == GiftStatus.delivered) {
      haptics.medium(after: arrival);
    }
    ref.read(celebrationArmedProvider.notifier).arm(gift.recipientId);
    if (chosen == GiftStatus.delivered) {
      ref.read(deliveredArmsProvider).arm(gift.id);
    }
    await controller.setGiftStatus(gift.id, chosen);
  }
}
