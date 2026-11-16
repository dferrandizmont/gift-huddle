import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/domain/next_occasion.dart';
import 'package:regalos/features/family/domain/occasion_presets.dart';

Occasion occ(
  String id,
  OccasionKind kind,
  int month,
  int day, {
  bool recurring = true,
  int? year,
  bool archived = false,
  String? color,
  String? icon,
  String? rawKind,
  String? name,
}) => Occasion(
  id: id,
  kind: kind,
  rawKind: rawKind ?? kind.name,
  name: name ?? id,
  month: month,
  day: day,
  year: year,
  recurring: recurring,
  archived: archived,
  color: color,
  icon: icon,
);

SyncRecord recordOf(Occasion o) {
  final stamp = Hlc(millis: 1, counter: 0, node: 'aaaa');
  return SyncRecord(
    id: o.id,
    fields: <String, FieldValue>{
      for (final e in o.toFields().entries)
        e.key: FieldValue(value: e.value, stamp: stamp),
    },
  );
}

void main() {
  group('tipos de ocasión', () {
    test('los tipos nuevos se guardan y se leen por su nombre', () {
      const names = [
        'chineseNewYear',
        'wedding',
        'anniversary',
        'santJordi',
        'valentine',
        'baptism',
        'communion',
        'graduation',
      ];
      for (final name in names) {
        final kind = OccasionKind.tryParse(name);
        expect(kind, isNotNull, reason: name);
        expect(kind!.name, name);
        final o = occ('x', kind, 4, 23);
        expect(Occasion.fromRecord(recordOf(o)), equals(o), reason: name);
      }
    });

    test('los tipos de antes siguen con su nombre', () {
      for (final name in ['tio', 'santa', 'kings', 'birthday', 'custom']) {
        expect(OccasionKind.tryParse(name)?.name, name);
      }
    });

    test(
      'un nombre que esta versión no conoce se lee como «Otra» y se guarda',
      () {
        final o = Occasion.fromRecord(
          recordOf(
            occ(
              'x',
              OccasionKind.custom,
              3,
              1,
              rawKind: 'futureKind',
              color: 'sky',
              icon: 'party',
            ),
          ),
        )!;
        expect(o.kind, OccasionKind.custom);
        expect(o.rawKind, 'futureKind');
        expect(o.toFields()['kind'], 'futureKind');
        expect(OccasionKind.fromName('futureKind'), OccasionKind.custom);
      },
    );

    test('el color y el icono de «Otra» viajan en la ocasión', () {
      final o = occ(
        'x',
        OccasionKind.custom,
        5,
        2,
        color: 'teal',
        icon: 'music',
      );
      final read = Occasion.fromRecord(recordOf(o))!;
      expect(read.color, 'teal');
      expect(read.icon, 'music');
      expect(read, equals(o));
    });

    test('una ocasión de antes, sin color ni icono, se lee igual', () {
      final stamp = Hlc(millis: 1, counter: 0, node: 'aaaa');
      final read = Occasion.fromRecord(
        SyncRecord(
          id: 'o1',
          fields: <String, FieldValue>{
            'kind': FieldValue(value: 'santa', stamp: stamp),
            'name': FieldValue(value: 'Navidad', stamp: stamp),
            'month': FieldValue(value: 12, stamp: stamp),
            'day': FieldValue(value: 25, stamp: stamp),
            'recurring': FieldValue(value: true, stamp: stamp),
            'archived': FieldValue(value: false, stamp: stamp),
          },
        ),
      )!;
      expect(read.kind, OccasionKind.santa);
      expect(read.color, isNull);
      expect(read.icon, isNull);
    });

    test('el cumpleaños no se ofrece al crear una ocasión', () {
      expect(kCreatableKinds, isNot(contains(OccasionKind.birthday)));
      expect(kCreatableKinds, contains(OccasionKind.custom));
      expect({
        ...kCreatableKinds,
        OccasionKind.birthday,
      }, equals(OccasionKind.values.toSet()));
    });

    test('cada tipo con fecha fija la trae de serie', () {
      final now = DateTime(2026, 11, 9);
      expect(presetFor(OccasionKind.tio).dateFrom(now), (month: 12, day: 24));
      expect(presetFor(OccasionKind.santa).dateFrom(now), (month: 12, day: 25));
      expect(presetFor(OccasionKind.kings).dateFrom(now), (month: 1, day: 6));
      expect(presetFor(OccasionKind.santJordi).dateFrom(now), (
        month: 4,
        day: 23,
      ));
      expect(presetFor(OccasionKind.valentine).dateFrom(now), (
        month: 2,
        day: 14,
      ));
      // El Año Nuevo Chino es el de la próxima celebración.
      expect(presetFor(OccasionKind.chineseNewYear).dateFrom(now), (
        month: 2,
        day: 6,
      ));
      expect(presetFor(OccasionKind.chineseNewYear).autoDate, isTrue);
      // Estas las elige la persona.
      for (final k in [
        OccasionKind.wedding,
        OccasionKind.anniversary,
        OccasionKind.baptism,
        OccasionKind.communion,
        OccasionKind.graduation,
        OccasionKind.custom,
      ]) {
        expect(presetFor(k).dateFrom(now), isNull, reason: k.name);
      }
      // Una boda no se repite; un aniversario, sí.
      expect(presetFor(OccasionKind.wedding).recurring, isFalse);
      expect(presetFor(OccasionKind.anniversary).recurring, isTrue);
    });
  });

  group('Año Nuevo Chino como ocasión', () {
    final cny = occ('cny', OccasionKind.chineseNewYear, 2, 17);

    test('su fecha sale de la tabla y no del mes y día guardados', () {
      expect(nextDateOf(cny, DateTime(2026, 1, 1)), DateTime(2026, 2, 17));
      expect(nextDateOf(cny, DateTime(2026, 11, 9)), DateTime(2027, 2, 6));
      expect(nextDateOf(cny, DateTime(2027, 2, 6)), DateTime(2027, 2, 6));
      expect(nextDateOf(cny, DateTime(2027, 2, 7)), DateTime(2028, 1, 26));
    });

    test('el día y el mes que se enseñan son los de la próxima vez', () {
      expect(occasionDayMonth(cny, DateTime(2026, 11, 9)), (month: 2, day: 6));
      expect(
        occasionDayMonth(
          occ('t', OccasionKind.tio, 12, 24),
          DateTime(2026, 11, 9),
        ),
        (month: 12, day: 24),
      );
    });

    test('compite con las demás por ser la más cercana', () {
      final list = [
        occ('reyes', OccasionKind.kings, 1, 6),
        cny,
        occ('tio', OccasionKind.tio, 12, 24),
      ];
      final next = nextOccasionFrom(list, DateTime(2026, 11, 9))!;
      expect(next.occasion.id, 'tio');
      final later = upcomingOccasionsFrom(list, DateTime(2027, 1, 7));
      expect(later.first.occasion.id, 'cny');
      expect(later.first.days, 30);
    });
  });

  group('próximas ocasiones', () {
    final now = DateTime(2026, 11, 9);
    final list = [
      occ('reyes', OccasionKind.kings, 1, 6),
      occ('tio', OccasionKind.tio, 12, 24),
      occ('santa', OccasionKind.santa, 12, 25),
      occ('jordi', OccasionKind.santJordi, 4, 23),
      occ('archivada', OccasionKind.valentine, 11, 10, archived: true),
      occ('boda', OccasionKind.wedding, 5, 20, recurring: false, year: 2027),
      occ(
        'comunion',
        OccasionKind.communion,
        5,
        20,
        recurring: false,
        year: 2026,
      ),
    ];

    test(
      'van de la más cercana a la más lejana, sin archivadas ni pasadas',
      () {
        final ids = [
          for (final n in upcomingOccasionsFrom(list, now)) n.occasion.id,
        ];
        expect(ids, ['tio', 'santa', 'reyes', 'jordi', 'boda']);
      },
    );

    test('la primera es la más cercana', () {
      expect(upcomingOccasionsFrom(list, now).first.days, 45);
      expect(nextOccasionFrom(list, now)!.occasion.id, 'tio');
    });

    test('salen también las ocasiones a más de un año', () {
      final far = occ(
        'lejana',
        OccasionKind.custom,
        12,
        14,
        recurring: false,
        year: 2027,
      );
      final ids = [
        for (final n in upcomingOccasionsFrom([...list, far], now))
          n.occasion.id,
      ];
      expect(ids, contains('lejana'));
      expect(
        upcomingOccasionsFrom([...list, far], now).last.occasion.id,
        'lejana',
      );
    });

    test('una ocasión que pasó ayer desaparece hoy', () {
      final reyes = occ('reyes', OccasionKind.kings, 1, 6);
      final onTheDay = upcomingOccasionsFrom([reyes], DateTime(2027, 1, 6));
      expect(onTheDay.single.days, 0);
      // Al día siguiente ya no es la próxima: vuelve a caer dentro de un año,
      // pero sigue apareciendo al final de la lista.
      final other = occ('jordi', OccasionKind.santJordi, 4, 23);
      final next = upcomingOccasionsFrom([reyes, other], DateTime(2027, 1, 7));
      expect(next.map((n) => n.occasion.id), ['jordi', 'reyes']);
      // Una que no se repite desaparece del todo.
      final once = occ(
        'comunion',
        OccasionKind.communion,
        5,
        20,
        recurring: false,
        year: 2026,
      );
      expect(
        upcomingOccasionsFrom([once], DateTime(2026, 5, 20)),
        hasLength(1),
      );
      expect(upcomingOccasionsFrom([once], DateTime(2026, 5, 21)), isEmpty);
    });
  });
}
