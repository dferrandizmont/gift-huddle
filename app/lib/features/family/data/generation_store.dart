import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/device_keys.dart';
import '../../../core/sync/device_registry.dart';
import '../../../core/sync/envelope.dart';
import '../../../core/sync/family_candidate.dart';
import '../../../core/sync/family_doc.dart';
import '../../../core/sync/model.dart' show Collections;
import '../../../core/sync/pairing_v2.dart';
import 'device_keys_store.dart';
import 'family_store.dart';
import 'generation_storage.dart';
import 'renewal_journal_store.dart';
import 'recovery_store.dart';
import 'storage.dart';
import 'storage_providers.dart';

const _confirmedEraseFile = 'family.confirmedErase';

class RecoverySourceException implements Exception {
  const RecoverySourceException(this.code);
  final String code;
}

/// A pinned context. It keeps reading/writing the same generation after the
/// active pointer changes. Serialize edits and installation with the family lock.
class GenerationContext {
  GenerationContext._({
    required this.syncId,
    required this.family,
    required this.deviceKeys,
  });

  final String syncId;
  final FamilyStore family;
  final DeviceKeysStore deviceKeys;
}

/// Exact durable preparation. Ed25519, X25519, service credential, deviceId,
/// family key and syncId are fresh; the source document keeps its HLCs,
/// tombstones and unknown fields. Source scopes are left in the source context
/// for an authorized reader to transfer, never silently treated as empty.
class PreparedGeneration {
  PreparedGeneration._({
    required this.identity,
    required this.family,
    required this.deviceKeys,
    required this.commonFormatFloor,
  });

  final SyncIdentityV2 identity;
  final StoredFamily family;
  final DeviceKeys deviceKeys;
  final int commonFormatFloor;

  Map<String, Object?> toJson() => {
    'identity': identity.toJson(),
    'familyIdentity': family.identity.toJson(),
    'familyKey': family.key.toBase64Url(),
    'doc': family.doc.toJson(),
    'deviceKeys': deviceKeys.toJson(),
    'commonFormatFloor': commonFormatFloor,
  };

  static Future<PreparedGeneration> fromJson(Object? raw) async {
    try {
      final json = raw as Map;
      final identity = SyncIdentityV2.fromJson(json['identity']);
      final family = StoredFamily(
        identity: FamilyIdentity.fromJson(
          Map<String, Object?>.from(json['familyIdentity'] as Map),
        ),
        key: FamilyKey.fromBase64Url(json['familyKey'] as String),
        doc: FamilyDoc.fromJson(Map<String, Object?>.from(json['doc'] as Map)),
      );
      final floor = json['commonFormatFloor'] as int;
      if (family.identity.listId != identity.listId ||
          family.identity.node != identity.deviceId ||
          family.doc.listId != identity.listId ||
          floor < 2) {
        throw const FormatException();
      }
      return PreparedGeneration._(
        identity: identity,
        family: family,
        deviceKeys: await DeviceKeys.fromJson(
          Map<String, Object?>.from(json['deviceKeys'] as Map),
        ),
        commonFormatFloor: floor,
      );
    } on Object {
      throw const FormatException('prepared generation damaged');
    }
  }
}

/// Two (or more preserved branches of) complete local contexts. No generation
/// is pruned automatically; only [eraseAllConfirmed] deletes them. Use root
/// app stores. Public mutating operations
/// are serialized; the application must hold its family queue across network
/// work and invalidate/reload in-memory family state after activate/recover.
class GenerationStore {
  GenerationStore({required SecretStore secrets, required FileStore files})
    : _secrets = secrets,
      _files = files,
      journal = RenewalJournalStore(secrets: secrets, files: files),
      _queue = GenerationStorageQueue.on(secrets, 'generations');

  final SecretStore _secrets;
  final FileStore _files;
  final GenerationStorageQueue _queue;
  final RenewalJournalStore journal;
  final Map<String, GenerationContext> _contexts = {};

