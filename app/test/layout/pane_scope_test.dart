import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/layout/pane_scope.dart';
import 'package:regalos/core/layout/window_class.dart';

import '../helpers/tablet.dart';

const _probe = Key('probe');
const _sheet = Key('sheet');

/// Lo que ve un widget de dentro de un panel.
class _Seen {
  final List<double> widths = [];
  Size? size;
  PaneRole? role;
}

class _Probe extends StatelessWidget {
  const _Probe(this.seen, {super.key = _probe, this.full = true});

  final _Seen seen;

  /// Si además del ancho lee el tamaño y el papel.
  final bool full;

  @override
  Widget build(BuildContext context) {
    seen.widths.add(PaneScope.widthOf(context));
    if (full) {
      seen
        ..size = PaneScope.sizeOf(context)
        ..role = PaneScope.roleOf(context);
    }
    return const SizedBox.expand();
  }
}

/// Un marco como el de la app: raíl de 80 desde 600 dp y el panel al lado.
class _Shell extends StatelessWidget {
  const _Shell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final rail = WindowClass.of(context).usesRail;
    return Row(
      children: [
        SizedBox(width: rail ? RegalosLayout.railWidth : 0),
        Expanded(child: PaneScope(child: child)),
      ],
    );
  }
}

PaneAnchor? _anchor(WidgetTester tester) =>
    PaneScope.anchorOf(tester.element(find.byKey(_probe)));

