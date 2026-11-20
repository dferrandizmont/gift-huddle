// La página de una persona en la web: la tarjeta del presupuesto de la casa
// ocupa el ancho de la tabla, su barra se rellena una vez al aparecer y el
// círculo de estado dice el estado al pasar el ratón.
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/app.dart';
import 'package:regalos/core/layout/ui_scale.dart';
import 'package:regalos/core/motion/completion_ring.dart';
import 'package:regalos/core/motion/sheen.dart';
import 'package:regalos/core/widgets/budget_meter.dart';
import 'package:regalos/core/widgets/filter_pill.dart';
import 'package:regalos/core/widgets/status_checkbox.dart';
import 'package:regalos/features/web_board/presentation/board_gift_table.dart';
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

/// Abre a [name] sin esperar a que acaben las animaciones de entrada.
Future<void> _openPersonNoSettle(WidgetTester tester, String name) async {
  await tester.tap(
    find.descendant(of: find.byType(BoardSidebar), matching: find.text(name)),
  );
  await tester.pump();
}

/// La tarjeta del presupuesto de la casa de la página de la persona.
Finder get _card => find.ancestor(
  of: find.byType(BudgetMeter).first,
  matching: find.byType(Sheen),
);

/// El relleno de la primera barra de la tarjeta, de 0 a 1.
double _fill(WidgetTester tester) {
  final bar = find.descendant(
    of: find.byType(BudgetBar).first,
    matching: find.byType(FractionallySizedBox),
  );
  return tester.widget<FractionallySizedBox>(bar.first).widthFactor!;
}

