// Emparejamiento v2 y formato de la migración v1 → v2 (ADR 0004, fase 2a;
// requisito 22 de la revisión de seguridad de la fase 1 (segunda pasada)).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/envelope.dart'
    show FamilyKey, encodeBase64Url;
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/pairing_v2.dart';

import 'protected_harness.dart';

const _people = {'aritz', 'leo', 'nora'};

Future<RegistryView> _view(DeviceRegistry registry, Phone me) =>
    registry.viewFor(
      me: me.id,
      mySigningKey: me.keys.publicKeys.signing,
      livePeople: _people,
    );

void main() {
  late Phone aritz;
  late Phone leo;
  late Phone nora;
  late DeviceRegistry host;

  setUp(() async {
    aritz = await Phone.create('aritz-phone', 'aritz', 1);
    leo = await Phone.create('leo-phone', 'leo', 2);
    nora = await Phone.create('nora-phone', 'nora', 3);
    host = await DeviceRegistry.empty(kListId).withRecord(
      await DeviceRecord.create(
        keys: aritz.keys,
        listId: kListId,
        deviceId: aritz.id,
        personId: 'aritz',
      ),
    );
  });

  /// El anfitrión empieza; la oferta viaja por JSON (QR).
  Future<(PairingHost, PairingOffer)> start(
    DeviceRegistry registry,
    Phone me,
  ) async {
    final session = PairingHost.start(registry, await _view(registry, me));
    return (
      session,
      await PairingOffer.fromJson(
        jsonDecode(jsonEncode(session.offer.toJson())),
      ),
    );
  }

  Future<PairingJoin> join(PairingOffer offer, Phone guest, {String? id}) =>
      joinPairing(
        offer: offer,
        keys: guest.keys,
        deviceId: id ?? guest.id,
        personId: guest.self,
      );

  /// El anfitrión recibe [answer] (por JSON) y la acepta.
  Future<RegistryChange> accept(
    DeviceRegistry registry,
    Phone me,
    PairingHost session,
    PairingAnswer answer,
  ) async {
    await session.receive(
      PairingAnswer.fromJson(jsonDecode(jsonEncode(answer.toJson()))),
    );
    return acceptPairing(
      registry: registry,
      view: await _view(registry, me),
      myKeys: me.keys,
      session: session,
      confirmedPersonId: answer.guest.personId,
    );
  }

  group('emparejamiento v2', () {
    test(
      'oferta, respuesta, revelación y aceptación: el mismo código en los '
      'dos y emparejados desde el registro, con claves persistentes',
      () async {
        expect((await _view(host, aritz)).paired, isFalse);
        final (session, offer) = await start(host, aritz);
        final joined = await join(offer, leo);
        // El invitado ya confía en el anfitrión (lo ha visto en persona).
        final guestView = await _view(joined.registry, leo);
        expect(guestView.paired, isTrue);
        expect(guestView.member('aritz-phone')!.personId, 'aritz');
        // El anfitrión recibe la respuesta y revela el nonce.
        final reveal = await session.receive(
          PairingAnswer.fromJson(
            jsonDecode(jsonEncode(joined.answer.toJson())),
          ),
        );
        final guestCode = joined.codeFor(
          PairingReveal.fromJson(jsonDecode(jsonEncode(reveal.toJson()))),
        );
        expect(session.code, guestCode);
        expect(guestCode, matches(r'^\d{6}$'));
        // Una persona compara los códigos y confirma, aparte, que el móvil es
        // de Leo (hallazgo 3): sin eso, o con otra persona, no se acepta.
        for (final wrong in [null, 'nora']) {
          await expectLater(
            acceptPairing(
              registry: host,
              view: await _view(host, aritz),
              myKeys: aritz.keys,
              session: session,
              confirmedPersonId: wrong,
            ),
            throwsA(isA<PairingException>()),
          );
        }
        // Ni aunque se confirme, si esa persona ya no existe en la familia.
        await expectLater(
          acceptPairing(
            registry: host,
            view: await host.viewFor(
              me: aritz.id,
              mySigningKey: aritz.keys.publicKeys.signing,
              livePeople: {'aritz', 'nora'},
            ),
            myKeys: aritz.keys,
            session: session,
            confirmedPersonId: 'leo',
          ),
          throwsA(isA<PairingException>()),
        );
        final change = await acceptPairing(
          registry: host,
          view: await _view(host, aritz),
          myKeys: aritz.keys,
          session: session,
          confirmedPersonId: 'leo',
        );
        expect(change.rotates, isFalse);
        final hostView = await _view(change.registry, aritz);
        expect(hostView.paired, isTrue);
        expect(
          hostView.member('leo-phone')!.agreementKey,
          leo.keys.publicKeys.agreement,
        );
        // Al fusionar, los dos ven lo mismo.
        final merged = await change.registry.merge(joined.registry);
        expect((await _view(merged, leo)).members, [
          'aritz-phone',
          'leo-phone',
        ]);
      },
    );

    test(
      'ataque (hallazgo 6): quien sustituye la respuesta del invitado '
      'elige su ficha sin conocer el nonce, así que el código no coincide',
      () async {
        final (session, offer) = await start(host, aritz);
        final real = await join(offer, leo);
        // Nora intercepta y manda su propia respuesta, con otra ficha «de Leo».
        final evil = await join(offer, Phone('leo-phone', 'leo', nora.keys));
        final reveal = await session.receive(evil.answer);
        final guestCode = real.codeFor(reveal);
        expect(session.code, isNot(guestCode));
        // Antes de la revelación el código no se puede calcular: con otro
        // nonce sale otro, así que no sirve probar fichas sin conexión.
        final other = PairingHost.start(host, await _view(host, aritz));
        await other.receive(evil.answer);
        expect(other.code, isNot(session.code));
        // Y ya revelado el nonce, el anfitrión no acepta otra respuesta.
        await expectLater(
          session.receive(real.answer),
          throwsA(isA<PairingException>()),
        );
      },
    );

    test('N5: el nonce del invitado entra en el código: con otro nonce del '
        'invitado y las mismas fichas sale otro código', () async {
      final (session, offer) = await start(host, aritz);
      final joined = await join(offer, leo);
      final json = jsonDecode(jsonEncode(joined.answer.toJson())) as Map;
      expect(json['gn'], isA<String>());
      final reveal = await session.receive(PairingAnswer.fromJson(json));
      expect(joined.codeFor(reveal), session.code);
      // Quien cambia el nonce del invitado (y nada más) cambia el código.
      final other = PairingHost.start(host, await _view(host, aritz));
      final tampered = {...json, 'gn': encodeBase64Url(List.filled(32, 7))};
      await other.receive(PairingAnswer.fromJson(tampered));
      final sameNonce = PairingAnswer.fromJson(json);
      expect(
        pairingCode(
          offer.host,
          sameNonce.guest,
          reveal.nonce,
          List.filled(32, 7),
        ),
        isNot(session.code),
      );
      // Sin nonce, o con uno corto, la respuesta no se lee.
      for (final bad in [
        {...json}..remove('gn'),
        {...json, 'gn': 'corto'},
      ]) {
        expect(
          () => PairingAnswer.fromJson(bad),
          throwsA(isA<PairingException>()),
        );
      }
    });

    test('ataque (N5): una respuesta rota no gasta la única respuesta del '
        'anfitrión; la buena entra después', () async {
      final (session, offer) = await start(host, aritz);
      final joined = await join(offer, leo);
      final good = joined.answer.toJson();
      for (final bad in <Map<String, Object?>>[
        // La ficha no casa con su firma.
        {
          ...good,
          'guest': {...good['guest']! as Map, 'p': 'nora'},
        },
        // El aval no lo firma el invitado.
        {
          ...good,
          'vouch': {...good['vouch']! as Map, 'sig': 'A' * 86},
        },
      ]) {
        await expectLater(
          session.receive(PairingAnswer.fromJson(jsonDecode(jsonEncode(bad)))),
          throwsA(isA<PairingException>()),
        );
        expect(session.answer, isNull);
      }
      // Un aval para otra oferta (otra ficha del anfitrión) tampoco la gasta.
      final changed = await changePerson(
        registry: host,
        view: await _view(host, aritz),
        myKeys: aritz.keys,
        personId: 'leo',
      );
      final newer = PairingHost.start(
        changed.registry,
        await _view(changed.registry, aritz),
      );
      await expectLater(
        newer.receive(joined.answer),
        throwsA(isA<PairingException>()),
      );
      expect(newer.answer, isNull);
      // Y la respuesta buena sigue entrando en la sesión original.
      final reveal = await session.receive(PairingAnswer.fromJson(good));
      expect(joined.codeFor(reveal), session.code);
    });

    test('N2: el invitado tiene que elegir persona o marcar a propósito que '
        'no la tiene, y el anfitrión tiene que aceptarlo así', () async {
      final (session, offer) = await start(host, aritz);
      await expectLater(
        joinPairing(
          offer: offer,
          keys: leo.keys,
          deviceId: leo.id,
          personId: null,
        ),
        throwsA(isA<PairingException>()),
      );
      final joined = await joinPairing(
        offer: offer,
        keys: leo.keys,
        deviceId: leo.id,
        personId: null,
        withoutPerson: true,
      );
      expect(joined.answer.withoutPerson, isTrue);
      // 1.0.6: el anfitrión no acepta ningún móvil sin persona, y la
      // respuesta rota no gasta la única que tiene.
      await expectLater(
        session.receive(joined.answer),
        throwsA(isA<PairingException>()),
      );
      expect(session.answer, isNull);
    });

    test('una revelación que no casa con el compromiso de la oferta se '
        'rechaza', () async {
      final (session, offer) = await start(host, aritz);
      final joined = await join(offer, leo);
      final otherSession = PairingHost.start(host, await _view(host, aritz));
      final wrong = await otherSession.receive(joined.answer);
      expect(() => joined.codeFor(wrong), throwsA(isA<PairingException>()));
      expect(
        () => PairingReveal.fromJson({'v': 2, 'n': 'corto'}),
        throwsA(isA<PairingException>()),
      );
      expect(() => session.code, throwsStateError);
      await expectLater(
        acceptPairing(
          registry: host,
          view: await _view(host, aritz),
          myKeys: aritz.keys,
          session: session,
        ),
        throwsA(isA<PairingException>()),
      );
    });

    test('ataque: una oferta con la ficha manipulada o sin compromiso no se '
        'acepta', () async {
      final json = PairingHost.start(
        host,
        await _view(host, aritz),
      ).offer.toJson();
      for (final bad in <Map<String, Object?>>[
        {
          ...json,
          'host': {...json['host']! as Map, 'p': 'nora'},
        },
        {'v': 1, 'host': json['host'], 'c': json['c']},
        {'v': 2, 'host': json['host']},
        {...json, 'c': 'A' * 10},
      ]) {
        await expectLater(
          PairingOffer.fromJson(bad),
          throwsA(isA<PairingException>()),
        );
      }
    });

    test('ataque: una respuesta con la ficha de otro, con un aval que no es '
        'para mí o con la persona cambiada no se acepta', () async {
      final (_, offer) = await start(host, aritz);
      final joined = await join(offer, leo);
      final good = joined.answer.toJson();
      Future<void> rejected(
        Map<String, Object?> json, {
        DeviceRegistry? registry,
      }) async {
        final on = registry ?? host;
        final session = PairingHost.start(on, await _view(on, aritz));
        // N5: lo roto ya lo rechaza [PairingHost.receive], sin gastar la
        // respuesta; lo que pase de ahí lo rechaza [acceptPairing].
        try {
          await session.receive(PairingAnswer.fromJson(json));
        } on PairingException {
          expect(session.answer, isNull);
          return;
        }
        await expectLater(
          acceptPairing(
            registry: on,
            view: await _view(on, aritz),
            myKeys: aritz.keys,
            session: session,
            confirmedPersonId: session.answer!.guest.personId,
          ),
          throwsA(isA<PairingException>()),
        );
      }

      // La persona cambiada: la firma de la ficha ya no vale.
      await rejected({
        ...good,
        'guest': {...good['guest']! as Map, 'p': 'aritz'},
      });
      // El aval no lo ha firmado el móvil nuevo.
      await rejected({
        ...good,
        'vouch': {...good['vouch']! as Map, 'sig': 'A' * 86},
      });
      // El aval es de otro móvil (Nora reenvía el de Leo con su ficha).
      final other = await join(offer, Phone('nora-phone', 'leo', nora.keys));
      await rejected({...good, 'guest': other.answer.guest.toJson()});
      // El aval es para una ficha vieja de este móvil.
      final changed = await changePerson(
        registry: host,
        view: await _view(host, aritz),
        myKeys: aritz.keys,
        personId: 'leo',
      );
      await rejected(good, registry: changed.registry);
    });

    test('ataque: un móvil nuevo con el id de uno que ya existe y otras '
        'claves no entra', () async {
      final (session, offer) = await start(host, aritz);
      final first = await join(offer, leo);
      final paired = (await accept(
        host,
        aritz,
        session,
        first.answer,
      )).registry;
      final (again, offer2) = await start(paired, aritz);
      final impostor = await join(offer2, Phone('leo-phone', 'leo', nora.keys));
      await expectLater(
        accept(paired, aritz, again, impostor.answer),
        throwsA(isA<PairingException>()),
      );
      await expectLater(
        join(offer, Phone('aritz-phone', 'nora', nora.keys)),
        throwsA(isA<PairingException>()),
      );
    });

    test('un revocado no vuelve a emparejarse con el mismo id', () async {
      final (session, offer) = await start(host, aritz);
      final joined = await join(offer, leo);
      var registry = (await accept(
        host,
        aritz,
        session,
        joined.answer,
      )).registry;
      registry = (await revokeDevice(
        registry: registry,
        view: await _view(registry, aritz),
        myKeys: aritz.keys,
        deviceId: leo.id,
      )).registry;
      final (again, offer2) = await start(registry, aritz);
      final back = await join(offer2, leo);
      await expectLater(
        accept(registry, aritz, again, back.answer),
        throwsA(isA<PairingException>()),
      );
    });
  });

  group('migración v1 → v2', () {
    late FamilyDoc v1;

    setUp(() {
      final clock = clockOf('aritz-phone', 100);
      v1 = commonWithPeople(clock)
          .set(clock, Collections.gifts, 'g1', giftFields('nora', 'Libro'));
    });

    test('el móvil que migra conserva todo, marca el protocolo, estrena '
        'clave y syncId y empieza un registro con solo su ficha', () async {
      final m = await migrateToV2(
        v1Doc: v1,
        clock: clockOf('aritz-phone', 200),
        keys: aritz.keys,
        deviceId: aritz.id,
        personId: 'aritz',
      );
      expect(syncProtocolOf(v1), 1);
      expect(syncProtocolOf(m.common), kSyncProtocolV2);
      expect(m.common.listId, v1.listId);
      expect(m.common.record(Collections.gifts, 'g1')!['title'], 'Libro');
      expect(m.identity.migratedFromV1, isTrue);
      expect(m.identity.syncId, hasLength(22));
      final again = await migrateToV2(
        v1Doc: v1,
        clock: clockOf('aritz-phone', 200),
        keys: aritz.keys,
        deviceId: aritz.id,
        personId: 'aritz',
      );
      expect(again.identity.syncId, isNot(m.identity.syncId));
      expect(again.familyKey.bytes, isNot(m.familyKey.bytes));
      final view = await _view(m.registry, aritz);
      expect(view.members, ['aritz-phone']);
      expect(view.paired, isFalse);
      final back = SyncIdentityV2.fromJson(
        jsonDecode(jsonEncode(m.identity.toJson())),
      );
      expect(back.syncId, m.identity.syncId);
      expect(back.migratedFromV1, isTrue);
    });

    test(
      'no hay degradación: migrar dos veces falla, una identidad v1 no '
      'se lee como v2 y un documento v1 no entra por la sincronización',
      () async {
        final m = await migrateToV2(
          v1Doc: v1,
          clock: clockOf('aritz-phone', 200),
          keys: aritz.keys,
          deviceId: aritz.id,
          personId: 'aritz',
        );
        await expectLater(
          migrateToV2(
            v1Doc: m.common,
            clock: clockOf('aritz-phone', 300),
            keys: aritz.keys,
            deviceId: aritz.id,
            personId: 'aritz',
          ),
          throwsStateError,
        );
        expect(
          () => SyncIdentityV2.fromJson({...m.identity.toJson(), 'v': 1}),
          throwsFormatException,
        );
        expect(
          () =>
              SyncIdentityV2.fromJson({...m.identity.toJson(), 'sid': 'corto'}),
          throwsFormatException,
        );
        expect(acceptsProtocol(local: m.identity, incoming: v1), isFalse);
        expect(acceptsProtocol(local: m.identity, incoming: m.common), isTrue);
        expect(acceptsProtocol(local: null, incoming: m.common), isTrue);
        expect(acceptsProtocol(local: null, incoming: v1), isTrue);
      },
    );

    test('ataque (hallazgo 14): una marca de protocolo inventada no deja a '
        'nadie fuera; lo que entra lo decide la identidad local', () async {
      final m = await migrateToV2(
        v1Doc: v1,
        clock: clockOf('aritz-phone', 200),
        keys: aritz.keys,
        deviceId: aritz.id,
        personId: 'aritz',
      );
      FamilyDoc marked(Object? value) => m.common.set(
        clockOf('nora-phone', 900),
        Collections.meta,
        kProtocolRecordId,
        {kProtocolVersionField: value},
      );
      for (final value in [99, 3, 'dos', 0, 2.0, 1.0]) {
        final poisoned = marked(value);
        expect(syncProtocolOf(poisoned), isNull, reason: '$value');
        expect(acceptsProtocol(local: m.identity, incoming: poisoned), isFalse);
        expect(acceptsProtocol(local: null, incoming: poisoned), isFalse);
        expect(
          () => mergeLocalV1IntoV2(v2Doc: poisoned, localV1: v1),
          throwsStateError,
        );
        await expectLater(
          migrateToV2(
            v1Doc: poisoned,
            clock: clockOf('aritz-phone', 300),
            keys: aritz.keys,
            deviceId: aritz.id,
            personId: 'aritz',
          ),
          throwsStateError,
        );
      }
      // Aunque la copia propia lleve una marca envenenada, un documento v2
      // bueno sigue entrando: no decide la marca propia sino la identidad.
      expect(acceptsProtocol(local: m.identity, incoming: m.common), isTrue);
      expect(syncProtocolOf(marked(2)), kSyncProtocolV2);
      expect(syncProtocolOf(marked(1)), 1);
    });

    test('el móvil que vuelve a emparejarse fusiona su copia de v1: no se '
        'pierde lo suyo ni resucita lo que v2 borró', () async {
      final m = await migrateToV2(
        v1Doc: v1,
        clock: clockOf('aritz-phone', 200),
        keys: aritz.keys,
        deviceId: aritz.id,
        personId: 'aritz',
      );
      // En v2 se borra g1; Leo tenía en v1 una edición vieja de g1 y un g2.
      final v2 = m.common.delete(
        clockOf('aritz-phone', 400),
        Collections.gifts,
        'g1',
      );
      final leoClock = clockOf('leo-phone', 150);
      final local = v1
          .set(leoClock, Collections.gifts, 'g1', {'note': 'Tapa dura'})
          .set(leoClock, Collections.gifts, 'g2', giftFields('aritz', 'Balón'));
      final merged = mergeLocalV1IntoV2(v2Doc: v2, localV1: local);
      expect(merged.record(Collections.gifts, 'g1')!.isDeleted, isTrue);
      expect(merged.record(Collections.gifts, 'g1')!['note'], isNull);
      expect(merged.record(Collections.gifts, 'g2')!['title'], 'Balón');
      expect(syncProtocolOf(merged), kSyncProtocolV2);
      expect(
        () => mergeLocalV1IntoV2(v2Doc: v1, localV1: local),
        throwsStateError,
      );
      expect(
        () => mergeLocalV1IntoV2(v2Doc: v2, localV1: m.common),
        throwsStateError,
      );
    });
  });
  group('prueba de la clave v1 (hallazgo 6)', () {
    test(
      'solo la clave v1 de la lista y esta misma oferta la validan',
      () async {
        final v1 = await FamilyKey.generate();
        final (_, offer) = await start(host, aritz);
        final proof = encodeBase64Url(v1ListProof(v1, offer));
        expect(verifyV1ListProof(v1, offer, proof), isTrue);
        // Otra clave con el mismo listId (público): no.
        expect(
          verifyV1ListProof(await FamilyKey.generate(), offer, proof),
          isFalse,
        );
        // La misma prueba copiada en otra oferta (otro nonce): no.
        final (_, other) = await start(host, aritz);
        expect(verifyV1ListProof(v1, other, proof), isFalse);
        // Sin prueba o con basura: no.
        for (final bad in [
          null,
          '',
          'no-base64!',
          7,
          encodeBase64Url([1, 2]),
        ]) {
          expect(verifyV1ListProof(v1, offer, bad), isFalse, reason: '$bad');
        }
      },
    );
  });
}
