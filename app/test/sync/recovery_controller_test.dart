import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/device_keys.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/protected_doc.dart';
import 'package:regalos/core/sync/recovery.dart';
import 'package:regalos/core/sync/recovery_locator.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/family/data/generation_storage.dart';
import 'package:regalos/features/family/data/generation_store.dart';
import 'package:regalos/features/family/data/recovery_store.dart';
import 'package:regalos/features/family/data/storage.dart';
import 'package:regalos/features/sync/application/recovery_controller.dart';
import 'package:regalos/features/sync/application/common_v2.dart';
import 'package:regalos/features/sync/application/recovery_local_merge.dart';
import 'package:regalos/features/sync/data/recovery_transport.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';

import '../helpers/memory_recovery_transport.dart';
import '../helpers/memory_stores.dart';

class Cut implements Exception {}

class ActivationCutGenerations extends GenerationStore {
  ActivationCutGenerations({required super.secrets, required super.files});
  @override
  Future<void> activateRecovery({
    required String operationId,
    required String syncId,
    required Map<String, Object?> source,
  }) async {
    await super.activateRecovery(
      operationId: operationId,
      syncId: syncId,
      source: source,
    );
    throw Cut();
  }
}

class RejectedActivation extends GenerationStore {
  RejectedActivation({required super.secrets, required super.files});
  @override
  Future<void> activateRecovery({
    required String operationId,
    required String syncId,
    required Map<String, Object?> source,
  }) async {
    throw const RecoverySourceException('different_family');
  }
}

class Faults {
  int writes = 0;
  int? at;
  bool after = false;
  void before() {
    writes++;
    if (!after && writes == at) throw Cut();
  }

  void done() {
    if (after && writes == at) throw Cut();
  }
}

class Secrets extends MemorySecretStore {
  Secrets(this.faults);
  final Faults faults;
  @override
  Future<void> write(String key, String value) async {
    faults.before();
    await super.write(key, value);
    faults.done();
  }
}

class Files extends MemoryFileStore {
  Files(this.faults);
  final Faults faults;
  @override
  Future<void> writeAtomic(String name, Uint8List bytes) async {
    faults.before();
    await super.writeAtomic(name, bytes);
    faults.done();
  }
}

class Reader implements RecoveryReader {
  bool verified = false;
  bool missing = false;
  int reads = 0;
  @override
  Future<RecoveryCapsulePayload> verify(
    RecoveryCapsulePayload p,
    GenerationContext? local,
  ) async {
    verified = true;
    return p;
  }

  @override
  Future<RecoveryDownload> download(
    RecoveryCapsulePayload p,
    Map<String, Object?> progress,
    GenerationContext? local,
  ) async {
    reads++;
    if (missing) {
      return RecoveryDownload(
        progress: {'page': 1},
        incompleteReason: 'missing_package',
      );
    }
    if (progress.isEmpty) return RecoveryDownload(progress: {'page': 1});
    return RecoveryDownload(
      progress: {'page': 2},
      installation: RecoveryInstallation(
        payload: p,
        doc: FamilyDoc.empty(p.identity.listId),
        slots: SlotSet.empty,
        scopes: const {},
      ),
    );
  }
}

class Wire implements RecoveryTransport {
  Wire(this.server, this.reader);
  final MemoryRecoveryTransport server;
  final Reader reader;
  bool loseClaim = false;
  Future<void> Function()? beforeClaim;
  final claims = <Map<String, Object?>>[];
  @override
  Future<RecoveryResponse> send(RecoveryRequest r) async {
    expect(
      r.method,
      isNot('PUT'),
      reason: 'restore must never publish a snapshot',
    );
    if (r.path.endsWith('/claim')) {
      expect(reader.verified, isTrue);
      claims.add(r.toJson());
      final callback = beforeClaim;
      beforeClaim = null;
      if (callback != null) await callback();
    }
    final response = await server.send(r);
    if (loseClaim && r.path.endsWith('/claim') && response.status == 200) {
      loseClaim = false;
      throw Cut();
    }
    return response;
  }
}

