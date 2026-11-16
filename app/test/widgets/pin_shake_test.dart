import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/motion/shake.dart';
import 'package:regalos/core/theme/regalos_motion.dart';
import 'package:regalos/features/lock/presentation/pin_pad.dart';

import '../helpers/pump_app.dart';

/// Recoge la háptica que pide la app (`HapticFeedback.vibrate` con su tipo).
List<String> recordHaptics(WidgetTester tester) {
  final haptics = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        haptics.add(call.arguments as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return haptics;
}

void main() {
  test(
    'el muelle del temblor: primer pico de unos 10 px y apagado en ~560 ms',
    () {
      final sim = RegalosShake.simulation();
      var peak = 0.0;
      for (var ms = 0; ms <= 120; ms++) {
        peak = math.max(peak, sim.x(ms / 1000).abs());
      }
      expect(peak, inInclusiveRange(9, 11.5));
      // Oscila en los dos sentidos (un vaivén, no un rebote que se asienta).
      expect(sim.x(0.045), greaterThan(8));
      expect(sim.x(0.16), lessThan(-3));
      expect(sim.isDone(0.3), isFalse);
      expect(sim.isDone(0.65), isTrue);
    },
  );

  for (final reduce in [false, true]) {
    final name = reduce ? 'con «Reducir movimiento»' : 'con movimiento';

    testWidgets('un PIN erróneo $name: vibra fuerte y los puntos '
        '${reduce ? 'se tiñen y no tiemblan' : 'tiemblan'}', (tester) async {
      final haptics = recordHaptics(tester);
      final display = GlobalKey<PinDisplayState>();
      Future<void> pump(int count) => pumpThemed(
        tester,
        PinDisplay(key: display, count: count, total: 4),
        disableAnimations: reduce,
      );
      double x() => tester.getTopLeft(find.byType(PinDots)).dx;
      PinDots dots() => tester.widget<PinDots>(find.byType(PinDots));

      await pump(4);
      final rest = x();

      // Quien llama vacía su PIN y avisa del error en el mismo fotograma.
      display.currentState!.fail(4);
      await pump(0);
      expect(haptics, ['HapticFeedbackType.heavyImpact']);

      var maxShift = 0.0;
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        maxShift = math.max(maxShift, (x() - rest).abs());
        // Mientras dura el error los puntos siguen llenos.
        expect(dots().count, 4);
      }
      if (reduce) {
        expect(maxShift, 0, reason: 'con reducir no se traslada nada');
        expect(dots().error, isTrue);
        expect(
          find.descendant(
            of: find.byType(PinDisplay),
            matching: find.byType(Transform),
          ),
          findsNothing,
        );
      } else {
        expect(maxShift, inInclusiveRange(7, 12));
        expect(dots().error, isFalse);
      }

      // Al acabar se vacían a la vez, en 180 ms con `fold`.
      await tester.pump(const Duration(milliseconds: 300));
      expect(dots().count, 0);
      expect(dots().error, isFalse);
      expect(dots().clearDuration, const Duration(milliseconds: 180));
      await tester.pumpAndSettle();
      expect(x(), rest);
    });
  }

  testWidgets('el primer dígito nuevo corta el temblor y vacía al momento', (
    tester,
  ) async {
    recordHaptics(tester);
    final display = GlobalKey<PinDisplayState>();
    Future<void> pump(int count) =>
        pumpThemed(tester, PinDisplay(key: display, count: count, total: 4));
    double x() => tester.getTopLeft(find.byType(PinDots)).dx;
    PinDots dots() => tester.widget<PinDots>(find.byType(PinDots));

    await pump(4);
    final rest = x();
    display.currentState!.fail(4);
    await pump(0);
    await tester.pump(const Duration(milliseconds: 60));
    expect((x() - rest).abs(), greaterThan(3));

    // Se escribe un dígito a mitad del temblor.
    await pump(1);
    await tester.pump();
    expect(x(), rest);
    expect(dots().count, 1);
    expect(dots().clearDuration, Duration.zero);

    // Y ya no queda nada pendiente: el siguiente borrado vuelve a 120 ms.
    await tester.pumpAndSettle();
    await pump(0);
    expect(dots().clearDuration, const Duration(milliseconds: 120));
  });

  testWidgets('ShakeX con «Reducir movimiento» no hace nada', (tester) async {
    final key = GlobalKey<ShakeXState>();
    await pumpThemed(
      tester,
      ShakeX(key: key, child: const SizedBox(width: 20, height: 20)),
      disableAnimations: true,
    );
    key.currentState!.shake();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.descendant(
        of: find.byType(ShakeX),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
  });
}
