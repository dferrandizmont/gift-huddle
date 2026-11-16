import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/features/sync/invites/invite_crypto.dart';
import 'package:regalos/features/sync/invites/invite_link.dart';

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List _unhex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);

void main() {
  final vector = jsonDecode(
    File('../docs/adr/0002-vector-invitacion.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final input = vector['entrada']! as Map<String, Object?>;
  final output = vector['salida']! as Map<String, Object?>;
  final inviteId = input['inviteId']! as String;
  final nonce = _unhex(input['nonce']! as String);

  Future<(InviteKeyPair, InviteKeyPair)> pairs() async => (
    await InviteCrypto.generateKeyPair(seed: _unhex(input['seedA']! as String)),
    await InviteCrypto.generateKeyPair(seed: _unhex(input['seedB']! as String)),
  );

  group(
    'vector fijo de ADR 0002 (calculado con Python, no con este código)',
    () {
      test('claves públicas, secreto compartido y clave del paquete', () async {
        final (a, b) = await pairs();
        expect(_hex(a.publicKey), output['publicKeyA']);
        expect(_hex(b.publicKey), output['publicKeyB']);
        expect(
          _hex(await InviteCrypto.sharedSecretForTesting(a, b.publicKey)),
          output['sharedSecret'],
        );
        expect(
          _hex(await InviteCrypto.sharedSecretForTesting(b, a.publicKey)),
          output['sharedSecret'],
        );
        expect(
          _hex(await InviteCrypto.packageKeyForTesting(a, b.publicKey)),
          output['packageKey'],
        );
      });

      test(
        'código de verificación de 6 cifras (con cero a la izquierda)',
        () async {
          final (a, b) = await pairs();
          final code = await InviteCrypto.verificationCode(
            a.publicKey,
            b.publicKey,
          );
          expect(code, output['verificationCode']);
          expect(code, '030367');
          expect(InviteCrypto.formatCode(code), '030 367');
        },
      );

      test('el paquete cifrado sale idéntico al del vector', () async {
        final (a, b) = await pairs();
        final sealed = await InviteCrypto.sealPackage(
          mine: a,
          theirPublicKey: b.publicKey,
          inviteId: inviteId,
          package: InvitePackage(
            listId: input['listId']! as String,
            familyKey: FamilyKey(_unhex(input['familyKey']! as String)),
            deviceName: input['deviceNameA']! as String,
          ),
          nonce: nonce,
        );
        expect(_hex(sealed.ciphertext), output['ciphertext']);
        expect(_hex(sealed.nonce), input['nonce']);
      });

      test('B abre el paquete del vector', () async {
        final (a, b) = await pairs();
        final pkg = await InviteCrypto.openPackage(
          mine: b,
          theirPublicKey: a.publicKey,
          inviteId: inviteId,
          ciphertext: _unhex(output['ciphertext']! as String),
          nonce: nonce,
        );
        expect(pkg.listId, input['listId']);
        expect(_hex(pkg.familyKey.bytes), input['familyKey']);
        expect(pkg.deviceName, input['deviceNameA']);
      });
    },
  );

  group('código de verificación', () {
    test('es el mismo en los dos móviles y cambia si cambia cualquiera de las claves', () async {
      final a = await InviteCrypto.generateKeyPair();
      final b = await InviteCrypto.generateKeyPair();
      final evil = await InviteCrypto.generateKeyPair();
      final code = await InviteCrypto.verificationCode(
        a.publicKey,
        b.publicKey,
      );
      expect(code, matches(RegExp(r'^\d{6}$')));
      expect(
        await InviteCrypto.verificationCode(a.publicKey, b.publicKey),
        code,
      );
      // Si el servidor cambia la clave de A o la de B, el código de los dos
      // móviles ya no coincide.
      expect(
        await InviteCrypto.verificationCode(evil.publicKey, b.publicKey),
        isNot(code),
      );
      expect(
        await InviteCrypto.verificationCode(a.publicKey, evil.publicKey),
        isNot(code),
      );
    });

    test('rechaza claves que no miden 32 bytes', () async {
      final a = await InviteCrypto.generateKeyPair();
      expect(
        () => InviteCrypto.verificationCode(a.publicKey, [1, 2, 3]),
        throwsA(isA<InviteCryptoException>()),
      );
    });
  });

  group('paquete cifrado', () {
    test('no se abre con otra invitación, otra clave de A o de B', () async {
      final (a, b) = await pairs();
      final evil = await InviteCrypto.generateKeyPair();
      final ct = _unhex(output['ciphertext']! as String);
      Future<void> open({
        required InviteKeyPair mine,
        required List<int> their,
        String id = '',
        List<int>? text,
      }) => InviteCrypto.openPackage(
        mine: mine,
        theirPublicKey: their,
        inviteId: id.isEmpty ? inviteId : id,
        ciphertext: text ?? ct,
        nonce: nonce,
      );
      await open(mine: b, their: a.publicKey); // control: abre
      await expectLater(
        open(mine: b, their: a.publicKey, id: 'otra-invitacion-xxxxx'),
        throwsA(isA<InviteCryptoException>()),
      );
      await expectLater(
        open(mine: b, their: evil.publicKey),
        throwsA(isA<InviteCryptoException>()),
      );
      await expectLater(
        open(mine: evil, their: a.publicKey),
        throwsA(isA<InviteCryptoException>()),
      );
      final flipped = Uint8List.fromList(ct)..[3] ^= 1;
      await expectLater(
        open(mine: b, their: a.publicKey, text: flipped),
        throwsA(isA<InviteCryptoException>()),
      );
      await expectLater(
        open(mine: b, their: a.publicKey, text: ct.sublist(0, 10)),
        throwsA(isA<InviteCryptoException>()),
      );
    });

    test(
      'una clave de orden bajo (secreto de ceros) se rechaza en los dos lados',
      () async {
        final (a, _) = await pairs();
        final zeros = Uint8List(32);
        await expectLater(
          InviteCrypto.checkPeer(a, zeros),
          throwsA(isA<InviteCryptoException>()),
        );
        await expectLater(
          InviteCrypto.sealPackage(
            mine: a,
            theirPublicKey: zeros,
            inviteId: inviteId,
            package: InvitePackage(
              listId: 'l',
              familyKey: FamilyKey(Uint8List(32)),
              deviceName: 'x',
            ),
          ),
          throwsA(isA<InviteCryptoException>()),
        );
        await expectLater(
          InviteCrypto.openPackage(
            mine: a,
            theirPublicKey: zeros,
            inviteId: inviteId,
            ciphertext: _unhex(output['ciphertext']! as String),
            nonce: nonce,
          ),
          throwsA(isA<InviteCryptoException>()),
        );
      },
    );
  });

  group('nombre de móvil que viene de otro móvil', () {
    test('quita controles, bidi y ancho cero', () {
      expect(cleanDeviceName('\u202EMarta\u202C'), 'Marta');
      expect(cleanDeviceName('Ma\u200Brta\u200D\uFEFF'), 'Marta');
      expect(cleanDeviceName('\u2066Marta\u2069\u200E\u200F'), 'Marta');
      expect(cleanDeviceName('Mar\u0000ta\n\t'), 'Marta');
      expect(cleanDeviceName('Mar\u2028ta\u2029'), 'Marta');
      expect(cleanDeviceName('   '), '');
    });

    test('recorta a 40 caracteres', () {
      expect(cleanDeviceName('x' * 100).length, 40);
    });

    test('el paquete y la petición lo limpian', () {
      expect(
        InvitePackage(
          listId: 'l',
          familyKey: FamilyKey(Uint8List(32)),
          deviceName: '\u202Eevil',
        ).deviceName,
        'evil',
      );
    });
  });

  group('enlace de invitación', () {
    const id = 'oKGio6SlpqeoqaqrrK2urw';

    test('enlace completo, con espacios, con texto alrededor e id suelto', () {
      expect(parseInvite('https://sync.test/i#$id'), id);
      expect(parseInvite('  https://sync.test/i#$id \n'), id);
      expect(parseInvite('https://sync.test/i#oKGio6Slpq\n eoqaqrrK2urw'), id);
      expect(parseInvite('https://sync.test/ i# oKGio6SlpqeoqaqrrK 2urw'), id);
      expect(parseInvite('Te invito: https://sync.test/i#$id gracias'), id);
      expect(parseInvite(id), id);
      expect(parseInvite('  $id  '), id);
    });

    test('con host esperado solo vale ese servidor', () {
      expect(
        parseInvite('https://sync.test/i#$id', expectedHost: 'Sync.Test'),
        id,
      );
      expect(
        () => parseInvite('https://evil.test/i#$id', expectedHost: 'sync.test'),
        throwsA(isA<InviteFormatException>()),
      );
    });

    test('rechaza lo que no es una invitación', () {
      for (final bad in [
        '',
        '   ',
        'hola',
        'https://sync.test/s#$id',
        'https://sync.test/i#corto',
        'regalos-pair:v1:abc',
      ]) {
        expect(
          () => parseInvite(bad),
          throwsA(isA<InviteFormatException>()),
          reason: bad,
        );
      }
    });

    test(
      'only the current invitation host works for pasted links and App Links',
      () {
        for (final host in ['gifthuddle.app', 'GiftHuddle.App']) {
          final link = 'https://$host/i#$id';
          expect(
            parseInvite('Te invito: $link', expectedHost: 'gifthuddle.app'),
            id,
          );
          expect(inviteIdFromUri(link, 'gifthuddle.app'), id);
        }
        for (final host in [
          'gifthuddle.app.example.com',
          'xgifthuddle.app',
          'gifthuddle.app:443',
          'gifthuddle.app:8443',
          'usuario@gifthuddle.app',
          'gifthuddle.app@example.com',
          'gifthuddle.retired.example',
          'GiftHuddle.retired.example',
          'gifthuddle.retired.example:443',
          'gifthuddle.retired.example:8443',
          'usuario@gifthuddle.retired.example',
        ]) {
          final link = 'https://$host/i#$id';
          expect(
            () => parseInvite(link, expectedHost: 'gifthuddle.app'),
            throwsA(isA<InviteFormatException>()),
            reason: link,
          );
          expect(inviteIdFromUri(link, 'gifthuddle.app'), isNull, reason: link);
        }
        for (final link in [
          'http://gifthuddle.app/i#$id',
          'http://gifthuddle.retired.example/i#$id',
          'https://gifthuddle.app/i?x=1#$id',
        ]) {
          expect(
            () => parseInvite(link, expectedHost: 'gifthuddle.app'),
            throwsA(isA<InviteFormatException>()),
            reason: link,
          );
          expect(inviteIdFromUri(link, 'gifthuddle.app'), isNull, reason: link);
        }
        // Custom development origins require an exact host match too.
        expect(
          inviteIdFromUri('https://gifthuddle.app/i#$id', 'sync.test'),
          isNull,
        );
      },
    );

    test('inviteLink e inviteIdFromUri son inversos y miran el host', () {
      expect(inviteLink('sync.test', id), 'https://sync.test/i#$id');
      expect(inviteIdFromUri('https://sync.test/i#$id', 'sync.test'), id);
      expect(inviteIdFromUri('https://otro.test/i#$id', 'sync.test'), isNull);
      expect(inviteIdFromUri('http://sync.test/i#$id', 'sync.test'), isNull);
      expect(inviteIdFromUri('https://sync.test/s#$id', 'sync.test'), isNull);
      expect(inviteIdFromUri('https://sync.test/i#x', 'sync.test'), isNull);
    });
  });
}
