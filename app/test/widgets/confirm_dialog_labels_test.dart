// Los botones de un diálogo de confirmación nunca parten su texto en dos
// líneas: o caben lado a lado o se apilan a todo el ancho. Se prueba con las
// etiquetas largas reales (es, ca, en) y con letra al 100, 130 y 200 %.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/widgets/confirm_dialog.dart';
import 'package:regalos/l10n/app_localizations.dart';

import '../helpers/fonts.dart';
import '../helpers/pump_app.dart';

/// Las parejas «Cancelar» / acción más largas que usa la app, por idioma.
List<(String, String)> _pairs(AppLocalizations l) => [
  (l.actionCancel, l.deviceRemoveWebConfirmAction),
  (l.actionCancel, l.eraseAllContinue),
  (l.actionCancel, l.protectionDeactivateConfirm),
  (l.actionCancel, l.recoverAbandonConfirm),
  (l.actionCancel, l.recoveryRemoveConfirm),
  (l.actionCancel, l.recoveryMaintCancelConfirm),
  (l.actionCancel, l.webSettingsForgetConfirm),
  (l.actionCancel, l.pairingV2MigrateContinue),
  (l.recoveryLeaveStay, l.recoveryLeaveConfirm),
];

int _lines(WidgetTester tester, Finder button) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: button, matching: find.byType(RichText)).first,
  );
  final length = paragraph.text.toPlainText().length;
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: length),
  );
  return {for (final box in boxes) box.top.round()}.length;
}

Future<void> _open(
  WidgetTester tester, {
  required Locale locale,
  required double scale,
  required Size size,
  required String cancel,
  required String confirm,
}) async {
  await pumpThemed(
    tester,
    Builder(
      builder: (context) => TextButton(
        onPressed: () => showRegalosConfirm(
          context,
          title: '?',
          body: 'Texto',
          confirmLabel: confirm,
          cancelLabel: cancel,
        ),
        child: const Text('abrir'),
      ),
    ),
    locale: locale,
    textScale: scale,
    surfaceSize: size,
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadInter);

  for (final locale in const [Locale('es'), Locale('ca'), Locale('en')]) {
    final l10n = lookupAppLocalizations(locale);
    for (final size in const [Size(390, 844), Size(360, 640)]) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('${locale.languageCode} $size x$scale: una línea por '
            'botón', (tester) async {
          for (final (cancel, confirm) in _pairs(l10n)) {
            await _open(
              tester,
              locale: locale,
              scale: scale,
              size: size,
              cancel: cancel,
              confirm: confirm,
            );
            final outlined = find.byType(OutlinedButton);
            final filled = find.byType(FilledButton);
            expect(tester.takeException(), isNull);
            // O van en la misma fila, o uno bajo el otro y del mismo ancho.
            final a = tester.getRect(outlined);
            final b = tester.getRect(filled);
            final stacked = (a.top - b.top).abs() >= 1;
            if (stacked) {
              expect(a.bottom, lessThan(b.top));
              expect(a.width, b.width);
            } else {
              expect(a.right, lessThan(b.left));
            }
            for (final (button, label) in [
              (outlined, cancel),
              (filled, confirm),
            ]) {
              final lines = _lines(tester, button);
              final paragraph = tester.renderObject<RenderParagraph>(
                find
                    .descendant(of: button, matching: find.byType(RichText))
                    .first,
              );
              final room = tester.getSize(button).width - 32;
              final natural = paragraph.getMaxIntrinsicWidth(double.infinity);
              // Lado a lado, nunca partido. Apilado, solo si no cabe ni a
              // todo el ancho.
              if (!stacked || natural <= room) {
                expect(
                  lines,
                  1,
                  reason: '«$label» partido ($size x$scale, stacked=$stacked)',
                );
              }
            }
            await tester.tap(find.text(cancel));
            await tester.pumpAndSettle();
          }
        });
      }
    }
  }

  testWidgets('«Remove web app» en un iPhone, en inglés y con letra grande, '
      'se apila', (tester) async {
    await _open(
      tester,
      locale: const Locale('en'),
      scale: 1.3,
      size: const Size(390, 844),
      cancel: 'Cancel',
      confirm: 'Remove web app',
    );
    expect(
      tester.getTopLeft(find.byType(FilledButton)).dy,
      greaterThan(tester.getTopLeft(find.byType(OutlinedButton)).dy),
    );
    expect(_lines(tester, find.byType(FilledButton)), 1);
  });

  testWidgets('con etiquetas cortas siguen lado a lado', (tester) async {
    await _open(
      tester,
      locale: const Locale('es'),
      scale: 1,
      size: const Size(390, 844),
      cancel: 'Cancelar',
      confirm: 'Borrar',
    );
    expect(
      tester.getTopLeft(find.byType(OutlinedButton)).dy,
      tester.getTopLeft(find.byType(FilledButton)).dy,
    );
  });

  testWidgets('con una etiqueta que no cabe ni a todo el ancho no desborda', (
    tester,
  ) async {
    await _open(
      tester,
      locale: const Locale('en'),
      scale: 1,
      size: const Size(320, 640),
      cancel: 'Cancel',
      confirm: 'Delete everything on this phone and the whole family list',
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(FilledButton), findsOneWidget);
  });
}
