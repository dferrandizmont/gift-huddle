// La web al emparejar, casos límite de la revisión (1.0.2), con tiempo falso:
//  1. Tras un 429, pulsar «Coinciden» otra vez no adelanta el sondeo.
//  5. Un 429 en `/answer` reintenta la misma respuesta sin volver a pedir la
//     oferta ni crear otra.
//  6. Atrasar la hora del sistema no alarga las esperas.
//  a. Sin oferta, 1-2 s los dos primeros minutos y después 3-4 s.
//  b. Ninguna espera pasa de la vida que le queda al QR.
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/sync/application/invite_poll_pacer.dart';
import 'package:regalos/features/sync/application/pairing_v2_flow.dart';
import 'package:regalos/features/sync/application/v2_family_lock.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';
import 'package:regalos/features/sync/data/sync_transport_common.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';
import 'package:regalos/features/web_device/application/vault_service.dart';
import 'package:regalos/features/web_device/application/web_gate_controller.dart';
import 'package:regalos/features/web_device/data/guard_client.dart';
import 'package:regalos/features/web_device/data/vault_store.dart';
import 'package:regalos/features/web_device/presentation/web_gate_model.dart';

import 'test_support.dart';
import 'web_engine_support.dart';
import '../sync/v2_harness.dart';

/// Runs [future] to completion advancing the fake clock 1 ms at a time.
T _drive<T>(FakeAsync async, Future<T> future) {
  var done = false;
  late T value;
  Object? error;
  future.then(
    (v) {
      value = v;
      done = true;
    },
    onError: (Object e) {
      error = e;
      done = true;
    },
  );
  for (var i = 0; i < 20000 && !done; i++) {
    async.elapse(const Duration(milliseconds: 1));
  }
  if (!done) throw StateError('did not finish');
  if (error != null) throw error!;
  return value;
}

SyncResponse _limited(int seconds) => SyncResponse(429, {
  'retry-after': '$seconds',
}, Uint8List.fromList(utf8.encode('{"error":"rate_limited"}')));

