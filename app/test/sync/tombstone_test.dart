import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';

/// Lápidas: eliminar vacía el contenido, la lápida gana a cualquier edición
/// (anterior, concurrente o posterior) y la fusión sigue siendo un semirretículo.
void main() {
  // Relojes en el futuro lejano: el orden de las marcas lo dan los
  // milisegundos que pone cada prueba y no la hora real.
  const future = 4102444800000;
  HlcClock clockOf(String node, int millis) => HlcClock(
    node: node,
    last: Hlc(millis: future + millis, counter: 0, node: node),
  );

  FamilyDoc withGift(HlcClock clock) => FamilyDoc.empty('list-1')
      .set(clock, Collections.gifts, 'g1', {
        'recipientId': 'aritz',
        'title': 'Bicicleta',
        'note': 'La roja',
        'url': 'https://example.com/bici',
        'plannedCents': 12000,
        'status': 'idea',
        'surprise': false,
        'year': 2026,
      });

  SyncRecord gift(FamilyDoc doc) => doc.record(Collections.gifts, 'g1')!;

  group('eliminar', () {
    test('deja la lápida sin nombre, notas, precio ni enlaces', () {
      final created = withGift(clockOf('aaaa', 1000));
      final deleted = created.delete(
        clockOf('aaaa', 5000),
        Collections.gifts,
        'g1',
      );
      final record = gift(deleted);
      expect(record.isDeleted, isTrue);
      expect(record.hasTombstoneContent, isFalse);
      for (final name in ['title', 'note', 'url', 'plannedCents', 'status']) {
        expect(record.field(name), isNotNull, reason: name);
        expect(record[name], isNull, reason: name);
      }
      expect(deleted.canonicalJson(), isNot(contains('Bicicleta')));
      expect(deleted.canonicalJson(), isNot(contains('example.com')));
      expect(Gift.fromRecord(record), isNull);
    });

    test('los campos vaciados llevan una marca nueva, igual que deleted', () {
      final created = withGift(clockOf('aaaa', 1000));
      final deleted = created.delete(
        clockOf('aaaa', 5000),
        Collections.gifts,
        'g1',
      );
      final record = gift(deleted);
      final stamp = record.field('deleted')!.stamp;
      expect(stamp.millis, future + 5000);
      for (final entry in record.fields.entries) {
        expect(entry.value.stamp, stamp, reason: entry.key);
      }
    });

    test(
      'es idempotente: eliminar dos veces o volver a fusionar no cambia',
      () {
        final deleted = withGift(clockOf('aaaa', 1000))
            .delete(clockOf('aaaa', 5000), Collections.gifts, 'g1');
        expect(deleted.merge(deleted).canonicalJson(), deleted.canonicalJson());
        expect(deleted.scrubbed(), same(deleted));
        final again = deleted.delete(
          clockOf('aaaa', 9000),
          Collections.gifts,
          'g1',
        );
        expect(
          again.record(Collections.gifts, 'g1')!.hasTombstoneContent,
          false,
        );
        expect(gift(again).isDeleted, isTrue);
      },
    );

    test('eliminar algo que no existe deja solo la lápida', () {
      final deleted = FamilyDoc.empty('list-1')
          .delete(clockOf('aaaa', 5000), Collections.gifts, 'x');
      final record = deleted.record(Collections.gifts, 'x')!;
      expect(record.isDeleted, isTrue);
      expect(record.fields.keys, ['deleted']);
    });

    test('escribir en una lápida no devuelve el contenido', () {
      final deleted = withGift(clockOf('aaaa', 1000))
          .delete(clockOf('aaaa', 5000), Collections.gifts, 'g1');
      final edited = deleted.set(
        clockOf('aaaa', 9000),
        Collections.gifts,
        'g1',
        {'title': 'Otra cosa'},
      );
      expect(gift(edited).isDeleted, isTrue);
      expect(gift(edited)['title'], isNull);
      expect(edited.canonicalJson(), isNot(contains('Otra cosa')));
    });
  });

  group('fusión: eliminar frente a editar', () {
    late FamilyDoc base;
    setUp(() => base = withGift(clockOf('aaaa', 1000)));

    FamilyDoc deletedOn(FamilyDoc doc, int millis) =>
        doc.delete(clockOf('aaaa', millis), Collections.gifts, 'g1');

    FamilyDoc editedOn(
      FamilyDoc doc,
      int millis, [
      String title = 'Patinete',
    ]) => doc.set(clockOf('bbbb', millis), Collections.gifts, 'g1', {
      'title': title,
      'note': 'Con casco',
    });

    void expectGone(FamilyDoc doc) {
      final record = gift(doc);
      expect(record.isDeleted, isTrue);
      expect(Gift.fromRecord(record), isNull);
      expect(record.hasTombstoneContent, isFalse);
      expect(doc.canonicalJson(), isNot(contains('Patinete')));
      expect(doc.canonicalJson(), isNot(contains('Con casco')));
      expect(doc.canonicalJson(), isNot(contains('Bicicleta')));
    }

    test('edición concurrente con marca anterior: sigue eliminado', () {
      final deleted = deletedOn(base, 5000);
      final edited = editedOn(base, 3000);
      expectGone(deleted.merge(edited));
      expectGone(edited.merge(deleted));
    });

    test('edición concurrente con marca POSTERIOR: la lápida manda', () {
      // El otro móvil no había recibido el borrado y edita más tarde: su
      // título gana por marca en ese campo, pero la lápida lo vacía.
      final deleted = deletedOn(base, 5000);
      final edited = editedOn(base, 9000);
      final a = deleted.merge(edited);
      final b = edited.merge(deleted);
      expectGone(a);
      expectGone(b);
      expect(a.canonicalJson(), b.canonicalJson());
    });

    test('una edición que llega después de fusionar tampoco lo resucita', () {
      final merged = deletedOn(base, 5000).merge(editedOn(base, 9000));
      final late = editedOn(base, 20000, 'Patinete');
      expectGone(merged.merge(late));
      expectGone(late.merge(merged));
    });

    test('un deleted=false más reciente no deshace el borrado', () {
      final deleted = deletedOn(base, 5000);
      final undone = base.set(
        clockOf('cccc', 99000),
        Collections.gifts,
        'g1',
        const {'deleted': false},
      );
      expect(gift(undone).isDeleted, isFalse);
      expectGone(deleted.merge(undone));
      expectGone(undone.merge(deleted));
    });

    test(
      'set no quita una lápida: deleted=false escrito sobre ella se ignora',
      () {
        final deleted = deletedOn(base, 5000);
        final undone = deleted.set(
          clockOf('cccc', 99000),
          Collections.gifts,
          'g1',
          const {'deleted': false, 'title': 'Otra vez'},
        );
        expectGone(undone);
        expect(undone.canonicalJson(), isNot(contains('Otra vez')));
        final changed = deleted.setChanged(
          clockOf('cccc', 99500),
          Collections.gifts,
          'g1',
          const {'deleted': false},
        );
        expectGone(changed);
      },
    );

    test('un móvil antiguo con requestedBy o true posteriores: se vuelve a '
        'borrar con marca estrictamente mayor', () {
      final deleted = deletedOn(base, 5000);
      // El móvil antiguo escribe, sin conexión y tras el borrado, valores
      // cuyo texto canónico ordena por encima de «null».
      final legacy = FamilyDoc.fromJson({
        'v': kFamilyDocVersion,
        'listId': 'list-1',
        'c': {
          Collections.gifts: {
            'g1': {
              'surprise': [
                true,
                Hlc(millis: future + 9000, counter: 0, node: 'bbbb').pack(),
              ],
              'requestedBy': [
                {'name': 'Abuela'},
                Hlc(millis: future + 9000, counter: 0, node: 'bbbb').pack(),
              ],
            },
          },
        },
      });
      final merged = deleted.merge(legacy);
      final stale = deleted.staleTombstonesIn(legacy, merged);
      expect(stale, [(Collections.gifts, 'g1')]);
      final again = merged.delete(
        clockOf('aaaa', 20000),
        Collections.gifts,
        'g1',
      );
      final record = gift(again);
      for (final name in ['surprise', 'requestedBy']) {
        expect(
          record.field(name)!.stamp >
              legacy.record('gifts', 'g1')!.field(name)!.stamp,
          isTrue,
          reason: name,
        );
        expect(record[name], isNull);
      }
      // Ya no queda nada que el otro documento pueda traer de vuelta.
      expect(again.staleTombstonesIn(legacy, again.merge(legacy)), isEmpty);
      expectGone(again.merge(legacy));
    });

    test(
      'un documento ajeno más viejo que la lápida no la vuelve a borrar',
      () {
        final deleted = deletedOn(base, 5000);
        expect(deleted.staleTombstonesIn(base, deleted.merge(base)), isEmpty);
      },
    );

    test('el registro eliminado no aparece en las vistas', () {
      final merged = deletedOn(base, 5000).merge(editedOn(base, 9000));
      expect(FamilyView.fromDoc(merged).allGifts, isEmpty);
    });

    test('propiedades de semirretículo con borrados y ediciones al azar', () {
      final random = Random(7);
      const ids = ['r1', 'r2', 'r3'];
      for (var round = 0; round < 300; round++) {
        final clocks = [
          HlcClock(node: 'aaaa'),
          HlcClock(node: 'bbbb'),
          HlcClock(node: 'cccc'),
        ];
        var docs = List.generate(3, (_) => FamilyDoc.empty('list-1'));
        for (var op = 0; op < 20; op++) {
          final who = random.nextInt(3);
          final id = ids[random.nextInt(ids.length)];
          docs[who] = switch (random.nextInt(4)) {
            0 => docs[who].delete(clocks[who], Collections.recipients, id),
            1 => docs[who].set(clocks[who], Collections.recipients, id, {
              'name': 'N${random.nextInt(3)}',
              'archived': random.nextBool(),
            }),
            2 => docs[who].set(clocks[who], Collections.recipients, id, {
              'deleted': random.nextBool(),
            }),
            _ => docs[who].merge(docs[random.nextInt(3)]),
          };
          if (random.nextInt(3) == 0) {
            final other = docs[random.nextInt(3)].maxStamp;
            if (other != null) {
              clocks[who].receive(other);
            }
          }
        }
        final [a, b, c] = docs;
        String j(FamilyDoc d) => d.canonicalJson();
        expect(j(a.merge(b)), j(b.merge(a)), reason: 'conmutativa $round');
        expect(
          j(a.merge(b).merge(c)),
          j(a.merge(b.merge(c))),
          reason: 'asociativa $round',
        );
        expect(j(a.merge(a)), j(a.scrubbed()), reason: 'idempotente $round');
        expect(
          j(a.merge(a.merge(b))),
          j(a.merge(b)),
          reason: 'absorbente $round',
        );
        // Nada eliminado conserva contenido tras una fusión.
        for (final record
            in a
                .merge(b)
                .merge(c)
                .collections[Collections.recipients]!
                .values) {
          if (record.isDeleted) {
            expect(record.hasTombstoneContent, isFalse, reason: 'vacía $round');
          }
        }
      }
    });
  });

  group('documento antiguo', () {
    String stampOf(int millis) =>
        Hlc(millis: millis, counter: 0, node: 'aaaa').pack();

    // Lo que escribía la versión anterior: deleted=true y el resto intacto.
    FamilyDoc legacyDoc() => FamilyDoc.fromJson({
      'v': kFamilyDocVersion,
      'listId': 'list-1',
      'c': {
        Collections.gifts: {
          'g1': {
            'title': ['Bicicleta', stampOf(1000)],
            'deleted': [true, stampOf(5000)],
          },
          'g2': {
            'title': ['Vivo', stampOf(6000)],
          },
        },
      },
    });

    test('hasTombstoneContent detecta la lápida con contenido', () {
      expect(gift(legacyDoc()).hasTombstoneContent, isTrue);
      expect(
        legacyDoc().record(Collections.gifts, 'g2')!.hasTombstoneContent,
        isFalse,
      );
    });

    test('scrubbed() la vacía sin tocar marcas ni otros registros', () {
      final raw = legacyDoc();
      final clean = raw.scrubbed();
      expect(gift(clean).hasTombstoneContent, isFalse);
      expect(
        gift(clean).field('title')!.stamp,
        gift(raw).field('title')!.stamp,
      );
      expect(clean.record(Collections.gifts, 'g2')!['title'], 'Vivo');
      expect(clean.scrubbed(), same(clean));
      expect(clean.canonicalJson(), isNot(contains('Bicicleta')));
    });

    test('fusionar un documento antiguo con otro nuevo vacía la lápida', () {
      final raw = legacyDoc();
      // Registro que solo existe en el antiguo.
      final intoEmpty = FamilyDoc.empty('list-1').merge(raw);
      expect(gift(intoEmpty).hasTombstoneContent, isFalse);
      expect(intoEmpty.canonicalJson(), isNot(contains('Bicicleta')));
      // Registro que existe en los dos.
      final other = withGift(clockOf('bbbb', 2000));
      final both = other.merge(raw);
      expect(gift(both).isDeleted, isTrue);
      expect(both.canonicalJson(), isNot(contains('Bicicleta')));
      expect(raw.merge(other).canonicalJson(), both.canonicalJson());
    });

    test('un móvil antiguo que edita tras el borrado no lo resucita', () {
      // El móvil antiguo escribe el título con una marca posterior al borrado.
      final legacyEdit = FamilyDoc.fromJson({
        'v': kFamilyDocVersion,
        'listId': 'list-1',
        'c': {
          Collections.gifts: {
            'g1': {
              'title': ['Patinete', stampOf(9000)],
            },
          },
        },
      });
      final merged = legacyDoc().merge(legacyEdit);
      expect(gift(merged).isDeleted, isTrue);
      expect(merged.canonicalJson(), isNot(contains('Patinete')));
    });

    test('la versión del documento no cambia', () {
      expect(legacyDoc().toJson()['v'], 1);
      expect(kFamilyDocVersion, 1);
    });
  });
}
