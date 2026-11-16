// Cliente de la API v2 del Worker (server/README.md, «API v2»; ADR 0004,
// «Contrato final del Worker v2»). Credencial por móvil (`Authorization:
// Bearer <credencial de servicio>`), versión de la lista como ETag fuerte
// (`If-Match` / `If-None-Match`), slots como recursos aparte, revocación,
// invitaciones de emparejamiento v2 y WebSocket `gift-huddle.v2`.
//
// El cliente no confía en lo que contesta el servidor: comprueba la forma, que
// la versión del cuerpo y la del ETag coinciden y que un slot es del recurso
// que se pidió. Lo demás (firmas, registro, épocas) lo decide el móvil.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../../core/sync/device_keys.dart' show kSyncIdPattern;
import '../../../core/sync/envelope.dart' show decodeBase64Url, encodeBase64Url;
import '../../../core/sync/renewal_protocol.dart';
import 'sync_transport.dart';
import 'sync_transport_common.dart';

/// Subprotocolo del WebSocket v2.
const String kWsProtocolV2 = 'gift-huddle.v2';

/// Código de cierre del WebSocket cuando revocan esta credencial.
const int kWsClosedRevoked = 4401;

/// Código de cierre del WebSocket cuando la lista se ha borrado.
const int kWsClosedGone = 4404;

/// Slots propios que lleva como mucho un `PUT` (`V2_MAX_SLOTS_PER_PUT` del
/// Worker): con todo lo demás en su tope cabe en los 5 MiB que lee el Worker.
/// Los que no caben salen en la vuelta siguiente.
const int kV2MaxSlotsPerPut = 10;

/// Slots guardados en la lista desde los que conviene renovar
/// (`V2_WARN_SLOTS` del Worker). Nadie borra los slots de otro (B2): los
/// abandonados solo se van con la renovación.
const int kV2WarnSlots = 48;

/// Slots que puede tener un escritor (`V2_MAX_SLOTS_PER_WRITER` del Worker):
/// una sola credencial no llena el tope de la lista.
const int kV2MaxSlotsPerWriter = 32;

/// A web QR is created before the mobile publishes its offer.
class V2OfferNotYetException implements Exception {
  const V2OfferNotYetException();
}

/// The service rejected a web/person/role binding. Never retry unchanged.
class V2PairingMismatchException implements Exception {
  const V2PairingMismatchException(this.code);
  final String code;
}

/// Recoverable renewal conflict, including a frozen source or a plan invalidated
/// by revocation. The caller keeps its journal and reads the control again.
class V2RenewalConflictException implements Exception {
  const V2RenewalConflictException(this.code);
  final String code;
}

/// Control cannot be read. A retired source must never be recreated.
class V2RenewalGoneException implements Exception {
  const V2RenewalGoneException({required this.retired});
  final bool retired;
}

/// Service shape only: signatures and local trust still require verification.
class V2RenewalSnapshot {
  const V2RenewalSnapshot({required this.version, required this.renewal});
  final int version;

  /// Null means the live source has no reservation yet (HTTP 200).
  final Map<String, Object?>? renewal;
}

final RegExp _id16 = RegExp(r'^[A-Za-z0-9_-]{22}$');

/// Con qué se presenta este móvil ante la lista v2.
class V2Auth {
  /// Crea las credenciales. Lanza [ArgumentError] si algo no vale.
  V2Auth({
    required this.syncId,
    required this.deviceId,
    required Uint8List credential,
  }) : credential = Uint8List.fromList(credential) {
    if (!_id16.hasMatch(syncId) ||
        !kSyncIdPattern.hasMatch(deviceId) ||
        credential.length != 32) {
      throw ArgumentError('credenciales v2 no válidas');
    }
  }

  /// La lista en el servidor (16 bytes aleatorios en base64url).
  final String syncId;

  /// Este móvil.
  final String deviceId;

  /// Credencial de servicio (32 bytes, `DeviceKeys.serviceCredential`).
  final Uint8List credential;

  /// `Bearer <credencial>`.
  String get bearer => 'Bearer ${encodeBase64Url(credential)}';

  @override
  String toString() => 'V2Auth($syncId, $deviceId, …)';
}

// ------------------------------------------------------------- instantánea

/// Una entrada del manifiesto de slots: `version` es la versión de la lista
/// que escribió ese slot por última vez.
class V2SlotRef {
  /// Crea la entrada.
  const V2SlotRef({
    required this.personId,
    required this.deviceId,
    required this.version,
  });

  /// Persona protegida.
  final String personId;

  /// Escritor.
  final String deviceId;

  /// Versión de la lista que lo escribió.
  final int version;

  /// Clave `persona/móvil`.
  String get key => '$personId/$deviceId';
}

/// Una credencial que el servidor conoce.
class V2Device {
  /// Crea la entrada.
  const V2Device({
    required this.deviceId,
    required this.revoked,
    this.approvedBy,
    this.role = 'device',
    this.commonFormat = 1,
  });

  /// Móvil.
  final String deviceId;

  /// Si está revocada.
  final bool revoked;

  /// Credencial que aprobó la invitación; ausente en listas anteriores y
  /// en el móvil creador. Es información del servidor, no un aval firmado.
  final String? approvedBy;

  /// Immutable service role; old rows are mobile devices.
  final String role;

  /// El formato del común más nuevo que esta credencial ha anunciado que lee
  /// y escribe (`POST S/capability`, ADR 0005, B4); 1 si no ha anunciado
  /// nada. Es dato del servicio, no confianza firmada.
  final int commonFormat;
}

/// `GET /v2/lists/{syncId}`: la instantánea, sin el contenido de los slots.
class V2Snapshot {
  /// Crea la instantánea.
  const V2Snapshot({
    required this.version,
    required this.common,
    required this.registry,
    required this.keyPackages,
    required this.slots,
    required this.devices,
    this.capacity,
    this.minCommonFormat = 1,
  });

  /// Versión de la lista.
  final int version;

  /// Sobre común (bytes, ADR 0001).
  final Uint8List common;

  /// `DeviceRegistry.toJson()` tal como llega (sin verificar).
  final Object? registry;

  /// Paquetes de claves tal como llegan (sin verificar).
  final List<Map<String, Object?>> keyPackages;

  /// Manifiesto de slots.
  final List<V2SlotRef> slots;

  /// Credenciales que acepta el servidor (y las revocadas).
  final List<V2Device> devices;

  /// Lo llena que está esta generación (`capacity`), o null si el servidor
  /// no lo dice.
  final V2Capacity? capacity;

