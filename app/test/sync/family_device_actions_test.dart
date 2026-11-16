// Aprobar un móvil y ver qué pasaría al quitar otro (fase 3, lote «Móviles»):
// la API en Dart puro que usa SyncController, sobre móviles en memoria.
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/features/sync/application/family_device_actions.dart';
import 'package:regalos/features/sync/application/family_devices.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';

import '../helpers/fake_worker_v2.dart';
import 'v2_harness.dart';

void main() {
  late FakeWorkerV2 worker;
  late SyncV2Client client;
  late MemoryV2Phone aritz;
  late MemoryV2Phone leo;
  late MemoryV2Phone nora;

  Future<void> build({required bool vouchEveryone}) async {
    worker = FakeWorkerV2();
    client = worker.client();
    final key = await FamilyKey.generate();
    aritz = await MemoryV2Phone.create(
      'aritz-phone',
      'aritz',
      1,
      familyKey: key,
      migrated: true,
    );
    leo = await MemoryV2Phone.create('leo-phone', 'leo', 2, familyKey: key);
    nora = await MemoryV2Phone.create('nora-phone', 'nora', 3, familyKey: key);
    aritz
      ..addPerson('aritz', 'Aritz')
      ..addPerson('leo', 'Leo')
      ..addPerson('nora', 'Nora');
    if (vouchEveryone) {
      await vouchAll([aritz, leo, nora]);
    } else {
      // Cadena Aritz - Leo - Nora: Nora solo está avalada por Leo.
      var registry = DeviceRegistry.empty(kV2List);
      for (final p in [aritz, leo, nora]) {
        registry = await registry.merge(p.reg);
      }
      Future<DeviceRegistry> vouch(
        DeviceRegistry r,
        MemoryV2Phone by,
        MemoryV2Phone other,
      ) async => r.withVouch(
        await Vouch.create(
          keys: by.keys,
          voucher: by.record,
          record: other.record,
        ),
      );
      registry = await vouch(registry, aritz, leo);
      registry = await vouch(registry, leo, aritz);
      registry = await vouch(registry, leo, nora);
      registry = await vouch(registry, nora, leo);
      for (final p in [aritz, leo, nora]) {
        p.reg = registry;
      }
    }
    await aritz.engine(client).ensureCreated();
    for (final p in [leo, nora]) {
      worker.addCredentialForTesting(
        kV2Sync,
        p.identity.deviceId,
        p.keys.serviceCredential,
      );
    }
  }

  /// Nora pasa a «sin persona» (ficha 2) y la publica.
  Future<void> noraChangesPerson() async {
    final change = await changePerson(
      registry: nora.reg,
      view: await nora.view(),
      myKeys: nora.keys,
      personId: null,
    );
    nora.reg = change.registry;
    await nora.engine(client).sync();
  }

  group('previewRemoval', () {
    setUp(() => build(vouchEveryone: true));

    test('no hace nada: ni toca el registro ni el servidor', () async {
      final before = aritz.reg;
      final calls = Map.of(worker.calls);
      final preview = await previewRemoval(
        local: aritz,
        deviceId: 'nora-phone',
      );
      expect(preview.selfWouldWait, isFalse);
      expect(preview.orphans, isEmpty);
      expect(identical(aritz.reg, before), isTrue);
      expect(worker.calls, calls);
      expect((await aritz.view()).revoked, isEmpty);
    });

    test('no se puede quitar este móvil', () async {
      await expectLater(
        previewRemoval(local: aritz, deviceId: 'aritz-phone'),
        throwsA(isA<RegistryException>()),
      );
    });
  });

  group('N7: el único que aprobó la ficha actual', () {
    setUp(() => build(vouchEveryone: true));

    test('avisa solo si el que se quita es el único que la aprobó', () async {
      await noraChangesPerson();
      // Nadie la ha aprobado aún: no hay nada que perder.
      await aritz.engine(client).sync();
      expect((await aritz.view()).pending.map((d) => d.deviceId), [
        'nora-phone',
      ]);
      expect((await nora.view()).selfApproved, isFalse);
      expect(
        (await previewRemoval(
          local: nora,
          deviceId: 'aritz-phone',
        )).selfWouldWait,
        isFalse,
      );

      // Aritz la aprueba: es el único que la aprobó.
      await approveFamilyDevice(
        transport: client,
        local: aritz,
        deviceId: 'nora-phone',
      );
      await nora.engine(client).sync();
      expect((await nora.view()).selfApproved, isTrue);
      expect(
        (await previewRemoval(
          local: nora,
          deviceId: 'aritz-phone',
        )).selfWouldWait,
        isTrue,
        reason: 'si se quita a Aritz, Nora vuelve a esperar',
      );
      expect(
        (await previewRemoval(
          local: nora,
          deviceId: 'leo-phone',
        )).selfWouldWait,
        isFalse,
        reason: 'Leo no la había aprobado',
      );

      // Con Leo también, ya no es el único.
      await leo.engine(client).sync();
      await approveFamilyDevice(
        transport: client,
        local: leo,
        deviceId: 'nora-phone',
      );
      await nora.engine(client).sync();
      expect(
        (await previewRemoval(
          local: nora,
          deviceId: 'aritz-phone',
        )).selfWouldWait,
        isFalse,
      );
    });
  });

  group('approveFamilyDevice', () {
    setUp(() => build(vouchEveryone: true));

    test(
      'un pendiente: aprueba solo ese móvil y publica el registro',
      () async {
        await noraChangesPerson();
        await aritz.engine(client).sync();
        final before = await aritz.view();
        expect(before.pending, hasLength(1));
        final out = await approveFamilyDevice(
          transport: client,
          local: aritz,
          deviceId: 'nora-phone',
        );
        expect(out.rotates, isFalse);
        final after = await aritz.view();
        expect(after.pending, isEmpty);
        expect(after.member('nora-phone'), isNotNull);
        // Leo ve la aprobación al sincronizar: se publicó.
        await leo.engine(client).sync();
        expect((await leo.view()).pending, isEmpty);
      },
    );

    test('no aprueba este móvil, uno revocado ni uno desconocido', () async {
      await expectLater(
        approveFamilyDevice(
          transport: client,
          local: aritz,
          deviceId: 'aritz-phone',
        ),
        throwsA(isA<RegistryException>()),
      );
      await expectLater(
        approveFamilyDevice(
          transport: client,
          local: aritz,
          deviceId: 'otro-phone',
        ),
        throwsA(isA<RegistryException>()),
      );
      await removeDevice(
        transport: client,
        local: aritz,
        deviceId: 'nora-phone',
      );
      await expectLater(
        approveFamilyDevice(
          transport: client,
          local: aritz,
          deviceId: 'nora-phone',
        ),
        throwsA(isA<RegistryException>()),
      );
    });

    test('el aval va ligado a la ficha que se enseñó: si el móvil publica '
        'otra entre tanto, no se avala', () async {
      await noraChangesPerson();
      await aritz.engine(client).sync();
      final shown = (await aritz.view()).device('nora-phone')!.recordDigest;
      // Mientras Aritz mira «¿Este móvil es de Leo?», Nora publica otra
      // ficha (ahora de Leo) que antes no era la que se enseñó.
      final change = await changePerson(
        registry: nora.reg,
        view: await nora.view(),
        myKeys: nora.keys,
        personId: 'leo',
      );
      nora.reg = change.registry;
      await nora.engine(client).sync();
      await aritz.engine(client).sync();
      final current = (await aritz.view()).device('nora-phone')!.recordDigest;
      expect(current, isNot(shown));

      await expectLater(
        approveFamilyDevice(
          transport: client,
          local: aritz,
          deviceId: 'nora-phone',
          recordDigest: shown,
        ),
        throwsA(
          isA<RegistryException>().having(
            (e) => e.message,
            'message',
            kRecordChangedMessage,
          ),
        ),
      );
      expect(
        (await aritz.view()).member('nora-phone'),
        isNull,
        reason: 'no se avaló nada',
      );

      // Con la ficha que ahora se enseña, sí.
      await approveFamilyDevice(
        transport: client,
        local: aritz,
        deviceId: 'nora-phone',
        recordDigest: current,
      );
      expect((await aritz.view()).member('nora-phone'), isNotNull);
    });

    test('si la vuelta falla tras guardar el aval, sigue aprobado y se '
        'publicará con conexión', () async {
      await noraChangesPerson();
      await aritz.engine(client).sync();
      final digest = (await aritz.view()).device('nora-phone')!.recordDigest;
      final down = SyncV2Client(
        base: client.base,
        sendRequest: (method, uri, {body, headers = const {}}) async =>
            throw StateError('sin vuelta'),
      );
      final out = await approveFamilyDevice(
        transport: down,
        local: aritz,
        deviceId: 'nora-phone',
        recordDigest: digest,
      );
      expect(out.rotates, isFalse);
      expect((await aritz.view()).member('nora-phone'), isNotNull);
      // La siguiente vuelta lo publica.
      await aritz.engine(client).sync();
      await leo.engine(client).sync();
      expect((await leo.view()).pending, isEmpty);
    });
  });

  group('huérfanos tras quitar', () {
    setUp(() => build(vouchEveryone: false));

    test('se enseñan al quitar y se aprueban uno a uno con su ficha', () async {
      final preview = await previewRemoval(local: aritz, deviceId: 'leo-phone');
      expect(preview.orphans.map((d) => d.deviceId), ['nora-phone']);
      final change = await removeDevice(
        transport: client,
        local: aritz,
        deviceId: 'leo-phone',
      );
      final orphan = change.orphans.single;
      expect(orphan.deviceId, 'nora-phone');
      expect(orphan.personId, 'nora');
      // Ya no sale en la vista: sin la ficha mostrada no hay qué aprobar.
      final view = await aritz.view();
      expect(view.device('nora-phone'), isNull);
      await expectLater(
        approveFamilyDevice(
          transport: client,
          local: aritz,
          deviceId: 'nora-phone',
        ),
        throwsA(isA<RegistryException>()),
      );
      // Una ficha de otro móvil no vale para este.
      await expectLater(
        approveFamilyDevice(
          transport: client,
          local: aritz,
          deviceId: 'nora-phone',
          recordDigest: aritz.record.digest,
        ),
        throwsA(isA<RegistryException>()),
      );

      await approveFamilyDevice(
        transport: client,
        local: aritz,
        deviceId: 'nora-phone',
        recordDigest: orphan.recordDigest,
      );
      final after = await aritz.view();
      expect(after.member('nora-phone'), isNotNull);
      expect(after.revoked, contains('leo-phone'));
    });
  });

  group('quitar con la red caída', () {
    setUp(() => build(vouchEveryone: false));

    SyncV2Client down({required List<String> seen}) => SyncV2Client(
      base: client.base,
      sendRequest: (method, uri, {body, headers = const {}}) async {
        seen.add('$method ${uri.path}');
        throw const SyncTransportException(SyncFailure.network, 'sin red');
      },
    );

    test('si no se puede guardar la intención de revocar, no se revoca nada '
        'aunque los huérfanos ya se hubieran preparado', () async {
      aritz.failSaveState = true;
      var prepared = 0;
      await expectLater(
        removeDevice(
          transport: client,
          local: aritz,
          deviceId: 'leo-phone',
          rememberOrphans: (orphans) async => prepared = orphans.length,
        ),
        throwsA(isA<StateError>()),
      );
      expect(prepared, 1, reason: 'se prepararon antes de guardar');
      expect((await aritz.view()).revoked, isEmpty);
      expect(aritz.state.pendingRevocations, isEmpty);
    });

    test('los huérfanos se anotan antes de hablar con la red y la revocación '
        'queda guardada y pendiente', () async {
      final seen = <String>[];
      List<KnownDevice>? remembered;
      var requestsWhenRemembered = -1;
      await expectLater(
        removeDevice(
          transport: down(seen: seen),
          local: aritz,
          deviceId: 'leo-phone',
          rememberOrphans: (orphans) async {
            remembered = orphans;
            requestsWhenRemembered = seen.length;
          },
        ),
        throwsA(isA<SyncTransportException>()),
      );
      expect(requestsWhenRemembered, 0, reason: 'antes de la primera petición');
      expect(remembered!.map((d) => d.deviceId), ['nora-phone']);
      expect(remembered!.single.recordDigest, nora.record.digest);
      // Quitado en este móvil; el corte del servidor sigue pendiente.
      expect((await aritz.view()).revoked, contains('leo-phone'));
      final state = await aritz.readState();
      expect(state.pendingRevocations, {'leo-phone'});
      // Con red, el motor corta el acceso.
      await aritz.engine(client).sync();
      expect(worker.devicesOf(kV2Sync)['leo-phone'], isTrue);
      expect((await aritz.readState()).pendingRevocations, isEmpty);
    });
  });
}
