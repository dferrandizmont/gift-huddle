import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/sharing/presentation/scan_viewfinder.dart';

import '../helpers/pump_app.dart';

dynamic _painter(WidgetTester tester) {
  final painter = find.descendant(
    of: find.byType(ScanViewfinder),
    matching: find.byType(CustomPaint),
  );
  return tester.widget<CustomPaint>(painter.first).painter;
}

void main() {
  _beginTests();
  Future<GlobalKey<ScanViewfinderState>> pump(
    WidgetTester tester, {
    bool reduce = false,
  }) async {
    final key = GlobalKey<ScanViewfinderState>();
    await pumpThemed(
      tester,
      SizedBox(width: 300, height: 300, child: ScanViewfinder(key: key)),
      disableAnimations: reduce,
    );
    return key;
  }

  group('el visor del lector: entrada y destello', () {
    testWidgets('las esquinas llegan abiertas y se asientan; la línea de luz '
        'recorre el cuadro una vez', (tester) async {
      await pump(tester);
      await tester.pump();
      expect(_painter(tester).arrive as double, lessThan(1));

      await tester.pump(const Duration(milliseconds: 100));
      final mid = _painter(tester).arrive as double;
      expect(mid, inExclusiveRange(0, 1));
      expect(_painter(tester).sweep, isNull);

      // Pasada la entrada de las esquinas, la línea baja por el cuadro.
      await tester.pump(const Duration(milliseconds: 500));
      final line = _painter(tester).sweep as double?;
      expect(line, isNotNull);
      expect(line, inExclusiveRange(0, 1));

      await tester.pumpAndSettle();
      expect(_painter(tester).arrive, 1);
      expect(_painter(tester).sweep, isNull);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('al cerrarse sobre un código hay un destello pastel que se '
        'apaga', (tester) async {
      final key = await pump(tester);
      await tester.pumpAndSettle();
      expect(_painter(tester).flash, 0);

      key.currentState!.lock(const Rect.fromLTWH(110, 110, 80, 80));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(_painter(tester).flash as double, greaterThan(0));

      await tester.pumpAndSettle();
      expect(_painter(tester).flash, 0);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('si la lectura falla, la línea de luz vuelve a buscar', (
      tester,
    ) async {
      final key = await pump(tester);
      await tester.pumpAndSettle();
      key.currentState!.lock(null);
      await tester.pumpAndSettle();
      expect(_painter(tester).sweep, isNull);

      key.currentState!.reset();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(_painter(tester).sweep, isNotNull);
      await tester.pumpAndSettle();
      expect(_painter(tester).sweep, isNull);
    });

    testWidgets('con «Reducir movimiento» no hay entrada, línea ni destello', (
      tester,
    ) async {
      final key = await pump(tester, reduce: true);
      await tester.pump();
      expect(_painter(tester).arrive, 1);
      await tester.pump(const Duration(milliseconds: 600));
      expect(_painter(tester).sweep, isNull);

      key.currentState!.lock(const Rect.fromLTWH(110, 110, 80, 80));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(_painter(tester).flash, 0);
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}

void _beginTests() {
  group('el visor del lector: arranque con la cámara', () {
    testWidgets('con autoStart falso las esquinas esperan a begin() y solo '
        'entran una vez', (tester) async {
      final key = GlobalKey<ScanViewfinderState>();
      await pumpThemed(
        tester,
        SizedBox(
          width: 300,
          height: 300,
          child: ScanViewfinder(key: key, autoStart: false),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(_painter(tester).arrive, 0);

      key.currentState!.begin();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_painter(tester).arrive as double, inExclusiveRange(0, 1));

      await tester.pumpAndSettle();
      expect(_painter(tester).arrive, 1);
      // Una segunda llamada no repite la entrada.
      key.currentState!.begin();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_painter(tester).arrive, 1);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
