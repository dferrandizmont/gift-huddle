import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/protected_doc.dart';
import 'package:regalos/core/sync/protected_envelope.dart';
import 'package:regalos/core/sync/wish.dart';
import 'package:regalos/core/sync/wish_author.dart';
import 'package:regalos/core/sync/wish_boundary.dart';
import 'package:regalos/core/sync/wish_plan.dart';
import 'package:regalos/features/family/application/gift_search.dart';

import 'protected_harness.dart';

/// Fronteras y vistas de los deseos (ADR 0010, fase 4a): lo que ve cada móvil
/// de los deseos y de los planes, y lo que sale como común.
void main() {
  late Family family;
  late FamilyDoc common;
  late WishContext noraWishes;
  const on1 = PolicyState(hideOwnGifts: true, rev: 1);
  const bike = 'wbike';
  const book = 'wbook';
  const game = 'wgame';

  setUp(() async {
    family = await Family.create();
    noraWishes = WishContext.device(
      view: () => family.viewOf(family.nora),
      localKeys: family.nora.keys,
    );
    var doc = commonWithPeople(clockOf('base', 1));
    final c = clockOf('nora-phone', 10);
    for (final (id, title, extra) in [
      (bike, 'Bicicleta', 'Roja'),
      (book, 'Libro de dinosaurios', 'Tapa dura'),
      (game, 'Juego de mesa', 'Para cuatro'),
    ]) {
      doc = doc
          .createOwnWish(
            c,
            noraWishes,
            VisibleWishPatch(
              title: title,
              year: 2026,
              description: extra,
              url: 'https://example.com/$id',
            ),
            id: id,
          )
          .doc;
    }
    common = doc;
  });

  /// El ámbito de Nora con un plan de Aritz para cada deseo de [wishes].
  FamilyDoc scopeFor(
    List<String> wishes, {
    String note = 'Lo envuelvo yo',
    String shop = 'Juguetería Sol',
    String? giverId = 'nosotros',
    FamilyDoc? from,
  }) {
    var scope = FamilyDoc.empty(kListId);
    var at = 100;
    for (final wish in wishes) {
      final claim = scope.claimWish(
        clockOf(family.aritz.id, at++),
        family.viewOf(family.aritz),
        from ?? common,
        wish,
        planId: 'p-$wish',
        giverId: giverId,
      );
      expect(claim.ok, isTrue, reason: '${claim.error}');
      final edit = claim.scope.editPlan(
        clockOf(family.aritz.id, at++),
        family.viewOf(family.aritz),
        'p-$wish',
        PrivatePlanPatch(
          plannedCents: 2500,
          actualCents: 2400,
          store: shop,
          giverNote: note,
          status: GiftStatus.bought,
        ),
      );
      expect(edit.ok, isTrue, reason: '${edit.error}');
      scope = edit.scope;
    }
    return scope;
  }

  Future<SlotSet> slotsOf(FamilyDoc scope) async => family.setOf([
    await SealedSlot.seal(
      writerKeys: family.aritz.keys,
      writer: family.aritz.id,
      revision: 1,
      key: family.key,
      policy: on1,
      doc: scope,
    ),
  ]);

  Future<AuthorizedProjection> project(
    Phone phone, {
    required SlotSet slots,
    required SurpriseKeyring keyring,
    FamilyDoc? doc,
    RegistryView? view,
    int? year,
    Set<String> ownPeople = const {},
  }) => projectAuthorized(
    common: doc ?? common,
    slots: slots,
    keyring: keyring,
    view: view ?? family.viewOf(phone),
    year: year,
    includeArchived: true,
    ownPeople: ownPeople,
  );

  group('el móvil de Nora (la persona)', () {
    test('ve sus deseos, ningún plan y el bloque fijo', () async {
      final slots = await slotsOf(scopeFor([bike, book]));
      final p = await project(
        family.nora,
        slots: slots,
        keyring: SurpriseKeyring.empty,
        ownPeople: {'nora'},
      );
      expect(p.view.visibleWishes.map((w) => w.id).toSet(), {bike, book, game});
      expect(p.plansByWish, isEmpty);
      expect(p.planGiftIds, isEmpty);
      expect(p.secretGiftIds, isEmpty);
      expect(p.view.gifts, isEmpty);
      expect(p.view.allGifts, isEmpty);
      expect(p.wishPlanRowsFor('nora'), isEmpty);
      expect(p.lockedBlocks, [const SecretBlock('nora')]);
      // Nada del plan en lo que pinta: ni la tienda ni la nota.
      final text = jsonEncode(p.doc.toJson());
      expect(text, isNot(contains('Juguetería')));
      expect(text, isNot(contains('envuelvo')));
      expect(text, isNot(contains('sourceWishId')));
    });

    test('el bloque fijo existe con cero planes y sin ningún slot', () async {
      final p = await project(
        family.nora,
        slots: SlotSet.empty,
        keyring: SurpriseKeyring.empty,
        ownPeople: {'nora'},
      );
      expect(p.lockedBlocks, [const SecretBlock('nora')]);
      expect(p.view.visibleWishes, hasLength(3));
    });

    test('aunque tuviera la clave por error, no abre su bloque', () async {
      final slots = await slotsOf(scopeFor([bike]));
      final p = await project(
        family.nora,
        slots: slots,
        keyring: family.authorizedKeyring,
        ownPeople: {'nora'},
      );
      expect(p.plansByWish, isEmpty);
      expect(p.view.gifts, isEmpty);
      expect(p.wishPlanRowsFor('nora'), isEmpty);
    });

    test(
      'el estado de un deseo no cambia con lo que hagan los demás',
      () async {
        final before = await project(
          family.nora,
          slots: SlotSet.empty,
          keyring: SurpriseKeyring.empty,
          ownPeople: {'nora'},
        );
        final after = await project(
          family.nora,
          slots: await slotsOf(scopeFor([bike, book, game])),
          keyring: SurpriseKeyring.empty,
          ownPeople: {'nora'},
        );
        expect(jsonEncode(after.doc.toJson()), jsonEncode(before.doc.toJson()));
        expect(after.view.visibleWishes, before.view.visibleWishes);
        // Presupuesto y totales, intactos y a cero.
        final budget = after.view.budget();
        expect(budget.total.plannedCents, 0);
        expect(budget.total.spentCents, 0);
        expect(
          after.view.grid().cells.values.every(
            (r) => r.values.every((c) => c.giftCount == 0),
          ),
          isTrue,
        );
      },
    );

    test('dos móviles de Nora ven lo mismo', () async {
      final nora2 = await Phone.create('nora-phone-2', 'nora', 9);
      final registry = await registryOf([
        family.aritz,
        family.leo,
        family.nora,
        nora2,
      ]);
      final slots = await slotsOf(scopeFor([bike]));
      final a = await project(
        family.nora,
        slots: slots,
        keyring: SurpriseKeyring.empty,
        view: await family.nora.viewOf(registry),
        ownPeople: {'nora'},
      );
      final b = await project(
        nora2,
        slots: slots,
        keyring: SurpriseKeyring.empty,
        view: await nora2.viewOf(registry),
        ownPeople: {'nora'},
      );
      expect(jsonEncode(a.doc.toJson()), jsonEncode(b.doc.toJson()));
      expect(a.plansByWish, isEmpty);
      expect(b.plansByWish, isEmpty);
    });
  });

  group('el móvil de Aritz (quien regala)', () {
    test('cada plan es un regalo y el deseo libre no cuenta nada', () async {
      final scope = scopeFor([bike]);
      final p = await project(
        family.aritz,
        slots: await slotsOf(scope),
        keyring: family.authorizedKeyring,
      );
      // Tres deseos visibles; solo uno cogido.
      expect(p.view.visibleWishes, hasLength(3));
      expect(p.plansByWish.keys, [bike]);
      expect(p.view.gifts.map((g) => g.id), ['p-$bike']);
      final gift = p.view.gifts.single;
      expect(gift.recipientId, 'nora');
      expect(gift.title, 'Bicicleta');
      expect(gift.store, 'Juguetería Sol');
      expect(gift.note, 'Lo envuelvo yo');
      expect(gift.status, GiftStatus.bought);
      expect(gift.year, 2026);
      expect(p.secretGiftIds, contains('p-$bike'));
      expect(p.planGiftIds, {'p-$bike'});
      // Exactamente un regalo en el presupuesto.
      final budget = p.view.budget();
      expect(budget.total.plannedCents, 2500);
      expect(budget.total.spentCents, 2400);
      expect(p.view.forReparto().gifts, hasLength(1));
      // Los deseos libres no tienen fila de Reparto.
      final cells = p.view.grid().cells['nora']!.values;
      expect(cells.fold<int>(0, (n, c) => n + c.giftCount), 1);
    });

    test('el presupuesto de la vista incluye un plan sin asignar', () async {
      final slots = await slotsOf(scopeFor([bike], giverId: null));
      final p = await project(
        family.aritz,
        slots: slots,
        keyring: family.authorizedKeyring,
      );
      expect(p.view.gifts.single.giverId, isNull);
      expect(p.view.planGiftIds, {'p-$bike'});
      final budget = p.view.budget();
      expect(budget.total.plannedCents, 2500);
      expect(budget.total.spentCents, 2400);
      expect(budget.total.expectedCents, 2400);
      expect(budget.total.boughtCents, 2400);
      expect(budget.ofRecipient('nora').spentCents, 2400);
    });

    test(
      'estados derivados: disponible, cogido y quitado de la lista',
      () async {
        final scope = scopeFor([bike]);
        final p = await project(
          family.aritz,
          slots: await slotsOf(scope),
          keyring: family.authorizedKeyring,
        );
        final rows = {
          for (final r in p.wishPlanRowsFor('nora')) r.sourceWishId: r.state,
        };
        expect(rows, {
          bike: WishPlanState.claimed,
          book: WishPlanState.available,
          game: WishPlanState.available,
        });
        // Nora quita el deseo cogido: queda el plan.
        final removed = common.removeWish(
          clockOf(family.nora.id, 500),
          noraWishes,
          bike,
        );
        expect(removed.ok, isTrue);
        final after = await project(
          family.aritz,
          slots: await slotsOf(scope),
          keyring: family.authorizedKeyring,
          doc: removed.doc,
        );
        final row = after
            .wishPlanRowsFor('nora')
            .firstWhere((r) => r.sourceWishId == bike);
        expect(row.state, WishPlanState.removedFromList);
        expect(row.wish, isNull);
        expect(
          after.view.visibleWishes.map((w) => w.id),
          isNot(contains(bike)),
        );
        // El regalo sigue con lo que cogió, y cuenta una vez.
        expect(after.view.gifts.map((g) => g.id), ['p-$bike']);
        expect(after.view.budget().total.plannedCents, 2500);
      },
    );

    test(
      'dos reservas desconectadas: dos planes, dos regalos, conflicto',
      () async {
        // Leo no ve el plan de Aritz al coger a la vez: se junta al fusionar.
        final leo = FamilyDoc.empty(kListId).claimWish(
          clockOf(family.leo.id, 300),
          family.viewOf(family.leo),
          common,
          bike,
          planId: 'p-leo',
        );
        expect(leo.ok, isTrue);
        final scope = scopeFor([bike]).merge(leo.scope);
        final p = await project(
          family.aritz,
          slots: await slotsOf(scope),
          keyring: family.authorizedKeyring,
        );
        expect(p.plansByWish[bike], hasLength(2));
        expect(p.view.gifts, hasLength(2));
        final row = p
            .wishPlanRowsFor('nora')
            .firstWhere((r) => r.sourceWishId == bike);
        expect(row.state, WishPlanState.conflictingClaims);
      },
    );

    test('cero, uno y cinco planes: tantos regalos como planes', () async {
      var doc = common;
      final c = clockOf('nora-phone', 50);
      for (var i = 0; i < 4; i++) {
        doc = doc
            .createOwnWish(
              c,
              noraWishes,
              VisibleWishPatch(title: 'Extra $i', year: 2026),
              id: 'wx$i',
            )
            .doc;
      }
      final all = [bike, book, game, 'wx0', 'wx1'];
      for (final n in [0, 1, 5]) {
        final p = await project(
          family.aritz,
          slots: await slotsOf(scopeFor(all.take(n).toList(), from: doc)),
          keyring: family.authorizedKeyring,
          doc: doc,
        );
        expect(p.view.gifts, hasLength(n), reason: '$n planes');
        expect(p.view.budget().total.plannedCents, 2500 * n);
        expect(p.view.visibleWishes, hasLength(7));
      }
    });

    test('un año archivado y su filtro', () async {
      final old = common
          .createOwnWish(
            clockOf('nora-phone', 60),
            noraWishes,
            const VisibleWishPatch(title: 'Cometa', year: 2025),
            id: 'wold',
          )
          .doc;
      final slots = await slotsOf(scopeFor(['wold'], from: old));
      final all = await project(
        family.aritz,
        slots: slots,
        keyring: family.authorizedKeyring,
        doc: old,
      );
      expect(all.view.gifts.map((g) => g.year), [2025]);
      final y2026 = await project(
        family.aritz,
        slots: slots,
        keyring: family.authorizedKeyring,
        doc: old,
        year: 2026,
      );
      expect(y2026.view.gifts, isEmpty);
      expect(y2026.view.budget().total.plannedCents, 0);
      expect(
        y2026.view.visibleWishes.map((w) => w.id),
        isNot(contains('wold')),
      );
      expect(y2026.view.allVisibleWishes.map((w) => w.id), contains('wold'));
    });

    test(
      'un plan de quien no paga la casa no cuenta en su presupuesto',
      () async {
        final p = await project(
          family.aritz,
          slots: await slotsOf(scopeFor([bike])),
          keyring: family.authorizedKeyring,
          doc: common.set(
            clockOf('aritz-phone', 70),
            Collections.givers,
            'nosotros',
            {'householdPays': false},
          ),
        );
        expect(p.view.gifts, hasLength(1));
        expect(p.view.budget().total.plannedCents, 0);
      },
    );
  });

  group('Leo sin móvil', () {
    test('nadie le sugiere un deseo visible y nada cambia para él', () async {
      final registry = await registryOf([family.aritz, family.nora]);
      final view = await family.aritz.viewOf(registry);
      final ctx = WishContext.device(
        view: () => view,
        localKeys: family.aritz.keys,
      );
      final w = common.suggestVisibleWish(
        clockOf(family.aritz.id, 80),
        ctx,
        'leo',
        const VisibleWishPatch(title: 'Patinete', year: 2026),
      );
      expect(w.error, WishError.recipientHasNoDevice);
      final gifts = common.set(
        clockOf(family.aritz.id, 81),
        Collections.gifts,
        'g1',
        giftFields('leo', 'Pelota'),
      );
      final p = await projectAuthorized(
        common: gifts,
        slots: SlotSet.empty,
        keyring: SurpriseKeyring.empty,
        view: view,
      );
      expect(p.lockedBlocks, isEmpty);
      expect(p.view.gifts.map((g) => g.id), ['g1']);
      expect(
        p.view.visibleWishes.where((w) => w.recipientId == 'leo'),
        isEmpty,
      );
    });
  });

  group('búsqueda', () {
    test(
      'el deseo se busca por título, descripción y enlace para todos',
      () async {
        final nora = await project(
          family.nora,
          slots: SlotSet.empty,
          keyring: SurpriseKeyring.empty,
          ownPeople: {'nora'},
        );
        final wishes = nora.view.visibleWishes;
        bool found(String q) =>
            wishes.any((w) => wishMatchesQuery(w, 'Nora', q));
        expect(found('dinosaurios'), isTrue);
        expect(found('tapa dura'), isTrue);
        expect(found('example.com/wbike'), isTrue);
        expect(found('Juguetería'), isFalse);
      },
    );

    test(
      'la tienda y la nota del plan solo se buscan en un plan abierto',
      () async {
        final slots = await slotsOf(scopeFor([bike]));
        final aritz = await project(
          family.aritz,
          slots: slots,
          keyring: family.authorizedKeyring,
        );
        final nora = await project(
          family.nora,
          slots: slots,
          keyring: SurpriseKeyring.empty,
          ownPeople: {'nora'},
        );
        bool giftFound(AuthorizedProjection p, String q) =>
            p.view.gifts.any((g) => giftMatchesQuery(g, 'Nora', q));
        expect(giftFound(aritz, 'envuelvo'), isTrue);
        expect(giftFound(aritz, 'Juguetería'), isTrue);
        expect(giftFound(nora, 'envuelvo'), isFalse);
        expect(giftFound(nora, 'Juguetería'), isFalse);
        // Un deseo con plan sale una vez en el móvil de Aritz.
        expect(aritz.plansByWish[bike], isNotEmpty);
        expect(nora.plansByWish, isEmpty);
      },
    );
  });

  group('lo que sale como común', () {
    Map<String, Object?> planFields() => <String, Object?>{
      'recipientId': 'nora',
      'sourceWishId': bike,
      'claimantPersonId': 'aritz',
      'title': 'Bicicleta',
      'status': 'decided',
      'giverNote': 'secreto',
    };

    Future<FamilyDoc> publishable(FamilyDoc doc) async => publishableCommon(
      common: doc,
      slots: SlotSet.empty,
      keyring: family.authorizedKeyring,
      view: family.viewOf(family.aritz),
    );

    test(
      'con regalos vacíos, nunca sale wishPlans ni un campo de plan',
      () async {
        var dirty = common.set(
          clockOf('x', 5),
          ScopeCollections.wishPlans,
          'p1',
          planFields(),
        );
        dirty = dirty.set(clockOf('x', 6), Collections.meta, 'm', {
          'sourceWishId': bike,
        });
        expect(dirty.collections[Collections.gifts], isNull);
        final out = await publishable(dirty);
        expect(
          out.collections.containsKey(ScopeCollections.wishPlans),
          isFalse,
        );
        expect(out.record(Collections.meta, 'm'), isNull);
        final raw = jsonEncode(out.toJson());
        expect(raw, isNot(contains('sourceWishId')));
        expect(raw, isNot(contains('giverNote')));
        expect(raw, isNot(contains('claimantPersonId')));
        // Los deseos sí.
        expect(out.wishesFor('nora'), hasLength(3));
      },
    );

    test('un plan colado en gifts no sale', () async {
      final dirty = common.set(clockOf('x', 5), Collections.gifts, 'g1', {
        ...giftFields('nora', 'Otro'),
        ...planFields(),
      });
      final out = await publishable(dirty);
      expect(out.record(Collections.gifts, 'g1'), isNull);
    });

    test(
      'los deseos salen en su única forma y las lápidas se conservan',
      () async {
        final removed = common
            .removeWish(clockOf('nora-phone', 90), noraWishes, bike)
            .doc;
        final dirty = removed.set(clockOf('x', 95), Collections.wishes, book, {
          'sourceWishId': 'zzz',
        });
        final out = await publishable(dirty);
        expect(out.record(Collections.wishes, bike)!.isDeleted, isTrue);
        expect(
          validateWishRecord(out.record(Collections.wishes, bike)!),
          isNull,
        );
        expect(
          out.record(Collections.wishes, book)!.fields.keys,
          isNot(contains('sourceWishId')),
        );
        expect(out.wishesFor('nora').map((w) => w.id).toSet(), {book, game});
      },
    );

    test('un deseo mal formado no sale', () async {
      final dirty = common.set(clockOf('x', 5), Collections.wishes, 'wbad', {
        'recipientId': 'nora',
        'title': 'Sin año ni autor',
      });
      final out = await publishable(dirty);
      expect(out.record(Collections.wishes, 'wbad'), isNull);
    });

    test('el común limpio es el mismo objeto (no hay trabajo de más)', () {
      expect(identical(common.wishBoundary(), common), isTrue);
    });
  });
}
