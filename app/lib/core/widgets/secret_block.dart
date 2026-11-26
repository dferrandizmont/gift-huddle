import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/regalos_motion.dart';
import '../theme/regalos_shape.dart';
import '../theme/regalos_tokens.dart';
import 'person_avatar.dart' show personPalette;
import 'settings_icons.dart';
import 'stroke_icon.dart';

// El bloque secreto (fase 3, lote 6): lo que ocupa el lugar de los regalos de
// una persona protegida en un móvil que no tiene derecho a verlos. Es una
// pieza de tamaño y dibujo fijos: ni cifras, ni filas, ni nada que dependa de
// lo que hay detrás. Las barras borrosas son siempre las mismas.

/// Los anchos de las barras borrosas del fondo: fijos, sin relación con
/// ningún dato.
const List<double> _kBars = <double>[0.82, 0.56, 0.7];

class _BlurredBars extends StatelessWidget {
  const _BlurredBars({
    required this.colorIndex,
    required this.bars,
    this.barHeight = 10,
    this.inset = 12,
  });

  final int colorIndex;
  final int bars;
  final double barHeight;
  final double inset;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final palette = personPalette(colorIndex);
    final tint = palette.surfaceOf(t.isDark);
    return ExcludeSemantics(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: 5,
          sigmaY: 5,
          tileMode: TileMode.decal,
        ),
        child: Padding(
          padding: EdgeInsets.all(inset),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < bars; i++)
                FractionallySizedBox(
                  widthFactor: _kBars[i % _kBars.length],
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: i.isEven ? tint : t.track,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: SizedBox(height: barHeight),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La frase del bloque: «Este móvil no los muestra.» o, en la web ([web]),
/// «Este ordenador no los muestra.».
String secretBlockNoteText(AppLocalizations l10n, {bool web = false}) =>
    web ? l10n.secretBlockNoteWeb : l10n.secretBlockNote;

/// El texto de lectura de pantalla de un bloque: título y frase, sin cifras.
/// Con [web], la frase habla de este ordenador.
String secretBlockLabel(
  AppLocalizations l10n,
  String name, {
  bool web = false,
  String? title,
}) =>
    '${title ?? l10n.secretBlockTitle(name)}. '
    '${secretBlockNoteText(l10n, web: web)}';

/// El bloque «Regalos en secreto para [name]»: tamaño fijo, fondo borroso y
/// candado. Con [onTap] se puede tocar (abre la ficha de la persona).
class SecretBlockCard extends StatelessWidget {
  /// Crea el bloque de la persona llamada [name].
  const SecretBlockCard({
    super.key,
    required this.name,
    this.colorIndex = 0,
    this.onTap,
    this.note,
    this.title,
    this.web = false,
  });

  /// Otro título en lugar de «Regalos en secreto para [name]»: el bloque fijo
  /// de la propia persona se llama «Sorpresas» (ADR 0010): ni cifras, ni
  /// fechas, ni ocasión.
  final String? title;

  /// Nombre de la persona protegida.
  final String name;

  /// Si es la web: la frase dice «este ordenador» en lugar de «este móvil».
  final bool web;

  /// Otra frase en lugar de «Este móvil no los muestra.»: el bloque de la
  /// persona de este móvil (1.0.6) dice que en él no se ven sus regalos y que
  /// solo otra persona puede cambiarlo.
  final String? note;

  /// Su color.
  final int colorIndex;

  /// Si se toca.
  final VoidCallback? onTap;

  /// Alto fijo del bloque.
  static const double height = 88;

  /// De 88 como mínimo: con letra grande o con [note] crece para que quepa el
  /// texto, nunca por lo que hay detrás (ni cifras ni filas).
  Widget _sized(Widget child) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: height),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final card = ClipRRect(
      borderRadius: RegalosShape.card,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: RegalosShape.card,
          border: Border.all(color: t.separator),
        ),
        child: _sized(
          // `passthrough`: el contenido recibe el alto mínimo (88) y no solo
          // lo que mide; si no, un `Stack` suelto lo pegaba al borde de
          // arriba y el candado y los textos se quedaban fuera del centro.
          Stack(
            fit: StackFit.passthrough,
            children: [
              Positioned.fill(
                child: _BlurredBars(colorIndex: colorIndex, bars: 3),
              ),
              Positioned.fill(
                child: ColoredBox(color: t.surface.withValues(alpha: 0.55)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ExcludeSemantics(
                      child: Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: t.soft,
                          borderRadius: RegalosShape.chip,
                        ),
                        child: StrokeIcon(
                          SettingsIcons.lock,
                          size: 22,
                          color: t.textOnSoft,
                          strokeWidth: 1.9,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title ?? l10n.secretBlockTitle(name),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.start,
                            style: t.styles.rowTitle.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            note ?? secretBlockNoteText(l10n, web: web),
                            textAlign: TextAlign.start,
                            maxLines: note == null ? 2 : null,
                            overflow: note == null
                                ? TextOverflow.ellipsis
                                : TextOverflow.visible,
                            style: t.styles.meta,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      container: true,
      button: onTap != null,
      label: note == null
          ? secretBlockLabel(l10n, name, web: web)
          : '${title ?? l10n.secretBlockTitle(name)}. $note',
      excludeSemantics: true,
      onTap: onTap,
      child: onTap == null
          ? card
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: card,
            ),
    );
  }
}

/// El candado y el título de una [SecretStrip]. El título nunca se parte a
/// mitad de palabra (QA 1.0.7, c1: «Surp/rises» en la franja estrecha de la
/// propia persona en Reparto): si la palabra más larga no cabe junto al
/// candado, se quita el candado; si ni así cabe, se encoge un poco, y si aun así
/// no, una sola línea con «…».
class _StripLabel extends StatelessWidget {
  const _StripLabel({
    required this.text,
    required this.style,
    required this.iconColor,
  });

  final String text;
  final TextStyle style;
  final Color iconColor;

  static const double _icon = 16;
  static const double _gap = 6;

  /// Hasta cuánto se encoge el título antes de pasar a «…».
  static const double _minScale = 0.8;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    double longest() {
      var widest = 0.0;
      for (final word in text.trim().split(RegExp(r'\s+'))) {
        final painter = TextPainter(
          text: TextSpan(text: word, style: style),
          textDirection: direction,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        widest = widest < painter.width ? painter.width : widest;
        painter.dispose();
      }
      return widest;
    }

    return LayoutBuilder(
      builder: (context, box) {
        final word = longest();
        final room = box.maxWidth;
        final withIcon = word + _icon + _gap <= room;
        final label = Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: style,
        );
        if (withIcon) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StrokeIcon(
                SettingsIcons.lock,
                size: _icon,
                color: iconColor,
                strokeWidth: 1.9,
              ),
              const SizedBox(width: _gap),
              Flexible(child: label),
            ],
          );
        }
        if (word <= room) return label;
        if (word * _minScale <= room) {
          return FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              text,
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.center,
              style: style,
            ),
          );
        }
        return Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: style,
        );
      },
    );
  }
}

