import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/layout/pane_selection.dart';
import 'package:regalos/core/layout/smooth_wheel.dart';
import 'package:regalos/core/motion/shared_axis_switcher.dart';
import 'package:regalos/core/widgets/focus_ring.dart';
import 'package:regalos/core/widgets/person_avatar.dart';
import 'package:regalos/core/widgets/settings_row.dart';
import 'package:regalos/features/people/presentation/people_screen.dart';
import 'package:regalos/features/settings/presentation/settings_screen.dart';

import '../helpers/memory_stores.dart';
import '../helpers/pump_app.dart';
import '../helpers/screens.dart';
import '../helpers/settings_column.dart';

// La tanda 1 de la web de escritorio (la guía de diseño de escritorio, §3 y §4): navegar tiene que notarse inmediato.

const _desktop = Size(1280, 800);

String _path(FakePhone phone) => phone.container
    .read(routerProvider)
    .routeInformationProvider
    .value
    .uri
    .path;

Finder _row(String name) =>
    find.descendant(of: find.byType(PeopleListPane), matching: find.text(name));

Widget _host(Widget child, {bool reduce = false}) => MediaQuery(
  data: MediaQueryData(disableAnimations: reduce),
  child: Directionality(textDirection: TextDirection.ltr, child: child),
);

void main() {
  group('cambiar de persona con dos paneles', () {
    screenTest('las filas del detalle no repiten su entrada escalonada', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.tap(_row('Nora'));
      await tester.pump();
      // Pasado el fundido de 120 ms, nada del detalle sigue entrando: con
      // la cascada de antes quedaban más de 500 ms de movimiento.
      await tester.pump(const Duration(milliseconds: 200));
      final row = find.text('Cocinita de madera');
      expect(row, findsOneWidget);
      final fades = tester.widgetList<FadeTransition>(
        find.ancestor(of: row, matching: find.byType(FadeTransition)),
      );
      expect(
        fades.map((f) => f.opacity.value).fold<double>(1, (a, b) => a * b),
        1,
      );
      final shift = tester
          .widgetList<Transform>(
            find.ancestor(of: row, matching: find.byType(Transform)),
          )
          .map((t) => t.transform.getTranslation().y.abs())
          .fold<double>(0, (a, b) => a + b);
      expect(shift, 0);
      expect(tester.takeException(), isNull);
      await settle(tester);
    }, size: _desktop);

    screenTest(
      'no hay vuelo del avatar: ningún avatar de más ni de tamaño intermedio',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        final before = find.byType(PersonAvatar).evaluate().length;
        await tester.tap(_row('Leo'));
        await tester.pump();
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          expect(find.byType(PersonAvatar).evaluate().length, before);
        }
        await settle(tester);
      },
      size: _desktop,
    );

    screenTest('el recuadro de selección llega en unos 160 ms', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      expect(kSelectionTravel, const Duration(milliseconds: 160));
      await tester.tap(_row('Nora'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 170));
      // Con el viaje acabado, un fotograma más no mueve nada.
      final selection = find.byType(SelectionScope);
      expect(selection, findsWidgets);
      expect(tester.takeException(), isNull);
      await settle(tester);
    }, size: _desktop);
  });

  group('Ajustes con una sola página para el detalle', () {
    screenTest(
      '/settings/:section conserva la lista montada al cambiar de apartado',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await openSettingsTab(tester);
        expect(_path(phone), '/settings/people');
        final list = find.descendant(
          of: find.byType(SettingsScreen),
          matching: find.byType(SelectionScope),
        );
        final before = tester.state(list);
        final navigator = find.byType(Navigator);
        expect(navigator, findsWidgets);
        await tester.tap(
          find.descendant(
            of: find.byType(SettingsScreen),
            matching: find.widgetWithText(SettingsRow, 'Apariencia'),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));
        expect(_path(phone), '/settings/appearance');
        expect(
          identical(tester.state(list), before),
          isTrue,
          reason: 'la lista de apartados es la misma, no se montó de nuevo',
        );
        await settle(tester);
        expect(identical(tester.state(list), before), isTrue);
        // El atrás del sistema no vuelve por los apartados tocados.
        expect(find.byType(SettingsScreen), findsOneWidget);
      },
      size: _desktop,
    );

    screenTest('un apartado que no existe vuelve a la lista', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      phone.container.read(routerProvider).go('/settings/inventado');
      await settle(tester);
      expect(_path(phone), isNot('/settings/inventado'));
      expect(_path(phone).startsWith('/settings'), isTrue);
    }, size: _desktop);

    screenTest('/occasions/budget sigue siendo una URL válida', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      phone.container.read(routerProvider).go('/occasions/budget');
      await settle(tester);
      expect(_path(phone), '/occasions/budget');
      expect(tester.takeException(), isNull);
    }, size: _desktop);
  });

  group('cambiador de eje compartido en dos paneles', () {
    Widget switcher(int index, {bool reduce = false}) => _host(
      SharedAxisSwitcher(
        index: index,
        fadeOnly: true,
        child: Text('Paso $index'),
      ),
      reduce: reduce,
    );

    testWidgets('el que se va desaparece en el acto y el que llega se funde '
        'en 120 ms sin trasladarse', (tester) async {
      await tester.pumpWidget(switcher(0));
      await tester.pumpWidget(switcher(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('Paso 0'), findsNothing);
      final fade = tester.widget<FadeTransition>(
        find.ancestor(
          of: find.text('Paso 1'),
          matching: find.byType(FadeTransition),
        ),
      );
      expect(fade.opacity.value, lessThan(1));
      expect(
        find.ancestor(
          of: find.text('Paso 1'),
          matching: find.byType(Transform),
        ),
        findsNothing,
        reason: 'sin traslación',
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(fade.opacity.value, inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 70));
      expect(fade.opacity.value, 1);
    });

    testWidgets('con «Reducir movimiento» se cruzan con un fundido de 150 ms', (
      tester,
    ) async {
      await tester.pumpWidget(switcher(0, reduce: true));
      await tester.pumpWidget(switcher(1, reduce: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Paso 0'), findsOneWidget);
      expect(find.text('Paso 1'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('Paso 0'), findsNothing);
    });

    testWidgets('en móvil (sin fadeOnly) mantiene el eje de siempre', (
      tester,
    ) async {
      Widget axis(int index) =>
          _host(SharedAxisSwitcher(index: index, child: Text('Paso $index')));
      await tester.pumpWidget(axis(0));
      await tester.pumpWidget(axis(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('Paso 0'), findsOneWidget, reason: 'el que sale tarda');
      final shift = tester
          .widgetList<Transform>(
            find.ancestor(
              of: find.text('Paso 1'),
              matching: find.byType(Transform),
            ),
          )
          .map((t) => t.transform.getTranslation().x.abs())
          .fold<double>(0, (a, b) => a + b);
      expect(shift, greaterThan(0));
      await tester.pumpAndSettle();
    });
  });

  group('rueda del ratón', () {
    Future<ScrollController> pumpList(WidgetTester tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          SmoothWheel(
            child: ListView(
              controller: controller,
              children: [
                for (var i = 0; i < 60; i++)
                  SizedBox(height: 50, child: Text('Fila $i')),
              ],
            ),
          ),
        ),
      );
      return controller;
    }

    testWidgets('una muesca anima el desplazamiento en vez de saltar', (
      tester,
    ) async {
      final controller = await pumpList(tester);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(const Offset(100, 100)));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 100)));
      await tester.pump();
      expect(controller.offset, lessThan(100), reason: 'no salta de golpe');
      await tester.pump(const Duration(milliseconds: 60));
      expect(controller.offset, inExclusiveRange(0, 100));
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(100, 0.5));
    });

    testWidgets('varias muescas seguidas se suman', (tester) async {
      final controller = await pumpList(tester);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(const Offset(100, 100)));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 100)));
      await tester.pump(const Duration(milliseconds: 40));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 100)));
      await tester.pump(const Duration(milliseconds: 40));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 100)));
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(300, 0.01));
    });

    testWidgets('no pasa del final de la lista', (tester) async {
      final controller = await pumpList(tester);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(const Offset(100, 100)));
      for (var i = 0; i < 40; i++) {
        await tester.sendEventToBinding(mouse.scroll(const Offset(0, 100)));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();
      expect(controller.offset, controller.position.maxScrollExtent);
    });

    testWidgets('el trackpad no se toca: salta como siempre', (tester) async {
      final controller = await pumpList(tester);
      final pad = TestPointer(2, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(pad.hover(const Offset(100, 100)));
      await tester.sendEventToBinding(pad.scroll(const Offset(0, 100)));
      await tester.pump();
      expect(controller.offset, 100);
    });

    testWidgets('con «Reducir movimiento» salta como siempre', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          SmoothWheel(
            child: ListView(
              controller: controller,
              children: [
                for (var i = 0; i < 60; i++)
                  SizedBox(height: 50, child: Text('Fila $i')),
              ],
            ),
          ),
          reduce: true,
        ),
      );
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(const Offset(100, 100)));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 100)));
      await tester.pump();
      expect(controller.offset, 100);
    });
  });

  group('foco con teclado', () {
    testWidgets('el filete viaja de un control a otro en 120 ms', (
      tester,
    ) async {
      final a = FocusNode();
      final b = FocusNode();
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await pumpThemed(
        tester,
        FocusRingOverlay(
          child: Column(
            children: [
              Focus(
                focusNode: a,
                child: const SizedBox(width: 100, height: 40),
              ),
              const SizedBox(height: 200),
              Focus(
                focusNode: b,
                child: const SizedBox(width: 100, height: 40),
              ),
            ],
          ),
        ),
      );
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      a.requestFocus();
      await tester.pump();
      await tester.pump();
      Rect? ring() {
        final painter = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((p) => p.painter)
            .whereType<FocusRingPainter>()
            .first;
        return painter.rect;
      }

      final onA = ring();
      expect(onA, isNotNull);
      b.requestFocus();
      // El foco pasa, se mide el filete y arranca el viaje (el primer
      // fotograma de un ticker es el de tiempo cero).
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 40));
      final middle = ring()!;
      expect(middle.top, greaterThan(onA!.top));
      expect(middle.top, lessThan(240), reason: 'todavía de camino a B');
      await tester.pump(const Duration(milliseconds: 100));
      expect(ring()!.top, greaterThan(middle.top));
      await tester.pump(const Duration(milliseconds: 60));
      expect(ring()!.top, closeTo(240, 1));
    });
  });
}
