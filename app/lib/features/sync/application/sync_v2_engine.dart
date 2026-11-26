// Ciclo de sincronización v2 (ADR 0004, fase 2b): instantánea atómica,
// reconciliación en orden (común, registro, paquetes, slots), rotación de
// claves de sorpresa en cada vuelta, un solo punto que decide publicar slots
// (`slotPublishDue`, pendiente 15) y subida condicional con `If-Match`.
//
// No depende de Flutter: lo local llega por [SyncV2Local], que en la app es
// el controlador de la familia y el almacén, y en las pruebas, memoria.
library;

import 'dart:convert';
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:meta/meta.dart' show visibleForTesting;

import '../../../core/sync/access_policy.dart';
import '../../../core/sync/device_keys.dart';
import '../../../core/sync/device_registry.dart';
import '../../../core/sync/envelope.dart';
import '../../../core/sync/family_doc.dart';
import '../../../core/sync/family_envelope.dart' show isFamilyEnvelope;
import '../../../core/sync/family_key_bundle.dart' show FamilyKeyBundle;
import '../../../core/sync/hlc.dart';
import '../../../core/sync/key_bundle.dart';
import '../../../core/sync/model.dart' show Collections;
import '../../../core/sync/pairing_v2.dart';
import '../../../core/sync/protected_doc.dart';
import '../../../core/sync/protected_envelope.dart';
import '../data/sync_transport.dart';
import '../data/sync_transport_v2.dart';
import 'common_v2.dart';
import 'common_v2_cutover.dart';
import 'v2_health.dart';

/// Por qué un slot del servidor no se baja ni se guarda (B2).
enum IgnoredSlotReason {
  /// Ningún móvil puede leerlo (`SealedSlot.parse` falla).
  unreadable,

  /// Su escritor está revocado de verdad en el registro: revocación firmada
  /// y sin ambigüedad.
  revoked,

  /// Su escritor no es ningún móvil del registro visto desde aquí
  /// (`view.device` es null): falso, ambiguo o revocado sin enlace. Se
  /// mantiene mientras siga sin serlo.
  unknownWriter,

  /// Buzón de una web que no es de la persona de este móvil (1.0.6, ADR
  /// 0009): solo lo recogen los móviles de su persona. No cuenta para nada.
  webInbox,
}

/// Un slot que sigue en el servidor (B2: nadie borra los ajenos) pero que
/// este móvil ignora mientras su versión no cambie.
class IgnoredSlot {
  /// Crea la entrada.
  const IgnoredSlot(this.version, this.reason);

  /// La versión de la lista que escribió el slot.
  final int version;

  /// Por qué se ignora.
  final IgnoredSlotReason reason;

  @override
  bool operator ==(Object other) =>
      other is IgnoredSlot &&
      other.version == version &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(version, reason);
}

/// Cada cuánto vuelve a bajar un móvil el buzón de una web propia que espera
/// (1.0.6, ADR 0009, B2).
const Duration kWebInboxRetry = Duration(hours: 1);

/// Lo que recuerda este móvil de la lista v2 entre una vuelta y otra.
class V2SyncState {
  /// Crea el estado.
  const V2SyncState({
    this.created = false,
    this.version,
    this.slotVersions = const <String, int>{},
    this.ignoredSlots = const <String, IgnoredSlot>{},
    this.minSlotRevisions = const <String, int>{},
    this.deferred = const <String>{},
    this.pendingRevocations = const <String>{},
    this.pendingUnbackedRevocations = const <String>{},
    this.knownMembers = const <String>{},
    this.revocationOperations = const <String, Map<String, Object?>>{},
    this.keyPackageOutbox = const <Map<String, Object?>>[],
    this.health,
    this.commonFormatV2 = false,
    this.commonMigration = false,
    this.commonMigrationPut = false,
    this.createSent = false,
    this.webInboxFloors = const <String, SlotVersion>{},
    this.webInboxRejected = const <String, SlotVersion>{},
    this.webPlanInboxSeen = const <String, SlotVersion>{},
    this.webInboxDone = const <String, int>{},
    this.webTombstoneDay = 0,
    this.webTombstoneCount = 0,
    this.webShares = const <String, String>{},
    this.webInboxWait = const <String, List<int>>{},
  });

  /// Claves de sorpresas entregadas a webs propias (1.0.6, ADR 0009):
  /// `web|ficha de la web|mi ficha|persona|época|kid` -> el paquete (JSON).
  /// Se vuelve a emitir si el paquete ya no está ni en el servidor ni en la
  /// outbox. Distingue el `kid`: dos candidatas con la misma audiencia son
  /// dos paquetes (revisión de seguridad, M2).
  final Map<String, String> webShares;

  /// Buzones de webs propias que esperan (sin clave, freno diario, escritor
  /// ilegible...): `persona/web` -> [versión de la lista, momento]. No se
  /// vuelven a bajar hasta que cambien o pase [kWebInboxRetry] (B2).
  final Map<String, List<int>> webInboxWait;

  /// La creación de la lista se ha enviado al menos una vez (1.0.6): se
  /// guarda **antes** de enviarla, así que aunque se pierda la respuesta se
  /// sabe que la ficha de este móvil pudo salir. Con ella ya no se sustituye
  /// la primera ficha al cambiar de persona en un móvil solo.
  final bool createSent;

  /// De cada buzón de una web propia (`persona/web`), la última versión del
  /// slot (época y revisión) que ya está dentro del ámbito: la recogió este
  /// móvil o la declara (`s[web]`) el slot de otro móvil de la misma persona.
  /// Un buzón igual o más viejo no se vuelve a recoger (1.0.6, ADR 0009): el
  /// Worker no puede reponer uno viejo y nada resucita.
  final Map<String, SlotVersion> webInboxFloors;

  /// De cada buzón de una web propia (`persona/web`), la última versión que
  /// este móvil **rechazó entera** (más registros de los admitidos, de otra
  /// persona, con marcas del futuro...). Se declara en el slot (`x`) para que
  /// la web la dé por perdida y no por entregada. Una recogida posterior del
  /// mismo buzón la quita.
  final Map<String, SlotVersion> webInboxRejected;

  /// Versiones de [webInboxFloors] recogidas o rechazadas con soporte para
  /// planes. Viajan con la versión al retransmitirla entre móviles.
  final Map<String, SlotVersion> webPlanInboxSeen;

  /// Buzones de webs propias ya resueltos (recogidos, rechazados o viejos),
  /// con la versión de la lista que los escribió: no se vuelven a bajar
  /// mientras no cambien.
  final Map<String, int> webInboxDone;

  /// Día (UTC, días desde 1970) de [webTombstoneCount].
  final int webTombstoneDay;

  /// Lápidas de webs recogidas ese día ([kMaxWebTombstonesPerDay]).
  final int webTombstoneCount;

  /// Si la lista ya existe en el servidor (la creó este móvil o entró en
  /// ella).
  final bool created;

  /// La última versión completa que leyó o escribió. El servidor nunca puede
  /// servir una más vieja: sería un estado antiguo.
  final int? version;

  /// De cada slot (`persona/móvil`), la versión de la lista que lo escribió
  /// cuando este móvil lo bajó: solo se vuelven a bajar los que cambian.
  final Map<String, int> slotVersions;

  /// Slots que siguen en el servidor pero que este móvil ignora (B2: nadie
  /// borra los ajenos), con la versión que los escribió y el motivo: no se
  /// guardan en local ni se vuelven a bajar mientras esa versión no cambie.
  final Map<String, IgnoredSlot> ignoredSlots;

  /// Revisiones de slot que el anfitrión ya conocía al emparejar (pendiente
  /// 13): un slot con una revisión menor es viejo y no se acepta.
  final Map<String, int> minSlotRevisions;

  /// Personas cuyo slot tocaba publicar pero no cupo en el `PUT`
  /// ([kV2MaxSlotsPerPut]): en la vuelta siguiente van las primeras.
  final Set<String> deferred;

  /// Revocaciones pendientes de cortar en el servidor, antes de publicar.
  final Set<String> pendingRevocations;

  /// Resoluciones condicionales: cada intento debe volver a leer y verificar
  /// el registro remoto. Un respaldo sobrevenido cancela la intención.
  final Set<String> pendingUnbackedRevocations;

  /// Ids enlazados alguna vez por avales verificados desde este móvil.
  /// Sobreviven a la poda del registro: su ausencia posterior no permite
  /// cortar una credencial permanentemente. No conceden derechos ni avales.
  final Set<String> knownMembers;

  /// Registro con la declaración firmada de cada operación. Se conserva
  /// hasta publicar: permite recuperar un cierre antes de guardarlo.
  final Map<String, Map<String, Object?>> revocationOperations;

  /// Paquetes cifrados aún no aceptados por un PUT. Se guardan antes de
  /// actualizar la audiencia del llavero, en el mismo almacén seguro v2.
  final List<Map<String, Object?>> keyPackageOutbox;

  /// Observaciones que solo existen en la última instantánea del servicio.
  final V2Health? health;

  /// Interruptor de la clave común por época (ADR 0005, B3): con él, el
  /// común va en el sobre firmado (formato 2) sellado con candidatas del
  /// llavero común y repartido con paquetes v4, y la vía v3 `scope: family`
  /// queda cerrada. Apagado por defecto: lo enciende la migración (B4).
  /// La marca irreversible va aparte (`SyncV2Local.commonFormatFloor`): si
  /// este estado se pierde, la marca lo vuelve a encender.
  final bool commonFormatV2;

  /// El corte al formato 2 está a medias (ADR 0005, B4): se guarda antes de
  /// importar la clave histórica y de sellar nada, y se quita con la marca
  /// irreversible o si el corte ya no se puede hacer (no se había publicado
  /// nada en formato 2).
  final bool commonMigration;

  /// El `PUT` del corte ya se ha intentado (B4, tras la revisión de seguridad,
  /// B2): pudo entrar aunque no llegara la respuesta, así que desde aquí este
  /// móvil no vuelve a abrir nunca un formato 1. Si el corte no entró,
  /// reintenta sellando lo que tiene; lo que otros escribieron en formato 1
  /// vive en sus copias locales y entra cuando siguen el corte.
  final bool commonMigrationPut;

  /// Copia con cambios.
  V2SyncState copyWith({
    bool? created,
    int? version,
    Map<String, int>? slotVersions,
    Map<String, IgnoredSlot>? ignoredSlots,
    Map<String, int>? minSlotRevisions,
    Set<String>? deferred,
    Set<String>? pendingRevocations,
    Set<String>? pendingUnbackedRevocations,
    Set<String>? knownMembers,
    Map<String, Map<String, Object?>>? revocationOperations,
    List<Map<String, Object?>>? keyPackageOutbox,
    V2Health? health,
    bool? commonFormatV2,
    bool? commonMigration,
    bool? commonMigrationPut,
    bool? createSent,
    Map<String, SlotVersion>? webInboxFloors,
    Map<String, SlotVersion>? webInboxRejected,
    Map<String, SlotVersion>? webPlanInboxSeen,
    Map<String, int>? webInboxDone,
    int? webTombstoneDay,
    int? webTombstoneCount,
    Map<String, String>? webShares,
    Map<String, List<int>>? webInboxWait,
  }) => V2SyncState(
    created: created ?? this.created,
    version: version ?? this.version,
    slotVersions: slotVersions ?? this.slotVersions,
    ignoredSlots: ignoredSlots ?? this.ignoredSlots,
    minSlotRevisions: minSlotRevisions ?? this.minSlotRevisions,
    deferred: deferred ?? this.deferred,
    pendingRevocations: pendingRevocations ?? this.pendingRevocations,
    pendingUnbackedRevocations:
        pendingUnbackedRevocations ?? this.pendingUnbackedRevocations,
    knownMembers: knownMembers ?? this.knownMembers,
    revocationOperations: revocationOperations ?? this.revocationOperations,
    keyPackageOutbox: keyPackageOutbox ?? this.keyPackageOutbox,
    health: health ?? this.health,
    commonFormatV2: commonFormatV2 ?? this.commonFormatV2,
    commonMigration: commonMigration ?? this.commonMigration,
    commonMigrationPut: commonMigrationPut ?? this.commonMigrationPut,
    createSent: createSent ?? this.createSent,
    webInboxFloors: webInboxFloors ?? this.webInboxFloors,
    webInboxRejected: webInboxRejected ?? this.webInboxRejected,
    webPlanInboxSeen: webPlanInboxSeen ?? this.webPlanInboxSeen,
    webInboxDone: webInboxDone ?? this.webInboxDone,
    webTombstoneDay: webTombstoneDay ?? this.webTombstoneDay,
    webTombstoneCount: webTombstoneCount ?? this.webTombstoneCount,
    webShares: webShares ?? this.webShares,
    webInboxWait: webInboxWait ?? this.webInboxWait,
  );

