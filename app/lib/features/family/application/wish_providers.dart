import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/model.dart';
import '../../../core/sync/wish.dart';
import '../../../core/sync/wish_plan.dart';
import '../../web_device/application/web_app_provider.dart';
import '../../web_device/data/web_family_store.dart';
import '../data/family_store.dart' show familyStoreProvider;
import 'family_controller.dart';
import '../domain/family_errors.dart' show DevicePersonOwner;
import 'family_providers.dart';
import 'wish_service.dart';

/// Los deseos visibles de [person] (ADR 0010) del año en vista, por título.
/// Los ve cualquier lector, también la propia persona; nunca llevan estado.
final visibleWishesForProvider = Provider.family<List<Wish>, String>(
  (ref, person) => [
    for (final wish in ref.watch(familyViewProvider).visibleWishes)
      if (wish.recipientId == person) wish,
  ],
);

/// Lo que [reader] puede hacer con un deseo.
///
/// Para la propia persona (`isOwner`) [state], [plans] y [canClaim] son
/// siempre null, vacío y falso: no hay nada que decirle de lo que hacen los
/// demás.
final class WishActions {
  /// Crea las acciones.
  const WishActions({
    required this.isOwner,
    required this.canEdit,
    required this.canRemove,
    required this.canClaim,
    required this.canEditOwnPlan,
    this.state,
    this.plans = const <WishPlan>[],
    this.ownPlan,
  });

  /// Si [reader] es la persona a quien pertenece el deseo.
  final bool isOwner;

  /// Edita el contenido visible: solo la persona dueña.
  final bool canEdit;

  /// Lo quita de su lista: solo la persona dueña.
  final bool canRemove;

  /// Lo puede coger: este móvil abre el bloque, el deseo sigue en la lista y
  /// nadie (ni [reader]) lo tiene cogido.
  final bool canClaim;

  /// Puede cambiar, soltar o borrar su propio plan.
  final bool canEditOwnPlan;

  /// Estado derivado de los planes, o null si [reader] no abre el bloque.
  final WishPlanState? state;

  /// Los planes vivos de este deseo (vacío si [reader] no abre el bloque).
  final List<WishPlan> plans;

  /// El plan de [reader], si lo hay.
  final WishPlan? ownPlan;
}

/// Qué puede hacer [reader] con [wish]. [row] es la fila derivada de los
/// planes de [WishPlanRow] (null si este móvil no abre el bloque, siempre en
/// el de la propia persona).
WishActions wishActionsFor({
  required String? reader,
  required Wish wish,
  WishPlanRow? row,
}) {
  final owner = reader != null && reader == wish.recipientId;
  if (owner || row == null) {
    return WishActions(
      isOwner: owner,
      canEdit: owner,
      canRemove: owner,
      canClaim: false,
      canEditOwnPlan: false,
    );
  }
  final own = [
    for (final plan in row.plans)
      if (plan.claimantPersonId == reader) plan,
  ];
  return WishActions(
    isOwner: false,
    canEdit: false,
    canRemove: false,
    canClaim: row.state == WishPlanState.available && row.wish != null,
    canEditOwnPlan: own.isNotEmpty,
    state: row.state,
    plans: row.plans,
    ownPlan: own.firstOrNull,
  );
}

/// La persona que mira desde este móvil (la de su ficha en el registro, o la
/// identidad local mientras el registro no está).
final wishReaderProvider = Provider<String?>((ref) {
  final registry = ref.watch(screenRegistryViewProvider).value;
  return registry?.myPerson ??
      ref.watch(familyControllerProvider).value?.identity?.selfRecipientId;
});

/// Si quien mira en este móvil puede cambiar quién regala el regalo [giftId]:
/// sí en un regalo normal; en el plan de un deseo cogido, solo quien lo cogió
/// (ADR 0010). Los demás lo ven sin selector (Reparto).
final giftGiverEditableProvider = Provider.family<bool, String>((ref, giftId) {
  final plan = ref.watch(wishPlanOfGiftProvider(giftId));
  if (plan == null) return true;
  final reader = ref.watch(wishReaderProvider);
  return reader != null && reader == plan.claimantPersonId;
});

