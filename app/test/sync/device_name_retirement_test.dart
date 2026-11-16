import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/device_names.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/sync/application/family_devices.dart';
import 'package:regalos/features/sync/application/sync_v2_engine.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';

import '../helpers/fake_worker_v2.dart';
import 'v2_harness.dart';

void main() {
  late FakeWorkerV2 worker;
  late SyncV2Client client;
  late MemoryV2Phone aritz;
  late MemoryV2Phone leo;
  late MemoryV2Phone nora;

  setUp(() async {
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
    for (final (phone, name) in [
      (aritz, 'Aritz'),
      (leo, 'Leo'),
      (nora, 'Nora'),
    ]) {
      aritz.doc = withDeviceName(
        aritz.doc,
        aritz.clock,
        phone.identity.deviceId,
        name,
      );
    }
    leo.doc = nora.doc = aritz.doc;
    await vouchAll([aritz, leo, nora]);
    await aritz.engine(client).ensureCreated();
    for (final phone in [leo, nora]) {
      worker.addCredentialForTesting(
        kV2Sync,
        phone.identity.deviceId,
        phone.keys.serviceCredential,
      );
    }
  });

  void expectRetired(FamilyDoc doc, String id) {
    final record = doc.record(Collections.meta, 'device:$id');
    expect(record?.isDeleted, isTrue);
    expect(record?['name'], isNull);
    expect(deviceNameIn(doc, id), isNull);
  }

  // Publish an older client's signed removal without a name tombstone.
  Future<void> publishRemoval(String id) async {
    final change = await revokeDevice(
      registry: nora.reg,
      view: await nora.view(),
      myKeys: nora.keys,
      deviceId: id,
    );
    final snap = (await client.getList(nora.auth) as V2GetOk).snapshot;
    expect(
      await client.putList(
        nora.auth,
        version: snap.version,
        body: V2SnapshotUpload(
          common: snap.common,
          registry: change.registry.toJson(),
          keyPackages: snap.keyPackages,
        ),
      ),
      isA<V2WriteOk>(),
    );
  }

  test(
    'removeDevice erases and publishes the name; late edits cannot revive it',
    () async {
      final old = aritz.doc;
      await removeDevice(
        transport: client,
        local: aritz,
        deviceId: 'leo-phone',
      );
      expectRetired(aritz.doc, 'leo-phone');
      await nora.engine(client).sync();
      expectRetired(nora.doc, 'leo-phone');
      final late = withDeviceName(old, leo.clock, 'leo-phone', 'Móvil de Leo');
      await nora.mergeCommon(late, fromNode: leo.node);
      expectRetired(nora.doc, 'leo-phone');
      expect(deviceNameIn(nora.doc, 'nora-phone'), 'Nora');
    },
  );

  test('leaveFamily erases its local name and keeps the tombstone', () async {
    final old = leo.doc;
    await leaveFamily(transport: client, local: leo);
    expectRetired(leo.doc, 'leo-phone');
    await leo.mergeCommon(old, fromNode: nora.node);
    expectRetired(leo.doc, 'leo-phone');
    // Service departure alone is not a signed family removal.
    await aritz.engine(client).sync();
    expect(deviceNameIn(aritz.doc, 'leo-phone'), 'Leo');
    await removeDevice(transport: client, local: aritz, deviceId: 'leo-phone');
    await nora.engine(client).sync();
    expectRetired(nora.doc, 'leo-phone');
  });

  for (final format2 in [false, true]) {
    test(
      'received verified removal erases an old name (format2: $format2)',
      () async {
        if (format2) {
          for (final phone in [aritz, leo, nora]) {
            phone.commonV2Ready = true;
            await phone.engine(client).sync();
          }
          await aritz.engine(client).sync();
          expect(aritz.state.commonFormatV2, isTrue);
        }
        await publishRemoval('leo-phone');
        await aritz.engine(client).sync();
        expectRetired(aritz.doc, 'leo-phone');
        await nora.engine(client).sync();
        expectRetired(nora.doc, 'leo-phone');
      },
    );
  }

  test(
    'a verified self removal erases the name before stopping sync',
    () async {
      await publishRemoval('aritz-phone');
      await expectLater(
        aritz.engine(client).sync(),
        throwsA(isA<V2RevokedException>()),
      );
      expectRetired(aritz.doc, 'aritz-phone');
    },
  );

  test(
    'a name absent from the registry survives sync and can arrive later',
    () async {
      aritz.doc = withDeviceName(
        aritz.doc,
        aritz.clock,
        'temporarily-missing',
        'Móvil de Nora',
      );
      await aritz.engine(client).sync();
      await nora.engine(client).sync();
      expect(deviceNameIn(nora.doc, 'temporarily-missing'), 'Móvil de Nora');
      expect(
        nora.doc
            .record(Collections.meta, 'device:temporarily-missing')
            ?.isDeleted,
        isFalse,
      );
    },
  );

  test(
    'an ambiguous record does not erase its name without a signed removal',
    () async {
      aritz.reg = await aritz.reg.withRecord(
        await DeviceRecord.create(
          keys: leo.keys,
          listId: kV2List,
          deviceId: 'leo-phone',
          personId: 'nora',
        ),
      );
      final view = await aritz.view();
      expect(view.revoked, contains('leo-phone'));
      expect(view.explicitlyRevoked, isNot(contains('leo-phone')));
      await aritz.engine(client).sync();
      expect(deviceNameIn(aritz.doc, 'leo-phone'), 'Leo');
    },
  );

  test('a removal creates a tombstone even before the name arrives', () async {
    final empty = FamilyDoc.empty(kV2List);
    aritz.doc = empty;
    await retireDeviceNames(aritz, ['leo-phone']);
    final deleted = FamilyDoc.fromJson(aritz.doc.toJson());
    final late = withDeviceName(empty, leo.clock, 'leo-phone', 'Leo');
    expectRetired(deleted.merge(late), 'leo-phone');
    final before = aritz.doc.canonicalJson();
    await retireDeviceNames(aritz, ['leo-phone']);
    expect(aritz.doc.canonicalJson(), before);
  });
}
