import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/layout/content_width.dart';
import 'package:regalos/core/layout/window_class.dart';

import '../helpers/tablet.dart';

const _child = Key('child');
const _column = Key('column');

/// Un hijo que guarda las restricciones que recibe.
class _Probe extends StatelessWidget {
  const _Probe(this.seen);

  final List<BoxConstraints> seen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      seen.add(constraints);
      return const SizedBox.expand(key: _child);
    },
  );
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => setState(() => taps++),
    child: SizedBox.expand(
      child: Text('$taps', textDirection: TextDirection.ltr),
    ),
  );
}

Widget _root(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);

void main() {
  test('gutter: lo que sobra, a partes iguales', () {
    expect(ContentWidth.gutter(800, 640), 80);
    expect(ContentWidth.gutter(1280, 640), 320);
    expect(ContentWidth.gutter(1200, 560), 320);
    expect(ContentWidth.gutter(640, 640), 0);
    expect(ContentWidth.gutter(390, 640), 0);
    expect(ContentWidth.gutter(double.infinity, 640), 0);
  });

  group('por debajo del máximo no hace nada', () {
    tabletWidgetTest('mismas restricciones y mismo sitio', (
      tester,
      size,
    ) async {
      final bare = <BoxConstraints>[];
      await tester.pumpWidget(_root(_Probe(bare)));
      final bareRect = tester.getRect(find.byKey(_child));

      final wrapped = <BoxConstraints>[];
      await tester.pumpWidget(
        _root(
          ContentWidth(
            key: _column,
            maxWidth: RegalosLayout.listColumn,
            child: _Probe(wrapped),
          ),
        ),
      );
      expect(wrapped.last, bare.last);
      expect(tester.getRect(find.byKey(_child)), bareRect);
      expect(tester.getRect(find.byKey(_column)), bareRect);
    }, sizes: const [kPhoneSize, Size(640, 900)]);

    testWidgets('tampoco con restricciones sueltas', (tester) async {
      tester.view
        ..physicalSize = kPhoneSize
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _root(
          const Align(
            alignment: Alignment.topLeft,
            child: ContentWidth(
              key: _column,
              maxWidth: 640,
              child: SizedBox(key: _child, width: 200, height: 40),
            ),
          ),
        ),
      );
      expect(
        tester.getRect(find.byKey(_child)),
        const Rect.fromLTWH(0, 0, 200, 40),
      );
      expect(
        tester.getRect(find.byKey(_column)),
        const Rect.fromLTWH(0, 0, 200, 40),
      );
    });
  });

  group('por encima del máximo', () {
    tabletWidgetTest('limita el ancho y centra', (tester, size) async {
      final seen = <BoxConstraints>[];
      await tester.pumpWidget(
        _root(
          ContentWidth(
            key: _column,
            maxWidth: RegalosLayout.listColumn,
            child: _Probe(seen),
          ),
        ),
      );
      final gutter = (size.width - 640) / 2;
      // El hijo sigue recibiendo un ancho fijo: el de la columna.
      expect(seen.last, BoxConstraints.tight(Size(640, size.height)));
      expect(
        tester.getRect(find.byKey(_child)),
        Rect.fromLTWH(gutter, 0, 640, size.height),
      );
      // El widget ocupa todo el sitio: los márgenes son suyos.
      expect(tester.getRect(find.byKey(_column)), Offset.zero & size);
    });

    testWidgets('con restricciones sueltas el hijo no pasa del máximo', (
      tester,
    ) async {
      tester.view
        ..physicalSize = kTabletPortrait
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _root(
          const Align(
            alignment: Alignment.topCenter,
            child: ContentWidth(
              maxWidth: 560,
              child: SizedBox(key: _child, width: 2000, height: 40),
            ),
          ),
        ),
      );
      expect(
        tester.getRect(find.byKey(_child)),
        const Rect.fromLTWH(120, 0, 560, 40),
      );
    });

    testWidgets('los márgenes no son del hijo: no reciben sus toques', (
      tester,
    ) async {
      tester.view
        ..physicalSize = kTabletPortrait
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _root(const ContentWidth(maxWidth: 640, child: _Counter())),
      );
      await tester.tapAt(const Offset(40, 400));
      await tester.pump();
      expect(find.text('0'), findsOneWidget);
      await tester.tapAt(const Offset(400, 400));
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('cambiar el máximo recoloca', (tester) async {
      tester.view
        ..physicalSize = kTabletLandscape
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Widget build(double maxWidth) => _root(
        ContentWidth(
          maxWidth: maxWidth,
          child: const SizedBox.expand(key: _child),
        ),
      );
      await tester.pumpWidget(build(RegalosLayout.listColumn));
      expect(tester.getRect(find.byKey(_child)).left, 320);
      await tester.pumpWidget(build(RegalosLayout.formColumn));
      expect(
        tester.getRect(find.byKey(_child)),
        const Rect.fromLTWH(360, 0, 560, 800),
      );
    });
  });

  testWidgets('girar cruzando el máximo conserva el estado del hijo', (
    tester,
  ) async {
    tester.view
      ..physicalSize = kPhoneSize
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _root(const ContentWidth(maxWidth: 640, child: _Counter())),
    );
    await tester.tapAt(const Offset(200, 400));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    await setWindowSize(tester, kTabletPortrait);
    expect(find.text('1'), findsOneWidget);
    expect(tester.getRect(find.byType(_Counter)).left, 80);

    await rotate(tester);
    expect(find.text('1'), findsOneWidget);
    expect(tester.getRect(find.byType(_Counter)).left, 320);

    await setWindowSize(tester, kPhoneSize);
    expect(find.text('1'), findsOneWidget);
    expect(tester.getRect(find.byType(_Counter)).left, 0);
  });

  testWidgets('medidas intrínsecas y en seco, con el ancho de la columna', (
    tester,
  ) async {
    tester.view
      ..physicalSize = kTabletPortrait
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _root(
        const Align(
          alignment: Alignment.topLeft,
          child: ContentWidth(
            key: _column,
            maxWidth: 640,
            // El alto depende del ancho: la mitad.
            child: AspectRatio(aspectRatio: 2, child: SizedBox(key: _child)),
          ),
        ),
      ),
    );
    final box = tester.renderObject<RenderContentWidth>(find.byKey(_column));
    expect(box.maxWidth, 640);
    // Con 800 de sitio el hijo mide 640 × 320.
    expect(box.getMinIntrinsicHeight(800), 320);
    expect(box.getMaxIntrinsicHeight(800), 320);
    // Con 390 no hay margen: 390 × 195.
    expect(box.getMinIntrinsicHeight(390), 195);
    expect(
      box.getDryLayout(const BoxConstraints(maxWidth: 800)),
      const Size(800, 320),
    );
    expect(
      box.getDryLayout(const BoxConstraints(maxWidth: 390)),
      const Size(390, 195),
    );
    expect(tester.getSize(find.byKey(_child)), const Size(640, 320));
    expect(tester.getTopLeft(find.byKey(_child)), const Offset(80, 0));
  });

  testWidgets('sin hijo no se rompe', (tester) async {
    await tester.pumpWidget(
      _root(const Center(child: ContentWidth(maxWidth: 640))),
    );
    expect(tester.takeException(), isNull);
  });
}
