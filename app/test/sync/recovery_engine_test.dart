import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/sync/application/recovery_providers.dart';
import 'package:regalos/features/sync/application/sync_controller.dart';
import 'package:regalos/features/sync/data/sync_config.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/family_envelope.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/pairing_v2.dart';
import 'package:regalos/core/sync/protected_doc.dart';
import 'package:regalos/core/sync/recovery.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/family/data/generation_store.dart';
import 'package:regalos/features/family/data/recovery_store.dart';
import 'package:regalos/features/sync/application/common_v2.dart';
import 'package:regalos/features/sync/application/recovery_controller.dart';
import 'package:regalos/features/sync/application/recovery_engine.dart';
import 'package:regalos/features/sync/application/recovery_maintenance.dart';
import 'package:regalos/features/sync/application/stored_sync_v2_local.dart';
import 'package:regalos/features/sync/application/sync_v2_engine.dart';
import 'package:regalos/features/sync/data/recovery_transport.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';
import 'package:regalos/features/sync/data/sync_transport_common.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';

import '../helpers/fake_worker_v2.dart';
import '../helpers/memory_recovery_transport.dart';
import '../helpers/memory_stores.dart';
import '../helpers/fake_sync_server.dart';
import '../helpers/pump_app.dart';
import 'sync_harness.dart' show eventually, kFastTiming;

const sid = 'QUJDREVGR0hJSktMTU5PUA';
const list = 'recovery-list';

/// One fake service: claims replace exactly the same ordinary-sync principal.
class RecoveryWorker implements RecoveryTransport {
  final worker = FakeWorkerV2();
  final recoveries = MemoryRecoveryTransport();
  bool offline = false;
  bool loseUpdate = false;
  int mutations = 0;
  Future<void> Function()? beforeSyncMutation;
  final deviceSids = <String, String>{};
  late final SyncV2Client client = SyncV2Client(
    base: Uri.parse('https://sync.test'),
    sendRequest: syncSend,
    openSocket: worker.socket,
  );

  Future<SyncResponse> syncSend(
    String method,
    Uri uri, {
    Object? body,
    Map<String, String> headers = const {},
  }) async {
    if (offline) {
      throw const SyncTransportException(SyncFailure.network, 'offline');
    }
    if (method != 'GET') {
      await beforeSyncMutation?.call();
      mutations++;
    }
    final result = await worker.send(method, uri, body: body, headers: headers);
    if (method == 'PUT' &&
        headers['If-Match'] == '"0"' &&
        result.status == 201) {
      final id = (body as Map)['deviceId'] as String;
      final syncId = uri.path.split('/')[3];
      deviceSids[id] = syncId;
      await recoveries.register(
        V2Auth(
          syncId: syncId,
          deviceId: id,
          credential: decodeBase64Url(headers['Authorization']!.substring(7)),
        ),
      );
    }
    return result;
  }

  @override
  Future<RecoveryResponse> send(RecoveryRequest request) async {
    if (offline) {
      throw const SyncTransportException(SyncFailure.network, 'offline');
    }
    final r = await recoveries.send(request);
    if (request.path.endsWith('/claim') && r.status == 200) {
      worker.replaceRecoveryCredential(
        deviceSids[(r.body as Map)['deviceId']] ?? sid,
        (r.body as Map)['deviceId'] as String,
        request.body!['newCredentialVerifier'] as String,
      );
    }
    if (loseUpdate && request.method == 'PUT' && r.status == 200) {
      loseUpdate = false;
      throw const SyncTransportException(SyncFailure.network, 'lost response');
    }
    return r;
  }
}

class StoredPhone {
  StoredPhone({MemorySecretStore? secrets, MemoryFileStore? files})
    : secrets = secrets ?? MemorySecretStore(),
      files = files ?? MemoryFileStore() {
    keys = DeviceKeysStore(this.secrets);
    family = FamilyStore(
      secrets: this.secrets,
      files: this.files,
      deviceKeys: keys,
    );
    generations = GenerationStore(secrets: this.secrets, files: this.files);
    recovery = RecoveryStore(secrets: this.secrets, files: this.files);
  }
  final MemorySecretStore secrets;
  final MemoryFileStore files;
  late final DeviceKeysStore keys;
  late final FamilyStore family;
  late final GenerationStore generations;
  late final RecoveryStore recovery;

  Future<StoredSyncV2Local> local() async {
    final stored = (await family.load())!;
    return StoredSyncV2Local(
      store: family,
      deviceKeys: keys,
      identity: (await family.readSyncV2())!,
      keys: (await keys.read())!,
      familyKey: stored.key,
    );
  }

  Future<V2Auth> auth() async {
    final l = await local();
    return V2Auth(
      syncId: l.identity.syncId,
      deviceId: l.identity.deviceId,
      credential: l.keys.serviceCredential,
    );
  }

