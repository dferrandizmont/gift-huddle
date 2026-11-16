import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/prefs/shared_preferences_provider.dart';

/// Preferencia de idioma de la app: `null` significa "del sistema".
///
/// Valores persistidos: `null` (por defecto, "del sistema"), `'es'`, `'ca'`,
/// `'en'`. Se guarda en `shared_preferences` bajo la clave `'locale'`.
const _validLocaleCodes = <String>{'es', 'ca', 'en'};

class LocaleNotifier extends Notifier<Locale?> {
  /// Clave en `shared_preferences`.
  static const localeKey = 'locale';

  late SharedPreferences _prefs;

  Locale? _parse(String? code) {
    if (code == null || code.isEmpty || code == 'system') return null;
    if (!_validLocaleCodes.contains(code)) return null;
    return Locale(code);
  }

  @override
  Locale? build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    return _parse(_prefs.getString(localeKey));
  }

  /// Cambia el idioma. `null` (o un código no soportado) vuelve al del
  /// sistema y borra la preferencia.
  void setLocale(Locale? locale) {
    final code = locale?.languageCode;
    final valid = code != null && _validLocaleCodes.contains(code)
        ? code
        : null;
    state = valid == null ? null : Locale(valid);
    if (valid == null) {
      unawaited(_prefs.remove(localeKey));
    } else {
      unawaited(_prefs.setString(localeKey, valid));
    }
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale?>(
  LocaleNotifier.new,
);
