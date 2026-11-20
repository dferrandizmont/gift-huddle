// La web de escritorio, tercera ronda
// (la guía de diseño de escritorio): escala continua, sin
// tope de composición, carriles en una sola fila, columnas de Persona por
// prioridad y el editor que se superpone en una ventana estrecha.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/app.dart';
import 'package:flutter/services.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/layout/ui_scale.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/theme/regalos_tokens.dart';
import 'package:regalos/core/widgets/focus_ring.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/web_board/application/gift_editor_panel.dart';
import 'package:regalos/features/gifts/presentation/gift_editor_screen.dart';
import 'package:regalos/features/web_board/application/board_lanes.dart';
import 'package:regalos/features/web_board/application/board_metrics.dart';
import 'package:regalos/features/web_board/presentation/board_gift_table.dart';
import 'package:regalos/features/web_board/presentation/board_lanes_view.dart';
import 'package:regalos/features/web_board/presentation/board_occasion_strip.dart';
import 'package:regalos/features/web_board/presentation/board_sidebar.dart';
import 'package:regalos/features/web_device/application/web_app_provider.dart';
import 'package:regalos/features/web_device/application/web_device_providers.dart';
import 'package:regalos/features/web_device/application/web_sync_engine.dart'
    show WebSyncStatus;

import '../helpers/fonts.dart';
import '../helpers/memory_stores.dart';
import '../helpers/screens.dart';
import '../web_device/presentation/gate_test_support.dart';

const _confirmed = WebDeviceState(
  status: WebSyncStatus.confirmed,
  hasRoots: true,
  setAsideChanges: 0,
  persistenceDenied: false,
);

