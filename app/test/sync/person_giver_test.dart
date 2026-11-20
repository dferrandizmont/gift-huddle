import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/application/family_providers.dart';
import 'package:regalos/features/family/application/gift_logic.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/family/domain/delete_impact.dart';

import '../helpers/memory_stores.dart';

const nora = Recipient(
  id: 'nora',
  name: 'Nora',
  colorIndex: 2,
  archived: false,
);
const leo = Recipient(id: 'leo', name: 'Leo', colorIndex: 3, archived: false);

Gift gift(
  String id, {
  String person = 'leo',
  String? giver,
  String? occasion,
  int cents = 1200,
}) => Gift(
  id: id,
  recipientId: person,
  giverId: giver,
  occasionId: occasion,
  title: id,
  status: GiftStatus.bought,
  rawStatus: 'bought',
  plannedCents: cents,
  surprise: false,
  year: 2026,
);

Giver manual(String id, {bool pays = false}) => Giver(
  id: id,
  name: 'Nora',
  colorIndex: 0,
  householdPays: pays,
  archived: false,
);

// Fields written by Giver.toFields and upsertGiver in v1.0.3.
Map<String, Object?> legacyFields({bool pays = false}) => {
  'name': 'Nora',
  'colorIndex': 0,
  'householdPays': pays,
  'archived': false,
};

SyncRecord giverRecord(FamilyDoc doc, String id) =>
    doc.record(Collections.givers, id)!;

FamilyDoc roundTrip(FamilyDoc doc) =>
    FamilyDoc.fromJson(jsonDecode(doc.canonicalJson()) as Map<String, Object?>);

FamilyController controller(FakePhone phone) =>
    phone.container.read(familyControllerProvider.notifier);

FamilyDoc common(FakePhone phone) =>
    phone.container.read(familyControllerProvider).requireValue.doc;

