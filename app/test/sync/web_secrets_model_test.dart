// 1.0.6 (ADR 0009): la web lee y escribe los regalos en secreto de los demás
// como extensión del móvil de su persona. Modelo puro: `ownWebs`, paquetes
// para la web, buzón (`buildWebInbox`, `absorbWebInbox`) y compatibilidad con
// la 1.0.5.
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/key_bundle.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/protected_doc.dart';
import 'package:regalos/core/sync/protected_envelope.dart';

import 'fixtures/protected_envelope_v105.dart' as v105;
import 'protected_harness.dart';

Future<DeviceRecord> webRecord(Phone web, String person) => DeviceRecord.create(
  keys: web.keys,
  listId: kListId,
  deviceId: web.id,
  personId: person,
  kind: DeviceKind.web,
);

Future<Vouch> vouch(Phone signer, DeviceRecord from, DeviceRecord to) =>
    Vouch.create(keys: signer.keys, voucher: from, record: to);

SurpriseKey noraKey({List<String> audience = const ['aritz-phone']}) =>
    SurpriseKey(
      personId: 'nora',
      epoch: 1,
      bytes: List<int>.filled(32, 42),
      audience: audience,
    );

FamilyDoc giftsDoc(Map<String, SyncRecord> gifts) =>
    FamilyDoc(listId: kListId, collections: {Collections.gifts: gifts});

