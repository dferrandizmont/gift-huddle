import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/protected_doc.dart';
import 'package:regalos/core/sync/protected_envelope.dart';
import 'package:regalos/core/sync/wish_plan.dart';

import 'fixtures/protected_envelope_v106.dart' as v106;
import 'protected_harness.dart';

/// El bloque secreto con dos colecciones (ADR 0010, fase 3): abrir y sellar
/// regalos y planes, compactación por colección, capacidad compartida,
/// rotación y que un plan jamás se hace público.
void main() {
  late Family family;
  const on1 = PolicyState(hideOwnGifts: true, rev: 1);

  setUp(() async {
    family = await Family.create();
  });

  Map<String, Object?> planFields(String wish, {String title = 'Bicicleta'}) =>
      {
        'recipientId': 'nora',
        'sourceWishId': wish,
        'claimantPersonId': 'aritz',
        'title': title,
        'status': 'decided',
      };

  FamilyDoc scopeOf({
    int gifts = 0,
    int plans = 0,
    String giftTitle = 'Regalo',
  }) {
    var doc = FamilyDoc.empty(kListId);
    final c = clockOf('aritz-phone', 1);
    for (var i = 0; i < gifts; i++) {
      doc = doc.set(
        c,
        Collections.gifts,
        's$i',
        giftFields('nora', '$giftTitle $i'),
      );
    }
    for (var i = 0; i < plans; i++) {
      doc = doc.set(
        c,
        ScopeCollections.wishPlans,
        'p$i',
        planFields('w$i', title: 'Deseo $i'),
      );
    }
    return doc;
  }

  Future<SealedSlot> seal(
    Phone phone,
    FamilyDoc doc, {
    required int revision,
    SurpriseKey? key,
  }) => SealedSlot.seal(
    writerKeys: phone.keys,
    writer: phone.id,
    revision: revision,
    key: key ?? family.key,
    policy: on1,
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
    SurpriseKeyring? keyring,
    RegistryView? view,
  }) => publishScope(
    slots: slots,
    opened: opened,
    view: view ?? family.viewOf(phone),
    writerKeys: phone.keys,
    keyring: keyring ?? family.authorizedKeyring,
    policy: on1,
    doc: doc,
    nowMillis: now,
  );

  Future<SlotSet> withSlot(SlotSet slots, SealedSlot slot) async =>
      (await slots.acceptVerified(slot, view: family.view)).$1;

  group('abrir y sellar las dos colecciones', () {
    test(
      'los planes viajan en el slot y solo los abre quien tiene derecho',
      () async {
        final doc = scopeOf(gifts: 1, plans: 2);
        final slot = await seal(family.aritz, doc, revision: 1);
        final slots = await family.setOf([slot]);
        final leo = await openAs(family.leo, slots);
        expect(leo.doc.collections[ScopeCollections.wishPlans]!.keys, {
          'p0',
          'p1',
        });
        expect(leo.doc.record(Collections.gifts, 's0'), isNotNull);
        // El móvil de Nora no abre el bloque.
        expect(
          await openScope(
            personId: 'nora',
            slots: slots,
            keyring: SurpriseKeyring.empty,
            view: family.viewOf(family.nora),
          ),
          isNull,
        );
        expect(
          await openScope(
            personId: 'nora',
            slots: slots,
            keyring: family.authorizedKeyring,
            view: family.viewOf(family.nora),
          ),
          isNull,
        );
      },
    );

    test(
      'un ámbito sin planes es el de siempre: sin colección wishPlans',
      () async {
        final doc = scopeOf(gifts: 2);
        final slots = await family.setOf([
          await seal(family.aritz, doc, revision: 1),
        ]);
        final opened = await openAs(family.aritz, slots);
        expect(opened.doc.collections.keys, [Collections.gifts]);
        final published = await publishAs(
          family.aritz,
          slots,
          opened,
          opened.doc,
          now: 2000,
        );
        expect(published.sealed.collections.keys, [Collections.gifts]);
        expect(published.scope.collections.keys, [Collections.gifts]);
      },
    );

    test('se rechaza lo que no cabe en el registro de un plan', () async {
      final other = scopeOf().set(
        clockOf('aritz-phone', 2),
        ScopeCollections.wishPlans,
        'x',
        {...planFields('w'), 'recipientId': 'leo'},
      );
      await expectLater(
        seal(family.aritz, other, revision: 1),
        throwsA(isA<ArgumentError>()),
      );
      final huge = scopeOf().set(
        clockOf('aritz-phone', 2),
        ScopeCollections.wishPlans,
        'x',
        {...planFields('w'), 'giverNote': 'n' * 2500},
      );
      await expectLater(
        seal(family.aritz, huge, revision: 1),
        throwsA(isA<SurpriseGiftTooLargeException>()),
      );
      final unknown = scopeOf().set(clockOf('aritz-phone', 2), 'wishes', 'x', {
        'title': 'no',
      });
      await expectLater(
        seal(family.aritz, unknown, revision: 1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('scopeDocOnly deja los planes de la persona y las lápidas, y nada '
        'más', () {
      final c = clockOf('aritz-phone', 5);
      var doc = scopeOf(plans: 1)
          .set(c, ScopeCollections.wishPlans, 'otra', {
            ...planFields('w'),
            'recipientId': 'leo',
          })
          .set(c, ScopeCollections.wishPlans, 'borrado', planFields('w9'))
          .delete(c, ScopeCollections.wishPlans, 'borrado')
          .set(c, 'wishes', 'w1', {'title': 'no'});
      doc = scopeDocOnly(doc, 'nora');
      expect(doc.collections.keys.toSet(), {
        Collections.gifts,
        ScopeCollections.wishPlans,
      });
      expect(doc.collections[ScopeCollections.wishPlans]!.keys.toSet(), {
        'p0',
        'borrado',
      });
    });

    test(
      'un buzón de web con planes, sin la persona de la web, descarta los '
      'planes (fase 4: ya no se rechaza entero)',
      () async {
        final doc = scopeOf(gifts: 1, plans: 1);
        final slot = await seal(family.aritz, doc, revision: 1);
        final key = family.key;
        final opened = await slot.open(
          expectedListId: kListId,
          key: key,
          signingKey: family.aritz.keys.publicKeys.signing,
        );
        expect(opened.planRecords, 1);
        expect(opened.foreignRecords, 0);
        final absorbed = absorbWebInbox(
          scope: scopeOf(),
          inbox: opened,
          nowMillis: kFuture,
        );
        expect(absorbed.rejected, isNull);
        expect(absorbed.discarded, greaterThanOrEqualTo(1));
        expect(absorbed.scope.livePlans, isEmpty);
      },
    );
  });

  group('compactar lápidas por colección', () {
    // Un plan y un regalo con el mismo id: la lápida de uno nunca confirma
    // la del otro.
    FamilyDoc base() => FamilyDoc.empty(kListId)
        .set(
          clockOf('aritz-phone', 1),
          Collections.gifts,
          'x',
          giftFields('nora', 'Peonza'),
        )
        .set(
          clockOf('aritz-phone', 1),
          ScopeCollections.wishPlans,
          'x',
          planFields('w1'),
        );

    Future<(SlotSet, PublishedSlot)> aritzDeletesBoth() async {
      var slots = await family.setOf([
        await seal(family.aritz, base(), revision: 1),
        await seal(family.leo, base(), revision: 1),
      ]);
      final opened = await openAs(family.aritz, slots);
      final c = clockOf('aritz-phone', 2000);
      final pa = await publishAs(
        family.aritz,
        slots,
        opened,
        opened.doc
            .delete(c, Collections.gifts, 'x')
            .delete(c, ScopeCollections.wishPlans, 'x'),
        now: 2000,
      );
      slots = await withSlot(slots, pa.slot);
      return (slots, pa);
    }

    test('una lápida de gifts no confirma la de wishPlans', () async {
      var (slots, pa) = await aritzDeletesBoth();
      expect(pa.sealed.record(Collections.gifts, 'x')!.isDeleted, isTrue);
      expect(
        pa.sealed.record(ScopeCollections.wishPlans, 'x')!.isDeleted,
        isTrue,
      );
      // Leo publica con la lápida del regalo, pero aún con el plan vivo.
      final openedLeo = await openAs(family.leo, slots);
      final leoDoc = base().delete(
        clockOf('leo-phone', 3000),
        Collections.gifts,
        'x',
      );
      final pl = await publishAs(
        family.leo,
        slots,
        openedLeo,
        leoDoc,
        now: 3000,
      );
      slots = await withSlot(slots, pl.slot);
      // Aritz vuelve a publicar: el regalo (conocido por los dos) se compacta;
      // el plan no, porque Leo lo tiene vivo.
      final opened = await openAs(family.aritz, slots);
      final again = await publishAs(
        family.aritz,
        slots,
        opened,
        pa.scope,
        now: 4000,
      );
      expect(again.sealed.record(Collections.gifts, 'x'), isNull);
      expect(
        again.sealed.record(ScopeCollections.wishPlans, 'x')?.isDeleted,
        isTrue,
        reason: 'el plan sigue con su lápida',
      );
    });

    test(
      'y a la inversa: la lápida del plan no confirma la del regalo',
      () async {
        var (slots, pa) = await aritzDeletesBoth();
        final openedLeo = await openAs(family.leo, slots);
        final leoDoc = base().delete(
          clockOf('leo-phone', 3000),
          ScopeCollections.wishPlans,
          'x',
        );
        final pl = await publishAs(
          family.leo,
          slots,
          openedLeo,
          leoDoc,
          now: 3000,
        );
        slots = await withSlot(slots, pl.slot);
        final opened = await openAs(family.aritz, slots);
        final again = await publishAs(
          family.aritz,
          slots,
          opened,
          pa.scope,
          now: 4000,
        );
        expect(again.sealed.record(ScopeCollections.wishPlans, 'x'), isNull);
        expect(again.sealed.record(Collections.gifts, 'x')?.isDeleted, isTrue);
      },
    );

    test('con todos al día, la lápida de un plan se compacta y nada '
        'resucita', () async {
      var (slots, pa) = await aritzDeletesBoth();
      // Leo recibe y publica (conserva las lápidas: aún no las había
      // publicado).
      final openedLeo = await openAs(family.leo, slots);
      final pl = await publishAs(
        family.leo,
        slots,
        openedLeo,
        openedLeo.doc,
        now: 3000,
      );
      slots = await withSlot(slots, pl.slot);
      expect(
        pl.sealed.record(ScopeCollections.wishPlans, 'x')!.isDeleted,
        isTrue,
      );
      var opened = await openAs(family.aritz, slots);
      final pa2 = await publishAs(
        family.aritz,
        slots,
        opened,
        opened.doc,
        now: 4000,
      );
      expect(pa2.sealed.record(ScopeCollections.wishPlans, 'x'), isNull);
      expect(pa2.sealed.record(Collections.gifts, 'x'), isNull);
      slots = await withSlot(slots, pa2.slot);
      // Leo, que ve que Aritz ya fusionó su slot, también compacta.
      final leoAgain = await openAs(family.leo, slots);
      final pl2 = await publishAs(
        family.leo,
        slots,
        leoAgain,
        leoAgain.doc,
        now: 5000,
      );
      expect(pl2.sealed.record(ScopeCollections.wishPlans, 'x'), isNull);
      opened = await openAs(family.aritz, await withSlot(slots, pl2.slot));
      expect(opened.doc.livePlans, isEmpty);
      expect(opened.doc.canonicalJson(), isNot(contains('Bicicleta')));
    });

    test(
      'con un escritor sin slot no se compactan lápidas de planes',
      () async {
        final slots = await family.setOf([
          await seal(family.aritz, base(), revision: 1),
        ]);
        final opened = await openAs(family.aritz, slots);
        final doc = opened.doc.delete(
          clockOf('aritz-phone', 2),
          ScopeCollections.wishPlans,
          'x',
        );
        final compact = compactScope(
          doc: doc,
          opened: opened,
          view: family.viewOf(family.aritz),
        );
        expect(identical(compact, doc), isTrue);
      },
    );
  });

  group('compactScope: salidas tempranas con planes', () {
    FamilyDoc withTombs() {
      final c = clockOf('aritz-phone', 2);
      return scopeOf(
        gifts: 1,
        plans: 1,
      ).delete(c, ScopeCollections.wishPlans, 'p0');
    }

    test('sin slot propio no se compacta nada', () async {
      final slots = await family.setOf([
        await seal(family.leo, scopeOf(gifts: 1, plans: 1), revision: 1),
      ]);
      final opened = await openAs(family.aritz, slots);
      expect(opened.parts.containsKey(family.aritz.id), isFalse);
      final doc = withTombs();
      final out = compactScope(
        doc: doc,
        opened: opened,
        view: family.viewOf(family.aritz),
      );
      expect(identical(out, doc), isTrue);
    });

    test(
      'con un escritor congelado no se compactan lápidas de planes',
      () async {
        final both = scopeOf(gifts: 1, plans: 1);
        final tomb = both.delete(
          clockOf('aritz-phone', 2),
          ScopeCollections.wishPlans,
          'p0',
        );
        final slots = await family.setOf([
          await seal(family.aritz, tomb, revision: 1),
          await seal(family.leo, tomb, revision: 1),
        ]);
        final real = await openAs(family.aritz, slots);
        final doc = real.doc;
        // Todos la conocen: se compactaría...
        expect(
          compactScope(
            doc: doc,
            opened: real,
            view: family.viewOf(family.aritz),
          ).record(ScopeCollections.wishPlans, 'p0'),
          isNull,
        );
        // ...pero no con un escritor congelado.
        final frozen = OpenedScope(
          personId: real.personId,
          doc: real.doc,
          authenticatedPolicy: real.authenticatedPolicy,
          parts: real.parts,
          unreadableWriters: real.unreadableWriters,
          ignoredWriters: const ['zombie'],
          frozenWriters: const ['zombie'],
        );
        final out = compactScope(
          doc: doc,
          opened: frozen,
          view: family.viewOf(family.aritz),
        );
        expect(identical(out, doc), isTrue);
        expect(out.record(ScopeCollections.wishPlans, 'p0')!.isDeleted, isTrue);
      },
    );
  });

  group('compatibilidad byte a byte con la 1.0.6', () {
    test(
      'un slot sin planes sale como el de la versión anterior salvo «wp» '
      'del cuerpo: misma cabecera, mismo tamaño, mismo documento',
      () async {
        final doc = scopeOf(gifts: 3);
        final nonce = List<int>.generate(12, (i) => i + 1);
        final now = await SealedSlot.sealForTesting(
          writerKeys: family.aritz.keys,
          writer: family.aritz.id,
          revision: 7,
          key: family.key,
          policy: on1,
          doc: doc,
          nonce: nonce,
        );
        final before = await v106.SealedSlot.sealForTesting(
          writerKeys: family.aritz.keys,
          writer: family.aritz.id,
          revision: 7,
          key: family.key,
          policy: on1,
          doc: doc,
          nonce: nonce,
        );
        // La cabecera (lo que la 1.0.6 comprueba) y el tamaño son los
        // mismos; el cuerpo cifrado solo gana «wp», que la 1.0.6 no mira.
        expect(now.header.toBytes(), before.header.toBytes());
        expect(now.bytes.length, before.bytes.length);
        final opened = await v106.SealedSlot.parse(now.bytes).open(
          expectedListId: kListId,
          key: family.key,
          signingKey: family.aritz.keys.publicKeys.signing,
        );
        expect(opened.foreignRecords, 0);
        expect(opened.doc.canonicalJson(), doc.canonicalJson());
      },
    );
  });

  group('capacidad compartida por gifts + wishPlans', () {
    test('232 registros vivos entre las dos colecciones caben, 233 no', () {
      final fits = scopeOf(gifts: 200, plans: 32);
      expect(liveSurpriseGifts(fits), kMaxSlotGifts);
      expect(scopeFitsInSlot(fits, 'nora'), isTrue);
      final over = scopeOf(gifts: 200, plans: 33);
      expect(scopeFitsInSlot(over, 'nora'), isFalse);
      final (sealed, left) = fitScopeToSlot(over, 'nora');
      expect(liveSurpriseGifts(sealed), kMaxSlotGifts);
      expect(left, hasLength(1));
    });

    test('las lápidas de las dos colecciones se conservan al ajustar', () {
      final c = clockOf('aritz-phone', 9);
      final over = scopeOf(gifts: 200, plans: 33)
          .delete(c, Collections.gifts, 's5')
          .delete(c, ScopeCollections.wishPlans, 'p5');
      final (sealed, _) = fitScopeToSlot(over, 'nora');
      expect(sealed.record(Collections.gifts, 's5')!.isDeleted, isTrue);
      expect(
        sealed.record(ScopeCollections.wishPlans, 'p5')!.isDeleted,
        isTrue,
      );
    });

    test('con un escritor de 1.0.5 solo caben 64 entre las dos', () {
      final doc = scopeOf(gifts: 40, plans: 40);
      final (sealed, left) = fitScopeToSlot(
        doc,
        'nora',
        maxLive: kLegacySlotGifts,
      );
      expect(liveSurpriseGifts(sealed), kLegacySlotGifts);
      expect(left, hasLength(16));
    });

    test('el cupo de la interfaz (200) cuenta los planes', () {
      final doc = scopeOf(gifts: 150, plans: 50);
      expect(liveOwnSurpriseGifts(doc), 200);
      expect(
        () => addSurpriseGift(
          doc,
          clockOf('aritz-phone', 3),
          'nuevo',
          giftFields('nora', 'Uno más'),
        ),
        throwsA(isA<SurpriseCapacityException>()),
      );
    });

    test(
      'un slot con planes lleno de texto se ajusta sin perder lápidas',
      () async {
        // 232 registros con casi 1.900 bytes de texto cada uno.
        var doc = FamilyDoc.empty(kListId);
        final c = clockOf('aritz-phone', 1);
        for (var i = 0; i < 116; i++) {
          doc = doc.set(c, Collections.gifts, 'g$i', {
            ...giftFields('nora', 'R$i'),
            'note': 'n${'x' * 1500}$i',
          });
          doc = doc.set(c, ScopeCollections.wishPlans, 'p$i', {
            ...planFields('w$i'),
            'giverNote': 'q${'y' * 1500}$i',
          });
        }
        final slots = await family.setOf([
          await seal(family.aritz, scopeOf(), revision: 1),
          await seal(family.leo, scopeOf(), revision: 1),
        ]);
        final opened = await openAs(family.aritz, slots);
        final published = await publishAs(
          family.aritz,
          slots,
          opened,
          doc,
          now: 2000,
        );
        expect(liveSurpriseGifts(published.sealed), lessThanOrEqualTo(232));
        expect(
          liveSurpriseGifts(published.sealed) + published.leftOut.length,
          232,
        );
        // Lo sellado se puede abrir.
        final back = await openAs(
          family.leo,
          await withSlot(slots, published.slot),
        );
        expect(
          liveSurpriseGifts(back.doc),
          liveSurpriseGifts(published.sealed),
        );
      },
    );
  });

  group('rotación de claves', () {
    test('la clave nueva conserva los planes', () async {
      final aunt = await Phone.create('tia-phone', 'leo', 4);
      final registry = await registryOf([
        family.aritz,
        family.leo,
        family.nora,
        aunt,
      ]);
      final view = await family.aritz.viewOf(registry);
      final doc = scopeOf(gifts: 1, plans: 2);
      final slots = (await SlotSet.verified([
        await seal(family.aritz, doc, revision: 1),
        await seal(family.leo, doc, revision: 1),
      ], view: view)).$1;
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
      var opened = await openAs(
        family.aritz,
        slots,
        keyring: rotation.keyring,
        view: view2,
      );
      final published = await publishAs(
        family.aritz,
        slots,
        opened,
        opened.doc,
        now: 6000,
        keyring: rotation.keyring,
        view: view2,
      );
      expect(published.slot.header.epoch, 2);
      expect(
        published.sealed.collections[ScopeCollections.wishPlans]!.keys.toSet(),
        {'p0', 'p1'},
      );
      final slots2 = (await slots.acceptVerified(
        published.slot,
        view: view2,
      )).$1;
      opened = await openAs(
        family.aritz,
        slots2,
        keyring: rotation.keyring,
        view: view2,
      );
      expect(opened.doc.livePlans.map((p) => p.planId), ['p0', 'p1']);
    });
  });

  group('un plan nunca se hace público', () {
    FamilyDoc commonDoc() => commonWithPeople(clockOf('aritz-phone', 100)).set(
      clockOf('aritz-phone', 100),
      Collections.gifts,
      'g1',
      giftFields('nora', 'Muñeca'),
    );

    test('desproteger publica los regalos y deja los planes cerrados', () {
      final scope = scopeOf(gifts: 1, plans: 2, giftTitle: 'Secreto');
      final t = deactivateProtection(
        common: commonDoc(),
        scope: scope,
        key: family.key,
        publicClock: clockOf('aritz-phone', 1000),
        scopeClock: clockOf('aritz-phone', 1000),
        authenticated: on1,
      );
      expect(
        t.common.collections.containsKey(ScopeCollections.wishPlans),
        isFalse,
      );
      expect(t.common.canonicalJson(), isNot(contains('Deseo')));
      expect(t.common.canonicalJson(), isNot(contains('sourceWishId')));
      expect(t.common.canonicalJson(), contains('Secreto 0'));
      // El plan sigue vivo en el ámbito, sin tocar.
      expect(t.scope.livePlans.map((p) => p.planId), ['p0', 'p1']);
      expect(t.scope.record(Collections.gifts, 's0')!.isDeleted, isTrue);
    });

    test('reconciliar sin protección tampoco los publica', () async {
      final scope = scopeOf(gifts: 1, plans: 1);
      final slots = await family.setOf([
        await seal(family.aritz, scope, revision: 1),
      ]);
      final opened = await openAs(family.aritz, slots);
      const off = PolicyState(hideOwnGifts: false, rev: 2);
      final off2 = await seal(family.aritz, scope, revision: 2);
      // Una política autenticada «sin protección» viene de un slot firmado.
      final offSlot = await SealedSlot.seal(
        writerKeys: family.aritz.keys,
        writer: family.aritz.id,
        revision: 3,
        key: family.key,
        policy: off,
        doc: scope,
      );
      final slots2 = await withSlot(await withSlot(slots, off2), offSlot);
      final opened2 = await openAs(family.aritz, slots2);
      expect(opened2.authenticatedPolicy, off);
      final t = reconcileProtection(
        common: commonDoc(),
        scope: opened2.doc,
        opened: opened2,
        key: family.key,
        publicClock: clockOf('aritz-phone', 2000),
        scopeClock: clockOf('aritz-phone', 2000),
      );
      expect(
        t.common.collections.containsKey(ScopeCollections.wishPlans),
        isFalse,
      );
      expect(t.common.canonicalJson(), isNot(contains('sourceWishId')));
      expect(t.scope.livePlans, hasLength(1));
      expect(opened.doc.livePlans, hasLength(1));
    });

    test('activar la protección con planes en el ámbito los conserva y no '
        'los mueve al común', () {
      final t = activateProtection(
        common: commonDoc(),
        scope: scopeOf(plans: 1),
        key: family.key,
        publicClock: clockOf('aritz-phone', 1000),
        scopeClock: clockOf('aritz-phone', 1000),
      );
      expect(t.scope.livePlans, hasLength(1));
      expect(
        t.common.collections.containsKey(ScopeCollections.wishPlans),
        isFalse,
      );
      expect(t.scope.record(Collections.gifts, 'g1'), isNotNull);
    });

    test('la vista autorizada no lleva wishPlans', () async {
      final scope = scopeOf(gifts: 1, plans: 1);
      final slots = await family.setOf([
        await seal(family.aritz, scope, revision: 1),
      ]);
      final projection = await projectAuthorized(
        common: commonDoc(),
        slots: slots,
        keyring: family.authorizedKeyring,
        view: family.viewOf(family.aritz),
      );
      expect(
        projection.doc.collections.containsKey(ScopeCollections.wishPlans),
        isFalse,
      );
      // El plan sí se ve donde se debe: en el ámbito abierto.
      expect(projection.openedScopes['nora']!.doc.livePlans, hasLength(1));
    });
  });

  group('idempotencia', () {
    test('fusionar el mismo ámbito dos veces o en otro orden no cambia '
        'nada', () {
      final a = scopeOf(gifts: 1, plans: 2);
      final b = scopeOf(gifts: 1, plans: 3);
      expect(a.merge(a).canonicalJson(), a.canonicalJson());
      expect(a.merge(b).canonicalJson(), b.merge(a).canonicalJson());
    });

    test('volver a publicar lo mismo da el mismo contenido', () async {
      final doc = scopeOf(gifts: 1, plans: 2);
      final slots = await family.setOf([
        await seal(family.aritz, doc, revision: 1),
        await seal(family.leo, doc, revision: 1),
      ]);
      final opened = await openAs(family.aritz, slots);
      final one = await publishAs(family.aritz, slots, opened, doc, now: 2000);
      final two = await publishAs(family.aritz, slots, opened, doc, now: 2000);
      expect(one.sealed.canonicalJson(), two.sealed.canonicalJson());
    });
  });
}
