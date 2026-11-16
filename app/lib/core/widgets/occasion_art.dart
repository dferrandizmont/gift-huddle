// Pendiente de rediseño; ver ramas ilustraciones*. Sin uso por ahora: la
// pantalla de la ocasión vuelve al color del tema y al adorno fino.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/occasion_theme.dart';

/// Ancho y alto del lienzo en el que están dibujadas las ilustraciones; el
/// `OccasionBanner` lo escala al ancho disponible.
const double kArtWidth = 360;
const double kArtHeight = 132;

// Colores sueltos de las ilustraciones (no son tokens de la app: son dibujo).
const Color _white = Color(0xFFFFFFFF);
const Color _cream = Color(0xFFFFF4DC);
const Color _gold = Color(0xFFF5C451);
const Color _goldDark = Color(0xFFC8921C);
const Color _goldDeep = Color(0xFF9A6B0E);

Paint _fill(Color c, [double opacity = 1]) => Paint()
  ..color = c.withValues(alpha: opacity)
  ..style = PaintingStyle.fill
  ..isAntiAlias = true;

Paint _line(
  Color c,
  double width, {
  double opacity = 1,
  StrokeCap cap = StrokeCap.round,
}) => Paint()
  ..color = c.withValues(alpha: opacity)
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = cap
  ..strokeJoin = StrokeJoin.round
  ..isAntiAlias = true;

/// Estrella de cuatro puntas (destello).
void _sparkle(Canvas c, Offset o, double r, Paint p) {
  final path = Path();
  final k = r * 0.22;
  path
    ..moveTo(o.dx, o.dy - r)
    ..quadraticBezierTo(o.dx + k, o.dy - k, o.dx + r, o.dy)
    ..quadraticBezierTo(o.dx + k, o.dy + k, o.dx, o.dy + r)
    ..quadraticBezierTo(o.dx - k, o.dy + k, o.dx - r, o.dy)
    ..quadraticBezierTo(o.dx - k, o.dy - k, o.dx, o.dy - r)
    ..close();
  c.drawPath(path, p);
}

/// Estrella de cinco puntas.
Path _star5Path(Offset o, double r, {double inner = 0.45, double turn = 0}) {
  final path = Path();
  for (var i = 0; i < 10; i++) {
    final rr = i.isEven ? r : r * inner;
    final a = -math.pi / 2 + turn + i * math.pi / 5;
    final pt = Offset(o.dx + math.cos(a) * rr, o.dy + math.sin(a) * rr);
    if (i == 0) {
      path.moveTo(pt.dx, pt.dy);
    } else {
      path.lineTo(pt.dx, pt.dy);
    }
  }
  return path..close();
}

/// Corazón de ancho [s] con la punta abajo en `o + (0, 0.45 s)`.
Path _heartPath(Offset o, double s) {
  final k = s / 2;
  return Path()
    ..moveTo(o.dx, o.dy + 0.9 * k)
    ..cubicTo(
      o.dx - 1.55 * k,
      o.dy - 0.1 * k,
      o.dx - 0.75 * k,
      o.dy - 1.2 * k,
      o.dx,
      o.dy - 0.45 * k,
    )
    ..cubicTo(
      o.dx + 0.75 * k,
      o.dy - 1.2 * k,
      o.dx + 1.55 * k,
      o.dy - 0.1 * k,
      o.dx,
      o.dy + 0.9 * k,
    )
    ..close();
}

Offset _quad(Offset a, Offset b, Offset c, double t) {
  final u = 1 - t;
  return Offset(
    u * u * a.dx + 2 * u * t * b.dx + t * t * c.dx,
    u * u * a.dy + 2 * u * t * b.dy + t * t * c.dy,
  );
}

/// Dibuja la ilustración de [theme] en el lienzo de [kArtWidth] x
/// [kArtHeight].
void paintOccasionArt(
  Canvas canvas,
  OccasionTheme theme, {
  required bool dark,
}) {
  switch (theme.art) {
    case OccasionArt.santa:
      _santa(canvas, dark);
    case OccasionArt.tio:
      _tio(canvas, dark);
    case OccasionArt.kings:
      _kings(canvas, dark);
    case OccasionArt.birthday:
      _birthday(canvas, dark);
    case OccasionArt.chineseNewYear:
      _chineseNewYear(canvas, dark);
    case OccasionArt.wedding:
      _wedding(canvas, dark);
    case OccasionArt.anniversary:
      _anniversary(canvas, dark);
    case OccasionArt.santJordi:
      _santJordi(canvas, dark);
    case OccasionArt.valentine:
      _valentine(canvas, dark);
    case OccasionArt.baptism:
      _baptism(canvas, dark);
    case OccasionArt.communion:
      _communion(canvas, dark);
    case OccasionArt.graduation:
      _graduation(canvas, dark);
    case OccasionArt.custom:
      _custom(canvas, theme, dark);
  }
}

// ---------------------------------------------------------------- Papá Noel

