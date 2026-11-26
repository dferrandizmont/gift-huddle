// ADR 0010, fase 1: el corte de versión de 1.0.7 (deseos propios). Un 1.0.6 y
// un 1.0.7 ya no se emparejan (móvil ni web) y 1.0.6 rechaza los ficheros que
// escribe 1.0.7 antes de fusionar. Lo «1.0.6» se simula con las constantes y
// los JSON de antes (sin `wp`, aprobación v4, versión exterior 1).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/device_keys.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/exchange_file.dart';
import 'package:regalos/features/sync/application/common_v2_cutover.dart'
    show kCommonFormatLatest;
import 'package:regalos/core/sync/pairing_v2.dart';
import 'package:regalos/features/sync/application/exchange_v2.dart';
import 'package:regalos/features/sync/application/pairing_v2_flow.dart';
import 'package:regalos/features/sync/application/v2_family_lock.dart';
import 'package:regalos/features/sync/data/sync_transport_common.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';

import '../helpers/fake_worker_v2.dart';
import 'protected_harness.dart';
import 'v2_harness.dart';

// ------------------------------------------------------------ helpers

Map<String, Object?> _rt(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

/// Lo que mandaría 1.0.6: el mismo JSON sin la capacidad ni la firma (y una
/// oferta, de versión 2).
Map<String, Object?> _old(Map<String, Object?> json) {
  final out = _rt(json)
    ..remove(kWishProtocolField)
    ..remove(kPairingSignatureField);
  if (out.containsKey('host')) out['v'] = kSyncProtocolV2;
  return out;
}

/// El lector de ofertas de 1.0.6: solo la versión 2.
bool _reader106AcceptsOffer(Map<String, Object?> json) =>
    json['v'] == kSyncProtocolV2;

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

const _people = {'aritz', 'leo', 'nora'};

Matcher get _outdated => throwsA(isA<PairingGuestOutdatedException>());
Matcher get _mismatch => throwsA(isA<PairingV2VersionMismatchException>());

void main() {
  // ----------------------------------------------- núcleo: oferta/respuesta
  group('capacidad en la oferta y la respuesta', () {
    late Phone aritz;
    late Phone leo;
    late DeviceRegistry registry;

    setUp(() async {
      aritz = await Phone.create('aritz-phone', 'aritz', 1);
      leo = await Phone.create('leo-phone', 'leo', 2);
      registry = await DeviceRegistry.empty(kListId).withRecord(
        await DeviceRecord.create(
          keys: aritz.keys,
          listId: kListId,
          deviceId: aritz.id,
          personId: 'aritz',
        ),
      );
    });

    Future<PairingHost> host({bool web = false}) async {
      final view = await registry.viewFor(
        me: aritz.id,
        mySigningKey: aritz.keys.publicKeys.signing,
        livePeople: _people,
      );
      if (!web) {
        final session = PairingHost.start(registry, view);
        await session.signOffer(aritz.keys);
        return session;
      }
      // El QR web fija la huella de las claves de la web (el invitado).
      final inviteId = encodeBase64Url(List<int>.filled(16, 5));
      final session = PairingHost.start(
        registry,
        view,
        expectWeb: true,
        inviteId: inviteId,
        guestPerson: 'leo',
        expectedFingerprint: webPairingFingerprint(
          inviteId,
          leo.keys.publicKeys.signing,
          leo.keys.publicKeys.agreement,
        ),
      );
      await session.signOffer(aritz.keys);
      return session;
    }

    Future<PairingJoin> join(
      PairingOffer offer, {
      DeviceKind kind = DeviceKind.mobile,
    }) => joinPairing(
      offer: offer,
      keys: leo.keys,
      deviceId: 'leo-phone',
      personId: 'leo',
      kind: kind,
      // La web conoce la invitación por el QR.
      inviteId: kind == DeviceKind.web
          ? encodeBase64Url(List<int>.filled(16, 5))
          : null,
    );

    test('1.0.7 lleva la capacidad en los dos JSON', () async {
      final session = await host();
      final offer = _rt(session.offer.toJson());
      expect(offer[kWishProtocolField], kWishProtocol);
      expect(offer['v'], kPairingOfferVersion);
      expect(offer[kPairingSignatureField], isA<String>());
      final joined = await join(await PairingOffer.fromJson(offer));
      final answer = _rt(joined.answer.toJson());
      expect(answer[kWishProtocolField], kWishProtocol);
      expect(answer[kPairingSignatureField], isA<String>());
    });

    test('la oferta nueva lleva una versión que el lector de 1.0.6 rechaza '
        'antes de responder', () async {
      final session = await host();
      final json = _rt(session.offer.toJson());
      expect(_reader106AcceptsOffer(json), isFalse);
      expect(_reader106AcceptsOffer(_old(json)), isTrue);
      // 1.0.7 lee las dos, pero la antigua ya no vale para responder.
      expect((await PairingOffer.fromJson(_old(json))).wishProtocol, isNull);
    });

    test('la oferta firmada: cualquier cambio (marca, capacidad, compromiso, '
        'ficha) o quitar la firma se rechaza al leerla', () async {
      final session = await host();
      final json = _rt(session.offer.toJson());
      Object other(String key) => key == 'c'
          ? encodeBase64Url(List<int>.filled(32, 9))
          : key == 'wp'
          ? 2
          : 1;
      for (final bad in <Map<String, Object?>>[
        {...json, kWishProtocolField: other('wp')},
        {...json, kHostPicksPersonField: other('hp')},
        {...json, 'c': other('c')},
        {...json}..remove(kPairingSignatureField),
        {...json, kPairingSignatureField: 'AAAA'},
        {...json}..remove(kWishProtocolField),
        // Una oferta de otra invitación del mismo anfitrión.
        {
          ...json,
          kPairingSignatureField: _rt(
            (await host()).offer.toJson(),
          )[kPairingSignatureField],
        },
      ]) {
        await expectLater(
          PairingOffer.fromJson(bad),
          throwsA(isA<PairingException>()),
        );
      }
    });

    test('un anfitrión 1.0.6 (oferta sin capacidad) no vale para un invitado '
        'móvil ni web: nada se responde', () async {
      final session = await host();
      for (final broken in [
        _old(session.offer.toJson()),
        // Una oferta antigua a la que alguien añade la capacidad: sigue
        // siendo de versión 2, sin firma, y no vale.
        {..._old(session.offer.toJson()), kWishProtocolField: 1},
      ]) {
        final offer = await PairingOffer.fromJson(broken);
        expect(offer.wishProtocol, isNot(kWishProtocol));
        expect(
          () => PairingV2Guest.forWeb(
            transport: FakeWorkerV2().client(),
            inviteId: 'invite-1',
            offer: offer,
            keys: leo.keys,
            deviceId: 'leo-phone',
          ),
          _mismatch,
        );
      }
    });

    test('un invitado 1.0.6 (respuesta sin capacidad, alterada o '
        'desconocida) no gasta la respuesta del anfitrión móvil', () async {
      final session = await host();
      final offer = await PairingOffer.fromJson(_rt(session.offer.toJson()));
      final joined = await join(offer);
      final good = _rt(joined.answer.toJson());
      for (final broken in [
        _old(good),
        {...good, kWishProtocolField: 2},
        {...good, kWishProtocolField: 0},
        {...good, kWishProtocolField: '1'},
        {...good, kWishProtocolField: null},
      ]) {
        await expectLater(
          session.receive(PairingAnswer.fromJson(broken)),
          _outdated,
        );
        expect(session.answer, isNull, reason: 'no se gasta la respuesta');
      }
      // Capacidad añadida a una respuesta 1.0.6 (sin firma) o con una firma
      // que no es del invitado, de otra invitación o de otros campos.
      final other = await join(
        await PairingOffer.fromJson(_rt((await host()).offer.toJson())),
      );
      for (final forged in [
        {..._old(good), kWishProtocolField: 1},
        {...good}..remove(kPairingSignatureField),
        {...good, kPairingSignatureField: 'AAAA'},
        {
          ...good,
          kPairingSignatureField: _rt(
            other.answer.toJson(),
          )[kPairingSignatureField],
        },
        {
          ...good,
          kHostPicksPersonField: 1,
          'gn': _rt(other.answer.toJson())['gn'],
        },
      ]) {
        await expectLater(
          session.receive(PairingAnswer.fromJson(forged)),
          throwsA(
            isA<PairingException>().having(
              (e) => e is PairingGuestOutdatedException,
              'outdated',
              isFalse,
            ),
          ),
        );
        expect(session.answer, isNull, reason: 'no se gasta la respuesta');
      }
      // La buena sigue valiendo.
      await session.receive(PairingAnswer.fromJson(good));
      expect(session.answer, isNotNull);
    });

    test('lo mismo con una web con la aplicación antigua en caché', () async {
      final session = await host(web: true);
      final offer = await PairingOffer.fromJson(_rt(session.offer.toJson()));
      final joined = await join(offer, kind: DeviceKind.web);
      final good = _rt(joined.answer.toJson());
      await expectLater(
        session.receive(PairingAnswer.fromJson(_old(good))),
        _outdated,
      );
      await expectLater(
        session.receive(
          PairingAnswer.fromJson({...good, kWishProtocolField: 2}),
        ),
        _outdated,
      );
      expect(session.answer, isNull);
      await session.receive(PairingAnswer.fromJson(good));
      expect(session.answer, isNotNull);
    });

    test('la respuesta firmada liga la invitación y el verificador de la '
        'credencial: otra invitación o otro verificador no valen', () async {
      final session = await host();
      session.bindInvite('invite-A');
      final offer = await PairingOffer.fromJson(_rt(session.offer.toJson()));
      final verifier = List<int>.filled(32, 4);
      Future<PairingAnswer> answerFor(String? invite, List<int>? v) async =>
          PairingAnswer.fromJson(
            _rt(
              (await joinPairing(
                offer: offer,
                keys: leo.keys,
                deviceId: 'leo-phone',
                personId: 'leo',
                inviteId: invite,
                verifier: v,
              )).answer.toJson(),
            ),
          );
      // Una respuesta obtenida con otro id de invitación, o sin id.
      for (final bad in [
        await answerFor('invite-B', verifier),
        await answerFor(null, verifier),
      ]) {
        await expectLater(
          session.receive(bad),
          throwsA(
            isA<PairingException>().having(
              (e) => e is PairingGuestOutdatedException,
              'outdated',
              isFalse,
            ),
          ),
        );
        expect(session.answer, isNull);
      }
      // El verificador cambiado en la respuesta (el servidor lo sustituye).
      final good = _rt((await answerFor('invite-A', verifier)).toJson());
      expect(good[kPairingVerifierField], encodeBase64Url(verifier));
      for (final bad in [
        {...good, kPairingVerifierField: encodeBase64Url(List.filled(32, 5))},
        {...good}..remove(kPairingVerifierField),
      ]) {
        await expectLater(
          session.receive(PairingAnswer.fromJson(bad)),
          throwsA(isA<PairingException>()),
        );
        expect(session.answer, isNull);
      }
      await session.receive(PairingAnswer.fromJson(good));
      expect(session.answer, isNotNull);
    });

    test('el resumen del intercambio firmado liga la capacidad de los dos '
        'lados', () async {
      final session = await host();
      final offer = await PairingOffer.fromJson(_rt(session.offer.toJson()));
      final joined = await join(offer);
      final good = _rt(joined.answer.toJson());
      final nonce = List<int>.filled(32, 7);
      String hash(PairingOffer o, PairingAnswer a) => pairingTranscriptHash(
        inviteId: 'invite-1',
        offer: o,
        answer: a,
        hostNonce: nonce,
      );
      final base = hash(offer, PairingAnswer.fromJson(good));
      expect(
        hash(offer, PairingAnswer.fromJson({...good, kWishProtocolField: 2})),
        isNot(base),
      );
      expect(hash(offer, PairingAnswer.fromJson(_old(good))), isNot(base));
      final oldOffer = await PairingOffer.fromJson(
        _old(session.offer.toJson()),
      );
      expect(hash(oldOffer, PairingAnswer.fromJson(good)), isNot(base));
    });
  });

  // ------------------------------------------------ flujo completo (Worker)
  group('emparejamiento contra el Worker falso', () {
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
        ..addGift('g1', 'leo', 'Libro');
    });

    Future<PairingV2Host> startHost() => PairingV2Host.start(
      transport: client,
      local: aritz,
      lock: lock,
      guestPerson: 'leo',
      hostPicksPerson: true,
    );

    Future<PairingV2Guest> openGuest(String inviteId) async =>
        PairingV2Guest.open(
          transport: client,
          inviteId: inviteId,
          keys: await _keys(2),
          deviceIdFor: (_, _) => 'leo-phone',
        );

    bool isInvite(String method, Uri uri, String id) =>
        method == 'GET' && uri.path.contains('/invites/$id');

    test('1.0.7 con 1.0.7: aprobación v5 con la capacidad firmada', () async {
      final host = await startHost();
      final guest = await openGuest(host.inviteId);
      await guest.answer(personId: 'leo');
      final code = (await host.poll())!.code;
      expect(await guest.code(), code);
      guest.confirmCode();
      await host.confirm(confirmedPersonId: 'leo');
      final got = await client.pollInviteResult(
        host.inviteId,
        credential: (await _keys(2)).serviceCredential,
      ) as V2InviteApproved;
      expect(kPairingPackageVersion, 5);
      expect(got.package['v'], 5);
      expect(got.package[kWishProtocolField], kWishProtocol);
      expect(await guest.finish(), isNotNull);
    });

    test('anfitrión 1.0.6 y invitado 1.0.7: sin capacidad en la oferta no '
        'hay respuesta ni credencial', () async {
      final host = await startHost();
      worker.tamper = (method, uri, r) {
        if (isInvite(method, uri, host.inviteId) && r.status == 200) {
          final body = r.json();
          return _json(200, {
            ...body,
            'offer': _old((body['offer'] as Map).cast<String, Object?>()),
          });
        }
        return r;
      };
      await expectLater(openGuest(host.inviteId), _mismatch);
      expect(worker.devicesOf(kV2Sync).keys, isNot(contains('leo-phone')));
    });

    test('invitado 1.0.6 y anfitrión 1.0.7: no se gasta la respuesta ni se '
        'registra ninguna credencial', () async {
      final host = await startHost();
      final guest = await openGuest(host.inviteId);
      worker.tamper = (method, uri, r) {
        if (isInvite(method, uri, host.inviteId) &&
            r.status == 200 &&
            r.json()['answer'] != null) {
          final body = r.json();
          return _json(200, {
            ...body,
            'answer': _old((body['answer'] as Map).cast<String, Object?>()),
          });
        }
        return r;
      };
      await guest.answer(personId: 'leo');
      await expectLater(host.poll(), _outdated);
      expect(worker.devicesOf(kV2Sync).keys, isNot(contains('leo-phone')));
    });

    test('la misma invitación: el lector de 1.0.6 rechaza la oferta nueva '
        'antes de responder y después entra un invitado 1.0.7', () async {
      final host = await startHost();
      final raw = await client.getOffer(host.inviteId);
      final json = (raw.offer! as Map).cast<String, Object?>();
      expect(_reader106AcceptsOffer(json), isFalse);
      // Nada se respondió: la invitación sigue sin respuesta.
      expect(await host.poll(), isNull);
      final guest = await openGuest(host.inviteId);
      await guest.answer(personId: 'leo');
      final code = (await host.poll())!.code;
      expect(await guest.code(), code);
    });

    test('una oferta alterada por el servidor (capacidad, marca o '
        'compromiso) no se responde ni crea credencial', () async {
      final host = await startHost();
      for (final change in <String, Object?>{
        kWishProtocolField: 2,
        kHostPicksPersonField: 0,
        'c': encodeBase64Url(List<int>.filled(32, 9)),
      }.entries) {
        worker.tamper = (method, uri, r) {
          if (isInvite(method, uri, host.inviteId) && r.status == 200) {
            final body = r.json();
            return _json(200, {
              ...body,
              'offer': {
                ...(body['offer'] as Map).cast<String, Object?>(),
                change.key: change.value,
              },
            });
          }
          return r;
        };
        await expectLater(
          openGuest(host.inviteId),
          throwsA(isA<PairingException>()),
        );
      }
      expect(worker.devicesOf(kV2Sync).keys, isNot(contains('leo-phone')));
    });

    test(
      'un servidor que añade la capacidad a una respuesta 1.0.6: el '
      'anfitrión la rechaza antes de avalar nada y no toca lo suyo',
      () async {
        final host = await startHost();
        final guest = await openGuest(host.inviteId);
        final registryBefore = jsonEncode(aritz.reg.toJson());
        worker.tamper = (method, uri, r) {
          if (isInvite(method, uri, host.inviteId) &&
              r.status == 200 &&
              r.json()['answer'] != null) {
            final body = r.json();
            return _json(200, {
              ...body,
              'answer': {
                ..._old((body['answer'] as Map).cast<String, Object?>()),
                kWishProtocolField: 1,
              },
            });
          }
          return r;
        };
        await guest.answer(personId: 'leo');
        await expectLater(
          host.poll(),
          throwsA(
            isA<PairingException>().having(
              (e) => e is PairingGuestOutdatedException,
              'outdated',
              isFalse,
            ),
          ),
        );
        expect(jsonEncode(aritz.reg.toJson()), registryBefore);
        expect(worker.devicesOf(kV2Sync).keys, isNot(contains('leo-phone')));
        worker.tamper = null;
        // La invitación se borró: ni respuesta, ni aprobación, ni checkpoint.
        expect(
          await client.pollInviteResult(
            host.inviteId,
            credential: (await _keys(2)).serviceCredential,
          ),
          isNot(isA<V2InviteApproved>()),
        );
      },
    );

    test(
      'la aprobación v5 se firma con el dominio v5, fijado aparte',
      () async {
        final host = await startHost();
        final guest = await openGuest(host.inviteId);
        await guest.answer(personId: 'leo');
        await host.poll();
        await guest.code();
        guest.confirmCode();
        await host.confirm(confirmedPersonId: 'leo');
        final got = await client.pollInviteResult(
          host.inviteId,
          credential: (await _keys(2)).serviceCredential,
        ) as V2InviteApproved;
        final package = got.package;
        final signature = decodeBase64Url(package['sig']! as String);
        List<int> bytes(String domain) => [
          ...utf8.encode(domain),
          0,
          ...utf8.encode(
            canonicalJsonText({
              for (final e in package.entries)
                if (e.key != 'sig') e.key: e.value,
            }),
          ),
        ];
        final signing = aritz.keys.publicKeys.signing;
        expect(
          await verifyDeviceSignature(
            message: bytes('gift-huddle-pairing-approval-v5'),
            signature: signature,
            signingPublicKey: signing,
          ),
          isTrue,
        );
        expect(
          await verifyDeviceSignature(
            message: bytes('gift-huddle-pairing-approval-v4'),
            signature: signature,
            signingPublicKey: signing,
          ),
          isFalse,
        );
      },
    );

    for (final change in <String, Object?>{
      'v4 (1.0.6)': 4,
      'sin capacidad': null,
      'capacidad alterada': 2,
    }.entries) {
      test('aprobación ${change.key}: el invitado no instala nada', () async {
        final host = await startHost();
        final guest = await openGuest(host.inviteId);
        await guest.answer(personId: 'leo');
        await host.poll();
        await guest.code();
        guest.confirmCode();
        await host.confirm(confirmedPersonId: 'leo');
        worker.tamper = (method, uri, r) {
          if (uri.path == '/v2/invites/${host.inviteId}/result' &&
              r.status == 200) {
            final body = r.json();
            final package = <String, Object?>{
              ...(body['package'] as Map).cast<String, Object?>(),
            };
            if (change.value == 4) {
              package['v'] = 4;
              package.remove(kWishProtocolField);
            } else if (change.value == null) {
              package.remove(kWishProtocolField);
            } else {
              package[kWishProtocolField] = change.value;
            }
            return _json(200, {...body, 'package': package});
          }
          return r;
        };
        await expectLater(
          guest.finish(),
          throwsA(
            change.value == 4
                ? isA<PairingV2VersionMismatchException>()
                : isA<PairingException>(),
          ),
        );
      });
    }
  });

  // --------------------------------------------------------------- ficheros
  group('ficheros con versión exterior', () {
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
    }

    /// El fichero tal como lo escribía 1.0.6: versión 1 en el byte y en la
    /// cabecera.
    Uint8List asV106(Uint8List bytes) {
      final file = ExchangeFile.parse(bytes);
      final header = utf8.encode(
        jsonEncode({
          'kp': file.packages,
          'l': file.listId,
          'rec': file.records,
          'sid': file.syncId,
          'v': 1,
        }),
      );
      return Uint8List.fromList([
        0x52,
        0x58,
        1,
        ...(ByteData(4)..setUint32(0, header.length)).buffer.asUint8List(),
        ...header,
        ...file.common,
      ]);
    }

    /// El lector de 1.0.6: la comprobación exterior de `ExchangeFile.parse`.
    bool reader106Accepts(Uint8List bytes) => bytes[2] == 1;

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
      nora = await MemoryV2Phone.create(
        'nora-phone',
        'nora',
        3,
        familyKey: key,
      );
      aritz
        ..addPerson('aritz', 'Aritz')
        ..addPerson('leo', 'Leo')
        ..addPerson('nora', 'Nora')
        ..addGift('g-aritz', 'leo', 'Libro');
    });

    test('el intercambio de 1.0.7 lleva versión 2 y 1.0.6 lo rechaza; el de '
        '1.0.6 sigue leyéndose', () async {
      await cut();
      leo.addGift('g-leo', 'aritz', 'Puzle');
      final bytes = await ExchangeV2(leo).export();
      expect(kExchangeFileVersion, 2);
      expect(bytes[2], 2);
      expect(reader106Accepts(bytes), isFalse);
      // La cabecera también lleva la versión.
      expect(ExchangeFile.parse(bytes).syncId, kV2Sync);
      // Lo de 1.0.6 se lee y fusiona.
      final legacy = asV106(bytes);
      expect(reader106Accepts(legacy), isTrue);
      final opened = await ExchangeV2(aritz).receive(legacy, nowMillis: 1000);
      await aritz.mergeCommon(opened.doc, fromNode: opened.fromNode);
      expect(aritz.giftTitles, contains('Puzle'));
    });

    test('byte y cabecera tienen que coincidir y no se admite una versión '
        'desconocida; el rechazo no toca la copia local', () async {
      await cut();
      leo.addGift('g-leo', 'aritz', 'Puzle');
      final bytes = await ExchangeV2(leo).export();
      final before = aritz.giftTitles.toSet();
      final stamp = aritz.doc.maxStamp?.pack();
      final registry = jsonEncode(aritz.reg.toJson());
      // Byte 1 con cabecera 2 (cabecera distinta de la versión exterior).
      final mixed = Uint8List.fromList(bytes)..[2] = 1;
      for (final bad in [
        mixed,
        Uint8List.fromList(bytes)..[2] = 3,
        Uint8List.fromList(bytes)..[2] = 0,
      ]) {
        await expectLater(
          ExchangeV2(aritz).receive(bad, nowMillis: 1000),
          throwsA(isA<EnvelopeFormatException>()),
        );
      }
      expect(aritz.giftTitles.toSet(), before);
      expect(aritz.doc.maxStamp?.pack(), stamp);
      expect(jsonEncode(aritz.reg.toJson()), registry);
    });

    test('sobre clásico: 1.0.7 escribe la versión exterior 3 y el lector de '
        '1.0.6 (peekHeader/open sin la marca) lo rechaza antes de '
        'fusionar; 1.0.7 lee el 1 y el 3', () async {
      final doc = <String, Object?>{'k': 1};
      Future<Uint8List> sealWith(int version) => seal(
        doc: doc,
        listId: 'list-1',
        fromNode: 'aritz-phone',
        at: '',
        key: key,
        version: version,
      );
      final v1 = await sealWith(1);
      final v3 = await sealWith(kFileEnvelopeVersion);
      expect(v1[2], 1);
      expect(v3[2], kFileEnvelopeVersion);
      expect(kFileEnvelopeVersion, isNot(2), reason: '2 es el sobre firmado');
      // 1.0.6 (así lee la sincronización y 1.0.6 los ficheros).
      expect(peekHeader(v1).version, 1);
      expect(() => peekHeader(v3), throwsA(isA<EnvelopeFormatException>()));
      await expectLater(
        open(v3, key: key, expectedListId: 'list-1'),
        throwsA(isA<EnvelopeFormatException>()),
      );
      // 1.0.7 lee los ficheros viejos y los nuevos.
      expect(peekHeader(v1, acceptFileVersion: true).version, 1);
      expect(peekHeader(v3, acceptFileVersion: true).version, 3);
      for (final bytes in [v1, v3]) {
        final opened = await open(
          bytes,
          key: key,
          expectedListId: 'list-1',
          acceptFileVersion: true,
        );
        expect(opened.doc, doc);
      }
      // El byte y la cabecera tienen que coincidir.
      final mixed = Uint8List.fromList(v3)..[2] = 1;
      expect(
        () => peekHeader(mixed, acceptFileVersion: true),
        throwsA(isA<EnvelopeFormatException>()),
      );
      // Tras el corte, un sobre clásico nuevo también es «de siempre».
      expect(isLegacyEnvelope(v1), isTrue);
      expect(isLegacyEnvelope(v3), isTrue);
    });
  });
}
