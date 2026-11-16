import '../../../l10n/app_localizations.dart';
import '../../sync/application/recovery_file_flow.dart';
import '../../sync/application/recovery_providers.dart';
import 'recovery_problem.dart';

/// Lo que le pasa a una operación con un fichero de recuperación (ADR 0008),
/// en el lenguaje de la persona. Los errores tipados de la capa de aplicación
/// (`RecoveryFileException`, `RecoveryFileFlowException`,
/// `DocumentPickerException`, `RecoveryApplicationException`) caen en uno de
/// estos grupos.
enum RecoveryFileProblemKind {
  /// La relectura del destino no dio lo mismo: no se comprueba nada.
  verification,

  /// No se pudo leer o escribir el documento.
  unreadable,

  /// Este móvil no tiene selector de ficheros.
  unavailable,

  /// Ya hay un selector abierto.
  pickerBusy,

  /// No es un fichero de recuperación (o pasa del tope).
  notRecoveryFile,

  /// Es de una versión más nueva de la app.
  newerVersion,

  /// Contraseña incorrecta o fichero dañado.
  wrongPassword,

  /// El fichero abre otro código, no el vigente.
  notCurrentCode,

  /// Este móvil ya tiene una lista.
  hasFamily,

  /// Hay otra operación de fichero en marcha.
  busy,

  /// Un error de la recuperación de siempre ([RecoveryFileProblem.inner]).
  recovery,
}

/// Un problema ya clasificado, listo para traducir.
class RecoveryFileProblem {
  /// Crea el problema.
  const RecoveryFileProblem(this.kind, [this.inner]);

  /// El grupo.
  final RecoveryFileProblemKind kind;

  /// Solo con [RecoveryFileProblemKind.recovery].
  final RecoveryProblem? inner;

  /// Si se arregla escribiendo otra contraseña.
  bool get isWrongPassword => kind == RecoveryFileProblemKind.wrongPassword;
}

/// Clasifica [error]. Null si no es un fallo que enseñar: una cancelación del
/// flujo (la persona ya lo sabe).
RecoveryFileProblem? recoveryFileProblemOf(Object error) {
  switch (error) {
    case RecoveryFileException(:final failure):
      return RecoveryFileProblem(switch (failure) {
        RecoveryFileFailure.notRecoveryFile =>
          RecoveryFileProblemKind.notRecoveryFile,
        RecoveryFileFailure.newerVersion =>
          RecoveryFileProblemKind.newerVersion,
        RecoveryFileFailure.damagedOrWrongPassword =>
          RecoveryFileProblemKind.wrongPassword,
      });
    case RecoveryFileFlowException(:final error):
      switch (error) {
        case RecoveryFileFlowError.cancelled:
          return null;
        case RecoveryFileFlowError.busy:
          return const RecoveryFileProblem(RecoveryFileProblemKind.busy);
        case RecoveryFileFlowError.hasFamily:
          return const RecoveryFileProblem(RecoveryFileProblemKind.hasFamily);
        case RecoveryFileFlowError.verificationFailed:
          return const RecoveryFileProblem(
            RecoveryFileProblemKind.verification,
          );
        case RecoveryFileFlowError.passwordRequired:
        case RecoveryFileFlowError.noFile:
          return const RecoveryFileProblem(
            RecoveryFileProblemKind.recovery,
            RecoveryProblem.other,
          );
      }
    case DocumentPickerException(:final failure):
      return RecoveryFileProblem(switch (failure) {
        DocumentPickerFailure.tooLarge =>
          RecoveryFileProblemKind.notRecoveryFile,
        DocumentPickerFailure.unreadable => RecoveryFileProblemKind.unreadable,
        DocumentPickerFailure.busy => RecoveryFileProblemKind.pickerBusy,
        DocumentPickerFailure.unavailable =>
          RecoveryFileProblemKind.unavailable,
      });
    case RecoveryApplicationException(:final code):
      if (code == 'not_current_code') {
        return const RecoveryFileProblem(
          RecoveryFileProblemKind.notCurrentCode,
        );
      }
      return RecoveryFileProblem(
        RecoveryFileProblemKind.recovery,
        recoveryProblemOfException(error),
      );
    default:
      return const RecoveryFileProblem(
        RecoveryFileProblemKind.recovery,
        RecoveryProblem.other,
      );
  }
}