  GenerationContext _context(
    String syncId, {
    String? prefix,
    bool staging = false,
  }) => _contexts.putIfAbsent('$syncId/${prefix ?? "dynamic"}/$staging', () {
    final secrets = prefix == null
        ? GenerationSecretStore(_secrets, syncId: syncId)
        : GenerationSecretStore.pinned(
            _secrets,
            prefix,
            recoveryStaging: staging,
          );
    final keys = DeviceKeysStore(secrets);
    return GenerationContext._(
      syncId: syncId,
      deviceKeys: keys,
      family: FamilyStore(
        secrets: secrets,
        files: GenerationFileStore(_files, secrets),
        deviceKeys: keys,
      ),
    );
  });

  /// Register the installed v2 layout in place, without rewriting any data.
  /// This is the only legacy namespace; subsequent generations are isolated.
  Future<String> adoptCurrent() => _queue.run(_adoptCurrent);

  Future<String> _adoptCurrent() async {
    final existing = await GenerationDirectory.read(_secrets);
    if (existing != null) return existing.active;
    final keys = DeviceKeysStore(_secrets);
    final store = FamilyStore(
      secrets: _secrets,
      files: _files,
      deviceKeys: keys,
    );
    final identity = await store.readSyncV2();
    final family = await store.load();
    final install = await store.readPendingV2();
    if (install is Map && install['sid'] is String) {
      throw StateError('finish the pending generation installation first');
    }
    if (identity == null ||
        family == null ||
        await keys.read() == null ||
        await _files.read('family.doc') == null ||
        identity.listId != family.identity.listId ||
        identity.deviceId != family.identity.node) {
      throw StateError('no complete installed v2 generation');
    }
    await GenerationDirectory(
      active: identity.syncId,
      entries: {identity.syncId: (listId: identity.listId, legacy: true)},
    ).save(_secrets);
    return identity.syncId;
  }

  Future<String?> activeSyncId() async =>
      (await GenerationDirectory.read(_secrets))?.active;

  Future<Set<String>> generationIds({
    bool includeRecoveryRetained = true,
  }) async {
    final directory = await GenerationDirectory.read(_secrets);
    return {...?directory?.entries.keys}..removeAll(
      includeRecoveryRetained
          ? const <String>{}
          : directory?.recoveryRetained ?? {},
    );
  }

  Future<GenerationContext> open(String syncId) async {
    checkGenerationId(syncId);
    final directory = await GenerationDirectory.read(_secrets);
    if (directory?.entries.containsKey(syncId) != true) {
      throw StateError('generation not registered');
    }
    final entry = directory!.entries[syncId]!;
    return _context(
      syncId,
      prefix:
          directory.storagePrefixes[syncId] ??
          (entry.legacy ? '' : 'generation.$syncId.'),
    );
  }

  /// An unregistered context is invisible to active app stores. The operation
  /// id fixes its namespace across every crash and retry, even on an empty app.
  GenerationContext recoveryStaging(String operationId) {
    checkGenerationId(operationId);
    return _context(
      operationId,
      prefix: 'generation.$operationId.',
      staging: true,
    );
  }

  /// Isolated read workspace. The reader erases it in finally, on every path.
  GenerationContext recoveryReader(String syncId) {
    checkGenerationId(syncId);
    return _context(syncId, prefix: 'recovery.read.$syncId.', staging: true);
  }

  /// Capture under the family lock before discovery/claim. Existing v2 data is
  /// retained; a v1 family needs the explicit replacement flow, not an overwrite.
  Future<Map<String, Object?>> recoverySource({bool replaceExisting = false}) =>
      _queue.run(() async {
        var directory = await GenerationDirectory.read(_secrets);
        if (directory == null) {
          final family = FamilyStore(
            secrets: _secrets,
            files: _files,
            deviceKeys: DeviceKeysStore(_secrets),
          );
          final installed = await family.load();
          if (installed != null) {
            if (await family.readSyncV2() == null) {
              if (!replaceExisting) {
                throw const RecoverySourceException('existing_v1_family');
              }
              return {
                'active': null,
                'activation': 0,
                'replaceV1': true,
                'v1ListId': installed.identity.listId,
                'v1Node': installed.identity.node,
              };
            }
            await _adoptCurrent();
            directory = await GenerationDirectory.read(_secrets);
          }
        }
        return {
          'active': directory?.active,
          'activation': directory?.activation ?? 0,
        };
      });

  Future<GenerationContext?> recoveryLocal(String sid) async {
    final directory = await GenerationDirectory.read(_secrets);
    return directory?.entries.containsKey(sid) == true ? open(sid) : null;
  }

