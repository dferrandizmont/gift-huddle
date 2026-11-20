import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/widgets/occasion_countdown_card.dart';

import '../helpers/pump_app.dart';

// La tarjeta compacta de «Resumen» (la de arriba de la lista de Personas en
// la tablet) crece con la letra grande en vez de tener un alto fijo.
void main() {
  for (final size in const [Size(800, 1280), Size(1280, 800)]) {
    for (final scale in const [1.0, 1.5, 2.0]) {
      testWidgets('no desborda a $scale en ${size.width.toInt()} × '
          '${size.height.toInt()}', (tester) async {
        await pumpThemed(
          tester,
          // Como en la columna: dentro de una lista, sin alto fijo.
          SizedBox(
            width: 320,
            child: ListView(
              shrinkWrap: true,
              children: const [
                OccasionCountdownCard(
                  days: 10,
                  unit: 'días',
                  title: 'Cumpleaños de Leo',
                  date: '29 nov',
                  meta: 'Sin regalos todavía',
                  compact: true,
                ),
              ],
            ),
          ),
          textScale: scale,
          surfaceSize: size,
        );
        expect(tester.takeException(), isNull);
        final height = tester
            .getSize(find.byType(OccasionCountdownCard))
            .height;
        expect(
          height,
          greaterThanOrEqualTo(OccasionCountdownCard.compactHeight),
        );
        if (scale == 1.0) {
          expect(height, OccasionCountdownCard.compactHeight);
        }
      });
    }
  }
}
