// Lo que el ADR deja sin fijar, tal como lo implementa el servidor (server/src):
// - `PUT` correcto: `200`/`201 { "version": n }`. Primera subida sobre una lista
//   que ya existe con otro verificador: `409 { "error": "exists" }` sin sobre.
// - Crear invitación: `201 { "inviteId", "expiresAt" }` (`expiresAt` en ms).
// - Ver la petición: `200 { "status", "expiresAt", "request"?: { "publicKey",
//   "deviceName" } }`; `404`: la invitación ya no existe.
// - Rechazar o cancelar: `POST /v1/lists/{listId}/invites/{inviteId}/reject`.
// - Oferta: `POST …/invites/{inviteId}/offer { "publicKeyA" }`; después
//   `POST …/approve { "ciphertext", "nonce" }`.
// - Recoger: `GET /v1/invites/{inviteId}/result` con la clave pública de quien
//   entra en la cabecera `X-Public-Key` (base64url); sin oferta, `202`; con
//   oferta, `202 { "status": "pending", "publicKeyA" }`; con acceso dado,
//   `200 { "ciphertext", "nonce" }` (una sola vez); cualquier otra cosa, el
//   mismo `404`.
// - Las URLs de la lista llevan el `syncId`, no el `listId`.
// - WebSocket: subprotocolos `gift-huddle.v1` y `bearer.<authKey>`; al borrarse
//   la lista se cierra con 4404.

import 'dart:convert';
import 'dart:typed_data';

import '../../../core/sync/envelope.dart';
import 'sync_endpoint.dart';
import 'sync_routes.dart';
import 'sync_transport.dart';
import 'sync_transport_v2.dart';

const maxSyncResponseBytes = 4 * 1024 * 1024;

class SyncResponse {
  SyncResponse(this.status, this.headers, this.body);

  final int status;
  final Map<String, String> headers;
  final Uint8List body;

  Map<String, Object?> json() {
    if (body.isEmpty) {
      return const {};
    }
    try {
      final decoded = jsonDecode(utf8.decode(body));
      if (decoded is Map) {
        return Map<String, Object?>.from(decoded);
      }
    } on FormatException {
      // Cae al error de protocolo.
    }
    throw const SyncTransportException(
      SyncFailure.protocol,
      'respuesta que no es un objeto JSON',
    );
  }

  void requireWorkerError(String expected) {
    try {
      final body = json();
      if (body.length == 1 && body['error'] == expected) return;
    } on SyncTransportException {
      // Un proxy puede devolver HTML u otra respuesta que no sea JSON.
    }
    throw SyncTransportException(SyncFailure.server, 'HTTP $status');
  }
}

abstract class BaseSyncTransport implements SyncTransport {
  BaseSyncTransport(
    this.endpoint, {
    this.timeout = const Duration(seconds: 20),
    SyncRoutes? routes,
  }) : routes = routes ?? SyncRoutes.shared(endpoint.routes);
  final SyncEndpoint endpoint;
  final Duration timeout;

  /// Los hosts que se prueban para cada petición y cada WebSocket
  /// (`sync_routes.dart`). Las direcciones se construyen siempre con
  /// `endpoint.base`; el transporte cambia el host al enviar.
  final SyncRoutes routes;
  Uri uri(String path, [Map<String, String>? query]) =>
      endpoint.base.replace(path: path, queryParameters: query);
  String listPath(SyncCredentials auth) => '/v1/lists/${auth.syncId}';
  Future<SyncResponse> send(
    String method,
    Uri uri, {
    SyncCredentials? auth,
    Object? body,
    Map<String, String> headers = const {},
  });
  void close();

  /// Abre un WebSocket de la API v2 (ver `SyncV2Client.watch`). Solo en los
  /// móviles: la web no tiene credencial de móvil (ADR 0004, 27).
  Stream<SyncEvent> socketV2(Uri uri, List<String> protocols) => Stream.error(
    const SyncTransportException(SyncFailure.network, 'sin WebSocket v2'),
  );

  /// El cliente de la API v2 sobre este mismo transporte.
  late final SyncV2Client v2 = SyncV2Client(
    base: endpoint.base,
    sendRequest: (method, uri, {body, headers = const {}}) =>
        send(method, uri, body: body, headers: headers),
    openSocket: socketV2,
  );

