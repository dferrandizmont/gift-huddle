import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/prefs/shared_preferences_provider.dart';
import '../../../core/theme/accent_palette.dart';

/// Apariencia elegida en Ajustes › Apariencia.
@immutable
class AppearanceSettings {
  const AppearanceSettings({
    this.accent = AccentId.defaultAccent,
    this.themeMode = ThemeMode.system,
    this.occasionThemes = true,
  });

  final AccentId accent;
  final ThemeMode themeMode;

  /// Si las ocasiones (Navidad, cumpleaños) usan su propio acento.
  final bool occasionThemes;

  AppearanceSettings copyWith({
    AccentId? accent,
    ThemeMode? themeMode,
    bool? occasionThemes,
  }) => AppearanceSettings(
    accent: accent ?? this.accent,
    themeMode: themeMode ?? this.themeMode,
    occasionThemes: occasionThemes ?? this.occasionThemes,
  );

  @override
  bool operator ==(Object other) =>
      other is AppearanceSettings &&
      other.accent == accent &&
      other.themeMode == themeMode &&
      other.occasionThemes == occasionThemes;

  @override
  int get hashCode => Object.hash(accent, themeMode, occasionThemes);
}

/// Guarda y aplica la apariencia. Lee de `shared_preferences` al crearse (sin
/// parpadeo al arrancar) y escribe en cada cambio.
class AppearanceNotifier extends Notifier<AppearanceSettings> {
  static const accentKey = 'appearance.accent';
  static const themeModeKey = 'appearance.themeMode';
  static const occasionThemesKey = 'appearance.occasionThemes';

  late SharedPreferences _prefs;

  @override
  AppearanceSettings build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    return AppearanceSettings(
      accent: AccentId.fromName(_prefs.getString(accentKey)),
      themeMode: ThemeMode.values.firstWhere(
        (m) => m.name == _prefs.getString(themeModeKey),
        orElse: () => ThemeMode.system,
      ),
      occasionThemes: _prefs.getBool(occasionThemesKey) ?? true,
    );
  }

  void setAccent(AccentId accent) {
    state = state.copyWith(accent: accent);
    unawaited(_prefs.setString(accentKey, accent.name));
  }

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    unawaited(_prefs.setString(themeModeKey, mode.name));
  }

  void setOccasionThemes({required bool enabled}) {
    state = state.copyWith(occasionThemes: enabled);
    unawaited(_prefs.setBool(occasionThemesKey, enabled));
  }
}

final appearanceProvider =
    NotifierProvider<AppearanceNotifier, AppearanceSettings>(
      AppearanceNotifier.new,
    );
