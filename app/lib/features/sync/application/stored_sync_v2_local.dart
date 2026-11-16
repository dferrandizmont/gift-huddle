import 'dart:typed_data';

import '../../../core/sync/device_keys.dart';
import '../../../core/sync/access_policy.dart';
import '../../../core/sync/device_registry.dart';
import '../../../core/sync/envelope.dart';
import '../../../core/sync/family_doc.dart';
import '../../../core/sync/pairing_v2.dart';
import '../../../core/sync/protected_doc.dart';
import '../../family/data/device_keys_store.dart';
import '../../family/data/family_store.dart';
import 'common_v2.dart';
import '../data/sync_transport_v2.dart';
import 'sync_v2_engine.dart';

/// Real encrypted stores in a pinned generation. No application edit state.
class StoredSyncV2Local
    implements
        SyncV2Local,
        RecoverySyncLocal,
        RecoveryBootstrapLocal,
        RecoverySlotCacheLocal {
  StoredSyncV2Local({
    required this.store,
    required this.deviceKeys,
    required this.identity,
    required this.keys,
    required this.familyKey,
  });
  final FamilyStore store;
  final DeviceKeysStore deviceKeys;
  @override
  final SyncIdentityV2 identity;
  @override
  final DeviceKeys keys;
  @override
  final FamilyKey familyKey;
  @override
  String get node => identity.deviceId;
  RegistryAnchor get _anchor =>
      RegistryAnchor(deviceId: node, signingKey: keys.publicKeys.signing);
  @override
  Future<FamilyDoc> common() async => (await store.load())!.doc;
  @override
  Future<void> mergeCommon(FamilyDoc remote, {required String fromNode}) async {
    await store.saveDoc((await common()).merge(remote));
  }

  @override
  Future<Uint8List?> readRecoverySlot(int snapshot, V2SlotRef ref) async {
    final raw = await store.readRecoverySlotCache();
    if (raw is! Map || raw['snapshot'] != snapshot) return null;
    final entry = (raw['slots'] as Map)[ref.key];
    if (entry is! Map || entry['version'] != ref.version) return null;
    return decodeBase64Url(entry['bytes'] as String);
  }

  @override
  Future<void> saveRecoverySlot(
    int snapshot,
    V2SlotRef ref,
    Uint8List bytes,
  ) async {
    final raw = await store.readRecoverySlotCache();
    final slots = raw is Map && raw['snapshot'] == snapshot
        ? Map<String, Object?>.from(raw['slots'] as Map)
        : <String, Object?>{};
    slots[ref.key] = {'version': ref.version, 'bytes': encodeBase64Url(bytes)};
    await store.saveRecoverySlotCache({'snapshot': snapshot, 'slots': slots});
  }

  @override
  Future<V2SnapshotUpload?> readRecoveryBootstrap() async =>
      await store.recoveryActivationPending()
      ? recoveryBootstrapFromJson(await store.readRecoveryBootstrap())
      : null;
  @override
  Future<void> saveRecoveryBootstrap(V2SnapshotUpload body) async {
    if (await store.recoveryActivationPending()) {
      await store.saveRecoveryBootstrap(recoveryBootstrapJson(body));
    }
  }

  @override
  Future<void> assertSyncWritable() async {
    await store.assertWritable();
    if (await store.recoveryPersonInvalidationPending()) {
      throw const V2RecoveryInvalidationPendingException();
    }
  }

  @override
  Future<void> markSyncTransferred() => store.markTransferred();
  @override
  Future<int> slotRevisionFloor(String personId) async =>
      (await store.readRecoveryRevisionFloors()).slots['$personId/$node'] ?? 0;
  @override
  Future<void> rememberSlotRevision(String personId, int revision) =>
      store.raiseRecoveryRevisionFloors({'$personId/$node': revision});
  @override
  Future<DeviceRegistry> registry() async =>
      await store.readRegistry(anchor: _anchor) ??
      DeviceRegistry.empty(identity.listId);

  @override
  Future<void> saveRegistry(DeviceRegistry registry) =>
      store.saveRegistry(registry);

  @override
  Future<SlotSet> slots() => store.readSlots();

  @override
  Future<void> saveSlots(SlotSet slots) => store.saveSlots(slots);

  @override
  Future<SurpriseKeyring> updateKeyring(
    SurpriseKeyring Function(SurpriseKeyring current) update,
  ) => deviceKeys.updateKeyring(identity.listId, update);

  @override
  Future<FamilyDoc?> readScope(String personId) => store.readScope(personId);

  @override
  Future<void> saveScope(String personId, FamilyDoc scope) =>
      store.saveScope(personId, scope);

  @override
  Future<void> deleteScope(String personId) => store.deleteScope(personId);

  @override
  Future<V2SyncState> readState() async =>
      V2SyncState.fromJson(await store.readSyncV2State());

  @override
  Future<void> saveState(V2SyncState state) =>
      store.saveSyncV2State(state.toJson());

  @override
  Future<CommonKeyState?> readCommonKeys() async {
    final raw = await store.readCommonKeys();
    return raw == null ? null : CommonKeyState.fromJson(raw);
  }

  @override
  Future<void> saveCommonKeys(CommonKeyState state) =>
      store.saveCommonKeys(state.toJson());

  @override
  Future<bool> commonKeysMarked() => store.commonKeysMarked();

  @override
  Future<void> markCommonKeys() => store.markCommonKeys();

  @override
  Future<int> commonFormatFloor() => store.readCommonFormatFloor();

  @override
  Future<void> raiseCommonFormatFloor(int format) =>
      store.raiseCommonFormatFloor(format);

  @override
  Future<List<RetainedCommon>> readRetainedCommons() async {
    final raw = await store.readRetainedCommons();
    if (raw == null) return const [];
    if (raw is! List) {
      throw const CommonStateException('índice de comunes retenidos dañado');
    }
    return [for (final item in raw) RetainedCommon.fromJson(item)];
  }

  @override
  Future<void> saveRetainedCommons(List<RetainedCommon> retained) =>
      store.saveRetainedCommons([for (final r in retained) r.toJson()]);

  @override
  Future<Uint8List?> readRetainedBytes(String hash) =>
      store.readRetainedBytes(hash);

  @override
  Future<void> saveRetainedBytes(String hash, Uint8List bytes) =>
      store.saveRetainedBytes(hash, bytes);

  @override
  Future<void> deleteRetainedBytes(String hash) =>
      store.deleteRetainedBytes(hash);
}
