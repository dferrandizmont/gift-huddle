// Los sondeos del emparejamiento en el móvil (1.0.2): con la pantalla abierta
// preguntan a 1-2 s (aquí, con tiempos cortos) y se paran en el acto al
// cancelar, al volver a empezar y al cerrar.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/prefs/shared_preferences_provider.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/sync/application/pairing_v2_controller.dart';
import 'package:regalos/features/sync/application/sync_controller.dart';
import 'package:regalos/features/sync/data/sync_config.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';

import '../helpers/fake_sync_server.dart';
import '../helpers/fake_worker_v2.dart';
import '../helpers/memory_stores.dart';
import '../helpers/pump_app.dart';
import 'sync_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSyncServer v1;
  late FakeWorkerV2 worker;
  final requests = <String>[];

  /// If set, the next `/result` request waits for it.
  Completer<void>? holdResult;

  setUp(() {
    v1 = FakeSyncServer();
    worker = FakeWorkerV2();
    requests.clear();
    holdResult = null;
  });

  SyncV2Transport counting() => SyncV2Client(
    base: Uri.parse('https://sync.test'),
    sendRequest: (method, uri, {body, headers = const {}}) async {
      requests.add('$method ${uri.path}');
      final hold = holdResult;
      if (hold != null && uri.path.endsWith('/result')) {
        holdResult = null;
        await hold.future;
      }
      return worker.send(method, uri, body: body, headers: headers);
    },
  );

  // Without automatic polls: each step is driven by the test.
  const manual = SyncTiming(
    debounce: Duration(days: 1),
    invitePoll: Duration(days: 1),
    inviteHostPoll: Duration(days: 1),
  );

  Future<FakePhone> phone({SyncTiming timing = kFastTiming}) async {
    final p = FakePhone(
      prefs: await mockPrefs(),
      syncHost: null,
      extraOverrides: [
        syncHostProvider.overrideWithValue(kTestHost),
        invitationOriginProvider.overrideWithValue(''),
        syncTransportProvider.overrideWithValue(v1.connect()),
        syncV2TransportProvider.overrideWithValue(counting()),
        syncTimingProvider.overrideWithValue(timing),
      ],
    );
    addTearDown(p.dispose);
    p.container.read(syncControllerProvider);
    p.container.read(sharedPreferencesProvider);
    await p.container.read(familyControllerProvider.future);
    return p;
  }

  Future<FakePhone> owner({SyncTiming timing = kFastTiming}) async {
    final a = await phone(timing: timing);
    final fam = a.container.read(familyControllerProvider.notifier);
    await fam.createFamily(deviceName: 'Aritz');
    await fam.upsertRecipient(
      const Recipient(id: 'nora', name: 'Nora', colorIndex: 1, archived: false),
    );
    return a;
  }

  int invitePolls(String inviteId) =>
      requests.where((r) => r.endsWith('/invites/$inviteId')).length;

  test('the host polls by itself while waiting and stops on cancel, restart '
      'and close', () async {
    final a = await owner();
    final host = a.container.read(pairingV2HostProvider.notifier);
    await host.start();
    expect(
      a.container.read(pairingV2HostProvider).phase,
      PairingV2HostPhase.waiting,
    );
    final link = a.container.read(pairingV2HostProvider).link!;
    final first = link.substring(link.indexOf('#') + 1);
    await eventually(() => invitePolls(first) >= 3, reason: 'polls');
    await eventually(() => host.polling, reason: 'a poll is scheduled');

    await host.cancel();
    expect(host.polling, isFalse);
    final afterCancel = invitePolls(first);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(invitePolls(first), afterCancel, reason: 'no poll after cancel');

    await host.start();
    final again = a.container.read(pairingV2HostProvider).link!;
    final second = again.substring(again.indexOf('#') + 1);
    await eventually(() => invitePolls(second) >= 1, reason: 'polls again');
    // Starting over stops the old run: only the new invitation is polled.
    final old = invitePolls(first);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(invitePolls(first), old);

    a.container.dispose();
    final closed = requests.length;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(requests.length, closed, reason: 'no poll after close');
  });

  test(
    'the guest polls for the code at the fast rate and stops on cancel',
    () async {
      final a = await owner();
      final b = await phone();
      final host = a.container.read(pairingV2HostProvider.notifier);
      await host.start();
      final link = a.container.read(pairingV2HostProvider).link!;
      final id2 = link.substring(link.indexOf('#') + 1);
      final guest = b.container.read(pairingV2GuestProvider.notifier);
      await guest.begin(id2);
      await guest.choosePerson(null);
      await eventually(() => guest.polling, reason: 'a poll is scheduled');
      await eventually(
        () =>
            b.container.read(pairingV2GuestProvider).phase ==
            PairingV2GuestPhase.compare,
        reason: 'the code arrives without waiting 4 s',
        timeout: const Duration(seconds: 3),
      );
      guest.confirmCode();
      await eventually(() => guest.polling, reason: 'a poll is scheduled');
      guest.cancel();
      expect(guest.polling, isFalse);
      final results = requests.where((r) => r.endsWith('/result')).length;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(requests.where((r) => r.endsWith('/result')).length, results);
    },
  );

  test('item 2: a late answer to an old attempt does not stop or reset the '
      'polls of the new one', () async {
    final a = await owner(timing: manual);
    final c = await owner(timing: manual);
    final b = await phone(timing: manual);
    String inviteOf(FakePhone host) {
      final link = host.container.read(pairingV2HostProvider).link!;
      return link.substring(link.indexOf('#') + 1);
    }

    await a.container.read(pairingV2HostProvider.notifier).start();
    final guest = b.container.read(pairingV2GuestProvider.notifier);
    await guest.begin(inviteOf(a));
    await guest.choosePerson(null);
    // Attempt A asks for the code and its answer is held back.
    final hold = holdResult = Completer<void>();
    final stale = guest.pollNow();
    await Future<void>.delayed(Duration.zero);
    guest.cancel();
    // Attempt B, with another family's invitation.
    await c.container.read(pairingV2HostProvider.notifier).start();
    await guest.begin(inviteOf(c));
    await guest.choosePerson(null);
    expect(guest.polling, isTrue);
    expect(
      b.container.read(pairingV2GuestProvider).phase,
      PairingV2GuestPhase.waitingCode,
    );
    // A's answer arrives now (no code yet): it must not touch B.
    hold.complete();
    await stale;
    expect(guest.polling, isTrue, reason: "B's poll is still scheduled");
    expect(
      b.container.read(pairingV2GuestProvider).phase,
      PairingV2GuestPhase.waitingCode,
    );
    guest.cancel();
  });
}
