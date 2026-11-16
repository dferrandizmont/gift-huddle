import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:regalos/core/format/dates.dart';
import 'package:regalos/core/format/money.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/gift_logic.dart';

Gift gift(
  String id, {
  String title = 'Bloques',
  String recipient = 'aritz',
  String? giver,
  String? occasion,
  GiftStatus status = GiftStatus.idea,
}) => Gift(
  id: id,
  recipientId: recipient,
  title: title,
  giverId: giver,
  occasionId: occasion,
  status: status,
  rawStatus: status.name,
  surprise: false,
  year: 2026,
);

Occasion occasion(
  String id,
  int month,
  int day, {
  bool recurring = true,
  int? year,
}) => Occasion(
  id: id,
  kind: OccasionKind.custom,
  rawKind: 'custom',
  name: id,
  month: month,
  day: day,
  year: year,
  recurring: recurring,
  archived: false,
);

void main() {
  setUpAll(() => initializeDateFormatting());

  group('importes', () {
    test('se leen con coma, con punto, con el euro y con millares', () {
      expect(parseCents('12'), 1200);
      expect(parseCents('12,5'), 1250);
      expect(parseCents('12,50'), 1250);
      expect(parseCents('12.50'), 1250);
      expect(parseCents(' 49,99 € '), 4999);
      expect(parseCents('1.234,56'), 123456);
      expect(parseCents('1,234.56'), 123456);
      expect(parseCents('1.234'), 123400);
      expect(parseCents('0,05'), 5);
      expect(parseCents(',5'), 50);
      expect(parseCents('12,345'), 1234500);
    });

    test('lo que no es un importe da null', () {
      for (final bad in [
        '',
        'abc',
        '-3',
        '1,2,3',
        '12,345,6',
        '12 euros',
        '12,',
        '.',
      ]) {
        expect(parseCents(bad), isNull, reason: bad);
      }
      expect(parseCents('99999999999'), isNull);
    });

    test('se escriben sin decimales si son redondos', () {
      expect(formatCents(3100, 'es'), '31 €');
      expect(formatCents(7294, 'es'), '72,94 €');
      expect(formatCents(7294, 'en'), '€72.94');
      expect(formatCents(0, 'es'), '0 €');
    });
  });

  group('fechas', () {
    test('día y mes en corto y en largo', () {
      expect(shortDayMonth(12, 24, 'es'), '24 dic');
      expect(longDayMonth(1, 6, 'es'), '6 de enero');
      expect(longDayMonth(2, 29, 'es'), '29 de febrero');
    });

    test('la edad espera al cumpleaños', () {
      const nora = Recipient(
        id: 'n',
        name: 'Nora',
        colorIndex: 0,
        birthMonth: 6,
        birthDay: 12,
        birthYear: 2022,
        archived: false,
      );
      expect(ageOf(nora, DateTime(2026, 6, 11)), 3);
      expect(ageOf(nora, DateTime(2026, 6, 12)), 4);
      expect(ageOf(nora, DateTime(2026, 11, 9)), 4);
      const sin = Recipient(id: 's', name: 'S', colorIndex: 0, archived: false);
      expect(ageOf(sin, DateTime(2026, 6, 12)), isNull);
    });
  });

  group('filtros de regalos', () {
    final idea = gift('1');
    final decided = gift(
      '2',
      status: GiftStatus.decided,
      giver: 'us',
      occasion: 'kings',
    );
    final bought = gift('3', status: GiftStatus.bought, giver: 'us');
    final arrived = gift('4', status: GiftStatus.arrived, occasion: 'kings');
    final all = [idea, decided, bought, arrived];

    List<String> ids(GiftFilter f) => [
      for (final g in all)
        if (f.matches(g)) g.id,
    ];

    test('sin filtros pasan todos', () {
      expect(ids(const GiftFilter()), ['1', '2', '3', '4']);
      expect(const GiftFilter().isActive, isFalse);
    });

    test('falta comprar es idea o decidido; falta envolver, lo que llegó', () {
      expect(ids(const GiftFilter(needsBuy: true)), ['1', '2']);
      expect(ids(const GiftFilter(needsWrap: true)), ['4']);
      expect(ids(const GiftFilter(needsBuy: true, needsWrap: true)), isEmpty);
    });

    test('por ocasión, por quien regala y sin asignar', () {
      expect(ids(const GiftFilter(occasionId: 'kings')), ['2', '4']);
      expect(ids(const GiftFilter(occasionId: GiftFilter.kNoOccasion)), [
        '1',
        '3',
      ]);
      expect(ids(const GiftFilter(giverId: 'us')), ['2', '3']);
      expect(ids(const GiftFilter(giverId: kUnassignedGiver)), ['1', '4']);
      expect(ids(const GiftFilter(status: GiftStatus.bought)), ['3']);
      expect(ids(const GiftFilter(occasionId: 'kings', giverId: 'us')), ['2']);
    });

    test('copyWith pone y quita filtros, y los cuenta', () {
      var f = const GiftFilter().copyWith(occasionId: 'a', needsBuy: true);
      expect(f.count, 2);
      f = f.copyWith(clearOccasion: true);
      expect(f.occasionId, isNull);
      expect(f.count, 1);
    });
  });

  group('duplicados al guardar', () {
    const aritz = Recipient(
      id: 'aritz',
      name: 'Aritz',
      colorIndex: 0,
      archived: false,
    );
    const nora = Recipient(
      id: 'nora',
      name: 'Nora',
      colorIndex: 1,
      archived: false,
    );
    FamilyView view(List<Gift> gifts) => FamilyView(
      recipients: const [aritz, nora],
      givers: const [],
      occasions: const [],
      gifts: gifts,
    );

    test('encuentra un regalo casi igual de la misma persona', () {
      final v = view([gift('a', title: 'Puzle de 48 piezas')]);
      final pairs = duplicatesOf(v, gift('b', title: 'puzle 48 piezas'));
      expect(pairs, hasLength(1));
    });

    test('no cuenta a otras personas, ni a sí mismo, ni lo distinto', () {
      final v = view([
        gift('a', title: 'Puzle de 48 piezas', recipient: 'nora'),
        gift('b', title: 'Patinete'),
      ]);
      expect(duplicatesOf(v, gift('c', title: 'Puzle de 48 piezas')), isEmpty);
      expect(duplicatesOf(v, gift('b', title: 'Patinete')), isEmpty);
      expect(duplicatesOf(v, gift('d', title: 'Libro de cuentos')), isEmpty);
    });

    test(
      'un regalo que ya está y se edita no se compara con su versión vieja',
      () {
        final v = view([gift('a', title: 'Puzle de 48 piezas')]);
        expect(
          duplicatesOf(v, gift('a', title: 'Puzle de 48 piezas XL')),
          isEmpty,
        );
      },
    );
  });

  group('ocasiones por fecha', () {
    final now = DateTime(2026, 11, 9);

    test('van por la próxima fecha y las pasadas al final', () {
      final ordered = occasionsByNextDate([
        occasion('reyes', 1, 6),
        occasion('tio', 12, 24),
        occasion('comunion', 5, 20, recurring: false, year: 2026),
        occasion('cumple', 11, 9),
      ], now);
      expect(
        [for (final o in ordered) o.id],
        ['cumple', 'tio', 'reyes', 'comunion'],
      );
    });

    test('los días que faltan', () {
      expect(daysUntil(occasion('reyes', 1, 6), now), 58);
      expect(daysUntil(occasion('hoy', 11, 9), now), 0);
      expect(
        daysUntil(occasion('pasada', 3, 1, recurring: false, year: 2026), now),
        isNull,
      );
    });
  });

  test('los totales suman lo previsto y lo gastado', () {
    final totals = totalsOf([
      Gift(
        id: 'a',
        recipientId: 'p',
        title: 'A',
        status: GiftStatus.bought,
        rawStatus: 'bought',
        plannedCents: 1000,
        actualCents: 900,
        surprise: false,
        year: 2026,
      ),
      gift('b'),
    ]);
    expect(totals.plannedCents, 1000);
    expect(totals.spentCents, 900);
  });
}
