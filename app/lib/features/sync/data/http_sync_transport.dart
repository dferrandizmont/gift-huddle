import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../domain/sync_keys.dart';
import 'sync_endpoint.dart';
import 'sync_routes.dart';
import 'sync_transport.dart';
import 'sync_transport_common.dart';
import 'sync_transport_v2.dart';
export 'sync_endpoint.dart';
export 'sync_transport_common.dart' show parseSyncEvent;

/// [SyncTransport] sobre `HttpClient` y `WebSocket` de `dart:io`.
///
/// Cada petición y cada WebSocket prueban los hosts de [routes] en orden:
/// si no se puede conectar con uno en [connectTimeout] (o se corta, o falla
/// TLS) se prueba el siguiente; un estado HTTP nunca cambia de host.
class HttpSyncTransport extends BaseSyncTransport {
  /// Crea el cliente hacia [endpoint].
  HttpSyncTransport(
    super.endpoint, {
    HttpClient? client,
    super.timeout,
    super.routes,
    this.connectTimeout = kSyncConnectTimeout,
    this.largeBodyTimeout = const Duration(seconds: 30),
  }) : _client = client ?? HttpClient() {
    _client.connectionTimeout = connectTimeout;
    _client.userAgent = 'GiftHuddle';
  }

  final HttpClient _client;

  /// Tiempo para conectar con cada host (TCP y TLS).
  final Duration connectTimeout;

  /// Espera de la respuesta tras subir un cuerpo de más de [largeBodyBytes]
  /// (en bytes UTF-8): 30 s, como pide el plan para lo que lleva slots.
  final Duration largeBodyTimeout;

  /// Bytes de un cuerpo que se considera grande.
  static const int largeBodyBytes = 64 * 1024;

  /// Abre la conexión con [target]. Lo que falla aquí (nada se ha enviado
  /// todavía) es [SyncRouteConnectFailure]: se puede probar otro host.
  Future<HttpClientRequest> _open(String method, Uri target) async {
    final pending = _client.openUrl(method, target);
    try {
      return await pending.timeout(connectTimeout);
    } on TimeoutException {
      // Si al final conecta, se suelta sin enviar nada.
      unawaited(pending.then((r) => r.abort(), onError: (Object _) {}));
      throw const SyncRouteConnectFailure('tiempo de conexión agotado');
    } on SocketException catch (e) {
      throw SyncRouteConnectFailure(e.message);
    } on TlsException {
      throw const SyncRouteConnectFailure('fallo de TLS');
    } on HttpException catch (e) {
      throw SyncRouteConnectFailure(e.message);
    }
  }

  @override
  Future<SyncResponse> send(
    String method,
    Uri uri, {
    SyncCredentials? auth,
    Object? body,
    Map<String, String> headers = const {},
  }) async {
    try {
      return await routes.run(
        uri,
        (target, connected) =>
            _send(method, target, connected, auth, body, headers),
      );
    } on SyncTransportException {
      rethrow;
    } on TimeoutException {
      throw const SyncTransportException(SyncFailure.network, 'tiempo agotado');
    } on SocketException catch (e) {
      throw SyncTransportException(SyncFailure.network, e.message);
    } on HandshakeException {
      throw const SyncTransportException(SyncFailure.network, 'fallo de TLS');
    } on HttpException catch (e) {
      throw SyncTransportException(SyncFailure.network, e.message);
    }
  }

