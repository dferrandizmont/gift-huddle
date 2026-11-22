// Lote B7 del ADR 0005: el checkpoint al emparejar (§6, fila
// «Emparejamiento» de la §8). El anfitrión firma la aprobación del estado
// exacto que hay en el servidor; el Worker guarda una copia inmutable por
// invitación; el invitado instala esa base verificada y después fusiona lo
// actual. Contra el Worker falso y con un servidor que manipula.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/device_keys.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/family_envelope.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/pairing_v2.dart';
import 'package:regalos/features/sync/application/common_v2.dart';
import 'package:regalos/features/sync/application/migration_v2.dart';
import 'package:regalos/features/sync/application/pairing_v2_flow.dart';
import 'package:regalos/features/sync/application/v2_family_lock.dart';
import 'package:regalos/features/sync/data/sync_transport_common.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';
import 'package:regalos/features/web_device/application/web_pairing_guest.dart';

import '../helpers/fake_worker_v2.dart';
import 'v2_harness.dart';

Future<DeviceKeys> _keys(int seed) => DeviceKeys.fromSeedsForTesting(
  agreementSeed: List<int>.filled(32, seed),
  signingSeed: List<int>.filled(32, seed + 100),
  serviceCredential: List<int>.filled(32, seed + 200),
);

SyncResponse _json(int status, Object? body, [Map<String, String>? headers]) =>
    SyncResponse(
      status,
      headers ?? const {},
      Uint8List.fromList(utf8.encode(jsonEncode(body))),
    );

Matcher _pairing(String message) => throwsA(
  isA<PairingException>().having((e) => e.message, 'message', message),
);

const _notApproved = 'el checkpoint no es el aprobado';

