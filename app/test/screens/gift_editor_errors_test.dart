import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/screens.dart';

// F4: los errores de «Para quién» y de «Regalo» se alinean igual.
void main() {
  screenTest('en el editor, los errores de Para quién y Regalo van alineados', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await tester.tap(
      find.widgetWithText(FloatingActionButton, 'Añadir regalo'),
    );
    await settle(tester);
    await tapText(tester, 'Guardar');
    await settle(tester);

    final who = find.text('Elige para quién es el regalo.');
    final what = find.text('Escribe qué regalo es.');
    expect(who, findsOneWidget);
    expect(what, findsOneWidget);
    expect(tester.widget<Text>(who).textAlign, TextAlign.start);
    // A la izquierda, junto al margen del campo, no centrado.
    final field = tester.getTopLeft(find.widgetWithText(TextField, 'Regalo'));
    expect(tester.getTopLeft(who).dx, lessThan(field.dx + 20));
    expect(
      (tester.getTopLeft(who).dx - tester.getTopLeft(what).dx).abs(),
      lessThan(4),
    );
  });
}
