// El corte al formato 2 del común (ADR 0005, lote B4): cuándo una familia v2
// que ya existe pasa de la `familyKey` de siempre a la clave común por época,
// y el arranque seguro que comparte con la renovación (fase 3, lote 4).
//
// - **Capacidad.** Cada móvil anuncia en el Worker que lee y escribe el
//   formato 2 (`POST S/capability`, un campo de su credencial que se ve en
//   `devices`). Es dato del servicio, no confianza firmada: un servidor que
//   mienta solo puede retrasar el corte o romper la disponibilidad, nunca
//   leer nada. No depende de `meta/protocol` del documento editable.
// - **Activación.** Solo la empieza un móvil activo y aprobado cuando todos
//   los miembros activos de su registro (webs incluidas) han anunciado el
//   formato 2 y [kCommonV2Ready] está encendido. Persiste primero la
//   migración pendiente (`V2SyncState.commonMigration`), importa la
//   `familyKey` como candidata histórica (abre, no sella), y en esa misma
//   vuelta abre por última vez el común en formato 1, crea una candidata
//   aleatoria, la guarda con su reparto y sube el común acumulado en formato
//   2 con `minCommonFormat: 2` (el Worker sube su mínimo en la misma
//   transacción). Al terminar pone la marca local irreversible
//   (`SyncV2Local.raiseCommonFormatFloor`).
// - **Seguir el corte.** Un móvil que ve el mínimo del servidor en 2 (otro
//   activó, o él mismo y se cerró antes de la marca) importa la clave
//   histórica, pone la marca y pasa al formato 2 sin abrir nunca un formato
//   1. Así se pone al día el que estaba desconectado.
// - **Arranque seguro compartido** con el lote 4: con la marca puesta (o el
//   interruptor encendido), `SyncV2Engine.ensureCreated` crea la generación
//   directamente en formato 2 con `minCommonFormat: 2`, una candidata
//   aleatoria guardada antes de sellar y la marca al terminar. Ver
//   [CommonV2Bootstrap].
//
// No depende de Flutter.
library;

import '../../../core/sync/device_keys.dart';
import '../../../core/sync/device_registry.dart';
import '../../../core/sync/envelope.dart' show FamilyKey;
import '../../../core/sync/family_candidate.dart';
import '../data/sync_transport_v2.dart' show V2Device;
import 'sync_v2_engine.dart' show SyncV2Local, V2SyncState;

/// Si esta versión puede **empezar** el corte de una familia al formato 2.
///
/// Apagado hasta que estén la web (B5, que tiene que abrir y firmar el
/// común en formato 2), los ficheros `.regalos` firmados (B6: tras el corte
/// el de siempre no se importa ni se exporta) y el checkpoint del
/// emparejamiento (B7, que tiene que entregar al invitado un paquete v4 y el
/// formato mínimo dentro de la aprobación firmada, en vez de la `familyKey`
/// en v3: hasta entonces emparejar tras el corte falla). Con él
/// apagado este móvil no anuncia la capacidad, así que nadie lo corta. Seguir
/// un corte que ya ha hecho otro no depende de él: si el servidor ya pide el
/// formato 2, el formato 1 no se puede subir.
const bool kCommonV2Ready = false;

/// El formato del común más nuevo que conoce esta versión.
const int kCommonFormatLatest = 2;

/// Referencia de la candidata histórica que viene de la `familyKey`: nunca
/// se recorta ni se poda.
const String kLegacyRef = 'legacy';

/// Qué ha pasado con el corte en una vuelta.
enum CommonCutover {
  /// Nada: o ya está en el formato 2, o este móvil no puede empezarlo.
  none,

  /// Este móvil quiere cortar pero falta que algún miembro activo anuncie
  /// el formato 2.
  waiting,

  /// Este móvil está activando el corte en esta vuelta.
  activating,

  /// El corte ha terminado en esta vuelta: el Worker exige el formato 2 y
  /// este móvil tiene la marca.
  activated,

