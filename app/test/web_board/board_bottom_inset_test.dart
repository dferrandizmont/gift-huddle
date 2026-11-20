// El margen seguro de abajo en los carriles del tablero (fallo de una revisión):
// desde 1280 de ancho, `BoardPage` usaba `SafeArea(bottom: false)`
// y un margen fijo de 16, así que con una barra del sistema abajo el final de
// un carril quedaba debajo de ella.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/app.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/sync/model.dart' show Gift, GiftStatus;
import 'package:regalos/features/web_board/application/board_lanes.dart';
import 'package:regalos/features/web_board/presentation/board_lanes_view.dart';
import 'package:regalos/features/web_device/application/web_app_provider.dart';
import 'package:regalos/features/web_device/application/web_device_providers.dart';
import 'package:regalos/features/web_device/application/web_sync_engine.dart'
    show WebSyncStatus;

import '../helpers/fonts.dart';
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

Finder _lane(BoardLane lane) =>
    find.byKey(ValueKey<String>('board-lane-${lane.name}'));

void main() {
  setUpAll(loadInter);

  for (final path in ['/people', '/occasions/seed-kings']) {
    screenTest(
      'con 48 de margen seguro abajo, el carril llega al final por encima de '
      'la barra del sistema ($path)',
      (tester, phone) async {
        // Primero sin margen seguro: el borde de abajo de referencia.
        tester.view.padding = FakeViewPadding.zero;
        await seedSample(tester, phone);
        // Muchos regalos «por decidir»: el carril se desplaza por dentro.
        for (var i = 0; i < 24; i++) {
          await tester.runAsync(
            () => familyOf(phone).upsertGift(
              Gift(
                id: 'inset-$i',
                recipientId: 'aritz',
                occasionId: 'seed-kings',
                title: 'Regalo de prueba $i',
                status: GiftStatus.idea,
                rawStatus: 'idea',
                surprise: false,
                year: 2026,
              ),
            ),
          );
        }
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: phone.container,
            child: const RegalosApp(webSession: true),
          ),
        );
        await settle(tester);
        phone.container.read(routerProvider).go(path);
        await settle(tester);

        final lane = _lane(BoardLane.decide);
        expect(lane, findsOneWidget);
        final bottomWithout = tester.getRect(lane).bottom;
        // Con 48 de margen seguro el borde de abajo sube exactamente 48 (no
        // basta con que quepa: un margen que no se aplica o se aplica doble
        // lo delata).
        tester.view.padding = const FakeViewPadding(bottom: 48);
        await tester.pump();
        await settle(tester);
        expect(
          bottomWithout - tester.getRect(lane).bottom,
          closeTo(48, 1),
          reason: 'el carril sube lo que mide el margen seguro',
        );
        // El carril (y con él su lista) acaba por encima del margen seguro.
        final screen = tester.view.physicalSize.height;
        expect(tester.getRect(lane).bottom, lessThanOrEqualTo(screen - 48));

        // Hasta el final: la última tarjeta queda entera a la vista.
        final list = find.descendant(
          of: lane,
          matching: find.byType(Scrollable),
        );
        await tester.drag(list.first, const Offset(0, -4000));
        await settle(tester);
        final last = find
            .descendant(of: lane, matching: find.byType(BoardGiftRow))
            .last;
        expect(tester.getRect(last).bottom, lessThanOrEqualTo(screen - 48));
        expect(tester.takeException(), isNull);
      },
      size: const Size(1440, 760),
      overrides: _web(),
    );
  }
}