  /// En JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'c': created,
    'v': ?version,
    's': slotVersions,
    if (ignoredSlots.isNotEmpty)
      'ig': {
        for (final e in ignoredSlots.entries)
          e.key: [e.value.version, e.value.reason.name],
      },
    'm': minSlotRevisions,
    if (deferred.isNotEmpty) 'p': (deferred.toList()..sort()),
    if (pendingRevocations.isNotEmpty)
      'r': (pendingRevocations.toList()..sort()),
    if (pendingUnbackedRevocations.isNotEmpty)
      'ur': (pendingUnbackedRevocations.toList()..sort()),
    if (knownMembers.isNotEmpty) 'km': (knownMembers.toList()..sort()),
    if (keyPackageOutbox.isNotEmpty) 'o': keyPackageOutbox,
    if (revocationOperations.isNotEmpty) 'ro': revocationOperations,
    if (health != null) 'health': health!.toJson(),
    if (commonFormatV2) 'cf': true,
    if (commonMigration) 'cm': true,
    if (commonMigrationPut) 'cmp': true,
    if (createSent) 'cs': true,
    if (webInboxFloors.isNotEmpty)
      'wf': {
        for (final e in webInboxFloors.entries)
          e.key: [e.value.epoch, e.value.revision],
      },
    if (webInboxRejected.isNotEmpty)
      'wx': {
        for (final e in webInboxRejected.entries)
          e.key: [e.value.epoch, e.value.revision],
      },
    'wpf': {
      for (final e in webPlanInboxSeen.entries)
        e.key: [e.value.epoch, e.value.revision],
    },
    if (webInboxDone.isNotEmpty) 'wd': webInboxDone,
    if (webTombstoneCount > 0) 'wt': [webTombstoneDay, webTombstoneCount],
    if (webShares.isNotEmpty) 'ws': webShares,
    if (webInboxWait.isNotEmpty) 'ww': webInboxWait,
  };

  /// Lee [toJson]; lo que no se entiende se olvida (se vuelve a bajar).
  factory V2SyncState.fromJson(Object? json) {
    if (json is! Map) return const V2SyncState();
    Map<String, int> ints(Object? raw) => {
      if (raw is Map)
        for (final e in raw.entries)
          if (e.key is String && e.value is int && (e.value as int) >= 0)
            e.key as String: e.value as int,
    };
    Map<String, SlotVersion> inboxVersions(Object? raw) => {
      if (raw is Map)
        for (final e in raw.entries)
          if (e.key is String)
            if (e.value case [final int epoch, final int revision])
              e.key as String: SlotVersion(epoch, revision),
    };
    final v = json['v'];
    final p = json['p'];
    final wt = json['wt'];
    return V2SyncState(
      webInboxRejected: inboxVersions(json['wx']),
      webInboxFloors: inboxVersions(json['wf']),
      webPlanInboxSeen: inboxVersions(json['wpf']),
      // A previous version may have marked an unread plan as resolved.
      webInboxDone: json['wpf'] is Map ? ints(json['wd']) : const {},
      webShares: {
        if (json['ws'] is Map)
          for (final e in (json['ws'] as Map).entries)
            if (e.key is String && e.value is String)
              e.key as String: e.value as String,
      },
      webInboxWait: {
        if (json['ww'] is Map)
          for (final e in (json['ww'] as Map).entries)
            if (e.key is String &&
                e.value is List &&
                (e.value as List).length == 2 &&
                (e.value as List).every((x) => x is int))
              e.key as String: (e.value as List).cast<int>(),
      },
      webTombstoneDay: wt is List && wt.length == 2 && wt[0] is int
          ? wt[0] as int
          : 0,
      webTombstoneCount: wt is List && wt.length == 2 && wt[1] is int
          ? wt[1] as int
          : 0,
      health: json['health'] == null ? null : V2Health.fromJson(json['health']),
      created: json['c'] == true,
      commonFormatV2: json['cf'] == true,
      commonMigration: json['cm'] == true,
      commonMigrationPut: json['cmp'] == true,
      createSent: json['cs'] == true,
      version: v is int && v >= 0 ? v : null,
      slotVersions: ints(json['s']),
      ignoredSlots: {
        if (json['ig'] is Map)
          for (final e in (json['ig'] as Map).entries)
            if (e.key is String &&
                e.value is List &&
                (e.value as List).length == 2 &&
                (e.value as List)[0] is int &&
                ((e.value as List)[0] as int) >= 0)
              for (final reason in IgnoredSlotReason.values)
                if (reason.name == (e.value as List)[1])
                  e.key as String: IgnoredSlot(
                    (e.value as List)[0] as int,
                    reason,
                  ),
      },
      minSlotRevisions: ints(json['m']),
      deferred: {
        if (p is List)
          for (final id in p)
            if (id is String) id,
      },
      pendingRevocations: {
        if (json['r'] is List)
          for (final id in json['r'] as List)
            if (id is String) id,
      },
      pendingUnbackedRevocations: {
        if (json['ur'] is List)
          for (final id in json['ur'] as List)
            if (id is String) id,
      },
      knownMembers: {
        if (json['km'] is List)
          for (final id in json['km'] as List)
            if (id is String) id,
      },
      keyPackageOutbox: [
        if (json['o'] is List)
          for (final p in json['o'] as List)
            if (p is Map) Map<String, Object?>.from(p),
      ],
      revocationOperations: {
        if (json['ro'] is Map)
          for (final e in (json['ro'] as Map).entries)
            if (e.key is String && e.value is Map)
              e.key as String: Map<String, Object?>.from(e.value as Map),
      },
    );
  }
}

/// Optional application reconciliation, after verified remote data is stored
/// and before any scope compaction or common publication.
abstract interface class ProtectionSyncLocal {
  Future<void> reconcileProtectionBeforePublish();
}

/// Durable writer floors and the irreversible service-credential gate.
abstract interface class RecoverySyncLocal {
  Future<void> assertSyncWritable();
  Future<void> markSyncTransferred();
  Future<int> slotRevisionFloor(String personId);
  Future<void> rememberSlotRevision(String personId, int revision);
}

class V2RecoveryInvalidationPendingException implements Exception {
  const V2RecoveryInvalidationPendingException();
}

abstract interface class RecoverySlotCacheLocal {
  Future<Uint8List?> readRecoverySlot(int snapshot, V2SlotRef ref);
  Future<void> saveRecoverySlot(int snapshot, V2SlotRef ref, Uint8List bytes);
}

abstract interface class RecoveryBootstrapLocal {
  Future<V2SnapshotUpload?> readRecoveryBootstrap();
  Future<void> saveRecoveryBootstrap(V2SnapshotUpload body);
}

Map<String, Object?> recoveryBootstrapJson(V2SnapshotUpload body) => {
  'common': encodeBase64Url(body.common),
  'registry': body.registry,
  'keyPackages': body.keyPackages,
  'minCommonFormat': body.minCommonFormat,
  'inviteCopy': body.inviteCopy,
};
V2SnapshotUpload? recoveryBootstrapFromJson(Object? raw) {
  if (raw == null) return null;
  final j = raw as Map;
  return V2SnapshotUpload(
    common: decodeBase64Url(j['common'] as String),
    registry: Map<String, Object?>.from(j['registry'] as Map),
    keyPackages: [
      for (final p in j['keyPackages'] as List)
        Map<String, Object?>.from(p as Map),
    ],
    minCommonFormat: j['minCommonFormat'] as int?,
    inviteCopy: j['inviteCopy'] as bool? ?? false,
  );
}

class V2TransferredException implements Exception {
  const V2TransferredException();
}

class V2RecoveryIncompleteException implements Exception {
  const V2RecoveryIncompleteException(this.code);
  final String code;
}

/// Lo local que necesita el ciclo.
abstract interface class SyncV2Local {
  /// Identidad v2 de este móvil.
  SyncIdentityV2 get identity;

  /// Claves persistentes de este móvil.
  DeviceKeys get keys;

  /// Nodo del reloj de este móvil (va en la cabecera del sobre común).
  String get node;

  /// La clave de la familia.
  FamilyKey get familyKey;

  /// El documento común de ahora.
  Future<FamilyDoc> common();

  /// Fusiona un documento común que llega (como `mergeRemote`).
  Future<void> mergeCommon(FamilyDoc remote, {required String fromNode});

  /// El registro guardado (con el ancla de este móvil).
  Future<DeviceRegistry> registry();

  /// Guarda el registro.
  Future<void> saveRegistry(DeviceRegistry registry);

  /// Los slots guardados.
  Future<SlotSet> slots();

  /// Guarda los slots.
  Future<void> saveSlots(SlotSet slots);

  /// Cambia el llavero dentro de su cola.
  Future<SurpriseKeyring> updateKeyring(
    SurpriseKeyring Function(SurpriseKeyring current) update,
  );

  /// La copia local del ámbito secreto de una persona.
  Future<FamilyDoc?> readScope(String personId);

  /// Guarda la copia local del ámbito secreto de una persona.
  Future<void> saveScope(String personId, FamilyDoc scope);

  /// Borra la copia local del ámbito secreto de una persona.
  Future<void> deleteScope(String personId);

  /// El estado de la sincronización.
  Future<V2SyncState> readState();

  /// Guarda el estado de la sincronización.
  Future<void> saveState(V2SyncState state);

  /// Lo que guarda este móvil de la clave común (ADR 0005, B3): llavero,
  /// intención de reparto, revisión y bloqueo, o null si no hay. Lanza si
  /// está dañado.
  Future<CommonKeyState?> readCommonKeys();

  /// Lo guarda en una sola escritura atómica, en el almacén cifrado.
  Future<void> saveCommonKeys(CommonKeyState state);

  /// Si ya se ha guardado alguna vez la clave común (marca en el almacén
  /// seguro): sin ella, que falte el estado no es un primer arranque.
  Future<bool> commonKeysMarked();

  /// Pone esa marca.
  Future<void> markCommonKeys();

  /// La marca local irreversible del formato mínimo del común (ADR 0005,
  /// B4): 1 si no hay. Va aparte del documento y de [V2SyncState], así que
  /// ni una copia antigua ni un estado que se pierde la rebajan.
  Future<int> commonFormatFloor();

  /// Sube esa marca (nunca la baja).
  Future<void> raiseCommonFormatFloor(int format);

  /// El índice de los comunes remotos guardados aparte (sin fusionar). Lanza
  /// [CommonStateException] si no se puede leer.
  Future<List<RetainedCommon>> readRetainedCommons();

  /// Guarda el índice de los comunes retenidos.
  Future<void> saveRetainedCommons(List<RetainedCommon> retained);

  /// Los bytes de un común retenido (por su hash), o null.
  Future<Uint8List?> readRetainedBytes(String hash);

  /// Guarda los bytes de un común retenido, en su propio fichero.
  Future<void> saveRetainedBytes(String hash, Uint8List bytes);

  /// Borra los bytes de un común retenido.
  Future<void> deleteRetainedBytes(String hash);
}

/// Erases names only for explicit departures or verified revocations. Keep
/// even an empty tombstone: a delayed name must never revive a retired id.
Future<void> retireDeviceNames(
  SyncV2Local local,
  Iterable<String> deviceIds,
) async {
  final common = await local.common();
  var next = common;
  final nameClock = HlcClock(node: local.node, last: common.maxStamp);
  for (final id in deviceIds) {
    if (next.record(Collections.meta, 'device:$id')?.isDeleted == true) {
      continue;
    }
    next = next.delete(nameClock, Collections.meta, 'device:$id');
  }
  if (!identical(next, common)) {
    await local.mergeCommon(next, fromNode: local.node);
  }
}

/// El servidor ha servido una versión más vieja que una que este móvil ya
/// vio: o se ha vuelto atrás o alguien sirve un estado antiguo.
class V2RollbackException implements Exception {
  /// Crea el error.
  const V2RollbackException({required this.known, required this.served});

  /// La que conocía este móvil.
  final int known;

  /// La que ha servido.
  final int served;

  @override
  String toString() => 'V2RollbackException($served < $known)';
}

/// La lista ya no está en el servidor (se borró o caducó). Un `syncId` v2 no
/// se puede volver a crear.
class V2ListGoneException implements Exception {
  /// Crea el error.
  const V2ListGoneException();

  @override
  String toString() => 'V2ListGoneException';
}

/// Alguien de la familia ha revocado a este móvil (o usa su id con otras
/// claves): deja de publicar.
class V2RevokedException implements Exception {
  /// Crea el error.
  const V2RevokedException();

  @override
  String toString() => 'V2RevokedException';
}

