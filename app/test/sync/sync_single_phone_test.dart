import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/prefs/shared_preferences_provider.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/features/sharing/application/pairing_service.dart';
import 'package:regalos/features/sharing/application/share_service.dart';
import 'package:regalos/features/sync/application/peer_connected.dart';
import 'package:regalos/features/sync/application/sync_controller.dart';
import 'package:regalos/features/sync/data/sync_config.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';
import 'package:regalos/features/sync/domain/sync_keys.dart';
import 'package:regalos/features/sync/domain/sync_status.dart';
import 'package:regalos/features/sync/invites/invite_guest.dart';
import 'package:regalos/features/sync/invites/invite_host.dart';

import '../helpers/fake_sync_server.dart';
import 'sync_harness.dart';

/// Con un solo móvil no se habla con el servidor: nada sube ni se abre el
/// WebSocket hasta que la familia tiene un segundo móvil emparejado, por QR o
/// por invitación. Los que ya estaban emparejados siguen igual.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSyncServer server;
  final phones = <SyncPhone>[];

  setUp(() => server = FakeSyncServer());
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

  /// Deja pasar lo que estuviera en marcha (retardos, sondeos, reintentos).
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 300));

  Future<String> syncIdOf(SyncPhone p) => SyncKeys.syncId(p.family.familyKey!);

  group('un solo móvil', () {
    test('no hace ninguna petición: ni al crear la familia, ni al editar, ni al volver, ni con Sincronizar ahora', () async {
      final a = await newPhone();
      await a.createFamily();
      await a.putGift('g1', 'Pijama');
      await a.putGift('g2', 'Libro');
      await settle();
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.paused,
      );
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await a.sync.syncNow();
      await settle();

      expect(server.calls, isEmpty, reason: 'ninguna petición al servidor');
      expect(a.transport.times, isEmpty);
      final syncId = await syncIdOf(a);
      expect(server.hasList(syncId), isFalse);
      expect(server.watchers(syncId), 0);
      expect(a.status.phase, SyncPhase.waitingForPeer);
      // Encendida (el interruptor sigue puesto), solo que a la espera.
      expect(a.status.active, isTrue);
      // Lo local sigue en su sitio.
      expect((await a.gift('g1'))!.title, 'Pijama');
    });

    test('tampoco tras cerrar y abrir la app', () async {
      final a = await newPhone();
      await a.createFamily();
      await a.putGift('g1', 'Pijama');
      a.phone.restart();
      a.c.read(syncControllerProvider); // arranca la sincronización
      await eventually(() => a.status.phase == SyncPhase.waitingForPeer);
      await a.putGift('g2', 'Libro');
      await settle();
      expect(server.calls, isEmpty);
    });

    test('apagar y encender la sincronización no sube nada', () async {
      final a = await newPhone();
      await a.createFamily();
      await a.sync.setEnabled(false);
      expect(a.status.phase, SyncPhase.disabled);
      await a.sync.setEnabled(true);
      await settle();
      expect(a.status.phase, SyncPhase.waitingForPeer);
      expect(server.calls, isEmpty);
    });
  });

  group('emparejar por QR', () {
    test('enseñar el QR solo mira si el otro ha entrado: no sube nada ni abre el WebSocket', () async {
      final a = await newPhone();
      await a.createFamily();
      await a.putGift('g1', 'Pijama');
      await a.c.read(pairingServiceProvider).qrTextForPairing();
      await eventually(() => (server.calls['get'] ?? 0) >= 2, reason: 'A mira');
      await a.putGift('g2', 'Libro');
      await settle();

      expect(server.calls.keys, {'get'}, reason: 'solo lecturas');
      final syncId = await syncIdOf(a);
      expect(server.hasList(syncId), isFalse);
      expect(server.watchers(syncId), 0);
      expect(a.status.phase, SyncPhase.waitingForPeer);
      expect((await a.family.future).paired, isFalse);
    });

    test(
      'cuando el otro móvil lee el QR empieza la sincronización en los dos',
      () async {
        final a = await newPhone();
        await a.createFamily();
        await a.putGift('g1', 'Pijama');
        final b = await newPhone();
        await b.joinFamilyOf(a);

        await converge([a, b]);
        expect((await b.gift('g1'))!.title, 'Pijama');
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
        final syncId = await syncIdOf(a);
        expect(server.hasList(syncId), isTrue);
        await eventually(
          () => server.watchers(syncId) == 2,
          reason: 'dos WebSocket',
        );

        // Y desde ahí, los cambios viajan en los dos sentidos.
        await a.putGift('ga', 'De A');
        await b.putGift('gb', 'De B');
        await converge([a, b]);
        final ids = (await a.view()).gifts.map((g) => g.id).toSet();
        expect(ids, {'g1', 'ga', 'gb'});
      },
    );

    test(
      'A sigue mirando aunque se cierre y se abra la app antes de que B suba',
      () async {
        final a = await newPhone();
        await a.createFamily();
        await a.putGift('g1', 'Pijama');
        final text = await a.c.read(pairingServiceProvider).qrTextForPairing();
        a.phone.restart();
        a.c.read(syncControllerProvider); // arranca la sincronización

        final b = await newPhone();
        await b.c
            .read(pairingServiceProvider)
            .joinFromQr(text, deviceName: 'Móvil B');
        await converge([a, b]);
        expect((await b.gift('g1'))!.title, 'Pijama');
        expect((await a.family.future).paired, isTrue);
      },
    );

    test('pasado el sondeo, A mira solo al volver a la app; pasado el plazo, ya no mira', () async {
      final a = await newPhone(
        timing: const SyncTiming(
          debounce: Duration(milliseconds: 30),
          peerPoll: Duration(milliseconds: 30),
          peerPollFor: Duration(milliseconds: 150),
          peerWait: Duration(days: 3),
        ),
      );
      await a.createFamily();
      await a.c.read(pairingServiceProvider).qrTextForPairing();
      await eventually(() => (server.calls['get'] ?? 0) >= 1, reason: 'A mira');
      // El sondeo se acaba solo.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final afterPoll = server.calls['get']!;
      await settle();
      expect(server.calls['get'], afterPoll, reason: 'el sondeo ha parado');
      // Dentro del plazo, volver a la app mira una vez.
      await a.sync.syncNow();
      expect(server.calls['get'], afterPoll + 1);
      final prefs = a.c.read(sharedPreferencesProvider);
      expect(prefs.getStringList('sync.peerWait'), hasLength(1));
      // Cuatro días después ya no: vuelve a ser un solo móvil.
      final later = clock.now().add(const Duration(days: 4));
      await withClock(Clock.fixed(later), () async {
        await a.sync.syncNow();
        await a.sync.syncNow();
      });
      expect(server.calls['get'], afterPoll + 1);
      expect(server.calls.keys, {'get'});
      expect(a.status.phase, SyncPhase.waitingForPeer);
      // Y la marca de que se enseñó el QR se borra al caducar, no solo al
      // emparejarse.
      expect(prefs.getStringList('sync.peerWait'), isNull);
    });

    test(
      'los tiempos de serie: mira cada 12 s y deja de esperar a los 3 días',
      () {
        const timing = SyncTiming();
        expect(timing.peerPoll, const Duration(seconds: 12));
        expect(timing.peerWait, const Duration(days: 3));
      },
    );

    /// Un sondeo tan lento que cualquier `GET` de más sería un reintento.
    const slowPoll = SyncTiming(
      debounce: Duration(milliseconds: 30),
      backoff: [Duration(milliseconds: 30), Duration(milliseconds: 60)],
      peerPoll: Duration(hours: 1),
    );

    for (final (what, failure) in <(String, SyncTransportException?)>[
      ('sin red', null),
      ('con un 5xx', const SyncTransportException(SyncFailure.server, '503')),
      (
        'con un 429',
        const SyncTransportException(
          SyncFailure.rateLimited,
          '429',
          retryAfter: Duration(milliseconds: 40),
        ),
      ),
    ]) {
      test(
        'si la consulta falla $what no reintenta con espera creciente y sigue «a la espera»',
        () async {
          final a = await newPhone(timing: slowPoll);
          await a.createFamily();
          final phases = <SyncPhase>[];
          final sub = a.c.listen(
            syncControllerProvider,
            (_, next) => phases.add(next.phase),
          );
          addTearDown(sub.close);
          if (failure == null) {
            a.transport.offline = true;
          } else {
            a.transport.getError = failure;
          }
          await a.c.read(pairingServiceProvider).qrTextForPairing();
          await eventually(
            () => (server.calls['get'] ?? 0) >= 1,
            reason: 'A mira',
          );
          await settle();

          expect(server.calls['get'], 1, reason: 'ningún reintento');
          expect(server.calls.keys, {'get'});
          expect(a.status.phase, SyncPhase.waitingForPeer);
          expect(phases, isNot(contains(SyncPhase.offline)));
          expect(phases, isNot(contains(SyncPhase.error)));
        },
      );
    }

    test('tras un fallo sigue mirando con el sondeo normal y empareja cuando vuelve la red', () async {
      final a = await newPhone();
      await a.createFamily();
      a.transport.offline = true;
      final text = await a.c.read(pairingServiceProvider).qrTextForPairing();
      await eventually(
        () => (server.calls['get'] ?? 0) >= 2,
        reason: 'A sigue mirando',
      );
      expect(a.status.phase, SyncPhase.waitingForPeer);
      a.transport.offline = false;
      final b = await newPhone();
      await b.c
          .read(pairingServiceProvider)
          .joinFromQr(text, deviceName: 'Móvil B');
      await eventually(
        () async => (await a.family.future).paired,
        reason: 'A emparejado',
      );
    });

    test('en segundo plano, sin emparejar, no hace ninguna petición: ni sondeo, ni reintento, ni cambios pendientes', () async {
      final a = await newPhone(
        timing: const SyncTiming(
          debounce: Duration(milliseconds: 30),
          backoff: [Duration(milliseconds: 30)],
          peerPoll: Duration(milliseconds: 30),
        ),
      );
      await a.createFamily();
      await a.c.read(pairingServiceProvider).qrTextForPairing();
      await eventually(() => (server.calls['get'] ?? 0) >= 1, reason: 'A mira');
      // Falla la subida de una invitación: queda un reintento programado.
      a.transport.offline = true;
      await a.c.read(inviteHostProvider.notifier).create();
      expect(a.c.read(inviteHostProvider).phase, InvitePhase.failed);
      // Y un cambio local a medio agrupar.
      await a.putGift('g1', 'Pijama');
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.paused,
      );
      addTearDown(
        () => WidgetsBinding.instance.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      // Lo que estuviera en vuelo al pasar a segundo plano termina.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final calls = Map.of(server.calls);
      await settle();
      expect(server.calls, calls, reason: 'nada en segundo plano');

      // Al volver, mira otra vez.
      a.transport.offline = false;
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await eventually(
        () => server.calls['get']! > calls['get']!,
        reason: 'vuelve a mirar',
      );
      expect(a.status.phase, SyncPhase.waitingForPeer);
    });

    test('al entrar el otro, el móvil que enseñó el QR recibe el aviso de que se ha conectado; el que lo leyó, no', () async {
      final a = await newPhone();
      await a.createFamily();
      expect(a.c.read(peerConnectedProvider), isNull);
      final b = await newPhone();
      await b.joinFamilyOf(a);
      await eventually(
        () => a.c.read(peerConnectedProvider) != null,
        reason: 'el aviso en A',
      );
      await converge([a, b]);
      await settle();
      expect(b.c.read(peerConnectedProvider), isNull);
      // Se da una sola vez.
      a.c.read(peerConnectedProvider.notifier).consume();
      await a.putGift('g1', 'Pijama');
      await converge([a, b]);
      expect(a.c.read(peerConnectedProvider), isNull);
    });

    test('recibir un fichero .regalos del otro móvil también cuenta: empieza a sincronizar', () async {
      final a = await newPhone();
      await a.createFamily();
      await a.putGift('g1', 'Pijama');
      // B entra con la clave sin que A haya enseñado el QR en esta sesión (lo
      // leyó de otra forma) y sin red.
      final b = await newPhone();
      b.transport.offline = true;
      await b.family.joinFamily(
        payload: PairingPayload(
          listId: (await a.listId())!,
          key: a.family.familyKey!,
          deviceName: 'Móvil A',
        ),
        deviceName: 'Móvil B',
      );
      await b.putGift('g2', 'Libro');
      await settle();
      expect(a.transport.times, isEmpty, reason: 'A no ha pedido nada');
      expect(server.hasList(await syncIdOf(a)), isFalse);

      final envelope = await b.c.read(shareServiceProvider).buildEnvelope();
      await a.c.read(shareServiceProvider).importEnvelopeBytes(envelope);
      expect((await a.family.future).paired, isTrue);
      await eventually(
        () => a.status.phase == SyncPhase.synced,
        reason: 'A sincroniza al quedar emparejado',
      );
      final syncId = await syncIdOf(a);
      expect(server.hasList(syncId), isTrue);
      expect(server.watchers(syncId), 1);
      b.transport.offline = false;
      await b.sync.syncNow();
      await converge([a, b]);
    });
  });

  group('emparejar por invitación', () {
    InviteHostState host(SyncPhone p) => p.c.read(inviteHostProvider);
    InviteGuestState guest(SyncPhone p) => p.c.read(inviteGuestProvider);

    test('crear la invitación sube la lista (hace falta para invitar), pero los cambios siguientes esperan al segundo móvil', () async {
      final a = await newPhone();
      await a.createFamily();
      await a.putGift('g1', 'Pijama');
      await settle();
      expect(server.calls, isEmpty);

      await a.c.read(inviteHostProvider.notifier).create();
      expect(host(a).phase, InvitePhase.waiting, reason: '${host(a).issue}');
      final syncId = await syncIdOf(a);
      expect(server.hasList(syncId), isTrue);
      expect(server.versionOf(syncId), 1);

      // Mientras nadie entra, lo que se edita no sube.
      await a.putGift('g2', 'Libro');
      await settle();
      expect(server.versionOf(syncId), 1);
      expect(server.calls['put'], 1);
      expect(a.status.phase, SyncPhase.waitingForPeer);
      expect((await a.family.future).paired, isFalse);
    });

    test('al dar acceso empieza la sincronización y el invitado recibe todo, también lo editado mientras esperaba', () async {
      final a = await newPhone();
      await a.createFamily();
      await a.putGift('g1', 'Pijama');
      await a.c.read(inviteHostProvider.notifier).create();
      final link = host(a).link!;
      await a.putGift('g2', 'Editado mientras esperaba');

      final b = await newPhone();
      final sub = b.c.listen(inviteGuestProvider, (_, _) {});
      addTearDown(sub.close);
      await b.c
          .read(inviteGuestProvider.notifier)
          .begin(link, deviceName: 'Móvil de Marta');
      await eventually(
        () => host(a).phase == InvitePhase.request,
        reason: 'la petición',
      );
      await eventually(
        () => guest(b).phase == JoinPhase.compare,
        reason: 'el código en B',
      );
      await a.c.read(inviteHostProvider.notifier).approve();
      expect((await a.family.future).paired, isTrue);
      await eventually(
        () => guest(b).phase == JoinPhase.joined,
        reason: 'que B entre',
      );

      await converge([a, b]);
      expect((await b.gift('g1'))!.title, 'Pijama');
      expect((await b.gift('g2'))!.title, 'Editado mientras esperaba');
      final syncId = await syncIdOf(a);
      await eventually(
        () => server.watchers(syncId) == 2,
        reason: 'dos WebSocket',
      );
      await b.putGift('g3', 'De B');
      await converge([a, b]);
      expect((await a.gift('g3'))!.title, 'De B');
    });
  });

  group('una invitación que acaba sin emparejar a nadie', () {
    InviteHostState host(SyncPhone p) => p.c.read(inviteHostProvider);

    Future<(SyncPhone, String)> invited() async {
      final a = await newPhone();
      await a.createFamily();
      await a.putGift('g1', 'Pijama');
      await a.c.read(inviteHostProvider.notifier).create();
      expect(host(a).phase, InvitePhase.waiting, reason: '${host(a).issue}');
      final syncId = await syncIdOf(a);
      expect(server.hasList(syncId), isTrue);
      return (a, syncId);
    }

    test('si caduca, se borra del servidor la copia que subió', () async {
      final (a, syncId) = await invited();
      server.expireInvites();
      await eventually(
        () => host(a).phase == InvitePhase.expired,
        reason: 'caducada',
      );
      await eventually(
        () => !server.hasList(syncId),
        reason: 'la copia se borra',
      );
      expect(server.calls['delete'], 1);
      await settle();
      expect(a.status.phase, SyncPhase.waitingForPeer);
      // Lo local sigue en su sitio.
      expect((await a.gift('g1'))!.title, 'Pijama');
    });

    test('si se cancela o se rechaza, también', () async {
      final (a, syncId) = await invited();
      await a.c.read(inviteHostProvider.notifier).reject();
      expect(host(a).phase, InvitePhase.rejected);
      await eventually(
        () => !server.hasList(syncId),
        reason: 'la copia se borra',
      );
      expect(server.openInvites, 0);
    });

    test('se puede volver a invitar después: la lista sube otra vez', () async {
      final (a, syncId) = await invited();
      await a.c.read(inviteHostProvider.notifier).reject();
      await eventually(() => !server.hasList(syncId));
      a.c.read(inviteHostProvider.notifier).dismiss();
      await a.c.read(inviteHostProvider.notifier).create();
      expect(host(a).phase, InvitePhase.waiting, reason: '${host(a).issue}');
      expect(server.hasList(syncId), isTrue);
    });

    test('con otro móvil ya emparejado no se borra nada', () async {
      final a = await newPhone();
      await a.createPairedFamily();
      final syncId = await syncIdOf(a);
      await a.c.read(inviteHostProvider.notifier).create();
      expect(host(a).phase, InvitePhase.waiting, reason: '${host(a).issue}');
      await a.c.read(inviteHostProvider.notifier).reject();
      await settle();
      expect(server.hasList(syncId), isTrue);
      expect(server.calls['delete'], isNull);
    });

    test('N8: al arrancar con una invitación que caducó con la app cerrada se olvida y se borra su copia del servidor', () async {
      final (a, syncId) = await invited();
      a.phone.restart();
      final later = clock.now().add(const Duration(days: 2));
      await withClock(Clock.fixed(later), () async {
        // Basta con que arranque la sincronización: no hace falta abrir la
        // pantalla de invitar.
        a.c.read(syncControllerProvider);
        await eventually(
          () => !server.hasList(syncId),
          reason: 'la copia se borra al arrancar',
        );
        expect(a.c.read(inviteHostProvider).phase, InvitePhase.idle);
        await settle();
      });
      expect(host(a).phase, InvitePhase.idle);
      expect(server.calls['delete'], 1);
      final prefs = a.c.read(sharedPreferencesProvider);
      expect(prefs.getString('sync.activeInvite'), isNull);
      expect(prefs.getStringList('sync.inviteCopy'), isNull);
      expect(a.status.phase, SyncPhase.waitingForPeer);
    });

    test(
      'al arrancar con la invitación todavía viva no se borra nada',
      () async {
        final (a, syncId) = await invited();
        a.phone.restart();
        a.c.read(syncControllerProvider);
        await settle();
        WidgetsBinding.instance.handleAppLifecycleStateChanged(
          AppLifecycleState.paused,
        );
        WidgetsBinding.instance.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await settle();
        expect(server.hasList(syncId), isTrue);
        expect(server.calls['delete'], isNull);
      },
    );

    test('N7: si otro móvil ya ha escrito en la lista, la copia no se borra: es la lista de los dos', () async {
      // A no sondea (un día entre consultas): solo se entera al ir a borrar.
      final a = await newPhone(
        timing: const SyncTiming(
          debounce: Duration(milliseconds: 30),
          inviteHostPoll: Duration(milliseconds: 30),
          peerPoll: Duration(days: 1),
        ),
      );
      await a.createFamily();
      await a.putGift('g1', 'Pijama');
      await a.c.read(inviteHostProvider.notifier).create();
      expect(host(a).phase, InvitePhase.waiting, reason: '${host(a).issue}');
      final syncId = await syncIdOf(a);
      expect(server.versionOf(syncId), 1);
      // Mientras la invitación espera, B entra leyendo el QR y sube su copia.
      final b = await newPhone();
      await b.joinFamilyOf(a);
      await b.putGift('g2', 'De B');
      await eventually(() => server.versionOf(syncId)! >= 2, reason: 'B sube');
      await settle();
      expect(
        (await a.family.future).paired,
        isFalse,
        reason: 'A aún no lo sabe',
      );
      // La invitación se rechaza: antes de borrar, A mira y ve que la lista
      // ya no es solo suya.
      await a.c.read(inviteHostProvider.notifier).reject();
      await eventually(
        () async => (await a.family.future).paired,
        reason: 'A emparejado',
      );
      await settle();
      expect(server.hasList(syncId), isTrue);
      expect(server.calls['delete'], isNull);
      expect(
        a.c.read(sharedPreferencesProvider).getStringList('sync.inviteCopy'),
        isNull,
      );
      await converge([a, b]);
      expect((await a.gift('g2'))!.title, 'De B');
      expect((await b.gift('g1'))!.title, 'Pijama');
    });

    test('si el borrado falla, queda pendiente y se reintenta al volver a primer plano', () async {
      final (a, syncId) = await invited();
      a.transport.deleteError = const SyncTransportException(
        SyncFailure.server,
        '503',
      );
      await a.c.read(inviteHostProvider.notifier).reject();
      await eventually(
        () => server.calls['delete'] == 1,
        reason: 'intenta borrar',
      );
      await settle();
      expect(server.hasList(syncId), isTrue, reason: 'el borrado falló');
      final prefs = a.c.read(sharedPreferencesProvider);
      expect(prefs.getStringList('sync.inviteCopy'), hasLength(1));
      // Sin volver a la app no insiste.
      await settle();
      expect(server.calls['delete'], 1);
      a.transport.deleteError = null;
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.paused,
      );
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await eventually(
        () => !server.hasList(syncId),
        reason: 'se borra al volver',
      );
      await settle();
      expect(prefs.getStringList('sync.inviteCopy'), isNull);
      expect(server.calls['delete'], 2);
      expect(a.status.phase, SyncPhase.waitingForPeer);
    });

    test(
      'si el borrado falla y la app se cierra, se reintenta al arrancar',
      () async {
        final (a, syncId) = await invited();
        a.transport.offline = true;
        await a.c.read(inviteHostProvider.notifier).reject();
        await settle();
        expect(server.hasList(syncId), isTrue);
        a.phone.restart();
        a.transport.offline = false;
        a.c.read(syncControllerProvider);
        await eventually(
          () => !server.hasList(syncId),
          reason: 'se borra al arrancar',
        );
        await settle();
        expect(
          a.c.read(sharedPreferencesProvider).getStringList('sync.inviteCopy'),
          isNull,
        );
        // Lo local sigue en su sitio.
        expect((await a.gift('g1'))!.title, 'Pijama');
      },
    );

    test('si crear la invitación falla después de subir la lista, la copia se borra en ese mismo fallo', () async {
      final a = await newPhone();
      await a.createFamily();
      await a.putGift('g1', 'Pijama');
      final syncId = await syncIdOf(a);
      a.transport.inviteError = const SyncTransportException(
        SyncFailure.server,
        '500',
      );
      await a.c.read(inviteHostProvider.notifier).create();
      expect(host(a).phase, InvitePhase.failed);
      expect(server.calls['put'], 1, reason: 'la lista llegó a subir');
      await eventually(
        () => !server.hasList(syncId),
        reason: 'la copia se borra',
      );
      await settle();
      expect(server.calls['delete'], 1);
      expect(
        a.c.read(sharedPreferencesProvider).getStringList('sync.inviteCopy'),
        isNull,
      );
      // Y se puede volver a intentar.
      a.transport.inviteError = null;
      a.c.read(inviteHostProvider.notifier).dismiss();
      await a.c.read(inviteHostProvider.notifier).create();
      expect(host(a).phase, InvitePhase.waiting, reason: '${host(a).issue}');
      expect(server.hasList(syncId), isTrue);
    });
  });

  group('móviles que ya estaban emparejados', () {
    test(
      'siguen sincronizando igual al abrir la app: suben, escuchan y reciben',
      () async {
        final a = await newPhone();
        await a.createFamily();
        final b = await newPhone();
        await b.joinFamilyOf(a);
        await converge([a, b]);
        await eventually(() async => (await a.family.future).paired);
        await eventually(
          () =>
              a.status.phase == SyncPhase.synced &&
              b.status.phase == SyncPhase.synced,
        );
        final syncId = await syncIdOf(a);

        // Los dos se cierran y se abren (la app actualizada arranca con el
        // emparejado ya guardado).
        for (final p in [a, b]) {
          p.phone.restart();
          p.c.read(syncControllerProvider);
        }
        await eventually(
          () =>
              a.status.phase == SyncPhase.synced &&
              b.status.phase == SyncPhase.synced,
          reason: 'sincronizan al arrancar',
        );
        await eventually(
          () => server.watchers(syncId) == 2,
          reason: 'reabren el WebSocket',
        );
        final version = server.versionOf(syncId)!;
        await a.putGift('g1', 'Tras actualizar');
        await converge([a, b]);
        expect((await b.gift('g1'))!.title, 'Tras actualizar');
        expect(server.versionOf(syncId), greaterThan(version));
      },
    );

    test('un móvil emparejado sin ninguna espera guardada sube al arrancar, aunque el servidor haya perdido la lista', () async {
      final a = await newPhone();
      await a.createPairedFamily();
      final syncId = await syncIdOf(a);
      a.phone.restart();
      server.expireList(syncId);
      a.c.read(syncControllerProvider);
      await eventually(
        () => server.hasList(syncId),
        reason: 'la vuelve a subir',
      );
      await eventually(() => server.watchers(syncId) == 1);
    });
  });
}
