// Pendiente de rediseño; ver ramas ilustraciones*. Sin uso por ahora: la
// pantalla de la ocasión vuelve al color del tema y al adorno fino.

import 'package:flutter/material.dart';

import '../theme/occasion_theme.dart';
import 'occasion_art.dart';

/// Cabecera ilustrada de la pantalla de una ocasión: un cartel de color con
/// el dibujo de la fiesta (guirnalda con Papá Noel, las coronas y la estrella
/// de los Reyes, el Tió con su barretina, la vela del cumpleaños...).
///
/// Es solo dibujo: no lleva texto (el título sigue en la cabecera de la
/// pantalla, con el contraste de siempre) y no se anuncia a los lectores de
/// pantalla.
class OccasionBanner extends StatelessWidget {
  const OccasionBanner({super.key, required this.theme, required this.dark});

  final OccasionTheme theme;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: kArtWidth / kArtHeight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CustomPaint(
            painter: _BannerPainter(theme: theme, dark: dark),
          ),
        ),
      ),
    );
  }
}

class _BannerPainter extends CustomPainter {
  const _BannerPainter({required this.theme, required this.dark});

  final OccasionTheme theme;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final colors = dark ? theme.bannerD : theme.banner;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ).createShader(Offset.zero & size),
    );
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / kArtWidth, size.height / kArtHeight);
    paintOccasionArt(canvas, theme, dark: dark);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BannerPainter old) =>
      old.theme != theme || old.dark != dark;
}
