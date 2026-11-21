import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/widgets/picker_field.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/widgets/filter_pill.dart';
import 'package:regalos/features/family/presentation/family_screen.dart';

import '../helpers/memory_stores.dart';
import '../helpers/screens.dart';

Future<void> openReparto(WidgetTester tester) async {
  await tester.tap(find.text('Reparto').last);
  await settle(tester);
}

bool _selected(WidgetTester tester, String label) => tester
    .widget<FilterPill>(
      find.descendant(
        of: find.byKey(kOccasionChipsKey),
        matching: find.widgetWithText(FilterPill, label),
      ),
    )
    .selected;

Future<void> pick(WidgetTester tester, String label) async {
  final chip = find.descendant(
    of: find.byKey(kOccasionChipsKey),
    matching: find.widgetWithText(FilterPill, label),
  );
  await tester.ensureVisible(chip);
  await tester.pump();
  await tester.tap(chip);
  await settle(tester);
}

void main() {
  const tall = Size(390, 1500);

  screenTest('Reparto se llama así y abre en «Todas», aunque haya una ocasión '
      'cercana', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    expect(find.text('Reparto'), findsWidgets);
    expect(find.text('Familia'), findsNothing);
    await openReparto(tester);

    // Hoy es el 9 de noviembre: la más cercana es el Tió (24 de diciembre),
    // pero el filtro arranca en «Todas».
    expect(find.text('Todas las ocasiones'), findsOneWidget);
    expect(find.text('Para Tió, 24 de diciembre'), findsNothing);
    for (final chip in ['Todas', 'Tió', 'Navidad', 'Reyes', 'Cumpleaños']) {
      expect(
        find.descendant(
          of: find.byKey(kOccasionChipsKey),
          matching: find.widgetWithText(FilterPill, chip),
        ),
        findsOneWidget,
        reason: chip,
      );
    }
    expect(_selected(tester, 'Todas'), isTrue);
    expect(_selected(tester, 'Tió'), isFalse);
    expect(_selected(tester, 'Reyes'), isFalse);
    // Un solo chip de cumpleaños aunque haya tres personas con fecha.
    expect(
      find.widgetWithText(FilterPill, 'Cumpleaños de Aritz'),
      findsNothing,
    );
  }, size: tall);

  screenTest('la rejilla solo cuenta los regalos de la ocasión elegida', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openReparto(tester);
    await pick(tester, 'Tió');

    // Tió: el pijama de Nosotros y el libro de Tía Marta, los dos para Aritz.
    expect(
      find.bySemanticsLabel(
        eur('Nosotros para Aritz: 1 regalo, 24 €, todo comprado'),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        eur('Tía Marta y Jordi para Aritz: 1 regalo, 18 €, algo pendiente'),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Yayos de Terrassa para Aritz: nada todavía, añadir regalo',
      ),
      findsOneWidget,
    );

    await pick(tester, 'Reyes');
    expect(find.text('Para Reyes, 6 de enero'), findsOneWidget);
    expect(_selected(tester, 'Reyes'), isTrue);
    expect(_selected(tester, 'Tió'), isFalse);
    // Reyes: la bici de los yayos, la estación de bomberos de Nosotros...
    expect(
      find.bySemanticsLabel(
        eur('Yayos de Terrassa para Aritz: 1 regalo, 180 €, algo pendiente'),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        eur('Nosotros para Aritz: 1 regalo, 49,99 €, todo comprado'),
      ),
      findsOneWidget,
    );
    // Lo del Tió ya no cuenta aquí.
    expect(
      find.bySemanticsLabel(RegExp('Tía Marta y Jordi para Aritz: 1')),
      findsNothing,
    );

    await pick(tester, 'Navidad');
    expect(find.text('Para Navidad, 25 de diciembre'), findsOneWidget);
    // El aviso de duplicado cuenta entre ocasiones: el puzle de Nora está en
    // Navidad y en Reyes, y se sigue viendo.
    expect(
      find.textContaining('Posible duplicado: «Puzle de 48 piezas» para Nora'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        RegExp('^Avis de Girona para Nora: .*posible duplicado'),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('^Avis de Girona para Nora: 1 regalo')),
      findsOneWidget,
    );

    await pick(tester, 'Cumpleaños');
    expect(find.text('Para los cumpleaños'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'para Aritz: \d regalo')),
      findsNothing,
    );
    expect(
      find.bySemanticsLabel('Nosotros para Aritz: nada todavía, añadir regalo'),
      findsOneWidget,
    );
  }, size: tall);

  screenTest('«Todas» junta todo y marca cada celda con sus ocasiones', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openReparto(tester);
    await pick(tester, 'Todas');
    expect(find.text('Todas las ocasiones'), findsOneWidget);
    expect(_selected(tester, 'Todas'), isTrue);
    expect(
      find.bySemanticsLabel(
        eur(
          'Nosotros para Aritz: 2 regalos, 73,99 €, todo comprado, para Tió, Reyes',
        ),
      ),
      findsOneWidget,
    );
    // Una celda con un solo tipo de regalo lo dice igual.
    expect(
      // (y es uno de los dos del posible duplicado)
      find.bySemanticsLabel(
        eur(
          'Avis de Girona para Nora: 1 regalo, 19 €, algo pendiente, para Navidad, posible duplicado',
        ),
      ),
      findsOneWidget,
    );
    // Las celdas son pequeñas: las ocasiones no se pintan, solo las lee el
    // lector de pantalla, y solo en «Todas».
    await pick(tester, 'Reyes');
    expect(find.bySemanticsLabel(RegExp(', para ')), findsNothing);
  }, size: tall);

  screenTest('lo elegido se conserva y tocar una celda lleva a esa ocasión', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openReparto(tester);
    await pick(tester, 'Reyes');

    await tester.tap(
      find.bySemanticsLabel(RegExp('^Nosotros para Aritz: 1 regalo')),
    );
    await settle(tester);
    // La hoja enseña solo lo de Reyes y lleva a la lista de Aritz.
    expect(find.text('Estación de bomberos de bloques'), findsOneWidget);
    expect(find.text('Pijama de astronautas, talla 8'), findsNothing);
    await tester.tap(find.text('Ver la lista de Aritz'));
    await settle(tester);
    // La lista de Aritz llega filtrada por quien regala y por la ocasión.
    expect(find.bySemanticsLabel('Quitar filtro Nosotros'), findsOneWidget);
    expect(find.bySemanticsLabel('Quitar filtro Reyes'), findsOneWidget);
    expect(find.text('Estación de bomberos de bloques'), findsOneWidget);
    expect(find.text('Pijama de astronautas, talla 8'), findsNothing);
  }, size: tall);

  screenTest('una celda vacía abre el editor ya con la ocasión elegida', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openReparto(tester);
    await pick(tester, 'Reyes');
    await tester.tap(
      find.bySemanticsLabel(
        'Padrina Anna para Leo: nada todavía, añadir regalo',
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Añadir regalo de Padrina Anna'));
    await settle(tester);
    expect(find.text('Nuevo regalo'), findsOneWidget);
    final occasion = tester
        .widgetList<PickerField<String>>(find.byType(PickerField<String>))
        .map((d) => d.value)
        .toList();
    expect(occasion, contains('seed-kings'));
  }, size: tall);

  screenTest(
    'el selector aguanta el texto al 130 % sin desbordar',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openReparto(tester);
      expect(tester.takeException(), isNull);
      await pick(tester, 'Todas');
      expect(tester.takeException(), isNull);
    },
    size: const Size(390, 1900),
    textScale: 1.3,
  );

  screenTest('una ocasión nueva sale en el selector y se puede elegir', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await tester.runAsync(
      () => familyOf(phone).upsertOccasion(
        const Occasion(
          id: 'boda',
          kind: OccasionKind.wedding,
          rawKind: 'wedding',
          name: 'Boda de Marta',
          month: 11,
          day: 20,
          year: 2026,
          recurring: false,
          archived: false,
        ),
      ),
    );
    await pumpRegalos(tester, phone);
    await openReparto(tester);
    // Faltan 11 días: es la más cercana, pero el filtro sigue en «Todas».
    expect(_selected(tester, 'Todas'), isTrue);
    await pick(tester, 'Boda de Marta');
    expect(find.text('Para Boda de Marta, 20 de noviembre'), findsOneWidget);
    expect(_selected(tester, 'Boda de Marta'), isTrue);
  }, size: tall);

  group('el nombre de quien regala en la cabecera', () {
    Future<void> addGiver(WidgetTester tester, FakePhone phone, String name) =>
        tester.runAsync(
          () => familyOf(phone).upsertGiver(
            Giver(
              id: 'long',
              name: name,
              colorIndex: 2,
              householdPays: false,
              archived: false,
            ),
          ),
        );

    Text nameText(WidgetTester tester, String name) =>
        tester.widget<Text>(find.text(name));

    screenTest('«Tía Marta y Jordi» va entero en una sola línea inclinada y se '
        'acorta si no cabe', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openReparto(tester);
      final text = nameText(tester, 'Tía Marta y Jordi');
      expect(text.maxLines, 1);
      expect(text.softWrap, isFalse);
      expect(text.overflow, TextOverflow.ellipsis);
      // Va inclinado: su caja sube hacia la derecha.
      final rect = tester.getRect(find.text('Tía Marta y Jordi'));
      expect(rect.height, greaterThan(40));
      expect(rect.right, lessThanOrEqualTo(390));
    }, size: tall);

    screenTest('un nombre muy largo se acorta con puntos suspensivos y no se '
        'sale de la pantalla', (tester, phone) async {
      await seedSample(tester, phone);
      await addGiver(tester, phone, 'Superabuelitosdeterrassa');
      await pumpRegalos(tester, phone);
      await openReparto(tester);
      final text = nameText(tester, 'Superabuelitosdeterrassa');
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(
        tester.getRect(find.text('Superabuelitosdeterrassa')).right,
        lessThanOrEqualTo(390),
      );
      expect(tester.takeException(), isNull);
    }, size: tall);

    screenTest('al tocar el nombre sale completo', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openReparto(tester);
      expect(find.text('Tío Pere'), findsOneWidget);
      await tester.tap(find.text('Tío Pere'));
      await tester.pump(const Duration(milliseconds: 200));
      // El mismo texto en la ayuda que se abre sobre el nombre.
      expect(find.text('Tío Pere'), findsNWidgets(2));
      await tester.pump(const Duration(seconds: 5));
    }, size: tall);

    screenTest(
      'sigue sin romperse con el texto al 130 %',
      (tester, phone) async {
        await seedSample(tester, phone);
        await addGiver(tester, phone, 'Superabuelitosdeterrassa');
        await pumpRegalos(tester, phone);
        await openReparto(tester);
        expect(tester.takeException(), isNull);
        final text = nameText(tester, 'Superabuelitosdeterrassa');
        expect(text.maxLines, 1);
      },
      size: const Size(390, 1900),
      textScale: 1.3,
    );
  });
}
