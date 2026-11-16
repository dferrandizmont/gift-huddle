import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_candidate.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/family_key_bundle.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/key_bundle.dart';
import 'package:regalos/core/sync/pairing_v2.dart';
import 'package:regalos/core/sync/recovery.dart';
import 'package:regalos/core/sync/recovery_locator.dart';

import 'family_key_harness.dart';
import 'protected_harness.dart';

Uint8List hex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);

Map<String, Object?> clone(Object? value) =>
    Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);

void main() {
  final vector = jsonDecode(
    File('../docs/adr/0007-vector-recuperacion.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final code = RecoveryCode(hex(vector['entropyHex'] as String));
  final salt = hex(vector['saltHex'] as String);
  final nonce = hex(vector['nonceHex'] as String);
  final vectorBytes = decodeBase64Url(vector['capsule'] as String);
  final key = hex(vector['argon2KeyHex'] as String);
  final fails = throwsA(isA<RecoveryException>());
  late RecoveryCapsulePayload payload;

  setUpAll(() async {
    payload = await RecoveryCapsulePayload.fromJson(vector['payload']);
  });

  // Produce authenticated malformed inputs without deriving a key repeatedly
  // during construction. The reader must still enforce every bound/schema.
  Future<Uint8List> authenticated(List<int> compressed) async {
    final h = peekRecoveryCapsule(vectorBytes);
    final aad = vectorBytes.sublist(0, h.aadEnd);
    final box = await AesGcm.with256bits().encrypt(
      compressed,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: aad,
    );
    return Uint8List.fromList([
      ...aad,
      ...nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  Uint8List changeHeader(void Function(Map<String, Object?>) change) {
    final h = peekRecoveryCapsule(vectorBytes);
    final j = clone(vector['header']);
    change(j);
    final header = utf8.encode(canonicalJsonOf(j));
    return Uint8List.fromList([
      0x47,
      0x48,
      0x52,
      2,
      header.length >> 8,
      header.length & 255,
      ...header,
      ...vectorBytes.sublist(h.aadEnd),
    ]);
  }

  test('fixed HKDF, verifier and independent Argon2id vector', () async {
    final locator = await deriveRecoveryLocator(code);
    expect(locator.recoveryId, vector['recoveryId']);
    expect(locator.readCap, vector['readCap']);
    expect(locator.readVerifier, vector['readVerifier']);
    final words = RecoveryWordlist.parse(
      File(kRecoveryWordlistAsset).readAsStringSync(),
    );
    expect(code.toWords(words).join(' '), vector['words']);
    expect(await deriveRecoveryCapsuleKey(code, salt), key);
    final legacy = await deriveRecoveryKey(
      code,
      salt,
      RecoveryKdfParams.standard,
    );
    expect(legacy, isNot(key));
    expect({
      locator.recoveryId,
      locator.readCap,
      encodeBase64Url(key),
      encodeBase64Url(legacy),
    }, hasLength(4));
    expect(locator.toString(), isNot(contains(locator.readCap)));
    expect(() => recoveryReadVerifier('${locator.readCap}='), fails);
    expect(() => recoveryReadVerifier(locator.readCap.substring(1)), fails);
  });

  test(
    'independent binary/AAD/AES vector opens and HTTP JSON roundtrips',
    () async {
      final h = peekRecoveryCapsule(vectorBytes);
      expect(vectorBytes.sublist(0, h.aadEnd), hex(vector['aadHex'] as String));
      expect(
        vectorBytes.sublist(h.aadEnd + 12),
        hex(vector['ciphertextAndTagHex'] as String),
      );
      final got = await openRecoveryCapsule(
        vectorBytes,
        code,
        expectedRevision: 1,
      );
      expect(got.toJson(), vector['payload']);
      expect(got.commonKeys.keyring.entries, hasLength(2));
      for (final candidate in got.commonKeys.keyring.candidates) {
        expect(
          await candidate.verifyCreator(got.deviceKeys.publicKeys.signing),
          isTrue,
        );
      }
      final json = RecoveryCapsule(vectorBytes).toJson();
      expect(RecoveryCapsule.fromJson(json).bytes, vectorBytes);
      for (final field in json.keys) {
        final bad = {...json}..remove(field);
        expect(() => RecoveryCapsule.fromJson(bad), fails, reason: field);
      }
      for (final entry in {
        'v': 3,
        'recoveryId': 'x',
        'revision': 2,
        'capsule': '${json['capsule']}=',
      }.entries) {
        expect(
          () => RecoveryCapsule.fromJson({...json, entry.key: entry.value}),
          fails,
          reason: entry.key,
        );
      }
    },
  );

  test(
    'Dart sealer preserves canonical plaintext; random writes differ',
    () async {
      final fixed = await sealRecoveryCapsuleForTesting(
        payload,
        code,
        revision: 1,
        salt: salt,
        nonce: nonce,
      );
      final h = peekRecoveryCapsule(fixed);
      expect(fixed.sublist(0, h.aadEnd), hex(vector['aadHex'] as String));
      final compressed = await AesGcm.with256bits().decrypt(
        SecretBox(
          fixed.sublist(h.aadEnd + 12, fixed.length - 16),
          nonce: nonce,
          mac: Mac(fixed.sublist(fixed.length - 16)),
        ),
        secretKey: SecretKey(key),
        aad: fixed.sublist(0, h.aadEnd),
      );
      expect(
        Inflate(compressed).getBytes(),
        hex(vector['plaintextHex'] as String),
      );
      expect(
        (await openRecoveryCapsule(fixed, code, expectedRevision: 1)).toJson(),
        payload.toJson(),
      );
      final random1 = await sealRecoveryCapsule(payload, code, revision: 2);
      final random2 = await sealRecoveryCapsule(payload, code, revision: 2);
      expect(random1, isNot(random2));
      expect(
        peekRecoveryCapsule(random1).salt,
        isNot(peekRecoveryCapsule(random2).salt),
      );
    },
  );

  test('wrong code and replayed revision fail', () async {
    await expectLater(
      openRecoveryCapsule(
        vectorBytes,
        RecoveryCode(List.filled(32, 99)),
        expectedRevision: 1,
      ),
      fails,
    );
    await expectLater(
      openRecoveryCapsule(vectorBytes, code, expectedRevision: 2),
      fails,
    );
    await expectLater(
      openRecoveryCapsule(vectorBytes, code, expectedRevision: 0),
      fails,
    );
  });

  test('closed resource constants and revision range', () async {
    expect(kRecoveryCapsuleMaxBytes, 1048576);
    expect(kRecoveryCapsuleMaxPlaintextBytes, 4194304);
    expect(kRecoveryMaxActivePerIdentity, 1);
    expect(kRecoveryMaxActivePerList, 4);
    expect(kRecoveryMaxStoredBytes, 4194304);
    expect(kRecoveryMaxTemporaryBytes, 1048576);
    expect(kRecoveryMaxHttpBodyBytes, 1400832);
    expect(kRecoveryMaxControlBodyBytes, 4096);
    expect(kRecoveryMaxLifetimeIds, 256);
    expect(kRecoveryMaxReceipts, 512);
    expect(kRecoveryMaxRetiredVerifiers, 256);
    expect(kRecoveryReadsPerMinute, 30);
    expect(kRecoveryMutationsPerMinute, 6);
    expect(kRecoveryWritesPerDay, 24);
    for (final revision in [0, -1, kRecoveryMaxRevision + 1]) {
      await expectLater(
        sealRecoveryCapsule(payload, code, revision: revision),
        fails,
      );
    }
  });

  test('dated v1 proof survives encryption without renewing its age', () async {
    final original = payload.transition.v1Proof!;
    expect(original.sinceMillis, 1760000000000);
    expect(original.key.toBase64Url(), isNot(payload.familyKey.toBase64Url()));
    final restored = await openRecoveryCapsule(
      await sealRecoveryCapsule(payload, code, revision: 2),
      code,
      expectedRevision: 2,
    );
    expect(restored.transition.toJson(), payload.transition.toJson());
    expect(restored.transition.v1Proof!.sinceMillis, original.sinceMillis);
    final absent = clone(payload.toJson());
    (absent['transition'] as Map)['v1Proof'] = null;
    expect(
      (await RecoveryCapsulePayload.fromJson(absent)).transition.v1Proof,
      isNull,
    );
  });

  test('every transition journal blocks sealing until resolved', () async {
    for (final field in payload.transition.toJson().keys) {
      final missing = clone(payload.toJson());
      (missing['transition'] as Map).remove(field);
      await expectLater(
        RecoveryCapsulePayload.fromJson(missing),
        fails,
        reason: field,
      );
      if (field == 'v' || field == 'v1Proof') continue;
      final j = clone(payload.toJson());
      (j['transition'] as Map)[field] = true;
      final pending = await RecoveryCapsulePayload.fromJson(j);
      expect(pending.transition.blocksPublication, isTrue, reason: field);
      await expectLater(
        sealRecoveryCapsule(pending, code, revision: 2),
        fails,
        reason: field,
      );
    }
    expect(payload.transition.blocksPublication, isFalse);
  });

  test(
    'v1 proof and transition schemas reject corruption and future versions',
    () async {
      final proof = payload.transition.v1Proof!.toJson();
      for (final field in proof.keys) {
        final j = clone(payload.toJson());
        ((j['transition'] as Map)['v1Proof'] as Map).remove(field);
        await expectLater(
          RecoveryCapsulePayload.fromJson(j),
          fails,
          reason: field,
        );
      }
      for (final entry in {
        'v': 2,
        'listId': 'other-list',
        'key': '${proof['key']}=',
        'since': -1,
        'extra': true,
      }.entries) {
        final j = clone(payload.toJson());
        ((j['transition'] as Map)['v1Proof'] as Map)[entry.key] = entry.value;
        await expectLater(
          RecoveryCapsulePayload.fromJson(j),
          fails,
          reason: entry.key,
        );
      }
      for (final value in [null, 'now', 1.5, kRecoveryMaxRevision + 1]) {
        final j = clone(payload.toJson());
        ((j['transition'] as Map)['v1Proof'] as Map)['since'] = value;
        await expectLater(RecoveryCapsulePayload.fromJson(j), fails);
      }
      final future = clone(payload.toJson());
      (future['transition'] as Map)['v'] = 2;
      await expectLater(RecoveryCapsulePayload.fromJson(future), fails);
    },
  );

  test(
    'nonempty authenticated outboxes survive with revision floors',
    () async {
      final family = await Family.create();
      final candidate = await candidateFor(family, family.view);
      final commonPacket = await FamilyKeyBundle.seal(
        sender: family.aritz.keys,
        view: family.view,
        syncId: kSync,
        toDevice: family.leo.id,
        candidate: candidate,
      );
      final surprisePacket = await KeyBundle.sealSurpriseKey(
        sender: family.aritz.keys,
        view: family.view,
        toDevice: family.leo.id,
        key: family.key,
      );
      final p = RecoveryCapsulePayload(
        transition: const RecoveryTransitionState(),
        identity: SyncIdentityV2(
          listId: kListId,
          deviceId: family.aritz.id,
          syncId: kSync,
        ),
        deviceName: 'Aritz',
        peerName: null,
        paired: true,
        personId: 'aritz',
        deviceKeys: family.aritz.keys,
        familyKey: payload.familyKey,
        registry: family.registry,
        commonKeys: RecoveryCommonKeys(
          keyring: FamilyKeyring.empty.withOwnCandidate(candidate),
          revision: 99,
          lastKid: candidate.kid,
        ),
        surpriseKeys: family.authorizedKeyring,
        commonKeysMarked: true,
        commonFormatFloor: 2,
        resume: RecoveryResumeState(
          versionFloor: 101,
          hlc: Hlc(millis: kFuture, counter: 7, node: family.aritz.id),
          slotRevisions: const {'nora': 123},
          minSlotRevisions: const {'nora/leo-phone': 111},
          pendingRevocations: const {'lost-phone'},
          revocationOperations: {'lost-phone': family.registry.toJson()},
          keyPackageOutbox: [surprisePacket.toJson()],
          commonKeyOutbox: [commonPacket.toJson()],
          commonFormatV2: true,
        ),
      );
      final got = await openRecoveryCapsule(
        await sealRecoveryCapsule(p, code, revision: 2),
        code,
        expectedRevision: 2,
      );
      expect(got.resume.toJson(), p.resume.toJson());
      expect(got.commonKeys.toJson(), p.commonKeys.toJson());
      final openedCommon =
          await FamilyKeyBundle.fromJson(got.resume.commonKeyOutbox.single)
              .open(
                mine: family.leo.keys,
                view: family.viewOf(family.leo),
                registry: family.registry,
                syncId: kSync,
              );
      expect(openedCommon.toJson(), candidate.toJson());
      final openedSurprise = await KeyBundle.fromJson(
        got.resume.keyPackageOutbox.single,
      ).openSurpriseKey(mine: family.leo.keys, view: family.viewOf(family.leo));
      expect(openedSurprise.toJson(), family.key.toJson());
      expect(
        await got.commonKeys.keyring.candidates.single.verifyCreator(
          family.aritz.keys.publicKeys.signing,
        ),
        isTrue,
      );
    },
  );

  test(
    'durable slot floors, pending work and migration flags are preserved',
    () async {
      final j = clone(payload.toJson());
      final resume = j['resume'] as Map;
      resume['pendingRevocations'] = ['leo-phone'];
      resume['pendingUnbackedRevocations'] = ['aritz-phone'];
      resume['revocationOperations'] = {'leo-phone': payload.registry.toJson()};
      final p = await RecoveryCapsulePayload.fromJson(j);
      final got = await openRecoveryCapsule(
        await sealRecoveryCapsule(p, code, revision: 2),
        code,
        expectedRevision: 2,
      );
      expect(got.resume.toJson(), resume);
      expect(got.resume.minSlotRevisions, {'leo/aritz-phone': 8});
      resume['commonMigration'] = true;
      final migrating = await RecoveryCapsulePayload.fromJson(j);
      expect(migrating.resume.commonMigration, isTrue);
      await expectLater(
        sealRecoveryCapsule(migrating, code, revision: 2),
        fails,
      );
      for (final field in ['keyPackageOutbox', 'commonKeyOutbox']) {
        final bad = clone(payload.toJson());
        (bad['resume'] as Map)[field] = [
          {'v': 99},
        ];
        await expectLater(RecoveryCapsulePayload.fromJson(bad), fails);
      }
    },
  );

  final headerChanges = <String, void Function(Map<String, Object?>)>{
    'kind': (j) => j['k'] = 'backup',
    'version': (j) => j['v'] = 3,
    'rid': (j) => j['rid'] = encodeBase64Url(List.filled(32, 9)),
    'revision': (j) => j['r'] = 2,
    'salt': (j) => j['s'] = encodeBase64Url(List.filled(16, 7)),
    'kdf': (j) => (j['kdf'] as Map)['m'] = 8,
    'extra': (j) => j['unknown'] = true,
  };
  for (final e in headerChanges.entries) {
    test('tampered header ${e.key} fails', () async {
      await expectLater(
        openRecoveryCapsule(
          changeHeader(e.value),
          code,
          expectedRevision: e.key == 'revision' ? 2 : 1,
        ),
        fails,
      );
    });
  }

  for (final field in [
    'magic',
    'version',
    'length',
    'nonce',
    'ciphertext',
    'tag',
  ]) {
    test('tampered binary $field fails', () async {
      final h = peekRecoveryCapsule(vectorBytes);
      final offsets = {
        'magic': 0,
        'version': 3,
        'length': 4,
        'nonce': h.aadEnd,
        'ciphertext': h.aadEnd + 12,
        'tag': vectorBytes.length - 1,
      };
      final bytes = Uint8List.fromList(vectorBytes);
      bytes[offsets[field]!] ^= 1;
      await expectLater(
        openRecoveryCapsule(bytes, code, expectedRevision: 1),
        fails,
      );
    });
  }

  test(
    'every payload field is required; damaged state never defaults',
    () async {
      for (final field in payload.toJson().keys) {
        final j = clone(payload.toJson())..remove(field);
        await expectLater(
          RecoveryCapsulePayload.fromJson(j),
          fails,
          reason: field,
        );
      }
      for (final field in payload.resume.toJson().keys) {
        final j = clone(payload.toJson());
        (j['resume'] as Map).remove(field);
        await expectLater(
          RecoveryCapsulePayload.fromJson(j),
          fails,
          reason: field,
        );
      }
    },
  );

  test(
    'future payload, identity, keyring and minimum format are refused',
    () async {
      final mutations = <void Function(Map<String, Object?>)>[
        (j) => j['v'] = 3,
        (j) => (j['identity'] as Map)['v'] = 3,
        (j) => ((j['commonKeys'] as Map)['keyring'] as Map)['v'] = 3,
        (j) => (j['surpriseKeys'] as Map)['v'] = 3,
        (j) => j['commonFormatFloor'] = 3,
        (j) => (j['anchor'] as Map)['deviceId'] = 'other-phone',
        (j) => j['personId'] = 'leo',
        (j) => (j['resume'] as Map)['versionFloor'] = -1,
        (j) => (j['resume'] as Map)['commonMigrationPut'] = true,
        (j) => (j['resume'] as Map)['hlc'] = 'broken',
        (j) =>
            (((j['registry'] as Map)['records'] as List).first as Map)['sig'] =
                encodeBase64Url(List.filled(64, 0)),
      ];
      for (var i = 0; i < mutations.length; i++) {
        final j = clone(payload.toJson());
        mutations[i](j);
        await expectLater(
          RecoveryCapsulePayload.fromJson(j),
          fails,
          reason: '$i',
        );
      }
      final future = clone(payload.toJson())..['v'] = 3;
      await expectLater(
        openRecoveryCapsule(
          await authenticated(
            Deflate(utf8.encode(canonicalJsonOf(future))).getBytes(),
          ),
          code,
          expectedRevision: 1,
        ),
        fails,
      );
    },
  );

  test(
    'own surprises removed in ALL epochs; historical keyrings survive',
    () async {
      final family = await Family.create();
      final first = await candidateFor(family, family.view, seed: 7);
      final second = await candidateFor(family, family.view, seed: 9);
      final ring = FamilyKeyring.empty
          .withOwnCandidate(first, historical: true)
          .withReference(first.kid, 'legacy')
          .withReceivedCandidate(
            second,
            from: family.leo.id,
            fromRecord: family.viewOf(family.leo).self.recordDigest,
            sealable: (_) => true,
          );
      final surprises = SurpriseKeyring([
        for (final person in ['aritz', 'nora', 'leo'])
          for (final epoch in [1, 2, 3])
            SurpriseKey(
              personId: person,
              epoch: epoch,
              bytes: List.filled(32, epoch),
              audience: [family.aritz.id],
            ),
      ]);
      final p = RecoveryCapsulePayload(
        transition: const RecoveryTransitionState(),
        identity: payload.identity,
        deviceName: payload.deviceName,
        peerName: null,
        paired: false,
        personId: 'nora',
        deviceKeys: payload.deviceKeys,
        familyKey: payload.familyKey,
        registry: payload.registry,
        commonKeys: RecoveryCommonKeys(
          keyring: ring,
          revision: 19,
          lastKid: second.kid,
        ),
        surpriseKeys: surprises,
        commonKeysMarked: true,
        commonFormatFloor: 1,
        resume: payload.resume,
      );
      expect(p.surpriseKeys.keys.where((k) => k.personId == 'nora'), isEmpty);
      final got = await openRecoveryCapsule(
        await sealRecoveryCapsule(p, code, revision: 3),
        code,
        expectedRevision: 3,
      );
      expect(got.commonKeys.toJson(), p.commonKeys.toJson());
      expect(got.commonKeys.keyring.entry(first.kid)!.historical, isTrue);
      expect(
        got.commonKeys.keyring.entry(first.kid)!.references,
        contains('legacy'),
      );
      expect(got.commonKeys.keyring.entry(second.kid)!.senders, hasLength(1));
      expect(got.surpriseKeys.keys, hasLength(6));
      final bad = clone(p.toJson())..['surpriseKeys'] = surprises.toJson();
      await expectLater(RecoveryCapsulePayload.fromJson(bad), fails);
    },
  );

  test(
    'size limits include binary/header and precede expensive work',
    () async {
      expect(
        () => peekRecoveryCapsule(Uint8List(kRecoveryCapsuleMaxBytes + 1)),
        fails,
      );
      final atLimit = Uint8List(kRecoveryCapsuleMaxBytes)
        ..setAll(0, vectorBytes);
      expect(peekRecoveryCapsule(atLimit).revision, 1);
      final hugeHeader = Uint8List.fromList(vectorBytes)
        ..[4] = 0x04
        ..[5] = 0x01;
      expect(() => peekRecoveryCapsule(hugeHeader), fails);
      final json = RecoveryCapsule(vectorBytes).toJson()
        ..['capsule'] = 'A' * ((kRecoveryCapsuleMaxBytes * 4 + 2) ~/ 3 + 1);
      expect(() => RecoveryCapsule.fromJson(json), fails);
      expect(() => deriveRecoveryCapsuleKey(code, List.filled(15, 0)), fails);
    },
  );

  test(
    '4 MiB exact plaintext accepted, next byte rejected; binary cap on seal',
    () async {
      final json = clone(payload.toJson())..['deviceName'] = '';
      final overhead = utf8.encode(canonicalJsonOf(json)).length;
      json['deviceName'] = 'A' * (kRecoveryCapsuleMaxPlaintextBytes - overhead);
      final big = await RecoveryCapsulePayload.fromJson(json);
      final bytes = await sealRecoveryCapsule(big, code, revision: 1);
      expect(
        (await openRecoveryCapsule(
          bytes,
          code,
          expectedRevision: 1,
        )).deviceName.length,
        kRecoveryCapsuleMaxPlaintextBytes - overhead,
      );
      json['deviceName'] = '${json['deviceName']}A';
      await expectLater(
        sealRecoveryCapsule(
          await RecoveryCapsulePayload.fromJson(json),
          code,
          revision: 1,
        ),
        fails,
      );
      final random = Random(777);
      json['deviceName'] = base64Encode(
        List.generate(1500000, (_) => random.nextInt(256)),
      );
      await expectLater(
        sealRecoveryCapsule(
          await RecoveryCapsulePayload.fromJson(json),
          code,
          revision: 1,
        ),
        fails,
      );
    },
  );

  test(
    'authenticated compression bomb and truncated deflate rejected',
    () async {
      final bomb = Deflate(
        List.filled(kRecoveryCapsuleMaxPlaintextBytes + 1, 65),
      ).getBytes();
      await expectLater(
        openRecoveryCapsule(
          await authenticated(bomb),
          code,
          expectedRevision: 1,
        ),
        fails,
      );
      final compressed = hex(vector['compressedHex'] as String);
      await expectLater(
        openRecoveryCapsule(
          await authenticated(compressed.sublist(0, 10)),
          code,
          expectedRevision: 1,
        ),
        fails,
      );
    },
  );

  test('authenticated noncanonical JSON is rejected', () async {
    final plain = utf8.encode(' ${canonicalJsonOf(payload.toJson())}');
    await expectLater(
      openRecoveryCapsule(
        await authenticated(Deflate(plain).getBytes()),
        code,
        expectedRevision: 1,
      ),
      fails,
    );
  });

  test('R-c/v1 and future binary are never read as a v2 capsule', () async {
    final v1 = Uint8List.fromList(vectorBytes)..[3] = 1;
    final future = Uint8List.fromList(vectorBytes)..[3] = 3;
    expect(() => peekRecoveryCapsule(v1), fails);
    expect(() => peekRecoveryCapsule(future), fails);
    expect(() => peekRecoveryKind(vectorBytes), fails);
    await expectLater(openRecovery(vectorBytes, code), fails);
    final oldPayload = {...payload.toJson(), 'v': 1, 'k': 'keys'};
    await expectLater(RecoveryCapsulePayload.fromJson(oldPayload), fails);
  });
}