/// El título de [problem].
String recoveryFileProblemTitle(
  AppLocalizations l10n,
  RecoveryFileProblem problem,
) => switch (problem.kind) {
  RecoveryFileProblemKind.verification => l10n.recoveryFileProblemVerifyTitle,
  RecoveryFileProblemKind.unreadable => l10n.recoveryFileProblemUnreadableTitle,
  RecoveryFileProblemKind.unavailable =>
    l10n.recoveryFileProblemUnavailableTitle,
  RecoveryFileProblemKind.pickerBusy => l10n.recoveryFileProblemPickerBusyTitle,
  RecoveryFileProblemKind.notRecoveryFile =>
    l10n.recoveryFileProblemNotFileTitle,
  RecoveryFileProblemKind.newerVersion => l10n.recoveryFileProblemNewerTitle,
  RecoveryFileProblemKind.wrongPassword =>
    l10n.recoveryFileProblemPasswordTitle,
  RecoveryFileProblemKind.notCurrentCode =>
    l10n.recoveryFileProblemNotCurrentTitle,
  RecoveryFileProblemKind.hasFamily => l10n.recoveryFileProblemHasFamilyTitle,
  RecoveryFileProblemKind.busy => l10n.recoveryProblemBusyTitle,
  RecoveryFileProblemKind.recovery => recoveryProblemTitle(
    l10n,
    problem.inner ?? RecoveryProblem.other,
  ),
};

/// La explicación de [problem].
String recoveryFileProblemBody(
  AppLocalizations l10n,
  RecoveryFileProblem problem,
) => switch (problem.kind) {
  RecoveryFileProblemKind.verification => l10n.recoveryFileProblemVerifyBody,
  RecoveryFileProblemKind.unreadable => l10n.recoveryFileProblemUnreadableBody,
  RecoveryFileProblemKind.unavailable =>
    l10n.recoveryFileProblemUnavailableBody,
  RecoveryFileProblemKind.pickerBusy => l10n.recoveryFileProblemPickerBusyBody,
  RecoveryFileProblemKind.notRecoveryFile =>
    l10n.recoveryFileProblemNotFileBody,
  RecoveryFileProblemKind.newerVersion => l10n.recoveryFileProblemNewerBody,
  RecoveryFileProblemKind.wrongPassword => l10n.recoveryFileProblemPasswordBody,
  RecoveryFileProblemKind.notCurrentCode =>
    l10n.recoveryFileProblemNotCurrentBody,
  RecoveryFileProblemKind.hasFamily => l10n.recoveryFileProblemHasFamilyBody,
  RecoveryFileProblemKind.busy => l10n.recoveryProblemBusyBody,
  RecoveryFileProblemKind.recovery => recoveryProblemBody(
    l10n,
    problem.inner ?? RecoveryProblem.other,
  ),
};

/// El motivo de una contraseña nueva que no vale, en el idioma de la app.
String recoveryPasswordProblemText(
  AppLocalizations l10n,
  RecoveryPasswordProblem problem,
) => switch (problem) {
  RecoveryPasswordProblem.tooShort => l10n.recoveryFilePwTooShort(
    kRecoveryPasswordMinRunes,
  ),
  RecoveryPasswordProblem.tooLong => l10n.recoveryFilePwTooLong(
    kRecoveryPasswordMaxRunes,
  ),
  RecoveryPasswordProblem.repeated => l10n.recoveryFilePwRepeated,
  RecoveryPasswordProblem.onlyDigits => l10n.recoveryFilePwDigits,
  RecoveryPasswordProblem.keyboardSequence => l10n.recoveryFilePwKeyboard,
  RecoveryPasswordProblem.containsAppName => l10n.recoveryFilePwAppName,
  RecoveryPasswordProblem.common => l10n.recoveryFilePwCommon,
  RecoveryPasswordProblem.mismatch => l10n.recoveryFilePwMismatch,
};
