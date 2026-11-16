import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/family/domain/family_errors.dart';
import 'package:regalos/features/sharing/application/incoming_share.dart';
import 'package:regalos/features/sharing/application/pairing_service.dart';
import 'package:regalos/features/sharing/application/share_service.dart';

import '../helpers/memory_stores.dart';

Gift gift(String id, {String title = 'Bloques', String? note}) => Gift(
  id: id,
  recipientId: 'aritz',
  title: title,
  status: GiftStatus.idea,
  rawStatus: 'idea',
  note: note,
  surprise: false,
  year: 2026,
);

const aritz = Recipient(
  id: 'aritz',
  name: 'Aritz',
  colorIndex: 0,
  archived: false,
);

FamilyController ctl(FakePhone p) =>
    p.container.read(familyControllerProvider.notifier);
PairingService pairing(FakePhone p) => p.container.read(pairingServiceProvider);
ShareService share(FakePhone p) => p.container.read(shareServiceProvider);
Future<FamilyState> stateOf(FakePhone p) =>
    p.container.read(familyControllerProvider.future);

/// A crea la familia con un par de datos.
Future<FakePhone> phoneWithFamily(String name) async {
  final phone = FakePhone();
  await ctl(phone).createFamily(deviceName: name);
  await ctl(phone).upsertRecipient(aritz);
  await ctl(phone).upsertGift(gift('g1', note: 'azul'));
  return phone;
}

