// PBKDF2-HMAC-SHA256 fuera del navegador (pruebas en la VM): la
// implementación en Dart puro de `cryptography`, llamada sobre su clase
// concreta. En la web se usa `vault_pbkdf2_web.dart` (WebCrypto).
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:cryptography/dart.dart' show DartHmac, DartPbkdf2, DartSha256;

/// PBKDF2-HMAC-SHA256 de [password] con [salt], [iterations] vueltas y
/// [bits] de salida.
Future<Uint8List> pbkdf2Sha256(
  List<int> password,
  List<int> salt, {
  required int iterations,
  required int bits,
}) async {
  final key = await DartPbkdf2(
    macAlgorithm: const DartHmac(DartSha256()),
    iterations: iterations,
    bits: bits,
  ).deriveKey(secretKey: SecretKey(password), nonce: salt);
  return Uint8List.fromList(await key.extractBytes());
}
