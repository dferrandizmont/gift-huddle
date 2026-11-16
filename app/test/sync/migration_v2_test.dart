import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/device_keys.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/pairing_v2.dart';
import 'package:regalos/features/sync/application/migration_v2.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';
import 'package:regalos/features/sync/domain/sync_keys.dart';

import '../helpers/fake_sync_server.dart';

const _list = 'list-migra';

Future<DeviceKeys> _keys(int seed) => DeviceKeys.fromSeedsForTesting(
  agreementSeed: List<int>.filled(32, seed),
  signingSeed: List<int>.filled(32, seed + 100),
  serviceCredential: List<int>.filled(32, seed + 200),
);

FamilyDoc _gift(FamilyDoc doc, HlcClock clock, String id, String title) =>
    doc.set(clock, Collections.gifts, id, {
      'recipientId': 'nora',
      'title': title,
      'status': 'idea',
      'year': 2026,
    });

Set<String> _titles(FamilyDoc doc) => {
  for (final r
      in doc.collections[Collections.gifts]?.values ?? const <SyncRecord>[])
    if (!r.isDeleted) r['title'] as String,
};

void main() {
  // Nodos de reloj de los tres móviles de v1 (serán sus ids de móvil en v2).
  final aritz = HlcClock(node: 'aritznode1');
  final leo = HlcClock(node: 'leonode002');
  final nora = HlcClock(node: 'noranode03');

  test(
    'el anfitrión migra sin perder nada y su id de móvil es su nodo',
    () async {
      var v1 = _gift(FamilyDoc.empty(_list), aritz, 'g1', 'Bufanda');
      v1 = _gift(v1, leo, 'g2', 'Libro');
      final migrated = await migrateToV2(
        v1Doc: v1,
        clock: aritz,
        keys: await _keys(1),
        deviceId: aritz.node,
        personId: 'aritz',
      );
      expect(syncProtocolOf(migrated.common), kSyncProtocolV2);
      expect(_titles(migrated.common), {'Bufanda', 'Libro'});
      expect(migrated.identity.migratedFromV1, isTrue);
      expect(migrated.registry.records.single.deviceId, aritz.node);
      expect(
        v1WritersMigrated(
          known: writerNodesOf(v1),
          registry: migrated.registry,
        ),
        isFalse,
        reason: 'Leo también escribió en v1',
      );
    },
  );

  test('ataque (hallazgo 1): la marca del protocolo de una copia v1 no entra '
      'en v2, ni más nueva ni como lápida', () async {
    final v1 = _gift(FamilyDoc.empty(_list), aritz, 'g1', 'Bufanda');
    final migrated = await migrateToV2(
      v1Doc: v1,
      clock: aritz,
      keys: await _keys(1),
      deviceId: aritz.node,
      personId: 'aritz',
    );
    // Quien tiene la clave v1 escribe en v1 la marca a 1 con un reloj muy
    // adelantado, o la borra (una lápida es final).
    final evil = HlcClock(
      node: 'evilnode01',
      last: Hlc(millis: 4102444800000, counter: 0, node: 'evilnode01'),
    );
    final raised = _gift(v1, evil, 'g9', 'Intruso').set(
      evil,
      Collections.meta,
      kProtocolRecordId,
      {kProtocolVersionField: 1},
    );
    final tombstoned = v1.delete(evil, Collections.meta, kProtocolRecordId);
    for (final poisoned in [raised, tombstoned]) {
      expect(syncProtocolOf(poisoned), 1);
      final merged = mergeLocalV1IntoV2(
        v2Doc: migrated.common,
        localV1: poisoned,
      );
      expect(syncProtocolOf(merged), kSyncProtocolV2);
      expect(
        withoutProtocolMark(poisoned)
            .record(Collections.meta, kProtocolRecordId),
        isNull,
      );
    }
    // Y si aun así llega una marca 1 por la sincronización v2, el móvil v2
    // la vuelve a escribir a 2 con su reloj (gana por marca).
    final lowered = migrated.common.merge(raised);
    expect(syncProtocolOf(lowered), 1);
    final repaired = keepProtocolV2(
      before: migrated.common,
      merged: lowered,
      clock: HlcClock(node: aritz.node, last: lowered.maxStamp),
    );
    expect(syncProtocolOf(repaired), kSyncProtocolV2);
    expect(syncProtocolOf(repaired.merge(raised)), kSyncProtocolV2);
    // Un documento que nunca fue v2 no se marca.
    expect(
      keepProtocolV2(before: v1, merged: raised, clock: aritz),
      same(raised),
    );
  });

  test('el invitado fusiona su copia v1: lo suyo entra y lo borrado en v2 '
      'sigue borrado', () async {
    var shared = _gift(FamilyDoc.empty(_list), aritz, 'g1', 'Bufanda');
    shared = _gift(shared, aritz, 'g2', 'Cometa');
    // Leo, todavía en v1, añade algo sin conexión.
    final leoLocal = _gift(shared, leo, 'g3', 'Peonza');
    final migrated = await migrateToV2(
      v1Doc: shared,
      clock: aritz,
      keys: await _keys(1),
      deviceId: aritz.node,
      personId: 'aritz',
    );
    final v2 = migrated.common.delete(aritz, Collections.gifts, 'g2');
    final merged = mergeLocalV1IntoV2(v2Doc: v2, localV1: leoLocal);
    expect(_titles(merged), {'Bufanda', 'Peonza'});
    expect(syncProtocolOf(merged), kSyncProtocolV2);
    expect(
      () => mergeLocalV1IntoV2(v2Doc: leoLocal, localV1: v2),
      throwsStateError,
    );
  });

  group('retirar la copia v1 del servidor', () {
    late FakeSyncServer server;
    late SyncTransport transport;
    late FamilyKey v1Key;
    late SyncCredentials auth;

    setUp(() async {
      server = FakeSyncServer();
      transport = server.connect();
      v1Key = await FamilyKey.generate();
      auth = SyncCredentials(
        listId: _list,
        syncId: await SyncKeys.syncId(v1Key),
        authKey: await SyncKeys.authKey(v1Key),
      );
    });

    Future<void> upload(FamilyDoc doc, {int? base}) async {
      final put = await transport.putList(
        auth,
        baseVersion: base,
        envelope: await seal(
          doc: doc.toJson(),
          listId: _list,
          fromNode: 'x',
          at: '',
          key: v1Key,
        ),
      );
      expect(put, isA<SyncPutOk>());
    }

    Future<DeviceRegistry> registryWith(List<(String, int)> devices) async {
      var registry = DeviceRegistry.empty(_list);
      for (final (id, seed) in devices) {
        registry = await registry.withRecord(
          await DeviceRecord.create(
            keys: await _keys(seed),
            listId: _list,
            deviceId: id,
            personId: null,
          ),
        );
      }
      return registry;
    }

    test('se queda mientras alguien que escribió en v1 no ha migrado, y lo '
        'que escribe se fusiona en v2; después se borra', () async {
      var v1 = _gift(FamilyDoc.empty(_list), aritz, 'g1', 'Bufanda');
      v1 = _gift(v1, nora, 'g2', 'Taza');
      await upload(v1);
      final legacy = LegacyV1(
        listId: _list,
        key: v1Key,
        since: clock.now(),
        nodes: writerNodesOf(v1),
      );
      final absorbed = <FamilyDoc>[];
      final first = await retireV1(
        transport: transport,
        legacy: legacy,
        registry: await registryWith([(aritz.node, 1), (leo.node, 2)]),
        absorb: (doc) async => absorbed.add(doc),
      );
      expect(first, V1Retirement.kept);
      expect(server.hasList(auth.syncId), isTrue);
      expect(_titles(absorbed.single), {'Bufanda', 'Taza'});
      final second = await retireV1(
        transport: transport,
        legacy: legacy,
        registry: await registryWith([
          (aritz.node, 1),
          (leo.node, 2),
          (nora.node, 3),
        ]),
        absorb: (doc) async => absorbed.add(doc),
      );
      expect(second, V1Retirement.retired);
      expect(server.hasList(auth.syncId), isFalse);
    });

    test('B4: tras el corte al formato 2 la absorción está cerrada: no se '
        'fusiona nada y se borra aunque falte alguien', () async {
      await upload(_gift(FamilyDoc.empty(_list), nora, 'g1', 'Taza'));
      final absorbed = <FamilyDoc>[];
      final result = await retireV1(
        transport: transport,
        legacy: LegacyV1(
          listId: _list,
          key: v1Key,
          since: clock.now(),
          nodes: {nora.node},
        ),
        registry: await registryWith([(aritz.node, 1)]),
        absorb: (doc) async => absorbed.add(doc),
        closed: true,
      );
      expect(result, V1Retirement.retired);
      expect(absorbed, isEmpty);
      expect(server.hasList(auth.syncId), isFalse);
    });

    test('«Dejar de sincronizar» la borra aunque falte alguien', () async {
      await upload(_gift(FamilyDoc.empty(_list), nora, 'g1', 'Taza'));
      final result = await retireV1(
        transport: transport,
        legacy: LegacyV1(
          listId: _list,
          key: v1Key,
          since: clock.now(),
          nodes: {nora.node},
        ),
        registry: await registryWith([(aritz.node, 1)]),
        absorb: (_) async {},
        force: true,
      );
      expect(result, V1Retirement.retired);
      expect(server.hasList(auth.syncId), isFalse);
    });

    test(
      'ataque (hallazgo 1): escribir con nodos nuevos no retiene la copia '
      'v1; caduca a los 30 días y se le quita la marca al absorberla',
      () async {
        final v1 = _gift(FamilyDoc.empty(_list), aritz, 'g1', 'Bufanda');
        final legacy = LegacyV1(
          listId: _list,
          key: v1Key,
          since: clock.now(),
          nodes: writerNodesOf(v1),
        );
        // Alguien con la clave v1 escribe con un nodo que nadie conocía al
        // migrar, y la marca a 1.
        final intruder = HlcClock(node: 'intruder01');
        await upload(
          _gift(v1, intruder, 'g2', 'Intruso').set(
            intruder,
            Collections.meta,
            kProtocolRecordId,
            {kProtocolVersionField: 1},
          ),
        );
        final absorbed = <FamilyDoc>[];
        final result = await retireV1(
          transport: transport,
          legacy: legacy,
          registry: await registryWith([(aritz.node, 1)]),
          absorb: (doc) async => absorbed.add(doc),
        );
        expect(
          result,
          V1Retirement.retired,
          reason: 'solo se esperaba a Aritz',
        );
        expect(
          absorbed.single.record(Collections.meta, kProtocolRecordId),
          isNull,
        );

        // Con alguien que falta de verdad, se espera... hasta los 30 días.
        await upload(_gift(FamilyDoc.empty(_list), nora, 'g3', 'Taza'));
        final waiting = LegacyV1(
          listId: _list,
          key: v1Key,
          since: DateTime.utc(2026, 11, 1),
          nodes: {aritz.node, nora.node},
        );
        Future<V1Retirement> at(DateTime now) => withClock(
          Clock.fixed(now),
          () async => retireV1(
            transport: transport,
            legacy: waiting,
            registry: await registryWith([(aritz.node, 1)]),
            absorb: (_) async {},
          ),
        );
        expect(await at(DateTime.utc(2026, 11, 30)), V1Retirement.kept);
        expect(server.hasList(auth.syncId), isTrue);
        expect(await at(DateTime.utc(2026, 12, 1)), V1Retirement.retired);
        expect(server.hasList(auth.syncId), isFalse);
        // Un recuerdo sin fecha ni nodos (formato anterior) está caducado.
        final old = LegacyV1.fromJson({'l': _list, 'k': v1Key.toBase64Url()});
        expect(old.expiredAt(DateTime.utc(2026)), isTrue);
      },
    );
  });
}
