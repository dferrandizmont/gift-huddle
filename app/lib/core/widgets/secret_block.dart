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
}) => '${l10n.secretBlockTitle(name)}. ${secretBlockNoteText(l10n, web: web)}';

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
    this.web = false,
  });

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
          Stack(
            children: [
              Positioned.fill(
                child: _BlurredBars(colorIndex: colorIndex, bars: 3),
              ),
              Positioned.fill(
                child: ColoredBox(color: t.surface.withValues(alpha: 0.55)),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: note == null ? 0 : 14,
                ),
                child: Row(
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
                            l10n.secretBlockTitle(name),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: t.styles.rowTitle.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            note ?? secretBlockNoteText(l10n, web: web),
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
          : '${l10n.secretBlockTitle(name)}. $note',
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
    this.web = false,
  });

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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StrokeIcon(
                      SettingsIcons.lock,
                      size: 16,
                      color: t.textOnSoft,
                      strokeWidth: 1.9,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        l10n.secretBlockTitle(name),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: t.styles.caption.copyWith(
                          fontSize: 12,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: t.text,
                        ),
                      ),
                    ),
                  ],
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
            label: secretBlockLabel(l10n, name, web: web),
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
