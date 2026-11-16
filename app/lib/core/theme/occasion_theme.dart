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
      pastelD: Color(0xFF10C7BF),
      tintaD: Color(0xFF00DDD4),
      tintD: Color(0xFF013C39),
      onFill: Color(0xFF001B19),
      swatchBorder: Color(0xFFA5D8D3),
    ),
  ),
  const OccasionColor(
    'slate',
    AccentPalette(
      pastel: Color(0xFFDDE3EA),
      tinta: Color(0xFF3B4A5C),
      pastelD: Color(0xFF51A0FF),
      tintaD: Color(0xFF96C4FE),
      tintD: Color(0xFF153358),
      onFill: Color(0xFF05162C),
      swatchBorder: Color(0xFFC3CDD9),
    ),
  ),
];

/// Los iconos que se pueden elegir para una ocasión «Otra», por nombre.
///
/// El nombre se guarda en la ocasión (`Occasion.icon`): no renombrar.
const Map<String, IconData> kOccasionIcons = {
  'star': Icons.star_outline_rounded,
  'heart': Icons.favorite_border_rounded,
  'home': Icons.home_outlined,
  'trip': Icons.flight_takeoff_rounded,
  'school': Icons.school_outlined,
  'pets': Icons.pets_outlined,
  'baby': Icons.child_care_outlined,
  'work': Icons.work_outline_rounded,
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
    required this.cardBorderD,
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
  final Color cardBorderD;

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
      dark ? (markDark ?? palette.pastelD) : (markLight ?? palette.tinta);

  /// Navidad, Papá Noel: rojo con guirnalda.
  static const christmas = OccasionTheme(
    id: 'christmas',
    palette: AccentPalette(
      pastel: Color(0xFFF9D4D0),
      tinta: Color(0xFF9E1B1B),
      pastelD: Color(0xFFFF8578),
      tintaD: Color(0xFFFEA69B),
      tintD: Color(0xFF53211D),
      onFill: Color(0xFF290B09),
      swatchBorder: Color(0xFFEDB0AB),
    ),
    cardBorder: Color(0xFFEDB0AB),
    cardBorderD: Color(0xFF873F38),
    ornament: Color(0xFFB8892B),
    ornamentD: Color(0xFFF5C672),
    ornamentAlt: Color(0xFF2E7D4F),
    ornamentAltD: Color(0xFF7ADD9E),
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
      pastelD: Color(0xFF12CE7B),
      tintaD: Color(0xFF62DD97),
      tintD: Color(0xFF043E22),
      onFill: Color(0xFF001C0C),
      swatchBorder: Color(0xFFBCD5C4),
    ),
    cardBorder: Color(0xFFBCD5C4),
    cardBorderD: Color(0xFF1A683F),
    ornament: Color(0xFFB8892B),
    ornamentD: Color(0xFFF5C672),
    ornamentAlt: Color(0xFFC62828),
    ornamentAltD: Color(0xFFFFABA2),
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
      pastelD: Color(0xFFA785FE),
      tintaD: Color(0xFFC5B4FF),
      tintD: Color(0xFF362A55),
      onFill: Color(0xFF18112A),
      swatchBorder: Color(0xFFCDBDEB),
    ),
    cardBorder: Color(0xFFCDBDEB),
    cardBorderD: Color(0xFF5C4B8A),
    ornament: Color(0xFFB8892B),
    ornamentD: Color(0xFFF5C672),
    ornamentAlt: Color(0xFF7E57C2),
    ornamentAltD: Color(0xFFCBB6FE),
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
      pastelD: Color(0xFFFE8293),
      tintaD: Color(0xFFFEA4AD),
      tintD: Color(0xFF522028),
      onFill: Color(0xFF280B10),
      swatchBorder: Color(0xFFF0B9B0),
    ),
    cardBorder: Color(0xFFF0B9B0),
    cardBorderD: Color(0xFF863E49),
    ornament: Color(0xFFE8912D),
    ornamentD: Color(0xFFF1AE6B),
    ornamentAlt: Color(0xFF12A3A3),
    ornamentAltD: Color(0xFF36DEDD),
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
      pastelD: Color(0xFFFE8671),
      tintaD: Color(0xFFFFA796),
      tintD: Color(0xFF53221A),
      onFill: Color(0xFF290C07),
      swatchBorder: Color(0xFFEDB9A8),
    ),
    cardBorder: Color(0xFFEDB9A8),
    cardBorderD: Color(0xFF874033),
    ornament: Color(0xFFB8892B),
    ornamentD: Color(0xFFF5C672),
    ornamentAlt: Color(0xFFD84315),
    ornamentAltD: Color(0xFFFEAD96),
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
      pastelD: Color(0xFFFDC001),
      tintaD: Color(0xFFFDC94B),
      tintD: Color(0xFF423001),
      onFill: Color(0xFF1E1400),
      swatchBorder: Color(0xFFE2D4AE),
    ),
    cardBorder: Color(0xFFE2D4AE),
    cardBorderD: Color(0xFF705301),
    ornament: Color(0xFFB8892B),
    ornamentD: Color(0xFFF5C672),
    ornamentAlt: Color(0xFFC48A9A),
    ornamentAltD: Color(0xFFFEA6C0),
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
      pastelD: Color(0xFFFF7FA0),
      tintaD: Color(0xFFFEA2B7),
      tintD: Color(0xFF51202D),
      onFill: Color(0xFF280B13),
      swatchBorder: Color(0xFFE9B7C8),
    ),
    cardBorder: Color(0xFFE9B7C8),
    cardBorderD: Color(0xFF853D50),
    ornament: Color(0xFFB8892B),
    ornamentD: Color(0xFFF5C672),
    ornamentAlt: Color(0xFFB04A6C),
    ornamentAltD: Color(0xFFFFA6BF),
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
      pastelD: Color(0xFFFFBD56),
      tintaD: Color(0xFFFEC672),
      tintD: Color(0xFF462D00),
      onFill: Color(0xFF211300),
      swatchBorder: Color(0xFFE9D47E),
    ),
    cardBorder: Color(0xFFE9D47E),
    cardBorderD: Color(0xFF764F01),
    ornament: Color(0xFFC62828),
    ornamentD: Color(0xFFFFA096),
    ornamentAlt: Color(0xFFB8892B),
    ornamentAltD: Color(0xFFEFBB58),
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
      pastelD: Color(0xFFFF7EA4),
      tintaD: Color(0xFFFFA1BA),
      tintD: Color(0xFF51202F),
      onFill: Color(0xFF280B14),
      swatchBorder: Color(0xFFEFB2CA),
    ),
    cardBorder: Color(0xFFEFB2CA),
    cardBorderD: Color(0xFF843D52),
    ornament: Color(0xFFD81B60),
    ornamentD: Color(0xFFFD9EB0),
    ornamentAlt: Color(0xFFB8892B),
    ornamentAltD: Color(0xFFEFBB58),
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
      pastelD: Color(0xFF2EA5FF),
      tintaD: Color(0xFF8BC7FE),
      tintD: Color(0xFF0A3557),
      onFill: Color(0xFF01172B),
      swatchBorder: Color(0xFFB3D3EC),
    ),
    cardBorder: Color(0xFFB3D3EC),
    cardBorderD: Color(0xFF1D5C8C),
    ornament: Color(0xFFB8892B),
    ornamentD: Color(0xFFF5C672),
    ornamentAlt: Color(0xFF4F9AD0),
    ornamentAltD: Color(0xFF8ACCFF),
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
      pastelD: Color(0xFF0FC9B2),
      tintaD: Color(0xFF05DFC5),
      tintD: Color(0xFF013C34),
      onFill: Color(0xFF001B17),
      swatchBorder: Color(0xFFB1DDD3),
    ),
    cardBorder: Color(0xFFB1DDD3),
    cardBorderD: Color(0xFF006759),
    ornament: Color(0xFFB8892B),
    ornamentD: Color(0xFFF5C672),
    ornamentAlt: Color(0xFF26A69A),
    ornamentAltD: Color(0xFF41DFCF),
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
      pastelD: Color(0xFF7199FF),
      tintaD: Color(0xFFA5C0FF),
      tintD: Color(0xFF213159),
      onFill: Color(0xFF0B152D),
      swatchBorder: Color(0xFFB8C6E8),
    ),
    cardBorder: Color(0xFFB8C6E8),
    cardBorderD: Color(0xFF3D5590),
    ornament: Color(0xFFB8892B),
    ornamentD: Color(0xFFF5C672),
    ornamentAlt: Color(0xFF3F5BB8),
    ornamentAltD: Color(0xFFABC3FE),
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
      cardBorderD: Color.lerp(p.tintD, p.pastelD, 0.25)!,
      ornament: p.tinta,
      ornamentD: p.tintaD,
      ornamentAlt: p.pastelD,
      ornamentAltD: p.pastelD,
      ornamentLine: p.swatchBorder,
      ornamentLineD: Color.lerp(p.tintD, p.pastelD, 0.3)!,
      art: OccasionArt.custom,
      banner: [p.pastel, Color.lerp(p.pastel, p.pastelD, 0.7)!],
      bannerD: [
        Color.lerp(p.tintD, p.pastelD, 0.18)!,
        Color.lerp(p.tintD, Colors.black, 0.25)!,
      ],
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
