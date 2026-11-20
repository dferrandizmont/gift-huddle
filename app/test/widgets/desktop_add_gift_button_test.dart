import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:regalos/core/widgets/desktop_add_gift_button.dart';
import 'package:regalos/core/widgets/header_button.dart';
import 'package:regalos/core/widgets/stroke_icon.dart';

import '../helpers/fonts.dart';
import '../helpers/pump_app.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  setUpAll(loadInter);

  for (final accent in AccentId.values) {
    for (final brightness in Brightness.values) {
      testWidgets('«Añadir regalo» usa el pastel del acento con su texto, AA, '
          'en ${accent.name} / ${brightness.name}', (tester) async {
        await pumpThemed(
          tester,
          DesktopAddGiftButton(onPressed: () {}),
          accent: accent,
          brightness: brightness,
        );
        final t = RegalosTokens.of(
          tester.element(find.byType(DesktopAddGiftButton)),
        );
        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        final style = button.style!;
        final background = style.backgroundColor!.resolve({})!;
        final foreground = style.foregroundColor!.resolve({})!;
        // El mismo relleno que «Guardar» (el del tema), no la tinta oscura.
        expect(background, t.fill);
        expect(foreground, t.onFill);
        expect(background, isNot(t.ink));
        expect(_contrast(foreground, background), greaterThanOrEqualTo(4.5));
        // Del mismo alto que «Cambiar fecha» y los botones de icono de la
        // cabecera del tablero (44).
        expect(
          tester.getSize(find.byType(FilledButton)).height,
          DesktopAddGiftButton.height,
        );
      });
    }
  }

  // En escritorio la densidad visual es compacta y le quitaba 8 al alto: se
  // mide el `Material` que se ve, no la caja exterior (con su margen táctil).
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
    TargetPlatform.android,
  ]) {
    testWidgets('«Añadir regalo», «Cambiar fecha» y editar miden 48 en '
        '${platform.name}', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await pumpThemed(
          tester,
          Wrap(
            children: [
              DesktopAddGiftButton(onPressed: () {}),
              OutlinedButton(
                key: const ValueKey<String>('date'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(44, DesktopAddGiftButton.height),
                ),
                onPressed: () {},
                child: const Text('Cambiar fecha'),
              ),
              HeaderIconButton(
                key: const ValueKey<String>('edit'),
                size: 48,
                icon: AppIcons.edit,
                label: 'Editar',
                onTap: () {},
              ),
            ],
          ),
        );
        Size visible(Finder of) => tester.getSize(
          find.descendant(of: of, matching: find.byType(Material)).first,
        );
        expect(visible(find.byType(FilledButton)).height, 48);
        expect(visible(find.byKey(const ValueKey<String>('date'))).height, 48);
        expect(visible(find.byKey(const ValueKey<String>('edit'))).height, 48);
        expect(visible(find.byKey(const ValueKey<String>('edit'))).width, 48);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
