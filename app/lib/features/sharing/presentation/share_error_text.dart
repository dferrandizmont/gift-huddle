import '../../../core/sync/envelope.dart';
import '../../../core/sync/exchange_file.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/domain/family_errors.dart';
import '../../sync/application/recovery_providers.dart'
    show RecoveryApplicationException;

/// El texto para el usuario de un error al importar un envío o emparejar.
String shareErrorMessage(AppLocalizations l10n, Object error) =>
    switch (error) {
      // Los del fichero de intercambio (ADR 0005, B6), antes que sus bases.
      ExchangeLegacyFileException() => l10n.shareErrorLegacyFile,
      ExchangeNotReadyException() => l10n.shareErrorNotReady,
      ExchangeGenerationException() => l10n.shareErrorGeneration,
      ExchangeRevokedWriterException() => l10n.shareErrorRevokedWriter,
      ExchangeMissingKeyException(kept: false) => l10n.shareErrorSyncAndReopen,
      ExchangeMissingKeyException() => l10n.shareErrorMissingKey,
      ExchangeNotAllowedException() => l10n.shareErrorNotAllowed,
      EnvelopeWrongListException() => l10n.shareErrorWrongList,
      EnvelopeAuthException() => l10n.shareErrorAuth,
      EnvelopeTooLargeException() => l10n.shareErrorTooLarge,
      NoFamilyException() => l10n.shareErrorNoFamily,
      ImportClockDriftException() => l10n.shareErrorClockDrift,
      PairingFormatException() => l10n.pairErrorInvalidCode,
      RecoveryApplicationException(code: 'restore_pending') =>
        l10n.recoveryProblemPendingBody,
      _ => l10n.shareErrorNotEnvelope,
    };

/// El texto de un error al guardar una copia: los del fichero de
/// intercambio que tienen arreglo (B6), o el genérico.
String shareSendErrorMessage(AppLocalizations l10n, Object error) =>
    switch (error) {
      ExchangeNotAllowedException() => l10n.shareErrorNotAllowed,
      ExchangeNotReadyException() => l10n.shareErrorNotReady,
      EnvelopeTooLargeException() => l10n.shareErrorTooLarge,
      _ => l10n.shareSendError,
    };
