import 'dart:typed_data';

import '../../../core/sync/device_registry.dart';
import '../../../core/sync/envelope.dart';
import '../../../core/sync/family_doc.dart';
import '../../../core/sync/hlc.dart';
import '../../../core/sync/pairing_v2.dart';
import '../../../core/sync/protected_doc.dart';
import '../../family/data/family_store.dart';
import '../../family/data/storage.dart';
import '../application/vault_service.dart';
import '../application/web_sync_engine.dart';
import 'web_device_keys_store.dart';

/// No filesystem or ordinary secret-store persistence. Each save becomes one
/// encrypted queue action (all indirect field writes included).
class WebFamilyStore extends FamilyStore {
  WebFamilyStore(this.vault, this.engine, {this.onSaved})
    : super(
        secrets: _DeniedSecrets(),
        files: _DeniedFiles(),
        deviceKeys: WebDeviceKeysStore(vault),
      );
  final VaultService vault;
  final WebSyncEngine engine;
  final void Function()? onSaved;
  FamilyDoc? _displayed;
  Hlc? _latest;
  void _remember(Hlc? stamp) {
    if (stamp != null && (_latest == null || stamp > _latest!)) _latest = stamp;
  }

  @override
  Hlc? latestStoredStamp(FamilyDoc doc) {
    _remember(doc.maxStamp);
    return _latest;
  }

  FamilyIdentity get identity => FamilyIdentity(
    listId: engine.listId,
    node: vault.opened.header.deviceId,
    deviceName: '',
    paired: true,
    selfRecipientId: vault.opened.data['personId'] as String?,
  );
  @override
  Future<StoredFamily?> load() async {
    final doc = engine.candidate;
    if (doc == null) throw StateError('No coherent web snapshot');
    for (final entry in await engine.queue.entries()) {
      _remember(entry.delta.maxStamp);
    }
    _displayed = doc;
    return StoredFamily(
      identity: identity,
      key: FamilyKey.fromBase64Url(vault.opened.data['familyKey'] as String),
      doc: doc,
    );
  }

  @override
  FamilyDoc savedDoc(FamilyDoc requested) => engine.candidate!;
  @override
  bool get durableGiftDeletes => true;
  @override
  bool get supportsRecovery => false;
  @override
  Future<void> assertWritable() async {
    // Web writes are gated by the open vault and checked again by the engine
    // when persisted. Mobile transfer and restore flags do not exist here.
    vault.opened;
  }

  @override
  Future<void> saveGiftDeleteIntent(
    FamilyDoc before,
    FamilyDoc after,
    String id,
    Duration window,
  ) async {
    await engine.save(
      before,
      after,
      undoGiftId: id,
      publishAfter: engine.now().add(window),
    );
    _remember(after.maxStamp);
    _displayed = engine.candidate;
    onSaved?.call();
  }

  @override
  Future<bool> undoGiftDeleteIntent(String id) async {
    final undone = await engine.undoGiftDelete(id);
    _displayed = engine.candidate;
    if (undone) onSaved?.call();
    return undone;
  }

  @override
  Future<FamilyDoc> cascadeDoc(FamilyDoc displayed) async {
    // Read deltas first: sync persists its confirmed snapshot before acking
    // them. Reading the snapshot first could miss a delta acked in between.
    final entries = await engine.queue.entries();
    var doc = await engine.savedCommon();
    final blocked = await engine.queue.blockedPeople();
    for (final entry in entries) {
      // A provisional tombstone must not hide a gift's references from a
      // cascade. Its independent undo intent remains durable and cancellable.
      if (entry.undoGiftId == null &&
          !entry.setAside &&
          webEntryAllowed(doc, entry, blocked)) {
        doc = doc.merge(entry.delta);
      }
    }
    return doc;
  }

  @override
  Future<void> saveCascadeDoc(FamilyDoc before, FamilyDoc after) async {
    await engine.save(before, after);
    _remember(after.maxStamp);
    _displayed = engine.candidate;
    onSaved?.call();
  }

  @override
  void requireMobileOperation(String operation) =>
      throw WebOperationException(operation);
  @override
  Future<void> saveDoc(FamilyDoc doc) async {
    await engine.save(_displayed ?? engine.candidate!, doc);
    _remember(doc.maxStamp);
    _displayed = engine.candidate;
    onSaved?.call();
  }

  @override
  Future<void> saveFamily(StoredFamily family) async =>
      throw const WebOperationException('replaceFamily');
  @override
  Future<void> saveIdentity(FamilyIdentity identity) async {
    if (identity.toJson().toString() != this.identity.toJson().toString()) {
      throw const WebOperationException('changeIdentity');
    }
  }

  @override
  Future<void> clear() async =>
      throw const WebOperationException('leaveFamily');
  @override
  Future<void> saveSelfRecipient(String? recipientId) async {
    if (recipientId != identity.selfRecipientId) {
      throw const WebOperationException('changePerson');
    }
  }

  @override
  Future<String?> readSelfRecipient() async => identity.selfRecipientId;
  @override
  Future<SyncIdentityV2?> readSyncV2() async => SyncIdentityV2(
    listId: engine.listId,
    deviceId: identity.node,
    syncId: vault.opened.header.syncId,
  );
  @override
  Future<Object?> readSyncV2State() async => {
    'version': engine.version,
    'created': true,
  };
  @override
  Future<Object?> readLegacyV1() async => null;
  @override
  Future<Object?> readPendingV2() async => null;
  @override
  Future<DeviceRegistry?> readRegistry({RegistryAnchor? anchor}) async =>
      DeviceRegistry.fromLocalStoreJson(
        vault.opened.data['registryLocal'],
        anchor: anchor,
      );
  @override
  Future<SlotSet> readSlots() async => SlotSet.empty;
  @override
  Future<List<Map<String, Object?>>> readOrphans() async => [];
  @override
  Future<String?> orphanScope() async => null;
}

class _DeniedSecrets implements SecretStore {
  Never _deny() => throw const WebOperationException('restrictedStorage');
  @override
  Future<String?> read(String key) async => _deny();
  @override
  Future<void> write(String key, String value) async => _deny();
  @override
  Future<void> delete(String key) async => _deny();
}

class _DeniedFiles implements FileStore {
  Never _deny() => throw const WebOperationException('restrictedStorage');
  @override
  Future<Uint8List?> read(String name) async => _deny();
  @override
  Future<void> writeAtomic(String name, Uint8List bytes) async => _deny();
  @override
  Future<void> delete(String name) async => _deny();
}
