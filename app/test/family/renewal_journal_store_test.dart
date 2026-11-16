import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/family/data/renewal_journal_store.dart';

import '../helpers/memory_stores.dart';

RenewalJournal _entry(String phase) => RenewalJournal(
  operationId: 'operation-1',
  sourceSyncId: 'AAAAAAAAAAAAAAAAAAAAAA',
  destinationSyncId: 'BBBBBBBBBBBBBBBBBBBBBB',
  phase: phase,
  data: {
    'preparedGeneration': {'private': 'durable secret'},
    'anchors': ['old-record', 'new-record'],
    'minCommonFormat': 2,
    'snapshot': {'common': 'exact ciphertext', 'version': 17},
    'checkpoint': {'commonKeys': 'referenced keyring'},
    'invitations': ['approved-not-installed'],
    'mappings': {'old-device': 'new-device'},
    'receipts': ['signed opaque receipt'],
    'exclusions': ['explicit individual exclusion'],
    'pending': ['overflow', 'leftOut', 'unreadable-slot'],
    'retryAt': 123456789,
  },
);

class _FailingFiles extends MemoryFileStore {
  bool fail = false;
  @override
  Future<void> writeAtomic(String name, Uint8List bytes) async {
    if (fail) throw StateError('storage interrupted');
    await super.writeAtomic(name, bytes);
  }
}

void main() {
  for (final phase in [
    'before-reservation',
    'reservation-response-lost',
    'creation-response-lost',
    'partial-publication',
    'approved-checkpoint-not-installed',
    'merged-before-put',
    'put-accepted-before-receipt',
    'active-generation-switch',
    'closure-barrier-accepted',
    'delete-response-lost',
    'retry-412',
    'retry-429',
    'network-unavailable',
  ]) {
    test('reopening keeps the exact journal at $phase', () async {
      final secrets = MemorySecretStore();
      final files = MemoryFileStore();
      final store = RenewalJournalStore(secrets: secrets, files: files);
      final entry = _entry(phase);
      await store.save(entry);
      final reopened = RenewalJournalStore(secrets: secrets, files: files);
      expect((await reopened.read())!.toJson(), entry.toJson());
      final bytes = files.files.values.single;
      expect(latin1.decode(bytes), isNot(contains('durable secret')));
      expect(latin1.decode(bytes), isNot(contains('opaque receipt')));
      expect(secrets.values.values, isNot(contains('durable secret')));
    });
  }

  test(
    'identical retries are idempotent and stale concurrent writers conflict',
    () async {
      final secrets = MemorySecretStore();
      final files = MemoryFileStore();
      final first = RenewalJournalStore(secrets: secrets, files: files);
      final second = RenewalJournalStore(secrets: secrets, files: files);
      final entry = _entry('prepared');
      await first.save(entry);
      await second.save(entry);
      final outcomes = await Future.wait([
        first
            .save(entry.next(phase: 'reserved'))
            .then((_) => true, onError: (Object _) => false),
        second
            .save(entry.next(phase: 'different-reservation'))
            .then((_) => true, onError: (Object _) => false),
      ]);
      expect(outcomes.where((ok) => ok).length, 1);
      expect((await first.read())!.revision, 1);
      await expectLater(second.save(entry), throwsStateError);
    },
  );

  test(
    'changing operation, source, destination or prepared secrets is rejected',
    () async {
      final secrets = MemorySecretStore();
      final files = MemoryFileStore();
      final store = RenewalJournalStore(secrets: secrets, files: files);
      final entry = _entry('prepared');
      await store.save(entry);
      for (final field in ['operation', 'source', 'destination', 'data']) {
        final changed = entry.next(phase: 'reserved').toJson();
        changed[field] = switch (field) {
          'operation' => 'other-operation',
          'data' => {'preparedGeneration': 'replacement'},
          _ => 'CCCCCCCCCCCCCCCCCCCCCC',
        };
        await expectLater(
          store.save(RenewalJournal.fromJson(changed)),
          throwsStateError,
        );
      }
      await expectLater(
        store.save(entry.next(phase: 'reserved', data: {})),
        throwsStateError,
      );
      expect((await store.read())!.toJson(), entry.toJson());
    },
  );

  test(
    'failed replacement preserves the previous complete encrypted journal',
    () async {
      final secrets = MemorySecretStore();
      final files = _FailingFiles();
      final store = RenewalJournalStore(secrets: secrets, files: files);
      final entry = _entry('prepared');
      await store.save(entry);
      files.fail = true;
      await expectLater(
        store.save(entry.next(phase: 'reserved')),
        throwsStateError,
      );
      files.fail = false;
      expect((await store.read())!.toJson(), entry.toJson());
      await store.save(entry.next(phase: 'reserved'));
      expect((await store.read())!.phase, 'reserved');
    },
  );

  test(
    'missing key, wrong key, truncation and tampering never mean no renewal',
    () async {
      for (final damage in [
        'missing-key',
        'wrong-key',
        'truncated',
        'tampered',
      ]) {
        final secrets = MemorySecretStore();
        final files = MemoryFileStore();
        final store = RenewalJournalStore(secrets: secrets, files: files);
        await store.save(_entry('closure-barrier-accepted'));
        final fileName = files.files.keys.single;
        final keyName = secrets.values.keys.single;
        switch (damage) {
          case 'missing-key':
            secrets.values.remove(keyName);
          case 'wrong-key':
            secrets.values[keyName] = base64Url
                .encode(List.filled(32, 0))
                .replaceAll('=', '');
          case 'truncated':
            files.files[fileName] = Uint8List.fromList([1, 2, 3]);
          case 'tampered':
            files.files[fileName]![15] ^= 1;
        }
        final damagedBytes = Uint8List.fromList(files.files[fileName]!);
        await expectLater(store.read(), throwsFormatException);
        await expectLater(
          store.save(_entry('replacement')),
          throwsFormatException,
        );
        expect(files.files[fileName], damagedBytes);
        if (damage == 'missing-key') expect(secrets.values, isEmpty);
      }
    },
  );

  test(
    'archives keep references across many generations without a retention cap',
    () async {
      final secrets = MemorySecretStore();
      final files = MemoryFileStore();
      final store = RenewalJournalStore(secrets: secrets, files: files);
      for (var i = 0; i < 70; i++) {
        final json = _entry('retired').toJson()..['operation'] = 'operation-$i';
        await store.save(RenewalJournal.fromJson(json));
        await store.archive('operation-$i');
      }
      final reopened = RenewalJournalStore(secrets: secrets, files: files);
      expect(await reopened.read(), isNull);
      final archives = await reopened.readArchives();
      expect(archives.length, 70);
      expect(archives.first.data.keys, ['digest']);
      expect(archives.first.data['digest'], matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(
        jsonEncode(archives.first.toJson()),
        isNot(contains('durable secret')),
      );
      await expectLater(store.save(_entry('replayed')), throwsStateError);
    },
  );
}
