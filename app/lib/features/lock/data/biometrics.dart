import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/platform/platform_capabilities.dart';

/// Huella o rostro del móvil. Se abstrae para poder probar sin plugin.
abstract interface class BiometricAuthenticator {
  /// Si el móvil tiene huella o rostro dados de alta.
  Future<bool> isAvailable();

  /// Pide la huella o el rostro. `false` si se cancela o falla.
  Future<bool> authenticate(String reason);
}

/// [BiometricAuthenticator] sobre `local_auth`.
class LocalAuthBiometrics implements BiometricAuthenticator {
  /// Crea el autenticador.
  LocalAuthBiometrics([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    if (!platformCapabilities.biometrics) return false;
    try {
      return await _auth.canCheckBiometrics &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    if (!platformCapabilities.biometrics) return false;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
      );
    } on Object {
      return false;
    }
  }
}

/// La biometría del móvil. Las pruebas la sustituyen.
final biometricAuthenticatorProvider = Provider<BiometricAuthenticator>(
  (ref) => LocalAuthBiometrics(),
);
