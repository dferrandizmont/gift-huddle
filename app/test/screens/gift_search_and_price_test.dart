// El buscador de regalos de Personas (móvil, tableta y web estrecha) y los
// importes del formulario de regalo.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:regalos/core/sync/model.dart' show Recipient;
import 'package:regalos/features/gifts/presentation/gift_search.dart';

import '../helpers/screens.dart';

Finder _inResults(String text) => find.descendant(
  of: find.byType(GiftSearchResults),
  matching: find.text(text),
);

const _lupa = ValueKey<String>('people-gift-search-button');
const _cancel = ValueKey<String>('people-gift-search-cancel');

Future<void> _openSearch(WidgetTester tester) async {
  await tester.tap(find.byKey(_lupa));
  await settle(tester);
}

void main() {
  screenTest('la lupa está junto al «+», con su mismo tamaño y forma, y el '
      'campo desplegado tiene el foco con el teclado', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    final lupa = find.byKey(_lupa);
    // Su etiqueta es propia, no la del campo.
    expect(find.bySemanticsLabel('Buscar regalos'), findsOneWidget);
    expect(find.byTooltip('Buscar regalos'), findsOneWidget);
    final plus = find.bySemanticsLabel('Añadir persona');
    expect(lupa, findsOneWidget);
    expect(tester.getSize(lupa), tester.getSize(plus.first));
    expect(tester.getCenter(lupa).dy, tester.getCenter(plus.first).dy);
    expect(
      tester.getCenter(lupa).dx,
      lessThan(tester.getCenter(plus.first).dx),
    );
    // La forma: radio 8 como mucho, nunca una píldora.
    final material = tester.widget<Material>(
      find.descendant(of: lupa, matching: find.byType(Material)).first,
    );
    final shape = material.shape! as RoundedRectangleBorder;
    expect(
      (shape.borderRadius as BorderRadius).topLeft.x,
      lessThanOrEqualTo(8),
    );
    await _openSearch(tester);
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('people-gift-search')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.focusNode!.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.takeException(), isNull);
  });

  screenTest('«Cancelar» vacía la búsqueda, vuelve la lista y pliega el '
      'campo', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await _openSearch(tester);
    final field = find.byKey(const ValueKey<String>('people-gift-search'));
    await tester.enterText(field, 'puzle');
    await settle(tester);
    expect(find.byType(GiftSearchResults), findsOneWidget);
    await tester.tap(find.byKey(_cancel));
    await settle(tester);
    expect(find.byType(GiftSearchResults), findsNothing);
    expect(field, findsNothing);
    expect(find.text('Aritz'), findsWidgets);
    expect(tester.testTextInput.isVisible, isFalse);
    // Se vuelve a abrir vacío.
    await _openSearch(tester);
    expect(
      tester
          .widget<TextField>(
            find.descendant(of: field, matching: find.byType(TextField)),
          )
          .controller!
          .text,
      isEmpty,
    );
  });

  screenTest('sin regalos no hay lupa', (tester, phone) async {
    await bareFamily(tester, phone);
    await tester.runAsync(
      () => familyOf(phone).upsertRecipient(
        const Recipient(
          id: 'aritz',
          name: 'Aritz',
          colorIndex: 0,
          archived: false,
        ),
      ),
    );
    await pumpRegalos(tester, phone);
    expect(find.text('Aritz'), findsWidgets);
    expect(find.byKey(_lupa), findsNothing);
  });

  screenTest(
    'letra grande y oscuro: la cabecera y el campo caben',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openSearch(tester);
      expect(find.byKey(_cancel), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    textScale: 2,
    brightness: Brightness.dark,
  );

  screenTest('con «Reducir movimiento» el campo aparece y desaparece sin '
      'estirarse', (tester, phone) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await _openSearch(tester);
    expect(
      find.byKey(const ValueKey<String>('people-gift-search')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(_cancel));
    await settle(tester);
    expect(
      find.byKey(const ValueKey<String>('people-gift-search')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  screenTest('buscar un regalo en Personas: por nombre, por persona y sin '
      'resultados', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    final field = find.byKey(const ValueKey<String>('people-gift-search'));
    // Plegado: ni campo fijo bajo el título; solo la lupa de la cabecera.
    expect(field, findsNothing);
    await _openSearch(tester);
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
