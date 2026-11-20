import 'package:flutter/material.dart';

import '../sync/model.dart';
import 'accent_palette.dart';

/// La ilustración de la cabecera de una ocasión (`OccasionBanner`).
enum OccasionArt {
  santa,
  tio,
  kings,
  birthday,
  chineseNewYear,
  wedding,
  anniversary,
  santJordi,
  valentine,
  baptism,
  communion,
  graduation,
  custom,
}

/// Un color elegible para una ocasión «Otra».
///
/// [name] se guarda en la ocasión (`Occasion.color`): no renombrar.
@immutable
class OccasionColor {
  const OccasionColor(this.name, this.palette);

  final String name;
  final AccentPalette palette;
}

/// Los ocho colores que se pueden elegir para una ocasión «Otra».
final List<OccasionColor> kOccasionColors = [
  OccasionColor('lavender', AccentId.lavender.palette),
  OccasionColor('sage', AccentId.sage.palette),
  OccasionColor('peach', AccentId.peach.palette),
  OccasionColor('sky', AccentId.sky.palette),
  OccasionColor('rose', AccentId.rose.palette),
  OccasionColor('butter', AccentId.butter.palette),
  const OccasionColor(
    'teal',
    AccentPalette(
      pastel: Color(0xFFCDEDEA),
      tinta: Color(0xFF0F6B66),
      swatchBorder: Color(0xFFA5D8D3),
    ),
  ),
  const OccasionColor(
    'slate',
    AccentPalette(
      pastel: Color(0xFFDDE3EA),
      tinta: Color(0xFF3B4A5C),
      swatchBorder: Color(0xFFC3CDD9),
    ),
  ),
];

/// Los iconos que se pueden elegir para una ocasión «Otra», por nombre.
///
/// El nombre se guarda en la ocasión (`Occasion.icon`): no renombrar.
const Map<String, IconData> kOccasionIcons = {
  'star': Icons.star_outlined,
  'heart': Icons.favorite_border_outlined,
  'home': Icons.home_outlined,
  'trip': Icons.flight_takeoff_outlined,
  'school': Icons.school_outlined,
  'pets': Icons.pets_outlined,
  'baby': Icons.child_care_outlined,
  'work': Icons.work_outline_outlined,
  'music': Icons.music_note_outlined,
  'sport': Icons.sports_soccer_outlined,
  'flower': Icons.local_florist_outlined,
  'party': Icons.celebration_outlined,
};

/// Icono de serie de una ocasión «Otra».
const String kDefaultOccasionIcon = 'star';

/// Color de serie de una ocasión «Otra».
const String kDefaultOccasionColor = 'lavender';

/// Tema de una ocasión: cambia el acento, pinta una cabecera ilustrada y
/// añade adornos.
///
/// Los acentos de Navidad y cumpleaños vienen de `P6-Navidad.dc.html` y
/// `P6-Cumple.dc.html` (Navidad pasó a rojo con Papá Noel); los demás siguen
/// la misma idea (un pastel, su tinta y el par oscuro) y todos llegan a
/// contraste AA, lo comprueba `test/theme/theme_test.dart`.
@immutable
class OccasionTheme {
  const OccasionTheme({
    required this.id,
    required this.palette,
    required this.cardBorder,
    required this.ornament,
    required this.ornamentD,
    required this.ornamentAlt,
    required this.ornamentAltD,
    required this.ornamentLine,
    required this.ornamentLineD,
    this.art = OccasionArt.custom,
    this.banner = const [Color(0xFFD8D2F8), Color(0xFFB9B0EE)],
    this.bannerD = const [Color(0xFF3D3C43), Color(0xFF2A2931)],
    this.icon,
    this.markLight,
    this.markDark,
  });

  final String id;

  /// Acento de la ocasión (sustituye al elegido en Ajustes).
  final AccentPalette palette;

  /// Borde de la tarjeta de cuenta atrás.
  final Color cardBorder;

