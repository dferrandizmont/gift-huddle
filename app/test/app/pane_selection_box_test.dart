import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/layout/pane_selection.dart';
import 'package:regalos/core/widgets/settings_row.dart';

import '../helpers/screens.dart';
import '../helpers/tablet.dart';

// El recuadro de la fila elegida de un panel de lista de dos paneles se pinta
// donde está su fila (Redmi Pad, 1280 × 800): sin hueco con la vecina y
// centrado con el contenido. Antes se quedaba donde estaba la fila un
// fotograma antes, al acabar la entrada escalonada (unos 4 px más abajo).

/// El rectángulo de la fila de [id] en la pantalla.
Rect _row(WidgetTester tester, Object id) {
  final element = find
      .byWidgetPredicate((w) => w is SelectionRow && w.id == id)
      .evaluate()
      .single;
  return tester.getRect(find.byElementPredicate((e) => e == element));
}

/// Los píxeles de la ventana ya pintada.
Future<ui.Image> _pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  late ui.Image image;
  await tester.runAsync(() async => image = await boundary.toImage());
  return image;
}

/// De arriba abajo, el primero y el último píxel distintos del fondo en la
/// columna de [row] pegada a su borde izquierdo (donde no hay texto), dentro
/// de [row] y 3 px de aire; `null` si no hay recuadro.
Future<(int, int)?> _box(WidgetTester tester, Rect row) async {
  final image = await _pixels(tester);
  late ByteData data;
  await tester.runAsync(() async => data = (await image.toByteData())!);
  final x = (row.left + 6).round();
  int pixel(int y) => data.getUint32((y * image.width + x) * 4);
  int channel(int rgba, int shift) => (rgba >> shift) & 0xff;
  bool differs(int a, int b) =>
      (channel(a, 24) - channel(b, 24)).abs() +
          (channel(a, 16) - channel(b, 16)).abs() +
          (channel(a, 8) - channel(b, 8)).abs() >
      24;
  final background = pixel(row.top.round() - 6);
  int? first;
  int? last;
  for (var y = row.top.round() - 3; y <= row.bottom.round() + 3; y++) {
    if (differs(pixel(y), background)) {
      first ??= y;
      last = y;
    }
  }
  return first == null ? null : (first, last!);
}

void main() {
  for (final brightness in Brightness.values) {
    group('${brightness.name}, a 1280 × 800', () {
      screenTest(
        'Ajustes: el recuadro de «Personas» mide lo que su fila y va '
        'centrado con ella',
        (tester, phone) async {
          await seedSample(tester, phone);
          await pumpRegalos(tester, phone);
          phone.container.read(routerProvider).go('/settings');
          await settle(tester);
          final row = _row(tester, 'people');
          expect(row.height, 48);
          final box = await _box(tester, row);
          expect(box, isNotNull);
          expect(
            box!.$1,
            inInclusiveRange(row.top.round() - 1, row.top.round()),
          );
          expect(
            box.$2,
            inInclusiveRange(row.bottom.round() - 2, row.bottom.round()),
          );
          // El icono de la fila, centrado en el recuadro.
          final icon = tester.getRect(
            find
                .descendant(
                  of: find.widgetWithText(SettingsRow, 'Personas'),
                  matching: find.byType(CustomPaint),
                )
                .first,
          );
          expect(icon.center.dy, closeTo((box.$1 + box.$2 + 1) / 2, 1.5));
        },
        size: kTabletLandscape,
        brightness: brightness,
      );

      screenTest(
        'Ocasiones: el recuadro de «Tió» deja el mismo hueco arriba y '
        'abajo, sin invadir a la vecina',
        (tester, phone) async {
          await seedSample(tester, phone);
          await pumpRegalos(tester, phone);
          phone.container.read(routerProvider).go('/occasions');
          await settle(tester);
          final tio = _row(tester, 'seed-tio');
          final noel = _row(tester, 'seed-santa');
          // La misma separación entre todas las filas de un grupo.
          expect(noel.top - tio.bottom, 4);
          final box = await _box(tester, tio);
          expect(box, isNotNull);
          expect(
            box!.$1,
            inInclusiveRange(tio.top.round() - 1, tio.top.round()),
          );
          expect(
            box.$2,
            inInclusiveRange(tio.bottom.round() - 2, tio.bottom.round()),
          );
          // Y no entra en la fila de debajo.
          expect(box.$2, lessThan(noel.top.round()));
        },
        size: kTabletLandscape,
        brightness: brightness,
      );
    });
  }
}
