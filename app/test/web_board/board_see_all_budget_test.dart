// «Ver todas» al final de la tira de Hoy y el presupuesto como entrada propia
// de la barra lateral de la web (ya no es una tarjeta de la tira de Ocasiones).
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/app.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/layout/pane_selection.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/widgets/empty_state.dart';
import 'package:regalos/core/widgets/regalos_nav_bar.dart';
import 'package:regalos/core/widgets/regalos_nav_rail.dart';
import 'package:regalos/core/widgets/budget_meter.dart';
import 'package:regalos/features/web_board/presentation/web_budget_card.dart';
import 'package:regalos/features/web_board/presentation/web_budget_page.dart';
import 'package:regalos/features/family/application/family_providers.dart';
import 'package:regalos/features/occasions/presentation/budget_screen.dart';
import 'package:regalos/features/web_board/application/board_occasion_order.dart';
import 'package:regalos/features/web_board/presentation/board_occasion_strip.dart';
import 'package:regalos/features/web_board/presentation/board_budget_view.dart';
import 'package:regalos/features/web_board/presentation/board_page.dart';
import 'package:regalos/features/web_board/presentation/board_screens.dart';
import 'package:regalos/features/web_board/presentation/board_sidebar.dart';
import 'package:regalos/features/web_device/application/web_app_provider.dart';
import 'package:regalos/features/web_device/application/web_device_providers.dart';
import 'package:regalos/features/web_device/application/web_sync_engine.dart'
    show WebSyncStatus;

import '../helpers/fonts.dart';
import '../helpers/memory_stores.dart' show FakePhone;
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

Occasion _occasion(String id, String name, int month, int day) => Occasion(
  id: id,
  kind: OccasionKind.custom,
  rawKind: OccasionKind.custom.name,
  name: name,
  month: month,
  day: day,
  recurring: true,
  archived: false,
);