  /// El formato mínimo del común que acepta esta generación (ADR 0005, B4);
  /// 1 si el servidor no lo dice.
  final int minCommonFormat;
}

/// Un contador de [V2Capacity]: lo usado, el aviso y el tope.
class V2CapacityCount {
  /// Crea el contador.
  const V2CapacityCount({
    required this.used,
    required this.warn,
    required this.max,
  });

  /// Lo usado.
  final int used;

  /// Desde aquí se propone renovar.
  final int warn;

  /// El tope: al llegar, `409 generation_full`.
  final int max;
}

/// `capacity` del `GET`: credenciales y fichas de esta generación (un
/// `syncId`) y si conviene renovar (ADR 0004, «Cupos, generaciones y
/// renovación»).
class V2Capacity {
  /// Crea la capacidad.
  const V2Capacity({
    required this.credentials,
    required this.records,
    required this.renew,
    this.slots,
  });

  /// Credenciales dadas de alta (revocadas incluidas).
  final V2CapacityCount credentials;

  /// Declaraciones de ficha que ha visto la generación.
  final V2CapacityCount records;

  /// Stored slots, when supplied by the Worker (older responses omit it).
  final V2CapacityCount? slots;

  /// Si se ha cruzado algún aviso.
  final bool renew;
}

/// `409 common_format_too_old`, `common_format_unannounced` o
/// `400 common_format_unknown` (ADR 0005, B4): el común que se sube no es del
/// formato que pide la generación. Para un cliente antiguo quiere decir que
/// hay que actualizar la app.
class V2CommonFormatException implements Exception {
  /// Crea el error.
  const V2CommonFormatException(this.code);

  /// El código del servidor.
  final String code;

  @override
  String toString() => 'V2CommonFormatException($code)';
}

/// `409 generation_full`: esta generación ha llegado a su tope de
/// credenciales o de fichas. Es para siempre en ese `syncId`: hay que
/// renovar (fase 3).
class V2GenerationFullException implements Exception {
  /// Crea el error.
  const V2GenerationFullException();

  @override
  String toString() => 'V2GenerationFullException';
}

/// Lo que se sube en un `PUT`: el común, el registro y los paquetes se
/// reemplazan; los slots son una delta (`data` null lo borra).
class V2SnapshotUpload {
  /// Crea la subida.
  const V2SnapshotUpload({
    required this.common,
    required this.registry,
    required this.keyPackages,
    this.slots = const <V2SlotChange>[],
    this.minCommonFormat,
    this.inviteCopy = false,
  });

  /// Sobre común.
  final Uint8List common;

  /// `DeviceRegistry.toJson()`.
  final Map<String, Object?> registry;

  /// `KeyBundle.toJson()` de cada paquete.
  final List<Map<String, Object?>> keyPackages;

  /// Delta de slots.
  final List<V2SlotChange> slots;

  /// Con valor, sube el formato mínimo del común de la generación en este
  /// mismo `PUT` (ADR 0005, B4): [common] tiene que ser de ese formato.
  final int? minCommonFormat;

  /// Creation only: expire an invitation-only server copy after 24 hours,
  /// unless another device is approved or a recovery capsule is published.
  final bool inviteCopy;

  Map<String, Object?> _json({String? deviceId}) => <String, Object?>{
    'deviceId': ?deviceId,
    'common': encodeBase64Url(common),
    'registry': registry,
    'keyPackages': keyPackages,
    'slots': [for (final s in slots) s.toJson()],
    'minCommonFormat': ?minCommonFormat,
    if (deviceId != null && inviteCopy) 'inviteCopy': true,
  };
}

/// Un cambio de slot en un `PUT`.
class V2SlotChange {
  /// Crea el cambio. [data] null borra el slot.
  const V2SlotChange({
    required this.personId,
    required this.deviceId,
    required this.data,
  });

  /// Persona protegida.
  final String personId;

  /// Escritor.
  final String deviceId;

  /// Bytes del slot sellado, o null para borrarlo.
  final Uint8List? data;

  /// En JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'personId': personId,
    'deviceId': deviceId,
    'data': data == null ? null : encodeBase64Url(data!),
  };
}

/// Respuesta a `GET /v2/lists/{syncId}`.
sealed class V2GetResult {
  const V2GetResult();
}

/// `200`.
final class V2GetOk extends V2GetResult {
  /// Crea el resultado.
  const V2GetOk(this.snapshot);

  /// La instantánea.
  final V2Snapshot snapshot;
}

/// `304`.
final class V2GetNotModified extends V2GetResult {
  /// Crea el resultado.
  const V2GetNotModified();
}

/// `404`: no existe o se borró (un `syncId` borrado no se puede recrear).
final class V2GetNotFound extends V2GetResult {
  /// Crea el resultado.
  const V2GetNotFound();
}

/// Respuesta a una escritura condicional (`PUT`, `DELETE`, aprobar).
sealed class V2WriteResult {
  const V2WriteResult();
}

/// Hecha: [version] es la nueva versión (en `DELETE`, la que había).
final class V2WriteOk extends V2WriteResult {
  /// Crea el resultado.
  const V2WriteOk(this.version);

  /// Versión nueva.
  final int version;
}

/// `412`: la lista está en otra versión ([current], si la dijo).
final class V2WriteStale extends V2WriteResult {
  /// Crea el resultado.
  const V2WriteStale(this.current);

  /// Versión actual según el `ETag` de la respuesta.
  final int? current;
}

/// `404`: la lista no existe o se borró; también `410 retired` al crear un
/// `syncId` retirado (borrado o caducado), que no vuelve nunca.
final class V2WriteNotFound extends V2WriteResult {
  /// Crea el resultado.
  const V2WriteNotFound();
}

/// Respuesta a `GET …/slots/{persona}/{móvil}`.
sealed class V2SlotResult {
  const V2SlotResult();
}

/// `200`.
final class V2SlotOk extends V2SlotResult {
  /// Crea el resultado.
  const V2SlotOk({
    required this.version,
    required this.slotVersion,
    required this.data,
  });

  /// Versión de la lista (la de `If-Match`).
  final int version;

  /// Versión que escribió el slot.
  final int slotVersion;

  /// Bytes del slot sellado (sin verificar).
  final Uint8List data;
}

/// `412`: la instantánea ha cambiado; hay que empezar otra vez.
final class V2SlotStale extends V2SlotResult {
  /// Crea el resultado.
  const V2SlotStale();
}

/// `404`: ese slot no existe en esta versión.
final class V2SlotMissing extends V2SlotResult {
  /// Crea el resultado.
  const V2SlotMissing();
}

// ------------------------------------------------------------ invitaciones

