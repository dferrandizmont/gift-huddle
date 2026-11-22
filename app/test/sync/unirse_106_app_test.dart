// 1.0.6 en la app, de punta a punta: quien invita elige para quién es el
// móvil nuevo, ese móvil entra ya asignado y aprobado, y en él no se pinta
// ningún regalo para su persona; la protección se activa antes de aprobar;
// «¿Quién eres?» antes de invitar; y al quedarse solo vuelve a ver lo suyo.
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/prefs/shared_preferences_provider.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/device_keys.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/pairing_v2.dart'
    show PairingOffer, joinPairing, kHostPicksPersonField;
import 'package:regalos/core/sync/protected_doc.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/application/family_providers.dart';
import 'package:regalos/features/family/application/self_person_gate.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/sync/application/app_sync_v2_local.dart';
import 'package:regalos/features/sync/application/pairing_v2_controller.dart';
import 'package:regalos/features/sync/application/pairing_v2_flow.dart';
import 'package:regalos/features/sync/application/sync_v2_engine.dart';
import 'package:regalos/features/sync/application/sync_controller.dart';
import 'package:regalos/features/sync/data/sync_config.dart';
import 'package:regalos/features/sync/data/sync_transport.dart'
    show SyncFailure, SyncTransportException;
import 'package:regalos/features/sync/data/sync_transport_common.dart';

import '../helpers/fake_sync_server.dart';
import '../helpers/fake_worker_v2.dart';
import '../helpers/memory_stores.dart';
import '../helpers/pump_app.dart';
import 'sync_harness.dart';