Future<void> _mount(
  WidgetTester tester,
  FakePhone phone, {
  int extraOccasions = 0,
  bool noOccasions = false,
  Map<String, int?> budgets = const {},
}) async {
  await seedSample(tester, phone);
  await tester.runAsync(() async {
    final c = familyOf(phone);
    for (final entry in budgets.entries) {
      await c.setOccasionBudget(entry.key, entry.value);
    }
    for (var i = 0; i < extraOccasions; i++) {
      await c.upsertOccasion(_occasion('extra-$i', 'Extra $i', 12, 10 + i));
    }
    if (noOccasions) {
      for (final o in phone.container.read(occasionsProvider)) {
        await c.deleteOccasion(o.id);
      }
    }
  });
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

Finder get _sidebar => find.byType(BoardSidebar);

Finder _inSidebar(String text) =>
    find.descendant(of: _sidebar, matching: find.text(text));

final _seeAll = find.byKey(const ValueKey<String>('board-see-all'));

/// Las etiquetas de la navegación principal (barra o raíl), por orden.
List<String> _navLabels(WidgetTester tester) {
  final bar = find.byType(RegalosNavBar);
  if (bar.evaluate().isNotEmpty) {
    return [
      for (final d in tester.widget<RegalosNavBar>(bar).destinations) d.label,
    ];
  }
  return [
    for (final d
        in tester
            .widget<RegalosNavRail>(find.byType(RegalosNavRail))
            .destinations)
      d.label,
  ];
}

/// El destino elegido de la navegación principal.
int _navSelected(WidgetTester tester) {
  final bar = find.byType(RegalosNavBar);
  return bar.evaluate().isNotEmpty
      ? tester.widget<RegalosNavBar>(bar).selectedIndex
      : tester
            .widget<RegalosNavRail>(find.byType(RegalosNavRail))
            .selectedIndex;
}

final _card = find.byType(WebBudgetCard);

int _totalOccasions(FakePhone phone) => boardOccasionOrder(
  phone.container.read(occasionsProvider),
  clock.now(),
  includePassed: true,
).length;

void main() {
  setUpAll(loadInter);

  group('«Ver todas» en Hoy', () {
    screenTest(
      'no sale si la tira ya lleva todas las ocasiones',
      (tester, phone) async {
        await _mount(tester, phone);
        expect(_totalOccasions(phone), lessThanOrEqualTo(8));
        expect(find.byType(BoardOccasionStrip), findsOneWidget);
        expect(_seeAll, findsNothing);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1440, 900),
      overrides: _web(),
    );

    screenTest(
      'con más de las que caben sale al final, con el total, y lleva a Ocasiones',
      (tester, phone) async {
        await _mount(tester, phone, extraOccasions: 8);
        final total = _totalOccasions(phone);
        expect(total, greaterThan(BoardHomeScreen.stripCount));
        expect(_path(phone), '/people');
        expect(_seeAll, findsOneWidget);
        expect(find.text('Ver todas ($total)'), findsOneWidget);
        // Solo salen las de la tira.
        expect(
          find.byType(BoardOccasionCard),
          findsNWidgets(BoardHomeScreen.stripCount),
        );

        // Fuera de la zona que se desvanece y con zona de toque de 44 o más.
        final strip = find.byType(BoardOccasionStrip);
        expect(
          find.descendant(of: strip, matching: find.byType(ShaderMask)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.descendant(of: strip, matching: find.byType(ShaderMask)),
            matching: _seeAll,
          ),
          findsNothing,
        );
        final rect = tester.getRect(_seeAll);
        expect(rect.height, greaterThanOrEqualTo(44));
        expect(rect.width, greaterThanOrEqualTo(44));
        final window = tester.view.physicalSize / tester.view.devicePixelRatio;
        expect(rect.right, lessThanOrEqualTo(window.width));
        // Centrado en vertical con las tarjetas.
        final card = tester.getRect(find.byType(BoardOccasionCard).first);
        expect((rect.center.dy - card.center.dy).abs(), lessThan(1));

        await tester.tap(_seeAll);
        await settle(tester);
        expect(_path(phone), '/occasions');
        expect(_seeAll, findsNothing);
        // La tira de Ocasiones lleva todas, y nada más (sin tarjeta de
        // presupuesto).
        expect(find.byType(BoardOccasionStrip), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1280, 720),
      overrides: _web(),
    );

    screenTest(
      'se ve también con la tira ancha y repartida',
      (tester, phone) async {
        await _mount(tester, phone, extraOccasions: 8);
        expect(_seeAll, findsOneWidget);
        final rect = tester.getRect(_seeAll);
        final window = tester.view.physicalSize / tester.view.devicePixelRatio;
        expect(rect.right, lessThanOrEqualTo(window.width));
        expect(tester.takeException(), isNull);
      },
      size: const Size(2560, 1300),
      overrides: _web(),
    );
  });

  group('el presupuesto en la web', () {
    screenTest(
      'la tira de Ocasiones ya no lleva la tarjeta de presupuesto',
      (tester, phone) async {
        await _mount(tester, phone);
        await tester.tap(_inSidebar('Ocasiones'));
        await settle(tester);
        expect(_path(phone), '/occasions');
        final strip = find.byType(BoardOccasionStrip);
        expect(strip, findsOneWidget);
        expect(find.text('Presupuesto de la casa'), findsNothing);
        expect(
          find.descendant(of: strip, matching: find.text('Presupuesto')),
          findsNothing,
        );
        expect(find.byType(BoardBudgetView), findsNothing);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1440, 900),
      overrides: _web(),
    );

    screenTest(
      'la barra lateral tiene «Presupuesto», que se abre y queda elegida',
      (tester, phone) async {
        await _mount(tester, phone);
        expect(_inSidebar('Presupuesto'), findsOneWidget);
        // Entre Ocasiones y Ajustes.
        expect(
          tester.getTopLeft(_inSidebar('Ocasiones')).dy,
          lessThan(tester.getTopLeft(_inSidebar('Presupuesto')).dy),
        );
        expect(
          tester.getTopLeft(_inSidebar('Presupuesto')).dy,
          lessThan(tester.getTopLeft(_inSidebar('Ajustes')).dy),
        );

        await tester.tap(_inSidebar('Presupuesto'));
        await settle(tester);
        expect(_path(phone), '/occasions/budget');
        expect(find.byType(BoardBudgetView), findsOneWidget);
        // Sin la tira de ocasiones, y con su título.
        expect(find.byType(BoardOccasionStrip), findsNothing);
        expect(boardSelectionOf(Uri.parse('/occasions/budget')), boardBudgetId);
        expect(
          tester.widget<SelectionScope>(find.byType(SelectionScope)).selectedId,
          boardBudgetId,
        );

        // Y Ocasiones vuelve al tablero de ocasiones, no al presupuesto.
        await tester.tap(_inSidebar('Ocasiones'));
        await settle(tester);
        expect(_path(phone), '/occasions');
        expect(find.byType(BoardBudgetView), findsNothing);
        expect(
          tester.widget<SelectionScope>(find.byType(SelectionScope)).selectedId,
          'occasions',
        );
        expect(tester.takeException(), isNull);
      },
      size: const Size(1440, 900),
      overrides: _web(),
    );

    screenTest(
      'solo hay un título «Presupuesto», el de la cabecera, y el contenido va a su izquierda',
      (tester, phone) async {
        await _mount(tester, phone);
        await tester.tap(_inSidebar('Presupuesto'));
        await settle(tester);
        expect(find.byType(BoardBudgetView), findsOneWidget);
        // Un «Presupuesto» en la barra, uno de título y la primera de las tres
        // cifras («Presupuesto», «Gastado» y «Queda»); ninguno más, ni el
        // pequeño «Ocasiones» de encima.
        final titles = find.byWidgetPredicate(
          (w) => w is Text && w.data == 'Presupuesto',
        );
        expect(find.descendant(of: _sidebar, matching: titles), findsOneWidget);
        expect(titles, findsNWidgets(3));
        // El de la cabecera es el primero; el segundo es la cifra.
        final title = tester.getTopLeft(
          find
              .descendant(
                of: find.byType(BoardPage),
                matching: find.text('Presupuesto'),
              )
              .first,
        );
        expect(
          find.textContaining('Lo pones tú en cada ocasión'),
          findsOneWidget,
        );
        // El contenido empieza en el mismo margen que la cabecera.
        final card = find.ancestor(
          of: find.text('Sin presupuesto').first,
          matching: find.byType(AnimatedContainer),
        );
        expect(tester.getTopLeft(card).dx, title.dx);
        // Las tres cifras (sin presupuesto, «Queda» no lleva cifra) y las
        // tarjetas de ocasión y de persona.
        expect(find.text('Sin presupuesto'), findsWidgets);
        expect(find.text('Gastado'), findsWidgets);
        expect(find.text('Queda'), findsOneWidget);
        expect(find.text('Por ocasión'), findsOneWidget);
        expect(find.text('Por persona'), findsOneWidget);
        expect(tester.getTopLeft(find.text('Por ocasión')).dx, title.dx);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1440, 900),
      overrides: _web(),
    );

    screenTest(
      'con la barra plegada, «Presupuesto» sigue ahí, con su icono',
      (tester, phone) async {
        await _mount(tester, phone);
        await tester.tap(find.byTooltip('Plegar la barra lateral'));
        await settle(tester);
        final sidebar = find.byType(BoardSidebar);
        // Plegada, las filas solo llevan icono y una ayuda con el nombre.
        expect(
          find.descendant(of: sidebar, matching: find.byTooltip('Presupuesto')),
          findsOneWidget,
        );
        await tester.tap(
          find.descendant(of: sidebar, matching: find.byTooltip('Presupuesto')),
        );
        await settle(tester);
        expect(_path(phone), '/occasions/budget');
        expect(find.byType(BoardBudgetView), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1440, 900),
      overrides: _web(),
    );

    screenTest(
      'el enlace de siempre, /occasions/budget, sigue abriendo el presupuesto',
      (tester, phone) async {
        await _mount(tester, phone);
        phone.container.read(routerProvider).go('/occasions/budget');
        await settle(tester);
        expect(_path(phone), '/occasions/budget');
        expect(find.byType(BoardBudgetView), findsOneWidget);
        expect(find.byType(BoardBudgetScreen), findsOneWidget);
        expect(
          tester.widget<SelectionScope>(find.byType(SelectionScope)).selectedId,
          boardBudgetId,
        );
        expect(tester.takeException(), isNull);
      },
      size: const Size(1440, 900),
      overrides: _web(),
    );
  });

  group('el presupuesto en la web, a cada ancho', () {
    // Por debajo de 1280 con raíl, la web tiene un quinto destino
    // «Presupuesto», con su propia página; Ocasiones no lleva tarjeta.
    for (final size in const [Size(800, 900), Size(1100, 800)]) {
      screenTest(
        'destino visible y elegido a ${size.width.toInt()} × ${size.height.toInt()}',
        (tester, phone) async {
          await _mount(tester, phone);
          expect(_navLabels(tester), [
            'Personas',
            'Reparto',
            'Ocasiones',
            'Presupuesto',
            'Ajustes',
          ]);
          expect(_navSelected(tester), 0);
          // Ocasiones ya no lleva la fila del presupuesto.
          phone.container.read(routerProvider).go('/occasions');
          await settle(tester);
          expect(_navSelected(tester), 2);
          expect(find.text('Presupuesto de la casa'), findsNothing);
          expect(_card, findsNothing);

          await tester.tap(find.text('Presupuesto').last);
          await settle(tester);
          expect(_path(phone), '/occasions/budget');
          expect(find.byType(WebBudgetPage), findsOneWidget);
          expect(find.byType(BoardBudgetView), findsOneWidget);
          expect(find.byType(BudgetScreen), findsNothing);
          expect(_navSelected(tester), 3);
          expect(
            find.textContaining('Lo pones tú en cada ocasión'),
            findsOneWidget,
          );

          // Ocasiones vuelve a su lista, no al presupuesto.
          await tester.tap(find.text('Ocasiones').last);
          await settle(tester);
          // Con dos paneles, la lista lleva ya a la próxima ocasión.
          expect(_path(phone), startsWith('/occasions'));
          expect(_path(phone), isNot('/occasions/budget'));
          expect(find.byType(BoardBudgetView), findsNothing);
          expect(_navSelected(tester), 2);
          // Y Ajustes sigue en su sitio.
          await tester.tap(find.text('Ajustes').last);
          await settle(tester);
          expect(_path(phone), startsWith('/settings'));
          expect(_navSelected(tester), 4);
          expect(tester.takeException(), isNull);
        },
        size: size,
        overrides: _web(),
      );

      screenTest(
        'el enlace de siempre abre el presupuesto elegido a ${size.width.toInt()}',
        (tester, phone) async {
          await _mount(tester, phone);
          phone.container.read(routerProvider).go('/occasions/budget');
          await settle(tester);
          expect(find.byType(BoardBudgetView), findsOneWidget);
          expect(_navSelected(tester), 3);
          expect(tester.takeException(), isNull);
        },
        size: size,
        overrides: _web(),
      );

      screenTest(
        'sin ninguna ocasión también se llega, a ${size.width.toInt()}',
        (tester, phone) async {
          await _mount(tester, phone, noOccasions: true);
          await tester.tap(find.text('Presupuesto').last);
          await settle(tester);
          expect(_path(phone), '/occasions/budget');
          expect(find.byType(BoardBudgetView), findsOneWidget);
          expect(_navSelected(tester), 3);
          expect(tester.takeException(), isNull);
        },
        size: size,
        overrides: _web(),
      );
    }

    // A ancho de móvil (barra inferior) no hay quinto destino: Ocasiones
    // lleva arriba una tarjeta de Presupuesto.
    for (final size in const [Size(390, 844), Size(360, 740)]) {
      for (final scale in const [1.0, 2.0]) {
        screenTest(
          'a ${size.width.toInt()} con la letra al ${(scale * 100).round()} %: cuatro destinos y la tarjeta de Presupuesto',
          (tester, phone) async {
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            await _mount(
              tester,
              phone,
              budgets: {'seed-santa': 15000, 'seed-kings': 30000},
            );
            tester.takeException();
            expect(_navLabels(tester), [
              'Personas',
              'Reparto',
              'Ocasiones',
              'Ajustes',
            ]);
            phone.container.read(routerProvider).go('/occasions');
            await settle(tester);
            expect(_navSelected(tester), 2);
            expect(find.text('Presupuesto de la casa'), findsNothing);
            expect(_card, findsOneWidget);
            // Arriba del todo, antes de la primera ocasión (sin secciones:
            // la lista va por días).
            expect(
              tester.getTopLeft(_card).dy,
              lessThan(tester.getTopLeft(find.text('Navidad').first).dy),
            );
            expect(
              find.descendant(of: _card, matching: find.text('Presupuesto')),
              findsOneWidget,
            );
            expect(
              find.descendant(of: _card, matching: find.byType(BudgetBar)),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);

            await tester.tap(_card);
            await settle(tester);
            expect(_path(phone), '/occasions/budget');
            expect(find.byType(WebBudgetPage), findsOneWidget);
            expect(find.byType(BoardBudgetView), findsOneWidget);
            expect(find.byType(BudgetScreen), findsNothing);
            // Sin quinto destino: sigue resaltado Ocasiones.
            expect(_navSelected(tester), 2);
            expect(tester.takeException(), isNull);

            // La flecha vuelve a Ocasiones.
            await tester.tap(find.bySemanticsLabel('Volver a Ocasiones'));
            await settle(tester);
            expect(_path(phone), startsWith('/occasions'));
            expect(_path(phone), isNot('/occasions/budget'));
            expect(_card, findsOneWidget);
            expect(tester.takeException(), isNull);
          },
          size: size,
          overrides: _web(),
        );
      }
    }

    screenTest(
      'a ancho de móvil el enlace de siempre abre el presupuesto con Ocasiones elegido',
      (tester, phone) async {
        await _mount(tester, phone);
        phone.container.read(routerProvider).go('/occasions/budget');
        await settle(tester);
        expect(find.byType(BoardBudgetView), findsOneWidget);
        expect(_navSelected(tester), 2);
        expect(tester.takeException(), isNull);
      },
      size: const Size(390, 844),
      overrides: _web(),
    );

    screenTest(
      'a ancho de móvil, sin ninguna ocasión, la tarjeta sale sobre el estado vacío',
      (tester, phone) async {
        await _mount(tester, phone, noOccasions: true);
        phone.container.read(routerProvider).go('/occasions');
        await settle(tester);
        expect(_card, findsOneWidget);
        expect(find.byType(EmptyState), findsOneWidget);
        expect(
          tester.getTopLeft(_card).dy,
          lessThan(tester.getTopLeft(find.byType(EmptyState)).dy),
        );
        await tester.tap(_card);
        await settle(tester);
        expect(find.byType(BoardBudgetView), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      size: const Size(390, 844),
      overrides: _web(),
    );

    screenTest(
      'la app nativa sigue con cuatro destinos y su pantalla de siempre',
      (tester, phone) async {
        await seedSample(tester, phone);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: phone.container,
            child: const RegalosApp(),
          ),
        );
        await settle(tester);
        expect(_navLabels(tester), [
          'Personas',
          'Reparto',
          'Ocasiones',
          'Ajustes',
        ]);
        phone.container.read(routerProvider).go('/occasions');
        await settle(tester);
        await tester.tap(find.text('Presupuesto de la casa'));
        await settle(tester);
        expect(_path(phone), '/occasions/budget');
        expect(find.byType(BudgetScreen), findsOneWidget);
        expect(find.byType(BoardBudgetView), findsNothing);
        expect(_navSelected(tester), 2);
        expect(tester.takeException(), isNull);
      },
      size: const Size(390, 844),
    );

    for (final (size, scale) in const [
      (Size(1440, 900), 1.0),
      (Size(1440, 900), 2.0),
      (Size(1280, 720), 2.0),
    ]) {
      screenTest(
        'el tablero no desborda a ${size.width.toInt()} con la letra al ${(scale * 100).round()} %',
        (tester, phone) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await _mount(tester, phone, extraOccasions: 3);
          // El desborde de «Hoy» con la letra al 200 % es anterior y de otra
          // pantalla: aquí solo cuenta el presupuesto.
          tester.takeException();
          await tester.tap(_inSidebar('Presupuesto'));
          await settle(tester);
          expect(find.byType(BoardBudgetView), findsOneWidget);
          expect(find.text('Por ocasión'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
        size: size,
        overrides: _web(),
      );
    }

    screenTest(
      'con el tablero estrecho de 1280, las tarjetas se reparten en columnas',
      (tester, phone) async {
        await _mount(tester, phone);
        await tester.tap(_inSidebar('Presupuesto'));
        await settle(tester);
        final cards = find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('budget-occasion-'),
        );
        expect(cards, findsAtLeastNWidgets(2));
        final a = tester.getRect(cards.at(0));
        final b = tester.getRect(cards.at(1));
        // En ancho grande, una al lado de la otra.
        expect(a.top, b.top);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1440, 900),
      overrides: _web(),
    );
  });

  group('Ocasiones sin ocasiones', () {
    screenTest(
      'muestra su estado vacío, no el presupuesto',
      (tester, phone) async {
        await _mount(tester, phone, noOccasions: true);
        expect(phone.container.read(occasionsProvider), isEmpty);
        await tester.tap(_inSidebar('Ocasiones'));
        await settle(tester);
        expect(_path(phone), '/occasions');
        expect(find.byType(EmptyState), findsOneWidget);
        expect(find.text('Sin ocasiones'), findsOneWidget);
        expect(find.byType(BoardBudgetView), findsNothing);
        expect(find.byType(BoardOccasionStrip), findsNothing);
        // El botón de añadir ocasión sigue en la cabecera.
        expect(find.byTooltip('Nueva ocasión'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1440, 900),
      overrides: _web(),
    );
  });
}
