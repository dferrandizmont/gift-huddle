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

import '../../../core/sync/device_keys.dart' show constantTimeEquals;
import '../../family/application/family_controller.dart';
import '../../family/data/device_keys_store.dart';
import '../../family/data/family_store.dart';
import '../../family/data/generation_store.dart';
import 'migration_v2.dart';

/// Termina la generación v2 que quedó a medias, si la hay. Devuelve si había
/// una (y se ha terminado o descartado).
///
/// Un pendiente sobre un documento que sigue en v1 (la migración se cortó
/// antes de guardar el documento) se descarta: la migración empieza otra
/// vez entera, con clave nueva.
Future<bool> finishPendingV2(Ref ref) => ref
    .read(familyControllerProvider.notifier)
    .finishPendingV2(
      rotatePairingCredential: () => rotateServiceCredential(ref),
    );

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
    await family.switchStoredGenerationWithinLock(
      generations.startLocalGeneration,
    );
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
