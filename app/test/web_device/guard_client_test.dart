import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/features/web_device/data/guard_client.dart';
import 'package:regalos/features/web_device/data/vault_crypto.dart';

import 'fake_guard_server.dart';
import 'test_support.dart';

Matcher failure(GuardFailure expected, {int? left}) => isA<GuardException>()
    .having((e) => e.failure, 'failure', expected)
    .having((e) => left == null || e.left == left, 'left', isTrue);

void main() {
  test(
    'two proofs count once, 429 costs nothing, tenth failure suspends',
    () async {
      final h = VaultHarness();
      await h.enroll();
      final old = h.service.opened.header;
      h.failRoute = 'commit';
      h.rejectRoute = 'cancel';
      await expectLater(h.service.changePin('654321'), throwsStateError);
      h.rejectRoute = null;
      h.failRoute = null;
      final next = VaultHeader.fromJson((await h.store.read()).pending!.header);
      final bad = List<int>.filled(32, 0);
      final proofs = [
        GuardProof(old.guardVersion, old.guardToken, bad),
        GuardProof(next.guardVersion, next.guardToken, bad),
      ];
      for (var i = 1; i <= 10; i++) {
        await expectLater(
          h.client.open(old, proofs),
          throwsA(
            failure(
              i == 10 ? GuardFailure.suspended : GuardFailure.wrongPin,
              left: i == 10 ? null : 10 - i,
            ),
          ),
        );
        expect(h.server.guards.values.single.failures, i);
        await expectLater(
          h.client.open(old, proofs),
          throwsA(
            isA<GuardException>()
                .having((e) => e.failure, 'failure', GuardFailure.rateLimited)
                .having(
                  (e) => e.retryAfter,
                  'Retry-After',
                  const Duration(seconds: 2),
                ),
          ),
        );
        expect(h.server.guards.values.single.failures, i);
        h.advance();
      }
      final correct = await h.service.crypto.derive('123456', old);
      await expectLater(
        h.client.open(old, [
          GuardProof(
            old.guardVersion,
            old.guardToken,
            await correct.proof.extractBytes(),
          ),
        ]),
        throwsA(failure(GuardFailure.suspended)),
      );
      expect(h.server.guards.values.single.failures, 10);
    },
  );
  test(
    'uniform 404 for absent, wrong token and retired, without counters',
    () async {
      final h = VaultHarness();
      await h.enroll();
      final header = h.service.opened.header;
      final proof = GuardProof(1, List.filled(32, 0), List.filled(32, 0));
      await expectLater(
        h.client.open(header, [proof]),
        throwsA(failure(GuardFailure.disconnected)),
      );
      expect(h.server.guards.values.single.failures, 0);
      final correctToken = GuardProof(1, header.guardToken, List.filled(32, 0));
      h.server.retiredLists.add(header.syncId);
      await expectLater(
        h.client.open(header, [correctToken]),
        throwsA(failure(GuardFailure.disconnected)),
      );
      expect(h.server.guards.values.single.failures, 0);
      h.server.retiredLists.clear();
      h.server.guards.clear();
      await expectLater(
        h.client.open(header, [correctToken]),
        throwsA(failure(GuardFailure.disconnected)),
      );
    },
  );
  test(
    'prepare conflicts, commit/cancel idempotency and open has no credential',
    () async {
      final h = VaultHarness();
      await h.enroll();
      final header = h.service.opened.header;
      await h.client.commit(header, h.credential);
      await h.client.commit(header, h.credential);
      await h.client.cancel(header, h.credential);
      expect(h.server.guards.values.single.current!.version, 1);
      final current = h.server.guards.values.single.current!;
      await h.client.prepare(
        header,
        h.credential,
        tokenHash: current.tokenHash,
        verifier: current.verifier,
        b: decodeBase64Url(current.secret),
      );
      await expectLater(
        h.client.prepare(
          header,
          h.credential,
          tokenHash: current.tokenHash,
          verifier: current.verifier,
          b: List.filled(32, 7),
        ),
        throwsA(failure(GuardFailure.conflict)),
      );
      var called = false;
      final client = GuardClient(
        base: h.client.base,
        send: (method, uri, {body, headers = const {}}) {
          expect(headers.containsKey('Authorization'), isFalse);
          called = true;
          return h.server.send(method, uri, body: body, headers: headers);
        },
      );
      final d = await h.service.crypto.derive('123456', header);
      await client.open(header, [
        GuardProof(1, header.guardToken, await d.proof.extractBytes()),
      ]);
      expect(called, isTrue);
    },
  );
  test(
    'resume requires active device role from same list; errors stay distinct',
    () async {
      final h = VaultHarness();
      await h.enroll();
      final header = h.service.opened.header;
      final state = h.server.guards.values.single
        ..suspended = true
        ..failures = 10;
      await expectLater(
        h.client.resume(header, h.credential),
        throwsA(failure(GuardFailure.forbidden)),
      );
      final mobile = List<int>.filled(32, 3);
      final bearer = 'Bearer ${encodeBase64Url(mobile)}';
      h.server.credentials[bearer] = FakeGuardCredential(
        'other-list',
        'mobile',
        'device',
      );
      await expectLater(
        h.client.resume(header, mobile),
        throwsA(failure(GuardFailure.forbidden)),
      );
      expect(state.suspended, isTrue);
      h.server.credentials[bearer] = FakeGuardCredential(
        header.syncId,
        'mobile',
        'device',
      )..revoked = true;
      await expectLater(
        h.client.resume(header, mobile),
        throwsA(failure(GuardFailure.unauthorized)),
      );
      h.server.credentials[bearer]!.revoked = false;
      await h.client.resume(header, mobile);
      expect(state.suspended, isFalse);
      expect(state.failures, 0);
      h.server.retiredLists.add(header.syncId);
      await expectLater(
        h.client.commit(header, h.credential),
        throwsA(failure(GuardFailure.retired)),
      );
    },
  );
}
