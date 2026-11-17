// «Tus 24 palabras»: «Guardar en un fichero» vive en la zona fija de abajo,
// siempre a la vista y nunca tapado (QA 1.0.2, fallo m1).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/recovery/presentation/recovery_file_save_screen.dart';

import '../helpers/memory_stores.dart' show FakePhone;
import 'recovery_file_ui_test.dart' show createUntilWords, fileTest;

Finder get _file =>
    find.widgetWithText(OutlinedButton, 'Guardar en un fichero');
Finder get _saved => find.widgetWithText(FilledButton, 'Ya las he guardado');
Finder get _qr => find.widgetWithText(OutlinedButton, 'Ver código QR');

/// El móvil de la queja: 1280×2856 px a 480 dpi (densidad 3, ≈ 427×952 dp).
void _qaPhone(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1280, 2856)
    ..devicePixelRatio = 3.0;
}

/// La parte que se desplaza: acaba justo donde empieza la zona fija.
Rect _scrollArea(WidgetTester tester) =>
    tester.getRect(find.byType(SingleChildScrollView).first);

Future<void> _openWords(
  WidgetTester tester,
  FakePhone phone, {
  bool qaPhone = false,
}) async {
  if (qaPhone) {
    _qaPhone(tester);
  }
  await createUntilWords(tester, phone);
  expect(find.text('Tus 24 palabras'), findsOneWidget);
}

/// Las tres acciones están en la zona fija, dentro de la pantalla y sin nada
/// encima.
void _expectFixedAndVisible(WidgetTester tester, {Finder? qr}) {
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  final zoneTop = _scrollArea(tester).bottom;
  for (final finder in [_saved, _file, qr ?? _qr]) {
    final rect = tester.getRect(finder);
    expect(rect.top, greaterThanOrEqualTo(zoneTop), reason: '$finder');
    expect(rect.bottom, lessThanOrEqualTo(screen.height), reason: '$finder');
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(screen.width));
    expect(finder.hitTestable(), findsOneWidget, reason: '$finder');
  }
}

void main() {
  group('palabras: acciones a la vista', () {
    fileTest('en el móvil de la queja (427×952 dp) se ve sin desplazar', (
      tester,
      phone,
    ) async {
      await _openWords(tester, phone, qaPhone: true);
      _expectFixedAndVisible(tester);
      // Sin tocar el desplazamiento: sigue arriba del todo.
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(scroll.position.pixels, 0);
      expect(find.text('Ya las he guardado'), findsOneWidget);
    });

    fileTest('en un móvil pequeño (360×640) no queda tapado al bajar del '
        'todo', (tester, phone) async {
      await createUntilWords(tester, phone);
      _expectFixedAndVisible(tester);
      // Se baja hasta el final: el último bloque queda por encima de la zona
      // fija y las acciones siguen ahí.
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -3000),
      );
      await tester.pumpAndSettle();
      final warning = find.textContaining('Quien tenga estas palabras');
      if (warning.evaluate().isNotEmpty) {
        expect(
          tester.getRect(warning.first).bottom,
          lessThanOrEqualTo(_scrollArea(tester).bottom),
        );
      }
      _expectFixedAndVisible(tester);
    }, size: const Size(360, 640));

    fileTest('en una tablet', (tester, phone) async {
      await _openWords(tester, phone);
      _expectFixedAndVisible(tester);
      final width = tester.getSize(_saved).width;
      expect(width, lessThanOrEqualTo(520));
    }, size: const Size(820, 1180));

    fileTest(
      'con letra al 200 % se apilan y no se tapa nada',
      (tester, phone) async {
        await _openWords(tester, phone);
        final file = tester.getRect(_file);
        final qr = tester.getRect(_qr);
        expect(qr.top, greaterThanOrEqualTo(file.bottom));
        _expectFixedAndVisible(tester);
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -5000),
        );
        await tester.pumpAndSettle();
        _expectFixedAndVisible(tester);
        expect(tester.takeException(), isNull);
      },
      size: const Size(360, 780),
      textScale: 2,
    );

    fileTest('«Guardar en un fichero» abre la pantalla del fichero', (
      tester,
      phone,
    ) async {
      await _openWords(tester, phone, qaPhone: true);
      await tester.tap(_file);
      await tester.pumpAndSettle();
      expect(find.byType(RecoveryFileSaveScreen), findsOneWidget);
    });

    fileTest('el QR sigue alternando con las palabras', (tester, phone) async {
      await _openWords(tester, phone, qaPhone: true);
      await tester.tap(_qr);
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(OutlinedButton, 'Ver las palabras'),
        findsOneWidget,
      );
      _expectFixedAndVisible(
        tester,
        qr: find.widgetWithText(OutlinedButton, 'Ver las palabras'),
      );
    });
  });
}