void main() {
  late WebHarness h;
  late WebGateController gate;
  late List<String> requests;
  late List<Object?> answers;

  /// The wall clock is the fake time plus [shift] (the tests move it).
  late Duration shift;
  var limitAnswer = false;

  /// The next [failResults] `/result` requests fail with a network error;
  /// with [hangResult], the next one never answers.
  var failResults = 0;
  var hangResult = false;
  var hangWithdraw = false;
  var failWithdraw = false;
  var hangRevoke = false, failRevoke = false;
  var separateWithdrawal = false, pollingClosed = false, cleanupClosed = false;
  Completer<void>? holdAnswer;

  /// How many requests had been made when the offer came back with 200.
  int? offerOkAt;

  WebGateController start(FakeAsync async) {
    Future<SyncResponse> sendRequest(
      String method,
      Uri uri, {
      Object? body,
      Map<String, String> headers = const {},
    }) {
      requests.add('$method ${uri.path.split('/').last}');
      if (uri.path.endsWith('/withdraw')) {
        if (hangWithdraw) return Completer<SyncResponse>().future;
        if (failWithdraw) return Future.error(StateError('offline'));
      }
      if (uri.path.endsWith('/revoke')) {
        if (hangRevoke) return Completer<SyncResponse>().future;
        if (failRevoke) return Future.error(StateError('offline'));
      }
      if (uri.path.endsWith('/result')) {
        if (hangResult) {
          hangResult = false;
          return Completer<SyncResponse>().future;
        }
        if (failResults > 0) {
          failResults--;
          return Future.error(
            const SyncTransportException(SyncFailure.network, 'corte'),
          );
        }
      }
      if (uri.path.endsWith('/answer')) {
        answers.add(jsonEncode(body));
        // The Worker refuses it before reading it, like its rate limiter.
        if (limitAnswer) {
          limitAnswer = false;
          return Future.value(_limited(5));
        }
      }
      final hold = holdAnswer;
      if (hold != null && uri.path.endsWith('/answer')) {
        holdAnswer = null;
        return hold.future.then(
          (_) => h.worker.send(method, uri, body: body, headers: headers),
        );
      }
      return h.worker.send(method, uri, body: body, headers: headers).then((r) {
        if (uri.path.endsWith('/offer') && r.status == 200) {
          offerOkAt ??= requests.length;
        }
        return r;
      });
    }

    SyncV2Client? client;
    void Function()? closePolling;
    SyncV2Client network() {
      if (client != null) return client!;
      // Like the bootstrap, restart closes the old client and lazily opens a
      // new one. Each client keeps its own closed state for late requests.
      var closed = false;
      pollingClosed = false;
      closePolling = () {
        closed = pollingClosed = true;
        client = null;
      };
      return client = SyncV2Client(
        base: Uri.parse('https://sync.test'),
        sendRequest: (method, uri, {body, headers = const {}}) {
          if (closed) return Future.error(StateError('polling closed'));
          return sendRequest(method, uri, body: body, headers: headers);
        },
      );
    }

    final next = WebGateController(
      vault: VaultService(
        store: MemoryVaultStore(),
        guard: GuardClient(
          base: Uri.parse('https://sync.test'),
          send: h.worker.send,
        ),
        crypto: FastTestCrypto(),
        persist: () async => false,
      ),
      platform: FakeSessionPlatform(FakeLockHub()),
      transport: network,
      cancelTransport: separateWithdrawal ? () => closePolling?.call() : null,
      withdrawInvite: separateWithdrawal
          ? (
              inviteId, {
              required credential,
              required onAlreadyApproved,
            }) async {
              final cleanup = SyncV2Client(
                base: Uri.parse('https://sync.test'),
                sendRequest: sendRequest,
              );
              try {
                final result = await cleanup
                    .withdrawInvite(inviteId, credential: credential)
                    .timeout(const Duration(seconds: 2));
                if (result == V2InviteWithdrawal.alreadyApproved) {
                  await onAlreadyApproved(cleanup);
                }
                return result;
              } finally {
                cleanupClosed = true;
              }
            }
          : null,
      createContainer: (_) {},
      disposeContainer: () {},
      pairingNow: () =>
          DateTime.utc(2026, 11, 16, 12).add(async.elapsed + shift),
      pairingElapsed: () => async.elapsed,
      pairingPacer: () =>
          InvitePollPacer(random: Random(3), elapsed: () => async.elapsed),
    );
    _drive(async, next.initialize());
    expect(next.view, isA<WebGateConnect>());
    return next;
  }

  void setUpAll(FakeAsync async, {bool separate = false}) {
    requests = [];
    answers = [];
    shift = Duration.zero;
    limitAnswer = false;
    offerOkAt = null;
    failResults = 0;
    hangResult = false;
    hangWithdraw = false;
    failWithdraw = false;
    hangRevoke = failRevoke = false;
    separateWithdrawal = separate;
    pollingClosed = cleanupClosed = false;
    holdAnswer = null;
    h = WebHarness();
    _drive(async, h.setup(approve: false));
    h.guest.cancel();
    requests.clear();
    gate = start(async);
  }

  PairingV2Host scan(FakeAsync async) => _drive(
    async,
    PairingV2Host.start(
      transport: h.client,
      local: h.phone,
      lock: V2FamilyLock(),
      web: gate.guest!.qr,
      guestPerson: 'nora',
    ),
  );

  void close(FakeAsync async) {
    unawaited(gate.close());
    async.flushMicrotasks();
    // Closed: no poll is left behind.
    requests.clear();
    async.elapse(const Duration(seconds: 70));
    expect(requests, isEmpty);
  }

  for (final action in [
    'reject',
    'restart',
    'watchdog',
    'expiry',
    'close',
    'cancel',
  ]) {
    test(
      '$action withdraws exactly once after answer and never waits for HTTP',
      () {
        fakeAsync((async) {
          setUpAll(async);
          final host = scan(async);
          async.elapse(const Duration(seconds: 3));
          _drive(async, host.poll());
          async.elapse(const Duration(seconds: 3));
          expect(gate.view, isA<WebGateComparing>());
          hangWithdraw = true;
          requests.clear();
          switch (action) {
            case 'reject':
              _drive(async, gate.rejectCode());
            case 'restart':
              _drive(async, gate.restartPairing());
            case 'watchdog':
              _drive(async, gate.confirmCode());
              hangResult = true;
              async.elapse(const Duration(seconds: 35));
              failResults = 3;
              async.elapse(const Duration(seconds: 15));
            case 'expiry':
              shift = const Duration(minutes: 11);
              _drive(async, gate.checkPairing());
            case 'close':
              unawaited(gate.close());
              async.flushMicrotasks();
            case 'cancel':
              gate.session.lock();
              async.flushMicrotasks();
          }
          expect(requests.where((r) => r == 'POST withdraw'), hasLength(1));
          if (action == 'restart') {
            expect(gate.view, isA<WebGateConnect>());
          } else if (action != 'close' && action != 'cancel') {
            expect(gate.view, isA<WebGateConnectFailed>());
          }
          // Even a stuck withdrawal times out without an unhandled exception.
          async.elapse(const Duration(seconds: 3));
          expect(requests.where((r) => r == 'POST withdraw'), hasLength(1));
          if (action != 'close') close(async);
        });
      },
    );
  }

  test('withdrawal failure never replaces the mismatch message; no answer means no withdrawal', () {
    fakeAsync((async) {
      setUpAll(async);
      _drive(async, gate.rejectCode());
      expect(requests.where((r) => r == 'POST withdraw'), isEmpty);
      _drive(async, gate.restartPairing());
      final host = scan(async);
      async.elapse(const Duration(seconds: 3));
      _drive(async, host.poll());
      async.elapse(const Duration(seconds: 3));
      failWithdraw = true;
      _drive(async, gate.rejectCode());
      async.flushMicrotasks();
      expect(
        (gate.view as WebGateConnectFailed).reason,
        WebConnectFailure.codeMismatch,
      );
      expect(requests.where((r) => r == 'POST withdraw'), hasLength(1));
      close(async);
    });
  });

  test('delivered withdrawal removes the invitation seen by the phone', () {
    fakeAsync((async) {
      setUpAll(async);
      final host = scan(async);
      async.elapse(const Duration(seconds: 3));
      _drive(async, host.poll());
      async.elapse(const Duration(seconds: 3));
      _drive(async, gate.rejectCode());
      Object? error;
      _drive(
        async,
        host.ensureAlive().catchError((Object e) {
          error = e;
        }),
      );
      expect(error, isA<InviteGoneException>());
      close(async);
    });
  });

  for (final failure in [
    'none',
    'result error',
    'result timeout',
    'result pending',
    'result gone',
    'result malformed',
    'revoke error',
    'revoke timeout',
  ]) {
    test(
      'approval wins: $failure never blocks cancellation with a closed polling client',
      () {
        fakeAsync((async) {
          setUpAll(async, separate: true);
          final host = scan(async);
          async.elapse(const Duration(seconds: 3));
          _drive(async, host.poll());
          async.elapse(const Duration(seconds: 3));
          expect(gate.view, isA<WebGateComparing>());
          _drive(async, host.confirm(confirmedPersonId: 'nora'));
          // Phone approval alone leaves the unconfirmed comparison in place.
          async.elapse(const Duration(seconds: 5));
          expect(gate.view, isA<WebGateComparing>());
          expect((gate.view as WebGateComparing).confirmed, isFalse);
          expect(pollingClosed, isFalse);
          expect(requests.where((r) => r == 'POST withdraw'), isEmpty);
          expect(requests.where((r) => r == 'POST revoke'), isEmpty);
          final webId = h.worker
              .devicesOf(kV2Sync)
              .keys
              .singleWhere((id) => id != h.phone.identity.deviceId);
          final guest = gate.guest!;
          switch (failure) {
            case 'result error':
              failResults = 1;
            case 'result timeout':
              hangResult = true;
            case 'revoke error':
              failRevoke = true;
            case 'revoke timeout':
              hangRevoke = true;
            case 'result pending':
            case 'result gone':
            case 'result malformed':
              h.worker.tamper = (method, uri, response) {
                if (!uri.path.endsWith('/result')) return response;
                return SyncResponse(
                  failure == 'result pending'
                      ? 202
                      : failure == 'result gone'
                      ? 404
                      : 200,
                  const {},
                  Uint8List.fromList(
                    utf8.encode(
                      failure == 'result pending'
                          ? '{"status":"pending","reveal":null}'
                          : '{}',
                    ),
                  ),
                );
              };
          }
          requests.clear();
          var cancelled = false;
          unawaited(gate.rejectCode().then((_) => cancelled = true));
          async.flushMicrotasks();
          expect(
            cancelled,
            isTrue,
            reason: 'cancellation never waits for HTTP',
          );
          expect(pollingClosed, isTrue);
          expect(
            (gate.view as WebGateConnectFailed).reason,
            WebConnectFailure.codeMismatch,
          );
          // The 409 has not come back yet: the cleanup runs on its own.
          expect(guest.approved, isFalse);
          async.elapse(const Duration(seconds: 5));
          expect(cleanupClosed, isTrue);
          expect(guest.approved, isTrue);
          expect(
            (gate.view as WebGateConnectFailed).reason,
            WebConnectFailure.codeMismatch,
          );
          expect(requests, [
            'POST withdraw',
            'GET result',
            if (failure == 'none' || failure.startsWith('revoke'))
              'POST revoke',
          ]);
          expect(h.worker.devicesOf(kV2Sync)[webId], failure == 'none');
          expect(
            h.worker.devicesOf(kV2Sync)[h.phone.identity.deviceId],
            isFalse,
          );
          close(async);
        });
      },
    );
  }

  test(
    'a restart can compare again while the old approval cleanup times out',
    () {
      fakeAsync((async) {
        setUpAll(async, separate: true);
        final host = scan(async);
        async.elapse(const Duration(seconds: 3));
        _drive(async, host.poll());
        async.elapse(const Duration(seconds: 3));
        expect(gate.view, isA<WebGateComparing>());
        _drive(async, host.confirm(confirmedPersonId: 'nora'));
        final oldGuest = gate.guest!;
        hangResult = true;
        _drive(async, gate.restartPairing());
        expect(gate.view, isA<WebGateConnect>());
        expect(pollingClosed, isFalse);
        expect(cleanupClosed, isFalse);
        expect(gate.guest!.qr.inviteId, isNot(oldGuest.qr.inviteId));

        final nextHost = scan(async);
        _drive(async, gate.checkPairing());
        _drive(async, nextHost.poll());
        _drive(async, gate.checkPairing());
        expect(cleanupClosed, isFalse);
        final comparison = gate.view;
        expect(comparison, isA<WebGateComparing>());
        async.elapse(const Duration(seconds: 3));
        expect(cleanupClosed, isTrue);
        expect(oldGuest.approved, isTrue);
        expect(gate.view, same(comparison));
        expect((gate.view as WebGateComparing).confirmed, isFalse);
        expect(pollingClosed, isFalse);
        expect(requests.where((r) => r == 'POST withdraw'), hasLength(1));
        expect(requests.where((r) => r == 'POST revoke'), isEmpty);
        close(async);
      });
    },
  );

  test(
    'a late accepted answer retries a withdrawal that saw no answer yet',
    () {
      fakeAsync((async) {
        setUpAll(async);
        final host = scan(async);
        final hold = holdAnswer = Completer<void>();
        async.elapse(const Duration(seconds: 3));
        expect(requests.where((r) => r == 'POST answer'), hasLength(1));
        _drive(async, gate.rejectCode());
        async.flushMicrotasks();
        expect(requests.where((r) => r == 'POST withdraw'), hasLength(1));
        hold.complete();
        async.elapse(const Duration(milliseconds: 10));
        expect(requests.where((r) => r == 'POST withdraw'), hasLength(2));
        Object? error;
        _drive(
          async,
          host.ensureAlive().catchError((Object e) {
            error = e;
          }),
        );
        expect(error, isA<InviteGoneException>());
        expect(
          (gate.view as WebGateConnectFailed).reason,
          WebConnectFailure.codeMismatch,
        );
        close(async);
      });
    },
  );

  test('1: after a 429, a second «They match» does not bring the poll '
      'forward; the poll comes when Retry-After ends', () {
    fakeAsync((async) {
      setUpAll(async);
      final host = scan(async);
      // The web reads the offer and answers on its own (1-2 s polls).
      async.elapse(const Duration(seconds: 3));
      _drive(async, host.poll()); // reveal
      async.elapse(const Duration(seconds: 3));
      expect(gate.view, isA<WebGateComparing>());
      // The approval poll right after «They match» gets a 429 of 60 s.
      h.worker.rateLimitNext = 60;
      _drive(async, gate.confirmCode());
      async.elapse(const Duration(milliseconds: 10));
      expect(gate.nextPairingPoll, const Duration(seconds: 60));
      requests.clear();
      _drive(async, gate.confirmCode()); // pressed again
      async.elapse(const Duration(seconds: 58));
      expect(requests, isEmpty, reason: 'nothing before Retry-After ends');
      async.elapse(const Duration(seconds: 3));
      expect(requests, contains('GET result'));
      expect((gate.view as WebGateComparing).confirmed, isTrue);
      close(async);
    });
  });

  test('5: a 429 on /answer retries the same answer and never asks for the '
      'offer again', () {
    fakeAsync((async) {
      setUpAll(async);
      limitAnswer = true;
      final host = scan(async);
      // Offer + answer (429), then the retry after Retry-After.
      async.elapse(const Duration(seconds: 10));
      // The request that got the 200 offer is the last offer request: the
      // answer (429) and its retry come after it, with no offer in between.
      expect(offerOkAt, isNotNull);
      final after = requests.sublist(offerOkAt!);
      expect(after.where((r) => r == 'GET offer'), isEmpty);
      expect(after.where((r) => r == 'POST answer'), hasLength(2));
      expect(answers, hasLength(2));
      expect(answers[1], answers[0], reason: 'the same answer and transcript');
      _drive(async, host.poll());
      async.elapse(const Duration(seconds: 3));
      expect(gate.view, isA<WebGateComparing>());
      close(async);
    });
  });

  test('a: no offer yet: 1-2 s for two minutes, then 3-4 s', () {
    fakeAsync((async) {
      setUpAll(async);
      async.elapse(const Duration(seconds: 30));
      expect(
        gate.nextPairingPoll!.inMilliseconds,
        inInclusiveRange(1000, 2000),
      );
      async.elapse(const Duration(minutes: 2));
      expect(
        gate.nextPairingPoll!.inMilliseconds,
        inInclusiveRange(3000, 4000),
      );
      close(async);
    });
  });

  test('b: a long Retry-After never goes past the QR lifetime', () {
    fakeAsync((async) {
      setUpAll(async);
      shift = const Duration(minutes: 9, seconds: 59, milliseconds: 500);
      h.worker.rateLimitNext = 60;
      _drive(async, gate.checkPairing());
      expect(
        gate.nextPairingPoll,
        lessThanOrEqualTo(const Duration(milliseconds: 510)),
      );
      // When it fires, the QR has expired.
      async.elapse(const Duration(seconds: 1));
      expect(
        (gate.view as WebGateConnectFailed).reason,
        WebConnectFailure.expired,
      );
      close(async);
    });
  });

  test('6: moving the system clock back an hour does not stall the polls', () {
    fakeAsync((async) {
      setUpAll(async);
      async.elapse(const Duration(seconds: 5));
      shift = const Duration(hours: -1);
      requests.clear();
      async.elapse(const Duration(seconds: 5));
      expect(requests.where((r) => r == 'GET offer').length, greaterThan(1));
      expect(
        gate.nextPairingPoll,
        lessThanOrEqualTo(const Duration(seconds: 2)),
      );
      close(async);
    });
  });

  test('6: with a 429 deadline and requests in the window, moving the wall '
      'clock back or forward keeps the accounting and the backoff', () {
    fakeAsync((async) {
      setUpAll(async);
      final host = scan(async);
      async.elapse(const Duration(seconds: 3));
      _drive(async, host.poll()); // reveal
      async.elapse(const Duration(seconds: 3));
      h.worker.rateLimitNext = 30;
      _drive(async, gate.confirmCode());
      async.elapse(const Duration(milliseconds: 10));
      final pacer = gate.guest!.pacer;
      (int, Duration) state() => (pacer.inWindow, pacer.retryRemaining);
      final before = state();
      expect(before.$1, greaterThan(2), reason: 'offer, answer, code, result');
      expect(before.$2, greaterThan(const Duration(seconds: 29)));
      for (final moved in [
        const Duration(hours: -1),
        const Duration(minutes: 5),
      ]) {
        shift = moved;
        async.flushMicrotasks();
        expect(state(), before, reason: 'wall clock moved by $moved');
      }
      shift = Duration.zero;
      requests.clear();
      async.elapse(const Duration(seconds: 29));
      expect(requests, isEmpty, reason: 'the backoff is not shortened');
      async.elapse(const Duration(seconds: 2));
      expect(requests, contains('GET result'));
      close(async);
    });
  });

  test('QA: the phone cancels while the code is shown and NOT confirmed; '
      'the web polls every 3-4 s and says «cancelled» within seconds', () {
    fakeAsync((async) {
      setUpAll(async);
      final host = scan(async);
      async.elapse(const Duration(seconds: 3));
      _drive(async, host.poll()); // reveal
      async.elapse(const Duration(seconds: 3));
      expect(gate.view, isA<WebGateComparing>());
      expect((gate.view as WebGateComparing).confirmed, isFalse);
      requests.clear();
      async.elapse(const Duration(seconds: 10));
      // Gentle liveness polls while comparing.
      final polls = requests.where((r) => r == 'GET result').length;
      expect(polls, inInclusiveRange(2, 4));
      expect(
        gate.nextPairingPoll!.inMilliseconds,
        inInclusiveRange(3000, 4000),
      );
      _drive(async, host.cancel());
      async.elapse(const Duration(seconds: 5));
      expect(
        (gate.view as WebGateConnectFailed).reason,
        WebConnectFailure.cancelled,
      );
      close(async);
    });
  });

  test('while comparing, two transient errors or a watchdog timeout are '
      'retried; a third failure in a row ends the pairing', () {
    fakeAsync((async) {
      setUpAll(async);
      final host = scan(async);
      async.elapse(const Duration(seconds: 3));
      _drive(async, host.poll()); // reveal
      async.elapse(const Duration(seconds: 3));
      expect(gate.view, isA<WebGateComparing>());
      // A liveness poll that never answers: the 30 s watchdog, tolerated.
      hangResult = true;
      async.elapse(const Duration(seconds: 40));
      expect(gate.view, isA<WebGateComparing>());
      // Then one network error, tolerated; then a success resets the count.
      failResults = 1;
      async.elapse(const Duration(seconds: 5));
      expect(gate.view, isA<WebGateComparing>());
      async.elapse(const Duration(seconds: 5));
      // Three in a row: the pairing fails with «network».
      failResults = 3;
      async.elapse(const Duration(seconds: 15));
      expect(
        (gate.view as WebGateConnectFailed).reason,
        WebConnectFailure.network,
      );
      close(async);
    });
  });
}
