// ADR 0010, revisión de seguridad de la 1.0.7: familias con móviles de la
// 1.0.6 y de la 1.0.7 a la vez (A1, B3) y planes que llegan por el buzón de la
// web antes que su deseo, o después de que se quitara (M2).
//
// Un 1.0.6 cuenta cualquier colección que no sea `gifts` como ajena y rechaza
// entero el slot o el buzón: los planes solo se escriben si todos los que
// leen el ámbito anuncian «wp», y van siempre en un buzón aparte de los
// regalos.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/protected_doc.dart';
import 'package:regalos/core/sync/protected_envelope.dart';
import 'package:regalos/core/sync/wish_plan.dart';
import 'package:regalos/features/sync/application/sync_v2_engine.dart'
    show V2SyncState;

import 'fixtures/protected_envelope_v106.dart' as v106;
import 'protected_harness.dart';

const _on = PolicyState(hideOwnGifts: true, rev: 1);

Map<String, Object?> _plan(String wish) => {
  'recipientId': 'nora',
  'sourceWishId': wish,
  'claimantPersonId': 'aritz',
  'title': 'Bicicleta',
  'status': 'decided',
};

/// Un deseo de Nora que ya es una lápida.
FamilyDoc _removedWish(String id) =>
    FamilyDoc.empty(kListId).set(clockOf('nora', 2), Collections.wishes, id, {
      for (final n in const [
        'recipientId',
        'authorPersonId',
        'suggested',
        'title',
        'year',
        'occasionId',
        'size',
        'url',
        'description',
      ])
        n: null,
      'deleted': true,
    });

