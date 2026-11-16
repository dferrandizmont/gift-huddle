import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/family/domain/delete_impact.dart';

import '../helpers/memory_stores.dart';

const _aritz = Recipient(
  id: 'aritz',
  name: 'Aritz',
  colorIndex: 0,
  birthMonth: 3,
  birthDay: 14,
  archived: false,
);
const _nora = Recipient(
  id: 'nora',
  name: 'Nora',
  colorIndex: 1,
  archived: false,
);
const _us = Giver(
  id: 'us',
  name: 'Nosotros',
  colorIndex: 0,
  householdPays: true,
  archived: false,
);
const _tio = Occasion(
  id: 'seed-tio',
  kind: OccasionKind.tio,
  rawKind: 'tio',
  name: 'Tió',
  month: 12,
  day: 24,
  recurring: true,
  archived: false,
);

Gift _gift(
  String id,
  String recipient,
  String title, {
  String? giver,
  String? occasion,
  RequestedBy? by,
  int year = 2026,
}) => Gift(
  id: id,
  recipientId: recipient,
  title: title,
  giverId: giver,
  occasionId: occasion,
  status: GiftStatus.idea,
  rawStatus: 'idea',
  plannedCents: 1500,
  note: 'Nota de $title',
  url: 'https://example.com/$id',
  requestedBy: by,
  surprise: false,
  year: year,
);