/// Lo que ha pasado en una vuelta.
/// Lo que hay en el servidor en [V2SyncOutcome.version], byte a byte: lo
/// que se leyó (sin subir nada) o lo que se subió (ADR 0005, B7). El
/// anfitrión aprueba exactamente esto al emparejar.
class V2Published {
  /// Crea el estado.
  const V2Published({
    required this.common,
    required this.registry,
    required this.keyPackages,
  });

  /// El común.
  final Uint8List common;

  /// El registro en JSON.
  final Object? registry;

  /// Los paquetes de claves.
  final List<Map<String, Object?>> keyPackages;
}

class V2SyncOutcome {
  /// Crea el resultado.
  const V2SyncOutcome({
    required this.version,
    required this.view,
    required this.hasOtherActiveCredential,
    required this.uploaded,
    required this.unbackedCredentials,
    this.departedDevices = const [],
    required this.frozenPeople,
    required this.publishedPeople,
    required this.rejectedSlots,
    this.renewSuggested = false,
    this.slotsFull = false,
    this.writerSlotsFull = false,
    this.morePending = false,
    this.commonStatus,
    this.commonKid,
    this.commonReplaced = false,
    this.commonPackagesFull = false,
    this.commonCutover = CommonCutover.none,
    this.published,
  });

  /// Lo que queda en el servidor en [version] (B7).
  final V2Published? published;

  /// Qué ha pasado con el corte al formato 2 del común en esta vuelta (B4).
  final CommonCutover commonCutover;

  /// Con la clave común por época: qué pasó con el común remoto.
  final RemoteCommonStatus? commonStatus;

  /// Con la clave común por época: `kid` del común que queda en el servidor
  /// (o del remoto, si no se ha subido), si es formato 2.
  final String? commonKid;

  /// Se ha sustituido un común remoto que no se podía abrir (falso, de un
  /// revocado o tras la espera); está guardado aparte.
  final bool commonReplaced;

  /// El reparto de la clave común no cabe en los límites del Worker: no se
  /// ha sustituido el común (contrapresión) y hay que renovar.
  final bool commonPackagesFull;

  /// Versión de la lista al terminar.
  final int version;

  /// El registro visto desde este móvil.
  final RegistryView view;

  /// Whether the merged snapshot contained another non-revoked credential.
  final bool hasOtherActiveCredential;

  /// Si se ha subido algo.
  final bool uploaded;

  /// Credenciales activas en el servidor que el registro de este móvil no
  /// respalda (ni son de la familia ni esperan aprobación): por ejemplo, una
  /// que aprobó un móvil revocado sin publicarla. La fase 3 las revoca.
  final List<String> unbackedCredentials;

  /// Móviles que el registro tiene activos pero cuya credencial ya está
  /// revocada en el servidor (salieron de la familia): la fase 3 pide
  /// revocarlos también en el registro. No se hace solo, porque `devices`
  /// lo dice el servidor.
  final List<String> departedDevices;

  /// Personas cuyas sorpresas tiene congeladas este móvil (hallazgo 2).
  final List<String> frozenPeople;

  /// Personas cuyo slot ha vuelto a sellar este móvil en esta vuelta.
  final List<String> publishedPeople;

  /// Slots que no han entrado (firma, escritor, época o revisión viejos).
  final int rejectedSlots;

  /// El servidor dice que esta generación ha cruzado un aviso
  /// (`capacity.renew`): conviene renovar antes del tope (fase 3).
  final bool renewSuggested;

  /// Algún slot propio nuevo no ha cabido porque la lista está llena: no se
  /// ha publicado y hay que renovar (revisión de seguridad, M2). También enciende
  /// [renewSuggested].
  final bool slotsFull;

  /// Algún slot propio nuevo no ha cabido porque este móvil ya tiene
  /// [kV2MaxSlotsPerWriter]. Renovar no lo arregla, así que no enciende
  /// [renewSuggested]; la interfaz lo enseñará aparte (lote 6).
  final bool writerSlotsFull;

  /// Quedan slots o paquetes por publicar que no cupieron en este `PUT`:
  /// hay que dar otra vuelta.
  final bool morePending;
}

class _Restart implements Exception {
  const _Restart();
}

/// Corta primero el acceso. Una caída deja la intención persistida y evita
/// publicar el registro hasta que otra vuelta pueda completar el corte.
Future<void> _retryPendingRevocations({
  required SyncV2Transport transport,
  required SyncV2Local local,
}) async {
  var state = await local.readState();
  final anchor = RegistryAnchor(
    deviceId: local.identity.deviceId,
    signingKey: local.keys.publicKeys.signing,
  );
  // Antes de fusionar operaciones recuperadas: esa fusión también puede
  // podar la última ficha o aval de un huérfano conocido.
  final before = await (await local.registry()).viewFor(
    me: local.identity.deviceId,
    mySigningKey: local.keys.publicKeys.signing,
    livePeople: livePeopleOf(await local.common()),
  );
  // Compatibilidad con las resoluciones sin respaldo guardadas antes de
  // separar las colas. Una revocación firmada conserva su carácter explícito.
  final legacyUnbacked = {
    for (final id in state.pendingRevocations)
      if (!before.revoked.contains(id) &&
          !state.revocationOperations.containsKey(id) &&
          (state.health?.unbackedCredentials.contains(id) ?? false))
        id,
  };
  state = state.copyWith(
    knownMembers: {...state.knownMembers, ...before.everMembers},
    pendingRevocations: {...state.pendingRevocations}
      ..removeAll(legacyUnbacked),
    pendingUnbackedRevocations: {
      ...state.pendingUnbackedRevocations,
      ...legacyUnbacked,
    },
  );
  await local.saveState(state);
  // Recuperar la declaración antes de cortar, incluso si nunca llegó a
  // escribirse el registro. La fusión idempotente conserva otros cambios.
  for (final raw in state.revocationOperations.values) {
    final operation = await DeviceRegistry.fromJsonVerified(
      raw,
      anchor: anchor,
    );
    await local.saveRegistry(
      await (await local.registry()).merge(operation, anchor: anchor),
    );
  }
  final restoredView = state.revocationOperations.isEmpty
      ? before
      : await (await local.registry()).viewFor(
          me: local.identity.deviceId,
          mySigningKey: local.keys.publicKeys.signing,
          livePeople: livePeopleOf(await local.common()),
        );
  await retireDeviceNames(local, {
    ...restoredView.explicitlyRevoked,
    if (restoredView.selfRevoked) local.identity.deviceId,
  });
  final auth = V2Auth(
    syncId: local.identity.syncId,
    deviceId: local.identity.deviceId,
    credential: local.keys.serviceCredential,
  );
  for (final id in state.pendingRevocations.toList()..sort()) {
    int? version;
    for (var attempt = 0; ; attempt++) {
      try {
        version = await transport.revoke(auth, id);
        if (state.version != null && version < state.version!) {
          throw V2RollbackException(known: state.version!, served: version);
        }
        break;
      } on SyncTransportException catch (e) {
        // 404: nunca llegó a tener credencial. Los demás errores conservan
        // el pendiente; no se interpretan como una revocación aceptada.
        if (e.failure == SyncFailure.protocol &&
            e.message == 'móvil desconocido') {
          break;
        }
        if (attempt >= 2 ||
            (e.failure != SyncFailure.network &&
                e.failure != SyncFailure.server)) {
          rethrow;
        }
      }
    }
    state = state.copyWith(
      version: version,
      pendingRevocations: {...state.pendingRevocations}..remove(id),
    );
    await local.saveState(state);
  }
}

/// El ciclo v2. Una instancia por lista; no es reentrante (el controlador
/// pone las vueltas en fila).
/// Cómo acabó retirar un acceso sin respaldo, decidido dentro de la operación
/// con el registro verificado y la lista del servicio.
enum UnbackedRevocation {
  /// El servicio ha cortado el acceso.
  revoked,

  /// El servicio ya no lo tenía activo: no había nada que cortar.
  alreadyResolved,

  /// El acceso figura en el registro de la familia (o es de este móvil): no
  /// se corta.
  keptBecauseBacked,

  /// Nunca se corta porque este móvil ya conoció a ese móvil como miembro
  /// (puede haber salido del registro): no se corta.
  knownMember,
}

/// Slots bajados en una vuelta que no terminó (por ejemplo, un `429` a mitad
/// de una lista de 128 en frío; el Worker admite 120 peticiones por minuto y
/// credencial): la vuelta siguiente no los vuelve a pedir. Son los bytes tal
/// como llegaron, sin verificar, por (lista, recurso, versión del recurso),
/// y pasan las mismas comprobaciones que uno recién bajado. Se vacía al
/// terminar la descarga de esa lista. En memoria del proceso: comparte los
/// motores que se crean y se cierran.
final _pendingSlotDownloads = <String, Uint8List>{};

/// Se olvida lo bajado a medias (SOLO pruebas).
@visibleForTesting
void clearPendingSlotDownloadsForTesting() => _pendingSlotDownloads.clear();

class SyncV2Engine {
  /// Crea el ciclo.
  SyncV2Engine({
    required this.transport,
    required this.local,
    this.maxRestarts = 3,
    this.commonV2Ready = kCommonV2Ready,
    this.readOnly = false,
  });

  /// La API v2.
  final SyncV2Transport transport;

  /// Lo local.
  final SyncV2Local local;

  /// Cuántas veces se empieza de nuevo tras un `412` en una vuelta.
  final int maxRestarts;

  /// Si este móvil anuncia el formato 2 del común y puede empezar el corte
  /// (B4). Por defecto [kCommonV2Ready]; las pruebas lo encienden. Seguir un
  /// corte que ya está hecho no depende de esto.
  final bool commonV2Ready;

  /// Recovery runs the same signature/key/slot checks on isolated stores,
  /// stopping before revocations, rotation, reconciliation or publication.
  final bool readOnly;

  /// Cómo acabó cada intención de retirar un acceso sin respaldo en la
  /// última vuelta que la procesó.
  final Map<String, UnbackedRevocation> unbackedOutcomes = {};

  V2Auth get _auth => V2Auth(
    syncId: local.identity.syncId,
    deviceId: local.identity.deviceId,
    credential: local.keys.serviceCredential,
  );

  RegistryAnchor get _anchor => RegistryAnchor(
    deviceId: local.identity.deviceId,
    signingKey: local.keys.publicKeys.signing,
  );

  /// Crea la lista en el servidor con lo de este móvil (solo su ficha, sin
  /// slots), si todavía no existe. Idempotente.
  ///
  /// Con el formato 2 (el interruptor o la marca irreversible, B4) la lista
  /// nace en formato 2 con `minCommonFormat: 2` y, si el servidor la acepta,
  /// se pone la marca: es el arranque seguro que comparte la renovación
  /// (lote 4, [CommonV2Bootstrap]).
  Future<void> ensureCreated({bool inviteCopy = false}) async {
    try {
      await _ensureCreated(inviteCopy: inviteCopy);
    } on V2ForbiddenException catch (e) {
      if (e.code != 'credential_replaced') rethrow;
      if (local case final RecoverySyncLocal recovery) {
        await recovery.markSyncTransferred();
      }
      throw const V2TransferredException();
    }
  }

  Future<void> _ensureCreated({required bool inviteCopy}) async {
    if (readOnly) throw StateError('read-only recovery');
    if (local case final RecoverySyncLocal recovery) {
      await recovery.assertSyncWritable();
    }
    var state = await local.readState();
    if (state.created) return;
    if (local case final ProtectionSyncLocal protection) {
      await protection.reconcileProtectionBeforePublish();
      state = await local.readState();
    }
    final floor = await local.commonFormatFloor();
    if (floor > kCommonFormatLatest) throw _laterFloor;
    if (!state.commonFormatV2 && floor >= kCommonFormatLatest) {
      state = state.copyWith(commonFormatV2: true);
      await local.saveState(state);
    }
    final registry = await local.registry();
    final localCommon = await local.common();
    final createView = await registry.viewFor(
      me: local.identity.deviceId,
      mySigningKey: local.keys.publicKeys.signing,
      livePeople: livePeopleOf(localCommon),
    );
    // Solo el común publicable sale: sin los regalos públicos tardíos de una
    // persona protegida que este móvil aún no ha podido pasar al bloque
    // secreto (revisión de seguridad del lote 6, 1).
    final common = publishableCommon(
      common: localCommon,
      slots: await local.slots(),
      keyring: await local.updateKeyring((k) => k),
      view: createView,
    );
    // Con la clave común por época, el común nace sellado con una candidata
    // guardada antes (y repartida a quien ya esté en el registro).
    final cycle = state.commonFormatV2 ? CommonV2Cycle(local) : null;
    final plan = cycle == null
        ? null
        : await cycle.prepare(
            const CommonReceived(status: RemoteCommonStatus.empty),
            serverCommon: Uint8List(0),
            serverPackages: const [],
            common: common,
            view: createView,
            registry: registry,
          );
    final format2 =
        state.commonFormatV2 && plan != null && isFamilyEnvelope(plan.common);
    var bootstrap = V2SnapshotUpload(
      common: plan?.common ?? await _seal(common),
      registry: registry.toJson(),
      keyPackages: plan?.mandatory ?? const [],
      minCommonFormat: format2 ? kCommonFormatLatest : null,
      inviteCopy: inviteCopy,
    );
    if (local case final RecoveryBootstrapLocal durable) {
      final previous = await durable.readRecoveryBootstrap();
      if (previous != null) {
        bootstrap = previous;
      } else {
        await durable.saveRecoveryBootstrap(bootstrap);
      }
    }
    // 1.0.6: la intención de publicar, antes de enviar (ver createSent).
    if (!state.createSent) {
      state = state.copyWith(createSent: true);
      await local.saveState(state);
    }
    final result = await transport.createList(_auth, bootstrap);
    switch (result) {
      case V2WriteOk():
        if (plan != null) await cycle!.accepted(plan, plan.mandatory);
        await local.saveState(
          state.copyWith(created: true, version: result.version),
        );
        if (format2) await CommonV2Bootstrap.finish(local);
      case V2WriteStale():
        // Ya existía y este móvil está en ella: se sigue con una vuelta.
        await local.saveState(state.copyWith(created: true));
        // En formato 2 (la respuesta de la creación pudo perderse), la marca
        // también: no se vuelve nunca al formato 1 (revisión de seguridad, M2).
        if (format2) await CommonV2Bootstrap.finish(local);
      case V2WriteNotFound():
        throw const V2ListGoneException();
    }
  }