void _santa(Canvas c, bool dark) {
  const snow = [
    (24.0, 52.0, 2.2),
    (58.0, 92.0, 1.8),
    (92.0, 60.0, 2.6),
    (40.0, 112.0, 2.0),
    (112.0, 104.0, 1.6),
    (132.0, 70.0, 2.0),
    (236.0, 76.0, 1.8),
    (262.0, 108.0, 2.4),
    (292.0, 64.0, 2.0),
    (322.0, 96.0, 2.6),
    (344.0, 60.0, 1.8),
    (306.0, 118.0, 1.6),
    (210.0, 120.0, 1.6),
    (16.0, 90.0, 1.6),
  ];
  for (final (x, y, r) in snow) {
    c.drawCircle(Offset(x, y), r, _fill(_white, 0.7));
  }
  _sparkle(c, const Offset(70, 82), 6, _fill(_white, 0.85));
  _sparkle(c, const Offset(296, 84), 7, _fill(_white, 0.85));
  _sparkle(c, const Offset(118, 40), 4, _fill(_gold, 0.9));

  // Guirnalda: un arco que cuelga de las esquinas.
  const a = Offset(-14, 2);
  const b = Offset(180, 76);
  const e = Offset(374, 2);
  final garland = Path()
    ..moveTo(a.dx, a.dy)
    ..quadraticBezierTo(b.dx, b.dy, e.dx, e.dy);
  c.drawPath(garland, _line(const Color(0xFF1B5E37), 14));
  c.drawPath(garland, _line(const Color(0xFF2E7D4F), 9));
  const greens = [Color(0xFF43A06A), Color(0xFF1F6E41), Color(0xFF5BB67F)];
  for (var i = 0; i < 90; i++) {
    final t = i / 89;
    final p = _quad(a, b, e, t);
    final ang = (i * 137) % 360 * math.pi / 180;
    final len = 5.0 + (i % 3) * 1.5;
    c.drawLine(
      p,
      p + Offset(math.cos(ang) * len, math.sin(ang) * len),
      _line(greens[i % 3], 2.2),
    );
  }
  // Bolas y luces.
  const baubleColors = [_gold, _cream, Color(0xFF9AD0FF), Color(0xFFFF8A80)];
  var n = 0;
  for (final t in const [0.07, 0.17, 0.27, 0.37, 0.63, 0.73, 0.83, 0.93]) {
    final p = _quad(a, b, e, t);
    final colour = baubleColors[n++ % baubleColors.length];
    c.drawLine(p, p + const Offset(0, 6), _line(_goldDeep, 1.2));
    c.drawCircle(p + const Offset(0, 13), 7, _fill(colour));
    c.drawCircle(p + const Offset(-2, 11), 2, _fill(_white, 0.65));
    c.drawRect(
      Rect.fromCenter(center: p + const Offset(0, 6), width: 5, height: 3),
      _fill(_goldDark),
    );
  }
  for (final t in const [0.12, 0.22, 0.32, 0.42, 0.58, 0.68, 0.78, 0.88]) {
    final p = _quad(a, b, e, t);
    c.drawCircle(p, 6, _fill(_gold, 0.25));
    c.drawCircle(p, 2.6, _fill(const Color(0xFFFFE680)));
  }
  // Lazos en las esquinas.
  for (final side in const [-1.0, 1.0]) {
    final o = Offset(side < 0 ? 24 : 336, 12);
    for (final turn in const [-0.5, 0.5]) {
      c.save();
      c.translate(o.dx, o.dy);
      c.rotate(side * turn);
      c.drawOval(
        Rect.fromCenter(center: Offset(side * 9, 0), width: 18, height: 9),
        _fill(_cream),
      );
      c.restore();
    }
    c.drawCircle(o, 4, _fill(_gold));
  }

  // Papá Noel: un busto que asoma por la guirnalda.
  c.save();
  c.translate(0, -7);
  const suit = Color(0xFFE53935);
  const suitDark = Color(0xFFB71C1C);
  final body = Rect.fromCenter(
    center: const Offset(180, 140),
    width: 118,
    height: 66,
  );
  c.drawOval(body, _fill(suit));
  c.drawOval(
    Rect.fromCenter(center: const Offset(180, 122), width: 92, height: 14),
    _fill(_white),
  );
  // Cara.
  const skin = Color(0xFFF6C9A5);
  c.drawCircle(const Offset(180, 86), 25, _fill(skin));
  c.drawCircle(const Offset(165, 92), 5, _fill(const Color(0xFFF08A80), 0.55));
  c.drawCircle(const Offset(195, 92), 5, _fill(const Color(0xFFF08A80), 0.55));
  // Barba.
  final beard = Paint()..color = _white;
  for (final (x, y, r) in const [
    (158.0, 98.0, 13.0),
    (202.0, 98.0, 13.0),
    (166.0, 110.0, 14.0),
    (194.0, 110.0, 14.0),
    (180.0, 116.0, 15.0),
    (180.0, 100.0, 18.0),
  ]) {
    c.drawCircle(Offset(x, y), r, beard);
  }
  // Bigote y nariz.
  for (final side in const [-1.0, 1.0]) {
    c.save();
    c.translate(180 + side * 9, 96);
    c.rotate(side * -0.25);
    c.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 22, height: 11),
      _fill(_white),
    );
    c.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 22, height: 11),
      _line(const Color(0xFFDCE3EA), 1),
    );
    c.restore();
  }
  c.drawCircle(const Offset(180, 90), 4.6, _fill(const Color(0xFFEE8B7E)));
  // Ojos y cejas.
  for (final x in const [170.0, 190.0]) {
    c.drawCircle(Offset(x, 80), 2, _fill(const Color(0xFF2B2B33)));
    c.drawLine(Offset(x - 5, 74), Offset(x + 5, 73), _line(_white, 3));
  }
  // Gorro: la banda blanca, el fieltro rojo caído y el pompón.
  final hat = Path()
    ..moveTo(153, 70)
    ..cubicTo(150, 40, 176, 26, 203, 36)
    ..cubicTo(218, 42, 226, 54, 230, 66)
    ..lineTo(206, 70)
    ..close();
  c.drawPath(hat, _fill(suit));
  c.drawPath(
    Path()
      ..moveTo(190, 33)
      ..cubicTo(208, 38, 220, 50, 224, 64)
      ..lineTo(208, 68)
      ..cubicTo(204, 54, 198, 44, 190, 33)
      ..close(),
    _fill(suitDark, 0.5),
  );
  c.drawCircle(const Offset(233, 70), 9, _fill(_white));
  c.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: const Offset(180, 69), width: 66, height: 13),
      const Radius.circular(6.5),
    ),
    _fill(_white),
  );
  // Sombra suave del gorro sobre la frente.
  c.drawRect(
    Rect.fromLTWH(156, 74, 48, 2),
    _fill(const Color(0xFF000000), 0.06),
  );
  c.restore();
}

// ---------------------------------------------------------------------- Tió

