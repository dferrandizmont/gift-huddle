// PBKDF2-HMAC-SHA256 del navegador (WebCrypto `deriveBits`), sin pasar por
// `Pbkdf2` de `cryptography`: compilado a wasm, dart2wasm (Flutter 3.47)
// deja sin destino su `deriveKey` (comparte selector con el de Hkdf y
// Argon2id) y lo cambia por `unreachable`; guardar el PIN de la web se
// paraba ahí. Los bytes son los mismos (es el mismo PBKDF2 que usaba
// `BrowserPbkdf2`): las cajas que ya hay se siguen abriendo con su PIN.
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// PBKDF2-HMAC-SHA256 de [password] con [salt], [iterations] vueltas y
/// [bits] de salida.
Future<Uint8List> pbkdf2Sha256(
  List<int> password,
  List<int> salt, {
  required int iterations,
  required int bits,
}) async {
  final subtle = web.window.crypto.subtle;
  final pin = Uint8List.fromList(password);
  final pinJs = pin.toJS;
  Uint8List? derived;
  try {
    final key = await subtle
        .importKey(
          'raw',
          pinJs,
          'PBKDF2'.toJS,
          false,
          ['deriveBits'.toJS].toJS,
        )
        .toDart;
    final params = _Pbkdf2Params(
      name: 'PBKDF2',
      hash: 'SHA-256',
      salt: Uint8List.fromList(salt).toJS,
      iterations: iterations,
    );
    final bitsBuffer = await subtle.deriveBits(params, key, bits).toDart;
    derived = bitsBuffer.toDart.asUint8List();
    return Uint8List.fromList(derived);
  } finally {
    // Las copias propias del PIN y de lo derivado se borran también si
    // WebCrypto falla (nunca las del que llama).
    pin.fillRange(0, pin.length, 0);
    final pinView = pinJs.toDart;
    pinView.fillRange(0, pinView.length, 0);
    derived?.fillRange(0, derived.length, 0);
  }
}

/// `Pbkdf2Params` de WebCrypto (un objeto literal).
extension type _Pbkdf2Params._(JSObject _) implements JSObject {
  external factory _Pbkdf2Params({
    String name,
    String hash,
    JSUint8Array salt,
    int iterations,
  });
}
