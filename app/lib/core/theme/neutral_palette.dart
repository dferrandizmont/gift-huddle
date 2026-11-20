import 'package:flutter/material.dart';

/// Neutros del diseño «A + Actual»: fondo blanco puro en claro y, en oscuro,
/// el casi negro cálido de «Pastel en velo» (D1).
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
    required this.dangerOnTint,
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
    required this.sidebar,
    required this.field,
    required this.popover,
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

  /// El aviso (texto, trazo y barra) sobre una superficie pastel de color
  /// (tarjeta de ocasión o de persona): en claro, el mismo `danger`; en oscuro,
  /// uno más claro que llega a 4,5:1 sobre el velo de las seis paletas.
  final Color dangerOnTint;

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

  /// Fondo de la barra lateral del tablero (un escalón por debajo del fondo
  /// en claro y por encima en oscuro).
  final Color sidebar;

  /// Fondo de los campos de texto y de los buscadores.
  final Color field;

  /// Fondo de un desplegable abierto (lo más alto que hay).
  final Color popover;

  static const light = NeutralPalette(
    bg: Color(0xFFFFFFFF),
    surface: Color(0xFFF5F5F8),
    sheet: Color(0xFFFFFFFF),
    sheetEdge: Color(0x00FFFFFF),
    scrim: Color(0x5217171C),
    shadow: Color(0xFF14143C),
    danger: Color(0xFFB3261E),
    dangerOnTint: Color(0xFFB3261E),
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
    sidebar: Color(0xFFFAFAFC),
    field: Color(0xFFFFFFFF),
    popover: Color(0xFFFFFFFF),
  );

  // «Pastel en velo» (D1): casi negro cálido, con un escalón claro entre
  // fondo, tarjeta y hoja; texto marfil y, encima, los pasteles velados (los
  // pone `AccentPalette`).
  static const dark = NeutralPalette(
    bg: Color(0xFF161514),
    surface: Color(0xFF1F1D1B),
    sheet: Color(0xFF252321),
    sheetEdge: Color(0xFF3A3633),
    scrim: Color(0x8C000000),
    shadow: Color(0xFF000000),
    danger: Color(0xFFFF7A6E),
    dangerOnTint: Color(0xFFFF8F84),
    dangerSoft: Color(0xFF55231F),
    dangerRow: Color(0xFF34201D),
    text: Color(0xFFF2EFEA),
    textSecondary: Color(0xFFBDB7AE),
    textOnSoft: Color(0xFFE2DED7),
    separator: Color(0xFF2D2A27),
    outline: Color(0xFF4A4541),
    // 4,9:1 sobre el fondo y 4,4:1 sobre la hoja: los controles que solo se
    // reconocen por el borde siguen pasando de 3:1.
    controlBorder: Color(0xFF87817A),
    track: Color(0xFF2D2A27),
    idea: Color(0xFF8C8781),
    sidebar: Color(0xFF1A1918),
    field: Color(0xFF1A1918),
    popover: Color(0xFF252321),
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
