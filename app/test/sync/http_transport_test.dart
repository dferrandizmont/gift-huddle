import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/features/sync/data/http_sync_transport.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';

/// Lo que el servidor de prueba vio de una petición.
class Seen {
  Seen(this.method, this.path, this.headers, this.body);

  final String method;
  final String path;
  final HttpHeaders headers;
  final String body;
}

void main() {
  late HttpServer server;
  late HttpSyncTransport transport;
  final seen = <Seen>[];
  late Future<void> Function(HttpRequest request, String body) handler;

  final auth = SyncCredentials(
    listId: 'lista-que-no-sale',
    syncId: 'Xfhn06v0kc7dAEsbhsMBlQ',
    authKey: Uint8List.fromList(List<int>.generate(32, (i) => i)),
  );
  final authHeader = 'Bearer ${encodeBase64Url(auth.authKey)}';

  setUp(() async {
    seen.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        seen.add(Seen('WS', request.uri.path, request.headers, ''));
        await handler(request, '');
        return;
      }
      final body = await utf8.decoder.bind(request).join();
      seen.add(Seen(request.method, request.uri.path, request.headers, body));
      await handler(request, body);
    });
    transport = HttpSyncTransport(
      SyncEndpoint.parse('http://localhost:${server.port}')!,
      timeout: const Duration(seconds: 3),
    );
  });

  tearDown(() async {
    transport.close();
    await server.close(force: true);
  });

  Future<void> reply(
    HttpRequest r,
    int status, [
    Object? json,
    Map<String, String> headers = const {},
  ]) async {
    r.response.statusCode = status;
    headers.forEach(r.response.headers.set);
    if (json != null) {
      r.response.headers.contentType = ContentType.json;
      r.response.write(jsonEncode(json));
    }
    await r.response.close();
  }

  final envelope = Uint8List.fromList([1, 2, 3, 250, 251]);

  test('la lista va por syncId, con Bearer y sin el listId', () async {
    handler = (r, b) =>
        reply(r, 200, {'version': 3, 'envelope': encodeBase64Url(envelope)});
    final got = await transport.getList(auth, ifNoneMatch: 2);
    expect(got, isA<SyncGetOk>());
    expect((got as SyncGetOk).version, 3);
    expect(got.envelope, envelope);
    final s = seen.single;
    expect(s.method, 'GET');
    expect(s.path, '/v1/lists/${auth.syncId}');
    expect(s.headers.value('authorization'), authHeader);
    expect(s.headers.value('if-none-match'), '"2"');
    expect(s.path, isNot(contains(auth.listId)));
  });

  test('GET: 304 y 404', () async {
    handler = (r, b) => reply(r, 304);
    expect(
      await transport.getList(auth, ifNoneMatch: 3),
      isA<SyncGetNotModified>(),
    );
    handler = (r, b) => reply(r, 404, {'error': 'not_found'});
    expect(await transport.getList(auth), isA<SyncGetNotFound>());
  });

  test('B5 HTTP 410 means the v1 list is retired on GET and DELETE', () async {
    handler = (r, b) => reply(r, 410, {'error': 'retired'});
    expect(await transport.getList(auth), isA<SyncGetNotFound>());
    await transport.deleteList(auth);
  });

  test('PUT: cuerpo JSON, ok, 409 con sobre, 409 exists y 404', () async {
    handler = (r, b) => reply(r, 201, {'version': 1});
    final ok = await transport.putList(
      auth,
      baseVersion: null,
      envelope: envelope,
    );
    expect((ok as SyncPutOk).version, 1);
    final s = seen.single;
    expect(s.method, 'PUT');
    expect(s.headers.contentType?.mimeType, 'application/json');
    expect(jsonDecode(s.body), {
      'baseVersion': null,
      'envelope': encodeBase64Url(envelope),
    });

    handler = (r, b) =>
        reply(r, 409, {'version': 7, 'envelope': encodeBase64Url(envelope)});
    final conflict = await transport.putList(
      auth,
      baseVersion: 6,
      envelope: envelope,
    );
    expect((conflict as SyncPutConflict).version, 7);
    expect(conflict.envelope, envelope);

    handler = (r, b) => reply(r, 409, {'error': 'exists'});
    await expectLater(
      transport.putList(auth, baseVersion: null, envelope: envelope),
      throwsA(
        isA<SyncTransportException>().having(
          (e) => e.failure,
          'failure',
          SyncFailure.unauthorized,
        ),
      ),
    );

    handler = (r, b) => reply(r, 404, {'error': 'not_found'});
    expect(
      await transport.putList(auth, baseVersion: 2, envelope: envelope),
      isA<SyncPutNotFound>(),
    );
  });

  test('errores: 401, 413, 429 con Retry-After, 5xx y sin servidor', () async {
    Future<SyncFailure> failure() async {
      try {
        await transport.getList(auth);
      } on SyncTransportException catch (e) {
        return e.failure;
      }
      throw StateError('no falló');
    }

    handler = (r, b) => reply(r, 401);
    expect(await failure(), SyncFailure.unauthorized);
    handler = (r, b) => reply(r, 413);
    expect(await failure(), SyncFailure.tooLarge);
    handler = (r, b) => reply(r, 503);
    expect(await failure(), SyncFailure.server);
    handler = (r, b) =>
        reply(r, 429, {'error': 'rate_limited'}, {'Retry-After': '7'});
    try {
      await transport.getList(auth);
      fail('debía fallar');
    } on SyncTransportException catch (e) {
      expect(e.failure, SyncFailure.rateLimited);
      expect(e.retryAfter, const Duration(seconds: 7));
    }
    await server.close(force: true);
    expect(await failure(), SyncFailure.network);
  });

  test('DELETE', () async {
    handler = (r, b) => reply(r, 204);
    await transport.deleteList(auth);
    expect(seen.single.method, 'DELETE');
    expect(seen.single.path, '/v1/lists/${auth.syncId}');
  });

  test('invitaciones: crear, ver, ofrecer, aprobar, rechazar', () async {
    const id = 'oKGio6SlpqeoqaqrrK2urw';
    final key = Uint8List.fromList(List<int>.generate(32, (i) => 100 + i));

    handler = (r, b) =>
        reply(r, 201, {'inviteId': id, 'expiresAt': 1800000000000});
    final ticket = await transport.createInvite(auth);
    expect(ticket.inviteId, id);
    expect(ticket.expiresAt.millisecondsSinceEpoch, 1800000000000);
    expect(seen.last.path, '/v1/lists/${auth.syncId}/invites');
    expect(seen.last.method, 'POST');
    expect(seen.last.headers.contentType?.mimeType, 'application/json');

    handler = (r, b) => reply(r, 200, {'status': 'waiting', 'expiresAt': 1});
    expect(await transport.getInviteRequest(auth, id), isNull);
    handler = (r, b) => reply(r, 200, {
      'status': 'pending',
      'request': {'publicKey': encodeBase64Url(key), 'deviceName': 'Marta'},
    });
    final request = await transport.getInviteRequest(auth, id);
    expect(request!.publicKey, key);
    expect(request.deviceName, 'Marta');
    expect(seen.last.path, '/v1/lists/${auth.syncId}/invites/$id');

    handler = (r, b) => reply(r, 204);
    await transport.offerInvite(auth, id, key);
    expect(seen.last.method, 'POST');
    expect(seen.last.path, '/v1/lists/${auth.syncId}/invites/$id/offer');
    expect(jsonDecode(seen.last.body), {'publicKeyA': encodeBase64Url(key)});

    await transport.approveInvite(
      auth,
      id,
      InviteApproval(
        ciphertext: Uint8List.fromList([9, 9, 9]),
        nonce: Uint8List(12),
      ),
    );
    expect(seen.last.path, '/v1/lists/${auth.syncId}/invites/$id/approve');
    final approveBody = jsonDecode(seen.last.body) as Map;
    expect(approveBody.keys.toSet(), {
      'ciphertext',
      'nonce',
    }, reason: 'sin publicKeyA');

    await transport.rejectInvite(auth, id);
    expect(seen.last.method, 'POST');
    expect(seen.last.path, '/v1/lists/${auth.syncId}/invites/$id/reject');

    handler = (r, b) => reply(r, 404, {'error': 'not_found'});
    await expectLater(
      transport.getInviteRequest(auth, id),
      throwsA(isA<InviteGoneException>()),
    );
  });

  test('quien entra: join sin auth, 409, y result con X-Public-Key (202 pendiente, 202 con oferta, 200, 404)', () async {
    const id = 'oKGio6SlpqeoqaqrrK2urw';
    final b = Uint8List.fromList(List<int>.generate(32, (i) => 1 + i));
    final a = Uint8List.fromList(List<int>.generate(32, (i) => 50 + i));

    handler = (r, body) => reply(r, 201, {'expiresAt': 1});
    await transport.requestJoin(id, publicKey: b, deviceName: 'Marta');
    expect(seen.last.path, '/v1/invites/$id/join');
    expect(seen.last.headers.value('authorization'), isNull);
    expect(jsonDecode(seen.last.body), {
      'publicKey': encodeBase64Url(b),
      'deviceName': 'Marta',
    });

    handler = (r, body) => reply(r, 409, {'error': 'already_requested'});
    await expectLater(
      transport.requestJoin(id, publicKey: b, deviceName: 'Otro'),
      throwsA(isA<InviteTakenException>()),
    );
    handler = (r, body) => reply(r, 404, {'error': 'not_found'});
    await expectLater(
      transport.requestJoin(id, publicKey: b, deviceName: 'Otro'),
      throwsA(isA<InviteGoneException>()),
    );

    handler = (r, body) => reply(r, 202, {'status': 'pending'});
    var outcome = await transport.pollInviteResult(id, publicKey: b);
    expect(outcome, isA<InvitePending>());
    expect((outcome as InvitePending).publicKeyA, isNull);
    expect(seen.last.path, '/v1/invites/$id/result');
    expect(seen.last.headers.value('x-public-key'), encodeBase64Url(b));
    expect(seen.last.headers.value('authorization'), isNull);

    handler = (r, body) =>
        reply(r, 202, {'status': 'pending', 'publicKeyA': encodeBase64Url(a)});
    outcome = await transport.pollInviteResult(id, publicKey: b);
    expect((outcome as InvitePending).publicKeyA, a);

    handler = (r, body) => reply(r, 200, {
      'ciphertext': encodeBase64Url([1, 2, 3, 4]),
      'nonce': encodeBase64Url(Uint8List(12)),
    });
    final done = await transport.pollInviteResult(id, publicKey: b);
    expect(done, isA<InviteApproved>());
    expect((done as InviteApproved).approval.ciphertext, [1, 2, 3, 4]);

    handler = (r, body) => reply(r, 404);
    expect(
      await transport.pollInviteResult(id, publicKey: b),
      isA<InviteGone>(),
    );
  });

  test('WebSocket: ofrece gift-huddle.v1 y bearer.<authKey>, lee versiones y avisa del cierre 4404', () async {
    handler = (r, _) async {
      final socket = await WebSocketTransformer.upgrade(
        r,
        protocolSelector: (protocols) => 'gift-huddle.v1',
      );
      socket.add(jsonEncode({'type': 'version', 'version': 5}));
      socket.add('pong');
      socket.add(jsonEncode({'type': 'join-request', 'inviteId': 'x'}));
      socket.add(jsonEncode({'type': 'algo-nuevo'}));
      await socket.close(4404, 'gone');
    };
    final events = await transport.watch(auth).toList();
    expect(events.length, 4);
    // Primero el aviso propio de que la conexión se abrió.
    expect(events[0], isA<SyncOpenEvent>());
    expect((events[1] as SyncVersionEvent).version, 5);
    expect(events[2], isA<SyncJoinRequestEvent>());
    expect(events[3], isA<SyncGoneEvent>());
    final s = seen.single;
    expect(s.path, '/v1/lists/${auth.syncId}/ws');
    final protocols = s.headers.value('sec-websocket-protocol')!;
    expect(protocols, contains('gift-huddle.v1'));
    expect(protocols, contains('bearer.${encodeBase64Url(auth.authKey)}'));
  });

  test(
    'WebSocket: una redirección es un fallo y la authKey no viaja a otro sitio',
    () async {
      final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final reached = <String>[];
      other.listen((request) async {
        reached.add(
          request.headers.value('sec-websocket-protocol') ?? '(sin cabecera)',
        );
        request.response.statusCode = 400;
        await request.response.close();
      });
      addTearDown(() => other.close(force: true));
      handler = (r, _) => reply(r, 307, null, {
        'location': 'http://localhost:${other.port}/v1/lists/${auth.syncId}/ws',
      });

      await expectLater(
        transport.watch(auth).toList(),
        throwsA(isA<SyncTransportException>()),
      );
      // Dale tiempo a que, si hubiera seguido la redirección, llegara.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(seen, hasLength(1));
      expect(reached, isEmpty, reason: 'no se debe seguir la redirección');
    },
  );

  test('WebSocket: un 401 se reconoce como no autorizado', () async {
    handler = (r, _) => reply(r, 401);
    await expectLater(
      transport.watch(auth).toList(),
      throwsA(
        isA<SyncTransportException>().having(
          (e) => e.failure,
          'failure',
          SyncFailure.unauthorized,
        ),
      ),
    );
  });

  test(
    'WebSocket: un 101 que no acepta la clave del saludo se rechaza',
    () async {
      handler = (r, _) async {
        final socket = await r.response.detachSocket();
        socket.write(
          'HTTP/1.1 101 Switching Protocols\r\n'
          'Upgrade: websocket\r\n'
          'Connection: Upgrade\r\n'
          'Sec-WebSocket-Accept: AAAAAAAAAAAAAAAAAAAAAAAAAAA=\r\n\r\n',
        );
        await socket.flush();
        socket.destroy();
      };
      await expectLater(
        transport.watch(auth).toList(),
        throwsA(isA<SyncTransportException>()),
      );
    },
  );

  test('parseSyncEvent ignora lo que no entiende', () {
    expect(parseSyncEvent('pong'), isNull);
    expect(parseSyncEvent('[]'), isNull);
    expect(parseSyncEvent('{"type":"version"}'), isNull);
    expect(
      parseSyncEvent('{"type":"version","version":2}'),
      isA<SyncVersionEvent>(),
    );
  });
}
