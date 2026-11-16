// Regresión de la 1.0.1 (D): tras quitar la web, Ajustes decía «2 · al día».
// Con el controlador, el registro y el Worker de verdad (los falsos): este
// móvil empareja una web, Ajustes cuenta 2; se quita la web por el mismo
// camino que «Quitar» (`familyDeviceActionsProvider.remove`) y Ajustes pasa a
// «Solo este», sin quedarse con la cuenta vieja.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/prefs/shared_preferences_provider.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/settings/presentation/settings_screen.dart';
import 'package:regalos/features/sync/application/family_device_review.dart';
import 'package:regalos/features/sync/application/family_device_rows.dart';
import 'package:regalos/features/sync/application/pairing_v2_controller.dart';
import 'package:regalos/features/sync/application/pairing_v2_flow.dart';
import 'package:regalos/features/sync/application/sync_controller.dart';
import 'package:regalos/features/sync/data/sync_config.dart';
import 'package:regalos/features/web_device/application/web_pairing_guest.dart';

import '../helpers/fake_sync_server.dart';
import '../helpers/fake_worker_v2.dart';
import '../helpers/memory_stores.dart';
import '../helpers/pump_app.dart';
import '../sync/invite_approval_view_test.dart' show screenApp, phoneSize;
import '../sync/sync_harness.dart';

Finder _row(String value) =>
    find.bySemanticsLabel('Móviles de la familia. $value');

void main() {
  testWidgets('this phone + a web, remove the web: Settings says «Solo este»', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    phoneSize(tester);
    final worker = FakeWorkerV2();
    late FakePhone a;
    late String webId;
    await tester.runAsync(() async {
      a = FakePhone(
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

      // Pair a web for Nora with the real host controller.
      final web = await WebPairingGuest.create(transport: worker.client());
      final host = a.container.read(pairingV2HostProvider.notifier);
      await host.startWeb(
        web.qr.url(origin: kWebPairingOrigin),
        guestPerson: 'nora',
      );
      await web.poll(); // offer + answer
      await eventually(
        () =>
            a.container.read(pairingV2HostProvider).phase ==
            PairingV2HostPhase.compare,
        reason: 'the phone shows the code',
      );
      await web.poll(); // code
      web.confirmCode();
      await host.confirm();
      await host.confirmPerson();
      expect(
        a.container.read(pairingV2HostProvider).phase,
        PairingV2HostPhase.done,
      );
      await web.poll();
      expect(web.joined, isNotNull);
      webId = web.joined!.identity.deviceId;
      host.dismiss();
      await eventually(
        () async =>
            (await a.container.read(familyDeviceRowsProvider.future))!.length ==
            2,
        reason: 'the web is in the list',
      );
    });
    addTearDown(a.dispose);

    await tester.pumpWidget(screenApp(a.container, const SettingsScreen()));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(
      find.bySemanticsLabel(RegExp(r'^Móviles de la familia\. 2')),
      findsOneWidget,
    );

    // «Quitar» goes through these actions. Work the screen started while
    // pumping (a sync round under the v2 lock) runs in the test zone, so the
    // removal advances with pumps and real time together.
    var removed = false;
    Object? failure;
    await tester.runAsync(() async {
      unawaited(
        a.container
            .read(familyDeviceActionsProvider)
            .remove(webId)
            .then((_) => removed = true, onError: (Object e) => failure = e),
      );
    });
    for (var i = 0; i < 200 && !removed && failure == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(failure, isNull);
    expect(removed, isTrue);
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(
      (await tester.runAsync(
        () => a.container.read(familyDeviceRowsProvider.future),
      ))!,
      hasLength(1),
    );
    expect(_row('Solo este'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^Móviles de la familia\. \d')),
      findsNothing,
      reason: 'no stale count',
    );
    await tester.pumpWidget(const SizedBox());
    handle.dispose();
  });
}
