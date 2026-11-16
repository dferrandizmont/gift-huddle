import 'dart:ui';

import 'stroke_icon.dart';

/// Convierte datos de trazo SVG (el atributo `d`) en un [Path].
///
/// Admite lo que usan los iconos de Tabler: `M L H V C S Q T A Z`, en
/// mayúscula (absoluto) y minúscula (relativo). Sin dependencias: así no hace
/// falta `flutter_svg` para dibujar unos cuantos iconos de trazo.
Path parseSvgPath(String d) {
  final path = Path();
  final r = _Reader(d);
  var x = 0.0, y = 0.0; // punto actual
  var sx = 0.0, sy = 0.0; // inicio del subtrazado
  double? cx, cy; // último control de una cúbica (para S)
  double? qx, qy; // último control de una cuadrática (para T)
  String cmd = '';
  while (true) {
    r.skipSeparators();
    if (r.done) {
      break;
    }
    if (r.atCommand) {
      cmd = r.takeCommand();
    } else if (cmd.isEmpty) {
      throw FormatException('Datos de trazo mal formados', d);
    } else if (cmd == 'M') {
      cmd = 'L';
    } else if (cmd == 'm') {
      cmd = 'l';
    }
    final rel = cmd == cmd.toLowerCase();
    final ox = rel ? x : 0.0;
    final oy = rel ? y : 0.0;
    switch (cmd.toUpperCase()) {
      case 'M':
        x = ox + r.number();
        y = oy + r.number();
        sx = x;
        sy = y;
        path.moveTo(x, y);
        cx = cy = qx = qy = null;
      case 'L':
        x = ox + r.number();
        y = oy + r.number();
        path.lineTo(x, y);
        cx = cy = qx = qy = null;
      case 'H':
        x = ox + r.number();
        path.lineTo(x, y);
        cx = cy = qx = qy = null;
      case 'V':
        y = oy + r.number();
        path.lineTo(x, y);
        cx = cy = qx = qy = null;
      case 'C':
        final x1 = ox + r.number(), y1 = oy + r.number();
        final x2 = ox + r.number(), y2 = oy + r.number();
        x = ox + r.number();
        y = oy + r.number();
        path.cubicTo(x1, y1, x2, y2, x, y);
        cx = x2;
        cy = y2;
        qx = qy = null;
      case 'S':
        final (x1, y1) = (cx != null && cy != null)
            ? (2 * x - cx, 2 * y - cy)
            : (x, y);
        final x2 = ox + r.number(), y2 = oy + r.number();
        x = ox + r.number();
        y = oy + r.number();
        path.cubicTo(x1, y1, x2, y2, x, y);
        cx = x2;
        cy = y2;
        qx = qy = null;
      case 'Q':
        final x1 = ox + r.number(), y1 = oy + r.number();
        x = ox + r.number();
        y = oy + r.number();
        path.quadraticBezierTo(x1, y1, x, y);
        qx = x1;
        qy = y1;
        cx = cy = null;
      case 'T':
        final (x1, y1) = (qx != null && qy != null)
            ? (2 * x - qx, 2 * y - qy)
            : (x, y);
        x = ox + r.number();
        y = oy + r.number();
        path.quadraticBezierTo(x1, y1, x, y);
        qx = x1;
        qy = y1;
        cx = cy = null;
      case 'A':
        final rx = r.number(), ry = r.number();
        final rotation = r.number();
        final large = r.flag();
        final sweep = r.flag();
        x = ox + r.number();
        y = oy + r.number();
        if (rx == 0 || ry == 0) {
          path.lineTo(x, y);
        } else {
          path.arcToPoint(
            Offset(x, y),
            radius: Radius.elliptical(rx.abs(), ry.abs()),
            rotation: rotation,
            largeArc: large,
            clockwise: sweep,
          );
        }
        cx = cy = qx = qy = null;
      case 'Z':
        path.close();
        x = sx;
        y = sy;
        cx = cy = qx = qy = null;
      default:
        throw FormatException('Comando de trazo no admitido: $cmd', d);
    }
  }
  return path;
}

/// Un icono de trazo (rejilla de 24) hecho con uno o varios trazos SVG.
StrokeIconBuilder svgIcon(List<String> paths) {
  Path? cached;
  return (target) {
    cached ??= () {
      final p = Path();
      for (final d in paths) {
        p.addPath(parseSvgPath(d), Offset.zero);
      }
      return p;
    }();
    target.addPath(cached!, Offset.zero);
  };
}

class _Reader {
  _Reader(this.s);

  final String s;
  int i = 0;

  static final _number = RegExp(r'[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?');

  bool get done => i >= s.length;

  void skipSeparators() {
    while (i < s.length &&
        (s[i] == ' ' ||
            s[i] == ',' ||
            s[i] == '\n' ||
            s[i] == '\t' ||
            s[i] == '\r')) {
      i++;
    }
  }

  bool get atCommand => RegExp('[A-Za-z]').hasMatch(s[i]);

  String takeCommand() => s[i++];

  double number() {
    skipSeparators();
    final m = _number.matchAsPrefix(s, i);
    if (m == null) {
      throw FormatException('Se esperaba un número', s, i);
    }
    i = m.end;
    return double.parse(m.group(0)!);
  }

  /// Un indicador de arco: un solo 0 o 1, que puede ir pegado al siguiente.
  bool flag() {
    skipSeparators();
    final c = s[i++];
    if (c != '0' && c != '1') {
      throw FormatException('Se esperaba un indicador 0 o 1', s, i - 1);
    }
    return c == '1';
  }
}
