// Generaciones v2 en este móvil (ADR 0004, «Cupos, generaciones y
// renovación»; revisión de la fase 2b, hallazgos 2 y 7).
//
// - Instalar una generación (migrar, unirse, renovar) pasa siempre por un
//   pendiente ([PendingV2]) escrito antes de tocar el documento o la clave:
//   si se corta, [finishPendingV2] lo termina con la misma clave y el mismo
//   `syncId`, y la identidad v2 va la última.
// - [startNewGenerationV2] es el flujo mínimo de renovación: cuando la lista
//   del servidor ya no está (se borró o caducó: su `syncId` no vuelve) o este
//   móvil sale de la familia, se estrena aquí un `syncId`, una clave de la
//   familia y un registro con solo la ficha de este móvil. Lo de la lista se
//   queda; no se sube nada hasta volver a conectar otro móvil en persona. La
//   interfaz completa de renovación es de la fase 3.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/access_policy.dart' show SurpriseKeyring;
import '../../../core/sync/device_keys.dart' show constantTimeEquals;
import '../../../core/sync/device_registry.dart';
import '../../../core/sync/pairing_v2.dart';
import '../../../core/sync/protected_doc.dart'
    show SlotSet, ownGiftsWereHidden, purgeOwnGiftsOnLeaving;
import '../../family/application/family_controller.dart';
import '../../family/data/device_keys_store.dart';
import '../../family/data/family_store.dart';
import '../../family/data/generation_store.dart';
import 'family_snapshot.dart';
import 'migration_v2.dart';
import 'sync_v2_engine.dart';

/// Termina la generación v2 que quedó a medias, si la hay. Devuelve si había
/// una (y se ha terminado o descartado).
///
/// Un pendiente sobre un documento que sigue en v1 (la migración se cortó
/// antes de guardar el documento) se descarta: la migración empieza otra
/// vez entera, con clave nueva.
Future<bool> finishPendingV2(Ref ref) async {
  final store = ref.read(familyStoreProvider);
  final raw = await store.readPendingV2();
  if (raw == null) return false;
  final pending = PendingV2.fromJson(raw);
  final fam = await familySnapshot(ref);
  final identity = fam.identity;
  if (pending == null ||
      identity == null ||
      (!pending.reset && syncProtocolOf(fam.doc) != kSyncProtocolV2)) {
    if (pending != null && pending.pairing) {
      // Un invitado que se cortó antes del documento (B7): se deshace lo que
      // escribió y se abandona la credencial, que el anfitrión ya registró
      // (si no, volver a emparejar daría `credential_exists`). Queda un
      // dispositivo fantasma que el anfitrión tiene que quitar.
      await store.discardPairingInstall();
      await rotateServiceCredential(ref);
    }
    await store.savePendingV2(null);
    return true;
  }
  final keysStore = ref.read(deviceKeysStoreProvider);
  final keys = await keysStore.read() ?? await keysStore.create();
  Future<DeviceRegistry> own() async =>
      DeviceRegistry.empty(identity.listId).withRecord(
        await DeviceRecord.create(
          keys: keys,
          listId: identity.listId,
          deviceId: identity.node,
          personId: identity.selfRecipientId,
        ),
      );
  var doc = fam.doc;
  if (pending.reset) {
    // 1.0.6: sin nadie más, este móvil vuelve a ver lo suyo. Antes se quitan
    // del común de la generación nueva los regalos para su persona que la
    // protección aún no había pasado al bloque secreto (nunca se pintaron
    // aquí). Este común no sube a la lista de la familia: es otra generación.
    final previous = await store.readRegistry();
    // La ficha más reciente de este móvil (un cambio de persona pendiente).
    DeviceRecord? previousSelf;
    for (final r in previous?.records ?? const <DeviceRecord>[]) {
      if (r.deviceId == identity.node &&
          (previousSelf == null || r.seq > previousSelf.seq)) {
        previousSelf = r;
      }
    }
    final people = [
      identity.selfRecipientId,
      previousSelf?.personId,
      ...identity.formerSelf,
      // Las de todas las fichas de este móvil, como la capa de pantalla con
      // un cambio pendiente (revisión de seguridad, B4).
      for (final r in previous?.records ?? const <DeviceRecord>[])
        if (r.deviceId == identity.node) r.personId,
    ];
    doc = purgeOwnGiftsOnLeaving(
      doc,
      node: identity.node,
      people: people,
      // La misma regla que la capa de pantalla: dos dispositivos de la misma
      // persona, sin nadie más, no se ocultaban nada y no se purga.
      hadCompany: ownGiftsWereHidden(
        registry: previous,
        me: identity.node,
        people: people,
        paired: identity.paired,
      ),
    );
    await store.disableRemoteSync();
    await store.savePendingInviteAcknowledgement(null);
    await store.setRecoveryRemovalPending(false);
    // Nada de la generación anterior: ni sus fichas, ni sus slots, ni sus
    // claves de sorpresa, ni lo que recordaba del servidor. Los ámbitos
    // locales se quedan y se vuelven a sellar con las claves nuevas.
    await store.saveRegistry(await own());
    await store.saveSyncV2State(const V2SyncState().toJson());
    await store.saveSlots(SlotSet.empty);
    await keysStore.saveKeyring(identity.listId, SurpriseKeyring.empty);
  } else if (await store.readRegistry() == null) {
    await store.saveRegistry(await own());
  }
  final family = ref.read(familyControllerProvider.notifier);
  await family.installV2(
    listId: identity.listId,
    node: identity.node,
    key: pending.key,
    doc: doc,
  );
  if (pending.reset) await family.markUnpaired();
  // Un invitado que entró tras el corte (B7) nace con la marca: antes de la
  // identidad, para que ninguna vuelta abra nunca un formato 1.
  if (pending.commonFormat > 1) {
    await store.raiseCommonFormatFloor(pending.commonFormat);
  }
  await store.saveSyncV2(
    SyncIdentityV2(
      listId: identity.listId,
      deviceId: identity.node,
      syncId: pending.syncId,
      migratedFromV1: pending.fromV1,
    ),
  );
  await store.savePendingV2(null);
  return true;
}

