import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Instancia de `SharedPreferences` ya abierta. `main()` la sustituye con
/// `overrideWithValue`; las pruebas hacen lo mismo con valores simulados.
///
/// No se reintenta: que falte es un error de montaje, no algo pasajero, y un
/// reintento dejaría un temporizador pendiente en las pruebas que no lo
/// simulan.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider debe sustituirse en el ProviderScope.',
  ),
  retry: (_, _) => null,
);
