import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/format/money.dart';
import 'package:regalos/core/widgets/budget_meter.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/family_providers.dart';
import 'package:regalos/features/occasions/presentation/budget_screen.dart';
import 'package:regalos/features/occasions/presentation/occasion_detail_screen.dart';
import 'package:regalos/features/settings/application/locale_provider.dart';

import '../helpers/screens.dart';
import '../helpers/tablet.dart';

String _path(dynamic phone) => phone.container
    .read(routerProvider)
    .routeInformationProvider
    .value
    .uri
    .path;

String _money(int cents) => formatCents(cents, 'es');

BudgetTotals _total(dynamic phone) =>
    phone.container.read(budgetProvider).total as BudgetTotals;

BudgetTotals _budgeted(dynamic phone) =>
    (phone.container.read(budgetProvider) as Budget).budgeted;

Future<void> _openBudget(WidgetTester tester, dynamic phone) async {
  phone.container.read(routerProvider).go('/occasions/budget');
  await settle(tester);
  expect(find.byType(BudgetScreen), findsOneWidget);
}

Finder _card(String id) => find.byKey(ValueKey<String>('budget-occasion-$id'));

Finder _field(String key) => find.byKey(ValueKey<String>(key));

/// Sin ninguna ocasión con presupuesto, las tres cifras cuentan todo.
const _subtitle =
    'Puedes poner un presupuesto en cada ocasión. «Gastado» suma los precios '
    'reales de los regalos que paga la casa. Si ya se ha comprado un regalo y '
    'falta el precio real, cuenta el previsto.';

/// Con alguna ocasión con presupuesto, avisa de que solo cuentan esas.
const _subtitleBudgeted =
    'Puedes poner un presupuesto en cada ocasión. Las tres cifras solo incluyen '
    'ocasiones con presupuesto. «Gastado» suma los precios reales de los regalos '
    'que paga la casa. Si ya se ha comprado un regalo y falta el precio real, '
    'cuenta el previsto.';

String _fieldText(WidgetTester tester, Finder field) =>
    tester.widget<TextField>(field).controller!.text;

