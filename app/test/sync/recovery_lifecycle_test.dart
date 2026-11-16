import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/recovery.dart';
import 'package:regalos/core/sync/recovery_locator.dart';
import 'package:regalos/features/family/data/recovery_store.dart';
import 'package:regalos/features/sync/application/recovery_engine.dart';
import 'package:regalos/features/sync/application/recovery_maintenance.dart';
import 'package:regalos/features/sync/application/sync_v2_engine.dart';
import 'package:regalos/features/sync/data/recovery_transport.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';
import 'package:regalos/features/sync/data/sync_transport_common.dart';

import 'recovery_audit_test.dart' show AuditWorker;
import 'recovery_engine_test.dart' show family, StoredPhone, sid;

void main() {
  late AuditWorker w;
  setUp(() => w = AuditWorker());

  Future<RecoveryMaintenance> maintenance(
    StoredPhone p, {
    DateTime Function()? now,
  }) async => RecoveryMaintenance(
    store: p.recovery,
    family: p.family,
    exporter: RecoveryExporter(p.generations, p.reader(w)),
    transport: w,
    auth: await p.auth(),
    now: now,
  );

  void workspaceEmpty(StoredPhone p) {
    expect(
      p.secrets.values.keys.where((k) => k.startsWith('recovery.read.')),
      isEmpty,
    );
    expect(
      p.files.files.keys.where((k) => k.startsWith('recovery.read.')),
      isEmpty,
    );
  }

  test('unconfirmed words survive restart without becoming ready or being shown twice', () async {
    final p = (await family(w, solo: true)).single;
    final code = RecoveryCode.generate();
    await (await p.maintenance(w)).create(code);
    expect(
      (await (await p.maintenance(w)).status()).readiness,
      RecoveryReadiness.confirmationPending,
    );
    final entropy = (await p.recovery.takeCodeDisplay(sid))!;
    final restarted = StoredPhone(secrets: p.secrets, files: p.files);
    expect(await restarted.recovery.takeCodeDisplay(sid), isNull);
    expect(
      (await (await restarted.maintenance(w)).status()).readiness,
      RecoveryReadiness.confirmationPending,
    );
    final replacement = RecoveryCode.generate();
    await (await restarted.maintenance(w)).rotate(replacement);
    final oldLocator = await deriveRecoveryLocator(code);
    expect(
      (await w.send(
        RecoveryRequest(
          'GET',
          '/v2/recoveries/${oldLocator.recoveryId}',
          headers: {'X-Recovery-Cap': oldLocator.readCap},
        ),
      )).status,
      isNot(200),
    );
    await expectLater(
      restarted.recovery.confirmCode(sid, entropy),
      throwsStateError,
    );
    final replacementEntropy = (await restarted.recovery.takeCodeDisplay(sid))!;
    await restarted.recovery.confirmCode(sid, replacementEntropy);
    expect(
      (await (await restarted.maintenance(w)).status()).readiness,
      RecoveryReadiness.prepared,
    );
    final installed = (await restarted.family.load())!;
    await restarted.family.saveIdentity(
      installed.identity.copyWith(deviceName: 'Nora'),
    );
    await (await restarted.maintenance(w)).maintain();
    expect(
      (await restarted.recovery.readMaterial(sid))!['wordsConfirmed'],
      isTrue,
    );
  });

  test(
    'legacy material without proof of checking is also unconfirmed',
    () async {
      final p = (await family(w, solo: true)).single;
      final m = await p.maintenance(w);
      await m.create(RecoveryCode.generate());
      await p.recovery.takeCodeDisplay(sid);
      final legacy = (await p.recovery.readMaterial(sid))!
        ..remove('wordsConfirmed');
      await p.recovery.finishMaintenance(sid, {'retired': true});
      await p.recovery.finishMaintenance(sid, legacy);
      final restarted = StoredPhone(secrets: p.secrets, files: p.files);
      expect(await restarted.recovery.hasCodeDisplay(sid), isFalse);
      expect(
        (await (await restarted.maintenance(w)).status()).readiness,
        RecoveryReadiness.confirmationPending,
      );
    },
  );

  test(
    'confirmation survives cancelling an update captured before the check',
    () async {
      final p = (await family(w, solo: true)).single;
      final m = await p.maintenance(w);
      await m.create(RecoveryCode.generate());
      final entropy = (await p.recovery.takeCodeDisplay(sid))!;
      await expectLater(
        p.recovery.confirmCode(sid, 'another-code'),
        throwsStateError,
      );
      final installed = (await p.family.load())!;
      await p.family.saveIdentity(
        installed.identity.copyWith(deviceName: 'Nora'),
      );
      w.offline = true;
      await expectLater(m.maintain(), throwsA(isA<SyncTransportException>()));
      await p.recovery.confirmCode(sid, entropy);
      w.offline = false;
      await m.cancel();
      expect((await p.recovery.readMaterial(sid))!['wordsConfirmed'], isTrue);
      await m.maintain();
      expect((await m.status()).readiness, RecoveryReadiness.prepared);
    },
  );

  test(
    'M-B cancelling creation returns to absent and permits another create',
    () async {
      final p = (await family(w, solo: true)).single;
      final m = await p.maintenance(w);
      await m.queueNewCode(RecoveryCode.generate(), rotate: false);
      await m.cancel();
      expect((await m.status()).readiness, RecoveryReadiness.absent);
      expect(await p.recovery.readFailure(sid), isNull);
      await m.create(RecoveryCode.generate());
      expect(
        (await m.status()).readiness,
        RecoveryReadiness.confirmationPending,
      );
    },
  );

  test(
    'M-B cancellation also clears a previously closed terminal failure',
    () async {
      final p = (await family(w, solo: true)).single;
      final m = await p.maintenance(w);
      await m.queueNewCode(RecoveryCode.generate(), rotate: false);
      await p.recovery.closeMaintenance(sid, 'recovery_limit');
      expect((await m.status()).readiness, RecoveryReadiness.needsAttention);
      await m.cancel();
      expect((await m.status()).readiness, RecoveryReadiness.absent);
      expect(await p.recovery.readFailure(sid), isNull);
    },
  );

  test('M-B cancelled rotation keeps the previous unconfirmed code', () async {
    final p = (await family(w, solo: true)).single;
    final m = await p.maintenance(w);
    final old = RecoveryCode.generate();
    await m.create(old);
    await p.recovery.takeCodeDisplay(sid);
    await m.queueNewCode(RecoveryCode.generate(), rotate: true);
    await m.cancel();
    expect((await m.status()).readiness, RecoveryReadiness.confirmationPending);
    expect(
      (await p.recovery.readMaterial(sid))!['entropy'],
      encodeBase64Url(old.entropy),
    );
    expect(await p.recovery.takeCodeDisplay(sid), isNull);
  });

  for (final savedPhase in ['commit', 'send', 'finish']) {
    test(
      'BAJA-1 cancelling ambiguous rotation in $savedPhase adopts active candidate',
      () async {
        final p = (await family(w, solo: true)).single;
        final m = await p.maintenance(w);
        final old = RecoveryCode.generate(),
            candidate = RecoveryCode.generate();
        await m.create(old);
        await p.recovery.takeCodeDisplay(sid);
        w.intercept = (r) async {
          if (!r.path.endsWith('/commit')) return null;
          expect((await w.recoveries.send(r)).status, 200);
          throw const SyncTransportException(
            SyncFailure.network,
            'lost commit response',
          );
        };
        await expectLater(
          m.rotate(candidate),
          throwsA(isA<SyncTransportException>()),
        );
        final record = (await p.recovery.readMaintenance(sid))!;
        expect((record['intent'] as Map)['phase'], 'commit');
        await p.recovery.advanceMaintenance(sid, record, {
          ...Map<String, Object?>.from(record['intent'] as Map),
          'phase': savedPhase,
        });
        var listed = false;
        w.intercept = (r) async {
          if (r.path == '/v2/lists/$sid/recoveries' && r.method == 'GET') {
            listed = true;
          }
          return null;
        };
        await m.cancel();
        expect(listed, isTrue);
        expect(
          (await p.recovery.readMaterial(sid))!['entropy'],
          encodeBase64Url(candidate.entropy),
        );
        expect(
          (await m.status()).readiness,
          RecoveryReadiness.confirmationPending,
        );
        expect(
          await p.recovery.takeCodeDisplay(sid),
          encodeBase64Url(candidate.entropy),
        );
        expect(await p.recovery.readMaintenance(sid), isNull);
      },
    );
  }

  test('BAJA-1 failed resolution keeps rotation durable; uncommitted cancellation keeps old code', () async {
    final p = (await family(w, solo: true)).single;
    final m = await p.maintenance(w);
    final old = RecoveryCode.generate();
    await m.create(old);
    w.intercept = (r) async =>
        r.path.endsWith('/commit') ? RecoveryResponse(503) : null;
    await expectLater(
      m.rotate(RecoveryCode.generate()),
      throwsA(isA<RecoveryTransportException>()),
    );
    final pending = await p.recovery.readMaintenance(sid);
    w.intercept = (r) async =>
        r.path == '/v2/lists/$sid/recoveries' ? RecoveryResponse(503) : null;
    await expectLater(m.cancel(), throwsA(isA<RecoveryTransportException>()));
    expect(await p.recovery.readMaintenance(sid), pending);
    w.intercept = null;
    await m.cancel();
    expect((await m.status()).readiness, RecoveryReadiness.confirmationPending);
    expect(
      (await p.recovery.readMaterial(sid))!['entropy'],
      encodeBase64Url(old.entropy),
    );
    expect(await p.recovery.takeCodeDisplay(sid), isNull);
  });

  for (final deleteApplied in [false, true]) {
    test(
      'N-1 cancelling ambiguous retirement reconciles DELETE (applied=$deleteApplied)',
      () async {
        final p = (await family(w, solo: true)).single;
        final m = await p.maintenance(w);
        await m.create(RecoveryCode.generate());
        final old = await p.recovery.readMaterial(sid);
        w.intercept = (r) async {
          if (r.method != 'DELETE') return null;
          if (deleteApplied) expect((await w.recoveries.send(r)).status, 204);
          throw const SyncTransportException(
            SyncFailure.network,
            'lost DELETE response',
          );
        };
        await expectLater(m.retire(), throwsA(isA<SyncTransportException>()));
        final restarted = StoredPhone(secrets: p.secrets, files: p.files);
        final resumed = await restarted.maintenance(w);
        final pending = await restarted.recovery.readMaintenance(sid);
        w.intercept = (r) async => r.path == '/v2/lists/$sid/recoveries'
            ? RecoveryResponse(503)
            : null;
        await expectLater(
          resumed.cancel(),
          throwsA(isA<RecoveryTransportException>()),
        );
        expect(await restarted.recovery.readMaintenance(sid), pending);
        expect(await restarted.recovery.readMaterial(sid), old);
        var listed = false;
        w.intercept = (r) async {
          expect(r.method, 'GET');
          if (r.path == '/v2/lists/$sid/recoveries') listed = true;
          return null;
        };
        await resumed.cancel();
        expect(listed, isTrue);
        expect(await restarted.recovery.readMaintenance(sid), isNull);
        expect(await restarted.recovery.readFailure(sid), isNull);
        expect(
          (await resumed.status()).readiness,
          deleteApplied
              ? RecoveryReadiness.absent
              : RecoveryReadiness.confirmationPending,
        );
        if (deleteApplied) {
          expect(
            (await restarted.recovery.readMaterial(sid))!['retired'],
            isTrue,
          );
          expect(await restarted.recovery.takeCodeDisplay(sid), isNull);
        } else {
          expect(await restarted.recovery.readMaterial(sid), old);
        }
      },
    );
  }

  test(
    'M1 material uploads respect a durable minimum interval across restart',
    () async {
      final p = (await family(w, solo: true)).single;
      var now = DateTime.utc(2026, 11, 15, 10);
      final code = RecoveryCode.generate();
      await (await maintenance(p, now: () => now)).create(code);
      expect(w.puts, 1);
      final stored = (await p.family.load())!;
      await p.family.saveIdentity(stored.identity.copyWith(deviceName: 'Nora'));
      final restarted = StoredPhone(secrets: p.secrets, files: p.files);
      await (await maintenance(restarted, now: () => now)).maintain();
      expect(w.puts, 1);
      expect(await restarted.family.recoveryDirty(), isNotNull);
      now = now.add(const Duration(hours: 4));
      await (await maintenance(restarted, now: () => now)).maintain();
      expect(w.puts, 2);
      expect(await restarted.family.recoveryDirty(), isNull);
    },
  );

  test('M1 fingerprint ignores document and writer counters', () async {
    final p = (await family(w, solo: true)).single;
    final exporter = RecoveryExporter(p.generations, p.reader(w));
    final before = await exporter.capture(sid);
    await p.gift('leo', 'ordinary', 'Gift');
    await p.sync(w);
    final after = await exporter.capture(sid);
    expect(after.resume.versionFloor, greaterThan(before.resume.versionFloor));
    expect(after.resume.hlc, greaterThan(before.resume.hlc));
    expect(after.commonKeys.revision, greaterThan(before.commonKeys.revision));
    expect(recoveryMaterialSnapshot(after), recoveryMaterialSnapshot(before));
  });

  test(
    'A3 M5 missing rotation candidate preserves the old active entropy',
    () async {
      final p = (await family(w, solo: true)).single;
      final old = RecoveryCode.generate(), candidate = RecoveryCode.generate();
      await (await p.maintenance(w)).create(old);
      final locator = await deriveRecoveryLocator(candidate);
      w.intercept = (r) async =>
          r.method == 'GET' && r.path == '/v2/recoveries/${locator.recoveryId}'
          ? RecoveryResponse(404, body: {'error': 'not_found'})
          : null;
      await (await p.maintenance(w)).rotate(candidate);
      expect(await p.recovery.readMaintenance(sid), isNull);
      expect(
        (await p.recovery.readMaterial(sid))!['entropy'],
        encodeBase64Url(old.entropy),
      );
      expect(await p.recovery.takeCodeDisplay(sid), isNull);
    },
  );

  test(
    'M3 a transferred namespace can recover while old handles remain read-only',
    () async {
      final p = (await family(w, solo: true)).single;
      final code = RecoveryCode.generate();
      await (await p.maintenance(w)).create(code);
      final old = await p.generations.open(sid);
      final other = StoredPhone();
      expect((await other.restorer(w).start(code)).phase, RecoveryPhase.active);
      await expectLater(p.sync(w), throwsA(isA<V2TransferredException>()));
      expect(await p.recovery.isTransferred(sid), isTrue);
      expect((await p.restorer(w).start(code)).phase, RecoveryPhase.active);
      expect(await p.recovery.isTransferred(sid), isFalse);
      await expectLater(
        old.family.saveDoc((await old.family.load())!.doc),
        throwsStateError,
      );
      await p.sync(w);
    },
  );

  test('M3 concurrent claim during real reader validation reopens capsule and succeeds', () async {
    final owner = (await family(w, solo: true)).single;
    final code = RecoveryCode.generate();
    await (await owner.maintenance(w)).create(code);
    final a = StoredPhone(), b = StoredPhone();
    var raced = false;
    w.beforeSyncRequest = (method, uri) async {
      if (method != 'GET' || uri.path != '/v2/lists/$sid') return;
      w.beforeSyncRequest = null;
      raced = true;
      expect((await b.restorer(w).start(code)).phase, RecoveryPhase.active);
    };
    expect((await a.restorer(w).start(code)).phase, RecoveryPhase.active);
    expect(raced, isTrue);
    expect(await a.recovery.isTransferred(sid), isFalse);
    expect((await a.restorer(w).start(code)).phase, RecoveryPhase.active);
    workspaceEmpty(a);
    workspaceEmpty(b);
  });

  test(
    'A3 rotation keeps old entropy until commit and withholds candidate words',
    () async {
      final p = (await family(w, solo: true)).single;
      final old = RecoveryCode.generate(), next = RecoveryCode.generate();
      await (await p.maintenance(w)).create(old);
      await p.recovery.takeCodeDisplay(sid);
      w.intercept = (r) async => r.path.endsWith('/commit')
          ? RecoveryResponse(503, body: {'error': 'unavailable'})
          : null;
      await expectLater(
        (await p.maintenance(w)).rotate(next),
        throwsA(isA<RecoveryTransportException>()),
      );
      expect(
        (await p.recovery.readMaterial(sid))!['entropy'],
        encodeBase64Url(old.entropy),
      );
      expect(await p.recovery.takeCodeDisplay(sid), isNull);
      w.intercept = null;
      await (await p.maintenance(w)).resume();
      expect(
        await p.recovery.takeCodeDisplay(sid),
        encodeBase64Url(next.entropy),
      );
      expect(await p.recovery.takeCodeDisplay(sid), isNull);
    },
  );

  for (final cause in [
    'recovery_rotation_expired',
    'recovery_rotation_cancelled',
    'recovery_retired',
    'not_found',
    'recovery_limit',
    'recovery_history_full',
    'recovery_exists',
    'recovery_operation_conflict',
    'invalid_recovery',
    'recovery_too_large',
    'unauthorized',
  ]) {
    test('M5 terminal $cause closes intention and allows a new code', () async {
      final p = (await family(w, solo: true)).single;
      final old = RecoveryCode.generate();
      await (await p.maintenance(w)).create(old);
      final retired = cause == 'recovery_retired' || cause == 'not_found';
      if (retired) {
        final locator = await deriveRecoveryLocator(old);
        final deleted = await w.send(
          RecoveryRequest(
            'DELETE',
            '/v2/lists/$sid/recoveries/${locator.recoveryId}',
            headers: recoveryAuthHeaders(await p.auth(), 1),
          ),
        );
        expect(deleted.status, 204);
      }
      w.intercept = (r) async => r.path.endsWith('/rotation')
          ? RecoveryResponse(
              cause == 'not_found' ? 404 : 409,
              body: {'error': cause},
            )
          : null;
      await (await p.maintenance(w)).rotate(RecoveryCode.generate());
      expect(await p.recovery.readMaintenance(sid), isNull);
      final material = (await p.recovery.readMaterial(sid))!;
      if (retired) {
        expect(material['retired'], isTrue);
      } else {
        expect(material['entropy'], encodeBase64Url(old.entropy));
        final locator = await deriveRecoveryLocator(old);
        expect(
          (await w.send(
            RecoveryRequest(
              'GET',
              '/v2/recoveries/${locator.recoveryId}',
              headers: {'X-Recovery-Cap': locator.readCap},
            ),
          )).status,
          200,
        );
      }
      expect(await p.recovery.takeCodeDisplay(sid), isNull);
      w.intercept = null;
      await (await p.maintenance(w))
          .queueNewCode(RecoveryCode.generate(), rotate: !retired);
      await (await p.maintenance(w)).resume();
      expect(
        (await (await p.maintenance(w)).status()).readiness,
        RecoveryReadiness.confirmationPending,
      );
      expect(await p.recovery.takeCodeDisplay(sid), isNotNull);
    });
  }

  test(
    'MEDIA-4 ambiguous create is listed and deleted before closing',
    () async {
      final p = (await family(w, solo: true)).single;
      final code = RecoveryCode.generate();
      final calls = <String>[];
      w.intercept = (r) async {
        calls.add('${r.method} ${r.path}');
        if (r.method != 'PUT') return null;
        expect((await w.recoveries.send(r)).status, 201);
        return RecoveryResponse(
          409,
          body: {'error': 'recovery_operation_conflict'},
        );
      };
      await (await p.maintenance(w)).create(code);
      expect(calls, contains('GET /v2/lists/$sid/recoveries'));
      expect(calls.where((r) => r.startsWith('DELETE')), hasLength(1));
      expect(await p.recovery.readMaintenance(sid), isNull);
      w.intercept = null;
      await (await p.maintenance(w)).create(RecoveryCode.generate());
      expect(
        (await (await p.maintenance(w)).status()).readiness,
        RecoveryReadiness.confirmationPending,
      );
    },
  );

  test(
    'MEDIA-4 update CAS loss reopens current capsule and recaptures',
    () async {
      final p = (await family(w, solo: true)).single;
      final code = RecoveryCode.generate();
      await (await p.maintenance(w)).create(code);
      final stored = (await p.family.load())!;
      await p.family.saveIdentity(stored.identity.copyWith(deviceName: 'Nora'));
      final updater = RecoveryMaintenance(
        store: p.recovery,
        family: p.family,
        exporter: RecoveryExporter(p.generations, p.reader(w)),
        transport: w,
        auth: await p.auth(),
        minimumUpdateInterval: Duration.zero,
      );
      var raced = false;
      final puts = <String?>[];
      w.intercept = (r) async {
        if (r.method != 'PUT') return null;
        puts.add(r.headers['If-Match']);
        if (!raced) {
          raced = true;
          expect((await w.recoveries.send(r)).status, 200);
          final locator = await deriveRecoveryLocator(code);
          final current = await w.recoveries.send(
            RecoveryRequest(
              'GET',
              '/v2/recoveries/${locator.recoveryId}',
              headers: {'X-Recovery-Cap': locator.readCap},
            ),
          );
          final payload = await openRecoveryCapsule(
            RecoveryCapsule.fromJson(current.body).bytes,
            code,
            expectedRevision: 2,
          );
          expect(
            (await w.recoveries.send(
              RecoveryRequest(
                'PUT',
                r.path,
                headers: recoveryAuthHeaders(await p.auth(), 2),
                body: {
                  ...r.body!,
                  'capsule': encodeBase64Url(
                    await sealRecoveryCapsule(payload, code, revision: 3),
                  ),
                },
              ),
            )).status,
            200,
          );
          return RecoveryResponse(412, body: {'error': 'precondition_failed'});
        }
        return null;
      };
      await updater.maintain();
      expect(puts, ['"1"', '"3"']);
      expect(await p.recovery.readMaintenance(sid), isNull);
      expect((await p.recovery.readMaterial(sid))!['revision'], 4);
    },
  );

  test('MEDIA-4 cancel pending update preserves installed material', () async {
    final p = (await family(w, solo: true)).single;
    final code = RecoveryCode.generate();
    await (await p.maintenance(w)).create(code);
    final old = (await p.recovery.readMaterial(sid))!;
    await p.recovery.prepareMaintenance(sid, RecoveryMaintenanceKind.update, {
      'old': old,
      'phase': 'capture',
      'entropy': old['entropy'],
    });
    await (await p.maintenance(w)).cancel();
    expect(await p.recovery.readMaintenance(sid), isNull);
    expect(await p.recovery.readMaterial(sid), old);
  });

  for (final cause in [
    'recovery_limit',
    'recovery_history_full',
    'recovery_exists',
    'recovery_operation_conflict',
    'invalid_recovery',
    'recovery_too_large',
    'unauthorized',
  ]) {
    test('MEDIA-4 create terminal $cause releases intent', () async {
      final p = (await family(w, solo: true)).single;
      w.failPut = cause;
      await (await p.maintenance(w)).create(RecoveryCode.generate());
      expect(await p.recovery.readMaintenance(sid), isNull);
      expect(await p.recovery.hasCodeDisplay(sid), isFalse);
      w.failPut = null;
      await (await p.maintenance(w)).create(RecoveryCode.generate());
      expect(
        (await (await p.maintenance(w)).status()).readiness,
        RecoveryReadiness.confirmationPending,
      );
    });
  }

  for (final rotate in [false, true]) {
    test(
      'MEDIA-4 ${rotate ? 'rotate' : 'create'} revision mismatch closes unseen code',
      () async {
        final p = (await family(w, solo: true)).single;
        final oldCode = RecoveryCode.generate();
        if (rotate) await (await p.maintenance(w)).create(oldCode);
        final candidate = RecoveryCode.generate();
        final locator = await deriveRecoveryLocator(candidate);
        w.intercept = (r) async {
          if (r.method != 'GET' ||
              r.path != '/v2/recoveries/${locator.recoveryId}') {
            return null;
          }
          final actual = await w.recoveries.send(r);
          final payload = await openRecoveryCapsule(
            RecoveryCapsule.fromJson(actual.body).bytes,
            candidate,
            expectedRevision: 1,
          );
          return RecoveryResponse(
            200,
            headers: {'etag': '"2"'},
            body: RecoveryCapsule(
              await sealRecoveryCapsule(payload, candidate, revision: 2),
            ).toJson(),
          );
        };
        final maintenance = await p.maintenance(w);
        if (rotate) {
          await maintenance.rotate(candidate);
        } else {
          await maintenance.create(candidate);
        }
        expect(await p.recovery.readMaintenance(sid), isNull);
        expect(await p.recovery.hasCodeDisplay(sid), isFalse);
        expect(await p.recovery.readFailure(sid), 'capsule_revision_mismatch');
        if (rotate) {
          expect(
            (await p.recovery.readMaterial(sid))!['entropy'],
            encodeBase64Url(oldCode.entropy),
          );
        }
      },
    );
  }

  Future<StoredPhone> changingPerson() async {
    final p = (await family(w, solo: true)).single;
    await (await p.maintenance(w)).create(RecoveryCode.generate());
    // The real journal installs the barrier before changing local identity.
    await p.family.prepareSelfPersonChange(
      personId: 'leo',
      registry: (await p.family.readRegistry())!,
      orphans: [],
    );
    await p.family.finishSelfPersonChange();
    return p;
  }

  test('M4 no ordinary publication until DELETE is confirmed', () async {
    final p = await changingPerson();
    final mutations = w.mutations;
    await expectLater(
      p.sync(w),
      throwsA(isA<V2RecoveryInvalidationPendingException>()),
    );
    expect(w.mutations, mutations);
    w.intercept = (r) async =>
        r.method == 'DELETE' ? RecoveryResponse(503) : null;
    await expectLater(
      (await p.maintenance(w)).maintain(),
      throwsA(isA<RecoveryTransportException>()),
    );
    expect(await p.family.recoveryPersonInvalidationPending(), isTrue);
    await expectLater(
      p.sync(w),
      throwsA(isA<V2RecoveryInvalidationPendingException>()),
    );
    expect(w.mutations, mutations);
    w.intercept = null;
    await (await p.maintenance(w)).maintain();
    expect(await p.family.recoveryPersonInvalidationPending(), isFalse);
    await p.sync(w);
  });

  test(
    'M4 missing capsule in pre-retirement GET completes invalidation',
    () async {
      final p = await changingPerson();
      w.intercept = (r) async =>
          r.method == 'GET' && r.path.startsWith('/v2/recoveries/')
          ? RecoveryResponse(404, body: {'error': 'not_found'})
          : null;
      await (await p.maintenance(w)).maintain();
      expect(await p.family.recoveryPersonInvalidationPending(), isFalse);
      expect((await p.recovery.readMaterial(sid))!['retired'], isTrue);
      expect(await p.recovery.readMaintenance(sid), isNull);
    },
  );

  test(
    'M4 DELETE CAS loss lists, reopens capsule and retries fresh CAS',
    () async {
      final p = await changingPerson();
      final calls = <String>[];
      var raced = false;
      w.intercept = (r) async {
        calls.add('${r.method} ${r.path}');
        if (r.method != 'DELETE' || raced) return null;
        raced = true;
        final material = (await p.recovery.readMaterial(sid))!;
        final code = RecoveryCode(
          decodeBase64Url(material['entropy'] as String),
        );
        final locator = await deriveRecoveryLocator(code);
        final current = await w.recoveries.send(
          RecoveryRequest(
            'GET',
            '/v2/recoveries/${locator.recoveryId}',
            headers: {'X-Recovery-Cap': locator.readCap},
          ),
        );
        final payload = await openRecoveryCapsule(
          RecoveryCapsule.fromJson(current.body).bytes,
          code,
          expectedRevision: 1,
        );
        final updated = await w.recoveries.send(
          RecoveryRequest(
            'PUT',
            '/v2/lists/$sid/recoveries/${locator.recoveryId}',
            headers: recoveryAuthHeaders(await p.auth(), 1),
            body: {
              'v': 2,
              'deviceId': payload.identity.deviceId,
              'readVerifier': locator.readVerifier,
              'capsule': encodeBase64Url(
                await sealRecoveryCapsule(payload, code, revision: 2),
              ),
            },
          ),
        );
        expect(updated.status, 200);
        return null;
      };
      await (await p.maintenance(w)).maintain();
      expect(calls.where((r) => r.startsWith('DELETE')), hasLength(2));
      expect(calls, contains('GET /v2/lists/$sid/recoveries'));
      expect(await p.family.recoveryPersonInvalidationPending(), isFalse);
    },
  );

  test('B3 capability-only credential_replaced never marks installation transferred', () async {
    final p = await changingPerson();
    w.intercept = (r) async => r.headers.containsKey('X-Recovery-Cap')
        ? RecoveryResponse(403, body: {'error': 'credential_replaced'})
        : null;
    await expectLater(
      (await p.maintenance(w)).maintain(),
      throwsA(isA<RecoveryTransportException>()),
    );
    expect(await p.recovery.isTransferred(sid), isFalse);
    expect(await p.family.isTransferred(), isFalse);
  });

  test('M6 reader workspace is erased after successful and failed reads; B1 observed floor survives', () async {
    final p = (await family(w, solo: true)).single;
    final captured = await RecoveryExporter(
      p.generations,
      p.reader(w),
    ).capture(sid);
    workspaceEmpty(p);
    final stale = await RecoveryCapsulePayload.fromJson({
      ...captured.toJson(),
      'commonFormatFloor': 1,
      'commonKeysMarked': false,
      'resume': {...captured.resume.toJson(), 'commonFormatV2': false},
    });
    final result = await p.reader(w).download(stale, const {}, null);
    expect(result.installation!.payload.commonFormatFloor, 2);
    expect(result.installation!.payload.commonKeysMarked, isTrue);
    expect(result.installation!.payload.resume.commonFormatV2, isTrue);
    workspaceEmpty(p);
    w.offline = true;
    await expectLater(
      p.reader(w).download(captured, const {}, null),
      throwsA(isA<SyncTransportException>()),
    );
    workspaceEmpty(p);
  });

  test(
    'M6 person change and confirmed erase include isolated workspaces',
    () async {
      final p = (await family(w, solo: true)).single;
      final workspace = p.generations.recoveryReader(sid);
      await workspace.deviceKeys.restoreReadWorkspace((await p.keys.read())!);
      await p.family.prepareSelfPersonChange(
        personId: 'leo',
        registry: (await p.family.readRegistry())!,
        orphans: [],
      );
      workspaceEmpty(p);
      await workspace.deviceKeys.restoreReadWorkspace((await p.keys.read())!);
      await p.files.writeAtomic(
        'recovery.read.$sid.family.scope.orphan',
        Uint8List(1),
      );
      await p.generations.eraseAllConfirmed();
      workspaceEmpty(p);
      expect(p.secrets.values, isEmpty);
    },
  );

  for (final status in [200, 502]) {
    test(
      'B2 non-JSON HTTP $status is a transient typed transport error',
      () async {
        final client = RecoveryClient(
          base: Uri.parse('https://sync.test'),
          sendRequest: (method, uri, {body, headers = const {}}) async =>
              SyncResponse(
                status,
                {},
                Uint8List.fromList(utf8.encode('<html>Unavailable</html>')),
              ),
        );
        await expectLater(
          client.send(RecoveryRequest('GET', '/v2/recoveries/id')),
          throwsA(
            isA<RecoveryTransportException>()
                .having((e) => e.status, 'status', status)
                .having((e) => e.code, 'code', 'invalid_response')
                .having((e) => e.retryable, 'retryable', isTrue),
          ),
        );
      },
    );
  }

  test('B4 arbitrary server text cannot become a recovery cause', () {
    expect(
      RecoveryResponse(409, body: {'error': 'arbitrary server text'}).error,
      'invalid_response',
    );
    expect(
      RecoveryResponse(
        403,
        body: {
          'error': {'secret': 'text'},
        },
      ).error,
      'invalid_response',
    );
    expect(
      RecoveryResponse(409, body: {'error': 'recovery_retired'}).error,
      'recovery_retired',
    );
  });
}
