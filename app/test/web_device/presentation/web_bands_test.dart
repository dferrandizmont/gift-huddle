// La web de escritorio por bandas y con escala de interfaz
// (la guía de diseño de escritorio, §2): escala automática por
// ventana, toques que caen en su sitio, bandas y anchos a tres tamaños,
// «Guardado» abajo del raíl y nada cambia en móvil ni en tablet.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/app.dart';
import 'package:regalos/core/layout/pane_scope.dart';
import 'package:regalos/core/layout/ui_scale.dart';
import 'package:regalos/core/layout/window_class.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/core/widgets/regalos_nav_bar.dart';
import 'package:regalos/core/widgets/regalos_nav_rail.dart';
import 'package:regalos/features/web_board/application/web_board.dart';
import 'package:regalos/features/web_device/application/web_app_provider.dart';
import 'package:regalos/features/web_device/application/web_device_providers.dart';
import 'package:regalos/features/web_device/application/web_sync_engine.dart'
    show WebSyncStatus;
import 'package:regalos/features/web_device/presentation/web_desktop_frame.dart';

import '../../helpers/fonts.dart';
import '../../helpers/memory_stores.dart';
import '../../helpers/screens.dart';
import 'gate_test_support.dart';

const _confirmed = WebDeviceState(
  status: WebSyncStatus.confirmed,
  hasRoots: true,
  setAsideChanges: 0,
  persistenceDenied: false,
);

List<Override> _web() => [
  webAppProvider.overrideWithValue(true),
  // Estas pruebas miran el diseño por bandas; el tablero «Hoy» tiene las suyas
  // (`test/web_board/`).
  webBoardEnabledProvider.overrideWithValue(false),
  webGateActionsProvider.overrideWithValue(FakeGateActions()),
  webDeviceStateProvider.overrideWithValue(_confirmed),
];

Future<void> _mountWeb(WidgetTester tester, FakePhone phone) async {
  await seedSample(tester, phone);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: phone.container,
      child: const RegalosApp(webSession: true),
    ),
  );
  await settle(tester);
}

Finder _pane(PaneRole role) => find.byWidgetPredicate(
  (w) => w is PaneScope && w.role == role,
  description: 'PaneScope($role)',
);

/// El ancho lógico de la ventana tal como lo ve el marco (ya sin escala).
Size _logicalWindow(WidgetTester tester) =>
    MediaQuery.sizeOf(tester.element(find.byType(WebDesktopFrame)));

/// La esquina de [finder] en puntos lógicos de la app: la posición global
/// (en píxeles, ya con la escala) dividida por [scale]. Los tamaños de
/// `getSize` ya vienen en lógicos.
Offset _logicalTopLeft(WidgetTester tester, Finder finder, double scale) =>
    tester.getTopLeft(finder) / scale;