/// La versión en franja del bloque, para el hueco de las celdas de una fila de
/// Reparto: el mismo fondo borroso y el candado, en una línea.
///
/// Entra y sale con un fundido suave ([shown]); con «Reducir movimiento», de
/// 150 ms. Nunca se mueve ni cambia de tamaño.
class SecretStrip extends StatelessWidget {
  /// Crea la franja de la persona llamada [name].
  const SecretStrip({
    super.key,
    required this.shown,
    required this.name,
    this.colorIndex = 0,
    this.onTap,
    this.title,
    this.web = false,
  });

  /// Otro título en lugar de «Regalos en secreto para [name]» («Sorpresas»
  /// en el bloque de la propia persona).
  final String? title;

  /// Si hay que enseñarla.
  final bool shown;

  /// Si es la web: la lectura de pantalla dice «este ordenador».
  final bool web;

  /// Nombre de la persona protegida.
  final String name;

  /// Su color.
  final int colorIndex;

  /// Si se toca.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final motion = RegalosMotion.of(context);
    final face = ClipRRect(
      borderRadius: RegalosShape.card,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: RegalosShape.card,
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: _BlurredBars(
                colorIndex: colorIndex,
                bars: 2,
                barHeight: 7,
                inset: 6,
              ),
            ),
            Positioned.fill(
              child: ColoredBox(color: t.surface.withValues(alpha: 0.55)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: _StripLabel(
                  text: title ?? l10n.secretBlockTitle(name),
                  style: t.styles.caption.copyWith(
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                  iconColor: t.textOnSoft,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return IgnorePointer(
      ignoring: !shown,
      child: AnimatedOpacity(
        opacity: shown ? 1 : 0,
        duration: motion.duration(RegalosSprings.softDuration),
        curve: motion.curve(Curves.easeOut),
        child: ExcludeSemantics(
          excluding: !shown,
          child: Semantics(
            container: true,
            button: onTap != null,
            label: secretBlockLabel(l10n, name, web: web, title: title),
            excludeSemantics: true,
            onTap: onTap,
            child: onTap == null
                ? face
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onTap,
                    child: face,
                  ),
          ),
        ),
      ),
    );
  }
}
