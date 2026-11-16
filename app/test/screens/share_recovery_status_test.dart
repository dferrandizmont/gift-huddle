// La tarjeta de estado de Ajustes › Móviles de la familia distingue «Solo en
// este móvil» de «Copia de recuperación guardada» (código de recuperación
// activo: la lista tiene copia cifrada en el servidor aunque no haya otro
// móvil). La capa de recuperación va falseada.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/features/sync/application/recovery_providers.dart';

import '../helpers/fake_recovery.dart';
import '../helpers/memory_stores.dart';
import '../helpers/screens.dart';
import 'settings_test.dart' show openSettings;

void main() {
  Future<void> openDevices(WidgetTester tester, FakePhone phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openSettings(tester);
    await tapText(tester, 'Móviles de la familia');
  }

  for (final (name, readiness) in [
    ('preparado', RecoveryReadiness.prepared),
    ('actualización pendiente', RecoveryReadiness.updatePending),
  ]) {
    screenTest(
      'con el código de recuperación $name, la tarjeta dice que hay copia',
      (tester, phone) async {
        await openDevices(tester, phone);
        expect(find.text('Copia de recuperación guardada'), findsOneWidget);
        expect(find.text('Solo en este móvil'), findsNothing);
        expect(
          find.text(
            'La lista tiene una copia cifrada que se recupera con tu código. '
            'Conecta otro móvil para verla en los dos.',
          ),
          findsOneWidget,
        );
      },
      overrides: [
        recoveryApplicationProvider.overrideWith(
          () => FakeRecovery(initial: RecoveryStatus(readiness)),
        ),
      ],
    );
  }

  for (final readiness in [
    RecoveryReadiness.absent,
    RecoveryReadiness.needsAttention,
  ]) {
    screenTest(
      'con el código de recuperación en $readiness, sigue «Solo en este móvil»',
      (tester, phone) async {
        await openDevices(tester, phone);
        expect(find.text('Solo en este móvil'), findsOneWidget);
        expect(find.text('Copia de recuperación guardada'), findsNothing);
      },
      overrides: [
        recoveryApplicationProvider.overrideWith(
          () => FakeRecovery(initial: RecoveryStatus(readiness)),
        ),
      ],
    );
  }

  screenTest(
    'la tarjeta con copia de recuperación cabe con letra al 200 % en catalán',
    (tester, phone) async {
      tester.platformDispatcher.localesTestValue = const [Locale('ca', 'ES')];
      tester.platformDispatcher.localeTestValue = const Locale('ca', 'ES');
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      phone.container.read(routerProvider).go('/settings/share');
      await settle(tester);
      expect(find.text('Còpia de recuperació desada'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    textScale: 2,
    overrides: [
      recoveryApplicationProvider.overrideWith(
        () => FakeRecovery(
          initial: const RecoveryStatus(RecoveryReadiness.prepared),
        ),
      ),
    ],
  );
}
