import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/motion/value_switcher.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/lock/application/lock_controller.dart';

import '../helpers/memory_stores.dart';
import '../lock/lock_gate_test.dart' show pumpGate, settle, typePin;

void main() {
  late FakePhone phone;

  setUp(() async {
    phone = FakePhone();
    await phone.container
        .read(familyControllerProvider.notifier)
        .createFamily(deviceName: 'A');
    await phone.container.read(lockControllerProvider.notifier).setPin('4821');
    phone.restart();
  });
  tearDown(() => phone.dispose());

  // F2: el mensaje de PIN erróneo salta de línea y no se recorta, tampoco con
  // el texto grande ni en una pantalla estrecha.
  for (final scale in [1.0, 2.0]) {
    testWidgets('el mensaje de PIN erróneo cabe entero con texto x$scale', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpGate(tester, phone);
      tester.view.physicalSize = const Size(340, 900);
      await tester.pump();
      await typePin(tester, '0000');
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 400));

      final message = find.textContaining('PIN incorrecto');
      expect(message, findsOneWidget);
      final box = tester.getRect(message);
      expect(box.left, greaterThanOrEqualTo(0));
      expect(box.right, lessThanOrEqualTo(340));
      // El hueco del mensaje crece con él: nada queda recortado.
      final slot = tester.getRect(find.byType(ValueSwitcher));
      expect(slot.bottom, greaterThanOrEqualTo(box.bottom - 0.5));
      expect(tester.takeException(), isNull);
    });
  }
}
