// El presupuesto por ocasión en la web: las tres cifras (presupuesto, gastado y
// queda), «Si compras lo que falta», las tarjetas de ocasión y de persona, el
// botón que pone el presupuesto y la tarjeta de Ocasiones a ancho de móvil.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/app.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/format/money.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/family_providers.dart';
import 'package:regalos/features/occasions/presentation/occasion_detail_screen.dart';
import 'package:regalos/features/settings/application/locale_provider.dart';
import 'package:regalos/features/web_board/presentation/board_budget_view.dart';
import 'package:regalos/features/web_board/presentation/board_occasion_strip.dart';
import 'package:regalos/features/web_board/presentation/web_budget_card.dart';
import 'package:regalos/features/web_device/application/web_app_provider.dart';
import 'package:regalos/features/web_device/application/web_device_providers.dart';
import 'package:regalos/features/web_device/application/web_sync_engine.dart'
    show WebSyncStatus;
import 'package:regalos/l10n/app_localizations.dart';

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

Future<void> _mount(
  WidgetTester tester,
  FakePhone phone, {
  Map<String, int?> budgets = const {},
  bool pending = false,
  bool noGifts = false,
  bool noOccasions = false,
  bool looseSpent = false,
}) async {
  if (noGifts) {
    // Una familia con sus ocasiones de serie pero sin regalos.
    await tester.runAsync(() async {
      await familyOf(phone).createFamily(deviceName: 'M');
      await familyOf(phone).seedDefaultOccasions('ES-CT');
    });
  } else {
    await seedSample(tester, phone);
  }
  await tester.runAsync(() async {
    final c = familyOf(phone);
    if (noOccasions) {
      for (final o in phone.container.read(occasionsProvider)) {
        await c.deleteOccasion(o.id);
      }
    }
    for (final entry in budgets.entries) {
      await c.setOccasionBudget(entry.key, entry.value);
    }
    if (looseSpent) {
      // Una persona con un regalo comprado a 45 € reales y sin previsto.
      await c.upsertRecipient(
        const Recipient(
          id: 'suelta',
          name: 'Leo',
          colorIndex: 1,
          archived: false,
        ),
      );
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
    }
    if (pending) {
      // Un regalo de la casa por comprar, previsto en 200 €.
      await c.upsertGift(
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
}

Future<void> _openBudget(WidgetTester tester, FakePhone phone) async {
  phone.container.read(routerProvider).go('/occasions/budget');
  await settle(tester);
  expect(find.byType(BoardBudgetView), findsOneWidget);
}

String _path(FakePhone phone) => phone.container
    .read(routerProvider)
    .routeInformationProvider
    .value
    .uri
    .path;

String _money(int cents) => formatCents(cents, 'es');

Finder _occasion(String id) =>
    find.byKey(ValueKey<String>('budget-occasion-$id'));

Finder _field() => find.byKey(const ValueKey<String>('budget-sheet-field'));

final _changeDate = find.byKey(const ValueKey<String>('board-change-date'));

const _budgets = <String, int?>{'seed-santa': 15000, 'seed-kings': 30000};

void main() {
  setUpAll(loadInter);

  for (final size in const [Size(1440, 1000), Size(800, 1100)]) {
    final at = '${size.width.toInt()}';

    screenTest(
      'a $at sin presupuesto: «Sin presupuesto», Queda sin cifra, un acceso '
      'para ponerlo, y nunca «de 0 €» ni «Te pasas»',
      (tester, phone) async {
        await _mount(tester, phone);
        await _openBudget(tester, phone);
        expect(find.text('Sin presupuesto'), findsWidgets);
        expect(find.text('Gastado'), findsWidgets);
        expect(find.text('Disponible'), findsOneWidget);
        expect(find.text('–'), findsOneWidget);
        expect(find.textContaining('Si compras lo que falta'), findsNothing);
        expect(find.textContaining('Te pasas'), findsNothing);
        expect(find.textContaining(eur('de 0 €')), findsNothing);
        expect(
          find.descendant(
            of: _occasion('seed-kings'),
            matching: find.text('Sin presupuesto'),
          ),
          findsOneWidget,
        );

        // El acceso de arriba: elige la ocasión y pone el importe.
        await tester.tap(
          find.byKey(const ValueKey<String>('budget-set-first')),
        );
        await settle(tester);
        await tester.enterText(_field(), '75');
        await tester.tap(find.text('Guardar'));
        await settle(tester);
        expect(phone.container.read(budgetProvider).total.budgetCents, 7500);
        expect(
          find.byKey(const ValueKey<String>('budget-set-first')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
      size: size,
      overrides: _web(),
    );

    screenTest(
      'a $at con presupuesto: presupuesto, gastado, queda y «Si compras lo '
      'que falta»',
      (tester, phone) async {
        await _mount(tester, phone, budgets: _budgets, pending: true);
        await _openBudget(tester, phone);
        final budget = phone.container.read(budgetProvider);
        // Las cifras de arriba cuentan solo las ocasiones con presupuesto.
        final total = budget.budgeted;
        final kingsTotals = budget.ofOccasion('seed-kings');
        expect(total.budgetCents, 45000);
        expect(find.text(eur('450 €')), findsOneWidget);
        expect(find.text(eur('145,49 €')), findsWidgets);
        expect(
          find.text(
            eur(
              'Además, la casa ha gastado 24 € fuera de las ocasiones con presupuesto.',
            ),
          ),
          findsOneWidget,
        );
        expect(find.text('Disponible'), findsOneWidget);
        expect(find.textContaining('Te pasas'), findsNothing);
        final ifBought = total.leftIfBoughtCents!;
        expect(ifBought, greaterThan(0));
        expect(
          find.bySemanticsLabel(
            eur('Si compras lo que falta, te quedarás con ${_money(ifBought)}'),
          ),
          findsOneWidget,
        );
        final kings = _occasion('seed-kings');
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

        // Si no llega: «te pasarás»; y «Te pasas» solo si ya se pasó.
        await setBudgets(tester, phone, {
          'seed-santa': null,
          'seed-kings': kingsTotals.spentCents + kingsTotals.pendingCents - 500,
        });
        await settle(tester);
        expect(
          find.bySemanticsLabel(eur('Si compras lo que falta, te pasarás 5 €')),
          findsOneWidget,
        );
        expect(find.text('Te pasas'), findsNothing);
        await setBudgets(tester, phone, {
          'seed-kings': kingsTotals.spentCents - 100,
        });
        await settle(tester);
        expect(find.text('Te pasas'), findsOneWidget);
        expect(find.text('Disponible'), findsNothing);
        expect(tester.takeException(), isNull);
      },
      size: size,
      overrides: _web(),
    );

    screenTest(
      'a $at pulsar una ocasión o una persona abre sus regalos y el botón '
      'cambia o quita el presupuesto',
      (tester, phone) async {
        await _mount(tester, phone, budgets: _budgets);
        await _openBudget(tester, phone);

        await tester.tap(
          find.bySemanticsLabel('Cambiar el presupuesto de Reyes'),
        );
        await settle(tester);
        expect(find.text('Presupuesto de Reyes'), findsOneWidget);
        expect(tester.widget<TextField>(_field()).controller!.text, '300');
        await tester.enterText(_field(), '1.000');
        await tester.tap(find.text('Guardar'));
        await settle(tester);
        expect(
          phone.container
              .read(budgetProvider)
              .ofOccasion('seed-kings')
              .budgetCents,
          100000,
        );

        await tester.tap(
          find.bySemanticsLabel('Cambiar el presupuesto de Reyes'),
        );
        await settle(tester);
        await tester.enterText(_field(), '');
        await tester.tap(find.text('Guardar'));
        await settle(tester);
        expect(
          phone.container
              .read(budgetProvider)
              .ofOccasion('seed-kings')
              .budgetCents,
          isNull,
        );
        expect(
          find.descendant(
            of: _occasion('seed-kings'),
            matching: find.text('Sin presupuesto'),
          ),
          findsOneWidget,
        );

        // Una persona: su ficha.
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey<String>('budget-person-aritz')),
            matching: find.text('Aritz'),
          ),
        );
        await settle(tester);
        expect(_path(phone), '/people/aritz');

        // Una ocasión: sus regalos.
        await _openBudget(tester, phone);
        await tester.tap(
          find.descendant(
            of: _occasion('seed-santa'),
            matching: find.text('Navidad'),
          ),
        );
        await settle(tester);
        expect(_path(phone), '/occasions/seed-santa');
        expect(tester.takeException(), isNull);
      },
      size: size,
      overrides: _web(),
    );
  }

  for (final (size, scale) in const [
    (Size(1440, 900), 2.0),
    (Size(360, 740), 2.0),
    (Size(360, 740), 1.0),
  ]) {
    for (final budgets in const [<String, int?>{}, _budgets]) {
      screenTest(
        'a ${size.width.toInt()} con la letra al ${(scale * 100).round()} % '
        'no desborda (${budgets.isEmpty ? 'sin' : 'con'} presupuesto)',
        (tester, phone) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await _mount(tester, phone, budgets: budgets, pending: true);
          tester.takeException();
          await _openBudget(tester, phone);
          final budget = find.byType(BoardBudgetView);
          final l10n = AppLocalizations.of(tester.element(budget));
          final subtitle = find.text(
            budgets.isEmpty ? l10n.budgetSubtitle : l10n.budgetSubtitleBudgeted,
          );
          expect(subtitle, findsOneWidget);
          final rect = tester.getRect(subtitle);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -4000),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
        size: size,
        overrides: _web(),
      );
    }
  }

  for (final (size, scale) in const [
    (Size(1440, 900), 2.0),
    (Size(360, 740), 2.0),
    (Size(360, 740), 1.0),
  ]) {
    for (final entry in const {
      'es': 'Archivada · no suma',
      'ca': 'Arxivada · no suma',
      'en': 'Archived · not counted',
    }.entries) {
      screenTest(
        'a ${size.width.toInt()} con la letra al ${(scale * 100).round()} % '
        'la marca de una archivada (${entry.key}) no desborda y su fila '
        'conserva las cifras',
        (tester, phone) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await _mount(tester, phone);
          await driveAsync(tester, () async {
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
          phone.container
              .read(localeProvider.notifier)
              .setLocale(Locale(entry.key));
          await settle(tester);
          tester.takeException();
          await _openBudget(tester, phone);
          final budget = phone.container.read(budgetProvider);
          expect(budget.ofOccasion('vieja').spentCents, 12000);
          expect(budget.isArchivedOccasion('vieja'), isTrue);
          final vieja = _occasion('vieja');
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
          expect(rect.right, lessThanOrEqualTo(size.width));
          expect(tester.takeException(), isNull);
        },
        size: size,
        overrides: _web(),
      );
    }
  }

  for (final budgetCents in const <int>[10000, 0]) {
    screenTest(
      'si todos los importes están en una archivada (presupuesto de '
      '${budgetCents ~/ 100} €), sigue su fila con la marca y arriba queda '
      '«Sin presupuesto» a cero, no el estado vacío',
      (tester, phone) async {
        await _mount(tester, phone, noGifts: true);
        await driveAsync(tester, () async {
          for (final o in phone.container.read(occasionsProvider)) {
            await familyOf(phone).deleteOccasion(o.id);
          }
        });
        await driveAsync(tester, () async {
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
        await settle(tester);
        await _openBudget(tester, phone);
        final budget = phone.container.read(budgetProvider);
        expect(budget.total.spentCents, 0);
        expect(budget.hasBudgeted, isFalse);
        expect(
          find.textContaining('Activa «Cuenta como gasto de casa»'),
          findsNothing,
        );
        expect(find.text('Sin presupuesto'), findsWidgets);
        final vieja = _occasion('vieja');
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
      },
      size: const Size(1440, 1000),
      overrides: _web(),
    );
  }

  group('las tres cifras y «Por ocasión» en la web', () {
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

    for (final size in const [Size(1440, 1000), Size(800, 1100)]) {
      final at = '${size.width.toInt()}';

      screenTest(
        'a $at «Además, la casa ha gastado» sale solo si hay gasto fuera de las ocasiones con '
        'presupuesto, y una ocasión vacía se lista con «Poner presupuesto»',
        (tester, phone) async {
          await _mount(tester, phone, budgets: {'seed-kings': 30000});
          await driveAsync(tester, () => familyOf(phone).upsertOccasion(boda));
          await tester.pump();
          await _openBudget(tester, phone);
          expect(
            find.text(
              eur(
                'Además, la casa ha gastado 88,50 € fuera de las ocasiones con presupuesto.',
              ),
            ),
            findsOneWidget,
          );
          // Las cifras de arriba son solo las de Reyes.
          expect(find.text(eur('300 €')), findsOneWidget);
          expect(find.text(eur('80,99 €')), findsWidgets);
          expect(find.text(eur('169,49 €')), findsNothing);
          // La ocasión vacía sale con su acceso.
          expect(
            find.descendant(
              of: _occasion('boda'),
              matching: find.text('Sin presupuesto'),
            ),
            findsOneWidget,
          );
          await tester.tap(
            find.bySemanticsLabel('Poner presupuesto a Boda de Leo'),
          );
          await settle(tester);
          await tester.enterText(_field(), '60');
          await tester.tap(find.text('Guardar'));
          await settle(tester);
          expect(
            phone.container.read(budgetProvider).budgeted.budgetCents,
            36000,
          );

          // Con todo dentro de un presupuesto, no queda nada aparte.
          await setBudgets(tester, phone, {
            'seed-tio': 5000,
            'seed-santa': 15000,
          });
          await settle(tester);
          expect(
            find.textContaining('Además, la casa ha gastado'),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        },
        size: size,
        overrides: _web(),
      );
    }

    screenTest(
      'sin ninguna ocasión con presupuesto no sale «Además, la casa ha gastado» y el subtítulo no '
      'dice que las cifras solo cuentan las que tienen presupuesto',
      (tester, phone) async {
        await _mount(tester, phone);
        await _openBudget(tester, phone);
        expect(find.textContaining('Además, la casa ha gastado'), findsNothing);
        expect(
          find.textContaining('«Gastado» suma los precios reales'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Las tres cifras solo incluyen'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
      size: const Size(1440, 1000),
      overrides: _web(),
    );

    screenTest(
      'con presupuesto el subtítulo avisa de que las cifras solo cuentan esas '
      'ocasiones',
      (tester, phone) async {
        await _mount(tester, phone, budgets: {'seed-kings': 30000});
        await _openBudget(tester, phone);
        expect(
          find.textContaining('Las tres cifras solo incluyen ocasiones con '),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
      size: const Size(1440, 1000),
      overrides: _web(),
    );

    screenTest(
      'el cumpleaños de una persona archivada sigue llevando su nombre, y '
      'cada botón dice de quién es',
      (tester, phone) async {
        await _mount(tester, phone);
        await driveAsync(tester, () async {
          await familyOf(phone).archiveRecipient('nora');
          await familyOf(phone).archiveRecipient('leo');
        });
        await tester.pump();
        await _openBudget(tester, phone);
        for (final (id, name) in const [
          ('birthday-nora', 'Nora'),
          ('birthday-leo', 'Leo'),
        ]) {
          final card = _occasion(id);
          expect(card, findsOneWidget, reason: id);
          expect(
            find.descendant(
              of: card,
              matching: find.text('Cumpleaños de $name'),
            ),
            findsOneWidget,
            reason: id,
          );
          expect(
            find.bySemanticsLabel('Poner presupuesto a Cumpleaños de $name'),
            findsOneWidget,
            reason: id,
          );
        }
        expect(
          find.bySemanticsLabel('Poner presupuesto a Cumpleaños'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
      size: const Size(1440, 1000),
      overrides: _web(),
    );

    screenTest(
      'la tarjeta compacta cuenta solo las ocasiones con presupuesto',
      (tester, phone) async {
        await _mount(tester, phone, budgets: {'seed-kings': 30000});
        phone.container.read(routerProvider).go('/occasions');
        await settle(tester);
        final card = find.byType(WebBudgetCard);
        expect(
          find.descendant(
            of: card,
            matching: find.text(eur('${_money(8099)} de 300 €')),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.text('Disponible ${_money(30000 - 8099)}'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
      size: const Size(390, 844),
      overrides: _web(),
    );
  });

  group('la tarjeta de Ocasiones a ancho de móvil', () {
    screenTest(
      'sin presupuesto dice «Sin presupuesto»',
      (tester, phone) async {
        await _mount(tester, phone);
        phone.container.read(routerProvider).go('/occasions');
        await settle(tester);
        final card = find.byType(WebBudgetCard);
        expect(card, findsOneWidget);
        expect(
          find.descendant(of: card, matching: find.text('Sin presupuesto')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: card, matching: find.textContaining('Te pasas')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
      size: const Size(390, 844),
      overrides: _web(),
    );

    screenTest(
      'con presupuesto dice lo gastado de él y lo que queda, o «Te pasas» si '
      'se pasó',
      (tester, phone) async {
        await _mount(tester, phone, budgets: _budgets);
        phone.container.read(routerProvider).go('/occasions');
        await settle(tester);
        final card = find.byType(WebBudgetCard);
        expect(
          find.descendant(
            of: card,
            matching: find.text(eur('${_money(14549)} de 450 €')),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.text('Disponible ${_money(45000 - 14549)}'),
          ),
          findsOneWidget,
        );
        await setBudgets(tester, phone, {
          'seed-santa': null,
          'seed-kings': 100,
        });
        await settle(tester);
        expect(
          find.descendant(
            of: card,
            matching: find.text('Te pasas ${_money(8099 - 100)}'),
          ),
          findsOneWidget,
        );

        // Al pulsarla abre la página del presupuesto.
        await tester.tap(card);
        await settle(tester);
        expect(_path(phone), '/occasions/budget');
        expect(tester.takeException(), isNull);
      },
      size: const Size(390, 844),
      overrides: _web(),
    );

    screenTest(
      'a 360 con la letra al 200 % no desborda',
      (tester, phone) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _mount(tester, phone, budgets: _budgets);
        tester.takeException();
        phone.container.read(routerProvider).go('/occasions');
        await settle(tester);
        expect(find.byType(WebBudgetCard), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      size: const Size(360, 740),
      overrides: _web(),
    );
  });

  screenTest(
    'las ocasiones archivadas y los regalos sin ocasión con importe salen, '
    'al final y marcadas',
    (tester, phone) async {
      await _mount(tester, phone);
      await driveAsync(tester, () async {
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
      await settle(tester);
      await _openBudget(tester, phone);
      final vieja = _occasion('vieja');
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
      final none = _occasion('');
      expect(none, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    size: const Size(1440, 1000),
    overrides: _web(),
  );

  group('segunda ronda', () {
    const vieja = Occasion(
      id: 'vieja',
      kind: OccasionKind.custom,
      rawKind: 'custom',
      name: 'Fiesta de Leo',
      month: 5,
      day: 2,
      year: 2024,
      recurring: false,
      archived: true,
      budgetCents: 10000,
    );

    screenTest(
      'las personas no tienen presupuesto: nunca «Te pasas», aunque se gaste '
      'más de lo previsto',
      (tester, phone) async {
        await _mount(tester, phone);
        await driveAsync(
          tester,
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
        await settle(tester);
        await _openBudget(tester, phone);
        final nora = phone.container.read(budgetProvider).ofRecipient('nora');
        expect(nora.spentCents, greaterThan(nora.plannedCents));
        expect(find.textContaining('Te pasas'), findsNothing);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1440, 1000),
      overrides: _web(),
    );

    screenTest(
      'con ocasiones pero sin ningún importe, se puede poner el primer '
      'presupuesto',
      (tester, phone) async {
        await _mount(tester, phone, noGifts: true);
        await _openBudget(tester, phone);
        expect(
          find.textContaining('Activa «Cuenta como gasto de casa»'),
          findsOneWidget,
        );
        final access = find.byKey(const ValueKey<String>('budget-set-first'));
        expect(access, findsOneWidget);
        expect(tester.getSize(access).height, greaterThanOrEqualTo(44));
        await tester.tap(access);
        await settle(tester);
        await tester.enterText(_field(), '60');
        await tester.tap(find.text('Guardar'));
        await settle(tester);
        expect(phone.container.read(budgetProvider).total.budgetCents, 6000);
        expect(
          find.textContaining('Activa «Cuenta como gasto de casa»'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
      size: const Size(1440, 1000),
      overrides: _web(),
    );

    screenTest(
      'sin ninguna ocasión activa, el botón general crea una ocasión',
      (tester, phone) async {
        await _mount(tester, phone, noGifts: true, noOccasions: true);
        await _openBudget(tester, phone);
        expect(
          find.byKey(const ValueKey<String>('budget-set-first')),
          findsNothing,
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('budget-create-occasion')),
        );
        await settle(tester);
        expect(find.text('Nueva ocasión'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1440, 1000),
      overrides: _web(),
    );

    screenTest(
      'una archivada de 2024 abre su calendario y no selecciona otra ocasión',
      (tester, phone) async {
        await _mount(tester, phone);
        await driveAsync(tester, () => familyOf(phone).upsertOccasion(vieja));
        await settle(tester);
        await _openBudget(tester, phone);
        await tester.tap(
          find.descendant(
            of: _occasion('vieja'),
            matching: find.text('Fiesta de Leo'),
          ),
        );
        await settle(tester);
        expect(_path(phone), '/occasions/vieja');
        expect(find.text('Fiesta de Leo'), findsWidgets);
        final strip = tester.widget<BoardOccasionStrip>(
          find.byType(BoardOccasionStrip),
        );
        expect(strip.selectedId, vieja.id);
        await tester.tap(_changeDate);
        await settle(tester);
        final picker = tester.widget<DatePickerDialog>(
          find.byType(DatePickerDialog),
        );
        expect(picker.initialDate, DateTime(2024, 5, 2));
        expect(tester.takeException(), isNull);
      },
      size: const Size(1440, 1000),
      overrides: _web(),
    );

    screenTest(
      'cambiar la fecha conserva el nombre, el archivado y el presupuesto remotos',
      (tester, phone) async {
        await _mount(tester, phone, budgets: _budgets);
        const id = 'seed-santa';
        phone.container.read(routerProvider).go('/occasions/$id');
        await settle(tester);
        await tester.tap(_changeDate);
        await settle(tester);
        final picker = find.byType(DatePickerDialog);
        expect(picker, findsOneWidget);

        final local = (await familyState(tester, phone)).doc;
        final remoteClock = HlcClock(node: 'remote', last: local.maxStamp);
        final remote = local.set(remoteClock, Collections.occasions, id, {
          'name': 'Navidad de Nora',
          'archived': true,
          Occasion.budgetField: 17500,
        });
        await driveAsync(
          tester,
          () => familyOf(phone).mergeRemote(remote, fromNode: remoteClock.node),
        );
        await settle(tester);
        expect(picker, findsOneWidget);
        await tester.tap(
          find.descendant(of: picker, matching: find.text('26')),
        );
        await tester.pump();
        await tester.tap(
          find.descendant(of: picker, matching: find.byType(TextButton)).last,
        );
        await settleSaved(tester);

        final saved = (await familyState(tester, phone)).doc;
        final record = saved.record(Collections.occasions, id)!;
        final incoming = remote.record(Collections.occasions, id)!;
        expect(record['day'], 26);
        for (final field in ['name', 'archived', Occasion.budgetField]) {
          expect(record.field(field), incoming.field(field), reason: field);
        }
        expect(tester.takeException(), isNull);
      },
      size: const Size(1440, 1000),
      overrides: _web(),
    );
  });

  // Para el import de OccasionDetailScreen: pulsar una ocasión en el móvil
  // abre su detalle.
  screenTest(
    'a ancho de móvil, pulsar una ocasión del presupuesto abre su detalle',
    (tester, phone) async {
      await _mount(tester, phone, budgets: _budgets);
      await _openBudget(tester, phone);
      await tester.tap(
        find.descendant(
          of: _occasion('seed-kings'),
          matching: find.text('Reyes'),
        ),
      );
      await settle(tester);
      expect(_path(phone), '/occasions/seed-kings');
      expect(find.byType(OccasionDetailScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    size: const Size(390, 2200),
    overrides: _web(),
  );

  for (final size in const [Size(1440, 1000), Size(800, 1100)]) {
    screenTest(
      'a ${size.width.toInt()}, por persona: un regalo con solo precio real '
      'muestra «45 € de 45 €»',
      (tester, phone) async {
        await _mount(tester, phone, looseSpent: true);
        await _openBudget(tester, phone);
        final totals = phone.container
            .read(budgetProvider)
            .ofRecipient('suelta');
        expect(totals.plannedCents, 4500);
        expect(totals.spentCents, 4500);
        final card = find.byKey(const ValueKey<String>('budget-person-suelta'));
        expect(card, findsOneWidget);
        expect(
          find.descendant(of: card, matching: find.text(_money(4500))),
          findsOneWidget,
        );
        expect(
          find.descendant(of: card, matching: find.text('de ${_money(4500)}')),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('Leo, ${_money(4500)} de ${_money(4500)}'),
          findsOneWidget,
        );
        final aritz = find.byKey(const ValueKey<String>('budget-person-aritz'));
        expect(
          find.descendant(of: aritz, matching: find.textContaining('de ')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
      size: size,
      overrides: _web(),
    );
  }
}
