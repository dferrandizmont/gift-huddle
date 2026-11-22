import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/pairing_v2.dart';
import 'package:regalos/core/sync/protected_doc.dart';
import 'package:regalos/features/sync/application/family_devices.dart';
import 'package:regalos/features/sync/application/sync_v2_engine.dart';
import 'package:regalos/features/sync/application/v2_health.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';
import 'package:regalos/features/sync/data/sync_transport_common.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';

import '../helpers/fake_worker_v2.dart';
import 'v2_harness.dart';

SyncResponse _json(SyncResponse r, Map<String, Object?> body, {int? etag}) =>
    SyncResponse(r.status, {
      ...r.headers,
      if (etag != null) 'etag': '"$etag"',
    }, Uint8List.fromList(utf8.encode(jsonEncode(body))));

void main() {
  late FakeWorkerV2 worker;
  late SyncV2Client client;
  late MemoryV2Phone aritz;
  late MemoryV2Phone leo;
  late MemoryV2Phone nora;

  /// Las sorpresas de Nora, época 1, que tienen Aritz y Leo.
  SurpriseKey noraKey() => SurpriseKey(
    personId: 'nora',
    epoch: 1,
    bytes: List<int>.filled(32, 42),
    audience: const ['aritz-phone', 'leo-phone'],
  );

  setUp(() async {
    worker = FakeWorkerV2();
    client = worker.client();
    final key = await FamilyKey.generate();
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
      ..addPerson('nora', 'Nora');
    await vouchAll([aritz, leo, nora]);
    await aritz.engine(client).ensureCreated();
    for (final p in [leo, nora]) {
      worker.addCredentialForTesting(
        kV2Sync,
        p.identity.deviceId,
        p.keys.serviceCredential,
      );
    }
  });

  group('instantánea y fusión', () {
    for (final withoutPerson in [true, false]) {
      test(
        'ronda 4: intermediario ${withoutPerson ? "sin persona" : "sin derecho"} '
        'conserva el paquete de A para B desconectado',
        () async {
          if (withoutPerson) {
            nora = await MemoryV2Phone.create(
              'relay-c',
              null,
              4,
              familyKey: aritz.familyKey,
            );
            await vouchAll([aritz, leo, nora]);
            worker.addCredentialForTesting(
              kV2Sync,
              'relay-c',
              nora.keys.serviceCredential,
            );
          }
          // B (Leo) aún no tiene la clave: A debe repartirla una sola vez.
          aritz.keyring = SurpriseKeyring([
            SurpriseKey(
              personId: 'nora',
              epoch: 1,
              bytes: noraKey().bytes,
              audience: const ['aritz-phone'],
            ),
          ]);
          await aritz.engine(client).sync();
          expect(aritz.state.keyPackageOutbox, isEmpty);
          final before = (await client.getList(aritz.auth) as V2GetOk).snapshot;
          final package = before.keyPackages.singleWhere(
            (p) => p['to'] == 'leo-phone',
          );
          nora.addGift(
            'from-c',
            'aritz',
            'Libro',
          ); // Fuerza el PUT del intermediario.
          final outcome = await nora.engine(client).sync();
          expect(outcome.uploaded, isTrue);
          final after = (await client.getList(aritz.auth) as V2GetOk).snapshot;
          expect(
            after.keyPackages.any((p) => jsonEncode(p) == jsonEncode(package)),
            isTrue,
          );
          await leo.engine(client).sync();
          expect(leo.keyring.latestFor('nora')!.bytes, noraKey().bytes);
        },
      );
    }

    test('ronda 4: huérfano conocido conserva credencial tras poda al límite '
        'del registro y reinicio', () async {
      // A -> B -> C: el único aval de C viene de B.
      leo = await MemoryV2Phone.create(
        'orphan-c',
        'leo',
        4,
        familyKey: aritz.familyKey,
      );
      var registry = DeviceRegistry.empty(kV2List);
      for (final p in [aritz, nora, leo]) {
        registry = await registry.withRecord(p.record);
      }
      for (final (a, b) in [(aritz, nora), (nora, aritz), (nora, leo)]) {
        registry = await registry.withVouch(
          await Vouch.create(keys: a.keys, voucher: a.record, record: b.record),
        );
      }
      aritz.reg = registry;
      // Procedencia real de C en el servidor: fue aprobado por B.
      worker.addCredentialForTesting(
        kV2Sync,
        'orphan-c',
        leo.keys.serviceCredential,
        approvedBy: 'nora-phone',
      );
      await aritz.engine(client).sync();
      await removeDevice(
        transport: client,
        local: aritz,
        deviceId: 'nora-phone',
      );
      expect((await aritz.view()).everMembers, contains('orphan-c'));
      // Llena las 64 fichas; todas las nuevas están enlazadas a A. La poda
      // acaba desalojando C y su aval, que solo colgaban del revocado B.
      var voucherId = 'aritz-phone';
      for (var i = 0; i < kMaxRegistryRecords; i++) {
        if (!(await aritz.view()).everMembers.contains('orphan-c')) break;
        final record = await DeviceRecord.create(
          keys: aritz.keys,
          listId: kV2List,
          deviceId: 'extra-$i',
          personId: 'aritz',
        );
        final view = await aritz.reg.viewFor(
          me: voucherId,
          mySigningKey: aritz.keys.publicKeys.signing,
          livePeople: livePeopleOf(aritz.doc),
        );
        aritz.reg = (await approveDevice(
          registry: aritz.reg,
          view: view,
          myKeys: aritz.keys,
          record: record,
        )).registry;
        aritz.reg = await aritz.reg.withVouch(
          await Vouch.create(
            keys: aritz.keys,
            voucher: record,
            record: aritz.reg.recordByDigest(view.self.recordDigest)!,
          ),
          anchor: (await aritz.view()).anchor,
        );
        voucherId = record.deviceId;
        // Publica en lotes separados por 24 h para respetar también los
        // cupos del Worker, sin inventar un registro remoto imposible.
        if (i % 8 == 7 ||
            !(await aritz.view()).everMembers.contains('orphan-c')) {
          await withClock(Clock.fixed(DateTime(2030, 1, i + 1)), () async {
            final snap = (await client.getList(aritz.auth) as V2GetOk).snapshot;
            expect(
              await client.putList(
                aritz.auth,
                version: snap.version,
                body: V2SnapshotUpload(
                  common: snap.common,
                  registry: aritz.reg.toJson(),
                  keyPackages: snap.keyPackages,
                ),
              ),
              isA<V2WriteOk>(),
            );
          });
        }
      }
      expect(aritz.reg.records, hasLength(kMaxRegistryRecords));
      expect((await aritz.view()).everMembers, isNot(contains('orphan-c')));
      // El servidor también recibe el registro podado; no puede rescatar
      // la evidencia histórica en la siguiente vuelta.
      aritz.state = V2SyncState.fromJson(
        jsonDecode(jsonEncode(aritz.state.toJson())),
      );
      await aritz.engine(client).sync();
      expect(worker.devicesOf(kV2Sync)['orphan-c'], isFalse);
      expect(await client.getList(leo.auth), isA<V2GetOk>());
    });

    test('ronda 2: outbox no entrega al perder el único avalista tras fallo '
        'PUT y reinicio', () async {
      aritz.addPerson('protected', 'Nora');
      var registry = DeviceRegistry.empty(kV2List);
      for (final p in [aritz, nora, leo]) {
        registry = await registry.withRecord(p.record);
      }
      for (final (a, b) in [
        (aritz, nora),
        (nora, aritz),
        (nora, leo),
        (leo, nora),
      ]) {
        registry = await registry.withVouch(
          await Vouch.create(keys: a.keys, voucher: a.record, record: b.record),
        );
      }
      aritz.reg = registry;
      final got = await client.getList(aritz.auth) as V2GetOk;
      await client.putList(
        aritz.auth,
        version: got.snapshot.version,
        body: V2SnapshotUpload(
          common: got.snapshot.common,
          registry: registry.toJson(),
          keyPackages: const [],
        ),
      );
      aritz.keyring = SurpriseKeyring([
        SurpriseKey(
          personId: 'protected',
          epoch: 1,
          bytes: List.filled(32, 42),
          audience: const ['aritz-phone'],
        ),
      ]);
      worker.beforePut = (_) async {
        throw const SyncTransportException(SyncFailure.network, 'cierre');
      };
      await expectLater(
        aritz.engine(client).sync(),
        throwsA(isA<SyncTransportException>()),
      );
      expect(
        aritz.state.keyPackageOutbox.where((p) => p['to'] == 'leo-phone'),
        isNotEmpty,
      );
      aritz.reg = (await revokeDevice(
        registry: aritz.reg,
        view: await aritz.view(),
        myKeys: aritz.keys,
        deviceId: 'nora-phone',
      )).registry;
      aritz.state = V2SyncState.fromJson(
        jsonDecode(jsonEncode(aritz.state.toJson())),
      );
      final guarded = SyncV2Client(
        base: client.base,
        sendRequest: (method, uri, {body, headers = const {}}) async {
          if (method == 'PUT') {
            expect(
              ((body as Map)['keyPackages'] as List).where(
                (p) => (p as Map)['to'] == 'leo-phone',
              ),
              isEmpty,
              reason: 'estar huérfano no autoriza recibir la clave pendiente',
            );
          }
          return worker.send(method, uri, body: body, headers: headers);
        },
      );
      await aritz.engine(guarded).sync();
      expect(aritz.state.keyPackageOutbox, isEmpty);
      expect(worker.devicesOf(kV2Sync)['leo-phone'], isFalse);
    });

    test('ronda 2: invitaciones reales T -> X -> Y -> Z, incluso con X ya '
        'revocado en el servicio, conservan la raíz del corte', () async {
      Future<MemoryV2Phone> hidden(
        MemoryV2Phone parent,
        String id,
        int seed,
      ) async {
        final child = await MemoryV2Phone.create(
          id,
          'leo',
          seed,
          familyKey: aritz.familyKey,
        );
        parent.doc = aritz.doc;
        final session = PairingHost.start(parent.reg, await parent.view());
        final ticket = await client.createInvite(
          parent.auth,
          session.offer.toJson(),
        );
        final join = await joinPairing(
          offer: session.offer,
          keys: child.keys,
          deviceId: id,
          personId: 'leo',
        );
        await client.answerInvite(
          ticket.inviteId,
          answer: join.answer.toJson(),
          verifier: await child.keys.serviceCredentialVerifier(),
        );
        final reveal = await session.receive(join.answer);
        await client.revealInvite(
          parent.auth,
          ticket.inviteId,
          reveal.toJson(),
        );
        final snap = (await client.getList(parent.auth) as V2GetOk).snapshot;
        expect(
          await client.approveInvite(
            parent.auth,
            ticket.inviteId,
            version: snap.version,
            package: {'hidden': true},
          ),
          isA<V2WriteOk>(),
        );
        // El atacante entrega el registro por otro canal: nunca lo publica.
        child.reg = (await acceptPairing(
          registry: parent.reg,
          view: await parent.view(),
          myKeys: parent.keys,
          session: session,
          confirmedPersonId: 'leo',
        )).registry;
        child.doc = aritz.doc;
        return child;
      }

      final x = await hidden(nora, 'hidden-x', 11);
      final y = await hidden(x, 'hidden-y', 12);
      final z = await hidden(y, 'hidden-z', 13);
      await client.revoke(aritz.auth, x.identity.deviceId);
      await removeDevice(
        transport: client,
        local: aritz,
        deviceId: 'nora-phone',
      );
      for (final p in [nora, x, y, z]) {
        expect(worker.devicesOf(kV2Sync)[p.identity.deviceId], isTrue);
        await expectLater(
          client.getList(p.auth),
          throwsA(isA<SyncTransportException>()),
        );
        await expectLater(
          client.createInvite(
            p.auth,
            PairingHost.start(p.reg, await p.view()).offer.toJson(),
          ),
          throwsA(isA<SyncTransportException>()),
        );
      }
    });

    for (final targetPerson in ['nora', 'aritz']) {
      test('ronda 2: outbox revalida la ficha tras fallo PUT, cambio a '
          '$targetPerson y reinicio', () async {
        aritz.keyring = SurpriseKeyring([
          SurpriseKey(
            personId: 'nora',
            epoch: 1,
            bytes: List.filled(32, 42),
            audience: const ['aritz-phone'],
          ),
        ]);
        worker.beforePut = (_) async {
          throw const SyncTransportException(SyncFailure.network, 'cierre');
        };
        await expectLater(
          aritz.engine(client).sync(),
          throwsA(isA<SyncTransportException>()),
        );
        final queued = aritz.state.keyPackageOutbox
            .where((p) => p['to'] == 'leo-phone')
            .map(jsonEncode)
            .toSet();
        expect(queued, isNotEmpty);
        final changed = await changePerson(
          registry: leo.reg,
          view: await leo.view(),
          myKeys: leo.keys,
          personId: targetPerson,
        );
        aritz.reg = await aritz.reg.merge(
          changed.registry,
          anchor: (await aritz.view()).anchor,
        );
        if (targetPerson == 'aritz') {
          final record = changed.registry.records
              .where((r) => r.deviceId == 'leo-phone')
              .reduce((a, b) => a.seq > b.seq ? a : b);
          aritz.reg = (await approveDevice(
            registry: aritz.reg,
            view: await aritz.view(),
            myKeys: aritz.keys,
            record: record,
          )).registry;
        }
        aritz.state = V2SyncState.fromJson(
          jsonDecode(jsonEncode(aritz.state.toJson())),
        );
        var puts = 0;
        final guarded = SyncV2Client(
          base: client.base,
          sendRequest: (method, uri, {body, headers = const {}}) async {
            if (method == 'PUT') {
              puts++;
              final upload = body as Map;
              expect(
                (upload['keyPackages'] as List)
                    .map(jsonEncode)
                    .toSet()
                    .intersection(queued),
                isEmpty,
                reason:
                    'ni siquiera se transmite el paquete con la ficha antigua',
              );
              if (targetPerson == 'nora') {
                expect(
                  (upload['keyPackages'] as List).where(
                    (p) => (p as Map)['to'] == 'leo-phone',
                  ),
                  isEmpty,
                );
              }
            }
            return worker.send(method, uri, body: body, headers: headers);
          },
        );
        await aritz.engine(guarded).sync();
        expect(puts, greaterThan(0));
        expect(aritz.state.keyPackageOutbox, isEmpty);
        final snap = (await client.getList(aritz.auth) as V2GetOk).snapshot;
        if (targetPerson == 'aritz') {
          expect(
            snap.keyPackages.where((p) => p['to'] == 'leo-phone'),
            isNotEmpty,
            reason: 'con derecho actual se genera un paquete nuevo',
          );
        }
      });
    }

    test(
      '4: revocar sin red persiste; al reabrir corta antes del PUT y reintenta',
      () async {
        final puts = worker.calls['PUT list'];
        var cuts = 0;
        final failing = SyncV2Client(
          base: client.base,
          sendRequest: (method, uri, {body, headers = const {}}) async {
            if (uri.path.endsWith('/revoke')) {
              cuts++;
              throw const SyncTransportException(SyncFailure.network, 'corte');
            }
            return worker.send(method, uri, body: body, headers: headers);
          },
        );
        await expectLater(
          removeDevice(
            transport: failing,
            local: aritz,
            deviceId: 'nora-phone',
          ),
          throwsA(isA<SyncTransportException>()),
        );
        expect(cuts, 3);
        expect(worker.calls['PUT list'], puts);
        aritz.state = V2SyncState.fromJson(
          jsonDecode(jsonEncode(aritz.state.toJson())),
        );
        expect(aritz.state.pendingRevocations, {'nora-phone'});
        var tries = 0;
        final retry = SyncV2Client(
          base: client.base,
          sendRequest: (method, uri, {body, headers = const {}}) async {
            if (uri.path.endsWith('/revoke') && tries++ == 0) {
              throw const SyncTransportException(
                SyncFailure.network,
                'corte transitorio',
              );
            }
            if (method == 'PUT') {
              expect(
                worker.devicesOf(kV2Sync)['nora-phone'],
                isTrue,
                reason: 'corta antes de publicar el registro',
              );
            }
            return worker.send(method, uri, body: body, headers: headers);
          },
        );
        await aritz.engine(retry).sync();
        expect(tries, 2);
        expect(aritz.state.pendingRevocations, isEmpty);
      },
    );

    test('4: un segundo móvil corta credenciales revocadas y las aprobadas '
        'por el revocado sin ficha respaldada', () async {
      final change = await revokeDevice(
        registry: aritz.reg,
        view: await aritz.view(),
        myKeys: aritz.keys,
        deviceId: 'nora-phone',
      );
      // El registro ya publicado por otra vía, sin POST /revoke.
      final got = await client.getList(aritz.auth) as V2GetOk;
      await client.putList(
        aritz.auth,
        version: got.snapshot.version,
        body: V2SnapshotUpload(
          common: got.snapshot.common,
          registry: change.registry.toJson(),
          keyPackages: const [],
        ),
      );
      worker.addCredentialForTesting(
        kV2Sync,
        'intruso',
        Uint8List(32),
        approvedBy: 'nora-phone',
      );
      await leo.engine(client).sync();
      expect(worker.devicesOf(kV2Sync)['nora-phone'], isTrue);
      expect(worker.devicesOf(kV2Sync)['intruso'], isTrue);
      expect(worker.devicesOf(kV2Sync)['aritz-phone'], isFalse);
    });

    for (final failure in ['412', 'network']) {
      for (final rotating in [false, true]) {
        test('9: outbox ${rotating ? "rotación" : "nuevo miembro"} sobrevive '
            '$failure y reinicio, y entrega la misma clave', () async {
          aritz.keyring = SurpriseKeyring([
            SurpriseKey(
              personId: 'nora',
              epoch: 1,
              bytes: List.filled(32, 42),
              audience: const ['aritz-phone'],
            ),
          ]);
          if (rotating) {
            aritz.reg = (await revokeDevice(
              registry: aritz.reg,
              view: await aritz.view(),
              myKeys: aritz.keys,
              deviceId: 'nora-phone',
            )).registry;
            await client.revoke(aritz.auth, 'nora-phone');
          }
          worker.beforePut = (_) async {
            if (failure == 'network') {
              throw const SyncTransportException(SyncFailure.network, 'cierre');
            }
            leo.addGift('race', 'aritz', 'Libro');
            await leo.engine(client).sync();
          };
          await expectLater(
            SyncV2Engine(
              transport: client,
              local: aritz,
              maxRestarts: 0,
            ).sync(),
            throwsA(isA<SyncTransportException>()),
          );
          // JSON es lo único que conserva el motor al cerrar la app.
          aritz.state = V2SyncState.fromJson(
            jsonDecode(jsonEncode(aritz.state.toJson())),
          );
          expect(aritz.state.keyPackageOutbox, isNotEmpty);
          final kid = aritz.keyring.latestFor('nora')!.kid;
          await aritz.engine(client).sync();
          expect(aritz.state.keyPackageOutbox, isEmpty);
          await leo.engine(client).sync();
          expect(leo.keyring.latestFor('nora')!.kid, kid);
        });
      }
    }

    test(
      'crear es idempotente y una vuelta sin cambios no sube nada',
      () async {
        expect(worker.versionOf(kV2Sync), 1);
        await aritz.engine(client).ensureCreated();
        expect(worker.calls['PUT list'], 1);
        final out = await aritz.engine(client).sync();
        expect(out.uploaded, isFalse);
        expect(out.version, 1);
        expect(worker.calls['PUT list'], 1);
      },
    );

    test('lo de un móvil llega a los demás y se fusiona sin perder nada '
        'con dos escritores a la vez (412 y vuelta a empezar)', () async {
      await leo.engine(client).sync();
      expect(leo.doc.record('recipients', 'nora'), isNotNull);
      aritz.addGift('g1', 'nora', 'Bufanda');
      leo.addGift('g2', 'aritz', 'Libro');
      // Leo escribe justo antes de que llegue el PUT de Aritz.
      worker.beforePut = (_) async {
        await leo.engine(client).sync();
      };
      final out = await aritz.engine(client).sync();
      expect(out.uploaded, isTrue);
      expect(
        worker.calls['PUT list'],
        4,
        reason: 'crear, Aritz (412), Leo y Aritz otra vez',
      );
      await leo.engine(client).sync();
      expect(aritz.giftTitles, {'Bufanda', 'Libro'});
      expect(leo.giftTitles, {'Bufanda', 'Libro'});
    });

    test('ataque: un servidor que sirve un estado más viejo se rechaza y no '
        'se sube nada', () async {
      aritz.addGift('g1', 'leo', 'Pelota');
      await aritz.engine(client).sync();
      expect(aritz.state.version, 2);
      worker.tamper = (method, uri, r) => method == 'GET' && r.status == 200
          ? _json(r, {...r.json(), 'version': 1}, etag: 1)
          : r;
      aritz.addGift('g2', 'leo', 'Cometa');
      await expectLater(
        aritz.engine(client).sync(),
        throwsA(isA<V2RollbackException>()),
      );
      expect(worker.versionOf(kV2Sync), 2);
    });

    test('ataque: un sobre común de otra lista no se fusiona', () async {
      final other = await seal(
        doc: aritz.doc.toJson(),
        listId: 'otra-lista',
        fromNode: 'x',
        at: '',
        key: aritz.familyKey,
      );
      worker.tamper = (method, uri, r) => method == 'GET' && r.status == 200
          ? _json(r, {...r.json(), 'common': encodeBase64Url(other)})
          : r;
      await expectLater(
        leo.engine(client).sync(),
        throwsA(isA<EnvelopeException>()),
      );
      expect(leo.merges, 0);
    });

    test('ataque (hallazgo 1): un común con la marca bajada a 1 no deja a la '
        'familia sin sincronizar; el primer móvil v2 lo repara', () async {
      await aritz.engine(client).sync();
      await leo.engine(client).sync();
      expect(syncProtocolOf(leo.doc), kSyncProtocolV2);
      // Leo (o un móvil viejo) sube el común con la marca en 1, más nueva.
      leo.doc = leo.doc.set(
        HlcClock(node: 'node-leo-phone', last: leo.doc.maxStamp),
        Collections.meta,
        kProtocolRecordId,
        {kProtocolVersionField: 1},
      );
      await leo.engine(client).sync();
      // Aritz lo acepta, vuelve a marcar 2 y lo sube en la misma vuelta.
      final out = await aritz.engine(client).sync();
      expect(out.uploaded, isTrue);
      expect(syncProtocolOf(aritz.doc), kSyncProtocolV2);
      // Nora, que no ha visto nada raro, recibe el común ya reparado.
      await nora.engine(client).sync();
      expect(syncProtocolOf(nora.doc), kSyncProtocolV2);
      // Y una versión desconocida sigue sin entrar.
      leo.doc = leo.doc.set(
        HlcClock(node: 'node-leo-phone', last: leo.doc.maxStamp),
        Collections.meta,
        kProtocolRecordId,
        {kProtocolVersionField: 99},
      );
      await leo.engine(client).sync();
      await expectLater(
        nora.engine(client).sync(),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });

    test('la credencial revocada no lee ni escribe', () async {
      await client.revoke(aritz.auth, 'nora-phone');
      nora.addGift('g1', 'aritz', 'Taza');
      await expectLater(
        nora.engine(client).sync(),
        throwsA(
          isA<SyncTransportException>().having(
            (e) => e.failure,
            'failure',
            SyncFailure.unauthorized,
          ),
        ),
      );
      expect(worker.versionOf(kV2Sync), 2, reason: 'solo la revocación');
      expect(
        nora.state.health?.revokedByOthers ?? false,
        isFalse,
        reason: 'the ordinary list route only reports a generic 401',
      );
    });

    test(
      'transient 401 does not persist removal and the next sync succeeds',
      () async {
        worker.tamper = (method, uri, response) => SyncResponse(
          401,
          const {},
          Uint8List.fromList(utf8.encode('{"error":"unauthorized"}')),
        );
        await expectLater(
          leo.engine(client).sync(),
          throwsA(
            isA<SyncTransportException>().having(
              (e) => e.failure,
              'failure',
              SyncFailure.unauthorized,
            ),
          ),
        );
        expect(leo.state.health?.revokedByOthers ?? false, isFalse);
        leo.state = V2SyncState.fromJson(leo.state.toJson());
        worker.tamper = null;
        final out = await leo.engine(client).sync();
        expect(out.view.revokedByOthers, isFalse);
        expect(leo.state.health!.revokedByOthers, isFalse);
      },
    );

    test('explicit server revocation persists confirmed removal', () async {
      worker.tamper = (method, uri, response) => SyncResponse(
        403,
        const {},
        Uint8List.fromList(utf8.encode('{"error":"revoked"}')),
      );
      await expectLater(
        leo.engine(client).sync(),
        throwsA(isA<V2RevokedException>()),
      );
      expect(leo.state.health!.revokedByOthers, isTrue);
      expect(
        V2SyncState.fromJson(leo.state.toJson()).health!.revokedByOthers,
        isTrue,
      );
    });

    test('una credencial que el registro no respalda se señala', () async {
      worker.addCredentialForTesting(
        kV2Sync,
        'intruso',
        Uint8List.fromList(List.filled(32, 77)),
      );
      final out = await aritz.engine(client).sync();
      expect(out.unbackedCredentials, ['intruso']);
    });
  });

  group('slots y claves', () {
    setUp(() {
      aritz.keyring = SurpriseKeyring([noraKey()]);
      leo.keyring = SurpriseKeyring([noraKey()]);
    });

    test(
      '15: dos huérfanos con vistas distintas no borran mutuamente sus slots',
      () async {
        // Aritz y Leo solo se conocen a través de Nora.
        // El puente es de Aritz: para las sorpresas de Nora la cadena
        // inicial tiene que ser limpia (sin atravesar a la protegida).
        final bridgeRecord = await DeviceRecord.create(
          keys: nora.keys,
          listId: kV2List,
          deviceId: 'nora-phone',
          personId: 'aritz',
        );
        var registry = DeviceRegistry.empty(kV2List);
        for (final record in [aritz.record, leo.record, bridgeRecord]) {
          registry = await registry.withRecord(record);
        }
        for (final p in [aritz, leo]) {
          registry = await registry.withVouch(
            await Vouch.create(
              keys: nora.keys,
              voucher: bridgeRecord,
              record: p.record,
            ),
          );
          registry = await registry.withVouch(
            await Vouch.create(
              keys: p.keys,
              voucher: p.record,
              record: bridgeRecord,
            ),
          );
        }
        for (final p in [aritz, leo, nora]) {
          p.reg = registry;
        }
        final snap = (await client.getList(aritz.auth) as V2GetOk).snapshot;
        await client.putList(
          aritz.auth,
          version: snap.version,
          body: V2SnapshotUpload(
            common: snap.common,
            registry: registry.toJson(),
            keyPackages: const [],
          ),
        );
        await aritz.engine(client).sync();
        await leo.engine(client).sync();
        aritz.reg = (await revokeDevice(
          registry: registry,
          view: await aritz.view(),
          myKeys: aritz.keys,
          deviceId: 'nora-phone',
        )).registry;
        await aritz.engine(client).sync();
        await Future.wait([
          aritz.engine(client).sync(),
          leo.engine(client).sync(),
        ]);
        await aritz.engine(client).sync();
        expect((await aritz.view()).device('leo-phone'), isNull);
        expect((await leo.view()).device('aritz-phone'), isNull);
        expect(
          worker.slotVersions(kV2Sync).keys.toSet(),
          containsAll(['nora/aritz-phone', 'nora/leo-phone']),
        );
      },
    );

    test(
      '15: un escritor frozenWriters se conserva hasta su revocación explícita',
      () async {
        await aritz.engine(client).sync();
        await leo.engine(client).sync();
        await aritz.engine(client).sync();
        leo.reg = (await changePerson(
          registry: leo.reg,
          view: await leo.view(),
          myKeys: leo.keys,
          personId: 'aritz',
        )).registry;
        await leo.engine(client).sync();
        await aritz.engine(client).sync();
        expect(
          (await aritz.view()).pending.map((p) => p.deviceId),
          contains('leo-phone'),
        );
        expect(worker.slotVersions(kV2Sync), contains('nora/leo-phone'));
        final opened = await openScope(
          personId: 'nora',
          slots: aritz.slotSet,
          keyring: aritz.keyring,
          view: await aritz.view(),
        );
        expect(opened!.frozenWriters, contains('leo-phone'));
        await removeDevice(
          transport: client,
          local: aritz,
          deviceId: 'leo-phone',
        );
        // B2: revocado, deja de contar, pero nadie borra su slot remoto.
        await aritz.engine(client).sync();
        expect(worker.slotVersions(kV2Sync), contains('nora/leo-phone'));
        expect(aritz.slotSet.slotOf('nora', 'leo-phone'), isNull);
      },
    );

    test('cada móvil con derecho publica su slot; Nora los guarda sin '
        'abrirlos ni publicar', () async {
      final a = await aritz.engine(client).sync();
      expect(a.publishedPeople, ['nora']);
      final l = await leo.engine(client).sync();
      expect(l.publishedPeople, ['nora']);
      final n = await nora.engine(client).sync();
      expect(n.publishedPeople, isEmpty);
      expect(worker.slotVersions(kV2Sync).keys.toSet(), {
        'nora/aritz-phone',
        'nora/leo-phone',
      });
      expect(nora.slotSet.slotsFor('nora'), hasLength(2));
      expect(nora.keyring.people, isEmpty);
      expect(nora.scopes, isEmpty);
    });

    test('pendiente 15: sin cambios del común y dentro de la cadencia no se '
        'vuelve a sellar; con un cambio del común, sí', () async {
      await aritz.engine(client).sync();
      final puts = worker.calls['PUT list'];
      final again = await aritz.engine(client).sync();
      expect(again.publishedPeople, isEmpty);
      expect(worker.calls['PUT list'], puts);
      aritz.addGift('g1', 'leo', 'Patinete');
      final changed = await aritz.engine(client).sync();
      expect(changed.publishedPeople, ['nora']);
    });

    test(
      'hallazgo 10: un PUT lleva como mucho kV2MaxSlotsPerPut slots '
      'propios; los que no caben salen en la vuelta siguiente, primero',
      () async {
        final people = [
          for (var i = 0; i < 12; i++) 'p${i.toString().padLeft(2, '0')}',
        ];
        for (final p in people) {
          aritz.addPerson(p, p.toUpperCase());
        }
        aritz.keyring = SurpriseKeyring([
          noraKey(),
          for (final p in people)
            SurpriseKey(
              personId: p,
              epoch: 1,
              bytes: List<int>.filled(32, 7),
              audience: const ['aritz-phone', 'leo-phone', 'nora-phone'],
            ),
        ]);
        final sizes = <int>[];
        final realSend = worker.send;
        final counting = SyncV2Client(
          base: Uri.parse('https://sync.test'),
          sendRequest: (method, uri, {body, headers = const {}}) {
            if (method == 'PUT' && body is Map) {
              sizes.add(
                ((body['slots'] as List?) ?? const [])
                    .where((s) => (s as Map)['data'] != null)
                    .length,
              );
            }
            return realSend(method, uri, body: body, headers: headers);
          },
          openSocket: worker.socket,
        );
        final first = await aritz.engine(counting).sync();
        expect(first.publishedPeople, hasLength(kV2MaxSlotsPerPut));
        expect(first.morePending, isTrue);
        final second = await aritz.engine(counting).sync();
        // Los 3 que faltaban (13 personas con clave) van primero y solos.
        expect(second.publishedPeople, hasLength(13 - kV2MaxSlotsPerPut));
        expect(second.morePending, isFalse);
        expect(sizes.every((n) => n <= kV2MaxSlotsPerPut), isTrue);
        final written = worker
            .slotVersions(kV2Sync)
            .keys
            .where((k) => k.endsWith('/aritz-phone'))
            .length;
        expect(written, 13);
      },
    );

    test('solo se bajan los slots que cambian', () async {
      await aritz.engine(client).sync();
      await leo.engine(client).sync();
      worker.calls.remove('GET slot');
      await leo.engine(client).sync();
      expect(worker.calls['GET slot'], isNull);
    });

    test('ataque: una respuesta de slot sustituida (otro recurso) se '
        'rechaza', () async {
      await aritz.engine(client).sync();
      await leo.engine(client).sync();
      final aritzSlot = aritz.slotSet.slotOf('nora', 'aritz-phone')!;
      worker.tamper = (method, uri, r) =>
          uri.path.endsWith('/slots/nora/leo-phone')
          ? _json(r, {...r.json(), 'data': encodeBase64Url(aritzSlot.bytes)})
          : r;
      await expectLater(
        nora.engine(client).sync(),
        throwsA(isA<SyncTransportException>()),
      );
      expect(nora.slotSet.slotsFor('nora'), isEmpty);
    });

    test('pendiente 13: un slot más viejo de lo que el anfitrión ya conocía '
        'no entra', () async {
      await aritz.engine(client).sync();
      final old = aritz.slotSet.slotOf('nora', 'aritz-phone')!;
      aritz.addGift('g1', 'leo', 'Peonza');
      await aritz.engine(client).sync();
      final fresh = aritz.slotSet.slotOf('nora', 'aritz-phone')!;
      expect(fresh.header.revision, greaterThan(old.header.revision));
      // El servidor le sirve a Leo el slot viejo de Aritz.
      worker.tamper = (method, uri, r) =>
          uri.path.endsWith('/slots/nora/aritz-phone')
          ? _json(r, {...r.json(), 'data': encodeBase64Url(old.bytes)})
          : r;
      leo.state = leo.state.copyWith(
        minSlotRevisions: {'nora/aritz-phone': fresh.header.revision},
      );
      final out = await leo.engine(client).sync();
      expect(out.rejectedSlots, 1);
      expect(leo.slotSet.slotOf('nora', 'aritz-phone'), isNull);
    });

    test('7 resto: el registro de la instantánea se fusiona antes de abrir '
        'paquetes, y cada vuelta rota las claves', () async {
      await aritz.engine(client).sync();
      await leo.engine(client).sync();
      // Aritz revoca el móvil de Nora: el registro abre la época 2.
      final change = await revokeDevice(
        registry: aritz.reg,
        view: await aritz.view(),
        myKeys: aritz.keys,
        deviceId: 'nora-phone',
      );
      aritz.reg = change.registry;
      await client.revoke(aritz.auth, 'nora-phone');
      final out = await aritz.engine(client).sync();
      expect(out.view.epoch, 2);
      expect(aritz.keyring.latestFor('nora')!.epoch, 2);
      expect(out.publishedPeople, ['nora']);
      // Leo todavía no tiene la revocación en su registro: el paquete de la
      // época 2 solo se abre si fusiona antes el de la instantánea.
      expect((await leo.view()).epoch, 1);
      await leo.engine(client).sync();
      expect((await leo.view()).epoch, 2);
      expect(leo.keyring.latestFor('nora')!.epoch, 2);
      expect(
        leo.keyring.latestFor('nora')!.kid,
        aritz.keyring.latestFor('nora')!.kid,
      );
    });

    /// Un cliente que apunta cada `data: null` que se sube.
    SyncV2Client watchingRemovals(List<String> removals) => SyncV2Client(
      base: Uri.parse('https://sync.test'),
      sendRequest: (method, uri, {body, headers = const {}}) {
        if (method == 'PUT' && body is Map) {
          for (final raw in (body['slots'] as List?) ?? const []) {
            final s = raw as Map;
            if (s['data'] == null) {
              removals.add('${s['personId']}/${s['deviceId']}');
            }
          }
        }
        return worker.send(method, uri, body: body, headers: headers);
      },
      openSocket: worker.socket,
    );

    test('B2: el motor ya no manda data: null para el slot de un escritor '
        'revocado; se queda en el servidor y no se vuelve a bajar', () async {
      await aritz.engine(client).sync();
      await leo.engine(client).sync();
      expect(worker.slotVersions(kV2Sync), contains('nora/leo-phone'));
      final before = worker.slotVersions(kV2Sync)['nora/leo-phone'];
      aritz.reg = (await revokeDevice(
        registry: aritz.reg,
        view: await aritz.view(),
        myKeys: aritz.keys,
        deviceId: 'leo-phone',
      )).registry;
      await client.revoke(aritz.auth, 'leo-phone');
      final removals = <String>[];
      final watching = watchingRemovals(removals);
      final out = await aritz.engine(watching).sync();
      // Aritz sí vuelve a sellar el suyo (época nueva).
      expect(out.publishedPeople, ['nora']);
      expect(removals, isEmpty);
      expect(worker.slotVersions(kV2Sync)['nora/leo-phone'], before);
      // En local no cuenta: no se guarda ni se abre.
      expect(aritz.slotSet.slotOf('nora', 'leo-phone'), isNull);
      worker.calls.remove('GET slot');
      await aritz.engine(watching).sync();
      expect(worker.calls['GET slot'], isNull);
      expect(removals, isEmpty);
    });

    test('B2: no reemplaza un slot propio que no puede abrir', () async {
      await aritz.engine(client).sync();
      final mine = worker.slotVersions(kV2Sync)['nora/aritz-phone'];
      expect(mine, isNotNull);
      final sealed = aritz.slotSet.slotOf('nora', 'aritz-phone')!;
      // Otra clave de la misma época: puede sellar, pero no abrir el anterior.
      aritz.keyring = SurpriseKeyring([
        SurpriseKey(
          personId: 'nora',
          epoch: 1,
          bytes: List<int>.filled(32, 9),
          audience: const ['aritz-phone', 'leo-phone'],
        ),
      ]);
      final view = await aritz.view();
      expect(
        aritz.keyring.sealingKeyFor(
          'nora',
          view.epoch,
          allowed: view.entitledDevices('nora'),
        ),
        isNotNull,
        reason: 'puede sellar: lo que lo frena es no poder abrir el anterior',
      );
      aritz.addGift('g1', 'leo', 'Patinete');
      final out = await aritz.engine(client).sync();
      expect(out.publishedPeople, isEmpty);
      expect(worker.slotVersions(kV2Sync)['nora/aritz-phone'], mine);
      expect(aritz.slotSet.slotOf('nora', 'aritz-phone')!.bytes, sealed.bytes);
    });

    for (final oldServer in [false, true]) {
      test(
        'B2: los slots abandonados ocupan sitio y piden renovar '
        '(${oldServer ? "sin capacity, por el manifiesto" : "capacity"})',
        () async {
          if (oldServer) {
            worker.tamper = (method, uri, r) =>
                method == 'GET' && uri.path == '/v2/lists/$kV2Sync'
                ? _json(r, {...r.json()}..remove('capacity'))
                : r;
          }
          await aritz.engine(client).sync();
          // Leo y Nora no han anunciado `slotCapacity`: vale el aviso de 1.0.5.
          final warn = worker.slotWarnOf(kV2Sync);
          // Slots de escritores que ya no están: no cuentan, pero ocupan sitio.
          var planted = worker.plantSlotsForTesting(kV2Sync, warn - 2);
          final below = await aritz.engine(client).sync();
          expect(below.renewSuggested, isFalse);
          planted = {...planted, ...worker.plantSlotsForTesting(kV2Sync, 1)};
          final at = await aritz.engine(client).sync();
          expect(at.renewSuggested, isTrue);
          expect(aritz.state.health!.renewSuggested, isTrue);
          // Nada se borra para hacer sitio.
          expect(worker.slotVersions(kV2Sync).keys, containsAll(planted.keys));
        },
      );
    }
  });

  group('B2', () {
    setUp(() {
      aritz.keyring = SurpriseKeyring([noraKey()]);
      leo.keyring = SurpriseKeyring([noraKey()]);
    });

    /// Un cliente que apunta cada data: null que se sube.
    SyncV2Client watchingRemovals(List<String> removals) => SyncV2Client(
      base: Uri.parse('https://sync.test'),
      sendRequest: (method, uri, {body, headers = const {}}) {
        if (method == 'PUT' && body is Map) {
          for (final raw in (body['slots'] as List?) ?? const []) {
            final s = raw as Map;
            if (s['data'] == null) {
              removals.add('${s['personId']}/${s['deviceId']}');
            }
          }
        }
        return worker.send(method, uri, body: body, headers: headers);
      },
      openSocket: worker.socket,
    );

    test('M1: un slot ajeno ilegible no impide sincronizar el común, no se '
        'vuelve a bajar y sí cuando cambia su versión', () async {
      await aritz.engine(client).sync();
      worker.plantRawSlotForTesting(kV2Sync, 'nora', 'ghost', 'AAAA');
      aritz.addGift('g1', 'leo', 'Patinete');
      final out = await aritz.engine(client).sync();
      expect(out.rejectedSlots, 1);
      expect(out.uploaded, isTrue);
      await leo.engine(client).sync();
      expect(leo.giftTitles, contains('Patinete'));
      expect(
        aritz.state.ignoredSlots['nora/ghost'],
        isA<IgnoredSlot>().having(
          (e) => e.reason,
          'reason',
          IgnoredSlotReason.unreadable,
        ),
      );
      // Una vuelta para bajar el slot nuevo de Leo; después, nada.
      await aritz.engine(client).sync();
      worker.calls.remove('GET slot');
      await aritz.engine(client).sync();
      expect(worker.calls['GET slot'], isNull);
      // Otra versión del mismo recurso: se vuelve a bajar.
      leo.addGift('g2', 'leo', 'Peonza');
      await leo.engine(client).sync();
      worker.plantRawSlotForTesting(kV2Sync, 'nora', 'ghost', 'BBBB');
      final newer = worker.slotVersions(kV2Sync)['nora/ghost']!;
      final again = await aritz.engine(client).sync();
      expect(aritz.state.ignoredSlots['nora/ghost']!.version, newer);
      expect(again.rejectedSlots, 1);
      expect(aritz.giftTitles, contains('Peonza'));
    });

    test(
      'B2: una entrada de «revocado» cuyo escritor no lo está de verdad '
      'se olvida y el slot se vuelve a bajar en la vuelta siguiente',
      () async {
        await aritz.engine(client).sync();
        await leo.engine(client).sync();
        final v = worker.slotVersions(kV2Sync)['nora/leo-phone']!;
        // Como un id que fue ambiguo y ya no lo es: Leo está activo.
        aritz.state = aritz.state.copyWith(
          ignoredSlots: {
            'nora/leo-phone': IgnoredSlot(v, IgnoredSlotReason.revoked),
          },
          slotVersions: {...aritz.state.slotVersions}..remove('nora/leo-phone'),
        );
        final (onlyMine, _) = await SlotSet.empty.merge([
          aritz.slotSet.slotOf('nora', 'aritz-phone')!,
        ], view: await aritz.view());
        aritz.slotSet = onlyMine;
        await aritz.engine(client).sync();
        expect(aritz.state.ignoredSlots, isNot(contains('nora/leo-phone')));
        await aritz.engine(client).sync();
        expect(aritz.slotSet.slotOf('nora', 'leo-phone'), isNotNull);
      },
    );

    test('1.0.6: mientras un móvil no anuncia la capacidad nueva (un 1.0.5), '
        'la lista no pasa de 64; cuando la anuncia, sí, y un móvil con la '
        'caché vacía baja un manifiesto de 65', () async {
      await aritz.engine(client).sync();
      expect(worker.slotCapacityOf(kV2Sync, 'aritz-phone'), kV2SlotCapacity);
      // Nora no ha sincronizado: como un 1.0.5, no ha anunciado nada.
      expect(worker.slotCapacityOf(kV2Sync, 'nora-phone'), 1);
      worker.plantSlotsForTesting(
        kV2Sync,
        kV2LegacyMaxSlots - worker.slotVersions(kV2Sync).length,
      );
      expect(worker.slotVersions(kV2Sync), hasLength(kV2LegacyMaxSlots));
      // El alta de Leo sería el slot 65: no se sube.
      leo.addGift('g1', 'leo', 'Patinete');
      final held = await leo.engine(client).sync();
      expect(worker.slotCapacityOf(kV2Sync, 'leo-phone'), kV2SlotCapacity);
      expect(held.slotsFull, isTrue);
      expect(held.uploaded, isTrue);
      expect(worker.slotVersions(kV2Sync), hasLength(kV2LegacyMaxSlots));
      // Nora actualiza: al sincronizar lo anuncia y ya caben más.
      await nora.engine(client).sync();
      expect(worker.slotCapacityOf(kV2Sync, 'nora-phone'), kV2SlotCapacity);
      final grown = await leo.engine(client).sync();
      expect(grown.slotsFull, isFalse);
      expect(grown.publishedPeople, ['nora']);
      expect(worker.slotVersions(kV2Sync), hasLength(kV2LegacyMaxSlots + 1));
      // Un móvil con la caché vacía baja los 65.
      aritz.slotSet = SlotSet.empty;
      await aritz.engine(client).sync();
      expect(aritz.slotSet.slotOf('nora', 'leo-phone'), isNotNull);
      expect(aritz.giftTitles, contains('Patinete'));
    });

    test('1.0.6: un slot de otro recurso no se queda guardado para la vuelta '
        'siguiente; cuando el servidor lo arregla, entra', () async {
      clearPendingSlotDownloadsForTesting();
      addTearDown(clearPendingSlotDownloadsForTesting);
      await aritz.engine(client).sync();
      leo.addGift('g1', 'leo', 'Patinete');
      await leo.engine(client).sync();
      final version = worker.slotVersions(kV2Sync)['nora/leo-phone']!;
      final snap = (await client.getList(aritz.auth) as V2GetOk).snapshot;
      Future<Uint8List> dataOf(String writer) async => ((await client.getSlot(
        aritz.auth,
        version: snap.version,
        personId: 'nora',
        deviceId: writer,
      )) as V2SlotOk).data;
      final leoData = await dataOf('leo-phone');
      final aritzData = await dataOf('aritz-phone');
      // El servidor sirve en el recurso de Leo el slot de Aritz.
      worker.plantRawSlotForTesting(
        kV2Sync,
        'nora',
        'leo-phone',
        encodeBase64Url(aritzData),
      );
      expect(worker.slotVersions(kV2Sync)['nora/leo-phone'], version);
      aritz.slotSet = SlotSet.empty;
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
      // Mismo recurso y misma versión, ya con los bytes buenos.
      worker.plantRawSlotForTesting(
        kV2Sync,
        'nora',
        'leo-phone',
        encodeBase64Url(leoData),
      );
      await aritz.engine(client).sync();
      expect(
        aritz.slotSet.slotOf('nora', 'leo-phone')!.header.writer,
        'leo-phone',
      );
    });

    test('1.0.6: un manifiesto de más de kMaxSlotsPerList o un slot más '
        'largo que el máximo no se descargan', () async {
      await aritz.engine(client).sync();
      var slotGets = 0;
      worker.tamper = (method, uri, r) {
        if (method == 'GET' && uri.path.contains('/slots/')) slotGets++;
        if (method == 'GET' && uri.path == '/v2/lists/$kV2Sync') {
          final body = r.json();
          return _json(r, {
            ...body,
            'slots': [
              for (var i = 0; i <= kMaxSlotsPerList; i++)
                {'personId': 'p$i', 'deviceId': 'gone$i', 'version': 1},
            ],
          });
        }
        return r;
      };
      await expectLater(
        client.getList(aritz.auth),
        throwsA(
          isA<SyncTransportException>().having(
            (e) => e.message,
            'message',
            'demasiados slots',
          ),
        ),
      );
      expect(slotGets, 0);
      worker.tamper = (method, uri, r) {
        if (method == 'GET' && uri.path.contains('/slots/')) {
          return _json(r, {...r.json(), 'data': 'A' * (kV2MaxSlotChars + 1)});
        }
        return r;
      };
      final snap = (await client.getList(aritz.auth) as V2GetOk).snapshot;
      await expectLater(
        client.getSlot(
          aritz.auth,
          version: snap.version,
          personId: 'nora',
          deviceId: 'aritz-phone',
        ),
        throwsA(
          isA<SyncTransportException>().having(
            (e) => e.message,
            'message',
            'slot demasiado grande',
          ),
        ),
      );
    });

    test('1.0.6: la descarga en frío de 128 slots sigue tras un 429 a mitad '
        'sin volver a pedir lo ya bajado', () async {
      clearPendingSlotDownloadsForTesting();
      addTearDown(clearPendingSlotDownloadsForTesting);
      await aritz.engine(client).sync();
      await leo.engine(client).sync();
      await nora.engine(client).sync();
      worker.plantSlotsForTesting(
        kV2Sync,
        kMaxSlotsPerList - worker.slotVersions(kV2Sync).length,
      );
      expect(worker.slotVersions(kV2Sync), hasLength(kMaxSlotsPerList));
      var slotGets = 0;
      var limited = false;
      worker.tamper = (method, uri, r) {
        if (method != 'GET' || !uri.path.contains('/slots/')) return r;
        slotGets++;
        // La cuota de la credencial (120 por minuto) se acaba a mitad.
        if (!limited && slotGets == 61) {
          limited = true;
          return SyncResponse(429, {'retry-after': '60'}, Uint8List(0));
        }
        return r;
      };
      leo.slotSet = SlotSet.empty;
      await expectLater(
        leo.engine(client).sync(),
        throwsA(
          isA<SyncTransportException>().having(
            (e) => e.failure,
            'failure',
            SyncFailure.rateLimited,
          ),
        ),
      );
      expect(slotGets, 61);
      // La vuelta siguiente (otro motor, como al reabrir) termina y solo pide
      // lo que faltaba.
      await leo.engine(client).sync();
      expect(slotGets, kMaxSlotsPerList + 1);
      expect(leo.slotSet.slotOf('nora', 'aritz-phone'), isNotNull);
    });

    test('M2: con la lista llena, un alta propia no se sube, el común sí, y '
        'se avisa; sustituir el propio sigue funcionando', () async {
      await aritz.engine(client).sync();
      worker.plantSlotsForTesting(
        kV2Sync,
        kMaxSlotsPerList - worker.slotVersions(kV2Sync).length,
      );
      expect(worker.slotVersions(kV2Sync), hasLength(kMaxSlotsPerList));
      // Leo todavía no tiene slot: el suyo sería un alta.
      leo.addGift('g1', 'leo', 'Patinete');
      final out = await leo.engine(client).sync();
      expect(out.publishedPeople, isEmpty);
      expect(out.slotsFull, isTrue);
      expect(out.renewSuggested, isTrue);
      expect(out.uploaded, isTrue);
      expect(leo.state.health!.renewSuggested, isTrue);
      expect(leo.slotSet.slotOf('nora', 'leo-phone'), isNull);
      await aritz.engine(client).sync();
      expect(aritz.giftTitles, contains('Patinete'));
      // Aritz ya tenía el suyo: sustituirlo cabe.
      aritz.addGift('g2', 'leo', 'Peonza');
      final mine = await aritz.engine(client).sync();
      expect(mine.publishedPeople, ['nora']);
      expect(worker.slotVersions(kV2Sync), hasLength(kMaxSlotsPerList));
    });

    test('M2: con su tope de escritor lleno, las altas no se sellan, el común '
        'se sube igual y el aviso va aparte de renovar', () async {
      await aritz.engine(client).sync();
      // Leo ya tiene kV2MaxSlotsPerWriter slots (de personas de antes).
      worker.plantSlotsForTesting(
        kV2Sync,
        kV2MaxSlotsPerWriter,
        writer: 'leo-phone',
      );
      leo.addGift('g1', 'leo', 'Patinete');
      final out = await leo.engine(client).sync();
      expect(out.publishedPeople, isEmpty);
      expect(out.writerSlotsFull, isTrue);
      expect(out.slotsFull, isFalse);
      expect(out.renewSuggested, isFalse);
      expect(out.uploaded, isTrue);
      expect(leo.state.health!.writerSlotsFull, isTrue);
      expect(leo.state.health!.renewSuggested, isFalse);
      expect(
        V2Health.fromJson(leo.state.health!.toJson()).writerSlotsFull,
        isTrue,
      );
      expect(leo.slotSet.slotOf('nora', 'leo-phone'), isNull);
      expect(worker.slotVersions(kV2Sync), isNot(contains('nora/leo-phone')));
      await aritz.engine(client).sync();
      expect(aritz.giftTitles, contains('Patinete'));
    });

    test('unknownWriter: el slot de un escritor que el registro no conoce no '
        'se vuelve a bajar mientras siga sin conocerse', () async {
      await aritz.engine(client).sync();
      worker.plantSlotsForTesting(kV2Sync, 1, writer: 'ghost-phone');
      final out = await aritz.engine(client).sync();
      expect(out.rejectedSlots, 1);
      expect(
        aritz.state.ignoredSlots['gone0/ghost-phone']?.reason,
        IgnoredSlotReason.unknownWriter,
      );
      // Sobrevive a guardar y leer el estado.
      aritz.state = V2SyncState.fromJson(
        jsonDecode(jsonEncode(aritz.state.toJson())),
      );
      worker.calls.remove('GET slot');
      final again = await aritz.engine(client).sync();
      expect(worker.calls['GET slot'], isNull);
      expect(again.rejectedSlots, 0);
      expect(aritz.state.ignoredSlots, contains('gone0/ghost-phone'));
    });

    test('rama destructiva: con la ficha pendiente no retira su slot de su '
        'nueva persona; aprobada, sí (y nunca uno ajeno)', () async {
      await aritz.engine(client).sync();
      await leo.engine(client).sync();
      expect(worker.slotVersions(kV2Sync), contains('nora/leo-phone'));
      // Leo pasa a ser el móvil de Nora: hasta que lo aprueben, pendiente.
      final changed = await changePerson(
        registry: leo.reg,
        view: await leo.view(),
        myKeys: leo.keys,
        personId: 'nora',
      );
      leo.reg = changed.registry;
      final removals = <String>[];
      await leo.engine(watchingRemovals(removals)).sync();
      expect((await leo.view()).selfApproved, isFalse);
      expect(removals, isEmpty);
      expect(worker.slotVersions(kV2Sync), contains('nora/leo-phone'));
      // Aritz aprueba la ficha nueva.
      await aritz.engine(client).sync();
      final record = aritz.reg.records
          .where((r) => r.deviceId == 'leo-phone')
          .reduce((a, b) => a.seq > b.seq ? a : b);
      expect(record.personId, 'nora');
      aritz.reg = (await approveDevice(
        registry: aritz.reg,
        view: await aritz.view(),
        myKeys: aritz.keys,
        record: record,
      )).registry;
      final aritzRemovals = <String>[];
      await aritz.engine(watchingRemovals(aritzRemovals)).sync();
      expect(aritzRemovals, isEmpty);
      await leo.engine(watchingRemovals(removals)).sync();
      final view = await leo.view();
      expect(view.selfApproved, isTrue);
      expect(view.myPerson, 'nora');
      expect(removals, ['nora/leo-phone']);
      expect(worker.slotVersions(kV2Sync), contains('nora/aritz-phone'));
      expect(worker.slotVersions(kV2Sync), isNot(contains('nora/leo-phone')));
    });

    test(
      'M2: retira su propio slot de una persona borrada, nunca uno ajeno',
      () async {
        await aritz.engine(client).sync();
        await leo.engine(client).sync();
        expect(
          worker.slotVersions(kV2Sync).keys,
          containsAll(['nora/aritz-phone', 'nora/leo-phone']),
        );
        aritz.doc = aritz.doc.delete(
          aritz.clock,
          Collections.recipients,
          'nora',
        );
        final removals = <String>[];
        final out = await aritz.engine(watchingRemovals(removals)).sync();
        expect(out.publishedPeople, isEmpty);
        expect(removals, ['nora/aritz-phone']);
        expect(worker.slotVersions(kV2Sync).keys, ['nora/leo-phone']);
        // Una vuelta más no vuelve a sellar ni a retirar nada.
        removals.clear();
        await aritz.engine(watchingRemovals(removals)).sync();
        expect(removals, isEmpty);
        expect(worker.slotVersions(kV2Sync).keys, ['nora/leo-phone']);
      },
    );
  });

  group('móviles de la familia', () {
    test('isDevicePerson: las personas con ficha activa, también la de este '
        'móvil; deja de serlo al quitar su móvil', () async {
      await aritz.engine(client).sync();
      final view = await localView(aritz);
      for (final person in ['aritz', 'leo', 'nora']) {
        expect(isDevicePerson(view, person), isTrue, reason: person);
      }
      expect(isDevicePerson(view, 'otra'), isFalse);
      await removeDevice(
        transport: client,
        local: aritz,
        deviceId: 'nora-phone',
      );
      expect(isDevicePerson(await localView(aritz), 'nora'), isFalse);
    });

    test('quitar un móvil lo revoca en el servidor y en el registro, y los '
        'demás lo ven al sincronizar', () async {
      final change = await removeDevice(
        transport: client,
        local: aritz,
        deviceId: 'nora-phone',
      );
      expect(change.rotates, isTrue);
      expect(change.orphans, isEmpty, reason: 'Leo está avalado por Aritz');
      expect(worker.devicesOf(kV2Sync)['nora-phone'], isTrue);
      expect((await localView(aritz)).revoked, contains('nora-phone'));
      await leo.engine(client).sync();
      expect((await leo.view()).revoked, contains('nora-phone'));
      await expectLater(
        nora.engine(client).sync(),
        throwsA(isA<SyncTransportException>()),
      );
      await expectLater(
        removeDevice(transport: client, local: aritz, deviceId: 'aritz-phone'),
        throwsA(isA<RegistryException>()),
      );
    });

    test('salir conserva el regalo secreto que solo estaba en el slot del '
        'escritor; otro móvil lo recibe después de su salida', () async {
      aritz.keyring = SurpriseKeyring([noraKey()]);
      leo.keyring = SurpriseKeyring([noraKey()]);
      // Un regalo público de Nora no saldría de un móvil con su clave (lote
      // 6); el de esta prueba es para Aritz.
      leo.addGift('g1', 'aritz', 'Libro');
      await aritz.engine(client).sync();
      leo.scopes['nora'] = FamilyDoc.empty(kV2List).set(
        HlcClock(node: 'secret-leo'),
        Collections.gifts,
        'secret',
        {'recipientId': 'nora', 'title': 'Bufanda', 'status': 'idea'},
      );
      await leo.engine(client).sync();
      final before = await openScope(
        personId: 'nora',
        slots: aritz.slotSet,
        keyring: aritz.keyring,
        view: await aritz.view(),
      );
      expect(before!.doc.record(Collections.gifts, 'secret'), isNull);
      expect(leo.doc.record(Collections.gifts, 'secret'), isNull);
      expect(worker.slotVersions(kV2Sync).keys, contains('nora/leo-phone'));
      final slotsBefore = worker.slotVersions(kV2Sync);
      await leaveFamily(transport: client, local: leo);
      expect(worker.devicesOf(kV2Sync)['leo-phone'], isTrue);
      expect(worker.hasList(kV2Sync), isTrue);
      expect(worker.slotVersions(kV2Sync), slotsBefore);
      expect(leo.giftTitles, {'Libro'});
      expect(
        leo.scopes['nora']!.record(Collections.gifts, 'secret')!['title'],
        'Bufanda',
      );
      final out = await aritz.engine(client).sync();
      expect(out.departedDevices, ['leo-phone']);
      expect(aritz.giftTitles, {'Libro'});
      final after = await openScope(
        personId: 'nora',
        slots: aritz.slotSet,
        keyring: aritz.keyring,
        view: await aritz.view(),
      );
      expect(
        after!.doc.record(Collections.gifts, 'secret')!['title'],
        'Bufanda',
      );
      await expectLater(
        leo.engine(client).sync(),
        throwsA(isA<SyncTransportException>()),
      );
    });
  });
}