  EngineRecoveryReader reader(RecoveryWorker w) =>
      EngineRecoveryReader(generations: generations, transport: w.client);
  Future<RecoveryMaintenance> maintenance(RecoveryWorker w) async =>
      RecoveryMaintenance(
        store: recovery,
        family: family,
        exporter: RecoveryExporter(generations, reader(w)),
        transport: w,
        auth: await auth(),
        minimumUpdateInterval: Duration.zero,
      );
  RecoveryController restorer(RecoveryWorker w) => RecoveryController(
    store: recovery,
    generations: generations,
    transport: w,
    reader: reader(w),
  );
  Future<void> sync(RecoveryWorker w) async =>
      SyncV2Engine(transport: w.client, local: await local()).sync();

  Future<void> gift(
    String person,
    String id,
    String title, {
    bool secret = false,
  }) async {
    final l = await local();
    final doc = secret
        ? await family.readScope(person) ?? FamilyDoc.empty(list)
        : await l.common();
    final next = doc.set(
      HlcClock(node: l.node, last: doc.maxStamp),
      Collections.gifts,
      id,
      {'recipientId': person, 'title': title, 'year': 2026},
    );
    if (secret) {
      await family.saveScope(person, next);
    } else {
      await family.saveDoc(next);
    }
  }
}

Future<List<StoredPhone>> family(RecoveryWorker w, {bool solo = false}) async {
  final phones = List.generate(solo ? 1 : 6, (_) => StoredPhone());
  final familyKey = await FamilyKey.generate();
  final deviceKeys = [for (final p in phones) await p.keys.create()];
  final ids = [
    'aritz-phone',
    'leo-phone',
    'nora-phone',
    'extra0',
    'extra1',
    'extra2',
  ];
  final people = ['aritz', 'leo', 'nora', null, null, null];
  final records = <DeviceRecord>[];
  var registry = DeviceRegistry.empty(list);
  for (var i = 0; i < phones.length; i++) {
    final record = await DeviceRecord.create(
      keys: deviceKeys[i],
      listId: list,
      deviceId: ids[i],
      personId: people[i],
    );
    records.add(record);
    registry = await registry.withRecord(record);
  }
  for (var i = 0; i < phones.length; i++) {
    for (var j = 0; j < phones.length; j++) {
      if (i == j) continue;
      registry = await registry.withVouch(
        await Vouch.create(
          keys: deviceKeys[i],
          voucher: records[i],
          record: records[j],
        ),
      );
    }
  }
  final clock = HlcClock(node: ids.first);
  var doc = FamilyDoc.empty(list).set(
    clock,
    Collections.meta,
    kProtocolRecordId,
    {kProtocolVersionField: kSyncProtocolV2},
  );
  for (final person in ['aritz', 'leo', 'nora']) {
    doc = doc.set(clock, Collections.recipients, person, {
      'name': switch (person) {
        'aritz' => 'Aritz',
        'leo' => 'Leo',
        _ => 'Nora',
      },
    });
  }
  for (var i = 0; i < phones.length; i++) {
    final p = phones[i];
    await p.family.saveFamily(
      StoredFamily(
        identity: FamilyIdentity(
          listId: list,
          node: ids[i],
          deviceName: ids[i],
          selfRecipientId: people[i],
          paired: !solo,
        ),
        key: familyKey,
        doc: doc,
      ),
    );
    await p.family.saveSyncV2(
      SyncIdentityV2(listId: list, deviceId: ids[i], syncId: sid),
    );
    await p.family.saveRegistry(registry);
    await p.family.saveSyncV2State(
      const V2SyncState(commonFormatV2: true).toJson(),
    );
    await p.family.saveCommonKeys(CommonKeyState().toJson());
    await p.family.raiseCommonFormatFloor(2);
    await p.generations.adoptCurrent();
  }
  await SyncV2Engine(
    transport: w.client,
    local: await phones.first.local(),
  ).ensureCreated();
  for (var i = 0; i < phones.length; i++) {
    final auth = await phones[i].auth();
    if (i != 0) {
      w.worker.addCredentialForTesting(sid, auth.deviceId, auth.credential);
    }
    await w.recoveries.register(auth);
  }
  for (final p in phones.take(solo ? 1 : 3)) {
    await p.sync(w);
  }
  return phones;
}

