import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../domain/sync_keys.dart';
import 'sync_endpoint.dart';
import 'sync_transport.dart';
import 'sync_transport_common.dart';
import 'sync_transport_v2.dart';
export 'sync_endpoint.dart';
export 'sync_transport_common.dart' show parseSyncEvent;

/// [SyncTransport] sobre `HttpClient` y `WebSocket` de `dart:io`.
class HttpSyncTransport extends BaseSyncTransport {
  /// Crea el cliente hacia [endpoint].
  HttpSyncTransport(super.endpoint, {HttpClient? client, super.timeout})
    : _client = client ?? HttpClient() {
    _client.connectionTimeout = timeout;
    _client.userAgent = 'GiftHuddle';
  }

  final HttpClient _client;

  @override
  Future<SyncResponse> send(
    String method,
    Uri uri, {
    SyncCredentials? auth,
    Object? body,
    Map<String, String> headers = const {},
  }) async {
    try {
      final request = await _client.openUrl(method, uri).timeout(timeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (auth != null) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${SyncKeys.bearer(auth.authKey)}',
        );
      }
      headers.forEach(request.headers.set);
      if (body != null) {
        final bytes = utf8.encode(jsonEncode(body));
        request.headers.contentType = ContentType.json;
        request.contentLength = bytes.length;
        request.add(bytes);
      }
      final response = await request.close().timeout(timeout);
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
        (name, values) =>
            responseHeaders[name.toLowerCase()] = values.join(', '),
      );
      return SyncResponse(
        response.statusCode,
        responseHeaders,
        builder.takeBytes(),
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
      socket = await _connectWebSocket(uri, protocols).timeout(timeout);
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
  Future<WebSocket> _connectWebSocket(Uri uri, List<String> protocols) async {
    final random = Random.secure();
    final nonce = base64.encode(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
    final request = await _client.openUrl(
      'GET',
      uri.replace(scheme: uri.scheme == 'wss' ? 'https' : 'http'),
    );
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
