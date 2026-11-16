// Iconos de ocasión dibujados para Gift Huddle con el mismo trazo que Tabler
// (rejilla de 24, trazo 2, extremos y uniones redondos, sin rellenos).
//
// Los datos son los de los SVG de los iconos de ocasión (obra
// del propio proyecto, bajo su misma licencia); lo comprueba
// `test/widgets/occasion_icons_test.dart`. La corona de Reyes es la `crown`
// de Tabler (MIT), que ya lleva la app.
import 'stroke_icon.dart';
import 'svg_path.dart';

/// Tió: tronco tumbado con barretina (`tio-a`).
const _dataTio = <String>[
  'M6 10.2a2.8 3.8 0 1 0 0 7.6a2.8 3.8 0 1 0 0 -7.6',
  'M6 10.2h11.7a3.8 3.8 0 0 1 0 7.6h-11.7',
  'M8.5 17.8v2.7',
  'M14 17.8v2.7',
  'M4.5 10.8c-.1 -3.6 .9 -6.3 3.2 -7.3c1.8 -.8 3.7 -.2 4.8 1.4',
  'M12.5 4.9c-1.9 .7 -3.1 2.6 -3.4 5.3',
];
final StrokeIconBuilder occasionIconTio = svgIcon(_dataTio);

/// Papá Noel: el gorro (`santa-a`).
const _dataSanta = <String>[
  'M4 17.5a1.5 1.5 0 0 1 1.5 -1.5h13a1.5 1.5 0 0 1 0 3h-13a1.5 1.5 0 0 1 -1.5 -1.5',
  'M6 16c0 -6.2 2.6 -10.1 7.2 -10.6c3 -.3 5 1.4 5.8 4.6',
  'M17.6 16c0 -2.3 -.4 -4.3 -1.3 -6.1',
  'M17.5 11.6a1.5 1.5 0 1 0 3 0a1.5 1.5 0 1 0 -3 0',
];
final StrokeIconBuilder occasionIconSanta = svgIcon(_dataSanta);

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
/// original (para pruebas).
const Map<String, List<String>> kOccasionStrokeIconData = {
  'tio-a': _dataTio,
  'santa-a': _dataSanta,
  'cny-a': _dataChineseNewYear,
  'wedding-b': _dataWedding,
};
