import 'dart:async';
import 'dart:math' show max;
import 'dart:typed_data';

import '../../../core/sync/access_policy.dart';
import '../../../core/sync/device_keys.dart';
import '../../../core/sync/device_registry.dart';
import '../../../core/sync/envelope.dart';
import '../../../core/sync/envelope.dart' as envelope;
import '../../../core/sync/family_candidate.dart';
import '../../../core/sync/family_doc.dart';
import '../../../core/sync/family_envelope.dart';
import '../../../core/sync/family_key_bundle.dart';
import '../../../core/sync/hlc.dart';
import '../../../core/sync/key_bundle.dart';
import '../../../core/sync/model.dart';
import '../../../core/sync/pairing_v2.dart' show syncProtocolOf;
import '../../../core/sync/protected_doc.dart';
import '../../../core/sync/protected_envelope.dart';
import '../../../core/sync/wish.dart';
import '../../../core/sync/wish_author.dart';
import '../../../core/sync/wish_boundary.dart';
import '../../../core/sync/wish_plan.dart';
import '../../sync/application/common_v2.dart';
import '../../sync/application/common_v2_cutover.dart';
import '../../sync/application/sync_v2_engine.dart' show V2RollbackException;
import '../../sync/data/sync_transport.dart';
import '../../sync/data/sync_transport_v2.dart';
import '../data/vault_store.dart';
import 'pending_queue.dart';
import 'vault_service.dart';
import 'web_common.dart';
import 'web_secrets.dart';

/// The web's inbox history in the vault (1.0.6, ADR 0009): per person, the
/// inbox slots it sealed (epoch, revision and the queue entries inside).
const String kWebInboxField = 'webInbox';

/// The people of all the records of each phone that vouched [screen]'s own
/// record (the web's current one) while that phone was of the web's person
/// (final review, M1). If the phone that connected the web later changes
/// person, its screen layer hides the old and the new person while the change
/// waits; the web cannot change person, so it hides them too. A phone of
/// another person that vouched the web (an older flow) adds nothing.
Set<String> webPhonePeople(DeviceRegistry registry, RegistryView screen) {
  final web = screen.self;
  final person = web.personId;
  if (person == null) return const {};
  final byDigest = {for (final r in registry.records) r.digest: r};
  final phones = <String>{
    for (final v in registry.vouches)
      if (v.recordDigest == web.recordDigest)
        if (byDigest[v.byRecord] case final then?
            when then.kind == DeviceKind.mobile &&
                then.personId == person &&
                then.deviceId != web.deviceId)
          then.deviceId,
  };
  return {
    for (final r in registry.records)
      if (phones.contains(r.deviceId) && r.personId != null) r.personId!,
  };
}

/// Inbox slots one web may hold at once (`V2_MAX_WEB_SLOTS`).
const int kMaxWebInboxSlots = 8;

/// The last inbox revision the web sealed per person, kept after the
/// history empties (security review, B7): a clock going back never seals
/// below a phone's mark.
const String kWebInboxRevisionField = 'webInboxRevision';

/// How long an inbox the Worker refused (cap, size, renewal, an old Worker)
/// waits before the web tries it again (security review, M3).
const Duration kWebInboxHold = Duration(minutes: 10);

/// Product operations unavailable to a restricted web identity.
class WebOperationException implements Exception {
  const WebOperationException(this.operation);
  final String operation;
  @override
  String toString() => 'WebOperationException($operation)';
}

Map<String, Object?> snapshotJson(V2Snapshot s) => {
  'version': s.version,
  'common': encodeBase64Url(s.common),
  'registry': s.registry,
  'keyPackages': s.keyPackages,
  'slots': [
    for (final r in s.slots)
      {'personId': r.personId, 'deviceId': r.deviceId, 'version': r.version},
  ],
  'devices': [
    for (final d in s.devices)
      {'deviceId': d.deviceId, 'revoked': d.revoked, 'role': d.role},
  ],
};

Map<String, Object?> rootJson(RegistryAnchor r) => {
  'deviceId': r.deviceId,
  'signingKey': encodeBase64Url(r.signingKey),
};

List<RegistryAnchor> pinnedRoots(Object? value) => [
  for (final r in value as List)
    RegistryAnchor(
      deviceId: (r as Map)['deviceId'] as String,
      signingKey: decodeBase64Url(r['signingKey'] as String),
    ),
];

/// Exactly the fields written by one action; preserves their original HLCs.
FamilyDoc webDelta(FamilyDoc before, FamilyDoc after) {
  if (before.listId != after.listId) {
    throw const WebOperationException('replaceFamily');
  }
  return FamilyDoc(
    listId: before.listId,
    collections: {
      for (final c in after.collections.entries)
        c.key: {
          for (final r in c.value.values)
            if (r.fields.entries.any(
              (f) => !_same(before.record(c.key, r.id)?.field(f.key), f.value),
            ))
              r.id: SyncRecord(
                id: r.id,
                fields: {
                  for (final f in r.fields.entries)
                    if (!_same(
                      before.record(c.key, r.id)?.field(f.key),
                      f.value,
                    ))
                      f.key: f.value,
                },
              ),
        },
    },
  );
}

bool _same(FieldValue? a, FieldValue b) =>
    a != null &&
    a.stamp == b.stamp &&
    canonicalJsonOf(a.value) == canonicalJsonOf(b.value);

/// The single ADR 0003 §4 publication predicate. Checks historical, proposed
/// and merged recipients even when an unrelated field is the only edit.
bool webEntryAllowed(
  FamilyDoc before,
  PendingEntry entry,
  Set<String> blocked,
) {
  // A private scope change (wish plans, ADR 0010) is never a public write.
  if (entry.kind == PendingKind.privateScope) return false;
  final result = before.merge(entry.delta);
  for (final r
      in entry.delta.collections[Collections.gifts]?.values ?? <SyncRecord>[]) {
    final people = <Object?>{
      ...?entry.giftPeople[r.id],
      before.record(Collections.gifts, r.id)?['recipientId'],
      r['recipientId'],
      result.record(Collections.gifts, r.id)?['recipientId'],
    };
    for (final person in people.whereType<String>().where(blocked.contains)) {
      // A recipient cascade can scrub that person's public gift in place.
      if (!r.isDeleted ||
          r.hasTombstoneContent ||
          entry.delta.record(Collections.recipients, person)?.isDeleted !=
              true) {
        return false;
      }
    }
  }
  return true;
}

enum WebSyncStatus { pending, confirmed, disconnected }

/// What a confirmed engine is doing with the network right now. Read-only
/// hint for the status line; it never feeds publication decisions.
enum WebSyncActivity {
  /// Nothing waits to be published and the connection looks fine.
  idle,

  /// A publication is running or admitted entries are not confirmed yet.
  uploading,

  /// A network failure or a dropped socket is being retried.
  offline,
}

/// Restricted v2 engine. Its only publication call is PUT S/common. All
/// Network operations share a queue; undo registration uses the vault lock.
/// Session cancellation invalidates every awaited callback.
class WebSyncEngine {
  WebSyncEngine({
    required this.transport,
    required this.vault,
    required this.queue,
    this.onChanged,
    this.onDisconnected,
    this.onError,
    DateTime Function()? now,
    this.commonV2Ready = kCommonV2Ready,
    this.refreshInterval = const Duration(seconds: 60),
    bool Function()? isVisible,
  }) : now = now ?? DateTime.now,
       isVisible = isVisible ?? (() => true);
  final DateTime Function() now;
  final bool Function() isVisible;

  /// Backup check after a successful sync, only while the tab is visible.
  final Duration refreshInterval;

  /// ADR 0005, B4/B5: with it this web announces that it reads and writes
  /// the common format 2. Following a cut never depends on it (the mark in
  /// the vault does).
  final bool commonV2Ready;

  /// What happened to the remote common in format 2 on the last read; null
  /// before the cut. Read-only hint: anything but
  /// [RemoteCommonStatus.opened] retains the queue.
  RemoteCommonStatus? commonStatus;

  /// A v4 package did not fit in the keyring (hard limit).
  bool commonKeyringFull = false;

  /// The candidate this web may seal with (see [webSealingCandidate]).
  FamilyCandidate? _sealing;

  /// After the cut, changes wait encrypted in the queue: the key, the
  /// confirmation or the distribution is missing.
  bool get commonHeld => commonStatus != null && _sealing == null;
  final SyncV2Transport transport;
  final VaultService vault;
  final PendingQueue queue;
  final void Function()? onChanged, onDisconnected;
  final void Function(Object)? onError;
  FamilyDoc? candidate;
  FamilyDoc? _publicationCandidate;
  bool _needsWishRepair = false;
  RegistryView? view;

  /// The registry seen as this web (its own id and person), for the screen
  /// layer only: [view] is anchored at the phone that verifies signatures,
  /// so its `accompanied` and `myPerson` are the phone's, not the web's.
  /// Null while it cannot be read (then the web hides its own person).
  RegistryView? screenView;

  /// The people of every record of the phone that vouched this web's current
  /// record while it was of the web's person (final review, M1): if that
  /// phone changes person, the web follows the screen layer of the phone and
  /// hides both. See [webPhonePeople].
  Set<String> phonePeople = const {};

