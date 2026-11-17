import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:regalos/app/web_bootstrap.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';
import 'package:regalos/features/sync/data/sync_config.dart';
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
}
