// HKDF-SHA256 propio (lib/core/sync/hkdf.dart): los mismos bytes que el
// `DartHkdf` de `cryptography` (lo que usaban móviles y web hasta la 1.0.1),
// así que lo que selló uno lo abre el otro; y el vector 1 de RFC 5869.
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/hkdf.dart';

List<int> _hex(String s) => [
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
];

void main() {
  test('RFC 5869 test case 1', () {
    final okm = hkdfSha256Bytes(
      _hex('0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b'),
      salt: _hex('000102030405060708090a0b0c'),
      info: _hex('f0f1f2f3f4f5f6f7f8f9'),
      length: 42,
    );
    expect(
      okm,
      _hex(
        '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf'
        '34007208d5b887185865',
      ),
    );
  });

  test('same bytes as cryptography DartHkdf (empty and long salts, '
      'lengths 3, 16, 32, 64)', () async {
    final random = Random(42);
    List<int> bytes(int n) => [for (var i = 0; i < n; i++) random.nextInt(256)];
    for (var round = 0; round < 40; round++) {
      final ikm = bytes(1 + random.nextInt(64));
      final salt = round % 4 == 0 ? <int>[] : bytes(random.nextInt(100));
      final info = bytes(random.nextInt(40));
      for (final length in [3, 16, 32, 64]) {
        final theirs = await DartHkdf(
          hmac: const DartHmac(DartSha256()),
          outputLength: length,
        ).deriveKey(secretKey: SecretKey(ikm), nonce: salt, info: info);
        final ours = await hkdfSha256(
          secretKey: SecretKey(ikm),
          nonce: salt,
          info: info,
          length: length,
        );
        expect(
          await ours.extractBytes(),
          await theirs.extractBytes(),
          reason: 'round $round length $length',
        );
      }
    }
  });

  test('RFC 5869 test case 2 (long inputs, 82 bytes)', () {
    List<int> range(int from, int to) => [for (var i = from; i <= to; i++) i];
    expect(
      hkdfSha256Bytes(
        range(0x00, 0x4f),
        salt: range(0x60, 0xaf),
        info: range(0xb0, 0xff),
        length: 82,
      ),
      _hex(
        'b11e398dc80327a1c8e7f78c596a49344f012eda2d4efad8a050cc4c19afa97c'
        '59045a99cac7827271cb41c65e590e09da3275600c2f09b8367793a9aca3db71'
        'cc30c58179ec3e87c14c01d5c1f3434f1d87',
      ),
    );
  });

  test('RFC 5869 test case 3 (empty salt and info)', () {
    expect(
      hkdfSha256Bytes(List<int>.filled(22, 0x0b), length: 42),
      _hex(
        '8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d'
        '9d201395faa4b61a96c8',
      ),
    );
  });

  test('65 and 8160 bytes (the maximum) match DartHkdf', () async {
    for (final length in [65, 255 * 32]) {
      final theirs = await DartHkdf(
        hmac: const DartHmac(DartSha256()),
        outputLength: length,
      ).deriveKey(secretKey: SecretKey([1, 2, 3]), nonce: [4], info: [5]);
      expect(
        hkdfSha256Bytes([1, 2, 3], salt: [4], info: [5], length: length),
        await theirs.extractBytes(),
        reason: 'length $length',
      );
    }
  });

  test('rejects negative, zero and over-limit lengths', () {
    for (final length in [-1, 0, 255 * 32 + 1]) {
      expect(
        () => hkdfSha256Bytes([1], length: length),
        throwsArgumentError,
        reason: 'length $length',
      );
    }
  });
}
