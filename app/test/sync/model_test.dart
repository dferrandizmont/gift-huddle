import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';

void main() {
  final base = DateTime.utc(2026, 11, 9, 10);

  /// The list of the product: Aritz and Nora, the house and the grandparents.
  FamilyDoc sampleDoc() => withClock(Clock.fixed(base), () {
    final clock = HlcClock(node: 'aaaa');
    var doc = FamilyDoc.empty('list-1');

    doc = doc.set(clock, Collections.recipients, 'r1', {
      'id': 'r1',
      'name': 'Aritz',
      'colorIndex': 0,
      'relation': 'hijo',
      'birthMonth': 6,
      'birthDay': 10,
      'archived': false,
    });
    doc = doc.set(clock, Collections.recipients, 'r2', {
      'id': 'r2',
      'name': 'Nora',
      'colorIndex': 1,
      'archived': false,
    });

    doc = doc.set(clock, Collections.givers, 'g1', {
      'id': 'g1',
      'name': 'Nosotros',
      'colorIndex': 0,
      'householdPays': true,
      'archived': false,
    });
    doc = doc.set(clock, Collections.givers, 'g2', {
      'id': 'g2',
      'name': 'Yayos de Terrassa',
      'colorIndex': 1,
      'householdPays': false,
      'archived': false,
    });

    doc = doc.set(clock, Collections.occasions, 'o1', {
      'id': 'o1',
      'kind': 'santa',
      'name': 'Navidad',
      'month': 12,
      'day': 25,
      'recurring': true,
      'archived': false,
    });
    doc = doc.set(clock, Collections.occasions, 'o2', {
      'id': 'o2',
      'kind': 'birthday',
      'name': 'Cumpleaños de Aritz',
      'month': 6,
      'day': 10,
      'recurring': true,
      'recipientId': 'r1',
      'archived': false,
    });

    doc = doc.set(clock, Collections.gifts, 'g1', {
      'id': 'g1',
      'recipientId': 'r1',
      'title': 'Bicicleta',
      'giverId': 'g1',
      'occasionId': 'o1',
      'status': 'bought',
      'plannedCents': 12000,
      'actualCents': 7294,
      'requestedBy': <String, Object?>{'recipientId': 'r1'},
      'surprise': false,
      'year': 2026,
    });
    doc = doc.set(clock, Collections.gifts, 'g2', {
      'id': 'g2',
      'recipientId': 'r1',
      'title': 'Puzle de 48 piezas',
      'giverId': 'g1',
      'occasionId': 'o1',
      'status': 'idea',
      'plannedCents': 2500,
      'surprise': true,
      'year': 2026,
    });
    doc = doc.set(clock, Collections.gifts, 'g3', {
      'id': 'g3',
      'recipientId': 'r2',
      'title': 'Camión',
      'giverId': 'g1',
      'occasionId': 'o2',
      'status': 'bought',
      'plannedCents': 3000,
      'surprise': false,
      'year': 2026,
    });
    doc = doc.set(clock, Collections.gifts, 'g4', {
      'id': 'g4',
      'recipientId': 'r1',
      'title': 'Ratón de fibra',
      'giverId': 'g2',
      'occasionId': 'o1',
      'status': 'idea',
      'plannedCents': 50000,
      'surprise': true,
      'year': 2026,
    });

    return doc;
  });

  group('lectura del documento', () {
    test('las listas están ordenadas y sin lo borrado', () {
      final doc = withClock(Clock.fixed(base), () {
        final clock = HlcClock(node: 'aaaa');
        var withLeo = sampleDoc();
        withLeo = withLeo.set(clock, Collections.recipients, 'r3', {
          'id': 'r3',
          'name': 'Leo',
          'colorIndex': 2,
          'archived': false,
        });
        return withLeo.delete(clock, Collections.recipients, 'r2');
      });

      final view = FamilyView.fromDoc(doc);
      expect(
        view.recipients.map((recipient) => recipient.name).toList(),
        equals(<String>['Aritz', 'Leo']),
      );
      expect(
        view.gifts.map((gift) => gift.title).toList(),
        equals(<String>[
          'Bicicleta',
          // «Camión» era de Nora, que está eliminada: su regalo no se ve.
          'Puzle de 48 piezas',
          'Ratón de fibra',
        ]),
      );
      expect(
        view.givers.map((giver) => giver.name).toList(),
        equals(<String>['Nosotros', 'Yayos de Terrassa']),
      );
      expect(
        view.occasions.map((occasion) => occasion.name).toList(),
        equals(<String>['Cumpleaños de Aritz', 'Navidad']),
      );
    });

    test('un estado desconocido se lee como idea sin perder el original', () {
      final stamp = Hlc(millis: 1, counter: 0, node: 'aaaa');
      final record = SyncRecord(
        id: 'g1',
        fields: <String, FieldValue>{
          'recipientId': FieldValue(value: 'r1', stamp: stamp),
          'title': FieldValue(value: 'Bicicleta', stamp: stamp),
          'status': FieldValue(value: 'comprado', stamp: stamp),
          'surprise': FieldValue(value: false, stamp: stamp),
          'year': FieldValue(value: 2026, stamp: stamp),
        },
      );

      final gift = Gift.fromRecord(record);
      expect(gift, isNotNull);
      expect(gift!.status, equals(GiftStatus.idea));
      expect(gift.rawStatus, equals('comprado'));
      expect(record['status'], equals('comprado'));
      expect(gift.toFields()['status'], equals('comprado'));
    });

    test('un registro borrado o incompleto no se lee', () {
      final stamp = Hlc(millis: 1, counter: 0, node: 'aaaa');
      final deleted = SyncRecord(
        id: 'g1',
        fields: <String, FieldValue>{
          'deleted': FieldValue(value: true, stamp: stamp),
          'recipientId': FieldValue(value: 'r1', stamp: stamp),
          'title': FieldValue(value: 'Bicicleta', stamp: stamp),
          'status': FieldValue(value: 'idea', stamp: stamp),
          'surprise': FieldValue(value: false, stamp: stamp),
          'year': FieldValue(value: 2026, stamp: stamp),
        },
      );
      expect(Gift.fromRecord(deleted), isNull);

      final incomplete = SyncRecord(
        id: 'g2',
        fields: <String, FieldValue>{
          'recipientId': FieldValue(value: 'r1', stamp: stamp),
        },
      );
      expect(Gift.fromRecord(incomplete), isNull);
      expect(Recipient.fromRecord(incomplete), isNull);
      expect(Giver.fromRecord(incomplete), isNull);
      expect(Occasion.fromRecord(incomplete), isNull);
    });

    test('los tipos del dominio se vuelven a escribir igual', () {
      final recipient = Recipient(
        id: 'r1',
        name: 'Aritz',
        colorIndex: 0,
        relation: 'hijo',
        birthMonth: 6,
        birthDay: 10,
        birthYear: null,
        archived: false,
      );
      final record = SyncRecord(
        id: 'r1',
        fields: <String, FieldValue>{
          for (final entry in recipient.toFields().entries)
            entry.key: FieldValue(
              value: entry.value,
              stamp: Hlc(millis: 1, counter: 0, node: 'aaaa'),
            ),
        },
      );
      expect(Recipient.fromRecord(record), equals(recipient));

      final giver = Giver(
        id: 'g1',
        name: 'Nosotros',
        colorIndex: 0,
        householdPays: true,
        archived: false,
      );
      final giverRecord = SyncRecord(
        id: 'g1',
        fields: <String, FieldValue>{
          for (final entry in giver.toFields().entries)
            entry.key: FieldValue(
              value: entry.value,
              stamp: Hlc(millis: 1, counter: 0, node: 'aaaa'),
            ),
        },
      );
      expect(Giver.fromRecord(giverRecord), equals(giver));

      final occasion = Occasion(
        id: 'o1',
        kind: OccasionKind.santa,
        rawKind: 'santa',
        name: 'Navidad',
        month: 12,
        day: 25,
        year: null,
        recurring: true,
        recipientId: null,
        archived: false,
      );
      final occasionRecord = SyncRecord(
        id: 'o1',
        fields: <String, FieldValue>{
          for (final entry in occasion.toFields().entries)
            entry.key: FieldValue(
              value: entry.value,
              stamp: Hlc(millis: 1, counter: 0, node: 'aaaa'),
            ),
        },
      );
      expect(Occasion.fromRecord(occasionRecord), equals(occasion));

      final gift = Gift(
        id: 'g1',
        recipientId: 'r1',
        title: 'Bicicleta',
        giverId: 'g1',
        occasionId: 'o1',
        status: GiftStatus.bought,
        rawStatus: 'bought',
        plannedCents: 12000,
        actualCents: 7294,
        store: null,
        url: null,
        note: null,
        size: null,
        requestedBy: const RequestedByRecipient('r1'),
        requestNote: 'La pidió él mismo',
        surprise: false,
        year: 2026,
      );
      final giftRecord = SyncRecord(
        id: 'g1',
        fields: <String, FieldValue>{
          for (final entry in gift.toFields().entries)
            entry.key: FieldValue(
              value: entry.value,
              stamp: Hlc(millis: 1, counter: 0, node: 'aaaa'),
            ),
        },
      );
      expect(Gift.fromRecord(giftRecord), equals(gift));
    });

    test('la relación de un destinatario es texto libre y puede faltar', () {
      final view = FamilyView.fromDoc(sampleDoc());
      final recipients = view.recipientsById;

      expect(recipients['r1']!.relation, equals('hijo'));
      expect(recipients['r2']!.relation, isNull);
      expect(recipients['r2']!.toFields()['relation'], isNull);
    });

    test('el id es la clave del registro, no un campo', () {
      final stamp = Hlc(millis: 1, counter: 0, node: 'aaaa');
      final record = SyncRecord(
        id: 'g1',
        fields: <String, FieldValue>{
          'id': FieldValue(value: 'g2', stamp: stamp),
          'recipientId': FieldValue(value: 'r1', stamp: stamp),
          'title': FieldValue(value: 'Bicicleta', stamp: stamp),
          'status': FieldValue(value: 'idea', stamp: stamp),
          'surprise': FieldValue(value: false, stamp: stamp),
          'year': FieldValue(value: 2026, stamp: stamp),
        },
      );

      final gift = Gift.fromRecord(record);
      expect(gift, isNotNull);
      expect(gift!.id, equals('g1'));
      expect(gift.toFields().containsKey('id'), isFalse);
    });

    test('los campos que no existen se escriben con null', () {
      final gift = Gift(
        id: 'g1',
        recipientId: 'r1',
        title: 'Bicicleta',
        status: GiftStatus.idea,
        rawStatus: 'idea',
        surprise: false,
        year: 2026,
      );

      final fields = gift.toFields();
      expect(fields.containsKey('store'), isTrue);
      expect(fields['store'], isNull);
      expect(fields.containsKey('id'), isFalse);
    });
  });

  group('lo que llega del otro móvil', () {
    /// A record of a gift with the given fields.
    SyncRecord giftRecord(Map<String, Object?> fields) {
      final stamp = Hlc(millis: 1, counter: 0, node: 'aaaa');
      return SyncRecord(
        id: 'g1',
        fields: <String, FieldValue>{
          'recipientId': FieldValue(value: 'r1', stamp: stamp),
          'title': FieldValue(value: 'Bicicleta', stamp: stamp),
          'status': FieldValue(value: 'idea', stamp: stamp),
          'surprise': FieldValue(value: false, stamp: stamp),
          'year': FieldValue(value: 2026, stamp: stamp),
          for (final entry in fields.entries)
            entry.key: FieldValue(value: entry.value, stamp: stamp),
        },
      );
    }

    test('los céntimos fuera de rango se ignoran', () {
      final gift = Gift.fromRecord(
        giftRecord(<String, Object?>{
          'plannedCents': -5,
          'actualCents': 2000000000,
        }),
      );

      expect(gift, isNotNull);
      expect(gift!.plannedCents, isNull);
      expect(gift.actualCents, isNull);
    });

    test('un mes o un día imposibles invalidan la ocasión', () {
      final stamp = Hlc(millis: 1, counter: 0, node: 'aaaa');
      SyncRecord occasionRecord(int month, int day) => SyncRecord(
        id: 'o1',
        fields: <String, FieldValue>{
          'kind': FieldValue(value: 'santa', stamp: stamp),
          'name': FieldValue(value: 'Navidad', stamp: stamp),
          'month': FieldValue(value: month, stamp: stamp),
          'day': FieldValue(value: day, stamp: stamp),
          'recurring': FieldValue(value: true, stamp: stamp),
          'archived': FieldValue(value: false, stamp: stamp),
        },
      );

      expect(Occasion.fromRecord(occasionRecord(13, 25)), isNull);
      expect(Occasion.fromRecord(occasionRecord(12, 32)), isNull);
      expect(Occasion.fromRecord(occasionRecord(12, 25)), isNotNull);
    });

    test('un cumpleaños sin persona no se lee', () {
      final stamp = Hlc(millis: 1, counter: 0, node: 'aaaa');
      final record = SyncRecord(
        id: 'o1',
        fields: <String, FieldValue>{
          'kind': FieldValue(value: 'birthday', stamp: stamp),
          'name': FieldValue(value: 'Cumpleaños', stamp: stamp),
          'month': FieldValue(value: 6, stamp: stamp),
          'day': FieldValue(value: 10, stamp: stamp),
          'recurring': FieldValue(value: true, stamp: stamp),
          'archived': FieldValue(value: false, stamp: stamp),
        },
      );

      expect(Occasion.fromRecord(record), isNull);
    });

    test('un encargo de alguien que no está en la lista se lee igual', () {
      final gift = Gift.fromRecord(
        giftRecord(<String, Object?>{
          'requestedBy': <String, Object?>{'recipientId': 'noexiste'},
        }),
      );

      expect(gift, isNotNull);
      expect(gift!.requestedBy, equals(const RequestedByRecipient('noexiste')));
    });
  });

  group('presupuesto', () {
    test('solo cuenta lo que paga la casa', () {
      final view = FamilyView.fromDoc(sampleDoc());
      final budget = view.budget();

      // Aritz: 12000 + 2500 previstos y 7294 gastados (el puzle es solo idea).
      expect(budget.ofRecipient('r1').plannedCents, equals(14500));
      expect(budget.ofRecipient('r1').spentCents, equals(7294));

      // Nora: comprado sin precio real, cuenta lo previsto.
      expect(budget.ofRecipient('r2').plannedCents, equals(3000));
      expect(budget.ofRecipient('r2').spentCents, equals(3000));

      // El ratón de los yayos no es gasto de la casa.
      expect(budget.total.plannedCents, equals(17500));
      expect(budget.total.spentCents, equals(10294));

      expect(budget.ofOccasion('o1').plannedCents, equals(14500));
      expect(budget.ofOccasion('o1').spentCents, equals(7294));
      expect(budget.ofOccasion('o2').plannedCents, equals(3000));
    });

    test('un regalo de otro regalador no cuenta como gasto', () {
      final view = FamilyView.fromDoc(sampleDoc());
      final budget = view.budget();
      expect(
        budget.total.plannedCents,
        equals(
          view.gifts
              .where((gift) => gift.giverId == 'g1')
              .fold<int>(0, (sum, gift) => sum + (gift.plannedCents ?? 0)),
        ),
      );
    });

    test('un regalo de la casa a una pareja es gasto', () {
      final doc = withClock(Clock.fixed(base), () {
        final clock = HlcClock(node: 'aaaa');
        var doc = FamilyDoc.empty('list-1');
        doc = doc.set(clock, Collections.recipients, 'r1', {
          'id': 'r1',
          'name': 'Leo',
          'colorIndex': 2,
          'relation': 'pareja',
          'archived': false,
        });
        doc = doc.set(clock, Collections.givers, 'g1', {
          'id': 'g1',
          'name': 'Nosotros',
          'colorIndex': 0,
          'householdPays': true,
          'archived': false,
        });
        doc = doc.set(clock, Collections.gifts, 'g1', {
          'id': 'g1',
          'recipientId': 'r1',
          'title': 'Anillo',
          'giverId': 'g1',
          'status': 'bought',
          'plannedCents': 9000,
          'surprise': true,
          'year': 2026,
        });
        return doc;
      });

      final view = FamilyView.fromDoc(doc);
      final budget = view.budget();
      expect(budget.ofRecipient('r1').plannedCents, equals(9000));
      expect(budget.ofRecipient('r1').spentCents, equals(9000));
      expect(budget.total.plannedCents, equals(9000));
    });

    test('un encargo no convierte en gasto lo que paga otro', () {
      // Aritz pide un regalo a los yayos: lo pagan ellos, no la casa.
      final doc = withClock(Clock.fixed(base), () {
        final clock = HlcClock(node: 'aaaa');
        var doc = FamilyDoc.empty('list-1');
        doc = doc.set(clock, Collections.recipients, 'r1', {
          'id': 'r1',
          'name': 'Aritz',
          'colorIndex': 0,
          'archived': false,
        });
        doc = doc.set(clock, Collections.givers, 'g2', {
          'id': 'g2',
          'name': 'Yayos de Terrassa',
          'colorIndex': 1,
          'householdPays': false,
          'archived': false,
        });
        doc = doc.set(clock, Collections.gifts, 'g1', {
          'id': 'g1',
          'recipientId': 'r1',
          'title': 'Bicicleta',
          'giverId': 'g2',
          'status': 'bought',
          'plannedCents': 12000,
          'requestedBy': <String, Object?>{'recipientId': 'r1'},
          'surprise': false,
          'year': 2026,
        });
        return doc;
      });

      final budget = FamilyView.fromDoc(doc).budget();
      expect(budget.total.plannedCents, equals(0));
      expect(budget.total.spentCents, equals(0));
      expect(budget.ofRecipient('r1').plannedCents, equals(0));
    });

    test('un encargo pagado por la casa sigue siendo gasto', () {
      // Nora pide un regalo para Aritz, pero lo paga la casa.
      final doc = withClock(Clock.fixed(base), () {
        final clock = HlcClock(node: 'aaaa');
        var doc = FamilyDoc.empty('list-1');
        doc = doc.set(clock, Collections.recipients, 'r1', {
          'id': 'r1',
          'name': 'Aritz',
          'colorIndex': 0,
          'archived': false,
        });
        doc = doc.set(clock, Collections.recipients, 'r2', {
          'id': 'r2',
          'name': 'Nora',
          'colorIndex': 1,
          'archived': false,
        });
        doc = doc.set(clock, Collections.givers, 'g1', {
          'id': 'g1',
          'name': 'Nosotros',
          'colorIndex': 0,
          'householdPays': true,
          'archived': false,
        });
        doc = doc.set(clock, Collections.gifts, 'g1', {
          'id': 'g1',
          'recipientId': 'r1',
          'title': 'Bicicleta',
          'giverId': 'g1',
          'status': 'bought',
          'plannedCents': 12000,
          'requestedBy': <String, Object?>{'recipientId': 'r2'},
          'surprise': false,
          'year': 2026,
        });
        return doc;
      });

      final budget = FamilyView.fromDoc(doc).budget();
      expect(budget.ofRecipient('r1').plannedCents, equals(12000));
      expect(budget.total.plannedCents, equals(12000));
    });
  });

  group('encargos', () {
    test('un encargo de alguien sin ficha se guarda solo con el nombre', () {
      final doc = withClock(Clock.fixed(base), () {
        final clock = HlcClock(node: 'aaaa');
        var doc = FamilyDoc.empty('list-1');
        doc = doc.set(clock, Collections.recipients, 'r1', {
          'id': 'r1',
          'name': 'Aritz',
          'colorIndex': 0,
          'archived': false,
        });
        doc = doc.set(clock, Collections.gifts, 'g1', {
          'id': 'g1',
          'recipientId': 'r1',
          'title': 'Bicicleta',
          'status': 'idea',
          'requestedBy': <String, Object?>{'name': 'Leo'},
          'requestNote': 'Para el año que viene',
          'surprise': false,
          'year': 2026,
        });
        return doc;
      });

      final gift = FamilyView.fromDoc(doc).giftsFor('r1').single;
      expect(gift.requestedBy, equals(const RequestedByName('Leo')));
      expect(gift.requestNote, equals('Para el año que viene'));
      expect(
        gift.toFields()['requestedBy'],
        equals(<String, Object?>{'name': 'Leo'}),
      );
      expect(gift.toFields()['requestNote'], equals('Para el año que viene'));
    });

    test('un encargo de alguien de la lista apunta a su ficha', () {
      final doc = withClock(Clock.fixed(base), () {
        final clock = HlcClock(node: 'aaaa');
        var doc = FamilyDoc.empty('list-1');
        doc = doc.set(clock, Collections.recipients, 'r1', {
          'id': 'r1',
          'name': 'Aritz',
          'colorIndex': 0,
          'archived': false,
        });
        doc = doc.set(clock, Collections.recipients, 'r2', {
          'id': 'r2',
          'name': 'Nora',
          'colorIndex': 1,
          'archived': false,
        });
        doc = doc.set(clock, Collections.gifts, 'g1', {
          'id': 'g1',
          'recipientId': 'r1',
          'title': 'Bicicleta',
          'status': 'idea',
          'requestedBy': <String, Object?>{'recipientId': 'r2'},
          'surprise': false,
          'year': 2026,
        });
        return doc;
      });

      final gift = FamilyView.fromDoc(doc).giftsFor('r1').single;
      expect(gift.requestedBy, equals(const RequestedByRecipient('r2')));
      expect(
        gift.toFields()['requestedBy'],
        equals(<String, Object?>{'recipientId': 'r2'}),
      );
    });

    test('lo pidió la propia persona', () {
      final view = FamilyView.fromDoc(sampleDoc());
      final gift = view.giftsFor('r1').firstWhere((gift) => gift.id == 'g1');

      expect(gift.requestedBy, equals(const RequestedByRecipient('r1')));
      expect(gift.recipientId, equals('r1'));
    });

    test('quien pidió se puede leer con las dos variantes', () {
      final view = FamilyView.fromDoc(sampleDoc());
      final gift = view.giftsFor('r1').firstWhere((gift) => gift.id == 'g1');

      final askedBy = switch (gift.requestedBy) {
        RequestedByRecipient(:final recipientId) => 'ficha $recipientId',
        RequestedByName(:final name) => 'nombre $name',
        null => 'nadie',
      };
      expect(askedBy, equals('ficha r1'));
    });

    test('un regalo sin encargo no escribe el campo', () {
      final view = FamilyView.fromDoc(sampleDoc());
      final gift = view.giftsFor('r1').firstWhere((gift) => gift.id == 'g2');

      expect(gift.requestedBy, isNull);
      expect(gift.requestNote, isNull);
      expect(gift.toFields()['requestedBy'], isNull);
      expect(gift.toFields()['requestNote'], isNull);
    });
  });

  group('rejilla', () {
    test('cada regalador y cada destinatario tienen su celda', () {
      final view = FamilyView.fromDoc(sampleDoc());
      final grid = view.grid();

      expect(grid.recipients.length, equals(2));
      expect(grid.givers.length, equals(2));

      final house = grid.cell('r1', 'g1');
      expect(house.giftCount, equals(2));
      expect(house.plannedCents, equals(14500));
      expect(house.spentCents, equals(7294));
      expect(house.status, equals(GridStatus.pending));
      expect(house.cents, equals(7294));
    });

    test('una celda vacía', () {
      final view = FamilyView.fromDoc(sampleDoc());
      final grid = view.grid();

      // Nora no tiene ningún regalo de los yayos.
      final empty = grid.cell('r2', 'g2');
      expect(empty.giftCount, equals(0));
      expect(empty.cents, equals(0));
      expect(empty.status, equals(GridStatus.none));

      final unknown = grid.cell('nadie', 'g1');
      expect(unknown.giftCount, equals(0));
      expect(unknown.status, equals(GridStatus.none));
    });

    test('una celda con todo comprado', () {
      final view = FamilyView.fromDoc(sampleDoc());
      final grid = view.grid();
      expect(grid.cell('r2', 'g1').status, equals(GridStatus.allBought));
    });

    test('un regalo sin regalador conocido sale en la fila sin asignar', () {
      final doc = withClock(Clock.fixed(base), () {
        final clock = HlcClock(node: 'aaaa');
        var built = FamilyDoc.empty('list-1');
        built = built.set(clock, Collections.recipients, 'r1', {
          'name': 'Aritz',
          'colorIndex': 0,
          'archived': false,
        });
        built = built.set(clock, Collections.givers, 'g1', {
          'name': 'Nosotros',
          'colorIndex': 0,
          'householdPays': true,
          'archived': false,
        });
        built = built.set(clock, Collections.gifts, 'g1', {
          'recipientId': 'r1',
          'title': 'Bicicleta',
          'giverId': 'g1',
          'status': 'idea',
          'surprise': false,
          'year': 2026,
        });
        built = built.set(clock, Collections.gifts, 'g2', {
          'recipientId': 'r1',
          'title': 'Camión',
          'giverId': 'noexiste',
          'status': 'idea',
          'surprise': false,
          'year': 2026,
        });
        built = built.set(clock, Collections.gifts, 'g3', {
          'recipientId': 'r1',
          'title': 'Puzle',
          'status': 'idea',
          'surprise': false,
          'year': 2026,
        });
        return built;
      });

      final grid = FamilyView.fromDoc(doc).grid();
      expect(grid.hasUnassignedGifts, isTrue);
      expect(grid.unassignedCell('r1').giftCount, equals(2));
      expect(grid.cell('r1', 'g1').giftCount, equals(1));
    });

    test('una lista sin regalos sin asignar no tiene esa fila', () {
      final grid = FamilyView.fromDoc(sampleDoc()).grid();
      expect(grid.hasUnassignedGifts, isFalse);
      expect(grid.unassignedCell('r1').giftCount, equals(0));
    });

    test('los regalos de un regalador archivado no salen en la rejilla', () {
      final doc = withClock(Clock.fixed(base), () {
        final clock = HlcClock(node: 'aaaa');
        var built = FamilyDoc.empty('list-1');
        built = built.set(clock, Collections.recipients, 'r1', {
          'name': 'Aritz',
          'colorIndex': 0,
          'archived': false,
        });
        built = built.set(clock, Collections.givers, 'g1', {
          'name': 'Nosotros',
          'colorIndex': 0,
          'householdPays': true,
          'archived': false,
        });
        built = built.set(clock, Collections.givers, 'g2', {
          'name': 'Yayos de Terrassa',
          'colorIndex': 1,
          'householdPays': false,
          'archived': true,
        });
        built = built.set(clock, Collections.gifts, 'g1', {
          'recipientId': 'r1',
          'title': 'Bicicleta',
          'giverId': 'g2',
          'status': 'idea',
          'surprise': false,
          'year': 2026,
        });
        return built;
      });

      final grid = FamilyView.fromDoc(doc).grid();
      expect(grid.hasUnassignedGifts, isFalse);
      expect(grid.unassignedCell('r1').giftCount, equals(0));
      expect(grid.cell('r1', 'g1').giftCount, equals(0));

      // Cuando se piden también los archivados, el regalo sale en su celda.
      final all = FamilyView.fromDoc(doc, includeArchived: true).grid();
      expect(all.cell('r1', 'g2').giftCount, equals(1));
    });
  });

  group('años y archivados', () {
    /// A list with a recipient, a giver and gifts of two years.
    FamilyDoc docWithYears() => withClock(Clock.fixed(base), () {
      final clock = HlcClock(node: 'aaaa');
      var doc = FamilyDoc.empty('list-1');
      doc = doc.set(clock, Collections.recipients, 'r1', {
        'name': 'Aritz',
        'colorIndex': 0,
        'archived': false,
      });
      doc = doc.set(clock, Collections.recipients, 'r2', {
        'name': 'Nora',
        'colorIndex': 1,
        'archived': true,
      });
      doc = doc.set(clock, Collections.givers, 'g1', {
        'name': 'Nosotros',
        'colorIndex': 0,
        'householdPays': true,
        'archived': false,
      });
      doc = doc.set(clock, Collections.givers, 'g2', {
        'name': 'Yayos de Terrassa',
        'colorIndex': 1,
        'householdPays': false,
        'archived': true,
      });
      doc = doc.set(clock, Collections.gifts, 'g1', {
        'recipientId': 'r1',
        'title': 'Bicicleta',
        'giverId': 'g1',
        'status': 'bought',
        'plannedCents': 1000,
        'surprise': false,
        'year': 2026,
      });
      doc = doc.set(clock, Collections.gifts, 'g2', {
        'recipientId': 'r1',
        'title': 'Puzle',
        'giverId': 'g1',
        'status': 'idea',
        'plannedCents': 2000,
        'surprise': false,
        'year': 2025,
      });
      doc = doc.set(clock, Collections.gifts, 'g3', {
        'recipientId': 'r2',
        'title': 'Camión',
        'giverId': 'g2',
        'status': 'idea',
        'plannedCents': 3000,
        'surprise': false,
        'year': 2026,
      });
      return doc;
    });

    test('con año solo se cuentan los regalos de ese año', () {
      final view = FamilyView.fromDoc(docWithYears(), year: 2026);

      expect(
        view.gifts.map((gift) => gift.title).toList(),
        equals(<String>['Bicicleta', 'Camión']),
      );
      expect(view.budget().total.plannedCents, equals(1000));
    });

    test('sin año se ven los regalos de todos los años', () {
      final view = FamilyView.fromDoc(docWithYears());
      expect(view.gifts.length, equals(3));
      // La bicicleta de 2026 y el puzle de 2025 los paga la casa; el
      // camión lo pagan los yayos, que están archivados.
      expect(view.budget().total.plannedCents, equals(3000));
    });

    test('los archivados no salen por defecto', () {
      final view = FamilyView.fromDoc(docWithYears());

      expect(
        view.recipients.map((recipient) => recipient.name).toList(),
        equals(<String>['Aritz']),
      );
      expect(
        view.givers.map((giver) => giver.name).toList(),
        equals(<String>['Nosotros']),
      );
    });

    test('los archivados salen cuando se piden', () {
      final view = FamilyView.fromDoc(docWithYears(), includeArchived: true);

      expect(view.recipients.length, equals(2));
      expect(view.givers.length, equals(2));
    });

    test('los regalos de los archivados no salen en la rejilla', () {
      final grid = FamilyView.fromDoc(docWithYears()).grid();

      expect(grid.recipients.length, equals(1));
      expect(grid.givers.length, equals(1));
      expect(grid.cell('r1', 'g1').giftCount, equals(2));
      expect(grid.cell('r2', 'g2').giftCount, equals(0));
    });

    test('los regalos del año pasado son otro aviso que el duplicado', () {
      final view = FamilyView.fromDoc(docWithYears(), year: 2026);
      final previous = view.previousYearsGifts('r1', 2026);

      expect(
        previous.map((gift) => gift.title).toList(),
        equals(<String>['Puzle']),
      );
      expect(view.previousYearsGifts('r1', 2025), isEmpty);
      expect(view.possibleDuplicates(), isEmpty);
    });
  });

  group('posibles duplicados', () {
    /// A list with a recipient and some gifts with the given titles.
    FamilyDoc docWithTitles(List<String> titles, {String recipientId = 'r1'}) =>
        withClock(Clock.fixed(base), () {
          final clock = HlcClock(node: 'aaaa');
          var doc = FamilyDoc.empty('list-1');
          doc = doc.set(clock, Collections.recipients, recipientId, {
            'id': recipientId,
            'name': 'Aritz',
            'colorIndex': 0,
            'archived': false,
          });
          for (var i = 0; i < titles.length; i++) {
            doc = doc.set(clock, Collections.gifts, 'g$i', {
              'id': 'g$i',
              'recipientId': recipientId,
              'title': titles[i],
              'status': 'idea',
              'surprise': false,
              'year': 2026,
            });
          }
          return doc;
        });

    test('avisa de dos regalos con casi el mismo nombre', () {
      final view = FamilyView.fromDoc(
        docWithTitles(<String>['Puzle de 48 piezas', 'puzle 48 piezas']),
      );
      final pairs = view.possibleDuplicates();

      expect(pairs.length, equals(1));
      expect(pairs.first.recipientId, equals('r1'));
      expect(<String>{
        pairs.first.first.title,
        pairs.first.second.title,
      }, equals(<String>{'Puzle de 48 piezas', 'puzle 48 piezas'}));
    });

    test('los regalos parecidos de destinatarios distintos no avisan', () {
      final doc = withClock(Clock.fixed(base), () {
        final clock = HlcClock(node: 'aaaa');
        var built = FamilyDoc.empty('list-1');
        for (final recipient in <Map<String, Object?>>[
          <String, Object?>{'id': 'r1', 'name': 'Aritz'},
          <String, Object?>{'id': 'r2', 'name': 'Nora'},
        ]) {
          final recipientId = recipient['id'] as String;
          built = built.set(clock, Collections.recipients, recipientId, {
            ...recipient,
            'colorIndex': 0,
            'archived': false,
          });
          built = built.set(clock, Collections.gifts, 'g$recipientId', {
            'id': 'g$recipientId',
            'recipientId': recipientId,
            'title': 'Puzle de 48 piezas',
            'status': 'idea',
            'surprise': false,
            'year': 2026,
          });
        }
        return built;
      });
      expect(FamilyView.fromDoc(doc).possibleDuplicates(), isEmpty);
    });

    test('los acentos no cuentan', () {
      final view = FamilyView.fromDoc(
        docWithTitles(<String>['Cámara', 'camara']),
      );
      expect(view.possibleDuplicates().length, equals(1));
    });

    test('un título dentro de otro también avisa', () {
      final view = FamilyView.fromDoc(
        docWithTitles(<String>['Puzle', 'Puzle de 48 piezas']),
      );
      expect(view.possibleDuplicates().length, equals(1));
    });

    test('no avisa de regalos que no se parecen', () {
      final view = FamilyView.fromDoc(
        docWithTitles(<String>['Pijama', 'Patinete']),
      );
      expect(view.possibleDuplicates(), isEmpty);
    });

    test('no avisa de títulos parecidos que son distintos', () {
      for (final titles in <List<String>>[
        <String>['Coche', 'Noche'],
        <String>['Pijama', 'Pirata'],
        <String>['Pelota', 'Peluca'],
      ]) {
        final view = FamilyView.fromDoc(docWithTitles(titles));
        expect(
          view.possibleDuplicates(),
          isEmpty,
          reason: 'no es duplicado: ${titles.join(' y ')}',
        );
      }
    });
  });

  test('las pruebas no dependen del reloj real', () {
    withClock(Clock.fixed(base), () {
      final doc = sampleDoc();
      expect(doc.maxStamp, isNotNull);
      expect(
        doc.maxStamp!.millis,
        greaterThanOrEqualTo(base.millisecondsSinceEpoch),
      );
    });
  });
}