void main() {
  test('deterministic id has a stable wire format', () {
    expect(
      Giver.nextPersonGiverId(FamilyDoc.empty('family'), nora.id),
      'person-giver:bnLb8RbQWSFuB1OA1L_FZg:0',
    );
  });

  test('v1.0.3 fields round-trip and its edits preserve unknown HLCs', () {
    final oldClock = HlcClock(node: 'old');
    final old = FamilyDoc.empty('family')
        .set(oldClock, Collections.givers, 'manual', legacyFields());
    expect(
      Giver.fromRecord(giverRecord(roundTrip(old), 'manual')),
      manual('manual'),
    );
    final linked = old.set(oldClock, Collections.givers, 'manual', {
      Giver.recipientIdField: nora.id,
      'future': ['Leo', 7],
    });
    final edited = roundTrip(linked).setChanged(
      HlcClock(node: 'old', last: linked.maxStamp),
      Collections.givers,
      'manual',
      legacyFields(pays: true),
    );
    final record = giverRecord(roundTrip(edited), 'manual');
    expect(Giver.fromRecord(record)?.householdPays, isTrue);
    for (final field in [
      Giver.recipientIdField,
      'future',
      'name',
      'colorIndex',
      'archived',
    ]) {
      final before = giverRecord(linked, 'manual').field(field)!;
      expect(record.field(field)?.value, before.value);
      expect(record.field(field)?.stamp, before.stamp);
    }
  });

  test(
    'an unlink writes a null with its own HLC and wins over an older link',
    () async {
      final phone = FakePhone();
      addTearDown(phone.dispose);
      final c = controller(phone);
      await c.createFamily(deviceName: 'Aritz');
      await c.upsertRecipient(nora);
      await c.upsertRecipient(leo);
      await c.upsertGiver(manual('manual'));
      await c.linkGiver('manual', nora.id);
      final before = common(phone);
      final oldLink = before.set(
        HlcClock(node: 'remote', last: before.maxStamp),
        Collections.givers,
        'manual',
        {Giver.recipientIdField: leo.id},
      );
      await c.mergeRemote(
        before.set(
          HlcClock(node: 'remote', last: oldLink.maxStamp),
          Collections.meta,
          'future',
          {'marker': true},
        ),
        fromNode: 'remote',
      );
      expect(
        await c.unlinkGiver('manual', expectedPersonId: nora.id),
        nora.name,
      );
      final cleared = common(phone);
      final removal = giverRecord(
        cleared,
        'manual',
      ).field(Giver.recipientIdField)!;
      expect(removal.value, isNull);
      for (final merged in [oldLink.merge(cleared), cleared.merge(oldLink)]) {
        expect(
          giverRecord(merged, 'manual').field(Giver.recipientIdField),
          removal,
        );
      }
    },
  );

  group('People as givers', () {
    late FakePhone a;
    late FakePhone b;
    late FamilyController ca;
    late FamilyController cb;

    setUp(() async {
      a = FakePhone();
      b = FakePhone();
      ca = controller(a);
      cb = controller(b);
      await ca.createFamily(deviceName: 'Aritz');
      await ca.upsertRecipient(nora);
      await ca.upsertRecipient(leo);
      final base = common(a);
      await cb.installV2(
        listId: base.listId,
        node: 'second-phone',
        key: ca.familyKey!,
        doc: base,
        deviceName: 'Leo',
      );
    });
    tearDown(() {
      a.dispose();
      b.dispose();
    });

    test('two offline creations share one id and keep both gifts in either merge order', () async {
      await ca.upsertGift(gift('book'));
      expect(
        await ca.assignPersonAsGiver('book', nora.id),
        GiftWriteResult.saved,
      );
      expect(
        await cb.upsertGiftWithGiverPerson(gift('puzzle'), nora.id),
        GiftWriteResult.saved,
      );
      final da = common(a);
      final db = common(b);
      final id = FamilyView.fromDoc(da).givers.single.id;
      expect(id, FamilyView.fromDoc(db).givers.single.id);
      expect(id, startsWith(Giver.personIdPrefix));
      expect(id, endsWith(':0'));
      expect(FamilyView.fromDoc(da).givers.single.householdPays, isFalse);
      final merged = da.merge(db);
      expect(merged.canonicalJson(), db.merge(da).canonicalJson());
      expect(
        merged.merge(db).merge(da).canonicalJson(),
        merged.canonicalJson(),
      );
      for (final doc in [merged, db.merge(da)]) {
        final view = FamilyView.fromDoc(doc);
        expect(view.givers, hasLength(1));
        expect(view.gifts.map((g) => g.giverId), everyElement(id));
        expect(view.grid().cell(leo.id, id).giftCount, 2);
      }
      await ca.mergeRemote(db, fromNode: 'second-phone');
      final repeat = await ca.mergeRemote(db, fromNode: 'second-phone');
      expect(repeat.docChanged, isFalse);
    });

    test('a stale payer editor preserves the link and its exact HLC', () async {
      await ca.upsertGiver(manual('manual'));
      await ca.linkGiver('manual', nora.id);
      final before = giverRecord(common(a), 'manual');
      await ca.upsertGiver(manual('manual', pays: true));
      final after = giverRecord(common(a), 'manual');
      expect(
        after.field(Giver.recipientIdField),
        before.field(Giver.recipientIdField),
      );
      expect(after.field('colorIndex'), before.field('colorIndex'));
      expect(after['householdPays'], isTrue);
    });

    test(
      'link and unlink reject stale confirmations after a remote relink',
      () async {
        await ca.upsertGiver(manual('manual', pays: true));
        await ca.linkGiver('manual', nora.id);
        await cb.mergeRemote(common(a), fromNode: 'first-phone');
        expect(
          await cb.linkGiver('manual', leo.id, expectedPersonId: nora.id),
          isTrue,
        );
        await ca.mergeRemote(common(b), fromNode: 'second-phone');
        final before = common(a);
        final bytes = a.files.files['family.doc'];
        expect(
          await ca.unlinkGiver('manual', expectedPersonId: nora.id),
          isNull,
        );
        expect(await ca.linkGiver('manual', nora.id), isFalse);
        expect(
          await ca.linkGiver('manual', nora.id, expectedPersonId: nora.id),
          isFalse,
        );
        expect(common(a), same(before));
        expect(a.files.files['family.doc'], same(bytes));

        const renamed = Recipient(
          id: 'leo',
          name: 'Aritz',
          colorIndex: 8,
          archived: false,
        );
        await cb.upsertRecipient(renamed);
        await ca.mergeRemote(common(b), fromNode: 'second-phone');
        expect(
          await ca.unlinkGiver('manual', expectedPersonId: leo.id),
          renamed.name,
        );
        final unlinked = FamilyView.fromDoc(common(a))
            .giversByOriginalId['manual']!;
        expect(unlinked.recipientId, isNull);
        expect(unlinked.name, renamed.name);
        expect(unlinked.colorIndex, renamed.colorIndex);
        expect(unlinked.householdPays, isTrue);
        expect(
          await ca.unlinkGiver('manual', expectedPersonId: leo.id),
          isNull,
        );
      },
    );

    test('new generations skip explicitly unlinked records and permanent tombstones', () async {
      await ca.upsertGift(gift('book'));
      await ca.assignPersonAsGiver('book', nora.id);
      final first = FamilyView.fromDoc(common(a)).giverForPerson(nora.id)!.id;
      await ca.unlinkGiver(first, expectedPersonId: nora.id);
      await ca.upsertGift(gift('puzzle'));
      await ca.assignPersonAsGiver('puzzle', nora.id);
      final second = FamilyView.fromDoc(common(a)).giverForPerson(nora.id)!.id;
      expect(second, endsWith(':1'));
      await ca.deleteGiver(second);
      await ca.upsertGift(gift('bike'));
      await ca.assignPersonAsGiver('bike', nora.id);
      final doc = common(a);
      final view = FamilyView.fromDoc(doc);
      final third = view.giverForPerson(nora.id)!.id;
      expect(third, endsWith(':2'));
      expect(giverRecord(doc, second).isDeleted, isTrue);
      expect(view.gifts.singleWhere((g) => g.id == 'book').giverId, first);
      expect(view.gifts.singleWhere((g) => g.id == 'puzzle').giverId, isNull);
      expect(view.gifts.singleWhere((g) => g.id == 'bike').giverId, third);
    });

    test('independent renaming and recoloring converge with idempotent copy repair', () async {
      await ca.upsertGiver(manual('manual'));
      await ca.linkGiver('manual', nora.id);
      await cb.mergeRemote(common(a), fromNode: 'first-phone');
      await ca.upsertRecipient(
        const Recipient(
          id: 'nora',
          name: 'Aritz',
          colorIndex: 2,
          archived: false,
        ),
      );
      await cb.upsertRecipient(
        const Recipient(
          id: 'nora',
          name: 'Nora',
          colorIndex: 5,
          archived: false,
        ),
      );
      final da = common(a);
      final db = common(b);
      final merged = da.merge(db);
      expect(giverRecord(merged, 'manual')['name'], 'Aritz');
      expect(giverRecord(merged, 'manual')['colorIndex'], 5);
      final legacy = merged.set(
        HlcClock(node: 'old', last: merged.maxStamp),
        Collections.givers,
        'manual',
        {'name': 'Leo', 'future': true},
      );
      final snapshot = legacy.canonicalJson();
      final read = FamilyView.fromDoc(legacy).resolveGiver('manual')!;
      expect(read.name, 'Aritz');
      expect(read.colorIndex, 5);
      expect(legacy.canonicalJson(), snapshot);
      await ca.mergeRemote(legacy, fromNode: 'old');
      await cb.mergeRemote(common(a), fromNode: 'first-phone');
      expect(common(b).canonicalJson(), common(a).canonicalJson());
      final copy = giverRecord(common(a), 'manual');
      expect(copy['name'], 'Aritz');
      expect(
        copy.field('colorIndex'),
        giverRecord(legacy, 'manual').field('colorIndex'),
      );
      expect(
        copy.field('future'),
        giverRecord(legacy, 'manual').field('future'),
      );
      final doc = common(a);
      expect(
        reconcileGiverCopies(doc, HlcClock(node: 'a', last: doc.maxStamp)),
        same(doc),
      );
      expect(
        (await ca.mergeRemote(legacy, fromNode: 'old')).docChanged,
        isFalse,
      );
    });

    test('aliases share the grid, details and filter while keeping original payers', () async {
      await ca.upsertGiver(manual('a-other'));
      await ca.upsertGiver(manual('z-house', pays: true));
      await ca.upsertGiver(manual('homonym'));
      await ca.linkGiver('a-other', nora.id);
      await ca.linkGiver('z-house', nora.id);
      await ca.upsertGift(gift('book', giver: 'z-house'));
      await ca.upsertGift(gift('bike', giver: 'a-other', cents: 5000));
      await ca.upsertGift(gift('puzzle', giver: 'homonym', cents: 3000));
      final view = FamilyView.fromDoc(common(a));
      expect(
        view.givers.map((g) => g.id),
        unorderedEquals(['a-other', 'homonym']),
      );
      expect(view.allGivers, hasLength(3));
      expect(view.resolveGiver('z-house')?.id, 'a-other');
      expect(view.resolveGiver('homonym')?.id, 'homonym');
      final grid = view.grid();
      final detail = view.forReparto().gifts.where(
        (g) => const GiftFilter(giverId: 'z-house').matches(g, view: view),
      );
      expect(grid.cell(leo.id, 'a-other').giftCount, 2);
      expect(detail.map((g) => g.id), unorderedEquals(['book', 'bike']));
      expect(view.budget().total.spentCents, 1200);
      final impact = DeleteImpact.ofGiverColumn(view, 'a-other');
      expect(impact.gifts, 2);
      expect(impact.paysFromHousehold, isTrue);
      await ca.archiveGiver('a-other');
      final next = FamilyView.fromDoc(common(a));
      expect(next.resolveGiver('a-other')?.id, 'z-house');
      expect(
        next.repartoGiverId(next.gifts.singleWhere((g) => g.id == 'bike')),
        isNull,
      );
      expect(next.grid().cell(leo.id, 'z-house').giftCount, 1);
      expect(next.forReparto().gifts.map((gift) => gift.id), [
        'book',
        'puzzle',
      ]);
      expect(next.budget().total.spentCents, 1200);
      await ca.archiveGiver('z-house');
      final archived = FamilyView.fromDoc(common(a), includeArchived: true);
      expect(archived.giverForPerson(nora.id)?.id, 'a-other');
      expect(archived.budget().total.spentCents, 0);
    });

    test(
      'candidates use identity and person/giver archives are independent',
      () async {
        await ca.upsertGiver(manual('homonym'));
        await ca.upsertOccasion(
          const Occasion(
            id: 'kings',
            kind: OccasionKind.kings,
            rawKind: 'kings',
            name: 'Reyes',
            month: 1,
            day: 6,
            recurring: true,
            archived: false,
          ),
        );
        await ca.upsertGift(gift('book', occasion: 'kings'));
        List<String> candidates() => a.container
            .read(giftGiverPeopleProvider('book'))
            .map((person) => person.id)
            .toList();
        expect(candidates(), [nora.id]);
        expect(
          await ca.assignPersonAsGiver('book', leo.id),
          GiftWriteResult.invalidPair,
        );
        expect(
          await ca.assignPersonAsGiver('book', nora.id),
          GiftWriteResult.saved,
        );
        final id = FamilyView.fromDoc(common(a)).giverForPerson(nora.id)!.id;
        expect(id, isNot('homonym'));
        expect(candidates(), isEmpty);
        await ca.upsertGift(gift('received', person: nora.id));
        expect(
          await ca.setGiftGiver('received', id),
          GiftWriteResult.invalidPair,
        );
        await ca.setRecipientSkipOccasion(nora.id, 'kings', skip: true);
        await ca.setRecipientInReparto(nora.id, false);
        final excluded = FamilyView.fromDoc(common(a))
            .grid(occasionKeys: {'kings'});
        expect(excluded.recipients.map((person) => person.id), [leo.id]);
        expect(excluded.cell(leo.id, id).giftCount, 1);
        await ca.archiveRecipient(nora.id);
        expect(
          await ca.assignPersonAsGiver('book', nora.id),
          GiftWriteResult.giverPersonArchived,
        );
        expect(
          FamilyView.fromDoc(common(a)).grid().cell(leo.id, id).giftCount,
          1,
        );
        await ca.archiveGiver(id);
        expect(candidates(), isEmpty);
        await ca.archiveRecipient(nora.id, archived: false);
        expect(candidates(), [nora.id]);
        expect(
          FamilyView.fromDoc(common(a))
              .forReparto()
              .giverPeopleFor(leo.id)
              .map((person) => person.id),
          [nora.id],
        );
        final archived = FamilyView.fromDoc(common(a));
        expect(archived.giftsFor(nora.id).single.id, 'received');
        expect(archived.resolveGiver(id)?.archived, isTrue);
        expect(archived.grid().cell(leo.id, id).giftCount, 0);
        expect(
          await ca.assignPersonAsGiver('book', nora.id),
          GiftWriteResult.saved,
        );
        final recovered = FamilyView.fromDoc(common(a)).giverForPerson(nora.id);
        expect(recovered?.id, id);
        expect(recovered?.archived, isFalse);
        expect(candidates(), isEmpty);
      },
    );

    test(
      'gift writes report unavailable records without recovering a giver',
      () async {
        final giver = (await ca.addPersonAsGiver(nora.id))!;
        await ca.archiveGiver(giver.id);
        final original = gift('book');
        await ca.upsertGift(original);
        final before = common(a);
        final bytes = a.files.files['family.doc'];
        expect(
          await ca.upsertGiftWithGiverPerson(
            gift('book', person: nora.id),
            nora.id,
            original: original,
          ),
          GiftWriteResult.invalidPair,
        );
        expect(
          await ca.setGiftGiver(original.id, giver.id),
          GiftWriteResult.giverArchived,
        );
        expect(
          await ca.setGiftGiver(original.id, 'missing'),
          GiftWriteResult.giverUnavailable,
        );
        expect(
          await ca.assignPersonAsGiver(original.id, 'missing'),
          GiftWriteResult.giverPersonUnavailable,
        );
        expect(common(a), same(before));
        expect(a.files.files['family.doc'], same(bytes));

        expect(
          await ca.upsertGiftWithGiverPerson(
            original,
            nora.id,
            original: original,
          ),
          GiftWriteResult.saved,
        );
        final updated = FamilyView.fromDoc(common(a));
        expect(updated.gifts.single.giverId, giver.id);
        expect(updated.giverForPerson(nora.id)?.archived, isFalse);
        await ca.deleteGiver(giver.id);
        expect(
          await ca.setGiftGiver(original.id, giver.id),
          GiftWriteResult.giverUnavailable,
        );
        await ca.deleteGift(original.id);
        final afterDelete = common(a);
        expect(
          await ca.setGiftGiver(original.id, null),
          GiftWriteResult.giftDeleted,
        );
        expect(
          await ca.assignPersonAsGiver(original.id, nora.id),
          GiftWriteResult.giftDeleted,
        );
        expect(
          await ca.upsertGiftWithGiverPerson(
            original,
            nora.id,
            original: original,
          ),
          GiftWriteResult.giftDeleted,
        );
        expect(common(a), same(afterDelete));
      },
    );

    test(
      'the person label follows the person when their alias changes',
      () async {
        FamilyView view() => FamilyView.fromDoc(common(a));
        expect(view().giverForPerson(nora.id), isNull);
        expect(view().giverForPersonLabel(nora.id), nora.name);
        final giver = (await ca.addPersonAsGiver(nora.id))!;
        expect(view().giverForPerson(nora.id)?.id, giver.id);
        expect(view().giverForPersonLabel(nora.id), nora.name);
        await ca.linkGiver(giver.id, leo.id, expectedPersonId: nora.id);
        expect(view().giverForPerson(nora.id), isNull);
        expect(view().giverForPersonLabel(nora.id), nora.name);
        expect(view().giverForPersonLabel(leo.id), leo.name);
      },
    );

    test('person deletion keeps giver history and column deletion tombstones all aliases', () async {
      await ca.upsertGiver(manual('a-house', pays: true));
      await ca.upsertGiver(manual('z-other'));
      await ca.linkGiver('a-house', nora.id);
      await ca.linkGiver('z-other', nora.id);
      await ca.upsertGift(gift('book', giver: 'a-house'));
      await ca.upsertGift(gift('puzzle', giver: 'z-other'));
      await ca.upsertGift(gift('received', person: nora.id));
      await ca.archiveGiver('z-other');
      final aliasImpact = await ca.giverAliasDeleteImpact('a-house');
      expect(aliasImpact.linkedPersonExists, isTrue);
      final beforeDeletes = common(a);
      final personImpact = await ca.recipientDeleteImpact(nora.id);
      expect(personImpact.hasLinkedGiver, isTrue);
      await ca.deleteRecipient(nora.id, expectedImpact: personImpact);
      var view = FamilyView.fromDoc(common(a));
      expect(view.allRecipientsById[nora.id], isNull);
      expect(view.giverForPersonLabel(nora.id), isNull);
      final orphanImpact = await ca.giverAliasDeleteImpact('a-house');
      expect(orphanImpact.linkedPersonExists, isFalse);
      expect(orphanImpact.matches(aliasImpact), isFalse);
      expect(view.resolveGiver('a-house')?.name, 'Nora');
      expect(view.resolveGiver('z-other')?.colorIndex, nora.colorIndex);
      expect(view.gifts.map((g) => g.id), unorderedEquals(['book', 'puzzle']));
      expect(view.budget().total.spentCents, 1200);
      final column = await ca.giverColumnDeleteImpact('a-house');
      expect(column.affectedAliases.map((g) => g.id), ['a-house', 'z-other']);
      await ca.deleteGiverColumn('a-house', expectedImpact: column);
      for (final id in ['a-house', 'z-other']) {
        expect(giverRecord(common(a), id).isDeleted, isTrue);
      }
      final lateGift = beforeDeletes.set(
        HlcClock(node: 'remote', last: beforeDeletes.maxStamp),
        Collections.gifts,
        'late',
        gift('late', giver: 'z-other').toFields(),
      );
      await ca.mergeRemote(lateGift, fromNode: 'remote');
      view = FamilyView.fromDoc(common(a));
      expect(
        view.gifts.map((g) => g.id),
        unorderedEquals(['book', 'puzzle', 'late']),
      );
      expect(view.grid().unassignedCell(leo.id).giftCount, 3);
      expect(view.budget().total.spentCents, 0);
      expect(view.resolveGiver('z-other'), isNull);
    });

    test(
      'an archived alias delete leaves the active row and rechecks its gifts',
      () async {
        await ca.upsertGiver(manual('a-active', pays: true));
        await ca.upsertGiver(manual('z-archived'));
        await ca.linkGiver('a-active', nora.id);
        await ca.linkGiver('z-archived', nora.id);
        await ca.upsertGift(gift('book', giver: 'a-active'));
        await ca.upsertGift(gift('puzzle', giver: 'z-archived'));
        await ca.archiveGiver('z-archived');
        final row = await ca.giverAliasDeleteImpact('z-archived');
        final column = await ca.giverColumnDeleteImpact('a-active');
        expect(row.affectedAliases.map((g) => g.id), ['z-archived']);
        expect(row.affectedGifts.map((g) => g.id), ['puzzle']);
        expect(column.affectedGifts.map((g) => g.id), ['book', 'puzzle']);

        await ca.setGiftGiver('puzzle', null);
        final before = common(a);
        await expectLater(
          ca.deleteGiverAlias('z-archived', expectedImpact: row),
          throwsA(
            isA<DeleteImpactChanged>().having(
              (e) => e.current.affectedGifts,
              'gifts',
              isEmpty,
            ),
          ),
        );
        expect(common(a), same(before));
        await ca.deleteGiverAlias(
          'z-archived',
          expectedImpact: await ca.giverAliasDeleteImpact('z-archived'),
        );
        expect(giverRecord(common(a), 'z-archived').isDeleted, isTrue);
        expect(giverRecord(common(a), 'a-active').isDeleted, isFalse);
        expect(
          FamilyView.fromDoc(common(a)).giftsFor(leo.id).first.giverId,
          'a-active',
        );
        await expectLater(
          ca.deleteGiverColumn('a-active', expectedImpact: column),
          throwsA(isA<DeleteImpactChanged>()),
        );
      },
    );

    test('role changes validate the final giver and preserve old assignments on other edits', () async {
      await ca.upsertGiver(manual('nora-giver'));
      await ca.linkGiver('nora-giver', nora.id);
      final book = gift('book', giver: 'nora-giver');
      await ca.upsertGift(book);
      expect(
        await ca.upsertGift(
          gift('book', person: nora.id, giver: 'nora-giver'),
          original: book,
        ),
        isFalse,
      );
      final existing = common(a);
      final remote = existing.set(
        HlcClock(node: 'remote', last: existing.maxStamp),
        Collections.gifts,
        book.id,
        {'recipientId': nora.id},
      );
      await ca.mergeRemote(remote, fromNode: 'remote');
      final historical = FamilyView.fromDoc(common(a)).allGifts.single;
      expect(
        await ca.upsertGift(
          gift('book', person: nora.id, giver: 'nora-giver', cents: 2000),
          original: historical,
        ),
        isTrue,
      );
      expect(
        FamilyView.fromDoc(common(a)).allGifts.single.giverId,
        'nora-giver',
      );

      final draft = gift('new', giver: 'nora-giver');
      final beforeDelete = common(a);
      await ca.mergeRemote(
        beforeDelete.delete(
          HlcClock(node: 'remote', last: beforeDelete.maxStamp),
          Collections.givers,
          'nora-giver',
        ),
        fromNode: 'remote',
      );
      expect(await ca.upsertGift(draft), isFalse);
      expect(common(a).record(Collections.gifts, draft.id), isNull);
      final withDeletedGiver = FamilyView.fromDoc(common(a)).allGifts.single;
      expect(
        await ca.upsertGift(
          gift('book', person: nora.id, giver: 'nora-giver', cents: 3000),
          original: withDeletedGiver,
        ),
        isTrue,
      );
      expect(
        FamilyView.fromDoc(common(a)).allGifts.single.giverId,
        'nora-giver',
      );
    });

    test(
      'opening stale copies is read-only and sync repairs them once',
      () async {
        final giver = (await ca.addPersonAsGiver(nora.id))!;
        final doc = common(a);
        final stale = doc.set(
          HlcClock(node: 'legacy', last: doc.maxStamp),
          Collections.givers,
          giver.id,
          {'name': 'Leo', 'colorIndex': 8},
        );
        await a.container.read(familyStoreProvider).saveDoc(stale);
        final beforeOpening = a.files.files['family.doc'];
        a.restart();
        final state = await a.container.read(familyControllerProvider.future);
        expect(state.view.giverForPerson(nora.id)?.name, nora.name);
        expect(state.view.giverForPerson(nora.id)?.colorIndex, nora.colorIndex);
        expect(giverRecord(state.doc, giver.id)['name'], 'Leo');
        expect(a.files.files['family.doc'], same(beforeOpening));

        final reopened = controller(a);
        final repaired = await reopened.mergeRemote(stale, fromNode: 'legacy');
        expect(repaired.docChanged, isTrue);
        final afterSync = a.files.files['family.doc'];
        expect(afterSync, isNot(same(beforeOpening)));
        final corrected = giverRecord(common(a), giver.id);
        expect(
          (corrected['name'], corrected['colorIndex']),
          (nora.name, nora.colorIndex),
        );
        expect(
          (await reopened.mergeRemote(stale, fromNode: 'legacy')).docChanged,
          isFalse,
        );
        expect(a.files.files['family.doc'], same(afterSync));
      },
    );
  });
}
