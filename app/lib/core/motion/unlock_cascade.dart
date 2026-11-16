import 'package:flutter/foundation.dart';

import 'stagger.dart';

/// El desbloqueo en cascada (§1+.4 de la guía de movimiento):
/// debajo del candado que se va, la app no aparece entera. La puerta de
/// bloqueo llama a [play] al desbloquear desde la pantalla de bloqueo (nunca al
/// volver sin bloqueo):
///
/// - la entrada escalonada de la pantalla que se ve se repite con
///   [baseDelay] de retardo base (cabecera, cuenta atrás y filas, a 24 ms), y
/// - la cuenta atrás rueda desde vacío a los [countdownDelay] ([epoch] avisa
///   a quien tenga cifras que rodar).
abstract final class UnlockCascade {
  /// Retardo base de la entrada de los bloques.
  static const Duration baseDelay = Duration(milliseconds: 140);

  /// Cuándo empieza a rodar la cuenta atrás.
  static const Duration countdownDelay = Duration(milliseconds: 200);

  /// Sube en cada cascada. Las cifras que ruedan lo escuchan.
  static final ValueNotifier<int> epoch = ValueNotifier<int>(0);

  /// Lanza la cascada sobre lo que se ve ahora.
  static void play() {
    StaggerScope.replayVisible(delay: baseDelay);
    epoch.value++;
  }
}
