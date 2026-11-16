import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/envelope.dart';

const _listId = 'lista-0001';
const _node = 'nodo-aritz';
const _at = '0001a2b3c4d5-0003-nodo-aritz';

final _doc = <String, Object?>{
  'items': [
    {
      'id': 'i1',
      'name': 'Muñeca con sombrero ñandú',
      'note': 'Cumpleaños, árbol',
    },
    {'id': 'i2', 'name': 'Bicicleta', 'price': 120},
  ],
  'people': ['Aritz', 'Nora', 'Leo'],
};

FamilyKey _fixedKey() => FamilyKey(List<int>.generate(32, (i) => i));

Future<Uint8List> _seal({FamilyKey? key, Map<String, Object?>? doc}) async =>
    seal(
      doc: doc ?? _doc,
      listId: _listId,
      fromNode: _node,
      at: _at,
      key: key ?? _fixedKey(),
    );

bool _contains(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var ok = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return true;
  }
  return false;
}

/// Construye a mano un sobre válido con un cuerpo deflate arbitrario.
Future<Uint8List> _handSeal(List<int> deflated, FamilyKey key) async {
  final header = utf8.encode(
    '{"at":"$_at","from":"$_node","kind":"family","l":"$_listId","v":1}',
  );
  final aad = Uint8List.fromList([
    0x52, 0x47, 1, header.length >> 8, header.length & 0xFF, //
    ...header,
  ]);
  final nonce = List<int>.filled(12, 7);
  final box = await AesGcm.with256bits().encrypt(
    deflated,
    secretKey: SecretKey(key.bytes),
    nonce: nonce,
    aad: aad,
  );
  return Uint8List.fromList([
    ...aad,
    ...nonce,
    ...box.cipherText,
    ...box.mac.bytes,
  ]);
}

