import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../domain/sync_keys.dart';
import 'sync_endpoint.dart';
import 'sync_routes.dart';
import 'sync_transport.dart';
import 'sync_transport_common.dart';
import 'sync_transport_v2.dart';

/// Fetch omits credentials and rejects redirects. The API authenticates
/// WebSockets exclusively through the bearer subprotocol, never cookies.
///
/// Hosts ([routes], 1.0.6): a browser has no connect timeout and does not
/// say why a fetch failed, and a fetch that times out may already have been
/// applied by the Worker. So only reads (GET) try the next host, when the
/// fetch is rejected or has no response headers within [connectTimeout]. A
/// mutation is sent once, to the route a safe read chose
/// ([SyncRoutes.runOnce]): never repeated on the other host. The WebSocket
/// opens on that same route. An HTTP status never changes the route.
class WebSyncTransport extends BaseSyncTransport {
  WebSyncTransport(
    super.endpoint, {
    super.timeout,
    super.routes,
    this.connectTimeout = kWebConnectTimeout,
    this.largeBodyTimeout = const Duration(seconds: 30),
    this.openSocket = _openSocket,
  });
  final web.WebSocket Function(String uri, List<String> protocols) openSocket;

  /// Wait for the response headers of a read before trying the next host.
  final Duration connectTimeout;

  /// Wait for the response headers of a request with a body over
  /// [quickBodyBytes]: the upload itself may take that long on a slow link.
  final Duration largeBodyTimeout;

  /// UTF-8 bytes of a body that counts as large.
  static const int quickBodyBytes = 64 * 1024;

  static web.WebSocket _openSocket(String uri, List<String> protocols) =>
      web.WebSocket(uri, protocols.map((s) => s.toJS).toList().toJS);
  final _requests = <web.AbortController>{};
  final _watches = <void Function()>{};
  bool _closed = false;

  @override
  Future<SyncResponse> send(
    String method,
    Uri uri, {
    SyncCredentials? auth,
    Object? body,
    Map<String, String> headers = const {},
  }) async {
    if (_closed) {
      throw const SyncTransportException(
        SyncFailure.network,
        'cliente cerrado',
      );
    }
    final text = body == null ? null : jsonEncode(body);
    final large = text != null && utf8.encode(text).length > quickBodyBytes;
    final read = method == 'GET' || method == 'HEAD';
    if (read) {
      return routes.run(
        uri,
        (target, connected) => _send(
          method,
          target,
          connected,
          auth,
          text,
          headers,
          connectTimeout,
        ),
      );
    }
    return routes.runOnce(
      uri,
      probe: (target, connected) =>
          _send('GET', target, connected, null, null, const {}, connectTimeout),
      attempt: (target, connected) => _send(
        method,
        target,
        connected,
        auth,
        text,
        headers,
        large ? largeBodyTimeout : timeout,
      ),
    );
  }

  Future<SyncResponse> _send(
    String method,
    Uri uri,
    void Function() connected,
    SyncCredentials? auth,
    String? body,
    Map<String, String> headers,
    Duration headersWithin,
  ) async {
    final abort = web.AbortController();
    _requests.add(abort);
    Timer? timer;
    void armTimeout([Duration? wait]) {
      timer?.cancel();
      timer = Timer(wait ?? timeout, () => abort.abort());
    }

    final h = web.Headers()..set('Accept', 'application/json');
    if (auth != null) {
      h.set('Authorization', 'Bearer ${SyncKeys.bearer(auth.authKey)}');
    }
    headers.forEach((name, value) => h.set(name, value));
    if (body != null) h.set('Content-Type', 'application/json');
    try {
      armTimeout(headersWithin);
      final web.Response response;
      try {
        response = await web.window
            .fetch(
              uri.toString().toJS,
              web.RequestInit(
                method: method,
                headers: h,
                credentials: 'omit',
                redirect: 'manual',
                cache: 'no-store',
                signal: abort.signal,
                body: body?.toJS,
              ),
            )
            .toDart;
      } catch (_) {
        if (_closed) {
          throw const SyncTransportException(
            SyncFailure.network,
            'petición cancelada',
          );
        }
        // Rejected or no headers in time: a read tries the next host, a
        // mutation fails without being repeated (`SyncRoutes.runOnce`).
        throw const SyncRouteConnectFailure('fallo de red');
      }
      connected();
      final builder = BytesBuilder(copy: false);
      var size = 0;
      final stream = response.body;
      if (stream != null) {
        final reader = stream.getReader() as web.ReadableStreamDefaultReader;
        try {
          while (true) {
            armTimeout();
            final chunk = await reader.read().toDart;
            if (chunk.done) break;
            final bytes = (chunk.value as JSUint8Array).toDart;
            size += bytes.length;
            if (size > maxSyncResponseBytes) {
              abort.abort();
              throw const SyncTransportException(
                SyncFailure.protocol,
                'respuesta demasiado grande',
              );
            }
            builder.add(bytes);
          }
        } finally {
          reader.releaseLock();
        }
      }
      if (_closed || abort.signal.aborted) {
        throw const SyncTransportException(
          SyncFailure.network,
          'petición cancelada',
        );
      }
      return SyncResponse(response.status, {
        for (final name in ['retry-after', 'etag'])
          if (response.headers.get(name) case final String value) name: value,
      }, builder.takeBytes());
    } on SyncTransportException {
      rethrow;
    } on SyncRouteConnectFailure {
      rethrow;
    } catch (_) {
      throw const SyncTransportException(SyncFailure.network, 'fallo de red');
    } finally {
      timer?.cancel();
      _requests.remove(abort);
    }
  }