  /// The people whose gifts this web never paints: its own (screen layer,
  /// [screenView]) and [phonePeople].
  Set<String> get screenHiddenPeople => {
    ...ownHiddenPeople(
      view: screenView,
      selfRecipientId: vault.opened.data['personId'] as String?,
      paired: true,
    ),
    ...phonePeople,
  };

  /// Session-only surprise keys, slots and opened scopes (1.0.6, ADR 0009).
  final WebSecrets secrets = WebSecrets();

  /// Whether surprises are open in this session (idle lock at 5 minutes).
  bool get secretsOpen => secrets.isOpen;

  /// Gifts with changes waiting in an inbox for the owner's phone
  /// («Pendiente de tu móvil»).
  Set<String> pendingSecretGiftIds = const {};

  /// Inbox changes that wait because the surprises are not open now (no
  /// keys, or the web's phone is not there).
  int heldSecretCount = 0;

  /// Inbox changes dropped because their gift no longer exists, or because
  /// the phone rejected the whole inbox they were in.
  int discardedSecretCount = 0;

  /// Wish plans that wait in the queue because another phone of the family
  /// does not understand them yet (ADR 0010, A1): «update the other phones».
  int get heldPlanCount => _heldPlans.values.fold(0, (n, c) => n + c);

  /// People whose wish plans wait for the other phones to update.
  Set<String> get heldPlanPeople => {
    for (final e in _heldPlans.entries)
      if (e.value > 0) e.key,
  };

  final Map<String, int> _heldPlans = {};

  Map<String, List<PendingEntry>> _inbox = const {};

  /// Wish plans with changes waiting in an inbox for the owner's phone
  /// (ADR 0010).
  Set<String> pendingPlanIds = const {};

  /// The public common as this web sees it: the saved one with the public
  /// actions waiting in the queue. Never holds opened secrets, wish plans or
  /// inbox changes; its newest stamp is the public clock ([publicStamp]).
  FamilyDoc? _commonDoc;

  /// Inboxes the Worker refused, until when they wait (M3). The common
  /// keeps publishing meanwhile.
  final Map<String, DateTime> _inboxHeld = {};

  /// People whose inbox the Worker refused in this session.
  Set<String> get heldInboxPeople => {
    for (final e in _inboxHeld.entries)
      if (now().isBefore(e.value)) e.key,
  };
  WebSyncStatus status = WebSyncStatus.pending;
  int setAsideCount = 0;
  int rejectedSecretRecipientDeletes = 0;
  List<String> rejectedDevicePersonNames = const [];
  bool get hasRoots => (vault.opened.data['roots'] as List).isNotEmpty;
  int version = 0;
  int _generation = 0;
  int _watchGeneration = 0;
  bool _stopped = false;
  bool _started = false;
  Future<void> _tail = Future.value();
  StreamSubscription<SyncEvent>? _socket;
  Timer? _retry;
  Timer? _syncRetry;
  DateTime? _notBefore;
  Timer? _refresh;
  int _syncRequests = 0;
  int _syncing = 0;
  Timer? _undoDeadline;
  int _failures = 0;
  int _undoRevision = 0;
  bool _uploading = false, _syncOffline = false, _socketDown = false;

  /// Network activity for the status line; [onChanged] fires when it changes.
  WebSyncActivity get activity => _syncOffline || _socketDown
      ? WebSyncActivity.offline
      : _uploading
      ? WebSyncActivity.uploading
      : WebSyncActivity.idle;

  void _flag({bool? uploading, bool? syncOffline, bool? socketDown}) {
    final before = activity;
    _uploading = uploading ?? _uploading;
    _syncOffline = syncOffline ?? _syncOffline;
    _socketDown = socketDown ?? _socketDown;
    if (!_stopped && before != activity) onChanged?.call();
  }

  V2Auth get auth => V2Auth(
    syncId: vault.opened.header.syncId,
    deviceId: vault.opened.header.deviceId,
    credential: decodeBase64Url(vault.opened.data['credential'] as String),
  );
  String get listId => vault.opened.data['listId'] as String;
  void _check(int generation) {
    if (_stopped || generation != _generation) {
      throw StateError('Web session invalidated');
    }
    vault.opened;
  }

