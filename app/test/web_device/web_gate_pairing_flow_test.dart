// La web mientras se empareja (1.0.2): «Coinciden» vuelve en el acto con el
// estado confirmado, un sondeo colgado acaba en un fallo claro, la invitación
// borrada antes de caducar es «cancelado» y después «caducado», después de la
// oferta no se vuelve a pedir, los sondeos van a 1-2 s dentro del
// presupuesto de la invitación y todos los temporizadores se paran.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/sync/application/invite_poll_pacer.dart';
import 'package:regalos/features/sync/application/pairing_v2_flow.dart';
import 'package:regalos/features/sync/application/v2_family_lock.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';
import 'package:regalos/features/web_device/application/vault_service.dart';
import 'package:regalos/features/web_device/application/web_gate_controller.dart';
import 'package:regalos/features/web_device/data/guard_client.dart';
import 'package:regalos/features/web_device/data/vault_store.dart';
import 'package:regalos/features/web_device/presentation/web_gate_model.dart';

import 'test_support.dart';
import 'web_engine_support.dart';

void main() {
  late WebHarness h;
  late WebGateController gate;
  var closed = false;
  final requests = <String>[];
  final views = <WebGateView>[];

  /// Paths whose next request hangs until the completer is completed.
  final hang = <String, Completer<void>>{};
  var time = DateTime.utc(2026, 11, 16, 12);

  Future<WebGateController> start({
    Duration watchdog = const Duration(seconds: 30),
    InvitePollPacer Function()? pacer,
  }) async {
    final client = SyncV2Client(
      base: Uri.parse('https://sync.test'),
      sendRequest: (method, uri, {body, headers = const {}}) async {
        requests.add('$method ${uri.path.split('/').last}');
        for (final entry in hang.entries.toList()) {
          if (uri.path.endsWith('/${entry.key}')) await entry.value.future;
        }
        return h.worker.send(method, uri, body: body, headers: headers);
      },
    );
    final vault = VaultService(
      store: MemoryVaultStore(),
      guard: GuardClient(
        base: Uri.parse('https://sync.test'),
        send: h.worker.send,
      ),
      crypto: FastTestCrypto(),
      persist: () async => false,
    );
    final next = WebGateController(
      vault: vault,
      platform: FakeSessionPlatform(FakeLockHub()),
      transport: () => client,
      createContainer: (_) {},
      disposeContainer: () {},
      pairingWatchdog: watchdog,
      pairingNow: () => time,
      // Manual by default: the tests drive each poll unless they say otherwise.
      pairingPacer:
          pacer ?? () => InvitePollPacer(base: const Duration(hours: 1)),
    );
    next.addListener(() => views.add(next.view));
    await next.initialize();
    expect(next.view, isA<WebGateConnect>());
    return next;
  }

  setUp(() async {
    h = WebHarness();
    await h.setup(approve: false);
    h.guest.cancel();
    requests.clear();
    views.clear();
    hang.clear();
    closed = false;
    time = DateTime.utc(2026, 11, 16, 12);
  });
  tearDown(() async {
    for (final c in hang.values) {
      if (!c.isCompleted) c.complete();
    }
    if (!closed) await gate.close();
  });

  Future<PairingV2Host> reachComparison() async {
    final host = await PairingV2Host.start(
      transport: h.client,
      local: h.phone,
      lock: V2FamilyLock(),
      web: gate.guest!.qr,
      guestPerson: 'nora',
    );
    await gate.checkPairing(); // offer + answer
    await host.poll(); // reveal
    await gate.checkPairing(); // code
    expect(gate.view, isA<WebGateComparing>());
    return host;
  }

  test(
    '«Coinciden» returns at once with the confirmed state, even if the '
    'approval poll hangs, and never shows the code unconfirmed again',
    () async {
      gate = await start(
        pacer: () => InvitePollPacer(
          base: const Duration(milliseconds: 5),
          budget: null,
        ),
      );
      final host = await reachComparison();
      hang['result'] = Completer<void>();
      final code = (gate.view as WebGateComparing).code;
      await gate.confirmCode().timeout(const Duration(seconds: 1));
      expect(
        gate.view,
        isA<WebGateComparing>()
            .having((v) => v.code, 'code', code)
            .having((v) => v.confirmed, 'confirmed', isTrue),
      );
      final confirmedAt = views.length - 1;
      // The poll starts on its own and waits on the server.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(requests.last, 'GET result');
      hang['result']!.complete();
      hang.remove('result');
      await host.confirm(confirmedPersonId: 'nora');
      for (var i = 0; i < 100 && gate.view is! WebGateChoosePin; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(gate.view, isA<WebGateChoosePin>());
      for (final v in views.sublist(confirmedAt)) {
        if (v is WebGateComparing) expect(v.confirmed, isTrue);
      }
    },
  );

  test('a poll that does not finish within the watchdog ends in a network '
      'failure instead of hanging', () async {
    gate = await start(watchdog: const Duration(milliseconds: 100));
    await reachComparison();
    hang['result'] = Completer<void>();
    await gate.confirmCode();
    await gate.checkPairing();
    expect(
      gate.view,
      isA<WebGateConnectFailed>().having(
        (v) => v.reason,
        'reason',
        WebConnectFailure.network,
      ),
    );
    expect(gate.guest, isNull);
    expect(gate.nextPairingPoll, isNull);
  });

  test('the phone cancels before the QR expires: «cancelled»', () async {
    gate = await start();
    final host = await reachComparison();
    await gate.confirmCode();
    await host.cancel();
    await gate.checkPairing();
    expect(
      gate.view,
      isA<WebGateConnectFailed>().having(
        (v) => v.reason,
        'reason',
        WebConnectFailure.cancelled,
      ),
    );
  });

  test('cancelled while the code is shown and not confirmed: seen at the '
      'next liveness poll', () async {
    gate = await start();
    final host = await reachComparison();
    await host.cancel();
    final before = requests.length;
    await gate.checkPairing();
    expect(requests.sublist(before), ['GET result', 'POST withdraw']);
    expect(
      (gate.view as WebGateConnectFailed).reason,
      WebConnectFailure.cancelled,
    );
  });

  test('after the QR lifetime the same disappearance is «expired»', () async {
    gate = await start();
    final host = await reachComparison();
    await gate.confirmCode();
    await host.cancel();
    time = time.add(const Duration(minutes: 10));
    await gate.checkPairing();
    expect(
      (gate.view as WebGateConnectFailed).reason,
      WebConnectFailure.expired,
    );
  });

  test('once the offer is read the web never asks for it again', () async {
    gate = await start();
    await gate.checkPairing(); // not yet
    await gate.checkPairing(); // not yet
    expect(requests, ['GET offer', 'GET offer']);
    final host = await reachComparison();
    await gate.confirmCode();
    await host.confirm(confirmedPersonId: 'nora');
    await gate.checkPairing();
    expect(gate.view, isA<WebGateChoosePin>());
    final offers = requests.where((r) => r == 'GET offer').length;
    // Two before the phone scanned and the one that found it.
    expect(offers, 3);
  });

  test('polls on their own at the pacer rate and stay within the '
      'invitation budget', () async {
    gate = await start(
      pacer: () => InvitePollPacer(
        base: const Duration(milliseconds: 2),
        budget: 6,
        window: const Duration(minutes: 1),
      ),
    );
    await reachComparison();
    await gate.confirmCode();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // Offer, answer, code and then approval polls until the budget is spent:
    // the next one waits for the oldest to leave the 60 s window.
    expect(requests.where((r) => r == 'GET result').length, greaterThan(1));
    expect(gate.guest!.pacer.inWindow, lessThanOrEqualTo(6));
    expect(gate.nextPairingPoll, greaterThan(const Duration(seconds: 50)));
  });

  test('every timer stops on restart, failure and close', () async {
    gate = await start(
      pacer: () => InvitePollPacer(base: const Duration(milliseconds: 2)),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(requests, isNotEmpty, reason: 'it polls by itself');
    await gate.restartPairing();
    final afterRestart = gate.guest!.qr.inviteId;
    await gate.rejectCode();
    expect(gate.nextPairingPoll, isNull);
    requests.clear();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(requests, isEmpty, reason: 'no poll after a failure');
    await gate.restartPairing();
    expect(gate.guest!.qr.inviteId, isNot(afterRestart));
    await gate.close();
    closed = true;
    requests.clear();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(requests, isEmpty, reason: 'no poll after close');
  });

  test('a 429 waits for Retry-After and then goes on', () async {
    gate = await start();
    h.worker.rateLimitNext = 7;
    await gate.checkPairing();
    expect(gate.view, isA<WebGateConnect>());
    expect(
      gate.nextPairingPoll,
      greaterThanOrEqualTo(const Duration(seconds: 7)),
    );
  });
}