void _tio(Canvas c, bool dark) {
  // Estrellitas y nieve.
  for (final (x, y, r) in const [
    (30.0, 28.0, 5.0),
    (330.0, 30.0, 6.0),
    (300.0, 70.0, 3.5),
    (70.0, 52.0, 3.0),
    (250.0, 22.0, 4.0),
  ]) {
    _sparkle(c, Offset(x, y), r, _fill(_cream, 0.9));
  }
  for (final (x, y) in const [
    (46.0, 80.0),
    (100.0, 24.0),
    (206.0, 34.0),
    (320.0, 98.0),
    (280.0, 40.0),
    (24.0, 104.0),
  ]) {
    c.drawCircle(Offset(x, y), 1.8, _fill(_white, 0.7));
  }
  // Suelo.
  final ground = Path()
    ..moveTo(0, 112)
    ..quadraticBezierTo(90, 100, 180, 108)
    ..quadraticBezierTo(270, 116, 360, 102)
    ..lineTo(360, 132)
    ..lineTo(0, 132)
    ..close();
  c.drawPath(ground, _fill(const Color(0xFF173824), 0.75));

  // Patas.
  const wood = Color(0xFF7A4A24);
  const woodDark = Color(0xFF5B3517);
  for (final x in const [150.0, 262.0]) {
    c.drawLine(Offset(x, 100), Offset(x - 2, 118), _line(woodDark, 9));
  }
  // Cuerpo del tronco.
  final logBody = RRect.fromRectAndRadius(
    const Rect.fromLTRB(118, 62, 300, 106),
    const Radius.circular(16),
  );
  c.drawRRect(logBody, _fill(wood));
  // Vetas de la corteza.
  for (final (x1, y, x2) in const [
    (160.0, 72.0, 200.0),
    (200.0, 84.0, 250.0),
    (176.0, 96.0, 214.0),
    (240.0, 70.0, 280.0),
    (262.0, 94.0, 290.0),
  ]) {
    c.drawLine(Offset(x1, y), Offset(x2, y), _line(woodDark, 2.2));
  }
  // La manta.
  c.save();
  c.clipRRect(logBody);
  c.drawRect(
    const Rect.fromLTRB(206, 56, 304, 112),
    _fill(const Color(0xFFC62828)),
  );
  for (final x in const [226.0, 250.0, 274.0]) {
    c.drawRect(Rect.fromLTWH(x, 56, 7, 56), _fill(_gold));
  }
  c.restore();
  // La cara en el extremo cortado.
  final face = Rect.fromCenter(
    center: const Offset(124, 84),
    width: 40,
    height: 50,
  );
  c.drawOval(face.inflate(2), _fill(woodDark));
  c.drawOval(face, _fill(const Color(0xFFE3B67E)));
  c.drawOval(face.deflate(8), _line(const Color(0xFFC48E54), 1.4));
  c.drawOval(face.deflate(14), _line(const Color(0xFFC48E54), 1.2));
  c.drawCircle(const Offset(115, 80), 2.6, _fill(const Color(0xFF2B1B10)));
  c.drawCircle(const Offset(133, 80), 2.6, _fill(const Color(0xFF2B1B10)));
  c.drawCircle(const Offset(111, 90), 4, _fill(const Color(0xFFE57373), 0.7));
  c.drawCircle(const Offset(137, 90), 4, _fill(const Color(0xFFE57373), 0.7));
  c.drawArc(
    Rect.fromCenter(center: const Offset(124, 90), width: 18, height: 14),
    0.25,
    math.pi - 0.5,
    false,
    _line(const Color(0xFF2B1B10), 2),
  );
  // Barretina: un calcetín rojo caído hacia un lado con la banda oscura.
  final cap = Path()
    ..moveTo(110, 62)
    ..cubicTo(106, 22, 166, 14, 176, 56);
  c.drawPath(cap, _line(const Color(0xFFB71C1C), 22));
  c.drawPath(cap, _line(const Color(0xFFE53935), 16));
  c.drawPath(
    Path()
      ..moveTo(116, 52)
      ..cubicTo(116, 34, 140, 30, 154, 38),
    _line(const Color(0xFFFF8A80), 3, opacity: 0.7),
  );
  c.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: const Offset(124, 62), width: 38, height: 12),
      const Radius.circular(5),
    ),
    _fill(const Color(0xFF2B2B33)),
  );
  // Acebo con bayas.
  for (final side in const [-1.0, 1.0]) {
    c.save();
    c.translate(318, 100);
    c.rotate(side * 0.7);
    c.drawOval(
      Rect.fromCenter(center: const Offset(0, -9), width: 9, height: 20),
      _fill(const Color(0xFF3F9A5D)),
    );
    c.restore();
  }
  for (final p in const [
    Offset(314, 102),
    Offset(322, 101),
    Offset(318, 108),
  ]) {
    c.drawCircle(p, 3.4, _fill(const Color(0xFFE53935)));
  }
}

// -------------------------------------------------------------------- Reyes

void _kings(Canvas c, bool dark) {
  for (final (x, y, r) in const [
    (30.0, 20.0, 5.0),
    (118.0, 30.0, 4.0),
    (210.0, 16.0, 6.0),
    (330.0, 28.0, 5.0),
    (300.0, 70.0, 3.5),
    (20.0, 90.0, 3.5),
    (150.0, 78.0, 3.0),
  ]) {
    _sparkle(c, Offset(x, y), r, _fill(_cream, 0.9));
  }
  for (final (x, y) in const [
    (60.0, 12.0),
    (176.0, 40.0),
    (252.0, 38.0),
    (344.0, 84.0),
    (90.0, 100.0),
    (240.0, 8.0),
  ]) {
    c.drawCircle(Offset(x, y), 1.6, _fill(_white, 0.8));
  }
  // Estrella de Belén con su cola.
  const star = Offset(64, 46);
  final tail = Path()
    ..moveTo(star.dx - 4, star.dy + 4)
    ..quadraticBezierTo(120, 70, 188, 100)
    ..quadraticBezierTo(112, 62, star.dx + 4, star.dy - 4)
    ..close();
  c.drawPath(
    tail,
    Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xCCF5C451), Color(0x00F5C451)],
      ).createShader(const Rect.fromLTRB(60, 40, 190, 104)),
  );
  c.drawCircle(star, 30, _fill(_gold, 0.16));
  c.drawCircle(star, 20, _fill(_gold, 0.2));
  // Cuatro rayos largos y cuatro cortos.
  final rays = Path();
  for (var i = 0; i < 8; i++) {
    final a = i * math.pi / 4;
    final long = i.isEven;
    final r = long ? 30.0 : 17.0;
    final w = long ? 5.0 : 3.5;
    final tip = star + Offset(math.cos(a) * r, math.sin(a) * r);
    final l =
        star +
        Offset(math.cos(a - math.pi / 2) * w, math.sin(a - math.pi / 2) * w);
    final rr =
        star +
        Offset(math.cos(a + math.pi / 2) * w, math.sin(a + math.pi / 2) * w);
    rays
      ..moveTo(l.dx, l.dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(rr.dx, rr.dy)
      ..close();
  }
  c.drawPath(rays, _fill(_gold));
  c.drawCircle(star, 6, _fill(const Color(0xFFFFF1B8)));

  // Dunas.
  final dunes = Path()
    ..moveTo(0, 112)
    ..quadraticBezierTo(70, 96, 150, 110)
    ..quadraticBezierTo(250, 124, 360, 100)
    ..lineTo(360, 132)
    ..lineTo(0, 132)
    ..close();
  c.drawPath(dunes, _fill(const Color(0xFF150C38), 0.7));

  // Tres coronas de tamaños distintos.
  void crown(double cx, double base, double w, double h, Color jewel) {
    const band = Color(0xFFE0A526);
    final path = Path()
      ..moveTo(cx - w / 2, base)
      ..lineTo(cx - w / 2, base - h * 0.78)
      ..lineTo(cx - w / 4, base - h * 0.42)
      ..lineTo(cx, base - h * 0.95)
      ..lineTo(cx + w / 4, base - h * 0.42)
      ..lineTo(cx + w / 2, base - h * 0.78)
      ..lineTo(cx + w / 2, base)
      ..close();
    c.drawPath(path, _fill(_gold));
    c.drawPath(path, _line(_goldDeep, 1.2));
    c.drawRect(
      Rect.fromLTRB(cx - w / 2, base - h * 0.24, cx + w / 2, base),
      _fill(band),
    );
    for (final (x, y) in [
      (cx - w / 2, base - h * 0.78),
      (cx, base - h * 0.95),
      (cx + w / 2, base - h * 0.78),
    ]) {
      c.drawCircle(Offset(x, y), w * 0.06, _fill(_cream));
    }
    for (final dx in [-w * 0.3, 0.0, w * 0.3]) {
      c.drawCircle(
        Offset(cx + dx, base - h * 0.12),
        h * 0.075,
        _fill(dx == 0 ? jewel : _cream),
      );
    }
  }

  crown(196, 104, 44, 40, const Color(0xFFE53935));
  crown(262, 90, 64, 56, const Color(0xFF2E86DE));
  crown(326, 106, 44, 40, const Color(0xFF2EBD73));
}

