import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_typography.dart';
import '../theme/occasion_theme.dart';
import '../theme/regalos_shape.dart';
import '../theme/regalos_tokens.dart';

/// Lo que la tarjeta de cuenta atrás del detalle de una ocasión comparte con
/// la ruta que la hace crecer desde la tarjeta del carrusel (§3.1 y «momento
/// K» de la guía de movimiento).
///
/// - Las claves permiten medir el rectángulo de la tarjeta y el del número.
/// - Mientras [hidden] vale `true` la tarjeta no pinta su superficie ni su
///   número (los pinta el vuelo) y los textos de al lado aún no se ven.
/// - Los textos se funden y suben de 6 a 0 px con el avance de [progress]
///   (opacidad en `Interval(0.5, 0.9)` y traslación en `Interval(0.45, 0.95)`).
class CountdownFlight {
  /// Crea el vuelo.
  CountdownFlight({required this.hidden, required this.progress});

  /// La superficie de la tarjeta.
  final GlobalKey cardKey = GlobalKey(debugLabel: 'countdown-card');

  /// El número de la tarjeta.
  final GlobalKey numberKey = GlobalKey(debugLabel: 'countdown-number');

  /// Si el vuelo pinta ahora la tarjeta y su número.
  final ValueListenable<bool> hidden;

  /// El avance de la ruta (0 a 1).
  final Animation<double> progress;

  /// El estilo del número, que escribe la tarjeta al construirse para que el
  /// vuelo lo interpole con el de origen.
  TextStyle? numberStyle;
}

/// Tarjeta de cuenta atrás: número grande en el color del acento sobre su
/// fondo suave, con el título («días para Reyes») y la fecha de hoy debajo.
///
/// - [days]: días que faltan.
/// - [title]: texto junto al número, ya traducido.
/// - [date]: línea pequeña (por ejemplo «Hoy es 9 de noviembre»).
/// - [occasion]: tema de ocasión; cambia el acento y añade el borde fino.
///   Sin él usa el acento de Ajustes.
/// - [size]: 44 px en vistas previas, 56 en Navidad, 64 en cumpleaños.
/// - [titleMaxLines]: líneas máximas del título; con más se corta con puntos
///   suspensivos. Sin límite por defecto.
class CountdownCard extends StatelessWidget {
  const CountdownCard({
    super.key,
    required this.days,
    required this.title,
    required this.date,
    this.occasion,
    this.size = CountdownSize.compact,
    this.titleMaxLines,
    this.minHeight,
    this.flight,
  });

  final int days;

  /// Si la tarjeta es el destino del vuelo de la tarjeta del carrusel.
  final CountdownFlight? flight;
  final String title;
  final String date;
  final OccasionTheme? occasion;
  final CountdownSize size;
  final int? titleMaxLines;

  /// Alto mínimo de la tarjeta; el contenido va centrado en vertical.
  final double? minHeight;