void main() {
  final vector = jsonDecode(
    File('../docs/adr/0007-vector-recuperacion.json').readAsStringSync(),
  ) as Map;
  late RecoveryCapsulePayload payload;
  late RecoveryCode code;
  late RecoveryLocator locator;
  late V2Auth auth;
  setUpAll(() async {
    payload = await RecoveryCapsulePayload.fromJson(vector['payload']);
    final hex = vector['entropyHex'] as String;
    code = RecoveryCode(
      Uint8List.fromList([
        for (var i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ]),
    );
    locator = await deriveRecoveryLocator(code);
    auth = V2Auth(
      syncId: payload.identity.syncId,
      deviceId: payload.identity.deviceId,
      credential: payload.deviceKeys.serviceCredential,
    );
  });

  Future<MemoryRecoveryTransport> server() async {
    final s = MemoryRecoveryTransport();
    await s.register(auth);
    final created = await s.send(
      RecoveryRequest(
        'PUT',
        '/v2/lists/${auth.syncId}/recoveries/${locator.recoveryId}',
        headers: {
          ...recoveryAuthHeaders(auth, 0),
          'X-Recovery-Operation': encodeBase64Url(List.filled(16, 8)),
        },
        body: {
          'v': 2,
          'deviceId': auth.deviceId,
          'readVerifier': locator.readVerifier,
          'capsule': vector['capsule'],
        },
      ),
    );
    expect(created.status, 201);
    return s;
  }

  RecoveryController controller(
    SecretStore s,
    FileStore f,
    Wire wire,
    Reader reader,
  ) => RecoveryController(
    store: RecoveryStore(secrets: s, files: f),
    generations: GenerationStore(secrets: s, files: f),
    transport: wire,
    reader: reader,
  );

  test('A1 abandon after ambiguous claim erases staging and releases the global gate', () async {
    final s = MemorySecretStore(), f = MemoryFileStore();
    final reader = Reader();
    final wire = Wire(await server(), reader)..loseClaim = true;
    final c = controller(s, f, wire, reader);
    await expectLater(c.start(code), throwsA(isA<Cut>()));
    final j = (await c.store.readRestore())!;
    final staged = c.generations.recoveryStaging(j.operationId);
    await staged.deviceKeys.restore(payload.deviceKeys);
    final workspace = c.generations.recoveryReader(auth.syncId);
    await workspace.deviceKeys.restoreReadWorkspace(payload.deviceKeys);
    await c.abandon();
    expect(await c.store.readRestore(), isNull);
    expect(s.values['family.recoveryRestoring'], isNull);
    expect(
      s.values.keys.where(
        (k) => k.startsWith('generation.') || k.startsWith('recovery.read.'),
      ),
      isEmpty,
    );
    expect(
      f.files.keys.where(
        (k) => k.startsWith('generation.') || k.startsWith('recovery.read.'),
      ),
      isEmpty,
    );
    expect((await c.start(code)).phase, RecoveryPhase.active);
  });

  for (final phase in [
    RecoveryPhase.locating,
    RecoveryPhase.located,
    RecoveryPhase.verified,
    RecoveryPhase.installPrepared,
  ]) {
    for (final v2 in [false, true]) {
      test(
        'ALTA-1 $phase detects a new ${v2 ? 'v2' : 'v1'} family on resume',
        () async {
          final s = MemorySecretStore(), f = MemoryFileStore();
          final reader = Reader();
          final wire = Wire(await server(), reader);
          final c = RecoveryController(
            store: RecoveryStore(secrets: s, files: f),
            generations: GenerationStore(secrets: s, files: f),
            transport: wire,
            reader: reader,
            onPhase: (p) {
              if (p == phase) throw Cut();
            },
          );
          await expectLater(c.start(code), throwsA(isA<Cut>()));
          // Simulate a family installed by an older client while offline.
          s.values.remove('family.recoveryRestoring');
          final keys = DeviceKeysStore(s);
          final family = FamilyStore(secrets: s, files: f, deviceKeys: keys);
          await keys.restore(payload.deviceKeys);
          await family.saveFamily(
            StoredFamily(
              identity: FamilyIdentity(
                listId: payload.identity.listId,
                node: auth.deviceId,
                deviceName: 'Nora',
                selfRecipientId: payload.personId,
              ),
              key: payload.familyKey,
              doc: FamilyDoc.empty(payload.identity.listId),
            ),
          );
          if (v2) {
            await family.saveSyncV2(payload.identity);
            await c.generations.adoptCurrent();
          }
          final claimsBefore = wire.claims.length;
          final result = await controller(s, f, wire, reader).resume();
          expect(result.phase, RecoveryPhase.needsAttention);
          expect(result.data['reason'], 'different_family');
          expect(wire.claims, hasLength(claimsBefore));
          expect((await family.load())!.identity.deviceName, 'Nora');
          if (phase == RecoveryPhase.verified ||
              phase == RecoveryPhase.installPrepared) {
            expect(
              (await controller(
                s,
                f,
                wire,
                reader,
              ).start(code, replaceExisting: true)).phase,
              RecoveryPhase.active,
            );
          }
        },
      );
    }
  }

  test(
    'BAJA-1 abandoning a prepared but unsent claim keeps local family writable',
    () async {
      final s = MemorySecretStore(), f = MemoryFileStore();
      final reader = Reader();
      final wire = Wire(await server(), reader);
      final keys = DeviceKeysStore(s);
      final family = FamilyStore(secrets: s, files: f, deviceKeys: keys);
      await keys.restore(payload.deviceKeys);
      await family.saveFamily(
        StoredFamily(
          identity: FamilyIdentity(
            listId: payload.identity.listId,
            node: auth.deviceId,
            deviceName: 'Aritz',
            selfRecipientId: payload.personId,
          ),
          key: payload.familyKey,
          doc: FamilyDoc.empty(payload.identity.listId),
        ),
      );
      await family.saveSyncV2(payload.identity);
      final c = RecoveryController(
        store: RecoveryStore(secrets: s, files: f),
        generations: GenerationStore(secrets: s, files: f),
        transport: wire,
        reader: reader,
        onPhase: (p) {
          if (p == RecoveryPhase.claimPrepared) throw Cut();
        },
      );
      await expectLater(c.start(code), throwsA(isA<Cut>()));
      expect(wire.claims, isEmpty);
      await c.abandon();
      expect(await family.isTransferred(), isFalse);
      await family.saveDoc((await family.load())!.doc);
    },
  );

  test(
    'A1 abandon after activation keeps the selected claimed namespace writable',
    () async {
      final s = MemorySecretStore(), f = MemoryFileStore();
      final reader = Reader();
      final wire = Wire(await server(), reader);
      final c = RecoveryController(
        store: RecoveryStore(secrets: s, files: f),
        generations: ActivationCutGenerations(secrets: s, files: f),
        transport: wire,
        reader: reader,
      );
      await expectLater(c.start(code), throwsA(isA<Cut>()));
      expect(
        (await c.store.readRestore())!.phase,
        RecoveryPhase.installPrepared,
      );
      await c.abandon();
      expect(await c.store.readRestore(), isNull);
      final active = await c.generations.open(auth.syncId);
      expect(await active.family.isTransferred(), isFalse);
      final doc = (await active.family.load())!.doc;
      await active.family.saveDoc(doc);
      expect(await active.deviceKeys.read(), isNotNull);
      expect(await c.store.readMaterial(auth.syncId), isNotNull);
    },
  );

  test(
    'ALTA-1 typed activation rejection becomes actionable needsAttention',
    () async {
      final s = MemorySecretStore(), f = MemoryFileStore();
      final reader = Reader();
      final c = RecoveryController(
        store: RecoveryStore(secrets: s, files: f),
        generations: RejectedActivation(secrets: s, files: f),
        transport: Wire(await server(), reader),
        reader: reader,
      );
      final result = await c.start(code);
      expect(result.phase, RecoveryPhase.needsAttention);
      expect(result.data['reason'], 'different_family');
      expect(result.claimSent, isTrue);
      await c.abandon();
      expect(s.values['family.recoveryRestoring'], isNull);
    },
  );

  test('ALTA-1 activation checks root v1 without a directory', () async {
    final s = MemorySecretStore(), f = MemoryFileStore();
    final generations = GenerationStore(secrets: s, files: f);
    final source = await generations.recoverySource();
    final family = FamilyStore(
      secrets: s,
      files: f,
      deviceKeys: DeviceKeysStore(s),
    );
    await family.saveFamily(
      StoredFamily(
        identity: FamilyIdentity(
          listId: payload.identity.listId,
          node: auth.deviceId,
          deviceName: 'Nora',
        ),
        key: payload.familyKey,
        doc: FamilyDoc.empty(payload.identity.listId),
      ),
    );
    await expectLater(
      generations.activateRecovery(
        operationId: encodeBase64Url(List.filled(16, 7)),
        syncId: auth.syncId,
        source: source,
      ),
      throwsA(
        isA<RecoverySourceException>().having(
          (e) => e.code,
          'code',
          'different_family',
        ),
      ),
    );
    expect((await family.load())!.identity.deviceName, 'Nora');
  });

  test('lost claim response replays exact request; old credential is cut before installation', () async {
    final s = MemorySecretStore();
    final f = MemoryFileStore();
    final backend = await server();
    final reader = Reader();
    final wire = Wire(backend, reader)..loseClaim = true;
    var c = controller(s, f, wire, reader);
    await expectLater(c.start(code), throwsA(isA<Cut>()));
    expect((await c.store.readRestore())!.phase, RecoveryPhase.claimPrepared);
    expect(await GenerationDirectory.read(s), isNull);
    final rejected = await backend.send(
      RecoveryRequest(
        'GET',
        '/v2/lists/${auth.syncId}/recoveries',
        headers: {'Authorization': auth.bearer},
      ),
    );
    expect(rejected.error, 'credential_replaced');
    c = controller(s, f, wire, reader);
    expect((await c.resume()).phase, RecoveryPhase.active);
    expect(wire.claims, hasLength(2));
    expect(wire.claims[0], wire.claims[1]);
    final active = await c.generations.open(auth.syncId);
    expect(await active.family.remoteSyncEnabled(), isTrue);
    expect((await active.family.readSyncV2())!.deviceId, auth.deviceId);
    expect(
      (await active.deviceKeys.read())!.serviceCredential,
      isNot(auth.credential),
    );
    expect(await c.store.readMaterial(auth.syncId), contains('entropy'));
    expect((await c.store.readRestore())!.data.keys, ['syncId']);
  });

  test('every durable write resumes after a cut before and after, without a partial active family', () async {
    Future<int> run(int? at, bool after) async {
      final faults = Faults()
        ..at = at
        ..after = after;
      final s = Secrets(faults);
      final f = Files(faults);
      final reader = Reader();
      final wire = Wire(await server(), reader);
      var c = controller(s, f, wire, reader);
      try {
        await c.start(code);
      } on Cut {
        final directory = await GenerationDirectory.read(s);
        if (directory != null) {
          final active = await c.generations.open(directory.active);
          expect(await active.family.load(), isNotNull);
          expect(await active.family.remoteSyncEnabled(), isTrue);
          expect(await active.family.readCommonKeys(), isNotNull);
        }
      }
      final count = faults.writes;
      faults.at = null;
      c = controller(s, f, wire, reader);
      final pending = await c.store.readRestore();
      final result = pending == null ? await c.start(code) : await c.resume();
      expect(
        result.phase,
        RecoveryPhase.active,
        reason: 'write $at after=$after',
      );
      final active = await c.generations.open(auth.syncId);
      expect(await active.family.remoteSyncEnabled(), isTrue);
      expect((await active.family.load())!.identity.node, auth.deviceId);
      return count;
    }

    final count = await run(null, false);
    for (var n = 1; n <= count; n++) {
      await run(n, false);
      await run(n, true);
    }
  }, timeout: const Timeout(Duration(minutes: 12)));

  test(
    'missing packages retain progress and preserve an existing family',
    () async {
      final s = MemorySecretStore();
      final f = MemoryFileStore();
      final keys = DeviceKeysStore(s);
      final family = FamilyStore(secrets: s, files: f, deviceKeys: keys);
      await keys.restore(payload.deviceKeys);
      await family.saveFamily(
        StoredFamily(
          identity: FamilyIdentity(
            listId: payload.identity.listId,
            node: auth.deviceId,
            deviceName: 'Aritz',
            selfRecipientId: payload.personId,
          ),
          key: payload.familyKey,
          doc: FamilyDoc.empty(payload.identity.listId),
        ),
      );
      await family.saveSyncV2(payload.identity);
      await family.saveRegistry(payload.registry);
      final reader = Reader()..missing = true;
      final wire = Wire(await server(), reader);
      var c = controller(s, f, wire, reader);
      final result = await c.start(code);
      expect(result.phase, RecoveryPhase.needsAttention);
      expect(result.data['progress'], {'page': 1});
      expect((await family.load())!.identity.deviceName, 'Aritz');
      reader.missing = false;
      c = controller(s, f, wire, reader);
      expect((await c.retryIncomplete()).phase, RecoveryPhase.active);
    },
  );

  test(
    'transferred is durable, read-only, and exact errors alone trigger it',
    () async {
      final s = MemorySecretStore();
      final f = MemoryFileStore();
      final reader = Reader();
      final wire = Wire(await server(), reader);
      final c = controller(s, f, wire, reader);
      await c.start(code);
      final old = await c.generations.open(auth.syncId);
      final doc = (await old.family.load())!.doc;
      expect(
        await c.handleRejection(
          auth.syncId,
          status: 503,
          error: 'credential_replaced',
        ),
        isFalse,
      );
      expect(
        await c.handleRejection(auth.syncId, status: 403, error: 'revoked'),
        isFalse,
      );
      await c.handleRejection(
        auth.syncId,
        socketCode: 4410,
        socketReason: 'credential_replaced',
      );
      final reopened = controller(s, f, wire, reader);
      expect(await reopened.store.isTransferred(auth.syncId), isTrue);
      expect(await old.family.isTransferred(), isTrue);
      expect(await old.family.load(), isNotNull);
      expect(await old.deviceKeys.read(), isNotNull);
      await expectLater(old.family.saveDoc(doc), throwsStateError);
      await expectLater(
        old.family.saveSyncV2State({'c': true}),
        throwsStateError,
      );
      await expectLater(old.deviceKeys.purgePerson(null), throwsStateError);
      await expectLater(
        old.family.deleteScope(encodeBase64Url(List.filled(16, 5))),
        throwsStateError,
      );
    },
  );

  test('old capsule unions registry and preserves newer local data, key state and revision floors', () async {
    final s = MemorySecretStore();
    final f = MemoryFileStore();
    final keys = DeviceKeysStore(s);
    final family = FamilyStore(secrets: s, files: f, deviceKeys: keys);
    await keys.restore(payload.deviceKeys);
    final clock = HlcClock(
      node: auth.deviceId,
      last: Hlc(millis: 900000, counter: 4, node: auth.deviceId),
    );
    final doc = FamilyDoc.empty(payload.identity.listId).set(
      clock,
      'recipients',
      encodeBase64Url(List.filled(16, 3)),
      {'name': 'Nora'},
    );
    await family.saveFamily(
      StoredFamily(
        identity: FamilyIdentity(
          listId: payload.identity.listId,
          node: auth.deviceId,
          deviceName: payload.deviceName,
          paired: false,
          selfRecipientId: payload.personId,
        ),
        key: payload.familyKey,
        doc: doc,
      ),
    );
    await family.saveSyncV2(payload.identity);
    final other = await DeviceRecord.create(
      keys: await DeviceKeys.generate(),
      listId: payload.identity.listId,
      deviceId: encodeBase64Url(List.filled(16, 9)),
      personId: null,
    );
    await family.saveRegistry(await payload.registry.withRecord(other));
    await family.saveCommonKeys(
      CommonKeyState(
        keyring: payload.commonKeys.keyring,
        revision: 900,
        lastKid: payload.commonKeys.lastKid,
      ).toJson(),
    );
    await family.raiseCommonFormatFloor(2);
    await family.markCommonKeys();
    final person = encodeBase64Url(List.filled(16, 3));
    await family.raiseRecoveryRevisionFloors({
      '$person/${auth.deviceId}': 999999,
    }, hlc: clock.last);
    await family.saveScope(person, doc);
    // Security review, B1: a private scope with a stamp far ahead of the
    // public data must not become the floor of the public clock.
    final person2 = encodeBase64Url(List.filled(16, 4));
    final ahead = Hlc(millis: 9000000000000, counter: 0, node: auth.deviceId);
    final privateScope = FamilyDoc.empty(payload.identity.listId).set(
      HlcClock(node: auth.deviceId, last: ahead),
      'gifts',
      'g1',
      {'recipientId': person2, 'title': 'Secreto'},
    );
    await family.saveScope(person2, privateScope);
    final reader = Reader();
    final wire = Wire(await server(), reader);
    final c = controller(s, f, wire, reader);
    await c.generations.adoptCurrent();
    await mergeRecoveryLocal(payload, await c.generations.open(auth.syncId));
    final restored = await c.start(code);
    expect(
      restored.phase,
      RecoveryPhase.active,
      reason: '${restored.data['reason']} / ${restored.data['resumePhase']}',
    );
    final active = await c.generations.open(auth.syncId);
    expect((await active.family.load())!.doc.toJson(), doc.toJson());
    expect((await active.family.load())!.identity.paired, isFalse);
    expect(await active.family.remoteSyncEnabled(), isTrue);
    expect(
      (await active.family.readRegistry())!.records.map((r) => r.digest),
      contains(other.digest),
    );
    expect(
      CommonKeyState.fromJson(await active.family.readCommonKeys()).revision,
      900,
    );
    expect(await active.family.readCommonFormatFloor(), 2);
    expect(await active.family.commonKeysMarked(), isTrue);
    final floors = await active.family.readRecoveryRevisionFloors();
    expect(floors.slots['$person/${auth.deviceId}'], 999999);
    expect(floors.hlc! >= clock.last, isTrue);
    expect(floors.hlc! < ahead, isTrue, reason: 'the public floor ignores scopes');
    expect(
      (await active.family.readScope(person2))!.maxStamp,
      privateScope.maxStamp,
      reason: 'the scope keeps its own stamps',
    );
    expect((await active.family.readScope(person))!.toJson(), doc.toJson());
    final archiveId = (await c.generations.generationIds()).firstWhere(
      (id) => id != auth.syncId,
    );
    final archived = await c.generations.open(archiveId);
    expect((await archived.family.load())!.doc.toJson(), doc.toJson());
  });

  test('monotone floors survive reopening; maintenance intentions do not lose secrets', () async {
    final s = MemorySecretStore();
    final f = MemoryFileStore();
    final family = FamilyStore(
      secrets: s,
      files: f,
      deviceKeys: DeviceKeysStore(s),
    );
    final id = '${auth.deviceId}/${auth.deviceId}';
    await family.raiseRecoveryRevisionFloors({
      id: 99,
    }, hlc: Hlc(millis: 100, counter: 4, node: auth.deviceId));
    await family.raiseRecoveryRevisionFloors({
      id: 3,
    }, hlc: Hlc(millis: 1, counter: 0, node: auth.deviceId));
    await family.raiseCommonFormatFloor(2);
    await family.raiseCommonFormatFloor(1);
    expect((await family.readRecoveryRevisionFloors()).slots[id], 99);
    expect(await family.readCommonFormatFloor(), 2);
    final store = RecoveryStore(secrets: s, files: f);
    for (final kind in RecoveryMaintenanceKind.values) {
      await store.prepareMaintenance(auth.syncId, kind, {
        'body': {'secret': 'retained'},
        'cas': 1,
      });
      expect(
        (await RecoveryStore(
          secrets: s,
          files: f,
        ).readMaintenance(auth.syncId))!['kind'],
        kind.name,
      );
      await store.finishMaintenance(auth.syncId, {'entropy': 'retained'});
      expect(await store.readMaterial(auth.syncId), {'entropy': 'retained'});
    }
  });

  test(
    'CAS change reopens and revalidates before preparing another exact claim',
    () async {
      final s = MemorySecretStore();
      final f = MemoryFileStore();
      final backend = await server();
      final reader = Reader();
      final wire = Wire(backend, reader);
      wire.beforeClaim = () async {
        final bytes = await sealRecoveryCapsule(payload, code, revision: 2);
        final updated = await backend.send(
          RecoveryRequest(
            'PUT',
            '/v2/lists/${auth.syncId}/recoveries/${locator.recoveryId}',
            headers: recoveryAuthHeaders(auth, 1),
            body: {
              'v': 2,
              'deviceId': auth.deviceId,
              'readVerifier': locator.readVerifier,
              'capsule': encodeBase64Url(bytes),
            },
          ),
        );
        expect(updated.status, 200);
      };
      final c = controller(s, f, wire, reader);
      expect((await c.start(code)).phase, RecoveryPhase.active);
      expect(wire.claims, hasLength(2));
      expect((wire.claims[0]['headers'] as Map)['If-Match'], '"1"');
      expect((wire.claims[1]['headers'] as Map)['If-Match'], '"2"');
      expect(
        (wire.claims[0]['body'] as Map)['operationId'],
        (wire.claims[1]['body'] as Map)['operationId'],
      );
    },
  );

  test('M3 another claim wins: reopen and revalidate current capsule without poisoning sid', () async {
    final s = MemorySecretStore();
    final f = MemoryFileStore();
    final backend = await server();
    final reader = Reader();
    final wire = Wire(backend, reader);
    wire.beforeClaim = () async {
      final keys = await payload.deviceKeys.withNewServiceCredential();
      final other = await RecoveryCapsulePayload.fromJson({
        ...payload.toJson(),
        'deviceKeys': keys.toJson(),
      });
      final bytes = await sealRecoveryCapsule(other, code, revision: 2);
      final accepted = await backend.send(
        RecoveryRequest(
          'POST',
          '/v2/recoveries/${locator.recoveryId}/claim',
          headers: {
            ...recoveryAuthHeaders(auth, 1),
            'X-Recovery-Cap': locator.readCap,
          },
          body: {
            'v': 2,
            'operationId': encodeBase64Url(List.filled(16, 77)),
            'newCredentialVerifier': encodeBase64Url(
              await keys.serviceCredentialVerifier(),
            ),
            'capsule': encodeBase64Url(bytes),
          },
        ),
      );
      expect(accepted.status, 200);
    };
    final c = controller(s, f, wire, reader);
    final result = await c.start(code);
    expect(result.phase, RecoveryPhase.active);
    expect(await GenerationDirectory.read(s), isNotNull);
    final reopened = controller(s, f, wire, reader);
    expect(await reopened.store.isTransferred(auth.syncId), isFalse);
    expect((await reopened.resume()).phase, RecoveryPhase.active);
    expect(wire.claims, hasLength(2));
    expect((await reopened.start(code)).phase, RecoveryPhase.active);
  });

  test('a cut between transferred gate and encrypted bookkeeping still blocks old handles', () async {
    final faults = Faults();
    final s = Secrets(faults);
    final f = Files(faults);
    final reader = Reader();
    final wire = Wire(await server(), reader);
    final c = controller(s, f, wire, reader);
    await c.start(code);
    final old = await c.generations.open(auth.syncId);
    final doc = (await old.family.load())!.doc;
    faults.writes = 0;
    faults.at = 1;
    faults.after = true;
    await expectLater(
      c.handleRejection(auth.syncId, status: 403, error: 'credential_replaced'),
      throwsA(isA<Cut>()),
    );
    faults.at = null;
    final reopened = controller(s, f, wire, reader);
    expect(await reopened.store.isTransferred(auth.syncId), isTrue);
    expect(await old.family.load(), isNotNull);
    await expectLater(old.family.saveDoc(doc), throwsStateError);
    await expectLater(
      reopened.store.prepareMaintenance(
        auth.syncId,
        RecoveryMaintenanceKind.update,
        {'cas': 2},
      ),
      throwsStateError,
    );
  });
}