  /// Convierte los estados de error comunes en [SyncTransportException].
  Never _fail(SyncResponse r) {
    final status = r.status;
    if (status == 401 || status == 403) {
      throw SyncTransportException(SyncFailure.unauthorized, 'HTTP $status');
    }
    if (status == 413) {
      throw SyncTransportException(SyncFailure.tooLarge, 'HTTP $status');
    }
    if (status == 429) {
      final raw = r.headers['retry-after'];
      final seconds = raw == null ? null : int.tryParse(raw);
      throw SyncTransportException(
        SyncFailure.rateLimited,
        'HTTP 429',
        retryAfter: seconds == null ? null : Duration(seconds: seconds),
      );
    }
    if (status >= 500) {
      throw SyncTransportException(SyncFailure.server, 'HTTP $status');
    }
    throw SyncTransportException(SyncFailure.protocol, 'HTTP $status');
  }

  static int _version(Map<String, Object?> json) {
    final v = json['version'];
    if (v is int && v >= 0) {
      return v;
    }
    throw const SyncTransportException(SyncFailure.protocol, 'falta version');
  }

  static Uint8List _bytes(Object? value, String what) {
    if (value is String) {
      try {
        return decodeBase64Url(value);
      } on FormatException {
        // Cae al error.
      }
    }
    throw SyncTransportException(SyncFailure.protocol, '$what no es base64url');
  }

  // ---------------------------------------------------------------- lista

  static void _checkListMissing(SyncResponse r) {
    r.requireWorkerError(r.status == 404 ? 'not_found' : 'gone');
  }

  @override
  Future<SyncGetResult> getList(
    SyncCredentials auth, {
    int? ifNoneMatch,
  }) async {
    final r = await send(
      'GET',
      uri(listPath(auth)),
      auth: auth,
      headers: {if (ifNoneMatch != null) 'If-None-Match': '"$ifNoneMatch"'},
    );
    switch (r.status) {
      case 200:
        final json = r.json();
        return SyncGetOk(
          version: _version(json),
          envelope: _bytes(json['envelope'], 'envelope'),
        );
      case 304:
        return const SyncGetNotModified();
      case 404:
      case 410:
        _checkListMissing(r);
        return const SyncGetNotFound();
      default:
        _fail(r);
    }
  }

  @override
  Future<SyncPutResult> putList(
    SyncCredentials auth, {
    required int? baseVersion,
    required Uint8List envelope,
  }) async {
    final r = await send(
      'PUT',
      uri(listPath(auth)),
      auth: auth,
      body: {'baseVersion': baseVersion, 'envelope': encodeBase64Url(envelope)},
    );
    switch (r.status) {
      case 200:
      case 201:
        final json = r.json();
        // Si el servidor no dice la versión, se deduce.
        final v = json['version'];
        return SyncPutOk(version: v is int ? v : (baseVersion ?? 0) + 1);
      case 409:
        final json = r.json();
        if (json['error'] == 'exists') {
          // La lista ya existe con otra clave: no es de este móvil.
          throw const SyncTransportException(
            SyncFailure.unauthorized,
            'la lista ya existe con otra clave',
          );
        }
        return SyncPutConflict(
          version: _version(json),
          envelope: _bytes(json['envelope'], 'envelope'),
        );
      case 404:
        return const SyncPutNotFound();
      default:
        _fail(r);
    }
  }

  @override
  Future<void> deleteList(SyncCredentials auth) async {
    final r = await send('DELETE', uri(listPath(auth)), auth: auth);
    // El Worker confirma el borrado con 204; otro 2xx (un intermediario que
    // no entregó la petición) no cuenta como borrado.
    if (r.status == 204) {
      return;
    }
    if (r.status == 404 || r.status == 410) {
      _checkListMissing(r);
      return;
    }
    _fail(r);
  }

  // --------------------------------------------------------- invitaciones

  @override
  Future<InviteTicket> createInvite(SyncCredentials auth) async {
    final r = await send(
      'POST',
      uri('${listPath(auth)}/invites'),
      auth: auth,
      body: const <String, Object?>{},
    );
    if (r.status != 200 && r.status != 201) {
      _fail(r);
    }
    final json = r.json();
    final id = json['inviteId'];
    final expires = _expiry(json['expiresAt']);
    if (id is! String || expires == null) {
      throw const SyncTransportException(
        SyncFailure.protocol,
        'invitación sin inviteId o expiresAt',
      );
    }
    return InviteTicket(inviteId: id, expiresAt: expires);
  }

