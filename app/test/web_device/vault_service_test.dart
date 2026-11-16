import 'dart:convert';
import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/device_keys.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';
import 'package:regalos/features/web_device/application/pending_queue.dart';
import 'package:regalos/features/web_device/application/vault_service.dart';
import 'package:regalos/features/web_device/data/guard_client.dart';
import 'package:regalos/features/web_device/data/vault_crypto.dart';
import 'package:regalos/features/web_device/data/web_device_keys_store.dart';
import 'package:regalos/features/web_device/data/vault_store.dart';
import 'package:regalos/features/web_device/application/web_session_controller.dart';

import 'test_support.dart';
import 'fake_guard_server.dart';

FamilyDoc delta() =>
    FamilyDoc.empty('family')
        .set(HlcClock(node: 'bbbbbbbbbb'), 'people', 'nora', {'name': 'Nora'});

class _Pbkdf2Spy extends VaultCrypto {
  int calls = 0;
  @override
  Future<SecretKey> pbkdf2(List<int> pinBytes, VaultHeader header) {
    calls++;
    throw StateError('PBKDF2 must not start');
  }
}

class _DeferredStore extends VaultStore {
  _DeferredStore(this.inner);
  final VaultStore inner;
  Completer<void>? gate;
  final entered = Completer<void>();
  @override
  Future<VaultState> read() => inner.read();
  @override
  Future<void> transaction(VaultState Function(VaultState) update) async {
    if (gate case final pending?) {
      entered.complete();
      await pending.future;
    }
    await inner.transaction(update);
  }
}

