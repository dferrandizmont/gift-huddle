// 1.0.6: unir un móvil ya asignado y regalos propios ocultos por defecto
// (modelo, Dart puro). Ver docs/adr/0004-yo-sorpresas-revocar.md y el
// diseño de la 1.0.6: capa de pantalla, quien invita elige la persona,
// protección automática y excepción del móvil solo.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/pairing_v2.dart';
import 'package:regalos/core/sync/protected_doc.dart';

import 'protected_harness.dart';

Future<RegistryView> _view(DeviceRegistry registry, Phone me) =>
    registry.viewFor(
      me: me.id,
      mySigningKey: me.keys.publicKeys.signing,
      livePeople: kPeople,
    );

FamilyDoc _commonWithGifts() {
  final clock = clockOf('aritz-phone', 1);
  var doc = commonWithPeople(clock);
  doc = doc.set(
    clock,
    Collections.gifts,
    'g-nora',
    giftFields('nora', 'Libro'),
  );
  doc = doc.set(clock, Collections.gifts, 'g-leo', giftFields('leo', 'Tren'));
  return doc;
}

Set<String> _titles(AuthorizedProjection p) => {
  for (final g in p.view.gifts) g.title,
};

void main() {
  late Phone aritz;
  late Phone leo;
  late Phone nora;
  late Phone nora2;

  setUp(() async {
    aritz = await Phone.create('aritz-phone', 'aritz', 1);
    leo = await Phone.create('leo-phone', 'leo', 2);
    nora = await Phone.create('nora-phone', 'nora', 3);
    nora2 = await Phone.create('nora-tablet', 'nora', 4);
  });

  group('registro: acompañado, solo y personas con dispositivo', () {
    test('un móvil sin nadie más está solo y no acompañado', () async {
      final registry = await registryOf([nora]);
      final view = await _view(registry, nora);
      expect(view.alone, isTrue);
      expect(view.accompanied('nora'), isFalse);
      expect(view.devicePeople, {'nora'});
    });

    test('con el móvil de otra persona está acompañado; con dos de la misma '
        'persona, no', () async {
      final family = await _view(await registryOf([aritz, nora]), nora);
      expect(family.alone, isFalse);
      expect(family.accompanied('nora'), isTrue);
      expect(family.devicePeople, {'aritz', 'nora'});
      final twins = await _view(await registryOf([nora, nora2]), nora);
      expect(twins.alone, isFalse);
      expect(twins.accompanied('nora'), isFalse);
    });

    test(
      'quitar a los demás no levanta nada: sus fichas siguen contando',
      () async {
        var registry = await registryOf([aritz, nora]);
        final view = await _view(registry, nora);
        registry = await registry.withRevocation(
          await Revocation.create(
            keys: nora.keys,
            by: registry.recordByDigest(view.self.recordDigest)!,
            deviceId: aritz.id,
          ),
        );
        final after = await _view(registry, nora);
        expect(after.members, [nora.id]);
        expect(after.alone, isFalse);
        expect(after.accompanied('nora'), isTrue);
        // Ya no tiene dispositivo activo: no cuenta para la protección.
        expect(after.devicePeople, {'nora'});
      },
    );
  });

  group('capa de pantalla', () {
    test('el caso del incidente: en el móvil de Nora acompañado no se pinta '
        'ningún regalo para Nora, sin política, y queda su bloque', () async {
      final registry = await registryOf([aritz, nora]);
      final view = await _view(registry, nora);
      final own = ownHiddenPeople(
        view: view,
        selfRecipientId: 'nora',
        paired: true,
      );
      expect(own, {'nora'});
      final projection = await projectAuthorized(
        common: _commonWithGifts(),
        slots: SlotSet.empty,
        keyring: SurpriseKeyring.empty,
        view: view,
        ownPeople: own,
      );
      expect(_titles(projection), {'Tren'});
      expect(projection.lockedBlocks, [const SecretBlock('nora')]);
      expect(projection.view.giftsFor('nora'), isEmpty);
      expect(projection.doc.record(Collections.gifts, 'g-nora'), isNull);
      // A los demás no les toca.
      final other = await projectAuthorized(
        common: _commonWithGifts(),
        slots: SlotSet.empty,
        keyring: SurpriseKeyring.empty,
        view: await _view(registry, aritz),
        ownPeople: ownHiddenPeople(
          view: await _view(registry, aritz),
          selfRecipientId: 'aritz',
          paired: true,
        ),
      );
      expect(_titles(other), {'Tren', 'Libro'});
      expect(other.lockedBlocks, [const SecretBlock('aritz')]);
    });

    test('solo, nunca emparejado, se ve todo lo suyo', () async {
      final view = await _view(await registryOf([nora]), nora);
      expect(
        ownHiddenPeople(view: view, selfRecipientId: 'nora', paired: false),
        isEmpty,
      );
      final projection = await projectAuthorized(
        common: _commonWithGifts(),
        slots: SlotSet.empty,
        keyring: SurpriseKeyring.empty,
        view: view,
      );
      expect(_titles(projection), {'Tren', 'Libro'});
    });

    test('emparejado con el registro aún solo (v1 que pasa a v2) y sin '
        'registro (v1): se oculta', () async {
      final view = await _view(await registryOf([nora]), nora);
      expect(
        ownHiddenPeople(view: view, selfRecipientId: 'nora', paired: true),
        {'nora'},
      );
      expect(
        ownHiddenPeople(view: null, selfRecipientId: 'nora', paired: true),
        {'nora'},
      );
      expect(
        ownHiddenPeople(view: null, selfRecipientId: 'nora', paired: false),
        isEmpty,
      );
    });

    test('la persona de la ficha cuenta aunque «Yo» diga otra', () async {
      final view = await _view(await registryOf([aritz, nora]), nora);
      expect(ownHiddenPeople(view: view, selfRecipientId: null, paired: true), {
        'nora',
      });
    });
  });

  group('excepción del móvil solo', () {
    FamilyDoc protectedCommon() => requestProtection(
      _commonWithGifts(),
      clockOf('aritz-phone', 2),
      'nora',
    );

    test('solo y sin emparejar, la política de su persona no oculta; '
        'acompañado, sí', () async {
      final common = protectedCommon();
      final alone = await _view(await registryOf([nora]), nora);
      expect(ownProtectionLifted(view: alone, paired: false), isTrue);
      expect(
        lockedPolicy(
          common: common,
          slots: SlotSet.empty,
          view: alone,
          personId: 'nora',
          alone: true,
        ).hideOwnGifts,
        isFalse,
      );
      expect(
        publicGiftsBlockedFor(
          common: common,
          slots: SlotSet.empty,
          keyring: SurpriseKeyring.empty,
          view: alone,
          personId: 'nora',
          alone: true,
        ),
        isFalse,
      );
      // Sin la marca, como siempre: «ocultar».
      expect(
        lockedPolicy(
          common: common,
          slots: SlotSet.empty,
          view: alone,
          personId: 'nora',
        ).hideOwnGifts,
        isTrue,
      );
      // La marca no vale con otros en el registro ni para otra persona.
      final family = await _view(await registryOf([aritz, nora]), nora);
      expect(ownProtectionLifted(view: family, paired: false), isFalse);
      expect(
        lockedPolicy(
          common: common,
          slots: SlotSet.empty,
          view: family,
          personId: 'nora',
          alone: true,
        ).hideOwnGifts,
        isTrue,
      );
      final otherCommon = requestProtection(
        common,
        clockOf('nora-phone', 3),
        'leo',
      );
      expect(
        lockedPolicy(
          common: otherCommon,
          slots: SlotSet.empty,
          view: alone,
          personId: 'leo',
          alone: true,
        ).hideOwnGifts,
        isTrue,
      );
      // Emparejado en esta generación: no vale.
      expect(ownProtectionLifted(view: alone, paired: true), isFalse);
    });

    test('purgar al quedarse solo borra solo lo vivo de su persona y solo '
        'si hubo compañía', () {
      final common = _commonWithGifts();
      final purged = purgeOwnGiftsOnLeaving(
        common,
        node: 'nora-new',
        people: ['nora', null],
        hadCompany: true,
      );
      expect(purged.record(Collections.gifts, 'g-nora')!.isDeleted, isTrue);
      expect(
        purged.record(Collections.gifts, 'g-nora')!['title'],
        isNull,
        reason: 'lápida vacía',
      );
      expect(purged.record(Collections.gifts, 'g-leo')!.isDeleted, isFalse);
      expect(
        purgeOwnGiftsOnLeaving(
          common,
          node: 'nora-new',
          people: ['nora'],
          hadCompany: false,
        ),
        same(common),
      );
    });

    test('QA M1: solo, vuelve a sellar para sí lo de los demás que ya tenía, '
        'nunca lo suyo', () async {
      var common = requestProtection(
        protectedCommon(),
        clockOf('aritz-phone', 3),
        'leo',
      );
      common = requestProtection(common, clockOf('aritz-phone', 4), 'aritz');
      final alone = await _view(await registryOf([aritz]), aritz);
      const all = AloneRestorePlan(people: {'nora', 'leo', 'aritz'});
      Set<String> restore({
        RegistryView? view,
        FamilyDoc? doc,
        SurpriseKeyring? keyring,
        Iterable<String> scopes = const ['nora', 'leo', 'aritz'],
        bool paired = false,
        AloneRestorePlan plan = all,
      }) => othersToRestoreWhenAlone(
        common: doc ?? common,
        view: view ?? alone,
        slots: SlotSet.empty,
        keyring: keyring ?? SurpriseKeyring.empty,
        localScopes: scopes,
        paired: paired,
        plan: plan,
      );

      // Lo de Nora y Leo, que ya podía abrir; lo de Aritz (el suyo), nunca,
      // aunque hubiera una copia local y el plan lo dejara.
      expect(restore(), {'nora', 'leo'});
      // Sin copia local no hay nada que volver a sellar.
      expect(restore(scopes: const ['nora']), {'nora'});
      // Solo lo que deja el plan de la generación anterior, nunca su `own`.
      expect(restore(plan: const AloneRestorePlan(people: {'nora'})), {'nora'});
      expect(
        restore(
          plan: const AloneRestorePlan(people: {'nora', 'leo'}, own: {'leo'}),
        ),
        {'nora'},
      );
      expect(restore(plan: AloneRestorePlan.none), isEmpty);
      // Sin la protección puesta en el común, nada que restaurar.
      expect(restore(doc: protectedCommon(), scopes: const ['leo']), isEmpty);
      // Idempotente: con la clave de la generación ya no hace nada.
      final key = SurpriseKey.generate('nora', 1, audience: [aritz.id]);
      expect(restore(keyring: SurpriseKeyring([key])), {'leo'});
      // Emparejado en esta generación, o con otro dispositivo en el
      // registro: no vale.
      expect(restore(paired: true), isEmpty);
      final family = await _view(await registryOf([aritz, nora]), aritz);
      expect(family.alone, isFalse);
      expect(restore(view: family), isEmpty);
      // El móvil de Nora solo: lo de Leo y Aritz, nunca lo de Nora.
      final noraAlone = await _view(await registryOf([nora]), nora);
      expect(restore(view: noraAlone), {'leo', 'aritz'});
    });

    test('QA M1 (B1, B2): el plan sale de la generación que se deja; '
        'revocado, con un cambio pendiente o con personas borradas no '
        'recupera nada de quien ya no tiene derecho', () async {
      const held = ['aritz', 'leo', 'nora'];
      final registry = await registryOf([aritz, nora]);
      // Con derecho: los demás; nunca la suya.
      final ok = planAloneRestore(
        view: await _view(registry, aritz),
        held: held,
        selfRecipientId: 'aritz',
      );
      expect(ok.people, {'leo', 'nora'});
      expect(ok.own, {'aritz'});

      // Revocado por otro: nada.
      final revoked = await revokeDevice(
        registry: registry,
        view: await _view(registry, nora),
        myKeys: nora.keys,
        deviceId: aritz.id,
      );
      final revokedView = await _view(revoked.registry, aritz);
      expect(revokedView.revokedByOthers, isTrue);
      expect(planAloneRestore(view: revokedView, held: held).people, isEmpty);

      // Cambio de persona sin aprobar (de Aritz a Leo): nada, y las dos
      // personas, la de antes y la nueva, son suyas.
      final changed = await changePerson(
        registry: registry,
        view: await _view(registry, aritz),
        myKeys: aritz.keys,
        personId: 'leo',
      );
      final pendingView = await _view(changed.registry, aritz);
      expect(pendingView.selfApproved, isFalse);
      final pending = planAloneRestore(
        view: pendingView,
        held: held,
        selfRecipientId: 'leo',
        formerSelf: const {'aritz'},
      );
      expect(pending.people, isEmpty);
      expect(pending.own, containsAll(<String>{'aritz', 'leo'}));

      // Una persona borrada no vuelve; con la suya borrada, nada.
      final noNora = planAloneRestore(
        view: await aritz.viewOf(registry, people: const {'aritz', 'leo'}),
        held: held,
      );
      expect(noNora.people, {'leo'});
      final noSelf = planAloneRestore(
        view: await aritz.viewOf(registry, people: const {'leo', 'nora'}),
        held: held,
      );
      expect(noSelf.people, isEmpty);
    });
  });

  group('protección automática', () {
    test('las personas con dispositivo, sin la de este móvil, con derecho y '
        'sin registro de política', () async {
      final registry = await registryOf([aritz, leo, nora]);
      final common = _commonWithGifts();
      final fromAritz = await _view(registry, aritz);
      expect(peopleToAutoProtect(common, fromAritz), {'leo', 'nora'});
      // El móvil de Nora no tiene derecho a lo suyo.
      final fromNora = await _view(registry, nora);
      expect(peopleToAutoProtect(common, fromNora), {'aritz', 'leo'});
      // Con un registro publicado (pedido o desactivado) manda la política.
      final requested = requestProtection(
        common,
        clockOf('leo-phone', 5),
        'nora',
      );
      expect(peopleToAutoProtect(requested, fromAritz), {'leo'});
    });

    test('quien solo regala no se protege', () async {
      final registry = await registryOf([aritz, nora]);
      var common = _commonWithGifts();
      common = common.set(
        clockOf('aritz-phone', 9),
        Collections.recipients,
        'nora',
        {Recipient.noGiftsField: true},
      );
      expect(receivesNoGifts(common, 'nora'), isTrue);
      // B5 (revisión final): con un regalo vivo suyo (de un 1.0.5) se
      // protege igual; sin ninguno, no hay nada que ocultar.
      expect(nothingToProtectFor(common, 'nora'), isFalse);
      expect(
        peopleToAutoProtect(common, await _view(registry, aritz)),
        {'nora'},
      );
      common = common.delete(clockOf('aritz-phone', 10), Collections.gifts, 'g-nora');
      expect(nothingToProtectFor(common, 'nora'), isTrue);
      expect(
        peopleToAutoProtect(common, await _view(registry, aritz)),
        isEmpty,
      );
    });

    test('sin persona no hay derecho: no protege a nadie', () async {
      final nobody = await Phone.create('nobody-phone', null, 7);
      final registry = await registryOf([nobody, nora]);
      expect(
        peopleToAutoProtect(_commonWithGifts(), await _view(registry, nobody)),
        isEmpty,
      );
    });
  });

  group('quien invita elige la persona', () {
    late DeviceRegistry host;

    setUp(() async {
      host = await registryOf([aritz]);
    });

    Future<PairingAnswer> answer(
      PairingOffer offer,
      Phone guest, {
      String? personId,
      bool withoutPerson = false,
    }) async {
      final join = await joinPairing(
        offer: offer,
        keys: guest.keys,
        deviceId: guest.id,
        personId: personId,
        withoutPerson: withoutPerson,
      );
      return PairingAnswer.fromJson(
        jsonDecode(jsonEncode(join.answer.toJson())),
      );
    }

    Future<PairingOffer> roundTrip(PairingHost session) async =>
        PairingOffer.fromJson(jsonDecode(jsonEncode(session.offer.toJson())));

    test('la oferta lleva la marca y el invitado la lee', () async {
      final session = PairingHost.start(
        host,
        await _view(host, aritz),
        guestPerson: 'nora',
        hostPicksPerson: true,
      );
      expect(session.offer.toJson()[kHostPicksPersonField], 1);
      expect((await roundTrip(session)).hostPicksPerson, isTrue);
      final old = PairingHost.start(host, await _view(host, aritz));
      expect(old.offer.toJson().containsKey(kHostPicksPersonField), isFalse);
      expect((await roundTrip(old)).hostPicksPerson, isFalse);
    });

    test(
      'solo acepta la persona elegida y no gasta la respuesta con otra',
      () async {
        final session = PairingHost.start(
          host,
          await _view(host, aritz),
          guestPerson: 'nora',
          hostPicksPerson: true,
        );
        final offer = await roundTrip(session);
        await expectLater(
          session.receive(await answer(offer, nora, personId: 'leo')),
          throwsA(isA<PairingException>()),
        );
        await expectLater(
          session.receive(await answer(offer, nora, withoutPerson: true)),
          throwsA(isA<PairingException>()),
        );
        expect(session.answer, isNull);
        await session.receive(await answer(offer, nora, personId: 'nora'));
        final change = await acceptPairing(
          registry: host,
          view: await _view(host, aritz),
          myKeys: aritz.keys,
          session: session,
          confirmedPersonId: 'nora',
        );
        final fromNora = await change.registry.viewFor(
          me: nora.id,
          mySigningKey: nora.keys.publicKeys.signing,
          livePeople: kPeople,
        );
        // Entra asignado y aprobado, sin segunda aprobación.
        expect(fromNora.myPerson, 'nora');
        expect(fromNora.selfApproved, isTrue);
      },
    );

    test('B1: un invitado 1.0.5 (sin la marca) que elige la misma persona no '
        'gasta la respuesta ni se aprueba', () async {
      final session = PairingHost.start(
        host,
        await _view(host, aritz),
        guestPerson: 'nora',
        hostPicksPerson: true,
      );
      final offer = await roundTrip(session);
      final good = await answer(offer, nora, personId: 'nora');
      final json =
          jsonDecode(jsonEncode(good.toJson())) as Map<String, Object?>;
      expect(json[kHostPicksPersonField], 1);
      final old = PairingAnswer.fromJson(
        {...json}..remove(kHostPicksPersonField),
      );
      expect(old.hostPicksPerson, isFalse);
      await expectLater(
        session.receive(old),
        throwsA(isA<PairingGuestOutdatedException>()),
      );
      expect(session.answer, isNull);
      // QA 1.0.6, m1: un 1.0.5 recién instalado («Elegir después», sin
      // persona y sin la marca) u otro que eligió otra persona, también.
      final fresh = jsonDecode(
        jsonEncode((await answer(offer, nora, withoutPerson: true)).toJson()),
      ) as Map<String, Object?>;
      for (final outdated in [
        {...fresh}..remove(kHostPicksPersonField),
        fresh,
        jsonDecode(
          jsonEncode((await answer(offer, nora, personId: 'leo')).toJson()),
        ) as Map<String, Object?>..remove(kHostPicksPersonField),
      ]) {
        await expectLater(
          session.receive(PairingAnswer.fromJson(outdated)),
          throwsA(isA<PairingGuestOutdatedException>()),
        );
        expect(session.answer, isNull, reason: 'no gasta la respuesta');
      }
      await session.receive(good);
      expect(session.answer, isNotNull);
    });

    test('ningún móvil entra sin persona: ni eligiéndolo quien invita ni '
        'respondiendo «Elegir después» a un anfitrión viejo', () async {
      final view = await _view(host, aritz);
      expect(
        () => PairingHost.start(host, view, hostPicksPerson: true),
        throwsA(isA<PairingException>()),
      );
      final old = PairingHost.start(host, view);
      final offer = await roundTrip(old);
      await expectLater(
        old.receive(await answer(offer, nora, withoutPerson: true)),
        throwsA(isA<PairingException>()),
      );
      expect(old.answer, isNull, reason: 'no gasta la única respuesta');
      await old.receive(await answer(offer, nora, personId: 'nora'));
      expect(old.answer!.guest.personId, 'nora');
    });

    test('la compañía y la purga siguen la misma regla: dos dispositivos de '
        'la misma persona no se ocultan nada', () async {
      final twins = await registryOf([nora, nora2]);
      expect((await _view(twins, nora)).accompanied('nora'), isFalse);
      expect(
        ownGiftsWereHidden(
          registry: twins,
          me: nora.id,
          people: ['nora'],
          paired: true,
        ),
        isFalse,
      );
      final family = await registryOf([aritz, nora]);
      expect(
        ownGiftsWereHidden(
          registry: family,
          me: nora.id,
          people: ['nora'],
          paired: true,
        ),
        isTrue,
      );
      // Sin otras fichas: solo si se emparejó (v1 que pasa a v2).
      final alone = await registryOf([nora]);
      expect(
        ownGiftsWereHidden(
          registry: alone,
          me: nora.id,
          people: ['nora'],
          paired: true,
        ),
        isTrue,
      );
      expect(
        ownGiftsWereHidden(
          registry: alone,
          me: nora.id,
          people: ['nora'],
          paired: false,
        ),
        isFalse,
      );
      expect(
        ownGiftsWereHidden(
          registry: null,
          me: nora.id,
          people: ['nora'],
          paired: false,
          unreadable: true,
        ),
        isTrue,
      );
    });

    test(
      'con un cambio de persona pendiente, la de antes sigue oculta',
      () async {
        var registry = await registryOf([aritz, nora]);
        // El móvil de Nora pasa a ser de Leo: ficha 2, sin aprobar.
        registry = await registry.withRecord(
          await nora.record(person: 'leo', seq: 2),
        );
        final view = await _view(registry, nora);
        expect(view.myPerson, 'leo');
        expect(view.selfApproved, isFalse);
        final own = ownHiddenPeople(
          view: view,
          selfRecipientId: 'leo',
          paired: true,
        );
        expect(own, containsAll({'leo', 'nora'}));
        // Sin registro (v1 emparejado): la de antes, apuntada aparte.
        expect(
          ownHiddenPeople(
            view: null,
            selfRecipientId: 'leo',
            paired: true,
            formerSelf: {'nora'},
          ),
          {'leo', 'nora'},
        );
        // Aprobado el cambio, ya no.
        final approved = await registryOf([aritz, nora]);
        expect(
          ownHiddenPeople(
            view: await _view(approved, nora),
            selfRecipientId: 'nora',
            paired: true,
            formerSelf: {'leo'},
          ),
          {'nora'},
        );
      },
    );

    test(
      'no se puede elegir a quien no existe ni fijar persona en la web',
      () async {
        final view = await _view(host, aritz);
        expect(
          () => PairingHost.start(
            host,
            view,
            guestPerson: 'otra-no',
            hostPicksPerson: true,
          ),
          throwsA(isA<PairingException>()),
        );
        expect(
          () => PairingHost.start(
            host,
            view,
            expectWeb: true,
            guestPerson: 'nora',
            hostPicksPerson: true,
          ),
          throwsA(isA<PairingException>()),
        );
      },
    );

    test('los derechos no cambian: entitled, selfEntitled y épocas', () async {
      final registry = await registryOf([aritz, leo, nora]);
      final fromAritz = await _view(registry, aritz);
      expect(fromAritz.selfEntitled('nora'), isTrue);
      expect(fromAritz.entitledDevices('nora'), [aritz.id, leo.id]);
      final fromNora = await _view(registry, nora);
      expect(fromNora.selfEntitled('nora'), isFalse);
      expect(fromNora.epoch, fromAritz.epoch);
    });
  });

  group('quien solo regala', () {
    test('no sale como destinatario ni en Reparto, pero sí en Personas', () {
      final clock = clockOf('aritz-phone', 1);
      var doc = commonWithPeople(clock);
      doc = doc.set(clock, Collections.recipients, 'aritz', {
        Recipient.noGiftsField: true,
      });
      final view = FamilyView.fromDoc(doc);
      expect(view.recipients.map((r) => r.id), contains('aritz'));
      expect(view.giftRecipients.map((r) => r.id), isNot(contains('aritz')));
      expect(view.repartoRecipients.map((r) => r.id), isNot(contains('aritz')));
      expect(view.outsideReparto.map((r) => r.id), isNot(contains('aritz')));
      expect(view.grid().recipients.map((r) => r.id), isNot(contains('aritz')));
      final aritz = view.recipientsById['aritz']!;
      expect(aritz.noGifts, isTrue);
      expect(aritz.toFields()[Recipient.noGiftsField], isTrue);
      expect(
        view.recipientsById['nora']!.toFields().containsKey(
          Recipient.noGiftsField,
        ),
        isFalse,
      );
    });
  });
}
