import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Un texto de la interfaz que nunca parte una palabra a mitad.
///
/// Se pinta como un `Text` normal (con sus líneas, su alineación y su
/// escalado de texto). Solo si, con la letra grande, la palabra más larga no
/// cabe en el ancho que le dan, baja el tamaño de la fuente lo justo para que
/// quepa entera: nunca por debajo de [minFactor] del tamaño original ni del
/// tamaño que el texto tiene a letra normal. Si ni así cabe, pasa a una sola
/// línea con «…» (una palabra tampoco se parte). A letra normal no cambia
/// nada.
///
/// Es para etiquetas y títulos que escribe la app («Repartiment», «24 de
/// desembre») y para el nombre de una persona en una fila o tarjeta; los
/// nombres de quien regala en las columnas tienen su propia lógica.
class FitText extends StatelessWidget {
  /// Crea el texto.
  const FitText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.minFactor = 0.55,
  });

  /// El texto.
  final String text;

  /// El estilo, a tamaño base (sin escalar por el sistema).
  final TextStyle? style;

  /// Líneas máximas, o `null` para las que haga falta.
  final int? maxLines;

  /// Qué hacer si, aun así, no cabe en [maxLines].
  final TextOverflow? overflow;

  /// Alineación del texto.
  final TextAlign? textAlign;

  /// La parte del tamaño original por debajo de la cual no se baja.
  final double minFactor;

  /// El factor (entre [minFactor] y 1) por el que hay que multiplicar el
  /// tamaño para que la palabra más larga de [text] quepa en [maxWidth], y si
  /// con él cabe de verdad.
  @visibleForTesting
  static ({double factor, bool fits}) measure({
    required String text,
    required TextStyle effective,
    required TextScaler scaler,
    required TextDirection direction,
    required double maxWidth,
    Locale? locale,
    double minFactor = 0.55,
  }) {
    if (!maxWidth.isFinite || maxWidth <= 0) {
      return (factor: 1, fits: true);
    }
    final words = text.trim().split(RegExp(r'\s+'));
    final base = effective.fontSize ?? 14;
    double longest(double factor) {
      var widest = 0.0;
      for (final word in words) {
        final painter = TextPainter(
          text: TextSpan(
            text: word,
            style: effective.copyWith(fontSize: base * factor),
          ),
          textDirection: direction,
          textScaler: scaler,
          locale: locale,
          maxLines: 1,
        )..layout();
        widest = math.max(widest, painter.width);
        painter.dispose();
      }
      return widest;
    }

    // Suelo: el tamaño que quedaría pintado nunca baja del que tiene a letra
    // normal (1,0). A letra 1,0 o menor no se encoge nada; a 1,4, hasta 1/1,4.
    final scale = scaler.scale(base) / base;
    final floor = math.max(minFactor, scale > 0 ? 1 / scale : 1.0);
    if (floor >= 1) {
      return (factor: 1, fits: longest(1) <= maxWidth);
    }
    var factor = 1.0;
    // El escalado del sistema no tiene por qué ser lineal: se repite hasta
    // que cabe, siempre un poco por debajo de la proporción.
    for (var i = 0; i < 12 && factor > floor; i++) {
      final w = longest(factor);
      if (w <= maxWidth) {
        return (factor: factor, fits: true);
      }
      factor = math.max(floor, factor * math.min(0.98, maxWidth / w));
    }
    return (factor: factor, fits: longest(factor) <= maxWidth);
  }

  /// Solo el factor de [measure].
  @visibleForTesting
  static double factorFor({
    required String text,
    required TextStyle effective,
    required TextScaler scaler,
    required TextDirection direction,
    required double maxWidth,
    Locale? locale,
    double minFactor = 0.55,
  }) => measure(
    text: text,
    effective: effective,
    scaler: scaler,
    direction: direction,
    maxWidth: maxWidth,
    locale: locale,
    minFactor: minFactor,
  ).factor;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    var effective = DefaultTextStyle.of(context).style.merge(style);
    if (MediaQuery.boldTextOf(context)) {
      effective = effective.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    return LayoutBuilder(
      builder: (context, box) {
        final base = effective.fontSize ?? 14;
        // A letra normal no se toca nada.
        final fit = scaler == TextScaler.noScaling
            ? (factor: 1.0, fits: true)
            : measure(
                text: text,
                effective: effective,
                scaler: scaler,
                direction: direction,
                maxWidth: box.maxWidth,
                locale: locale,
                minFactor: minFactor,
              );
        return Text(
          text,
          // Si ni encogida cabe la palabra, una línea con «…»: no se parte.
          maxLines: fit.fits ? maxLines : 1,
          softWrap: fit.fits ? null : false,
          overflow: fit.fits ? overflow : TextOverflow.ellipsis,
          textAlign: textAlign,
          style: fit.factor < 1
              ? (style ?? const TextStyle()).copyWith(
                  fontSize: base * fit.factor,
                )
              : style,
        );
      },
    );
  }
}