void main() {
  for (final resume in [false, true]) {
    test('copied token dies on owner unlock, resume=$resume', () async {
      final h = VaultHarness();
      await h.enroll();
      final old = h.service.opened.header;
      final oldSecret = h.server.guards.values.single.current!.secret;
      final queue = PendingQueue(h.service);
      final id = await queue.add(delta());
      await queue.blockedPeople(remember: {'nora'});
      h.service.lock();
      final attempts = resume ? 10 : 3;
      for (var i = 0; i < attempts; i++) {
        await expectLater(
          h.service.unlock('999999'),
          throwsA(isA<GuardException>()),
        );
        h.advance();
      }
      if (resume) {
        final mobile = List<int>.filled(32, 3);
        h.server.credentials['Bearer ${encodeBase64Url(mobile)}'] =
            FakeGuardCredential(old.syncId, 'mobile', 'device');
        await h.client.resume(old, mobile);
      }
      await h.service.unlock('123456');
      expect(h.service.lastUnlockFailedAttempts, attempts);
      final fresh = h.service.opened.header;
      expect(fresh.guardVersion, 2);
      expect(fresh.salt, isNot(old.salt));
      expect(fresh.guardToken, isNot(old.guardToken));
      expect(h.server.guards.values.single.current!.secret, isNot(oldSecret));
      expect((await queue.entries()).single.id, id);
      expect(await queue.blockedPeople(), {'nora'});
      await expectLater(
        h.client.open(old, [GuardProof(1, old.guardToken, List.filled(32, 0))]),
        throwsA(
          isA<GuardException>().having(
            (e) => e.failure,
            'failure',
            GuardFailure.disconnected,
          ),
        ),
      );
      h.service.lock();
      h.advance();
      await h.service.unlock('123456');
      expect(h.service.lastUnlockFailedAttempts, 0);
      expect(h.service.opened.header.guardVersion, 2);
    });
  }

  test('automatic rotation failure stays locked and retries despite delivered counter', () async {
    final h = VaultHarness();
    await h.enroll();
    h.service.lock();
    await expectLater(
      h.service.unlock('999999'),
      throwsA(isA<GuardException>()),
    );
    h.advance();
    h.failRoute = 'prepare';
    await expectLater(h.service.unlock('123456'), throwsStateError);
    expect(h.service.status, VaultStatus.locked);
    expect(() => h.service.opened, throwsStateError);
    expect(h.server.guards.values.single.rotationRequired, isTrue);
    h.failRoute = null;
    h.advance();
    await h.service.unlock('123456');
    expect(h.service.opened.header.guardVersion, 2);
  });

  for (final route in ['prepare', 'commit']) {
    test(
      'failed $route cleans pending so session can save and enqueue',
      () async {
        final h = VaultHarness();
        await h.enroll();
        h.failRoute = route;
        await expectLater(h.service.changePin('654321'), throwsStateError);
        expect((await h.store.read()).pending, isNull);
        expect(h.service.status, VaultStatus.open);
        await h.service.saveData({...h.service.opened.data, 'saved': true});
        await PendingQueue(h.service).add(delta());
        expect(await PendingQueue(h.service).entries(), hasLength(1));
      },
    );
  }

  for (final tamper in ['delete entry', 'old marks', 'old box']) {
    for (final reopen in [false, true]) {
      // Full-store rollback cannot be detected after restart without an external
      // anchor, but partial rollback and in-session stale counters must fail.
      if (tamper == 'old box' && reopen) continue;
      test('rejects $tamper, reopen=$reopen', () async {
        final h = VaultHarness();
        await h.enroll();
        final queue = PendingQueue(h.service);
        final id = await queue.add(delta());
        await queue.blockedPeople(remember: {'nora'});
        final old = (await h.store.read()).current!;
        await queue.blockedPeople(remember: {'leo'});
        await h.store.transaction(
          (s) => VaultState(
            current: VaultSet(
              header: s.current!.header,
              box: tamper == 'old box' ? old.box : s.current!.box,
              entries: {...s.current!.entries}
                ..remove(tamper == 'delete entry' ? id : ''),
              marks: tamper == 'old marks' ? old.marks : s.current!.marks,
            ),
          ),
        );
        if (reopen) {
          h.service.lock();
          await expectLater(h.service.unlock('123456'), throwsFormatException);
          expect(h.service.status, VaultStatus.locked);
        } else {
          await expectLater(queue.entries(), throwsFormatException);
          await expectLater(queue.blockedPeople(), throwsFormatException);
          await expectLater(
            h.service.saveData(h.service.opened.data),
            throwsFormatException,
          );
          await expectLater(
            h.service.changePin('654321'),
            throwsFormatException,
          );
        }
      });
    }
  }

  test(
    'counter rejects an old valid box with an unchanged queue and marks',
    () async {
      final h = VaultHarness();
      await h.enroll();
      final previous = (await h.store.read()).current!;
      final counter = h.service.opened.counter;
      await h.service.saveData({
        ...h.service.opened.data,
        'snapshot': {'version': 2},
      });
      expect(h.service.opened.counter, counter + 1);
      await h.store.transaction((_) => VaultState(current: previous));
      await expectLater(
        PendingQueue(h.service).entries(),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('stale counter'),
          ),
        ),
      );
    },
  );

  test(
    'lost commit response retains the live new set even when cancel succeeds',
    () async {
      final h = VaultHarness();
      await h.enroll();
      final id = await PendingQueue(h.service).add(delta());
      h.failRoute = 'commit';
      h.failAfter = true;
      await expectLater(h.service.changePin('654321'), throwsStateError);
      expect(h.service.status, VaultStatus.locked);
      expect((await h.store.read()).pending, isNotNull);
      expect(h.server.guards.values.single.current!.version, 2);
      h.failRoute = null;
      await h.service.unlock('654321');
      expect(h.service.opened.header.guardVersion, 2);
      expect((await PendingQueue(h.service).entries()).single.id, id);
    },
  );

  test('failed local pending cleanup locks and next unlock recovers', () async {
    final h = VaultHarness();
    await h.enroll();
    var writes = 0;
    h.store.beforeWrite = () {
      if (++writes == 2) throw StateError('Cleanup disk failure');
    };
    h.failRoute = 'prepare';
    await expectLater(h.service.changePin('654321'), throwsStateError);
    expect(h.service.status, VaultStatus.locked);
    expect((await h.store.read()).pending, isNotNull);
    h.store.beforeWrite = null;
    h.failRoute = null;
    await h.service.unlock('123456');
    expect((await h.store.read()).pending, isNull);
    await PendingQueue(h.service).add(delta());
  });

  test('enrollment cut before durable storage is aborted', () async {
    final h = VaultHarness();
    h.store.beforeWrite = () => throw StateError('Disk failure');
    await expectLater(h.enroll(), throwsStateError);
    expect((await h.store.read()).pending, isNull);
    expect((await h.store.read()).current, isNull);
    expect(h.service.status, VaultStatus.locked);
    expect(h.server.guards.values.single.pending!.version, 1);
    await expectLater(h.newService().unlock('123456'), throwsStateError);
  });
  for (final after in [false, true]) {
    test(
      'enrollment cut ${after ? 'after' : 'before'} commit recovers durable pending',
      () async {
        final h = VaultHarness()
          ..failRoute = 'commit'
          ..failAfter = after;
        await expectLater(h.enroll(), throwsStateError);
        expect((await h.store.read()).pending, isNotNull);
        expect(h.service.status, VaultStatus.locked);
        h.failRoute = null;
        final recovered = h.newService();
        await recovered.unlock('123456');
        expect(recovered.status, VaultStatus.open);
        expect((await h.store.read()).current!.header['guardVersion'], 1);
        expect((await h.store.read()).pending, isNull);
      },
    );
  }
  for (final cut in ['before_prepare', 'after_prepare', 'after_commit']) {
    for (final pin in ['123456', '654321']) {
      test(
        'PIN change cut $cut then open $pin preserves queue and marks',
        () async {
          final h = VaultHarness();
          await h.enroll();
          final queue = PendingQueue(h.service);
          final action = delta();
          final id = await queue.add(action);
          await queue.setAside(id);
          await queue.blockedPeople(remember: {'nora'});
          h.failRoute = cut == 'after_commit' ? 'commit' : 'prepare';
          h.failAfter = cut != 'before_prepare';
          h.rejectRoute = 'cancel'; // Simulate interruption, including cleanup.
          await expectLater(h.service.changePin('654321'), throwsStateError);
          h.rejectRoute = null;
          final before = await h.store.read();
          expect(before.current, isNotNull);
          expect(before.pending, isNotNull);
          // Queue, box and marks are independently re-encrypted with fresh nonces.
          expect(
            before.current!.entries[id]!['nonce'],
            isNot(before.pending!.entries[id]!['nonce']),
          );
          expect(
            before.current!.marks!['nonce'],
            isNot(before.pending!.marks!['nonce']),
          );
          h.service.lock();
          h.failRoute = null;
          final recovered = h.newService();
          final shouldOpen = cut == 'before_prepare'
              ? pin == '123456'
              : cut == 'after_commit'
              ? pin == '654321'
              : true;
          if (!shouldOpen) {
            await expectLater(
              recovered.unlock(pin),
              throwsA(isA<GuardException>()),
            );
            expect((await h.store.read()).pending, isNotNull);
            h.advance();
            await recovered.unlock(pin == '123456' ? '654321' : '123456');
          } else {
            await recovered.unlock(pin);
          }
          final expectedVersion =
              cut == 'before_prepare' ||
                  (cut == 'after_prepare' && pin == '123456')
              ? 1
              : 2;
          expect(
            recovered.opened.header.guardVersion,
            expectedVersion + (shouldOpen ? 0 : 1),
          );
          expect((await h.store.read()).pending, isNull);
          expect(h.server.guards.values.single.pending, isNull);
          final restoredQueue = PendingQueue(recovered);
          final entries = await restoredQueue.entries();
          expect(entries.single.id, id);
          expect(entries.single.delta.toJson(), action.toJson());
          expect(entries.single.setAside, isTrue);
          expect(await restoredQueue.blockedPeople(), {'nora'});
        },
      );
    }
  }
  test('failed pending transaction never prepares a new guard', () async {
    final h = VaultHarness();
    await h.enroll();
    h.store.beforeWrite = () => throw StateError('Quota exceeded');
    await expectLater(h.service.changePin('654321'), throwsStateError);
    expect((await h.store.read()).pending, isNull);
    expect(h.server.guards.values.single.pending, isNull);
    expect(h.service.opened.header.guardVersion, 1);
  });
  test('queue stores deltas, aside survives, failed ack retains entry and receipt is atomic', () async {
    final h = VaultHarness();
    await h.enroll();
    final queue = PendingQueue(h.service);
    final ids = await Future.wait(List.generate(10, (_) => queue.add(delta())));
    expect(await queue.entries(), hasLength(10));
    expect(
      jsonEncode((await h.store.read()).toJson()),
      isNot(contains('Nora')),
    );
    h.store.beforeWrite = () => throw StateError('Disk failed');
    await expectLater(
      queue.ack(ids.first, confirmation: {'version': 7}),
      throwsStateError,
    );
    expect(await queue.entries(), hasLength(10));
    h.store.beforeWrite = null;
    await h.service.saveData({
      ...h.service.opened.data,
      'snapshot': {'version': 7},
    });
    await queue.ack(ids.first, confirmation: {'version': 7});
    expect(await queue.entries(), hasLength(9));
    final state = (await h.store.read()).current!;
    final marks = await h.service.crypto.open(
      state.marks!,
      h.service.opened.key,
      h.service.opened.header,
      'blocked',
    ) as Map;
    expect((marks['acks'] as Map)[ids.first], {'version': 7});
    await queue.blockedPeople(remember: {'nora'});
    await h.service.changePin('654321');
    h.service.lock();
    await h.service.unlock('654321');
    expect(h.service.opened.data['snapshot'], {'version': 7});
    expect(await queue.entries(), hasLength(9));
    expect(await queue.blockedPeople(), {'nora'});
  });
  test('404 disconnects, retaining ciphertext and queued changes', () async {
    final h = VaultHarness();
    await h.enroll();
    await PendingQueue(h.service).add(delta());
    h.service.lock();
    h.server.guards.clear();
    final before = jsonEncode((await h.store.read()).toJson());
    await expectLater(
      h.service.unlock('123456'),
      throwsA(isA<GuardException>()),
    );
    expect(h.service.status, VaultStatus.disconnected);
    expect(jsonEncode((await h.store.read()).toJson()), before);
    await h.service.forget();
    expect((await h.store.read()).current, isNull);
  });
  test('wrong PIN never deletes vault; suspension is distinct', () async {
    final h = VaultHarness();
    await h.enroll();
    h.service.lock();
    for (var n = 0; n < 10; n++) {
      await expectLater(
        h.service.unlock('999999'),
        throwsA(isA<GuardException>()),
      );
      h.advance();
    }
    expect(h.service.status, VaultStatus.suspended);
    expect((await h.store.read()).current, isNotNull);
  });
  test('forget awaits revocation; failing hook retains ciphertext', () async {
    final h = VaultHarness();
    await h.enroll();
    h.service.lock();
    var revoked = false;
    var fail = true;
    final service = VaultService(
      store: h.store,
      guard: h.client,
      crypto: FastTestCrypto(),
      revokeSelf: (_) async {
        if (fail) throw StateError('Offline');
        revoked = true;
      },
    );
    await service.unlock('123456');
    await expectLater(service.forget(), throwsStateError);
    expect((await h.store.read()).current, isNotNull);
    fail = false;
    await service.forget();
    expect(revoked, isTrue);
    expect((await h.store.read()).current, isNull);
  });
  test(
    'web identity reads opened vault, every surprise operation refuses',
    () async {
      final h = VaultHarness();
      final keys = await DeviceKeys.generate();
      await h.service.enroll(
        pin: '123456',
        syncId: 'AAAAAAAAAAAAAAAAAAAAAA',
        deviceId: 'bbbbbbbbbb',
        data: {
          'credential': encodeBase64Url(h.credential),
          'deviceKeys': keys.toJson(),
        },
      );
      final web = WebDeviceKeysStore(h.service);
      expect((await web.read())!.toJson(), keys.toJson());
      for (final operation in [
        () => web.readKeyring('family'),
        () => web.saveKeyring('family', SurpriseKeyring.empty),
        () => web.updateKeyring('family', (k) => k),
        () => web.purgePerson('nora'),
        () => web.create(),
        () => web.restore(keys),
        () => web.clear(),
      ]) {
        await expectLater(
          operation(),
          throwsA(isA<DeviceKeysStoreException>()),
        );
      }
      h.service.lock();
      await expectLater(web.read(), throwsStateError);
    },
  );
  test('all headers are bounded before KDF starts', () async {
    final h = VaultHarness();
    await h.enroll();
    final state = await h.store.read();
    h.service.lock();
    final spy = _Pbkdf2Spy();
    final service = VaultService(store: h.store, guard: h.client, crypto: spy);
    for (final change in [
      {'iterations': 599999},
      {'iterations': 2000001},
      {'format': 2},
      {'salt': encodeBase64Url(List.filled(15, 0))},
    ]) {
      await h.store.writePending(
        VaultSet(
          header: {...state.current!.header, 'guardVersion': 2, ...change},
          box: state.current!.box,
        ),
      );
      await expectLater(service.unlock('123456'), throwsFormatException);
      expect(
        spy.calls,
        0,
      ); // Even the valid current header must not reach PBKDF2.
    }
  });

  for (final cut in ['cancel_rejected', 'cancel_lost', 'delete', 'promote']) {
    test(
      'recovery cut at $cut retains a usable encrypted set and retries',
      () async {
        final h = VaultHarness();
        await h.enroll();
        final queueId = await PendingQueue(h.service).add(delta());
        await PendingQueue(h.service).blockedPeople(remember: {'nora'});
        h.failRoute = 'commit';
        h.failAfter = false;
        h.rejectRoute = 'cancel';
        await expectLater(h.service.changePin('654321'), throwsStateError);
        h.rejectRoute = null;
        h.service.lock();
        h.failRoute = null;
        h.requests.clear();
        final before = jsonEncode((await h.store.read()).toJson());
        if (cut == 'cancel_rejected') h.rejectRoute = 'cancel';
        if (cut == 'cancel_lost') {
          h.failRoute = 'cancel';
          h.failAfter = true;
        }
        if (cut == 'delete' || cut == 'promote') {
          h.store.beforeWrite = () =>
              throw StateError('Local transaction failed');
        }
        final recovered = h.newService();
        final pin = cut == 'promote' ? '654321' : '123456';
        await expectLater(
          recovered.unlock(pin),
          cut == 'cancel_rejected'
              ? throwsA(
                  isA<GuardException>().having(
                    (error) => error.failure,
                    'failure',
                    GuardFailure.forbidden,
                  ),
                )
              : throwsStateError,
        );
        expect(h.requests, ['open', cut == 'promote' ? 'commit' : 'cancel']);
        expect(recovered.status, VaultStatus.locked);
        expect(jsonEncode((await h.store.read()).toJson()), before);
        final remote = h.server.guards.values.single;
        if (cut == 'cancel_rejected') expect(remote.pending, isNotNull);
        if (cut == 'cancel_lost' || cut == 'delete') {
          expect(remote.pending, isNull);
        }
        if (cut == 'promote') {
          expect(remote.current!.version, 2);
          expect(remote.pending, isNull);
        }
        h.rejectRoute = null;
        h.failRoute = null;
        h.store.beforeWrite = null;
        h.advance();
        await recovered.unlock(pin);
        expect((await h.store.read()).pending, isNull);
        expect((await PendingQueue(recovered).entries()).single.id, queueId);
        expect(await PendingQueue(recovered).blockedPeople(), {'nora'});
      },
    );
  }

  test(
    'late forget after lock handover preserves the other session writes',
    () async {
      final h = VaultHarness();
      await h.enroll();
      h.service.lock();
      final hookEntered = Completer<void>();
      final hook = Completer<void>();
      final first = VaultService(
        store: h.store,
        guard: h.client,
        crypto: FastTestCrypto(),
        revokeSelf: (_) {
          hookEntered.complete();
          return hook.future;
        },
      );
      final hub = FakeLockHub();
      final clock = FakeSessionClock();
      WebSessionController controller(VaultService vault) =>
          WebSessionController(
            platform: FakeSessionPlatform(hub),
            clock: clock,
            cover: () {},
            cancelWork: () {},
            disposeContainer: () {},
            lockVault: vault.lock,
            unlockVault: (pin) async {
              await vault.unlock(pin);
            },
            createContainer: () {},
          );
      final a = controller(first);
      final second = h.newService();
      final b = controller(second);
      await a.unlock('123456');
      final forgotten = first.forget();
      final rejected = expectLater(forgotten, throwsStateError);
      await hookEntered.future;
      a.lock();
      h.advance();
      await b.unlock('123456');
      expect(b.state, WebSessionState.abierta);
      await second.saveData({
        ...second.opened.data,
        'snapshot': {'version': 9},
      });
      final before = jsonEncode((await h.store.read()).toJson());
      hook.complete();
      await rejected;
      expect(jsonEncode((await h.store.read()).toJson()), before);
      expect(first.status, VaultStatus.locked);
      await a.dispose();
      await b.dispose();
    },
  );

  test('forget checks generation inside the deleting transaction', () async {
    final h = VaultHarness();
    await h.enroll();
    final store = _DeferredStore(h.store);
    final service = VaultService(
      store: store,
      guard: h.client,
      crypto: FastTestCrypto(),
    );
    await service.unlock('123456');
    store.gate = Completer<void>();
    final forgotten = expectLater(
      service.forget(localOnly: true),
      throwsStateError,
    );
    await store.entered.future;
    service.lock();
    store.gate!.complete();
    await forgotten;
    expect((await h.store.read()).current, isNotNull);
  });
}
