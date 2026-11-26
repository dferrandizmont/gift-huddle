import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/device_keys.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/recovery.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';
import 'package:regalos/features/family/data/recovery_store.dart';
import 'package:regalos/features/family/data/generation_store.dart';
import 'package:regalos/features/settings/application/erase_all.dart';
import 'package:regalos/features/sync/application/recovery_providers.dart';
import 'package:regalos/features/sync/application/pairing_v2_controller.dart';
import 'package:regalos/features/sync/application/sync_controller.dart';
import 'package:regalos/features/sync/application/sync_v2_engine.dart';
import 'package:regalos/features/sync/application/migration_v2.dart';
import 'package:regalos/features/sync/application/v2_health.dart';
import 'package:regalos/features/sync/domain/sync_status.dart';
import 'package:regalos/features/sync/data/sync_endpoint.dart';
import 'package:regalos/features/sync/data/recovery_transport.dart';
import 'package:regalos/features/sync/data/sync_config.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';
import 'package:regalos/features/sync/data/sync_transport_common.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';

import '../helpers/fake_sync_server.dart';
import '../helpers/host_person.dart';
import '../helpers/memory_stores.dart';
import '../helpers/pump_app.dart';
import 'recovery_engine_test.dart' show RecoveryWorker;
import 'sync_harness.dart' show eventually, kFastTiming;

class AuditWorker extends RecoveryWorker {
  int puts = 0;
  String? failPut;
  Future<RecoveryResponse?> Function(RecoveryRequest)? intercept;
  Future<void> Function(String method, Uri uri)? beforeSyncRequest;
  Future<SyncResponse?> Function(String method, Uri uri)? interceptSync;

  @override
  Future<SyncResponse> syncSend(
    String method,
    Uri uri, {
    Object? body,
    Map<String, String> headers = const {},
  }) async {
    await beforeSyncRequest?.call(method, uri);
    final intercepted = await interceptSync?.call(method, uri);
    if (intercepted != null) return intercepted;
    return super.syncSend(method, uri, body: body, headers: headers);
  }

  @override
  Future<RecoveryResponse> send(RecoveryRequest request) async {
    final intercepted = await intercept?.call(request);
    if (intercepted != null) return intercepted;
    if (request.method == 'PUT') {
      puts++;
      if (failPut != null) {
        return RecoveryResponse(409, body: {'error': failPut});
      }
    }
    return super.send(request);
  }
}

class _RetiredV1Transport extends BaseSyncTransport {
  _RetiredV1Transport() : super(SyncEndpoint.parse('https://sync.test')!);
  int requests = 0;

  @override
  Future<SyncResponse> send(
    String method,
    Uri uri, {
    SyncCredentials? auth,
    Object? body,
    Map<String, String> headers = const {},
  }) async {
    requests++;
    return SyncResponse(
      410,
      const {},
      Uint8List.fromList(utf8.encode('{"error":"gone"}')),
    );
  }

  @override
  Stream<SyncEvent> watch(SyncCredentials auth, {int? since}) =>
      const Stream.empty();

  @override
  void close() {}
}

class _FailingRecoveryFiles extends MemoryFileStore {
  bool failRead = false;

