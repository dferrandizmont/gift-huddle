import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/recovery.dart';
import 'package:regalos/core/sync/recovery_file.dart';

/// ADR 0008: fichero de recuperación GHK v1, contra los vectores normativos
/// generados en Python (tool/recovery_file_vectors.py).
Uint8List hex(String text) => Uint8List.fromList([
  for (var i = 0; i < text.length; i += 2)
    int.parse(text.substring(i, i + 2), radix: 16),
]);

String toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// A 1.0.6 vector (container version 1) as 1.0.7 writes it (version 2): the
/// outer byte and the `v` in the header change; nothing else.
Uint8List upgraded(Uint8List v1) {
  final out = Uint8List.fromList(v1);
  final at = 6 + ((out[4] << 8) | out[5]) - 2;
  expect(out[3], 1);
  expect(out[at], 0x31);
  out[3] = 2;
  out[at] = 0x32;
  return out;
}

Matcher fails(RecoveryFileFailure failure) => throwsA(
  isA<RecoveryFileException>().having((e) => e.failure, 'failure', failure),
);

void main() {
  final vector = jsonDecode(
    File('../docs/adr/0008-vector-fichero.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final entropy = hex(vector['entropyHex'] as String);
  final code = RecoveryCode(entropy);
  final salt = hex(vector['saltHex'] as String);
  final nonce = hex(vector['nonceHex'] as String);
  final open = vector['open'] as Map<String, Object?>;
  final protected = [
    for (final p in vector['protected'] as List) p as Map<String, Object?>,
  ];
  final ascii = protected.firstWhere((p) => p['name'] == 'ascii');
  final nfc = protected.firstWhere((p) => p['name'] == 'nfc');
  String password(Map<String, Object?> p, [String field = 'passwordUtf8Hex']) =>
      utf8.decode(hex(p[field] as String));

  test('the profile constants match the vector', () {
    expect(vector['kdf'], {
      'a': 'argon2id',
      'm': kRecoveryFileKdfMemoryKiB,
      'p': kRecoveryFileKdfParallelism,
      't': kRecoveryFileKdfIterations,
    });
    expect(vector['kdfAssociated'], 'gift-huddle-recovery-file-v1');
  });

  group('open variant', () {
    test('seals the exact bytes and opens them', () {
      final sealed = sealOpenRecoveryFile(code);
      // 1.0.7 writes container version 2 (1.0.6 rejects it as newer).
      expect(
        toHex(sealed.bytes),
        toHex(upgraded(hex(open['fileHex'] as String))),
      );
      expect(sealed.bytes[3], kRecoveryFileVersion);
      expect(kRecoveryFileVersion, isNot(kRecoveryFileVersionLegacy));
      // ... and still reads the 1.0.6 file.
      expect(sealed.variant, RecoveryFileVariant.open);
      final file = parseRecoveryFile(hex(open['fileHex'] as String));
      expect(file.variant, RecoveryFileVariant.open);
      expect(file.needsPassword, isFalse);
      expect(openOpenRecoveryFile(file).entropy, entropy);
    });

    test('reopen of the read back destination gives the same code', () async {
      final sealed = sealOpenRecoveryFile(code);
      expect((await sealed.reopen(sealed.bytes)).entropy, entropy);
    });
  });

  group('protected variant', () {
    test('derives the vector keys (ASCII and NFC)', () async {
      for (final p in [ascii, nfc]) {
        final key = await deriveRecoveryFileKey(password(p), salt);
        expect(toHex(key), p['keyHex'], reason: p['name'] as String);
      }
    });

    test('seals the exact bytes and opens them with the key', () async {
      for (final p in [ascii, nfc]) {
        final sealed = await sealProtectedRecoveryFileForTesting(
          code,
          password(p),
          salt: salt,
          nonce: nonce,
        );
        // The version is part of the AAD, so the tag differs from the v1
        // vector: header and ciphertext are checked by opening below.
        expect(sealed.bytes[3], kRecoveryFileVersion);
        expect(
          toHex(sealed.bytes.sublist(0, (p['aadHex'] as String).length ~/ 2)),
          toHex(upgraded(hex(p['aadHex'] as String))),
        );
        final written = parseRecoveryFile(sealed.bytes);
        expect(
          (await openRecoveryFileWithKey(
            written,
            hex(p['keyHex'] as String),
          )).entropy,
          entropy,
        );
        final file = parseRecoveryFile(hex(p['fileHex'] as String));
        expect(file.needsPassword, isTrue);
        expect(recoveryFileSalt(file), salt);
        final opened = await openRecoveryFileWithKey(
          file,
          hex(p['keyHex'] as String),
        );
        expect(opened.entropy, entropy);
        // The destination is reopened with the same key, no second Argon2.
        expect((await sealed.reopen(sealed.bytes)).entropy, entropy);
      }
    });

    test('opens with its password (derivation included)', () async {
      final file = parseRecoveryFile(hex(ascii['fileHex'] as String));
      final opened = await openProtectedRecoveryFile(file, password(ascii));
      expect(opened.entropy, entropy);
    });

    test('the NFD spelling is different bytes in the core', () {
      // NFC is the platform's job (application layer tests cover it).
      expect(password(nfc, 'passwordNfdUtf8Hex'), isNot(password(nfc)));
    });

    test('fresh salt and nonce on each seal', () async {
      final a = await sealProtectedRecoveryFile(code, password(ascii));
      final b = await sealProtectedRecoveryFile(code, password(ascii));
      expect(a.bytes, isNot(b.bytes));
      expect((await a.reopen(a.bytes)).entropy, entropy);
      await expectLater(
        a.reopen(b.bytes),
        fails(RecoveryFileFailure.damagedOrWrongPassword),
      );
    });

    test('reopen rejects a destination of the other variant', () async {
      final sealed = sealOpenRecoveryFile(code);
      await expectLater(
        sealed.reopen(hex(ascii['fileHex'] as String)),
        fails(RecoveryFileFailure.notRecoveryFile),
      );
    });
  });

  test('version 3 is newer: rejected before anything else', () {
    final bytes = Uint8List.fromList(sealOpenRecoveryFile(code).bytes)..[3] = 3;
    expect(
      () => parseRecoveryFile(bytes),
      fails(RecoveryFileFailure.newerVersion),
    );
  });

  group('negatives', () {
    final negatives = [
      for (final n in vector['negatives'] as List) n as Map<String, Object?>,
    ];
    final asciiKey = hex(ascii['keyHex'] as String);

    for (final n in negatives) {
      final name = n['name'] as String;
      final bytes = hex(n['fileHex'] as String);
      // 1.0.7 reads container version 2: the old "version-2" vector keeps
      // `v: 1` in its header, so it is now a mismatch, not a newer version
      // (the newer-version case is `version 3` below).
      final expected = name == 'version-2'
          ? RecoveryFileFailure.notRecoveryFile
          : RecoveryFileFailure.values.byName(n['expect'] as String);
      test(name, () async {
        if (expected != RecoveryFileFailure.damagedOrWrongPassword) {
          expect(() => parseRecoveryFile(bytes), fails(expected));
          if (name.startsWith('open-')) {
            // The open checksum is validated on open, still before anything.
            expect(
              () => openOpenRecoveryFile(parseRecoveryFile(bytes)),
              fails(expected),
            );
          }
          return;
        }
        final file = parseRecoveryFile(bytes);
        if (name == 'wrong-password') {
          await expectLater(
            openProtectedRecoveryFile(file, password(n)),
            fails(expected),
          );
        } else {
          // Tampering fails the GCM even with the original key.
          await expectLater(
            openRecoveryFileWithKey(file, asciiKey),
            fails(expected),
          );
        }
      });
    }

    test('every open-variant negative fails before anything else', () {
      for (final n in negatives.where(
        (n) => (n['name'] as String).startsWith('open-'),
      )) {
        final bytes = hex(n['fileHex'] as String);
        expect(() {
          final file = parseRecoveryFile(bytes);
          openOpenRecoveryFile(file);
        }, fails(RecoveryFileFailure.notRecoveryFile));
      }
    });
  });

  group('isRecoveryFile', () {
    test('detects by magic only', () {
      expect(isRecoveryFile(hex(open['fileHex'] as String)), isTrue);
      expect(isRecoveryFile(hex(ascii['fileHex'] as String)), isTrue);
      expect(isRecoveryFile([0x47, 0x48, 0x4B, 0x02]), isTrue);
      expect(isRecoveryFile([0x47, 0x48, 0x52, 0x01]), isFalse); // GHR
      expect(isRecoveryFile(utf8.encode('RG')), isFalse);
      expect(isRecoveryFile(const []), isFalse);
      expect(isRecoveryFile([0x47, 0x48]), isFalse);
    });

    test('a file past 512 bytes is never parsed', () {
      final big = Uint8List(kRecoveryFileMaxBytes + 1)
        ..setAll(0, [0x47, 0x48, 0x4B, 0x01]);
      expect(
        () => parseRecoveryFile(big),
        fails(RecoveryFileFailure.notRecoveryFile),
      );
    });

    test('parsing works on its own copy', () async {
      final bytes = hex(ascii['fileHex'] as String);
      final file = parseRecoveryFile(bytes);
      bytes[bytes.length - 1] ^= 1;
      expect(
        (await openRecoveryFileWithKey(
          file,
          hex(ascii['keyHex'] as String),
        )).entropy,
        entropy,
      );
    });
  });

  group('checkRecoveryPassword', () {
    RecoveryPasswordProblem? check(String p) => checkRecoveryPassword(p);

    test('accepts long passphrases of random words', () {
      expect(check('marmota violeta despega cada lunes'), isNull);
      expect(check('cañón azul sobre árbol nevado'), isNull);
      expect(check('tren gato lluvia azul'), isNull);
      expect(check('Xq7!mPz2#rL9vB4w'), isNull);
      expect(check('Λόγος καλός ημέρα'), isNull);
    });

    test('length counts runes after NFC, 15 to 128', () {
      expect(check('tren gato azul'), RecoveryPasswordProblem.tooShort);
      expect(check('ñandú perezoso'), RecoveryPasswordProblem.tooShort);
      expect(check('ñandú perezoso!'), isNull);
      expect(
        check('🎁🎁🎁🎁🎁🎁🎁🎁🎁🎁🎁🎁🎁🎁'),
        RecoveryPasswordProblem.tooShort,
      );
      final long = List.filled(13, 'tren gato ').join(); // 130 runes
      expect(check(long), RecoveryPasswordProblem.tooLong);
      expect(
        check(long.substring(0, 128)),
        isNot(RecoveryPasswordProblem.tooLong),
      );
    });

    test('rejects repeated characters and blocks', () {
      expect(check('aaaaaaaaaaaaaaaa'), RecoveryPasswordProblem.repeated);
      expect(check('abcabcabcabcabcab'), RecoveryPasswordProblem.repeated);
      expect(check('hola mundo hola mundo'), RecoveryPasswordProblem.repeated);
      expect(check(' ' * 15), RecoveryPasswordProblem.repeated);
      expect(check('\t' * 20), RecoveryPasswordProblem.repeated);
      expect(
        check(' \t \t \t \t \t \t \t \t'),
        RecoveryPasswordProblem.repeated,
      );
      expect(check(' ' * 16), RecoveryPasswordProblem.repeated);
    });

    test('rejects only digits', () {
      expect(check('202612251225 2026'), RecoveryPasswordProblem.onlyDigits);
      expect(check('31-12-2026-25-12-27'), RecoveryPasswordProblem.onlyDigits);
    });

    test('rejects keyboard rows, columns and sequences', () {
      expect(
        check('qwertyuiopasdfghjkl'),
        RecoveryPasswordProblem.keyboardSequence,
      );
      expect(
        check('qwertyuiop12345'),
        RecoveryPasswordProblem.keyboardSequence,
      );
      expect(
        check('1qaz2wsx3edc4rfv'),
        RecoveryPasswordProblem.keyboardSequence,
      );
      expect(
        check('abcdefghijklmnopq'),
        RecoveryPasswordProblem.keyboardSequence,
      );
      expect(
        check('ponmlkjihgfedcba'),
        RecoveryPasswordProblem.keyboardSequence,
      );
      expect(
        check('azertyuiopqsdfghj'),
        RecoveryPasswordProblem.keyboardSequence,
      );
    });

    test('rejects the app name', () {
      expect(
        check('mi lista de Gift Huddle'),
        RecoveryPasswordProblem.containsAppName,
      );
      expect(
        check('GIFTHUDDLE recovery 2026'),
        RecoveryPasswordProblem.containsAppName,
      );
    });

    test('rejects frequent phrases in es, ca and en', () {
      expect(
        check('Correct Horse Battery Staple'),
        RecoveryPasswordProblem.common,
      );
      expect(check('Feliz Navidad 2026 !!'), RecoveryPasswordProblem.common);
      expect(check('felizcumpleaños2026'), RecoveryPasswordProblem.common);
      expect(check('Bon Nadal 1234567'), RecoveryPasswordProblem.common);
      expect(check('Lista de regalos 2026'), RecoveryPasswordProblem.common);
      expect(check('la meva contrasenya'), RecoveryPasswordProblem.common);
    });

    test('the two entries must match', () {
      expect(
        checkNewRecoveryPassword(
          'marmota violeta despega',
          'marmota violeta despega',
        ),
        isNull,
      );
      expect(
        checkNewRecoveryPassword(
          'marmota violeta despega',
          'marmota violeta despegA',
        ),
        RecoveryPasswordProblem.mismatch,
      );
      expect(
        checkNewRecoveryPassword('corta', 'corta'),
        RecoveryPasswordProblem.tooShort,
      );
    });
  });
}
