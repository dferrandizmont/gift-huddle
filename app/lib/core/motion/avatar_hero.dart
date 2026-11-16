import 'package:flutter/material.dart';

import '../layout/pane_scope.dart';
import '../theme/regalos_motion.dart';
import '../widgets/person_avatar.dart';

/// El avatar de una persona que vuela de la fila de Personas a la cabecera de
/// su lista y vuelve (§1.5 de la guía de movimiento).
///
/// - Ida con `snap` (la ruta dura lo mismo); vuelta con `fold` en los 220 ms
///   de la ruta. Va recto, sin el arco de Material.
/// - En vuelo se pinta un [PersonAvatar] cuyo tamaño sigue al rectángulo, para
///   que la inicial escale con nitidez.
/// - Con «Reducir movimiento» no hay vuelo (`HeroMode` apagado).
/// - El nombre no vuela: un `Hero` de texto salta de tamaño de letra.
/// - Con dos paneles no hay ruta que cambie (el `Hero` se apaga) y tampoco hay
///   vuelo: la lista sigue a la vista y la cabecera no puede quedarse sin
///   avatar mientras algo viaja. El avatar del detalle entra con una escala de
///   0,92 a 1 en 160 ms; con
///   «Reducir movimiento», sin escala.
class AvatarHero extends StatefulWidget {
  /// Crea el avatar con vuelo.
  const AvatarHero({
    super.key,
    required this.personId,
    required this.name,
    required this.colorIndex,
    required this.size,
  });

  /// Identificador de la persona (empareja las dos pantallas).
  final String personId;
  final String name;
  final int colorIndex;

  /// Tamaño en reposo.
  final double size;

  /// De qué escala parte el avatar de la cabecera de un panel de detalle.
  static const double entryScale = 0.92;

  /// Lo que tarda en asentarse el avatar de la cabecera de un panel de detalle.
  static const Duration entryDuration = Duration(milliseconds: 160);

  /// La etiqueta del `Hero` de una persona.
  static Object tagFor(String personId) => 'avatar-$personId';

  /// La clave con la que el avatar de la barra lateral del tablero de la web
  /// vuela a la cabecera de la persona (`FlightTarget`).
  static Object flightKeyFor(String personId) => ('avatar-flight', personId);

  @override
  State<AvatarHero> createState() => _AvatarHeroState();
}

class _AvatarHeroState extends State<AvatarHero> {
  @override
  Widget build(BuildContext context) {
    final reduce = RegalosMotion.of(context).reduce;
    final avatar = HeroMode(
      enabled: !reduce,
      child: Hero(
        tag: AvatarHero.tagFor(widget.personId),
        curve: RegalosCurves.snap,
        // En la vuelta, la animación de la ruta va de 1 a 0 y el `Hero` la
        // invierte: con la curva `fold` volteada sale `fold` de ida.
        reverseCurve: RegalosCurves.fold.flipped,
        createRectTween: (begin, end) => RectTween(begin: begin, end: end),
        flightShuttleBuilder: (_, _, _, _, _) => LayoutBuilder(
          builder: (context, box) => PersonAvatar(
            name: widget.name,
            colorIndex: widget.colorIndex,
            size: box.biggest.shortestSide,
          ),
        ),
        child: PersonAvatar(
          name: widget.name,
          colorIndex: widget.colorIndex,
          size: widget.size,
        ),
      ),
    );
    if (PaneScope.roleOf(context) != PaneRole.detail || reduce) {
      return avatar;
    }
    // En el panel de detalle, la cabecera de cada persona (se monta de nuevo al
    // elegir otra) asienta el avatar con una escala pequeña.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: AvatarHero.entryScale, end: 1),
      duration: AvatarHero.entryDuration,
      curve: Curves.easeOut,
      child: avatar,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
    );
  }
}
