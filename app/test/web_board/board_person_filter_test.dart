// El filtro por persona de «Hoy» y el buscador de la barra lateral
// (derivado del tablero «Hoy» de la web de escritorio
// (la guía de diseño de escritorio, A): barra lateral, carriles por
// lo que falta a cada regalo, ocasiones filtradas y el editor como panel fijo.
// Solo en la web y desde 1280; el móvil, la tablet y la web estrecha no
// cambian.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/app.dart';
import 'package:regalos/core/widgets/anchored_picker.dart';
import 'package:regalos/core/sync/model.dart' show GiftStatus;
import 'package:regalos/features/gifts/presentation/gift_search.dart';
import 'package:regalos/features/web_board/application/board_lanes.dart';
import 'package:regalos/features/web_board/application/board_metrics.dart';
import 'package:regalos/features/web_board/presentation/board_lanes_view.dart';
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

Finder _rowIn(BoardLane lane, String title) => find.descendant(
  of: _lane(lane),
  matching: find.widgetWithText(BoardGiftRow, title),
);

Future<void> _selectPerson(WidgetTester tester, String name) async {
  await tester.tap(
    find.byKey(const ValueKey<String>('board-person-filter')),
    kind: PointerDeviceKind.mouse,
  );
  await settle(tester);
  await tester.tap(
    find.descendant(
      of: find.byKey(kAnchoredPickerKey),
      matching: find.text(name),
    ),
    kind: PointerDeviceKind.mouse,
  );
  await settle(tester);
}

void main() {
  setUpAll(loadInter);

  screenTest(
    'una persona sin regalos deja los carriles vacíos',
    (tester, phone) async {
      await _mountWeb(tester, phone);
      await tester.runAsync(() => familyOf(phone).deleteGift('g9'));
      await settle(tester);
      await _selectPerson(tester, 'Leo');
      for (final lane in BoardLane.values) {
        expect(
          find.descendant(of: _lane(lane), matching: find.byType(BoardGiftRow)),
          findsNothing,
        );
      }
    },
    size: const Size(1536, 900),
    overrides: _web(),
  );

  screenTest(
    'al borrar la persona seleccionada vuelve a todas',
    (tester, phone) async {
      await _mountWeb(tester, phone);
      await _selectPerson(tester, 'Nora');
      await tester.runAsync(() => familyOf(phone).deleteRecipient('nora'));
      await settle(tester);
      expect(phone.container.read(boardPersonFilterProvider), isNull);
      expect(find.text('Todas las personas'), findsOneWidget);
      expect(
        _rowIn(BoardLane.decide, 'Libro de dinosaurios con solapas'),
        findsOneWidget,
      );
    },
    size: const Size(1536, 900),
    overrides: _web(),
  );

  screenTest(
    'mover un regalo mantiene el filtro y cambia su estado',
    (tester, phone) async {
      await _mountWeb(tester, phone);
      await _selectPerson(tester, 'Aritz');
      final gesture = await tester.startGesture(
        tester.getCenter(_rowIn(BoardLane.decide, 'Patinete')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveBy(const Offset(12, 0));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(_lane(BoardLane.buy)));
      await tester.pump();
      await gesture.up();
      await settle(tester);
      expect(_rowIn(BoardLane.buy, 'Patinete'), findsOneWidget);
      expect(
        phone.container
            .read(boardGiftsProvider)
            .firstWhere((g) => g.title == 'Patinete')
            .status,
        GiftStatus.decided,
      );
      expect(
        find.widgetWithText(BoardGiftRow, 'Puzle de 48 piezas'),
        findsNothing,
      );
    },
    size: const Size(1920, 960),
    overrides: _web(),
  );

  screenTest(
    'el filtro por persona deja solo sus regalos en los carriles y «Todas» los '
    'devuelve',
    (tester, phone) async {
      await _mountWeb(tester, phone);
      final filter = find.byKey(const ValueKey<String>('board-person-filter'));
      expect(filter, findsOneWidget);
      // Del alto de los botones de la cabecera (48), no de un campo (52).
      expect(tester.getSize(filter).height, 48);
      // Sin filtro: regalos de Aritz y de Nora a la vez.
      expect(
        _rowIn(BoardLane.decide, 'Libro de dinosaurios con solapas'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(BoardGiftRow, 'Puzle de 48 piezas'),
        findsWidgets,
      );

      await tester.tap(filter, kind: PointerDeviceKind.mouse);
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byKey(kAnchoredPickerKey),
          matching: find.text('Nora'),
        ),
        kind: PointerDeviceKind.mouse,
      );
      await settle(tester);
      expect(
        find.widgetWithText(BoardGiftRow, 'Libro de dinosaurios con solapas'),
        findsNothing,
      );
      expect(
        find.widgetWithText(BoardGiftRow, 'Puzle de 48 piezas'),
        findsWidgets,
      );

      await tester.tap(filter, kind: PointerDeviceKind.mouse);
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byKey(kAnchoredPickerKey),
          matching: find.text('Todas las personas'),
        ),
        kind: PointerDeviceKind.mouse,
      );
      await settle(tester);
      expect(
        find.widgetWithText(BoardGiftRow, 'Libro de dinosaurios con solapas'),
        findsWidgets,
      );
    },
    size: const Size(1536, 900),
    overrides: _web(),
  );

  screenTest(
    'la búsqueda de la barra lateral mira también la nota y la persona, y '
    'avisa si nada coincide',
    (tester, phone) async {
      await _mountWeb(tester, phone);
      final field = find.descendant(
        of: find.byType(BoardSidebar),
        matching: find.byType(TextField),
      );
      // La variante compacta del mismo campo de los demás sitios.
      expect(
        tester
            .widget<GiftSearchField>(
              find.byKey(const ValueKey<String>('board-sidebar-search')),
            )
            .dense,
        isTrue,
      );
      await tester.enterText(field, 'nora');
      await settle(tester);
      expect(
        find.descendant(
          of: find.byType(GiftSearchResults),
          matching: find.text('Puzle de 48 piezas'),
        ),
        findsWidgets,
      );
      await tester.enterText(field, 'zzzz');
      await settle(tester);
      expect(find.text('Ningún regalo coincide'), findsOneWidget);
      // La cruz borra la búsqueda.
      await tester.tap(find.byTooltip('Borrar la búsqueda'));
      await settle(tester);
      expect(find.byType(GiftSearchResults), findsNothing);
    },
    size: const Size(1536, 900),
    overrides: _web(),
  );
}
