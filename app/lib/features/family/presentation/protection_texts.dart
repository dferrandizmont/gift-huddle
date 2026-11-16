import '../../../core/sync/protected_doc.dart' show ProtectedPersonReason;
import '../../../l10n/app_localizations.dart';
import '../application/family_providers.dart' show PersonProtectionStatus;

// Textos de la protección por persona (fase 3, lote 6): el motivo por el que
// no se pueden guardar o elegir los regalos de una persona protegida y el
// nombre de cada estado. Un solo sitio para que el selector, el editor y la
// hoja digan lo mismo.

/// El motivo, en una o dos frases llanas, para la persona llamada [name].
String protectionReasonText(
  AppLocalizations l10n,
  ProtectedPersonReason reason,
  String name,
) => switch (reason) {
  ProtectedPersonReason.protectedPerson =>
    l10n.protectionReason_protectedPerson(name),
  ProtectedPersonReason.noEntitlement => l10n.protectionReason_noEntitlement(
    name,
  ),
  ProtectedPersonReason.ownRequestsRestricted =>
    l10n.protectionReason_ownRequestsRestricted(name),
  ProtectedPersonReason.missingEpochKey =>
    l10n.protectionReason_missingEpochKey(name),
  ProtectedPersonReason.protectionPending =>
    l10n.protectionReason_protectionPending(name),
  ProtectedPersonReason.unreadableSlot => l10n.protectionReason_unreadableSlot(
    name,
  ),
  ProtectedPersonReason.blockFull => l10n.protectionReason_blockFull(name),
  ProtectedPersonReason.giftTooLarge => l10n.protectionReason_giftTooLarge(
    name,
  ),
  ProtectedPersonReason.writerSlotsFull =>
    l10n.protectionReason_writerSlotsFull(name),
  ProtectedPersonReason.slotsFull => l10n.protectionReason_slotsFull(name),
  ProtectedPersonReason.requiresV2 => l10n.protectionReason_requiresV2(name),
};

/// El nombre corto del estado de la protección.
String protectionStatusText(
  AppLocalizations l10n,
  PersonProtectionStatus status,
) => switch (status) {
  PersonProtectionStatus.unprotected => l10n.protectionStatusOff,
  PersonProtectionStatus.requested => l10n.protectionStatusRequested,
  PersonProtectionStatus.active => l10n.protectionStatusActive,
};
