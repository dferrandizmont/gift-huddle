import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/screens.dart';

void main() {
  screenTest('sin familia la app empieza por el primer uso', (
    tester,
    phone,
  ) async {
    await pumpRegalos(tester, phone);
    expect(find.text('Te damos la bienvenida a Gift Huddle'), findsOneWidget);
    // Sin barra inferior hasta que haya familia.
    expect(find.bySemanticsLabel('Navegación principal'), findsNothing);
  });

  screenTest('la barra tiene cuatro destinos y empieza en Personas', (
    tester,
    phone,
  ) async {
    await bareFamily(tester, phone);
    await pumpRegalos(tester, phone);
    for (final label in ['Personas', 'Reparto', 'Ocasiones', 'Ajustes']) {
      expect(find.bySemanticsLabel(label), findsWidgets);
    }
    expect(find.text('Aún no hay personas'), findsOneWidget);
  });

  screenTest('cada destino muestra su título y su estado vacío', (
    tester,
    phone,
  ) async {
    await bareFamily(tester, phone);
    await pumpRegalos(tester, phone);

    await tester.tap(find.text('Reparto'));
    await settle(tester);
    expect(find.text('Faltan personas'), findsOneWidget);

    await tester.tap(find.text('Ocasiones'));
    await settle(tester);
    expect(find.text('Sin ocasiones'), findsOneWidget);

    await tester.tap(find.text('Ajustes'));
    await settle(tester);
    expect(find.text('Apariencia'), findsOneWidget);
  });

  screenTest('Ajustes lleva a Apariencia y se vuelve con la flecha', (
    tester,
    phone,
  ) async {
    await bareFamily(tester, phone);
    await pumpRegalos(tester, phone);
    await tester.tap(find.text('Ajustes'));
    await settle(tester);
    await tapText(tester, 'Apariencia');
    expect(find.text('Vista previa'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Volver a Ajustes'));
    await settle(tester);
    expect(find.text('Vista previa'), findsNothing);
    expect(find.text('Apariencia'), findsOneWidget);
  });

  screenTest(
    'los destinos miden 44 px o más y la barra no desborda al 130 %',
    (tester, phone) async {
      await bareFamily(tester, phone);
      await pumpRegalos(tester, phone);
      final inkWells = find.descendant(
        of: find.bySemanticsLabel('Navegación principal'),
        matching: find.byType(InkWell),
      );
      expect(inkWells, findsNWidgets(4));
      for (final e in inkWells.evaluate()) {
        expect(
          tester.getSize(find.byWidget(e.widget)).height,
          greaterThanOrEqualTo(44),
        );
      }
      expect(tester.takeException(), isNull);
    },
    size: const Size(360, 780),
    textScale: 1.3,
  );

  screenTest(
    'Ajustes y sus pantallas no desbordan al 130 % en 360 px',
    (tester, phone) async {
      await seedSample(tester, phone, pin: true);
      await pumpRegalos(tester, phone);
      await tester.tap(find.text('Ajustes'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      // De arriba abajo: la lista es perezosa y las filas de más abajo solo
      // existen cuando se ha llegado cerca.
      for (final row in [
        'Personas',
        'Quién regala',
        'Ocasiones',
        'Archivo',
        'Bloqueo',
        'Apariencia',
        'Móviles de la familia',
        'Copia de seguridad',
      ]) {
        await tester.ensureVisible(find.text(row).first);
        await tester.pump();
        await tapText(tester, row);
        expect(tester.takeException(), isNull, reason: row);
        await tester.tap(find.bySemanticsLabel('Volver a Ajustes'));
        await settle(tester);
      }
    },
    size: const Size(360, 780),
    textScale: 1.3,
  );
}