  /// Borde de la tarjeta en oscuro: el pastel al 30 % sobre el fondo.
  Color get cardBorderD => palette.borderD;

  /// Adorno principal (dorado de Navidad, naranja del confeti) y secundario.
  final Color ornament;
  final Color ornamentD;
  final Color ornamentAlt;
  final Color ornamentAltD;

  /// Filete a los lados del adorno de la cabecera.
  final Color ornamentLine;
  final Color ornamentLineD;

  /// Ilustración de la cabecera.
  final OccasionArt art;

  /// Degradado de fondo de la cabecera (de arriba abajo), en claro y en
  /// oscuro.
  final List<Color> banner;
  final List<Color> bannerD;

  /// Icono grande de la cabecera de una ocasión «Otra».
  final IconData? icon;

  /// Color propio de la ocasión para sus puntos en Reparto: se elige para que
  /// los tipos que suelen convivir (Papá Noel, Tió, Reyes, cumpleaños) se
  /// distingan; sin él se usa el acento.
  final Color? markLight;
  final Color? markDark;

  /// Color de un punto o marca de esta ocasión sobre una superficie o el
  /// fondo de la pantalla (3:1 o más).
  Color mark({required bool dark}) =>
      dark ? (markDark ?? palette.pastel) : (markLight ?? palette.tinta);

  /// Navidad, Papá Noel: rojo con guirnalda.
  static const christmas = OccasionTheme(
    id: 'christmas',
    palette: AccentPalette(
      pastel: Color(0xFFF9D4D0),
      tinta: Color(0xFF9E1B1B),
      swatchBorder: Color(0xFFEDB0AB),
    ),
    cardBorder: Color(0xFFEDB0AB),
    ornament: Color(0xFFB8892B),
    ornamentD: Color(0xFFD6B478),
    ornamentAlt: Color(0xFF2E7D4F),
    ornamentAltD: Color(0xFF7CC396),
    ornamentLine: Color(0xFFE6C7C3),
    ornamentLineD: Color(0xFF533C37),
    markLight: Color(0xFFC62828),
    markDark: Color(0xFFFFA197),
    art: OccasionArt.santa,
    banner: [Color(0xFFA5232A), Color(0xFF6E1319)],
    bannerD: [Color(0xFF75201C), Color(0xFF540005)],
  );

  /// Tió: verde de bosque con el tronco y su barretina.
  static const tio = OccasionTheme(
    id: 'tio',
    palette: AccentPalette(
      pastel: Color(0xFFD5E8DB),
      tinta: Color(0xFF1F5C3A),
      swatchBorder: Color(0xFFBCD5C4),
    ),
    cardBorder: Color(0xFFBCD5C4),
    ornament: Color(0xFFB8892B),
    ornamentD: Color(0xFFD6B478),
    ornamentAlt: Color(0xFFC62828),
    ornamentAltD: Color(0xFFE8A39C),
    ornamentLine: Color(0xFFDCCB9A),
    ornamentLineD: Color(0xFF364838),
    markLight: Color(0xFF2E7D32),
    markDark: Color(0xFF7DD77E),
    art: OccasionArt.tio,
    banner: [Color(0xFF2F6B47), Color(0xFF1E4630)],
    bannerD: [Color(0xFF02502E), Color(0xFF013219)],
  );

  /// Reyes Magos: noche índigo con la estrella y las coronas.
  static const kings = OccasionTheme(
    id: 'kings',
    palette: AccentPalette(
      pastel: Color(0xFFE3D8F5),
      tinta: Color(0xFF52279A),
      swatchBorder: Color(0xFFCDBDEB),
    ),
    cardBorder: Color(0xFFCDBDEB),
    ornament: Color(0xFFB8892B),
    ornamentD: Color(0xFFD6B478),
    ornamentAlt: Color(0xFF7E57C2),
    ornamentAltD: Color(0xFFBEABEA),
    ornamentLine: Color(0xFFD8CCEE),
    ornamentLineD: Color(0xFF453E52),
    markLight: Color(0xFF6A3FB5),
    markDark: Color(0xFFC4AFFE),
    art: OccasionArt.kings,
    banner: [Color(0xFF2A1A66), Color(0xFF47298C)],
    bannerD: [Color(0xFF48317A), Color(0xFF2F145C)],
  );

