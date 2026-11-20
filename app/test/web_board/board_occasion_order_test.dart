// El orden de las ocasiones es el mismo en «Hoy» y en «Ocasiones» (por los
// días que faltan) y la tira que se desplaza se desvanece con una máscara, no
// con una franja de color encima.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/app.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/web_board/application/board_occasion_order.dart';
import 'package:regalos/features/web_board/presentation/board_occasion_strip.dart';
import 'package:regalos/features/web_board/presentation/board_sidebar.dart';
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

Occasion _occasion(
  String id,
  String name,
  int month,
  int day, {
  bool recurring = true,
  int? year,
  OccasionKind kind = OccasionKind.custom,
}) => Occasion(
  id: id,
  kind: kind,
  rawKind: kind.name,
  name: name,
  month: month,
  day: day,
  year: year,
  recurring: recurring,
  archived: false,
);

/// Los ids de las tarjetas de ocasión de la tira, de izquierda a derecha.
List<String> _stripIds(WidgetTester tester) {
  final cards = find.byType(BoardOccasionCard).evaluate().toList();
  final entries = [
    for (final e in cards)
      (
        x: tester.getTopLeft(find.byElementPredicate((x) => x == e)).dx,
        id: (e.widget as BoardOccasionCard).occasion.id,
      ),
  ]..sort((a, b) => a.x.compareTo(b.x));
  return [for (final e in entries) e.id];
}

void main() {
  setUpAll(loadInter);

  group('boardOccasionOrder', () {
    final now = DateTime(2026, 11, 9, 10);
    final nora = _occasion('nora-b', 'Cumpleaños de Nora', 12, 11);
    final christmas = _occasion('xmas', 'Navidad', 12, 15);
    final past = _occasion(
      'past',
      'Ya pasó',
      1,
      5,
      recurring: false,
      year: 2026,
    );
    final aritz = _occasion('aritz-b', 'Cumpleaños de Aritz', 3, 14);

    test('por días, no por tipo, y las pasadas solo si se piden', () {
      final all = [aritz, past, christmas, nora];
      expect(boardOccasionOrder(all, now).map((o) => o.id), [
        'nora-b',
        'xmas',
        'aritz-b',
      ]);
      expect(
        boardOccasionOrder(all, now, includePassed: true).map((o) => o.id),
        ['nora-b', 'xmas', 'aritz-b', 'past'],
      );
    });

    test('a igual fecha, un orden estable', () {
      final a = _occasion('b', 'Igual', 12, 1);
      final b = _occasion('a', 'Igual', 12, 1);
      expect(boardOccasionOrder([a, b], now).map((o) => o.id), ['a', 'b']);
      expect(boardOccasionOrder([b, a], now).map((o) => o.id), ['a', 'b']);
    });
  });

  group('la tira en la web', () {
    screenTest(
      'Hoy y Ocasiones dan el mismo orden, por días',
      (tester, phone) async {
        await seedSample(tester, phone);
        // Una ocasión no fija a 36 días (15 dic), antes que Tió y Navidad, y
        // una que ya pasó.
        await tester.runAsync(() async {
          final c = familyOf(phone);
          await c.upsertOccasion(
            _occasion('custom-near', 'Aniversario', 12, 15),
          );
          await c.upsertOccasion(
            _occasion(
              'custom-past',
              'Pasada',
              1,
              5,
              recurring: false,
              year: 2026,
            ),
          );
        });
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: phone.container,
            child: const RegalosApp(webSession: true),
          ),
        );
        await settle(tester);
        expect(find.byType(BoardOccasionStrip), findsOneWidget);
        final today = _stripIds(tester);
        expect(today.first, 'custom-near');

        await tester.tap(
          find.descendant(
            of: find.byType(BoardSidebar),
            matching: find.text('Ocasiones'),
          ),
        );
        await settle(tester);
        final occasions = _stripIds(tester);
        // Mismo orden en las que comparten: la de Ocasiones solo añade al
        // final la pasada.
        expect(occasions.last, 'custom-past');
        final shared = occasions.sublist(0, occasions.length - 1);
        expect(shared.take(today.length).toList(), today.take(shared.length));
        expect(occasions.first, 'custom-near');
        // Y es por días: las fijas (Tió, Navidad, Reyes) no van delante de
        // las demás por ser fijas.
        final ids = [for (final id in occasions) id];
        expect(ids.indexOf('custom-near'), lessThan(ids.indexOf('seed-kings')));
        expect(tester.takeException(), isNull);
      },
      size: const Size(1440, 900),
      overrides: _web(),
    );

    screenTest(
      'la tira que se desplaza se desvanece con una máscara, sin franja opaca',
      (tester, phone) async {
        await seedSample(tester, phone);
        // Las de serie caben; con tres más la tira ya se desplaza.
        await tester.runAsync(() async {
          final c = familyOf(phone);
          for (var i = 0; i < 6; i++) {
            await c.upsertOccasion(
              _occasion('extra-$i', 'Extra $i', 12, 10 + i),
            );
          }
        });
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: phone.container,
            child: const RegalosApp(webSession: true),
          ),
        );
        await settle(tester);
        final strip = find.byType(BoardOccasionStrip);
        final mask = find.descendant(
          of: strip,
          matching: find.byType(ShaderMask),
        );
        expect(mask, findsOneWidget);
        // Ninguna caja pintada encima con un degradado de color.
        expect(
          find.descendant(
            of: strip,
            matching: find.byWidgetPredicate(
              (w) =>
                  w is DecoratedBox &&
                  w.decoration is BoxDecoration &&
                  (w.decoration as BoxDecoration).gradient != null,
            ),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
      size: const Size(1280, 720),
      overrides: _web(),
    );
  });
}
