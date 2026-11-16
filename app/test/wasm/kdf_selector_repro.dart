// ignore_for_file: avoid_print
// Reproducción del fallo de la web 1.0.1 (dart2wasm, Flutter 3.47): con
// `Pbkdf2` en el mismo programa, `Hkdf(...).deriveKey(..., info: ...)` de
// `cryptography` se compila como `unreachable` (también en -O2).
//
//   dart compile wasm -O4 -DBUG=true test/wasm/kdf_selector_repro.dart \
//     -o build/kdf/probe.wasm && node test/wasm/run_probe.mjs build/kdf
//   -> RuntimeError: unreachable (código 1)
//
// Sin `-DBUG=true` usa `hkdfSha256` (lib/core/sync/hkdf.dart) y termina bien,
// con los mismos bytes que `DartHkdf`.
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:regalos/core/sync/hkdf.dart';

const _bug = bool.fromEnvironment('BUG');

Future<void> main() async {
  final secret = SecretKey(List<int>.filled(32, 1));
  if (DateTime.now().year > 2000) {
    final p = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 2,
      bits: 256,
    ).deriveKey(secretKey: secret, nonce: [9, 9]);
    print('pbkdf2 ${(await p.extractBytes()).length}');
  }
  final k = _bug
      ? await Hkdf(
          hmac: Hmac.sha256(),
          outputLength: 32,
        ).deriveKey(secretKey: secret, nonce: [1, 2, 3], info: utf8.encode('i'))
      : await hkdfSha256(
          secretKey: secret,
          nonce: [1, 2, 3],
          info: utf8.encode('i'),
        );
  print('hkdf ${(await k.extractBytes()).length}');
  print('PROBE DONE ok=1 fail=0');
}