/// Estado de una invitación v2 visto por su dueño (`GET I`).
class V2InviteState {
  /// Crea el estado.
  const V2InviteState({
    required this.offer,
    required this.answer,
    required this.revealed,
    required this.approved,
    required this.expiresAt,
    this.canApprove = true,
  });

  /// Si una aprobación cabría ahora (cupo diario, checkpoints vivos y
  /// generación; B7). Orientativo: aprobar lo vuelve a comprobar. Un Worker
  /// que no lo dice cuenta como que sí.
  final bool canApprove;

  /// `PairingOffer.toJson()` publicado.
  final Object? offer;

  /// `PairingAnswer.toJson()` del invitado, o null.
  final Object? answer;

  /// Si ya se reveló el nonce.
  final bool revealed;

  /// Si ya se aprobó.
  final bool approved;

  /// Cuándo caduca.
  final DateTime expiresAt;
}

/// `GET J/offer`.
class V2InviteOffer {
  /// Crea la oferta.
  const V2InviteOffer({
    required this.offer,
    required this.expiresAt,
    this.guestPerson,
  });

  /// Person selected by the mobile before offering access to a web.
  final String? guestPerson;

  /// `PairingOffer.toJson()` (sin verificar).
  final Object? offer;

  /// Cuándo caduca.
  final DateTime expiresAt;
}

/// Respuesta a `GET J/result`.
sealed class V2InviteOutcome {
  const V2InviteOutcome();
}

/// `202`: sin aprobar. [reveal] es la revelación del anfitrión, si ya la hay.
final class V2InvitePending extends V2InviteOutcome {
  /// Crea el resultado.
  const V2InvitePending(this.reveal);

  /// `PairingReveal.toJson()`, o null.
  final Object? reveal;
}

/// `200`: aprobada.
final class V2InviteApproved extends V2InviteOutcome {
  /// Crea el resultado.
  const V2InviteApproved({
    required this.reveal,
    required this.package,
    required this.minVersion,
    required this.syncId,
  });

  /// `PairingReveal.toJson()`.
  final Object? reveal;

  /// Paquete cifrado del anfitrión (opaco para el servidor).
  final Map<String, Object?> package;

  /// La versión que creó la aprobación: hay que leer una instantánea al
  /// menos así de nueva.
  final int minVersion;

  /// La lista.
  final String syncId;
}

/// `GET J/checkpoint` (ADR 0005, B7): el común y el registro exactos que
/// aprobó el anfitrión, tal como los guardó el Worker. Sin autenticar: el
/// invitado comprueba sus hashes con la aprobación firmada.
class V2InviteCheckpoint {
  /// Crea el checkpoint.
  const V2InviteCheckpoint({required this.common, required this.registry});

  /// El texto base64url del común.
  final String common;

  /// El registro en JSON canónico (texto).
  final String registry;
}

/// Los dos hashes del checkpoint que el anfitrión manda al aprobar (B7).
class V2CheckpointClaim {
  /// Crea la petición.
  const V2CheckpointClaim({required this.common, required this.registry});

  /// `pairingCheckpointHash('common', ...)`.
  final String common;

  /// `pairingCheckpointHash('registry', ...)`.
  final String registry;
}

/// `404` en `result`: credencial equivocada, caducada, cancelada o dueño
/// revocado.
final class V2InviteGone extends V2InviteOutcome {
  /// Crea el resultado.
  const V2InviteGone();
}

/// `409` de una invitación v2, con su código (`invalid_state`,
/// `credential_exists`, `too_many_devices`, `already_answered`).
class V2InviteConflictException implements Exception {
  /// Crea el error.
  const V2InviteConflictException(this.code);

  /// Código del servidor.
  final String code;

  @override
  String toString() => 'V2InviteConflictException($code)';
}

/// `403`: la credencial no puede hacer eso (un slot de otro móvil, o una
/// invitación de otro dueño).
class V2ForbiddenException implements Exception {
  /// Crea el error.
  const V2ForbiddenException(this.code);

  /// Código del servidor.
  final String code;

  @override
  String toString() => 'V2ForbiddenException($code)';
}

/// `412` de un `POST S/revoke` condicional: la lista ya no está en la
/// versión que se vio, así que no se ha revocado nada. Hay que volver a
/// leer, verificar y decidir (B2).
class V2RevokeStaleException implements Exception {
  /// Crea el error.
  const V2RevokeStaleException();

  @override
  String toString() => 'V2RevokeStaleException';
}

// --------------------------------------------------------------- interfaz

/// Lo que la app necesita de la API v2.
abstract interface class SyncV2Transport {
  /// Reads durable control without spending declaration/registration capacity.
  /// Throws [V2RenewalGoneException] on 404/410; never resets local state.
  Future<V2RenewalSnapshot> getRenewal(V2Auth auth);

  /// Pinned public log page; verify/replay the complete signed log before use.
  Future<RenewalLogPage> getRenewalLogPage(
    V2Auth auth, {
    required String operationId,
    required String head,
    required int after,
  });

  /// Conditional signed control command (wire format in server/README.md).
  /// [command] includes sourceVersion == [version]. Retry the exact command
  /// after a lost response; an accepted duplicate is idempotent even with its
  /// original ETag. Phones verify signatures before following remote control.
  Future<V2WriteResult> putRenewal(
    V2Auth auth, {
    required int version,
    required Map<String, Object?> command,
  });

  /// Restricted conditional write: no registry, packages or slots.
  Future<V2WriteResult> putCommon(
    V2Auth auth, {
    required int version,
    required Uint8List common,
  });

  /// `PUT S` con `If-Match: "0"`: crea la lista. [V2WriteStale] si ya existe
  /// y este móvil está en ella.
  Future<V2WriteResult> createList(V2Auth auth, V2SnapshotUpload body);

  /// `GET S`, con `If-None-Match` si se da [ifNoneMatch].
  Future<V2GetResult> getList(V2Auth auth, {int? ifNoneMatch});

  /// `GET S/slots/{personId}/{deviceId}` con `If-Match: "version"`.
  Future<V2SlotResult> getSlot(
    V2Auth auth, {
    required int version,
    required String personId,
    required String deviceId,
  });

  /// `PUT S` con `If-Match: "version"`.
  Future<V2WriteResult> putList(
    V2Auth auth, {
    required int version,
    required V2SnapshotUpload body,
  });

  /// `DELETE S` con `If-Match: "version"`.
  Future<V2WriteResult> deleteList(
    V2Auth auth, {
    required int version,
    bool automaticRetirement = false,
  });

