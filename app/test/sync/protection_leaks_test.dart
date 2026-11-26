// Revisión de seguridad del lote 6: regalos de personas protegidas que no deben
// salir de ningún móvil (subida al servidor, sobres y ficheros) y quién puede
// activar o desactivar la protección. Pruebas a nivel de aplicación y de
// motor, contra el Worker falso.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/pairing_v2.dart';
import 'package:regalos/core/sync/protected_doc.dart';
import 'package:regalos/core/sync/protected_envelope.dart';
import 'package:regalos/core/sync/wish.dart';
import 'package:regalos/core/sync/wish_plan.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/application/family_providers.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/sharing/application/share_service.dart';
import 'package:regalos/features/sync/application/app_sync_v2_local.dart';
import 'package:regalos/core/sync/exchange_file.dart'
    show ExchangeNotReadyException;
import 'package:regalos/features/sync/application/sync_controller.dart';
import 'package:regalos/features/sync/application/sync_v2_engine.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';

import '../helpers/fake_worker_v2.dart';
import '../helpers/memory_stores.dart';
import 'protected_harness.dart';

final _localProvider = FutureProvider<AppSyncV2Local?>(
  (ref) => AppSyncV2Local.load(ref),
);

const _syncId = 'AAAAAAAAAAAAAAAAAAAAAA';

class _Phone {
  _Phone(this.phone, this.member);
  final FakePhone phone;
  final Phone member;

  FamilyController get controller =>
      phone.container.read(familyControllerProvider.notifier);
  FamilyStore get store => phone.container.read(familyStoreProvider);
  FamilyDoc get common =>
      phone.container.read(familyControllerProvider).value!.doc;

  Future<AuthorizedProjection> projection() async {
    phone.container.invalidate(localRegistryReadProvider);
    phone.container.invalidate(authorizedProjectionProvider);
    final projection = await phone.container.read(
      authorizedProjectionProvider.future,
    );
    return projection!;
  }

  Future<bool> reconcile() => phone.container
      .read(v2FamilyLockProvider)
      .run(controller.reconcileProtectedPeopleWithinLock);

  Future<AppSyncV2Local> local() async {
    final local = await phone.container.read(_localProvider.future);
    return local!;
  }
}

/// Un cliente del Worker falso que guarda el cuerpo de cada `PUT`.
class _Recording {
  _Recording(this.worker) {
    client = SyncV2Client(
      base: Uri.parse('https://sync.test'),
      sendRequest:
          (
            method,
            uri, {
            Object? body,
            Map<String, String> headers = const {},
          }) {
            if (method == 'PUT' && body is Map && body['common'] is String) {
              puts.add(decodeBase64Url(body['common'] as String));
            }
            return worker.send(method, uri, body: body, headers: headers);
          },
      openSocket: worker.socket,
    );
  }

  final FakeWorkerV2 worker;
  late final SyncV2Client client;

  /// El sobre común de cada `PUT` (también el de crear la lista).
  final puts = <Uint8List>[];

