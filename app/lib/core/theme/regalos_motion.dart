import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// Los muelles de la app (masa 1), los mismos de la maqueta de Reparto
/// (la guía de reparto, «Animaciones en Flutter»).
///
/// | Nombre   | Rigidez / amortiguación | Se asienta | Sobrepaso |
/// |----------|-------------------------|-----------|-----------|
/// | `snap`   | 520 / 38                | 375 ms    | 0,4 %     |
/// | `bounce` | 320 / 17                | 746 ms    | 17,6 %    |
/// | `soft`   | 200 / 26                | 525 ms    | 0 %       |
/// | `flight` | 180 / 25                | 571 ms    | 0 %       |
abstract final class RegalosSprings {
  /// Hoja, indicadores, cambio de forma, plegado.
  static const SpringDescription snap = SpringDescription(
    mass: 1,
    stiffness: 520,
    damping: 38,
  );

  /// Solo escalas pequeñas: rebote de celda, ancho del chip.
  static const SpringDescription bounce = SpringDescription(
    mass: 1,
    stiffness: 320,
    damping: 17,
  );

  /// Fundidos y filtros.
  static const SpringDescription soft = SpringDescription(
    mass: 1,
    stiffness: 200,
    damping: 26,
  );

  /// Regalos que viajan entre vistas.
  static const SpringDescription flight = SpringDescription(
    mass: 1,
    stiffness: 180,
    damping: 25,
  );

  static const Duration snapDuration = Duration(milliseconds: 375);
  static const Duration bounceDuration = Duration(milliseconds: 746);
  static const Duration softDuration = Duration(milliseconds: 525);
  static const Duration flightDuration = Duration(milliseconds: 571);
}

/// Una curva que sigue un muelle: evalúa `SpringSimulation.x(t × duración)`,
/// como la `linear()` de la maqueta. Para los widgets que piden `Duration` y
/// `Curve` (`AnimatedSize`, `AnimatedContainer`...); la duración debe ser la de
/// la tabla de [RegalosSprings].
class SpringCurve extends Curve {
  /// Crea la curva de [spring] que dura [duration].
  SpringCurve(SpringDescription spring, this.duration)
    : _simulation = SpringSimulation(spring, 0, 1, 0);

  /// Lo que tarda en asentarse.
  final Duration duration;
  final SpringSimulation _simulation;

  @override
  double transformInternal(double t) => _simulation.x(
    t * duration.inMicroseconds / Duration.microsecondsPerSecond,
  );
}

/// Las curvas listas de cada muelle.
abstract final class RegalosCurves {
  static final SpringCurve snap = SpringCurve(
    RegalosSprings.snap,
    RegalosSprings.snapDuration,
  );
  static final SpringCurve bounce = SpringCurve(
    RegalosSprings.bounce,
    RegalosSprings.bounceDuration,
  );
  static final SpringCurve soft = SpringCurve(
    RegalosSprings.soft,
    RegalosSprings.softDuration,
  );
  static final SpringCurve flight = SpringCurve(
    RegalosSprings.flight,
    RegalosSprings.flightDuration,
  );

  /// Las salidas no rebotan: la hoja que se cierra...
  static const Cubic sheetExit = Cubic(0.4, 0, 1, 1);

  /// ...y la fila que se pliega.
  static const Curve fold = Curves.fastOutSlowIn;

  static const Duration sheetExitDuration = Duration(milliseconds: 240);
  static const Duration foldDuration = Duration(milliseconds: 180);
}

/// Si hay que mover algo o solo fundir.
///
/// Con «Quitar animaciones» (Android) o «Reducir movimiento» (iOS),
/// `MediaQuery.disableAnimationsOf` es `true`: nada se mueve ni escala y todo
/// pasa a un fundido de 150 ms.
class RegalosMotion {
  const RegalosMotion._(this.reduce);

  /// Lee la preferencia del sistema.
  static RegalosMotion of(BuildContext context) =>
      RegalosMotion._(MediaQuery.disableAnimationsOf(context));

  /// El fundido que sustituye a todo movimiento.
  static const Duration fade = Duration(milliseconds: 150);

  /// Si el sistema pide reducir el movimiento.
  final bool reduce;

  /// [normal], o el fundido de 150 ms.
  Duration duration(Duration normal) => reduce ? fade : normal;

  /// [normal], o lineal para el fundido.
  Curve curve(Curve normal) => reduce ? Curves.linear : normal;

  /// Cómo sube y baja toda hoja inferior: la tarjeta con `snap` y la salida
  /// sin rebote. Con «Reducir movimiento», sin animar la ruta (el contenido
  /// se funde por su lado, ver `showRegalosSheet`).
  AnimationStyle get sheetStyle => reduce
      ? AnimationStyle.noAnimation
      : AnimationStyle(
          duration: RegalosSprings.snapDuration,
          curve: RegalosCurves.snap,
          reverseDuration: RegalosCurves.sheetExitDuration,
          reverseCurve: RegalosCurves.sheetExit,
        );
}

/// El temblor del PIN erróneo (la guía de movimiento, §0).
///
/// Rigidez 900 y amortiguación 14 (ζ 0,23): un vaivén de 4,6 Hz que pierde
/// el 53 % en cada ciclo. Se lanza desde 0 con velocidad
/// ([initialVelocity]); el primer pico es de unos 10 px y se apaga en unos
/// 560 ms ([duration]).
abstract final class RegalosShake {
  static const SpringDescription spring = SpringDescription(
    mass: 1,
    stiffness: 900,
    damping: 14,
  );

  /// Lo que tarda en apagarse.
  static const Duration duration = Duration(milliseconds: 560);

  /// Velocidad de salida, en px/s.
  static const double initialVelocity = 420;

  /// Cuándo se da por apagado: por debajo de 0,3 px y 10 px/s.
  static const Tolerance tolerance = Tolerance(distance: 0.3, velocity: 10);

  /// La simulación del temblor: la posición en px a lo largo del tiempo.
  ///
  /// Al apagarse vale exactamente 0 (`snapToEnd`): el hijo no se queda
  /// desplazado una fracción de píxel.
  static SpringSimulation simulation() => SpringSimulation(
    spring,
    0,
    0,
    initialVelocity,
    tolerance: tolerance,
    snapToEnd: true,
  );
}
