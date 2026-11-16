// Aprobar un móvil y ver qué pasaría al quitar otro (ADR 0004, fase 3, lote
// «Móviles»), en Dart puro sobre `SyncV2Local`. Aparte de `family_devices.dart`
// (que es la API de salir y quitar). Quien las llama (SyncController) las
// ejecuta dentro de `v2FamilyLockProvider`.
library;

import '../../../core/sync/device_registry.dart';
import '../data/sync_transport_v2.dart';
import 'family_devices.dart' show localView;
import 'sync_v2_engine.dart';

/// Lo que pasaría al quitar un móvil, sin hacerlo.
class RemovalPreview {
  /// Crea la vista previa.
  const RemovalPreview({required this.selfWouldWait, required this.orphans});

  /// Si el móvil que se quita es el único activo que aprobó la ficha actual
  /// de este (N7): al quitarlo, este móvil volvería a esperar aprobación.
  final bool selfWouldWait;

  /// Móviles que dejarían de estar enlazados a este y habría que confirmar
  /// uno a uno.
  final List<KnownDevice> orphans;
}

/// Calcula, sin guardar nada ni hablar con el servidor, qué pasaría al
/// quitar [deviceId]: hace la revocación en memoria y vuelve a leer el
/// registro. Lanza [RegistryException] si ese móvil no se puede revocar (es
/// este, o no existe).
Future<RemovalPreview> previewRemoval({
  required SyncV2Local local,
  required String deviceId,
}) async {
  if (deviceId == local.identity.deviceId) {
    throw const RegistryException('para este móvil, salir de la familia');
  }
  final view = await localView(local);
  final change = await revokeDevice(
    registry: await local.registry(),
    view: view,
    myKeys: local.keys,
    deviceId: deviceId,
  );
  final after = await change.registry.viewFor(
    me: view.me,
    mySigningKey: local.keys.publicKeys.signing,
    livePeople: view.livePeople,
  );
  return RemovalPreview(
    selfWouldWait: view.selfApproved && !after.selfApproved,
    orphans: change.orphans,
  );
}

/// Al quitar, la situación cambió desde que se enseñó el aviso (este móvil
/// pasaría a esperar aprobación y no se había aceptado): hay que volver a
/// preguntar.
class DeviceRemovalChangedException implements Exception {
  /// Crea el error.
  const DeviceRemovalChangedException();

  @override
  String toString() => 'DeviceRemovalChangedException';
}

/// Mensaje de la [RegistryException] cuando la ficha del móvil ya no es la
/// que se enseñó.
const kRecordChangedMessage = 'la ficha ha cambiado';

KnownDevice? _find(RegistryView view, String deviceId) {
  final known = view.device(deviceId);
  if (known != null) return known;
  for (final d in view.detached) {
    if (d.deviceId == deviceId) return d;
  }
  return null;
}

/// Este móvil aprueba a [deviceId] («este móvil es de Q», confirmado por una
/// persona en la pantalla): firma un aval de su ficha, lo guarda y publica el
/// registro con una vuelta. Uno a uno: nunca aprueba más que el móvil que se
/// pide.
///
/// La ficha es la actual de ese móvil en el registro (activo, pendiente o
/// que cuelga de uno revocado y nos avaló). Un huérfano que ya no sale en la
/// vista tras quitar otro móvil se aprueba con [recordDigest], el de la
/// ficha que se mostró; solo vale si esa ficha está en el registro local
/// verificado y es de [deviceId].
///
/// Si llega [recordDigest] y la ficha actual del móvil es otra, lanza
/// [RegistryException] con [kRecordChangedMessage]: el aval va ligado a lo que
/// se enseñó. Si la vuelta falla después de guardar el aval (cualquier
/// error, no solo de red), el aval ya está guardado y saldrá en la siguiente.
/// Lanza [RegistryException] si el móvil no se puede aprobar (es este, está
/// revocado o no hay ficha suya).
Future<RegistryChange> approveFamilyDevice({
  required SyncV2Transport transport,
  required SyncV2Local local,
  required String deviceId,
  String? recordDigest,
}) async {
  final registry = await local.registry();
  final view = await localView(local);
  final known = _find(view, deviceId);
  // Lo que se avala es la ficha que la persona vio en la pantalla: si el móvil
  // ha publicado otra entre tanto, no se avala (hay que volver a mirarla).
  if (recordDigest != null &&
      known != null &&
      known.recordDigest != recordDigest) {
    throw const RegistryException(kRecordChangedMessage);
  }
  final digest = known?.recordDigest ?? recordDigest;
  final record = digest == null ? null : registry.recordByDigest(digest);
  if (record == null || record.deviceId != deviceId) {
    throw const RegistryException('no hay ficha de ese móvil');
  }
  final change = await approveDevice(
    registry: registry,
    view: view,
    myKeys: local.keys,
    record: record,
  );
  await local.saveRegistry(change.registry);
  try {
    await SyncV2Engine(transport: transport, local: local).sync();
  } on Object {
    // El aval está guardado: la siguiente vuelta lo publica.
  }
  return change;
}