  Future<T> _serial<T>(Future<T> Function(int) action) {
    final g = _generation;
    final result = _tail.then((_) {
      _check(g);
      return action(g);
    });
    _tail = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> start() async {
    if (_started || _stopped) return;
    _started = true;
    try {
      await requestSync();
    } finally {
      if (!_stopped) _watch();
    }
  }

  /// A suspended browser can lose notifications without a close event. Read
  /// on return (respecting backoff) and replace the potentially stale connection.
  Future<void> resume() async {
    if (!_started || _stopped || !isVisible()) return;
    final watchGeneration = ++_watchGeneration;
    _retry?.cancel();
    _retry = null;
    final socket = _socket;
    _socket = null;
    await socket?.cancel();
    if (_stopped || !isVisible() || watchGeneration != _watchGeneration) return;
    _watch(syncOnOpen: false);
    await requestSync();
  }

  /// Closing the subscription also cancels transport pings and their deadline.
  /// Keep the session open: its existing five-minute hidden lock still applies.
  void suspend() {
    _watchGeneration++;
    _retry?.cancel();
    _retry = null;
    _syncRetry?.cancel();
    _syncRetry = null;
    _refresh?.cancel();
    _refresh = null;
    final socket = _socket;
    _socket = null;
    unawaited(socket?.cancel());
  }

  /// Used by edits/socket notifications. A network cut retains the encrypted
  /// action and retries with bounded backoff; Retry-After is a lower bound.
  Future<void> requestSync() async {
    if (_stopped || !isVisible() || _deferSync()) return;
    _refresh?.cancel();
    _refresh = null;
    _syncRetry?.cancel();
    _syncRetry = null;
    _syncRequests++;
    var refreshed = false;
    try {
      await sync();
      refreshed = true;
    } catch (e) {
      if (_stopped) return;
      onError?.call(e);
    } finally {
      _syncRequests--;
      if (refreshed) _scheduleRefresh();
    }
  }

  bool _deferSync() {
    final deadline = _notBefore;
    if (deadline == null || !now().isBefore(deadline)) return false;
    _armSyncRetry();
    return true;
  }

  void _armSyncRetry() {
    if (_stopped || !isVisible() || _syncRetry != null) return;
    final delay = _notBefore!.difference(now());
    _syncRetry = Timer(delay.isNegative ? Duration.zero : delay, () {
      _syncRetry = null;
      unawaited(requestSync());
    });
  }

  void _scheduleSyncRetry(Object e) {
    if (_stopped) return;
    if (e is SyncTransportException && e.failure == SyncFailure.network) {
      _flag(syncOffline: true);
    }
    if (e is! SyncTransportException ||
        !{
          SyncFailure.network,
          SyncFailure.server,
          SyncFailure.rateLimited,
        }.contains(e.failure)) {
      return;
    }
    var delay = Duration(
      seconds: [5, 15, 45, 120, 300][(_failures++).clamp(0, 4)],
    );
    if (e.retryAfter != null && e.retryAfter! > delay) delay = e.retryAfter!;
    _notBefore = now().add(delay);
    _syncRetry?.cancel();
    _syncRetry = null;
    _armSyncRetry();
  }

  void _scheduleRefresh() {
    if (!_started ||
        _stopped ||
        !isVisible() ||
        _syncRequests != 0 ||
        _syncing != 0 ||
        _syncRetry != null) {
      return;
    }
    _refresh?.cancel();
    _refresh = Timer(refreshInterval, () {
      _refresh = null;
      // A direct/manual sync also uses the serial queue. Never add a backup
      // read behind it, or perform background reads while the tab is hidden.
      if (_syncing == 0) unawaited(requestSync());
    });
  }

  void stop() {
    _stopped = true;
    _generation++;
    _watchGeneration++;
    _retry?.cancel();
    _syncRetry?.cancel();
    _refresh?.cancel();
    _undoDeadline?.cancel();
    unawaited(_socket?.cancel());
    _socket = null;
    candidate = null;
    _commonDoc = null;
    _publicationCandidate = null;
    view = null;
    screenView = null;
    phonePeople = const {};
    secrets.clear();
    _inbox = const {};
    _heldPlans.clear();
    pendingSecretGiftIds = const {};
  }

  void _disconnect() {
    if (_stopped) return;
    status = WebSyncStatus.disconnected;
    stop();
    vault.disconnect();
    onDisconnected?.call();
  }

  void _watch({bool syncOnOpen = true}) {
    if (_stopped || !isVisible() || _socket != null) return;
    final g = _generation;
    final watchGeneration = ++_watchGeneration;
    bool current() =>
        !_stopped &&
        isVisible() &&
        g == _generation &&
        watchGeneration == _watchGeneration;
    _socket = transport
        .watch(auth)
        .listen(
          (event) {
            if (!current()) return;
            if (event is SyncRevokedEvent || event is SyncGoneEvent) {
              _disconnect();
              return;
            }
            if (event is SyncOpenEvent) {
              _failures = 0;
              _flag(socketDown: false);
            }
            if (event is SyncOpenEvent && syncOnOpen ||
                event is SyncVersionEvent && event.version > version) {
              unawaited(requestSync());
            }
          },
          onError: (Object e) {
            if (!current()) return;
            if (e is SyncTransportException &&
                e.failure == SyncFailure.unauthorized) {
              _disconnect();
            } else {
              _flag(socketDown: true);
              onError?.call(e);
            }
          },
          onDone: () {
            if (!current()) return;
            _socket = null;
            _flag(socketDown: true);
            final delay = [1, 2, 5, 15, 30][(_failures++).clamp(0, 4)];
            _retry = Timer(Duration(seconds: delay), _watch);
          },
        );
  }

  /// Durable one-action delta, then a candidate reconstructed from the remote
  /// snapshot. Network publication is independent of reporting local durability.
  Future<void> save(
    FamilyDoc before,
    FamilyDoc after, {
    String? undoGiftId,
    DateTime? publishAfter,
  }) => _serial(
    (g) => _save(
      g,
      before,
      after,
      undoGiftId: undoGiftId,
      publishAfter: publishAfter,
    ),
  );

  /// Saves a controller cascade, including the wish tombstones of any
  /// recipient removed in the same action.
  Future<void> saveCascade(FamilyDoc before, FamilyDoc after) =>
      _serial((g) => _save(g, before, after, cascade: true));

  Future<void> _save(
    int g,
    FamilyDoc before,
    FamilyDoc after, {
    String? undoGiftId,
    DateTime? publishAfter,
    bool ownWishes = false,
    bool cascade = false,
  }) async {
    final delta = webDelta(before, after);
    const allowed = {
      Collections.recipients,
      Collections.givers,
      Collections.occasions,
      Collections.gifts,
      Collections.meta,
    };
    for (final c in delta.collections.entries) {
      if (c.value.isEmpty) continue;
      if (ownWishes) {
        if (c.key != Collections.wishes) {
          throw const WebOperationException('restrictedDocument');
        }
      } else if (cascade && c.key == Collections.wishes) {
        for (final wish in c.value.values) {
          final old = before.record(Collections.wishes, wish.id);
          final recipient = old?['recipientId'];
          if (old == null ||
              old.isDeleted ||
              recipient is! String ||
              delta.record(Collections.recipients, recipient)?.isDeleted !=
                  true ||
              !wish.isDeleted ||
              validateWishRecord(after.record(Collections.wishes, wish.id)!) !=
                  null) {
            throw const WebOperationException('wishInvalid');
          }
        }
      } else if (!allowed.contains(c.key) ||
          c.key == Collections.meta && c.value.containsKey('protocol')) {
        throw const WebOperationException('restrictedDocument');
      }
    }
    if (delta.collections.values.every((v) => v.isEmpty)) return;
    _check(g);
    final giftPeople = {
      for (final id in delta.collections[Collections.gifts]?.keys ?? <String>[])
        id: {
          before.record(Collections.gifts, id)?['recipientId'],
          after.record(Collections.gifts, id)?['recipientId'],
        }.whereType<String>().toList(),
    };
    final entry = PendingEntry('', delta, giftPeople: giftPeople);
    final deletedPeople = _deletedPeople(entry);
    if (cascade &&
        deletedPeople.isNotEmpty &&
        (!_canDeletePeople(deletedPeople) ||
            !webEntryAllowed(before, entry, await queue.blockedPeople()))) {
      // A mixed cascade cannot go to an inbox. Reject it before recording
      // any part of the action as saved.
      throw const WebOperationException('deleteProtectedReferences');
    }
    // 1.0.6 (ADR 0009): with surprises open, an action on the gifts of one
    // protected person the web can write for goes to that person's inbox.
    final inboxPerson = _inboxPerson(entry, await savedCommon());
    _check(g);
    await queue.add(
      delta,
      inboxPerson: secrets.writablePeople.contains(inboxPerson)
          ? inboxPerson
          : null,
      undoGiftId: undoGiftId,
      publishAfter: publishAfter,
      giftPeople: giftPeople,
      newGifts: {
        for (final id
            in delta.collections[Collections.gifts]?.keys ?? <String>[])
          if (before.record(Collections.gifts, id) == null) id,
      },
    );
    _check(g);
    await _candidate(g);
  }

  Future<bool> undoGiftDelete(String id) async {
    final g = _generation;
    _check(g);
    _undoRevision++;
    // Register durably under the vault lock, without waiting for network I/O.
    final undone = await queue.undoGiftDelete(id, now());
    _check(g);
    if (undone) {
      await _serial((g) async {
        await _candidate(g);
      });
    }
    return undone;
  }

  Future<void> sync() async {
    if (_stopped || !isVisible() || _deferSync()) return;
    _refresh?.cancel();
    _refresh = null;
    _syncRetry?.cancel();
    _syncRetry = null;
    _syncing++;
    try {
      await _sync();
    } finally {
      _syncing--;
      _scheduleRefresh();
    }
  }

  Future<void> _sync() => _serial((g) async {
    // A preceding queued request may have failed since this one was admitted.
    if (!isVisible() || _deferSync()) return;
    try {
      await _syncOnce(g);
      _notBefore = null;
      _failures = 0;
      _syncRetry?.cancel();
      _syncRetry = null;
      _flag(syncOffline: false);
    } catch (e) {
      // Record the deadline before releasing the serial queue to other reads.
      _scheduleSyncRetry(e);
      rethrow;
    }
  });

  Future<void> _syncOnce(int g) async {
    try {
      var inboxWrites = 0;
      for (var attempt = 0; attempt < 4; attempt++) {
        final snap = await _read(g);
        if (snap == null) return;
        var admitted = await _candidate(g);
        if (status != WebSyncStatus.confirmed) return;
        // 1.0.6 (ADR 0009): the inbox for the owner's phone first. A write
        // moves the version: read again. Inbox writes do not spend the
        // conflict attempts (B7), up to two per inbox slot.
        if (await _syncInbox(g, snap)) {
          if (++inboxWrites <= 2 * kMaxWebInboxSlots) attempt--;
          continue;
        }
        if (_stopped) return;
        if (commonStatus == null || commonStatus == RemoteCommonStatus.opened) {
          final beforeRepair = _publicationCandidate!;
          final repaired = reconcileGiverCopies(
            beforeRepair,
            HlcClock(node: auth.deviceId, last: beforeRepair.maxStamp),
          );
          if (!identical(repaired, beforeRepair)) {
            _check(g);
            await queue.add(webDelta(beforeRepair, repaired));
            admitted = await _candidate(g);
          }
        }
        // Old phones can leave live wishes behind a recipient tombstone.
        // Publish their repair through the same version check as queued edits.
        if (admitted.isEmpty && !_needsWishRepair) return;
        _check(g);
        final data = vault.opened.data;
        final sealedCandidate = _publicationCandidate!.canonicalJson();
        final Uint8List bytes;
        if (commonStatus != null) {
          // Format 2: never without a distributed candidate (B6 of the security review).
          // The queue is retained, encrypted, until a mobile fixes it.
          final sealing = _sealing;
          final writer = view?.member(auth.deviceId);
          if (sealing == null || writer == null) return;
          // The revision is saved before sealing, with the keyring.
          final ks = webCommonKeys(data);
          final revision = ks.revision + 1;
          await vault.saveData({
            ...data,
            kWebCommonKeysField: CommonKeyState(
              keyring: ks.keyring,
              revision: revision,
              lastKid: ks.lastKid,
            ).toJson(),
          });
          _check(g);
          bytes = await sealFamilyEnvelope(
            doc: _publicationCandidate!,
            candidate: sealing,
            writer: writer,
            revision: revision,
            signer: await DeviceKeys.fromJson(
              Map<String, Object?>.from(data['deviceKeys'] as Map),
            ),
          );
        } else {
          final key = FamilyKey.fromBase64Url(data['familyKey'] as String);
          bytes = await seal(
            doc: _publicationCandidate!.toJson(),
            listId: listId,
            fromNode: auth.deviceId,
            at: DateTime.now().toUtc().toIso8601String(),
            key: key,
          );
        }
        _check(g);
        // Undo can change the queue while sealing or reconstructing. Observe
        // its registration before expiry and reject a concurrently stale view.
        final undoRevision = _undoRevision;
        final revalidated = await _candidate(g);
        _check(g);
        if (undoRevision != _undoRevision ||
            _publicationCandidate!.canonicalJson() != sealedCandidate ||
            canonicalJsonOf(revalidated) != canonicalJsonOf(admitted)) {
          continue;
        }
        if (!isVisible()) return;
        final put = await transport.putCommon(
          auth,
          version: snap.version,
          common: bytes,
        );
        _check(g);
        if (put is V2WriteStale) continue;
        if (put is V2WriteNotFound) {
          _disconnect();
          return;
        }
        final accepted = (put as V2WriteOk).version;
        // Persist a coherent server snapshot before removing any accepted delta.
        final confirmed = await _read(g);
        if (confirmed == null) return;
        if (confirmed.version < accepted) {
          throw V2RollbackException(known: accepted, served: confirmed.version);
        }
        // Security review, M1: an entry is confirmed only when the common this web
        // could open after the PUT already contains it. A common it cannot
        // open (format 2) or one without the delta keeps the queue.
        if (commonStatus != null && commonStatus != RemoteCommonStatus.opened) {
          await _candidate(g);
          return;
        }
        final saved = await savedCommon();
        final savedJson = saved.canonicalJson();
        final byId = {for (final e in await queue.entries()) e.id: e};
        for (final id in admitted) {
          _check(g);
          final entry = byId[id];
          if (entry == null ||
              saved.merge(entry.delta).canonicalJson() != savedJson) {
            continue;
          }
          await queue.ack(id, confirmation: {'version': accepted});
        }
        await _candidate(g);
        return;
      }
      throw const SyncTransportException(
        SyncFailure.server,
        'too many conflicts',
      );
    } on SyncTransportException catch (e) {
      if (e.failure == SyncFailure.unauthorized) {
        _disconnect();
        return;
      }
      rethrow;
    }
  }

  /// The common document of the saved snapshot (format 1 before the cut,
  /// format 2 opened by `kid` afterwards).
  ///
  /// It enters through the wish boundary (ADR 0010): an old web or phone that
  /// wrote plan fields into the common never reaches the queue, the candidate
  /// or a publication.
  Future<FamilyDoc> savedCommon() async =>
      (await _openSavedCommon()).wishBoundary();

  Future<FamilyDoc> _openSavedCommon() => openSavedCommon(
    vault.opened.data,
    listId: listId,
    syncId: vault.opened.header.syncId,
  );

  Future<V2Snapshot?> _read(int g, {bool announced = false}) async {
    if (!isVisible()) return null;
    // Recover observations from enrollment (including an interrupted commit)
    // before a new GET can replace the only snapshot which contains them.
    final initial = vault.opened.data['snapshot'] as Map;
    final initialDoc = await savedCommon();
    _check(g);
    await queue.blockedPeople(
      remember: {
        ...?initialDoc.collections[Collections.policies]?.keys,
        for (final ref in initial['slots'] as List)
          (ref as Map)['personId'] as String,
      },
    );
    _check(g);
    if (!isVisible()) return null;
    final got = await transport.getList(auth);
    _check(g);
    if (!isVisible()) return null;
    if (got is V2GetNotFound) {
      _disconnect();
      return null;
    }
    if (got is! V2GetOk) {
      throw const SyncTransportException(
        SyncFailure.protocol,
        'snapshot required',
      );
    }
    final s = got.snapshot;
    final data = vault.opened.data;
    final previous = data['snapshot'] as Map?;
    final seen = data[kWebSeenVersionField];
    final floor = [
      previous?['version'] as int? ?? 0,
      if (seen is int) seen,
    ].reduce((a, b) => a > b ? a : b);
    if (s.version < floor) {
      throw V2RollbackException(known: floor, served: s.version);
    }
    // ADR 0005, B5: the format cut-over. A later minimum or local mark needs
    // an update; with [commonV2Ready] this web announces the capability once
    // (it changes the version) so a family with a web can cut.
    final formatFloor = webCommonFloor(data);
    if (s.minCommonFormat > kCommonFormatLatest ||
        formatFloor > kCommonFormatLatest ||
        laterCommonFormat(s.common)) {
      throw const EnvelopeFormatException(
        'la familia usa un formato posterior del común: hay que actualizar',
      );
    }
    final mine = activeCredential(s.devices, auth.deviceId);
    if (commonV2Ready &&
        !announced &&
        mine != null &&
        mine.role == 'web' &&
        mine.commonFormat < kCommonFormatLatest) {
      // Best effort (security review, B3): only a lost credential stops the read; on
      // any other failure this snapshot is read as is and it retries later.
      var sent = false;
      try {
        await transport.announceCommonFormat(auth, kCommonFormatLatest);
        sent = true;
      } on Exception catch (e) {
        if (e is SyncTransportException &&
            e.failure == SyncFailure.unauthorized) {
          rethrow;
        }
      }
      _check(g);
      if (sent) return _read(g, announced: true);
    }
    // Followed by the mark, not by the switch: once set, format 1 is never
    // opened from the network again.
    final format2 =
        formatFloor >= kCommonFormatLatest ||
        s.minCommonFormat >= kCommonFormatLatest;
    if (format2 && !isFamilyEnvelope(s.common)) {
      // The Worker never allows it: a lying server.
      throw const SyncTransportException(
        SyncFailure.protocol,
        'el servidor pide el formato 2 con un común que no lo es',
      );
    }
    final roots = pinnedRoots(data['roots']);
    RegistryView? selected;
    DeviceRegistry? registry;
    RegistryView? revokedRootView;
    for (final root in roots) {
      if (revokedRootView != null) {
        final next = revokedRootView.member(root.deviceId);
        if (next == null ||
            next.kind != DeviceKind.mobile ||
            !constantTimeEquals(next.signingKey, root.signingKey)) {
          continue;
        }
      }
      try {
        var reg = await DeviceRegistry.fromJsonVerified(
          s.registry,
          anchor: root,
        );
        // Only authenticated local conflict memory is carried over; never
        // interpret network JSON as local-store JSON.
        if (data['registryLocal'] != null) {
          final old = await DeviceRegistry.fromLocalStoreJson(
            data['registryLocal'],
            anchor: root,
          );
          reg = await old.merge(reg, anchor: root);
        }
        _check(g);
        final v = await reg.viewFor(
          me: root.deviceId,
          mySigningKey: root.signingKey,
          livePeople: const {},
        );
        if (v.self.kind != DeviceKind.mobile) continue;
        if (v.revokedByOthers) {
          revokedRootView = v;
          continue;
        }
        selected = v;
        registry = reg;
        break;
      } on RegistryException {
        continue;
      }
    }
    _check(g);
    if (selected != null &&
        webStatusIn(selected, auth.deviceId) == WebDeviceStatus.revoked) {
      _disconnect();
      return null;
    }
    var key = FamilyKey.fromBase64Url(data['familyKey'] as String);
    final keys = await DeviceKeys.fromJson(
      Map<String, Object?>.from(data['deviceKeys'] as Map),
    );
    final recipient = selected?.member(auth.deviceId);
    status =
        selected != null &&
            webStatusIn(selected, auth.deviceId) == WebDeviceStatus.confirmed &&
            recipient != null &&
            constantTimeEquals(recipient.signingKey, keys.publicKeys.signing) &&
            constantTimeEquals(
              recipient.agreementKey,
              keys.publicKeys.agreement,
            )
        ? WebSyncStatus.confirmed
        : WebSyncStatus.pending;
    if (format2) {
      return _readFormat2(
        g,
        s,
        data: data,
        keys: keys,
        selected: selected,
        registry: registry,
        formatFloor: formatFloor,
      );
    }
    commonStatus = null;
    _sealing = null;
    if (status == WebSyncStatus.confirmed) {
      final bundles = <KeyBundle>[];
      for (final raw in s.keyPackages) {
        try {
          final b = KeyBundle.fromJson(raw);
          if (b.scope == KeyScope.family && b.toDevice == auth.deviceId) {
            bundles.add(b);
          }
        } on KeyBundleException {
          /* Untrusted package. */
        }
      }
      bundles.sort((a, b) => a.epoch.compareTo(b.epoch));
      for (final b in bundles) {
        try {
          key = await b.openFamilyKey(mine: keys, view: selected!);
        } on KeyBundleException {
          /* Never open surprise packages. */
        }
      }
    }
    final opened = await envelope.open(
      s.common,
      key: key,
      expectedListId: listId,
    );
    final remote = FamilyDoc.fromJson(opened.doc);
    _check(g);
    if (selected != null) {
      selected = await registry!.viewFor(
        me: selected.me,
        mySigningKey: selected.self.signingKey,
        livePeople: livePeopleOf(remote),
      );
    }
    final newRoots = selected == null
        ? <RegistryAnchor>[]
        : [
            for (final id in selected.members)
              if (selected.member(id)!.kind == DeviceKind.mobile)
                RegistryAnchor(
                  deviceId: id,
                  signingKey: selected.member(id)!.signingKey,
                ),
          ];
    await queue.blockedPeople(
      remember: {
        ...?remote.collections[Collections.policies]?.keys,
        for (final ref in s.slots) ref.personId,
      },
    );
    _check(g);
    await vault.saveData({
      ...data,
      'familyKey': key.toBase64Url(),
      if (selected != null) 'roots': newRoots.map(rootJson).toList(),
      'snapshot': snapshotJson(s),
      if (selected != null && registry != null)
        'registryLocal': registry.toLocalStoreJson(),
    });
    _check(g);
    await _refreshSecrets(g, s, registry, selected, keys);
    version = s.version;
    view = selected;
    return s;
  }

  /// [_read] once the family uses the common format 2 (ADR 0005, B5): opens
  /// the v4 packages for this web into the keyring of the vault, opens the
  /// remote common by `kid` with [commonWriterResolver] and saves keyring,
  /// registry, roots and the snapshot reference in one vault write. A remote
  /// common it cannot open is never merged nor replaced: the saved snapshot
  /// stays, the queue is retained and nothing is published.
  Future<V2Snapshot?> _readFormat2(
    int g,
    V2Snapshot s, {
    required VaultJson data,
    required DeviceKeys keys,
    required RegistryView? selected,
    required DeviceRegistry? registry,
    required int formatFloor,
  }) async {
    final syncId = auth.syncId;
    var ks = webCommonKeys(data);
    FamilyEnvelopeHeader? peeked;
    try {
      peeked = peekFamilyEnvelope(s.common);
    } on EnvelopeException {
      peeked = null;
    }
    final wanted = <String>{?peeked?.kid, ?ks.lastKid};
    var keyring = ks.keyring;
    var keyringFull = false;
    if (selected != null && registry != null) {
      // Only v4 packages addressed to this web; surprises are never opened.
      if (status == WebSyncStatus.confirmed) {
        final view = selected;
        for (final raw in s.keyPackages) {
          if (!FamilyKeyBundle.isV4(raw) || raw['to'] != auth.deviceId) {
            continue;
          }
          final kid = raw['kid'];
          final known = kid is String ? keyring.entry(kid) : null;
          if (known != null &&
              (known.own ||
                  known.senders.length >= kMaxCandidateSenders ||
                  known.senders.any((m) => m.deviceId == raw['from']))) {
            continue;
          }
          try {
            final bundle = FamilyKeyBundle.fromJson(raw);
            final candidate = await bundle.open(
              mine: keys,
              view: view,
              registry: registry,
              syncId: syncId,
            );
            keyring = keyring.withReceivedCandidate(
              candidate,
              from: bundle.fromDevice,
              fromRecord: bundle.senderRecord,
              sealable: (c) => c.sealableIn(view, syncId: syncId),
              wanted: wanted,
            );
          } on FamilyKeyringFullException {
            keyringFull = true;
          } on KeyBundleException {
            continue;
          } on FamilyKeyException {
            continue;
          }
          _check(g);
        }
      }
      keyring = trimCommonKeyring(
        keyring.pruneRevoked(selected, wanted: wanted),
        selected,
        syncId: syncId,
        wanted: wanted,
      );
    }

    // The remote common: only a verified active member's signature counts.
    var remoteStatus = RemoteCommonStatus.forged;
    var verified = false;
    FamilyDoc? remote;
    List<int>? writerKey;
    if (peeked != null && selected != null && registry != null) {
      final resolve = commonWriterResolver(selected, registry);
      if (reallyRevoked(selected, peeked.writer)) {
        remoteStatus = RemoteCommonStatus.revokedWriter;
      } else {
        try {
          await verifyFamilyEnvelope(
            s.common,
            expectedListId: listId,
            expectedSyncId: syncId,
            resolveWriter: resolve,
          );
          verified = true;
        } on EnvelopeUnknownWriterException {
          remoteStatus = RemoteCommonStatus.unknownWriter;
        } on EnvelopeException {
          remoteStatus = RemoteCommonStatus.forged;
        }
        if (verified) {
          try {
            final opened = await openFamilyEnvelope(
              s.common,
              expectedListId: listId,
              expectedSyncId: syncId,
              resolveWriter: resolve,
              keyring: keyring,
            );
            writerKey = await resolve(peeked.writer, peeked.writerRecord);
            remote = opened.doc;
            remoteStatus = RemoteCommonStatus.opened;
          } on EnvelopeMissingKeyException {
            remoteStatus = RemoteCommonStatus.missingKey;
          } on EnvelopeException {
            remoteStatus = RemoteCommonStatus.unreadable;
          }
        }
      }
    } else if (peeked != null) {
      // No pinned root verifies the registry: nobody can be authenticated.
      remoteStatus = RemoteCommonStatus.unknownWriter;
    }
    _check(g);
    // Following the cut: the irreversible mark only after a verified active
    // member's signature on a format 2 common (the minimum is not signed).
    final raise = formatFloor < kCommonFormatLatest;
    if (raise && !verified) {
      throw const SyncTransportException(
        SyncFailure.protocol,
        'el común del formato 2 no lo firma un miembro activo',
      );
    }
    if (remote != null && syncProtocolOf(remote) == null) {
      throw const EnvelopeFormatException('documento de otro protocolo');
    }
    final opened = remote != null;
    final lastKid = opened ? peeked!.kid : ks.lastKid;
    ks = CommonKeyState(
      keyring: withCommonReferences(
        keyring,
        lastKid: lastKid,
        outbox: const [],
        retained: const [],
      ),
      revision: ks.revision,
      lastKid: lastKid,
    );
    var current = selected;
    if (current != null) {
      // People of the opened common or, while it waits, of the saved one.
      current = await registry!.viewFor(
        me: current.me,
        mySigningKey: current.self.signingKey,
        livePeople: livePeopleOf(
          remote ?? await openSavedCommon(data, listId: listId, syncId: syncId),
        ),
      );
      _check(g);
    }
    final newRoots = current == null
        ? <RegistryAnchor>[]
        : [
            for (final id in current.members)
              if (current.member(id)!.kind == DeviceKind.mobile)
                RegistryAnchor(
                  deviceId: id,
                  signingKey: current.member(id)!.signingKey,
                ),
          ];
    await queue.blockedPeople(
      remember: {
        ...?remote?.collections[Collections.policies]?.keys,
        for (final ref in s.slots) ref.personId,
      },
    );
    _check(g);
    await vault.saveData({
      ...data,
      kWebCommonKeysField: ks.toJson(),
      if (raise) kWebCommonFloorField: kCommonFormatLatest,
      // Security review, B2: only after a member's verified signature. The version
      // is not signed: this only keeps the number from going down.
      if (verified) kWebSeenVersionField: s.version,
      if (current != null) 'roots': newRoots.map(rootJson).toList(),
      if (opened)
        'snapshot': {
          ...snapshotJson(s),
          kWebWriterKeyField: encodeBase64Url(writerKey!),
        },
      if (current != null && registry != null)
        'registryLocal': registry.toLocalStoreJson(),
    });
    _check(g);
    commonStatus = remoteStatus;
    commonKeyringFull = keyringFull;
    _sealing = opened && status == WebSyncStatus.confirmed && current != null
        ? await webSealingCandidate(
            keyring: ks.keyring,
            remoteKid: peeked!.kid,
            writer: peeked.writer,
            view: current,
            registry: registry!,
            syncId: syncId,
            me: auth.deviceId,
            packages: s.keyPackages,
          )
        : null;
    _check(g);
    await _refreshSecrets(g, s, registry, current, keys);
    version = s.version;
    view = current;
    return s;
  }

  /// Rebuilds the screen view and the session surprises from snapshot [s]
  /// (1.0.6, ADR 0009). [root] is the verified phone view of this read.
  Future<void> _refreshSecrets(
    int g,
    V2Snapshot s,
    DeviceRegistry? registry,
    RegistryView? root,
    DeviceKeys keys,
  ) async {
    screenView = null;
    phonePeople = const {};
    if (registry == null || root == null) {
      secrets.clear();
      return;
    }
    try {
      screenView = await registry.viewFor(
        me: auth.deviceId,
        mySigningKey: keys.publicKeys.signing,
        livePeople: root.livePeople,
      );
    } on RegistryException {
      screenView = null;
    }
    _check(g);
    final screen = screenView;
    if (screen != null) phonePeople = webPhonePeople(registry, screen);
    if (status != WebSyncStatus.confirmed) {
      secrets.clear();
      return;
    }
    await secrets.refresh(
      snap: s,
      registry: registry,
      root: root,
      webDeviceId: auth.deviceId,
      keys: keys,
      transport: transport,
      auth: auth,
      check: () => _check(g),
    );
  }

  // ----------------------------------------------------------------------
  // ADR 0010 (1.0.7): own wishes and wish plans from the web.

  /// The person of this web (its record), or null: with it the web paints the
  /// fixed «Sorpresas» block for that person from the start, whether or not
  /// anything is inside or the keys are open (ADR 0010, decision 5). The
  /// block never depends on the secrets: do not derive it from them.
  String? get ownPersonId => vault.opened.data['personId'] as String?;

  /// Whether the screen must show the fixed «Sorpresas» block of this web's
  /// own person (see [ownPersonId]).
  bool get showsOwnSurprisesBlock => ownPersonId != null;

  /// The public common (see [_commonDoc]); null before the first candidate.
  FamilyDoc? get publicDoc => _commonDoc;

  /// The newest stamp the public clock must follow: only the saved common and
  /// the public actions in the queue. Opened secrets, inbox changes and plans
  /// never enter it, so a private edit cannot move the next public stamp.
  Hlc? get publicStamp => _commonDoc?.maxStamp;

  /// A clock for public actions of this web (wishes, gifts...).
  HlcClock newPublicClock() =>
      HlcClock(node: auth.deviceId, last: publicStamp);

  /// The newest stamp of the private scope of [personId]: what the phones
  /// wrote in it plus the changes of this web waiting for its inbox. Kept
  /// apart from [publicStamp].
  Hlc? scopeStamp(String personId) {
    Hlc? newest = secrets.opened[personId]?.doc.maxStamp;
    for (final entry in _inbox[personId] ?? const <PendingEntry>[]) {
      final stamp = entry.delta.maxStamp;
      if (stamp != null && (newest == null || stamp > newest)) newest = stamp;
    }
    return newest;
  }

  /// A clock for private changes of the scope of [personId].
  HlcClock newScopeClock(String personId) =>
      HlcClock(node: auth.deviceId, last: scopeStamp(personId));

  /// Ids of the gifts that only exist in opened scopes or the inbox: they are
  /// never part of the public clock.
  Set<String> get secretGiftIds => {
    for (final scope in secrets.opened.values)
      ...?scope.doc.collections[Collections.gifts]?.keys,
    for (final list in _inbox.values)
      for (final e in list)
        ...?e.delta.collections[Collections.gifts]?.keys,
  };

  /// [doc] without the gifts that only exist in opened scopes or the inbox:
  /// what a public clock may follow.
  FamilyDoc withoutSecrets(FamilyDoc doc) {
    final secret = secretGiftIds;
    final gifts = doc.collections[Collections.gifts];
    if (secret.isEmpty || gifts == null) return doc;
    return FamilyDoc(
      listId: doc.listId,
      collections: {
        ...doc.collections,
        Collections.gifts: {
          for (final e in gifts.entries)
            if (!secret.contains(e.key)) e.key: e.value,
        },
      },
    );
  }

  /// The private scope of [personId] as the web sees it: what its phones
  /// wrote plus the web's own changes waiting for its inbox (gifts and wish
  /// plans). Null unless that person's surprises are open. Never exists for
  /// the web's own person.
  FamilyDoc? scopeDocFor(String personId) {
    if (_commonDoc?.record(Collections.recipients, personId)?.isDeleted ==
        true) {
      return null;
    }
    final opened = secrets.opened[personId];
    if (opened == null) return null;
    var scope = opened.doc;
    for (final entry in _inbox[personId] ?? const <PendingEntry>[]) {
      scope = scope.merge(_scopeBits(entry.delta, scope.listId));
    }
    return scope;
  }

  /// The wish rows of [personId] with their plans (claimed, in conflict,
  /// removed from the list). Empty unless that person's surprises are open.
  List<WishPlanRow> wishPlanRows(String personId) {
    final scope = scopeDocFor(personId);
    final common = _commonDoc;
    if (scope == null || common == null) return const [];
    return deriveWishPlanRows(
      common: common,
      scope: scope,
      recipientId: personId,
    );
  }

  /// The context that resolves the author of a wish from this web's record:
  /// the phone view that vouches it ([WishContext.web]). Null if there is no
  /// such view yet.
  Future<WishContext?> wishContext() async {
    final root = secrets.view ?? view;
    if (root == null) return null;
    final keys = await DeviceKeys.fromJson(
      Map<String, Object?>.from(vault.opened.data['deviceKeys'] as Map),
    );
    return WishContext.web(
      rootView: () => secrets.view ?? view ?? root,
      webDeviceId: auth.deviceId,
      webKeys: keys,
    );
  }

  /// Creates an own wish of this web's person, queued as a public change.
  /// Works without any surprise key (the web of P never opens P's).
  Future<WishWrite> createOwnWish(VisibleWishPatch patch, {String? id}) =>
      _ownWishAction((doc, clock, ctx) => doc.createOwnWish(clock, ctx, patch, id: id));

  /// Edits an own wish, queued as a public change.
  Future<WishWrite> editOwnWish(String wishId, VisibleWishPatch patch) =>
      _ownWishAction((doc, clock, ctx) => doc.editVisibleWish(clock, ctx, wishId, patch));

  /// Removes an own wish (a tombstone), queued as a public change.
  Future<WishWrite> removeOwnWish(String wishId) =>
      _ownWishAction((doc, clock, ctx) => doc.removeWish(clock, ctx, wishId));

  Future<WishWrite> _ownWishAction(
    WishWrite Function(FamilyDoc doc, HlcClock clock, WishContext ctx) act,
  ) => _serial((g) async {
    final ctx = await wishContext();
    final before = _commonDoc;
    if (ctx == null || before == null) {
      throw const WebOperationException('wishUnavailable');
    }
    _check(g);
    final write = act(before, newPublicClock(), ctx);
    if (!write.ok) return write;
    _validateOwnWishes(before, write.doc, ctx);
    await _save(g, before, write.doc, ownWishes: true);
    return write;
  });

  /// The web writes only wishes of its own person, as it resolves from its
  /// record: new ones are not suggestions, nothing changes recipient or
  /// author, and a dead wish stays dead.
  void _validateOwnWishes(FamilyDoc before, FamilyDoc after, WishContext ctx) {
    final author = ctx.resolve(listId);
    if (!author.ok) throw const WebOperationException('wishAuthor');
    final person = author.author!.personId;
    final delta = webDelta(before, after);
    for (final r in delta.collections[Collections.wishes]?.values ??
        const <SyncRecord>[]) {
      final result = after.record(Collections.wishes, r.id)!;
      final old = before.record(Collections.wishes, r.id);
      var ok = validateWishRecord(result) == null;
      if (old == null) {
        ok =
            ok &&
            !result.isDeleted &&
            result['recipientId'] == person &&
            result['authorPersonId'] == person &&
            result['suggested'] == false;
      } else {
        ok = ok && !old.isDeleted && old['recipientId'] == person;
        if (ok && !result.isDeleted) {
          for (final name in const [
            'recipientId',
            'authorPersonId',
            'suggested',
          ]) {
            ok = ok && result[name] == old[name];
          }
        }
      }
      if (!ok) throw const WebOperationException('wishInvalid');
    }
  }

  /// Takes a wish of someone else for this web's person: a private plan for
  /// that person's inbox (W5). Needs that person's surprises open.
  Future<WishPlanWrite> claimWish(
    String wishId, {
    String? giverId,
    String? planId,
  }) {
    final recipient = _commonDoc?.record(Collections.wishes, wishId)?[
      'recipientId'
    ];
    return _planAction(
      recipient is String ? recipient : null,
      (scope, clock, view, common) => scope.claimWish(
        clock,
        view,
        common,
        wishId,
        planId: planId,
        giverId: giverId,
      ),
    );
  }

  /// Edits a plan of this web's person.
  Future<WishPlanWrite> editPlan(
    String personId,
    String planId,
    PrivatePlanPatch patch,
  ) => _planAction(
    personId,
    (scope, clock, view, _) => scope.editPlan(clock, view, planId, patch),
  );

  /// Releases a plan of this web's person (the wish becomes available).
  Future<WishPlanWrite> releasePlan(String personId, String planId) =>
      _planAction(
        personId,
        (scope, clock, view, _) => scope.releasePlan(clock, view, planId),
      );

  /// Whether every phone entitled to read [personId]'s surprises announces it
  /// understands wish plans (a 1.0.6 would reject the whole scope, gifts
  /// included). False without the surprises open.
  bool wishPlansAllowedFor(String personId) {
    final v = secrets.view;
    final opened = secrets.opened[personId];
    if (v == null || opened == null) return false;
    return wishPlansAllowed([
      for (final device in v.entitledDevices(personId)) opened.parts[device],
    ]);
  }

  Future<WishPlanWrite> _planAction(
    String? personId,
    WishPlanWrite Function(
      FamilyDoc scope,
      HlcClock clock,
      RegistryView view,
      FamilyDoc common,
    )
    act,
  ) => _serial((g) async {
    final view = secrets.view;
    final common = _commonDoc;
    final scope = personId == null ? null : scopeDocFor(personId);
    if (personId == null ||
        view == null ||
        common == null ||
        scope == null ||
        !secrets.writablePeople.contains(personId)) {
      return WishPlanWrite.failed(
        scope ?? FamilyDoc.empty(listId),
        WishPlanError.unavailable,
      );
    }
    if (!wishPlansAllowedFor(personId)) {
      return WishPlanWrite.failed(scope, WishPlanError.devicesNeedUpdate);
    }
    final write = act(scope, newScopeClock(personId), view, common);
    if (!write.ok) return write;
    final delta = webDelta(scope, write.scope);
    for (final c in delta.collections.entries) {
      if (c.value.isNotEmpty && c.key != ScopeCollections.wishPlans) {
        throw const WebOperationException('restrictedDocument');
      }
    }
    final plans = delta.collections[ScopeCollections.wishPlans];
    if (plans == null || plans.isEmpty) return write;
    _check(g);
    await queue.add(
      delta,
      kind: PendingKind.privateScope,
      inboxPerson: personId,
      newPlans: {
        for (final id in plans.keys)
          if (scope.record(ScopeCollections.wishPlans, id) == null) id,
      },
    );
    _check(g);
    await _candidate(g);
    return write;
  });

  /// The scope collections of [delta] (gifts and wish plans) as a document.
  FamilyDoc _scopeBits(FamilyDoc delta, String listId) => FamilyDoc(
    listId: listId,
    collections: {
      Collections.gifts: delta.collections[Collections.gifts] ?? const {},
      if ((delta.collections[ScopeCollections.wishPlans] ?? const {})
          .isNotEmpty)
        ScopeCollections.wishPlans:
            delta.collections[ScopeCollections.wishPlans]!,
    },
  );

  /// The only person whose protected gifts [entry] touches, if it touches
  /// nothing but gifts of exactly one person who is not this web's: then it
  /// goes to that person's inbox. Null otherwise (set aside).
  String? _inboxPerson(PendingEntry entry, FamilyDoc common) {
    for (final c in entry.delta.collections.entries) {
      if (c.value.isNotEmpty && c.key != Collections.gifts) return null;
    }
    final gifts = entry.delta.collections[Collections.gifts];
    if (gifts == null || gifts.isEmpty) return null;
    final people = <String>{};
    for (final r in gifts.values) {
      people.addAll(entry.giftPeople[r.id] ?? const []);
      for (final id in [
        r['recipientId'],
        common.record(Collections.gifts, r.id)?['recipientId'],
      ]) {
        if (id is String) people.add(id);
      }
    }
    if (people.length != 1) return null;
    final person = people.single;
    final mine = vault.opened.data['personId'];
    if (person == mine || person == secrets.person) return null;
    return person;
  }

  /// What the web shows and edits with surprises open: the common lane, the
  /// opened scopes with the inbox entries on top, without the gifts of a
  /// protected person it cannot open and without its own person's.
  FamilyDoc _secretCandidate(
    FamilyDoc common,
    Map<String, List<PendingEntry>> inbox,
  ) {
    final gifts = <String, SyncRecord>{
      ...?common.collections[Collections.gifts],
    };
    final secretIds = <String>{};
    for (final e in secrets.opened.entries) {
      if (common.record(Collections.recipients, e.key)?.isDeleted == true) {
        continue;
      }
      var scope = e.value.doc;
      for (final entry in inbox[e.key] ?? const <PendingEntry>[]) {
        scope = scope.merge(
          FamilyDoc(
            listId: scope.listId,
            collections: {
              Collections.gifts:
                  entry.delta.collections[Collections.gifts] ?? const {},
            },
          ),
        );
      }
      for (final record
          in scope.collections[Collections.gifts]?.values ??
              const <SyncRecord>[]) {
        gifts[record.id] = record;
        if (!record.isDeleted) secretIds.add(record.id);
      }
    }
    final v = secrets.view;
    final protected = <String>{
      for (final e in publishedPolicies(common).entries)
        if (e.value.hideOwnGifts) e.key,
      if (v != null)
        for (final p in secrets.slots.people)
          if (secrets.slots.authenticatedPolicy(p, v)?.hideOwnGifts == true) p,
      ...secrets.opened.keys,
    };
    final own = screenHiddenPeople;
    gifts.removeWhere(
      (id, record) =>
          (protected.contains(record['recipientId']) &&
              !secretIds.contains(id)) ||
          own.contains(record['recipientId']),
    );
    return FamilyDoc(
      listId: common.listId,
      collections: {...common.collections, Collections.gifts: gifts},
    );
  }

  Map<String, List<({int epoch, int revision, Set<String> ids})>>
  _inboxHistory() {
    final raw = vault.opened.data[kWebInboxField];
    return {
      if (raw is Map)
        for (final e in raw.entries)
          if (e.key is String && e.value is List)
            e.key as String: [
              for (final item in e.value as List)
                if (item is Map &&
                    item['e'] is int &&
                    item['r'] is int &&
                    item['ids'] is List)
                  (
                    epoch: item['e'] as int,
                    revision: item['r'] as int,
                    ids: {...(item['ids'] as List).whereType<String>()},
                  ),
            ],
    };
  }

  Future<void> _saveInboxHistory(
    int g,
    Map<String, List<({int epoch, int revision, Set<String> ids})>> history,
  ) async {
    await vault.saveData({
      ...vault.opened.data,
      kWebInboxField: {
        for (final e in history.entries)
          if (e.value.isNotEmpty)
            e.key: [
              for (final h in e.value)
                {'e': h.epoch, 'r': h.revision, 'ids': (h.ids.toList()..sort())},
            ],
      },
    });
    _check(g);
  }

  int _inboxRevision(String person) {
    final raw = vault.opened.data[kWebInboxRevisionField];
    final r = raw is Map ? raw[person] : null;
    return r is int ? r : 0;
  }

  Future<void> _saveInboxRevision(int g, String person, int revision) async {
    final raw = vault.opened.data[kWebInboxRevisionField];
    await vault.saveData({
      ...vault.opened.data,
      kWebInboxRevisionField: {
        if (raw is Map)
          for (final e in raw.entries)
            if (e.key is String && e.value is int) e.key as String: e.value,
        person: max(revision, _inboxRevision(person)),
      },
    });
    _check(g);
  }

  /// One inbox write. A refusal the web cannot fix by retrying soon (cap,
  /// size, renewal freeze, an old Worker without the route...) holds that
  /// inbox for [kWebInboxHold] and returns null, so the common still
  /// publishes (security review, M3). Network, server, rate and credential
  /// failures go up as always.
  Future<V2WriteResult?> _putInbox(
    int g,
    V2Snapshot snap,
    String person,
    Uint8List? data,
  ) async {
    try {
      final put = await transport.putWebSlot(
        auth,
        version: snap.version,
        personId: person,
        data: data,
      );
      _check(g);
      if (put is V2WriteOk) _inboxHeld.remove(person);
      return put;
    } on SyncTransportException catch (e) {
      _check(g);
      if (const {
        SyncFailure.network,
        SyncFailure.server,
        SyncFailure.rateLimited,
        SyncFailure.unauthorized,
      }.contains(e.failure)) {
        rethrow;
      }
      _inboxHeld[person] = now().add(kWebInboxHold);
      onError?.call(e);
      return null;
    }
  }

  /// Confirms, seals or removes this web's inbox slots (1.0.6, ADR 0009,
  /// A.8.5). An entry is confirmed when a slot of a phone of the web's
  /// person already holds it, or declares (`s[web]`) an inbox that held it.
  /// Returns true after a write (the version moved).
  bool _entryHasPlans(PendingEntry e) =>
      (e.delta.collections[ScopeCollections.wishPlans] ?? const {}).isNotEmpty;

  Future<bool> _syncInbox(int g, V2Snapshot snap) async {
    final v = secrets.view;
    final me = auth.deviceId;
    final history = _inboxHistory();
    final ownSlots = {
      for (final ref in snap.slots)
        if (ref.deviceId == me) ref.personId,
    };
    FamilyDoc? confirmed;
    var acked = false;
    final people = {
      ..._inbox.keys,
      ...history.keys,
      ...ownSlots,
    }.toList()..sort();
    for (final person in people) {
      final held = _inboxHeld[person];
      final waitHeld = held != null && now().isBefore(held);
      if (_commonDoc?.record(Collections.recipients, person)?.isDeleted ==
          true) {
        final common = confirmed ??= await savedCommon();
        _check(g);
        if (common.record(Collections.recipients, person)?.isDeleted != true) {
          continue;
        }
        _heldPlans.remove(person);
        if (history.remove(person) != null) await _saveInboxHistory(g, history);
        if (ownSlots.contains(person) && !waitHeld) {
          final put = await _putInbox(g, snap, person, null);
          if (put is V2WriteNotFound) {
            _disconnect();
            return false;
          }
          if (put != null) return true;
        }
        continue;
      }
      if (v == null || secrets.person == null) continue;
      final opened = secrets.opened[person];
      if (opened == null) continue;
      final all = _inbox[person] ?? const <PendingEntry>[];
      final phones = [
        for (final part in opened.parts.entries)
          if (part.key != me && secrets.ownPhone(part.key)) part.value,
      ];
      final past = history[person] ?? const [];
      final remaining = <PendingEntry>[];
      for (final entry in all) {
        if (entry.publishAfter != null) continue;
        final gifts = _scopeBits(entry.delta, opened.doc.listId);
        final inSlot = phones.any(
          (part) =>
              part.doc.merge(gifts).canonicalJson() ==
              part.doc.canonicalJson(),
        );
        // Match the exact revision declared in `s[web]`. An inbox recorded
        // before a failed PUT may never have reached the server. Entries in
        // a replaced inbox stay pending until a phone declares a revision
        // that included them (A-1). A rejection (`x[web]`) drops them with a
        // notice (B3). Plan declarations also carry proof that the reader of
        // that revision understood plans, even after relay or upgrade (B-1).
        final withPlans = _entryHasPlans(entry);
        var declared = false;
        var rejected = true;
        for (final part in phones) {
          final seen = part.seen[me];
          if (seen == null) continue;
          if (withPlans &&
              (part.wishPlans < kWishPlanCapability ||
                  part.planInboxSeen[me] != seen)) {
            continue;
          }
          ({int epoch, int revision, Set<String> ids})? read;
          for (final h in past) {
            if (h.epoch == seen.epoch && h.revision == seen.revision) {
              read = h;
              break;
            }
          }
          if (read == null || !read.ids.contains(entry.id)) continue;
          declared = true;
          if (part.rejectedInboxes[me] != seen) {
            rejected = false;
          }
        }
        if (inSlot || (declared && !rejected)) {
          await queue.ack(entry.id, confirmation: {'inbox': person});
          _check(g);
          acked = true;
        } else if (declared) {
          await queue.ack(
            entry.id,
            confirmation: {'inbox': person, 'dropped': true, 'rejected': true},
          );
          _check(g);
          discardedSecretCount++;
          acked = true;
        } else {
          remaining.add(entry);
        }
      }
      final waiting = all.any((e) => e.publishAfter != null);
      if (!secrets.writablePeople.contains(person) || waitHeld) continue;
      // Gifts and wish plans never share an inbox (security review, A1/B3):
      // a phone that cannot read plans rejects the whole inbox, so a plan
      // can never take gift edits with it. Gift changes go first; plans
      // follow once none is left waiting.
      final plansAllowed = wishPlansAllowedFor(person);
      WebInboxBuild? build;
      var heldNow = 0;
      var deferredAny = false;
      for (final group in [
        [for (final e in remaining) if (!_entryHasPlans(e)) e],
        [for (final e in remaining) if (_entryHasPlans(e)) e],
      ]) {
        if (group.isEmpty) continue;
        final next = buildWebInbox(
          personId: person,
          scope: opened.doc,
          webPersonId: secrets.person,
          plansAllowed: plansAllowed,
          entries: [
            for (final e in group)
              WebInboxEntry(
                id: e.id,
                delta: e.delta,
                newGifts: e.newGifts,
                newPlans: e.newPlans,
              ),
          ],
        );
        for (final id in [...next.moot, ...next.discarded]) {
          await queue.ack(id, confirmation: {'inbox': person, 'dropped': true});
          _check(g);
          acked = true;
        }
        discardedSecretCount += next.discarded.length;
        heldNow += next.held.length;
        deferredAny = deferredAny || next.deferred.isNotEmpty;
        build = next;
        if (!next.isEmpty) break;
      }
      if (heldNow > 0) {
        _heldPlans[person] = heldNow;
      } else {
        _heldPlans.remove(person);
      }
      build ??= buildWebInbox(
        personId: person,
        scope: opened.doc,
        entries: const [],
      );
      final onServer = secrets.ownInbox.containsKey(person);
      if (build.isEmpty) {
        if (!waiting && !deferredAny) {
          if (history.remove(person) != null) await _saveInboxHistory(g, history);
          if (onServer) {
            final put = await _putInbox(g, snap, person, null);
            if (put == null) continue;
            if (put is V2WriteNotFound) {
              _disconnect();
              return false;
            }
            return true;
          }
        }
        continue;
      }
      final matching = [
        for (final h in past)
          if (h.ids.length == build.included.length &&
              h.ids.containsAll(build.included))
            SlotVersion(h.epoch, h.revision),
      ];
      if (onServer && matching.isNotEmpty) {
        // A restart may remember an attempted replacement alongside the
        // old published inbox. Only the server's actual revision can match.
        final published = await transport.getSlot(
          auth,
          version: snap.version,
          personId: person,
          deviceId: me,
        );
        _check(g);
        if (published is V2SlotStale) return true;
        if (published is V2SlotOk) {
          try {
            final slot = SealedSlot.parse(published.data);
            final writer = v.member(me);
            if (writer != null &&
                slot.header.listId == listId &&
                slot.header.personId == person &&
                slot.header.writer == me &&
                matching.contains(slot.header.version)) {
              final signed = await slot.verifySignature(writer.signingKey);
              _check(g);
              if (signed) continue;
            }
          } on ProtectedEnvelopeException {
            // Replace a slot whose revision cannot be read.
          }
        }
      }
      if (!onServer && secrets.ownInbox.length >= kMaxWebInboxSlots) continue;
      final key = secrets.sealingKeyFor(person);
      final policy = opened.authenticatedPolicy;
      if (key == null || policy == null) continue;
      final SealedSlot slot;
      try {
        slot = await SealedSlot.seal(
          writerKeys: await DeviceKeys.fromJson(
            Map<String, Object?>.from(vault.opened.data['deviceKeys'] as Map),
          ),
          writer: me,
          revision: max(
            now().millisecondsSinceEpoch,
            max(
                  past.isEmpty ? 0 : past.map((h) => h.revision).reduce(max),
                  _inboxRevision(person),
                ) +
                1,
          ),
          key: key,
          policy: policy,
          doc: build.doc,
        );
      } on ProtectedEnvelopeException {
        continue;
      } on ArgumentError {
        continue;
      }
      _check(g);
      // The history goes first: an inbox may enter without an answer.
      final kept = [
        ...past,
        (
          epoch: slot.header.epoch,
          revision: slot.header.revision,
          ids: build.included.toSet(),
        ),
      ];
      history[person] = kept.length > 16
          ? kept.sublist(kept.length - 16)
          : kept;
      await _saveInboxHistory(g, history);
      await _saveInboxRevision(g, person, slot.header.revision);
      _flag(uploading: true);
      final put = await _putInbox(g, snap, person, slot.bytes);
      if (put == null) continue;
      if (put is V2WriteStale) {
        // This replacement definitely failed. Keep the earlier history,
        // including the revision the server may still be serving.
        history[person] = past;
        await _saveInboxHistory(g, history);
        return true;
      }
      if (put is V2WriteNotFound) {
        _disconnect();
        return false;
      }
      return true;
    }
    if (acked) await _candidate(g);
    return false;
  }

  Iterable<String> _deletedPeople(PendingEntry entry) =>
      (entry.delta.collections[Collections.recipients] ?? const {}).values
          .where((record) => record.isDeleted)
          .map((record) => record.id);

  bool _canDeletePeople(Iterable<String> people) {
    final registry = view;
    return registry != null &&
        !people.any((id) => _hasConnectedDevice(registry, id));
  }

  bool _hasConnectedDevice(RegistryView registry, String personId) =>
      personId == vault.opened.data['personId'] ||
      registry.members.any((id) => registry.member(id)!.personId == personId);

  Future<List<String>> _candidate(int g) async {
    final data = vault.opened.data;
    final snapshot = data['snapshot'] as Map;
    final raw = await _openSavedCommon();
    _needsWishRepair = !identical(
      raw.tombstoneWishesForDeletedRecipients(),
      raw,
    );
    final confirmed = raw.wishBoundary();
    var doc = confirmed;
    var publication = doc;
    final blocked = await queue.blockedPeople(
      remember: {
        ...?doc.collections[Collections.policies]?.keys,
        for (final r in snapshot['slots'] as List)
          (r as Map)['personId'] as String,
      },
    );
    final entries = await queue.entries(expireUndoAt: now());
    final admitted = <String>[];
    final inbox = <String, List<PendingEntry>>{};
    var held = 0;
    DateTime? deadline;
    _undoDeadline?.cancel();
    setAsideCount = 0;
    rejectedSecretRecipientDeletes = 0;
    final rejectedDeviceNames = <String>[];
    for (final entry in entries) {
      _check(g);
      final target = entry.inboxPerson;
      if (target != null &&
          confirmed.record(Collections.recipients, target)?.isDeleted == true) {
        await queue.ack(
          entry.id,
          confirmation: {'inbox': target, 'dropped': true},
        );
        _check(g);
        _heldPlans.remove(target);
        discardedSecretCount++;
        continue;
      }
      final due = entry.publishAfter;
      final waiting = due != null;
      if (waiting) {
        if (deadline == null || due.isBefore(deadline)) deadline = due;
      }
      final deletedPeople = _deletedPeople(entry);
      if (deletedPeople.isNotEmpty) {
        final registry = view;
        final connectedPeople = [
          if (registry != null)
            for (final id in deletedPeople)
              if (_hasConnectedDevice(registry, id)) id,
        ];
        if (entry.setAside ||
            connectedPeople.isNotEmpty ||
            !webEntryAllowed(doc, entry, blocked)) {
          final names =
              entry.blockingDevicePersonNames ??
              connectedPeople
                  .map(
                    (id) => confirmed.record(Collections.recipients, id)?['name'],
                  )
                  .whereType<String>()
                  .toList();
          if (!entry.setAside) {
            await queue.setAside(entry.id, blockingDevicePersonNames: names);
          }
          if (names.isEmpty) {
            rejectedSecretRecipientDeletes++;
          } else {
            rejectedDeviceNames.addAll(names);
          }
          continue;
        }
        // Wait for verified membership before projecting or publishing a delete.
        if (registry == null) continue;
      }
      if (entry.setAside) {
        setAsideCount++;
      } else if (entry.kind == PendingKind.privateScope) {
        // ADR 0010: a private scope change (wish plans) only ever goes to
        // the inbox of its person. Without the key it waits, encrypted in
        // the queue; it never turns into a public write.
        final person = entry.inboxPerson;
        if (person == null) {
          await queue.setAside(entry.id);
          setAsideCount++;
        } else {
          (inbox[person] ??= []).add(entry);
          if (!secrets.openedPeople.contains(person)) held++;
        }
      } else if (!webEntryAllowed(doc, entry, blocked)) {
        // 1.0.6 (ADR 0009): an action on the gifts of one protected person
        // (not this web's) goes to that person's inbox; anything else that
        // touches a protected person is still set aside («hazlo desde el
        // móvil»).
        final person = entry.inboxPerson != null &&
                _inboxPerson(entry, doc) == entry.inboxPerson
            ? entry.inboxPerson
            : null;
        if (person == null) {
          await queue.setAside(entry.id);
          setAsideCount++;
        } else {
          (inbox[person] ??= []).add(entry);
          if (!secrets.openedPeople.contains(person)) held++;
        }
      } else {
        doc = doc.merge(entry.delta);
        if (!waiting) {
          admitted.add(entry.id);
          publication = publication.merge(entry.delta);
        }
      }
    }
    _check(g);
    _inbox = inbox;
    rejectedDevicePersonNames = List.unmodifiable(rejectedDeviceNames);
    doc = doc.normalizedWishes();
    _commonDoc = doc;
    heldSecretCount = held;
    pendingSecretGiftIds = {
      for (final list in inbox.values)
        for (final e in list)
          ...?e.delta.collections[Collections.gifts]?.keys,
    };
    pendingPlanIds = {
      for (final list in inbox.values)
        for (final e in list)
          ...?e.delta.collections[ScopeCollections.wishPlans]?.keys,
    };
    candidate = secrets.isOpen ? _secretCandidate(doc, inbox) : doc;
    _publicationCandidate = publication.wishBoundary();
    _uploading = (admitted.isNotEmpty || _needsWishRepair) && !commonHeld;
    if (deadline != null) {
      _undoDeadline = Timer(
        deadline.difference(now()),
        () => unawaited(requestSync()),
      );
    }
    onChanged?.call();
    return admitted;
  }
}
