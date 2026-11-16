// Lo local del ciclo v2 en la app: el documento común pasa por
// `FamilyController` (misma cola que las ediciones), y el registro, los
// slots, el llavero, los ámbitos y el estado, por `FamilyStore` y
// `DeviceKeysStore`, cifrados en el móvil.
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/access_policy.dart';
import '../../../core/sync/device_keys.dart';
import '../../../core/sync/device_registry.dart';
import '../../../core/sync/envelope.dart';
import '../../../core/sync/family_doc.dart';
import '../../../core/sync/pairing_v2.dart';
import '../../../core/sync/protected_doc.dart';
import '../../family/application/family_controller.dart';
import '../../family/data/device_keys_store.dart';
import '../../family/data/family_store.dart';
import 'common_v2.dart';
import '../data/sync_transport_v2.dart';
import 'family_snapshot.dart';
import 'sync_v2_engine.dart';
import 'v2_family_lock.dart';

/// Una sola cola por los almacenes de familia de este contenedor.
final v2FamilyLockProvider = Provider<V2FamilyLock>((ref) => V2FamilyLock());

/// [SyncV2Local] sobre los almacenes de la app.
class AppSyncV2Local
    implements
        SyncV2Local,
        ProtectionSyncLocal,
        RecoverySyncLocal,
        RecoveryBootstrapLocal {
  AppSyncV2Local._(
    this._ref,
    this.identity,
    this.keys,
    this.node,
    this.familyKey,
  );

  /// Lo local de la familia v2 de este móvil, o null si no hay familia, sigue
  /// en v1 o le faltan las claves del móvil.
  static Future<AppSyncV2Local?> load(Ref ref) async {
    final store = ref.read(familyStoreProvider);
    final v2 = await store.readSyncV2();
    if (v2 == null) return null;
    await ref
        .read(familyControllerProvider.notifier)
        .recoverProtectionWithinLock();
    final fam = await familySnapshot(ref);
    final key = ref.read(familyControllerProvider.notifier).familyKey;
    final keys = await ref.read(deviceKeysStoreProvider).read();
    final identity = fam.identity;
    if (identity == null ||
        key == null ||
        keys == null ||
        identity.listId != v2.listId) {
      return null;
    }
    return AppSyncV2Local._(ref, v2, keys, identity.node, key);
  }

  final Ref _ref;

  @override
  final SyncIdentityV2 identity;

  @override
  final DeviceKeys keys;

  @override
  final String node;

  @override
  final FamilyKey familyKey;

  FamilyStore get _store => _ref.read(familyStoreProvider);

  @override
  Future<V2SnapshotUpload?> readRecoveryBootstrap() async =>
      await _store.recoveryActivationPending()
      ? recoveryBootstrapFromJson(await _store.readRecoveryBootstrap())
      : null;
  @override
  Future<void> saveRecoveryBootstrap(V2SnapshotUpload body) async {
    if (await _store.recoveryActivationPending()) {
      await _store.saveRecoveryBootstrap(recoveryBootstrapJson(body));
    }
  }

  @override
  Future<void> assertSyncWritable() async {
    await _store.assertWritable();
    if (await _store.recoveryPersonInvalidationPending()) {
      throw const V2RecoveryInvalidationPendingException();
    }
  }

  @override
  Future<void> markSyncTransferred() => _store.markTransferred();
  @override
  Future<int> slotRevisionFloor(String personId) async =>
      (await _store.readRecoveryRevisionFloors())
          .slots['$personId/${identity.deviceId}'] ??
      0;
  @override
  Future<void> rememberSlotRevision(String personId, int revision) =>
      _store.raiseRecoveryRevisionFloors({
        '$personId/${identity.deviceId}': revision,
      });

  @override
  Future<void> reconcileProtectionBeforePublish() async {
    await _ref
        .read(familyControllerProvider.notifier)
        .publishDeviceNameWithinLock();
    await _ref
        .read(familyControllerProvider.notifier)
        .reconcileProtectedPeopleWithinLock();
  }

  RegistryAnchor get _anchor => RegistryAnchor(
    deviceId: identity.deviceId,
    signingKey: keys.publicKeys.signing,
  );

  @override
  Future<FamilyDoc> common() async => (await familySnapshot(_ref)).doc;

  @override
  Future<void> mergeCommon(FamilyDoc remote, {required String fromNode}) => _ref
      .read(familyControllerProvider.notifier)
      .mergeRemote(remote, fromNode: fromNode);

  @override
  Future<DeviceRegistry> registry() async =>
      await _store.readRegistry(anchor: _anchor) ??
      DeviceRegistry.empty(identity.listId);

  @override
  Future<void> saveRegistry(DeviceRegistry registry) =>
      _store.saveRegistry(registry);

  @override
  Future<SlotSet> slots() => _store.readSlots();

  @override
  Future<void> saveSlots(SlotSet slots) => _store.saveSlots(slots);

  @override
  Future<SurpriseKeyring> updateKeyring(
    SurpriseKeyring Function(SurpriseKeyring current) update,
  ) =>
      _ref.read(deviceKeysStoreProvider).updateKeyring(identity.listId, update);

  @override
  Future<FamilyDoc?> readScope(String personId) => _store.readScope(personId);

  @override
  Future<void> saveScope(String personId, FamilyDoc scope) =>
      _store.saveScope(personId, scope);

  @override
  Future<void> deleteScope(String personId) => _store.deleteScope(personId);

  @override
  Future<V2SyncState> readState() async =>
      V2SyncState.fromJson(await _store.readSyncV2State());

  @override
  Future<void> saveState(V2SyncState state) =>
      _store.saveSyncV2State(state.toJson());

  @override
  Future<CommonKeyState?> readCommonKeys() async {
    final raw = await _store.readCommonKeys();
    return raw == null ? null : CommonKeyState.fromJson(raw);
  }

  @override
  Future<void> saveCommonKeys(CommonKeyState state) =>
      _store.saveCommonKeys(state.toJson());

  @override
  Future<bool> commonKeysMarked() => _store.commonKeysMarked();

  @override
  Future<void> markCommonKeys() => _store.markCommonKeys();

  @override
  Future<int> commonFormatFloor() => _store.readCommonFormatFloor();

  @override
  Future<void> raiseCommonFormatFloor(int format) =>
      _store.raiseCommonFormatFloor(format);

  @override
  Future<List<RetainedCommon>> readRetainedCommons() async {
    final raw = await _store.readRetainedCommons();
    if (raw == null) return const [];
    if (raw is! List) {
      throw const CommonStateException('índice de comunes retenidos dañado');
    }
    return [for (final item in raw) RetainedCommon.fromJson(item)];
  }

  @override
  Future<void> saveRetainedCommons(List<RetainedCommon> retained) =>
      _store.saveRetainedCommons([for (final r in retained) r.toJson()]);

  @override
  Future<Uint8List?> readRetainedBytes(String hash) =>
      _store.readRetainedBytes(hash);

  @override
  Future<void> saveRetainedBytes(String hash, Uint8List bytes) =>
      _store.saveRetainedBytes(hash, bytes);

  @override
  Future<void> deleteRetainedBytes(String hash) =>
      _store.deleteRetainedBytes(hash);
}
