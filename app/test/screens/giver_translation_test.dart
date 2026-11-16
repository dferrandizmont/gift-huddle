import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:regalos/core/widgets/picker_field.dart';
import 'package:regalos/features/settings/application/locale_provider.dart';

import '../helpers/screens.dart';

Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.text('Ajustes').last);
  await settle(tester);
}

void main() {
  screenTest(
    'el nombre de serie de quién regala se traduce al cambiar el idioma',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openSettings(tester);
      await tapText(tester, 'Quién regala');
      expect(find.text('Nosotros'), findsOneWidget);

      await tester.runAsync(() async {
        phone.container
            .read(localeProvider.notifier)
            .setLocale(const Locale('en'));
      });
      await settle(tester);
      expect(find.text('Us'), findsOneWidget);

      // Reparto: la columna de quién regala.
      await tester.tap(find.text('Who gives').last);
      await settle(tester);
      expect(find.text('Us'), findsWidgets);
      expect(find.text('Nosotros'), findsNothing);

      // Personas: la hoja de filtros de la lista de Aritz.
      await tester.tap(find.text('People').last);
      await settle(tester);
      await tapText(tester, 'Aritz');
      await tapText(tester, 'Filters');
      final sheet = find.byType(BottomSheet);
      expect(find.text('Filter gifts'), findsOneWidget);
      expect(
        find.descendant(of: sheet, matching: find.text('Us')),
        findsOneWidget,
      );
      expect(find.text('Nosotros'), findsNothing);
      await tester.tap(find.descendant(of: sheet, matching: find.text('Us')));
      await settle(tester);
      await tapText(tester, 'Done');
      expect(find.bySemanticsLabel('Remove filter Us'), findsOneWidget);
      expect(find.bySemanticsLabel('Remove filter Nosotros'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Remove filter Us'));
      await settle(tester);

      // Editor de regalo: el desplegable de quién regala.
      await tester.tap(find.byType(FloatingActionButton));
      await settle(tester);
      await tester.tap(find.byType(PickerField<String>).at(1));
      await settle(tester);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Us'),
        ),
        findsOneWidget,
      );
      expect(find.text('Nosotros'), findsNothing);
    },
    size: const Size(390, 1500),
  );
}
