import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/theme/theme.dart';

// El aviso de «Te pasas» sobre una tarjeta pastel (la de una ocasión del
// presupuesto en la web): `dangerOnTint` llega a 4,5:1 sobre la superficie de
// las seis paletas de acento y de todas las ocasiones, en claro y en oscuro.

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  final palettes = <(String, AccentPalette)>[
    for (final id in AccentId.values) (id.name, id.palette),
    for (final o in OccasionTheme.all) (o.id, o.palette),
    for (final c in kOccasionColors) ('otra-${c.name}', c.palette),
  ];

  for (final brightness in Brightness.values) {
    test('el aviso sobre pastel llega a 4,5:1 en ${brightness.name}', () {
      final t = RegalosTokens.resolve(
        accent: AccentId.lavender.palette,
        brightness: brightness,
      );
      expect(palettes.length, greaterThanOrEqualTo(6));
      for (final (name, palette) in palettes) {
        final surface = palette.surfaceOf(t.isDark);
        expect(
          _contrast(t.dangerOnTint, surface),
          greaterThanOrEqualTo(4.5),
          reason: '$name en ${brightness.name}',
        );
      }
    });
  }

  test('en oscuro, el aviso sobre pastel es más claro que el del resto', () {
    final dark = RegalosTokens.resolve(
      accent: AccentId.lavender.palette,
      brightness: Brightness.dark,
    );
    final light = RegalosTokens.resolve(
      accent: AccentId.lavender.palette,
      brightness: Brightness.light,
    );
    expect(
      dark.dangerOnTint.computeLuminance(),
      greaterThan(dark.danger.computeLuminance()),
    );
    expect(light.dangerOnTint, light.danger);
  });
}
