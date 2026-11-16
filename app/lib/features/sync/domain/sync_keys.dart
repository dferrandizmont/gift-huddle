// Claves de la sincronización. Dart puro (sin Flutter).
// Decisión: docs/adr/0002-sincronizacion.md.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../../core/sync/envelope.dart';
import '../../../core/sync/hkdf.dart';

const _authSalt = 'gift-huddle';
const _authInfo = 'sync-auth-v1';
const _syncIdInfo = 'sync-id-v1';

/// Claves que se derivan de la clave de la familia para hablar con el
/// servidor. El servidor nunca recibe la clave de la familia.
abstract final class SyncKeys {
  /// `authKey = HKDF-SHA256(familyKey, salt = "gift-huddle",
  /// info = "sync-auth-v1", 32 bytes)`.
  ///
  /// Quien la tiene puede leer y escribir la lista cifrada en el servidor,
  /// pero no descifrarla.
  static Future<Uint8List> authKey(FamilyKey familyKey) async {
    final derived = await hkdfSha256(
      secretKey: SecretKey(familyKey.bytes),
      nonce: utf8.encode(_authSalt),
      info: utf8.encode(_authInfo),
    );
    return Uint8List.fromList(await derived.extractBytes());
  }

  /// `syncId = base64url(HKDF-SHA256(familyKey, salt = "gift-huddle",
  /// info = "sync-id-v1", 16 bytes))`, sin relleno (22 caracteres): el
  /// identificador de la lista en el servidor. Sin la clave no se puede
  /// calcular ni ocupar (el `listId` va en claro en los sobres `.regalos`).
  static Future<String> syncId(FamilyKey familyKey) async {
    final derived = await hkdfSha256(
      secretKey: SecretKey(familyKey.bytes),
      nonce: utf8.encode(_authSalt),
      info: utf8.encode(_syncIdInfo),
      length: 16,
    );
    return encodeBase64Url(await derived.extractBytes());
  }

  /// `SHA-256(authKey)`: lo único que guarda el servidor para reconocer a
  /// quien escribe.
  static Future<Uint8List> verifier(List<int> authKey) async =>
      Uint8List.fromList((await Sha256().hash(authKey)).bytes);

  /// El valor de `Authorization: Bearer <...>`.
  static String bearer(List<int> authKey) => encodeBase64Url(authKey);
}