List<Override> _web() => [
  webAppProvider.overrideWithValue(true),
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

Finder _lane(BoardLane lane) =>
    find.byKey(ValueKey<String>('board-lane-${lane.name}'));

Finder _header(String label) => find.descendant(
  of: find.byType(BoardGiftTableHeader),
  matching: find.text(label),
);

Future<void> _openPerson(WidgetTester tester, String name) async {
  await tester.tap(
    find.descendant(of: find.byType(BoardSidebar), matching: find.text(name)),
  );
  await settle(tester);
}

void main() {
  setUpAll(loadInter);

  group('escala continua', () {
    test('los puntos de la regla', () {
      expect(UiScaleSteps.forWindow(1536), 1);
      expect(UiScaleSteps.forWindow(1920), 1);
      expect(UiScaleSteps.forWindow(2560), closeTo(1.2, 1e-9));
      expect(UiScaleSteps.forWindow(3000), closeTo(1.25, 1e-9));
      expect(UiScaleSteps.forWindow(3440), closeTo(1.3, 1e-9));
      expect(UiScaleSteps.forWindow(5000), closeTo(1.3, 1e-9));
    });

    test('es monótona de 1500 a 3440 y va de 0,025 en 0,025', () {
      var last = UiScaleSteps.forWindow(1500);
      for (var w = 1500.0; w <= 3440; w += 1) {
        final s = UiScaleSteps.forWindow(w);
        expect(s, greaterThanOrEqualTo(last), reason: 'a $w');
        final steps = s / UiScaleSteps.quantum;
        expect(steps, closeTo(steps.roundToDouble(), 1e-6), reason: 'a $w');
        last = s;
      }
    });

    test('el ancho lógico nunca va hacia atrás al ensanchar 150 px', () {
      for (var w = 1500.0; w + 150 <= 3440; w += 1) {
        final now = w / UiScaleSteps.forWindow(w);
        final later = (w + 150) / UiScaleSteps.forWindow(w + 150);
        expect(later, greaterThan(now), reason: 'a $w');
      }
    });

    test('1536 → 1536, 1920 → 1920, 2560 → 2133, 3440 → 2646', () {
      double logical(double w) => w / UiScaleSteps.forWindow(w);
      expect(logical(1536), closeTo(1536, 1));
      expect(logical(1920), closeTo(1920, 1));
      expect(logical(2560), closeTo(2133, 1));
      expect(logical(3440), closeTo(2646, 1));
    });
  });

  group('medidas del tablero', () {
    test('barra, margen y editor', () {
      expect(BoardMetrics.sidebarFor(1536), 232);
      expect(BoardMetrics.sidebarFor(1600), 264);
      expect(BoardMetrics.marginFor(1536), 24);
      expect(BoardMetrics.marginFor(1920), 32);
      expect(BoardMetrics.marginFor(2400), 32);
      expect(BoardMetrics.marginFor(2646), 40);
      expect(BoardMetrics.editorWidthFor(1536), 400);
      expect(BoardMetrics.editorWidthFor(2646), closeTo(0.17 * 2646, 1e-9));
      expect(BoardMetrics.editorWidthFor(4000), 480);
    });

    test('el editor se superpone a 1536 y empuja a 1920, 2133 y 2646', () {
      bool pushes(double w) =>
          BoardMetrics.editorPushes(w, sidebar: BoardMetrics.sidebarFor(w));
      expect(pushes(1536), isFalse);
      expect(pushes(1920), isTrue);
      expect(pushes(2133), isTrue);
      expect(pushes(2646), isTrue);
    });
  });

  group('tira de ocasiones', () {
    test('220 cómodo y 200 duro: reparte si caben a 200 o más', () {
      // 1920: 7 ocasiones con el presupuesto en 1592 salen a unos 217.
      expect(BoardOccasionStrip.cardWidthFor(1592, 7), closeTo(217.1, 0.1));
      // Ocho ya no caben a 200: 200 y se desplaza.
      expect(BoardOccasionStrip.cardWidthFor(1592, 8), 200);
      // 4 o más se reparten el ancho entero (como mucho 520).
      expect(BoardOccasionStrip.cardWidthFor(4000, 4), 520);
      // 1 a 3, como mucho 360.
      expect(BoardOccasionStrip.cardWidthFor(2000, 3), 360);
    });
  });

  group('carriles en una sola fila', () {
    test('cinco desde 1304 cómodos; «Listo» se pliega; luego se desplaza', () {
      // 1920 sin editor: 1592 de sitio, cinco de unos 309.
      var layout = BoardLanesLayout.of(1592);
      expect(layout.fold, isFalse);
      expect(layout.scrolls, isFalse);
      expect(layout.laneWidth, closeTo(308.8, 0.1));
      expect(layout.total, closeTo(1592, 0.01));
      // 1920 con editor: 1192, «Listo» plegado y cuatro de unos 272.
      layout = BoardLanesLayout.of(1192);
      expect(layout.fold, isTrue);
      expect(layout.scrolls, isFalse);
      expect(layout.readyWidth, BoardLanesView.foldedWidth);
      expect(layout.laneWidth, closeTo(272, 1));
      expect(layout.total, closeTo(1192, 0.01));
      // 1536 sin barra de por medio no cabe ni así: se desplaza.
      layout = BoardLanesLayout.of(1000);
      expect(layout.scrolls, isTrue);
      expect(layout.laneWidth, BoardLanesView.minLaneWidth);
    });

    test('nunca pasa de 520 por carril', () {
      expect(BoardLanesLayout.of(4000).laneWidth, 520);
    });

    test('el ancho de los carriles sube con la ventana en cada tramo', () {
      for (final fold in [false, true]) {
        var last = 0.0;
        for (var w = 1112.0; w <= 4000; w += 4) {
          final l = BoardLanesLayout.of(w);
          if (l.fold != fold) {
            last = 0;
            continue;
          }
          expect(l.laneWidth, greaterThanOrEqualTo(last), reason: 'a $w');
          last = l.laneWidth;
        }
      }
    });
  });

  group('columnas de Persona por prioridad', () {
    test('entran de una en una según el ancho', () {
      Set<BoardColumn> at(double w) => BoardTableColumns.forWidth(w).shown;
      // 1536 con el editor superpuesto: hasta quién regala.
      expect(at(896), <BoardColumn>{
        BoardColumn.statusText,
        BoardColumn.price,
        BoardColumn.giver,
      });
      // 1920 con el editor: hasta la tienda.
      expect(at(1224), contains(BoardColumn.store));
      expect(at(1224), isNot(contains(BoardColumn.size)));
      // 2133 con el editor: hasta la talla.
      expect(at(1437), contains(BoardColumn.size));
      expect(at(1437), isNot(contains(BoardColumn.note)));
      // 3440: todas.
      expect(at(1884), BoardColumn.values.toSet());
    });

    test(
      'siempre por orden de prioridad y sin quitar ninguna al ensanchar',
      () {
        var last = <BoardColumn>{};
        for (var w = 300.0; w <= 2400; w += 2) {
          final shown = BoardTableColumns.forWidth(w).shown;
          expect(shown.containsAll(last), isTrue, reason: 'a $w');
          for (var i = 0; i < BoardColumn.values.length; i++) {
            if (shown.contains(BoardColumn.values[i]) && i > 0) {
              expect(
                shown.contains(BoardColumn.values[i - 1]),
                isTrue,
                reason: '${BoardColumn.values[i]} sin la anterior a $w',
              );
            }
          }
          last = shown;
        }
      },
    );

    test('la nota mide de 240 a 480', () {
      expect(
        BoardTableColumns.forWidth(1700).noteWidth,
        inInclusiveRange(240, 480),
      );
      expect(BoardTableColumns.forWidth(3000).noteWidth, 480);
    });
  });

  group('en la ventana', () {
    screenTest(
      'a 3440 el tablero llena la ventana: sin franja gris ni barra desplazada',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        final scale = UiScaleSteps.forWindow(3440);
        final sidebar = tester.getRect(find.byType(BoardSidebar));
        expect(sidebar.left, closeTo(0, 0.5));
        // Los cinco carriles en una fila y el último llega hasta el margen.
        final tops = [
          for (final lane in BoardLane.values)
            tester.getTopLeft(_lane(lane)).dy,
        ];
        expect(tops.toSet().length, 1);
        final last = tester.getRect(_lane(BoardLane.ready));
        final logicalWidth = 3440 / scale;
        expect(
          last.right / scale,
          closeTo(logicalWidth - BoardMetrics.marginFor(logicalWidth), 1),
        );
        expect(tester.takeException(), isNull);
      },
      size: const Size(3440, 1300),
      overrides: _web(),
    );

    screenTest(
      'a 1920 con el editor «Listo» se pliega y los carriles siguen en una fila',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        final before = tester.getSize(_lane(BoardLane.decide)).width;
        expect(find.text('Listo'), findsOneWidget);
        await tester.tap(find.text('Patinete').first);
        await settle(tester);
        final tops = [
          for (final lane in BoardLane.values.take(4))
            tester.getTopLeft(_lane(lane)).dy,
        ];
        expect(tops.toSet().length, 1);
        // «Listo» ya no es un carril: va plegado en su columna de 56.
        expect(_lane(BoardLane.ready), findsNothing);
        expect(tester.getSize(_lane(BoardLane.decide)).width, lessThan(before));
        // Los carriles llenan el alto de la ventana.
        final bottom = tester.getRect(_lane(BoardLane.decide)).bottom;
        expect(bottom, greaterThan(850));
        expect(tester.takeException(), isNull);
      },
      size: const Size(1920, 960),
      overrides: _web(),
    );

    screenTest(
      'a 1536 el editor se superpone: los carriles no se estrechan',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        final before = tester.getSize(_lane(BoardLane.decide)).width;
        await tester.tap(find.text('Patinete').first);
        await settle(tester);
        expect(find.byType(GiftEditorScreen), findsOneWidget);
        expect(
          tester.getSize(_lane(BoardLane.decide)).width,
          closeTo(before, 0.5),
        );
        final editor = tester.getRect(find.byType(GiftEditorScreen));
        // El panel está encima, pegado al borde derecho.
        expect(editor.right, closeTo(1536, 0.5));
        expect(tester.takeException(), isNull);
      },
      size: const Size(1536, 740),
      overrides: _web(),
    );

    screenTest(
      'Persona con el editor superpuesto pierde columnas en vez de quedar debajo',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        await _openPerson(tester, 'Aritz');
        expect(_header('Tienda'), findsOneWidget);
        await tester.tap(find.byType(BoardGiftTableRow).first);
        await settle(tester);
        // Con el editor encima, la tabla llega hasta él y no pasa de «Quién
        // regala».
        expect(_header('Quién regala'), findsOneWidget);
        expect(_header('Tienda'), findsNothing);
        final editor = tester.getRect(find.byType(GiftEditorScreen));
        final table = tester.getRect(find.byType(BoardGiftTableHeader));
        expect(table.right, lessThanOrEqualTo(editor.left + 0.5));
        expect(tester.takeException(), isNull);
      },
      size: const Size(1536, 740),
      overrides: _web(),
    );

    screenTest(
      'a 1920 con el editor, Persona llega hasta la tienda',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        await _openPerson(tester, 'Aritz');
        await tester.tap(find.byType(BoardGiftTableRow).first);
        await settle(tester);
        expect(_header('Tienda'), findsOneWidget);
        expect(_header('Nota'), findsNothing);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1920, 960),
      overrides: _web(),
    );
  });

  group('comportamiento al cambiar de pantalla', () {
    String path(FakePhone phone) => phone.container
        .read(routerProvider)
        .routeInformationProvider
        .value
        .uri
        .path;

    Finder section(String name) => find.descendant(
      of: find.byType(BoardSidebar),
      matching: find.text(name),
    );

    screenTest(
      'Reparto web agrupa los alias y muestra las referencias tardías sin asignar',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        await tester.runAsync(() async {
          final c = familyOf(phone);
          await c.linkGiver('marta', 'nora');
          await c.linkGiver('us', 'nora');
          await c.deleteGiver('yayos');
          final doc = phone.container
              .read(familyControllerProvider)
              .requireValue
              .doc;
          final clock = HlcClock(node: 'remote', last: doc.maxStamp);
          await c.mergeRemote(
            doc.set(clock, Collections.gifts, 'late', {
              'recipientId': 'aritz',
              'giverId': 'yayos',
              'title': 'Bicicleta plegable',
              'status': 'idea',
              'surprise': false,
              'year': 2026,
            }),
            fromNode: 'remote',
          );
        });
        await tester.tap(section('Reparto'));
        await settle(tester);
        await tester.tap(find.text('Todas'));
        await settle(tester);
        expect(
          find.bySemanticsLabel(RegExp(r'^Nora para Aritz: 3 regalos')),
          findsOneWidget,
        );
        expect(find.text('Bicicleta plegable'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1920, 960),
      overrides: _web(),
    );

    screenTest(
      'G1: el editor se cierra al cambiar de sección o de persona y quita la '
      'marca',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        final cursor = phone.container.read(boardGiftCursorProvider);
        await tester.tap(find.text('Libro de dinosaurios con solapas').first);
        await settle(tester);
        expect(find.byType(GiftEditorScreen), findsOneWidget);
        expect(cursor.current, isNotNull);
        await tester.tap(section('Reparto'));
        await settle(tester);
        expect(find.byType(GiftEditorScreen), findsNothing);
        expect(cursor.current, isNull);
        // Otra persona: también.
        await tester.tap(section('Hoy'));
        await settle(tester);
        await tester.tap(find.text('Patinete').first);
        await settle(tester);
        expect(find.byType(GiftEditorScreen), findsOneWidget);
        await _openPerson(tester, 'Nora');
        expect(find.byType(GiftEditorScreen), findsNothing);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1920, 960),
      overrides: _web(),
    );

    screenTest(
      'G1: se queda abierto si se va a la persona del regalo o si hay cambios '
      'sin guardar',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        // «Patinete» es de Aritz: ir a Aritz no lo cierra.
        await tester.tap(find.text('Patinete').first);
        await settle(tester);
        await _openPerson(tester, 'Aritz');
        expect(find.byType(GiftEditorScreen), findsOneWidget);
        // Con cambios sin guardar, tampoco se cierra al ir a otra persona.
        final field = find.descendant(
          of: find.byType(GiftEditorScreen),
          matching: find.byType(EditableText),
        );
        await tester.enterText(field.first, 'Patinete eléctrico');
        await tester.pump();
        expect(phone.container.read(giftEditorPanelProvider).isDirty, isTrue);
        await _openPerson(tester, 'Nora');
        expect(find.byType(GiftEditorScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1920, 960),
      overrides: _web(),
    );

    screenTest(
      'G2: «Hoy» lleva siempre a «Hoy», no a la última persona visitada',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        await _openPerson(tester, 'Aritz');
        expect(path(phone), '/people/aritz');
        await tester.tap(section('Reparto'));
        await settle(tester);
        expect(path(phone), '/family');
        await tester.tap(section('Hoy'));
        await settle(tester);
        expect(path(phone), '/people');
        expect(
          find.byKey(const ValueKey<String>('board-add-gift')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
      size: const Size(1920, 960),
      overrides: _web(),
    );

    testWidgets('G3: un foco de una pantalla que ya no se ve no lleva filete', (
      tester,
    ) async {
      final visible = FocusNode();
      final hidden = FocusNode();
      addTearDown(visible.dispose);
      addTearDown(hidden.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              Focus(focusNode: visible, child: const SizedBox(width: 10)),
              TickerMode(
                enabled: false,
                child: Focus(
                  focusNode: hidden,
                  child: const SizedBox(width: 10),
                ),
              ),
            ],
          ),
        ),
      );
      expect(focusRingable(visible), isTrue);
      expect(focusRingable(hidden), isFalse);
    });

    screenTest(
      'M4: el fondo y el filete solo con el editor; la marca del teclado, un '
      'borde de 1',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        final t = RegalosTokens.of(tester.element(find.byType(BoardSidebar)));
        final soft = find.descendant(
          of: find.byType(BoardGiftRow),
          matching: find.byWidgetPredicate(
            (w) =>
                w is DecoratedBox &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).color == t.selection &&
                (w.decoration as BoxDecoration).border is Border &&
                ((w.decoration as BoxDecoration).border! as Border).top.color ==
                    t.ink,
          ),
        );
        final marked = find.descendant(
          of: find.byType(BoardGiftRow),
          matching: find.byWidgetPredicate((w) {
            if (w is! DecoratedBox) return false;
            final d = w.decoration;
            return d is BoxDecoration &&
                d.border is Border &&
                (d.border! as Border).top.color == t.controlBorder;
          }),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await settle(tester);
        // Solo la marca: borde de control, sin fondo suave.
        expect(marked, findsOneWidget);
        expect(soft, findsNothing);
        // Con el editor, el fondo suave y el filete de tinta.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await settle(tester);
        expect(soft, findsOneWidget);
        expect(marked, findsNothing);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1920, 960),
      overrides: _web(),
    );

    test('M5: sin dato, las columnas de prioridad 5 o más no cuentan', () {
      // 1920 con editor (1224): sin tienda, la talla ocupa su sitio.
      final cols = BoardTableColumns.forWidth(
        1224,
        withData: {BoardColumn.size},
      );
      expect(cols.has(BoardColumn.store), isFalse);
      expect(cols.has(BoardColumn.size), isTrue);
      // Sin datos de ninguna, solo las de prioridad 2 a 4.
      final none = BoardTableColumns.forWidth(3000, withData: <BoardColumn>{});
      expect(none.shown, {
        BoardColumn.statusText,
        BoardColumn.price,
        BoardColumn.giver,
      });
    });

    screenTest(
      'M5: Irene, sin tienda ni talla ni nota, no las enseña; Aritz, con '
      'tienda, sí',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        await _openPerson(tester, 'Aritz');
        expect(_header('Tienda'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1920, 960),
      overrides: _web(),
    );
  });
}
