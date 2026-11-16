import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/layout/pane_scope.dart';
import 'package:regalos/core/layout/two_pane.dart';
import 'package:regalos/core/theme/regalos_tokens.dart';
import 'package:regalos/core/widgets/screen_header.dart';
import 'package:regalos/features/gifts/presentation/gift_editor_screen.dart';
import 'package:regalos/features/occasions/presentation/budget_screen.dart';
import 'package:regalos/features/occasions/presentation/occasion_detail_screen.dart';
import 'package:regalos/features/occasions/presentation/occasions_screen.dart';

import '../helpers/memory_stores.dart';
import '../helpers/screens.dart';
import '../helpers/tablet.dart';

// Los dos paneles de Ocasiones (la guía de diseño de escritorio, §2.2 y
// tanda W2a): la lista de ocasiones a la izquierda (la próxima, elegida al
// entrar, y «Presupuesto» como una fila más) y el detalle a la derecha, sin
// flecha, con la selección en la URL. Por debajo de 840 de ancho nada cambia.

const _desktop = Size(1280, 800);
const _huge = Size(2560, 1300);

/// La ruta en la que está el router ahora mismo.
String _path(FakePhone phone) => phone.container
    .read(routerProvider)
    .routeInformationProvider
    .value
    .uri
    .path;

Future<void> _openOccasions(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.bySemanticsLabel('Navegación principal'),
      matching: find.text('Ocasiones'),
    ),
  );
  await settle(tester);
  expect(find.byType(OccasionsScreen), findsOneWidget);
}

/// La fila de [title] en el panel de lista.
Finder _row(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(InkWell)).first;

Rect _listPane(WidgetTester tester) =>
    tester.getRect(find.byType(OccasionsScreen));
Rect _detailPane(WidgetTester tester) => tester.getRect(
  find.byType(OccasionDetailScreen).evaluate().isEmpty
      ? find.byType(BudgetScreen)
      : find.byType(OccasionDetailScreen),
);

bool _selected(WidgetTester tester, Pattern label) =>
    tester
        .getSemantics(find.bySemanticsLabel(label).first)
        .getSemanticsData()
        .flagsCollection
        .isSelected ==
    Tristate.isTrue;

