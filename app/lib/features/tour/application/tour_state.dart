import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/prefs/shared_preferences_provider.dart';

/// La preferencia que recuerda que la guía «Cómo funciona» ya se enseñó al
/// terminar la bienvenida. «Borrar todo» la quita con el resto.
const String kTourSeenKey = 'tour_seen';

/// Lo que se recuerda de la guía «Cómo funciona».
class TourSeen {
  /// Crea el registro sobre [_prefs].
  const TourSeen(this._prefs);

  final SharedPreferences _prefs;

  /// Si la guía ya se enseñó al terminar la bienvenida.
  bool get seen => _prefs.getBool(kTourSeenKey) ?? false;

  /// Anota que la guía ya se enseñó.
  Future<void> markSeen() => _prefs.setBool(kTourSeenKey, true);
}

/// Lo que se recuerda de la guía.
final Provider<TourSeen> tourSeenProvider = Provider<TourSeen>(
  (ref) => TourSeen(ref.watch(sharedPreferencesProvider)),
);

/// El aviso de que, al terminar la bienvenida, el router debe abrir la guía
/// en vez de Personas. Lo arma la bienvenida antes de guardar la familia (el
/// router decide en cuanto aparece) y lo apaga la guía al abrirse. Vive en
/// memoria: solo un móvil que acaba de pasar por la bienvenida lo arma, no uno
/// que se une a una familia con un QR.
class TourAfterWelcome {
  /// Si la guía debe abrirse al salir de la bienvenida.
  bool pending = false;
}

/// El aviso [TourAfterWelcome].
final Provider<TourAfterWelcome> tourAfterWelcomeProvider =
    Provider<TourAfterWelcome>((ref) => TourAfterWelcome());
