import '../../../core/sync/envelope.dart';
import '../../../core/sync/family_doc.dart';
import '../data/vault_store.dart';
import 'vault_service.dart';

/// What an action changes (ADR 0010). The kind is typed so that a private
/// change can never be published in the clear by mistake.
enum PendingKind {
  /// A change to the common document (a gift, an own wish...). Published
  /// by the web itself.
  publicChange,

  /// A change to the private scope of one person (the surprises of someone
  /// else: gifts and wish plans), for the inbox of the web's phone. It is
  /// never merged into the common document, whatever happens to the key.
  privateScope,
}

class PendingEntry {
  PendingEntry(
    this.id,
    this.delta, {
    this.setAside = false,
    this.blockingDevicePersonNames,
    this.giftPeople = const {},
    this.undoGiftId,
    this.publishAfter,
    this.newGifts = const {},
    this.inboxPerson,
    this.newPlans = const {},
    this.kind = PendingKind.publicChange,
  });
  final String id;

  /// Public change or private scope change (see [PendingKind]).
  final PendingKind kind;

  /// Wish plans the action created (a wish was claimed), for the inbox.
  final Set<String> newPlans;

  /// The protected person whose inbox this action was written for: the web
  /// could change that person's secret gifts when it was saved (1.0.6, ADR
  /// 0009). Null for every other action, which a protection still sets
  /// aside as before.
  final String? inboxPerson;

  /// Gifts the action created (they did not exist before it), for the inbox
  /// of a protected person (1.0.6, ADR 0009).
  final Set<String> newGifts;
  final FamilyDoc delta;
  final bool setAside;

  /// Names recorded when a connected device blocked a queued person deletion.
  /// Null for entries written before the rejection reason was saved.
  final List<String>? blockingDevicePersonNames;

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
    Set<String> newGifts = const {},
    String? inboxPerson,
    Set<String> newPlans = const {},
    PendingKind kind = PendingKind.publicChange,
  }) => vault.serial(() async {
    final current = await _current();
    final open = vault.opened;
    final id = encodeBase64Url(vault.crypto.randomBytes(16));
    final sealed = await vault.crypto.seal(
      {
        'delta': delta.toJson(),
        // A private change is stored as set aside so that the 1.0.6 web code,
        // which does not know it, parks it («hazlo desde el móvil») instead
        // of reading its delta; this version routes by `kind` first and
        // ignores the flag for it (security review, M1).
        'aside': kind == PendingKind.privateScope,
        'giftPeople': giftPeople,
        'undoGiftId': ?undoGiftId,
        if (newGifts.isNotEmpty) 'newGifts': (newGifts.toList()..sort()),
        'inbox': ?inboxPerson,
        if (newPlans.isNotEmpty) 'newPlans': (newPlans.toList()..sort()),
        if (kind == PendingKind.privateScope) 'kind': 'private',
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
              setAside:
                  value['kind'] != 'private' && (value['aside'] as bool),
              blockingDevicePersonNames:
                  (value['blockingDevicePersonNames'] as List?)?.cast<String>(),
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
              newGifts: {
                for (final id in (value['newGifts'] as List?) ?? const [])
                  if (id is String) id,
              },
              inboxPerson: value['inbox'] as String?,
              newPlans: {
                for (final id in (value['newPlans'] as List?) ?? const [])
                  if (id is String) id,
              },
              kind: value['kind'] == 'private'
                  ? PendingKind.privateScope
                  : PendingKind.publicChange,
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
  Future<void> setAside(
    String id, {
    List<String>? blockingDevicePersonNames,
  }) => vault.serial(() async {
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
    if (blockingDevicePersonNames != null) {
      value['blockingDevicePersonNames'] = blockingDevicePersonNames;
    }
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