  Future<List<FamilyDoc>> docs(FamilyKey key) async => [
    for (final bytes in puts)
      FamilyDoc.fromJson(
        (await open(bytes, key: key, expectedListId: kListId)).doc,
      ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Family family;
  late FamilyDoc common;
  late FamilyKey familyKey;

  setUp(() async {
    family = await Family.create();
    familyKey = await FamilyKey.generate();
    final clock = HlcClock(node: family.aritz.id);
    common = commonWithPeople(clock).set(
      clock,
      Collections.meta,
      kProtocolRecordId,
      {kProtocolVersionField: kSyncProtocolV2},
    );
  });

  Future<_Phone> install(
    Phone member, {
    FamilyDoc? doc,
    bool withKey = false,
    SlotSet? slots,
    DeviceRegistry? registry,
  }) async {
    final fake = FakePhone();
    addTearDown(fake.dispose);
    final p = _Phone(fake, member);
    final keys = fake.container.read(deviceKeysStoreProvider);
    await keys.restore(member.keys);
    await p.store.saveFamily(
      StoredFamily(
        identity: FamilyIdentity(
          listId: kListId,
          node: member.id,
          deviceName: member.self ?? 'Móvil',
          paired: true,
          selfRecipientId: member.self,
        ),
        key: familyKey,
        doc: doc ?? common,
      ),
    );
    await p.store.saveSyncV2(
      SyncIdentityV2(listId: kListId, deviceId: member.id, syncId: _syncId),
    );
    await p.store.saveRegistry(registry ?? family.registry);
    if (withKey) await keys.saveKeyring(kListId, family.authorizedKeyring);
    if (slots != null) await p.store.saveSlots(slots);
    await fake.container.read(familyControllerProvider.future);
    return p;
  }

  Gift gift(String id, {String person = 'nora', String title = 'Bloques'}) =>
      Gift(
        id: id,
        recipientId: person,
        title: title,
        status: GiftStatus.idea,
        rawStatus: 'idea',
        surprise: false,
        year: 2026,
        giverId: 'nosotros',
        plannedCents: 1000,
      );

  List<Gift> liveFor(FamilyDoc doc, String person) => [
    for (final g in FamilyView.fromDoc(doc).gifts)
      if (g.recipientId == person) g,
  ];

  /// [base] con [n] regalos públicos tardíos para Nora escritos por [node].
  FamilyDoc withLate(FamilyDoc base, String node, int n) {
    final clock = HlcClock(node: node, last: base.maxStamp);
    var doc = base;
    for (var i = 0; i < n; i++) {
      final id = 'late$i';
      doc = doc.set(
        clock,
        Collections.gifts,
        id,
        gift(id, title: 'Tardío $i').toFields(),
      );
    }
    return doc;
  }

  /// Aritz activa la protección de Nora; devuelve sus slots. Sin [withKey],
  /// la clave de Nora que crea Aritz no es la que tiene nadie más.
  Future<(_Phone, SlotSet)> protectedByAritz({bool withKey = false}) async {
    final a = await install(family.aritz, withKey: withKey);
    await a.controller.activateProtection('nora');
    return (a, await a.store.readSlots());
  }

  /// Dos vueltas del motor de [p] contra un Worker nuevo.
  Future<(_Recording, List<FamilyDoc>)> rounds(_Phone p) async {
    final rec = _Recording(FakeWorkerV2());
    final engine = SyncV2Engine(transport: rec.client, local: await p.local());
    await engine.ensureCreated();
    await engine.sync();
    await engine.sync();
    return (rec, await rec.docs(familyKey));
  }

  group('1: regalos públicos tardíos que el móvil no puede sellar', () {
    test('A: con derecho pero sin la clave de la época, el común que sube no '
        'lleva los regalos tardíos', () async {
      final (a, slots) = await protectedByAritz();
      final leo = await install(
        family.leo,
        doc: withLate(a.common, family.leo.id, 3),
        slots: slots,
      );
      // 1.0.6: la vuelta puede proteger sola a otras personas con móvil; lo de
      // Nora no lo puede sellar.
      await leo.reconcile();
      expect(liveFor(leo.common, 'nora'), hasLength(3));
      final (rec, sent) = await rounds(leo);
      expect(rec.puts, isNotEmpty);
      for (final doc in sent) {
        expect(liveFor(doc, 'nora'), isEmpty);
      }
      // Nada se pierde: el común local los conserva para cuando llegue la
      // clave.
      expect(liveFor(leo.common, 'nora'), hasLength(3));
      // El registro sí subió: la lista existe en el servidor.
      expect(rec.worker.versionOf(_syncId), isNotNull);
    });

    test(
      'B: con clave pero con un slot ajeno ilegible, tampoco salen',
      () async {
        final (a, slots) = await protectedByAritz();
        final leo = await install(
          family.leo,
          withKey: true,
          doc: withLate(a.common, family.leo.id, 3),
          slots: slots,
        );
        await leo.reconcile(); // 1.0.6: puede proteger a otros; lo de Nora no.
        expect(liveFor(leo.common, 'nora'), hasLength(3));
        final (rec, sent) = await rounds(leo);
        expect(rec.puts, isNotEmpty);
        for (final doc in sent) {
          expect(liveFor(doc, 'nora'), isEmpty);
        }
        expect(liveFor(leo.common, 'nora'), hasLength(3));
      },
    );

    test(
      'lo que el común remoto ya tiene no se quita ni crea cambios falsos',
      () async {
        final (a, slots) = await protectedByAritz();
        final leo = await install(
          family.leo,
          doc: withLate(a.common, family.leo.id, 2),
          slots: slots,
        );
        final view = (await leo.phone.container.read(
          localRegistryViewProvider.future,
        ))!;
        final keyring = await leo.phone.container
            .read(deviceKeysStoreProvider)
            .readKeyring(kListId);
        final local = leo.common;
        FamilyDoc publishable(FamilyDoc? remote) => publishableCommon(
          common: local,
          slots: slots,
          keyring: keyring,
          view: view,
          remote: remote,
        );
        expect(liveFor(publishable(null), 'nora'), isEmpty);
        // Si el servidor ya los tiene, el común publicable es el mismo.
        expect(publishable(local).canonicalJson(), local.canonicalJson());
        // Las personas no protegidas no se tocan.
        final other = local.set(
          HlcClock(node: family.leo.id, last: local.maxStamp),
          Collections.gifts,
          'leo-gift',
          gift('leo-gift', person: 'leo').toFields(),
        );
        expect(
          liveFor(
            publishableCommon(
              common: other,
              slots: slots,
              keyring: keyring,
              view: view,
            ),
            'leo',
          ),
          hasLength(1),
        );
      },
    );
  });

  group('retoques tras la revisión', () {
    test('el móvil de la propia persona conserva sus regalos escritos sin '
        'conexión (N2)', () async {
      final (a, slots) = await protectedByAritz();
      final nora = await install(
        family.nora,
        doc: withLate(a.common, family.nora.id, 2),
        slots: slots,
      );
      final view = (await nora.phone.container.read(
        localRegistryViewProvider.future,
      ))!;
      expect(view.myPerson, 'nora');
      final keyring = await nora.phone.container
          .read(deviceKeysStoreProvider)
          .readKeyring(kListId);
      final out = publishableCommon(
        common: nora.common,
        slots: slots,
        keyring: keyring,
        view: view,
      );
      expect(liveFor(out, 'nora'), hasLength(2));
      // Lo mismo desde otro móvil sí los quita.
      final leoView = (await (await install(
        family.leo,
        doc: nora.common,
        slots: slots,
      )).phone.container.read(localRegistryViewProvider.future))!;
      expect(
        liveFor(
          publishableCommon(
            common: nora.common,
            slots: slots,
            keyring: keyring,
            view: leoView,
          ),
          'nora',
        ),
        isEmpty,
      );
    });

    test(
      'una familia v2 sin lo local listo no exporta el común sin filtrar',
      () async {
        final (a, slots) = await protectedByAritz();
        final leo = await install(
          family.leo,
          doc: withLate(a.common, family.leo.id, 1),
          slots: slots,
        );
        await leo.store.saveSyncV2(
          SyncIdentityV2(
            listId: 'otra-lista',
            deviceId: family.leo.id,
            syncId: _syncId,
          ),
        );
        await expectLater(
          leo.phone.container.read(shareServiceProvider).buildEnvelope(),
          throwsA(isA<ExchangeNotReadyException>()),
        );
      },
    );

    test('pedir protección sube la revisión desde la mayor de la publicada '
        'y la autenticada', () async {
      final clock = HlcClock(node: family.aritz.id);
      final plain = requestProtection(common, clock, 'nora');
      expect(publishedPolicy(plain, 'nora')!.rev, 1);
      final next = requestProtection(
        common,
        clock,
        'nora',
        authenticated: const PolicyState(hideOwnGifts: false, rev: 5),
      );
      expect(
        publishedPolicy(next, 'nora'),
        const PolicyState(hideOwnGifts: true, rev: 6),
      );
    });
  });

  group('2: las exportaciones salen del común publicable', () {
    test('J: el sobre de siempre no lleva los regalos tardíos', () async {
      final (a, slots) = await protectedByAritz();
      final leo = await install(
        family.leo,
        doc: withLate(a.common, family.leo.id, 3),
        slots: slots,
      );
      final bytes = await leo.phone.container
          .read(shareServiceProvider)
          .buildEnvelope();
      final opened = await open(
        bytes,
        key: leo.controller.familyKey!,
        expectedListId: kListId,
        acceptFileVersion: true,
      );
      final doc = FamilyDoc.fromJson(opened.doc);
      expect(liveFor(doc, 'nora'), isEmpty);
      expect(opened.doc.toString(), isNot(contains('Tardío')));
      expect(liveFor(leo.common, 'nora'), hasLength(3));
    });

    test('I: las lápidas y los regalos del ámbito secreto no salen', () async {
      final a = await install(family.aritz, withKey: true);
      await a.controller.activateProtection('nora');
      await a.controller.upsertGift(gift('s1', title: 'Secreto uno'));
      await a.controller.upsertGift(gift('s2', title: 'Secreto dos'));
      await a.controller.deleteGift('s1');
      final bytes = await a.phone.container
          .read(shareServiceProvider)
          .buildEnvelope();
      final opened = await open(
        bytes,
        key: a.controller.familyKey!,
        expectedListId: kListId,
        acceptFileVersion: true,
      );
      final doc = FamilyDoc.fromJson(opened.doc);
      expect(doc.record(Collections.gifts, 's1'), isNull);
      expect(doc.record(Collections.gifts, 's2'), isNull);
      expect(jsonEncode(opened.doc), isNot(contains('Secreto')));
      expect(
        (doc.collections[Collections.gifts] ?? const {}).length,
        (a.common.collections[Collections.gifts] ?? const {}).length,
      );
    });
  });

  group('quién puede activar o desactivar', () {
    // Rechazar es lanzar o no hacer nada (devolver `false`, o terminar sin
    // cambiar el común ni los slots): lo que no puede pasar es cambiar algo.
    Future<void> expectRefused(
      _Phone p,
      Future<Object?> Function() action,
    ) async {
      final common = p.common.canonicalJson();
      final slots = [
        for (final s in (await p.store.readSlots()).all) s.bytes.toList(),
      ];
      Object? result;
      try {
        result = await action();
      } catch (_) {
        result = false;
      }
      expect(result, anyOf(isNull, isFalse));
      expect(p.common.canonicalJson(), common);
      expect([
        for (final s in (await p.store.readSlots()).all) s.bytes.toList(),
      ], slots);
    }

    test('C: el móvil de la persona protegida no activa ni desactiva ni '
        've ninguno de sus regalos', () async {
      final a = await install(family.aritz, withKey: true);
      await a.controller.upsertGift(gift('old'));
      await a.controller.activateProtection('nora');
      await a.controller.upsertGift(gift('secret'));
      final slots = await a.store.readSlots();
      final n = await install(family.nora, doc: a.common, slots: slots);
      await expectRefused(n, () => n.controller.deactivateProtection('nora'));
      await expectRefused(n, () => n.controller.activateProtection('nora'));
      await expectRefused(
        n,
        () => n.controller.setGiftStatus('secret', GiftStatus.bought),
      );
      await expectRefused(n, () => n.controller.deleteGift('secret'));
      final projection = await n.projection();
      expect(projection.view.gifts, isEmpty);
      expect(projection.lockedBlocks, [const SecretBlock('nora')]);
      // Con la clave en el móvil, sigue sin poder.
      await n.phone.container
          .read(deviceKeysStoreProvider)
          .saveKeyring(kListId, family.authorizedKeyring);
      await expectRefused(n, () => n.controller.deactivateProtection('nora'));
      expect((await n.projection()).view.gifts, isEmpty);
    });

    test('G: un móvil revocado que lo sabe no activa, no desactiva y no ve '
        'regalos', () async {
      final a = await install(family.aritz, withKey: true);
      await a.controller.upsertGift(gift('old'));
      await a.controller.activateProtection('nora');
      final slots = await a.store.readSlots();
      final change = await revokeDevice(
        registry: family.registry,
        view: family.view,
        myKeys: family.aritz.keys,
        deviceId: family.leo.id,
      );
      final rev = await install(
        family.leo,
        withKey: true,
        doc: a.common,
        slots: slots,
        registry: change.registry,
      );
      await expectRefused(
        rev,
        () => rev.controller.deactivateProtection('nora'),
      );
      await expectRefused(rev, () => rev.controller.activateProtection('nora'));
      await expectRefused(rev, () => rev.controller.upsertGift(gift('x')));
      final projection = await rev.projection();
      expect(projection.view.gifts, isEmpty);
      expect(projection.lockedBlocks, contains(const SecretBlock('nora')));
    });

    test('H: el móvil de Nora que pasa a ser de otra persona queda pendiente '
        'y no puede activar ni desactivar', () async {
      final a = await install(family.aritz, withKey: true);
      await a.controller.upsertGift(gift('old'));
      await a.controller.activateProtection('nora');
      final slots = await a.store.readSlots();
      final n = await install(family.nora, doc: a.common, slots: slots);
      await n.controller.changeSelfPerson('leo');
      final view = (await n.phone.container.read(
        localRegistryViewProvider.future,
      ))!;
      expect(view.selfApproved, isFalse);
      expect(view.selfEntitled('nora'), isFalse);
      await expectRefused(n, () => n.controller.deactivateProtection('nora'));
      await expectRefused(n, () => n.controller.activateProtection('nora'));
      final projection = await n.projection();
      expect(projection.view.gifts, isEmpty);
      expect(projection.lockedBlocks, contains(const SecretBlock('nora')));
    });
  });

  group('una vuelta entre dos móviles', () {
    test('el móvil de la persona protegida no guarda ningún regalo ni sabe '
        'ni cuántos son', () async {
      final a = await install(family.aritz, withKey: true);
      await a.controller.upsertGift(gift('old', title: 'Antiguo'));
      await a.controller.activateProtection('nora');
      await a.controller.upsertGift(gift('s1', title: 'Secreto uno'));
      await a.controller.upsertGift(gift('s2', title: 'Secreto dos'));
      final n = await install(family.nora, doc: a.common);

      final worker = FakeWorkerV2();
      final transport = worker.client();
      final engineA = SyncV2Engine(
        transport: transport,
        local: await a.local(),
      );
      await engineA.ensureCreated();
      worker.addCredentialForTesting(
        _syncId,
        family.nora.id,
        family.nora.keys.serviceCredential,
      );
      await engineA.sync();
      final engineN = SyncV2Engine(
        transport: transport,
        local: await n.local(),
      );
      await engineN.sync();
      await engineA.sync();
      await engineN.sync();

      // El móvil de Aritz sigue viendo sus dos secretos.
      expect((await a.projection()).view.gifts.map((g) => g.id).toSet(), {
        'old',
        's1',
        's2',
      });
      // El de Nora: ninguno, ni su número; solo el bloque de tamaño fijo.
      final projection = await n.projection();
      expect(projection.view.gifts, isEmpty);
      expect(projection.view.allGifts, isEmpty);
      expect(projection.lockedBlocks, [const SecretBlock('nora')]);
      expect(liveFor(n.common, 'nora'), isEmpty);
      expect(await n.store.readScope('nora'), isNull);
      expect(await n.store.readOverflow('nora'), isEmpty);
      final keyring = await n.phone.container
          .read(deviceKeysStoreProvider)
          .readKeyring(kListId);
      // 1.0.6: protege sola a las demás personas con móvil; nunca a Nora.
      expect(keyring.people, isNot(contains('nora')));
      // Lo guardado no lleva ningún título, ni en el común ni en los slots.
      final stored = [
        jsonEncode(n.common.toJson()),
        for (final s in (await n.store.readSlots()).all)
          latin1.decode(s.bytes, allowInvalid: true),
      ].join('\n');
      expect(stored, isNot(contains('Secreto')));
      expect(stored, isNot(contains('Antiguo')));
    });
  });

  group('3: deseos y planes (ADR 0010)', () {
    const wishId = 'wbike';

    /// Aritz con la protección de Nora activa, el deseo de Nora ya escrito
    /// en su móvil y recibido por Aritz, y un plan con datos privados.
    Future<(_Phone, _Phone)> withPlan() async {
      final a = await install(family.aritz, withKey: true);
      await a.controller.activateProtection('nora');
      // Leo's phone, up to date, has published its slot of Nora's block: a
      // plan is only written when every other reader announces plans.
      final leoSlot = await SealedSlot.seal(
        writerKeys: family.leo.keys,
        writer: family.leo.id,
        revision: 1,
        key: family.key,
        policy: const PolicyState(hideOwnGifts: true, rev: 1),
        doc: FamilyDoc.empty(kListId),
      );
      final (withLeo, _) = await (await a.store.readSlots()).merge([
        leoSlot,
      ], view: family.view);
      await a.store.saveSlots(withLeo);
      final n = await install(
        family.nora,
        doc: a.common,
        slots: await a.store.readSlots(),
      );
      final w = await n.controller.createOwnWish(
        const VisibleWishPatch(title: 'Bicicleta', year: 2026),
        id: wishId,
      );
      expect(w.ok, isTrue, reason: '${w.error} ${w.authorError}');
      await a.controller.mergeRemote(n.common, fromNode: family.nora.id);
      expect((await a.controller.claimWish(wishId, planId: 'p1')).ok, isTrue);
      final edit = await a.controller.editWishPlan(
        'nora',
        'p1',
        const PrivatePlanPatch(
          store: 'Tienda del plan',
          giverNote: 'Nota del plan',
          plannedCents: 3000,
        ),
      );
      expect(edit.ok, isTrue);
      return (a, n);
    }

    const secrets = [
      'Tienda del plan',
      'Nota del plan',
      'wishPlans',
      'sourceWishId',
      'claimantPersonId',
    ];

    test('J: el sobre de siempre lleva el deseo y nunca el plan', () async {
      final (a, _) = await withPlan();
      final bytes = await a.phone.container
          .read(shareServiceProvider)
          .buildEnvelope();
      final opened = await open(
        bytes,
        key: a.controller.familyKey!,
        expectedListId: kListId,
        acceptFileVersion: true,
      );
      final doc = FamilyDoc.fromJson(opened.doc);
      expect(doc.wishesFor('nora').map((w) => w.title), ['Bicicleta']);
      final raw = jsonEncode(opened.doc);
      for (final secret in secrets) {
        expect(raw, isNot(contains(secret)));
      }
    });

    test('A/B: el común que sube tampoco lleva planes, ni con regalos vacíos '
        'ni con un plan colado en el común local', () async {
      final (a, _) = await withPlan();
      // Un común local sucio: un plan colado y un campo de plan.
      final dirty = a.common.set(
        HlcClock(node: family.aritz.id, last: a.common.maxStamp),
        ScopeCollections.wishPlans,
        'pX',
        {
          'recipientId': 'nora',
          'sourceWishId': wishId,
          'claimantPersonId': 'aritz',
          'title': 'Bicicleta',
          'status': 'decided',
          'giverNote': 'Nota del plan',
        },
      );
      await a.store.saveDoc(dirty);
      final (rec, sent) = await rounds(a);
      expect(rec.puts, isNotEmpty);
      expect(sent, isNotEmpty);
      for (final doc in sent) {
        expect(
          doc.collections.containsKey(ScopeCollections.wishPlans),
          isFalse,
        );
        expect(jsonEncode(doc.toJson()), isNot(contains('Nota del plan')));
        expect(doc.wishesFor('nora'), hasLength(1));
      }
    });

    test(
      'I: lo que llega por un fichero o la red no mete planes en el común',
      () async {
        final (a, n) = await withPlan();
        final hostile = n.common.set(
          HlcClock(node: 'x', last: n.common.maxStamp),
          ScopeCollections.wishPlans,
          'pZ',
          {'recipientId': 'nora', 'sourceWishId': wishId, 'title': 'T'},
        );
        await n.controller.mergeRemote(hostile, fromNode: 'x');
        expect(
          n.common.collections.containsKey(ScopeCollections.wishPlans),
          isFalse,
        );
        expect(n.common.wishesFor('nora'), hasLength(1));
        expect(a.common.wishesFor('nora'), hasLength(1));
      },
    );

    test('C/G/H: el móvil de Nora no coge, un revocado no escribe y quien '
        'cambia de persona no coge', () async {
      final (a, n) = await withPlan();
      // C: ni con la clave en el móvil.
      await n.phone.container
          .read(deviceKeysStoreProvider)
          .saveKeyring(kListId, family.authorizedKeyring);
      final before = n.common.canonicalJson();
      final claim = await n.controller.claimWish(wishId, planId: 'pN');
      expect(claim.ok, isFalse);
      expect(n.common.canonicalJson(), before);
      expect((await n.projection()).plansByWish, isEmpty);
      // G: un móvil revocado que lo sabe no escribe deseos ni coge.
      final change = await revokeDevice(
        registry: family.registry,
        view: family.view,
        myKeys: family.aritz.keys,
        deviceId: family.leo.id,
      );
      final rev = await install(
        family.leo,
        withKey: true,
        doc: a.common,
        slots: await a.store.readSlots(),
        registry: change.registry,
      );
      final revBefore = rev.common.canonicalJson();
      expect(
        (await rev.controller.claimWish(wishId, planId: 'pL')).ok,
        isFalse,
      );
      expect(
        (await rev.controller.createOwnWish(
          const VisibleWishPatch(title: 'Algo', year: 2026),
        )).ok,
        isFalse,
      );
      expect(rev.common.canonicalJson(), revBefore);
      expect((await rev.projection()).plansByWish, isEmpty);
      // H: el móvil de Nora que pasa a ser de Leo queda pendiente.
      await n.controller.changeSelfPerson('leo');
      final view = (await n.phone.container.read(
        localRegistryViewProvider.future,
      ))!;
      expect(view.selfEntitled('nora'), isFalse);
      expect((await n.controller.claimWish(wishId, planId: 'pH')).ok, isFalse);
      expect((await n.projection()).plansByWish, isEmpty);
    });
  });
}