  /// El alto que ocupa una tarjeta de [width] px con ese contenido, para
  /// los contenedores que necesitan un alto fijo (el carrusel de Personas).
  ///
  /// Mide el texto con el tamaño de letra del sistema y sigue la misma
  /// maqueta que [build]: relleno de 16 por 8, borde de 1, número, 16 de
  /// separación y debajo el título y la fecha.
  static double heightFor(
    BuildContext context, {
    required double width,
    required int days,
    required String title,
    required String date,
    CountdownSize size = CountdownSize.compact,
    int? titleMaxLines,
    double? minHeight,
  }) {
    final t = RegalosTokens.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final base = DefaultTextStyle.of(context).style;
    double layout(String text, TextStyle style, {int? maxLines, double? max}) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: base.merge(style)),
        textDirection: direction,
        textScaler: scaler,
        maxLines: maxLines,
        ellipsis: maxLines == null ? null : '…',
      )..layout(maxWidth: max ?? double.infinity);
      final h = painter.height;
      painter.dispose();
      return h;
    }

    final numberStyle = t.styles.countdownNumber(size, t.ink);
    final titleStyle = _titleStyle(t, size);
    final numberPainter = TextPainter(
      text: TextSpan(text: '$days', style: base.merge(numberStyle)),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final numberWidth = numberPainter.width;
    final numberHeight = numberPainter.height;
    numberPainter.dispose();
    final inner = math.max(40.0, width - 2 - 32 - numberWidth - 16);
    final column =
        layout(title, titleStyle, maxLines: titleMaxLines, max: inner) +
        layout(date, t.styles.meta, max: inner);
    final content = math.max(numberHeight, column) + 2 * _vertical(size) + 2;
    return math.max(content, minHeight ?? 0);
  }

  static double _vertical(CountdownSize size) => switch (size) {
    CountdownSize.compact => 8.0,
    CountdownSize.medium => 10.0,
    CountdownSize.large => 12.0,
    CountdownSize.carousel => 14.0,
  };

  static TextStyle _titleStyle(RegalosTokens t, CountdownSize size) =>
      size == CountdownSize.compact
      ? t.styles.countdownTitle.copyWith(color: t.ink)
      : t.styles.countdownTitle.copyWith(
          fontSize: 16,
          height: 22 / 16,
          color: t.ink,
        );

  @override
  Widget build(BuildContext context) {
    var t = RegalosTokens.of(context);
    if (occasion != null && occasion != t.occasion) {
      t = t.copyWith(occasion: occasion);
    }

    final vertical = _vertical(size);
    final stacked =
        size != CountdownSize.compact &&
        MediaQuery.textScalerOf(context).scale(16) > 16 * 1.5;
    final titleStyle = _titleStyle(t, size);
    final numberStyle = t.styles.countdownNumber(size, t.ink);
    final flight = this.flight?..numberStyle = numberStyle;

    Widget card(bool hidden) {
      Widget number = Text('$days', style: numberStyle, maxLines: 1);
      Widget texts = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: titleStyle,
            maxLines: titleMaxLines,
            overflow: titleMaxLines == null ? null : TextOverflow.ellipsis,
          ),
          Text(date, style: t.styles.meta.copyWith(color: t.textOnSoft)),
        ],
      );
      if (flight != null) {
        number = KeyedSubtree(
          key: flight.numberKey,
          child: Opacity(opacity: hidden ? 0 : 1, child: number),
        );
        texts = _FlightReveal(progress: flight.progress, child: texts);
      }
      return Container(
        key: flight?.cardKey,
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: vertical),
        constraints: minHeight == null
            ? null
            : BoxConstraints(minHeight: minHeight!),
        alignment: minHeight == null ? null : Alignment.centerLeft,
        decoration: BoxDecoration(
          color: hidden ? t.soft.withValues(alpha: 0) : t.soft,
          borderRadius: RegalosShape.card,
          border: t.cardBorder == null || hidden
              ? null
              : Border.all(color: t.cardBorder!),
        ),
        // Con letra muy grande el número se come el ancho y el texto quedaría
        // en una columna de dos letras: pasa debajo del número.
        child: stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [number, const SizedBox(height: 4), texts],
              )
            : Row(
                children: [
                  number,
                  const SizedBox(width: 16),
                  Expanded(child: texts),
                ],
              ),
      );
    }

    return Semantics(
      container: true,
      label: '$days $title. $date',
      excludeSemantics: true,
      child: flight == null
          ? card(false)
          : ValueListenableBuilder<bool>(
              valueListenable: flight.hidden,
              builder: (context, hidden, _) => card(hidden),
            ),
    );
  }
}

/// Los textos de la tarjeta del detalle mientras la ruta crece: opacidad en
/// `Interval(0.5, 0.9)` y subida de 6 a 0 px en `Interval(0.45, 0.95)`.
class _FlightReveal extends StatelessWidget {
  const _FlightReveal({required this.progress, required this.child});

  final Animation<double> progress;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: progress,
    child: child,
    builder: (context, child) {
      final p = progress.value;
      final opacity = const Interval(0.5, 0.9).transform(p);
      final rise = 6 * (1 - const Interval(0.45, 0.95).transform(p));
      return Opacity(
        opacity: opacity,
        child: Transform.translate(offset: Offset(0, rise), child: child),
      );
    },
  );
}
