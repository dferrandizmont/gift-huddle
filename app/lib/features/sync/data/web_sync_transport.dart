import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../domain/sync_keys.dart';
import 'sync_endpoint.dart';
import 'sync_transport.dart';
import 'sync_transport_common.dart';
import 'sync_transport_v2.dart';

/// Fetch omits credentials and rejects redirects. The API authenticates
/// WebSockets exclusively through the bearer subprotocol, never cookies.
class WebSyncTransport extends BaseSyncTransport {
  WebSyncTransport(
    super.endpoint, {
    super.timeout,
    this.openSocket = _openSocket,
  });
  final web.WebSocket Function(String uri, List<String> protocols) openSocket;

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
    final abort = web.AbortController();
    _requests.add(abort);
    Timer? timer;
    void armTimeout() {
      timer?.cancel();
      timer = Timer(timeout, () => abort.abort());
    }

    final h = web.Headers()..set('Accept', 'application/json');
    if (auth != null) {
      h.set('Authorization', 'Bearer ${SyncKeys.bearer(auth.authKey)}');
    }
    headers.forEach((name, value) => h.set(name, value));
    if (body != null) h.set('Content-Type', 'application/json');
    try {
      armTimeout();
      final response = await web.window
          .fetch(
            uri.toString().toJS,
            web.RequestInit(
              method: method,
              headers: h,
              credentials: 'omit',
              redirect: 'manual',
              cache: 'no-store',
              signal: abort.signal,
              body: body == null ? null : jsonEncode(body).toJS,
            ),
          )
          .toDart;
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
    final listeners = <String, JSFunction>{};
    var stopped = false;
    void stop() {
      if (stopped) return;
      stopped = true;
      connectTimer?.cancel();
      ping?.cancel();
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

    events = StreamController<SyncEvent>(
      onListen: () {
        if (_closed) {
          fail();
          return;
        }
        _watches.add(stop);
        try {
          final ws = openSocket(uri.toString(), protocols);
          socket = ws;
          listeners['open'] = ((web.Event _) {
            connectTimer?.cancel();
            if (stopped) return;
            if (ws.protocol != protocols.first) {
              fail();
              return;
            }
            events.add(const SyncOpenEvent());
            ping = Timer.periodic(const Duration(seconds: 30), (_) {
              if (!stopped) ws.send('ping'.toJS);
            });
          }).toJS;
          listeners['message'] = ((web.Event event) {
            if (stopped) return;
            final data = (event as web.MessageEvent).data;
            if (data.isA<JSString>()) {
              final message = (data as JSString).toDart;
              if (utf8.encode(message).length > maxSyncResponseBytes) {
                fail();
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
