import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/platform/platform_capabilities.dart';

/// Qué biometría tiene el dispositivo, para nombrarla en los textos.
///
/// Solo en iOS se distingue (Face ID o Touch ID); en Android y cuando no se
/// sabe es [generic] y los textos siguen diciendo «huella o rostro».
enum BiometricKind {
  /// No se sabe o no es iOS: texto genérico.
  generic,

  /// Face ID.
  face,

  /// Touch ID.
  fingerprint,
}

/// Huella o rostro del móvil. Se abstrae para poder probar sin plugin.
abstract interface class BiometricAuthenticator {
  /// Si el móvil tiene huella o rostro dados de alta.
  Future<bool> isAvailable();

  /// Qué biometría hay, para poner su nombre en los textos.
  Future<BiometricKind> kind();

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
  Future<BiometricKind> kind() async {
    if (!platformCapabilities.biometrics ||
        defaultTargetPlatform != TargetPlatform.iOS) {
      return BiometricKind.generic;
    }
    try {
      final types = await _auth.getAvailableBiometrics();
      if (types.contains(BiometricType.face)) return BiometricKind.face;
      if (types.contains(BiometricType.fingerprint)) {
        return BiometricKind.fingerprint;
      }
    } on Object {
      // Sin saberlo, texto genérico.
    }
    return BiometricKind.generic;
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

/// El tipo de biometría del móvil, consultado una vez por arranque (siempre
/// [BiometricKind.generic] fuera de iOS o mientras se consulta).
final biometricKindProvider = FutureProvider<BiometricKind>(
  (ref) => ref.read(biometricAuthenticatorProvider).kind(),
);

/// Vuelve a preguntar qué biometría hay (se pudo dar de alta Face ID o Touch ID
/// con la app abierta). Mientras responde se sigue viendo el valor anterior.
/// Se puede llamar al construir una pantalla: la consulta sale después y solo
/// si [alive] (normalmente `mounted`) sigue siendo cierto.
void refreshBiometricKind(WidgetRef ref, bool Function() alive) {
  Future.microtask(() {
    if (alive()) ref.invalidate(biometricKindProvider);
  });
}