  /// `POST S/capability {commonFormat}` (ADR 0005, B4): este móvil anuncia
  /// que lee y escribe ese formato del común. Devuelve la versión (sube solo
  /// si cambia algo).
  Future<int> announceCommonFormat(V2Auth auth, int format);

  /// `POST S/revoke {deviceId}`: devuelve la versión nueva.
  ///
  /// Con [ifVersion] va con `If-Match: "ifVersion"` (revocación condicional,
  /// decidida a partir de esa instantánea) y lanza [V2RevokeStaleException]
  /// si la lista se ha movido. Sin él es incondicional (las explícitas).
  Future<int> revoke(V2Auth auth, String deviceId, {int? ifVersion});

  /// `GET S/ws` con el subprotocolo [kWsProtocolV2].
  Stream<SyncEvent> watch(V2Auth auth);

  /// `POST S/invites {offer}`.
  Future<InviteTicket> createInvite(
    V2Auth auth,
    Map<String, Object?> offer, {
    String? inviteId,
    String? guestPerson,
  });

  /// `GET I`. Lanza [InviteGoneException] si ya no existe.
  Future<V2InviteState> getInvite(V2Auth auth, String inviteId);

  /// `POST I/reveal {reveal}`.
  Future<void> revealInvite(
    V2Auth auth,
    String inviteId,
    Map<String, Object?> reveal,
  );

  /// `POST I/approve {package}` con `If-Match: "version"`. Con [checkpoint]
  /// (B7), el Worker copia el común y el registro de esa versión para el
  /// invitado si sus hashes son esos (si no, [V2InviteConflictException]
  /// `checkpoint_mismatch`).
  Future<V2WriteResult> approveInvite(
    V2Auth auth,
    String inviteId, {
    required int version,
    required Map<String, Object?> package,
    String role = 'device',
    V2CheckpointClaim? checkpoint,
  });

  /// `DELETE I`.
  Future<void> deleteInvite(V2Auth auth, String inviteId);

  /// `GET J/offer` (sin autenticación).
  Future<V2InviteOffer> getOffer(String inviteId, {bool allowNotYet = false});

  /// `POST J/answer {answer, serviceCredentialVerifier}` (sin autenticación).
  Future<void> answerInvite(
    String inviteId, {
    required Map<String, Object?> answer,
    required Uint8List verifier,
  });

  /// `GET J/result` con la credencial de este móvil.
  Future<V2InviteOutcome> pollInviteResult(
    String inviteId, {
    required Uint8List credential,
  });

  /// `GET J/checkpoint` con la credencial de este móvil (B7). Null si el
  /// servidor no lo da (todavía no, nunca o lo retiene): el emparejamiento
  /// queda pendiente.
  Future<V2InviteCheckpoint?> getInviteCheckpoint(
    String inviteId, {
    required Uint8List credential,
  });

  /// `DELETE J/checkpoint` con la credencial de este móvil: ya instaló la
  /// base y libera la copia del Worker (B7). Un `404` también vale.
  Future<void> releaseInviteCheckpoint(
    String inviteId, {
    required Uint8List credential,
  });
}

// ------------------------------------------------------------- implementación

/// Cómo se manda una petición (lo pone `BaseSyncTransport.send`).
typedef V2Send = Future<SyncResponse> Function(
  String method,
  Uri uri, {
  Object? body,
  Map<String, String> headers,
});

/// Cómo se abre un WebSocket: el flujo da [SyncOpenEvent] al conectar, los
/// mensajes y, al cerrarse, [SyncGoneEvent] o [SyncRevokedEvent] según el
/// código.
typedef V2Socket = Stream<SyncEvent> Function(Uri uri, List<String> protocols);

/// [SyncV2Transport] sobre el `send` de un transporte de la app.
class SyncV2Client implements SyncV2Transport {
  /// Crea el cliente hacia [base].
  SyncV2Client({
    required this.base,
    required this.sendRequest,
    this.openSocket,
  });

  /// Dirección base.
  final Uri base;

  /// Cómo se manda una petición.
  final V2Send sendRequest;

  /// Cómo se abre el WebSocket (null: sin WebSocket).
  final V2Socket? openSocket;

  Uri _uri(String path) => base.replace(path: path);

  static String _list(V2Auth auth) => '/v2/lists/${auth.syncId}';

  static void _checkId(String id) {
    if (!_id16.hasMatch(id)) {
      throw const SyncTransportException(SyncFailure.protocol, 'id no válido');
    }
  }

  static void _checkPathId(String id) {
    if (!kSyncIdPattern.hasMatch(id)) {
      throw const SyncTransportException(SyncFailure.protocol, 'id no válido');
    }
  }

  Map<String, String> _authed(V2Auth auth, [Map<String, String>? more]) => {
    'Authorization': auth.bearer,
    ...?more,
  };

  static String _etag(int version) => '"$version"';

  /// La versión de un `ETag` (`"N"`), o null. Acepta también la forma débil
  /// `W/"N"`: Cloudflare la pone al comprimir una respuesta grande, y la
  /// pre.19 no podía emparejar por eso. Solo se lee: lo que se envía en
  /// `If-Match` sigue siendo el fuerte de [_etag], y la versión del cuerpo
  /// tiene que casar igual.
  static int? etagVersion(String? raw) {
    if (raw == null) return null;
    final m = RegExp(r'^(?:W/)?"(0|[1-9][0-9]{0,15})"$').firstMatch(raw.trim());
    return m == null ? null : int.parse(m.group(1)!);
  }

  static String? _code(SyncResponse r) {
    try {
      final e = r.json()['error'];
      return e is String ? e : null;
    } on SyncTransportException {
      return null;
    }
  }

  /// Los fallos comunes a todas las rutas.
  static Never _fail(SyncResponse r) {
    final status = r.status;
    final code = _code(r) ?? 'HTTP $status';
    if (status == 409 && code.startsWith('renewal_')) {
      throw V2RenewalConflictException(code);
    }
    if (status == 400 &&
        (code == 'role_mismatch' || code == 'person_mismatch')) {
      throw V2PairingMismatchException(code);
    }
    switch (status) {
      case 401:
        throw SyncTransportException(SyncFailure.unauthorized, code);
      case 403:
        throw V2ForbiddenException(code);
      case 410:
        throw SyncTransportException(SyncFailure.unauthorized, code);
      case 413:
        throw SyncTransportException(SyncFailure.tooLarge, code);
      case 429:
        final raw = r.headers['retry-after'];
        final seconds = raw == null ? null : int.tryParse(raw.trim());
        throw SyncTransportException(
          SyncFailure.rateLimited,
          code,
          retryAfter: seconds == null ? null : Duration(seconds: seconds),
        );
    }
    if (status >= 500) {
      throw SyncTransportException(SyncFailure.server, code);
    }
    // 400, 405, 415, 426, 428 y lo que no se espera: es un error del
    // cliente o del servidor, nunca se reintenta igual.
    throw SyncTransportException(SyncFailure.protocol, code);
  }