void main() {
  group('sin panel', () {
    tabletWidgetTest('contesta con la ventana', (tester, size) async {
      final seen = _Seen();
      await tester.pumpWidget(MaterialApp(home: _Probe(seen)));
      expect(seen.widths.last, size.width);
      expect(seen.size, size);
      expect(seen.role, PaneRole.single);
      expect(_anchor(tester), isNull);
    }, sizes: kLayoutSizes);
  });

  group('un panel al lado del raíl', () {
    tabletWidgetTest('mide el panel, no la ventana', (tester, size) async {
      final seen = _Seen();
      await tester.pumpWidget(MaterialApp(home: _Shell(child: _Probe(seen))));
      final rail = size.width >= 600 ? 80.0 : 0.0;
      expect(seen.widths.last, size.width - rail);
      expect(seen.size, Size(size.width - rail, size.height));
      expect(seen.role, PaneRole.single);
      expect(
        _anchor(tester)!.value,
        Rect.fromLTWH(rail, 0, size.width - rail, size.height),
      );
    }, sizes: kLayoutSizes);

    testWidgets('al girar cambia el ancho en el mismo fotograma', (
      tester,
    ) async {
      tester.view
        ..physicalSize = kTabletLandscape
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final seen = _Seen();
      await tester.pumpWidget(MaterialApp(home: _Shell(child: _Probe(seen))));
      final anchor = _anchor(tester)!;
      var notified = 0;
      anchor.addListener(() => notified++);
      expect(seen.widths.last, 1200);

      await rotate(tester);
      expect(seen.widths.last, 720);
      expect(seen.size, const Size(720, 1280));
      // El ancla ya tiene el rectángulo nuevo y ha avisado una vez.
      expect(anchor.value, const Rect.fromLTWH(80, 0, 720, 1280));
      expect(notified, 1);

      await setWindowSize(tester, kPhoneSize);
      expect(seen.widths.last, 390);
      expect(anchor.value, Offset.zero & kPhoneSize);
      expect(notified, 2);
      // Es el mismo panel: no se ha vuelto a crear.
      expect(_anchor(tester), same(anchor));
    });

    testWidgets('quien solo lee el ancho no se reconstruye si cambia el alto', (
      tester,
    ) async {
      tester.view
        ..physicalSize = kTabletLandscape
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final seen = _Seen();
      await tester.pumpWidget(
        MaterialApp(home: _Shell(child: _Probe(seen, full: false))),
      );
      final builds = seen.widths.length;
      await setWindowSize(tester, const Size(1280, 700));
      expect(seen.widths.length, builds);
      await setWindowSize(tester, const Size(1180, 700));
      expect(seen.widths.length, builds + 1);
      expect(seen.widths.last, 1100);
    });
  });

  testWidgets('dos paneles: cada uno con su papel, su ancho y su rectángulo', (
    tester,
  ) async {
    tester.view
      ..physicalSize = kTabletLandscape
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final list = _Seen();
    final detail = _Seen();
    const listKey = Key('list');
    final listWidth = RegalosLayout.listPaneWidth(1280 - 80);
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            const SizedBox(width: RegalosLayout.railWidth),
            SizedBox(
              width: listWidth,
              child: PaneScope(
                role: PaneRole.list,
                child: _Probe(list, key: listKey),
              ),
            ),
            Expanded(
              child: PaneScope(role: PaneRole.detail, child: _Probe(detail)),
            ),
          ],
        ),
      ),
    );
    expect(list.role, PaneRole.list);
    expect(list.widths.last, closeTo(408, 0.001));
    expect(detail.role, PaneRole.detail);
    expect(detail.widths.last, closeTo(792, 0.001));
    final listRect = PaneScope.anchorOf(tester.element(find.byKey(listKey)))!
        .value;
    expect(listRect.left, 80);
    expect(listRect.width, closeTo(408, 0.001));
    final detailRect = _anchor(tester)!.value;
    expect(detailRect.left, closeTo(488, 0.001));
    expect(detailRect.right, 1280);
  });

  testWidgets('anchorOf vuelve a medir si el panel se ha movido sin maquetar', (
    tester,
  ) async {
    tester.view
      ..physicalSize = kTabletPortrait
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final shift = ValueNotifier<double>(120);
    addTearDown(shift.dispose);
    final seen = _Seen();
    final pane = PaneScope(child: _Probe(seen));
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<double>(
          valueListenable: shift,
          child: pane,
          builder: (context, dx, child) =>
              Transform.translate(offset: Offset(dx, 0), child: child),
        ),
      ),
    );
    // Como una pantalla que entra: se midió a mitad de camino.
    final context = tester.element(find.byKey(_probe));
    expect(PaneScope.anchorOf(context)!.value.left, 120);
    shift.value = 0;
    await tester.pump();
    expect(
      PaneScope.anchorOf(context)!.value,
      const Rect.fromLTWH(0, 0, 800, 1280),
    );
  });

  group('PaneAligned.insetsFor', () {
    test('centra la columna en el panel', () {
      expect(
        PaneAligned.insetsFor(
          pane: const Rect.fromLTWH(80, 0, 1200, 800),
          windowWidth: 1280,
          maxWidth: RegalosLayout.sheetWidth,
        ),
        const EdgeInsets.only(left: 400, right: 320),
      );
      expect(
        PaneAligned.insetsFor(
          pane: const Rect.fromLTWH(488, 0, 792, 800),
          windowWidth: 1280,
          maxWidth: RegalosLayout.sheetWidth,
        ),
        const EdgeInsets.only(left: 604, right: 116),
      );
    });

    test('un panel más estrecho que la columna se ocupa entero', () {
      expect(
        PaneAligned.insetsFor(
          pane: const Rect.fromLTWH(0, 0, 390, 844),
          windowWidth: 390,
          maxWidth: RegalosLayout.sheetWidth,
        ),
        EdgeInsets.zero,
      );
      expect(
        PaneAligned.insetsFor(
          pane: const Rect.fromLTWH(80, 0, 520, 900),
          windowWidth: 600,
          maxWidth: RegalosLayout.sheetWidth,
        ),
        const EdgeInsets.only(left: 80),
      );
    });

    test('sin medir todavía, la ventana entera', () {
      expect(
        PaneAligned.insetsFor(
          pane: Rect.zero,
          windowWidth: 1280,
          maxWidth: RegalosLayout.sheetWidth,
        ),
        const EdgeInsets.symmetric(horizontal: 360),
      );
    });

    test('una medida de antes de girar se recorta a la ventana', () {
      final insets = PaneAligned.insetsFor(
        pane: const Rect.fromLTWH(80, 0, 1200, 800),
        windowWidth: 800,
        maxWidth: RegalosLayout.sheetWidth,
      );
      expect(insets, const EdgeInsets.only(left: 160, right: 80));
      // Fuera del todo: la ventana entera.
      expect(
        PaneAligned.insetsFor(
          pane: const Rect.fromLTWH(900, 0, 300, 800),
          windowWidth: 800,
          maxWidth: RegalosLayout.sheetWidth,
        ),
        const EdgeInsets.symmetric(horizontal: 120),
      );
    });
  });

  group('una hoja en la capa raíz', () {
    Widget sheet(PaneAnchor? anchor) => PaneAligned(
      anchor: anchor,
      maxWidth: RegalosLayout.sheetWidth,
      child: const Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(key: _sheet, height: 200, width: double.infinity),
      ),
    );

    /// Un botón dentro del panel que abre la hoja en el navegador raíz, como
    /// hará `showRegalosSheet`: coge el ancla al tocar.
    Widget opener() => Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () {
            final anchor = PaneScope.anchorOf(context);
            showGeneralDialog<void>(
              context: context,
              useRootNavigator: true,
              transitionDuration: Duration.zero,
              pageBuilder: (_, _, _) => sheet(anchor),
            );
          },
          child: const Text('Abrir'),
        ),
      ),
    );

    tabletWidgetTest('se centra en el panel, no en la ventana', (
      tester,
      size,
    ) async {
      await tester.pumpWidget(MaterialApp(home: _Shell(child: opener())));
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      final rail = size.width >= 600 ? 80.0 : 0.0;
      final pane = size.width - rail;
      final width = pane < 560 ? pane : 560.0;
      expect(
        tester.getRect(find.byKey(_sheet)),
        Rect.fromLTWH(rail + (pane - width) / 2, size.height - 200, width, 200),
      );
    }, sizes: kLayoutSizes);

    testWidgets('sigue al panel al girar, sin cerrarse', (tester) async {
      tester.view
        ..physicalSize = kTabletLandscape
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: _Shell(child: opener())));
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(_sheet)),
        const Rect.fromLTWH(400, 600, 560, 200),
      );

      await rotate(tester);
      expect(tester.takeException(), isNull);
      // El ancla avisa al acabar el fotograma del giro: la hoja se recoloca
      // en el siguiente.
      await tester.pump();
      expect(
        tester.getRect(find.byKey(_sheet)),
        const Rect.fromLTWH(160, 1080, 560, 200),
      );

      await setWindowSize(tester, kPhoneSize);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.byKey(_sheet)),
        const Rect.fromLTWH(0, 644, 390, 200),
      );
    });

    testWidgets('sin panel se centra en la ventana', (tester) async {
      tester.view
        ..physicalSize = kTabletLandscape
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: opener()));
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(_sheet)),
        const Rect.fromLTWH(360, 600, 560, 200),
      );
    });
  });
}
