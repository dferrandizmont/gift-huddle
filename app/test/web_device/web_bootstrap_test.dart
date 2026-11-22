import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:regalos/app/web_bootstrap.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/protected_doc.dart' show ownHiddenPeople;
import 'package:regalos/features/family/application/protection_providers.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';
import 'package:regalos/features/sharing/presentation/share_dialogs.dart';
import 'package:regalos/features/sync/data/sync_config.dart';
import 'package:regalos/features/sync/presentation/invite_link_listener.dart';
import 'package:regalos/features/web_device/application/web_gate_controller.dart';
import 'package:regalos/features/web_device/data/web_device_keys_store.dart';
import 'package:regalos/features/web_device/presentation/web_gate_model.dart';

import 'test_support.dart';
import 'web_engine_support.dart';

void main() {
  testWidgets(
    'real bootstrap receives phone changes live and destroys its container on lock',
    (tester) async {
      late WebHarness h;
      final locks = FakeLockHub();
      late WebGateController gate;
      late SharedPreferences prefs;
      await tester.runAsync(() async {
        // Create the fake store's Future queue in the real async zone.
        h = WebHarness();
        await h.setup();
        h.engine.stop();
        h.vault.lock();
        SharedPreferences.setMockInitialValues({});
        prefs = await SharedPreferences.getInstance();
      });
      await tester.pumpWidget(
        WebBootstrap(
          preferences: prefs,
          gateFactory: (create, dispose, changed) => gate = WebGateController(
            vault: h.vault,
            platform: FakeSessionPlatform(locks),
            transport: () => h.client,
            createContainer: create,
            disposeContainer: dispose,
            candidateChanged: changed,
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
        await gate.submitPin('123456').timeout(const Duration(seconds: 15));
        // Complete the startup refresh before rendering under the fake clock.
        await gate.engine!.sync();
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      expect(gate.view, isA<WebGateOpen>());
      // The web gate owns invitations. The Wasm guard's reviewed dead
      // InviteLinkListener traps rely on native listeners never mounting here.
      expect(
        find.byType(IncomingShareListener, skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byType(InviteLinkListener, skipOffstage: false),
        findsNothing,
      );
      final container = tester
          .widget<UncontrolledProviderScope>(
            find.byType(UncontrolledProviderScope).first,
          )
          .container;
      expect(
        container.read(deviceKeysStoreProvider),
        isA<WebDeviceKeysStore>(),
      );
      expect(container.read(syncTransportProvider), isNull);
      expect(container.read(syncV2TransportProvider), isNull);
      var destroyed = false;
      final probe = Provider<int>((ref) {
        ref.onDispose(() => destroyed = true);
        return 1;
      });
      container.read(probe);
      await tester.runAsync(() async {
        await container
            .read(familyControllerProvider.future)
            .timeout(const Duration(seconds: 15));
        await h.publish(
          doc: h.phone.doc.set(h.phone.clock, Collections.gifts, 'gift', {
            'title': 'Libro',
          }),
        );
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (container
                    .read(familyControllerProvider)
                    .value!
                    .doc
                    .record(Collections.gifts, 'gift')!['title'] !=
                'Libro' &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(
          container
              .read(familyControllerProvider)
              .value!
              .doc
              .record(Collections.gifts, 'gift')!['title'],
          'Libro',
        );
        expect(
          await container
              .read(familyControllerProvider.notifier)
              .deleteGiftWithUndo('gift'),
          isTrue,
        );
        await gate.lock();
      });
      await tester.pump();
      expect(destroyed, isTrue);
      expect(() => container.read(familyControllerProvider), throwsStateError);
      expect(find.byType(UncontrolledProviderScope), findsNothing);
      expect(gate.view, isA<WebGateUnlock>());
      await tester.runAsync(() async {
        expect((await h.store.read()).current!.entries, hasLength(1));
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
        h.close();
      });
    },
  );

  testWidgets('1.0.6 (la revisión, 4): la web de Nora, emparejada por el móvil de '
      'Aritz, oculta los regalos de Nora con el registro ya cargado', (
    tester,
  ) async {
    late WebHarness h;
    final locks = FakeLockHub();
    late WebGateController gate;
    late SharedPreferences prefs;
    await tester.runAsync(() async {
      h = WebHarness(webPerson: 'nora');
      await h.setup();
      // Un regalo público de Aritz, que la web de Nora sí ve.
      h.phone.addGift('aritz-gift', 'aritz', 'Reloj');
      await h.publish();
      h.engine.stop();
      h.vault.lock();
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });
    await tester.pumpWidget(
      WebBootstrap(
        preferences: prefs,
        gateFactory: (create, dispose, changed) => gate = WebGateController(
          vault: h.vault,
          platform: FakeSessionPlatform(locks),
          transport: () => h.client,
          createContainer: create,
          disposeContainer: dispose,
          candidateChanged: changed,
        ),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
      await gate.submitPin('123456').timeout(const Duration(seconds: 15));
      await gate.engine!.sync();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    final container = tester
        .widget<UncontrolledProviderScope>(
          find.byType(UncontrolledProviderScope).first,
        )
        .container;
    await tester.runAsync(() async {
      await container
          .read(familyControllerProvider.future)
          .timeout(const Duration(seconds: 15));
    });
    final engine = gate.engine!;
    // La raíz que verifica es el móvil de Aritz; la de pantalla, la web.
    expect(engine.view!.me, 'aritz-phone');
    expect(engine.screenView!.me, engine.auth.deviceId);
    expect(engine.screenView!.myPerson, 'nora');
    // Con la raíz, Nora no estaría acompañada (el fallo de antes).
    expect(
      ownHiddenPeople(view: engine.view, selfRecipientId: 'nora', paired: true),
      isNot(contains('nora')),
    );
    expect(container.read(screenRegistryViewProvider).value, engine.screenView);
    expect(container.read(ownHiddenPeopleProvider), {'nora'});
    final doc = container.read(projectedFamilyDocProvider);
    expect(doc.record(Collections.gifts, 'gift'), isNull);
    expect(doc.record(Collections.gifts, 'aritz-gift'), isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
      h.close();
    });
  });
}
