// Lote B5 del ADR 0005: la web con la clave común por época. Llavero común
// en la caja, abrir por `kid`, firmar el común con la Ed25519 de la web,
// cola retenida si falta la clave o el reparto, corte con su marca
// irreversible y nada de candidatas, paquetes ni sorpresas.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/device_keys.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_candidate.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/family_envelope.dart';
import 'package:regalos/core/sync/family_key_bundle.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/wish.dart';
import 'package:regalos/features/sync/application/common_v2.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';
import 'package:regalos/features/sync/data/sync_transport_common.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';
import 'package:regalos/features/web_device/application/web_sync_engine.dart';
import 'package:regalos/features/web_device/application/web_common.dart';

import '../sync/v2_harness.dart';
import 'web_engine_support.dart';

FamilyDoc edit(FamilyDoc doc, String title, {String id = 'gift'}) => doc.set(
  HlcClock(node: 'web-edit', last: doc.maxStamp),
  Collections.gifts,
  id,
  {'recipientId': 'aritz', 'title': title},
);

void main() {
  late WebHarness h;
  late String webId;

  Future<V2Snapshot> snapshot() async =>
      (await h.client.getList(h.phone.auth) as V2GetOk).snapshot;

  Map<String, Object?> data() => h.vault.opened.data;

  Future<String> webSays(String title, {String id = 'gift'}) async {
    final before = h.engine.candidate!;
    await h.engine.save(before, edit(before, title, id: id));
    return title;
  }

  /// The phone cuts the family over (the web announced in its first sync).
  Future<void> cut() async {
    h.phone.commonV2Ready = true;
    for (var i = 0; i < 3 && h.worker.minCommonFormatOf(kV2Sync) < 2; i++) {
      await h.phone.engine(h.client).sync();
    }
    expect(h.worker.minCommonFormatOf(kV2Sync), 2);
  }

  /// As the phone: seals its document with [candidate] and uploads it with
  /// [packages] added to the server's (PUT S), or only the common.
  Future<void> phoneSeals(
    FamilyCandidate candidate, {
    List<Map<String, Object?>>? packages,
    int revision = 100,
    bool signedByWeb = false,
  }) async {
    final view = await h.phone.view();
    final bytes = signedByWeb
        ? await sealFamilyEnvelopeForTesting(
            doc: h.phone.doc,
            candidate: candidate,
            writer: view.me,
            writerRecord: view.self.recordDigest,
            revision: revision,
            signer: await DeviceKeys.fromJson(
              Map<String, Object?>.from(data()['deviceKeys']! as Map),
            ),
            nonce: List<int>.filled(12, 5),
          )
        : await sealFamilyEnvelope(
            doc: h.phone.doc,
            candidate: candidate,
            writer: view.self,
            revision: revision,
            signer: h.phone.keys,
          );
    final s = await snapshot();
    final result = packages == null
        ? await h.client.putCommon(
            h.phone.auth,
            version: s.version,
            common: bytes,
          )
        : await h.client.putList(
            h.phone.auth,
            version: s.version,
            body: V2SnapshotUpload(
              common: bytes,
              registry: Map<String, Object?>.from(s.registry! as Map),
              keyPackages: [...s.keyPackages, ...packages],
            ),
          );
    expect(result, isA<V2WriteOk>());
  }

  Future<void> publishRegistry(DeviceRegistry reg) async {
    final s = await snapshot();
    expect(
      await h.client.putList(
        h.phone.auth,
        version: s.version,
        body: V2SnapshotUpload(
          common: s.common,
          registry: Map<String, Object?>.from(reg.toJson() as Map),
          keyPackages: s.keyPackages,
        ),
      ),
      isA<V2WriteOk>(),
    );
  }

  Future<FamilyCandidate> fresh() async => FamilyCandidate.generate(
    await h.phone.view(),
    keys: h.phone.keys,
    syncId: kV2Sync,
  );

  Future<Map<String, Object?>> toWeb(FamilyCandidate c) async =>
      (await FamilyKeyBundle.seal(
        sender: h.phone.keys,
        view: await h.phone.view(),
        syncId: kV2Sync,
        toDevice: webId,
        candidate: c,
      )).toJson();

  tearDown(() => h.close());

  group('con la web dentro', () {
    setUp(() async {
      h = WebHarness(commonV2Ready: true);
      await h.setup();
      webId = h.vault.opened.header.deviceId;
    });

    test('la web anuncia una vez, la familia corta y la web sigue el corte '
        'con su marca, abre por kid y firma el común', () async {
      expect(h.worker.commonFormatOf(kV2Sync, webId), 2);
      final header = jsonEncode(h.vault.opened.header.toJson());
      final credential = data()['credential'];
      await cut();
      final cutKid = peekFamilyEnvelope((await snapshot()).common).kid;
      expect(webCommonFloor(data()), 1);
      await h.engine.sync();
      expect(webCommonFloor(data()), 2);
      expect(h.engine.commonStatus, RemoteCommonStatus.opened);
      var keys = webCommonKeys(data());
      expect(keys.lastKid, cutKid);
      // Received, never own: the web does not create candidates.
      expect(keys.keyring.entries.single.own, isFalse);
      expect(keys.keyring.entry(cutKid)!.references, contains(kCommonRef));
      expect(
        h.engine.candidate!.record(Collections.gifts, 'gift')!['title'],
        'Bufanda',
      );

      final packages = jsonEncode((await snapshot()).keyPackages);
      await webSays('Libro');
      await h.engine.sync();
      final common = (await snapshot()).common;
      final head = peekFamilyEnvelope(common);
      expect(head.writer, webId);
      expect(head.kid, cutKid);
      expect(head.revision, 1);
      expect(await h.queue.entries(), isEmpty);
      // The web never emits packages.
      expect(jsonEncode((await snapshot()).keyPackages), packages);
      keys = webCommonKeys(data());
      expect(keys.revision, 1);
      expect(keys.keyring.entries.every((e) => !e.own), isTrue);

      // The phone merges what the web signed.
      await h.phone.engine(h.client).sync();
      expect(h.phone.giftTitles, contains('Libro'));

      // PIN, guard and the vault secret do not change.
      expect(jsonEncode(h.vault.opened.header.toJson()), header);
      expect(data()['credential'], credential);
      h.engine.stop();
      h.vault.lock();
      await h.vault.unlock('123456');
      expect(webCommonKeys(data()).lastKid, isNotNull);
    });

    test('tras la marca nunca abre un formato 1, ni con un servidor que baja '
        'el mínimo', () async {
      await cut();
      await h.engine.sync();
      final saved = jsonEncode(data()['snapshot']);
      final v1 = await seal(
        doc: edit(h.phone.doc, 'Inyectado').toJson(),
        listId: kV2List,
        fromNode: 'node-aritz-phone',
        at: '2026-11-14T00:00:00Z',
        key: h.phone.familyKey,
      );
      h.worker.setCommonForTesting(kV2Sync, v1, minCommonFormat: 1);
      await expectLater(
        h.engine.sync(),
        throwsA(
          isA<SyncTransportException>().having(
            (e) => e.failure,
            'failure',
            SyncFailure.protocol,
          ),
        ),
      );
      expect(jsonEncode(data()['snapshot']), saved);
      expect(webCommonFloor(data()), 2);
      expect(
        h.engine.candidate!.record(Collections.gifts, 'gift')!['title'],
        'Bufanda',
      );
    });

    test('mínimo 2 con un común que no es formato 2, o un formato 2 sin la '
        'firma de un miembro: protocolo y sin marca', () async {
      await cut();
      final v1 = await seal(
        doc: h.phone.doc.toJson(),
        listId: kV2List,
        fromNode: 'node-aritz-phone',
        at: '2026-11-14T00:00:00Z',
        key: h.phone.familyKey,
      );
      final junk = Uint8List.fromList([0x52, 0x47, 0x02, 0, 3, 1, 2, 3, 4]);
      for (final bad in [v1, junk]) {
        h.worker.setCommonForTesting(kV2Sync, bad);
        await expectLater(
          h.engine.sync(),
          throwsA(
            isA<SyncTransportException>().having(
              (e) => e.failure,
              'failure',
              SyncFailure.protocol,
            ),
          ),
        );
        expect(webCommonFloor(data()), 1);
        expect(data()[kWebCommonKeysField], isNull);
      }
    });

    test(
      'un formato posterior pide actualizar, sin marcar ni guardar nada',
      () async {
        await cut();
        final snap = jsonEncode(data()['snapshot']);
        h.worker.setCommonForTesting(
          kV2Sync,
          Uint8List.fromList([0x52, 0x47, 0x03, 0, 0]),
          minCommonFormat: 3,
        );
        await expectLater(
          h.engine.sync(),
          throwsA(isA<EnvelopeFormatException>()),
        );
        expect(jsonEncode(data()['snapshot']), snap);
        expect(webCommonFloor(data()), 1);
      },
    );

    test('sin su candidata espera: retiene la cola cifrada, no sustituye ni '
        'publica; al llegar su paquete, publica', () async {
      await cut();
      await h.engine.sync();
      final first = webCommonKeys(data()).lastKid;
      final rotated = await fresh();
      await phoneSeals(rotated);
      final served = (await snapshot()).version;
      await webSays('Retenido');
      await h.engine.sync();
      expect(h.engine.commonStatus, RemoteCommonStatus.missingKey);
      expect(h.engine.commonHeld, isTrue);
      expect((await snapshot()).version, served);
      expect(await h.queue.entries(), hasLength(1));
      // Shown locally over the last common it could open.
      expect(
        h.engine.candidate!.record(Collections.gifts, 'gift')!['title'],
        'Retenido',
      );
      expect(webCommonKeys(data()).lastKid, first);
      expect(data()[kWebSeenVersionField], served);

      await phoneSeals(rotated, packages: [await toWeb(rotated)]);
      await h.engine.sync();
      expect(h.engine.commonStatus, RemoteCommonStatus.opened);
      expect(await h.queue.entries(), isEmpty);
      final head = peekFamilyEnvelope((await snapshot()).common);
      expect(head.writer, webId);
      expect(head.kid, rotated.kid);
    });

    test('repara deseos con la cola vacía tras un 412 en el común firmado', () async {
      await cut();
      await h.engine.sync();
      final keys = webCommonKeys(data());
      final candidate = keys.keyring.entry(keys.lastKid!)!.candidate;
      final clock = HlcClock(node: h.phone.node, last: h.phone.doc.maxStamp);
      h.phone.doc = h.phone.doc.set(clock, Collections.wishes, 'legacy', {
        'recipientId': 'nora',
        'authorPersonId': 'nora',
        'suggested': false,
        'title': 'Patinete',
        'description': 'Con luces',
        'url': 'https://example.com/patinete',
        'year': 2026,
      }).delete(clock, Collections.recipients, 'nora');
      await phoneSeals(candidate);
      expect(await h.queue.entries(), isEmpty);
      var conflicts = 0;
      h.worker.beforePut = (_) async {
        conflicts++;
        h.phone.doc = edit(h.phone.doc, 'Bufanda', id: 'remote-edit');
        await phoneSeals(candidate, revision: 101);
      };

      await h.engine.sync();

      expect(conflicts, 1);
      final bytes = (await snapshot()).common;
      expect(peekFamilyEnvelope(bytes).writer, webId);
      final view = await h.phone.view();
      final opened = await openFamilyEnvelope(
        bytes,
        expectedListId: kV2List,
        expectedSyncId: kV2Sync,
        resolveWriter: (writer, _) => view.member(writer)?.signingKey,
        keyring: webCommonKeys(data()).keyring,
      );
      final wish = opened.doc.record(Collections.wishes, 'legacy')!;
      expect(wish.isDeleted, isTrue);
      expect(wish.hasTombstoneContent, isFalse);
      expect(validateWishRecord(wish), isNull);
      expect(opened.doc.record(Collections.gifts, 'remote-edit')!['title'], 'Bufanda');
      expect(await h.queue.entries(), isEmpty);
    });

    test('dos candidatas recibidas en distinto orden: abre cada común por su '
        'kid, nunca por la última recibida', () async {
      await cut();
      await h.engine.sync();
      final a = await fresh();
      final b = await fresh();
      final (low, high) = a.kid.compareTo(b.kid) < 0 ? (a, b) : (b, a);
      // Packages arrive high first; the common is sealed with the low one.
      await phoneSeals(low, packages: [await toWeb(high), await toWeb(low)]);
      await h.engine.sync();
      expect(h.engine.commonStatus, RemoteCommonStatus.opened);
      expect(webCommonKeys(data()).lastKid, low.kid);
      await phoneSeals(high, revision: 101);
      await h.engine.sync();
      expect(h.engine.commonStatus, RemoteCommonStatus.opened);
      final keys = webCommonKeys(data());
      expect(keys.lastKid, high.kid);
      expect(keys.keyring.entry(low.kid), isNotNull);
      expect(keys.keyring.entry(high.kid)!.references, contains(kCommonRef));
      expect(
        keys.keyring.entry(low.kid)!.references,
        isNot(contains(kCommonRef)),
      );
    });

    test('un común firmado con otra clave bajo el nombre de un miembro no se '
        'fusiona y la cola se queda', () async {
      await cut();
      await h.engine.sync();
      final c = await fresh();
      h.phone.doc = edit(h.phone.doc, 'Falso', id: 'other');
      await phoneSeals(c, packages: [await toWeb(c)], signedByWeb: true);
      await webSays('Mio');
      await h.engine.sync();
      expect(h.engine.commonStatus, RemoteCommonStatus.forged);
      expect(h.engine.commonHeld, isTrue);
      expect(await h.queue.entries(), hasLength(1));
      expect(h.engine.candidate!.record(Collections.gifts, 'other'), isNull);
      expect(
        h.engine.candidate!.record(Collections.gifts, 'gift')!['title'],
        'Mio',
      );
    });

    test('cambio de PIN a la vez que llega una rotación: el llavero entra en '
        'la caja nueva y el PIN nuevo la abre', () async {
      await cut();
      await h.engine.sync();
      final rotated = await fresh();
      await phoneSeals(rotated, packages: [await toWeb(rotated)]);
      await Future.wait([h.engine.sync(), h.vault.changePin('654321')]);
      await h.engine.sync();
      expect(webCommonKeys(data()).lastKid, rotated.kid);
      h.engine.stop();
      h.vault.lock();
      await h.vault.unlock('654321');
      expect(webCommonKeys(data()).lastKid, rotated.kid);
      expect(webCommonFloor(data()), 2);
    });

    group('M1: la cola solo se confirma con un común que la '
        'contiene', () {
      void afterWebPut(Uint8List Function() common) {
        var done = false;
        h.worker.tamper = (method, uri, response) {
          if (!done &&
              method == 'PUT' &&
              uri.path.endsWith('/common') &&
              response.status == 200) {
            done = true;
            h.worker.setCommonForTesting(kV2Sync, common());
          }
          return response;
        };
      }

      test(
        'basura RG 0x02 tras el PUT: la cola y el cambio se quedan',
        () async {
          await cut();
          await h.engine.sync();
          await webSays('Libro');
          afterWebPut(
            () => Uint8List.fromList([0x52, 0x47, 0x02, 0, 3, 1, 2, 3, 4]),
          );
          await h.engine.sync();
          expect(h.engine.commonStatus, RemoteCommonStatus.forged);
          expect(await h.queue.entries(), hasLength(1));
          expect(
            h.engine.candidate!.record(Collections.gifts, 'gift')!['title'],
            'Libro',
          );
        },
      );

      test('un común de un miembro que la web no abre (missingKey) tras el '
          'PUT: la cola se queda', () async {
        await cut();
        await h.engine.sync();
        await webSays('Libro');
        final view = await h.phone.view();
        final rotated = await fresh();
        final bytes = await sealFamilyEnvelope(
          doc: h.phone.doc,
          candidate: rotated,
          writer: view.self,
          revision: 100,
          signer: h.phone.keys,
        );
        afterWebPut(() => bytes);
        await h.engine.sync();
        expect(h.engine.commonStatus, RemoteCommonStatus.missingKey);
        expect(await h.queue.entries(), hasLength(1));
        expect(
          h.engine.candidate!.record(Collections.gifts, 'gift')!['title'],
          'Libro',
        );
      });

      test(
        'un común que abre pero no lleva el cambio: la cola se queda',
        () async {
          await cut();
          await h.engine.sync();
          final keys = webCommonKeys(data());
          final candidate = keys.keyring.entry(keys.lastKid!)!.candidate;
          await webSays('Libro');
          final view = await h.phone.view();
          final bytes = await sealFamilyEnvelope(
            doc: h.phone.doc,
            candidate: candidate,
            writer: view.self,
            revision: 100,
            signer: h.phone.keys,
          );
          afterWebPut(() => bytes);
          await h.engine.sync();
          expect(h.engine.commonStatus, RemoteCommonStatus.opened);
          expect(await h.queue.entries(), hasLength(1));
        },
      );
    });

    test('412: vuelve a leer, vuelve a aplicar el filtro con el común nuevo '
        'y no publica lo que ya no puede', () async {
      await cut();
      await h.engine.sync();
      final keys = webCommonKeys(data());
      final candidate = keys.keyring.entry(keys.lastKid!)!.candidate;
      await webSays('Libro');
      // Another writer between the web's GET and PUT: a policy for Aritz,
      // so the web's gift for Aritz is no longer publishable.
      h.worker.beforePut = (_) async {
        h.phone.doc = h.phone.doc.set(
          h.phone.clock,
          Collections.policies,
          'aritz',
          {'hideOwnGifts': false},
        );
        await phoneSeals(candidate, revision: 200);
      };
      await h.engine.sync();
      expect(h.worker.beforePut, isNull);
      final head = peekFamilyEnvelope((await snapshot()).common);
      expect(head.writer, 'aritz-phone');
      expect(head.revision, 200);
      final left = await h.queue.entries();
      expect(left, hasLength(1));
      expect(left.single.setAside, isTrue);
    });

    test(
      '412 con un cambio publicable: publica sobre el común del otro',
      () async {
        await cut();
        await h.engine.sync();
        final keys = webCommonKeys(data());
        final candidate = keys.keyring.entry(keys.lastKid!)!.candidate;
        await webSays('Libro');
        h.worker.beforePut = (_) async {
          h.phone.addGift('other', 'nora', 'Del móvil');
          await phoneSeals(candidate, revision: 200);
        };
        await h.engine.sync();
        expect(await h.queue.entries(), isEmpty);
        final head = peekFamilyEnvelope((await snapshot()).common);
        expect(head.writer, webId);
        final doc = await h.engine.savedCommon();
        expect(doc.record(Collections.gifts, 'gift')!['title'], 'Libro');
        expect(doc.record(Collections.gifts, 'other')!['title'], 'Del móvil');
      },
    );

    test('la web sin confirmar en formato 2 no publica', () async {
      await cut();
      await h.engine.sync();
      final record = await DeviceRecord.create(
        keys: h.guest.keys,
        listId: kV2List,
        deviceId: webId,
        personId: 'leo',
        seq: 2,
        kind: DeviceKind.web,
      );
      final reg = await h.phone.reg.withRecord(
        record,
        anchor: (await h.phone.view()).anchor,
      );
      await publishRegistry(reg);
      await webSays('Libro');
      final before = (await snapshot()).version;
      await h.engine.sync();
      expect(h.engine.status, WebSyncStatus.pending);
      expect((await snapshot()).version, before);
      expect(await h.queue.entries(), hasLength(1));
    });

    test('la raíz revocada por otro móvil: lo que firma ya no se fusiona y la '
        'web no publica', () async {
      await cut();
      await h.engine.sync();
      final leo = await MemoryV2Phone.create(
        'leo-phone',
        'leo',
        2,
        familyKey: h.phone.familyKey,
      );
      var reg = await h.phone.reg.merge(leo.reg);
      reg = await reg.withVouch(
        await Vouch.create(
          keys: h.phone.keys,
          voucher: h.phone.record,
          record: leo.record,
        ),
      );
      reg = await reg.withVouch(
        await Vouch.create(
          keys: leo.keys,
          voucher: leo.record,
          record: h.phone.record,
        ),
      );
      await publishRegistry(reg);
      await h.engine.sync();
      expect(data()['roots'] as List, hasLength(2));
      leo.reg = reg;
      final change = await revokeDevice(
        registry: reg,
        view: await leo.view(),
        myKeys: leo.keys,
        deviceId: 'aritz-phone',
      );
      h.phone.doc = edit(h.phone.doc, 'Del revocado', id: 'other');
      final keys = webCommonKeys(data());
      final candidate = keys.keyring.entry(keys.lastKid!)!.candidate;
      final view = await h.phone.view();
      final bytes = await sealFamilyEnvelope(
        doc: h.phone.doc,
        candidate: candidate,
        writer: view.self,
        revision: 300,
        signer: h.phone.keys,
      );
      final s = await snapshot();
      expect(
        await h.client.putList(
          h.phone.auth,
          version: s.version,
          body: V2SnapshotUpload(
            common: bytes,
            registry: Map<String, Object?>.from(
              change.registry.toJson() as Map,
            ),
            keyPackages: s.keyPackages,
          ),
        ),
        isA<V2WriteOk>(),
      );
      await webSays('Libro');
      final before = (await snapshot()).version;
      await h.engine.sync();
      expect(h.engine.commonStatus, RemoteCommonStatus.revokedWriter);
      expect(h.engine.candidate!.record(Collections.gifts, 'other'), isNull);
      expect((await snapshot()).version, before);
      expect(await h.queue.entries(), hasLength(1));
    });

    test('B2: un común sin firma de un miembro no sube seenVersion', () async {
      await cut();
      await h.engine.sync();
      final seen = data()[kWebSeenVersionField];
      final c = await fresh();
      await phoneSeals(c, packages: [await toWeb(c)], signedByWeb: true);
      await h.engine.sync();
      expect(h.engine.commonStatus, RemoteCommonStatus.forged);
      expect(data()[kWebSeenVersionField], seen);
    });

    test('el estado de la clave común perdido con la marca no vuelve a '
        'empezar de cero', () async {
      await cut();
      await h.engine.sync();
      await h.vault.saveData({...data()}..remove(kWebCommonKeysField));
      await expectLater(h.engine.sync(), throwsA(isA<CommonStateException>()));
    });
  });

  test('B3: si anunciar falla (respuesta perdida), la web sigue '
      'leyendo y se confirma igual', () async {
    h = WebHarness(commonV2Ready: true);
    var failed = 0;
    h.worker.tamper = (method, uri, response) {
      if (method == 'POST' && uri.path.endsWith('/capability')) {
        failed++;
        return SyncResponse(503, const {}, Uint8List(0));
      }
      return response;
    };
    await h.setup();
    webId = h.vault.opened.header.deviceId;
    expect(failed, greaterThan(0));
    expect(h.engine.status, WebSyncStatus.confirmed);
    expect(h.engine.candidate, isNotNull);
  });

  test(
    'sin el interruptor la web no anuncia y una familia con web no corta',
    () async {
      h = WebHarness();
      await h.setup();
      webId = h.vault.opened.header.deviceId;
      expect(h.worker.commonFormatOf(kV2Sync, webId), 1);
      h.phone.commonV2Ready = true;
      await h.phone.engine(h.client).sync();
      await h.phone.engine(h.client).sync();
      expect(h.worker.minCommonFormatOf(kV2Sync), 1);
      await h.engine.sync();
      expect(h.engine.commonStatus, isNull);
      expect(data()[kWebCommonKeysField], isNull);
    },
  );
}
