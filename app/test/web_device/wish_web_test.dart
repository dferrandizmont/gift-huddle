// ADR 0010 (1.0.7), fase 4b: la web. La web de P crea, edita y quita los
// deseos de P como cambios públicos y nunca ve planes; la web de otra persona
// coge, edita y suelta los planes de los deseos de P por el buzón W5 y el
// móvil los recoge. De punta a punta contra el Worker falso.
import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/envelope.dart' show encodeBase64Url;
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/protected_doc.dart'
    show openScope, projectAuthorized;
import 'package:regalos/core/sync/protected_envelope.dart'
    show SealedSlot, kWebNewField;
import 'package:regalos/core/sync/wish.dart';
import 'package:regalos/core/sync/wish_plan.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/application/family_providers.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/family/domain/family_errors.dart';
import 'package:regalos/features/sync/application/sync_controller.dart'
    show localRegistryViewProvider;
import 'package:regalos/features/sync/application/sync_v2_engine.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart'
    show V2GetOk, V2SlotOk, V2WriteOk;
import 'package:regalos/features/web_device/application/pending_queue.dart';
import 'package:regalos/features/web_device/application/web_secrets.dart';
import 'package:regalos/features/web_device/application/web_sync_engine.dart'
    show WebOperationException, WebSyncEngine, kWebInboxHold, webEntryAllowed;
import 'package:regalos/features/web_device/data/web_family_store.dart';

import '../sync/fixtures/protected_envelope_v106.dart' as v106;
import '../sync/v2_harness.dart';
import 'web_engine_support.dart';
import 'web_secrets_review_test.dart' show aritzTablet;
import 'web_secrets_test.dart' show protectNora;

/// El móvil de Nora, en la familia y avalando también la web (ella es la
/// persona de la web: sin él la web no es «propia» de nadie, ADR 0009).
Future<MemoryV2Phone> noraPhone(WebHarness h) async {
  final nora = await MemoryV2Phone.create(
    'nora-phone',
    'nora',
    9,
    familyKey: h.phone.familyKey,
  );
  nora.doc = h.phone.doc;
  await vouchAll([h.phone, nora]);
  final web = h.engine.auth.deviceId;
  final record = nora.reg.records.firstWhere((r) => r.deviceId == web);
  nora.reg = await nora.reg.withVouch(
    await Vouch.create(keys: nora.keys, voucher: nora.record, record: record),
  );
  h.worker.addCredentialForTesting(
    kV2Sync,
    'nora-phone',
    nora.keys.serviceCredential,
  );
  await nora.engine(h.client).sync();
  await h.phone.engine(h.client).sync();
  await nora.engine(h.client).sync();
  return nora;
}

/// Un deseo de Nora ya publicado por el móvil de Aritz.
Future<void> publishNoraWish(WebHarness h, String id) async {
  h.phone.doc = h.phone.doc.set(h.phone.clock, Collections.wishes, id, {
    'recipientId': 'nora',
    'authorPersonId': 'nora',
    'suggested': false,
    'title': 'Patinete',
    'year': 2026,
  });
  await h.phone.engine(h.client).sync();
}

