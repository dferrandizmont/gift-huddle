import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/device_keys.dart';
import 'package:regalos/core/sync/envelope.dart';

/// Claves por móvil (ADR 0004, fase 1). Los paquetes: key_bundle_test.dart.
void main() {
  // Puntos de orden bajo de Curve25519: con cualquier clave privada el
  // secreto X25519 sale todo ceros.
  final lowOrder = <List<int>>[
    Uint8List(32),
    [1, ...List<int>.filled(31, 0)],
    _hex('e0eb7a7c3b41b8ae1656e3faf19fc46ada098deb9c32b1fd866205165f49b800'),
    _hex('5f9c95bca3508c24b1d0b1559c83ef5b04445cc4581c8e86d8224eddd09f1157'),
    _hex('ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f'),
  ];

  group('claves del móvil', () {
    test('se generan distintas cada vez, con credencial aleatoria', () async {
      final a = await DeviceKeys.generate();
      final b = await DeviceKeys.generate();
      expect(a.publicKeys.agreement, isNot(b.publicKeys.agreement));
      expect(a.publicKeys.signing, isNot(b.publicKeys.signing));
      expect(a.serviceCredential, isNot(b.serviceCredential));
      expect(a.serviceCredential, hasLength(32));
    });

    test(
      'la credencial de servicio no depende de la clave de la familia',
      () async {
        final familyKey = await FamilyKey.generate();
        final keys = await DeviceKeys.generate();
        expect(keys.serviceCredential, isNot(familyKey.bytes));
        expect(await keys.serviceCredentialVerifier(), hasLength(32));
      },
    );

    test('ida y vuelta por JSON con las mismas claves públicas', () async {
      final keys = await DeviceKeys.generate();
      final back = await DeviceKeys.fromJson(keys.toJson());
      expect(back.publicKeys.agreement, keys.publicKeys.agreement);
      expect(back.publicKeys.signing, keys.publicKeys.signing);
      expect(back.serviceCredential, keys.serviceCredential);
      expect(keys.toString(), isNot(contains(keys.toJson()['x'] as String)));
    });

    test(
      'vector fijo: de las semillas salen siempre las mismas claves',
      () async {
        final keys = await DeviceKeys.fromSeedsForTesting(
          agreementSeed: _hex(
            '77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a',
          ),
          signingSeed: List<int>.generate(32, (i) => 32 + i),
          serviceCredential: List<int>.filled(32, 7),
        );
        // RFC 7748 §6.1: la clave pública de Alice.
        expect(
          _toHex(keys.publicKeys.agreement),
          '8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a',
        );
        final signature = await keys.sign([1, 2, 3]);
        expect(
          await verifyDeviceSignature(
            message: [1, 2, 3],
            signature: signature,
            signingPublicKey: keys.publicKeys.signing,
          ),
          isTrue,
        );
      },
    );

    test('firma falsa o de otro móvil: no vale', () async {
      final a = await DeviceKeys.generate();
      final b = await DeviceKeys.generate();
      final signature = await a.sign([9, 9]);
      expect(
        await verifyDeviceSignature(
          message: [9, 9],
          signature: signature,
          signingPublicKey: b.publicKeys.signing,
        ),
        isFalse,
      );
      expect(
        await verifyDeviceSignature(
          message: [9, 9],
          signature: Uint8List(64),
          signingPublicKey: a.publicKeys.signing,
        ),
        isFalse,
      );
      expect(
        await verifyDeviceSignature(
          message: [9, 8],
          signature: signature,
          signingPublicKey: a.publicKeys.signing,
        ),
        isFalse,
      );
    });

    test('rechaza las claves X25519 de orden bajo', () async {
      final keys = await DeviceKeys.generate();
      for (final point in lowOrder) {
        await expectLater(
          keys.agree(point),
          throwsA(isA<DeviceKeyException>()),
          reason: _toHex(point),
        );
      }
      await expectLater(
        keys.agree(Uint8List(31)),
        throwsA(isA<DeviceKeyException>()),
      );
    });
  });
}

Uint8List _hex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

String _toHex(List<int> bytes) =>
    [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();
