// El buscador de regalos de Personas (móvil, tableta y web estrecha) y los
// importes del formulario de regalo.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:regalos/features/gifts/presentation/gift_search.dart';

import '../helpers/screens.dart';

Finder _inResults(String text) => find.descendant(
  of: find.byType(GiftSearchResults),
  matching: find.text(text),
);

void main() {
  screenTest('buscar un regalo en Personas: por nombre, por persona y sin '
      'resultados', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    final field = find.byKey(const ValueKey<String>('people-gift-search'));
    expect(field, findsOneWidget);
    // Sin buscar, las personas.
    expect(find.text('Aritz'), findsWidgets);

    await tester.enterText(field, 'PUZLE');
    await settle(tester);
    expect(_inResults('Puzle de 48 piezas'), findsWidgets);
    // Sus resultados sustituyen a la lista de personas.
    expect(_inResults('Pijama de astronautas, talla 8'), findsNothing);

    // Por la persona.
    await tester.enterText(field, 'aritz');
    await settle(tester);
    expect(_inResults('Pijama de astronautas, talla 8'), findsWidgets);
    expect(_inResults('Puzle de 48 piezas'), findsNothing);

    await tester.enterText(field, 'zzzz');
    await settle(tester);
    expect(find.text('Ningún regalo coincide'), findsOneWidget);

    // La cruz vacía el campo y vuelve la lista.
    await tester.tap(find.byTooltip('Borrar la búsqueda'));
    await settle(tester);
    expect(find.byType(GiftSearchResults), findsNothing);
    expect(find.byTooltip('Borrar la búsqueda'), findsNothing);
    expect(find.text('Aritz'), findsWidgets);
  });

  screenTest('el importe acepta punto y coma y se deja como lo escribe el '
      'idioma al salir del campo', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await tapText(tester, 'Aritz');
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    final planned = find.widgetWithText(TextField, 'Previsto');
    await tester.enterText(planned, '12.5');
    await tester.tap(find.widgetWithText(TextField, 'Regalo'));
    await settle(tester);
    expect(tester.widget<TextField>(planned).controller!.text, '12,50');

    await tester.enterText(planned, '7,');
    await tester.tap(find.widgetWithText(TextField, 'Regalo'));
    await settle(tester);
    expect(tester.widget<TextField>(planned).controller!.text, '7');
    expect(find.text('Escribe un importe, por ejemplo 12,50.'), findsNothing);
  });
}