void main() {
  ProviderContainer webContainer(WebHarness h) {
    final container = ProviderContainer(
      overrides: [
        familyStoreProvider.overrideWithValue(
          WebFamilyStore(h.vault, h.engine),
        ),
        localRegistryViewProvider.overrideWith((ref) async => h.engine.view),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test(
    'la web protege a la persona del móvil raíz al confirmar y publicar',
    () async {
      final h = WebHarness(webPerson: 'aritz');
      addTearDown(h.close);
      await h.setup();
      final tablet = await aritzTablet(h);
      await publishNoraWish(h, 'own');
      await h.engine.sync();
      final container = webContainer(h);
      await container.read(familyControllerProvider.future);
      final controller = container.read(familyControllerProvider.notifier);
      await controller.deleteRecipient('nora');
      expect(await h.queue.entries(), hasLength(1));

      final phone = h.phone;
      final change = await changePerson(
        registry: phone.reg,
        view: await phone.view(),
        myKeys: phone.keys,
        personId: 'nora',
      );
      final registry = await change.registry.withVouch(
        await Vouch.create(
          keys: tablet.keys,
          voucher: tablet.record,
          record: change.registry.records.singleWhere(
            (r) =>
                r.deviceId == phone.identity.deviceId && r.personId == 'nora',
          ),
        ),
      );
      await h.publish(registry: registry.toJson());
      await h.engine.sync();
      expect(h.engine.view?.me, phone.identity.deviceId);
      expect(h.engine.view?.myPerson, 'nora');
      expect(h.engine.rejectedDevicePersonNames, ['Nora']);
      expect(h.engine.rejectedSecretRecipientDeletes, 0);
      final rejected = (await h.queue.entries()).single;
      expect(rejected.setAside, isTrue);
      expect(rejected.blockingDevicePersonNames, ['Nora']);
      await controller.reloadStoredCandidate();
      await container.read(localRegistryViewProvider.future);
      expect(
        container.read(familyStateProvider)?.devicePersonOwner('nora'),
        DevicePersonOwner.otherDevice,
      );
      await expectLater(
        controller.deleteRecipient('nora'),
        throwsA(
          isA<DevicePersonException>().having(
            (error) => error.owner,
            'owner',
            DevicePersonOwner.otherDevice,
          ),
        ),
      );
      final remote = await h.remote();
      expect(remote.record(Collections.recipients, 'nora')!.isDeleted, isFalse);
      expect(remote.wishesFor('nora').single.id, 'own');
    },
  );

  test('un 412 deja un aviso de borrado cuando una referencia pasa a estar protegida', () async {
    final h = WebHarness(webPerson: 'aritz');
    addTearDown(h.close);
    await h.setup();
    final phone = h.phone;
    final before = phone.doc
        .set(phone.clock, Collections.wishes, 'leo-wish', {
          'recipientId': 'leo',
          'authorPersonId': 'leo',
          'suggested': false,
          'title': 'Patinete',
          'year': 2026,
        })
        .set(phone.clock, Collections.gifts, 'gift', {
          'requestedBy': const RequestedByRecipient('leo').toFields(),
        });
    await h.publish(doc: before);
    await h.engine.sync();
    final container = webContainer(h);
    await container.read(familyControllerProvider.future);
    await container
        .read(familyControllerProvider.notifier)
        .deleteRecipient('leo');
    expect(
      h.engine.candidate!.record(Collections.recipients, 'leo')!.isDeleted,
      isTrue,
    );
    final callsBefore = h.worker.calls['PUT common'] ?? 0;
    FamilyDoc? protected;
    h.worker.beforePut = (_) async {
      protected = before.set(phone.clock, Collections.policies, 'nora', {
        'hideOwnGifts': true,
        'rev': 1,
      });
      await h.publish(doc: protected);
    };
    await h.engine.sync();
    expect(protected, isNotNull);
    expect(h.worker.calls['PUT common'], callsBefore + 1);
    expect(h.engine.rejectedSecretRecipientDeletes, 1);
    expect(h.engine.rejectedDevicePersonNames, isEmpty);
    expect(h.engine.setAsideCount, 0);
    expect((await h.queue.entries()).single.setAside, isTrue);
    final remote = await h.remote();
    expect(remote.canonicalJson(), protected!.canonicalJson());
    expect(remote.record(Collections.recipients, 'leo')!.isDeleted, isFalse);
    expect(remote.wishesFor('leo').single.id, 'leo-wish');
    expect(
      remote.record(Collections.gifts, 'gift')!['requestedBy'],
      const RequestedByRecipient('leo').toFields(),
    );
  });

  test('la web borra a una persona y descarta su buzón', () async {
    final h = WebHarness(webPerson: 'aritz');
    addTearDown(h.close);
    await h.setup();
    await protectNora(h);
    final phone = h.phone;
    var before = phone.doc;
    for (final (id, recipient, author) in [
      ('own', 'nora', 'nora'),
      ('incoming', 'nora', 'aritz'),
      ('outgoing', 'aritz', 'nora'),
    ]) {
      before = before.set(phone.clock, Collections.wishes, id, {
        'recipientId': recipient,
        'authorPersonId': author,
        'suggested': recipient != author,
        'title': 'Patinete',
        'url': 'https://example.com/$id',
        'description': 'Con luces',
        'year': 2026,
      });
    }
    phone.doc = before;
    await phone.engine(h.client).sync();
    await h.engine.sync();
    expect(h.engine.wishPlanRows('nora'), hasLength(2));
    expect(
      (await h.engine.removeOwnWish('incoming')).error,
      WishError.notWishOwner,
    );
    expect(
      (await h.engine.claimWish('own', planId: 'saved-plan')).ok,
      isTrue,
    );
    await h.engine.sync();
    await phone.engine(h.client).sync();
    await h.engine.sync();
    expect(phone.scopes['nora']!.livePlans.single.planId, 'saved-plan');
    expect(
      (await h.engine.claimWish('incoming', planId: 'pending-plan')).ok,
      isTrue,
    );
    await h.engine.sync();
    final withSecrets = h.engine.candidate!;
    await h.engine.save(
      withSecrets,
      withSecrets.set(
        h.engine.newScopeClock('nora'),
        Collections.gifts,
        'pending-gift',
        {
          'recipientId': 'nora',
          'title': 'Bufanda',
          'status': 'idea',
          'year': 2026,
        },
      ),
    );
    final pending = await h.queue.entries();
    expect(
      pending.where((entry) => entry.inboxPerson == 'nora'),
      hasLength(2),
    );
    expect(h.engine.pendingSecretGiftIds, {'pending-gift'});
    expect(h.engine.pendingPlanIds, {'pending-plan'});
    final web = h.engine.auth.deviceId;
    expect(h.worker.slotVersions(kV2Sync), contains('nora/$web'));

    final container = ProviderContainer(
      overrides: [
        familyStoreProvider.overrideWithValue(
          WebFamilyStore(h.vault, h.engine),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(familyControllerProvider.future);
    final controller = container.read(familyControllerProvider.notifier);
    await controller.deleteRecipient('nora');
    expect(h.engine.wishPlanRows('nora'), isEmpty);
    expect(await h.queue.entries(), hasLength(3));
    await h.engine.sync();
    await h.engine.sync();
    expect(await h.queue.entries(), isEmpty);
    expect(h.engine.pendingSecretGiftIds, isEmpty);
    expect(h.engine.pendingPlanIds, isEmpty);
    expect(h.engine.heldSecretCount, 0);
    expect(h.engine.discardedSecretCount, 2);
    final vault = h.vault.opened;
    final marks = await h.vault.crypto.open(
      (await h.vault.readCurrent()).marks!,
      vault.key,
      vault.header,
      'blocked',
    ) as Map;
    for (final entry in pending) {
      expect((marks['acks'] as Map)[entry.id], {
        'inbox': 'nora',
        'dropped': true,
      });
    }
    expect(h.worker.slotVersions(kV2Sync), isNot(contains('nora/$web')));
    final deleted = await h.remote();

    void expectDeletedWishes(FamilyDoc doc) {
      expect(doc.record(Collections.recipients, 'nora')!.isDeleted, isTrue);
      for (final id in ['own', 'incoming']) {
        final wish = doc.record(Collections.wishes, id)!;
        expect(wish.isDeleted, isTrue);
        expect(wish.hasTombstoneContent, isFalse);
        expect(validateWishRecord(wish), isNull);
      }
      expect(doc.wishesFor('aritz').single.id, 'outgoing');
    }

    expectDeletedWishes(deleted);
    phone.doc = phone.doc.set(
      HlcClock(node: phone.identity.deviceId, last: deleted.maxStamp),
      Collections.wishes,
      'own',
      {'title': 'Patinete azul', 'description': 'Con timbre'},
    );
    final outcome = await phone.engine(h.client).sync();
    expect(outcome.frozenPeople, isNot(contains('nora')));
    await h.engine.sync();
    expectDeletedWishes(await h.remote());
    expectDeletedWishes(h.engine.candidate!);
    expect(phone.scopes['nora'], isNull);
    expect(phone.slotSet.people, isNot(contains('nora')));
    expect(
      h.worker.slotVersions(kV2Sync),
      isNot(contains('nora/${phone.identity.deviceId}')),
    );
  });

  test(
    'retirar el buzón de una persona borrada respeta el plazo del rechazo',
    () async {
      var now = DateTime.now();
      final h = WebHarness(webPerson: 'aritz', now: () => now);
      addTearDown(h.close);
      await h.setup();
      await protectNora(h);
      await publishNoraWish(h, 'own');
      await h.engine.sync();
      expect(
        (await h.engine.claimWish('own', planId: 'pending-plan')).ok,
        isTrue,
      );
      await h.engine.sync();
      final slot = 'nora/${h.engine.auth.deviceId}';
      expect(h.worker.slotVersions(kV2Sync), contains(slot));

      final container = webContainer(h);
      await container.read(familyControllerProvider.future);
      await container
          .read(familyControllerProvider.notifier)
          .deleteRecipient('nora');
      h.worker.refuseWebSlot = 413;
      final before = h.worker.calls['PUT slot']!;
      await h.engine.sync();
      await h.engine.sync();
      expect(h.worker.calls['PUT slot'], before + 1);
      expect(await h.queue.entries(), isEmpty);
      expect(h.engine.heldInboxPeople, {'nora'});

      h.worker.refuseWebSlot = null;
      now = now.add(kWebInboxHold - const Duration(seconds: 1));
      await h.engine.sync();
      expect(h.worker.calls['PUT slot'], before + 1);
      expect(h.worker.slotVersions(kV2Sync), contains(slot));
      now = now.add(const Duration(seconds: 1));
      await h.engine.sync();
      expect(h.worker.calls['PUT slot'], before + 2);
      expect(h.worker.slotVersions(kV2Sync), isNot(contains(slot)));
      expect(h.engine.heldInboxPeople, isEmpty);
    },
  );

  test(
    'la web rechaza antes de encolar una cascada con una referencia protegida',
    () async {
      final h = WebHarness(webPerson: 'aritz');
      addTearDown(h.close);
      await h.setup();
      await protectNora(h);
      await h.publish(
        doc: h.phone.doc
            .set(h.phone.clock, Collections.wishes, 'leo-wish', {
              'recipientId': 'leo',
              'authorPersonId': 'leo',
              'suggested': false,
              'title': 'Patinete',
              'year': 2026,
            })
            .set(h.phone.clock, Collections.gifts, 'old-public-gift', {
              'recipientId': 'nora',
              'title': 'Bufanda',
              'year': 2026,
              'requestedBy': const RequestedByRecipient('leo').toFields(),
            }),
      );
      await h.engine.sync();
      expect(await h.queue.blockedPeople(), contains('nora'));
      final before = await h.remote();
      final container = ProviderContainer(
        overrides: [
          familyStoreProvider.overrideWithValue(
            WebFamilyStore(h.vault, h.engine),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(familyControllerProvider.future);
      final controller = container.read(familyControllerProvider.notifier);
      await expectLater(
        controller.deleteRecipient('leo'),
        throwsA(
          isA<WebOperationException>().having(
            (e) => e.operation,
            'operation',
            'deleteProtectedReferences',
          ),
        ),
      );
      expect(await h.queue.entries(), isEmpty);
      await h.engine.sync();
      expect((await h.remote()).canonicalJson(), before.canonicalJson());
    },
  );

  test('la web repara en el servidor los deseos de un borrado antiguo con la cola vacía', () async {
    final h = WebHarness(webPerson: 'aritz');
    addTearDown(h.close);
    await h.setup();
    await publishNoraWish(h, 'legacy-wish');
    final old = h.phone.doc
        .set(h.phone.clock, Collections.wishes, 'legacy-wish', {
          'url': 'https://example.com/patinete',
          'description': 'Con luces',
        })
        .delete(h.phone.clock, Collections.recipients, 'nora');
    await h.publish(doc: old);
    expect(
      (await h.remote()).record(Collections.wishes, 'legacy-wish')!['title'],
      'Patinete',
    );
    expect(await h.queue.entries(), isEmpty);

    await h.engine.sync();

    final repaired = (await h.remote()).record(
      Collections.wishes,
      'legacy-wish',
    )!;
    expect(repaired.isDeleted, isTrue);
    expect(repaired.hasTombstoneContent, isFalse);
    expect(validateWishRecord(repaired), isNull);
    expect(await h.queue.entries(), isEmpty);
    final version = h.worker.versionOf(kV2Sync);
    await h.engine.sync();
    expect(h.worker.versionOf(kV2Sync), version);
  });

  test('la web de Nora crea, edita y quita su deseo como cambio público '
      '(aunque su persona esté protegida) y nunca ve planes', () async {
    final h = WebHarness(webPerson: 'nora');
    addTearDown(h.close);
    await h.setup();
    await protectNora(h);
    await noraPhone(h);
    await h.engine.sync();
    expect(await h.queue.blockedPeople(), contains('nora'));
    expect(h.engine.showsOwnSurprisesBlock, isTrue);
    expect(h.engine.secrets.view, isNotNull);

    final created = await h.engine.createOwnWish(
      const VisibleWishPatch(title: 'Patinete', year: 2026),
    );
    expect(created.ok, isTrue, reason: '${created.error} ${created.authorError}');
    final id = created.wishId!;
    var entries = await h.queue.entries();
    expect(entries.single.kind, PendingKind.publicChange);
    expect(entries.single.inboxPerson, isNull);
    expect(h.engine.setAsideCount, 0);
    await h.engine.sync();
    var wish = (await h.remote()).record(Collections.wishes, id)!;
    expect(wish['title'], 'Patinete');
    expect(wish['recipientId'], 'nora');
    expect(wish['authorPersonId'], 'nora');
    expect(wish['suggested'], isFalse);
    expect(await h.queue.entries(), isEmpty);
    // El móvil de Aritz lo ve como un deseo más.
    await h.phone.engine(h.client).sync();
    expect(h.phone.doc.record(Collections.wishes, id)!['title'], 'Patinete');

    final edited = await h.engine.editOwnWish(
      id,
      const VisibleWishPatch(title: 'Patinete rojo', size: 'M'),
    );
    expect(edited.ok, isTrue);
    await h.engine.sync();
    wish = (await h.remote()).record(Collections.wishes, id)!;
    expect(wish['title'], 'Patinete rojo');
    expect(wish['size'], 'M');

    final removed = await h.engine.removeOwnWish(id);
    expect(removed.ok, isTrue);
    await h.engine.sync();
    expect((await h.remote()).record(Collections.wishes, id)!.isDeleted, isTrue);
    expect(await h.queue.entries(), isEmpty);

    // Aritz coge un deseo de Nora: la web de Nora no abre ese ámbito.
    await publishNoraWish(h, 'w9');
    h.phone.scopes['nora'] = (h.phone.scopes['nora'] ?? FamilyDoc.empty(kV2List))
        .set(h.phone.clock, ScopeCollections.wishPlans, 'p1', {
          'recipientId': 'nora',
          'sourceWishId': 'w9',
          'claimantPersonId': 'aritz',
          'title': 'Patinete',
          'status': 'decided',
        });
    h.phone.state = h.phone.state.copyWith(deferred: {'nora'});
    await h.phone.engine(h.client).sync();
    await h.engine.sync();
    expect(h.engine.secrets.openedPeople, isEmpty);
    expect(h.engine.scopeDocFor('nora'), isNull);
    expect(h.engine.wishPlanRows('nora'), isEmpty);
    expect(h.engine.candidate!.collections[ScopeCollections.wishPlans], isNull);
    expect(h.engine.pendingPlanIds, isEmpty);
    final claim = await h.engine.claimWish('w9');
    expect(claim.error, WishPlanError.unavailable);
    expect(await h.queue.entries(), isEmpty);
  });

  test('la web de Nora no escribe deseos de otra persona ni sugerencias',
      () async {
    final h = WebHarness(webPerson: 'nora');
    addTearDown(h.close);
    await h.setup();
    await noraPhone(h);
    await h.engine.sync();
    // Una edición hecha a mano de un deseo de otra persona, o un deseo nuevo
    // sugerido, no sale por la web: solo `createOwnWish` y compañía.
    final before = h.engine.publicDoc!;
    final clock = h.engine.newPublicClock();
    final foreign = before.set(clock, Collections.wishes, 'x1', {
      'recipientId': 'leo',
      'authorPersonId': 'nora',
      'suggested': true,
      'title': 'Balón',
      'year': 2026,
    });
    await expectLater(
      h.engine.save(before, foreign),
      throwsA(isA<Object>()),
    );
    expect(await h.queue.entries(), isEmpty);
    final mine = await h.engine.createOwnWish(
      const VisibleWishPatch(title: 'Libro', year: 2026),
    );
    expect(mine.ok, isTrue);
    // Quitar uno ajeno (de Leo) no se puede.
    await publishNoraWish(h, 'wn');
    h.phone.doc = h.phone.doc.set(h.phone.clock, Collections.wishes, 'wl', {
      'recipientId': 'leo',
      'authorPersonId': 'leo',
      'suggested': false,
      'title': 'Balón',
      'year': 2026,
    });
    await h.phone.engine(h.client).sync();
    await h.engine.sync();
    final other = await h.engine.removeOwnWish('wl');
    expect(other.error, WishError.notWishOwner);
  });

  test('la web de Aritz coge, edita y suelta el plan de un deseo de Nora '
      'por W5 y el móvil lo recoge', () async {
    final h = WebHarness(webPerson: 'aritz');
    addTearDown(h.close);
    await h.setup();
    final web = h.engine.auth.deviceId;
    await protectNora(h);
    await publishNoraWish(h, 'w1');
    await h.engine.sync();
    expect(h.engine.secrets.writablePeople, {'nora'});

    final claim = await h.engine.claimWish('w1', giverId: 'aritz');
    expect(claim.ok, isTrue, reason: '${claim.error}');
    final planId = claim.planId!;
    expect(h.engine.pendingPlanIds, {planId});
    var rows = h.engine.wishPlanRows('nora');
    expect(rows.single.state, WishPlanState.claimed);
    expect(rows.single.plans.single.claimantPersonId, 'aritz');
    final entries = await h.queue.entries();
    expect(entries.single.kind, PendingKind.privateScope);
    expect(entries.single.inboxPerson, 'nora');
    expect(entries.single.newPlans, {planId});
    expect(h.engine.setAsideCount, 0);

    await h.engine.sync();
    expect(h.worker.slotVersions(kV2Sync).keys, contains('nora/$web'));
    // Nada de plan en el común.
    final common = await h.remote();
    expect(common.collections[ScopeCollections.wishPlans], isNull);
    expect(common.canonicalJson(), isNot(contains(planId)));

    await h.phone.engine(h.client).sync();
    var plan = h.phone.scopes['nora']!.record(
      ScopeCollections.wishPlans,
      planId,
    )!;
    expect(plan['claimantPersonId'], 'aritz');
    expect(plan['sourceWishId'], 'w1');
    expect(plan[kWebNewField], isNull);
    await h.engine.sync();
    expect(await h.queue.entries(), isEmpty);
    expect(h.engine.pendingPlanIds, isEmpty);
    rows = h.engine.wishPlanRows('nora');
    expect(rows.single.state, WishPlanState.claimed);

    final edited = await h.engine.editPlan(
      'nora',
      planId,
      const PrivatePlanPatch(
        status: GiftStatus.bought,
        actualCents: 1200,
        giverNote: 'Talla M',
      ),
    );
    expect(edited.ok, isTrue, reason: '${edited.error}');
    await h.engine.sync();
    await h.phone.engine(h.client).sync();
    plan = h.phone.scopes['nora']!.record(ScopeCollections.wishPlans, planId)!;
    expect(plan['status'], 'bought');
    expect(plan['actualCents'], 1200);
    expect(plan['giverNote'], 'Talla M');
    await h.engine.sync();
    expect(await h.queue.entries(), isEmpty);

    final released = await h.engine.releasePlan('nora', planId);
    expect(released.ok, isTrue);
    await h.engine.sync();
    await h.phone.engine(h.client).sync();
    expect(
      h.phone.scopes['nora']!
          .record(ScopeCollections.wishPlans, planId)!
          .isDeleted,
      isTrue,
    );
    await h.engine.sync();
    expect(await h.queue.entries(), isEmpty);
    rows = h.engine.wishPlanRows('nora');
    expect(rows.single.state, WishPlanState.available);
  });

  test('borrar un regalador en la web desasigna el plan en la web y el móvil',
      () async {
    final h = WebHarness(webPerson: 'aritz');
    addTearDown(h.close);
    await h.setup();
    await protectNora(h);
    h.phone.doc = h.phone.doc.set(
      h.phone.clock,
      Collections.givers,
      'nosotros',
      const Giver(
        id: 'nosotros',
        name: 'Nosotros',
        colorIndex: 0,
        householdPays: true,
        archived: false,
      ).toFields(),
    );
    await publishNoraWish(h, 'w1');
    await h.engine.sync();
    final claim = await h.engine.claimWish('w1', giverId: 'nosotros');
    expect(claim.ok, isTrue, reason: '${claim.error}');
    final planId = claim.planId!;
    await h.engine.sync();
    await h.phone.engine(h.client).sync();
    await h.engine.sync();
    expect(h.engine.wishPlanRows('nora').single.plans.single.giverId, 'nosotros');

    final container = ProviderContainer(
      overrides: [
        familyStoreProvider.overrideWithValue(WebFamilyStore(h.vault, h.engine)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(familyControllerProvider.future);
    final controller = container.read(familyControllerProvider.notifier);
    await controller.deleteGiver('nosotros');
    expect(h.engine.wishPlanRows('nora').single.plans.single.giverId, isNull);

    // The phone edits another field before the web publishes the deletion.
    final scope = h.phone.scopes['nora']!;
    final giver = scope
        .record(ScopeCollections.wishPlans, planId)!
        .field('giverId');
    final edit = scope.editPlan(
      h.phone.clock,
      await h.phone.view(),
      planId,
      const PrivatePlanPatch(giverNote: 'Reservado en tienda'),
    );
    expect(edit.ok, isTrue, reason: '${edit.error}');
    h.phone.scopes['nora'] = edit.scope;
    h.phone.state = h.phone.state.copyWith(deferred: {'nora'});
    await h.engine.sync();
    await h.phone.engine(h.client).sync();
    await h.engine.sync();

    expect(
      h.phone.doc.record(Collections.givers, 'nosotros')!.isDeleted,
      isTrue,
    );
    final phone = await projectAuthorized(
      common: h.phone.doc,
      slots: h.phone.slotSet,
      keyring: h.phone.keyring,
      view: await h.phone.view(),
      localScopes: h.phone.scopes,
    );
    for (final row in [
      h.engine.wishPlanRows('nora').single,
      phone.wishPlanRowsFor('nora').single,
    ]) {
      expect(row.state, WishPlanState.claimed);
      expect(row.plans.single.planId, planId);
      expect(row.plans.single.giverId, isNull);
      expect(row.plans.single.giverNote, 'Reservado en tienda');
    }
    expect(
      phone.view.allGifts.singleWhere((g) => g.id == planId).giverId,
      isNull,
    );
    expect(
      h.phone.scopes['nora']!
          .record(ScopeCollections.wishPlans, planId)!
          .field('giverId'),
      giver,
    );
  });

  for (final reassign in [false, true]) {
    final change = reassign
        ? 'reasignación a un regalador activo'
        : 'asignación al regalador borrado';
    for (final phoneFirst in [false, true]) {
      final first = phoneFirst ? 'móvil' : 'web';
      test('$change concurrente con el borrado web ($first primero)', () async {
        final h = WebHarness(webPerson: 'aritz');
        addTearDown(h.close);
        await h.setup();
        await protectNora(h);
        const deletedGiver = 'nosotros';
        const liveGiver = 'leo';
        for (final (id, name) in [
          (deletedGiver, 'Nosotros'),
          (liveGiver, 'Leo'),
        ]) {
          h.phone.doc = h.phone.doc.set(
            h.phone.clock,
            Collections.givers,
            id,
            Giver(
              id: id,
              name: name,
              colorIndex: 0,
              householdPays: true,
              archived: false,
            ).toFields(),
          );
        }
        await publishNoraWish(h, 'w1');
        await h.engine.sync();
        final claim = await h.engine.claimWish(
          'w1',
          giverId: reassign ? deletedGiver : null,
        );
        expect(claim.ok, isTrue, reason: '${claim.error}');
        final planId = claim.planId!;
        await h.engine.sync();
        final phoneEngine = h.phone.engine(h.client);
        await phoneEngine.sync();
        await h.engine.sync();

        final container = ProviderContainer(
          overrides: [
            familyStoreProvider.overrideWithValue(
              WebFamilyStore(h.vault, h.engine),
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(familyControllerProvider.future);
        final controller = container.read(familyControllerProvider.notifier);
        await controller.deleteGiver(deletedGiver);

        // Neither replica has received the other's change yet.
        expect(
          h.phone.doc.record(Collections.givers, deletedGiver)!.isDeleted,
          isFalse,
        );
        final scope = h.phone.scopes['nora']!;
        final assigned = reassign ? liveGiver : deletedGiver;
        final edit = scope.editPlan(
          h.phone.clock,
          await h.phone.view(),
          planId,
          PrivatePlanPatch(giverId: assigned),
        );
        expect(edit.ok, isTrue, reason: '${edit.error}');
        final winningAssignment = edit.scope
            .record(ScopeCollections.wishPlans, planId)!
            .field('giverId');
        expect(winningAssignment?.value, assigned);
        h.phone.scopes['nora'] = edit.scope;
        h.phone.state = h.phone.state.copyWith(deferred: {'nora'});

        if (phoneFirst) await phoneEngine.sync();
        await h.engine.sync();
        await phoneEngine.sync();
        await h.engine.sync();

        expect(await h.queue.entries(), isEmpty);
        expect(
          h.phone.doc.record(Collections.givers, deletedGiver)!.isDeleted,
          isTrue,
        );
        final phone = await projectAuthorized(
          common: h.phone.doc,
          slots: h.phone.slotSet,
          keyring: h.phone.keyring,
          view: await h.phone.view(),
          localScopes: h.phone.scopes,
        );
        final phoneRow = phone.wishPlanRowsFor('nora').single;
        final webRow = h.engine.wishPlanRows('nora').single;
        expect(phoneRow.state, WishPlanState.claimed);
        expect(webRow.state, phoneRow.state);
        expect(webRow.sourceWishId, phoneRow.sourceWishId);
        final phonePlan = phoneRow.plans.single;
        final webPlan = webRow.plans.single;
        final expectedGiver = reassign ? liveGiver : null;
        expect(phonePlan.giverId, expectedGiver);
        expect(
          phone.view.giftsFor('nora').singleWhere((g) => g.id == planId).giverId,
          expectedGiver,
        );
        expect(webPlan.planId, phonePlan.planId);
        expect(webPlan.claimantPersonId, phonePlan.claimantPersonId);
        expect(
          webPlan.toGiftForAuthorizedView(year: 2026).toFields(),
          phonePlan.toGiftForAuthorizedView(year: 2026).toFields(),
        );
        for (final merged in [
          h.phone.scopes['nora']!,
          h.engine.scopeDocFor('nora')!,
        ]) {
          expect(
            merged.record(ScopeCollections.wishPlans, planId)!.field('giverId'),
            winningAssignment,
          );
        }
      });
    }
  }

  test('no hay un segundo «coger» normal: un deseo ya cogido por otra '
      'persona no se coge', () async {
    final h = WebHarness(webPerson: 'aritz');
    addTearDown(h.close);
    await h.setup();
    await protectNora(h);
    await publishNoraWish(h, 'w1');
    h.phone.scopes['nora'] = h.phone.scopes['nora']!.set(
      h.phone.clock,
      ScopeCollections.wishPlans,
      'pl',
      {
        'recipientId': 'nora',
        'sourceWishId': 'w1',
        'claimantPersonId': 'leo',
        'title': 'Patinete',
        'status': 'decided',
      },
    );
    h.phone.state = h.phone.state.copyWith(deferred: {'nora'});
    await h.phone.engine(h.client).sync();
    await h.engine.sync();
    expect(h.engine.wishPlanRows('nora').single.state, WishPlanState.claimed);
    final second = await h.engine.claimWish('w1');
    expect(second.error, WishPlanError.alreadyClaimed);
    expect(await h.queue.entries(), isEmpty);
    // Un deseo que no existe o que es de la propia persona de la web.
    expect((await h.engine.claimWish('nada')).error, WishPlanError.unavailable);
  });

  test('el plan web aceptado sin conexión llega aunque el de Leo se publique primero', () async {
    final h = WebHarness(webPerson: 'aritz');
    addTearDown(h.close);
    await h.setup();
    await protectNora(h);
    await publishNoraWish(h, 'w1');
    final leo = await MemoryV2Phone.create('leo-phone', 'leo', 7,
        familyKey: h.phone.familyKey);
    leo.doc = h.phone.doc;
    await vouchAll([h.phone, leo]);
    h.worker.addCredentialForTesting(kV2Sync, leo.identity.deviceId,
        leo.keys.serviceCredential);
    await h.phone.engine(h.client).sync();
    await leo.engine(h.client).sync();
    await h.phone.engine(h.client).sync();
    await leo.engine(h.client).sync();
    await h.engine.sync();
    final claim = await h.engine.claimWish('w1', planId: 'aritz-plan');
    expect(claim.ok, isTrue);
    expect(
      (await h.engine.editPlan(
        'nora',
        'aritz-plan',
        const PrivatePlanPatch(giverNote: 'Reservado en tienda'),
      )).ok,
      isTrue,
    );

    final leoView = await leo.view();
    final leoClaim = leo.scopes['nora']!.claimWish(
      leo.clock, leoView, leo.doc, 'w1', planId: 'leo-plan',
    );
    expect(leoClaim.ok, isTrue, reason: '${leoClaim.error}');
    final leoEdit = leoClaim.scope.editPlan(
      leo.clock, leoView, 'leo-plan',
      const PrivatePlanPatch(giverNote: 'Guardado en casa'),
    );
    expect(leoEdit.ok, isTrue);
    leo.scopes['nora'] = leoEdit.scope;
    leo.state = leo.state.copyWith(deferred: {'nora'});
    await leo.engine(h.client).sync();

    await h.engine.sync();
    await h.phone.engine(h.client).sync();
    await h.engine.sync();
    final row = deriveWishPlanRows(
      common: h.phone.doc,
      scope: h.phone.scopes['nora']!,
      recipientId: 'nora',
    ).single;
    expect(row.state, WishPlanState.conflictingClaims);
    expect(
      {for (final p in row.plans) p.claimantPersonId: p.giverNote},
      {'aritz': 'Reservado en tienda', 'leo': 'Guardado en casa'},
    );
    expect(
      h.engine.wishPlanRows('nora').single.state,
      WishPlanState.conflictingClaims,
    );
    expect(h.engine.discardedSecretCount, 0);
    expect(await h.queue.entries(), isEmpty);
  });

  test('la web y el móvil de Aritz cogen el mismo deseo sin conexión y '
      'conservan ambas reservas tras el acuse', () async {
    final h = WebHarness(webPerson: 'aritz');
    addTearDown(h.close);
    await h.setup();
    await protectNora(h);
    await publishNoraWish(h, 'w1');
    await h.engine.sync();

    // Los dos dispositivos cogen y editan desde la misma vista del deseo libre.
    const webPlanId = 'web-plan';
    const phonePlanId = 'phone-plan';
    final webClaim = await h.engine.claimWish('w1', planId: webPlanId);
    expect(webClaim.planId, webPlanId);
    final webEdit = await h.engine.editPlan(
      'nora',
      webPlanId,
      const PrivatePlanPatch(
        giverNote: 'Reservado en tienda',
        plannedCents: 1500,
        actualCents: 1200,
      ),
    );
    expect(webEdit.ok, isTrue, reason: '${webEdit.error}');

    final phoneView = await h.phone.view();
    final phoneClaim = h.phone.scopes['nora']!.claimWish(
      h.phone.clock,
      phoneView,
      h.phone.doc,
      'w1',
      planId: phonePlanId,
    );
    expect(phoneClaim.ok, isTrue, reason: '${phoneClaim.error}');
    final phoneEdit = phoneClaim.scope.editPlan(
      h.phone.clock,
      phoneView,
      phonePlanId,
      const PrivatePlanPatch(
        giverNote: 'Guardado en casa',
        plannedCents: 1800,
        actualCents: 1600,
      ),
    );
    expect(phoneEdit.ok, isTrue, reason: '${phoneEdit.error}');
    h.phone.scopes['nora'] = phoneEdit.scope;
    h.phone.state = h.phone.state.copyWith(deferred: {'nora'});

    await h.engine.sync();
    expect(h.engine.pendingPlanIds, {webPlanId});
    await h.phone.engine(h.client).sync();
    await h.engine.sync();
    expect(await h.queue.entries(), isEmpty);
    expect(h.engine.pendingPlanIds, isEmpty);
    expect(h.engine.discardedSecretCount, 0);

    final phoneRow = deriveWishPlanRows(
      common: h.phone.doc,
      scope: h.phone.scopes['nora']!,
      recipientId: 'nora',
    ).single;
    final webRow = h.engine.wishPlanRows('nora').single;
    for (final row in [phoneRow, webRow]) {
      expect(row.state, WishPlanState.conflictingClaims);
      expect({
        for (final p in row.plans)
          p.planId: (p.claimantPersonId, p.giverNote, p.plannedCents, p.actualCents),
      }, {
        webPlanId: ('aritz', 'Reservado en tienda', 1500, 1200),
        phonePlanId: ('aritz', 'Guardado en casa', 1800, 1600),
      });
    }
  });

  for (final (oldId, newId) in [('z', 'a'), ('a', 'z')]) {
    test(
      'soltar $oldId y volver a coger $newId antes de sync conserva la nota',
      () async {
        final h = WebHarness(webPerson: 'aritz');
        addTearDown(h.close);
        await h.setup();
        await protectNora(h);
        await publishNoraWish(h, 'w1');
        await h.engine.sync();
        expect((await h.engine.claimWish('w1', planId: oldId)).ok, isTrue);
        await h.engine.sync();
        await h.phone.engine(h.client).sync();
        await h.engine.sync();
        expect(await h.queue.entries(), isEmpty);

        expect((await h.engine.releasePlan('nora', oldId)).ok, isTrue);
        expect((await h.engine.claimWish('w1', planId: newId)).ok, isTrue);
        expect(
          (await h.engine.editPlan(
            'nora',
            newId,
            const PrivatePlanPatch(giverNote: 'Segunda reserva'),
          )).ok,
          isTrue,
        );
        await h.engine.sync();
        await h.phone.engine(h.client).sync();
        await h.engine.sync();

        final scope = h.phone.scopes['nora']!;
        expect(
          scope.record(ScopeCollections.wishPlans, oldId)?.isDeleted,
          isTrue,
        );
        final plan = scope.plansFor('nora', 'w1').single;
        expect(plan.planId, newId);
        expect(plan.giverNote, 'Segunda reserva');
        expect(await h.queue.entries(), isEmpty);
      },
    );
  }

  test('un buzón antiguo con un plan ya soltado y compactado no lo '
      'resucita', () async {
    final h = WebHarness(webPerson: 'aritz');
    addTearDown(h.close);
    await h.setup();
    final web = h.engine.auth.deviceId;
    await protectNora(h);
    await publishNoraWish(h, 'w1');
    await h.engine.sync();
    final claim = await h.engine.claimWish('w1');
    final planId = claim.planId!;
    await h.engine.sync();
    await h.phone.engine(h.client).sync();
    expect(
      h.phone.scopes['nora']!.record(ScopeCollections.wishPlans, planId),
      isNotNull,
    );
    // El móvil lo suelta y, siendo el único escritor, la lápida se compacta:
    // ni vivo ni lápida.
    h.phone.scopes['nora'] = h.phone.scopes['nora']!.delete(
      h.phone.clock,
      ScopeCollections.wishPlans,
      planId,
    );
    for (var i = 0; i < 2; i++) {
      h.phone.state = h.phone.state.copyWith(deferred: {'nora'});
      await h.phone.engine(h.client).sync();
    }
    expect(
      h.phone.scopes['nora']!.record(ScopeCollections.wishPlans, planId),
      isNull,
    );
    // El Worker sigue sirviendo el buzón antiguo y el móvil lo vuelve a
    // bajar: no entra.
    expect(h.worker.slotVersions(kV2Sync).keys, contains('nora/$web'));
    h.phone.state = h.phone.state.copyWith(
      webInboxDone: const {},
      deferred: {'nora'},
    );
    await h.phone.engine(h.client).sync();
    expect(
      h.phone.scopes['nora']!.record(ScopeCollections.wishPlans, planId),
      isNull,
    );
    // La web confirma por `s[web]` y no lo vuelve a mandar.
    await h.engine.sync();
    expect(await h.queue.entries(), isEmpty);
    expect(h.worker.slotVersions(kV2Sync).keys, isNot(contains('nora/$web')));
  });

  test('con la clave caducada, un cambio privado espera en la cola y nunca '
      'se publica en el común', () async {
    final h = WebHarness(webPerson: 'aritz');
    addTearDown(h.close);
    await h.setup();
    await protectNora(h);
    await publishNoraWish(h, 'w1');
    await h.engine.sync();
    final claim = await h.engine.claimWish('w1');
    final planId = claim.planId!;
    // Caduca la sesión de secretos (bloqueo de 5 minutos) y llega otra
    // acción pública: la cola se vuelve a evaluar sin ninguna clave.
    h.engine.secrets.clear();
    final before = h.engine.publicDoc!;
    await h.engine.save(
      before,
      before.set(h.engine.newPublicClock(), Collections.recipients, 'leo', {
        'name': 'Leo',
      }),
    );
    expect(h.engine.heldSecretCount, 1);
    expect(h.engine.setAsideCount, 0);
    expect(h.engine.publicDoc!.canonicalJson(), isNot(contains(planId)));
    expect(h.engine.candidate!.canonicalJson(), isNot(contains(planId)));
    expect(await h.queue.entries(), hasLength(2));
    // Y con todo sincronizado, el común sigue sin el plan.
    await h.engine.sync();
    expect((await h.remote()).canonicalJson(), isNot(contains(planId)));
    expect(
      (await h.queue.entries()).where((e) => e.kind == PendingKind.privateScope),
      hasLength(1),
    );
    await h.phone.engine(h.client).sync();
    expect(
      h.phone.scopes['nora']!.record(ScopeCollections.wishPlans, planId),
      isNotNull,
    );
  });

  test('un cambio privado sin ninguna clave abierta no es una escritura '
      'pública aunque nadie lo proteja', () async {
    final h = WebHarness(webPerson: 'aritz');
    addTearDown(h.close);
    await h.setup();
    await h.engine.sync();
    final delta = FamilyDoc(
      listId: kV2List,
      collections: {
        ScopeCollections.wishPlans: {
          'p1': FamilyDoc.empty(kV2List)
              .set(h.engine.newScopeClock('nora'), ScopeCollections.wishPlans, 'p1', {
                'recipientId': 'nora',
                'sourceWishId': 'w1',
                'claimantPersonId': 'aritz',
                'title': 'Patinete',
                'status': 'decided',
              })
              .record(ScopeCollections.wishPlans, 'p1')!,
        },
      },
    );
    await h.queue.add(
      delta,
      kind: PendingKind.privateScope,
      inboxPerson: 'nora',
      newPlans: const {'p1'},
    );
    await h.engine.sync();
    expect(h.engine.heldSecretCount, 1);
    expect((await h.remote()).canonicalJson(), isNot(contains('p1')));
    expect(await h.queue.entries(), hasLength(1));
    final entry = (await h.queue.entries()).single;
    expect(webEntryAllowed(h.engine.publicDoc!, entry, const {}), isFalse);
  });

  test('relojes separados: cien ediciones privadas no mueven el siguiente '
      'sello público ni lo que la web recuerda', () async {
    final h = WebHarness(webPerson: 'aritz');
    addTearDown(h.close);
    await h.setup();
    await protectNora(h);
    // El regalo secreto lleva una marca adelantada: si la web inicializara
    // su reloj público desde la candidata, la heredaría.
    final ahead = DateTime.now().millisecondsSinceEpoch + 60000;
    h.phone.scopes['nora'] = FamilyDoc.empty(kV2List).set(
      HlcClock(
        node: 'node-aritz-phone',
        last: Hlc(millis: ahead, counter: 0, node: 'node-aritz-phone'),
      ),
      Collections.gifts,
      's1',
      {
        'recipientId': 'nora',
        'title': 'Patinete',
        'status': 'idea',
        'year': 2026,
      },
    );
    h.phone.state = h.phone.state.copyWith(deferred: {'nora'});
    await publishNoraWish(h, 'w1');
    await h.engine.sync();
    final candidate = h.engine.candidate!;
    expect(candidate.record(Collections.gifts, 's1'), isNotNull);
    final store = WebFamilyStore(h.vault, h.engine);
    await store.load();
    final publicBefore = h.engine.publicStamp;
    final storedBefore = store.latestStoredStamp(candidate);
    // La candidata lleva el sello del secreto; lo público, no.
    expect(candidate.maxStamp! > publicBefore!, isTrue);
    expect(storedBefore, publicBefore);
    final nextPublic = h.engine.newPublicClock().last;
    expect(nextPublic, publicBefore);

    Future<FamilyController> controller(WebFamilyStore store) async {
      final container = ProviderContainer(
        retry: familyRetry,
        overrides: [familyStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      await container.read(familyControllerProvider.future);
      return container.read(familyControllerProvider.notifier);
    }

    final baseline = await controller(WebFamilyStore(h.vault, h.engine));
    final afterPrivateEdits = await controller(store);
    final fixed = Clock.fixed(
      DateTime.fromMillisecondsSinceEpoch(publicBefore.millis),
    );
    Future<Hlc> writePublicGift(FamilyController c) async {
      expect(
        await withClock(
          fixed,
          () => c.upsertGift(
            const Gift(
              id: 'public-gift',
              recipientId: 'leo',
              title: 'Libro',
              status: GiftStatus.idea,
              rawStatus: 'idea',
              surprise: false,
              year: 2026,
            ),
          ),
        ),
        isTrue,
      );
      return h.engine.candidate!
          .record(Collections.gifts, 'public-gift')!
          .field('title')!
          .stamp;
    }

    final baselineStamp = await writePublicGift(baseline);
    await h.queue.ack((await h.queue.entries()).single.id, confirmation: {});

    final claim = await h.engine.claimWish('w1');
    final planId = claim.planId!;
    final scopeBefore = h.engine.scopeStamp('nora');
    for (var i = 0; i < 100; i++) {
      final r = await h.engine.editPlan(
        'nora',
        planId,
        PrivatePlanPatch(giverNote: 'nota $i'),
      );
      expect(r.ok, isTrue);
      await withClock(fixed, afterPrivateEdits.reloadStoredCandidate);
    }
    expect(h.engine.scopeStamp('nora')! > scopeBefore!, isTrue);
    expect(h.engine.publicStamp, publicBefore);
    expect(h.engine.newPublicClock().last, publicBefore);
    expect(store.latestStoredStamp(h.engine.candidate!), storedBefore);
    // Tras recargar la tienda (otra sesión), igual.
    final fresh = WebFamilyStore(h.vault, h.engine);
    await fresh.load();
    expect(fresh.latestStoredStamp(h.engine.candidate!), storedBefore);
    expect(fresh.latestScopeStamp('nora'), h.engine.scopeStamp('nora'));
    expect(await writePublicGift(afterPrivateEdits), baselineStamp);
  });

  test('A1/B3: con un móvil de la 1.0.6 en la familia la web no coge ni '
      'escribe planes, no encola nada, y sus regalos siguen llegando; al '
      'actualizar el móvil ya puede', () async {
    final h = WebHarness(webPerson: 'aritz');
    addTearDown(h.close);
    await h.setup();
    await protectNora(h);
    await publishNoraWish(h, 'w1');
    // El slot de Nora del móvil pasa a ser el de un 1.0.6: sin «wp».
    final mine = h.phone.slotSet.slotOf('nora', 'aritz-phone')!;
    final old = await v106.SealedSlot.seal(
      writerKeys: h.phone.keys,
      writer: 'aritz-phone',
      revision: mine.header.revision + 1,
      key: h.phone.keyring.latestFor('nora')!,
      policy: mine.header.policy,
      doc: h.phone.scopes['nora']!,
    );
    h.worker.plantRawSlotForTesting(
      kV2Sync,
      'nora',
      'aritz-phone',
      encodeBase64Url(old.bytes),
    );
    await h.engine.sync();
    expect(h.engine.secrets.writablePeople, {'nora'});
    expect(h.engine.secrets.opened['nora']!.parts['aritz-phone']!.wishPlans, 0);
    expect(h.engine.wishPlansAllowedFor('nora'), isFalse);

    final claim = await h.engine.claimWish('w1');
    expect(claim.error, WishPlanError.devicesNeedUpdate);
    expect(await h.queue.entries(), isEmpty);
    expect(h.engine.pendingPlanIds, isEmpty);

    // Los regalos secretos sí: el buzón no lleva ningún plan.
    final before = h.engine.candidate!;
    await h.engine.save(
      before,
      before.set(
        HlcClock(node: h.engine.auth.deviceId, last: before.maxStamp),
        Collections.gifts,
        's1',
        {'status': 'bought'},
      ),
    );
    await h.engine.sync();
    await h.phone.engine(h.client).sync();
    expect(
      h.phone.scopes['nora']!.record(Collections.gifts, 's1')!['status'],
      'bought',
    );
    expect(
      h.phone.scopes['nora']!.collections[ScopeCollections.wishPlans],
      isNull,
    );
    // El móvil (ya actualizado: su slot de ahora lleva «wp») permite coger.
    await h.engine.sync();
    expect(h.engine.wishPlansAllowedFor('nora'), isTrue);
    final retry = await h.engine.claimWish('w1');
    expect(retry.ok, isTrue, reason: '${retry.error}');
    expect(await h.queue.entries(), hasLength(1));
  });

  for (final restartAfterStale in [false, true]) {
    test('A-1: si un buzón de regalos sustituye al de planes antes de que el '
        'móvil lo recoja, el plan no se da por entregado: se vuelve a ofrecer y '
        'llega (reinicio tras 412: $restartAfterStale)', () async {
      final h = WebHarness(webPerson: 'aritz');
      addTearDown(h.close);
      await h.setup();
      final web = h.engine.auth.deviceId;
      await protectNora(h);
      await publishNoraWish(h, 'w1');
      await h.engine.sync();
      final claim = await h.engine.claimWish('w1', giverId: 'aritz');
      expect(claim.ok, isTrue, reason: '${claim.error}');
      final planId = claim.planId!;
      await h.engine.sync(); // inbox v1 = {plan}
      final firstVersion = h.worker.slotVersions(kV2Sync)['nora/$web'];
      expect(firstVersion, isNotNull);
      // Before the phone collects it, the web edits Nora's secret gift.
      final before = h.engine.candidate!;
      await h.engine.save(
        before,
        before.set(
          HlcClock(node: web, last: before.maxStamp),
          Collections.gifts,
          's1',
          {'status': 'bought'},
        ),
      );
      var engine = h.engine;
      if (restartAfterStale) {
        h.worker.beforePut = (_) async {
          final latest = (await h.client.getList(h.phone.auth) as V2GetOk).snapshot;
          expect(await h.client.putCommon(h.phone.auth,
              version: latest.version, common: latest.common), isA<V2WriteOk>());
          // The replacement gets a 412 after this session has closed, so
          // the sealed attempt's history still exists at restart.
          engine.stop();
        };
        await expectLater(engine.sync(), throwsStateError);
        expect(h.worker.slotVersions(kV2Sync)['nora/$web'], firstVersion);
        expect(await h.queue.entries(), hasLength(2));
        engine.stop();
        h.vault.lock();
        await h.vault.unlock('123456');
        engine = WebSyncEngine(
          transport: h.client,
          vault: h.vault,
          queue: h.queue,
        );
        addTearDown(engine.stop);
      }
      await engine.sync(); // inbox v2 = {gift} replaces v1
      expect(
        h.worker.slotVersions(kV2Sync)['nora/$web'],
        greaterThan(firstVersion!),
      );
      await h.phone.engine(h.client).sync(); // collects v2 only
      await engine.sync();
      // The plan was never collected: still pending, not delivered, not lost.
      expect(
        h.phone.scopes['nora']!.record(ScopeCollections.wishPlans, planId),
        isNull,
      );
      final pending = await h.queue.entries();
      expect(pending.map((e) => e.newPlans).expand((s) => s), [planId]);
      expect(engine.discardedSecretCount, 0);
      expect(engine.wishPlanRows('nora').single.state, WishPlanState.claimed);
      // It goes in a new inbox of its own and reaches the phone.
      for (var i = 0; i < 3; i++) {
        await h.phone.engine(h.client).sync();
        await engine.sync();
      }
      expect(
        h.phone.scopes['nora']!.record(Collections.gifts, 's1')!['status'],
        'bought',
      );
      expect(
        h.phone.scopes['nora']!.record(ScopeCollections.wishPlans, planId),
        isNotNull,
      );
      expect(await h.queue.entries(), isEmpty);
      expect(engine.wishPlanRows('nora').single.state, WishPlanState.claimed);
    });
  }

  for (final upgradeBeforeRead in [false, true]) {
    test(
      'B-1: el rechazo 1.0.6 nunca se convierte en acuse '
      '(declarante actualizado antes de la lectura: $upgradeBeforeRead)',
      () async {
        final h = WebHarness(webPerson: 'aritz');
        addTearDown(h.close);
        await h.setup();
        final web = h.engine.auth.deviceId;
        await protectNora(h);
        final tablet = await aritzTablet(h);
        await publishNoraWish(h, 'w1');
        await h.engine.sync();
        final claim = await h.engine.claimWish('w1');
        expect(claim.ok, isTrue);
        await h.engine.sync(); // the plan inbox is on the server
        final snap = (await h.client.getList(h.phone.auth) as V2GetOk).snapshot;
        final got = await h.client.getSlot(
          h.phone.auth,
          version: snap.version,
          personId: 'nora',
          deviceId: web,
        ) as V2SlotOk;
        final inbox = SealedSlot.parse(got.data).header.version;
        // A 1.0.6 phone that became entitled later rejects the plan inbox and
        // declares it without «x».
        final mine = h.phone.slotSet.slotOf('nora', 'aritz-phone')!;
        final old = await v106.SealedSlot.seal(
          writerKeys: h.phone.keys,
          writer: 'aritz-phone',
          revision: mine.header.revision + 1,
          key: h.phone.keyring.latestFor('nora')!,
          policy: mine.header.policy,
          doc: h.phone.scopes['nora']!,
          seen: {web: v106.SlotVersion(inbox.epoch, inbox.revision)},
        );
        h.worker.plantRawSlotForTesting(
          kV2Sync,
          'nora',
          'aritz-phone',
          encodeBase64Url(old.bytes),
        );
        final key = 'nora/$web';
        // The old app also persisted its floor and resolved slot cache.
        h.phone.state = V2SyncState.fromJson(
          {
            ...h.phone.state.toJson(),
            'wf': {
              key: [inbox.epoch, inbox.revision],
            },
            'wd': {key: snap.slots.firstWhere((r) => r.key == key).version},
          }..remove('wpf'),
        );
        // Publish the tablet's transitive declaration while its peer lacks wp.
        tablet.state = tablet.state.copyWith(deferred: {'nora'});
        await tablet.engine(h.client).sync();
        expect(
          tablet.scopes['nora']!.record(
            ScopeCollections.wishPlans,
            claim.planId!,
          ),
          isNull,
        );
        if (upgradeBeforeRead) {
          // A newly upgraded declarer can publish its old floor before it reads
          // any inbox, for example when it saves an ordinary surprise locally.
          final upgraded = await SealedSlot.seal(
            writerKeys: h.phone.keys,
            writer: 'aritz-phone',
            revision: mine.header.revision + 2,
            key: h.phone.keyring.latestFor('nora')!,
            policy: mine.header.policy,
            doc: h.phone.scopes['nora']!,
            seen: {web: inbox},
          );
          h.worker.plantRawSlotForTesting(
            kV2Sync,
            'nora',
            'aritz-phone',
            encodeBase64Url(upgraded.bytes),
          );
        }
        await h.engine.sync();
        final entries = await h.queue.entries();
        expect(entries, hasLength(1));
        expect(entries.single.newPlans, {claim.planId});
        expect(h.engine.discardedSecretCount, 0);
        expect(h.engine.heldPlanCount, upgradeBeforeRead ? 0 : 1);
        if (!upgradeBeforeRead) {
          // The original phone upgrades with its saved 1.0.6 state intact.
        h.phone.state = h.phone.state.copyWith(deferred: {'nora'});
          await h.phone.engine(h.client).sync();
        }
        for (var i = 0; i < 3; i++) {
          await tablet.engine(h.client).sync();
          await h.phone.engine(h.client).sync();
          await h.engine.sync();
        }
      for (final phone in [h.phone, tablet]) {
        final opened = await openScope(personId: 'nora', slots: phone.slotSet,
            keyring: phone.keyring, view: await phone.view());
        expect(opened!.doc.plansFor('nora', 'w1').map((p) => p.planId),
            [claim.planId]);
      }
        expect(await h.queue.entries(), isEmpty);
      },
    );
  }

  test('B3: un buzón que el móvil rechaza entero no se da por entregado: '
      'la web lo da por descartado con aviso', () async {
    final h = WebHarness(webPerson: 'aritz');
    addTearDown(h.close);
    await h.setup();
    final web = h.engine.auth.deviceId;
    await protectNora(h);
    await h.engine.sync();
    // Una edición con un sello a un mes vista: el móvil rechaza el buzón
    // entero (marcas del futuro).
    final before = h.engine.candidate!;
    final far = DateTime.now().millisecondsSinceEpoch + 40 * 86400000;
    await h.engine.save(
      before,
      before.set(
        HlcClock(node: web, last: Hlc(millis: far, counter: 0, node: web)),
        Collections.gifts,
        's1',
        {'status': 'bought'},
      ),
    );
    await h.engine.sync();
    expect(h.worker.slotVersions(kV2Sync).keys, contains('nora/$web'));
    await h.phone.engine(h.client).sync();
    expect(
      h.phone.scopes['nora']!.record(Collections.gifts, 's1')!['status'],
      isNot('bought'),
    );
    expect(h.phone.state.webInboxRejected.keys, ['nora/$web']);
    final mineAfter = h.phone.slotSet.slotOf('nora', 'aritz-phone')!;
    expect(mineAfter, isNotNull);
    // La web ve que el móvil declara el buzón y que lo rechazó: no lo da
    // por entregado.
    await h.engine.sync();
    expect(await h.queue.entries(), isEmpty);
    expect(h.engine.discardedSecretCount, 1);
  });

  test('M1: un cambio privado se guarda como «aparte» para que el código '
      'web de la 1.0.6 no lo lea, y esta versión lo encamina por su clase',
      () async {
    final h = WebHarness(webPerson: 'aritz');
    addTearDown(h.close);
    await h.setup();
    await protectNora(h);
    await publishNoraWish(h, 'w1');
    await h.engine.sync();
    final claim = await h.engine.claimWish('w1');
    expect(claim.ok, isTrue);
    final entry = (await h.queue.entries()).single;
    final current = await h.vault.readCurrent();
    final raw =
        await h.vault.crypto.open(
              current.entries[entry.id]!,
              h.vault.opened.key,
              h.vault.opened.header,
              'queue',
              entry.id,
            )
            as Map;
    expect(raw['kind'], 'private');
    expect(raw['aside'], isTrue);
    // Esta versión no lo trata como apartado: va al buzón de su persona.
    expect(entry.setAside, isFalse);
    expect(entry.kind, PendingKind.privateScope);
    expect(h.engine.setAsideCount, 0);
    await h.engine.sync();
    expect(h.engine.setAsideCount, 0);
    expect(h.worker.slotVersions(kV2Sync).keys, contains(
      'nora/${h.engine.auth.deviceId}',
    ));
  });

  test('M1: el común guardado y lo que la web publica pasan por la frontera '
      'de los deseos', () async {
    final h = WebHarness(webPerson: 'aritz');
    addTearDown(h.close);
    await h.setup();
    // Un común con un campo privado de plan en un regalo (otra versión, o
    // un móvil que no pasó por su frontera).
    await h.publish(
      doc: h.phone.doc.set(h.phone.clock, Collections.gifts, 'gx', {
        'recipientId': 'leo',
        'title': 'Libro',
        'status': 'idea',
        'year': 2026,
        'purchaseUrl': 'https://tienda.example/secreto',
      }),
    );
    await h.engine.sync();
    expect((await h.engine.savedCommon()).record(Collections.gifts, 'gx'), isNull);
    expect(h.engine.publicDoc!.record(Collections.gifts, 'gx'), isNull);
    // Una acción pública cualquiera: lo que sube no lo lleva.
    final before = h.engine.publicDoc!;
    await h.engine.save(
      before,
      before.set(h.engine.newPublicClock(), Collections.recipients, 'leo', {
        'name': 'Leo',
      }),
    );
    await h.engine.sync();
    final remote = await h.remote();
    expect(remote.record(Collections.gifts, 'gx'), isNull);
    expect(remote.canonicalJson(), isNot(contains('secreto')));
  });

  test('la web de P enseña desde el principio el bloque fijo «Sorpresas» '
      'de P, con o sin claves ni contenido', () async {
    final h = WebHarness(webPerson: 'nora');
    addTearDown(h.close);
    await h.setup();
    expect(h.engine.secrets.state, isNot(WebSecretsState.open));
    expect(h.engine.showsOwnSurprisesBlock, isTrue);
    expect(h.engine.ownPersonId, 'nora');
    final store = WebFamilyStore(h.vault, h.engine);
    expect(store.showsOwnSurprisesBlock, isTrue);
  });
}

