import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/widgets/picker_field.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/widgets/countdown_card.dart';
import 'package:regalos/core/theme/regalos_tokens.dart';
import 'package:regalos/features/occasions/presentation/occasion_garland.dart';
import 'package:regalos/features/settings/application/appearance_provider.dart';

import '../helpers/screens.dart';

Future<void> openOccasions(WidgetTester tester) async {
  await tester.tap(find.text('Ocasiones').last);
  await settle(tester);
}

void main() {
  const tall = Size(390, 1900);

  screenTest('la lista de ocasiones va por orden, con días y regalos', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openOccasions(tester);
    expect(find.text('Presupuesto de la casa'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Tió. 24 de diciembre · Faltan 45 días · 2 regalos',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Reyes. 6 de enero · Faltan 58 días · 6 regalos'),
      findsOneWidget,
    );
    // El primero es el Tió (el más cercano).
    expect(
      tester.getTopLeft(find.text('Tió')).dy,
      lessThan(tester.getTopLeft(find.text('Reyes')).dy),
    );
    expect(find.text('Cumpleaños de Nora'), findsOneWidget);
  }, size: tall);

  screenTest(
    'la vista de Reyes: cuenta atrás, por envolver, reparto y compras',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openOccasions(tester);
      await tapText(tester, 'Reyes');

      expect(find.text('58'), findsOneWidget);
      expect(find.text('días para Reyes'), findsOneWidget);
      expect(find.text('Hoy, 9 de noviembre'), findsOneWidget);
      expect(find.text('6 de enero'), findsOneWidget);
      expect(find.bySemanticsLabel('0 por envolver'), findsOneWidget);
      expect(find.bySemanticsLabel('2 por llegar'), findsOneWidget);

      // Cada persona con lo que recibe y el reparto entre Tió, Navidad, Reyes.
      expect(find.text('Cada persona'), findsOneWidget);
      expect(find.text('Estación de bomberos de bloques'), findsOneWidget);
      expect(find.text('Tren de madera'), findsOneWidget);
      expect(find.text('0 · 2 · 2'), findsOneWidget); // Nora
      expect(find.text('2 · 0 · 3'), findsOneWidget); // Aritz
      expect(
        find.bySemanticsLabel('Reparto de Nora: Tió 0, Navidad 2, Reyes 2'),
        findsOneWidget,
      );

      // Lo pendiente de comprar, por tienda.
      expect(find.text('Pendiente de comprar'), findsOneWidget);
      expect(find.text('Decathlon'), findsOneWidget);
      expect(find.text('Juguetería del barrio'), findsNothing); // solo ideas
      await tester.tap(
        find.bySemanticsLabel('Marcar Bici de 20" con cambios como comprado'),
      );
      await settle(tester);
      final state = await familyState(tester, phone);
      expect(
        state.view.gifts.firstWhere((g) => g.id == 'g4').status,
        GiftStatus.bought,
      );
      expect(find.text('Decathlon'), findsNothing);
      expect(find.textContaining('Nada decidido todavía'), findsOneWidget);
      expect(find.bySemanticsLabel('3 por llegar'), findsOneWidget);
    },
    size: tall,
  );

  screenTest('el tema de ocasión sigue al interruptor de Apariencia', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    phone.container.read(routerProvider).go('/occasions/seed-kings');
    await settle(tester);
    RegalosTokens tokens() =>
        Theme.of(tester.element(find.byType(CountdownCard)))
            .extension<RegalosTokens>()!;
    expect(tokens().occasion?.id, 'kings');

    phone.container
        .read(appearanceProvider.notifier)
        .setOccasionThemes(enabled: false);
    await settle(tester);
    expect(tokens().occasion, isNull);

    phone.container.read(routerProvider).go('/occasions/birthday-nora');
    await settle(tester);
    expect(tokens().occasion, isNull);
    phone.container
        .read(appearanceProvider.notifier)
        .setOccasionThemes(enabled: true);
    await settle(tester);
    expect(tokens().occasion?.id, 'birthday');
  }, size: tall);

  screenTest('un cumpleaños enseña la edad y sus días', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    phone.container.read(routerProvider).go('/occasions/birthday-nora');
    await settle(tester);
    expect(find.text('Cumpleaños de Nora'), findsOneWidget);
    expect(find.text('12 de junio · Nora, 4 años'), findsOneWidget);
    expect(find.text('215'), findsOneWidget);
    expect(find.text('días para el cumpleaños de Nora'), findsOneWidget);
    // Sin regalos, una sola frase (y el «+» flotante), sin contadores vacíos.
    expect(
      find.text('Todavía no hay regalos para esta ocasión.'),
      findsOneWidget,
    );
    // Un regalo nuevo desde la ocasión ya lleva la ocasión y la persona.
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    final dropdowns = find.byType(PickerField<String>);
    expect(
      find.descendant(of: dropdowns.at(0), matching: find.text('Nora')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dropdowns.at(2),
        matching: find.text('Cumpleaños de Nora'),
      ),
      findsOneWidget,
    );
  }, size: tall);

  screenTest('el presupuesto cuenta solo lo que paga la casa', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openOccasions(tester);
    await tapText(tester, 'Presupuesto de la casa');
    expect(find.text('Solo lo que paga la casa'), findsOneWidget);
    expect(find.text(eur('174,50 €')), findsWidgets); // previsto
    expect(find.text(eur('169,49 €')), findsWidgets); // gastado
    expect(find.text(eur('5,01 €')), findsOneWidget); // queda
    expect(find.text('Queda'), findsOneWidget);
    // Los 180 € de los yayos son un regalo, no un gasto de la casa.
    expect(find.textContaining('180'), findsNothing);
    expect(find.text('Por persona'), findsOneWidget);
    expect(find.text('Por ocasión'), findsOneWidget);
    expect(find.text('Aritz'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        RegExp(RegExp.escape(eur('Gastado: 73,99 € de 79 €'))),
      ),
      findsOneWidget,
    );
  }, size: tall);

  screenTest('sin nada que pague la casa, el presupuesto lo explica', (
    tester,
    phone,
  ) async {
    await bareFamily(tester, phone);
    await pumpRegalos(tester, phone);
    phone.container.read(routerProvider).go('/occasions/budget');
    await settle(tester);
    expect(find.textContaining('Marca «Paga la casa»'), findsOneWidget);
  });

  screenTest(
    'la guirnalda sale en la lista y en la cabecera, y se apaga con los '
    'temas',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openOccasions(tester);
      // Tió, Navidad, Reyes y tres cumpleaños: seis guirnaldas.
      expect(find.byType(OccasionGarland), findsNWidgets(6));
      final motifs = tester
          .widgetList<OccasionGarland>(find.byType(OccasionGarland))
          .map((g) => g.motif)
          .toSet();
      expect(motifs, GarlandMotif.values.toSet());
      // En la lista mide 24 con iconos de 18.
      final first = tester.widget<OccasionGarland>(
        find.byType(OccasionGarland).first,
      );
      expect(first.height, 24);
      expect(first.iconSize, 18);

      await tapText(tester, 'Reyes');
      expect(find.byType(OccasionGarland), findsOneWidget);
      final header = tester.widget<OccasionGarland>(
        find.byType(OccasionGarland),
      );
      expect(header.motif, GarlandMotif.kings);
      expect(header.height, 28);
      expect(header.iconSize, 22);

      phone.container
          .read(appearanceProvider.notifier)
          .setOccasionThemes(enabled: false);
      await settle(tester);
      expect(find.byType(OccasionGarland), findsNothing);
    },
    size: tall,
  );
}