  /// Cumpleaños: coral suave con vela, bengala y confeti.
  static const birthday = OccasionTheme(
    id: 'birthday',
    palette: AccentPalette(
      pastel: Color(0xFFFFD5CF),
      tinta: Color(0xFFA8324A),
      swatchBorder: Color(0xFFF0B9B0),
    ),
    cardBorder: Color(0xFFF0B9B0),
    ornament: Color(0xFFE8912D),
    ornamentD: Color(0xFFD2A272),
    ornamentAlt: Color(0xFF12A3A3),
    ornamentAltD: Color(0xFF48B9B8),
    ornamentLine: Color(0xFFF0C9C2),
    ornamentLineD: Color(0xFF543B3B),
    markLight: Color(0xFF00838F),
    markDark: Color(0xFF09D6E8),
    art: OccasionArt.birthday,
    banner: [Color(0xFFEF6B72), Color(0xFFD14262)],
    bannerD: [Color(0xFF741E31), Color(0xFF52001A)],
  );

  /// Año Nuevo Chino: rojo y oro con faroles.
  static const chineseNewYear = OccasionTheme(
    id: 'chineseNewYear',
    palette: AccentPalette(
      pastel: Color(0xFFFAD8CC),
      tinta: Color(0xFFA3220F),
      swatchBorder: Color(0xFFEDB9A8),
    ),
    cardBorder: Color(0xFFEDB9A8),
    ornament: Color(0xFFB8892B),
    ornamentD: Color(0xFFD6B478),
    ornamentAlt: Color(0xFFD84315),
    ornamentAltD: Color(0xFFE5A593),
    ornamentLine: Color(0xFFE9CDBF),
    ornamentLineD: Color(0xFF533C35),
    markLight: Color(0xFFE65100),
    markDark: Color(0xFFFEA382),
    art: OccasionArt.chineseNewYear,
    banner: [Color(0xFFC8171E), Color(0xFF8E0E14)],
    bannerD: [Color(0xFF752113), Color(0xFF520600)],
  );

  /// Boda: marfil y oro con dos alianzas.
  static const wedding = OccasionTheme(
    id: 'wedding',
    palette: AccentPalette(
      pastel: Color(0xFFF3EAD3),
      tinta: Color(0xFF6B5214),
      swatchBorder: Color(0xFFE2D4AE),
    ),
    cardBorder: Color(0xFFE2D4AE),
    ornament: Color(0xFFB8892B),
    ornamentD: Color(0xFFD6B478),
    ornamentAlt: Color(0xFFC48A9A),
    ornamentAltD: Color(0xFFE79FB4),
    ornamentLine: Color(0xFFE8DCB8),
    ornamentLineD: Color(0xFF4B412D),
    markLight: Color(0xFF9E7C00),
    markDark: Color(0xFFE4B831),
    art: OccasionArt.wedding,
    banner: [Color(0xFFF6EBCB), Color(0xFFE2CB8E)],
    bannerD: [Color(0xFF563E00), Color(0xFF362601)],
  );

  /// Aniversario: burdeos con dos copas.
  static const anniversary = OccasionTheme(
    id: 'anniversary',
    palette: AccentPalette(
      pastel: Color(0xFFF6D5DD),
      tinta: Color(0xFF8E1F45),
      swatchBorder: Color(0xFFE9B7C8),
    ),
    cardBorder: Color(0xFFE9B7C8),
    ornament: Color(0xFFB8892B),
    ornamentD: Color(0xFFD6B478),
    ornamentAlt: Color(0xFFB04A6C),
    ornamentAltD: Color(0xFFE89FB4),
    ornamentLine: Color(0xFFEBCAD3),
    ornamentLineD: Color(0xFF533B3D),
    markLight: Color(0xFF6D4C41),
    markDark: Color(0xFFFFA384),
    art: OccasionArt.anniversary,
    banner: [Color(0xFF8A2547), Color(0xFF591530)],
    bannerD: [Color(0xFF731E39), Color(0xFF510021)],
  );

