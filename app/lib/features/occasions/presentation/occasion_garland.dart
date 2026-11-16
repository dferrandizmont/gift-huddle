import 'package:flutter/material.dart';

import '../../../core/theme/occasion_theme.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../core/widgets/tabler_icons.dart';

/// Los tres motivos de la guirnalda de una ocasión.
enum GarlandMotif {
  /// Cumpleaños: regalo, pastel y globo.
  birthday,

  /// Navidad (Papá Noel y Tió): copo, abeto y reno.
  christmas,

  /// Reyes: corona, estrella y pieza de rey.
  kings;

  /// Los tres iconos de Tabler, de izquierda a derecha.
  List<StrokeIconBuilder> get icons => switch (this) {
    GarlandMotif.birthday => [tablerGift, tablerCake, tablerBalloon],
    GarlandMotif.christmas => [
      tablerSnowflake,
      tablerChristmasTree,
      tablerDeer,
    ],
    GarlandMotif.kings => [tablerCrown, tablerStar, tablerChessKing],
  };

  /// El icono de la tarjeta de cuenta atrás: el abeto de Navidad, la corona de
  /// Reyes y el pastel de los cumpleaños.
  StrokeIconBuilder get cardIcon => switch (this) {
    GarlandMotif.birthday => tablerCake,
    GarlandMotif.christmas => tablerChristmasTree,
    GarlandMotif.kings => tablerCrown,
  };

  /// El motivo de un tema de ocasión, o `null` si no tiene guirnalda (el
  /// resto de celebraciones siguen con su filete).
  static GarlandMotif? forTheme(OccasionTheme? theme) => switch (theme?.id) {
    'birthday' => GarlandMotif.birthday,
    'christmas' || 'tio' => GarlandMotif.christmas,
    'kings' => GarlandMotif.kings,
    _ => null,
  };
}

/// Guirnalda espaciada de una ocasión: una línea que se desvanece por los
/// extremos, dos rombos y tres iconos de Tabler sobre la tinta de la
/// ocasión (línea al 50 %, iconos al 62 %).
///
/// Es decorativa. [height] y [iconSize] son 28 y 22 en la cabecera del detalle
/// y 24 y 18 en la lista. [background] es el color de la superficie sobre la
/// que se pinta: tapa la línea detrás de cada icono.
///
/// Con [draw] las piezas se dibujan una tras otra (§3.4 de
/// la guía de movimiento): ver [GarlandPieces].
class OccasionGarland extends StatelessWidget {
  const OccasionGarland({
    super.key,
    required this.motif,
    required this.color,
    required this.background,
    this.height = 28,
    this.iconSize = 22,
    this.draw,
  });

  final GarlandMotif motif;
  final Color color;
  final Color background;
  final double height;
  final double iconSize;

  /// El avance (0 a 1) del dibujo de las piezas, o `null` si se pinta entera.
  final Animation<double>? draw;

  /// Para la cabecera del detalle: tinta del tema sobre el fondo de pantalla.
  static Widget header(
    BuildContext context,
    GarlandMotif motif,
    RegalosTokens tokens,
  ) => OccasionGarland(motif: motif, color: tokens.ink, background: tokens.bg);

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _GarlandPainter(
            motif: motif,
            color: color,
            background: background,
            iconSize: iconSize,
            draw: draw,
          ),
        ),
      ),
    );
  }
}

/// Las seis piezas de la guirnalda en el orden en que se dibujan: la línea,
/// el primer icono, el primer rombo, el segundo icono, el segundo rombo y el
/// tercer icono.
///
/// Cada pieza se dibuja en [duration] con `flight` ([RegalosCurves.flight]) y
/// la siguiente empieza [stagger] después. Los trazos se recorren con
/// `PathMetric.extractPath`; los rombos, que son rellenos, aparecen creciendo
/// desde su centro.
abstract final class GarlandPieces {
  /// Cuántas piezas hay.
  static const int count = 6;

  /// Lo que tarda en dibujarse cada una.
  static const Duration duration = Duration(milliseconds: 600);

  /// Desfase entre una pieza y la siguiente.
  static const Duration stagger = Duration(milliseconds: 40);

  /// Lo que tarda en dibujarse la guirnalda entera.
  static Duration get total => stagger * (count - 1) + duration;

  /// El avance (0 a 1) de la pieza [piece] cuando han pasado [elapsed].
  static double progress(int piece, Duration elapsed) {
    final local =
        (elapsed - stagger * piece).inMicroseconds / duration.inMicroseconds;
    return RegalosCurves.flight.transform(local.clamp(0.0, 1.0));
  }
}

/// La guirnalda del detalle de una ocasión, que **se dibuja** la primera vez
/// que se ve en una visita (§3.4): [delay] después de crearse (a los ~205 ms,
/// el 55 % de la ruta que hace crecer el detalle) empieza el dibujo de las
/// piezas. No se repite al reconstruir. Con «Reducir movimiento» aparece
/// entera.
class DrawnGarland extends StatefulWidget {
  /// Crea la guirnalda.
  const DrawnGarland({
    super.key,
    required this.motif,
    required this.tokens,
    this.delay = const Duration(milliseconds: 205),
  });

  /// Los iconos.
  final GarlandMotif motif;

  /// Los colores del tema de la ocasión.
  final RegalosTokens tokens;

  /// Cuánto espera antes de empezar a dibujarse.
  final Duration delay;

  @override
  State<DrawnGarland> createState() => _DrawnGarlandState();
}

