import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/format/money.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/widgets/budget_meter.dart';
import 'package:regalos/features/gifts/presentation/person_list_screen.dart';

import '../helpers/memory_stores.dart' show FakePhone;
import '../helpers/screens.dart';

// Las dos tiras de la ficha de una persona cuentan lo comprado sobre el total
// de sus regalos (precio real o, si falta, el previsto), sin rojo.

Gift _gift(
  String id,
  String giver, {
  required GiftStatus status,
  int? planned,
  int? actual,
}) => Gift(
  id: id,
  recipientId: 'aritz',
  title: id,
  giverId: giver,
  status: status,
  rawStatus: status.name,
  plannedCents: planned,
  actualCents: actual,
  surprise: false,
  year: 2026,
);

Future<void> _seed(WidgetTester tester, FakePhone phone) async {
  await bareFamily(tester, phone);
  await tester.runAsync(() async {
    final c = familyOf(phone);
    await c.upsertGiver(
      const Giver(
        id: 'us',
        name: 'Nosotros',
        colorIndex: 0,
        householdPays: true,
        archived: false,
      ),
    );
    await c.upsertGiver(
      const Giver(
        id: 'leo',
        name: 'Leo',
        colorIndex: 1,
        householdPays: false,
        archived: false,
      ),
    );
    await c.upsertRecipient(
      const Recipient(
        id: 'aritz',
        name: 'Aritz',
        colorIndex: 2,
        archived: false,
      ),
    );
    // Quien regala y no cuenta como gasto de casa: solo real, solo previsto
    // y uno sin comprar.
    await c.upsertGift(
      _gift('real', 'leo', status: GiftStatus.bought, actual: 3000),
    );
    await c.upsertGift(
      _gift('previsto', 'leo', status: GiftStatus.arrived, planned: 2000),
    );
    await c.upsertGift(
      _gift('sin-comprar', 'leo', status: GiftStatus.decided, planned: 1000),
    );
    // Gasto de casa: con los dos precios (cuenta el real) y uno sin comprar.
    await c.upsertGift(
      _gift(
        'ambos',
        'us',
        status: GiftStatus.bought,
        planned: 5000,
        actual: 4000,
      ),
    );
    await c.upsertGift(
      _gift('casa-sin-comprar', 'us', status: GiftStatus.idea, planned: 3000),
    );
  });
}

void main() {
  screenTest(
    'la tira de la persona cuenta todos sus regalos y la de la casa solo lo '
    'que cuenta como gasto de casa: «Comprado X de Y», sin rojo',
    (tester, phone) async {
      await _seed(tester, phone);
      await pumpRegalos(tester, phone);
      String money(int cents) => formatCents(cents, 'es');

      final detail = find.byType(PersonListScreen);
      expect(detail, findsOneWidget);

      void expectStrip(Finder meter, {required int bought, required int of}) {
        expect(meter, findsOneWidget);
        expect(
          find.descendant(of: meter, matching: find.text('Comprado')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: meter, matching: find.text(money(bought))),
          findsOneWidget,
        );
        expect(
          find.descendant(of: meter, matching: find.text('de ${money(of)}')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: meter, matching: find.text('Gastado')),
          findsNothing,
        );
        final bar = tester.widget<BudgetBar>(
          find.descendant(of: meter, matching: find.byType(BudgetBar)),
        );
        // Nunca pasa de 1: sin presupuesto no hay rojo.
        expect(bar.fraction, closeTo(bought / of, 1e-9));
        expect(bar.fraction, lessThanOrEqualTo(1));
      }

      // Aritz: 30 + 20 + 40 comprados de 30 + 20 + 10 + 40 + 30 en total,
      // pague quien pague.
      expectStrip(
        find.descendant(
          of: detail,
          matching: find.widgetWithText(BudgetMeter, 'Aritz'),
        ),
        bought: 9000,
        of: 13000,
      );
      // La casa: solo lo de «Nosotros».
      expectStrip(
        find.descendant(
          of: detail,
          matching: find.widgetWithText(BudgetMeter, 'Gasto de casa · total'),
        ),
        bought: 4000,
        of: 7000,
      );
      expect(find.textContaining('La casa ·'), findsNothing);
      expect(tester.takeException(), isNull);
    },
    size: const Size(1700, 1000),
  );
}