/// Cambia la credencial de servicio de las claves guardadas por una nueva
/// (B7, M3), si es [used] (o siempre, sin [used]). Devuelve si la cambió.
Future<bool> rotateServiceCredential(Ref ref, {List<int>? used}) async {
  final keysStore = ref.read(deviceKeysStoreProvider);
  final keys = await keysStore.read();
  if (keys == null) return false;
  if (used != null && !constantTimeEquals(keys.serviceCredential, used)) {
    return false;
  }
  await keysStore.restore(await keys.withNewServiceCredential());
  return true;
}

/// Estrena una generación v2 en este móvil: `syncId`, clave de la familia y
/// registro nuevos, sin otros móviles. No hace nada si la familia no está en
/// v2.
Future<void> startNewGenerationV2(Ref ref) async {
  final store = ref.read(familyStoreProvider);
  final current = await store.readSyncV2();
  if (current == null) return;
  final generations = ref.read(generationStoreProvider);
  final family = ref.read(familyControllerProvider.notifier);
  // QA 1.0.6, M1 (B1 y B2): quién podrá volver se decide con la generación
  // que se deja, antes de tirar su llavero, su registro y `formerSelf`. Vale
  // para los dos caminos: `startLocalGeneration` y el reinicio de
  // [finishPendingV2]. Un reinicio que se reanuda tras un cierre no tiene
  // plan y no restaura nada (como antes: vuelve al conectar otro móvil).
  final plan = await family.planAloneRestoreWithinLock();
  if (await generations.activeSyncId() != null) {
    await generations.startLocalGeneration();
    await family.reloadStoredCandidate();
  } else {
    final pending = await PendingV2.fresh(
      fromV1: current.migratedFromV1,
      reset: true,
    );
    await store.savePendingV2(pending.toJson());
    await finishPendingV2(ref);
  }
  // QA 1.0.6, M1: solo, sigue viendo y editando las sorpresas de los demás
  // que ya tenía; las de su persona no vuelven. De mejor esfuerzo (B3): con
  // la generación ya estrenada, un fallo aquí no hace fallar a quien llama.
  try {
    await family.restoreOthersSecretsWhenAloneWithinLock(plan);
  } on Object {
    // Vuelve al conectar otro móvil.
  }
}
