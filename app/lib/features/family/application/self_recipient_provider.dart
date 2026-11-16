import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/model.dart';
import 'family_controller.dart';
import 'family_providers.dart';

/// «Yo» (ADR 0004): el id estable de la persona dueña de este móvil, o `null`
/// si no se ha elegido.
///
/// Es local: sale de la identidad guardada de este móvil
/// (`FamilyIdentity.selfRecipientId`), nunca del documento compartido, y no
/// da permisos. Si la persona elegida se elimina (aquí o desde otro móvil),
/// vale `null` enseguida y la elección guardada se quita sola. Una persona
/// archivada sigue siendo «Yo».
class SelfRecipient extends Notifier<String?> {
  @override
  String? build() {
    final family = ref.watch(familyStateProvider);
    final stored = family?.identity?.selfRecipientId;
    if (family == null || stored == null) {
      return null;
    }
    final record = family.doc.record(Collections.recipients, stored);
    if (record != null && !record.isDeleted) {
      return stored;
    }
    // La persona ya no existe y una lápida no vuelve: se limpia lo guardado.
    // Si falla el guardado no pasa nada: sigue valiendo `null` y se
    // reintenta la próxima vez que cambie la familia.
    unawaited(
      Future<void>.microtask(() async {
        if (!ref.mounted) {
          return;
        }
        try {
          await ref
              .read(familyControllerProvider.notifier)
              .setSelfRecipient(null);
        } on Object {
          // Ver arriba.
        }
      }),
    );
    return null;
  }

  /// Elige de quién es este móvil; `null` lo deja sin nadie.
  ///
  /// Pasa por `changeSelfPerson`: en una familia v2 el cambio publica una
  /// ficha nueva y este móvil espera a que otro lo apruebe
  /// ([ChangeSelfPersonResult.pendingApproval]); sin familia v2 solo cambia
  /// la identidad local. Al elegir a alguien se quitan del llavero de este
  /// móvil sus claves de sorpresa. Lanza [SelfPersonSequenceExhaustedException]
  /// si ya no puede cambiar de persona, y lo que lance el guardado.
  Future<ChangeSelfPersonResult> choose(String? recipientId) =>
      ref.read(familyControllerProvider.notifier).changeSelfPerson(recipientId);
}

/// El id de «Yo», o `null`. Para marcar a esa persona (Reparto) basta con
/// compararlo con el id de cada una.
final selfRecipientIdProvider = NotifierProvider<SelfRecipient, String?>(
  SelfRecipient.new,
);

/// La persona de «Yo» con su nombre y su color, o `null`.
final selfRecipientProvider = Provider<Recipient?>((ref) {
  final id = ref.watch(selfRecipientIdProvider);
  if (id == null) {
    return null;
  }
  for (final recipient in ref.watch(familyFullViewProvider).recipients) {
    if (recipient.id == id) {
      return recipient;
    }
  }
  return null;
});
