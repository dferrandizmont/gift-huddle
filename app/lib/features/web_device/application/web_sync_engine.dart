import 'dart:async';
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
import '../../../core/sync/key_bundle.dart';
import '../../../core/sync/model.dart';
import '../../../core/sync/pairing_v2.dart' show syncProtocolOf;
import '../../sync/application/common_v2.dart';
import '../../sync/application/common_v2_cutover.dart';
import '../../sync/application/sync_v2_engine.dart' show V2RollbackException;
import '../../sync/data/sync_transport.dart';
import '../../sync/data/sync_transport_v2.dart';
import '../data/vault_store.dart';
import 'pending_queue.dart';
import 'vault_service.dart';
import 'web_common.dart';

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
  final result = before.merge(entry.delta);
  for (final r
      in entry.delta.collections[Collections.gifts]?.values ?? <SyncRecord>[]) {
    final people = <Object?>{
      ...?entry.giftPeople[r.id],
      before.record(Collections.gifts, r.id)?['recipientId'],
      r['recipientId'],
      result.record(Collections.gifts, r.id)?['recipientId'],
    };
    if (people.any(blocked.contains)) return false;
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
  }) : now = now ?? DateTime.now;
  final DateTime Function() now;

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
  RegistryView? view;
  WebSyncStatus status = WebSyncStatus.pending;
  int setAsideCount = 0;
  bool get hasRoots => (vault.opened.data['roots'] as List).isNotEmpty;
  int version = 0;
  int _generation = 0;
  bool _stopped = false;
  bool _started = false;
  Future<void> _tail = Future.value();
  StreamSubscription<SyncEvent>? _socket;
  Timer? _retry;
  Timer? _syncRetry;
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

  /// Used by edits/socket notifications. A network cut retains the encrypted
  /// action and retries with bounded backoff; Retry-After is a lower bound.
  Future<void> requestSync() async {
    try {
      await sync();
      _failures = 0;
      _flag(syncOffline: false);
    } catch (e) {
      if (_stopped) return;
      if (e is SyncTransportException && e.failure == SyncFailure.network) {
        _flag(syncOffline: true);
      }
      onError?.call(e);
      if (e is SyncTransportException &&
          {
            SyncFailure.network,
            SyncFailure.server,
            SyncFailure.rateLimited,
          }.contains(e.failure)) {
        var delay = Duration(
          seconds: [5, 15, 45, 120, 300][(_failures++).clamp(0, 4)],
        );
        if (e.retryAfter != null && e.retryAfter! > delay) {
          delay = e.retryAfter!;
        }
        _syncRetry?.cancel();
        _syncRetry = Timer(delay, () => unawaited(requestSync()));
      }
    }
  }

  void stop() {
    _stopped = true;
    _generation++;
    _retry?.cancel();
    _syncRetry?.cancel();
    _undoDeadline?.cancel();
    unawaited(_socket?.cancel());
    _socket = null;
    candidate = null;
    _publicationCandidate = null;
    view = null;
  }

  void _disconnect() {
    if (_stopped) return;
    status = WebSyncStatus.disconnected;
    stop();
    vault.disconnect();
    onDisconnected?.call();
  }

  void _watch() {
    if (_stopped) return;
    final g = _generation;
    _socket = transport
        .watch(auth)
        .listen(
          (event) {
            if (_stopped || g != _generation) return;
            if (event is SyncRevokedEvent || event is SyncGoneEvent) {
              _disconnect();
              return;
            }
            if (event is SyncOpenEvent) {
              _failures = 0;
              _flag(socketDown: false);
            }
            if (event is SyncOpenEvent ||
                event is SyncVersionEvent && event.version > version) {
              unawaited(requestSync());
            }
          },
          onError: (Object e) {
            if (_stopped || g != _generation) return;
            if (e is SyncTransportException &&
                e.failure == SyncFailure.unauthorized) {
              _disconnect();
            } else {
              _flag(socketDown: true);
              onError?.call(e);
            }
          },
          onDone: () {
            if (_stopped || g != _generation) return;
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
  }) => _serial((g) async {
    final delta = webDelta(before, after);
    const allowed = {
      Collections.recipients,
      Collections.givers,
      Collections.occasions,
      Collections.gifts,
      Collections.meta,
    };
    for (final c in delta.collections.entries) {
      if (c.value.isNotEmpty &&
          (!allowed.contains(c.key) ||
              c.key == Collections.meta && c.value.containsKey('protocol'))) {
        throw const WebOperationException('restrictedDocument');
      }
    }
    if (delta.collections.values.every((v) => v.isEmpty)) return;
    _check(g);
    await queue.add(
      delta,
      undoGiftId: undoGiftId,
      publishAfter: publishAfter,
      giftPeople: {
        for (final id
            in delta.collections[Collections.gifts]?.keys ?? <String>[])
          id: {
            before.record(Collections.gifts, id)?['recipientId'],
            after.record(Collections.gifts, id)?['recipientId'],
          }.whereType<String>().toList(),
      },
    );
    _check(g);
    await _candidate(g);
  });

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

  Future<void> sync() => _serial((g) async {
    try {
      for (var attempt = 0; attempt < 4; attempt++) {
        final snap = await _read(g);
        if (snap == null) return;
        final admitted = await _candidate(g);
        if (status != WebSyncStatus.confirmed || admitted.isEmpty) return;
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
  });

  /// The common document of the saved snapshot (format 1 before the cut,
  /// format 2 opened by `kid` afterwards).
  Future<FamilyDoc> savedCommon() => openSavedCommon(
    vault.opened.data,
    listId: listId,
    syncId: vault.opened.header.syncId,
  );

  Future<V2Snapshot?> _read(int g, {bool announced = false}) async {
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
    final got = await transport.getList(auth);
    _check(g);
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
    version = s.version;
    view = current;
    return s;
  }

  Future<List<String>> _candidate(int g) async {
    final data = vault.opened.data;
    final snapshot = data['snapshot'] as Map;
    var doc = await savedCommon();
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
    DateTime? deadline;
    _undoDeadline?.cancel();
    setAsideCount = 0;
    for (final entry in entries) {
      _check(g);
      final due = entry.publishAfter;
      final waiting = due != null;
      if (waiting) {
        if (deadline == null || due.isBefore(deadline)) deadline = due;
      }
      if (entry.setAside || !webEntryAllowed(doc, entry, blocked)) {
        if (!entry.setAside) await queue.setAside(entry.id);
        setAsideCount++;
      } else {
        doc = doc.merge(entry.delta);
        if (!waiting) {
          admitted.add(entry.id);
          publication = publication.merge(entry.delta);
        }
      }
    }
    _check(g);
    candidate = doc;
    _publicationCandidate = publication;
    _uploading = admitted.isNotEmpty && !commonHeld;
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
