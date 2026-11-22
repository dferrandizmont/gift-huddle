import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/features/sync/application/pairing_v2_flow.dart';
import 'package:regalos/features/sync/application/v2_family_lock.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';
import 'package:regalos/features/web_device/application/pending_queue.dart';
import 'package:regalos/features/web_device/application/vault_service.dart';
import 'package:regalos/features/web_device/application/web_pairing_guest.dart';
import 'package:regalos/features/web_device/application/web_sync_engine.dart';
import 'package:regalos/features/web_device/data/guard_client.dart';
import 'package:regalos/features/web_device/data/vault_store.dart';

import '../helpers/fake_worker_v2.dart';
import '../sync/v2_harness.dart';
import 'test_support.dart';

class WebHarness {
  WebHarness({this.commonV2Ready = false, this.webPerson = 'leo'});

  /// The person the phone pairs the web for (1.0.6: its own, by default in
  /// the app; the older tests use Leo).
  final String webPerson;

  /// ADR 0005, B5: whether this web announces the common format 2.
  final bool commonV2Ready;
  final worker = FakeWorkerV2();
  late final client = worker.client();
  late MemoryV2Phone phone;
  late WebPairingGuest guest;
  late PairingV2Host host;
  final store = MemoryVaultStore();
  late final vault = VaultService(
    store: store,
    guard: GuardClient(base: Uri.parse('https://sync.test'), send: worker.send),
    crypto: FastTestCrypto(),
    persist: () async => false,
  );
  late final queue = PendingQueue(vault);
  late final engine = WebSyncEngine(
    transport: client,
    vault: vault,
    queue: queue,
    commonV2Ready: commonV2Ready,
  );
  Future<void> setup({
    bool enroll = true,
    bool approve = true,
    Future<void> Function()? beforeFinish,
    Future<void> Function()? beforeApprove,
    bool cut = false,
  }) async {
    phone = await MemoryV2Phone.create(
      'aritz-phone',
      'aritz',
      1,
      familyKey: await FamilyKey.generate(),
      migrated: true,
    );
    phone
      ..addPerson('aritz', 'Aritz')
      ..addPerson('nora', 'Nora')
      ..addPerson('leo', 'Leo')
      ..addGift('gift', 'nora', 'Bufanda');
    // Con [cut], la familia ya está en el formato 2 del común (B4).
    if (cut) phone.enableCommonV2();
    guest = await WebPairingGuest.create(transport: client);
    await guest.poll(); // No offer yet is not expiration.
    host = await PairingV2Host.start(
      transport: client,
      local: phone,
      lock: V2FamilyLock(),
      web: guest.qr,
      guestPerson: webPerson,
    );
    await guest.poll();
    final answered = (await host.poll())!;
    await guest.poll();
    expect(guest.code, answered.code);
    if (!approve) return;
    guest.confirmCode();
    await beforeApprove?.call();
    await host.confirm(confirmedPersonId: webPerson);
    await beforeFinish?.call();
    await guest.poll();
    expect(guest.personName, {
      'aritz': 'Aritz',
      'nora': 'Nora',
      'leo': 'Leo',
    }[webPerson]);
    if (enroll) {
      await guest.enroll(vault, '123456');
      await engine.sync();
    }
  }

  Future<void> publish({
    FamilyDoc? doc,
    Object? registry,
    List<V2SlotChange> slots = const [],
  }) async {
    if (doc != null) phone.doc = doc;
    final bytes = await seal(
      doc: phone.doc.toJson(),
      listId: kV2List,
      fromNode: phone.identity.deviceId,
      at: '2026-11-13T12:00:00Z',
      key: phone.familyKey,
    );
    final result = await client.putList(
      phone.auth,
      version: worker.versionOf(kV2Sync)!,
      body: V2SnapshotUpload(
        common: bytes,
        registry: Map<String, Object?>.from(
          (registry ?? phone.reg.toJson()) as Map,
        ),
        keyPackages: const [],
        slots: slots,
      ),
    );
    expect(result, isA<V2WriteOk>());
  }

  Future<FamilyDoc> remote() async {
    final s = (await client.getList(phone.auth) as V2GetOk).snapshot;
    final opened = await open(
      s.common,
      key: phone.familyKey,
      expectedListId: kV2List,
    );
    return FamilyDoc.fromJson(opened.doc);
  }

  void close() {
    guest.cancel();
    engine.stop();
    vault.lock();
  }
}
