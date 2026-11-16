import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/features/lock/presentation/lock_gate.dart';
import 'package:regalos/l10n/app_localizations.dart';

import '../helpers/memory_stores.dart';

void main() {
  late FakePhone phone;
  setUp(() => phone = FakePhone());
  tearDown(() => phone.dispose());

  // N2 (QA pre.29): el fotograma de carga va entre la pantalla de inicio y la
  // bienvenida; no lleva texto (salía «Gift Huddle» en negrita suelto) y es
  // solo el fondo del tema, sin subrayado.
  testWidgets('la cubierta de carga es solo el fondo, sin texto', (
    tester,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: phone.container,
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildTheme(AccentId.lavender.palette, Brightness.light),
          home: const LockGate(child: Text('LA APP')),
        ),
      ),
    );
    expect(find.text('Gift Huddle'), findsNothing);
    final cover = find.descendant(
      of: find.byType(LockGate),
      matching: find.byType(Material),
    );
    expect(cover, findsWidgets);
    expect(
      tester.widget<Material>(cover.last).color,
      buildTheme(
        AccentId.lavender.palette,
        Brightness.light,
      ).colorScheme.surface,
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  });
}
