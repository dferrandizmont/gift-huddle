@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/features/sync/data/sync_endpoint.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';
import 'package:regalos/features/sync/data/web_sync_transport.dart';
import 'package:regalos/features/web_device/application/web_session_platform_web.dart'
    as browser;
import 'package:regalos/features/web_device/data/vault_pin_web.dart';
import 'package:regalos/features/web_device/application/pending_queue.dart';
import 'package:regalos/features/web_device/application/vault_service.dart';
import 'package:regalos/features/web_device/application/web_sync_engine.dart';
import 'package:regalos/web_probe/main_probe.dart';
import 'package:web/web.dart' as web;

/// Browser-shaped objects exercise the production JS interop boundaries.
class _Locks {
  _Locks() {
    object['request'] =
        ((JSString name, web.LockOptions options, JSFunction callback) {
          requests.add(options);
          final hasSignal = (options as JSObject).has('signal');
          // The actual browser constraint that the old implementation violated.
          if ((options as JSObject).has('ifAvailable') &&
              options.ifAvailable &&
              hasSignal) {
            return Future<JSAny?>.error(StateError('NotSupportedError')).toJS;
          }
          final done = Completer<JSAny?>();
          if (hasSignal) {
            options.signal.addEventListener(
              'abort',
              ((web.Event _) {
                if (!done.isCompleted) {
                  done.completeError(StateError('AbortError'));
                }
              }).toJS,
            );
          }
          Future<void>(() async {
            if (waitGate case final gate?) await gate.future;
            if (done.isCompleted) return;
            final lock = available ? JSObject() : null;
            final held =
                callback.callAsFunction(null, lock) as JSPromise<JSAny?>;
            done.complete(await held.toDart);
          });
          return done.future.toJS;
        }).toJS;
  }
  final object = JSObject();
  final requests = <web.LockOptions>[];
  bool available = true;
  Completer<void>? waitGate;
  web.LockManager get manager => object as web.LockManager;
}

class _Socket {
  _Socket() {
    object['protocol'] = 'gift-huddle.v2'.toJS;
    object['addEventListener'] = ((JSString name, JSFunction listener) {
      listeners[name.toDart] = listener;
    }).toJS;
    object['removeEventListener'] = ((JSString name, JSFunction listener) {
      expect(identical(listeners.remove(name.toDart), listener), isTrue);
      removed++;
    }).toJS;
    object['close'] = (() {
      closed++;
    }).toJS;
    object['send'] = ((JSAny value) {
      sent++;
    }).toJS;
  }
  final object = JSObject();
  final listeners = <String, JSFunction>{};
  int closed = 0, removed = 0, sent = 0;
  String? uri;
  List<String>? protocols;
  web.WebSocket open(String uri, List<String> protocols) {
    this.uri = uri;
    this.protocols = List.of(protocols);
    return object as web.WebSocket;
  }

  void emit(String name, web.Event event) =>
      listeners[name]?.callAsFunction(null, event);
}

