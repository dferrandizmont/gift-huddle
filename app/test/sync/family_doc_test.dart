import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';

/// A value nested [levels] levels deep.
Object? _nested(int levels) {
  Object? value = 'hoja';
  for (var i = 0; i < levels; i++) {
    value = <Object?>[value];
  }
  return value;
}

void main() {
  final base = DateTime.utc(2026, 11, 9, 10);

  HlcClock clockAt(String node) => HlcClock(node: node);

  group('documento', () {
    test('escribe campos y los vuelve a leer', () {
      final clock = clockAt('aaaa');
      var doc = FamilyDoc.empty('list-1');
      doc = doc.set(clock, 'children', 'c1', {
        'name': 'Aritz',
        'colorIndex': 0,
      });
      doc = doc.set(clock, 'gifts', 'g1', {
        'title': 'Puzle de 48 piezas',
        'plannedCents': 1999,
      });

      final child = doc.record('children', 'c1');
      expect(child, isNotNull);
      expect(child!['name'], equals('Aritz'));
      expect(child['colorIndex'], equals(0));
      expect(doc.record('gifts', 'g1')!['plannedCents'], equals(1999));
      expect(doc.record('children', 'c1')!.isDeleted, isFalse);
    });

    test('no toca el documento original', () {
      final clock = clockAt('aaaa');
      final original = FamilyDoc.empty('list-1');
      final changed = original.set(clock, 'children', 'c1', {'name': 'Aritz'});
      expect(original.collections.containsKey('children'), isFalse);
      expect(changed.collections.containsKey('children'), isTrue);
    });

    test('todos los campos de una escritura comparten marca', () {
      final clock = clockAt('aaaa');
      final doc = FamilyDoc.empty('list-1')
          .set(clock, 'children', 'c1', {'name': 'Aritz', 'colorIndex': 1});
      final record = doc.record('children', 'c1')!;
      expect(
        record.field('name')!.stamp,
        equals(record.field('colorIndex')!.stamp),
      );
    });

    test('borrar deja una lápida', () {
      final clock = clockAt('aaaa');
      var doc = FamilyDoc.empty('list-1');
      doc = doc.set(clock, 'gifts', 'g1', {'title': 'Bicicleta'});
      doc = doc.delete(clock, 'gifts', 'g1');
      expect(doc.record('gifts', 'g1')!.isDeleted, isTrue);
      // La lápida no conserva el contenido: el campo sigue, pero vacío.
      expect(doc.record('gifts', 'g1')!['title'], isNull);
      expect(doc.record('gifts', 'g1')!.field('title'), isNotNull);
    });

    test('la marca más nueva dice cuándo se escribió', () {
      final clock = clockAt('aaaa');
      var doc = FamilyDoc.empty('list-1');
      expect(doc.maxStamp, isNull);
      doc = doc.set(clock, 'children', 'c1', {'name': 'Aritz'});
      final first = doc.maxStamp!;
      doc = doc.set(clock, 'children', 'c2', {'name': 'Nora'});
      expect(doc.maxStamp! > first, isTrue);
    });

    test('no se pueden mezclar listas distintas', () {
      final clock = clockAt('aaaa');
      final a = FamilyDoc.empty('list-1')
          .set(clock, 'children', 'c1', {'name': 'Aritz'});
      final b = FamilyDoc.empty('list-2');
      expect(() => a.merge(b), throwsArgumentError);
    });
  });

  group('cambios', () {
    test('guardar un regalo cambiando solo el estado no toca el título', () {
      final clock = clockAt('aaaa');
      var doc = FamilyDoc.empty('list-1');
      doc = doc.set(clock, 'gifts', 'g1', {
        'title': 'Bicicleta',
        'status': 'idea',
      });
      final titleStamp = doc.record('gifts', 'g1')!.field('title')!.stamp;

      doc = doc.setChanged(clock, 'gifts', 'g1', {
        'title': 'Bicicleta',
        'status': 'bought',
      });

      final record = doc.record('gifts', 'g1')!;
      expect(record['status'], equals('bought'));
      expect(record.field('title')!.stamp, equals(titleStamp));
      expect(record.field('status')!.stamp > titleStamp, isTrue);
    });

    test('si nada cambia se devuelve el mismo documento', () {
      final clock = clockAt('aaaa');
      final doc = FamilyDoc.empty('list-1')
          .set(clock, 'gifts', 'g1', {'title': 'Bicicleta'});
      final same = doc.setChanged(clock, 'gifts', 'g1', {'title': 'Bicicleta'});
      expect(identical(same, doc), isTrue);
    });

    test('un campo que no estaba se escribe y uno que estaba se borra', () {
      final clock = clockAt('aaaa');
      var doc = FamilyDoc.empty('list-1');
      doc = doc.set(clock, 'gifts', 'g1', {'title': 'Bicicleta'});
      doc = doc.setChanged(clock, 'gifts', 'g1', {'store': 'Toyland'});
      expect(doc.record('gifts', 'g1')!['store'], equals('Toyland'));

      doc = doc.setChanged(clock, 'gifts', 'g1', {'store': null});
      expect(doc.record('gifts', 'g1')!['store'], isNull);
      expect(doc.record('gifts', 'g1')!.field('store'), isNotNull);
    });

    test('un valor que no es json se rechaza', () {
      final clock = clockAt('aaaa');
      final doc = FamilyDoc.empty('list-1');
      expect(
        () => doc.set(clock, 'gifts', 'g1', {'when': DateTime.utc(2026)}),
        throwsArgumentError,
      );
      expect(
        () => doc.set(clock, 'gifts', 'g1', {'price': double.nan}),
        throwsArgumentError,
      );
      expect(
        () => doc.set(clock, 'gifts', 'g1', {'price': double.infinity}),
        throwsArgumentError,
      );
      expect(
        () => doc.set(clock, 'gifts', 'g1', {
          'tags': <Object?, Object?>{1: 'no es una clave de texto'},
        }),
        throwsArgumentError,
      );
      expect(
        () =>
            doc.setChanged(clock, 'gifts', 'g1', {'when': DateTime.utc(2026)}),
        throwsArgumentError,
      );
    });

    test('un valor demasiado profundo se rechaza', () {
      final clock = clockAt('aaaa');
      final doc = FamilyDoc.empty('list-1');
      expect(
        () => doc.set(clock, 'gifts', 'g1', {'deep': _nested(33)}),
        throwsArgumentError,
      );
      expect(
        () => doc.set(clock, 'gifts', 'g1', {'deep': _nested(32)}),
        returnsNormally,
      );
    });
  });

  group('json', () {
    test('ida y vuelta', () {
      final clock = clockAt('aaaa');
      var doc = FamilyDoc.empty('list-1');
      doc = doc.set(clock, 'children', 'c1', {
        'name': 'Aritz',
        'colorIndex': 2,
        'birthMonth': 6,
        'archived': false,
      });
      doc = doc.set(clock, 'gifts', 'g1', {
        'title': 'Puzle',
        'plannedCents': 1999,
        'tags': ['juego', 'puzle'],
        'store': null,
      });

      final json = doc.toJson();
      expect(json['v'], equals(1));
      expect(json['listId'], equals('list-1'));

      final read = FamilyDoc.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, Object?>,
      );
      expect(read.canonicalJson(), equals(doc.canonicalJson()));
      expect(read.record('children', 'c1')!['name'], equals('Aritz'));
      expect(read.record('gifts', 'g1')!['tags'], equals(['juego', 'puzle']));
      expect(read.record('gifts', 'g1')!['store'], isNull);
    });

    test('el mismo documento da siempre los mismos bytes', () {
      final clock = clockAt('aaaa');
      final one = FamilyDoc.empty('list-1')
          .set(clock, 'children', 'c1', {'name': 'Aritz', 'colorIndex': 0})
          .set(clock, 'gifts', 'g1', {'title': 'Bicicleta'});

      // The same document, with the fields written in another order.
      final record = one.record('children', 'c1')!;
      final other = FamilyDoc(
        listId: 'list-1',
        collections: <String, Map<String, SyncRecord>>{
          'children': <String, SyncRecord>{
            'c1': SyncRecord(
              id: 'c1',
              fields: <String, FieldValue>{
                'colorIndex': record.field('colorIndex')!,
                'name': record.field('name')!,
              },
            ),
          },
          'gifts': one.collections['gifts']!,
        },
      );

      expect(other.canonicalJson(), equals(one.canonicalJson()));
    });

    test('el json sale con las claves ordenadas', () {
      final clock = clockAt('aaaa');
      final doc = FamilyDoc.empty('list-1')
          .set(clock, 'children', 'c1', {'name': 'Aritz'});
      final text = doc.canonicalJson();
      final collectionIndex = text.indexOf('"children"');
      final listIndex = text.indexOf('"listId"');
      final versionIndex = text.indexOf('"v"');
      expect(collectionIndex, greaterThan(-1));
      expect(collectionIndex, lessThan(listIndex));
      expect(listIndex, lessThan(versionIndex));
    });

    test('las estructuras malas se rechazan', () {
      expect(
        () => FamilyDoc.fromJson(const <String, Object?>{}),
        throwsFormatException,
      );
      expect(
        () => FamilyDoc.fromJson(const <String, Object?>{
          'v': 2,
          'listId': 'l',
          'c': <String, Object?>{},
        }),
        throwsFormatException,
      );
      expect(
        () => FamilyDoc.fromJson(const <String, Object?>{
          'v': 1,
          'c': <String, Object?>{},
        }),
        throwsFormatException,
      );
      expect(
        () => FamilyDoc.fromJson(const <String, Object?>{
          'v': 1,
          'listId': '',
          'c': <String, Object?>{},
        }),
        throwsFormatException,
      );
      expect(
        () => FamilyDoc.fromJson(const <String, Object?>{
          'v': 1,
          'listId': 'l',
          'c': 'nope',
        }),
        throwsFormatException,
      );
      expect(
        () => FamilyDoc.fromJson(const <String, Object?>{
          'v': 1,
          'listId': 'l',
          'c': <String, Object?>{
            'gifts': <String, Object?>{
              'g1': <String, Object?>{'title': 'nada'},
            },
          },
        }),
        throwsFormatException,
      );
      expect(
        () => FamilyDoc.fromJson(const <String, Object?>{
          'v': 1,
          'listId': 'l',
          'c': <String, Object?>{
            'gifts': <String, Object?>{
              'g1': <String, Object?>{
                'title': <Object?>['Bicicleta', 'no-es-una-marca'],
              },
            },
          },
        }),
        throwsFormatException,
      );
      expect(
        () => FamilyDoc.fromJson(const <String, Object?>{
          'v': 1,
          'listId': 'l',
          'c': <String, Object?>{
            'gifts': <String, Object?>{
              'g1': <String, Object?>{
                'title': <Object?>['Bicicleta'],
              },
            },
          },
        }),
        throwsFormatException,
      );
    });

    test('los campos y colecciones desconocidos se conservan', () {
      final clock = clockAt('aaaa');
      var doc = FamilyDoc.empty('list-1');
      doc = doc.set(clock, 'children', 'c1', {'name': 'Aritz'});
      doc = doc.set(clock, 'inventario', 'i1', {
        'quantity': 3,
        'note': 'del año pasado',
      });
      doc = doc.set(clock, 'children', 'c1', {'futureField': true});

      final read = FamilyDoc.fromJson(
        jsonDecode(jsonEncode(doc.toJson())) as Map<String, Object?>,
      );
      expect(read.record('inventario', 'i1')!['quantity'], equals(3));
      expect(read.record('children', 'c1')!['futureField'], equals(true));
    });

    test('un campo puesto a null se borra y sigue borrado al releerlo', () {
      final clock = clockAt('aaaa');
      var doc = FamilyDoc.empty('list-1');
      doc = doc.set(clock, 'gifts', 'g1', {
        'title': 'Bicicleta',
        'store': 'Toyland',
      });
      doc = doc.set(clock, 'gifts', 'g1', {'store': null});

      expect(doc.record('gifts', 'g1')!['store'], isNull);

      final read = FamilyDoc.fromJson(
        jsonDecode(jsonEncode(doc.toJson())) as Map<String, Object?>,
      );
      expect(read.record('gifts', 'g1')!['store'], isNull);
      expect(read.record('gifts', 'g1')!.field('store'), isNotNull);
      expect(read.record('gifts', 'g1')!['title'], equals('Bicicleta'));
    });

    test('un valor demasiado profundo no se puede leer', () {
      expect(
        () => FamilyDoc.fromJson(<String, Object?>{
          'v': 1,
          'listId': 'l',
          'c': <String, Object?>{
            'gifts': <String, Object?>{
              'g1': <String, Object?>{'deep': _nested(33)},
            },
          },
        }),
        throwsFormatException,
      );
    });
  });

  group('texto canónico', () {
    test('las claves de un objeto van ordenadas', () {
      expect(
        canonicalJsonOf(<String, Object?>{'b': 1, 'a': 2}),
        equals('{"a":2,"b":1}'),
      );
    });

    test('los valores iguales dan el mismo texto', () {
      expect(
        canonicalJsonOf(<String, Object?>{
          'a': <Object?>[1, 2],
        }),
        equals(
          canonicalJsonOf(<String, Object?>{
            'a': <Object?>[1, 2],
          }),
        ),
      );
    });

    test('un valor que no es json se rechaza', () {
      expect(() => canonicalJsonOf(DateTime.utc(2026)), throwsFormatException);
    });

    test('un valor demasiado profundo no tiene texto canónico', () {
      expect(() => canonicalJsonOf(_nested(33)), throwsFormatException);
      expect(canonicalJsonOf(_nested(32)), isNotEmpty);
    });
  });

  // The clock is only used to keep the tests independent of the real time.
  test('las marcas no dependen del reloj real', () {
    withClock(Clock.fixed(base), () {
      final clock = clockAt('aaaa');
      final stamp = clock.now();
      expect(stamp.millis, equals(base.millisecondsSinceEpoch));
    });
  });
}
