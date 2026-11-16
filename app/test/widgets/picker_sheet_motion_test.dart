import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/widgets/picker_field.dart';

import '../helpers/pump_app.dart';
import 'pin_shake_test.dart' show recordHaptics;

void main() {
  const options = [
    PickerOption(value: 'a', label: 'Reyes'),
    PickerOption(value: 'b', label: 'Tió'),
    PickerOption(value: 'c', label: 'Santa'),
  ];

  Future<List<String>> open(
    WidgetTester tester,
    List<String> picked, {
    bool reduce = false,
  }) async {
    final haptics = recordHaptics(tester);
    await pumpThemed(
      tester,
      PickerField<String>(
        label: 'Ocasión',
        value: 'a',
        options: options,
        onChanged: picked.add,
      ),
      disableAnimations: reduce,
    );
    await tester.tap(find.byType(PickerField<String>));
    await tester.pumpAndSettle();
    return haptics;
  }

  Finder inSheet(String text) =>
      find.descendant(of: find.byType(BottomSheet), matching: find.text(text));

  for (final reduce in [false, true]) {
    testWidgets('elegir una opción ${reduce ? 'con «Reducir movimiento» ' : ''}'
        'espera 120 ms para que se vea y luego cierra y entrega el valor', (
      tester,
    ) async {
      final picked = <String>[];
      final haptics = await open(tester, picked, reduce: reduce);

      await tester.tap(inSheet('Tió'));
      await tester.pump(const Duration(milliseconds: 60));
      // Se ve elegida, con su háptica, y la hoja sigue ahí.
      expect(haptics, ['HapticFeedbackType.selectionClick']);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(picked, isEmpty);

      await tester.pump(const Duration(milliseconds: 70));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(picked, ['b']);
    });
  }

  testWidgets('un segundo toque en la pausa cierra al momento con ese valor', (
    tester,
  ) async {
    final picked = <String>[];
    await open(tester, picked);
    await tester.tap(inSheet('Tió'));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(inSheet('Santa'));
    await tester.pumpAndSettle();
    expect(picked, ['c']);
  });

  /// La opacidad con la que entra la fila de [text] (el `StaggerItem`).
  double entering(WidgetTester tester, String text) => tester
      .widget<FadeTransition>(
        find
            .ancestor(of: inSheet(text), matching: find.byType(FadeTransition))
            .first,
      )
      .opacity
      .value;

  Future<void> tapField(WidgetTester tester, {required bool reduce}) async {
    await pumpThemed(
      tester,
      PickerField<String>(
        label: 'Ocasión',
        value: 'a',
        options: options,
        onChanged: (_) {},
      ),
      disableAnimations: reduce,
    );
    await tester.tap(find.byType(PickerField<String>));
    // El primer fotograma monta la hoja y el siguiente arranca la entrada.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
  }

  testWidgets('las opciones entran escalonadas, de arriba abajo', (
    tester,
  ) async {
    await tapField(tester, reduce: false);
    await tester.pump(const Duration(milliseconds: 130));
    final first = entering(tester, 'Reyes');
    final last = entering(tester, 'Santa');
    expect(first, greaterThan(0));
    expect(last, lessThan(first));
    await tester.pumpAndSettle();
    expect(entering(tester, 'Santa'), 1);
  });

  testWidgets('con «Reducir movimiento» entran todas a la vez, solo con '
      'fundido y sin desplazarse', (tester) async {
    await tapField(tester, reduce: true);
    await tester.pump(const Duration(milliseconds: 40));
    final first = entering(tester, 'Reyes');
    expect(first, inExclusiveRange(0, 1));
    expect(entering(tester, 'Santa'), first);
    // Ni la hoja ni las opciones llevan un `Transform` desplazado.
    for (final t in tester.widgetList<Transform>(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Transform),
      ),
    )) {
      expect(t.transform.getTranslation().length, 0);
      expect(t.transform.storage[0], 1);
    }
    await tester.pumpAndSettle();
  });
}
