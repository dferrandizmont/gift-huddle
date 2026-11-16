import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/device_keys.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_candidate.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/pairing_v2.dart';
import 'package:regalos/core/sync/protected_doc.dart';
import 'package:regalos/core/sync/protected_envelope.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/family/data/generation_storage.dart';
import 'package:regalos/features/family/data/generation_store.dart';
import 'package:regalos/features/sync/application/common_v2.dart';

import '../helpers/memory_stores.dart';

const _sourceId = 'AAAAAAAAAAAAAAAAAAAAAA';
const _destinationId = 'BBBBBBBBBBBBBBBBBBBBBB';
const _hash =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

class _Interrupted implements Exception {}

class _ReadBarrier {
  _ReadBarrier(this.name);
  final String name;
  final reached = Completer<void>();
  final resume = Completer<void>();
}

class _Faults {
  int writes = 0;
  int? failAt;
  bool after = false;

  Future<void> mutate(Future<void> Function() action) async {
    final fails = ++writes == failAt;
    if (fails && !after) throw _Interrupted();
    await action();
    if (fails && after) throw _Interrupted();
  }
}

class _Secrets extends MemorySecretStore {
  _Secrets(this.faults);
  final _Faults faults;
  _ReadBarrier? barrier;
  @override
  Future<String?> read(String key) async {
    final value = await super.read(key);
    final paused = barrier;
    if (paused?.name == key) {
      barrier = null;
      paused!.reached.complete();
      await paused.resume.future;
    }
    return value;
  }

  @override
  Future<void> write(String key, String value) =>
      faults.mutate(() => super.write(key, value));
  @override
  Future<void> delete(String key) => faults.mutate(() => super.delete(key));
  @override
  Future<void> eraseAllSecrets() => faults.mutate(super.eraseAllSecrets);
}

class _Files extends MemoryFileStore {
  _Files(this.faults);
  final _Faults faults;
  _ReadBarrier? barrier;
  @override
  Future<Uint8List?> read(String name) async {
    final value = await super.read(name);
    final paused = barrier;
    if (paused?.name == name) {
      barrier = null;
      paused!.reached.complete();
      await paused.resume.future;
    }
    return value;
  }

  @override
  Future<void> writeAtomic(String name, Uint8List bytes) =>
      faults.mutate(() => super.writeAtomic(name, bytes));
  @override
  Future<void> delete(String name) => faults.mutate(() => super.delete(name));
}

class _Phone {
  _Phone() {
    secrets = _Secrets(faults);
    files = _Files(faults);
    restart();
  }

  final faults = _Faults();
  late final _Secrets secrets;
  late final _Files files;
  late DeviceKeysStore keys;
  late FamilyStore family;
  late GenerationStore generations;

  void restart() {
    keys = DeviceKeysStore(secrets, enabled: true);
    family = FamilyStore(secrets: secrets, files: files, deviceKeys: keys);
    generations = GenerationStore(secrets: secrets, files: files);
  }

  _Phone copy() {
    final next = _Phone();
    next.secrets.values.addAll(secrets.values);
    next.files.files.addAll({
      for (final e in files.files.entries) e.key: Uint8List.fromList(e.value),
    });
    return next;
  }

  Future<void> seed({bool commonFormat2 = true}) async {
    final ownKeys = await keys.create();
    final doc = FamilyDoc(
      listId: 'list-1',
      collections: {
        Collections.recipients: {
          for (final id in ['aritz', 'nora', 'leo'])
            id: SyncRecord(
              id: id,
              fields: {
                'name': FieldValue(
                  value: id,
                  stamp: Hlc(millis: 42, counter: 7, node: 'source-device'),
                ),
              },
            ),
        },
        'unknown-future': {
          'kept': SyncRecord(
            id: 'kept',
            fields: {
              'nested': FieldValue(
                value: {
                  'opaque': [1, 2],
                },
                stamp: Hlc(millis: 43, counter: 9, node: 'source-device'),
              ),
            },
          ),
          'deleted': SyncRecord(
            id: 'deleted',
            fields: {
              'deleted': FieldValue(
                value: true,
                stamp: Hlc(millis: 44, counter: 1, node: 'source-device'),
              ),
            },
          ),
        },
      },
    );
    await family.saveFamily(
      StoredFamily(
        identity: const FamilyIdentity(
          listId: 'list-1',
          node: 'source-device',
          deviceName: 'Pixel',
          selfRecipientId: 'aritz',
        ),
        key: await FamilyKey.generate(),
        doc: doc,
      ),
    );
    await family.saveSyncV2(
      SyncIdentityV2(
        listId: 'list-1',
        deviceId: 'source-device',
        syncId: _sourceId,
      ),
    );
    final registry = await DeviceRegistry.empty('list-1').withRecord(
      await DeviceRecord.create(
        keys: ownKeys,
        listId: 'list-1',
        deviceId: 'source-device',
        personId: 'aritz',
      ),
    );
    await family.saveRegistry(registry);
    await family.saveSyncV2State({
      'version': 17,
      'pending': ['put', 'revoke'],
      'ignored': ['unreadable'],
    });
    await family.savePendingV2({
      'checkpoint': 'exact',
      'credential': 'prepared',
    });
    await family.saveOrphans([
      {'d': 'old-orphan', 'record': 'old-record'},
    ]);
    await family.saveLegacyV1({'archived': true});
    await family.saveV1ProofKey({'archivedProof': true});
    final scope = FamilyDoc.empty('list-1').set(
      HlcClock(node: 'source-device'),
      Collections.gifts,
      'gift',
      {'title': 'Peonza', 'recipientId': 'nora'},
    );
    await family.saveScope('nora', scope);
    await family.saveOverflow(
      'nora',
      scope.collections[Collections.gifts]!.values.toList(),
    );
    final key = SurpriseKey.generate('nora', 1, audience: ['source-device']);
    await keys.saveKeyring('list-1', SurpriseKeyring([key]));
    final slot = await SealedSlot.seal(
      writerKeys: ownKeys,
      writer: 'source-device',
      revision: 1,
      key: key,
      policy: const PolicyState(hideOwnGifts: true, rev: 1),
      doc: scope,
    );
    final view = await registry.viewFor(
      me: 'source-device',
      mySigningKey: ownKeys.publicKeys.signing,
      livePeople: {'aritz', 'nora', 'leo'},
    );
    await family.saveSlots((await SlotSet.verified([slot], view: view)).$1);
    if (commonFormat2) await installCommon(family, ownKeys, _sourceId);
    await family.saveRetainedBytes(_hash, Uint8List.fromList([3, 4, 5]));
    await family.saveRetainedCommons([
      {'h': _hash, 'b': true},
    ]);
    if (commonFormat2) await family.raiseCommonFormatFloor(2);
    faults.writes = 0;
  }