  Future<bool> isRecoveryActive(String operationId, String syncId) async {
    final directory = await GenerationDirectory.read(_secrets);
    return directory?.active == syncId &&
        directory?.storagePrefixes[syncId] == 'generation.$operationId.';
  }

  /// All bytes, keys and remoteSyncEnabled must already be durable. The single
  /// pointer write is the activation transaction; no copying into active files.
  /// An old copy of this same sid is retained under the operation's archive id.
  Future<void> activateRecovery({
    required String operationId,
    required String syncId,
    required Map<String, Object?> source,
  }) => _queue.run(() async {
    checkGenerationId(syncId);
    final prefix = 'generation.$operationId.';
    final directory = await GenerationDirectory.read(_secrets);
    if (directory?.active == syncId &&
        directory?.storagePrefixes[syncId] == prefix) {
      return;
    }
    if (directory?.active != source['active'] ||
        (directory?.activation ?? 0) != source['activation']) {
      throw const RecoverySourceException('different_family');
    }
    if (directory == null && source['replaceV1'] != true) {
      final root = FamilyStore(
        secrets: _secrets,
        files: _files,
        deviceKeys: DeviceKeysStore(_secrets),
      );
      if (await root.load() != null) {
        throw const RecoverySourceException('different_family');
      }
    }
    final staged = recoveryStaging(operationId);
    final family = await staged.family.load();
    final identity = await staged.family.readSyncV2();
    if (family == null ||
        identity?.syncId != syncId ||
        family.identity.listId != identity!.listId ||
        family.identity.node != identity.deviceId ||
        await staged.deviceKeys.read() == null ||
        await staged.family.readRegistry() == null ||
        !await staged.family.remoteSyncEnabled()) {
      throw const RecoverySourceException('incomplete_installation');
    }
    final entries = {...?directory?.entries};
    final prefixes = {...?directory?.storagePrefixes};
    final archives = {...?directory?.recoveryArchives};
    final retained = {...?directory?.recoveryRetained}..remove(syncId);
    if (directory != null && directory.active != syncId) {
      retained.add(directory.active);
    }
    if (entries.containsKey(syncId)) {
      if (entries.containsKey(operationId) || operationId == syncId) {
        throw const RecoverySourceException('recovery_namespace_conflict');
      }
      final previous = entries[syncId]!;
      // Only one legacy entry is allowed; its archive retains that property.
      entries[operationId] = previous;
      archives[operationId] = syncId;
      prefixes[operationId] =
          prefixes[syncId] ?? (previous.legacy ? '' : 'generation.$syncId.');
    }
    entries[syncId] = (listId: identity.listId, legacy: false);
    prefixes[syncId] = prefix;
    await GenerationDirectory(
      active: syncId,
      entries: entries,
      storagePrefixes: prefixes,
      recoveryArchives: archives,
      recoveryRetained: retained,
      activation: (directory?.activation ?? 0) + 1,
    ).save(_secrets);
  });

  /// Local reset after confirmed server retirement. Uses the same durable
  /// preparation as renewal, but never publishes or attests a remote transfer.
  Future<void> startLocalGeneration() => _queue.run(() async {
    var existing = await journal.read();
    if (existing != null && existing.data['localReset'] != true) {
      // The caller has confirmed remote retirement. That source can no longer
      // complete a renewal; retain its contexts and archive its reference before
      // preparing a local-only generation. A crash can resume either step.
      await journal.archive(existing.operationId);
      existing = null;
    }
    final sourceId = existing?.sourceSyncId ?? await _adoptCurrent();
    await _prepare(operationId: sourceId, localOnly: true);
    await _finishLocalGeneration((await journal.read())!);
  });

  Future<void> _finishLocalGeneration(RenewalJournal pending) async {
    final source = await open(pending.sourceSyncId);
    final target = await open(pending.destinationSyncId);
    for (final entry in (await source.family.readRecoveryScopes()).entries) {
      await target.family.saveScope(entry.key, entry.value);
    }
    await target.family.disableRemoteSync();
    await target.family.setRecoveryRemovalPending(false);
    await _switch(pending);
    await journal.archive(pending.operationId);
  }

