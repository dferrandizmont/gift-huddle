import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/widgets/picker_field.dart';

import '../helpers/pump_app.dart';

void main() {
  const options = [
    PickerOption(value: 'none', label: 'Sin ocasión'),
    PickerOption(value: 'a', label: 'Reyes', group: 'Fiestas'),
    PickerOption(value: 'b', label: 'Tió', group: 'Fiestas'),
    PickerOption(value: 'c', label: 'Cumpleaños de Aritz', group: 'Cumpleaños'),
  ];

  testWidgets('abre la hoja, agrupa, marca la elegida y aplica el valor', (
    tester,
  ) async {
    String value = 'a';
    await pumpThemed(
      tester,
      StatefulBuilder(
        builder: (context, setState) => PickerField<String>(
          label: 'Ocasión',
          value: value,
          options: options,
          onChanged: (v) => setState(() => value = v),
        ),
      ),
    );
    expect(find.text('Reyes'), findsOneWidget);

    await tester.tap(find.byType(PickerField<String>));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Fiestas'), findsOneWidget);
    expect(find.text('Cumpleaños'), findsOneWidget);

    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.bySemanticsLabel('Reyes').last),
      matchesSemantics(
        label: 'Reyes',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();

    await tester.tap(
      find.descendant(of: find.byType(BottomSheet), matching: find.text('Tió')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(value, 'b');
    expect(find.text('Tió'), findsOneWidget);
  });
}
