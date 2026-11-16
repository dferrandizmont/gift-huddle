// Emparejamiento v2 en la app, de punta a punta: dos móviles que estaban
// emparejados en v1 vuelven a conectarse; el que invita migra, el que entra
// fusiona su copia v1 y, cuando los dos están en v2, la copia v1 del servidor
// se borra.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/device/device_name.dart';
import 'package:regalos/core/prefs/shared_preferences_provider.dart';
import 'package:regalos/core/sync/device_keys.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/pairing_v2.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/family/data/storage.dart';
import 'package:regalos/features/family/data/storage_native.dart';
import 'package:regalos/features/family/data/storage_providers.dart';
import 'package:regalos/features/family/domain/family_errors.dart';
import 'package:regalos/features/sharing/application/pairing_service.dart';
import 'package:regalos/features/settings/application/erase_all.dart';
import 'package:regalos/features/sync/application/app_sync_v2_local.dart';
import 'package:regalos/features/sync/application/family_device_rows.dart';
import 'package:regalos/features/sync/application/family_devices.dart'
    show FamilyDeviceRow;
import 'package:regalos/features/sync/application/migration_v2.dart';
import 'package:regalos/features/sync/application/pairing_v2_controller.dart';
import 'package:regalos/features/sync/application/pairing_v2_flow.dart';
import 'package:regalos/features/sync/application/sync_controller.dart';
import 'package:regalos/features/sync/application/sync_v2_engine.dart';
import 'package:regalos/features/sync/application/v2_family_lock.dart';
import 'package:regalos/features/sync/application/v2_health_provider.dart';
import 'package:regalos/features/sync/data/sync_config.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';
import 'package:regalos/features/sync/data/sync_transport_common.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';
import 'package:regalos/features/sync/domain/sync_keys.dart';
import 'package:regalos/features/sync/domain/sync_status.dart';

import '../helpers/fake_sync_server.dart';
import '../helpers/fake_worker_v2.dart';
import '../helpers/memory_stores.dart';
import '../helpers/pump_app.dart';

