import 'package:flutter/material.dart';

import '../theme/accent_palette.dart';
import '../theme/regalos_tokens.dart';

/// El color de una persona: una de las seis parejas pastel/tinta del diseño.
AccentPalette personPalette(int colorIndex) =>
    AccentId.values[colorIndex.abs() % AccentId.values.length].palette;

/// Cuadrado con la inicial de una persona, en su color.
///
/// Tiene un tamaño fijo (no crece con el tamaño de letra del sistema) y las
/// esquinas redondeadas con un radio de [radiusFor] como máximo 8: en la app
/// no hay círculos ni píldoras en los controles. Es decorativo: el nombre
/// siempre va al lado.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.name,
    required this.colorIndex,
    this.size = 40,
  });

  final String name;
  final int colorIndex;
  final double size;

  /// El radio de las esquinas: un quinto del lado y nunca más de 8.
  static double radiusFor(double size) => (size * 0.2).clamp(0.0, 8.0);

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final p = personPalette(colorIndex);
    final trimmed = name.trim();
    final initial = trimmed.isEmpty
        ? '?'
        : String.fromCharCode(trimmed.runes.first).toUpperCase();
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: p.fillOf(t.isDark),
          borderRadius: BorderRadius.circular(radiusFor(size)),
        ),
        child: Text(
          initial,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: size * 0.45,
            fontWeight: FontWeight.w700,
            color: p.inkOf(t.isDark),
          ),
        ),
      ),
    );
  }
}
