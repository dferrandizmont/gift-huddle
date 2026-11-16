import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion/rolling_number.dart';
import '../theme/app_typography.dart';
import '../theme/occasion_theme.dart';
import '../theme/regalos_shape.dart';
import '../theme/regalos_tokens.dart';
import 'stroke_icon.dart';

/// Tarjeta del carrusel de Personas (maqueta v3): el nombre de la ocasión y
/// su icono arriba, el número de días grande con «días» al lado, y debajo la
/// fecha y cuántos regalos están comprados.
///
/// Con el tema de la ocasión (si el interruptor «Temas de ocasión» está
/// encendido) usa su acento y su borde fino; sin él, el acento de Ajustes.
class OccasionCountdownCard extends StatelessWidget {
  const OccasionCountdownCard({
    super.key,
    required this.days,
    required this.unit,
    required this.title,
    required this.date,
    required this.meta,
    this.icon,
    this.occasion,
    this.minHeight = RegalosSizes.carouselHeight,
    this.height,
    this.rollFromEmpty = false,
    this.rollDelay = Duration.zero,
    this.rollCue,
    this.rollFrom,
    this.iconBuilder,
    this.numberKey,
    this.compact = false,
  });

  final int days;

  /// La versión compacta de la columna «Resumen» de escritorio: 112 de alto,
  /// cifra de 44, y la fecha y los regalos comprados en una sola línea.
  final bool compact;

  /// El alto fijo de la tarjeta [compact].
  static const double compactHeight = 112;

  /// Para medir dónde está el número (el vuelo hasta el detalle de la ocasión
  /// parte de ahí).
  final Key? numberKey;

  /// «días» / «día».
  final String unit;
  final String title;

  /// «25 de diciembre».
  final String date;

  /// «2 de 6 regalos comprados» o «Sin regalos todavía».
  final String meta;

  /// Icono de la ocasión (el del medio de su guirnalda), o `null`.
  final StrokeIconBuilder? icon;
  final OccasionTheme? occasion;
  final double minHeight;

  /// Alto fijo (el del carrusel: la tarjeta más alta de todas).
  final double? height;

  /// Si la primera vez las cifras ruedan desde vacío (la primera vista del
  /// carrusel), tras [rollDelay].
  final bool rollFromEmpty;

  /// Retardo de la rodadura inicial.
  final Duration rollDelay;

  /// Cuando cambia, el número rueda desde [rollFrom] hasta [days] (el
  /// carrusel lo cambia al llegar a esta tarjeta).
  final Object? rollCue;

  /// El número de la tarjeta anterior, desde el que rueda al llegar.
  final int? rollFrom;

  /// Envuelve el icono del dibujo (paralaje y rebote del carrusel).
  final Widget Function(Widget icon)? iconBuilder;

  static const double _padH = 16;
  static const double _padV = 14;
  static const double _iconSize = 28;

  static TextStyle _titleStyle(RegalosTokens t) =>
      t.styles.countdownTitle.copyWith(color: t.ink);

  static TextStyle _unitStyle(RegalosTokens t) =>
      t.styles.label.copyWith(fontSize: 17, height: 1.2, color: t.ink);

  static TextStyle _dateStyle(RegalosTokens t) =>
      t.styles.meta.copyWith(fontSize: 13.5, height: 1.3, color: t.text);

  static TextStyle _metaStyle(RegalosTokens t) =>
      _dateStyle(t).copyWith(color: t.ink.withValues(alpha: 0.8));

  static TextStyle _numberStyle(RegalosTokens t, {bool compact = false}) => t
      .styles
      .countdownNumber(
        compact ? CountdownSize.compact : CountdownSize.carousel,
        t.ink,
      )
      .copyWith(letterSpacing: compact ? -1 : -1.5, height: compact ? 1 : null);

  /// El estilo del número grande, para el vuelo hasta el detalle.
  static TextStyle numberStyleOf(RegalosTokens t, {bool compact = false}) =>
      _numberStyle(t, compact: compact);

