import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/model.dart';
import '../../sync/application/sync_controller.dart'
    show localRegistryViewProvider;
import '../domain/next_occasion.dart';
import 'family_controller.dart';
import 'protection_providers.dart';
import 'wish_providers.dart' show webPlanGiftsProvider;

export 'protection_providers.dart';
export 'wish_providers.dart';

/// El estado ya cargado, o `null` mientras carga o si falló.
final familyStateProvider = Provider<FamilyState?>((ref) {
  final current = ref.watch(familyControllerProvider).value;
  if (current == null) return null;
  final registry = ref.watch(localRegistryViewProvider);
  return FamilyState(
    doc: ref.watch(projectedFamilyDocProvider),
    identity: current.identity,
    hiddenGiftIds: current.hiddenGiftIds,
    otherDevicePeople: registry.hasValue
        ? otherActiveDevicePeople(
            registry.value,
            excludingDevice: current.identity?.node,
          )
        : current.otherDevicePeople,
    authorized: true,
    plansByWish: ref.watch(projectedPlansByWishProvider),
    planGiftIds: ref.watch(projectedPlanGiftIdsProvider),
  );
});

/// The People choices for a visible gift, including whether a protected
/// assignment needs a separate public add. For draft gifts use
/// [FamilyView.giverPersonCandidatesFor] with the protection status of both
/// the original gift, if any, and the selected recipient.
final giftGiverPersonCandidatesProvider =
    Provider.family<List<GiverPersonCandidate>, String>((ref, giftId) {
      final view = ref.watch(familyFullViewProvider);
      final gift = view.allGifts.where((g) => g.id == giftId).firstOrNull;
      if (gift == null) return const [];
      final projection = ref.watch(authorizedProjectionProvider).value;
      return view.giverPersonCandidatesFor(
        gift.recipientId,
        protected:
            (projection?.secretGiftIds.contains(giftId) ?? false) ||
            projection?.policies[gift.recipientId]?.hideOwnGifts == true,
      );
    });

/// El año de la lista que se está viendo, o `null` para todos los años.
class YearFilter extends Notifier<int?> {
  @override
  int? build() => null;

  /// Cambia el año; `null` enseña todos.
  void set(int? year) => state = year;
}

/// Año que filtra los regalos de los providers derivados (presupuesto,
/// rejilla, duplicados, regalos por persona). Por defecto, todos.
final yearFilterProvider = NotifierProvider<YearFilter, int?>(YearFilter.new);

/// La vista de la familia con el año elegido: sin personas ni quien regala
/// archivados.
final familyViewProvider = Provider<FamilyView>((ref) {
  final state = ref.watch(familyStateProvider) ?? FamilyState.noFamily();
  final year = ref.watch(yearFilterProvider);
  return year == null
      ? state.view
      : FamilyView.fromDoc(
          state.doc,
          year: year,
          hiddenGiftIds: state.hiddenGiftIds,
          plansByWish: state.plansByWish,
          planGiftIds: state.view.planGiftIds,
        );
});

/// La vista con todo, también lo archivado y de todos los años: para la
/// pantalla de archivados.
final familyFullViewProvider = Provider<FamilyView>(
  (ref) => (ref.watch(familyStateProvider) ?? FamilyState.noFamily()).fullView,
);

/// Las personas a las que se regala (sin archivadas), por nombre.
final recipientsProvider = Provider<List<Recipient>>(
  (ref) => ref.watch(familyViewProvider).recipients,
);

/// Quien regala (sin archivados), por nombre.
final giversProvider = Provider<List<Giver>>(
  (ref) => ref.watch(familyViewProvider).givers,
);

/// People choices for an existing gift in the authorized view. The recipient
/// is resolved again whenever sync moves the gift.
final giftGiverPeopleProvider = Provider.family<List<Recipient>, String>((
  ref,
  giftId,
) {
  final view = ref.watch(familyFullViewProvider);
  final gift = view.allGifts.where((g) => g.id == giftId).firstOrNull;
  return gift == null ? const [] : view.giverPeopleFor(gift.recipientId);
});

/// Las ocasiones (sin archivadas), por nombre.
final occasionsProvider = Provider<List<Occasion>>(
  (ref) => [
    for (final o in ref.watch(familyViewProvider).occasions)
      if (!o.archived) o,
  ],
);

