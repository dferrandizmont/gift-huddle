import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/core/widgets/occasion_countdown_card.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  // (acento, ocasión) que se comprueban: los seis colores y los dos temas.
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

  for (final (name, palette, occasion) in variants) {
    for (final brightness in Brightness.values) {
      test('contraste AA en $name / ${brightness.name}', () {
        final t = RegalosTokens.resolve(
          accent: palette,
          brightness: brightness,
          occasion: occasion,
        );
        const aa = 4.5;
        final pairs = <String, (Color, Color)>{
          'texto sobre fondo': (t.text, t.bg),
          'texto secundario sobre fondo': (t.textSecondary, t.bg),
          'texto secundario sobre superficie': (t.textSecondary, t.surface),
          'texto sobre superficie': (t.text, t.surface),
          'tinta sobre fondo (etiqueta activa, números)': (t.ink, t.bg),
          'texto sobre relleno (píldora, segmento, botón)': (t.onFill, t.fill),
          'tinta sobre fondo suave (cuenta atrás)': (t.ink, t.soft),
          'texto sobre fondo suave': (t.text, t.soft),
          'texto de fecha sobre fondo suave': (t.textOnSoft, t.soft),
        };
        pairs.forEach((what, colors) {
          expect(
            _contrast(colors.$1, colors.$2),
            greaterThanOrEqualTo(aa),
            reason: '$what en $name/${brightness.name}',
          );
        });
      });
    }
  }

  test('los puntos de cada ocasión se ven (3:1) sobre fondo y superficie', () {
    final themes = [
      ...OccasionTheme.all,
      for (final c in kOccasionColors) OccasionTheme.custom(color: c.name),
    ];
    for (final brightness in Brightness.values) {
      final dark = brightness == Brightness.dark;
      final t = RegalosTokens.resolve(
        accent: AccentId.lavender.palette,
        brightness: brightness,
      );
      for (final o in themes) {
        final mark = o.mark(dark: dark);
        expect(
          _contrast(mark, t.bg),
          greaterThanOrEqualTo(3),
          reason: '${o.id} sobre el fondo (${brightness.name})',
        );
        expect(
          _contrast(mark, t.surface),
          greaterThanOrEqualTo(3),
          reason: '${o.id} sobre la superficie (${brightness.name})',
        );
      }
    }
  });

  test('cada tipo de ocasión tiene su tema, y «Otra» el de su color', () {
    for (final kind in OccasionKind.values) {
      if (kind == OccasionKind.custom) {
        expect(OccasionTheme.forKind(kind), isNull);
        continue;
      }
      final theme = OccasionTheme.forKind(kind);
      expect(theme, isNotNull, reason: kind.name);
      expect(OccasionTheme.all, contains(theme));
    }
    // Todos distintos: cada fiesta tiene su acento y su ilustración.
    final ids = {for (final o in OccasionTheme.all) o.id};
    expect(ids.length, OccasionTheme.all.length);
    final arts = {for (final o in OccasionTheme.all) o.art};
    expect(arts.length, OccasionTheme.all.length);
    // Navidad es roja (Navidad) y el Tió, verde.
    expect(OccasionTheme.christmas.palette.tinta.r, greaterThan(0.5));
    expect(OccasionTheme.tio.palette.tinta.g, greaterThan(0.3));
    final custom = OccasionTheme.custom(color: 'sky', icon: 'party');
    expect(custom.palette.pastel, AccentId.sky.palette.pastel);
    expect(custom.icon, kOccasionIcons['party']);
    // Un nombre desconocido cae en el de serie.
    final fallback = OccasionTheme.custom(color: 'nope', icon: 'nope');
    expect(fallback.palette.pastel, kOccasionColors.first.palette.pastel);
    expect(fallback.icon, kOccasionIcons[kDefaultOccasionIcon]);
  });

  test('los elementos gráficos tienen al menos 3:1 (AA no textual)', () {
    for (final brightness in Brightness.values) {
      for (final id in AccentId.values) {
        final t = RegalosTokens.resolve(
          accent: id.palette,
          brightness: brightness,
        );
        expect(_contrast(t.ideaStroke, t.bg), greaterThanOrEqualTo(3));
        expect(_contrast(t.ink, t.bg), greaterThanOrEqualTo(3));
        for (final g in t.givers) {
          expect(
            _contrast(g, t.bg),
            greaterThanOrEqualTo(3),
            reason: 'giver $g en ${brightness.name}',
          );
        }
      }
    }
  });

  test('el texto secundario de la cuenta atrás llega a 4,5:1 en los dos temas '
      '(color efectivo sobre la tarjeta)', () {
    final themes = <(String, AccentPalette, OccasionTheme?)>[
      for (final id in AccentId.values) (id.name, id.palette, null),
      for (final o in OccasionTheme.all) (o.id, AccentId.lavender.palette, o),
    ];
    for (final b in Brightness.values) {
      for (final (name, accent, occasion) in themes) {
        final t = RegalosTokens.resolve(
          accent: accent,
          brightness: b,
          occasion: occasion,
        );
        final meta = OccasionCountdownCard.metaColorOf(t);
        // El color efectivo: lo que se ve tras mezclar con la tarjeta.
        final effective = Color.alphaBlend(meta, t.soft);
        expect(meta.a, 1, reason: 'opaco en $name / ${b.name}');
        expect(
          _contrast(effective, t.soft),
          greaterThanOrEqualTo(4.5),
          reason: '$name / ${b.name}',
        );
      }
    }
  });

  test('avisos y calendario siguen los tokens en claro y oscuro', () {
    for (final b in Brightness.values) {
      for (final id in AccentId.values) {
        final theme = buildTheme(id.palette, b);
        final t = theme.extension<RegalosTokens>()!;
        final snack = theme.snackBarTheme;
        final bg = snack.backgroundColor!;
        final text = snack.contentTextStyle!.color!;
        final action = snack.actionTextColor!;
        final reason = '${id.name} / ${b.name}';
        expect(_contrast(text, bg), greaterThanOrEqualTo(4.5), reason: reason);
        expect(
          _contrast(action, bg),
          greaterThanOrEqualTo(4.5),
          reason: reason,
        );
        if (b == Brightness.dark) {
          expect(bg, t.popover);
          expect(text, t.text);
          expect(action, t.ink);
          expect(
            ((snack.shape! as RoundedRectangleBorder).side).color,
            t.separator,
          );
        }
        final date = theme.datePickerTheme;
        expect(date.backgroundColor, t.sheet);
        final selected = <WidgetState>{WidgetState.selected};
        expect(date.dayBackgroundColor!.resolve(selected), t.selection);
        expect(date.dayForegroundColor!.resolve(selected), t.ink);
        expect(
          _contrast(
            date.dayForegroundColor!.resolve(selected)!,
            date.dayBackgroundColor!.resolve(selected)!,
          ),
          greaterThanOrEqualTo(4.5),
          reason: reason,
        );
        expect(date.dayForegroundColor!.resolve({}), t.text);
      }
    }
  });

  test('hay seis acentos con los valores de la maqueta', () {
    expect(AccentId.values.length, 6);
    expect(AccentId.defaultAccent, AccentId.lavender);
    final l = AccentId.lavender.palette;
    expect(l.pastel, const Color(0xFFD8D2F8));
    expect(l.tinta, const Color(0xFF4B3FB0));
    // El oscuro «Pastel en velo»: el pastel encima y, debajo, su velo.
    expect(l.tintaD, const Color(0xFFD8D2F8));
    expect(l.onFill, const Color(0xFFD8D2F8));
    expect(
      l.pastelD,
      Color.lerp(const Color(0xFF161514), l.veilSource, kVeilFill),
    );
  });

  test('AccentId.fromName cae en lavanda con un valor desconocido', () {
    expect(AccentId.fromName('sky'), AccentId.sky);
    expect(AccentId.fromName('nope'), AccentId.lavender);
    expect(AccentId.fromName(null), AccentId.lavender);
  });

  test('buildTheme devuelve Material 3 con los tokens y los neutros', () {
    final light = buildTheme(AccentId.sage.palette, Brightness.light);
    final dark = buildTheme(AccentId.sage.palette, Brightness.dark);
    expect(light.useMaterial3, isTrue);
    expect(light.extension<RegalosTokens>(), isNotNull);
    expect(light.scaffoldBackgroundColor, const Color(0xFFFFFFFF));
    expect(dark.scaffoldBackgroundColor, const Color(0xFF161514));
    expect(light.colorScheme.primaryContainer, AccentId.sage.palette.pastel);
    expect(dark.colorScheme.primaryContainer, AccentId.sage.palette.pastelD);
  });

  test('el tema de ocasión sustituye al acento', () {
    final t = buildTheme(
      AccentId.lavender.palette,
      Brightness.light,
      occasion: OccasionTheme.christmas,
    ).extension<RegalosTokens>()!;
    expect(t.fill, OccasionTheme.christmas.palette.pastel);
    expect(t.cardBorder, OccasionTheme.christmas.cardBorder);
    expect(t.ornament, OccasionTheme.christmas.ornament);
    final plain = buildTheme(
      AccentId.lavender.palette,
      Brightness.light,
    ).extension<RegalosTokens>()!;
    expect(plain.cardBorder, isNull);
    expect(plain.ornament, isNull);
  });

  test('la tipografía sigue las maquetas y usa un único punto de fuente', () {
    final t = RegalosTextStyles(
      text: const Color(0xFF000000),
      secondary: const Color(0xFF555555),
    );
    // «A + Actual»: 32 en el tablero, 28 en el móvil, 15 los grupos y los
    // carriles, 12 la segunda línea.
    expect(t.boardTitle.fontSize, 32);
    expect(t.screenTitle.fontSize, 28);
    expect(t.screenTitle.fontWeight, FontWeight.w700);
    expect(t.screenTitle.letterSpacing, closeTo(-0.56, 1e-9));
    expect(t.rowTitle.fontSize, 16);
    expect(t.sectionTitle.fontSize, 15);
    expect(t.meta.fontSize, 13);
    expect(t.caption.fontSize, 12);
    expect(
      t
          .countdownNumber(CountdownSize.compact, const Color(0xFF000000))
          .fontSize,
      44,
    );
    expect(t.rowTitle.fontFamily, kAppFontFamily);
  });
}
