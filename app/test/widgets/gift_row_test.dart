import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/core/widgets/gift_row.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('muestra nombre, quien regala, precio y estado', (tester) async {
    await pumpThemed(
      tester,
      const GiftRow(
        name: 'Estación de bomberos de bloques',
        giverName: 'Nosotros',
        giverColorIndex: 0,
        price: '49,99 €',
        status: GiftStatus.bought,
      ),
    );
    expect(find.text('Estación de bomberos de bloques'), findsOneWidget);
    expect(find.text('Nosotros'), findsOneWidget);
    expect(find.text('49,99 €'), findsOneWidget);
    expect(find.text('Comprado'), findsOneWidget);
  });

  testWidgets('la casilla de estado avisa del toque', (tester) async {
    var taps = 0;
    await pumpThemed(
      tester,
      GiftRow(
        name: 'Patinete',
        giverName: 'Sin asignar',
        status: GiftStatus.idea,
        onStatusTap: () => taps++,
      ),
    );
    await tester.tap(
      find.bySemanticsLabel(RegExp('Cambiar estado de Patinete')),
    );
    expect(taps, 1);
  });

  testWidgets('la fila mide al menos 60 px y no desborda al 130 %', (
    tester,
  ) async {
    await pumpThemed(
      tester,
      const GiftRow(
        name: 'Libro de dinosaurios con solapas y pegatinas',
        giverName: 'Tía Marta y Jordi',
        giverColorIndex: 1,
        price: '18 €',
        note: 'Lo pidió Aritz',
        status: GiftStatus.decided,
      ),
      textScale: 1.3,
      surfaceSize: const Size(320, 600),
    );
    expect(
      tester.getSize(find.byType(GiftRow)).height,
      greaterThanOrEqualTo(60),
    );
    expect(tester.takeException(), isNull);
  });
}
