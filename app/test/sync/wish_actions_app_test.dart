// Deseos propios y planes por los controladores reales (ADR 0010, fase 4a):
// quién crea, edita y quita, qué ve cada móvil por los providers, y que el
// móvil de la propia persona no recibe nada de lo que hacen los demás.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/pairing_v2.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/protected_doc.dart';
import 'package:regalos/core/sync/protected_envelope.dart';
import 'package:regalos/core/sync/wish.dart';
import 'package:regalos/core/sync/wish_plan.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/application/family_providers.dart';
import 'package:regalos/features/family/application/gift_search.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/family/presentation/secret_blocks.dart';
import 'package:regalos/features/sync/application/app_sync_v2_local.dart';
import 'package:regalos/features/sync/application/sync_controller.dart';
import 'package:regalos/features/sync/application/sync_v2_engine.dart';

import '../helpers/fake_worker_v2.dart';
import '../helpers/memory_stores.dart';
import 'fixtures/protected_envelope_v106.dart' as v106;
import 'protected_harness.dart';

final _localProvider = FutureProvider<AppSyncV2Local?>(
  (ref) => AppSyncV2Local.load(ref),
);

const _syncId = 'AAAAAAAAAAAAAAAAAAAAAA';
const _wish = 'wbike';

class _Phone {
  _Phone(this.phone, this.member);
  final FakePhone phone;
  final Phone member;

  ProviderContainer get c => phone.container;
  FamilyController get controller => c.read(familyControllerProvider.notifier);
  FamilyStore get store => c.read(familyStoreProvider);
  FamilyDoc get common => c.read(familyControllerProvider).value!.doc;

  /// Vuelve a calcular la proyección y espera a que esté.
  Future<AuthorizedProjection> ready() async {
    c.invalidate(localRegistryReadProvider);
    c.invalidate(authorizedProjectionProvider);
    final projection = await c.read(authorizedProjectionProvider.future);
    return projection!;
  }