// ----------------------------------------------------------------- Cumpleaños

void _birthday(Canvas c, bool dark) {
  // Confeti.
  const colors = [
    Color(0xFFFFC857),
    Color(0xFF2EC4B6),
    _white,
    Color(0xFFFFE0A3),
    Color(0xFF7BE0D5),
  ];
  final confetti = <(double, double, double)>[
    (20, 24, 0.4),
    (52, 60, 1.1),
    (96, 20, 2.0),
    (136, 54, 0.7),
    (28, 100, 1.6),
    (76, 112, 0.2),
    (150, 106, 2.5),
    (232, 22, 1.0),
    (258, 70, 0.5),
    (300, 18, 1.8),
    (336, 52, 0.9),
    (320, 108, 2.2),
    (284, 112, 0.3),
    (206, 112, 1.4),
    (346, 82, 2.8),
  ];
  for (var i = 0; i < confetti.length; i++) {
    final (x, y, a) = confetti[i];
    c.save();
    c.translate(x, y);
    c.rotate(a);
    final p = _fill(colors[i % colors.length]);
    switch (i % 3) {
      case 0:
        c.drawRect(const Rect.fromLTWH(-4, -2, 8, 4), p);
      case 1:
        c.drawCircle(Offset.zero, 2.8, p);
      default:
        c.drawPath(
          Path()
            ..moveTo(-4, 3)
            ..lineTo(4, 3)
            ..lineTo(0, -4)
            ..close(),
          p,
        );
    }
    c.restore();
  }

  // Bengala a la izquierda.
  const spark = Offset(78, 56);
  c.drawLine(spark, const Offset(52, 120), _line(const Color(0xFFE8E0D8), 3.5));
  c.drawLine(spark, const Offset(57, 104), _line(const Color(0xFF9E8F83), 3.5));
  for (var i = 0; i < 16; i++) {
    final a = i * math.pi / 8 + 0.2;
    final long = i.isEven ? 26.0 : 15.0;
    final colour = i % 3 == 0
        ? _white
        : (i % 3 == 1 ? _gold : const Color(0xFFFFE0A3));
    c.drawLine(
      spark + Offset(math.cos(a) * 5, math.sin(a) * 5),
      spark + Offset(math.cos(a) * long, math.sin(a) * long),
      _line(colour, 2.2),
    );
    c.drawCircle(
      spark + Offset(math.cos(a) * (long + 5), math.sin(a) * (long + 5)),
      1.6,
      _fill(colour),
    );
  }
  c.drawCircle(spark, 7, _fill(_gold, 0.35));
  c.drawCircle(spark, 3.5, _fill(_white));

  // Tarta con tres velas.
  const frosting = Color(0xFFFFF1F3);
  const cakeB = Color(0xFF8E3A59);
  final bottom = RRect.fromRectAndRadius(
    const Rect.fromLTRB(150, 92, 300, 124),
    const Radius.circular(8),
  );
  c.drawRRect(bottom, _fill(cakeB));
  final top = RRect.fromRectAndRadius(
    const Rect.fromLTRB(172, 64, 278, 94),
    const Radius.circular(8),
  );
  c.drawRRect(top, _fill(const Color(0xFFB7506F)));
  // Glaseado con gotas.
  for (final (rect, ys) in [
    (
      const Rect.fromLTRB(150, 92, 300, 100),
      [168.0, 196.0, 230.0, 262.0, 288.0],
    ),
    (const Rect.fromLTRB(172, 64, 278, 72), [188.0, 214.0, 246.0, 268.0]),
  ]) {
    c.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(5)),
      _fill(frosting),
    );
    for (final x in ys) {
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 4, rect.top + 2, 8, 12),
          const Radius.circular(4),
        ),
        _fill(frosting),
      );
    }
  }
  for (final x in const [168.0, 190.0, 212.0, 234.0, 258.0, 280.0]) {
    c.drawCircle(Offset(x, 112), 2.2, _fill(_gold));
  }
  // Velas.
  const candleColors = [Color(0xFF2EC4B6), _gold, Color(0xFF7AA7FF)];
  for (var i = 0; i < 3; i++) {
    final x = 198.0 + i * 38;
    final candle = RRect.fromRectAndRadius(
      Rect.fromLTRB(x - 4, 38, x + 4, 66),
      const Radius.circular(2),
    );
    c.drawRRect(candle, _fill(candleColors[i]));
    for (var s = 0; s < 3; s++) {
      c.drawLine(
        Offset(x - 4, 44.0 + s * 8),
        Offset(x + 4, 41.0 + s * 8),
        _line(_white, 2, opacity: 0.85),
      );
    }
    c.drawCircle(Offset(x, 28), 12, _fill(_gold, 0.28));
    final flame = Path()
      ..moveTo(x, 17)
      ..cubicTo(x + 7, 25, x + 5, 36, x, 36)
      ..cubicTo(x - 5, 36, x - 7, 25, x, 17)
      ..close();
    c.drawPath(flame, _fill(const Color(0xFFFFB300)));
    c.drawOval(
      Rect.fromCenter(center: Offset(x, 31), width: 5, height: 9),
      _fill(const Color(0xFFFFF3B0)),
    );
  }
}

// ------------------------------------------------------------ Año Nuevo Chino

