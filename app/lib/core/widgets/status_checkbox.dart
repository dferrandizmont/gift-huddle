import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../motion/animated_status_glyph.dart';
import '../motion/haptics.dart';
import '../theme/gift_status.dart';
import '../theme/regalos_tokens.dart';
import 'gift_status_l10n.dart';
import 'stroke_icon.dart';

/// Casilla redonda de estado (solo el dibujo, sin zona táctil).
///
/// Seis formas, de las maquetas «Tareas»: idea (círculo discontinuo gris),
/// decidido (anillo), comprado (¼), llegó (½), envuelto (¾) y entregado
/// (círculo lleno con visto). El estado nunca se indica solo con color: lo que
/// cambia es la forma.
class StatusGlyph extends StatelessWidget {
  const StatusGlyph({
    super.key,
    required this.status,
    this.size = 24,
    this.stroke,
  });

  final GiftStatus status;
  final double size;

  /// Color del trazo; por defecto el del estado. Sobre un relleno del acento
  /// (un chip o una celda elegidos) se pasa el color del texto: el trazo de
  /// serie apenas se distingue ahí en oscuro.
  final Color? stroke;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: StatusGlyphPainter(
          status: status,
          stroke: stroke ?? t.statusStroke(status),
          fill: t.statusFill(status),
        ),
      ),
    );
  }
}

/// Pintor de la casilla; la rejilla es la del SVG de las maquetas (22 x 22).
///
/// Sin los parámetros de animación pinta el estado en reposo. [AnimatedStatusGlyph]
/// los pasa para ir de un estado al siguiente:
/// - [sweep]: fracción del sector (0 a 1), desde las 12 en sentido del reloj.
/// - [solid]: 0 es el anillo discontinuo de «idea»; 1, el anillo continuo.
/// - [grow]: 0 a 1, el círculo lleno de «entregado» crece desde el centro.
/// - [check]: 0 a 1, cuánto del visto está dibujado.
class StatusGlyphPainter extends CustomPainter {
  const StatusGlyphPainter({
    required this.status,
    required this.stroke,
    required this.fill,
    this.sweep,
    this.solid,
    this.grow,
    this.check,
  });

  final GiftStatus status;
  final Color stroke;
  final Color fill;
  final double? sweep;
  final double? solid;
  final double? grow;
  final double? check;

  static const double _grid = 22;
  static const Offset _c = Offset(11, 11);

  double get _sweep => sweep ?? status.fill;
  double get _solid => solid ?? (status == GiftStatus.idea ? 0 : 1);
  double get _grow => grow ?? (status == GiftStatus.delivered ? 1 : 0);
  double get _check => check ?? (status == GiftStatus.delivered ? 1 : 0);

