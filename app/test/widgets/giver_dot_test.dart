import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/core/widgets/giver_dot.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('pinta un punto de 8 px con el color claro de quien regala', (
    tester,
  ) async {
    await pumpThemed(tester, const GiverDot(colorIndex: 0));
    expect(tester.getSize(find.byType(GiverDot)), const Size(8, 8));
    final deco = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(GiverDot),
        matching: find.byType(DecoratedBox),
      ),
    );
    expect((deco.decoration as BoxDecoration).color, giverColors[0].$1);
  });

  testWidgets('en oscuro usa la variante clara del color', (tester) async {
    await pumpThemed(
      tester,
      const GiverDot(colorIndex: 2),
      brightness: Brightness.dark,
    );
    final deco = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(GiverDot),
        matching: find.byType(DecoratedBox),
      ),
    );
    expect((deco.decoration as BoxDecoration).color, giverColors[2].$2);
  });

  testWidgets('el índice se repite pasados los seis colores', (tester) async {
    await pumpThemed(tester, const GiverDot(colorIndex: 6));
    final deco = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(GiverDot),
        matching: find.byType(DecoratedBox),
      ),
    );
    expect((deco.decoration as BoxDecoration).color, giverColors[0].$1);
  });

  testWidgets(
    'sin color es un círculo discontinuo y sin etiqueta por defecto',
    (tester) async {
      final handle = tester.ensureSemantics();
      await pumpThemed(tester, const GiverDot());
      expect(
        find.descendant(
          of: find.byType(GiverDot),
          matching: find.byType(CustomPaint),
        ),
        findsWidgets,
      );
      expect(find.bySemanticsLabel('Sin asignar'), findsNothing);
      handle.dispose();
    },
  );

  testWidgets('con semanticLabel lo lee el lector de pantalla', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpThemed(
      tester,
      const GiverDot(colorIndex: 1, semanticLabel: 'Tío Pere'),
    );
    expect(find.bySemanticsLabel('Tío Pere'), findsOneWidget);
    handle.dispose();
  });
}