void _chineseNewYear(Canvas c, bool dark) {
  const red = Color(0xFFE53935);
  const redDark = Color(0xFFB71C1C);
  // Luz de fondo: círculos concéntricos dorados.
  for (var i = 0; i < 4; i++) {
    c.drawCircle(
      const Offset(180, 72),
      70.0 - i * 14,
      _line(_gold, 1.4, opacity: 0.22 - i * 0.04),
    );
  }
  // Moneda dorada con el agujero cuadrado.
  c.drawCircle(const Offset(180, 72), 26, _fill(_goldDark));
  c.drawCircle(const Offset(180, 72), 23.5, _fill(_gold));
  c.drawCircle(const Offset(180, 72), 21, _line(_goldDark, 1.4));
  c.drawRect(
    Rect.fromCenter(center: const Offset(180, 72), width: 15, height: 15),
    _fill(const Color(0xFF8E0E14)),
  );
  c.drawRect(
    Rect.fromCenter(center: const Offset(180, 72), width: 15, height: 15),
    _line(_goldDark, 1.6),
  );
  // Faroles.
  void lantern(double cx, double top, double scale) {
    c.save();
    c.translate(cx, top);
    c.scale(scale);
    c.drawLine(const Offset(0, -20), const Offset(0, 8), _line(_gold, 1.6));
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(-9, 8, 9, 14),
        const Radius.circular(2),
      ),
      _fill(_gold),
    );
    const body = Rect.fromLTRB(-25, 12, 25, 56);
    c.drawOval(body, _fill(redDark));
    c.drawOval(body.deflate(1.5), _fill(red));
    c.drawOval(
      Rect.fromCenter(center: const Offset(-9, 28), width: 10, height: 18),
      _fill(_white, 0.14),
    );
    for (final w in const [0.0, 13.0, 22.0]) {
      c.drawOval(
        Rect.fromCenter(center: const Offset(0, 34), width: w * 2, height: 44),
        _line(_gold, 1.3, opacity: 0.85),
      );
    }
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(-10, 54, 10, 60),
        const Radius.circular(2),
      ),
      _fill(_gold),
    );
    for (final dx in const [-6.0, 0.0, 6.0]) {
      c.drawLine(Offset(dx, 60), Offset(dx, 76), _line(_gold, 1.8));
    }
    c.drawCircle(const Offset(0, 64), 2.5, _fill(_goldDark));
    c.restore();
  }

  lantern(76, 12, 1.0);
  lantern(284, 6, 1.05);
  lantern(330, 2, 0.62);
  lantern(32, 4, 0.58);
  // Chispas.
  for (final (x, y, r) in const [
    (130.0, 30.0, 6.0),
    (236.0, 34.0, 5.0),
    (146.0, 112.0, 4.0),
    (222.0, 110.0, 5.0),
    (182.0, 16.0, 4.0),
  ]) {
    _sparkle(c, Offset(x, y), r, _fill(_gold));
  }
}

// ---------------------------------------------------------------------- Boda

void _wedding(Canvas c, bool dark) {
  final gold = dark ? const Color(0xFFF1CF73) : const Color(0xFFB8892B);
  final goldHi = dark ? const Color(0xFFFFF0B0) : const Color(0xFFE6BB52);
  final soft = dark ? _white : _white;
  // Luces desenfocadas.
  for (final (x, y, r, o) in const [
    (40.0, 30.0, 22.0, 0.22),
    (96.0, 100.0, 16.0, 0.18),
    (308.0, 34.0, 26.0, 0.2),
    (330.0, 104.0, 14.0, 0.18),
    (250.0, 18.0, 10.0, 0.2),
  ]) {
    c.drawCircle(Offset(x, y), r, _fill(soft, o));
  }
  // Las dos alianzas entrelazadas.
  const left = Offset(160, 72);
  const right = Offset(204, 72);
  const radius = 32.0;
  c.drawCircle(left, radius, _line(gold, 9));
  c.drawCircle(left, radius, _line(goldHi, 3, opacity: 0.8));
  c.drawCircle(right, radius, _line(gold, 9));
  c.drawCircle(right, radius, _line(goldHi, 3, opacity: 0.8));
  // La izquierda pasa por encima de la derecha en el cruce de arriba.
  c.save();
  c.clipRect(
    Rect.fromCenter(center: const Offset(182, 44), width: 24, height: 22),
  );
  c.drawCircle(left, radius, _line(gold, 9));
  c.drawCircle(left, radius, _line(goldHi, 3, opacity: 0.8));
  c.restore();
  // Diamante sobre la derecha.
  const gem = Offset(204, 33);
  final diamond = Path()
    ..moveTo(gem.dx - 10, gem.dy)
    ..lineTo(gem.dx - 5, gem.dy - 8)
    ..lineTo(gem.dx + 5, gem.dy - 8)
    ..lineTo(gem.dx + 10, gem.dy)
    ..lineTo(gem.dx, gem.dy + 12)
    ..close();
  c.drawPath(diamond, _fill(const Color(0xFFD7F2FF)));
  c.drawPath(
    Path()
      ..moveTo(gem.dx - 10, gem.dy)
      ..lineTo(gem.dx + 10, gem.dy)
      ..moveTo(gem.dx - 5, gem.dy - 8)
      ..lineTo(gem.dx - 2, gem.dy)
      ..lineTo(gem.dx, gem.dy + 12)
      ..moveTo(gem.dx + 5, gem.dy - 8)
      ..lineTo(gem.dx + 2, gem.dy)
      ..lineTo(gem.dx, gem.dy + 12),
    _line(const Color(0xFF6BB5D9), 1),
  );
  c.drawPath(diamond, _line(gold, 1.6));
  // Destellos y corazones pequeños.
  for (final (x, y, r) in const [
    (110.0, 34.0, 7.0),
    (258.0, 44.0, 6.0),
    (122.0, 112.0, 5.0),
    (246.0, 112.0, 7.0),
    (60.0, 78.0, 5.0),
    (300.0, 74.0, 5.0),
  ]) {
    _sparkle(c, Offset(x, y), r, _fill(goldHi));
  }
  c.drawPath(
    _heartPath(const Offset(86, 56), 12),
    _fill(const Color(0xFFD98CA0), 0.9),
  );
  c.drawPath(
    _heartPath(const Offset(280, 100), 14),
    _fill(const Color(0xFFD98CA0), 0.9),
  );
}

// ---------------------------------------------------------------- Aniversario

void _anniversary(Canvas c, bool dark) {
  const glass = Color(0xFFFFF2D0);
  const wine = Color(0xFFF2C85B);
  // Fondo de luces.
  for (final (x, y, r, o) in const [
    (50.0, 30.0, 18.0, 0.12),
    (320.0, 36.0, 24.0, 0.12),
    (88.0, 104.0, 14.0, 0.1),
    (300.0, 100.0, 16.0, 0.1),
  ]) {
    c.drawCircle(Offset(x, y), r, _fill(_gold, o));
  }

  void flute(Offset base, double angle) {
    c.save();
    c.translate(base.dx, base.dy);
    c.rotate(angle);
    final bowl = Path()
      ..moveTo(-12, -96)
      ..lineTo(12, -96)
      ..cubicTo(12, -66, 6, -44, 0, -38)
      ..cubicTo(-6, -44, -12, -66, -12, -96)
      ..close();
    // Vino.
    c.save();
    c.clipPath(bowl);
    c.drawRect(const Rect.fromLTRB(-14, -78, 14, -36), _fill(wine, 0.95));
    c.restore();
    c.drawPath(bowl, _fill(glass, 0.22));
    c.drawPath(bowl, _line(glass, 2));
    c.drawLine(const Offset(0, -40), const Offset(0, -4), _line(glass, 2.6));
    c.drawOval(
      Rect.fromCenter(center: const Offset(0, -2), width: 30, height: 7),
      _fill(glass, 0.9),
    );
    // Burbujas.
    for (final (x, y, r) in const [
      (-3.0, -58.0, 1.8),
      (3.0, -66.0, 1.4),
      (-1.0, -72.0, 1.2),
      (2.0, -50.0, 1.2),
    ]) {
      c.drawCircle(Offset(x, y), r, _fill(_white, 0.85));
    }
    // Brillo.
    c.drawLine(
      const Offset(-8, -90),
      const Offset(-6, -66),
      _line(_white, 2, opacity: 0.7),
    );
    c.restore();
  }

  flute(const Offset(140, 126), 0.27);
  flute(const Offset(220, 126), -0.27);
  // El brindis.
  const clink = Offset(180, 40);
  for (var i = 0; i < 8; i++) {
    final a = i * math.pi / 4;
    final long = i.isEven ? 16.0 : 9.0;
    c.drawLine(
      clink + Offset(math.cos(a) * 5, math.sin(a) * 5),
      clink + Offset(math.cos(a) * long, math.sin(a) * long),
      _line(_gold, 2),
    );
  }
  for (final (x, y, r) in const [
    (110.0, 34.0, 7.0),
    (252.0, 28.0, 8.0),
    (96.0, 82.0, 5.0),
    (270.0, 80.0, 6.0),
    (180.0, 12.0, 5.0),
  ]) {
    _sparkle(c, Offset(x, y), r, _fill(_gold));
  }
  c.drawPath(
    _heartPath(const Offset(300, 56), 14),
    _fill(const Color(0xFFF3A6BC), 0.9),
  );
  c.drawPath(
    _heartPath(const Offset(62, 58), 12),
    _fill(const Color(0xFFF3A6BC), 0.9),
  );
}