  static const _laterFloor = EnvelopeFormatException(
    'este móvil ya usa un formato posterior del común: hay que actualizar la '
    'app',
  );

  /// Una vuelta: lee la instantánea entera, reconcilia y, si hay algo que
  /// subir, sube con `If-Match`. Con `412` empieza otra vez (como mucho
  /// [maxRestarts]).
  Future<V2SyncOutcome> sync() async {
    if (local case final RecoverySyncLocal recovery when !readOnly) {
      await recovery.assertSyncWritable();
    }
    // Una vuelta para el bloqueo del común (B3): los reintentos tras `412`
    // no cuentan como vueltas nuevas.
    final round = encodeBase64Url(secureRandomBytes(12));
    for (var attempt = 0; ; attempt++) {
      try {
        return await _once(round);
      } on V2RevokedException {
        await _rememberServiceFailure(revoked: true);
        rethrow;
      } on V2GenerationFullException {
        await _rememberServiceFailure(renew: true);
        rethrow;
      } on V2ForbiddenException catch (e) {
        if (e.code == 'revoked') {
          await _rememberServiceFailure(revoked: true);
          throw const V2RevokedException();
        }
        if (e.code == 'credential_replaced' && !readOnly) {
          if (local case final RecoverySyncLocal recovery) {
            await recovery.markSyncTransferred();
          }
          throw const V2TransferredException();
        }
        rethrow;
      } on _Restart {
        if (attempt >= maxRestarts) {
          throw const SyncTransportException(
            SyncFailure.server,
            'la lista cambia demasiado deprisa',
          );
        }
      }
    }
  }

  Future<void> _rememberServiceFailure({
    bool revoked = false,
    bool renew = false,
  }) async {
    final state = await local.readState();
    final previous = state.health;
    await local.saveState(
      state.copyWith(
        health: V2Health(
          unbackedCredentials: previous?.unbackedCredentials ?? const [],
          departedDevices: previous?.departedDevices ?? const [],
          revokedByOthers: revoked || (previous?.revokedByOthers ?? false),
          renewSuggested: renew || (previous?.renewSuggested ?? false),
          commonBlocked: previous?.commonBlocked ?? false,
          commonBlockedWriter: previous?.commonBlockedWriter,
          commonPackagesFull: previous?.commonPackagesFull ?? false,
          commonKeyringFull: previous?.commonKeyringFull ?? false,
          retainedCommons: previous?.retainedCommons ?? 0,
        ),
      ),
    );
  }

  Future<Uint8List> _seal(FamilyDoc doc) => seal(
    doc: doc.toJson(),
    listId: local.identity.listId,
    fromNode: local.node,
    at: doc.maxStamp?.pack() ?? '',
    key: local.familyKey,
  );

  Future<void> _retryPendingUnbackedRevocations() async {
    final pending = (await local.readState()).pendingUnbackedRevocations;
    for (final id in pending.toList()..sort()) {
      var failures = 0;
      var stale = 0;
      while (true) {
        try {
          var state = await local.readState();
          final got = await transport.getList(_auth);
          if (got is V2GetNotFound) throw const V2ListGoneException();
          if (got is! V2GetOk) {
            throw const SyncTransportException(SyncFailure.protocol, '304');
          }
          final snap = got.snapshot;
          if (state.version != null && snap.version < state.version!) {
            throw V2RollbackException(
              known: state.version!,
              served: snap.version,
            );
          }
          final before = await local.registry();
          final beforeView = await before.viewFor(
            me: _auth.deviceId,
            mySigningKey: local.keys.publicKeys.signing,
            livePeople: livePeopleOf(await local.common()),
          );
          final DeviceRegistry remote;
          try {
            remote = await DeviceRegistry.fromJsonVerified(
              snap.registry,
              anchor: _anchor,
            );
          } on RegistryException {
            throw const SyncTransportException(
              SyncFailure.protocol,
              'registro no válido',
            );
          }
          final registry = await before.merge(remote, anchor: _anchor);
          await local.saveRegistry(registry);
          final view = await registry.viewFor(
            me: _auth.deviceId,
            mySigningKey: local.keys.publicKeys.signing,
            livePeople: livePeopleOf(await local.common()),
          );
          if (view.revokedByOthers) throw const V2RevokedException();
          state = state.copyWith(
            version: snap.version,
            knownMembers: {
              ...state.knownMembers,
              ...beforeView.everMembers,
              ...view.everMembers,
            },
          );
          await local.saveState(state);
          final registryBacked = id == view.me || view.device(id) != null;
          final known = state.knownMembers.contains(id);
          final active = snap.devices.any(
            (d) => d.deviceId == id && !d.revoked,
          );
          var outcome = UnbackedRevocation.alreadyResolved;
          if (registryBacked) {
            outcome = UnbackedRevocation.keptBecauseBacked;
          } else if (known) {
            outcome = UnbackedRevocation.knownMember;
          } else if (active) {
            // Condicional (B2): solo si la lista sigue en la versión que se
            // acaba de verificar. Con `412` se vuelve al GET y se decide de
            // nuevo: el respaldo pudo publicarse entre este GET y el POST.
            final version = await transport.revoke(
              _auth,
              id,
              ifVersion: snap.version,
            );
            if (version < snap.version) {
              throw V2RollbackException(known: snap.version, served: version);
            }
            state = state.copyWith(version: version);
            outcome = UnbackedRevocation.revoked;
          }
          await local.saveState(
            state.copyWith(
              pendingUnbackedRevocations: {...state.pendingUnbackedRevocations}
                ..remove(id),
            ),
          );
          unbackedOutcomes[id] = outcome;
          break;
        } on V2RevokeStaleException {
          // No se ha revocado nada. Si la lista no se está quieta, la
          // intención queda pendiente y la vuelta sigue (revisión de seguridad, B1): mejor
          // una credencial sin respaldo viva un rato que cortar una
          // respaldada. No hay escape incondicional.
          if (++stale > maxRestarts) break;
        } on SyncTransportException catch (e) {
          if (failures++ >= 2 ||
              (e.failure != SyncFailure.network &&
                  e.failure != SyncFailure.server)) {
            rethrow;
          }
          // También un reintento dentro de la misma vuelta vuelve al GET.
        }
      }
    }
  }

