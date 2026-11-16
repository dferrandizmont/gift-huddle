import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/envelope.dart';

FamilyKey _key(int n) => FamilyKey(List<int>.filled(32, n));

void main() {
  test('hashCode de la clave no depende de sus bytes', () {
    expect(_key(1).hashCode, _key(2).hashCode);
    expect(_key(1), _key(1));
    expect(_key(1), isNot(_key(2)));
  });

  test('parse rechaza cuerpos de más de 4096 caracteres', () {
    final long = 'regalos-pair:v1:${'A' * 4097}';
    expect(
      () => PairingPayload.parse(long),
      throwsA(
        isA<PairingFormatException>().having(
          (e) => e.message,
          'message',
          contains('largo'),
        ),
      ),
    );
    final ok = PairingPayload(
      listId: 'L',
      key: _key(3),
      deviceName: 'x',
    ).toQrText();
    expect(PairingPayload.parse(ok).listId, 'L');
  });

  test('el nombre pierde controles y caracteres bidi', () {
    final p = PairingPayload(
      listId: 'L',
      key: _key(3),
      deviceName: 'Aritz\u202E\u0000\n\u200Bfdp\u0007',
    );
    expect(p.deviceName, 'Aritzfdp');
    expect(PairingPayload.parse(p.toQrText()).deviceName, 'Aritzfdp');
  });

  test('listId solo acepta [A-Za-z0-9_-]{1,128} en el emparejamiento', () {
    String enc(String l) {
      final json = jsonEncode({
        'v': 1,
        'l': l,
        'k': _key(3).toBase64Url(),
        'n': 'x',
      });
      return 'regalos-pair:v1:${encodeBase64Url(utf8.encode(json))}';
    }

    expect(PairingPayload.parse(enc('a' * 128)).listId, 'a' * 128);
    for (final bad in ['a' * 129, '', 'a b', 'a/b', 'ñ', 'a\u202Eb', 'a.b']) {
      expect(
        () => PairingPayload.parse(enc(bad)),
        throwsA(isA<PairingFormatException>()),
        reason: bad,
      );
    }
  });

  test('listId inválido: seal lo rechaza y peekHeader/open también', () async {
    final key = _key(4);
    await expectLater(
      seal(doc: {}, listId: 'a b', fromNode: 'n', at: 't', key: key),
      throwsArgumentError,
    );
    // Sobre bien autenticado pero con listId fuera de patrón, hecho a mano.
    for (final bad in ['a b', 'a\u202Eb', '']) {
      final header = utf8.encode(
        jsonEncode({
          'at': 't',
          'from': 'n',
          'kind': 'family',
          'l': bad,
          'v': 1,
        }),
      );
      final aad = Uint8List.fromList([
        0x52, 0x47, 1, header.length >> 8, header.length & 0xFF, //
        ...header,
      ]);
      final nonce = List<int>.filled(12, 1);
      final box = await AesGcm.with256bits().encrypt(
        [3],
        secretKey: SecretKey(key.bytes),
        nonce: nonce,
        aad: aad,
      );
      final bytes = Uint8List.fromList([
        ...aad, ...nonce, ...box.cipherText, ...box.mac.bytes, //
      ]);
      expect(() => peekHeader(bytes), throwsA(isA<EnvelopeFormatException>()));
      await expectLater(
        open(bytes, key: key, expectedListId: bad),
        throwsA(isA<EnvelopeFormatException>()),
        reason: bad,
      );
    }
  });
}
