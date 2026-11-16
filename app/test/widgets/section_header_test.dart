import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/core/widgets/section_header.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('muestra título y dato a la derecha', (tester) async {
    await pumpThemed(
      tester,
      const SectionHeader(title: 'Tió', trailing: '24 dic'),
    );
    expect(find.text('Tió'), findsOneWidget);
    expect(find.text('24 dic'), findsOneWidget);
  });

  testWidgets('el título es una cabecera para el lector de pantalla', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpThemed(tester, const SectionHeader(title: 'Reyes'));
    expect(
      tester.getSemantics(find.text('Reyes')),
      matchesSemantics(label: 'Reyes', isHeader: true),
    );
    handle.dispose();
  });

  testWidgets('con filete usa el separador del tema', (tester) async {
    await pumpThemed(tester, const SectionHeader(title: 'Reyes'));
    final t = RegalosTokens.of(tester.element(find.byType(SectionHeader)));
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(SectionHeader),
        matching: find.byType(Container),
      ),
    );
    final border = (container.decoration! as BoxDecoration).border! as Border;
    expect(border.bottom.color, t.separator);
  });

  testWidgets('sin filete no dibuja decoración', (tester) async {
    await pumpThemed(
      tester,
      const SectionHeader(title: 'Color', bordered: false),
    );
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(SectionHeader),
        matching: find.byType(Container),
      ),
    );
    expect(container.decoration, isNull);
  });

  testWidgets('un título largo no desborda al 130 %', (tester) async {
    await pumpThemed(
      tester,
      const SectionHeader(
        title: 'Pendiente de comprar en la juguetería del barrio',
        trailing: '4 regalos',
      ),
      textScale: 1.3,
      surfaceSize: const Size(320, 600),
    );
    expect(tester.takeException(), isNull);
  });
}
