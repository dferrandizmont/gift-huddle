import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/core/widgets/countdown_card.dart';

import '../helpers/pump_app.dart';

BoxDecoration _decoration(WidgetTester tester) {
  final container = tester.widget<Container>(
    find
        .descendant(
          of: find.byType(CountdownCard),
          matching: find.byType(Container),
        )
        .first,
  );
  return container.decoration! as BoxDecoration;
}

void main() {
  const card = CountdownCard(
    days: 58,
    title: 'días para Reyes',
    date: 'Hoy es 9 de noviembre',
  );

  testWidgets('muestra días, título y fecha', (tester) async {
    await pumpThemed(tester, card);
    expect(find.text('58'), findsOneWidget);
    expect(find.text('días para Reyes'), findsOneWidget);
    expect(find.text('Hoy es 9 de noviembre'), findsOneWidget);
  });

  testWidgets('en claro usa el pastel del acento y la tinta en el número', (
    tester,
  ) async {
    await pumpThemed(tester, card, accent: AccentId.sage);
    final p = AccentId.sage.palette;
    expect(_decoration(tester).color, p.pastel);
    expect(tester.widget<Text>(find.text('58')).style!.color, p.tinta);
    expect(_decoration(tester).border, isNull);
  });

  testWidgets('en oscuro usa tintD de fondo y tintaD en el número', (
    tester,
  ) async {
    await pumpThemed(
      tester,
      card,
      accent: AccentId.rose,
      brightness: Brightness.dark,
    );
    final p = AccentId.rose.palette;
    expect(_decoration(tester).color, p.tintD);
    expect(tester.widget<Text>(find.text('58')).style!.color, p.tintaD);
  });

  testWidgets('con tema de ocasión cambia de acento y lleva borde', (
    tester,
  ) async {
    await pumpThemed(
      tester,
      const CountdownCard(
        days: 215,
        title: 'días para el cumpleaños',
        date: 'Hoy es 9 de noviembre',
        occasion: OccasionTheme.birthday,
        size: CountdownSize.large,
      ),
    );
    final deco = _decoration(tester);
    expect(deco.color, OccasionTheme.birthday.palette.pastel);
    expect(
      (deco.border! as Border).top.color,
      OccasionTheme.birthday.cardBorder,
    );
    final number = tester.widget<Text>(find.text('215')).style!;
    expect(number.fontSize, 64);
    expect(number.color, OccasionTheme.birthday.palette.tinta);
  });

  testWidgets('Semantics lee la tarjeta como una sola frase', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpThemed(tester, card);
    expect(
      find.bySemanticsLabel('58 días para Reyes. Hoy es 9 de noviembre'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('aguanta el texto al 130 % en pantalla estrecha', (tester) async {
    await pumpThemed(
      tester,
      card,
      textScale: 1.3,
      surfaceSize: const Size(320, 600),
    );
    expect(tester.takeException(), isNull);
  });
}
