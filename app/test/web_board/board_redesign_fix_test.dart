// Arreglos tras el rediseño «A + Actual»: la tira de ocasiones de «Hoy» y «Ocasiones» no corta
// texto, el título del carril tampoco, el «+» está en los cinco carriles y
// abre el editor con el estado del carril, y las zonas de toque llegan a 44.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/app.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/sync/model.dart' show GiftStatus;
import 'package:regalos/core/widgets/status_checkbox.dart';
import 'package:regalos/core/widgets/choice_grid.dart';
import 'package:regalos/core/widgets/gift_status_l10n.dart';
import 'package:regalos/core/widgets/gift_status_map.dart';
import 'package:regalos/l10n/app_localizations.dart';
import 'package:regalos/features/web_board/application/board_lanes.dart';
import 'package:regalos/features/web_board/application/gift_editor_panel.dart';
import 'package:regalos/features/web_board/presentation/board_lanes_view.dart';
import 'package:regalos/features/web_board/presentation/board_occasion_strip.dart';
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

/// Los textos de [root] que se ven cortados (con «…» o recortados).
List<String> _cutTexts(WidgetTester tester, Finder root) {
  final cut = <String>[];
  for (final element
      in find
          .descendant(of: root, matching: find.byType(RichText))
          .evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    final wanted = paragraph.getMaxIntrinsicWidth(double.infinity);
    if (wanted > paragraph.size.width + 0.5) {
      cut.add(paragraph.text.toPlainText());
    }
  }
  return cut;
}

void main() {
  setUpAll(loadInter);

  group('tira de ocasiones de «Hoy» y «Ocasiones»', () {
    for (final width in [1440.0, 1920.0, 3440.0]) {
      screenTest(
        'a ${width.toInt()} ningún nombre ni dato sale cortado',
        (tester, phone) async {
          await _mountWeb(tester, phone);
          final strip = find.byType(BoardOccasionStrip);
          expect(strip, findsOneWidget);
          expect(find.byType(BoardOccasionCard), findsWidgets);
          expect(_cutTexts(tester, strip), isEmpty);
          // Las tarjetas miden 72 a 1×.
          for (final card in find.byType(BoardOccasionCard).evaluate()) {
            final h = tester.getSize(find.byElementPredicate((e) => e == card));
            expect(h.height, closeTo(BoardOccasionStrip.cardHeight, 0.5));
          }
          expect(tester.takeException(), isNull);
        },
        size: Size(width, 920),
        overrides: _web(),
      );
    }

    screenTest(
      '«Hoy» y «Ocasiones» usan la misma tarjeta, del mismo alto',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        Size first() => tester.getSize(find.byType(BoardOccasionCard).first);
        final today = first();
        expect(today.height, closeTo(72, 0.5));
        phone.container.read(routerProvider).go('/occasions');
        await settle(tester);
        expect(find.byType(BoardOccasionCard), findsWidgets);
        final occasions = first();
        expect(occasions.height, closeTo(today.height, 0.5));
        for (
          var i = 0;
          i < find.byType(BoardOccasionCard).evaluate().length;
          i++
        ) {
          expect(
            _cutTexts(tester, find.byType(BoardOccasionCard).at(i)),
            isEmpty,
          );
        }
        expect(tester.takeException(), isNull);
      },
      size: const Size(1920, 920),
      overrides: _web(),
    );

    screenTest(
      'la etiqueta para el lector de pantalla dice días, fecha y comprados',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        final card = find.byType(BoardOccasionCard).first;
        final label = tester.getSemantics(card).label;
        expect(label, contains('días'));
        expect(label, matches(RegExp(r'\d+ de \d+ comprados|Sin regalos')));
      },
      size: const Size(1440, 920),
      overrides: _web(),
    );

    screenTest(
      'a letra 2× la tarjeta crece con el texto y no se recorta',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        final card = find.byType(BoardOccasionCard).first;
        final h = tester.getSize(card).height;
        final expected = BoardOccasionStrip.cardHeightFor(
          const TextScaler.linear(2),
        );
        expect(h, closeTo(expected, 0.5));
        expect(h, greaterThan(BoardOccasionStrip.cardHeight));
        expect(
          _cutTexts(tester, find.byType(BoardOccasionStrip)),
          isEmpty,
          reason: 'ningún texto cortado a 2×',
        );
        // La barra lateral a 2× desborda por su cuenta (ajeno a la tira): se
        // recoge para que no cuente en esta prueba.
        tester.takeException();
      },
      size: const Size(1440, 920),
      textScale: 2,
      overrides: _web(),
    );
  });

  group('carriles', () {
    screenTest(
      'a 1440 el título «Por decidir» no se corta',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        final lane = _lane(BoardLane.decide);
        final title = find.descendant(
          of: lane,
          matching: find.text('Por decidir'),
        );
        expect(title, findsOneWidget);
        expect(_cutTexts(tester, title), isEmpty);
      },
      size: const Size(1440, 920),
      overrides: _web(),
    );

    screenTest(
      'a 1920 el «+» está en los cinco carriles y abre el editor con su estado',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        final adds = find.byKey(const ValueKey<String>('board-lane-add'));
        expect(adds, findsNWidgets(5));
        for (final lane in BoardLane.values) {
          await tester.tap(find.descendant(of: _lane(lane), matching: adds));
          await settle(tester);
          final panel = phone.container.read(giftEditorPanelProvider);
          expect(panel.request, isNotNull, reason: lane.name);
          expect(panel.request!.gift, isNull);
          expect(panel.request!.status, lane.status, reason: lane.name);
          // El editor lo muestra: el estado del carril viene elegido.
          expect(
            find.byWidgetPredicate(
              (w) =>
                  w is ChoiceGrid &&
                  w.items.any(
                    (i) =>
                        i.selected &&
                        i.label ==
                            lane.status.visualStatus.label(
                              AppLocalizations.of(
                                tester.element(find.byType(ChoiceGrid).first),
                              ),
                            ),
                  ),
            ),
            findsOneWidget,
            reason: lane.name,
          );
          panel.close();
          await settle(tester);
        }
        expect(tester.takeException(), isNull);
      },
      size: const Size(1920, 960),
      overrides: _web(),
    );

    screenTest(
      'con el dedo el «+» y la casilla de estado miden 44 por 44',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        final add = find.descendant(
          of: _lane(BoardLane.decide),
          matching: find.byKey(const ValueKey<String>('board-lane-add')),
        );
        final size = tester.getSize(add);
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
        final box = find
            .descendant(
              of: _lane(BoardLane.decide),
              matching: find.byType(StatusCheckbox),
            )
            .first;
        final rect = tester.getRect(box);
        expect(rect.width, 44);
        expect(rect.height, 44);
        // La casilla queda entera dentro de su tarjeta y a la izquierda del
        // texto que abre el editor: no se pisan.
        final card = tester.getRect(
          find
              .descendant(
                of: _lane(BoardLane.decide),
                matching: find.byType(BoardGiftRow),
              )
              .first,
        );
        expect(rect.left, greaterThanOrEqualTo(card.left));
        expect(rect.right, lessThan(card.right));
      },
      size: const Size(1920, 960),
      overrides: _web(),
    );

    test('el estado inicial del editor llega a la petición del panel', () {
      final panel = GiftEditorPanelController()..attach();
      panel.open(status: GiftStatus.wrapped);
      expect(panel.request!.status, GiftStatus.wrapped);
      panel.open();
      expect(panel.request!.status, isNull);
    });
  });
}
