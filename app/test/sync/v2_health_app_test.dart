import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/sync/application/app_sync_v2_local.dart';
import 'package:regalos/features/sync/application/family_device_review.dart';
import 'package:regalos/features/sync/application/family_device_actions.dart'
    show approveFamilyDevice, DeviceRemovalChangedException;
import 'package:regalos/features/sync/application/sync_controller.dart';
import 'package:regalos/features/sync/application/sync_v2_engine.dart';
import 'package:regalos/features/sync/application/v2_health_provider.dart';
import 'package:regalos/features/sync/application/v2_resolution_actions.dart';
import 'package:regalos/features/sync/data/sync_config.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';
import 'package:regalos/features/sync/data/sync_transport_common.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';

import '../helpers/fake_worker_v2.dart';
import '../helpers/fake_sync_server.dart';
import '../helpers/memory_stores.dart';
import '../helpers/pump_app.dart' show mockPrefs;
import 'v2_harness.dart';

final _local = FutureProvider((ref) => AppSyncV2Local.load(ref));

class _Secrets extends MemorySecretStore {
  String? failWrite;
  bool failFinish = false;

  @override
  Future<void> write(String key, String value) async {
    if (key == failWrite) {
      failWrite = null;
      throw StateError('cierre simulado');
    }
    await super.write(key, value);
  }

  @override
  Future<void> delete(String key) async {
    if (key == 'family.selfPersonChange' && failFinish) {
      failFinish = false;
      throw StateError('cierre simulado');
    }
    await super.delete(key);
  }
}

class _Files extends MemoryFileStore {
  bool failRegistry = false;
  bool failAfterWrite = false;
  String? failDelete;

  @override
  Future<void> delete(String name) async {
    if (name == failDelete) {
      failDelete = null;
      throw StateError('cierre simulado');
    }
    await super.delete(name);
  }