  Future<PreparedGeneration> prepare() => generations.prepare(
    operationId: 'operation-1',
    destinationSyncId: _destinationId,
  );

  Future<void> ready() async {
    final target = await generations.open(_destinationId);
    await installCommon(
      target.family,
      (await target.deviceKeys.read())!,
      _destinationId,
    );
    final pending = (await generations.journal.read())!;
    await generations.journal.save(
      pending.next(
        phase: 'moving',
        data: {...pending.data, 'destinationReady': true},
      ),
    );
    faults.writes = 0;
  }
}

Future<void> installCommon(
  FamilyStore store,
  DeviceKeys keys,
  String syncId,
) async {
  final identity = (await store.readSyncV2())!;
  final registry = (await store.readRegistry())!;
  final view = await registry.viewFor(
    me: identity.deviceId,
    mySigningKey: keys.publicKeys.signing,
    livePeople: {'aritz', 'nora', 'leo'},
  );
  final candidate = await FamilyCandidate.generate(
    view,
    keys: keys,
    syncId: syncId,
  );
  await store.saveCommonKeys(
    CommonKeyState(
      keyring: FamilyKeyring.empty
          .withOwnCandidate(candidate)
          .withReference(candidate.kid, 'checkpoint:retained')
          .withReference(candidate.kid, kCommonRef),
      revision: 7,
      lastKid: candidate.kid,
      outbox: const [
        {'pending': 'package'},
      ],
    ).toJson(),
  );
  await store.markCommonKeys();
}

