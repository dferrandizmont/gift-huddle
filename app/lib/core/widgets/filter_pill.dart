import 'package:flutter/material.dart';

import '../motion/haptics.dart';
import '../motion/pop_in.dart';
import '../theme/regalos_motion.dart';
import '../theme/regalos_shape.dart';
import '../theme/regalos_tokens.dart';
import 'stroke_icon.dart';

/// Filtro de la ficha «A + Actual»: 36 de alto, radio 6 y zona táctil de 44.
///
/// Activo lleva el fondo de la selección (lavanda velada), su borde y el texto
/// en tinta y negrita; además, un visto delante, así que el estado no depende
/// solo del color. Sin activar, el fondo de los campos y el borde de control.
///
/// Al activarse (§2.6 de la guía de movimiento) el relleno cambia
/// con `snap` y el color del texto con `soft`; el visto entra con el ancho del
/// chip (`bounce`, de 0 a 20 px) y el icono rebota (`PopIn` desde 0,6). Al
/// apagarse, el ancho baja a 0 en 180 ms con `fold`. El radio es fijo. Con
/// «Reducir movimiento» solo hay un fundido de 150 ms, sin cambiar el ancho.
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.icon,
    this.trailingIcon,
    this.leading,
    this.semanticLabel,
    this.solid = false,
    this.radius,
    this.haptic = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;
  final StrokeIconBuilder? icon;
  final StrokeIconBuilder? trailingIcon;

  /// Adorno delante de la etiqueta (un punto de color) mientras no está
  /// activa; activa lo sustituye el visto.
  final Widget? leading;
  final String? semanticLabel;

  /// Activa se rellena con el pastel y el texto en tinta (el selector de
  /// Reparto), sin visto ni punto.
  final bool solid;

  /// Radio de las esquinas; por defecto el de los chips (6).
  final double? radius;

  /// Si el toque vibra con un clic. Las pastillas que solo abren una hoja (el
  /// botón de filtros) no vibran: abrir una pantalla no lleva vibración.
  final bool haptic;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final fillColor = solid ? t.fill : t.selection;
    final edgeColor = solid ? t.fill : t.selectionBorder;
    final color = selected ? (solid ? t.onFill : t.ink) : t.text;
    final motion = RegalosMotion.of(context);
    final borderRadius = radius == null
        ? RegalosShape.chip
        : BorderRadius.circular(radius!);
    // El adorno de delante: el visto, el punto o el icono. Entra y sale con el
    // ancho del chip.
    Widget? lead;
    if (selected && solid) {
      // Sin adorno: lo dice el relleno.
    } else if (selected && trailingIcon == null) {
      lead = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopIn(
            from: 0.6,
            child: StrokeIcon(
              AppIcons.check,
              size: 14,
              color: color,
              strokeWidth: 2.6,
            ),
          ),
          const SizedBox(width: 4),
        ],
      );
    } else if (leading != null) {
      lead = Row(
        mainAxisSize: MainAxisSize.min,
        children: [leading!, const SizedBox(width: 6)],
      );
    } else if (icon != null) {
      lead = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StrokeIcon(icon!, size: 18, color: color, strokeWidth: 1.75),
          const SizedBox(width: 7),
        ],
      );
    }
    void tap() {
      // Elegir o quitar vibra; tocar de nuevo la ya elegida de un selector
      // (`solid`), que no cambia nada, no.
      if (haptic && !(selected && solid)) {
        context.haptics.selection();
      }
      onTap();
    }

    final pill = AnimatedContainer(
      duration: motion.duration(RegalosSprings.snapDuration),
      curve: motion.curve(RegalosCurves.snap),
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? fillColor : t.field,
        border: Border.all(color: selected ? edgeColor : t.chipBorder),
        borderRadius: borderRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Con «Reducir movimiento» el ancho no se anima: el visto se funde.
          if (motion.reduce)
            lead ?? const SizedBox.shrink()
          else
            AnimatedSize(
              duration: RegalosSprings.bounceDuration,
              reverseDuration: RegalosCurves.foldDuration,
              curve: RegalosCurves.bounce,
              alignment: Alignment.centerLeft,
              child: lead ?? const SizedBox.shrink(),
            ),
          Flexible(
            child: AnimatedDefaultTextStyle(
              duration: motion.duration(RegalosSprings.softDuration),
              curve: motion.curve(RegalosCurves.soft),
              style: t.styles.metaStrong.copyWith(
                fontSize: 14,
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
              child: Text(label),
            ),
          ),
          if (trailingIcon != null) ...[
            const SizedBox(width: 4),
            StrokeIcon(trailingIcon!, size: 14, color: color, strokeWidth: 2.4),
          ],
        ],
      ),
    );
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: semanticLabel ?? label,
      onTap: tap,
      excludeSemantics: true,
      // La zona de toque es la de 44 por 44 entera, no solo el dibujo de 36: el
      // margen de fuera también activa el filtro; encima del dibujo, la tinta.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: InkWell(onTap: tap, borderRadius: borderRadius, child: pill),
          ),
        ),
      ),
    );
  }
}
