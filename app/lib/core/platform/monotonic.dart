import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reloj monotónico: tiempo transcurrido desde un origen cualquiera que solo
/// avanza. Cambiar la hora del sistema no lo mueve.
typedef MonotonicNow = Duration Function();

final Stopwatch _sinceStart = Stopwatch()..start();

/// El reloj monotónico real (un `Stopwatch` desde el arranque del proceso).
///
/// Ojo: en Android y iOS no cuenta el tiempo con el móvil dormido, así que
/// nunca debe ser la única fuente: se combina con la hora del sistema
/// quedándose con el mayor de los dos tiempos.
Duration systemMonotonicNow() => _sinceStart.elapsed;

/// El reloj monotónico de la app. Las pruebas lo sustituyen.
final monotonicNowProvider = Provider<MonotonicNow>(
  (ref) => systemMonotonicNow,
);