  /// Sant Jordi: oro de senyera con el libro y la rosa.
  static const santJordi = OccasionTheme(
    id: 'santJordi',
    palette: AccentPalette(
      pastel: Color(0xFFFBE9A6),
      tinta: Color(0xFF744D00),
      swatchBorder: Color(0xFFE9D47E),
    ),
    cardBorder: Color(0xFFE9D47E),
    ornament: Color(0xFFC62828),
    ornamentD: Color(0xFFE69B93),
    ornamentAlt: Color(0xFFB8892B),
    ornamentAltD: Color(0xFFCDA863),
    ornamentLine: Color(0xFFEFDD99),
    ornamentLineD: Color(0xFF4D402D),
    markLight: Color(0xFF827717),
    markDark: Color(0xFFD1C139),
    art: OccasionArt.santJordi,
    banner: [Color(0xFFF7CB45), Color(0xFFE59B22)],
    bannerD: [Color(0xFF5B3B00), Color(0xFF392401)],
  );

  /// San Valentín: rosa con corazones y una flecha.
  static const valentine = OccasionTheme(
    id: 'valentine',
    palette: AccentPalette(
      pastel: Color(0xFFFAD2E1),
      tinta: Color(0xFFA81453),
      swatchBorder: Color(0xFFEFB2CA),
    ),
    cardBorder: Color(0xFFEFB2CA),
    ornament: Color(0xFFD81B60),
    ornamentD: Color(0xFFE599A8),
    ornamentAlt: Color(0xFFB8892B),
    ornamentAltD: Color(0xFFCDA863),
    ornamentLine: Color(0xFFF1C8D9),
    ornamentLineD: Color(0xFF533B3E),
    markLight: Color(0xFFD81B60),
    markDark: Color(0xFFFF9DAF),
    art: OccasionArt.valentine,
    banner: [Color(0xFFEE5F8F), Color(0xFFC62868)],
    bannerD: [Color(0xFF721E3C), Color(0xFF500124)],
  );

  /// Bautizo o nacimiento: azul cielo con un móvil de cuna.
  static const baptism = OccasionTheme(
    id: 'baptism',
    palette: AccentPalette(
      pastel: Color(0xFFD3E8F7),
      tinta: Color(0xFF1D5A8A),
      swatchBorder: Color(0xFFB3D3EC),
    ),
    cardBorder: Color(0xFFB3D3EC),
    ornament: Color(0xFFB8892B),
    ornamentD: Color(0xFFD6B478),
    ornamentAlt: Color(0xFF4F9AD0),
    ornamentAltD: Color(0xFF8ABCE4),
    ornamentLine: Color(0xFFC9DFF0),
    ornamentLineD: Color(0xFF334454),
    markLight: Color(0xFF0277BD),
    markDark: Color(0xFF82C5FE),
    art: OccasionArt.baptism,
    banner: [Color(0xFFBFE0F7), Color(0xFF8FC6EE)],
    bannerD: [Color(0xFF004574), Color(0xFF012B4A)],
  );

  /// Comunión: turquesa claro con el cáliz y la luz.
  static const communion = OccasionTheme(
    id: 'communion',
    palette: AccentPalette(
      pastel: Color(0xFFD2EEE8),
      tinta: Color(0xFF0F6B5E),
      swatchBorder: Color(0xFFB1DDD3),
    ),
    cardBorder: Color(0xFFB1DDD3),
    ornament: Color(0xFFB8892B),
    ornamentD: Color(0xFFD6B478),
    ornamentAlt: Color(0xFF26A69A),
    ornamentAltD: Color(0xFF50BBB1),
    ornamentLine: Color(0xFFC6E6DF),
    ornamentLineD: Color(0xFF2F4940),
    markLight: Color(0xFF00897B),
    markDark: Color(0xFF0DDBC5),
    art: OccasionArt.communion,
    banner: [Color(0xFFA9E0D5), Color(0xFF6CC3B4)],
    bannerD: [Color(0xFF044E43), Color(0xFF01312A)],
  );

