import 'package:flutter/widgets.dart';

/// La escala de interfaz de la web de escritorio
/// (la guía de diseño de escritorio): en un monitor grande
/// todo se ve pequeño, así que la app se agranda sola, **de forma continua**.
///
/// Con w el ancho real de la ventana en píxeles CSS:
///
/// - hasta [rampStart] (1920): 1,0;
/// - de [rampStart] a [midWidth] (2560): sube de 1,0 a [midScale] (1,2);
/// - de [midWidth] a [endWidth] (3440): sube de [midScale] a [endScale] (1,3);
/// - por encima: [endScale].
///
/// Se redondea a [quantum] (0,025). Siempre sube con el ancho y no depende de
/// la densidad de píxeles. Resultado (ancho lógico que ve el árbol): 1536 →
/// 1536, 1920 → 1920, 2560 → 2133, 3000 → 2400, 3440 → 2646.
///
/// Los cortes miran el ancho **de la ventana** (sin escalar); los puntos de
/// corte del layout (`RegalosBreakpoints`, `BoardMetrics`) miran después el
/// ancho ya escalado, que es el que ve el árbol.
abstract final class UiScaleSteps {
  /// Ancho de ventana desde el que la escala empieza a subir.
  static const double rampStart = 1920;

  /// Ancho de ventana en el que la escala llega a [midScale].
  static const double midWidth = 2560;

  /// Ancho de ventana en el que la escala llega a [endScale].
  static const double endWidth = 3440;

  /// Escala en [midWidth].
  static const double midScale = 1.2;

  /// Escala desde [endWidth].
  static const double endScale = 1.3;

  /// El paso al que se redondea.
  static const double quantum = 0.025;

  /// La escala para una ventana de [windowWidth] píxeles.
  static double forWindow(double windowWidth) {
    final double raw;
    if (windowWidth <= rampStart) {
      raw = 1;
    } else if (windowWidth <= midWidth) {
      raw =
          1 +
          (midScale - 1) * (windowWidth - rampStart) / (midWidth - rampStart);
    } else if (windowWidth <= endWidth) {
      raw =
          midScale +
          (endScale - midScale) *
              (windowWidth - midWidth) /
              (endWidth - midWidth);
    } else {
      raw = endScale;
    }
    return (raw / quantum).round() * quantum;
  }
}

/// Agranda todo lo de dentro (pantallas, hojas, diálogos y avisos, que viven
/// bajo el mismo `Navigator`) según [UiScaleSteps], solo en la web.
///
/// Se pone en la raíz (`MaterialApp.builder`). El hijo ve un `MediaQuery` con
/// el tamaño dividido por la escala (la ventana de 3000 con 1,25 es, para el
/// layout, una de 2400) y se pinta con `Transform.scale` desde la esquina
/// superior izquierda, así que cubre exactamente la ventana. El puntero se
/// deshace con la inversa de la matriz: un clic cae en el botón que se ve.
///
/// El árbol tiene siempre la misma forma, también con escala 1: cruzar un
/// corte al cambiar el tamaño de la ventana no desmonta nada.
class UiScale extends StatelessWidget {
  /// Crea la escala automática.
  const UiScale({super.key, required this.child});

  /// La app.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scale = UiScaleSteps.forWindow(media.size.width);
    final size = media.size / scale;
    return Transform.scale(
      scale: scale,
      alignment: Alignment.topLeft,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: size.width,
        maxWidth: size.width,
        minHeight: size.height,
        maxHeight: size.height,
        child: MediaQuery(
          data: media.copyWith(
            size: size,
            padding: media.padding / scale,
            viewPadding: media.viewPadding / scale,
            viewInsets: media.viewInsets / scale,
            systemGestureInsets: media.systemGestureInsets / scale,
          ),
          child: child,
        ),
      ),
    );
  }
}
