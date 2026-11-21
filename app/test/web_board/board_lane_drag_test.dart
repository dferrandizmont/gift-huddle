// Pasar un regalo de carril en «Qué toca ahora» (la guía de diseño de
// escritorio, A): arrastrando la tarjeta, con Ctrl o Cmd y las flechas ← y →
// o con las acciones del lector de pantalla. Cada carril es un solo estado y
// el regalo pasa al del carril donde se suelta, también hacia atrás.
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/app.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/motion/haptics.dart';
import 'package:regalos/core/sync/model.dart' show Gift, GiftStatus;
import 'package:regalos/core/widgets/status_checkbox.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/web_board/presentation/board_lane_drag.dart';
import 'package:regalos/features/web_board/presentation/board_lane_move.dart';
import 'package:regalos/features/web_board/application/board_lanes.dart';
import 'package:regalos/features/web_board/application/board_metrics.dart';
import 'package:regalos/features/web_board/presentation/board_lanes_view.dart';
import 'package:regalos/features/web_device/application/web_app_provider.dart';
import 'package:regalos/features/web_device/application/web_device_providers.dart';
import 'package:regalos/features/web_device/application/web_sync_engine.dart'
    show WebSyncStatus;

import '../helpers/fonts.dart';
import '../helpers/memory_stores.dart';
import '../helpers/screens.dart';
import '../web_device/presentation/gate_test_support.dart';
import '../widgets/pin_shake_test.dart' show recordHaptics;

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

Finder _inLane(BoardLane lane, String title) =>
    find.descendant(of: _lane(lane), matching: find.text(title));

Gift _gift(FakePhone phone, String title) => phone.container
    .read(boardGiftsProvider)
    .firstWhere((g) => g.title == title);

