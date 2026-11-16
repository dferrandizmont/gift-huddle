// Claves propias de cada móvil. Dart puro (sin Flutter).
// Decisión: docs/adr/0004-yo-sorpresas-revocar.md (fase 1).
//
// Cada móvil genera, y nunca comparte en claro:
// - un par X25519 persistente para recibir paquetes de claves (ECDH);
// - un par Ed25519 para firmar lo que publica (slots de sorpresas, paquetes);
// - una credencial de servicio aleatoria de 32 bytes, independiente de la
//   `familyKey`, que el Worker usará en la fase 2 (guardará su SHA-256).
//
// Formato guardado (JSON, en el almacén seguro del sistema):
//   {"v":1,"x":<semilla X25519>,"e":<semilla Ed25519>,"c":<credencial>}
// todo en base64url sin relleno. Las claves públicas se recalculan al leer.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:meta/meta.dart';

import 'envelope.dart' show decodeBase64Url, encodeBase64Url;

/// Versión del formato guardado de [DeviceKeys].
const int kDeviceKeysVersion = 1;

const _seedLength = 32;
const _publicLength = 32;
const _signatureLength = 64;
const _credentialLength = 32;

/// Patrón de los identificadores (lista, móvil, persona) que viajan en las
/// cabeceras: los mismos caracteres que el `listId` de los sobres v1.
final RegExp kSyncIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

/// Una clave o una firma que no vale (formato roto, clave de orden bajo,
/// firma que no corresponde).
class DeviceKeyException implements Exception {
  /// Crea el error.
  const DeviceKeyException(this.message);

  /// Qué pasó (sin claves).
  final String message;

  @override
  String toString() => 'DeviceKeyException: $message';
}

/// `n` bytes aleatorios de un generador criptográfico.
Uint8List secureRandomBytes(int n) {
  final rnd = Random.secure();
  return Uint8List.fromList(List<int>.generate(n, (_) => rnd.nextInt(256)));
}

/// Compara dos listas de bytes en tiempo constante respecto al contenido.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

// Lo que este móvil sabe de los demás (`KnownDevice`) sale solo del registro
// firmado de móviles: device_registry.dart.

/// Las claves públicas de un móvil: lo que conocen los demás.
class DevicePublicKeys {
  /// Crea el par de claves públicas. Lanza [DeviceKeyException] si alguna no
  /// tiene 32 bytes.
  DevicePublicKeys({required List<int> agreement, required List<int> signing})
    : agreement = Uint8List.fromList(agreement),
      signing = Uint8List.fromList(signing) {
    if (this.agreement.length != _publicLength ||
        this.signing.length != _publicLength) {
      throw const DeviceKeyException('clave pública no válida');
    }
  }

  /// Lee las claves de [toJson]. Lanza [DeviceKeyException] si no valen.
  factory DevicePublicKeys.fromJson(Map<String, Object?> json) {
    final x = json['x'];
    final e = json['e'];
    if (x is! String || e is! String) {
      throw const DeviceKeyException('claves públicas no válidas');
    }
    try {
      return DevicePublicKeys(
        agreement: decodeBase64Url(x),
        signing: decodeBase64Url(e),
      );
    } on FormatException {
      throw const DeviceKeyException('claves públicas no válidas');
    }
  }

  /// Clave pública X25519 (para cifrarle paquetes de claves).
  final Uint8List agreement;

  /// Clave pública Ed25519 (para comprobar sus firmas).
  final Uint8List signing;

  /// `{"x":..., "e":...}` en base64url.
  Map<String, Object?> toJson() => <String, Object?>{
    'x': encodeBase64Url(agreement),
    'e': encodeBase64Url(signing),
  };
}

/// Las claves secretas de este móvil. Nunca aparecen en `toString()`.
class DeviceKeys {
  DeviceKeys._({
    required this._agreementPair,
    required this._agreementSeed,
    required this._signingSeed,
    required this._signingPair,
    required this._serviceCredential,
    required this.publicKeys,
  });

  static final X25519 _x25519 = X25519();
  static final Ed25519 _ed25519 = Ed25519();

  final SimpleKeyPairData _agreementPair;
  final Uint8List _agreementSeed;
  final Uint8List _signingSeed;
  final SimpleKeyPairData _signingPair;
  final Uint8List _serviceCredential;

  /// Las claves públicas de este móvil.
  final DevicePublicKeys publicKeys;

  /// Genera claves nuevas y aleatorias.
  static Future<DeviceKeys> generate() => _build(
    secureRandomBytes(_seedLength),
    secureRandomBytes(_seedLength),
    secureRandomBytes(_credentialLength),
  );

  /// Claves deterministas a partir de semillas: solo para pruebas y
  /// vectores fijos.
  @visibleForTesting
  static Future<DeviceKeys> fromSeedsForTesting({
    required List<int> agreementSeed,
    required List<int> signingSeed,
    required List<int> serviceCredential,
  }) => _build(agreementSeed, signingSeed, serviceCredential);

