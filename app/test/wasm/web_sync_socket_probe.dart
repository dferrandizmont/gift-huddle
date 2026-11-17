// ignore_for_file: avoid_print
// Standalone wasm check of the production WebSocket interop (no Flutter).
// Both commands, from app/:
// dart compile wasm -O4 test/wasm/web_sync_socket_probe.dart
//   -o <temporary directory>/probe.wasm
// Then: node test/wasm/run_sync_socket_probe.mjs <temporary directory>
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:web/web.dart' as web;

import 'package:regalos/features/sync/data/sync_endpoint.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';
import 'package:regalos/features/sync/data/web_sync_transport.dart';

@JS('PROBE_SOCKET_BASE')
external JSString get _base;

class _Socket {
  _Socket() {
    object['protocol'] = 'gift-huddle.v2'.toJS;
    object['addEventListener'] = ((JSString name, JSFunction listener) {
      listeners[name.toDart] = listener;
    }).toJS;
    object['removeEventListener'] = ((JSString name, JSFunction listener) {
      listeners.remove(name.toDart);
    }).toJS;
    object['send'] = ((JSString message) {
      _require(message.toDart == 'ping', 'unexpected outbound message');
      pings++;
    }).toJS;
    object['close'] = (() {
      closed++;
    }).toJS;
  }
  final object = JSObject();
  final listeners = <String, JSFunction>{};
  int pings = 0, closed = 0;
  void emit(String name, [JSObject? event]) =>
      listeners[name]?.callAsFunction(null, event ?? JSObject());
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

// Runs the production interop and its timers under optimized wasm, without a
// Flutter/browser test harness or wall-clock waits.
void _checkHeartbeat() {
  for (final reply in [null, 'pong', '{"type":"future-message"}']) {
    fakeAsync((time) {
      final socket = _Socket();
      final transport = WebSyncTransport(
        SyncEndpoint.parse('https://example.test')!,
        openSocket: (_, _) => socket.object as web.WebSocket,
      );
      final events = <SyncEvent>[];
      final errors = <Object>[];
      var done = false;
      final sub = transport
          .socketV2(Uri.parse('wss://example.test/ws'), [
            'gift-huddle.v2',
            'bearer.test',
          ])
          .listen(
            events.add,
            onError: errors.add,
            onDone: () {
              done = true;
            },
          );
      socket.emit('open');
      time.flushMicrotasks();
      time.elapse(const Duration(seconds: 30));
      _require(socket.pings == 1, 'ping must wait 30 seconds');
      time.elapse(const Duration(seconds: 9));
      _require(socket.closed == 0, 'socket closed before reply deadline');
      if (reply != null) {
        socket.emit('message', JSObject()..['data'] = reply.toJS);
      }
      time.elapse(const Duration(seconds: 1));
      if (reply == null) {
        _require(socket.closed == 1 && done, 'unanswered ping did not close');
        _require(
          errors.length == 1 && errors.single is SyncTransportException,
          'unanswered ping did not report network failure',
        );
      } else {
        _require(
          socket.closed == 0 && errors.isEmpty,
          'reply did not keep socket alive',
        );
        _require(
          events.whereType<SyncVersionEvent>().isEmpty,
          'reply counted as change',
        );
        _require(
          events.whereType<SyncAliveEvent>().length ==
              (reply == 'pong' ? 1 : 0),
          'pong liveness event missing',
        );
        // Cancel with a second ping deadline pending.
        time.elapse(const Duration(seconds: 20));
        _require(socket.pings == 2, 'second ping missing');
      }
      sub.cancel();
      transport.close();
      time.elapse(const Duration(minutes: 2));
      _require(
        socket.closed == 1 && socket.listeners.isEmpty,
        'socket cleanup failed',
      );
      _require(
        time.nonPeriodicTimerCount + time.periodicTimerCount == 0,
        'heartbeat timers survived cancellation',
      );
    });
  }
  print('PROBE HEARTBEAT ok=3 fail=0');
}

Future<void> main() async {
  _checkHeartbeat();
  final transport = WebSyncTransport(SyncEndpoint.parse(_base.toDart)!);
  final events = <SyncEvent>[];
  final done = Completer<void>();
  final sub = transport.v2
      .watch(
        V2Auth(
          syncId: 'AAAAAAAAAAAAAAAAAAAAAA',
          deviceId: 'test-web',
          credential: Uint8List(32),
        ),
      )
      .listen((event) {
        events.add(event);
        print(
          event is SyncVersionEvent
              ? 'PROBE VERSION ${event.version}'
              : event is SyncAliveEvent
              ? 'PROBE ALIVE'
              : 'PROBE OPEN',
        );
        if (event is SyncVersionEvent && event.version == 8) done.complete();
      }, onError: done.completeError);
  try {
    await done.future.timeout(const Duration(seconds: 5));
    if (events.first is! SyncOpenEvent ||
        events.whereType<SyncAliveEvent>().length != 1 ||
        events.whereType<SyncVersionEvent>().map((e) => e.version).join(',') !=
            '7,8') {
      throw StateError('unexpected socket events');
    }
    final closed = Completer<void>();
    final errors = <Object>[];
    final rejected = transport
        .socketV2(Uri.parse('${_base.toDart}/wrong-protocol'), [
          'gift-huddle.v2',
          'gift-huddle.v1',
        ])
        .listen(
          (_) => throw StateError('accepted the wrong protocol'),
          onError: errors.add,
          onDone: closed.complete,
        );
    try {
      await closed.future.timeout(const Duration(seconds: 5));
      if (errors.length != 1 || errors.single is! SyncTransportException) {
        throw StateError('protocol failure did not close the stream');
      }
    } finally {
      await rejected.cancel();
    }
    print('PROBE DONE ok=5 fail=0');
  } finally {
    await sub.cancel();
    transport.close();
  }
}
