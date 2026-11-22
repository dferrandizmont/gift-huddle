// 1.0.6 (la revisión, 4): aprobar una web pasa por el mismo intento obligatorio de
// poner en secreto los regalos de su persona que un móvil, y la web hereda la
// persona del móvil que la conecta si no se elige otra.
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/prefs/shared_preferences_provider.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/sync/application/pairing_v2_controller.dart';
import 'package:regalos/features/sync/application/pairing_v2_flow.dart';
import 'package:regalos/features/sync/application/sync_controller.dart';
import 'package:regalos/features/sync/data/sync_config.dart';
import 'package:regalos/features/web_device/application/web_pairing_guest.dart';

import '../helpers/fake_sync_server.dart';
import '../helpers/fake_worker_v2.dart';
import '../helpers/memory_stores.dart';
import '../helpers/pump_app.dart' show mockPrefs;
import 'sync_harness.dart';

Future<(FakePhone, FakeWorkerV2)> _phone() async {
  final worker = FakeWorkerV2();
  final a = FakePhone(
    prefs: await mockPrefs(),
    syncHost: null,
    extraOverrides: [
      syncHostProvider.overrideWithValue(kTestHost),
      invitationOriginProvider.overrideWithValue(''),
      syncTransportProvider.overrideWithValue(FakeSyncServer().connect()),
      syncV2TransportProvider.overrideWithValue(worker.client()),
      syncTimingProvider.overrideWithValue(kFastTiming),
    ],
  );
  a.container.read(syncControllerProvider);
  a.container.read(sharedPreferencesProvider);
  final fam = a.container.read(familyControllerProvider.notifier);
  await a.container.read(familyControllerProvider.future);
  await fam.createFamily(deviceName: 'Aritz');
  for (final (id, name) in [('aritz', 'Aritz'), ('nora', 'Nora')]) {
    await fam.upsertRecipient(
      Recipient(id: id, name: name, colorIndex: 0, archived: false),
    );
  }
  await fam.setSelfRecipient('aritz');
  return (a, worker);
}

Future<String> _pair(FakePhone a, FakeWorkerV2 worker, String? person) async {
  final web = await WebPairingGuest.create(transport: worker.client());
  final host = a.container.read(pairingV2HostProvider.notifier);
  await host.startWeb(
    web.qr.url(origin: kWebPairingOrigin),
    guestPerson: person,
  );
  await web.poll();
  await eventually(
    () =>
        a.container.read(pairingV2HostProvider).phase ==
        PairingV2HostPhase.compare,
    reason: 'the phone shows the code',
  );
  await web.poll();
  web.confirmCode();
  await host.confirm();
  if (a.container.read(pairingV2HostProvider).phase ==
      PairingV2HostPhase.confirmPerson) {
    await host.confirmPerson();
  }
  expect(
    a.container.read(pairingV2HostProvider).phase,
    PairingV2HostPhase.done,
  );
  await web.poll();
  return web.personName;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('una web para Nora pone en secreto los regalos de Nora antes de '
      'aprobarla', () async {
    final (a, worker) = await _phone();
    addTearDown(a.dispose);
    final fam = a.container.read(familyControllerProvider.notifier);
    await fam.upsertGift(
      Gift(
        id: 'g1',
        recipientId: 'nora',
        title: 'Bufanda',
        status: GiftStatus.idea,
        rawStatus: 'idea',
        surprise: false,
        year: 2026,
      ),
    );
    expect(await _pair(a, worker, 'nora'), 'Nora');
    final doc = (await a.container.read(familyControllerProvider.future)).doc;
    expect(publishedPolicy(doc, 'nora')?.hideOwnGifts, isTrue);
    // El regalo ya no está a la vista en el común.
    expect(doc.record(Collections.gifts, 'g1')?.isDeleted ?? true, isTrue);
  });

  test('sin elegir, la web hereda la persona del móvil y no protege a nadie',
      () async {
    final (a, worker) = await _phone();
    addTearDown(a.dispose);
    expect(await _pair(a, worker, null), 'Aritz');
    final doc = (await a.container.read(familyControllerProvider.future)).doc;
    expect(publishedPolicy(doc, 'aritz'), isNull);
  });
}