void main() {
  late _Phone source;
  setUpAll(() async {
    source = _Phone();
    await source.seed();
  });

  for (final access in ['family.identity', 'family.doc', 'family.registry']) {
    test('activation between $access and later reads stays coherent', () async {
      final phone = source.copy();
      final oldFamily = (await phone.family.load())!;
      final oldRegistry = (await phone.family.readRegistry())!
          .toLocalStoreJson();
      final prepared = await phone.prepare();
      final target = await phone.generations.open(_destinationId);
      final newDoc = prepared.family.doc.set(
        HlcClock(node: prepared.identity.deviceId),
        'unknown-future',
        'new-generation',
        {'value': 'destination only'},
      );
      await target.family.saveDoc(newDoc);
      await phone.ready();
      final barrier = _ReadBarrier(access);
      if (access == 'family.identity') {
        phone.secrets.barrier = barrier;
      } else {
        phone.files.barrier = barrier;
      }
      final readingRegistry = access == 'family.registry';
      final reading = readingRegistry
          ? phone.family.readRegistry()
          : phone.family.load();
      await barrier.reached.future;
      try {
        await phone.generations.activate('operation-1');
        expect(await phone.generations.activeSyncId(), _destinationId);
        // A concurrent operation must see the new generation while the
        // suspended operation keeps its old namespace, without a global pin.
        final current = (await phone.family.load())!;
        expect(current.identity.node, prepared.identity.deviceId);
        expect(current.key.toBase64Url(), prepared.family.key.toBase64Url());
        expect(current.doc.canonicalJson(), newDoc.canonicalJson());
      } finally {
        barrier.resume.complete();
      }
      final result = await reading;
      if (readingRegistry) {
        expect((result as DeviceRegistry).toLocalStoreJson(), oldRegistry);
        expect(
          (await phone.family.readRegistry())!.records.single.deviceId,
          prepared.identity.deviceId,
        );
      } else {
        final family = result as StoredFamily;
        expect(family.identity.toJson(), oldFamily.identity.toJson());
        expect(family.key.toBase64Url(), oldFamily.key.toBase64Url());
        expect(family.doc.canonicalJson(), oldFamily.doc.canonicalJson());
      }
    });
  }

  test(
    'pre.29 common format 1 opens unchanged and renews into format 2',
    () async {
      final phone = _Phone();
      await phone.seed(commonFormat2: false);
      final original = (await phone.family.load())!;
      final secrets = Map.of(phone.secrets.values);
      final files = Map.of(phone.files.files);
      expect(secrets.containsKey(generationDirectoryKey), isFalse);
      expect(await phone.family.readCommonFormatFloor(), 1);
      expect(await phone.family.readCommonKeys(), isNull);
      expect(await phone.family.commonKeysMarked(), isFalse);
      phone.restart();
      expect(
        (await phone.family.load())!.doc.canonicalJson(),
        original.doc.canonicalJson(),
      );
      final prepared = await phone.prepare();
      final old = await phone.generations.open(_sourceId);
      expect(await old.family.readCommonFormatFloor(), 1);
      expect(
        (await old.family.load())!.identity.toJson(),
        original.identity.toJson(),
      );
      expect(
        (await old.family.load())!.key.toBase64Url(),
        original.key.toBase64Url(),
      );
      expect(prepared.family.doc.canonicalJson(), original.doc.canonicalJson());
      await phone.ready();
      await phone.generations.activate('operation-1');
      phone.restart();
      expect(await phone.family.readCommonFormatFloor(), 2);
      await phone.family.raiseCommonFormatFloor(1);
      expect(await phone.family.readCommonFormatFloor(), 2);
      expect(
        (await phone.family.load())!.doc.canonicalJson(),
        original.doc.canonicalJson(),
      );
      for (final e in secrets.entries) {
        expect(phone.secrets.values[e.key], e.value, reason: e.key);
      }
      for (final e in files.entries) {
        expect(phone.files.files[e.key], e.value, reason: e.key);
      }
      expect(
        (await old.family.readScope('nora'))!.collections[Collections.gifts],
        isNotEmpty,
      );
      expect((await old.deviceKeys.readKeyring('list-1')).keys.length, 1);
      expect(await old.family.readRetainedBytes(_hash), [3, 4, 5]);
    },
  );

  for (final activated in [false, true]) {
    test(
      'confirmed erase permits a new family and renewal (active=$activated)',
      () async {
        final phone = source.copy();
        await phone.prepare();
        if (activated) {
          await phone.ready();
          await phone.generations.activate('operation-1');
          await phone.generations.journal.archive('operation-1');
          await phone.generations.prepare(
            operationId: 'operation-2',
            destinationSyncId: 'CCCCCCCCCCCCCCCCCCCCCC',
          );
        }
        await expectLater(
          phone.family.clear(),
          throwsA(isA<FamilyStoreException>()),
        );
        await phone.generations.eraseAllConfirmed();
        expect(phone.files.files, isEmpty);
        expect(phone.secrets.values, isEmpty);
        // The rest of EraseAll can now sweep the secure store and reset the
        // controller without orphaning an encrypted renewal journal.
        phone.secrets.values.clear();
        await phone.family.clear();
        phone.restart();
        expect(await phone.family.load(), isNull);
        expect(await phone.generations.journal.read(), isNull);
        expect(await phone.generations.journal.readArchives(), isEmpty);
        await phone.seed();
        final next = await phone.prepare();
        expect(next.identity.syncId, _destinationId);
        expect(await phone.generations.generationIds(), {
          _sourceId,
          _destinationId,
        });
      },
    );
  }

  for (final after in [false, true]) {
    test(
      'confirmed erase recovers every interruption (after=$after)',
      () async {
        final prepared = source.copy();
        await prepared.prepare();
        final baseline = prepared.copy();
        await baseline.generations.eraseAllConfirmed();
        final count = baseline.faults.writes;
        expect(count, greaterThan(20));
        for (var at = 1; at <= count; at++) {
          final phone = prepared.copy();
          phone.faults
            ..failAt = at
            ..after = after;
          await expectLater(
            phone.generations.eraseAllConfirmed(),
            throwsA(isA<_Interrupted>()),
          );
          phone.faults.failAt = null;
          phone.restart();
          if (phone.files.files.containsKey('family.confirmedErase')) {
            // Simulate even the secure-store sweep that caused the original
            // unrecoverable journal: recovery needs only the durable inventory.
            phone.secrets.values.clear();
            expect(await phone.generations.recover(), isNull);
          } else {
            await phone.generations.eraseAllConfirmed();
          }
          expect(phone.files.files, isEmpty, reason: 'write $at');
          expect(phone.secrets.values, isEmpty, reason: 'write $at');
        }
      },
    );
  }

  test(
    'adopts in place; preparing and activating keep two complete contexts',
    () async {
      final phone = source.copy();
      final originalSecrets = Map.of(phone.secrets.values);
      final originalFiles = Map.of(phone.files.files);
      final prepared = await phone.prepare();
      final old = await phone.generations.open(_sourceId);
      final target = await phone.generations.open(_destinationId);
      expect(await phone.generations.activeSyncId(), _sourceId);
      expect(
        (await old.family.load())!.doc.canonicalJson(),
        prepared.family.doc.canonicalJson(),
      );
      expect(prepared.identity.deviceId, isNot('source-device'));
      expect(
        prepared.deviceKeys.publicKeys.signing,
        isNot((await old.deviceKeys.read())!.publicKeys.signing),
      );
      expect(
        prepared.deviceKeys.publicKeys.agreement,
        isNot((await old.deviceKeys.read())!.publicKeys.agreement),
      );
      expect((await target.family.readRegistry())!.records.single.seq, 1);
      expect((await target.family.readRegistry())!.vouches, isEmpty);
      expect((await target.family.readRegistry())!.revocations, isEmpty);
      expect(await target.family.readCommonKeys(), isNull);
      expect(await target.family.readScope('nora'), isNull);
      expect(await target.family.readOverflow('nora'), isEmpty);
      expect((await target.deviceKeys.readKeyring('list-1')).keys, isEmpty);
      expect(await target.family.readPendingV2(), isNull);
      expect(await target.family.readOrphans(), isEmpty);
      expect(await target.family.readLegacyV1(), isNull);
      expect(await target.family.readV1ProofKey(), isNull);
      expect(await target.family.readCommonFormatFloor(), 2);
      await phone.ready();
      await phone.generations.activate('operation-1');
      phone.restart();
      expect((await phone.family.readSyncV2())!.syncId, _destinationId);
      expect(
        (await phone.family.load())!.identity.node,
        prepared.identity.deviceId,
      );
      expect((await phone.keys.read())!.toJson(), prepared.deviceKeys.toJson());
      expect((await old.family.readSyncV2())!.syncId, _sourceId);
      expect(
        (await old.family.readScope('nora'))!
            .collections[Collections.gifts]!
            .length,
        1,
      );
      expect((await old.family.readOverflow('nora')).length, 1);
      expect((await old.deviceKeys.readKeyring('list-1')).keys.length, 1);
      expect((await old.family.readSlots()).all.length, 1);
      expect(await old.family.readRetainedBytes(_hash), [3, 4, 5]);
      expect(await old.family.readPendingV2(), {
        'checkpoint': 'exact',
        'credential': 'prepared',
      });
      for (final e in originalSecrets.entries) {
        expect(phone.secrets.values[e.key], e.value, reason: e.key);
      }
      for (final e in originalFiles.entries) {
        expect(phone.files.files[e.key], e.value, reason: e.key);
      }
      expect(
        phone.secrets.values['family.localKey'],
        isNot(
          phone.secrets.values['generation.$_destinationId.family.localKey'],
        ),
      );
    },
  );

  test(
    'CommonKeyState, retained references and format floor are per generation',
    () async {
      final phone = source.copy();
      await phone.prepare();
      await phone.ready();
      final old = await phone.generations.open(_sourceId);
      final target = await phone.generations.open(_destinationId);
      final oldJson = await old.family.readCommonKeys();
      final newState = CommonKeyState.fromJson(
        await target.family.readCommonKeys(),
      );
      expect(newState.lastKid, isNot(CommonKeyState.fromJson(oldJson).lastKid));
      await target.family.saveCommonKeys(
        newState.copyWith(revision: 999).toJson(),
      );
      await target.family.raiseCommonFormatFloor(3);
      phone.restart();
      expect(await old.family.readCommonKeys(), oldJson);
      final reopened = CommonKeyState.fromJson(
        await target.family.readCommonKeys(),
      );
      expect(reopened.revision, 999);
      expect(
        reopened.keyring.entries.single.references,
        contains('checkpoint:retained'),
      );
      expect(await old.family.readCommonFormatFloor(), 2);
      expect(await target.family.readCommonFormatFloor(), 3);
      await expectLater(
        old.family.clear(),
        throwsA(isA<FamilyStoreException>()),
      );
      await expectLater(
        old.deviceKeys.clear(),
        throwsA(isA<DeviceKeysStoreException>()),
      );
      await expectLater(
        old.family.clearCommonKeys(),
        throwsA(isA<FamilyStoreException>()),
      );
      await expectLater(
        old.deviceKeys.restore(await DeviceKeys.generate()),
        throwsA(isA<DeviceKeysStoreException>()),
      );
      expect(await old.family.readCommonKeys(), oldJson);
    },
  );

  test(
    'retries reuse the preparation and never overwrite a later checkpoint',
    () async {
      final phone = source.copy();
      final first = await phone.prepare();
      final target = await phone.generations.open(_destinationId);
      final later = first.family.doc.set(
        HlcClock(node: 'checkpoint'),
        'unknown-future',
        'later',
        {'value': 'base approved in person'},
      );
      await target.family.saveDoc(later);
      await phone.ready();
      phone.restart();
      final pending = (await phone.generations.journal.read())!;
      // Protocol/UI phase names must never replay the local preparation over
      // an exact checkpoint that has already been installed.
      await phone.generations.journal.save(pending.next(phase: 'preparation'));
      await phone.generations.recover();
      final again = await phone.prepare();
      expect(again.toJson(), first.toJson());
      expect(
        (await target.family.load())!.doc.canonicalJson(),
        later.canonicalJson(),
      );
      await expectLater(
        phone.generations.prepare(operationId: 'other-operation'),
        throwsStateError,
      );
      await expectLater(
        phone.generations.prepare(
          operationId: 'operation-1',
          destinationSyncId: 'CCCCCCCCCCCCCCCCCCCCCC',
        ),
        throwsStateError,
      );
    },
  );

  test(
    'old signed declarations have no trust path from the fresh root',
    () async {
      final phone = source.copy();
      final sourceKeys = (await phone.keys.read())!;
      final oldRecord = (await phone.family.readRegistry())!.records.single;
      final revokedKeys = await DeviceKeys.generate();
      final revoked = await DeviceRecord.create(
        keys: revokedKeys,
        listId: 'list-1',
        deviceId: 'revoked-old',
        personId: 'leo',
      );
      var registry = await (await phone.family.readRegistry())!.withRecord(
        revoked,
      );
      registry = await registry.withVouch(
        await Vouch.create(
          keys: sourceKeys,
          voucher: oldRecord,
          record: revoked,
        ),
      );
      final withRevocation = await registry.withRevocation(
        await Revocation.create(
          keys: sourceKeys,
          by: oldRecord,
          deviceId: revoked.deviceId,
        ),
      );
      await phone.family.saveRegistry(withRevocation);
      final prepared = await phone.prepare();
      final target = await phone.generations.open(_destinationId);
      final anchor = RegistryAnchor(
        deviceId: prepared.identity.deviceId,
        signingKey: prepared.deviceKeys.publicKeys.signing,
      );
      final merged = await (await target.family.readRegistry())!.merge(
        registry,
        anchor: anchor,
      );
      final view = await merged.viewFor(
        me: prepared.identity.deviceId,
        mySigningKey: prepared.deviceKeys.publicKeys.signing,
        livePeople: {'aritz', 'nora', 'leo'},
      );
      expect(view.member('revoked-old'), isNull);
      expect(view.member(oldRecord.deviceId), isNull);
      expect(view.linkedSigningKey('revoked-old'), isNull);
      expect(view.members, [prepared.identity.deviceId]);
    },
  );

  test(
    'copied ciphertext and a missing source key fail without replacing data',
    () async {
      final phone = source.copy();
      await phone.prepare();
      final target = await phone.generations.open(_destinationId);
      phone.files.files['generation.$_destinationId.family.doc'] =
          phone.files.files['family.doc']!;
      await expectLater(
        target.family.load(),
        throwsA(isA<FamilyStoreException>()),
      );
      final journal = (await phone.generations.journal.read())!.toJson();
      phone.secrets.values.remove('family.localKey');
      await expectLater(
        phone.generations.recover(),
        throwsA(isA<FamilyStoreException>()),
      );
      expect(phone.secrets.values.containsKey('family.localKey'), isFalse);
      expect((await phone.generations.journal.read())!.toJson(), journal);
    },
  );

  test('malformed directory never falls back to the old context', () async {
    final phone = source.copy();
    phone.secrets.values[generationDirectoryKey] = '{broken';
    await expectLater(phone.family.load(), throwsFormatException);
    await expectLater(phone.keys.read(), throwsFormatException);
  });

  test(
    'missing directory or journal cannot resurrect the old layout',
    () async {
      final complete = source.copy();
      await complete.prepare();
      final missingDirectory = complete.copy();
      missingDirectory.secrets.values.remove(generationDirectoryKey);
      await expectLater(missingDirectory.family.load(), throwsFormatException);
      await expectLater(
        missingDirectory.generations.recover(),
        throwsFormatException,
      );
      final missingJournal = complete.copy();
      missingJournal.files.files.remove('family.renewalJournal');
      await expectLater(
        missingJournal.generations.recover(),
        throwsFormatException,
      );
      await expectLater(missingJournal.prepare(), throwsFormatException);
      expect(
        missingJournal.secrets.values['family.localKey'],
        complete.secrets.values['family.localKey'],
      );
    },
  );

  test(
    'lost local key cannot be replaced by saving another document',
    () async {
      final phone = source.copy();
      await phone.prepare();
      final bytes = Uint8List.fromList(phone.files.files['family.doc']!);
      phone.secrets.values.remove('family.localKey');
      await expectLater(
        phone.family.saveDoc(FamilyDoc.empty('list-1')),
        throwsA(isA<FamilyStoreException>()),
      );
      expect(phone.files.files['family.doc'], bytes);
      expect(phone.secrets.values.containsKey('family.localKey'), isFalse);
    },
  );

  test(
    'old resets cannot replace a managed family or recreate device keys',
    () async {
      final phone = source.copy();
      await phone.prepare();
      final original = (await phone.family.load())!;
      final originalBytes = Uint8List.fromList(
        phone.files.files['family.doc']!,
      );
      await expectLater(
        phone.family.savePendingV2({'reset': true, 'sid': _destinationId}),
        throwsA(isA<FamilyStoreException>()),
      );
      expect(await phone.family.readPendingV2(), {
        'checkpoint': 'exact',
        'credential': 'prepared',
      });
      await expectLater(
        phone.family.saveFamily(
          StoredFamily(
            identity: original.identity,
            key: await FamilyKey.generate(),
            doc: FamilyDoc.empty('list-1'),
          ),
        ),
        throwsA(isA<FamilyStoreException>()),
      );
      expect(phone.files.files['family.doc'], originalBytes);
      phone.secrets.values.remove(kDeviceKeysSecret);
      await expectLater(
        phone.keys.create(),
        throwsA(isA<DeviceKeysStoreException>()),
      );
      expect(phone.secrets.values.containsKey(kDeviceKeysSecret), isFalse);
    },
  );

  test(
    'corrupted pending operations remain errors in a managed generation',
    () async {
      final phone = source.copy();
      await phone.prepare();
      for (final entry in <String, Future<Object?> Function()>{
        'family.syncV2State': phone.family.readSyncV2State,
        'family.pendingV2': phone.family.readPendingV2,
        'family.legacyV1': phone.family.readLegacyV1,
        'family.v1ProofKey': phone.family.readV1ProofKey,
      }.entries) {
        phone.secrets.values[entry.key] = '{broken';
        await expectLater(entry.value(), throwsA(isA<FamilyStoreException>()));
        expect(phone.secrets.values[entry.key], '{broken');
      }
    },
  );

  test(
    'activation rejects a common keyring from the source generation',
    () async {
      final phone = source.copy();
      await phone.prepare();
      await phone.ready();
      final old = await phone.generations.open(_sourceId);
      final target = await phone.generations.open(_destinationId);
      await target.family.saveCommonKeys(
        Map<String, Object?>.from((await old.family.readCommonKeys())! as Map),
      );
      await expectLater(
        phone.generations.activate('operation-1'),
        throwsStateError,
      );
      expect(await phone.generations.activeSyncId(), _sourceId);
    },
  );

  test(
    'replacing an abandoned plan preserves its prepared branch and keys',
    () async {
      final phone = source.copy();
      final abandoned = await phone.prepare();
      final firstContext = await phone.generations.open(_destinationId);
      await phone.generations.journal.archive('operation-1');
      final replacement = await phone.generations.prepare(
        operationId: 'operation-2',
        destinationSyncId: 'CCCCCCCCCCCCCCCCCCCCCC',
      );
      phone.restart();
      expect(await phone.generations.generationIds(), {
        _sourceId,
        _destinationId,
        'CCCCCCCCCCCCCCCCCCCCCC',
      });
      expect(
        (await firstContext.deviceKeys.read())!.toJson(),
        abandoned.deviceKeys.toJson(),
      );
      expect(
        (await firstContext.family.load())!.doc.canonicalJson(),
        abandoned.family.doc.canonicalJson(),
      );
      expect(
        replacement.deviceKeys.toJson(),
        isNot(abandoned.deviceKeys.toJson()),
      );
      expect(
        (await phone.generations.journal.readArchives()).single.data.keys,
        ['digest'],
      );
    },
  );

  test(
    'activation requires publication and a complete durable destination',
    () async {
      final phone = source.copy();
      await phone.prepare();
      await expectLater(
        phone.generations.activate('operation-1'),
        throwsStateError,
      );
      final pending = (await phone.generations.journal.read())!;
      await phone.generations.journal.save(
        pending.next(
          phase: 'moving',
          data: {...pending.data, 'destinationReady': true},
        ),
      );
      await expectLater(
        phone.generations.activate('operation-1'),
        throwsStateError,
      );
      expect(await phone.generations.activeSyncId(), _sourceId);
    },
  );

  test('replacement keeps the remote operation and original source after activation', () async {
    final phone = source.copy();
    final abandoned = await phone.prepare();
    await phone.ready();
    await phone.generations.activate('operation-1');
    final before = (await phone.generations.journal.read())!;
    await phone.generations.journal.save(
      before.next(
        phase: before.phase,
        data: {
          ...before.data,
          'operationContext': {'sourceVersionFloor': 17},
          'privateSalt': 'persisted-private-salt',
        },
      ),
    );
    final replacement = await phone.generations.prepareReplacement(
      operationId: 'operation-1',
      destinationSyncId: 'CCCCCCCCCCCCCCCCCCCCCC',
    );
    phone.restart();
    final journal = (await phone.generations.recover())!;
    expect(journal.operationId, 'operation-1');
    expect(journal.sourceSyncId, _sourceId);
    expect(journal.destinationSyncId, replacement.identity.syncId);
    expect(journal.data['previousDestinations'], [_destinationId]);
    expect(journal.data['destinationReady'], isNull);
    expect(journal.data['operationContext'], {'sourceVersionFloor': 17});
    expect(
      ((journal.data['previousPreparations'] as Map)[_destinationId]
          as Map)['privateSalt'],
      'persisted-private-salt',
    );
    expect(
      (await phone.generations.open(_destinationId)).deviceKeys
          .read()
          .then((k) => k!.toJson()),
      completion(abandoned.deviceKeys.toJson()),
    );
    expect(
      (await phone.generations.prepareReplacement(
        operationId: 'operation-1',
        destinationSyncId: replacement.identity.syncId,
      )).toJson(),
      replacement.toJson(),
    );
  });

  for (final after in [false, true]) {
    test(
      'replacement recovers every interruption (${after ? 'after' : 'before'} each write)',
      () async {
        final original = source.copy();
        await original.prepare();
        final baseline = original.copy();
        await baseline.generations.prepareReplacement(
          operationId: 'operation-1',
          destinationSyncId: 'CCCCCCCCCCCCCCCCCCCCCC',
        );
        for (var at = 1; at <= baseline.faults.writes; at++) {
          final phone = original.copy();
          phone.faults
            ..failAt = at
            ..after = after;
          await expectLater(
            phone.generations.prepareReplacement(
              operationId: 'operation-1',
              destinationSyncId: 'CCCCCCCCCCCCCCCCCCCCCC',
            ),
            throwsA(isA<_Interrupted>()),
            reason: 'write $at',
          );
          phone.faults.failAt = null;
          phone.restart();
          await phone.generations.recover();
          final committed = (await phone.generations.journal.read())!;
          final saved = committed.destinationSyncId == 'CCCCCCCCCCCCCCCCCCCCCC'
              ? committed.data['preparedGeneration']
              : null;
          final replacement = await phone.generations.prepareReplacement(
            operationId: 'operation-1',
            destinationSyncId: 'CCCCCCCCCCCCCCCCCCCCCC',
          );
          if (saved != null) expect(replacement.toJson(), saved);
          expect(
            (await phone.generations.journal.read())!.sourceSyncId,
            _sourceId,
          );
          expect(
            await (await phone.generations.open(_sourceId)).family.load(),
            isNotNull,
          );
          expect(
            await (await phone.generations.open(_destinationId)).deviceKeys
                .read(),
            isNotNull,
          );
        }
      },
    );
  }

  test(
    'activation invalidates stale unpinned document writers until reload',
    () async {
      final phone = source.copy();
      final old = (await phone.family.load())!;
      await phone.prepare();
      final pinned = await phone.generations.open(_sourceId);
      await phone.ready();
      await phone.generations.activate('operation-1');
      final before = Uint8List.fromList(
        phone.files.files['generation.$_destinationId.family.doc']!,
      );
      await expectLater(phone.family.saveDoc(old.doc), throwsStateError);
      expect(
        phone.files.files['generation.$_destinationId.family.doc'],
        before,
      );
      await pinned.family.saveDoc(old.doc);
      final fresh = (await phone.family.load())!;
      await phone.family.saveDoc(fresh.doc);
    },
  );

  for (final damage in [
    'directory',
    'missing-directory',
    'truncated-directory',
    'scope-index',
    'retained-index',
    'erase-inventory',
  ]) {
    test(
      'confirmed erase tolerates $damage and deletes unindexed generation files',
      () async {
        final phone = source.copy();
        await phone.prepare();
        phone.files.files['generation.$_destinationId.family.scope.orphan'] =
            Uint8List.fromList([1, 2]);
        phone.files.files['device.orphan'] = Uint8List.fromList([3]);
        phone.files.files['unrelated'] = Uint8List.fromList([4]);
        switch (damage) {
          case 'directory':
            phone.secrets.values[generationDirectoryKey] = 'damaged';
          case 'missing-directory':
            phone.secrets.values.remove(generationDirectoryKey);
          case 'truncated-directory':
            final directory = (jsonDecode(
              phone.secrets.values[generationDirectoryKey]!,
            ) as Map);
            (directory['entries'] as Map).remove(_destinationId);
            phone.secrets.values[generationDirectoryKey] = jsonEncode(
              directory,
            );
          case 'scope-index':
            phone.secrets.values['family.scopePeople'] = 'damaged';
          case 'retained-index':
            phone.files.files['family.retainedcommons'] = Uint8List.fromList([
              0,
            ]);
          case 'erase-inventory':
            phone.files.files['family.confirmedErase'] = Uint8List.fromList([
              0,
            ]);
        }
        phone.restart();
        await phone.generations.eraseAllConfirmed();
        expect(phone.secrets.values.keys, isEmpty);
        expect(phone.files.files.keys, ['unrelated']);
        phone.restart();
        expect(await phone.generations.recover(), isNull);
      },
    );
  }

  for (final after in [false, true]) {
    test(
      'damaged confirmed erase recovers across every write (${after ? 'after' : 'before'})',
      () async {
        final prepared = source.copy();
        await prepared.prepare();
        prepared.secrets.values[generationDirectoryKey] = 'damaged';
        final baseline = prepared.copy();
        await baseline.generations.eraseAllConfirmed();
        for (var at = 1; at <= baseline.faults.writes; at++) {
          final phone = prepared.copy();
          phone.faults
            ..failAt = at
            ..after = after;
          await expectLater(
            phone.generations.eraseAllConfirmed(),
            throwsA(isA<_Interrupted>()),
            reason: 'write $at',
          );
          phone.faults.failAt = null;
          phone.restart();
          if (phone.files.files.containsKey('family.confirmedErase')) {
            await phone.generations.recover();
          } else {
            await phone.generations.eraseAllConfirmed();
          }
          expect(phone.secrets.values, isEmpty);
          expect(phone.files.files, isEmpty);
        }
      },
    );
  }

  test('simultaneous preparations share one durable identity', () async {
    final phone = source.copy();
    final other = GenerationStore(secrets: phone.secrets, files: phone.files);
    final results = await Future.wait([
      phone.prepare(),
      other.prepare(
        operationId: 'operation-1',
        destinationSyncId: _destinationId,
      ),
    ]);
    expect(results[0].toJson(), results[1].toJson());
  });

  test(
    'an unfinished legacy installation is recovered before adoption',
    () async {
      final phone = source.copy();
      await phone.family.savePendingV2({'reset': true, 'sid': _destinationId});
      await expectLater(phone.prepare(), throwsStateError);
      expect(phone.secrets.values.containsKey(generationDirectoryKey), isFalse);
      expect(await phone.generations.journal.read(), isNull);
    },
  );

  for (final after in [false, true]) {
    test(
      'preparation recovers every storage interruption (${after ? 'after' : 'before'} each write)',
      () async {
        final baseline = source.copy();
        await baseline.prepare();
        final count = baseline.faults.writes;
        expect(count, greaterThan(10));
        for (var at = 1; at <= count; at++) {
          final phone = source.copy();
          phone.faults
            ..failAt = at
            ..after = after;
          await expectLater(
            phone.prepare(),
            throwsA(isA<_Interrupted>()),
            reason: 'write $at',
          );
          phone.faults.failAt = null;
          final durable = await phone.generations.journal.read();
          phone.restart();
          final prepared = await phone.prepare();
          if (durable != null) {
            expect(
              prepared.toJson(),
              durable.data['preparedGeneration'],
              reason: 'write $at',
            );
          }
          expect(await phone.generations.activeSyncId(), _sourceId);
          final old = await phone.generations.open(_sourceId);
          final target = await phone.generations.open(_destinationId);
          expect(
            (await target.deviceKeys.read())!.toJson(),
            prepared.deviceKeys.toJson(),
          );
          expect(
            (await target.family.load())!.doc.canonicalJson(),
            prepared.family.doc.canonicalJson(),
          );
          expect(
            (await old.family.readScope('nora'))!
                .collections[Collections.gifts],
            isNotEmpty,
          );
          expect(await old.family.readRetainedBytes(_hash), [3, 4, 5]);
        }
      },
    );

    test(
      'active pointer recovers every interruption (${after ? 'after' : 'before'} each write)',
      () async {
        final ready = source.copy();
        await ready.prepare();
        await ready.ready();
        final baseline = ready.copy();
        await baseline.generations.activate('operation-1');
        final count = baseline.faults.writes;
        expect(count, 2);
        for (var at = 1; at <= count; at++) {
          final phone = ready.copy();
          phone.faults
            ..failAt = at
            ..after = after;
          await expectLater(
            phone.generations.activate('operation-1'),
            throwsA(isA<_Interrupted>()),
          );
          phone.faults.failAt = null;
          phone.restart();
          await phone.generations.recover();
          await phone.generations.activate('operation-1');
          await phone.generations.recover();
          expect((await phone.family.readSyncV2())!.syncId, _destinationId);
          final old = await phone.generations.open(_sourceId);
          expect(await old.family.readRetainedBytes(_hash), [3, 4, 5]);
          expect(
            (await old.deviceKeys.read())!.toJson(),
            (await source.keys.read())!.toJson(),
          );
        }
      },
    );
  }

  test('retirement archive preserves journal and generation secrets', () async {
    final phone = source.copy();
    await phone.prepare();
    await phone.ready();
    await phone.generations.activate('operation-1');
    final pending = (await phone.generations.journal.read())!;
    await phone.generations.journal.save(
      pending.next(
        phase: 'retired',
        data: {
          ...pending.data,
          'pendingRecovery': ['absent-phone'],
          'checkpoint': {
            'common': 'exact bytes',
            'keys': await phone.family.readCommonKeys(),
          },
        },
      ),
    );
    await phone.generations.journal.archive('operation-1');
    await phone.generations.journal.archive('operation-1');
    phone.restart();
    expect(await phone.generations.recover(), isNull);
    final archived = (await phone.generations.journal.readArchives()).single;
    expect(archived.data.keys, ['digest']);
    expect(archived.data['digest'], matches(RegExp(r'^[a-f0-9]{64}$')));
    expect(await phone.generations.generationIds(), {
      _sourceId,
      _destinationId,
    });
    final old = await phone.generations.open(_sourceId);
    expect((await old.deviceKeys.readKeyring('list-1')).keys.length, 1);
    expect(await old.family.readRetainedBytes(_hash), [3, 4, 5]);
    final ciphertext = latin1.decode(
      phone.files.files['family.renewalJournal']!,
    );
    expect(ciphertext, isNot(contains('preparedGeneration')));
    expect(
      ciphertext,
      isNot(contains(jsonEncode((await source.keys.read())!.toJson()))),
    );
  });
}
