import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/app.dart';
import 'package:regalos/core/prefs/shared_preferences_provider.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/lock/application/lock_controller.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/features/settings/application/locale_provider.dart';

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

void main() {
  group('LocaleNotifier', () {
    test('arranca en del sistema (null) sin preferencia guardada', () async {
      final c = await _container();
      expect(c.read(localeProvider), isNull);
    });

    test('lee el valor guardado', () async {
      final c = await _container({'locale': 'ca'});
      expect(c.read(localeProvider), const Locale('ca'));
    });

    test('un código fuera de {es, ca, en} da null', () async {
      final c = await _container({'locale': 'fr'});
      expect(c.read(localeProvider), isNull);
      c.read(localeProvider.notifier).setLocale(const Locale('fr'));
      expect(c.read(localeProvider), isNull);
      expect(c.read(sharedPreferencesProvider).getString('locale'), isNull);
    });

    test('setter → prefs y contenedor nuevo leen lo mismo', () async {
      final c = await _container();
      c.read(localeProvider.notifier).setLocale(const Locale('ca'));
      final prefs = c.read(sharedPreferencesProvider);
      expect(prefs.getString('locale'), 'ca');
      expect(c.read(localeProvider), const Locale('ca'));

      final reopened = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(reopened.dispose);
      expect(reopened.read(localeProvider), const Locale('ca'));
    });

    test('null borra la preferencia', () async {
      final c = await _container({'locale': 'es'});
      c.read(localeProvider.notifier).setLocale(null);
      final prefs = c.read(sharedPreferencesProvider);
      expect(c.read(localeProvider), isNull);
      expect(prefs.getString('locale'), isNull);
    });

    test("'system' se trata como del sistema", () async {
      final c = await _container();
      // setLocale(null) ya cubre; comprobamos que un Locale no válido no persiste.
      c.read(localeProvider.notifier).setLocale(const Locale('system'));
      // Locale('system') no está en {es,ca,en}: se borra.
      expect(c.read(localeProvider), isNull);
    });
  });

  group('RegalosApp locale', () {
    testWidgets(
      'monta con locale ca, cambia a en y la ocasión de serie sigue el idioma',
      (tester) async {
        tester.view
          ..physicalSize = const Size(390, 844)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final prefs = await mockPrefs({'locale': 'ca'});
        final phone = FakePhone(prefs: prefs);
        addTearDown(phone.dispose);
        await tester.runAsync(() async {
          await phone.container
              .read(familyControllerProvider.notifier)
              .createFamily(deviceName: 'M');
          await phone.container
              .read(familyControllerProvider.notifier)
              .seedDefaultOccasions('ES-CT');
          await phone.container
              .read(lockControllerProvider.notifier)
              .skipSetup();
        });

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: phone.container,
            child: const RegalosApp(),
          ),
        );
        await tester.pumpAndSettle();

        // Abre la pestaña de Ocasiones para que se pinten todos los títulos.
        phone.container.read(routerProvider).go(AppRoutes.occasions);
        await tester.pumpAndSettle();

        // Texto en catalán: el nombre de serie de Navidad.
        expect(find.textContaining('Nadal'), findsWidgets);

        // Cambio a inglés: el título de la ocasión de serie sigue el idioma.
        phone.container
            .read(localeProvider.notifier)
            .setLocale(const Locale('en'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Christmas'), findsWidgets);
        expect(find.textContaining('Nadal'), findsNothing);
      },
    );
  });
}
