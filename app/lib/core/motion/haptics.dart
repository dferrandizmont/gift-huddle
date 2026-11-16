import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../prefs/shared_preferences_provider.dart';
import '../theme/regalos_motion.dart';

/// Los niveles de vibración, con nombres de significado como los de iOS
/// (la guía de movimiento, «Vibraciones»). Nadie pide un
/// `HapticFeedback` concreto: pide un nivel y el servicio decide cómo suena.
enum HapticLevel {
  /// Un clic seco al elegir algo (celda, pastilla, destino, interruptor).
  selection,

  /// Un toque ligero: algo ha cambiado de estado.
  light,

  /// Un toque medio: algo importante ha pasado (borrar, conectar).
  medium,

  /// Algo ha salido bien: dos toques que suben (persona completa, móvil
  /// conectado).
  success,

  /// Aviso fuerte: dos toques medios seguidos (borrar todo).
  warning,

  /// Algo ha salido mal: tres toques que bajan (PIN equivocado).
  error,
}

/// Lo único que toca el sistema. Se sustituye en las pruebas para ver qué se
/// ha pedido y cuándo, sin plugins.
abstract class HapticDriver {
  /// Crea el motor.
  const HapticDriver();

  /// `HapticFeedback.selectionClick`.
  Future<void> selectionClick();

  /// `HapticFeedback.lightImpact`.
  Future<void> lightImpact();

  /// `HapticFeedback.mediumImpact`.
  Future<void> mediumImpact();

  /// `HapticFeedback.heavyImpact`.
  Future<void> heavyImpact();
}

/// El motor de verdad: `HapticFeedback` de Flutter, sin plugins nuevos.
class SystemHapticDriver extends HapticDriver {
  /// Crea el motor del sistema.
  const SystemHapticDriver();

  @override
  Future<void> selectionClick() => HapticFeedback.selectionClick();

  @override
  Future<void> lightImpact() => HapticFeedback.lightImpact();

  @override
  Future<void> mediumImpact() => HapticFeedback.mediumImpact();

  @override
  Future<void> heavyImpact() => HapticFeedback.heavyImpact();
}

/// Cuándo se asienta el muelle `snap` a efectos de la mano: un 95 % del
/// recorrido. La vibración de lo que viaja con ese muelle (la casilla, el
/// recuadro de la barra) llega en ese instante y no con el toque.
const Duration kHapticSpringArrival = Duration(milliseconds: 160);

/// Cuándo aparece el sello de «persona completa» tras la acción (250 ms): la
/// vibración de logro llega con él.
const Duration kHapticSeal = Duration(milliseconds: 250);

/// Lo mínimo que hay que arrastrar una hoja para que, al soltarla y volver a
/// su sitio, vibre. Un roce no cuenta.
const double kHapticMinDrag = 40;

/// Entre dos vibraciones sueltas tiene que haber al menos esto.
const Duration kHapticMinGap = Duration(milliseconds: 80);

/// El servicio de vibraciones.
///
/// - **Niveles.** [play] y los atajos ([selection], [light], [medium],
///   [success], [warning], [error]).
/// - **Antirrebote global.** Nunca dos vibraciones en menos de
///   [kHapticMinGap]: la que llega mientras suena otra (o su patrón) se
///   descarta. Una vibración con [play]`(after:)` se mide cuando le toca
///   sonar, no cuando se pide.
/// - **Ajuste.** Si `enabled` devuelve `false` no suena nada. «Reducir
///   movimiento» del sistema no lo apaga: la vibración no es movimiento.
/// - **Pruebas.** Las pantallas lo piden por [hapticsProvider]; una prueba lo
///   sustituye por una subclase que apunte los niveles, o crea uno con un
///   [HapticDriver] propio.
class Haptics {
  /// Crea el servicio. [enabled] se lee cada vez que algo va a sonar.
  Haptics({
    required this._enabled,
    this._driver = const SystemHapticDriver(),
    Duration Function()? now,
  }) : _now = now ?? _frameClock,
       _bare = false;

