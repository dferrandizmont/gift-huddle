import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/device_keys.dart';
import '../../../core/sync/envelope.dart';
import 'generation_storage.dart';
import 'storage.dart';
import 'storage_providers.dart';

const recoveryJournalFile = 'family.recoveryJournal';
const recoveryJournalKey = 'family.recoveryJournalKey';
final _aad = utf8.encode('gift-huddle-recovery-journal-v1');

enum RecoveryPhase {
  locating,
  located,
  verified,
  claimPrepared,
  claimConfirmed,
  downloading,
  installPrepared,
  active,
  needsAttention,
}

enum RecoveryMaintenanceKind { create, update, rotate, retire }

/// Contains secrets and exact requests. Never log or export this record.
/// Progress and staging are preserved on incomplete/unsupported recovery.
class RecoveryJournal {
  RecoveryJournal({
    required this.operationId,
    required this.phase,
    required Map<String, Object?> data,
  }) : data = Map.unmodifiable(_copy(data)) {
    checkGenerationId(operationId);
  }

  final String operationId;
  final RecoveryPhase phase;
  final Map<String, Object?> data;

  /// True once the claim may have reached the service, including lost replies.
  bool get claimSent => data['claimSent'] == true;

  RecoveryJournal next(
    RecoveryPhase phase, [
    Map<String, Object?> data = const {},
  ]) => RecoveryJournal(
    operationId: operationId,
    phase: phase,
    data: {...this.data, ...data},
  );

  Map<String, Object?> toJson() => {
    'v': 1,
    'operationId': operationId,
    'phase': phase.name,
    'data': data,
  };

  factory RecoveryJournal.fromJson(Object? raw) {
    final j = raw as Map;
    if (j['v'] != 1) {
      throw const FormatException('unsupported recovery journal');
    }
    return RecoveryJournal(
      operationId: j['operationId'] as String,
      phase: RecoveryPhase.values.byName(j['phase'] as String),
      data: Map<String, Object?>.from(j['data'] as Map),
    );
  }
}

Map<String, Object?> _copy(Object? value) =>
    Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);

/// Root storage, independent of the active family and generation. One atomic
/// encrypted write contains each intention, its exact body/CAS and receipt.
/// The secure-store encryption key is created before the first file write.
class RecoveryStore {
  RecoveryStore({required SecretStore secrets, required FileStore files})
    : _secrets = secrets,
      _files = files,
      _queue = GenerationStorageQueue.on(secrets, 'recoveryJournal') {
    if (secrets is GenerationSecretStore || files is GenerationFileStore) {
      throw ArgumentError('recovery journal requires root stores');
    }
  }

  final SecretStore _secrets;
  final FileStore _files;
  final GenerationStorageQueue _queue;
  final _aes = AesGcm.with256bits();

  Future<Map<String, Object?>> _read() async {
    final bytes = await _files.read(recoveryJournalFile);
    if (bytes == null) {
      return {
        'v': 1,
        'restore': null,
        'maintenance': {},
        'material': {},
        'transferred': {},
      };
    }
    try {
      final key = await _secrets.read(recoveryJournalKey);
      if (key == null || bytes.length < 29 || bytes[0] != 1) {
        throw const FormatException();
      }
      final plain = await _aes.decrypt(
        SecretBox(
          bytes.sublist(13, bytes.length - 16),
          nonce: bytes.sublist(1, 13),
          mac: Mac(bytes.sublist(bytes.length - 16)),
        ),
        secretKey: SecretKey(decodeBase64Url(key)),
        aad: _aad,
      );
      final j = _copy(jsonDecode(utf8.decode(plain)));
      if (j['v'] != 1 ||
          j['maintenance'] is! Map ||
          j['material'] is! Map ||
          j['transferred'] is! Map) {
        throw const FormatException();
      }
      if (j['restore'] != null) RecoveryJournal.fromJson(j['restore']);
      return j;
    } on Object {
      // Lost local encryption material must not brick startup. Discard the
      // unreadable intention before releasing its gate; remote codes survive.
      await _files.delete(recoveryJournalFile);
      await _secrets.delete(recoveryJournalKey);
      await _secrets.delete('family.recoveryRestoring');
      return _read();
    }
  }

