import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/features/family/presentation/giver_picker.dart';

// Contrastes del tema oscuro «Pastel en velo» (D1): 4,5:1 para texto y 3:1
// para lo que se reconoce solo por su trazo, con los seis acentos, las doce
// ocasiones y las ocasiones «Otra». Los rellenos de color son el pastel velado
// sobre el fondo: el botón se reconoce por su texto pastel (4,5:1), no por el
// relleno.

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
        'tinta sobre la selección': (t.ink, t.selection),
        'texto sobre la selección': (t.text, t.selection),
        'texto sobre desplegable': (t.text, t.popover),
        'secundario sobre la barra lateral': (t.textSecondary, t.sidebar),
        'secundario sobre campo': (t.textSecondary, t.field),
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
        'borde de control sobre fondo': (t.chipBorder, t.bg),
        'borde de control sobre hoja': (t.chipBorder, t.sheet),
        'borde de selector sobre fondo': (t.controlBorder, t.bg),
        'trazo «Idea» sobre fondo': (t.ideaStroke, t.bg),
        'trazo «Idea» sobre hoja': (t.ideaStroke, t.sheet),
        'tinta frente al fondo': (t.ink, t.bg),
        'borde de control sobre campo': (t.controlBorder, t.field),
        'borde de lo elegido sobre fondo': (t.selectionEdge, t.bg),
        'borde de lo elegido sobre tarjeta': (t.selectionEdge, t.surface),
        'borde de lo elegido sobre hoja': (t.selectionEdge, t.sheet),
      };
      controls.forEach((what, c) {
        expect(
          _contrast(c.$1, c.$2),
          greaterThanOrEqualTo(control),
          reason: '$what en $name',
        );
      });
      // El velo se distingue del fondo aunque no llegue a 3:1.
      expect(
        _contrast(t.fill, t.bg),
        greaterThanOrEqualTo(1.25),
        reason: 'relleno frente al fondo en $name',
      );
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

  // Los adornos de la cabecera conviven con el velo: ni saturados (el dorado
  // #F5C672 de antes) ni apagados (siguen a 3:1 sobre el fondo y la hoja).
  test('oscuro: los adornos de ocasión no están saturados y se leen', () {
    final t = tokens(AccentId.lavender.palette, null);
    for (final o in OccasionTheme.all) {
      for (final (what, c) in [
        ('adorno', o.ornamentD),
        ('adorno secundario', o.ornamentAltD),
      ]) {
        final hsl = HSLColor.fromColor(c);
        expect(
          hsl.saturation,
          lessThanOrEqualTo(0.65),
          reason: '$what de ${o.id}',
        );
        expect(
          _contrast(c, t.bg),
          greaterThanOrEqualTo(control),
          reason: '$what de ${o.id} sobre el fondo',
        );
        expect(
          _contrast(c, t.sheet),
          greaterThanOrEqualTo(control),
          reason: '$what de ${o.id} sobre la hoja',
        );
      }
    }
  });

  test('oscuro: aviso de duplicado (mantequilla) y acento de serie', () {
    final warn = AccentId.butter.palette;
    expect(_contrast(warn.tintaD, warn.tintD), greaterThanOrEqualTo(text));
    expect(_contrast(warn.onFill, warn.pastelD), greaterThanOrEqualTo(text));
  });

  // «Pastel en velo»: neutros cálidos (más rojo que azul) y escalones claros.
  test('oscuro: neutros cálidos, casi negros, con escalones claros', () {
    final t = tokens(AccentId.lavender.palette, null);
    expect(t.bg, const Color(0xFF161514));
    for (final c in [t.bg, t.surface, t.sheet, t.text, t.textSecondary]) {
      expect(
        c.r >= c.g && c.g >= c.b,
        isTrue,
        reason: 'el neutro $c no es cálido',
      );
    }
    expect(
      _contrast(t.surface, t.bg),
      greaterThanOrEqualTo(1.08),
      reason: 'tarjeta frente al fondo',
    );
    expect(
      _contrast(t.sheet, t.surface),
      greaterThanOrEqualTo(1.05),
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
        greaterThanOrEqualTo(1.25),
        reason: 'relleno frente a la tarjeta en $name',
      );
    });
  }

  test('oscuro: los colores salen del pastel velado sobre el fondo', () {
    final palettes = [
      for (final id in AccentId.values) id.palette,
      for (final o in OccasionTheme.all) o.palette,
    ];
    const bg = Color(0xFF161514);
    for (final p in palettes) {
      expect(p.tintaD, p.pastel);
      expect(p.onFill, p.pastel);
      final source = Color.lerp(p.pastel, p.tinta, kVeilTintaShare)!;
      expect(p.veilSource, source);
      expect(p.pastelD, Color.lerp(bg, source, kVeilFill));
      expect(p.tintD, Color.lerp(bg, source, kVeilSoft));
      expect(p.borderD, Color.lerp(bg, source, kVeilBorder));
      expect(p.selectionD, Color.lerp(bg, source, kVeilSelection));
    }
  });

  // La maqueta vela el pastel solo y en pantalla se ve gris: las superficies
  // de color tienen que distinguirse del gris neutro y del fondo, y el texto
  // pastel llegar a 4,5:1 sobre todas.
  test('oscuro: el velo se ve y el texto pastel llega a 4,5:1', () {
    final palettes = [
      for (final id in AccentId.values) id.palette,
      for (final o in OccasionTheme.all) o.palette,
    ];
    for (final p in palettes) {
      for (final (what, veil) in [
        ('relleno', p.pastelD),
        ('superficie', p.tintD),
        ('selección', p.selectionD),
        ('borde', p.borderD),
      ]) {
        expect(
          _contrast(p.tintaD, veil),
          greaterThanOrEqualTo(text),
          reason: 'pastel sobre $what de ${p.pastel}',
        );
        expect(
          _contrast(veil, kVeilBackground),
          greaterThanOrEqualTo(what == 'selección' ? 1.15 : 1.2),
          reason: '$what de ${p.pastel} frente al fondo',
        );
      }
    }
  });

  test('claro y oscuro: la tinta sobre la selección llega a 4,5:1', () {
    for (final id in AccentId.values) {
      for (final b in Brightness.values) {
        final t = RegalosTokens.resolve(accent: id.palette, brightness: b);
        expect(
          _contrast(t.ink, t.selection),
          greaterThanOrEqualTo(text),
          reason: '${id.name} / ${b.name}',
        );
      }
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
