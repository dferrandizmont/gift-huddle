import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/features/web_device/data/vault_crypto.dart';

class _NoKdf extends VaultCrypto {
  bool derived = false;
  @override
  Future<SecretKey> pbkdf2(List<int> pinBytes, VaultHeader header) {
    derived = true;
    throw StateError('PBKDF2 must not start');
  }
}

void main() {
  final vector = jsonDecode(
    File('../docs/adr/0003-vector-caja.json').readAsStringSync(),
  ) as Map;
  final crypto = VaultCrypto();
  final header = VaultHeader.fromJson(
    Map<String, Object?>.from(vector['header'] as Map),
  );
  test('independent Node PBKDF2/HKDF/AES-GCM ASCII vector', () async {
    final bigA = await crypto.deriveA(vector['pin'] as String, header);
    expect(encodeBase64Url(await bigA.extractBytes()), vector['A']);
    final a = await crypto.hkdf(bigA, 'gift-huddle web vault-a v1');
    final proof = await crypto.hkdf(bigA, 'gift-huddle web guard-proof v1');
    expect(encodeBase64Url(await a.extractBytes()), vector['a']);
    expect(encodeBase64Url(await proof.extractBytes()), vector['prueba']);
    final key = await crypto.key(
      VaultDerivation(a, proof),
      decodeBase64Url(vector['b'] as String),
    );
    expect(encodeBase64Url(await key.extractBytes()), vector['K']);
    expect(utf8.decode(crypto.aad(header, 'vault', '')), vector['aad']);
    expect(
      await crypto.open(
        Map<String, Object?>.from(vector['box'] as Map),
        key,
        header,
        'vault',
      ),
      vector['plaintext'],
    );
    final sealed = await AesGcm.with256bits().encrypt(
      utf8.encode(jsonEncode(vector['plaintext'])),
      secretKey: key,
      nonce: decodeBase64Url(vector['nonce'] as String),
      aad: crypto.aad(header, 'vault', ''),
    );
    expect(
      encodeBase64Url(sealed.cipherText),
      (vector['box'] as Map)['ciphertext'],
    );
    expect(encodeBase64Url(sealed.mac.bytes), (vector['box'] as Map)['mac']);
  });
  test('VM accepts ASCII and explicitly rejects every non-ASCII PIN', () async {
    for (final pin in [
      'Cafe\u0301 Nora',
      'Café Nora',
      '\u1100\u1161\u11a8',
      'phrase\u00a0',
    ]) {
      expect(() => VaultCrypto.validPin(pin), throwsUnsupportedError);
      await expectLater(crypto.deriveA(pin, header), throwsUnsupportedError);
    }
    expect(VaultCrypto.validPin('12345'), isFalse);
    expect(VaultCrypto.validPin('123456'), isTrue);
    expect(VaultCrypto.validPin('frase 12'), isTrue);
    expect(VaultCrypto.validPin('corta'), isFalse);
  });
  test('AAD binds device, version, kind and queue id', () async {
    final key = SecretKey(decodeBase64Url(vector['K'] as String));
    final box = Map<String, Object?>.from(vector['box'] as Map);
    for (final change in [
      {'deviceId': 'cccccccccc'},
      {'guardVersion': 2},
      {'format': 2},
    ]) {
      await expectLater(() async {
        final altered = VaultHeader.fromJson({...header.toJson(), ...change});
        await crypto.open(box, key, altered, 'vault');
      }, throwsA(anything));
    }
    await expectLater(
      crypto.open(box, key, header, 'queue'),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
    final queued = await crypto.seal(
      {'delta': 'Nora'},
      key,
      header,
      'queue',
      'one',
    );
    await expectLater(
      crypto.open(queued, key, header, 'queue', 'two'),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
    final ciphertext = decodeBase64Url(box['ciphertext'] as String)..[0] ^= 1;
    await expectLater(
      crypto.open(
        {...box, 'ciphertext': encodeBase64Url(ciphertext)},
        key,
        header,
        'vault',
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });
  test('1000 writes use 1000 fresh 96-bit nonces', () async {
    final key = SecretKey(List.filled(32, 7));
    final nonces = <String>{};
    for (var i = 0; i < 1000; i++) {
      final box = await crypto.seal({'n': i}, key, header, 'queue', 'same');
      expect(decodeBase64Url(box['nonce'] as String), hasLength(12));
      nonces.add(box['nonce'] as String);
    }
    expect(nonces, hasLength(1000));
  });
  test('untrusted KDF parameters fail before any derivation', () async {
    final noKdf = _NoKdf();
    for (final params in [
      {'iterations': 599999},
      {'iterations': 2000001},
      {'format': 2},
      {'salt': encodeBase64Url(List.filled(15, 0))},
    ]) {
      await expectLater(() async {
        final h = VaultHeader.fromJson({...header.toJson(), ...params});
        await noKdf.derive('123456', h);
      }, throwsFormatException);
      final direct = VaultHeader(
        syncId: header.syncId,
        deviceId: header.deviceId,
        guardToken: header.guardToken,
        salt: params.containsKey('salt') ? List.filled(15, 0) : header.salt,
        guardVersion: 1,
        format: params['format'] as int? ?? 1,
        iterations: params['iterations'] as int? ?? 600000,
      );
      await expectLater(noKdf.derive('123456', direct), throwsFormatException);
    }
    expect(noKdf.derived, isFalse);
  });
}