  /// Prepare once before reserving remotely. Supplying destinationSyncId is
  /// useful for a mobile reconnecting to an already chosen destination.
  /// The approved checkpoint can then be installed in the returned context.
  /// A retry of the operation always uses the exact same prepared secrets.
  Future<PreparedGeneration> prepare({
    required String operationId,
    String? destinationSyncId,
  }) => _queue.run(
    () => _prepare(
      operationId: operationId,
      destinationSyncId: destinationSyncId,
    ),
  );

  /// A remote replace keeps its operation id and original source even when
  /// the active pointer already names a destination. Persist selection and
  /// fresh secrets atomically before installing; recover resumes that choice.
  Future<PreparedGeneration> prepareReplacement({
    required String operationId,
    required String destinationSyncId,
  }) => _queue.run(
    () => _prepare(
      operationId: operationId,
      destinationSyncId: destinationSyncId,
      replace: true,
    ),
  );

  Future<PreparedGeneration> _prepare({
    required String operationId,
    String? destinationSyncId,
    bool replace = false,
    bool localOnly = false,
  }) async {
    final adopted = await _adoptCurrent();
    var pending = await journal.read();
    final sourceId = pending?.sourceSyncId ?? adopted;
    if (pending != null) {
      if (pending.operationId != operationId) {
        throw StateError('another renewal is pending');
      }
      if (destinationSyncId == null ||
          pending.destinationSyncId == destinationSyncId) {
        final prepared = await _prepared(pending);
        if (pending.data['preparationInstalled'] != true) {
          await _installPreparation(pending);
        }
        return prepared;
      }
      if (!replace) throw StateError('another renewal is pending');
    } else if (replace) {
      throw StateError('no renewal to replace');
    }
    final source = _context(sourceId);
    final family = (await source.family.load())!;
    final sourceIdentity = (await source.family.readSyncV2())!;
    final floor = await source.family.readCommonFormatFloor();
    if (floor > 2) throw StateError('unsupported common format');
    final destination = destinationSyncId ?? SyncIdentityV2.newSyncId();
    checkGenerationId(destination);
    final directory = (await GenerationDirectory.read(_secrets))!;
    if (directory.entries.containsKey(destination)) {
      throw StateError('destination already exists');
    }
    final deviceId = encodeBase64Url(secureRandomBytes(16));
    final identity = SyncIdentityV2(
      listId: sourceIdentity.listId,
      deviceId: deviceId,
      syncId: destination,
    );
    final prepared = PreparedGeneration._(
      identity: identity,
      family: StoredFamily(
        identity: FamilyIdentity(
          listId: identity.listId,
          node: deviceId,
          deviceName: family.identity.deviceName,
          selfRecipientId: family.identity.selfRecipientId,
        ),
        key: await FamilyKey.generate(),
        doc: family.doc,
      ),
      deviceKeys: await DeviceKeys.generate(),
      commonFormatFloor: 2,
    );
    final previous = pending;
    pending = RenewalJournal(
      operationId: operationId,
      sourceSyncId: sourceId,
      destinationSyncId: destination,
      phase: 'preparation',
      revision: previous == null ? 0 : previous.revision + 1,
      data: {
        if (localOnly) 'localReset': true,
        'preparedGeneration': prepared.toJson(),
        'preparationInstalled': false,
        if (previous != null) ...{
          'operationContext':
              previous.data['operationContext'] ?? <String, Object?>{},
          'previousPreparations': {
            ...?previous.data['previousPreparations'] as Map?,
            previous.destinationSyncId: {
              for (final e in previous.data.entries)
                if (e.key != 'previousPreparations' &&
                    e.key != 'operationContext')
                  e.key: e.value,
            },
          },
        },
        if (previous != null)
          'previousDestinations': [
            ...?previous.data['previousDestinations'] as List?,
            previous.destinationSyncId,
          ],
      },
    );
    // The complete preparation is one encrypted atomic write, before either
    // the destination directory entry or any destination data is written.
    if (previous == null) {
      await journal.save(pending);
    } else {
      await journal.replaceDestination(pending);
    }
    await _installPreparation(pending);
    return prepared;
  }