  /// Este móvil ha seguido un corte que ya estaba hecho en el servidor.
  followed,
}

/// La credencial de servicio activa de [deviceId] en [devices], o null.
V2Device? activeCredential(List<V2Device> devices, String deviceId) {
  for (final d in devices) {
    if (d.deviceId == deviceId && !d.revoked) return d;
  }
  return null;
}

/// Si este móvil puede activar el corte desde [view]: es un móvil activo,
/// aprobado y no revocado, **todos** los miembros activos (él incluido, y
/// las webs) tienen una credencial activa que ha anunciado el formato 2 (un
/// miembro sin credencial cuenta como antiguo) y, además, toda credencial no
/// revocada de [devices] lo ha anunciado, también las que no están en la
/// vista (huérfanas, pendientes, sin respaldo): el Worker exige lo mismo
/// (revisión de seguridad, M1).
bool membersAnnouncedCommonV2(RegistryView view, List<V2Device> devices) {
  if (view.self.kind != DeviceKind.mobile ||
      !view.selfApproved ||
      view.revokedByOthers) {
    return false;
  }
  for (final id in view.members) {
    final d = activeCredential(devices, id);
    if (d == null || d.commonFormat < kCommonFormatLatest) return false;
  }
  return devices.every(
    (d) => d.revoked || d.commonFormat >= kCommonFormatLatest,
  );
}

/// La `familyKey` de siempre como candidata del llavero común: creador este
/// móvil, la época y la audiencia que ve [view] (descriptivas: la audiencia
/// real de esa clave no se puede reconstruir) y el secreto, la propia clave.
/// Se guarda como histórica: abre, nunca sella.
Future<FamilyCandidate> legacyFamilyCandidate(
  RegistryView view, {
  required DeviceKeys keys,
  required String syncId,
  required FamilyKey familyKey,
}) {
  final descriptor = EpochDescriptor.ofView(view, syncId: syncId);
  return FamilyCandidate.create(
    listId: view.listId,
    syncId: syncId,
    epochNumber: view.epoch,
    epochContext: descriptor.context,
    creator: view.me,
    creatorRecord: view.self.recordDigest,
    audience: descriptor.members,
    secret: familyKey.bytes,
    creatorKeys: keys,
  );
}

/// El arranque seguro del formato 2, compartido con la renovación (fase 3,
/// lote 4).
///
/// Para crear una generación nueva directamente en formato 2:
///
/// 1. [prepareFresh] antes de `SyncV2Engine.ensureCreated` (o con la marca
///    ya puesta, que `ensureCreated` respeta): deja el interruptor
///    encendido en el estado, que se persiste antes de nada.
/// 2. `ensureCreated` elige o crea la candidata, la guarda con su reparto
///    **antes** de sellar (B3), crea la lista con `minCommonFormat: 2` y, si
///    el servidor la acepta, pone la marca ([finish]).
///
/// Una generación nueva no hereda la `familyKey` ni la clave histórica: no
/// tiene nada publicado en formato 1.
abstract final class CommonV2Bootstrap {
  /// Enciende el formato 2 en el estado de [local] antes de crear nada.
  static Future<void> prepareFresh(SyncV2Local local) async {
    final state = await local.readState();
    if (state.commonFormatV2) return;
    await local.saveState(state.copyWith(commonFormatV2: true));
  }

  /// Pone la marca irreversible y deja el estado en formato 2, sin
  /// migración pendiente. Idempotente. La marca va primero: un cierre
  /// después deja el estado atrasado, que la vuelta siguiente cura.
  static Future<V2SyncState> finish(SyncV2Local local) async {
    await local.raiseCommonFormatFloor(kCommonFormatLatest);
    final state = await local.readState();
    final next = state.copyWith(
      commonFormatV2: true,
      commonMigration: false,
      commonMigrationPut: false,
    );
    if (!state.commonFormatV2 ||
        state.commonMigration ||
        state.commonMigrationPut) {
      await local.saveState(next);
    }
    return next;
  }
}
