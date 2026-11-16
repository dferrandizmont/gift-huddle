// HKDF-SHA256 (RFC 5869) propio, sobre el HMAC síncrono de `hmac.dart`.
//
// No se usa `Hkdf` de `cryptography`: en la web compilada a wasm, `dart2wasm`
// (Flutter 3.47) junta en un mismo selector `deriveKey` el de `Pbkdf2`
// (`secretKey`, `nonce`) y el de `Hkdf` (`secretKey`, `nonce`, `info`); con
// los dos en el programa, la llamada de `Hkdf` con `info` se queda sin destino,
// el compilador borra `DartHkdf.deriveKey` y `BrowserHkdf.deriveKey` y deja un
// `unreachable`: la web se paraba al abrir el paquete de la clave de la
// familia (`KeyBundle._wrapKey`, 1.0.1) y lo mismo le pasaría a la caja web.
// Reproducido en 30 líneas con `dart compile wasm` en -O2 y -O4
// (`test/wasm/kdf_selector_repro.dart`). Los bytes son los mismos que los de
// `cryptography` (prueba `hkdf_test.dart`): móviles y web siguen entendiéndose.
library;

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show SecretKey, SecretKeyData;

import 'hmac.dart';

/// Los bytes de HKDF-SHA256 de [ikm] con sal [salt] (vacía: 32 ceros, que
/// para HMAC es lo mismo) e [info], [length] bytes (como mucho 255 × 32).
Uint8List hkdfSha256Bytes(
  List<int> ikm, {
  List<int> salt = const <int>[],
  List<int> info = const <int>[],
  int length = 32,
}) {
  if (length < 1 || length > 255 * 32) {
    throw ArgumentError.value(length, 'length');
  }
  // Extract.
  final prk = hmacSha256(salt, ikm);
  // Expand.
  final out = Uint8List(length);
  var previous = const <int>[];
  var offset = 0;
  for (var i = 1; offset < length; i++) {
    final input = [...previous, ...info, i];
    final next = hmacSha256(prk, input);
    // Lo intermedio es propio: se borra en cuanto deja de hacer falta.
    wipeBytes(input);
    if (i > 1) wipeBytes(previous);
    previous = next;
    final n = length - offset < previous.length
        ? length - offset
        : previous.length;
    out.setRange(offset, offset + n, previous);
    offset += n;
  }
  wipeBytes(previous);
  wipeBytes(prk);
  return out;
}

/// [hkdfSha256Bytes] con la forma de `Hkdf.deriveKey` de `cryptography`:
/// [nonce] es la sal.
Future<SecretKey> hkdfSha256({
  required SecretKey secretKey,
  List<int> nonce = const <int>[],
  List<int> info = const <int>[],
  int length = 32,
}) async => SecretKeyData(
  hkdfSha256Bytes(
    await secretKey.extractBytes(),
    salt: nonce,
    info: info,
    length: length,
  ),
);
