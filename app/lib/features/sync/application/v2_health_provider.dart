import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/protected_doc.dart';
import '../../../core/sync/model.dart' show Collections;
import '../../family/data/device_keys_store.dart';
import 'app_sync_v2_local.dart';
import 'sync_controller.dart';
import 'v2_health.dart';

export 'v2_health.dart';

/// Estado persistente para los avisos de la interfaz. Funciona sin red y se
/// actualiza con cada invalidación del registro al acabar una vuelta v2.
final v2HealthProvider = FutureProvider<V2Health>((ref) async {
  final view = await ref.watch(localRegistryViewProvider.future);
  if (view == null) return V2Health();
  final local = await AppSyncV2Local.load(ref);
  if (local == null) return V2Health();
  final observed = (await local.readState()).health;
  final keyring = await ref
      .read(deviceKeysStoreProvider)
      .readKeyring(view.listId);
  final slots = await local.slots();
  final common = await local.common();
  final frozen = <String>{};
  final writers = <String>{};
  for (final person in keyring.people) {
    if (person == view.self.personId ||
        common.record(Collections.recipients, person)?.isDeleted == true) {
      continue;
    }
    if ((observed?.revokedByOthers ?? false) || !view.selfEntitled(person)) {
      frozen.add(person);
      continue;
    }
    final opened = await openScope(
      personId: person,
      slots: slots,
      keyring: keyring,
      view: view,
    );
    // SlotHeader.writer y OpenedScope.frozenWriters son ids de móvil.
    writers.addAll(opened?.frozenWriters ?? const <String>[]);
  }
  return V2Health(
    frozenPeople: frozen,
    // Mientras este móvil espera la aprobación de otro, el aviso nombra a la
    // persona que ha elegido (1.0.6, QA m4), no a la de quien lo invitó.
    pendingSelfPerson: view.selfApproved ? null : (view.self.personId ?? ''),
    revokedByOthers:
        view.revokedByOthers || (observed?.revokedByOthers ?? false),
    unbackedCredentials: observed?.unbackedCredentials ?? const [],
    departedDevices: {
      for (final id in observed?.departedDevices ?? const <String>{})
        if (view.member(id) != null) id,
    },
    frozenWriterDeviceIds: writers,
    renewSuggested: observed?.renewSuggested ?? false,
    writerSlotsFull: observed?.writerSlotsFull ?? false,
    commonBlocked: observed?.commonBlocked ?? false,
    commonBlockedWriter: observed?.commonBlockedWriter,
    commonPackagesFull: observed?.commonPackagesFull ?? false,
    commonKeyringFull: observed?.commonKeyringFull ?? false,
    retainedCommons: observed?.retainedCommons ?? 0,
  );
});