  Future<SyncResponse> _send(
    String method,
    Uri uri,
    void Function() connected,
    SyncCredentials? auth,
    Object? body,
    Map<String, String> headers,
  ) async {
    final request = await _open(method, uri);
    connected();
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (auth != null) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${SyncKeys.bearer(auth.authKey)}',
      );
    }
    headers.forEach(request.headers.set);
    var wait = timeout;
    if (body != null) {
      final bytes = utf8.encode(jsonEncode(body));
      request.headers.contentType = ContentType.json;
      request.contentLength = bytes.length;
      request.add(bytes);
      // Una subida grande (slots) puede tardar más en salir por datos móviles.
      if (bytes.length > largeBodyBytes) wait = largeBodyTimeout;
    }
    final response = await request.close().timeout(wait);
    final builder = BytesBuilder(copy: false);
    var size = 0;
    await for (final chunk in response.timeout(timeout)) {
      size += chunk.length;
      if (size > maxSyncResponseBytes) {
        throw const SyncTransportException(
          SyncFailure.protocol,
          'respuesta demasiado grande',
        );
      }
      builder.add(chunk);
    }
    final responseHeaders = <String, String>{};
    response.headers.forEach(
      (name, values) => responseHeaders[name.toLowerCase()] = values.join(', '),
    );
    return SyncResponse(
      response.statusCode,
      responseHeaders,
      builder.takeBytes(),
    );
  }

  @override
  Stream<SyncEvent> watch(SyncCredentials auth) {
    final base = endpoint.base;
    final uri = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '${listPath(auth)}/ws',
    );
    return _events(uri, [
      'gift-huddle.v1',
      'bearer.${SyncKeys.bearer(auth.authKey)}',
    ], parseSyncEvent);
  }

  @override
  Stream<SyncEvent> socketV2(Uri uri, List<String> protocols) =>
      _events(uri, protocols, parseSyncEventV2);

  /// Abre el WebSocket [uri] con [protocols]: da [SyncOpenEvent] al conectar,
  /// los mensajes que entiende [parse] y, al cerrarse, [SyncGoneEvent] (4404)
  /// o [SyncRevokedEvent] (4401).
  Stream<SyncEvent> _events(
    Uri uri,
    List<String> protocols,
    SyncEvent? Function(String) parse,
  ) async* {
    final WebSocket socket;
    try {
      socket = await routes
          .run(
            uri,
            (target, connected) =>
                _connectWebSocket(target, protocols, connected),
          )
          .timeout(timeout);
    } on SyncTransportException {
      rethrow;
    } on TimeoutException {
      throw const SyncTransportException(SyncFailure.network, 'tiempo agotado');
    } on SocketException catch (e) {
      throw SyncTransportException(SyncFailure.network, e.message);
    } on WebSocketException catch (e) {
      throw SyncTransportException(
        e.message.contains('401')
            ? SyncFailure.unauthorized
            : SyncFailure.network,
        e.message,
      );
    } on HandshakeException {
      throw const SyncTransportException(SyncFailure.network, 'fallo de TLS');
    } on HttpException catch (e) {
      throw SyncTransportException(SyncFailure.network, e.message);
    }
    socket.pingInterval = const Duration(seconds: 30);
    try {
      yield const SyncOpenEvent();
      await for (final message in socket) {
        if (message is! String) {
          continue;
        }
        final event = parse(message);
        if (event != null) {
          yield event;
        }
      }
      if (socket.closeCode == kWsClosedGone) {
        yield const SyncGoneEvent();
      } else if (socket.closeCode == 4410 &&
          socket.closeReason == 'credential_replaced') {
        yield const SyncTransferredEvent();
      } else if (socket.closeCode == kWsClosedRevoked) {
        yield const SyncRevokedEvent();
      }
    } on WebSocketException catch (e) {
      throw SyncTransportException(SyncFailure.network, e.message);
    } finally {
      await socket.close();
    }
  }

  /// Saludo WebSocket hecho a mano para poder desactivar las redirecciones.
  ///
  /// `WebSocket.connect` de `dart:io` sigue hasta cinco y copia el
  /// subprotocolo `bearer.<authKey>` al destino, aunque sea otro host o
  /// `http`. Aquí cualquier respuesta que no sea `101` (3xx incluido) es un
  /// fallo y la clave no sale hacia ningún otro sitio.
  ///
  /// Con los mismos hosts y el mismo orden que las peticiones: solo un
  /// fallo al conectar ([_open]) prueba el siguiente.
  Future<WebSocket> _connectWebSocket(
    Uri uri,
    List<String> protocols,
    void Function() connected,
  ) async {
    final random = Random.secure();
    final nonce = base64.encode(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
    final request = await _open(
      'GET',
      uri.replace(scheme: uri.scheme == 'wss' ? 'https' : 'http'),
    );
    connected();
    request.followRedirects = false;
    request.headers
      ..set(HttpHeaders.connectionHeader, 'Upgrade')
      ..set(HttpHeaders.upgradeHeader, 'websocket')
      ..set('Sec-WebSocket-Key', nonce)
      ..set('Sec-WebSocket-Version', '13')
      ..set('Sec-WebSocket-Protocol', protocols.join(', '))
      ..set(HttpHeaders.cacheControlHeader, 'no-cache');
    final response = await request.close();
    if (response.statusCode != HttpStatus.switchingProtocols) {
      // No se sigue ni se lee nada más: se corta la conexión.
      final status = response.statusCode;
      (await response.detachSocket()).destroy();
      throw WebSocketException(
        "Connection to '$uri' was not upgraded to websocket, "
        'HTTP status code: $status',
      );
    }
    final accept = (await Sha1().hash(
      utf8.encode('${nonce}258EAFA5-E914-47DA-95CA-C5AB0DC85B11'),
    )).bytes;
    final upgrade = response.headers.value(HttpHeaders.upgradeHeader);
    final connection = response.headers.value(HttpHeaders.connectionHeader);
    final protocol = response.headers.value('Sec-WebSocket-Protocol');
    final socket = await response.detachSocket();
    if (upgrade == null ||
        upgrade.toLowerCase() != 'websocket' ||
        connection == null ||
        !connection.toLowerCase().contains('upgrade') ||
        response.headers.value('Sec-WebSocket-Accept') !=
            base64.encode(accept) ||
        (protocol != null && !protocols.contains(protocol))) {
      socket.destroy();
      throw WebSocketException(
        "Connection to '$uri' was not upgraded to websocket",
      );
    }
    return WebSocket.fromUpgradedSocket(
      socket,
      protocol: protocol,
      serverSide: false,
    );
  }

  @override
  void close() => _client.close(force: true);
}

BaseSyncTransport createSyncTransport(SyncEndpoint endpoint) =>
    HttpSyncTransport(endpoint);
