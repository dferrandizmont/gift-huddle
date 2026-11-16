// HMAC-SHA256 síncrono compartido por las pruebas de emparejamiento
// (`pairing_v2.dart`) y los ids de movimiento (`protected_doc.dart`).
library;

import 'dart:typed_data';

import 'package:cryptography/dart.dart';

/// HMAC-SHA256 (RFC 2104) síncrono. Una clave de más de 64 bytes se resume
/// antes con SHA-256.
List<int> hmacSha256(List<int> key, List<int> message) {
  const sha = DartSha256();
  final short = key.length > 64 ? sha.hashSync(key).bytes : key;
  final k = Uint8List(64)..setRange(0, short.length, short);
  final inner = sha.hashSync([for (final b in k) b ^ 0x36, ...message]).bytes;
  return sha.hashSync([for (final b in k) b ^ 0x5c, ...inner]).bytes;
}