final _localProvider = FutureProvider((ref) => AppSyncV2Local.load(ref));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeWorkerV2 worker;

  setUp(() => worker = FakeWorkerV2());

  Future<FakePhone> phone() async {
    final p = FakePhone(
      prefs: await mockPrefs(),
      syncHost: null,
      extraOverrides: [
        syncHostProvider.overrideWithValue(kTestHost),
        invitationOriginProvider.overrideWithValue(''),
        syncTransportProvider.overrideWithValue(FakeSyncServer().connect()),
        syncV2TransportProvider.overrideWithValue(worker.client()),
        syncTimingProvider.overrideWithValue(kFastTiming),
      ],
    );
    addTearDown(p.dispose);
    p.container.read(syncControllerProvider);
    p.container.read(sharedPreferencesProvider);
    await p.container.read(familyControllerProvider.future);
    return p;
  }

  FamilyController family(FakePhone p) =>
      p.container.read(familyControllerProvider.notifier);

  Gift gift(String id, String recipientId, String title) => Gift(
    id: id,
    recipientId: recipientId,
    title: title,
    status: GiftStatus.idea,
    rawStatus: 'idea',
    surprise: false,
    year: 2026,
  );

  /// Lo que pinta el móvil (la vista autorizada).
  Future<Set<String>> shown(FakePhone p) async {
    await p.container.read(authorizedProjectionProvider.future);
    return {
      for (final g in p.container.read(familyFullViewProvider).allGifts)
        g.title,
    };
  }

  /// A: familia con Aritz (su móvil), Nora y Leo, y un regalo para cada uno.
  Future<FakePhone> owner() async {
    final a = await phone();
    final fam = family(a);
    await fam.createFamily(deviceName: 'Aritz');
    for (final (id, name) in [
      ('aritz', 'Aritz'),
      ('nora', 'Nora'),
      ('leo', 'Leo'),
    ]) {
      await fam.upsertRecipient(
        Recipient(id: id, name: name, colorIndex: 0, archived: false),
      );
    }
    final self = await a.container
        .read(selfPersonGateActionsProvider)
        .choose('aritz');
    expect(self, ChangeSelfPersonResult.localOnly);
    await fam.upsertGift(gift('g-nora', 'nora', 'Libro'));
    await fam.upsertGift(gift('g-leo', 'leo', 'Tren'));
    return a;
  }

  /// A invita a [b] para [person]: B no elige nada.
  Future<void> invite(FakePhone a, FakePhone b, String person) async {
    final host = a.container.read(pairingV2HostProvider.notifier);
    await host.start(guestPerson: person);
    final state = a.container.read(pairingV2HostProvider);
    expect(
      state.phase,
      PairingV2HostPhase.waiting,
      reason: '${state.failureCode}',
    );
    final link = state.link!;
    final guest = b.container.read(pairingV2GuestProvider.notifier);
    await guest.begin(link.substring(link.indexOf('#') + 1));
    final assigned = b.container.read(pairingV2GuestProvider);
    expect(assigned.hostAssigned, isTrue);
    expect(assigned.assignedPersonId, person);
    await eventually(
      () =>
          a.container.read(pairingV2HostProvider).phase ==
              PairingV2HostPhase.compare &&
          b.container.read(pairingV2GuestProvider).phase ==
              PairingV2GuestPhase.compare,
      reason: 'los dos enseñan el código',
    );
    guest.confirmCode();
    await host.confirm();
    expect(
      a.container.read(pairingV2HostProvider).phase,
      PairingV2HostPhase.done,
      reason: 'sin otro paso: la persona la eligió A',
    );
    await eventually(
      () =>
          b.container.read(pairingV2GuestProvider).phase ==
          PairingV2GuestPhase.done,
      reason: 'B dentro',
    );
  }

  Future<RegistryView> viewOf(FakePhone p) async {
    final RegistryView? view = await p.container.read(
      localRegistryViewProvider.future,
    );
    return view!;
  }

  test('el incidente: A elige a Nora para el móvil nuevo; en él no aparece '
      'ningún regalo para Nora, entra aprobado y sus regalos ya están en '
      'secreto', () async {
    final a = await owner();
    final b = await phone();
    await invite(a, b, 'nora');

    // B entra asignado y aprobado, sin segunda aprobación.
    final idB = b.container.read(familyControllerProvider).value!.identity!;
    expect(idB.selfRecipientId, 'nora');
    final viewB = await viewOf(b);
    expect(viewB.myPerson, 'nora');
    expect(viewB.selfApproved, isTrue);
    // El común que recibió B no lleva ningún regalo vivo para Nora: A lo
    // puso en secreto antes del checkpoint.
    final common = b.container.read(familyControllerProvider).value!.doc;
    expect(
      common.collections[Collections.gifts]!.values.where(
        (r) => !r.isDeleted && r['recipientId'] == 'nora',
      ),
      isEmpty,
    );
    expect(publishedPolicy(common, 'nora')?.hideOwnGifts, isTrue);
    // Y no se pinta: ni en la lista ni en la rejilla ni en el presupuesto.
    expect(await shown(b), {'Tren'});
    expect(b.container.read(giftsForProvider('nora')), isEmpty);
    expect(
      b.container.read(secretBlocksProvider),
      contains(const SecretBlock('nora')),
    );
    // En el editor, Nora no se puede elegir en su propio móvil.
    final access = await b.container.read(giftRecipientAccessProvider.future);
    final nora = access.singleWhere((x) => x.recipient.id == 'nora');
    expect(nora.canSelect, isFalse);
    expect(nora.reason, ProtectedPersonReason.ownGiftsHidden);
    expect(
      await b.container.read(ownGiftRequestStateProvider.future),
      OwnGiftRequestState.protectionRestricted,
    );
    await expectLater(
      family(b).upsertGift(gift('own', 'nora', 'Bufanda')),
      throwsA(isA<ProtectedPersonException>()),
    );

    // A sigue viendo lo de Nora (lo tiene en secreto) y lo de Leo.
    expect(await shown(a), {'Libro', 'Tren'});
  });

  test('capa de pantalla aunque nadie haya protegido todavía: un regalo '
      'público para Nora que llega no se pinta en su móvil', () async {
    final a = await owner();
    final b = await phone();
    await invite(a, b, 'nora');
    // Un regalo público tardío para Nora (por ejemplo, de un móvil 1.0.5).
    final doc = b.container.read(familyControllerProvider).value!.doc;
    final late = doc.set(
      HlcClock(node: 'otro-movil', last: doc.maxStamp),
      Collections.gifts,
      'late',
      gift('late', 'nora', 'Puzle').toFields(),
    );
    await family(b).mergeRemote(late, fromNode: 'otro-movil');
    expect(
      b.container
          .read(familyControllerProvider)
          .value!
          .doc
          .record(Collections.gifts, 'late')!
          .isDeleted,
      isFalse,
      reason: 'el regalo está en el móvil, pero no se pinta',
    );
    expect(await shown(b), isNot(contains('Puzle')));
  });

  test(
    'quien invita sin persona no crea nada: antes, «¿Quién eres?»',
    () async {
      final a = await phone();
      await family(a).createFamily(deviceName: 'Aritz');
      await family(a).upsertRecipient(
        const Recipient(
          id: 'nora',
          name: 'Nora',
          colorIndex: 0,
          archived: false,
        ),
      );
      final gate = await a.container.read(selfPersonGateProvider.future);
      expect(gate.answered, isFalse);
      expect(gate.suggestedName, 'Aritz');
      final host = a.container.read(pairingV2HostProvider.notifier);
      await host.choose();
      expect(a.container.read(pairingV2HostProvider).needsWhoAreYou, isTrue);
      await host.start(guestPerson: 'nora');
      final failed = a.container.read(pairingV2HostProvider);
      expect(failed.phase, PairingV2HostPhase.failed);
      expect(failed.needsSelfPerson, isTrue);
      expect(worker.calls['POST invites'] ?? 0, 0);
      expect(await a.container.read(familyStoreProvider).readSyncV2(), isNull);
    },
  );

  test('«No estoy en la lista» crea la persona y la asigna; la primera ficha '
      'nace con ella y aprobada', () async {
    final a = await phone();
    await family(a).createFamily(deviceName: 'Aritz');
    final id = await a.container
        .read(selfPersonGateActionsProvider)
        .notOnList('Aritz');
    final fam = a.container.read(familyControllerProvider).value!;
    expect(fam.identity!.selfRecipientId, id);
    expect(fam.view.recipientsById[id]!.name, 'Aritz');
    expect(fam.view.recipientsById[id]!.noGifts, isFalse);
    expect(
      (await a.container.read(selfPersonGateProvider.future)).answered,
      isTrue,
    );
    // Invitar crea la familia v2 con la persona ya en la ficha (seq 1).
    final b = await phone();
    // El móvil nuevo es de alguien que solo regala.
    await family(a).upsertRecipient(
      const Recipient(
        id: 'leo-solo',
        name: 'Leo',
        colorIndex: 1,
        archived: false,
        noGifts: true,
      ),
    );
    await invite(a, b, 'leo-solo');
    final view = await viewOf(a);
    expect(view.myPerson, id);
    expect(view.selfApproved, isTrue);
  });

  test('«Nadie» es una persona que solo regala: no sale como destinataria y '
      'el móvil conserva sus derechos', () async {
    final a = await phone();
    await family(a).createFamily(deviceName: 'Aritz');
    await family(a).upsertRecipient(
      const Recipient(id: 'nora', name: 'Nora', colorIndex: 0, archived: false),
    );
    await family(a).upsertGift(gift('g-nora', 'nora', 'Libro'));
    final id = await a.container
        .read(selfPersonGateActionsProvider)
        .nobody('Aritz');
    final view = a.container.read(familyViewProvider);
    expect(view.recipientsById[id]!.noGifts, isTrue);
    expect(view.giftRecipients.map((r) => r.id), ['nora']);
    expect(view.repartoRecipients.map((r) => r.id), ['nora']);
    // Puede conectar el móvil de Nora: tiene derecho a sus sorpresas.
    final b = await phone();
    await invite(a, b, 'nora');
    expect((await viewOf(a)).selfEntitled('nora'), isTrue);
    expect(await shown(b), isEmpty);
  });

  test(
    'un móvil v2 solo cuya ficha ya salió del móvil: elige persona, queda '
    'pendiente y el aval del invitado lo aprueba antes de proteger',
    () async {
      final a = await owner();
      // A pasa a v2 (una invitación que cancela) y su ficha sale del móvil
      // con la sincronización puesta: ya no se puede sustituir sin más.
      final host = a.container.read(pairingV2HostProvider.notifier);
      await host.start(guestPerson: 'nora');
      await host.cancel();
      final store = a.container.read(familyStoreProvider);
      expect(await store.readSyncV2(), isNotNull);
      await store.enableRemoteSync();
      expect((await viewOf(a)).alone, isTrue);
      // A cambia de persona estando solo: la ficha nueva espera aprobación
      // (choque 6).
      final result = await family(a).changeSelfPerson('leo');
      expect(result, ChangeSelfPersonResult.pendingApproval);
      a.container.invalidate(localRegistryReadProvider);
      expect((await viewOf(a)).selfApproved, isFalse);
      // Conecta el móvil de Nora: el aval del invitado aprueba a A dentro de
      // `confirm` y ahí se ponen en secreto los regalos de Nora.
      final c = await phone();
      await invite(a, c, 'nora');
      a.container.invalidate(localRegistryReadProvider);
      expect((await viewOf(a)).selfApproved, isTrue);
      final common = c.container.read(familyControllerProvider).value!.doc;
      expect(publishedPolicy(common, 'nora')?.hideOwnGifts, isTrue);
      expect(await shown(c), isNot(contains('Libro')));
    },
  );

  test('un invitado 1.0.6 no entra con un anfitrión sin la marca: pide '
      'actualizar', () async {
    final a = await owner();
    final host = a.container.read(pairingV2HostProvider.notifier);
    await host.start(guestPerson: 'nora');
    final link = a.container.read(pairingV2HostProvider).link!;
    // Un anfitrión 1.0.5: la misma oferta sin la marca.
    worker.tamper = (method, uri, response) {
      if (!uri.path.endsWith('/offer')) return response;
      final json = response.json();
      final offer = Map<String, Object?>.from(json['offer']! as Map)
        ..remove(kHostPicksPersonField);
      return SyncResponse(
        response.status,
        response.headers,
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({...json, 'offer': offer, 'guestPerson': null}),
          ),
        ),
      );
    };
    final b = await phone();
    final guest = b.container.read(pairingV2GuestProvider.notifier);
    await guest.begin(link.substring(link.indexOf('#') + 1));
    worker.tamper = null;
    final state = b.container.read(pairingV2GuestProvider);
    expect(state.phase, PairingV2GuestPhase.failed);
    expect(state.versionMismatch, isTrue);
    await host.cancel();
  });

  test('al dejar de sincronizar, el móvil de Nora se queda solo: purga lo '
      'que quedaba para Nora y vuelve a ver y añadir lo suyo', () async {
    final a = await owner();
    final b = await phone();
    await invite(a, b, 'nora');
    await b.container.read(syncControllerProvider.notifier).stopSyncing();
    await b.container.read(familyControllerProvider.future);
    b.container.invalidate(localRegistryReadProvider);
    final view = await viewOf(b);
    expect(view.alone, isTrue);
    expect(
      b.container.read(familyControllerProvider).value!.identity!.paired,
      isFalse,
    );
    // Nada de lo que estaba en secreto, y ningún regalo vivo para Nora.
    final doc = b.container.read(familyControllerProvider).value!.doc;
    expect(
      doc.collections[Collections.gifts]!.values.where(
        (r) => !r.isDeleted && r['recipientId'] == 'nora',
      ),
      isEmpty,
    );
    // Vuelve a poder añadir y ver lo suyo.
    await family(b).upsertGift(gift('mine', 'nora', 'Bufanda'));
    expect(await shown(b), contains('Bufanda'));
    expect(await shown(b), isNot(contains('Libro')));
  });

  // ---------------------------------------------- revisión de la revisión (FIX)

  Future<AppSyncV2Local> localOf(FakePhone p) async {
    final AppSyncV2Local? local = await p.container.read(_localProvider.future);
    return local!;
  }

  /// A pasa a v2 (una invitación que cancela).
  Future<void> toV2(FakePhone a, String person) async {
    final host = a.container.read(pairingV2HostProvider.notifier);
    await host.start(guestPerson: person);
    await host.cancel();
  }

  Future<String?> pendingGuestOf(FakePhone p) =>
      p.container.read(familyStoreProvider).readPairingPendingGuest();

  test('1: el anfitrión no acepta un móvil sin persona', () async {
    final a = await owner();
    final host = a.container.read(pairingV2HostProvider.notifier);
    await host.start(guestPerson: 'nora');
    final link = a.container.read(pairingV2HostProvider).link!;
    // Un invitado viejo que responde «Elegir después».
    final guest = await PairingV2Guest.open(
      transport: worker.client(),
      inviteId: link.substring(link.indexOf('#') + 1),
      keys: await DeviceKeys.generate(),
      deviceIdFor: (_, _) => 'viejo',
    );
    // QA 1.0.6, m1: el servidor la deja pasar y el anfitrión la rechaza:
    // pide actualizar y cancela, sin aprobar a nadie.
    await guest.answer(withoutPerson: true);
    await eventually(
      () =>
          a.container.read(pairingV2HostProvider).phase ==
          PairingV2HostPhase.failed,
      reason: 'el anfitrión no la acepta',
    );
    expect(a.container.read(pairingV2HostProvider).guestOutdated, isTrue);
    final view = await viewOf(a);
    expect(view.members, [view.me]);
  });

  test('2: con un cambio de persona pendiente, lo de la persona de antes '
      'sigue sin verse y se purga al quedarse solo', () async {
    final a = await owner();
    final b = await phone();
    await invite(a, b, 'nora');
    // Un regalo público tardío para Nora, oculto solo por la pantalla.
    final doc = b.container.read(familyControllerProvider).value!.doc;
    await family(b).mergeRemote(
      doc.set(
        HlcClock(node: 'otro-movil', last: doc.maxStamp),
        Collections.gifts,
        'late',
        gift('late', 'nora', 'Puzle').toFields(),
      ),
      fromNode: 'otro-movil',
    );
    expect(await shown(b), isNot(contains('Puzle')));
    // B pasa a ser de Leo: espera aprobación y Nora sigue oculta.
    expect(
      await family(b).changeSelfPerson('leo'),
      ChangeSelfPersonResult.pendingApproval,
    );
    b.container.invalidate(localRegistryReadProvider);
    expect((await viewOf(b)).selfApproved, isFalse);
    expect(
      b.container.read(familyControllerProvider).value!.identity!.formerSelf,
      {'nora'},
    );
    expect(await shown(b), isNot(contains('Puzle')));
    // Al quedarse solo, se purga también lo de Nora.
    await b.container.read(syncControllerProvider.notifier).stopSyncing();
    await b.container.read(familyControllerProvider.future);
    final after = b.container.read(familyControllerProvider).value!;
    expect(after.identity!.formerSelf, isEmpty);
    expect(after.doc.record(Collections.gifts, 'late')!.isDeleted, isTrue);
  });

  test('3: en v1 emparejado, el diálogo de borrar no nombra regalos de la '
      'persona de este móvil', () async {
    final a = await phone();
    final fam = family(a);
    await fam.createFamily(deviceName: 'Nora');
    await fam.upsertRecipient(
      const Recipient(id: 'nora', name: 'Nora', colorIndex: 0, archived: false),
    );
    await fam.upsertGiver(
      const Giver(
        id: 'nosotros',
        name: 'Nosotros',
        colorIndex: 0,
        householdPays: true,
        archived: false,
      ),
    );
    await fam.upsertGift(
      const Gift(
        id: 'g-nora',
        recipientId: 'nora',
        title: 'Libro',
        status: GiftStatus.idea,
        rawStatus: 'idea',
        surprise: false,
        year: 2026,
        giverId: 'nosotros',
      ),
    );
    final before = await fam.giverColumnDeleteImpact('nosotros');
    expect(before.affectedGifts.map((g) => g.title), ['Libro']);
    await fam.changeSelfPerson('nora');
    await fam.markPaired();
    final impact = await fam.giverColumnDeleteImpact('nosotros');
    expect(impact.affectedGifts.map((g) => g.title), isEmpty);
  });

  test('5: si el común que se aprueba no protege a su persona, no se aprueba '
      'y el invitado queda revocado aquí', () async {
    final a = await owner();
    await toV2(a, 'nora');
    final local = await localOf(a);
    final store = a.container.read(familyStoreProvider);
    // Como el controlador: mientras se empareja, no se retira la lista.
    a.container.read(syncControllerProvider.notifier).setV2Pairing(true);
    final host = await PairingV2Host.start(
      transport: worker.client(),
      local: local,
      lock: a.container.read(v2FamilyLockProvider),
      guestPerson: 'nora',
      hostPicksPerson: true,
    );
    final b = await phone();
    final guest = b.container.read(pairingV2GuestProvider.notifier);
    await guest.begin(host.inviteId);
    await eventually(
      () async => await host.poll() != null,
      reason: 'el invitado responde',
    );
    await expectLater(
      host.confirm(
        confirmedPersonId: 'nora',
        verifyCheckpoint: (_) async => false,
        onPending: store.savePairingPendingGuest,
        onSettled: () => store.savePairingPendingGuest(null),
      ),
      throwsA(isA<PairingCheckpointUnprotectedException>()),
    );
    final view = await (await local.registry()).viewFor(
      me: local.identity.deviceId,
      mySigningKey: local.keys.publicKeys.signing,
      livePeople: const {'aritz', 'nora', 'leo'},
    );
    expect(view.revoked, hasLength(1), reason: 'el invitado, revocado aquí');
    expect(view.members, [local.identity.deviceId]);
    expect(await pendingGuestOf(a), isNull);
  });

  test('5: un cierre a mitad de la aprobación deja la marca; la vuelta '
      'siguiente revoca al invitado', () async {
    final a = await owner();
    final b = await phone();
    await invite(a, b, 'nora');
    final guestId =
        (await b.container.read(familyStoreProvider).readSyncV2())!.deviceId;
    await a.container
        .read(familyStoreProvider)
        .savePairingPendingGuest(guestId);
    await a.container.read(syncControllerProvider.notifier).syncNow();
    a.container.invalidate(localRegistryReadProvider);
    // El invitado queda fuera (revocado; y como A se queda solo, estrena
    // generación sin él).
    expect((await viewOf(a)).device(guestId), isNull);
    expect(
      worker
          .devicesOf(
            (await a.container.read(familyStoreProvider).readSyncV2())!.syncId,
          )
          .containsKey(guestId),
      isFalse,
    );
    expect(await pendingGuestOf(a), isNull);
  });

  test('6: si se pierde la respuesta de crear la lista, la ficha ya pudo '
      'salir: cambiar de persona en el móvil solo espera aprobación', () async {
    final a = await owner();
    // La creación entra en el servidor, pero la respuesta se pierde (y la
    // red sigue caída para los reintentos).
    worker.tamper = (method, uri, response) {
      if (method == 'PUT' && !uri.path.contains('/invites')) {
        throw const SyncTransportException(SyncFailure.network, 'perdida');
      }
      return response;
    };
    await a.container
        .read(pairingV2HostProvider.notifier)
        .start(guestPerson: 'nora');
    worker.tamper = null;
    expect(
      a.container.read(pairingV2HostProvider).phase,
      PairingV2HostPhase.failed,
    );
    final state = V2SyncState.fromJson(
      await a.container.read(familyStoreProvider).readSyncV2State(),
    );
    expect(state.created, isFalse);
    expect(state.createSent, isTrue);
    expect(
      await family(a).changeSelfPerson('leo'),
      ChangeSelfPersonResult.pendingApproval,
    );
  });

  test('7: una marca añadida por el camino a la oferta de un anfitrión que no '
      'eligió persona no deja entrar: la aprobación no la firma', () async {
    final a = await owner();
    await toV2(a, 'nora');
    final local = await localOf(a);
    a.container.read(syncControllerProvider.notifier).setV2Pairing(true);
    final old = await PairingV2Host.start(
      transport: worker.client(),
      local: local,
      lock: a.container.read(v2FamilyLockProvider),
    );
    worker.tamper = (method, uri, response) {
      if (!uri.path.endsWith('/offer')) return response;
      final json = response.json();
      final offer = Map<String, Object?>.from(json['offer']! as Map)
        ..[kHostPicksPersonField] = 1;
      return SyncResponse(
        response.status,
        response.headers,
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({...json, 'offer': offer, 'guestPerson': 'nora'}),
          ),
        ),
      );
    };
    final b = await phone();
    final guest = b.container.read(pairingV2GuestProvider.notifier);
    await guest.begin(old.inviteId);
    worker.tamper = null;
    await eventually(
      () async =>
          await old.poll() != null &&
          b.container.read(pairingV2GuestProvider).phase ==
              PairingV2GuestPhase.compare,
      reason: 'los dos enseñan el código',
    );
    guest.confirmCode();
    await old.confirm(confirmedPersonId: 'nora');
    await eventually(
      () =>
          b.container.read(pairingV2GuestProvider).phase ==
          PairingV2GuestPhase.failed,
      reason: 'el invitado no entra',
    );
    expect(b.container.read(pairingV2GuestProvider).versionMismatch, isTrue);
    expect(b.container.read(familyControllerProvider).value!.identity, isNull);
  });

  test('8: dos móviles de la misma persona no se ocultan nada y al '
      'desconectar uno no se purga', () async {
    final a = await owner();
    await family(a).upsertGift(gift('g-aritz', 'aritz', 'Gafas'));
    final b = await phone();
    await invite(a, b, 'aritz');
    await a.container.read(syncControllerProvider.notifier).syncNow();
    await b.container.read(syncControllerProvider.notifier).syncNow();
    expect(await shown(b), contains('Gafas'));
    await b.container.read(syncControllerProvider.notifier).stopSyncing();
    await b.container.read(familyControllerProvider.future);
    final doc = b.container.read(familyControllerProvider).value!.doc;
    expect(doc.record(Collections.gifts, 'g-aritz')!.isDeleted, isFalse);
    expect(await shown(b), contains('Gafas'));
  });

  test('9: quien solo regala no recibe regalos al guardar; lo que ya era '
      'suyo se sigue pudiendo editar', () async {
    final a = await owner();
    final fam = family(a);
    await fam.upsertRecipient(
      const Recipient(
        id: 'leo-solo',
        name: 'Leo',
        colorIndex: 1,
        archived: false,
        noGifts: true,
      ),
    );
    expect(
      await fam.upsertGiftResult(gift('nuevo', 'leo-solo', 'Reloj')),
      GiftWriteResult.recipientUnavailable,
    );
    expect(
      await fam.upsertGiftResult(
        gift('g-leo', 'leo-solo', 'Tren'),
        original: gift('g-leo', 'leo', 'Tren'),
      ),
      GiftWriteResult.recipientUnavailable,
    );
    // Un regalo histórico suyo (llegado de otro móvil) se puede editar.
    final doc = a.container.read(familyControllerProvider).value!.doc;
    await fam.mergeRemote(
      doc.set(
        HlcClock(node: 'otro-movil', last: doc.maxStamp),
        Collections.gifts,
        'viejo',
        gift('viejo', 'leo-solo', 'Bufanda').toFields(),
      ),
      fromNode: 'otro-movil',
    );
    expect(
      await fam.upsertGiftResult(
        gift('viejo', 'leo-solo', 'Bufanda roja'),
        original: gift('viejo', 'leo-solo', 'Bufanda'),
      ),
      GiftWriteResult.saved,
    );
  });

  // ------------------------------------ QA 1.0.6, m1: invitado 1.0.5

  test('m1: un invitado 1.0.5 recién instalado responde sin persona: el '
      'anfitrión pide actualizar y cancela la invitación', () async {
    // El Worker deja pasar la respuesta sin persona hasta el anfitrión.
    final a = await owner();
    final host = a.container.read(pairingV2HostProvider.notifier);
    await host.start(guestPerson: 'nora');
    final link = a.container.read(pairingV2HostProvider).link!;
    final inviteId = link.substring(link.indexOf('#') + 1);
    // Lo que manda un 1.0.5 sin familia: «Elegir después», sin la marca.
    final client = worker.client();
    final offer = await PairingOffer.fromJson(
      (await client.getOffer(inviteId)).offer,
    );
    final keys = await DeviceKeys.generate();
    final join = await joinPairing(
      offer: offer,
      keys: keys,
      deviceId: 'movil-105',
      personId: null,
      withoutPerson: true,
    );
    final answer =
        jsonDecode(jsonEncode(join.answer.toJson())) as Map<String, Object?>
          ..remove(kHostPicksPersonField);
    await client.answerInvite(
      inviteId,
      answer: answer,
      verifier: await keys.serviceCredentialVerifier(),
    );
    await eventually(
      () =>
          a.container.read(pairingV2HostProvider).phase ==
          PairingV2HostPhase.failed,
      reason: 'el anfitrión deja de esperar',
    );
    expect(a.container.read(pairingV2HostProvider).guestOutdated, isTrue);
    expect(worker.calls['DELETE invite'] ?? 0, greaterThan(0));
    // Nadie ha entrado.
    expect((await viewOf(a)).members, [(await viewOf(a)).me]);
  });

  // ------------------------------------ QA 1.0.6, M1: el anfitrión solo

  for (final departure in ['leaves', 'removed']) {
    test('M1 ($departure): el anfitrión que se queda solo sigue viendo y '
        'editando lo de Nora y Leo, y no ve lo suyo', () async {
      final a = await owner();
      await family(a).upsertGift(gift('g-aritz', 'aritz', 'Gafas'));
      final b = await phone();
      await invite(a, b, 'nora');
      await family(a).activateProtection('leo');
      final sync = a.container.read(syncControllerProvider.notifier);
      await sync.syncNow();
      await b.container.read(syncControllerProvider.notifier).syncNow();
      await sync.syncNow();
      expect(await shown(a), {'Libro', 'Tren'});
      final store = a.container.read(familyStoreProvider);
      final old = (await store.readSyncV2())!;

      if (departure == 'leaves') {
        await b.container.read(syncControllerProvider.notifier).stopSyncing();
        await sync.syncNow();
      } else {
        final peer = (await b.container
            .read(familyStoreProvider)
            .readSyncV2())!;
        await sync.removeDevice(peer.deviceId);
      }
      await a.container.read(familyControllerProvider.future);
      a.container.invalidate(localRegistryReadProvider);

      // Se ha quedado solo en una generación nueva.
      final fresh = (await store.readSyncV2())!;
      expect(fresh.syncId, isNot(old.syncId));
      final view = await viewOf(a);
      expect(view.alone, isTrue);

      // Sigue viendo lo de Nora y Leo, sin bloque cerrado.
      expect(await shown(a), {'Libro', 'Tren'});
      final locked = a.container.read(secretBlocksProvider);
      expect(locked, isNot(contains(const SecretBlock('nora'))));
      expect(locked, isNot(contains(const SecretBlock('leo'))));
      // Siguen en secreto: no han vuelto al común.
      final common = a.container.read(familyControllerProvider).value!.doc;
      expect(
        common.collections[Collections.gifts]!.values.where(
          (r) =>
              !r.isDeleted &&
              (r['recipientId'] == 'nora' || r['recipientId'] == 'leo'),
        ),
        isEmpty,
      );

      // Y puede editarlos y añadir otros.
      expect(
        await family(a).upsertGiftResult(
          gift('g-nora', 'nora', 'Libro grande'),
          original: gift('g-nora', 'nora', 'Libro'),
        ),
        GiftWriteResult.saved,
      );
      expect(
        await family(a).upsertGiftResult(gift('n2', 'nora', 'Cuento')),
        GiftWriteResult.saved,
      );
      expect(
        await family(a).upsertGiftResult(gift('l2', 'leo', 'Pelota')),
        GiftWriteResult.saved,
      );
      expect(await shown(a), {'Libro grande', 'Cuento', 'Tren', 'Pelota'});

      // Las claves nuevas solo las tiene él, y ninguna es de su persona.
      final ring = await a.container
          .read(deviceKeysStoreProvider)
          .readKeyring(view.listId);
      expect(ring.people, {'nora', 'leo'});
      for (final key in ring.keys) {
        expect(key.audience, [view.me]);
      }
      // Lo suyo nunca vuelve.
      expect(await shown(a), isNot(contains('Gafas')));
    });
  }

  test('M1 (B2): con un cambio de persona sin aprobar, el anfitrión que se '
      'queda solo no recupera nada: ni lo de su persona nueva ni lo de la de '
      'antes ni lo de los demás', () async {
    final a = await owner();
    await family(a).upsertGift(gift('g-aritz', 'aritz', 'Gafas'));
    final b = await phone();
    await invite(a, b, 'nora');
    await family(a).activateProtection('leo');
    final sync = a.container.read(syncControllerProvider.notifier);
    await sync.syncNow();
    await b.container.read(syncControllerProvider.notifier).syncNow();
    await sync.syncNow();
    expect(await shown(a), {'Libro', 'Tren'});
    // Aritz cambia este móvil a Leo; Nora no lo aprueba.
    expect(
      await family(a).changeSelfPerson('leo'),
      ChangeSelfPersonResult.pendingApproval,
    );
    final old = (await a.container.read(familyStoreProvider).readSyncV2())!;

    // «Dejar de sincronizar» en este móvil: se queda solo en una generación
    // nueva. (Si el que se va es el otro, con la persona congelada este
    // móvil ni siquiera retira la lista.)
    await sync.stopSyncing();
    await a.container.read(familyControllerProvider.future);
    a.container.invalidate(localRegistryReadProvider);

    final fresh = (await a.container.read(familyStoreProvider).readSyncV2())!;
    expect(fresh.syncId, isNot(old.syncId));
    final view = await viewOf(a);
    expect(view.alone, isTrue);
    final ring = await a.container
        .read(deviceKeysStoreProvider)
        .readKeyring(view.listId);
    expect(ring.people, isEmpty, reason: 'no nace ninguna clave');
    final titles = await shown(a);
    expect(titles, isNot(contains('Tren')), reason: 'Leo es su persona nueva');
    expect(titles, isNot(contains('Gafas')), reason: 'Aritz era la de antes');
    expect(titles, isNot(contains('Libro')), reason: 'sin ficha aprobada');
  });
}
