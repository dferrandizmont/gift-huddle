import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/gifts/presentation/gift_editor_screen.dart';
import 'package:regalos/features/gifts/presentation/person_list_screen.dart';

import '../helpers/memory_stores.dart';
import '../helpers/screens.dart';
import '../helpers/tablet.dart';

/// El diálogo de escritorio solo existe en la web (F9): estas pruebas lo fuerzan.
final _webOn = [giftEditorAsDialogProvider.overrideWithValue(true)];

// El editor de regalo como diálogo en escritorio
// (la guía de diseño de escritorio, §2, §3.7 y las decisiones
// de producto): desde 1280 de ventana es un diálogo de 880 con el alto de su
// contenido, a un 10 % del borde superior, con «Cancelar» y «Guardar» abajo a
// la derecha. Por debajo de 1280, la hoja de siempre; en el móvil, de lado a
// lado.

final _editor = find.byType(GiftEditorScreen);
final _save = find.descendant(
  of: _editor,
  matching: find.widgetWithText(FilledButton, 'Guardar'),
);
final _cancel = find.descendant(
  of: _editor,
  matching: find.widgetWithText(TextButton, 'Cancelar'),
);

/// El panel de detalle de Personas, debajo del diálogo: donde se centra.
Rect _pane(WidgetTester tester) =>
    tester.getRect(find.byType(PersonListScreen));

/// Abre el editor con la N, para la persona elegida.
Future<void> _openWithN(WidgetTester tester, FakePhone phone) async {
  await seedSample(tester, phone);
  await pumpRegalos(tester, phone);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
  await settle(tester);
  expect(_editor, findsOneWidget);
}

/// El primer campo de texto del editor (el título), y no el buscador de
/// regalos que la lista de Personas lleva debajo del diálogo.
Finder get _firstField =>
    find.descendant(of: _editor, matching: find.byType(TextField)).first;

/// Las escalas de los `Transform` por encima del editor.
List<double> _scales(WidgetTester tester) => [
  for (final t in tester.widgetList<Transform>(
    find.ancestor(of: _editor, matching: find.byType(Transform)),
  ))
    t.transform.entry(0, 0),
];