void main() {
  late List<FakePhone> phones;
  FakePhone track(FakePhone p) {
    phones.add(p);
    return p;
  }

  setUp(() => phones = []);
  tearDown(() {
    for (final p in phones) {
      p.dispose();
    }
  });

  test('B4: tras el corte al formato 2 un .regalos antiguo no entra ni se '
      'exporta, y no rebaja la marca', () async {
    final a = track(await phoneWithFamily('Móvil A'));
    final b = track(FakePhone());
    await pairing(b)
        .joinFromQr(await pairing(a).qrTextForPairing(), deviceName: 'Móvil B');
    // Un fichero de antes del corte.
    final old = await share(a).buildEnvelope();
    final store = b.container.read(familyStoreProvider);
    await store.raiseCommonFormatFloor(2);
    final before = (await stateOf(b)).doc.canonicalJson();
    await expectLater(
      share(b).importEnvelopeBytes(old),
      throwsA(isA<EnvelopeFormatException>()),
    );
    await expectLater(
      share(b).buildEnvelope(),
      throwsA(isA<EnvelopeFormatException>()),
    );
    expect((await stateOf(b)).doc.canonicalJson(), before);
    expect(await store.readCommonFormatFloor(), 2);
    // Nunca baja.
    await store.raiseCommonFormatFloor(1);
    expect(await store.readCommonFormatFloor(), 2);
    // El que aún no ha cortado sigue como antes.
    expect((await share(a).importEnvelopeBytes(old)).giftsAdded, 0);
  });

  test(
    'dos móviles: QR, cambios por los dos lados y mismo documento',
    () async {
      final a = track(await phoneWithFamily('Móvil A'));
      final b = track(FakePhone());

      final qr = await pairing(a).qrTextForPairing();
      final joined = await pairing(b).joinFromQr(qr, deviceName: 'Móvil B');
      expect(joined.peerName, 'Móvil A');
      expect(joined.replacedFamily, isFalse);
      final stateB = await stateOf(b);
      expect(stateB.paired, isTrue);
      expect(stateB.listId, (await stateOf(a)).listId);
      expect(ctl(b).familyKey, ctl(a).familyKey);
      expect(stateB.identity!.node, isNot((await stateOf(a)).identity!.node));

      // A manda su lista a B.
      final first = await share(b)
          .importEnvelopeBytes(await share(a).buildEnvelope());
      expect(first.giftsAdded, 1);
      expect((await stateOf(b)).view.gifts.single.title, 'Bloques');

      // Los dos editan: A cambia el título; B cambia la nota y añade un regalo.
      await ctl(a)
          .upsertGift(gift('g1', title: 'Bloques grandes', note: 'azul'));
      await ctl(b).upsertGift(gift('g1', note: 'rojo'));
      await ctl(b).upsertGift(gift('g2', title: 'Tren'));

      // Intercambian en las dos direcciones.
      final intoA = await share(a)
          .importEnvelopeBytes(await share(b).buildEnvelope());
      expect(intoA.giftsAdded, 1);
      expect(intoA.giftsChanged, 1);
      expect((await stateOf(a)).paired, isTrue);
      final intoB = await share(b)
          .importEnvelopeBytes(await share(a).buildEnvelope());
      expect(intoB.giftsChanged, 1);

      final docA = (await stateOf(a)).doc.canonicalJson();
      final docB = (await stateOf(b)).doc.canonicalJson();
      expect(docA, docB);
      final merged = (await stateOf(a)).view.gifts;
      final g1 = merged.firstWhere((g) => g.id == 'g1');
      // Cada cambio vive: el título de A y la nota de B.
      expect(g1.title, 'Bloques grandes');
      expect(g1.note, 'rojo');
      expect(merged, hasLength(2));

      // Repetir el mismo sobre no cambia nada.
      final again = await share(a)
          .importEnvelopeBytes(await share(b).buildEnvelope());
      expect(again.docChanged, isFalse);
      expect(again.giftsAdded + again.giftsChanged + again.giftsDeleted, 0);

      // Un borrado viaja como lápida.
      await ctl(b).deleteGift('g2');
      final del = await share(a)
          .importEnvelopeBytes(await share(b).buildEnvelope());
      expect(del.giftsDeleted, 1);
    },
  );

  test('lo guardado sobrevive a reiniciar tras unirse', () async {
    final a = track(await phoneWithFamily('A'));
    final b = track(FakePhone());
    await pairing(b).joinFromQr(await pairing(a).qrTextForPairing());
    b.restart();
    final state = await stateOf(b);
    expect(state.paired, isTrue);
    expect(state.identity!.peerName, 'A');
    expect(ctl(b).familyKey, ctl(a).familyKey);
  });

  group('unirse a otra familia', () {
    test('con datos exige replace', () async {
      final a = track(await phoneWithFamily('A'));
      final c = track(await phoneWithFamily('C'));
      final qr = await pairing(a).qrTextForPairing();
      final oldList = (await stateOf(c)).listId;

      await expectLater(
        pairing(c).joinFromQr(qr),
        throwsA(
          isA<FamilyConflictException>().having(
            (e) => e.existingListId,
            'existingListId',
            oldList,
          ),
        ),
      );
      expect((await stateOf(c)).listId, oldList);
      expect((await stateOf(c)).view.gifts, hasLength(1));

      final result = await pairing(c).joinFromQr(qr, replace: true);
      expect(result.replacedFamily, isTrue);
      expect((await stateOf(c)).listId, (await stateOf(a)).listId);
      expect((await stateOf(c)).view.gifts, isEmpty);
    });

    test('sin datos no hace falta replace', () async {
      final a = track(await phoneWithFamily('A'));
      final empty = track(FakePhone());
      await ctl(empty).createFamily(deviceName: 'Vacío');
      final result = await pairing(empty)
          .joinFromQr(await pairing(a).qrTextForPairing());
      expect(result.replacedFamily, isFalse);
      expect((await stateOf(empty)).listId, (await stateOf(a)).listId);
    });

    test('la misma lista con otra clave exige replace', () async {
      final a = track(await phoneWithFamily('A'));
      final b = track(FakePhone());
      await pairing(b).joinFromQr(await pairing(a).qrTextForPairing());
      await share(b).importEnvelopeBytes(await share(a).buildEnvelope());
      final goodKey = ctl(b).familyKey;
      final other = PairingPayload(
        listId: (await stateOf(a)).listId!,
        key: await FamilyKey.generate(),
        deviceName: 'Intruso',
      ).toQrText();

      await expectLater(
        pairing(b).joinFromQr(other),
        throwsA(isA<FamilyConflictException>()),
      );
      expect(ctl(b).familyKey, goodKey);
      expect((await stateOf(b)).view.gifts, hasLength(1));

      final result = await pairing(b).joinFromQr(other, replace: true);
      expect(result.replacedFamily, isTrue);
      expect(ctl(b).familyKey, isNot(goodKey));
      expect((await stateOf(b)).view.gifts, isEmpty);
    });

    test('un texto que no es un QR de la app da su error', () async {
      final b = track(FakePhone());
      await expectLater(
        pairing(b).joinFromQr('https://example.com'),
        throwsA(isA<PairingFormatException>()),
      );
    });

    test('sin familia no hay QR', () async {
      final b = track(FakePhone());
      await expectLater(
        pairing(b).qrTextForPairing(),
        throwsA(isA<NoFamilyException>()),
      );
    });
  });

  group('sobres rechazados', () {
    test('un sobre de otra lista', () async {
      final a = track(await phoneWithFamily('A'));
      final other = track(await phoneWithFamily('Otra'));
      await expectLater(
        share(a).importEnvelopeBytes(await share(other).buildEnvelope()),
        throwsA(isA<EnvelopeWrongListException>()),
      );
      expect((await stateOf(a)).view.gifts, hasLength(1));
    });

    test('un sobre manipulado', () async {
      final a = track(await phoneWithFamily('A'));
      final b = track(FakePhone());
      await pairing(b).joinFromQr(await pairing(a).qrTextForPairing());
      final bytes = await share(a).buildEnvelope();
      bytes[bytes.length - 20] ^= 0x01;
      await expectLater(
        share(b).importEnvelopeBytes(bytes),
        throwsA(isA<EnvelopeAuthException>()),
      );
    });

    test('bytes que no son un sobre y texto sin sobre', () async {
      final a = track(await phoneWithFamily('A'));
      await expectLater(
        share(a).importEnvelopeBytes(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<EnvelopeFormatException>()),
      );
      await expectLater(
        share(a).importFromText('hola'),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });

    test('sin familia', () async {
      final a = track(await phoneWithFamily('A'));
      final empty = track(FakePhone());
      await expectLater(
        share(empty).importEnvelopeBytes(await share(a).buildEnvelope()),
        throwsA(isA<NoFamilyException>()),
      );
    });

    test('el otro móvil tiene la hora más de un día adelantada', () async {
      final a = track(await phoneWithFamily('A'));
      final b = track(FakePhone());
      await pairing(b).joinFromQr(await pairing(a).qrTextForPairing());
      final future = DateTime.now().add(const Duration(days: 3));
      await withClock(Clock.fixed(future), () => ctl(a).upsertGift(gift('g9')));
      final before = (await stateOf(b)).doc.canonicalJson();
      await expectLater(
        share(b).importEnvelopeBytes(await share(a).buildEnvelope()),
        throwsA(isA<ImportClockDriftException>()),
      );
      expect((await stateOf(b)).doc.canonicalJson(), before);
    });
  });

  test('importFromText acepta el enlace y el texto pegado', () async {
    final a = track(await phoneWithFamily('A'));
    final b = track(FakePhone());
    await pairing(b).joinFromQr(await pairing(a).qrTextForPairing());
    final bytes = await share(a).buildEnvelope();
    final summary = await share(b)
        .importFromText('  ${envelopeToLink(bytes)}\n');
    expect(summary.giftsAdded, 1);
  });

  for (final extension in ['.gifthuddle', '.regalos']) {
    test(
      'exportEnvelope genera .gifthuddle y se importa como $extension',
      () async {
        final dir = await Directory.systemTemp.createTemp('regalos_test');
        addTearDown(() => dir.delete(recursive: true));
        final a = track(FakePhone(temp: dir));
        await ctl(a).createFamily(deviceName: 'A');
        await ctl(a).upsertRecipient(aritz);
        await ctl(a).upsertGift(gift('g1'));
        final b = track(FakePhone(temp: dir));
        await pairing(b).joinFromQr(await pairing(a).qrTextForPairing());

        final file = await share(a).exportEnvelope();
        expect(file.name, startsWith('gift-huddle-'));
        expect(file.path.endsWith('.gifthuddle'), isTrue);
        expect(file.mimeType, 'application/vnd.gifthuddle');
        // El nombre no decide el formato: ambos transportan los mismos bytes.
        final received = await File(file.path)
            .copy('${dir.path}/copia$extension');
        final summary = await share(b)
            .importEnvelopeBytes(await received.readAsBytes());
        expect(summary.giftsAdded, 1);
      },
    );
  }

  group('enlaces', () {
    test('solo se aceptan los del dominio de la app', () {
      expect(shareTextFromUri(Uri.parse('https://$kShareHost/s#abc')), 'abc');
      expect(shareTextFromUri(Uri.parse('https://otro.example/s#abc')), isNull);
      expect(shareTextFromUri(Uri.parse('http://$kShareHost/s#abc')), isNull);
      expect(shareTextFromUri(Uri.parse('https://$kShareHost/x#abc')), isNull);
      expect(shareTextFromUri(Uri.parse('https://$kShareHost/s')), isNull);
    });
  });
}
