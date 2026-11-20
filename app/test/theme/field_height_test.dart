import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/widgets/picker_field.dart';

import '../helpers/fonts.dart';
import '../helpers/pump_app.dart';

void main() {
  setUpAll(loadInter);

  for (final brightness in Brightness.values) {
    testWidgets('campos de texto y selectores miden 52 de alto en '
        '${brightness.name}', (tester) async {
      await pumpThemed(
        tester,
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const TextField(decoration: InputDecoration(labelText: 'Regalo')),
              const SizedBox(height: 16),
              PickerField<String>(
                label: 'Para quién',
                value: 'a',
                options: const [PickerOption(value: 'a', label: 'Aritz')],
                onChanged: (_) {},
              ),
              const SizedBox(height: 16),
              const TextField(
                decoration: InputDecoration(
                  labelText: 'Previsto',
                  suffixText: '€',
                ),
              ),
            ],
          ),
        ),
        brightness: brightness,
      );
      final fields = find.byType(InputDecorator);
      expect(fields, findsNWidgets(3));
      for (final element in fields.evaluate()) {
        final h = tester.getSize(find.byWidget(element.widget)).height;
        expect(h, 52);
      }
    });
  }
}
