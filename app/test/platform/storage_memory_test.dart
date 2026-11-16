import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/family/data/storage_memory.dart';

void main() {
  test('memory stores isolate instances and copy byte buffers', () async {
    final files = MemoryFileStore();
    final bytes = Uint8List.fromList([1, 2]);
    await files.writeAtomic('family.doc', bytes);
    bytes[0] = 9;
    final read = (await files.read('family.doc'))!;
    expect(read, [1, 2]);
    read[0] = 8;
    expect(await files.read('family.doc'), [1, 2]);
    expect(await MemoryFileStore().read('family.doc'), isNull);
    await files.delete('family.doc');
    await files.delete('family.doc');
    expect(await files.read('family.doc'), isNull);
    final secrets = MemorySecretStore();
    await secrets.write('key', 'value');
    expect(await secrets.read('key'), 'value');
    expect(await MemorySecretStore().read('key'), isNull);
    await secrets.delete('key');
    expect(await secrets.read('key'), isNull);
  });
  test(
    'FamilyStore round trips the same encrypted document format in memory',
    () async {
      final secrets = MemorySecretStore();
      final files = MemoryFileStore();
      final store = FamilyStore(
        secrets: secrets,
        files: files,
        deviceKeys: DeviceKeysStore(secrets, enabled: true),
      );
      final family = StoredFamily(
        identity: const FamilyIdentity(
          listId: 'family',
          node: 'node',
          deviceName: 'Aritz',
        ),
        key: FamilyKey(Uint8List(32)),
        doc: FamilyDoc.empty('family'),
      );
      await store.saveFamily(family);
      final raw = (await files.read('family.doc'))!;
      expect(raw.take(4), [0x52, 0x47, 0x44, 1]);
      final loaded = await FamilyStore(
        secrets: secrets,
        files: files,
        deviceKeys: DeviceKeysStore(secrets, enabled: true),
      ).load();
      expect(loaded!.doc.canonicalJson(), family.doc.canonicalJson());
      expect(loaded.key.bytes, family.key.bytes);
      await store.clear();
      expect(await store.load(), isNull);
      expect(await files.read('family.doc'), isNull);
    },
  );
}
