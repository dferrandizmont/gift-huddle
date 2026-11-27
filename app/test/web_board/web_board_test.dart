// El tablero «Hoy» de la web de escritorio
// (la guía de diseño de escritorio, A): barra lateral, carriles por
// lo que falta a cada regalo, ocasiones filtradas y el editor como panel fijo.
// Solo en la web y desde 1280; el móvil, la tablet y la web estrecha no
// cambian.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/app.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/layout/pane_scope.dart';
import 'package:regalos/core/sync/model.dart' show GiftStatus;
import 'package:regalos/core/widgets/pane_list_row.dart';
import 'package:regalos/core/widgets/person_avatar.dart';
import 'package:regalos/features/settings/presentation/settings_column.dart';
import 'package:regalos/features/gifts/presentation/gift_editor_screen.dart';
import 'package:regalos/features/people/presentation/people_screen.dart';
import 'package:regalos/features/web_board/application/board_lanes.dart';
import 'package:regalos/features/web_board/application/board_metrics.dart';
import 'package:regalos/features/web_board/presentation/board_editor_host.dart';
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

String _path(FakePhone phone) => phone.container
    .read(routerProvider)
    .routeInformationProvider
    .value
    .uri
    .path;

Finder _lane(BoardLane lane) =>
    find.byKey(ValueKey<String>('board-lane-${lane.name}'));

/// Lo que vuela encima de todo (`FlightTarget`): un `Positioned` con tamaño
/// propio que no recibe toques, directo en el `Overlay`.
Finder get _flying => find.byWidgetPredicate(
  (w) =>
      w is Positioned &&
      w.width != null &&
      w.height != null &&
      w.child is IgnorePointer,
  description: 'algo volando',
);

Finder _rowOf(String title) => find.widgetWithText(BoardGiftRow, title).first;

