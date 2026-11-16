import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/device_keys.dart';
import '../../../core/sync/envelope.dart';
import '../../../core/sync/family_candidate.dart' show sha256Hex;
import '../../../core/sync/pairing_v2.dart' show canonicalJsonText;
import 'generation_storage.dart';
import 'storage.dart';
import 'storage_providers.dart';

const renewalJournalFile = 'family.renewalJournal';
const _journalKey = renewalJournalEncryptionKey;
final _aad = utf8.encode('gift-huddle-renewal-journal-v1');

/// Durable local progress, separate from PendingV2 and the network contract.
/// [data] contains prepared secrets, exact checkpoints, anchors, inventories,
/// mappings, receipts, exclusions and pending actions. No capacity pruning is
/// applied here: references remain recoverable even after retirement.
class RenewalJournal {
  RenewalJournal({
    required this.operationId,
    required this.sourceSyncId,
    required this.destinationSyncId,
    required this.phase,
    this.revision = 0,
    Map<String, Object?> data = const {},
  }) : data = Map<String, Object?>.unmodifiable(
         Map<String, Object?>.from(jsonDecode(jsonEncode(data)) as Map),
       ) {
    checkGenerationId(sourceSyncId);
    checkGenerationId(destinationSyncId);
    if (!kSyncIdPattern.hasMatch(operationId) ||
        sourceSyncId == destinationSyncId ||
        phase.isEmpty ||
        revision < 0) {
      throw const FormatException('invalid renewal journal');
    }
  }

  final String operationId;
  final String sourceSyncId;
  final String destinationSyncId;
  final String phase;
  final int revision;
  final Map<String, Object?> data;

  RenewalJournal next({required String phase, Map<String, Object?>? data}) =>
      RenewalJournal(
        operationId: operationId,
        sourceSyncId: sourceSyncId,
        destinationSyncId: destinationSyncId,
        phase: phase,
        revision: revision + 1,
        data: data ?? this.data,
      );

  Map<String, Object?> toJson() => {
    'v': 1,
    'operation': operationId,
    'source': sourceSyncId,
    'destination': destinationSyncId,
    'phase': phase,
    'revision': revision,
    'data': data,
  };

  factory RenewalJournal.fromJson(Object? raw) {
    try {
      final json = raw as Map;
      if (json['v'] != 1) throw const FormatException();
      return RenewalJournal(
        operationId: json['operation'] as String,
        sourceSyncId: json['source'] as String,
        destinationSyncId: json['destination'] as String,
        phase: json['phase'] as String,
        revision: json['revision'] as int,
        data: Map<String, Object?>.from(json['data'] as Map),
      );
    } on Object {
      throw const FormatException('renewal journal damaged');
    }
  }
}

/// One encrypted atomic file contains the active operation and its archives.
/// A lost/malformed key or journal is an error, never an absent operation.
/// Use root app stores here, not a generation-scoped handle.
class RenewalJournalStore {
  RenewalJournalStore({required SecretStore secrets, required FileStore files})
    : _secrets = secrets,
      _files = files,
      _queue = GenerationStorageQueue.on(secrets, 'renewalJournal') {
    if (secrets is GenerationSecretStore || files is GenerationFileStore) {
      throw ArgumentError('renewal journal requires root stores');
    }
  }

  final SecretStore _secrets;
  final FileStore _files;
  final GenerationStorageQueue _queue;
  final _aes = AesGcm.with256bits();

  Future<({RenewalJournal? active, List<RenewalJournal> archives})>
  _read() async {
    final bytes = await _files.read(renewalJournalFile);
    if (bytes == null) {
      final directory = await GenerationDirectory.read(_secrets);
      if (directory != null &&
          directory.entries.keys
                  .where(
                    (id) =>
                        !directory.recoveryArchives.containsKey(id) &&
                        !directory.recoveryRetained.contains(id),
                  )
                  .length >
              1) {
        throw const FormatException('renewal journal missing');
      }
      // With only the source registered, a crash between saving the first
      // encryption key and the first journal file has not exposed a target.
      return (active: null, archives: <RenewalJournal>[]);
    }
    final key = await _secrets.read(_journalKey);
    if (key == null) throw const FormatException('renewal journal key missing');
    try {
      if (bytes.length < 29 || bytes[0] != 1) throw const FormatException();
      final plain = await _aes.decrypt(
        SecretBox(
          bytes.sublist(13, bytes.length - 16),
          nonce: bytes.sublist(1, 13),
          mac: Mac(bytes.sublist(bytes.length - 16)),
        ),
        secretKey: SecretKey(decodeBase64Url(key)),
        aad: _aad,
      );
      final json = jsonDecode(utf8.decode(plain)) as Map;
      if (json['v'] != 1) throw const FormatException();
      return (
        active: json['active'] == null
            ? null
            : RenewalJournal.fromJson(json['active']),
        archives: [
          for (final item in json['archives'] as List)
            RenewalJournal.fromJson(item),
        ],
      );
    } on Object {
      throw const FormatException('renewal journal unreadable');
    }
  }

