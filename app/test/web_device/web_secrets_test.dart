// 1.0.6 (ADR 0009): la web de Aritz lee y escribe los regalos en secreto de
// Nora a través de su móvil, de punta a punta contra el Worker falso.
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/protected_envelope.dart';
import 'package:regalos/features/sync/application/family_devices.dart';
import 'package:regalos/features/sync/application/sync_v2_engine.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';
import 'package:regalos/features/web_device/application/web_secrets.dart';

import '../sync/v2_harness.dart';
import 'web_engine_support.dart';

SurpriseKey noraKey(List<String> audience) => SurpriseKey(
  personId: 'nora',
  epoch: 1,
  bytes: List<int>.filled(32, 42),
  audience: audience,
);

/// Protege a Nora en el móvil de Aritz con un regalo en secreto, y publica.
Future<void> protectNora(WebHarness h) async {
  final phone = h.phone;
  phone.doc = writePublishedPolicy(
    phone.doc,
    phone.clock,
    'nora',
    const PolicyState(hideOwnGifts: true, rev: 1),
  );
  phone.keyring = SurpriseKeyring([noraKey(const ['aritz-phone'])]);
  phone.scopes['nora'] = FamilyDoc.empty(kV2List).set(
    phone.clock,
    Collections.gifts,
    's1',
    {'recipientId': 'nora', 'title': 'Patinete', 'status': 'idea', 'year': 2026},
  );
  await phone.engine(h.client).sync();
}

