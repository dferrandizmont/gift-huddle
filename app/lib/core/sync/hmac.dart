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
  final innerInput = [for (final b in k) b ^ 0x36, ...message];
  final inner = sha.hashSync(innerInput).bytes;
  final outerInput = [for (final b in k) b ^ 0x5c, ...inner];
  final out = sha.hashSync(outerInput).bytes;
  // Los búferes propios se borran; [key] y [message] son del que llama.
  wipeBytes(k);
  wipeBytes(innerInput);
  wipeBytes(outerInput);
  wipeBytes(inner);
  if (!identical(short, key)) wipeBytes(short);
  return out;
}

/// Pone a cero [bytes] si se puede (una lista inmodificable se deja).
void wipeBytes(List<int> bytes) {
  try {
    bytes.fillRange(0, bytes.length, 0);
  } on UnsupportedError {
    // Inmodificable: nada que borrar.
  }
}