  static Path _checkPath() => Path()
    ..moveTo(6.8, 11.4)
    ..relativeLineTo(3, 3)
    ..relativeLineTo(5.6, -6);

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / _grid);

    final grow = _grow.clamp(0.0, 1.2);
    final solid = _solid.clamp(0.0, 1.0);
    final ringRadius = grow > 0 ? 9.6 : 9.5;

    if (grow > 0) {
      canvas.drawCircle(_c, 9.6 * grow, Paint()..color = fill);
    }

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..color = stroke
      ..strokeWidth = 1.6;
    if (solid < 1) {
      paintDashedCircle(
        canvas,
        center: _c,
        radius: 9.5,
        paint: Paint()
          ..style = PaintingStyle.stroke
          ..color = stroke.withValues(alpha: stroke.a * (1 - solid))
          ..strokeWidth = 1.6,
        dash: 3,
        gap: 3,
      );
    }
    if (solid > 0) {
      canvas.drawCircle(
        _c,
        ringRadius,
        ring..color = stroke.withValues(alpha: stroke.a * solid),
      );
    }

    // El sector se va tapando con el círculo lleno cuando se entrega.
    final wedgeAlpha = (1 - grow).clamp(0.0, 1.0);
    if (_sweep > 0.004 && wedgeAlpha > 0) {
      _paintWedge(canvas, _sweep.clamp(0.0, 1.0), wedgeAlpha);
    }

    final check = _check.clamp(0.0, 1.0);
    if (check > 0) {
      final path = _checkPath();
      final drawn = Path();
      for (final metric in path.computeMetrics()) {
        drawn.addPath(
          metric.extractPath(0, metric.length * check),
          Offset.zero,
        );
      }
      canvas.drawPath(
        drawn,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    canvas.restore();
  }

  /// Sector que arranca a las 12 y avanza en el sentido del reloj.
  void _paintWedge(Canvas canvas, double fraction, double alpha) {
    const r = 6.5;
    final path = Path()
      ..moveTo(_c.dx, _c.dy)
      ..lineTo(_c.dx, _c.dy - r)
      ..arcTo(
        Rect.fromCircle(center: _c, radius: r),
        -math.pi / 2,
        2 * math.pi * fraction,
        false,
      )
      ..close();
    canvas
      ..drawPath(path, Paint()..color = fill.withValues(alpha: fill.a * alpha))
      ..drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = stroke.withValues(alpha: stroke.a * alpha)
          ..strokeWidth = 1.2
          ..strokeJoin = StrokeJoin.round,
      );
  }

  @override
  bool shouldRepaint(StatusGlyphPainter old) =>
      old.status != status ||
      old.stroke != stroke ||
      old.fill != fill ||
      old.sweep != sweep ||
      old.solid != solid ||
      old.grow != grow ||
      old.check != check;
}

/// Lo que hay que mantener pulsada la casilla para abrir el selector. Menos que
/// los 500 ms de Flutter y que los 400 ms de Android: una pulsación larga a la
/// manera del sistema no debe quedarse en un toque que avanza el estado.
const Duration kStatusLongPress = Duration(milliseconds: 350);

/// Casilla de estado tocable: botón de 44 x 44 con el estado en voz alta.
///
/// [itemName] es el nombre del regalo, para la etiqueta accesible «Cambiar
/// estado de X. Estado actual: Y». Sin [onTap] solo muestra el estado.
class StatusCheckbox extends StatelessWidget {
  const StatusCheckbox({
    super.key,
    required this.status,
    required this.itemName,
    this.onTap,
    this.onLongPress,
  });

  final GiftStatus status;
  final String itemName;
  final VoidCallback? onTap;

  /// Pulsación larga: abre el selector de los seis estados.
  final VoidCallback? onLongPress;

  static const double target = 44;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final statusName = status.label(l10n);
    final interactive = onTap != null;
    final label = interactive
        ? l10n.statusCheckboxLabel(itemName, statusName)
        : l10n.statusReadOnlyLabel(statusName);

    return Semantics(
      container: true,
      button: interactive,
      label: label,
      onTap: onTap,
      onLongPress: onLongPress,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: target,
        child: LongPressAfter(
          duration: kStatusLongPress,
          onLongPress: onLongPress,
          child: InkResponse(
            onTap: onTap,
            customBorder: const CircleBorder(),
            radius: target / 2,
            child: Center(child: AnimatedStatusGlyph(status: status)),
          ),
        ),
      ),
    );
  }
}

/// Pulsación larga con su propio tiempo. Compite en la arena con el toque del
/// hijo: si se suelta antes es un toque; si se mantiene, gana esta y el toque
/// se cancela.
class LongPressAfter extends StatelessWidget {
  const LongPressAfter({
    super.key,
    required this.duration,
    required this.onLongPress,
    required this.child,
  });

  final Duration duration;
  final VoidCallback? onLongPress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final callback = onLongPress;
    if (callback == null) {
      return child;
    }
    return RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory>{
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(duration: duration),
              (recognizer) => recognizer.onLongPress = () {
                context.haptics.selection();
                callback();
              },
            ),
      },
      child: child,
    );
  }
}
