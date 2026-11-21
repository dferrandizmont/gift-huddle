// Quitar un móvil y aprobar un huérfano con el controlador real (fase 3, lote
// «Móviles»): tres móviles emparejados por v2 en cadena (Aritz - Nora - Leo),
// el arnés de `pairing_v2_app_test.dart`.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/pairing_v2.dart' show SyncIdentityV2;
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/sync/application/family_device_review.dart';
import 'package:regalos/features/sync/application/family_device_rows.dart';
import 'package:regalos/features/sync/application/pairing_v2_controller.dart';
import 'package:regalos/features/sync/application/sync_controller.dart';
import 'package:regalos/features/sync/data/sync_config.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';
import 'package:regalos/core/prefs/shared_preferences_provider.dart';

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
    SyncV2Transport? v2,
    List<Override> extra = const <Override>[],
  }) async {
    final prefs = await mockPrefs();
    final p = FakePhone(
      prefs: prefs,
      syncHost: null,
      extraOverrides: [
        syncHostProvider.overrideWithValue(kTestHost),
        invitationOriginProvider.overrideWithValue(''),
        syncTransportProvider.overrideWithValue(v1.connect()),
        syncV2TransportProvider.overrideWithValue(v2 ?? worker.client()),
        syncTimingProvider.overrideWithValue(kFastTiming),
        ...extra,
      ],
    );
    addTearDown(p.dispose);
    p.container.read(syncControllerProvider);
    p.container.read(sharedPreferencesProvider);
    return p;
  }

  Future<void> connectV2(
    FakePhone host,
    FakePhone guestPhone, {
    String? personId,
  }) async {
    final h = host.container.read(pairingV2HostProvider.notifier);
    await h.start();
    final link = host.container.read(pairingV2HostProvider).link!;
    final guest = guestPhone.container.read(pairingV2GuestProvider.notifier);
    await guest.begin(link.substring(link.indexOf('#') + 1));
    await guest.choosePerson(personId);
    await eventually(
      () =>
          host.container.read(pairingV2HostProvider).phase ==
              PairingV2HostPhase.compare &&
          guestPhone.container.read(pairingV2GuestProvider).phase ==
              PairingV2GuestPhase.compare,
      reason: 'los dos enseñan el código',
    );
    guest.confirmCode();
    await h.confirm();
    if (personId != null) await h.confirmPerson();
    await eventually(
      () =>
          guestPhone.container.read(pairingV2GuestProvider).phase ==
          PairingV2GuestPhase.done,
      reason: 'el invitado dentro',
    );
    h.dismiss();
  }

  Future<List<String>> activeIds(FakePhone p) async => [
    for (final r in (await p.container.read(familyDeviceRowsProvider.future))!)
      r.deviceId,
  ];

  Future<Map<String, bool>> serverDevices(FakePhone p) async =>
      worker.devicesOf(
        (await p.container.read(familyStoreProvider).readSyncV2())!.syncId,
      );

  Future<FakePhone> ownerWith(
    SyncV2Transport? v2, {
    List<Override> extra = const <Override>[],
  }) async {
    final a = await phone(v2: v2, extra: extra);
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

  Future<FakePhone> familyOwner() => ownerWith(null);

  SyncController syncOf(FakePhone p) =>
      p.container.read(syncControllerProvider.notifier);

  Future<String> selfId(FakePhone p) async =>
      (await p.container.read(familyDeviceRowsProvider.future))!
          .firstWhere((r) => r.isSelf)
          .deviceId;

  /// Cadena Aritz - Nora - Leo con Aritz de dueño: Leo solo está unido a
  /// Aritz por Nora. Devuelve los tres móviles y los ids de Nora y Leo.
  Future<(FakePhone, FakePhone, FakePhone, String, String)> chain({
    SyncV2Transport? v2,
    List<Override> extra = const <Override>[],
  }) async {
    final a = await ownerWith(v2, extra: extra);
    final b = await phone();
    final c = await phone();
    await b.container.read(familyControllerProvider.future);
    await c.container.read(familyControllerProvider.future);
    await connectV2(a, b, personId: 'nora');
    await syncOf(a).syncNow();
    await syncOf(b).syncNow();
    await connectV2(b, c, personId: 'leo');
    await syncOf(c).syncNow();
    await syncOf(b).syncNow();
    await syncOf(a).syncNow();
    await eventually(
      () async => (await activeIds(a)).length == 3,
      reason: 'Aritz ve a los tres',
    );
    final deviceB = (await b.container.read(familyDeviceRowsProvider.future))!
        .firstWhere((r) => r.isSelf)
        .deviceId;
    final deviceC = (await c.container.read(familyDeviceRowsProvider.future))!
        .firstWhere((r) => r.isSelf)
        .deviceId;
    return (a, b, c, deviceB, deviceC);
  }

  test('N7 se comprueba dentro de la misma transacción que revoca: sin '
      'aceptar el aviso, no se quita nada', () async {
    final (a, b, _, _, _) = await chain();
    final deviceA = await selfId(a);
    // Nora cambia de persona (ficha 2) y solo Aritz la aprueba: si quita a
    // Aritz, Nora volvería a esperar aprobación (N7).
    final store = b.container.read(familyStoreProvider);
    final keys = (await b.container.read(deviceKeysStoreProvider).read())!;
    final identity = (await store.readSyncV2())!;
    final anchor = RegistryAnchor(
      deviceId: identity.deviceId,
      signingKey: keys.publicKeys.signing,
    );
    final registry = (await store.readRegistry(anchor: anchor))!;
    final change = await changePerson(
      registry: registry,
      view: await registry.viewFor(
        me: identity.deviceId,
        mySigningKey: keys.publicKeys.signing,
        livePeople: const {'aritz', 'nora', 'leo'},
      ),
      myKeys: keys,
      personId: null,
    );
    await store.saveRegistry(change.registry);
    await syncOf(b).syncNow();
    await syncOf(a).syncNow();
    final review = await a.container.read(deviceReviewProvider.future);
    final item = review.items.singleWhere(
      (i) => i.deviceId == identity.deviceId,
    );
    await a.container
        .read(familyDeviceActionsProvider)
        .approve(item.deviceId, recordDigest: item.recordDigest);
    await syncOf(b).syncNow();
    final deviceB = identity.deviceId;
    final preview = await b.container
        .read(familyDeviceActionsProvider)
        .previewRemoval(deviceA);
    expect(preview.selfWouldWait, isTrue, reason: 'solo Aritz la aprobó');
    await expectLater(
      syncOf(b).removeDevice(deviceA, selfWaitAccepted: false),
      throwsA(isA<DeviceRemovalChangedException>()),
    );
    await expectLater(
      b.container
          .read(familyDeviceActionsProvider)
          .remove(deviceA, selfWaitAccepted: false),
      throwsA(isA<DeviceRemovalChangedException>()),
    );
    expect(deviceB, isNot(deviceA));
    // No cambió nada: Aritz sigue en la lista y no hay huérfanos.
    expect(await activeIds(b), contains(deviceA));
    expect(
      (await b.container.read(deviceReviewProvider.future)).isEmpty,
      isTrue,
    );
    // Aceptado el aviso, se quita.
    await b.container
        .read(familyDeviceActionsProvider)
        .remove(deviceA, selfWaitAccepted: true);
    expect(await activeIds(b), isNot(contains(deviceA)));
  });
  test('si limpiar la memoria de huérfanos falla tras guardar el aval, '
      'el aval sigue siendo un éxito', () async {
    final (a, _, _, deviceB, deviceC) = await chain(
      extra: [rememberedOrphansProvider.overrideWith(_FlakyOrphans.new)],
    );
    addTearDown(() => _FlakyOrphans.failForget = false);
    final actions = a.container.read(familyDeviceActionsProvider);
    final orphans = await actions.remove(deviceB);
    expect(orphans.map((o) => o.deviceId), [deviceC]);
    _FlakyOrphans.failForget = true;
    await actions.approve(deviceC, recordDigest: orphans.single.recordDigest);
    expect(await activeIds(a), contains(deviceC), reason: 'avalado');
  });

  test('una familia emparejada con normalidad no tiene nada que revisar', () async {
    final a = await familyOwner();
    final b = await phone();
    final c = await phone();
    await b.container.read(familyControllerProvider.future);
    await c.container.read(familyControllerProvider.future);
    await connectV2(a, b, personId: 'nora');
    await connectV2(a, c, personId: 'leo');
    for (final p in [a, b, c, a]) {
      await syncOf(p).syncNow();
    }
    for (final p in [a, b, c]) {
      final review = await p.container.read(deviceReviewProvider.future);
      expect(
        review.isEmpty,
        isTrue,
        reason:
            'sin falsos avisos: ${[for (final i in review.items) '${i.deviceId} ${i.personId} ${i.reason}']}',
      );
    }
    expect(await activeIds(a), hasLength(3));
  });

  test('quitar un móvil real: sale de la lista, los demás lo ven y el huérfano '
      'se aprueba uno a uno', () async {
    final a = await familyOwner();
    final b = await phone();
    final c = await phone();
    await b.container.read(familyControllerProvider.future);
    await c.container.read(familyControllerProvider.future);
    // Cadena: Leo solo está unido a Aritz por Nora.
    await connectV2(a, b, personId: 'nora');
    await syncOf(a).syncNow();
    await syncOf(b).syncNow();
    await connectV2(b, c, personId: 'leo');
    await syncOf(c).syncNow();
    await syncOf(b).syncNow();
    await syncOf(a).syncNow();
    await eventually(
      () async => (await activeIds(a)).length == 3,
      reason: 'Aritz ve a los tres',
    );
    final idsBefore = await activeIds(a);
    final deviceB = (await b.container.read(familyDeviceRowsProvider.future))!
        .firstWhere((r) => r.isSelf)
        .deviceId;
    final deviceC = (await c.container.read(familyDeviceRowsProvider.future))!
        .firstWhere((r) => r.isSelf)
        .deviceId;
    expect(idsBefore, containsAll([deviceB, deviceC]));
    expect(
      (await a.container.read(deviceReviewProvider.future)).isEmpty,
      isTrue,
    );

    final actions = a.container.read(familyDeviceActionsProvider);
    // Antes de quitar: Aritz no depende de Nora (su ficha es la primera).
    final preview = await actions.previewRemoval(deviceB);
    expect(preview.selfWouldWait, isFalse);
    expect(preview.orphans.map((o) => o.deviceId), [deviceC]);
    expect(
      await activeIds(a),
      idsBefore,
      reason: 'la vista previa no cambia nada',
    );

    final orphans = await actions.remove(deviceB);
    expect(orphans.map((o) => o.deviceId), [deviceC]);
    expect(orphans.single.reason, DeviceReviewReason.orphan);
    // Nora ya no está; Leo ya no sale en la vista pero la bandeja lo recuerda.
    expect(await activeIds(a), hasLength(1));
    final review = await a.container.read(deviceReviewProvider.future);
    expect(review.items.map((i) => i.deviceId), [deviceC]);
    expect(review.items.single.personId, 'leo');

    // Aprobar solo al huérfano que se enseña.
    await actions.approve(deviceC, recordDigest: orphans.single.recordDigest);
    expect(await activeIds(a), contains(deviceC));
    expect(await activeIds(a), isNot(contains(deviceB)));
    expect(
      (await a.container.read(deviceReviewProvider.future)).isEmpty,
      isTrue,
    );
  });

  test(
    'quitar con la red caída: queda quitado aquí, el huérfano sale en la '
    'bandeja y sigue ahí tras reiniciar; con red se corta el acceso',
    () async {
      var failRevoke = false;
      final base = worker.client();
      final flaky = SyncV2Client(
        base: base.base,
        sendRequest: (method, uri, {body, headers = const {}}) async {
          if (failRevoke && uri.path.endsWith('/revoke')) {
            throw const SyncTransportException(SyncFailure.network, 'sin red');
          }
          return worker.send(method, uri, body: body, headers: headers);
        },
      );
      final a = await ownerWith(flaky);
      final b = await phone();
      final c = await phone();
      await b.container.read(familyControllerProvider.future);
      await c.container.read(familyControllerProvider.future);
      // Cadena: Leo solo está unido a Aritz por Nora.
      await connectV2(a, b, personId: 'nora');
      await syncOf(a).syncNow();
      await syncOf(b).syncNow();
      await connectV2(b, c, personId: 'leo');
      await syncOf(c).syncNow();
      await syncOf(b).syncNow();
      await syncOf(a).syncNow();
      await eventually(
        () async => (await activeIds(a)).length == 3,
        reason: 'Aritz ve a los tres',
      );
      final deviceB = (await b.container.read(familyDeviceRowsProvider.future))!
          .firstWhere((r) => r.isSelf)
          .deviceId;
      final deviceC = (await c.container.read(familyDeviceRowsProvider.future))!
          .firstWhere((r) => r.isSelf)
          .deviceId;

      failRevoke = true;
      final actions = a.container.read(familyDeviceActionsProvider);
      await expectLater(
        actions.remove(deviceB),
        throwsA(
          isA<DeviceRemovalPendingException>().having(
            (e) => e.orphans.map((o) => o.deviceId).toList(),
            'orphans',
            [deviceC],
          ),
        ),
      );
      // Quitado aquí (ya no sale en la lista) y el huérfano, en la bandeja.
      expect(await activeIds(a), isNot(contains(deviceB)));
      var review = await a.container.read(deviceReviewProvider.future);
      expect(review.items.map((i) => i.deviceId), [deviceC]);
      expect((await serverDevices(a))[deviceB], isNot(true));

      // Reiniciar la app: el huérfano sigue (guardado cifrado).
      a.restart();
      a.container.read(syncControllerProvider);
      a.container.read(sharedPreferencesProvider);
      await a.container.read(familyControllerProvider.future);
      review = await a.container.read(deviceReviewProvider.future);
      expect(review.items.map((i) => i.deviceId), [deviceC]);
      expect(review.items.single.personId, 'leo');

      // Con red, el motor corta el acceso pendiente.
      failRevoke = false;
      await syncOf(a).syncNow();
      expect((await serverDevices(a))[deviceB], isTrue);

      // Aprobarlo lo quita de lo guardado: tras otro reinicio ya no vuelve.
      await a.container
          .read(familyDeviceActionsProvider)
          .approve(deviceC, recordDigest: review.items.single.recordDigest);
      a.restart();
      a.container.read(syncControllerProvider);
      a.container.read(sharedPreferencesProvider);
      await a.container.read(familyControllerProvider.future);
      expect(
        (await a.container.read(deviceReviewProvider.future)).isEmpty,
        isTrue,
      );

      // Los «preparados» solo se enseñan si su revocación quedó guardada.
      final memory = a.container.read(rememberedOrphansProvider.notifier);
      await memory.remember([
        const DeviceReviewItem(
          deviceId: 'fantasma',
          reason: DeviceReviewReason.orphan,
          recordDigest: 'z',
          becauseOf: 'nunca-revocado',
        ),
      ]);
      expect(
        (await a.container.read(deviceReviewProvider.future)).isEmpty,
        isTrue,
        reason: 'revocación sin guardar: no se enseña',
      );
      await memory.discard('nunca-revocado');
      expect(
        await a.container.read(familyStoreProvider).readOrphans(),
        isEmpty,
      );

      // Otra generación (mismo listId, otro syncId): memoria y disco se
      // vacían.
      await memory.remember([
        const DeviceReviewItem(
          deviceId: 'x',
          reason: DeviceReviewReason.orphan,
          recordDigest: 'y',
        ),
      ]);
      expect(
        (await a.container.read(deviceReviewProvider.future)).items,
        hasLength(1),
      );
      final current = (await a.container
          .read(familyStoreProvider)
          .readSyncV2())!;
      await a.container
          .read(familyStoreProvider)
          .saveSyncV2(
            SyncIdentityV2(
              listId: current.listId,
              deviceId: current.deviceId,
              syncId: SyncIdentityV2.newSyncId(),
            ),
          );
      a.container.invalidate(localRegistryReadProvider);
      expect(
        (await a.container.read(deviceReviewProvider.future)).isEmpty,
        isTrue,
        reason: 'la memoria sigue a la generación',
      );
      expect(
        await a.container.read(familyStoreProvider).readOrphans(),
        isEmpty,
      );
      // Volver a la identidad anterior no los resucita.
      await a.container.read(familyStoreProvider).saveSyncV2(current);
      a.container.invalidate(localRegistryReadProvider);
      expect(
        (await a.container.read(deviceReviewProvider.future)).isEmpty,
        isTrue,
      );

      // Solo valen para esta lista, y salir de la familia los borra.
      final store = a.container.read(familyStoreProvider);
      await store.saveOrphans([
        {'d': 'x', 'g': 'y'},
      ]);
      expect(await store.readOrphans(), hasLength(1));
      final saved = a.secrets.values['family.orphans']!;
      final identity = (await store.readSyncV2())!;
      a.secrets.values['family.orphans'] = saved.replaceFirst(
        identity.listId,
        'otra-lista',
      );
      expect(await store.readOrphans(), isEmpty, reason: 'otra lista');
      expect(a.secrets.values.containsKey('family.orphans'), isFalse);
      await store.saveOrphans([
        {'d': 'x', 'g': 'y'},
      ]);
      await store.clear();
      expect(a.secrets.values.containsKey('family.orphans'), isFalse);
    },
  );
}

/// Un `RememberedOrphans` al que se le puede romper `forget`.
class _FlakyOrphans extends RememberedOrphans {
  static bool failForget = false;

  @override
  Future<void> forget(String deviceId) async {
    if (failForget) throw StateError('disco lleno');
    return super.forget(deviceId);
  }
}
