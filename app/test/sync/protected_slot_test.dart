import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/device_keys.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/protected_doc.dart';
import 'package:regalos/core/sync/protected_envelope.dart';

import 'protected_harness.dart';

/// Formato de los slots de sorpresas: tamaño fijo, capacidad, AAD y firma.
void main() {
  late Family family;
  setUp(() async => family = await Family.create());

  const on = PolicyState(hideOwnGifts: true, rev: 1);

  Future<SealedSlot> sealAs(
    Phone phone,
    FamilyDoc doc, {
    int revision = 1,
    SurpriseKey? key,
  }) => SealedSlot.seal(
    writerKeys: phone.keys,
    writer: phone.id,
    revision: revision,
    key: key ?? family.key,
    policy: on,
    doc: doc,
  );

  Future<OpenedSlot> openAsLeo(SealedSlot slot, {Phone? signer}) => slot.open(
    expectedListId: kListId,
    key: family.key,
    signingKey: (signer ?? family.aritz).keys.publicKeys.signing,
  );

  group('tamaño fijo', () {
    test('con 0, 1, 5 y 50 regalos el slot mide lo mismo', () async {
      final sizes = <int>{};
      for (final n in [0, 1, 5, 50]) {
        final doc = scopeWith(clockOf('aritz-phone', 1000), [
          for (var i = 0; i < n; i++) 'Regalo número $i',
        ]);
        final slot = await sealAs(family.aritz, doc);
        sizes.add(slot.bytes.length);
        final opened = await openAsLeo(SealedSlot.parse(slot.bytes));
        expect(liveSurpriseGifts(opened.doc), n);
      }
      expect(sizes, hasLength(1));
      expect(
        sizes.single,
        SealedSlot.sizeFor(
          SlotHeader(
            listId: kListId,
            personId: 'nora',
            epoch: 1,
            writer: 'aritz-phone',
            revision: 1,
            policy: on,
            kid: family.key.kid,
          ),
        ),
      );
    });

    test('caben 50 regalos con textos largos y poco comprimibles', () async {
      final rnd = Random(7);
      String noise(int n) => String.fromCharCodes(
        List<int>.generate(n, (_) => 0x61 + rnd.nextInt(26)),
      );
      var doc = FamilyDoc.empty(kListId);
      final clock = clockOf('aritz-phone', 1000);
      for (var i = 0; i < kMaxSurpriseGifts; i++) {
        doc = doc.set(clock, Collections.gifts, 'g$i', {
          ...giftFields('nora', noise(80), note: noise(400)),
          'url': 'https://example.com/${noise(150)}',
          'store': noise(30),
          'size': noise(10),
          'requestNote': noise(120),
          'plannedCents': 123456,
        });
      }
      final slot = await sealAs(family.aritz, doc);
      final opened = await openAsLeo(slot);
      expect(liveSurpriseGifts(opened.doc), kMaxSurpriseGifts);
    });

    test('desde la interfaz caben 200: el 201 da un error claro', () {
      final clock = clockOf('aritz-phone', 1000);
      var doc = FamilyDoc.empty(kListId);
      for (var i = 0; i < kMaxSurpriseGifts; i++) {
        doc = addSurpriseGift(doc, clock, 'g$i', giftFields('nora', 'R$i'));
      }
      expect(liveSurpriseGifts(doc), 200);
      expect(
        () => addSurpriseGift(doc, clock, 'g200', giftFields('nora', 'R200')),
        throwsA(
          isA<SurpriseCapacityException>().having((e) => e.count, 'count', 201),
        ),
      );
      // Editar uno que ya está sí se puede.
      final edited = addSurpriseGift(doc, clock, 'g3', {'title': 'Otro'});
      expect(edited.record(Collections.gifts, 'g3')!['title'], 'Otro');
    });

    test(
      'el slot admite el margen de la reconciliación y ni uno más',
      () async {
        final ok = scopeWith(clockOf('aritz-phone', 1000), [
          for (var i = 0; i < kMaxSlotGifts; i++) 'Regalo $i',
        ]);
        final slot = await sealAs(family.aritz, ok);
        expect(liveSurpriseGifts((await openAsLeo(slot)).doc), kMaxSlotGifts);
        final tooMany = scopeWith(clockOf('aritz-phone', 1000), [
          for (var i = 0; i <= kMaxSlotGifts; i++) 'Regalo $i',
        ]);
        await expectLater(
          sealAs(family.aritz, tooMany),
          throwsA(isA<SurpriseCapacityException>()),
        );
      },
    );

    test('las lápidas no cuentan para la capacidad', () async {
      final clock = clockOf('aritz-phone', 1000);
      var doc = scopeWith(clock, [for (var i = 0; i < 74; i++) 'Regalo $i']);
      for (var i = 0; i < 10; i++) {
        doc = doc.delete(clock, Collections.gifts, 's$i');
      }
      final opened = await openAsLeo(await sealAs(family.aritz, doc));
      expect(liveSurpriseGifts(opened.doc), 64);
    });

    test('64 regalos al tope de tamaño, incomprimibles, caben (lo que abre '
        'un 1.0.5)', () async {
      final rnd = Random(11);
      var doc = FamilyDoc.empty(kListId);
      final clock = clockOf('aritz-phone', 1000);
      for (var i = 0; i < kLegacySlotGifts; i++) {
        doc = doc.set(clock, Collections.gifts, 'g$i', giftFields('nora', 'T'));
        final record = doc.record(Collections.gifts, 'g$i')!;
        final room = kMaxSurpriseGiftBytes - surpriseRecordBytes(record) - 4;
        doc = doc.set(clock, Collections.gifts, 'g$i', {
          'note': String.fromCharCodes(
            List<int>.generate(room, (_) => 0x21 + rnd.nextInt(90)),
          ).replaceAll('"', 'x').replaceAll(r'\', 'y'),
        });
        expect(
          surpriseRecordBytes(doc.record(Collections.gifts, 'g$i')!),
          lessThanOrEqualTo(kMaxSurpriseGiftBytes),
        );
      }
      final opened = await openAsLeo(await sealAs(family.aritz, doc));
      expect(liveSurpriseGifts(opened.doc), kLegacySlotGifts);
    });

    test('un regalo demasiado grande: error, sin crecer (M4)', () async {
      final huge = 'x' * (kMaxSurpriseGiftBytes + 1);
      final doc = FamilyDoc.empty(kListId).set(
        clockOf('aritz-phone', 1000),
        Collections.gifts,
        'g1',
        giftFields('nora', 'Libro', note: huge),
      );
      await expectLater(
        sealAs(family.aritz, doc),
        throwsA(isA<SurpriseGiftTooLargeException>()),
      );
      expect(
        () => addSurpriseGift(
          FamilyDoc.empty(kListId),
          clockOf('aritz-phone', 1000),
          'g1',
          giftFields('nora', 'Libro', note: huge),
        ),
        throwsA(isA<SurpriseGiftTooLargeException>()),
      );
    });

    test('más de 1 MiB sin comprimir: error antes de sellar algo que no se '
        'podría abrir (M4)', () async {
      final clock = clockOf('aritz-phone', 1000);
      final gifts = <String, SyncRecord>{};
      // Muchas lápidas: comprimen bien, pero el JSON pasa de 1 MiB.
      var doc = FamilyDoc.empty(kListId)
          .set(clock, Collections.gifts, 't', giftFields('nora', 'Muestra'));
      doc = doc.delete(clock, Collections.gifts, 't');
      final tombstone = doc.record(Collections.gifts, 't')!;
      for (var i = 0; i < 5000; i++) {
        gifts['t$i'] = SyncRecord(id: 't$i', fields: tombstone.fields);
      }
      final big = FamilyDoc(
        listId: kListId,
        collections: {Collections.gifts: gifts},
      );
      expect(
        utf8.encode(big.canonicalJson()).length,
        greaterThan(kMaxSlotJsonBytes),
      );
      expect(scopeFitsInSlot(big, 'nora'), isFalse);
      await expectLater(
        sealAs(family.aritz, big),
        throwsA(isA<SurpriseSlotFullException>()),
      );
    });
  });

  group('contenido', () {
    test('no se ve nada en claro y el relleno va cifrado', () async {
      final doc = scopeWith(clockOf('aritz-phone', 1000), ['Bicicleta roja']);
      final slot = await sealAs(family.aritz, doc);
      final text = latin1.decode(slot.bytes);
      expect(text, isNot(contains('Bicicleta')));
      expect(text, isNot(contains('Nota del regalo')));
      // El relleno de ceros no se nota: en la parte cifrada no hay rachas
      // largas de ceros.
      final body = slot.bytes.sublist(64, slot.bytes.length - 80);
      var run = 0;
      var longest = 0;
      for (final b in body) {
        run = b == 0 ? run + 1 : 0;
        longest = max(longest, run);
      }
      expect(longest, lessThan(16));
    });

    test('solo se sellan regalos de la persona protegida', () async {
      final doc = FamilyDoc.empty(kListId).set(
        clockOf('aritz-phone', 1000),
        Collections.gifts,
        'g1',
        giftFields('aritz', 'Para Aritz'),
      );
      expect(() => sealAs(family.aritz, doc), throwsArgumentError);
      final withPeople = commonWithPeople(clockOf('aritz-phone', 1000));
      expect(() => sealAs(family.aritz, withPeople), throwsArgumentError);
    });

    test('la política va dentro, autenticada', () async {
      final slot = await SealedSlot.seal(
        writerKeys: family.aritz.keys,
        writer: family.aritz.id,
        revision: 3,
        key: family.key,
        policy: const PolicyState(hideOwnGifts: false, rev: 7),
        doc: FamilyDoc.empty(kListId),
      );
      final opened = await openAsLeo(slot);
      expect(opened.policy, const PolicyState(hideOwnGifts: false, rev: 7));
      expect(opened.header.revision, 3);
    });
  });

  group('rechazos', () {
    late SealedSlot slot;
    setUp(() async {
      slot = await sealAs(
        family.aritz,
        scopeWith(clockOf('aritz-phone', 1000), ['Patinete']),
        revision: 5,
      );
    });

    test('manipular la lista, el ámbito, la época, el escritor o la revisión '
        'de la cabecera: rechazado', () async {
      const listStart = _listStart;
      final personStart = listStart + kListId.length + 1;
      final writerStart = personStart + 'nora'.length + 1;
      for (final offset in [7, 15, listStart, personStart, writerStart]) {
        final bytes = Uint8List.fromList(slot.bytes);
        bytes[offset] ^= 0x02;
        final SealedSlot tampered;
        try {
          tampered = SealedSlot.parse(bytes);
        } on SlotFormatException {
          continue;
        }
        await expectLater(
          tampered.open(
            expectedListId: tampered.header.listId,
            key: SurpriseKey(
              personId: tampered.header.personId,
              epoch: tampered.header.epoch,
              bytes: family.key.bytes,
            ),
            signingKey: family.aritz.keys.publicKeys.signing,
          ),
          throwsA(isA<ProtectedEnvelopeException>()),
          reason: 'byte $offset',
        );
        // Aunque quien manipula vuelva a firmar, el GCM no cuadra.
        final resigned = await _resign(bytes, family.aritz.keys);
        await expectLater(
          SealedSlot.parse(resigned).open(
            expectedListId: tampered.header.listId,
            key: SurpriseKey(
              personId: tampered.header.personId,
              epoch: tampered.header.epoch,
              bytes: family.key.bytes,
            ),
            signingKey: family.aritz.keys.publicKeys.signing,
          ),
          throwsA(isA<ProtectedEnvelopeException>()),
          reason: 'byte $offset, firmado otra vez',
        );
      }
    });

    test('ataque N1: cambiar la política de la cabecera (de «ocultar» a '
        '«publicar», o su revisión) rompe la firma, y si el propio escritor '
        'la cambia y vuelve a firmar, el GCM', () async {
      for (final offset in [_policyFlag, _policyRevEnd]) {
        final bytes = Uint8List.fromList(slot.bytes);
        bytes[offset] ^= 0x01;
        final tampered = SealedSlot.parse(bytes);
        expect(
          tampered.header.policy,
          isNot(slot.header.policy),
          reason: 'byte $offset',
        );
        // Quien no tiene la clave de firma del escritor (Nora, el servidor):
        // la firma ya no vale, así que el slot no entra en ningún conjunto.
        expect(
          await tampered.verifySignature(family.aritz.keys.publicKeys.signing),
          isFalse,
        );
        await expectLater(
          SlotSet.empty.acceptVerified(tampered, view: family.view),
          throwsA(isA<SlotAuthException>()),
        );
        // Firmado otra vez: la cabecera es el AAD, y el GCM no cuadra.
        await expectLater(
          openAsLeo(SealedSlot.parse(await _resign(bytes, family.aritz.keys))),
          throwsA(isA<SlotAuthException>()),
        );
      }
      expect(slot.header.policy, on);
      expect(slot.header.kid, family.key.kid);
    });

    test('cambio de escritor: ni con la firma del otro móvil', () async {
      final bytes = _withWriter(slot.bytes, 'leo-phone');
      final asLeo = SealedSlot.parse(bytes);
      expect(asLeo.header.writer, 'leo-phone');
      // Sin volver a firmar: la firma no es de Leo.
      expect(
        await asLeo.verifySignature(family.leo.keys.publicKeys.signing),
        isFalse,
      );
      // Firmado por Leo: la firma vale, pero el AAD ya no es el del GCM.
      final resigned = SealedSlot.parse(await _resign(bytes, family.leo.keys));
      expect(
        await resigned.verifySignature(family.leo.keys.publicKeys.signing),
        isTrue,
      );
      await expectLater(
        openAsLeo(resigned, signer: family.leo),
        throwsA(isA<SlotAuthException>()),
      );
    });

    test('firma falsa: rechazada', () async {
      final bytes = Uint8List.fromList(slot.bytes);
      for (var i = bytes.length - 64; i < bytes.length; i++) {
        bytes[i] = 0;
      }
      final fake = SealedSlot.parse(bytes);
      expect(
        await fake.verifySignature(family.aritz.keys.publicKeys.signing),
        isFalse,
      );
      await expectLater(openAsLeo(fake), throwsA(isA<SlotAuthException>()));
      // Firma de verdad, pero de otro móvil.
      await expectLater(
        openAsLeo(slot, signer: family.nora),
        throwsA(isA<SlotAuthException>()),
      );
    });

    test('texto cifrado manipulado: rechazado', () async {
      final bytes = Uint8List.fromList(slot.bytes);
      bytes[bytes.length - 200] ^= 0x80;
      await expectLater(
        openAsLeo(SealedSlot.parse(bytes)),
        throwsA(isA<SlotAuthException>()),
      );
    });

    test('ni la familyKey ni otra clave lo abren', () async {
      final familyKey = await FamilyKey.generate();
      for (final bytes in [familyKey.bytes, secureRandomBytes(32)]) {
        final wrong = SurpriseKey(personId: 'nora', epoch: 1, bytes: bytes);
        // La cabecera dice con qué clave se selló: con otra ni se intenta.
        await expectLater(
          slot.open(
            expectedListId: kListId,
            key: wrong,
            signingKey: family.aritz.keys.publicKeys.signing,
          ),
          throwsA(isA<SlotWrongScopeException>()),
        );
        // Y si el escritor pusiera en la cabecera esa otra clave y volviera
        // a firmar, el GCM no cuadra.
        final relabelled = Uint8List.fromList(slot.bytes)
          ..setRange(_kidStart, _kidStart + 8, _hexBytes(wrong.kid));
        await expectLater(
          SealedSlot.parse(await _resign(relabelled, family.aritz.keys)).open(
            expectedListId: kListId,
            key: wrong,
            signingKey: family.aritz.keys.publicKeys.signing,
          ),
          throwsA(isA<SlotAuthException>()),
        );
      }
    });

    test('otra lista, otra persona u otra época: rechazado', () async {
      await expectLater(
        slot.open(
          expectedListId: 'otra',
          key: family.key,
          signingKey: family.aritz.keys.publicKeys.signing,
        ),
        throwsA(isA<SlotWrongScopeException>()),
      );
      await expectLater(
        slot.open(
          expectedListId: kListId,
          key: SurpriseKey(personId: 'nora', epoch: 2, bytes: family.key.bytes),
          signingKey: family.aritz.keys.publicKeys.signing,
        ),
        throwsA(isA<SlotWrongScopeException>()),
      );
    });

    test('bytes truncados, de más o de otra cosa: error de formato', () {
      for (final bad in [
        slot.bytes.sublist(0, slot.bytes.length - 1),
        Uint8List.fromList([...slot.bytes, 0]),
        Uint8List.fromList(utf8.encode('RG no es un slot')),
        Uint8List(0),
      ]) {
        expect(
          () => SealedSlot.parse(bad),
          throwsA(isA<SlotFormatException>()),
        );
      }
    });
  });
}

/// Vuelve a firmar [bytes] (con la firma que tenga) con [keys].
Future<Uint8List> _resign(Uint8List bytes, DeviceKeys keys) async {
  final unsigned = bytes.sublist(0, bytes.length - 64);
  final signature = await keys.sign([
    ...utf8.encode('gift-huddle-slot-v2'),
    0,
    ...unsigned,
  ]);
  return Uint8List.fromList([...unsigned, ...signature]);
}

// Desplazamientos de la cabecera: 4..7 época, 8..15 revisión, 16 política
// (bit 0 = ocultar), 17..24 revisión de la política, 25..32 kid, 33 =
// longitud de la lista y luego sus letras, la persona y el escritor.
const _policyFlag = 16;
const _policyRevEnd = 24;
const _kidStart = 25;
const _listStart = 34;

List<int> _hexBytes(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

/// [bytes] con otro escritor en la cabecera (misma firma).
Uint8List _withWriter(Uint8List bytes, String writer) {
  const listStart = _listStart;
  final personLength = bytes[listStart + kListId.length];
  final writerLengthAt = listStart + kListId.length + 1 + personLength;
  final oldLength = bytes[writerLengthAt];
  return Uint8List.fromList([
    ...bytes.sublist(0, writerLengthAt),
    writer.length,
    ...ascii.encode(writer),
    ...bytes.sublist(writerLengthAt + 1 + oldLength),
  ]);
}
