import '../../../core/sync/envelope.dart';
import '../../../core/sync/family_doc.dart';
import '../data/vault_store.dart';
import 'vault_service.dart';

class PendingEntry {
  PendingEntry(
    this.id,
    this.delta, {
    this.setAside = false,
    this.giftPeople = const {},
    this.undoGiftId,
    this.publishAfter,
  });
  final String id;
  final FamilyDoc delta;
  final bool setAside;

  /// Original and proposed recipients, including deletions and moves. These
  /// survive remote changes which can otherwise erase the original recipient.
  final Map<String, List<String>> giftPeople;
  final String? undoGiftId;
  final DateTime? publishAfter;
}

/// Storage only. Lot 4 must provide deltas with precisely the records/fields
/// written by a single action and apply the admission rule before publication.
class PendingQueue {
  PendingQueue(this.vault);
  final VaultService vault;
  Future<VaultSet> _current() => vault.readCurrent();

  Future<void> _write(VaultSet previous, VaultSet next) =>
      vault.replaceCurrent(previous, next);
  Future<String> add(
    FamilyDoc delta, {
    Map<String, List<String>> giftPeople = const {},
    String? undoGiftId,
    DateTime? publishAfter,
  }) => vault.serial(() async {
    final current = await _current();
    final open = vault.opened;
    final id = encodeBase64Url(vault.crypto.randomBytes(16));
    final sealed = await vault.crypto.seal(
      {
        'delta': delta.toJson(),
        'aside': false,
        'giftPeople': giftPeople,
        'undoGiftId': ?undoGiftId,
        if (publishAfter != null)
          'publishAfter': publishAfter.millisecondsSinceEpoch,
      },
      open.key,
      open.header,
      'queue',
      id,
    );
    await _write(
      current,
      current.copy(entries: {...current.entries, id: sealed}),
    );
    return id;
  });

  /// Expiry and the returned snapshot share the vault lock with cancellation.
  /// Resolve intents before a publication candidate can admit their deltas.
  Future<List<PendingEntry>> entries({DateTime? expireUndoAt}) =>
      vault.serial(() async {
        final current = await _current();
        final open = vault.opened;
        final result = <PendingEntry>[];
        final updated = Map.of(current.entries);
        var changed = false;
        for (final entry in current.entries.entries) {
          final value = Map<String, Object?>.from(
            await vault.crypto.open(
              entry.value,
              open.key,
              open.header,
              'queue',
              entry.key,
            ) as Map,
          );
          final due = value['publishAfter'] as int?;
          if (expireUndoAt != null &&
              due != null &&
              due <= expireUndoAt.millisecondsSinceEpoch) {
            value.remove('undoGiftId');
            value.remove('publishAfter');
            updated[entry.key] = await vault.crypto.seal(
              value,
              open.key,
              open.header,
              'queue',
              entry.key,
            );
            changed = true;
          }
          result.add(
            PendingEntry(
              entry.key,
              FamilyDoc.fromJson(
                Map<String, Object?>.from(value['delta'] as Map),
              ),
              setAside: value['aside'] as bool,
              undoGiftId: value['undoGiftId'] as String?,
              publishAfter: value['publishAfter'] == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(
                      value['publishAfter'] as int,
                      isUtc: true,
                    ),
              giftPeople: {
                for (final e in ((value['giftPeople'] as Map?) ?? {}).entries)
                  e.key as String: (e.value as List).cast<String>(),
              },
            ),
          );
        }
        if (changed) await _write(current, current.copy(entries: updated));
        return result;
      });

  /// Durable cancellation of an undoable action; no server receipt is created.
  Future<bool> undoGiftDelete(String giftId, DateTime at) =>
      vault.serial(() async {
        final current = await _current();
        final open = vault.opened;
        for (final entry in current.entries.entries) {
          final value = await vault.crypto.open(
            entry.value,
            open.key,
            open.header,
            'queue',
            entry.key,
          ) as Map;
          if (value['undoGiftId'] == giftId &&
              (value['publishAfter'] as int) > at.millisecondsSinceEpoch) {
            await _write(
              current,
              current.copy(entries: Map.of(current.entries)..remove(entry.key)),
            );
            return true;
          }
        }
        return false;
      });
  Future<VaultJson> _marks(VaultSet current) async {
    final open = vault.opened;
    return current.marks == null
        ? {'blocked': <String>[], 'acks': <String, Object?>{}}
        : Map<String, Object?>.from(
            await vault.crypto.open(
              current.marks!,
              open.key,
              open.header,
              'blocked',
            ) as Map,
          );
  }

  /// Receipt and removal commit together. A failed transaction retains the delta.
  Future<void> ack(String id, {required Object confirmation}) =>
      vault.serial(() async {
        final current = await _current();
        if (!current.entries.containsKey(id)) return;
        final marks = await _marks(current);
        (marks['acks'] as Map)[id] = confirmation;
        final open = vault.opened;
        final sealed = await vault.crypto.seal(
          marks,
          open.key,
          open.header,
          'blocked',
        );
        final entries = Map.of(current.entries)..remove(id);
        await _write(current, current.copy(entries: entries, marks: sealed));
      });
  Future<void> setAside(String id) => vault.serial(() async {
    final current = await _current();
    if (!current.entries.containsKey(id)) return;
    final open = vault.opened;
    final value = Map<String, Object?>.from(
      await vault.crypto.open(
        current.entries[id]!,
        open.key,
        open.header,
        'queue',
        id,
      ) as Map,
    )..['aside'] = true;
    final sealed = await vault.crypto.seal(
      value,
      open.key,
      open.header,
      'queue',
      id,
    );
    await _write(
      current,
      current.copy(entries: {...current.entries, id: sealed}),
    );
  });

  /// Monotonic, durable marks; await this before any PUT.
  Future<Set<String>> blockedPeople({Set<String> remember = const {}}) =>
      vault.serial(() async {
        final current = await _current();
        final marks = await _marks(current);
        final people = (marks['blocked'] as List).cast<String>().toSet()
          ..addAll(remember);
        if (remember.isNotEmpty) {
          marks['blocked'] = people.toList()..sort();
          final open = vault.opened;
          await _write(
            current,
            current.copy(
              marks: await vault.crypto.seal(
                marks,
                open.key,
                open.header,
                'blocked',
              ),
            ),
          );
        }
        return people;
      });
}
