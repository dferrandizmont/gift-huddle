import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/layout/window_class.dart';
import 'package:regalos/core/widgets/screen_header.dart';
import 'package:regalos/features/settings/presentation/settings_column.dart';

import 'screens.dart';
import 'tablet.dart';

// Ayudantes de la tanda T2 del plan de tablet (la guía de diseño para tablet,
// §6): la columna de Ajustes y de Compartir mide 560 y va centrada en su
// panel; en el detalle de un escritorio (desde 1280) mide 640 y va a 72 px del
// filete.

/// Ancho del raíl en la ventana de la prueba (cero en compacto).
double railWidth(WidgetTester tester) =>
    WindowClass.fromSize(windowSize(tester)).usesRail
    ? RegalosLayout.railWidth
    : 0;

/// Dónde empieza el panel de la pantalla que se ve: el área de contenido (la
/// ventana menos el raíl) o, con dos paneles, el panel de detalle (a la
/// derecha de la lista y su filete). Con [rail] en `false`, la ventana.
double paneStart(WidgetTester tester, {bool rail = true}) {
  if (!rail) {
    return 0;
  }
  final window = windowSize(tester);
  final start = railWidth(tester);
  if (!WindowClass.fromSize(window).usesTwoPanes) {
    return start;
  }
  return start +
      RegalosLayout.listPaneWidth(
        window.width - start,
        desktop: RegalosLayout.isDesktop(window.width),
      ) +
      1;
}

/// El rectángulo horizontal de la columna de Ajustes en la ventana de la
/// prueba: 560 como mucho, centrada en el área de contenido (la ventana menos
/// el raíl). Con dos paneles, en el panel de detalle va alineada a la
/// izquierda: en una tablet, a 95 px del filete como mucho; en un escritorio
/// (desde 1280), de 640 y a 72 px. Con [rail] en `false`, centrada en la
/// ventana: las pantallas que se abren por encima del marco (la invitación).
({double left, double right, double width}) settingsColumn(
  WidgetTester tester, {
  bool rail = true,
}) {
  final window = windowSize(tester);
  final start = paneStart(tester, rail: rail);
  final pane = window.width - start;
  final detail = rail && WindowClass.fromSize(window).usesTwoPanes;
  final desktop = detail && RegalosLayout.isDesktop(window.width);
  final width = math.min(
    pane,
    desktop ? kSettingsDesktopColumn : RegalosLayout.formColumn,
  );
  final gutter = detail
      ? math.min((pane - width) / 2, desktop ? kSettingsDesktopLeading : 95.0)
      : (pane - width) / 2;
  final left = start + gutter;
  return (left: left, right: left + width, width: width);
}

/// Cada widget de [finder] va de un borde a otro de la columna, menos
/// [inset] a cada lado.
void expectFillsColumn(
  WidgetTester tester,
  Finder finder, {
  double inset = 0,
  bool rail = true,
  String? reason,
}) {
  final column = settingsColumn(tester, rail: rail);
  final elements = finder.evaluate().toList();
  expect(elements, isNotEmpty, reason: reason ?? '$finder');
  for (final element in elements) {
    final rect = tester.getRect(find.byElementPredicate((e) => e == element));
    final why = '${reason ?? finder} en ${sizeLabel(windowSize(tester))}';
    expect(rect.left, closeTo(column.left + inset, 0.01), reason: why);
    expect(rect.right, closeTo(column.right - inset, 0.01), reason: why);
  }
}

/// Cada widget de [finder] cabe dentro de la columna.
void expectInsideColumn(
  WidgetTester tester,
  Finder finder, {
  bool rail = true,
  String? reason,
}) {
  final column = settingsColumn(tester, rail: rail);
  final elements = finder.evaluate().toList();
  expect(elements, isNotEmpty, reason: reason ?? '$finder');
  for (final element in elements) {
    final rect = tester.getRect(find.byElementPredicate((e) => e == element));
    final why = '${reason ?? finder} en ${sizeLabel(windowSize(tester))}';
    expect(rect.left, greaterThanOrEqualTo(column.left - 0.01), reason: why);
    expect(rect.right, lessThanOrEqualTo(column.right + 0.01), reason: why);
  }
}

/// La cabecera de la pantalla que se ve va en la columna, y la lista que se
/// desplaza sigue ocupando todo el panel (los márgenes también arrastran).
///
/// [scrollable] es la lista; si no se da, la que lleva dentro la cabecera.
void expectColumnScreen(
  WidgetTester tester, {
  bool rail = true,
  Finder? scrollable,
}) {
  expectFillsColumn(
    tester,
    find.byType(ScreenHeader),
    rail: rail,
    reason: 'cabecera',
  );
  final window = windowSize(tester);
  final start = paneStart(tester, rail: rail);
  final list =
      scrollable ??
      find.ancestor(
        of: find.byType(ScreenHeader),
        matching: find.byType(Scrollable),
      );
  final listRect = tester.getRect(list.first);
  expect(listRect.left, start, reason: 'la lista empieza donde el panel');
  expect(listRect.right, window.width, reason: 'y acaba donde el panel');
}

/// Abre la pestaña Ajustes desde la barra o el raíl.
Future<void> openSettingsTab(WidgetTester tester) async {
  await tester.tap(
    find
        .descendant(
          of: find.bySemanticsLabel('Navegación principal'),
          matching: find.text('Ajustes'),
        )
        .first,
  );
  await settle(tester);
}

/// Pulsa lo que encuentre [finder], desplazando antes la lista si hace falta.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pump();
  await tester.tap(finder.first);
  await settle(tester);
}