void main() {
  setUpAll(loadInter);

  group('tarjeta de gastos de la persona', () {
    screenTest(
      'a 1440 ocupa el ancho de la tabla con los bordes alineados por los dos lados',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        await _openPersonNoSettle(tester, 'Aritz');
        await settle(tester);
        final card = tester.getRect(_card);
        final row = tester.getRect(find.byType(BoardGiftTableRow).first);
        // Mismo margen a cada lado que la tabla (16 puntos).
        expect(card.left, closeTo(row.left + 16, 0.5));
        expect(card.right, closeTo(row.right - 16, 0.5));
        expect(tester.takeException(), isNull);
      },
      size: const Size(1440, 900),
      overrides: _web(),
    );

    screenTest(
      'a 3440 se alinea a la izquierda con la tabla y no pasa de 1200',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        await _openPersonNoSettle(tester, 'Aritz');
        await settle(tester);
        final card = tester.getRect(_card);
        final row = tester.getRect(find.byType(BoardGiftTableRow).first);
        // La ventana se escala (1,3 a 3440): los 16 y los 1200 son lógicos.
        final scale = UiScaleSteps.forWindow(3440);
        expect(card.left, closeTo(row.left + 16 * scale, 0.5));
        expect(card.width, closeTo(1200 * scale, 0.5));
        expect(card.right, lessThan(row.right - 16 * scale));
        expect(tester.takeException(), isNull);
      },
      size: const Size(3440, 1200),
      overrides: _web(),
    );

    screenTest(
      'el avatar, la tarjeta, los filtros y la tabla empiezan en el mismo borde izquierdo',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        await _openPersonNoSettle(tester, 'Aritz');
        await settle(tester);
        final avatar = tester.getRect(find.byType(CompletionAvatar)).left;
        final card = tester.getRect(_card).left;
        final filters = tester
            .getRect(
              find.ancestor(
                of: find.text('Filtros'),
                matching: find.byType(FilterPill),
              ),
            )
            .left;
        final row = tester.getRect(find.byType(BoardGiftTableRow).first).left;
        // La tabla dibuja sus filetes a 16 de su borde.
        final rule = row + 16;
        expect(card, closeTo(rule, 0.5));
        expect(filters, closeTo(card, 0.5));
        expect(avatar, closeTo(card, 0.5));
        expect(tester.takeException(), isNull);
      },
      size: const Size(1440, 900),
      overrides: _web(),
    );

    screenTest(
      'la barra mide 10 de alto y se rellena desde 0 una sola vez',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        await _openPersonNoSettle(tester, 'Aritz');
        final bar = tester.widget<BudgetBar>(find.byType(BudgetBar).first);
        expect(bar.height, 10);
        expect(bar.radius, lessThanOrEqualTo(4));
        final target = bar.fraction.clamp(0.0, 1.0);
        expect(target, greaterThan(0));
        // Al aparecer: casi vacía.
        await tester.pump(const Duration(milliseconds: 40));
        expect(_fill(tester), lessThan(target * 0.5));
        // A medias del camino.
        await tester.pump(const Duration(milliseconds: 260));
        final mid = _fill(tester);
        expect(mid, greaterThan(0));
        expect(mid, lessThan(target));
        // Al cabo de 600 ms (y el margen de la entrada de la pantalla): llena.
        await tester.pump(const Duration(milliseconds: 900));
        expect(_fill(tester), closeTo(target, 1e-6));
        // Reconstruir la pantalla no la vacía ni la vuelve a rellenar.
        await tester.pump(const Duration(milliseconds: 16));
        expect(_fill(tester), closeTo(target, 1e-6));
        await settle(tester);
        expect(_fill(tester), closeTo(target, 1e-6));
        expect(tester.takeException(), isNull);
      },
      size: const Size(1440, 900),
      overrides: _web(),
    );

    screenTest(
      'con «Reducir movimiento» la barra aparece ya llena',
      (tester, phone) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await _mountWeb(tester, phone);
        await _openPersonNoSettle(tester, 'Aritz');
        final target = tester
            .widget<BudgetBar>(find.byType(BudgetBar).first)
            .fraction
            .clamp(0.0, 1.0);
        await tester.pump(const Duration(milliseconds: 20));
        expect(_fill(tester), closeTo(target, 1e-6));
        expect(tester.takeException(), isNull);
      },
      size: const Size(1440, 900),
      overrides: _web(),
    );
  });

  group('círculo de estado', () {
    screenTest(
      'al pasar el ratón dice el estado, lo lee un lector y no estorba al clic',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        await _openPersonNoSettle(tester, 'Aritz');
        await settle(tester);
        final row = tester.widget<BoardGiftTableRow>(
          find.byType(BoardGiftTableRow).first,
        );
        const names = {
          'idea': 'Idea',
          'decided': 'Decidido',
          'bought': 'Comprado',
          'arrived': 'Llegó',
          'wrapped': 'Envuelto',
          'delivered': 'Entregado',
        };
        final name = names[row.status.name]!;
        final checkbox = find
            .descendant(
              of: find.byType(BoardGiftTableRow).first,
              matching: find.byType(StatusCheckbox),
            )
            .first;
        // Hay un tooltip con el nombre del estado.
        final tip = tester.widget<Tooltip>(
          find.descendant(of: checkbox, matching: find.byType(Tooltip)),
        );
        expect(tip.message, name);
        // Y la etiqueta accesible del círculo lleva el estado.
        final semantics = tester.getSemantics(checkbox);
        expect(semantics.label, contains(name));
        expect(
          semantics.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
        // Sin el ratón encima, no se ve.
        final before = find.text(name).evaluate().length;
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(checkbox));
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text(name).evaluate().length, before + 1);
        // El clic con el ratón encima sigue cambiando el estado.
        await mouse.down(tester.getCenter(checkbox));
        await mouse.up();
        await settle(tester);
        final after = tester.widget<BoardGiftTableRow>(
          find.byType(BoardGiftTableRow).first,
        );
        expect(after.status, isNot(row.status));
        expect(tester.takeException(), isNull);
      },
      size: const Size(1440, 900),
      overrides: _web(),
    );
  });
}
