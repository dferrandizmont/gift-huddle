import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/device_keys.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/key_bundle.dart';
import 'package:regalos/core/sync/pairing_v2.dart';
import 'package:regalos/features/sync/application/pairing_v2_flow.dart';
import 'package:regalos/features/sync/application/sync_v2_engine.dart';
import 'package:regalos/features/sync/application/v2_family_lock.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';
import 'package:regalos/features/sync/data/sync_transport_common.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';

import '../helpers/fake_worker_v2.dart';
import 'v2_harness.dart';

Future<DeviceKeys> _keys(int seed) => DeviceKeys.fromSeedsForTesting(
  agreementSeed: List<int>.filled(32, seed),
  signingSeed: List<int>.filled(32, seed + 100),
  serviceCredential: List<int>.filled(32, seed + 200),
);

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

  test(
    'pairing marks its first upload as temporary; permanent sync opts out',
    () async {
      for (final temporary in [true, false]) {
        final uploads = <Map<String, Object?>>[];
        final transport = SyncV2Client(
          base: Uri.parse('https://sync.test'),
          sendRequest: (method, uri, {body, headers = const {}}) {
            if (method == 'PUT' && headers['If-Match'] == '"0"') {
              uploads.add(Map<String, Object?>.from(body! as Map));
            }
            return worker.send(method, uri, body: body, headers: headers);
          },
        );
        final local = await MemoryV2Phone.create(
          temporary ? 'aritz-phone' : 'nora-phone',
          temporary ? 'aritz' : 'nora',
          temporary ? 1 : 2,
          familyKey: await FamilyKey.generate(),
          syncId: encodeBase64Url(
            Uint8List.fromList(List.filled(16, temporary ? 1 : 2)),
          ),
          migrated: true,
        );
        await PairingV2Host.start(
          transport: transport,
          local: local,
          lock: lock,
          inviteCopy: temporary,
        );
        expect(uploads, hasLength(1));
        expect(uploads.single['inviteCopy'], temporary ? isTrue : isNull);
      }
    },
  );

  /// Los dos lados hasta enseñar el código.
  Future<(PairingV2Host, PairingV2Guest, String, String)> toCodes({
    String? person = 'leo',
    bool withoutPerson = false,
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
      keys: await _keys(2),
      deviceIdFor: (_, _) => 'leo-phone',
    );
    expect(guest.listId, kV2List);
    expect(await host.poll(), isNull);
    await guest.answer(personId: person, withoutPerson: withoutPerson);
    expect(await guest.code(), isNull, reason: 'sin revelar todavía');
    final answered = (await host.poll())!;
    final code = (await guest.code())!;
    return (host, guest, answered.code, code);
  }

  test('los dos ven el mismo código; al confirmar, el invitado entra con '
      'la clave de la familia, el registro y la marca del anfitrión', () async {
    aritz.keyring = SurpriseKeyring([
      SurpriseKey(
        personId: 'nora',
        epoch: 1,
        bytes: List<int>.filled(32, 42),
        audience: const ['aritz-phone'],
      ),
    ]);
    // Un regalo público de Nora no sale del móvil que tiene su clave (lote
    // 6): el que viaja es uno de otra persona.
    aritz.addGift('g2', 'leo', 'Libro');
    final (host, guest, hostCode, guestCode) = await toCodes();
    expect(hostCode, guestCode);
    expect(hostCode, matches(RegExp(r'^\d{6}$')));
    await expectLater(guest.finish(), throwsA(isA<PairingException>()));
    guest.confirmCode();
    expect(await guest.finish(), isNull, reason: 'sin aprobar');
    await host.confirm(confirmedPersonId: 'leo');
    final joined = (await guest.finish())!;
    expect(joined.familyKey, aritz.familyKey);
    expect(joined.identity.syncId, kV2Sync);
    expect(joined.minSlotRevisions.keys, ['nora/aritz-phone']);
    expect(joined.hostDeviceId, 'aritz-phone');
    expect(joined.common.record('gifts', 'g1'), isNull);
    expect(joined.common.record('gifts', 'g2'), isNotNull);
    // El invitado sincroniza con lo que ha recibido.
    final leo = await MemoryV2Phone.create(
      'leo-phone',
      'leo',
      2,
      familyKey: joined.familyKey,
    );
    leo
      ..reg = joined.registry
      ..state = leo.state.copyWith(
        created: true,
        minSlotRevisions: joined.minSlotRevisions,
      );
    await leo.engine(client).sync();
    expect(leo.giftTitles, {'Libro'});
    expect((await leo.view()).paired, isTrue);
    // La clave de las sorpresas de Nora le llega a Leo (tiene derecho).
    expect(leo.keyring.latestFor('nora'), isNotNull);
    expect((await aritz.view()).paired, isTrue);
  });

  test('M1 de la revisión de seguridad: el invitado instala el común del '
      'checkpoint por la frontera de los deseos', () async {
    // Un anfitrión de esta versión ya saca esto de lo que aprueba; el
    // invitado lo vuelve a pasar por la frontera por si el anfitrión no lo es
    // (defensa en profundidad: aquí no se puede fabricar un anfitrión que no
    // la aplique, porque el checkpoint va firmado).
    aritz.doc = aritz.doc.set(aritz.clock, 'gifts', 'gx', {
      'recipientId': 'leo',
      'title': 'Libro',
      'status': 'idea',
      'year': 2026,
      'purchaseUrl': 'https://tienda.example/secreto',
      'claimantPersonId': 'aritz',
    });
    aritz.addGift('g2', 'leo', 'Otro');
    final (host, guest, _, _) = await toCodes();
    guest.confirmCode();
    await host.confirm(confirmedPersonId: 'leo');
    final joined = (await guest.finish())!;
    expect(joined.common.record('gifts', 'g2'), isNotNull);
    expect(joined.common.record('gifts', 'gx'), isNull);
    expect(joined.common.canonicalJson(), isNot(contains('secreto')));
  });

  for (final attack in [
    'quitar',
    'bajar',
    'subir',
    'sustituir clave',
    'sin firma',
    'bajar suelo',
    'quitar suelo',
  ]) {
    test(
      '11: el servidor no puede $attack revisiones en la aprobación',
      () async {
        aritz.keyring = SurpriseKeyring([
          SurpriseKey(
            personId: 'nora',
            epoch: 1,
            bytes: List.filled(32, 42),
            audience: const ['aritz-phone'],
          ),
        ]);
        final (host, guest, _, _) = await toCodes();
        guest.confirmCode();
        await host.confirm(confirmedPersonId: 'leo');
        worker.tamper = (method, uri, response) {
          if (uri.path.endsWith('/result') && response.status == 200) {
            final json = response.json();
            final package = Map<String, Object?>.from(json['package'] as Map);
            final slots = Map<String, Object?>.from(
              package['slotFloors'] as Map,
            );
            expect(slots, isNotEmpty);
            switch (attack) {
              case 'quitar':
                package['slotFloors'] = <String, Object?>{};
              case 'bajar':
                package['slotFloors'] = {for (final k in slots.keys) k: 0};
              case 'subir':
                package['slotFloors'] = {for (final k in slots.keys) k: 999999};
              case 'sustituir clave':
                final key = Map<String, Object?>.from(
                  (package['familyKeyPackages'] as List).single as Map,
                );
                package['familyKeyPackages'] = [
                  {...key, 'e': (key['e'] as int) + 1},
                ];
              case 'sin firma':
                package.remove('sig');
              case 'bajar suelo':
                package['minVersion'] = 1;
              case 'quitar suelo':
                package.remove('minVersion');
            }
            return SyncResponse(
              response.status,
              response.headers,
              Uint8List.fromList(
                utf8.encode(jsonEncode({...json, 'package': package})),
              ),
            );
          }
          return response;
        };
        await expectLater(guest.finish(), throwsA(isA<PairingException>()));
      },
    );
  }

  test('ronda 2: bajar solo minVersion y servir un común antiguo válido '
      'no rebaja el suelo firmado', () async {
    SyncResponse? old;
    client = SyncV2Client(
      base: client.base,
      sendRequest: (method, uri, {body, headers = const {}}) async {
        if (uri.path.endsWith('/approve')) {
          // Instantánea real anterior a la aprobación: ya tiene los avales.
          old = await worker.send(
            'GET',
            uri.replace(path: '/v2/lists/$kV2Sync'),
            headers: {'Authorization': aritz.auth.bearer},
          );
        }
        return worker.send(method, uri, body: body, headers: headers);
      },
    );
    final (host, guest, _, _) = await toCodes();
    guest.confirmCode();
    await host.confirm(confirmedPersonId: 'leo');
    final snapshot = (await client.getList(aritz.auth) as V2GetOk).snapshot;
    final stale = Map<String, Object?>.from(old!.json());
    final oldVersion = stale['version'] as int;
    expect(oldVersion, lessThan(snapshot.version));
    worker.tamper = (method, uri, response) {
      if (uri.path.endsWith('/result') && response.status == 200) {
        final json = response.json();
        // Conservar todos los bytes del paquete firmado.
        return SyncResponse(
          200,
          response.headers,
          Uint8List.fromList(
            utf8.encode(jsonEncode({...json, 'minVersion': oldVersion})),
          ),
        );
      }
      if (method == 'GET' &&
          uri.path.endsWith(kV2Sync) &&
          response.status == 200) {
        return SyncResponse(200, {
          ...response.headers,
          'etag': '"$oldVersion"',
        }, Uint8List.fromList(utf8.encode(jsonEncode(stale))));
      }
      return response;
    };
    // B7: el invitado parte del checkpoint con el suelo firmado (no del
    // `minVersion` del servidor) y su primera vuelta rechaza lo viejo.
    final joined = (await guest.finish())!;
    expect(joined.minVersion, greaterThan(oldVersion));
    expect(joined.snapshot.version, joined.minVersion);
    final leo = await MemoryV2Phone.create(
      'leo-phone',
      'leo',
      2,
      familyKey: joined.familyKey,
      doc: joined.common,
    );
    leo
      ..reg = joined.registry
      ..state = leo.state.copyWith(created: true, version: joined.minVersion);
    await expectLater(
      leo.engine(client).sync(),
      throwsA(isA<V2RollbackException>()),
    );
  });

  test('ataque: un servidor que sustituye la respuesta del invitado no '
      'consigue el mismo código', () async {
    final host = await PairingV2Host.start(
      transport: client,
      local: aritz,
      lock: lock,
    );
    final guest = await PairingV2Guest.open(
      transport: client,
      inviteId: host.inviteId,
      keys: await _keys(2),
      deviceIdFor: (_, _) => 'leo-phone',
    );
    // Un intruso prepara su respuesta a la misma oferta.
    final intruder = await joinPairing(
      offer: guest.offer,
      keys: await _keys(9),
      deviceId: 'leo-phone',
      personId: 'leo',
      inviteId: host.inviteId,
    );
    worker.tamper = (method, uri, r) {
      if (method == 'GET' &&
          uri.path.contains('/invites/') &&
          r.status == 200) {
        final json = r.json();
        if (json['answer'] != null) {
          return SyncResponse(
            200,
            r.headers,
            Uint8List.fromList(
              utf8.encode(
                jsonEncode({...json, 'answer': intruder.answer.toJson()}),
              ),
            ),
          );
        }
      }
      return r;
    };
    await guest.answer(personId: 'leo');
    final hostCode = (await host.poll())!.code;
    final guestCode = (await guest.code())!;
    expect(hostCode, isNot(guestCode));
  });

  test('ataque: una revelación cambiada no casa con el compromiso', () async {
    final host = await PairingV2Host.start(
      transport: client,
      local: aritz,
      lock: lock,
    );
    final guest = await PairingV2Guest.open(
      transport: client,
      inviteId: host.inviteId,
      keys: await _keys(2),
      deviceIdFor: (_, _) => 'leo-phone',
    );
    await guest.answer(personId: 'leo');
    await host.poll();
    worker.tamper = (method, uri, r) => uri.path.endsWith('/result')
        ? SyncResponse(
            202,
            r.headers,
            Uint8List.fromList(
              utf8.encode(
                jsonEncode({
                  'status': 'pending',
                  'reveal': {
                    'v': 2,
                    'n': encodeBase64Url(List<int>.filled(32, 1)),
                  },
                }),
              ),
            ),
          )
        : r;
    await expectLater(guest.code(), throwsA(isA<PairingException>()));
  });

  test('N2 y 1.0.6: ningún móvil entra sin persona, ni a propósito', () async {
    final host = await PairingV2Host.start(
      transport: client,
      local: aritz,
      lock: lock,
    );
    final guest = await PairingV2Guest.open(
      transport: client,
      inviteId: host.inviteId,
      keys: await _keys(2),
      deviceIdFor: (_, _) => 'leo-phone',
    );
    await expectLater(guest.answer(), throwsA(isA<PairingException>()));
    await guest.answer(withoutPerson: true);
    // El anfitrión no acepta la respuesta y borra la invitación.
    await expectLater(host.poll(), throwsA(isA<PairingException>()));
    expect(worker.devicesOf(kV2Sync).keys, isNot(contains('leo-phone')));
  });

  test('ataque (hallazgo 3): el anfitrión no avala la persona del invitado '
      'sin confirmarla aparte, ni una que no existe o se ha borrado', () async {
    // Sin confirmar la persona (o confirmando otra), no entra.
    final (host, guest, _, _) = await toCodes();
    guest.confirmCode();
    await expectLater(host.confirm(), throwsA(isA<PairingException>()));
    await expectLater(
      host.confirm(confirmedPersonId: 'nora'),
      throwsA(isA<PairingException>()),
    );
    expect(worker.devicesOf(kV2Sync).keys, isNot(contains('leo-phone')));
    // Una persona que este móvil no conoce: ni se revela el código, y la
    // invitación se borra.
    final unknown = await PairingV2Host.start(
      transport: client,
      local: aritz,
      lock: lock,
    );
    final stranger = await PairingV2Guest.open(
      transport: client,
      inviteId: unknown.inviteId,
      keys: await _keys(3),
      deviceIdFor: (_, _) => 'otro-phone',
    );
    await stranger.answer(personId: 'fantasma');
    await expectLater(unknown.poll(), throwsA(isA<PairingException>()));
    await expectLater(stranger.code(), throwsA(isA<InviteGoneException>()));
    // Una persona que existía al responder pero se borra antes de aprobar.
    final (hostB, guestB, _, _) = await toCodes(person: 'nora');
    guestB.confirmCode();
    aritz.doc = aritz.doc.delete(aritz.clock, 'recipients', 'nora');
    await expectLater(
      hostB.confirm(confirmedPersonId: 'nora'),
      throwsA(isA<PairingException>()),
    );
    expect(worker.devicesOf(kV2Sync).keys, isNot(contains('leo-phone')));
  });

  test('B7 (antes B4): tras el corte al formato 2, el anfitrión ya no sella '
      'la clave de la familia en v3: entrega el paquete v4', () async {
    aritz.enableCommonV2();
    final (host, guest, _, _) = await toCodes();
    guest.confirmCode();
    await host.confirm(confirmedPersonId: 'leo');
    final got = await client.pollInviteResult(
      host.inviteId,
      credential: (await _keys(2)).serviceCredential,
    ) as V2InviteApproved;
    final packages = got.package['familyKeyPackages'] as List;
    expect(packages, isNotEmpty);
    expect(packages.every((p) => (p as Map)['v'] == 4), isTrue);
    expect(got.package['minCommonFormat'], 2);
    final joined = (await guest.finish())!;
    expect(joined.commonFormat, 2);
    expect(joined.commonKeys, isNotNull);
    final view = await aritz.view();
    expect(
      () => KeyBundle.sealFamilyKey(
        sender: aritz.keys,
        view: view,
        toDevice: 'leo-phone',
        epoch: 1,
        familyKey: aritz.familyKey,
        commonFormatV2: true,
      ),
      throwsA(isA<KeyBundleException>()),
    );
  });

  test('«No coinciden»: cancelar borra la invitación', () async {
    final (host, guest, _, _) = await toCodes();
    await host.cancel();
    guest.confirmCode();
    await expectLater(guest.finish(), throwsA(isA<InviteGoneException>()));
    expect(worker.devicesOf(kV2Sync).keys, ['aritz-phone']);
  });
}