  /// Graduación o fin de curso: azul marino con birrete y diploma.
  static const graduation = OccasionTheme(
    id: 'graduation',
    palette: AccentPalette(
      pastel: Color(0xFFD5DEF2),
      tinta: Color(0xFF1F3A8A),
      swatchBorder: Color(0xFFB8C6E8),
    ),
    cardBorder: Color(0xFFB8C6E8),
    ornament: Color(0xFFB8892B),
    ornamentD: Color(0xFFD6B478),
    ornamentAlt: Color(0xFF3F5BB8),
    ornamentAltD: Color(0xFFA3B7E8),
    ornamentLine: Color(0xFFCBD6EE),
    ornamentLineD: Color(0xFF3B4255),
    markLight: Color(0xFF283593),
    markDark: Color(0xFFA6BAFF),
    art: OccasionArt.graduation,
    banner: [Color(0xFF223C86), Color(0xFF15275C)],
    bannerD: [Color(0xFF233D81), Color(0xFF0C2063)],
  );

  /// Todos los temas con nombre (los de las ocasiones que no son «Otra»).
  static const all = [
    christmas,
    tio,
    kings,
    birthday,
    chineseNewYear,
    wedding,
    anniversary,
    santJordi,
    valentine,
    baptism,
    communion,
    graduation,
  ];

  /// Tema de una ocasión «Otra» con el color y el icono elegidos. Un nombre
  /// que no se conoce cae en el color o el icono de serie.
  factory OccasionTheme.custom({String? color, String? icon}) {
    final chosen = kOccasionColors.firstWhere(
      (c) => c.name == color,
      orElse: () => kOccasionColors.first,
    );
    final p = chosen.palette;
    return OccasionTheme(
      id: 'custom-${chosen.name}',
      palette: p,
      cardBorder: p.swatchBorder,
      ornament: p.tinta,
      ornamentD: p.tintaD,
      ornamentAlt: Color.lerp(p.tinta, p.pastel, 0.35)!,
      ornamentAltD: p.pastel,
      ornamentLine: p.swatchBorder,
      ornamentLineD: p.borderD,
      art: OccasionArt.custom,
      banner: [p.pastel, p.pastel],
      bannerD: [p.tintD, p.tintD],
      icon: kOccasionIcons[icon] ?? kOccasionIcons[kDefaultOccasionIcon],
    );
  }

  /// El tema que corresponde a [kind]; `null` para una ocasión «Otra», que
  /// necesita su color y su icono (ver [forOccasion]).
  static OccasionTheme? forKind(OccasionKind kind) => switch (kind) {
    OccasionKind.santa => christmas,
    OccasionKind.tio => tio,
    OccasionKind.kings => kings,
    OccasionKind.birthday => birthday,
    OccasionKind.chineseNewYear => chineseNewYear,
    OccasionKind.wedding => wedding,
    OccasionKind.anniversary => anniversary,
    OccasionKind.santJordi => santJordi,
    OccasionKind.valentine => valentine,
    OccasionKind.baptism => baptism,
    OccasionKind.communion => communion,
    OccasionKind.graduation => graduation,
    OccasionKind.custom => null,
  };

  /// El tema de una ocasión: el de su tipo o, si es «Otra», el de su color y
  /// su icono.
  static OccasionTheme forOccasion(Occasion occasion) =>
      forKind(occasion.kind) ??
      OccasionTheme.custom(color: occasion.color, icon: occasion.icon);
}
