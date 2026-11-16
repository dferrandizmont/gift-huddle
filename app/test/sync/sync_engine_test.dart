import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/sync/application/sync_controller.dart';
import 'package:regalos/features/sync/data/http_sync_transport.dart';
import 'package:regalos/features/sync/data/sync_config.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';
import 'package:regalos/features/sync/domain/sync_keys.dart';
import 'package:regalos/features/sync/domain/sync_status.dart';

import '../helpers/fake_sync_server.dart';
import '../helpers/memory_stores.dart';
import 'sync_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSyncServer server;
  final phones = <SyncPhone>[];

  setUp(() {
    server = FakeSyncServer();
  });

  tearDown(() {
    for (final p in phones) {
      p.dispose();
    }
    phones.clear();
  });

  Future<SyncPhone> newPhone({SyncTiming timing = kFastTiming}) async {
    final p = await SyncPhone.create(server, timing: timing);
    phones.add(p);
    return p;
  }

  /// A con la familia creada y B unido; los dos al día.
  Future<(SyncPhone, SyncPhone)> pair({SyncTiming timing = kFastTiming}) async {
    final a = await newPhone(timing: timing);
    await a.createFamily();
    final b = await newPhone(timing: timing);
    await b.joinFamilyOf(a);
    await converge([a, b]);
    // A (el que enseñó el QR) empieza a sincronizar al ver la copia de B.
    await eventually(
      () async => (await a.family.future).paired,
      reason: 'A emparejado',
    );
    await eventually(
      () =>
          a.status.phase == SyncPhase.synced &&
          b.status.phase == SyncPhase.synced,
      reason: 'los dos al día',
    );
    return (a, b);
  }

  /// Espera a que A (el que enseñó el QR) quede emparejado con la subida de
  /// emparejamiento hecha, y a que todos estén sincronizados con la misma copia
  /// y sin ciclos en marcha.
  Future<void> atRest(SyncPhone hub, List<SyncPhone> phones) async {
    await eventually(
      () async => (await hub.family.future).paired,
      reason: 'A emparejado',
    );
    await converge(phones);
    await eventually(
      () => phones.every((p) => p.status.phase == SyncPhase.synced),
      reason: 'móviles en reposo',
    );
  }

  group('configuración', () {
    test('por defecto apunta al Worker v2 del dominio propio', () {
      expect(kSyncHost, kDefaultSyncHost);
      expect(kDefaultSyncHost, 'https://sync.gifthuddle.app');
      expect(kInvitationOrigin, 'https://gifthuddle.app');
      final endpoint = SyncEndpoint.parse(
        kSyncHost,
        invitationOrigin: kInvitationOrigin,
      )!;
      expect(endpoint.host, 'sync.gifthuddle.app');
      expect(endpoint.invitationHost, 'gifthuddle.app');
    });

    test(
      'sin servidor la sincronización queda desactivada y lo dice',
      () async {
        final phone = FakePhone();
        addTearDown(phone.dispose);
        expect(
          phone.container.read(syncControllerProvider).phase,
          SyncPhase.notConfigured,
        );
        expect(phone.container.read(syncTransportProvider), isNull);
      },
    );

    test('los tiempos por defecto son los del ADR', () {
      const timing = SyncTiming();
      expect(timing.debounce, const Duration(seconds: 2));
      // 1.0.2: 1-2 s con la pantalla abierta; el límite del Worker lo
      // guarda `InvitePollPacer` (25 por invitación en 60 s).
      expect(timing.invitePoll, const Duration(seconds: 1));
      expect(timing.inviteHostPoll, const Duration(seconds: 1));
      expect(timing.inviteTimeout, const Duration(minutes: 10));
      expect(timing.maxConflicts, 3);
      // La espera crece y la última se repite.
      for (var i = 1; i < timing.backoff.length; i++) {
        expect(timing.backoffFor(i + 1), greaterThan(timing.backoffFor(i)));
      }
      expect(timing.backoffFor(100), timing.backoff.last);
    });

    test(
      'SyncEndpoint solo admite https, salvo http hacia el propio equipo',
      () {
        expect(SyncEndpoint.parse(''), isNull);
        expect(
          SyncEndpoint.parse('sync.example.workers.dev')!.base.scheme,
          'https',
        );
        expect(
          SyncEndpoint.parse('http://localhost:8787')!.host,
          'localhost:8787',
        );
        expect(SyncEndpoint.parse('http://10.0.2.2:8787'), isNotNull);
        expect(SyncEndpoint.parse('http://sync.example.com'), isNull);
        expect(SyncEndpoint.parse('ftp://sync.example.com'), isNull);
      },
    );
  });

  group('un móvil ya emparejado', () {
    test('sube la lista cifrada, con el syncId y no con el listId', () async {
      final a = await newPhone();
      await a.createPairedFamily();
      final key = a.family.familyKey!;
      final syncId = await SyncKeys.syncId(key);
      expect(server.hasList(syncId), isTrue);
      expect(server.hasList((await a.listId())!), isFalse);
      expect(server.versionOf(syncId), 1);
      expect(a.status.phase, SyncPhase.synced);
      expect(a.status.lastSyncAt, isNotNull);
    });

    test('un cambio local sube tras el retardo, agrupando varios en una sola subida', () async {
      final a = await newPhone(
        timing: const SyncTiming(
          debounce: Duration(milliseconds: 200),
          backoff: [Duration(milliseconds: 80)],
        ),
      );
      await a.createPairedFamily();
      final puts = server.calls['put']!;
      for (var i = 0; i < 5; i++) {
        await a.putGift('g$i', 'Regalo $i');
      }
      // Dentro del retardo no ha subido nada.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(server.calls['put'], puts);
      await eventually(
        () => server.calls['put'] == puts + 1,
        reason: 'una subida',
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(
        server.calls['put'],
        puts + 1,
        reason: 'cinco cambios, una sola subida',
      );
    });

    test(
      'Dejar de sincronizar borra la copia y no se vuelve a subir',
      () async {
        final a = await newPhone();
        await a.createPairedFamily();
        final syncId = await SyncKeys.syncId(a.family.familyKey!);
        await a.sync.stopSyncing();
        expect(server.hasList(syncId), isFalse);
        expect(a.status.phase, SyncPhase.disabled);
        // El cierre 4404 del WebSocket no hace que se suba otra vez.
        await Future<void>.delayed(const Duration(milliseconds: 400));
        expect(server.hasList(syncId), isFalse);
        await a.putGift('g1', 'Sigue guardado en local');
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(server.hasList(syncId), isFalse);
        expect((await a.gift('g1'))!.title, 'Sigue guardado en local');
        // Volver a encender la sube de nuevo.
        await a.sync.setEnabled(true);
        expect(server.hasList(syncId), isTrue);
        expect(a.status.phase, SyncPhase.synced);
      },
    );

    test('si no hay red, Dejar de sincronizar falla y no apaga nada', () async {
      final a = await newPhone();
      await a.createPairedFamily();
      a.transport.offline = true;
      await expectLater(
        a.sync.stopSyncing(),
        throwsA(isA<SyncTransportException>()),
      );
      expect(a.status.phase, isNot(SyncPhase.disabled));
      a.transport.offline = false;
      await eventually(() => a.status.phase == SyncPhase.synced);
    });

    test('una primera subida demasiado grande da un aviso propio y no se reintenta sin parar', () async {
      final a = await newPhone();
      a.transport.putError = const SyncTransportException(
        SyncFailure.tooLarge,
        '413',
      );
      await a.family.createFamily(deviceName: 'A');
      await a.family.markPaired(peerName: 'Otro móvil');
      await eventually(() => a.status.phase == SyncPhase.error);
      expect(a.status.issue, SyncIssue.firstUploadTooLarge);
      final puts = server.calls['put'];
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(server.calls['put'], puts);
    });

    test('apagada, los cambios se quedan en local y no se sube nada', () async {
      final a = await newPhone();
      await a.createPairedFamily();
      await a.sync.setEnabled(false);
      final puts = server.calls['put'];
      await a.putGift('g1', 'Local');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(server.calls['put'], puts);
      expect(a.status.phase, SyncPhase.disabled);
      await a.sync.setEnabled(true);
      expect(server.calls['put'], puts! + 1);
    });

    test(
      'si el servidor pierde la lista (404 o cierre 4404) la vuelve a subir',
      () async {
        final a = await newPhone();
        await a.createPairedFamily();
        final syncId = await SyncKeys.syncId(a.family.familyKey!);
        await a.putGift('g1', 'Uno');
        await eventually(() => server.versionOf(syncId)! >= 2);
        // 4404 por el WebSocket.
        server.expireList(syncId);
        await eventually(
          () => server.hasList(syncId),
          reason: 'resubida tras 4404',
        );
        expect(server.versionOf(syncId), 1);
        // 404 en un GET, sin WebSocket.
        a.transport.dropSockets(syncId);
        server.expireList(syncId);
        await a.sync.syncNow();
        expect(server.hasList(syncId), isTrue);
      },
    );
  });

  group('dos y tres móviles', () {
    test('B recibe lo que A ya tenía al unirse', () async {
      final a = await newPhone();
      await a.createFamily();
      await a.putGift('g1', 'Pijama', status: GiftStatus.bought);
      final b = await newPhone();
      await b.joinFamilyOf(a);
      await converge([a, b]);
      expect((await b.gift('g1'))!.title, 'Pijama');
      expect((await b.gift('g1'))!.status, GiftStatus.bought);
    });

    test('dos móviles editan a la vez, en campos distintos y en el mismo, y convergen', () async {
      final (a, b) = await pair();
      await a.putGift('g1', 'Libro');
      await converge([a, b]);
      // A la vez: A cambia el título y el precio; B, el estado y la tienda.
      await Future.wait([
        a.putGift('g1', 'Libro de dinosaurios', planned: 1800),
        b.putGift('g1', 'Libro', status: GiftStatus.bought, store: 'Librería'),
      ]);
      await converge([a, b]);
      final g = (await a.gift('g1'))!;
      expect(g.plannedCents, 1800);
      expect(g.status, GiftStatus.bought);
      expect(g.store, 'Librería');
      expect(await a.canonical(), await b.canonical());
    });

    test('tres móviles editan a la vez y todos acaban con lo mismo, sin perder nada', () async {
      final (a, b) = await pair();
      final c = await newPhone();
      await c.joinFamilyOf(a);
      await converge([a, b, c]);
      await Future.wait([
        a.putGift('ga', 'De A'),
        b.putGift('gb', 'De B'),
        c.putGift('gc', 'De C'),
      ]);
      await converge([a, b, c]);
      for (final p in [a, b, c]) {
        final ids = (await p.view()).gifts.map((g) => g.id).toSet();
        expect(ids, {'ga', 'gb', 'gc'});
      }
      // Los tres tocan el mismo campo del mismo regalo: gana uno y los tres
      // coinciden.
      await Future.wait([
        a.putGift('ga', 'Título A'),
        b.putGift('ga', 'Título B'),
        c.putGift('ga', 'Título C'),
      ]);
      await converge([a, b, c]);
      final titles = {
        for (final p in [a, b, c]) (await p.gift('ga'))!.title,
      };
      expect(titles.length, 1);
      expect(titles.single, startsWith('Título'));
    });

    test('un borrado viaja como lápida y no resucita', () async {
      final (a, b) = await pair();
      await a.putGift('g1', 'Uno');
      await converge([a, b]);
      await b.family.deleteGift('g1');
      await converge([a, b]);
      expect(await a.gift('g1'), isNull);
      await a.putGift('g1', 'Otra vez');
      await converge([a, b]);
      expect(await b.gift('g1'), isNull);
    });

    test(
      'el 409 se resuelve: se fusiona lo del servidor y se reintenta',
      () async {
        // Sin retardo ni avisos propios: solo corren los ciclos que se piden.
        final (a, b) = await pair(
          timing: const SyncTiming(
            peerPoll: Duration(milliseconds: 30),
            debounce: Duration(hours: 1),
            backoff: [Duration(milliseconds: 80)],
          ),
        );
        await a.putGift('g1', 'Base');
        await a.sync.syncNow();
        await b.sync.syncNow();
        expect((await b.gift('g1'))!.title, 'Base');

        var armed = true;
        server.beforePut = (syncId) async {
          if (!armed) {
            return;
          }
          armed = false;
          // Mientras A sube, B sube antes.
          await b.putGift('g2', 'De B, justo antes');
          await b.sync.syncNow();
        };
        final conflicts = server.conflicts;
        await a.putGift('g3', 'De A');
        await a.sync.syncNow();
        server.beforePut = null;

        expect(server.conflicts, conflicts + 1);
        expect(a.status.phase, SyncPhase.synced);
        await b.sync.syncNow();
        await converge([a, b]);
        final ids = (await a.view()).gifts.map((g) => g.id).toSet();
        expect(ids, {'g1', 'g2', 'g3'});
      },
    );

    test(
      'el WebSocket trae el cambio al momento, sin esperar a otra subida',
      () async {
        final (a, b) = await pair(
          timing: const SyncTiming(
            peerPoll: Duration(milliseconds: 30),
            debounce: Duration(milliseconds: 30),
            backoff: [Duration(milliseconds: 80)],
          ),
        );
        final syncId = await SyncKeys.syncId(a.family.familyKey!);
        expect(server.watchers(syncId), 2);
        final gets = server.calls['get'];
        await a.putGift('g1', 'Por WebSocket');
        await eventually(() async => (await b.gift('g1')) != null);
        expect(server.calls['get'], greaterThan(gets!));
      },
    );

    test('solo escucha el WebSocket en primer plano', () async {
      final a = await newPhone();
      await a.createPairedFamily();
      final syncId = await SyncKeys.syncId(a.family.familyKey!);
      expect(server.watchers(syncId), 1);
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.paused,
      );
      await eventually(
        () => server.watchers(syncId) == 0,
        reason: 'cerrar el WebSocket',
      );
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await eventually(
        () => server.watchers(syncId) == 1,
        reason: 'reabrir el WebSocket',
      );
      // Al volver a primer plano sincroniza.
      expect(a.status.phase, SyncPhase.synced);
    });

    test('si el WebSocket se corta, vuelve a conectar', () async {
      final a = await newPhone();
      await a.createPairedFamily();
      final syncId = await SyncKeys.syncId(a.family.familyKey!);
      a.transport.dropSockets(syncId);
      expect(server.watchers(syncId), 0);
      await eventually(
        () => server.watchers(syncId) == 1,
        reason: 'reconexión',
      );
    });

    test('al reconectar el WebSocket se pone al día con lo que perdió mientras estuvo cortado', () async {
      final (a, b) = await pair(
        timing: const SyncTiming(
          peerPoll: Duration(milliseconds: 30),
          debounce: Duration(milliseconds: 30),
          backoff: [Duration(milliseconds: 80)],
          watchBackoff: [Duration(milliseconds: 500)],
        ),
      );
      final syncId = await SyncKeys.syncId(a.family.familyKey!);
      // El servidor falso corta los WebSocket de la lista entera.
      b.transport.dropSockets(syncId);
      expect(server.watchers(syncId), 0);
      await a.putGift('g1', 'Mientras B estaba cortado');
      await eventually(
        () => (server.versionOf(syncId) ?? 0) >= 2,
        reason: 'A sube',
      );
      expect(await b.gift('g1'), isNull);
      // B reconecta y, sin que llegue ningún aviso nuevo, pide lo que faltaba.
      await eventually(
        () async => (await b.gift('g1')) != null,
        reason: 'puesta al día',
      );
      expect(server.watchers(syncId), 2);
    });

    test('el WebSocket que se abre reinicia la espera de reconexión', () async {
      final a = await newPhone(
        timing: const SyncTiming(
          debounce: Duration(milliseconds: 30),
          backoff: [Duration(milliseconds: 80)],
          watchBackoff: [Duration(milliseconds: 60), Duration(hours: 1)],
        ),
      );
      await a.createPairedFamily();
      final syncId = await SyncKeys.syncId(a.family.familyKey!);
      // Si la cuenta de cortes no se reiniciara al abrir, el segundo corte
      // esperaría una hora.
      for (var i = 0; i < 3; i++) {
        a.transport.dropSockets(syncId);
        await eventually(
          () => server.watchers(syncId) == 1,
          reason: 'reconexión $i',
        );
      }
    });
  });

  group('sin red', () {
    test(
      'guarda en local, avisa, reintenta con espera creciente y se recupera',
      () async {
        final (a, b) = await pair(
          timing: const SyncTiming(
            peerPoll: Duration(milliseconds: 30),
            debounce: Duration(milliseconds: 20),
            backoff: [Duration(milliseconds: 100), Duration(milliseconds: 400)],
          ),
        );
        a.transport.offline = true;
        a.transport.times['get']?.clear();
        await a.putGift('g1', 'Hecho sin red');
        await eventually(
          () => a.status.phase == SyncPhase.offline,
          reason: 'estado sin conexión',
        );
        // Sigue en el móvil.
        expect((await a.gift('g1'))!.title, 'Hecho sin red');
        expect(await b.gift('g1'), isNull);
        // Reintenta cada vez más despacio.
        await eventually(
          () => (a.transport.times['get']?.length ?? 0) >= 3,
          reason: 'tres intentos',
        );
        final t = a.transport.times['get']!;
        expect(
          t[2] - t[1],
          greaterThan(t[1] - t[0]),
          reason: 'espera creciente $t',
        );
        // Vuelve la red.
        a.transport.offline = false;
        await eventually(
          () => a.status.phase == SyncPhase.synced,
          reason: 'recuperación',
        );
        await converge([a, b]);
        expect((await b.gift('g1'))!.title, 'Hecho sin red');
      },
    );

    test('lo que llega mientras A está sin red se fusiona al volver, sin perder nada', () async {
      final (a, b) = await pair();
      a.transport.offline = true;
      await a.putGift('ga', 'De A sin red');
      await b.putGift('gb', 'De B con red');
      await eventually(() => a.status.phase == SyncPhase.offline);
      a.transport.offline = false;
      await converge([a, b]);
      final ids = (await a.view()).gifts.map((g) => g.id).toSet();
      expect(ids, {'ga', 'gb'});
    });

    test(
      'volver a primer plano reintenta ya, sin esperar a la espera',
      () async {
        final a = await newPhone(
          timing: const SyncTiming(
            debounce: Duration(milliseconds: 20),
            backoff: [Duration(hours: 1)],
          ),
        );
        await a.createPairedFamily();
        a.transport.offline = true;
        await a.putGift('g1', 'Uno');
        await eventually(() => a.status.phase == SyncPhase.offline);
        a.transport.offline = false;
        WidgetsBinding.instance.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await eventually(
          () => a.status.phase == SyncPhase.synced,
          reason: 'sincronizar al volver',
        );
      },
    );
  });

  group('deriva de reloj', () {
    test('un móvil con el reloj más de un día adelantado se rechaza y avisa', () async {
      final (a, b) = await pair();
      final c = await newPhone();
      await c.joinFamilyOf(a);
      await converge([a, b, c]);
      // Con A y B (y C) en reposo: el emparejamiento ya ha subido lo suyo, así
      // que la versión que se captura no cambia por subidas pendientes.
      await atRest(a, [a, b, c]);
      final before = await a.canonical();
      // C escribe con el reloj tres días adelantado y sube.
      final future = clock.now().add(const Duration(days: 3));
      final syncId = await SyncKeys.syncId(c.family.familyKey!);
      final versionBefore = server.versionOf(syncId) ?? 0;
      await withClock(Clock.fixed(future), () => c.putGift('gx', 'Del futuro'));
      await eventually(() async {
        final v = server.versionOf(syncId);
        return v != null && v > versionBefore;
      });
      await a.sync.syncNow();
      expect(a.status.phase, SyncPhase.error);
      expect(a.status.issue, SyncIssue.clockDrift);
      // Lo local no se toca ni se mezcla nada del futuro.
      expect(await a.canonical(), before);
      expect(await a.gift('gx'), isNull);
      // Y A puede seguir trabajando en local.
      await a.putGift('ga', 'Sigue funcionando');
      expect((await a.gift('ga'))!.title, 'Sigue funcionando');
    });

    test('un móvil con el reloj atrasado no pierde sus cambios: el reloj lógico lo corrige', () async {
      final (a, b) = await pair();
      await a.putGift('g1', 'Antiguo');
      await converge([a, b]);
      // B ya vio los sellos de A; escribe ahora con el reloj tres días atrasado.
      final past = clock.now().subtract(const Duration(days: 3));
      await withClock(Clock.fixed(past), () => b.putGift('g1', 'Nuevo de B'));
      await converge([a, b]);
      expect((await a.gift('g1'))!.title, 'Nuevo de B');
      expect((await b.gift('g1'))!.title, 'Nuevo de B');
    });
  });

  group('emparejamiento por sincronizacion', () {
    test(
      'A queda emparejado al recibir el primer sobre de B, sin editar nada',
      () async {
        final a = await newPhone();
        await a.createFamily();
        final b = await newPhone();
        await b.joinFamilyOf(a);
        expect(
          (await a.family.future).paired,
          isFalse,
          reason: 'Aun no ha recibido nada de B',
        );

        await b.sync.syncNow();
        await eventually(
          () async => (await a.family.future).paired,
          reason: 'A queda emparejado al recibir a B',
        );
        await a.sync.syncNow();
        expect((await a.family.future).paired, isTrue);
      },
    );

    test('la subida forzada ocurre una sola vez', () async {
      final a = await newPhone();
      await a.createFamily();
      // Con un solo móvil A no ha subido nada.
      final putsOfAAtCreate = a.transport.times['put']?.length ?? 0;
      expect(putsOfAAtCreate, 0);
      final b = await newPhone();
      await b.joinFamilyOf(a);
      await converge([a, b]);
      await atRest(a, [a, b]);
      expect(
        a.transport.times['put']!.length - putsOfAAtCreate,
        1,
        reason: 'A hace exactamente una subida de emparejamiento',
      );
      final putsBefore = server.calls['put']!;
      await a.sync.syncNow();
      await b.sync.syncNow();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(
        server.calls['put'],
        putsBefore,
        reason: 'no debe haber subidas extra sin cambios',
      );
    });
  });
}