/// Arrastra con el ratón la tarjeta de [title] hasta el centro de [to] y la
/// suelta (salvo con `release: false`: devuelve el gesto para soltarla luego).
Future<TestGesture> _drag(
  WidgetTester tester,
  String title,
  Finder to, {
  bool release = true,
}) async {
  final from = tester.getCenter(
    find.descendant(
      of: find.byType(BoardLanesView),
      matching: find.text(title),
    ),
  );
  final gesture = await tester.startGesture(
    from,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  // Primero un poco, para pasar el umbral; luego, hasta el carril.
  await gesture.moveBy(const Offset(12, 0));
  await tester.pump();
  await gesture.moveTo(tester.getCenter(to));
  await tester.pump();
  if (release) {
    await gesture.up();
    await settle(tester);
  }
  return gesture;
}

/// Arrastra con el dedo la tarjeta de [title] hasta el centro de [to] y la
/// suelta. Con el dedo, el arrastre espera a la pulsación larga.
Future<TestGesture> _touchDrag(
  WidgetTester tester,
  String title,
  Finder to, {
  bool release = true,
}) async {
  final from = tester.getCenter(
    find.descendant(
      of: find.byType(BoardLanesView),
      matching: find.text(title),
    ),
  );
  final gesture = await tester.startGesture(from);
  await tester.pump();
  // Quieto hasta que pasa la pulsación larga.
  await tester.pump(
    BoardCardDraggable.holdDelay + const Duration(milliseconds: 50),
  );
  // Primero un poco, para pasar el umbral; luego, hasta el carril.
  await gesture.moveBy(const Offset(12, 0));
  await tester.pump();
  await gesture.moveTo(tester.getCenter(to));
  await tester.pump();
  if (release) {
    await gesture.up();
    await settle(tester);
  }
  return gesture;
}

void main() {
  setUpAll(loadInter);

  group('arrastrar una tarjeta a otro carril', () {
    screenTest(
      'soltarla en otro carril le pone el estado de ese carril',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        expect(_gift(phone, 'Patinete').status, GiftStatus.idea);
        await _drag(tester, 'Patinete', _lane(BoardLane.buy));
        expect(_gift(phone, 'Patinete').status, GiftStatus.decided);
        expect(_inLane(BoardLane.buy, 'Patinete'), findsOneWidget);
        expect(_inLane(BoardLane.decide, 'Patinete'), findsNothing);
        // El aviso dice dónde ha quedado y deja deshacer.
        expect(find.text('Patinete: Por comprar'), findsOneWidget);
        expect(find.text('Deshacer'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1920, 960),
      overrides: _web(),
    );

    screenTest(
      'también hacia atrás, saltando carriles',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        // Comprado → idea.
        expect(_gift(phone, 'Tren de madera').status, GiftStatus.bought);
        await _drag(tester, 'Tren de madera', _lane(BoardLane.decide));
        expect(_gift(phone, 'Tren de madera').status, GiftStatus.idea);
        // Y adelante, hasta «Listo».
        await _drag(tester, 'Patinete', _lane(BoardLane.ready));
        expect(_gift(phone, 'Patinete').status, GiftStatus.wrapped);
        expect(_inLane(BoardLane.ready, 'Patinete'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1920, 960),
      overrides: _web(),
    );

    screenTest(
      'soltarla en su carril no cambia nada ni avisa',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        await _drag(tester, 'Patinete', _lane(BoardLane.decide));
        expect(_gift(phone, 'Patinete').status, GiftStatus.idea);
        expect(_inLane(BoardLane.decide, 'Patinete'), findsOneWidget);
        expect(find.text('Deshacer'), findsNothing);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1920, 960),
      overrides: _web(),
    );

    screenTest(
      'soltarla fuera de los carriles no cambia nada',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        await _drag(tester, 'Patinete', find.text('Hoy').first);
        expect(_gift(phone, 'Patinete').status, GiftStatus.idea);
        expect(find.text('Deshacer'), findsNothing);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1920, 960),
      overrides: _web(),
    );

    screenTest(
      'mientras se arrastra, el carril de destino se tiñe y la tarjeta flota',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        final lane = _lane(BoardLane.buy);
        Color? colorOf() {
          final box = tester.widget<AnimatedContainer>(lane);
          return (box.decoration as BoxDecoration?)?.color;
        }

        final before = colorOf();
        final gesture = await _drag(tester, 'Patinete', lane, release: false);
        await tester.pump(const Duration(milliseconds: 200));
        expect(colorOf(), isNot(before));
        // La que flota va en el `Overlay`, escalada.
        expect(
          find.byWidgetPredicate(
            (w) => w is Transform && w.transform.getMaxScaleOnAxis() > 1.0,
          ),
          findsWidgets,
        );
        await gesture.up();
        await settle(tester);
        expect(_gift(phone, 'Patinete').status, GiftStatus.decided);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1920, 960),
      overrides: _web(),
    );

    screenTest(
      'Deshacer devuelve el regalo a su carril',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        await _drag(tester, 'Patinete', _lane(BoardLane.arrive));
        expect(_gift(phone, 'Patinete').status, GiftStatus.bought);
        await tester.tap(find.text('Deshacer'));
        await settle(tester);
        expect(_gift(phone, 'Patinete').status, GiftStatus.idea);
        expect(_inLane(BoardLane.decide, 'Patinete'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1920, 960),
      overrides: _web(),
    );
  });

  group('vibración del arrastre', () {
    screenTest(
      'con el dedo, al empezar el arrastre suena un clic',
      (tester, phone) async {
        final haptics = recordHaptics(tester);
        await _mountWeb(tester, phone);
        await _touchDrag(tester, 'Patinete', _lane(BoardLane.buy));
        // El regalo se movió de verdad: el gesto fue un arrastre.
        expect(_gift(phone, 'Patinete').status, GiftStatus.decided);
        expect(haptics, contains('HapticFeedbackType.selectionClick'));
        expect(tester.takeException(), isNull);
      },
      size: const Size(1920, 960),
      overrides: _web(),
    );

    screenTest(
      'con las vibraciones apagadas en Ajustes, el arrastre no suena',
      (tester, phone) async {
        final haptics = recordHaptics(tester);
        await _mountWeb(tester, phone);
        await _touchDrag(tester, 'Patinete', _lane(BoardLane.buy));
        expect(_gift(phone, 'Patinete').status, GiftStatus.decided);
        expect(haptics, isEmpty);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1920, 960),
      overrides: _web(),
      prefs: {kHapticsEnabledKey: false},
    );
  });

  group('Deshacer del aviso', () {
    Future<void> undo(WidgetTester tester) async {
      // Como una persona: tarda un par de segundos y pulsa de verdad el
      // botón del aviso.
      await tester.pump(const Duration(milliseconds: 1500));
      final action = find.byType(SnackBarAction);
      expect(action, findsOneWidget);
      await tester.tap(action);
      await settle(tester);
    }

    screenTest(
      'tras arrastrar una tarjeta, el botón del aviso la devuelve',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        await _drag(tester, 'Patinete', _lane(BoardLane.buy));
        expect(_gift(phone, 'Patinete').status, GiftStatus.decided);
        await undo(tester);
        expect(_gift(phone, 'Patinete').status, GiftStatus.idea);
        expect(_inLane(BoardLane.decide, 'Patinete'), findsOneWidget);
        expect(_inLane(BoardLane.buy, 'Patinete'), findsNothing);
      },
      size: const Size(1920, 960),
      overrides: _web(),
    );

    screenTest(
      'tras pulsar el círculo de estado, el botón del aviso lo devuelve',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        final check = find.descendant(
          of: find.widgetWithText(BoardGiftRow, 'Patinete').first,
          matching: find.byType(InkResponse),
        );
        await tester.tap(check.first);
        await settle(tester);
        expect(_gift(phone, 'Patinete').status, GiftStatus.decided);
        await undo(tester);
        expect(_gift(phone, 'Patinete').status, GiftStatus.idea);
        expect(_inLane(BoardLane.decide, 'Patinete'), findsOneWidget);
        expect(_inLane(BoardLane.buy, 'Patinete'), findsNothing);
      },
      size: const Size(1920, 960),
      overrides: _web(),
    );
  });

  group('con el teclado y el lector de pantalla', () {
    Future<void> chord(
      WidgetTester tester,
      LogicalKeyboardKey modifier,
      LogicalKeyboardKey key,
    ) async {
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(modifier);
      await settle(tester);
    }

    screenTest(
      'Ctrl con → y ← mueve el regalo marcado al carril de al lado',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        final cursor = phone.container.read(boardGiftCursorProvider);
        cursor.set(_gift(phone, 'Patinete').id);
        await settle(tester);
        await chord(
          tester,
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.arrowRight,
        );
        expect(_gift(phone, 'Patinete').status, GiftStatus.decided);
        expect(_inLane(BoardLane.buy, 'Patinete'), findsOneWidget);
        expect(find.text('Patinete: Por comprar'), findsOneWidget);
        // La marca sigue en el regalo: otra vez, y de vuelta atrás.
        expect(cursor.current, _gift(phone, 'Patinete').id);
        await chord(
          tester,
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.arrowRight,
        );
        expect(_gift(phone, 'Patinete').status, GiftStatus.bought);
        await chord(
          tester,
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.arrowLeft,
        );
        expect(_gift(phone, 'Patinete').status, GiftStatus.decided);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1920, 960),
      overrides: _web(),
    );

    screenTest(
      'Cmd también, y no sigue más allá del primer ni del último carril',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        final cursor = phone.container.read(boardGiftCursorProvider);
        cursor.set(_gift(phone, 'Patinete').id);
        await settle(tester);
        // Ya está en el primero: ← no hace nada.
        await chord(
          tester,
          LogicalKeyboardKey.metaLeft,
          LogicalKeyboardKey.arrowLeft,
        );
        expect(_gift(phone, 'Patinete').status, GiftStatus.idea);
        expect(find.text('Deshacer'), findsNothing);
        for (var i = 0; i < 6; i++) {
          await chord(
            tester,
            LogicalKeyboardKey.metaLeft,
            LogicalKeyboardKey.arrowRight,
          );
        }
        // El último carril es «Listo» (envuelto): no pasa a entregado.
        expect(_gift(phone, 'Patinete').status, GiftStatus.wrapped);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1920, 960),
      overrides: _web(),
    );

    screenTest(
      'sin regalo marcado, Ctrl con las flechas no hace nada',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        await chord(
          tester,
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.arrowRight,
        );
        expect(_gift(phone, 'Patinete').status, GiftStatus.idea);
        expect(find.text('Deshacer'), findsNothing);
      },
      size: const Size(1920, 960),
      overrides: _web(),
    );

    screenTest(
      'la fila ofrece «Mover a…» a los lectores de pantalla',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        final node = tester.getSemantics(
          find.descendant(
            of: _lane(BoardLane.decide),
            matching: find.text('Patinete'),
          ),
        );
        final ids = node.getSemanticsData().customSemanticsActionIds ?? [];
        final labels = [
          for (final id in ids) CustomSemanticsAction.getAction(id)!.label,
        ];
        // Todos los carriles menos en el que está.
        // (el orden lo da el de creación de las acciones, que no importa).
        expect(
          labels,
          unorderedEquals([
            'Mover a «Por comprar»',
            'Mover a «Por llegar»',
            'Mover a «Por envolver»',
            'Mover a «Listo»',
          ]),
        );
        // Pedir una la ejecuta.
        final action = CustomSemanticsAction(label: 'Mover a «Por llegar»');
        tester.semantics.performAction(
          find.semantics.byPredicate((n) => n.id == node.id),
          SemanticsAction.customAction,
          args: CustomSemanticsAction.getIdentifier(action),
        );
        await settle(tester);
        expect(_gift(phone, 'Patinete').status, GiftStatus.bought);
        expect(find.text('Patinete: Por llegar'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1920, 960),
      overrides: _web(),
    );
  });

  group('revisión: foco, arrastre desmontado y «Listo» plegado', () {
    // Tabula (con el teclado, así que el foco se ve) hasta que [test] diga que
    // el foco está donde se busca.
    Future<void> tabUntil(
      WidgetTester tester,
      bool Function(BuildContext focused) test,
    ) async {
      for (var i = 0; i < 400; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final context = FocusManager.instance.primaryFocus?.context;
        if (context != null && test(context)) {
          return;
        }
      }
      fail('el foco no llegó');
    }

    screenTest(
      'tabulando del texto de una fila a la casilla de otra, el atajo mueve la '
      'segunda',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        final cursor = phone.container.read(boardGiftCursorProvider);
        // Foco en el texto de «Patinete».
        await tabUntil(tester, (c) {
          final row = c.findAncestorWidgetOfExactType<BoardGiftRow>();
          return row?.gift.title == 'Patinete' &&
              c.findAncestorWidgetOfExactType<StatusCheckbox>() == null;
        });
        expect(cursor.current, _gift(phone, 'Patinete').id);
        // Y a la casilla de otro regalo.
        await tabUntil(tester, (c) {
          final row = c.findAncestorWidgetOfExactType<BoardGiftRow>();
          return row?.gift.title == 'Bici de 20" con cambios' &&
              c.findAncestorWidgetOfExactType<StatusCheckbox>() != null;
        });
        expect(cursor.current, _gift(phone, 'Bici de 20" con cambios').id);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await settle(tester);
        expect(
          _gift(phone, 'Bici de 20" con cambios').status,
          GiftStatus.bought,
        );
        expect(_gift(phone, 'Patinete').status, GiftStatus.idea);
      },
      size: const Size(1920, 960),
      overrides: _web(),
    );

    screenTest(
      'si el regalo arrastrado desaparece, no salta ninguna excepción y el '
      'puntero compartido se limpia',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        final pointer = phone.container.read(boardDragPointerProvider);
        final id = _gift(phone, 'Patinete').id;
        final gesture = await _drag(
          tester,
          'Patinete',
          _lane(BoardLane.buy),
          release: false,
        );
        expect(pointer.value, isNotNull);
        // Otro móvil lo borra con el botón aún pulsado.
        await tester.runAsync(
          () => phone.container
              .read(familyControllerProvider.notifier)
              .deleteGift(id),
        );
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        // Al irse la tarjeta, el arrastre se da por terminado sin esperar a
        // soltar.
        expect(pointer.value, isNull);
        await gesture.moveBy(const Offset(10, 10));
        await tester.pump();
        await gesture.up();
        await settle(tester);
        expect(pointer.value, isNull);
        expect(find.text('Patinete'), findsNothing);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1920, 960),
      overrides: _web(),
    );

    screenTest(
      'con «Listo» plegado, mover con el teclado a «Listo» lo abre y la marca '
      'sigue: el atajo lo devuelve',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        expect(
          find.byKey(const ValueKey<String>('board-lane-ready')),
          findsNothing,
        );
        final cursor = phone.container.read(boardGiftCursorProvider);
        final id = _gift(phone, 'Patinete').id;
        cursor.set(id);
        await settle(tester);
        Future<void> chord(LogicalKeyboardKey key) async {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(key);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await settle(tester);
        }

        for (var i = 0; i < 4; i++) {
          await chord(LogicalKeyboardKey.arrowRight);
        }
        expect(_gift(phone, 'Patinete').status, GiftStatus.wrapped);
        // El panel de «Listo» se ha abierto, con el regalo dentro y marcado.
        expect(_inLane(BoardLane.ready, 'Patinete'), findsOneWidget);
        expect(cursor.current, id);
        await chord(LogicalKeyboardKey.arrowLeft);
        expect(_gift(phone, 'Patinete').status, GiftStatus.arrived);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1280, 720),
      overrides: _web(),
    );
  });

  group('revisión: dos tableros montados', () {
    screenTest(
      'tras ir de «Hoy» a una ocasión, mover a «Listo» plegado abre el panel '
      'del tablero visible y la marca sigue',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        // «Hoy» queda montado (sin verse) al abrir la ocasión.
        phone.container.read(routerProvider).go('/occasions/seed-kings');
        await settle(tester);
        final cursor = phone.container.read(boardGiftCursorProvider);
        final id = _gift(phone, 'Patinete').id;
        cursor.set(id);
        await settle(tester);
        Future<void> chord(LogicalKeyboardKey key) async {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(key);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await settle(tester);
        }

        for (var i = 0; i < 4; i++) {
          await chord(LogicalKeyboardKey.arrowRight);
        }
        expect(_gift(phone, 'Patinete').status, GiftStatus.wrapped);
        expect(_inLane(BoardLane.ready, 'Patinete'), findsOneWidget);
        expect(cursor.current, id);
        await chord(LogicalKeyboardKey.arrowLeft);
        expect(_gift(phone, 'Patinete').status, GiftStatus.arrived);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1280, 720),
      overrides: _web(),
    );
  });

  group('barras de desplazamiento', () {
    screenTest(
      'cada carril lleva una sola barra (en escritorio Material ya la pone)',
      (tester, phone) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          await _mountWeb(tester, phone);
          expect(
            find.descendant(
              of: _lane(BoardLane.decide),
              matching: find.byWidgetPredicate((w) => w is RawScrollbar),
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
      size: const Size(1920, 960),
      overrides: _web(),
    );
  });
}
