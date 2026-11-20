import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/format/money.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/widgets/budget_meter.dart';
import 'package:regalos/features/gifts/presentation/person_list_screen.dart';
import 'package:regalos/features/people/presentation/countdown_carousel.dart';

import '../helpers/memory_stores.dart' show FakePhone;
import '../helpers/screens.dart';

// «La casa · X» (ficha de la persona) y el total del «Resumen»: sin previsto,
// «Gastado X» y sin barra; nunca «X de 0 €».

Future<void> _seedLoose(
  WidgetTester tester,
  FakePhone phone, {
  required bool withGift,
}) async {
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
    await c.upsertRecipient(
      const Recipient(id: 'nora', name: 'Nora', colorIndex: 4, archived: false),
    );
    if (withGift) {
      // Comprado a 45 € reales, sin precio previsto.
      await c.upsertGift(
        const Gift(
          id: 'sin-previsto',
          recipientId: 'nora',
          title: 'Real',
          giverId: 'us',
          status: GiftStatus.bought,
          rawStatus: 'bought',
          actualCents: 4500,
          surprise: false,
          year: 2026,
        ),
      );
    }
  });
}

void main() {
  const wide = Size(1700, 1000);

  for (final withGift in [true, false]) {
    screenTest(
      withGift
          ? 'con lo gastado y sin previsto, «La casa · Nora» y el total del '
                'Resumen dicen «Gastado 45 €», sin barra ni «de 0 €»'
          : 'sin importes, el total del Resumen dice «Gastado 0 €», sin '
                'barra ni «0 € de 0 €»',
      (tester, phone) async {
        await _seedLoose(tester, phone, withGift: withGift);
        await pumpRegalos(tester, phone);
        final money = formatCents(withGift ? 4500 : 0, 'es');

        final detail = find.byType(PersonListScreen);
        final summary = find.byType(SummaryColumn);
        expect(summary, findsOneWidget);
        // En escritorio, sin regalos la ficha no lleva el bloque de la casa: solo
        // queda el total del Resumen.
        for (final scope in [if (withGift) detail, summary]) {
          final meters = find.descendant(
            of: scope,
            matching: find.byType(BudgetMeter),
          );
          expect(meters, findsWidgets, reason: 'hay medidor en $scope');
          expect(
            find.descendant(of: scope, matching: find.byType(BudgetBar)),
            findsNothing,
          );
          expect(
            find.descendant(of: scope, matching: find.text('Gastado')),
            findsWidgets,
          );
          expect(
            find.descendant(
              of: scope,
              matching: find.textContaining(RegExp(r'^de ')),
            ),
            findsNothing,
          );
          // El importe, dentro del propio medidor (el del Resumen incluido).
          expect(
            find.descendant(of: meters.first, matching: find.text(money)),
            findsOneWidget,
          );
        }
        if (withGift) {
          expect(
            find.descendant(
              of: detail,
              matching: find.textContaining('La casa · Nora'),
            ),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      },
      size: wide,
    );
  }
}
