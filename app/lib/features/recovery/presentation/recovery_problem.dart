import '../../../l10n/app_localizations.dart';
import '../../sync/application/recovery_providers.dart';

/// Lo que le pasa a una recuperación, en el lenguaje de la persona: cada
/// código técnico de `RecoveryApplicationException` o de la causa del estado
/// cae en uno de estos grupos y cada grupo tiene su texto.
enum RecoveryProblem {
  /// Sin red o el servidor no responde: se puede reintentar.
  offline,

  /// El código no abre ninguna copia.
  wrongCode,

  /// El código se cambió o se quitó.
  retired,

  /// Este móvil ya no está en la familia.
  removed,

  /// Falta una parte de la lista: lo descargado se conserva.
  incomplete,

  /// Hay otra operación en marcha.
  busy,

  /// La copia es de una versión que esta app no abre, o está dañada.
  unsupported,

  /// Este móvil no tiene servidor al que hablar.
  unavailable,

  /// El código es de otra familia y sustituiría la de este móvil: pide
  /// confirmación.
  otherFamily,

  /// La copia cifrada no ha quedado preparada en el servidor.
  notReady,

  /// Hay una recuperación a medias en este móvil: se reanuda o se cancela
  /// antes de crear o unirse a una familia.
  restorePending,

  /// La persona de «Yo» cambió (o hay una invalidación pendiente) y el código
  /// ya no es el de la persona actual: hay que crear uno nuevo.
  personChanged,

  /// Cualquier otra cosa.
  other,
}

/// El grupo de un código de error o de una causa de estado.
RecoveryProblem recoveryProblemOf(String? code) => switch (code) {
  'network' || 'server' || 'rateLimited' => RecoveryProblem.offline,
  'not_found' ||
  'invalid_code_or_capsule' ||
  'invalid_capsule' => RecoveryProblem.wrongCode,
  'recovery_retired' || 'recovery_not_active' => RecoveryProblem.retired,
  'revoked' || 'unauthorized' => RecoveryProblem.removed,
  'operation_pending' ||
  'recovery_in_progress' ||
  'setup_pending' ||
  'already_configured' => RecoveryProblem.busy,
  'unsupported_or_invalid_data' ||
  'local_or_unsupported_state' ||
  'unsupported_local_context' ||
  'protocol' ||
  'tooLarge' ||
  'recovery_too_large' => RecoveryProblem.unsupported,
  'not_configured' => RecoveryProblem.unavailable,
  'different_family' || 'existing_v1_family' => RecoveryProblem.otherFamily,
  'publication_pending' => RecoveryProblem.notReady,
  'restore_pending' => RecoveryProblem.restorePending,
  'missing_common_keyring' ||
  'incomplete_remote' ||
  'incomplete_installation' ||
  'transition_pending' ||
  'local_resources_pending' ||
  'renewal_pending' ||
  'person_changed' ||
  'generation_gone' ||
  'snapshot_rollback' ||
  'capsule_rollback' ||
  'identity_changed' ||
  'local_identity_conflict' ||
  'capsule_revision_mismatch' ||
  'capsule_verification_failed' => RecoveryProblem.incomplete,
  _ => RecoveryProblem.other,
};

/// El grupo de una excepción de la capa de aplicación.
RecoveryProblem recoveryProblemOfException(RecoveryApplicationException e) {
  // Como excepción de comprobar o guardar un código; como causa de estado de
  // una restauración, `person_changed` sigue siendo «incompleta».
  if (e.code == 'person_changed') {
    return RecoveryProblem.personChanged;
  }
  final byCode = recoveryProblemOf(e.code);
  if (byCode != RecoveryProblem.other) {
    return byCode;
  }
  return e.retryable ? RecoveryProblem.offline : RecoveryProblem.other;
}

/// Los problemas en los que escribir otro código tiene sentido.
bool recoveryProblemAllowsOtherCode(RecoveryProblem problem) =>
    problem == RecoveryProblem.wrongCode ||
    problem == RecoveryProblem.retired ||
    problem == RecoveryProblem.removed ||
    problem == RecoveryProblem.unsupported;

/// Los problemas que se arreglan reintentando.
bool recoveryProblemAllowsRetry(RecoveryProblem problem) =>
    problem == RecoveryProblem.offline ||
    problem == RecoveryProblem.incomplete ||
    problem == RecoveryProblem.busy ||
    problem == RecoveryProblem.notReady ||
    problem == RecoveryProblem.other;

/// Los que piden confirmar antes de sustituir la familia de este móvil.
bool recoveryProblemNeedsReplace(RecoveryProblem problem) =>
    problem == RecoveryProblem.otherFamily;

/// El título de [problem].
String recoveryProblemTitle(AppLocalizations l10n, RecoveryProblem problem) =>
    switch (problem) {
      RecoveryProblem.offline => l10n.recoveryProblemOfflineTitle,
      RecoveryProblem.wrongCode => l10n.recoveryProblemWrongTitle,
      RecoveryProblem.retired => l10n.recoveryProblemRetiredTitle,
      RecoveryProblem.removed => l10n.recoveryProblemRemovedTitle,
      RecoveryProblem.incomplete => l10n.recoveryProblemIncompleteTitle,
      RecoveryProblem.busy => l10n.recoveryProblemBusyTitle,
      RecoveryProblem.unsupported => l10n.recoveryProblemUnsupportedTitle,
      RecoveryProblem.unavailable => l10n.recoveryProblemUnavailableTitle,
      RecoveryProblem.otherFamily => l10n.recoveryProblemFamilyTitle,
      RecoveryProblem.notReady => l10n.recoveryProblemNotReadyTitle,
      RecoveryProblem.restorePending => l10n.recoveryProblemPendingTitle,
      RecoveryProblem.personChanged => l10n.recoveryProblemPersonTitle,
      RecoveryProblem.other => l10n.recoveryProblemOtherTitle,
    };

/// La explicación de [problem].
String recoveryProblemBody(AppLocalizations l10n, RecoveryProblem problem) =>
    switch (problem) {
      RecoveryProblem.offline => l10n.recoveryProblemOfflineBody,
      RecoveryProblem.wrongCode => l10n.recoveryProblemWrongBody,
      RecoveryProblem.retired => l10n.recoveryProblemRetiredBody,
      RecoveryProblem.removed => l10n.recoveryProblemRemovedBody,
      RecoveryProblem.incomplete => l10n.recoveryProblemIncompleteBody,
      RecoveryProblem.busy => l10n.recoveryProblemBusyBody,
      RecoveryProblem.unsupported => l10n.recoveryProblemUnsupportedBody,
      RecoveryProblem.unavailable => l10n.recoveryProblemUnavailableBody,
      RecoveryProblem.otherFamily => l10n.recoveryProblemFamilyBody,
      RecoveryProblem.notReady => l10n.recoveryProblemNotReadyBody,
      RecoveryProblem.restorePending => l10n.recoveryProblemPendingBody,
      RecoveryProblem.personChanged => l10n.recoveryProblemPersonBody,
      RecoveryProblem.other => l10n.recoveryProblemOtherBody,
    };
