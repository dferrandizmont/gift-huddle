import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/application/family_providers.dart';
import 'package:regalos/features/family/presentation/family_screen.dart'
    show occasionGroupsFor, kAllOccasionsKey, kBirthdaysKey;
import 'package:regalos/l10n/app_localizations_es.dart';

import '../helpers/memory_stores.dart';

const _aritz = Recipient(
  id: 'aritz',
  name: 'Aritz',
  colorIndex: 0,
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

Gift _gift(
  String id, {
  String recipient = 'aritz',
  String? occasion,
  String? giver = 'us',
  int year = 2026,
}) => Gift(
  id: id,
  recipientId: recipient,
  title: 'Bloques',
  giverId: giver,
  occasionId: occasion,
  status: GiftStatus.bought,
  rawStatus: 'bought',
  plannedCents: 100,
  actualCents: 80,
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
    await controller.createFamily(deviceName: 'A');
    await controller.upsertRecipient(_aritz);
    await controller.upsertRecipient(_nora);
    await controller.upsertGiver(_us);
    await controller.seedDefaultOccasions('ES');
    await controller.upsertGift(_gift('santa', occasion: 'seed-santa'));
    await controller.upsertGift(_gift('kings', occasion: 'seed-kings'));
    await controller.upsertGift(_gift('no-occasion', giver: null));
    await controller.upsertGift(
      _gift('nora', recipient: 'nora', occasion: 'seed-santa'),
    );
  });
  tearDown(() => phone.dispose());

  test('selector keys resolve All, a single occasion and birthday ids', () async {
    for (final id in ['aritz', 'nora']) {
      await controller.upsertRecipient(
        Recipient(
          id: id,
          name: id == 'aritz' ? 'Aritz' : 'Nora',
          colorIndex: id == 'aritz' ? 0 : 1,
          archived: false,
          birthMonth: 5,
          birthDay: 1,
        ),
      );
    }
    await controller.ensureBirthdayOccasions();
    final occasions = phone.container.read(familyViewProvider).occasions;
    final groups = occasionGroupsFor(
      AppLocalizationsEs(),
      occasions,
      DateTime(2026, 11, 11),
    );
    final santa = occasions.singleWhere((o) => o.kind == OccasionKind.santa);
    final single = groups.singleWhere((g) => g.ids.contains(santa.id));
    final birthdays = groups.singleWhere((g) => g.key == kBirthdaysKey);
    expect(birthdays.ids, {'birthday-aritz', 'birthday-nora'});
    for (final id in birthdays.ids) {
      await controller.upsertGift(_gift(id, occasion: id));
    }
    await controller.setRecipientSkipOccasion('aritz', santa.id, skip: true);
    final skippedBirthday = occasions.singleWhere(
      (o) => o.kind == OccasionKind.birthday && o.recipientId == 'aritz',
    );
    await controller.setRecipientSkipOccasion(
      'aritz',
      skippedBirthday.id,
      skip: true,
    );
    final expected = <String, Set<String>>{
      kAllOccasionsKey: {'kings', 'no-occasion', 'nora', 'birthday-nora'},
      single.key: {'nora'},
      birthdays.key: {'birthday-nora'},
    };
    for (final entry in expected.entries) {
      final view = phone.container.read(repartoFamilyViewProvider(entry.key));
      final grid = phone.container.read(
        familyGridForOccasionProvider(entry.key),
      );
      expect(
        view.gifts.map((g) => g.id).toSet(),
        entry.value,
        reason: entry.key,
      );
      expect(
        grid.cells.values
            .expand((row) => row.values)
            .fold<int>(0, (total, cell) => total + cell.giftCount),
        entry.value.length,
        reason: entry.key,
      );
      expect(
        grid.cell('aritz', 'us').giftCount,
        entry.key == kAllOccasionsKey
            ? 2
            : entry.key == kBirthdaysKey
            ? 1
            : 0,
      );
    }
    expect(
      phone.container.read(repartoFamilyViewProvider(null)).gifts,
      phone.container.read(repartoFamilyViewProvider(kAllOccasionsKey)).gifts,
    );
    expect(
      phone.container
          .read(familyGridForOccasionProvider(single.key))
          .excludedRecipients
          .single
          .id,
      'aritz',
    );
    expect(
      phone.container
          .read(familyGridForOccasionProvider(birthdays.key))
          .excludedRecipients,
      isEmpty,
    );

    // Resolving the String key must watch the current occasions, not cache ids.
    await controller.archiveOccasion('birthday-nora');
    expect(
      phone.container.read(repartoFamilyViewProvider(birthdays.key)).gifts,
      isEmpty,
    );
    expect(
      phone.container
          .read(familyGridForOccasionProvider(birthdays.key))
          .excludedRecipients
          .single
          .id,
      'aritz',
    );
    await controller.archiveOccasion('birthday-aritz');
    expect(
      phone.container.read(repartoFamilyViewProvider(birthdays.key)).gifts,
      isEmpty,
    );
    expect(
      phone.container
          .read(familyGridForOccasionProvider(birthdays.key))
          .excludedRecipients,
      isEmpty,
    );
  });

  test(
    'invalid and deleted occasion ids do not create stamped exclusions',
    () async {
      var before = (await state()).doc;
      for (final key in [
        '',
        'missing',
        'santa',
        kAllOccasionsKey,
        kBirthdaysKey,
      ]) {
        await controller.setRecipientSkipOccasion('aritz', key, skip: true);
        await controller.setRecipientSkipOccasion('aritz', key, skip: false);
      }
      expect((await state()).doc.canonicalJson(), before.canonicalJson());
      final deleted = before.delete(
        HlcClock(node: 'remote', last: before.maxStamp),
        Collections.occasions,
        'seed-santa',
      );
      await controller.mergeRemote(deleted, fromNode: 'remote');
      before = (await state()).doc;
      await controller.setRecipientSkipOccasion(
        'aritz',
        'seed-santa',
        skip: true,
      );
      expect((await state()).doc.canonicalJson(), before.canonicalJson());
    },
  );

  test(
    'outside Reparto is separate; People, gifts and budget are retained',
    () async {
      final before = await state();
      await controller.setRecipientInReparto('aritz', false);
      final view = (await state()).view;
      final grid = phone.container.read(familyGridProvider);
      expect(grid.recipients.map((r) => r.id), ['nora']);
      expect(grid.outsideReparto.map((r) => r.id), ['aritz']);
      expect(grid.cells.containsKey('aritz'), isFalse);
      expect(grid.hasUnassignedGifts, isFalse);
      expect(phone.container.read(outsideRepartoProvider).single.id, 'aritz');
      expect(phone.container.read(recipientsProvider), hasLength(2));
      expect(view.gifts, before.view.gifts);
      expect(view.giftsFor('aritz'), hasLength(3));
      expect(phone.container.read(budgetProvider).total.plannedCents, 300);
      expect(
        phone.container.read(repartoFamilyViewProvider(null)).gifts.single.id,
        'nora',
      );
      await controller.setRecipientInReparto('aritz', true);
      expect(phone.container.read(familyGridProvider).recipients, hasLength(2));
      expect(phone.container.read(outsideRepartoProvider), isEmpty);
      expect(
        phone.container.read(familyGridProvider).cell('aritz', 'us').giftCount,
        2,
      );
    },
  );

  test(
    'skipped occasion has excluded cells and zero totals, distinct from empty',
    () async {
      await controller.setRecipientSkipOccasion(
        'aritz',
        'seed-santa',
        skip: true,
      );
      final grid = phone.container.read(
        familyGridForOccasionProvider('seed-santa'),
      );
      expect(grid.recipients, hasLength(2));
      expect(grid.excludedRecipients.single.id, 'aritz');
      expect(
        grid.cell('aritz', 'us'),
        const GridCell(status: GridStatus.excluded),
      );
      expect(grid.unassignedCell('aritz').status, GridStatus.excluded);
      expect(grid.hasUnassignedGifts, isFalse);
      expect(grid.cell('nora', 'us').giftCount, 1);
      expect(grid.unassignedCell('nora').status, GridStatus.none);
      final view = phone.container.read(
        repartoFamilyViewProvider('seed-santa'),
      );
      expect(view.gifts.single.id, 'nora');
      expect(view.budget().ofRecipient('aritz').plannedCents, 0);
      expect(view.budget().ofOccasion('seed-santa').spentCents, 80);
      expect(view.budget().total.plannedCents, 100);
    },
  );

  test(
    'All keeps partial exclusions as rows and counts only included gifts',
    () async {
      await controller.setRecipientSkipOccasion(
        'aritz',
        'seed-santa',
        skip: true,
      );
      final grid = phone.container.read(familyGridProvider);
      expect(grid.recipients, hasLength(2));
      expect(grid.excludedRecipients, isEmpty);
      expect(grid.cell('aritz', 'us').giftCount, 1);
      expect(grid.cell('aritz', 'us').plannedCents, 100);
      expect(grid.unassignedCell('aritz').giftCount, 1);
      expect(grid.hasUnassignedGifts, isTrue);
      expect(
        grid.recipients.firstWhere((r) => r.id == 'aritz').skippedOccasionKeys,
        {'seed-santa'},
      );
      final all = phone.container.read(repartoFamilyViewProvider(null));
      expect(all.gifts.map((g) => g.id).toSet(), {
        'kings',
        'no-occasion',
        'nora',
      });
      expect(all.budget().ofOccasion('seed-santa').plannedCents, 100);
      expect(all.budget().total.plannedCents, 200);
      // Only Reparto totals change: existing expenses still belong to Budget.
      expect(phone.container.read(budgetProvider).total.plannedCents, 300);
      await controller.setRecipientSkipOccasion(
        'aritz',
        'seed-kings',
        skip: true,
      );
      expect(phone.container.read(familyGridProvider).recipients, hasLength(2));
      expect(
        phone.container.read(familyGridProvider).excludedRecipients,
        isEmpty,
      );
    },
  );

  test(
    'groups exclude a row only when every selected occasion is skipped',
    () async {
      await controller.setRecipientSkipOccasion(
        'aritz',
        'seed-santa',
        skip: true,
      );
      final keys = {'seed-santa', 'seed-kings'};
      var view = (await state()).view;
      expect(view.grid(occasionKeys: keys).cell('aritz', 'us').giftCount, 1);
      expect(view.grid(occasionKeys: keys).excludedRecipients, isEmpty);
      expect(
        view.forReparto(occasionKeys: keys).gifts.map((g) => g.id).toSet(),
        {'kings', 'nora'},
      );
      await controller.setRecipientSkipOccasion(
        'aritz',
        'seed-kings',
        skip: true,
      );
      view = (await state()).view;
      expect(
        view.grid(occasionKeys: keys).excludedRecipients.single.id,
        'aritz',
      );
      expect(
        view.grid(occasionKeys: keys).cell('aritz', 'us').status,
        GridStatus.excluded,
      );
      expect(
        view.grid(occasionKeys: {}).cell('aritz', 'us').status,
        GridStatus.none,
      );
      expect(view.forReparto(occasionKeys: {}).gifts, isEmpty);
      final noGivers = FamilyView(
        recipients: view.recipients,
        givers: [],
        occasions: [],
        gifts: view.gifts,
      ).grid(occasionKeys: keys);
      expect(noGivers.excludedRecipients.single.id, 'aritz');
      expect(noGivers.unassignedCell('aritz').status, GridStatus.excluded);
      expect(noGivers.hasUnassignedGifts, isTrue); // Nora's gift remains.
    },
  );

  test(
    'each setter touches only its field; repeated writes keep HLC',
    () async {
      final before = (await state()).doc.record(
        Collections.recipients,
        'aritz',
      )!;
      await controller.setRecipientInReparto('aritz', false);
      await controller.setRecipientSkipOccasion(
        'aritz',
        'seed-santa',
        skip: true,
      );
      final after = (await state()).doc.record(
        Collections.recipients,
        'aritz',
      )!;
      for (final field in before.fields.keys.where((f) => f != 'inReparto')) {
        expect(after.field(field), before.field(field), reason: field);
      }
      await controller.setRecipientInReparto('aritz', false);
      await controller.setRecipientSkipOccasion(
        'aritz',
        'seed-santa',
        skip: true,
      );
      expect(
        (await state()).doc.record(Collections.recipients, 'aritz')!.fields,
        after.fields,
      );
      await controller.setRecipientSkipOccasion(
        'aritz',
        'seed-santa',
        skip: false,
      );
      final included = (await state()).doc.record(
        Collections.recipients,
        'aritz',
      )!;
      final field = Recipient.skipOccasionField('seed-santa');
      expect(included[field], isFalse);
      expect(included.field(field)!.stamp > after.field(field)!.stamp, isTrue);
      expect(included.field('inReparto'), after.field('inReparto'));
      phone.restart();
      expect(
        (await state()).view.recipients
            .firstWhere((r) => r.id == 'aritz')
            .skipOccasions,
        {'seed-santa': false},
      );
      expect(phone.container.read(outsideRepartoProvider).single.id, 'aritz');
    },
  );

  test(
    'queued setters preserve a remote change to a different entry',
    () async {
      final current = await state();
      final remote = current.doc.set(
        HlcClock(node: 'remote', last: current.doc.maxStamp),
        Collections.recipients,
        'aritz',
        {Recipient.skipOccasionField('seed-kings'): true},
      );
      final merge = controller.mergeRemote(remote, fromNode: 'remote');
      final edit = controller.setRecipientSkipOccasion(
        'aritz',
        'seed-santa',
        skip: true,
      );
      await merge;
      await edit;
      expect(
        (await state()).view.recipients
            .firstWhere((r) => r.id == 'aritz')
            .skipOccasions,
        {'seed-santa': true, 'seed-kings': true},
      );
    },
  );

  test(
    'missing/deleted recipients are untouched; archived people stay separate',
    () async {
      final before = (await state()).doc;
      await controller.setRecipientInReparto('missing', false);
      await controller.setRecipientSkipOccasion(
        'missing',
        'seed-santa',
        skip: true,
      );
      expect((await state()).doc.canonicalJson(), before.canonicalJson());
      final deleted = before.delete(
        HlcClock(node: 'remote', last: before.maxStamp),
        Collections.recipients,
        'aritz',
      );
      await controller.mergeRemote(deleted, fromNode: 'remote');
      final tombstone = (await state()).doc;
      await controller.setRecipientInReparto('aritz', false);
      await controller.setRecipientSkipOccasion(
        'aritz',
        'seed-santa',
        skip: true,
      );
      expect((await state()).doc.canonicalJson(), tombstone.canonicalJson());
      await controller.setRecipientInReparto('nora', false);
      await controller.archiveRecipient('nora');
      expect(phone.container.read(outsideRepartoProvider), isEmpty);
      expect((await state()).fullView.grid().outsideReparto, isEmpty);
      await controller.archiveRecipient('nora', archived: false);
      expect(phone.container.read(outsideRepartoProvider).single.id, 'nora');
    },
  );

  test('existing person editors cannot reset Reparto preferences', () async {
    await controller.setRecipientInReparto('aritz', false);
    await controller.setRecipientSkipOccasion(
      'aritz',
      'seed-santa',
      skip: true,
    );
    await controller.setRecipientSkipOccasion(
      'aritz',
      'seed-kings',
      skip: false,
    );
    final before = (await state()).doc.record(Collections.recipients, 'aritz')!;
    await controller.upsertRecipient(
      const Recipient(
        id: 'aritz',
        name: 'Leo',
        colorIndex: 0,
        archived: false,
        inReparto: true,
        skipOccasions: {'seed-santa': false, 'seed-kings': true, 'new': true},
      ),
    );
    final after = (await state()).doc.record(Collections.recipients, 'aritz')!;
    expect(after['name'], 'Leo');
    for (final key in [
      'inReparto',
      Recipient.skipOccasionField('seed-santa'),
      Recipient.skipOccasionField('seed-kings'),
    ]) {
      expect(after.field(key), before.field(key));
    }
    expect(after.field(Recipient.skipOccasionField('new')), isNull);
    await controller.upsertRecipient(
      const Recipient(
        id: 'leo',
        name: 'Leo',
        colorIndex: 2,
        archived: false,
        inReparto: false,
        skipOccasions: {'seed-santa': true},
      ),
    );
    final created = (await state()).view.recipients.firstWhere(
      (r) => r.id == 'leo',
    );
    expect(created.inReparto, isFalse);
    expect(created.skipsOccasion('seed-santa'), isTrue);
  });

  test(
    'upsert of a legacy recipient leaves absent Reparto fields absent',
    () async {
      final current = await state();
      final legacyFields = <String, Object?>{
        'name': 'Leo',
        'colorIndex': 2,
        'archived': false,
        'relation': null,
        'birthMonth': null,
        'birthDay': null,
        'birthYear': null,
      };
      final legacy = FamilyDoc.empty(current.doc.listId).set(
        HlcClock(node: 'old', last: current.doc.maxStamp),
        Collections.recipients,
        'leo',
        legacyFields,
      );
      await controller.mergeRemote(legacy, fromNode: 'old');
      await controller.upsertRecipient(
        const Recipient(id: 'leo', name: 'Leo', colorIndex: 1, archived: false),
      );
      phone.restart();
      final saved = await state();
      final record = saved.doc.record(Collections.recipients, 'leo')!;
      expect(record['colorIndex'], 1);
      expect(record.field('inReparto'), isNull);
      expect(
        record.fields.keys.where(
          (k) => k.startsWith(Recipient.skipOccasionFieldPrefix),
        ),
        isEmpty,
      );
      final recipient = saved.view.recipients.singleWhere((r) => r.id == 'leo');
      expect(recipient.inReparto, isTrue);
      expect(recipient.skipOccasions, isEmpty);
    },
  );

  test(
    'Reparto history filters every year with the same occasion rules',
    () async {
      await controller.upsertGift(
        _gift('old-santa', occasion: 'seed-santa', year: 2025),
      );
      await controller.upsertGift(
        _gift('old-kings', occasion: 'seed-kings', year: 2025),
      );
      await controller.upsertGift(
        _gift('old-outside', recipient: 'nora', year: 2025),
      );
      await controller.setRecipientSkipOccasion(
        'aritz',
        'seed-santa',
        skip: true,
      );
      await controller.setRecipientInReparto('nora', false);
      phone.container.read(yearFilterProvider.notifier).set(2026);
      final all = phone.container.read(
        repartoFamilyViewProvider(kAllOccasionsKey),
      );
      expect(all.previousYearsGifts('aritz', 2026).map((g) => g.id), [
        'old-kings',
      ]);
      expect(all.previousYearsGifts('nora', 2026), isEmpty);
      expect(
        phone.container
            .read(repartoFamilyViewProvider('seed-santa'))
            .previousYearsGifts('aritz', 2026),
        isEmpty,
      );
      expect(
        phone.container
            .read(familyViewProvider)
            .previousYearsGifts('aritz', 2026)
            .map((g) => g.id)
            .toSet(),
        {'old-santa', 'old-kings'},
      );
    },
  );

  test('year filter is respected by filtered Reparto providers', () async {
    await controller.upsertGift(
      _gift('old', occasion: 'seed-kings', year: 2025),
    );
    phone.container.read(yearFilterProvider.notifier).set(2025);
    expect(
      phone.container
          .read(familyGridForOccasionProvider('seed-kings'))
          .cell('aritz', 'us')
          .giftCount,
      1,
    );
    expect(
      phone.container.read(repartoFamilyViewProvider(null)).gifts.single.id,
      'old',
    );
    await controller.setRecipientSkipOccasion(
      'aritz',
      'seed-kings',
      skip: true,
    );
    expect(
      phone.container.read(repartoFamilyViewProvider(null)).gifts,
      isEmpty,
    );
    expect(
      phone.container
          .read(familyGridForOccasionProvider('seed-kings'))
          .cell('aritz', 'us')
          .status,
      GridStatus.excluded,
    );
  });
}
