import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/sync/application/app_sync_v2_local.dart';
import 'package:regalos/features/sync/application/pairing_v2_controller.dart';
import 'package:regalos/features/sync/data/sync_config.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';
import 'package:regalos/features/web_device/application/web_pairing_guest.dart';

import '../helpers/fake_sync_server.dart';
import '../helpers/host_person.dart';
import '../helpers/fake_worker_v2.dart';
import '../helpers/memory_stores.dart';
import '../helpers/pump_app.dart';

// Advances timers as well as microtasks without sleeping in real time. This
// measures scheduling/HTTP delays, not CPU time spent verifying real signatures.
T complete<T>(FakeAsync time, Future<T> future) {
  var done = false;
  late T value;
  Object? error;
  StackTrace? stack;
  future.then(
    (result) {
      value = result;
      done = true;
    },
    onError: (Object e, StackTrace s) {
      error = e;
      stack = s;
      done = true;
    },
  );
  for (var i = 0; i < 3000 && !done; i++) {
    time.flushMicrotasks();
    if (!done) time.elapse(const Duration(milliseconds: 10));
  }
  expect(
    done,
    isTrue,
    reason: 'operation completes within 30 simulated seconds',
  );
  if (error != null) Error.throwWithStackTrace(error!, stack!);
  return value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final busyFamily in [false, true]) {
    test('host reveals in the first poll that sees the web answer '
        '(family lock busy: $busyFamily)', () async {
      final prefs = await mockPrefs();
      fakeAsync((time) {
        final worker = FakeWorkerV2();
        Duration? answerAt, detectedAt, revealAt;
        var detectingPolls = 0;
        var emptyPolls = 0;
        var listRequestsAfterAnswer = 0;
        final transport = SyncV2Client(
          base: Uri.parse('https://sync.test'),
          sendRequest: (method, uri, {body, headers = const {}}) async {
            if (answerAt != null && !uri.path.contains('/invites/')) {
              listRequestsAfterAnswer++;
            }
            if (uri.path.endsWith('/reveal')) revealAt = time.elapsed;
            // Both clients use the real HTTP codec, with 100 ms per request.
            await Future<void>.delayed(const Duration(milliseconds: 100));
            final response = await worker.send(
              method,
              uri,
              body: body,
              headers: headers,
            );
            if (uri.path.endsWith('/answer') && response.status == 201) {
              answerAt = time.elapsed;
            }
            if (method == 'GET' &&
                uri.path.contains('/lists/') &&
                uri.path.contains('/invites/')) {
              if (response.json()['answer'] == null) {
                emptyPolls++;
              } else {
                detectingPolls++;
                detectedAt = time.elapsed;
              }
            }
            return response;
          },
        );
        final phone = FakePhone(
          prefs: prefs,
          syncHost: null,
          extraOverrides: [
            syncHostProvider.overrideWithValue('sync.test'),
            invitationOriginProvider.overrideWithValue(''),
            syncTransportProvider.overrideWithValue(FakeSyncServer().connect()),
            syncV2TransportProvider.overrideWithValue(transport),
            // Use the production 1-2 s cadence, not kFastTiming or pollNow().
            syncTimingProvider.overrideWithValue(
              const SyncTiming(debounce: Duration(days: 1)),
            ),
          ],
        );
        try {
          complete(time, phone.container.read(familyControllerProvider.future));
          final family = phone.container.read(
            familyControllerProvider.notifier,
          );
          complete(time, family.createFamily(deviceName: 'Aritz'));
          complete(
            time,
            family.upsertRecipient(
              const Recipient(
                id: 'nora',
                name: 'Nora',
                colorIndex: 1,
                archived: false,
              ),
            ),
          );
          final web = complete(
            time,
            WebPairingGuest.create(transport: transport),
          );
          complete(time, hostWithPerson(phone));
          final host = phone.container.read(pairingV2HostProvider.notifier);
          complete(time, host.startWeb(web.qr.url(), guestPerson: 'nora'));
          time.elapse(const Duration(milliseconds: 2100));
          expect(emptyPolls, greaterThanOrEqualTo(1));

          final release = Completer<void>();
          Future<void>? held;
          if (busyFamily) {
            held = phone.container
                .read(v2FamilyLockProvider)
                .run(() => release.future);
            time.flushMicrotasks();
          }
          try {
            complete(time, web.poll()); // POST /answer -> 201.
            expect(answerAt, isNotNull);
            expect(revealAt, isNull);
            final deadline = time.elapsed + const Duration(milliseconds: 2300);
            while (phone.container.read(pairingV2HostProvider).phase !=
                    PairingV2HostPhase.compare &&
                time.elapsed < deadline) {
              time.elapse(const Duration(milliseconds: 10));
            }
            expect(detectingPolls, 1);
            expect(
              revealAt,
              detectedAt,
              reason: 'no timer, sync or storage wait before POST /reveal',
            );
            expect(revealAt! - answerAt!, lessThan(const Duration(seconds: 3)));
            expect(listRequestsAfterAnswer, 0);
            expect(
              phone.container.read(pairingV2HostProvider).phase,
              PairingV2HostPhase.compare,
            );
            complete(time, web.poll());
            expect(
              web.code,
              phone.container.read(pairingV2HostProvider).code,
              reason: 'the web verified the nonce commitment',
            );
          } finally {
            release.complete();
            if (held != null) complete(time, held);
          }
        } finally {
          phone.dispose();
          time.flushMicrotasks();
        }
      });
    });
  }
}
