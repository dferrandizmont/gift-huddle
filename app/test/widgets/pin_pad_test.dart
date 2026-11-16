import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/lock/presentation/pin_pad.dart';

import '../helpers/pump_app.dart';

void main() {
  Future<List<String>> pumpPad(WidgetTester tester) async {
    final digits = <String>[];
    await pumpThemed(
      tester,
      PinPad(onDigit: digits.add, onBackspace: () {}, onBiometric: () {}),
    );
    return digits;
  }

  testWidgets(
    'cada tecla es un rectángulo de 84 por 66 con la tinta recortada',
    (tester) async {
      await pumpPad(tester);
      // Doce teclas: diez dígitos, borrar y huella.
      final inks = find.byType(InkWell);
      expect(inks, findsNWidgets(12));
      for (final ink in tester.widgetList<InkWell>(inks)) {
        expect(ink.customBorder, isA<RoundedRectangleBorder>());
      }
      for (final element in inks.evaluate()) {
        final size = tester.getSize(
          find.byElementPredicate((e) => e == element),
        );
        expect(size, const Size(84, 66));
        // El Material que la envuelve recorta con su forma (radio 8: nada pasa
        // de 8).
        final material = element.findAncestorWidgetOfExactType<Material>()!;
        expect(material.shape, isA<RoundedRectangleBorder>());
        expect(
          (material.shape! as RoundedRectangleBorder).borderRadius,
          const BorderRadius.all(Radius.circular(8)),
        );
        expect(material.clipBehavior, Clip.antiAlias);
      }
    },
  );

  testWidgets(
    'al pulsar, el resplandor tiene la forma de la tecla y no la sobrepasa',
    (tester) async {
      final digits = await pumpPad(tester);
      final key = find.text('5');
      final gesture = await tester.startGesture(tester.getCenter(key));
      await tester.pump(const Duration(milliseconds: 100));
      // La tinta pinta dentro del Material de la tecla, que es un rectángulo de 84
      // por 66 recortado: lo que se ve no sale del cuadrado de la tecla.
      final material = tester.renderObject(
        find.ancestor(of: key, matching: find.byType(Material)).first,
      );
      expect(material.paintBounds.size, const Size(84, 66));
      expect(tester.takeException(), isNull);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(digits, ['5']);
    },
  );

  testWidgets('los dígitos, borrar y la huella responden', (tester) async {
    final digits = <String>[];
    var back = 0;
    var bio = 0;
    await pumpThemed(
      tester,
      PinPad(
        onDigit: digits.add,
        onBackspace: () => back++,
        onBiometric: () => bio++,
      ),
    );
    for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0']) {
      await tester.tap(find.text(d));
    }
    await tester.tap(find.bySemanticsLabel('Borrar'));
    await tester.tap(find.bySemanticsLabel('Usar huella o rostro'));
    expect(digits.join(), '1234567890');
    expect(back, 1);
    expect(bio, 1);
  });
}
