import 'package:flutter/widgets.dart';

/// Radios del rediseño v3 (dirección A «Tareas ajustado»). Son constantes:
/// no dependen del brillo ni del acento. Se leen con
/// `RegalosTokens.of(context).shape` o directamente como `RegalosShape.x`.
abstract final class RegalosShape {
  static const double chipRadius = 8;
  static const double cardRadius = 8;
  static const double buttonRadius = 8;
  static const double fieldRadius = 8;

  /// Piezas diminutas de una ilustración (una barra de carga, un paquete, la
  /// barra de direcciones de un navegador dibujado): 4.
  static const double tinyRadius = 4;

  /// Teclas del PIN: 8, como los botones.
  static const double keyRadius = 8;

  /// El «+» y el recuadro de la navegación: 8, como todo control (nada pasa
  /// de 8).
  static const double fabRadius = 8;
  static const double navIndicatorRadius = 8;

  /// Chips del selector de Reparto (activo sólido).
  static const double repartoChipRadius = 6;

  /// Hojas (las esquinas de arriba) y diálogos: 8 también. Son superficies,
  /// pero nada pasa de 8.
  static const double sheetRadius = 8;
  static const double dialogRadius = 8;

  /// Las hojas de Ajustes y Compartir (`showRegalosSheet(flat: true)`): 8,
  /// igual que [sheetRadius] desde que todas las hojas van a 8.
  static const double flatSheetRadius = 8;

  static const BorderRadius chip = BorderRadius.all(
    Radius.circular(chipRadius),
  );
  static const BorderRadius card = BorderRadius.all(
    Radius.circular(cardRadius),
  );
  static const BorderRadius button = BorderRadius.all(
    Radius.circular(buttonRadius),
  );
  static const BorderRadius field = BorderRadius.all(
    Radius.circular(fieldRadius),
  );
  static const BorderRadius tiny = BorderRadius.all(
    Radius.circular(tinyRadius),
  );
  static const BorderRadius key = BorderRadius.all(Radius.circular(keyRadius));
  static const BorderRadius fab = BorderRadius.all(Radius.circular(fabRadius));
  static const BorderRadius navIndicator = BorderRadius.all(
    Radius.circular(navIndicatorRadius),
  );
}

/// Medidas del rediseño v3.
abstract final class RegalosSizes {
  /// Tarjeta de persona: alto mínimo y avatar.
  static const double personCardHeight = 92;
  static const double personAvatar = 52;

  /// Carrusel de cuenta atrás: alto mínimo (el real lo da
  /// `CountdownCard.heightFor`), fracción del visor, hueco y margen izquierdo.
  static const double carouselHeight = 156;

  /// Fracción del visor (que empieza a 11 del borde): da una tarjeta de 332
  /// en un móvil de 390, como la maqueta.
  static const double carouselViewportFraction = 0.9;
  static const double carouselGap = 10;
  static const double carouselEdge = 16;
  static const double countdownNumber = 60;

  /// Puntos de paginación: 6 de alto, el activo 18 de ancho.
  static const double dot = 6;
  static const double dotActiveWidth = 18;

  /// Barra inferior B: 68 de alto, icono de 22 con trazo 1,75 y una línea
  /// de 2 px sobre el destino activo.
  static const double navBarHeight = 68;
  static const double navIconSize = 22;
  static const double navIconStroke = 1.75;
  static const double navActiveLine = 2;

  /// Barra segmentada de la tarjeta de persona (un segmento por regalo).
  static const double segmentHeight = 5;
  static const double segmentGap = 3;
}
