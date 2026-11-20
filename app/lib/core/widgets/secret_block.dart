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

/// El texto de lectura de pantalla de un bloque: título y frase, sin cifras.
String secretBlockLabel(AppLocalizations l10n, String name) =>
    '${l10n.secretBlockTitle(name)}. ${l10n.secretBlockNote}';

/// El bloque «Regalos en secreto para [name]»: tamaño fijo, fondo borroso y
/// candado. Con [onTap] se puede tocar (abre la ficha de la persona).
class SecretBlockCard extends StatelessWidget {
  /// Crea el bloque de la persona llamada [name].
  const SecretBlockCard({
    super.key,
    required this.name,
    this.colorIndex = 0,
    this.onTap,
  });

  /// Nombre de la persona protegida.
  final String name;

  /// Su color.
  final int colorIndex;

  /// Si se toca.
  final VoidCallback? onTap;

  /// Alto fijo del bloque.
  static const double height = 88;

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
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: _BlurredBars(colorIndex: colorIndex, bars: 3),
              ),
              Positioned.fill(
                child: ColoredBox(color: t.surface.withValues(alpha: 0.55)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
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
                            l10n.secretBlockNote,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
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
      label: secretBlockLabel(l10n, name),
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
  });

  /// Si hay que enseñarla.
  final bool shown;

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
            label: secretBlockLabel(l10n, name),
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
