import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_candidate.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/protected_doc.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/sync/application/common_v2.dart';

import '../helpers/memory_stores.dart';

/// Almacén que apunta el orden de los borrados.
class _RecordingSecrets extends MemorySecretStore {
  final deleted = <String>[];

  @override
  Future<void> delete(String key) async {
    deleted.add(key);
    await super.delete(key);
  }
}

/// Almacén lento: cada lectura y cada escritura ceden el turno, como el
/// almacén seguro de verdad, para que dos operaciones a la vez se mezclen.
class _SlowSecrets extends _RecordingSecrets {
  @override
  Future<String?> read(String key) async {
    await Future<void>.delayed(Duration.zero);
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    await Future<void>.delayed(Duration.zero);
    await super.write(key, value);
  }
}

/// Guardado de «Yo», de las claves del móvil y del llavero (ADR 0004).
void main() {
  late _RecordingSecrets secrets;
  late MemoryFileStore files;
  late FamilyStore store;
  late DeviceKeysStore keysStore;

  void build(_RecordingSecrets on) {
    secrets = on;
    files = MemoryFileStore();
    keysStore = DeviceKeysStore(secrets, enabled: true);
    store = FamilyStore(secrets: secrets, files: files, deviceKeys: keysStore);
  }

  setUp(() => build(_RecordingSecrets()));

  Future<void> saveFamily() => store.saveFamily(
    StoredFamily(
      identity: const FamilyIdentity(
        listId: 'list-1',
        node: 'abcdefghij',
        deviceName: 'Pixel',
      ),
      key: FamilyKey(List<int>.filled(32, 1)),
      doc: FamilyDoc.empty('list-1'),
    ),
  );

  group('«Yo»', () {
    test('se guarda, se lee y se quita, solo con el id', () async {
      await saveFamily();
      expect(await store.readSelfRecipient(), isNull);
      await store.saveSelfRecipient('nora');
      expect(await store.readSelfRecipient(), 'nora');
      final loaded = await store.load();
      expect(loaded!.identity.selfRecipientId, 'nora');
      expect(loaded.doc.canonicalJson(), isNot(contains('nora')));
      await store.saveIdentity(loaded.identity.copyWith(paired: true));
      expect(await store.readSelfRecipient(), 'nora');
      await store.saveSelfRecipient(null);
      expect(await store.readSelfRecipient(), isNull);
    });

    test(
      'M7: elegir «Yo» quita del llavero las claves de esa persona',
      () async {
        await saveFamily();
        await keysStore.saveKeyring(
          'list-1',
          SurpriseKeyring([
            SurpriseKey.generate('nora', 1),
            SurpriseKey.generate('leo', 1),
          ]),
        );
        await store.saveSelfRecipient('nora');
        final keyring = await keysStore.readKeyring('list-1');
        expect(keyring.people, {'leo'});
      },
    );

    test('N5: purgar y guardar el llavero a la vez no se pisan: las dos '
        'cosas van por la misma cola', () async {
      build(_SlowSecrets());
      await saveFamily();
      await keysStore.saveKeyring(
        'list-1',
        SurpriseKeyring([SurpriseKey.generate('nora', 1)]),
      );
      // A la vez: este móvil pasa a ser de Nora y llega la clave de Leo.
      await Future.wait([
        store.saveSelfRecipient('nora'),
        keysStore.saveKeyring(
          'list-1',
          SurpriseKeyring([SurpriseKey.generate('leo', 1)]),
        ),
      ]);
      // Ni se queda la clave de Nora ni se pierde la de Leo.
      expect((await keysStore.readKeyring('list-1')).people, {'leo'});
      // Y borrar la familia tampoco se cruza con una escritura pendiente.
      final pending = keysStore.saveKeyring(
        'list-1',
        SurpriseKeyring([SurpriseKey.generate('aritz', 1)]),
      );
      await Future.wait([pending, store.clear()]);
      expect((await keysStore.readKeyring('list-1')).people, isEmpty);
    });

    test('ataque (hallazgo 11): un llavero leído antes de elegir «Yo» no '
        'devuelve, al guardarlo, las claves de esa persona', () async {
      await saveFamily();
      await keysStore.saveKeyring(
        'list-1',
        SurpriseKeyring([
          SurpriseKey.generate('nora', 1),
          SurpriseKey.generate('leo', 1),
        ]),
      );
      final stale = await keysStore.readKeyring('list-1');
      await store.saveSelfRecipient('nora');
      // Quien leyó antes guarda el llavero entero, o lo cambia sobre lo viejo.
      await keysStore.saveKeyring('list-1', stale);
      expect((await keysStore.readKeyring('list-1')).people, {'leo'});
      await keysStore.updateKeyring('list-1', (_) => stale);
      expect((await keysStore.readKeyring('list-1')).people, {'leo'});
      // Tampoco entra una clave nueva de Nora mientras este móvil sea suyo.
      final back = await keysStore.updateKeyring(
        'list-1',
        (k) => k.withKey(SurpriseKey.generate('nora', 2), registryEpoch: 2),
      );
      expect(back.people, {'leo'});
      // Al dejar de ser de Nora, sí.
      await store.saveSelfRecipient('leo');
      final again = await keysStore.updateKeyring(
        'list-1',
        (k) => k.withKey(SurpriseKey.generate('nora', 2), registryEpoch: 2),
      );
      expect(again.people, {'nora'});
    });

    test(
      'hallazgo 11: dos cambios del llavero a la vez no se pierden nada',
      () async {
        build(_SlowSecrets());
        await saveFamily();
        await Future.wait([
          for (final person in ['aritz', 'leo', 'nora'])
            keysStore.updateKeyring(
              'list-1',
              (k) =>
                  k.withKey(SurpriseKey.generate(person, 1), registryEpoch: 1),
            ),
        ]);
        expect((await keysStore.readKeyring('list-1')).people, {
          'aritz',
          'leo',
          'nora',
        });
      },
    );

    test('req. 4: elegir «Yo» borra la copia local de sus sorpresas y lo que '
        'se guardó de ella', () async {
      await saveFamily();
      final clock = HlcClock(node: 'abcdefghij');
      FamilyDoc scopeOf(String person) => FamilyDoc.empty('list-1').set(
        clock,
        Collections.gifts,
        'g-$person',
        {'recipientId': person, 'title': 'Sorpresa de $person'},
      );
      for (final person in ['nora', 'leo']) {
        await store.saveScope(person, scopeOf(person));
        await store.saveOverflow(
          person,
          scopeOf(person).collections[Collections.gifts]!.values.toList(),
        );
      }
      expect(
        (await store.readScope('nora'))!.canonicalJson(),
        contains('nora'),
      );
      expect(await store.readOverflow('nora'), hasLength(1));
      // En el disco va cifrado.
      expect(
        String.fromCharCodes((await files.read('family.scope.nora'))!),
        isNot(contains('Sorpresa')),
      );
      await store.saveSelfRecipient('nora');
      expect(await store.readScope('nora'), isNull);
      expect(await store.readOverflow('nora'), isEmpty);
      expect(await files.read('family.scope.nora'), isNull);
      // Lo de Leo sigue.
      expect((await store.readScope('leo'))!.canonicalJson(), contains('leo'));
      // Lo que no cabe se va sumando, no se pisa.
      await store.saveOverflow('leo', [
        scopeOf('leo')
            .set(clock, Collections.gifts, 'otro', {
              'recipientId': 'leo',
              'title': 'Otro',
            })
            .record(Collections.gifts, 'otro')!,
      ]);
      expect(
        [for (final r in await store.readOverflow('leo')) r.id],
        ['g-leo', 'otro'],
      );
      // Un fichero de un ámbito no se abre como otro, ni un id raro sirve de
      // nombre de fichero.
      await files.writeAtomic(
        'family.scope.nora',
        (await files.read('family.scope.leo'))!,
      );
      await expectLater(
        store.readScope('nora'),
        throwsA(isA<FamilyStoreException>()),
      );
      await expectLater(
        store.saveScope('../fuera', scopeOf('leo')),
        throwsA(isA<FamilyStoreException>()),
      );
      // Borrar la familia se lleva todo.
      await store.clear();
      expect(await files.read('family.scope.leo'), isNull);
      expect(await files.read('family.overflow.leo'), isNull);
    });

    test('el registro de móviles y los slots se guardan cifrados y se leen '
        'igual', () async {
      await saveFamily();
      expect(await store.readRegistry(), isNull);
      expect((await store.readSlots()).all, isEmpty);
      final keys = await keysStore.create();
      final registry = await DeviceRegistry.empty('list-1').withRecord(
        await DeviceRecord.create(
          keys: keys,
          listId: 'list-1',
          deviceId: 'abcdefghij',
          personId: 'aritz',
        ),
      );
      await store.saveRegistry(registry);
      await store.saveSlots(SlotSet.empty);
      expect((await store.readRegistry())!.sameAs(registry), isTrue);
      // N8: con el ancla de la vista de este móvil, lo mismo.
      expect(
        (await store.readRegistry(
          anchor: RegistryAnchor(
            deviceId: 'abcdefghij',
            signingKey: keys.publicKeys.signing,
          ),
        ))!.sameAs(registry),
        isTrue,
      );
      expect((await store.readSlots()).all, isEmpty);
      expect(
        String.fromCharCodes((await files.read('family.registry'))!),
        isNot(contains('abcdefghij')),
      );
      await store.clear();
      expect(await files.read('family.registry'), isNull);
      expect(await files.read('family.slots'), isNull);
    });

    test('B3: la clave común y los comunes retenidos van cifrados, se leen '
        'igual tras reabrir y se borran al salir', () async {
      await saveFamily();
      expect(await store.readCommonKeys(), isNull);
      final keys = await keysStore.create();
      final registry = await DeviceRegistry.empty('list-1').withRecord(
        await DeviceRecord.create(
          keys: keys,
          listId: 'list-1',
          deviceId: 'abcdefghij',
          personId: 'aritz',
        ),
      );
      final view = await registry.viewFor(
        me: 'abcdefghij',
        mySigningKey: keys.publicKeys.signing,
        livePeople: {'aritz'},
      );
      final candidate = await FamilyCandidate.generate(
        view,
        keys: keys,
        syncId: 'QUJDREVGR0hJSktMTU5PUA',
      );
      final state = CommonKeyState(
        keyring: FamilyKeyring.empty
            .withOwnCandidate(candidate)
            .withReference(candidate.kid, kCommonRef),
        revision: 3,
        lastKid: candidate.kid,
      );
      expect(await store.commonKeysMarked(), isFalse);
      await store.saveCommonKeys(state.toJson());
      await store.markCommonKeys();
      final hash = 'c' * 64;
      await store.saveRetainedBytes(hash, Uint8List.fromList([1, 2, 3]));
      await store.saveRetainedCommons([
        RetainedCommon(
          hash: hash,
          reason: RemoteCommonStatus.missingKey,
          seenAtMillis: 5,
          hasBytes: true,
        ).toJson(),
      ]);
      expect(
        String.fromCharCodes((await files.read('family.retained.$hash'))!),
        isNot(contains('AQID')),
      );
      final raw = String.fromCharCodes(
        (await files.read('family.commonkeys'))!,
      );
      expect(raw, isNot(contains(candidate.kid)));
      expect(raw, isNot(contains(encodeBase64Url(candidate.secret))));
      final reopened = FamilyStore(
        secrets: secrets,
        files: files,
        deviceKeys: keysStore,
      );
      final back = CommonKeyState.fromJson(await reopened.readCommonKeys());
      expect(back.revision, 3);
      expect(back.lastKid, candidate.kid);
      expect(
        back.keyring.entry(candidate.kid)!.candidate.secret,
        candidate.secret,
      );
      expect(back.keyring.entry(candidate.kid)!.references, {kCommonRef});
      final retained = await reopened.readRetainedCommons();
      expect(RetainedCommon.fromJson((retained! as List).single).hash, hash);
      expect(await reopened.readRetainedBytes(hash), [1, 2, 3]);
      expect(await reopened.commonKeysMarked(), isTrue);
      await store.clear();
      expect(await files.read('family.commonkeys'), isNull);
      expect(await files.read('family.retainedcommons'), isNull);
      expect(await files.read('family.retained.$hash'), isNull);
      expect(await store.commonKeysMarked(), isFalse);
    });

    test('B3: los bytes de un retenido que no llegó al índice (cierre a '
        'medias) se borran al leer el índice y al salir', () async {
      await saveFamily();
      final kept = 'd' * 64;
      final orphan = 'e' * 64;
      await store.saveRetainedBytes(kept, Uint8List.fromList([1]));
      await store.saveRetainedCommons([
        RetainedCommon(
          hash: kept,
          reason: RemoteCommonStatus.missingKey,
          seenAtMillis: 1,
          hasBytes: true,
        ).toJson(),
      ]);
      // Cierre después de escribir los bytes y antes del índice.
      await store.saveRetainedBytes(orphan, Uint8List.fromList([2]));
      expect(await files.read('family.retained.$orphan'), isNotNull);
      await store.readRetainedCommons();
      expect(await files.read('family.retained.$orphan'), isNull);
      expect(await store.readRetainedBytes(kept), [1]);
      // Otro a medias: también sale con «borrar todo».
      await store.saveRetainedBytes(orphan, Uint8List.fromList([3]));
      await store.clear();
      expect(await files.read('family.retained.$orphan'), isNull);
      expect(await files.read('family.retained.$kept'), isNull);
    });

    test(
      'el registro conserva las marcas de conflicto en el almacén cifrado',
      () async {
        await saveFamily();
        final keys = await keysStore.create();
        final root = await DeviceRecord.create(
          keys: keys,
          listId: 'list-1',
          deviceId: 'abcdefghij',
          personId: 'aritz',
        );
        final other = keys;
        final mobile = await DeviceRecord.create(
          keys: other,
          listId: 'list-1',
          deviceId: 'nora-web',
          personId: 'nora',
        );
        final web = await DeviceRecord.create(
          keys: other,
          listId: 'list-1',
          deviceId: 'nora-web',
          personId: 'nora',
          kind: DeviceKind.web,
        );
        final anchor = RegistryAnchor(
          deviceId: root.deviceId,
          signingKey: root.keys.signing,
        );
        final registry = await DeviceRegistry.empty('list-1').withDeclarations(
          records: [root, mobile, web],
          vouches: [await Vouch.create(keys: keys, voucher: root, record: web)],
          anchor: anchor,
        );
        expect(registry.toLocalStoreJson()['localTypeConflicts'], hasLength(1));
        await store.saveRegistry(registry);
        final reopened = FamilyStore(
          secrets: secrets,
          files: files,
          deviceKeys: keysStore,
        );
        final restored = (await reopened.readRegistry())!;
        expect(restored.sameAs(registry), isTrue);
        expect(restored.toJson().containsKey('localTypeConflicts'), isFalse);
      },
    );

    test('una identidad antigua, sin el campo, se sigue leyendo', () async {
      await saveFamily();
      final raw = jsonDecode((await secrets.read('family.identity'))!) as Map;
      expect(raw.containsKey('selfRecipientId'), isFalse);
      expect((await store.load())!.identity.selfRecipientId, isNull);
    });

    test('sin familia no se puede elegir', () async {
      expect(await store.readSelfRecipient(), isNull);
      await expectLater(
        store.saveSelfRecipient('aritz'),
        throwsA(isA<FamilyStoreException>()),
      );
    });
  });

  group('claves del móvil', () {
    test('se crean una vez y nunca se regeneran en silencio (B4)', () async {
      expect(await keysStore.read(), isNull);
      final first = await keysStore.create();
      final again = await keysStore.read();
      expect(again!.publicKeys.signing, first.publicKeys.signing);
      expect(again.serviceCredential, first.serviceCredential);
      await expectLater(
        keysStore.create(),
        throwsA(isA<DeviceKeysStoreException>()),
      );
      expect(
        (await keysStore.read())!.publicKeys.signing,
        first.publicKeys.signing,
      );
    });

    test('dos creaciones a la vez: una gana y la otra falla (B4)', () async {
      final results = await Future.wait([
        keysStore.create().then((_) => true, onError: (_) => false),
        keysStore.create().then((_) => true, onError: (_) => false),
      ]);
      expect(results.where((ok) => ok), hasLength(1));
    });

    test('el llavero va con su lista: de otra lista no se usa (B4)', () async {
      expect((await keysStore.readKeyring('list-1')).people, isEmpty);
      final key = SurpriseKey.generate('nora', 1);
      await keysStore.saveKeyring('list-1', SurpriseKeyring([key]));
      final back = await keysStore.readKeyring('list-1');
      expect(back.latestFor('nora')!.bytes, key.bytes);
      expect((await keysStore.readKeyring('otra-lista')).people, isEmpty);
    });

    test('en la web no se guarda nada (B4)', () async {
      final web = DeviceKeysStore(secrets, enabled: false);
      await expectLater(web.create(), throwsA(isA<DeviceKeysStoreException>()));
      await expectLater(
        web.saveKeyring('list-1', SurpriseKeyring.empty),
        throwsA(isA<DeviceKeysStoreException>()),
      );
      expect(secrets.values, isEmpty);
    });

    test('dañadas: error claro', () async {
      await secrets.write(kDeviceKeysSecret, '{"v":1}');
      await secrets.write(kSurpriseKeysSecret, 'no es json');
      await expectLater(
        keysStore.read(),
        throwsA(isA<DeviceKeysStoreException>()),
      );
      await expectLater(
        keysStore.readKeyring('list-1'),
        throwsA(isA<DeviceKeysStoreException>()),
      );
    });

    test('borrar la familia borra antes los secretos y la identidad al final '
        '(B4)', () async {
      await saveFamily();
      await keysStore.create();
      await keysStore.saveKeyring(
        'list-1',
        SurpriseKeyring([SurpriseKey.generate('nora', 1)]),
      );
      await store.clear();
      expect(await keysStore.read(), isNull);
      expect((await keysStore.readKeyring('list-1')).people, isEmpty);
      expect(secrets.deleted.last, 'family.identity');
      expect(
        secrets.deleted.indexOf(kDeviceKeysSecret),
        lessThan(secrets.deleted.indexOf('family.identity')),
      );
    });
  });
}
