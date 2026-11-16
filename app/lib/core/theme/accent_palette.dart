import 'package:flutter/material.dart';

/// Una pareja pastel/tinta del diseño «Tareas», con su variante oscura.
///
/// Valores tomados de la paleta del diseño (`renderVals`).
/// - [pastel]: relleno en claro (píldora de la barra, cuenta atrás, casilla).
/// - [tinta]: texto, trazo y números sobre fondo claro.
/// - [pastelD]: relleno en oscuro.
/// - [tintaD]: texto y trazo sobre fondo oscuro.
/// - [tintD]: fondo suave en oscuro (tarjeta de cuenta atrás, interruptor): el
///   tono del acento a claridad 0,33 y croma 0,045 (la guía del tema oscuro).
/// - [onFill]: texto e iconos sobre [pastelD].
/// - [swatchBorder]: borde de la muestra de color en claro.
@immutable
class AccentPalette {
  const AccentPalette({
    required this.pastel,
    required this.tinta,
    required this.pastelD,
    required this.tintaD,
    required this.tintD,
    required this.onFill,
    required this.swatchBorder,
  });

  final Color pastel;
  final Color tinta;
  final Color pastelD;
  final Color tintaD;
  final Color tintD;
  final Color onFill;
  final Color swatchBorder;
}

/// Los seis colores elegibles en Ajustes › Apariencia. Lavanda es el de serie.
///
/// [name] se guarda en `shared_preferences`: no renombrar los valores.
enum AccentId {
  lavender(
    AccentPalette(
      pastel: Color(0xFFD8D2F8),
      tinta: Color(0xFF4B3FB0),
      pastelD: Color(0xFF908FFE),
      tintaD: Color(0xFFB6BAFE),
      tintD: Color(0xFF2D2D58),
      onFill: Color(0xFF13122C),
      swatchBorder: Color(0xFFB9B0EE),
    ),
  ),
  sage(
    AccentPalette(
      pastel: Color(0xFFCFE5D4),
      tinta: Color(0xFF2F6B45),
      pastelD: Color(0xFF2CCD75),
      tintaD: Color(0xFF69DD92),
      tintD: Color(0xFF093D20),
      onFill: Color(0xFF011C0B),
      swatchBorder: Color(0xFFA9CDB2),
    ),
  ),
  peach(
    AccentPalette(
      pastel: Color(0xFFFFD8C4),
      tinta: Color(0xFFA4411A),
      pastelD: Color(0xFFFE885F),
      tintaD: Color(0xFFFEA88B),
      tintD: Color(0xFF522313),
      onFill: Color(0xFF280C04),
      swatchBorder: Color(0xFFF0B89C),
    ),
  ),
  sky(
    AccentPalette(
      pastel: Color(0xFFCBE4F7),
      tinta: Color(0xFF1F5F8F),
      pastelD: Color(0xFF5BB6FE),
      tintaD: Color(0xFF87C8FF),
      tintD: Color(0xFF063656),
      onFill: Color(0xFF00182B),
      swatchBorder: Color(0xFFA5CBEA),
    ),
  ),
  rose(
    AccentPalette(
      pastel: Color(0xFFF8D3E1),
      tinta: Color(0xFFA22C5F),
      pastelD: Color(0xFFFF7CAC),
      tintaD: Color(0xFFFFA0BF),
      tintD: Color(0xFF502032),
      onFill: Color(0xFF270B16),
      swatchBorder: Color(0xFFEDB0C9),
    ),
  ),
  butter(
    AccentPalette(
      pastel: Color(0xFFF8E9A6),
      tinta: Color(0xFF7A5C00),
      pastelD: Color(0xFFFBC10F),
      tintaD: Color(0xFFFCC94B),
      tintD: Color(0xFF413001),
      onFill: Color(0xFF1E1400),
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