class _DrawnGarlandState extends State<DrawnGarland>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.delay + GarlandPieces.total,
    animationBehavior: AnimationBehavior.preserve,
  );
  // El avance que ve el pintor: lo que queda tras el retardo.
  late final Animation<double> _drawn = _DelayedAnimation(
    _controller,
    widget.delay,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;
    if (RegalosMotion.of(context).reduce) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.isCompleted) {
      return OccasionGarland.header(context, widget.motif, widget.tokens);
    }
    return OccasionGarland(
      motif: widget.motif,
      color: widget.tokens.ink,
      background: widget.tokens.bg,
      draw: _drawn,
    );
  }
}

/// El avance de [parent] contado desde que pasó [delay] (0 hasta entonces y
/// luego de 0 a 1 en lo que queda), con el tiempo total de [GarlandPieces].
class _DelayedAnimation extends Animation<double>
    with AnimationWithParentMixin<double> {
  _DelayedAnimation(this.parent, this.delay);

  @override
  final AnimationController parent;
  final Duration delay;

  @override
  double get value {
    final total = parent.duration!.inMicroseconds;
    final elapsed = parent.value * total - delay.inMicroseconds;
    return (elapsed / GarlandPieces.total.inMicroseconds).clamp(0.0, 1.0);
  }
}

class _GarlandPainter extends CustomPainter {
  _GarlandPainter({
    required this.motif,
    required this.color,
    required this.background,
    required this.iconSize,
    this.draw,
  }) : super(repaint: draw);

  final GarlandMotif motif;
  final Color color;
  final Color background;
  final double iconSize;
  final Animation<double>? draw;

  static const _xs = [0.2, 0.5, 0.8];

  /// El alfa de la línea y los rombos, y el de los iconos.
  static const double _lineAlpha = 0.5;
  static const double _iconAlpha = 0x9E / 255;

  /// El avance de cada pieza: la línea, icono 0, rombo 0, icono 1, rombo 1,
  /// icono 2.
  @visibleForTesting
  List<double> pieces() {
    final animation = draw;
    if (animation == null) {
      return List<double>.filled(GarlandPieces.count, 1);
    }
    final elapsed = Duration(
      microseconds: (animation.value * GarlandPieces.total.inMicroseconds)
          .round(),
    );
    return [
      for (var i = 0; i < GarlandPieces.count; i++)
        GarlandPieces.progress(i, elapsed),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final cy = size.height / 2;
    final k = iconSize / 22;
    final xs = [for (final f in _xs) f * w];
    final icons = motif.icons;
    final progress = pieces();
    final lineT = progress[0];
    final iconT = [progress[1], progress[3], progress[5]];
    final diamondT = [progress[2], progress[4]];

    // Sin `saveLayer`: el alfa va en el color de cada trazo (una capa fuera de
    // pantalla por guirnalda y por fotograma cuesta, y hay una guirnalda en
    // cada fila de ocasión). Línea y rombos, al 50 %.
    final lineColor = color.withValues(alpha: color.a * _lineAlpha);
    final r = 2.4 * k;
    final centers = [(xs[0] + xs[1]) / 2, (xs[1] + xs[2]) / 2];
    final diamonds = Path();
    for (var i = 0; i < centers.length; i++) {
      final x = centers[i];
      final s = diamondT[i];
      if (s <= 0) {
        continue;
      }
      diamonds
        ..moveTo(x, cy - r * s)
        ..lineTo(x + r * s, cy)
        ..lineTo(x, cy + r * s)
        ..lineTo(x - r * s, cy)
        ..close();
    }
    if (lineT > 0) {
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = k
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          colors: [
            lineColor.withValues(alpha: 0),
            lineColor,
            lineColor,
            lineColor.withValues(alpha: 0),
          ],
          stops: const [0, 0.14, 0.86, 1],
        ).createShader(Offset.zero & size);
      // Donde hay un rombo la línea no pasa: sumar los dos al 50 % la
      // oscurecería, y lo que hacía la capa era pintarlos como una sola forma.
      canvas
        ..save()
        ..clipPath(
          Path.combine(
            PathOperation.difference,
            Path()..addRect(Offset.zero & size),
            diamonds,
          ),
        )
        ..drawLine(Offset(0, cy), Offset(w * lineT, cy), line)
        ..restore();
    }
    canvas.drawPath(diamonds, Paint()..color = lineColor);

    // Un hueco redondo detrás de cada icono para que la línea no lo cruce.
    final knock = Paint()..color = background;
    for (var i = 0; i < xs.length; i++) {
      if (iconT[i] > 0) {
        canvas.drawCircle(Offset(xs[i], cy), iconSize * 0.62, knock);
      }
    }

    // Iconos, al 62 %, con trazo de 1,5 sobre la rejilla de 24. Cada icono es
    // un solo trazo y no se solapa con otro: el alfa en el color da lo mismo.
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: color.a * _iconAlpha);
    for (var i = 0; i < icons.length && i < xs.length; i++) {
      final t = iconT[i];
      if (t <= 0) {
        continue;
      }
      final path = Path();
      icons[i](path);
      canvas
        ..save()
        ..translate(xs[i] - iconSize / 2, cy - iconSize / 2)
        ..scale(iconSize / 24)
        ..drawPath(t >= 1 ? path : _partial(path, t), stroke)
        ..restore();
    }
  }

  /// El tramo de [path] hasta la fracción [t] de cada uno de sus trazos.
  static Path _partial(Path path, double t) {
    final out = Path();
    for (final metric in path.computeMetrics()) {
      out.addPath(metric.extractPath(0, metric.length * t), Offset.zero);
    }
    return out;
  }

  @override
  bool shouldRepaint(_GarlandPainter old) =>
      old.color != color ||
      old.background != background ||
      old.iconSize != iconSize ||
      old.motif != motif ||
      old.draw != draw;
}