/// Los regalos de una persona, por título, con los planes visibles en la web.
final giftsForProvider = Provider.family<List<Gift>, String>((ref, recipientId) {
  final gifts = ref.watch(familyViewProvider).giftsFor(recipientId);
  final plans = ref.watch(webPlanGiftsProvider(recipientId));
  if (plans.isEmpty) return gifts;
  final year = ref.watch(yearFilterProvider);
  final giftIds = {for (final gift in gifts) gift.id};
  return [
    ...gifts,
    for (final plan in plans)
      if ((year == null || plan.year == year) && !giftIds.contains(plan.id))
        plan,
  ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
});

/// La rejilla de la familia (personas y quien regala activos, con la fila de
/// «sin asignar» del modelo).
final familyGridProvider = Provider<FamilyGrid>(
  (ref) => ref.watch(familyViewProvider).grid(),
);

/// Personas activas fuera de Reparto; siguen estando en Personas.
final outsideRepartoProvider = Provider<List<Recipient>>(
  (ref) => ref.watch(familyViewProvider).outsideReparto,
);

/// Resuelve las claves del selector sin depender de la capa de presentación.
/// Las familias de Riverpod usan String (igualdad por valor), nunca un Set.
Set<String>? _repartoOccasionIds(String? key, List<Occasion> occasions) {
  if (key == null || key == 'all') return null;
  if (key == 'birthdays') {
    return {
      for (final occasion in occasions)
        if (!occasion.archived && occasion.kind == OccasionKind.birthday)
          occasion.id,
    };
  }
  return {key};
}

/// Regalos y personas que cuentan en Reparto, para sus listas y totales.
/// `null` y `all` significan Todas; `birthdays` reúne los cumpleaños activos;
/// cualquier otra clave es el id estable de una ocasión.
final repartoFamilyViewProvider = Provider.family<FamilyView, String?>((
  ref,
  occasionKey,
) {
  final view = ref.watch(familyViewProvider);
  return view.forReparto(
    occasionKeys: _repartoOccasionIds(occasionKey, view.occasions),
  );
});

/// Rejilla filtrada, con celdas `excluded` y la lista `outsideReparto`.
/// Acepta las mismas claves del selector que [repartoFamilyViewProvider].
final familyGridForOccasionProvider = Provider.family<FamilyGrid, String?>((
  ref,
  occasionKey,
) {
  final view = ref.watch(familyViewProvider);
  return view.grid(
    occasionKeys: _repartoOccasionIds(occasionKey, view.occasions),
  );
});

/// El presupuesto de los regalos de las personas activas.
final budgetProvider = Provider<Budget>((ref) {
  final view = ref.watch(familyViewProvider);
  final active = {for (final recipient in view.giftRecipients) recipient.id};
  final year = ref.watch(yearFilterProvider);
  final hiddenPeople = ref.watch(ownHiddenPeopleProvider);
  return FamilyView(
    recipients: view.recipients,
    givers: view.givers,
    occasions: view.occasions,
    gifts: [
      for (final gift in view.gifts)
        if (active.contains(gift.recipientId)) gift,
    ],
    allGifts: view.allGifts,
    allGivers: view.allGivers,
    planGiftIds: view.planGiftIds,
  ).budget(
    wishPlanGifts: [
      for (final recipientId in active)
        if (!hiddenPeople.contains(recipientId))
          for (final plan in ref.watch(webPlanGiftsProvider(recipientId)))
            if (year == null || plan.year == year) plan,
    ],
  );
});

/// Pares de regalos casi iguales para la misma persona (personas activas).
final duplicatesProvider = Provider<List<DuplicatePair>>(
  (ref) => ref.watch(familyViewProvider).possibleDuplicates(),
);

/// La próxima ocasión y los días que faltan. Usa `clock.now()` al calcular;
/// se recalcula cuando cambia la familia, no al pasar la medianoche.
final nextOccasionProvider = Provider<NextOccasion?>(
  (ref) => nextOccasionFrom(ref.watch(occasionsProvider), clock.now()),
);

/// Las próximas ocasiones para la cuenta atrás de Personas, de la más cercana
/// a la más lejana, sin archivadas ni las que ya pasaron y no se repiten.
final upcomingOccasionsProvider = Provider<List<NextOccasion>>(
  (ref) => upcomingOccasionsFrom(ref.watch(occasionsProvider), clock.now()),
);
