// Fase 2a del ADR 0004: política en la cabecera firmada (N1), capacidad
// (N2 a N4), slots sin señal (M5), claves candidatas, épocas, rotación y
// compactación. Requisitos 7 a 17, 24 y 25 de
// la revisión de seguridad de la fase 1 (segunda pasada)
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:clock/clock.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/key_bundle.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/protected_doc.dart';
import 'package:regalos/core/sync/protected_envelope.dart';

import 'protected_harness.dart';

void main() {
  late Family family;
  late FamilyDoc common;
  const on1 = PolicyState(hideOwnGifts: true, rev: 1);
  const nora = SecretBlock('nora');

  setUp(() async {
    family = await Family.create();
    final clock = clockOf('aritz-phone', 100);
    common = commonWithPeople(clock)
        .set(clock, Collections.gifts, 'g1', giftFields('nora', 'Muñeca'))
        .set(clock, Collections.gifts, 'g2', giftFields('aritz', 'Balón'));
  });

  Future<SealedSlot> seal(
    Phone phone,
    FamilyDoc doc, {
    required int revision,
    PolicyState policy = on1,
    SurpriseKey? key,
  }) => SealedSlot.seal(
    writerKeys: phone.keys,
    writer: phone.id,
    revision: revision,
    key: key ?? family.key,
    policy: policy,
    doc: doc,
  );

  Future<OpenedScope> openAs(
    Phone phone,
    SlotSet slots, {
    SurpriseKeyring? keyring,
    RegistryView? view,
  }) async => (await openScope(
    personId: 'nora',
    slots: slots,
    keyring: keyring ?? family.authorizedKeyring,
    view: view ?? family.viewOf(phone),
  ))!;

  Future<PublishedSlot> publishAs(
    Phone phone,
    SlotSet slots,
    OpenedScope opened,
    FamilyDoc doc, {
    required int now,
    PolicyState policy = on1,
    SurpriseKeyring? keyring,
    RegistryView? view,
  }) => publishScope(
    slots: slots,
    opened: opened,
    view: view ?? family.viewOf(phone),
    writerKeys: phone.keys,
    keyring: keyring ?? family.authorizedKeyring,
    policy: policy,
    doc: doc,
    nowMillis: now,
  );

  Future<SlotSet> withSlot(
    SlotSet slots,
    SealedSlot slot, {
    RegistryView? view,
  }) async => (await slots.acceptVerified(slot, view: view ?? family.view)).$1;

  ProtectionTransition activate(FamilyDoc from, {SurpriseKey? key}) =>
      activateProtection(
        common: from,
        scope: FamilyDoc.empty(kListId),
        key: key ?? family.key,
        publicClock: clockOf('aritz-phone', 1000),
        scopeClock: clockOf('aritz-phone', 1000),
      );

  Future<AuthorizedProjection> projectAs(
    Phone phone,
    FamilyDoc from,
    SlotSet slots, {
    SurpriseKeyring? keyring,
    RegistryView? view,
  }) => projectAuthorized(
    common: from,
    slots: slots,
    keyring: keyring ?? SurpriseKeyring.empty,
    view: view ?? family.viewOf(phone),
  );

  List<SyncRecord> publicGiftsOfNora(FamilyDoc doc) => [
    for (final r in doc.collections[Collections.gifts]!.values)
      if (!r.isDeleted && r['recipientId'] == 'nora') r,
  ];

  /// Un documento de ámbito con [n] lápidas.
  FamilyDoc tombstones(int n, String prefix) {
    final clock = clockOf('aritz-phone', 500);
    final one = FamilyDoc.empty(kListId)
        .set(clock, Collections.gifts, 't', giftFields('nora', 'Muestra'))
        .delete(clock, Collections.gifts, 't')
        .record(Collections.gifts, 't')!;
    return FamilyDoc(
      listId: kListId,
      collections: {
        Collections.gifts: {
          for (var i = 0; i < n; i++)
            '$prefix$i': SyncRecord(id: '$prefix$i', fields: one.fields),
        },
      },
    );
  }

  group('N1: la política va en la cabecera firmada', () {
    test('ataque: un móvil autorizado que aún no tiene la clave no se cree '
        'una política publicada que dice «publicar»', () async {
      final on = activate(common);
      final slots = await family.setOf([
        await seal(family.aritz, on.scope, revision: 1),
      ]);
      final forged = writePublishedPolicy(
        on.common,
        clockOf('nora-phone', 5000),
        'nora',
        const PolicyState(hideOwnGifts: false, rev: 99),
      );
      for (final phone in [family.leo, family.nora]) {
        final p = await projectAs(phone, forged, slots);
        expect(p.lockedBlocks, [nora], reason: phone.id);
        expect(p.policies['nora'], on1, reason: phone.id);
        expect(p.openedScopes, isEmpty);
      }
      expect(slots.authenticatedPolicy('nora', family.viewOf(family.leo)), on1);
    });

    test('sin clave, con slots y sin ninguna política autenticada (el '
        'escritor está revocado): ocultar', () async {
      final on = activate(common);
      final slots = await family.setOf([
        await seal(family.aritz, on.scope, revision: 1),
      ]);
      final revoked = (await revokeDevice(
        registry: family.registry,
        view: family.viewOf(family.nora),
        myKeys: family.nora.keys,
        deviceId: family.aritz.id,
      )).registry;
      final view = await family.leo.viewOf(revoked);
      expect(slots.authenticatedPolicy('nora', view), isNull);
      final forged = writePublishedPolicy(
        on.common,
        clockOf('nora-phone', 5000),
        'nora',
        const PolicyState(hideOwnGifts: false, rev: 99),
      );
      final p = await projectAs(family.leo, forged, slots, view: view);
      expect(p.lockedBlocks, [nora]);
      expect(p.policies['nora']!.hideOwnGifts, isTrue);
    });

    test('una desactivación autenticada se ve sin la clave', () async {
      final on = activate(common);
      final off = deactivateProtection(
        common: on.common,
        scope: on.scope,
        key: family.key,
        publicClock: clockOf('aritz-phone', 2000),
        scopeClock: clockOf('aritz-phone', 2000),
        authenticated: on.policy,
      );
      final slots = await family.setOf([
        await seal(family.aritz, off.scope, revision: 2, policy: off.policy),
      ]);
      for (final phone in [family.leo, family.nora]) {
        final p = await projectAs(phone, off.common, slots);
        expect(p.lockedBlocks, isEmpty);
        expect(p.policies['nora'], off.policy);
      }
    });
  });

  group('regalos públicos de una persona protegida (req. 14 y 15)', () {
    test('un móvil sin clave no añade al común regalos para quien tiene la '
        'protección pedida o slots', () async {
      final view = family.viewOf(family.leo);
      final clock = clockOf('leo-phone', 700);
      FamilyDoc add(FamilyDoc doc, SlotSet slots, String to) => addPublicGift(
        common: doc,
        clock: clock,
        slots: slots,
        keyring: SurpriseKeyring.empty,
        view: view,
        giftId: 'g9',
        fields: giftFields(to, 'Pinturas'),
      );
      final blocked = throwsA(isA<ProtectedPersonException>());
      // Sin protección: se puede.
      expect(
        add(common, SlotSet.empty, 'nora').canonicalJson(),
        contains('Pin'),
      );
      // Pedida: no.
      final requested = requestProtection(
        common,
        clockOf('nora-phone', 500),
        'nora',
      );
      expect(() => add(requested, SlotSet.empty, 'nora'), blocked);
      expect(add(requested, SlotSet.empty, 'aritz'), isNotNull);
      // Con slots, aunque el común diga «publicar»: no.
      final on = activate(common);
      final slots = await family.setOf([
        await seal(family.aritz, on.scope, revision: 1),
      ]);
      final forged = writePublishedPolicy(
        on.common,
        clockOf('nora-phone', 5000),
        'nora',
        const PolicyState(hideOwnGifts: false, rev: 99),
      );
      expect(() => add(forged, slots, 'nora'), blocked);
      // Tampoco cambiando de persona un regalo que ya existe.
      expect(
        () => addPublicGift(
          common: forged,
          clock: clock,
          slots: slots,
          keyring: SurpriseKeyring.empty,
          view: view,
          giftId: 'g2',
          fields: {'recipientId': 'nora'},
        ),
        blocked,
      );
      // Con la protección quitada de verdad (cabecera firmada): se puede.
      final off = deactivateProtection(
        common: on.common,
        scope: on.scope,
        key: family.key,
        publicClock: clockOf('aritz-phone', 2000),
        scopeClock: clockOf('aritz-phone', 2000),
        authenticated: on.policy,
      );
      final offSlots = await withSlot(
        slots,
        await seal(family.aritz, off.scope, revision: 2, policy: off.policy),
      );
      expect(add(off.common, offSlots, 'nora'), isNotNull);
    });

    test('pedir la protección no crea clave ni mueve nada: lo confirma un '
        'móvil con derecho', () async {
      final requested = requestProtection(
        common,
        clockOf('nora-phone', 500),
        'nora',
      );
      expect(requested.record(Collections.gifts, 'g1')!['title'], 'Muñeca');
      // Un móvil con derecho pero sin clave ve el bloque y no mueve nada.
      final p = await projectAs(family.aritz, requested, SlotSet.empty);
      expect(p.lockedBlocks, [nora]);
      expect(p.openedScopes, isEmpty);
      expect(
        await openScope(
          personId: 'nora',
          slots: SlotSet.empty,
          keyring: SurpriseKeyring.empty,
          view: family.view,
        ),
        isNull,
      );
      // El móvil de Nora no puede crear la clave.
      await expectLater(
        createSurpriseKey(
          personId: 'nora',
          keyring: SurpriseKeyring.empty,
          view: family.viewOf(family.nora),
          keys: family.nora.keys,
        ),
        throwsStateError,
      );
      // Aritz confirma: nace la clave, con un paquete para Leo y ninguno
      // para Nora, y entonces sí se mueven los regalos.
      final share = await createSurpriseKey(
        personId: 'nora',
        keyring: SurpriseKeyring.empty,
        view: family.view,
        keys: family.aritz.keys,
      );
      expect([for (final b in share.bundles) b.toDevice], ['leo-phone']);
      expect(share.key.epoch, family.view.epoch);
      final t = activate(requested, key: share.key);
      expect(t.policy, on1);
      expect(publicGiftsOfNora(t.common), isEmpty);
      expect(t.scope.record(Collections.gifts, 'g1')!['title'], 'Muñeca');
    });
  });

  group('slots sin señal (M5, req. 7 a 9)', () {
    test('cuándo toca publicar depende solo de datos públicos', () async {
      final mine = (await seal(
        family.aritz,
        FamilyDoc.empty(kListId),
        revision: 5000,
      )).header;
      bool due({
        SlotHeader? header,
        int epoch = 1,
        String? kid,
        int now = 5010,
        bool commonChanged = false,
      }) => slotPublishDue(
        mine: header,
        epoch: epoch,
        sealingKid: kid ?? family.key.kid,
        nowMillis: now,
        commonChanged: commonChanged,
      );
      expect(due(), isTrue, reason: 'sin slot');
      expect(due(header: mine), isFalse, reason: 'nada público ha cambiado');
      expect(due(header: mine, commonChanged: true), isTrue);
      expect(due(header: mine, epoch: 2), isTrue);
      expect(due(header: mine, kid: '0000000000000000'), isTrue);
      final hour = kSlotCadence.inMilliseconds;
      expect(due(header: mine, now: 5000 + hour - 1), isFalse);
      expect(due(header: mine, now: 5000 + hour), isTrue);
    });

    test(
      'la revisión es el momento de sellar, no un contador de ediciones',
      () async {
        var slots = SlotSet.empty;
        expect(
          slots.nextRevision('nora', 'aritz-phone', nowMillis: 7000),
          7000,
        );
        final on = activate(common);
        var opened = await openAs(family.aritz, slots);
        // Publica sin haber editado nada y después con treinta ediciones.
        final first = await publishAs(
          family.aritz,
          slots,
          opened,
          on.scope,
          now: 7000,
        );
        slots = await withSlot(slots, first.slot);
        opened = await openAs(family.aritz, slots);
        var edited = opened.doc;
        final clock = clockOf('aritz-phone', 7500);
        for (var i = 0; i < 30; i++) {
          edited = addSurpriseGift(
            edited,
            clock,
            'x$i',
            giftFields('nora', 'R$i'),
          );
        }
        final second = await publishAs(
          family.aritz,
          slots,
          opened,
          edited,
          now: 8000,
        );
        expect(first.slot.header.revision, 7000);
        expect(second.slot.header.revision, 8000);
        expect(second.slot.bytes.length, first.slot.bytes.length);
        // Con el reloj atrasado sube de uno en uno, sin repetir.
        slots = await withSlot(slots, second.slot);
        expect(slots.nextRevision('nora', 'aritz-phone', nowMillis: 10), 8001);
      },
    );

    test('un slot por móvil con derecho, también del que no tiene nada que '
        'decir', () async {
      final on = activate(common);
      var slots = SlotSet.empty;
      final a = await publishAs(
        family.aritz,
        slots,
        await openAs(family.aritz, slots),
        on.scope,
        now: 1000,
      );
      slots = await withSlot(slots, a.slot);
      // Leo recibe la clave y publica el suyo sin haber escrito nada.
      final openedLeo = await openAs(family.leo, slots);
      final l = await publishAs(
        family.leo,
        slots,
        openedLeo,
        openedLeo.doc,
        now: 1200,
      );
      slots = await withSlot(slots, l.slot);
      expect([
        for (final s in slots.slotsFor('nora')) s.header.writer,
      ], family.view.entitledDevices('nora'));
      for (final s in slots.slotsFor('nora')) {
        expect(s.bytes.length, SealedSlot.sizeFor(s.header));
      }
      expect(l.slot.header.policy, on1);
    });

    test('publishScope se niega cuando este móvil no debe publicar', () async {
      final on = activate(common);
      final slots = await family.setOf([
        await seal(family.aritz, on.scope, revision: 1),
        await seal(family.leo, on.scope, revision: 1),
      ]);
      final opened = await openAs(family.leo, slots);
      final blocked = throwsA(isA<SlotPublishBlockedException>());
      // Revocado por otro.
      final revoked = (await revokeDevice(
        registry: family.registry,
        view: family.view,
        myKeys: family.aritz.keys,
        deviceId: family.leo.id,
      )).registry;
      await expectLater(
        publishAs(
          family.leo,
          slots,
          opened,
          opened.doc,
          now: 2000,
          view: await family.leo.viewOf(revoked),
        ),
        blocked,
      );
      // Sin la clave de la época actual (el registro ya va por la 2).
      final epoch2 = (await revokeDevice(
        registry: family.registry,
        view: family.view,
        myKeys: family.aritz.keys,
        deviceId: family.nora.id,
      )).registry;
      await expectLater(
        publishAs(
          family.leo,
          slots,
          opened,
          opened.doc,
          now: 2000,
          view: await family.leo.viewOf(epoch2),
        ),
        blocked,
      );
      // Con una política más vieja que la autenticada.
      final off = deactivateProtection(
        common: on.common,
        scope: on.scope,
        key: family.key,
        publicClock: clockOf('aritz-phone', 2000),
        scopeClock: clockOf('aritz-phone', 2000),
        authenticated: on.policy,
      );
      final offSlots = await withSlot(
        slots,
        await seal(family.aritz, off.scope, revision: 2, policy: off.policy),
      );
      final openedOff = await openAs(family.leo, offSlots);
      expect(openedOff.authenticatedPolicy, off.policy);
      await expectLater(
        publishAs(family.leo, offSlots, openedOff, openedOff.doc, now: 3000),
        blocked,
      );
      // Sin haber podido leer su propio slot anterior (una copia restaurada
      // con otro llavero): su instantánea no lo recogería.
      final other = SurpriseKey(
        personId: 'nora',
        epoch: 1,
        bytes: List<int>.filled(32, 9),
        audience: const ['aritz-phone', 'leo-phone'],
      );
      final onlyOther = SurpriseKeyring([other]);
      final openedOther = await openAs(family.leo, slots, keyring: onlyOther);
      expect(openedOther.unreadableWriters, ['aritz-phone', 'leo-phone']);
      await expectLater(
        publishAs(
          family.leo,
          slots,
          openedOther,
          openedOther.doc,
          now: 3000,
          keyring: onlyOther,
        ),
        blocked,
      );
      // Y en el caso normal publica.
      expect(
        (await publishAs(
          family.leo,
          slots,
          opened,
          opened.doc,
          now: 3000,
        )).leftOut,
        isEmpty,
      );
    });
  });

  group('slots de revocados y de épocas (req. 10)', () {
    test('el slot de un móvil revocado se ignora: ni se lee ni bloquea, y el '
        'revocado no abre lo que se publica después', () async {
      final on = activate(common);
      final leoOnly = scopeWith(clockOf('leo-phone', 1500), ['Solo de Leo']);
      final slots = await family.setOf([
        await seal(family.aritz, on.scope, revision: 1),
        await seal(family.leo, leoOnly, revision: 1),
      ]);
      final registry = (await revokeDevice(
        registry: family.registry,
        view: family.view,
        myKeys: family.aritz.keys,
        deviceId: family.leo.id,
      )).registry;
      final view = await family.aritz.viewOf(registry);
      expect(view.epoch, 2);
      final opened = await openAs(family.aritz, slots, view: view);
      expect(opened.ignoredWriters, ['leo-phone']);
      expect(opened.unreadableWriters, isEmpty);
      expect(opened.doc.canonicalJson(), isNot(contains('Solo de Leo')));
      // Rota: clave nueva de la época 2, sin paquete para nadie más.
      final rotation = await rotateSurpriseKeys(
        keyring: family.authorizedKeyring,
        view: view,
        keys: family.aritz.keys,
      );
      expect(rotation.bundles, isEmpty);
      final published = await publishAs(
        family.aritz,
        slots,
        opened,
        opened.doc,
        now: 9000,
        keyring: rotation.keyring,
        view: view,
      );
      expect(published.slot.header.epoch, 2);
      await expectLater(
        published.slot.open(
          expectedListId: kListId,
          key: family.key,
          signingKey: family.aritz.keys.publicKeys.signing,
        ),
        throwsA(isA<SlotWrongScopeException>()),
      );
      // Lo que mande el revocado ya no entra, y sus slots se retiran.
      await expectLater(
        slots.acceptVerified(
          await seal(family.leo, leoOnly, revision: 2),
          view: view,
        ),
        throwsA(isA<SlotAuthException>()),
      );
      expect(
        [for (final s in slots.pruned(view).slotsFor('nora')) s.header.writer],
        ['aritz-phone'],
      );
    });

    test(
      'el slot de época vieja de un escritor que sigue activo se sigue '
      'leyendo; uno de una época que el registro no ha abierto no entra',
      () async {
        final on = activate(common);
        final slots = await family.setOf([
          await seal(family.aritz, on.scope, revision: 1),
          await seal(
            family.leo,
            scopeWith(clockOf('leo-phone', 1500), ['Cometa']),
            revision: 1,
          ),
        ]);
        final future = SurpriseKey(
          personId: 'nora',
          epoch: 2,
          bytes: List<int>.filled(32, 8),
        );
        final early = await seal(
          family.leo,
          on.scope,
          revision: 5,
          key: future,
        );
        await expectLater(
          slots.acceptVerified(early, view: family.view),
          throwsA(isA<SlotWrongScopeException>()),
        );
        // Se revoca el móvil de Nora: época 2. Aritz ya tiene la clave nueva.
        final registry = (await revokeDevice(
          registry: family.registry,
          view: family.view,
          myKeys: family.aritz.keys,
          deviceId: family.nora.id,
        )).registry;
        final view = await family.aritz.viewOf(registry);
        final opened = await openAs(
          family.aritz,
          await withSlot(slots, early, view: view),
          keyring: SurpriseKeyring([family.key, future]),
          view: view,
        );
        expect(opened.unreadableWriters, isEmpty);
        expect(opened.parts.keys, ['aritz-phone', 'leo-phone']);
        // Sin la clave nueva, el slot nuevo de Leo es ilegible (pasajero), pero
        // su política firmada cuenta y Aritz sigue pudiendo abrir el suyo.
        final without = await openAs(
          family.aritz,
          await withSlot(slots, early, view: view),
          view: view,
        );
        expect(without.unreadableWriters, ['leo-phone']);
        expect(without.authenticatedPolicy, on1);
        expect(without.parts.keys, ['aritz-phone']);
      },
    );
  });

  group('dos móviles crean clave a la vez (req. 11)', () {
    test('no chocan: dos candidatas, se cruzan los paquetes y los dos acaban '
        'sellando con la misma, sin regalos duplicados', () async {
      final leoView = family.viewOf(family.leo);
      final a = await createSurpriseKey(
        personId: 'nora',
        keyring: SurpriseKeyring.empty,
        view: family.view,
        keys: family.aritz.keys,
      );
      final l = await createSurpriseKey(
        personId: 'nora',
        keyring: SurpriseKeyring.empty,
        view: leoView,
        keys: family.leo.keys,
      );
      expect(a.key.kid, isNot(l.key.kid));
      // Cada uno activa y publica con la suya, sin saber del otro.
      final ta = activate(common, key: a.key);
      final tl = activateProtection(
        common: common,
        scope: FamilyDoc.empty(kListId),
        key: l.key,
        publicClock: clockOf('leo-phone', 1000),
        scopeClock: clockOf('leo-phone', 1000),
      );
      final sa = await publishAs(
        family.aritz,
        SlotSet.empty,
        await openAs(family.aritz, SlotSet.empty, keyring: a.keyring),
        ta.scope,
        now: 1000,
        keyring: a.keyring,
      );
      final sl = await publishAs(
        family.leo,
        SlotSet.empty,
        await openAs(family.leo, SlotSet.empty, keyring: l.keyring),
        tl.scope,
        now: 1000,
        keyring: l.keyring,
      );
      var slots = await family.setOf([sa.slot, sl.slot]);
      // Antes de cruzar los paquetes: el del otro es ilegible, pero su
      // política firmada cuenta y nada se rompe.
      final before = await openAs(family.aritz, slots, keyring: a.keyring);
      expect(before.unreadableWriters, ['leo-phone']);
      expect(before.authenticatedPolicy, on1);
      // Se cruzan los paquetes: el llavero guarda las dos, sin conflicto.
      final aKeys = a.keyring.withKey(
        await l.bundles.single.openSurpriseKey(
          mine: family.aritz.keys,
          view: family.view,
        ),
        registryEpoch: family.view.epoch,
      );
      final lKeys = l.keyring.withKey(
        await a.bundles.single.openSurpriseKey(
          mine: family.leo.keys,
          view: leoView,
        ),
        registryEpoch: leoView.epoch,
      );
      expect(aKeys.keys, hasLength(2));
      final allowed = family.view.entitledDevices('nora');
      final canonical = aKeys.sealingKeyFor('nora', 1, allowed: allowed)!.kid;
      expect(lKeys.sealingKeyFor('nora', 1, allowed: allowed)!.kid, canonical);
      expect(
        canonical,
        [a.key.kid, l.key.kid].reduce((x, y) => x.compareTo(y) < 0 ? x : y),
      );
      // Los dos abren los dos slots: un solo regalo, con su id de siempre.
      final openedA = await openAs(family.aritz, slots, keyring: aKeys);
      final openedL = await openAs(family.leo, slots, keyring: lKeys);
      for (final opened in [openedA, openedL]) {
        expect(opened.unreadableWriters, isEmpty);
        expect(liveSurpriseGifts(opened.doc), 1);
        expect(opened.doc.record(Collections.gifts, 'g1')!['title'], 'Muñeca');
      }
      expect(openedA.doc.canonicalJson(), openedL.doc.canonicalJson());
      // El común también converge, sin la muñeca.
      final merged = ta.common.merge(tl.common);
      expect(
        merged.canonicalJson(),
        tl.common.merge(ta.common).canonicalJson(),
      );
      expect(publicGiftsOfNora(merged), isEmpty);
      // La siguiente publicación de los dos va con la misma clave.
      final sa2 = await publishAs(
        family.aritz,
        slots,
        openedA,
        openedA.doc,
        now: 2000,
        keyring: aKeys,
      );
      final sl2 = await publishAs(
        family.leo,
        slots,
        openedL,
        openedL.doc,
        now: 2000,
        keyring: lKeys,
      );
      expect(sa2.slot.header.kid, canonical);
      expect(sl2.slot.header.kid, canonical);
      slots = await withSlot(await withSlot(slots, sa2.slot), sl2.slot);
      // Y quien solo tenga una de las dos sigue abriendo ambos.
      final onlyCanonical = SurpriseKeyring([
        aKeys.sealingKeyFor('nora', 1, allowed: allowed)!,
      ]);
      final late = await openAs(family.leo, slots, keyring: onlyCanonical);
      expect(late.unreadableWriters, isEmpty);
      expect(liveSurpriseGifts(late.doc), 1);
    });
  });

  group('capacidad (N2, N3 y N4; req. 16)', () {
    test('ataque N2: Nora llena el común de regalos para sí misma. No gasta '
        'el cupo de la interfaz y lo que no cabe se conserva', () async {
      final on = activate(common);
      final opened = await openAs(
        family.aritz,
        await family.setOf([await seal(family.aritz, on.scope, revision: 1)]),
      );
      var commonNow = on.common;
      for (var i = 0; i < 40; i++) {
        commonNow = commonNow.set(
          clockOf('nora-phone', 2000),
          Collections.gifts,
          'n${i.toString().padLeft(2, '0')}',
          giftFields('nora', 'Relleno $i'),
        );
      }
      var scope = opened.doc;
      final overflow = <SyncRecord>[];
      for (var pass = 0; pass < 5; pass++) {
        final t = reconcileProtection(
          common: commonNow,
          scope: scope,
          opened: opened,
          key: family.key,
          publicClock: clockOf('aritz-phone', 3000 + pass),
          scopeClock: clockOf('aritz-phone', 3000 + pass),
        );
        expect(
          t.common.canonicalJson().split('Relleno').length - 1,
          32 - 8 * pass,
        );
        commonNow = t.common;
        scope = t.scope;
        overflow.addAll(t.overflow);
      }
      expect(publicGiftsOfNora(commonNow), isEmpty);
      expect(liveMovedInGifts(scope), kMaxReconcileGifts);
      expect(liveOwnSurpriseGifts(scope), 1);
      // Lo que no cupo sale con su contenido, para guardarlo en local.
      expect(overflow, hasLength(40 - kMaxReconcileGifts));
      expect(overflow.first['title'], 'Relleno $kMaxReconcileGifts');
      // El cupo de la interfaz sigue entero: caben los otros 199 y ni uno más.
      final clock = clockOf('aritz-phone', 4000);
      for (var i = 0; i < kMaxSurpriseGifts - 1; i++) {
        scope = addSurpriseGift(scope, clock, 'u$i', giftFields('nora', 'S$i'));
      }
      expect(
        () => addSurpriseGift(scope, clock, 'ux', giftFields('nora', 'Sx')),
        throwsA(isA<SurpriseCapacityException>()),
      );
      expect(liveSurpriseGifts(scope), kMaxSlotGifts);
      expect(scopeFitsInSlot(scope, 'nora'), isTrue);
      // Borrar uno movido libera su cupo.
      scope = scope.delete(clock, Collections.gifts, 'n00');
      expect(liveMovedInGifts(scope), kMaxReconcileGifts - 1);
    });

    test('N3: más de kMaxSlotGifts vivos al fusionar dos escritores no '
        'bloquea la publicación ni pierde nada', () async {
      // Cada uno llenó el suyo sin red: entre los dos pasan del tope por 16.
      const each = kMaxSlotGifts ~/ 2 + 8;
      FamilyDoc forty(String node, String prefix) {
        var doc = FamilyDoc.empty(kListId);
        final clock = clockOf(node, 1000);
        for (var i = 0; i < each; i++) {
          doc = doc.set(
            clock,
            Collections.gifts,
            '$prefix${i.toString().padLeft(3, '0')}',
            giftFields('nora', 'Regalo $prefix$i'),
          );
        }
        return doc;
      }

      final leoSlot = await seal(
        family.leo,
        forty('leo-phone', 'l'),
        revision: 1,
      );
      final slots = await family.setOf([
        await seal(family.aritz, forty('aritz-phone', 'a'), revision: 1),
        leoSlot,
      ]);
      final opened = await openAs(family.aritz, slots);
      expect(liveSurpriseGifts(opened.doc), 2 * each);
      final published = await publishAs(
        family.aritz,
        slots,
        opened,
        opened.doc,
        now: 5000,
      );
      expect(liveSurpriseGifts(published.sealed), kMaxSlotGifts);
      expect(published.leftOut, hasLength(16));
      expect(
        published.leftOut.first,
        'l${(kMaxSlotGifts - each).toString().padLeft(3, '0')}',
      );
      // Entre los dos slots sigue estando todo.
      final after = await openAs(
        family.leo,
        await withSlot(slots, published.slot),
      );
      expect(liveSurpriseGifts(after.doc), 2 * each);
      // Y desde la interfaz no entra ni uno más.
      expect(
        () => addSurpriseGift(
          opened.doc,
          clockOf('aritz-phone', 6000),
          'nuevo',
          giftFields('nora', 'Otro'),
        ),
        throwsA(isA<SurpriseCapacityException>()),
      );
    });

    test('N3: lo que no se puede sellar tampoco se acepta al abrir', () async {
      var doc = FamilyDoc.empty(kListId);
      final clock = clockOf('leo-phone', 1000);
      for (var i = 0; i < kMaxSlotGifts + 1; i++) {
        doc = doc.set(
          clock,
          Collections.gifts,
          'x$i',
          giftFields('nora', 'R$i'),
        );
      }
      await expectLater(
        seal(family.leo, doc, revision: 1),
        throwsA(isA<SurpriseCapacityException>()),
      );
      // Un escritor que se salta el límite fabrica el slot a mano.
      final raw = await _rawSlot(family.leo, family.key, doc);
      await expectLater(
        raw.open(
          expectedListId: kListId,
          key: family.key,
          signingKey: family.leo.keys.publicKeys.signing,
        ),
        throwsA(isA<SlotFormatException>()),
      );
      final huge = FamilyDoc.empty(kListId).set(
        clock,
        Collections.gifts,
        'x',
        giftFields('nora', 'x' * (kMaxSurpriseGiftBytes + 1)),
      );
      await expectLater(
        (await _rawSlot(family.leo, family.key, huge)).open(
          expectedListId: kListId,
          key: family.key,
          signingKey: family.leo.keys.publicKeys.signing,
        ),
        throwsA(isA<SlotFormatException>()),
      );
      // En el conjunto queda como ilegible: no rompe la apertura.
      final opened = await openAs(family.aritz, await family.setOf([raw]));
      expect(opened.unreadableWriters, ['leo-phone']);
      expect(liveSurpriseGifts(opened.doc), 0);
    });

    test('N3 con «cap»: al abrir vale el límite que anuncia el slot', () async {
      var doc = FamilyDoc.empty(kListId);
      final clock = clockOf('leo-phone', 1000);
      for (var i = 0; i < kLegacySlotGifts + 1; i++) {
        doc = doc.set(
          clock,
          Collections.gifts,
          'x$i',
          giftFields('nora', 'R$i'),
        );
      }
      Future<OpenedSlot> open(Object? cap) async =>
          (await _rawSlot(family.leo, family.key, doc, cap: cap)).open(
            expectedListId: kListId,
            key: family.key,
            signingKey: family.leo.keys.publicKeys.signing,
          );
      // Sin «cap» (como un 1.0.5) no puede pasar de 64.
      await expectLater(open(null), throwsA(isA<SlotFormatException>()));
      expect(liveSurpriseGifts((await open(kSlotCapacity)).doc), 65);
      expect((await open(kSlotCapacity)).cap, kSlotCapacity);
      for (final bad in [0, -1, '2', 2.5, true]) {
        await expectLater(
          open(bad),
          throwsA(isA<SlotFormatException>()),
          reason: '$bad',
        );
      }
    });

    test('ataque N4: Nora no puede bloquear la activación con 202 regalos y '
        'uno enorme, y ninguno se queda en público', () {
      var many = common;
      for (var i = 0; i < kMaxSurpriseGifts + 1; i++) {
        many = many.set(
          clockOf('nora-phone', 200),
          Collections.gifts,
          'n${i.toString().padLeft(3, '0')}',
          giftFields('nora', 'R$i'),
        );
      }
      many = many.set(
        clockOf('nora-phone', 200),
        Collections.gifts,
        'zz-enorme',
        giftFields('nora', 'x' * 2500),
      );
      final t = activate(many);
      expect(t.policy, on1);
      expect(publishedPolicy(t.common, 'nora'), on1);
      expect(publicGiftsOfNora(t.common), isEmpty);
      expect(t.common.canonicalJson(), isNot(contains('xxxxxxxx')));
      expect(liveOwnSurpriseGifts(t.scope), kMaxSurpriseGifts);
      expect(liveMovedInGifts(t.scope), 2);
      expect(t.droppedGiftIds, ['zz-enorme']);
      expect(t.overflow.single['title'], hasLength(2500));
      expect(scopeFitsInSlot(t.scope, 'nora'), isTrue);
      // Y lo de Aritz no se toca.
      expect(t.common.record(Collections.gifts, 'g2')!['title'], 'Balón');
    });
  });

  group('compactar lápidas (req. 17)', () {
    test('una lápida se quita cuando todos los que tienen derecho la conocen, '
        'y nada resucita', () async {
      final base = scopeWith(clockOf('aritz-phone', 1000), [
        'Peonza',
        'Cometa',
      ]);
      var slots = await family.setOf([
        await seal(family.aritz, base, revision: 1),
        await seal(family.leo, base, revision: 1),
      ]);
      bool hasTomb(PublishedSlot p) =>
          p.sealed.record(Collections.gifts, 's0')?.isDeleted ?? false;
      // Aritz borra s0. Leo todavía lo tiene vivo: la lápida se queda.
      var opened = await openAs(family.aritz, slots);
      var pa = await publishAs(
        family.aritz,
        slots,
        opened,
        opened.doc.delete(
          clockOf('aritz-phone', 2000),
          Collections.gifts,
          's0',
        ),
        now: 2000,
      );
      expect(hasTomb(pa), isTrue);
      slots = await withSlot(slots, pa.slot);
      opened = await openAs(family.aritz, slots);
      pa = await publishAs(family.aritz, slots, opened, opened.doc, now: 3000);
      expect(hasTomb(pa), isTrue, reason: 'Leo aún no la ha visto');
      slots = await withSlot(slots, pa.slot);
      // Leo la recibe y publica: él aún no la había publicado, así que la
      // conserva.
      var openedLeo = await openAs(family.leo, slots);
      var pl = await publishAs(
        family.leo,
        slots,
        openedLeo,
        openedLeo.doc,
        now: 4000,
      );
      expect(hasTomb(pl), isTrue);
      slots = await withSlot(slots, pl.slot);
      // Ahora los dos la tienen publicada: Aritz la quita.
      opened = await openAs(family.aritz, slots);
      pa = await publishAs(family.aritz, slots, opened, opened.doc, now: 5000);
      expect(pa.sealed.record(Collections.gifts, 's0'), isNull);
      slots = await withSlot(slots, pa.slot);
      // Y Leo, que ve que Aritz ya había fusionado su slot, también.
      openedLeo = await openAs(family.leo, slots);
      pl = await publishAs(
        family.leo,
        slots,
        openedLeo,
        openedLeo.doc,
        now: 6000,
      );
      expect(pl.sealed.record(Collections.gifts, 's0'), isNull);
      slots = await withSlot(slots, pl.slot);
      final end = await openAs(family.aritz, slots);
      expect(end.doc.record(Collections.gifts, 's0'), isNull);
      expect(liveSurpriseGifts(end.doc), 1);
      expect(end.doc.canonicalJson(), isNot(contains('Peonza')));
    });

    test('un slot lleno de lápidas se desbloquea al revocar al móvil que no '
        'contesta (rotación)', () async {
      final aunt = await Phone.create('tia-phone', 'leo', 4);
      final registry = await registryOf([
        family.aritz,
        family.leo,
        family.nora,
        aunt,
      ]);
      final view = await family.aritz.viewOf(registry);
      expect(view.entitledDevices('nora'), hasLength(3));
      final old = tombstones(1500, 't');
      final all = old.merge(tombstones(1500, 'u'));
      expect(scopeFitsInSlot(old, 'nora'), isTrue);
      expect(scopeFitsInSlot(all, 'nora'), isFalse);
      // Aritz y Leo ya publicaron las primeras; la tía nunca publica.
      final slots = (await SlotSet.verified([
        await seal(family.aritz, old, revision: 1),
        await seal(family.leo, old, revision: 1),
      ], view: view)).$1;
      var opened = await openAs(family.aritz, slots, view: view);
      await expectLater(
        publishAs(family.aritz, slots, opened, all, now: 5000, view: view),
        throwsA(isA<SurpriseSlotFullException>()),
      );
      // Se revoca a la tía: época nueva, clave nueva y compactación.
      final revoked = (await revokeDevice(
        registry: registry,
        view: view,
        myKeys: family.aritz.keys,
        deviceId: aunt.id,
      )).registry;
      final view2 = await family.aritz.viewOf(revoked);
      final rotation = await rotateSurpriseKeys(
        keyring: family.authorizedKeyring,
        view: view2,
        keys: family.aritz.keys,
      );
      expect([for (final b in rotation.bundles) b.toDevice], ['leo-phone']);
      opened = await openAs(
        family.aritz,
        slots,
        keyring: rotation.keyring,
        view: view2,
      );
      final published = await publishAs(
        family.aritz,
        slots,
        opened,
        all,
        now: 6000,
        keyring: rotation.keyring,
        view: view2,
      );
      expect(published.slot.header.epoch, 2);
      expect(published.sealed.collections[Collections.gifts]!.keys.toSet(), {
        for (var i = 0; i < 1500; i++) 'u$i',
      });
    });

    test(
      'sin el slot de alguno de los que tienen derecho no se quita nada',
      () async {
        final base = scopeWith(clockOf('aritz-phone', 1000), ['Peonza']);
        final dead = base.delete(
          clockOf('aritz-phone', 2000),
          Collections.gifts,
          's0',
        );
        final slots = await family.setOf([
          await seal(family.aritz, dead, revision: 1),
        ]);
        final opened = await openAs(family.aritz, slots);
        final p = await publishAs(
          family.aritz,
          slots,
          opened,
          opened.doc,
          now: 3000,
        );
        expect(p.sealed.record(Collections.gifts, 's0')!.isDeleted, isTrue);
      },
    );
  });

  group('rotación y cambio de persona (req. 4)', () {
    test('quien pasa a ser de Nora purga su llavero; los demás rotan y no le '
        'mandan la clave nueva', () async {
      final on = activate(common);
      final slots = await family.setOf([
        await seal(family.aritz, on.scope, revision: 1),
        await seal(family.leo, on.scope, revision: 1),
      ]);
      final changed = await changePerson(
        registry: family.registry,
        view: family.viewOf(family.leo),
        myKeys: family.leo.keys,
        personId: 'nora',
      );
      expect(changed.rotates, isTrue);
      // El móvil que cambia: fuera las claves de Nora.
      final leoView = await family.leo.viewOf(changed.registry);
      final purge = await rotateSurpriseKeys(
        keyring: family.authorizedKeyring,
        view: leoView,
        keys: family.leo.keys,
      );
      expect(purge.purgedPeople, ['nora']);
      expect(purge.keyring.people, isEmpty);
      expect(purge.bundles, isEmpty);
      // Aritz: época 2, clave nueva, ningún paquete (Leo no tiene derecho,
      // ni antes ni después de que lo aprueben como móvil de Nora).
      var view = await family.aritz.viewOf(changed.registry);
      expect(view.epoch, 2);
      final rotation = await rotateSurpriseKeys(
        keyring: family.authorizedKeyring,
        view: view,
        keys: family.aritz.keys,
      );
      expect(rotation.bundles, isEmpty);
      expect(rotation.purgedPeople, isEmpty);
      final again = await rotateSurpriseKeys(
        keyring: rotation.keyring,
        view: view,
        keys: family.aritz.keys,
      );
      expect(identical(again.keyring, rotation.keyring), isTrue);
      view = await family.aritz.viewOf(
        (await approveDevice(
          registry: changed.registry,
          view: view,
          myKeys: family.aritz.keys,
          record: changed.registry.recordByDigest(
            view.pending.single.recordDigest,
          )!,
        )).registry,
      );
      expect(view.entitledDevices('nora'), ['aritz-phone']);
      // El slot viejo de Leo ya no cuenta, y lo nuevo de Aritz no se abre
      // con la clave que Leo pudo copiarse antes.
      final opened = await openAs(
        family.aritz,
        slots,
        keyring: rotation.keyring,
        view: view,
      );
      expect(opened.ignoredWriters, ['leo-phone']);
      final published = await publishAs(
        family.aritz,
        slots,
        opened,
        addSurpriseGift(
          opened.doc,
          clockOf('aritz-phone', 7000),
          'nuevo',
          giftFields('nora', 'Sorpresa nueva'),
        ),
        now: 7000,
        keyring: rotation.keyring,
        view: view,
      );
      await expectLater(
        published.slot.open(
          expectedListId: kListId,
          key: family.key,
          signingKey: family.aritz.keys.publicKeys.signing,
        ),
        throwsA(isA<SlotWrongScopeException>()),
      );
      expect(
        await openScope(
          personId: 'nora',
          slots: await withSlot(slots, published.slot, view: view),
          keyring: family.authorizedKeyring,
          view: await family.leo.viewOf(changed.registry),
        ),
        isNull,
      );
    });

    test('un móvil que llega después recibe la clave de la época actual solo '
        'cuando alguien con derecho lo ha aprobado', () async {
      final second = await Phone.create('leo-2', 'leo', 4);
      final record = await second.record();
      // Emparejado por Nora: es de la familia, pero sin derecho.
      var registry = (await approveDevice(
        registry: family.registry,
        view: family.viewOf(family.nora),
        myKeys: family.nora.keys,
        record: record,
      )).registry;
      Future<List<KeyBundle>> share(String to) async =>
          (await shareSurpriseKeysWith(
            deviceId: to,
            keyring: family.authorizedKeyring,
            view: await family.aritz.viewOf(registry),
            keys: family.aritz.keys,
          )).bundles;
      expect(await share('leo-2'), isEmpty);
      expect(await share('nora-phone'), isEmpty);
      expect(await share('aritz-phone'), isEmpty);
      // Aritz lo confirma (y el móvil nuevo a Aritz): ya se le puede dar.
      registry = (await approveDevice(
        registry: registry,
        view: await family.aritz.viewOf(registry),
        myKeys: family.aritz.keys,
        record: record,
      )).registry;
      registry = (await approveDevice(
        registry: registry,
        view: await second.viewOf(registry),
        myKeys: second.keys,
        record: registry.recordByDigest(family.view.self.recordDigest)!,
      )).registry;
      final shared = await shareSurpriseKeysWith(
        deviceId: 'leo-2',
        keyring: family.authorizedKeyring,
        view: await family.aritz.viewOf(registry),
        keys: family.aritz.keys,
      );
      expect(shared.bundles, hasLength(1));
      final key = await shared.bundles.single.openSurpriseKey(
        mine: second.keys,
        view: await second.viewOf(registry),
      );
      expect(key.bytes, family.key.bytes);
      // Los dos saben que ahora la conoce también el móvil nuevo.
      expect(key.audience, ['aritz-phone', 'leo-2', 'leo-phone']);
      expect(shared.keyring.keys.single.audience, key.audience);
      // Quien no tiene la clave de la época actual no reparte nada.
      expect(
        (await shareSurpriseKeysWith(
          deviceId: 'leo-2',
          keyring: SurpriseKeyring.empty,
          view: await family.aritz.viewOf(registry),
          keys: family.aritz.keys,
        )).bundles,
        isEmpty,
      );
    });
  });

  group('revisiones con el reloj adelantado (hallazgo 12)', () {
    const now = 1800000000000;
    final at = Clock.fixed(
      DateTime.fromMillisecondsSinceEpoch(now, isUtc: true),
    );

    test('un slot con la revisión más de un día por delante no entra (si '
        'entrara, su escritor no podría publicar uno más nuevo)', () {
      return withClock(at, () async {
        final limit = now + kMaxSlotClockSkew.inMilliseconds;
        final ahead = await seal(
          family.aritz,
          FamilyDoc.empty(kListId),
          revision: limit + 1,
        );
        await expectLater(
          SlotSet.empty.acceptVerified(ahead, view: family.view),
          throwsA(isA<SlotWrongScopeException>()),
        );
        final (set, rejected) = await SlotSet.verified([
          ahead,
        ], view: family.view);
        expect(rejected, 1);
        expect(set.all, isEmpty);
        final ok = await seal(
          family.aritz,
          FamilyDoc.empty(kListId),
          revision: limit,
        );
        expect(
          (await SlotSet.empty.acceptVerified(ok, view: family.view)).$2,
          SlotAcceptance.added,
        );
      });
    });
  });

  group('dos registros con la misma época (hallazgo 7)', () {
    test('ataque: Leo crea la clave de la época 2 desde un registro en el que '
        'la tía sigue con derecho; Aritz, que la ha revocado, abre el paquete '
        'pero no sella con esa clave', () async {
      final aunt = await Phone.create('tia-phone', 'leo', 4);
      final cousin = await Phone.create('primo-phone', 'aritz', 5);
      final base = await registryOf([
        family.aritz,
        family.leo,
        family.nora,
        aunt,
        cousin,
      ]);
      // Aritz revoca a la tía; Leo, sin saberlo, al primo: los dos, época 2.
      final mine = (await revokeDevice(
        registry: base,
        view: await family.aritz.viewOf(base),
        myKeys: family.aritz.keys,
        deviceId: aunt.id,
      )).registry;
      final his = (await revokeDevice(
        registry: base,
        view: await family.leo.viewOf(base),
        myKeys: family.leo.keys,
        deviceId: cousin.id,
      )).registry;
      final aritzView = await family.aritz.viewOf(mine);
      final leoView = await family.leo.viewOf(his);
      expect(aritzView.epoch, 2);
      expect(leoView.epoch, 2);
      final fromLeo = await createSurpriseKey(
        personId: 'nora',
        keyring: SurpriseKeyring.empty,
        view: leoView,
        keys: family.leo.keys,
      );
      expect(fromLeo.key.audience, contains('tia-phone'));
      final key = await fromLeo.bundles
          .singleWhere((b) => b.toDevice == family.aritz.id)
          .openSurpriseKey(mine: family.aritz.keys, view: aritzView);
      expect(key.audience, contains('tia-phone'));
      final keyring = SurpriseKeyring.empty.withKey(
        key,
        registryEpoch: aritzView.epoch,
      );
      final allowed = aritzView.entitledDevices('nora');
      // El primo sigue con derecho para Aritz (solo lo revocó Leo).
      expect(allowed, ['aritz-phone', 'leo-phone', 'primo-phone']);
      expect(keyring.sealingKeyFor('nora', 2, allowed: allowed), isNull);
      // Rotar crea otra que la tía no conoce, y con esa se sella.
      final rotation = await rotateSurpriseKeys(
        keyring: keyring,
        view: aritzView,
        keys: family.aritz.keys,
      );
      final sealing = rotation.keyring.sealingKeyFor(
        'nora',
        2,
        allowed: allowed,
      )!;
      expect(sealing.kid, isNot(key.kid));
      expect(sealing.audience, allowed);
      expect(
        [for (final b in rotation.bundles) b.toDevice],
        ['leo-phone', 'primo-phone'],
      );
      final published = await publishScope(
        slots: SlotSet.empty,
        opened: (await openScope(
          personId: 'nora',
          slots: SlotSet.empty,
          keyring: rotation.keyring,
          view: aritzView,
        ))!,
        view: aritzView,
        writerKeys: family.aritz.keys,
        keyring: rotation.keyring,
        policy: on1,
        doc: FamilyDoc.empty(kListId),
        nowMillis: 1000,
      );
      expect(published.slot.header.kid, sealing.kid);
    });
  });

  group('perder el derecho sin pasar a ser de la persona (hallazgo 2)', () {
    test('revocado por otro (un móvil robado revoca a Aritz): congela, no '
        'purga, y no abre ni publica', () async {
      final revoked = (await revokeDevice(
        registry: family.registry,
        view: family.viewOf(family.leo),
        myKeys: family.leo.keys,
        deviceId: family.aritz.id,
      )).registry;
      final view = await family.aritz.viewOf(revoked);
      expect(view.revokedByOthers, isTrue);
      final rotation = await rotateSurpriseKeys(
        keyring: family.authorizedKeyring,
        view: view,
        keys: family.aritz.keys,
      );
      expect(rotation.purgedPeople, isEmpty);
      expect(rotation.frozenPeople, ['nora']);
      expect(rotation.keyring.keys.single.bytes, family.key.bytes);
      expect(rotation.bundles, isEmpty);
      expect(
        await openScope(
          personId: 'nora',
          slots: SlotSet.empty,
          keyring: rotation.keyring,
          view: view,
        ),
        isNull,
      );
    });

    test('pendiente tras cambiar entre dos personas que no son Nora: '
        'congela', () async {
      final changed = await changePerson(
        registry: family.registry,
        view: family.view,
        myKeys: family.aritz.keys,
        personId: 'leo',
      );
      final view = await family.aritz.viewOf(changed.registry);
      expect(view.selfApproved, isFalse);
      final rotation = await rotateSurpriseKeys(
        keyring: family.authorizedKeyring,
        view: view,
        keys: family.aritz.keys,
      );
      expect(rotation.purgedPeople, isEmpty);
      expect(rotation.frozenPeople, ['nora']);
      expect(rotation.keyring.people, {'nora'});
    });

    test('su persona se ha borrado: congela', () async {
      final view = await family.aritz.viewOf(
        family.registry,
        people: {'leo', 'nora'},
      );
      final rotation = await rotateSurpriseKeys(
        keyring: family.authorizedKeyring,
        view: view,
        keys: family.aritz.keys,
      );
      expect(rotation.purgedPeople, isEmpty);
      expect(rotation.frozenPeople, ['nora']);
      expect(rotation.keyring.people, {'nora'});
    });

    test('pasar a ser de Nora sí purga', () async {
      final changed = await changePerson(
        registry: family.registry,
        view: family.view,
        myKeys: family.aritz.keys,
        personId: 'nora',
      );
      final rotation = await rotateSurpriseKeys(
        keyring: family.authorizedKeyring,
        view: await family.aritz.viewOf(changed.registry),
        keys: family.aritz.keys,
      );
      expect(rotation.purgedPeople, ['nora']);
      expect(rotation.keyring.people, isEmpty);
    });

    test('con un escritor congelado no se compactan lápidas, y su slot no se '
        'poda', () async {
      final base = scopeWith(clockOf('aritz-phone', 1000), ['Peonza']);
      final dead = base.delete(
        clockOf('aritz-phone', 2000),
        Collections.gifts,
        's0',
      );
      // Los dos ya tenían la lápida publicada: se podría compactar.
      final slots = await family.setOf([
        await seal(family.aritz, dead, revision: 1),
        await seal(family.leo, dead, revision: 1),
      ]);
      // Leo corrige su «Yo» (a Aritz) y queda pendiente.
      final changed = await changePerson(
        registry: family.registry,
        view: family.viewOf(family.leo),
        myKeys: family.leo.keys,
        personId: 'aritz',
      );
      final view = await family.aritz.viewOf(changed.registry);
      expect(view.member('leo-phone'), isNull);
      final opened = await openAs(family.aritz, slots, view: view);
      expect(opened.frozenWriters, ['leo-phone']);
      expect(
        compactScope(
          doc: opened.doc,
          opened: opened,
          view: view,
        ).record(Collections.gifts, 's0')!.isDeleted,
        isTrue,
      );
      expect(
        [for (final s in slots.pruned(view).slotsFor('nora')) s.header.writer],
        ['aritz-phone', 'leo-phone'],
      );
      // Con todos al día sí se compacta.
      expect(
        compactScope(
          doc: (await openAs(family.aritz, slots)).doc,
          opened: await openAs(family.aritz, slots),
          view: family.view,
        ).record(Collections.gifts, 's0'),
        isNull,
      );
    });
  });

  group('política falsificada sin slots que cuenten (hallazgo 3)', () {
    const off99 = PolicyState(hideOwnGifts: false, rev: 99);

    Future<DeviceRegistry> vouchAll(
      DeviceRegistry registry,
      List<(Phone, Phone)> pairs,
    ) async {
      var out = registry;
      for (final (by, to) in pairs) {
        out = await out.withVouch(
          await Vouch.create(
            keys: by.keys,
            voucher: await by.record(),
            record: await to.record(),
          ),
        );
      }
      return out;
    }

    FamilyDoc forge(FamilyDoc doc) =>
        writePublishedPolicy(doc, clockOf('nora-phone', 5000), 'nora', off99);

    bool blocked(
      FamilyDoc doc,
      SlotSet slots,
      RegistryView view, {
      SurpriseKeyring? keyring,
    }) => publicGiftsBlockedFor(
      common: doc,
      slots: slots,
      keyring: keyring ?? SurpriseKeyring.empty,
      view: view,
      personId: 'nora',
    );

    test(
      'ataque en estrella: Nora emparejó a Aritz y a Leo por separado; '
      'Leo rechaza el slot de Aritz y no se cree el «publicar» de Nora',
      () async {
        var registry = DeviceRegistry.empty(kListId);
        for (final p in [family.aritz, family.leo, family.nora]) {
          registry = await registry.withRecord(await p.record());
        }
        registry = await vouchAll(registry, [
          (family.nora, family.aritz),
          (family.aritz, family.nora),
          (family.nora, family.leo),
          (family.leo, family.nora),
        ]);
        final leoView = await family.leo.viewOf(registry);
        expect(leoView.entitled('aritz-phone', 'nora'), isNull);
        final on = activate(common);
        final (slots, rejected) = await SlotSet.verified([
          await seal(family.aritz, on.scope, revision: 1),
        ], view: leoView);
        expect(rejected, 1);
        final forged = forge(on.common);
        expect(blocked(forged, slots, leoView), isTrue);
        final p = await projectAs(family.leo, forged, slots, view: leoView);
        expect(p.lockedBlocks, [nora]);
        expect(p.policies['nora']!.hideOwnGifts, isTrue);
      },
    );

    test('ataque: tras podar los slots de un revocado, el «publicar» de Nora '
        'tampoco vale', () async {
      final on = activate(common);
      final slots = await family.setOf([
        await seal(family.aritz, on.scope, revision: 1),
      ]);
      final revoked = (await revokeDevice(
        registry: family.registry,
        view: family.viewOf(family.nora),
        myKeys: family.nora.keys,
        deviceId: family.aritz.id,
      )).registry;
      final view = await family.leo.viewOf(revoked);
      final pruned = slots.pruned(view);
      expect(pruned.slotsFor('nora'), isEmpty);
      expect(blocked(forge(on.common), pruned, view), isTrue);
    });

    test('ataque: un móvil sin persona guarda el slot del móvil falso de Nora '
        '(registrado como «leo») y no se cree su «publicar»', () async {
      final nobody = await Phone.create('sin-persona', null, 5);
      final fake = await Phone.create('nora-2', 'leo', 7);
      var registry = family.registry;
      registry = await registry.withRecord(await nobody.record());
      registry = await registry.withRecord(await fake.record());
      registry = await vouchAll(registry, [
        (family.aritz, nobody),
        (nobody, family.aritz),
        (family.nora, fake),
        (fake, family.nora),
      ]);
      final view = await nobody.viewOf(registry);
      // Lo guarda y lo reenvía (no lo abre)...
      final fakeSlot = await seal(
        fake,
        FamilyDoc.empty(kListId),
        revision: 1,
        policy: off99,
        key: SurpriseKey(
          personId: 'nora',
          epoch: 1,
          bytes: List<int>.filled(32, 7),
        ),
      );
      final (slots, rejected) = await SlotSet.verified([fakeSlot], view: view);
      expect(rejected, 0);
      expect(view.relayable('nora-2', 'nora'), isNotNull);
      // ...pero no autentica nada: oculta.
      expect(view.entitled('nora-2', 'nora'), isNull);
      expect(slots.authenticatedPolicy('nora', view), isNull);
      final forged = forge(activate(common).common);
      expect(blocked(forged, slots, view), isTrue);
      // Y para Aritz, que sí tiene cadena limpia, el slot falso no entra.
      await expectLater(
        family.setOf([fakeSlot]).then((s) => s.slotsFor('nora').isEmpty),
        completion(isTrue),
      );
    });

    test('sin registro de política, ni slots, ni clave: no hay protección', () {
      expect(
        blocked(common, SlotSet.empty, family.viewOf(family.leo)),
        isFalse,
      );
      expect(
        blocked(
          common,
          SlotSet.empty,
          family.view,
          keyring: family.authorizedKeyring,
        ),
        isTrue,
      );
    });
  });

  group('segunda revisión de la fase 2a (N3 y 7)', () {
    test('ataque (N3): un ladrón que Aritz emparejó avala una cadena de '
        'móviles falsos con derecho y les hace escribir slots: el conjunto '
        'no pasa del tope, al revocarlo se podan, y un escritor con derecho '
        'desaloja a los que ya no lo tienen', () async {
      final thief = await Phone.create('ladron', 'aritz', 20);
      final rThief = await thief.record();
      final rAritz = await family.aritz.record();
      var registry = await family.registry.withRecord(rThief);
      for (final (by, voucher, record) in [
        (family.aritz, rAritz, rThief),
        (thief, rThief, rAritz),
      ]) {
        registry = await registry.withVouch(
          await Vouch.create(keys: by.keys, voucher: voucher, record: record),
        );
      }
      // Una cadena de 33 falsos «de Aritz», cada uno avalado por el
      // anterior: todos con derecho a las sorpresas de Nora y de Leo.
      final junk = await Phone.create('basura', 'aritz', 21);
      final fakes = <Phone>[];
      var prev = (thief, rThief);
      for (var i = 0; i < 33; i++) {
        final fake = Phone('falso-$i', 'aritz', junk.keys);
        final r = await fake.record();
        registry = await registry.withRecord(r);
        registry = await registry.withVouch(
          await Vouch.create(keys: prev.$1.keys, voucher: prev.$2, record: r),
        );
        fakes.add(fake);
        prev = (fake, r);
      }
      // Con cuatro personas más, cada falso escribe seis slots: entre todos
      // pasan de kMaxSlotsPerList (128 desde la 1.0.6).
      const extra = ['p0', 'p1', 'p2', 'p3'];
      final view = await family.aritz.viewOf(
        registry,
        people: {...kPeople, ...extra},
      );
      expect(view.entitled('falso-32', 'nora'), isNotNull);
      expect(view.entitled('falso-32', 'leo'), isNotNull);
      expect(view.entitled('falso-32', 'p3'), isNotNull);
      final keys = [
        family.key,
        SurpriseKey(personId: 'leo', epoch: 1, bytes: List<int>.filled(32, 43)),
        for (final (i, person) in extra.indexed)
          SurpriseKey(
            personId: person,
            epoch: 1,
            bytes: List<int>.filled(32, 50 + i),
          ),
      ];
      expect(keys.length * fakes.length, greaterThan(kMaxSlotsPerList));
      final empty = FamilyDoc.empty(kListId);
      var slots = SlotSet.empty;
      var rejected = 0;
      for (final fake in fakes) {
        for (final key in keys) {
          final slot = await seal(fake, empty, revision: 1, key: key);
          try {
            slots = (await slots.acceptVerified(slot, view: view)).$1;
          } on SlotFormatException {
            rejected++;
          }
        }
      }
      expect(slots.all, hasLength(kMaxSlotsPerList));
      expect(rejected, keys.length * fakes.length - kMaxSlotsPerList);
      // Lo que se guarda se vuelve a leer (antes, con más de 64, el almacén
      // local no podía leerlo).
      expect(SlotSet.fromLocalStoreJson(slots.toJson()).sameAs(slots), isTrue);
      // Aritz revoca al ladrón: lo que solo colgaba de él ya no es de la
      // familia (ni pendiente), y sus slots se podan.
      final revoked = (await revokeDevice(
        registry: registry,
        view: view,
        myKeys: family.aritz.keys,
        deviceId: 'ladron',
      )).registry;
      final after = await family.aritz.viewOf(revoked);
      expect(after.pending, isEmpty);
      expect(after.device('falso-0'), isNull);
      expect(slots.pruned(after).all, isEmpty);
      // Sin podar, un escritor con derecho desaloja a uno que ya no lo tiene.
      final leoSlot = await seal(family.leo, empty, revision: 1);
      final (withLeo, acceptance) = await slots.acceptVerified(
        leoSlot,
        view: after,
      );
      expect(acceptance, SlotAcceptance.added);
      expect(withLeo.all, hasLength(kMaxSlotsPerList));
      expect(withLeo.slotOf('nora', 'leo-phone'), isNotNull);
    });

    test('7: las candidatas que ya no sirven para sellar no cuentan para el '
        'tope, así que rotar siempre puede crear una', () async {
      // 16 candidatas de la época 1 que conoce un móvil que ya no tiene
      // derecho (creadas desde otro estado del registro).
      final stale = SurpriseKeyring([
        for (var i = 0; i < kMaxKeyCandidates; i++)
          SurpriseKey(
            personId: 'nora',
            epoch: 1,
            bytes: List<int>.filled(32, 100 + i),
            audience: const ['aritz-phone', 'ladron'],
          ),
      ]);
      // Sin saber quién tiene derecho, el tope cuenta todas (como antes).
      expect(
        () => stale.withKey(
          SurpriseKey.generate('nora', 1, audience: ['aritz-phone']),
          registryEpoch: 1,
        ),
        throwsA(isA<KeyringConflictException>()),
      );
      final rotation = await rotateSurpriseKeys(
        keyring: stale,
        view: family.view,
        keys: family.aritz.keys,
      );
      final sealing = rotation.keyring.sealingKeyFor(
        'nora',
        1,
        allowed: family.view.entitledDevices('nora'),
      );
      expect(sealing, isNotNull);
      expect(rotation.bundles, hasLength(1));
      // Lo que se guarda tiene tope: con el llavero lleno de candidatas que
      // no sirven, entra la nueva y sale la que no sirve de kid más alto.
      var full = stale;
      for (var i = kMaxKeyCandidates; i < kMaxStoredKeyCandidates; i++) {
        full = full.withKey(
          SurpriseKey(
            personId: 'nora',
            epoch: 1,
            bytes: List<int>.filled(32, 100 + i),
            audience: const ['aritz-phone', 'ladron'],
          ),
          registryEpoch: 1,
          allowed: const ['aritz-phone', 'leo-phone'],
        );
      }
      expect(full.keys, hasLength(kMaxStoredKeyCandidates));
      final fresh = SurpriseKey.generate(
        'nora',
        1,
        audience: ['aritz-phone', 'leo-phone'],
      );
      final next = full.withKey(
        fresh,
        registryEpoch: 1,
        allowed: const ['aritz-phone', 'leo-phone'],
      );
      expect(next.keys, hasLength(kMaxStoredKeyCandidates));
      expect(next.keyFor('nora', 1, fresh.kid), isNotNull);
      final highest = (full.keys.map((k) => k.kid).toList()..sort()).last;
      expect(next.keyFor('nora', 1, highest), isNull);
    });
  });

  group('relojes y vectores (req. 24 y 25)', () {
    test(
      'tras publicar, el reloj público queda por delante de lo publicado: '
      'una edición pública posterior gana',
      () => withClock(_atTestTime, () {
        final publicClock = clockOf('aritz-phone', 1000);
        final scopeClock = clockOf('aritz-phone', 1000);
        final on = activateProtection(
          common: common,
          scope: FamilyDoc.empty(kListId),
          key: family.key,
          publicClock: publicClock,
          scopeClock: scopeClock,
        );
        // Ediciones secretas, con marcas muy por delante del reloj público.
        final late = clockOf('leo-phone', 900000);
        final scope = addSurpriseGift(on.scope, late, 'g1', {
          'title': 'Muñeca 2',
        });
        expect(late.last.compareTo(publicClock.last), greaterThan(0));
        final off = deactivateProtection(
          common: on.common,
          scope: scope,
          key: family.key,
          publicClock: publicClock,
          scopeClock: scopeClock,
          authenticated: on.policy,
        );
        expect(
          publicClock.last.compareTo(off.common.maxStamp!),
          greaterThanOrEqualTo(0),
        );
        final published = publicGiftsOfNora(off.common).single;
        expect(published['title'], 'Muñeca 2');
        // Alguien la edita en público con ese reloj; al fusionar con la copia
        // de otro móvil, gana la edición.
        final edited = off.common.set(
          publicClock,
          Collections.gifts,
          published.id,
          {'title': 'Muñeca 3'},
        );
        expect(
          off.common
              .merge(edited)
              .record(Collections.gifts, published.id)!['title'],
          'Muñeca 3',
        );
      }),
    );

    test(
      'reconciliar una desactivación también adelanta el reloj '
      'público',
      () => withClock(_atTestTime, () async {
        final on = activate(common);
        final late = clockOf('leo-phone', 900000);
        final scope = addSurpriseGift(on.scope, late, 'g1', {
          'title': 'Muñeca 2',
        });
        final off = deactivateProtection(
          common: on.common,
          scope: FamilyDoc.empty(kListId),
          key: family.key,
          publicClock: clockOf('aritz-phone', 2000),
          scopeClock: clockOf('aritz-phone', 2000),
          authenticated: on.policy,
        );
        // Leo tenía la muñeca en su slot y reconcilia la desactivación.
        final slots = await family.setOf([
          await seal(family.aritz, off.scope, revision: 2, policy: off.policy),
          await seal(family.leo, scope, revision: 1),
        ]);
        final opened = await openAs(family.leo, slots);
        final publicClock = clockOf('leo-phone', 3000);
        final t = reconcileProtection(
          common: off.common,
          scope: opened.doc,
          opened: opened,
          key: family.key,
          publicClock: publicClock,
          scopeClock: clockOf('leo-phone', 3000),
        );
        expect(publicGiftsOfNora(t.common).single['title'], 'Muñeca 2');
        expect(
          publicClock.last.compareTo(t.common.maxStamp!),
          greaterThanOrEqualTo(0),
        );
      }),
    );

    test('HMAC-SHA256: vectores del RFC 4231', () {
      String mac(List<int> key, List<int> data) => [
        for (final b in hmacSha256ForTesting(key, data))
          b.toRadixString(16).padLeft(2, '0'),
      ].join();
      expect(
        mac(List<int>.filled(20, 0x0b), utf8.encode('Hi There')),
        'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7',
      );
      expect(
        mac(utf8.encode('Jefe'), utf8.encode('what do ya want for nothing?')),
        '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843',
      );
      expect(
        mac(List<int>.filled(20, 0xaa), List<int>.filled(50, 0xdd)),
        '773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe',
      );
      expect(
        mac(
          List<int>.filled(131, 0xaa),
          utf8.encode('Test Using Larger Than Block-Size Key - Hash Key First'),
        ),
        '60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54',
      );
    });

    test('el id al publicar no se puede adivinar sin abrir el bloque y no '
        'depende de la clave con la que selle cada móvil (B2)', () {
      String id({String giftId = 'g1', String salt = 'sal', int rev = 2}) =>
          publishedGiftId(
            listId: kListId,
            personId: 'nora',
            giftId: giftId,
            salt: salt,
            rev: rev,
          );
      expect(id(), id());
      expect(id(), isNot(id(salt: 'otra')));
      expect(id(), isNot(id(rev: 3)));
      expect(id(), isNot(id(giftId: 'g2')));
      expect(id(), matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-8[0-9a-f]{3}-')));
      // Un regalo que vino del común lleva su sal dentro del bloque, y la
      // sal sale de la clave: Nora, que conoce g1, no puede calcularla.
      final a = activate(common);
      final b = activate(
        common,
        key: SurpriseKey(
          personId: 'nora',
          epoch: 1,
          bytes: List<int>.filled(32, 43),
        ),
      );
      final saltA = a.scope.record(Collections.gifts, 'g1')![kPublishSaltField];
      final saltB = b.scope.record(Collections.gifts, 'g1')![kPublishSaltField];
      expect(saltA, isA<String>());
      expect(saltA, isNot(saltB));
      expect(a.common.canonicalJson(), isNot(contains(saltA! as String)));
      // Al publicarse no salen ni la sal ni la marca del cupo.
      final off = deactivateProtection(
        common: a.common,
        scope: a.scope,
        key: family.key,
        publicClock: clockOf('aritz-phone', 2000),
        scopeClock: clockOf('aritz-phone', 2000),
        authenticated: a.policy,
      );
      final published = publicGiftsOfNora(off.common).single;
      expect(published.id, id(salt: saltA as String));
      expect(published[kPublishSaltField], isNull);
      expect(published[kMovedInField], isNull);
    });
  });
}

/// La hora de los relojes de las pruebas ([kFuture]): sin esto, `receive`
/// ignora sus marcas por adelantadas.
final _atTestTime = Clock.fixed(
  DateTime.fromMillisecondsSinceEpoch(kFuture, isUtc: true),
);

/// Un slot hecho a mano, sin los límites de `SealedSlot.seal`.
Future<SealedSlot> _rawSlot(
  Phone writer,
  SurpriseKey key,
  FamilyDoc doc, {
  Object? cap,
}) async {
  final header = SlotHeader(
    listId: kListId,
    personId: key.personId,
    epoch: key.epoch,
    writer: writer.id,
    revision: 1,
    policy: const PolicyState(hideOwnGifts: true, rev: 1),
    kid: key.kid,
  ).toBytes();
  final compressed = Deflate(
    utf8.encode(
      canonicalJsonOf(<String, Object?>{
        'cap': ?cap,
        'd': doc.toJson(),
        's': <String, Object?>{},
        'v': 2,
      }),
    ),
  ).getBytes();
  final plain = Uint8List(kSlotPlainBytes);
  ByteData.sublistView(plain).setUint32(0, compressed.length);
  plain.setRange(4, 4 + compressed.length, compressed);
  final nonce = List<int>.filled(12, 1);
  final box = await AesGcm.with256bits().encrypt(
    plain,
    secretKey: SecretKey(key.bytes),
    nonce: nonce,
    aad: header,
  );
  final unsigned = [...header, ...nonce, ...box.cipherText, ...box.mac.bytes];
  final signature = await writer.keys.sign([
    ...utf8.encode('gift-huddle-slot-v2'),
    0,
    ...unsigned,
  ]);
  return SealedSlot.parse([...unsigned, ...signature]);
}
