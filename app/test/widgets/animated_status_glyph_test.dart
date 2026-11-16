import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/motion/animated_status_glyph.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/core/widgets/status_checkbox.dart';

import '../helpers/pump_app.dart';

StatusGlyphPainter painter(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is StatusGlyphPainter,
    ),
  );
  return paint.painter! as StatusGlyphPainter;
}

/// Las escalas y traslaciones de los `Transform` de la casilla.
List<Matrix4> transforms(WidgetTester tester) => [
  for (final t in tester.widgetList<Transform>(
    find.descendant(
      of: find.byType(AnimatedStatusGlyph),
      matching: find.byType(Transform),
    ),
  ))
    t.transform,
];

void main() {
  Future<void> pump(
    WidgetTester tester,
    GiftStatus status, {
    bool reduce = false,
  }) => pumpThemed(
    tester,
    AnimatedStatusGlyph(status: status),
    disableAnimations: reduce,
  );

  testWidgets('se construye ya en su estado, sin animar', (tester) async {
    await pump(tester, GiftStatus.arrived);
    expect(tester.hasRunningAnimations, isFalse);
    expect(painter(tester).sweep, 0.5);
    expect(transforms(tester), isEmpty);
  });

  testWidgets('el sector barre de un estado al siguiente y la casilla rebota', (
    tester,
  ) async {
    await pump(tester, GiftStatus.bought);
    expect(painter(tester).sweep, 0.25);

    await pump(tester, GiftStatus.arrived);
    await tester.pump(const Duration(milliseconds: 60));
    final mid = painter(tester).sweep!;
    // A mitad de camino entre ¼ y ½, no ya en el destino.
    expect(mid, inExclusiveRange(0.27, 0.5));
    // Toda la casilla rebota: parte de 0,78 y crece.
    final scale = transforms(tester).single.storage[0];
    expect(scale, lessThan(1));

    await tester.pumpAndSettle();
    expect(painter(tester).sweep, closeTo(0.5, 0.001));
  });

  testWidgets(
    'de idea a decidido se cruza el trazo discontinuo con el anillo',
    (tester) async {
      await pump(tester, GiftStatus.idea);
      expect(painter(tester).solid, 0);
      await pump(tester, GiftStatus.decided);
      await tester.pump(const Duration(milliseconds: 100));
      expect(painter(tester).solid, closeTo(0.5, 0.1));
      await tester.pumpAndSettle();
      expect(painter(tester).solid, 1);
    },
  );

  testWidgets('entregado: el círculo crece y el visto se dibuja con retraso', (
    tester,
  ) async {
    await pump(tester, GiftStatus.wrapped);
    await pump(tester, GiftStatus.delivered);
    // Antes de los 120 ms el visto aún no ha empezado.
    await tester.pump(const Duration(milliseconds: 80));
    expect(painter(tester).grow, greaterThan(0.3));
    expect(painter(tester).check, 0);
    await tester.pump(const Duration(milliseconds: 120));
    expect(painter(tester).check, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(painter(tester).grow, closeTo(1, 0.001));
    expect(painter(tester).check, 1);

    // Al volver atrás: la misma animación al revés y sin rebote.
    await pump(tester, GiftStatus.wrapped);
    await tester.pumpAndSettle();
    expect(painter(tester).grow, 0);
    expect(painter(tester).check, 0);
    expect(painter(tester).sweep, closeTo(0.75, 0.001));
  });

  testWidgets('con «Reducir movimiento» hay fundido y ni barrido ni rebote', (
    tester,
  ) async {
    await pump(tester, GiftStatus.bought, reduce: true);
    await pump(tester, GiftStatus.arrived, reduce: true);
    await tester.pump(const Duration(milliseconds: 60));
    // La casilla vieja y la nueva conviven mientras se funden...
    expect(find.byType(StatusGlyph), findsNWidgets(2));
    expect(find.byType(FadeTransition), findsWidgets);
    // ...y nada se escala ni se traslada.
    for (final m in transforms(tester)) {
      expect(m.storage[0], 1);
      expect(m.storage[5], 1);
      expect(m.getTranslation().length, 0);
    }
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(find.byType(StatusGlyph), findsOneWidget);
  });
}