  Future<V2SyncOutcome> _once(String round) async {
    final auth = _auth;
    final me = auth.deviceId;
    if (!readOnly) {
      await _retryPendingRevocations(transport: transport, local: local);
      await _retryPendingUnbackedRevocations();
    }
    var state = await local.readState();
    // B4 (revisión de seguridad, B2): si el `PUT` del corte entró y se apuntó (`lastKid`),
    // la marca va antes de abrir nada, aunque el servidor diga otra cosa.
    if (state.commonMigration &&
        (await local.readCommonKeys())?.lastKid != null) {
      state = await CommonV2Bootstrap.finish(local);
    }
    final got = await transport.getList(auth);
    final V2Snapshot snap;
    switch (got) {
      case V2GetOk():
        snap = got.snapshot;
      case V2GetNotModified():
        // Sin If-None-Match no puede pasar.
        throw const SyncTransportException(SyncFailure.protocol, '304');
      case V2GetNotFound():
        throw const V2ListGoneException();
    }
    final known = state.version;
    if (known != null && snap.version < known) {
      throw V2RollbackException(known: known, served: snap.version);
    }

    // B4: el corte al formato 2. Un mínimo posterior al que conoce esta
    // versión pide actualizar; la marca irreversible vuelve a encender el
    // interruptor si el estado se perdió; con [commonV2Ready] este móvil
    // anuncia la capacidad (una vez: cambia la versión) y, si el servidor ya
    // exige el formato 2, lo sigue sin abrir nunca un formato 1.
    if (snap.minCommonFormat > kCommonFormatLatest) {
      throw const EnvelopeFormatException(
        'la familia usa un formato posterior del común: hay que actualizar '
        'la app',
      );
    }
    final floor = await local.commonFormatFloor();
    if (floor > kCommonFormatLatest) throw _laterFloor;
    if (!state.commonFormatV2 && floor >= kCommonFormatLatest) {
      state = state.copyWith(commonFormatV2: true);
      await local.saveState(state);
    }
    final myCredential = activeCredential(snap.devices, me);
    if (!readOnly &&
        commonV2Ready &&
        myCredential != null &&
        myCredential.role == 'device' &&
        myCredential.commonFormat < kCommonFormatLatest) {
      await transport.announceCommonFormat(auth, kCommonFormatLatest);
      throw const _Restart();
    }
    // 1.0.6: este móvil lee listas de hasta kMaxSlotsPerList slots. El Worker
    // no deja pasar de 64 (lo que admite un 1.0.5) mientras falte un móvil
    // activo por anunciarlo. Una vez. Solo mueve la versión si con él cambia
    // el tope (es el último): entonces se vuelve a empezar con la instantánea
    // nueva; si no, la vuelta sigue. Si falla, se intenta en la siguiente.
    if (!readOnly &&
        snap.slotCapacitySupported &&
        myCredential != null &&
        myCredential.role == 'device' &&
        myCredential.slotCapacity < kV2SlotCapacity) {
      int? moved;
      try {
        moved = await transport.announceSlotCapacity(auth);
      } on SyncTransportException {
        // Se repite en la vuelta siguiente.
      }
      if (moved != null && moved != snap.version) throw const _Restart();
    }
    // Se sigue por la marca, no por el interruptor (revisión de seguridad, M2): un móvil con
    // el interruptor encendido y sin la marca también la pone.
    final follow =
        floor < kCommonFormatLatest &&
        snap.minCommonFormat >= kCommonFormatLatest;
    // Un mínimo 2 con un común que no es del formato 2 no es un corte: el
    // Worker no lo permite, así que es un servidor que miente (revisión de seguridad, B1).
    if (follow && !isFamilyEnvelope(snap.common)) {
      throw const SyncTransportException(
        SyncFailure.protocol,
        'el servidor pide el formato 2 con un común que no lo es',
      );
    }

    // 1. Los slots de esta misma versión: solo los que han cambiado. Con
    // `412` la instantánea se ha movido y se descarta lo leído.
    var common = await local.common();
    var localSlots = await local.slots();
    final fetched = <SealedSlot>[];
    final slotVersions = <String, int>{};
    final ignored = <String, IgnoredSlot>{};
    var unreadable = 0;
    final webDone = <String, int>{};
    final webWait = <String, List<int>>{};
    final fetchMillis = clock.now().millisecondsSinceEpoch;
    for (final ref in snap.slots) {
      if (common.record(Collections.recipients, ref.personId)?.isDeleted ==
          true) {
        continue;
      }
      final was = state.ignoredSlots[ref.key];
      if (was != null && was.version == ref.version) {
        ignored[ref.key] = was;
        continue;
      }
      if (state.webInboxDone[ref.key] == ref.version) {
        webDone[ref.key] = ref.version;
        continue;
      }
      final waited = state.webInboxWait[ref.key];
      if (waited != null &&
          waited[0] == ref.version &&
          fetchMillis - waited[1] < kWebInboxRetry.inMilliseconds) {
        webWait[ref.key] = waited;
        continue;
      }
      final have = localSlots.slotOf(ref.personId, ref.deviceId);
      if (have != null && state.slotVersions[ref.key] == ref.version) {
        slotVersions[ref.key] = ref.version;
        continue;
      }
      final pendingKey = '${auth.syncId}|${ref.key}|${ref.version}';
      final cached = readOnly && local is RecoverySlotCacheLocal
          ? await (local as RecoverySlotCacheLocal).readRecoverySlot(
              snap.version,
              ref,
            )
          : (readOnly ? null : _pendingSlotDownloads[pendingKey]);
      final slot = cached == null
          ? await transport.getSlot(
              auth,
              version: snap.version,
              personId: ref.personId,
              deviceId: ref.deviceId,
            )
          : V2SlotOk(
              version: snap.version,
              slotVersion: ref.version,
              data: cached,
            );
      switch (slot) {
        case V2SlotStale():
        case V2SlotMissing():
          throw const _Restart();
        case V2SlotOk():
          if (slot.slotVersion != ref.version) {
            throw const SyncTransportException(
              SyncFailure.protocol,
              'el slot no es el del manifiesto',
            );
          }
          if (readOnly && cached == null && local is RecoverySlotCacheLocal) {
            await (local as RecoverySlotCacheLocal).saveRecoverySlot(
              snap.version,
              ref,
              slot.data,
            );
          }
          final SealedSlot parsed;
          try {
            parsed = SealedSlot.parse(slot.data);
          } on ProtectedEnvelopeException {
            _pendingSlotDownloads.remove(pendingKey);
            // Un slot que nadie puede leer no tumba la vuelta de la familia
            // (revisión de seguridad, M1): se rechaza, se apunta con su versión y no se
            // vuelve a bajar hasta que cambie.
            unreadable++;
            ignored[ref.key] = IgnoredSlot(
              ref.version,
              IgnoredSlotReason.unreadable,
            );
            continue;
          }
          // Una respuesta sustituida: el slot dice ser de otro recurso.
          if (parsed.header.personId != ref.personId ||
              parsed.header.writer != ref.deviceId) {
            _pendingSlotDownloads.remove(pendingKey);
            throw const SyncTransportException(
              SyncFailure.protocol,
              'el slot no es del recurso pedido',
            );
          }
          // Solo se guarda para la vuelta siguiente lo que tiene estructura de
          // slot y es del recurso pedido (firma, derechos y revisión se
          // comprueban después, igual que con uno recién bajado).
          if (!readOnly && cached == null) {
            if (_pendingSlotDownloads.length >= kMaxSlotsPerList) {
              _pendingSlotDownloads.clear();
            }
            _pendingSlotDownloads[pendingKey] = slot.data;
          }
          fetched.add(parsed);
          slotVersions[ref.key] = ref.version;
      }
    }
    // La descarga de esta lista terminó: lo bajado a medias ya está en
    // [fetched].
    _pendingSlotDownloads.removeWhere(
      (k, _) => k.startsWith('${auth.syncId}|'),
    );

    // 2. El documento común. Con la clave común por época va después del
    // registro (ADR 0005, sección 4): primero los permisos y los paquetes.
    var v2 = state.commonFormatV2 || follow || state.commonMigrationPut;
    FamilyDoc? remoteCommon;
    if (!v2) {
      try {
        final opened = await open(
          snap.common,
          key: local.familyKey,
          expectedListId: local.identity.listId,
        );
        remoteCommon = FamilyDoc.fromJson(opened.doc);
        // Una versión desconocida no entra nunca. Un común que dice 1 (alguien
        // bajó la marca) sí: lo decide la identidad v2 de este móvil, la
        // fusión vuelve a marcar 2 (`keepProtocolV2`) y esta misma vuelta
        // sube el común reparado (hallazgo 1). Rechazarlo dejaba a toda la
        // familia sin sincronizar.
        if (syncProtocolOf(remoteCommon) == null) {
          throw const EnvelopeFormatException('documento de otro protocolo');
        }
        await local.mergeCommon(remoteCommon, fromNode: opened.header.fromNode);
        common = await local.common();
      } on FormatException {
        throw const EnvelopeFormatException('documento no válido');
      }
    }
    // 3. El registro de la instantánea, antes de abrir ningún paquete (7
    // resto): emisor y receptor leen el mismo estado.
    final DeviceRegistry remoteRegistry;
    try {
      remoteRegistry = await DeviceRegistry.fromJsonVerified(
        snap.registry,
        anchor: _anchor,
      );
    } on RegistryException {
      throw const SyncTransportException(
        SyncFailure.protocol,
        'registro no válido',
      );
    }
    final registry = await (await local.registry()).merge(
      remoteRegistry,
      anchor: _anchor,
    );
    if (readOnly) {
      final previous = (await local.registry()).toLocalStoreJson();
      final remote = remoteRegistry.toLocalStoreJson();
      final actual = registry.toLocalStoreJson();
      for (final field in [
        'records',
        'vouches',
        'revocations',
        'localTypeConflicts',
      ]) {
        final expected = {
          for (final source in [previous, remote])
            for (final value in source[field] as List? ?? [])
              canonicalJsonOf(value),
        };
        final kept = {
          for (final value in actual[field] as List? ?? [])
            canonicalJsonOf(value),
        };
        if (!kept.containsAll(expected)) {
          throw const V2RecoveryIncompleteException('registry_union_full');
        }
      }
    }
    await local.saveRegistry(registry);
    var view = await registry.viewFor(
      me: me,
      mySigningKey: local.keys.publicKeys.signing,
      livePeople: livePeopleOf(common),
    );
    if (!readOnly && view.selfRevoked) {
      await retireDeviceNames(local, [me]);
    }
    if (view.revokedByOthers) {
      throw const V2RevokedException();
    }
    state = state.copyWith(
      created: true,
      version: snap.version,
      knownMembers: {...state.knownMembers, ...view.everMembers},
    );
    await local.saveState(state);

    // El servidor no decide confianza. Solo una revocación verificada (o
    // una aprobación por una credencial así revocada, sin ficha respaldada)
    // autoriza este corte automático; `devices` por sí solo no basta.
    final backed = {...view.members, for (final p in view.pending) p.deviceId};
    // Los huérfanos conocidos conservan su credencial para confirmarlos
    // individualmente. Solo las credenciales ocultas heredan el corte.
    final knownDevices = state.knownMembers;
    final tainted = {...view.revoked};
    var more = true;
    while (more) {
      more = false;
      for (final d in snap.devices) {
        if (!knownDevices.contains(d.deviceId) &&
            tainted.contains(d.approvedBy) &&
            tainted.add(d.deviceId)) {
          more = true;
        }
      }
    }
    final revoke = {
      for (final d in snap.devices)
        if (!d.revoked && d.deviceId != me && tainted.contains(d.deviceId))
          d.deviceId,
    };
    if (!readOnly && revoke.isNotEmpty) {
      await local.saveState(
        state.copyWith(
          pendingRevocations: {...state.pendingRevocations, ...revoke},
        ),
      );
      await _retryPendingRevocations(transport: transport, local: local);
      // POST /revoke cambia la versión de la instantánea.
      throw const _Restart();
    }

    // B4: con los permisos ya resueltos, seguir el corte o activarlo.
    var cutover = CommonCutover.none;
    FamilyKey? legacyKey;
    var legacyImported = false;
    if (follow) {
      // Otro móvil ya cortó (o este, y se cerró antes de la marca): la
      // clave de siempre queda como histórica. La marca, solo después de
      // ver en el común la firma de un miembro activo (revisión de seguridad, B1).
      legacyImported = await CommonV2Cycle(local)
          .importLegacyKey(view, local.familyKey);
    } else if (state.commonMigrationPut && !state.commonFormatV2) {
      // El `PUT` del corte ya se intentó: nunca más el formato 1. Se
      // reintenta sellando lo que hay.
      cutover = CommonCutover.activating;
    } else if (!v2) {
      final can =
          !readOnly &&
          commonV2Ready &&
          snap.minCommonFormat < kCommonFormatLatest &&
          !isFamilyEnvelope(snap.common) &&
          membersAnnouncedCommonV2(view, snap.devices);
      if (can) {
        // Lo primero, la migración pendiente; después la clave histórica.
        // En esta vuelta se abre por última vez el formato 1 y se sube el
        // común acumulado en formato 2 con el mínimo del Worker.
        if (!state.commonMigration) {
          state = state.copyWith(commonMigration: true);
          await local.saveState(state);
        }
        if (await CommonV2Cycle(local).importLegacyKey(view, local.familyKey)) {
          v2 = true;
          legacyKey = local.familyKey;
          cutover = CommonCutover.activating;
        } else {
          cutover = CommonCutover.waiting;
        }
      } else {
        // No se había publicado nada en formato 2 (el servidor seguiría en
        // el mínimo 1): la migración pendiente se deja para otra vez.
        if (state.commonMigration) {
          state = state.copyWith(commonMigration: false);
          await local.saveState(state);
        }
        if (commonV2Ready) cutover = CommonCutover.waiting;
      }
    }

    // 4-6 con la clave común por época (ADR 0005, B3): con los permisos ya
    // resueltos (el contexto de la época no depende de las personas), los
    // paquetes v4 y el común. Después, la vista con las personas del común
    // fusionado para las sorpresas.
    final cycle = v2 ? CommonV2Cycle(local) : null;
    CommonReceived? received;
    if (cycle != null) {
      received = await cycle.receive(
        remote: snap.common,
        packages: snap.keyPackages,
        registry: registry,
        view: view,
        round: round,
        nowMillis: clock.now().millisecondsSinceEpoch,
        legacyKey: legacyKey,
      );
      if (follow) {
        // Seguir el corte solo con un común firmado por un miembro activo:
        // abierto, o que espera su clave, o basura cifrada con firma válida.
        // Un mínimo 2 sin eso es un servidor que miente: no se marca ni se
        // sustituye nada.
        const signed = {
          RemoteCommonStatus.opened,
          RemoteCommonStatus.missingKey,
          RemoteCommonStatus.unreadable,
        };
        if (!signed.contains(received.status)) {
          throw const SyncTransportException(
            SyncFailure.protocol,
            'el corte del servidor no lleva un común firmado por la familia',
          );
        }
        if (legacyImported) {
          state = await CommonV2Bootstrap.finish(local);
          cutover = CommonCutover.followed;
        }
      }
      common = await local.common();
      view = await registry.viewFor(
        me: me,
        mySigningKey: local.keys.publicKeys.signing,
        livePeople: livePeopleOf(common),
      );
    }

    if (!readOnly) {
      await retireDeviceNames(local, view.explicitlyRevoked);
      common = await local.common();
    }

    // The common tombstone retires local scopes even when their slots are
    // still on the server. Discard earlier downloads before storing slots.
    final tombstoned = {
      for (final record
          in common.collections[Collections.recipients]?.values ??
              const <SyncRecord>[])
        if (record.isDeleted && kSyncIdPattern.hasMatch(record.id)) record.id,
    };
    if (tombstoned.isNotEmpty) {
      for (final person in tombstoned) {
        final own = localSlots.slotOf(person, me);
        if (local case final RecoverySyncLocal recovery when own != null) {
          await recovery.rememberSlotRevision(person, own.header.revision);
        }
        await local.deleteScope(person);
      }
      localSlots = localSlots.withoutPeople(tombstoned);
      fetched.removeWhere((slot) => tombstoned.contains(slot.header.personId));
    }

    // La outbox es una intención, no un permiso permanente. Los obsoletos
    // nunca salen en el PUT; se conservan como intención de regeneración
    // hasta aceptarlo, también si se cierra antes de repartir de nuevo.
    final obsolete = state.keyPackageOutbox
        .where((p) => !_packageAllowed(p, view))
        .toList();

    // 4. Los paquetes para este móvil.
    await _openPackages(snap.keyPackages, view);

    if (readOnly) {
      if (!view.selfApproved) {
        throw const V2RecoveryIncompleteException('person_not_approved');
      }
      if (received != null && received.status != RemoteCommonStatus.opened) {
        throw const V2RecoveryIncompleteException('common_unavailable');
      }
      final fresh = <SealedSlot>[];
      for (final slot in fetched) {
        final h = slot.header;
        if (view.entitled(h.writer, h.personId) == null) continue;
        if (h.epoch > view.epoch) {
          throw const V2RecoveryIncompleteException('slot_future_epoch');
        }
        final min = state.minSlotRevisions['${h.personId}/${h.writer}'];
        if (min != null && h.revision < min) {
          throw const V2RecoveryIncompleteException('slot_rollback');
        }
        fresh.add(slot);
      }
      final (merged, refused) = await localSlots.merge(fresh, view: view);
      final unreadableAuthorized = ignored.entries.any((e) {
        final pair = e.key.split('/');
        return e.value.reason == IgnoredSlotReason.unreadable &&
            view.entitled(pair[1], pair[0]) != null;
      });
      if (refused != 0 || unreadableAuthorized) {
        throw const V2RecoveryIncompleteException('invalid_slot');
      }
      await local.saveSlots(merged);
      final ring = await local.updateKeyring((k) => k);
      final people = {
        ...ring.people,
        for (final ref in snap.slots) ref.personId,
        for (final e in publishedPolicies(common).entries)
          if (e.value.hideOwnGifts) e.key,
      };
      for (final person in people) {
        if (!view.selfEntitled(person)) continue;
        final scope = await openScope(
          personId: person,
          slots: merged,
          keyring: ring,
          view: view,
        );
        if (scope == null || scope.unreadableWriters.isNotEmpty) {
          throw const V2RecoveryIncompleteException('missing_scope_package');
        }
        await local.saveScope(person, scope.doc);
      }
      // Confirm the manifest stayed coherent during the slot download.
      final check = await transport.getList(auth);
      if (check is! V2GetOk || check.snapshot.version != snap.version) {
        throw const _Restart();
      }
      return V2SyncOutcome(
        version: snap.version,
        view: view,
        hasOtherActiveCredential: snap.devices.any(
          (d) => !d.revoked && d.deviceId != me,
        ),
        uploaded: false,
        unbackedCredentials: const [],
        frozenPeople: const [],
        publishedPeople: const [],
        rejectedSlots: 0,
        published: V2Published(
          common: snap.common,
          registry: snap.registry,
          keyPackages: snap.keyPackages,
        ),
      );
    }

    // 5. Rotación en cada vuelta (es idempotente; 7 resto).
    final keyring = await local.updateKeyring((current) => current);
    final rotation = await rotateSurpriseKeys(
      keyring: keyring,
      view: view,
      keys: local.keys,
      deletedPeople: tombstoned,
    );
    Future<void> enqueue(List<KeyBundle> bundles) async {
      if (bundles.isEmpty) return;
      state = state.copyWith(
        keyPackageOutbox: [
          ...state.keyPackageOutbox,
          for (final bundle in bundles) bundle.toJson(),
        ],
      );
      await local.saveState(state);
    }

    await enqueue(rotation.bundles);
    // La rotación puede crear claves sin paquetes si solo queda este móvil
    // con derecho. Se guarda también entonces, después de la outbox.
    // Se aplica sobre el llavero de ahora (otra escritura pudo entrar entre
    // medias): se quitan las purgadas y se añaden las candidatas nuevas.
    await local.updateKeyring((current) {
      var next = current;
      for (final person in rotation.purgedPeople) {
        next = next.without(person);
      }
      for (final key in rotation.keyring.keys) {
        if (next.keyFor(key.personId, key.epoch, key.kid) != null) continue;
        try {
          next = next.withKey(
            key,
            registryEpoch: view.epoch,
            allowed: view.entitledDevices(key.personId),
          );
        } on KeyringConflictException {
          // La que ya había gana; la nueva se vuelve a crear la próxima.
        }
      }
      return next;
    });
    final frozen = rotation.frozenPeople;
    // Un móvil que ha pasado a tener derecho después (se emparejó o lo han
    // aprobado) recibe la clave de la época actual de quien ya la tiene.
    final shared = await local.updateKeyring((k) => k);
    final newcomers = <String>{
      for (final p in obsolete)
        if (p['to'] is String) p['to'] as String,
    };
    for (final person in shared.people) {
      final key = shared.sealingKeyFor(
        person,
        view.epoch,
        allowed: view.entitledDevices(person),
      );
      if (key == null || !view.selfEntitled(person)) continue;
      for (final device in view.entitledDevices(person)) {
        if (device != me && !key.audience.contains(device)) {
          newcomers.add(device);
        }
      }
    }
    for (final device in newcomers.toList()..sort()) {
      final current = await local.updateKeyring((k) => k);
      final share = await shareSurpriseKeysWith(
        deviceId: device,
        keyring: current,
        view: view,
        keys: local.keys,
      );
      await enqueue(share.bundles);
      await local.updateKeyring((now) {
        var next = now;
        for (final key in share.keyring.keys) {
          try {
            next = next.withKey(
              key,
              registryEpoch: view.epoch,
              allowed: view.entitledDevices(key.personId),
            );
          } on KeyringConflictException {
            continue;
          }
        }
        return next;
      });
    }
    for (final person in rotation.purgedPeople) {
      await local.deleteScope(person);
    }

    // 5b. Las webs de la persona de este móvil (1.0.6, ADR 0009): la clave
    // de cada candidata de la época de cada persona que no es la suya, sin
    // añadir la web a la audiencia. Una por (web, candidata) y ficha.
    final ownWebs = view.ownWebs();
    {
      final ring = await local.updateKeyring((k) => k);
      final present = {
        for (final p in [...snap.keyPackages, ...state.keyPackageOutbox])
          if (p['from'] == me) jsonEncode(p),
      };
      final shares = <String, String>{};
      final bundles = <KeyBundle>[];
      for (final web in ownWebs) {
        for (final key in ring.keys) {
          if (key.epoch != view.epoch ||
              key.personId == web.personId ||
              !view.selfEntitled(key.personId)) {
            continue;
          }
          final id = [
            web.deviceId,
            web.recordDigest,
            view.self.recordDigest,
            key.personId,
            key.epoch,
            key.kid,
          ].join('|');
          final known = state.webShares[id];
          if (known != null && present.contains(known)) {
            shares[id] = known;
            continue;
          }
          try {
            final bundle = await KeyBundle.sealSurpriseKeyForOwnWeb(
              sender: local.keys,
              view: view,
              toDevice: web.deviceId,
              key: key,
            );
            bundles.add(bundle);
            shares[id] = jsonEncode(bundle.toJson());
          } on KeyBundleException {
            continue;
          }
        }
      }
      if (bundles.isNotEmpty ||
          shares.length != state.webShares.length ||
          shares.keys.any((k) => !state.webShares.containsKey(k))) {
        state = state.copyWith(webShares: shares);
        await enqueue(bundles);
        await local.saveState(state);
      }
    }
    final ownWebIds = {for (final w in ownWebs) w.deviceId};

    // 6. Los slots: los nuevos, verificados contra el registro ya fusionado;
    // los que son más viejos de lo que el anfitrión ya conocía no entran.
    final fresh = <SealedSlot>[];
    var rejected = unreadable;
    // Los slots de una web son buzones (1.0.6, ADR 0009): nunca entran en el
    // conjunto. Los de las webs propias se recogen al publicar; los demás se
    // ignoran mientras no cambien.
    final inboxes = <String, List<SealedSlot>>{};
    for (final slot in fetched) {
      final key = '${slot.header.personId}/${slot.header.writer}';
      if (view.device(slot.header.writer)?.kind == DeviceKind.web) {
        if (ownWebIds.contains(slot.header.writer) &&
            slot.header.personId != view.myPerson) {
          (inboxes[slot.header.personId] ??= []).add(slot);
        } else {
          ignored[key] = IgnoredSlot(
            slotVersions[key]!,
            IgnoredSlotReason.webInbox,
          );
        }
        continue;
      }
      final min = state.minSlotRevisions[key];
      if (min != null && slot.header.revision < min) {
        rejected++;
        continue;
      }
      fresh.add(slot);
    }
    final (merged, refused) = await localSlots.merge(fresh, view: view);
    rejected += refused;
    localSlots = merged.pruned(view);
    // El slot de un escritor revocado de verdad (revocación firmada, sin
    // ambigüedad: `linkedSigningKey` es null para un id ambiguo) no cuenta,
    // así que no hace falta bajarlo en cada vuelta. Los que se apuntaron
    // así y ya no lo están (un id ambiguo que se aclara) se vuelven a bajar
    // en la vuelta siguiente (revisión de seguridad, B2).
    bool reallyRevoked(String writer) =>
        view.revoked.contains(writer) && view.linkedSigningKey(writer) != null;
    bool unknown(String writer) => view.device(writer) == null;
    ignored.removeWhere((key, entry) {
      final writer = key.substring(key.indexOf('/') + 1);
      return switch (entry.reason) {
        IgnoredSlotReason.revoked => !reallyRevoked(writer),
        IgnoredSlotReason.unknownWriter => !unknown(writer),
        IgnoredSlotReason.unreadable => false,
        IgnoredSlotReason.webInbox =>
          view.device(writer)?.kind != DeviceKind.web ||
              ownWebIds.contains(writer),
      };
    });
    for (final ref in snap.slots) {
      if (ignored.containsKey(ref.key) ||
          localSlots.slotOf(ref.personId, ref.deviceId) != null) {
        continue;
      }
      if (reallyRevoked(ref.deviceId)) {
        ignored[ref.key] = IgnoredSlot(ref.version, IgnoredSlotReason.revoked);
      } else if (unknown(ref.deviceId) && ref.deviceId != me) {
        // Un escritor que el registro no conoce no cuenta: no se baja en
        // cada vuelta mientras siga sin conocerse.
        ignored[ref.key] = IgnoredSlot(
          ref.version,
          IgnoredSlotReason.unknownWriter,
        );
      }
    }

    // Application migrations must see this snapshot before a policy is
    // signed or the common is sealed. Repeat this on every 412 restart.
    await local.saveSlots(localSlots);
    if (local case final ProtectionSyncLocal protection) {
      await protection.reconcileProtectionBeforePublish();
      common = await local.common();
      localSlots = await local.slots();
      state = await local.readState();
    }

    // 7. Un solo punto decide qué slots se vuelven a sellar (pendiente 15).
    final currentKeyring = await local.updateKeyring((k) => k);
    final changes = <V2SlotChange>[];
    final published = <String>[];
    // Con el común bloqueado no cuenta como cambio: si no, los slots se
    // volverían a sellar en cada vuelta mientras dura la espera (B1 de la revisión de seguridad).
    // Lo que sale es el común publicable: sin los regalos públicos tardíos de
    // una persona protegida que este móvil no ha podido sellar (revisión de seguridad, lote
    // 6, 1). El común local no se toca y se reconcilia cuando llegue la clave.
    final outgoing = publishableCommon(
      common: common,
      slots: localSlots,
      keyring: currentKeyring,
      view: view,
      remote: received != null ? received.doc : remoteCommon,
    );
    final commonChanged = received != null
        ? received.doc == null
              ? !commonWaits(received.status)
              : outgoing.canonicalJson() != received.doc!.canonicalJson()
        : outgoing.canonicalJson() != remoteCommon!.canonicalJson();
    final nowMillis = clock.now().millisecondsSinceEpoch;
    // Los que no cupieron la vez anterior van primero: ninguno espera más
    // de una vuelta por culpa de los demás.
    final order = currentKeyring.people.toList()
      ..sort((a, b) {
        final da = state.deferred.contains(a) ? 0 : 1;
        final db = state.deferred.contains(b) ? 0 : 1;
        return da != db ? da - db : a.compareTo(b);
      });
    final deferred = <String>{};
    // Los slots propios que sobran se retiran (el Worker lo permite): los de
    // personas borradas y, con la ficha aprobada, el de la persona de este
    // móvil (ha pasado a ser la protegida). Nunca uno ajeno.
    for (final ref in snap.slots) {
      if (ref.deviceId == me &&
          (tombstoned.contains(ref.personId) ||
              (view.selfApproved && view.myPerson == ref.personId))) {
        changes.add(
          V2SlotChange(personId: ref.personId, deviceId: me, data: null),
        );
      }
    }
    // Sitio para slots nuevos (los ajenos no se borran, B2): el tope de la
    // lista y el de cada escritor. Sustituir el propio siempre cabe.
    final onServer = {for (final ref in snap.slots) ref.key};
    final retiring = changes.length;
    // El tope que dice el Worker: 64 mientras algún móvil no haya anunciado
    // `slotCapacity` (o si el Worker es anterior y no lo dice).
    final listCap = min(
      kMaxSlotsPerList,
      snap.capacity?.slots?.max ?? kV2LegacyMaxSlots,
    );
    var room = listCap - (snap.slots.length - retiring);
    var ownRoom =
        kV2MaxSlotsPerWriter -
        (snap.slots.where((r) => r.deviceId == me).length - retiring);
    var slotsFull = false;
    var writerSlotsFull = false;
    // Personas con algún buzón recogido en esta vuelta: siguen en `deferred`
    // hasta que su slot entre (B5), para declarar `s[web]` cuanto antes.
    final collectedPeople = <String>{};
    for (final person in order) {
      if (!view.selfEntitled(person) || frozen.contains(person)) continue;
      if (tombstoned.contains(person)) continue;
      final sealing = currentKeyring.sealingKeyFor(
        person,
        view.epoch,
        allowed: view.entitledDevices(person),
      );
      if (sealing == null) continue;
      final mine = localSlots.slotOf(person, me)?.header;
      final due =
          state.deferred.contains(person) ||
          slotPublishDue(
            mine: mine,
            epoch: view.epoch,
            sealingKid: sealing.kid,
            nowMillis: nowMillis,
            commonChanged: commonChanged,
          );
      // Un buzón por recoger no obliga a publicar: solo si se recoge (B2).
      if (!due && !inboxes.containsKey(person)) continue;
      if (published.length >= kV2MaxSlotsPerPut) {
        // El Worker lee como mucho 5 MiB (hallazgo 10): el resto, en la
        // vuelta siguiente.
        deferred.add(person);
        continue;
      }
      // Un alta que no cabe (revisión de seguridad, M2) no se sella ni se guarda: el `PUT`
      // sube igualmente el común, el registro y los paquetes, y se avisa.
      final adding = !onServer.contains('$person/$me');
      if (adding && (room <= 0 || ownRoom <= 0)) {
        // El tope de la lista se arregla renovando; el del escritor no (es
        // por móvil), así que va con su propio aviso.
        if (room <= 0) slotsFull = true;
        if (ownRoom <= 0) writerSlotsFull = true;
        continue;
      }
      final opened = await openScope(
        personId: person,
        slots: localSlots,
        keyring: currentKeyring,
        view: view,
      );
      if (opened == null) continue;
      var scope =
          (await local.readScope(person) ?? FamilyDoc.empty(view.listId)).merge(
            opened.doc,
          );
      // 1.0.6 (ADR 0009): los buzones de las webs propias para esta persona.
      final collected = await _collectWebInboxes(
        person: person,
        scope: scope,
        opened: opened,
        inboxes: inboxes[person] ?? const [],
        ownWebIds: ownWebIds,
        view: view,
        keyring: currentKeyring,
        state: state,
        slotVersions: slotVersions,
        nowMillis: nowMillis,
        common: common,
      );
      if (!identical(collected.scope, scope)) {
        scope = collected.scope;
        await local.saveScope(person, scope);
      }
      webDone.addAll(collected.done);
      for (final key in collected.waiting) {
        webWait[key] = [slotVersions[key]!, nowMillis];
      }
      if (!identical(collected.state, state)) {
        state = collected.state;
        await local.saveState(state);
      }
      if (collected.collected) collectedPeople.add(person);
      if (!due && !collected.collected) continue;
      try {
        final result = await publishScope(
          slots: localSlots,
          opened: opened,
          view: view,
          writerKeys: local.keys,
          keyring: currentKeyring,
          policy: opened.effective(publishedPolicy(common, person)),
          doc: scope,
          nowMillis: nowMillis,
          revisionFloor: local is RecoverySyncLocal
              ? await (local as RecoverySyncLocal).slotRevisionFloor(person)
              : 0,
          extraSeen: {
            for (final e in state.webInboxFloors.entries)
              if (e.key.startsWith('$person/') &&
                  view.device(e.key.substring(person.length + 1))?.kind ==
                      DeviceKind.web)
                e.key.substring(person.length + 1): e.value,
          },
          extraRejected: {
            for (final e in state.webInboxRejected.entries)
              if (e.key.startsWith('$person/') &&
                  view.device(e.key.substring(person.length + 1))?.kind ==
                      DeviceKind.web)
                e.key.substring(person.length + 1): e.value,
          },
          extraPlanInboxSeen: {
            for (final e in state.webPlanInboxSeen.entries)
              if (e.key.startsWith('$person/') &&
                  view.device(e.key.substring(person.length + 1))?.kind ==
                      DeviceKind.web)
                e.key.substring(person.length + 1): e.value,
          },
        );
        if (local case final RecoverySyncLocal recovery) {
          await recovery.rememberSlotRevision(
            person,
            result.slot.header.revision,
          );
        }
        final (withMine, _) = await localSlots.merge([result.slot], view: view);
        localSlots = withMine;
        await local.saveScope(person, result.scope);
        changes.add(
          V2SlotChange(personId: person, deviceId: me, data: result.slot.bytes),
        );
        published.add(person);
        if (adding) {
          room--;
          ownRoom--;
        }
      } on SlotPublishBlockedException {
        // No toca ahora (falta clave, slot propio ilegible...): no se publica.
      }
    }

    // B6 (revisión final): un buzón propio que esta vuelta no ha resuelto
    // (persona congelada, sin clave de sellado, sin derecho o inexistente)
    // espera como los demás y no se vuelve a bajar en cada vuelta. Los de
    // personas que solo se aplazan por el tope del `PUT` se miran en la
    // siguiente.
    for (final entry in inboxes.entries) {
      if (deferred.contains(entry.key)) continue;
      for (final slot in entry.value) {
        final key = '${slot.header.personId}/${slot.header.writer}';
        if (!webDone.containsKey(key) && !webWait.containsKey(key)) {
          webWait[key] = [slotVersions[key]!, nowMillis];
        }
      }
    }

    // Los slots ajenos no se destruyen nunca en el servidor (ADR 0005, 7;
    // B2): «no cuenta para abrir o autenticar» (lo decide `openScope` con
    // la vista, y `pruned` solo lo quita de la copia local) no quiere decir
    // «se puede borrar». Solo se cambian los propios, y siempre con datos.
    // Los abandonados siguen ocupando sitio: la presión sale por
    // `renewSuggested`.
    await local.saveSlots(localSlots);

    // 8. Credenciales que el registro no respalda (para la fase 3).
    final unbacked = [
      for (final d in snap.devices)
        if (!d.revoked && !backed.contains(d.deviceId)) d.deviceId,
    ]..sort();
    final departed = [
      for (final d in snap.devices)
        if (d.revoked && d.deviceId != me && view.member(d.deviceId) != null)
          d.deviceId,
    ]..sort();

    // 9. ¿Hay algo que subir?
    final registryChanged =
        state.revocationOperations.isNotEmpty ||
        jsonEncode(registry.toJson()) != jsonEncode(remoteRegistry.toJson());
    // Con la clave común por época, los paquetes v4 van aparte (el común y
    // su reparto los decide el ciclo común) y aquí solo los v3.
    final serverV3 = v2
        ? [
            for (final p in snap.keyPackages)
              if (!FamilyKeyBundle.isV4(p)) p,
          ]
        : snap.keyPackages;
    var packages = _packagesToUpload(serverV3, state.keyPackageOutbox, view);
    final requiredHistory = {
      for (final p in [...serverV3, ...state.keyPackageOutbox])
        if ((p['from'] != me || _packageAllowed(p, view)) &&
            localSlots.all.any(
              (slot) =>
                  p['s'] == KeyScope.surprise(slot.header.personId) &&
                  p['e'] == slot.header.epoch &&
                  view.entitled(slot.header.writer, slot.header.personId) !=
                      null &&
                  p['to'] is String &&
                  p['from'] is String &&
                  view.entitled(p['to'] as String, slot.header.personId) !=
                      null &&
                  view.entitled(p['from'] as String, slot.header.personId) !=
                      null,
            ))
          jsonEncode(p),
    };
    var packagesChanged =
        packages.length != serverV3.length || state.keyPackageOutbox.isNotEmpty;
    // 8 y 9 de la sección 4: candidata, reparto e intención guardados antes
    // de sellar. El reparto de la clave común va primero y nunca se recorta
    // (A1 de la revisión de seguridad): detrás, los v3 (los más nuevos) y los v4 ajenos de otras
    // candidatas, mientras quepan en número y en bytes. Solo si el reparto
    // no cabe ni solo, no se sustituye el común (contrapresión) y se pide
    // renovar.
    CommonPlan? plan;
    var familyPackages = const <Map<String, Object?>>[];
    var commonPackagesFull = false;
    if (cycle != null) {
      plan = await cycle.prepare(
        received!,
        serverCommon: snap.common,
        serverPackages: snap.keyPackages,
        common: outgoing,
        view: view,
        registry: registry,
      );
      if (!familyPackagesFit(plan.mandatory)) {
        plan = plan.held();
        commonPackagesFull = true;
      }
      final (v3, v4) = budgetPackages(
        plan.mandatory,
        packages,
        plan.optional,
        preferred: plan.preferred,
      );
      packages = v3;
      familyPackages = v4;
      packages = trimOwnPackages(packages, familyPackages, me: me);
      String set(Iterable<Map<String, Object?>> l) =>
          (l.map(jsonEncode).toList()..sort()).join('\n');
      packagesChanged =
          state.keyPackageOutbox.isNotEmpty ||
          set([...packages, ...familyPackages]) != set(snap.keyPackages);
    } else {
      // El tope por escritor del Worker vale también sin la clave común.
      final trimmed = trimOwnPackages(packages, const [], me: me);
      if (trimmed.length != packages.length) packagesChanged = true;
      packages = trimmed;
    }
    // Historical keys referenced by live slots cannot be silently evicted to
    // meet package limits: keep the old snapshot and request renewal instead.
    if (!packages.map(jsonEncode).toSet().containsAll(requiredHistory)) {
      throw const V2GenerationFullException();
    }
    // Los slots abandonados ya no se podan (B2): también piden renovar. Un
    // servidor anterior no cuenta los slots en `capacity`; el manifiesto sí
    // (con su aviso, el de 64 slots, o el que diga `capacity`).
    final renew =
        (snap.capacity?.renew ?? false) ||
        snap.slots.length >=
            (snap.capacity?.slots?.warn ?? kV2LegacyWarnSlots) ||
        slotsFull ||
        commonPackagesFull;
    final retainedCommons = cycle == null
        ? 0
        : (await local.readRetainedCommons()).length;
    final commonBlocked =
        received != null &&
        commonWaits(received.status) &&
        !(plan?.replaced ?? false);
    state = state.copyWith(
      created: true,
      version: snap.version,
      slotVersions: slotVersions,
      ignoredSlots: ignored,
      deferred: {...deferred, ...collectedPeople},
      webInboxDone: {
        for (final ref in snap.slots)
          if (webDone[ref.key] == ref.version) ref.key: ref.version,
      },
      // B1: la última recogida se conserva mientras la web siga en el
      // registro (activa o pendiente), aunque hoy no sea propia.
      webInboxFloors: {
        for (final e in state.webInboxFloors.entries)
          if (view.device(e.key.substring(e.key.indexOf('/') + 1))?.kind ==
              DeviceKind.web)
            e.key: e.value,
      },
      webInboxRejected: {
        for (final e in state.webInboxRejected.entries)
          if (view.device(e.key.substring(e.key.indexOf('/') + 1))?.kind ==
              DeviceKind.web)
            e.key: e.value,
      },
      webPlanInboxSeen: {
        for (final e in state.webPlanInboxSeen.entries)
          if (view.device(e.key.substring(e.key.indexOf('/') + 1))?.kind ==
              DeviceKind.web)
            e.key: e.value,
      },
      webInboxWait: {
        for (final ref in snap.slots)
          if (webWait[ref.key] case final w? when w[0] == ref.version)
            ref.key: w,
      },
      health: V2Health(
        unbackedCredentials: unbacked,
        departedDevices: departed,
        renewSuggested: renew,
        writerSlotsFull: writerSlotsFull,
        commonBlocked: commonBlocked,
        commonBlockedWriter: commonBlocked ? received.block?.writer : null,
        commonPackagesFull: commonPackagesFull,
        commonKeyringFull: plan?.keyringFull ?? false,
        retainedCommons: retainedCommons,
      ),
    );
    // Guardar incluso si el PUT falla: la instantánea ya se verificó y los
    // avisos del servicio no se pueden reconstruir sin conexión.
    await local.saveState(state);
    if (!(plan == null ? commonChanged : plan.resealed) &&
        !registryChanged &&
        !packagesChanged &&
        changes.isEmpty) {
      return V2SyncOutcome(
        version: snap.version,
        view: view,
        hasOtherActiveCredential: snap.devices.any(
          (d) => !d.revoked && d.deviceId != me,
        ),
        uploaded: false,
        unbackedCredentials: unbacked,
        departedDevices: departed,
        frozenPeople: frozen,
        publishedPeople: published,
        rejectedSlots: rejected,
        renewSuggested: renew,
        slotsFull: slotsFull,
        writerSlotsFull: writerSlotsFull,
        morePending: deferred.isNotEmpty,
        commonStatus: received?.status,
        commonKid: received?.kid,
        commonPackagesFull: commonPackagesFull,
        commonCutover: cutover,
        published: V2Published(
          common: snap.common,
          registry: snap.registry,
          keyPackages: snap.keyPackages,
        ),
      );
    }
    // B4: el mínimo del Worker sube con el primer común en formato 2 que
    // sube quien activa el corte (o quien ya tiene la marca y ve un servidor
    // atrasado), si su credencial anunció el formato.
    final raise =
        plan != null &&
        isFamilyEnvelope(plan.common) &&
        snap.minCommonFormat < kCommonFormatLatest &&
        (myCredential?.commonFormat ?? 1) >= kCommonFormatLatest &&
        (cutover == CommonCutover.activating || floor >= kCommonFormatLatest);
    if (raise &&
        cutover == CommonCutover.activating &&
        !state.commonMigrationPut) {
      // Antes del `PUT` del corte: desde aquí, nunca el formato 1.
      state = state.copyWith(commonMigrationPut: true);
      await local.saveState(state);
    }
    final upload = V2SnapshotUpload(
      common: plan?.common ?? await _seal(outgoing),
      registry: registry.toJson(),
      keyPackages: [...packages, ...familyPackages],
      slots: changes,
      minCommonFormat: raise ? kCommonFormatLatest : null,
    );
    final put = await transport.putList(
      auth,
      version: snap.version,
      body: upload,
    );
    switch (put) {
      case V2WriteOk():
        if (plan != null) await cycle!.accepted(plan, familyPackages);
        final versions = {...slotVersions};
        for (final c in changes) {
          final key = '${c.personId}/${c.deviceId}';
          if (c.data == null) {
            versions.remove(key);
          } else {
            versions[key] = put.version;
          }
        }
        final remainingPackages = state.keyPackageOutbox
            .where(
              (p) =>
                  _packageAllowed(p, view) &&
                  !packages.any((sent) => jsonEncode(sent) == jsonEncode(p)),
            )
            .toList();
        await local.saveState(
          state.copyWith(
            version: put.version,
            slotVersions: versions,
            keyPackageOutbox: remainingPackages,
            revocationOperations: const {},
            // El slot con lo recogido ya entró (B5).
            deferred: deferred,
          ),
        );
        // La marca irreversible, al terminar: un cierre antes deja el
        // servidor en el mínimo 2 y la vuelta siguiente sigue el corte.
        if (raise && cutover == CommonCutover.activating) {
          await CommonV2Bootstrap.finish(local);
          cutover = CommonCutover.activated;
        }
        return V2SyncOutcome(
          version: put.version,
          view: view,
          hasOtherActiveCredential: snap.devices.any(
            (d) => !d.revoked && d.deviceId != me,
          ),
          uploaded: true,
          unbackedCredentials: unbacked,
          departedDevices: departed,
          frozenPeople: frozen,
          publishedPeople: published,
          rejectedSlots: rejected,
          renewSuggested: renew,
          slotsFull: slotsFull,
          writerSlotsFull: writerSlotsFull,
          morePending: deferred.isNotEmpty || remainingPackages.isNotEmpty,
          commonStatus: received?.status,
          commonKid: plan == null ? null : plan.uploadedKid ?? received?.kid,
          commonReplaced: plan?.replaced ?? false,
          commonPackagesFull: commonPackagesFull,
          commonCutover: cutover,
          published: V2Published(
            common: upload.common,
            registry: upload.registry,
            keyPackages: upload.keyPackages,
          ),
        );
      case V2WriteStale():
        // Lo fusionado ya está guardado; la siguiente vuelta lo vuelve a subir
        // sobre la instantánea nueva.
        await local.saveState(state);
        throw const _Restart();
      case V2WriteNotFound():
        throw const V2ListGoneException();
    }
  }

