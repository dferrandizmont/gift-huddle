import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/protected_envelope.dart';
import 'package:regalos/core/sync/wish.dart';
import 'package:regalos/core/sync/wish_author.dart';
import 'package:regalos/core/sync/wish_plan.dart';

import 'protected_harness.dart';

/// Planes de deseos (ADR 0010, fase 3): coger, editar, soltar, convertir,
/// conflictos y estados derivados, sobre el documento del ámbito secreto.
void main() {
  late Family family;
  late FamilyDoc common;
  late WishContext noraWishes;
  const wishBike = 'wbike';
  const wishBook = 'wbook';

  setUp(() async {
    family = await Family.create();
    noraWishes = WishContext.device(
      view: () => family.viewOf(family.nora),
      localKeys: family.nora.keys,
    );
    var doc = commonWithPeople(clockOf('base', 1));
    final c = clockOf('nora-phone', 10);
    doc = doc
        .createOwnWish(
          c,
          noraWishes,
          const VisibleWishPatch(
            title: 'Bicicleta',
            year: 2026,
            size: '8 años',
            url: 'https://example.com/bici',
            description: 'Roja',
          ),
          id: wishBike,
        )
        .doc;
    doc = doc
        .createOwnWish(
          c,
          noraWishes,
          const VisibleWishPatch(title: 'Libro', year: 2026),
          id: wishBook,
        )
        .doc;
    common = doc;
  });

  FamilyDoc emptyScope() => FamilyDoc.empty(kListId);

  WishPlanWrite claimAs(
    Phone phone,
    FamilyDoc scope,
    String wishId, {
    String? planId,
    int at = 100,
    FamilyDoc? from,
  }) => scope.claimWish(
    clockOf(phone.id, at),
    family.viewOf(phone),
    from ?? common,
    wishId,
    planId: planId,
  );

  group('coger', () {
    test('copia solo título, talla y enlace y escribe solo en wishPlans', () {
      final r = claimAs(family.aritz, emptyScope(), wishBike, planId: 'p1');
      expect(r.ok, isTrue);
      expect(r.planId, 'p1');
      expect(r.scope.collections.keys, [ScopeCollections.wishPlans]);
      final plan = WishPlan.fromRecord(
        r.scope.record(ScopeCollections.wishPlans, 'p1')!,
      )!;
      expect(plan.recipientId, 'nora');
      expect(plan.sourceWishId, wishBike);
      expect(plan.claimantPersonId, 'aritz');
      expect(plan.title, 'Bicicleta');
      expect(plan.size, '8 años');
      expect(plan.url, 'https://example.com/bici');
      expect(plan.status, GiftStatus.decided);
      final record = r.scope.record(ScopeCollections.wishPlans, 'p1')!;
      expect(record.fields.keys.toSet(), {
        'recipientId',
        'sourceWishId',
        'claimantPersonId',
        'title',
        'size',
        'url',
        'status',
      });
      // La descripción del deseo no se copia.
      expect(r.scope.canonicalJson(), isNot(contains('Roja')));
    });

    test('el plan más grande que cabe cabe en el registro secreto', () {
      final big = common
          .createOwnWish(
            clockOf('nora-phone', 20),
            noraWishes,
            VisibleWishPatch(
              title: 'T' * 500,
              year: 2026,
              size: 'S' * 100,
              url: 'https://example.com/${'u' * 450}',
            ),
            id: 'wbig',
          )
          .doc;
      expect(
        wishCopyBytes(
          title: 'T' * 500,
          size: 'S' * 100,
          url: 'https://example.com/${'u' * 450}',
        ),
        lessThanOrEqualTo(kMaxWishCopyBytes),
      );
      final r = claimAs(
        family.aritz,
        emptyScope(),
        'wbig',
        planId: 'p-${'x' * 34}',
        from: big,
      );
      expect(r.ok, isTrue, reason: '${r.error}');
      final bytes = surpriseRecordBytes(
        r.scope.record(ScopeCollections.wishPlans, r.planId!)!,
      );
      expect(bytes, lessThanOrEqualTo(kMaxSurpriseGiftBytes));
    });

    test('no toca el deseo de P ni el común', () {
      final before = common.canonicalJson();
      claimAs(family.aritz, emptyScope(), wishBike);
      expect(common.canonicalJson(), before);
    });

    test('el móvil de P no puede coger nada', () {
      final r = claimAs(family.nora, emptyScope(), wishBike);
      expect(r.error, WishPlanError.notEntitled);
      expect(r.scope.collections, isEmpty);
    });

    test('deseo inexistente o quitado', () {
      expect(
        claimAs(family.aritz, emptyScope(), 'nope').error,
        WishPlanError.wishNotFound,
      );
      final removed = common
          .removeWish(clockOf('nora-phone', 50), noraWishes, wishBike)
          .doc;
      expect(
        claimAs(family.aritz, emptyScope(), wishBike, from: removed).error,
        WishPlanError.wishRemoved,
      );
    });

    test('un reintento reutiliza el id guardado y no escribe otro plan', () {
      final first = claimAs(family.aritz, emptyScope(), wishBike, planId: 'p1');
      final retry = claimAs(
        family.aritz,
        first.scope,
        wishBike,
        planId: 'p1',
        at: 200,
      );
      expect(retry.ok, isTrue);
      expect(retry.planId, 'p1');
      expect(identical(retry.scope, first.scope), isTrue);
      // Sin id guardado, también reutiliza el plan vivo de la misma persona.
      final noId = claimAs(family.aritz, first.scope, wishBike, at: 300);
      expect(noId.planId, 'p1');
      expect(identical(noId.scope, first.scope), isTrue);
      expect(first.scope.livePlans, hasLength(1));
    });

    test('una reserva visible de otra persona bloquea la segunda', () {
      final aritz = claimAs(family.aritz, emptyScope(), wishBike);
      final leo = claimAs(family.leo, aritz.scope, wishBike, at: 200);
      expect(leo.error, WishPlanError.alreadyClaimed);
      expect(identical(leo.scope, aritz.scope), isTrue);
      // Otro deseo sí.
      expect(claimAs(family.leo, aritz.scope, wishBook).ok, isTrue);
    });

    test('un id que ya fue de otro plan no se reutiliza', () {
      final a = claimAs(family.aritz, emptyScope(), wishBike, planId: 'p1');
      final other = claimAs(family.aritz, a.scope, wishBook, planId: 'p1');
      expect(other.error, WishPlanError.planIdInUse);
      final released = a.scope.releasePlan(
        clockOf('aritz-phone', 150),
        family.viewOf(family.aritz),
        'p1',
      );
      final again = claimAs(
        family.aritz,
        released.scope,
        wishBike,
        planId: 'p1',
        at: 300,
      );
      expect(again.error, WishPlanError.planIdInUse);
    });
  });

  group('soltar y volver a coger', () {
    test('releasePlan deja una lápida sin contenido y se puede volver a '
        'coger con un id nuevo', () {
      final view = family.viewOf(family.aritz);
      final a = claimAs(family.aritz, emptyScope(), wishBike, planId: 'p1');
      final r = a.scope.releasePlan(clockOf('aritz-phone', 200), view, 'p1');
      expect(r.ok, isTrue);
      final tomb = r.scope.record(ScopeCollections.wishPlans, 'p1')!;
      expect(tomb.isDeleted, isTrue);
      expect(tomb.hasTombstoneContent, isFalse);
      expect(r.scope.canonicalJson(), isNot(contains('Bicicleta')));
      expect(r.scope.livePlans, isEmpty);
      // Soltar otra vez no escribe.
      final twice = r.scope.releasePlan(
        clockOf('aritz-phone', 300),
        view,
        'p1',
      );
      expect(twice.ok, isTrue);
      expect(identical(twice.scope, r.scope), isTrue);
      final reclaim = claimAs(family.aritz, r.scope, wishBike, at: 400);
      expect(reclaim.ok, isTrue);
      expect(reclaim.planId, isNot('p1'));
      expect(reclaim.scope.livePlans.map((p) => p.planId), [reclaim.planId]);
      expect(
        reclaim.scope.record(ScopeCollections.wishPlans, 'p1')!.isDeleted,
        isTrue,
      );
    });

    test('deletePlan hace lo mismo y no existe un plan que no existe', () {
      final view = family.viewOf(family.aritz);
      final a = claimAs(family.aritz, emptyScope(), wishBike, planId: 'p1');
      final r = a.scope.deletePlan(clockOf('aritz-phone', 200), view, 'p1');
      expect(r.scope.record(ScopeCollections.wishPlans, 'p1')!.isDeleted, true);
      expect(
        a.scope.deletePlan(clockOf('aritz-phone', 200), view, 'nope').error,
        WishPlanError.planNotFound,
      );
    });

    test('la lápida gana a una edición concurrente', () {
      final view = family.viewOf(family.aritz);
      final a = claimAs(family.aritz, emptyScope(), wishBike, planId: 'p1');
      final edited = a.scope.editPlan(
        clockOf('leo-phone', 500),
        family.viewOf(family.leo),
        'p1',
        const PrivatePlanPatch(store: 'Tienda'),
      );
      final released = a.scope.releasePlan(
        clockOf('aritz-phone', 200),
        view,
        'p1',
      );
      final merged = edited.scope.merge(released.scope);
      expect(merged.record(ScopeCollections.wishPlans, 'p1')!.isDeleted, true);
      expect(merged.canonicalJson(), isNot(contains('Tienda')));
      expect(
        merged.canonicalJson(),
        merged.merge(edited.scope).canonicalJson(),
      );
    });
  });

  group('dos reservas desconectadas', () {
    test('se conservan las dos y se expone el conflicto', () {
      final a = claimAs(family.aritz, emptyScope(), wishBike, planId: 'pa');
      final l = claimAs(family.leo, emptyScope(), wishBike, planId: 'pl');
      expect(a.ok && l.ok, isTrue);
      final merged = a.scope.merge(l.scope);
      expect(merged.livePlans.map((p) => p.claimantPersonId), ['aritz', 'leo']);
      final rows = deriveWishPlanRows(
        common: common,
        scope: merged,
        recipientId: 'nora',
      );
      final bike = rows.singleWhere((r) => r.sourceWishId == wishBike);
      expect(bike.state, WishPlanState.conflictingClaims);
      expect(bike.plans, hasLength(2));
      expect(
        rows.singleWhere((r) => r.sourceWishId == wishBook).state,
        WishPlanState.available,
      );
      // Se resuelve soltando uno.
      final resolved = merged.releasePlan(
        clockOf('leo-phone', 900),
        family.viewOf(family.leo),
        'pl',
      );
      expect(resolved.ok, isTrue);
      final after = deriveWishPlanRows(
        common: common,
        scope: resolved.scope,
        recipientId: 'nora',
      );
      expect(
        after.singleWhere((r) => r.sourceWishId == wishBike).state,
        WishPlanState.claimed,
      );
    });

    test('el orden de la fusión no cambia nada', () {
      final a = claimAs(family.aritz, emptyScope(), wishBike, planId: 'pa');
      final l = claimAs(family.leo, emptyScope(), wishBike, planId: 'pl');
      expect(
        a.scope.merge(l.scope).canonicalJson(),
        l.scope.merge(a.scope).canonicalJson(),
      );
    });
  });

  group('estados derivados', () {
    test('available, claimed y removedFromList', () {
      final a = claimAs(family.aritz, emptyScope(), wishBike, planId: 'p1');
      List<WishPlanRow> rows(FamilyDoc c, FamilyDoc s) =>
          deriveWishPlanRows(common: c, scope: s, recipientId: 'nora');
      expect(
        rows(common, emptyScope()).map((r) => r.state),
        everyElement(WishPlanState.available),
      );
      expect(
        rows(
          common,
          a.scope,
        ).singleWhere((r) => r.sourceWishId == wishBike).state,
        WishPlanState.claimed,
      );
      // P quita el deseo (después de recibir la reserva).
      final removed = common
          .removeWish(clockOf('nora-phone', 50), noraWishes, wishBike)
          .doc;
      final row = rows(
        removed,
        a.scope,
      ).singleWhere((r) => r.sourceWishId == wishBike);
      expect(row.state, WishPlanState.removedFromList);
      expect(row.wish, isNull);
      expect(row.plans.single.title, 'Bicicleta');
      expect(row.plans.single.size, '8 años');
      // Sin plan, un deseo quitado no sale.
      expect(rows(removed, emptyScope()).map((r) => r.sourceWishId), [
        wishBook,
      ]);
    });

    test('P quita el deseo antes de recibir la reserva: al juntarlo, '
        'removedFromList y el plan sigue editable', () {
      // Aritz coge con su común (aún con el deseo); Nora lo quitó antes.
      final a = claimAs(family.aritz, emptyScope(), wishBike, planId: 'p1');
      final removed = common
          .removeWish(clockOf('nora-phone', 50), noraWishes, wishBike)
          .doc;
      final joined = common.merge(removed);
      final row = deriveWishPlanRows(
        common: joined,
        scope: a.scope,
        recipientId: 'nora',
      ).singleWhere((r) => r.sourceWishId == wishBike);
      expect(row.state, WishPlanState.removedFromList);
      // El plan sigue editable, con su copia.
      final edited = a.scope.editPlan(
        clockOf('aritz-phone', 300),
        family.viewOf(family.aritz),
        'p1',
        const PrivatePlanPatch(
          status: GiftStatus.bought,
          plannedCents: 4500,
          store: 'Decathlon',
          purchaseUrl: 'https://example.com/compra',
        ),
      );
      expect(edited.ok, isTrue);
      final plan = edited.scope.livePlans.single;
      expect(plan.title, 'Bicicleta');
      expect(plan.status, GiftStatus.bought);
      expect(plan.plannedCents, 4500);
    });

    test('que el deseo falte en el común no es removedFromList', () {
      final a = claimAs(family.aritz, emptyScope(), wishBike, planId: 'p1');
      final partial = FamilyDoc.empty(kListId);
      final row = deriveWishPlanRows(
        common: partial,
        scope: a.scope,
        recipientId: 'nora',
      ).single;
      expect(row.state, WishPlanState.claimed);
      expect(row.wish, isNull);
    });

    test('un deseo de otra persona no cuenta para esta vista', () {
      final a = claimAs(family.aritz, emptyScope(), wishBike, planId: 'p1');
      expect(
        deriveWishPlanRows(common: common, scope: a.scope, recipientId: 'leo'),
        isEmpty,
      );
    });
  });

  group('editar', () {
    test('cambia solo campos privados y conserva la marca de los demás', () {
      final view = family.viewOf(family.aritz);
      final a = claimAs(family.aritz, emptyScope(), wishBike, planId: 'p1');
      final before = a.scope.record(ScopeCollections.wishPlans, 'p1')!;
      final r = a.scope.editPlan(
        clockOf('aritz-phone', 300),
        view,
        'p1',
        const PrivatePlanPatch(
          giverNote: 'Envolver en azul',
          actualCents: 4200,
        ),
      );
      expect(r.ok, isTrue);
      final after = r.scope.record(ScopeCollections.wishPlans, 'p1')!;
      expect(after['title'], 'Bicicleta');
      expect(after.field('title'), before.field('title'));
      expect(after['giverNote'], 'Envolver en azul');
      expect(after['actualCents'], 4200);
      // Sin cambios, el mismo documento.
      final same = r.scope.editPlan(
        clockOf('aritz-phone', 400),
        view,
        'p1',
        const PrivatePlanPatch(giverNote: 'Envolver en azul'),
      );
      expect(identical(same.scope, r.scope), isTrue);
      // Vaciar un campo.
      final cleared = r.scope.editPlan(
        clockOf('aritz-phone', 500),
        view,
        'p1',
        const PrivatePlanPatch(clear: {WishPlanField.giverNote}),
      );
      expect(cleared.scope.livePlans.single.giverNote, isNull);
    });

    test('valores que no valen y demasiado texto no escriben nada', () {
      final view = family.viewOf(family.aritz);
      final a = claimAs(family.aritz, emptyScope(), wishBike, planId: 'p1');
      WishPlanError? err(PrivatePlanPatch p) =>
          a.scope.editPlan(clockOf('aritz-phone', 300), view, 'p1', p).error;
      expect(
        err(const PrivatePlanPatch(plannedCents: -1)),
        WishPlanError.invalidField,
      );
      expect(
        err(const PrivatePlanPatch(purchaseUrl: 'javascript:alert(1)')),
        WishPlanError.invalidField,
      );
      expect(
        err(const PrivatePlanPatch(store: '   ')),
        WishPlanError.invalidField,
      );
      final huge = a.scope.editPlan(
        clockOf('aritz-phone', 300),
        view,
        'p1',
        PrivatePlanPatch(giverNote: 'n' * 3000),
      );
      expect(huge.error, WishPlanError.tooLarge);
      expect(identical(huge.scope, a.scope), isTrue);
      expect(
        a.scope
            .editPlan(
              clockOf('aritz-phone', 300),
              view,
              'nope',
              const PrivatePlanPatch(store: 'x'),
            )
            .error,
        WishPlanError.planNotFound,
      );
    });

    test('el móvil de P no edita planes', () {
      final a = claimAs(family.aritz, emptyScope(), wishBike, planId: 'p1');
      expect(
        a.scope
            .editPlan(
              clockOf('nora-phone', 300),
              family.viewOf(family.nora),
              'p1',
              const PrivatePlanPatch(store: 'x'),
            )
            .error,
        WishPlanError.notEntitled,
      );
    });
  });

  group('convertir en sorpresa', () {
    test('el plan pasa a ser un regalo independiente sin tocar el deseo', () {
      final view = family.viewOf(family.aritz);
      final a = claimAs(family.aritz, emptyScope(), wishBike, planId: 'p1');
      final edited = a.scope.editPlan(
        clockOf('aritz-phone', 200),
        view,
        'p1',
        const PrivatePlanPatch(
          plannedCents: 5000,
          store: 'Tienda',
          giverNote: 'Lazo',
          giverId: 'nosotros',
        ),
      );
      final commonBefore = common.canonicalJson();
      final r = edited.scope.convertPlanToSurprise(
        clockOf('aritz-phone', 300),
        view,
        'p1',
        common: common,
        year: 2026,
        occasionId: 'navidad',
        giftId: 'g1',
      );
      expect(r.ok, isTrue, reason: '${r.error}');
      expect(r.giftId, 'g1');
      expect(r.scope.livePlans, isEmpty);
      expect(r.scope.record(ScopeCollections.wishPlans, 'p1')!.isDeleted, true);
      final gift = Gift.fromRecord(r.scope.record(Collections.gifts, 'g1')!)!;
      expect(gift.surprise, isTrue);
      expect(gift.recipientId, 'nora');
      expect(gift.title, 'Bicicleta');
      expect(gift.giverId, 'nosotros');
      expect(gift.plannedCents, 5000);
      expect(gift.store, 'Tienda');
      expect(gift.note, 'Lazo');
      expect(gift.year, 2026);
      expect(gift.occasionId, 'navidad');
      expect(common.canonicalJson(), commonBefore);
      // El deseo de Nora sigue ahí, disponible otra vez.
      final row = deriveWishPlanRows(
        common: common,
        scope: r.scope,
        recipientId: 'nora',
      ).singleWhere((x) => x.sourceWishId == wishBike);
      expect(row.state, WishPlanState.available);
      // Reintento con el mismo id: no duplica.
      final retry = r.scope.convertPlanToSurprise(
        clockOf('aritz-phone', 400),
        view,
        'p1',
        common: common,
        year: 2026,
        giftId: 'g1',
      );
      expect(retry.ok, isTrue);
      expect(identical(retry.scope, r.scope), isTrue);
    });

    test('omite el regalador eliminado y conserva los datos privados', () {
      final view = family.viewOf(family.aritz);
      const giverId = 'nosotros';
      final withGiver = common.set(
        clockOf('aritz-phone', 90),
        Collections.givers,
        giverId,
        const Giver(
          id: giverId,
          name: 'Nosotros',
          colorIndex: 0,
          householdPays: true,
          archived: false,
        ).toFields(),
      );
      final claim = claimAs(
        family.aritz,
        emptyScope(),
        wishBike,
        planId: 'p1',
        from: withGiver,
      );
      final edited = claim.scope.editPlan(
        clockOf('aritz-phone', 200),
        view,
        'p1',
        const PrivatePlanPatch(
          giverId: giverId,
          status: GiftStatus.bought,
          plannedCents: 5000,
          actualCents: 4500,
          store: 'Tienda',
          purchaseUrl: 'https://example.com/compra',
          giverNote: 'Lazo',
        ),
      );
      expect(edited.ok, isTrue, reason: '${edited.error}');
      final afterDeletion = withGiver.delete(
        clockOf('aritz-web', 250),
        Collections.givers,
        giverId,
      );
      expect(
        edited.scope.record(ScopeCollections.wishPlans, 'p1')!['giverId'],
        giverId,
      );
      final converted = edited.scope.convertPlanToSurprise(
        clockOf('aritz-phone', 300),
        view,
        'p1',
        common: afterDeletion,
        year: 2026,
        giftId: 'g1',
      );
      expect(converted.ok, isTrue, reason: '${converted.error}');
      final record = converted.scope.record(Collections.gifts, 'g1')!;
      expect(record['giverId'], isNull);
      final gift = Gift.fromRecord(record)!;
      expect(gift.giverId, isNull);
      expect(gift.status, GiftStatus.bought);
      expect(gift.plannedCents, 5000);
      expect(gift.actualCents, 4500);
      expect(gift.store, 'Tienda');
      expect(gift.url, 'https://example.com/compra');
      expect(gift.note, 'Lazo');
      expect(gift.size, '8 años');
    });
  });

  group('capacidad compartida con los regalos', () {
    FamilyDoc withGifts(int n) {
      var doc = emptyScope();
      final c = clockOf('aritz-phone', 1);
      for (var i = 0; i < n; i++) {
        doc = doc.set(
          c,
          Collections.gifts,
          's$i',
          giftFields('nora', 'Regalo $i'),
        );
      }
      return doc;
    }

    test('con 200 registros vivos no se puede coger', () {
      final r = claimAs(family.aritz, withGifts(kMaxSurpriseGifts), wishBike);
      expect(r.error, WishPlanError.capacityReached);
    });

    test('un plan gasta una plaza de los 200', () {
      final scope = withGifts(kMaxSurpriseGifts - 1);
      final a = claimAs(family.aritz, scope, wishBike, planId: 'p1');
      expect(a.ok, isTrue);
      expect(liveOwnSurpriseGifts(a.scope), kMaxSurpriseGifts);
      expect(liveSurpriseGifts(a.scope), kMaxSurpriseGifts);
      expect(
        claimAs(family.aritz, a.scope, wishBook).error,
        WishPlanError.capacityReached,
      );
      // Convertir un plan no pide una plaza más.
      final c = a.scope.convertPlanToSurprise(
        clockOf('aritz-phone', 300),
        family.viewOf(family.aritz),
        'p1',
        common: common,
        year: 2026,
        giftId: 'gx',
      );
      expect(c.ok, isTrue, reason: '${c.error}');
      expect(liveSurpriseGifts(c.scope), kMaxSurpriseGifts);
    });

    test('un solo criterio: con 190 regalos y 10 movidos el bloque ya está '
        'lleno para coger y para convertir', () {
      var scope = emptyScope();
      final c = clockOf('aritz-phone', 1);
      for (var i = 0; i < 200; i++) {
        scope = scope.set(c, Collections.gifts, 's$i', {
          ...giftFields('nora', 'Regalo $i'),
          if (i >= 190) kMovedInField: true,
        });
      }
      expect(liveOwnSurpriseGifts(scope), 190);
      expect(liveSurpriseGifts(scope), 200);
      // La interfaz de regalos ya no admitiría editar con 201: coger tampoco.
      expect(
        claimAs(family.aritz, scope, wishBike).error,
        WishPlanError.capacityReached,
      );
      // Con uno menos, entra y deja el bloque en 200, editable.
      final nine = scope.delete(c, Collections.gifts, 's199');
      final ok = claimAs(family.aritz, nine, wishBike, planId: 'p1');
      expect(ok.ok, isTrue, reason: '${ok.error}');
      expect(liveSurpriseGifts(ok.scope), kMaxSurpriseGifts);
      // Convertir con el bloque por encima de 200 también se rechaza.
      final over = ok.scope.set(
        c,
        Collections.gifts,
        'extra',
        giftFields('nora', 'Extra'),
      );
      expect(
        over
            .convertPlanToSurprise(
              clockOf('aritz-phone', 300),
              family.viewOf(family.aritz),
              'p1',
              common: common,
              year: 2026,
            )
            .error,
        WishPlanError.capacityReached,
      );
    });

    test('con el límite real del slot (64 con un escritor sin slot) el plan '
        'que no se sellaría se rechaza', () {
      var scope = emptyScope();
      final c = clockOf('aritz-phone', 1);
      for (var i = 0; i < kLegacySlotGifts; i++) {
        scope = scope.set(
          c,
          Collections.gifts,
          's$i',
          giftFields('nora', 'Regalo $i'),
        );
      }
      const legacy = SlotLimits(maxLive: kLegacySlotGifts);
      final r = scope.claimWish(
        clockOf('aritz-phone', 100),
        family.viewOf(family.aritz),
        common,
        wishBike,
        limits: legacy,
      );
      expect(r.error, WishPlanError.slotFull);
      expect(identical(r.scope, scope), isTrue);
      final fewer = scope.delete(c, Collections.gifts, 's0');
      expect(
        fewer
            .claimWish(
              clockOf('aritz-phone', 100),
              family.viewOf(family.aritz),
              common,
              wishBike,
              limits: legacy,
            )
            .ok,
        isTrue,
      );
    });
  });
}
