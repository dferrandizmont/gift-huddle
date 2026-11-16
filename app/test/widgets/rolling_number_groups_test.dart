import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/motion/rolling_number.dart';

import '../helpers/pump_app.dart';

/// La mayor opacidad con la que se ve [char] (cada columna reserva su ancho
/// con otro texto invisible).
double _opacityOf(WidgetTester tester, String char) {
  var best = 0.0;
  for (final o in tester.widgetList<Opacity>(
    find.ancestor(of: find.text(char), matching: find.byType(Opacity)),
  )) {
    if (o.opacity > best) {
      best = o.opacity;
    }
  }
  return best;
}

void main() {
  group('RollingNumber.text con leftToRight', () {
    Future<void> pump(WidgetTester tester, {bool reduce = false}) => pumpThemed(
      tester,
      const RollingNumber.text(
        text: '123 456',
        rollFromEmpty: true,
        leftToRight: true,
        style: TextStyle(fontSize: 20),
      ),
      disableAnimations: reduce,
    );

    testWidgets('el primer grupo entra antes que el segundo y todo acaba '
        'quieto', (tester) async {
      await pump(tester);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      // El grupo de la izquierda ya aparece; el de la derecha espera.
      expect(_opacityOf(tester, '1'), greaterThan(0));
      expect(_opacityOf(tester, '4'), 0);

      await tester.pump(const Duration(milliseconds: 120));
      expect(_opacityOf(tester, '4'), greaterThan(0));

      await tester.pumpAndSettle();
      expect(find.text('123 456'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('con «Reducir movimiento» se cruzan sin desplazarse', (
      tester,
    ) async {
      await pump(tester, reduce: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byType(FractionalTranslation), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('123 456'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