void main() {
  group('como diálogo desde 1280', () {
    for (final size in const [Size(1536, 864), Size(2560, 1440)]) {
      screenTest(
        'a ${size.width.toInt()} × ${size.height.toInt()} mide 880, baja un '
        '10 % y «Guardar» está a la vista, a la derecha',
        (tester, phone) async {
          await _openWithN(tester, phone);
          final card = tester.getRect(_editor);
          expect(card.width, 880);
          expect(card.center.dx, closeTo(_pane(tester).center.dx, 0.5));
          expect(card.top, closeTo(size.height * 0.10, 0.5));
          // El alto es el de su contenido: no llega al borde de la ventana.
          expect(card.bottom, lessThanOrEqualTo(size.height - 24 + 0.5));
          expect(card.height, lessThan(size.height * 0.9));
          // «Cancelar» y «Guardar», abajo a la derecha, dentro de la tarjeta.
          final save = tester.getRect(_save);
          final cancel = tester.getRect(_cancel);
          expect(save.right, closeTo(card.right - 24, 0.5));
          expect(cancel.right, lessThan(save.left));
          expect(save.bottom, lessThanOrEqualTo(card.bottom));
          expect(save.bottom, lessThanOrEqualTo(size.height));
          expect(save.top, greaterThan(card.top));
          // Sin la flecha de volver de la hoja.
          expect(find.bySemanticsLabel('Cerrar'), findsNothing);
          expect(tester.takeException(), isNull);
        },
        size: size,
        overrides: _webOn,
      );
    }

    screenTest(
      'Esc cierra el editor',
      (tester, phone) async {
        await _openWithN(tester, phone);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(tester);
        expect(_editor, findsNothing);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1536, 864),
      overrides: _webOn,
    );

    screenTest(
      '«Cancelar» lo cierra y no guarda nada',
      (tester, phone) async {
        await _openWithN(tester, phone);
        await tester.enterText(_firstField, 'Cometa');
        await tester.tap(_cancel);
        await settle(tester);
        expect(_editor, findsNothing);
        expect(find.text('Cometa'), findsNothing);
      },
      size: const Size(1536, 864),
      overrides: _webOn,
    );

    screenTest(
      '«Guardar» guarda el regalo y cierra el diálogo',
      (tester, phone) async {
        await _openWithN(tester, phone);
        await tester.enterText(_firstField, 'Cometa');
        await tester.tap(_save);
        await settle(tester);
        expect(_editor, findsNothing);
        expect(find.text('Cometa'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1536, 864),
      overrides: _webOn,
    );

    screenTest(
      'un precio negativo pegado no se guarda',
      (tester, phone) async {
        await _openWithN(tester, phone);
        await tester.enterText(_firstField, 'Cometa');
        final price = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Previsto',
        );
        await tester.ensureVisible(price);
        await tester.enterText(price, '-12,');
        await tester.tap(_save);
        await settle(tester);
        expect(_editor, findsOneWidget);
        expect(tester.widget<TextField>(price).controller!.text, '-12,');
        expect(
          find.text('Escribe un importe, por ejemplo 12,50.'),
          findsOneWidget,
        );
        expect(find.text('Cometa'), findsOneWidget);
      },
      size: const Size(1536, 864),
      overrides: _webOn,
    );

    screenTest(
      'si no cabe en la ventana, el formulario se desplaza por dentro y '
      '«Guardar» sigue a la vista',
      (tester, phone) async {
        await _openWithN(tester, phone);
        final card = tester.getRect(_editor);
        expect(card.bottom, lessThanOrEqualTo(560 - 24 + 0.5));
        expect(tester.getRect(_save).bottom, lessThanOrEqualTo(560));
        expect(tester.takeException(), isNull);
      },
      size: const Size(1280, 560),
      overrides: _webOn,
    );

    screenTest(
      'entra con una escala de 0,97 a 1 y se asienta en 1',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));
        expect(_scales(tester).any((s) => s < 1 && s >= 0.97), isTrue);
        await settle(tester);
        expect(_scales(tester).every((s) => (s - 1).abs() < 0.001), isTrue);
      },
      size: const Size(1536, 864),
      overrides: _webOn,
    );

    screenTest(
      'con «Reducir movimiento» solo se funde, sin escala',
      (tester, phone) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        expect(_editor, findsOneWidget);
        expect(_scales(tester).every((s) => (s - 1).abs() < 0.001), isTrue);
        expect(
          find.ancestor(of: _editor, matching: find.byType(FadeTransition)),
          findsWidgets,
        );
        await settle(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(tester);
        expect(_editor, findsNothing);
      },
      size: const Size(1536, 864),
      overrides: _webOn,
    );
  });

  group('como hoja por debajo de 1280', () {
    screenTest(
      'a 1279 × 800 sigue siendo la hoja de 640, a 12 del borde y hasta abajo',
      (tester, phone) async {
        await _openWithN(tester, phone);
        final card = tester.getRect(_editor);
        expect(card.width, 640);
        expect(card.top, 12);
        expect(card.bottom, 800);
        // La hoja de siempre: un solo «Guardar» de lado a lado, sin «Cancelar».
        expect(_cancel, findsNothing);
        expect(tester.getRect(_save).width, greaterThan(500));
        expect(tester.takeException(), isNull);
      },
      size: const Size(1279, 800),
    );

    screenTest('en el móvil sube desde abajo y ocupa el ancho entero', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tapText(tester, 'Aritz');
      await tester.tap(find.byType(FloatingActionButton));
      await settle(tester);
      final card = tester.getRect(_editor);
      expect(card.left, 0);
      expect(card.width, 390);
      expect(card.top, 12);
      expect(card.bottom, 844);
      expect(_cancel, findsNothing);
    }, size: kPhoneSize);
  });
}
