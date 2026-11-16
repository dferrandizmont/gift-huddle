import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/sync/application/pairing_v2_controller.dart';

import '../helpers/screens.dart';

/// Ajustes › Móviles de la familia con la sincronización v2.
void main() {
  const notice = 'Vuelve a conectar los móviles para la nueva sincronización';

  Future<void> openDevices(WidgetTester tester) async {
    await tester.tap(find.text('Ajustes').last);
    await settle(tester);
    await tapText(tester, 'Móviles de la familia');
  }

  screenTest(
    'avisa de que hay que volver a conectar los móviles',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openDevices(tester);
      expect(find.text(notice), findsOneWidget);
      expect(
        find.textContaining('«Conectar otro móvil» y comparando un número'),
        findsOneWidget,
      );
    },
    size: const Size(390, 1500),
    overrides: [syncReconnectNeededProvider.overrideWith((ref) async => true)],
  );

  screenTest('sin necesidad de reconectar no hay aviso', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openDevices(tester);
    expect(find.text(notice), findsNothing);
  }, size: const Size(390, 1500));
}
