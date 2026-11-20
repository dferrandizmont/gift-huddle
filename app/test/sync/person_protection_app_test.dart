import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/pairing_v2.dart';
import 'package:regalos/core/sync/protected_doc.dart';
import 'package:regalos/core/sync/protected_envelope.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/application/family_providers.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/family/domain/family_errors.dart';
import 'package:regalos/features/sharing/application/share_service.dart';
import 'package:regalos/features/sync/application/app_sync_v2_local.dart';
import 'package:regalos/features/sync/application/sync_controller.dart';
import 'package:regalos/features/sync/application/sync_v2_engine.dart';
import 'package:regalos/features/sync/data/sync_config.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';
import 'package:regalos/features/sync/domain/sync_status.dart';

import '../helpers/memory_stores.dart';
import '../helpers/fake_worker_v2.dart';
import '../helpers/fake_sync_server.dart';
import '../helpers/pump_app.dart';
import 'protected_harness.dart';
import 'sync_harness.dart' show eventually, kFastTiming, kTestHost;

final _localProvider = FutureProvider<AppSyncV2Local?>(
  (ref) => AppSyncV2Local.load(ref),
);

/// Fail after the durable operation exists, before the common is replaced.
class ClosingDisk extends MemoryFileStore {
  String? failAt;
  String? failDeleteAt;
  @override
  Future<void> writeAtomic(String name, Uint8List bytes) async {
    if (name == failAt) {
      failAt = null;
      throw StateError('simulated close');
    }
    await super.writeAtomic(name, bytes);
  }

  @override
  Future<void> delete(String name) async {
    if (name == failDeleteAt) {
      failDeleteAt = null;
      throw StateError('simulated close');
    }
    await super.delete(name);
  }
}

class ClosingSecrets extends MemorySecretStore {
  String? failAt;
  @override
  Future<void> write(String key, String value) async {
    if (key == failAt) {
      failAt = null;
      throw StateError('simulated close');
    }
    await super.write(key, value);
  }
}

class ProtectionPhone {
  ProtectionPhone(this.phone, this.member);
  final FakePhone phone;
  final Phone member;
  FamilyController get controller =>
      phone.container.read(familyControllerProvider.notifier);
  FamilyStore get store => phone.container.read(familyStoreProvider);
  FamilyDoc get common =>
      phone.container.read(familyControllerProvider).value!.doc;

  Future<AuthorizedProjection> projection() async {
    final projection = await phone.container.read(
      authorizedProjectionProvider.future,
    );
    return projection!;
  }

