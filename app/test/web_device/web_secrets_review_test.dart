// 1.0.6 (ADR 0009): los casos que pidió la revisión de seguridad de la revisión
// (M2, M3, B1, recogida transitiva, dos móviles a la vez y 412).
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/wish.dart';
import 'package:regalos/core/sync/wish_plan.dart';
import 'package:regalos/core/sync/protected_doc.dart' show openScope;
import 'package:regalos/features/sync/data/sync_transport_v2.dart';
import 'package:regalos/features/web_device/application/pending_queue.dart';

import '../sync/v2_harness.dart';
import 'web_engine_support.dart';
import 'web_secrets_test.dart' show protectNora;

/// Un segundo móvil de Aritz (la tableta), en la familia y avalando también
/// la web.
Future<MemoryV2Phone> aritzTablet(WebHarness h) async {
  final tablet = await MemoryV2Phone.create(
    'aritz-tablet',
    'aritz',
    8,
    familyKey: h.phone.familyKey,
  );
  tablet.doc = h.phone.doc;
  await vouchAll([h.phone, tablet]);
  final web = h.engine.auth.deviceId;
  final record = tablet.reg.records.firstWhere((r) => r.deviceId == web);
  tablet.reg = await tablet.reg.withVouch(
    await Vouch.create(keys: tablet.keys, voucher: tablet.record, record: record),
  );
  h.worker.addCredentialForTesting(
    kV2Sync,
    'aritz-tablet',
    tablet.keys.serviceCredential,
  );
  await tablet.engine(h.client).sync();
  await h.phone.engine(h.client).sync();
  await tablet.engine(h.client).sync();
  return tablet;
}

/// La web cambia [fields] del regalo [id].
Future<void> webSet(
  WebHarness h,
  String collection,
  String id,
  Map<String, Object?> fields,
) async {
  final before = h.engine.candidate!;
  await h.engine.save(
    before,
    before.set(
      HlcClock(node: h.engine.auth.deviceId, last: before.maxStamp),
      collection,
      id,
      fields,
    ),
  );
}

Future<WebHarness> ready() async {
  final h = WebHarness(webPerson: 'aritz');
  addTearDown(h.close);
  await h.setup();
  await protectNora(h);
  return h;
}

