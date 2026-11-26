import 'dart:typed_data';

import 'package:clock/clock.dart';
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
import 'package:regalos/core/sync/wish.dart';
import 'package:regalos/core/sync/wish_author.dart';
import 'package:regalos/core/sync/wish_plan.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/application/family_providers.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/family/domain/family_errors.dart';
import 'package:regalos/features/sharing/application/share_service.dart';
import 'package:regalos/features/sync/application/app_sync_v2_local.dart';
import 'package:regalos/features/sync/application/generation_v2.dart';
import 'package:regalos/features/sync/application/migration_v2.dart';
import 'package:regalos/features/sync/application/sync_controller.dart';
import 'package:regalos/features/sync/application/sync_v2_engine.dart';
import 'package:regalos/features/sync/application/v2_health_provider.dart';
import 'package:regalos/features/sync/data/sync_config.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';
import 'package:regalos/features/sync/domain/sync_status.dart';

import '../helpers/memory_stores.dart';
import '../helpers/fake_worker_v2.dart';
import '../helpers/fake_sync_server.dart';
import '../helpers/pump_app.dart' hide scopeWith;
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

class RegistryReadDisk extends MemoryFileStore {
  int registryReads = 0;

  @override
  Future<Uint8List?> read(String name) {
    if (name == 'family.registry') registryReads++;
    return super.read(name);
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

  /// Reads the access list while it is listened, as the sheet does: a
  /// failing registry read retries only while someone listens.
  Future<List<GiftRecipientAccess>> listenedAccess() {
    final sub = phone.container.listen(giftRecipientAccessProvider, (_, _) {});
    return phone.container
        .read(giftRecipientAccessProvider.future)
        .whenComplete(sub.close);
  }

  Future<void> refresh() async {
    phone.container.invalidate(localRegistryReadProvider);
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
    bool v2 = true,
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
    if (v2) await keys.restore(member.keys);
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
    if (v2) {
      await p.store.saveSyncV2(
        SyncIdentityV2(
          listId: kListId,
          deviceId: member.id,
          syncId: 'AAAAAAAAAAAAAAAAAAAAAA',
        ),
      );
      await p.store.saveRegistry(registry ?? family.registry);
    }
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
      gift('given', person: 'leo-guest', title: 'Puzle', actualCents: 1900),
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
    expect(before.candidates, [('aritz', null, false)]);
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
    expect(authorView.grid().cell('leo-guest', giverNora.id).giftCount, 1);
    expect(authorView.budget().total.spentCents, 9023);

    Future<void> expectNoraSeesOnlyGiving(String giverId) async {
      final projection = await n.projection();
      final view = projection.view;
      expect(view.allGifts.map((g) => (g.title, g.plannedCents)), [
        ('Puzle', 1000),
      ]);
      expect(view.grid().cell('leo-guest', giverId).giftCount, 1);
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
    // Una persona sin móvil: en el de Aritz no se ve nada para Aritz (1.0.6).
    await p.controller.upsertRecipient(
      const Recipient(
        id: 'leo-guest',
        name: 'Leo',
        colorIndex: 2,
        archived: false,
      ),
    );
    final original = gift('book', person: 'leo-guest');
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

  test(
    'an approved web still protects its person after its phone changes person',
    () async {
      final aritz = family.aritz;
      final leo = family.leo;
      final web = await Phone.create('aritz-web', 'aritz', 4);
      final webRecord = await DeviceRecord.create(
        keys: web.keys,
        listId: kListId,
        deviceId: web.id,
        personId: web.self,
        kind: DeviceKind.web,
      );
      var registry = await registryOf([aritz, leo]);
      registry = await registry.withRecord(webRecord);
      registry = await registry.withVouch(
        await Vouch.create(
          keys: aritz.keys,
          voucher: await aritz.record(),
          record: webRecord,
        ),
      );
      registry = (await changePerson(
        registry: registry,
        view: await aritz.viewOf(registry),
        myKeys: aritz.keys,
        personId: 'nora',
      )).registry;
      registry = await registry.withVouch(
        await Vouch.create(
          keys: leo.keys,
          voucher: await leo.record(),
          record: registry.records.singleWhere(
            (record) => record.deviceId == aritz.id && record.seq == 2,
          ),
        ),
      );
      final view = await leo.viewOf(registry);
      expect(webStatusIn(view, web.id), WebDeviceStatus.confirmed);
      expect(view.members.where((id) => view.member(id)?.personId == 'aritz'), [
        web.id,
      ]);

      final p = await install(leo, registry: registry);
      expect(
        p.phone.container.read(familyStateProvider)?.isDevicePerson('aritz'),
        isTrue,
      );
      final before = p.common.canonicalJson();
      final refused = throwsA(
        isA<DevicePersonException>().having(
          (error) => error.owner,
          'owner',
          DevicePersonOwner.otherDevice,
        ),
      );
      await expectLater(p.controller.archiveRecipient('aritz'), refused);
      await expectLater(p.controller.deleteRecipient('aritz'), refused);
      expect((await p.store.load())!.doc.canonicalJson(), before);
    },
  );

  test(
    'offline file import retires secret gifts, overflow, plans and slots',
    () async {
      final p = await install(family.aritz, withKey: true);
      final clock = HlcClock(node: family.aritz.id, last: p.common.maxStamp);
      final sealedScope = FamilyDoc.empty(kListId)
          .set(clock, Collections.gifts, 'secret', gift('secret').toFields())
          .set(clock, ScopeCollections.wishPlans, 'plan', {
            'recipientId': 'nora',
            'sourceWishId': 'wish',
            'claimantPersonId': 'aritz',
            'title': 'Patinete',
            'status': 'idea',
          });
      final scope = sealedScope.set(clock, ScopeCollections.wishPlans, 'partial', {
        'title': 'Patinete',
      });
      await p.store.saveScope('nora', scope);
      await p.store.saveOverflow('nora', [
        scope.record(Collections.gifts, 'secret')!,
      ]);
      final slot = await SealedSlot.seal(
        writerKeys: family.aritz.keys,
        writer: family.aritz.id,
        revision: 42,
        key: family.key,
        policy: const PolicyState(hideOwnGifts: true, rev: 1),
        doc: sealedScope,
      );
      await p.store.saveSlots(await family.setOf([slot]));
      expect((await p.store.readSlots()).people, {'nora'});
      expect(await p.store.readOverflow('nora'), isNotEmpty);
      expect(
        (await p.store.readRecoveryScopes())['nora']!.record(
          ScopeCollections.wishPlans,
          'partial',
        )!['recipientId'],
        isNull,
      );

      final remote = p.common.delete(clock, Collections.recipients, 'nora');
      final bytes = await seal(
        doc: remote.toJson(),
        listId: kListId,
        fromNode: family.leo.id,
        at: remote.maxStamp!.pack(),
        key: p.controller.familyKey!,
        version: kFileEnvelopeVersion,
      );
      await p.phone.container
          .read(shareServiceProvider)
          .importEnvelopeBytes(bytes);
      expect(
        (await p.store.load())!.doc
            .record(Collections.recipients, 'nora')!
            .isDeleted,
        isTrue,
      );
      expect(await p.store.readScope('nora'), isNull);
      expect(await p.store.readOverflow('nora'), isEmpty);
      expect(await p.store.readRecoveryScopes(), isEmpty);
      expect((await p.store.readSlots()).people, isEmpty);
      expect(
        (await p.store.readRecoveryRevisionFloors())
            .slots['nora/${family.aritz.id}'],
        42,
      );
    },
  );

  for (final local in [true, false]) {
    test(
      'a failed recipient purge is retried before the next edit (local: $local)',
      () async {
        final disk = ClosingDisk();
        final p = await install(
          family.aritz,
          disk: disk,
          withKey: true,
          registry: await registryOf([family.aritz, family.leo]),
        );
        final clock = HlcClock(node: family.aritz.id, last: p.common.maxStamp);
        final before = p.common.set(clock, Collections.wishes, 'wish', {
          'recipientId': 'nora',
          'authorPersonId': 'nora',
          'suggested': false,
          'title': 'Patinete',
          'year': 2026,
        });
        await p.controller.mergeRemote(before, fromNode: family.aritz.id);
        final scope = FamilyDoc.empty(kListId)
            .set(clock, Collections.gifts, 'secret', gift('secret').toFields());
        final slot = await SealedSlot.seal(
          writerKeys: family.aritz.keys,
          writer: family.aritz.id,
          revision: 42,
          key: family.key,
          policy: const PolicyState(hideOwnGifts: true, rev: 1),
          doc: scope,
        );
        await p.store.saveScope('nora', scope);
        await p.store.saveSlots(await family.setOf([slot]));
        disk.failAt = 'family.recoveryFloors';
        await expectLater(
          local
              ? p.controller.deleteRecipient('nora')
              : p.controller.mergeRemote(
                  before.delete(clock, Collections.recipients, 'nora'),
                  fromNode: family.leo.id,
                ),
          throwsStateError,
        );
        expect(
          (await p.store.load())!.doc
              .record(Collections.recipients, 'nora')!
              .isDeleted,
          isTrue,
        );
        expect(
          p.common.record(Collections.recipients, 'nora')!.isDeleted,
          isTrue,
        );
        expect(await p.store.readScope('nora'), isNotNull);
        final health = await p.phone.container.read(v2HealthProvider.future);
        expect(health.frozenPeople, isNot(contains('nora')));
        await p.controller.setRecipientInReparto('leo', false);
        final saved = (await p.store.load())!.doc;
        expect(saved.record(Collections.recipients, 'nora')!.isDeleted, isTrue);
        expect(saved.record(Collections.wishes, 'wish')!.isDeleted, isTrue);
        expect(
          saved.record(Collections.recipients, 'leo')!['inReparto'],
          isFalse,
        );
        expect(await p.store.readScope('nora'), isNull);
        expect((await p.store.readSlots()).people, isEmpty);
        expect(
          (await p.store.readRecoveryRevisionFloors())
              .slots['nora/${family.aritz.id}'],
          42,
        );
      },
    );
  }

  test(
    'a saved v2 common without its v2 identity cannot delete a person',
    () async {
      final clock = HlcClock(node: family.aritz.id, last: common.maxStamp);
      final doc = common.set(clock, Collections.wishes, 'wish', {
        'recipientId': 'nora',
        'authorPersonId': 'nora',
        'suggested': false,
        'title': 'Patinete',
        'year': 2026,
      });
      final p = await install(family.aritz, doc: doc, v2: false);
      final before = (await p.store.load())!.doc.canonicalJson();
      final beforeBytes = p.phone.files.files['family.doc']!;
      expect(await p.store.readSyncV2(), isNull);
      await expectLater(
        p.controller.deleteRecipient('nora'),
        throwsA(
          isA<ProtectedPersonException>().having(
            (error) => error.reason,
            'reason',
            ProtectedPersonReason.registryUnavailable,
          ),
        ),
      );
      final saved = (await p.store.load())!.doc;
      expect(saved.canonicalJson(), before);
      expect(p.phone.files.files['family.doc'], beforeBytes);
      expect(saved.wishesFor('nora').single.id, 'wish');
    },
  );

  test('a pending v2 installation finishes on cold start with a tombstone', () async {
    final p = await install(family.aritz, v2: false);
    final clock = HlcClock(node: family.aritz.id, last: p.common.maxStamp);
    await p.store.saveDoc(
      p.common.delete(clock, Collections.recipients, 'nora'),
    );
    await p.store.saveScope('nora', scopeWith(clock, ['Bloques']));
    final pending = await PendingV2.fresh();
    await p.store.savePendingV2(pending.toJson());
    p.phone.restart();
    final finish = Provider((ref) {
      return ref.read(v2FamilyLockProvider).run(() => finishPendingV2(ref));
    });
    expect(
      await p.phone.container.read(finish).timeout(const Duration(seconds: 5)),
      isTrue,
    );
    expect(await p.store.readPendingV2(), isNull);
    expect((await p.store.readSyncV2())?.syncId, pending.syncId);
    expect(await p.store.readScope('nora'), isNotNull);
    await p.controller.setRecipientInReparto('leo', false);
    expect(await p.store.readScope('nora'), isNull);
  });

  test('purging deleted recipient scopes without a stored identity is a no-op', () async {
    final p = await install(family.aritz, v2: false);
    final clock = HlcClock(node: family.aritz.id, last: p.common.maxStamp);
    await p.store.saveScope('nora', scopeWith(clock, ['Bloques']));
    final deleted = p.common.delete(clock, Collections.recipients, 'nora');
    await p.phone.secrets.delete('family.identity');
    final files = Map.of(p.phone.files.files);
    final secrets = Map.of(p.phone.secrets.values);

    await p.store.purgeDeletedRecipientScopes(deleted);

    expect(p.phone.files.files, files);
    expect(p.phone.secrets.values, secrets);
  });

  test(
    'a v2 identity without a verified registry cannot delete a person',
    () async {
      final disk = ClosingDisk();
      final p = await install(family.aritz, disk: disk);
      await disk.delete('family.registry');
      final before = p.common.canonicalJson();
      await expectLater(
        p.controller.deleteRecipient('nora'),
        throwsA(
          isA<ProtectedPersonException>().having(
            (error) => error.reason,
            'reason',
            ProtectedPersonReason.registryUnavailable,
          ),
        ),
      );
      expect((await p.store.load())!.doc.canonicalJson(), before);
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
      final existing = gift('public', person: 'leo');
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
        'leo',
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
      final old = gift('public', person: 'leo');
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
    'the unassigned 8T can only request protection with a confirmer',
    () async {
      final unassigned = await Phone.create('8t', null, 5);
      final pair = await registryOf([unassigned, family.nora]);
      final p = await install(unassigned, registry: pair);
      final before = p.common.toJson();
      final persisted = p.phone.files.files['family.doc'];
      expect(persisted, isNotNull);

      Future<GiftRecipientAccess> noraAccess() async =>
          (await p.phone.container.read(giftRecipientAccessProvider.future))
              .singleWhere((access) => access.recipient.id == 'nora');

      final blocked = await noraAccess();
      expect(blocked.canRequest, isFalse);
      expect(blocked.requestReason, ProtectedPersonReason.noConfirmer);
      await expectLater(
        p.controller.requestProtection('nora'),
        throwsA(
          isA<ProtectedPersonException>().having(
            (e) => e.reason,
            'reason',
            ProtectedPersonReason.noConfirmer,
          ),
        ),
      );
      expect(p.common.toJson(), before);
      expect(p.phone.files.files['family.doc'], same(persisted));

      await p.store.saveRegistry(
        await registryOf([unassigned, family.nora, family.aritz]),
      );
      await p.refresh();
      expect((await noraAccess()).canRequest, isTrue);
      await p.controller.requestProtection('nora');
      expect(publishedPolicy(p.common, 'nora')?.hideOwnGifts, isTrue);
      expect((await p.store.load())!.doc.toJson(), p.common.toJson());
      expect((await p.store.readSlots()).all, isEmpty);
    },
  );

  test('Nora cannot request protection with only the unassigned 8T', () async {
    final unassigned = await Phone.create('8t', null, 5);
    final pair = await registryOf([unassigned, family.nora]);
    final p = await install(family.nora, registry: pair);
    final before = p.common.toJson();
    final slots = (await p.store.readSlots()).toJson();
    final keys = p.phone.container.read(deviceKeysStoreProvider);
    final keyring = (await keys.readKeyring(kListId)).toJson();
    final access = await p.phone.container.read(
      giftRecipientAccessProvider.future,
    );
    final nora = access.singleWhere((a) => a.recipient.id == 'nora');
    expect(nora.canRequest, isFalse);
    expect(nora.requestReason, ProtectedPersonReason.noConfirmer);
    expect(nora.viewerIsRecipient, isTrue);

    await expectLater(
      p.controller.requestProtection('nora'),
      throwsA(
        isA<ProtectedPersonException>().having(
          (e) => e.reason,
          'reason',
          ProtectedPersonReason.noConfirmer,
        ),
      ),
    );
    expect(p.common.toJson(), before);
    expect((await p.store.load())!.doc.toJson(), before);
    expect((await p.store.readSlots()).toJson(), slots);
    expect((await keys.readKeyring(kListId)).toJson(), keyring);
  });

  test(
    'the request rechecks the registry after waiting for the family lock',
    () async {
      final unassigned = await Phone.create('8t', null, 5);
      final registry = await registryOf([
        unassigned,
        family.nora,
        family.aritz,
      ]);
      final p = await install(unassigned, registry: registry);
      final before = p.common.toJson();
      final access = await p.phone.container.read(
        giftRecipientAccessProvider.future,
      );
      expect(
        access.singleWhere((a) => a.recipient.id == 'nora').canRequest,
        isTrue,
      );
      final revoked = await registry.withRevocation(
        await Revocation.create(
          keys: family.nora.keys,
          by: await family.nora.record(),
          deviceId: family.aritz.id,
        ),
      );
      final lock = p.phone.container.read(v2FamilyLockProvider);
      late Future<void> rejection;
      await lock.run(() async {
        rejection = expectLater(
          p.controller.requestProtection('nora'),
          throwsA(
            isA<ProtectedPersonException>().having(
              (e) => e.reason,
              'reason',
              ProtectedPersonReason.noConfirmer,
            ),
          ),
        );
        await p.store.saveRegistry(revoked);
      });
      await rejection;
      expect((await p.store.load())!.doc.toJson(), before);
    },
  );

  test('a request cannot use a registry with a mixed local identity', () async {
    final web = await DeviceRecord.create(
      keys: family.aritz.keys,
      listId: kListId,
      deviceId: family.aritz.id,
      personId: 'aritz',
      kind: DeviceKind.web,
    );
    final p = await install(
      family.aritz,
      registry: await family.registry.withRecord(web),
    );
    final before = p.common.toJson();
    final access = await p.listenedAccess();
    final nora = access.singleWhere((a) => a.recipient.id == 'nora');
    expect(nora.canRequest, isFalse);
    expect(nora.requestReason, ProtectedPersonReason.requesterAmbiguous);
    expect(nora.canSelect, isFalse);

    await expectLater(
      p.controller.requestProtection('nora'),
      throwsA(
        isA<ProtectedPersonException>().having(
          (e) => e.reason,
          'reason',
          ProtectedPersonReason.requesterAmbiguous,
        ),
      ),
    );
    expect((await p.store.load())!.doc.toJson(), before);
  });

  test('v1 can select recipients and cannot request protection', () async {
    final p = await install(
      family.aritz,
      doc: commonWithPeople(HlcClock(node: family.aritz.id)),
      v2: false,
    );
    expect(await p.store.readSyncV2(), isNull);
    final nora = (await p.listenedAccess()).singleWhere(
      (a) => a.recipient.id == 'nora',
    );
    expect(nora.canSelect, isTrue);
    expect(nora.canRequest, isFalse);
    expect(nora.requestReason, ProtectedPersonReason.requiresV2);
    await expectLater(
      p.controller.requestProtection('nora'),
      throwsA(
        isA<ProtectedPersonException>().having(
          (e) => e.reason,
          'reason',
          ProtectedPersonReason.requiresV2,
        ),
      ),
    );
  });

  test(
    'v2 without its registry stays blocked with any protocol mark',
    () async {
      final clock = HlcClock(node: family.aritz.id, last: common.maxStamp);
      final versionOne = common.set(
        clock,
        Collections.meta,
        kProtocolRecordId,
        {kProtocolVersionField: 1},
      );
      final tombstone = common.delete(
        clock,
        Collections.meta,
        kProtocolRecordId,
      );
      expect(syncProtocolOf(versionOne), 1);
      expect(
        tombstone.record(Collections.meta, kProtocolRecordId)!.isDeleted,
        isTrue,
      );
      for (final doc in [common, versionOne, tombstone]) {
        final p = await install(family.aritz, doc: doc);
        expect(await p.store.readSyncV2(), isNotNull);
        await p.phone.files.delete('family.registry');
        final before = p.common.toJson();
        final access = await p.listenedAccess();
        final nora = access.singleWhere((a) => a.recipient.id == 'nora');
        expect(nora.canRequest, isFalse);
        expect(nora.requestReason, ProtectedPersonReason.registryUnavailable);
        expect(nora.canSelect, isFalse);
        expect(nora.reason, ProtectedPersonReason.registryUnavailable);
        await expectLater(
          p.controller.requestProtection('nora'),
          throwsA(
            isA<ProtectedPersonException>().having(
              (e) => e.reason,
              'reason',
              ProtectedPersonReason.registryUnavailable,
            ),
          ),
        );
        expect((await p.store.load())!.doc.toJson(), before);
      }
    },
  );

  test(
    'projection and recipient access share one verified registry read',
    () async {
      final disk = RegistryReadDisk();
      final p = await install(family.aritz, disk: disk);
      disk.registryReads = 0;

      final projection = p.projection();
      final access = p.listenedAccess();
      expect(await projection, isA<AuthorizedProjection>());
      expect(
        (await access).singleWhere((a) => a.recipient.id == 'nora').canRequest,
        isTrue,
      );
      expect(disk.registryReads, 1);
    },
  );

  test(
    'unreadable device keys block a request and the family can reopen',
    () async {
      final p = await install(family.aritz);
      final before = p.common.toJson();
      expect(
        (await p.listenedAccess())
            .singleWhere((a) => a.recipient.id == 'nora')
            .canRequest,
        isTrue,
      );
      await p.phone.secrets.write(kDeviceKeysSecret, 'unreadable');

      await expectLater(
        p.controller.requestProtection('nora'),
        throwsA(
          isA<ProtectedPersonException>().having(
            (e) => e.reason,
            'reason',
            ProtectedPersonReason.registryUnavailable,
          ),
        ),
      );
      expect((await p.store.load())!.doc.toJson(), before);

      p.phone.restart();
      final reopened = await p.phone.container.read(
        familyControllerProvider.future,
      );
      expect(reopened.doc.toJson(), before);
      expect(reopened.otherDevicePeople, isEmpty);
      final nora = (await p.listenedAccess()).singleWhere(
        (a) => a.recipient.id == 'nora',
      );
      expect(nora.canRequest, isFalse);
      expect(nora.canSelect, isFalse);
      expect(nora.requestReason, ProtectedPersonReason.registryUnavailable);
    },
  );

  test(
    'request stays pending on own phone and restricts own requests',
    () async {
      final p = await install(family.nora);
      final before = await p.phone.container.read(
        giftRecipientAccessProvider.future,
      );
      expect(
        before.singleWhere((a) => a.recipient.id == 'nora').canRequest,
        isTrue,
      );
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
      expect(nora.canRequest, isFalse);
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
            ProtectedPersonReason.ownGiftsHidden,
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
      expect(projection.lockedBlocks, contains(const SecretBlock('nora')));
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
      acceptFileVersion: true,
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
    '201st gift stays encrypted locally and retries after freeing capacity',
    () async {
      final p = await install(family.aritz, withKey: true);
      await p.controller.activateProtection('nora');
      var scope = FamilyDoc.empty(kListId);
      final clock = HlcClock(node: family.aritz.id);
      for (var i = 0; i < kMaxSurpriseGifts; i++) {
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
      // Leo aún no ha publicado su slot (podría ser un 1.0.5): de los 200
      // solo se comparten 64 y el resto también queda pendiente en local.
      final pending = (await p.phone.container.read(
        pendingProtectedGiftsProvider.future,
      )).map((p) => p.gift.id).toList();
      expect(pending, contains('extra'));
      expect(pending, hasLength(1 + kMaxSurpriseGifts - kLegacySlotGifts));
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
      final firstVersion = before.slots
          .singleWhere((s) => s.personId == 'nora')
          .version;
      final original = (await p.projection()).view.gifts.single;
      await p.controller.upsertGift(
        gift('slot-only', title: 'Puzle'),
        original: original,
      );
      final out = await engine.sync();
      expect(out.uploaded, isTrue);
      final after = (await transport.getList(auth) as V2GetOk).snapshot;
      expect(
        after.slots.singleWhere((s) => s.personId == 'nora').deviceId,
        family.aritz.id,
      );
      expect(
        after.slots.singleWhere((s) => s.personId == 'nora').version,
        greaterThan(firstVersion),
      );
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

  test('activation keeps gifts above the capacity pending and deactivation publishes them too', () async {
    final clock = HlcClock(node: family.aritz.id);
    var many = common;
    for (var i = 0; i < kMaxSurpriseGifts + 2; i++) {
      many = many.set(clock, Collections.gifts, 'g$i', gift('g$i').toFields());
    }
    final p = await install(family.aritz, doc: many);
    await p.controller.activateProtection('nora');
    expect(
      liveSurpriseGifts((await p.store.readScope('nora'))!),
      kMaxSurpriseGifts,
    );
    expect(await p.store.readOverflow('nora'), hasLength(2));
    expect(FamilyView.fromDoc(p.common).gifts, isEmpty);
    await p.controller.deactivateProtection('nora');
    expect(
      FamilyView.fromDoc(p.common).gifts,
      hasLength(kMaxSurpriseGifts + 2),
    );
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
      // Público y sin móvil (1.0.6: aquí no se escribe nada para Aritz).
      await p.controller.upsertRecipient(
        const Recipient(
          id: 'leo-guest',
          name: 'Leo',
          colorIndex: 2,
          archived: false,
        ),
      );
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
        gift(moved.id, person: 'leo-guest'),
        original: moved,
      );
      expect((await p.projection()).view.gifts.single.recipientId, 'leo-guest');
      expect(
        FamilyView.fromDoc(p.common).gifts.single.recipientId,
        'leo-guest',
      );
    },
  );

  test('import notices do not count gifts hidden by an incoming protection request', () async {
    // 1.0.6: Nora's phone never writes a gift for Nora; it arrived earlier.
    final old = gift('old');
    final p = await install(
      family.nora,
      doc: common.set(
        HlcClock(node: family.leo.id),
        Collections.gifts,
        old.id,
        old.toFields(),
      ),
    );
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

  // 1.0.6: the public target is a person without a phone (on Aritz's phone
  // nothing for Aritz is written or shown).
  for (final target in ['leo-guest', 'leo']) {
    test(
      'moving an overflow edit to $target preserves every pending field',
      () async {
        final disk = ClosingDisk();
        final p = await install(family.aritz, withKey: true, disk: disk);
        await p.controller.upsertRecipient(
          const Recipient(
            id: 'leo-guest',
            name: 'Leo',
            colorIndex: 2,
            archived: false,
          ),
        );
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
        final moved = target == 'leo-guest'
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

  group('1.0.6: antes de aprobar el móvil nuevo', () {
    test('con derecho, pone en secreto los regalos de su persona', () async {
      final p = await install(family.aritz, withKey: true);
      await p.controller.upsertGift(gift('old'));
      final lock = p.phone.container.read(v2FamilyLockProvider);
      await lock.run(() => p.controller.protectForPairingWithinLock('nora'));
      expect(publishedPolicy(p.common, 'nora')?.hideOwnGifts, isTrue);
      expect(
        p.common.collections[Collections.gifts]?.values.where(
              (r) => !r.isDeleted && r['recipientId'] == 'nora',
            ) ??
            const <SyncRecord>[],
        isEmpty,
      );
      expect((await p.projection()).view.gifts.map((g) => g.id), ['old']);
      final slots = await p.store.readSlots();
      final view = await family.aritz.viewOf(family.registry);
      expect(slots.authenticatedPolicy('nora', view)?.hideOwnGifts, isTrue);
    });

    test(
      'sin derecho (ficha pendiente) falla en cerrado y no toca nada',
      () async {
        final pending = await registryOf([family.leo, family.nora])
            .then((r) async => r.withRecord(await family.aritz.record(seq: 2)));
        final p = await install(family.aritz, registry: pending);
        await p.controller.upsertGift(gift('old', person: 'leo'));
        final before = p.common.toJson();
        final lock = p.phone.container.read(v2FamilyLockProvider);
        await expectLater(
          lock.run(() => p.controller.protectForPairingWithinLock('leo')),
          throwsA(isA<PairingProtectionException>()),
        );
        expect(p.common.toJson(), before);
        // Su segundo móvil (la misma persona) no tiene nada que ocultar.
        await lock.run(() => p.controller.protectForPairingWithinLock('aritz'));
      },
    );
  });

  group('planes de deseos (ADR 0010, fase 3)', () {
    FamilyDoc withWishes() {
      final ctx = WishContext.device(
        view: () => family.viewOf(family.nora),
        localKeys: family.nora.keys,
      );
      var doc = common;
      for (final (id, title) in [('wbike', 'Bicicleta'), ('wbook', 'Libro')]) {
        doc = doc
            .createOwnWish(
              HlcClock(node: family.nora.id),
              ctx,
              VisibleWishPatch(title: title, year: 2026),
              id: id,
            )
            .doc;
      }
      return doc;
    }

    /// Leo's phone, up to date, has published its slot of Nora's block: a
    /// plan is only written when every other phone that reads the block
    /// announces wish plans (security review, A1).
    Future<void> peerPublishes(
      ProtectionPhone p,
      Phone writer,
      String person,
    ) async {
      final keyring = await p.phone.container
          .read(deviceKeysStoreProvider)
          .readKeyring(kListId);
      final slot = await SealedSlot.seal(
        writerKeys: writer.keys,
        writer: writer.id,
        revision: 1,
        key: keyring.latestFor(person)!,
        policy: const PolicyState(hideOwnGifts: true, rev: 1),
        doc: FamilyDoc.empty(kListId),
      );
      final (merged, _) = await (await p.store.readSlots()).merge([
        slot,
      ], view: family.view);
      await p.store.saveSlots(merged);
    }

    Future<void> leoPublishes(ProtectionPhone p) =>
        peerPublishes(p, family.leo, 'nora');

    Future<ProtectionPhone> aritzWithWishes({
      MemoryFileStore? disk,
      bool leoPublished = true,
    }) async {
      final p = await install(
        family.aritz,
        withKey: true,
        disk: disk,
        doc: withWishes(),
      );
      await p.controller.activateProtection('nora');
      if (leoPublished) await leoPublishes(p);
      return p;
    }

    Future<List<WishPlanRow>> rows(ProtectionPhone p) =>
        p.controller.wishPlanRows('nora');

    test('claim writes only the private scope: the common and the wish stay '
        'byte for byte', () async {
      final p = await aritzWithWishes();
      final commonBefore = p.common.canonicalJson();
      final out = await p.controller.claimWish('wbike', planId: 'plan1');
      expect(out.ok, isTrue, reason: '${out.write.error}');
      expect(out.pendingReason, isNull);
      expect(p.common.canonicalJson(), commonBefore);
      expect(p.common.collections.containsKey('wishPlans'), isFalse);
      final r = await rows(p);
      final bike = r.singleWhere((x) => x.sourceWishId == 'wbike');
      expect(bike.state, WishPlanState.claimed);
      expect(bike.plans.single.planId, 'plan1');
      expect(bike.plans.single.claimantPersonId, 'aritz');
      expect(
        r.singleWhere((x) => x.sourceWishId == 'wbook').state,
        WishPlanState.available,
      );
      // It is sealed in this phone's slot and reloaded from disk.
      final slots = await p.store.readSlots();
      expect(slots.slotOf('nora', family.aritz.id), isNotNull);
      p.phone.restart();
      await p.phone.container.read(familyControllerProvider.future);
      expect(
        (await rows(p)).singleWhere((x) => x.sourceWishId == 'wbike').plans,
        isNotEmpty,
      );
      // The authorized projection keeps it out of the readable document.
      final projection = await p.projection();
      expect(projection.doc.collections.containsKey('wishPlans'), isFalse);
    });

    test('a retry reuses the stored plan id and never writes a second '
        'plan', () async {
      final p = await aritzWithWishes();
      await p.controller.claimWish('wbike', planId: 'plan1');
      final again = await p.controller.claimWish('wbike', planId: 'plan1');
      expect(again.ok, isTrue);
      expect(again.write.planId, 'plan1');
      final noId = await p.controller.claimWish('wbike');
      expect(noId.write.planId, 'plan1');
      final bike = (await rows(p))
          .singleWhere((x) => x.sourceWishId == 'wbike');
      expect(bike.plans, hasLength(1));
    });

    test("the protected person's phone gets nothing", () async {
      final p = await aritzWithWishes();
      await p.controller.claimWish('wbike', planId: 'plan1');
      final n = await install(family.nora, doc: p.common);
      await n.store.saveSlots(await p.store.readSlots());
      final out = await n.controller.claimWish('wbook');
      expect(out.write.error, WishPlanError.notEntitled);
      expect(await n.controller.wishPlanRows('nora'), isEmpty);
      expect(await n.store.readScope('nora'), isNull);
      final projection = await n.projection();
      expect(projection.openedScopes, isEmpty);
      expect(projection.doc.collections.containsKey('wishPlans'), isFalse);
    });

    test('release, then claim again with a new id', () async {
      final p = await aritzWithWishes();
      await p.controller.claimWish('wbike', planId: 'plan1');
      expect((await p.controller.releaseWishPlan('nora', 'plan1')).ok, isTrue);
      expect(
        (await rows(p)).singleWhere((x) => x.sourceWishId == 'wbike').state,
        WishPlanState.available,
      );
      final again = await p.controller.claimWish('wbike');
      expect(again.ok, isTrue);
      expect(again.write.planId, isNot('plan1'));
      final plans = (await rows(p))
          .singleWhere((x) => x.sourceWishId == 'wbike')
          .plans;
      expect(plans.single.planId, again.write.planId);
      // The old id is never reused.
      final reuse = await p.controller.claimWish('wbook', planId: 'plan1');
      expect(reuse.write.error, WishPlanError.planIdInUse);
    });

    test('edit and convert to an independent surprise gift', () async {
      final p = await aritzWithWishes();
      await p.controller.claimWish('wbike', planId: 'plan1');
      final edited = await p.controller.editWishPlan(
        'nora',
        'plan1',
        const PrivatePlanPatch(plannedCents: 4500, store: 'Decathlon'),
      );
      expect(edited.ok, isTrue);
      final commonBefore = p.common.canonicalJson();
      final converted = await p.controller.convertWishPlanToSurprise(
        'nora',
        'plan1',
        year: 2026,
        giftId: 'gift-from-plan',
      );
      expect(converted.ok, isTrue, reason: '${converted.write.error}');
      expect(p.common.canonicalJson(), commonBefore);
      final projection = await p.projection();
      final gift = projection.view.gifts.singleWhere(
        (g) => g.id == 'gift-from-plan',
      );
      expect(gift.title, 'Bicicleta');
      expect(gift.plannedCents, 4500);
      expect(gift.store, 'Decathlon');
      expect(projection.secretGiftIds, contains('gift-from-plan'));
      final bike = (await rows(p))
          .singleWhere((x) => x.sourceWishId == 'wbike');
      expect(bike.state, WishPlanState.available);
    });

    test('a crash before the journal exists changes nothing and the retry '
        'writes one plan', () async {
      final disk = ClosingDisk();
      final p = await aritzWithWishes(disk: disk);
      disk.failAt = 'family.protection';
      await expectLater(
        p.controller.claimWish('wbike', planId: 'plan1'),
        throwsStateError,
      );
      expect(
        (await rows(p)).singleWhere((x) => x.sourceWishId == 'wbike').state,
        WishPlanState.available,
      );
      final ok = await p.controller.claimWish('wbike', planId: 'plan1');
      expect(ok.ok, isTrue);
      expect(
        (await rows(p)).singleWhere((x) => x.sourceWishId == 'wbike').plans,
        hasLength(1),
      );
    });

    test('a crash after the journal was written replays it on restart: one '
        'plan, no duplicates', () async {
      final disk = ClosingDisk();
      final p = await aritzWithWishes(disk: disk);
      disk.failDeleteAt = 'family.protection';
      await expectLater(
        p.controller.claimWish('wbike', planId: 'plan1'),
        throwsStateError,
      );
      expect(disk.files, contains('family.protection'));
      p.phone.restart();
      await p.phone.container.read(familyControllerProvider.future);
      // The retry first recovers the operation, then finds the live plan.
      final retry = await p.controller.claimWish('wbike');
      expect(retry.ok, isTrue);
      expect(retry.write.planId, 'plan1');
      expect(disk.files.containsKey('family.protection'), isFalse);
      final bike = (await rows(p))
          .singleWhere((x) => x.sourceWishId == 'wbike');
      expect(bike.plans, hasLength(1));
    });

    test(
      'unprotect never publishes a plan and a later activation keeps it',
      () async {
        final p = await aritzWithWishes();
        await p.controller.claimWish('wbike', planId: 'plan1');
        await p.controller.upsertGift(gift('secret', title: 'Libro oculto'));
        await p.controller.deactivateProtection('nora');
        expect(publishedPolicy(p.common, 'nora')?.hideOwnGifts, isFalse);
        expect(p.common.collections.containsKey('wishPlans'), isFalse);
        expect(p.common.canonicalJson(), isNot(contains('sourceWishId')));
        expect(p.common.canonicalJson(), isNot(contains('plan1')));
        // The gift went public; the plan did not.
        expect(
          p.common.collections[Collections.gifts]!.values.any(
            (r) => r['title'] == 'Libro oculto',
          ),
          isTrue,
        );
        expect(
          (await rows(p)).singleWhere((x) => x.sourceWishId == 'wbike').state,
          WishPlanState.claimed,
        );
        // Protecting again does not lose or publish it either.
        await p.controller.activateProtection('nora');
        expect(p.common.collections.containsKey('wishPlans'), isFalse);
        expect(
          (await rows(p))
              .singleWhere((x) => x.sourceWishId == 'wbike')
              .plans
              .single
              .planId,
          'plan1',
        );
      },
    );

    test('one cap everywhere: a claim that would leave the gift side over '
        '200 live records is refused', () async {
      final p = await aritzWithWishes();
      // 190 interface gifts + 10 moved in by the reconciliation = 200 live.
      var scope = FamilyDoc.empty(kListId);
      final c = HlcClock(node: family.aritz.id);
      for (var i = 0; i < 200; i++) {
        scope = scope.set(c, Collections.gifts, 's$i', {
          ...giftFields('nora', 'Regalo $i'),
          if (i >= 190) kMovedInField: true,
        });
      }
      await p.store.saveScope('nora', scope);
      final out = await p.controller.claimWish('wbike', planId: 'plan1');
      expect(out.write.error, WishPlanError.capacityReached);
      expect(
        (await rows(p)).singleWhere((x) => x.sourceWishId == 'wbike').plans,
        isEmpty,
      );
    });

    test('a claim while another phone has not published (or is on 1.0.6) is '
        'refused with devicesNeedUpdate and writes nothing', () async {
      final p = await aritzWithWishes(leoPublished: false);
      var scope = FamilyDoc.empty(kListId);
      final c = HlcClock(node: family.aritz.id);
      for (var i = 0; i < kLegacySlotGifts; i++) {
        scope = scope.set(
          c,
          Collections.gifts,
          's$i',
          giftFields('nora', 'Regalo $i'),
        );
      }
      await p.store.saveScope('nora', scope);
      final out = await p.controller.claimWish('wbike', planId: 'plan1');
      expect(out.write.error, WishPlanError.devicesNeedUpdate);
      expect(out.pendingReason, isNull);
      expect(
        (await rows(p)).singleWhere((x) => x.sourceWishId == 'wbike').state,
        WishPlanState.available,
      );
      // A second claim by someone else is not blocked by a ghost.
      expect((await p.store.readScope('nora'))!.livePlans, isEmpty);
    });

    test('errors come back typed: removed wish, missing key', () async {
      final ctx = WishContext.device(
        view: () => family.viewOf(family.nora),
        localKeys: family.nora.keys,
      );
      final removed = withWishes()
          .removeWish(HlcClock(node: family.nora.id), ctx, 'wbike')
          .doc;
      final p = await install(family.aritz, withKey: true, doc: removed);
      await p.controller.activateProtection('nora');
      final gone = await p.controller.claimWish('wbike');
      expect(gone.write.error, WishPlanError.wishRemoved);
      expect(
        (await p.controller.claimWish('nope')).write.error,
        WishPlanError.wishNotFound,
      );
      // No key for the epoch: typed failure, no exception.
      final keyless = await install(family.aritz, doc: withWishes());
      final out = await keyless.controller.claimWish('wbook');
      expect(out.write.error, WishPlanError.unavailable);
      expect(out.failure, isNotNull);
    });

    test('a far-future public stamp does not break the scope clock', () async {
      final ctx = WishContext.device(
        view: () => family.viewOf(family.nora),
        localKeys: family.nora.keys,
      );
      final future = common
          .createOwnWish(
            clockOf('nora-phone', 10),
            ctx,
            const VisibleWishPatch(title: 'Futuro', year: 2026),
            id: 'wfuture',
          )
          .doc;
      final p = await install(family.aritz, withKey: true, doc: future);
      await p.controller.activateProtection('nora');
      await leoPublishes(p);
      final out = await p.controller.claimWish('wfuture');
      expect(out.ok, isTrue, reason: '${out.write.error}');
    });

    test('the public clock does not see a claim: the next public write '
        'carries the same stamp', () async {
      final fixed = DateTime.now();
      Future<String> stampAfter({required bool claim}) async {
        return withClock(Clock.fixed(fixed), () async {
          final p = await aritzWithWishes();
          await p.controller.upsertGiver(
            const Giver(
              id: 'g-a',
              name: 'Abuelos',
              colorIndex: 1,
              householdPays: false,
              archived: false,
            ),
          );
          if (claim) await p.controller.claimWish('wbike', planId: 'plan1');
          await p.controller.upsertGiver(
            const Giver(
              id: 'g-b',
              name: 'Tíos',
              colorIndex: 2,
              householdPays: false,
              archived: false,
            ),
          );
          return p.common
              .record(Collections.givers, 'g-b')!
              .field('name')!
              .stamp
              .pack();
        });
      }

      expect(await stampAfter(claim: true), await stampAfter(claim: false));
    });

    test('deleting a giver clears it from the plans and counts them in the '
        'impact; deleting a person deletes theirs', () async {
      // Leo has no device here, so his person can be deleted.
      final registry = await registryOf([family.aritz, family.nora]);
      var doc = common.set(
        HlcClock(node: family.aritz.id),
        Collections.wishes,
        'wleo',
        {
          'recipientId': 'leo',
          'authorPersonId': 'leo',
          'suggested': false,
          'title': 'Peonza',
          'year': 2026,
        },
      );
      doc = withWishes().merge(doc);
      final p = await install(
        family.aritz,
        withKey: true,
        doc: doc,
        registry: registry,
      );
      await p.controller.activateProtection('nora');
      await p.controller.activateProtection('leo');
      // Nora's phone reads Leo's block: it has published its slot.
      await peerPublishes(p, family.nora, 'leo');
      await p.controller.claimWish(
        'wbike',
        planId: 'plan-nora',
        giverId: 'nosotros',
      );
      await p.controller.claimWish(
        'wleo',
        planId: 'plan-leo',
        giverId: 'nosotros',
      );
      final giverImpact = await p.controller.giverAliasDeleteImpact('nosotros');
      expect(giverImpact.plans, 2);
      await p.controller.deleteGiverAlias(
        'nosotros',
        expectedImpact: giverImpact,
      );
      Future<WishPlan> planOf(String person) async =>
          (await p.store.readScope(person))!.livePlans.single;
      expect((await planOf('nora')).giverId, isNull);
      expect((await planOf('leo')).giverId, isNull);
      // The plans are still there, now without a giver.
      final personImpact = await p.controller.recipientDeleteImpact('leo');
      expect(personImpact.plans, 1);
      expect(personImpact.affectedPlanIds, ['plan-leo']);
      // A stale confirmation is refused.
      await expectLater(
        p.controller.deleteRecipient(
          'leo',
          expectedImpact: personImpact.withPlans(const []),
        ),
        throwsA(isA<DeleteImpactChanged>()),
      );
      await p.controller.deleteRecipient('leo', expectedImpact: personImpact);
      final removed = p.common.record(Collections.wishes, 'wleo')!;
      expect(removed.isDeleted, isTrue);
      expect(removed.hasTombstoneContent, isFalse);
      expect(await p.store.readScope('leo'), isNull);
      expect((await p.store.readSlots()).people, isNot(contains('leo')));
      expect((await p.projection()).plansByWish, isNot(contains('wleo')));
      expect((await planOf('nora')).planId, 'plan-nora');
    });

    test('restore when alone keeps the plans closed', () async {
      final p = await aritzWithWishes();
      await p.controller.claimWish('wbike', planId: 'plan1');
      final plan = await p.controller.planAloneRestoreWithinLock();
      expect(plan.people, contains('nora'));
      // A new generation without anybody: registry, keys and slots are new.
      await p.store.saveRegistry(await registryOf([family.aritz]));
      await p.phone.container
          .read(deviceKeysStoreProvider)
          .saveKeyring(kListId, SurpriseKeyring.empty);
      await p.store.saveSlots(SlotSet.empty);
      final identity = (await p.store.load())!.identity;
      await p.store.saveIdentity(
        FamilyIdentity(
          listId: identity.listId,
          node: identity.node,
          deviceName: identity.deviceName,
          paired: false,
          selfRecipientId: identity.selfRecipientId,
        ),
      );
      p.phone.restart();
      await p.phone.container.read(familyControllerProvider.future);
      await p.controller.restoreOthersSecretsWhenAloneWithinLock(plan);
      expect(p.common.collections.containsKey('wishPlans'), isFalse);
      expect(p.common.canonicalJson(), isNot(contains('sourceWishId')));
      final scope = (await p.store.readScope('nora'))!;
      expect(scope.livePlans.map((x) => x.planId), ['plan1']);
    });
  });
}
