import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/family/data/generation_storage.dart';

import '../helpers/memory_stores.dart';

const _identity = FamilyIdentity(
  listId: 'family',
  node: 'phone',
  deviceName: 'Aritz',
);
final _localKey = List<int>.generate(32, (i) => i);

class _DelayedPrefix extends MemorySecretStore {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<String?> read(String key) async {
    if (key == generationDirectoryKey && !started.isCompleted) {
      started.complete();
      await release.future;
    }
    return super.read(key);
  }
}

Future<Uint8List> _legacyBytes(FamilyDoc doc, List<int> nonce) async {
  final box = await AesGcm.with256bits().encrypt(
    utf8.encode(doc.canonicalJson()),
    secretKey: SecretKey(_localKey),
    nonce: nonce,
    aad: utf8.encode('regalos-doc:v1'),
  );
  return Uint8List.fromList([
    0x52,
    0x47,
    0x44,
    0x01,
    ...box.nonce,
    ...box.cipherText,
    ...box.mac.bytes,
  ]);
}

void main() {
  late MemorySecretStore secrets;
  late MemoryFileStore files;
  late FamilyStore store;
  late FamilyDoc doc;

  setUp(() {
    secrets = MemorySecretStore()
      ..values['family.localKey'] = encodeBase64Url(_localKey)
      ..values['family.key'] = FamilyKey(List<int>.filled(32, 3)).toBase64Url()
      ..values['family.identity'] = jsonEncode(_identity.toJson());
    files = MemoryFileStore();
    store = FamilyStore(
      secrets: secrets,
      files: files,
      deviceKeys: DeviceKeysStore(secrets),
    );
    final clock = HlcClock(node: _identity.node);
    doc = FamilyDoc.empty(_identity.listId);
    for (var i = 0; i < 465; i++) {
      doc = doc.set(clock, 'gifts', 'gift-$i', {
        'title': 'Pel·lícula $i',
        'extra': {
          'b': null,
          'a': [1, true, 'Nora'],
        },
      });
    }
  });

  test(
    'reads the old format and writes the same bytes for the same nonce',
    () async {
      files.files['family.doc'] = await _legacyBytes(
        doc,
        List<int>.filled(12, 7),
      );
      expect((await store.load())!.doc.toJson(), doc.toJson());

      await store.saveDoc(doc);
      final written = files.files['family.doc']!;
      expect(written, await _legacyBytes(doc, written.sublist(4, 16)));
      expect((await store.load())!.doc.toJson(), doc.toJson());
    },
  );

  test('a small save queued after a large save is written last', () async {
    final smallDoc = FamilyDoc.empty(_identity.listId);
    await Future.wait([store.saveDoc(doc), store.saveDoc(smallDoc)]);
    expect((await store.load())!.doc.toJson(), smallDoc.toJson());
  });

  test('a slow first prefix lookup does not reorder saves', () async {
    final delayed = _DelayedPrefix()..values.addAll(secrets.values);
    final store = FamilyStore(
      secrets: delayed,
      files: files,
      deviceKeys: DeviceKeysStore(delayed),
    );
    final first = store.saveDoc(doc);
    await delayed.started.future;
    final lastDoc = FamilyDoc.empty(_identity.listId);
    final second = store.saveDoc(lastDoc);
    await Future<void>.delayed(Duration.zero);
    delayed.release.complete();

    await Future.wait([first, second]);
    expect((await store.load())!.doc.toJson(), lastDoc.toJson());
  });

  test(
    'a queued save keeps the generation pinned in its caller zone',
    () async {
      const source = 'AAAAAAAAAAAAAAAAAAAAAA';
      const destination = 'BBBBBBBBBBBBBBBBBBBBBB';
      const entries = {
        source: (listId: 'family', legacy: true),
        destination: (listId: 'family', legacy: false),
      };
      await GenerationDirectory(active: source, entries: entries).save(secrets);
      final caller = GenerationSecretStore(secrets);
      final blocker = Completer<void>();
      final previous = GenerationStorageQueue.on(
        secrets,
        'family.doc',
      ).run(() => blocker.future);

      await caller.inGeneration(() async {
        await GenerationDirectory(
          active: destination,
          entries: entries,
          activation: 1,
        ).save(secrets);
        final save = store.saveDoc(doc);
        blocker.complete();
        await save;
      });
      await previous;

      expect(files.files.keys, ['family.doc']);
      final sourceSecrets = GenerationSecretStore(secrets, syncId: source);
      final sourceStore = FamilyStore(
        secrets: sourceSecrets,
        files: files,
        deviceKeys: DeviceKeysStore(sourceSecrets),
      );
      expect((await sourceStore.load())!.doc.toJson(), doc.toJson());
    },
  );
}
