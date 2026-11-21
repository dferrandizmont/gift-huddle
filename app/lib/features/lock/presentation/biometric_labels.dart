import '../../../l10n/app_localizations.dart';
import '../data/biometrics.dart';

/// Textos de la biometría según lo que tenga el dispositivo.
///
/// En iOS nombran Face ID o Touch ID; en Android, o si no se sabe, siguen
/// siendo los genéricos de «huella o rostro».
extension BiometricLabels on BiometricKind {
  /// Nombre propio (no se traduce); `null` si es genérico.
  String? get brandName => switch (this) {
    BiometricKind.face => 'Face ID',
    BiometricKind.fingerprint => 'Touch ID',
    BiometricKind.generic => null,
  };

  /// Etiqueta del botón de desbloqueo.
  String button(AppLocalizations l10n) => brandName == null
      ? l10n.lockBiometric
      : l10n.lockBiometricNamed(brandName!);

  /// Pista bajo el teclado de bloqueo.
  String hint(AppLocalizations l10n) => brandName == null
      ? l10n.lockBiometricHint
      : l10n.lockBiometricHintNamed(brandName!);

  /// Aviso bajo el ajuste: sirve cualquier huella o cara dada de alta.
  String notice(AppLocalizations l10n) => switch (this) {
    BiometricKind.face => l10n.lockBiometricNoticeFace,
    BiometricKind.fingerprint => l10n.lockBiometricNoticeTouch,
    BiometricKind.generic => l10n.lockBiometricNotice,
  };

  /// Título de la oferta que sale al crear el PIN.
  String offerTitle(AppLocalizations l10n) => brandName == null
      ? l10n.pinBiometricOfferTitle
      : l10n.pinBiometricOfferTitleNamed(brandName!);

  /// Título del interruptor de Seguridad.
  String settingTitle(AppLocalizations l10n) =>
      brandName ?? l10n.securityBiometrics;

  /// Error al activar la biometría.
  String failed(AppLocalizations l10n) => brandName == null
      ? l10n.securityBiometricsFailed
      : l10n.securityBiometricsFailedNamed(brandName!);
}