  Future<PreparedGeneration> _prepared(RenewalJournal pending) async {
    final prepared = await PreparedGeneration.fromJson(
      pending.data['preparedGeneration'],
    );
    if (prepared.identity.syncId != pending.destinationSyncId) {
      throw StateError('destination substitution');
    }
    final source = _context(pending.sourceSyncId);
    final sourceKeys = await source.deviceKeys.read();
    final sourceIdentity = await source.family.readSyncV2();
    final sourceFamily = await source.family.load();
    if (sourceKeys == null ||
        sourceIdentity == null ||
        sourceFamily == null ||
        sourceIdentity.syncId != pending.sourceSyncId ||
        sourceIdentity.listId != prepared.identity.listId ||
        sourceIdentity.deviceId == prepared.identity.deviceId ||
        constantTimeEquals(
          sourceKeys.publicKeys.signing,
          prepared.deviceKeys.publicKeys.signing,
        ) ||
        constantTimeEquals(
          sourceKeys.publicKeys.agreement,
          prepared.deviceKeys.publicKeys.agreement,
        ) ||
        constantTimeEquals(
          sourceKeys.serviceCredential,
          prepared.deviceKeys.serviceCredential,
        ) ||
        sourceFamily.key.toBase64Url() == prepared.family.key.toBase64Url()) {
      throw StateError('renewal must use independent identities and secrets');
    }
    return prepared;
  }

  Future<void> _installPreparation(RenewalJournal pending) async {
    final prepared = await _prepared(pending);
    final directory = (await GenerationDirectory.read(_secrets))!;
    final destination = prepared.identity.syncId;
    final entry = directory.entries[destination];
    if (entry != null &&
        (entry.legacy || entry.listId != prepared.identity.listId)) {
      throw StateError('destination namespace conflict');
    }
    if (entry == null) {
      await GenerationDirectory(
        active: directory.active,
        activation: directory.activation,
        storagePrefixes: directory.storagePrefixes,
        recoveryArchives: directory.recoveryArchives,
        recoveryRetained: directory.recoveryRetained,
        entries: {
          ...directory.entries,
          destination: (listId: prepared.identity.listId, legacy: false),
        },
      ).save(_secrets);
    }
    final target = _context(destination);
    await target.deviceKeys.restore(prepared.deviceKeys);
    await target.deviceKeys.purgePerson(
      prepared.family.identity.selfRecipientId,
    );
    final own = await DeviceRecord.create(
      keys: prepared.deviceKeys,
      listId: prepared.identity.listId,
      deviceId: prepared.identity.deviceId,
      personId: prepared.family.identity.selfRecipientId,
    );
    await target.family.saveRegistry(
      await DeviceRegistry.empty(own.listId).withRecord(own),
    );
    await target.family.saveFamily(prepared.family);
    await target.family.raiseCommonFormatFloor(prepared.commonFormatFloor);
    await target.family.saveSyncV2(prepared.identity);
    await journal.save(
      pending.next(
        phase: 'prepared',
        data: {...pending.data, 'preparationInstalled': true},
      ),
    );
  }

  Future<void> _validateDestination(RenewalJournal pending) async {
    final prepared = await _prepared(pending);
    final target = _context(pending.destinationSyncId);
    final family = await target.family.load();
    final identity = await target.family.readSyncV2();
    final keys = await target.deviceKeys.read();
    final registry = await target.family.readRegistry();
    final commonKeys = await target.family.readCommonKeys();
    if (family == null ||
        identity == null ||
        keys == null ||
        registry == null ||
        identity.syncId != prepared.identity.syncId ||
        identity.deviceId != prepared.identity.deviceId ||
        family.identity.node != identity.deviceId ||
        family.identity.listId != identity.listId ||
        jsonEncode(keys.toJson()) != jsonEncode(prepared.deviceKeys.toJson()) ||
        await target.family.readCommonFormatFloor() !=
            prepared.commonFormatFloor ||
        commonKeys is! Map ||
        !await target.family.commonKeysMarked()) {
      throw StateError('destination context is incomplete');
    }
    final keyring = FamilyKeyring.fromJson(commonKeys['k']);
    if (commonKeys['v'] != 1 ||
        commonKeys['c'] is! String ||
        keyring.entry(commonKeys['c'] as String) == null ||
        keyring.candidates.any(
          (c) => c.syncId != identity.syncId || c.listId != identity.listId,
        )) {
      throw StateError(
        'common keys belong to another generation or are missing',
      );
    }
    final view = await registry.viewFor(
      me: identity.deviceId,
      mySigningKey: keys.publicKeys.signing,
      livePeople: {
        for (final person
            in (family.doc.collections[Collections.recipients] ?? const {})
                .values)
          if (!person.isDeleted) person.id,
      },
    );
    if (view.member(identity.deviceId) == null ||
        !view.selfApproved ||
        view.revokedByOthers) {
      throw StateError('destination identity is not active');
    }
  }