// ------------------------------------------------------------------ Sant Jordi

void _santJordi(Canvas c, bool dark) {
  const red = Color(0xFFC62828);
  const redDark = Color(0xFF8E1B1B);
  final cord = Path()
    ..moveTo(-6, 8)
    ..quadraticBezierTo(180, 30, 366, 8);
  c.drawPath(cord, _line(redDark, 1.4));
  // Banderines rojos y amarillos.
  for (var i = 0; i < 12; i++) {
    final t = (i + 0.5) / 12;
    final p = _quad(
      const Offset(-6, 8),
      const Offset(180, 30),
      const Offset(366, 8),
      t,
    );
    final flag = Path()
      ..moveTo(p.dx - 9, p.dy)
      ..lineTo(p.dx + 9, p.dy)
      ..lineTo(p.dx, p.dy + 17)
      ..close();
    c.drawPath(flag, _fill(i.isEven ? red : const Color(0xFFFFF0B0)));
  }
  // Libro.
  c.save();
  c.translate(96, 84);
  c.rotate(-0.08);
  final cover = RRect.fromRectAndRadius(
    const Rect.fromLTRB(-58, -30, 58, 34),
    const Radius.circular(5),
  );
  c.drawRRect(
    cover.shift(const Offset(2, 4)),
    _fill(const Color(0xFF000000), 0.18),
  );
  c.drawRRect(cover, _fill(const Color(0xFF1F3A5F)));
  c.drawRect(
    const Rect.fromLTRB(-58, -30, -48, 34),
    _fill(const Color(0xFF14284A)),
  );
  c.drawRect(const Rect.fromLTRB(-30, -16, 40, -8), _fill(_gold));
  c.drawRect(const Rect.fromLTRB(-30, 0, 20, 5), _fill(_gold, 0.8));
  c.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(-58, 28, 58, 40),
      const Radius.circular(3),
    ),
    _fill(_cream),
  );
  c.drawLine(
    const Offset(-52, 33),
    const Offset(52, 33),
    _line(const Color(0xFFD9C9A3), 1.2),
  );
  c.drawLine(
    const Offset(-52, 37),
    const Offset(52, 37),
    _line(const Color(0xFFD9C9A3), 1.2),
  );
  c.restore();
  // Tallo y hojas.
  final stem = Path()
    ..moveTo(150, 116)
    ..cubicTo(196, 100, 224, 80, 252, 62);
  c.drawPath(stem, _line(const Color(0xFF2E7D4F), 4.5));
  for (final (x, y, a) in const [(188.0, 100.0, -0.2), (222.0, 82.0, 0.6)]) {
    c.save();
    c.translate(x, y);
    c.rotate(a);
    c.drawPath(
      Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(14, -22, 30, -6)
        ..quadraticBezierTo(14, 6, 0, 0)
        ..close(),
      _fill(const Color(0xFF3F9A5D)),
    );
    c.restore();
  }
  for (final (x, y, a) in const [(176.0, 108.0, 2.4), (206.0, 92.0, 2.5)]) {
    c.save();
    c.translate(x, y);
    c.rotate(a);
    c.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(4, -7)
        ..lineTo(8, 0)
        ..close(),
      _fill(const Color(0xFF1F5C3A)),
    );
    c.restore();
  }
  // La rosa.
  const bloom = Offset(258, 54);
  c.drawCircle(bloom, 24, _fill(redDark));
  c.drawCircle(bloom, 22, _fill(red));
  for (final (r, o) in const [(17.0, 0.0), (12.0, 1.6), (7.0, 3.2)]) {
    c.drawArc(
      Rect.fromCircle(center: bloom + Offset(o * 0.6, -o * 0.4), radius: r),
      0.6 + o,
      math.pi * 1.5,
      false,
      _line(redDark, 2.2),
    );
  }
  c.drawCircle(bloom + const Offset(1, -1), 3, _fill(redDark));
  c.drawArc(
    Rect.fromCircle(center: bloom, radius: 19),
    3.6,
    1.2,
    false,
    _line(const Color(0xFFFF8A80), 2.4),
  );
  // Pétalos y destellos.
  for (final (x, y, a) in const [
    (304.0, 100.0, 0.6),
    (324.0, 78.0, -0.4),
    (290.0, 116.0, 1.2),
  ]) {
    c.save();
    c.translate(x, y);
    c.rotate(a);
    c.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 9, height: 5),
      _fill(red, 0.9),
    );
    c.restore();
  }
  _sparkle(c, const Offset(316, 44), 6, _fill(_white, 0.9));
  _sparkle(c, const Offset(40, 36), 5, _fill(_white, 0.8));
}

// ----------------------------------------------------------------- San Valentín

