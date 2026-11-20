import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';

const _christmas = Occasion(
  id: 'navidad',
  kind: OccasionKind.santa,
  rawKind: 'santa',
  name: 'Navidad',
  month: 12,
  day: 25,
  recurring: true,
  archived: false,
);

const _kings = Occasion(
  id: 'reyes',
  kind: OccasionKind.kings,
  rawKind: 'kings',
  name: 'Reyes',
  month: 1,
  day: 6,
  recurring: true,
  archived: false,
  budgetCents: 20000,
);

const _household = Giver(
  id: 'household',
  name: 'Nosotros',
  colorIndex: 0,
  householdPays: true,
  archived: false,
);

const _leo = Giver(
  id: 'leo',
  name: 'Leo',
  colorIndex: 1,
  householdPays: false,
  archived: false,
);

final _base = DateTime.utc(2026, 11, 19);

/// La misma ocasión, archivada.
Occasion _archive(Occasion o) => Occasion(
  id: o.id,
  kind: o.kind,
  rawKind: o.rawKind,
  name: o.name,
  month: o.month,
  day: o.day,
  year: o.year,
  recurring: o.recurring,
  recipientId: o.recipientId,
  archived: true,
  color: o.color,
  icon: o.icon,
  budgetCents: o.budgetCents,
);

FamilyDoc _edit(
  FamilyDoc doc,
  String node,
  int seconds,
  Map<String, Object?> fields,
) => withClock(Clock.fixed(_base.add(Duration(seconds: seconds))), () {
  final clock = HlcClock(node: node);
  return doc.setChanged(clock, Collections.occasions, _christmas.id, fields);
});

SyncRecord _occasionRecord(FamilyDoc doc) =>
    doc.record(Collections.occasions, _christmas.id)!;

FamilyDoc _roundTrip(FamilyDoc doc) => FamilyDoc.fromJson(
  jsonDecode(jsonEncode(doc.toJson())) as Map<String, Object?>,
);

Gift _gift(
  String title,
  int? planned, {
  int? actual,
  String? occasion = 'navidad',
  String giver = 'household',
  GiftStatus status = GiftStatus.idea,
}) => Gift(
  id: title,
  title: title,
  recipientId: 'aritz',
  giverId: giver,
  occasionId: occasion,
  status: status,
  rawStatus: status.name,
  plannedCents: planned,
  actualCents: actual,
  surprise: false,
  year: 2026,
);

