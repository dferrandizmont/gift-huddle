import 'package:flutter/material.dart';

import '../sync/model.dart';
import '../theme/occasion_theme.dart';
import 'occasion_stroke_icons.dart';
import 'stroke_icon.dart';
import 'tabler_icons.dart';

/// El icono de trazo propio de un tipo de ocasión, o `null` si ese tipo usa
/// uno de Material ([occasionKindIcon]).
///
/// Navidad: `christmas-tree`; Reyes: `crown`; cumpleaños: `cake` (los tres
/// de Tabler). Tió, Año Nuevo chino (farolillo) y boda (dos alianzas) están
/// dibujados con las reglas de Tabler porque ninguna biblioteca los trae.
StrokeIconBuilder? occasionKindStrokeIcon(OccasionKind kind) => switch (kind) {
  OccasionKind.tio => occasionIconTio,
  OccasionKind.santa => tablerChristmasTree,
  OccasionKind.kings => tablerCrown,
  OccasionKind.birthday => tablerCake,
  OccasionKind.chineseNewYear => occasionIconChineseNewYear,
  OccasionKind.wedding => occasionIconWedding,
  _ => null,
};

/// El icono de Material de un tipo de ocasión sin icono de trazo propio. Para
/// «Otra» sale el icono elegido en la ocasión. Los tipos con icono propio
/// ([occasionKindStrokeIcon]) devuelven aquí uno de reserva: dibújalos con
/// [OccasionKindIcon].
IconData occasionKindIcon(OccasionKind kind, {String? customIcon}) =>
    switch (kind) {
      OccasionKind.tio => Icons.park_outlined,
      OccasionKind.santa => Icons.ac_unit_rounded,
      OccasionKind.kings => Icons.stars_outlined,
      OccasionKind.birthday => Icons.cake_outlined,
      OccasionKind.chineseNewYear => Icons.festival_outlined,
      OccasionKind.wedding => Icons.diamond_outlined,
      OccasionKind.anniversary => Icons.wine_bar_outlined,
      OccasionKind.santJordi => Icons.menu_book_outlined,
      OccasionKind.valentine => Icons.favorite_border_rounded,
      OccasionKind.baptism => Icons.child_care_outlined,
      OccasionKind.communion => Icons.church_outlined,
      OccasionKind.graduation => Icons.school_outlined,
      OccasionKind.custom =>
        kOccasionIcons[customIcon] ?? kOccasionIcons[kDefaultOccasionIcon]!,
    };

/// El icono de un tipo de ocasión: el de trazo propio si lo tiene y, si no,
/// el de Material. Es decorativo (el texto lo lleva la fila que lo contiene).
class OccasionKindIcon extends StatelessWidget {
  const OccasionKindIcon(
    this.kind, {
    super.key,
    this.customIcon,
    this.size = 24,
    this.color,
  });

  final OccasionKind kind;

  /// Nombre del icono elegido para «Otra» (`Occasion.icon`).
  final String? customIcon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final stroke = occasionKindStrokeIcon(kind);
    if (stroke != null) {
      return StrokeIcon(stroke, size: size, color: color, strokeWidth: 2);
    }
    return Icon(
      occasionKindIcon(kind, customIcon: customIcon),
      size: size,
      color: color,
    );
  }
}
