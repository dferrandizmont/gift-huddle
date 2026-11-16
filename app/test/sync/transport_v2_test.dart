import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/renewal_protocol.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';
import 'package:regalos/features/sync/data/sync_transport_common.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';

import '../helpers/fake_worker_v2.dart';

const _sync = 'AAAAAAAAAAAAAAAAAAAAAA';

Uint8List _cred(int seed) => Uint8List.fromList(List.filled(32, seed));

V2Auth _auth(String device, int seed) =>
    V2Auth(syncId: _sync, deviceId: device, credential: _cred(seed));

/// Unos bytes con la cabecera de un slot (`GHS`, formato 2) que nombra a
/// [person] y [writer], y el tamaño exacto: el servidor solo lee eso.
/// [fill] cambia el resto.
Uint8List _slot(String person, String writer, {int fill = 0}) {
  final out = BytesBuilder()
    ..add([0x47, 0x48, 0x53, 0x02])
    ..add(List.filled(29, 0));
  for (final id in ['list', person, writer]) {
    out
      ..addByte(id.length)
      ..add(ascii.encode(id));
  }
  out.add(List.filled(kSlotBodyBytesForTesting, fill));
  return out.takeBytes();
}

V2SnapshotUpload _body({
  List<V2SlotChange> slots = const [],
  String common = 'AAAA',
}) => V2SnapshotUpload(
  common: decodeBase64Url(common),
  registry: const {
    'v': 2,
    'records': <Object?>[],
    'vouches': <Object?>[],
    'revocations': <Object?>[],
  },
  keyPackages: const [],
  slots: slots,
);

SyncResponse _withBody(
  SyncResponse r,
  Map<String, Object?> Function(Map<String, Object?>) edit,
) => SyncResponse(
  r.status,
  r.headers,
  Uint8List.fromList(utf8.encode(jsonEncode(edit(r.json())))),
);

Map<String, Object?> _renewalCommand(
  V2Auth auth,
  int version,
  String action, [
  Map<String, Object?> extra = const {},
]) => {
  'v': 1,
  'action': action,
  'operationId': encodeBase64Url(Uint8List.fromList(List.filled(16, 3))),
  'sourceSyncId': auth.syncId,
  'targetSyncId': encodeBase64Url(Uint8List.fromList(List.filled(16, 4))),
  'revision': 1,
  'sourceVersion': version,
  'signerDeviceId': auth.deviceId,
  'signature': encodeBase64Url(Uint8List(64)),
  'prev': null,
  ...extra,
};

Map<String, Object?> _reservation(V2Auth auth, {List<String>? participants}) =>
    _renewalCommand(auth, 1, 'reserve', {
      'participants': participants ?? [auth.deviceId],
      'newDeviceId': '${auth.deviceId}-new',
      'newSigningKey': encodeBase64Url(_cred(7)),
      'targetCommitment': encodeBase64Url(_cred(8)),
      'inventoryCommitment': encodeBase64Url(_cred(9)),
    });

