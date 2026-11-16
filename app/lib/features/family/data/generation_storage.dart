import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'storage.dart';

/// One atomic secure-store record selects the active namespace. The original
/// generation keeps its existing filenames; adopting it never copies secrets.
const generationDirectoryKey = 'family.generations';
const renewalJournalEncryptionKey = 'family.renewalJournalKey';

void checkGenerationId(String id) {
  if (!RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(id)) {
    throw const FormatException('invalid generation id');
  }
}

/// Only durable recovery material triggers an update. Ordinary document,
/// slot and transport counters are reconstructed by a full authenticated read.
Object? recoverySecretMaterial(String key, String? value) {
  if (value == null) return null;
  if (key == 'family.syncV2State') {
    final j = Map<String, Object?>.from(jsonDecode(value) as Map);
    return {
      for (final k in ['km', 'r', 'ur', 'ro', 'o', 'cf', 'cm', 'cmp', 'm'])
        if (j.containsKey(k)) k: j[k],
    };
  }
  return value;
}

bool isRecoveryMaterialSecret(String key) => const {
  'device.keys',
  'device.surpriseKeys',
  'family.key',
  'family.identity',
  'family.syncV2',
  'family.syncV2State',
  'family.commonKeysMarker',
  'family.commonFormatFloor',
  'family.v1ProofKey',
  'family.legacyV1',
  'family.pendingV2',
  'family.selfPersonChange',
}.contains(key);

/// Local directory, deliberately independent of the renewal wire protocol.
class GenerationDirectory {
  GenerationDirectory({
    required this.active,
    required this.entries,
    this.activation = 0,
    this.storagePrefixes = const {},
    this.recoveryArchives = const {},
    this.recoveryRetained = const {},
  });

  final String active;
  final int activation;

  /// Recovery installs into an independent namespace, then selects it atomically.
  final Map<String, String> storagePrefixes;

  /// Archive alias -> original syncId. These preserve a previous installation
  /// of the same generation; they do not imply a pending renewal journal.
  final Map<String, String> recoveryArchives;

  /// Families explicitly replaced by recovery are retained local data, not
  /// unfinished renewal destinations. They never block the active engine.
  final Set<String> recoveryRetained;

  /// syncId -> {listId, legacy}. Entries are never removed automatically.
  final Map<String, ({String listId, bool legacy})> entries;

  static Future<GenerationDirectory?> read(SecretStore secrets) async {
    final raw = await secrets.read(generationDirectoryKey);
    if (raw == null) {
      if (await secrets.read(renewalJournalEncryptionKey) != null) {
        throw const FormatException('generation directory missing');
      }
      return null;
    }
    try {
      final json = jsonDecode(raw) as Map;
      if (json['v'] != 1) throw const FormatException();
      final active = json['active'] as String;
      final entries = <String, ({String listId, bool legacy})>{};
      for (final e in (json['entries'] as Map).entries) {
        final id = e.key as String;
        checkGenerationId(id);
        final value = e.value as Map;
        final listId = value['listId'] as String;
        if (listId.isEmpty || value['legacy'] is! bool) {
          throw const FormatException();
        }
        entries[id] = (listId: listId, legacy: value['legacy'] as bool);
      }
      if (!entries.containsKey(active) ||
          entries.values.where((e) => e.legacy).length > 1) {
        throw const FormatException();
      }
      final activation = json['activation'] ?? 0;
      if (activation is! int || activation < 0) throw const FormatException();
      final prefixes = Map<String, String>.from(
        json['storagePrefixes'] as Map? ?? {},
      );
      for (final e in prefixes.entries) {
        if (!entries.containsKey(e.key) ||
            (e.value.isNotEmpty &&
                !RegExp(r'^generation\.[A-Za-z0-9_-]{22}\.$')
                    .hasMatch(e.value))) {
          throw const FormatException();
        }
      }
      final archives = Map<String, String>.from(
        json['recoveryArchives'] as Map? ?? {},
      );
      final retained = (json['recoveryRetained'] as List? ?? [])
          .cast<String>()
          .toSet();
      if (retained.contains(active) ||
          !entries.keys.toSet().containsAll(retained)) {
        throw const FormatException();
      }
      for (final e in archives.entries) {
        if (e.key == active ||
            e.key == e.value ||
            !entries.containsKey(e.key) ||
            !entries.containsKey(e.value) ||
            entries[e.key]!.listId != entries[e.value]!.listId ||
            archives.containsKey(e.value)) {
          throw const FormatException();
        }
      }
      return GenerationDirectory(
        active: active,
        entries: entries,
        activation: activation,
        storagePrefixes: prefixes,
        recoveryArchives: archives,
        recoveryRetained: retained,
      );
    } on Object {
      // A corrupt directory must never fall back to the old global files.
      throw const FormatException('generation directory damaged');
    }
  }

  Future<void> save(SecretStore secrets) => secrets.write(
    generationDirectoryKey,
    jsonEncode({
      'v': 1,
      'active': active,
      'activation': activation,
      'storagePrefixes': storagePrefixes,
      'recoveryArchives': recoveryArchives,
      'recoveryRetained': recoveryRetained.toList()..sort(),
      'entries': {
        for (final e in entries.entries)
          e.key: {'listId': e.value.listId, 'legacy': e.value.legacy},
      },
    }),
  );
}

/// Shared in-process queues, including across reconstructed store instances.
/// Callers also hold the family/controller lock across installation and edits.
class GenerationStorageQueue {
  static final _queues = Expando<Map<String, GenerationStorageQueue>>();
  // Idle queues must not create or retain futures tied to another zone
  // (for example, across nested startup work or provider reconstruction).
  Future<void>? _tail;