void main() {
  late Family family;
  setUp(() async => family = await Family.create());

  Future<SealedSlot> seal({
    Map<String, SlotVersion> rejected = const {},
    FamilyDoc? doc,
  }) => SealedSlot.seal(
    writerKeys: family.aritz.keys,
    writer: family.aritz.id,
    revision: 1,
    key: family.key,
    policy: _on,
    doc: doc ?? FamilyDoc.empty(kListId),
    rejected: rejected,
  );

  Future<OpenedSlot> open(SealedSlot slot) => slot.open(
    expectedListId: kListId,
    key: family.key,
    signingKey: family.aritz.keys.publicKeys.signing,
  );

  group('«wp» en los slots', () {
    test('un slot de la 1.0.7 anuncia los planes, uno de la 1.0.6 no, y la '
        '1.0.6 sigue abriendo el de la 1.0.7', () async {
      final slot = await seal(
        rejected: {'web-aritz': const SlotVersion(1, 7)},
        doc: FamilyDoc.empty(kListId).set(
          clockOf('aritz', 1),
          Collections.gifts,
          's0',
          giftFields('nora', 'Regalo'),
        ),
      );
      final now = await open(slot);
      expect(now.wishPlans, kWishPlanCapability);
      expect(now.rejectedInboxes, {'web-aritz': const SlotVersion(1, 7)});

      // La 1.0.6 no mira ni «wp» ni «x»: lo abre y ve el regalo.
      final old = await v106.SealedSlot.parse(slot.bytes).open(
        expectedListId: kListId,
        key: family.key,
        signingKey: family.aritz.keys.publicKeys.signing,
      );
      expect(old.foreignRecords, 0);
      expect(old.doc.collections[Collections.gifts], hasLength(1));

      // Y al revés: un slot de la 1.0.6 no anuncia nada.
      final oldSlot = await v106.SealedSlot.seal(
        writerKeys: family.aritz.keys,
        writer: family.aritz.id,
        revision: 1,
        key: family.key,
        policy: _on,
        doc: FamilyDoc.empty(kListId),
      );
      final opened = await open(SealedSlot.parse(oldSlot.bytes));
      expect(opened.wishPlans, 0);
      expect(opened.rejectedInboxes, isEmpty);
    });

    test('los planes solo se permiten si todos los que leen el ámbito los '
        'anuncian, y uno sin slot cuenta como que no', () async {
      final modern = await open(await seal());
      final old = await open(
        SealedSlot.parse(
          (await v106.SealedSlot.seal(
            writerKeys: family.aritz.keys,
            writer: family.aritz.id,
            revision: 1,
            key: family.key,
            policy: _on,
            doc: FamilyDoc.empty(kListId),
          )).bytes,
        ),
      );
      expect(wishPlansAllowed([modern, modern]), isTrue);
      expect(wishPlansAllowed(const <OpenedSlot?>[]), isTrue);
      expect(wishPlansAllowed([modern, old]), isFalse);
      expect(wishPlansAllowed([modern, null]), isFalse);
    });
  });

  test('el estado del móvil guarda los buzones que rechazó', () {
    const state = V2SyncState(
      webInboxRejected: {'nora/web-aritz': SlotVersion(1, 7)},
    );
    final back = V2SyncState.fromJson(jsonDecode(jsonEncode(state.toJson())));
    expect(back.webInboxRejected, {'nora/web-aritz': const SlotVersion(1, 7)});
    expect(const V2SyncState().toJson().containsKey('wx'), isFalse);
  });

  group('buzón de una web con un móvil de la 1.0.6 (A1, B3)', () {
    final c = clockOf('web-aritz', 1);
    FamilyDoc delta({bool gift = false, bool plan = false}) {
      var d = FamilyDoc.empty(kListId);
      if (gift) {
        d = d.set(c, Collections.gifts, 's0', giftFields('nora', 'Regalo'));
      }
      if (plan) d = d.set(c, ScopeCollections.wishPlans, 'p0', _plan('w0'));
      return d;
    }

    WebInboxEntry gift() =>
        WebInboxEntry(id: 'g1', delta: delta(gift: true), newGifts: {'s0'});
    WebInboxEntry plan() =>
        WebInboxEntry(id: 'p1', delta: delta(plan: true), newPlans: {'p0'});

    /// Registros que la 1.0.6 cuenta como ajenos al abrir este buzón; con
    /// alguno, `absorbWebInbox` de la 1.0.6 lo rechaza entero.
    Future<int> foreignIn106(FamilyDoc doc) async {
      final slot = await seal(doc: doc);
      final opened = await v106.SealedSlot.parse(slot.bytes).open(
        expectedListId: kListId,
        key: family.key,
        signingKey: family.aritz.keys.publicKeys.signing,
      );
      return opened.foreignRecords;
    }

    test('con un móvil sin «wp» el plan no entra en el buzón, los regalos sí '
        'y la 1.0.6 no rechaza nada', () async {
      final built = buildWebInbox(
        personId: 'nora',
        scope: FamilyDoc.empty(kListId),
        webPersonId: 'aritz',
        plansAllowed: false,
        entries: [gift(), plan()],
      );
      expect(built.included, ['g1']);
      expect(built.held, ['p1']);
      expect(built.discarded, isEmpty);
      expect(built.doc.collections[ScopeCollections.wishPlans], isNull);
      expect(await foreignIn106(built.doc), 0);
      // Un buzón de solo regalos lo recoge la 1.0.7 como siempre.
      final r = absorbWebInbox(
        scope: FamilyDoc.empty(kListId),
        inbox: await open(await seal(doc: built.doc)),
        nowMillis: 1 << 50,
        webPersonId: 'aritz',
        plansAllowed: false,
      );
      expect(r.absorbed, isTrue);
      expect(r.scope.record(Collections.gifts, 's0'), isNotNull);
    });

    test('lo que la 1.0.6 rechazaría: un buzón con regalos y un plan juntos '
        '(por eso no se mezclan)', () async {
      final both = buildWebInbox(
        personId: 'nora',
        scope: FamilyDoc.empty(kListId),
        webPersonId: 'aritz',
        entries: [gift(), plan()],
      );
      expect(both.included, ['g1', 'p1']);
      expect(await foreignIn106(both.doc), greaterThan(0));
    });

    test('un buzón con planes espera entero mientras algún móvil no los '
        'entienda, y entra en cuanto todos los anuncian', () async {
      final built = buildWebInbox(
        personId: 'nora',
        scope: FamilyDoc.empty(kListId),
        webPersonId: 'aritz',
        entries: [plan()],
      );
      final inbox = await open(await seal(doc: built.doc));
      final waiting = absorbWebInbox(
        scope: FamilyDoc.empty(kListId),
        inbox: inbox,
        nowMillis: 1 << 50,
        webPersonId: 'aritz',
        plansAllowed: false,
        common: _wishCommon('w0'),
      );
      expect(waiting.waiting, isTrue);
      expect(waiting.absorbed, isFalse);
      expect(waiting.rejected, isNull);
      expect(waiting.scope.collections[ScopeCollections.wishPlans], isNull);
      final done = absorbWebInbox(
        scope: FamilyDoc.empty(kListId),
        inbox: inbox,
        nowMillis: 1 << 50,
        webPersonId: 'aritz',
        plansAllowed: true,
        common: _wishCommon('w0'),
      );
      expect(done.absorbed, isTrue);
      expect(done.scope.record(ScopeCollections.wishPlans, 'p0'), isNotNull);
    });
  });

  group('un plan de la web y su deseo (M2)', () {
    Future<OpenedSlot> inboxWithPlan() async {
      final delta = FamilyDoc.empty(
        kListId,
      ).set(clockOf('web-aritz', 1), ScopeCollections.wishPlans, 'p0', _plan('w0'));
      final built = buildWebInbox(
        personId: 'nora',
        scope: FamilyDoc.empty(kListId),
        webPersonId: 'aritz',
        entries: [
          WebInboxEntry(id: 'e1', delta: delta, newPlans: {'p0'}),
        ],
      );
      return open(await seal(doc: built.doc));
    }

    WebInboxAbsorption absorb(OpenedSlot inbox, FamilyDoc common) =>
        absorbWebInbox(
          scope: FamilyDoc.empty(kListId),
          inbox: inbox,
          nowMillis: 1 << 50,
          webPersonId: 'aritz',
          common: common,
        );

    test('si el deseo aún no ha llegado al móvil el buzón espera: no se '
        'descarta ni se da por recogido', () async {
      final r = absorb(await inboxWithPlan(), FamilyDoc.empty(kListId));
      expect(r.waiting, isTrue);
      expect(r.absorbed, isFalse);
      expect(r.discarded, 0);
      expect(r.scope.collections[ScopeCollections.wishPlans], isNull);
      // Cuando el deseo llega, el mismo buzón entra.
      final later = absorb(await inboxWithPlan(), _wishCommon('w0'));
      expect(later.absorbed, isTrue);
      expect(later.discarded, 0);
      expect(later.scope.record(ScopeCollections.wishPlans, 'p0'), isNotNull);
    });

    test('si Nora ya lo quitó el plan entra con su título copiado y sale '
        'como quitado de la lista', () async {
      final common = _removedWish('w0');
      final r = absorb(await inboxWithPlan(), common);
      expect(r.absorbed, isTrue);
      expect(r.discarded, 0);
      expect(r.scope.record(ScopeCollections.wishPlans, 'p0'), isNotNull);
      final rows = deriveWishPlanRows(
        common: common,
        scope: r.scope,
        recipientId: 'nora',
      );
      expect(rows.single.state, WishPlanState.removedFromList);
      expect(rows.single.plans.single.title, 'Bicicleta');
    });

    test('lo demás se sigue comprobando: un deseo vivo de otra persona '
        'descarta el plan', () async {
      final common = FamilyDoc.empty(kListId).set(
        clockOf('leo', 1),
        Collections.wishes,
        'w0',
        {
          'recipientId': 'leo',
          'authorPersonId': 'leo',
          'suggested': false,
          'title': 'Balón',
          'year': 2026,
        },
      );
      final r = absorb(await inboxWithPlan(), common);
      expect(r.absorbed, isTrue);
      expect(r.discarded, 1);
      expect(r.scope.collections[ScopeCollections.wishPlans], isNull);
    });
  });
}

/// Un común con un deseo vivo de Nora.
FamilyDoc _wishCommon(String id) => FamilyDoc.empty(
  kListId,
).set(clockOf('nora', 1), Collections.wishes, id, {
  'recipientId': 'nora',
  'authorPersonId': 'nora',
  'suggested': false,
  'title': 'Bicicleta',
  'year': 2026,
});
