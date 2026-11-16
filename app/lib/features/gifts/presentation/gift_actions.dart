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
import '../../family/application/family_controller.dart';
import '../application/delivered_arm.dart';
import '../application/person_completion.dart';

/// Lo que pasa al tocar la casilla de un regalo: avanza al siguiente estado y
/// avisa con un «Deshacer». Si ya está entregado, abre el selector.
Future<void> advanceGiftStatus(
  BuildContext context,
  WidgetRef ref,
  Gift gift,
) async {
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
    showRegalosSnackBar(context, SnackBar(content: Text(l10n.giftNotSaved)));
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

/// Abre el selector con los seis estados y aplica el que se toque.
Future<void> showGiftStatusPicker(
  BuildContext context,
  WidgetRef ref,
  Gift gift,
) async {
  final controller = ref.read(familyControllerProvider.notifier);
  final haptics = ref.read(hapticsProvider);
  final arrival = context.hapticArrival;
  final chosen = await showRegalosSheet<GiftStatus>(
    context,
    builder: (sheetContext) {
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
                  l10n.giftStatusPickerTitle(gift.title),
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
                      selected: status == gift.status,
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
