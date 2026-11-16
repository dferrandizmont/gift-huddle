import 'package:flutter/material.dart';

/// Neutros del diseño: fondo blanco puro en claro y gris neutro casi negro en
/// oscuro, al estilo Todoist (la guía del tema oscuro).
@immutable
class NeutralPalette {
  const NeutralPalette({
    required this.bg,
    required this.surface,
    required this.sheet,
    required this.sheetEdge,
    required this.scrim,
    required this.shadow,
    required this.danger,
    required this.dangerSoft,
    required this.dangerRow,
    required this.text,
    required this.textSecondary,
    required this.textOnSoft,
    required this.separator,
    required this.outline,
    required this.controlBorder,
    required this.track,
    required this.idea,
  });

  /// Fondo de pantalla.
  final Color bg;

  /// Fondo de tarjetas suaves (resumen de gasto, celdas de la rejilla).
  final Color surface;

  /// Hoja inferior, tarjeta que sube y diálogo: el escalón más alto. En claro
  /// es el fondo; en oscuro, lo elevado es más claro.
  final Color sheet;

  /// Filo de 1 px de arriba de la hoja (solo se ve en oscuro).
  final Color sheetEdge;

  /// Velo que oscurece la pantalla bajo una hoja.
  final Color scrim;

  /// Sombra bajo la hoja que sube y la celda que vuela.
  final Color shadow;

  /// Rojo de error y de acción destructiva (texto, trazo, barra pasada de
  /// presupuesto) y su fondo suave (botón de borrar, fila que se borra).
  final Color danger;
  final Color dangerSoft;

  /// Tinte de una fila (sobre el fondo) mientras se borra.
  final Color dangerRow;
  final Color text;
  final Color textSecondary;

  /// Texto secundario sobre el fondo suave del acento (cuenta atrás): algo más
  /// oscuro que [textSecondary] para llegar a AA con todos los pasteles.
  final Color textOnSoft;

  /// Separadores de lista y bordes finos de tarjeta.
  final Color separator;

  /// Borde fino y decorativo: separadores de tarjeta, etiquetas y trazo
  /// discontinuo de «Nada». No llega a 3:1; para controles, [controlBorder].
  final Color outline;

  /// Borde de chips, filtros, celdas «por comprar» y selector segmentado
  /// (3:1 como mínimo sobre el fondo y sobre la hoja).
  final Color controlBorder;

  /// Fondo de las barras de progreso.
  final Color track;

  /// Trazo discontinuo de «Idea» y de «sin asignar».
  final Color idea;

  static const light = NeutralPalette(
    bg: Color(0xFFFFFFFF),
    surface: Color(0xFFF5F5F8),
    sheet: Color(0xFFFFFFFF),
    sheetEdge: Color(0x00FFFFFF),
    scrim: Color(0x5217171C),
    shadow: Color(0xFF14143C),
    danger: Color(0xFFB3261E),
    dangerSoft: Color(0xFFF9DEDC),
    dangerRow: Color(0xFFFCEBE9),
    text: Color(0xFF17171C),
    textSecondary: Color(0xFF5F6068),
    textOnSoft: Color(0xFF3F3F46),
    separator: Color(0xFFE6E6EA),
    outline: Color(0xFFCFCFD6),
    // 3,3:1 sobre blanco y 3,1:1 sobre el gris suave de las tarjetas (WCAG
    // 1.4.11). Antes era #D5D5DB (1,4:1) y los controles que se reconocen solo
    // por el borde casi no se veían.
    controlBorder: Color(0xFF8B8C96),
    track: Color(0xFFE1E1E8),
    idea: Color(0xFF8B8C96),
  );

  // «Todoist neutro» (la guía del tema oscuro): grises sin tinte, con un
  // escalón claro entre fondo, tarjeta y hoja; texto casi blanco y acentos
  // saturados (los pone `AccentPalette`).
  static const dark = NeutralPalette(
    bg: Color(0xFF1C1C1C),
    surface: Color(0xFF2B2B2B),
    sheet: Color(0xFF363636),
    sheetEdge: Color(0xFF4C4C4C),
    scrim: Color(0x66000000),
    shadow: Color(0xFF000000),
    danger: Color(0xFFFF7A6E),
    dangerSoft: Color(0xFF55231F),
    dangerRow: Color(0xFF3A2321),
    text: Color(0xFFF5F5F5),
    textSecondary: Color(0xFFC4C4C4),
    textOnSoft: Color(0xFFD2D2D2),
    separator: Color(0xFF3B3B3B),
    outline: Color(0xFF565656),
    controlBorder: Color(0xFF8C8C8C),
    track: Color(0xFF444444),
    idea: Color(0xFF949494),
  );
}

/// Los seis colores de quien regala (el punto de 8 px junto al nombre).
/// Cada par es `(claro, oscuro)`; el orden es el de asignación automática.
/// Los oscuros son pasteles de la misma claridad (grafito cálido).
const List<(Color, Color)> giverColors = [
  (Color(0xFF0F766E), Color(0xFF1FE1D2)), // verde azulado
  (Color(0xFF4D7C0F), Color(0xFFA2D774)), // lima
  (Color(0xFF1D4ED8), Color(0xFFA8C4FE)), // azul
  (Color(0xFFBE185D), Color(0xFFFEA7BD)), // rosa
  (Color(0xFFB45309), Color(0xFFFFC16D)), // ámbar
  (Color(0xFF7E22CE), Color(0xFFD1B4FF)), // violeta
];

/// Texto sobre el chip de quien regala elegido, en el orden de [giverColors]:
/// `(claro, oscuro)`. En claro es blanco; en oscuro, la tinta oscura del mismo
/// tono que el relleno (el blanco no llegaba ni a 3:1).
const List<(Color, Color)> giverOnColors = [
  (Color(0xFFFFFFFF), Color(0xFF011B18)), // verde azulado
  (Color(0xFFFFFFFF), Color(0xFF0D1A02)), // lima
  (Color(0xFFFFFFFF), Color(0xFF0A152C)), // azul
  (Color(0xFFFFFFFF), Color(0xFF280B13)), // rosa
  (Color(0xFFFFFFFF), Color(0xFF211300)), // ámbar
  (Color(0xFFFFFFFF), Color(0xFF1B0F28)), // violeta
];
