import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/layout/content_gutter.dart';

// `ContentGutter` y lo que se apoya en él: el margen de la columna sale de
// las restricciones de la maquetación, no de un ancho heredado.

Widget _host(double width, Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(width: width, height: 600, child: child),
  ),
);

void main() {
  testWidgets('da el margen de cada lado y cero si la columna cabe', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final seen = <double>[];
    Widget gutter() => ContentGutter(
      maxWidth: 640,
      builder: (_, gutter) {
        seen.add(gutter);
        return const SizedBox.expand();
      },
    );
    await tester.pumpWidget(_host(390, gutter()));
    await tester.pumpWidget(_host(640, gutter()));
    await tester.pumpWidget(_host(720, gutter()));
    await tester.pumpWidget(_host(1200, gutter()));
    expect(seen, [0, 0, 40, 280]);
  });

  testWidgets('ContentListView: la lista ocupa todo el sitio y su contenido, '
      'la columna centrada', (tester) async {
    tester.view
      ..physicalSize = const Size(1400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget list() => ContentListView(
      maxWidth: 640,
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: const [SizedBox(key: ValueKey('fila'), height: 40)],
    );
    final row = find.byKey(const ValueKey('fila'));

    await tester.pumpWidget(_host(390, list()));
    expect(tester.getRect(find.byType(ListView)).width, 390);
    expect(tester.getRect(row), const Rect.fromLTWH(0, 8, 390, 40));
    final state = tester.state(find.byType(Scrollable));

    await tester.pumpWidget(_host(1200, list()));
    expect(tester.getRect(find.byType(ListView)).width, 1200);
    expect(tester.getRect(row), const Rect.fromLTWH(280, 8, 640, 40));
    // El mismo árbol a cualquier ancho: la lista no pierde su posición.
    expect(tester.state(find.byType(Scrollable)), same(state));
  });

  testWidgets('ContentFloatingButton: el botón queda al borde de la columna '
      'y mide lo mismo', (tester) async {
    tester.view
      ..physicalSize = const Size(1400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget scaffold() => MaterialApp(
      home: Scaffold(
        floatingActionButton: ContentFloatingButton(
          maxWidth: 640,
          child: FloatingActionButton(onPressed: () {}),
        ),
      ),
    );
    final button = find.byType(FloatingActionButton);

    await tester.pumpWidget(scaffold());
    await tester.pumpAndSettle();
    // Ventana de 1400: columna de 640 con 380 a cada lado.
    expect(tester.getRect(button).right, 1400 - 380 - 16);
    expect(tester.getSize(button), const Size(56, 56));

    tester.view.physicalSize = const Size(390, 800);
    await tester.pumpAndSettle();
    expect(tester.getRect(button).right, 390 - 16);
    expect(tester.getSize(button), const Size(56, 56));
  });
}
