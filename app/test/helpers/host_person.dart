import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/family_controller.dart';

import 'memory_stores.dart';

/// La persona de los móviles que las pruebas conectan sin que importe de
/// quién son (1.0.6: ningún móvil entra sin persona). Solo regala: no tiene
/// regalos, no se protege y no oculta nada.
const String kGuestGiver = 'leo-solo';

/// 1.0.6: para invitar a otro dispositivo, el móvil que invita tiene que ser
/// de una persona («¿Quién eres?»). Si [phone] tiene familia y todavía no es
/// de nadie, lo hace de [id] (y da de alta a esa persona si no existe). En
/// un móvil solo cuya ficha no ha salido de él no necesita aprobación.
/// También da de alta a [kGuestGiver], para los invitados.
Future<void> hostWithPerson(
  FakePhone phone, {
  String id = 'aritz',
  String name = 'Aritz',
}) async {
  final family = await phone.container.read(familyControllerProvider.future);
  final identity = family.identity;
  if (identity == null) return;
  final controller = phone.container.read(familyControllerProvider.notifier);
  if (family.doc.record(Collections.recipients, kGuestGiver) == null) {
    await controller.upsertRecipient(
      const Recipient(
        id: kGuestGiver,
        name: 'Leo',
        colorIndex: 1,
        archived: false,
        inReparto: false,
        noGifts: true,
      ),
    );
  }
  if (identity.selfRecipientId != null) return;
  final record = family.doc.record(Collections.recipients, id);
  if (record == null) {
    await controller.upsertRecipient(
      Recipient(id: id, name: name, colorIndex: 0, archived: false),
    );
  } else if (record.isDeleted) {
    return;
  }
  await controller.changeSelfPerson(id);
}