  static int _int(Object? v, String what) {
    if (v is int && v >= 0) return v;
    throw SyncTransportException(SyncFailure.protocol, 'falta $what');
  }

  static Uint8List _b64(Object? v, String what) {
    if (v is String) {
      try {
        return decodeBase64Url(v);
      } on FormatException {
        // Cae al error.
      }
    }
    throw SyncTransportException(SyncFailure.protocol, '$what no válido');
  }

  static DateTime _time(Object? v) {
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true);
    throw const SyncTransportException(SyncFailure.protocol, 'falta expiresAt');
  }

  static Map<String, Object?> _map(Object? v, String what) {
    if (v is Map) return Map<String, Object?>.from(v);
    throw SyncTransportException(SyncFailure.protocol, '$what no válido');
  }

  /// La versión del cuerpo, que tiene que ser la del `ETag` si lo hay: una
  /// respuesta que no casa consigo misma se rechaza.
  static int _versioned(SyncResponse r, Map<String, Object?> json) {
    final version = _int(json['version'], 'version');
    final tag = r.headers['etag'];
    if (tag != null && etagVersion(tag) != version) {
      throw const SyncTransportException(
        SyncFailure.protocol,
        'la versión no casa con el ETag',
      );
    }
    return version;
  }

  static bool _renewalId(Object? v) {
    if (v is! String || !_id16.hasMatch(v)) return false;
    try {
      final bytes = decodeBase64Url(v);
      return bytes.length == 16 && encodeBase64Url(bytes) == v;
    } on FormatException {
      return false;
    }
  }

  static bool _renewalBytes(Object? v, int length) {
    if (v is! String) return false;
    try {
      final bytes = decodeBase64Url(v);
      return bytes.length == length && encodeBase64Url(bytes) == v;
    } on FormatException {
      return false;
    }
  }

  static bool _renewalCommand(Map<String, Object?> c) {
    try {
      RenewalCommand.fromJson(c);
      return true;
    } on RenewalProtocolException {
      return false;
    }
  }

  static Map<String, Object?>? _renewalState(
    Object? raw,
    V2Auth auth,
    int version,
  ) {
    if (raw == null) return null;
    Never bad() => throw const SyncTransportException(
      SyncFailure.protocol,
      'renovación no válida',
    );
    final s = _map(raw, 'renewal');
    const keys = [
      'head',
      'height',
      'logBytes',
      'operationId',
      'sourceSyncId',
      'targetSyncId',
      'revision',
      'participants',
      'branches',
      'recovery',
      'plan',
      'reservation',
      'barrier',
      'abortion',
      'ready',
      'acknowledgements',
      'transfers',
      'exclusions',
      'preparation',
      'confirmation',
      'barrierVersion',
      'confirmedVersion',
      'needsRevalidation',
    ];
    if (s.length != keys.length ||
        keys.any((k) => !s.containsKey(k)) ||
        s['sourceSyncId'] != auth.syncId ||
        !_renewalId(s['operationId']) ||
        !_renewalId(s['targetSyncId']) ||
        s['targetSyncId'] == auth.syncId ||
        !_renewalBytes(s['head'], 32) ||
        s['height'] is! int ||
        (s['height'] as int) < 1 ||
        (s['height'] as int) > kRenewalLogMaxCommands ||
        s['logBytes'] is! int ||
        (s['logBytes'] as int) < 1 ||
        (s['logBytes'] as int) > kRenewalLogMaxBytes ||
        s['revision'] is! int ||
        (s['revision'] as int) < 1 ||
        s['needsRevalidation'] is! bool ||
        utf8.encode(jsonEncode(s)).length > kRenewalControlBytes) {
      bad();
    }
    bool ids(Object? raw, int max, {bool generations = false}) =>
        raw is List &&
        raw.length <= max &&
        raw.toSet().length == raw.length &&
        raw.every(
          (id) => generations
              ? _renewalId(id)
              : id is String && kSyncIdPattern.hasMatch(id),
        );
    if (!ids(s['participants'], kRenewalParticipants) ||
        (s['participants'] as List).isEmpty ||
        !ids(s['branches'], 8, generations: true) ||
        (s['branches'] as List).contains(auth.syncId) ||
        (s['branches'] as List).contains(s['targetSyncId'])) {
      bad();
    }
    for (final key in [
      'plan',
      'reservation',
      'recovery',
      'barrier',
      'abortion',
      'ready',
      'preparation',
      'confirmation',
    ]) {
      if ((s[key] != null || key == 'plan' || key == 'reservation') &&
          !_renewalBytes(s[key], 32)) {
        bad();
      }
    }
    for (final key in ['acknowledgements', 'transfers', 'exclusions']) {
      final values = _map(s[key], key);
      if (values.length > kRenewalParticipants ||
          values.entries.any(
            (e) =>
                !(s['participants'] as List).contains(e.key) ||
                !_renewalBytes(e.value, 32),
          )) {
        bad();
      }
    }
    for (final key in ['barrierVersion', 'confirmedVersion']) {
      if (s[key] != null &&
          (s[key] is! int ||
              (s[key] as int) < 1 ||
              (s[key] as int) > version)) {
        bad();
      }
    }
    return Map.unmodifiable(s);
  }

  @override
  Future<V2RenewalSnapshot> getRenewal(V2Auth auth) => _getRenewal(auth);
  @override
  Future<RenewalLogPage> getRenewalLogPage(
    V2Auth auth, {
    required String operationId,
    required String head,
    required int after,
  }) async {
    if (!_renewalId(operationId) ||
        !_renewalBytes(head, 32) ||
        after < 0 ||
        after > kRenewalLogMaxCommands) {
      throw ArgumentError('renewal log cursor');
    }
    final r = await sendRequest(
      'GET',
      _uri('${_list(auth)}/renewal/log/$operationId/$head/$after'),
      headers: _authed(auth),
    );
    if (r.status == 404 || r.status == 410) {
      throw V2RenewalGoneException(retired: r.status == 410);
    }
    if (r.status != 200) _fail(r);
    try {
      final page = RenewalLogPage.fromJson(r.json());
      if (page.sourceSyncId != auth.syncId ||
          page.operationId != operationId ||
          page.head != head ||
          page.after != after) {
        throw const RenewalProtocolException('page_context');
      }
      return page;
    } on RenewalProtocolException {
      throw const SyncTransportException(
        SyncFailure.protocol,
        'registro de renovación no válido',
      );
    }
  }

  Future<V2RenewalSnapshot> _getRenewal(V2Auth auth) async {
    final r = await sendRequest(
      'GET',
      _uri('${_list(auth)}/renewal'),
      headers: _authed(auth),
    );
    if (r.status == 404 || r.status == 410) {
      throw V2RenewalGoneException(retired: r.status == 410);
    }
    if (r.status != 200) _fail(r);
    final json = r.json();
    final version = _versioned(r, json);
    if (version < 1 ||
        r.headers['etag'] == null ||
        !json.containsKey('renewal')) {
      throw const SyncTransportException(
        SyncFailure.protocol,
        'falta renovación o ETag',
      );
    }
    return V2RenewalSnapshot(
      version: version,
      renewal: _renewalState(json['renewal'], auth, version),
    );
  }

  @override
  Future<V2WriteResult> putRenewal(
    V2Auth auth, {
    required int version,
    required Map<String, Object?> command,
  }) async {
    if (!_renewalCommand(command) ||
        command['sourceSyncId'] != auth.syncId ||
        command['signerDeviceId'] != auth.deviceId ||
        command['sourceVersion'] != version ||
        utf8.encode(jsonEncode(command)).length > kRenewalCommandBytes) {
      throw const SyncTransportException(
        SyncFailure.protocol,
        'comando de renovación no válido',
      );
    }
    final r = await sendRequest(
      'PUT',
      _uri('${_list(auth)}/renewal'),
      headers: _authed(auth, {'If-Match': _etag(version)}),
      body: command,
    );
    if (r.status == 200) {
      final json = r.json();
      final next = _versioned(r, json);
      final state = _renewalState(json['renewal'], auth, next);
      if (next <= version ||
          r.headers['etag'] == null ||
          !json.containsKey('renewal') ||
          state == null ||
          state['operationId'] != command['operationId'] ||
          state['targetSyncId'] != command['targetSyncId'] ||
          state['revision'] != command['revision']) {
        throw const SyncTransportException(
          SyncFailure.protocol,
          'respuesta de renovación no válida',
        );
      }
      return V2WriteOk(next);
    }
    // Control never creates a list: 201 must not bypass context validation.
    if (r.status == 201) _fail(r);
    return _write(r);
  }

  V2WriteResult _write(SyncResponse r) {
    switch (r.status) {
      case 200:
      case 201:
        return V2WriteOk(_versioned(r, r.json()));
      case 412:
        return V2WriteStale(etagVersion(r.headers['etag']));
      case 404:
      case 410:
        return const V2WriteNotFound();
      case 409:
        if (_code(r) == 'generation_full') {
          throw const V2GenerationFullException();
        }
    }
    final code = _code(r);
    if ((r.status == 409 || r.status == 400) &&
        code != null &&
        code.startsWith('common_format_')) {
      throw V2CommonFormatException(code);
    }
    _fail(r);
  }

  /// `capacity` del `GET`, o null si no viene (un servidor anterior). Si
  /// viene, tiene que estar bien formado.
  static V2Capacity? _capacity(Object? raw) {
    if (raw == null) return null;
    V2CapacityCount count(Object? v) {
      final m = _map(v, 'capacity');
      return V2CapacityCount(
        used: _int(m['used'], 'capacity'),
        warn: _int(m['warn'], 'capacity'),
        max: _int(m['max'], 'capacity'),
      );
    }

    final m = _map(raw, 'capacity');
    final renew = m['renew'];
    if (renew is! bool) {
      throw const SyncTransportException(
        SyncFailure.protocol,
        'capacity no válido',
      );
    }
    return V2Capacity(
      credentials: count(m['credentials']),
      records: count(m['records']),
      slots: m['slots'] == null ? null : count(m['slots']),
      renew: renew,
    );
  }

  // ----------------------------------------------------------------- lista

  @override
  Future<V2WriteResult> createList(V2Auth auth, V2SnapshotUpload body) async {
    final r = await sendRequest(
      'PUT',
      _uri(_list(auth)),
      body: body._json(deviceId: auth.deviceId),
      headers: _authed(auth, {'If-Match': _etag(0)}),
    );
    final result = _write(r);
    if (result is V2WriteOk && result.version != 1) {
      throw const SyncTransportException(
        SyncFailure.protocol,
        'una lista nueva empieza en la versión 1',
      );
    }
    return result;
  }

  @override
  Future<V2GetResult> getList(V2Auth auth, {int? ifNoneMatch}) async {
    final r = await sendRequest(
      'GET',
      _uri(_list(auth)),
      headers: _authed(auth, {
        if (ifNoneMatch != null) 'If-None-Match': _etag(ifNoneMatch),
      }),
    );
    switch (r.status) {
      case 200:
        final json = r.json();
        final version = _versioned(r, json);
        final packages = json['keyPackages'];
        final slots = json['slots'];
        final devices = json['devices'];
        if (packages is! List || slots is! List || devices is! List) {
          throw const SyncTransportException(
            SyncFailure.protocol,
            'instantánea incompleta',
          );
        }
        final refs = <V2SlotRef>[];
        final seen = <String>{};
        for (final raw in slots) {
          final s = _map(raw, 'slot');
          final person = s['personId'];
          final device = s['deviceId'];
          if (person is! String ||
              device is! String ||
              !kSyncIdPattern.hasMatch(person) ||
              !kSyncIdPattern.hasMatch(device)) {
            throw const SyncTransportException(
              SyncFailure.protocol,
              'manifiesto no válido',
            );
          }
          final ref = V2SlotRef(
            personId: person,
            deviceId: device,
            version: _int(s['version'], 'version del slot'),
          );
          // Un slot no puede ser más nuevo que la instantánea ni repetirse.
          if (ref.version > version || !seen.add(ref.key)) {
            throw const SyncTransportException(
              SyncFailure.protocol,
              'manifiesto no válido',
            );
          }
          refs.add(ref);
        }
        return V2GetOk(
          V2Snapshot(
            version: version,
            common: _b64(json['common'], 'common'),
            registry: json['registry'],
            keyPackages: [for (final p in packages) _map(p, 'paquete')],
            slots: List.unmodifiable(refs),
            devices: List.unmodifiable([
              for (final raw in devices)
                () {
                  final d = _map(raw, 'device');
                  final id = d['deviceId'];
                  if (id is! String || d['revoked'] is! bool) {
                    throw const SyncTransportException(
                      SyncFailure.protocol,
                      'devices no válido',
                    );
                  }
                  final by = d['approvedBy'];
                  final role = d['role'] ?? 'device';
                  if (role != 'device' && role != 'web') {
                    throw const SyncTransportException(
                      SyncFailure.protocol,
                      'role',
                    );
                  }
                  if (by != null &&
                      (by is! String || !kSyncIdPattern.hasMatch(by))) {
                    throw const SyncTransportException(
                      SyncFailure.protocol,
                      'approvedBy',
                    );
                  }
                  final format = d['commonFormat'] ?? 1;
                  if (format is! int || format < 1) {
                    throw const SyncTransportException(
                      SyncFailure.protocol,
                      'commonFormat',
                    );
                  }
                  return V2Device(
                    deviceId: id,
                    revoked: d['revoked'] == true,
                    approvedBy: by as String?,
                    role: role as String,
                    commonFormat: format,
                  );
                }(),
            ]),
            capacity: _capacity(json['capacity']),
            minCommonFormat: () {
              final min = json['minCommonFormat'] ?? 1;
              if (min is! int || min < 1) {
                throw const SyncTransportException(
                  SyncFailure.protocol,
                  'minCommonFormat',
                );
              }
              return min;
            }(),
          ),
        );
      case 304:
        if (ifNoneMatch == null) _fail(r);
        return const V2GetNotModified();
      case 404:
        return const V2GetNotFound();
    }
    _fail(r);
  }

  @override
  Future<V2SlotResult> getSlot(
    V2Auth auth, {
    required int version,
    required String personId,
    required String deviceId,
  }) async {
    _checkPathId(personId);
    _checkPathId(deviceId);
    final r = await sendRequest(
      'GET',
      _uri('${_list(auth)}/slots/$personId/$deviceId'),
      headers: _authed(auth, {'If-Match': _etag(version)}),
    );
    switch (r.status) {
      case 200:
        final json = r.json();
        final got = _versioned(r, json);
        if (got != version) {
          // Un servidor que contesta con otra versión que la pedida mezcla
          // instantáneas: no vale.
          throw const SyncTransportException(
            SyncFailure.protocol,
            'slot de otra versión',
          );
        }
        final slotVersion = _int(json['slotVersion'], 'slotVersion');
        if (slotVersion > version) {
          throw const SyncTransportException(
            SyncFailure.protocol,
            'slot del futuro',
          );
        }
        return V2SlotOk(
          version: got,
          slotVersion: slotVersion,
          data: _b64(json['data'], 'data'),
        );
      case 412:
        return const V2SlotStale();
      case 404:
        return const V2SlotMissing();
    }
    _fail(r);
  }

  @override
  Future<V2WriteResult> putList(
    V2Auth auth, {
    required int version,
    required V2SnapshotUpload body,
  }) async {
    final r = await sendRequest(
      'PUT',
      _uri(_list(auth)),
      body: body._json(),
      headers: _authed(auth, {'If-Match': _etag(version)}),
    );
    final result = _write(r);
    if (result is V2WriteOk && result.version <= version) {
      throw const SyncTransportException(
        SyncFailure.protocol,
        'la versión no ha subido',
      );
    }
    return result;
  }

  @override
  Future<V2WriteResult> putCommon(
    V2Auth auth, {
    required int version,
    required Uint8List common,
  }) async {
    final r = await sendRequest(
      'PUT',
      _uri('${_list(auth)}/common'),
      body: {'common': encodeBase64Url(common)},
      headers: _authed(auth, {'If-Match': _etag(version)}),
    );
    final result = _write(r);
    if (result is V2WriteOk && result.version <= version) {
      throw const SyncTransportException(
        SyncFailure.protocol,
        'la versión no ha subido',
      );
    }
    return result;
  }

  @override
  Future<V2WriteResult> deleteList(
    V2Auth auth, {
    required int version,
    bool automaticRetirement = false,
  }) async {
    final r = await sendRequest(
      'DELETE',
      _uri(_list(auth)),
      headers: _authed(auth, {
        'If-Match': _etag(version),
        if (automaticRetirement) 'X-Automatic-Retirement': 'true',
      }),
    );
    if (r.status == 204) return V2WriteOk(version);
    return _write(r);
  }

  @override
  Future<int> announceCommonFormat(V2Auth auth, int format) async {
    final r = await sendRequest(
      'POST',
      _uri('${_list(auth)}/capability'),
      body: {'commonFormat': format},
      headers: _authed(auth),
    );
    if (r.status == 200) return _versioned(r, r.json());
    _fail(r);
  }

  @override
  Future<int> revoke(V2Auth auth, String deviceId, {int? ifVersion}) async {
    _checkPathId(deviceId);
    final r = await sendRequest(
      'POST',
      _uri('${_list(auth)}/revoke'),
      body: {'deviceId': deviceId},
      headers: _authed(auth, {
        if (ifVersion != null) 'If-Match': _etag(ifVersion),
      }),
    );
    if (r.status == 200) return _versioned(r, r.json());
    if (r.status == 412 && ifVersion != null) {
      throw const V2RevokeStaleException();
    }
    if (r.status == 404) {
      throw const SyncTransportException(
        SyncFailure.protocol,
        'móvil desconocido',
      );
    }
    _fail(r);
  }

  @override
  Stream<SyncEvent> watch(V2Auth auth) {
    final socket = openSocket;
    if (socket == null) {
      return Stream.error(
        const SyncTransportException(SyncFailure.network, 'sin WebSocket'),
      );
    }
    final ws = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '${_list(auth)}/ws',
    );
    return socket(ws, [
      kWsProtocolV2,
      'bearer.${encodeBase64Url(auth.credential)}',
    ]);
  }

  // ---------------------------------------------------------- invitaciones

  InviteTicket _ticket(SyncResponse r) {
    final json = r.json();
    final id = json['inviteId'];
    if (id is! String || !_id16.hasMatch(id)) {
      throw const SyncTransportException(SyncFailure.protocol, 'sin inviteId');
    }
    return InviteTicket(inviteId: id, expiresAt: _time(json['expiresAt']));
  }

  Never _inviteFail(SyncResponse r) {
    if (r.status == 404) throw const InviteGoneException();
    if (r.status == 409) {
      final code = _code(r) ?? 'conflict';
      if (code.startsWith('renewal_')) _fail(r);
      if (code == 'already_answered') throw const InviteTakenException();
      throw V2InviteConflictException(code);
    }
    _fail(r);
  }

  @override
  Future<InviteTicket> createInvite(
    V2Auth auth,
    Map<String, Object?> offer, {
    String? inviteId,
    String? guestPerson,
  }) async {
    if (inviteId != null) _checkId(inviteId);
    if (guestPerson != null) _checkPathId(guestPerson);
    final r = await sendRequest(
      'POST',
      _uri('${_list(auth)}/invites'),
      body: {
        'offer': offer,
        'inviteId': ?inviteId,
        'guestPerson': ?guestPerson,
      },
      headers: _authed(auth),
    );
    if (r.status == 201 || r.status == 200) return _ticket(r);
    _inviteFail(r);
  }

  @override
  Future<V2InviteState> getInvite(V2Auth auth, String inviteId) async {
    _checkId(inviteId);
    final r = await sendRequest(
      'GET',
      _uri('${_list(auth)}/invites/$inviteId'),
      headers: _authed(auth),
    );
    if (r.status != 200) _inviteFail(r);
    final json = r.json();
    return V2InviteState(
      offer: json['offer'],
      answer: json['answer'],
      revealed: json['revealed'] == true,
      approved: json['approved'] == true,
      canApprove: json['canApprove'] != false,
      expiresAt: _time(json['expiresAt']),
    );
  }

  @override
  Future<void> revealInvite(
    V2Auth auth,
    String inviteId,
    Map<String, Object?> reveal,
  ) async {
    _checkId(inviteId);
    final r = await sendRequest(
      'POST',
      _uri('${_list(auth)}/invites/$inviteId/reveal'),
      body: {'reveal': reveal},
      headers: _authed(auth),
    );
    if (r.status != 200) _inviteFail(r);
  }

  @override
  Future<V2WriteResult> approveInvite(
    V2Auth auth,
    String inviteId, {
    required int version,
    required Map<String, Object?> package,
    String role = 'device',
    V2CheckpointClaim? checkpoint,
  }) async {
    _checkId(inviteId);
    final r = await sendRequest(
      'POST',
      _uri('${_list(auth)}/invites/$inviteId/approve'),
      body: {
        'package': package,
        'role': role,
        if (checkpoint != null)
          'checkpoint': {
            'common': checkpoint.common,
            'registry': checkpoint.registry,
          },
      },
      headers: _authed(auth, {'If-Match': _etag(version)}),
    );
    if (r.status == 200) {
      final v = _versioned(r, r.json());
      if (v <= version) {
        throw const SyncTransportException(
          SyncFailure.protocol,
          'la versión no ha subido',
        );
      }
      return V2WriteOk(v);
    }
    if (r.status == 412) return V2WriteStale(etagVersion(r.headers['etag']));
    _inviteFail(r);
  }

  @override
  Future<void> deleteInvite(V2Auth auth, String inviteId) async {
    _checkId(inviteId);
    final r = await sendRequest(
      'DELETE',
      _uri('${_list(auth)}/invites/$inviteId'),
      headers: _authed(auth),
    );
    if (r.status == 204 || r.status == 404) return;
    _fail(r);
  }

  @override
  Future<V2InviteOffer> getOffer(
    String inviteId, {
    bool allowNotYet = false,
  }) async {
    _checkId(inviteId);
    final r = await sendRequest('GET', _uri('/v2/invites/$inviteId/offer'));
    if (r.status == 404 && allowNotYet) throw const V2OfferNotYetException();
    if (r.status != 200) _inviteFail(r);
    final json = r.json();
    final person = json['guestPerson'];
    if (person != null &&
        (person is! String || !kSyncIdPattern.hasMatch(person))) {
      throw const SyncTransportException(SyncFailure.protocol, 'guestPerson');
    }
    return V2InviteOffer(
      offer: json['offer'],
      guestPerson: person as String?,
      expiresAt: _time(json['expiresAt']),
    );
  }

  @override
  Future<void> answerInvite(
    String inviteId, {
    required Map<String, Object?> answer,
    required Uint8List verifier,
  }) async {
    _checkId(inviteId);
    final r = await sendRequest(
      'POST',
      _uri('/v2/invites/$inviteId/answer'),
      body: {
        'answer': answer,
        'serviceCredentialVerifier': encodeBase64Url(verifier),
      },
    );
    if (r.status == 201 || r.status == 200) return;
    _inviteFail(r);
  }

  @override
  Future<V2InviteOutcome> pollInviteResult(
    String inviteId, {
    required Uint8List credential,
  }) async {
    _checkId(inviteId);
    final r = await sendRequest(
      'GET',
      _uri('/v2/invites/$inviteId/result'),
      headers: {'Authorization': 'Bearer ${encodeBase64Url(credential)}'},
    );
    switch (r.status) {
      case 202:
        return V2InvitePending(r.json()['reveal']);
      case 200:
        final json = r.json();
        final syncId = json['syncId'];
        if (syncId is! String || !_id16.hasMatch(syncId)) {
          throw const SyncTransportException(
            SyncFailure.protocol,
            'syncId no válido',
          );
        }
        return V2InviteApproved(
          reveal: json['reveal'],
          package: _map(json['package'], 'package'),
          minVersion: _int(json['minVersion'], 'minVersion'),
          syncId: syncId,
        );
      case 404:
        return const V2InviteGone();
    }
    _fail(r);
  }

  @override
  Future<V2InviteCheckpoint?> getInviteCheckpoint(
    String inviteId, {
    required Uint8List credential,
  }) async {
    _checkId(inviteId);
    final r = await sendRequest(
      'GET',
      _uri('/v2/invites/$inviteId/checkpoint'),
      headers: {'Authorization': 'Bearer ${encodeBase64Url(credential)}'},
    );
    if (r.status == 404) return null;
    if (r.status != 200) _fail(r);
    final json = r.json();
    final common = json['common'];
    final registry = json['registry'];
    if (common is! String || registry is! String) {
      throw const SyncTransportException(
        SyncFailure.protocol,
        'checkpoint no válido',
      );
    }
    return V2InviteCheckpoint(common: common, registry: registry);
  }

  @override
  Future<void> releaseInviteCheckpoint(
    String inviteId, {
    required Uint8List credential,
  }) async {
    _checkId(inviteId);
    final r = await sendRequest(
      'DELETE',
      _uri('/v2/invites/$inviteId/checkpoint'),
      headers: {'Authorization': 'Bearer ${encodeBase64Url(credential)}'},
    );
    if (r.status == 204 || r.status == 404) return;
    _fail(r);
  }
}

/// Interpreta un mensaje del WebSocket v2 (solo `version`). Devuelve null si
/// no se entiende.
SyncEvent? parseSyncEventV2(String message) {
  try {
    final json = jsonDecode(message);
    if (json is Map && json['type'] == 'version') {
      final v = json['version'];
      return v is int && v >= 0 ? SyncVersionEvent(v) : null;
    }
  } on FormatException {
    return null;
  }
  return null;
}