  Future<void> _write(
    RenewalJournal? active,
    List<RenewalJournal> archives,
  ) async {
    var key = await _secrets.read(_journalKey);
    if (key == null) {
      // _read has already checked that no encrypted journal exists.
      key = encodeBase64Url(secureRandomBytes(32));
      await _secrets.write(_journalKey, key);
    }
    final box = await _aes.encrypt(
      utf8.encode(
        jsonEncode({
          'v': 1,
          'active': active?.toJson(),
          'archives': [for (final item in archives) item.toJson()],
        }),
      ),
      secretKey: SecretKey(decodeBase64Url(key)),
      aad: _aad,
    );
    await _files.writeAtomic(
      renewalJournalFile,
      Uint8List.fromList([
        1,
        ...box.nonce,
        ...box.cipherText,
        ...box.mac.bytes,
      ]),
    );
  }

  Future<RenewalJournal?> read() =>
      _queue.run(() async => (await _read()).active);

  Future<List<RenewalJournal>> readArchives() =>
      _queue.run(() async => (await _read()).archives);

  /// Initial revision is zero. Subsequent writes must be the next revision;
  /// an identical retry is harmless. Concurrent stale writers cannot win.
  Future<void> save(RenewalJournal journal) => _queue.run(() async {
    final state = await _read();
    final old = state.active;
    if (old != null &&
        jsonEncode(old.toJson()) == jsonEncode(journal.toJson())) {
      return;
    }
    if (old == null) {
      if (journal.revision != 0 ||
          state.archives.any((a) => a.operationId == journal.operationId)) {
        throw StateError('renewal operation already completed or stale');
      }
    } else if (old.operationId != journal.operationId ||
        old.sourceSyncId != journal.sourceSyncId ||
        old.destinationSyncId != journal.destinationSyncId ||
        journal.revision != old.revision + 1) {
      throw StateError('renewal journal conflict');
    }
    if (old?.data['preparedGeneration'] != null &&
        jsonEncode(old!.data['preparedGeneration']) !=
            jsonEncode(journal.data['preparedGeneration'])) {
      throw StateError('prepared generation cannot be replaced or forgotten');
    }
    for (final field in ['previousPreparations', 'previousDestinations']) {
      if (old?.data[field] != null &&
          canonicalJsonText(old!.data[field]) !=
              canonicalJsonText(journal.data[field])) {
        throw StateError(
          'preparation history cannot be changed by ordinary save',
        );
      }
    }
    for (final field in ['preparationInstalled', 'activationPrepared']) {
      if (old?.data[field] == true && journal.data[field] != true) {
        throw StateError('durable installation progress cannot be rolled back');
      }
    }
    await _write(journal, state.archives);
  });

  /// Atomically select a fresh preparation within the SAME remote operation.
  /// The old context stays registered. This is separate from save, so stale
  /// ordinary journal writers cannot change destination or installation intent.
  Future<void> replaceDestination(RenewalJournal next) => _queue.run(() async {
    final state = await _read();
    final old = state.active;
    if (old != null && jsonEncode(old.toJson()) == jsonEncode(next.toJson())) {
      return;
    }
    if (old == null ||
        old.operationId != next.operationId ||
        old.sourceSyncId != next.sourceSyncId ||
        old.destinationSyncId == next.destinationSyncId ||
        next.revision != old.revision + 1 ||
        next.data['preparedGeneration'] == null ||
        next.data['preparationInstalled'] != false ||
        next.data['activationPrepared'] == true ||
        next.data['destinationReady'] == true) {
      throw StateError('renewal replacement conflict');
    }
    final expected = {
      ...?old.data['previousPreparations'] as Map?,
      old.destinationSyncId: {
        for (final e in old.data.entries)
          if (e.key != 'previousPreparations' && e.key != 'operationContext')
            e.key: e.value,
      },
    };
    if (canonicalJsonText(next.data['previousPreparations']) !=
            canonicalJsonText(expected) ||
        canonicalJsonText(next.data['operationContext']) !=
            canonicalJsonText(
              old.data['operationContext'] ?? <String, Object?>{},
            )) {
      throw StateError(
        'replacement must preserve preparation history and source control',
      );
    }
    await _write(next, state.archives);
  });

  /// Archives contain references and a digest only. Secrets remain solely in
  /// their generation contexts; no second full snapshot survives completion.
  Future<void> archive(String operationId) => _queue.run(() async {
    final state = await _read();
    final active = state.active;
    if (active == null &&
        state.archives.any((a) => a.operationId == operationId)) {
      return;
    }
    if (active?.operationId != operationId) {
      throw StateError('renewal operation mismatch');
    }
    final reference = RenewalJournal(
      operationId: active!.operationId,
      sourceSyncId: active.sourceSyncId,
      destinationSyncId: active.destinationSyncId,
      phase: 'archived',
      revision: active.revision,
      data: {
        'digest': sha256Hex(utf8.encode(canonicalJsonText(active.toJson()))),
      },
    );
    await _write(null, [...state.archives, reference]);
  });
}

final renewalJournalStoreProvider = Provider<RenewalJournalStore>(
  (ref) => RenewalJournalStore(
    secrets: ref.watch(secretStoreProvider),
    files: ref.watch(fileStoreProvider),
  ),
);
