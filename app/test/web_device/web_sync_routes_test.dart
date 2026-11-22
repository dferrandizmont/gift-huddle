@TestOn('browser')
library;

// Ruta de reserva en el navegador (1.0.6): fetch que falla o no contesta a
// tiempo prueba el segundo host; un estado HTTP no; el WebSocket sigue el
// mismo orden.
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/sync/data/sync_endpoint.dart';
import 'package:regalos/features/sync/data/sync_routes.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';
import 'package:regalos/features/sync/data/web_sync_transport.dart';
import 'package:web/web.dart' as web;

class _Socket {
  _Socket() {
    object['protocol'] = 'gift-huddle.v2'.toJS;
    object['addEventListener'] = ((JSString name, JSFunction listener) {
      listeners[name.toDart] = listener;
    }).toJS;
    object['removeEventListener'] = ((JSString name, JSFunction listener) {
      listeners.remove(name.toDart);
    }).toJS;
    object['close'] = (() {
      closed++;
    }).toJS;
    object['send'] = ((JSAny value) {}).toJS;
  }
  final object = JSObject();
  final listeners = <String, JSFunction>{};
  int closed = 0;
  String? uri;

  void emit(String name, web.Event event) =>
      listeners[name]?.callAsFunction(null, event);
}

/// En [fakeFetch], rechazar la petición (como un fallo de red).
const _reject = -1;

void main() {
  final auth = SyncCredentials(
    listId: 'lista',
    syncId: 'Xfhn06v0kc7dAEsbhsMBlQ',
    authKey: Uint8List(32),
  );
  final window = web.window as JSObject;
  late JSAny? original;
  final hosts = <String>[];
  final requests = <String>[];

  setUp(() {
    original = window['fetch'];
    hosts.clear();
    requests.clear();
  });
  tearDown(() => window['fetch'] = original);

  web.Response json(int status) => web.Response(
    (status == 200
            ? '{"version":3,"envelope":"AQID"}'
            : '{"error":"not_found"}')
        .toJS,
    web.ResponseInit(status: status),
  );

  /// `fetch` falso: [answer] da el estado de cada host; null es no contestar
  /// nunca (solo el aborto lo termina) y [_reject], rechazar.
  void fakeFetch(int? Function(String host) answer, {String? hangOn}) {
    window['fetch'] = ((JSString input, web.RequestInit init) {
      final uri = Uri.parse(input.toDart);
      final host = uri.host;
      hosts.add(host);
      requests.add('${init.method} $host${uri.path}');
      // [hangOn]: el Worker la aplica, pero la respuesta no llega nunca.
      final status = hangOn != null && uri.path.endsWith(hangOn)
          ? null
          : answer(host);
      if (status != null && status != _reject) {
        return Future.value(json(status)).toJS;
      }
      final done = Completer<web.Response>();
      if (status == _reject) {
        done.completeError(StateError('TypeError'));
      } else {
        init.signal?.addEventListener(
          'abort',
          ((web.Event _) {
            if (!done.isCompleted) done.completeError(StateError('AbortError'));
          }).toJS,
        );
      }
      return done.future.toJS;
    }).toJS;
  }

  WebSyncTransport transport({List<_Socket>? sockets}) {
    final endpoint = SyncEndpoint.parse(kDefaultSyncHost)!;
    return WebSyncTransport(
      endpoint,
      routes: SyncRoutes(endpoint.routes),
      timeout: const Duration(milliseconds: 150),
      connectTimeout: const Duration(milliseconds: 50),
      openSocket: (uri, protocols) {
        final socket = _Socket()..uri = uri;
        sockets?.add(socket);
        return socket.object as web.WebSocket;
      },
    );
  }

  test('fetch rechazado en el principal: sale por la reserva y se '
      'recuerda', () async {
    fakeFetch((host) => host == kSyncHosts.first ? _reject : 200);
    final t = transport();
    addTearDown(t.close);
    expect(await t.getList(auth), isA<SyncGetOk>());
    expect(hosts, kSyncHosts);
    expect(t.routes.current, 1);
  });

  test('sin cabecera en el plazo: prueba la reserva', () async {
    fakeFetch((host) => host == kSyncHosts.first ? null : 200);
    final t = transport();
    addTearDown(t.close);
    expect(await t.getList(auth), isA<SyncGetOk>());
    expect(hosts, kSyncHosts);
  });

  test('un 503 o un 404 no prueban la reserva', () async {
    var status = 503;
    fakeFetch((_) => status);
    final t = transport();
    addTearDown(t.close);
    await expectLater(
      t.getList(auth),
      throwsA(
        isA<SyncTransportException>().having(
          (e) => e.failure,
          'failure',
          SyncFailure.server,
        ),
      ),
    );
    status = 404;
    expect(await t.getList(auth), isA<SyncGetNotFound>());
    expect(hosts, [kSyncHosts.first, kSyncHosts.first]);
    expect(t.routes.current, 0);
  });

  test(
    'una mutación (PIN en guards/open) sale una sola vez, por la ruta '
    'que eligió una lectura; si su respuesta no llega, no se repite',
    () async {
      fakeFetch(
        (host) => host == kSyncHosts.first ? _reject : 404,
        hangOn: '/open',
      );
      final t = transport();
      addTearDown(t.close);
      final open = Uri.parse(
        'https://${kSyncHosts.first}/v2/lists/${auth.syncId}/guards/web-1/open',
      );
      await expectLater(
        t.send('POST', open, body: {'pin': '123456'}),
        throwsA(
          isA<SyncTransportException>().having(
            (e) => e.failure,
            'failure',
            SyncFailure.network,
          ),
        ),
      );
      expect(requests, [
        'GET ${kSyncHosts.first}$kSyncRouteProbePath',
        'GET ${kSyncHosts.last}$kSyncRouteProbePath',
        'POST ${kSyncHosts.last}/v2/lists/${auth.syncId}/guards/web-1/open',
      ]);
    },
  );

  test('WebSocket: abre en la ruta que eligió HTTP y un error antes de '
      'abrir no prueba otro host', () async {
    fakeFetch((host) => host == kSyncHosts.first ? _reject : 200);
    final sockets = <_Socket>[];
    final t = transport(sockets: sockets);
    addTearDown(t.close);
    expect(await t.getList(auth), isA<SyncGetOk>());
    final errors = <Object>[];
    final sub = t
        .socketV2(Uri.parse('wss://${kSyncHosts.first}/v2/lists/x/ws'), [
          'gift-huddle.v2',
          'bearer.test',
        ])
        .listen((_) {}, onError: errors.add);
    await Future<void>.delayed(Duration.zero);
    expect(Uri.parse(sockets.single.uri!).host, kSyncHosts.last);
    // Un 401 o un 503 antes de `open` se ve igual que un fallo de red.
    sockets.single.emit('error', web.Event('error'));
    await Future<void>.delayed(Duration.zero);
    expect(sockets, hasLength(1));
    expect(errors.single, isA<SyncTransportException>());
    await sub.cancel();
  });
}
