import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/widgets/occasion_countdown_card.dart';

import '../helpers/pump_app.dart';

// La fila de la próxima ocasión de encima de la lista de Personas (la de «10»,
// «Cumpleaños de Leo»...) crece con la letra grande en vez de tener 56 fijos.
void main() {
  for (final size in const [Size(1280, 800), Size(800, 1280)]) {
    for (final scale in const [1.0, 1.5, 2.0]) {
      testWidgets(
        'no desborda a $scale en ${size.width.toInt()} × ${size.height.toInt()}',
        (tester) async {
          await pumpThemed(
            tester,
            const SizedBox(
              width: 320,
              child: OccasionSummaryRow(
                days: 10,
                unit: 'días',
                title: 'Cumpleaños de Leo',
                date: '29 nov',
                meta: 'Sin regalos todavía',
              ),
            ),
            textScale: scale,
            surfaceSize: size,
          );
          expect(tester.takeException(), isNull);
          final height = tester.getSize(find.byType(OccasionSummaryRow)).height;
          if (scale == 1.0) {
            expect(height, OccasionSummaryRow.rowHeight);
          } else {
            // Crece con la letra en vez de encoger el texto a 56.
            expect(height, greaterThan(OccasionSummaryRow.rowHeight));
          }
        },
      );
    }
  }
}
