import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/prefs/shared_preferences_provider.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/features/family/data/storage_providers.dart';
import 'package:regalos/features/sync/data/sync_config.dart';
import 'package:regalos/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'memory_stores.dart';

/// Monta [child] con el tema «Tareas», los idiomas y Riverpod, para las
/// pruebas de widgets sueltos.
Future<void> pumpThemed(
  WidgetTester tester,
  Widget child, {
  AccentId accent = AccentId.lavender,
  Brightness brightness = Brightness.light,
  OccasionTheme? occasion,
  Locale locale = const Locale('es'),
  double textScale = 1,
  bool? disableAnimations,
  Size surfaceSize = const Size(390, 844),
}) async {
  tester.view
    ..physicalSize = surfaceSize
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildTheme(accent.palette, brightness, occasion: occasion),
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations:
              disableAnimations ?? MediaQuery.of(context).disableAnimations,
        ),
        child: c!,
      ),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

/// Crea un `SharedPreferences` simulado con [values].
Future<SharedPreferences> mockPrefs([Map<String, Object> values = const {}]) {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

/// `ProviderScope` con preferencias y almacenes simulados, para las pruebas
/// de la app.
Future<ProviderScope> scopeWith(
  Widget child, [
  Map<String, Object> values = const {},
]) async {
  final prefs = await mockPrefs(values);
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      // Sin plugins: la familia y el bloqueo usan almacenes en memoria.
      secretStoreProvider.overrideWithValue(MemorySecretStore()),
      fileStoreProvider.overrideWithValue(MemoryFileStore()),
      // Ninguna prueba habla con el servidor de verdad.
      syncHostProvider.overrideWithValue(''),
    ],
    child: child,
  );
}
