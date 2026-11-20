import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/model.dart';
import '../../../core/sync/protected_doc.dart' show ProtectedPersonException;
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/regalos_snack_bar.dart';
import '../../../l10n/app_localizations.dart';
import '../application/family_controller.dart';

// Una persona de la familia como «quién regala»: la sección «Personas» de los
// selectores, el paso explícito de un regalo secreto y la asignación.

/// Las personas que se ofrecen en la sección «Personas» de un selector: las
/// que aún no tienen un quién regala activo (las que ya lo tienen salen entre
/// los quién regala de siempre).
List<GiverPersonCandidate> personSectionOf(
  List<GiverPersonCandidate> candidates,
) => [
  for (final candidate in candidates)
    if (candidate.giver == null || candidate.giver!.archived) candidate,
];

/// La frase bajo una persona de la sección: qué pasa al elegirla, o `null` si
/// solo se asigna.
String? personCandidateHint(AppLocalizations l10n, GiverPersonCandidate c) {
  if (c.needsPublicAdd) {
    return l10n.giverPeopleHintAdd;
  }
  return c.giver?.archived == true ? l10n.giverPeopleHintRecover : null;
}

/// Una pregunta con un botón de acción que no destruye nada: relleno del
/// acento, y «Cancelar» con contorno. Devuelve `true` solo si se confirma.
Future<bool> showRegalosAsk(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  required String cancelLabel,
}) async {
  final result = await showRegalosDialog<bool>(
    context,
    avoidKeyboard: false,
    builder: (dialogContext) {
      final t = RegalosTokens.of(dialogContext);
      return RegalosDialogSurface(
        scrollable: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: t.styles.screenTitleSmall),
            ),
            const SizedBox(height: 8),
            Text(body, style: t.styles.body),
            const SizedBox(height: 20),
            DialogButtonRow(
              cancelLabel: cancelLabel,
              confirmLabel: confirmLabel,
              cancel: OutlinedButton(
                style: regalosDialogCancelStyle(t),
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(cancelLabel),
              ),
              confirm: FilledButton(
                style: regalosDialogPrimaryStyle(t),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(confirmLabel),
              ),
            ),
          ],
        ),
      );
    },
  );
  return result ?? false;
}

/// Un aviso con un solo botón.
Future<void> showRegalosNotice(
  BuildContext context, {
  required String title,
  required String body,
  required String okLabel,
}) => showRegalosDialog<void>(
  context,
  avoidKeyboard: false,
  builder: (dialogContext) {
    final t = RegalosTokens.of(dialogContext);
    return RegalosDialogSurface(
      scrollable: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: t.styles.screenTitleSmall),
          ),
          const SizedBox(height: 8),
          Text(body, style: t.styles.body),
          const SizedBox(height: 20),
          FilledButton(
            style: regalosDialogPrimaryStyle(t),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(okLabel),
          ),
        ],
      ),
    );
  },
);

/// El paso explícito de un regalo secreto: explica por qué, y si se confirma
/// añade a [person] como quién regala para toda la familia. Devuelve su
/// registro, o `null` si se cancela o falla (con un aviso).
Future<Giver?> addPersonAsGiverExplicitly(
  BuildContext context,
  WidgetRef ref,
  Recipient person,
) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showRegalosAsk(
    context,
    title: l10n.giverPersonAddTitle(person.name),
    body: l10n.giverPersonAddBody(person.name),
    confirmLabel: l10n.giverPersonAddConfirm(person.name),
    cancelLabel: l10n.actionCancel,
  );
  if (!confirmed || !context.mounted) {
    return null;
  }
  Giver? giver;
  try {
    giver = await ref
        .read(familyControllerProvider.notifier)
        .addPersonAsGiver(person.id);
  } on Object {
    giver = null;
  }
  if (giver == null && context.mounted) {
    showRegalosSnackBar(
      context,
      SnackBar(content: Text(l10n.giverPersonAddFailed(person.name))),
    );
  }
  return giver;
}

/// Lo que dice el aviso de un guardado rechazado, según el motivo.
String giftWriteResultText(AppLocalizations l10n, GiftWriteResult result) =>
    switch (result) {
      GiftWriteResult.saved => '',
      GiftWriteResult.giftDeleted => l10n.giftNotSaved,
      GiftWriteResult.giftUnavailable => l10n.giftWriteGiftUnavailable,
      GiftWriteResult.recipientUnavailable => l10n.giftWriteRecipientGone,
      GiftWriteResult.invalidPair => l10n.giftWriteInvalidPair,
      GiftWriteResult.giverUnavailable => l10n.giftWriteGiverGone,
      GiftWriteResult.giverArchived => l10n.giftWriteGiverArchived,
      GiftWriteResult.giverPersonUnavailable => l10n.giftWritePersonGone,
      GiftWriteResult.giverPersonArchived => l10n.giftWritePersonArchived,
    };

/// Asigna [candidate] como quién regala [gift], al momento (Reparto). En un
/// regalo secreto pasa antes por el paso explícito. Devuelve el resultado de
/// la escritura, o `null` si la persona canceló.
Future<GiftWriteResult?> assignGiftToPerson(
  BuildContext context,
  WidgetRef ref, {
  required Gift gift,
  required GiverPersonCandidate candidate,
}) async {
  final controller = ref.read(familyControllerProvider.notifier);
  try {
    if (candidate.needsPublicAdd) {
      return await _addThenAssign(context, ref, gift, candidate.person);
    }
    return await controller.assignPersonAsGiver(gift.id, candidate.person.id);
  } on GiverPersonNeedsPublicAdd {
    // El regalo pasó a ser secreto mientras tanto.
    if (!context.mounted) {
      return null;
    }
    return _addThenAssign(context, ref, gift, candidate.person);
  } on ProtectedPersonException catch (error) {
    return error.savedLocally
        ? GiftWriteResult.saved
        : GiftWriteResult.giftUnavailable;
  }
}

Future<GiftWriteResult?> _addThenAssign(
  BuildContext context,
  WidgetRef ref,
  Gift gift,
  Recipient person,
) async {
  final giver = await addPersonAsGiverExplicitly(context, ref, person);
  if (giver == null) {
    return null;
  }
  try {
    return await ref
        .read(familyControllerProvider.notifier)
        .assignPersonAsGiver(gift.id, person.id);
  } on GiverPersonNeedsPublicAdd {
    return GiftWriteResult.giftUnavailable;
  } on ProtectedPersonException catch (error) {
    return error.savedLocally
        ? GiftWriteResult.saved
        : GiftWriteResult.giftUnavailable;
  }
}
