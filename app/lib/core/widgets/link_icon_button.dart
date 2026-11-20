import 'package:flutter/material.dart';

import '../theme/regalos_motion.dart';
import '../theme/regalos_shape.dart';
import '../theme/regalos_tokens.dart';
import 'stroke_icon.dart';
import 'tabler_icons.dart';

/// Lo que pulsa y abre algo (el enlace de un regalo): sin borde ni fondo, con
/// la mano del ratón, el foco del teclado (el filete de siempre) y un efecto
/// de pulsación sobrio: el contenido encoge un poco mientras se aprieta. Con
/// «Reducir movimiento» no escala: solo se aclara.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final reduce = RegalosMotion.of(context).reduce;
    final pressed = _pressed && widget.onTap != null;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: widget.onTap,
        onHighlightChanged: (v) {
          if (mounted && _pressed != v) {
            setState(() => _pressed = v);
          }
        },
        borderRadius: RegalosShape.button,
        hoverColor: t.ink.withValues(alpha: 0.08),
        child: AnimatedScale(
          scale: pressed && !reduce ? 0.9 : 1,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: pressed && reduce ? 0.55 : 1,
            duration: RegalosMotion.fade,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Un icono de trazo que se pulsa y abre el enlace de un regalo.
///
/// El dibujo mide [iconSize] en un cuadrado exacto (no se estira con la celda
/// que lo rodea: una columna de 40 no lo deforma) y la zona que responde mide
/// [hitSize]. Con [onTap] `null` no responde ni se anuncia como botón.
class LinkIconButton extends StatelessWidget {
  /// Crea el botón.
  const LinkIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.tooltip,
    this.iconSize = 18,
    this.hitSize = 32,
    this.color,
  });

  /// El dibujo (de Tabler).
  final StrokeIconBuilder icon;

  /// Lo que dice el lector de pantalla.
  final String label;

  /// Lo que hace al pulsar; `null` lo deja sin respuesta.
  final VoidCallback? onTap;

  /// La ayuda del ratón; si no se da, la misma [label].
  final String? tooltip;

  /// El lado del dibujo.
  final double iconSize;

  /// El lado de la zona que responde.
  final double hitSize;

  /// El color del dibujo; por defecto, el texto secundario.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Tooltip(
        message: tooltip ?? label,
        excludeFromSemantics: true,
        child: SizedBox.square(
          dimension: hitSize,
          child: _Pressable(
            onTap: onTap,
            child: Center(
              child: StrokeIcon(
                icon,
                size: iconSize,
                color: color ?? t.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// El enlace de un regalo en una fila de la lista: el icono de enlace de
/// Tabler y el sitio («amzn.eu»), pequeño, en el color secundario; al pulsarlo
/// abre el enlace. Con [separator] lleva delante el «·» que lo separa de lo
/// anterior, y los dos pasan juntos a la línea siguiente si no caben.
///
/// Lo que se ve no cambia al ensanchar la zona de toque: mide como mínimo 44 de
/// ancho y 23 de alto (el alto que sobra de la fila, que no crece por tenerlo;
/// más arriba está el nombre y no se le puede quitar el toque). El sitio largo
/// se corta con puntos suspensivos.
class GiftLinkLabel extends StatelessWidget {
  /// Crea la marca del enlace.
  const GiftLinkLabel({
    super.key,
    required this.host,
    required this.label,
    required this.onTap,
    this.separator = false,
    this.compact = false,
  });

  /// El sitio ya preparado para enseñarlo (`userLinkHost`).
  final String host;

  /// Lo que dice el lector de pantalla («Abrir enlace: amzn.eu»).
  final String label;

  /// Abre el enlace.
  final VoidCallback onTap;

  /// Si lleva delante el «·» de separación.
  final bool separator;

  /// Sin zona de toque añadida (el ratón de las filas en columnas de
  /// escritorio no la necesita).
  final bool compact;

  /// El mayor ancho del sitio y su icono.
  static const double maxWidth = 150;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final link = Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: _Pressable(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: compact ? 0 : 44),
          child: Padding(
            // El alto de la línea (16) más 7 de zona de toque: lo que sobra
            // del alto mínimo de la fila, sin hacerla crecer.
            padding: compact
                ? EdgeInsets.zero
                : const EdgeInsets.only(top: 2, bottom: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StrokeIcon(tablerLink, size: 13, color: t.textSecondary),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.styles.meta,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: maxWidth),
      child: separator
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('·', semanticsLabel: ''),
                const SizedBox(width: 6),
                Flexible(child: link),
              ],
            )
          : link,
    );
  }
}