void _valentine(Canvas c, bool dark) {
  // Corazones pequeños flotando.
  for (final (x, y, s, o) in const [
    (40.0, 40.0, 16.0, 0.55),
    (84.0, 96.0, 12.0, 0.45),
    (118.0, 28.0, 10.0, 0.5),
    (300.0, 30.0, 18.0, 0.55),
    (330.0, 90.0, 13.0, 0.5),
    (262.0, 110.0, 10.0, 0.45),
    (22.0, 98.0, 9.0, 0.45),
    (348.0, 50.0, 8.0, 0.45),
  ]) {
    c.drawPath(_heartPath(Offset(x, y), s), _fill(_white, o));
  }
  // El corazón grande con brillo.
  const center = Offset(180, 66);
  final heart = _heartPath(center, 92);
  c.drawPath(
    heart.shift(const Offset(2, 4)),
    _fill(const Color(0xFF000000), 0.16),
  );
  c.drawPath(heart, _fill(const Color(0xFFFFF1F5)));
  c.save();
  c.clipPath(heart);
  c.drawRect(
    const Rect.fromLTRB(180, 0, 280, 132),
    _fill(const Color(0xFFF8C7D9), 0.7),
  );
  c.restore();
  c.drawPath(
    Path()
      ..moveTo(146, 40)
      ..cubicTo(138, 44, 134, 52, 136, 62),
    _line(_white, 4),
  );
  // La flecha de Cupido.
  c.save();
  c.translate(180, 64);
  c.rotate(-0.42);
  c.drawLine(
    const Offset(-112, 0),
    const Offset(108, 0),
    _line(_goldDark, 3.6),
  );
  c.drawLine(const Offset(-112, 0), const Offset(108, 0), _line(_gold, 1.6));
  c.drawPath(
    Path()
      ..moveTo(122, 0)
      ..lineTo(104, -9)
      ..lineTo(104, 9)
      ..close(),
    _fill(const Color(0xFFFFF0B0)),
  );
  for (final dx in const [0.0, 10.0, 20.0]) {
    c.drawPath(
      Path()
        ..moveTo(-112 + dx, 0)
        ..lineTo(-122 + dx, -9)
        ..lineTo(-114 + dx, 0)
        ..lineTo(-122 + dx, 9)
        ..close(),
      _fill(_white, 0.95),
    );
  }
  c.restore();
  _sparkle(c, const Offset(246, 30), 7, _fill(_white, 0.9));
  _sparkle(c, const Offset(112, 112), 6, _fill(_white, 0.9));
}

// ----------------------------------------------------------------- Bautizo

void _baptism(Canvas c, bool dark) {
  final cloud = dark ? const Color(0xFFD7E8F7) : _white;
  // Nubes de fondo.
  void cloudShape(double cx, double cy, double s, double o) {
    final p = _fill(cloud, o);
    c.drawCircle(Offset(cx - 14 * s, cy), 11 * s, p);
    c.drawCircle(Offset(cx, cy - 7 * s), 14 * s, p);
    c.drawCircle(Offset(cx + 15 * s, cy), 11 * s, p);
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(cx - 25 * s, cy - 2 * s, cx + 26 * s, cy + 11 * s),
        Radius.circular(6 * s),
      ),
      p,
    );
  }

  cloudShape(52, 104, 1.1, dark ? 0.2 : 0.65);
  cloudShape(318, 96, 1.2, dark ? 0.2 : 0.65);
  cloudShape(250, 116, 0.7, dark ? 0.15 : 0.5);
  // Barra del móvil.
  c.drawLine(const Offset(180, 0), const Offset(180, 14), _line(_goldDark, 2));
  c.drawLine(
    const Offset(100, 14),
    const Offset(260, 14),
    _line(_goldDark, 3.4),
  );
  c.drawCircle(const Offset(180, 14), 5, _fill(_gold));
  // Colgantes.
  c.drawLine(
    const Offset(110, 14),
    const Offset(110, 48),
    _line(_goldDark, 1.4),
  );
  cloudShape(110, 62, 0.8, 1);
  c.drawLine(
    const Offset(180, 14),
    const Offset(180, 70),
    _line(_goldDark, 1.4),
  );
  // Luna creciente.
  const moonC = Offset(180, 90);
  final moon = Path.combine(
    PathOperation.difference,
    Path()..addOval(Rect.fromCircle(center: moonC, radius: 22)),
    Path()..addOval(
      Rect.fromCircle(center: moonC + const Offset(11, -6), radius: 19),
    ),
  );
  c.drawPath(moon, _fill(_gold));
  c.drawPath(moon, _line(_goldDark, 1.4));
  c.drawLine(
    const Offset(250, 14),
    const Offset(250, 52),
    _line(_goldDark, 1.4),
  );
  final star = _star5Path(const Offset(250, 68), 17, inner: 0.5);
  c.drawPath(star, _fill(_gold));
  c.drawPath(star, _line(_goldDark, 1.4));
  // Destellos.
  for (final (x, y, r) in const [
    (60.0, 36.0, 6.0),
    (312.0, 40.0, 7.0),
    (140.0, 108.0, 4.0),
    (222.0, 100.0, 4.0),
    (30.0, 70.0, 4.0),
    (340.0, 70.0, 4.0),
  ]) {
    _sparkle(c, Offset(x, y), r, _fill(dark ? _cream : _white, 0.95));
  }
}

// ----------------------------------------------------------------- Comunión

void _communion(Canvas c, bool dark) {
  // Rayos de luz.
  const origin = Offset(180, 44);
  for (var i = 0; i < 14; i++) {
    final a = -math.pi + i * math.pi / 13 + 0.05;
    final w = 0.07;
    c.drawPath(
      Path()
        ..moveTo(origin.dx, origin.dy)
        ..lineTo(
          origin.dx + math.cos(a - w) * 170,
          origin.dy + math.sin(a - w) * 170,
        )
        ..lineTo(
          origin.dx + math.cos(a + w) * 170,
          origin.dy + math.sin(a + w) * 170,
        )
        ..close(),
      _fill(_white, i.isEven ? (dark ? 0.1 : 0.28) : 0.0),
    );
  }
  // Hostia con cruz.
  c.drawCircle(origin, 22, _fill(_gold, 0.25));
  c.drawCircle(origin, 15, _fill(_cream));
  c.drawCircle(origin, 15, _line(_goldDark, 1.4));
  c.drawLine(
    origin + const Offset(0, -8),
    origin + const Offset(0, 8),
    _line(_goldDark, 2),
  );
  c.drawLine(
    origin + const Offset(-6, -2),
    origin + const Offset(6, -2),
    _line(_goldDark, 2),
  );
  // Cáliz.
  final cup = Path()
    ..moveTo(150, 62)
    ..lineTo(210, 62)
    ..cubicTo(210, 86, 198, 96, 180, 98)
    ..cubicTo(162, 96, 150, 86, 150, 62)
    ..close();
  c.drawPath(
    cup.shift(const Offset(2, 3)),
    _fill(const Color(0xFF000000), 0.14),
  );
  c.drawPath(cup, _fill(_gold));
  c.drawPath(
    Path()
      ..moveTo(156, 66)
      ..cubicTo(157, 82, 164, 90, 172, 93),
    _line(const Color(0xFFFFE9A0), 3.4),
  );
  c.drawRect(const Rect.fromLTRB(148, 60, 212, 66), _fill(_goldDark));
  c.drawRect(const Rect.fromLTRB(176, 96, 184, 112), _fill(_goldDark));
  c.drawOval(
    Rect.fromCenter(center: const Offset(180, 104), width: 24, height: 12),
    _fill(_gold),
  );
  c.drawOval(
    Rect.fromCenter(center: const Offset(180, 104), width: 24, height: 12),
    _line(_goldDeep, 1.2),
  );
  final base = RRect.fromRectAndRadius(
    const Rect.fromLTRB(154, 112, 206, 122),
    const Radius.circular(5),
  );
  c.drawRRect(base, _fill(_gold));
  c.drawRRect(base, _line(_goldDeep, 1.2));
  c.drawCircle(const Offset(180, 80), 4, _fill(const Color(0xFFE53935)));
  // Ramas de trigo.
  for (final side in const [-1.0, 1.0]) {
    final x = 180 + side * 96;
    c.drawLine(Offset(x, 124), Offset(x + side * 8, 54), _line(_goldDark, 2));
    for (var i = 0; i < 5; i++) {
      final y = 54.0 + i * 9;
      final cx = x + side * (8 - i * 1.1);
      for (final s in const [-1.0, 1.0]) {
        c.save();
        c.translate(cx, y);
        c.rotate(s * 0.7);
        c.drawOval(
          Rect.fromCenter(center: const Offset(0, -4), width: 5, height: 11),
          _fill(_gold),
        );
        c.restore();
      }
    }
  }
  for (final (x, y, r) in const [
    (50.0, 40.0, 6.0),
    (310.0, 36.0, 6.0),
    (104.0, 100.0, 4.0),
    (258.0, 104.0, 4.0),
    (40.0, 100.0, 4.0),
  ]) {
    _sparkle(c, Offset(x, y), r, _fill(_white, 0.95));
  }
}

