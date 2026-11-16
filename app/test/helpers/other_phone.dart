import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/family_controller.dart';

import 'memory_stores.dart';

/// Otro móvil de la familia cambia el documento y el cambio llega a [phone]
/// mezclado, como al sincronizar.
///
/// Para lo que este móvil no deja hacer aquí: archivar o eliminar a la
/// persona que es «Yo».
Future<void> changedElsewhere(
  FakePhone phone,
  FamilyDoc Function(FamilyDoc doc, HlcClock clock) change,
) async {
  final doc = (await phone.container.read(familyControllerProvider.future)).doc;
  await phone.container
      .read(familyControllerProvider.notifier)
      .mergeRemote(
        change(doc, HlcClock(node: 'remoto', last: doc.maxStamp)),
        fromNode: 'remoto',
      );
}

/// Otro móvil elimina a la persona [recipientId].
Future<void> deletedElsewhere(FakePhone phone, String recipientId) =>
    changedElsewhere(
      phone,
      (doc, clock) => doc.delete(clock, Collections.recipients, recipientId),
    );

/// Otro móvil archiva a la persona [recipientId].
Future<void> archivedElsewhere(FakePhone phone, String recipientId) =>
    changedElsewhere(
      phone,
      (doc, clock) => doc.set(clock, Collections.recipients, recipientId, {
        'archived': true,
      }),
    );
