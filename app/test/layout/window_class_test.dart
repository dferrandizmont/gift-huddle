import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/layout/window_class.dart';

import '../helpers/tablet.dart';

void main() {
  group('WindowClass.fromSize', () {
    // La tabla del §2.1 de la guía de diseño para tablet, entera.
    const table = <(String, Size, WindowClass)>[
      ('Redmi Pad 2 Pro en vertical', Size(800, 1280), WindowClass.medium),
      ('Redmi Pad 2 Pro en horizontal', Size(1280, 800), WindowClass.expanded),
      ('iPad de 11" en vertical', Size(834, 1194), WindowClass.medium),
      ('iPad de 11" en horizontal', Size(1194, 834), WindowClass.expanded),
      ('iPad de 13" en vertical', Size(1024, 1366), WindowClass.expanded),
      ('iPad mini en vertical', Size(744, 1133), WindowClass.medium),
      ('media pantalla estrecha', Size(590, 800), WindowClass.compact),
      ('media pantalla ancha', Size(640, 800), WindowClass.medium),
      ('un tercio de pantalla, 320', Size(320, 800), WindowClass.compact),
      ('un tercio de pantalla, 400', Size(400, 800), WindowClass.compact),
      ('móvil en horizontal', Size(844, 390), WindowClass.compact),
      ('móvil en vertical', Size(390, 844), WindowClass.compact),
      ('Redmi a densidad 280, vertical', Size(914, 1463), WindowClass.expanded),
    ];
    for (final (name, size, expected) in table) {
      test('$name (${sizeLabel(size)}) es ${expected.name}', () {
        expect(WindowClass.fromSize(size), expected);
      });
    }

    test('los cortes de ancho son 600 y 840, incluidos', () {
      expect(WindowClass.fromSize(const Size(599.9, 900)), WindowClass.compact);
      expect(WindowClass.fromSize(const Size(600, 900)), WindowClass.medium);
      expect(WindowClass.fromSize(const Size(839.9, 900)), WindowClass.medium);
      expect(WindowClass.fromSize(const Size(840, 900)), WindowClass.expanded);
    });

    test('con menos de 480 de alto es compacto a cualquier ancho', () {
      expect(
        WindowClass.fromSize(const Size(1280, 479.9)),
        WindowClass.compact,
      );
      expect(WindowClass.fromSize(const Size(1280, 480)), WindowClass.expanded);
      expect(WindowClass.fromSize(const Size(700, 479.9)), WindowClass.compact);
      expect(WindowClass.fromSize(const Size(700, 480)), WindowClass.medium);
    });

    test('los tamaños de prueba caen cada uno en su clase', () {
      expect(WindowClass.fromSize(kPhoneSize), WindowClass.compact);
      expect(WindowClass.fromSize(kTabletPortrait), WindowClass.medium);
      expect(WindowClass.fromSize(kTabletLandscape), WindowClass.expanded);
    });
  });

  test('raíl desde medio y dos paneles solo en expandido', () {
    expect(WindowClass.compact.usesRail, isFalse);
    expect(WindowClass.medium.usesRail, isTrue);
    expect(WindowClass.expanded.usesRail, isTrue);
    expect(WindowClass.compact.usesTwoPanes, isFalse);
    expect(WindowClass.medium.usesTwoPanes, isFalse);
    expect(WindowClass.expanded.usesTwoPanes, isTrue);
  });

  group('WindowClass.of', () {
    Future<void> pumpProbe(WidgetTester tester, List<WindowClass> seen) =>
        tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                seen.add(WindowClass.of(context));
                return const SizedBox();
              },
            ),
          ),
        );

    tabletWidgetTest('lee la ventana', (tester, size) async {
      final seen = <WindowClass>[];
      await pumpProbe(tester, seen);
      expect(seen.last, WindowClass.fromSize(size));
    }, sizes: kLayoutSizes);

    tabletWidgetTest('cambia al girar', (tester, size) async {
      final seen = <WindowClass>[];
      await pumpProbe(tester, seen);
      expect(seen.last, WindowClass.medium);
      await rotate(tester);
      expect(windowSize(tester), kTabletLandscape);
      expect(seen.last, WindowClass.expanded);
      await rotate(tester);
      expect(seen.last, WindowClass.medium);
    }, sizes: const [kTabletPortrait]);

    testWidgets('en un panel estrecho sigue mirando la ventana', (
      tester,
    ) async {
      tester.view
        ..physicalSize = kTabletLandscape
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late WindowClass seen;
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 300,
              child: Builder(
                builder: (context) {
                  seen = WindowClass.of(context);
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      expect(seen, WindowClass.expanded);
    });
  });

  group('RegalosLayout', () {
    test('las medidas del §2.2', () {
      expect(RegalosLayout.railWidth, 80);
      expect(RegalosLayout.detailMaxWidth, 720);
      expect(RegalosLayout.listColumn, 640);
      expect(RegalosLayout.formColumn, 560);
      expect(RegalosLayout.sheetWidth, 560);
      expect(RegalosLayout.editorWidth, 640);
      expect(RegalosLayout.dialogWidth, 340);
      expect(RegalosLayout.snackBarWidth, 480);
      expect(RegalosLayout.onboardingColumn, 520);
    });

    test('el panel de lista es el 34 %, entre 340 y 420', () {
      // Redmi en horizontal: 1280 − 80 de raíl.
      expect(RegalosLayout.listPaneWidth(1200), closeTo(408, 0.001));
      // Redmi a densidad 280 en vertical: 914 − 80.
      expect(RegalosLayout.listPaneWidth(834), closeTo(340, 0.001));
      // iPad de 13" en horizontal: 1366 − 80.
      expect(RegalosLayout.listPaneWidth(1286), closeTo(420, 0.001));
      expect(RegalosLayout.listPaneWidth(1000), closeTo(340, 0.001));
      expect(RegalosLayout.listPaneWidth(1100), closeTo(374, 0.001));
    });

    test('el QR de emparejar crece desde 600 dp', () {
      expect(RegalosLayout.pairingQrSize(WindowClass.compact), 260);
      expect(RegalosLayout.pairingQrSize(WindowClass.medium), 320);
      expect(RegalosLayout.pairingQrSize(WindowClass.expanded), 320);
    });
  });
}