  /// The engine sets data.destinationReady=true only after it has verified
  /// full publication (pairing alone is insufficient). Persist the activation
  /// intent first, validate the durable context, then change the pointer last.
  /// This method does not attest transfer, issue a receipt or retire the source.
  Future<void> activate(String operationId) => _queue.run(() async {
    var pending = await journal.read();
    if (pending == null ||
        pending.operationId != operationId ||
        pending.data['destinationReady'] != true) {
      throw StateError('destination publication not confirmed');
    }
    await _validateDestination(pending);
    if (pending.data['activationPrepared'] != true) {
      pending = pending.next(
        phase: pending.phase,
        data: {...pending.data, 'activationPrepared': true},
      );
      await journal.save(pending);
    }
    await _switch(pending);
  });

  Future<void> _switch(RenewalJournal pending) async {
    final directory = (await GenerationDirectory.read(_secrets))!;
    if (directory.active == pending.destinationSyncId) return;
    if ((directory.active != pending.sourceSyncId &&
            !(pending.data['previousDestinations'] as List? ?? []).contains(
              directory.active,
            )) ||
        !directory.entries.containsKey(pending.destinationSyncId)) {
      throw StateError('active generation conflict');
    }
    await GenerationDirectory(
      active: pending.destinationSyncId,
      entries: directory.entries,
      activation: directory.activation + 1,
      storagePrefixes: directory.storagePrefixes,
      recoveryArchives: directory.recoveryArchives,
      recoveryRetained: {
        ...directory.recoveryRetained,
        // The retired source and any abandoned renewal preparations remain
        // local history, not pending transitions blocking a new recovery code.
        if (pending.data['localReset'] == true)
          ...directory.entries.keys.where(
            (id) => id != pending.destinationSyncId,
          ),
      },
    ).save(_secrets);
  }

  /// Only for the user's confirmed Erase All action, never for Gone/reset.
  /// The caller must stop edits/sync and hold the family queue. Call this
  /// before resetting the family controller or sweeping secure storage.
  ///
  /// Save a deletion inventory (filenames/secret names, no key material)
  /// before deleting data. Keep it until all generations, journal and keys
  /// are gone. Retrying, including after a secure-store sweep, is idempotent.
  Future<void> eraseAllConfirmed() => _queue.run(
    () => GenerationStorageQueue.on(
      _secrets,
      'renewalJournal',
    ).run(_eraseAllConfirmed),
  );

  Future<void> _eraseAllConfirmed() async {
    try {
      final marker = await _files.read(_confirmedEraseFile);
      if (marker != null &&
          (jsonDecode(utf8.decode(marker)) as Map)['v'] == 2) {
        await _eraseByListing();
        return;
      }
      await _eraseInventoried();
    } on FormatException {
      await _eraseByListing();
    } on FamilyStoreException {
      await _eraseByListing();
    } on TypeError {
      await _eraseByListing();
    }
  }

  Future<void> _eraseByListing() async {
    // Consent survives both a secure-store sweep and a process interruption.
    await _files.writeAtomic(
      _confirmedEraseFile,
      Uint8List.fromList(utf8.encode('{"v":2}')),
    );
    if (_secrets is! ErasableSecretStore || _files is! ListableFileStore) {
      throw StateError(
        'confirmed erase requires secret wipe and directory listing',
      );
    }
    await _secrets.eraseAllSecrets();
    for (final name in await _files.listNames()) {
      if (name != _confirmedEraseFile &&
          (name.startsWith('generation.') ||
              name.startsWith('family.') ||
              name.startsWith('recovery.read.') ||
              name.startsWith('device.'))) {
        await _files.delete(name);
      }
    }
    _contexts.clear();
    await _files.delete(_confirmedEraseFile);
  }

