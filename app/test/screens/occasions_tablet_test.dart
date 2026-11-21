import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/layout/pane_scope.dart';
import 'package:regalos/core/widgets/budget_meter.dart';
import 'package:regalos/core/widgets/countdown_card.dart';
import 'package:regalos/core/widgets/screen_header.dart';
import 'package:regalos/features/occasions/presentation/budget_screen.dart';
import 'package:regalos/features/occasions/presentation/occasion_detail_screen.dart';
import 'package:regalos/features/occasions/presentation/occasions_screen.dart';

import '../helpers/screens.dart';
import '../helpers/tablet.dart';

// Tanda T3 del plan de tablet (la guía de diseño para tablet, §6):
// Ocasiones, el detalle de una ocasión y Presupuesto en una columna de 640
// centrada en el panel. En el móvil, nada.

/// La columna de las listas dentro del panel: 640 centrados o, si el panel es
/// más estrecho, el panel entero.
Rect _column(WidgetTester tester) {
  final pane = tester.getRect(find.byType(PaneScope));
  final width = math.min(640.0, pane.width);
  return Rect.fromLTWH(
    pane.left + (pane.width - width) / 2,
    pane.top,
    width,
    pane.height,
  );
}

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

/// La tarjeta de la fila de [title] en Ocasiones.
Finder _row(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(InkWell)).first;

void main() {
  tabletScreenTest(
    'Ocasiones: la cabecera, «Presupuesto de la casa» y las filas van en la '
    'columna de 640; en el móvil, de lado a lado',
    (tester, phone, size) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openOccasions(tester);
      final column = _column(tester);
      if (size == kPhoneSize) {
        expect(column.left, 0);
        expect(column.width, 390);
      } else {
        expect(column.width, 640);
        expect(column.center.dx, 80 + (size.width - 80) / 2);
      }

      final header = tester.getRect(find.byType(ScreenHeader));
      expect(header.left, column.left);
      expect(header.right, column.right);

      final budget = tester.getRect(_row('Presupuesto de la casa'));
      expect(budget.left, column.left);
      expect(budget.right, column.right);

      for (final title in ['Tió', 'Navidad', 'Reyes']) {
        final row = tester.getRect(_row(title));
        expect(row.left, column.left + 16, reason: title);
        expect(row.right, column.right - 16, reason: title);
      }
      expect(tester.takeException(), isNull);
    },
    // Con dos paneles (1280) ver `two_pane_occasions_test.dart`.
    sizes: const [kPhoneSize, kTabletPortrait],
  );

  tabletScreenTest(
    'el detalle de una ocasión va en la columna, con el «+» a 16 de su borde '
    'derecho',
    (tester, phone, size) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openOccasions(tester);
      await tester.tap(_row('Reyes'));
      await settle(tester);
      expect(find.byType(OccasionDetailScreen), findsOneWidget);
      final column = _column(tester);

      final header = tester.getRect(find.byType(ScreenHeader));
      expect(header.left, column.left);
      expect(header.right, column.right);

      final countdown = tester.getRect(find.byType(CountdownCard));
      expect(countdown.left, column.left + 16);
      expect(countdown.right, column.right - 16);

      final section = tester.getRect(find.text('Por persona'));
      expect(section.left, column.left + 16);

      final add = tester.getRect(find.byType(FloatingActionButton));
      expect(add.right, column.right - 16);
      expect(add.size, const Size(56, 56));

      // La lista ocupa el panel entero (se desplaza arrastrando por el
      // margen); la columna es su relleno.
      final list = tester.getRect(
        find.descendant(
          of: find.byType(OccasionDetailScreen),
          matching: find.byType(ListView),
        ),
      );
      final pane = tester.getRect(find.byType(PaneScope));
      expect(list.left, pane.left);
      expect(list.right, pane.right);
      expect(tester.takeException(), isNull);
    },
    // Con dos paneles (1280) ver `two_pane_occasions_test.dart`.
    sizes: const [kPhoneSize, kTabletPortrait],
  );

  tabletScreenTest('Presupuesto va en la columna', (tester, phone, size) async {
    await seedSample(tester, phone);
    await setBudgets(tester, phone, {'seed-santa': 15000, 'seed-kings': 30000});
    await pumpRegalos(tester, phone);
    await _openOccasions(tester);
    await tester.tap(_row('Presupuesto de la casa'));
    await settle(tester);
    expect(find.byType(BudgetScreen), findsOneWidget);
    final column = _column(tester);

    final header = tester.getRect(find.byType(ScreenHeader));
    expect(header.left, column.left);
    expect(header.right, column.right);

    // La barra grande del total: dentro de su tarjeta, a 32 de los bordes.
    final total = tester.getRect(find.byType(BudgetBar).first);
    expect(total.left, column.left + 32);
    expect(total.right, column.right - 32);

    final byPerson = tester.getRect(find.text('Por persona'));
    expect(byPerson.left, column.left + 16);
    for (final meter in find.byType(BudgetMeter).evaluate()) {
      final rect = tester.getRect(find.byElementPredicate((e) => e == meter));
      expect(rect.left, column.left + 16);
      expect(rect.right, column.right - 16);
    }
    expect(tester.takeException(), isNull);
    // Con dos paneles (1280) ver `two_pane_occasions_test.dart`.
  }, sizes: const [kPhoneSize, kTabletPortrait]);

  screenTest(
    'girar en el detalle no pierde la pantalla ni su posición, y la columna '
    'se recoloca',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openOccasions(tester);
      await tester.tap(_row('Reyes'));
      await settle(tester);
      final detail = find.byType(OccasionDetailScreen);
      final element = tester.element(detail);

      // En horizontal hay dos paneles: el detalle pasa al de la derecha (la
      // misma pantalla, no una nueva).
      await rotate(tester);
      await settle(tester);
      expect(windowSize(tester), kTabletLandscape);
      expect(tester.element(detail), same(element));
      final pane = tester.getRect(detail);
      expect(pane.left, closeTo(80 + 408 + 1, 0.01));
      expect(tester.getRect(find.byType(ScreenHeader).last).left, pane.left);
      // Con dos paneles no hay «+» flotante: «Añadir regalo» va en la
      // cabecera del detalle.
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Añadir regalo'),
        findsOneWidget,
      );

      await rotate(tester);
      await settle(tester);
      final column = _column(tester);
      expect(column.left, 80 + 40);
      expect(tester.getRect(find.byType(CountdownCard)).left, column.left + 16);
      expect(tester.takeException(), isNull);
    },
    size: kTabletPortrait,
  );

  group('en oscuro, con la letra al 130 % y con «Reducir movimiento»', () {
    screenTest(
      'Ocasiones, el detalle y Presupuesto, sin desbordes a 800 × 1280',
      (tester, phone) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openOccasions(tester);
        expect(tester.takeException(), isNull);

        await tester.tap(_row('Presupuesto de la casa'));
        await settle(tester);
        expect(find.byType(BudgetScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.binding.handlePopRoute();
        await settle(tester);

        await tester.tap(_row('Reyes'));
        await settle(tester);
        expect(find.byType(OccasionDetailScreen), findsOneWidget);
        final column = _column(tester);
        expect(
          tester.getRect(find.byType(FloatingActionButton)).right,
          column.right - 16,
        );
        expect(tester.takeException(), isNull);
      },
      size: kTabletPortrait,
      textScale: 1.3,
      brightness: Brightness.dark,
    );
  });
}