void main() {
  test('la web de Aritz ve el secreto de Nora, lo cambia, lo crea y lo borra '
      'a través del móvil de Aritz', () async {
    final h = WebHarness(webPerson: 'aritz');
    addTearDown(h.close);
    await h.setup();
    final web = h.engine.auth.deviceId;
    await protectNora(h);
    final view = await h.phone.view();
    expect(view.ownWebs().map((w) => w.deviceId), [web]);
    // El paquete para la web es de Nora, nunca de Aritz.
    final snap = (await h.client.getList(h.phone.auth) as V2GetOk).snapshot;
    final toWeb = [
      for (final p in snap.keyPackages)
        if (p['to'] == web) p['s'],
    ];
    expect(toWeb, [KeyScope.surprise('nora')]);

    await h.engine.sync();
    expect(h.engine.secrets.state, WebSecretsState.open);
    expect(h.engine.secrets.openedPeople, {'nora'});
    expect(h.engine.secrets.writablePeople, {'nora'});
    expect(h.engine.secretsOpen, isTrue);
    expect(h.engine.candidate!.record(Collections.gifts, 's1')!['title'], 'Patinete');
    // El regalo público de Nora (de antes de protegerla) no se ve.
    expect(h.engine.candidate!.record(Collections.gifts, 'gift'), isNull);

    // Editar: va al buzón, no al común.
    var before = h.engine.candidate!;
    final clock = HlcClock(node: web, last: before.maxStamp);
    await h.engine.save(
      before,
      before.set(clock, Collections.gifts, 's1', {'status': 'bought'}),
    );
    expect(h.engine.pendingSecretGiftIds, {'s1'});
    expect(h.engine.setAsideCount, 0);
    await h.engine.sync();
    expect(h.worker.slotVersions(kV2Sync).keys, contains('nora/$web'));
    // El común publicado no tiene nada de Nora.
    final common = await h.remote();
    expect(common.record(Collections.gifts, 's1'), isNull);

    await h.phone.engine(h.client).sync();
    expect(
      h.phone.scopes['nora']!.record(Collections.gifts, 's1')!['status'],
      'bought',
    );
    final mine = h.phone.slotSet.slotOf('nora', 'aritz-phone')!;
    final opened = await mine.open(
      expectedListId: kV2List,
      key: h.phone.keyring.keyFor('nora', mine.header.epoch, mine.header.kid)!,
      signingKey: h.phone.keys.publicKeys.signing,
    );
    expect(opened.seen.keys, contains(web));

    await h.engine.sync();
    expect(await h.queue.entries(), isEmpty);
    expect(h.engine.pendingSecretGiftIds, isEmpty);
    expect(h.worker.slotVersions(kV2Sync).keys, isNot(contains('nora/$web')));
    expect(
      h.engine.candidate!.record(Collections.gifts, 's1')!['status'],
      'bought',
    );

    // Crear y después borrar.
    before = h.engine.candidate!;
    await h.engine.save(
      before,
      before.set(clock, Collections.gifts, 's2', {
        'recipientId': 'nora',
        'title': 'Libro',
        'status': 'idea',
        'year': 2026,
      }),
    );
    await h.engine.sync();
    await h.phone.engine(h.client).sync();
    final s2 = h.phone.scopes['nora']!.record(Collections.gifts, 's2')!;
    expect(s2['title'], 'Libro');
    expect(s2[kWebNewField], isNull);
    await h.engine.sync();
    before = h.engine.candidate!;
    await h.engine.save(before, before.delete(clock, Collections.gifts, 's2'));
    await h.engine.sync();
    await h.phone.engine(h.client).sync();
    expect(
      h.phone.scopes['nora']!.record(Collections.gifts, 's2')!.isDeleted,
      isTrue,
    );
    expect(h.phone.state.webTombstoneCount, 1);
    await h.engine.sync();
    expect(await h.queue.entries(), isEmpty);
  });

  test('un buzón ya recogido no vuelve a entrar aunque el regalo se '
      'compacte (no resucita)', () async {
    final h = WebHarness(webPerson: 'aritz');
    addTearDown(h.close);
    await h.setup();
    final web = h.engine.auth.deviceId;
    await protectNora(h);
    await h.engine.sync();
    final before = h.engine.candidate!;
    final clock = HlcClock(node: web, last: before.maxStamp);
    await h.engine.save(
      before,
      before.set(clock, Collections.gifts, 'g9', {
        'recipientId': 'nora',
        'title': 'Tren',
        'status': 'idea',
        'year': 2026,
      }),
    );
    await h.engine.sync();
    await h.phone.engine(h.client).sync();
    expect(h.phone.scopes['nora']!.record(Collections.gifts, 'g9'), isNotNull);
    // Se borra en el móvil y, como es el único escritor, la lápida se
    // compacta: ni vivo ni lápida.
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
    // El Worker sigue sirviendo el buzón (la web no ha vuelto) y el móvil lo
    // vuelve a bajar: no entra.
    expect(h.worker.slotVersions(kV2Sync).keys, contains('nora/$web'));
    h.phone.state = h.phone.state.copyWith(
      webInboxDone: const {},
      deferred: {'nora'},
    );
    await h.phone.engine(h.client).sync();
    expect(h.phone.scopes['nora']!.record(Collections.gifts, 'g9'), isNull);
    // La web confirma por `s[web]` aunque el regalo ya no esté, y no lo
    // vuelve a mandar.
    await h.engine.sync();
    expect(await h.queue.entries(), isEmpty);
    expect(h.worker.slotVersions(kV2Sync).keys, isNot(contains('nora/$web')));
  });

  test('el móvil de otra persona ignora el buzón y no lo vuelve a bajar', () async {
    final h = WebHarness(webPerson: 'aritz');
    addTearDown(h.close);
    await h.setup();
    final web = h.engine.auth.deviceId;
    await protectNora(h);
    final leo = await MemoryV2Phone.create(
      'leo-phone',
      'leo',
      7,
      familyKey: h.phone.familyKey,
    );
    leo.doc = h.phone.doc;
    await vouchAll([h.phone, leo]);
    h.worker.addCredentialForTesting(
      kV2Sync,
      'leo-phone',
      leo.keys.serviceCredential,
    );
    await h.phone.engine(h.client).sync();
    await h.engine.sync();
    final before = h.engine.candidate!;
    await h.engine.save(
      before,
      before.set(
        HlcClock(node: web, last: before.maxStamp),
        Collections.gifts,
        's1',
        {'status': 'bought'},
      ),
    );
    await h.engine.sync();
    expect(h.worker.slotVersions(kV2Sync).keys, contains('nora/$web'));
    final out = await leo.engine(h.client).sync();
    expect(out.rejectedSlots, 0);
    expect(
      leo.state.ignoredSlots['nora/$web']?.reason,
      IgnoredSlotReason.webInbox,
    );
    expect(leo.slotSet.slotOf('nora', web), isNull);
    final gets = h.worker.calls['GET slot'];
    await leo.engine(h.client).sync();
    expect(h.worker.calls['GET slot'], gets);
  });

  test('la web de otra persona no recibe nada y revocar la web borra su buzón '
      'y deja de darle claves', () async {
    final other = WebHarness(webPerson: 'nora');
    addTearDown(other.close);
    await other.setup();
    await protectNora(other);
    expect((await other.phone.view()).ownWebs(), isEmpty);
    await other.engine.sync();
    expect(other.engine.secrets.state, WebSecretsState.reconnect);
    expect(other.engine.secretsOpen, isFalse);

    final h = WebHarness(webPerson: 'aritz');
    addTearDown(h.close);
    await h.setup();
    final web = h.engine.auth.deviceId;
    await protectNora(h);
    await h.engine.sync();
    final before = h.engine.candidate!;
    await h.engine.save(
      before,
      before.set(
        HlcClock(node: web, last: before.maxStamp),
        Collections.gifts,
        's1',
        {'status': 'bought'},
      ),
    );
    await h.engine.sync();
    expect(h.worker.slotVersions(kV2Sync).keys, contains('nora/$web'));
    await removeDevice(transport: h.client, local: h.phone, deviceId: web);
    expect(h.worker.slotVersions(kV2Sync).keys, isNot(contains('nora/$web')));
    await h.phone.engine(h.client).sync();
    final snap = (await h.client.getList(h.phone.auth) as V2GetOk).snapshot;
    expect([for (final p in snap.keyPackages) p['to']], isNot(contains(web)));
    // Lo no recogido se pierde: el secreto sigue como estaba.
    expect(
      h.phone.scopes['nora']!.record(Collections.gifts, 's1')!['status'],
      'idea',
    );
  });
}
