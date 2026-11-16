import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/protected_doc.dart';
import 'package:regalos/core/sync/protected_envelope.dart';
import 'package:regalos/core/sync/recovery.dart';

import 'protected_harness.dart';

/// Código de recuperación (R-b) y copia exportable (R-c), ADR 0004.
void main() {
  late RecoveryWordlist wordlist;
  setUpAll(() {
    wordlist = RecoveryWordlist.parse(
      File(kRecoveryWordlistAsset).readAsStringSync(),
    );
  });

  // Parámetros pequeños para que las pruebas vayan rápido; los de verdad
  // se comprueban aparte.
  const fast = RecoveryKdfParams(memoryKiB: 64, iterations: 1, parallelism: 1);

  group('lista de palabras', () {
    test('es la inglesa de BIP-39', () {
      expect(wordlist.words, hasLength(2048));
      expect(wordlist.words.first, 'abandon');
      expect(wordlist.words.last, 'zoo');
    });

    test('una lista cambiada no se acepta', () {
      final text = File(kRecoveryWordlistAsset).readAsStringSync();
      expect(
        () => RecoveryWordlist.parse(text.replaceFirst('zoo', 'zoom')),
        throwsA(isA<RecoveryException>()),
      );
    });
  });

  group('código', () {
    // Vectores de BIP-39 (trezor/python-mnemonic, vectors.json) con 256 bits.
    final vectors = <String, String>{
      '00' * 32: '${'abandon ' * 23}art',
      '7f' * 32:
          'legal winner thank year wave sausage worth useful legal winner '
          'thank year wave sausage worth useful legal winner thank year wave '
          'sausage worth title',
      '80' * 32:
          'letter advice cage absurd amount doctor acoustic avoid letter '
          'advice cage absurd amount doctor acoustic avoid letter advice cage '
          'absurd amount doctor acoustic bless',
      'ff' * 32: '${'zoo ' * 23}vote',
    };

    test('vectores fijos de BIP-39', () {
      vectors.forEach((hex, words) {
        final code = RecoveryCode(_hex(hex));
        expect(code.toWords(wordlist).join(' '), words);
        expect(RecoveryCode.fromWords(words, wordlist).entropy, _hex(hex));
      });
    });

    test('ida y vuelta por palabras y por QR', () {
      for (var i = 0; i < 20; i++) {
        final code = RecoveryCode.generate();
        final words = code.toWords(wordlist);
        expect(words, hasLength(24));
        expect(
          RecoveryCode.fromWords(words.join(' '), wordlist).entropy,
          code.entropy,
        );
        expect(RecoveryCode.fromQrText(code.toQrText()).entropy, code.entropy);
      }
    });

    test('acepta mayúsculas, saltos de línea y las cuatro primeras letras', () {
      final code = RecoveryCode(_hex('80' * 32));
      final words = code.toWords(wordlist);
      final typed = [
        for (var i = 0; i < words.length; i++)
          i.isEven ? words[i].toUpperCase() : words[i].substring(0, 4),
      ].join('\n  ');
      expect(RecoveryCode.fromWords(typed, wordlist).entropy, code.entropy);
    });

    test('palabra equivocada, que falta o que sobra: rechazado', () {
      final words = RecoveryCode(_hex('7f' * 32)).toWords(wordlist);
      // Una palabra que no está en la lista.
      final unknown = [...words]..[3] = 'zzzz';
      // Una palabra de la lista, pero otra: la suma de control no cuadra.
      final wrong = [...words]..[0] = 'letter';
      // Un prefijo que no es de ninguna palabra.
      final typo = [...words]..[5] = 'wavx';
      for (final bad in [
        unknown.join(' '),
        wrong.join(' '),
        typo.join(' '),
        words.sublist(1).join(' '),
        [...words, 'abandon'].join(' '),
      ]) {
        expect(
          () => RecoveryCode.fromWords(bad, wordlist),
          throwsA(isA<RecoveryException>()),
          reason: bad,
        );
      }
    });

    test('QR dañado: rechazado', () {
      final text = RecoveryCode.generate().toQrText();
      final flipped =
          text.substring(0, text.length - 3) +
          (text[text.length - 3] == 'A' ? 'B' : 'A') +
          text.substring(text.length - 2);
      for (final bad in [flipped, 'gift-huddle-recovery:v1:', 'hola']) {
        expect(
          () => RecoveryCode.fromQrText(bad),
          throwsA(isA<RecoveryException>()),
        );
      }
    });

    test('nunca aparece en toString', () {
      final code = RecoveryCode(_hex('00' * 32));
      expect(code.toString(), isNot(contains('abandon')));
      expect(code.toString(), isNot(contains('AAAA')));
    });
  });

  group('derivación', () {
    test('Argon2id cumple el vector de RFC 9106', () async {
      final key =
          await const DartArgon2id(
            parallelism: 4,
            memory: 32,
            iterations: 3,
            hashLength: 32,
          ).deriveKey(
            secretKey: SecretKey(List<int>.filled(32, 1)),
            nonce: List<int>.filled(16, 2),
            optionalSecret: List<int>.filled(8, 3),
            associatedData: List<int>.filled(12, 4),
          );
      expect(
        _toHex(await key.extractBytes()),
        '0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659',
      );
    });

    test(
      'topes del KDF: más de 64 MiB, 4 pasadas o 4 hilos se rechaza (B3)',
      () async {
        for (final params in const [
          RecoveryKdfParams(memoryKiB: 65537, iterations: 2, parallelism: 1),
          RecoveryKdfParams(memoryKiB: 19456, iterations: 5, parallelism: 1),
          RecoveryKdfParams(memoryKiB: 19456, iterations: 2, parallelism: 5),
        ]) {
          await expectLater(
            deriveRecoveryKey(
              RecoveryCode.generate(),
              List.filled(16, 1),
              params,
            ),
            throwsA(isA<RecoveryException>()),
          );
        }
        // En el tope justo, sí.
        expect(
          await deriveRecoveryKey(
            RecoveryCode(_hex('00' * 32)),
            List<int>.filled(16, 1),
            const RecoveryKdfParams(
              memoryKiB: 64,
              iterations: 4,
              parallelism: 4,
            ),
          ),
          hasLength(32),
        );
      },
    );

    test('los parámetros de verdad: 19 MiB, 2 pasadas, 1 hilo', () async {
      expect(RecoveryKdfParams.standard.memoryKiB, 19456);
      expect(RecoveryKdfParams.standard.iterations, 2);
      expect(RecoveryKdfParams.standard.parallelism, 1);
      final watch = Stopwatch()..start();
      final key = await deriveRecoveryKey(
        RecoveryCode(_hex('00' * 32)),
        List<int>.filled(16, 1),
        RecoveryKdfParams.standard,
      );
      expect(key, hasLength(32));
      // En un PC tarda unas décimas; el tope es solo para notar un error.
      expect(watch.elapsed, lessThan(const Duration(seconds: 20)));
    });

    test('vector fijo de la clave', () async {
      final key = await deriveRecoveryKey(
        RecoveryCode(List<int>.generate(32, (i) => i)),
        List<int>.filled(16, 0xAA),
        fast,
      );
      expect(_toHex(key), _keyVector);
    });
  });

  group('copia cifrada', () {
    late Family family;
    late FamilyKey familyKey;
    setUp(() async {
      family = await Family.create();
      familyKey = FamilyKey(List<int>.filled(32, 0x11));
    });

    RecoveryPayload keysOf(Phone phone, SurpriseKeyring keyring) =>
        RecoveryPayload(
          kind: RecoveryKind.keys,
          listId: kListId,
          familyKey: familyKey,
          deviceId: phone.id,
          selfRecipientId: phone.self,
          deviceKeys: phone.keys,
          surpriseKeys: keyring,
        );

    test('R-b: ida y vuelta de las claves', () async {
      final code = RecoveryCode.generate();
      final bytes = await sealRecovery(
        keysOf(family.aritz, family.authorizedKeyring),
        code,
        params: fast,
      );
      expect(peekRecoveryKind(bytes), RecoveryKind.keys);
      final back = await openRecovery(bytes, code);
      expect(back.familyKey, familyKey);
      expect(back.deviceId, 'aritz-phone');
      expect(back.selfRecipientId, 'aritz');
      expect(
        back.deviceKeys.publicKeys.signing,
        family.aritz.keys.publicKeys.signing,
      );
      expect(back.surpriseKeys.latestFor('nora')!.bytes, family.key.bytes);
    });

    test('R-c: la copia completa abre las sorpresas en otro móvil', () async {
      final scope = scopeWith(clockOf('aritz-phone', 1000), ['Microscopio']);
      final slot = await SealedSlot.seal(
        writerKeys: family.aritz.keys,
        writer: family.aritz.id,
        revision: 1,
        key: family.key,
        policy: const PolicyState(hideOwnGifts: true, rev: 1),
        doc: scope,
      );
      final common = commonWithPeople(clockOf('aritz-phone', 100));
      final code = RecoveryCode.generate();
      final bytes = await sealRecovery(
        RecoveryPayload(
          kind: RecoveryKind.backup,
          listId: kListId,
          familyKey: familyKey,
          deviceId: family.aritz.id,
          selfRecipientId: 'aritz',
          deviceKeys: family.aritz.keys,
          surpriseKeys: family.authorizedKeyring,
          common: common,
          slots: [slot],
        ),
        code,
        params: fast,
      );
      expect(peekRecoveryKind(bytes), RecoveryKind.backup);
      expect(String.fromCharCodes(bytes), isNot(contains('Microscopio')));
      expect(String.fromCharCodes(bytes), isNot(contains('Aritz')));
      final back = await openRecovery(bytes, code);
      expect(back.common!.canonicalJson(), common.canonicalJson());
      final opened = await openScope(
        personId: 'nora',
        slots: await family.setOf(back.slots!),
        keyring: back.surpriseKeys,
        view: family.view,
      );
      expect(
        opened!.doc.record(Collections.gifts, 's0')!['title'],
        'Microscopio',
      );
    });

    test('la copia de Nora no lleva su clave ni abre sus sorpresas', () async {
      final scope = scopeWith(clockOf('aritz-phone', 1000), ['Microscopio']);
      final slot = await SealedSlot.seal(
        writerKeys: family.aritz.keys,
        writer: family.aritz.id,
        revision: 1,
        key: family.key,
        policy: const PolicyState(hideOwnGifts: true, rev: 1),
        doc: scope,
      );
      final code = RecoveryCode.generate();
      // Aunque por error tuviera la clave, al sellar se quita.
      final bytes = await sealRecovery(
        RecoveryPayload(
          kind: RecoveryKind.backup,
          listId: kListId,
          familyKey: familyKey,
          deviceId: family.nora.id,
          selfRecipientId: 'nora',
          deviceKeys: family.nora.keys,
          surpriseKeys: family.authorizedKeyring,
          common: FamilyDoc.empty(kListId),
          slots: [slot],
        ),
        code,
        params: fast,
      );
      final back = await openRecovery(bytes, code);
      expect(back.surpriseKeys.people, isEmpty);
      expect(
        await openScope(
          personId: 'nora',
          slots: await family.setOf(back.slots!),
          keyring: back.surpriseKeys,
          view: family.viewOf(family.nora),
        ),
        isNull,
      );
      // Ni con la familyKey ni con las claves de su móvil de la copia.
      for (final candidate in [
        back.familyKey.bytes,
        back.deviceKeys.serviceCredential,
      ]) {
        await expectLater(
          back.slots!.single.open(
            expectedListId: kListId,
            key: SurpriseKey(personId: 'nora', epoch: 1, bytes: candidate),
            signingKey: family.aritz.keys.publicKeys.signing,
          ),
          throwsA(isA<ProtectedEnvelopeException>()),
        );
      }
    });

    test(
      'otro código, palabra equivocada o copia manipulada: rechazado',
      () async {
        final code = RecoveryCode(_hex('7f' * 32));
        final bytes = await sealRecovery(
          keysOf(family.leo, family.authorizedKeyring),
          code,
          params: fast,
        );
        // Otro código válido (suma de control correcta) no abre.
        await expectLater(
          openRecovery(bytes, RecoveryCode(_hex('80' * 32))),
          throwsA(isA<RecoveryException>()),
        );
        for (final offset in [0, 3, 10, bytes.length - 20, bytes.length - 1]) {
          final tampered = Uint8List.fromList(bytes)..[offset] ^= 0x04;
          await expectLater(
            openRecovery(tampered, code),
            throwsA(isA<RecoveryException>()),
            reason: 'byte $offset',
          );
        }
        // Un sobre normal de Regalos no es una copia.
        final envelope = await seal(
          doc: FamilyDoc.empty(kListId).toJson(),
          listId: kListId,
          fromNode: 'aritz-phone',
          at: '',
          key: familyKey,
        );
        await expectLater(
          openRecovery(envelope, code),
          throwsA(isA<RecoveryException>()),
        );
      },
    );

    test(
      'una copia con parámetros desmesurados se rechaza sin derivar',
      () async {
        final code = RecoveryCode(_hex('7f' * 32));
        final bytes = await sealRecovery(
          keysOf(family.leo, SurpriseKeyring.empty),
          code,
          params: fast,
        );
        final length = (bytes[4] << 8) | bytes[5];
        final header = String.fromCharCodes(bytes.sublist(6, 6 + length))
            .replaceFirst('"m":64', '"m":99999999');
        final evil = Uint8List.fromList([
          ...bytes.sublist(0, 4),
          header.length >> 8,
          header.length & 0xFF,
          ...header.codeUnits,
          ...bytes.sublist(6 + length),
        ]);
        // Los parámetros se salen del rango: error sin intentar derivar.
        await expectLater(
          openRecovery(evil, code),
          throwsA(isA<RecoveryException>()),
        );
      },
    );

    test('vector fijo de la copia', () async {
      final bytes = await sealRecoveryForTesting(
        keysOf(family.aritz, family.authorizedKeyring),
        RecoveryCode(List<int>.generate(32, (i) => i)),
        params: fast,
        salt: List<int>.filled(16, 0xAA),
        nonce: List<int>.filled(12, 0xBB),
      );
      final digest = const DartSha256().hashSync(bytes).bytes;
      expect(_toHex(digest), _backupVector);
      final back = await openRecovery(
        bytes,
        RecoveryCode(List<int>.generate(32, (i) => i)),
      );
      expect(back.deviceId, 'aritz-phone');
    });

    test('nombre del fichero', () {
      expect(
        recoveryFileName(DateTime(2026, 11, 12, 9, 5)),
        'gift-huddle-copia-20261112-0905.gifthuddle',
      );
    });
  });
}

// Argon2id (64 KiB, 1 pasada, 1 hilo) del código 00..1f con sal aa..aa.
const _keyVector =
    '8af2581604c1f0051cb45a80b642f764b15ab66f29be22788baadbfb7af1ca49';

// SHA-256 de la copia de claves de Aritz con sal aa..aa y nonce bb..bb
// (el llavero lleva la audiencia de cada clave desde la revisión de la fase
// 2a, hallazgo 7).
const _backupVector =
    'deefe8b15229c6b13d45378cbf9e89fd58873d8785cb2f64b6c2efdb21c12b2d';

Uint8List _hex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

String _toHex(List<int> bytes) =>
    [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();
