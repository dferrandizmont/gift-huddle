// Lote B4 del ADR 0005: el corte de una familia v2 que ya existe al formato
// 2 del común (clave legacy histórica, activación recuperable e
// irreversible, coordinación entre móviles y formato mínimo del Worker),
// contra el Worker falso.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/family_envelope.dart';
import 'package:regalos/core/sync/family_key_bundle.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/pairing_v2.dart';
import 'package:regalos/features/sync/application/common_v2.dart';
import 'package:regalos/features/sync/application/common_v2_cutover.dart';
import 'package:regalos/features/sync/application/sync_v2_engine.dart';
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

  Future<Uint8List> serverCommon() async => (await snapshot()).common;

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

  Future<Uint8List> sealV1(MemoryV2Phone p) => seal(
    doc: p.doc.toJson(),
    listId: kV2List,
    fromNode: p.node,
    at: p.doc.maxStamp?.pack() ?? '',
    key: key,
  );

  Future<void> syncAll(Iterable<MemoryV2Phone> phones) async {
    for (final p in phones) {
      await p.engine(client).sync();
    }
  }

  /// La familia en el formato 1, como antes de B4.
  Future<void> start(List<MemoryV2Phone> phones) async {
    await vouchAll(phones);
    await phones.first.engine(client).ensureCreated();
    for (final p in phones.skip(1)) {
      worker.addCredentialForTesting(
        kV2Sync,
        p.identity.deviceId,
        p.keys.serviceCredential,
      );
    }
    await syncAll([...phones.skip(1), phones.first]);
  }

  void ready(Iterable<MemoryV2Phone> phones) {
    for (final p in phones) {
      p.commonV2Ready = true;
    }
  }

  /// Todos anuncian; nadie corta todavía porque [last] aún no ha anunciado
  /// cuando los demás sincronizan.
  Future<void> announceAll(List<MemoryV2Phone> phones) async {
    for (final p in phones) {
      await client.announceCommonFormat(p.auth, kCommonFormatLatest);
    }
  }

  /// Lo que se exige al terminar: el servidor en el mínimo 2 con un común
  /// en formato 2 que cada móvil abre, la marca y el interruptor en todos,
  /// nada pendiente y lo de todos fusionado.
  Future<void> expectCut(List<MemoryV2Phone> phones, Set<String> gifts) async {
    expect(worker.minCommonFormatOf(kV2Sync), 2);
    final common = await serverCommon();
    expect(isFamilyEnvelope(common), isTrue);
    // La clave de siempre ya no lo abre: a un cliente antiguo no se le sirve
    // nada cifrado con ella.
    await expectLater(
      open(common, key: key, expectedListId: kV2List),
      throwsA(isA<EnvelopeFormatException>()),
    );
    final kid = peekFamilyEnvelope(common).kid;
    for (final p in phones) {
      final who = p.identity.deviceId;
      expect(p.formatFloor, 2, reason: who);
      expect(p.state.commonFormatV2, isTrue, reason: who);
      expect(p.state.commonMigration, isFalse, reason: who);
      expect(p.giftTitles, gifts, reason: who);
      expect(titles(await openAs(p, common)), gifts, reason: who);
      // La legacy está, histórica, y nunca es la que sella.
      final legacy = p.commonKeys.keyring.entries.where(
        (e) => e.references.contains(kLegacyRef),
      );
      expect(legacy, hasLength(1), reason: who);
      expect(legacy.single.historical, isTrue, reason: who);
      expect(legacy.single.candidate.kid, isNot(kid), reason: who);
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

  test('B4: kCommonV2Ready está apagado: sin anuncio ni corte', () async {
    expect(kCommonV2Ready, isFalse);
    await start([aritz, leo, nora]);
    await syncAll([aritz, leo, nora]);
    for (final p in [aritz, leo, nora]) {
      expect(worker.commonFormatOf(kV2Sync, p.identity.deviceId), 1);
      expect(p.formatFloor, 1);
      expect(p.state.commonFormatV2, isFalse);
    }
    expect(worker.minCommonFormatOf(kV2Sync), 1);
    expect(isFamilyEnvelope(await serverCommon()), isFalse);
  });

  test('B4: corte coordinado: nadie activa hasta que todos los miembros '
      'activos anuncian; después todos quedan en el formato 2', () async {
    await start([aritz, leo, nora]);
    leo.addGift('g-leo', 'aritz', 'Puzle');
    await leo.engine(client).sync();
    ready([aritz, leo, nora]);
    final first = await aritz.engine(client).sync();
    expect(first.commonCutover, CommonCutover.waiting);
    expect(worker.commonFormatOf(kV2Sync, 'aritz-phone'), 2);
    expect(worker.minCommonFormatOf(kV2Sync), 1);
    expect(isFamilyEnvelope(await serverCommon()), isFalse);
    expect(
      (await leo.engine(client).sync()).commonCutover,
      CommonCutover.waiting,
    );
    // Un cambio local de Nora que aún no ha subido entra en el corte.
    nora.addGift('g-nora', 'leo', 'Tren');
    final cut = await nora.engine(client).sync();
    expect(cut.commonCutover, CommonCutover.activated);
    expect(cut.commonStatus, RemoteCommonStatus.legacy);
    final back = await leo.engine(client).sync();
    expect(back.commonCutover, CommonCutover.followed);
    expect(back.commonStatus, RemoteCommonStatus.opened);
    await syncAll([aritz, leo, nora]);
    await expectCut([aritz, leo, nora], {'Libro', 'Puzle', 'Tren'});
    // Ya no hay vuelta atrás: otra vuelta no cambia nada del corte.
    final again = await aritz.engine(client).sync();
    expect(again.commonCutover, CommonCutover.none);
    expect(again.commonStatus, RemoteCommonStatus.opened);
  });

  test('B4: un miembro que no anuncia (versión antigua) bloquea el corte; '
      'cuando anuncia, corta el siguiente', () async {
    await start([aritz, leo, nora]);
    ready([aritz, leo]);
    await syncAll([aritz, leo, aritz, leo]);
    expect(worker.minCommonFormatOf(kV2Sync), 1);
    expect(isFamilyEnvelope(await serverCommon()), isFalse);
    for (final p in [aritz, leo]) {
      expect(p.formatFloor, 1);
      expect(p.state.commonMigration, isFalse);
    }
    expect(
      (await leo.engine(client).sync()).commonCutover,
      CommonCutover.waiting,
    );
    // Cuando anuncia, el siguiente que sincroniza corta.
    ready([nora]);
    await nora.engine(client).sync();
    expect(worker.minCommonFormatOf(kV2Sync), 2);
  });

  group('B4: corte interrumpido en cada paso', () {
    Future<void> arm() async {
      await start([aritz, leo, nora]);
      ready([aritz, leo, nora]);
      await announceAll([aritz, leo, nora]);
      aritz.addGift('g-2', 'nora', 'Cometa');
    }

    Future<void> afterCrash() async {
      // Nunca queda publicado nada que no se pueda abrir: o sigue el formato
      // 1 con el mínimo 1, o el formato 2 con su clave guardada.
      final common = await serverCommon();
      if (isFamilyEnvelope(common)) {
        expect(worker.minCommonFormatOf(kV2Sync), 2);
        expect(
          aritz.commonKeys.keyring.entry(peekFamilyEnvelope(common).kid),
          isNotNull,
        );
      } else {
        expect(worker.minCommonFormatOf(kV2Sync), 1);
        expect(aritz.formatFloor, 1);
      }
    }

    Future<void> recover() async {
      await aritz.engine(client).sync();
      await syncAll([leo, nora, aritz]);
      await expectCut([aritz, leo, nora], {'Libro', 'Cometa'});
    }

    test('al guardar la migración pendiente', () async {
      await arm();
      aritz.failSaveStateIf = (s) => s.commonMigration;
      await expectLater(
        aritz.engine(client).sync(),
        throwsA(isA<StateError>()),
      );
      aritz.failSaveStateIf = null;
      expect(aritz.commonKeysJson, isNull);
      await afterCrash();
      await recover();
    });

    // 1: la clave histórica; 2 y 3: `receive`; 4: candidata y reparto antes
    // de sellar; 5: `accepted`, con el PUT ya dentro.
    for (final at in [1, 2, 3, 4, 5]) {
      test('en el guardado $at de la clave común', () async {
        await arm();
        final saves = aritz.commonKeySaves;
        aritz.failCommonKeySaveAt = saves + at;
        await expectLater(
          aritz.engine(client).sync(),
          throwsA(isA<StateError>()),
        );
        aritz.failCommonKeySaveAt = null;
        // Cae justo en el guardado que dice: los anteriores entraron.
        expect(aritz.commonKeySaves, saves + at - 1);
        // Solo el último cae con el PUT ya hecho.
        expect(aritz.state.commonMigrationPut, at == 5);
        expect(aritz.state.commonMigration, isTrue);
        await afterCrash();
        if (at == 5) {
          // El PUT entró: al volver, el móvil sigue su propio corte.
          final out = await aritz.engine(client).sync();
          expect(out.commonCutover, CommonCutover.followed);
          expect(out.commonStatus, RemoteCommonStatus.opened);
        }
        await recover();
      });
    }

    test('al poner la marca, con el PUT ya dentro', () async {
      await arm();
      aritz.failRaiseFloor = true;
      await expectLater(
        aritz.engine(client).sync(),
        throwsA(isA<StateError>()),
      );
      aritz.failRaiseFloor = false;
      expect(aritz.formatFloor, 1);
      await afterCrash();
      // El `PUT` se apuntó (lastKid): la marca va antes de abrir nada.
      expect(
        (await aritz.engine(client).sync()).commonCutover,
        CommonCutover.none,
      );
      expect(aritz.formatFloor, 2);
      await recover();
    });

    test('P8: el PUT entró y no hay marca; un servidor que baja el mínimo y '
        'sirve un formato 1 no inyecta nada', () async {
      await arm();
      aritz.failRaiseFloor = true;
      await expectLater(
        aritz.engine(client).sync(),
        throwsA(isA<StateError>()),
      );
      aritz.failRaiseFloor = false;
      expect(aritz.formatFloor, 1);
      expect(aritz.commonKeys.lastKid, isNotNull);
      nora.addGift('g-malo', 'leo', 'Malo');
      worker.setCommonForTesting(
        kV2Sync,
        await sealV1(nora),
        minCommonFormat: 1,
      );
      final out = await aritz.engine(client).sync();
      expect(out.commonStatus, RemoteCommonStatus.forged);
      expect(aritz.giftTitles.contains('Malo'), isFalse);
      expect(aritz.formatFloor, 2);
      // Y vuelve a subir el mínimo con su formato 2.
      expect(worker.minCommonFormatOf(kV2Sync), 2);
      expect(isFamilyEnvelope(await serverCommon()), isTrue);
    });

    test('un servidor que tira siempre la respuesta del PUT: el corte entra, '
        'el móvil lo sigue y nunca abre un formato 1', () async {
      await arm();
      worker.tamper = (method, uri, response) => method == 'PUT'
          ? SyncResponse(500, const {}, Uint8List(0))
          : response;
      await expectLater(
        aritz.engine(client).sync(),
        throwsA(isA<SyncTransportException>()),
      );
      expect(aritz.state.commonMigrationPut, isTrue);
      expect(worker.minCommonFormatOf(kV2Sync), 2);
      // La vuelta siguiente sigue su propio corte (no sube nada: no hay
      // cambios) y pone la marca.
      final out = await aritz.engine(client).sync();
      expect(out.commonCutover, CommonCutover.followed);
      expect(out.commonStatus, RemoteCommonStatus.opened);
      expect(aritz.formatFloor, 2);
      worker.tamper = null;
      await recover();
    });

    test(
      'el PUT del corte no llega: el móvil no vuelve a abrir el formato 1; '
      'lo que otro escribió en formato 1 entra cuando sigue el corte',
      () async {
        await arm();
        void cut() => worker.beforePut = (_) async =>
            throw const SyncTransportException(SyncFailure.network, 'sin red');
        cut();
        await expectLater(
          aritz.engine(client).sync(),
          throwsA(isA<SyncTransportException>()),
        );
        expect(aritz.state.commonMigrationPut, isTrue);
        expect(worker.minCommonFormatOf(kV2Sync), 1);
        // Leo, sin cortar todavía, escribe en formato 1.
        leo.commonV2Ready = false;
        leo.addGift('g-leo', 'aritz', 'Puzle');
        await leo.engine(client).sync();
        expect(isFamilyEnvelope(await serverCommon()), isFalse);
        cut();
        await expectLater(
          aritz.engine(client).sync(),
          throwsA(isA<SyncTransportException>()),
        );
        expect(aritz.giftTitles.contains('Puzle'), isFalse);
        // Con red, el corte entra sellando lo que tiene Aritz.
        worker.beforePut = null;
        final out = await aritz.engine(client).sync();
        expect(out.commonCutover, CommonCutover.activated);
        expect(aritz.giftTitles.contains('Puzle'), isFalse);
        // Leo sigue el corte (no depende de su interruptor) y sube lo suyo.
        final back = await leo.engine(client).sync();
        expect(back.commonCutover, CommonCutover.followed);
        await syncAll([nora, aritz, leo]);
        await expectCut([aritz, leo, nora], {'Libro', 'Cometa', 'Puzle'});
      },
    );

    test('con la respuesta del PUT perdida', () async {
      await arm();
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
      worker.tamper = null;
      await afterCrash();
      expect(isFamilyEnvelope(await serverCommon()), isTrue);
      await recover();
    });

    test(
      'sin red justo antes del PUT: se reanuda con la misma candidata',
      () async {
        await arm();
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
        await afterCrash();
        final saved = aritz.commonKeys.keyring.entries
            .where((e) => e.own && !e.historical)
            .single
            .candidate
            .kid;
        final out = await aritz.engine(client).sync();
        expect(out.commonCutover, CommonCutover.activated);
        expect(peekFamilyEnvelope(await serverCommon()).kid, saved);
        await recover();
      },
    );

    test('si al reanudar ya no anuncian todos, la migración pendiente se deja '
        'sin publicar nada', () async {
      await arm();
      aritz.failCommonKeySaveAt = aritz.commonKeySaves + 4;
      await expectLater(
        aritz.engine(client).sync(),
        throwsA(isA<StateError>()),
      );
      aritz.failCommonKeySaveAt = null;
      expect(aritz.state.commonMigration, isTrue);
      // Entra un móvil más, de una versión que no anuncia.
      final extra = await MemoryV2Phone.create(
        'extra-phone',
        null,
        11,
        familyKey: key,
      );
      await vouchAll([aritz, leo, nora, extra]);
      worker.addCredentialForTesting(
        kV2Sync,
        'extra-phone',
        extra.keys.serviceCredential,
      );
      final out = await aritz.engine(client).sync();
      expect(out.commonCutover, CommonCutover.waiting);
      expect(aritz.state.commonMigration, isFalse);
      expect(isFamilyEnvelope(await serverCommon()), isFalse);
      expect(worker.minCommonFormatOf(kV2Sync), 1);
      expect(aritz.formatFloor, 1);
      await leo.engine(client).sync();
      expect(leo.giftTitles, {'Libro', 'Cometa'});
    });
  });

  test('P1: un servidor que dice mínimo 2 con un común en formato 1 no hace '
      'cortar a nadie', () async {
    await start([aritz, leo, nora]);
    final v1 = await serverCommon();
    worker.setCommonForTesting(kV2Sync, v1, minCommonFormat: 2);
    await expectLater(
      aritz.engine(client).sync(),
      throwsA(
        isA<SyncTransportException>().having(
          (e) => e.failure,
          'failure',
          SyncFailure.protocol,
        ),
      ),
    );
    expect(aritz.formatFloor, 1);
    expect(aritz.state.commonFormatV2, isFalse);
    expect(await serverCommon(), v1);
  });

  test('B1: un mínimo 2 con un común en formato 2 que no firma ningún '
      'miembro no pone la marca ni se sustituye', () async {
    await start([aritz, leo, nora]);
    final junk = Uint8List.fromList([0x52, 0x47, 0x02, 0, 3, 1, 2, 3, 4]);
    worker.setCommonForTesting(kV2Sync, junk, minCommonFormat: 2);
    await expectLater(
      aritz.engine(client).sync(),
      throwsA(isA<SyncTransportException>()),
    );
    expect(aritz.formatFloor, 1);
    expect(await serverCommon(), junk);
  });

  test('M1: una web dentro (aún no puede anunciar) bloquea el corte, en el '
      'móvil y en el Worker', () async {
    await start([aritz, leo, nora]);
    worker.addCredentialForTesting(
      kV2Sync,
      'nora-web',
      Uint8List.fromList(List<int>.filled(32, 77)),
      role: 'web',
    );
    ready([aritz, leo, nora]);
    await announceAll([aritz, leo, nora]);
    final out = await aritz.engine(client).sync();
    expect(out.commonCutover, CommonCutover.waiting);
    expect(worker.minCommonFormatOf(kV2Sync), 1);
    // Un cliente que se salte la comprobación tampoco corta: 409.
    final s = await snapshot();
    await expectLater(
      client.putList(
        aritz.auth,
        version: s.version,
        body: V2SnapshotUpload(
          common: Uint8List.fromList([0x52, 0x47, 0x02, 0, 3, 1, 2, 3, 4]),
          registry: Map<String, Object?>.from(s.registry! as Map),
          keyPackages: s.keyPackages,
          minCommonFormat: 2,
        ),
      ),
      throwsA(
        isA<V2CommonFormatException>().having(
          (e) => e.code,
          'code',
          'common_format_unannounced',
        ),
      ),
    );
    expect(worker.minCommonFormatOf(kV2Sync), 1);
  });

  test('P9: una credencial activa fuera de la vista que no anuncia bloquea '
      'el corte', () async {
    await start([aritz, leo]);
    worker.addCredentialForTesting(
      kV2Sync,
      nora.identity.deviceId,
      nora.keys.serviceCredential,
    );
    ready([aritz, leo]);
    await aritz.engine(client).sync();
    final out = await leo.engine(client).sync();
    expect(out.commonCutover, CommonCutover.waiting);
    expect(worker.minCommonFormatOf(kV2Sync), 1);
    expect(isFamilyEnvelope(await serverCommon()), isFalse);
  });

  test('P2: la respuesta de la creación en formato 2 se pierde: la marca se '
      'pone igual', () async {
    await vouchAll([aritz, leo]);
    await CommonV2Bootstrap.prepareFresh(aritz);
    var armed = true;
    worker.tamper = (method, uri, response) {
      if (method == 'PUT' && armed) {
        armed = false;
        return SyncResponse(500, const {}, Uint8List(0));
      }
      return response;
    };
    await expectLater(
      aritz.engine(client).ensureCreated(),
      throwsA(isA<SyncTransportException>()),
    );
    worker.tamper = null;
    expect(aritz.formatFloor, 1);
    await aritz.engine(client).ensureCreated();
    expect(aritz.formatFloor, 2);
  });

  test('P2: cierre entre crear la lista en formato 2 y la marca: la vuelta '
      'siguiente la pone (por la marca, no por el interruptor)', () async {
    await vouchAll([aritz, leo]);
    await CommonV2Bootstrap.prepareFresh(aritz);
    aritz.failRaiseFloor = true;
    await expectLater(
      aritz.engine(client).ensureCreated(),
      throwsA(isA<StateError>()),
    );
    aritz.failRaiseFloor = false;
    expect(aritz.state.commonFormatV2, isTrue);
    expect(aritz.formatFloor, 1);
    final out = await aritz.engine(client).sync();
    expect(out.commonCutover, CommonCutover.followed);
    expect(aritz.formatFloor, 2);
  });

  test(
    'un seguidor sin su paquete v4 espera y no sustituye el común',
    () async {
      await start([aritz, leo, nora]);
      ready([aritz, leo, nora]);
      await announceAll([aritz, leo, nora]);
      expect(
        (await aritz.engine(client).sync()).commonCutover,
        CommonCutover.activated,
      );
      // Un servidor (o quien sea) quita el paquete de Nora.
      final s = await snapshot();
      expect(
        await client.putList(
          leo.auth,
          version: s.version,
          body: V2SnapshotUpload(
            common: s.common,
            registry: Map<String, Object?>.from(s.registry! as Map),
            keyPackages: [
              for (final p in s.keyPackages)
                if (p['to'] != 'nora-phone') p,
            ],
          ),
        ),
        isA<V2WriteOk>(),
      );
      final before = await serverCommon();
      nora.addGift('g-nora', 'leo', 'Tren');
      final out = await nora.engine(client).sync();
      expect(out.commonStatus, RemoteCommonStatus.missingKey);
      expect(out.commonReplaced, isFalse);
      expect(await serverCommon(), before);
      // La firma de Aritz se ha comprobado: la marca está.
      expect(nora.formatFloor, 2);
      // Cuando Aritz vuelve a repartir, Nora abre y sube lo suyo.
      await aritz.engine(client).sync();
      final back = await nora.engine(client).sync();
      expect(back.commonStatus, RemoteCommonStatus.opened);
      await syncAll([aritz, leo]);
      expect(aritz.giftTitles, {'Libro', 'Tren'});
    },
  );

  group('B4: después del corte', () {
    Future<void> cut() async {
      await start([aritz, leo, nora]);
      ready([aritz, leo, nora]);
      await announceAll([aritz, leo, nora]);
      expect(
        (await aritz.engine(client).sync()).commonCutover,
        CommonCutover.activated,
      );
      await syncAll([leo, nora, aritz]);
    }

    test('un cliente antiguo intenta escribir el formato 1 y no degrada la '
        'familia; al leer, ve que hay que actualizar', () async {
      await cut();
      final before = await snapshot();
      leo.addGift('g-viejo', 'aritz', 'Desde la versión antigua');
      final legacy = await sealV1(leo);
      await expectLater(
        client.putList(
          leo.auth,
          version: before.version,
          body: V2SnapshotUpload(
            common: legacy,
            registry: Map<String, Object?>.from(before.registry! as Map),
            keyPackages: before.keyPackages,
          ),
        ),
        throwsA(
          isA<V2CommonFormatException>().having(
            (e) => e.code,
            'code',
            'common_format_too_old',
          ),
        ),
      );
      await expectLater(
        client.putCommon(leo.auth, version: before.version, common: legacy),
        throwsA(isA<V2CommonFormatException>()),
      );
      final after = await snapshot();
      expect(after.version, before.version);
      expect(after.common, before.common);
      // Lo que lee un cliente antiguo: un sobre que su versión no entiende.
      await expectLater(
        open(after.common, key: key, expectedListId: kV2List),
        throwsA(isA<EnvelopeFormatException>()),
      );
      await syncAll([aritz, nora]);
      expect(aritz.giftTitles.contains('Desde la versión antigua'), isFalse);
    });

    test('puente v1 cerrado: un formato 1 que sirve un servidor que manipula '
        'es falso, no se fusiona y se sustituye', () async {
      await cut();
      nora.addGift('g-malo', 'leo', 'Malo');
      worker.setCommonForTesting(kV2Sync, await sealV1(nora));
      final out = await aritz.engine(client).sync();
      expect(out.commonStatus, RemoteCommonStatus.forged);
      expect(out.commonReplaced, isTrue);
      expect(aritz.giftTitles.contains('Malo'), isFalse);
      expect(isFamilyEnvelope(await serverCommon()), isTrue);
      // Ni aunque el servidor diga que el mínimo vuelve a ser 1.
      worker.setCommonForTesting(
        kV2Sync,
        await sealV1(nora),
        minCommonFormat: 1,
      );
      final again = await leo.engine(client).sync();
      expect(again.commonStatus, RemoteCommonStatus.forged);
      expect(leo.giftTitles.contains('Malo'), isFalse);
      // Y como tiene la marca, vuelve a subir el mínimo con su formato 2.
      expect(worker.minCommonFormatOf(kV2Sync), 2);
      expect(isFamilyEnvelope(await serverCommon()), isTrue);
    });

    test(
      'una copia antigua o un estado perdido no rebajan el formato',
      () async {
        await cut();
        // Un documento antiguo (como el de una copia de recuperación o un
        // .regalos de antes) que dice protocolo 1, y el estado de la
        // sincronización perdido.
        final old = FamilyDoc.empty(kV2List)
            .set(
              HlcClock(node: 'node-viejo'),
              Collections.meta,
              kProtocolRecordId,
              {kProtocolVersionField: 1},
            )
            .set(HlcClock(node: 'node-viejo'), Collections.gifts, 'g-copia', {
              'title': 'De la copia',
              'recipientId': 'leo',
            });
        await aritz.mergeCommon(old, fromNode: 'node-viejo');
        aritz.state = const V2SyncState();
        final out = await aritz.engine(client).sync();
        expect(out.commonStatus, RemoteCommonStatus.opened);
        expect(aritz.state.commonFormatV2, isTrue);
        expect(aritz.formatFloor, 2);
        expect(worker.minCommonFormatOf(kV2Sync), 2);
        expect(isFamilyEnvelope(await serverCommon()), isTrue);
        await leo.engine(client).sync();
        expect(leo.giftTitles.contains('De la copia'), isTrue);
      },
    );

    test('un mínimo posterior pide actualizar', () async {
      await cut();
      worker.setCommonForTesting(
        kV2Sync,
        await serverCommon(),
        minCommonFormat: 3,
      );
      await expectLater(
        aritz.engine(client).sync(),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });
  });

  test('B4: dos móviles activan a la vez: uno gana y el otro sigue su corte '
      'sin perder nada', () async {
    await start([aritz, leo, nora]);
    ready([aritz, leo, nora]);
    await announceAll([aritz, leo, nora]);
    aritz.addGift('g-a', 'nora', 'Cometa');
    leo.addGift('g-l', 'aritz', 'Puzle');
    CommonCutover? leoCut;
    worker.beforePut = (_) async {
      leoCut = (await leo.engine(client).sync()).commonCutover;
    };
    final out = await aritz.engine(client).sync();
    expect(leoCut, CommonCutover.activated);
    expect(out.commonCutover, CommonCutover.followed);
    await syncAll([leo, nora, aritz, leo]);
    await expectCut([aritz, leo, nora], {'Libro', 'Cometa', 'Puzle'});
  });

  test('B4: un móvil desconectado durante la activación vuelve, sigue el '
      'corte y sube lo suyo', () async {
    await start([aritz, leo, nora]);
    ready([aritz, leo, nora]);
    await announceAll([aritz, leo, nora]);
    // Nora se queda sin conexión con un cambio local.
    nora.addGift('g-nora', 'leo', 'Tren');
    expect(
      (await aritz.engine(client).sync()).commonCutover,
      CommonCutover.activated,
    );
    await leo.engine(client).sync();
    // Su paquete v4 la espera.
    expect(
      (await snapshot()).keyPackages.where(
        (p) => FamilyKeyBundle.isV4(p) && p['to'] == 'nora-phone',
      ),
      isNotEmpty,
    );
    final back = await nora.engine(client).sync();
    expect(back.commonCutover, CommonCutover.followed);
    expect(back.commonStatus, RemoteCommonStatus.opened);
    expect(back.uploaded, isTrue);
    await syncAll([aritz, leo]);
    await expectCut([aritz, leo, nora], {'Libro', 'Tren'});
  });

  test('B4: arranque seguro compartido: con la marca, una generación nueva '
      'nace en formato 2 con el mínimo del Worker', () async {
    await vouchAll([aritz, leo]);
    await CommonV2Bootstrap.prepareFresh(aritz);
    expect(aritz.state.commonFormatV2, isTrue);
    await aritz.engine(client).ensureCreated();
    expect(worker.minCommonFormatOf(kV2Sync), 2);
    expect(worker.commonFormatOf(kV2Sync, 'aritz-phone'), 2);
    expect(isFamilyEnvelope(await serverCommon()), isTrue);
    expect(aritz.formatFloor, 2);
    // Sin clave legacy: una generación nueva no tiene nada en formato 1.
    expect(
      aritz.commonKeys.keyring.entries.where(
        (e) => e.references.contains(kLegacyRef),
      ),
      isEmpty,
    );
    // Solo con la marca (el estado perdido) también.
    final other = await MemoryV2Phone.create(
      'otro-phone',
      null,
      21,
      familyKey: key,
      syncId: 'UVJTVFVWV1hZWmFiY2RlZg',
    );
    other.formatFloor = 2;
    await other.engine(client).ensureCreated();
    expect(worker.minCommonFormatOf('UVJTVFVWV1hZWmFiY2RlZg'), 2);
    expect(other.state.commonFormatV2, isTrue);
  });
}