void main() {
  late FamilyDoc oldDoc;

  setUp(() {
    final oldFields = _christmas.toFields()..remove('budgetCents');
    oldDoc = _edit(FamilyDoc.empty('list'), 'aritz', 0, oldFields);
  });

  test('un documento antiguo sin el campo se lee sin presupuesto', () {
    final record = _occasionRecord(_roundTrip(oldDoc));
    expect(record.field('budgetCents'), isNull);
    expect(Occasion.fromRecord(record), _christmas);
  });

  test('el presupuesto y su borrado se serializan con el mismo campo', () {
    final occasion = _christmas.copyWith(budgetCents: 50000);
    expect(occasion, isNot(_christmas));
    expect(occasion.toFields()['budgetCents'], 50000);
    final written = _edit(oldDoc, 'aritz', 1, occasion.toFields());
    expect(Occasion.fromRecord(_occasionRecord(_roundTrip(written))), occasion);

    final cleared = occasion.copyWith(budgetCents: null);
    expect(cleared, _christmas);
    expect(cleared.toFields(), containsPair('budgetCents', null));
    final record = _occasionRecord(
      _roundTrip(_edit(written, 'aritz', 2, cleared.toFields())),
    );
    expect(record.field('budgetCents'), isNotNull);
    expect(Occasion.fromRecord(record), _christmas);
  });

  test('valida el rango y el valor entero del presupuesto recibido', () {
    for (final invalid in [-1, 10.5, '50000', true, kMaxCents + 1]) {
      final record = _occasionRecord(
        _edit(oldDoc, 'aritz', 1, {'budgetCents': invalid}),
      );
      expect(Occasion.fromRecord(record), _christmas, reason: '$invalid');
    }
    for (final valid in [0, kMaxCents]) {
      final record = _occasionRecord(
        _edit(oldDoc, 'aritz', 1, {'budgetCents': valid}),
      );
      expect(Occasion.fromRecord(record)?.budgetCents, valid);
    }
  });

  test('un cliente antiguo conserva el campo desconocido y su sello', () {
    final modern = _edit(oldDoc, 'aritz', 1, {'budgetCents': 50000});
    final received = _roundTrip(modern);
    // El editor de 1.0.3 reconstruye solamente los campos que conoce y
    // guarda con setChanged sobre el documento recibido, como upsertOccasion.
    final legacyFields = {
      for (final name in [
        'kind',
        'name',
        'month',
        'day',
        'year',
        'recurring',
        'recipientId',
        'archived',
        'color',
        'icon',
      ])
        name: _occasionRecord(received)[name],
    }..['name'] = 'Fiesta de Navidad';
    final reexported = _roundTrip(_edit(received, 'nora', 2, legacyFields));
    final budget = _occasionRecord(modern).field('budgetCents');
    expect(_occasionRecord(reexported).field('budgetCents'), budget);
    for (final merged in [modern.merge(reexported), reexported.merge(modern)]) {
      final record = _occasionRecord(merged);
      expect(record.field('budgetCents'), budget);
      expect(Occasion.fromRecord(record)?.budgetCents, 50000);
      expect(Occasion.fromRecord(record)?.name, 'Fiesta de Navidad');
    }
  });

  for (final latestBudget in <int?>[null, 50000]) {
    test('en ambos órdenes gana el presupuesto posterior ($latestBudget)', () {
      final original = _edit(oldDoc, 'aritz', 1, {'budgetCents': 20000});
      final earlier = _edit(original, 'aritz', 2, {
        'budgetCents': latestBudget == null ? 50000 : null,
        'name': 'Fiesta de Navidad',
      });
      final later = _edit(original, 'nora', 3, {'budgetCents': latestBudget});
      final stamped = _occasionRecord(later).field('budgetCents');
      expect(stamped, isNotNull);
      expect(stamped!.value, latestBudget);
      expect(
        stamped.stamp,
        greaterThan(_occasionRecord(earlier).field('budgetCents')!.stamp),
      );
      expect(
        _occasionRecord(later).field('name'),
        _occasionRecord(original).field('name'),
      );

      for (final merged in [earlier.merge(later), later.merge(earlier)]) {
        final record = _occasionRecord(merged);
        expect(record.field('budgetCents'), stamped);
        expect(record.field('name'), _occasionRecord(earlier).field('name'));
        final occasion = Occasion.fromRecord(record)!;
        expect(occasion.budgetCents, latestBudget);
        expect(occasion.name, 'Fiesta de Navidad');
      }
    });
  }

  test(
    'calcula presupuesto, gasto real y pendiente por ocasión y en total',
    () {
      final budget = FamilyView(
        recipients: const [],
        givers: const [_household, _leo],
        occasions: [
          _christmas.copyWith(budgetCents: 50000),
          _kings,
          const Occasion(
            id: 'archivada',
            kind: OccasionKind.custom,
            rawKind: 'custom',
            name: 'Fiesta',
            month: 3,
            day: 1,
            recurring: false,
            archived: true,
            budgetCents: 1000,
          ),
        ],
        gifts: [
          _gift('Puzle', 4999, actual: 3999, status: GiftStatus.bought),
          _gift('Cometa', 2000, status: GiftStatus.decided),
          _gift('Libro', 80000, actual: 80000, giver: 'leo'),
          _gift(
            'Cuento',
            1500,
            occasion: 'archivada',
            status: GiftStatus.wrapped,
          ),
          _gift('Patines', 2500, occasion: null),
          _gift(
            'Cromos',
            500,
            occasion: 'desconocida',
            status: GiftStatus.delivered,
          ),
        ],
      ).budget();

      final christmas = budget.ofOccasion('navidad');
      expect(
        christmas,
        const BudgetTotals(
          budgetCents: 50000,
          plannedCents: 6999,
          spentCents: 3999,
          pendingCents: 2000,
        ),
      );
      expect(christmas.leftCents, 46001);
      expect(christmas.leftIfBoughtCents, 44001);
      expect(christmas.isOver, isFalse);

      expect(
        budget.ofOccasion('reyes'),
        const BudgetTotals(budgetCents: 20000),
      );
      final archived = budget.ofOccasion('archivada');
      expect(archived.leftCents, -500);
      expect(archived.isOver, isTrue);
      // Su fila conserva todas sus cifras.
      expect(
        archived,
        const BudgetTotals(
          budgetCents: 1000,
          plannedCents: 1500,
          spentCents: 1500,
        ),
      );

      final loose = budget.byOccasion[Budget.noOccasion]!;
      expect(budget.byOccasion, isNot(contains('desconocida')));
      expect(
        loose,
        const BudgetTotals(
          plannedCents: 3000,
          spentCents: 500,
          pendingCents: 2500,
        ),
      );
      expect(loose.leftCents, isNull);
      expect(loose.leftIfBoughtCents, isNull);
      expect(loose.isOver, isFalse);

      // La archivada (1000 € de presupuesto, Cuento) no suma en el total.
      expect(
        budget.total,
        const BudgetTotals(
          budgetCents: 70000,
          plannedCents: 9999,
          spentCents: 4499,
          pendingCents: 4500,
        ),
      );
      expect(budget.total.leftCents, 65501);
      expect(budget.total.leftIfBoughtCents, 61001);
      expect(
        budget.ofRecipient('aritz'),
        const BudgetTotals(plannedCents: 9999, spentCents: 4499),
      );
    },
  );

  test(
    'un regalo creado a la vez que se borra su ocasión queda sin ocasión',
    () {
      withClock(Clock.fixed(_base.add(const Duration(seconds: 1))), () {
        final aritz = HlcClock(node: 'aritz');
        final nora = HlcClock(node: 'nora');
        final shared = oldDoc.set(
          aritz,
          Collections.givers,
          _household.id,
          _household.toFields(),
        );
        final deleted = shared.delete(
          aritz,
          Collections.occasions,
          _christmas.id,
        );
        final gift = _gift(
          'Puzle',
          1500,
          actual: 1200,
          status: GiftStatus.bought,
        );
        final added = shared.set(
          nora,
          Collections.gifts,
          gift.id,
          gift.toFields(),
        );

        const totals = BudgetTotals(plannedCents: 1500, spentCents: 1200);
        for (final merged in [deleted.merge(added), added.merge(deleted)]) {
          final view = FamilyView.fromDoc(merged, year: 2026);
          expect(view.occasions, isEmpty);
          expect(view.gifts.single.occasionId, _christmas.id);
          final budget = view.budget();
          expect(budget.total, totals);
          expect(budget.byOccasion, {Budget.noOccasion: totals});
        }
      });
    },
  );

  test('archivar una ocasión la saca del total y recuperarla devuelve sus importes', () {
    withClock(Clock.fixed(_base.add(const Duration(seconds: 1))), () {
      final clock = HlcClock(node: 'aritz');
      final bought = _gift('Puzle', 25000, status: GiftStatus.bought);
      final pending = _gift('Cometa', 2000);
      final active = oldDoc
          .set(clock, Collections.givers, _household.id, _household.toFields())
          .set(clock, Collections.occasions, _kings.id, _kings.toFields())
          .set(clock, Collections.occasions, _christmas.id, {
            'budgetCents': 10000,
          })
          .set(clock, Collections.gifts, bought.id, bought.toFields())
          .set(clock, Collections.gifts, pending.id, pending.toFields());
      final archived = active.set(clock, Collections.occasions, _christmas.id, {
        'archived': true,
      });

      final before = FamilyView.fromDoc(active, year: 2026).budget();
      final after = FamilyView.fromDoc(archived, year: 2026).budget();
      const full = BudgetTotals(
        budgetCents: 10000,
        plannedCents: 27000,
        spentCents: 25000,
        pendingCents: 2000,
      );
      expect(before.total.isOver, isFalse);
      // Reyes (200 €) está activa en los dos casos.
      expect(
        before.total,
        const BudgetTotals(
          budgetCents: 30000,
          plannedCents: 27000,
          spentCents: 25000,
          pendingCents: 2000,
        ),
      );
      // Archivada: fuera del total y de las personas; su fila sigue entera.
      expect(after.total, const BudgetTotals(budgetCents: 20000));
      expect(after.ofRecipient('aritz'), const BudgetTotals());
      expect(after.budgeted, const BudgetTotals(budgetCents: 20000));
      expect(after.spentOutsideBudgetCents, 0);
      expect(after.ofOccasion(_christmas.id), full);
      expect(after.isArchivedOccasion(_christmas.id), isTrue);
      // Recuperarla (desarchivar) devuelve sus importes.
      final restored = archived.set(
        clock,
        Collections.occasions,
        _christmas.id,
        {'archived': false},
      );
      final back = FamilyView.fromDoc(restored, year: 2026).budget();
      expect(back.total, before.total);
      expect(back.byRecipient, before.byRecipient);
    });
  });

  for (final actual in <int?>[3200, null]) {
    test('regalo comprado sin precio previsto (precio real: $actual)', () {
      final budget = FamilyView(
        recipients: const [],
        givers: const [_household],
        occasions: const [_christmas],
        gifts: [
          _gift('Puzle', null, actual: actual, status: GiftStatus.bought),
        ],
      ).budget();
      final totals = BudgetTotals(spentCents: actual ?? 0);
      expect(budget.byOccasion[_christmas.id], totals);
      expect(budget.total, totals);
    });
  }

  test('distingue presupuesto ausente, cero, gasto al límite y previsión', () {
    final missing = FamilyView(
      recipients: const [],
      givers: const [_household],
      occasions: const [_christmas],
      gifts: [_gift('Cometa', 1500, actual: 1800)],
    ).budget();
    for (final totals in [missing.ofOccasion('navidad'), missing.total]) {
      expect(totals.budgetCents, isNull);
      expect(totals.spentCents, 1800);
      expect(totals.pendingCents, 1500);
      expect(totals.leftCents, isNull);
      expect(totals.leftIfBoughtCents, isNull);
      expect(totals.isOver, isFalse);
    }

    final zero = FamilyView(
      recipients: const [],
      givers: const [_household],
      occasions: [_christmas.copyWith(budgetCents: 0)],
      gifts: [_gift('Cometa', 1500)],
    ).budget().total;
    expect(zero.budgetCents, 0);
    expect(zero.leftCents, 0);
    expect(zero.leftIfBoughtCents, -1500);
    expect(zero.isOver, isFalse);
  });

  group('las cifras de arriba (Budget.budgeted) cuentan solo las ocasiones con '
      'presupuesto', () {
    const tio = Occasion(
      id: 'tio',
      kind: OccasionKind.custom,
      rawKind: 'custom',
      name: 'Tió',
      month: 12,
      day: 24,
      recurring: true,
      archived: false,
      budgetCents: 8800,
    );

    Budget budgetOf(
      List<Occasion> occasions,
      List<Gift> gifts, {
      List<Giver> givers = const [_household, _leo],
    }) => FamilyView(
      recipients: const [],
      givers: givers,
      occasions: occasions,
      gifts: gifts,
    ).budget();

    test('Tió 88 € sin gasto y Navidad sin presupuesto con 45 € gastados', () {
      final budget = budgetOf(
        [tio, _christmas],
        [_gift('Puzle', 4500, actual: 4500, status: GiftStatus.bought)],
      );
      // Lo de arriba solo cuenta Tió: 88 € puestos, nada gastado, 88 € que
      // quedan; los 45 € de Navidad van aparte.
      expect(budget.hasBudgeted, isTrue);
      expect(budget.budgeted, const BudgetTotals(budgetCents: 8800));
      expect(budget.budgeted.leftCents, 8800);
      expect(budget.budgeted.leftIfBoughtCents, 8800);
      expect(budget.spentOutsideBudgetCents, 4500);
      // El total de la casa no cambia: sigue con todo lo que paga la casa.
      expect(budget.total.budgetCents, 8800);
      expect(budget.total.spentCents, 4500);
      expect(budget.total.leftCents, 4300);
    });

    test(
      'lo pendiente de una ocasión sin presupuesto no resta de lo que queda',
      () {
        final budget = budgetOf(
          [tio, _christmas],
          [
            _gift('Cometa', 3000, occasion: 'tio'),
            _gift('Puzle', 9000, occasion: 'navidad'),
          ],
        );
        expect(budget.budgeted.pendingCents, 3000);
        expect(budget.budgeted.leftIfBoughtCents, 5800);
        expect(budget.total.pendingCents, 12000);
        expect(budget.spentOutsideBudgetCents, 0);
      },
    );

    test('0 € es un presupuesto válido', () {
      final budget = budgetOf(
        [tio.copyWith(budgetCents: 0), _christmas],
        [_gift('Puzle', 4500, actual: 4500, status: GiftStatus.bought)],
      );
      expect(budget.hasBudgeted, isTrue);
      expect(budget.budgeted, const BudgetTotals(budgetCents: 0));
      expect(budget.spentOutsideBudgetCents, 4500);
    });

    test('una ocasión archivada con presupuesto no cuenta', () {
      final budget = budgetOf(
        [
          const Occasion(
            id: 'tio',
            kind: OccasionKind.custom,
            rawKind: 'custom',
            name: 'Tió',
            month: 12,
            day: 24,
            recurring: true,
            archived: true,
            budgetCents: 8800,
          ),
          _christmas,
        ],
        [
          _gift(
            'Cometa',
            3000,
            actual: 2500,
            occasion: 'tio',
            status: GiftStatus.bought,
          ),
        ],
      );
      // Fuera de lo de arriba, de «Además» y de las personas; su fila entera.
      expect(budget.hasBudgeted, isFalse);
      expect(budget.budgeted, const BudgetTotals());
      expect(budget.spentOutsideBudgetCents, 0);
      expect(budget.total, const BudgetTotals());
      expect(budget.ofRecipient('aritz'), const BudgetTotals());
      expect(
        budget.ofOccasion('tio'),
        const BudgetTotals(
          budgetCents: 8800,
          plannedCents: 3000,
          spentCents: 2500,
        ),
      );
    });

    test('Navidad 100 € con 120 € gastados, archivada: todo fuera', () {
      final budget = budgetOf(
        [_archive(_christmas.copyWith(budgetCents: 10000)), _kings],
        [
          _gift('Puzle', 12000, actual: 12000, status: GiftStatus.bought),
          _gift('Cometa', 3000, occasion: 'reyes'),
          _gift('Libro', 4000, occasion: null),
        ],
      );
      // Arriba, solo Reyes (200 €, nada gastado); «Además», solo lo de sin
      // ocasión (nada gastado); personas, sin lo de Navidad.
      expect(budget.hasBudgeted, isTrue);
      expect(
        budget.budgeted,
        const BudgetTotals(
          budgetCents: 20000,
          plannedCents: 3000,
          pendingCents: 3000,
        ),
      );
      expect(budget.spentOutsideBudgetCents, 0);
      expect(
        budget.ofRecipient('aritz'),
        const BudgetTotals(plannedCents: 7000),
      );
      expect(budget.total.plannedCents, 7000);
      // La fila de Navidad: presupuesto, gastado y pasado, con la marca.
      final christmas = budget.ofOccasion('navidad');
      expect(christmas.budgetCents, 10000);
      expect(christmas.spentCents, 12000);
      expect(christmas.isOver, isTrue);
      expect(budget.isArchivedOccasion('navidad'), isTrue);
    });

    test('«Además» suma lo de activas sin presupuesto y sin ocasión', () {
      final budget = budgetOf(
        [tio, _christmas, _archive(_kings)],
        [
          _gift('Puzle', 4500, actual: 4500, status: GiftStatus.bought),
          _gift(
            'Libro',
            900,
            actual: 900,
            occasion: null,
            status: GiftStatus.bought,
          ),
          _gift(
            'Cometa',
            7000,
            actual: 7000,
            occasion: 'reyes',
            status: GiftStatus.bought,
          ),
        ],
      );
      expect(budget.spentOutsideBudgetCents, 5400);
      // Por persona = arriba + «Además».
      expect(
        budget.ofRecipient('aritz').spentCents,
        budget.budgeted.spentCents + budget.spentOutsideBudgetCents,
      );
      expect(budget.total.spentCents, 5400);
    });

    test(
      'lo pendiente de una archivada no cuenta en previsto ni pendiente',
      () {
        final budget = budgetOf(
          [_archive(_christmas), tio],
          [_gift('Puzle', 4500), _gift('Cometa', 1000, occasion: 'tio')],
        );
        expect(budget.total.plannedCents, 1000);
        expect(budget.total.pendingCents, 1000);
        expect(budget.ofRecipient('aritz').plannedCents, 1000);
        expect(budget.ofOccasion('navidad').pendingCents, 4500);
      },
    );

    test('con todas las archivadas la tarjeta queda en «Sin presupuesto» con '
        'el gasto de activas y «Sin ocasión»', () {
      final budget = budgetOf(
        [_archive(tio), _christmas],
        [
          _gift(
            'Cometa',
            3000,
            actual: 3000,
            occasion: 'tio',
            status: GiftStatus.bought,
          ),
          _gift('Puzle', 4500, actual: 4500, status: GiftStatus.bought),
          _gift(
            'Libro',
            900,
            actual: 900,
            occasion: null,
            status: GiftStatus.bought,
          ),
        ],
      );
      expect(budget.hasBudgeted, isFalse);
      expect(budget.budgeted.budgetCents, isNull);
      expect(budget.total.budgetCents, isNull);
      expect(budget.total.spentCents, 5400);
      expect(budget.ofRecipient('aritz').spentCents, 5400);
    });

    test('un regalo sin ocasión, o de una ocasión borrada, va aparte', () {
      final budget = budgetOf(
        [tio],
        [
          _gift(
            'Libro',
            1500,
            actual: 1500,
            occasion: null,
            status: GiftStatus.bought,
          ),
          _gift(
            'Taza',
            900,
            actual: 900,
            occasion: 'borrada',
            status: GiftStatus.bought,
          ),
          _gift(
            'Cometa',
            3000,
            actual: 2000,
            occasion: 'tio',
            status: GiftStatus.bought,
          ),
        ],
      );
      expect(budget.budgeted.spentCents, 2000);
      expect(budget.spentOutsideBudgetCents, 2400);
      expect(budget.total.spentCents, 4400);
    });

    test('lo que no paga la casa no cuenta en ninguna de las dos', () {
      final budget = budgetOf(
        [tio],
        [
          _gift(
            'Cometa',
            3000,
            actual: 2000,
            occasion: 'tio',
            giver: 'leo',
            status: GiftStatus.bought,
          ),
        ],
      );
      expect(budget.budgeted, const BudgetTotals(budgetCents: 8800));
      expect(budget.spentOutsideBudgetCents, 0);
    });

    test('sin ninguna ocasión con presupuesto no hay cifras de arriba', () {
      final budget = budgetOf(
        [_christmas],
        [_gift('Puzle', 4500, actual: 4500, status: GiftStatus.bought)],
      );
      expect(budget.hasBudgeted, isFalse);
      expect(budget.budgeted, const BudgetTotals());
      expect(budget.budgeted.budgetCents, isNull);
      expect(budget.spentOutsideBudgetCents, 4500);
      expect(budget.total.spentCents, 4500);
    });
  });
}
