// Los móviles de la familia v2 (ADR 0004): salir de la familia desde este
// móvil, quitar otro móvil y saber qué personas tienen móvil. La interfaz es
// de la fase 3; esto es la API, en Dart puro.
library;

import '../../../core/sync/access_policy.dart' show livePeopleOf;
import '../../../core/sync/device_registry.dart';
import '../../../core/sync/device_names.dart';
import '../../../core/sync/family_doc.dart';
import '../data/sync_transport_v2.dart';
import 'sync_v2_engine.dart';

/// Las personas que tienen un móvil activo en la familia según [view]
/// (también este móvil, si tiene persona).
Set<String> devicePersonIds(RegistryView view) => {
  for (final id in view.members)
    if (view.member(id)!.personId case final String person) person,
};

/// Si alguna ficha activa del registro (de otro móvil o de este) es de
/// [recipientId]: esa persona no se puede archivar ni eliminar mientras
/// tenga móvil.
bool isDevicePerson(RegistryView view, String recipientId) =>
    devicePersonIds(view).contains(recipientId);

/// Una fila de la lista «Conectados» de Móviles de la familia (v2): un móvil
/// activo del registro firmado.
class FamilyDeviceRow {
  /// Crea la fila.
  const FamilyDeviceRow({
    required this.deviceId,
    required this.isSelf,
    this.personId,
    this.deviceName,
    this.isWeb = false,
  });

  /// Id del móvil.
  final String deviceId;

  /// Si es una web (el navegador de un ordenador emparejado como un
  /// dispositivo más) y no un móvil.
  final bool isWeb;

  /// Si es este móvil.
  final bool isSelf;

  /// Persona dueña según la ficha firmada del móvil, o null si se unió con
  /// «Elegir después».
  final String? personId;

  /// Nombre local o recibido en el documento común cifrado; null hasta llegar.
  final String? deviceName;
}

/// Los móviles activos de [view] como filas: este primero y luego los demás
/// por nombre (y, a igualdad, por id, para que el orden sea estable).
List<FamilyDeviceRow> familyDeviceRows(
  RegistryView view, {
  String? selfName,
  FamilyDoc? common,
}) {
  final name = selfName?.trim();
  final rows = [
    for (final id in view.members)
      FamilyDeviceRow(
        deviceId: id,
        isSelf: id == view.me,
        personId: view.member(id)!.personId,
        isWeb: view.member(id)!.kind == DeviceKind.web,
        deviceName: id == view.me && name != null && name.isNotEmpty
            ? name
            : common == null
            ? null
            : deviceNameIn(common, id),
      ),
  ];
  rows.sort((a, b) {
    if (a.isSelf != b.isSelf) return a.isSelf ? -1 : 1;
    final byName = (a.deviceName ?? '').toLowerCase().compareTo(
      (b.deviceName ?? '').toLowerCase(),
    );
    return byName != 0 ? byName : a.deviceId.compareTo(b.deviceId);
  });
  return rows;
}

V2Auth _auth(SyncV2Local local) => V2Auth(
  syncId: local.identity.syncId,
  deviceId: local.identity.deviceId,
  credential: local.keys.serviceCredential,
);

/// El registro de este móvil visto desde él.
Future<RegistryView> localView(SyncV2Local local) async =>
    (await local.registry()).viewFor(
      me: local.identity.deviceId,
      mySigningKey: local.keys.publicKeys.signing,
      livePeople: livePeopleOf(await local.common()),
    );

/// Si en el servidor queda algún otro móvil con acceso a la lista (una
/// credencial sin revocar que no es la de este). Sin ninguno, este es el
/// último y «Dejar de sincronizar» puede borrar la lista entera.
Future<bool> othersHaveAccess({
  required SyncV2Transport transport,
  required SyncV2Local local,
}) async {
  final got = await transport.getList(_auth(local));
  if (got is! V2GetOk) return false;
  return got.snapshot.devices.any(
    (d) => !d.revoked && d.deviceId != local.identity.deviceId,
  );
}

/// Quita el móvil [deviceId] de la familia: lo revoca en el servidor (deja
/// de tener acceso en ese momento; revocar gana) y en el registro firmado, y
/// publica el registro con una vuelta, que también rota las claves de
/// sorpresa que conocía. Devuelve el cambio, con los huérfanos que hay que
/// confirmar uno a uno (fase 3). Lanza [RegistryException] si ese móvil no
/// se puede revocar (es este, o no existe).
///
/// [rememberOrphans] se llama con esos huérfanos **antes** de guardar nada ni
/// hablar con la red: si la vuelta falla, la revocación queda guardada (y el
/// motor corta el acceso cuando haya conexión) y los huérfanos ya están
/// anotados para confirmarlos.
Future<RegistryChange> removeDevice({
  required SyncV2Transport transport,
  required SyncV2Local local,
  required String deviceId,
  Future<void> Function(List<KnownDevice> orphans)? rememberOrphans,
  void Function(V2SyncOutcome outcome)? onSynced,
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
  await rememberOrphans?.call(change.orphans);
  final state = await local.readState();
  await local.saveState(
    state.copyWith(
      knownMembers: {...state.knownMembers, ...view.everMembers},
      pendingRevocations: {...state.pendingRevocations, deviceId},
      revocationOperations: {
        ...state.revocationOperations,
        deviceId: change.registry.toJson(),
      },
    ),
  );
  await local.saveRegistry(change.registry);
  await retireDeviceNames(local, [deviceId]);
  final outcome = await SyncV2Engine(transport: transport, local: local).sync();
  onSynced?.call(outcome);
  return change;
}

/// Este móvil sale de la familia: revoca su propia credencial en el servidor,
/// conservando sus slots, igual que al quitar otro móvil. Son instantáneas
/// compartidas que pueden contener regalos aún no copiados por los demás.
/// No borra la lista para los demás. Lo local
/// se queda en el móvil. Los demás lo ven revocado en el servidor
/// ([V2SyncOutcome.departedDevices]) y lo revocan en el registro (fase 3),
/// que rota las claves que conocía; un móvil no puede firmar su propia
/// revocación.
Future<void> leaveFamily({
  required SyncV2Transport transport,
  required SyncV2Local local,
}) async {
  final auth = _auth(local);
  await transport.revoke(auth, auth.deviceId);
  await retireDeviceNames(local, [auth.deviceId]);
}