// ----------------------------------------------------------------- Graduación

void _graduation(Canvas c, bool dark) {
  // Confeti dorado.
  for (final (x, y, a) in const [
    (24.0, 26.0, 0.4),
    (60.0, 106.0, 1.0),
    (100.0, 18.0, 2.0),
    (310.0, 24.0, 0.8),
    (340.0, 70.0, 1.9),
    (290.0, 114.0, 0.2),
    (230.0, 20.0, 1.4),
    (18.0, 70.0, 2.4),
  ]) {
    c.save();
    c.translate(x, y);
    c.rotate(a);
    c.drawRect(const Rect.fromLTWH(-5, -2, 10, 4), _fill(_gold));
    c.restore();
  }
  _sparkle(c, const Offset(128, 22), 6, _fill(_cream));
  _sparkle(c, const Offset(266, 100), 6, _fill(_cream));
  _sparkle(c, const Offset(330, 38), 5, _fill(_cream));

  // Birrete.
  const ink = Color(0xFF14172B);
  const inkHi = Color(0xFF2A2F52);
  final skull = Path()
    ..moveTo(110, 66)
    ..lineTo(110, 92)
    ..quadraticBezierTo(150, 112, 190, 92)
    ..lineTo(190, 66)
    ..close();
  c.drawPath(skull, _fill(ink));
  final board = Path()
    ..moveTo(150, 24)
    ..lineTo(232, 52)
    ..lineTo(150, 80)
    ..lineTo(68, 52)
    ..close();
  c.drawPath(
    board.shift(const Offset(0, 4)),
    _fill(const Color(0xFF000000), 0.2),
  );
  c.drawPath(board, _fill(inkHi));
  c.drawPath(
    Path()
      ..moveTo(150, 24)
      ..lineTo(232, 52)
      ..lineTo(150, 52)
      ..close(),
    _fill(ink, 0.7),
  );
  c.drawPath(board, _line(ink, 1.4));
  // Borla.
  c.drawCircle(const Offset(150, 52), 5, _fill(_gold));
  final cord = Path()
    ..moveTo(150, 52)
    ..quadraticBezierTo(210, 50, 222, 70)
    ..lineTo(222, 92);
  c.drawPath(cord, _line(_goldDark, 2.6));
  c.drawPath(cord, _line(_gold, 1.2));
  c.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(217, 88, 227, 98),
      const Radius.circular(2),
    ),
    _fill(_gold),
  );
  for (final dx in const [-4.0, -1.5, 1.5, 4.0]) {
    c.drawLine(
      Offset(222 + dx, 98),
      Offset(222 + dx * 1.4, 112),
      _line(_gold, 1.6),
    );
  }
  // Diploma.
  c.save();
  c.translate(290, 92);
  c.rotate(-0.35);
  final roll = RRect.fromRectAndRadius(
    const Rect.fromLTRB(-34, -11, 34, 11),
    const Radius.circular(11),
  );
  c.drawRRect(
    roll.shift(const Offset(1, 3)),
    _fill(const Color(0xFF000000), 0.2),
  );
  c.drawRRect(roll, _fill(_cream));
  c.drawOval(
    Rect.fromCenter(center: const Offset(-30, 0), width: 14, height: 22),
    _fill(const Color(0xFFE3D3A8)),
  );
  c.drawOval(
    Rect.fromCenter(center: const Offset(-30, 0), width: 7, height: 12),
    _line(const Color(0xFFB8A57A), 1.2),
  );
  c.drawRect(
    const Rect.fromLTRB(-4, -11, 8, 11),
    _fill(const Color(0xFFD32F2F)),
  );
  c.drawPath(
    Path()
      ..moveTo(0, 10)
      ..lineTo(-5, 22)
      ..lineTo(0, 18)
      ..lineTo(5, 22)
      ..close(),
    _fill(const Color(0xFFD32F2F)),
  );
  c.restore();
}

// ------------------------------------------------------------- Otra (icono)

void _custom(Canvas c, OccasionTheme theme, bool dark) {
  final p = theme.palette;
  final strong = dark ? p.tintaD : p.tinta;
  final soft = dark ? p.pastelD : p.pastelD;
  // Círculos suaves de fondo.
  for (final (x, y, r, o) in const [
    (60.0, 40.0, 40.0, 0.18),
    (96.0, 100.0, 24.0, 0.14),
    (300.0, 36.0, 34.0, 0.16),
    (330.0, 104.0, 22.0, 0.14),
    (240.0, 112.0, 14.0, 0.14),
    (130.0, 20.0, 12.0, 0.14),
  ]) {
    c.drawCircle(Offset(x, y), r, _fill(soft, dark ? o : o + 0.1));
  }
  _sparkle(c, const Offset(120, 40), 7, _fill(strong, 0.7));
  _sparkle(c, const Offset(250, 90), 6, _fill(strong, 0.7));
  _sparkle(c, const Offset(266, 34), 4, _fill(strong, 0.7));
  // Disco central con el icono.
  const center = Offset(180, 66);
  c.drawCircle(center, 46, _fill(soft, dark ? 0.2 : 0.45));
  c.drawCircle(center, 36, _fill(strong, dark ? 0.9 : 0.95));
  final icon = theme.icon;
  if (icon != null) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: 44,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: dark ? p.onFill : _white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }
}