void main() {
  group('FamilyKey', () {
    test(
      'genera 32 bytes distintos cada vez y va y viene en base64url',
      () async {
        final a = await FamilyKey.generate();
        final b = await FamilyKey.generate();
        expect(a.bytes.length, 32);
        expect(a, isNot(b));
        final text = a.toBase64Url();
        expect(text, isNot(contains('=')));
        expect(FamilyKey.fromBase64Url(text), a);
      },
    );

    test('valida la longitud', () {
      expect(() => FamilyKey(List<int>.filled(31, 1)), throwsArgumentError);
      expect(
        () => FamilyKey.fromBase64Url(encodeBase64Url(List<int>.filled(33, 1))),
        throwsArgumentError,
      );
      expect(() => FamilyKey.fromBase64Url('***'), throwsArgumentError);
    });

    test('toString no revela la clave', () {
      final k = _fixedKey();
      expect(k.toString(), 'FamilyKey(…)');
      expect(k.toString(), isNot(contains(k.toBase64Url())));
    });
  });

  group('PairingPayload', () {
    test('ida y vuelta, con espacios y saltos de línea alrededor', () async {
      final key = await FamilyKey.generate();
      final p = PairingPayload(
        listId: _listId,
        key: key,
        deviceName: 'Móvil de Aritz',
      );
      final text = p.toQrText();
      expect(text, startsWith('regalos-pair:v1:'));
      final back = PairingPayload.parse('  \n$text\r\n ');
      expect(back.listId, _listId);
      expect(back.key, key);
      expect(back.deviceName, 'Móvil de Aritz');
    });

    test('el JSON es compacto y en el orden v, l, k, n', () {
      final p = PairingPayload(listId: 'L', key: _fixedKey(), deviceName: 'N');
      final body = p.toQrText().substring('regalos-pair:v1:'.length);
      expect(
        utf8.decode(decodeBase64Url(body)),
        '{"v":1,"l":"L","k":"${_fixedKey().toBase64Url()}","n":"N"}',
      );
    });

    test('recorta el nombre a 40 caracteres', () {
      final p = PairingPayload(
        listId: _listId,
        key: _fixedKey(),
        deviceName: 'ñ' * 60,
      );
      expect(p.deviceName.length, 40);
      expect(PairingPayload.parse(p.toQrText()).deviceName, 'ñ' * 40);
    });

    test('rechaza basura', () {
      final good = PairingPayload(
        listId: _listId,
        key: _fixedKey(),
        deviceName: 'x',
      ).toQrText();
      String enc(String json) =>
          'regalos-pair:v1:${encodeBase64Url(utf8.encode(json))}';
      final k = _fixedKey().toBase64Url();
      for (final bad in <String>[
        '',
        'hola',
        'regalos-pair:v1:',
        'regalos-pair:v1:@@@@',
        'regalos-pair:v2:${good.split(':').last}',
        'https://regalos.example/s#abc',
        enc('no json'),
        enc('[]'),
        enc('{"v":2,"l":"a","k":"$k","n":"x"}'),
        enc('{"v":1,"l":"","k":"$k","n":"x"}'),
        enc('{"v":1,"l":"a","k":"corta","n":"x"}'),
        enc('{"v":1,"l":"a","k":"$k"}'),
        enc('{"v":1,"l":1,"k":"$k","n":"x"}'),
      ]) {
        expect(
          () => PairingPayload.parse(bad),
          throwsA(isA<PairingFormatException>()),
          reason: bad,
        );
      }
    });
  });

  group('sobre', () {
    test('ida y vuelta con tildes y ñ', () async {
      final key = await FamilyKey.generate();
      final bytes = await _seal(key: key);
      final opened = await open(bytes, key: key, expectedListId: _listId);
      expect(opened.doc, _doc);
      expect(opened.header.listId, _listId);
      expect(opened.header.fromNode, _node);
      expect(opened.header.at, _at);
      expect(opened.header.kind, 'family');
    });

    test('cabecera con claves ordenadas y estructura de bytes', () async {
      final bytes = await _seal();
      expect(bytes.sublist(0, 3), [0x52, 0x47, 1]);
      final hLen = (bytes[3] << 8) | bytes[4];
      expect(
        utf8.decode(bytes.sublist(5, 5 + hLen)),
        '{"at":"$_at","from":"$_node","kind":"family","l":"$_listId","v":1}',
      );
    });

    test('dos sobres iguales usan nonce distinto', () async {
      expect(await _seal(), isNot(await _seal()));
    });

    test('el cuerpo es deflate en bruto (lo abre dart:io raw)', () async {
      final key = _fixedKey();
      final bytes = await sealWithNonceForTesting(
        doc: _doc,
        listId: _listId,
        fromNode: _node,
        at: _at,
        key: key,
        nonce: List<int>.filled(12, 9),
      );
      final hLen = (bytes[3] << 8) | bytes[4];
      final aadEnd = 5 + hLen;
      final clear = await AesGcm.with256bits().decrypt(
        SecretBox(
          bytes.sublist(aadEnd + 12, bytes.length - 16),
          nonce: bytes.sublist(aadEnd, aadEnd + 12),
          mac: Mac(bytes.sublist(bytes.length - 16)),
        ),
        secretKey: SecretKey(key.bytes),
        aad: bytes.sublist(0, aadEnd),
      );
      final plain = io.ZLibDecoder(raw: true).convert(clear);
      expect(jsonDecode(utf8.decode(plain)), _doc);
    });

    test('no contiene la clave en ninguna forma', () async {
      final key = await FamilyKey.generate();
      final bytes = await _seal(key: key);
      final link = envelopeToLink(bytes);
      expect(_contains(bytes, key.bytes), isFalse);
      expect(_contains(bytes, utf8.encode(key.toBase64Url())), isFalse);
      expect(_contains(bytes, utf8.encode(base64.encode(key.bytes))), isFalse);
      expect(encodeBase64Url(bytes), isNot(contains(key.toBase64Url())));
      expect(link, isNot(contains(key.toBase64Url())));
      expect(link, startsWith('https://$kShareHost/s#'));
    });

    test('peekHeader lee la lista sin clave', () async {
      final h = peekHeader(await _seal());
      expect(h.listId, _listId);
      expect(h.fromNode, _node);
      expect(h.at, _at);
    });

    test('cambiar cualquier byte hace fallar open', () async {
      final key = _fixedKey();
      final bytes = await _seal(key: key, doc: {'a': 1});
      expect(bytes.length, lessThan(300));
      for (var i = 0; i < bytes.length; i++) {
        final copy = Uint8List.fromList(bytes);
        copy[i] ^= 0x01;
        await expectLater(
          open(copy, key: key, expectedListId: _listId),
          throwsA(
            anyOf(isA<EnvelopeAuthException>(), isA<EnvelopeFormatException>()),
          ),
          reason: 'byte $i',
        );
      }
    });

    test('truncar o ampliar el sobre falla', () async {
      final key = _fixedKey();
      final bytes = await _seal(key: key, doc: {'a': 1});
      for (var n = 0; n < bytes.length; n++) {
        await expectLater(
          open(bytes.sublist(0, n), key: key, expectedListId: _listId),
          throwsA(isA<EnvelopeException>()),
          reason: 'longitud $n',
        );
      }
      await expectLater(
        open(
          Uint8List.fromList([...bytes, 0]),
          key: key,
          expectedListId: _listId,
        ),
        throwsA(isA<EnvelopeException>()),
      );
    });

    test('clave equivocada: error de autenticación', () async {
      final bytes = await _seal();
      final other = FamilyKey(List<int>.filled(32, 5));
      await expectLater(
        open(bytes, key: other, expectedListId: _listId),
        throwsA(isA<EnvelopeAuthException>()),
      );
    });

    test('otra lista: error de lista', () async {
      final bytes = await _seal();
      await expectLater(
        open(bytes, key: _fixedKey(), expectedListId: 'otra'),
        throwsA(isA<EnvelopeWrongListException>()),
      );
    });

    test('versión desconocida: error de formato', () async {
      final bytes = await _seal();
      final v2 = Uint8List.fromList(bytes)..[2] = 2;
      await expectLater(
        open(v2, key: _fixedKey(), expectedListId: _listId),
        throwsA(isA<EnvelopeFormatException>()),
      );
      expect(() => peekHeader(v2), throwsA(isA<EnvelopeFormatException>()));
      expect(
        () => peekHeader(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });

    test('sobre de más de 2 MB: error de tamaño', () async {
      final big = Uint8List(kMaxEnvelopeBytes + 1);
      await expectLater(
        open(big, key: _fixedKey(), expectedListId: _listId),
        throwsA(isA<EnvelopeTooLargeException>()),
      );
    });

    test('bomba de compresión: 9 MB de ceros', () async {
      final key = _fixedKey();
      final bomb = Deflate(Uint8List(9 * 1024 * 1024)).getBytes();
      expect(bomb.length, lessThan(100 * 1024));
      final bytes = await _handSeal(bomb, key);
      await expectLater(
        open(bytes, key: key, expectedListId: _listId),
        throwsA(isA<EnvelopeTooLargeException>()),
      );
    });

    test(
      'cuerpo de justo 8 MB se acepta hasta el JSON (no es un objeto)',
      () async {
        final key = _fixedKey();
        final body = Deflate(Uint8List(8 * 1024 * 1024)).getBytes();
        final bytes = await _handSeal(body, key);
        // No es JSON: pasa el límite de tamaño y falla por formato.
        await expectLater(
          open(bytes, key: key, expectedListId: _listId),
          throwsA(isA<EnvelopeFormatException>()),
        );
      },
    );

    test('cuerpo no deflate o truncado: error de formato', () async {
      final key = _fixedKey();
      final trunc = Deflate(utf8.encode(jsonEncode(_doc))).getBytes();
      for (final body in [
        <int>[1, 2, 3, 4, 5],
        trunc.sublist(0, trunc.length ~/ 2),
      ]) {
        await expectLater(
          open(await _handSeal(body, key), key: key, expectedListId: _listId),
          throwsA(isA<EnvelopeFormatException>()),
        );
      }
    });

    test('seal rechaza documentos de más de 8 MB', () async {
      await expectLater(
        _seal(doc: {'x': 'a' * (kMaxPlainBytes + 1)}),
        throwsA(isA<EnvelopeTooLargeException>()),
      );
    });
  });

  group('formas de texto', () {
    test('parseShared acepta enlace, fragmento y base64 suelto', () async {
      final bytes = await _seal();
      final b64 = encodeBase64Url(bytes);
      expect(parseShared(envelopeToLink(bytes)), bytes);
      expect(parseShared('#$b64'), bytes);
      expect(parseShared(b64), bytes);
    });

    test(
      'parseShared con el enlace partido en líneas y con espacios',
      () async {
        final bytes = await _seal();
        final link = envelopeToLink(bytes);
        final cut = link.length ~/ 2;
        final messy =
            '  ${link.substring(0, 20)}\n${link.substring(20, cut)} '
            '\r\n${link.substring(cut)}  \n';
        expect(parseShared(messy), bytes);
      },
    );

    test('parseShared rechaza basura', () {
      for (final bad in [
        '',
        '   ',
        'https://regalos.example/s',
        'a b/c',
        '@@@',
        'a',
      ]) {
        expect(
          () => parseShared(bad),
          throwsA(isA<EnvelopeException>()),
          reason: bad,
        );
      }
    });

    test('envelopeFileName', () {
      expect(
        envelopeFileName(DateTime(2026, 11, 9, 7, 5)),
        'gift-huddle-20261109-0705.gifthuddle',
      );
    });
  });
}
