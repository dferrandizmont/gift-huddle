// Contrato HTTP de la sincronización (docs/adr/0002-sincronizacion.md) como
// interfaz. La implementación real está en `http_sync_transport.dart`; las
// pruebas usan un servidor falso en memoria.
library;

import 'dart:typed_data';

/// Con qué se identifica un móvil ante el servidor: la lista y su `authKey`.
class SyncCredentials {
  /// Crea las credenciales.
  const SyncCredentials({
    required this.listId,
    required this.syncId,
    required this.authKey,
  });

  /// Id de la lista (ADR 0001). No sale del móvil hacia el servidor.
  final String listId;

  /// Id de la lista en el servidor (URLs): derivado de la clave de la familia.
  final String syncId;

  /// `authKey` derivada de la clave de la familia (`SyncKeys.authKey`).
  final Uint8List authKey;

  @override
  String toString() => 'SyncCredentials($syncId, …)';
}

// ------------------------------------------------------------- resultados

/// Respuesta a `GET /v1/lists/{listId}`.
sealed class SyncGetResult {
  const SyncGetResult();
}

/// `200 { version, envelope }`.
final class SyncGetOk extends SyncGetResult {
  /// Crea el resultado.
  const SyncGetOk({required this.version, required this.envelope});

  /// Versión del servidor.
  final int version;

  /// Sobre cifrado (ADR 0001).
  final Uint8List envelope;
}

/// `304`: no hay nada más nuevo que la versión conocida.
final class SyncGetNotModified extends SyncGetResult {
  /// Crea el resultado.
  const SyncGetNotModified();
}

/// `404`: el servidor no tiene la lista (primera vez o caducada).
final class SyncGetNotFound extends SyncGetResult {
  /// Crea el resultado.
  const SyncGetNotFound();
}

/// Respuesta a `PUT /v1/lists/{listId}`.
sealed class SyncPutResult {
  const SyncPutResult();
}

/// Guardado: [version] es la nueva versión del servidor.
final class SyncPutOk extends SyncPutResult {
  /// Crea el resultado.
  const SyncPutOk({required this.version});

  /// Nueva versión.
  final int version;
}

/// `409`: otro móvil subió antes. Trae lo que hay en el servidor para
/// fusionarlo y reintentar.
final class SyncPutConflict extends SyncPutResult {
  /// Crea el resultado.
  const SyncPutConflict({required this.version, required this.envelope});

  /// Versión actual del servidor.
  final int version;

  /// Sobre actual del servidor.
  final Uint8List envelope;
}

/// `404` al subir con `baseVersion` distinto de `null`: la lista ya no está
/// en el servidor; hay que volver a subirla con `baseVersion: null`.
final class SyncPutNotFound extends SyncPutResult {
  /// Crea el resultado.
  const SyncPutNotFound();
}

/// Lo que llega por el WebSocket de la lista.
sealed class SyncEvent {
  const SyncEvent();
}

/// El WebSocket acaba de abrirse. No lo manda el servidor: lo genera el cliente
/// al conectar, para saber que la conexión es buena y ponerse al día con lo que
/// se haya podido perder mientras estuvo cortada.
final class SyncOpenEvent extends SyncEvent {
  /// Crea el evento.
  const SyncOpenEvent();
}

/// A WebSocket pong confirms liveness without announcing a list change.
/// Emitted by the browser transport; wire-message parsers remain unchanged.
final class SyncAliveEvent extends SyncEvent {
  const SyncAliveEvent();
}

/// `{"type":"version","version":n}`: la lista cambió en el servidor.
final class SyncVersionEvent extends SyncEvent {
  /// Crea el evento.
  const SyncVersionEvent(this.version);

  /// Versión nueva.
  final int version;
}

/// `{"type":"join-request"}`: alguien pidió entrar con una invitación.
final class SyncJoinRequestEvent extends SyncEvent {
  /// Crea el evento.
  const SyncJoinRequestEvent();
}

/// El servidor cerró el WebSocket con 4404: la lista ya no está (la borró otro
/// móvil o caducó). Hay que volver a subirla con `baseVersion: null`, salvo que
/// la persona haya pedido dejar de sincronizar.
final class SyncGoneEvent extends SyncEvent {
  /// Crea el evento.
  const SyncGoneEvent();
}

/// v2: el servidor ha revocado la credencial de este móvil (cierre 4401).
final class SyncRevokedEvent extends SyncEvent {
  /// Crea el evento.
  const SyncRevokedEvent();
}

/// Exact authenticated close 4410 / credential_replaced (ADR 0007).
final class SyncTransferredEvent extends SyncEvent {
  const SyncTransferredEvent();
}

// ----------------------------------------------------------- invitaciones

/// Respuesta a crear una invitación.
class InviteTicket {
  /// Crea el resultado.
  const InviteTicket({required this.inviteId, required this.expiresAt});

  /// Id de la invitación: 16 bytes aleatorios en base64url.
  final String inviteId;

  /// Cuándo caduca.
  final DateTime expiresAt;
}

/// La petición de quien abrió el enlace.
class InviteJoinRequest {
  /// Crea la petición.
  const InviteJoinRequest({required this.publicKey, required this.deviceName});

  /// Clave pública X25519 efímera de quien entra (32 bytes).
  final Uint8List publicKey;

  /// Nombre del móvil que pide entrar (viene de otro móvil: no es de fiar).
  final String deviceName;
}

