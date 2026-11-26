// Las líneas de trozos separados por « · » (el resumen de la cabecera de una
// persona): el separador va siempre al final del trozo anterior y nunca abre
// una línea, con letra normal, ×1,5 y ×2.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/widgets/dot_line.dart';

import '../helpers/fonts.dart';
import '../helpers/pump_app.dart';

/// Las líneas (su `dy` arriba) donde cae el «·» de cada trozo y la letra
/// anterior; si no coinciden, el separador abrió una línea.
void expectSeparatorsStayAtLineEnd(WidgetTester tester) {
  final dots = find.byWidgetPredicate(
    (w) => w is Text && (w.data ?? '').endsWith(DotLine.glue),
  );
  expect(dots, findsWidgets);
  for (final element in dots.evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    final text = paragraph.text.toPlainText();
    final at = text.length - 1;
    final dot = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: at, extentOffset: at + 1),
    );
    final before = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: at - 2, extentOffset: at - 1),
    );
    expect(dot, isNotEmpty);
    expect(before, isNotEmpty);
    expect(
      dot.first.top,
      before.first.top,
      reason: '«$text»: el «·» no puede quedarse solo en la línea de abajo',
    );
  }
}

void main() {
  setUpAll(loadInter);

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('cortar entre trozos: «·» al final, nunca al principio '
        '(letra ×$scale)', (tester) async {
      await pumpThemed(
        tester,
        const SizedBox(
          width: 250,
          child: DotLine(
            style: TextStyle(fontSize: 13, height: 18 / 13),
            parts: [
              DotPart('3 años'),
              DotPart('10 regalos', rollValue: 10),
              DotPart('Cumpleaños de Nora de la tía Marta'),
              DotPart('2 de 3 comprados', rollValue: 2),
            ],
          ),
        ),
        textScale: scale,
      );
      // Ningún trozo empieza por el separador.
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        expect((text.data ?? '').trimLeft().startsWith('·'), isFalse);
      }
      expectSeparatorsStayAtLineEnd(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('el lector de pantalla lee cada trozo sin el «·»', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpThemed(
      tester,
      const DotLine(
        style: TextStyle(fontSize: 13),
        parts: [DotPart('3 años'), DotPart('10 regalos', rollValue: 10)],
      ),
    );
    expect(find.bySemanticsLabel('3 años'), findsOneWidget);
    expect(find.bySemanticsLabel('10 regalos'), findsOneWidget);
    handle.dispose();
  });
}