  /// El servicio sencillo de quien no tiene `ProviderScope` (la prueba de un
  /// widget suelto): siempre encendido, sin esperas ni patrones (cada nivel es
  /// un solo toque, al momento) y sin temporizadores que dejar pendientes.
  Haptics.bare()
    : _enabled = (() => true),
      _driver = const SystemHapticDriver(),
      _now = _frameClock,
      _bare = true;

  final bool Function() _enabled;
  final HapticDriver _driver;
  final Duration Function() _now;
  final bool _bare;

  /// Hasta cuándo no puede sonar otra (fin de la última más el hueco).
  Duration? _blockedUntil;

  /// La hora del servicio: la del último fotograma, que en una prueba de
  /// widgets avanza con `pump` y no con el reloj de la máquina.
  static Duration _frameClock() =>
      SchedulerBinding.instance.currentSystemFrameTimeStamp;

  /// Lo que espera su turno. No son `Timer`: se despachan en los fotogramas,
  /// así que una prueba de widgets no se queda con temporizadores pendientes y
  /// una pantalla sin fotogramas (la app en segundo plano) no vibra tarde.
  final List<_Due> _queue = <_Due>[];
  bool _armed = false;

  /// El desfase de cada toque de un patrón respecto al primero.
  @visibleForTesting
  static const Map<HapticLevel, List<Duration>>
  patternOffsets = <HapticLevel, List<Duration>>{
    HapticLevel.selection: <Duration>[Duration.zero],
    HapticLevel.light: <Duration>[Duration.zero],
    HapticLevel.medium: <Duration>[Duration.zero],
    HapticLevel.success: <Duration>[Duration.zero, Duration(milliseconds: 90)],
    HapticLevel.warning: <Duration>[Duration.zero, Duration(milliseconds: 120)],
    HapticLevel.error: <Duration>[
      Duration.zero,
      Duration(milliseconds: 90),
      Duration(milliseconds: 180),
    ],
  };

  Future<void> Function() _tap(HapticLevel level, int index) {
    switch (level) {
      case HapticLevel.selection:
        return _driver.selectionClick;
      case HapticLevel.light:
        return _driver.lightImpact;
      case HapticLevel.medium:
        return _driver.mediumImpact;
      case HapticLevel.success:
        // Ligero y luego medio: sube.
        return index == 0 ? _driver.lightImpact : _driver.mediumImpact;
      case HapticLevel.warning:
        return _driver.mediumImpact;
      case HapticLevel.error:
        // Fuerte, fuerte y un eco ligero: baja.
        return index < 2 ? _driver.heavyImpact : _driver.lightImpact;
    }
  }

  /// Pide una vibración de [level]. Con [after] suena pasado ese tiempo (para
  /// que coincida con el instante en que algo llega). Con [supersede] anula
  /// antes las que aún esperan su turno: es el momento que manda.
  void play(
    HapticLevel level, {
    Duration after = Duration.zero,
    bool supersede = false,
  }) {
    if (!_enabled()) {
      return;
    }
    if (supersede) {
      cancelPending();
    }
    if (after <= Duration.zero || _bare) {
      _fire(level);
      return;
    }
    _later(after, () => _fire(level), cancelable: true);
  }

  /// [HapticLevel.selection].
  void selection({Duration after = Duration.zero}) =>
      play(HapticLevel.selection, after: after);

  /// [HapticLevel.light].
  void light({Duration after = Duration.zero}) =>
      play(HapticLevel.light, after: after);

  /// [HapticLevel.medium].
  void medium({Duration after = Duration.zero}) =>
      play(HapticLevel.medium, after: after);

  /// [HapticLevel.success].
  void success({Duration after = Duration.zero}) =>
      play(HapticLevel.success, after: after);

  /// [HapticLevel.warning].
  void warning({Duration after = Duration.zero}) =>
      play(HapticLevel.warning, after: after);

  /// [HapticLevel.error].
  void error({Duration after = Duration.zero}) =>
      play(HapticLevel.error, after: after);

  /// Descarta las vibraciones pedidas con espera que aún no han sonado (los
  /// toques que faltan de un patrón ya empezado siguen).
  void cancelPending() => _queue.removeWhere((d) => d.cancelable);

