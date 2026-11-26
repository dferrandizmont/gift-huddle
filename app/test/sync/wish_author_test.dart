import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/device_keys.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/wish.dart';
import 'package:regalos/core/sync/wish_author.dart';

import 'protected_harness.dart';

/// El autor de un deseo sale de este dispositivo y del registro actual de la
/// lista (ADR 0010): nadie elige otro dispositivo, persona ni lista, y el
/// contexto lee el estado vigente en cada operación.
void main() {
  late Phone aritz;
  late Phone nora;
  late Phone noraTwo;
  late Phone leo;

  setUpAll(() async {
    aritz = await Phone.create('aritz-phone', 'aritz', 1);
    nora = await Phone.create('nora-phone', 'nora', 3);
    noraTwo = await Phone.create('nora-two', 'nora', 4);
    leo = await Phone.create('leo-phone', 'leo', 2);
  });

  FamilyDoc base({String listId = kListId}) {
    var doc = FamilyDoc.empty(listId);
    final c = clockOf('base', 0);
    for (final p in kPeople) {
      doc = doc.set(c, Collections.recipients, p, {'name': p});
    }
    return doc;
  }

  const bike = VisibleWishPatch(title: 'Bicicleta', year: 2026);

  Future<WishContext> ctxOf(
    Phone p,
    DeviceRegistry registry, {
    Set<String> people = kPeople,
  }) async {
    final view = await p.viewOf(registry, people: people);
    return WishContext.device(view: () => view, localKeys: p.keys);
  }

  WishContext ctxOfView(RegistryView view, DeviceKeys keys) =>
      WishContext.device(view: () => view, localKeys: keys);

  /// Que [ctx] no pueda escribir: error tipado, mismo documento y reloj.
  void expectRefused(
    FamilyDoc doc,
    WishContext ctx,
    WishAuthorError error, {
    String? listId,
  }) {
    final c = clockOf('t', 900);
    final before = c.last;
    final results = [
      doc.createOwnWish(c, ctx, bike),
      doc.suggestVisibleWish(c, ctx, 'nora', bike),
      doc.editVisibleWish(c, ctx, 'w1', const VisibleWishPatch(title: 'x')),
      doc.removeWish(c, ctx, 'w1'),
    ];
    for (final r in results) {
      expect(r.error, WishError.authorRefused);
      expect(r.authorError, error);
      expect(r.doc, same(doc));
    }
    expect(c.last, before);
    expect(ctx.resolve(listId ?? doc.listId).error, error);
  }

  Future<DeviceRegistry> pairWith(
    DeviceRegistry registry,
    Phone voucher,
    Phone target, {
    String? targetPerson,
    int seq = 1,
  }) async => registry.withVouch(
    await Vouch.create(
      keys: voucher.keys,
      voucher: await voucher.record(),
      record: await target.record(person: targetPerson, seq: seq),
    ),
  );

  Future<DeviceRecord> webRecordOf(Phone web, String person) =>
      DeviceRecord.create(
        keys: web.keys,
        listId: kListId,
        deviceId: web.id,
        personId: person,
        kind: DeviceKind.web,
      );

  Future<DeviceRegistry> revoke(
    DeviceRegistry registry,
    Phone by,
    Phone target,
  ) async => registry.withRevocation(
    await Revocation.create(
      keys: by.keys,
      by: await by.record(),
      deviceId: target.id,
    ),
  );

  test('un móvil aprobado escribe como su persona y lista', () async {
    final registry = await registryOf([aritz, nora]);
    final r = (await ctxOf(aritz, registry)).resolve(kListId);
    expect(r.ok, isTrue);
    expect(r.author!.personId, 'aritz');
    expect(r.author!.listId, kListId);
    expect(r.author!.deviceId, 'aritz-phone');
  });

  test('Aritz no puede escribir como Nora: no hay forma de elegirla', () async {
    final registry = await registryOf([aritz, nora]);
    final ctx = await ctxOf(aritz, registry);
    var doc = base()
        .createOwnWish(
          clockOf('n', 10),
          await ctxOf(nora, registry),
          bike,
          id: 'w1',
        )
        .doc;
    final c = clockOf('a', 900);
    final before = c.last;
    for (final r in [
      doc.editVisibleWish(c, ctx, 'w1', const VisibleWishPatch(title: 'x')),
      doc.removeWish(c, ctx, 'w1'),
    ]) {
      expect(r.error, WishError.notWishOwner);
      expect(r.doc, same(doc));
    }
    expect(c.last, before);
    doc = doc.createOwnWish(c, ctx, bike, id: 'w2').doc;
    expect(
      Wish.fromRecord(doc.record(Collections.wishes, 'w2')!)!.recipientId,
      'aritz',
    );
    // Unas claves locales de otro móvil no sirven para su vista.
    final spoofView = await aritz.viewOf(registry);
    final spoofCtx = WishContext.device(
      view: () => spoofView,
      localKeys: nora.keys,
    );
    expectRefused(doc, spoofCtx, WishAuthorError.unknownDevice);
  });

  test('el segundo móvil de P puede editar y quitar sus deseos', () async {
    final registry = await registryOf([aritz, nora, noraTwo]);
    final first = await ctxOf(nora, registry);
    final second = await ctxOf(noraTwo, registry);
    var doc = base().createOwnWish(clockOf('a', 10), first, bike, id: 'w1').doc;
    final edit = doc.editVisibleWish(
      clockOf('b', 20),
      second,
      'w1',
      const VisibleWishPatch(title: 'Bici azul'),
    );
    expect(edit.ok, isTrue);
    doc = edit.doc;
    expect(doc.wishesFor('nora').single.title, 'Bici azul');
    expect(doc.removeWish(clockOf('b', 30), second, 'w1').ok, isTrue);
  });

  test('quien sugiere (Aritz) no edita ni quita; Nora sí', () async {
    final registry = await registryOf([aritz, nora]);
    final a = await ctxOf(aritz, registry);
    final n = await ctxOf(nora, registry);
    final doc = base()
        .suggestVisibleWish(clockOf('a', 10), a, 'nora', bike, id: 'w1')
        .doc;
    final c = clockOf('a', 20);
    final before = c.last;
    expect(
      doc.editVisibleWish(c, a, 'w1', const VisibleWishPatch(title: 'x')).error,
      WishError.notWishOwner,
    );
    expect(doc.removeWish(c, a, 'w1').error, WishError.notWishOwner);
    expect(c.last, before);
    expect(doc.removeWish(clockOf('n', 20), n, 'w1').ok, isTrue);
  });

  group('aprobación', () {
    test(
      'una primera ficha que nadie avaló, con otros móviles: pendiente',
      () async {
        // Leo entra con su ficha (seq 1) junto a Aritz y Nora; él avala a
        // Aritz, pero ningún activo avala su ficha.
        var registry = await registryOf([aritz, nora]);
        registry = await registry.withRecord(await leo.record());
        registry = await registry.withVouch(
          await Vouch.create(
            keys: leo.keys,
            voucher: await leo.record(),
            record: await aritz.record(),
          ),
        );
        final view = await leo.viewOf(registry);
        expect(view.selfApproved, isTrue, reason: 'por construcción (seq 1)');
        expect(view.aloneAmongLiveMobiles, isFalse);
        expectRefused(
          base(),
          ctxOfView(view, leo.keys),
          WishAuthorError.devicePending,
        );
        // En cuanto Aritz (activo) la avala, ya puede.
        final approved = await pairWith(registry, aritz, leo);
        expect(
          (await ctxOf(leo, approved)).resolve(kListId).author!.personId,
          'leo',
        );
      },
    );

    test('un móvil solo en su registro escribe', () async {
      final alone = await DeviceRegistry.empty(kListId)
          .withRecord(await aritz.record());
      expect((await ctxOf(aritz, alone)).resolve(kListId).ok, isTrue);
    });

    test('el móvil solo con su primera web: los dos escriben', () async {
      final web = await Phone.create('nora-web', 'nora', 8);
      final webRecord = await webRecordOf(web, 'nora');
      var registry = await DeviceRegistry.empty(kListId)
          .withRecord(await nora.record());
      registry = await registry.withRecord(webRecord);
      // El emparejamiento guarda móvil -> web, no web -> móvil.
      registry = await registry.withVouch(
        await Vouch.create(
          keys: nora.keys,
          voucher: await nora.record(),
          record: webRecord,
        ),
      );
      final phoneView = await nora.viewOf(registry);
      expect(phoneView.alone, isFalse);
      expect(phoneView.approvedByActive, isFalse);
      expect(ctxOfView(phoneView, nora.keys).resolve(kListId).ok, isTrue);
      final web1 = WishContext.web(
        rootView: () => phoneView,
        webDeviceId: web.id,
        webKeys: web.keys,
      ).resolve(kListId);
      expect(web1.ok, isTrue);
      expect(web1.author!.personId, 'nora');
    });

    test(
      'fundador con un invitado revocado: el fundador sigue escribiendo',
      () async {
        var registry = await registryOf([aritz, nora]);
        expect((await ctxOf(aritz, registry)).resolve(kListId).ok, isTrue);
        registry = await revoke(registry, aritz, nora);
        final founder = await ctxOf(aritz, registry);
        expect(founder.resolve(kListId).ok, isTrue);
        // El revocado no escribe.
        expectRefused(
          base(),
          await ctxOf(nora, registry),
          WishAuthorError.deviceRevoked,
        );
      },
    );

    test('un cambio de persona sin aprobar queda pendiente', () async {
      final registry = await registryOf([aritz, leo]);
      final moved = await registry.withRecord(
        await leo.record(person: 'nora', seq: 2),
      );
      expectRefused(
        base(),
        await ctxOf(leo, moved),
        WishAuthorError.devicePending,
      );
    });
  });

  test('un móvil revocado no escribe', () async {
    final registry = await registryOf([aritz, nora, leo]);
    expect((await ctxOf(leo, registry)).resolve(kListId).ok, isTrue);
    final revoked = await revoke(registry, aritz, leo);
    expectRefused(
      base(),
      await ctxOf(leo, revoked),
      WishAuthorError.deviceRevoked,
    );
    expect((await ctxOf(aritz, revoked)).resolve(kListId).ok, isTrue);
    expect((await ctxOf(nora, revoked)).resolve(kListId).ok, isTrue);
  });

  test(
    'un contexto guardado deja de valer cuando se revoca el móvil',
    () async {
      final registry = await registryOf([aritz, nora, leo]);
      var view = await leo.viewOf(registry);
      final ctx = WishContext.device(view: () => view, localKeys: leo.keys);
      var doc = base();
      final c = clockOf('l', 10);
      final ok = doc.createOwnWish(c, ctx, bike, id: 'w1');
      expect(ok.ok, isTrue);
      doc = ok.doc;
      // Se conoce la revocación: la fuente da la vista nueva.
      view = await leo.viewOf(await revoke(registry, aritz, leo));
      final before = c.last;
      for (final r in [
        doc.createOwnWish(c, ctx, bike),
        doc.editVisibleWish(c, ctx, 'w1', const VisibleWishPatch(title: 'x')),
        doc.removeWish(c, ctx, 'w1'),
      ]) {
        expect(r.error, WishError.authorRefused);
        expect(r.authorError, WishAuthorError.deviceRevoked);
        expect(r.doc, same(doc));
      }
      expect(c.last, before);
    },
  );

  test(
    'ambigüedad real: dos fichas con las mismas ids y otras claves',
    () async {
      final registry = await registryOf([aritz, nora]);
      final imposter = await Phone.create('nora-phone', 'nora', 50);
      final taken = await (await registry.withRecord(await imposter.record()))
          .withVouch(
            await Vouch.create(
              keys: aritz.keys,
              voucher: await aritz.record(),
              record: await imposter.record(),
            ),
          );
      final view = await nora.viewOf(taken);
      expect(view.revokedByOthers, isTrue);
      expect(view.selfRevoked, isFalse);
      expectRefused(
        base(),
        ctxOfView(view, nora.keys),
        WishAuthorError.deviceAmbiguous,
      );
    },
  );

  test('un móvil sin persona no escribe', () async {
    final loose = await Phone.create('loose-phone', null, 7);
    final registry = await registryOf([aritz, loose]);
    expectRefused(
      base(),
      await ctxOf(loose, registry),
      WishAuthorError.noPerson,
    );
  });

  test('una persona que ya no existe no escribe', () async {
    final registry = await registryOf([aritz, nora]);
    expectRefused(
      base(),
      await ctxOf(nora, registry, people: {'aritz', 'leo'}),
      WishAuthorError.personUnavailable,
    );
  });

  test('otra lista: el contexto y el documento deben coincidir', () async {
    final registry = await registryOf([aritz, nora]);
    final ctx = await ctxOf(nora, registry);
    expectRefused(base(listId: 'list-2'), ctx, WishAuthorError.wrongList);
    expect(ctx.resolve(kListId).ok, isTrue);
  });

  group('sugerir solo a quien tiene un dispositivo activo', () {
    test('un cambio de persona a Leo sin aprobar no cuenta', () async {
      var registry = await registryOf([aritz, nora, noraTwo]);
      // El segundo móvil de Nora pasa a ser «de Leo», pero nadie lo aprueba.
      registry = await registry.withRecord(
        await noraTwo.record(person: 'leo', seq: 2),
      );
      final a = await ctxOf(aritz, registry);
      expect(a.hasDevice('leo'), isFalse);
      final doc = base();
      final c = clockOf('a', 10);
      final before = c.last;
      final r = doc.suggestVisibleWish(c, a, 'leo', bike);
      expect(r.error, WishError.recipientHasNoDevice);
      expect(r.doc, same(doc));
      expect(c.last, before);
      // Aritz lo aprueba: ahora sí hay un dispositivo activo de Leo.
      final approved = await pairWith(
        registry,
        aritz,
        noraTwo,
        targetPerson: 'leo',
        seq: 2,
      );
      final a2 = await ctxOf(aritz, approved);
      expect(a2.hasDevice('leo'), isTrue);
      expect(doc.suggestVisibleWish(c, a2, 'leo', bike).ok, isTrue);
    });
  });

  group('webs', () {
    // Una web de Nora (persona de la web = Nora), avalada por [approver].
    // La web ve la lista desde su raíz móvil fijada: aquí, Nora.
    Future<(DeviceRegistry, Phone)> webRegistry(Phone approver) async {
      final web = await Phone.create('nora-web', 'nora', 8);
      final webRecord = await webRecordOf(web, 'nora');
      var registry = await registryOf([aritz, nora]);
      registry = await registry.withRecord(webRecord);
      registry = await registry.withVouch(
        await Vouch.create(
          keys: approver.keys,
          voucher: await approver.record(),
          record: webRecord,
        ),
      );
      return (registry, web);
    }

    Future<WishContext> webCtx(DeviceRegistry registry, Phone web) async {
      final root = await nora.viewOf(registry);
      return WishContext.web(
        rootView: () => root,
        webDeviceId: web.id,
        webKeys: web.keys,
      );
    }

    test('aprobada por un móvil de la misma persona: escribe', () async {
      final (registry, web) = await webRegistry(nora);
      final r = (await webCtx(registry, web)).resolve(kListId);
      expect(r.ok, isTrue);
      expect(r.author!.personId, 'nora');
      expect(r.author!.deviceId, 'nora-web');
    });

    test('aprobada solo por el móvil de otra persona: pendiente', () async {
      final (registry, web) = await webRegistry(aritz);
      expectRefused(
        base(),
        await webCtx(registry, web),
        WishAuthorError.devicePending,
      );
    });

    test('con otras claves o un id que no existe, no escribe', () async {
      final (registry, web) = await webRegistry(nora);
      final other = await Phone.create('nora-web', 'nora', 9);
      expectRefused(
        base(),
        await webCtx(registry, other),
        WishAuthorError.unknownDevice,
      );
      final root = await nora.viewOf(registry);
      expect(
        WishContext.web(
          rootView: () => root,
          webDeviceId: 'ghost',
          webKeys: web.keys,
        ).resolve(kListId).error,
        WishAuthorError.unknownDevice,
      );
    });
  });

  group('un solo teléfono, sin registro v2', () {
    LocalWishIdentity? identity = const LocalWishIdentity(
      listId: kListId,
      selfRecipientId: 'nora',
      paired: false,
    );
    DeviceRegistry? registry;
    setUp(() {
      identity = const LocalWishIdentity(
        listId: kListId,
        selfRecipientId: 'nora',
        paired: false,
      );
      registry = null;
    });

    WishContext ctx() => WishContext.singlePhone(
      identity: () => identity,
      registry: () => registry,
      livePeople: () => kPeople,
    );

    test('vale sin registro y es la persona de «Este móvil es de»', () {
      final r = ctx().resolve(kListId);
      expect(r.author!.personId, 'nora');
      expect(r.author!.deviceId, isNull);
      final doc = base().createOwnWish(clockOf('a', 10), ctx(), bike).doc;
      expect(doc.wishesFor('nora'), hasLength(1));
      // Sin dispositivos de otros no se sugiere a nadie.
      expect(
        doc.suggestVisibleWish(clockOf('a', 20), ctx(), 'aritz', bike).error,
        WishError.recipientHasNoDevice,
      );
    });

    test('tras emparejar se rechaza, con el mismo contexto guardado', () {
      final kept = ctx();
      var doc = base();
      final c = clockOf('a', 10);
      final ok = doc.createOwnWish(c, kept, bike, id: 'w1');
      expect(ok.ok, isTrue);
      doc = ok.doc;
      // La app empareja: la identidad que lee el contexto cambia.
      identity = const LocalWishIdentity(
        listId: kListId,
        selfRecipientId: 'nora',
        paired: true,
      );
      expectRefused(doc, kept, WishAuthorError.singlePhoneNotAllowed);
    });

    test(
      'con un registro con fichas se rechaza; de otra lista, wrongList',
      () async {
        registry = await registryOf([aritz, nora]);
        expectRefused(base(), ctx(), WishAuthorError.singlePhoneNotAllowed);
        registry = DeviceRegistry.empty('list-2');
        expectRefused(base(), ctx(), WishAuthorError.wrongList);
      },
    );

    test('sin persona, persona que no existe u otra lista', () {
      identity = const LocalWishIdentity(
        listId: kListId,
        selfRecipientId: null,
        paired: false,
      );
      expectRefused(base(), ctx(), WishAuthorError.noPerson);
      identity = const LocalWishIdentity(
        listId: kListId,
        selfRecipientId: 'nadie',
        paired: false,
      );
      expectRefused(base(), ctx(), WishAuthorError.personUnavailable);
      identity = const LocalWishIdentity(
        listId: 'list-2',
        selfRecipientId: 'nora',
        paired: false,
      );
      expectRefused(base(), ctx(), WishAuthorError.wrongList);
      identity = null;
      expectRefused(base(), ctx(), WishAuthorError.singlePhoneNotAllowed);
    });
  });
}
