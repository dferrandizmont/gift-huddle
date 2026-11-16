import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/theme/regalos_motion.dart';
import 'package:regalos/core/widgets/spring_pulse.dart';

void main() {
  group('muelles', () {
    test('cada curva parte de 0, llega a 1 y se asienta en su duración', () {
      for (final curve in [
        RegalosCurves.snap,
        RegalosCurves.bounce,
        RegalosCurves.soft,
      ]) {
        expect(curve.transform(0), 0);
        expect(curve.transform(1), 1);
        expect(curve.transform(0.99), closeTo(1, 0.03));
      }
    });

    test('snap casi no se pasa, bounce rebota y soft no se pasa', () {
      double peak(Curve c) {
        var m = 0.0;
        for (var i = 1; i < 1000; i++) {
          final v = c.transform(i / 1000);
          if (v > m) {
            m = v;
          }
        }
        return m;
      }

      // Los sobrepasos de la tabla del README: casi nada, algo menos de un
      // 20 % y nada.
      expect(peak(RegalosCurves.snap), inInclusiveRange(1.0, 1.012));
      expect(peak(RegalosCurves.bounce), inInclusiveRange(1.15, 1.2));
      expect(peak(RegalosCurves.soft), lessThanOrEqualTo(1.001));
    });
  });

  group('SpringPulse', () {
    Widget host(Object trigger, {bool reduce = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Center(
          child: SpringPulse(
            trigger: trigger,
            child: const SizedBox(key: Key('x'), width: 40, height: 40),
          ),
        ),
      ),
    );

    testWidgets('rebota desde 0,78 al cambiar el disparador y vuelve a 1', (
      tester,
    ) async {
      await tester.pumpWidget(host(1));
      expect(tester.getSize(find.byKey(const Key('x'))), const Size(40, 40));
      await tester.pumpWidget(host(2));
      await tester.pump(const Duration(milliseconds: 1));
      final box = tester.getSize(find.byKey(const Key('x')));
      // El hijo no cambia de tamaño de layout; lo que cambia es la escala.
      expect(box, const Size(40, 40));
      final scale = tester
          .widget<Transform>(
            find
                .descendant(
                  of: find.byType(SpringPulse),
                  matching: find.byType(Transform),
                )
                .first,
          )
          .transform
          .entry(0, 0);
      expect(scale, lessThan(0.9));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(SpringPulse),
          matching: find.byType(Transform),
        ),
        findsNothing,
      );
    });

    testWidgets('con «Reducir movimiento» solo se funde, sin escalar', (
      tester,
    ) async {
      await tester.pumpWidget(host(1, reduce: true));
      await tester.pumpWidget(host(2, reduce: true));
      await tester.pump(const Duration(milliseconds: 20));
      expect(
        find.descendant(
          of: find.byType(SpringPulse),
          matching: find.byType(Transform),
        ),
        findsNothing,
      );
      final opacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(SpringPulse),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, lessThan(1));
      await tester.pump(const Duration(milliseconds: 160));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