import 'sync_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSyncServer v1;
  late FakeWorkerV2 worker;

  setUp(() {
    v1 = FakeSyncServer();
    worker = FakeWorkerV2();
  });

  Future<FakePhone> phone({
    String deviceModel = '',
    FileStore? disk,
    MemorySecretStore? secrets,
    V2FamilyLock? lock,
    SyncTiming timing = kFastTiming,
    SyncV2Transport? transport,
  }) async {
    final prefs = await mockPrefs();
    final p = FakePhone(
      prefs: prefs,
      secrets: secrets,
      syncHost: null,
      extraOverrides: [
        suggestedDeviceNameProvider.overrideWith((ref) async => deviceModel),
        if (lock != null) v2FamilyLockProvider.overrideWithValue(lock),
        if (disk != null)
          familyStoreProvider.overrideWith(
            (ref) => FamilyStore(
              secrets: ref.watch(secretStoreProvider),
              files: disk,
              deviceKeys: ref.watch(deviceKeysStoreProvider),
            ),
          ),
        syncHostProvider.overrideWithValue(kTestHost),
        // Las invitaciones, en el mismo origen que el servidor de pruebas.
        invitationOriginProvider.overrideWithValue(''),
        syncTransportProvider.overrideWithValue(v1.connect()),
        syncV2TransportProvider.overrideWithValue(transport ?? worker.client()),
        syncTimingProvider.overrideWithValue(timing),
      ],
    );
    addTearDown(p.dispose);
    p.container.read(syncControllerProvider);
    p.container.read(sharedPreferencesProvider);
    return p;
  }

  Set<String> titles(FakePhone p) => {
    for (final g
        in p.container.read(familyControllerProvider).value!.fullView.gifts)
      g.title,
  };

  Future<FakePhone> threeV1Phones({FileStore? disk, V2FamilyLock? lock}) async {
    final a = await phone(disk: disk, lock: lock);
    final fam = a.container.read(familyControllerProvider.notifier);
    await a.container.read(familyControllerProvider.future);
    await fam.createFamily(deviceName: 'Aritz');
    for (final name in ['Aritz', 'Nora', 'Leo']) {
      await fam.upsertRecipient(
        Recipient(
          id: name.toLowerCase(),
          name: name,
          colorIndex: 0,
          archived: false,
        ),
      );
    }
    await fam.setSelfRecipient('aritz');
    final identity = a.container
        .read(familyControllerProvider)
        .value!
        .identity!;
    for (final name in ['Nora', 'Leo']) {
      final other = await phone();
      await other.container.read(familyControllerProvider.future);
      final family = other.container.read(familyControllerProvider.notifier);
      await family.joinFamily(
        payload: PairingPayload(
          listId: identity.listId,
          key: fam.familyKey!,
          deviceName: 'Aritz',
        ),
        deviceName: name,
      );
      await family.upsertRecipient(
        Recipient(
          id: name.toLowerCase(),
          name: name,
          colorIndex: 0,
          archived: false,
        ),
      );
      await family.upsertGift(
        Gift(
          id: 'gift-${name.toLowerCase()}',
          recipientId: name.toLowerCase(),
          title: 'Libro',
          status: GiftStatus.idea,
          rawStatus: 'idea',
          surprise: false,
          year: 2026,
        ),
      );
      await other.container.read(syncControllerProvider.notifier).syncNow();
    }
    await fam.markPaired(peerName: 'Leo');
    await a.container.read(syncControllerProvider.notifier).syncNow();
    expect(
      writerNodesOf(a.container.read(familyControllerProvider).value!.doc),
      hasLength(3),
    );
    return a;
  }

  test('migrar tres móviles con Yo y volver a invitar', () async {
    final a = await threeV1Phones();
    final host = a.container.read(pairingV2HostProvider.notifier);
    await host.start();
    await host.confirmMigration();
    expect(
      a.container.read(pairingV2HostProvider).phase,
      PairingV2HostPhase.waiting,
    );
    await host.cancel();
    await host.start();
    expect(
      a.container.read(pairingV2HostProvider).phase,
      PairingV2HostPhase.waiting,
    );
    await host.cancel();
  });

  test('un start interrumpido tras crear la lista se recupera al reabrir '
      'limpiando la copia temporal y estrenando generación', () async {
    final dir = await Directory.systemTemp.createTemp('regalos_pairing_retry');
    addTearDown(() => dir.delete(recursive: true));
    var interrupted = false;
    final disk = DirectoryFileStore(
      () async => dir,
      excludeFromBackupHook: (path) async {
        if (interrupted &&
            path.endsWith('family.registry.tmp') &&
            (worker.calls['GET list'] ?? 0) > 0) {
          throw const FileSystemException(
            'detalle privado que nunca debe registrarse',
          );
        }
      },
    );
    final a = await threeV1Phones(disk: disk);
    interrupted = true;
    final host = a.container.read(pairingV2HostProvider.notifier);
    await host.start();
    await host.confirmMigration();
    final failed = a.container.read(pairingV2HostProvider);
    expect(failed.phase, PairingV2HostPhase.failed);
    expect(failed.notReady, isFalse);
    expect(failed.failureCode, 'sync:FileSystemException');
    final leftover = File(
      '${dir.path}${Platform.pathSeparator}family.registry.tmp',
    );
    expect(await leftover.exists(), isTrue);
    final store = a.container.read(familyStoreProvider);
    final identity = (await store.readSyncV2())!;
    final key = a.container.read(familyControllerProvider.notifier).familyKey!;
    final legacy = await store.readLegacyV1();
    expect(V2SyncState.fromJson(await store.readSyncV2State()).created, isTrue);
    expect(worker.calls['POST invites'] ?? 0, 0);
    final puts = worker.calls['PUT list'];
    expect(LegacyV1.fromJson(legacy).nodes, hasLength(3));
    await a.container.read(syncControllerProvider.notifier).syncNow();
    a.restart();
    await a.container.read(familyControllerProvider.future);
    interrupted = false;
    a.container.read(syncControllerProvider);
    await eventually(
      () async =>
          (await a.container.read(familyStoreProvider).readSyncV2())!.syncId !=
          identity.syncId,
      reason: 'startup removes the interrupted invitation copy',
    );
    final retry = a.container.read(pairingV2HostProvider.notifier);
    await Future.wait([
      retry.start(),
      a.container.read(syncControllerProvider.notifier).syncNow(),
    ]);
    expect(
      a.container.read(pairingV2HostProvider).phase,
      PairingV2HostPhase.waiting,
    );
    expect(a.container.read(pairingV2HostProvider).failureCode, isNull);
    final restored = a.container.read(familyStoreProvider);
    expect((await restored.readSyncV2())!.syncId, isNot(identity.syncId));
    expect(worker.hasList(identity.syncId), isFalse);
    expect(
      a.container
          .read(familyControllerProvider)
          .value!
          .identity!
          .selfRecipientId,
      'aritz',
    );
    expect(
      a.container.read(familyControllerProvider.notifier).familyKey,
      isNot(key),
    );
    expect((await restored.readRegistry())!.records.single.personId, 'aritz');
    expect(await restored.readLegacyV1(), legacy);
    expect(titles(a), {'Libro'});
    expect(await leftover.exists(), isFalse);
    expect(
      worker.calls['PUT list'],
      greaterThan(puts!),
      reason: 'creates the fresh generation for the new invitation',
    );
    await retry.cancel();
  });

  test('invitar tras migrar mientras otra vuelta v2 guarda el registro '
      'en disco', () async {
    final dir = await Directory.systemTemp.createTemp('regalos_pairing');
    addTearDown(() => dir.delete(recursive: true));
    Completer<void>? writing;
    Completer<void>? resume;
    final disk = DirectoryFileStore(
      () async => dir,
      excludeFromBackupHook: (path) async {
        if (path.endsWith('family.registry.tmp') && writing != null) {
          final signal = writing!;
          writing = null;
          signal.complete();
          await resume!.future;
        }
      },
    );
    final lock = _ObservedFamilyLock();
    final a = await threeV1Phones(disk: disk, lock: lock);
    final host = a.container.read(pairingV2HostProvider.notifier);
    await host.start();
    await host.confirmMigration();
    expect(
      a.container.read(pairingV2HostProvider).phase,
      PairingV2HostPhase.waiting,
    );
    await host.cancel();
    // Cancelar sin nadie nuevo borra la lista y estrena generación (hallazgo
    // 14): la vuelta que sigue al cambio de clave acaba antes de la carrera.
    await a.container.read(syncControllerProvider.notifier).syncNow();
    final store = a.container.read(familyStoreProvider);
    final before = (await store.readSyncV2())!;
    final registry = (await store.readRegistry())!;
    expect(registry.records.single.personId, 'aritz');
    writing = Completer<void>();
    final entered = writing!.future;
    resume = Completer<void>();
    final retry = host.start();
    await entered;
    final requested = lock.nextRequest();
    final background = a.container
        .read(syncControllerProvider.notifier)
        .syncNow();
    // La vuelta de fondo ya ha pedido la cola que mantiene el anfitrión.
    await requested;
    resume.complete();
    await Future.wait([retry, background]);
    final state = a.container.read(pairingV2HostProvider);
    expect(state.phase, PairingV2HostPhase.waiting, reason: state.failureCode);
    expect((await store.readSyncV2())!.syncId, before.syncId);
    expect((await store.readRegistry())!.sameAs(registry), isTrue);
    await host.cancel();
  });

  // Sin sondeos ni debounce durante las carreras: cada paso lo dispara la prueba.
  const manualTiming = SyncTiming(
    debounce: Duration(days: 1),
    invitePoll: Duration(days: 1),
    inviteHostPoll: Duration(days: 1),
  );

  Future<(FakePhone, PairingV2Guest)> readyToApprove({
    required _ObservedFamilyLock lock,
    required _RegistryDisk disk,
    required _VersionSecrets secrets,
    SyncV2Transport? transport,
  }) async {
    final a = await phone(
      disk: disk,
      secrets: secrets,
      lock: lock,
      timing: manualTiming,
      transport: transport,
    );
    await a.container.read(familyControllerProvider.future);
    await a.container
        .read(familyControllerProvider.notifier)
        .createFamily(deviceName: 'Aritz');
    final host = a.container.read(pairingV2HostProvider.notifier);
    await host.start();
    await a.container.read(syncControllerProvider.notifier).syncNow();
    final link = a.container.read(pairingV2HostProvider).link!;
    final guest = await PairingV2Guest.open(
      transport: worker.client(),
      inviteId: link.substring(link.indexOf('#') + 1),
      keys: await DeviceKeys.generate(),
      deviceIdFor: (_, _) => 'leo-phone',
    );
    await guest.answer(withoutPerson: true);
    await host.check();
    expect(await guest.code(), a.container.read(pairingV2HostProvider).code);
    guest.confirmCode();
    return (a, guest);
  }

  for (final pauseAt in ['registry', 'state', 'stale']) {
    test('cola v2: $pauseAt conserva R+Leo y la versión N+1', () async {
      final lock = _ObservedFamilyLock();
      final disk = _RegistryDisk();
      final secrets = _VersionSecrets();
      var collide = false;
      var sawStale = false;
      final client = SyncV2Client(
        base: Uri.parse('https://sync.test'),
        sendRequest: (method, uri, {body, headers = const {}}) async {
          if (collide && method == 'PUT') {
            collide = false;
            // Otra petición publica N+1 antes del PUT condicional de N.
            final other = await worker.send(
              method,
              uri,
              body: body,
              headers: headers,
            );
            expect(other.status, 200);
          }
          final response = await worker.send(
            method,
            uri,
            body: body,
            headers: headers,
          );
          if (response.status == 412) sawStale = true;
          return response;
        },
        openSocket: worker.socket,
      );
      final (a, guest) = await readyToApprove(
        lock: lock,
        disk: disk,
        secrets: secrets,
        transport: client,
      );
      if (pauseAt == 'stale') {
        await a.container
            .read(familyControllerProvider.notifier)
            .upsertRecipient(
              const Recipient(
                id: 'nora',
                name: 'Nora',
                colorIndex: 0,
                archived: false,
              ),
            );
        collide = true;
      }
      final store = a.container.read(familyStoreProvider);
      final registries = <Set<String>>[];
      disk.afterRegistry = () async {
        registries.add({
          for (final record in (await store.readRegistry())!.records)
            record.deviceId,
        });
      };
      final gate = _WriteGate();
      addTearDown(gate.release);
      if (pauseAt == 'registry') {
        disk.gate = gate;
      } else {
        secrets.gate = gate;
      }
      final background = a.container
          .read(syncControllerProvider.notifier)
          .syncNow();
      await gate.entered.future;
      final requested = lock.nextRequest();
      final approval = a.container
          .read(pairingV2HostProvider.notifier)
          .confirm();
      // Con cola, confirm está esperando; sin ella completa antes de soltar
      // la escritura vieja. El mismo escenario reproduce ambas implementaciones.
      await Future.any([requested, approval]);
      gate.release();
      await Future.wait([background, approval]);
      await a.container.read(syncControllerProvider.notifier).syncNow();
      expect(
        a.container.read(pairingV2HostProvider).phase,
        PairingV2HostPhase.done,
      );
      expect(await guest.finish(), isNotNull);
      final firstGuest = registries.indexWhere((r) => r.contains('leo-phone'));
      expect(firstGuest, greaterThanOrEqualTo(0));
      expect(
        registries.skip(firstGuest).every((r) => r.contains('leo-phone')),
        isTrue,
        reason: 'ninguna escritura posterior pierde la incorporación',
      );
      if (pauseAt == 'stale') expect(sawStale, isTrue);
      expect(secrets.versions, isNotEmpty);
      for (var i = 1; i < secrets.versions.length; i++) {
        expect(
          secrets.versions[i],
          greaterThanOrEqualTo(secrets.versions[i - 1]),
          reason: 'la versión recordada nunca baja: ${secrets.versions}',
        );
      }
      final identity = (await store.readSyncV2())!;
      expect(
        V2SyncState.fromJson(await store.readSyncV2State()).version,
        worker.versionOf(identity.syncId),
      );
    });
  }

  test('cola v2: aprobar mantiene el turno hasta guardar la versión', () async {
    final lock = _ObservedFamilyLock();
    final gate = _WriteGate();
    addTearDown(gate.release);
    final client = SyncV2Client(
      base: Uri.parse('https://sync.test'),
      sendRequest: (method, uri, {body, headers = const {}}) async {
        final response = await worker.send(
          method,
          uri,
          body: body,
          headers: headers,
        );
        if (method == 'POST' && uri.path.endsWith('/approve')) {
          await gate.pause();
        }
        return response;
      },
      openSocket: worker.socket,
    );
    final (a, guest) = await readyToApprove(
      lock: lock,
      disk: _RegistryDisk(),
      secrets: _VersionSecrets(),
      transport: client,
    );
    final approval = a.container.read(pairingV2HostProvider.notifier).confirm();
    await gate.entered.future;
    final gets = worker.calls['GET list'];
    final requested = lock.nextRequest();
    final background = a.container
        .read(syncControllerProvider.notifier)
        .syncNow();
    await Future.any([requested, background]);
    final getsWhileApproving = worker.calls['GET list'];
    gate.release();
    await Future.wait([background, approval]);
    expect(
      getsWhileApproving,
      gets,
      reason: 'el fondo espera a guardar la aprobación',
    );
    expect(await guest.finish(), isNotNull);
  });

  test(
    'el invitado conserva fase y tipo de error sin detalles privados',
    () async {
      final a = await threeV1Phones();
      final host = a.container.read(pairingV2HostProvider.notifier);
      await host.start();
      await host.confirmMigration();
      final link = a.container.read(pairingV2HostProvider).link!;
      final b = await phone();
      await b.container.read(familyControllerProvider.future);
      worker.tamper = (method, uri, response) {
        if (uri.path.endsWith('/offer')) {
          throw StateError('detalle privado que nunca debe registrarse');
        }
        return response;
      };
      final guest = b.container.read(pairingV2GuestProvider.notifier);
      await guest.begin(link.substring(link.indexOf('#') + 1));
      final failed = b.container.read(pairingV2GuestProvider);
      expect(failed.phase, PairingV2GuestPhase.failed);
      expect(failed.failureCode, 'offer:StateError');
      expect(failed.notReady, isFalse);
      worker.tamper = null;
      await guest.begin(link.substring(link.indexOf('#') + 1));
      expect(
        b.container.read(pairingV2GuestProvider).phase,
        PairingV2GuestPhase.choosePerson,
      );
      expect(b.container.read(pairingV2GuestProvider).failureCode, isNull);
      guest.cancel();
      await host.cancel();
    },
  );

  test(
    'volver a conectar dos móviles v1: migra, fusiona y retira v1',
    () async {
      final a = await phone();
      final b = await phone();
      final famA = a.container.read(familyControllerProvider.notifier);
      await a.container.read(familyControllerProvider.future);
      await famA.createFamily(deviceName: 'Aritz');
      await famA.upsertRecipient(
        const Recipient(
          id: 'nora',
          name: 'Nora',
          colorIndex: 0,
          archived: false,
        ),
      );
      final idA = a.container.read(familyControllerProvider).value!.identity!;
      // B entra en v1 por QR.
      await b.container.read(familyControllerProvider.future);
      await b.container
          .read(familyControllerProvider.notifier)
          .joinFamily(
            payload: PairingPayload(
              listId: idA.listId,
              key: famA.familyKey!,
              deviceName: 'Aritz',
            ),
            deviceName: 'Leo',
          );
      await famA.markPaired(peerName: 'Leo');
      await a.container.read(syncControllerProvider.notifier).syncNow();
      await b.container.read(syncControllerProvider.notifier).syncNow();
      await eventually(
        () => b.container
            .read(familyControllerProvider)
            .value!
            .fullView
            .recipients
            .isNotEmpty,
        reason: 'B tiene la lista v1',
      );
      final v1SyncId = await SyncKeys.syncId(famA.familyKey!);
      expect(v1.hasList(v1SyncId), isTrue);
      // B escribe algo que solo tiene él (todavía en v1, sin subirlo).
      await b.container.read(syncControllerProvider.notifier).setEnabled(false);
      await b.container
          .read(familyControllerProvider.notifier)
          .upsertGift(
            Gift(
              id: 'g-b',
              recipientId: 'nora',
              title: 'Bufanda',
              status: GiftStatus.idea,
              rawStatus: 'idea',
              surprise: false,
              year: 2026,
            ),
          );
      expect(
        await b.container.read(syncReconnectNeededProvider.future),
        isTrue,
      );

      // A vuelve a conectar: primero pregunta (hallazgo 8) y no toca nada;
      // al confirmar, migra y enseña la invitación.
      final host = a.container.read(pairingV2HostProvider.notifier);
      final storeA = a.container.read(familyStoreProvider);
      await host.start();
      expect(
        a.container.read(pairingV2HostProvider).phase,
        PairingV2HostPhase.confirmMigration,
      );
      expect(await storeA.readSyncV2(), isNull);
      expect(await storeA.readLegacyV1(), isNull);
      expect(
        syncProtocolOf(a.container.read(familyControllerProvider).value!.doc),
        1,
      );
      await host.confirmMigration();
      final link = a.container.read(pairingV2HostProvider).link!;
      final v2A = (await storeA.readSyncV2())!;
      expect(v2A.deviceId, idA.node);
      expect(v2A.migratedFromV1, isTrue);
      expect(await storeA.readLegacyV1(), isNotNull);
      expect(famA.familyKey, isNot(equals(await _v1Key(storeA))));
      expect(
        syncProtocolOf(a.container.read(familyControllerProvider).value!.doc),
        kSyncProtocolV2,
      );

      // B tenía «Este móvil es de» en Nora: al entrar sale ya marcada.
      await b.container
          .read(familyControllerProvider.notifier)
          .setSelfRecipient('nora');
      // B lee el QR (el enlace) y elige persona.
      final guest = b.container.read(pairingV2GuestProvider.notifier);
      await guest.begin(link.substring(link.indexOf('#') + 1));
      final choose = b.container.read(pairingV2GuestProvider);
      expect(choose.phase, PairingV2GuestPhase.choosePerson);
      expect(choose.people.map((p) => p.id), ['nora']);
      expect(choose.selfId, 'nora');
      await guest.choosePerson('nora');
      await eventually(
        () =>
            b.container.read(pairingV2GuestProvider).phase ==
                PairingV2GuestPhase.compare &&
            a.container.read(pairingV2HostProvider).phase ==
                PairingV2HostPhase.compare,
        reason: 'los dos enseñan el código',
      );
      expect(
        a.container.read(pairingV2HostProvider).code,
        b.container.read(pairingV2GuestProvider).code,
      );
      guest.confirmCode();
      // «Coinciden» no basta: B dice ser de Nora y hay que confirmarlo aparte
      // (hallazgo 3).
      await host.confirm();
      final claim = a.container.read(pairingV2HostProvider);
      expect(claim.phase, PairingV2HostPhase.confirmPerson);
      expect(claim.guestPersonName, 'Nora');
      expect(
        worker.devicesOf(v2A.syncId).keys,
        isNot(
          contains(
            b.container.read(familyControllerProvider).value!.identity!.node,
          ),
        ),
      );
      await host.confirmPerson();
      expect(
        a.container.read(pairingV2HostProvider).phase,
        PairingV2HostPhase.done,
      );
      await eventually(
        () =>
            b.container.read(pairingV2GuestProvider).phase ==
            PairingV2GuestPhase.done,
        reason: 'B dentro',
      );
      final storeB = b.container.read(familyStoreProvider);
      final idB = b.container.read(familyControllerProvider).value!.identity!;
      expect((await storeB.readSyncV2())!.deviceId, idB.node);
      // B tenía la sincronización apagada: al terminar de emparejar se vuelve a
      // encender sola (uso real, pre.21: «Sincronización apagada» tras
      // conectar los dos móviles).
      await eventually(
        () =>
            b.container.read(syncControllerProvider).phase !=
            SyncPhase.disabled,
        reason: 'emparejar enciende la sincronización',
      );
      await a.container.read(syncControllerProvider.notifier).syncNow();
      await eventually(
        () => titles(a).contains('Bufanda') && titles(b).contains('Bufanda'),
        reason: 'lo de B en v1 llega a v2',
      );
      await eventually(
        () =>
            a.container.read(syncControllerProvider).phase == SyncPhase.synced,
        reason:
            'la sincronización termina tras las ediciones de los dos móviles',
      );
      // Los dos que escribieron en v1 ya están en v2: la copia v1 se borra.
      await b.container.read(syncControllerProvider.notifier).syncNow();
      await eventually(
        () => !v1.hasList(v1SyncId),
        reason: 'la copia v1 se borra',
      );
      await eventually(
        () async => !await a.container.read(syncReconnectNeededProvider.future),
        reason: 'sin aviso',
      );

      // Las personas con móvil: Aritz no tenía «Yo»; B eligió a Nora.
      expect(await a.container.read(devicePersonIdsProvider.future), {'nora'});
      expect(
        await a.container.read(isDevicePersonProvider('nora').future),
        isTrue,
      );

      // «Dejar de sincronizar» en B, con A todavía dentro: B sale de la
      // familia y la lista se queda para A; lo local de B se queda.
      final v2Sync = v2A.syncId;
      final keyB = b.container
          .read(familyControllerProvider.notifier)
          .familyKey;
      await b.container.read(syncControllerProvider.notifier).stopSyncing();
      expect(worker.hasList(v2Sync), isTrue);
      expect(worker.devicesOf(v2Sync)[idB.node], isTrue);
      expect(titles(b), contains('Bufanda'));
      // B queda en una generación propia, sin otros móviles (hallazgo 2).
      final renewedB = (await storeB.readSyncV2())!;
      expect(renewedB.syncId, isNot(v2Sync));
      expect(
        b.container.read(familyControllerProvider.notifier).familyKey,
        isNot(keyB),
      );
      expect((await storeB.readRegistry())!.records.map((r) => r.deviceId), [
        idB.node,
      ]);
      expect(
        b.container.read(familyControllerProvider).value!.identity!.paired,
        isFalse,
      );
      await storeA.enableRemoteSync();
      // A ya es el último con acceso: ahora sí se borra la lista entera.
      await a.container.read(syncControllerProvider.notifier).stopSyncing();
      expect(worker.hasList(v2Sync), isFalse);
      await a.container.read(syncControllerProvider.notifier).setEnabled(true);
      expect(worker.hasList((await storeA.readSyncV2())!.syncId), isFalse);
      expect(await storeA.remoteSyncEnabled(), isFalse);
      expect(
        a.container.read(syncControllerProvider).phase,
        SyncPhase.waitingForPeer,
      );
    },
  );

  /// A crea una familia y conecta a B (sin familia) por v2, «Elegir después».
  Future<(FakePhone, FakePhone)> pairedV2({
    String guestDeviceModel = '',
    String guestConfirmedName = '',
    SyncV2Transport? hostTransport,
    SyncV2Transport? guestTransport,
  }) async {
    final a = await phone(transport: hostTransport);
    final b = await phone(
      transport: guestTransport,
      deviceModel: guestDeviceModel,
    );
    final famA = a.container.read(familyControllerProvider.notifier);
    await a.container.read(familyControllerProvider.future);
    await famA.createFamily(deviceName: 'Aritz');
    await famA.upsertRecipient(
      const Recipient(id: 'nora', name: 'Nora', colorIndex: 0, archived: false),
    );
    await b.container.read(familyControllerProvider.future);
    final host = a.container.read(pairingV2HostProvider.notifier);
    await host.start();
    // Sin otros móviles en v1, no hay nada que preguntar.
    final link = a.container.read(pairingV2HostProvider).link!;
    final guest = b.container.read(pairingV2GuestProvider.notifier);
    await guest.begin(
      link.substring(link.indexOf('#') + 1),
      deviceName: guestConfirmedName,
    );
    await guest.choosePerson(null);
    await eventually(
      () =>
          a.container.read(pairingV2HostProvider).phase ==
              PairingV2HostPhase.compare &&
          b.container.read(pairingV2GuestProvider).phase ==
              PairingV2GuestPhase.compare,
      reason: 'los dos enseñan el código',
    );
    guest.confirmCode();
    await host.confirm();
    await eventually(
      () =>
          b.container.read(pairingV2GuestProvider).phase ==
          PairingV2GuestPhase.done,
      reason: 'B dentro',
    );
    await a.container.read(syncControllerProvider.notifier).syncNow();
    await b.container.read(syncControllerProvider.notifier).syncNow();
    return (a, b);
  }

  test('link pairing publishes the name confirmed before joining', () async {
    final (a, b) = await pairedV2(
      guestDeviceModel: 'Unconfirmed model',
      guestConfirmedName: 'Pixel de Nora',
    );
    await a.container.read(syncControllerProvider.notifier).syncNow();
    final id = (await b.container.read(familyStoreProvider).readSyncV2())!;
    expect(
      b.container.read(familyControllerProvider).value!.identity!.deviceName,
      'Pixel de Nora',
    );
    final rows = (await a.container.read(familyDeviceRowsProvider.future))!;
    expect(
      rows.firstWhere((r) => r.deviceId == id.deviceId).deviceName,
      'Pixel de Nora',
    );
  });

  test('a model without confirmation stays private; later confirmed names update open rows', () async {
    final (a, b) = await pairedV2(guestDeviceModel: 'Pixel de Nora');
    final bId =
        (await b.container.read(familyStoreProvider).readSyncV2())!.deviceId;
    final aId =
        (await a.container.read(familyStoreProvider).readSyncV2())!.deviceId;
    final updates = <List<FamilyDeviceRow>>[];
    final subscription = a.container.listen(familyDeviceRowsProvider, (
      _,
      next,
    ) {
      if (next.value case final rows?) updates.add(rows);
    }, fireImmediately: true);
    addTearDown(subscription.close);
    expect(
      b.container.read(familyControllerProvider).value!.identity!.deviceName,
      isEmpty,
    );
    final initialRows = (await a.container.read(
      familyDeviceRowsProvider.future,
    ))!;
    expect(
      initialRows.firstWhere((row) => row.deviceId == bId).deviceName,
      isNull,
    );
    await b.container
        .read(familyControllerProvider.notifier)
        .setDeviceName('Pixel de Nora');
    await b.container.read(syncControllerProvider.notifier).syncNow();
    await a.container.read(syncControllerProvider.notifier).syncNow();
    await eventually(
      () => updates.any(
        (rows) => rows.any(
          (row) => row.deviceId == bId && row.deviceName == 'Pixel de Nora',
        ),
      ),
      reason: 'open rows update as soon as the encrypted name arrives',
    );
    final guestRows = (await b.container.read(
      familyDeviceRowsProvider.future,
    ))!;
    expect(
      guestRows.firstWhere((row) => row.deviceId == aId).deviceName,
      'Aritz',
    );
    await b.container
        .read(familyControllerProvider.notifier)
        .setDeviceName('Móvil de Nora');
    await b.container.read(syncControllerProvider.notifier).syncNow();
    await a.container.read(syncControllerProvider.notifier).syncNow();
    await eventually(
      () => updates.any(
        (rows) => rows.any(
          (row) => row.deviceId == bId && row.deviceName == 'Móvil de Nora',
        ),
      ),
      reason: 'subsequent renames update the same subscription',
    );
  });

  for (final recovery in ['retry', 'restart', 'legacy']) {
    test('401 remains recoverable without hiding phones ($recovery)', () async {
      var reject = false;
      var reads = 0;
      final transport = SyncV2Client(
        base: worker.client().base,
        sendRequest: (method, uri, {body, headers = const {}}) async {
          if (method == 'GET' && uri.path.contains('/lists/')) {
            reads++;
            if (reject) {
              return SyncResponse(
                401,
                const {},
                Uint8List.fromList(utf8.encode('{"error":"unauthorized"}')),
              );
            }
          }
          return worker.send(method, uri, body: body, headers: headers);
        },
      );
      final (_, b) = await pairedV2(guestTransport: transport);
      final store = b.container.read(familyStoreProvider);
      final identity = (await store.readSyncV2())!;
      reject = true;
      await b.container.read(syncControllerProvider.notifier).syncNow();
      expect(b.container.read(syncControllerProvider).issue, SyncIssue.auth);
      expect(b.container.read(syncControllerProvider).active, isTrue);
      expect(
        (await b.container.read(v2HealthProvider.future)).revokedByOthers,
        isFalse,
      );
      expect(
        (await b.container.read(familyDeviceRowsProvider.future))!,
        hasLength(2),
      );
      if (recovery != 'retry') {
        if (recovery == 'legacy') {
          final saved = (await store.readSyncV2State())! as Map;
          await store.saveSyncV2State({
            ...Map<String, Object?>.from(saved),
            'health': {...?(saved['health'] as Map?), 'revoked': true},
          });
        }
        b.restart();
        b.container.read(syncControllerProvider);
        await b.container.read(familyControllerProvider.future);
        final beforeRestartRead = reads;
        await b.container.read(syncControllerProvider.notifier).syncNow();
        expect(reads, greaterThan(beforeRestartRead));
        expect(b.container.read(syncControllerProvider).issue, SyncIssue.auth);
        expect(
          (await b.container.read(familyDeviceRowsProvider.future))!,
          hasLength(2),
        );
      }
      final beforeRetry = reads;
      reject = false;
      await eventually(
        () =>
            b.container.read(syncControllerProvider).phase == SyncPhase.synced,
        reason: 'automatic retry accepts the still-valid credential',
      );
      expect(reads, greaterThan(beforeRetry));
      expect((await store.readSyncV2())!.syncId, identity.syncId);
      expect(
        (await b.container.read(v2HealthProvider.future)).revokedByOthers,
        isFalse,
      );
    });
  }

  for (final cause in ['signed', 'explicit', 'socket']) {
    test('removal is durable and lists only this phone ($cause)', () async {
      final client = worker.client();
      var reads = 0;
      var explicitlyRevoked = false;
      final guestTransport = SyncV2Client(
        base: client.base,
        sendRequest: (method, uri, {body, headers = const {}}) async {
          if (method == 'GET' && uri.path.contains('/lists/')) reads++;
          if (explicitlyRevoked) {
            return SyncResponse(
              403,
              const {},
              Uint8List.fromList(utf8.encode('{"error":"revoked"}')),
            );
          }
          return worker.send(method, uri, body: body, headers: headers);
        },
        openSocket: cause == 'socket' ? worker.socket : null,
      );
      final (a, b) = await pairedV2(guestTransport: guestTransport);
      await a.container
          .read(familyControllerProvider.notifier)
          .upsertGift(
            const Gift(
              id: 'kept',
              recipientId: 'nora',
              title: 'Libro',
              status: GiftStatus.idea,
              rawStatus: 'idea',
              surprise: false,
              year: 2026,
            ),
          );
      await a.container.read(syncControllerProvider.notifier).syncNow();
      await b.container.read(syncControllerProvider.notifier).syncNow();
      final store = b.container.read(familyStoreProvider);
      final identity = (await store.readSyncV2())!;
      final hostStore = a.container.read(familyStoreProvider);
      final hostIdentity = (await hostStore.readSyncV2())!;
      final hostKeys = (await a.container
          .read(deviceKeysStoreProvider)
          .read())!;
      final sync = b.container.read(syncControllerProvider.notifier);
      final before = titles(b);
      expect(before, contains('Libro'));
      if (cause == 'signed') {
        final registry = (await hostStore.readRegistry(
          anchor: RegistryAnchor(
            deviceId: hostIdentity.deviceId,
            signingKey: hostKeys.publicKeys.signing,
          ),
        ))!;
        final change = await revokeDevice(
          registry: registry,
          view: (await a.container.read(localRegistryViewProvider.future))!,
          myKeys: hostKeys,
          deviceId: identity.deviceId,
        );
        await store.saveRegistry(change.registry);
        await sync.syncNow();
      } else {
        if (cause == 'socket') {
          await eventually(
            () => worker.watchers(identity.syncId) == 2,
            reason: 'guest watch connected',
          );
        }
        await client.revoke(
          V2Auth(
            syncId: hostIdentity.syncId,
            deviceId: hostIdentity.deviceId,
            credential: hostKeys.serviceCredential,
          ),
          identity.deviceId,
        );
        if (cause == 'explicit') {
          // Some server routes report revocation explicitly. A generic 401
          // from the ordinary list route is insufficient evidence.
          explicitlyRevoked = true;
          await sync.syncNow();
        }
      }
      await eventually(
        () =>
            b.container.read(syncControllerProvider).phase == SyncPhase.removed,
        reason: 'removal recognized',
      );
      expect(b.container.read(syncControllerProvider).active, isFalse);
      expect(b.container.read(syncControllerProvider).issue, isNull);
      expect(
        (await b.container.read(v2HealthProvider.future)).revokedByOthers,
        isTrue,
      );
      final rows = (await b.container.read(familyDeviceRowsProvider.future))!;
      expect(rows, hasLength(1));
      expect(rows.single.deviceId, identity.deviceId);
      expect(rows.single.isSelf, isTrue);
      final readsAfterRemoval = reads;
      b.restart();
      b.container.read(syncControllerProvider);
      await b.container.read(familyControllerProvider.future);
      await b.container.read(syncControllerProvider.notifier).syncNow();
      expect(b.container.read(syncControllerProvider).phase, SyncPhase.removed);
      expect(
        reads,
        readsAfterRemoval,
        reason: 'no retry with the retired credential',
      );
      expect(
        (await b.container.read(familyDeviceRowsProvider.future))!,
        hasLength(1),
      );
      expect(titles(b), before);
      explicitlyRevoked = false;
      if (cause != 'signed') {
        await b.container.read(syncControllerProvider.notifier).stopSyncing();
        expect((await store.readSyncV2())!.syncId, isNot(identity.syncId));
        expect(titles(b), before);
      }
    });
  }

  test('old default phone names are not published as chosen names', () async {
    final p = await phone();
    final family = p.container.read(familyControllerProvider.notifier);
    await p.container.read(familyControllerProvider.future);
    await family.createFamily(deviceName: 'Mi móvil');
    await family.publishDeviceNameWithinLock();
    final state = p.container.read(familyControllerProvider).value!;
    expect(
      state.doc.record(Collections.meta, 'device:${state.identity!.node}'),
      isNull,
    );
  });

  for (final departure in ['removed', 'leaves']) {
    test(
      'privacy: last phone retires the unshared copy when peer $departure',
      () async {
        final (a, b) = await pairedV2();
        final store = a.container.read(familyStoreProvider);
        final old = (await store.readSyncV2())!;
        final sync = a.container.read(syncControllerProvider.notifier);
        if (departure == 'removed') {
          final peer = (await b.container
              .read(familyStoreProvider)
              .readSyncV2())!;
          await sync.removeDevice(peer.deviceId);
        } else {
          await b.container.read(syncControllerProvider.notifier).stopSyncing();
          await sync.syncNow();
        }
        expect(worker.hasList(old.syncId), isFalse);
        final fresh = (await store.readSyncV2())!;
        expect(fresh.syncId, isNot(old.syncId));
        expect(await store.remoteSyncEnabled(), isFalse);
        expect(worker.hasList(fresh.syncId), isFalse);
        expect(
          a.container.read(syncControllerProvider).phase,
          SyncPhase.waitingForPeer,
        );
        await sync.syncNow();
        expect(worker.hasList(fresh.syncId), isFalse);
      },
    );
  }

  test('privacy: shared rounds use only the engine snapshot GET', () async {
    // Count one requested round without a socket scheduling another on departure.
    final (a, b) = await pairedV2(
      hostTransport: SyncV2Client(
        base: Uri.parse('https://sync.test'),
        sendRequest: worker.send,
      ),
    );
    final sync = a.container.read(syncControllerProvider.notifier);
    final old = (await a.container.read(familyStoreProvider).readSyncV2())!;
    worker.calls.clear();
    await sync.syncNow();
    expect(worker.calls['GET list'], 1);
    // Service credentials absent from the signed registry also prevent retirement.
    await b.container.read(syncControllerProvider.notifier).stopSyncing();
    worker.addCredentialForTesting(
      old.syncId,
      'unbacked',
      Uint8List.fromList(List.filled(32, 77)),
    );
    worker.calls.clear();
    await sync.syncNow();
    expect(worker.calls['GET list'], 1);
    expect(worker.calls['DELETE list'] ?? 0, 0);
  });

  for (final operation in ['round', 'remove']) {
    for (final failure in [
      'network',
      '429',
      '500',
      'renewal_close_pending',
      'get',
    ]) {
      test('privacy: $operation succeeds despite retirement $failure', () async {
        var intercept = false;
        var gets = 0;
        final client = SyncV2Client(
          base: Uri.parse('https://sync.test'),
          sendRequest: (method, uri, {body, headers = const {}}) async {
            final list = RegExp(r'^/v2/lists/[^/]+$').hasMatch(uri.path);
            if (intercept && list && method == 'GET') gets++;
            if (intercept && list && method == 'DELETE') {
              expect(headers['X-Automatic-Retirement'], 'true');
              expect(headers['If-Match'], isNotNull);
            }
            if (intercept &&
                list &&
                ((method == 'DELETE' && failure != 'get') ||
                    (method == 'GET' && failure == 'get' && gets == 2))) {
              if (failure == 'network' || failure == 'get') {
                throw const SyncTransportException(
                  SyncFailure.network,
                  'offline',
                );
              }
              final status = failure == 'renewal_close_pending'
                  ? 409
                  : int.parse(failure);
              return SyncResponse(
                status,
                const {},
                Uint8List.fromList(
                  utf8.encode(
                    '{"error":"${failure == 'renewal_close_pending' ? failure : 'internal'}"}',
                  ),
                ),
              );
            }
            return worker.send(method, uri, body: body, headers: headers);
          },
        );
        final (a, b) = await pairedV2(hostTransport: client);
        final sync = a.container.read(syncControllerProvider.notifier);
        final store = a.container.read(familyStoreProvider);
        final old = (await store.readSyncV2())!;
        intercept = true;
        if (operation == 'remove') {
          final peer = (await b.container
              .read(familyStoreProvider)
              .readSyncV2())!;
          await sync.removeDevice(peer.deviceId);
          expect(worker.devicesOf(old.syncId)[peer.deviceId], isTrue);
        } else {
          await b.container.read(syncControllerProvider.notifier).stopSyncing();
          await sync.syncNow();
          expect(
            a.container.read(syncControllerProvider).phase,
            SyncPhase.synced,
          );
          expect(
            a.container.read(syncControllerProvider).lastSyncAt,
            isNotNull,
          );
        }
        expect(worker.hasList(old.syncId), isTrue);
        intercept = false;
        await sync.syncNow();
        expect(worker.hasList(old.syncId), isFalse);
      });
    }
  }

  test(
    'privacy: solo round merges rejected slots before considering retirement',
    () async {
      final (a, b) = await pairedV2();
      final sync = a.container.read(syncControllerProvider.notifier);
      final store = a.container.read(familyStoreProvider);
      final old = (await store.readSyncV2())!;
      final peer = (await b.container.read(familyStoreProvider).readSyncV2())!;
      sync.setV2Pairing(true);
      await sync.removeDevice(peer.deviceId);
      sync.setV2Pairing(false);
      worker.plantRawSlotForTesting(old.syncId, 'nora', old.deviceId, 'AAAA');
      worker.calls.clear();
      await sync.syncNow();
      expect(worker.calls['DELETE list'] ?? 0, 0);
      expect(worker.hasList(old.syncId), isTrue);
      expect((await store.readSyncV2())!.syncId, old.syncId);
      expect(a.container.read(syncControllerProvider).phase, SyncPhase.synced);
      // Cached unreadable slots must keep blocking later rounds as well.
      await sync.syncNow();
      expect(worker.calls['DELETE list'] ?? 0, 0);
    },
  );

  test('privacy: a stored service version is not proof of merged content', () async {
    final (a, b) = await pairedV2();
    final sync = a.container.read(syncControllerProvider.notifier);
    final store = a.container.read(familyStoreProvider);
    final old = (await store.readSyncV2())!;
    final peer = (await b.container.read(familyStoreProvider).readSyncV2())!;
    sync.setV2Pairing(true);
    await sync.removeDevice(peer.deviceId);
    sync.setV2Pairing(false);
    final doc = a.container.read(familyControllerProvider).value!.doc;
    final remote = doc.set(
      HlcClock(node: 'remote', last: doc.maxStamp),
      Collections.gifts,
      'late',
      const Gift(
        id: 'late',
        recipientId: 'nora',
        title: 'Libro',
        status: GiftStatus.idea,
        rawStatus: 'idea',
        surprise: false,
        year: 2026,
      ).toFields(),
    );
    worker.setCommonForTesting(
      old.syncId,
      await seal(
        doc: remote.toJson(),
        listId: old.listId,
        fromNode: 'remote',
        at: DateTime.now().toUtc().toIso8601String(),
        key: a.container.read(familyControllerProvider.notifier).familyKey!,
      ),
    );
    // Revocation acknowledgements can persist a service version without
    // merging its common document. Reproduce that durable state after restart.
    final pending = V2SyncState.fromJson(await store.readSyncV2State());
    await store.saveSyncV2State(
      pending.copyWith(version: worker.versionOf(old.syncId)).toJson(),
    );
    expect(titles(a), isNot(contains('Libro')));
    await sync.syncNow();
    expect(titles(a), contains('Libro'));
    expect(worker.hasList(old.syncId), isFalse);
  });

  test('privacy: frozen surprises keep the solo remote copy', () async {
    final (a, b) = await pairedV2();
    final sync = a.container.read(syncControllerProvider.notifier);
    final store = a.container.read(familyStoreProvider);
    final old = (await store.readSyncV2())!;
    final peer = (await b.container.read(familyStoreProvider).readSyncV2())!;
    sync.setV2Pairing(true);
    await sync.removeDevice(peer.deviceId);
    sync.setV2Pairing(false);
    // A has no selected person, so historical surprise keys stay frozen.
    await a.container
        .read(deviceKeysStoreProvider)
        .updateKeyring(
          old.listId,
          (_) => SurpriseKeyring([
            SurpriseKey(
              personId: 'nora',
              epoch: 1,
              bytes: List<int>.filled(32, 42),
              audience: [old.deviceId],
            ),
          ]),
        );
    worker.calls.clear();
    await sync.syncNow();
    expect(worker.calls['DELETE list'] ?? 0, 0);
    expect(worker.hasList(old.syncId), isTrue);
    expect((await store.readSyncV2())!.syncId, old.syncId);
    expect(a.container.read(syncControllerProvider).phase, SyncPhase.synced);
  });

  test('privacy: removing a peer preserves rejected remote slots', () async {
    final (a, b) = await pairedV2();
    final sync = a.container.read(syncControllerProvider.notifier);
    final old = (await a.container.read(familyStoreProvider).readSyncV2())!;
    final peer = (await b.container.read(familyStoreProvider).readSyncV2())!;
    worker.plantRawSlotForTesting(old.syncId, 'nora', old.deviceId, 'AAAA');
    worker.calls.clear();
    await sync.removeDevice(peer.deviceId);
    expect(worker.devicesOf(old.syncId)[peer.deviceId], isTrue);
    expect(worker.calls['DELETE list'] ?? 0, 0);
    expect(worker.hasList(old.syncId), isTrue);
  });

  test('privacy: an ongoing pairing defers last-phone retirement', () async {
    final (a, b) = await pairedV2();
    final store = a.container.read(familyStoreProvider);
    final old = (await store.readSyncV2())!;
    final sync = a.container.read(syncControllerProvider.notifier);
    sync.setV2Pairing(true);
    await b.container.read(syncControllerProvider.notifier).stopSyncing();
    await sync.syncNow();
    expect(worker.hasList(old.syncId), isTrue);
    expect((await store.readSyncV2())!.syncId, old.syncId);
    sync.setV2Pairing(false);
    await sync.syncNow();
    expect(worker.hasList(old.syncId), isFalse);
  });

  for (final refusal in [
    'cas',
    'devices_active',
    'lost_response',
    'partial_500',
    'pairing',
  ]) {
    test('privacy: last-phone retirement handles $refusal conservatively', () async {
      var intercept = false;
      var deletes = 0;
      late SyncController sync;
      final transport = SyncV2Client(
        base: Uri.parse('https://sync.test'),
        sendRequest: (method, uri, {body, headers = const {}}) async {
          if (intercept &&
              method == 'DELETE' &&
              RegExp(r'^/v2/lists/[^/]+$').hasMatch(uri.path)) {
            deletes++;
            if (refusal == 'cas') {
              expect(headers['If-Match'], isNotNull);
              return SyncResponse(412, const {'etag': '"99"'}, Uint8List(0));
            }
            if (refusal == 'devices_active') {
              return SyncResponse(
                409,
                const {},
                Uint8List.fromList(utf8.encode('{"error":"devices_active"}')),
              );
            }
            if (refusal == 'lost_response' || refusal == 'partial_500') {
              await worker.send(method, uri, body: body, headers: headers);
              if (refusal == 'partial_500') {
                return SyncResponse(
                  500,
                  const {},
                  Uint8List.fromList(utf8.encode('{"error":"internal"}')),
                );
              }
              throw const SyncTransportException(
                SyncFailure.network,
                'lost response',
              );
            }
          }
          final response = await worker.send(
            method,
            uri,
            body: body,
            headers: headers,
          );
          // Pairing starts while the retirement GET is in flight.
          if (intercept &&
              refusal == 'pairing' &&
              method == 'GET' &&
              RegExp(r'^/v2/lists/[^/]+$').hasMatch(uri.path)) {
            sync.setV2Pairing(true);
          }
          return response;
        },
      );
      final (a, b) = await pairedV2(hostTransport: transport);
      sync = a.container.read(syncControllerProvider.notifier);
      final store = a.container.read(familyStoreProvider);
      final old = (await store.readSyncV2())!;
      // No socket in this fixture: A observes B's departure only on this round.
      await b.container.read(syncControllerProvider.notifier).stopSyncing();
      intercept = true;
      await sync.syncNow();
      // Publishing names may queue a follow-up round. If DELETE already
      // succeeded, that round can observe Gone and finish local retirement.
      expect(
        a.container.read(syncControllerProvider).phase,
        refusal == 'lost_response' || refusal == 'partial_500'
            ? isIn([SyncPhase.synced, SyncPhase.waitingForPeer])
            : SyncPhase.synced,
      );
      if (refusal == 'lost_response' || refusal == 'partial_500') {
        expect(worker.hasList(old.syncId), isFalse);
      } else {
        expect(worker.hasList(old.syncId), isTrue);
        expect((await store.readSyncV2())!.syncId, old.syncId);
      }
      expect(deletes, refusal == 'pairing' ? 0 : greaterThan(0));
      intercept = false;
      sync.setV2Pairing(false);
      await sync.syncNow();
      expect(worker.hasList(old.syncId), isFalse);
      expect((await store.readSyncV2())!.syncId, isNot(old.syncId));
    });
  }

  test(
    'privacy: a pending revocation never triggers last-phone deletion',
    () async {
      var offline = false;
      var deletes = 0;
      final transport = SyncV2Client(
        base: Uri.parse('https://sync.test'),
        sendRequest: (method, uri, {body, headers = const {}}) async {
          if (offline && uri.path.endsWith('/revoke')) {
            throw const SyncTransportException(SyncFailure.network, 'offline');
          }
          if (method == 'DELETE' &&
              RegExp(r'^/v2/lists/[^/]+$').hasMatch(uri.path)) {
            deletes++;
          }
          return worker.send(method, uri, body: body, headers: headers);
        },
      );
      final (a, b) = await pairedV2(hostTransport: transport);
      final sync = a.container.read(syncControllerProvider.notifier);
      final store = a.container.read(familyStoreProvider);
      final old = (await store.readSyncV2())!;
      final peer = (await b.container.read(familyStoreProvider).readSyncV2())!;
      offline = true;
      await expectLater(
        sync.removeDevice(peer.deviceId),
        throwsA(isA<SyncTransportException>()),
      );
      await sync.syncNow();
      expect(
        V2SyncState.fromJson(await store.readSyncV2State()).pendingRevocations,
        contains(peer.deviceId),
      );
      expect(deletes, 0);
      expect(worker.hasList(old.syncId), isTrue);
      offline = false;
      await sync.syncNow();
      expect(worker.hasList(old.syncId), isFalse);
      expect((await store.readSyncV2())!.syncId, isNot(old.syncId));
    },
  );

  test('privacy: installation acknowledgement survives restart and removes the invitation', () async {
    var failAcknowledgement = true;
    final base = worker.client();
    final client = SyncV2Client(
      base: base.base,
      sendRequest: (method, uri, {body, headers = const {}}) async {
        if (failAcknowledgement &&
            method == 'DELETE' &&
            uri.path.endsWith('/checkpoint')) {
          throw const SyncTransportException(SyncFailure.network, 'offline');
        }
        return worker.send(method, uri, body: body, headers: headers);
      },
    );
    final (_, b) = await pairedV2(guestTransport: client);
    var store = b.container.read(familyStoreProvider);
    final pending = (await store.pendingInviteAcknowledgement())!;
    final keys = (await b.container.read(deviceKeysStoreProvider).read())!;
    expect(
      await client.pollInviteResult(
        pending['inviteId']!,
        credential: keys.serviceCredential,
      ),
      isA<V2InviteApproved>(),
    );
    b.restart();
    b.container.read(syncControllerProvider);
    await b.container.read(familyControllerProvider.future);
    store = b.container.read(familyStoreProvider);
    expect(await store.pendingInviteAcknowledgement(), pending);
    failAcknowledgement = false;
    await b.container.read(syncControllerProvider.notifier).syncNow();
    await eventually(
      () async => await store.pendingInviteAcknowledgement() == null,
      reason: 'installation acknowledged',
    );
    expect(
      await client.pollInviteResult(
        pending['inviteId']!,
        credential: keys.serviceCredential,
      ),
      isA<V2InviteGone>(),
    );
  });

  test('ataque (hallazgo 2): una lista v2 borrada no deja a los móviles sin '
      'salida: estrenan generación y pueden volver a invitar', () async {
    final (a, b) = await pairedV2();
    final storeA = a.container.read(familyStoreProvider);
    final storeB = b.container.read(familyStoreProvider);
    final old = (await storeB.readSyncV2())!.syncId;
    final oldKey = b.container
        .read(familyControllerProvider.notifier)
        .familyKey;
    // Alguien (el último móvil, o la caducidad) borra la lista del servidor.
    final idA = (await storeA.readSyncV2())!;
    final keysA = (await a.container.read(deviceKeysStoreProvider).read())!;
    final authA = V2Auth(
      syncId: idA.syncId,
      deviceId: idA.deviceId,
      credential: keysA.serviceCredential,
    );
    final client = worker.client();
    expect(
      await client.deleteList(authA, version: worker.versionOf(old)!),
      isA<V2WriteOk>(),
    );
    // B lo ve al sincronizar: syncId, clave y registro nuevos, sin subir nada.
    await b.container.read(syncControllerProvider.notifier).syncNow();
    final fresh = (await storeB.readSyncV2())!;
    expect(fresh.syncId, isNot(old));
    expect(
      b.container.read(familyControllerProvider.notifier).familyKey,
      isNot(oldKey),
    );
    expect(await storeB.readPendingV2(), isNull);
    expect(
      b.container.read(syncControllerProvider).phase,
      SyncPhase.waitingForPeer,
    );
    expect(worker.hasList(fresh.syncId), isFalse);
    expect(titles(b), titles(a));
    // Y puede volver a invitar: crear el syncId nuevo no es 410.
    final host = b.container.read(pairingV2HostProvider.notifier);
    await host.start();
    expect(
      b.container.read(pairingV2HostProvider).phase,
      PairingV2HostPhase.waiting,
    );
    expect(worker.hasList(fresh.syncId), isTrue);
    host.dismiss();
  });

  test('ataque (hallazgo 2): «Borrar todo» con otros móviles solo saca a '
      'este; la lista sigue para los demás', () async {
    final (a, b) = await pairedV2();
    final storeB = b.container.read(familyStoreProvider);
    final sync = (await storeB.readSyncV2())!.syncId;
    final idA = a.container.read(familyControllerProvider).value!.identity!;
    await a.container.read(eraseAllProvider).eraseServerCopy();
    expect(worker.hasList(sync), isTrue);
    expect(worker.devicesOf(sync)[idA.node], isTrue);
    await b.container.read(syncControllerProvider.notifier).syncNow();
    expect(
      b.container.read(syncControllerProvider).phase,
      SyncPhase.waitingForPeer,
    );
    expect(worker.hasList(sync), isFalse);
  });

  test('ataque (hallazgo 7): una migración a medias nunca usa como clave v2 '
      'la que ya tenía el móvil; con pendiente, termina con la suya', () async {
    final a = await phone();
    final famA = a.container.read(familyControllerProvider.notifier);
    await a.container.read(familyControllerProvider.future);
    await famA.createFamily(deviceName: 'Aritz');
    final id = a.container.read(familyControllerProvider).value!.identity!;
    final store = a.container.read(familyStoreProvider);
    final v1Key = famA.familyKey!;
    // El documento ya dice v2 (cortada tras guardarlo, o la marca llegó por
    // la lista v1), con la clave de siempre y sin identidad v2.
    final marked = a.container.read(familyControllerProvider).value!.doc.set(
      HlcClock(node: id.node),
      Collections.meta,
      kProtocolRecordId,
      {kProtocolVersionField: kSyncProtocolV2},
    );
    await famA.installV2(
      listId: id.listId,
      node: id.node,
      key: v1Key,
      doc: marked,
    );
    final host = a.container.read(pairingV2HostProvider.notifier);
    await host.start();
    expect(await store.readSyncV2(), isNotNull);
    expect(famA.familyKey, isNot(v1Key));
    expect(await store.readPendingV2(), isNull);
    host.dismiss();

    // Con un pendiente guardado, se termina con esa clave y ese syncId.
    final b = await phone();
    final famB = b.container.read(familyControllerProvider.notifier);
    await b.container.read(familyControllerProvider.future);
    await famB.createFamily(deviceName: 'Leo');
    final idB = b.container.read(familyControllerProvider).value!.identity!;
    final storeB = b.container.read(familyStoreProvider);
    final pending = await PendingV2.fresh(fromV1: true);
    await storeB.savePendingV2(pending.toJson());
    await famB.installV2(
      listId: idB.listId,
      node: idB.node,
      key: famB.familyKey!,
      doc: b.container.read(familyControllerProvider).value!.doc.set(
        HlcClock(node: idB.node),
        Collections.meta,
        kProtocolRecordId,
        {kProtocolVersionField: kSyncProtocolV2},
      ),
    );
    await b.container.read(syncControllerProvider.notifier).syncNow();
    expect((await storeB.readSyncV2())!.syncId, pending.syncId);
    expect(famB.familyKey, pending.key);
    expect(await storeB.readPendingV2(), isNull);
  });

  test('ataque (hallazgo 5): «Sustituir y unirme» no borra nada hasta estar '
      'dentro de la familia nueva', () async {
    final a = await phone();
    final famA = a.container.read(familyControllerProvider.notifier);
    await a.container.read(familyControllerProvider.future);
    await famA.createFamily(deviceName: 'Aritz');
    final b = await phone();
    final famB = b.container.read(familyControllerProvider.notifier);
    await b.container.read(familyControllerProvider.future);
    await famB.createFamily(deviceName: 'Leo');
    await famB.upsertRecipient(
      const Recipient(id: 'leo', name: 'Leo', colorIndex: 1, archived: false),
    );
    final keysStoreB = b.container.read(deviceKeysStoreProvider);
    final keysBefore = await keysStoreB.read() ?? await keysStoreB.create();
    final listB = b.container.read(familyControllerProvider).value!.identity!;
    final host = a.container.read(pairingV2HostProvider.notifier);
    await host.start();
    final link = a.container.read(pairingV2HostProvider).link!;
    final inviteId = link.substring(link.indexOf('#') + 1);
    final guest = b.container.read(pairingV2GuestProvider.notifier);
    bool stillB() {
      final fam = b.container.read(familyControllerProvider).value!;
      return fam.identity!.listId == listB.listId &&
          fam.fullView.recipients.any((r) => r.id == 'leo');
    }

    await guest.begin(inviteId);
    expect(
      b.container.read(pairingV2GuestProvider).phase,
      PairingV2GuestPhase.confirmReplace,
    );
    await guest.confirmReplace();
    expect(
      b.container.read(pairingV2GuestProvider).phase,
      PairingV2GuestPhase.choosePerson,
    );
    // Otra familia: no hay personas que premarcar.
    expect(b.container.read(pairingV2GuestProvider).selfId, isNull);
    // Confirmado el reemplazo, todo sigue igual: ni la lista ni las claves.
    expect(stillB(), isTrue);
    expect(
      (await keysStoreB.read())!.publicKeys.signing,
      keysBefore.publicKeys.signing,
    );
    await guest.choosePerson(null);
    await eventually(
      () =>
          b.container.read(pairingV2GuestProvider).phase ==
          PairingV2GuestPhase.compare,
      reason: 'B enseña el código',
    );
    // «No coinciden» en B: se queda como estaba.
    guest.cancel();
    expect(stillB(), isTrue);
    expect(
      (await keysStoreB.read())!.publicKeys.signing,
      keysBefore.publicKeys.signing,
    );
    await host.cancel();

    // Otra vez, hasta el final: solo al entrar se sustituye.
    await host.start();
    final again = a.container.read(pairingV2HostProvider).link!;
    await guest.begin(again.substring(again.indexOf('#') + 1));
    await guest.confirmReplace();
    await guest.choosePerson(null);
    await eventually(
      () =>
          a.container.read(pairingV2HostProvider).phase ==
              PairingV2HostPhase.compare &&
          b.container.read(pairingV2GuestProvider).phase ==
              PairingV2GuestPhase.compare,
      reason: 'los dos enseñan el código',
    );
    guest.confirmCode();
    expect(stillB(), isTrue, reason: 'aún sin aprobar');
    await host.confirm();
    await eventually(
      () =>
          b.container.read(pairingV2GuestProvider).phase ==
          PairingV2GuestPhase.done,
      reason: 'B dentro',
    );
    final famNow = b.container.read(familyControllerProvider).value!;
    expect(
      famNow.identity!.listId,
      a.container.read(familyControllerProvider).value!.identity!.listId,
    );
    expect(famNow.fullView.recipients.any((r) => r.id == 'leo'), isFalse);
    expect(famNow.identity!.deviceName, 'Leo');
    expect(
      (await keysStoreB.read())!.publicKeys.signing,
      isNot(keysBefore.publicKeys.signing),
    );
  });

  // ----------------------------------------------- lista de móviles (v2)

  /// A (anfitrión) conecta a [guestPhone] por v2 con [personId] (null:
  /// «Elegir después»). Los dos terminan dentro.
  Future<void> connectV2(
    FakePhone a,
    FakePhone guestPhone, {
    String? personId,
    bool replace = false,
  }) async {
    final host = a.container.read(pairingV2HostProvider.notifier);
    await host.start();
    final link = a.container.read(pairingV2HostProvider).link!;
    final guest = guestPhone.container.read(pairingV2GuestProvider.notifier);
    await guest.begin(link.substring(link.indexOf('#') + 1));
    if (replace) await guest.confirmReplace();
    await guest.choosePerson(personId);
    await eventually(
      () =>
          a.container.read(pairingV2HostProvider).phase ==
              PairingV2HostPhase.compare &&
          guestPhone.container.read(pairingV2GuestProvider).phase ==
              PairingV2GuestPhase.compare,
      reason: 'los dos enseñan el código',
    );
    guest.confirmCode();
    await host.confirm();
    if (personId != null) await host.confirmPerson();
    await eventually(
      () =>
          guestPhone.container.read(pairingV2GuestProvider).phase ==
          PairingV2GuestPhase.done,
      reason: 'el invitado dentro',
    );
    host.dismiss();
  }

  Future<List<FamilyDeviceRow>?> rowsOf(FakePhone p) => p.container
      .read(familyDeviceRowsProvider.future)
      .timeout(const Duration(seconds: 10));

  Future<FakePhone> familyOwner({
    FileStore? disk,
    MemorySecretStore? secrets,
    SyncV2Transport? transport,
    V2FamilyLock? lock,
  }) async {
    final a = await phone(
      disk: disk,
      secrets: secrets,
      transport: transport,
      lock: lock,
    );
    final fam = a.container.read(familyControllerProvider.notifier);
    await a.container.read(familyControllerProvider.future);
    await fam.createFamily(deviceName: 'Aritz');
    for (final (id, name, color) in [
      ('aritz', 'Aritz', 0),
      ('nora', 'Nora', 1),
      ('leo', 'Leo', 2),
    ]) {
      await fam.upsertRecipient(
        Recipient(id: id, name: name, colorIndex: color, archived: false),
      );
    }
    await fam.setSelfRecipient('aritz');
    return a;
  }

  /// Hasta que el invitado confirma el código y el anfitrión aprueba.
  Future<void> approveV2(FakePhone a, FakePhone guestPhone) async {
    final host = a.container.read(pairingV2HostProvider.notifier);
    await host.start();
    final link = a.container.read(pairingV2HostProvider).link!;
    final guest = guestPhone.container.read(pairingV2GuestProvider.notifier);
    await guest.begin(link.substring(link.indexOf('#') + 1));
    await guest.choosePerson('leo');
    await eventually(
      () =>
          a.container.read(pairingV2HostProvider).phase ==
              PairingV2HostPhase.compare &&
          guestPhone.container.read(pairingV2GuestProvider).phase ==
              PairingV2GuestPhase.compare,
      reason: 'los dos enseñan el código',
    );
    guest.confirmCode();
    await host.confirm();
    await host.confirmPerson();
  }

  test('B7: tras el corte, el invitado nace con la marca y la clave común '
      'guardadas, y sincroniza', () async {
    final a = await familyOwner();
    await a.container.read(familyStoreProvider).raiseCommonFormatFloor(2);
    final b = await phone();
    await b.container.read(familyControllerProvider.future);
    await connectV2(a, b, personId: 'leo');
    final store = b.container.read(familyStoreProvider);
    expect(await store.readCommonFormatFloor(), 2);
    expect(await store.readCommonKeys(), isNotNull);
    expect(await store.commonKeysMarked(), isTrue);
    expect(
      V2SyncState.fromJson(await store.readSyncV2State()).commonFormatV2,
      isTrue,
    );
    expect(await store.readPendingV2(), isNull);
    await b.container.read(syncControllerProvider.notifier).syncNow();
    expect(
      b.container.read(syncControllerProvider).phase,
      isNot(SyncPhase.error),
    );
    expect(
      {
        for (final r
            in b.container
                .read(familyControllerProvider)
                .value!
                .fullView
                .recipients)
          r.id,
      },
      {'aritz', 'nora', 'leo'},
    );
  });

  test('P1 (M3): si el invitado falla del todo tras la aprobación, cambia su '
      'credencial, avisa del dispositivo que queda y puede volver a '
      'emparejar', () async {
    final a = await familyOwner();
    final b = await phone();
    await b.container.read(familyControllerProvider.future);
    final before = (await b.container.read(deviceKeysStoreProvider).read())
        ?.serviceCredential;
    worker.tamper = (method, uri, response) {
      if (uri.path.endsWith('/checkpoint') && response.status == 200) {
        final json = response.json();
        return SyncResponse(
          200,
          response.headers,
          Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                ...json,
                'common': encodeBase64Url(List<int>.filled(48, 1)),
              }),
            ),
          ),
        );
      }
      return response;
    };
    await approveV2(a, b);
    await eventually(
      () =>
          b.container.read(pairingV2GuestProvider).phase ==
          PairingV2GuestPhase.failed,
      reason: 'el checkpoint no casa',
    );
    worker.tamper = null;
    expect(b.container.read(pairingV2GuestProvider).leftoverDevice, isTrue);
    final rotated = (await b.container.read(deviceKeysStoreProvider).read())!
        .serviceCredential;
    if (before != null) expect(rotated, isNot(before));
    a.container.read(pairingV2HostProvider.notifier).dismiss();
    // Sin el cambio, volver a responder daría `credential_exists`.
    await connectV2(a, b, personId: 'leo');
    expect(await b.container.read(familyStoreProvider).readSyncV2(), isNotNull);
  });

  test('M3: cancelar después de que el anfitrión apruebe y volver a '
      'emparejar no da credential_exists', () async {
    final a = await familyOwner();
    final b = await phone();
    await b.container.read(familyControllerProvider.future);
    // El invitado no llega a ver la aprobación (sigue esperando).
    worker.tamper = (method, uri, response) =>
        uri.path.endsWith('/result') && response.status == 200
        ? SyncResponse(
            202,
            response.headers,
            Uint8List.fromList(
              utf8.encode(
                jsonEncode({
                  'status': 'pending',
                  'reveal': response.json()['reveal'],
                }),
              ),
            ),
          )
        : response;
    await approveV2(a, b);
    await eventually(
      () =>
          a.container.read(pairingV2HostProvider).phase ==
          PairingV2HostPhase.done,
      reason: 'aprobado en el servidor',
    );
    b.container.read(pairingV2GuestProvider.notifier).cancel();
    worker.tamper = null;
    a.container.read(pairingV2HostProvider.notifier).dismiss();
    await connectV2(a, b, personId: 'leo');
    final syncId =
        (await b.container.read(familyStoreProvider).readSyncV2())!.syncId;
    // El anfitrión, el que se canceló y el de ahora.
    expect(worker.devicesOf(syncId).keys, hasLength(3));
  });

  test('P1 (M3, B2): una instalación cortada antes del documento se deshace '
      'y cambia la credencial al volver a emparejar', () async {
    final a = await familyOwner();
    await a.container.read(familyStoreProvider).raiseCommonFormatFloor(2);
    final secrets = _CrashOnceSecrets('family.syncV2State');
    final b = await phone(secrets: secrets);
    await b.container.read(familyControllerProvider.future);
    await approveV2(a, b);
    await eventually(
      () =>
          b.container.read(pairingV2GuestProvider).phase ==
          PairingV2GuestPhase.failed,
      reason: 'la instalación se corta',
    );
    final store = b.container.read(familyStoreProvider);
    expect(await store.readPendingV2(), isNotNull);
    expect(await store.readCommonKeys(), isNotNull);
    final first = (await b.container.read(deviceKeysStoreProvider).read())!
        .serviceCredential;
    a.container.read(pairingV2HostProvider.notifier).dismiss();
    await connectV2(a, b, personId: 'leo');
    final keys = (await b.container.read(deviceKeysStoreProvider).read())!;
    expect(keys.serviceCredential, isNot(first));
    expect(await store.readPendingV2(), isNull);
    expect(await store.readSyncV2(), isNotNull);
    expect(await store.readCommonFormatFloor(), 2);
    final syncId = (await store.readSyncV2())!.syncId;
    // El anfitrión, el fantasma y el de ahora.
    expect(worker.devicesOf(syncId).keys, hasLength(3));
  });

  test('B7: un reinicio durante la instalación termina con la marca antes '
      'de la identidad, sin volver a emparejar', () async {
    final a = await familyOwner();
    await a.container.read(familyStoreProvider).raiseCommonFormatFloor(2);
    final secrets = _CrashOnceSecrets('family.commonFormatFloor');
    final b = await phone(secrets: secrets);
    await b.container.read(familyControllerProvider.future);
    await approveV2(a, b);
    await eventually(
      () =>
          b.container.read(pairingV2GuestProvider).phase ==
          PairingV2GuestPhase.failed,
      reason: 'la instalación se corta',
    );
    var store = b.container.read(familyStoreProvider);
    expect(await store.readCommonKeys(), isNotNull, reason: 'claves antes');
    // La vuelta siguiente (aquí o tras reiniciar) termina el pendiente: la
    // identidad nunca está sin la marca.
    if (await store.readSyncV2() != null) {
      expect(await store.readCommonFormatFloor(), 2);
    } else {
      expect(await store.readPendingV2(), isNotNull);
    }
    b.restart();
    await b.container.read(familyControllerProvider.future);
    await b.container.read(syncControllerProvider.notifier).syncNow();
    store = b.container.read(familyStoreProvider);
    expect(await store.readCommonFormatFloor(), 2);
    expect(await store.readSyncV2(), isNotNull);
    expect(await store.readPendingV2(), isNull);
    expect(
      worker.devicesOf((await store.readSyncV2())!.syncId).keys,
      hasLength(2),
    );
  });

  for (final version in [3, 5]) {
    test('ronda 4: aprobación v$version deja incompatibilidad propia en el '
        'estado del invitado sin instalar la familia', () async {
      final a = await familyOwner();
      final b = await phone();
      await b.container.read(familyControllerProvider.future);
      final host = a.container.read(pairingV2HostProvider.notifier);
      await host.start();
      final link = a.container.read(pairingV2HostProvider).link!;
      final guest = b.container.read(pairingV2GuestProvider.notifier);
      await guest.begin(link.substring(link.indexOf('#') + 1));
      await guest.choosePerson(null);
      await eventually(
        () =>
            a.container.read(pairingV2HostProvider).phase ==
                PairingV2HostPhase.compare &&
            b.container.read(pairingV2GuestProvider).phase ==
                PairingV2GuestPhase.compare,
      );
      worker.tamper = (method, uri, response) {
        if (uri.path.endsWith('/result') && response.status == 200) {
          final json = response.json();
          if (json['package'] is Map) {
            return SyncResponse(
              response.status,
              response.headers,
              Uint8List.fromList(
                utf8.encode(
                  jsonEncode({
                    ...json,
                    'package': {...json['package'] as Map, 'v': version},
                  }),
                ),
              ),
            );
          }
        }
        return response;
      };
      guest.confirmCode();
      await host.confirm();
      await eventually(
        () =>
            b.container.read(pairingV2GuestProvider).phase ==
            PairingV2GuestPhase.failed,
      );
      expect(
        b.container.read(pairingV2GuestProvider).failureCode,
        'approval:PairingV2VersionMismatchException',
      );
      expect(b.container.read(pairingV2GuestProvider).versionMismatch, isTrue);
      expect(await b.container.read(familyStoreProvider).readSyncV2(), isNull);
    });
  }

  for (final crash in [false, true]) {
    test(
      'ronda 2: controlador y almacén recuperan revocación ${crash ? "tras guardar solo la operación" : "sin red y sin pareja"}',
      () async {
        var offline = false;
        final lock = _ObservedFamilyLock();
        final secrets = _RevocationSecrets();
        final dir = await Directory.systemTemp.createTemp('regalos_revoke');
        addTearDown(() => dir.delete(recursive: true));
        final disk = DirectoryFileStore(
          () async => dir,
          excludeFromBackupHook: (_) async {},
        );
        final client = worker.client();
        final transport = SyncV2Client(
          base: client.base,
          sendRequest: (method, uri, {body, headers = const {}}) async {
            if (offline && uri.path.endsWith('/revoke')) {
              throw const SyncTransportException(
                SyncFailure.network,
                'sin red',
              );
            }
            return worker.send(method, uri, body: body, headers: headers);
          },
        );
        final a = await familyOwner(
          disk: disk,
          secrets: secrets,
          transport: transport,
          lock: lock,
        );
        final b = await phone();
        await b.container.read(familyControllerProvider.future);
        await connectV2(a, b, personId: 'leo');
        final controller = a.container.read(syncControllerProvider.notifier);
        await controller.setEnabled(false);
        await b.container
            .read(syncControllerProvider.notifier)
            .setEnabled(false);
        final store = a.container.read(familyStoreProvider);
        final identity = (await store.readSyncV2())!;
        final other = (await b.container
            .read(familyStoreProvider)
            .readSyncV2())!;
        // Keep a live web credential while this test inspects the old signed
        // registry after recovery. With no other access the copy now retires.
        worker.addCredentialForTesting(
          identity.syncId,
          'nora-web',
          Uint8List(32),
          role: 'web',
        );
        final keys = (await a.container.read(deviceKeysStoreProvider).read())!;
        final anchor = RegistryAnchor(
          deviceId: identity.deviceId,
          signingKey: keys.publicKeys.signing,
        );
        final before = (await store.readRegistry(anchor: anchor))!;
        final view = await before.viewFor(
          me: identity.deviceId,
          mySigningKey: keys.publicKeys.signing,
          livePeople: {'aritz', 'nora', 'leo'},
        );
        final initial = SurpriseKey(
          personId: 'nora',
          epoch: view.epoch,
          bytes: List.filled(32, 42),
          audience: view.entitledDevices('nora'),
        );
        await a.container
            .read(deviceKeysStoreProvider)
            .updateKeyring(identity.listId, (_) => SurpriseKeyring([initial]));
        offline = true;
        secrets.crash = crash;
        // Mientras otra operación v2 mantiene la cola, quitar un móvil no
        // puede leer ni escribir el estado. Después se inyecta el cierre.
        final gate = _WriteGate();
        addTearDown(gate.release);
        final holding = lock.run(gate.pause);
        await gate.entered.future;
        final requested = lock.nextRequest();
        final removal = expectLater(
          controller.removeDevice(other.deviceId),
          throwsA(anyOf(isA<SyncTransportException>(), isA<StateError>())),
        );
        try {
          await requested.timeout(const Duration(seconds: 3));
          expect(
            V2SyncState.fromJson(await store.readSyncV2State())
                .pendingRevocations,
            isEmpty,
          );
        } finally {
          gate.release();
        }
        await holding;
        await removal;
        final pending = V2SyncState.fromJson(await store.readSyncV2State());
        expect(pending.pendingRevocations, contains(other.deviceId));
        if (crash) {
          expect(
            (await store.readRegistry(anchor: anchor))!.sameAs(before),
            isTrue,
            reason: 'el cierre sucede antes de escribir la declaración en el registro',
          );
        } else {
          final after = await (await store.readRegistry(anchor: anchor))!
              .viewFor(
                me: identity.deviceId,
                mySigningKey: keys.publicKeys.signing,
                livePeople: {'aritz', 'nora', 'leo'},
              );
          expect(after.paired, isFalse);
        }
        expect(worker.devicesOf(identity.syncId)[other.deviceId], isFalse);
        a.restart();
        await a.container.read(familyControllerProvider.future);
        final restarted = a.container.read(syncControllerProvider.notifier);
        await eventually(
          () =>
              a.container.read(syncControllerProvider).phase ==
              SyncPhase.disabled,
          reason: 'al reabrir se cargan las preferencias de sincronización',
        );
        offline = false;
        await restarted.setEnabled(true);
        await restarted.syncNow();
        final recoveredStore = a.container.read(familyStoreProvider);
        final recovered = (await recoveredStore.readRegistry(anchor: anchor))!;
        final after = await recovered.viewFor(
          me: identity.deviceId,
          mySigningKey: keys.publicKeys.signing,
          livePeople: {'aritz', 'nora', 'leo'},
        );
        expect(after.revoked, contains(other.deviceId));
        expect(
          after.epoch,
          view.epoch + 1,
          reason: 'reaplicar la declaración firmada no abre otra época',
        );
        expect(worker.devicesOf(identity.syncId)[other.deviceId], isTrue);
        final finalState = V2SyncState.fromJson(
          await recoveredStore.readSyncV2State(),
        );
        expect(finalState.pendingRevocations, isEmpty);
        expect(finalState.revocationOperations, isEmpty);
        final rotated = await a.container
            .read(deviceKeysStoreProvider)
            .readKeyring(identity.listId);
        expect(rotated.latestFor('nora')!.epoch, after.epoch);
        expect(rotated.latestFor('nora')!.kid, isNot(initial.kid));
        final got = await client.getList(
          V2Auth(
            syncId: identity.syncId,
            deviceId: identity.deviceId,
            credential: keys.serviceCredential,
          ),
        ) as V2GetOk;
        final published = await DeviceRegistry.fromJsonVerified(
          got.snapshot.registry,
          anchor: anchor,
        );
        expect(
          (await published.viewFor(
            me: identity.deviceId,
            mySigningKey: keys.publicKeys.signing,
            livePeople: const {},
          )).revoked,
          contains(other.deviceId),
        );
        // Repetir la recuperación no cambia la época ni recrea la operación.
        await restarted.syncNow();
        expect(
          V2SyncState.fromJson(await recoveredStore.readSyncV2State())
              .revocationOperations,
          isEmpty,
        );
      },
    );
  }

  test(
    'ronda 2: A empareja B, B empareja C; revocar B permite reconfirmar C',
    () async {
      final a = await familyOwner();
      final b = await phone();
      final c = await phone();
      await b.container.read(familyControllerProvider.future);
      await c.container.read(familyControllerProvider.future);
      await connectV2(a, b, personId: 'leo');
      await connectV2(b, c, personId: 'nora');
      final controller = a.container.read(syncControllerProvider.notifier);
      await controller.syncNow();
      await controller.setEnabled(false);
      await b.container.read(syncControllerProvider.notifier).setEnabled(false);
      await c.container.read(syncControllerProvider.notifier).setEnabled(false);
      final store = a.container.read(familyStoreProvider);
      final identity = (await store.readSyncV2())!;
      final bId =
          (await b.container.read(familyStoreProvider).readSyncV2())!.deviceId;
      final cId =
          (await c.container.read(familyStoreProvider).readSyncV2())!.deviceId;
      final keys = (await a.container.read(deviceKeysStoreProvider).read())!;
      final anchor = RegistryAnchor(
        deviceId: identity.deviceId,
        signingKey: keys.publicKeys.signing,
      );
      final change = await controller.removeDevice(bId);
      expect(change.orphans.map((d) => d.deviceId), contains(cId));
      expect(
        worker.devicesOf(identity.syncId)[cId],
        isFalse,
        reason: 'un huérfano legítimo conserva su credencial',
      );
      final registry = (await store.readRegistry(anchor: anchor))!;
      final view = await registry.viewFor(
        me: identity.deviceId,
        mySigningKey: keys.publicKeys.signing,
        livePeople: {'aritz', 'nora', 'leo'},
      );
      final cRecord = registry.records.firstWhere((r) => r.deviceId == cId);
      final approved = await approveDevice(
        registry: registry,
        view: view,
        myKeys: keys,
        record: cRecord,
      );
      await store.saveRegistry(approved.registry);
      await controller.setEnabled(true);
      await controller.syncNow();
      await c.container.read(syncControllerProvider.notifier).setEnabled(true);
      await c.container.read(syncControllerProvider.notifier).setEnabled(false);
      // C también confirma de vuelta a A; la confianza no se hereda de B.
      final cStore = c.container.read(familyStoreProvider);
      final cKeys = (await c.container.read(deviceKeysStoreProvider).read())!;
      final cAnchor = RegistryAnchor(
        deviceId: cId,
        signingKey: cKeys.publicKeys.signing,
      );
      final cRegistry = (await cStore.readRegistry(anchor: cAnchor))!;
      final cView = await cRegistry.viewFor(
        me: cId,
        mySigningKey: cKeys.publicKeys.signing,
        livePeople: {'aritz', 'nora', 'leo'},
      );
      expect(
        cView.detached.map((d) => d.deviceId),
        contains(identity.deviceId),
      );
      final confirmedBack = await approveDevice(
        registry: cRegistry,
        view: cView,
        myKeys: cKeys,
        record: cRegistry.records.firstWhere(
          (r) => r.deviceId == identity.deviceId,
        ),
      );
      await cStore.saveRegistry(confirmedBack.registry);
      await c.container.read(syncControllerProvider.notifier).setEnabled(true);
      await c.container.read(syncControllerProvider.notifier).syncNow();
      expect(c.container.read(syncControllerProvider).phase, SyncPhase.synced);
      expect((await rowsOf(a))!.map((r) => r.deviceId), contains(cId));
    },
  );

  test(
    '11: instalar persiste minVersion antes de la primera sincronización',
    () async {
      final a = await familyOwner();
      final secrets = _ApprovalStateSecrets();
      final b = await phone(secrets: secrets);
      await b.container.read(familyControllerProvider.future);
      int? signedFloor;
      worker.tamper = (method, uri, response) {
        if (uri.path.endsWith('/result') && response.status == 200) {
          signedFloor =
              (response.json()['package'] as Map)['minVersion'] as int;
        }
        return response;
      };
      await connectV2(a, b, personId: 'leo');
      expect(secrets.installedVersions, isNotEmpty);
      expect(
        secrets.installedVersions.first,
        isNotNull,
        reason: 'el suelo de rollback se guarda al instalar, antes de reanudar',
      );
      expect(secrets.installedVersions.first, greaterThanOrEqualTo(2));
      expect(
        secrets.installedVersions.first,
        greaterThanOrEqualTo(signedFloor!),
      );
    },
  );

  test(
    'filas de móviles (provider real): al emparejar entra el invitado con '
    'su persona y un tercero que entra las refresca tras sincronizar',
    () async {
      final a = await familyOwner();
      final b = await phone();
      final c = await phone();
      await b.container.read(familyControllerProvider.future);
      await c.container.read(familyControllerProvider.future);
      // Con la familia aún en v1 no hay lista v2.
      expect(await rowsOf(a), isNull);
      final subA = a.container.listen(familyDeviceRowsProvider, (_, _) {});
      addTearDown(subA.close);

      await connectV2(a, b, personId: 'nora');
      await eventually(
        () async => (await rowsOf(a))?.length == 2,
        reason: 'el anfitrión ve a los dos móviles',
      );
      final rowsA = (await rowsOf(a))!;
      expect(rowsA.first.isSelf, isTrue);
      expect(rowsA.first.deviceName, 'Aritz');
      expect(rowsA.first.personId, 'aritz');
      expect(rowsA.last.isSelf, isFalse);
      expect(rowsA.last.personId, 'nora');

      // B llega a saber de A; luego C entra por A y B solo se entera al
      // sincronizar (cambia solo el registro).
      await a.container.read(syncControllerProvider.notifier).syncNow();
      await b.container.read(syncControllerProvider.notifier).syncNow();
      final subB = b.container.listen(familyDeviceRowsProvider, (_, _) {});
      addTearDown(subB.close);
      expect((await rowsOf(b))!, hasLength(2));
      await connectV2(a, c, personId: 'leo');
      await a.container.read(syncControllerProvider.notifier).syncNow();
      await eventually(
        () async => (await rowsOf(a))?.length == 3,
        reason: 'el anfitrión ve a los tres móviles',
      );
      await b.container.read(syncControllerProvider.notifier).syncNow();
      await eventually(
        () async => (await rowsOf(b))?.length == 3,
        reason: 'B refresca las filas tras sincronizar',
      );
      final rowsB = (await rowsOf(b))!;
      expect(rowsB.first.isSelf, isTrue);
      expect({for (final r in rowsB) r.personId}, {'aritz', 'nora', 'leo'});
      // Las personas con móvil salen de la misma lectura.
      expect(await b.container.read(devicePersonIdsProvider.future), {
        'aritz',
        'nora',
        'leo',
      });
    },
  );

  test('emparejar enciende la sincronización apagada del anfitrión', () async {
    final a = await familyOwner();
    final b = await phone();
    await b.container.read(familyControllerProvider.future);
    final listId = a.container
        .read(familyControllerProvider)
        .value!
        .identity!
        .listId;
    await eventually(
      () =>
          a.container.read(syncControllerProvider).phase != SyncPhase.noFamily,
      reason: 'A ya conoce su lista',
    );
    await a.container.read(syncControllerProvider.notifier).setEnabled(false);
    final prefs = a.container.read(sharedPreferencesProvider);
    expect(prefs.getStringList('sync.offLists'), contains(listId));
    expect(a.container.read(syncControllerProvider).phase, SyncPhase.disabled);

    await connectV2(a, b);
    await eventually(
      () =>
          a.container.read(syncControllerProvider).phase != SyncPhase.disabled,
      reason: 'emparejar enciende la sincronización del anfitrión',
    );
    expect(
      prefs.getStringList('sync.offLists') ?? const <String>[],
      isNot(contains(listId)),
    );
  });

  test('«Sustituir y unirme»: la lista nueva del invitado queda encendida y '
      'la preferencia de la anterior no se toca', () async {
    final a = await familyOwner();
    final b = await phone();
    final famB = b.container.read(familyControllerProvider.notifier);
    await b.container.read(familyControllerProvider.future);
    await famB.createFamily(deviceName: 'Leo');
    final oldList = b.container
        .read(familyControllerProvider)
        .value!
        .identity!
        .listId;
    await eventually(
      () =>
          b.container.read(syncControllerProvider).phase != SyncPhase.noFamily,
      reason: 'B ya conoce su lista',
    );
    await b.container.read(syncControllerProvider.notifier).setEnabled(false);
    final prefs = b.container.read(sharedPreferencesProvider);
    expect(prefs.getStringList('sync.offLists'), [oldList]);

    await connectV2(a, b, replace: true);
    final newList = b.container
        .read(familyControllerProvider)
        .value!
        .identity!
        .listId;
    expect(newList, isNot(oldList));
    await eventually(
      () =>
          b.container.read(syncControllerProvider).phase != SyncPhase.disabled,
      reason: 'la lista nueva queda encendida',
    );
    expect(prefs.getStringList('sync.offLists'), [oldList]);
  });
  // ------------------------------- antes de tiendas (hallazgos 6, 13, 14)

  test('ataque (hallazgo 6): un anfitrión con el mismo listId y sin la '
      'clave v1 no entra como «la misma lista»', () async {
    // B: familia v1 con datos.
    final b = await phone();
    final famB = b.container.read(familyControllerProvider.notifier);
    await b.container.read(familyControllerProvider.future);
    await famB.createFamily(deviceName: 'Leo');
    await famB.upsertRecipient(
      const Recipient(id: 'leo', name: 'Leo', colorIndex: 1, archived: false),
    );
    final listB = b.container.read(familyControllerProvider).value!.identity!;
    // A copia el listId (público) de B, con otra clave, y lo pasa a v2.
    final a = await phone();
    await a.container.read(familyControllerProvider.future);
    await a.container
        .read(familyControllerProvider.notifier)
        .joinFamily(
          payload: PairingPayload(
            listId: listB.listId,
            key: await FamilyKey.generate(),
            deviceName: 'Leo',
          ),
          deviceName: 'Intruso',
        );
    final host = a.container.read(pairingV2HostProvider.notifier);
    await host.start();
    await host.confirmMigration();
    final link = a.container.read(pairingV2HostProvider).link!;
    expect(
      a.container.read(familyControllerProvider).value!.identity!.listId,
      listB.listId,
    );
    final guest = b.container.read(pairingV2GuestProvider.notifier);
    await guest.begin(link.substring(link.indexOf('#') + 1));
    // Sin la prueba de la clave v1 es otra familia: sustituir, con
    // confirmación, y sin enseñar las personas de B.
    expect(
      b.container.read(pairingV2GuestProvider).phase,
      PairingV2GuestPhase.confirmReplace,
    );
    final fam = b.container.read(familyControllerProvider).value!;
    expect(fam.identity!.node, listB.node);
    expect(fam.fullView.recipients.map((r) => r.id), ['leo']);
    guest.cancel();
    await host.cancel();
  });

  test('ataque (hallazgo 6): un móvil que ya está en v2 nunca entra como '
      '«la misma lista»', () async {
    final a = await familyOwner();
    final b = await phone();
    await b.container.read(familyControllerProvider.future);
    await connectV2(a, b, personId: 'nora');
    final before = b.container.read(familyControllerProvider).value!;
    // Otra invitación con el mismo listId: B ya es v2 y tiene que confirmar
    // que sustituye; no se queda con su nodo ni enseña sus personas.
    final host = a.container.read(pairingV2HostProvider.notifier);
    await host.start();
    final link = a.container.read(pairingV2HostProvider).link!;
    final guest = b.container.read(pairingV2GuestProvider.notifier);
    await guest.begin(link.substring(link.indexOf('#') + 1));
    expect(
      b.container.read(pairingV2GuestProvider).phase,
      PairingV2GuestPhase.confirmReplace,
    );
    await guest.confirmReplace();
    final choose = b.container.read(pairingV2GuestProvider);
    expect(choose.phase, PairingV2GuestPhase.choosePerson);
    expect(choose.people, isEmpty);
    expect(
      b.container.read(familyControllerProvider).value!.identity!.node,
      before.identity!.node,
      reason: 'nada cambia hasta entrar',
    );
    guest.cancel();
    await host.cancel();
  });

  test('ataque (hallazgo 13): un móvil en v2 rechaza un QR v1 con la clave '
      'sin tocar nada', () async {
    final a = await familyOwner();
    final b = await phone();
    await b.container.read(familyControllerProvider.future);
    await connectV2(a, b, personId: 'nora');
    final store = b.container.read(familyStoreProvider);
    final v2Before = (await store.readSyncV2())!;
    final keyBefore = b.container
        .read(familyControllerProvider.notifier)
        .familyKey;
    final listId = b.container
        .read(familyControllerProvider)
        .value!
        .identity!
        .listId;
    // Quien tenga la clave v1 (o cualquiera, con el listId) enseña un QR v1.
    for (final replace in [false, true]) {
      final qr = PairingPayload(
        listId: listId,
        key: await FamilyKey.generate(),
        deviceName: 'Intruso',
      ).toQrText();
      await expectLater(
        b.container
            .read(pairingServiceProvider)
            .joinFromQr(qr, replace: replace),
        throwsA(isA<V1PairingOnV2Exception>()),
      );
    }
    expect((await store.readSyncV2())!.syncId, v2Before.syncId);
    expect(
      b.container.read(familyControllerProvider.notifier).familyKey,
      keyBefore,
    );
    expect(
      b.container.read(familyControllerProvider).value!.identity!.paired,
      isTrue,
    );
  });

  test(
    'a killed open invitation is already marked and cleaned on restart',
    () async {
      final a = await familyOwner();
      await a.container.read(pairingV2HostProvider.notifier).start();
      final store = a.container.read(familyStoreProvider);
      final sid = (await store.readSyncV2())!.syncId;
      expect(
        a.container
            .read(sharedPreferencesProvider)
            .getString('sync.v2InviteCopy'),
        sid,
      );
      expect(worker.hasList(sid), isTrue);
      // Dispose without cancel/dismiss, as when the OS kills the process.
      a.restart();
      await a.container.read(familyControllerProvider.future);
      a.container.read(syncControllerProvider);
      await eventually(
        () => !worker.hasList(sid),
        reason: 'startup cleans the marked invitation',
      );
      await eventually(
        () async =>
            (await a.container.read(familyStoreProvider).readSyncV2())!
                .syncId !=
            sid,
        reason: 'startup rotates the retired generation',
      );
    },
  );

  test('ataque (hallazgo 14): cancelar una invitación no deja la lista en el '
      'servidor, también si la red falla al cancelar', () async {
    final a = await familyOwner();
    final store = a.container.read(familyStoreProvider);
    final host = a.container.read(pairingV2HostProvider.notifier);
    await host.start();
    final first = (await store.readSyncV2())!.syncId;
    expect(worker.hasList(first), isTrue, reason: 'subió para invitar');
    await host.cancel();
    expect(worker.hasList(first), isFalse);
    // Su syncId ya no vuelve: hay generación nueva y no ha subido nada.
    final second = (await store.readSyncV2())!.syncId;
    expect(second, isNot(first));
    expect(worker.hasList(second), isFalse);
    expect(
      a.container.read(familyControllerProvider).value!.fullView.recipients,
      hasLength(3),
      reason: 'lo local se queda',
    );

    // Otra vez, ahora sin red al cancelar: queda apuntada y se borra al
    // volver a abrir la app.
    await host.start();
    expect(
      a.container.read(pairingV2HostProvider).phase,
      PairingV2HostPhase.waiting,
    );
    expect(worker.hasList(second), isTrue);
    worker.offline = true;
    await host.cancel();
    expect(worker.hasList(second), isTrue);
    worker.offline = false;
    a.restart();
    await a.container.read(familyControllerProvider.future);
    a.container.read(syncControllerProvider);
    await eventually(
      () => !worker.hasList(second),
      reason: 'el reintento la borra',
    );
    await eventually(
      () async =>
          (await a.container.read(familyStoreProvider).readSyncV2())!.syncId !=
          second,
      reason: 'y estrena generación',
    );
  });

  test('hallazgo 14: con otro móvil dentro, la lista se queda', () async {
    final a = await familyOwner();
    final b = await phone();
    await b.container.read(familyControllerProvider.future);
    await connectV2(a, b, personId: 'nora');
    final syncId =
        (await a.container.read(familyStoreProvider).readSyncV2())!.syncId;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(worker.hasList(syncId), isTrue);
    // Una invitación cancelada con otro móvil ya dentro tampoco la borra.
    final host = a.container.read(pairingV2HostProvider.notifier);
    await host.start();
    await host.cancel();
    expect(worker.hasList(syncId), isTrue);
    expect(
      (await a.container.read(familyStoreProvider).readSyncV2())!.syncId,
      syncId,
    );
  });
  SyncResponse jsonResponse(SyncResponse r, Map<String, Object?> body) =>
      SyncResponse(
        r.status,
        r.headers,
        Uint8List.fromList(utf8.encode(jsonEncode(body))),
      );

  test('hallazgo 14: el servidor manda; con otra credencial viva o una '
      'versión que cambia (412), la lista se queda', () async {
    var staleDeletes = false;
    final a = await familyOwner(
      transport: SyncV2Client(
        base: Uri.parse('https://sync.test'),
        sendRequest: (method, uri, {body, headers = const {}}) async {
          // El DELETE no llega a la lista: otra escritura se ha adelantado.
          if (staleDeletes &&
              method == 'DELETE' &&
              RegExp(r'^/v2/lists/[^/]+$').hasMatch(uri.path)) {
            return SyncResponse(412, const {'etag': '"99"'}, Uint8List(0));
          }
          return worker.send(method, uri, body: body, headers: headers);
        },
        openSocket: worker.socket,
      ),
    );
    final store = a.container.read(familyStoreProvider);
    final host = a.container.read(pairingV2HostProvider.notifier);
    final prefs = a.container.read(sharedPreferencesProvider);
    bool isList(String method, Uri uri, String want) =>
        method == want && RegExp(r'^/v2/lists/[^/]+$').hasMatch(uri.path);

    // 1. El registro local dice «solo», pero el servidor tiene otra
    //    credencial sin revocar: no se borra y la marca se quita.
    await host.start();
    final syncId = (await store.readSyncV2())!.syncId;
    worker.tamper = (method, uri, r) {
      if (!isList(method, uri, 'GET') || r.status != 200) return r;
      final body = r.json();
      return jsonResponse(r, {
        ...body,
        'devices': [
          ...body['devices']! as List,
          {'deviceId': 'intruso', 'revoked': false},
        ],
      });
    };
    await host.cancel();
    expect(worker.hasList(syncId), isTrue);
    expect((await store.readSyncV2())!.syncId, syncId);
    expect(prefs.getString('sync.v2InviteCopy'), isNull);

    // 2. La versión cambia entre el GET y el DELETE (412 cada vez): no se
    //    borra ni se estrena generación; queda apuntada para reintentar.
    await host.start();
    worker.tamper = null;
    staleDeletes = true;
    await host.cancel();
    expect(worker.hasList(syncId), isTrue);
    expect((await store.readSyncV2())!.syncId, syncId);
    expect(prefs.getString('sync.v2InviteCopy'), syncId);
    worker.tamper = null;
  });

  test('cerrar y reabrir «Invitar» con el borrado en vuelo no borra la lista '
      'nueva', () async {
    final a = await familyOwner();
    final store = a.container.read(familyStoreProvider);
    final host = a.container.read(pairingV2HostProvider.notifier);
    await host.start();
    final syncId = (await store.readSyncV2())!.syncId;
    // Se cierra (el DELETE de la invitación sale) y se vuelve a abrir antes
    // de que vuelva.
    host.dismiss();
    await host.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final state = a.container.read(pairingV2HostProvider);
    expect(state.phase, PairingV2HostPhase.waiting);
    expect((await store.readSyncV2())!.syncId, syncId);
    expect(worker.hasList(syncId), isTrue, reason: 'la nueva la necesita');
    await host.cancel();
    expect(worker.hasList(syncId), isFalse);
  });

  test('hueco (hallazgo 14): si aprobar falla, la lista se queda porque el '
      'registro ya tiene la ficha del invitado', () async {
    final a = await familyOwner();
    final b = await phone();
    await b.container.read(familyControllerProvider.future);
    final store = a.container.read(familyStoreProvider);
    final host = a.container.read(pairingV2HostProvider.notifier);
    await host.start();
    final syncId = (await store.readSyncV2())!.syncId;
    final link = a.container.read(pairingV2HostProvider).link!;
    final guest = b.container.read(pairingV2GuestProvider.notifier);
    await guest.begin(link.substring(link.indexOf('#') + 1));
    await guest.choosePerson(null);
    await eventually(
      () =>
          a.container.read(pairingV2HostProvider).phase ==
              PairingV2HostPhase.compare &&
          b.container.read(pairingV2GuestProvider).phase ==
              PairingV2GuestPhase.compare,
      reason: 'los dos enseñan el código',
    );
    worker.tamper = (method, uri, r) =>
        method == 'POST' && uri.path.endsWith('/approve')
        ? SyncResponse(500, const {}, Uint8List(0))
        : r;
    await host.confirm();
    worker.tamper = null;
    expect(
      a.container.read(pairingV2HostProvider).phase,
      PairingV2HostPhase.failed,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(worker.hasList(syncId), isTrue);
    expect((await store.readSyncV2())!.syncId, syncId);
    guest.cancel();
  });

  test('ataque (hallazgo 6): un móvil v2 no es «misma lista» ni con una '
      'prueba hecha con su propia clave de la familia', () async {
    final a = await familyOwner();
    final b = await phone();
    await b.container.read(familyControllerProvider.future);
    await connectV2(a, b, personId: 'nora');
    final keyB = b.container.read(familyControllerProvider.notifier).familyKey!;
    final host = a.container.read(pairingV2HostProvider.notifier);
    await host.start();
    final link = a.container.read(pairingV2HostProvider).link!;
    final inviteId = link.substring(link.indexOf('#') + 1);
    final offer = await PairingOffer.fromJson(
      (await worker.client().getOffer(inviteId)).offer,
    );
    final proof = encodeBase64Url(v1ListProof(keyB, offer));
    worker.tamper = (method, uri, r) {
      if (method != 'GET' || !uri.path.endsWith('/offer') || r.status != 200) {
        return r;
      }
      final body = r.json();
      return jsonResponse(r, {
        ...body,
        'offer': {
          ...Map<String, Object?>.from(body['offer']! as Map),
          kV1ProofField: proof,
        },
      });
    };
    final guest = b.container.read(pairingV2GuestProvider.notifier);
    await guest.begin(inviteId);
    worker.tamper = null;
    expect(
      b.container.read(pairingV2GuestProvider).phase,
      PairingV2GuestPhase.confirmReplace,
    );
    await guest.confirmReplace();
    expect(b.container.read(pairingV2GuestProvider).people, isEmpty);
    guest.cancel();
    await host.cancel();
  });

  test('hallazgo 6: un móvil que migró sin estar emparejado en v1 también '
      'prueba su clave v1', () async {
    final a = await phone();
    final famA = a.container.read(familyControllerProvider.notifier);
    await a.container.read(familyControllerProvider.future);
    await famA.createFamily(deviceName: 'Aritz');
    await famA.upsertRecipient(
      const Recipient(id: 'nora', name: 'Nora', colorIndex: 0, archived: false),
    );
    final idA = a.container.read(familyControllerProvider).value!.identity!;
    // B leyó el QR v1 de A, pero A no llegó a verlo (sigue sin emparejar).
    final b = await phone();
    await b.container.read(familyControllerProvider.future);
    await b.container
        .read(familyControllerProvider.notifier)
        .joinFamily(
          payload: PairingPayload(
            listId: idA.listId,
            key: famA.familyKey!,
            deviceName: 'Aritz',
          ),
          deviceName: 'Leo',
        );
    await b.container
        .read(familyControllerProvider.notifier)
        .upsertRecipient(
          const Recipient(
            id: 'nora',
            name: 'Nora',
            colorIndex: 0,
            archived: false,
          ),
        );
    expect(idA.paired, isFalse);
    final host = a.container.read(pairingV2HostProvider.notifier);
    await host.start();
    expect(await a.container.read(familyStoreProvider).readLegacyV1(), isNull);
    final link = a.container.read(pairingV2HostProvider).link!;
    final guest = b.container.read(pairingV2GuestProvider.notifier);
    await guest.begin(link.substring(link.indexOf('#') + 1));
    final choose = b.container.read(pairingV2GuestProvider);
    expect(choose.phase, PairingV2GuestPhase.choosePerson);
    expect(choose.people.map((p) => p.id), ['nora']);
    guest.cancel();
    await host.cancel();
  });
  test('cancelar y cerrar la pantalla con el borrado de la invitación en '
      'vuelo sigue borrando la lista y suelta el emparejamiento', () async {
    Completer<void>? hold;
    final a = await familyOwner(
      transport: SyncV2Client(
        base: Uri.parse('https://sync.test'),
        sendRequest: (method, uri, {body, headers = const {}}) async {
          if (method == 'DELETE' && uri.path.contains('/invites/')) {
            await hold?.future;
          }
          return worker.send(method, uri, body: body, headers: headers);
        },
        openSocket: worker.socket,
      ),
    );
    final store = a.container.read(familyStoreProvider);
    final host = a.container.read(pairingV2HostProvider.notifier);
    await host.start();
    final syncId = (await store.readSyncV2())!.syncId;
    expect(worker.hasList(syncId), isTrue);
    hold = Completer<void>();
    final cancelling = host.cancel();
    // Se cierra la pantalla con el DELETE retenido.
    host.dismiss();
    hold.complete();
    await cancelling;
    expect(worker.hasList(syncId), isFalse, reason: 'la copia se borra');
    expect(
      a.container.read(pairingV2HostProvider).phase,
      PairingV2HostPhase.idle,
    );
    // Sin emparejamiento en marcha, una vuelta con el móvil solo no habla
    // con el servidor: no vuelve a crear la lista.
    final puts = worker.calls['PUT list'] ?? 0;
    await a.container.read(syncControllerProvider.notifier).syncNow();
    expect(worker.calls['PUT list'] ?? 0, puts);
    expect(
      a.container.read(syncControllerProvider).phase,
      SyncPhase.waitingForPeer,
    );
  });

  /// [b] entra, sustituyendo su familia v2, en la de [host].
  Future<void> replaceInto(FakePhone host, FakePhone b) async {
    final h = host.container.read(pairingV2HostProvider.notifier);
    await h.start();
    final link = host.container.read(pairingV2HostProvider).link!;
    final guest = b.container.read(pairingV2GuestProvider.notifier);
    await guest.begin(link.substring(link.indexOf('#') + 1));
    expect(
      b.container.read(pairingV2GuestProvider).phase,
      PairingV2GuestPhase.confirmReplace,
    );
    await guest.confirmReplace();
    await guest.choosePerson(null);
    await eventually(
      () =>
          host.container.read(pairingV2HostProvider).phase ==
              PairingV2HostPhase.compare &&
          b.container.read(pairingV2GuestProvider).phase ==
              PairingV2GuestPhase.compare,
      reason: 'los dos enseñan el código',
    );
    guest.confirmCode();
    await h.confirm();
    await eventually(
      () =>
          b.container.read(pairingV2GuestProvider).phase ==
          PairingV2GuestPhase.done,
      reason: 'dentro de la nueva',
    );
    h.dismiss();
  }

  test(
    'sustituir desde un móvil v2 que estaba solo borra su lista vieja',
    () async {
      final b = await familyOwner();
      await b.container.read(pairingV2HostProvider.notifier).start();
      final old = (await b.container.read(familyStoreProvider).readSyncV2())!;
      expect(worker.hasList(old.syncId), isTrue);
      final c = await familyOwner();
      await replaceInto(c, b);
      expect(worker.hasList(old.syncId), isFalse);
      final now = (await b.container.read(familyStoreProvider).readSyncV2())!;
      expect(now.syncId, isNot(old.syncId));
    },
  );

  test('sustituir desde un móvil v2 con otros dentro conserva su lista y '
      'solo revoca la credencial propia', () async {
    final a = await familyOwner();
    final b = await phone();
    await b.container.read(familyControllerProvider.future);
    await connectV2(a, b, personId: 'nora');
    final old = (await b.container.read(familyStoreProvider).readSyncV2())!;
    final hostId =
        (await a.container.read(familyStoreProvider).readSyncV2())!.deviceId;
    final c = await familyOwner();
    await replaceInto(c, b);
    expect(worker.hasList(old.syncId), isTrue);
    final devices = worker.devicesOf(old.syncId);
    expect(devices[old.deviceId], isTrue, reason: 'B sale');
    expect(devices[hostId], isFalse, reason: 'A sigue dentro');
  });
}