  static GenerationStorageQueue on(SecretStore secrets, String name) {
    final root = secrets is GenerationSecretStore ? secrets.root : secrets;
    return (_queues[root] ??= {})[name] ??= GenerationStorageQueue();
  }

  Future<T> run<T>(Future<T> Function() task) {
    final previous = _tail;
    final result = previous == null
        ? Future<T>.microtask(task)
        : previous.then((_) => task());
    late final Future<void> tail;
    void release() {
      if (identical(_tail, tail)) _tail = null;
    }

    tail = result.then<void>(
      (_) => release(),
      onError: (Object _) => release(),
    );
    _tail = tail;
    return result;
  }
}

/// null selects the active generation dynamically; a syncId pins a handle.
/// [inGeneration] pins the selector throughout a compound operation.
/// Without a directory the active handle reads the unchanged legacy layout.
class GenerationSecretStore implements SecretStore {
  GenerationSecretStore(this.root, {this.syncId}) : recoveryStaging = false {
    if (syncId != null) checkGenerationId(syncId!);
  }

  GenerationSecretStore.pinned(
    this.root,
    String prefix, {
    this.recoveryStaging = false,
  }) : syncId = null,
       _fixedPrefix = prefix;

  final bool recoveryStaging;
  bool get fixedNamespace => _fixedPrefix != null;

  final SecretStore root;
  final String? syncId;
  String? _fixedPrefix;

  static final _operationPrefixes = Object();

  /// Pin one namespace for an entire operation, including nested calls and
  /// other active handles on the same root store. Zones isolate concurrent
  /// operations; explicit generation handles keep their own namespace.
  Future<T> inGeneration<T>(Future<T> Function() task) async {
    final key = (root, _fixedPrefix ?? syncId);
    final prefixes =
        Zone.current[_operationPrefixes]
            as Map<(SecretStore, String?), String>? ??
        {};
    if (prefixes.containsKey(key)) return task();
    final selected = await prefix();
    return runZoned(
      task,
      zoneValues: {
        _operationPrefixes: {...prefixes, key: selected},
      },
    );
  }

  static SecretStore active(SecretStore secrets) =>
      secrets is GenerationSecretStore
      ? secrets
      : GenerationSecretStore(secrets);

  Future<bool> get managed async =>
      _fixedPrefix != null || await GenerationDirectory.read(root) != null;

  Future<String> prefix() async {
    if (_fixedPrefix != null) return _fixedPrefix!;
    final prefixes =
        Zone.current[_operationPrefixes]
            as Map<(SecretStore, String?), String>?;
    final pinned = prefixes?[(root, syncId)];
    if (pinned != null) return pinned;
    final directory = await GenerationDirectory.read(root);
    if (directory == null && syncId == null) return '';
    final id = syncId ?? directory?.active;
    final entry = directory?.entries[id];
    if (id == null || entry == null) {
      throw const FormatException('generation not registered');
    }
    return directory!.storagePrefixes[id] ??
        (entry.legacy ? '' : 'generation.$id.');
  }

  @override
  Future<String?> read(String key) async => root.read('${await prefix()}$key');

  /// Checked when queued work actually executes, including writes through old
  /// handles. Reads remain available to a transferred installation.
  Future<void> assertWritable() async {
    if (!recoveryStaging &&
        await root.read('family.recoveryRestoring') == 'true') {
      throw StateError('recovery_in_progress');
    }
    final selected = await prefix();
    if (await root.read('${selected}family.transferred') == 'true') {
      throw StateError('transferred');
    }
  }

  @override
  Future<void> write(String key, String value) async {
    await assertWritable();
    if (isRecoveryMaterialSecret(key) &&
        jsonEncode(recoverySecretMaterial(key, await read(key))) !=
            jsonEncode(recoverySecretMaterial(key, value))) {
      await markRecoveryDirty();
    }
    await root.write('${await prefix()}$key', value);
  }

  /// Persist intent before changing recovery material, including queued writes.
  Future<void> markRecoveryDirty() async {
    final selected = await prefix();
    if (await root.read('${selected}family.recoveryConfigured') != 'true') {
      return;
    }
    await root.write(
      '${selected}family.recoveryDirty',
      '${DateTime.now().microsecondsSinceEpoch}:${Random.secure().nextInt(1 << 32)}',
    );
  }

  @override
  Future<void> delete(String key) async {
    await assertWritable();
    if (isRecoveryMaterialSecret(key) && await read(key) != null) {
      await markRecoveryDirty();
    }
    await root.delete('${await prefix()}$key');
  }
}

/// Files and secrets resolve through the same namespace selector. Local AES
/// keys are independent, so ciphertext copied across generations fails to open.
class GenerationFileStore implements FileStore {
  GenerationFileStore(this.root, this.secrets);
  final FileStore root;
  final GenerationSecretStore secrets;

  static FileStore active(FileStore files, SecretStore secrets) =>
      files is GenerationFileStore
      ? files
      : GenerationFileStore(
          files,
          GenerationSecretStore.active(secrets) as GenerationSecretStore,
        );

  @override
  Future<Uint8List?> read(String name) async =>
      root.read('${await secrets.prefix()}$name');
  @override
  Future<void> writeAtomic(String name, Uint8List bytes) async {
    await secrets.assertWritable();
    await root.writeAtomic('${await secrets.prefix()}$name', bytes);
  }

  @override
  Future<void> delete(String name) async {
    await secrets.assertWritable();
    await root.delete('${await secrets.prefix()}$name');
  }
}