/// Lo que este móvil puede hacer con el deseo [wishId] de [person]: sale de
/// [wishActionsFor] con el lector de este móvil y los planes de su
/// proyección. En el móvil de [person] no lleva ningún estado.
final wishActionsProvider =
    Provider.family<WishActions?, ({String person, String wishId})>((ref, key) {
      final view = ref.watch(familyFullViewProvider);
      final wish = view.allVisibleWishes
          .where((w) => w.id == key.wishId && w.recipientId == key.person)
          .firstOrNull;
      if (wish == null) return null;
      final row = ref
          .watch(wishPlanStateRowsProvider(key.person))
          .where((r) => r.sourceWishId == key.wishId)
          .firstOrNull;
      return wishActionsFor(
        reader: ref.watch(wishReaderProvider),
        wish: wish,
        row: row,
      );
    });

/// Los deseos de [person] con el estado que les dan los planes, en el móvil o
/// en la web (el motor de la web los lleva aparte de la proyección). En los
/// dispositivos de la propia persona, siempre vacío.
final wishPlanStateRowsProvider = Provider.family<List<WishPlanRow>, String>((
  ref,
  person,
) {
  // La web: lo que cambia el motor llega con un candidato nuevo.
  final store = ref.watch(familyStoreProvider);
  if (store is WebFamilyStore) {
    ref.watch(familyControllerProvider);
    return store.engine.wishPlanRows(person);
  }
  return ref.watch(wishPlanRowsProvider(person));
});

/// Un deseo con lo que este dispositivo puede hacer con él.
final class WishEntry {
  /// Crea la entrada.
  const WishEntry({required this.wish, required this.actions});

  /// El deseo.
  final Wish wish;

  /// Lo que puede hacer quien mira.
  final WishActions actions;
}

/// Los deseos de [person] del año en vista, con las acciones de quien mira.
/// En el dispositivo de la propia persona no llevan estado ni planes.
final wishEntriesProvider = Provider.family<List<WishEntry>, String>((
  ref,
  person,
) {
  final reader = ref.watch(wishReaderProvider);
  final rows = ref.watch(wishPlanStateRowsProvider(person));
  return [
    for (final wish in ref.watch(visibleWishesForProvider(person)))
      WishEntry(
        wish: wish,
        actions: wishActionsFor(
          reader: reader,
          wish: wish,
          row: rows.where((r) => r.sourceWishId == wish.id).firstOrNull,
        ),
      ),
  ];
});

/// Los deseos sin coger que ve este móvil, por persona y por ocasión, para
/// contarlos aparte de los regalos («2 regalos · 4 deseos»; QA 1.0.7, m1). Un
/// deseo cogido se cuenta como su plan (un regalo) y no aquí. Los deseos
/// propios se cuentan en el resumen de la persona si no se ocultan sus regalos.
final class FreeWishCounts {
  /// Crea las cuentas.
  const FreeWishCounts(this.byPerson, this.byOccasion);

  /// Por id de persona.
  final Map<String, int> byPerson;

  /// Por id de ocasión (los deseos sin ocasión no entran).
  final Map<String, int> byOccasion;

  /// Los deseos sin coger de [person].
  int ofPerson(String person) => byPerson[person] ?? 0;

  /// Los deseos sin coger de [occasion].
  int ofOccasion(String occasion) => byOccasion[occasion] ?? 0;
}

/// Las cuentas de deseos sin coger de [FreeWishCounts].
final freeWishCountsProvider = Provider<FreeWishCounts>((ref) {
  final byPerson = <String, int>{};
  final byOccasion = <String, int>{};
  final ownHidden = ref.watch(ownHiddenPeopleProvider);
  for (final person in ref.watch(familyFullViewProvider).recipientsById.keys) {
    for (final entry in ref.watch(wishEntriesProvider(person))) {
      if (entry.actions.plans.isNotEmpty) continue;
      if (!entry.actions.isOwner || !ownHidden.contains(person)) {
        byPerson[person] = (byPerson[person] ?? 0) + 1;
      }
      if (entry.actions.isOwner) continue;
      final occasion = entry.wish.occasionId;
      if (occasion != null) {
        byOccasion[occasion] = (byOccasion[occasion] ?? 0) + 1;
      }
    }
  }
  return FreeWishCounts(byPerson, byOccasion);
});