void main() {
  late FakePhone phone;
  late FamilyController controller;

  Future<FamilyState> state() =>
      phone.container.read(familyControllerProvider.future);

  setUp(() async {
    phone = FakePhone();
    controller = phone.container.read(familyControllerProvider.notifier);
    await controller.createFamily(deviceName: 'Móvil');
    await controller.upsertRecipient(_aritz);
    await controller.upsertRecipient(_nora);
    await controller.upsertGiver(_us);
    await controller.upsertOccasion(_tio);
    await controller.ensureBirthdayOccasions();
    await controller.upsertGift(_gift('g1', 'aritz', 'Bici', giver: 'us'));
    await controller.upsertGift(
      _gift('g2', 'aritz', 'Libro', giver: 'us', occasion: 'seed-tio'),
    );
    await controller.upsertGift(
      _gift('g3', 'aritz', 'Puzle', year: 2025, giver: 'us'),
    );
    await controller.upsertGift(
      _gift(
        'g4',
        'nora',
        'Muñeca',
        giver: 'us',
        occasion: 'seed-tio',
        by: const RequestedByRecipient('aritz'),
      ),
    );
  });
  tearDown(() => phone.dispose());

  test('el impacto cuenta regalos de todos los años y el cumpleaños', () async {
    final full = (await state()).fullView;
    final aritz = DeleteImpact.ofRecipient(full, 'aritz');
    expect(aritz.gifts, 3);
    expect(aritz.hasBirthday, isTrue);
    expect(DeleteImpact.ofRecipient(full, 'nora').hasBirthday, isFalse);
    expect(DeleteImpact.ofGiver(full, 'us').gifts, 4);
    expect(DeleteImpact.ofOccasion(full, 'seed-tio').gifts, 2);
  });

  test(
    'eliminar a una persona: lápida vacía, sus regalos y su cumpleaños',
    () async {
      await controller.deleteRecipient('aritz');
      final s = await state();
      final doc = s.doc;
      expect(s.fullView.recipients.map((r) => r.id), ['nora']);
      expect(s.fullView.allGifts.map((g) => g.id), ['g4']);
      expect(s.fullView.occasions.map((o) => o.id), ['seed-tio']);
      // Ninguna lápida conserva texto legible.
      for (final text in [
        'Aritz',
        'Bici',
        'Libro',
        'Puzle',
        'Nota de Bici',
        'Nota de Libro',
        'Nota de Puzle',
        'example.com/g1',
      ]) {
        expect(doc.canonicalJson(), isNot(contains(text)), reason: text);
      }
      for (final records in doc.collections.values) {
        for (final record in records.values) {
          expect(record.hasTombstoneContent, isFalse, reason: record.id);
        }
      }
      // El regalo de otra persona que había pedido Aritz pierde ese dato.
      expect(s.fullView.allGifts.single.requestedBy, isNull);
      expect(s.fullView.allGifts.single.title, 'Muñeca');
    },
  );

  test('eliminar a quien regala: sus regalos se quedan sin él', () async {
    await controller.deleteGiver('us');
    final s = await state();
    expect(s.fullView.givers, isEmpty);
    expect(s.fullView.allGifts, hasLength(4));
    expect(s.fullView.allGifts.every((g) => g.giverId == null), isTrue);
    expect(s.doc.canonicalJson(), isNot(contains('Nosotros')));
  });

  test('eliminar una ocasión: sus regalos se quedan sin ocasión', () async {
    await controller.deleteOccasion('seed-tio');
    final s = await state();
    expect(s.fullView.occasions.map((o) => o.id), ['birthday-aritz']);
    expect(s.fullView.allGifts, hasLength(4));
    expect(s.fullView.allGifts.every((g) => g.occasionId == null), isTrue);
    expect(s.doc.canonicalJson(), isNot(contains('Tió')));
  });

  test('eliminar dos veces o algo que no existe no escribe nada', () async {
    await controller.deleteGiver('us');
    final before = (await state()).doc.canonicalJson();
    await controller.deleteGiver('us');
    await controller.deleteGiver('nadie');
    await controller.deleteRecipient('nadie');
    await controller.deleteOccasion('nadie');
    expect((await state()).doc.canonicalJson(), before);
  });

  test(
    'una edición concurrente en otro móvil no resucita lo eliminado',
    () async {
      final original = (await state()).doc;
      await controller.deleteRecipient('aritz');
      // Otro móvil, sin haber recibido el borrado, edita a Aritz más tarde.
      final remote = original.set(
        HlcClock(node: 'remoto', last: (await state()).doc.maxStamp),
        Collections.recipients,
        'aritz',
        {'name': 'Aritz Martí', 'relation': 'Hijo'},
      );
      await controller.mergeRemote(remote, fromNode: 'remoto');
      final s = await state();
      expect(s.fullView.recipients.map((r) => r.id), ['nora']);
      expect(s.doc.record(Collections.recipients, 'aritz')!.isDeleted, isTrue);
      expect(s.doc.canonicalJson(), isNot(contains('Aritz Martí')));
      expect(s.doc.canonicalJson(), isNot(contains('Hijo')));
    },
  );

  test(
    'al cargar, las lápidas antiguas con contenido se vacían y se guardan',
    () async {
      // Un guardado de la versión anterior: lápida con su contenido.
      final stored = (await state()).doc;
      final legacy = FamilyDoc.fromJson({
        ...stored.toJson(),
        'c': {
          ...(stored.toJson()['c'] as Map<String, Object?>),
          Collections.givers: {
            ...((stored.toJson()['c']
                    as Map<String, Object?>)[Collections.givers]
                as Map<String, Object?>),
            'us': {
              'name': [
                'Nosotros',
                Hlc(millis: 1, counter: 0, node: 'x').pack(),
              ],
              'deleted': [true, Hlc(millis: 2, counter: 0, node: 'x').pack()],
            },
          },
        },
      });
      expect(
        legacy.record(Collections.givers, 'us')!.hasTombstoneContent,
        isTrue,
      );
      await phone.container.read(familyStoreProvider).saveDoc(legacy);
      phone.restart();
      final s = await state();
      expect(s.doc.canonicalJson(), isNot(contains('Nosotros')));
      expect(s.fullView.givers, isEmpty);
      phone.restart();
      expect((await state()).doc.canonicalJson(), s.doc.canonicalJson());
    },
  );

  test('al cargar, el vaciado de una lápida antigua gana por marca', () async {
    final stored = (await state()).doc;
    final old = Hlc(millis: 5, counter: 0, node: 'x').pack();
    final json = stored.toJson();
    final collections = json['c'] as Map<String, Object?>;
    final legacy = FamilyDoc.fromJson({
      ...json,
      'c': {
        ...collections,
        Collections.gifts: {
          ...(collections[Collections.gifts] as Map<String, Object?>),
          'g1': {
            'surprise': [true, old],
            'requestedBy': [
              {'recipientId': 'nora'},
              old,
            ],
            'deleted': [true, old],
          },
        },
      },
    });
    await phone.container.read(familyStoreProvider).saveDoc(legacy);
    phone.restart();
    final record = (await state()).doc.record(Collections.gifts, 'g1')!;
    expect(record.hasTombstoneContent, isFalse);
    // Marcas nuevas: más recientes que las del contenido que traía la lápida.
    expect(record.field('surprise')!.stamp.millis, greaterThan(5));
    expect(record.field('requestedBy')!.stamp.millis, greaterThan(5));
  });

  test('un regalo creado después del borrado de su persona no se ve', () async {
    final original = (await state()).doc;
    await controller.deleteRecipient('aritz');
    final stamp = (await state()).doc.maxStamp;
    // Otro móvil, sin haber recibido el borrado, crea un regalo para Aritz y
    // un cumpleaños suyo con otro id.
    final remote = original
        .set(HlcClock(node: 'remoto', last: stamp), Collections.gifts, 'g9', {
          'recipientId': 'aritz',
          'title': 'Cohete',
          'status': 'idea',
          'surprise': false,
          'year': 2026,
        })
        .set(
          HlcClock(node: 'remoto', last: stamp),
          Collections.occasions,
          'b-extra',
          {
            'kind': 'birthday',
            'name': '',
            'month': 3,
            'day': 14,
            'recurring': true,
            'recipientId': 'aritz',
            'archived': false,
          },
        );
    await controller.mergeRemote(remote, fromNode: 'remoto');
    final s = await state();
    expect(s.fullView.allGifts.map((g) => g.id), ['g4']);
    expect(s.view.gifts.map((g) => g.id), ['g4']);
    expect(s.fullView.occasions.map((o) => o.id), ['seed-tio']);
  });

  test('guardar un regalo de una persona eliminada no escribe nada', () async {
    await controller.deleteRecipient('aritz');
    final before = (await state()).doc.canonicalJson();
    expect(
      await controller.upsertGift(_gift('g9', 'aritz', 'Cohete')),
      isFalse,
    );
    expect(await controller.upsertGift(_gift('g1', 'aritz', 'Otra')), isFalse);
    expect(await controller.setGiftStatus('g1', GiftStatus.bought), isFalse);
    expect(await controller.upsertGift(_gift('g8', 'nora', 'Tren')), isTrue);
    final after = (await state()).doc;
    expect(after.record(Collections.gifts, 'g9'), isNull);
    expect(after.canonicalJson(), isNot(equals(before)));
    expect(after.canonicalJson(), isNot(contains('Otra')));
  });

  test('guardar sin cambios sigue contando como guardado', () async {
    final s = await state();
    final g4 = s.fullView.allGifts.firstWhere((g) => g.id == 'g4');
    expect(await controller.upsertGift(g4, original: g4), isTrue);
  });

  test('personas y ocasiones archivadas cuentan igual en el impacto', () async {
    await controller.archiveRecipient('nora');
    await controller.archiveOccasion('seed-tio');
    final full = (await state()).fullView;
    expect(DeleteImpact.ofRecipient(full, 'nora').gifts, 1);
    expect(DeleteImpact.ofOccasion(full, 'seed-tio').gifts, 2);
    expect(DeleteImpact.ofRecipient(full, 'aritz').hasRequests, isTrue);
    expect(DeleteImpact.ofRecipient(full, 'nora').hasRequests, isFalse);
    expect(DeleteImpact.ofGiver(full, 'us').paysFromHousehold, isTrue);
    await controller.deleteRecipient('nora');
    await controller.deleteOccasion('seed-tio');
    final after = (await state()).fullView;
    expect(after.allGifts.where((g) => g.recipientId == 'nora'), isEmpty);
    expect(after.allGifts.every((g) => g.occasionId != 'seed-tio'), isTrue);
  });

  group('borrar un regalo con Deshacer', () {
    test('se oculta sin escribir la lápida y Deshacer lo devuelve', () async {
      final before = (await state()).doc.canonicalJson();
      expect(await controller.deleteGiftWithUndo('g1'), isTrue);
      final s = await state();
      expect(s.view.gifts.map((g) => g.id), isNot(contains('g1')));
      expect(s.fullView.allGifts.map((g) => g.id), isNot(contains('g1')));
      // El contenido sigue en memoria y nada se ha escrito.
      expect(s.doc.canonicalJson(), before);
      phone.restart();
      expect((await state()).doc.canonicalJson(), before);
      controller = phone.container.read(familyControllerProvider.notifier);
      expect(await controller.deleteGiftWithUndo('g1'), isTrue);
      expect(await controller.undoDeleteGift('g1'), isTrue);
      final back = await state();
      expect(back.view.gifts.map((g) => g.id), contains('g1'));
      expect(back.doc.canonicalJson(), before);
      expect(await controller.undoDeleteGift('g1'), isFalse);
    });

    test('al pasar a segundo plano se escribe la lápida vacía', () async {
      await controller.deleteGiftWithUndo('g1');
      await controller.flushPendingDeletes();
      final s = await state();
      expect(s.hiddenGiftIds, isEmpty);
      final record = s.doc.record(Collections.gifts, 'g1')!;
      expect(record.isDeleted, isTrue);
      expect(record.hasTombstoneContent, isFalse);
      expect(s.doc.canonicalJson(), isNot(contains('Bici')));
      expect(await controller.undoDeleteGift('g1'), isFalse);
      phone.restart();
      expect(
        (await state()).doc.record(Collections.gifts, 'g1')!.isDeleted,
        isTrue,
      );
    });

    test('un regalo que no existe o ya está borrado no se aplaza', () async {
      expect(await controller.deleteGiftWithUndo('nadie'), isFalse);
      await controller.deleteGift('g1');
      expect(await controller.deleteGiftWithUndo('g1'), isFalse);
    });

    test(
      'una fusión mientras espera no escribe ni pierde el borrado',
      () async {
        await controller.deleteGiftWithUndo('g1');
        final remote = (await state()).doc.set(
          HlcClock(node: 'remoto', last: (await state()).doc.maxStamp),
          Collections.gifts,
          'g2',
          {'note': 'Nueva nota'},
        );
        await controller.mergeRemote(remote, fromNode: 'remoto');
        var s = await state();
        expect(s.view.gifts.map((g) => g.id), isNot(contains('g1')));
        await controller.flushPendingDeletes();
        s = await state();
        expect(s.doc.record(Collections.gifts, 'g1')!.isDeleted, isTrue);
        expect(s.doc.record(Collections.gifts, 'g2')!['note'], 'Nueva nota');
      },
    );
  });
}
