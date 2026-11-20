// Lote B6 del ADR 0005: el fichero `.regalos` de intercambio tras el corte al
// formato 2 del común (contenedor con el común firmado, el registro y los
// paquetes v4), contra el Worker falso. Sección 8, «Revocación y ficheros».
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/platform/task_runner.dart';
import 'package:regalos/core/sync/access_policy.dart' show requestProtection;
import 'package:regalos/core/sync/device_keys.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/exchange_file.dart';
import 'package:regalos/core/sync/family_candidate.dart' show sha256Hex;
import 'package:regalos/core/sync/family_envelope.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/sync/application/common_v2.dart';
import 'package:regalos/features/sync/application/common_v2_cutover.dart';
import 'package:regalos/features/sync/application/exchange_v2.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';

import '../helpers/fake_worker_v2.dart';
import 'v2_harness.dart';

void main() {
  late FakeWorkerV2 worker;
  late SyncV2Client client;
  late FamilyKey key;
  late MemoryV2Phone aritz;
  late MemoryV2Phone leo;
  late MemoryV2Phone nora;

  Future<void> syncAll(Iterable<MemoryV2Phone> phones) async {
    for (final p in phones) {
      await p.engine(client).sync();
    }
  }

  Future<void> revokeIn(MemoryV2Phone by, String id) async =>
      by.reg = await by.reg.withRevocation(
        await Revocation.create(keys: by.keys, by: by.record, deviceId: id),
      );

  /// Una familia de tres que ya ha pasado al formato 2 (B4).
  Future<void> cut() async {
    final phones = [aritz, leo, nora];
    await vouchAll(phones);
    await aritz.engine(client).ensureCreated();
    for (final p in [leo, nora]) {
      worker.addCredentialForTesting(
        kV2Sync,
        p.identity.deviceId,
        p.keys.serviceCredential,
      );
    }
    await syncAll([leo, nora, aritz]);
    for (final p in phones) {
      p.commonV2Ready = true;
      await client.announceCommonFormat(p.auth, kCommonFormatLatest);
    }
    await syncAll([...phones, ...phones]);
    expect(worker.minCommonFormatOf(kV2Sync), 2);
    for (final p in phones) {
      expect(p.formatFloor, 2, reason: p.identity.deviceId);
    }
  }

  /// Abre [bytes] en [p] y fusiona lo que traen.
  Future<void> import(MemoryV2Phone p, Uint8List bytes) async {
    final opened = await ExchangeV2(p).receive(bytes, nowMillis: 1000);
    await p.mergeCommon(opened.doc, fromNode: opened.fromNode);
  }

  /// [bytes] con otra cabecera (sin tocar el común).
  Uint8List rewrite(
    Uint8List bytes, {
    String? syncId,
    String? listId,
    List<Map<String, Object?>>? records,
    List<Map<String, Object?>>? packages,
    Uint8List? common,
  }) {
    final file = ExchangeFile.parse(bytes);
    final header = utf8.encode(
      jsonEncode({
        'kp': packages ?? file.packages,
        'l': listId ?? file.listId,
        'rec': records ?? file.records,
        'sid': syncId ?? file.syncId,
        'v': 1,
      }),
    );
    return Uint8List.fromList([
      0x52,
      0x58,
      1,
      ...(ByteData(4)..setUint32(0, header.length)).buffer.asUint8List(),
      ...header,
      ...common ?? file.common,
    ]);
  }

  setUp(() async {
    worker = FakeWorkerV2();
    client = worker.client();
    key = await FamilyKey.generate();
    aritz = await MemoryV2Phone.create(
      'aritz-phone',
      'aritz',
      1,
      familyKey: key,
      migrated: true,
    );
    leo = await MemoryV2Phone.create('leo-phone', 'leo', 2, familyKey: key);
    nora = await MemoryV2Phone.create('nora-phone', 'nora', 3, familyKey: key);
    aritz
      ..addPerson('aritz', 'Aritz')
      ..addPerson('leo', 'Leo')
      ..addPerson('nora', 'Nora')
      ..addGift('g-aritz', 'leo', 'Libro');
  });

  test('B6: el fichero lleva el común firmado, el registro y los paquetes '
      'v4, y ninguna clave en claro ni la de siempre', () async {
    await cut();
    leo.addGift('g-leo', 'aritz', 'Puzle');
    final bytes = await ExchangeV2(leo).export();
    expect(isExchangeFile(bytes), isTrue);
    expect(isLegacyEnvelope(bytes), isFalse);
    final file = ExchangeFile.parse(bytes);
    expect(file.syncId, kV2Sync);
    expect(isFamilyEnvelope(file.common), isTrue);
    expect(peekFamilyEnvelope(file.common).writer, 'leo-phone');
    expect(
      {for (final p in file.packages) p['to']},
      {'aritz-phone', 'nora-phone'},
    );
    // Ni la clave de siempre ni ninguna candidata viajan en claro.
    final text = latin1.decode(bytes);
    expect(text.contains(key.toBase64Url()), isFalse);
    for (final e in leo.commonKeys.keyring.entries) {
      expect(text.contains(encodeBase64Url(e.candidate.secret)), isFalse);
    }
    // El de siempre no lo abre.
    await expectLater(
      open(file.common, key: key, expectedListId: kV2List),
      throwsA(isA<EnvelopeFormatException>()),
    );
    // Aritz lo abre y fusiona; la marca no cambia.
    await import(aritz, bytes);
    expect(aritz.giftTitles, {'Libro', 'Puzle'});
    expect(aritz.formatFloor, 2);
    // Repetirlo no cambia nada.
    await import(aritz, bytes);
    expect(aritz.giftTitles, {'Libro', 'Puzle'});
  });

  test('lote 6: el fichero no lleva los regalos públicos de una persona '
      'protegida y el común local los conserva', () async {
    await cut();
    leo.addGift('g-leo', 'aritz', 'Puzle');
    leo.addGift('g-late', 'nora', 'Tardío');
    leo.doc = requestProtection(leo.doc, leo.clock, 'nora');
    final bytes = await ExchangeV2(leo).export();
    await import(aritz, bytes);
    expect(aritz.giftTitles, contains('Puzle'));
    expect(aritz.giftTitles, isNot(contains('Tardío')));
    expect(latin1.decode(bytes), isNot(contains('Tardío')));
    expect(leo.giftTitles, contains('Tardío'));
  });

  test(
    'exchange and sync keep the linked giver and unknown field stamps',
    () async {
      await cut();
      final giver = Giver(
        id: Giver.nextPersonGiverId(leo.doc, 'nora'),
        name: 'Nora',
        colorIndex: 2,
        householdPays: true,
        archived: false,
        recipientId: 'nora',
      );
      leo.addGift('given', 'aritz', 'Puzle');
      leo.addGift('secret', 'nora', 'Libro secreto');
      leo.doc = requestProtection(leo.doc, leo.clock, 'nora')
          .set(leo.clock, Collections.recipients, 'nora', {'colorIndex': 2})
          .set(leo.clock, Collections.givers, giver.id, {
            ...giver.toFields(),
            'future': {'version': 2},
          })
          .set(leo.clock, Collections.gifts, 'given', {
            'giverId': giver.id,
            'surprise': false,
          });
      final exported = leo.doc.record(Collections.givers, giver.id)!;
      final bytes = await ExchangeV2(leo).export();
      await import(aritz, bytes);
      expect(aritz.giftTitles, contains('Puzle'));
      expect(aritz.giftTitles, isNot(contains('Libro secreto')));
      final imported = aritz.doc.record(Collections.givers, giver.id)!;
      expect(Giver.fromRecord(imported), giver);
      expect(imported.fields.keys, unorderedEquals(exported.fields.keys));
      for (final field in exported.fields.keys) {
        expect(imported.field(field)?.value, exported.field(field)?.value);
        expect(imported.field(field)?.stamp, exported.field(field)?.stamp);
      }
      expect(
        FamilyView.fromDoc(aritz.doc).gifts
            .singleWhere((gift) => gift.id == 'given')
            .giverId,
        giver.id,
      );
      aritz.doc = aritz.doc.setChanged(
        aritz.clock,
        Collections.givers,
        giver.id,
        {'householdPays': false},
      );
      await import(leo, await ExchangeV2(aritz).export());
      await syncAll([aritz, leo, nora]);
      for (final phone in [aritz, leo, nora]) {
        final received = phone.doc.record(Collections.givers, giver.id)!;
        expect(received['householdPays'], isFalse);
        for (final field in [
          Giver.recipientIdField,
          'name',
          'colorIndex',
          'future',
        ]) {
          expect(received.field(field)?.value, exported.field(field)?.value);
          expect(received.field(field)?.stamp, exported.field(field)?.stamp);
        }
      }
    },
  );

  test('B6: un revocado con la clave vieja fabrica un fichero y no entra; '
      'tampoco rehabilita su credencial ni quita la revocación', () async {
    await cut();
    // Nora se queda con lo de antes: clave común vieja, registro viejo.
    final noraBefore = nora.reg;
    await revokeIn(aritz, 'nora-phone');
    await syncAll([aritz, leo, aritz]);
    nora.addGift('g-nora', 'aritz', 'Trampa');
    // Su fichero, firmado de verdad por ella con la candidata vieja y con su
    // registro, que no trae la revocación.
    final forged = await ExchangeV2(nora).export();
    for (final p in [aritz, leo]) {
      final before = p.doc.canonicalJson();
      final regBefore = p.reg;
      await expectLater(
        import(p, forged),
        throwsA(isA<ExchangeRevokedWriterException>()),
      );
      expect(p.doc.canonicalJson(), before, reason: p.identity.deviceId);
      expect(p.giftTitles.contains('Trampa'), isFalse);
      // El registro no cambia y la revocación sigue.
      expect(identical(p.reg, regBefore), isTrue);
      expect((await p.view()).revoked, contains('nora-phone'));
      expect(await p.readRetainedCommons(), isEmpty);
      expect(p.formatFloor, 2);
    }
    // Ni haciéndose pasar por Leo: no tiene su firma.
    final nView = await noraBefore.viewFor(
      me: 'nora-phone',
      mySigningKey: nora.keys.publicKeys.signing,
      livePeople: const {'aritz', 'leo', 'nora'},
    );
    final oldCandidate = nora.commonKeys.keyring.forSealingIn(
      nView,
      syncId: kV2Sync,
    )!;
    final asLeo = await sealFamilyEnvelopeForTesting(
      doc: nora.doc,
      candidate: oldCandidate,
      writer: 'leo-phone',
      writerRecord: leo.record.digest,
      revision: 9,
      signer: nora.keys,
      nonce: List<int>.filled(12, 7),
    );
    await expectLater(
      import(aritz, rewrite(forged, common: asLeo)),
      throwsA(isA<EnvelopeAuthException>()),
    );
    expect(aritz.giftTitles.contains('Trampa'), isFalse);
    // Ni con el sobre de siempre y la clave de la familia.
    final legacy = await seal(
      doc: nora.doc.toJson(),
      listId: kV2List,
      fromNode: nora.node,
      at: nora.doc.maxStamp?.pack() ?? '',
      key: key,
    );
    await expectLater(
      ExchangeV2(aritz).receive(legacy, nowMillis: 1),
      throwsA(isA<EnvelopeFormatException>()),
    );
    expect(aritz.giftTitles.contains('Trampa'), isFalse);
  });

  test('B6: un escritor legítimo reexporta su copia desde el móvil '
      'actualizado; un fichero antiguo firmado de un escritor que sigue '
      'activo también entra', () async {
    await cut();
    // Un fichero de Leo de antes de revocar a Nora (otra candidata), con un
    // cambio que no llega al servidor.
    final docBefore = leo.doc;
    leo.addGift('g-leo', 'aritz', 'Puzle');
    final older = await ExchangeV2(leo).export();
    leo.doc = docBefore;
    final olderKid = peekFamilyEnvelope(ExchangeFile.parse(older).common).kid;
    await revokeIn(aritz, 'nora-phone');
    await syncAll([aritz, leo, aritz]);
    final now = peekFamilyEnvelope(
      (await (client.getList(aritz.auth)) as V2GetOk).snapshot.common,
    ).kid;
    expect(now, isNot(olderKid));
    // El antiguo, firmado por Leo (que sigue activo), aporta lo suyo.
    expect(aritz.giftTitles.contains('Puzle'), isFalse);
    leo.addGift('g-leo-2', 'aritz', 'Cometa');
    await import(aritz, older);
    expect(aritz.giftTitles, containsAll({'Libro', 'Puzle'}));
    // Leo reexporta con la candidata de ahora: entra.
    final again = await ExchangeV2(leo).export();
    expect(peekFamilyEnvelope(ExchangeFile.parse(again).common).kid, now);
    expect(
      {for (final p in ExchangeFile.parse(again).packages) p['to']},
      {'aritz-phone'},
    );
    await import(aritz, again);
    expect(aritz.giftTitles, {'Libro', 'Puzle', 'Cometa'});
  });

  test('B6: un fichero legacy no degrada la familia', () async {
    await cut();
    final legacy = await seal(
      doc: leo.doc.toJson(),
      listId: kV2List,
      fromNode: leo.node,
      at: leo.doc.maxStamp?.pack() ?? '',
      key: key,
    );
    final before = aritz.doc.canonicalJson();
    final keys = aritz.commonKeysJson;
    await expectLater(
      ExchangeV2(aritz).receive(legacy, nowMillis: 1),
      throwsA(isA<EnvelopeFormatException>()),
    );
    expect(aritz.doc.canonicalJson(), before);
    expect(aritz.commonKeysJson, keys);
    expect(aritz.formatFloor, 2);
    expect(aritz.state.commonFormatV2, isTrue);
    // La vuelta siguiente sigue en el formato 2.
    final out = await aritz.engine(client).sync();
    expect(out.commonStatus, RemoteCommonStatus.opened);
    expect(worker.minCommonFormatOf(kV2Sync), 2);
  });

  test('B6: una generación distinta se rechaza sin tocar nada', () async {
    await cut();
    final bytes = await ExchangeV2(leo).export();
    final other = rewrite(bytes, syncId: 'WllZWllZWllZWllZWllZWQ');
    final reg = aritz.reg;
    await expectLater(
      ExchangeV2(aritz).receive(other, nowMillis: 1),
      throwsA(isA<ExchangeGenerationException>()),
    );
    expect(identical(aritz.reg, reg), isTrue);
    // Y otra lista.
    await expectLater(
      ExchangeV2(aritz)
          .receive(rewrite(bytes, listId: 'otra-lista'), nowMillis: 1),
      throwsA(isA<EnvelopeWrongListException>()),
    );
    expect(identical(aritz.reg, reg), isTrue);
  });

  test('B6: falta la clave y el fichero se conserva; entra solo al llegar '
      'la clave', () async {
    await cut();
    // Leo revoca a Nora en local y no sincroniza: su candidata de ahora ya
    // no sella, así que el fichero va con una nueva que Aritz no tiene.
    await revokeIn(leo, 'nora-phone');
    final docBefore = leo.doc;
    leo.addGift('g-file', 'aritz', 'Solo en el fichero');
    final bytes = await ExchangeV2(leo).export();
    leo.doc = docBefore;
    // Sin sus paquetes.
    final stripped = rewrite(bytes, packages: const []);
    final before = aritz.doc.canonicalJson();
    await expectLater(
      ExchangeV2(aritz).receive(stripped, nowMillis: 5),
      throwsA(
        isA<ExchangeMissingKeyException>().having((e) => e.kept, 'kept', true),
      ),
    );
    expect(aritz.doc.canonicalJson(), before);
    final retained = (await aritz.readRetainedCommons()).single;
    expect(retained.fromFile, isTrue);
    expect(retained.reason, RemoteCommonStatus.missingKey);
    expect(retained.writer, 'leo-phone');
    // Se guarda el fichero entero (con sus paquetes; B1 de la revisión de seguridad).
    expect(aritz.retainedFiles[retained.hash], stripped);
    // La clave de ese fichero queda referenciada: el recorte no la quita.
    // Otra vez el mismo fichero: no se duplica.
    await expectLater(
      ExchangeV2(aritz).receive(stripped, nowMillis: 6),
      throwsA(isA<ExchangeMissingKeyException>()),
    );
    expect(await aritz.readRetainedCommons(), hasLength(1));
    // Un retenido de fichero no cuenta como bloqueo del común del servidor.
    expect(aritz.commonKeys.blocked, isNull);
    // Leo sincroniza: reparte su candidata. Aritz la recibe y el fichero
    // guardado entra solo.
    await leo.engine(client).sync();
    await aritz.engine(client).sync();
    expect(aritz.giftTitles, contains('Solo en el fichero'));
    expect(await aritz.readRetainedCommons(), isEmpty);
    expect(aritz.retainedFiles, isEmpty);
  });

  test('B6: los retenidos de ficheros tienen su cupo y no desalojan a los '
      'del servidor', () {
    RetainedCommon r(int i, {bool file = false}) => RetainedCommon(
      hash: List.filled(64, '$i'[0]).join().replaceRange(0, 1, 'a'),
      reason: RemoteCommonStatus.missingKey,
      seenAtMillis: i,
      hasBytes: true,
      fromFile: file,
    );
    final server = [for (var i = 0; i < kMaxRetainedWaiting; i++) r(i)];
    final files = [
      for (var i = 0; i < kMaxRetainedFiles + 3; i++) r(i + 10, file: true),
    ];
    final capped = capRetained([...server, ...files]);
    expect(capped.where((x) => !x.fromFile), hasLength(kMaxRetainedWaiting));
    expect(capped.where((x) => x.fromFile), hasLength(kMaxRetainedFiles));
    // La marca de fichero se conserva al leer y al cambiar de motivo.
    final back = RetainedCommon.fromJson(files.first.toJson());
    expect(back.fromFile, isTrue);
    expect(back.withReason(RemoteCommonStatus.unknownWriter).fromFile, isTrue);
  });

  test('B6: sin la marca no se guarda ni se abre; quien ya no es de la '
      'familia no guarda', () async {
    await cut();
    final bytes = await ExchangeV2(leo).export();
    leo.formatFloor = 1;
    await expectLater(
      ExchangeV2(leo).export(),
      throwsA(isA<ExchangeNotReadyException>()),
    );
    await expectLater(
      ExchangeV2(leo).receive(bytes, nowMillis: 1),
      throwsA(isA<ExchangeNotReadyException>()),
    );
    // Nora, revocada y al tanto, no guarda.
    await revokeIn(aritz, 'nora-phone');
    // (Su credencial ya está cortada; el registro le llega por otra vía.)
    nora.reg = await nora.reg.merge(aritz.reg);
    expect((await nora.view()).revokedByOthers, isTrue);
    await expectLater(
      ExchangeV2(nora).export(),
      throwsA(isA<ExchangeNotAllowedException>()),
    );
  });

  group('B6: el contenedor', () {
    test('rechaza lo que no es, lo truncado y una versión posterior', () async {
      await cut();
      final bytes = await ExchangeV2(leo).export();
      for (final bad in [
        Uint8List(0),
        Uint8List.fromList([0x52, 0x58]),
        Uint8List.sublistView(bytes, 0, 10),
        Uint8List.fromList([...bytes.sublist(0, 2), 2, ...bytes.sublist(3)]),
      ]) {
        expect(
          () => ExchangeFile.parse(bad),
          throwsA(isA<EnvelopeFormatException>()),
        );
      }
      // Una cabecera con claves de más.
      final file = ExchangeFile.parse(bytes);
      final header = utf8.encode(
        jsonEncode({
          'kp': file.packages,
          'l': file.listId,
          'rec': file.records,
          'sid': file.syncId,
          'v': 1,
          'k': key.toBase64Url(),
        }),
      );
      final extra = Uint8List.fromList([
        0x52,
        0x58,
        1,
        ...(ByteData(4)..setUint32(0, header.length)).buffer.asUint8List(),
        ...header,
        ...file.common,
      ]);
      expect(
        () => ExchangeFile.parse(extra),
        throwsA(isA<EnvelopeFormatException>()),
      );
      // Demasiado grande.
      expect(
        () => ExchangeFile.parse(Uint8List(kMaxEnvelopeBytes + 1)),
        throwsA(isA<EnvelopeTooLargeException>()),
      );
      // Un común que no es del formato 2.
      expect(
        () => ExchangeFile.parse(rewrite(bytes, common: Uint8List(100))),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });

    test('un paquete manipulado no da la clave', () async {
      await cut();
      await revokeIn(leo, 'nora-phone');
      final bytes = await ExchangeV2(leo).export();
      final file = ExchangeFile.parse(bytes);
      final tampered = [
        for (final p in file.packages) {...p, 'e': (p['e']! as int) + 1},
      ];
      await expectLater(
        ExchangeV2(aritz)
            .receive(rewrite(bytes, packages: tampered), nowMillis: 1),
        throwsA(isA<ExchangeMissingKeyException>()),
      );
    });
  });
  group('B6: el registro del fichero no cuenta', () {
    Uint8List garbage() =>
        Uint8List.fromList([0x52, 0x47, 2, ...List<int>.filled(200, 0)]);

    /// Un fichero con [records] y un común cualquiera.
    Uint8List fileWith(
      List<Map<String, Object?>> records, {
      Uint8List? common,
    }) => ExchangeFile(
      listId: kV2List,
      syncId: kV2Sync,
      records: records,
      packages: const [],
      common: common ?? garbage(),
    ).encode();

    test('P1 y P5: un revocado no mete revocaciones (ni de Leo ni del '
        'receptor) y el registro queda idéntico', () async {
      await cut();
      await revokeIn(aritz, 'nora-phone');
      await syncAll([aritz, leo, aritz]);
      for (final target in ['leo-phone', 'aritz-phone']) {
        final rev = await Revocation.create(
          keys: nora.keys,
          by: nora.record,
          deviceId: target,
        );
        // Lo que antes iba en el registro del fichero ya no tiene sitio: la
        // cabecera solo admite fichas.
        final header = utf8.encode(
          jsonEncode({
            'kp': const <Object?>[],
            'l': kV2List,
            'rec': [nora.record.toJson()],
            'revocations': [rev.toJson()],
            'sid': kV2Sync,
            'v': 1,
          }),
        );
        final withRevocation = Uint8List.fromList([
          0x52,
          0x58,
          1,
          ...(ByteData(4)..setUint32(0, header.length)).buffer.asUint8List(),
          ...header,
          ...garbage(),
        ]);
        final reg = aritz.reg;
        await expectLater(
          ExchangeV2(aritz).receive(withRevocation, nowMillis: 1),
          throwsA(isA<EnvelopeFormatException>()),
        );
        await expectLater(
          ExchangeV2(aritz)
              .receive(fileWith([nora.record.toJson()]), nowMillis: 1),
          throwsA(isA<EnvelopeAuthException>()),
        );
        expect(identical(aritz.reg, reg), isTrue, reason: target);
      }
      final v = await aritz.view();
      expect(v.members, containsAll(['aritz-phone', 'leo-phone']));
      expect(v.revokedByOthers, isFalse);
      expect(v.revoked, {'nora-phone'});
      // Las vueltas siguen y este móvil puede guardar.
      await syncAll([aritz, leo]);
      expect((await leo.view()).revokedByOthers, isFalse);
      expect(isExchangeFile(await ExchangeV2(aritz).export()), isTrue);
    });

    test('P2 y M1: un revocado que se hace ambiguo sigue revocado; su '
        'fichero no entra ni se guarda', () async {
      await cut();
      await revokeIn(aritz, 'nora-phone');
      await syncAll([aritz, leo, aritz]);
      nora.addGift('g-nora', 'aritz', 'Trampa');
      final forged = await ExchangeV2(nora).export();
      final twin = await DeviceRecord.create(
        keys: nora.keys,
        listId: kV2List,
        deviceId: 'nora-phone',
        personId: 'leo',
      );
      // En el fichero, la ficha gemela no llega al registro.
      final reg = aritz.reg;
      await expectLater(
        ExchangeV2(aritz).receive(
          rewrite(
            forged,
            records: [...ExchangeFile.parse(forged).records, twin.toJson()],
          ),
          nowMillis: 1,
        ),
        throwsA(isA<ExchangeRevokedWriterException>()),
      );
      expect(identical(aritz.reg, reg), isTrue);
      // Y si le llega por el servidor (M1): ambigua, pero revocada.
      aritz.reg = await aritz.reg.withRecord(twin);
      final v = await aritz.view();
      expect(v.linkedSigningKey('nora-phone'), isNull);
      expect(v.explicitlyRevoked, contains('nora-phone'));
      expect(reallyRevoked(v, 'nora-phone'), isTrue);
      await expectLater(
        ExchangeV2(aritz).receive(forged, nowMillis: 1),
        throwsA(isA<EnvelopeAuthException>()),
      );
      expect(await aritz.readRetainedCommons(), isEmpty);
      expect(aritz.giftTitles.contains('Trampa'), isFalse);
    });

    test(
      'P3: un revocado de la generación anterior no entra en la nueva',
      () async {
        await cut();
        final noraBefore = nora.reg;
        await revokeIn(aritz, 'nora-phone');
        await syncAll([aritz, leo, aritz]);
        const sync2 = 'WllZWllZWllZWllZWllZWQ';
        final aritz2 = await MemoryV2Phone.create(
          'aritz-phone',
          'aritz',
          1,
          familyKey: await FamilyKey.generate(),
          syncId: sync2,
          doc: aritz.doc,
        );
        aritz2.enableCommonV2();
        final nora2 = await MemoryV2Phone.create(
          'nora-phone',
          'nora',
          3,
          familyKey: key,
          syncId: sync2,
          doc: nora.doc,
        );
        nora2
          ..enableCommonV2()
          ..reg = noraBefore
          ..addGift('g-nora', 'aritz', 'Trampa');
        final file = await ExchangeV2(nora2).export();
        final reg = aritz2.reg;
        await expectLater(
          ExchangeV2(aritz2).receive(file, nowMillis: 1),
          throwsA(
            isA<ExchangeMissingKeyException>().having(
              (e) => e.kept,
              'kept',
              false,
            ),
          ),
        );
        expect(identical(aritz2.reg, reg), isTrue);
        expect((await aritz2.view()).members, ['aritz-phone']);
        expect(aritz2.giftTitles.contains('Trampa'), isFalse);
        expect(await aritz2.readRetainedCommons(), isEmpty);
        // Su fichero siguiente no reparte nada a Nora.
        final out = ExchangeFile.parse(await ExchangeV2(aritz2).export());
        expect(out.packages, isEmpty);
      },
    );

    test('P4: un desconocido no llena el registro: como mucho 64 fichas, '
        'que nunca se guardan, y las vueltas siguen', () async {
      await cut();
      final junk = <Map<String, Object?>>[];
      for (var i = 0; i < kMaxExchangeRecords + 1; i++) {
        final k = await DeviceKeys.fromSeedsForTesting(
          agreementSeed: List<int>.filled(32, 50 + i),
          signingSeed: List<int>.filled(32, 150 + i),
          serviceCredential: List<int>.filled(32, 7),
        );
        junk.add(
          (await DeviceRecord.create(
            keys: k,
            listId: kV2List,
            deviceId: 'junk-$i',
            personId: null,
          )).toJson(),
        );
      }
      expect(
        () => ExchangeFile.parse(rewrite(fileWith(const []), records: junk)),
        throwsA(isA<EnvelopeTooLargeException>()),
      );
      // Al guardar, un error claro (el de «demasiado grande»).
      expect(
        () => ExchangeFile(
          listId: kV2List,
          syncId: kV2Sync,
          records: junk,
          packages: const [],
          common: garbage(),
        ),
        throwsA(isA<EnvelopeTooLargeException>()),
      );
      // 64 fichas basura junto a un común auténtico de Leo: entra lo de Leo
      // y el registro no cambia.
      leo.addGift('g-leo', 'nora', 'Puzle');
      final legit = await ExchangeV2(leo).export();
      final reg = aritz.reg;
      await import(
        aritz,
        rewrite(
          legit,
          records: [
            ...ExchangeFile.parse(legit).records,
            ...junk,
          ].take(kMaxExchangeRecords).toList(),
        ),
      );
      expect(aritz.giftTitles, contains('Puzle'));
      expect(identical(aritz.reg, reg), isTrue);
      aritz.addGift('g-new', 'leo', 'Nuevo');
      await aritz.engine(client).sync();
      await leo.engine(client).sync();
      expect(leo.giftTitles, contains('Nuevo'));
    });

    test('P6: un común auténtico de Leo con fichas ajenas pegadas entra sin '
        'tocar el registro', () async {
      await cut();
      await revokeIn(aritz, 'nora-phone');
      await syncAll([aritz, leo, aritz]);
      leo.addGift('g-leo', 'nora', 'Puzle');
      final legit = await ExchangeV2(leo).export();
      final twin = await DeviceRecord.create(
        keys: nora.keys,
        listId: kV2List,
        deviceId: 'leo-phone',
        personId: 'nora',
      );
      final reg = aritz.reg;
      await import(
        aritz,
        rewrite(
          legit,
          records: [
            ...ExchangeFile.parse(legit).records,
            nora.record.toJson(),
            twin.toJson(),
          ],
        ),
      );
      expect(aritz.giftTitles, contains('Puzle'));
      expect(identical(aritz.reg, reg), isTrue);
      final v = await aritz.view();
      expect(v.members, containsAll(['aritz-phone', 'leo-phone']));
      expect(v.revoked, {'nora-phone'});
    });

    test('las fichas del fichero de otro tipo que el del id aquí no '
        'cuentan', () async {
      await cut();
      final view = await aritz.view();
      final asWeb = await DeviceRecord.create(
        keys: leo.keys,
        listId: kV2List,
        deviceId: 'leo-phone',
        personId: 'leo',
        seq: 2,
        kind: DeviceKind.web,
      );
      final asMobile = await DeviceRecord.create(
        keys: leo.keys,
        listId: kV2List,
        deviceId: 'leo-phone',
        personId: 'nora',
        seq: 2,
      );
      final out = await linkedFileRecords(
        [asWeb.toJson(), asMobile.toJson()],
        view,
        aritz.reg,
      );
      expect([for (final r in out) r.digest], [asMobile.digest]);
    });

    test('un retenido sin paquete se sustituye por el mismo fichero con '
        'paquete para este móvil', () async {
      await cut();
      await revokeIn(leo, 'nora-phone');
      final bytes = await ExchangeV2(leo).export();
      final file = ExchangeFile.parse(bytes);
      final stripped = rewrite(bytes, packages: const []);
      // Un paquete para Aritz que hoy no se abre (firma rota).
      final unusable = rewrite(
        bytes,
        packages: [
          for (final p in file.packages)
            if (p['to'] == 'aritz-phone') {...p, 'e': (p['e']! as int) + 1},
        ],
      );
      final hash = sha256Hex(file.common);
      for (final (input, stored) in [
        (stripped, stripped),
        (unusable, unusable),
        (stripped, unusable),
      ]) {
        await expectLater(
          ExchangeV2(aritz).receive(input, nowMillis: 1),
          throwsA(isA<ExchangeMissingKeyException>()),
        );
        expect(aritz.retainedFiles[hash], stored);
      }
      expect(await aritz.readRetainedCommons(), hasLength(1));
    });

    test('explicitlyRevoked: solo lo revocado, no lo ambiguo', () async {
      await cut();
      await revokeIn(aritz, 'nora-phone');
      // Una ficha gemela de Leo (misma clave y `seq`) lo hace ambiguo.
      aritz.reg = await aritz.reg.withRecord(
        await DeviceRecord.create(
          keys: leo.keys,
          listId: kV2List,
          deviceId: 'leo-phone',
          personId: 'nora',
        ),
      );
      final v = await aritz.view();
      expect(v.explicitlyRevoked, {'nora-phone'});
      expect(v.revoked, {'nora-phone', 'leo-phone'});
      expect(reallyRevoked(v, 'leo-phone'), isFalse);
      expect(reallyRevoked(v, 'nora-phone'), isTrue);
    });

    test('el fichero solo lleva las fichas del escritor, el creador y la '
        'audiencia', () async {
      await cut();
      final file = ExchangeFile.parse(await ExchangeV2(leo).export());
      expect(file.records, hasLength(3));
      expect(
        {for (final r in file.records) DeviceRecord.fromJson(r).deviceId},
        {'aritz-phone', 'leo-phone', 'nora-phone'},
      );
    });

    test('unknownWriter autenticado: se guarda y entra al aprobarlo', () async {
      await cut();
      final docBefore = leo.doc;
      leo.addGift('g-leo', 'nora', 'De Leo');
      final file = await ExchangeV2(leo).export();
      leo.doc = docBefore;
      // Leo cambia de persona: aquí está pendiente de aprobar.
      final leoNew = await DeviceRecord.create(
        keys: leo.keys,
        listId: kV2List,
        deviceId: 'leo-phone',
        personId: 'aritz',
        seq: 2,
      );
      aritz.reg = await aritz.reg.withRecord(leoNew);
      expect((await aritz.view()).member('leo-phone'), isNull);
      final reg = aritz.reg;
      await expectLater(
        ExchangeV2(aritz).receive(file, nowMillis: 1),
        throwsA(
          isA<ExchangeMissingKeyException>().having(
            (e) => e.kept,
            'kept',
            true,
          ),
        ),
      );
      expect(identical(aritz.reg, reg), isTrue);
      final retained = (await aritz.readRetainedCommons()).single;
      expect(retained.reason, RemoteCommonStatus.unknownWriter);
      expect(retained.fromFile, isTrue);
      // Aritz lo aprueba: la vuelta siguiente lo abre (su ficha anterior,
      // con la misma clave, vale) y lo fusiona.
      aritz.reg = await aritz.reg.withVouch(
        await Vouch.create(
          keys: aritz.keys,
          voucher: aritz.record,
          record: leoNew,
        ),
      );
      await aritz.engine(client).sync();
      expect(aritz.giftTitles, contains('De Leo'));
      expect(await aritz.readRetainedCommons(), isEmpty);
    });

    test('un retenido cuyo escritor se revoca después no entra', () async {
      await cut();
      await revokeIn(leo, 'nora-phone');
      final docBefore = leo.doc;
      leo.addGift('g-file', 'nora', 'Del revocado');
      final bytes = await ExchangeV2(leo).export();
      leo.doc = docBefore;
      await expectLater(
        ExchangeV2(aritz)
            .receive(rewrite(bytes, packages: const []), nowMillis: 1),
        throwsA(isA<ExchangeMissingKeyException>()),
      );
      await revokeIn(aritz, 'leo-phone');
      await aritz.engine(client).sync();
      expect(aritz.giftTitles.contains('Del revocado'), isFalse);
      final retained = (await aritz.readRetainedCommons()).single;
      expect(retained.reason, RemoteCommonStatus.revokedWriter);
      expect(retained.fromFile, isTrue);
    });

    test('el cupo de punta a punta: el quinto fichero que espera desaloja '
        'al más antiguo y borra sus bytes', () async {
      await cut();
      await revokeIn(leo, 'nora-phone');
      final hashes = <String>[];
      for (var i = 0; i < kMaxRetainedFiles + 1; i++) {
        leo.addGift('g-$i', 'nora', 'Regalo $i');
        final bytes = rewrite(
          await ExchangeV2(leo).export(),
          packages: const [],
        );
        await expectLater(
          ExchangeV2(aritz).receive(bytes, nowMillis: 100 + i),
          throwsA(isA<ExchangeMissingKeyException>()),
        );
        hashes.add(sha256Hex(ExchangeFile.parse(bytes).common));
      }
      final retained = await aritz.readRetainedCommons();
      expect(retained, hasLength(kMaxRetainedFiles));
      expect(retained.map((r) => r.hash), isNot(contains(hashes.first)));
      expect(aritz.retainedFiles.containsKey(hashes.first), isFalse);
      expect(aritz.retainedFiles, hasLength(kMaxRetainedFiles));
    });

    test('abrir y guardar no bloquean la interfaz: todo lo criptográfico va '
        'por el ejecutor de tareas', () async {
      await cut();
      var calls = 0;
      Future<T> counting<T>(FutureOr<T> Function() task) {
        calls++;
        return runTask(task);
      }

      leo.addGift('g-leo', 'nora', 'Puzle');
      final bytes = await ExchangeV2(leo, run: counting).export();
      expect(calls, 1);
      final opened = await ExchangeV2(
        aritz,
        run: counting,
      ).receive(bytes, nowMillis: 1);
      expect(calls, 2);
      expect(opened.doc, isNotNull);
    });
  });
}
