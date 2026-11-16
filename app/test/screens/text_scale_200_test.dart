import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/screens.dart';

// F5: con el texto al 200 % las etiquetas de la barra inferior y los títulos
// de Ajustes no se cortan.
void main() {
  screenTest(
    'texto al 200 %: la barra no corta las etiquetas y Apariencia cabe entera',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);

      // Las cuatro etiquetas comparten el tamaño que deja caber la más larga:
      // enteras (sin «…»), dentro de su hueco y sin que ninguna se encoja por
      // su cuenta.
      final sizes = <double>{};
      for (final label in ['Personas', 'Reparto', 'Ocasiones', 'Ajustes']) {
        final text = find.text(label).last;
        sizes.add(tester.widget<Text>(text).style!.fontSize!);
        expect(
          tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
          isFalse,
          reason: label,
        );
        expect(
          find.ancestor(of: text, matching: find.byType(FittedBox)),
          findsNothing,
          reason: label,
        );
        final r = tester.getRect(text);
        expect(r.left, greaterThanOrEqualTo(0), reason: label);
        expect(r.right, lessThanOrEqualTo(400), reason: label);
      }
      expect(sizes.length, 1, reason: '$sizes');

      await tester.tap(find.text('Ajustes').last);
      await settle(tester);
      final row = find.text('Apariencia');
      await tester.scrollUntilVisible(
        row,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester);
      // El valor queda debajo del título, no al lado (la fila crece en alto;
      // el desborde de la tarjeta de cuenta atrás es de la fuente de prueba).
      final title = tester.getRect(row);
      final value = find.textContaining('·');
      expect(value, findsOneWidget);
      expect(tester.getTopLeft(value).dy, greaterThan(title.bottom - 2));
      tester.takeException();
    },
    textScale: 2,
  );
}
