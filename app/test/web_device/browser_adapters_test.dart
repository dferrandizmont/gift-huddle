@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/features/sync/data/sync_endpoint.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';
import 'package:regalos/features/sync/data/web_sync_transport.dart';
import 'package:regalos/features/web_device/application/web_session_platform_web.dart'
    as browser;
import 'package:regalos/features/web_device/data/vault_pin_web.dart';
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

void main() {
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