void main() {
  late FakeWorkerV2 worker;
  late SyncV2Client client;
  late MemoryV2Phone aritz;
  late V2FamilyLock lock;

  setUp(() async {
    lock = V2FamilyLock();
    worker = FakeWorkerV2();
    client = worker.client();
    aritz = await MemoryV2Phone.create(
      'aritz-phone',
      'aritz',
      1,
      familyKey: await FamilyKey.generate(),
      migrated: true,
    );
    aritz
      ..addPerson('aritz', 'Aritz')
      ..addPerson('leo', 'Leo')
      ..addPerson('nora', 'Nora')
      ..addGift('g1', 'nora', 'Bufanda');
  });

  /// Hasta los dos códigos, con el invitado [deviceId] (semilla [seed]).
  Future<(PairingV2Host, PairingV2Guest)> toCodes({
    String deviceId = 'leo-phone',
    int seed = 2,
    String? person = 'leo',
  }) async {
    // 1.0.6: el anfitrión elige la persona del móvil nuevo.
    final host = await PairingV2Host.start(
      transport: client,
      local: aritz,
      lock: lock,
      guestPerson: person,
      hostPicksPerson: person != null,
    );
    final guest = await PairingV2Guest.open(
      transport: client,
      inviteId: host.inviteId,
      keys: await _keys(seed),
      deviceIdFor: (_, _) => deviceId,
    );
    await guest.answer(personId: person, withoutPerson: person == null);
    final hostCode = (await host.poll())!.code;
    expect(await guest.code(), hostCode);
    guest.confirmCode();
    return (host, guest);
  }

  /// El invitado como un móvil v2 en memoria, instalado como `_install`.
  Future<MemoryV2Phone> install(
    PairingV2Joined joined, {
    String deviceId = 'leo-phone',
    String person = 'leo',
    int seed = 2,
  }) async {
    final p = await MemoryV2Phone.create(
      deviceId,
      person,
      seed,
      familyKey: joined.familyKey,
      doc: joined.common,
    );
    p
      ..reg = joined.registry
      ..state = p.state.copyWith(
        created: true,
        version: joined.minVersion,
        minSlotRevisions: joined.minSlotRevisions,
        commonFormatV2: joined.commonFormat >= 2,
      )
      ..formatFloor = joined.commonFormat;
    if (joined.commonKeys != null) {
      p
        ..commonKeysJson = jsonEncode(joined.commonKeys!.toJson())
        ..commonKeysMarker = true;
    }
    return p;
  }

  Future<V2Snapshot> snapshot() async =>
      (await client.getList(aritz.auth) as V2GetOk).snapshot;

  bool isCheckpoint(Uri uri) => uri.path.endsWith('/checkpoint');
  bool isList(String method, Uri uri) =>
      method == 'GET' && uri.path == '/v2/lists/$kV2Sync';

  for (final cut in [false, true]) {
    final format = cut ? 'formato 2' : 'formato 1';

    test('$format: el invitado instala exactamente la base aprobada y la '
        'aprobación la ata a la invitación', () async {
      if (cut) aritz.enableCommonV2();
      final (host, guest) = await toCodes();
      await host.confirm(confirmedPersonId: 'leo');
      final joined = (await guest.finish())!;
      expect(joined.commonFormat, cut ? 2 : 1);
      expect((cut ? joined.commonKeys : null) != null, cut);
      expect(joined.common.record(Collections.gifts, 'g1'), isNotNull);
      final checkpoint = (await client.getInviteCheckpoint(
        host.inviteId,
        credential: (await _keys(2)).serviceCredential,
      ))!;
      final got = await client.pollInviteResult(
        host.inviteId,
        credential: (await _keys(2)).serviceCredential,
      ) as V2InviteApproved;
      expect(
        got.package['commonCheckpointHash'],
        pairingCheckpointHash('common', checkpoint.common),
      );
      expect(got.package['inviteId'], host.inviteId);
      final leo = await install(joined);
      await leo.engine(client).sync();
      expect(leo.giftTitles, {'Bufanda'});
      expect((await leo.view()).paired, isTrue);
    });

    test('$format: un común viejo con versión nueva no borra la base que el '
        'invitado ya verificó', () async {
      if (cut) aritz.enableCommonV2();
      await aritz.engine(client).ensureCreated();
      await aritz.engine(client).sync();
      final old = (await snapshot()).common;
      aritz.addGift('g2', 'leo', 'Libro');
      final (host, guest) = await toCodes();
      await host.confirm(confirmedPersonId: 'leo');
      // El servidor sirve al invitado el común de antes con el ETag nuevo.
      worker.tamper = (method, uri, response) {
        if (isList(method, uri) && response.status == 200) {
          return _json(200, {
            ...response.json(),
            'common': encodeBase64Url(old),
          }, response.headers);
        }
        return response;
      };
      final joined = (await guest.finish())!;
      expect(joined.common.record(Collections.gifts, 'g2'), isNotNull);
      final leo = await install(joined);
      await leo.engine(client).sync();
      expect(leo.giftTitles, {'Bufanda', 'Libro'});
    });

    test('$format: un checkpoint sustituido (común o registro) no se '
        'instala', () async {
      if (cut) aritz.enableCommonV2();
      for (final part in ['common', 'registry']) {
        final (host, guest) = await toCodes(
          deviceId: part == 'common' ? 'leo-phone' : 'nora-phone',
          seed: part == 'common' ? 2 : 3,
          person: part == 'common' ? 'leo' : 'nora',
        );
        await host.confirm(
          confirmedPersonId: part == 'common' ? 'leo' : 'nora',
        );
        // Lo actual es legítimo, pero no es lo aprobado.
        aritz.addGift('g-$part', 'aritz', 'Otra cosa');
        await aritz.engine(client).sync();
        final now = await snapshot();
        worker.tamper = (method, uri, response) {
          if (isCheckpoint(uri) && response.status == 200) {
            final json = response.json();
            return _json(200, {
              ...json,
              if (part == 'common') 'common': encodeBase64Url(now.common),
              if (part == 'registry')
                'registry': canonicalJsonText({
                  ...(jsonDecode(json['registry'] as String) as Map),
                  'records': [
                    ...((jsonDecode(json['registry'] as String)
                            as Map)['records']
                        as List),
                  ].reversed.toList(),
                }),
            });
          }
          return response;
        };
        await expectLater(guest.finish(), _pairing(_notApproved), reason: part);
        worker.tamper = null;
      }
    });

    test('$format: el servidor que retiene el checkpoint deja el '
        'emparejamiento pendiente, sin instalar nada', () async {
      if (cut) aritz.enableCommonV2();
      final (host, guest) = await toCodes();
      await host.confirm(confirmedPersonId: 'leo');
      var withheld = true;
      worker.tamper = (method, uri, response) => withheld && isCheckpoint(uri)
          ? _json(404, {'error': 'not_found'})
          : response;
      for (var i = 0; i < 3; i++) {
        expect(await guest.finish(), isNull, reason: 'pendiente');
      }
      // Sin checkpoint, aunque el resto llegue, no hay base distinta.
      withheld = false;
      final joined = (await guest.finish())!;
      expect(joined.common.record(Collections.gifts, 'g1'), isNotNull);
    });

    test('$format: un común actual posterior legítimo no obliga a empezar '
        'de nuevo y entra en la primera vuelta', () async {
      if (cut) aritz.enableCommonV2();
      final (host, guest) = await toCodes();
      await host.confirm(confirmedPersonId: 'leo');
      aritz.addGift('g3', 'leo', 'Bici');
      await aritz.engine(client).sync();
      final joined = (await guest.finish())!;
      expect(joined.common.record(Collections.gifts, 'g3'), isNull);
      final leo = await install(joined);
      await leo.engine(client).sync();
      expect(leo.giftTitles, {'Bufanda', 'Bici'});
    });

    test('$format: invitaciones mezcladas no valen (ni la aprobación ni el '
        'checkpoint de otra)', () async {
      if (cut) aritz.enableCommonV2();
      final (hostA, guestA) = await toCodes();
      final (hostB, guestB) = await toCodes(
        deviceId: 'nora-phone',
        seed: 3,
        person: 'nora',
      );
      await hostA.confirm(confirmedPersonId: 'leo');
      await hostB.confirm(confirmedPersonId: 'nora');
      final credA = (await _keys(2)).serviceCredential;
      final resultA = await client.pollInviteResult(
        hostA.inviteId,
        credential: credA,
      ) as V2InviteApproved;
      final checkpointA = (await client.getInviteCheckpoint(
        hostA.inviteId,
        credential: credA,
      ))!;
      // La aprobación (bien firmada) de A, servida en B.
      worker.tamper = (method, uri, response) {
        if (uri.path == '/v2/invites/${hostB.inviteId}/result' &&
            response.status == 200) {
          return _json(200, {...response.json(), 'package': resultA.package});
        }
        return response;
      };
      await expectLater(
        guestB.finish(),
        _pairing('la aprobación es de otro emparejamiento'),
      );
      // El checkpoint de A, servido en B.
      worker.tamper = (method, uri, response) {
        if (uri.path == '/v2/invites/${hostB.inviteId}/checkpoint') {
          return _json(200, {
            'common': checkpointA.common,
            'registry': checkpointA.registry,
          });
        }
        return response;
      };
      await expectLater(guestB.finish(), _pairing(_notApproved));
      worker.tamper = null;
      expect(await guestB.finish(), isNotNull);
      expect(await guestA.finish(), isNotNull);
    });
  }

  test('formato 1: un HLC máximo intacto con campos omitidos no sustituye '
      'la base, ni como checkpoint ni como común actual', () async {
    final (host, guest) = await toCodes();
    await host.confirm(confirmedPersonId: 'leo');
    // Un común bien cifrado que conserva el campo de HLC máximo y omite los
    // demás (la bufanda).
    final forged = FamilyDoc.empty(kV2List)
        .set(aritz.clock, Collections.meta, kProtocolRecordId, {
          kProtocolVersionField: kSyncProtocolV2,
        })
        .set(aritz.clock, Collections.gifts, 'g9', {
          'recipientId': 'nora',
          'title': 'Gorro',
          'status': 'idea',
          'year': 2026,
        });
    expect(forged.maxStamp!.compareTo(aritz.doc.maxStamp!), greaterThan(0));
    final bytes = await seal(
      doc: forged.toJson(),
      listId: kV2List,
      fromNode: aritz.node,
      at: forged.maxStamp!.pack(),
      key: aritz.familyKey,
    );
    worker.tamper = (method, uri, response) {
      if (isCheckpoint(uri) && response.status == 200) {
        return _json(200, {
          ...response.json(),
          'common': encodeBase64Url(bytes),
        });
      }
      return response;
    };
    await expectLater(guest.finish(), _pairing(_notApproved));
    worker.tamper = (method, uri, response) {
      if (isList(method, uri) && response.status == 200) {
        return _json(200, {
          ...response.json(),
          'common': encodeBase64Url(bytes),
        }, response.headers);
      }
      return response;
    };
    final joined = (await guest.finish())!;
    final leo = await install(joined);
    await leo.engine(client).sync();
    expect(leo.giftTitles, containsAll(['Bufanda', 'Gorro']));
  });

  test('tras el corte el invitado nace con la marca y nunca abre un formato '
      '1, aunque el servidor lo sirva con el mínimo 1', () async {
    aritz.enableCommonV2();
    final (host, guest) = await toCodes();
    await host.confirm(confirmedPersonId: 'leo');
    final joined = (await guest.finish())!;
    final leo = await install(joined);
    expect(leo.formatFloor, 2);
    expect(
      leo.commonKeys.lastKid,
      peekFamilyEnvelope(
        decodeBase64Url(
          (await client.getInviteCheckpoint(
            host.inviteId,
            credential: leo.keys.serviceCredential,
          ))!.common,
        ),
      ).kid,
    );
    await leo.engine(client).sync();
    expect(leo.giftTitles, {'Bufanda'});
    // Un servidor que miente: un formato 1 con la clave de siempre (que el
    // invitado ni conoce) y el mínimo bajado.
    final v1 = FamilyDoc.empty(kV2List)
        .merge(aritz.doc)
        .set(aritz.clock, Collections.gifts, 'g8', {
          'recipientId': 'nora',
          'title': 'Colado',
          'status': 'idea',
          'year': 2026,
        });
    worker.setCommonForTesting(
      kV2Sync,
      await seal(
        doc: v1.toJson(),
        listId: kV2List,
        fromNode: aritz.node,
        at: v1.maxStamp!.pack(),
        key: aritz.familyKey,
      ),
      minCommonFormat: 1,
    );
    try {
      await leo.engine(client).sync();
    } on Object {
      // Puede rechazar la vuelta; lo que importa es que no fusiona.
    }
    expect(leo.giftTitles, {'Bufanda'});
    expect(leo.formatFloor, 2);
  });

  test('sin corte, el paquete sigue siendo la familyKey en v3 y el invitado '
      'no pone la marca', () async {
    final (host, guest) = await toCodes();
    await host.confirm(confirmedPersonId: 'leo');
    final joined = (await guest.finish())!;
    expect(joined.commonFormat, 1);
    expect(joined.commonKeys, isNull);
    expect(joined.familyKey, aritz.familyKey);
  });

  test('el anfitrión no aprueba lo que no puede abrir: no queda ninguna '
      'credencial', () async {
    aritz.enableCommonV2();
    final (host, guest) = await toCodes();
    // El llavero de este móvil se pierde (o el común es de una candidata
    // que no tiene): no firma una base que no ha autenticado.
    final real = aritz.commonKeysJson;
    worker.tamper = (method, uri, response) {
      if (method == 'PUT' && uri.path == '/v2/lists/$kV2Sync') {
        aritz.commonKeysJson = jsonEncode(CommonKeyState().toJson());
      }
      return response;
    };
    await expectLater(
      host.confirm(confirmedPersonId: 'leo'),
      _pairing('este móvil no puede abrir el común que aprobaría'),
    );
    worker.tamper = null;
    aritz.commonKeysJson = real;
    expect(worker.devicesOf(kV2Sync).containsKey('leo-phone'), isFalse);
    expect(await guest.finish(), isNull);
  });

  test('P4 (M1): la web parte del checkpoint verificado, no de la '
      'instantánea actual sin verificar', () async {
    aritz.keyring = SurpriseKeyring([
      SurpriseKey(
        personId: 'nora',
        epoch: 1,
        bytes: List<int>.filled(32, 42),
        audience: const ['aritz-phone'],
      ),
    ]);
    final web = await WebPairingGuest.create(transport: client);
    await web.poll();
    final host = await PairingV2Host.start(
      transport: client,
      local: aritz,
      lock: lock,
      web: web.qr,
      guestPerson: 'leo',
    );
    await web.poll();
    await host.poll();
    await web.poll();
    web.confirmCode();
    await host.confirm(confirmedPersonId: 'leo');
    final garbage = encodeBase64Url(List<int>.filled(64, 7));
    worker.tamper = (method, uri, response) {
      if (isList(method, uri) && response.status == 200) {
        return _json(200, {
          ...response.json(),
          'common': garbage,
          'registry': {
            'v': 2,
            'l': 'otra',
            'records': <Object?>[],
            'vouches': <Object?>[],
            'revocations': <Object?>[],
          },
        }, response.headers);
      }
      return response;
    };
    await web.poll();
    final joined = web.joined!;
    worker.tamper = null;
    final got = await client.pollInviteResult(
      host.inviteId,
      credential: web.keys.serviceCredential,
    ) as V2InviteApproved;
    expect(encodeBase64Url(joined.snapshot.common), isNot(garbage));
    expect(
      pairingCheckpointHash('common', encodeBase64Url(joined.snapshot.common)),
      got.package['commonCheckpointHash'],
    );
    expect(
      pairingCheckpointHash(
        'registry',
        canonicalJsonText(joined.snapshot.registry),
      ),
      got.package['registryCheckpointHash'],
    );
    expect(joined.snapshot.version, got.package['minVersion']);
    expect(joined.snapshot.keyPackages, isEmpty);
    // El testigo de protegidos sale de los suelos firmados, no del servidor.
    expect(
      [for (final r in joined.snapshot.slots) '${r.personId}/${r.deviceId}'],
      ['nora/aritz-phone'],
    );
    expect((got.package['slotFloors'] as Map).keys, ['nora/aritz-phone']);
    expect(joined.snapshot.devices, isEmpty);
  });

  test(
    'privacy: installation acknowledgement retries a lost request',
    () async {
      var deletes = 0;
      client = SyncV2Client(
        base: client.base,
        sendRequest: (method, uri, {body, headers = const {}}) async {
          if (method == 'DELETE' &&
              uri.path.endsWith('/checkpoint') &&
              ++deletes < 3) {
            return _json(503, {'error': 'unavailable'});
          }
          return worker.send(method, uri, body: body, headers: headers);
        },
      );
      final (host, guest) = await toCodes();
      await host.confirm(confirmedPersonId: 'leo');
      expect(await guest.finish(), isNotNull);
      await guest.releaseCheckpoint();
      expect(deletes, 3);
      expect(
        await client.pollInviteResult(
          host.inviteId,
          credential: (await _keys(2)).serviceCredential,
        ),
        isA<V2InviteGone>(),
      );
    },
  );

  test('P2 (M2): cinco emparejamientos seguidos caben; el invitado libera su '
      'checkpoint; sin cupo el anfitrión se para antes de publicar', () async {
    for (var n = 0; n < 8; n++) {
      final (host, guest) = await toCodes(
        deviceId: 'phone-$n',
        seed: 10 + n,
        person: 'leo',
      );
      await host.confirm(confirmedPersonId: 'leo');
      expect(await guest.finish(), isNotNull, reason: 'emparejamiento $n');
      await guest.releaseCheckpoint();
      expect(
        await client.pollInviteResult(
          host.inviteId,
          credential: (await _keys(10 + n)).serviceCredential,
        ),
        isA<V2InviteGone>(),
      );

      expect(
        await client.getInviteCheckpoint(
          host.inviteId,
          credential: (await _keys(10 + n)).serviceCredential,
        ),
        isNull,
        reason: 'liberado',
      );
    }
    // El cupo diario de altas (8) ya está gastado: se para antes de
    // publicar la ficha y los avales del noveno.
    final (host, _) = await toCodes(
      deviceId: 'phone-8',
      seed: 18,
      person: 'leo',
    );
    final before = await snapshot();
    await expectLater(
      host.confirm(confirmedPersonId: 'leo'),
      _pairing('hoy ya no caben más dispositivos nuevos en la familia'),
    );
    expect((await snapshot()).version, before.version);
    expect((await aritz.view()).device('phone-8'), isNull);
    expect(worker.devicesOf(kV2Sync).containsKey('phone-8'), isFalse);
  });

  test('P3: el mismo invitado en dos invitaciones: la aprobación y el '
      'checkpoint de una no valen en la otra', () async {
    final (hostA, guestA) = await toCodes();
    final (hostB, guestB) = await toCodes();
    await hostA.confirm(confirmedPersonId: 'leo');
    final cred = (await _keys(2)).serviceCredential;
    final resultA = await client.pollInviteResult(
      hostA.inviteId,
      credential: cred,
    ) as V2InviteApproved;
    final checkpointA = (await client.getInviteCheckpoint(
      hostA.inviteId,
      credential: cred,
    ))!;
    worker.tamper = (method, uri, response) {
      if (uri.path == '/v2/invites/${hostB.inviteId}/result') {
        final json = response.json();
        return _json(200, {
          'reveal': json['reveal'],
          'package': resultA.package,
          'minVersion': resultA.minVersion,
          'syncId': resultA.syncId,
        });
      }
      if (uri.path == '/v2/invites/${hostB.inviteId}/checkpoint') {
        return _json(200, {
          'common': checkpointA.common,
          'registry': checkpointA.registry,
        });
      }
      return response;
    };
    await expectLater(
      guestB.finish(),
      _pairing('la aprobación es de otro emparejamiento'),
    );
    worker.tamper = null;
    expect(await guestA.finish(), isNotNull);
  });

  test('B3: ante checkpoint_mismatch el anfitrión reescribe una vez el '
      'común y el registro y vuelve a aprobar', () async {
    var refused = 0;
    var puts = 0;
    client = SyncV2Client(
      base: client.base,
      sendRequest: (method, uri, {body, headers = const {}}) async {
        if (method == 'PUT' && uri.path == '/v2/lists/$kV2Sync') puts++;
        // El Worker no llega a aprobar: lo guardado no casa con los hashes.
        if (uri.path.endsWith('/approve') && refused == 0) {
          refused++;
          return _json(409, {'error': 'checkpoint_mismatch'});
        }
        return worker.send(method, uri, body: body, headers: headers);
      },
    );
    final (host, guest) = await toCodes();
    final putsBefore = puts;
    await host.confirm(confirmedPersonId: 'leo');
    expect(refused, 1);
    expect(puts - putsBefore, greaterThanOrEqualTo(2), reason: 'reescrito');
    expect(await guest.finish(), isNotNull);
  });

  test(
    'B4: tras el corte el anfitrión pone primero su propio paquete',
    () async {
      aritz.enableCommonV2();
      final (host, guest) = await toCodes();
      await host.confirm(confirmedPersonId: 'leo');
      final got = await client.pollInviteResult(
        host.inviteId,
        credential: (await _keys(2)).serviceCredential,
      ) as V2InviteApproved;
      final packages = got.package['familyKeyPackages'] as List;
      expect((packages.first as Map)['from'], 'aritz-phone');
      expect(await guest.finish(), isNotNull);
    },
  );

  test('PendingV2 conserva el formato mínimo (y uno dañado no lo rebaja)', () {
    final key = FamilyKey.fromBase64Url(
      encodeBase64Url(List<int>.filled(32, 7)),
    );
    final p = PendingV2(key: key, syncId: kV2Sync, commonFormat: 2);
    expect(PendingV2.fromJson(p.toJson())!.commonFormat, 2);
    expect(
      PendingV2.fromJson(PendingV2(key: key, syncId: kV2Sync).toJson())!
          .commonFormat,
      1,
    );
    expect(PendingV2.fromJson({...p.toJson(), 'cf': 'x'})!.commonFormat, 2);
  });

  test('vector del hash del checkpoint (el Worker calcula el mismo)', () {
    const registry = {
      'v': 2,
      'l': 'family',
      'records': [
        {'d': 'aritz', 'k': 'web', 'n': 'Ñandú'},
      ],
      'vouches': <Object?>[],
      'revocations': <Object?>[],
      'x': {'10': 1, '2': 9007199254740991, 'a': true, 'b': null},
    };
    final text = canonicalJsonText(registry);
    expect(
      text,
      '{"l":"family","records":[{"d":"aritz","k":"web","n":"Ñandú"}],'
      '"revocations":[],"v":2,"vouches":[],'
      '"x":{"10":1,"2":9007199254740991,"a":true,"b":null}}',
    );
    expect(pairingCheckpointHash('registry', text), kCheckpointRegistryVector);
    expect(pairingCheckpointHash('common', 'UkcCAAA'), kCheckpointCommonVector);
  });
}

/// Los mismos que `server/test/v2.test.ts` («B7: pairing checkpoint»).
const kCheckpointRegistryVector = 'Jbf9Hr-umQPirKpZKVLGe49T-uM7u3_O6Yvxi3ymXv0';
const kCheckpointCommonVector = 'kaBsFU0H8fypGZFljR160Awkn3unXVz7VzKls73eid4';
