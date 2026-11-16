import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prefs/shared_preferences_provider.dart';

/// Las dos vistas de Reparto: la rejilla (B) y la lista por ocasión (C).
enum RepartoView {
  /// Personas que reciben contra quienes regalan, en celdas.
  grid,

  /// Una pestaña por ocasión, con sus regalos y quién regala cada uno.
  occasion,
}

/// La vista de Reparto que se usó la última vez en este móvil; la rejilla si
/// nunca se eligió. Se guarda en `shared_preferences` bajo `reparto.view`.
class RepartoViewNotifier extends Notifier<RepartoView> {
  /// Clave en `shared_preferences`.
  static const prefsKey = 'reparto.view';

  @override
  RepartoView build() {
    final stored = ref.watch(sharedPreferencesProvider).getString(prefsKey);
    return stored == 'occasion' ? RepartoView.occasion : RepartoView.grid;
  }

  /// Cambia de vista y la recuerda.
  void set(RepartoView view) {
    if (view == state) {
      return;
    }
    state = view;
    unawaited(
      ref
          .read(sharedPreferencesProvider)
          .setString(
            prefsKey,
            view == RepartoView.occasion ? 'occasion' : 'grid',
          ),
    );
  }
}

/// La vista elegida de Reparto.
final repartoViewProvider = NotifierProvider<RepartoViewNotifier, RepartoView>(
  RepartoViewNotifier.new,
);
