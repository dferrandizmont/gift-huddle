import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/pairing_v2.dart';
import 'package:regalos/core/sync/protected_doc.dart';
import 'package:regalos/core/sync/protected_envelope.dart';
import 'package:regalos/core/sync/wish_plan.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';
import 'package:regalos/features/family/data/family_store.dart';

import '../helpers/memory_stores.dart';
import 'fixtures/protected_envelope_v106.dart' as v106;
import 'protected_harness.dart';

const _wish = 'wbike';
const _plan = 'p1';
const _policy = PolicyState(hideOwnGifts: true, rev: 1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Family family;
  late HlcClock clock;
  late FamilyDoc common;
  late FamilyDoc scope;
  late SealedSlot aritzSlot;

  setUp(() async {
    family = await Family.create();
    clock = HlcClock(node: family.aritz.id);
    common =
        writePublishedPolicy(commonWithPeople(clock), clock, 'nora', _policy)
            .set(clock, Collections.meta, kProtocolRecordId, {
              kProtocolVersionField: kSyncProtocolV2,
            })
            .set(clock, Collections.wishes, _wish, {
              'recipientId': 'nora',
              'authorPersonId': 'nora',
              'suggested': false,
              'title': 'Bicicleta',
              'year': 2026,
            });
    final claim = FamilyDoc.empty(kListId).claimWish(
      clock,
      family.view,
      common,
      _wish,
      planId: _plan,
      giverId: 'nosotros',
    );
    expect(claim.ok, isTrue);
    final edit = claim.scope.editPlan(
      clock,
      family.view,
      _plan,
      const PrivatePlanPatch(giverNote: 'Nota de Aritz'),
    );
    expect(edit.ok, isTrue);
    scope = edit.scope;
    aritzSlot = await SealedSlot.seal(
      writerKeys: family.aritz.keys,
      writer: family.aritz.id,
      revision: 1,
      key: family.key,
      policy: _policy,
      doc: scope,
    );
  });

  Future<SealedSlot> leoSlot({required int revision, bool old = false}) async {
    final empty = FamilyDoc.empty(kListId);
    if (old) {
      final slot = await v106.SealedSlot.seal(
        writerKeys: family.leo.keys,
        writer: family.leo.id,
        revision: revision,
        key: family.key,
        policy: _policy,
        doc: empty,
      );
      return SealedSlot.parse(slot.bytes);
    }
    return SealedSlot.seal(
      writerKeys: family.leo.keys,
      writer: family.leo.id,
      revision: revision,
      key: family.key,
      policy: _policy,
      doc: empty,
    );
  }

  Future<({FamilyController controller, FamilyStore store})> install(
    Phone device,
    SlotSet slots,
  ) async {
    final phone = FakePhone();
    addTearDown(phone.dispose);
    final c = phone.container;
    final store = c.read(familyStoreProvider);
    final keys = c.read(deviceKeysStoreProvider);
    await keys.restore(device.keys);
    await keys.saveKeyring(kListId, family.authorizedKeyring);
    await store.saveFamily(
      StoredFamily(
        identity: FamilyIdentity(
          listId: kListId,
          node: device.id,
          deviceName: device.self!,
          paired: true,
          selfRecipientId: device.self,
        ),
        key: await FamilyKey.generate(),
        doc: common,
      ),
    );
    await store.saveSyncV2(
      SyncIdentityV2(
        listId: kListId,
        deviceId: device.id,
        syncId: 'AAAAAAAAAAAAAAAAAAAAAA',
      ),
    );
    await store.saveRegistry(family.registry);
    await store.saveSlots(slots);
    await c.read(familyControllerProvider.future);
    return (
      controller: c.read(familyControllerProvider.notifier),
      store: store,
    );
  }

  for (final removed in [false, true]) {
    test(
      'Leo no cambia ni elimina el plan de Aritz (deseo quitado: $removed)',
      () async {
        if (removed) common = common.delete(clock, Collections.wishes, _wish);
        final slots = await family.setOf([aritzSlot]);
        final (:controller, :store) = await install(family.leo, slots);
        final rows = await controller.wishPlanRows('nora');
        expect(
          rows.single.state,
          removed ? WishPlanState.removedFromList : WishPlanState.claimed,
        );
        expect(rows.single.plans.single.giverNote, 'Nota de Aritz');
        for (final action in <Future<WishPlanOutcome> Function()>[
          () => controller.editWishPlan(
            'nora',
            _plan,
            const PrivatePlanPatch(giverNote: 'Nota de Leo'),
          ),
          () => controller.releaseWishPlan('nora', _plan),
          () => controller.deleteWishPlan('nora', _plan),
          () => controller.convertWishPlanToSurprise(
            'nora',
            _plan,
            year: 2026,
            giftId: 's1',
          ),
        ]) {
          final result = await action();
          expect(result.write.error, WishPlanError.notClaimant);
          expect(result.pendingReason, isNull);
        }
        expect(
          (await store.load())!.doc.canonicalJson(),
          common.canonicalJson(),
        );
        expect(await store.readScope('nora'), isNull);
        expect(
          jsonEncode((await store.readSlots()).toJson()),
          jsonEncode(slots.toJson()),
        );
      },
    );
  }

  test(
    'borrar un regalador espera a que el lector del plan anuncie wp',
    () async {
      final slots = await family.setOf([
        aritzSlot,
        await leoSlot(revision: 1, old: true),
      ]);
      final (:controller, :store) = await install(family.aritz, slots);
      await store.saveScope('nora', scope);
      await expectLater(
        controller.deleteGiver('nosotros'),
        throwsA(WishPlanError.devicesNeedUpdate),
      );
      expect((await store.load())!.doc.canonicalJson(), common.canonicalJson());
      expect(
        (await store.readScope('nora'))!.canonicalJson(),
        scope.canonicalJson(),
      );
      expect(
        jsonEncode((await store.readSlots()).toJson()),
        jsonEncode(slots.toJson()),
      );

      await store.saveSlots(
        await family.setOf([aritzSlot, await leoSlot(revision: 2)]),
      );
      await controller.deleteGiver('nosotros');
      expect(
        (await store.load())!.doc
            .record(Collections.givers, 'nosotros')!
            .isDeleted,
        isTrue,
      );
      final plan = (await store.readScope('nora'))!
          .plansFor('nora', _wish)
          .single;
      expect(plan.giverId, isNull);
      expect(plan.giverNote, 'Nota de Aritz');
    },
  );
}