void main() {
  test('recogida transitiva: la tableta de Aritz no vuelve a recoger lo que '
      'ya recogió el móvil', () async {
    final h = await ready();
    final web = h.engine.auth.deviceId;
    final tablet = await aritzTablet(h);
    expect((await tablet.view()).ownWebs().map((w) => w.deviceId), [web]);
    await h.engine.sync();
    final before = h.engine.candidate!;
    await h.engine.save(
      before,
      before.delete(
        HlcClock(node: web, last: before.maxStamp),
        Collections.gifts,
        's1',
      ),
    );
    await h.engine.sync();
    await h.phone.engine(h.client).sync();
    expect(h.phone.state.webTombstoneCount, 1);
    await tablet.engine(h.client).sync();
    // La tableta sube su marca desde `s[web]` del móvil y no recoge nada.
    expect(
      tablet.state.webInboxFloors['nora/$web'],
      h.phone.state.webInboxFloors['nora/$web'],
    );
    expect(tablet.state.webTombstoneCount, 0);
    // Y ve el borrado por el slot del móvil.
    final opened = await openScope(
      personId: 'nora',
      slots: tablet.slotSet,
      keyring: tablet.keyring,
      view: await tablet.view(),
    );
    expect(opened!.doc.record(Collections.gifts, 's1')!.isDeleted, isTrue);
  });

  test('dos móviles de Aritz recogen a la vez y acaban igual', () async {
    final h = await ready();
    final tablet = await aritzTablet(h);
    await h.engine.sync();
    await webSet(h, Collections.gifts, 's1', {'status': 'bought'});
    await h.engine.sync();
    await Future.wait([
      h.phone.engine(h.client).sync(),
      tablet.engine(h.client).sync(),
    ]);
    await h.phone.engine(h.client).sync();
    await tablet.engine(h.client).sync();
    final a = h.phone.scopes['nora']!.record(Collections.gifts, 's1')!;
    final b = tablet.scopes['nora']!.record(Collections.gifts, 's1')!;
    expect(a['status'], 'bought');
    expect(b.fields, a.fields);
    await h.engine.sync();
    expect(await h.queue.entries(), isEmpty);
  });

  test('B-2: la recogida transitiva copia también el rechazo: la tableta '
      'que lee el slot del móvil declara el mismo «x»', () async {
    final h = await ready();
    final tablet = await aritzTablet(h);
    final web = h.engine.auth.deviceId;
    await h.engine.sync();
    // An edit with a stamp a month ahead: the phone rejects the inbox whole.
    final before = h.engine.candidate!;
    final far = DateTime.now().millisecondsSinceEpoch + 40 * 86400000;
    await h.engine.save(
      before,
      before.set(
        HlcClock(node: web, last: Hlc(millis: far, counter: 0, node: web)),
        Collections.gifts,
        's1',
        {'status': 'bought'},
      ),
    );
    await h.engine.sync();
    await h.phone.engine(h.client).sync();
    expect(h.phone.state.webInboxRejected.keys, ['nora/$web']);
    expect(tablet.state.webInboxRejected, isEmpty);
    // The tablet reads the phone's slot (`s[web]` and `x[web]`): it does not
    // collect the inbox itself, and still carries the rejection.
    await tablet.engine(h.client).sync();
    expect(tablet.state.webInboxFloors['nora/$web'], isNotNull);
    expect(tablet.state.webInboxRejected, h.phone.state.webInboxRejected);
    expect(
      tablet.scopes['nora']!.record(Collections.gifts, 's1')?['status'],
      isNot('bought'),
    );
  });

  test('B1: sin estado, el móvil no vuelve a recoger un buzón que ya declaró',
      () async {
    final h = await ready();
    await h.engine.sync();
    await webSet(h, Collections.gifts, 'g9', {
      'recipientId': 'nora',
      'title': 'Tren',
      'status': 'idea',
      'year': 2026,
    });
    await h.engine.sync();
    await h.phone.engine(h.client).sync();
    expect(h.phone.scopes['nora']!.record(Collections.gifts, 'g9'), isNotNull);
    h.phone.scopes['nora'] = h.phone.scopes['nora']!.delete(
      h.phone.clock,
      Collections.gifts,
      'g9',
    );
    for (var i = 0; i < 2; i++) {
      h.phone.state = h.phone.state.copyWith(deferred: {'nora'});
      await h.phone.engine(h.client).sync();
    }
    expect(h.phone.scopes['nora']!.record(Collections.gifts, 'g9'), isNull);
    // Se pierde todo lo del buzón en el estado (una copia restaurada).
    h.phone.state = h.phone.state.copyWith(
      webInboxFloors: const {},
      webInboxDone: const {},
      webInboxWait: const {},
      deferred: {'nora'},
    );
    await h.phone.engine(h.client).sync();
    expect(h.phone.scopes['nora']!.record(Collections.gifts, 'g9'), isNull);
  });

  test('412 al subir el buzón: la web vuelve a leer y lo sube', () async {
    final h = await ready();
    final web = h.engine.auth.deviceId;
    await h.engine.sync();
    await webSet(h, Collections.gifts, 's1', {'status': 'bought'});
    var moved = false;
    h.worker.beforePut = (_) async {
      final s = (await h.client.getList(h.phone.auth) as V2GetOk).snapshot;
      await h.client.putCommon(
        h.phone.auth,
        version: s.version,
        common: s.common,
      );
      moved = true;
    };
    await h.engine.sync();
    expect(moved, isTrue);
    expect(h.worker.slotVersions(kV2Sync).keys, contains('nora/$web'));
    expect(h.worker.calls['PUT slot'], greaterThanOrEqualTo(2));
    await h.phone.engine(h.client).sync();
    expect(
      h.phone.scopes['nora']!.record(Collections.gifts, 's1')!['status'],
      'bought',
    );
  });

  test('M3: si el Worker rechaza el buzón, lo público se publica igual',
      () async {
    final h = await ready();
    await h.engine.sync();
    await webSet(h, Collections.gifts, 's1', {'status': 'bought'});
    await webSet(h, Collections.recipients, 'leo', {'name': 'Leo Bis'});
    h.worker.refuseWebSlot = 413;
    await h.engine.sync();
    expect(
      (await h.remote()).record(Collections.recipients, 'leo')!['name'],
      'Leo Bis',
    );
    expect(h.engine.heldInboxPeople, {'nora'});
    expect(h.engine.pendingSecretGiftIds, {'s1'});
  });

  test('M2: dos candidatas de Nora con la misma audiencia llegan las dos a '
      'la web', () async {
    final h = await ready();
    final web = h.engine.auth.deviceId;
    final second = SurpriseKey(
      personId: 'nora',
      epoch: 1,
      bytes: List<int>.filled(32, 43),
      audience: const ['aritz-phone'],
    );
    await h.phone.updateKeyring((k) => k.withKey(second, registryEpoch: 1));
    await h.phone.engine(h.client).sync();
    final snap = (await h.client.getList(h.phone.auth) as V2GetOk).snapshot;
    final toWeb = [
      for (final p in snap.keyPackages)
        if (p['to'] == web && p['s'] == KeyScope.surprise('nora')) p,
    ];
    expect(toWeb, hasLength(2));
    await h.engine.sync();
    expect(h.engine.secrets.keyring.keys, hasLength(2));
    expect(h.engine.secrets.openedPeople, {'nora'});
  });

  test('M1 (revisión final): si el móvil que conectó la web cambia de '
      'persona, la web oculta la de antes y la nueva', () async {
    final h = await ready();
    await h.engine.sync();
    expect(h.engine.phonePeople, {'aritz'});
    h.phone.reg = (await changePerson(
      registry: h.phone.reg,
      view: await h.phone.view(),
      myKeys: h.phone.keys,
      personId: 'leo',
    )).registry;
    await h.phone.engine(h.client).sync();
    await h.engine.sync();
    expect(h.engine.phonePeople, {'aritz', 'leo'});
    expect(h.engine.screenHiddenPeople, containsAll(['aritz', 'leo']));
    // Sin su móvil de la persona aprobado, la web suelta las claves.
    expect(h.engine.secretsOpen, isFalse);
  });

  test('ADR 0010: dos móviles de Aritz recogen a la vez el plan de la web y '
      'acaban igual, sin duplicarlo', () async {
    final h = await ready();
    final tablet = await aritzTablet(h);
    h.phone.doc = h.phone.doc.set(h.phone.clock, Collections.wishes, 'w1', {
      'recipientId': 'nora',
      'authorPersonId': 'nora',
      'suggested': false,
      'title': 'Patinete',
      'year': 2026,
    });
    await h.phone.engine(h.client).sync();
    await h.engine.sync();
    final claim = await h.engine.claimWish('w1');
    expect(claim.ok, isTrue);
    await h.engine.sync();
    await Future.wait([
      h.phone.engine(h.client).sync(),
      tablet.engine(h.client).sync(),
    ]);
    await h.phone.engine(h.client).sync();
    await tablet.engine(h.client).sync();
    final a = h.phone.scopes['nora']!;
    // La tableta ve el plan por el slot del móvil (no republica si no hay nada que decir).
    final b = (await openScope(
      personId: 'nora',
      slots: tablet.slotSet,
      keyring: tablet.keyring,
      view: await tablet.view(),
    ))!
        .doc;
    expect(a.livePlans.map((p) => p.planId), [claim.planId]);
    expect(b.livePlans.map((p) => p.planId), [claim.planId]);
    expect(
      b.record(ScopeCollections.wishPlans, claim.planId!)!.fields,
      a.record(ScopeCollections.wishPlans, claim.planId!)!.fields,
    );
    await h.engine.sync();
    expect(await h.queue.entries(), isEmpty);
  });

  test('ADR 0010, M3: si el Worker rechaza el buzón, el deseo propio se '
      'publica igual y el plan espera', () async {
    final h = await ready();
    h.phone.doc = h.phone.doc.set(h.phone.clock, Collections.wishes, 'w1', {
      'recipientId': 'nora',
      'authorPersonId': 'nora',
      'suggested': false,
      'title': 'Patinete',
      'year': 2026,
    });
    await h.phone.engine(h.client).sync();
    await h.engine.sync();
    final mine = await h.engine.createOwnWish(
      const VisibleWishPatch(title: 'Libro', year: 2026),
    );
    expect(mine.ok, isTrue);
    final claim = await h.engine.claimWish('w1');
    expect(claim.ok, isTrue);
    h.worker.refuseWebSlot = 413;
    await h.engine.sync();
    final wish = (await h.remote()).record(Collections.wishes, mine.wishId!)!;
    expect(wish['authorPersonId'], 'aritz');
    expect((await h.remote()).canonicalJson(), isNot(contains(claim.planId!)));
    expect(h.engine.heldInboxPeople, {'nora'});
    expect(h.engine.pendingPlanIds, {claim.planId});
    expect(
      (await h.queue.entries()).where((e) => e.kind == PendingKind.privateScope),
      hasLength(1),
    );
  });
}
