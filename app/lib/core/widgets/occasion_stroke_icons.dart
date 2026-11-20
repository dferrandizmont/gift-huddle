// Iconos de ocasión dibujados para Gift Huddle con las reglas de Tabler
// (rejilla de 24, trazo 2, extremos y uniones redondos, sin rellenos, margen
// de 2). Solo lo que no existe en ninguna biblioteca: el resto de tipos usa
// iconos reales de Tabler (`tabler_icons.dart`).
//
// Los datos son los de los SVG de referencia (obra del propio proyecto, bajo
// su misma licencia); lo comprueba `test/widgets/occasion_icons_test.dart`.
import 'stroke_icon.dart';
import 'svg_path.dart';

/// Tió: tronco tumbado con cara (ojos y sonrisa), dos patas delanteras y barretina
/// (`assets/icons/tabler-style/tio.svg`).
///
/// Alternativa de Tabler por si hiciera falta (`wood`, un tronco vertical, sin
/// cara ni barretina):
/// `M12 5.5m-6 0a6 2.5 0 1 0 12 0a6 2.5 0 1 0 -12 0`,
/// `M18 5.5v4.626a1.415 1.415 0 0 1 1.683 2.18l-.097 .108l-1.586 1.586v4c0 1.61 -2.54 2.925 -5.725 3l-.275 0c-3.314 0 -6 -1.343 -6 -3v-2l-1.586 -1.586a1.414 1.414 0 0 1 1.586 -2.287v-6.627`,
/// `M10 12.5v1.5`, `M14 16v1`.
const _dataTio = <String>[
  'M5 9.5h5.5v-2a4 4 0 0 0 -4 -4h-.5a3 3 0 0 0 -3 3v.5h3z',
  'M10.5 9.5h6a4.5 4.5 0 0 1 0 9H7.5',
  'M5 9.5c-1.25 1 -2 2.6 -2 4.5a4.5 4.5 0 0 0 9 0c0 -1.9 -.5 -3.5 -1.5 -4.5',
  'M5.75 12.75h.01m3.49 0h.01',
  'M6.25 15.5a2 2 0 0 0 2.5 0',
  'M6.75 18.5l-1 2.5m7 -2.5l-1 2.5',
];
final StrokeIconBuilder occasionIconTio = svgIcon(_dataTio);

/// Año Nuevo chino: el farolillo (`cny-a`).
const _dataChineseNewYear = <String>[
  'M12 2v2',
  'M9 6v-2h6v2',
  'M8 6h8c2.4 1.5 3.5 3.6 3.5 6s-1.1 4.5 -3.5 6h-8c-2.4 -1.5 -3.5 -3.6 -3.5 -6s1.1 -4.5 3.5 -6',
  'M9.3 6.3c-1.4 1.5 -2.1 3.4 -2.1 5.7s.7 4.2 2.1 5.7',
  'M14.7 6.3c1.4 1.5 2.1 3.4 2.1 5.7s-.7 4.2 -2.1 5.7',
  'M9 18v2h6v-2',
  'M12 20v2',
];
final StrokeIconBuilder occasionIconChineseNewYear = svgIcon(
  _dataChineseNewYear,
);

/// Boda: dos alianzas entrelazadas (`wedding-b`).
const _dataWedding = <String>[
  'M10.38 18.75A5.5 5.5 0 1 1 13.27 16.64',
  'M13.62 8.25A5.5 5.5 0 1 1 10.73 10.36',
];
final StrokeIconBuilder occasionIconWedding = svgIcon(_dataWedding);

/// Los datos de trazo de cada icono dibujado, por el nombre de su SVG
/// original (para pruebas). `tio` está en `assets/icons/tabler-style/`; el
/// resto, en `test/fixtures/occasion_icons/`.
const Map<String, List<String>> kOccasionStrokeIconData = {
  'tio': _dataTio,
  'cny-a': _dataChineseNewYear,
  'wedding-b': _dataWedding,
};
