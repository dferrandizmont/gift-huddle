// Vectores de X25519 de orden bajo (ADR 0005, B5, nota «X25519» de B1): lo
// que da el Dart (VM y, compilado, la web) con la clave de acuerdo de Leo
// frente a los puntos de orden bajo de Curve25519 y sus formas no reducidas.
// `server/test/webcrypto-vectors.test.ts` comprueba que WebCrypto da lo
// mismo: rechaza las siete primeras (secreto de ceros) y, en las que llevan
// el bit alto, que el RFC 7748 enmascara, da el mismo secreto no nulo.
//
// Regenerar (solo si cambia la biblioteca):
//   REGALOS_WRITE_VECTORS=1 flutter test test/sync/x25519_vector_test.dart
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/device_keys.dart';
import 'package:regalos/core/sync/envelope.dart';

import '../web_device/vectors_data.dart';

const _path = '../docs/adr/0005-vector-x25519.json';

String _hexOf(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

List<int> _hex(String s) => [
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
];

const _points = <String>[
  '0000000000000000000000000000000000000000000000000000000000000000',
  '0100000000000000000000000000000000000000000000000000000000000000',
  'e0eb7a7c3b41b8ae1656e3faf19fc46ada098deb9c32b1fd866205165f49b800',
  '5f9c95bca3508c24b1d0b1559c83ef5b04445cc4581c8e86d8224eddd09f1157',
  'ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f',
  'edffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f',
  'eeffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f',
  'cdeb7a7c3b41b8ae1656e3faf19fc46ada098deb9c32b1fd866205165f49b880',
  '4c9c95bca3508c24b1d0b1559c83ef5b04445cc4581c8e86d8224eddd09f11d7',
  'd9ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
  'daffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
  'dbffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
];

Future<Map<String, Object?>> _compute() async {
  final seed = List<int>.filled(32, 2);
  final leo = await DeviceKeys.fromSeedsForTesting(
    agreementSeed: seed,
    signingSeed: List<int>.filled(32, 102),
    serviceCredential: List<int>.filled(32, 0),
  );
  final aritz = await DeviceKeys.fromSeedsForTesting(
    agreementSeed: List<int>.filled(32, 1),
    signingSeed: List<int>.filled(32, 101),
    serviceCredential: List<int>.filled(32, 0),
  );
  Future<String?> agree(List<int> point) async {
    try {
      return _hexOf(await (await leo.agree(point)).extractBytes());
    } on DeviceKeyException {
      return null;
    }
  }

  return <String, Object?>{
    'about':
        'ADR 0005, B5. X25519 con la clave privada de semilla agreementSeed '
        '(hexadecimal). secret null: rechazado (secreto de ceros). Las siete '
        'primeras son de orden bajo; las cinco últimas llevan el bit alto, '
        'que el RFC 7748 enmascara.',
    'agreementSeed': _hexOf(seed),
    'agreementPublic': _hexOf(leo.publicKeys.agreement),
    'control': {
      'public': _hexOf(aritz.publicKeys.agreement),
      'secret': await agree(aritz.publicKeys.agreement),
    },
    'points': [
      for (final p in _points) {'public': p, 'secret': await agree(_hex(p))},
    ],
  };
}

void main() {
  test(
    'los vectores de X25519 de orden bajo salen igual desde el Dart',
    () async {
      final computed = await _compute();
      final text = '${const JsonEncoder.withIndent('  ').convert(computed)}\n';
      final file = io.File(_path);
      if (io.Platform.environment['REGALOS_WRITE_VECTORS'] == '1') {
        file.writeAsStringSync(text);
      }
      expect(jsonDecode(file.readAsStringSync()), jsonDecode(text));
      final points = computed['points']! as List;
      for (var i = 0; i < points.length; i++) {
        final secret = (points[i] as Map)['secret'];
        expect(secret == null, i < 7, reason: '$i');
      }
      expect(
        encodeBase64Url(_hex(computed['agreementPublic']! as String)),
        'zo060cy2M-x7cMF4FKXHbs0CloUFDTRHRboFhw5YfVk',
      );
    },
  );

  test('la copia de los vectores para el navegador es la de docs/adr', () {
    expect(
      jsonDecode(kX25519Vectors),
      jsonDecode(io.File(_path).readAsStringSync()),
    );
    expect(
      jsonDecode(kCommonKeyVectors),
      jsonDecode(
        io.File('../docs/adr/0005-vector-clave-comun.json').readAsStringSync(),
      ),
    );
  });
}