  static DateTime? _expiry(Object? raw) {
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
    }
    if (raw is String) {
      return DateTime.tryParse(raw)?.toUtc();
    }
    return null;
  }

  @override
  Future<InviteJoinRequest?> getInviteRequest(
    SyncCredentials auth,
    String inviteId,
  ) async {
    final r = await send(
      'GET',
      uri('${listPath(auth)}/invites/$inviteId'),
      auth: auth,
    );
    if (r.status == 404 || r.status == 410) {
      throw const InviteGoneException();
    }
    if (r.status == 204) {
      return null;
    }
    if (r.status != 200) {
      _fail(r);
    }
    final json = r.json();
    final inner = json['request'];
    final map = inner is Map ? Map<String, Object?>.from(inner) : json;
    if (map['publicKey'] is! String) {
      return null;
    }
    final name = map['deviceName'];
    return InviteJoinRequest(
      publicKey: _bytes(map['publicKey'], 'publicKey'),
      deviceName: name is String ? name : '',
    );
  }

  @override
  Future<void> offerInvite(
    SyncCredentials auth,
    String inviteId,
    Uint8List publicKeyA,
  ) async {
    final r = await send(
      'POST',
      uri('${listPath(auth)}/invites/$inviteId/offer'),
      auth: auth,
      body: {'publicKeyA': encodeBase64Url(publicKeyA)},
    );
    if (r.status == 404 || r.status == 410) {
      throw const InviteGoneException();
    }
    if (r.status < 200 || r.status >= 300) {
      _fail(r);
    }
  }

  @override
  Future<void> approveInvite(
    SyncCredentials auth,
    String inviteId,
    InviteApproval approval,
  ) async {
    final r = await send(
      'POST',
      uri('${listPath(auth)}/invites/$inviteId/approve'),
      auth: auth,
      body: {
        'ciphertext': encodeBase64Url(approval.ciphertext),
        'nonce': encodeBase64Url(approval.nonce),
      },
    );
    if (r.status == 404 || r.status == 410) {
      throw const InviteGoneException();
    }
    if (r.status < 200 || r.status >= 300) {
      _fail(r);
    }
  }

  @override
  Future<void> rejectInvite(SyncCredentials auth, String inviteId) async {
    final r = await send(
      'POST',
      uri('${listPath(auth)}/invites/$inviteId/reject'),
      auth: auth,
      body: const <String, Object?>{},
    );
    if (r.status >= 200 && r.status < 300 ||
        r.status == 404 ||
        r.status == 410) {
      return;
    }
    _fail(r);
  }

  @override
  Future<void> requestJoin(
    String inviteId, {
    required Uint8List publicKey,
    required String deviceName,
  }) async {
    final r = await send(
      'POST',
      uri('/v1/invites/$inviteId/join'),
      body: {'publicKey': encodeBase64Url(publicKey), 'deviceName': deviceName},
    );
    if (r.status == 409) {
      throw const InviteTakenException();
    }
    if (r.status == 404 || r.status == 410) {
      throw const InviteGoneException();
    }
    if (r.status < 200 || r.status >= 300) {
      _fail(r);
    }
  }

  @override
  Future<InviteOutcome> pollInviteResult(
    String inviteId, {
    required Uint8List publicKey,
  }) async {
    final r = await send(
      'GET',
      uri('/v1/invites/$inviteId/result'),
      headers: {'X-Public-Key': encodeBase64Url(publicKey)},
    );
    if (r.status == 404 || r.status == 410) {
      return const InviteGone();
    }
    if (r.status == 204) {
      return const InvitePending();
    }
    if (r.status != 200 && r.status != 202) {
      _fail(r);
    }
    final json = r.json();
    if (r.status == 202 || json['ciphertext'] is! String) {
      return InvitePending(
        publicKeyA: json['publicKeyA'] is String
            ? _bytes(json['publicKeyA'], 'publicKeyA')
            : null,
      );
    }
    return InviteApproved(
      InviteApproval(
        ciphertext: _bytes(json['ciphertext'], 'ciphertext'),
        nonce: _bytes(json['nonce'], 'nonce'),
      ),
    );
  }
}

/// Interpreta un mensaje del WebSocket. Devuelve `null` si no se entiende:
/// los mensajes desconocidos se ignoran.
SyncEvent? parseSyncEvent(String message) {
  try {
    final json = jsonDecode(message);
    if (json is! Map) {
      return null;
    }
    switch (json['type']) {
      case 'version':
        final v = json['version'];
        return v is int ? SyncVersionEvent(v) : null;
      case 'join-request':
        return const SyncJoinRequestEvent();
    }
  } on FormatException {
    return null;
  }
  return null;
}
