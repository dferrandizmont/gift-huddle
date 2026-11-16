import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';
import 'package:regalos/features/web_device/data/guard_client.dart';
import 'package:regalos/features/web_device/application/web_session_platform.dart';
import 'package:regalos/features/sync/application/pairing_v2_flow.dart';
import 'package:regalos/features/sync/application/v2_family_lock.dart';
import 'package:regalos/features/web_device/application/vault_service.dart';
import 'package:regalos/features/web_device/application/web_gate_controller.dart';
import 'package:regalos/features/web_device/application/web_session_controller.dart';
import 'package:regalos/features/web_device/application/web_sync_engine.dart';
import 'package:regalos/features/web_device/data/vault_crypto.dart';
import 'package:regalos/features/web_device/data/vault_store.dart';
import 'package:regalos/features/web_device/presentation/web_gate_model.dart';

import 'test_support.dart';
import 'web_engine_support.dart';

void main() {
  late WebHarness h;
  late FakeLockHub locks;
  late WebGateController gate;
  final events = <String>[];
  WebGateController controller(VaultService vault) => WebGateController(
    vault: vault,
    platform: FakeSessionPlatform(locks),
    transport: () => h.client,
    createContainer: (_) => events.add('create'),
    disposeContainer: () => events.add('dispose'),
    cancelTransport: () => events.add('cancel'),
  );
  void cooldown() {
    for (final s in h.worker.guard.guards.values) {
      s.nextAttemptAt = null;
    }
  }

  setUp(() async {
    h = WebHarness();
    await h.setup();
    h.engine.stop();
    h.vault.lock();
    locks = FakeLockHub();
    events.clear();
    gate = controller(h.vault);
    gate.addListener(() {
      if (gate.view is WebGateLocked) events.add('cover');
    });
    await gate.initialize();
  });
  tearDown(() async {
    await gate.close();
    h.guest.cancel();
  });

  Future<PairingV2Host> reachComparison() async {
    final host = await PairingV2Host.start(
      transport: h.client,
      local: h.phone,
      lock: V2FamilyLock(),
      web: gate.guest!.qr,
      guestPerson: 'nora',
    );
    await gate.checkPairing();
    await host.poll();
    await gate.checkPairing();
    return host;
  }

  Future<void> reachPin() async {
    final host = await reachComparison();
    await gate.confirmCode();
    await host.confirm(confirmedPersonId: 'nora');
    await gate.checkPairing();
    expect(gate.view, isA<WebGateChoosePin>());
  }

  for (final phase in ['qr', 'comparison', 'pin']) {
    test(
      'BFCache during $phase aborts enrollment with no box and permits a new QR',
      () async {
        await gate.eraseComputer();
        final old = gate.guest!.qr.inviteId;
        if (phase == 'comparison') await reachComparison();
        if (phase == 'pin') await reachPin();
        final platform = locks.platforms.single;
        platform.life.add(SessionLifecycle.pagehide);
        platform.life.add(SessionLifecycle.pageshowPersisted);
        await Future<void>.delayed(Duration.zero);
        expect(gate.view, isA<WebGateConnectFailed>());
        expect(gate.guest, isNull);
        expect((await h.store.read()).current, isNull);
        await gate.restartPairing();
        expect(gate.view, isA<WebGateConnect>());
        expect(gate.guest!.qr.inviteId, isNot(old));
      },
    );
  }

  for (final route in ['prepare', 'commit']) {
    test(
      'cut after $route recovers according to the actual current or pending box',
      () async {
        await gate.eraseComputer();
        await reachPin();
        h.worker.tamper = (method, uri, response) {
          if (uri.path.endsWith('/$route')) {
            throw StateError('cut after $route');
          }
          return response;
        };
        await gate.choosePin('123456');
        h.worker.tamper = null;
        if (route == 'prepare') {
          expect((await h.store.read()).pending, isNull);
          expect(gate.view, isA<WebGateConnectFailed>());
          await gate.restartPairing();
          expect(gate.view, isA<WebGateConnect>());
        } else {
          expect((await h.store.read()).pending, isNotNull);
          expect(gate.view, isA<WebGateUnlock>());
          await gate.submitPin('123456');
          expect(gate.view, isA<WebGateOpen>());
          expect((await h.store.read()).pending, isNull);
        }
      },
    );
  }

  test(
    'pagehide during prepare before local write leaves an aborted enrollment',
    () async {
      await gate.eraseComputer();
      await gate.close();
      final prepared = Completer<void>();
      final resume = Completer<void>();
      final vault = VaultService(
        store: h.store,
        crypto: FastTestCrypto(),
        persist: () async => false,
        guard: GuardClient(
          base: Uri.parse('https://sync.test'),
          send: (method, uri, {body, headers = const {}}) async {
            final response = await h.worker.send(
              method,
              uri,
              body: body,
              headers: headers,
            );
            if (uri.path.endsWith('/prepare')) {
              prepared.complete();
              await resume.future;
            }
            return response;
          },
        ),
      );
      gate = controller(vault);
      await gate.initialize();
      await reachPin();
      final enrollment = gate.choosePin('123456');
      await prepared.future;
      locks.platforms.single.life.add(SessionLifecycle.pagehide);
      locks.platforms.single.life.add(SessionLifecycle.pageshowPersisted);
      resume.complete();
      await enrollment;
      await Future<void>.delayed(Duration.zero);
      expect((await h.store.read()).pending, isNull);
      expect(gate.view, isA<WebGateConnectFailed>());
      await gate.restartPairing();
      expect(gate.view, isA<WebGateConnect>());
    },
  );

  test('self-revocation 4401 before HTTP response still erases box and queue under the lease', () async {
    await gate.close();
    final revoked = Completer<void>();
    final responseAllowed = Completer<void>();
    final client = SyncV2Client(
      base: Uri.parse('https://sync.test'),
      openSocket: h.worker.socket,
      sendRequest: (method, uri, {body, headers = const {}}) async {
        final response = await h.worker.send(
          method,
          uri,
          body: body,
          headers: headers,
        );
        if (uri.path.endsWith('/revoke')) {
          revoked.complete();
          await responseAllowed.future;
        }
        return response;
      },
    );
    final vault = VaultService(
      store: h.store,
      guard: h.vault.guard,
      crypto: FastTestCrypto(),
      persist: () async => false,
      revokeSelf: (opened) async {
        final auth = V2Auth(
          syncId: opened.header.syncId,
          deviceId: opened.header.deviceId,
          credential: decodeBase64Url(opened.data['credential'] as String),
        );
        await client.revoke(auth, auth.deviceId);
      },
    );
    gate = WebGateController(
      vault: vault,
      platform: FakeSessionPlatform(locks),
      transport: () => client,
      createContainer: (_) {},
      disposeContainer: () {},
    );
    await gate.initialize();
    await gate.submitPin('123456');
    await gate.engine!.start();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(h.worker.watchers(vault.opened.header.syncId), 1);
    final before = gate.engine!.candidate!;
    await gate.engine!.save(
      before,
      before.set(
        HlcClock(node: 'web', last: before.maxStamp),
        Collections.gifts,
        'gift',
        {'title': 'Libro'},
      ),
    );
    final forgetting = gate.forgetComputer();
    await revoked.future;
    await Future<void>.delayed(Duration.zero);
    expect(vault.status, VaultStatus.open);
    expect(locks.owner, isNotNull);
    expect((await h.store.read()).current!.entries, hasLength(1));
    responseAllowed.complete();
    await forgetting;
    expect((await h.store.read()).current, isNull);
    expect((await h.store.read()).pending, isNull);
    expect(vault.status, VaultStatus.locked);
    expect(locks.owner, isNull);
    expect(gate.view, isA<WebGateConnect>());
  });

  test('wrong PIN yields a new unlock instance, retryAfter, suspension; never erases', () async {
    expect(gate.view, isA<WebGateUnlock>());
    final first = gate.view;
    await gate.submitPin('654321');
    expect(
      gate.view,
      isA<WebGateUnlock>()
          .having((v) => v.wrongPin, 'wrong', true)
          .having((v) => v.attemptsLeft, 'remaining', 9),
    );
    expect(identical(gate.view, first), isFalse);
    final second = gate.view;
    await gate.submitPin('654321');
    expect(
      gate.view,
      isA<WebGateUnlock>().having((v) => v.retryAfter, 'wait', isNotNull),
    );
    expect(identical(gate.view, second), isFalse);
    for (var i = 0; i < 9; i++) {
      cooldown();
      await gate.submitPin('654321');
    }
    expect(gate.view, isA<WebGateSuspended>());
    expect((await h.store.read()).current, isNotNull);
    expect(events, isNot(contains('create')));
    await gate.retry();
    expect(gate.view, isA<WebGateUnlock>());
  });

  test('a box whose integrity check fails after the right PIN shows WebGateDamaged, then erase reconnects', () async {
    // A queue entry the checkpoint never sealed: stateHash no longer matches.
    await h.store.transaction((state) {
      final current = state.current!;
      return VaultState(
        current: VaultSet(
          header: current.header,
          box: current.box,
          entries: {
            ...current.entries,
            'ghost': {'nonce': 'AA', 'ciphertext': 'AA', 'mac': 'AA'},
          },
          marks: current.marks,
        ),
      );
    });
    await gate.submitPin('123456');
    expect(gate.view, isA<WebGateDamaged>());
    expect(events, isNot(contains('create')));
    // The lock that follows the failure must not bring the PIN screen back.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(gate.view, isA<WebGateDamaged>());
    expect((await h.store.read()).current, isNotNull);

    await gate.eraseComputer();
    expect((await h.store.read()).current, isNull);
    expect(gate.view, isA<WebGateConnect>());
  });

  test('a wrong PIN is still a wrong PIN, not damage', () async {
    await gate.submitPin('654321');
    expect(
      gate.view,
      isA<WebGateUnlock>().having((v) => v.wrongPin, 'wrong', true),
    );
  });

  test('open -> synchronous cover -> cancel -> dispose -> locked; no mobile container survives', () async {
    await gate.submitPin('123456');
    expect(gate.view, isA<WebGateOpen>());
    expect(events, contains('create'));
    events.clear();
    await gate.lock();
    expect(events.take(3), ['cover', 'cancel', 'dispose']);
    expect(gate.view, isA<WebGateUnlock>());
    expect(h.vault.status, VaultStatus.locked);
    expect(gate.engine, isNull);
  });

  for (final route in ['prepare', 'commit']) {
    for (final guardError in [false, true]) {
      test(
        'PIN change $route and cancel failure (guardError=$guardError) closes the session',
        () async {
          await gate.submitPin('123456');
          expect(gate.view, isA<WebGateOpen>());
          cooldown();
          events.clear();
          final failedRoutes = <String>[];
          h.worker.tamper = (method, uri, response) {
            if (uri.path.endsWith('/$route') || uri.path.endsWith('/cancel')) {
              failedRoutes.add(uri.pathSegments.last);
              if (guardError) throw const GuardException(GuardFailure.protocol);
              throw StateError('Network cut after ${uri.pathSegments.last}');
            }
            return response;
          };

          expect(
            await gate.changePin('123456', '654321'),
            WebPinChangeResult.failed,
          );
          expect(failedRoutes, [route, 'cancel']);
          expect(gate.view, isA<WebGateUnlock>());
          expect(gate.session.state, WebSessionState.bloqueada);
          expect(h.vault.status, VaultStatus.locked);
          expect(gate.engine, isNull);
          expect(locks.owner, isNull);
          expect(events.take(3), ['cover', 'cancel', 'dispose']);
          expect((await h.store.read()).pending, isNotNull);

          h.worker.tamper = null;
          cooldown();
          await gate.submitPin(route == 'commit' ? '654321' : '123456');
          expect(gate.view, isA<WebGateOpen>());
          expect((await h.store.read()).pending, isNull);
        },
      );
    }
  }

  test(
    'failed rotation while verifying the current PIN closes the session',
    () async {
      await gate.submitPin('123456');
      expect(gate.view, isA<WebGateOpen>());
      cooldown();
      events.clear();
      h.worker.guard.guards.values.single.mustRotate = true;
      h.worker.tamper = (method, uri, response) {
        if (uri.path.endsWith('/prepare')) throw StateError('Network cut');
        return response;
      };

      expect(
        await gate.changePin('123456', '654321'),
        WebPinChangeResult.failed,
      );
      expect(gate.view, isA<WebGateUnlock>());
      expect(gate.session.state, WebSessionState.bloqueada);
      expect(h.vault.status, VaultStatus.locked);
      expect(gate.engine, isNull);
      expect(locks.owner, isNull);
      expect(events.take(3), ['cover', 'cancel', 'dispose']);

      h.worker.tamper = null;
      cooldown();
      await gate.submitPin('123456');
      expect(gate.view, isA<WebGateOpen>());
      expect(h.worker.guard.guards.values.single.rotationRequired, isFalse);
    },
  );

  test(
    'a second tab never opens before the exclusive lease is released',
    () async {
      await gate.submitPin('123456');
      final vault2 = VaultService(
        store: h.store,
        guard: h.vault.guard,
        crypto: FastTestCrypto(),
        persist: () async => false,
      );
      final other = controller(vault2);
      addTearDown(other.close);
      await other.initialize();
      await other.submitPin('123456');
      expect(other.view, isA<WebGateOtherTab>());
      await other.useHere();
      cooldown();
      await other.submitPin('123456');
      expect(gate.view, isA<WebGateUnlock>());
      expect(other.view, isA<WebGateOpen>());
    },
  );

  test(
    'revocation keeps encrypted actions; reconnect requires explicit erase',
    () async {
      await gate.submitPin('123456');
      final engine = gate.engine!;
      final before = engine.candidate!;
      await engine.save(
        before,
        before.set(
          HlcClock(node: 'web', last: before.maxStamp),
          Collections.gifts,
          'gift',
          {'title': 'Libro'},
        ),
      );
      await h.client.revoke(h.phone.auth, h.guest.joined!.identity.deviceId);
      // The socket may still be starting; the read reaches the same disconnection.
      await engine.sync().catchError((Object _) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        gate.view,
        isA<WebGateDisconnected>().having((v) => v.unsentChanges, 'saved', 1),
      );
      await gate.reconnect();
      expect(
        gate.view,
        isA<WebGateDisconnected>().having(
          (v) => v.confirmErase,
          'confirm',
          true,
        ),
      );
      expect((await h.store.read()).current!.entries, hasLength(1));
      await gate.eraseComputer();
      expect(gate.view, isA<WebGateConnect>());
      expect((await h.store.read()).current, isNull);
    },
  );

  test('resume with mobile credential unlocks a suspended web without replacing its guard', () async {
    final state = h.worker.guard.guards.values.single;
    state.suspended = true;
    final header = VaultHeader.fromJson((await h.store.read()).current!.header);
    final current = state.current;
    await gate.submitPin('123456');
    expect(gate.view, isA<WebGateSuspended>());
    await h.vault.guard.resume(header, h.phone.keys.serviceCredential);
    expect(state.current, same(current));
    await gate.retry();
    await gate.submitPin('123456');
    expect(gate.view, isA<WebGateOpen>());
  });

  test(
    'the real gate drives QR, comparison, name, PIN enrollment and open',
    () async {
      // Explicit erase is the only way from this existing identity to a new QR.
      await gate.eraseComputer();
      final web = gate.guest!;
      final host = await PairingV2Host.start(
        transport: h.client,
        local: h.phone,
        lock: V2FamilyLock(),
        web: web.qr,
        guestPerson: 'nora',
      );
      await gate.checkPairing();
      final answer = (await host.poll())!;
      await gate.checkPairing();
      expect(
        gate.view,
        isA<WebGateComparing>().having((v) => v.code, 'code', answer.code),
      );
      await gate.confirmCode();
      await host.confirm(confirmedPersonId: 'nora');
      await gate.checkPairing();
      expect(
        gate.view,
        isA<WebGateChoosePin>().having((v) => v.personName, 'name', 'Nora'),
      );
      await gate.choosePin('123456');
      expect(gate.view, isA<WebGateOpen>());
      expect(gate.engine!.status, WebSyncStatus.confirmed);
      expect(h.vault.opened.data['personId'], 'nora');
    },
  );

  test(
    'pre-offer Retry-After is a lower bound and cancellation discards the poll',
    () async {
      await gate.eraseComputer();
      h.worker.rateLimitNext = 120;
      await gate.checkPairing();
      expect(gate.view, isA<WebGateConnect>());
      // Honoured, but never more than 60 s (1.0.2).
      expect(gate.nextPairingPoll, const Duration(seconds: 60));
      await gate.rejectCode();
      expect(gate.nextPairingPoll, isNull);
    },
  );

  test(
    'code mismatch invalidates the in-memory identity without creating a vault',
    () async {
      await gate.eraseComputer();
      final old = gate.guest!.qr.inviteId;
      await gate.rejectCode();
      expect(
        gate.view,
        isA<WebGateConnectFailed>().having(
          (v) => v.reason,
          'reason',
          WebConnectFailure.codeMismatch,
        ),
      );
      await gate.restartPairing();
      expect(gate.guest!.qr.inviteId, isNot(old));
      expect((await h.store.read()).current, isNull);
    },
  );
}