void main() {
  setUpAll(loadInter);

  group('cuántos carriles caben', () {
    test('cuatro y «Listo» plegado, o los cinco', () {
      expect(BoardLanesView.columnsFor(1280 - 232 - 48), 4);
      expect(BoardLanesView.columnsFor(1536 - 232 - 48), 4);
      expect(BoardLanesView.columnsFor(1920 - 264 - 64), 5);
      expect(BoardLanesView.columnsFor(2133 - 264 - 64), 5);
    });
  });

  group('reparto en carriles', () {
    test('cada estado va a su carril y lo entregado no sale', () {
      expect(BoardLane.of(GiftStatus.idea), BoardLane.decide);
      expect(BoardLane.of(GiftStatus.decided), BoardLane.buy);
      expect(BoardLane.of(GiftStatus.bought), BoardLane.arrive);
      expect(BoardLane.of(GiftStatus.arrived), BoardLane.wrap);
      expect(BoardLane.of(GiftStatus.wrapped), BoardLane.ready);
      expect(BoardLane.of(GiftStatus.delivered), isNull);
    });
  });

  group('a 1280 × 720', () {
    screenTest(
      'barra lateral, tira de ocasiones y los carriles en una sola fila',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        expect(find.byType(BoardSidebar), findsOneWidget);
        expect(find.byType(BoardOccasionStrip), findsOneWidget);
        expect(find.byType(PeopleListPane), findsNothing);
        expect(_path(phone), '/people');
        // La barra: secciones y las tres personas de muestra.
        final sidebar = find.byType(BoardSidebar);
        for (final text in const ['Hoy', 'Reparto', 'Ocasiones', 'Ajustes']) {
          expect(
            find.descendant(of: sidebar, matching: find.text(text)),
            findsOneWidget,
            reason: text,
          );
        }
        for (final name in const ['Aritz', 'Nora', 'Leo']) {
          expect(
            find.descendant(of: sidebar, matching: find.text(name)),
            findsOneWidget,
            reason: name,
          );
        }
        // Siempre una sola fila: los cuatro primeros, uno al lado de otro, y
        // «Listo» plegado en su columna (no hay segunda fila).
        final tops = [
          for (final lane in BoardLane.values.take(4))
            tester.getTopLeft(_lane(lane)).dy,
        ];
        expect(tops.toSet().length, 1);
        expect(_lane(BoardLane.ready), findsNothing);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1280, 720),
      overrides: _web(),
    );

    screenTest(
      'los regalos van al carril de lo que les falta',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        Finder inLane(BoardLane lane, String title) =>
            find.descendant(of: _lane(lane), matching: find.text(title));
        // Idea → decidir; decidido → comprar; comprado → llegar; envuelto →
        // listo; entregado, en ninguno.
        expect(inLane(BoardLane.decide, 'Patinete'), findsOneWidget);
        expect(
          inLane(BoardLane.buy, 'Bici de 20" con cambios'),
          findsOneWidget,
        );
        expect(inLane(BoardLane.arrive, 'Tren de madera'), findsOneWidget);
        expect(inLane(BoardLane.ready, 'Cocinita de madera'), findsOneWidget);
        expect(find.text('Libro de cuentos'), findsNothing);
      },
      size: const Size(1920, 960),
      overrides: _web(),
    );

    screenTest(
      'marcar un regalo lo lleva al carril siguiente',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        final check = find.descendant(
          of: _rowOf('Patinete'),
          matching: find.byType(InkResponse),
        );
        await tester.tap(check.first);
        await settle(tester);
        // «Patinete» era una idea: pasa a «decidido», el carril de comprar.
        expect(
          find.descendant(
            of: _lane(BoardLane.buy),
            matching: find.text('Patinete'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: _lane(BoardLane.decide),
            matching: find.text('Patinete'),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
      size: const Size(1280, 720),
      overrides: _web(),
    );

    screenTest(
      'el editor es un panel fijo a la derecha y no tapa los carriles',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        final lanesBefore = tester.getSize(_lane(BoardLane.decide)).width;
        await tester.tap(find.text('Patinete').first);
        await settle(tester);
        final editor = find.byType(GiftEditorScreen);
        expect(editor, findsOneWidget);
        final rect = tester.getRect(editor);
        expect(rect.width, closeTo(BoardEditorHost.widthFor(1920), 0.5));
        expect(rect.right, closeTo(1920, 0.5));
        // Los carriles siguen a la vista, solo más estrechos.
        expect(_lane(BoardLane.decide), findsOneWidget);
        expect(
          tester.getSize(_lane(BoardLane.decide)).width,
          lessThan(lanesBefore),
        );
        expect(
          tester.getRect(_lane(BoardLane.decide)).right,
          lessThanOrEqualTo(rect.left),
        );
        // Se pasa a otro regalo sin cerrar el panel.
        await tester.ensureVisible(find.text('Tren de madera').first);
        await tester.pump();
        await tester.tap(find.text('Tren de madera').first);
        await settle(tester);
        expect(find.byType(GiftEditorScreen), findsOneWidget);
        final fields = tester.widgetList<EditableText>(
          find.descendant(
            of: find.byType(GiftEditorScreen),
            matching: find.byType(EditableText),
          ),
        );
        expect(
          fields.map((f) => f.controller.text).toList(),
          contains('Tren de madera'),
        );
        // Esc lo cierra.
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(tester);
        expect(find.byType(GiftEditorScreen), findsNothing);
        expect(
          tester.getSize(_lane(BoardLane.decide)).width,
          closeTo(lanesBefore, 40),
        );
        expect(tester.takeException(), isNull);
      },
      size: const Size(1920, 960),
      overrides: _web(),
    );

    screenTest(
      'N abre un regalo nuevo y Esc lo cierra',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
        await settle(tester);
        expect(find.byType(GiftEditorScreen), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(tester);
        expect(find.byType(GiftEditorScreen), findsNothing);
      },
      size: const Size(1280, 720),
      overrides: _web(),
    );

    screenTest(
      'Esc con el foco en el tablero pregunta antes de descartar cambios',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
        await settle(tester);
        expect(find.byType(GiftEditorScreen), findsOneWidget);
        await tester.enterText(
          find
              .descendant(
                of: find.byType(GiftEditorScreen),
                matching: find.byType(TextField),
              )
              .first,
          'Cometa',
        );
        // El foco sale del editor: lo atiende el tablero.
        final node = find
            .descendant(
              of: find.descendant(
                of: find.byType(BoardSidebar),
                matching: find.byType(InkWell),
              ),
              matching: find.byType(Text),
            )
            .evaluate()
            .map(Focus.maybeOf)
            .firstWhere((n) => n != null && n.canRequestFocus)!;
        node.requestFocus();
        await tester.pump();
        expect(BoardEditorMarker.isInside(node.context!), isFalse);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(tester);
        expect(find.text('¿Descartar los cambios?'), findsOneWidget);
        expect(find.byType(GiftEditorScreen), findsOneWidget);
        await tester.tap(find.text('Seguir editando'));
        await settle(tester);
        expect(find.byType(GiftEditorScreen), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(tester);
        await tester.tap(find.widgetWithText(FilledButton, 'Descartar'));
        await settle(tester);
        expect(find.byType(GiftEditorScreen), findsNothing);
      },
      size: const Size(1280, 720),
      overrides: _web(),
    );

    screenTest(
      '↓ y ↑ recorren los regalos; Alt con ↓ y ↑ cambia de persona',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        final cursor = phone.container.read(boardGiftCursorProvider);
        expect(cursor.current, isNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await settle(tester);
        // Marca el primer regalo y no cambia de pantalla.
        final first = cursor.current;
        expect(first, isNotNull);
        expect(_path(phone), '/people');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await settle(tester);
        expect(cursor.current, isNot(first));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await settle(tester);
        expect(cursor.current, first);
        // Intro abre el marcado.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await settle(tester);
        expect(find.byType(GiftEditorScreen), findsOneWidget);
        // Esc cierra el editor y otro Esc quita la marca.
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(tester);
        expect(find.byType(GiftEditorScreen), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(tester);
        expect(cursor.current, isNull);
        // Alt con las flechas cambia de persona, con el avatar volando.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 100));
        expect(_flying, findsOneWidget);
        await settle(tester);
        expect(_path(phone), '/people/aritz');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await settle(tester);
        expect(_path(phone), '/people/leo');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await settle(tester);
        expect(_path(phone), '/people/aritz');
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      },
      size: const Size(1280, 720),
      overrides: _web(),
    );

    screenTest(
      'una persona de la barra abre su lista sin flecha de volver',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        await tester.tap(
          find.descendant(
            of: find.byType(BoardSidebar),
            matching: find.text('Nora'),
          ),
        );
        await settle(tester);
        expect(_path(phone), '/people/nora');
        expect(find.text('Cocinita de madera'), findsWidgets);
        expect(find.bySemanticsLabel('Volver a Personas'), findsNothing);
        expect(
          find.byWidgetPredicate(
            (w) => w is PaneScope && w.role == PaneRole.detail,
          ),
          findsWidgets,
        );
        expect(tester.takeException(), isNull);
      },
      size: const Size(1280, 720),
      overrides: _web(),
    );

    screenTest(
      'Ocasiones es el tablero filtrado por la ocasión elegida',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        await tester.tap(
          find.descendant(
            of: find.byType(BoardSidebar),
            matching: find.text('Ocasiones'),
          ),
        );
        await settle(tester);
        expect(_path(phone), '/occasions');
        // Entra la próxima ocasión (el Tió): solo sus regalos.
        expect(find.text('Pijama de astronautas, talla 8'), findsOneWidget);
        expect(find.text('Patinete'), findsNothing);
        // Elegir Reyes cambia los regalos que salen.
        await tester.tap(
          find.descendant(
            of: find.byType(BoardOccasionStrip),
            matching: find.text('Reyes'),
          ),
        );
        await settle(tester);
        expect(_path(phone), '/occasions/seed-kings');
        expect(find.text('Patinete'), findsOneWidget);
        expect(find.text('Pijama de astronautas, talla 8'), findsNothing);
        // La fecha se puede cambiar.
        expect(
          find.byKey(const ValueKey<String>('board-change-date')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
      size: const Size(1280, 720),
      overrides: _web(),
    );
  });

  group('movimiento', () {
    screenTest(
      'la fila que se marca vuela de un carril al otro',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        final check = find.descendant(
          of: _rowOf('Patinete'),
          matching: find.byType(InkResponse),
        );
        await tester.tap(check.first);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        await tester.pump(const Duration(milliseconds: 120));
        // En pleno vuelo hay dos: la que vuela, encima de todo, y la de verdad
        // ya en su carril, escondida hasta que llegue.
        expect(_flying, findsOneWidget);
        expect(
          find.descendant(of: _flying, matching: find.text('Patinete')),
          findsOneWidget,
        );
        await settle(tester);
        expect(_flying, findsNothing);
        expect(find.text('Patinete'), findsOneWidget);
        expect(
          find.descendant(
            of: _lane(BoardLane.buy),
            matching: find.text('Patinete'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
      size: const Size(1280, 720),
      inlineDocumentTasks: true,
      overrides: _web(),
    );

    screenTest(
      'con «Reducir movimiento» la fila no vuela: solo aparece en su carril',
      (tester, phone) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await _mountWeb(tester, phone);
        final check = find.descendant(
          of: _rowOf('Patinete'),
          matching: find.byType(InkResponse),
        );
        await tester.tap(check.first);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        expect(_flying, findsNothing);
        await settle(tester);
        expect(_flying, findsNothing);
        expect(find.text('Patinete'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1280, 720),
      overrides: _web(),
    );

    screenTest(
      'el avatar de la barra vuela a la cabecera de la persona',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        await tester.tap(
          find.descendant(
            of: find.byType(BoardSidebar),
            matching: find.text('Nora'),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 100));
        // Vuela encima de todo: un avatar con el nombre de la persona.
        expect(_flying, findsOneWidget);
        expect(
          find.descendant(of: _flying, matching: find.byType(PersonAvatar)),
          findsOneWidget,
        );
        await settle(tester);
        expect(_flying, findsNothing);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1280, 720),
      overrides: _web(),
    );
  });

  group('Ajustes en una columna con índice', () {
    Finder index(String label) => find.byWidgetPredicate(
      (w) => w is PaneListRow && w.label == label,
      description: 'fila «$label» del índice',
    );
    Finder active(String label) => find.byWidgetPredicate(
      (w) => w is PaneListRow && w.label == label && w.selected,
      description: 'fila «$label» marcada',
    );
    Finder header(String title) => find.descendant(
      of: find.byType(EmbeddedSectionHeader),
      matching: find.text(title),
    );

    Future<void> openSettings(WidgetTester tester, FakePhone phone) async {
      await _mountWeb(tester, phone);
      await tester.tap(
        find.descendant(
          of: find.byType(BoardSidebar),
          matching: find.text('Ajustes'),
        ),
      );
      await settle(tester);
    }

    screenTest(
      'todos los apartados van apilados, con el índice a la izquierda',
      (tester, phone) async {
        await openSettings(tester, phone);
        expect(_path(phone), '/settings');
        for (final title in const [
          'Personas',
          'Quién regala',
          'Ocasiones',
          'Archivo',
          'Este ordenador',
          'Apariencia',
          'Acerca de',
        ]) {
          expect(index(title), findsOneWidget, reason: 'índice: $title');
          expect(header(title), findsOneWidget, reason: 'apartado: $title');
        }
        // Una sola columna: los apartados uno debajo de otro, el índice a la
        // izquierda de todos.
        final people = tester.getTopLeft(header('Personas'));
        final givers = tester.getTopLeft(header('Quién regala'));
        expect(givers.dx, people.dx);
        expect(givers.dy, greaterThan(people.dy));
        expect(tester.getTopLeft(index('Personas')).dx, lessThan(people.dx));
        expect(active('Personas'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1280, 720),
      overrides: _web(),
    );

    screenTest(
      'tocar el índice salta al apartado y lo marca; al desplazarse, se mueve',
      (tester, phone) async {
        await openSettings(tester, phone);
        await tester.tap(index('Apariencia'));
        await settle(tester);
        expect(active('Apariencia'), findsOneWidget);
        expect(tester.getTopLeft(header('Apariencia')).dy, lessThan(220));
        // Desplazar la columna a mano cambia el apartado marcado.
        await tester.drag(
          find.byType(SingleChildScrollView).last,
          const Offset(0, 3000),
        );
        await settle(tester);
        expect(active('Personas'), findsOneWidget);
        await tester.drag(
          find.byType(SingleChildScrollView).last,
          const Offset(0, -5000),
        );
        await settle(tester);
        expect(active('Acerca de'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1280, 720),
      overrides: _web(),
    );
  });

  group('a 2560 × 1300', () {
    screenTest(
      'los cinco carriles caben en una sola fila',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        final tops = [
          for (final lane in BoardLane.values)
            tester.getTopLeft(_lane(lane)).dy,
        ];
        expect(tops.toSet().length, 1);
        expect(tester.takeException(), isNull);
      },
      size: const Size(2560, 1300),
      overrides: _web(),
    );
  });

  group('lo que no cambia', () {
    screenTest(
      'la web por debajo de 1280 sigue con la pantalla de siempre',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        expect(find.byType(BoardSidebar), findsNothing);
        expect(find.byType(BoardEditorHost), findsNothing);
        expect(find.byType(PeopleListPane), findsOneWidget);
      },
      size: const Size(1100, 800),
      overrides: _web(),
    );

    screenTest('una tablet de 1280 que no es la web no cambia', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      expect(find.byType(BoardSidebar), findsNothing);
      expect(find.byType(PeopleListPane), findsOneWidget);
    }, size: const Size(1280, 800));

    screenTest('el móvil no cambia', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      expect(find.byType(BoardSidebar), findsNothing);
      expect(find.byType(PeopleScreen), findsOneWidget);
    });
  });
}
