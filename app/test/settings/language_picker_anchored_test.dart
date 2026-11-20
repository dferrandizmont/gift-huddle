import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/widgets/anchored_picker.dart';
import 'package:regalos/features/settings/application/locale_provider.dart';
import 'package:regalos/features/settings/presentation/language_row.dart';

import '../helpers/pump_app.dart';

void main() {
  Future<void> pumpRow(WidgetTester tester, Size surface) async {
    final scope = await scopeWith(
      const SizedBox(width: 560, height: 64, child: LanguageRow()),
    );
    await pumpThemed(tester, scope, surfaceSize: surface);
  }

  testWidgets('en escritorio con ratón, Idioma es un desplegable anclado a la '
      'fila y elegir guarda el idioma', (tester) async {
    await pumpRow(tester, const Size(1536, 900));
    final row = tester.getRect(find.byType(LanguageRow));
    await tester.tap(find.byType(LanguageRow), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    final panel = tester.getRect(find.byKey(kAnchoredPickerKey));
    // Pegado al lado derecho de la fila, justo debajo y de 320 como mucho.
    expect(panel.right, closeTo(row.right, 0.5));
    expect(panel.width, lessThanOrEqualTo(320));
    expect(panel.top, closeTo(row.bottom + 4, 0.5));
    for (final name in ['Español', 'Català', 'English']) {
      expect(
        find.descendant(
          of: find.byKey(kAnchoredPickerKey),
          matching: find.text(name),
        ),
        findsOneWidget,
      );
    }

    await tester.tap(
      find.descendant(
        of: find.byKey(kAnchoredPickerKey),
        matching: find.text('Català'),
      ),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kAnchoredPickerKey), findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LanguageRow)),
    );
    expect(container.read(localeProvider), const Locale('ca'));
  });

  testWidgets('en el móvil sigue la hoja de idioma', (tester) async {
    await pumpRow(tester, const Size(390, 844));
    await tester.tap(find.byType(LanguageRow), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byKey(kAnchoredPickerKey), findsNothing);
  });
}