  Future<void> _openPackages(
    List<Map<String, Object?>> packages,
    RegistryView view,
  ) async {
    final me = view.me;
    final keys = <SurpriseKey>[];
    for (final raw in packages) {
      if (raw['to'] != me) continue;
      final KeyBundle bundle;
      try {
        bundle = KeyBundle.fromJson(raw);
      } on KeyBundleException {
        continue;
      }
      if (KeyScope.personOf(bundle.scope) == null) {
        // La rotación de la clave de la familia está pendiente (fase 2b,
        // segunda parte): un paquete de la familia aún no se aplica.
        continue;
      }
      try {
        keys.add(await bundle.openSurpriseKey(mine: local.keys, view: view));
      } on KeyBundleException {
        continue;
      }
    }
    if (keys.isEmpty) return;
    await local.updateKeyring((current) {
      var next = current;
      for (final key in keys) {
        if (view.myPerson == key.personId) continue;
        try {
          next = next.withKey(
            key,
            registryEpoch: view.epoch,
            allowed: view.entitledDevices(key.personId),
          );
        } on KeyringConflictException {
          continue;
        }
      }
      return next;
    });
  }

  /// Conserva los paquetes ajenos del servidor: la falta de derecho de un
  /// intermediario no autoriza borrarlos. Solo revalida los emitidos por
  /// este móvil, incluidos los ya publicados. Sin repetidos, hasta 512.
  List<Map<String, Object?>> _packagesToUpload(
    List<Map<String, Object?>> server,
    List<Map<String, Object?>> fresh,
    RegistryView view,
  ) {
    final seen = <String>{};
    final out = <Map<String, Object?>>[];
    for (final p in server) {
      if (p['from'] == view.me && !_packageAllowed(p, view)) continue;
      if (seen.add(jsonEncode(p))) out.add(p);
    }
    for (final p in fresh) {
      if (_packageAllowed(p, view) && seen.add(jsonEncode(p))) out.add(p);
    }
    return out.length > 512 ? out.sublist(out.length - 512) : out;
  }