  /// Lee las claves guardadas con [toJson]. Lanza [DeviceKeyException] si
  /// no valen.
  static Future<DeviceKeys> fromJson(Map<String, Object?> json) async {
    if (json['v'] != kDeviceKeysVersion) {
      throw const DeviceKeyException('versión de claves no soportada');
    }
    final x = json['x'];
    final e = json['e'];
    final c = json['c'];
    if (x is! String || e is! String || c is! String) {
      throw const DeviceKeyException('claves dañadas');
    }
    try {
      return await _build(
        decodeBase64Url(x),
        decodeBase64Url(e),
        decodeBase64Url(c),
      );
    } on FormatException {
      throw const DeviceKeyException('claves dañadas');
    }
  }

  static Future<DeviceKeys> _build(
    List<int> agreementSeed,
    List<int> signingSeed,
    List<int> credential,
  ) async {
    if (agreementSeed.length != _seedLength ||
        signingSeed.length != _seedLength ||
        credential.length != _credentialLength) {
      throw const DeviceKeyException('claves de longitud no válida');
    }
    final agreement = await (await _x25519.newKeyPairFromSeed(agreementSeed))
        .extract();
    final signing = await (await _ed25519.newKeyPairFromSeed(signingSeed))
        .extract();
    return DeviceKeys._(
      agreementPair: agreement,
      agreementSeed: Uint8List.fromList(agreementSeed),
      signingSeed: Uint8List.fromList(signingSeed),
      signingPair: signing,
      serviceCredential: Uint8List.fromList(credential),
      publicKeys: DevicePublicKeys(
        agreement: agreement.publicKey.bytes,
        signing: signing.publicKey.bytes,
      ),
    );
  }

  /// Las claves para guardarlas en el almacén seguro (contiene secretos).
  Map<String, Object?> toJson() => <String, Object?>{
    'v': kDeviceKeysVersion,
    'x': encodeBase64Url(_agreementSeed),
    'e': encodeBase64Url(_signingSeed),
    'c': encodeBase64Url(_serviceCredential),
  };

  /// Copia de la credencial de servicio (32 bytes). Solo se genera y se
  /// guarda: el Worker la usará en la fase 2.
  Uint8List get serviceCredential => Uint8List.fromList(_serviceCredential);

  /// Las mismas claves con otra credencial de servicio aleatoria (B7, M3):
  /// la credencial es independiente de las claves de la ficha, así que una
  /// que quedó registrada en una lista sin llegar a instalarla se abandona
  /// sin cambiar de identidad.
  Future<DeviceKeys> withNewServiceCredential() => _build(
    _agreementSeed,
    _signingSeed,
    secureRandomBytes(_credentialLength),
  );

  /// `SHA-256(credencial)`: lo que guardará el servidor en la fase 2.
  Future<Uint8List> serviceCredentialVerifier() async =>
      Uint8List.fromList((await Sha256().hash(_serviceCredential)).bytes);

  /// Firma [message] con la clave Ed25519 de este móvil (64 bytes).
  Future<Uint8List> sign(List<int> message) async {
    final signature = await _ed25519.sign(message, keyPair: _signingPair);
    return Uint8List.fromList(signature.bytes);
  }

  /// Secreto compartido X25519 con [theirPublicKey].
  ///
  /// Lanza [DeviceKeyException] si la clave no tiene 32 bytes o es de orden
  /// bajo (el secreto sale todo ceros).
  Future<SecretKey> agree(List<int> theirPublicKey) =>
      x25519Agree(_agreementPair, theirPublicKey);

  @override
  String toString() => 'DeviceKeys(…)';
}

/// Secreto X25519 entre [mine] y [theirPublicKey], rechazando las claves de
/// orden bajo (secreto de ceros) y las de longitud equivocada.
Future<SecretKey> x25519Agree(
  SimpleKeyPair mine,
  List<int> theirPublicKey,
) async {
  if (theirPublicKey.length != _publicLength) {
    throw const DeviceKeyException('clave pública no válida');
  }
  final SecretKey secret;
  try {
    secret = await X25519().sharedSecretKey(
      keyPair: mine,
      remotePublicKey: SimplePublicKey(
        theirPublicKey,
        type: KeyPairType.x25519,
      ),
    );
  } catch (_) {
    throw const DeviceKeyException('clave pública no válida');
  }
  final bytes = await secret.extractBytes();
  if (bytes.every((b) => b == 0)) {
    throw const DeviceKeyException('clave pública de orden bajo');
  }
  return secret;
}

/// Comprueba una firma Ed25519 de [message] con la clave pública
/// [signingPublicKey]. Devuelve false si no vale (nunca lanza).
Future<bool> verifyDeviceSignature({
  required List<int> message,
  required List<int> signature,
  required List<int> signingPublicKey,
}) async {
  if (signature.length != _signatureLength ||
      signingPublicKey.length != _publicLength) {
    return false;
  }
  try {
    return await Ed25519().verify(
      message,
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(signingPublicKey, type: KeyPairType.ed25519),
      ),
    );
  } catch (_) {
    return false;
  }
}

/// Texto JSON compacto con las claves ordenadas, para AAD y firmas.
List<int> canonicalHeaderBytes(Map<String, Object?> fields) {
  final keys = fields.keys.toList()..sort();
  return utf8.encode(
    jsonEncode(<String, Object?>{for (final k in keys) k: fields[k]}),
  );
}