void main() {
  const tall = Size(390, 2200);

  screenTest(
    'sin presupuesto: «Sin presupuesto», Queda sin cifra y un acceso para '
    'ponerlo; nunca «de 0 €» ni «Te pasas»',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openBudget(tester, phone);

      expect(_total(phone).budgetCents, isNull);
      // Las tres cifras de arriba.
      expect(find.text('Presupuesto'), findsNWidgets(2)); // título y cifra
      expect(find.text('Gastado'), findsWidgets); // cifra y ocasiones
      expect(find.text('Disponible'), findsOneWidget);
      expect(find.text('Sin presupuesto'), findsWidgets);
      expect(find.text('–'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('budget-set-first')),
        findsOneWidget,
      );
      // Ni «Si compras lo que falta», ni «Te pasas», ni «de 0 €».
      expect(find.textContaining('Si compras lo que falta'), findsNothing);
      expect(find.textContaining('Te pasas'), findsNothing);
      expect(find.textContaining(eur('de 0 €')), findsNothing);
      expect(find.text(_subtitle), findsOneWidget);
      expect(find.textContaining('Además, la casa ha gastado'), findsNothing);
      // Cada ocasión con regalos dice lo mismo y lleva su acceso.
      expect(
        find.descendant(
          of: _card('seed-kings'),
          matching: find.text('Sin presupuesto'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _card('seed-kings'),
          matching: find.text('Poner presupuesto'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    size: tall,
  );

  screenTest(
    'el acceso de arriba pone el presupuesto de la ocasión que se elija',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openBudget(tester, phone);

      await tester.tap(find.byKey(const ValueKey<String>('budget-set-first')));
      await settle(tester);
      // Una sola hoja: la ocasión (la más próxima, elegida) y el importe.
      expect(find.text('Ocasión'), findsOneWidget);
      expect(find.text('Tió'), findsWidgets);
      await tester.enterText(_field('budget-sheet-field'), '120,50');
      await tester.tap(find.text('Guardar'));
      await settle(tester);

      expect(_total(phone).budgetCents, 12050);
      expect(find.text('Sin presupuesto'), findsWidgets); // las demás
      expect(
        find.byKey(const ValueKey<String>('budget-set-first')),
        findsNothing,
      );
      expect(find.textContaining('Si compras lo que falta'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    size: tall,
  );

  screenTest(
    'con presupuesto: presupuesto, gastado y queda, y qué pasa si compras lo '
    'que falta',
    (tester, phone) async {
      await seedSample(tester, phone);
      await setBudgets(tester, phone, {
        'seed-santa': 15000,
        'seed-kings': 30000,
      });
      await pumpRegalos(tester, phone);
      await _openBudget(tester, phone);

      expect(find.text(_subtitleBudgeted), findsOneWidget);
      expect(find.text(_subtitle), findsNothing);
      final total = _budgeted(phone);
      expect(total.budgetCents, 45000);
      expect(total.isOver, isFalse);
      expect(find.text(eur('450 €')), findsOneWidget); // presupuesto
      // Solo Navidad y Reyes (145,49 €); los 24 € de Tió, sin presupuesto, van
      // en la línea de aparte y no en las tres cifras.
      expect(total.spentCents, 14549);
      expect(find.text(eur('145,49 €')), findsWidgets); // gastado
      expect(find.text(eur('169,49 €')), findsNothing);
      expect(find.text('Disponible'), findsOneWidget);
      expect(find.text(eur('304,51 €')), findsWidgets);
      expect(
        find.text(
          eur(
            'Además, la casa ha gastado 24 € fuera de las ocasiones con presupuesto.',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Sin presupuesto'), findsWidgets); // Tió, cumpleaños…
      expect(find.textContaining('Te pasas'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('budget-set-first')),
        findsNothing,
      );

      // «Si compras lo que falta, te quedarán X».
      final ifBought = total.leftIfBoughtCents!;
      expect(ifBought, greaterThanOrEqualTo(0));
      expect(
        find.bySemanticsLabel(
          'Si compras lo que falta, te quedarás con ${_money(ifBought)}',
        ),
        findsOneWidget,
      );
      // Cada ocasión con presupuesto: lo gastado de él y lo que queda.
      final kings = _card('seed-kings');
      expect(
        find.descendant(of: kings, matching: find.text(eur('de 300 €'))),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: kings,
          matching: find.text('Disponible ${_money(30000 - 8099)}'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: kings, matching: find.text('Cambiar presupuesto')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    size: tall,
  );

  screenTest(
    'si lo que falta por comprar no cabe, «te pasarás»; «Te pasas» solo '
    'cuando ya se gastó más',
    (tester, phone) async {
      await seedSample(tester, phone);
      // Un regalo de la casa por comprar, previsto en 200 €.
      await tester.runAsync(
        () => familyOf(phone).upsertGift(
          const Gift(
            id: 'pendiente',
            recipientId: 'nora',
            title: 'Bicicleta',
            giverId: 'us',
            occasionId: 'seed-kings',
            status: GiftStatus.decided,
            rawStatus: 'decided',
            plannedCents: 20000,
            surprise: false,
            year: 2026,
          ),
        ),
      );
      await pumpRegalos(tester, phone);
      // Reyes es la única ocasión con presupuesto: solo cuentan sus regalos.
      final before = phone.container
          .read(budgetProvider)
          .ofOccasion('seed-kings');
      expect(before.pendingCents, 20000);
      // Cabe lo gastado pero no lo que falta por comprar: faltan 5 € de más.
      await setBudgets(tester, phone, {
        'seed-kings': before.spentCents + before.pendingCents - 500,
      });
      await _openBudget(tester, phone);

      final total = _budgeted(phone);
      expect(total.isOver, isFalse);
      expect(total.leftIfBoughtCents, -500);
      expect(
        find.bySemanticsLabel(eur('Si compras lo que falta, te pasarás 5 €')),
        findsOneWidget,
      );
      expect(find.textContaining('Te pasas'), findsNothing);
      expect(find.text('Disponible'), findsOneWidget);

      // Un poco más de presupuesto y sobra: «te quedarán».
      await setBudgets(tester, phone, {
        'seed-kings': before.spentCents + before.pendingCents + 700,
      });
      await settle(tester);
      expect(
        find.bySemanticsLabel(eur('Si compras lo que falta, te quedarás con 7 €')),
        findsOneWidget,
      );

      // Y ahora ya se pasó de verdad.
      await setBudgets(tester, phone, {'seed-kings': before.spentCents - 100});
      await settle(tester);
      expect(_budgeted(phone).isOver, isTrue);
      expect(find.text('Te pasas'), findsOneWidget);
      expect(find.text('Disponible'), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp('Si compras lo que falta, te pasarás')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    size: tall,
  );

  screenTest(
    'una ocasión sin regalos pero con presupuesto sale con su presupuesto '
    'entero, y «Te pasas» solo en la que se pasa',
    (tester, phone) async {
      await seedSample(tester, phone);
      await tester.runAsync(
        () => familyOf(phone).upsertOccasion(
          const Occasion(
            id: 'boda',
            kind: OccasionKind.wedding,
            rawKind: 'wedding',
            name: 'Boda de Leo',
            month: 9,
            day: 12,
            recurring: false,
            year: 2027,
            archived: false,
            budgetCents: 30000,
          ),
        ),
      );
      await setBudgets(tester, phone, {'seed-tio': 2000});
      await pumpRegalos(tester, phone);
      await _openBudget(tester, phone);
      final boda = _card('boda');
      expect(boda, findsOneWidget);
      expect(
        find.descendant(
          of: boda,
          matching: find.text('Disponible ${_money(30000)}'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining(eur('de 0 €')), findsNothing);
      // Tió gastó 24 € de 20 €: se pasa por 4 €; la boda, no.
      expect(
        find.descendant(
          of: _card('seed-tio'),
          matching: find.text('Te pasas ${_money(400)}'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: boda, matching: find.textContaining('Te pasas')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
    size: tall,
  );

  screenTest(
    'las ocasiones archivadas y los regalos sin ocasión que tienen importe '
    'salen, al final y marcadas',
    (tester, phone) async {
      await seedSample(tester, phone);
      await tester.runAsync(() async {
        final c = familyOf(phone);
        await c.upsertOccasion(
          const Occasion(
            id: 'vieja',
            kind: OccasionKind.custom,
            rawKind: 'custom',
            name: 'Fiesta de Leo',
            month: 5,
            day: 2,
            recurring: true,
            archived: true,
            budgetCents: 10000,
          ),
        );
        await c.upsertGift(
          const Gift(
            id: 'suelto',
            recipientId: 'leo',
            title: 'Libro',
            giverId: 'us',
            status: GiftStatus.bought,
            rawStatus: 'bought',
            plannedCents: 1500,
            actualCents: 1500,
            surprise: false,
            year: 2026,
          ),
        );
      });
      await pumpRegalos(tester, phone);
      await _openBudget(tester, phone);
      // Archivada: su presupuesto no suma, pero su fila lo enseña entero.
      expect(_total(phone).budgetCents, isNull);
      expect(
        phone.container.read(budgetProvider).ofOccasion('vieja').budgetCents,
        10000,
      );
      final vieja = _card('vieja');
      expect(vieja, findsOneWidget);
      expect(
        find.descendant(of: vieja, matching: find.text('Archivada · no suma')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: vieja,
          matching: find.text('Disponible ${_money(10000)}'),
        ),
        findsOneWidget,
      );
      final none = find.byKey(const ValueKey<String>('budget-occasion-none'));
      expect(none, findsOneWidget);
      expect(
        tester.getTopLeft(none).dy,
        greaterThan(tester.getTopLeft(vieja).dy),
      );
      expect(tester.takeException(), isNull);
    },
    size: tall,
  );

  tabletScreenTest(
    'pulsar una ocasión o una persona abre sus regalos; el botón de la '
    'tarjeta pone, cambia y quita el presupuesto',
    (tester, phone, size) async {
      await seedSample(tester, phone);
      await setBudgets(tester, phone, {'seed-kings': 30000});
      await pumpRegalos(tester, phone);
      await _openBudget(tester, phone);

      // Cambiar: la hoja trae el importe puesto.
      await tester.tap(
        find.bySemanticsLabel('Cambiar el presupuesto de Reyes'),
      );
      await settle(tester);
      expect(find.text('Presupuesto de Reyes'), findsOneWidget);
      expect(_fieldText(tester, _field('budget-sheet-field')), '300');
      await tester.enterText(_field('budget-sheet-field'), '250');
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      expect(_total(phone).budgetCents, 25000);
      expect(
        phone.container
            .read(budgetProvider)
            .ofOccasion('seed-kings')
            .budgetCents,
        25000,
      );

      // Poner: la ocasión sin presupuesto.
      await tester.tap(find.bySemanticsLabel('Poner presupuesto a Navidad'));
      await settle(tester);
      expect(_fieldText(tester, _field('budget-sheet-field')), isEmpty);
      await tester.enterText(_field('budget-sheet-field'), '1,2,3');
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      // Un importe que no vale avisa y no cierra.
      expect(
        find.text('Escribe un importe, por ejemplo 12,50.'),
        findsOneWidget,
      );
      await tester.enterText(_field('budget-sheet-field'), '90');
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      expect(_total(phone).budgetCents, 34000);

      // Quitar: vaciar el campo.
      await tester.tap(
        find.bySemanticsLabel('Cambiar el presupuesto de Reyes'),
      );
      await settle(tester);
      await tester.enterText(_field('budget-sheet-field'), '');
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      expect(
        phone.container
            .read(budgetProvider)
            .ofOccasion('seed-kings')
            .budgetCents,
        isNull,
      );
      expect(_total(phone).budgetCents, 9000);

      // Cancelar no cambia nada.
      await tester.tap(
        find.bySemanticsLabel('Cambiar el presupuesto de Navidad'),
      );
      await settle(tester);
      await tester.enterText(_field('budget-sheet-field'), '5');
      await tester.tap(find.text('Cancelar'));
      await settle(tester);
      expect(_total(phone).budgetCents, 9000);

      // Pulsar la ocasión abre sus regalos.
      await tester.tap(
        find.descendant(of: _card('seed-kings'), matching: find.text('Reyes')),
      );
      await settle(tester);
      expect(_path(phone), '/occasions/seed-kings');
      expect(find.byType(OccasionDetailScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    sizes: const [Size(390, 2200), Size(800, 2400)],
  );

  tabletScreenTest('pulsar una persona abre su ficha', (
    tester,
    phone,
    size,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await _openBudget(tester, phone);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('budget-person-aritz')),
        matching: find.text('Aritz'),
      ),
    );
    await settle(tester);
    expect(_path(phone), '/people/aritz');
    expect(tester.takeException(), isNull);
  }, sizes: const [Size(390, 2200), Size(800, 2400)]);

  for (final scale in const [1.0, 2.0]) {
    for (final budgets in const [
      <String, int?>{},
      <String, int?>{'seed-santa': 15000, 'seed-kings': 100},
    ]) {
      screenTest(
        'a 360 con la letra al ${(scale * 100).round()} % no desborda '
        '(${budgets.isEmpty ? 'sin' : 'con'} presupuesto)',
        (tester, phone) async {
          await seedSample(tester, phone);
          await setBudgets(tester, phone, budgets);
          await pumpRegalos(tester, phone);
          await _openBudget(tester, phone);
          final subtitle = find.text(
            budgets.isEmpty ? _subtitle : _subtitleBudgeted,
          );
          expect(subtitle, findsOneWidget);
          final rect = tester.getRect(subtitle);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(360));
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -3000),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
        size: const Size(360, 740),
        textScale: scale,
      );
    }
  }

  for (final entry in const {
    'es': 'Archivada · no suma',
    'ca': 'Arxivada · no suma',
    'en': 'Archived · not counted',
  }.entries) {
    for (final scale in const [1.0, 2.0]) {
      screenTest(
        'a 360 con la letra al ${(scale * 100).round()} % la marca de una '
        'archivada (${entry.key}) no desborda y su fila conserva las cifras',
        (tester, phone) async {
          await seedSample(tester, phone);
          await tester.runAsync(() async {
            await familyOf(phone).upsertOccasion(
              const Occasion(
                id: 'vieja',
                kind: OccasionKind.custom,
                rawKind: 'custom',
                name: 'Fiesta de Leo',
                month: 5,
                day: 2,
                recurring: true,
                archived: true,
                budgetCents: 10000,
              ),
            );
            await familyOf(phone).upsertGift(
              const Gift(
                id: 'vieja-gasto',
                recipientId: 'leo',
                title: 'Libro',
                giverId: 'us',
                occasionId: 'vieja',
                status: GiftStatus.bought,
                rawStatus: 'bought',
                plannedCents: 12000,
                actualCents: 12000,
                surprise: false,
                year: 2026,
              ),
            );
          });
          await pumpRegalos(tester, phone);
          phone.container
              .read(localeProvider.notifier)
              .setLocale(Locale(entry.key));
          await settle(tester);
          await _openBudget(tester, phone);
          final budget = phone.container.read(budgetProvider);
          expect(budget.ofOccasion('vieja').spentCents, 12000);
          expect(budget.isArchivedOccasion('vieja'), isTrue);
          final vieja = _card('vieja');
          await tester.dragUntilVisible(
            vieja,
            find.byType(Scrollable).first,
            const Offset(0, -150),
          );
          final tag = find.descendant(
            of: vieja,
            matching: find.text(entry.value),
          );
          expect(tag, findsOneWidget);
          final rect = tester.getRect(tag);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(360));
          expect(tester.takeException(), isNull);
        },
        size: const Size(360, 740),
        textScale: scale,
      );
    }
  }

  screenTest(
    'con la tablet a 800 las cifras y las tarjetas siguen en su columna',
    (tester, phone) async {
      await seedSample(tester, phone);
      await setBudgets(tester, phone, {
        'seed-santa': 15000,
        'seed-kings': 30000,
      });
      await pumpRegalos(tester, phone);
      await _openBudget(tester, phone);
      final screen = tester.getRect(find.byType(BudgetScreen));
      for (final key in ['seed-santa', 'seed-kings']) {
        final rect = tester.getRect(_card(key));
        expect(rect.left, greaterThanOrEqualTo(screen.left));
        expect(rect.right, lessThanOrEqualTo(screen.right));
      }
      expect(tester.takeException(), isNull);
    },
    size: kTabletPortrait,
  );

  group('segunda ronda', () {
    const vieja = Occasion(
      id: 'vieja',
      kind: OccasionKind.custom,
      rawKind: 'custom',
      name: 'Fiesta de Leo',
      month: 5,
      day: 2,
      recurring: true,
      archived: true,
      budgetCents: 10000,
    );

    screenTest(
      'las personas no tienen presupuesto: nunca «Te pasas», aunque se gaste '
      'más de lo previsto',
      (tester, phone) async {
        await seedSample(tester, phone);
        await tester.runAsync(
          () => familyOf(phone).upsertGift(
            const Gift(
              id: 'caro',
              recipientId: 'nora',
              title: 'Disfraz',
              giverId: 'us',
              status: GiftStatus.bought,
              rawStatus: 'bought',
              plannedCents: 1000,
              actualCents: 1200,
              surprise: false,
              year: 2026,
            ),
          ),
        );
        await pumpRegalos(tester, phone);
        await _openBudget(tester, phone);
        final nora = phone.container.read(budgetProvider).ofRecipient('nora');
        expect(nora.spentCents, greaterThan(nora.plannedCents));
        expect(find.textContaining('Te pasas'), findsNothing);
        expect(tester.takeException(), isNull);
      },
      size: tall,
    );

    for (final budgetCents in const <int>[10000, 0]) {
      screenTest('si todos los importes están en una archivada (presupuesto de '
          '${budgetCents ~/ 100} €), sigue su fila con la marca y arriba queda '
          '«Sin presupuesto» a cero, no el estado vacío', (
        tester,
        phone,
      ) async {
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
            const Recipient(
              id: 'leo',
              name: 'Leo',
              colorIndex: 1,
              archived: false,
            ),
          );
          await c.upsertOccasion(
            Occasion(
              id: 'vieja',
              kind: OccasionKind.custom,
              rawKind: 'custom',
              name: 'Fiesta de Leo',
              month: 5,
              day: 2,
              recurring: true,
              archived: true,
              budgetCents: budgetCents,
            ),
          );
          await c.upsertGift(
            const Gift(
              id: 'vieja-gasto',
              recipientId: 'leo',
              title: 'Libro',
              giverId: 'us',
              occasionId: 'vieja',
              status: GiftStatus.bought,
              rawStatus: 'bought',
              plannedCents: 12000,
              actualCents: 12000,
              surprise: false,
              year: 2026,
            ),
          );
        });
        await pumpRegalos(tester, phone);
        await _openBudget(tester, phone);
        final budget = phone.container.read(budgetProvider);
        expect(budget.total.spentCents, 0);
        expect(budget.hasBudgeted, isFalse);
        expect(find.textContaining('Activa «Paga la casa»'), findsNothing);
        expect(find.text('Sin presupuesto'), findsWidgets);
        final vieja = _card('vieja');
        expect(vieja, findsOneWidget);
        expect(
          find.descendant(
            of: vieja,
            matching: find.text('Archivada · no suma'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: vieja, matching: find.textContaining('120')),
          findsWidgets,
        );
        expect(tester.takeException(), isNull);
      });
    }

    screenTest(
      'con ocasiones pero sin ningún importe, se puede poner el primer '
      'presupuesto',
      (tester, phone) async {
        await bareFamily(tester, phone);
        await tester.runAsync(
          () => familyOf(phone).upsertOccasion(
            const Occasion(
              id: 'boda',
              kind: OccasionKind.wedding,
              rawKind: 'wedding',
              name: 'Boda de Leo',
              month: 9,
              day: 12,
              recurring: false,
              year: 2027,
              archived: false,
            ),
          ),
        );
        await pumpRegalos(tester, phone);
        await _openBudget(tester, phone);
        // El estado vacío sale, y con él el acceso.
        expect(find.textContaining('Activa «Paga la casa»'), findsOneWidget);
        final access = find.byKey(const ValueKey<String>('budget-set-first'));
        expect(access, findsOneWidget);
        expect(tester.getSize(access).height, greaterThanOrEqualTo(44));
        await tester.tap(access);
        await settle(tester);
        await tester.enterText(_field('budget-sheet-field'), '60');
        await tester.tap(find.text('Guardar'));
        await settle(tester);
        expect(_total(phone).budgetCents, 6000);
        expect(find.textContaining('Activa «Paga la casa»'), findsNothing);
      },
    );

    tabletScreenTest(
      'sin ocasiones activas, la lista abre Presupuesto y permite crear una',
      (tester, phone, size) async {
        await seedSample(tester, phone);
        await tester.runAsync(() async {
          for (final o in phone.container.read(occasionsProvider)) {
            await familyOf(phone).archiveOccasion(o.id);
          }
        });
        await pumpRegalos(tester, phone);
        await tester.tap(
          find.descendant(
            of: find.bySemanticsLabel('Navegación principal'),
            matching: find.text('Ocasiones'),
          ),
        );
        await settle(tester);
        await tapText(tester, 'Presupuesto de la casa');
        expect(find.byType(BudgetScreen), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('budget-set-first')),
          findsNothing,
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('budget-create-occasion')),
        );
        await settle(tester);
        expect(find.text('Nueva ocasión'), findsOneWidget);
        expect(find.text('Tipo de ocasión'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      sizes: kLayoutSizes,
    );

    screenTest(
      'el lector de pantalla oye lo gastado de las ocasiones sin presupuesto',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openBudget(tester, phone);
        expect(
          find.bySemanticsLabel(
            RegExp('^Reyes, Sin presupuesto, Gastado .*80,99'),
          ),
          findsOneWidget,
        );
      },
      size: tall,
    );

    screenTest('las archivadas van después de las activas', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await tester.runAsync(() => familyOf(phone).upsertOccasion(vieja));
      await pumpRegalos(tester, phone);
      await _openBudget(tester, phone);
      final archived = tester.getTopLeft(_card('vieja')).dy;
      for (final id in ['seed-tio', 'seed-santa', 'seed-kings']) {
        expect(tester.getTopLeft(_card(id)).dy, lessThan(archived), reason: id);
      }
      expect(tester.takeException(), isNull);
    }, size: tall);

    screenTest(
      'en dos paneles, pulsar una ocasión archivada abre esa y no otra',
      (tester, phone) async {
        await seedSample(tester, phone);
        await tester.runAsync(() => familyOf(phone).upsertOccasion(vieja));
        await pumpRegalos(tester, phone);
        await _openBudget(tester, phone);
        await tester.tap(
          find.descendant(
            of: _card('vieja'),
            matching: find.text('Fiesta de Leo'),
          ),
        );
        await settle(tester);
        expect(_path(phone), '/occasions/vieja');
        final detail = tester.widget<OccasionDetailScreen>(
          find.byType(OccasionDetailScreen),
        );
        expect(detail.occasionId, 'vieja');
        expect(tester.takeException(), isNull);
      },
      size: const Size(1280, 2400),
    );
  });

  group('las tres cifras y «Por ocasión»', () {
    const boda = Occasion(
      id: 'boda',
      kind: OccasionKind.wedding,
      rawKind: 'wedding',
      name: 'Boda de Leo',
      month: 9,
      day: 12,
      recurring: false,
      year: 2027,
      archived: false,
    );

    screenTest(
      'sin gasto fuera de las ocasiones con presupuesto, no sale «Además, la casa ha gastado»',
      (tester, phone) async {
        await seedSample(tester, phone);
        await setBudgets(tester, phone, {
          'seed-tio': 5000,
          'seed-santa': 15000,
          'seed-kings': 30000,
        });
        await pumpRegalos(tester, phone);
        await _openBudget(tester, phone);
        final budget = phone.container.read(budgetProvider);
        expect(budget.spentOutsideBudgetCents, 0);
        // Con todo dentro, las cifras de arriba son las del total.
        expect(budget.budgeted, budget.total);
        expect(find.textContaining('Además, la casa ha gastado'), findsNothing);
        expect(find.textContaining('Si compras lo que falta'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      size: tall,
    );

    screenTest('con gasto fuera, «Además, la casa ha gastado» sale bajo «Si compras lo que falta» y se '
        'actualiza', (tester, phone) async {
      await seedSample(tester, phone);
      await setBudgets(tester, phone, {'seed-kings': 30000});
      await pumpRegalos(tester, phone);
      await _openBudget(tester, phone);
      // Solo Reyes (80,99 €): Tió y Navidad quedan fuera, 88,50 €.
      final budget = phone.container.read(budgetProvider);
      expect(budget.budgeted.spentCents, 8099);
      expect(budget.spentOutsideBudgetCents, 8850);
      expect(
        find.text(
          eur(
            'Además, la casa ha gastado 88,50 € fuera de las ocasiones con presupuesto.',
          ),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.textContaining('Además, la casa ha gastado')).dy,
        greaterThan(
          tester
              .getTopLeft(find.bySemanticsLabel(RegExp('^Si compras lo que')))
              .dy,
        ),
      );
      // Poner presupuesto a Tió lo mete en las cifras y baja lo de aparte.
      await tester.tap(find.bySemanticsLabel('Poner presupuesto a Tió'));
      await settle(tester);
      await tester.enterText(_field('budget-sheet-field'), '50');
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      expect(
        find.text(
          eur(
            'Además, la casa ha gastado 64,50 € fuera de las ocasiones con presupuesto.',
          ),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }, size: tall);

    screenTest(
      'una ocasión activa sin regalos ni presupuesto sale en «Por ocasión» y '
      'se le puede poner el primero',
      (tester, phone) async {
        await seedSample(tester, phone);
        await tester.runAsync(() async {
          await familyOf(phone).upsertOccasion(boda);
          // Una archivada sin ningún importe no sale.
          await familyOf(phone).upsertOccasion(
            const Occasion(
              id: 'vacia-archivada',
              kind: OccasionKind.custom,
              rawKind: 'custom',
              name: 'Cena',
              month: 3,
              day: 3,
              recurring: false,
              year: 2025,
              archived: true,
            ),
          );
        });
        await pumpRegalos(tester, phone);
        await _openBudget(tester, phone);
        expect(_card('vacia-archivada'), findsNothing);
        expect(
          find.descendant(
            of: _card('boda'),
            matching: find.text('Sin presupuesto'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: _card('boda'),
            matching: find.text('Poner presupuesto'),
          ),
          findsOneWidget,
        );
        expect(find.textContaining(eur('de 0 €')), findsNothing);
        await tester.tap(
          find.bySemanticsLabel('Poner presupuesto a Boda de Leo'),
        );
        await settle(tester);
        await tester.enterText(_field('budget-sheet-field'), '60');
        await tester.tap(find.text('Guardar'));
        await settle(tester);
        expect(_budgeted(phone).budgetCents, 6000);
        expect(
          find.descendant(
            of: _card('boda'),
            matching: find.text('Cambiar presupuesto'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
      size: tall,
    );

    for (final scale in const [1.0, 2.0]) {
      screenTest(
        'a 360 con la letra al ${(scale * 100).round()} % la línea «Además, la casa ha gastado» y '
        'una ocasión vacía no desbordan',
        (tester, phone) async {
          await seedSample(tester, phone);
          await tester.runAsync(() => familyOf(phone).upsertOccasion(boda));
          await setBudgets(tester, phone, {'seed-kings': 30000});
          await pumpRegalos(tester, phone);
          await _openBudget(tester, phone);
          final aside = find.textContaining('Además, la casa ha gastado');
          // Con la letra grande la tarjeta queda bajo el pliegue.
          await tester.dragUntilVisible(
            aside,
            find.byType(Scrollable).first,
            const Offset(0, -150),
          );
          expect(aside, findsOneWidget);
          final rect = tester.getRect(aside);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(360));
          await tester.dragUntilVisible(
            _card('boda'),
            find.byType(Scrollable).first,
            const Offset(0, -150),
          );
          expect(_card('boda'), findsOneWidget);
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -3000),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
        size: const Size(360, 740),
        textScale: scale,
      );
    }
  });

  screenTest(
    'por persona: una persona con lo gastado y sin previsto dice «Gastado '
    '45 €», sin «de 0 €» ni barra; la que sí tiene previsto no cambia',
    (tester, phone) async {
      await seedSample(tester, phone);
      await tester.runAsync(() async {
        final c = familyOf(phone);
        await c.upsertRecipient(
          const Recipient(
            id: 'suelta',
            name: 'Leo',
            colorIndex: 1,
            archived: false,
          ),
        );
        // Comprado a 45 € reales, sin precio previsto, pagado por la casa.
        await c.upsertGift(
          const Gift(
            id: 'sin-previsto',
            recipientId: 'suelta',
            title: 'Real',
            giverId: 'us',
            status: GiftStatus.bought,
            rawStatus: 'bought',
            actualCents: 4500,
            surprise: false,
            year: 2026,
          ),
        );
      });
      await pumpRegalos(tester, phone);
      await _openBudget(tester, phone);
      final totals = phone.container.read(budgetProvider).ofRecipient('suelta');
      expect(totals.plannedCents, 0);
      expect(totals.spentCents, 4500);

      final row = find.byKey(const ValueKey<String>('budget-person-suelta'));
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('Gastado')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text(_money(4500))),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.textContaining('de ')),
        findsNothing,
      );
      expect(
        find.descendant(of: row, matching: find.byType(BudgetBar)),
        findsNothing,
      );
      expect(find.bySemanticsLabel(RegExp('^Leo, Gastado 45')), findsOneWidget);
      // Una persona con previsto conserva «gastado de previsto» y su barra.
      final aritz = find.byKey(const ValueKey<String>('budget-person-aritz'));
      expect(
        find.descendant(of: aritz, matching: find.textContaining('de ')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: aritz, matching: find.byType(BudgetBar)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    size: tall,
  );
}