  Future<AppSyncV2Local> local() async {
    final local = await phone.container.read(_localProvider.future);
    return local!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Family family;
  late FamilyKey familyKey;
  late FamilyDoc common;

  setUp(() async {
    family = await Family.create();
    familyKey = await FamilyKey.generate();
    final clock = HlcClock(node: family.aritz.id);
    common = commonWithPeople(clock).set(
      clock,
      Collections.meta,
      kProtocolRecordId,
      {kProtocolVersionField: kSyncProtocolV2},
    );
  });

  Future<_Phone> install(
    Phone member, {
    FamilyDoc? doc,
    bool withKey = false,
    SlotSet? slots,
    DeviceRegistry? registry,
  }) async {
    final fake = FakePhone();
    addTearDown(fake.dispose);
    final p = _Phone(fake, member);
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
        key: familyKey,
        doc: doc ?? common,
      ),
    );
    await p.store.saveSyncV2(
      SyncIdentityV2(listId: kListId, deviceId: member.id, syncId: _syncId),
    );
    await p.store.saveRegistry(registry ?? family.registry);
    if (withKey) await keys.saveKeyring(kListId, family.authorizedKeyring);
    if (slots != null) await p.store.saveSlots(slots);
    await fake.container.read(familyControllerProvider.future);
    return p;
  }

  /// El móvil de Leo, también al día, ya ha publicado su slot de Nora: un
  /// plan solo se escribe cuando todos los que leen el bloque anuncian los
  /// planes (revisión de seguridad, A1).
  Future<void> leoPublishes(
    _Phone a, {
    int revision = 1,
    bool v106Slot = false,
  }) async {
    const policy = PolicyState(hideOwnGifts: true, rev: 1);
    final doc = FamilyDoc.empty(kListId);
    final slot = v106Slot
        ? SealedSlot.parse(
            (await v106.SealedSlot.seal(
              writerKeys: family.leo.keys,
              writer: family.leo.id,
              revision: revision,
              key: family.key,
              policy: policy,
              doc: doc,
            )).bytes,
          )
        : await SealedSlot.seal(
            writerKeys: family.leo.keys,
            writer: family.leo.id,
            revision: revision,
            key: family.key,
            policy: policy,
            doc: doc,
          );
    final slots = await a.store.readSlots();
    final (merged, _) = await slots.merge([slot], view: family.view);
    await a.store.saveSlots(merged);
  }

  /// Aritz con la protección de Nora activa y Nora con su móvil al día.
  Future<(_Phone, _Phone)> aritzAndNora({bool leoIsOld = false}) async {
    final a = await install(family.aritz, withKey: true);
    await a.controller.activateProtection('nora');
    await leoPublishes(a, v106Slot: leoIsOld);
    final n = await install(
      family.nora,
      doc: a.common,
      slots: await a.store.readSlots(),
    );
    return (a, n);
  }

  /// Nora apunta [_wish] y Aritz lo recibe.
  Future<void> noraWrites(_Phone a, _Phone n, {String? occasionId}) async {
    final w = await n.controller.createOwnWish(
      VisibleWishPatch(
        title: 'Bicicleta',
        year: 2026,
        occasionId: occasionId,
        description: 'Roja con timbre',
      ),
      id: _wish,
    );
    expect(w.ok, isTrue, reason: '${w.error} ${w.authorError}');
    await a.controller.mergeRemote(n.common, fromNode: family.nora.id);
  }

  group('crear, editar y quitar', () {
    test('Nora crea, edita y quita su deseo; nadie más', () async {
      final (a, n) = await aritzAndNora();
      await noraWrites(a, n);
      final wish = a.common.record(Collections.wishes, _wish)!;
      expect(wish['recipientId'], 'nora');
      expect(wish['authorPersonId'], 'nora');
      expect(wish['suggested'], false);

      // Aritz no edita ni quita el deseo de Nora: no escribe nada.
      final before = a.common.canonicalJson();
      final edit = await a.controller.editVisibleWish(
        _wish,
        const VisibleWishPatch(title: 'Otra cosa'),
      );
      expect(edit.error, WishError.notWishOwner);
      final remove = await a.controller.removeWish(_wish);
      expect(remove.error, WishError.notWishOwner);
      expect(a.common.canonicalJson(), before);

      final mine = await n.controller.editVisibleWish(
        _wish,
        const VisibleWishPatch(title: 'Bicicleta azul'),
      );
      expect(mine.ok, isTrue);
      expect(n.common.wishesFor('nora').single.title, 'Bicicleta azul');
      final gone = await n.controller.removeWish(_wish);
      expect(gone.ok, isTrue);
      expect(n.common.record(Collections.wishes, _wish)!.isDeleted, isTrue);
      expect(n.common.wishesFor('nora'), isEmpty);
    });

    test('Aritz sugiere «Visible para Nora»: la crea y desde entonces solo '
        'Nora la cambia', () async {
      final (a, n) = await aritzAndNora();
      final s = await a.controller.suggestVisibleWish(
        'nora',
        const VisibleWishPatch(title: 'Patines', year: 2026),
        id: 'wskates',
      );
      expect(s.ok, isTrue, reason: '${s.error}');
      final record = a.common.record(Collections.wishes, 'wskates')!;
      expect(record['authorPersonId'], 'aritz');
      expect(record['suggested'], true);
      expect(record['recipientId'], 'nora');
      // Una persona no se sugiere a sí misma.
      final self = await a.controller.suggestVisibleWish(
        'aritz',
        const VisibleWishPatch(title: 'Algo', year: 2026),
      );
      expect(self.error, WishError.suggestionForSelf);
      // Quien sugirió ya no la edita.
      final edit = await a.controller.editVisibleWish(
        'wskates',
        const VisibleWishPatch(title: 'Patines rojos'),
      );
      expect(edit.error, WishError.notWishOwner);
      await n.controller.mergeRemote(a.common, fromNode: family.aritz.id);
      final noraEdit = await n.controller.editVisibleWish(
        'wskates',
        const VisibleWishPatch(title: 'Patines rojos'),
      );
      expect(noraEdit.ok, isTrue);
    });

    test('un móvil revocado no escribe deseos', () async {
      final a = await install(family.aritz, withKey: true);
      final change = await revokeDevice(
        registry: family.registry,
        view: family.view,
        myKeys: family.aritz.keys,
        deviceId: family.leo.id,
      );
      final rev = await install(
        family.leo,
        withKey: true,
        doc: a.common,
        registry: change.registry,
      );
      final before = rev.common.canonicalJson();
      final w = await rev.controller.createOwnWish(
        const VisibleWishPatch(title: 'Algo', year: 2026),
      );
      expect(w.ok, isFalse);
      expect(w.error, WishError.authorRefused);
      expect(rev.common.canonicalJson(), before);
    });

    test(
      'un móvil que cambia de persona no escribe como la anterior',
      () async {
        final (a, n) = await aritzAndNora();
        await n.controller.changeSelfPerson('leo');
        final before = n.common.canonicalJson();
        final w = await n.controller.createOwnWish(
          const VisibleWishPatch(title: 'Algo', year: 2026),
        );
        // Pendiente de aprobar: o se rechaza o escribe como la persona de su
        // ficha avalada, nunca como Nora.
        if (w.ok) {
          expect(
            n.common.record(Collections.wishes, w.wishId!)!['recipientId'],
            isNot('nora'),
          );
        } else {
          expect(w.error, WishError.authorRefused);
          expect(n.common.canonicalJson(), before);
        }
        expect(a.common.wishesFor('nora'), isEmpty);
      },
    );
  });

  group('lo que ve cada móvil por los providers', () {
    test('Aritz coge el deseo: fila cogida, un regalo y su acción', () async {
      final (a, n) = await aritzAndNora();
      await noraWrites(a, n);
      await a.ready();
      var rows = a.c.read(wishPlanRowsProvider('nora'));
      expect(rows.single.state, WishPlanState.available);
      var actions = a.c.read(
        wishActionsProvider((person: 'nora', wishId: _wish)),
      )!;
      expect(actions.canClaim, isTrue);
      expect(actions.canEdit, isFalse);

      final claim = await a.controller.claimWish(_wish, planId: 'p1');
      expect(claim.ok, isTrue, reason: '${claim.write.error}');
      final edit = await a.controller.editWishPlan(
        'nora',
        'p1',
        const PrivatePlanPatch(
          giverId: 'nosotros',
          plannedCents: 4000,
          store: 'Tienda Sol',
          giverNote: 'Nota secreta',
        ),
      );
      expect(edit.ok, isTrue, reason: '${edit.write.error}');
      await a.ready();

      rows = a.c.read(wishPlanRowsProvider('nora'));
      expect(rows.single.state, WishPlanState.claimed);
      actions = a.c.read(wishActionsProvider((person: 'nora', wishId: _wish)))!;
      expect(actions.state, WishPlanState.claimed);
      expect(actions.canClaim, isFalse);
      expect(actions.canEditOwnPlan, isTrue);
      expect(actions.ownPlan!.planId, 'p1');
      // Una fila de deseo, un regalo, un solo precio.
      expect(a.c.read(visibleWishesForProvider('nora')), hasLength(1));
      expect(a.c.read(giftsForProvider('nora')).map((g) => g.id), ['p1']);
      expect(a.c.read(budgetProvider).total.plannedCents, 4000);
      // El buscador encuentra la nota privada en el plan y el texto del
      // deseo; el deseo y su plan salen una vez.
      final byNote = a.c.read(searchResultsProvider('secreta'));
      expect(byNote.gifts.map((g) => g.id), ['p1']);
      expect(byNote.wishes, isEmpty);
      final byDescription = a.c.read(searchResultsProvider('timbre'));
      expect(byDescription.gifts.map((g) => g.id), ['p1']);
      expect(byDescription.wishes, isEmpty);
    });

    test('con un móvil de la 1.0.6 en la familia no se escribe ningún plan: '
        'error tipado, nada en el bloque, y se puede en cuanto se actualiza',
        () async {
      final (a, n) = await aritzAndNora(leoIsOld: true);
      await noraWrites(a, n);
      final before = await a.store.readScope('nora');
      final claim = await a.controller.claimWish(_wish, planId: 'p1');
      expect(claim.write.error, WishPlanError.devicesNeedUpdate);
      expect(claim.pendingReason, isNull);
      expect(
        (await a.store.readScope('nora'))?.canonicalJson(),
        before?.canonicalJson(),
      );
      expect(
        (await a.store.readScope('nora'))?.collections[ScopeCollections
            .wishPlans],
        isNull,
      );
      // Las demás acciones sobre planes tampoco escriben nada.
      expect(
        (await a.controller.editWishPlan(
          'nora',
          'p1',
          const PrivatePlanPatch(status: GiftStatus.bought),
        )).write.error,
        WishPlanError.devicesNeedUpdate,
      );
      expect(
        (await a.controller.releaseWishPlan('nora', 'p1')).write.error,
        WishPlanError.devicesNeedUpdate,
      );
      // Leo actualiza y vuelve a publicar su slot (ahora con «wp»).
      await leoPublishes(a, revision: 2);
      final retry = await a.controller.claimWish(_wish, planId: 'p1');
      expect(retry.write.error, isNull, reason: '${retry.write.error}');
      expect(
        (await a.store.readScope('nora'))!.record(
          ScopeCollections.wishPlans,
          'p1',
        ),
        isNotNull,
      );
    });

    test('Nora no ve sus planes en Presupuesto al sincronizar', () async {
      final clock = HlcClock(node: family.aritz.id);
      common = common.set(clock, Collections.occasions, 'navidad', {
        'kind': 'santa',
        'name': 'Navidad',
        'month': 12,
        'day': 25,
        'recurring': true,
        'archived': false,
        'budgetCents': 10000,
      });
      final (a, n) = await aritzAndNora();
      await noraWrites(a, n, occasionId: 'navidad');
      await n.ready();
      final before = n.c.read(budgetProvider);
      expect(before.total, const BudgetTotals(budgetCents: 10000));
      final claim = await a.controller.claimWish(_wish, planId: 'p1');
      expect(claim.ok, isTrue);
      final edit = await a.controller.editWishPlan(
        'nora',
        'p1',
        const PrivatePlanPatch(
          plannedCents: 4000,
          status: GiftStatus.bought,
          store: 'Tienda Sol',
          giverNote: 'Nota secreta',
        ),
      );
      expect(edit.ok, isTrue, reason: '${edit.write.error}');
      await a.ready();
      final authorizedBudget = a.c.read(budgetProvider);
      expect(authorizedBudget.total.spentCents, 4000);
      expect(authorizedBudget.ofOccasion('navidad').spentCents, 4000);
      expect(authorizedBudget.ofRecipient('nora').spentCents, 4000);
      // Una vuelta real entre los dos móviles.
      final worker = FakeWorkerV2();
      final transport = worker.client();
      final engineA = SyncV2Engine(
        transport: transport,
        local: await a.local(),
      );
      await engineA.ensureCreated();
      worker.addCredentialForTesting(
        _syncId,
        family.nora.id,
        family.nora.keys.serviceCredential,
      );
      await engineA.sync();
      final engineN = SyncV2Engine(
        transport: transport,
        local: await n.local(),
      );
      await engineN.sync();
      await engineA.sync();
      await engineN.sync();

      final projection = await n.ready();
      expect(projection.plansByWish, isEmpty);
      expect(projection.view.gifts, isEmpty);
      expect(projection.wishPlanRowsFor('nora'), isEmpty);
      // Su deseo llega y no cambia con lo que hace Aritz.
      expect(n.c.read(visibleWishesForProvider('nora')), hasLength(1));
      expect(n.c.read(wishPlanRowsProvider('nora')), isEmpty);
      final actions = n.c.read(
        wishActionsProvider((person: 'nora', wishId: _wish)),
      )!;
      expect(actions.isOwner, isTrue);
      expect(actions.canEdit, isTrue);
      expect(actions.canRemove, isTrue);
      expect(actions.canClaim, isFalse);
      expect(actions.state, isNull);
      expect(actions.plans, isEmpty);
      final after = n.c.read(budgetProvider);
      expect(after.total, before.total);
      expect(after.budgeted, before.budgeted);
      expect(after.byOccasion, before.byOccasion);
      expect(after.byRecipient, before.byRecipient);
      expect(after.allGiftsByRecipient, before.allGiftsByRecipient);
      expect(n.c.read(giftsForProvider('nora')), isEmpty);
      expect(n.c.read(searchResultsProvider('secreta')).gifts, isEmpty);
      expect(n.c.read(searchResultsProvider('Tienda')).gifts, isEmpty);
      expect(n.c.read(searchResultsProvider('timbre')).wishes, hasLength(1));
      // Nada privado en lo que guarda: ni en el común ni en los slots.
      expect(await n.store.readScope('nora'), isNull);
      final stored = [
        jsonEncode(n.common.toJson()),
        for (final s in (await n.store.readSlots()).all)
          latin1.decode(s.bytes, allowInvalid: true),
      ].join('\n');
      for (final secret in ['Nota secreta', 'Tienda Sol', 'sourceWishId']) {
        expect(stored, isNot(contains(secret)));
      }
    });

    test('el bloque fijo de Nora existe desde que se une, sin slots, sin '
        'clave y sin planes', () async {
      final n = await install(family.nora);
      expect(await n.store.readSlots(), isA<SlotSet>());
      expect((await n.store.readSlots()).all, isEmpty);
      final projection = await n.ready();
      expect(projection.lockedBlocks, [const SecretBlock('nora')]);
      expect(n.c.read(secretBlocksProvider), [const SecretBlock('nora')]);
      expect(n.c.read(lockedPeopleProvider), {'nora'});
      // Con un deseo y un filtro de año distinto, el bloque sigue igual.
      await n.controller.createOwnWish(
        const VisibleWishPatch(title: 'Libro', year: 2025),
      );
      n.c.read(yearFilterProvider.notifier).set(2026);
      await n.ready();
      expect(n.c.read(lockedPeopleProvider), {'nora'});
      expect(n.c.read(visibleWishesForProvider('nora')), isEmpty);
      n.c.read(yearFilterProvider.notifier).set(null);
      expect(n.c.read(visibleWishesForProvider('nora')), hasLength(1));
    });
  });
}
