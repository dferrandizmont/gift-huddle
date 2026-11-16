// Lote B3 del ADR 0005: el motor móvil con la clave común por época
// (interruptor `commonFormatV2`), contra el Worker falso.
import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/device_keys.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_candidate.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/family_envelope.dart';
import 'package:regalos/core/sync/family_key_bundle.dart';
import 'package:regalos/core/sync/key_bundle.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/sync/application/common_v2.dart';
import 'package:regalos/features/sync/application/common_v2_cutover.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';
import 'package:regalos/features/sync/data/sync_transport_common.dart';
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

  Future<V2Snapshot> snapshot() async =>
      (await client.getList(aritz.auth) as V2GetOk).snapshot;

  Future<String> serverKid() async =>
      peekFamilyEnvelope((await snapshot()).common).kid;

  Future<String?> sealingKid(MemoryV2Phone p) async =>
      p.commonKeys.keyring.forSealingIn(await p.view(), syncId: kV2Sync)?.kid;

  Future<FamilyDoc> openAs(MemoryV2Phone p, Uint8List bytes) async =>
      (await openFamilyEnvelope(
        bytes,
        expectedListId: kV2List,
        expectedSyncId: kV2Sync,
        resolveWriter: commonWriterResolver(await p.view(), p.reg),
        keyring: p.commonKeys.keyring,
      )).doc;

  Set<String> titles(FamilyDoc doc) => {
    for (final r
        in doc.collections[Collections.gifts]?.values ?? const <SyncRecord>[])
      if (!r.isDeleted) r['title'] as String,
  };

  /// Sube una instantánea a mano (otro escritor o un servidor que manipula).
  Future<void> putRaw(
    MemoryV2Phone as, {
    Uint8List? common,
    List<Map<String, Object?>>? packages,
  }) async {
    final s = await snapshot();
    final result = await client.putList(
      as.auth,
      version: s.version,
      body: V2SnapshotUpload(
        common: common ?? s.common,
        registry: Map<String, Object?>.from(s.registry! as Map),
        keyPackages: packages ?? s.keyPackages,
      ),
    );
    expect(result, isA<V2WriteOk>());
  }

  Future<void> revokeIn(MemoryV2Phone by, String id) async =>
      by.reg = await by.reg.withRevocation(
        await Revocation.create(keys: by.keys, by: by.record, deviceId: id),
      );

  /// Un móvil sin persona que Aritz añade a la familia (cambia el contexto).
  Future<MemoryV2Phone> addDevice(String id, int seed) async {
    final x = await MemoryV2Phone.create(id, null, seed, familyKey: key);
    aritz.reg = await (await aritz.reg.merge(x.reg)).withVouch(
      await Vouch.create(
        keys: aritz.keys,
        voucher: aritz.record,
        record: x.record,
      ),
    );
    return x;
  }

  /// Avala solo las parejas [pairs] (en los dos sentidos) entre [all].
  Future<void> vouchPairs(
    List<MemoryV2Phone> all,
    List<(MemoryV2Phone, MemoryV2Phone)> pairs,
  ) async {
    var registry = DeviceRegistry.empty(kV2List);
    for (final p in all) {
      registry = await registry.merge(p.reg);
    }
    for (final (a, b) in pairs) {
      registry = await registry.withVouch(
        await Vouch.create(keys: a.keys, voucher: a.record, record: b.record),
      );
      registry = await registry.withVouch(
        await Vouch.create(keys: b.keys, voucher: b.record, record: a.record),
      );
    }
    for (final p in all) {
      p.reg = registry;
    }
  }

  Future<void> syncAll(Iterable<MemoryV2Phone> phones) async {
    for (final p in phones) {
      await p.engine(client).sync();
    }
  }

  Future<void> start(List<MemoryV2Phone> phones, {bool on = true}) async {
    if (on) {
      for (final p in phones) {
        p.enableCommonV2();
      }
    }
    await vouchAll(phones);
    await phones.first.engine(client).ensureCreated();
    for (final p in phones.skip(1)) {
      worker.addCredentialForTesting(
        kV2Sync,
        p.identity.deviceId,
        p.keys.serviceCredential,
      );
    }
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

  test('B3: con el interruptor apagado el común sigue en el formato 1, sin '
      'paquetes v4 ni llavero común', () async {
    await start([aritz, leo, nora], on: false);
    await syncAll([leo, nora, aritz]);
    final s = await snapshot();
    expect(isFamilyEnvelope(s.common), isFalse);
    expect(s.keyPackages.where(FamilyKeyBundle.isV4), isEmpty);
    expect(aritz.commonKeysJson, isNull);
    expect(leo.giftTitles, {'Libro'});
  });

  for (final n in [2, 3]) {
    test('B3: $n móviles con el interruptor sincronizan el común sellado con '
        'una candidata', () async {
      final phones = [aritz, leo, nora].take(n).toList();
      await start(phones);
      var s = await snapshot();
      expect(isFamilyEnvelope(s.common), isTrue);
      // La clave de siempre ya no lo abre.
      await expectLater(
        open(s.common, key: key, expectedListId: kV2List),
        throwsA(isA<EnvelopeException>()),
      );
      final kid = peekFamilyEnvelope(s.common).kid;
      final packages = s.keyPackages.where(FamilyKeyBundle.isV4).toList();
      expect(packages, hasLength(n - 1));
      expect(packages.every((p) => p['kid'] == kid), isTrue);

      await leo.engine(client).sync();
      expect(leo.giftTitles, {'Libro'});
      leo.addGift('g-leo', 'aritz', 'Puzle');
      final out = await leo.engine(client).sync();
      expect(out.uploaded, isTrue);
      expect(out.commonStatus, RemoteCommonStatus.opened);
      await syncAll(phones);
      for (final p in phones) {
        expect(p.giftTitles, {'Libro', 'Puzle'}, reason: p.identity.deviceId);
        expect(await sealingKid(p), kid);
      }
      s = await snapshot();
      expect(peekFamilyEnvelope(s.common).kid, kid);
      // Una sola candidata: nadie crea otra si ya hay una que sella.
      for (final p in phones) {
        expect(p.commonKeys.keyring.length, 1);
      }
    });
  }

  test('B3: revocar a uno rota la clave; el revocado no abre lo nuevo y los '
      'demás sí', () async {
    await start([aritz, leo, nora]);
    await syncAll([leo, nora, aritz]);
    final k1 = await serverKid();
    await revokeIn(aritz, 'nora-phone');
    aritz.addGift('g-2', 'leo', 'Tren');
    await aritz.engine(client).sync();
    final k2 = await serverKid();
    expect(k2, isNot(k1));
    final candidate = aritz.commonKeys.keyring.entry(k2)!.candidate;
    expect(candidate.audience.map((m) => m.deviceId), [
      'aritz-phone',
      'leo-phone',
    ]);
    final s = await snapshot();
    expect(
      s.keyPackages.where(
        (p) => familyPackageKid(p) == k2 && p['to'] == 'nora-phone',
      ),
      isEmpty,
    );
    // Lo de Aritz para Nora con la clave vieja ya no está (sustituido).
    expect(
      s.keyPackages.where(
        (p) => p['from'] == 'aritz-phone' && familyPackageKid(p) == k1,
      ),
      isEmpty,
    );
    await leo.engine(client).sync();
    expect(leo.giftTitles, {'Libro', 'Tren'});
    expect(await sealingKid(leo), k2);
    // Nora conserva la vieja, pero no abre el común nuevo.
    expect(nora.commonKeys.keyring.entry(k1), isNotNull);
    await expectLater(
      openAs(nora, s.common),
      throwsA(isA<EnvelopeMissingKeyException>()),
    );
    expect(worker.devicesOf(kV2Sync)['nora-phone'], isTrue);
    await expectLater(nora.engine(client).sync(), throwsA(anything));
  });

  test('B3: dos creadores a la vez con 412 convergen a la misma kid (la '
      'menor)', () async {
    await start([aritz, leo, nora]);
    await syncAll([leo, nora, aritz]);
    // Los dos ven la misma revocación: los dos crean candidata.
    final revocation = await Revocation.create(
      keys: aritz.keys,
      by: aritz.record,
      deviceId: 'nora-phone',
    );
    aritz.reg = await aritz.reg.withRevocation(revocation);
    leo.reg = await leo.reg.withRevocation(revocation);
    worker.beforePut = (_) => aritz.engine(client).sync();
    await leo.engine(client).sync();
    expect(worker.beforePut, isNull);
    await syncAll([aritz, leo, aritz]);
    final ctx = epochContextOf(await aritz.view(), syncId: kV2Sync);
    String ownKid(MemoryV2Phone p) => p.commonKeys.keyring.entries
        .singleWhere((e) => e.own && e.candidate.epochContext == ctx)
        .candidate
        .kid;
    final ka = ownKid(aritz);
    final kl = ownKid(leo);
    expect(ka, isNot(kl));
    final min = ka.compareTo(kl) < 0 ? ka : kl;
    expect(await serverKid(), min);
    expect(await sealingKid(aritz), min);
    expect(await sealingKid(leo), min);
    // Del otro solo quedan en el servidor paquetes de la elegida.
    final s = await snapshot();
    expect(
      s.keyPackages.where(FamilyKeyBundle.isV4).map((p) => p['kid']).toSet(),
      {min},
    );
  });

  test('B3: un móvil desconectado durante semanas (tres rotaciones) recibe '
      'la clave actual, fusiona y no pierde nada', () async {
    await start([aritz, leo, nora]);
    await syncAll([leo, nora, aritz]);
    final k1 = await serverKid();
    nora.addGift('g-nora', 'aritz', 'Bici');
    final seen = <String>{k1};
    // Rotación 1: entra un móvil; 2: se revoca; 3: entra otro.
    await addDevice('extra-1', 11);
    await syncAll([aritz, leo]);
    seen.add(await serverKid());
    await revokeIn(aritz, 'extra-1');
    aritz.addGift('g-a2', 'leo', 'Cometa');
    await syncAll([aritz, leo]);
    seen.add(await serverKid());
    await addDevice('extra-2', 12);
    leo.addGift('g-l2', 'aritz', 'Taza');
    await syncAll([aritz, leo, aritz]);
    final current = await serverKid();
    seen.add(current);
    expect(seen, hasLength(4));
    // Ningún paquete de Aritz de las claves sustituidas sigue en el servidor.
    final before = await snapshot();
    expect(
      before.keyPackages
          .where((p) => p['from'] == 'aritz-phone')
          .map(familyPackageKid)
          .toSet(),
      {current},
    );

    await withClock(Clock.fixed(DateTime(2027, 1, 20)), () async {
      final out = await nora.engine(client).sync();
      expect(out.commonStatus, RemoteCommonStatus.opened);
      expect(out.uploaded, isTrue);
    });
    expect(nora.giftTitles, {'Libro', 'Cometa', 'Taza', 'Bici'});
    expect(await sealingKid(nora), current);
    await syncAll([aritz, leo]);
    expect(aritz.giftTitles, {'Libro', 'Cometa', 'Taza', 'Bici'});
    expect(leo.giftTitles, {'Libro', 'Cometa', 'Taza', 'Bici'});
  });

  group('B3: cierre en cada punto de persistencia', () {
    for (final at in [1, 2, 3, 4]) {
      test('cierre en el guardado $at de la vuelta que rota: al reiniciar '
          'nada publicado queda sin clave', () async {
        await start([aritz, leo, nora]);
        await syncAll([leo, nora, aritz]);
        final k1 = await serverKid();
        await addDevice('extra-1', 11);
        aritz.addGift('g-2', 'nora', 'Tren');
        aritz.failCommonKeySaveAt = aritz.commonKeySaves + at;
        await expectLater(
          aritz.engine(client).sync(),
          throwsA(isA<StateError>()),
        );
        final published = await serverKid();
        if (at < 4) {
          // Sin guardar candidata e intención no se publica nada.
          expect(published, k1);
        } else {
          // El PUT entró antes del cierre: su clave ya estaba guardada.
          expect(published, isNot(k1));
        }
        expect(aritz.commonKeys.keyring.entry(published), isNotNull);
        aritz.failCommonKeySaveAt = null;
        await aritz.engine(client).sync();
        final k2 = await serverKid();
        expect(k2, isNot(k1));
        if (at == 4) expect(k2, published);
        await syncAll([leo, nora]);
        for (final p in [leo, nora]) {
          expect(p.giftTitles, {'Libro', 'Tren'}, reason: p.identity.deviceId);
          expect(titles(await openAs(p, (await snapshot()).common)), {
            'Libro',
            'Tren',
          });
        }
      });
    }

    test('PUT aceptado con la respuesta perdida: el móvil abre su propio '
        'común al volver', () async {
      await start([aritz, leo, nora]);
      await syncAll([leo, nora, aritz]);
      final k1 = await serverKid();
      await addDevice('extra-1', 11);
      aritz.addGift('g-2', 'nora', 'Tren');
      var armed = true;
      worker.tamper = (method, uri, response) {
        if (method == 'PUT' && armed) {
          armed = false;
          return SyncResponse(500, const {}, Uint8List(0));
        }
        return response;
      };
      await expectLater(
        aritz.engine(client).sync(),
        throwsA(isA<SyncTransportException>()),
      );
      final k2 = await serverKid();
      expect(k2, isNot(k1));
      final out = await aritz.engine(client).sync();
      expect(out.commonStatus, RemoteCommonStatus.opened);
      expect(await serverKid(), k2);
      await leo.engine(client).sync();
      expect(leo.giftTitles, {'Libro', 'Tren'});
    });

    test('sin red justo antes del PUT: se vuelve a usar la misma candidata '
        'guardada', () async {
      await start([aritz, leo, nora]);
      await syncAll([leo, nora, aritz]);
      final k1 = await serverKid();
      await addDevice('extra-1', 11);
      var armed = true;
      worker.tamper = (method, uri, response) {
        if (method == 'GET' && armed) {
          armed = false;
          worker.offline = true;
        }
        return response;
      };
      await expectLater(
        aritz.engine(client).sync(),
        throwsA(isA<SyncTransportException>()),
      );
      worker
        ..tamper = null
        ..offline = false;
      expect(await serverKid(), k1);
      final saved = aritz.commonKeys.keyring.entries
          .where((e) => e.own && e.candidate.kid != k1)
          .single
          .candidate
          .kid;
      expect(aritz.commonKeys.outbox, isNotEmpty);
      await aritz.engine(client).sync();
      expect(await serverKid(), saved);
      expect(aritz.commonKeys.outbox, isEmpty);
      await leo.engine(client).sync();
      expect(await sealingKid(leo), saved);
    });
  });

  group('B3: común remoto que no se abre', () {
    /// Leo publica un común con una candidata que solo tiene él (sin
    /// paquetes): un escritor activo cuya clave no llega.
    Future<FamilyCandidate> leoPublishesUnopenable() async {
      final view = await leo.view();
      final only = await FamilyCandidate.generate(
        view,
        keys: leo.keys,
        syncId: kV2Sync,
      );
      leo.addGift('g-secreto', 'aritz', 'Secreto');
      await putRaw(
        leo,
        common: await sealFamilyEnvelope(
          doc: leo.doc,
          candidate: only,
          writer: view.self,
          revision: 7,
          signer: leo.keys,
        ),
      );
      return only;
    }

    /// Leo sella basura con la clave buena que todos tienen: firma válida,
    /// candidata exacta en el llavero, y no se puede leer.
    Future<Uint8List> leoPublishesGarbage(int fill) async {
      final view = await leo.view();
      final k = leo.commonKeys.keyring.entry(await serverKid())!.candidate;
      final bytes = await sealFamilyEnvelopeForTesting(
        doc: leo.doc,
        candidate: k,
        writer: 'leo-phone',
        writerRecord: view.self.recordDigest,
        revision: 10 + fill,
        signer: leo.keys,
        nonce: List<int>.filled(12, fill),
        bodyForTesting: List<int>.filled(16, fill),
      );
      await putRaw(leo, common: bytes);
      return bytes;
    }

    test('A2: falta la clave de un escritor activo: se espera sin plazo, con '
        'el escritor en el aviso; al revocarlo se sustituye ya', () async {
      await start([aritz, leo, nora]);
      await syncAll([leo, nora, aritz]);
      await leoPublishesUnopenable();
      final blocked = (await snapshot()).common;
      aritz.addGift('g-a2', 'nora', 'Cometa');
      for (var i = 0; i < 3 * kCommonUnreadableRounds; i++) {
        final out = await withClock(
          Clock.fixed(DateTime(2026, 12, 1).add(Duration(days: i))),
          () => aritz.engine(client).sync(),
        );
        expect(out.commonStatus, RemoteCommonStatus.missingKey);
        expect(out.commonReplaced, isFalse);
      }
      expect((await snapshot()).common, blocked);
      expect(aritz.state.health!.commonBlocked, isTrue);
      expect(aritz.state.health!.commonBlockedWriter, 'leo-phone');
      final retained = (await aritz.readRetainedCommons()).single;
      expect(retained.reason, RemoteCommonStatus.missingKey);
      expect(aritz.retainedFiles[retained.hash], blocked);
      // Una persona decide: revocar a Leo sustituye el común en esa vuelta.
      await revokeIn(aritz, 'leo-phone');
      final out = await aritz.engine(client).sync();
      expect(out.commonStatus, RemoteCommonStatus.revokedWriter);
      expect(out.commonReplaced, isTrue);
      expect(aritz.state.health!.commonBlocked, isFalse);
      expect(aritz.giftTitles, {'Libro', 'Cometa'});
      await nora.engine(client).sync();
      expect(nora.giftTitles, {'Libro', 'Cometa'});
    });

    test('falta la clave y llega después: se abre, se fusiona y deja de '
        'estar retenido', () async {
      await start([aritz, leo, nora]);
      await syncAll([leo, nora, aritz]);
      final only = await leoPublishesUnopenable();
      final out = await aritz.engine(client).sync();
      expect(out.commonStatus, RemoteCommonStatus.missingKey);
      expect(await aritz.readRetainedCommons(), hasLength(1));
      final bundle = await FamilyKeyBundle.seal(
        sender: leo.keys,
        view: await leo.view(),
        syncId: kV2Sync,
        toDevice: 'aritz-phone',
        candidate: only,
      );
      await putRaw(
        leo,
        packages: [...(await snapshot()).keyPackages, bundle.toJson()],
      );
      final again = await aritz.engine(client).sync();
      expect(again.commonStatus, RemoteCommonStatus.opened);
      expect(aritz.giftTitles, {'Libro', 'Secreto'});
      expect(await aritz.readRetainedCommons(), isEmpty);
      expect(aritz.retainedFiles, isEmpty);
      expect(aritz.state.health!.commonBlocked, isFalse);
    });

    test(
      'un común falso se sustituye ya; de él solo se guarda el resumen',
      () async {
        await start([aritz, leo, nora]);
        await syncAll([leo, nora, aritz]);
        final kid = await serverKid();
        final junk = Uint8List.fromList([0x52, 0x47, 0x02, 0, 3, 1, 2, 3, 4]);
        await putRaw(nora, common: junk);
        final out = await aritz.engine(client).sync();
        expect(out.commonStatus, RemoteCommonStatus.forged);
        expect(out.commonReplaced, isTrue);
        expect(await serverKid(), kid);
        final retained = (await aritz.readRetainedCommons()).single;
        expect(retained.hasBytes, isFalse);
        expect(retained.hash, sha256Hex(junk));
        expect(aritz.retainedFiles, isEmpty);
        await leo.engine(client).sync();
        expect(leo.giftTitles, {'Libro'});
      },
    );

    test(
      'A2/P6: basura cifrada con la clave buena (unreadable) se sustituye '
      'tras las vueltas; un segundo común ilegible empieza de cero',
      () async {
        await start([aritz, leo, nora]);
        await syncAll([leo, nora, aritz]);
        final first = await leoPublishesGarbage(1);
        for (var i = 0; i < kCommonUnreadableRounds - 1; i++) {
          final out = await aritz.engine(client).sync();
          expect(out.commonStatus, RemoteCommonStatus.unreadable);
          expect(out.commonReplaced, isFalse);
        }
        expect((await snapshot()).common, first);
        expect(aritz.commonKeys.blocked!.rounds, kCommonUnreadableRounds - 1);
        // Otro común ilegible distinto: el plazo vuelve a empezar.
        final second = await leoPublishesGarbage(2);
        for (var i = 0; i < kCommonUnreadableRounds - 1; i++) {
          final out = await aritz.engine(client).sync();
          expect(out.commonReplaced, isFalse, reason: 'vuelta $i');
        }
        expect((await snapshot()).common, second);
        expect(aritz.commonKeys.blocked!.rounds, kCommonUnreadableRounds - 1);
        final out = await aritz.engine(client).sync();
        expect(out.commonStatus, RemoteCommonStatus.unreadable);
        expect(out.commonReplaced, isTrue);
        expect(isFamilyEnvelope((await snapshot()).common), isTrue);
        expect(titles(await openAs(leo, (await snapshot()).common)), {'Libro'});
        expect(
          (await aritz.readRetainedCommons()).map((r) => r.reason).toSet(),
          {RemoteCommonStatus.unreadable},
        );
      },
    );

    test('A2: unknownWriter de un id sin presencia en el registro se sustituye '
        'tras las vueltas', () async {
      await start([aritz, leo, nora]);
      await syncAll([leo, nora, aritz]);
      final ghostKeys = await DeviceKeys.fromSeedsForTesting(
        agreementSeed: List<int>.filled(32, 77),
        signingSeed: List<int>.filled(32, 78),
        serviceCredential: List<int>.filled(32, 79),
      );
      final ghost = await DeviceRecord.create(
        keys: ghostKeys,
        listId: kV2List,
        deviceId: 'ghost-phone',
        personId: null,
      );
      final member = AudienceMember('ghost-phone', ghost.digest);
      final candidate = await FamilyCandidate.create(
        listId: kV2List,
        syncId: kV2Sync,
        epochNumber: 1,
        epochContext: 'a' * 64,
        creator: 'ghost-phone',
        creatorRecord: ghost.digest,
        audience: [member],
        secret: List<int>.filled(32, 5),
        creatorKeys: ghostKeys,
      );
      await putRaw(
        nora,
        common: await sealFamilyEnvelopeForTesting(
          doc: FamilyDoc.empty(kV2List),
          candidate: candidate,
          writer: 'ghost-phone',
          writerRecord: ghost.digest,
          revision: 1,
          signer: ghostKeys,
          nonce: List<int>.filled(12, 3),
        ),
      );
      for (var i = 0; i < kCommonUnreadableRounds; i++) {
        final out = await aritz.engine(client).sync();
        expect(out.commonStatus, RemoteCommonStatus.unknownWriter);
        expect(out.commonReplaced, i == kCommonUnreadableRounds - 1);
      }
      expect(
        peekFamilyEnvelope((await snapshot()).common).writer,
        'aritz-phone',
      );
    });

    for (final genuine in [false, true]) {
      test(
        'N1/PA: un común que dice ser de un dispositivo conocido no activo '
        '${genuine ? "y lo firma él: se espera y se le nombra" : "sin su firma: es falso, se sustituye ya y no se culpa a nadie"}',
        () async {
          for (final p in [aritz, leo, nora]) {
            p.enableCommonV2();
          }
          await vouchPairs([aritz, leo, nora], [(aritz, leo), (leo, nora)]);
          await aritz.engine(client).ensureCreated();
          final ghost = await MemoryV2Phone.create(
            'ghost-phone',
            null,
            9,
            familyKey: key,
          );
          for (final p in [leo, nora, ghost]) {
            worker.addCredentialForTesting(
              kV2Sync,
              p.identity.deviceId,
              p.keys.serviceCredential,
            );
          }
          await syncAll([leo, nora, aritz]);
          // Aritz revoca a Leo: Nora queda como dispositivo conocido no activo.
          await revokeIn(aritz, 'leo-phone');
          await aritz.engine(client).sync();
          expect((await aritz.view()).member('nora-phone'), isNull);
          final noraDigest = nora.record.digest;
          final signer = genuine ? nora : ghost;
          final fake = await FamilyCandidate.create(
            listId: kV2List,
            syncId: kV2Sync,
            epochNumber: 1,
            epochContext: 'a' * 64,
            creator: 'nora-phone',
            creatorRecord: noraDigest,
            audience: [AudienceMember('nora-phone', noraDigest)],
            secret: List<int>.filled(32, 7),
            creatorKeys: signer.keys,
          );
          // Lo sube una credencial sin respaldo (o el servidor).
          await putRaw(
            ghost,
            common: await sealFamilyEnvelopeForTesting(
              doc: FamilyDoc.empty(kV2List),
              candidate: fake,
              writer: 'nora-phone',
              writerRecord: noraDigest,
              revision: 1,
              signer: signer.keys,
              nonce: Uint8List(12),
            ),
          );
          aritz.addGift('g-2', 'aritz', 'Tren');
          final out = await aritz.engine(client).sync();
          final health = aritz.state.health!;
          if (genuine) {
            expect(out.commonStatus, RemoteCommonStatus.unknownWriter);
            expect(out.commonReplaced, isFalse);
            expect(health.commonBlocked, isTrue);
            expect(health.commonBlockedWriter, 'nora-phone');
            for (var i = 0; i < 2 * kCommonUnreadableRounds; i++) {
              expect(
                (await aritz.engine(client).sync()).commonReplaced,
                isFalse,
              );
            }
          } else {
            expect(out.commonStatus, RemoteCommonStatus.forged);
            expect(out.commonReplaced, isTrue);
            expect(health.commonBlocked, isFalse);
            expect(health.commonBlockedWriter, isNull);
            expect(
              peekFamilyEnvelope((await snapshot()).common).writer,
              'aritz-phone',
            );
          }
        },
      );
    }

    test('A2/P1: huérfanos mutuos no se sustituyen el común uno a otro (sin '
        'vaivén): esperan a una persona', () async {
      for (final p in [aritz, leo, nora]) {
        p.enableCommonV2();
      }
      // Cadena aritz <-> leo <-> nora (nora se emparejó con leo).
      await vouchPairs([aritz, leo, nora], [(aritz, leo), (leo, nora)]);
      await aritz.engine(client).ensureCreated();
      for (final p in [leo, nora]) {
        worker.addCredentialForTesting(
          kV2Sync,
          p.identity.deviceId,
          p.keys.serviceCredential,
        );
      }
      await syncAll([leo, nora, aritz]);
      await revokeIn(aritz, 'leo-phone');
      aritz.addGift('g-a', 'nora', 'Tren');
      await aritz.engine(client).sync();
      nora.addGift('g-n', 'aritz', 'Bici');
      for (var round = 0; round < 4 * kCommonUnreadableRounds; round++) {
        final who = round.isEven ? nora : aritz;
        final out = await who.engine(client).sync();
        expect(out.commonReplaced, isFalse, reason: 'vuelta $round');
        expect(
          peekFamilyEnvelope((await snapshot()).common).writer,
          'aritz-phone',
        );
      }
      expect(nora.state.health!.commonBlocked, isTrue);
      expect(nora.state.health!.commonBlockedWriter, 'aritz-phone');
      // Nora no pierde lo suyo: sigue en local hasta que alguien decida.
      expect(nora.giftTitles, contains('Bici'));
    });
  });

  test('B3: un común nuevo de un escritor revocado no se fusiona; lo '
      'aceptado antes se queda', () async {
    await start([aritz, leo, nora]);
    await syncAll([leo, nora, aritz]);
    final k1 = await serverKid();
    nora.addGift('g-bueno', 'leo', 'Bueno');
    await nora.engine(client).sync();
    await leo.engine(client).sync();
    expect(leo.giftTitles, {'Libro', 'Bueno'});
    await revokeIn(aritz, 'nora-phone');
    await aritz.engine(client).sync();
    final k2 = await serverKid();
    // Nora, ya revocada, sella con la clave vieja; lo sube cualquiera.
    final noraView = await nora.view();
    nora.addGift('g-malo', 'leo', 'Malo');
    await putRaw(
      leo,
      common: await sealFamilyEnvelope(
        doc: nora.doc,
        candidate: nora.commonKeys.keyring.entry(k1)!.candidate,
        writer: noraView.self,
        revision: 99,
        signer: nora.keys,
      ),
    );
    final out = await leo.engine(client).sync();
    expect(out.commonStatus, RemoteCommonStatus.revokedWriter);
    expect(out.commonReplaced, isTrue);
    expect(leo.giftTitles, {'Libro', 'Bueno'});
    expect(await serverKid(), k2);
    final retained = (await leo.readRetainedCommons()).single;
    expect(retained.reason, RemoteCommonStatus.revokedWriter);
    expect(retained.writer, 'nora-phone');
    // No se vuelve a intentar: sigue sin fusionarse en las vueltas siguientes.
    await syncAll([aritz, leo]);
    expect(leo.giftTitles, {'Libro', 'Bueno'});
    expect(aritz.giftTitles, {'Libro', 'Bueno'});
  });

  test('B3: inundación de paquetes: la clave buscada (wanted) entra y el '
      'común se abre', () async {
    await start([aritz, leo, nora]);
    await syncAll([leo, nora, aritz]);
    final view = await nora.view();
    final flood = [
      for (var i = 0; i < 20; i++)
        await FamilyCandidate.generate(view, keys: nora.keys, syncId: kV2Sync),
    ]..sort((a, b) => a.kid.compareTo(b.kid));
    // Sella con la de kid mayor: la primera que se desalojaría.
    final used = flood.last;
    nora.addGift('g-nora', 'leo', 'Cometa');
    final packages = [
      for (final c in flood)
        (await FamilyKeyBundle.seal(
          sender: nora.keys,
          view: view,
          syncId: kV2Sync,
          toDevice: 'leo-phone',
          candidate: c,
        )).toJson(),
    ];
    await putRaw(
      nora,
      common: await sealFamilyEnvelope(
        doc: nora.doc,
        candidate: used,
        writer: view.self,
        revision: 3,
        signer: nora.keys,
      ),
      packages: [...(await snapshot()).keyPackages, ...packages],
    );
    final out = await leo.engine(client).sync();
    expect(out.commonStatus, RemoteCommonStatus.opened);
    expect(leo.giftTitles, {'Libro', 'Cometa'});
    final fromNora = leo.commonKeys.keyring.entries
        .where((e) => e.candidate.creator == 'nora-phone')
        .toList();
    expect(
      fromNora.length,
      lessThanOrEqualTo(kMaxIdleCandidatesPerCreator + 1),
    );
    expect(leo.commonKeys.keyring.entry(used.kid), isNotNull);
  });

  group('B3: paquetes (A1, M1)', () {
    test('A1: la app nunca sube paquetes repetidos, aunque el servidor los '
        'tenga (el Worker rechaza la lista entera)', () async {
      await start([aritz, leo, nora]);
      await syncAll([leo, nora, aritz]);
      final mine = (await snapshot()).keyPackages.firstWhere(
        (p) => p['from'] == 'aritz-phone',
      );
      // Lo que dejó un servidor anterior: copias del mismo paquete.
      worker.plantPackagesForTesting(kV2Sync, [mine, mine, mine]);
      leo.addGift('g-l', 'aritz', 'Taza');
      final out = await leo.engine(client).sync();
      expect(out.uploaded, isTrue);
      final s = await snapshot();
      final seen = {for (final p in s.keyPackages) jsonEncode(p)};
      expect(seen.length, s.keyPackages.length);
      expect(seen, contains(jsonEncode(mine)));
      // Y el presupuesto descarta repetidos entre las tres listas.
      final p = {'v': 3, 'n': 1};
      final (v3, v4) = budgetPackages([p, p], [p], [p]);
      expect(v3, isEmpty);
      expect(v4, [p]);
      // El Worker falso, como el de verdad, rechaza una lista con repetidos.
      await expectLater(
        client.putList(
          leo.auth,
          version: s.version,
          body: V2SnapshotUpload(
            common: s.common,
            registry: Map<String, Object?>.from(s.registry! as Map),
            keyPackages: [...s.keyPackages, mine],
          ),
        ),
        throwsA(isA<Exception>()),
      );
    });

    for (final v in [3, 4]) {
      test('A1/P2: una inundación v$v de quien luego se revoca no bloquea la '
          'rotación', () async {
        await start([aritz, leo, nora]);
        await syncAll([leo, nora, aritz]);
        final k1 = await serverKid();
        // Lo que dejó un servidor anterior, sin la regla del escritor.
        worker.plantPackagesForTesting(kV2Sync, [
          for (var i = 0; i < kV2MaxKeyPackages; i++)
            {'v': v, 'from': 'nora-phone', 'to': 'x', 'n': i},
        ]);
        await revokeIn(aritz, 'nora-phone');
        aritz.addGift('g-2', 'leo', 'Tren');
        final out = await aritz.engine(client).sync();
        expect(out.commonPackagesFull, isFalse);
        final k2 = await serverKid();
        expect(k2, isNot(k1));
        final s = await snapshot();
        expect(s.keyPackages.length, lessThanOrEqualTo(kV2MaxKeyPackages));
        // Los v4 inservibles no se vuelven a subir; los v3 se recortan.
        expect(
          s.keyPackages.where((p) => p['v'] == 4 && p['from'] == 'nora-phone'),
          isEmpty,
        );
        expect(
          s.keyPackages.where(
            (p) => familyPackageKid(p) == k2 && p['to'] == 'leo-phone',
          ),
          hasLength(1),
        );
        await leo.engine(client).sync();
        expect(leo.giftTitles, {'Libro', 'Tren'});
        expect(nora.commonKeys.keyring.entry(k2), isNull);
      });
    }

    test('A1: el Worker falso, como el de verdad, no deja meter paquetes '
        'nuevos a nombre de otro ni pasar del cupo por escritor', () async {
      await start([aritz, leo, nora]);
      await syncAll([leo, nora, aritz]);
      final s = await snapshot();
      Future<V2WriteResult> put(List<Map<String, Object?>> packages) =>
          client.putList(
            nora.auth,
            version: s.version,
            body: V2SnapshotUpload(
              common: s.common,
              registry: Map<String, Object?>.from(s.registry! as Map),
              keyPackages: packages,
            ),
          );
      await expectLater(
        put([
          ...s.keyPackages,
          {'v': 4, 'from': 'aritz-phone', 'n': 1},
        ]),
        throwsA(isA<V2ForbiddenException>()),
      );
      await expectLater(
        put([
          ...s.keyPackages,
          for (var i = 0; i <= kMaxFamilyPackagesPerSender; i++)
            {'v': 4, 'from': 'nora-phone', 'n': i},
        ]),
        throwsA(isA<Exception>()),
      );
      expect((await snapshot()).version, s.version);
    });

    test('A1: lo propio (v3 y v4 juntos) cabe en el tope por escritor: '
        'salen los v3 propios más antiguos, nunca el reparto ni lo ajeno', () {
      Map<String, Object?> p(String from, int v, int n, {int pad = 0}) => {
        'v': v,
        'from': from,
        'n': n,
        if (pad > 0) 'x': 'x' * pad,
      };
      final v4 = [for (var i = 0; i < 28; i++) p('me', 4, i)];
      final v3 = [
        for (var i = 0; i < 120; i++) p('me', 3, i),
        for (var i = 0; i < 10; i++) p('other', 3, i),
      ];
      final kept = trimOwnPackages(v3, v4, me: 'me');
      expect(kept.where((x) => x['from'] == 'me'), hasLength(100));
      expect(kept.where((x) => x['from'] == 'me').first['n'], 20);
      expect(kept.where((x) => x['from'] == 'other'), hasLength(10));
      // Por bytes, aunque haya hueco en número.
      final heavy = [for (var i = 0; i < 20; i++) p('me', 3, i, pad: 4000)];
      final light = trimOwnPackages(heavy, const [], me: 'me');
      final bytes = light.fold<int>(
        0,
        (n, x) => n + utf8.encode(jsonEncode(x)).length,
      );
      expect(bytes, lessThanOrEqualTo(kV2MaxPackageBytesPerWriter));
      expect(light.last, heavy.last);
    });

    test('A1: el reparto va primero; los v3 más nuevos y los v4 ajenos de '
        'otras candidatas, solo si caben (número y bytes)', () {
      Map<String, Object?> p(String tag, int n, {int pad = 0}) => {
        'v': 3,
        't': tag,
        'n': n,
        if (pad > 0) 'x': 'x' * pad,
      };
      final mandatory = [for (var i = 0; i < 500; i++) p('m', i)];
      final v3 = [for (var i = 0; i < 20; i++) p('v3', i)];
      final optional = [for (var i = 0; i < 5; i++) p('o', i)];
      final (keptV3, v4) = budgetPackages(mandatory, v3, optional);
      expect(v4.take(500), mandatory);
      expect(keptV3, v3.sublist(8)); // los 12 más nuevos, en su orden
      expect(v4.length, 500);
      // Por bytes: un v3 enorme no entra aunque haya hueco en número.
      final (bigV3, few) = budgetPackages(
        [p('m', 0, pad: kV2MaxKeyPackagesBytes - 100)],
        [p('v3', 0, pad: 200)],
        [p('o', 0)],
      );
      expect(bigV3, isEmpty);
      expect(few, hasLength(2));
      expect(familyPackagesFit([...few, ...bigV3]), isTrue);
      expect(
        familyPackagesFit([
          for (var i = 0; i <= kV2MaxKeyPackages; i++) p('m', i),
        ]),
        isFalse,
      );
    });

    test('M1/P3: un paquete ajeno (falso) no cuenta como entregado: quien '
        'sella reparte el suyo', () async {
      await start([aritz, leo, nora]);
      await syncAll([leo, nora, aritz]);
      final k1 = await serverKid();
      final view = await nora.view();
      FamilyCandidate km;
      do {
        km = await FamilyCandidate.generate(
          view,
          keys: nora.keys,
          syncId: kV2Sync,
        );
      } while (km.kid.compareTo(k1) >= 0);
      final toAritz = await FamilyKeyBundle.seal(
        sender: nora.keys,
        view: view,
        syncId: kV2Sync,
        toDevice: 'aritz-phone',
        candidate: km,
      );
      await putRaw(
        nora,
        packages: [...(await snapshot()).keyPackages, toAritz.toJson()],
      );
      worker.plantPackagesForTesting(kV2Sync, [
        {'v': 4, 'kid': km.kid, 'to': 'leo-phone', 'from': 'gone'},
      ]);
      aritz.addGift('g-2', 'leo', 'Tren');
      final out = await aritz.engine(client).sync();
      expect(out.commonKid, km.kid);
      final after = await snapshot();
      final forLeo = {
        for (final p in after.keyPackages)
          if (familyPackageKid(p) == km.kid && p['to'] == 'leo-phone')
            p['from'],
      };
      expect(forLeo, {'aritz-phone'});
      final lo = await leo.engine(client).sync();
      expect(lo.commonStatus, RemoteCommonStatus.opened);
      expect(leo.giftTitles, {'Libro', 'Tren'});
    });

    test('B3: inundación seguida de revocación del inundador: la clave buena '
        'sigue entrando y la rotación lo deja fuera', () async {
      await start([aritz, leo, nora]);
      await syncAll([leo, nora, aritz]);
      final view = await nora.view();
      final flood = [
        for (var i = 0; i < 40; i++)
          await FamilyCandidate.generate(
            view,
            keys: nora.keys,
            syncId: kV2Sync,
          ),
      ];
      await putRaw(
        nora,
        packages: [
          ...(await snapshot()).keyPackages,
          for (final c in flood)
            (await FamilyKeyBundle.seal(
              sender: nora.keys,
              view: view,
              syncId: kV2Sync,
              toDevice: 'leo-phone',
              candidate: c,
            )).toJson(),
        ],
      );
      await leo.engine(client).sync();
      await revokeIn(aritz, 'nora-phone');
      aritz.addGift('g-2', 'leo', 'Tren');
      await aritz.engine(client).sync();
      final k2 = await serverKid();
      await leo.engine(client).sync();
      expect(leo.giftTitles, {'Libro', 'Tren'});
      expect(await sealingKid(leo), k2);
      // Una vuelta más: la referencia del último común ya se ha movido a k2.
      await leo.engine(client).sync();
      // Las de la revocada sin referencias ni buscadas se podan.
      expect(
        leo.commonKeys.keyring.entries.where(
          (e) => e.candidate.creator == 'nora-phone',
        ),
        isEmpty,
      );
      // Y sus paquetes ya no se reenvían.
      expect(
        (await snapshot()).keyPackages.where((p) => p['from'] == 'nora-phone'),
        isEmpty,
      );
    });

    test('B3: dos revocaciones distintas a la vez convergen a una candidata '
        'que deja fuera a los dos', () async {
      await start([aritz, leo, nora]);
      final x = await addDevice('extra-1', 11);
      final y = await addDevice('extra-2', 12);
      expect(x.identity.deviceId, 'extra-1');
      expect(y.identity.deviceId, 'extra-2');
      await syncAll([aritz, leo, nora, aritz]);
      // Cada uno revoca a uno distinto sin saber del otro.
      await revokeIn(aritz, 'extra-1');
      await revokeIn(leo, 'extra-2');
      worker.beforePut = (_) => aritz.engine(client).sync();
      await leo.engine(client).sync();
      await syncAll([aritz, leo, nora, aritz, leo]);
      final kid = await serverKid();
      final candidate = aritz.commonKeys.keyring.entry(kid)!.candidate;
      expect(candidate.audience.map((m) => m.deviceId), [
        'aritz-phone',
        'leo-phone',
        'nora-phone',
      ]);
      for (final p in [aritz, leo, nora]) {
        expect(await sealingKid(p), kid, reason: p.identity.deviceId);
      }
    });
  });

  group('B3: formato 1, formatos futuros y escritores (M2, M4)', () {
    test('M2/P4: tras pasar al formato 2, un formato 1 (la clave vieja de un '
        'revocado) es falso: no se fusiona y se sustituye', () async {
      await start([aritz, leo, nora]);
      await syncAll([leo, nora, aritz]);
      await revokeIn(aritz, 'nora-phone');
      await aritz.engine(client).sync();
      await leo.engine(client).sync();
      final k2 = await serverKid();
      nora.addGift('g-malo', 'leo', 'Malo');
      final legacy = await seal(
        doc: nora.doc.toJson(),
        listId: kV2List,
        fromNode: 'node-nora-phone',
        at: nora.doc.maxStamp?.pack() ?? '',
        key: key,
      );
      // B4: el Worker ya no lo acepta (mínimo 2)...
      await expectLater(
        putRaw(leo, common: legacy),
        throwsA(isA<V2CommonFormatException>()),
      );
      // ...y si un servidor que manipula lo sirve, es falso.
      worker.setCommonForTesting(kV2Sync, legacy);
      final out = await aritz.engine(client).sync();
      expect(out.commonStatus, RemoteCommonStatus.forged);
      expect(out.commonReplaced, isTrue);
      expect(aritz.giftTitles.contains('Malo'), isFalse);
      expect(await serverKid(), k2);
      await leo.engine(client).sync();
      expect(leo.giftTitles.contains('Malo'), isFalse);
    });

    test('B4: el puente de la primera vuelta está cerrado: con el interruptor '
        'encendido sin la vuelta de activación, un formato 1 es falso y no se '
        'fusiona', () async {
      await start([aritz, leo], on: false);
      await leo.engine(client).sync();
      expect(isFamilyEnvelope((await snapshot()).common), isFalse);
      aritz.enableCommonV2();
      leo.enableCommonV2();
      final out = await leo.engine(client).sync();
      expect(out.commonStatus, RemoteCommonStatus.forged);
      expect(out.commonCutover, CommonCutover.none);
      // Leo ya lo tenía fusionado de antes; lo nuevo del formato 1 no entra.
      aritz.addGift('g-v1', 'leo', 'Por el formato 1');
      worker.setCommonForTesting(
        kV2Sync,
        await seal(
          doc: aritz.doc.toJson(),
          listId: kV2List,
          fromNode: aritz.node,
          at: aritz.doc.maxStamp?.pack() ?? '',
          key: key,
        ),
      );
      final again = await leo.engine(client).sync();
      expect(again.commonStatus, RemoteCommonStatus.forged);
      expect(leo.giftTitles.contains('Por el formato 1'), isFalse);
    });

    test('M4/P7: un formato posterior pide actualizar: ni se retiene ni se '
        'sustituye', () async {
      await start([aritz, leo, nora]);
      await syncAll([leo, nora, aritz]);
      final future = Uint8List.fromList([0x52, 0x47, 0x03, 0, 3, 1, 2, 3, 4]);
      // B4: el Worker lo rechaza (400)...
      await expectLater(
        putRaw(nora, common: future),
        throwsA(isA<V2CommonFormatException>()),
      );
      // ...y si un servidor que manipula lo sirve, se pide actualizar.
      worker.setCommonForTesting(kV2Sync, future);
      await expectLater(
        aritz.engine(client).sync(),
        throwsA(isA<EnvelopeFormatException>()),
      );
      expect((await snapshot()).common, future);
      expect(await aritz.readRetainedCommons(), isEmpty);
    });

    test('B3: un común sellado con la ficha anterior del escritor (antes de '
        'cambiar de persona) se abre', () async {
      await start([aritz, leo, nora]);
      await syncAll([leo, nora, aritz]);
      final k1 = leo.commonKeys.keyring.entry(await serverKid())!.candidate;
      leo.addGift('g-antes', 'aritz', 'Antes');
      await putRaw(
        leo,
        common: await sealFamilyEnvelope(
          doc: leo.doc,
          candidate: k1,
          writer: (await leo.view()).self,
          revision: 5,
          signer: leo.keys,
        ),
      );
      final second = await DeviceRecord.create(
        keys: leo.keys,
        listId: kV2List,
        deviceId: 'leo-phone',
        personId: null,
        seq: 2,
      );
      aritz.reg = await (await aritz.reg.withRecord(second)).withVouch(
        await Vouch.create(
          keys: aritz.keys,
          voucher: aritz.record,
          record: second,
        ),
      );
      final out = await aritz.engine(client).sync();
      expect(out.commonStatus, RemoteCommonStatus.opened);
      expect(aritz.giftTitles, contains('Antes'));
      // Y vuelve a sellar con una candidata del contexto nuevo.
      expect(await serverKid(), isNot(k1.kid));
    });
  });

  group('B3: retenidos y estado guardado (M3, B4)', () {
    Future<FamilyCandidate> leoUnopenable(String id) async {
      final view = await leo.view();
      final only = await FamilyCandidate.generate(
        view,
        keys: leo.keys,
        syncId: kV2Sync,
      );
      leo.addGift(id, 'aritz', id);
      await putRaw(
        leo,
        common: await sealFamilyEnvelope(
          doc: leo.doc,
          candidate: only,
          writer: view.self,
          revision: 7,
          signer: leo.keys,
        ),
      );
      return only;
    }

    test('M3/P5: los falsos no desalojan al retenido que espera; al llegar '
        'la clave se fusiona', () async {
      await start([aritz, leo, nora]);
      await syncAll([leo, nora, aritz]);
      final only = await leoUnopenable('Secreto');
      await aritz.engine(client).sync();
      for (var i = 0; i < kMaxRetainedForged + 2; i++) {
        await putRaw(
          nora,
          common: Uint8List.fromList([0x52, 0x47, 0x02, 0, 3, 1, 2, 3, i]),
        );
        final out = await aritz.engine(client).sync();
        expect(out.commonStatus, RemoteCommonStatus.forged);
      }
      final retained = await aritz.readRetainedCommons();
      expect(
        retained.where((r) => r.reason == RemoteCommonStatus.missingKey),
        hasLength(1),
      );
      expect(
        retained.where((r) => r.reason == RemoteCommonStatus.forged),
        hasLength(kMaxRetainedForged),
      );
      expect(aritz.retainedFiles, hasLength(1));
      final bundle = await FamilyKeyBundle.seal(
        sender: leo.keys,
        view: await leo.view(),
        syncId: kV2Sync,
        toDevice: 'aritz-phone',
        candidate: only,
      );
      await putRaw(
        leo,
        packages: [...(await snapshot()).keyPackages, bundle.toJson()],
      );
      await aritz.engine(client).sync();
      expect(aritz.giftTitles, contains('Secreto'));
      expect(aritz.retainedFiles, isEmpty);
    });

    test('M3: tope de los retenidos que esperan: sale el más antiguo y se '
        'borran sus bytes', () async {
      await start([aritz, leo, nora]);
      await syncAll([leo, nora, aritz]);
      final hashes = <String>[];
      for (var i = 0; i < kMaxRetainedWaiting + 1; i++) {
        await leoUnopenable('S$i');
        hashes.add(sha256Hex((await snapshot()).common));
        await withClock(
          Clock.fixed(DateTime(2026, 12, 1).add(Duration(minutes: i))),
          () => aritz.engine(client).sync(),
        );
      }
      final retained = await aritz.readRetainedCommons();
      expect(retained.map((r) => r.hash).toSet(), hashes.sublist(1).toSet());
      expect(aritz.retainedFiles.keys.toSet(), hashes.sublist(1).toSet());
    });

    test('B4: si falta la clave común ya guardada alguna vez, error (no se '
        'empieza de cero); un índice de retenidos dañado, también', () async {
      await start([aritz, leo, nora]);
      await syncAll([leo, nora, aritz]);
      expect(aritz.commonKeysMarker, isTrue);
      final saved = aritz.commonKeysJson;
      aritz.commonKeysJson = null;
      await expectLater(
        aritz.engine(client).sync(),
        throwsA(isA<CommonStateException>()),
      );
      aritz
        ..commonKeysJson = saved
        ..retainedJson = jsonEncode([
          {'h': 'a' * 64, 'r': 'opened', 't': 1},
        ]);
      await expectLater(
        aritz.engine(client).sync(),
        throwsA(isA<CommonStateException>()),
      );
    });

    test('B3: cierre entre guardar el índice de retenidos y las referencias: '
        'al volver, la clave del retenido queda referenciada', () async {
      await start([aritz, leo, nora]);
      await syncAll([leo, nora, aritz]);
      final k1 = await serverKid();
      final view = await leo.view();
      await putRaw(
        leo,
        common: await sealFamilyEnvelopeForTesting(
          doc: leo.doc,
          candidate: leo.commonKeys.keyring.entry(k1)!.candidate,
          writer: 'leo-phone',
          writerRecord: view.self.recordDigest,
          revision: 9,
          signer: leo.keys,
          nonce: List<int>.filled(12, 9),
          bodyForTesting: List<int>.filled(16, 9),
        ),
      );
      // Guardado 1: tras los paquetes; 2: el de las referencias.
      aritz.failCommonKeySaveAt = aritz.commonKeySaves + 2;
      await expectLater(
        aritz.engine(client).sync(),
        throwsA(isA<StateError>()),
      );
      final retained = (await aritz.readRetainedCommons()).single;
      expect(
        aritz.commonKeys.keyring.entry(k1)!.references,
        isNot(contains(retainedRef(retained.hash))),
      );
      aritz.failCommonKeySaveAt = null;
      await aritz.engine(client).sync();
      expect(
        aritz.commonKeys.keyring.entry(k1)!.references,
        contains(retainedRef(retained.hash)),
      );
    });

    test('B3: una clave referenciada sobrevive al recorte del llavero y a '
        'pruneRevoked', () async {
      await start([aritz, leo, nora]);
      await syncAll([leo, nora, aritz]);
      final view = await aritz.view();
      final record = view.self.recordDigest;
      var keyring = FamilyKeyring.empty;
      FamilyCandidate? oldest;
      for (var i = 0; i <= kCommonKeyringSoftLimit; i++) {
        final c = await FamilyCandidate.create(
          listId: kV2List,
          syncId: kV2Sync,
          epochNumber: 1 + i,
          epochContext: i.toRadixString(16).padLeft(64, '0'),
          creator: 'aritz-phone',
          creatorRecord: record,
          audience: [AudienceMember('aritz-phone', record)],
          secret: List<int>.generate(32, (j) => (i + j) % 255 + 1),
          creatorKeys: aritz.keys,
        );
        oldest ??= c;
        keyring = keyring.withOwnCandidate(c);
      }
      keyring = keyring.withReference(oldest!.kid, kCommonRef);
      final trimmed = trimCommonKeyring(
        keyring,
        view,
        syncId: kV2Sync,
        wanted: const {},
      );
      expect(trimmed.length, kCommonKeyringSoftLimit);
      expect(trimmed.entry(oldest.kid), isNotNull);
      // Recibida de una que luego se revoca: con referencia se queda.
      final noraView = await nora.view();
      final fromNora = await FamilyCandidate.generate(
        noraView,
        keys: nora.keys,
        syncId: kV2Sync,
      );
      var received = FamilyKeyring.empty.withReceivedCandidate(
        fromNora,
        from: 'nora-phone',
        fromRecord: noraView.self.recordDigest,
        sealable: (_) => false,
      );
      await revokeIn(aritz, 'nora-phone');
      final revokedView = await aritz.view();
      expect(received.pruneRevoked(revokedView).length, 0);
      received = received.withReference(fromNora.kid, retainedRef('b' * 64));
      expect(received.pruneRevoked(revokedView).entry(fromNora.kid), isNotNull);
    });

    test('B3: ensureCreated con el interruptor: formato 2, reparto, clave '
        'guardada y marca', () async {
      for (final p in [aritz, leo, nora]) {
        p.enableCommonV2();
      }
      await vouchAll([aritz, leo, nora]);
      await aritz.engine(client).ensureCreated();
      final s = await snapshot();
      expect(isFamilyEnvelope(s.common), isTrue);
      final kid = peekFamilyEnvelope(s.common).kid;
      expect(
        {for (final p in s.keyPackages) p['to']},
        {'leo-phone', 'nora-phone'},
      );
      expect(aritz.commonKeysMarker, isTrue);
      expect(aritz.commonKeys.lastKid, kid);
      expect(aritz.commonKeys.outbox, isEmpty);
      expect(aritz.commonKeys.keyring.entry(kid)!.own, isTrue);
      expect(aritz.state.created, isTrue);
    });
  });

  test('B3: la vía v3 scope: family se rechaza con el interruptor', () async {
    await start([aritz, leo]);
    final view = await aritz.view();
    expect(
      () => KeyBundle.sealFamilyKey(
        sender: aritz.keys,
        view: view,
        toDevice: 'leo-phone',
        epoch: view.epoch,
        familyKey: key,
        commonFormatV2: true,
      ),
      throwsA(isA<KeyBundleException>()),
    );
    final bundle = await KeyBundle.sealFamilyKey(
      sender: aritz.keys,
      view: view,
      toDevice: 'leo-phone',
      epoch: view.epoch,
      familyKey: key,
    );
    final leoView = await leo.view();
    await expectLater(
      bundle.openFamilyKey(mine: leo.keys, view: leoView, commonFormatV2: true),
      throwsA(isA<KeyBundleException>()),
    );
    // Apagado sigue como hoy.
    expect(
      (await bundle.openFamilyKey(mine: leo.keys, view: leoView)).bytes,
      key.bytes,
    );
    // Y el motor encendido no usa un paquete v3 de la familia que le llegue.
    await putRaw(
      aritz,
      packages: [...(await snapshot()).keyPackages, bundle.toJson()],
    );
    await leo.engine(client).sync();
    expect(leo.familyKey.bytes, key.bytes);
    expect(leo.commonKeys.keyring.length, 1);
  });
}
