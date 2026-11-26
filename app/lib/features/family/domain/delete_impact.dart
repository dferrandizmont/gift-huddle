import '../../../core/sync/model.dart';

/// What the device can show in the confirmation for a cascade.
///
/// Se calculan sobre la vista completa (también lo archivado y de todos los
/// años), porque eliminar no distingue años ni archivo.
class DeleteImpact {
  /// Crea el resultado.
  const DeleteImpact._({
    required this.affectedGifts,
    this.affectedAliases = const [],
    this.requestedGifts = const [],
    this.hasBirthday = false,
    this.hasLinkedGiver = false,
    this.linkedPersonExists = false,
    this.paysFromHousehold = false,
    this.affectedPlanIds = const [],
    this.affectedWishIds = const [],
  });

  /// Planes de deseos (ADR 0010) de los bloques secretos que este móvil
  /// puede abrir y que la eliminación borra (los de la persona) o deja sin
  /// quién regala (los del regalador). Se cuentan como los regalos.
  final List<String> affectedPlanIds;

  /// Cuántos planes de deseos afecta.
  int get plans => affectedPlanIds.length;

  /// Deseos visibles de la persona, de todos los años.
  final List<String> affectedWishIds;

  int get wishes => affectedWishIds.length;

  /// Este impacto con los planes [ids] (de los ámbitos que este móvil abre).
  DeleteImpact withPlans(List<String> ids) => DeleteImpact._(
    affectedGifts: affectedGifts,
    affectedAliases: affectedAliases,
    requestedGifts: requestedGifts,
    hasBirthday: hasBirthday,
    hasLinkedGiver: hasLinkedGiver,
    linkedPersonExists: linkedPersonExists,
    paysFromHousehold: paysFromHousehold,
    affectedPlanIds: List.unmodifiable(ids),
    affectedWishIds: affectedWishIds,
  );

  /// Si hay regalos de otras personas que había pedido esta persona: al
  /// eliminarla se borra quién los pidió.
  bool get hasRequests => requestedGifts.isNotEmpty;

  final List<Gift> requestedGifts;

  /// Whether the person's name will remain on gifts they gave.
  final bool hasLinkedGiver;

  /// Whether an affected giver is linked to a live person, including archived.
  final bool linkedPersonExists;

  /// Si quien regala paga la casa y tiene regalos: al quedarse sin quién
  /// regala, esos importes dejan de contar en el presupuesto.
  final bool paysFromHousehold;

  /// Regalos afectados: los que se eliminan (persona) o los que se quedan
  /// sin quién regala o sin ocasión (quien regala, ocasión).
  int get gifts => affectedGifts.length;

  final List<Gift> affectedGifts;
  final List<Giver> affectedAliases;

  /// Confirm against the same records regardless of their ordering.
  bool matches(DeleteImpact other) =>
      hasBirthday == other.hasBirthday &&
      hasLinkedGiver == other.hasLinkedGiver &&
      linkedPersonExists == other.linkedPersonExists &&
      paysFromHousehold == other.paysFromHousehold &&
      _sameIds(affectedPlanIds, other.affectedPlanIds) &&
      _sameIds(affectedWishIds, other.affectedWishIds) &&
      _sameIds(
        affectedAliases.map((g) => g.id),
        other.affectedAliases.map((g) => g.id),
      ) &&
      _sameIds(
        affectedGifts.map((g) => g.id),
        other.affectedGifts.map((g) => g.id),
      ) &&
      _sameIds(
        requestedGifts.map((g) => g.id),
        other.requestedGifts.map((g) => g.id),
      );

  /// Si la persona tiene una ocasión de cumpleaños que se elimina con ella.
  final bool hasBirthday;

  /// El impacto de eliminar a una persona.
  factory DeleteImpact.ofRecipient(FamilyView full, String id) =>
      DeleteImpact._(
        affectedGifts: List.unmodifiable(
          full.allGifts.where((gift) => gift.recipientId == id),
        ),
        affectedWishIds: List.unmodifiable([
          for (final wish in full.allVisibleWishes)
            if (wish.recipientId == id) wish.id,
        ]),
        hasLinkedGiver: full.giverForPerson(id) != null,
        hasBirthday: full.occasions.any(
          (o) => o.kind == OccasionKind.birthday && o.recipientId == id,
        ),
        requestedGifts: List.unmodifiable(
          full.allGifts.where((gift) {
            final by = gift.requestedBy;
            return gift.recipientId != id &&
                by is RequestedByRecipient &&
                by.recipientId == id;
          }),
        ),
      );

  /// The impact of deleting one original giver row.
  factory DeleteImpact.ofGiverAlias(FamilyView full, String id) =>
      DeleteImpact._givers(full, {id});

  /// The impact of deleting a grouped column and all of its original records.
  factory DeleteImpact.ofGiverColumn(FamilyView full, String id) =>
      DeleteImpact._givers(full, full.giverAliasIds(id));

  factory DeleteImpact._givers(FamilyView full, Set<String> ids) {
    final aliases = full.allGivers.where((giver) => ids.contains(giver.id));
    final liveIds = aliases.map((giver) => giver.id).toSet();
    final gifts = full.allGifts.where((gift) => liveIds.contains(gift.giverId));
    return DeleteImpact._(
      affectedAliases: List.unmodifiable(aliases),
      affectedGifts: List.unmodifiable(gifts),
      linkedPersonExists: aliases.any(
        (giver) => full.allRecipientsById.containsKey(giver.recipientId),
      ),
      paysFromHousehold: gifts.any((gift) {
        final giver = full.giversByOriginalId[gift.giverId]!;
        return giver.householdPays && !giver.archived;
      }),
    );
  }

  /// El impacto de eliminar una ocasión.
  factory DeleteImpact.ofOccasion(FamilyView full, String id) => DeleteImpact._(
    affectedGifts: List.unmodifiable(
      full.allGifts.where((gift) => gift.occasionId == id),
    ),
  );
}

bool _sameIds(Iterable<String> left, Iterable<String> right) =>
    left.length == right.length && left.toSet().containsAll(right);

/// The confirmation is stale. Show [current] before asking again.
class DeleteImpactChanged implements Exception {
  const DeleteImpactChanged(this.current);

  final DeleteImpact current;
}