  Future<void> refresh() async {
    phone.container.invalidate(localRegistryViewProvider);
    phone.container.invalidate(authorizedProjectionProvider);
    await projection();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Family family;
  late FamilyDoc common;
  setUp(() async {
    family = await Family.create();
    final clock = HlcClock(node: family.aritz.id);
    common = commonWithPeople(clock).set(
      clock,
      Collections.meta,
      kProtocolRecordId,
      {kProtocolVersionField: kSyncProtocolV2},
    );
  });

  Future<ProtectionPhone> install(
    Phone member, {
    MemoryFileStore? disk,
    MemorySecretStore? secrets,
    FamilyDoc? doc,
    bool withKey = false,
    SlotSet? slots,
    DeviceRegistry? registry,
    SyncV2Transport? transport,
  }) async {
    final fake = FakePhone(
      files: disk,
      secrets: secrets,
      prefs: transport == null ? null : await mockPrefs(),
      syncHost: transport == null ? '' : null,
      extraOverrides: [
        if (transport != null) ...[
          syncHostProvider.overrideWithValue(kTestHost),
          syncTransportProvider.overrideWithValue(FakeSyncServer().connect()),
          syncV2TransportProvider.overrideWithValue(transport),
          syncTimingProvider.overrideWithValue(kFastTiming),
        ],
      ],
    );
    addTearDown(fake.dispose);
    final p = ProtectionPhone(fake, member);
    final keys = fake.container.read(deviceKeysStoreProvider);
    await keys.restore(member.keys);
    await p.store.saveFamily(
      StoredFamily(
        identity: FamilyIdentity(
          listId: kListId,
          node: member.id,
          deviceName: member.self ?? 'Móvil',
          paired: true,
          selfRecipientId: member.self,
        ),
        key: await FamilyKey.generate(),
        doc: doc ?? common,
      ),
    );
    await p.store.saveSyncV2(
      SyncIdentityV2(
        listId: kListId,
        deviceId: member.id,
        syncId: 'AAAAAAAAAAAAAAAAAAAAAA',
      ),
    );
    await p.store.saveRegistry(registry ?? family.registry);
    if (withKey) await keys.saveKeyring(kListId, family.authorizedKeyring);
    if (slots != null) await p.store.saveSlots(slots);
    await fake.container.read(familyControllerProvider.future);
    return p;
  }

  Gift gift(
    String id, {
    String person = 'nora',
    String title = 'Bloques',
    String? note,
    int cents = 1000,
    int? actualCents,
    String? giverId = 'nosotros',
    RequestedBy? requestedBy,
  }) => Gift(
    id: id,
    recipientId: person,
    title: title,
    note: note,
    status: actualCents == null ? GiftStatus.idea : GiftStatus.bought,
    rawStatus: actualCents == null ? 'idea' : 'bought',
    surprise: false,
    year: 2026,
    giverId: giverId,
    plannedCents: cents,
    actualCents: actualCents,
    requestedBy: requestedBy,
  );

  Future<void> exchange(ProtectionPhone a, ProtectionPhone b) async {
    final common = a.common.merge(b.common);
    final slotsA = await a.store.readSlots();
    final slotsB = await b.store.readSlots();
    for (final p in [a, b]) {
      final view = await p.member.viewOf(family.registry);
      final slots = (await slotsA.merge(slotsB.all, view: view)).$1;
      await p.store.saveSlots(slots);
      await p.controller.mergeRemote(
        common,
        fromNode: p == a ? b.member.id : a.member.id,
      );
      await p.refresh();
    }
  }

  test('the protected person can see their own giving, and deleting an '
      'inaccessible giver reference preserves the secret gift', () async {
    final a = await install(family.aritz, withKey: true);
    final n = await install(family.nora);
    await a.controller.upsertRecipient(
      const Recipient(
        id: 'leo-guest',
        name: 'Leo',
        colorIndex: 2,
        archived: false,
      ),
    );
    await a.controller.activateProtection('nora');
    await a.controller.upsertGift(
      gift(
        'received',
        title: 'Libro secreto',
        actualCents: 7123,
        giverId: null,
      ),
    );
    await a.controller.upsertGift(
      gift('given', person: 'aritz', title: 'Puzle', actualCents: 1900),
    );
    expect(
      await a.controller.assignPersonAsGiver('given', 'nora'),
      GiftWriteResult.saved,
    );
    final giverNora = FamilyView.fromDoc(a.common).giverForPerson('nora')!;
    await a.controller.addPersonAsGiver('leo');
    for (final (id, person) in [
      (giverNora.id, 'nora'),
      ('a-leo-household', 'leo'),
    ]) {
      await a.controller.upsertGiver(
        Giver(
          id: id,
          name: person == 'nora' ? 'Nora' : 'Leo',
          colorIndex: 0,
          householdPays: true,
          archived: false,
        ),
      );
      await a.controller.linkGiver(id, person);
    }
    final giverLeo = FamilyView.fromDoc(a.common).giverForPerson('leo')!;
    expect(giverLeo.id, 'a-leo-household');
    expect(
      FamilyView.fromDoc(a.common).giverAliasIds(giverLeo.id),
      hasLength(2),
    );
    await exchange(a, n);

    ({
      List<Giver> columns,
      List<(String, String?, bool)> candidates,
      List<Giver> aliases,
    })
    publicChoices() {
      final view = n.phone.container.read(familyFullViewProvider);
      return (
        columns: view.grid().givers,
        candidates: n.phone.container
            .read(giftGiverPersonCandidatesProvider('given'))
            .map((c) => (c.person.id, c.giver?.id, c.needsPublicAdd))
            .toList(),
        aliases: view.allGivers,
      );
    }

    final before = publicChoices();
    expect(before.candidates, [('leo-guest', null, false)]);
    final commonBefore = a.common.canonicalJson();
    expect(
      await a.controller.assignPersonAsGiver('received', 'leo'),
      GiftWriteResult.saved,
    );
    expect(a.common.canonicalJson(), commonBefore);
    await exchange(a, n);
    final after = publicChoices();
    expect(after.columns, before.columns);
    expect(after.candidates, before.candidates);
    expect(after.aliases, before.aliases);
    final authorView = (await a.projection()).view;
    expect(authorView.allGifts, hasLength(2));
    expect(authorView.grid().cell('nora', giverLeo.id).giftCount, 1);
    expect(authorView.grid().cell('aritz', giverNora.id).giftCount, 1);
    expect(authorView.budget().total.spentCents, 9023);

    Future<void> expectNoraSeesOnlyGiving(String giverId) async {
      final projection = await n.projection();
      final view = projection.view;
      expect(view.allGifts.map((g) => (g.title, g.plannedCents)), [
        ('Puzle', 1000),
      ]);
      expect(view.grid().cell('aritz', giverId).giftCount, 1);
      expect(
        view.grid().cells['nora']?.values.every((cell) => cell.giftCount == 0),
        isTrue,
      );
      expect(view.budget().total.spentCents, 1900);
      expect(projection.lockedBlocks.map((b) => b.personId), ['nora']);
      expect(projection.doc.canonicalJson(), isNot(contains('Libro secreto')));
    }

    expect(
      n.phone.container
          .read(familyControllerProvider)
          .requireValue
          .identity
          ?.selfRecipientId,
      'nora',
    );
    await expectNoraSeesOnlyGiving(giverNora.id);
    expect(
      await n.controller.assignPersonAsGiver('given', 'leo'),
      GiftWriteResult.saved,
    );
    await expectNoraSeesOnlyGiving(giverLeo.id);
    expect(
      await n.controller.setGiftGiver('given', giverNora.id),
      GiftWriteResult.saved,
    );
    await expectNoraSeesOnlyGiving(giverNora.id);
    await n.controller.deleteGiver(giverLeo.id);
    await exchange(a, n);
    await expectNoraSeesOnlyGiving(giverNora.id);
    final received = (await a.projection()).view;
    expect(
      received.gifts.singleWhere((g) => g.id == 'received').title,
      'Libro secreto',
    );
    expect(received.resolveGiver(giverLeo.id), isNull);
    expect(received.grid().unassignedCell('nora').giftCount, 1);
  });

  test(
    'protected People choices need an explicit public add or recovery',
    () async {
      final disk = MemoryFileStore();
      final p = await install(family.aritz, withKey: true, disk: disk);
      await p.controller.activateProtection('nora');
      await p.controller.upsertGift(gift('secret'));
      await p.controller.addPersonAsGiver('aritz');
      await p.refresh();
      final options = p.phone.container.read(
        giftGiverPersonCandidatesProvider('secret'),
      );
      expect(options.map((c) => (c.person.id, c.needsPublicAdd)), [
        ('aritz', false),
        ('leo', true),
      ]);
      final commonBytes = disk.files['family.doc'];
      final scopeBytes = await p.store.readScope('nora');
      final needsAdd = throwsA(
        isA<GiverPersonNeedsPublicAdd>().having(
          (e) => e.personId,
          'person',
          'leo',
        ),
      );
      await expectLater(
        p.controller.assignPersonAsGiver('secret', 'leo'),
        needsAdd,
      );
      await expectLater(
        p.controller.upsertGiftWithGiverPerson(gift('new'), 'leo'),
        needsAdd,
      );
      expect(disk.files['family.doc'], same(commonBytes));
      expect(
        (await p.store.readScope('nora'))!.canonicalJson(),
        scopeBytes!.canonicalJson(),
      );
      expect(FamilyView.fromDoc(p.common).giverForPerson('leo'), isNull);

      final giver = (await p.controller.addPersonAsGiver('leo'))!;
      expect((await p.projection()).view.gifts.single.giverId, 'nosotros');
      await p.controller.archiveGiver(giver.id);
      await expectLater(
        p.controller.assignPersonAsGiver('secret', 'leo'),
        needsAdd,
      );
      expect((await p.controller.addPersonAsGiver('leo'))?.id, giver.id);
      expect(
        await p.controller.assignPersonAsGiver('secret', 'leo'),
        GiftWriteResult.saved,
      );
    },
  );

  test('the editor cannot recover an archived giver after moving the draft '
      'to a protected person', () async {
    final disk = MemoryFileStore();
    final p = await install(family.aritz, disk: disk, withKey: true);
    await p.controller.activateProtection('leo');
    final giver = (await p.controller.addPersonAsGiver('nora'))!;
    await p.controller.archiveGiver(giver.id);
    final original = gift('book', person: 'aritz');
    await p.controller.upsertGift(original);
    final candidate = (await p.projection()).view
        .giverPersonCandidatesFor(original.recipientId, protected: false)
        .singleWhere((choice) => choice.person.id == 'nora');
    expect(candidate.needsPublicAdd, isFalse);
    expect(candidate.giver?.archived, isTrue);

    final before = p.common;
    final bytes = disk.files['family.doc'];
    await expectLater(
      p.controller.upsertGiftWithGiverPerson(
        gift('book', person: 'leo'),
        candidate.person.id,
        original: original,
      ),
      throwsA(
        isA<GiverPersonNeedsPublicAdd>().having(
          (e) => e.personId,
          'person',
          'nora',
        ),
      ),
    );
    expect(p.common, same(before));
    expect(disk.files['family.doc'], same(bytes));
    final view = (await p.projection()).view;
    expect(view.giverForPerson('nora')?.archived, isTrue);
    expect(view.gifts.single.recipientId, original.recipientId);
    expect(view.gifts.single.giverId, original.giverId);
  });

  test('Reparto rechecks protection that arrived after selecting '
      'an archived giver', () async {
    final disk = MemoryFileStore();
    final a = await install(family.aritz, disk: disk, withKey: true);
    final b = await install(family.leo, withKey: true);
    final giver = (await a.controller.addPersonAsGiver('leo'))!;
    await a.controller.archiveGiver(giver.id);
    await a.controller.upsertGift(gift('book'));
    final candidate = (await a.projection()).view
        .giverPersonCandidatesFor('nora', protected: false)
        .singleWhere((choice) => choice.person.id == 'leo');
    expect(candidate.needsPublicAdd, isFalse);
    expect(candidate.giver?.archived, isTrue);

    await exchange(a, b);
    await b.controller.activateProtection('nora');
    await exchange(a, b);
    expect(FamilyView.fromDoc(a.common).gifts, isEmpty);
    expect((await a.projection()).view.gifts.single.id, 'book');
    final before = a.common;
    final bytes = disk.files['family.doc'];
    await expectLater(
      a.controller.assignPersonAsGiver('book', candidate.person.id),
      throwsA(
        isA<GiverPersonNeedsPublicAdd>().having(
          (e) => e.personId,
          'person',
          'leo',
        ),
      ),
    );
    expect(a.common, same(before));
    expect(disk.files['family.doc'], same(bytes));
    final view = (await a.projection()).view;
    expect(view.giverForPerson('leo')?.archived, isTrue);
    expect(view.gifts.single.giverId, 'nosotros');
  });

  test(
    'archiving and deleting recheck other owners in the signed registry',
    () async {
      final p = await install(
        family.aritz,
        registry: await registryOf([family.aritz]),
      );
      expect(
        p.phone.container
            .read(familyControllerProvider)
            .requireValue
            .otherDevicePeople,
        isEmpty,
      );
      final before = p.common.canonicalJson();
      await p.store.saveRegistry(family.registry);
      final refused = throwsA(
        isA<DevicePersonException>().having(
          (e) => e.owner,
          'owner',
          DevicePersonOwner.otherDevice,
        ),
      );
      await expectLater(p.controller.archiveRecipient('nora'), refused);
      await expectLater(p.controller.deleteRecipient('nora'), refused);
      expect(p.common.canonicalJson(), before);
      await p.refresh();
      expect(p.phone.container.read(familyStateProvider)?.otherDevicePeople, {
        'nora',
        'leo',
      });
    },
  );

  test(
    'person deletion clears secret requests and late references read empty',
    () async {
      final p = await install(
        family.aritz,
        registry: await registryOf([family.aritz, family.nora]),
      );
      const byLeo = RequestedByRecipient('leo');
      await p.controller.activateProtection('nora');
      await p.controller.upsertGift(gift('secret', requestedBy: byLeo));
      final impact = await p.controller.recipientDeleteImpact('leo');
      expect(impact.requestedGifts.map((g) => g.id), ['secret']);
      await p.controller.deleteRecipient('leo', expectedImpact: impact);
      final scope = (await p.store.readScope('nora'))!;
      expect(scope.record(Collections.gifts, 'secret')!['requestedBy'], isNull);
      expect((await p.projection()).view.gifts.single.requestedBy, isNull);
      final clock = HlcClock(node: family.leo.id, last: scope.maxStamp);
      final late = scope.set(
        clock,
        Collections.gifts,
        'late',
        gift('late', requestedBy: byLeo).toFields(),
      );
      await p.store.saveScope('nora', late);
      await p.refresh();
      expect(
        (await p.projection()).view.gifts
            .singleWhere((g) => g.id == 'late')
            .requestedBy,
        isNull,
      );
    },
  );

  test('a giver choice revalidates a remotely moved protected recipient '
      'while the editor is open', () async {
    final p = await install(family.aritz, withKey: true);
    final original = gift('gift', person: 'leo');
    await p.controller.upsertGift(original);
    final draft = FamilyView.fromDoc(p.common).gifts.single;
    await p.controller.upsertGiver(
      const Giver(
        id: 'linked',
        name: 'Nora',
        colorIndex: 1,
        householdPays: false,
        archived: false,
      ),
    );
    await p.controller.linkGiver('linked', 'nora');

    final clock = HlcClock(node: family.leo.id, last: p.common.maxStamp);
    final remote = requestProtection(
      p.common.set(clock, Collections.gifts, 'gift', {
        'recipientId': 'nora',
        'title': 'Puzle',
      }),
      clock,
      'nora',
    );
    await p.controller.mergeRemote(remote, fromNode: family.leo.id);
    expect(
      await p.controller.upsertGiftWithGiverPerson(
        draft,
        'nora',
        original: draft,
      ),
      GiftWriteResult.invalidPair,
    );
    expect(
      await p.controller.setGiftGiver('gift', 'linked'),
      GiftWriteResult.invalidPair,
    );
    await p.controller.addPersonAsGiver('leo');
    expect(
      await p.controller.assignPersonAsGiver('gift', 'leo'),
      GiftWriteResult.saved,
    );
    final secret = (await p.projection()).view;
    final saved = secret.gifts.single;
    expect(saved.recipientId, 'nora');
    expect(saved.title, 'Puzle');
    expect(saved.plannedCents, 1000);
    expect(secret.resolveGiver(saved.giverId)?.recipientId, 'leo');
    expect(p.common.record(Collections.gifts, 'gift')?.isDeleted, isTrue);
  });

  test(
    'retrying a failed secret assignment reuses the explicit public giver',
    () async {
      final disk = ClosingDisk();
      final p = await install(family.aritz, withKey: true, disk: disk);
      await p.controller.activateProtection('nora');
      await p.controller.upsertGift(gift('received'));
      final giver = (await p.controller.addPersonAsGiver('leo'))!;
      final record = p.common.record(Collections.givers, giver.id)!;
      disk.failAt = 'family.protection';
      await expectLater(
        p.controller.assignPersonAsGiver('received', 'leo'),
        throwsStateError,
      );
      expect(disk.failAt, isNull);
      expect(
        await p.controller.assignPersonAsGiver('received', 'leo'),
        GiftWriteResult.saved,
      );
      expect(
        p.common.record(Collections.givers, giver.id)!.fields,
        record.fields,
      );
      final projected = (await p.projection()).view;
      expect(
        projected.givers.where((g) => g.recipientId == 'leo'),
        hasLength(1),
      );
      expect(projected.gifts.single.giverId, giver.id);
    },
  );

  test(
    'upsert create and recipient edit fail closed without epoch key',
    () async {
      final clock = HlcClock(node: family.aritz.id);
      final existing = gift('public', person: 'aritz');
      final doc = requestProtection(
        common.set(clock, Collections.gifts, existing.id, existing.toFields()),
        clock,
        'nora',
      );
      final p = await install(family.aritz, doc: doc);
      final error = isA<ProtectedPersonException>()
          .having(
            (e) => e.reason,
            'reason',
            ProtectedPersonReason.missingEpochKey,
          )
          .having((e) => e.savedLocally, 'saved locally', false);
      await expectLater(p.controller.upsertGift(gift('new')), throwsA(error));
      await expectLater(
        p.controller.upsertGift(gift('public'), original: existing),
        throwsA(error),
      );
      expect(p.common.record(Collections.gifts, 'new'), isNull);
      expect(
        p.common.record(Collections.gifts, 'public')!['recipientId'],
        'aritz',
      );
      final access = await p.phone.container.read(
        giftRecipientAccessProvider.future,
      );
      expect(
        access.singleWhere((a) => a.recipient.id == 'nora').reason,
        ProtectedPersonReason.missingEpochKey,
      );
    },
  );

  test(
    'authorized create and recipient edit use own slot, preserving id',
    () async {
      final p = await install(family.aritz, withKey: true);
      final old = gift('public', person: 'aritz');
      expect(await p.controller.upsertGift(old), isTrue);
      await p.controller.activateProtection('nora');
      expect(await p.controller.upsertGift(gift('new')), isTrue);
      expect(
        await p.controller.upsertGift(gift('public'), original: old),
        isTrue,
      );
      expect(p.common.record(Collections.gifts, 'new'), isNull);
      expect(p.common.record(Collections.gifts, 'public')!.isDeleted, isTrue);
      final projection = await p.projection();
      expect(projection.view.gifts.map((g) => g.id).toSet(), {'new', 'public'});
      expect(
        (await p.store.readSlots()).all.every(
          (s) => s.header.writer == family.aritz.id,
        ),
        isTrue,
      );
    },
  );

  test(
    'request stays pending on own phone and restricts own requests',
    () async {
      final p = await install(family.nora);
      await p.controller.requestProtection('nora');
      expect(
        await p.phone.container
            .read(deviceKeysStoreProvider)
            .readKeyring(kListId),
        isA<SurpriseKeyring>().having((k) => k.people, 'people', isEmpty),
      );
      final access = await p.phone.container.read(
        giftRecipientAccessProvider.future,
      );
      final nora = access.singleWhere((a) => a.recipient.id == 'nora');
      expect(nora.status, PersonProtectionStatus.requested);
      expect(nora.canSelect, isFalse);
      expect(
        await p.phone.container.read(ownGiftRequestStateProvider.future),
        OwnGiftRequestState.protectionRestricted,
      );
      await expectLater(
        p.controller.upsertGift(gift('own')),
        throwsA(
          isA<ProtectedPersonException>().having(
            (e) => e.reason,
            'reason',
            ProtectedPersonReason.ownRequestsRestricted,
          ),
        ),
      );
    },
  );

  test('activation creates key, moves old gifts, deactivation uses deterministic ids', () async {
    final p = await install(family.aritz);
    await p.controller.upsertGift(gift('old'));
    await p.controller.requestProtection('nora');
    await p.controller.activateProtection('nora');
    expect(p.common.record(Collections.gifts, 'old')!.isDeleted, isTrue);
    final scope = (await p.store.readScope('nora'))!;
    expect(scope.record(Collections.gifts, 'old')!.isDeleted, isFalse);
    expect((await p.projection()).view.gifts.single.id, 'old');
    final keyring = await p.phone.container
        .read(deviceKeysStoreProvider)
        .readKeyring(kListId);
    expect(keyring.people, contains('nora'));
    await p.controller.deactivateProtection('nora');
    final published = FamilyView.fromDoc(p.common).gifts.single;
    expect(
      published.id,
      publishedGiftId(
        listId: kListId,
        personId: 'nora',
        giftId: 'old',
        salt:
            scope.record(Collections.gifts, 'old')![kPublishSaltField]
                as String,
        rev: 2,
      ),
    );
    expect(published.title, 'Bloques');
  });

  for (final activating in [true, false]) {
    for (final failAt in [
      'family.scope.nora',
      'family.overflow.nora',
      'family.slots',
      'family.doc',
      'family.protection:delete',
      'family.syncV2State',
      if (activating) kSurpriseKeysSecret,
    ]) {
      test(
        'recover ${activating ? "activation" : "deactivation"} after close at $failAt',
        () async {
          final disk = ClosingDisk();
          final secrets = ClosingSecrets();
          final p = await install(family.aritz, disk: disk, secrets: secrets);
          await p.controller.upsertGift(gift('old'));
          if (!activating) await p.controller.activateProtection('nora');
          if (failAt == 'family.protection:delete') {
            disk.failDeleteAt = 'family.protection';
          } else if (failAt == 'family.syncV2State' ||
              failAt == kSurpriseKeysSecret) {
            secrets.failAt = failAt;
          } else {
            disk.failAt = failAt;
          }
          await expectLater(
            activating
                ? p.controller.activateProtection('nora')
                : p.controller.deactivateProtection('nora'),
            throwsStateError,
          );
          expect(disk.files, contains('family.protection'));
          p.phone.restart();
          await p.phone.container.read(familyControllerProvider.future);
          final projection = await p.projection();
          expect(projection.view.gifts.single.title, 'Bloques');
          expect(projection.policies['nora']!.hideOwnGifts, activating);
          expect(disk.files.containsKey('family.protection'), isFalse);
          expect(await p.store.readSyncV2State(), isA<Map>());
          p.phone.restart();
          await p.phone.container.read(familyControllerProvider.future);
          expect((await p.projection()).view.gifts, hasLength(1));
        },
      );
    }
  }

  test('projection hides all own gifts including stale common; counts and budget follow it', () async {
    final a = await install(family.aritz, withKey: true);
    await a.controller.upsertGift(gift('old'));
    await a.controller.activateProtection('nora');
    await a.controller.upsertGift(gift('secret', cents: 2500));
    // A late public gift must never appear in the target's derived views.
    final stale = a.common.set(
      HlcClock(node: family.leo.id),
      Collections.gifts,
      'late',
      gift('late').toFields(),
    );
    final slots = await a.store.readSlots();
    final n = await install(family.nora, doc: stale, slots: slots);
    final noKey = await install(family.leo, doc: stale, slots: slots);
    final unassigned = await Phone.create('unassigned-phone', null, 4);
    final registry = await registryOf([
      family.aritz,
      family.leo,
      family.nora,
      unassigned,
    ]);
    final noRight = await install(
      unassigned,
      doc: stale,
      slots: slots,
      registry: registry,
    );
    for (final p in [n, noKey, noRight]) {
      final projection = await p.projection();
      expect(projection.view.gifts, isEmpty);
      expect(projection.view.allGifts, isEmpty);
      expect(projection.lockedBlocks, [const SecretBlock('nora')]);
      expect(p.phone.container.read(familyViewProvider).gifts, isEmpty);
      expect(p.phone.container.read(giftsForProvider('nora')), isEmpty);
      expect(p.phone.container.read(budgetProvider).total.plannedCents, 0);
      expect(
        p.phone.container
            .read(familyGridProvider)
            .cells
            .values
            .expand((row) => row.values)
            .fold<int>(0, (n, c) => n + c.giftCount),
        0,
      );
    }
    final projected = await a.projection();
    expect(projected.view.gifts, hasLength(2));
    expect(a.phone.container.read(budgetProvider).total.plannedCents, 3500);
    expect(
      a.phone.container.read(familyFullViewProvider).allGifts,
      hasLength(2),
    );
    // La exportación real sale del común publicable: ni el regalo público
    // tardío de Nora ni ningún secreto, aunque este móvil sí tenga derecho.
    final exported = await open(
      await noKey.phone.container.read(shareServiceProvider).buildEnvelope(),
      key: noKey.controller.familyKey!,
      expectedListId: kListId,
    );
    final exportedDoc = FamilyDoc.fromJson(exported.doc);
    expect(
      FamilyView.fromDoc(exportedDoc).gifts
          .where((g) => g.recipientId == 'nora'),
      isEmpty,
    );
    expect(exportedDoc.record(Collections.gifts, 'secret'), isNull);
    expect(exportedDoc.record(Collections.gifts, 'late'), isNull);
    // El común local conserva el regalo tardío para reconciliarlo luego.
    expect(noKey.common.record(Collections.gifts, 'late'), isNotNull);
    await expectLater(
      noRight.controller.upsertGift(gift('blocked')),
      throwsA(
        isA<ProtectedPersonException>().having(
          (e) => e.reason,
          'reason',
          ProtectedPersonReason.noEntitlement,
        ),
      ),
    );
  });

  test(
    'two secret writers merge different fields and propagate deletion',
    () async {
      final a = await install(family.aritz, withKey: true);
      await a.controller.activateProtection('nora');
      await a.controller.upsertGift(gift('g'));
      final b = await install(
        family.leo,
        withKey: true,
        doc: a.common,
        slots: await a.store.readSlots(),
      );
      final original = (await a.projection()).view.gifts.single;
      await a.controller.upsertGift(
        gift('g', title: 'Puzle'),
        original: original,
      );
      await b.controller.upsertGift(
        gift('g', note: 'Nota'),
        original: original,
      );
      await exchange(a, b);
      for (final p in [a, b]) {
        final merged = (await p.projection()).view.gifts.single;
        expect(merged.title, 'Puzle');
        expect(merged.note, 'Nota');
      }
      await b.controller.deleteGift('g');
      await exchange(a, b);
      expect((await a.projection()).view.gifts, isEmpty);
    },
  );

  test(
    '51st gift stays encrypted locally and retries after freeing capacity',
    () async {
      final p = await install(family.aritz, withKey: true);
      await p.controller.activateProtection('nora');
      var scope = FamilyDoc.empty(kListId);
      final clock = HlcClock(node: family.aritz.id);
      for (var i = 0; i < 50; i++) {
        scope = addSurpriseGift(scope, clock, 'g$i', gift('g$i').toFields());
      }
      await p.store.saveScope('nora', scope);
      await p.controller.retryPendingProtectedGifts('nora');
      await expectLater(
        p.controller.upsertGift(gift('extra')),
        throwsA(
          isA<ProtectedPersonException>()
              .having(
                (e) => e.reason,
                'reason',
                ProtectedPersonReason.blockFull,
              )
              .having((e) => e.savedLocally, 'saved', true),
        ),
      );
      expect((await p.store.readOverflow('nora')).single.id, 'extra');
      expect(p.common.record(Collections.gifts, 'extra'), isNull);
      expect(
        (await p.phone.container.read(pendingProtectedGiftsProvider.future))
            .map((p) => p.gift.id),
        ['extra'],
      );
      p.phone.restart();
      await p.phone.container.read(familyControllerProvider.future);
      await p.controller.deleteGift('g0');
      await p.controller.retryPendingProtectedGifts('nora');
      expect(await p.store.readOverflow('nora'), isEmpty);
      expect(
        (await p.projection()).view.gifts.any((g) => g.id == 'extra'),
        isTrue,
      );
    },
  );

  test(
    'writer slots full preserves gift and exposes pending sharing reason',
    () async {
      final p = await install(family.aritz, withKey: true);
      await p.controller.activateProtection('nora');
      await p.store.saveSyncV2State({
        's': {for (var i = 0; i < 32; i++) 'person$i/${family.aritz.id}': 1},
      });
      await expectLater(
        p.controller.upsertGift(gift('local')),
        throwsA(
          isA<ProtectedPersonException>()
              .having(
                (e) => e.reason,
                'reason',
                ProtectedPersonReason.writerSlotsFull,
              )
              .having((e) => e.savedLocally, 'saved', true),
        ),
      );
      final pending = await p.phone.container.read(
        pendingProtectedGiftsProvider.future,
      );
      expect(pending.single.gift.id, 'local');
      expect(pending.single.reason, ProtectedPersonReason.writerSlotsFull);
      p.phone.restart();
      await p.phone.container.read(familyControllerProvider.future);
      expect((await p.projection()).view.gifts.single.id, 'local');
    },
  );

  test(
    'real v2 engine publishes secret-only edits immediately in own slot',
    () async {
      final p = await install(family.aritz, withKey: true);
      final worker = FakeWorkerV2();
      final transport = worker.client();
      final loaded = await p.phone.container.read(_localProvider.future);
      final local = loaded!;
      final engine = SyncV2Engine(transport: transport, local: local);
      await engine.ensureCreated();
      await p.controller.activateProtection('nora');
      await p.controller.upsertGift(gift('slot-only'));
      await engine.sync();
      final auth = V2Auth(
        syncId: local.identity.syncId,
        deviceId: family.aritz.id,
        credential: family.aritz.keys.serviceCredential,
      );
      final before = (await transport.getList(auth) as V2GetOk).snapshot;
      final firstVersion = before.slots.single.version;
      final original = (await p.projection()).view.gifts.single;
      await p.controller.upsertGift(
        gift('slot-only', title: 'Puzle'),
        original: original,
      );
      final out = await engine.sync();
      expect(out.uploaded, isTrue);
      final after = (await transport.getList(auth) as V2GetOk).snapshot;
      expect(after.slots.single.deviceId, family.aritz.id);
      expect(after.slots.single.version, greaterThan(firstVersion));
      final public = await open(
        after.common,
        key: p.controller.familyKey!,
        expectedListId: kListId,
      );
      expect(FamilyView.fromDoc(FamilyDoc.fromJson(public.doc)).gifts, isEmpty);
    },
  );

  test('an entitled phone confirms a pending request and preserves the original id', () async {
    final p = await install(family.aritz);
    await p.controller.upsertGift(gift('old'));
    await p.controller.requestProtection('nora');
    final lock = p.phone.container.read(v2FamilyLockProvider);
    expect(
      await lock.run(p.controller.reconcileProtectedPeopleWithinLock),
      isTrue,
    );
    expect((await p.projection()).view.gifts.single.id, 'old');
    expect(
      await lock.run(p.controller.reconcileProtectedPeopleWithinLock),
      isFalse,
    );
  });

  test('activation keeps gifts above fifty pending and deactivation publishes them too', () async {
    final clock = HlcClock(node: family.aritz.id);
    var many = common;
    for (var i = 0; i < 52; i++) {
      many = many.set(clock, Collections.gifts, 'g$i', gift('g$i').toFields());
    }
    final p = await install(family.aritz, doc: many);
    await p.controller.activateProtection('nora');
    expect(liveSurpriseGifts((await p.store.readScope('nora'))!), 50);
    expect(await p.store.readOverflow('nora'), hasLength(2));
    expect(FamilyView.fromDoc(p.common).gifts, isEmpty);
    await p.controller.deactivateProtection('nora');
    expect(FamilyView.fromDoc(p.common).gifts, hasLength(52));
    expect(await p.store.readOverflow('nora'), isEmpty);
  });

  test(
    'leftOut from concurrent writer capacity remains local after reopening',
    () async {
      final p = await install(family.aritz, withKey: true);
      await p.controller.activateProtection('nora');
      final clock = HlcClock(node: family.aritz.id);
      var scope = FamilyDoc.empty(kListId);
      for (var i = 0; i < 70; i++) {
        scope = scope.set(
          clock,
          Collections.gifts,
          'g$i',
          gift('g$i').toFields(),
        );
      }
      await p.store.saveScope('nora', scope);
      await p.controller.retryPendingProtectedGifts('nora');
      final pending = await p.phone.container.read(
        pendingProtectedGiftsProvider.future,
      );
      expect(pending, hasLength(6));
      p.phone.restart();
      await p.phone.container.read(familyControllerProvider.future);
      expect(liveSurpriseGifts((await p.store.readScope('nora'))!), 70);
      expect(
        await p.phone.container.read(pendingProtectedGiftsProvider.future),
        hasLength(6),
      );
    },
  );

  test(
    'secret status, undo, and committed deletion all use the writer slot',
    () async {
      final p = await install(family.aritz, withKey: true);
      await p.controller.activateProtection('nora');
      await p.controller.upsertGift(gift('g'));
      expect(await p.controller.setGiftStatus('g', GiftStatus.bought), isTrue);
      expect(
        (await p.projection()).view.gifts.single.status,
        GiftStatus.bought,
      );
      expect(await p.controller.deleteGiftWithUndo('g'), isTrue);
      expect((await p.projection()).view.gifts, isEmpty);
      expect(await p.controller.undoDeleteGift('g'), isTrue);
      expect((await p.projection()).view.gifts, hasLength(1));
      await p.controller.deleteGiftWithUndo('g');
      await p.controller.flushPendingDeletes();
      expect((await p.projection()).view.gifts, isEmpty);
      expect(p.common.record(Collections.gifts, 'g'), isNull);
    },
  );

  test(
    'moving a secret gift to public or another protected person is recoverable',
    () async {
      final disk = ClosingDisk();
      final p = await install(family.aritz, withKey: true, disk: disk);
      await p.controller.activateProtection('nora');
      await p.controller.activateProtection('leo');
      await p.controller.upsertGift(gift('g'));
      final original = (await p.projection()).view.gifts.single;
      disk.failAt = 'family.doc';
      await expectLater(
        p.controller.upsertGift(gift('g', person: 'leo'), original: original),
        throwsStateError,
      );
      p.phone.restart();
      await p.phone.container.read(familyControllerProvider.future);
      final moved = (await p.projection()).view.gifts.single;
      expect(moved.id, isNot('g'));
      expect(moved.recipientId, 'leo');
      await p.controller.upsertGift(
        gift(moved.id, person: 'aritz'),
        original: moved,
      );
      expect((await p.projection()).view.gifts.single.recipientId, 'aritz');
      expect(FamilyView.fromDoc(p.common).gifts.single.recipientId, 'aritz');
    },
  );

  test('import notices do not count gifts hidden by an incoming protection request', () async {
    final p = await install(family.nora);
    await p.controller.upsertGift(gift('old'));
    final remote = requestProtection(
      p.common,
      HlcClock(node: family.aritz.id),
      'nora',
    );
    final summary = await p.controller.mergeRemote(
      remote,
      fromNode: family.aritz.id,
    );
    expect(summary.giftsAdded + summary.giftsChanged + summary.giftsDeleted, 0);
  });

  for (final withKey in [true, false]) {
    test(
      'stale editor preserves remote protected recipient (key: $withKey)',
      () async {
        final original = gift('g', person: 'aritz');
        final clock = HlcClock(node: family.leo.id);
        var doc = common.set(
          clock,
          Collections.gifts,
          'g',
          original.toFields(),
        );
        doc = requestProtection(doc, clock, 'nora');
        final p = await install(family.aritz, withKey: withKey, doc: doc);
        // The form still says Aritz; only its title was changed locally.
        final moved = p.common.set(
          HlcClock(node: family.leo.id),
          Collections.gifts,
          'g',
          {'recipientId': 'nora'},
        );
        await p.controller.mergeRemote(moved, fromNode: family.leo.id);
        final edit = p.controller.upsertGift(
          gift('g', person: 'aritz', title: 'Puzle'),
          original: original,
        );
        if (withKey) {
          expect(await edit, isTrue);
          expect(p.common.record(Collections.gifts, 'g')!.isDeleted, isTrue);
          final visible = (await p.projection()).view.gifts.single;
          expect(visible.recipientId, 'nora');
          expect(visible.title, 'Puzle');
        } else {
          await expectLater(
            edit,
            throwsA(
              isA<ProtectedPersonException>().having(
                (e) => e.reason,
                'reason',
                ProtectedPersonReason.missingEpochKey,
              ),
            ),
          );
          expect(p.common.record(Collections.gifts, 'g')!['title'], 'Bloques');
        }
      },
    );
  }

  for (final target in ['aritz', 'leo']) {
    test(
      'moving an overflow edit to $target preserves every pending field',
      () async {
        final disk = ClosingDisk();
        final p = await install(family.aritz, withKey: true, disk: disk);
        await p.controller.activateProtection('nora');
        if (target == 'leo') await p.controller.activateProtection('leo');
        await p.controller.upsertGift(gift('g'));
        final original = (await p.projection()).view.gifts.single;
        final note = 'x' * (kMaxSurpriseGiftBytes + 100);
        await expectLater(
          p.controller.upsertGift(gift('g', note: note), original: original),
          throwsA(
            isA<ProtectedPersonException>().having(
              (e) => e.savedLocally,
              'saved locally',
              true,
            ),
          ),
        );
        final pending = (await p.phone.container.read(
          pendingProtectedGiftsProvider.future,
        )).single.gift;
        expect(pending.note, note);
        // The form changes only recipientId; the note must come from overflow.
        disk.failAt = 'family.doc';
        await expectLater(
          p.controller.upsertGift(
            gift('g', person: target, note: note),
            original: pending,
          ),
          throwsStateError,
        );
        p.phone.restart();
        await p.phone.container.read(familyControllerProvider.future);
        expect(await p.store.readOverflow('nora'), isEmpty);
        expect(
          (await p.store.readScope('nora'))!
              .record(Collections.gifts, 'g')!
              .isDeleted,
          isTrue,
        );
        final moved = target == 'aritz'
            ? FamilyView.fromDoc(p.common).gifts.single
            : (await p.phone.container.read(
                pendingProtectedGiftsProvider.future,
              )).single.gift;
        expect(moved.recipientId, target);
        expect(moved.note, note);
        expect(moved.title, original.title);
        expect(moved.id, isNot('g'));
      },
    );
  }

  test(
    'remote deletion resolves overflow before compaction, restart and retry',
    () async {
      final a = await install(family.aritz, withKey: true);
      await a.controller.activateProtection('nora');
      await a.controller.upsertGift(gift('g'));
      final b = await install(
        family.leo,
        withKey: true,
        doc: a.common,
        slots: await a.store.readSlots(),
      );
      final original = (await a.projection()).view.gifts.single;
      await expectLater(
        a.controller.upsertGift(
          gift('g', note: 'x' * (kMaxSurpriseGiftBytes + 100)),
          original: original,
        ),
        throwsA(isA<ProtectedPersonException>()),
      );
      await b.controller.deleteGift('g');
      await exchange(a, b);
      expect(
        await a.phone.container.read(pendingProtectedGiftsProvider.future),
        isEmpty,
      );
      await a.phone.container
          .read(v2FamilyLockProvider)
          .run(a.controller.reconcileProtectedPeopleWithinLock);
      expect(await a.store.readOverflow('nora'), isEmpty);
      await exchange(a, b);
      await b.controller.retryPendingProtectedGifts('nora');
      await exchange(a, b);
      await a.controller.retryPendingProtectedGifts('nora');
      expect(
        (await a.store.readScope('nora'))!.record(Collections.gifts, 'g'),
        isNull,
        reason: 'tombstone compacted',
      );
      a.phone.restart();
      await a.phone.container.read(familyControllerProvider.future);
      await a.controller.retryPendingProtectedGifts('nora');
      expect((await a.projection()).view.gifts, isEmpty);
      expect(
        await a.phone.container.read(pendingProtectedGiftsProvider.future),
        isEmpty,
      );
      await a.controller.deactivateProtection('nora');
      expect(FamilyView.fromDoc(a.common).gifts, isEmpty);
    },
  );

  for (final undo in [false, true]) {
    test(
      'deactivation resolves active Undo deletion (undone: $undo)',
      () async {
        final p = await install(family.aritz, withKey: true);
        await p.controller.activateProtection('nora');
        await p.controller.upsertGift(gift('g'));
        await p.controller.deleteGiftWithUndo('g');
        if (undo) expect(await p.controller.undoDeleteGift('g'), isTrue);
        await p.controller.deactivateProtection('nora');
        await p.controller.flushPendingDeletes();
        expect(FamilyView.fromDoc(p.common).gifts, hasLength(undo ? 1 : 0));
        if (!undo) expect(await p.controller.undoDeleteGift('g'), isFalse);
        p.phone.restart();
        await p.phone.container.read(familyControllerProvider.future);
        expect((await p.projection()).view.gifts, hasLength(undo ? 1 : 0));
      },
    );
  }

  for (final requested in [false, true]) {
    test('app reconciles ${requested ? "requested" : "active"} protection before every upload', () async {
      final worker = FakeWorkerV2();
      final sent = <FamilyDoc>[];
      late ProtectionPhone p;
      late Uint8List remoteBytes;
      var inspect = false;
      var collide = true;
      final transport = SyncV2Client(
        base: Uri.parse('https://sync.test'),
        openSocket: worker.socket,
        sendRequest: (method, uri, {body, headers = const {}}) async {
          if (inspect &&
              method == 'PUT' &&
              body is Map &&
              body['common'] is String) {
            final opened = await open(
              decodeBase64Url(body['common'] as String),
              key: p.controller.familyKey!,
              expectedListId: kListId,
            );
            sent.add(FamilyDoc.fromJson(opened.doc));
            // A real 412 forces another GET, merge, reconcile and upload.
            if (collide) {
              collide = false;
              worker.setCommonForTesting('AAAAAAAAAAAAAAAAAAAAAA', remoteBytes);
            }
          }
          return worker.send(method, uri, body: body, headers: headers);
        },
      );
      p = await install(family.aritz, withKey: true, transport: transport);
      final local = (await p.phone.container.read(_localProvider.future))!;
      final engine = SyncV2Engine(transport: transport, local: local);
      await engine.ensureCreated();
      // Match the paired signed registry with another active service
      // credential; a sole credential without recovery now retires its copy.
      worker.addCredentialForTesting(
        local.identity.syncId,
        family.leo.id,
        family.leo.keys.serviceCredential,
      );
      if (!requested) {
        await p.controller.activateProtection('nora');
        await engine.sync();
      }
      final clock = HlcClock(node: family.leo.id, last: p.common.maxStamp);
      var remote = p.common;
      for (var i = 0; i < kMaxReconcileMoves + 2; i++) {
        final id = i == 0 ? 'late' : 'late$i';
        remote = remote.set(clock, Collections.gifts, id, gift(id).toFields());
      }
      if (requested) remote = requestProtection(remote, clock, 'nora');
      remoteBytes = await seal(
        doc: remote.toJson(),
        listId: kListId,
        fromNode: family.leo.id,
        at: remote.maxStamp!.pack(),
        key: p.controller.familyKey!,
      );
      worker.setCommonForTesting(local.identity.syncId, remoteBytes);
      inspect = true;
      // The application starts the exchange, rather than a direct engine call.
      p.phone.container.read(syncControllerProvider);
      try {
        await eventually(
          () =>
              sent.length >= 2 &&
              p.phone.container.read(syncControllerProvider).phase ==
                  SyncPhase.synced,
        );
      } catch (_) {
        fail(
          'uploads=${sent.length}, status=${p.phone.container.read(syncControllerProvider)}, calls=${worker.calls}',
        );
      }
      for (final upload in sent) {
        expect(
          FamilyView.fromDoc(upload).gifts
              .where((g) => g.recipientId == 'nora'),
          isEmpty,
        );
      }
      expect(
        (await p.projection()).view.gifts,
        hasLength(kMaxReconcileMoves + 2),
      );
      final version = worker.slotVersions(
        local.identity.syncId,
      )['nora/${family.aritz.id}']!;
      final original = (await p.projection()).view.gifts.singleWhere(
        (g) => g.id == 'late',
      );
      await p.controller.upsertGift(
        gift('late', title: 'Puzle'),
        original: original,
      );
      await eventually(
        () =>
            (worker.slotVersions(
                  local.identity.syncId,
                )['nora/${family.aritz.id}'] ??
                0) >
            version,
        reason: 'automatic publication of secret-only edit',
      );
      for (final upload in sent) {
        expect(FamilyView.fromDoc(upload).gifts, isEmpty);
      }
    });
  }

  test('v2 editing a gift that does not exist does not recreate it', () async {
    final p = await install(family.aritz);
    final missing = gift('missing', person: 'aritz');
    expect(await p.controller.upsertGift(missing, original: missing), isFalse);
    expect(p.common.record(Collections.gifts, 'missing'), isNull);
  });

  test(
    'saving with a cached key confirms the request before signing its policy',
    () async {
      final clock = HlcClock(node: family.leo.id);
      final doc = requestProtection(
        common.set(clock, Collections.gifts, 'old', gift('old').toFields()),
        clock,
        'nora',
      );
      final p = await install(family.aritz, withKey: true, doc: doc);
      await p.controller.upsertGift(gift('new'));
      expect(FamilyView.fromDoc(p.common).gifts, isEmpty);
      expect((await p.projection()).view.gifts.map((g) => g.id).toSet(), {
        'old',
        'new',
      });
    },
  );
}
