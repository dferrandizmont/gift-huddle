// 1.0.6 (ADR 0009): los casos que pidió la revisión de seguridad de la revisión
// (M2, M3, B1, recogida transitiva, dos móviles a la vez y 412).
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/protected_doc.dart' show openScope;
import 'package:regalos/features/sync/data/sync_transport_v2.dart';

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
}