  @override
  Future<Uint8List?> read(String name) {
    if (failRead && name == recoveryJournalFile) {
      throw const FileSystemException('journal read failed');
    }
    return super.read(name);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AuditWorker w;
  late Directory temp;
  setUp(() {
    w = AuditWorker();
    temp = Directory.systemTemp.createTempSync('recovery-audit');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Future<FakePhone> phone({
    MemoryFileStore? files,
    SyncTransport? v1,
    bool Function()? recoveryAvailable,
  }) async {
    final p = FakePhone(
      temp: temp,
      files: files,
      prefs: await mockPrefs(),
      syncHost: null,
      extraOverrides: [
        syncHostProvider.overrideWithValue('sync.test'),
        syncTransportProvider.overrideWithValue(
          v1 ?? FakeSyncServer().connect(),
        ),
        syncV2TransportProvider.overrideWithValue(w.client),
        recoveryTransportProvider.overrideWith(
          (ref) => recoveryAvailable?.call() == false ? null : w,
        ),
        syncTimingProvider.overrideWithValue(kFastTiming),
      ],
    );
    addTearDown(p.dispose);
    p.container.read(syncControllerProvider);
    await p.container.read(familyControllerProvider.future);
    return p;
  }

  Future<void> create(FakePhone p) => p.container
      .read(familyControllerProvider.notifier)
      .createFamily(deviceName: 'Aritz');

  Future<void> edit(FakePhone p, int i) => p.container
      .read(familyControllerProvider.notifier)
      .upsertRecipient(
        Recipient(id: 'p$i', name: 'Leo', colorIndex: 0, archived: false),
      );

  test('creates a recovery code on cold start with a tombstone', () async {
    final p = await phone();
    await create(p);
    await edit(p, 1);
    final store = p.container.read(familyStoreProvider);
    final saved = (await store.load())!;
    await store.saveDoc(
      saved.doc.delete(
        HlcClock(node: saved.identity.node, last: saved.doc.maxStamp),
        Collections.recipients,
        'p1',
      ),
    );
    p.restart(temp: temp);

    final display = await p.container
        .read(recoveryApplicationProvider.notifier)
        .createCode()
        .timeout(const Duration(seconds: 10));

    expect(display.words, hasLength(24));
    final family = await p.container.read(familyControllerProvider.future);
    expect(family.doc.record(Collections.recipients, 'p1')!.isDeleted, isTrue);
  });

  test(
    'word confirmation is durable, local and bound to the displayed code',
    () async {
      final p = await phone();
      await create(p);
      final app = p.container.read(recoveryApplicationProvider.notifier);
      final display = await app.createCode();
      expect(
        p.container.read(recoveryStatusProvider).readiness,
        RecoveryReadiness.confirmationPending,
      );
      expect(await app.hasCodeDisplay(), isFalse);
      await app.refresh();
      expect(
        p.container.read(recoveryStatusProvider).readiness,
        RecoveryReadiness.confirmationPending,
      );
      await p.container
          .read(syncControllerProvider.notifier)
          .suspendForRecovery();
      w.offline = true;
      await app.confirmCreatedCode(display);
      await app.refresh();
      expect(
        p.container.read(recoveryStatusProvider).readiness,
        RecoveryReadiness.prepared,
      );
      w.offline = false;
      final next = await app.rotateCode();
      await expectLater(
        app.confirmCreatedCode(display),
        throwsA(isA<RecoveryApplicationException>()),
      );
      expect(
        p.container.read(recoveryStatusProvider).readiness,
        RecoveryReadiness.confirmationPending,
      );
      await app.confirmCreatedCode(next);
      expect(
        p.container.read(recoveryStatusProvider).readiness,
        RecoveryReadiness.prepared,
      );
    },
  );

  test('M1 retire offline then cancel does not delete on sync', () async {
    final p = await phone();
    await create(p);
    final app = p.container.read(recoveryApplicationProvider.notifier);
    await app.createCode();
    final store = p.container.read(familyStoreProvider);
    final sid = (await store.readSyncV2())!.syncId;
    final sync = p.container.read(syncControllerProvider.notifier);
    w.offline = true;
    await expectLater(
      app.retireCode(),
      throwsA(isA<RecoveryApplicationException>()),
    );
    await sync.suspendForRecovery();
    w.offline = false;
    await app.cancelMaintenance();
    expect(await store.recoveryRemovalPending(), isFalse);
    sync.finishRecoveryClaim();
    await sync.syncNow();
    expect(await store.recoveryRemovalPending(), isFalse);
    expect(w.worker.hasList(sid), isTrue);
    expect((await store.readSyncV2())!.syncId, sid);
    expect(
      p.container.read(recoveryStatusProvider).readiness,
      RecoveryReadiness.confirmationPending,
    );
  });

  for (final action in ['dismiss', 'sync']) {
    test('M1 stale closed retirement is cleared by $action', () async {
      final p = await phone();
      await create(p);
      final app = p.container.read(recoveryApplicationProvider.notifier);
      await app.createCode();
      final sync = p.container.read(syncControllerProvider.notifier);
      await sync.suspendForRecovery();
      final store = p.container.read(familyStoreProvider);
      final sid = (await store.readSyncV2())!.syncId;
      await store.setRecoveryRemovalPending(true);
      if (action == 'dismiss') {
        await app.dismissFailure();
        expect(await store.recoveryRemovalPending(), isFalse);
      }
      sync.finishRecoveryClaim();
      await sync.syncNow();
      expect(await store.recoveryRemovalPending(), isFalse);
      expect(w.worker.hasList(sid), isTrue);
    });
  }

  test(
    'M2 missing maintenance transport clears removal and syncs normally',
    () async {
      var available = true;
      final p = await phone(recoveryAvailable: () => available);
      await create(p);
      await p.container.read(recoveryApplicationProvider.notifier).createCode();
      final sync = p.container.read(syncControllerProvider.notifier);
      await sync.suspendForRecovery();
      final store = p.container.read(familyStoreProvider);
      await store.setRecoveryRemovalPending(true);
      available = false;
      p.container.invalidate(recoveryTransportProvider);
      sync.finishRecoveryClaim();
      await sync.syncNow();
      expect(await store.recoveryRemovalPending(), isFalse);
      expect(p.container.read(syncControllerProvider).phase, SyncPhase.synced);
    },
  );

  test(
    'M2 permanent retirement failure keeps list and allows normal sync',
    () async {
      final p = await phone();
      await create(p);
      final app = p.container.read(recoveryApplicationProvider.notifier);
      await app.createCode();
      final store = p.container.read(familyStoreProvider);
      final sid = (await store.readSyncV2())!.syncId;
      final sync = p.container.read(syncControllerProvider.notifier);
      w.offline = true;
      await expectLater(
        app.retireCode(),
        throwsA(isA<RecoveryApplicationException>()),
      );
      await sync.suspendForRecovery();
      w.offline = false;
      w.intercept = (r) async => r.method == 'DELETE'
          ? RecoveryResponse(403, body: {'error': 'mobile_required'})
          : null;
      sync.finishRecoveryClaim();
      await sync.syncNow();
      expect(await store.recoveryRemovalPending(), isFalse);
      expect(w.worker.hasList(sid), isTrue);
      expect(p.container.read(syncControllerProvider).phase, SyncPhase.synced);
    },
  );

  test('M2 retirement after DELETE supersedes pending renewal with local generation', () async {
    final p = await phone();
    await create(p);
    final app = p.container.read(recoveryApplicationProvider.notifier);
    await app.createCode();
    final store = p.container.read(familyStoreProvider);
    final old = (await store.readSyncV2())!.syncId;
    final generations = p.container.read(generationStoreProvider);
    await generations.prepare(operationId: encodeBase64Url(List.filled(16, 9)));
    final doc = (await store.load())!.doc.toJson();
    await app.retireCode();
    expect(w.worker.hasList(old), isFalse);
    expect((await store.readSyncV2())!.syncId, isNot(old));
    expect(await store.remoteSyncEnabled(), isFalse);
    expect(await store.recoveryRemovalPending(), isFalse);
    expect((await store.load())!.doc.toJson(), doc);
    expect(await generations.journal.read(), isNull);
    await p.container.read(syncControllerProvider.notifier).syncNow();
    expect(
      p.container.read(syncControllerProvider).phase,
      SyncPhase.waitingForPeer,
    );
    expect((await app.createCode()).words, hasLength(24));
  });

  for (final status in [401, 403, 404, 429, 0]) {
    test(
      'B1 checkpoint acknowledgement $status never blocks normal sync',
      () async {
        final p = await phone();
        await create(p);
        await p.container
            .read(recoveryApplicationProvider.notifier)
            .createCode();
        final sync = p.container.read(syncControllerProvider.notifier);
        await sync.suspendForRecovery();
        final store = p.container.read(familyStoreProvider);
        final sid = (await store.readSyncV2())!.syncId;
        final ack = {
          'syncId': sid,
          'inviteId': encodeBase64Url(List.filled(16, 8)),
        };
        await store.savePendingInviteAcknowledgement(ack);
        var normalGets = 0;
        w.interceptSync = (method, uri) async {
          if (uri.path.endsWith('/checkpoint')) {
            if (status == 0) {
              throw const SyncTransportException(
                SyncFailure.network,
                'offline',
              );
            }
            return SyncResponse(status, const {}, Uint8List(0));
          }
          if (method == 'GET' && uri.path == '/v2/lists/$sid') normalGets++;
          return null;
        };
        sync.finishRecoveryClaim();
        await sync.syncNow();
        expect(normalGets, greaterThan(0));
        expect(
          p.container.read(syncControllerProvider).phase,
          SyncPhase.synced,
        );
        expect(
          await store.pendingInviteAcknowledgement(),
          status == 0 || status == 429 ? ack : isNull,
        );
        w.interceptSync = null;
        await sync.syncNow();
        expect(await store.pendingInviteAcknowledgement(), isNull);
      },
    );
  }

  test('B5 retired v1 copy is forgotten and never requested again', () async {
    final v1 = _RetiredV1Transport();
    final p = await phone(v1: v1);
    await create(p);
    final store = p.container.read(familyStoreProvider);
    await p.container.read(recoveryApplicationProvider.notifier).createCode();
    final sync = p.container.read(syncControllerProvider.notifier);
    await sync.suspendForRecovery();
    await store.saveLegacyV1(
      LegacyV1(
        listId: 'old',
        key: await FamilyKey.generate(),
        since: DateTime.utc(2026),
        nodes: const {},
      ).toJson(),
    );
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    sync.finishRecoveryClaim();
    await sync.syncNow();
    await eventually(
      () async => await store.readLegacyV1() == null,
      reason: 'retired v1 forgotten',
    );
    expect(v1.requests, 1);
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await sync.syncNow();
    expect(v1.requests, 1);
  });

  test(
    'privacy: enabling after stopping the only phone does not upload again',
    () async {
      final p = await phone();
      await create(p);
      await p.container.read(recoveryApplicationProvider.notifier).createCode();
      final sync = p.container.read(syncControllerProvider.notifier);
      await sync.stopSyncing();
      await sync.setEnabled(true);
      final store = p.container.read(familyStoreProvider);
      expect(await store.remoteSyncEnabled(), isFalse);
      expect(w.worker.hasList((await store.readSyncV2())!.syncId), isFalse);
      expect(
        p.container.read(syncControllerProvider).phase,
        SyncPhase.waitingForPeer,
      );
      await p.container.read(recoveryApplicationProvider.notifier).createCode();
      expect(w.worker.hasList((await store.readSyncV2())!.syncId), isTrue);
      expect(await store.remoteSyncEnabled(), isTrue);
    },
  );

  for (final role in ['device', 'web']) {
    test(
      'privacy: code removal keeps the list while another $role has access',
      () async {
        final p = await phone();
        await create(p);
        final app = p.container.read(recoveryApplicationProvider.notifier);
        await app.createCode();
        final store = p.container.read(familyStoreProvider);
        final sid = (await store.readSyncV2())!.syncId;
        w.worker.addCredentialForTesting(
          sid,
          'nora',
          Uint8List(32),
          role: role,
        );
        expect(await app.removalStopsRemoteSync(), isFalse);
        await app.retireCode();
        expect(w.worker.hasList(sid), isTrue);
        expect((await store.readSyncV2())!.syncId, sid);
        expect(await store.remoteSyncEnabled(), isFalse);
        expect(await store.recoveryRemovalPending(), isFalse);
        // The other credential leaves after code removal. The next round must
        // retire the old copy and select a local generation without uploading.
        await w.client.revoke(
          V2Auth(syncId: sid, deviceId: 'nora', credential: Uint8List(32)),
          'nora',
        );
        await p.container.read(syncControllerProvider.notifier).syncNow();
        expect(w.worker.hasList(sid), isFalse);
        expect((await store.readSyncV2())!.syncId, isNot(sid));
        expect(await store.remoteSyncEnabled(), isFalse);
        expect(
          p.container.read(syncControllerProvider).phase,
          SyncPhase.waitingForPeer,
        );
        final requests = <String>[];
        w.beforeSyncRequest = (method, uri) async => requests.add(method);
        await p.container.read(syncControllerProvider.notifier).syncNow();
        expect(requests, isEmpty);
      },
    );
  }

  test('privacy: create code, pair a phone, remove code, then remove the phone stays local', () async {
    final a = await phone();
    final b = await phone();
    await create(a);
    final recovery = a.container.read(recoveryApplicationProvider.notifier);
    await recovery.createCode();
    final store = a.container.read(familyStoreProvider);
    final sid = (await store.readSyncV2())!.syncId;
    // 1.0.6: los dos móviles, de quien solo regala: nadie protege a nadie, así
    // que al quitar el otro no quedan slots suyos que conservar.
    await hostWithPerson(a, id: kGuestGiver);
    final host = a.container.read(pairingV2HostProvider.notifier);
    final guest = b.container.read(pairingV2GuestProvider.notifier);
    await host.start(guestPerson: kGuestGiver);
    final link = a.container.read(pairingV2HostProvider).link!;
    await guest.begin(link.substring(link.indexOf('#') + 1));
    await guest.choosePerson(null);
    await eventually(
      () =>
          a.container.read(pairingV2HostProvider).phase ==
              PairingV2HostPhase.compare &&
          b.container.read(pairingV2GuestProvider).phase ==
              PairingV2GuestPhase.compare,
      reason: 'both phones compare the pairing code',
    );
    guest.confirmCode();
    await host.confirm();
    await eventually(
      () =>
          b.container.read(pairingV2GuestProvider).phase ==
          PairingV2GuestPhase.done,
      reason: 'second phone installed',
    );
    final sync = a.container.read(syncControllerProvider.notifier);
    await sync.syncNow();
    await recovery.retireCode();
    expect(w.worker.hasList(sid), isTrue);
    expect(await store.remoteSyncEnabled(), isFalse);
    await edit(a, 7);
    await sync.syncNow();
    await b.container.read(syncControllerProvider.notifier).syncNow();
    expect(
      b.container
          .read(familyControllerProvider)
          .value!
          .fullView
          .recipients
          .any((r) => r.id == 'p7'),
      isTrue,
    );
    final peer = (await b.container.read(familyStoreProvider).readSyncV2())!;
    await sync.removeDevice(peer.deviceId);
    expect(w.worker.hasList(sid), isFalse);
    expect((await store.readSyncV2())!.syncId, isNot(sid));
    final requests = <String>[];
    w.beforeSyncRequest = (method, uri) async => requests.add(method);
    await sync.syncNow();
    expect(requests, isEmpty);
    expect(
      a.container.read(syncControllerProvider).phase,
      SyncPhase.waitingForPeer,
    );
  });

  for (final knownAccess in [
    'alone',
    'phone',
    'web',
    'departed',
    'pending',
    'pendingUnbacked',
  ]) {
    test(
      'privacy: offline removal preview is read-only with $knownAccess',
      () async {
        final p = await phone();
        await create(p);
        final app = p.container.read(recoveryApplicationProvider.notifier);
        await app.createCode();
        await p.container
            .read(syncControllerProvider.notifier)
            .suspendForRecovery();
        final store = p.container.read(familyStoreProvider);
        final identity = (await store.readSyncV2())!;
        if (knownAccess == 'phone' || knownAccess == 'departed') {
          final keys = (await p.container
              .read(deviceKeysStoreProvider)
              .read())!;
          final peerKeys = await DeviceKeys.generate();
          var registry = (await store.readRegistry())!;
          final owner = registry.records.singleWhere(
            (r) => r.deviceId == identity.deviceId,
          );
          final peer = await DeviceRecord.create(
            keys: peerKeys,
            listId: identity.listId,
            deviceId: 'nora-phone',
            personId: null,
          );
          registry = await registry.withRecord(peer);
          registry = await registry.withVouch(
            await Vouch.create(keys: keys, voucher: owner, record: peer),
          );
          await store.saveRegistry(registry);
        }
        final cached = V2SyncState.fromJson(await store.readSyncV2State());
        await store.saveSyncV2State(
          cached
              .copyWith(
                pendingRevocations: knownAccess == 'pending'
                    ? {'nora-phone'}
                    : {},
                pendingUnbackedRevocations: knownAccess == 'pendingUnbacked'
                    ? {'nora-web'}
                    : {},
                health: V2Health(
                  unbackedCredentials: knownAccess == 'web' ? ['nora-web'] : [],
                  departedDevices: knownAccess == 'departed'
                      ? ['nora-phone']
                      : [],
                ),
              )
              .toJson(),
        );
        final status = p.container.read(recoveryStatusProvider);
        final secretsBefore = jsonEncode(p.secrets.values);
        final filesBefore = jsonEncode(p.files.files);
        final changes = <RecoveryStatus>[];
        final sub = p.container.listen(recoveryApplicationProvider, (_, next) {
          changes.add(next);
        });
        addTearDown(sub.close);
        w.offline = true;
        expect(
          await app.removalStopsRemoteSync(),
          knownAccess == 'alone' || knownAccess == 'departed',
        );
        expect(changes, isEmpty);
        expect(p.container.read(recoveryStatusProvider), same(status));
        // Compare without ever printing stored keys or recovery material.
        expect(jsonEncode(p.secrets.values) == secretsBefore, isTrue);
        expect(jsonEncode(p.files.files) == filesBefore, isTrue);
      },
    );
  }

  for (final responseStatus in [403, 404]) {
    test(
      'privacy: removal preview $responseStatus leaves recovery prepared',
      () async {
        final p = await phone();
        await create(p);
        final app = p.container.read(recoveryApplicationProvider.notifier);
        await app.createCode();
        await p.container
            .read(syncControllerProvider.notifier)
            .suspendForRecovery();
        final store = p.container.read(familyStoreProvider);
        final cached = V2SyncState.fromJson(await store.readSyncV2State());
        await store.saveSyncV2State(
          cached
              .copyWith(health: V2Health(unbackedCredentials: ['nora-web']))
              .toJson(),
        );
        final status = p.container.read(recoveryStatusProvider);
        w.interceptSync = (_, _) async => SyncResponse(
          responseStatus,
          const {},
          Uint8List.fromList(utf8.encode('{"error":"revoked"}')),
        );
        expect(await app.removalStopsRemoteSync(), responseStatus == 404);
        expect(p.container.read(recoveryStatusProvider), same(status));
        expect(status.readiness, RecoveryReadiness.confirmationPending);
      },
    );
  }

  test('privacy: interrupted list deletion resumes retirement without uploading again', () async {
    final p = await phone();
    await create(p);
    final app = p.container.read(recoveryApplicationProvider.notifier);
    await app.createCode();
    final store = p.container.read(familyStoreProvider);
    final sid = (await store.readSyncV2())!.syncId;
    var failDelete = true;
    w.beforeSyncRequest = (method, uri) async {
      if (method == 'DELETE' && uri.path == '/v2/lists/$sid' && failDelete) {
        throw const SyncTransportException(SyncFailure.network, 'offline');
      }
    };
    expect(await app.removalStopsRemoteSync(), isTrue);
    await expectLater(
      app.retireCode(),
      throwsA(isA<RecoveryApplicationException>()),
    );
    expect(await store.recoveryRemovalPending(), isTrue);
    expect(w.worker.hasList(sid), isTrue);
    failDelete = false;
    await p.container.read(syncControllerProvider.notifier).syncNow();
    await eventually(
      () async => !await store.recoveryRemovalPending(),
      reason: 'retirement resumed',
    );
    expect(w.worker.hasList(sid), isFalse);
    expect(await store.remoteSyncEnabled(), isFalse);
  });

  test('privacy: removing the only code retires the list and stays local after enabling', () async {
    final p = await phone();
    await create(p);
    final app = p.container.read(recoveryApplicationProvider.notifier);
    await app.createCode();
    final store = p.container.read(familyStoreProvider);
    await edit(p, 1);
    final localDoc = (await store.load())!.doc;
    final scope = FamilyDoc.empty(localDoc.listId).set(
      HlcClock(node: (await store.load())!.identity.node),
      Collections.gifts,
      'gift1',
      {'title': 'Bufanda', 'recipientId': 'p1', 'status': 'idea', 'year': 2026},
    );
    await store.saveScope('p1', scope);
    final old = (await store.readSyncV2())!.syncId;
    expect(w.worker.hasList(old), isTrue);
    await app.retireCode();
    expect(w.worker.hasList(old), isFalse);
    expect(await store.remoteSyncEnabled(), isFalse);
    expect((await store.load())!.doc.toJson(), localDoc.toJson());
    expect((await store.readScope('p1'))!.toJson(), scope.toJson());
    final sync = p.container.read(syncControllerProvider.notifier);
    await sync.setEnabled(true);
    final fresh = (await store.readSyncV2())!.syncId;
    expect(w.worker.hasList(fresh), isFalse);
    expect(
      p.container.read(syncControllerProvider).phase,
      SyncPhase.waitingForPeer,
    );
  });

  test(
    'A3 terminal refusal releases intent and a new create delivers words',
    () async {
      final p = await phone();
      await create(p);
      w.failPut = 'recovery_limit';
      final app = p.container.read(recoveryApplicationProvider.notifier);
      await expectLater(
        app.createCode(),
        throwsA(isA<RecoveryApplicationException>()),
      );
      expect(await app.takeCreatedCode(), isNull);
      expect(p.container.read(recoveryStatusProvider).cause, 'recovery_limit');
      w.failPut = null;
      final display = await app.createCode();
      expect(display.words, hasLength(24));
      expect(await app.takeCreatedCode(), isNull);
    },
  );

  for (final action in ['create', 'createWith', 'joinV1', 'installV2']) {
    test(
      'ALTA-1 pending locating restore rejects $action with typed error',
      () async {
        final p = await phone();
        final family = p.container.read(familyControllerProvider.notifier);
        final store = p.container.read(recoveryStoreProvider);
        await store.saveRestore(
          RecoveryJournal(
            operationId: encodeBase64Url(List.filled(16, 7)),
            phase: RecoveryPhase.locating,
            data: {'entropy': encodeBase64Url(RecoveryCode.generate().entropy)},
          ),
        );
        Future<void> run() async {
          switch (action) {
            case 'create':
              await family.createFamily(deviceName: 'Aritz');
            case 'createWith':
              await family.createFamilyWith(deviceName: 'Aritz', region: 'ES');
            case 'joinV1':
              await family.joinFamily(
                payload: PairingPayload(
                  listId: 'other',
                  key: await FamilyKey.generate(),
                  deviceName: 'Nora',
                ),
              );
            case 'installV2':
              await family.installV2(
                listId: 'other',
                node: 'other-phone',
                key: await FamilyKey.generate(),
                doc: FamilyDoc.empty('other'),
              );
          }
        }

        await expectLater(
          run(),
          throwsA(
            isA<RecoveryApplicationException>().having(
              (e) => e.code,
              'code',
              'restore_pending',
            ),
          ),
        );
        expect(await p.container.read(familyStoreProvider).load(), isNull);
      },
    );
  }

  test(
    'BAJA-2 pending restore fails guest begin without escaping its future',
    () async {
      final p = await phone();
      await p.container
          .read(recoveryStoreProvider)
          .saveRestore(
            RecoveryJournal(
              operationId: encodeBase64Url(List.filled(16, 7)),
              phase: RecoveryPhase.locating,
              data: {
                'entropy': encodeBase64Url(RecoveryCode.generate().entropy),
              },
            ),
          );
      await p.container.read(pairingV2GuestProvider.notifier).begin('invite');
      final guest = p.container.read(pairingV2GuestProvider);
      expect(guest.phase, PairingV2GuestPhase.failed);
      expect(guest.failureCode, 'restore_pending');
      expect(await p.container.read(familyStoreProvider).load(), isNull);
      expect(p.secrets.values['device.keys'], isNull);
    },
  );

  test(
    'N-3 journal read failure preserves freshly detected transferred gate',
    () async {
      final files = _FailingRecoveryFiles();
      final p = await phone(files: files);
      await create(p);
      final app = p.container.read(recoveryApplicationProvider.notifier);
      await app.createCode();
      await app.refresh();
      expect(
        p.container.read(recoveryStatusProvider).installationTransferred,
        isFalse,
      );
      await p.container
          .read(syncControllerProvider.notifier)
          .suspendForRecovery();
      await p.container.read(familyStoreProvider).markTransferred();
      files.failRead = true;
      await app.refresh();
      final status = p.container.read(recoveryStatusProvider);
      expect(status.cause, 'local_or_unsupported_state');
      expect(status.installationTransferred, isTrue);
      files.failRead = false;
      await app.refresh();
      expect(
        p.container.read(recoveryStatusProvider).readiness,
        RecoveryReadiness.transferred,
      );
    },
  );

  for (final fails in [false, true]) {
    test(
      'M-A real restore phases preserve transferred gate (failure=$fails)',
      () async {
        final p = await phone();
        await create(p);
        final app = p.container.read(recoveryApplicationProvider.notifier);
        final display = await app.createCode();
        await p.container
            .read(syncControllerProvider.notifier)
            .suspendForRecovery();
        final sid =
            (await p.container.read(familyStoreProvider).readSyncV2())!.syncId;
        await p.container.read(recoveryStoreProvider).markTransferred(sid);
        await app.refresh();
        expect(
          p.container.read(recoveryStatusProvider).readiness,
          RecoveryReadiness.transferred,
        );
        expect(
          p.container.read(recoveryStatusProvider).installationTransferred,
          isTrue,
        );
        final phases = <RecoveryPhase>[];
        final lostGate = <RecoveryPhase>[];
        final sub = p.container.listen(recoveryStatusProvider, (_, next) {
          if (next.phase != null && next.phase != RecoveryPhase.active) {
            phases.add(next.phase!);
            if (!next.installationTransferred) lostGate.add(next.phase!);
          }
        });
        addTearDown(sub.close);
        if (fails) {
          w.intercept = (r) async => r.path.endsWith('/claim')
              ? throw const SyncTransportException(
                  SyncFailure.network,
                  'offline',
                )
              : null;
          await expectLater(
            app.restoreQr(display.qrText),
            throwsA(isA<RecoveryApplicationException>()),
          );
          await p.container
              .read(syncControllerProvider.notifier)
              .suspendForRecovery();
          await app.refresh();
          expect(
            p.container.read(recoveryStatusProvider).installationTransferred,
            isTrue,
          );
          expect(p.container.read(recoveryStatusProvider).claimSent, isTrue);
        } else {
          await app.restoreQr(display.qrText);
          expect(
            (await p.container.read(recoveryStoreProvider).readRestore())!
                .phase,
            RecoveryPhase.active,
          );
          expect(
            p.container.read(recoveryStatusProvider).installationTransferred,
            isFalse,
          );
        }
        expect(lostGate, isEmpty);
        expect(phases, contains(RecoveryPhase.verified));
      },
    );
  }

  test(
    'M-B terminal failure can be dismissed without a pending operation',
    () async {
      final p = await phone();
      await create(p);
      final app = p.container.read(recoveryApplicationProvider.notifier);
      w.failPut = 'recovery_limit';
      await expectLater(
        app.createCode(),
        throwsA(isA<RecoveryApplicationException>()),
      );
      expect(
        p.container.read(recoveryStatusProvider).readiness,
        RecoveryReadiness.needsAttention,
      );
      expect(
        p.container.read(recoveryStatusProvider).canDismissFailure,
        isTrue,
      );
      await app.dismissFailure();
      expect(
        p.container.read(recoveryStatusProvider).readiness,
        RecoveryReadiness.absent,
      );
      expect(
        p.container.read(recoveryStatusProvider).canDismissFailure,
        isFalse,
      );
      final sid =
          (await p.container.read(familyStoreProvider).readSyncV2())!.syncId;
      expect(
        await p.container.read(recoveryStoreProvider).readFailure(sid),
        isNull,
      );
    },
  );

  test(
    'M-B dismissing a closed rotation failure preserves unconfirmed words',
    () async {
      final p = await phone();
      await create(p);
      final app = p.container.read(recoveryApplicationProvider.notifier);
      await app.createCode();
      await p.container
          .read(syncControllerProvider.notifier)
          .suspendForRecovery();
      final sid =
          (await p.container.read(familyStoreProvider).readSyncV2())!.syncId;
      final store = p.container.read(recoveryStoreProvider);
      final old = await store.readMaterial(sid);
      w.intercept = (r) async => r.path.endsWith('/rotation')
          ? RecoveryResponse(409, body: {'error': 'recovery_limit'})
          : null;
      await expectLater(
        app.rotateCode(),
        throwsA(isA<RecoveryApplicationException>()),
      );
      expect(
        p.container.read(recoveryStatusProvider).canDismissFailure,
        isTrue,
      );
      await app.dismissFailure();
      expect(
        p.container.read(recoveryStatusProvider).readiness,
        RecoveryReadiness.confirmationPending,
      );
      expect(await store.readMaterial(sid), old);
      expect(await app.hasCodeDisplay(), isFalse);
    },
  );

  test('M-B cancelling ambiguous creation cleans remote code and permits another create', () async {
    final p = await phone();
    await create(p);
    final app = p.container.read(recoveryApplicationProvider.notifier);
    w.intercept = (r) async =>
        r.method == 'GET' && r.path.startsWith('/v2/recoveries/')
        ? RecoveryResponse(503)
        : null;
    await expectLater(
      app.createCode(),
      throwsA(isA<RecoveryApplicationException>()),
    );
    await p.container
        .read(syncControllerProvider.notifier)
        .suspendForRecovery();
    final sid =
        (await p.container.read(familyStoreProvider).readSyncV2())!.syncId;
    final store = p.container.read(recoveryStoreProvider);
    final pending = await store.readMaintenance(sid);
    expect(pending, isNotNull);
    await expectLater(
      app.dismissFailure(),
      throwsA(isA<RecoveryApplicationException>()),
    );
    expect(await store.readMaintenance(sid), pending);
    w.intercept = null;
    await app.cancelMaintenance();
    expect(
      p.container.read(recoveryStatusProvider).readiness,
      RecoveryReadiness.absent,
    );
    expect(await store.readFailure(sid), isNull);
    expect(await app.hasCodeDisplay(), isFalse);
    expect((await app.createCode()).words, hasLength(24));
  });

  test('BAJA-1 provider cancellation preserves first display of committed rotation', () async {
    final p = await phone();
    await create(p);
    final app = p.container.read(recoveryApplicationProvider.notifier);
    final oldDisplay = await app.createCode();
    await p.container
        .read(syncControllerProvider.notifier)
        .suspendForRecovery();
    w.intercept = (r) async {
      if (!r.path.endsWith('/commit')) return null;
      expect((await w.recoveries.send(r)).status, 200);
      throw const SyncTransportException(SyncFailure.network, 'lost response');
    };
    await expectLater(
      app.rotateCode(),
      throwsA(isA<RecoveryApplicationException>()),
    );
    await app.cancelMaintenance();
    expect(
      p.container.read(recoveryStatusProvider).readiness,
      RecoveryReadiness.confirmationPending,
    );
    expect(await app.hasCodeDisplay(), isTrue);
    expect((await app.takeCreatedCode())!.qrText, isNot(oldDisplay.qrText));
    expect(await app.hasCodeDisplay(), isFalse);
  });

  test('MEDIA-2 display probe does not consume pending words', () async {
    final p = await phone();
    await create(p);
    final app = p.container.read(recoveryApplicationProvider.notifier);
    w.intercept = (r) async =>
        r.method == 'GET' && r.path.startsWith('/v2/recoveries/')
        ? RecoveryResponse(503)
        : null;
    await expectLater(
      app.createCode(),
      throwsA(isA<RecoveryApplicationException>()),
    );
    expect(await app.hasCodeDisplay(), isFalse);
    w.intercept = null;
    await app.retry();
    expect(await app.hasCodeDisplay(), isTrue);
    expect(await app.hasCodeDisplay(), isTrue);
    expect((await app.takeCreatedCode())?.words, hasLength(24));
    expect(await app.hasCodeDisplay(), isFalse);
  });

  test('ALTA-1 abandoning locating clears pending status without v2', () async {
    final p = await phone();
    final app = p.container.read(recoveryApplicationProvider.notifier);
    await p.container
        .read(recoveryStoreProvider)
        .saveRestore(
          RecoveryJournal(
            operationId: encodeBase64Url(List.filled(16, 7)),
            phase: RecoveryPhase.locating,
            data: {'entropy': encodeBase64Url(RecoveryCode.generate().entropy)},
          ),
        );
    await app.refresh();
    expect(p.container.read(recoveryStatusProvider).hasPendingRestore, isTrue);
    await app.abandon();
    final status = p.container.read(recoveryStatusProvider);
    expect(status.hasPendingRestore, isFalse);
    expect(status.readiness, RecoveryReadiness.absent);
    await create(p);
    expect(await p.container.read(familyStoreProvider).load(), isNotNull);
  });

  test('MEDIA-3 status preserves claimSent even in needsAttention', () async {
    final p = await phone();
    final app = p.container.read(recoveryApplicationProvider.notifier);
    final store = p.container.read(recoveryStoreProvider);
    for (final sent in [false, true]) {
      await store.saveRestore(
        RecoveryJournal(
          operationId: encodeBase64Url(List.filled(16, 7)),
          phase: RecoveryPhase.needsAttention,
          data: {'reason': 'different_family', 'claimSent': sent},
        ),
      );
      await app.refresh();
      final status = p.container.read(recoveryStatusProvider);
      expect(status.claimSent, sent);
      expect(status.hasPendingRestore, isTrue);
    }
  });

  test(
    'MEDIA-3 lost claim response exposes claimSent before refresh',
    () async {
      final owner = await phone();
      await create(owner);
      final display = await owner.container
          .read(recoveryApplicationProvider.notifier)
          .createCode();
      final p = await phone();
      w.intercept = (r) async => r.path.endsWith('/claim')
          ? throw const SyncTransportException(SyncFailure.network, 'offline')
          : null;
      final app = p.container.read(recoveryApplicationProvider.notifier);
      await expectLater(
        app.restoreQr(display.qrText),
        throwsA(isA<RecoveryApplicationException>()),
      );
      final status = p.container.read(recoveryStatusProvider);
      expect(status.claimSent, isTrue);
      expect(status.hasPendingRestore, isTrue);
      expect(
        (await p.container.read(recoveryStoreProvider).readRestore())!
            .claimSent,
        isTrue,
      );
      await p.container
          .read(syncControllerProvider.notifier)
          .suspendForRecovery();
      await owner.container
          .read(syncControllerProvider.notifier)
          .suspendForRecovery();
    },
  );

  test(
    'MEDIA-4 provider cancels maintenance without consuming installed code',
    () async {
      final p = await phone();
      await create(p);
      final app = p.container.read(recoveryApplicationProvider.notifier);
      await app.createCode();
      final identity = (await p.container
          .read(familyStoreProvider)
          .readSyncV2())!;
      final store = p.container.read(recoveryStoreProvider);
      final material = (await store.readMaterial(identity.syncId))!;
      await store.prepareMaintenance(
        identity.syncId,
        RecoveryMaintenanceKind.update,
        {'old': material, 'entropy': material['entropy'], 'phase': 'capture'},
      );
      await app.cancelMaintenance();
      expect(await store.readMaintenance(identity.syncId), isNull);
      expect(await store.readMaterial(identity.syncId), material);
    },
  );

  test('M1 ordinary edits do not upload another capsule', () async {
    final p = await phone();
    await create(p);
    await p.container.read(recoveryApplicationProvider.notifier).createCode();
    for (var i = 0; i < 4; i++) {
      final store = p.container.read(familyStoreProvider);
      final before = V2SyncState.fromJson(await store.readSyncV2State())
          .version!;
      await edit(p, i);
      await eventually(
        () async =>
            V2SyncState.fromJson(await store.readSyncV2State()).version! >
            before,
      );
    }
    expect(w.puts, 1);
  });

  test('A2 erase adopted family and pending restore, restart, create and restore again', () async {
    final p = await phone();
    await create(p);
    final display = await p.container
        .read(recoveryApplicationProvider.notifier)
        .createCode();
    await p.container
        .read(recoveryApplicationProvider.notifier)
        .restoreQr(RecoveryCode.generate().toQrText());
    await p.container.read(eraseAllProvider).eraseLocal();
    expect(
      p.files.files.keys.where(
        (k) =>
            k.startsWith('family.') ||
            k.startsWith('generation.') ||
            k.startsWith('recovery.read.'),
      ),
      isEmpty,
    );
    expect(p.secrets.values, isEmpty);
    p.restart(temp: temp);
    expect(
      (await p.container.read(familyControllerProvider.future)).hasFamily,
      isFalse,
    );
    await create(p);
    await p.container
        .read(recoveryApplicationProvider.notifier)
        .restoreQr(display.qrText, replaceExisting: true);
    expect(
      (await p.container.read(recoveryStoreProvider).readRestore())!.phase,
      RecoveryPhase.active,
    );
  });

  test(
    'A1 unknown code can be abandoned and existing family stays editable',
    () async {
      final p = await phone();
      await create(p);
      await p.container.read(recoveryApplicationProvider.notifier).createCode();
      final app = p.container.read(recoveryApplicationProvider.notifier);
      await app.restoreQr(RecoveryCode.generate().toQrText());
      expect(p.secrets.values['family.recoveryRestoring'], isNull);
      expect(
        (await p.container.read(recoveryStoreProvider).readRestore())!.phase,
        RecoveryPhase.needsAttention,
      );
      await app.abandon();
      expect(
        await p.container.read(recoveryStoreProvider).readRestore(),
        isNull,
      );
      await edit(p, 1);
      expect(
        (await p.container.read(familyStoreProvider).load())!.doc.record(
          'recipients',
          'p1',
        ),
        isNotNull,
      );
    },
  );

  test(
    'A1 empty phone abandons stuck journal, restores correct code twice',
    () async {
      final original = await phone();
      await create(original);
      final display = await original.container
          .read(recoveryApplicationProvider.notifier)
          .createCode();
      final empty = await phone();
      final app = empty.container.read(recoveryApplicationProvider.notifier);
      await app.restoreQr(RecoveryCode.generate().toQrText());
      await app.abandon();
      await app.restoreQr(display.qrText);
      expect(
        (await empty.container.read(recoveryStoreProvider).readRestore())!
            .phase,
        RecoveryPhase.active,
      );
      await app.restoreQr(display.qrText);
      expect(
        (await empty.container.read(recoveryStoreProvider).readRestore())!
            .phase,
        RecoveryPhase.active,
      );
      expect(
        await empty.container.read(familyStoreProvider).isTransferred(),
        isFalse,
      );
    },
  );

  test('A2 unreadable journal is discarded before family startup', () async {
    final p = await phone();
    await create(p);
    await p.container.read(recoveryApplicationProvider.notifier).createCode();
    p.dispose();
    p.secrets.values.remove(recoveryJournalKey);
    p.secrets.values['family.recoveryRestoring'] = 'true';
    p.restart(temp: temp);
    expect(
      (await p.container.read(familyControllerProvider.future)).hasFamily,
      isTrue,
    );
    expect(await p.container.read(recoveryStoreProvider).readRestore(), isNull);
    expect(p.files.files[recoveryJournalFile], isNull);
    expect(p.secrets.values['family.recoveryRestoring'], isNull);
    await edit(p, 1);
  });

  test(
    'M2 different v2 family requires explicit replacement before claim',
    () async {
      final a = await phone();
      await create(a);
      final display = await a.container
          .read(recoveryApplicationProvider.notifier)
          .createCode();
      final b = await phone();
      await create(b);
      await b.container.read(recoveryApplicationProvider.notifier).createCode();
      final before =
          (await b.container.read(familyStoreProvider).readSyncV2())!.syncId;
      final app = b.container.read(recoveryApplicationProvider.notifier);
      var claims = 0;
      w.intercept = (r) async {
        if (r.path.endsWith('/claim')) claims++;
        return null;
      };
      await app.restoreQr(display.qrText);
      expect(claims, 0);
      expect(
        b.container.read(recoveryStatusProvider).cause,
        'different_family',
      );
      expect(
        (await b.container.read(familyStoreProvider).readSyncV2())!.syncId,
        before,
      );
      await app.restoreQr(display.qrText, replaceExisting: true);
      expect(claims, 1);
      expect(
        await b.container.read(generationStoreProvider).generationIds(),
        contains(before),
      );
      expect((await app.rotateCode()).words, hasLength(24));
      b.restart(temp: temp);
      expect(
        (await b.container.read(familyControllerProvider.future)).hasFamily,
        isTrue,
      );
    },
  );

  test('B4 v1 replacement error is typed and generation reader rejects invalid ids', () async {
    final p = await phone();
    await create(p);
    await expectLater(
      p.container
          .read(recoveryApplicationProvider.notifier)
          .restoreQr(RecoveryCode.generate().toQrText()),
      throwsA(
        isA<RecoveryApplicationException>().having(
          (e) => e.code,
          'code',
          'existing_v1_family',
        ),
      ),
    );
    expect(
      () =>
          p.container.read(generationStoreProvider).recoveryReader('../escape'),
      throwsFormatException,
    );
  });

  test(
    'M1 recovery maintenance network failure does not fail ordinary sync',
    () async {
      final p = await phone();
      await create(p);
      await p.container.read(recoveryApplicationProvider.notifier).createCode();
      final family = p.container.read(familyStoreProvider);
      final sid = (await family.readSyncV2())!.syncId;
      final recovery = p.container.read(recoveryStoreProvider);
      final old = (await recovery.readMaterial(sid))!;
      await recovery.finishMaintenance(sid, {...old, 'uploadedAt': 0});
      await family.saveIdentity(
        (await family.load())!.identity.copyWith(deviceName: 'Nora'),
      );
      final before = V2SyncState.fromJson(await family.readSyncV2State())
          .version!;
      w.intercept = (_) async =>
          throw const SyncTransportException(SyncFailure.network, 'offline');
      await edit(p, 1);
      await eventually(
        () async =>
            V2SyncState.fromJson(await family.readSyncV2State()).version! >
            before,
      );
      await eventually(
        () =>
            p.container.read(syncControllerProvider).phase == SyncPhase.synced,
      );
      expect(p.container.read(recoveryStatusProvider).cause, 'network');
      expect(await recovery.readMaintenance(sid), isNotNull);
    },
  );
}