  @override
  Future<void> writeAtomic(String name, Uint8List bytes) async {
    if (name == 'family.registry' && failRegistry) {
      failRegistry = false;
      if (failAfterWrite) await super.writeAtomic(name, bytes);
      throw StateError('cierre simulado');
    }
    await super.writeAtomic(name, bytes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeWorkerV2 worker;
  late MemoryV2Phone a;
  late MemoryV2Phone b;
  late MemoryV2Phone c;
  late FakePhone phone;
  late _Secrets secrets;
  late _Files files;
  late SyncV2Client client;
  Future<void> Function(String method, Uri uri)? beforeRequest;

  FamilyController family() =>
      phone.container.read(familyControllerProvider.notifier);
  FamilyStore store() => phone.container.read(familyStoreProvider);
  Future<AppSyncV2Local> local() async =>
      (await phone.container.read<Future<AppSyncV2Local?>>(_local.future))!;
  DeviceRecord selfRecordOf(DeviceRegistry registry) =>
      (registry.records.where((r) => r.deviceId == 'aritz-phone').toList()
            ..sort((a, b) => b.seq.compareTo(a.seq)))
          .first;
  Future<V2Health> health() => phone.container.read(v2HealthProvider.future);
  Future<int> epochOf(DeviceRegistry registry) async => (await registry.viewFor(
    me: 'aritz-phone',
    mySigningKey: a.keys.publicKeys.signing,
    livePeople: const {'aritz', 'nora', 'leo'},
  )).epoch;
  Future<void> sync() async {
    await SyncV2Engine(transport: client, local: await local()).sync();
    phone.container.invalidate(localRegistryViewProvider);
  }

  setUp(() async {
    worker = FakeWorkerV2();
    beforeRequest = null;
    client = SyncV2Client(
      base: Uri.parse('https://sync.test'),
      sendRequest: (method, uri, {body, headers = const {}}) async {
        await beforeRequest?.call(method, uri);
        return worker.send(method, uri, body: body, headers: headers);
      },
      openSocket: worker.socket,
    );
    final key = await FamilyKey.generate();
    a = await MemoryV2Phone.create(
      'aritz-phone',
      'aritz',
      1,
      familyKey: key,
      migrated: true,
    );
    b = await MemoryV2Phone.create('leo-phone', 'leo', 2, familyKey: key);
    c = await MemoryV2Phone.create('nora-phone', 'nora', 3, familyKey: key);
    a.addPerson('aritz', 'Aritz');
    a.addPerson('nora', 'Nora');
    a.addPerson('leo', 'Leo');
    await vouchAll([a, b, c]);
    a.keyring = SurpriseKeyring([
      SurpriseKey(
        personId: 'nora',
        epoch: 1,
        bytes: List.filled(32, 42),
        audience: const ['aritz-phone', 'leo-phone'],
      ),
    ]);
    b.keyring = a.keyring;
    await a.engine(worker.client()).ensureCreated();
    for (final p in [b, c]) {
      worker.addCredentialForTesting(
        kV2Sync,
        p.identity.deviceId,
        p.keys.serviceCredential,
      );
    }
    secrets = _Secrets();
    files = _Files();
    phone = FakePhone(
      secrets: secrets,
      files: files,
      prefs: await mockPrefs(),
      extraOverrides: [
        syncTransportProvider.overrideWithValue(FakeSyncServer().connect()),
        syncV2TransportProvider.overrideWithValue(client),
      ],
    );
    addTearDown(phone.dispose);
    await phone.container.read(familyControllerProvider.future);
    await family().installV2(
      listId: kV2List,
      node: a.node,
      key: key,
      doc: a.doc,
      paired: true,
    );
    await phone.container.read(deviceKeysStoreProvider).restore(a.keys);
    await family().setSelfRecipient('aritz');
    await store().saveRegistry(a.reg);
    await store().saveSyncV2(a.identity);
    await phone.container
        .read(deviceKeysStoreProvider)
        .updateKeyring(kV2List, (_) => a.keyring);
    await store().saveScope('nora', FamilyDoc.empty(kV2List));
  });

  test(
    'el controlador publica los avisos a quien ya escucha el proveedor',
    () async {
      final subscription = phone.container.listen(v2HealthProvider, (_, _) {});
      addTearDown(subscription.close);
      expect((await health()).unbackedCredentials, isEmpty);
      worker.addCredentialForTesting(kV2Sync, 'unknown-phone', Uint8List(32));
      await phone.container.read(syncControllerProvider.notifier).syncNow();
      expect((await health()).unbackedCredentials, contains('unknown-phone'));
    },
  );

  test('avisos del servicio tras vuelta y reinicio sin red; desaparecen al resolver', () async {
    worker.addCredentialForTesting(kV2Sync, 'unknown-phone', Uint8List(32));
    await worker.client().revoke(a.auth, 'leo-phone');
    worker.fillGenerationForTesting(kV2Sync, credentials: 48);
    await sync();
    var h = await health();
    expect(h.unbackedCredentials, contains('unknown-phone'));
    expect(h.departedDevices, contains('leo-phone'));
    expect(h.renewSuggested, isTrue);
    expect(() => h.unbackedCredentials.add('x'), throwsUnsupportedError);
    phone.restart();
    worker.offline = true;
    h = await health();
    expect(h.unbackedCredentials, contains('unknown-phone'));
    expect(h.departedDevices, contains('leo-phone'));
    expect(h.renewSuggested, isTrue);
    worker.offline = false;
    final actions = phone.container.read(v2ResolutionActionsProvider);
    await actions.revokeUnbackedCredential('unknown-phone');
    await actions.completeDeparture('leo-phone');
    final epoch = (await phone.container.read(
      localRegistryViewProvider.future,
    ))!.epoch;
    await actions.revokeUnbackedCredential('unknown-phone');
    await actions.completeDeparture('leo-phone');
    expect(
      (await phone.container.read(localRegistryViewProvider.future))!.epoch,
      epoch,
    );
    h = await health();
    expect(h.unbackedCredentials, isEmpty);
    expect(h.departedDevices, isEmpty);
    expect(worker.devicesOf(kV2Sync)['unknown-phone'], isTrue);
  });

  test(
    'credencial sin respaldo: fallo de red conserva cola y reiniciar reintenta',
    () async {
      worker.addCredentialForTesting(kV2Sync, 'unknown-phone', Uint8List(32));
      await sync();
      worker.offline = true;
      await expectLater(
        phone.container
            .read(v2ResolutionActionsProvider)
            .revokeUnbackedCredential('unknown-phone'),
        throwsException,
      );
      expect(
        (await local()).readState().then((s) => s.pendingUnbackedRevocations),
        completion(contains('unknown-phone')),
      );
      phone.restart();
      worker.offline = false;
      await sync();
      expect(worker.devicesOf(kV2Sync)['unknown-phone'], isTrue);
      expect(
        (await (await local()).readState()).pendingUnbackedRevocations,
        isEmpty,
      );
    },
  );

  for (final retry in ['new', 'pending', 'legacy']) {
    test(
      'respaldo remoto sobrevenido cancela la resolución (reinicio: $retry)',
      () async {
        final d = await MemoryV2Phone.create(
          'unknown-phone',
          'leo',
          4,
          familyKey: a.familyKey,
        );
        worker.addCredentialForTesting(
          kV2Sync,
          'unknown-phone',
          d.keys.serviceCredential,
        );
        await sync();
        expect((await health()).unbackedCredentials, contains('unknown-phone'));
        if (retry != 'new') {
          worker.offline = true;
          await expectLater(
            phone.container
                .read(v2ResolutionActionsProvider)
                .revokeUnbackedCredential('unknown-phone'),
            throwsException,
          );
          expect(
            (await (await local()).readState()).pendingRevocations,
            isEmpty,
          );
          expect(
            (await (await local()).readState()).pendingUnbackedRevocations,
            {'unknown-phone'},
          );
          if (retry == 'legacy') {
            final state = await (await local()).readState();
            await (await local()).saveState(
              state.copyWith(
                pendingRevocations: state.pendingUnbackedRevocations,
                pendingUnbackedRevocations: {},
              ),
            );
          }
          phone.restart();
          worker.offline = false;
        }
        await vouchAll([a, b, c, d]);
        await b.engine(worker.client()).sync();
        final revokes = worker.calls['POST revoke'] ?? 0;
        expect(
          (await (await local()).registry()).records.where(
            (r) => r.deviceId == 'unknown-phone',
          ),
          isEmpty,
        );
        if (retry != 'new') {
          await phone.container.read(syncControllerProvider.notifier).syncNow();
        } else {
          await phone.container
              .read(v2ResolutionActionsProvider)
              .revokeUnbackedCredential('unknown-phone');
        }
        expect(worker.devicesOf(kV2Sync)['unknown-phone'], isFalse);
        expect(worker.calls['POST revoke'] ?? 0, revokes);
        expect(
          (await (await local()).readState()).pendingUnbackedRevocations,
          isEmpty,
        );
        expect((await health()).unbackedCredentials, isEmpty);
      },
    );
  }

  test('revokeUnbackedCredential dice qué ha pasado: revoked, '
      'alreadyResolved y knownMember', () async {
    worker.addCredentialForTesting(kV2Sync, 'unknown-phone', Uint8List(32));
    worker.addCredentialForTesting(kV2Sync, 'old-member', Uint8List(32));
    await sync();
    final actions = phone.container.read(v2ResolutionActionsProvider);

    // Nada que ver con la lista: ya estaba resuelto.
    expect(
      await actions.revokeUnbackedCredential('not-listed'),
      UnbackedRevocation.alreadyResolved,
    );

    // Un móvil que este ya conoció como miembro, aunque el registro no lo
    // enseñe: no se corta y se dice.
    final state = await (await local()).readState();
    await (await local()).saveState(
      state.copyWith(knownMembers: {...state.knownMembers, 'old-member'}),
    );
    final revokes = worker.calls['POST revoke'] ?? 0;
    expect(
      (await phone.container.read(localRegistryViewProvider.future))!
          .device('old-member'),
      isNull,
    );
    expect(
      await actions.revokeUnbackedCredential('old-member'),
      UnbackedRevocation.knownMember,
    );
    expect(worker.devicesOf(kV2Sync)['old-member'], isFalse);
    expect(worker.calls['POST revoke'] ?? 0, revokes);
    expect(
      (await (await local()).readState()).pendingUnbackedRevocations,
      isEmpty,
    );

    // Un acceso sin respaldo de verdad sí se corta.
    expect(
      await actions.revokeUnbackedCredential('unknown-phone'),
      UnbackedRevocation.revoked,
    );
    expect(worker.devicesOf(kV2Sync)['unknown-phone'], isTrue);
  });

  test(
    'un registro remoto ilegible conserva la intención y no revoca',
    () async {
      worker.addCredentialForTesting(kV2Sync, 'unknown-phone', Uint8List(32));
      await sync();
      final revokes = worker.calls['POST revoke'] ?? 0;
      worker.tamper = (method, uri, response) {
        if (method != 'GET' || uri.path != '/v2/lists/$kV2Sync') {
          return response;
        }
        return SyncResponse(
          response.status,
          response.headers,
          Uint8List.fromList(
            utf8.encode(
              jsonEncode({...response.json(), 'registry': 'invalid'}),
            ),
          ),
        );
      };
      await expectLater(
        phone.container
            .read(v2ResolutionActionsProvider)
            .revokeUnbackedCredential('unknown-phone'),
        throwsA(isA<SyncTransportException>()),
      );
      expect(worker.devicesOf(kV2Sync)['unknown-phone'], isFalse);
      expect(worker.calls['POST revoke'] ?? 0, revokes);
      expect((await (await local()).readState()).pendingUnbackedRevocations, {
        'unknown-phone',
      });
      worker.tamper = null;
      await sync();
      expect(worker.devicesOf(kV2Sync)['unknown-phone'], isTrue);
    },
  );

  test(
    'un reintento de POST también vuelve a verificar el respaldo remoto',
    () async {
      final d = await MemoryV2Phone.create(
        'unknown-phone',
        'leo',
        4,
        familyKey: a.familyKey,
      );
      worker.addCredentialForTesting(
        kV2Sync,
        'unknown-phone',
        d.keys.serviceCredential,
      );
      await sync();
      final gets = worker.calls['GET list'] ?? 0;
      final revokes = worker.calls['POST revoke'] ?? 0;
      var attempts = 0;
      beforeRequest = (method, uri) async {
        if (method != 'POST' || !uri.path.endsWith('/revoke')) return;
        attempts++;
        beforeRequest = null;
        await vouchAll([a, b, c, d]);
        await b.engine(worker.client()).sync();
        throw const SyncTransportException(
          SyncFailure.network,
          'sin respuesta',
        );
      };
      await phone.container
          .read(v2ResolutionActionsProvider)
          .revokeUnbackedCredential('unknown-phone');
      expect(attempts, 1);
      expect(worker.devicesOf(kV2Sync)['unknown-phone'], isFalse);
      expect(worker.calls['POST revoke'] ?? 0, revokes);
      expect(worker.calls['GET list']! - gets, greaterThanOrEqualTo(3));
      expect(
        (await (await local()).readState()).pendingUnbackedRevocations,
        isEmpty,
      );
    },
  );

  test('B2: respaldo publicado entre GET y POST devuelve 412; se relee y no revoca', () async {
    final d = await MemoryV2Phone.create(
      'unknown-phone',
      'leo',
      4,
      familyKey: a.familyKey,
    );
    worker.addCredentialForTesting(
      kV2Sync,
      'unknown-phone',
      d.keys.serviceCredential,
    );
    await sync();
    beforeRequest = (method, uri) async {
      if (method != 'POST' || !uri.path.endsWith('/revoke')) return;
      beforeRequest = null;
      // El GET condicional ya terminó. Otro móvil publica el respaldo
      // antes de que el Worker reciba el POST con esa versión antigua.
      await vouchAll([a, b, c, d]);
      await b.engine(worker.client()).sync();
    };
    final revokes = worker.calls['POST revoke'] ?? 0;
    final outcome = await phone.container
        .read(v2ResolutionActionsProvider)
        .revokeUnbackedCredential('unknown-phone');
    expect(outcome, UnbackedRevocation.keptBecauseBacked);
    // Un solo POST, rechazado con 412: tras releer ya no toca revocar.
    expect(worker.calls['POST revoke']! - revokes, 1);
    expect(worker.devicesOf(kV2Sync)['unknown-phone'], isFalse);
    expect(
      (await (await local()).readState()).pendingUnbackedRevocations,
      isEmpty,
    );
  });

  test(
    'B2: tras un 412 por otro cambio se relee, se verifica y se revoca con la '
    'versión nueva',
    () async {
      final d = await MemoryV2Phone.create(
        'unknown-phone',
        'leo',
        4,
        familyKey: a.familyKey,
      );
      worker.addCredentialForTesting(
        kV2Sync,
        'unknown-phone',
        d.keys.serviceCredential,
      );
      await sync();
      beforeRequest = (method, uri) async {
        if (method != 'POST' || !uri.path.endsWith('/revoke')) return;
        beforeRequest = null;
        // Otro móvil sube algo que no respalda la credencial.
        b.addGift('g9', 'leo', 'Peonza');
        await b.engine(worker.client()).sync();
      };
      final revokes = worker.calls['POST revoke'] ?? 0;
      final outcome = await phone.container
          .read(v2ResolutionActionsProvider)
          .revokeUnbackedCredential('unknown-phone');
      beforeRequest = null;
      expect(outcome, UnbackedRevocation.revoked);
      expect(worker.calls['POST revoke']! - revokes, 2);
      expect(worker.devicesOf(kV2Sync)['unknown-phone'], isTrue);
      expect(
        (await (await local()).readState()).pendingUnbackedRevocations,
        isEmpty,
      );
    },
  );

  test('B2: un 412 continuo no revoca, no aborta la vuelta y deja la intención pendiente', () async {
    worker.addCredentialForTesting(kV2Sync, 'unknown-phone', Uint8List(32));
    await sync();
    beforeRequest = (method, uri) async {
      if (method != 'POST' || !uri.path.endsWith('/revoke')) return;
      // Cada POST llega cuando la lista ya se ha movido.
      b.addGift('g${DateTime.now().microsecondsSinceEpoch}', 'leo', 'Peonza');
      await b.engine(worker.client()).sync();
    };
    await expectLater(
      phone.container
          .read(v2ResolutionActionsProvider)
          .revokeUnbackedCredential('unknown-phone'),
      throwsA(isA<SyncTransportException>()),
    );
    // La vuelta en sí no se aborta (revisión de seguridad, B1): termina y la
    // intención sigue pendiente, sin cortar nada.
    final engine = SyncV2Engine(transport: client, local: await local());
    final out = await engine.sync();
    expect(engine.unbackedOutcomes, isNot(contains('unknown-phone')));
    expect(out.version, greaterThan(0));
    beforeRequest = null;
    expect(worker.devicesOf(kV2Sync)['unknown-phone'], isFalse);
    expect((await (await local()).readState()).pendingUnbackedRevocations, {
      'unknown-phone',
    });
  });

  for (final recovery in ['sync', 'unbacked', 'departure']) {
    test(
      'recuperación sin reinicio por $recovery actualiza la identidad en memoria',
      () async {
        // Fallar antes de guardar identidad deja tanto disco como memoria viejos.
        secrets.failWrite = 'family.identity';
        await expectLater(family().changeSelfPerson('nora'), throwsStateError);
        expect(await store().readSelfRecipient(), 'aritz');
        expect(
          phone.container
              .read(familyControllerProvider)
              .requireValue
              .identity!
              .selfRecipientId,
          'aritz',
        );
        switch (recovery) {
          case 'sync':
            await phone.container
                .read(syncControllerProvider.notifier)
                .syncNow();
          case 'unbacked':
            await phone.container
                .read(v2ResolutionActionsProvider)
                .revokeUnbackedCredential('not-listed');
          case 'departure':
            await phone.container
                .read(v2ResolutionActionsProvider)
                .completeDeparture('not-departed');
        }
        expect(
          phone.container
              .read(familyControllerProvider)
              .requireValue
              .identity!
              .selfRecipientId,
          'nora',
        );
        expect(
          (await phone.container.read(localRegistryViewProvider.future))!
              .self
              .personId,
          'nora',
        );
        expect(selfRecordOf((await store().readRegistry())!).seq, 2);
        expect(await store().readScope('nora'), isNull);
        expect(
          await phone.container.read(rememberedOrphansProvider.future),
          isNotEmpty,
        );
        expect(secrets.values, isNot(contains('family.selfPersonChange')));
        await family().setDeviceName('Aritz');
        expect(await store().readSelfRecipient(), 'nora');
        expect(
          phone.container
              .read(familyControllerProvider)
              .requireValue
              .identity!
              .selfRecipientId,
          'nora',
        );
        // Ni repetir el cambio ni una nueva recuperación crean la ficha 3.
        expect(
          await family().changeSelfPerson('nora'),
          ChangeSelfPersonResult.unchanged,
        );
        expect(selfRecordOf((await store().readRegistry())!).seq, 2);
      },
    );
  }

  test('cambio de Yo espera a la vuelta de sincronización sin intercalar escrituras', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    beforeRequest = (method, uri) async {
      if (method == 'GET' && uri.path == '/v2/lists/$kV2Sync') {
        beforeRequest = null;
        entered.complete();
        await release.future;
      }
    };
    final round = phone.container
        .read(syncControllerProvider.notifier)
        .syncNow();
    await entered.future;
    final change = family().changeSelfPerson('nora');
    await family().setDeviceName('Aritz'); // Barrera de la cola de escrituras.
    expect(secrets.values, isNot(contains('family.selfPersonChange')));
    expect(await store().readSelfRecipient(), 'aritz');
    expect(selfRecordOf((await store().readRegistry())!).seq, 1);
    release.complete();
    await round;
    expect(await change, ChangeSelfPersonResult.pendingApproval);
    await sync();
    expect(await store().readSelfRecipient(), 'nora');
    expect(selfRecordOf((await store().readRegistry())!).seq, 2);
    expect(await store().readScope('nora'), isNull);
  });

  test(
    'completeDeparture previsualiza N7 y lo revalida bajo el cerrojo',
    () async {
      final actions = phone.container.read(v2ResolutionActionsProvider);
      // Antes no hace falta N7; después solo Leo avala la ficha nueva.
      expect(
        (await actions.previewDeparture('leo-phone')).selfWouldWait,
        isFalse,
      );
      await family().changeSelfPerson('leo');
      await sync();
      await b.engine(worker.client()).sync();
      await approveFamilyDevice(
        transport: worker.client(),
        local: b,
        deviceId: 'aritz-phone',
      );
      await sync();
      await worker.client().revoke(a.auth, 'leo-phone');
      await sync();
      expect((await health()).departedDevices, contains('leo-phone'));
      final preview = await actions.previewDeparture('leo-phone');
      expect(preview.selfWouldWait, isTrue);
      final before = (await store().readRegistry())!.toJson();
      final pending = (await (await local()).readState()).toJson();
      await expectLater(
        actions.completeDeparture('leo-phone'),
        throwsA(isA<DeviceRemovalChangedException>()),
      );
      expect((await store().readRegistry())!.toJson(), before);
      expect((await (await local()).readState()).toJson(), pending);
      expect(
        await actions.completeDeparture('leo-phone', selfWaitAccepted: true),
        isA<RegistryChange>(),
      );
      expect(
        (await phone.container.read(localRegistryViewProvider.future))!
            .selfApproved,
        isFalse,
      );
      expect((await health()).frozenPeople, contains('nora'));
      expect(await actions.completeDeparture('leo-phone'), isNull);
    },
  );

  test('escritor congelado visible aunque no toque publicar; persiste y llega a revisión', () async {
    await sync();
    await b.engine(worker.client()).sync();
    expect(worker.slotVersions(kV2Sync), contains('nora/leo-phone'));
    // Aritz conserva el slot cuando aún está autorizado. Una primera descarga
    // de un escritor ya pendiente se rechaza; no es un slot local congelado.
    await sync();
    b.reg = (await changePerson(
      registry: b.reg,
      view: await b.view(),
      myKeys: b.keys,
      personId: 'aritz',
    )).registry;
    await b.engine(worker.client()).sync();
    await sync();
    expect((await health()).frozenWriterDeviceIds, contains('leo-phone'));
    expect(
      phone.container.read(frozenDeviceIdsProvider),
      contains('leo-phone'),
    );
    expect(
      (await phone.container.read(deviceReviewProvider.future))
          .of('leo-phone')!
          .reason,
      DeviceReviewReason.frozen,
    );
    phone.restart();
    expect((await health()).frozenWriterDeviceIds, contains('leo-phone'));
  });

  test(
    'cambiar Yo v2: pendiente, huérfanos persistentes, purga y vuelta',
    () async {
      expect(
        await family().changeSelfPerson('nora'),
        ChangeSelfPersonResult.pendingApproval,
      );
      expect(await store().readSelfRecipient(), 'nora');
      expect(await store().readScope('nora'), isNull);
      expect(
        (await phone.container
                .read(deviceKeysStoreProvider)
                .readKeyring(kV2List))
            .people,
        isNot(contains('nora')),
      );
      expect(
        (await phone.container.read(localRegistryViewProvider.future))!
            .selfApproved,
        isFalse,
      );
      expect(
        await phone.container.read(rememberedOrphansProvider.future),
        isNotEmpty,
      );
      expect(
        await family().changeSelfPerson('nora'),
        ChangeSelfPersonResult.unchanged,
      );
      await sync();
      phone.restart();
      expect(
        await phone.container.read(rememberedOrphansProvider.future),
        isNotEmpty,
      );
      expect(
        (await phone.container.read(localRegistryViewProvider.future))!
            .self
            .personId,
        'nora',
      );
    },
  );

  test(
    'cambiar a otra persona congela las sorpresas y reiniciar las conserva',
    () async {
      await family().changeSelfPerson('leo');
      expect((await health()).frozenPeople, contains('nora'));
      phone.restart();
      expect((await health()).frozenPeople, contains('nora'));
      expect(await store().readScope('nora'), isNotNull);
    },
  );

  test('revocado por otros se deriva del registro al reiniciar', () async {
    final change = await revokeDevice(
      registry: b.reg,
      view: await b.view(),
      myKeys: b.keys,
      deviceId: 'aritz-phone',
    );
    await store().saveRegistry(change.registry);
    phone.restart();
    expect((await health()).revokedByOthers, isTrue);
    expect((await health()).frozenPeople, contains('nora'));
  });

  test('revocación explícita del servicio anterior al registro también sobrevive al reinicio', () async {
    await worker.client().revoke(b.auth, 'aritz-phone');
    worker.tamper = (method, uri, response) => SyncResponse(
      403,
      const {},
      Uint8List.fromList(utf8.encode('{"error":"revoked"}')),
    );
    await expectLater(sync(), throwsException);
    expect((await health()).revokedByOthers, isTrue);
    phone.restart();
    expect((await health()).revokedByOthers, isTrue);
    expect((await health()).frozenPeople, contains('nora'));
  });

  test(
    'completar baja sin red conserva la operación y repetir la termina una vez',
    () async {
      await worker.client().revoke(a.auth, 'leo-phone');
      await sync();
      worker.offline = true;
      await expectLater(
        phone.container
            .read(v2ResolutionActionsProvider)
            .completeDeparture('leo-phone'),
        throwsException,
      );
      expect(
        (await (await local()).readState()).revocationOperations,
        contains('leo-phone'),
      );
      final epoch = (await phone.container.read(
        localRegistryViewProvider.future,
      ))!.epoch;
      phone.restart();
      worker.offline = false;
      await phone.container
          .read(v2ResolutionActionsProvider)
          .completeDeparture('leo-phone');
      await phone.container
          .read(v2ResolutionActionsProvider)
          .completeDeparture('leo-phone');
      expect(
        (await phone.container.read(localRegistryViewProvider.future))!.epoch,
        epoch,
      );
      expect((await (await local()).readState()).revocationOperations, isEmpty);
    },
  );

  test('seq agotado es tipado y no cambia ni identidad ni claves', () async {
    final record = await DeviceRecord.create(
      keys: a.keys,
      listId: kV2List,
      deviceId: 'aritz-phone',
      personId: 'aritz',
      seq: kMaxDeviceSeq,
    );
    await store().saveRegistry(await a.reg.withRecord(record));
    await expectLater(
      family().changeSelfPerson('nora'),
      throwsA(isA<SelfPersonSequenceExhaustedException>()),
    );
    expect(await store().readSelfRecipient(), 'aritz');
    expect(
      (await phone.container.read(deviceKeysStoreProvider).readKeyring(kV2List))
          .people,
      contains('nora'),
    );
  });

  for (final boundary in [
    'keys',
    'scope',
    'overflow',
    'identity',
    'orphans',
    'registry',
    'registry-written',
    'finish',
  ]) {
    test(
      'cierre a medias en $boundary se recupera antes de exponer familia',
      () async {
        a.addGift('overflow', 'nora', 'Regalo');
        await store().saveOverflow('nora', [
          a.doc.collections['gifts']!['overflow']!,
        ]);
        final initialEpoch = await epochOf((await store().readRegistry())!);
        switch (boundary) {
          case 'keys':
            secrets.failWrite = kSurpriseKeysSecret;
          case 'scope':
            files.failDelete = 'family.scope.nora';
          case 'overflow':
            files.failDelete = 'family.overflow.nora';
          case 'identity':
            secrets.failWrite = 'family.identity';
          case 'orphans':
            secrets.failWrite = 'family.orphans';
          case 'registry':
            files.failRegistry = true;
          case 'registry-written':
            files.failRegistry = true;
            files.failAfterWrite = true;
          case 'finish':
            secrets.failFinish = true;
        }
        await expectLater(family().changeSelfPerson('nora'), throwsStateError);
        final registryWritten = [
          'registry-written',
          'finish',
        ].contains(boundary);
        final identityWritten = [
          'orphans',
          'registry',
          'registry-written',
          'finish',
        ].contains(boundary);
        final keysWritten = boundary != 'keys';
        final scopeDeleted = !['keys', 'scope'].contains(boundary);
        final overflowDeleted = ![
          'keys',
          'scope',
          'overflow',
        ].contains(boundary);
        final before = (await store().readRegistry())!;
        final self = selfRecordOf(before);
        expect(self.seq, registryWritten ? 2 : 1);
        expect(self.personId, registryWritten ? 'nora' : 'aritz');
        expect(await epochOf(before), initialEpoch + (registryWritten ? 1 : 0));
        expect(secrets.values, contains('family.selfPersonChange'));
        expect(
          await store().readSelfRecipient(),
          identityWritten ? 'nora' : 'aritz',
        );
        expect(
          phone.container
              .read(familyControllerProvider)
              .requireValue
              .identity!
              .selfRecipientId,
          identityWritten ? 'nora' : 'aritz',
        );
        expect(
          (await phone.container
                  .read(deviceKeysStoreProvider)
                  .readKeyring(kV2List))
              .people
              .contains('nora'),
          !keysWritten,
        );
        expect(
          await store().readScope('nora'),
          scopeDeleted ? isNull : isNotNull,
        );
        expect(
          await store().readOverflow('nora'),
          overflowDeleted ? isEmpty : hasLength(1),
        );
        expect(
          await store().readOrphans(),
          registryWritten || boundary == 'registry' ? isNotEmpty : isEmpty,
        );
        phone.restart();
        final familyState = await phone.container.read(
          familyControllerProvider.future,
        );
        expect(familyState.identity!.selfRecipientId, 'nora');
        expect(
          (await phone.container.read(localRegistryViewProvider.future))!
              .self
              .personId,
          'nora',
        );
        expect(
          (await phone.container
                  .read(deviceKeysStoreProvider)
                  .readKeyring(kV2List))
              .people,
          isNot(contains('nora')),
        );
        expect(await store().readScope('nora'), isNull);
        expect(await store().readOverflow('nora'), isEmpty);
        final recovered = (await store().readRegistry())!;
        expect(selfRecordOf(recovered).seq, 2);
        expect(await epochOf(recovered), initialEpoch + 1);
        expect(secrets.values, isNot(contains('family.selfPersonChange')));
        expect(
          await phone.container.read(rememberedOrphansProvider.future),
          isNotEmpty,
        );
      },
    );
  }

  test('v1 solo local y persona repetida no cambia nada', () async {
    await phone.secrets.delete('family.syncV2');
    expect(
      await family().changeSelfPerson('leo'),
      ChangeSelfPersonResult.localOnly,
    );
    expect(
      await family().changeSelfPerson('leo'),
      ChangeSelfPersonResult.unchanged,
    );
    expect(await store().readSelfRecipient(), 'leo');
    expect((await health()).unbackedCredentials, isEmpty);
  });
}