  /// El alto de una tarjeta de [width] px: lo que ocupa su contenido con el
  /// tamaño de letra del sistema, con [minHeight] como mínimo.
  static double heightFor(
    BuildContext context, {
    required double width,
    required int days,
    required String title,
    required String date,
    required String meta,
    double minHeight = RegalosSizes.carouselHeight,
  }) {
    final t = RegalosTokens.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final base = DefaultTextStyle.of(context).style;
    double measure(String text, TextStyle style, double max, int maxLines) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: base.merge(style)),
        textDirection: direction,
        textScaler: scaler,
        maxLines: maxLines,
        ellipsis: '…',
      )..layout(maxWidth: max);
      final h = painter.height;
      painter.dispose();
      return h;
    }

    final inner = width - 2 - 2 * _padH;
    final top = math.max(
      _iconSize,
      measure(title, _titleStyle(t), inner - _iconSize - 8, 2),
    );
    final number = measure('$days', _numberStyle(t), inner, 1);
    final bottom =
        measure(date, _dateStyle(t), inner, 1) +
        measure(meta, _metaStyle(t), inner, 2);
    return math.max(minHeight, top + number + bottom + 2 * _padV + 2 + 8);
  }

  Widget _wrapIcon(Widget icon) =>
      iconBuilder == null ? icon : iconBuilder!(icon);

  @override
  Widget build(BuildContext context) {
    var t = RegalosTokens.of(context);
    if (occasion != null && occasion != t.occasion) {
      t = t.copyWith(occasion: occasion);
    }
    final iconSize = compact ? 24.0 : _iconSize;
    return Semantics(
      container: true,
      label: '$days $unit. $title. $date. $meta',
      excludeSemantics: true,
      child: Container(
        height: compact ? compactHeight : height,
        constraints: BoxConstraints(minHeight: compact ? 0 : minHeight),
        padding: EdgeInsets.symmetric(
          horizontal: _padH,
          vertical: compact ? 12 : _padV,
        ),
        // Nada se sale de su tarjeta: el dibujo se desplaza con el paralaje del
        // carrusel y, en la tarjeta que asoma, se recorta en el borde.
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: t.soft,
          borderRadius: RegalosShape.card,
          border: Border.all(color: t.cardBorder ?? t.separator),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: _titleStyle(t),
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (icon != null) ...[
                  const SizedBox(width: 8),
                  _wrapIcon(
                    StrokeIcon(
                      icon!,
                      size: iconSize,
                      color: t.ink.withValues(alpha: 0.62),
                      strokeWidth: 1.5,
                    ),
                  ),
                ],
              ],
            ),
            // Con letra muy grande el número y «días» no caben en el ancho de
            // la tarjeta: se encogen juntos en vez de salirse.
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    KeyedSubtree(
                      key: numberKey,
                      child: RollingNumber(
                        value: days,
                        style: _numberStyle(t, compact: compact),
                        rollFromEmpty: rollFromEmpty,
                        delay: rollDelay,
                        cue: rollCue,
                        cueFrom: rollFrom,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(unit, style: _unitStyle(t), maxLines: 1),
                  ],
                ),
              ),
            ),
            if (compact)
              Text(
                '$date · $meta',
                style: _dateStyle(t),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(date, style: _dateStyle(t), maxLines: 1),
                  Text(
                    meta,
                    style: _metaStyle(t),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Una ocasión en una fila de [rowHeight] (la columna «Resumen» y la fila de
/// encima de la lista de Personas en escritorio): un cuadro pastel de 40 con
/// los días, el título y, debajo, la fecha y los regalos comprados.
///
/// Con el tema de la ocasión usa su pastel y su tinta; sin él, los del acento.
/// El toque y el ratón los pone quien la use (`onTap`).
class OccasionSummaryRow extends StatelessWidget {
  /// Crea la fila.
  const OccasionSummaryRow({
    super.key,
    required this.days,
    required this.unit,
    required this.title,
    required this.date,
    required this.meta,
    this.occasion,
    this.onTap,
  });

  /// Días que faltan.
  final int days;

  /// «días» / «día», para el lector de pantalla.
  final String unit;
  final String title;

  /// «25 de diciembre».
  final String date;

  /// «2 de 6 regalos comprados» o «Sin regalos todavía».
  final String meta;
  final OccasionTheme? occasion;
  final VoidCallback? onTap;

  /// El alto de la fila.
  static const double rowHeight = 56;

  /// El alto del cuadro de los días.
  static const double boxSize = 40;

  /// El ancho del cuadro de los días: 48, para que tres cifras quepan con
  /// aire.
  static const double boxWidth = 48;

  @override
  Widget build(BuildContext context) {
    var t = RegalosTokens.of(context);
    if (occasion != null && occasion != t.occasion) {
      t = t.copyWith(occasion: occasion);
    }
    return Semantics(
      container: true,
      button: onTap != null,
      label: '$days $unit. $title. $date. $meta',
      excludeSemantics: true,
      onTap: onTap,
      child: SizedBox(
        height: rowHeight,
        child: InkWell(
          onTap: onTap,
          borderRadius: RegalosShape.card,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: t.soft,
                    borderRadius: RegalosShape.card,
                    border: t.cardBorder == null
                        ? null
                        : Border.all(color: t.cardBorder!),
                  ),
                  child: SizedBox(
                    width: boxWidth,
                    height: boxSize,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '$days',
                            maxLines: 1,
                            style: t.styles.label.copyWith(
                              fontSize: 16,
                              height: 1,
                              fontWeight: FontWeight.w700,
                              color: t.ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.styles.label.copyWith(fontSize: 14.5),
                      ),
                      Text(
                        '$date · $meta',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.styles.meta,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
