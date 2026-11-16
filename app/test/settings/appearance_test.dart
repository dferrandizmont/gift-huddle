import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/app.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/prefs/shared_preferences_provider.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/lock/application/lock_controller.dart';
import 'package:regalos/features/settings/application/appearance_provider.dart';
import 'package:regalos/features/settings/presentation/occasion_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/memory_stores.dart';
import '../helpers/pump_app.dart';

Future<ProviderContainer> _container([
  Map<String, Object> values = const {},
]) async {
  final prefs = await mockPrefs(values);
  final c = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(c.dispose);
  return c;
}

/// Monta la app con una familia vacía y sin PIN (sin familia la app empieza
/// por el primer uso) y abre Apariencia.
Future<void> mountAppearance(
  WidgetTester tester, {
  Map<String, Object> values = const {},
  Size size = const Size(390, 1200),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final phone = FakePhone(prefs: await mockPrefs(values));
  addTearDown(phone.dispose);
  await tester.runAsync(() async {
    await phone.container
        .read(familyControllerProvider.notifier)
        .createFamily(deviceName: 'M');
    await phone.container.read(lockControllerProvider.notifier).skipSetup();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: phone.container,
      child: const RegalosApp(),
    ),
  );
  await tester.pumpAndSettle();
  phone.container.read(routerProvider).go(AppRoutes.appearance);
  await tester.pumpAndSettle();
}

void main() {
  group('AppearanceNotifier', () {
    test('arranca con lavanda, tema del sistema y temas de ocasión', () async {
      final c = await _container();
      final s = c.read(appearanceProvider);
      expect(s.accent, AccentId.lavender);
      expect(s.themeMode, ThemeMode.system);
      expect(s.occasionThemes, isTrue);
    });

    test('guarda cada cambio y se recupera al reabrir', () async {
      final c = await _container();
      final n = c.read(appearanceProvider.notifier)
        ..setAccent(AccentId.peach)
        ..setThemeMode(ThemeMode.dark)
        ..setOccasionThemes(enabled: false);
      expect(n, isNotNull);

      final prefs = c.read(sharedPreferencesProvider);
      expect(prefs.getString('appearance.accent'), 'peach');
      expect(prefs.getString('appearance.themeMode'), 'dark');
      expect(prefs.getBool('appearance.occasionThemes'), false);

      final reopened = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(reopened.dispose);
      final s = reopened.read(appearanceProvider);
      expect(s.accent, AccentId.peach);
      expect(s.themeMode, ThemeMode.dark);
      expect(s.occasionThemes, isFalse);
    });

    test('ignora valores guardados que ya no existen', () async {
      final c = await _container({
        'appearance.accent': 'turquoise',
        'appearance.themeMode': 'sepia',
      });
      final s = c.read(appearanceProvider);
      expect(s.accent, AccentId.lavender);
      expect(s.themeMode, ThemeMode.system);
    });
  });

  group('pantalla Apariencia', () {
    Future<void> openAppearance(
      WidgetTester tester, [
      Map<String, Object> values = const {},
    ]) => mountAppearance(tester, values: values);

    testWidgets('elegir un color cambia el tema al momento y se guarda', (
      tester,
    ) async {
      await openAppearance(tester);
      final before = Theme.of(tester.element(find.byType(Scaffold).last))
          .extension<RegalosTokens>()!;
      expect(before.fill, AccentId.lavender.palette.pastel);

      await tester.tap(find.bySemanticsLabel('Sage'));
      await tester.pumpAndSettle();

      final after = Theme.of(tester.element(find.byType(Scaffold).last))
          .extension<RegalosTokens>()!;
      expect(after.fill, AccentId.sage.palette.pastel);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('appearance.accent'), 'sage');
    });

    testWidgets('el selector de tema pasa a oscuro', (tester) async {
      await openAppearance(tester);
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.dark);
      expect(
        Theme.of(tester.element(find.byType(Scaffold).last)).brightness,
        Brightness.dark,
      );
    });

    testWidgets('el interruptor de ocasión se apaga y se guarda', (
      tester,
    ) async {
      await openAppearance(tester);
      await tester.tap(
        find.bySemanticsLabel('Occasion themes (Christmas, birthdays)'),
      );
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('appearance.occasionThemes'), isFalse);
    });

    testWidgets(
      'muestra los seis nombres, la vista previa y marca el elegido',
      (tester) async {
        final handle = tester.ensureSemantics();
        await openAppearance(tester, {'appearance.accent': 'rose'});
        for (final n in [
          'Lavender',
          'Sage',
          'Peach',
          'Sky',
          'Rose',
          'Butter',
        ]) {
          expect(find.bySemanticsLabel(n), findsOneWidget);
        }
        expect(
          tester.getSemantics(find.bySemanticsLabel('Rose')),
          matchesSemantics(
            label: 'Rose',
            hasCheckedState: true,
            isChecked: true,
            isInMutuallyExclusiveGroup: true,
            hasTapAction: true,
          ),
        );
        expect(find.text('Preview'), findsOneWidget);
        expect(find.text('Block fire station'), findsOneWidget);
        handle.dispose();
      },
    );

    testWidgets('no desborda con el texto al 130 %', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await mountAppearance(tester, size: const Size(360, 780));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
    'OccasionScope aplica el tema de la ocasión solo si está activo',
    (tester) async {
      RegalosTokens? seen;
      Future<void> pump(Map<String, Object> values) async {
        await tester.pumpWidget(
          await scopeWith(
            MaterialApp(
              theme: buildTheme(AccentId.lavender.palette, Brightness.light),
              home: OccasionScope(
                occasion: OccasionTheme.christmas,
                child: Builder(
                  builder: (context) {
                    seen = RegalosTokens.of(context);
                    return const SizedBox();
                  },
                ),
              ),
            ),
            values,
          ),
        );
      }

      await pump({});
      expect(seen!.fill, OccasionTheme.christmas.palette.pastel);
      await pump({'appearance.occasionThemes': false});
      expect(seen!.fill, AccentId.lavender.palette.pastel);
    },
  );
}