void main() {
  setUpAll(loadInter);

  group('escala de interfaz', () {
    test(
      'continua: 1,0 hasta 1920, 1,2 a 2560, 1,25 a 3000 y 1,3 desde 3440',
      () {
        expect(UiScaleSteps.forWindow(375), 1);
        expect(UiScaleSteps.forWindow(1536), 1);
        expect(UiScaleSteps.forWindow(1920), 1);
        expect(UiScaleSteps.forWindow(2200), closeTo(1.09, 0.02));
        expect(UiScaleSteps.forWindow(2560), closeTo(1.2, 1e-9));
        expect(UiScaleSteps.forWindow(3000), closeTo(1.25, 1e-9));
        expect(UiScaleSteps.forWindow(3440), closeTo(1.3, 1e-9));
        expect(UiScaleSteps.forWindow(5120), closeTo(1.3, 1e-9));
      },
    );

    testWidgets('el hijo ve el tamaño dividido por la escala', (tester) async {
      tester.view
        ..physicalSize = const Size(3000, 1400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Size? seen;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(3000, 1400)),
            child: UiScale(
              child: Builder(
                builder: (context) {
                  seen = MediaQuery.sizeOf(context);
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
      );
      expect(seen, const Size(2400, 1120));
    });

    testWidgets('un toque a escala 1,25 llega al botón que se ve', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(3000, 1400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final taps = <String>[];
      Widget button(String name, double left, double top) => Positioned(
        left: left,
        top: top,
        width: 100,
        height: 40,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => taps.add(name),
        ),
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(3000, 1400)),
            child: UiScale(
              child: Stack(
                children: [
                  button('a', 100, 100),
                  button('b', 300, 100),
                  button('c', 2300, 1080),
                ],
              ),
            ),
          ),
        ),
      );
      // A (100..200, 100..140) lógicos son (125..250, 125..175) píxeles.
      await tester.tapAt(const Offset(130, 130));
      expect(taps, ['a']);
      // Con coordenadas sin escalar, (110, 110) ya no es A: son (88, 88).
      await tester.tapAt(const Offset(110, 110));
      expect(taps, ['a']);
      // B (300..400) son (375..500) píxeles.
      await tester.tapAt(const Offset(480, 130));
      expect(taps, ['a', 'b']);
      // En la esquina de abajo a la derecha del lienzo lógico (2400 × 1120):
      // C (2300..2400, 1080..1120) son (2875..3000, 1350..1400) píxeles.
      await tester.tapAt(const Offset(2990, 1395));
      expect(taps, ['a', 'b', 'c']);
    });

    screenTest(
      'en la app, a 3440 px la escala es 1,3 y un clic en «Ajustes» abre '
      'Ajustes',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        expect(_logicalWindow(tester).width, closeTo(3440 / 1.3, 0.01));
        await tapText(tester, 'Ajustes');
        expect(find.text('Este ordenador'), findsOneWidget);
        expect(find.text('Copia de seguridad'), findsNothing);
        expect(tester.takeException(), isNull);
      },
      size: const Size(3440, 1440),
      overrides: _web(),
    );

    for (final window in const [
      Size(1920, 1000),
      Size(2200, 1000),
      Size(2999, 1200),
      Size(3000, 1200),
    ]) {
      screenTest(
        'en la app, la ventana de ${window.width.toInt()} px usa la escala '
        'continua',
        (tester, phone) async {
          await _mountWeb(tester, phone);
          expect(
            _logicalWindow(tester).width,
            closeTo(window.width / UiScaleSteps.forWindow(window.width), 0.01),
          );
          expect(tester.takeException(), isNull);
        },
        size: window,
        overrides: _web(),
      );
    }
  });

  group('medidas por ancho lógico', () {
    test('1280 a 1599: lista 320, contenido 880 y sin tercera columna', () {
      for (final w in const [1280.0, 1536.0, 1599.9]) {
        final b = DesktopBands.forWindow(w)!;
        expect(b.listWidth, 320);
        expect(b.contentWidth, 880);
        expect(b.hasAside, isFalse);
        expect(b.maxWidth, isNull);
      }
    });

    test('1600 a 2199: lista 340, detalle 1120 (960) y derecha 340', () {
      for (final w in const [1600.0, 2133.0, 2199.9]) {
        final b = DesktopBands.forWindow(w)!;
        expect(b.listWidth, 340);
        expect(b.contentWidth, 960);
        expect(b.asideWidth, 340);
        expect(b.detailMaxWidth, 1120);
        expect(b.maxWidth, 1880);
      }
    });

    test('desde 2200: lista 380, detalle 1200 (1040) y derecha 400', () {
      for (final w in const [2200.0, 2752.0, 4000.0]) {
        final b = DesktopBands.forWindow(w)!;
        expect(b.listWidth, 380);
        expect(b.contentWidth, 1040);
        expect(b.asideWidth, 400);
        expect(b.detailMaxWidth, 1200);
        expect(b.maxWidth, 2060);
      }
    });

    test('por debajo de 1280 no hay bandas', () {
      expect(DesktopBands.forWindow(1279.9), isNull);
      expect(DesktopBands.forWindow(840), isNull);
      expect(DesktopBands.forWindow(375), isNull);
    });
  });

  group('bandas en la app', () {
    screenTest(
      'a 1536x864: raíl 80, lista 320, detalle el resto y sin tercera '
      'columna',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        expect(_logicalWindow(tester), const Size(1536, 864));
        final rail = find.byType(RegalosNavRail);
        expect(tester.getTopLeft(rail).dx, 0);
        expect(tester.getSize(rail).width, 80);
        final list = _pane(PaneRole.list);
        final detail = _pane(PaneRole.detail);
        expect(tester.getTopLeft(list).dx, 80);
        expect(tester.getSize(list).width, 320);
        // Un filete de 1 px entre la lista y el detalle.
        expect(tester.getTopLeft(detail).dx, 80 + 320 + 1);
        expect(tester.getSize(detail).width, 1536 - 80 - 320 - 1);
        expect(_pane(PaneRole.aside), findsNothing);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1536, 864),
      overrides: _web(),
    );

    screenTest(
      'a 2133 lógicos (2560 con 1,2): composición de 1880 centrada, lista '
      '340, detalle 1120 y tercera columna 340',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        expect(_logicalWindow(tester).width, closeTo(2133.33, 0.01));
        // Márgenes de (2133,33 - 1880) / 2 = 126,67 lógicos.
        final rail = find.byType(RegalosNavRail);
        expect(_logicalTopLeft(tester, rail, 1.2).dx, closeTo(126.67, 0.01));
        expect(tester.getSize(rail).width, 80);
        final list = _pane(PaneRole.list);
        final detail = _pane(PaneRole.detail);
        final aside = _pane(PaneRole.aside);
        expect(tester.getSize(list).width, 340);
        // Los dos filetes de 1 px restan 2 a los 1120 del detalle.
        expect(tester.getSize(detail).width, 1120 - 2);
        expect(tester.getSize(aside).width, 340);
        // La composición acaba en 126,67 + 1880 lógicos.
        final right =
            _logicalTopLeft(tester, aside, 1.2).dx +
            tester.getSize(aside).width;
        expect(right, closeTo(126.67 + 1880, 0.01));
        expect(tester.takeException(), isNull);
      },
      size: const Size(2560, 1440),
      overrides: _web(),
    );

    screenTest(
      'a 2646 lógicos (3440 con 1,3): composición de 2060, lista 380, '
      'detalle 1200 y tercera columna 400',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        const logical = 3440 / 1.3;
        expect(_logicalWindow(tester).width, closeTo(logical, 0.01));
        // Márgenes de (2646,15 - 2060) / 2 lógicos.
        const margin = (logical - 2060) / 2;
        final rail = find.byType(RegalosNavRail);
        expect(_logicalTopLeft(tester, rail, 1.3).dx, closeTo(margin, 0.01));
        final list = _pane(PaneRole.list);
        final detail = _pane(PaneRole.detail);
        final aside = _pane(PaneRole.aside);
        expect(tester.getSize(list).width, 380);
        expect(tester.getSize(detail).width, 1200 - 2);
        expect(tester.getSize(aside).width, 400);
        final right =
            _logicalTopLeft(tester, aside, 1.3).dx +
            tester.getSize(aside).width;
        expect(right, closeTo(margin + 2060, 0.01));
        expect(tester.takeException(), isNull);
      },
      size: const Size(3440, 1440),
      overrides: _web(),
    );

    screenTest(
      'el raíl y la lista son una banda de t.surface y el detalle, de t.bg',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        final t = RegalosTokens.of(tester.element(find.byType(RegalosNavRail)));
        Color? colorBehind(Finder pane) {
          final box = find.ancestor(
            of: pane,
            matching: find.byType(ColoredBox),
          );
          return tester.widget<ColoredBox>(box.first).color;
        }

        expect(
          tester
              .widget<Material>(
                find
                    .descendant(
                      of: find.byType(RegalosNavRail),
                      matching: find.byType(Material),
                    )
                    .first,
              )
              .color,
          t.surface,
        );
        expect(colorBehind(_pane(PaneRole.list)), t.surface);
        expect(colorBehind(_pane(PaneRole.detail)), t.bg);
      },
      size: const Size(1536, 864),
      overrides: _web(),
    );

    screenTest(
      'en Ajustes (sin tercera columna propia) el detalle se queda el ancho '
      'de la tercera columna: no hay banda vacía a la derecha',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        await tapText(tester, 'Ajustes');
        // 1120 del detalle y 340 de la tercera columna, menos el filete de la
        // lista.
        expect(tester.getSize(_pane(PaneRole.detail)).width, 1120 + 340 - 1);
        expect(tester.takeException(), isNull);
      },
      size: const Size(2560, 1440),
      overrides: _web(),
    );

    screenTest(
      '«Guardado» va abajo del raíl y no en la franja de arriba',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        final rail = tester.getRect(find.byType(RegalosNavRail));
        final saved = tester.getCenter(find.text('Guardado'));
        expect(saved.dx, inInclusiveRange(rail.left, rail.right));
        expect(saved.dy, greaterThan(rail.bottom - 80));
        expect(tester.takeException(), isNull);
      },
      size: const Size(1536, 864),
      overrides: _web(),
    );
  });

  group('sin cambios fuera de la web de escritorio', () {
    screenTest(
      'en el móvil (390x844) con web: barra inferior, «Guardado» arriba y sin '
      'escala ni bandas',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        expect(find.byType(RegalosNavBar), findsOneWidget);
        expect(find.byType(RegalosNavRail), findsNothing);
        expect(_logicalWindow(tester), const Size(390, 844));
        expect(tester.getCenter(find.text('Guardado')).dy, lessThan(100));
        expect(tester.takeException(), isNull);
      },
      overrides: _web(),
    );

    for (final size in const [Size(800, 1280), Size(1280, 800)]) {
      screenTest(
        'tablet ${size.width.toInt()}x${size.height.toInt()} sin web: la '
        'misma lista de siempre, sin escala ni bandas',
        (tester, phone) async {
          await seedSample(tester, phone);
          await pumpRegalos(tester, phone);
          expect(find.byType(UiScale), findsNothing);
          expect(
            DesktopBands.maybeOf(tester.element(find.byType(RegalosNavRail))),
            isNull,
          );
          expect(tester.getSize(find.byType(RegalosNavRail)).width, 80);
          if (size.width >= RegalosBreakpoints.expanded) {
            // 34 % del área de contenido, entre 340 y 420 (360 y 420 desde
            // 1280): 408, como antes.
            expect(
              tester.getSize(_pane(PaneRole.list)).width,
              closeTo(408, 0.01),
            );
          } else {
            expect(_pane(PaneRole.list), findsNothing);
          }
          expect(tester.takeException(), isNull);
        },
        size: size,
      );
    }
  });
}
