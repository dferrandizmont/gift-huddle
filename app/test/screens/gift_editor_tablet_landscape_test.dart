import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/gifts/presentation/gift_editor_screen.dart';
import 'package:regalos/features/gifts/presentation/person_list_screen.dart';

import '../helpers/screens.dart';
import '../helpers/tablet.dart';

// F9: en una tablet en horizontal (1280 × 800, que no es la web) el editor de
// regalo es la tarjeta de 640 centrada en el panel de detalle (diseño D), con
// el formulario en una columna; no el diálogo de 880 de la web de escritorio.
void main() {
  tabletScreenTest(
    'el editor de regalo es una tarjeta de 640 centrada en el detalle',
    (tester, phone, size) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      final add = find.byKey(const ValueKey<String>('add-gift-header'));
      if (add.evaluate().isNotEmpty) {
        await tester.tap(add);
      } else {
        await tester.tap(
          find.widgetWithText(FloatingActionButton, 'Añadir regalo'),
        );
      }
      await settle(tester);

      final card = tester.getRect(find.byType(GiftEditorScreen));
      expect(card.width, lessThanOrEqualTo(640 + 0.5));
      expect(
        tester.widget<GiftEditorScreen>(find.byType(GiftEditorScreen)).asDialog,
        isFalse,
      );
      // Una columna: el campo «Regalo» y las notas van uno bajo otro.
      final title = tester.getTopLeft(find.widgetWithText(TextField, 'Regalo'));
      expect(title.dx, greaterThanOrEqualTo(card.left));
      if (size.width >= 1280) {
        final detail = find.byType(PersonListScreen);
        if (detail.evaluate().isNotEmpty) {
          expect(card.center.dx, closeTo(tester.getRect(detail).center.dx, 1));
        }
      }
    },
    sizes: const [kTabletLandscape],
  );
}
