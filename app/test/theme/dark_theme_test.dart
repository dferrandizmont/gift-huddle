import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/features/family/presentation/giver_picker.dart';

// Contrastes del tema oscuro «Todoist neutro» (la guía del tema oscuro):
// 4,5:1 para texto y 3:1 para controles, con los seis acentos, las doce
// ocasiones y las ocasiones «Otra».

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  const text = 4.5;
  const control = 3.0;

  // (nombre, acento, ocasión)
  final variants = <(String, AccentPalette, OccasionTheme?)>[
    for (final id in AccentId.values) (id.name, id.palette, null),
    for (final o in OccasionTheme.all) (o.id, AccentId.lavender.palette, o),
    for (final c in kOccasionColors)
      (
        'otra-${c.name}',
        AccentId.lavender.palette,
        OccasionTheme.custom(color: c.name),
      ),
  ];

  RegalosTokens tokens(AccentPalette a, OccasionTheme? o) =>
      RegalosTokens.resolve(
        accent: a,
        brightness: Brightness.dark,
        occasion: o,
      );

  test('las superficies suben de escalón: fondo < tarjeta < hoja', () {
    final t = tokens(AccentId.lavender.palette, null);
    expect(t.bg.computeLuminance(), lessThan(t.surface.computeLuminance()));
    expect(t.surface.computeLuminance(), lessThan(t.sheet.computeLuminance()));
    // En claro la hoja es el fondo.
    final light = RegalosTokens.resolve(
      accent: AccentId.lavender.palette,
      brightness: Brightness.light,
    );
    expect(light.sheet, light.bg);
    expect(light.sheetEdge.a, 0);
  });

  for (final (name, palette, occasion) in variants) {
    test('oscuro: texto 4,5:1 y controles 3:1 en $name', () {
      final t = tokens(palette, occasion);
      final texts = <String, (Color, Color)>{
        'texto sobre hoja': (t.text, t.sheet),
        'secundario sobre hoja': (t.textSecondary, t.sheet),
        'tinta sobre hoja': (t.ink, t.sheet),
        'tinta sobre fondo': (t.ink, t.bg),
        'tinta sobre fondo suave': (t.ink, t.soft),
        'texto sobre fondo suave': (t.text, t.soft),
        'secundario sobre fondo suave': (t.textOnSoft, t.soft),
        'texto sobre relleno': (t.onFill, t.fill),
        'aviso sobre su fondo': (t.danger, t.dangerSoft),
        'rojo sobre fondo': (t.danger, t.bg),
        'rojo sobre hoja': (t.danger, t.sheet),
        'rojo sobre la fila que se borra': (t.danger, t.dangerRow),
      };
      texts.forEach((what, c) {
        expect(
          _contrast(c.$1, c.$2),
          greaterThanOrEqualTo(text),
          reason: '$what en $name',
        );
      });
      final controls = <String, (Color, Color)>{
        'relleno frente al fondo': (t.fill, t.bg),
        'relleno frente a la hoja': (t.fill, t.sheet),
        'borde de control sobre fondo': (t.chipBorder, t.bg),
        'borde de control sobre hoja': (t.chipBorder, t.sheet),
        'borde de selector sobre fondo': (t.controlBorder, t.bg),
        'trazo «Idea» sobre fondo': (t.ideaStroke, t.bg),
        'trazo «Idea» sobre hoja': (t.ideaStroke, t.sheet),
        'tinta frente al fondo': (t.ink, t.bg),
      };
      controls.forEach((what, c) {
        expect(
          _contrast(c.$1, c.$2),
          greaterThanOrEqualTo(control),
          reason: '$what en $name',
        );
      });
    });
  }

  test('oscuro: la marca de cada ocasión se ve (3:1) sobre fondo y hoja', () {
    final t = tokens(AccentId.lavender.palette, null);
    final themes = [
      ...OccasionTheme.all,
      for (final c in kOccasionColors) OccasionTheme.custom(color: c.name),
    ];
    for (final o in themes) {
      final mark = o.mark(dark: true);
      expect(
        _contrast(mark, t.bg),
        greaterThanOrEqualTo(control),
        reason: o.id,
      );
      expect(
        _contrast(mark, t.sheet),
        greaterThanOrEqualTo(control),
        reason: o.id,
      );
    }
  });

  test('oscuro: quién regala, chip sin elegir y elegido (4,5:1)', () {
    final t = tokens(AccentId.lavender.palette, null);
    for (var i = 0; i < giverColors.length; i++) {
      final g = t.giver(i);
      final tint = Color.alphaBlend(
        g.withValues(alpha: kGiverChipTint),
        t.sheet,
      );
      expect(
        _contrast(g, tint),
        greaterThanOrEqualTo(text),
        reason: 'texto del chip $i',
      );
      expect(
        _contrast(t.giverOn(i), g),
        greaterThanOrEqualTo(text),
        reason: 'chip elegido $i',
      );
      expect(
        _contrast(g, t.bg),
        greaterThanOrEqualTo(control),
        reason: 'punto $i sobre el fondo',
      );
      // El texto del elegido no es blanco.
      expect(t.giverOn(i), isNot(const Color(0xFFFFFFFF)));
    }
  });

  test('oscuro: aviso de duplicado (mantequilla) y acento de serie', () {
    final warn = AccentId.butter.palette;
    expect(_contrast(warn.tintaD, warn.tintD), greaterThanOrEqualTo(text));
    expect(_contrast(warn.onFill, warn.pastelD), greaterThanOrEqualTo(text));
  });

  // «Todoist neutro»: grises sin tinte, escalones claros y acentos vivos.
  test('oscuro: neutros grises, sin tinte, con escalones claros', () {
    final t = tokens(AccentId.lavender.palette, null);
    for (final c in [t.bg, t.surface, t.sheet, t.text, t.textSecondary]) {
      expect(
        (c.r - c.g).abs() < 1e-6 && (c.g - c.b).abs() < 1e-6,
        isTrue,
        reason: 'el neutro $c no es gris',
      );
    }
    expect(
      _contrast(t.surface, t.bg),
      greaterThanOrEqualTo(1.15),
      reason: 'tarjeta frente al fondo',
    );
    expect(
      _contrast(t.sheet, t.surface),
      greaterThanOrEqualTo(1.1),
      reason: 'hoja frente a la tarjeta',
    );
    expect(_contrast(t.text, t.bg), greaterThanOrEqualTo(15));
    expect(_contrast(t.text, t.surface), greaterThanOrEqualTo(12));
  });

  for (final (name, palette, occasion) in variants) {
    test('oscuro: texto y tinta sobre la tarjeta (AA) en $name', () {
      final t = tokens(palette, occasion);
      final pairs = <String, (Color, Color)>{
        'texto sobre tarjeta': (t.text, t.surface),
        'secundario sobre tarjeta': (t.textSecondary, t.surface),
        'secundario sobre fondo': (t.textSecondary, t.bg),
        'secundario sobre hoja': (t.textSecondary, t.sheet),
        'tinta sobre tarjeta': (t.ink, t.surface),
        'rojo sobre tarjeta': (t.danger, t.surface),
      };
      pairs.forEach((what, c) {
        expect(
          _contrast(c.$1, c.$2),
          greaterThanOrEqualTo(text),
          reason: '$what en $name',
        );
      });
      expect(
        _contrast(t.fill, t.surface),
        greaterThanOrEqualTo(control),
        reason: 'relleno frente a la tarjeta en $name',
      );
    });
  }

  test('oscuro: los rellenos de cada acento son vivos, no pasteles lavados', () {
    final palettes = [
      for (final id in AccentId.values) id.palette,
      for (final o in OccasionTheme.all) o.palette,
    ];
    for (final p in palettes) {
      expect(
        HSVColor.fromColor(p.pastelD).saturation,
        greaterThanOrEqualTo(0.4),
        reason: 'relleno ${p.pastelD}',
      );
      expect(
        HSVColor.fromColor(p.tintD).saturation,
        greaterThanOrEqualTo(0.4),
        reason: 'fondo suave ${p.tintD}',
      );
    }
  });

  // WCAG 1.4.11: lo que se identifica solo por su borde llega a 3:1 en claro
  // sobre el fondo, la hoja y el gris suave de las tarjetas.
  for (final id in AccentId.values) {
    test('claro: bordes de control 3:1 con el acento ${id.name}', () {
      final t = RegalosTokens.resolve(
        accent: id.palette,
        brightness: Brightness.light,
      );
      expect(t.chipBorder, t.controlBorder);
      for (final (what, bg) in [
        ('fondo', t.bg),
        ('hoja', t.sheet),
        ('tarjeta', t.surface),
      ]) {
        expect(
          _contrast(t.controlBorder, bg),
          greaterThanOrEqualTo(control),
          reason: 'borde de control sobre $what',
        );
        expect(
          _contrast(t.chipBorder, bg),
          greaterThanOrEqualTo(control),
          reason: 'borde de chip sobre $what',
        );
      }
      // El borde decorativo sigue siendo suave: no es de control.
      expect(_contrast(t.outline, t.bg), lessThan(control));
    });
  }

  test('oscuro: el claro no cambia', () {
    final t = RegalosTokens.resolve(
      accent: AccentId.lavender.palette,
      brightness: Brightness.light,
    );
    expect(t.bg, const Color(0xFFFFFFFF));
    expect(t.danger, const Color(0xFFB3261E));
    expect(t.giverOn(2), const Color(0xFFFFFFFF));
  });
}