// These paths only use auth and sync; plaintext/queue handling is covered by
// web_sync_engine_test. Here we exercise real browser transport timers and
// the engine's reconnect/SyncOpenEvent wiring without asynchronous crypto.
class _UnusedVault implements VaultService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedQueue implements PendingQueue {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HeartbeatEngine extends WebSyncEngine {
  _HeartbeatEngine(WebSyncTransport transport, {super.isVisible})
    : super(
        transport: transport.v2,
        vault: _UnusedVault(),
        queue: _UnusedQueue(),
      );
  int syncs = 0;
  @override
  V2Auth get auth => V2Auth(
    syncId: 'AAAAAAAAAAAAAAAAAAAAAA',
    deviceId: 'test-web',
    credential: Uint8List(32),
  );
  @override
  Future<void> sync() async {
    syncs++;
  }
}

void main() {
  for (final hideAt in [0, 30, 40]) {
    test('hidden at ${hideAt}s suspends pings, deadlines and reconnects', () {
      fakeAsync((time) {
        var visible = true;
        final sockets = <_Socket>[];
        final transport = WebSyncTransport(
          SyncEndpoint.parse('https://example.test')!,
          openSocket: (uri, protocols) {
            final socket = _Socket();
            sockets.add(socket);
            return socket.open(uri, protocols);
          },
        );
        final engine = _HeartbeatEngine(transport, isVisible: () => visible);
        engine.start();
        time.flushMicrotasks();
        sockets.single.emit('open', web.Event('open'));
        time.flushMicrotasks();
        time.elapse(Duration(seconds: hideAt));
        final pings = sockets.single.sent;
        final reads = engine.syncs;
        visible = false;
        engine.suspend();
        time.elapse(const Duration(minutes: 4));
        expect(sockets, hasLength(1));
        expect(sockets.single.sent, pings);
        expect(sockets.single.closed, 1);
        expect(sockets.single.listeners, isEmpty);
        expect(engine.syncs, reads);
        expect(time.nonPeriodicTimerCount + time.periodicTimerCount, 0);
        visible = true;
        engine.resume();
        time.flushMicrotasks();
        expect(sockets, hasLength(2));
        expect(engine.syncs, reads + 1);
        sockets.last.emit('open', web.Event('open'));
        time.flushMicrotasks();
        expect(engine.syncs, reads + 1);
        engine.stop();
        transport.close();
        time.elapse(const Duration(minutes: 2));
        expect(sockets.last.closed, 1);
        expect(time.nonPeriodicTimerCount + time.periodicTimerCount, 0);
      });
    });
  }

  test('consecutive failed socket connections back off 1, 2, 5, 15, 30s', () {
    fakeAsync((time) {
      final sockets = <_Socket>[];
      final transport = WebSyncTransport(
        SyncEndpoint.parse('https://example.test')!,
        openSocket: (uri, protocols) {
          final socket = _Socket();
          sockets.add(socket);
          return socket.open(uri, protocols);
        },
      );
      final engine = _HeartbeatEngine(transport);
      engine.start();
      time.flushMicrotasks();
      for (final seconds in [1, 2, 5, 15, 30, 30]) {
        final attempts = sockets.length;
        sockets.last.emit('error', web.Event('error'));
        time.flushMicrotasks();
        time.elapse(Duration(milliseconds: seconds * 1000 - 1));
        expect(sockets, hasLength(attempts));
        time.elapse(const Duration(milliseconds: 1));
        expect(sockets, hasLength(attempts + 1));
      }
      engine.stop();
      transport.close();
      time.elapse(const Duration(minutes: 2));
      expect(time.nonPeriodicTimerCount + time.periodicTimerCount, 0);
    });
  });

  test('unanswered ping closes, backs off, reopens and syncs on open', () {
    fakeAsync((time) {
      final sockets = <_Socket>[];
      final transport = WebSyncTransport(
        SyncEndpoint.parse('https://example.test')!,
        openSocket: (uri, protocols) {
          final socket = _Socket();
          sockets.add(socket);
          return socket.open(uri, protocols);
        },
      );
      final engine = _HeartbeatEngine(transport);
      engine.start();
      time.flushMicrotasks();
      sockets.single.emit('open', web.Event('open'));
      time.flushMicrotasks();
      final initial = engine.syncs;
      expect(initial, 2); // Startup and SyncOpenEvent.
      time.elapse(const Duration(seconds: 30));
      expect(sockets.single.sent, 1);
      time.elapse(const Duration(seconds: 9));
      expect(sockets.single.closed, 0);
      time.elapse(const Duration(seconds: 1));
      expect(sockets.single.closed, 1);
      expect(sockets.single.listeners, isEmpty);
      expect(engine.activity, WebSyncActivity.offline);
      time.elapse(const Duration(milliseconds: 999));
      expect(sockets, hasLength(1));
      time.elapse(const Duration(milliseconds: 1));
      expect(sockets, hasLength(2));
      sockets.last.emit('open', web.Event('open'));
      time.flushMicrotasks();
      expect(engine.syncs, initial + 1);
      expect(engine.activity, WebSyncActivity.idle);
      // Stop with another ping deadline outstanding.
      time.elapse(const Duration(seconds: 30));
      engine.stop();
      transport.close();
      time.elapse(const Duration(minutes: 2));
      expect(sockets, hasLength(2));
      expect(sockets.last.closed, 1);
      expect(time.nonPeriodicTimerCount + time.periodicTimerCount, 0);
    });
  });

  for (final message in ['pong', '{"type":"future-message"}']) {
    test('inbound $message answers ping without announcing a change', () {
      fakeAsync((time) {
        final socket = _Socket();
        final transport = WebSyncTransport(
          SyncEndpoint.parse('https://example.test')!,
          openSocket: socket.open,
        );
        final events = <SyncEvent>[];
        final errors = <Object>[];
        final sub = transport
            .socketV2(Uri.parse('wss://example.test/ws'), [
              'gift-huddle.v2',
              'bearer.test',
            ])
            .listen(events.add, onError: errors.add);
        socket.emit('open', web.Event('open'));
        time.flushMicrotasks();
        for (var i = 0; i < 3; i++) {
          time.elapse(Duration(seconds: i == 0 ? 39 : 30));
          socket.emit(
            'message',
            web.MessageEvent(
              'message',
              web.MessageEventInit(data: message.toJS),
            ),
          );
          time.flushMicrotasks();
          expect(socket.closed, 0);
        }
        expect(socket.sent, 3);
        expect(events.whereType<SyncVersionEvent>(), isEmpty);
        expect(
          events.whereType<SyncAliveEvent>(),
          hasLength(message == 'pong' ? 3 : 0),
        );
        expect(errors, isEmpty);
        sub.cancel();
        transport.close();
        time.elapse(const Duration(minutes: 2));
        expect(socket.closed, 1);
        expect(time.nonPeriodicTimerCount + time.periodicTimerCount, 0);
      });
    });
  }

  test(
    'NFC uses browser normalization and probe matches Unicode vector A',
    () async {
      expect(normalizeNfc('Cafe\u0301 Nora'), 'Café Nora');
      expect(normalizeNfc('\u1100\u1161\u11a8'), '\uac01');
      expect(normalizeNfc('a\u0315\u0300'), 'à\u0315');
      expect(normalizeNfc('\u0344'), '\u0308\u0301');
      final probe = BrowserProbe();
      await probe.checkVaultNfcVector();
      expect(probe.lines.single, contains('matches vector A'));
      probe.dispose();
    },
  );

  test('Web Locks immediate options omit signal; exclusive lease lasts until release', () async {
    final locks = _Locks();
    final platform = browser.createSessionPlatform(
      'test-immediate',
      locks: locks.manager,
    );
    final lease = await platform.acquire(wait: false);
    expect(lease, isNotNull);
    expect(locks.requests.single.ifAvailable, isTrue);
    expect((locks.requests.single as JSObject).has('signal'), isFalse);
    await lease!.release();
    locks.available = false;
    expect(await platform.acquire(wait: false), isNull);
    await platform.dispose();
  });

  test('Web Locks queued options omit ifAvailable and disposal aborts waiting request', () async {
    final locks = _Locks()..waitGate = Completer<void>();
    final platform = browser.createSessionPlatform(
      'test-wait',
      locks: locks.manager,
    );
    var acquired = false;
    final acquiring = platform.acquire(wait: true).then((lease) {
      acquired = true;
      return lease;
    });
    await Future<void>.delayed(Duration.zero);
    expect(acquired, isFalse);
    expect((locks.requests.single as JSObject).has('ifAvailable'), isFalse);
    expect(locks.requests.single.signal, isNotNull);
    locks.waitGate!.complete();
    final lease = await acquiring;
    await lease!.release();
    locks.waitGate = Completer<void>();
    final rejected = expectLater(
      platform.acquire(wait: true),
      throwsStateError,
    );
    await platform.dispose();
    await rejected;
    locks.waitGate!.complete();
  });

  for (final code in [4401, 4404]) {
    test(
      'socketV2 negotiates protocols and maps close $code, removing all listeners',
      () async {
        final socket = _Socket();
        final transport = WebSyncTransport(
          SyncEndpoint.parse('https://example.test')!,
          openSocket: socket.open,
        );
        final auth = V2Auth(
          syncId: 'AAAAAAAAAAAAAAAAAAAAAA',
          deviceId: 'bbbbbbbbbb',
          credential: Uint8List(32),
        );
        final events = <SyncEvent>[];
        final done = Completer<void>();
        transport.v2.watch(auth).listen(events.add, onDone: done.complete);
        expect(socket.protocols, [
          'gift-huddle.v2',
          'bearer.${encodeBase64Url(auth.credential)}',
        ]);
        expect(
          socket.uri,
          'wss://example.test/v2/lists/AAAAAAAAAAAAAAAAAAAAAA/ws',
        );
        expect(socket.uri, isNot(contains(encodeBase64Url(auth.credential))));
        socket.emit('open', web.Event('open'));
        socket.emit(
          'message',
          web.MessageEvent(
            'message',
            web.MessageEventInit(data: '{"type":"version","version":7}'.toJS),
          ),
        );
        socket.emit(
          'close',
          web.CloseEvent('close', web.CloseEventInit(code: code)),
        );
        await done.future;
        expect(events.first, isA<SyncOpenEvent>());
        expect(events.whereType<SyncVersionEvent>().single.version, 7);
        expect(
          events.last,
          code == 4401 ? isA<SyncRevokedEvent>() : isA<SyncGoneEvent>(),
        );
        expect(socket.listeners, isEmpty);
        expect(socket.removed, 4);
        expect(socket.closed, 1);
        transport.close();
      },
    );
  }

  for (final connected in [false, true]) {
    test(
      'socketV2 cancellation while connected=$connected removes listeners and timers',
      () async {
        final socket = _Socket();
        final transport = WebSyncTransport(
          SyncEndpoint.parse('https://example.test')!,
          timeout: const Duration(milliseconds: 20),
          openSocket: socket.open,
        );
        final events = <SyncEvent>[];
        final errors = <Object>[];
        final subscription = transport
            .socketV2(Uri.parse('wss://example.test/ws'), [
              'gift-huddle.v2',
              'bearer.test',
            ])
            .listen(events.add, onError: errors.add);
        final lateMessage = socket.listeners['message']!;
        if (connected) socket.emit('open', web.Event('open'));
        await Future<void>.delayed(Duration.zero);
        final delivered = events.length;
        await subscription.cancel();
        lateMessage.callAsFunction(
          null,
          web.MessageEvent(
            'message',
            web.MessageEventInit(data: '{"type":"version","version":8}'.toJS),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(events, hasLength(delivered));
        expect(errors, isEmpty);
        expect(socket.listeners, isEmpty);
        expect(socket.closed, 1);
        expect(socket.removed, 4);
        expect(socket.sent, 0);
        transport.close();
      },
    );
  }

  test(
    'socketV2 rejects a different negotiated protocol and cleans up',
    () async {
      final socket = _Socket()..object['protocol'] = 'gift-huddle.v1'.toJS;
      final transport = WebSyncTransport(
        SyncEndpoint.parse('https://example.test')!,
        openSocket: socket.open,
      );
      final result = expectLater(
        transport.socketV2(Uri.parse('wss://example.test/ws'), [
          'gift-huddle.v2',
          'bearer.test',
        ]),
        emitsInOrder([emitsError(isA<SyncTransportException>()), emitsDone]),
      );
      socket.emit('open', web.Event('open'));
      await result;
      expect(socket.listeners, isEmpty);
      expect(socket.closed, 1);
      transport.close();
    },
  );
}