void main() {
  late Phone aritz, aritz2, leo, aritzWeb, leoWeb;
  late DeviceRecord ra, ra2, rl, rwa, rwl;
  late DeviceRegistry registry;

  setUp(() async {
    aritz = await Phone.create('aritz-phone', 'aritz', 1);
    aritz2 = await Phone.create('aritz-tablet', 'aritz', 2);
    leo = await Phone.create('leo-phone', 'leo', 3);
    aritzWeb = await Phone.create('aritz-web', 'aritz', 4);
    leoWeb = await Phone.create('leo-web', 'leo', 5);
    ra = await aritz.record();
    ra2 = await aritz2.record();
    rl = await leo.record();
    rwa = await webRecord(aritzWeb, 'aritz');
    rwl = await webRecord(leoWeb, 'leo');
    final anchor = RegistryAnchor(
      deviceId: aritz.id,
      signingKey: aritz.keys.publicKeys.signing,
    );
    registry = await DeviceRegistry.empty(kListId).withDeclarations(
      records: [ra, ra2, rl, rwa, rwl],
      vouches: [
        await vouch(aritz, ra, rl),
        await vouch(leo, rl, ra),
        await vouch(aritz, ra, ra2),
        await vouch(aritz2, ra2, ra),
        // La web de Aritz la emparejó su móvil; la de Leo, también su móvil.
        await vouch(aritz, ra, rwa),
        await vouch(leo, rl, rwl),
      ],
      anchor: anchor,
    );
  });

  group('ownWebs', () {
    test('solo las webs de mi persona que avalé yo', () async {
      final a = await aritz.viewOf(registry);
      expect(a.ownWebs().map((w) => w.deviceId), ['aritz-web']);
      // La tableta de Aritz no avaló la web: no es suya para dar claves.
      final t = await aritz2.viewOf(registry);
      expect(t.ownWebs(), isEmpty);
      // Leo ve su web, nunca la de Aritz.
      final l = await leo.viewOf(registry);
      expect(l.ownWebs().map((w) => w.deviceId), ['leo-web']);
      // Nada cambia en los predicados de las sorpresas.
      expect(a.entitled('aritz-web', 'nora'), isNull);
      expect(a.relayable('aritz-web', 'nora'), isNull);
    });

    test('un aval dado siendo de otra persona no cuenta', () async {
      // Aritz avaló la web de Leo cuando era de Leo y después pasó a Aritz:
      // la web «de Aritz» no es suya.
      final leoAsLeo = await leo.record();
      final web = await webRecord(
        await Phone.create('w', 'aritz', 9),
        'aritz',
      );
      final reg = await DeviceRegistry.empty(kListId).withDeclarations(
        records: [ra, leoAsLeo, web],
        vouches: [
          await vouch(aritz, ra, leoAsLeo),
          await vouch(leo, leoAsLeo, ra),
          await vouch(leo, leoAsLeo, web),
        ],
        anchor: RegistryAnchor(
          deviceId: leo.id,
          signingKey: leo.keys.publicKeys.signing,
        ),
      );
      final change = await changePerson(
        registry: reg,
        view: await leo.viewOf(reg),
        myKeys: leo.keys,
        personId: 'aritz',
      );
      final after = await leo.viewOf(change.registry);
      expect(after.ownWebs(), isEmpty);
    });
  });

  group('paquetes para la web', () {
    test('la web de Aritz recibe la clave de Nora y nunca la de Aritz', () async {
      final a = await aritz.viewOf(registry);
      final bundle = await KeyBundle.sealSurpriseKeyForOwnWeb(
        sender: aritz.keys,
        view: a,
        toDevice: 'aritz-web',
        key: noraKey(),
      );
      expect(bundle.audience, ['aritz-phone', 'aritz-web']);
      final key = await bundle.openSurpriseKeyAsWeb(
        mine: aritzWeb.keys,
        view: a,
        webDeviceId: 'aritz-web',
      );
      expect(key.kid, noraKey().kid);
      // La audiencia de la candidata no cambia.
      expect(key.audience, ['aritz-phone']);
      final aritzKey = SurpriseKey(
        personId: 'aritz',
        epoch: 1,
        bytes: List<int>.filled(32, 7),
        audience: const ['leo-phone'],
      );
      await expectLater(
        KeyBundle.sealSurpriseKeyForOwnWeb(
          sender: aritz.keys,
          view: a,
          toDevice: 'aritz-web',
          key: aritzKey,
        ),
        throwsA(isA<KeyBundleException>()),
      );
      // Ni a la web de otra persona.
      await expectLater(
        KeyBundle.sealSurpriseKeyForOwnWeb(
          sender: aritz.keys,
          view: a,
          toDevice: 'leo-web',
          key: noraKey(),
        ),
        throwsA(isA<KeyBundleException>()),
      );
    });

    test('ataque: paquete de un móvil de otra persona, con otro destinatario '
        'o leído con una raíz ajena', () async {
      final a = await aritz.viewOf(registry);
      final l = await leo.viewOf(registry);
      // Leo no puede sellar para la web de Aritz.
      await expectLater(
        KeyBundle.sealSurpriseKeyForOwnWeb(
          sender: leo.keys,
          view: l,
          toDevice: 'aritz-web',
          key: noraKey(audience: const ['leo-phone']),
        ),
        throwsA(isA<KeyBundleException>()),
      );
      // Un paquete forjado por Leo para la web de Aritz no se abre.
      final forged = await KeyBundle.sealForTesting(
        sender: leo.keys,
        fromDevice: 'leo-phone',
        toDevice: 'aritz-web',
        senderRecord: rl.digest,
        recipientRecord: rwa.digest,
        recipientAgreementKey: aritzWeb.keys.publicKeys.agreement,
        listId: kListId,
        scope: KeyScope.surprise('nora'),
        epoch: 1,
        key: List<int>.filled(32, 42),
        audience: const ['aritz-web', 'leo-phone'],
      );
      await expectLater(
        forged.openSurpriseKeyAsWeb(
          mine: aritzWeb.keys,
          view: a,
          webDeviceId: 'aritz-web',
        ),
        throwsA(isA<KeyBundleException>()),
      );
      final good = await KeyBundle.sealSurpriseKeyForOwnWeb(
        sender: aritz.keys,
        view: a,
        toDevice: 'aritz-web',
        key: noraKey(),
      );
      // Con la raíz de Leo (otra persona) no vale.
      await expectLater(
        good.openSurpriseKeyAsWeb(
          mine: aritzWeb.keys,
          view: l,
          webDeviceId: 'aritz-web',
        ),
        throwsA(isA<KeyBundleException>()),
      );
      // Con el destinatario cambiado, la firma no vale.
      await expectLater(
        good
            .copyForTesting(toDevice: 'leo-web')
            .openSurpriseKeyAsWeb(
              mine: leoWeb.keys,
              view: l,
              webDeviceId: 'leo-web',
            ),
        throwsA(isA<KeyBundleException>()),
      );
      // Un móvil (no la web) no abre por esta vía.
      await expectLater(
        good.openSurpriseKeyAsWeb(
          mine: aritz2.keys,
          view: a,
          webDeviceId: 'aritz-tablet',
        ),
        throwsA(isA<KeyBundleException>()),
      );
    });
  });

  group('buzón', () {
    final clock = clockOf('aritz-web', 1000);
    SyncRecord gift(String id, Map<String, Object?> fields) =>
        FamilyDoc.empty(kListId)
            .set(clock, Collections.gifts, id, {
              'recipientId': 'nora',
              ...fields,
            })
            .record(Collections.gifts, id)!;

    Future<OpenedSlot> inbox(FamilyDoc doc) async {
      final slot = await SealedSlot.seal(
        writerKeys: aritzWeb.keys,
        writer: 'aritz-web',
        revision: 10,
        key: noraKey(),
        policy: const PolicyState(hideOwnGifts: true, rev: 1),
        doc: doc,
      );
      return slot.open(
        expectedListId: kListId,
        key: noraKey(),
        signingKey: aritzWeb.keys.publicKeys.signing,
      );
    }

    test('construir: alta, edición, desconocido y lápida', () {
      final base = giftsDoc({
        'g1': gift('g1', {'title': 'Bufanda', 'status': 'idea'}),
        'dead': FamilyDoc.empty(kListId)
            .delete(clock, Collections.gifts, 'dead')
            .record(Collections.gifts, 'dead')!,
      });
      final edit = giftsDoc({
        'g1': SyncRecord(
          id: 'g1',
          fields: {
            'status': FieldValue(
              value: 'bought',
              stamp: Hlc(millis: kFuture + 5000, counter: 0, node: 'w'),
            ),
          },
        ),
      });
      final created = giftsDoc({'g2': gift('g2', {'title': 'Libro'})});
      final unknown = giftsDoc({'ghost': gift('ghost', {'title': 'X'})});
      final onDead = giftsDoc({'dead': gift('dead', {'title': 'Y'})});
      final build = buildWebInbox(
        personId: 'nora',
        scope: base,
        entries: [
          WebInboxEntry(id: 'e1', delta: edit),
          WebInboxEntry(id: 'e2', delta: created, newGifts: const {'g2'}),
          WebInboxEntry(id: 'e3', delta: unknown),
          WebInboxEntry(id: 'e4', delta: onDead),
        ],
      );
      expect(build.included, ['e1', 'e2']);
      expect(build.discarded, ['e3']);
      expect(build.moot, ['e4']);
      final g1 = build.doc.record(Collections.gifts, 'g1')!;
      // El registro completo como lo ve la web, con la marca nueva.
      expect(g1['title'], 'Bufanda');
      expect(g1['status'], 'bought');
      expect(g1[kWebNewField], isNull);
      expect(build.doc.record(Collections.gifts, 'g2')![kWebNewField], isTrue);
    });

    test('recoger: alta, edición y borrado; lo demás se descarta', () async {
      final scope = giftsDoc({
        'g1': gift('g1', {'title': 'Bufanda', 'status': 'idea'}),
        'g3': gift('g3', {'title': 'Gorro'}),
        'dead': FamilyDoc.empty(kListId)
            .delete(clock, Collections.gifts, 'dead')
            .record(Collections.gifts, 'dead')!,
      });
      final later = clockOf('aritz-web', 9000);
      var web = scope;
      web = web.set(later, Collections.gifts, 'g1', {'status': 'bought'});
      web = web.delete(later, Collections.gifts, 'g3');
      web = web.set(later, Collections.gifts, 'g2', {
        'recipientId': 'nora',
        'title': 'Libro',
      });
      final build = buildWebInbox(
        personId: 'nora',
        scope: scope,
        entries: [
          WebInboxEntry(
            id: 'all',
            delta: webDeltaOf(scope, web),
            newGifts: const {'g2'},
          ),
        ],
      );
      final inboxDoc = FamilyDoc(
        listId: kListId,
        collections: {
          Collections.gifts: {
            ...build.doc.collections[Collections.gifts]!,
            // Una edición de un regalo que no existe y una alta sobre una
            // lápida: se descartan sin tocar nada.
            'ghost': gift('ghost', {'title': 'X'}),
            'dead': SyncRecord(
              id: 'dead',
              fields: {
                ...gift('dead', {'title': 'Y'}).fields,
                kWebNewField: FieldValue(
                  value: true,
                  stamp: Hlc(millis: kFuture + 1, counter: 0, node: 'w'),
                ),
              },
            ),
          },
        },
      );
      final result = absorbWebInbox(
        scope: scope,
        inbox: await inbox(inboxDoc),
        nowMillis: kFuture + 10000,
      );
      expect(result.absorbed, isTrue);
      expect(result.applied, 3);
      expect(result.discarded, 2);
      expect(result.tombstones, 1);
      final after = result.scope;
      expect(after.record(Collections.gifts, 'g1')!['status'], 'bought');
      expect(after.record(Collections.gifts, 'g3')!.isDeleted, isTrue);
      expect(after.record(Collections.gifts, 'g2')!['title'], 'Libro');
      expect(after.record(Collections.gifts, 'g2')![kWebNewField], isNull);
      expect(after.record(Collections.gifts, 'ghost'), isNull);
      expect(after.record(Collections.gifts, 'dead')!.isDeleted, isTrue);
      // Recoger dos veces da lo mismo (dos móviles a la vez).
      final twice = absorbWebInbox(
        scope: after,
        inbox: await inbox(inboxDoc),
        nowMillis: kFuture + 10000,
      );
      expect(twice.scope.canonicalJson(), after.canonicalJson());
    });

    test('se rechaza entero: 41 registros, 11 lápidas, marca del futuro u '
        'otra persona', () async {
      final scope = giftsDoc({
        for (var i = 0; i < 41; i++) 'g$i': gift('g$i', {'title': 'T$i'}),
      });
      final many = giftsDoc({
        for (var i = 0; i < 41; i++) 'g$i': gift('g$i', {'title': 'U$i'}),
      });
      expect(
        absorbWebInbox(
          scope: scope,
          inbox: await inbox(many),
          nowMillis: kFuture + 10000,
        ).rejected,
        WebInboxRejection.tooManyRecords,
      );
      var dead = FamilyDoc.empty(kListId);
      for (var i = 0; i < 11; i++) {
        dead = dead.delete(clock, Collections.gifts, 'g$i');
      }
      expect(
        absorbWebInbox(
          scope: scope,
          inbox: await inbox(dead),
          nowMillis: kFuture + 10000,
        ).rejected,
        WebInboxRejection.tooManyTombstones,
      );
      final future = giftsDoc({
        'g1': SyncRecord(
          id: 'g1',
          fields: {
            ...gift('g1', {}).fields,
            'title': FieldValue(
              value: 'Futuro',
              stamp: Hlc(
                millis: kFuture + 3 * Duration.millisecondsPerDay,
                counter: 0,
                node: 'w',
              ),
            ),
          },
        ),
      });
      final rejected = absorbWebInbox(
        scope: scope,
        inbox: await inbox(future),
        nowMillis: kFuture,
      );
      expect(rejected.rejected, WebInboxRejection.futureStamp);
      expect(rejected.scope, same(scope));
      // Un regalo de otra persona no se puede sellar; si alguien lo cuela,
      // el buzón entero se rechaza.
      final opened = await inbox(giftsDoc({'g1': gift('g1', {'title': 'A'})}));
      final foreign = OpenedSlot(
        header: opened.header,
        doc: opened.doc,
        seen: opened.seen,
        cap: opened.cap,
        foreignRecords: 1,
      );
      expect(
        absorbWebInbox(
          scope: scope,
          inbox: foreign,
          nowMillis: kFuture + 10000,
        ).rejected,
        WebInboxRejection.foreignRecords,
      );
    });

    test('B7 (revisión final): un regalo que al fusionarse pasa del tope se '
        'descarta', () async {
      final scope = giftsDoc({
        'g1': gift('g1', {'title': 'T' * 1200}),
      });
      final grow = giftsDoc({
        'g1': SyncRecord(
          id: 'g1',
          fields: {
            'recipientId': FieldValue(
              value: 'nora',
              stamp: Hlc(millis: kFuture + 5000, counter: 0, node: 'w'),
            ),
            'note': FieldValue(
              value: 'N' * 900,
              stamp: Hlc(millis: kFuture + 5000, counter: 0, node: 'w'),
            ),
          },
        ),
      });
      final result = absorbWebInbox(
        scope: scope,
        inbox: await inbox(grow),
        nowMillis: kFuture + 10000,
      );
      expect(result.absorbed, isTrue);
      expect(result.applied, 0);
      expect(result.discarded, 1);
      expect(result.scope.record(Collections.gifts, 'g1')!['note'], isNull);
    });

    test('freno diario: sin sitio para más lápidas hoy, espera', () async {
      final scope = giftsDoc({
        for (var i = 0; i < 5; i++) 'g$i': gift('g$i', {'title': 'T$i'}),
      });
      var dead = FamilyDoc.empty(kListId);
      for (var i = 0; i < 5; i++) {
        dead = dead.delete(clockOf('w', 5000), Collections.gifts, 'g$i');
      }
      final result = absorbWebInbox(
        scope: scope,
        inbox: await inbox(dead),
        nowMillis: kFuture + 10000,
        tombstoneBudget: 4,
      );
      expect(result.waiting, isTrue);
      expect(result.scope, same(scope));
    });
  });

  group('1.0.5', () {
    test('un 1.0.5 lee el buzón como un slot y abre el slot con s[web]', () async {
      final doc = giftsDoc({
        'g1': FamilyDoc.empty(kListId)
            .set(clockOf('w', 1), Collections.gifts, 'g1', {
              'recipientId': 'nora',
              'title': 'Bufanda',
              kWebNewField: true,
            })
            .record(Collections.gifts, 'g1')!,
      });
      final inbox = await SealedSlot.seal(
        writerKeys: aritzWeb.keys,
        writer: 'aritz-web',
        revision: 10,
        key: noraKey(),
        policy: const PolicyState(hideOwnGifts: true, rev: 1),
        doc: doc,
      );
      final parsed = v105.SealedSlot.parse(inbox.bytes);
      expect(parsed.header.writer, 'aritz-web');
      // El slot de Aritz con el buzón recogido declara s[aritz-web].
      final mine = await SealedSlot.seal(
        writerKeys: aritz.keys,
        writer: 'aritz-phone',
        revision: 20,
        key: noraKey(),
        policy: const PolicyState(hideOwnGifts: true, rev: 1),
        doc: giftsDoc({}),
        seen: {'aritz-web': const SlotVersion(1, 10)},
      );
      final opened = await v105.SealedSlot.parse(mine.bytes).open(
        expectedListId: kListId,
        key: noraKey(),
        signingKey: aritz.keys.publicKeys.signing,
      );
      expect(opened.seen.keys, ['aritz-web']);
    });
  });
}

/// Lo que cambió entre [before] y [after] (como `webDelta` de la web).
FamilyDoc webDeltaOf(FamilyDoc before, FamilyDoc after) => FamilyDoc(
  listId: before.listId,
  collections: {
    Collections.gifts: {
      for (final r in after.collections[Collections.gifts]!.values)
        if (r.fields.entries.any(
          (f) =>
              before.record(Collections.gifts, r.id)?.field(f.key)?.stamp !=
              f.value.stamp,
        ))
          r.id: SyncRecord(
            id: r.id,
            fields: {
              for (final f in r.fields.entries)
                if (before.record(Collections.gifts, r.id)?.field(f.key)?.stamp !=
                    f.value.stamp)
                  f.key: f.value,
            },
          ),
    },
  },
);