  Future<void> _write(Map<String, Object?> value) async {
    var key = await _secrets.read(recoveryJournalKey);
    if (key == null) {
      key = encodeBase64Url(secureRandomBytes(32));
      await _secrets.write(recoveryJournalKey, key);
    }
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode(value)),
      secretKey: SecretKey(decodeBase64Url(key)),
      aad: _aad,
    );
    await _files.writeAtomic(
      recoveryJournalFile,
      Uint8List.fromList([
        1,
        ...box.nonce,
        ...box.cipherText,
        ...box.mac.bytes,
      ]),
    );
  }

  Future<RecoveryJournal?> readRestore() => _queue.run(() async {
    final j = (await _read())['restore'];
    return j == null ? null : RecoveryJournal.fromJson(j);
  });

  Future<void> saveRestore(RecoveryJournal journal) => _queue.run(() async {
    final j = await _read();
    final old = j['restore'] == null
        ? null
        : RecoveryJournal.fromJson(j['restore']);
    if (old != null &&
        old.phase != RecoveryPhase.active &&
        old.operationId != journal.operationId) {
      throw StateError('another recovery must be resolved first');
    }
    j['restore'] = journal.toJson();
    if (journal.phase == RecoveryPhase.claimPrepared) {
      await _secrets.write('family.recoveryRestoring', 'true');
    }
    await _write(j);
  });

  /// Caller holds the family lock and has erased unselected staging first.
  Future<void> abandonRestore() => _queue.run(() async {
    final j = await _read();
    j['restore'] = null;
    await _write(j);
    await _secrets.delete('family.recoveryRestoring');
  });

  /// A claimant superseded during read validation needs a fresh claim receipt.
  Future<void> restartRestore(RecoveryJournal expected, RecoveryJournal next) =>
      _queue.run(() async {
        final j = await _read();
        final old = RecoveryJournal.fromJson(j['restore']);
        if (old.operationId != expected.operationId ||
            old.phase == RecoveryPhase.active) {
          throw StateError('recovery changed');
        }
        j['restore'] = next.toJson();
        await _write(j);
      });

  /// For 5.4: prepare before create/update/rotation/DELETE, with exact request,
  /// source generation, entropy, old/new material, CAS and operation id. The
  /// caller holds the family lock; finishing never discards maintenance keys.
  Future<void> prepareMaintenance(
    String sid,
    RecoveryMaintenanceKind kind,
    Map<String, Object?> exactIntent,
  ) => _queue.run(() async {
    checkGenerationId(sid);
    final j = await _read();
    if (await _isTransferred(sid)) {
      throw StateError('transferred');
    }
    final intents = j['maintenance'] as Map;
    final next = {'kind': kind.name, 'intent': _copy(exactIntent)};
    if (intents[sid] != null && jsonEncode(intents[sid]) != jsonEncode(next)) {
      throw StateError('maintenance already pending');
    }
    intents[sid] = next;
    (j['failures'] as Map?)?.remove(sid);
    if (kind == RecoveryMaintenanceKind.create ||
        kind == RecoveryMaintenanceKind.rotate) {
      final displays = j['displays'] as Map? ?? <String, Object?>{};
      displays[sid] = exactIntent['entropy'];
      j['displays'] = displays;
    }
    await _write(j);
  });

  Future<Map<String, Object?>?> readMaintenance(String sid) =>
      _queue.run(() async {
        final value = ((await _read())['maintenance'] as Map)[sid];
        return value == null ? null : _copy(value);
      });

  /// 5.4 advances a prepared operation under the family lock. A compare on the
  /// entire previous record prevents a resumed task from replacing newer work.
  /// Persist the next exact request/phase before its dependent network call.
  Future<void> advanceMaintenance(
    String sid,
    Map<String, Object?> expected,
    Map<String, Object?> exactIntent,
  ) => _queue.run(() async {
    final j = await _read();
    if (await _isTransferred(sid)) {
      throw StateError('transferred');
    }
    final intents = j['maintenance'] as Map;
    if (jsonEncode(intents[sid]) != jsonEncode(expected)) {
      throw StateError('maintenance changed');
    }
    intents[sid] = {'kind': expected['kind'], 'intent': _copy(exactIntent)};
    await _write(j);
  });

  /// A person change invalidates any older maintenance. Preserve its exact
  /// request as evidence while giving confirmed remote retirement priority.
  Future<void> supersedeWithRetirement(
    String sid,
    Map<String, Object?> intent,
  ) => _queue.run(() async {
    final j = await _read();
    final intents = j['maintenance'] as Map;
    intents[sid] = {
      'kind': RecoveryMaintenanceKind.retire.name,
      'intent': {..._copy(intent), 'superseded': intents[sid]},
    };
    await _write(j);
  });

  Future<Map<String, Object?>?> readMaterial(String sid) =>
      _queue.run(() async {
        final value = ((await _read())['material'] as Map)[sid];
        return value == null ? null : _copy(value);
      });

  Future<void> finishMaintenance(String sid, Map<String, Object?> material) =>
      _queue.run(() async {
        final j = await _read();
        if (await _isTransferred(sid)) {
          throw StateError('transferred');
        }
        final previous = (j['material'] as Map)[sid] as Map?;
        (j['material'] as Map)[sid] = {
          ..._copy(material),
          if (material['entropy'] != null &&
              material['entropy'] == previous?['entropy'] &&
              previous!.containsKey('wordsConfirmed'))
            'wordsConfirmed': previous['wordsConfirmed'],
        };
        if (material['retired'] == true) (j['displays'] as Map?)?.remove(sid);
        (j['maintenance'] as Map).remove(sid);
        (j['failures'] as Map?)?.remove(sid);
        await _write(j);
      });

  Future<String?> readFailure(String sid) => _queue.run(
    () async => ((await _read())['failures'] as Map?)?[sid] as String?,
  );

  /// Dismiss only a closed operation; a pending intent must be resolved first.
  Future<void> dismissFailure(String sid) => _queue.run(() async {
    final j = await _read();
    if ((j['maintenance'] as Map)[sid] != null) {
      throw StateError('maintenance already pending');
    }
    (j['failures'] as Map?)?.remove(sid);
    await _write(j);
  });

  /// Terminal operations cannot be replayed. Keep the previous active entropy
  /// on a cancelled/expired rotation and release the intention for a new code.
  /// A null cause closes a user cancellation without leaving an error.
  Future<void> closeMaintenance(
    String sid,
    String? cause, {
    bool retired = false,
  }) => _queue.run(() async {
    final j = await _read();
    final record = (j['maintenance'] as Map).remove(sid) as Map?;
    final old = (record?['intent'] as Map?)?['old'] as Map?;
    if (retired) {
      (j['material'] as Map)[sid] = {'retired': true};
    } else if (old != null) {
      final current = (j['material'] as Map)[sid] as Map?;
      (j['material'] as Map)[sid] = {
        ..._copy(old),
        if (old['entropy'] == current?['entropy'] &&
            current?['wordsConfirmed'] == true)
          'wordsConfirmed': true,
      };
    }
    (j['displays'] as Map?)?.remove(sid);
    final failures = j['failures'] as Map? ?? <String, Object?>{};
    if (cause == null || cause == 'maintenance_cancelled') {
      failures.remove(sid);
    } else {
      failures[sid] = cause;
    }
    j['failures'] = failures;
    await _write(j);
  });

  Future<String?> _installedPrefix(String sid) async {
    checkGenerationId(sid);
    final directory = await GenerationDirectory.read(_secrets);
    if (directory != null && !directory.entries.containsKey(sid)) return null;
    final scoped = GenerationSecretStore(
      _secrets,
      syncId: directory == null ? null : sid,
    );
    final raw = await scoped.read('family.syncV2');
    if (raw == null || (jsonDecode(raw) as Map)['sid'] != sid) return null;
    return scoped.prefix();
  }

  Future<bool> _isTransferred(String sid) async {
    final prefix = await _installedPrefix(sid);
    return prefix != null &&
        await _secrets.read('${prefix}family.transferred') == 'true';
  }

  /// The mark belongs to the retired installation, never the recovered sid.
  /// A new claim installs a fresh namespace and leaves old handles read-only.
  Future<void> markTransferred(String sid) => _queue.run(() async {
    final prefix = await _installedPrefix(sid);
    if (prefix != null) {
      await _secrets.write('${prefix}family.transferred', 'true');
    }
  });

  Future<bool> isTransferred(String sid) =>
      _queue.run(() => _isTransferred(sid));

  Future<void> assertWritable(String sid) async {
    if (await isTransferred(sid)) throw StateError('transferred');
  }

  Future<void> clearCompletedRestoreGate() => _queue.run(() async {
    final raw = (await _read())['restore'];
    if (raw != null &&
        RecoveryJournal.fromJson(raw).phase == RecoveryPhase.active) {
      await _secrets.delete('family.recoveryRestoring');
    }
  });

  /// Tests availability without revealing or consuming the one-time delivery.
  Future<bool> hasCodeDisplay(String sid) => _queue.run(() async {
    final j = await _read();
    final entropy = (j['displays'] as Map?)?[sid];
    final material = (j['material'] as Map)[sid] as Map?;
    return entropy != null &&
        (j['maintenance'] as Map)[sid] == null &&
        material?['entropy'] == entropy &&
        material?['retired'] != true;
  });

  /// Consumed durably before returning; secrets never enter provider state.
  Future<String?> takeCodeDisplay(String sid) => _queue.run(() async {
    final j = await _read();
    final displays = j['displays'] as Map?;
    final entropy = displays?[sid] as String?;
    final material = (j['material'] as Map)[sid] as Map?;
    if (entropy == null ||
        (j['maintenance'] as Map)[sid] != null ||
        material?['entropy'] != entropy ||
        material?['retired'] == true) {
      return null;
    }
    displays!.remove(sid);
    await _write(j);
    return entropy;
  });

  /// Confirm only the code delivered to this flow, never a replacement code.
  Future<void> confirmCode(String sid, String entropy) => _queue.run(() async {
    final j = await _read();
    if (await _isTransferred(sid)) throw StateError('transferred');
    final material = (j['material'] as Map)[sid] as Map?;
    if (material == null ||
        material['retired'] == true ||
        material['entropy'] != entropy ||
        (j['displays'] as Map?)?[sid] == entropy) {
      throw StateError('recovery changed');
    }
    material['wordsConfirmed'] = true;
    await _write(j);
  });

  /// Success and maintenance material commit together, before redundant claim
  /// credentials and request bodies disappear from the restore journal.
  Future<void> completeRestore(
    RecoveryJournal journal,
    String sid,
    Map<String, Object?> material,
  ) => _queue.run(() async {
    final j = await _read();
    final old = RecoveryJournal.fromJson(j['restore']);
    if (old.operationId != journal.operationId) {
      throw StateError('recovery changed');
    }
    // Successfully restoring with the code proves possession of its words/QR.
    (j['material'] as Map)[sid] = {..._copy(material), 'wordsConfirmed': true};
    j['restore'] = RecoveryJournal(
      operationId: journal.operationId,
      phase: RecoveryPhase.active,
      data: {'syncId': sid},
    ).toJson();
    await _write(j);
    await _secrets.delete('family.recoveryRestoring');
  });
}

final recoveryStoreProvider = Provider<RecoveryStore>(
  (ref) => RecoveryStore(
    secrets: ref.watch(secretStoreProvider),
    files: ref.watch(fileStoreProvider),
  ),
);
