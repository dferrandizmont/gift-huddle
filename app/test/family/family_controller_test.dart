import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/application/family_providers.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/family/data/generation_storage.dart';

import '../helpers/memory_stores.dart';

Gift gift(String id, {String title = 'Bloques', String? note}) => Gift(
  id: id,
  recipientId: 'aritz',
  title: title,
  status: GiftStatus.idea,
  rawStatus: 'idea',
  note: note,
  surprise: false,
  year: 2026,
);

extension on Gift {
  Gift copyYear(int year) => Gift(
    id: id,
    recipientId: recipientId,
    title: title,
    status: status,
    rawStatus: rawStatus,
    surprise: surprise,
    year: year,
  );
}

const aritz = Recipient(
  id: 'aritz',
  name: 'Aritz',
  colorIndex: 0,
  birthMonth: 3,
  birthDay: 14,
  archived: false,
);

const us = Giver(
  id: 'us',
  name: 'Nosotros',
  colorIndex: 0,
  householdPays: true,
  archived: false,
);

Future<FamilyState> ready(ProviderContainer c) =>
    c.read(familyControllerProvider.future);

FamilyController ctl(ProviderContainer c) =>
    c.read(familyControllerProvider.notifier);

void main() {
  late FakePhone phone;
  setUp(() => phone = FakePhone());
  tearDown(() => phone.dispose());

  testWidgets('sin generación gestionada, marcar un regalo desde la app '
      'se guarda y actualiza el estado sin otra acción', (tester) async {
    final c = ctl(phone.container);
    await tester.runAsync(() async {
      await c.createFamily(deviceName: 'Móvil de Aritz');
      await c.upsertRecipient(aritz);
      await c.upsertGift(gift('g1'));
    });
    expect(await phone.secrets.read(generationDirectoryKey), isNull);

    // As with a screen tap: the edit starts on the widget clock, while
    // encryption/storage finish on the real event loop.
    final saved = c.setGiftStatus('g1', GiftStatus.bought);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(
      phone.container
          .read(familyControllerProvider)
          .requireValue
          .view
          .gifts
          .single
          .status,
      GiftStatus.bought,
    );
    await saved;
    final stored = await tester.runAsync(
      () => phone.container.read(familyStoreProvider).load(),
    );
    expect(
      FamilyView.fromDoc(stored!.doc).gifts.single.status,
      GiftStatus.bought,
    );
  });

  test('primer arranque: sin familia', () async {
    final state = await ready(phone.container);
    expect(state.hasFamily, isFalse);
    expect(state.paired, isFalse);
    expect(state.view.gifts, isEmpty);
  });

  test('crear la familia genera lista, clave y nodo, y se guarda', () async {
    await ctl(phone.container).createFamily(deviceName: 'Móvil de Sol');
    final state = await ready(phone.container);
    expect(state.hasFamily, isTrue);
    expect(state.identity!.deviceName, 'Móvil de Sol');
    expect(state.identity!.node, hasLength(10));
    final key = ctl(phone.container).familyKey;
    expect(key, isNotNull);

    phone.restart();
    final again = await ready(phone.container);
    expect(again.identity!.listId, state.identity!.listId);
    expect(again.identity!.node, state.identity!.node);
    expect(ctl(phone.container).familyKey, key);
  });

  test('el documento va cifrado y no en el almacén seguro', () async {
    final c = ctl(phone.container);
    await c.createFamily(deviceName: 'A');
    await c.upsertRecipient(aritz);
    await c.upsertGift(gift('g1', title: 'Estación de bomberos'));

    final asText = String.fromCharCodes(phone.files.files['family.doc']!);
    expect(asText.contains('bomberos'), isFalse);
    expect(asText.contains('Aritz'), isFalse);
    for (final value in phone.secrets.values.values) {
      expect(value.contains('bomberos'), isFalse);
    }
    // La clave local es distinta de la de la familia.
    expect(
      phone.secrets.values['family.localKey'],
      isNot(phone.secrets.values['family.key']),
    );
    // Al reabrir, lo guardado vuelve.
    phone.restart();
    final state = await ready(phone.container);
    expect(state.view.gifts.single.title, 'Estación de bomberos');
    expect(state.view.recipients.single.name, 'Aritz');
  });

  test('con la clave local perdida da un error tipado', () async {
    final c = ctl(phone.container);
    await c.createFamily(deviceName: 'A');
    await c.upsertRecipient(aritz);
    phone.secrets.values['family.localKey'] =
        phone.secrets.values['family.key']!;
    phone.restart();
    await expectLater(
      phone.container.read(familyControllerProvider.future),
      throwsA(isA<FamilyStoreException>()),
    );
    await ctl(phone.container).resetLocalData();
    expect((await ready(phone.container)).hasFamily, isFalse);
  });

  test('el reloj se reanuda desde doc.maxStamp', () async {
    final c = ctl(phone.container);
    await c.createFamily(deviceName: 'A');
    // Un reloj adelantado deja un sello alto; tras reiniciar con la hora
    // normal, el siguiente sello sigue siendo mayor.
    final ahead = DateTime.now().add(const Duration(hours: 5));
    await withClock(Clock.fixed(ahead), () => c.upsertRecipient(aritz));
    final before = (await ready(phone.container)).doc.maxStamp!;
    phone.restart();
    await ready(phone.container);
    await ctl(phone.container).upsertGift(gift('g1'));
    final after = (await ready(phone.container)).doc.maxStamp!;
    expect(after > before, isTrue);
  });

  group('upsert', () {
    setUp(() async {
      await ctl(phone.container).createFamily(deviceName: 'A');
      await ctl(phone.container).upsertRecipient(aritz);
    });

    test('upsertGift escribe solo lo que cambia', () async {
      final c = ctl(phone.container);
      final t0 = DateTime.utc(2026, 11, 1, 10);
      await withClock(
        Clock.fixed(t0),
        () => c.upsertGift(gift('g1', note: 'azul')),
      );
      final first = (await ready(phone.container)).doc.record('gifts', 'g1')!;

      final t1 = t0.add(const Duration(minutes: 5));
      await withClock(
        Clock.fixed(t1),
        () => c.upsertGift(gift('g1', title: 'Bloques grandes', note: 'azul')),
      );
      final second = (await ready(phone.container)).doc.record('gifts', 'g1')!;

      expect(second['title'], 'Bloques grandes');
      expect(
        second.field('title')!.stamp > first.field('title')!.stamp,
        isTrue,
      );
      for (final name in [
        'note',
        'status',
        'recipientId',
        'year',
        'surprise',
      ]) {
        expect(
          second.field(name)!.stamp,
          first.field(name)!.stamp,
          reason: name,
        );
      }
    });

    test(
      'el diff del editor se aplica después de una fusión en cola',
      () async {
        final c = ctl(phone.container);
        final original = gift('g1', note: 'azul');
        await c.upsertGift(original);
        final opened = await ready(phone.container);
        final remote = opened.doc.set(
          HlcClock(node: 'remote', last: opened.doc.maxStamp),
          'gifts',
          'g1',
          {'title': 'Bloques de Nora', 'note': 'verde'},
        );

        // No esperar la fusión: el guardado debe usar el documento que quede
        // cuando le toque su turno, con un sello posterior al remoto.
        final merge = c.mergeRemote(remote, fromNode: 'remote');
        final save = c.upsertGift(
          gift('g1', title: 'Bloques grandes', note: 'azul'),
          original: original,
        );
        await merge;
        await save;

        final saved = await ready(phone.container);
        final record = saved.doc.record('gifts', 'g1')!;
        expect(record['title'], 'Bloques grandes');
        expect(record.field('title')!.stamp > remote.maxStamp!, isTrue);
        expect(record['note'], 'verde');
        expect(record.field('note')!.stamp, remote.maxStamp);
        phone.restart();
        expect(
          (await ready(phone.container)).doc.canonicalJson(),
          saved.doc.canonicalJson(),
        );
      },
    );

    test('sin cambios no escribe ni guarda', () async {
      final c = ctl(phone.container);
      await c.upsertGift(gift('g1'));
      final doc = (await ready(phone.container)).doc;
      final bytes = phone.files.files['family.doc'];
      await c.upsertGift(gift('g1'));
      expect(identical((await ready(phone.container)).doc, doc), isTrue);
      expect(identical(phone.files.files['family.doc'], bytes), isTrue);
    });

    test('quitar un campo opcional lo borra', () async {
      final c = ctl(phone.container);
      await c.upsertGift(gift('g1', note: 'azul'));
      await c.upsertGift(gift('g1'));
      final state = await ready(phone.container);
      expect(state.view.gifts.single.note, isNull);
    });

    test('estado, archivar y borrar', () async {
      final c = ctl(phone.container);
      await c.upsertGift(gift('g1'));
      await c.setGiftStatus('g1', GiftStatus.bought);
      expect(
        (await ready(phone.container)).view.gifts.single.status,
        GiftStatus.bought,
      );
      await c.setGiftStatus('no-existe', GiftStatus.bought);
      expect((await ready(phone.container)).view.gifts, hasLength(1));

      await c.archiveRecipient('aritz');
      expect(phone.container.read(recipientsProvider), isEmpty);
      await c.archiveRecipient('aritz', archived: false);
      expect(phone.container.read(recipientsProvider), hasLength(1));

      await c.deleteGift('g1');
      expect((await ready(phone.container)).view.gifts, isEmpty);
      // Queda la lápida.
      expect(
        (await ready(phone.container)).doc.record('gifts', 'g1')!.isDeleted,
        isTrue,
      );
    });

    test('varias escrituras a la vez no se pisan', () async {
      final c = ctl(phone.container);
      await Future.wait([
        for (var i = 0; i < 10; i++)
          c.upsertGift(gift('g$i', title: 'Regalo $i')),
      ]);
      expect((await ready(phone.container)).view.gifts, hasLength(10));
      phone.restart();
      expect((await ready(phone.container)).view.gifts, hasLength(10));
    });
  });

  group('ocasiones de serie', () {
    test(
      'Tió, Navidad, Reyes y un cumpleaños por persona con fecha',
      () async {
        final c = ctl(phone.container);
        await c.createFamily(deviceName: 'A');
        await c.upsertRecipient(aritz);
        await c.upsertRecipient(
          const Recipient(
            id: 'nora',
            name: 'Nora',
            colorIndex: 1,
            archived: false,
          ),
        );
        await c.seedDefaultOccasions('ES-CT');
        final occasions = phone.container.read(occasionsProvider);
        expect(occasions.map((o) => o.kind).toSet(), {
          OccasionKind.tio,
          OccasionKind.santa,
          OccasionKind.kings,
          OccasionKind.birthday,
        });
        final tio = occasions.firstWhere((o) => o.kind == OccasionKind.tio);
        expect((tio.month, tio.day), (12, 24));
        final santa = occasions.firstWhere((o) => o.kind == OccasionKind.santa);
        expect((santa.month, santa.day), (12, 25));
        final kings = occasions.firstWhere((o) => o.kind == OccasionKind.kings);
        expect((kings.month, kings.day), (1, 6));
        final birthdays = occasions.where(
          (o) => o.kind == OccasionKind.birthday,
        );
        expect(birthdays.single.recipientId, 'aritz');
        expect((birthdays.single.month, birthdays.single.day), (3, 14));

        // Repetir no duplica.
        await c.seedDefaultOccasions('ES-CT');
        expect(phone.container.read(occasionsProvider), hasLength(4));
      },
    );

    test('el usuario elige cuáles', () async {
      final c = ctl(phone.container);
      await c.createFamily(deviceName: 'A');
      await c.seedDefaultOccasions('ES-CT', kinds: {OccasionKind.kings});
      expect(phone.container.read(occasionsProvider).map((o) => o.kind), [
        OccasionKind.kings,
      ]);
    });

    test('al cambiar el cumpleaños de la persona cambia su ocasión', () async {
      final c = ctl(phone.container);
      await c.createFamily(deviceName: 'A');
      await c.upsertRecipient(aritz);
      await c.seedDefaultOccasions('ES', kinds: {});
      await c.upsertRecipient(
        const Recipient(
          id: 'aritz',
          name: 'Aritz',
          colorIndex: 0,
          birthMonth: 5,
          birthDay: 2,
          archived: false,
        ),
      );
      final birthday = phone.container.read(occasionsProvider).single;
      expect((birthday.month, birthday.day), (5, 2));
    });
  });

  group('providers derivados', () {
    setUp(() async {
      final c = ctl(phone.container);
      await c.createFamily(deviceName: 'A');
      await c.upsertRecipient(aritz);
      await c.upsertGiver(us);
    });

    test('giftsFor, rejilla, presupuesto y duplicados', () async {
      final c = ctl(phone.container);
      Gift paid(String id, String title, int cents) => Gift(
        id: id,
        recipientId: 'aritz',
        title: title,
        giverId: 'us',
        status: GiftStatus.bought,
        rawStatus: 'bought',
        plannedCents: cents,
        surprise: false,
        year: 2026,
      );
      await c.upsertGift(paid('a', 'Tren de madera', 2000));
      await c.upsertGift(paid('b', 'Tren de madera', 1000));
      expect(phone.container.read(giftsForProvider('aritz')), hasLength(2));
      expect(phone.container.read(giftsForProvider('nadie')), isEmpty);
      expect(phone.container.read(budgetProvider).total.plannedCents, 3000);
      expect(phone.container.read(duplicatesProvider), hasLength(1));
      final grid = phone.container.read(familyGridProvider);
      expect(grid.cell('aritz', 'us').giftCount, 2);
      expect(grid.cell('aritz', 'us').status, GridStatus.allBought);

      await c.archiveRecipient('aritz');
      expect(phone.container.read(budgetProvider).total.plannedCents, 0);
      expect(phone.container.read(duplicatesProvider), isEmpty);
    });

    test('el filtro de año recorta los regalos de los providers', () async {
      final c = ctl(phone.container);
      await c.upsertGift(gift('old', title: 'Tren').copyYear(2025));
      await c.upsertGift(gift('new', title: 'Coche'));
      expect(phone.container.read(giftsForProvider('aritz')), hasLength(2));
      phone.container.read(yearFilterProvider.notifier).set(2026);
      expect(phone.container.read(giftsForProvider('aritz')).single.id, 'new');
    });

    test('la próxima ocasión usa el reloj', () async {
      await ctl(phone.container).seedDefaultOccasions('ES-CT');
      (String, int) at(DateTime day) => withClock(Clock.fixed(day), () {
        final next = phone.container.refresh(nextOccasionProvider)!;
        return (next.occasion.id, next.days);
      });
      expect(at(DateTime(2026, 12, 20)), ('seed-tio', 4));
      expect(at(DateTime(2026, 12, 24)), ('seed-tio', 0));
      expect(at(DateTime(2026, 12, 26)), ('seed-kings', 11));
      // El cumpleaños de Aritz (14 de marzo) gana en marzo.
      expect(at(DateTime(2027, 3, 1)).$2, 13);
    });
  });
}
