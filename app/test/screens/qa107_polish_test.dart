// Retoques de la QA 1.0.7: la franja «Sorpresas» de Reparto no parte la palabra
// (c1) y el texto de ayuda del nombre del móvil en la bienvenida baja de línea
// entero con letra grande (c3).
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/device/device_name.dart';
import 'package:regalos/core/widgets/secret_block.dart';
import 'package:regalos/l10n/app_localizations.dart';

import '../helpers/fonts.dart';
import '../helpers/pump_app.dart';

/// Cuántas líneas pinta el texto [text] (el que tiene el título de la franja).
int _lines(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  return (paragraph.size.height / paragraph.preferredLineHeight).round();
}

void main() {
  setUpAll(loadInter);

  group('c1: la franja del bloque secreto no parte palabras', () {
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final width in [67.0, 52.0, 40.0]) {
        for (final title in ['Surprises', 'Sorpresas', 'Sorpreses']) {
          testWidgets('«$title» en $width de ancho, letra $scale', (
            tester,
          ) async {
            await pumpThemed(
              tester,
              Center(
                child: SizedBox(
                  width: width,
                  height: 56,
                  child: SecretStrip(
                    shown: true,
                    name: 'Nora',
                    title: title,
                  ),
                ),
              ),
              textScale: scale,
            );
            await tester.pumpAndSettle();
            final text = find.descendant(
              of: find.byType(SecretStrip),
              matching: find.text(title),
            );
            expect(text, findsOneWidget);
            // Una sola palabra: una sola línea, nunca «Surp / rises».
            expect(_lines(tester, text), 1);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }

    testWidgets('con sitio, el candado sigue y el título de varias palabras '
        'baja de línea entre palabras', (tester) async {
      await pumpThemed(
        tester,
        const SizedBox(
          width: 150,
          height: 56,
          child: SecretStrip(shown: true, name: 'Aritz'),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
      final text = find.text(l10n.secretBlockTitle('Aritz'));
      expect(text, findsOneWidget);
      expect(_lines(tester, text), lessThanOrEqualTo(2));
      expect(tester.takeException(), isNull);
    });
  });

  group('c3: el texto de ayuda del nombre del móvil', () {
    for (final lang in ['en', 'es', 'ca']) {
      for (final scale in [1.5, 2.0]) {
        testWidgets('se lee entero ($lang, letra $scale)', (tester) async {
          await pumpThemed(
            tester,
            ProviderScope(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: DeviceNameField(
                  controller: TextEditingController(),
                  initial: 'Pixel de Nora',
                ),
              ),
            ),
            locale: Locale(lang),
            textScale: scale,
            surfaceSize: const Size(360, 800),
          );
          await tester.pumpAndSettle();
          final l10n = AppLocalizations.of(
            tester.element(find.byType(Scaffold)),
          );
          final hint = find.text(l10n.obDeviceNameHint);
          expect(hint, findsOneWidget);
          final paragraph = tester.renderObject<RenderParagraph>(hint);
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
