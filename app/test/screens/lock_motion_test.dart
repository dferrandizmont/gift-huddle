import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/motion/stagger.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/lock/application/lock_controller.dart';
import 'package:regalos/features/lock/presentation/lock_screen.dart';
import 'package:regalos/features/lock/presentation/pin_pad.dart';

import '../helpers/memory_stores.dart';
import '../lock/lock_gate_test.dart' show pumpGate, settle, typePin;
import '../widgets/pin_shake_test.dart' show recordHaptics;

void main() {
  late FakePhone phone;

  setUp(() async {
    phone = FakePhone();
    await phone.container
        .read(familyControllerProvider.notifier)
        .createFamily(deviceName: 'A');
    await phone.container.read(lockControllerProvider.notifier).setPin('4821');
    phone.restart(); // arranque en frío
  });
  tearDown(() => phone.dispose());

  void reduceMotion(WidgetTester tester) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }

  double dotsX(WidgetTester tester) =>
      tester.getTopLeft(find.byType(PinDots)).dx;

  for (final reduce in [false, true]) {
    testWidgets(
      'un PIN erróneo ${reduce ? 'con «Reducir movimiento» no tiembla y tiñe '
                'los anillos' : 'hace temblar los puntos'} y vibra fuerte',
      (tester) async {
        if (reduce) {
          reduceMotion(tester);
        }
        final haptics = recordHaptics(tester);
        await pumpGate(tester, phone);
        final rest = dotsX(tester);

        await typePin(tester, '0000');
        await settle(tester);
        expect(find.textContaining('PIN incorrecto'), findsOneWidget);
        expect(haptics, contains('HapticFeedbackType.heavyImpact'));

        var shift = 0.0;
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 40));
          shift = math.max(shift, (dotsX(tester) - rest).abs());
          // Los puntos siguen llenos mientras dura el error.
          expect(tester.widget<PinDots>(find.byType(PinDots)).count, 4);
        }
        if (reduce) {
          expect(shift, 0);
          expect(tester.widget<PinDots>(find.byType(PinDots)).error, isTrue);
        } else {
          expect(shift, greaterThan(6));
        }
        // Al acabar se vacían y el PIN vuelve a poder escribirse.
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(tester.widget<PinDots>(find.byType(PinDots)).count, 0);
        expect(dotsX(tester), rest);
      },
    );
  }

  for (final reduce in [false, true]) {
    testWidgets(
      'al acertar el PIN el bloqueo se funde ${reduce ? 'en 150 ms' : 'y crece '
                '375 ms'} y la app aparece debajo, sin corte',
      (tester) async {
        if (reduce) {
          reduceMotion(tester);
        }
        await pumpGate(tester, phone);
        await typePin(tester, '4821');
        await settle(tester);
        // A mitad del fundido conviven el bloqueo que se va y la app.
        await tester.pump(const Duration(milliseconds: 60));
        expect(find.byType(LockScreen), findsOneWidget);
        expect(find.text('LA APP'), findsOneWidget);
        // El que se va no recibe toques.
        expect(
          find.ancestor(
            of: find.byType(LockScreen),
            matching: find.byType(IgnorePointer),
          ),
          findsWidgets,
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(find.byType(LockScreen), findsNothing);
        expect(find.text('LA APP'), findsOneWidget);
      },
    );
  }

  // El desbloqueo en cascada (§1+.4, momento Q).
  group('el desbloqueo en cascada', () {
    Widget app() => StaggerScope(
      child: Column(
        children: [
          for (var i = 0; i < 3; i++)
            StaggerItem(
              index: i,
              child: SizedBox(key: Key('fila$i'), width: 60, height: 20),
            ),
        ],
      ),
    );

    // `StaggerItem` funde con `FadeTransition`; el más cercano a la fila es el suyo.
    double opacityOf(WidgetTester tester, int i) => tester
        .widget<FadeTransition>(
          find
              .ancestor(
                of: find.byKey(Key('fila$i')),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;

    /// La mayor escala de un punto del PIN que se está pintando.
    double dotScale(WidgetTester tester) {
      var best = 1.0;
      for (final t in tester.widgetList<Transform>(
        find.descendant(
          of: find.byType(PinDots),
          matching: find.byType(Transform),
        ),
      )) {
        best = math.max(best, t.transform.storage[0]);
      }
      return best;
    }

    double lockOpacity(WidgetTester tester) => tester
        .widget<Opacity>(
          find
              .ancestor(
                of: find.byType(LockScreen),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;

    testWidgets('los puntos laten de uno en uno y el candado espera 80 ms', (
      tester,
    ) async {
      await pumpGate(tester, phone, child: app());
      await typePin(tester, '4821');
      await settle(tester);
      // Los cuatro puntos siguen llenos mientras late la ola.
      expect(tester.widget<PinDots>(find.byType(PinDots)).count, 4);
      expect(tester.widget<PinDots>(find.byType(PinDots)).wave, isNotNull);
      var peak = 1.0;
      for (var i = 0; i < 12; i++) {
        peak = math.max(peak, dotScale(tester));
        // Durante los primeros 80 ms el candado aún no ha empezado a irse.
        if (i < 2) {
          expect(lockOpacity(tester), 1);
        }
        await tester.pump(const Duration(milliseconds: 30));
      }
      // Late hasta 1,35 y vuelve a 1.
      expect(peak, greaterThan(1.2));
      // (El último punto aún trae el rebote de rellenarse: 1,35 × 1,18.)
      expect(peak, lessThanOrEqualTo(1.6));
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsNothing);
      expect(dotScale(tester), 1);
    });

    testWidgets('debajo, la app no aparece entera: las filas entran a 24 ms '
        'con 140 ms de retardo base', (tester) async {
      await pumpGate(tester, phone, child: app());
      await typePin(tester, '4821');
      await settle(tester);
      // Espera los 80 ms del primer latido y arranca el desbloqueo.
      await tester.pump(const Duration(milliseconds: 90));
      await tester.pump(const Duration(milliseconds: 40));
      // Dentro del retardo base de 140 ms aún no se ve ninguna fila.
      expect(opacityOf(tester, 0), 0);
      expect(opacityOf(tester, 2), 0);
      await tester.pump(const Duration(milliseconds: 260));
      expect(opacityOf(tester, 0), greaterThan(opacityOf(tester, 2)));
      await tester.pumpAndSettle();
      expect(opacityOf(tester, 2), 1);
    });

    testWidgets('con «Reducir movimiento»: sin ola, sin espera y sin '
        'cascada', (tester) async {
      reduceMotion(tester);
      await pumpGate(tester, phone, child: app());
      await typePin(tester, '4821');
      await settle(tester);
      expect(tester.widget<PinDots>(find.byType(PinDots)).wave, isNull);
      expect(dotScale(tester), 1);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsNothing);
      expect(opacityOf(tester, 2), 1);
    });
  });
}