  /// Recoge en [scope] los [inboxes] de las webs propias para [person]
  /// (1.0.6, ADR 0009, A.8.4). Devuelve el ámbito (el mismo si no cambia),
  /// el estado con las últimas recogidas y el contador de lápidas, y los
  /// buzones resueltos (no se vuelven a bajar mientras no cambien), los que
  /// esperan y si se recogió alguno (entonces hay que publicar).
  Future<
    ({
      FamilyDoc scope,
      V2SyncState state,
      Map<String, int> done,
      Set<String> waiting,
      bool collected,
    })
  >
  _collectWebInboxes({
    required String person,
    required FamilyDoc scope,
    required OpenedScope opened,
    required List<SealedSlot> inboxes,
    required Set<String> ownWebIds,
    required RegistryView view,
    required SurpriseKeyring keyring,
    required V2SyncState state,
    required Map<String, int> slotVersions,
    required int nowMillis,
    FamilyDoc? common,
  }) async {
    final floors = {...state.webInboxFloors};
    final rejectedInboxes = {...state.webInboxRejected};
    final planInboxSeen = {...state.webPlanInboxSeen};
    // Los planes de deseos solo entran si todos los demás móviles que leen
    // este ámbito los anuncian (un 1.0.6 rechazaría el bloque entero).
    final plansAllowed = wishPlansAllowed([
      for (final device in view.entitledDevices(person))
        if (device != view.me) opened.parts[device],
    ]);
    // Recogida transitiva: lo que otro móvil de la misma persona ya declara
    // haber recogido (`s[web]`) ya viene en su slot.
    // También el slot propio (B1): si este móvil perdió su estado, lo que ya
    // declaró sigue valiendo.
    for (final part in opened.parts.entries) {
      if (view.member(part.key)?.personId != view.myPerson) continue;
      for (final web in ownWebIds) {
        final seen = part.value.seen[web];
        final key = '$person/$web';
        if (seen == null) continue;
        final floor = floors[key];
        final planAware =
            part.value.wishPlans >= kWishPlanCapability &&
            part.value.planInboxSeen[web] == seen;
        if (floor != null &&
            seen.compareTo(floor) <= 0 &&
            !(seen == floor && planAware && planInboxSeen[key] != seen)) {
          continue;
        }
        floors[key] = seen;
        // Keep the outcome and plan support of the same declaration.
        if (planAware) {
          planInboxSeen[key] = seen;
        } else {
          planInboxSeen.remove(key);
        }
        if (part.value.rejectedInboxes[web] == seen) {
          rejectedInboxes[key] = seen;
        } else {
          rejectedInboxes.remove(key);
        }
      }
    }
    final done = <String, int>{};
    final waiting = <String>{};
    var collected = false;
    final day = nowMillis ~/ Duration.millisecondsPerDay;
    var count = state.webTombstoneDay == day ? state.webTombstoneCount : 0;
    var next = scope;
    for (final inbox in inboxes) {
      final h = inbox.header;
      final key = '$person/${h.writer}';
      final floor = floors[key];
      final web = view.member(h.writer);
      if (web == null || web.kind != DeviceKind.web) continue;
      if (floor != null &&
          (h.version.compareTo(floor) < 0 ||
              (h.version == floor && planInboxSeen[key] == floor))) {
        done[key] = slotVersions[key]!;
        continue;
      }
      // Del futuro (época que el registro no ha abierto o revisión
      // adelantada), o con algún escritor ilegible (no se sabe si el regalo
      // existe, B4): espera.
      if (h.epoch > view.epoch ||
          h.revision > nowMillis + kMaxSlotClockSkew.inMilliseconds ||
          opened.unreadableWriters.isNotEmpty) {
        waiting.add(key);
        continue;
      }
      if (!await inbox.verifySignature(web.signingKey)) {
        done[key] = slotVersions[key]!;
        continue;
      }
      final key2 = keyring.keyFor(person, h.epoch, h.kid);
      // Sin la clave con que se selló, espera a que llegue.
      if (key2 == null) {
        waiting.add(key);
        continue;
      }
      final OpenedSlot content;
      try {
        content = await inbox.open(
          expectedListId: view.listId,
          key: key2,
          signingKey: web.signingKey,
        );
      } on ProtectedEnvelopeException {
        done[key] = slotVersions[key]!;
        continue;
      }
      if (h.version == floor && content.planRecords == 0) {
        done[key] = slotVersions[key]!;
        continue;
      }
      final result = absorbWebInbox(
        scope: next,
        inbox: content,
        nowMillis: nowMillis,
        tombstoneBudget: kMaxWebTombstonesPerDay - count,
        webPersonId: web.personId,
        common: common,
        plansAllowed: plansAllowed,
      );
      if (result.waiting) {
        waiting.add(key);
        continue;
      }
      floors[key] = h.version;
      if (content.planRecords > 0) {
        planInboxSeen[key] = h.version;
      } else {
        planInboxSeen.remove(key);
      }
      done[key] = slotVersions[key]!;
      // Rechazado o recogido: hay que declarar `s[web]` para que la web lo
      // deje de reenviar.
      collected = true;
      if (result.rejected != null) {
        // La web tiene que saber que no se recogió: el slot lo declara.
        rejectedInboxes[key] = h.version;
        continue;
      }
      rejectedInboxes.remove(key);
      next = result.scope;
      count += result.tombstones;
    }
    final changedFloors =
        floors.length != state.webInboxFloors.length ||
        floors.entries.any((e) => state.webInboxFloors[e.key] != e.value) ||
        rejectedInboxes.length != state.webInboxRejected.length ||
        rejectedInboxes.entries.any(
          (e) => state.webInboxRejected[e.key] != e.value,
        ) ||
        planInboxSeen.length != state.webPlanInboxSeen.length ||
        planInboxSeen.entries.any(
          (e) => state.webPlanInboxSeen[e.key] != e.value,
        );
    final changedCount =
        count != (state.webTombstoneDay == day ? state.webTombstoneCount : 0);
    return (
      scope: next,
      state: changedFloors || changedCount
          ? state.copyWith(
              webInboxFloors: floors,
              webInboxRejected: rejectedInboxes,
              webPlanInboxSeen: planInboxSeen,
              webTombstoneDay: day,
              webTombstoneCount: count,
            )
          : state,
      done: done,
      waiting: waiting,
      collected: collected,
    );
  }