/// Los planes de [person] que se ven como un regalo: en el móvil ya están en
/// su lista de regalos; en la web (donde no hay proyección) se pintan desde
/// las filas del motor. Por id de plan, con su fila.
final wishPlanRowByPlanProvider =
    Provider.family<Map<String, WishPlanRow>, String>(
      (ref, person) => {
        for (final row in ref.watch(wishPlanStateRowsProvider(person)))
          for (final plan in row.plans) plan.planId: row,
      },
    );

/// Un plan visto como un regalo, para pintarlo en la lista de la web (en el
/// móvil la proyección ya lo trae): copia lo que coge del deseo y lo privado
/// del plan. Nunca se guarda como regalo.
Gift wishPlanAsGift(WishPlan plan, {Wish? wish, required int year}) => Gift(
  id: plan.planId,
  recipientId: plan.recipientId,
  title: plan.title,
  giverId: plan.giverId,
  occasionId: wish?.occasionId,
  status: plan.status,
  rawStatus: plan.status.name,
  plannedCents: plan.plannedCents,
  actualCents: plan.actualCents,
  store: plan.store,
  url: plan.purchaseUrl ?? plan.url,
  note: plan.giverNote,
  size: plan.size,
  surprise: false,
  year: wish?.year ?? year,
);

/// Solo la web: los planes vivos que ve su motor, por id de deseo. En el móvil
/// (que los lleva en su proyección, [projectedPlansByWishProvider]) siempre
/// vacío.
final webWishPlansProvider = Provider<Map<String, List<WishPlan>>>((ref) {
  if (ref.watch(familyStoreProvider) is! WebFamilyStore) {
    return const <String, List<WishPlan>>{};
  }
  final plans = <String, List<WishPlan>>{};
  for (final person
      in ref.watch(familyFullViewProvider).allRecipientsById.keys) {
    for (final row in ref.watch(wishPlanStateRowsProvider(person))) {
      if (row.plans.isEmpty) continue;
      plans[row.sourceWishId] = row.plans;
    }
  }
  return plans;
});

/// Solo la web: los planes de [person] vistos como regalos, para pintarlos en
/// la lista, la ocasión, el buscador y el presupuesto (en el móvil la
/// proyección ya los trae entre sus regalos).
final webPlanGiftsProvider = Provider.family<List<Gift>, String>((ref, person) {
  if (ref.watch(familyStoreProvider) is! WebFamilyStore) return const <Gift>[];
  final year = clock.now().year;
  return [
    for (final row in ref.watch(wishPlanStateRowsProvider(person)))
      for (final plan in row.plans)
        wishPlanAsGift(plan, wish: row.wish, year: year),
  ];
});

/// El plan que está detrás del regalo [giftId] (un plan visto como regalo en
/// el móvil), o null si es un regalo normal. Solo hay planes en un móvil que
/// abre el bloque de la persona.
final wishPlanOfGiftProvider = Provider.family<WishPlan?, String>((
  ref,
  giftId,
) {
  for (final plans in ref.watch(projectedPlansByWishProvider).values) {
    for (final plan in plans) {
      if (plan.planId == giftId) return plan;
    }
  }
  // La web no tiene proyección: sus planes están en las filas de su motor.
  for (final plans in ref.watch(webWishPlansProvider).values) {
    for (final plan in plans) {
      if (plan.planId == giftId) return plan;
    }
  }
  return null;
});

/// Si a [recipientId] se le puede sugerir un deseo visible («Visible para»):
/// tiene móvil en la familia y este dispositivo sabe sugerir (la web no).
final canSuggestWishProvider = Provider.family<bool, String>(
  (ref, recipientId) =>
      recipientId.isNotEmpty &&
      !ref.watch(webAppProvider) &&
      ref.watch(wishServiceProvider).canSuggest &&
      ref.watch(familyStateProvider)?.devicePersonOwner(recipientId) ==
          DevicePersonOwner.otherDevice,
);
