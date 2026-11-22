// Ruta de reserva contra el bloqueo (1.0.6): orden de los hosts, cambio solo
// por fallo al conectar, recuerdo de 30 minutos, índice guardado y WebSocket.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/sync/data/http_sync_transport.dart';
import 'package:regalos/features/sync/data/sync_routes.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';

/// Almacén en memoria que cuenta lo que se escribe.
class _Store implements SyncRouteStore {
  _Store([this.memo]);

  SyncRouteMemo? memo;
  int writes = 0;

  @override
  SyncRouteMemo? read() => memo;

  @override
  void write(SyncRouteMemo? value) {
    writes++;
    memo = value;
  }
}

/// Una conexión que falla como lo haría la red: un poco después, cuando
/// `HttpClient` ya la está esperando.
Future<Socket> _failsLater(Object error) {
  final socket = Completer<Socket>();
  Timer(const Duration(milliseconds: 10), () => socket.completeError(error));
  return socket.future;
}

final _main = Uri.parse('https://sync.gifthuddle.app');
final _spare = Uri.parse('https://sync-gh.mainshai.com');

void main() {
  var now = DateTime.utc(2026, 12, 24, 9);
  T at<T>(T Function() run) => withClock(Clock(() => now), run);

  setUp(() {
    now = DateTime.utc(2026, 12, 24, 9);
    SyncRoutes.resetShared();
  });

  group('lista de hosts', () {
    test('el servidor por defecto da los dos hosts compilados; el de '
        'desarrollo, uno solo', () {
      final main = SyncEndpoint.parse(kDefaultSyncHost)!;
      expect(main.routes, [_main, _spare]);
      expect(kSyncHosts, ['sync.gifthuddle.app', 'sync-gh.mainshai.com']);
      for (final dev in [
        'http://localhost:8787',
        'http://10.0.2.2:8787',
        'https://sync.example',
        'https://sync.gifthuddle.app:8443',
      ]) {
        final endpoint = SyncEndpoint.parse(dev)!;
        expect(endpoint.routes, [endpoint.base], reason: dev);
      }
      // Fijado en la compilación (SYNC_API_ORIGIN), ni siquiera el principal
      // activa la reserva.
      expect(
        SyncEndpoint.parse(kDefaultSyncHost, explicitOrigin: true)!.routes,
        [_main],
      );
    });

    test('solo se reparten las direcciones del host principal, también '
        'las de WebSocket', () {
      final routes = SyncRoutes([_main, _spare]);
      expect(
        routes
            .targets(Uri.parse('https://sync.gifthuddle.app/v2/lists/a'))
            .map((t) => t.$2.toString()),
        [
          'https://sync.gifthuddle.app/v2/lists/a',
          'https://sync-gh.mainshai.com/v2/lists/a',
        ],
      );
      expect(
        routes
            .targets(Uri.parse('wss://sync.gifthuddle.app/v2/lists/a/ws'))
            .map((t) => t.$2.toString()),
        [
          'wss://sync.gifthuddle.app/v2/lists/a/ws',
          'wss://sync-gh.mainshai.com/v2/lists/a/ws',
        ],
      );
      for (final other in [
        'https://evil.example/v2',
        'http://sync.gifthuddle.app/v2',
        'https://sync.gifthuddle.app:444/v2',
      ]) {
        final uri = Uri.parse(other);
        expect(routes.targets(uri), [(null, uri)], reason: other);
      }
    });
  });

  group('cuándo se cambia de host', () {
    Future<(int, List<String>)> request(
      SyncRoutes routes,
      Object? Function(Uri target) mainOutcome,
    ) async {
      final tried = <String>[];
      final status = await routes.run(_main, (target, connected) async {
        tried.add(target.host);
        if (target.host == _main.host) {
          final outcome = mainOutcome(target);
          if (outcome is Exception) throw outcome;
          connected();
          return outcome! as int;
        }
        connected();
        return 200;
      });
      return (status, tried);
    }

    for (final (name, failure) in [
      ('tiempo agotado', 'tiempo de conexión agotado'),
      ('conexión cortada (RST)', 'Connection reset by peer'),
      ('TLS o certificado ajeno', 'fallo de TLS'),
    ]) {
      test('por $name pasa a la reserva y la recuerda', () async {
        final routes = SyncRoutes([_main, _spare]);
        final (status, tried) = await at(
          () => request(routes, (_) => SyncRouteConnectFailure(failure)),
        );
        expect(status, 200);
        expect(tried, [_main.host, _spare.host]);
        expect(at(() => routes.current), 1);
      });
    }

    for (final status in [400, 401, 404, 409, 412, 429, 500, 502, 503]) {
      test('un $status no cambia de host', () async {
        final routes = SyncRoutes([_main, _spare]);
        final (got, tried) = await at(() => request(routes, (_) => status));
        expect(got, status);
        expect(tried, [_main.host]);
        expect(at(() => routes.current), 0);
      });
    }

    test('un error después de conectar (respuesta lenta) no cambia de '
        'host', () async {
      final routes = SyncRoutes([_main, _spare]);
      final tried = <String>[];
      await expectLater(
        at(
          () => routes.run(_main, (target, connected) async {
            tried.add(target.host);
            connected();
            throw const SyncTransportException(
              SyncFailure.network,
              'tiempo agotado',
            );
          }),
        ),
        throwsA(isA<SyncTransportException>()),
      );
      expect(tried, [_main.host]);
    });

    test('si no conecta ninguno: error de red y, tras 3 seguidos, la pista '
        'del bloqueo; al conectar, se quita', () async {
      final routes = SyncRoutes([_main, _spare]);
      final seen = <bool>[];
      final sub = routes.watchBlocked().listen(seen.add);
      Future<void> fail() => expectLater(
        at(
          () => routes.run<int>(
            _main,
            (_, _) async => throw const SyncRouteConnectFailure('rechazada'),
          ),
        ),
        throwsA(
          isA<SyncTransportException>()
              .having((e) => e.failure, 'failure', SyncFailure.network)
              .having((e) => e.message, 'message', 'rechazada'),
        ),
      );
      await fail();
      await fail();
      expect(routes.likelyBlocked, isFalse);
      await fail();
      expect(routes.likelyBlocked, isTrue);
      await at(() => request(routes, (_) => 200));
      expect(routes.likelyBlocked, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(seen, [false, true, false]);
      await sub.cancel();
    });
  });

  group('mutaciones de la web (una sola vez)', () {
    final open = Uri.parse(
      'https://sync.gifthuddle.app/v2/lists/AAAA/guards/web-1/open',
    );

    test('la ruta se elige con una lectura y el POST con el PIN sale una '
        'vez; si su respuesta no llega, no se repite en la reserva', () async {
      final routes = SyncRoutes([_main, _spare]);
      final probes = <String>[];
      final posts = <String>[];
      Future<void> probe(Uri target, void Function() connected) async {
        probes.add('${target.host}${target.path}');
        if (target.host == _main.host) {
          throw const SyncRouteConnectFailure('rechazada');
        }
        connected();
      }

      // El Worker aplica el intento de PIN, pero la respuesta no llega.
      Future<int> applied(Uri target, void Function() connected) async {
        posts.add(target.host);
        throw const SyncRouteConnectFailure('sin cabecera a tiempo');
      }

      await expectLater(
        at(() => routes.runOnce(open, probe: probe, attempt: applied)),
        throwsA(
          isA<SyncTransportException>().having(
            (e) => e.failure,
            'failure',
            SyncFailure.network,
          ),
        ),
      );
      expect(probes, [
        '${_main.host}$kSyncRouteProbePath',
        '${_spare.host}$kSyncRouteProbePath',
      ]);
      expect(posts, [_spare.host]);
      // Lo mismo cuando conecta y la respuesta se retrasa: un solo POST.
      posts.clear();
      probes.clear();
      await expectLater(
        at(
          () => routes.runOnce(
            open,
            probe: probe,
            attempt: (target, connected) async {
              posts.add(target.host);
              connected();
              throw const SyncTransportException(
                SyncFailure.network,
                'tiempo agotado',
              );
            },
          ),
        ),
        throwsA(isA<SyncTransportException>()),
      );
      expect(posts, [_spare.host]);
    });

    test('con la ruta conectada hace menos de un minuto no se vuelve a '
        'leer; pasado el minuto, sí', () async {
      final routes = SyncRoutes([_main, _spare]);
      var probes = 0;
      Future<void> probe(Uri target, void Function() connected) async {
        probes++;
        connected();
      }

      Future<int> post(Uri target, void Function() connected) async {
        connected();
        return 200;
      }

      expect(
        await at(() => routes.runOnce(open, probe: probe, attempt: post)),
        200,
      );
      expect(
        await at(() => routes.runOnce(open, probe: probe, attempt: post)),
        200,
      );
      expect(probes, 1);
      now = now.add(kSyncRouteConfirmed);
      await at(() => routes.runOnce(open, probe: probe, attempt: post));
      expect(probes, 2);
    });

    test('con un solo host no hay lectura previa', () async {
      final dev = Uri.parse('http://localhost:8787');
      final routes = SyncRoutes([dev]);
      var probes = 0;
      final got = await routes.runOnce(
        dev.replace(path: '/v2/x'),
        probe: (_, _) async => probes++,
        attempt: (_, connected) async {
          connected();
          return 1;
        },
      );
      expect(got, 1);
      expect(probes, 0);
    });
  });

  group('recuerdo de 30 minutos', () {
    test('se empieza por la reserva durante 30 minutos sin alargarlos; '
        'después, otra vez por el principal', () async {
      final store = _Store();
      final routes = SyncRoutes([_main, _spare], store: store);
      at(() => routes.markConnected(1));
      expect(store.memo?.index, 1);
      expect(
        store.memo?.untilMillis,
        now.add(kSyncRouteMemory).millisecondsSinceEpoch,
      );
      now = now.add(const Duration(minutes: 20));
      expect(at(() => routes.targets(_main).first.$1), 1);
      // Seguir conectando con la reserva no alarga el plazo.
      at(() => routes.markConnected(1));
      expect(store.writes, 1);
      now = now.add(const Duration(minutes: 11));
      expect(at(() => routes.targets(_main).first.$1), 0);
      expect(store.memo, isNull);
    });

    test('si mientras tanto conecta el principal, se olvida la reserva', () {
      final store = _Store();
      final routes = SyncRoutes([_main, _spare], store: store);
      at(() => routes.markConnected(1));
      at(() => routes.markConnected(0));
      expect(at(() => routes.current), 0);
      expect(store.memo, isNull);
    });

    test('lo guardado se recupera al arrancar', () {
      final until = now.add(const Duration(minutes: 10)).millisecondsSinceEpoch;
      final routes = at(
        () => SyncRoutes([
          _main,
          _spare,
        ], store: _Store((index: 1, untilMillis: until))),
      );
      expect(at(() => routes.current), 1);
    });

    for (final (name, index, minutes) in [
      ('índice fuera de la lista', 2, 10),
      ('índice negativo', -1, 10),
      ('índice del principal', 0, 10),
      ('plazo vencido', 1, -1),
      ('plazo más largo que 30 minutos (reloj cambiado)', 1, 31),
    ]) {
      test('$name: no vale y se borra', () {
        final store = _Store((
          index: index,
          untilMillis: now
              .add(Duration(minutes: minutes))
              .millisecondsSinceEpoch,
        ));
        final routes = at(() => SyncRoutes([_main, _spare], store: store));
        expect(at(() => routes.current), 0);
        expect(store.memo, isNull);
      });
    }

    test('las rutas compartidas usan el almacén de main, también las que ya '
        'existían', () {
      final routes = SyncRoutes.shared([_main, _spare]);
      expect(identical(routes, SyncRoutes.shared([_main, _spare])), isTrue);
      final store = _Store((
        index: 1,
        untilMillis: now.add(const Duration(minutes: 5)).millisecondsSinceEpoch,
      ));
      at(() => SyncRoutes.useStore(store));
      expect(at(() => routes.current), 1);
    });
  });

  group('transporte de los móviles', () {
    late HttpServer spare;
    late List<String> spareSeen;
    late Future<void> Function(HttpRequest request) spareHandler;

    setUp(() async {
      spareSeen = [];
      spare = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      spare.listen((request) async {
        spareSeen.add('${request.method} ${request.uri.path}');
        await spareHandler(request);
      });
      spareHandler = (r) async {
        r.response.statusCode = 200;
        r.response.headers.contentType = ContentType.json;
        r.response.write(jsonEncode({'version': 3, 'envelope': 'AQID'}));
        await r.response.close();
      };
    });

    tearDown(() => spare.close(force: true));

    final auth = SyncCredentials(
      listId: 'lista',
      syncId: 'Xfhn06v0kc7dAEsbhsMBlQ',
      authKey: Uint8List(32),
    );

    /// Un transporte cuyo host principal (`main.test`) se comporta como
    /// diga [primary] y cuya reserva es el servidor local.
    (HttpSyncTransport, SyncRoutes) transportWith(
      Future<ConnectionTask<Socket>> Function() primary,
    ) {
      final spareBase = Uri.parse('http://127.0.0.1:${spare.port}');
      final mainBase = Uri.parse('http://localhost:${spare.port + 1}');
      final routes = SyncRoutes([mainBase, spareBase]);
      final client = HttpClient()
        ..connectionFactory = (uri, proxyHost, proxyPort) {
          if (uri.host == 'localhost') return primary();
          return Socket.startConnect(uri.host, uri.port);
        };
      final transport = HttpSyncTransport(
        SyncEndpoint.parse(mainBase.toString())!,
        client: client,
        routes: routes,
        timeout: const Duration(seconds: 3),
        connectTimeout: const Duration(milliseconds: 300),
      );
      return (transport, routes);
    }

    for (final (name, primary) in [
      (
        'tiempo de conexión agotado',
        () async =>
            ConnectionTask.fromSocket(Completer<Socket>().future, () {}),
      ),
      (
        'conexión cortada (RST)',
        () async => ConnectionTask.fromSocket(
          _failsLater(const SocketException('Connection reset by peer')),
          () {},
        ),
      ),
      (
        'certificado ajeno',
        () async => ConnectionTask.fromSocket(
          _failsLater(const HandshakeException('CERTIFICATE_VERIFY_FAILED')),
          () {},
        ),
      ),
    ]) {
      test('$name en el principal: la petición sale por la reserva', () async {
        final (transport, routes) = transportWith(primary);
        addTearDown(transport.close);
        final got = await transport.getList(auth);
        expect((got as SyncGetOk).version, 3);
        expect(spareSeen, ['GET /v1/lists/${auth.syncId}']);
        expect(routes.current, 1);
        // La siguiente ya empieza por la reserva.
        await transport.getList(auth);
        expect(spareSeen, hasLength(2));
      });
    }

    test('TLS que falla: el extremo rechazado no recibe ni cabeceras ni '
        'credencial, y se prueba el siguiente', () async {
      final received = <String, List<int>>{};
      final servers = <ServerSocket>[];
      for (final name in ['main', 'spare']) {
        // Contesta lo que no es TLS (como una página de bloqueo) y corta.
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        servers.add(server);
        received[name] = [];
        server.listen((socket) {
          socket.listen((data) {
            received[name]!.addAll(data);
            socket.add(utf8.encode('HTTP/1.1 403 Blocked\r\n\r\n'));
            unawaited(socket.close());
          }, onError: (Object _) {});
        });
      }
      addTearDown(() async {
        for (final s in servers) {
          await s.close();
        }
      });
      final routes = SyncRoutes([
        Uri.parse('https://localhost:${servers[0].port}'),
        Uri.parse('https://127.0.0.1:${servers[1].port}'),
      ]);
      final transport = HttpSyncTransport(
        SyncEndpoint.parse('https://localhost:${servers[0].port}')!,
        routes: routes,
        timeout: const Duration(seconds: 3),
        connectTimeout: const Duration(seconds: 2),
      );
      addTearDown(transport.close);
      final key = Uint8List.fromList(List<int>.generate(32, (i) => 200 - i));
      final secret = SyncCredentials(
        listId: 'lista',
        syncId: 'Xfhn06v0kc7dAEsbhsMBlQ',
        authKey: key,
      );
      await expectLater(
        transport.getList(secret),
        throwsA(
          isA<SyncTransportException>().having(
            (e) => e.failure,
            'failure',
            SyncFailure.network,
          ),
        ),
      );
      for (final name in ['main', 'spare']) {
        final bytes = received[name]!;
        // Solo el saludo TLS (registro de tipo 22): nada de HTTP en claro.
        expect(bytes, isNotEmpty, reason: name);
        expect(bytes.first, 0x16, reason: name);
        final text = latin1.decode(bytes);
        for (final leak in [
          'GET ',
          'Authorization',
          'Bearer',
          auth.syncId,
          base64Url.encode(key).replaceAll('=', ''),
        ]) {
          expect(text, isNot(contains(leak)), reason: '$name: $leak');
        }
      }
    });

    test('un 503 o un 404 del principal no prueban la reserva', () async {
      late HttpServer main;
      main = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => main.close(force: true));
      var status = 503;
      main.listen((r) async {
        r.response.statusCode = status;
        r.response.headers.contentType = ContentType.json;
        r.response.write(jsonEncode({'error': 'not_found'}));
        await r.response.close();
      });
      final (transport, routes) = transportWith(
        () => Socket.startConnect('127.0.0.1', main.port),
      );
      addTearDown(transport.close);
      await expectLater(
        transport.getList(auth),
        throwsA(
          isA<SyncTransportException>().having(
            (e) => e.failure,
            'failure',
            SyncFailure.server,
          ),
        ),
      );
      status = 404;
      expect(await transport.getList(auth), isA<SyncGetNotFound>());
      expect(spareSeen, isEmpty);
      expect(routes.current, 0);
    });

    test('WebSocket: si no conecta el principal, abre en la reserva', () async {
      spareHandler = (r) async {
        final socket = await WebSocketTransformer.upgrade(
          r,
          protocolSelector: (protocols) => 'gift-huddle.v2',
        );
        socket.add(jsonEncode({'type': 'version', 'version': 9}));
        await socket.close(4404, 'gone');
      };
      final (transport, routes) = transportWith(
        () async =>
            ConnectionTask.fromSocket(Completer<Socket>().future, () {}),
      );
      addTearDown(transport.close);
      final events = await transport.socketV2(
        Uri.parse(
          '${transport.endpoint.base.replace(scheme: 'ws')}/v2/lists/x/ws',
        ),
        ['gift-huddle.v2', 'bearer.test'],
      ).toList();
      expect(events.first, isA<SyncOpenEvent>());
      expect(events.last, isA<SyncGoneEvent>());
      expect(spareSeen, ['GET /v2/lists/x/ws']);
      expect(routes.current, 1);
    });

    test(
      'WebSocket: un rechazo HTTP del principal no prueba la reserva',
      () async {
        late HttpServer main;
        main = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => main.close(force: true));
        main.listen((r) async {
          r.response.statusCode = 401;
          await r.response.close();
        });
        final (transport, _) = transportWith(
          () => Socket.startConnect('127.0.0.1', main.port),
        );
        addTearDown(transport.close);
        await expectLater(
          transport.socketV2(
            Uri.parse(
              '${transport.endpoint.base.replace(scheme: 'ws')}/v2/lists/x/ws',
            ),
            ['gift-huddle.v2', 'bearer.test'],
          ).toList(),
          throwsA(
            isA<SyncTransportException>().having(
              (e) => e.failure,
              'failure',
              SyncFailure.unauthorized,
            ),
          ),
        );
        expect(spareSeen, isEmpty);
      },
    );
  });
}
