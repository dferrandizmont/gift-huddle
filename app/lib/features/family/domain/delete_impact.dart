import '../../../core/sync/model.dart';

/// Lo que arrastra eliminar una persona, quien regala o una ocasión: son los
/// números del diálogo de confirmación y deben coincidir con lo que hace
/// `FamilyController.deleteRecipient`, `deleteGiver` y `deleteOccasion`.
///
/// Se calculan sobre la vista completa (también lo archivado y de todos los
/// años), porque eliminar no distingue años ni archivo.
class DeleteImpact {
  /// Crea el resultado.
  const DeleteImpact({
    required this.gifts,
    this.hasBirthday = false,
    this.hasRequests = false,
    this.paysFromHousehold = false,
  });

  /// Si hay regalos de otras personas que había pedido esta persona: al
  /// eliminarla se borra quién los pidió.
  final bool hasRequests;

  /// Si quien regala paga la casa y tiene regalos: al quedarse sin quién
  /// regala, esos importes dejan de contar en el presupuesto.
  final bool paysFromHousehold;

  /// Regalos afectados: los que se eliminan (persona) o los que se quedan
  /// sin quién regala o sin ocasión (quien regala, ocasión).
  final int gifts;

  /// Si la persona tiene una ocasión de cumpleaños que se elimina con ella.
  final bool hasBirthday;

  /// El impacto de eliminar a una persona.
  factory DeleteImpact.ofRecipient(FamilyView full, String id) => DeleteImpact(
    gifts: full.allGifts.where((gift) => gift.recipientId == id).length,
    hasBirthday: full.occasions.any(
      (o) => o.kind == OccasionKind.birthday && o.recipientId == id,
    ),
    hasRequests: full.allGifts.any((gift) {
      final by = gift.requestedBy;
      return gift.recipientId != id &&
          by is RequestedByRecipient &&
          by.recipientId == id;
    }),
  );

  /// El impacto de eliminar a alguien que regala.
  factory DeleteImpact.ofGiver(FamilyView full, String id) {
    final gifts = full.allGifts.where((gift) => gift.giverId == id).length;
    final giver = full.allGivers.where((g) => g.id == id).firstOrNull;
    return DeleteImpact(
      gifts: gifts,
      paysFromHousehold: gifts > 0 && (giver?.householdPays ?? false),
    );
  }

  /// El impacto de eliminar una ocasión.
  factory DeleteImpact.ofOccasion(FamilyView full, String id) => DeleteImpact(
    gifts: full.allGifts.where((gift) => gift.occasionId == id).length,
  );
}
