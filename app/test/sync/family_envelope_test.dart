// Sobre común firmado (ADR 0005, lote B1, con los arreglos de la revisión
// de la revisión de seguridad): ida y vuelta con lápidas y campos desconocidos; cada campo de
// la cabecera con su error concreto, también firmado de nuevo para llegar al
// GCM; cabeceras no canónicas; escritor (clave, audiencia, revocado); clave
// derivada con HKDF; límites y bomba de compresión.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/device_keys.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_candidate.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/family_envelope.dart';
import 'package:regalos/core/sync/model.dart';

import 'family_key_harness.dart';
import 'protected_harness.dart';

Matcher _fails<T extends EnvelopeException>(String message) =>
    throwsA(isA<T>().having((e) => e.message, 'message', message));

void main() {
  late Family family;
  late FamilyCandidate candidate;
  late FamilyKeyring ring;
  late FamilyDoc doc;
  late KnownDevice aritz;

  setUp(() async {
    family = await Family.create();
    candidate = await candidateFor(family, family.view);
    ring = FamilyKeyring.empty.withOwnCandidate(candidate);
    aritz = family.view.member('aritz-phone')!;
    final clock = clockOf('aritz-phone', 1);
    doc = commonWithPeople(clock)
        .set(clock, Collections.gifts, 'g1', giftFields('leo', 'Cometa'))
        .set(clock, Collections.gifts, 'g2', giftFields('nora', 'Libro'))
        .delete(clock, Collections.gifts, 'g2')
        // Una colección y un campo que esta versión no conoce.
        .set(clock, 'futuro', 'x1', {
          'loQueSea': 3,
          'anidado': [1, 2],
        });
  });

  Future<List<int>?> resolver(String writer, String record) async {
    final known = family.view.member(writer);
    return known != null && known.recordDigest == record
        ? known.signingKey
        : null;
  }

  Future<Uint8List> sealAs({
    FamilyDoc? body,
    FamilyCandidate? key,
    int revision = 5,
    List<int>? nonce,
    List<int>? rawBody,
    String writer = 'aritz-phone',
    String? writerRecord,
    DeviceKeys? signer,
  }) => sealFamilyEnvelopeForTesting(
    doc: body ?? doc,
    candidate: key ?? candidate,
    writer: writer,
    writerRecord: writerRecord ?? family.view.member(writer)!.recordDigest,
    revision: revision,
    signer: signer ?? family.aritz.keys,
    nonce: nonce ?? List<int>.filled(12, 3),
    bodyForTesting: rawBody,
  );

  Future<OpenedFamilyEnvelope> openIt(
    Uint8List bytes, {
    FamilyKeyring? keyring,
    FamilyWriterResolver? resolve,
    String listId = kListId,
    String syncId = kSync,
  }) => openFamilyEnvelope(
    bytes,
    expectedListId: listId,
    expectedSyncId: syncId,
    resolveWriter: resolve ?? resolver,
    keyring: keyring ?? ring,
  );

  int headerLength(Uint8List bytes) => (bytes[3] << 8) | bytes[4];

  /// Rehace el sobre con otra cabecera en bruto, conservando nonce, cifrado
  /// y firma; con [resignWith], firma de nuevo (sin tocar el GCM).
  Future<Uint8List> withRawHeader(
    Uint8List bytes,
    List<int> header, {
    DeviceKeys? resignWith,
  }) async {
    final hLen = headerLength(bytes);
    final unsigned = [
      bytes[0],
      bytes[1],
      bytes[2],
      header.length >> 8,
      header.length & 0xFF,
      ...header,
      ...bytes.sublist(5 + hLen, bytes.length - 64),
    ];
    final signature = resignWith == null
        ? bytes.sublist(bytes.length - 64)
        : await resignWith.sign(familyEnvelopeSignedMessage(unsigned));
    return Uint8List.fromList([...unsigned, ...signature]);
  }

  Future<Uint8List> withHeader(
    Uint8List bytes,
    Map<String, Object?> Function(Map<String, Object?> h) change, {
    DeviceKeys? resignWith,
  }) {
    final hLen = headerLength(bytes);
    final header = jsonDecode(
      utf8.decode(bytes.sublist(5, 5 + hLen)),
    ) as Map<String, Object?>;
    return withRawHeader(
      bytes,
      canonicalHeaderBytes(change(header)),
      resignWith: resignWith,
    );
  }

  /// Cambia un byte y, con [resignWith], firma de nuevo.
  Future<Uint8List> flip(
    Uint8List bytes,
    int at, {
    DeviceKeys? resignWith,
  }) async {
    final copy = Uint8List.fromList(bytes)..[at] ^= 1;
    if (resignWith == null) return copy;
    final unsigned = copy.sublist(0, copy.length - 64);
    return Uint8List.fromList([
      ...unsigned,
      ...await resignWith.sign(familyEnvelopeSignedMessage(unsigned)),
    ]);
  }

  test('ida y vuelta: HLC, lápidas y campos desconocidos tal cual', () async {
    final bytes = await sealFamilyEnvelope(
      doc: doc,
      candidate: candidate,
      writer: aritz,
      revision: 5,
      signer: family.aritz.keys,
    );
    expect(isFamilyEnvelope(bytes), isTrue);
    final opened = await openIt(bytes);
    expect(opened.doc.canonicalJson(), doc.canonicalJson());
    expect(opened.doc.collections['futuro']!['x1']!['anidado'], [1, 2]);
    expect(opened.doc.collections[Collections.gifts]!['g2']!.isDeleted, true);
    expect(opened.header.writer, 'aritz-phone');
    expect(opened.header.revision, 5);
    expect(opened.header.kid, candidate.kid);
    expect(opened.candidate.kid, candidate.kid);
    expect(peekFamilyEnvelope(bytes).syncId, kSync);
    final verified = await verifyFamilyEnvelope(
      bytes,
      expectedListId: kListId,
      expectedSyncId: kSync,
      resolveWriter: resolver,
    );
    expect(verified.revision, 5);
  });

  test('B7: la clave AES sale de HKDF con el kid; el secreto tal cual no '
      'abre', () async {
    final bytes = await sealAs();
    final hLen = headerLength(bytes);
    final aad = bytes.sublist(0, 5 + hLen);
    final nonce = bytes.sublist(5 + hLen, 5 + hLen + 12);
    final macStart = bytes.length - 64 - 16;
    final box = SecretBox(
      bytes.sublist(5 + hLen + 12, macStart),
      nonce: nonce,
      mac: Mac(bytes.sublist(macStart, macStart + 16)),
    );
    final aes = AesGcm.with256bits();
    await expectLater(
      aes.decrypt(box, secretKey: SecretKey(candidate.secret), aad: aad),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
    final derived = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: SecretKey(candidate.secret),
      nonce: const <int>[],
      info: [
        ...utf8.encode('gift-huddle-common-v2'),
        0,
        ...utf8.encode(candidate.kid),
      ],
    );
    final plain = await aes.decrypt(box, secretKey: derived, aad: aad);
    expect(plain, isNotEmpty);
  });

  test('cada campo de la cabecera: sin volver a firmar falla la firma (o la '
      'lista); firmado de nuevo, falla lo que corresponde', () async {
    final bytes = await sealAs();
    final other = await candidateFor(family, family.view, seed: 9);
    final otherCtx = await candidateFor(
      family,
      family.view,
      seed: 10,
      context: 'a' * 64,
    );
    final otherEpoch = await candidateFor(
      family,
      family.view,
      seed: 11,
      epoch: 2,
    );
    // El llavero tiene de verdad candidatas de otro kid, otro contexto y otra
    // época: lo que falla no es solo «no hay clave».
    final wide = ring
        .withOwnCandidate(other)
        .withOwnCandidate(otherCtx)
        .withOwnCandidate(otherEpoch);
    final leoRecord = family.view.member('leo-phone')!.recordDigest;
    const badSig = 'firma no válida';
    const missing = 'falta la clave común del sobre';
    const gcm = 'clave equivocada o sobre manipulado';
    final cases =
        <
          String,
          ({
            Map<String, Object?> Function(Map<String, Object?>) change,
            DeviceKeys resigner,
            String listId,
            String syncId,
            Matcher plain,
            Matcher resigned,
          })
        >{
          // El kid liga contexto y época: ningún kid del llavero los acepta.
          'ctx': (
            change: (h) => {...h, 'ctx': otherCtx.epochContext},
            resigner: family.aritz.keys,
            listId: kListId,
            syncId: kSync,
            plain: _fails<EnvelopeAuthException>(badSig),
            resigned: _fails<EnvelopeMissingKeyException>(missing),
          ),
          'e': (
            change: (h) => {...h, 'e': 2},
            resigner: family.aritz.keys,
            listId: kListId,
            syncId: kSync,
            plain: _fails<EnvelopeAuthException>(badSig),
            resigned: _fails<EnvelopeMissingKeyException>(missing),
          ),
          'kid': (
            change: (h) => {...h, 'kid': other.kid},
            resigner: family.aritz.keys,
            listId: kListId,
            syncId: kSync,
            plain: _fails<EnvelopeAuthException>(badSig),
            resigned: _fails<EnvelopeAuthException>(gcm),
          ),
          'l': (
            change: (h) => {...h, 'l': 'list-2'},
            resigner: family.aritz.keys,
            listId: 'list-2',
            syncId: kSync,
            plain: _fails<EnvelopeAuthException>(badSig),
            resigned: _fails<EnvelopeMissingKeyException>(missing),
          ),
          'sid': (
            change: (h) => {...h, 'sid': kOtherSync},
            resigner: family.aritz.keys,
            listId: kListId,
            syncId: kOtherSync,
            plain: _fails<EnvelopeAuthException>(badSig),
            resigned: _fails<EnvelopeMissingKeyException>(missing),
          ),
          'r': (
            change: (h) => {...h, 'r': 6},
            resigner: family.aritz.keys,
            listId: kListId,
            syncId: kSync,
            plain: _fails<EnvelopeAuthException>(badSig),
            resigned: _fails<EnvelopeAuthException>(gcm),
          ),
          'w': (
            change: (h) => {...h, 'w': 'leo-phone', 'wr': leoRecord},
            resigner: family.leo.keys,
            listId: kListId,
            syncId: kSync,
            plain: _fails<EnvelopeAuthException>(badSig),
            resigned: _fails<EnvelopeAuthException>(gcm),
          ),
          'wr': (
            change: (h) => {...h, 'wr': leoRecord},
            resigner: family.aritz.keys,
            listId: kListId,
            syncId: kSync,
            plain: _fails<EnvelopeUnknownWriterException>(
              'escritor no reconocido',
            ),
            resigned: _fails<EnvelopeUnknownWriterException>(
              'escritor no reconocido',
            ),
          ),
        };
    for (final e in cases.entries) {
      final c = e.value;
      await expectLater(
        openIt(
          await withHeader(bytes, c.change),
          keyring: wide,
          listId: c.listId,
          syncId: c.syncId,
        ),
        c.plain,
        reason: e.key,
      );
      await expectLater(
        openIt(
          await withHeader(bytes, c.change, resignWith: c.resigner),
          keyring: wide,
          listId: c.listId,
          syncId: c.syncId,
        ),
        c.resigned,
        reason: '${e.key} (firmado de nuevo)',
      );
    }
    // B6: con un resolvedor que acepta cualquier ficha, el escritor con otra
    // ficha que la de la audiencia tampoco entra.
    await expectLater(
      openIt(
        await withHeader(
          bytes,
          (h) => {...h, 'wr': leoRecord},
          resignWith: family.aritz.keys,
        ),
        resolve: (_, _) => family.aritz.keys.publicKeys.signing,
      ),
      _fails<EnvelopeAuthException>(
        'el escritor no conoce la clave común del sobre',
      ),
    );
    // Ámbito, versión y claves de más.
    for (final change in [
      (Map<String, Object?> h) => {...h, 's': 'surprise:nora'},
      (Map<String, Object?> h) => {...h, 'v': 1},
      (Map<String, Object?> h) => {...h, 'extra': 1},
    ]) {
      await expectLater(
        openIt(await withHeader(bytes, change, resignWith: family.aritz.keys)),
        _fails<EnvelopeFormatException>('cabecera no válida'),
      );
    }
  });

  test('cabeceras no canónicas: claves repetidas, 1.0, 1e0, -0, escapes, '
      'espacios y BOM, aunque las firme el escritor', () async {
    final bytes = await sealAs();
    final header = utf8.decode(bytes.sublist(5, 5 + headerLength(bytes)));
    expect(header, contains('"e":1,'));
    expect(header, contains('"r":5,'));
    // Una barra invertida, sin escribirla en el código.
    final bs = String.fromCharCode(92);
    final variants = <String, (List<int>, List<String>)>{
      'clave repetida al principio': (
        utf8.encode(header.replaceFirst('{', '{"e":2,')),
        ['cabecera no canónica'],
      ),
      'clave repetida al final': (
        utf8.encode('${header.substring(0, header.length - 1)},"r":6}'),
        ['cabecera no canónica'],
      ),
      // En la VM 1.0 no es int; en dart2js lo es y falla la forma canónica.
      'e:1.0': (
        utf8.encode(header.replaceFirst('"e":1,', '"e":1.0,')),
        ['cabecera no válida', 'cabecera no canónica'],
      ),
      'e:1e0': (
        utf8.encode(header.replaceFirst('"e":1,', '"e":1e0,')),
        ['cabecera no válida', 'cabecera no canónica'],
      ),
      'r:-0': (
        utf8.encode(header.replaceFirst('"r":5,', '"r":-0,')),
        ['cabecera no canónica'],
      ),
      'escape en una clave': (
        utf8.encode(header.replaceFirst('"l":', '"${bs}u006c":')),
        ['cabecera no canónica'],
      ),
      'escape en un valor': (
        utf8.encode(header.replaceFirst('list-1', '${bs}u006cist-1')),
        ['cabecera no canónica'],
      ),
      'espacio': (
        utf8.encode(header.replaceFirst(':', ': ')),
        ['cabecera no canónica'],
      ),
      'espacio final': (utf8.encode('$header '), ['cabecera no canónica']),
      'BOM': (
        [0xEF, 0xBB, 0xBF, ...utf8.encode(header)],
        ['cabecera dañada', 'cabecera no canónica'],
      ),
    };
    // Control: la misma cabecera firmada de nuevo abre.
    expect(
      (await openIt(
        await withRawHeader(
          bytes,
          utf8.encode(header),
          resignWith: family.aritz.keys,
        ),
      )).header.revision,
      5,
    );
    for (final e in variants.entries) {
      await expectLater(
        openIt(
          await withRawHeader(bytes, e.value.$1, resignWith: family.aritz.keys),
        ),
        throwsA(
          isA<EnvelopeFormatException>().having(
            (x) => x.message,
            'message',
            isIn(e.value.$2),
          ),
        ),
        reason: e.key,
      );
    }
  });

  test('nonce, cifrado, etiqueta o firma: sin firmar de nuevo falla la '
      'firma; firmado de nuevo, el GCM', () async {
    final bytes = await sealAs();
    final hLen = headerLength(bytes);
    final positions = {
      'nonce': 5 + hLen,
      'cifrado': 5 + hLen + 12,
      'etiqueta': bytes.length - 64 - 1,
    };
    for (final e in positions.entries) {
      await expectLater(
        openIt(await flip(bytes, e.value)),
        _fails<EnvelopeAuthException>('firma no válida'),
        reason: e.key,
      );
      await expectLater(
        openIt(await flip(bytes, e.value, resignWith: family.aritz.keys)),
        _fails<EnvelopeAuthException>('clave equivocada o sobre manipulado'),
        reason: '${e.key} (firmado de nuevo)',
      );
    }
    await expectLater(
      openIt(await flip(bytes, bytes.length - 1)),
      _fails<EnvelopeAuthException>('firma no válida'),
    );
    await expectLater(
      openIt(await flip(bytes, 0)),
      _fails<EnvelopeFormatException>('no es un sobre de Regalos'),
    );
    await expectLater(
      openIt(await flip(bytes, 4)),
      _fails<EnvelopeFormatException>('cabecera dañada'),
    );
  });

  test('escritor: desconocido, firma de otro, clave que no es la suya, '
      'fuera de la audiencia o revocado', () async {
    final bytes = await sealAs();
    await expectLater(
      openIt(bytes, resolve: (_, _) => null),
      _fails<EnvelopeUnknownWriterException>('escritor no reconocido'),
    );
    await expectLater(
      openIt(bytes, resolve: (_, _) => family.leo.keys.publicKeys.signing),
      _fails<EnvelopeAuthException>('firma no válida'),
    );
    // Firmado por Leo diciendo ser Aritz.
    await expectLater(
      openIt(await sealAs(signer: family.leo.keys)),
      _fails<EnvelopeAuthException>('firma no válida'),
    );
    // B1: sealFamilyEnvelope no firma con claves que no son las del escritor.
    await expectLater(
      sealFamilyEnvelope(
        doc: doc,
        candidate: candidate,
        writer: aritz,
        revision: 1,
        signer: family.leo.keys,
      ),
      _fails<EnvelopeFormatException>('la firma no es la del escritor'),
    );
    // B6: el escritor tiene que estar en la audiencia con su ficha.
    final w = await withWeb(family);
    await expectLater(
      sealFamilyEnvelope(
        doc: doc,
        candidate: candidate,
        writer: w.root.member('web-1')!,
        revision: 1,
        signer: w.web.keys,
      ),
      _fails<EnvelopeFormatException>('el escritor no conoce esa clave común'),
    );
    // Una web de la audiencia sí escribe.
    final withWebKey = await candidateFor(family, w.root);
    final fromWeb = await sealFamilyEnvelope(
      doc: doc,
      candidate: withWebKey,
      writer: w.root.member('web-1')!,
      revision: 1,
      signer: w.web.keys,
    );
    expect(
      (await openIt(
        fromWeb,
        keyring: FamilyKeyring.empty.withOwnCandidate(withWebKey),
        resolve: (wr, r) => w.leo.member(wr)?.recordDigest == r
            ? w.leo.member(wr)!.signingKey
            : null,
      )).header.writer,
      'web-1',
    );
    // Un revocado: el resolvedor de quien llama ya no le da clave.
    final revoked = await family.leo.viewOf(
      await withRevoked(family, family.nora),
    );
    final fromNora = await sealAs(
      writer: 'nora-phone',
      signer: family.nora.keys,
      nonce: List<int>.filled(12, 5),
    );
    expect((await openIt(fromNora)).header.writer, 'nora-phone');
    await expectLater(
      openIt(
        fromNora,
        resolve: (wr, r) => revoked.member(wr)?.recordDigest == r
            ? revoked.member(wr)!.signingKey
            : null,
      ),
      _fails<EnvelopeUnknownWriterException>('escritor no reconocido'),
    );
  });

  test('lista, generación y clave', () async {
    final bytes = await sealAs();
    await expectLater(
      openIt(bytes, listId: 'list-2'),
      _fails<EnvelopeWrongListException>('el sobre es de otra lista'),
    );
    await expectLater(
      openIt(bytes, syncId: kOtherSync),
      _fails<EnvelopeWrongListException>('el sobre es de otra lista'),
    );
    await expectLater(
      openIt(bytes, keyring: FamilyKeyring.empty),
      _fails<EnvelopeMissingKeyException>('falta la clave común del sobre'),
    );
    await expectLater(
      openIt(
        bytes,
        keyring: FamilyKeyring.empty.withOwnCandidate(
          await candidateFor(family, family.view, context: 'a' * 64),
        ),
      ),
      _fails<EnvelopeMissingKeyException>('falta la clave común del sobre'),
    );
    final hist = FamilyKeyring.empty.withOwnCandidate(
      candidate,
      historical: true,
    );
    expect((await openIt(bytes, keyring: hist)).header.kid, candidate.kid);
    final foreign = await sealAs(
      rawBody: Deflate(
        utf8.encode(jsonEncode(FamilyDoc.empty('list-2').toJson())),
      ).getBytes(),
    );
    await expectLater(
      openIt(foreign),
      _fails<EnvelopeWrongListException>('el documento es de otra lista'),
    );
    await expectLater(
      sealAs(body: FamilyDoc.empty('list-2')),
      _fails<EnvelopeFormatException>('el documento es de otra lista'),
    );
  });

  test('formato 1 y formato 2 no se confunden', () async {
    final v1 = await seal(
      doc: doc.toJson(),
      listId: kListId,
      fromNode: 'aritz-phone',
      at: '',
      key: FamilyKey(candidate.secret),
    );
    expect(isFamilyEnvelope(v1), isFalse);
    await expectLater(
      openIt(v1),
      _fails<EnvelopeFormatException>('versión 1 no soportada'),
    );
    await expectLater(
      open(
        await sealAs(),
        key: FamilyKey(candidate.secret),
        expectedListId: kListId,
      ),
      _fails<EnvelopeFormatException>('versión 2 no soportada'),
    );
  });

  test('límites antes de verificar y bomba de compresión', () async {
    var called = false;
    Future<List<int>?> spy(String w, String r) async {
      called = true;
      return resolver(w, r);
    }

    final huge = Uint8List(kMaxEnvelopeBytes + 1)
      ..setAll(0, const [0x52, 0x47, 2, 0, 10]);
    await expectLater(
      openIt(huge, resolve: spy),
      _fails<EnvelopeTooLargeException>('sobre demasiado grande'),
    );
    final longHeader = Uint8List(2000)
      ..setAll(0, [
        0x52,
        0x47,
        2,
        (kMaxFamilyHeaderBytes + 1) >> 8,
        (kMaxFamilyHeaderBytes + 1) & 0xFF,
      ]);
    await expectLater(
      openIt(longHeader, resolve: spy),
      _fails<EnvelopeFormatException>('cabecera demasiado larga'),
    );
    final bytes = await sealAs();
    final hLen = headerLength(bytes);
    await expectLater(
      openIt(Uint8List.sublistView(bytes, 0, 5 + hLen + 40), resolve: spy),
      _fails<EnvelopeFormatException>('sobre truncado'),
    );
    expect(called, isFalse);
    await expectLater(
      openIt(Uint8List.sublistView(bytes, 0, bytes.length - 70)),
      _fails<EnvelopeAuthException>('firma no válida'),
    );

    // Bomba: 9 MiB de ceros comprimidos en unos KiB, cifrados y firmados
    // como es debido.
    final bomb = Deflate(Uint8List(kMaxPlainBytes + 1024 * 1024)).getBytes();
    expect(bomb.length, lessThan(64 * 1024));
    await expectLater(
      openIt(await sealAs(rawBody: bomb)),
      _fails<EnvelopeTooLargeException>('documento demasiado grande'),
    );
    for (final (raw, message) in [
      ([1, 2, 3, 4], 'cuerpo comprimido dañado'),
      (Deflate(utf8.encode('[1,2]')).getBytes(), 'documento no válido'),
      (Deflate(utf8.encode('{"v":9}')).getBytes(), 'documento no válido'),
    ]) {
      await expectLater(
        openIt(await sealAs(rawBody: raw)),
        throwsA(
          isA<EnvelopeFormatException>().having(
            (e) => e.message,
            'message',
            anyOf(message, 'cuerpo comprimido truncado'),
          ),
        ),
      );
    }
    var big = FamilyDoc.empty(kListId);
    final clock = clockOf('aritz-phone', 2);
    final text = List.filled(1024 * 1024, 'x').join();
    for (var i = 0; i < 9; i++) {
      big = big.set(clock, 'notas', 'n$i', {'t': text});
    }
    await expectLater(
      sealAs(body: big),
      _fails<EnvelopeTooLargeException>('documento demasiado grande'),
    );
  });

  test('revisión fuera de rango no se sella', () async {
    for (final r in [-1, kMaxFamilyRevision + 1]) {
      await expectLater(
        sealAs(revision: r),
        _fails<EnvelopeFormatException>('cabecera no válida'),
      );
    }
  });
}