class _ApprovalStateSecrets extends MemorySecretStore {
  final installedVersions = <Object?>[];

  @override
  Future<void> write(String key, String value) async {
    if (key == 'family.syncV2State') {
      final state = jsonDecode(value) as Map;
      if (state['c'] == true) installedVersions.add(state['v']);
    }
    await super.write(key, value);
  }
}

Future<FamilyKey?> _v1Key(FamilyStore store) async {
  final raw = await store.readLegacyV1();
  return raw is Map ? FamilyKey.fromBase64Url(raw['k'] as String) : null;
}

// Observa la petición, antes de esperar turno. No cambia el orden de la cola.
class _ObservedFamilyLock extends V2FamilyLock {
  Completer<void>? _requested;

  Future<void> nextRequest() => (_requested = Completer<void>()).future;

  @override
  Future<T> run<T>(Future<T> Function() transaction) {
    final requested = _requested;
    _requested = null;
    requested?.complete();
    return super.run(transaction);
  }
}

class _WriteGate {
  final entered = Completer<void>();
  final _resume = Completer<void>();

  Future<void> pause() async {
    entered.complete();
    await _resume.future;
  }

  void release() {
    if (!_resume.isCompleted) _resume.complete();
  }
}

class _RegistryDisk extends MemoryFileStore {
  _WriteGate? gate;
  Future<void> Function()? afterRegistry;