Future<void> protect(StoredPhone phone, String person) async {
  final local = await phone.local();
  var doc = await local.common();
  doc = writePublishedPolicy(
    doc,
    HlcClock(node: local.node, last: doc.maxStamp),
    person,
    const PolicyState(hideOwnGifts: true, rev: 1),
  );
  await phone.family.saveDoc(doc);
  final view = await (await local.registry()).viewFor(
    me: local.node,
    mySigningKey: local.keys.publicKeys.signing,
    livePeople: livePeopleOf(doc),
  );
  final share = await createSurpriseKey(
    personId: person,
    keyring: await phone.keys.readKeyring(list),
    view: view,
    keys: local.keys,
  );
  await phone.keys.saveKeyring(list, share.keyring);
  final state = await local.readState();
  await local.saveState(
    state.copyWith(
      keyPackageOutbox: [
        ...state.keyPackageOutbox,
        for (final b in share.bundles) b.toJson(),
      ],
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RecoveryWorker w;
  setUp(() => w = RecoveryWorker());

  Future<FakePhone> appPhone({
    MemorySecretStore? secrets,
    MemoryFileStore? files,
  }) async {
    final phone = FakePhone(
      prefs: await mockPrefs(),
      secrets: secrets,
      files: files,
      syncHost: null,
      extraOverrides: [
        syncHostProvider.overrideWithValue('sync.test'),
        syncTransportProvider.overrideWithValue(FakeSyncServer().connect()),
        syncV2TransportProvider.overrideWithValue(w.client),
        recoveryTransportProvider.overrideWithValue(w),
        syncTimingProvider.overrideWithValue(kFastTiming),
      ],
    );
    phone.container.read(syncControllerProvider);
    return phone;
  }

  test('solo v1 activation owns lock once, restores automatically and syncs after restart', () async {
    final original = await appPhone();
    addTearDown(original.dispose);
    final c = original.container;
    await c.read(familyControllerProvider.future);
    await c
        .read(familyControllerProvider.notifier)
        .createFamily(deviceName: 'Aritz');
    final display = await c
        .read(recoveryApplicationProvider.notifier)
        .createCode()
        .timeout(const Duration(seconds: 20));
    expect(display.words, hasLength(24));
    expect(
      await c.read(recoveryApplicationProvider.notifier).takeCreatedCode(),
      isNull,
    );
    final originalIdentity = (await c.read(familyStoreProvider).readSyncV2())!;
    await eventually(() => w.worker.watchers(originalIdentity.syncId) == 1);

    final empty = await appPhone();
    addTearDown(empty.dispose);
    await empty.container
        .read(recoveryApplicationProvider.notifier)
        .restoreWords(display.words.join(' '));
    await eventually(
      () async =>
          (await empty.container.read(familyStoreProvider).readSyncV2())
              ?.syncId ==
          originalIdentity.syncId,
    );
    expect(
      await empty.container.read(familyStoreProvider).remoteSyncEnabled(),
      isTrue,
    );
    await eventually(
      () => c.read(familyStoreProvider).isTransferred(),
      reason: 'old phone transferred by WebSocket',
    );
    empty.restart();
    empty.container.read(syncControllerProvider);
    await empty.container.read(familyControllerProvider.future);
    final beforeEdit = V2SyncState.fromJson(
      await empty.container.read(familyStoreProvider).readSyncV2State(),
    ).version!;
    await empty.container
        .read(familyControllerProvider.notifier)
        .upsertRecipient(
          const Recipient(
            id: 'leo',
            name: 'Leo',
            colorIndex: 0,
            archived: false,
          ),
        );
    await eventually(() async {
      final stored = await empty.container
          .read(familyStoreProvider)
          .readSyncV2State();
      return V2SyncState.fromJson(stored).version! > beforeEdit;
    });
    final local = await empty.container.read(familyStoreProvider).load();
    final keys = (await empty.container.read(deviceKeysStoreProvider).read())!;
    final got = await w.client.getList(
      V2Auth(
        syncId: originalIdentity.syncId,
        deviceId: originalIdentity.deviceId,
        credential: keys.serviceCredential,
      ),
    ) as V2GetOk;
    final reader = StoredPhone();
    final payload = await RecoveryExporter(
      empty.container.read(generationStoreProvider),
      EngineRecoveryReader(
        generations: reader.generations,
        transport: w.client,
      ),
    ).capture(originalIdentity.syncId);
    final downloaded = await reader.reader(w).download(payload, const {}, null);
    expect(
      downloaded.installation!.doc.record(Collections.recipients, 'leo'),
      isNotNull,
    );
    expect(local!.identity.paired, isFalse);
    expect(got.snapshot.common, isNotEmpty);
  });

  test(
    'solo activation intent resumes automatically after offline restart',
    () async {
      final phone = await appPhone();
      addTearDown(phone.dispose);
      await phone.container.read(familyControllerProvider.future);
      await phone.container
          .read(familyControllerProvider.notifier)
          .createFamily(deviceName: 'Aritz');
      w.offline = true;
      await expectLater(
        phone.container.read(recoveryApplicationProvider.notifier).createCode(),
        throwsA(isA<RecoveryApplicationException>()),
      );
      final identity = (await phone.container
          .read(familyStoreProvider)
          .readSyncV2())!;
      expect(
        await phone.container
            .read(familyStoreProvider)
            .recoveryActivationPending(),
        isTrue,
      );
      phone.restart();
      phone.container.read(syncControllerProvider);
      w.offline = false;
      await eventually(
        () async {
          final material = await phone.container
              .read(recoveryStoreProvider)
              .readMaterial(identity.syncId);
          return material != null;
        },
        timeout: const Duration(seconds: 20),
        reason: 'automatic solo activation',
      );
      expect(
        (await phone.container.read(familyStoreProvider).readSyncV2())!.syncId,
        identity.syncId,
      );
      expect(
        await phone.container
            .read(familyStoreProvider)
            .recoveryActivationPending(),
        isFalse,
      );
      final display = await phone.container
          .read(recoveryApplicationProvider.notifier)
          .takeCreatedCode();
      expect(display!.words, hasLength(24));
      expect(
        await phone.container
            .read(recoveryApplicationProvider.notifier)
            .takeCreatedCode(),
        isNull,
      );
    },
  );

  for (final throughApplication in [false, true]) {
    test(
      'words alone recover real common and all authorized scopes after offline epochs (${throughApplication ? 'application' : 'engine'})',
      () async {
        final phones = await family(w);
        final owner = phones[0], leo = phones[1], nora = phones[2];
        await protect(owner, 'nora');
        await owner.gift(
          'nora',
          'initial-secret',
          'First secret',
          secret: true,
        );
        await owner.sync(w);
        await leo.sync(w);
        final code = RecoveryCode.generate();
        await (await owner.maintenance(w)).create(code);
        expect(
          (await (await owner.maintenance(w)).status()).readiness,
          RecoveryReadiness.confirmationPending,
        );

        // A scope that did not exist in the capsule, with an old live slot while
        // its writer and the code holder are disconnected through three epochs.
        await nora.sync(w);
        await protect(nora, 'leo');
        await nora.gift('leo', 'later-scope', 'Later secret', secret: true);
        await nora.sync(w);
        for (var i = 0; i < 3; i++) {
          final local = await leo.local();
          final registry = await local.registry();
          final view = await registry.viewFor(
            me: local.node,
            mySigningKey: local.keys.publicKeys.signing,
            livePeople: livePeopleOf(await local.common()),
          );
          await leo.family.saveRegistry(
            await registry.withRevocation(
              await Revocation.create(
                keys: local.keys,
                by: registry.recordByDigest(view.self.recordDigest)!,
                deviceId: 'extra$i',
              ),
            ),
          );
          await leo.gift('aritz', 'remote$i', 'Remote $i');
          await leo.gift('nora', 'rotated$i', 'Rotated $i', secret: true);
          await leo.sync(w);
        }
        final wordlist = RecoveryWordlist.parse(
          File('assets/recovery/bip39-english.txt').readAsStringSync(),
        );
        final words = code.toWords(wordlist).join(' ');
        owner.secrets.values.clear();
        owner.files.files
            .clear(); // Simulate uninstall: no local state survives.
        final application = throughApplication ? await appPhone() : null;
        if (application != null) addTearDown(application.dispose);
        final empty = StoredPhone(
          secrets: application?.secrets,
          files: application?.files,
        );
        final mutations = w.mutations;
        w.beforeSyncMutation = () async {
          expect(
            (await empty.recovery.readRestore())?.phase,
            RecoveryPhase.active,
            reason: 'ordinary writes require a fully validated installation',
          );
        };
        if (application == null) {
          await empty
              .restorer(w)
              .start(RecoveryCode.fromWords(words, wordlist));
        } else {
          await application.container
              .read(recoveryApplicationProvider.notifier)
              .restoreWords(words);
        }
        final restored = (await empty.recovery.readRestore())!;
        expect(restored.phase, RecoveryPhase.active);
        if (application == null) {
          expect(
            w.mutations,
            mutations,
            reason: 'validation/download only GET; claim is separate',
          );
        }
        final stored = (await empty.family.load())!;
        expect(
          stored.doc.record(Collections.gifts, 'remote2')?['title'],
          'Remote 2',
        );
        expect(
          (await empty.family.readScope('leo'))!
              .record(Collections.gifts, 'later-scope')?['title'],
          'Later secret',
        );
        expect(
          (await empty.family.readScope('nora'))!
              .record(Collections.gifts, 'rotated2')?['title'],
          'Rotated 2',
        );
        expect(await empty.family.readScope('aritz'), isNull);
        expect(
          (await empty.keys.readKeyring(list)).people,
          isNot(contains('aritz')),
        );
        expect(await empty.family.remoteSyncEnabled(), isTrue);
        if (application == null) {
          await empty.sync(w);
        } else {
          await eventually(
            () => w.worker.watchers(sid) == 1,
            reason: 'restoration starts sync and WebSocket automatically',
          );
        }
      },
    );
  }

  test(
    'restored application clock advances past its durable HLC after restart',
    () async {
      final owner = (await family(w, solo: true)).single;
      final floor = Hlc(
        millis: DateTime.now().millisecondsSinceEpoch + 100000,
        counter: 5,
        node: 'aritz-phone',
      );
      await owner.family.raiseRecoveryRevisionFloors({}, hlc: floor);
      final code = RecoveryCode.generate();
      await (await owner.maintenance(w)).create(code);
      final application = await appPhone();
      addTearDown(application.dispose);
      await application.container
          .read(recoveryApplicationProvider.notifier)
          .restoreQr(code.toQrText());
      application.restart();
      application.container.read(syncControllerProvider);
      await application.container.read(familyControllerProvider.future);
      await application.container
          .read(familyControllerProvider.notifier)
          .upsertRecipient(
            const Recipient(
              id: 'leo',
              name: 'Leo',
              colorIndex: 1,
              archived: false,
            ),
          );
      final stored = (await application.container
          .read(familyStoreProvider)
          .load())!;
      expect(stored.doc.maxStamp, greaterThan(floor));
      expect(stored.doc.maxStamp!.node, floor.node);
    },
  );

  test(
    'solo restoration survives restart and publishes a later edit',
    () async {
      final owner = (await family(w, solo: true)).single;
      final code = RecoveryCode.generate();
      await (await owner.maintenance(w)).create(code);
      final empty = StoredPhone();
      final versionBeforeClaim = w.worker.versionOf(sid)!;
      expect((await empty.restorer(w).start(code)).phase, RecoveryPhase.active);
      expect(w.worker.versionOf(sid), versionBeforeClaim + 1);
      expect((await empty.family.load())!.identity.paired, isFalse);
      final restarted = StoredPhone(secrets: empty.secrets, files: empty.files);
      expect(await restarted.family.remoteSyncEnabled(), isTrue);
      await restarted.gift('leo', 'after-restart', 'Later edit');
      await restarted.sync(w);
      final independent = StoredPhone();
      final payload = await RecoveryExporter(
        restarted.generations,
        restarted.reader(w),
      ).capture(sid);
      final got = await independent.reader(w).download(payload, const {}, null);
      expect(
        got.installation!.doc.record(
          Collections.gifts,
          'after-restart',
        )?['title'],
        'Later edit',
      );
    },
  );

  test('revoked recovery rejected before installing any family', () async {
    final owner = (await family(w, solo: true)).single;
    final code = RecoveryCode.generate();
    await (await owner.maintenance(w)).create(code);
    w.recoveries.revoke(sid, 'aritz-phone');
    final empty = StoredPhone();
    final journal = await empty.restorer(w).start(code);
    expect(journal.phase, RecoveryPhase.needsAttention);
    expect(await empty.family.load(), isNull);
    expect(w.worker.hasList(sid), isTrue);
  });

  for (final restoreStale in [false, true]) {
    test(
      'remote deletion retires the secret scope (restore stale: $restoreStale)',
      () async {
        final owner = (await family(w, solo: true)).single;
        await protect(owner, 'nora');
        await owner.gift('nora', 'secret', 'Patinete', secret: true);
        await owner.sync(w);
        final local = await owner.local();
        final before = await local.common();
        final slot = (await owner.family.readSlots()).slotOf(
          'nora',
          local.node,
        )!;
        expect(w.worker.slotVersions(sid), contains('nora/${local.node}'));
        expect(await owner.family.readRecoveryScopes(), contains('nora'));
        final code = RecoveryCode.generate();
        if (restoreStale) {
          await (await owner.maintenance(w)).create(code);
          final scope = (await owner.family.readScope('nora'))!;
          await owner.family.saveScope(
            'nora',
            scope.set(
              HlcClock(node: local.node, last: scope.maxStamp),
              ScopeCollections.wishPlans,
              'local-plan',
              {
                'recipientId': 'nora',
                'sourceWishId': 'wish',
                'claimantPersonId': 'aritz',
                'title': 'Patinete',
                'status': 'idea',
              },
            ),
          );
        }

        final view = await (await local.registry()).viewFor(
          me: local.node,
          mySigningKey: local.keys.publicKeys.signing,
          livePeople: livePeopleOf(before),
        );
        final commonKeys = (await local.readCommonKeys())!;
        final remote = before.delete(
          HlcClock(node: local.node, last: before.maxStamp),
          Collections.recipients,
          'nora',
        );
        final auth = await owner.auth();
        final snap = (await w.client.getList(auth) as V2GetOk).snapshot;
        expect(
          await w.client.putList(
            auth,
            version: snap.version,
            body: V2SnapshotUpload(
              common: await sealFamilyEnvelope(
                doc: remote,
                candidate: commonKeys.keyring
                    .entry(commonKeys.lastKid!)!
                    .candidate,
                writer: view.self,
                revision: commonKeys.revision + 1,
                signer: local.keys,
              ),
              registry: Map<String, Object?>.from(snap.registry! as Map),
              keyPackages: snap.keyPackages,
              slots: [
                V2SlotChange(
                  personId: 'nora',
                  deviceId: local.node,
                  data: null,
                ),
              ],
            ),
          ),
          isA<V2WriteOk>(),
        );
        expect(
          w.worker.slotVersions(sid),
          isNot(contains('nora/${local.node}')),
        );
        if (restoreStale) {
          expect(
            (await owner.family.readScope('nora'))!
                .record(ScopeCollections.wishPlans, 'local-plan')?['title'],
            'Patinete',
          );
          expect(
            (await owner.restorer(w).start(code)).phase,
            RecoveryPhase.active,
          );
          expect(
            (await owner.family.load())!.doc
                .record(Collections.recipients, 'nora')!
                .isDeleted,
            isTrue,
          );
        } else {
          await owner.sync(w);
        }

        expect(await owner.family.readRecoveryScopes(), isEmpty);
        expect(
          (await owner.family.readSlots()).people,
          isNot(contains('nora')),
        );
        expect(
          w.worker.slotVersions(sid),
          isNot(contains('nora/${local.node}')),
        );
        expect(
          (await owner.family.readRecoveryRevisionFloors())
              .slots['nora/${local.node}'],
          slot.header.revision,
        );
        if (!restoreStale) {
          final maintenance = await owner.maintenance(w);
          await maintenance.create(code);
          expect(
            (await maintenance.status()).readiness,
            RecoveryReadiness.confirmationPending,
          );
        }
      },
    );
  }

  test(
    'missing packages remain incomplete, preserve existing family, no PUT',
    () async {
      final phones = await family(w);
      final owner = phones[0], leo = phones[1];
      final code = RecoveryCode.generate();
      await (await owner.maintenance(w)).create(code);
      await protect(leo, 'nora');
      await leo.gift('nora', 'never-open', 'Secret', secret: true);
      await leo.sync(w);
      w.worker.tamper = (method, uri, response) {
        if (method != 'GET' || uri.path != '/v2/lists/$sid') return response;
        final body = response.json();
        body['keyPackages'] = <Object?>[];
        return SyncResponse(
          response.status,
          response.headers,
          Uint8List.fromList(utf8.encode(jsonEncode(body))),
        );
      };
      final previous = (await owner.family.load())!.doc.canonicalJson();
      final mutations = w.mutations;
      final journal = await owner.restorer(w).start(code);
      expect(journal.phase, RecoveryPhase.needsAttention);
      expect((await owner.family.load())!.doc.canonicalJson(), previous);
      expect(w.mutations, mutations);
      w.worker.tamper = null;
      expect(
        (await owner.restorer(w).retryIncomplete()).phase,
        RecoveryPhase.active,
      );
      expect(
        (await owner.family.readScope('nora'))!
            .record(Collections.gifts, 'never-open')?['title'],
        'Secret',
      );
    },
  );

  test('writer revision floors are allocated before publish, retained after restart', () async {
    final phones = await family(w);
    final owner = phones[0];
    await protect(owner, 'nora');
    await owner.sync(w);
    final floor = DateTime.now().millisecondsSinceEpoch + 100000;
    await owner.family.raiseRecoveryRevisionFloors({
      'nora/aritz-phone': floor,
    }, hlc: Hlc(millis: floor, counter: 5, node: 'aritz-phone'));
    await owner.gift('leo', 'trigger', 'Publish');
    final restart = StoredPhone(secrets: owner.secrets, files: owner.files);
    await restart.sync(w);
    expect(
      (await restart.family.readSlots())
          .slotOf('nora', 'aritz-phone')!
          .header
          .revision,
      greaterThan(floor),
    );
    expect(
      (await restart.family.readRecoveryRevisionFloors())
          .slots['nora/aritz-phone'],
      greaterThan(floor),
    );
  });

  test(
    'pending update and exact ciphertext survive restart and lost response',
    () async {
      final owner = (await family(w, solo: true)).single;
      final code = RecoveryCode.generate();
      await (await owner.maintenance(w)).create(code);
      await owner.family.saveIdentity(
        (await owner.family.load())!.identity.copyWith(deviceName: 'Nora'),
      );
      await owner.sync(w);
      w.offline = true;
      await expectLater(
        (await owner.maintenance(w)).maintain(),
        throwsA(isA<SyncTransportException>()),
      );
      expect(await owner.recovery.readMaintenance(sid), isNotNull);
      final restarted = StoredPhone(secrets: owner.secrets, files: owner.files);
      expect(
        (await (await restarted.maintenance(w)).status()).readiness,
        RecoveryReadiness.updatePending,
      );
      w.offline = false;
      w.loseUpdate = true;
      await expectLater(
        (await restarted.maintenance(w)).maintain(),
        throwsA(isA<SyncTransportException>()),
      );
      final exact = await restarted.recovery.readMaintenance(sid);
      expect((exact!['intent'] as Map)['phase'], 'send');
      await (await restarted.maintenance(w)).maintain();
      expect(
        (await (await restarted.maintenance(w)).status()).readiness,
        RecoveryReadiness.confirmationPending,
      );
      expect(await restarted.recovery.readMaintenance(sid), isNull);
    },
  );

  test('capsule keeps both outboxes and pending signed revocations through restore', () async {
    final phones = await family(w);
    final owner = phones[0];
    await protect(owner, 'nora');
    await owner.sync(w);
    final local = await owner.local();
    final state = await local.readState();
    final view = await (await local.registry()).viewFor(
      me: local.node,
      mySigningKey: local.keys.publicKeys.signing,
      livePeople: livePeopleOf(await local.common()),
    );
    final revocation = await Revocation.create(
      keys: local.keys,
      by: (await local.registry()).recordByDigest(view.self.recordDigest)!,
      deviceId: 'extra0',
    );
    final operation = (await (await local.registry()).withRevocation(
      revocation,
    )).toJson();
    final snapshot =
        (await w.client.getList(await owner.auth()) as V2GetOk).snapshot;
    final v3 = snapshot.keyPackages.where((p) => p['v'] == 3).toList();
    final v4 = snapshot.keyPackages.where((p) => p['v'] == 4).take(1).toList();
    await local.saveState(
      state.copyWith(
        pendingRevocations: {'extra0'},
        pendingUnbackedRevocations: {'extra1'},
        revocationOperations: {'extra0': operation},
        keyPackageOutbox: v3,
      ),
    );
    await local.saveCommonKeys(
      (await local.readCommonKeys())!.copyWith(outbox: v4),
    );
    final code = RecoveryCode.generate();
    await (await owner.maintenance(w)).create(code);
    final empty = StoredPhone();
    expect((await empty.restorer(w).start(code)).phase, RecoveryPhase.active);
    final installed = await (await empty.local()).readState();
    expect(installed.pendingRevocations, {'extra0'});
    expect(installed.pendingUnbackedRevocations, {'extra1'});
    expect(installed.revocationOperations['extra0'], operation);
    expect(installed.keyPackageOutbox, containsAll(v3));
    expect(
      (await (await empty.local()).readCommonKeys())!.outbox,
      containsAll(v4),
    );
  });

  test(
    'rotation verifies candidate before commit; retired words cannot restore',
    () async {
      final owner = (await family(w, solo: true)).single;
      final old = RecoveryCode.generate(), next = RecoveryCode.generate();
      await (await owner.maintenance(w)).create(old);
      await (await owner.maintenance(w)).rotate(next);
      expect(
        (await (await owner.maintenance(w)).status()).readiness,
        RecoveryReadiness.confirmationPending,
      );
      final rejected = StoredPhone();
      expect(
        (await rejected.restorer(w).start(old)).phase,
        RecoveryPhase.needsAttention,
      );
      final accepted = StoredPhone();
      expect(
        (await accepted.restorer(w).start(next)).phase,
        RecoveryPhase.active,
      );
    },
  );

  test(
    'approved person change retires old code before allowing a fresh code',
    () async {
      final phones = await family(w);
      final owner = phones[0], nora = phones[2];
      final old = RecoveryCode.generate();
      await (await owner.maintenance(w)).create(old);
      final local = await owner.local();
      final approving = await nora.local();
      var registry = await local.registry();
      final updated = await DeviceRecord.create(
        keys: local.keys,
        listId: list,
        deviceId: local.node,
        personId: 'leo',
        seq: 2,
      );
      registry = await registry.withRecord(updated);
      registry = await registry.withVouch(
        await Vouch.create(
          keys: approving.keys,
          voucher: registry.records.firstWhere(
            (r) => r.deviceId == approving.node,
          ),
          record: updated,
        ),
      );
      await owner.family.prepareSelfPersonChange(
        personId: 'leo',
        registry: registry,
        orphans: [],
      );
      await owner.family.finishSelfPersonChange();
      await (await owner.maintenance(w)).maintain();
      await owner.sync(w);
      expect(
        (await (await owner.maintenance(w)).status()).readiness,
        RecoveryReadiness.absent,
      );
      final rejected = StoredPhone();
      expect(
        (await rejected.restorer(w).start(old)).phase,
        RecoveryPhase.needsAttention,
      );
      final next = RecoveryCode.generate();
      await (await owner.maintenance(w)).create(next);
      final empty = StoredPhone();
      expect((await empty.restorer(w).start(next)).phase, RecoveryPhase.active);
      expect((await empty.family.load())!.identity.selfRecipientId, 'leo');
    },
  );

  test('exporter inspects real migration, person, protection and local-resource blockers', () async {
    final owner = (await family(w, solo: true)).single;
    final exporter = RecoveryExporter(owner.generations, owner.reader(w));
    Future<void> blocked() =>
        expectLater(exporter.capture(sid), throwsA(isA<RecoveryIncomplete>()));
    await owner.family.savePendingV2({'pending': true});
    await blocked();
    await owner.family.savePendingV2(null);
    await owner.family.saveLegacyV1({'pending': true});
    await blocked();
    await owner.family.saveLegacyV1(null);
    await owner.secrets.write('family.selfPersonChange', '{"pending":true}');
    await blocked();
    await owner.secrets.delete('family.selfPersonChange');
    await owner.family.saveProtectionOperation({'pending': true});
    await blocked();
    await owner.files.delete('family.protection');
    final scope = FamilyDoc.empty(list).set(
      HlcClock(node: 'aritz-phone'),
      Collections.gifts,
      'local-only',
      {'recipientId': 'nora', 'title': 'Pending'},
    );
    await owner.family.saveOverflow(
      'nora',
      scope.collections[Collections.gifts]!.values.toList(),
    );
    await blocked();
    await owner.family.replaceOverflow('nora', []);
    await owner.family.saveScope('nora', scope);
    await blocked();
  });

  test(
    'application drains its old socket before restoring over its own family',
    () async {
      final phone = await appPhone();
      addTearDown(phone.dispose);
      await phone.container.read(familyControllerProvider.future);
      await phone.container
          .read(familyControllerProvider.notifier)
          .createFamily(deviceName: 'Aritz');
      final display = await phone.container
          .read(recoveryApplicationProvider.notifier)
          .createCode();
      final identity = (await phone.container
          .read(familyStoreProvider)
          .readSyncV2())!;
      await eventually(() => w.worker.watchers(identity.syncId) == 1);
      await phone.container
          .read(recoveryApplicationProvider.notifier)
          .restoreQr(display.qrText);
      expect(
        await phone.container.read(familyStoreProvider).isTransferred(),
        isFalse,
      );
      expect(
        (await phone.container.read(recoveryStoreProvider).readRestore())!
            .phase,
        RecoveryPhase.active,
      );
    },
  );

  test(
    'revoked writers left in the manifest do not block authorized recovery',
    () async {
      final phones = await family(w);
      final owner = phones[0], leo = phones[1];
      await protect(owner, 'nora');
      await owner.gift('nora', 'shared-secret', 'Secret', secret: true);
      await owner.sync(w);
      await leo.sync(w);
      final local = await owner.local();
      final registry = await local.registry();
      await owner.family.saveRegistry(
        await registry.withRevocation(
          await Revocation.create(
            keys: local.keys,
            by: registry.records.firstWhere((r) => r.deviceId == local.node),
            deviceId: 'leo-phone',
          ),
        ),
      );
      await owner.sync(w);
      final code = RecoveryCode.generate();
      await (await owner.maintenance(w)).create(code);
      final empty = StoredPhone();
      expect((await empty.restorer(w).start(code)).phase, RecoveryPhase.active);
      expect(
        (await empty.family.readScope('nora'))!
            .record(Collections.gifts, 'shared-secret'),
        isNotNull,
      );
    },
  );

  test('restoring over the same generation preserves its archive and future maintenance', () async {
    final owner = (await family(w, solo: true)).single;
    final code = RecoveryCode.generate();
    await (await owner.maintenance(w)).create(code);
    expect((await owner.restorer(w).start(code)).phase, RecoveryPhase.active);
    final restarted = StoredPhone(secrets: owner.secrets, files: owner.files);
    expect(await restarted.generations.generationIds(), hasLength(2));
    await restarted.gift('leo', 'after-local-restore', 'After');
    await restarted.sync(w);
    await (await restarted.maintenance(w)).maintain();
    expect(
      (await (await restarted.maintenance(w)).status()).readiness,
      RecoveryReadiness.prepared,
    );
  });

  test(
    'exhausted common writer revision never persists a wrapped counter',
    () async {
      final owner = (await family(w, solo: true)).single;
      final local = await owner.local();
      final keys = (await local.readCommonKeys())!;
      const maxRevision = 0x1fffffffffffff;
      await local.saveCommonKeys(keys.copyWith(revision: maxRevision));
      await owner.gift('leo', 'counter', 'Counter');
      await expectLater(owner.sync(w), throwsA(isA<CommonStateException>()));
      expect((await local.readCommonKeys())!.revision, maxRevision);
    },
  );

  test('credential replaced makes old real engine transferred without retry mutation', () async {
    final owner = (await family(w, solo: true)).single;
    final code = RecoveryCode.generate();
    await (await owner.maintenance(w)).create(code);
    final empty = StoredPhone();
    await empty.restorer(w).start(code);
    await expectLater(owner.sync(w), throwsA(isA<V2TransferredException>()));
    expect(await owner.family.isTransferred(), isTrue);
    final calls = w.mutations;
    await expectLater(owner.sync(w), throwsStateError);
    expect(w.mutations, calls);
  });
}