  /// Libera todo lo que espera.
  void dispose() => _queue.clear();

  void _later(Duration after, VoidCallback run, {required bool cancelable}) {
    _queue.add(_Due(_now() + after, run, cancelable));
    _arm();
  }

  void _arm() {
    if (_armed || _queue.isEmpty) {
      return;
    }
    _armed = true;
    final binding = SchedulerBinding.instance;
    binding.addPostFrameCallback((_) {
      _armed = false;
      _drain();
    });
    binding.scheduleFrame();
  }

  void _drain() {
    final now = _now();
    final due = _queue.where((d) => d.at <= now).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    _queue.removeWhere(due.contains);
    for (final d in due) {
      d.run();
    }
    _arm();
  }

  void _fire(HapticLevel level) {
    // Una vez pasado el ajuste y el antirrebote, el patrón entero suena.
    if (!_enabled()) {
      return;
    }
    final now = _now();
    final blocked = _blockedUntil;
    if (blocked != null && now < blocked) {
      return;
    }
    final offsets = _bare
        ? const <Duration>[Duration.zero]
        : patternOffsets[level]!;
    _blockedUntil = now + offsets.last + kHapticMinGap;
    for (var i = 0; i < offsets.length; i++) {
      final tap = _tap(level, i);
      if (offsets[i] == Duration.zero) {
        _run(tap);
      } else {
        _later(offsets[i], () => _run(tap), cancelable: false);
      }
    }
  }

  void _run(Future<void> Function() tap) {
    // Sin motor (escritorio, web, pruebas) no pasa nada.
    unawaited(tap().catchError((Object _) {}));
  }
}

class _Due {
  _Due(this.at, this.run, this.cancelable);

  final Duration at;
  final VoidCallback run;
  final bool cancelable;
}

/// Dónde se guarda el ajuste «Vibraciones» (Ajustes › Apariencia).
const String kHapticsEnabledKey = 'appearance.haptics';

/// El ajuste «Vibraciones»: encendido de serie y guardado en preferencias.
class HapticsEnabledNotifier extends Notifier<bool> {
  late SharedPreferences _prefs;

  @override
  bool build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    return _prefs.getBool(kHapticsEnabledKey) ?? true;
  }

  /// Enciende o apaga las vibraciones.
  void set({required bool enabled}) {
    state = enabled;
    unawaited(_prefs.setBool(kHapticsEnabledKey, enabled));
  }
}

/// Si las vibraciones están encendidas.
final hapticsEnabledProvider = NotifierProvider<HapticsEnabledNotifier, bool>(
  HapticsEnabledNotifier.new,
  // Sin preferencias montadas (una prueba que no las simula) falla y el
  // servicio lo toma por encendido: no se reintenta.
  retry: (_, _) => null,
);

/// El servicio de vibraciones de la app.
final hapticsProvider = Provider<Haptics>((ref) {
  final haptics = Haptics(
    enabled: () {
      try {
        return ref.read(hapticsEnabledProvider);
      } on Object {
        // Sin preferencias montadas (una prueba que no las simula): suena.
        return true;
      }
    },
  );
  ref.onDispose(haptics.dispose);
  return haptics;
});

/// El servicio de vibraciones desde cualquier widget.
extension HapticsContext on BuildContext {
  /// El [Haptics] de la app; uno sencillo ([Haptics.bare]) si no hay
  /// `ProviderScope`.
  Haptics get haptics {
    try {
      return ProviderScope.containerOf(
        this,
        listen: false,
      ).read(hapticsProvider);
    } on Object {
      return Haptics.bare();
    }
  }

  /// Cuándo vibra lo que viaja con el muelle `snap`: al asentarse, o al
  /// momento si el sistema pide reducir el movimiento.
  Duration get hapticArrival =>
      RegalosMotion.of(this).reduce ? Duration.zero : kHapticSpringArrival;

  /// Cuándo vibra el logro de completar a una persona: con el sello, o al
  /// momento si el sistema pide reducir el movimiento.
  Duration get hapticSeal =>
      RegalosMotion.of(this).reduce ? Duration.zero : kHapticSeal;
}
