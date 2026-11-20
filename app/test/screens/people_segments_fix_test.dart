// Personas en el móvil tras el rediseño: el texto de estado va pegado a la
// barra de segmentos (no flota a media fila) y con muchos regalos la barra
// no se desborda: reparte el hueco o pasa a una barra proporcional.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/model.dart' show Gift, GiftStatus;
import 'package:regalos/core/widgets/gift_segments.dart';
import 'package:regalos/core/theme/regalos_shape.dart';

import '../helpers/fonts.dart';
import '../helpers/pump_app.dart';
import '../helpers/screens.dart';

void main() {
  setUpAll(loadInter);

  group('GiftSegments', () {
    test('con sitio, segmentos de 18 y hueco de 3', () {
      final l = GiftSegments.layoutFor(5, 200)!;
      expect(l.width, RegalosSizes.segmentWidth);
      expect(l.gap, RegalosSizes.segmentGap);
    });

    test('con poco sitio baja el hueco y estrecha los segmentos', () {
      final l = GiftSegments.layoutFor(12, 160)!;
      expect(l.gap, lessThan(RegalosSizes.segmentGap));
      expect(l.width, lessThan(RegalosSizes.segmentWidth));
      expect(12 * l.width + 11 * l.gap, lessThanOrEqualTo(160 + 0.001));
    });

    test('cuando los segmentos ya no se distinguen, barra proporcional', () {
      expect(GiftSegments.layoutFor(40, 90), isNull);
    });

    testWidgets('40 regalos en 90 de ancho: una barra que cabe y sin errores', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        const Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 90,
            child: GiftSegments(total: 40, done: 10, color: Colors.purple),
          ),
        ),
      );
      final bar = find.byKey(const ValueKey('segments-bar'));
      expect(bar, findsOneWidget);
      expect(tester.getSize(bar).width, lessThanOrEqualTo(90));
      expect(tester.takeException(), isNull);
    });
  });

  screenTest('una persona con 40 regalos a 360 de ancho no desborda la fila', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => familyOf(phone).upsertGift(
          Gift(
            id: 'many-$i',
            recipientId: 'aritz',
            title: 'Regalo $i',
            status: i < 15 ? GiftStatus.bought : GiftStatus.idea,
            rawStatus: i < 15 ? 'bought' : 'idea',
            surprise: false,
            year: 2026,
          ),
        ),
      );
    }
    await pumpRegalos(tester, phone);
    expect(tester.takeException(), isNull);
    // Las barras de las filas caben en su fila.
    for (final e in find.byType(GiftSegments).evaluate()) {
      final r = tester.getRect(find.byElementPredicate((x) => x == e));
      expect(r.right, lessThanOrEqualTo(360 * 0.62));
    }
  }, size: const Size(360, 800));

  screenTest('el texto de estado va a continuación de la barra, a 10 de ella', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    final status = find.textContaining('por comprar').first;
    final statusRect = tester.getRect(status);
    // La barra de segmentos de la misma fila (la más cercana por encima).
    final bars = find
        .byType(GiftSegments)
        .evaluate()
        .map((e) => tester.getRect(find.byElementPredicate((x) => x == e)));
    final bar = bars.firstWhere(
      (r) => (r.center.dy - statusRect.center.dy).abs() < 8,
    );
    expect(statusRect.left - bar.right, closeTo(10, 0.5));
  }, size: const Size(390, 844));
}