/// Lo que sube quien da acceso y recoge quien entra: el paquete cifrado.
class InviteApproval {
  /// Crea la aprobación.
  const InviteApproval({required this.ciphertext, required this.nonce});

  /// Paquete cifrado con AES-256-GCM (texto cifrado y etiqueta de 16 bytes).
  final Uint8List ciphertext;

  /// Nonce de 96 bits.
  final Uint8List nonce;
}

/// Respuesta a recoger el resultado de una invitación.
sealed class InviteOutcome {
  const InviteOutcome();
}

/// Todavía no han dado acceso. Con [publicKeyA] ya hay oferta de quien invita:
/// quien entra puede calcular y enseñar el código.
final class InvitePending extends InviteOutcome {
  /// Crea el resultado.
  const InvitePending({this.publicKeyA});

  /// Clave pública X25519 efímera de quien invita (32 bytes), si ya la
  /// ofreció.
  final Uint8List? publicKeyA;
}

/// Aprobada: la clave viaja cifrada en [approval].
final class InviteApproved extends InviteOutcome {
  /// Crea el resultado.
  const InviteApproved(this.approval);

  /// La aprobación.
  final InviteApproval approval;
}

/// Rechazada, caducada o ya recogida.
final class InviteGone extends InviteOutcome {
  /// Crea el resultado.
  const InviteGone();
}

// ---------------------------------------------------------------- errores

/// Por qué falló una petición.
enum SyncFailure {
  /// Sin red, tiempo agotado o conexión cortada.
  network,

  /// `401` o `403`: el servidor no acepta la clave.
  unauthorized,

  /// `429`.
  rateLimited,

  /// `413`: el sobre pasa del límite.
  tooLarge,

  /// `5xx`.
  server,

  /// El servidor contestó algo que no se entiende.
  protocol,
}

/// Fallo de una petición al servidor.
class SyncTransportException implements Exception {
  /// Crea el error.
  const SyncTransportException(this.failure, this.message, {this.retryAfter});

  /// Clase de fallo.
  final SyncFailure failure;

  /// Detalle para el registro (nunca lleva claves).
  final String message;

  /// Espera que pide el servidor con `429`, si la dio.
  final Duration? retryAfter;

  @override
  String toString() => 'SyncTransportException(${failure.name}): $message';
}

/// La invitación ya tiene una petición (`409` al pedir entrada).
class InviteTakenException implements Exception {
  /// Crea el error.
  const InviteTakenException();

  @override
  String toString() => 'InviteTakenException';
}

/// La invitación no existe, caducó o se rechazó (`404`/`410`).
class InviteGoneException implements Exception {
  /// Crea el error.
  const InviteGoneException();

  @override
  String toString() => 'InviteGoneException';
}

// --------------------------------------------------------------- interfaz

/// Lo que la app necesita del servidor de sincronización.
abstract interface class SyncTransport {
  /// `GET /v1/lists/{listId}` con `If-None-Match` si se da [ifNoneMatch].
  Future<SyncGetResult> getList(SyncCredentials auth, {int? ifNoneMatch});

  /// `PUT /v1/lists/{listId}`. Con [baseVersion] `null` es la primera subida.
  Future<SyncPutResult> putList(
    SyncCredentials auth, {
    required int? baseVersion,
    required Uint8List envelope,
  });

  /// `DELETE /v1/lists/{listId}`.
  Future<void> deleteList(SyncCredentials auth);

  /// `GET /v1/lists/{listId}/ws`. El flujo se conecta al escucharlo y acaba
  /// (con error o sin él) cuando se corta; quien escucha reconecta.
  Stream<SyncEvent> watch(SyncCredentials auth);

  /// `POST /v1/lists/{listId}/invites`.
  Future<InviteTicket> createInvite(SyncCredentials auth);

  /// `GET /v1/lists/{listId}/invites/{inviteId}`: la petición de entrada, o
  /// `null` si todavía no hay. Lanza [InviteGoneException] si la invitación
  /// ya no existe.
  Future<InviteJoinRequest?> getInviteRequest(
    SyncCredentials auth,
    String inviteId,
  );

  /// `POST /v1/lists/{syncId}/invites/{inviteId}/offer { publicKeyA }`: quien
  /// invita ofrece su clave pública para que los dos calculen el código.
  Future<void> offerInvite(
    SyncCredentials auth,
    String inviteId,
    Uint8List publicKeyA,
  );

  /// `POST /v1/lists/{syncId}/invites/{inviteId}/approve { ciphertext, nonce }`:
  /// solo tras comparar el código y solo si hubo oferta.
  Future<void> approveInvite(
    SyncCredentials auth,
    String inviteId,
    InviteApproval approval,
  );

  /// `POST /v1/lists/{listId}/invites/{inviteId}/reject`: rechaza o cancela.
  Future<void> rejectInvite(SyncCredentials auth, String inviteId);

  /// `POST /v1/invites/{inviteId}/join` (sin autenticación).
  ///
  /// Lanza [InviteTakenException] si ya hay una petición e
  /// [InviteGoneException] si la invitación no existe.
  Future<void> requestJoin(
    String inviteId, {
    required Uint8List publicKey,
    required String deviceName,
  });

  /// `GET /v1/invites/{inviteId}/result` presentando la misma [publicKey]
  /// con la que se pidió entrada (sin autenticación).
  Future<InviteOutcome> pollInviteResult(
    String inviteId, {
    required Uint8List publicKey,
  });
}