  bool _packageAllowed(Map<String, Object?> raw, RegistryView view) {
    try {
      final p = KeyBundle.fromJson(raw);
      final person = KeyScope.personOf(p.scope);
      if (p.fromDevice != view.me ||
          p.listId != view.listId ||
          person == null ||
          p.epoch > view.epoch) {
        return false;
      }
      if (!view.selfEntitled(person)) return false;
      // 1.0.6 (ADR 0009): la clave para una web propia vale mientras la web
      // siga siendo propia con la misma ficha, sea de otra persona y la
      // época no haya cambiado (después recibe las nuevas).
      for (final web in view.ownWebs()) {
        if (web.deviceId != p.toDevice) continue;
        return person != web.personId &&
            p.epoch == view.epoch &&
            web.recordDigest == p.recipientRecord &&
            view.self.recordDigest == p.senderRecord &&
            p.audience.every(
              (id) => id == web.deviceId || view.entitled(id, person) != null,
            );
      }
      final sender = view.entitled(p.fromDevice, person);
      final recipient = view.entitled(p.toDevice, person);
      return sender != null &&
          recipient != null &&
          sender.recordDigest == p.senderRecord &&
          recipient.recordDigest == p.recipientRecord &&
          (p.epoch < view.epoch ||
              p.audience.every((id) => view.entitled(id, person) != null));
    } on KeyBundleException {
      return false;
    }
  }
}
