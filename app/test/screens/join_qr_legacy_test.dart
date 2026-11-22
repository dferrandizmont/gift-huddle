// 1.0.6: en la versión de tienda, una instalación nueva no entra con el QR
// antiguo que lleva la clave de la familia (entraría sin persona).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/sharing/presentation/join_qr_screen.dart';

import '../helpers/screens.dart';

void main() {
  // Un QR de la versión 1 (no es un enlace de invitación v2).
  const legacy = 'regalos://pair?v=1&l=lista&k=clave&n=Aritz';

  screenTest(
    'sin el QR antiguo: avisa de actualizar y no entra',
    (tester, phone) async {
      await pumpRegalos(tester, phone);
      await tapWelcomeChoice(tester, 'Escanear el QR');
      final scanner = find.text('Leer QR antiguo');
      await tester.ensureVisible(scanner);
      await tester.tap(scanner);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.textContaining(
          'Los dos móviles tienen que tener la última versión',
        ),
        findsOneWidget,
      );
      final family = await phone.container.read(
        familyControllerProvider.future,
      );
      expect(
        family.identity,
        isNull,
        reason: 'no ha entrado en ninguna familia',
      );
      await tester.pumpWidget(const SizedBox());
    },
    overrides: [legacyQrJoinAllowedProvider.overrideWithValue(false)],
    scanner: (context, onCode) => TextButton(
      onPressed: () => onCode(legacy),
      child: const Text('Leer QR antiguo'),
    ),
  );
}
