// El bloque «Regalos en secreto para …»: el candado y las dos líneas van
// dentro de la tarjeta, centrados en vertical y alineados a la izquierda, en
// móvil y en ancho de escritorio, claro y oscuro, es, ca y en, con letra normal
// y grande.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/widgets/secret_block.dart';
import 'package:regalos/core/widgets/stroke_icon.dart';
import 'package:regalos/l10n/app_localizations.dart';

import '../helpers/fonts.dart';
import '../helpers/pump_app.dart';

void main() {
  setUpAll(loadInter);

  for (final width in const [360.0, 1100.0]) {
    for (final brightness in Brightness.values) {
      for (final locale in const ['es', 'ca', 'en']) {
        for (final big in const [false, true]) {
          final label =
              '${width.round()} $locale ${brightness.name} '
              '${big ? 'x2' : 'x1'}';
          testWidgets('contenido dentro y centrado · $label', (tester) async {
            const key = ValueKey<String>('card');
            await pumpThemed(
              tester,
              const SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  // El nombre largo es el peor caso de ancho.
                  child: SecretBlockCard(
                    key: key,
                    name: 'Maria de la Concepcion',
                    web: true,
                  ),
                ),
              ),
              locale: Locale(locale),
              brightness: brightness,
              textScale: big ? 2 : 1,
              surfaceSize: Size(width, 900),
            );
            expect(tester.takeException(), isNull);
            final l10n = AppLocalizations.of(tester.element(find.byKey(key)));
            final card = tester.getRect(find.byKey(key));
            final icon = tester.getRect(
              find.descendant(
                of: find.byKey(key),
                matching: find.byType(StrokeIcon),
              ),
            );
            final title = tester.getRect(
              find.descendant(
                of: find.byKey(key),
                matching: find.text(
                  l10n.secretBlockTitle('Maria de la Concepcion'),
                ),
              ),
            );
            final note = tester.getRect(
              find.descendant(
                of: find.byKey(key),
                matching: find.text(secretBlockNoteText(l10n, web: true)),
              ),
            );
            // Todo dentro de la tarjeta, con su margen.
            for (final r in [icon, title, note]) {
              expect(r.top, greaterThanOrEqualTo(card.top + 8));
              expect(r.bottom, lessThanOrEqualTo(card.bottom - 8));
              expect(r.left, greaterThanOrEqualTo(card.left + 8));
              expect(r.right, lessThanOrEqualTo(card.right - 8));
            }
            // Centrados en vertical: el candado y el bloque de texto.
            expect(icon.center.dy, closeTo(card.center.dy, 1));
            final text = title.expandToInclude(note);
            expect(text.center.dy, closeTo(card.center.dy, 1.5));
            // Texto alineado a la izquierda y pegado al candado.
            expect(title.left, closeTo(note.left, 0.01));
            expect(title.left, greaterThan(icon.right));
            expect(title.left - icon.right, lessThan(26));
            expect(card.height, greaterThanOrEqualTo(SecretBlockCard.height));
          });
        }
      }
    }
  }
}
