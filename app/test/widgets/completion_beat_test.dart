// «Persona completa» (la ficha «A + Actual»): el cuadrado de la inicial late
// una vez de 1 a 1,08 al quedar completa la persona, y nada con «Reducir
// movimiento» ni al montarse ya completa.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/motion/completion_ring.dart';

import '../helpers/pump_app.dart';

double _scale(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find.descendant(
      of: find.byType(CompletionBeat),
      matching: find.byType(Transform),
    ),
  );
  return transform.transform.getMaxScaleOnAxis();
}

Widget _beat(ValueNotifier<bool> complete) => ValueListenableBuilder<bool>(
  valueListenable: complete,
  builder: (context, c, _) =>
      CompletionBeat(complete: c, child: const SizedBox.square(dimension: 44)),
);

void main() {
  test('la escala sube a 1,08 y vuelve a 1 en 480 ms', () {
    expect(CompletionBeat.scaleAt(0), 1);
    expect(CompletionBeat.scaleAt(190), closeTo(1.08, 1e-9));
    expect(CompletionBeat.scaleAt(100), greaterThan(1.04));
    expect(CompletionBeat.scaleAt(480), 1);
    for (var ms = 0.0; ms <= 480; ms += 10) {
      expect(CompletionBeat.scaleAt(ms), lessThan(1.1));
      expect(CompletionBeat.scaleAt(ms), greaterThanOrEqualTo(1));
    }
  });

  testWidgets('late una vez al quedar completa', (tester) async {
    final complete = ValueNotifier<bool>(false);
    addTearDown(complete.dispose);
    await pumpThemed(tester, Center(child: _beat(complete)));
    expect(_scale(tester), 1);
    complete.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 190));
    expect(_scale(tester), closeTo(1.08, 0.01));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_scale(tester), 1);
  });

  testWidgets('montada ya completa no late', (tester) async {
    final complete = ValueNotifier<bool>(true);
    addTearDown(complete.dispose);
    await pumpThemed(tester, Center(child: _beat(complete)));
    await tester.pump(const Duration(milliseconds: 190));
    expect(_scale(tester), 1);
  });

  testWidgets('con «Reducir movimiento» no escala', (tester) async {
    final complete = ValueNotifier<bool>(false);
    addTearDown(complete.dispose);
    await pumpThemed(
      tester,
      Center(child: _beat(complete)),
      disableAnimations: true,
    );
    complete.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 190));
    expect(_scale(tester), 1);
  });

  testWidgets('si «Reducir movimiento» se activa a mitad del latido, se para '
      'y la escala queda en 1', (tester) async {
    final complete = ValueNotifier<bool>(false);
    final reduce = ValueNotifier<bool>(false);
    addTearDown(complete.dispose);
    addTearDown(reduce.dispose);
    await pumpThemed(
      tester,
      ValueListenableBuilder<bool>(
        valueListenable: reduce,
        builder: (context, r, _) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: r),
          child: Center(child: _beat(complete)),
        ),
      ),
    );
    complete.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_scale(tester), greaterThan(1.02), reason: 'a mitad del latido');
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    reduce.value = true;
    await tester.pump();
    expect(_scale(tester), 1);
    // El controlador está parado: no queda ningún fotograma pendiente.
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(milliseconds: 150));
    expect(_scale(tester), 1);
  });
}