  @override
  Future<void> writeAtomic(String name, Uint8List bytes) async {
    if (name == 'family.registry') {
      final waiting = gate;
      gate = null;
      await waiting?.pause();
    }
    await super.writeAtomic(name, bytes);
    if (name == 'family.registry') await afterRegistry?.call();
  }
}

class _VersionSecrets extends MemorySecretStore {
  _WriteGate? gate;
  final versions = <int>[];

  @override
  Future<void> write(String key, String value) async {
    if (key == 'family.syncV2State') {
      final waiting = gate;
      gate = null;
      await waiting?.pause();
      final state = V2SyncState.fromJson(jsonDecode(value));
      if (state.version != null) versions.add(state.version!);
    }
    await super.write(key, value);
  }
}

class _RevocationSecrets extends MemorySecretStore {
  bool crash = false;

  @override
  Future<void> write(String key, String value) async {
    await super.write(key, value);
    if (crash &&
        key == 'family.syncV2State' &&
        V2SyncState.fromJson(jsonDecode(value)).pendingRevocations.isNotEmpty) {
      crash = false;
      throw StateError('cierre justo después de persistir la intención');
    }
  }
}

/// Un almacén seguro que falla una vez al escribir [key] (un cierre justo
/// antes de esa escritura).
class _CrashOnceSecrets extends MemorySecretStore {
  _CrashOnceSecrets(this.key);

  final String key;
  bool _crashed = false;

  @override
  Future<void> write(String key, String value) async {
    if (!_crashed && key == this.key) {
      _crashed = true;
      throw StateError('cierre justo antes de escribir $key');
    }
    await super.write(key, value);
  }
}
