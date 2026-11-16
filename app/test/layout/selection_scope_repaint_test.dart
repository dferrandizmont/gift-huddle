import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/layout/pane_selection.dart';
import 'package:regalos/core/motion/stagger.dart';

// El recuadro de selección sigue a su fila aunque el último movimiento de la
// fila ocurra en su propia capa (la entrada escalonada: opacidad y
// traslación), que no repinta el recuadro por sí sola.

const _ids = ['a', 'b', 'c'];
const _fill = Color(0xFFD00000);

Widget _app(String selected) => MaterialApp(
  home: Scaffold(
    backgroundColor: Colors.white,
    body: StaggerScope(
      key: const ValueKey('stagger'),
      child: SelectionScope(
        selectedId: selected,
        fill: _fill,
        border: _fill,
        child: Column(
          children: [
            const SizedBox(height: 60),
            for (var i = 0; i < _ids.length; i++)
              StaggerItem(
                index: i,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: SelectionRow(
                    id: _ids[i],
                    child: const SizedBox(width: 300, height: 40),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  ),
);

Rect _row(WidgetTester tester, String id) {
  final element = find
      .byWidgetPredicate((w) => w is SelectionRow && w.id == id)
      .evaluate()
      .single;
  return tester.getRect(find.byElementPredicate((e) => e == element));
}

/// De arriba abajo, los píxeles rojos de la columna de [row] pegada a su borde
/// izquierdo, entre 12 px antes y después de la fila.
Future<(int, int)?> _box(WidgetTester tester, Rect row) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  late ui.Image image;
  late ByteData data;
  await tester.runAsync(() async {
    image = await boundary.toImage();
    data = (await image.toByteData())!;
  });
  final x = (row.left + 6).round();
  int? first;
  int? last;
  for (var y = row.top.round() - 12; y <= row.bottom.round() + 12; y++) {
    final p = data.getUint32((y * image.width + x) * 4);
    final r = (p >> 24) & 0xff;
    final g = (p >> 16) & 0xff;
    if (r > 150 && g < 100) {
      first ??= y;
      last = y;
    }
  }
  return first == null ? null : (first, last!);
}

Future<void> _expectOn(WidgetTester tester, String id) async {
  final row = _row(tester, id);
  final box = await _box(tester, row);
  expect(box, isNotNull, reason: id);
  expect(box!.$1, inInclusiveRange(row.top.round() - 1, row.top.round()));
  expect(box.$2, inInclusiveRange(row.bottom.round() - 2, row.bottom.round()));
}

void main() {
  testWidgets('A, B y A otra vez: el recuadro acaba en la fila elegida, también '
      'tras repetirse la entrada', (tester) async {
    tester.view
      ..physicalSize = const Size(400, 400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app('a'));
    await tester.pumpAndSettle();
    await _expectOn(tester, 'a');

    await tester.pumpWidget(_app('b'));
    await tester.pumpAndSettle();
    await _expectOn(tester, 'b');

    await tester.pumpWidget(_app('a'));
    await tester.pumpAndSettle();
    await _expectOn(tester, 'a');

    // La entrada se repite (el desbloqueo en cascada): su último movimiento es
    // de las filas, en sus capas.
    tester.state<StaggerScopeState>(find.byType(StaggerScope)).replay();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    await _expectOn(tester, 'a');
  });
}