  @override
  Stream<SyncEvent> watch(SyncCredentials auth) {
    final base = endpoint.base;
    return _events(
      base.replace(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        path: '${listPath(auth)}/ws',
      ),
      ['gift-huddle.v1', 'bearer.${SyncKeys.bearer(auth.authKey)}'],
      parseSyncEvent,
    );
  }

  @override
  Stream<SyncEvent> socketV2(Uri uri, List<String> protocols) =>
      _events(uri, protocols, parseSyncEventV2);

  Stream<SyncEvent> _events(
    Uri uri,
    List<String> protocols,
    SyncEvent? Function(String) parse,
  ) {
    late StreamController<SyncEvent> events;
    web.WebSocket? socket;
    Timer? connectTimer;
    Timer? ping;
    Timer? pongDeadline;
    final listeners = <String, JSFunction>{};
    var stopped = false;
    void stop() {
      if (stopped) return;
      stopped = true;
      connectTimer?.cancel();
      ping?.cancel();
      pongDeadline?.cancel();
      final ws = socket;
      if (ws != null) {
        listeners.forEach(
          (name, listener) => ws.removeEventListener(name, listener),
        );
        ws.close();
      }
      _watches.remove(stop);
      unawaited(events.close());
    }

    void fail() {
      if (stopped) return;
      events.addError(
        const SyncTransportException(SyncFailure.network, 'fallo de WebSocket'),
      );
      stop();
    }

    // The route the HTTP requests chose ([SyncRoutes.current]). Before `open`
    // the browser reports a 401, a 403 or a 503 exactly like a network
    // failure, so the socket never picks a host by itself: the requests and
    // the existing polling do, and the next reconnect follows them.
    final (index, target) = routes.targets(uri).first;

    void connect() {
      try {
        final ws = openSocket(target.toString(), protocols);
        socket = ws;
        listeners['open'] = ((web.Event _) {
          connectTimer?.cancel();
          if (stopped) return;
          if (ws.protocol != protocols.first) {
            fail();
            return;
          }
          routes.markConnected(index);
          events.add(const SyncOpenEvent());
          ping = Timer.periodic(const Duration(seconds: 30), (_) {
            if (stopped) return;
            pongDeadline = Timer(const Duration(seconds: 10), fail);
            try {
              ws.send('ping'.toJS);
            } catch (_) {
              fail();
            }
          });
        }).toJS;
        listeners['message'] = ((web.Event event) {
          if (stopped) return;
          // Any inbound message proves that the connection still works.
          pongDeadline?.cancel();
          pongDeadline = null;
          final data = (event as web.MessageEvent).data;
          if (data.isA<JSString>()) {
            final message = (data as JSString).toDart;
            if (utf8.encode(message).length > maxSyncResponseBytes) {
              fail();
              return;
            }
            if (message == 'pong') {
              events.add(const SyncAliveEvent());
              return;
            }
            final parsed = parse(message);
            if (parsed != null) events.add(parsed);
          }
        }).toJS;
        listeners['error'] = ((web.Event _) {
          fail();
        }).toJS;
        listeners['close'] = ((web.Event event) {
          if (stopped) return;
          final code = (event as web.CloseEvent).code;
          if (code == kWsClosedGone) {
            events.add(const SyncGoneEvent());
          } else if (code == 4410 && event.reason == 'credential_replaced') {
            events.add(const SyncTransferredEvent());
          } else if (code == kWsClosedRevoked) {
            events.add(const SyncRevokedEvent());
          }
          stop();
        }).toJS;
        listeners.forEach(
          (name, listener) => ws.addEventListener(name, listener),
        );
        connectTimer = Timer(timeout, fail);
      } catch (_) {
        fail();
      }
    }

    events = StreamController<SyncEvent>(
      onListen: () {
        if (_closed) {
          fail();
          return;
        }
        _watches.add(stop);
        connect();
      },
      onCancel: stop,
    );
    return events.stream;
  }

  @override
  void close() {
    _closed = true;
    for (final abort in _requests.toList()) {
      abort.abort();
    }
    for (final stop in _watches.toList()) {
      stop();
    }
  }
}

BaseSyncTransport createSyncTransport(SyncEndpoint endpoint) =>
    WebSyncTransport(endpoint);
