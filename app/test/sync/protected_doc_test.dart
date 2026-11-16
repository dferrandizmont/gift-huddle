import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/envelope.dart' as env;
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/protected_doc.dart';
import 'package:regalos/core/sync/protected_envelope.dart';

import 'protected_harness.dart';

/// Bloque de sorpresas: fusión de slots, relevo por el móvil excluido,
/// transiciones sin resurrecciones, proyección autorizada (ADR 0004) y los
/// ataques de la revisión de seguridad de la fase 1.
void main() {
  late Family family;
  setUp(() async => family = await Family.create());

  const on1 = PolicyState(hideOwnGifts: true, rev: 1);

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

  Future<OpenedScope> openAs(Phone phone, SlotSet slots) async =>
      (await openScope(
        personId: 'nora',
        slots: slots,
        keyring: family.authorizedKeyring,
        view: family.viewOf(phone),
      ))!;

  Future<AuthorizedProjection> project(
    Phone phone,
    FamilyDoc common,
    SlotSet slots, {
    SurpriseKeyring? keyring,
  }) => projectAuthorized(
    common: common,
    slots: slots,
    keyring:
        keyring ??
        (phone == family.nora
            ? SurpriseKeyring.empty
            : family.authorizedKeyring),
    view: family.viewOf(phone),
  );

  List<String> titlesIn(AuthorizedProjection p) =>
      [for (final g in p.view.gifts) g.title]..sort();

  Future<SlotSet> merged(SlotSet a, SlotSet b) async =>
      (await a.merge(b.all, view: family.view)).$1;

  group('fusión de slots', () {
    late SealedSlot aritz1;
    late SealedSlot aritz2;
    late SealedSlot leo1;
    late SealedSlot leo1bis;
    setUp(() async {
      final base = scopeWith(clockOf('aritz-phone', 1000), ['Peonza']);
      aritz1 = await seal(family.aritz, base, revision: 1);
      aritz2 = await seal(
        family.aritz,
        base.set(clockOf('aritz-phone', 2000), Collections.gifts, 's0', {
          'title': 'Peonza azul',
        }),
        revision: 2,
      );
      leo1 = await seal(
        family.leo,
        base.set(clockOf('leo-phone', 3000), Collections.gifts, 's0', {
          'note': 'Con cuerda',
        }),
        revision: 1,
      );
      // Misma revisión, otro contenido (un error del escritor).
      leo1bis = await seal(
        family.leo,
        base.set(clockOf('leo-phone', 3500), Collections.gifts, 's0', {
          'note': 'Sin cuerda',
        }),
        revision: 1,
      );
    });

    test('conmutativa, asociativa e idempotente', () async {
      final a = await family.setOf([aritz1, leo1]);
      final b = await family.setOf([aritz2]);
      final c = await family.setOf([leo1bis, aritz1]);
      expect((await merged(a, b)).sameAs(await merged(b, a)), isTrue);
      expect((await merged(a, c)).sameAs(await merged(c, a)), isTrue);
      expect(
        (await merged(
          await merged(a, b),
          c,
        )).sameAs(await merged(a, await merged(b, c))),
        isTrue,
      );
      expect((await merged(a, a)).sameAs(a), isTrue);
      final ab = await merged(a, b);
      expect((await merged(ab, b)).sameAs(ab), isTrue);
    });

    test('se queda el último de cada escritor y no descarta al otro', () async {
      final set = await merged(
        await family.setOf([aritz1, leo1]),
        await family.setOf([aritz2]),
      );
      expect(set.slotOf('nora', 'aritz-phone')!.header.revision, 2);
      expect(set.slotOf('nora', 'leo-phone'), isNotNull);
      expect(set.slotsFor('nora'), hasLength(2));
      expect(set.nextRevision('nora', 'aritz-phone', nowMillis: 0), 3);
    });

    test('repetir una revisión antigua: rechazado y sin cambios', () async {
      final set = await family.setOf([aritz2]);
      Future<(SlotSet, SlotAcceptance)> accept(SlotSet s, SealedSlot slot) =>
          s.acceptVerified(slot, view: family.view);
      final (after, result) = await accept(set, aritz1);
      expect(result, SlotAcceptance.stale);
      expect(after.sameAs(set), isTrue);
      expect((await accept(set, aritz2)).$2, SlotAcceptance.duplicate);
      expect(
        (await accept(await family.setOf([aritz1]), aritz2)).$2,
        SlotAcceptance.replaced,
      );
      expect(
        (await accept(await family.setOf([leo1]), leo1bis)).$2,
        SlotAcceptance.conflict,
      );
    });

    test('los documentos descifrados también cumplen las leyes', () async {
      final orders = [
        [aritz1, leo1, aritz2],
        [aritz2, leo1, aritz1],
        [leo1, aritz2],
        [leo1, aritz1, aritz2, leo1, aritz2],
      ];
      final results = <String>{};
      for (final order in orders) {
        final scope = await openAs(family.aritz, await family.setOf(order));
        results.add(scope.doc.canonicalJson());
        expect(
          scope.doc.merge(scope.doc).canonicalJson(),
          scope.doc.canonicalJson(),
        );
      }
      expect(results, hasLength(1));
      final scope = await openAs(
        family.leo,
        await family.setOf([aritz2, leo1]),
      );
      final gift = scope.doc.record(Collections.gifts, 's0')!;
      expect(gift['title'], 'Peonza azul');
      expect(gift['note'], 'Con cuerda');
    });

    test(
      'ataque M3: un slot falso con revisión 999 no desplaza al bueno',
      () async {
        // Cabecera de Aritz con revisión 999 y todo lo demás a ceros.
        final forged = [...aritz1.bytes];
        final header = SlotHeader(
          listId: kListId,
          personId: 'nora',
          epoch: 1,
          writer: 'aritz-phone',
          revision: 999,
          policy: on1,
          kid: family.key.kid,
        ).toBytes();
        forged.setRange(0, header.length, header);
        for (var i = header.length; i < forged.length; i++) {
          forged[i] = 0;
        }
        final fake = SealedSlot.parse(forged);
        expect(fake.header.revision, 999);
        final good = await family.setOf([aritz1]);
        await expectLater(
          good.acceptVerified(fake, view: family.view),
          throwsA(isA<SlotAuthException>()),
        );
        final (after, rejected) = await good.merge([fake], view: family.view);
        expect(rejected, 1);
        expect(after.slotOf('nora', 'aritz-phone')!.header.revision, 1);
        // Desde JSON (red, fichero o copia) tampoco entra.
        final (fromJson, dropped) = await SlotSet.fromJsonVerified([
          env.encodeBase64Url(fake.bytes),
          env.encodeBase64Url(aritz1.bytes),
        ], view: family.view);
        expect(dropped, 1);
        expect(fromJson.slotOf('nora', 'aritz-phone')!.header.revision, 1);
      },
    );

    test('firma falsa, escritor desconocido u otra lista: no entra', () async {
      final bytes = [...aritz1.bytes];
      bytes[bytes.length - 1] ^= 1;
      await expectLater(
        SlotSet.empty.acceptVerified(
          SealedSlot.parse(bytes),
          view: family.view,
        ),
        throwsA(isA<SlotAuthException>()),
      );
      // Un escritor que el registro no conoce (aquí, un registro en el que
      // solo está Leo).
      final alone = await family.leo.viewOf(
        await DeviceRegistry.empty(kListId)
            .withRecord(await family.leo.record()),
      );
      await expectLater(
        SlotSet.empty.acceptVerified(aritz1, view: alone),
        throwsA(isA<SlotAuthException>()),
      );
      final other = await DeviceRecord.create(
        keys: family.aritz.keys,
        listId: 'otra',
        deviceId: family.aritz.id,
        personId: 'aritz',
      );
      await expectLater(
        SlotSet.empty.acceptVerified(
          aritz1,
          view: await (await DeviceRegistry.empty('otra').withRecord(other))
              .viewFor(
                me: family.aritz.id,
                mySigningKey: family.aritz.keys.publicKeys.signing,
                livePeople: kPeople,
              ),
        ),
        throwsA(isA<SlotWrongScopeException>()),
      );
      // Demasiados de una vez: no se mira ninguno.
      await expectLater(
        SlotSet.empty.merge(
          List.filled(kMaxSlotsPerList + 1, aritz1),
          view: family.view,
        ),
        throwsA(isA<SlotFormatException>()),
      );
      expect(
        () => parseSlotList(List.filled(kMaxSlotsPerList + 1, 'AA')),
        throwsFormatException,
      );
    });

    test('ida y vuelta por JSON (almacén local)', () async {
      final set = await family.setOf([aritz2, leo1]);
      final back = SlotSet.fromLocalStoreJson(
        jsonDecode(jsonEncode(set.toJson())),
      );
      expect(back.sameAs(set), isTrue);
    });
  });

  group('relevo por el móvil de Nora', () {
    test('dos escritores cambian campos distintos del mismo regalo y Nora '
        'reenvía sin abrir', () async {
      final aritzDoc = scopeWith(clockOf('aritz-phone', 1000), ['Puzle']);
      var noraSet = SlotSet.empty;
      Future<void> noraReceives(SealedSlot slot) async {
        noraSet = (await noraSet.acceptVerified(slot, view: family.view)).$1;
      }

      await noraReceives(await seal(family.aritz, aritzDoc, revision: 1));
      final leoView = await openAs(family.leo, noraSet);
      final leoDoc = leoView.doc.set(
        clockOf('leo-phone', 2000),
        Collections.gifts,
        's0',
        {'note': 'De 1000 piezas'},
      );
      final leoSlot = (await publishScope(
        slots: noraSet,
        opened: leoView,
        view: family.viewOf(family.leo),
        writerKeys: family.leo.keys,
        keyring: family.authorizedKeyring,
        policy: on1,
        doc: leoDoc,
        nowMillis: 1,
      )).slot;
      final aritzSlot = await seal(
        family.aritz,
        aritzDoc.set(clockOf('aritz-phone', 2500), Collections.gifts, 's0', {
          'title': 'Puzle del mapa',
        }),
        revision: 2,
      );
      await noraReceives(leoSlot);
      await noraReceives(aritzSlot);
      expect(
        await openScope(
          personId: 'nora',
          slots: noraSet,
          keyring: family.authorizedKeyring,
          view: family.viewOf(family.nora),
        ),
        isNull,
      );
      for (final phone in [family.aritz, family.leo]) {
        final scope = await openAs(phone, noraSet);
        final gift = scope.doc.record(Collections.gifts, 's0')!;
        expect(gift['title'], 'Puzle del mapa');
        expect(gift['note'], 'De 1000 piezas');
        expect(scope.unreadableWriters, isEmpty);
      }
    });

    test('borrar frente a editar dentro del slot: gana el borrado y no queda '
        'contenido', () async {
      final base = scopeWith(clockOf('aritz-phone', 1000), ['Cometa']);
      final deleted = await seal(
        family.aritz,
        base.delete(clockOf('aritz-phone', 2000), Collections.gifts, 's0'),
        revision: 2,
      );
      final edited = await seal(
        family.leo,
        base.set(clockOf('leo-phone', 9000), Collections.gifts, 's0', {
          'title': 'Cometa grande',
        }),
        revision: 1,
      );
      for (final order in [
        [deleted, edited],
        [edited, deleted],
      ]) {
        final scope = await openAs(family.aritz, await family.setOf(order));
        final gift = scope.doc.record(Collections.gifts, 's0')!;
        expect(gift.isDeleted, isTrue);
        expect(gift.hasTombstoneContent, isFalse);
        expect(scope.doc.canonicalJson(), isNot(contains('Cometa')));
      }
    });
  });

  group('activar y desactivar', () {
    late FamilyDoc common;
    setUp(() {
      final clock = clockOf('aritz-phone', 100);
      common = commonWithPeople(clock)
          .set(clock, Collections.gifts, 'g1', giftFields('nora', 'Muñeca'))
          .set(clock, Collections.gifts, 'g2', giftFields('aritz', 'Balón'));
    });

    ProtectionTransition activate(
      FamilyDoc common,
      FamilyDoc scope,
      String node,
      int millis, {
      PolicyState? authenticated,
    }) => activateProtection(
      common: common,
      scope: scope,
      key: family.key,
      publicClock: clockOf(node, millis),
      scopeClock: clockOf(node, millis),
      authenticated: authenticated,
    );

    test(
      'activar mueve sus regalos al bloque secreto y vacía los públicos',
      () {
        final t = activate(
          common,
          FamilyDoc.empty(kListId),
          'aritz-phone',
          1000,
        );
        expect(t.policy, const PolicyState(hideOwnGifts: true, rev: 1));
        expect(publishedPolicy(t.common, 'nora'), t.policy);
        expect(t.common.record(Collections.gifts, 'g1')!.isDeleted, isTrue);
        expect(t.common.canonicalJson(), isNot(contains('Muñeca')));
        expect(t.common.record(Collections.gifts, 'g2')!['title'], 'Balón');
        expect(liveSurpriseGifts(t.scope), 1);
        expect(t.overflow, isEmpty);
        // Conserva su id: en el común queda la lápida y en la vista manda el
        // secreto.
        final moved = t.scope.collections[Collections.gifts]!.values.single;
        expect(moved.id, 'g1');
        expect(moved['title'], 'Muñeca');
        expect(moved[kMovedInField], isNull);
        expect(
          moved.field('title')!.stamp,
          common.record(Collections.gifts, 'g1')!.field('title')!.stamp,
        );
      },
    );

    test('dos móviles con la clave que activan a la vez escriben lo mismo', () {
      final a = activate(common, FamilyDoc.empty(kListId), 'aritz-phone', 1000);
      final b = activate(common, FamilyDoc.empty(kListId), 'leo-phone', 1000);
      expect(a.scope.canonicalJson(), b.scope.canonicalJson());
      expect(liveSurpriseGifts(a.scope.merge(b.scope)), 1);
    });

    // B2 (el id al publicar no se puede adivinar): protected_phase2_test.

    test('B2: en la vista, el registro secreto sustituye al común del mismo '
        'id', () async {
      final t = activate(common, FamilyDoc.empty(kListId), 'aritz-phone', 1000);
      final movedId = t.scope.collections[Collections.gifts]!.keys.single;
      // Alguien intenta revivir en el común el registro con ese id: es una
      // lápida y lo sigue siendo.
      final colliding = t.common.set(
        clockOf('nora-phone', 9000),
        Collections.gifts,
        movedId,
        giftFields('nora', 'Señuelo'),
      );
      final slots = await family.setOf([
        await seal(family.aritz, t.scope, revision: 1),
      ]);
      final view = await project(family.aritz, colliding, slots);
      expect(titlesIn(view), ['Balón', 'Muñeca']);
    });

    test('ninguna resurrección al activar, desactivar y reactivar', () async {
      final oldCommon = common;
      // 1. Aritz activa.
      final on = activate(
        common,
        FamilyDoc.empty(kListId),
        'aritz-phone',
        1000,
      );
      final aritz1 = await seal(family.aritz, on.scope, revision: 1);
      final afterOld = on.common.merge(oldCommon);
      expect(afterOld.record(Collections.gifts, 'g1')!.isDeleted, isTrue);
      expect(afterOld.canonicalJson(), isNot(contains('Muñeca')));
      var slots = await family.setOf([aritz1]);
      expect(titlesIn(await project(family.nora, afterOld, slots)), ['Balón']);
      expect(titlesIn(await project(family.aritz, afterOld, slots)), [
        'Balón',
        'Muñeca',
      ]);

      final leoScope = await openAs(family.leo, slots);
      final leo1 = await seal(family.leo, leoScope.doc, revision: 1);
      slots = await merged(slots, await family.setOf([leo1]));

      // 2. Aritz desactiva: publica todo y vacía el bloque.
      final aritzScope = await openAs(family.aritz, slots);
      final off = deactivateProtection(
        common: afterOld,
        scope: aritzScope.doc,
        key: family.key,
        publicClock: clockOf('aritz-phone', 2000),
        scopeClock: clockOf('aritz-phone', 2000),
        authenticated: aritzScope.authenticatedPolicy,
      );
      expect(off.policy, const PolicyState(hideOwnGifts: false, rev: 2));
      final aritz2 = await seal(
        family.aritz,
        off.scope,
        revision: 2,
        policy: off.policy,
      );
      slots = await merged(slots, await family.setOf([aritz2]));
      expect(
        (await slots.acceptVerified(aritz1, view: family.view)).$2,
        SlotAcceptance.stale,
      );
      var commonNow = off.common.merge(afterOld).merge(oldCommon);
      for (final phone in [family.aritz, family.leo, family.nora]) {
        final p = await project(phone, commonNow, slots);
        expect(titlesIn(p), ['Balón', 'Muñeca'], reason: phone.id);
        expect(p.lockedBlocks, isEmpty);
      }
      final aritzView = await project(family.aritz, commonNow, slots);
      expect(aritzView.policies['nora'], off.policy);
      expect(aritzView.secretGiftIds, isEmpty);

      // 3. Leo reactiva.
      final leoScope2 = await openAs(family.leo, slots);
      final on2 = activate(
        commonNow,
        leoScope2.doc,
        'leo-phone',
        3000,
        authenticated: leoScope2.authenticatedPolicy,
      );
      expect(on2.policy, const PolicyState(hideOwnGifts: true, rev: 3));
      final leo2 = await seal(
        family.leo,
        on2.scope,
        revision: 2,
        policy: on2.policy,
      );
      slots = await merged(slots, await family.setOf([leo2]));
      commonNow = on2.common.merge(off.common).merge(afterOld).merge(oldCommon);
      expect(commonNow.canonicalJson(), isNot(contains('Muñeca')));
      final noraView = await project(family.nora, commonNow, slots);
      expect(titlesIn(noraView), ['Balón']);
      expect(noraView.lockedBlocks, [const SecretBlock('nora')]);
      for (final phone in [family.aritz, family.leo]) {
        final p = await project(phone, commonNow, slots);
        expect(titlesIn(p), ['Balón', 'Muñeca'], reason: phone.id);
        expect(p.secretGiftIds, hasLength(1));
        expect(p.policies['nora'], on2.policy);
      }
    });

    test('Nora no puede quitarse la protección desde su móvil', () async {
      final on = activate(
        common,
        FamilyDoc.empty(kListId),
        'aritz-phone',
        1000,
      );
      final slots = await family.setOf([
        await seal(family.aritz, on.scope, revision: 1),
      ]);
      final forged = writePublishedPolicy(
        on.common,
        clockOf('nora-phone', 5000),
        'nora',
        const PolicyState(hideOwnGifts: false, rev: 99),
      );
      final aritzView = await project(family.aritz, forged, slots);
      expect(aritzView.policies['nora'], on.policy);
      final opened = aritzView.openedScopes['nora']!;
      final fixed = reconcileProtection(
        common: forged,
        scope: opened.doc,
        opened: opened,
        key: family.key,
        publicClock: clockOf('aritz-phone', 6000),
        scopeClock: clockOf('aritz-phone', 6000),
      );
      expect(fixed.common.canonicalJson(), isNot(contains('Muñeca')));
      expect(publishedPolicy(fixed.common, 'nora'), on.policy);
      expect(liveSurpriseGifts(fixed.scope), 1);
      final noraView = await project(family.nora, fixed.common, slots);
      expect(noraView.lockedBlocks, [const SecretBlock('nora')]);
      expect(titlesIn(noraView), ['Balón']);
    });

    test('ataque A1: un slot escrito por el móvil de Nora con «publicar» no '
        'cuenta', () async {
      final on = activate(
        common,
        FamilyDoc.empty(kListId),
        'aritz-phone',
        1000,
      );
      // Nora consiguió la clave (por ejemplo, con el ataque del paquete) y
      // firma un slot que dice que no hay protección.
      final noraSlot = await seal(
        family.nora,
        FamilyDoc.empty(kListId),
        revision: 1,
        policy: const PolicyState(hideOwnGifts: false, rev: 50),
      );
      await expectLater(
        SlotSet.empty.acceptVerified(noraSlot, view: family.view),
        throwsA(isA<SlotAuthException>()),
      );
      // Aunque se colara en el almacén local, abrir lo ignora.
      final aritz1 = await seal(family.aritz, on.scope, revision: 1);
      final slots = SlotSet.fromLocalStoreJson([
        env.encodeBase64Url(aritz1.bytes),
        env.encodeBase64Url(noraSlot.bytes),
      ]);
      final opened = await openAs(family.aritz, slots);
      expect(opened.ignoredWriters, ['nora-phone']);
      expect(opened.unreadableWriters, isEmpty);
      expect(opened.authenticatedPolicy, on.policy);
      final t = reconcileProtection(
        common: on.common,
        scope: opened.doc,
        opened: opened,
        key: family.key,
        publicClock: clockOf('aritz-phone', 6000),
        scopeClock: clockOf('aritz-phone', 6000),
      );
      expect(t.policy, on.policy);
      expect(t.common.canonicalJson(), isNot(contains('Muñeca')));
      expect(liveSurpriseGifts(t.scope), 1);
      // Tampoco cuenta para un móvil sin clave, ni para el de la propia Nora.
      for (final phone in [family.leo, family.nora]) {
        expect(
          slots.authenticatedPolicy('nora', family.viewOf(phone)),
          on.policy,
        );
      }
    });

    test('M1: sin política autenticada y con la clave, falla en cerrado y no '
        'publica', () async {
      final on = activate(
        common,
        FamilyDoc.empty(kListId),
        'aritz-phone',
        1000,
      );
      final scope = on.scope;
      // Aritz tiene la clave pero no ve ningún slot, y el común dice «no».
      final forged = writePublishedPolicy(
        on.common,
        clockOf('nora-phone', 5000),
        'nora',
        const PolicyState(hideOwnGifts: false, rev: 9),
      );
      final opened = await openAs(family.aritz, SlotSet.empty);
      expect(opened.authenticatedPolicy, isNull);
      expect(
        opened.effective(publishedPolicy(forged, 'nora')).hideOwnGifts,
        isTrue,
      );
      final t = reconcileProtection(
        common: forged,
        scope: scope,
        opened: opened,
        key: family.key,
        publicClock: clockOf('aritz-phone', 6000),
        scopeClock: clockOf('aritz-phone', 6000),
      );
      expect(t.common.canonicalJson(), isNot(contains('Muñeca')));
      expect(liveSurpriseGifts(t.scope), 1);
      expect(effectivePolicy(failClosed: true).hideOwnGifts, isTrue);
    });

    test(
      'M1: con un slot que no puede descifrar, manda su política firmada',
      () async {
        final on = activate(
          common,
          FamilyDoc.empty(kListId),
          'aritz-phone',
          1000,
        );
        final aritz1 = await seal(family.aritz, on.scope, revision: 1);
        final aritzOpened = await openAs(
          family.aritz,
          await family.setOf([aritz1]),
        );
        final off = deactivateProtection(
          common: on.common,
          scope: aritzOpened.doc,
          key: family.key,
          publicClock: clockOf('aritz-phone', 2000),
          scopeClock: clockOf('aritz-phone', 2000),
          authenticated: aritzOpened.authenticatedPolicy,
        );
        final aritz2 = await seal(
          family.aritz,
          off.scope,
          revision: 2,
          policy: off.policy,
        );
        // Leo ha vuelto a activar (revisión 3) con otra clave candidata que
        // Aritz todavía no tiene: no puede descifrar su slot, pero la
        // política de la cabecera va firmada y cuenta.
        final otherKey = SurpriseKey(
          personId: 'nora',
          epoch: 1,
          bytes: List.filled(32, 9),
        );
        final leoOther = await seal(
          family.leo,
          scopeWith(clockOf('leo-phone', 2500), ['Lápices']),
          revision: 1,
          key: otherKey,
          policy: const PolicyState(hideOwnGifts: true, rev: 3),
        );
        final slots = await family.setOf([aritz2, leoOther]);
        final opened = await openAs(family.aritz, slots);
        expect(opened.unreadableWriters, ['leo-phone']);
        expect(
          opened.effective(publishedPolicy(off.common, 'nora')),
          const PolicyState(hideOwnGifts: true, rev: 3),
        );
        // El común dice «publicar» (revisión 2), pero Aritz no publica nada:
        // vuelve a ocultar lo de Nora y corrige la política publicada.
        final t = reconcileProtection(
          common: off.common,
          scope: opened.doc,
          opened: opened,
          key: family.key,
          publicClock: clockOf('aritz-phone', 6000),
          scopeClock: clockOf('aritz-phone', 6000),
        );
        expect(t.policy.hideOwnGifts, isTrue);
        expect(t.common.canonicalJson(), isNot(contains('Muñeca')));
        expect(t.common.canonicalJson(), isNot(contains('Lápices')));
        expect(publishedPolicy(t.common, 'nora'), t.policy);
        // Al revés: si el ilegible es el viejo («ocultar», revisión 1) y la
        // autenticada más nueva dice «publicar», se publica lo legible y lo
        // del ilegible se queda dentro hasta que se pueda abrir.
        final leoOld = await seal(
          family.leo,
          scopeWith(clockOf('leo-phone', 500), ['Lápices']),
          revision: 1,
          key: otherKey,
        );
        final opened2 = await openAs(
          family.aritz,
          await family.setOf([aritz2, leoOld]),
        );
        expect(opened2.unreadableWriters, ['leo-phone']);
        final t2 = reconcileProtection(
          common: off.common,
          scope: opened2.doc,
          opened: opened2,
          key: family.key,
          publicClock: clockOf('aritz-phone', 6000),
          scopeClock: clockOf('aritz-phone', 6000),
        );
        expect(t2.policy, off.policy);
        expect(t2.common.canonicalJson(), contains('Muñeca'));
        expect(t2.common.canonicalJson(), isNot(contains('Lápices')));
      },
    );

    test('M2: una lápida en la política se lee como «ocultar» y reconciliar '
        'sigue siendo idempotente', () async {
      final on = activate(
        common,
        FamilyDoc.empty(kListId),
        'aritz-phone',
        1000,
      );
      final tomb = on.common.delete(
        clockOf('nora-phone', 5000),
        Collections.policies,
        'nora',
      );
      expect(publishedPolicy(tomb, 'nora')!.hideOwnGifts, isTrue);
      final slots = await family.setOf([
        await seal(family.aritz, on.scope, revision: 1),
      ]);
      final noraView = await project(family.nora, tomb, slots);
      expect(noraView.lockedBlocks, [const SecretBlock('nora')]);
      final opened = await openAs(family.aritz, slots);
      final once = reconcileProtection(
        common: tomb,
        scope: opened.doc,
        opened: opened,
        key: family.key,
        publicClock: clockOf('aritz-phone', 6000),
        scopeClock: clockOf('aritz-phone', 6000),
      );
      final twice = reconcileProtection(
        common: once.common,
        scope: once.scope,
        opened: opened,
        key: family.key,
        publicClock: clockOf('aritz-phone', 7000),
        scopeClock: clockOf('aritz-phone', 7000),
      );
      expect(twice.common.canonicalJson(), once.common.canonicalJson());
      expect(twice.scope.canonicalJson(), once.scope.canonicalJson());
    });

    test('B1: una revisión publicada inflada no agota la política', () async {
      final on = activate(
        common,
        FamilyDoc.empty(kListId),
        'aritz-phone',
        1000,
      );
      final inflated = writePublishedPolicy(
        on.common,
        clockOf('nora-phone', 5000),
        'nora',
        const PolicyState(hideOwnGifts: true, rev: kMaxPolicyRev),
      );
      expect(
        effectivePolicy(
          published: publishedPolicy(inflated, 'nora'),
          authenticated: on.policy,
        ),
        const PolicyState(hideOwnGifts: true, rev: 2),
      );
      // Quitar la protección sigue siendo posible.
      final off = deactivateProtection(
        common: inflated,
        scope: on.scope,
        key: family.key,
        publicClock: clockOf('aritz-phone', 6000),
        scopeClock: clockOf('aritz-phone', 6000),
        authenticated: on.policy,
      );
      expect(off.policy, const PolicyState(hideOwnGifts: false, rev: 2));
      // Y pedirla desde un móvil sin clave tampoco se desborda.
      final maxed = writePublishedPolicy(
        on.common,
        clockOf('nora-phone', 5000),
        'nora',
        const PolicyState(hideOwnGifts: false, rev: kMaxPolicyRev),
      );
      final requested = requestProtection(
        maxed,
        clockOf('leo-phone', 6000),
        'nora',
      );
      expect(publishedPolicy(requested, 'nora')!.hideOwnGifts, isTrue);
      expect(
        nextPolicyRev(
          authenticated: const PolicyState(
            hideOwnGifts: true,
            rev: kMaxPolicyRev,
          ),
        ),
        kMaxPolicyRev,
      );
    });

    test('B5: el reloj del común no avanza con lo que se edita en secreto', () {
      final publicClock = clockOf('aritz-phone', 1000);
      final scopeClock = clockOf('aritz-phone', 1000);
      final on = activateProtection(
        common: common,
        scope: FamilyDoc.empty(kListId),
        key: family.key,
        publicClock: publicClock,
        scopeClock: scopeClock,
      );
      final before = publicClock.last;
      // Muchas ediciones secretas con el reloj del ámbito.
      var scope = on.scope;
      for (var i = 0; i < 20; i++) {
        scope = addSurpriseGift(
          scope,
          scopeClock,
          'x$i',
          giftFields('nora', 'R$i'),
        );
      }
      expect(publicClock.last, before);
      expect(scopeClock.last.compareTo(on.common.maxStamp!), greaterThan(0));
      // Al quitar la protección, la lápida del ámbito es más nueva que el
      // registro movido.
      final off = deactivateProtection(
        common: on.common,
        scope: scope,
        key: family.key,
        publicClock: publicClock,
        scopeClock: scopeClock,
        authenticated: on.policy,
      );
      for (final record in off.scope.collections[Collections.gifts]!.values) {
        expect(record.isDeleted, isTrue);
      }
    });

    test('un móvil antiguo añade un regalo público de Nora: se mueve, y '
        'repetirlo no cambia nada', () async {
      final on = activate(
        common,
        FamilyDoc.empty(kListId),
        'aritz-phone',
        1000,
      );
      final withOld = on.common.set(
        clockOf('oldphone01', 2000),
        Collections.gifts,
        'g9',
        giftFields('nora', 'Pinturas'),
      );
      final slots = await family.setOf([
        await seal(family.aritz, on.scope, revision: 1),
      ]);
      final opened = await openAs(family.aritz, slots);
      final once = reconcileProtection(
        common: withOld,
        scope: opened.doc,
        opened: opened,
        key: family.key,
        publicClock: clockOf('aritz-phone', 3000),
        scopeClock: clockOf('aritz-phone', 3000),
      );
      expect(once.common.canonicalJson(), isNot(contains('Pinturas')));
      expect(liveSurpriseGifts(once.scope), 2);
      final twice = reconcileProtection(
        common: once.common,
        scope: once.scope,
        opened: opened,
        key: family.key,
        publicClock: clockOf('aritz-phone', 4000),
        scopeClock: clockOf('aritz-phone', 4000),
      );
      expect(twice.common.canonicalJson(), once.common.canonicalJson());
      expect(twice.scope.canonicalJson(), once.scope.canonicalJson());
    });

    test('ataque A2: lo que cambia en el común no depende de cuántos secretos '
        'haya', () async {
      Future<String> commonAfter(int secrets, int probes) async {
        final on = activate(
          common,
          FamilyDoc.empty(kListId),
          'aritz-phone',
          1000,
        );
        var scope = on.scope;
        final clock = clockOf('aritz-phone', 1500);
        for (var i = 0; i < secrets; i++) {
          scope = scope.set(
            clock,
            Collections.gifts,
            'x$i',
            giftFields('nora', 'Secreto $i'),
          );
        }
        // Nora sondea con regalos públicos para sí misma.
        var probed = on.common;
        for (var i = 0; i < probes; i++) {
          probed = probed.set(
            clockOf('nora-phone', 2000),
            Collections.gifts,
            'p${i.toString().padLeft(2, '0')}',
            giftFields('nora', 'Sonda $i'),
          );
        }
        final slots = await family.setOf([
          await seal(family.aritz, scope, revision: 1),
        ]);
        final opened = await openAs(family.aritz, slots);
        final t = reconcileProtection(
          common: probed,
          scope: opened.doc,
          opened: opened,
          key: family.key,
          publicClock: clockOf('aritz-phone', 3000),
          scopeClock: clockOf('aritz-phone', 3000),
        );
        expect(liveSurpriseGifts(t.scope), lessThanOrEqualTo(kMaxSlotGifts));
        expect(scopeFitsInSlot(t.scope, 'nora'), isTrue);
        return t.common.canonicalJson();
      }

      for (final probes in [1, 8, 20]) {
        final results = {
          for (final secrets in [0, 25, 50, 62])
            await commonAfter(secrets, probes),
        };
        expect(results, hasLength(1), reason: '$probes sondas');
      }
    });

    // Activar con más regalos de los que caben (N4): protected_phase2_test.
  });

  group('Nora no abre sus sorpresas', () {
    test(
      'ni con la familyKey, ni con sus claves, ni con las exportaciones',
      () async {
        final scope = scopeWith(clockOf('aritz-phone', 1000), ['Telescopio']);
        final slot = await seal(family.aritz, scope, revision: 1);
        final familyKey = await env.FamilyKey.generate();
        final noraJson = family.nora.keys.toJson();
        final candidates = [
          familyKey.bytes,
          env.decodeBase64Url(noraJson['x'] as String),
          env.decodeBase64Url(noraJson['e'] as String),
          env.decodeBase64Url(noraJson['c'] as String),
          family.nora.keys.publicKeys.agreement,
        ];
        for (final bytes in candidates) {
          await expectLater(
            slot.open(
              expectedListId: kListId,
              key: SurpriseKey(personId: 'nora', epoch: 1, bytes: bytes),
              signingKey: family.aritz.keys.publicKeys.signing,
            ),
            // La cabecera dice con qué clave se selló: otra ni se prueba (y
            // si se probara, fallaría el GCM: ver protected_slot_test).
            throwsA(isA<SlotWrongScopeException>()),
          );
        }
        final common = commonWithPeople(clockOf('aritz-phone', 100));
        final envelope = await env.seal(
          doc: common.toJson(),
          listId: kListId,
          fromNode: 'nora-phone',
          at: '',
          key: familyKey,
        );
        final opened = await env.open(
          envelope,
          key: familyKey,
          expectedListId: kListId,
        );
        expect(jsonEncode(opened.doc), isNot(contains('Telescopio')));
        final view = await project(
          family.nora,
          common,
          await family.setOf([slot]),
          keyring: family.authorizedKeyring,
        );
        expect(view.openedScopes, isEmpty);
        expect(titlesIn(view), isEmpty);
      },
    );
  });

  group('proyección', () {
    Future<(FamilyDoc, SlotSet)> stateWith(int n) async {
      final on = activateProtection(
        common: commonWithPeople(clockOf('aritz-phone', 100)).set(
          clockOf('aritz-phone', 100),
          Collections.gifts,
          'p1',
          giftFields('aritz', 'Balón'),
        ),
        scope: FamilyDoc.empty(kListId),
        key: family.key,
        publicClock: clockOf('aritz-phone', 200),
        scopeClock: clockOf('aritz-phone', 200),
      );
      var scope = on.scope;
      final clock = clockOf('aritz-phone', 300);
      for (var i = 0; i < n; i++) {
        scope = scope.set(
          clock,
          Collections.gifts,
          'x$i',
          giftFields(
            'nora',
            i.isEven ? 'Bicicleta' : 'Bicicleta roja',
            plannedCents: 5000,
          ),
        );
      }
      final slot = await seal(
        family.aritz,
        scope,
        revision: 1,
        policy: on.policy,
      );
      return (on.common, await family.setOf([slot]));
    }

    test(
      'para Nora, con 0 o con 50: el mismo bloque y la misma vista',
      () async {
        final (common0, slots0) = await stateWith(0);
        final (common50, slots50) = await stateWith(50);
        expect(slots0.all.single.bytes.length, slots50.all.single.bytes.length);
        final a = await project(family.nora, common0, slots0);
        final b = await project(family.nora, common50, slots50);
        expect(a.lockedBlocks, [const SecretBlock('nora')]);
        expect(b.lockedBlocks, a.lockedBlocks);
        expect(b.view.gifts, a.view.gifts);
        expect(b.view.budget().total, a.view.budget().total);
        expect(b.view.budget().ofRecipient('nora'), const BudgetTotals());
        expect(b.view.possibleDuplicates(), isEmpty);
        expect(b.view.giftsFor('nora'), isEmpty);
        expect(b.secretGiftIds, isEmpty);
      },
    );

    test('para Aritz cuentan en presupuesto, búsqueda y duplicados', () async {
      final (common, slots) = await stateWith(2);
      final p = await project(family.aritz, common, slots);
      expect(p.lockedBlocks, isEmpty);
      expect(p.view.giftsFor('nora'), hasLength(2));
      expect(p.view.budget().ofRecipient('nora').plannedCents, 10000);
      expect(p.view.possibleDuplicates(), hasLength(1));
      expect(p.secretGiftIds, hasLength(2));
      expect(common.canonicalJson(), isNot(contains('Bicicleta')));
    });

    test(
      'un móvil autorizado que aún no tiene la clave ve el bloque',
      () async {
        final (common, slots) = await stateWith(3);
        final p = await project(
          family.leo,
          common,
          slots,
          keyring: SurpriseKeyring.empty,
        );
        expect(p.lockedBlocks, [const SecretBlock('nora')]);
        expect(p.view.giftsFor('nora'), isEmpty);
      },
    );
  });

  test(
    'el reloj del ámbito no se mueve con una marca demasiado adelantada',
    () {
      final scopeClock = clockOf('aritz-phone', 1000);
      final far = FamilyDoc.empty(kListId).set(
        HlcClock(
          node: 'farfuture1',
          last: Hlc(millis: kFuture * 2, counter: 0, node: 'farfuture1'),
        ),
        Collections.gifts,
        'g1',
        giftFields('aritz', 'Lejos'),
      );
      final before = scopeClock.last;
      activateProtection(
        common: far,
        scope: FamilyDoc.empty(kListId),
        key: family.key,
        publicClock: clockOf('aritz-phone', 1000),
        scopeClock: scopeClock,
      );
      expect(scopeClock.last, before);
    },
  );
}
