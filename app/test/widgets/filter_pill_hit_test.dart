import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/widgets/filter_pill.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('la zona de toque del filtro es de 44, no solo el dibujo de 36', (
    tester,
  ) async {
    var taps = 0;
    await pumpThemed(
      tester,
      Center(
        child: FilterPill(label: 'Falta comprar', onTap: () => taps++),
      ),
    );
    final pill = find.text('Falta comprar');
    final center = tester.getCenter(pill);
    final target = tester.getRect(
      find
          .descendant(
            of: find.byType(FilterPill),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    expect(target.height, greaterThanOrEqualTo(44));
    // 20 por encima del centro: fuera del dibujo (18 de medio alto) y dentro
    // de los 22 de media zona de toque.
    await tester.tapAt(center + const Offset(0, -20));
    await tester.pump();
    expect(taps, 1);
    await tester.tapAt(center + const Offset(0, 20));
    await tester.pump();
    expect(taps, 2);
    // Más allá de los 44 no cuenta.
    await tester.tapAt(center + const Offset(0, -30));
    await tester.pump();
    expect(taps, 2);
  });
}