  Future<void> _eraseInventoried() async {
    var inventory = await _files.read(_confirmedEraseFile);
    if (inventory == null) {
      final directory = await GenerationDirectory.read(_secrets);
      final secrets = <String>{renewalJournalEncryptionKey, recoveryJournalKey};
      final files = <String>{renewalJournalFile, recoveryJournalFile};
      final families = [
        // Also covers installations that have not adopted a generation yet.
        FamilyStore(
          secrets: _secrets,
          files: _files,
          deviceKeys: DeviceKeysStore(_secrets),
        ),
        for (final id in directory?.entries.keys ?? <String>[])
          _context(id).family,
      ];
      for (final family in families) {
        final entries = await family.confirmedEraseInventory();
        secrets.addAll(entries.secrets);
        files.addAll(entries.files);
      }
      if (_files is ListableFileStore) {
        files.addAll(
          (await _files.listNames()).where(
            (name) =>
                name != _confirmedEraseFile &&
                (name.startsWith('generation.') ||
                    name.startsWith('family.') ||
                    name.startsWith('recovery.read.') ||
                    name.startsWith('device.')),
          ),
        );
      }
      inventory = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'v': 1,
            'secrets': secrets.toList()..sort(),
            'files': files.toList()..sort(),
          }),
        ),
      );
      await _files.writeAtomic(_confirmedEraseFile, inventory);
    }
    final json = jsonDecode(utf8.decode(inventory)) as Map;
    if (json['v'] != 1) {
      throw const FormatException('confirmed erase inventory damaged');
    }
    final files = (json['files'] as List).cast<String>();
    final secrets = (json['secrets'] as List).cast<String>();
    final namePattern = RegExp(
      r'^((generation|recovery\.read)\.[A-Za-z0-9_-]{22}\.)?(family|device)\.[A-Za-z0-9_.-]+$',
    );
    if ([...files, ...secrets].any((name) => !namePattern.hasMatch(name)) ||
        files.contains(_confirmedEraseFile) ||
        secrets.contains(generationDirectoryKey)) {
      throw const FormatException('confirmed erase inventory damaged');
    }
    // A valid directory can still omit a generation. Its file names may be
    // discoverable while its secret names are absent from this inventory.
    // The durable intent authorizes wiping the entire application secret store.
    if (_secrets is! ErasableSecretStore) {
      throw StateError('confirmed erase requires secret wipe');
    }
    await _secrets.eraseAllSecrets();
    for (final file in files) {
      await _files.delete(file);
    }
    for (final secret in secrets) {
      await _secrets.delete(secret);
    }
    // Keep the directory until no generation data needs locating any more.
    await _secrets.delete(generationDirectoryKey);
    _contexts.clear();
    await _files.delete(_confirmedEraseFile);
  }

  /// Call before Gone/reset handling and before exposing an editable family.
  /// Replays preparation or a committed activation intent using the same keys.
  /// Other phases are returned untouched for the renewal engine to resume.
  Future<RenewalJournal?> recover() => _queue.run(() async {
    // A durable inventory is already the user's consent. Finish it before
    // opening any partially erased context or attempting journal recovery.
    if (await _files.read(_confirmedEraseFile) != null) {
      await GenerationStorageQueue.on(
        _secrets,
        'renewalJournal',
      ).run(_eraseAllConfirmed);
      return null;
    }
    final pending = await journal.read();
    if (pending == null) return null;
    await _prepared(pending);
    if (pending.data['preparationInstalled'] != true) {
      await _installPreparation(pending);
    }
    if (pending.data['localReset'] == true) {
      await _finishLocalGeneration((await journal.read())!);
      return null;
    }
    if (pending.data['activationPrepared'] == true) {
      if (pending.data['destinationReady'] != true) {
        throw StateError('invalid activation intent');
      }
      await _validateDestination(pending);
      await _switch(pending);
    }
    return journal.read();
  });
}

final generationStoreProvider = Provider<GenerationStore>(
  (ref) => GenerationStore(
    secrets: ref.watch(secretStoreProvider),
    files: ref.watch(fileStoreProvider),
  ),
);
