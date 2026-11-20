import 'package:flutter/material.dart';

/// El fondo del oscuro «Pastel en velo» (D1): casi negro y cálido. Los
/// colores oscuros de cada pareja se sacan velando su pastel sobre él.
const Color kVeilBackground = Color(0xFF161514);

/// [pastel] al [amount] (0 a 1) sobre [kVeilBackground]: el «velo» del
/// oscuro D1 (`mix(pastel, fondo, amount)` de la maqueta).
Color veilOf(Color pastel, double amount) =>
    Color.lerp(kVeilBackground, pastel, amount)!;

/// Cuánto pastel lleva cada superficie del oscuro. La maqueta usa 0,18 / 0,16
/// / 0,30 / 0,14 con el pastel solo, y en pantalla se queda gris: aquí el
/// pastel se acerca a su tinta ([AccentPalette.veilSource]) y el velo sube,
/// para que el color de la pareja se vea y el texto pastel siga a 4,5:1.
const double kVeilFill = 0.30;
const double kVeilSoft = 0.28;
const double kVeilBorder = 0.50;
const double kVeilSelection = 0.22;

/// Cuánto de la tinta lleva el color que se vela ([AccentPalette.veilSource]).
const double kVeilTintaShare = 0.5;

/// Una pareja pastel/tinta del diseño, con su variante oscura «Pastel en velo».
///
/// - [pastel]: relleno en claro (botón, cuenta atrás, cuadrado de la inicial)
///   y, en oscuro, el texto, las cifras y los iconos.
/// - [tinta]: texto, trazo y números sobre fondo claro.
/// - [swatchBorder]: borde de la muestra de color y de la selección en claro.
///
/// En oscuro todo sale del pastel velado sobre el fondo ([veilSource] al
/// [kVeilFill] es el relleno [pastelD], al [kVeilSoft] las superficies de
/// color [tintD], al [kVeilBorder] su borde [borderD] y al [kVeilSelection] la
/// selección [selectionD]); encima, el pastel tal cual ([tintaD], [onFill]).
@immutable
class AccentPalette {
  const AccentPalette({
    required this.pastel,
    required this.tinta,
    required this.swatchBorder,
  });

  final Color pastel;
  final Color tinta;
  final Color swatchBorder;

  /// El color que se vela en oscuro: el pastel con la mitad de camino hacia su
  /// tinta, para que el velo tenga color y no solo luz.
  Color get veilSource => Color.lerp(pastel, tinta, kVeilTintaShare)!;

  /// Relleno en oscuro: «Añadir regalo», «Guardar», el cuadrado de la inicial.
  Color get pastelD => veilOf(veilSource, kVeilFill);

  /// Texto, cifras y trazo sobre el fondo oscuro: el pastel.
  Color get tintaD => pastel;

  /// Superficie de color en oscuro: la tarjeta de la cuenta atrás.
  Color get tintD => veilOf(veilSource, kVeilSoft);

  /// Borde de una superficie de color en oscuro y pista de su barra.
  Color get borderD => veilOf(veilSource, kVeilBorder);

  /// Fondo de lo elegido en oscuro (filtro, destino de la barra lateral).
  Color get selectionD => veilOf(veilSource, kVeilSelection);

  /// Fondo de lo elegido en claro: el pastel a medias con el blanco.
  Color get selection => Color.lerp(pastel, const Color(0xFFFFFFFF), 0.5)!;

  /// Texto e iconos sobre [pastelD]: el pastel.
  Color get onFill => pastel;

  /// Superficie de color (avatar, tarjeta de cuenta atrás, aviso): [tintD] en
  /// oscuro y el pastel en claro.
  Color surfaceOf(bool dark) => dark ? tintD : pastel;

  /// Relleno de color (cuadrado de la inicial): [pastelD] en oscuro y el
  /// pastel en claro.
  Color fillOf(bool dark) => dark ? pastelD : pastel;

  /// Texto o trazo del acento sobre su superficie: [tintaD] en oscuro y la
  /// tinta en claro.
  Color inkOf(bool dark) => dark ? tintaD : tinta;

  /// Borde de una superficie de color: [borderD] en oscuro y el de la muestra
  /// en claro.
  Color borderOf(bool dark) => dark ? borderD : swatchBorder;

  @override
  bool operator ==(Object other) =>
      other is AccentPalette &&
      other.pastel == pastel &&
      other.tinta == tinta &&
      other.swatchBorder == swatchBorder;

  @override
  int get hashCode => Object.hash(pastel, tinta, swatchBorder);
}

/// Los seis colores elegibles en Ajustes › Apariencia. Lavanda es el de serie.
///
/// [name] se guarda en `shared_preferences`: no renombrar los valores.
enum AccentId {
  lavender(
    AccentPalette(
      pastel: Color(0xFFD8D2F8),
      tinta: Color(0xFF4B3FB0),
      swatchBorder: Color(0xFFB9B0EE),
    ),
  ),
  sage(
    AccentPalette(
      pastel: Color(0xFFCFE5D4),
      tinta: Color(0xFF2F6B45),
      swatchBorder: Color(0xFFA9CDB2),
    ),
  ),
  peach(
    AccentPalette(
      pastel: Color(0xFFFFD8C4),
      tinta: Color(0xFFA4411A),
      swatchBorder: Color(0xFFF0B89C),
    ),
  ),
  sky(
    AccentPalette(
      pastel: Color(0xFFCBE4F7),
      tinta: Color(0xFF1F5F8F),
      swatchBorder: Color(0xFFA5CBEA),
    ),
  ),
  rose(
    AccentPalette(
      pastel: Color(0xFFF8D3E1),
      tinta: Color(0xFFA22C5F),
      swatchBorder: Color(0xFFEDB0C9),
    ),
  ),
  butter(
    AccentPalette(
      pastel: Color(0xFFF8E9A6),
      tinta: Color(0xFF7A5C00),
      swatchBorder: Color(0xFFE3CF7C),
    ),
  );

  const AccentId(this.palette);

  final AccentPalette palette;

  static const AccentId defaultAccent = AccentId.lavender;

  /// Lee el valor guardado; cualquier cosa desconocida cae en el de serie.
  static AccentId fromName(String? name) {
    for (final id in values) {
      if (id.name == name) return id;
    }
    return defaultAccent;
  }
}