void main() {
  group('a 1280 × 800', () {
    screenTest('lista y detalle a la vez, con la próxima ocasión elegida', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openOccasions(tester);
      expect(find.byType(OccasionDetailScreen), findsOneWidget);
      // Tió es la próxima (a 45 días), y su dirección es la selección.
      expect(_path(phone), '/occasions/seed-tio');
      expect(_selected(tester, RegExp(r'^Tió\.')), isTrue);
      expect(_selected(tester, RegExp(r'^Reyes\.')), isFalse);
      // La lista a la izquierda (80 de raíl, 408 de lista, 1 de filete) y el
      // detalle con el resto.
      final list = _listPane(tester);
      final pane = _detailPane(tester);
      expect(list.left, 80);
      expect(list.width, closeTo(408, 0.01));
      expect(pane.left, closeTo(80 + 408 + 1, 0.01));
      expect(pane.right, 1280);
      expect(find.byType(PaneScope), findsNWidgets(3));
      // El detalle lleva su cabecera, sin flecha ni el «Ocasiones» de encima.
      final header = find.descendant(
        of: find.byType(OccasionDetailScreen),
        matching: find.byType(ScreenHeader),
      );
      expect(header, findsOneWidget);
      expect(find.bySemanticsLabel('Volver a Ocasiones'), findsNothing);
      expect(
        find.descendant(of: header, matching: find.text('Ocasiones')),
        findsNothing,
      );
      // Las casillas de resumen, en una fila.
      expect(
        tester.getRect(find.text('por envolver')).top,
        tester.getRect(find.text('por llegar')).top,
      );
      // Ningún «+» flotante con dos paneles: «Añadir regalo» va en la cabecera
      // del detalle (ver `occasions_desktop_test.dart`).
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(
        find.descendant(
          of: header,
          matching: find.widgetWithText(FilledButton, 'Añadir regalo'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }, size: _desktop);

    screenTest('tocar otra ocasión cambia la URL y el detalle, sin apilar', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openOccasions(tester);
      await tester.tap(_row('Reyes'));
      await settle(tester);
      expect(_path(phone), '/occasions/seed-kings');
      expect(find.byType(OccasionDetailScreen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(OccasionDetailScreen),
          matching: find.text('Estación de bomberos de bloques'),
        ),
        findsOneWidget,
      );
      expect(_selected(tester, RegExp(r'^Reyes\.')), isTrue);
      expect(_selected(tester, RegExp(r'^Tió\.')), isFalse);
      // Nada apilado debajo, ni siquiera fuera de la vista.
      expect(
        find.byType(OccasionDetailScreen, skipOffstage: false),
        findsOneWidget,
      );
      expect(find.byType(OccasionsScreen, skipOffstage: false), findsOneWidget);
      // El atrás del sistema sale de la app: la pantalla se queda como está.
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(_path(phone), '/occasions/seed-kings');
      expect(find.byType(OccasionDetailScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, size: _desktop);

    screenTest('«Presupuesto» es una fila más del panel de lista', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openOccasions(tester);
      await tester.tap(find.text('Presupuesto de la casa').first);
      await settle(tester);
      expect(_path(phone), '/occasions/budget');
      expect(find.byType(BudgetScreen), findsOneWidget);
      expect(find.byType(OccasionDetailScreen), findsNothing);
      expect(find.byType(OccasionsScreen), findsOneWidget);
      expect(_selected(tester, RegExp(r'^Presupuesto de la casa\.')), isTrue);
      expect(_selected(tester, RegExp(r'^Tió\.')), isFalse);
      expect(find.bySemanticsLabel('Volver a Ocasiones'), findsNothing);
      // El presupuesto ocupa el panel de detalle; el total, en su tarjeta.
      final pane = _detailPane(tester);
      final header = tester.getRect(
        find.descendant(
          of: find.byType(BudgetScreen),
          matching: find.byType(ScreenHeader),
        ),
      );
      expect(header.left, pane.left);
      expect(header.right, pane.right);
      // Volver a una ocasión: otra vez la lista de la ocasión.
      await tester.tap(_row('Navidad'));
      await settle(tester);
      expect(_path(phone), '/occasions/seed-santa');
      expect(find.byType(BudgetScreen), findsNothing);
      expect(find.byType(OccasionDetailScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, size: _desktop);

    screenTest('el tema de la ocasión solo tiñe el panel de detalle', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openOccasions(tester);
      final listTokens = RegalosTokens.of(
        tester.element(find.byType(OccasionsScreen)),
      );
      expect(listTokens.occasion, isNull);
      final detailTokens = RegalosTokens.of(
        tester.element(
          find.descendant(
            of: find.byType(OccasionDetailScreen),
            matching: find.byType(ScreenHeader),
          ),
        ),
      );
      expect(detailTokens.occasion, isNotNull);
      // La pestaña (el raíl) tampoco cambia de color.
      final railTokens = RegalosTokens.of(
        tester.element(find.bySemanticsLabel('Navegación principal')),
      );
      expect(railTokens.occasion, isNull);
    }, size: _desktop);
  });

  group('a 2560 × 1300', () {
    screenTest('el detalle va en su columna, centrada en el panel, con su '
        'botón en la cabecera', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openOccasions(tester);
      final pane = _detailPane(tester);
      expect(pane.width, greaterThan(1000));
      expect(find.byType(FloatingActionButton), findsNothing);
      // La cabecera y el resto, en la misma columna.
      final headerFinder = find.descendant(
        of: find.byType(OccasionDetailScreen),
        matching: find.byType(ScreenHeader),
      );
      final header = tester.getRect(headerFinder);
      expect(
        header.width,
        closeTo(detailColumnWidth(tester.element(headerFinder)), 0.01),
      );
      expect(header.width, greaterThanOrEqualTo(880));
      expect(header.center.dx, closeTo(pane.center.dx, 0.01));
      final add = tester.getRect(
        find.descendant(
          of: headerFinder,
          matching: find.widgetWithText(FilledButton, 'Añadir regalo'),
        ),
      );
      expect(add.right, lessThanOrEqualTo(header.right));
      expect(tester.takeException(), isNull);
    }, size: _huge);
  });

  group('teclado', () {
    screenTest('↑ y ↓ cambian de ocasión; N abre «Nuevo regalo» para ella; '
        'Esc cierra el editor', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openOccasions(tester);
      expect(_path(phone), '/occasions/seed-tio');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await settle(tester);
      expect(_path(phone), '/occasions/seed-santa');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await settle(tester);
      expect(_path(phone), '/occasions/seed-kings');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await settle(tester);
      expect(_path(phone), '/occasions/seed-santa');
      // Hacia arriba, hasta «Presupuesto», y ahí se para.
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await settle(tester);
      }
      expect(_path(phone), '/occasions/budget');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await settle(tester);
      expect(_path(phone), '/occasions/seed-tio');

      // N: el editor de un regalo nuevo con la ocasión elegida.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await settle(tester);
      expect(find.byType(GiftEditorScreen), findsOneWidget);
      expect(find.text('Nuevo regalo'), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(GiftEditorScreen),
          matching: find.text('Tió'),
        ),
        findsOneWidget,
      );
      // Esc lo cierra.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.byType(GiftEditorScreen), findsNothing);
      expect(_path(phone), '/occasions/seed-tio');
      expect(tester.takeException(), isNull);
    }, size: _desktop);

    screenTest('escribiendo en un campo, ni las flechas ni N hacen nada de '
        'esto', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openOccasions(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await settle(tester);
      // El título tiene el foco: la «n» se escribe, no abre otro editor.
      await tester.enterText(find.byType(TextField).first, 'a');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pump();
      expect(find.byType(GiftEditorScreen), findsOneWidget);
      expect(_path(phone), '/occasions/seed-tio');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(_path(phone), '/occasions/seed-tio');
    }, size: _desktop);

    screenTest('en otra pestaña las flechas no tocan las ocasiones', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openOccasions(tester);
      await tester.tap(
        find.descendant(
          of: find.bySemanticsLabel('Navegación principal'),
          matching: find.text('Personas'),
        ),
      );
      await settle(tester);
      expect(_path(phone), startsWith('/people/'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await settle(tester);
      // Las flechas cambiaron de persona, no de ocasión ni de pestaña.
      expect(_path(phone), '/people/leo');
      await tester.tap(
        find.descendant(
          of: find.bySemanticsLabel('Navegación principal'),
          matching: find.text('Ocasiones'),
        ),
      );
      await settle(tester);
      expect(_path(phone), '/occasions/seed-tio');
    }, size: _desktop);
  });

  group('sin cambios por debajo de 840', () {
    for (final size in [kPhoneSize, kTabletPortrait]) {
      screenTest('${sizeLabel(size)}: la lista y, aparte, el detalle con su '
          'flecha', (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openOccasions(tester);
        expect(_path(phone), '/occasions');
        expect(find.byType(PaneScope), findsOneWidget);
        expect(find.byType(OccasionDetailScreen), findsNothing);
        expect(find.byType(FloatingActionButton), findsOneWidget);
        await tester.tap(_row('Reyes'));
        await settle(tester);
        expect(_path(phone), '/occasions/seed-kings');
        expect(find.byType(OccasionDetailScreen), findsOneWidget);
        expect(find.byType(OccasionsScreen), findsNothing);
        expect(find.bySemanticsLabel('Volver a Ocasiones'), findsOneWidget);
        await tester.tap(find.bySemanticsLabel('Volver a Ocasiones'));
        await settle(tester);
        expect(_path(phone), '/occasions');
        await tester.tap(find.text('Presupuesto de la casa').first);
        await settle(tester);
        expect(_path(phone), '/occasions/budget');
        expect(find.byType(BudgetScreen), findsOneWidget);
        expect(find.bySemanticsLabel('Volver a Ocasiones'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }, size: size);
    }

    screenTest('estrechar la ventana: la ocasión que puso la app vuelve a la '
        'lista y la que eligió el usuario se queda con su flecha', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openOccasions(tester);
      expect(_path(phone), '/occasions/seed-tio');
      await setWindowSize(tester, kTabletPortrait);
      await settle(tester);
      expect(_path(phone), '/occasions');
      expect(find.byType(OccasionDetailScreen), findsNothing);
      await setWindowSize(tester, _desktop);
      await settle(tester);
      expect(_path(phone), '/occasions/seed-tio');
      // Ahora la elige el usuario.
      await tester.tap(_row('Reyes'));
      await settle(tester);
      await setWindowSize(tester, kTabletPortrait);
      await settle(tester);
      expect(_path(phone), '/occasions/seed-kings');
      expect(find.bySemanticsLabel('Volver a Ocasiones'), findsOneWidget);
      await setWindowSize(tester, _desktop);
      await settle(tester);
      expect(_path(phone), '/occasions/seed-kings');
      expect(find.byType(OccasionsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, size: _desktop);
  });
}
