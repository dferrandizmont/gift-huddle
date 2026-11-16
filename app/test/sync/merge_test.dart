import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';

/// A clock the test moves by hand.
class StepClock {
  StepClock(this._now);

  DateTime _now;

  /// The current time.
  DateTime call() => _now;

  /// Moves the clock forward.
  void advance(Duration duration) => _now = _now.add(duration);

  /// Sets the clock to an exact time.
  void setTo(DateTime time) => _now = time;
}

void main() {
  final base = DateTime.utc(2026, 11, 9, 10);

  group('propiedades de la fusión', () {
    test('conmutativa, asociativa, idempotente y absorbente', () {
      final random = Random(42);
      final source = StepClock(base);
      const ids = <String>['g1', 'g2', 'g3', 'g4'];
      const titles = <String>['Bicicleta', 'Puzle', 'Coche', 'Libro'];

      withClock(Clock(source.call), () {
        for (var iteration = 0; iteration < 300; iteration++) {
          final clocks = <HlcClock>[
            HlcClock(node: 'aaaa'),
            HlcClock(node: 'bbbb'),
            HlcClock(node: 'cccc'),
          ];
          final docs = <FamilyDoc>[
            FamilyDoc.empty('list-1'),
            FamilyDoc.empty('list-1'),
            FamilyDoc.empty('list-1'),
          ];

          for (var operation = 0; operation < 18; operation++) {
            final which = random.nextInt(3);
            final id = ids[random.nextInt(ids.length)];
            if (random.nextBool()) {
              docs[which] = docs[which].delete(clocks[which], 'gifts', id);
            } else {
              docs[which] = docs[which].set(clocks[which], 'gifts', id, {
                'title': titles[random.nextInt(titles.length)],
                'status': random.nextBool() ? 'idea' : 'bought',
                'plannedCents': random.nextInt(20000),
              });
            }
            if (random.nextBool()) {
              source.advance(Duration(milliseconds: random.nextInt(3)));
            }
            // De vez en cuando un móvil recibe el documento de otro: su
            // reloj salta hasta la marca más nueva que ha visto.
            if (random.nextInt(4) == 0) {
              final other = random.nextInt(3);
              final stamp = docs[other].maxStamp;
              if (stamp != null) {
                clocks[which].receive(stamp);
              }
            }
          }

          final a = docs[0];
          final b = docs[1];
          final c = docs[2];

          expect(
            a.merge(b).canonicalJson(),
            equals(b.merge(a).canonicalJson()),
            reason: 'conmutativa en la vuelta $iteration',
          );
          expect(
            a.merge(b).merge(c).canonicalJson(),
            equals(a.merge(b.merge(c)).canonicalJson()),
            reason: 'asociativa en la vuelta $iteration',
          );
          expect(
            a.merge(a).canonicalJson(),
            equals(a.canonicalJson()),
            reason: 'idempotente en la vuelta $iteration',
          );
          expect(
            a.merge(a.merge(b)).canonicalJson(),
            equals(a.merge(b).canonicalJson()),
            reason: 'absorbente en la vuelta $iteration',
          );
        }
      });
    });

    test('con la misma marca gana el valor más grande', () {
      final stamp = Hlc(millis: 1000, counter: 0, node: 'aaaa');
      final one = FamilyDoc(
        listId: 'list-1',
        collections: <String, Map<String, SyncRecord>>{
          'gifts': <String, SyncRecord>{
            'g1': SyncRecord(
              id: 'g1',
              fields: <String, FieldValue>{
                'title': FieldValue(value: 'aaa', stamp: stamp),
              },
            ),
          },
        },
      );
      final other = FamilyDoc(
        listId: 'list-1',
        collections: <String, Map<String, SyncRecord>>{
          'gifts': <String, SyncRecord>{
            'g1': SyncRecord(
              id: 'g1',
              fields: <String, FieldValue>{
                'title': FieldValue(value: 'zzz', stamp: stamp),
              },
            ),
          },
        },
      );
      expect(one.merge(other).record('gifts', 'g1')!['title'], equals('zzz'));
      expect(other.merge(one).record('gifts', 'g1')!['title'], equals('zzz'));
    });
  });

  group('casos de la especificación', () {
    test('dos móviles editan regalos distintos y los dos están', () {
      final source = StepClock(base);
      final clockA = HlcClock(node: 'aaaa');
      final clockB = HlcClock(node: 'bbbb');
      withClock(Clock(source.call), () {
        var docA = FamilyDoc.empty('list-1');
        var docB = FamilyDoc.empty('list-1');
        docA = docA.set(clockA, 'gifts', 'g1', {'title': 'Bicicleta'});
        source.advance(const Duration(seconds: 1));
        docB = docB.set(clockB, 'gifts', 'g2', {'title': 'Puzle'});

        final merged = docA.merge(docB);
        expect(merged.record('gifts', 'g1')!['title'], equals('Bicicleta'));
        expect(merged.record('gifts', 'g2')!['title'], equals('Puzle'));
        expect(
          merged.merge(docA).canonicalJson(),
          equals(merged.canonicalJson()),
        );
      });
    });

    test('los dos editan el mismo regalo en campos distintos', () {
      final source = StepClock(base);
      final clockA = HlcClock(node: 'aaaa');
      final clockB = HlcClock(node: 'bbbb');
      withClock(Clock(source.call), () {
        var docA = FamilyDoc.empty('list-1');
        var docB = FamilyDoc.empty('list-1');
        docA = docA.set(clockA, 'gifts', 'g1', {
          'title': 'Bicicleta',
          'status': 'idea',
        });
        source.advance(const Duration(seconds: 1));
        docB = docB.set(clockB, 'gifts', 'g1', {'status': 'bought'});

        final merged = docA.merge(docB);
        final gift = merged.record('gifts', 'g1')!;
        expect(gift['title'], equals('Bicicleta'));
        expect(gift['status'], equals('bought'));
      });
    });

    test('los dos cambian el mismo campo y gana el posterior', () {
      final source = StepClock(base);
      final clockA = HlcClock(node: 'aaaa');
      final clockB = HlcClock(node: 'bbbb');
      withClock(Clock(source.call), () {
        var docA = FamilyDoc.empty('list-1');
        var docB = FamilyDoc.empty('list-1');
        docA = docA.set(clockA, 'gifts', 'g1', {'title': 'Bicicleta'});
        source.advance(const Duration(seconds: 1));
        docB = docB.set(clockB, 'gifts', 'g1', {'title': 'Puzle'});

        final merged = docA.merge(docB);
        expect(merged.record('gifts', 'g1')!['title'], equals('Puzle'));

        final other = docB.merge(docA);
        expect(other.record('gifts', 'g1')!['title'], equals('Puzle'));
      });
    });

    test('uno cambia el estado y el otro el título: se conservan los dos', () {
      final source = StepClock(base);
      final clockA = HlcClock(node: 'aaaa');
      final clockB = HlcClock(node: 'bbbb');
      withClock(Clock(source.call), () {
        var docA = FamilyDoc.empty('list-1');
        var docB = FamilyDoc.empty('list-1');
        docA = docA.set(clockA, 'gifts', 'g1', {
          'title': 'Bicicleta',
          'status': 'idea',
        });
        source.advance(const Duration(seconds: 1));
        docB = docB.set(clockB, 'gifts', 'g1', {
          'title': 'Bicicleta',
          'status': 'idea',
        });
        source.advance(const Duration(seconds: 1));

        // A solo cambia el estado: la marca del título no se mueve.
        docA = docA.setChanged(clockA, 'gifts', 'g1', {
          'title': 'Bicicleta',
          'status': 'bought',
        });
        source.advance(const Duration(seconds: 1));

        // B solo cambia el título: la marca del estado no se mueve.
        docB = docB.setChanged(clockB, 'gifts', 'g1', {
          'title': 'Puzle',
          'status': 'idea',
        });

        final merged = docA.merge(docB);
        final gift = merged.record('gifts', 'g1')!;
        expect(gift['status'], equals('bought'));
        expect(gift['title'], equals('Puzle'));
      });
    });

    test('un móvil borra y el otro edita después: sigue borrado', () {
      final source = StepClock(base);
      final clockA = HlcClock(node: 'aaaa');
      final clockB = HlcClock(node: 'bbbb');
      withClock(Clock(source.call), () {
        var docA = FamilyDoc.empty('list-1');
        var docB = FamilyDoc.empty('list-1');
        docA = docA.set(clockA, 'gifts', 'g1', {'title': 'Bicicleta'});
        source.advance(const Duration(seconds: 1));
        docA = docA.delete(clockA, 'gifts', 'g1');
        source.advance(const Duration(seconds: 1));
        docB = docB.set(clockB, 'gifts', 'g1', {'store': 'Toyland'});

        final merged = docA.merge(docB);
        final gift = merged.record('gifts', 'g1')!;
        expect(gift.isDeleted, isTrue);
        // La edición posterior no resucita nada ni deja contenido legible.
        expect(gift['store'], isNull);
        expect(gift['title'], isNull);
        expect(merged.canonicalJson(), isNot(contains('Toyland')));
        expect(merged.canonicalJson(), isNot(contains('Bicicleta')));
        expect(
          docB.merge(docA).canonicalJson(),
          equals(merged.canonicalJson()),
        );
      });
    });

    test('el móvil con la hora adelantada no gana siempre', () {
      final source = StepClock(base);
      final clockA = HlcClock(node: 'aaaa');
      final clockB = HlcClock(node: 'bbbb');
      withClock(Clock(source.call), () {
        source.setTo(base);
        var docA = FamilyDoc.empty('list-1');
        docA = docA.set(clockA, 'gifts', 'g1', {'title': 'De A'});

        source.setTo(base.add(const Duration(hours: 1)));
        var docB = FamilyDoc.empty('list-1');
        docB = docB.set(clockB, 'gifts', 'g1', {'title': 'De B'});

        // Con la hora adelantada, B gana la primera vez.
        expect(
          docA.merge(docB).record('gifts', 'g1')!['title'],
          equals('De B'),
        );

        // A recibe el documento de B: su reloj salta hasta la marca de B.
        source.setTo(base);
        clockA.receive(docB.maxStamp!);
        final docA2 = docA.merge(docB).set(clockA, 'gifts', 'g1', {
          'title': 'De A otra vez',
        });

        // Ahora A vuelve a ganar aunque su reloj siga una hora atrasado.
        expect(
          docA2.merge(docB).record('gifts', 'g1')!['title'],
          equals('De A otra vez'),
        );
        expect(docA2.maxStamp! > docB.maxStamp!, isTrue);
      });
    });

    test('los campos y colecciones desconocidos sobreviven', () {
      final source = StepClock(base);
      final clockA = HlcClock(node: 'aaaa');
      final clockB = HlcClock(node: 'bbbb');
      withClock(Clock(source.call), () {
        var docA = FamilyDoc.empty('list-1');
        var docB = FamilyDoc.empty('list-1');
        docA = docA.set(clockA, 'children', 'c1', {
          'name': 'Aritz',
          'futureField': 'x',
        });
        source.advance(const Duration(seconds: 1));
        docB = docB.set(clockB, 'inventario', 'i1', {'quantity': 3});

        final merged = docA.merge(docB);
        expect(merged.record('children', 'c1')!['futureField'], equals('x'));
        expect(merged.record('inventario', 'i1')!['quantity'], equals(3));

        final read = FamilyDoc.fromJson(merged.toJson());
        expect(read.record('children', 'c1')!['futureField'], equals('x'));
        expect(read.record('inventario', 'i1')!['quantity'], equals(3));
      });
    });
  });
}