void main() {
  late FakeWorkerV2 worker;
  late SyncV2Client client;
  final aritz = _auth('aritz-phone', 1);
  final nora = _auth('nora-phone', 2);

  setUp(() {
    worker = FakeWorkerV2();
    client = worker.client();
  });

  group('renewal control', () {
    Future<V2WriteResult> step(
      V2Auth auth,
      String action,
      Map<String, Object?> extra,
    ) async {
      final current = await client.getRenewal(auth);
      return client.putRenewal(
        auth,
        version: current.version,
        command: _renewalCommand(auth, current.version, action, {
          'revision': current.renewal?['revision'] ?? 1,
          'prev': current.renewal?['head'],
          ...extra,
        }),
      );
    }

    Future<void> readyAndAck(V2Auth auth) async {
      await step(auth, 'ready', {'destinationVersion': 1});
      await step(auth, 'ack', {
        'newDeviceId': '${auth.deviceId}-new',
        'newSigningKey': encodeBase64Url(_cred(7)),
        'receipt': encodeBase64Url(_cred(10)),
        'destinationVersion': 2,
      });
    }

    test(
      'full generation: durable reservation, lost response and exact retry',
      () async {
        await client.createList(aritz, _body());
        worker.fillGenerationForTesting(_sync, credentials: 64, records: 512);
        worker.plantSlotsForTesting(_sync, 64);
        final full = await client.getList(aritz) as V2GetOk;
        expect(full.snapshot.capacity!.slots!.used, 64);
        expect((await client.getRenewal(aritz)).renewal, isNull);
        final c = _reservation(aritz);
        var dropped = false;
        worker.tamper = (method, uri, response) {
          if (!dropped && method == 'PUT' && uri.path.endsWith('/renewal')) {
            dropped = true;
            throw const SyncTransportException(
              SyncFailure.network,
              'lost response',
            );
          }
          return response;
        };
        await expectLater(
          client.putRenewal(aritz, version: 1, command: c),
          throwsA(isA<SyncTransportException>()),
        );
        expect(worker.versionOf(_sync), 2);
        expect(
          await client.putRenewal(aritz, version: 1, command: c),
          isA<V2WriteOk>().having((r) => r.version, 'version', 2),
        );
        expect(
          (await client.getRenewal(aritz)).renewal!['reservation'],
          renewalCommandHash(c),
        );
      },
    );

    test('CAS conflict returns latest ETag; 429 preserves retry time and signed command', () async {
      await client.createList(aritz, _body());
      final c = _reservation(aritz);
      final recording = SyncV2Client(
        base: Uri.parse('https://sync.test'),
        sendRequest: (method, uri, {body, headers = const {}}) {
          expect(method, 'PUT');
          expect(uri.path, '/v2/lists/$_sync/renewal');
          expect(headers['Authorization'], aritz.bearer);
          expect(headers['If-Match'], '"1"');
          expect(body, c);
          return worker.send(method, uri, body: body, headers: headers);
        },
      );
      worker.rateLimitNext = 7200;
      await expectLater(
        recording.putRenewal(aritz, version: 1, command: c),
        throwsA(
          isA<SyncTransportException>()
              .having((e) => e.failure, 'failure', SyncFailure.rateLimited)
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(hours: 2),
              ),
        ),
      );
      expect(worker.versionOf(_sync), 1);
      await recording.putRenewal(aritz, version: 1, command: c);
      final second = {
        ...c,
        'operationId': encodeBase64Url(Uint8List.fromList(List.filled(16, 5))),
      };
      expect(
        await client.putRenewal(aritz, version: 1, command: second),
        isA<V2WriteStale>().having((r) => r.current, 'current', 2),
      );
    });

    test('rejects malformed or wrong-generation control, signatures, revision, map bindings and ETag', () async {
      await client.createList(aritz, _body());
      await client.putRenewal(aritz, version: 1, command: _reservation(aritz));
      await readyAndAck(aritz);
      final mutations = <void Function(Map<String, Object?>)>[
        (s) => s['sourceSyncId'] = 'BBBBBBBBBBBBBBBBBBBBBA',
        (s) => s['revision'] = 0,
        (s) => s['plan'] = 'AAAA',
        (s) => (s['acknowledgements'] as Map)['nora-phone'] =
            (s['acknowledgements'] as Map).values.first,
        (s) => s['branches'] = List.filled(9, 'BBBBBBBBBBBBBBBBBBBBBA'),
        (s) => s.remove('reservation'),
        (s) => s['barrierVersion'] = 1000,
      ];
      for (final change in mutations) {
        worker.tamper = (_, uri, response) => uri.path.endsWith('/renewal')
            ? _withBody(response, (j) {
                change(j['renewal'] as Map<String, Object?>);
                return j;
              })
            : response;
        await expectLater(
          client.getRenewal(aritz),
          throwsA(
            isA<SyncTransportException>().having(
              (e) => e.failure,
              'failure',
              SyncFailure.protocol,
            ),
          ),
        );
      }
      worker.tamper = (_, _, response) =>
          _withBody(response, (j) => {...j, 'version': 123});
      await expectLater(
        client.getRenewal(aritz),
        throwsA(isA<SyncTransportException>()),
      );
    });

    test(
      'write responses cannot substitute a different valid operation',
      () async {
        await client.createList(aritz, _body());
        worker.tamper = (method, uri, response) {
          if (method != 'PUT' || !uri.path.endsWith('/renewal')) {
            return response;
          }
          return _withBody(response, (j) {
            final state = j['renewal'] as Map;
            final other = encodeBase64Url(
              Uint8List.fromList(List.filled(16, 17)),
            );
            state['operationId'] = other;
            return j;
          });
        };
        await expectLater(
          client.putRenewal(aritz, version: 1, command: _reservation(aritz)),
          throwsA(
            isA<SyncTransportException>().having(
              (e) => e.failure,
              'failure',
              SyncFailure.protocol,
            ),
          ),
        );
      },
    );

    test('a forged 201 cannot bypass control response validation', () async {
      await client.createList(aritz, _body());
      worker.tamper = (_, _, response) => SyncResponse(
        201,
        response.headers,
        Uint8List.fromList(utf8.encode(jsonEncode({'version': 2}))),
      );
      await expectLater(
        client.putRenewal(aritz, version: 1, command: _reservation(aritz)),
        throwsA(
          isA<SyncTransportException>().having(
            (e) => e.failure,
            'failure',
            SyncFailure.protocol,
          ),
        ),
      );
    });

    test('invalid outgoing context never sends; missing and retired sources have distinct recovery', () async {
      final c = _reservation(aritz);
      for (final change in <Map<String, Object?>>[
        {'signerDeviceId': nora.deviceId},
        {'sourceVersion': 3},
        {'signature': 'AAAA'},
        {'participants': List.filled(65, aritz.deviceId)},
        {'extra': true},
      ]) {
        await expectLater(
          client.putRenewal(aritz, version: 1, command: {...c, ...change}),
          throwsA(isA<SyncTransportException>()),
        );
      }
      expect(worker.calls['PUT renewal'], isNull);
      await expectLater(
        client.getRenewal(aritz),
        throwsA(
          isA<V2RenewalGoneException>().having(
            (e) => e.retired,
            'retired',
            false,
          ),
        ),
      );
      await client.createList(aritz, _body());
      await client.deleteList(aritz, version: 1);
      await expectLater(
        client.getRenewal(aritz),
        throwsA(
          isA<V2RenewalGoneException>().having(
            (e) => e.retired,
            'retired',
            true,
          ),
        ),
      );
      expect(
        await client.putRenewal(aritz, version: 1, command: c),
        isA<V2WriteNotFound>(),
      );
    });

    test('web ack, participant barrier, pending DELETE, final snapshot and retirement', () async {
      final web = _auth('nora-web', 3);
      await client.createList(aritz, _body());
      worker.addCredentialForTesting(
        _sync,
        web.deviceId,
        web.credential,
        role: 'web',
      );
      await expectLater(
        client.putRenewal(
          web,
          version: 1,
          command: _reservation(
            web,
            participants: [aritz.deviceId, web.deviceId],
          ),
        ),
        throwsA(isA<V2ForbiddenException>()),
      );
      await client.putRenewal(
        aritz,
        version: 1,
        command: _reservation(
          aritz,
          participants: [aritz.deviceId, web.deviceId],
        ),
      );
      await readyAndAck(aritz);
      await expectLater(
        step(aritz, 'prepare', {
          'pendingResources': 0,
          'coverageCommitment': encodeBase64Url(_cred(11)),
        }),
        throwsA(
          isA<V2RenewalConflictException>().having(
            (e) => e.code,
            'code',
            'renewal_participants_pending',
          ),
        ),
      );
      await step(web, 'ack', {
        'newDeviceId': 'web-new',
        'newSigningKey': encodeBase64Url(_cred(12)),
        'receipt': encodeBase64Url(_cred(13)),
        'destinationVersion': 3,
      });
      final prep = await step(aritz, 'prepare', {
        'pendingResources': 0,
        'coverageCommitment': encodeBase64Url(_cred(11)),
      }) as V2WriteOk;
      await expectLater(
        client.putCommon(
          web,
          version: prep.version,
          common: decodeBase64Url('BBBB'),
        ),
        throwsA(
          isA<V2RenewalConflictException>().having(
            (e) => e.code,
            'code',
            'renewal_frozen',
          ),
        ),
      );
      await expectLater(
        client.putList(aritz, version: prep.version, body: _body()),
        throwsA(isA<V2RenewalConflictException>()),
      );
      expect(await client.getList(web), isA<V2GetOk>());
      await expectLater(
        client.deleteList(aritz, version: prep.version),
        throwsA(isA<V2RenewalConflictException>()),
      );
      final confirmed = await step(aritz, 'confirm', {
        'snapshotVersion': prep.version,
        'pendingResources': 0,
        'coverageCommitment': encodeBase64Url(_cred(14)),
      }) as V2WriteOk;
      expect(
        await client.deleteList(aritz, version: prep.version),
        isA<V2WriteStale>(),
      );
      expect(
        await client.deleteList(aritz, version: confirmed.version),
        isA<V2WriteOk>(),
      );
      await expectLater(
        client.getRenewal(aritz),
        throwsA(isA<V2RenewalGoneException>()),
      );
    });

    test('revocation preserves barrier and requires signed revalidation, retaining identity commitment', () async {
      await client.createList(aritz, _body());
      worker.addCredentialForTesting(_sync, nora.deviceId, nora.credential);
      final plan = _reservation(
        aritz,
        participants: [aritz.deviceId, nora.deviceId],
      );
      await client.putRenewal(aritz, version: 1, command: plan);
      await readyAndAck(aritz);
      await step(nora, 'ack', {
        'newDeviceId': 'nora-new',
        'newSigningKey': encodeBase64Url(_cred(12)),
        'receipt': encodeBase64Url(_cred(13)),
        'destinationVersion': 3,
      });
      final prep = await step(aritz, 'prepare', {
        'pendingResources': 0,
        'coverageCommitment': encodeBase64Url(_cred(11)),
      }) as V2WriteOk;
      await step(aritz, 'revoke', {'participantDeviceId': nora.deviceId});
      final invalid = await client.getRenewal(aritz);
      expect(invalid.renewal!['needsRevalidation'], isTrue);
      expect(invalid.renewal!['barrierVersion'], prep.version);
      await expectLater(
        step(aritz, 'confirm', {
          'snapshotVersion': prep.version,
          'pendingResources': 0,
          'coverageCommitment': encodeBase64Url(_cred(14)),
        }),
        throwsA(isA<V2RenewalConflictException>()),
      );
      await step(aritz, 'revise', {
        'revision': 2,
        'participants': [aritz.deviceId, nora.deviceId],
        'inventoryCommitment': encodeBase64Url(_cred(15)),
      });
      final revised = await client.getRenewal(aritz);
      expect(revised.renewal!['reservation'], renewalCommandHash(plan));
      expect(revised.renewal!['acknowledgements'], isEmpty);
      await expectLater(
        client.putCommon(
          aritz,
          version: revised.version,
          common: decodeBase64Url('BBBB'),
        ),
        throwsA(isA<V2RenewalConflictException>()),
      );
      await readyAndAck(aritz);
      await step(aritz, 'exclude', {
        'participantDeviceId': nora.deviceId,
        'loss': true,
        'receipt': encodeBase64Url(_cred(16)),
      });
      await step(aritz, 'prepare', {
        'pendingResources': 0,
        'coverageCommitment': encodeBase64Url(_cred(11)),
      });
    });
  });

  group('lista', () {
    test(
      '4: approvedBy es opcional para pre.22 y llega cuando se conoce',
      () async {
        await client.createList(aritz, _body());
        expect(
          (await client.getList(
            aritz,
          ) as V2GetOk).snapshot.devices.single.approvedBy,
          isNull,
        );
        worker.addCredentialForTesting(
          _sync,
          nora.deviceId,
          nora.credential,
          approvedBy: aritz.deviceId,
        );
        final got = await client.getList(aritz) as V2GetOk;
        expect(got.snapshot.devices.last.approvedBy, aritz.deviceId);
      },
    );
    test('crear con If-Match "0", leer con ETag y 304', () async {
      expect(await client.createList(aritz, _body()), isA<V2WriteOk>());
      final got = await client.getList(aritz);
      expect(got, isA<V2GetOk>());
      final snap = (got as V2GetOk).snapshot;
      expect(snap.version, 1);
      expect(snap.devices.single.deviceId, 'aritz-phone');
      expect(snap.devices.single.revoked, isFalse);
      expect(
        await client.getList(aritz, ifNoneMatch: 1),
        isA<V2GetNotModified>(),
      );
    });

    test('crear otra vez: 412 si ya estoy dentro, 401 si no', () async {
      await client.createList(aritz, _body());
      final again = await client.createList(aritz, _body());
      expect(again, isA<V2WriteStale>());
      expect((again as V2WriteStale).current, 1);
      await expectLater(
        client.createList(nora, _body()),
        throwsA(
          isA<SyncTransportException>().having(
            (e) => e.failure,
            'failure',
            SyncFailure.unauthorized,
          ),
        ),
      );
    });

    test('PUT con versión vieja da 412 con la actual y no escribe', () async {
      await client.createList(aritz, _body());
      expect(
        await client.putList(aritz, version: 1, body: _body(common: 'BBBB')),
        isA<V2WriteOk>(),
      );
      final stale = await client.putList(aritz, version: 1, body: _body());
      expect((stale as V2WriteStale).current, 2);
      expect(worker.versionOf(_sync), 2);
    });

    test('un slot de otro móvil es 403 y más de 64 slots es 413', () async {
      await client.createList(aritz, _body());
      await expectLater(
        client.putList(
          aritz,
          version: 1,
          body: _body(
            slots: [
              V2SlotChange(
                personId: 'nora',
                deviceId: 'nora-phone',
                data: _slot('nora', 'nora-phone'),
              ),
            ],
          ),
        ),
        throwsA(isA<V2ForbiddenException>()),
      );
      await expectLater(
        client.putList(
          aritz,
          version: 1,
          body: _body(
            slots: [
              for (var i = 0; i < 65; i++)
                V2SlotChange(
                  personId: 'p$i',
                  deviceId: 'aritz-phone',
                  data: _slot('p$i', 'aritz-phone'),
                ),
            ],
          ),
        ),
        throwsA(
          isA<SyncTransportException>().having(
            (e) => e.failure,
            'failure',
            SyncFailure.tooLarge,
          ),
        ),
      );
    });

    test('slots: delta, manifiesto con versión, GET con If-Match', () async {
      await client.createList(
        aritz,
        _body(
          slots: [
            V2SlotChange(
              personId: 'leo',
              deviceId: 'aritz-phone',
              data: _slot('leo', 'aritz-phone'),
            ),
          ],
        ),
      );
      // Una subida sin slots ([]) los conserva.
      await client.putList(aritz, version: 1, body: _body(common: 'BBBB'));
      final snap = ((await client.getList(aritz)) as V2GetOk).snapshot;
      expect(snap.version, 2);
      expect(snap.slots.single.key, 'leo/aritz-phone');
      expect(snap.slots.single.version, 1);
      final slot = await client.getSlot(
        aritz,
        version: 2,
        personId: 'leo',
        deviceId: 'aritz-phone',
      );
      expect((slot as V2SlotOk).slotVersion, 1);
      expect(
        await client.getSlot(
          aritz,
          version: 1,
          personId: 'leo',
          deviceId: 'aritz-phone',
        ),
        isA<V2SlotStale>(),
      );
      expect(
        await client.getSlot(
          aritz,
          version: 2,
          personId: 'nora',
          deviceId: 'aritz-phone',
        ),
        isA<V2SlotMissing>(),
      );
    });

    test('DELETE condicional: 412 con otra versión y 404 después', () async {
      await client.createList(aritz, _body());
      await client.putList(aritz, version: 1, body: _body());
      expect(await client.deleteList(aritz, version: 1), isA<V2WriteStale>());
      expect(await client.deleteList(aritz, version: 2), isA<V2WriteOk>());
      expect(await client.getList(aritz), isA<V2GetNotFound>());
      // Un syncId borrado no se puede volver a crear.
      expect(worker.hasList(_sync), isFalse);
    });

    test('hallazgo 18: crear un syncId borrado es 410 retired para siempre y '
        'el cliente lo toma por lista que ya no está', () async {
      await client.createList(aritz, _body());
      expect(await client.deleteList(aritz, version: 1), isA<V2WriteOk>());
      final raw = await worker.send(
        'PUT',
        Uri.parse('https://sync.test/v2/lists/$_sync'),
        body: {
          'deviceId': 'leo-phone',
          'common': 'AAAA',
          'registry': {
            'v': 2,
            'records': <Object?>[],
            'vouches': <Object?>[],
            'revocations': <Object?>[],
          },
          'keyPackages': <Object?>[],
          'slots': <Object?>[],
        },
        headers: {
          'Authorization': _auth('leo-phone', 9).bearer,
          'If-Match': '"0"',
        },
      );
      expect(raw.status, 410);
      expect(raw.json()['error'], 'retired');
      for (final who in [aritz, nora, _auth('leo-phone', 9)]) {
        expect(await client.createList(who, _body()), isA<V2WriteNotFound>());
      }
      expect(await client.getList(aritz), isA<V2GetNotFound>());
    });

    test('hallazgo 18: capacity se lee del GET y 409 generation_full es un '
        'error propio y permanente', () async {
      await client.createList(aritz, _body());
      var snap = ((await client.getList(aritz)) as V2GetOk).snapshot;
      expect(snap.capacity!.credentials.used, 1);
      expect(snap.capacity!.credentials.warn, 48);
      expect(snap.capacity!.records.max, 512);
      expect(snap.capacity!.renew, isFalse);
      worker.fillGenerationForTesting(_sync, credentials: 48, records: 512);
      snap = ((await client.getList(aritz)) as V2GetOk).snapshot;
      expect(snap.capacity!.renew, isTrue);
      final full = V2SnapshotUpload(
        common: decodeBase64Url('AAAA'),
        registry: const {
          'v': 2,
          'records': [
            {'d': 'otro'},
          ],
          'vouches': <Object?>[],
          'revocations': <Object?>[],
        },
        keyPackages: const [],
      );
      await expectLater(
        client.putList(aritz, version: 1, body: full),
        throwsA(isA<V2GenerationFullException>()),
      );
      // Un capacity mal formado no se acepta.
      worker.tamper = (method, uri, r) => method == 'GET'
          ? _withBody(
              r,
              (j) => {
                ...j,
                'capacity': {'renew': 'sí'},
              },
            )
          : r;
      await expectLater(
        client.getList(aritz),
        throwsA(
          isA<SyncTransportException>().having(
            (e) => e.failure,
            'failure',
            SyncFailure.protocol,
          ),
        ),
      );
    });

    test('429 con Retry-After y 428 como error de protocolo', () async {
      await client.createList(aritz, _body());
      worker.rateLimitNext = 30;
      await expectLater(
        client.getList(aritz),
        throwsA(
          isA<SyncTransportException>()
              .having((e) => e.failure, 'failure', SyncFailure.rateLimited)
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(seconds: 30),
              ),
        ),
      );
      final raw = await worker.send(
        'PUT',
        Uri.parse('https://sync.test/v2/lists/$_sync'),
        body: {'common': 'AAAA'},
        headers: {'Authorization': aritz.bearer},
      );
      expect(raw.status, 428);
      worker.tamper = (method, uri, r) => raw;
      await expectLater(
        client.putList(aritz, version: 1, body: _body()),
        throwsA(
          isA<SyncTransportException>().having(
            (e) => e.failure,
            'failure',
            SyncFailure.protocol,
          ),
        ),
      );
    });
  });

  group('servidor que manipula', () {
    setUp(() async {
      await client.createList(
        aritz,
        _body(
          slots: [
            V2SlotChange(
              personId: 'leo',
              deviceId: 'aritz-phone',
              data: _slot('leo', 'aritz-phone'),
            ),
          ],
        ),
      );
    });

    test('una versión que no casa con el ETag no se acepta', () async {
      worker.tamper = (method, uri, r) =>
          method == 'GET' ? _withBody(r, (j) => {...j, 'version': 7}) : r;
      await expectLater(
        client.getList(aritz),
        throwsA(isA<SyncTransportException>()),
      );
    });

    // Cloudflare comprime las instantáneas grandes y pasa el ETag a W/"N"
    // (las primeras versiones de prueba no podían emparejar detrás del proxy).
    SyncResponse weakEtag(SyncResponse r, {int? version}) => SyncResponse(
      r.status,
      {
        ...r.headers,
        'etag': 'W/"${version ?? SyncV2Client.etagVersion(r.headers['etag'])}"',
      },
      r.body,
    );

    test('un ETag débil (W/"N") con la misma versión se acepta', () async {
      worker.tamper = (method, uri, r) =>
          method == 'GET' && r.status == 200 ? weakEtag(r) : r;
      final got = await client.getList(aritz);
      expect(got, isA<V2GetOk>());
    });

    test('un ETag débil con otra versión tampoco se acepta', () async {
      worker.tamper = (method, uri, r) =>
          method == 'GET' && r.status == 200 ? weakEtag(r, version: 7) : r;
      await expectLater(
        client.getList(aritz),
        throwsA(isA<SyncTransportException>()),
      );
    });

    test('un slot de otra versión que la pedida no se acepta', () async {
      worker.tamper = (method, uri, r) => uri.path.contains('/slots/')
          ? SyncResponse(
              200,
              {'etag': '"9"'},
              Uint8List.fromList(
                utf8.encode(
                  jsonEncode({'version': 9, 'slotVersion': 1, 'data': 'AAAA'}),
                ),
              ),
            )
          : r;
      await expectLater(
        client.getSlot(
          aritz,
          version: 1,
          personId: 'leo',
          deviceId: 'aritz-phone',
        ),
        throwsA(isA<SyncTransportException>()),
      );
    });

    test('un manifiesto con un slot más nuevo que la lista no vale', () async {
      worker.tamper = (method, uri, r) => method == 'GET'
          ? _withBody(r, (j) {
              final slots = [
                for (final s in j['slots'] as List)
                  {...(s as Map).cast<String, Object?>(), 'version': 5},
              ];
              return {...j, 'slots': slots};
            })
          : r;
      await expectLater(
        client.getList(aritz),
        throwsA(isA<SyncTransportException>()),
      );
    });

    test('una escritura que no sube la versión no vale', () async {
      worker.tamper = (method, uri, r) => method == 'PUT'
          ? SyncResponse(200, {
              'etag': '"1"',
            }, Uint8List.fromList(utf8.encode('{"version":1}')))
          : r;
      await expectLater(
        client.putList(aritz, version: 1, body: _body()),
        throwsA(isA<SyncTransportException>()),
      );
    });
  });

  group('revocar', () {
    test('la credencial revocada queda fuera de todo y su WS se cierra '
        'con 4401', () async {
      await client.createList(aritz, _body());
      worker.addCredentialForTesting(_sync, 'nora-phone', nora.credential);
      final events = <SyncEvent>[];
      final done = Completer<void>();
      client
          .watch(nora)
          .listen(events.add, onDone: done.complete, onError: (_) {});
      await Future<void>.delayed(Duration.zero);
      expect(worker.watchers(_sync), 1);
      expect(await client.revoke(aritz, 'nora-phone'), 2);
      await done.future;
      expect(events.first, isA<SyncOpenEvent>());
      expect(events.last, isA<SyncRevokedEvent>());
      for (final call in [
        () => client.getList(nora),
        () => client.putList(nora, version: 2, body: _body()),
        () => client.deleteList(nora, version: 2),
      ]) {
        await expectLater(
          call(),
          throwsA(
            isA<SyncTransportException>().having(
              (e) => e.failure,
              'failure',
              SyncFailure.unauthorized,
            ),
          ),
        );
      }
      // Idempotente y visible en devices.
      expect(await client.revoke(aritz, 'nora-phone'), 2);
      final snap = ((await client.getList(aritz)) as V2GetOk).snapshot;
      expect(
        snap.devices.firstWhere((d) => d.deviceId == 'nora-phone').revoked,
        isTrue,
      );
    });

    test('B2: condicional con ifVersion (If-Match); 412 no revoca; sin '
        'ifVersion no lleva precondición', () async {
      final leo = _auth('leo-phone', 3);
      final sent = <String?>[];
      final watching = SyncV2Client(
        base: Uri.parse('https://sync.test'),
        sendRequest: (method, uri, {body, headers = const {}}) {
          if (method == 'POST' && uri.path.endsWith('/revoke')) {
            sent.add(headers['If-Match']);
          }
          return worker.send(method, uri, body: body, headers: headers);
        },
        openSocket: worker.socket,
      );
      await client.createList(aritz, _body());
      worker.addCredentialForTesting(_sync, 'nora-phone', nora.credential);
      worker.addCredentialForTesting(_sync, 'leo-phone', leo.credential);
      await expectLater(
        watching.revoke(aritz, 'nora-phone', ifVersion: 0),
        throwsA(isA<V2RevokeStaleException>()),
      );
      expect(worker.devicesOf(_sync)['nora-phone'], isFalse);
      expect(await watching.revoke(aritz, 'nora-phone', ifVersion: 1), 2);
      expect(worker.devicesOf(_sync)['nora-phone'], isTrue);
      expect(await watching.revoke(aritz, 'leo-phone'), 3);
      expect(sent, ['"0"', '"1"', null]);
    });
  });

  group('invitaciones v2', () {
    Map<String, Object?> offer(String device) => {
      'v': 2,
      'host': {'d': device},
      'c': encodeBase64Url(List.filled(32, 3)),
    };
    final guestCredential = _cred(9);
    final guestVerifier = Uint8List.fromList(
      const DartSha256().hashSync(guestCredential).bytes,
    );
    Map<String, Object?> answer(String device) => {
      'v': 2,
      'guest': {'d': device},
      'vouch': <String, Object?>{},
      'gn': encodeBase64Url(List.filled(32, 4)),
    };

    test('oferta, respuesta única, revelación, aprobación y resultado '
        'repetible', () async {
      await client.createList(aritz, _body());
      final ticket = await client.createInvite(aritz, offer('aritz-phone'));
      final id = ticket.inviteId;
      expect((await client.getOffer(id)).offer, isA<Map>());
      expect(
        await client.pollInviteResult(id, credential: guestCredential),
        isA<V2InviteGone>(),
        reason: 'sin respuesta, la credencial no es de nadie',
      );
      await expectLater(
        client.revealInvite(aritz, id, {'v': 2, 'n': 'x'}),
        throwsA(
          isA<V2InviteConflictException>().having(
            (e) => e.code,
            'code',
            'invalid_state',
          ),
        ),
      );
      await client.answerInvite(
        id,
        answer: answer('leo-phone'),
        verifier: guestVerifier,
      );
      await expectLater(
        client.answerInvite(
          id,
          answer: answer('intruso'),
          verifier: Uint8List(32),
        ),
        throwsA(isA<InviteTakenException>()),
      );
      expect((await client.getInvite(aritz, id)).answer, isA<Map>());
      final pending = await client.pollInviteResult(
        id,
        credential: guestCredential,
      );
      expect((pending as V2InvitePending).reveal, isNull);
      await client.revealInvite(aritz, id, {
        'v': 2,
        'n': encodeBase64Url(List.filled(32, 5)),
      });
      final revealed = await client.pollInviteResult(
        id,
        credential: guestCredential,
      );
      expect((revealed as V2InvitePending).reveal, isA<Map>());
      expect(
        await client.approveInvite(aritz, id, version: 0, package: {}),
        isA<V2WriteStale>(),
      );
      final ok = await client.approveInvite(
        aritz,
        id,
        version: 1,
        package: {'k': 'cifrado'},
      );
      expect((ok as V2WriteOk).version, 2);
      for (var i = 0; i < 2; i++) {
        final result = await client.pollInviteResult(
          id,
          credential: guestCredential,
        );
        expect((result as V2InviteApproved).minVersion, 2);
        expect(result.syncId, _sync);
        expect(result.package['k'], 'cifrado');
      }
      // La credencial del invitado ya vale para la lista.
      final guest = V2Auth(
        syncId: _sync,
        deviceId: 'leo-phone',
        credential: guestCredential,
      );
      expect(await client.getList(guest), isA<V2GetOk>());
    });

    test('la invitación de otro dueño es 403 y una borrada, 404', () async {
      await client.createList(aritz, _body());
      worker.addCredentialForTesting(_sync, 'nora-phone', nora.credential);
      final id = (await client.createInvite(
        aritz,
        offer('aritz-phone'),
      )).inviteId;
      await expectLater(
        client.getInvite(nora, id),
        throwsA(isA<V2ForbiddenException>()),
      );
      await client.deleteInvite(aritz, id);
      await expectLater(
        client.getOffer(id),
        throwsA(isA<InviteGoneException>()),
      );
    });
  });
}
