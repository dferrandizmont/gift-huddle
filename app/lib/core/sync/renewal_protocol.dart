/// Source-generation renewal control. Wire format: server/README.md, API v2.
/// Parsing is not trust; use [RenewalControl.fromLog] before acting on a GET.
library;

import 'dart:collection';
import 'dart:convert';

import 'package:cryptography/dart.dart';

import 'device_keys.dart';
import 'device_registry.dart';
import 'envelope.dart' show encodeBase64Url;
import 'family_candidate.dart' show decodeCanonicalBase64Url, sha256Hex;
import 'pairing_v2.dart' show canonicalJsonText;

const kRenewalCommandBytes = 8 * 1024;
const kRenewalControlBytes = 256 * 1024;
const kRenewalParticipants = 32;
const kRenewalBranches = 8;
const kRenewalOrdinaryCommands = 512;
const kRenewalOrdinaryBytes = 512 * 1024;
const kRenewalRescueCommands = 64;
const kRenewalRescueBytes = 64 * 1024;
const kRenewalRefillCommands = 40;
const kRenewalRefillBytes = 40 * 1024;
const _maxSafeInteger = 9007199254740991;
const _domain = 'gift-huddle-renewal-control-v2';

/// Unsalted canonical digest of a complete public signed command.
String renewalCommandHash(Map<String, Object?> snapshot) => encodeBase64Url(
  const DartSha256().hashSync(utf8.encode(canonicalJsonText(snapshot))).bytes,
);

enum RenewalAction {
  reserve,
  replace,
  recover,
  revise,
  ready,
  ack,
  exclude,
  prepare,
  confirm,
  abort,
  revoke,
  resume,
  capability,
}

enum RenewalCommitmentKind { target, inventory, receipt, coverage }

/// A private, salted manifest commitment. Persist the random 32-byte salt and
/// manifest ONLY in the encrypted journal, before publishing the commitment.
/// The complete binding (including revision) prevents cross-generation reuse.
/// This hashes an assertion; it does not certify conservation of its contents.
String renewalCommitment({
  required RenewalBinding binding,
  required RenewalCommitmentKind kind,
  required List<int> salt,
  required Map<String, Object?> manifest,
}) {
  if (salt.length != 32 || salt.any((b) => b < 0 || b > 255)) {
    _bad('salt');
  }
  return encodeBase64Url(
    const DartSha256().hashSync([
      ...utf8.encode('gift-huddle-renewal-${kind.name}-v1'),
      0,
      ...utf8.encode(
        canonicalJsonText({
          'v': 1,
          'binding': binding.toJson(),
          'salt': encodeBase64Url(salt),
          'manifest': manifest,
        }),
      ),
    ]).bytes,
  );
}

class RenewalProtocolException implements Exception {
  const RenewalProtocolException(this.code);
  final String code;
  @override
  String toString() => 'RenewalProtocolException: $code';
}

Never _bad(String code) => throw RenewalProtocolException(code);

bool _positive(Object? n) => n is int && n > 0 && n <= _maxSafeInteger;
bool _bytes(Object? v, int n) =>
    v is String && decodeCanonicalBase64Url(v, length: n) != null;
bool _id(Object? v) => v is String && kSyncIdPattern.hasMatch(v);

Map<String, Object?> _map(Object? raw) {
  if (raw is! Map || raw.keys.any((k) => k is! String)) _bad('shape');
  return Map<String, Object?>.from(raw);
}

void _keys(Map<String, Object?> map, Iterable<String> keys) {
  if (map.length != keys.length || keys.any((k) => !map.containsKey(k))) {
    _bad('fields');
  }
}

List<String> _ids(
  Object? raw, {
  required int max,
  bool generations = false,
  bool empty = false,
}) {
  if (raw is! List ||
      raw.length > max ||
      (!empty && raw.isEmpty) ||
      raw.any((v) => generations ? !_bytes(v, 16) : !_id(v)) ||
      raw.toSet().length != raw.length) {
    _bad('identifiers');
  }
  return List<String>.unmodifiable(raw.cast<String>());
}

/// Full replay scope. listId is local context (not an extra wire field).
class RenewalBinding {
  RenewalBinding({
    required this.listId,
    required this.operationId,
    required this.sourceSyncId,
    required this.targetSyncId,
    required this.revision,
  }) {
    if (!_id(listId) ||
        !_bytes(operationId, 16) ||
        !_bytes(sourceSyncId, 16) ||
        !_bytes(targetSyncId, 16) ||
        sourceSyncId == targetSyncId ||
        !_positive(revision)) {
      _bad('binding');
    }
  }
  final String listId;
  final String operationId;
  final String sourceSyncId;
  final String targetSyncId;
  final int revision;

  Map<String, Object?> toJson() => {
    'listId': listId,
    'operationId': operationId,
    'sourceSyncId': sourceSyncId,
    'targetSyncId': targetSyncId,
    'revision': revision,
  };

  factory RenewalBinding.fromJson(Object? raw) {
    final m = _map(raw);
    _keys(m, [
      'listId',
      'operationId',
      'sourceSyncId',
      'targetSyncId',
      'revision',
    ]);
    if (m['listId'] is! String ||
        m['operationId'] is! String ||
        m['sourceSyncId'] is! String ||
        m['targetSyncId'] is! String ||
        m['revision'] is! int) {
      _bad('binding');
    }
    return RenewalBinding(
      listId: m['listId'] as String,
      operationId: m['operationId'] as String,
      sourceSyncId: m['sourceSyncId'] as String,
      targetSyncId: m['targetSyncId'] as String,
      revision: m['revision'] as int,
    );
  }
}

const _base = [
  'v',
  'action',
  'operationId',
  'sourceSyncId',
  'targetSyncId',
  'revision',
  'sourceVersion',
  'signerDeviceId',
  'signature',
  'prev',
];
const _fields = <RenewalAction, List<String>>{
  RenewalAction.reserve: [
    'participants',
    'newDeviceId',
    'newSigningKey',
    'targetCommitment',
    'inventoryCommitment',
  ],
  RenewalAction.replace: [
    'participants',
    'newDeviceId',
    'newSigningKey',
    'targetCommitment',
    'inventoryCommitment',
    'previousTargetSyncId',
  ],
  RenewalAction.recover: [
    'participants',
    'newDeviceId',
    'newSigningKey',
    'targetCommitment',
    'inventoryCommitment',
    'previousTargetSyncId',
  ],
  RenewalAction.revise: ['participants', 'inventoryCommitment'],
  RenewalAction.ready: ['destinationVersion'],
  RenewalAction.ack: [
    'newDeviceId',
    'newSigningKey',
    'receipt',
    'destinationVersion',
  ],
  RenewalAction.exclude: ['participantDeviceId', 'loss', 'receipt'],
  RenewalAction.prepare: ['pendingResources', 'coverageCommitment'],
  RenewalAction.confirm: [
    'snapshotVersion',
    'pendingResources',
    'coverageCommitment',
  ],
  RenewalAction.abort: [],
  RenewalAction.revoke: ['participantDeviceId'],
  RenewalAction.resume: [],
  RenewalAction.capability: ['commonFormat'],
};

/// Immutable, exact signed command, including the original sourceVersion.
/// The fields argument of [sign] contains only the action-specific fields.
/// Receipts/commitments are salted opaque 32-byte values, never gift hashes.
class RenewalCommand {
  RenewalCommand._(this._json, this.action);
  final Map<String, Object?> _json;
  final RenewalAction action;

  factory RenewalCommand.fromJson(Object? raw) {
    final m = _map(raw);
    final a = RenewalAction.values
        .where((a) => a.name == m['action'])
        .firstOrNull;
    if (a == null) _bad('action');
    final fields = _fields[a]!;
    _keys(m, [..._base, ...fields]);
    if (m['prev'] != null && !_bytes(m['prev'], 32)) {
      _bad('prev');
    }
    if (m['v'] != 1 ||
        m['v'] is! int ||
        !_bytes(m['operationId'], 16) ||
        !_bytes(m['sourceSyncId'], 16) ||
        !_bytes(m['targetSyncId'], 16) ||
        m['sourceSyncId'] == m['targetSyncId'] ||
        !_positive(m['revision']) ||
        !_positive(m['sourceVersion']) ||
        !_id(m['signerDeviceId']) ||
        !_bytes(m['signature'], 64)) {
      _bad('command');
    }
    if (fields.contains('participants')) {
      m['participants'] = _ids(m['participants'], max: kRenewalParticipants);
    }
    if (fields.contains('newDeviceId') &&
        (!_id(m['newDeviceId']) || !_bytes(m['newSigningKey'], 32))) {
      _bad('identity');
    }
    for (final k in ['destinationVersion', 'snapshotVersion']) {
      if (fields.contains(k) && !_positive(m[k])) _bad('version');
    }
    if (fields.contains('participantDeviceId') &&
        (!_id(m['participantDeviceId']) ||
            (a == RenewalAction.exclude && m['loss'] != true))) {
      _bad('loss');
    }
    if (fields.contains('pendingResources') &&
        (m['pendingResources'] is! int || m['pendingResources'] != 0)) {
      _bad('pending');
    }
    if (fields.contains('previousTargetSyncId') &&
        !_bytes(m['previousTargetSyncId'], 16)) {
      _bad('previous_target');
    }
    for (final k in [
      'targetCommitment',
      'inventoryCommitment',
      'receipt',
      'coverageCommitment',
    ]) {
      if (fields.contains(k) && !_bytes(m[k], 32)) _bad('commitment');
    }
    if (a == RenewalAction.capability &&
        (m['commonFormat'] is! int || m['commonFormat'] != 2)) {
      _bad('capability');
    }
    if (utf8.encode(canonicalJsonText(m)).length > kRenewalCommandBytes) {
      _bad('size');
    }
    return RenewalCommand._(Map.unmodifiable(m), a);
  }

  static Future<RenewalCommand> sign({
    required RenewalAction action,
    required RenewalBinding binding,
    required int sourceVersion,
    required String signerDeviceId,
    required DeviceKeys keys,
    required Map<String, Object?> fields,
    required RegistryView sourceView,
    required String? prev,
  }) async {
    _keys(fields, _fields[action]!);
    final provisional = RenewalCommand.fromJson({
      'v': 1,
      'action': action.name,
      'operationId': binding.operationId,
      'sourceSyncId': binding.sourceSyncId,
      'targetSyncId': binding.targetSyncId,
      'revision': binding.revision,
      'sourceVersion': sourceVersion,
      'signerDeviceId': signerDeviceId,
      'prev': prev,
      ...fields,
      'signature': encodeBase64Url(List<int>.filled(64, 0)),
    });
    if (sourceView.listId != binding.listId ||
        !provisional.authorizedIn(sourceView) ||
        !constantTimeEquals(
          sourceView.member(signerDeviceId)!.signingKey,
          keys.publicKeys.signing,
        )) {
      _bad('authority');
    }
    return RenewalCommand.fromJson({
      ...provisional._json,
      'signature': encodeBase64Url(await keys.sign(provisional.signingBytes)),
    });
  }

  String get operationId => _json['operationId'] as String;
  String get sourceSyncId => _json['sourceSyncId'] as String;
  String get targetSyncId => _json['targetSyncId'] as String;
  int get revision => _json['revision'] as int;
  int get sourceVersion => _json['sourceVersion'] as int;
  String get signerDeviceId => _json['signerDeviceId'] as String;
  String? get newDeviceId => _json['newDeviceId'] as String?;
  String? get newSigningKey => _json['newSigningKey'] as String?;
  int? get destinationVersion => _json['destinationVersion'] as int?;
  String? get receipt => _json['receipt'] as String?;
  String? get prev => _json['prev'] as String?;
  List<int> get signingBytes => [
    ...utf8.encode(_domain),
    0,
    ...utf8.encode(
      canonicalJsonText({
        for (final e in _json.entries)
          if (e.key != 'signature') e.key: e.value,
      }),
    ),
  ];
  late final int wireBytes = utf8.encode(canonicalJsonText(_json)).length;
  late final String hash = renewalCommandHash(_json);
  late final String digest = sha256Hex(utf8.encode(canonicalJsonText(_json)));
  Map<String, Object?> toJson() => _json;

  /// Current authority, separate from historical signature authenticity.
  bool authorizedIn(RegistryView view) {
    final d = view.member(signerDeviceId);
    return d != null &&
        !view.revoked.contains(signerDeviceId) &&
        (signerDeviceId != view.me ||
            (view.selfApproved && !view.revokedByOthers)) &&
        ([
              RenewalAction.ack,
              RenewalAction.resume,
              RenewalAction.capability,
            ].contains(action) ||
            d.kind == DeviceKind.mobile);
  }

  Future<void> verify({
    required RenewalBinding binding,
    required RegistryView sourceView,
    bool historicalReservation = false,
    bool historical = false,
  }) async {
    if (sourceView.listId != binding.listId ||
        operationId != binding.operationId ||
        sourceSyncId != binding.sourceSyncId ||
        (!historical && targetSyncId != binding.targetSyncId) ||
        (historicalReservation || historical
            ? revision > binding.revision
            : revision != binding.revision) ||
        (historicalReservation &&
            action != RenewalAction.reserve &&
            action != RenewalAction.replace &&
            action != RenewalAction.recover)) {
      _bad('context');
    }
    final key = sourceView.linkedSigningKey(signerDeviceId);
    if (key == null ||
        !await verifyDeviceSignature(
          message: signingBytes,
          signature: decodeCanonicalBase64Url(
            _json['signature'] as String,
            length: 64,
          )!,
          signingPublicKey: key,
        )) {
      _bad('signature');
    }
  }
}

/// A head received from another mobile (or persisted after verified replay).
/// A Worker-provided head alone cannot prove freshness to a first observer.
class RenewalLogAnchor {
  RenewalLogAnchor({
    required this.sourceSyncId,
    required this.operationId,
    required this.head,
    required this.height,
  }) {
    if (!_bytes(sourceSyncId, 16) ||
        !_bytes(operationId, 16) ||
        !_bytes(head, 32) ||
        !_positive(height)) {
      _bad('anchor');
    }
  }
  final String sourceSyncId;
  final String operationId;
  final String head;
  final int height;
  Map<String, Object?> toJson() => {
    'sourceSyncId': sourceSyncId,
    'operationId': operationId,
    'head': head,
    'height': height,
  };
  factory RenewalLogAnchor.fromJson(Object? raw) {
    final m = _map(raw);
    _keys(m, ['sourceSyncId', 'operationId', 'head', 'height']);
    if (m['sourceSyncId'] is! String ||
        m['operationId'] is! String ||
        m['head'] is! String ||
        m['height'] is! int) {
      _bad('anchor');
    }
    return RenewalLogAnchor(
      sourceSyncId: m['sourceSyncId'] as String,
      operationId: m['operationId'] as String,
      head: m['head'] as String,
      height: m['height'] as int,
    );
  }
}

const kRenewalLogPageCommands = 256;
const kRenewalLogPageBytes = 256 * 1024;
const kRenewalLogMaxPages = 512;
const kRenewalLogMaxCommands = 24576;
const kRenewalLogMaxBytes = 24 * 1024 * 1024;

/// A pinned page. Its contents still require chain and signature verification.
class RenewalLogPage {
  RenewalLogPage._(
    this.sourceSyncId,
    this.operationId,
    this.head,
    this.height,
    this.after,
    this.next,
    this.commands,
  );
  final String sourceSyncId;
  final String operationId;
  final String head;
  final int height;
  final int after;
  final int? next;
  final List<RenewalCommand> commands;
  factory RenewalLogPage.fromJson(Object? raw) {
    final m = _map(raw);
    _keys(m, [
      'sourceSyncId',
      'operationId',
      'head',
      'height',
      'after',
      'next',
      'commands',
    ]);
    final commands = m['commands'];
    if (!_bytes(m['sourceSyncId'], 16) ||
        !_bytes(m['operationId'], 16) ||
        !_bytes(m['head'], 32) ||
        !_positive(m['height']) ||
        (m['height'] as int) > kRenewalLogMaxCommands ||
        m['after'] is! int ||
        (m['after'] as int) < 0 ||
        (m['after'] as int) > (m['height'] as int) ||
        commands is! List ||
        commands.length > kRenewalLogPageCommands ||
        utf8.encode(canonicalJsonText(commands)).length >
            kRenewalLogPageBytes) {
      _bad('page');
    }
    if (m['next'] != null && m['next'] is! int) _bad('page');
    final end = (m['after'] as int) + commands.length;
    if (end > (m['height'] as int) ||
        (end == m['height']
            ? m['next'] != null
            : m['next'] != end || commands.isEmpty)) {
      _bad('page');
    }
    return RenewalLogPage._(
      m['sourceSyncId'] as String,
      m['operationId'] as String,
      m['head'] as String,
      m['height'] as int,
      m['after'] as int,
      m['next'] as int?,
      List.unmodifiable(commands.map(RenewalCommand.fromJson)),
    );
  }
}

/// Accumulated during one ordered pass. Keep this beside an in-memory replay;
/// durable evidence remains the signed commands, never these derived counters.
class RenewalReplayIndex {
  final byHash = <String, RenewalCommand>{};
  final targets = <String>{};
  final identitiesById = <String, Set<String>>{};
  final identitiesByKey = <String, Set<String>>{};
  final ackSigners = <String>{};
  final resumed = <String>{};
  final capabilities = <String>{};
  final rescueCount = <String, int>{};
  final rescueBytes = <String, int>{};
  var height = 0;
  var bytes = 0;
  var afterRevoke = false;

  static String owner(RenewalCommand c) =>
      '${c.targetSyncId}/${c.signerDeviceId}';
  bool identityUsed(RenewalCommand c, {bool sameOwner = false}) =>
      [identitiesById[c.newDeviceId], identitiesByKey[c.newSigningKey]].any(
        (owners) =>
            owners != null && (!sameOwner || owners.any((o) => o != owner(c))),
      );

  void addAll(Iterable<RenewalCommand> commands) {
    for (final c in commands) {
      add(c);
    }
  }

  void add(RenewalCommand c) {
    byHash[c.hash] = c;
    height++;
    bytes += c.wireBytes;
    if ([
      RenewalAction.reserve,
      RenewalAction.replace,
      RenewalAction.recover,
    ].contains(c.action)) {
      targets.add(c.targetSyncId);
    }
    if (c.newDeviceId != null) {
      (identitiesById[c.newDeviceId!] ??= {}).add(owner(c));
      (identitiesByKey[c.newSigningKey!] ??= {}).add(owner(c));
    }
    if (c.action == RenewalAction.ack) ackSigners.add(c.signerDeviceId);
    if (c.action == RenewalAction.resume) resumed.add(c.signerDeviceId);
    if (c.action == RenewalAction.capability) {
      capabilities.add(c.signerDeviceId);
    }
    if (c.action == RenewalAction.revoke) {
      rescueCount.clear();
      rescueBytes.clear();
      afterRevoke = true;
    } else if ((height > kRenewalOrdinaryCommands ||
            bytes > kRenewalOrdinaryBytes) &&
        ![RenewalAction.recover, RenewalAction.abort].contains(c.action)) {
      rescueCount.update(c.signerDeviceId, (n) => n + 1, ifAbsent: () => 1);
      rescueBytes.update(
        c.signerDeviceId,
        (n) => n + c.wireBytes,
        ifAbsent: () => c.wireBytes,
      );
    }
  }
}

/// Pure deterministic state transition. All proof collections live in the log;
/// this projection contains hashes only and stays below the control budget.
/// The service additionally checks CAS, inactivity, current credentials and
/// minimal destination creation. Those service assertions never prove inventory.
Map<String, Object?> replayRenewalCommand(
  Map<String, Object?>? previous,
  RenewalCommand c,
  Set<String> revoked, {
  required RenewalReplayIndex index,
}) {
  final i = index;
  final j = c.toJson();
  final old = previous;
  if (old == null) {
    if (c.action != RenewalAction.reserve ||
        c.revision != 1 ||
        c.prev != null) {
      _bad('genesis');
    }
  } else if (old['operationId'] != c.operationId ||
      old['sourceSyncId'] != c.sourceSyncId ||
      old['head'] != c.prev ||
      old['abortion'] != null) {
    _bad('chain');
  }
  bool has(Map<String, Object?>? state, String field, String id) =>
      state != null && (state[field] as Map).containsKey(id);
  final replacing =
      c.action == RenewalAction.replace || c.action == RenewalAction.recover;
  late Map<String, Object?> s;
  if (c.action == RenewalAction.reserve ||
      replacing ||
      c.action == RenewalAction.revise) {
    final participants = j['participants'] as List<String>;
    if (!participants.contains(c.signerDeviceId) ||
        (old != null &&
            (old['participants'] as List).any(
              (id) => !participants.contains(id),
            ))) {
      _bad('participants_missing');
    }
    if (old != null) {
      if (c.revision != (old['revision'] as int) + 1 ||
          has(old, 'exclusions', c.signerDeviceId)) {
        _bad('revision');
      }
      final reservation = i.byHash[old['reservation']]!;
      if (c.action == RenewalAction.revise &&
          revoked.contains(reservation.signerDeviceId)) {
        _bad('replace_required');
      }
      if (c.action == RenewalAction.recover &&
          !revoked.contains(reservation.signerDeviceId)) {
        _bad('recovery');
      }
      if (replacing &&
          ((j['previousTargetSyncId'] != old['targetSyncId']) ||
              i.targets.contains(c.targetSyncId))) {
        _bad('target');
      }
      if (c.action == RenewalAction.revise &&
          c.targetSyncId != old['targetSyncId']) {
        _bad('target');
      }
      if (replacing &&
          (old['transfers'] as Map).isNotEmpty &&
          !has(old, 'transfers', c.signerDeviceId) &&
          old['needsRevalidation'] != true) {
        _bad('not_migrated');
      }
    }
    if (c.action != RenewalAction.revise && i.identityUsed(c)) {
      _bad('identity_reused');
    }
    final branches = <String>[
      if (c.action != RenewalAction.recover)
        ...?(old?['branches'] as List?)?.cast<String>(),
    ];
    if (c.action == RenewalAction.replace &&
        (old!['transfers'] as Map).isNotEmpty) {
      branches.add(old['targetSyncId'] as String);
    }
    if (branches.length > kRenewalBranches) _bad('branches');
    // Extinction is a transition on the CURRENT barrier. A later ack cannot
    // recreate one that a previous legitimate replacement already extinguished.
    final keep = !replacing || i.ackSigners.any((id) => !revoked.contains(id));
    s = {
      'operationId': c.operationId,
      'sourceSyncId': c.sourceSyncId,
      'targetSyncId': c.targetSyncId,
      'revision': c.revision,
      'participants': participants,
      'branches': branches,
      'plan': c.hash,
      'reservation': c.action == RenewalAction.revise
          ? old!['reservation']
          : c.hash,
      'recovery': c.action == RenewalAction.recover ? c.hash : old?['recovery'],
      'barrier': keep ? (old?['barrier']) : null,
      'barrierVersion': keep ? (old?['barrierVersion']) : null,
      'abortion': null,
      'ready': null,
      'acknowledgements': <String, Object?>{},
      'transfers': c.action == RenewalAction.revise
          ? <String, Object?>{
              ..._map(old!['transfers']),
              ..._map(old['acknowledgements']),
            }
          : <String, Object?>{},
      'exclusions': <String, Object?>{},
      'preparation': null,
      'confirmation': null,
      'confirmedVersion': null,
      'needsRevalidation': false,
    };
  } else {
    if (old == null ||
        c.targetSyncId != old['targetSyncId'] ||
        c.revision != old['revision']) {
      _bad('context');
    }
    s = {
      ...old,
      'acknowledgements': {..._map(old['acknowledgements'])},
      'transfers': {..._map(old['transfers'])},
      'exclusions': {..._map(old['exclusions'])},
    };
    final acks = s['acknowledgements'] as Map<String, Object?>;
    final transfers = s['transfers'] as Map<String, Object?>;
    final exclusions = s['exclusions'] as Map<String, Object?>;
    final reservation = i.byHash[s['reservation']]!;
    if (s['needsRevalidation'] == true &&
        ![
          RenewalAction.abort,
          RenewalAction.revoke,
          RenewalAction.resume,
          RenewalAction.capability,
        ].contains(c.action)) {
      _bad('revalidation');
    }
    void invalidate() {
      s['needsRevalidation'] = true;
      s['preparation'] = null;
      s['confirmation'] = null;
      s['confirmedVersion'] = null;
    }

    switch (c.action) {
      case RenewalAction.revoke:
        final id = j['participantDeviceId'] as String;
        if (id == c.signerDeviceId || revoked.contains(id)) _bad('revocation');
        revoked.add(id);
        exclusions.remove(c.signerDeviceId);
        invalidate();
      case RenewalAction.resume:
        if (!exclusions.containsKey(c.signerDeviceId)) _bad('resume');
        if (i.resumed.contains(c.signerDeviceId)) _bad('resume_used');
        exclusions.remove(c.signerDeviceId);
        invalidate();
      case RenewalAction.capability:
        if (i.capabilities.contains(c.signerDeviceId)) {
          _bad('capability');
        }
      case RenewalAction.abort:
        if (s['recovery'] != null ||
            transfers.isNotEmpty ||
            (s['branches'] as List).isNotEmpty ||
            s['barrier'] != null) {
          _bad('abort');
        }
        s['abortion'] = c.hash;
      case RenewalAction.ready:
        if (s['ready'] != null ||
            s['preparation'] != null ||
            s['confirmation'] != null ||
            (c.signerDeviceId != reservation.signerDeviceId &&
                !transfers.containsKey(c.signerDeviceId))) {
          _bad('ready');
        }
        s['ready'] = c.hash;
      case RenewalAction.ack:
        if (s['ready'] == null ||
            !(s['participants'] as List).contains(c.signerDeviceId) ||
            s['confirmation'] != null ||
            exclusions.containsKey(c.signerDeviceId) ||
            acks.containsKey(c.signerDeviceId)) {
          _bad('ack');
        }
        final ready = i.byHash[s['ready']]!;
        if (c.destinationVersion! < ready.destinationVersion!) _bad('order');
        if (i.identityUsed(c, sameOwner: true)) {
          _bad('identity_reused');
        }
        if (reservation.signerDeviceId == c.signerDeviceId &&
            (reservation.newDeviceId != c.newDeviceId ||
                reservation.newSigningKey != c.newSigningKey)) {
          _bad('identity');
        }
        if (transfers.containsKey(c.signerDeviceId)) {
          final t = i.byHash[transfers[c.signerDeviceId]]!;
          if (t.newDeviceId != c.newDeviceId ||
              t.newSigningKey != c.newSigningKey) {
            _bad('identity');
          }
        }
        acks[c.signerDeviceId] = c.hash;
        transfers.putIfAbsent(c.signerDeviceId, () => c.hash);
      case RenewalAction.exclude:
        final id = j['participantDeviceId'] as String;
        if (s['ready'] == null ||
            !acks.containsKey(c.signerDeviceId) ||
            exclusions.containsKey(c.signerDeviceId) ||
            !(s['participants'] as List).contains(id) ||
            id == c.signerDeviceId ||
            acks.containsKey(id) ||
            (transfers.containsKey(id) && !revoked.contains(id)) ||
            exclusions.containsKey(id) ||
            s['preparation'] != null ||
            s['confirmation'] != null) {
          _bad('exclude');
        }
        exclusions[id] = c.hash;
      case RenewalAction.prepare:
      case RenewalAction.confirm:
        if (s['ready'] == null ||
            !acks.containsKey(c.signerDeviceId) ||
            exclusions.containsKey(c.signerDeviceId) ||
            !(s['participants'] as List).every(
              (id) =>
                  exclusions.containsKey(id) ||
                  (acks.containsKey(id) && !revoked.contains(id)),
            )) {
          _bad('participants_pending');
        }
        if (c.action == RenewalAction.prepare) {
          if (s['preparation'] != null || s['confirmation'] != null) {
            _bad('prepare');
          }
          s['preparation'] = c.hash;
          s['barrier'] = c.hash;
          s['barrierVersion'] = c.sourceVersion + 1;
        } else {
          if (s['preparation'] == null ||
              j['snapshotVersion'] != s['barrierVersion']) {
            _bad('snapshot');
          }
          s['confirmation'] = c.hash;
          s['confirmedVersion'] = c.sourceVersion + 1;
        }
      default:
        _bad('action');
    }
  }
  if (old != null &&
      !(old['participants'] as List).contains(c.signerDeviceId)) {
    _bad('participant');
  }
  final nextHeight = (old?['height'] as int? ?? 0) + 1;
  final nextBytes = (old?['logBytes'] as int? ?? 0) + c.wireBytes;
  if (nextHeight > kRenewalLogMaxCommands || nextBytes > kRenewalLogMaxBytes) {
    _bad('log_full');
  }
  if (nextHeight > kRenewalOrdinaryCommands ||
      nextBytes > kRenewalOrdinaryBytes) {
    if (c.action == RenewalAction.replace ||
        (c.action == RenewalAction.revise &&
            old?['needsRevalidation'] != true)) {
      _bad('log_full');
    }
    if (![
      RenewalAction.recover,
      RenewalAction.revoke,
      RenewalAction.abort,
    ].contains(c.action)) {
      if ((i.rescueCount[c.signerDeviceId] ?? 0) >=
              (i.afterRevoke
                  ? kRenewalRefillCommands
                  : kRenewalRescueCommands) ||
          (i.rescueBytes[c.signerDeviceId] ?? 0) + c.wireBytes >
              (i.afterRevoke ? kRenewalRefillBytes : kRenewalRescueBytes)) {
        _bad('log_full');
      }
    }
  }
  s['head'] = c.hash;
  s['height'] = (old?['height'] as int? ?? 0) + 1;
  s['logBytes'] = (old?['logBytes'] as int? ?? 0) + c.wireBytes;
  return s;
}

/// Immutable prefix of an append-only backing list. Forward extensions share
/// storage in O(1); a fork copies only when it diverges from that backing tail.
class _CommandPrefix extends ListBase<RenewalCommand> {
  _CommandPrefix(this._backing, this.length);
  final List<RenewalCommand> _backing;
  @override
  final int length;
  @override
  set length(int value) => throw UnsupportedError('immutable log');
  @override
  RenewalCommand operator [](int index) {
    RangeError.checkValidIndex(index, this);
    return _backing[index];
  }

  @override
  void operator []=(int index, RenewalCommand value) =>
      throw UnsupportedError('immutable log');
}

/// Verified, replayed log. Never populated from the Worker's state assertions.
class RenewalControl {
  RenewalControl._(
    this.binding,
    this.version,
    this._projection,
    this.commands,
    this._sourceView,
    this._verifiedKeys,
    this._byHash,
    this._replayIndex,
    this._replayRevoked,
    this._trust,
    this.replayedCommandCount,
  );
  final RenewalBinding binding;
  final int version;
  final Map<String, Object?> _projection;
  final List<RenewalCommand> commands;
  final RegistryView _sourceView;
  final Map<String, String> _verifiedKeys;
  // A cache belongs to a single verified tip. Consuming it leaves older controls
  // valid and immutable, but requires replay if they are used again as a fork.
  RenewalReplayIndex? _replayIndex;
  final Set<String> _replayRevoked;
  final String _trust;

  /// Number of transitions executed by this verification (for load measurement).
  final int replayedCommandCount;
  bool _revoked(String id, RegistryView view) =>
      view.revoked.contains(id) || _replayRevoked.contains(id);

  // Shared append-only lookup; each immutable projection references only hashes
  // inside its own prefix. Reading plan/receipts never rebuilds a prefix index.
  final Map<String, RenewalCommand> _byHash;
  String get head => _projection['head'] as String;
  int get height => _projection['height'] as int;
  RenewalLogAnchor get anchor => RenewalLogAnchor(
    sourceSyncId: binding.sourceSyncId,
    operationId: binding.operationId,
    head: head,
    height: height,
  );
  RenewalCommand? _command(String key) =>
      _projection[key] == null ? null : _byHash[_projection[key]];
  Map<String, RenewalCommand> _commands(String key) => Map.unmodifiable(
    _map(_projection[key]).map((id, hash) => MapEntry(id, _byHash[hash]!)),
  );
  List<String> get participants =>
      List.unmodifiable((_projection['participants'] as List).cast<String>());
  List<String> get branches =>
      List.unmodifiable((_projection['branches'] as List).cast<String>());
  RenewalCommand get plan => _command('plan')!;
  RenewalCommand get reservation => _command('reservation')!;
  RenewalCommand? get recovery => _command('recovery');
  RenewalCommand? get barrier => _command('barrier');
  RenewalCommand? get abortion => _command('abortion');
  RenewalCommand? get ready => _command('ready');
  RenewalCommand? get preparation => _command('preparation');
  RenewalCommand? get confirmation => _command('confirmation');
  int? get barrierVersion => _projection['barrierVersion'] as int?;
  int? get confirmedVersion => _projection['confirmedVersion'] as int?;
  bool get needsRevalidation => _projection['needsRevalidation'] as bool;
  Map<String, RenewalCommand> get acknowledgements =>
      _commands('acknowledgements');
  Map<String, RenewalCommand> get transfers => _commands('transfers');
  Map<String, RenewalCommand> get exclusions => _commands('exclusions');
  List<RenewalCommand> get identities =>
      List.unmodifiable(commands.where((c) => c.newDeviceId != null));
  Map<String, RenewalCommand> get revokedIdentities => Map.unmodifiable({
    for (final c in identities.where(
      (c) => _revoked(c.signerDeviceId, _sourceView),
    ))
      c.hash: c,
  });

  /// Supply a trusted anchor independently of the fetched projection. With a
  /// previous observation, only its suffix is downloaded; complete signed
  /// commands remain persisted and are replayed against current source trust.
  static Future<RenewalControl> fromLog({
    required String listId,
    required String sourceSyncId,
    required int version,
    required Object? projection,
    required DeviceRegistry sourceRegistry,
    required RegistryView sourceView,
    required Iterable<RenewalLogPage> pages,
    required RenewalLogAnchor anchor,
    RenewalControl? previous,
  }) async {
    final p = _map(projection);
    if (!_bytes(p['targetSyncId'], 16) ||
        !_positive(p['revision']) ||
        !_bytes(p['head'], 32) ||
        !_positive(p['height']) ||
        (p['height'] as int) > kRenewalLogMaxCommands ||
        !_positive(p['logBytes']) ||
        (p['logBytes'] as int) > kRenewalLogMaxBytes ||
        utf8.encode(canonicalJsonText(p)).length > kRenewalControlBytes ||
        !_positive(version) ||
        sourceRegistry.listId != listId ||
        sourceView.listId != listId ||
        p['sourceSyncId'] != sourceSyncId ||
        anchor.sourceSyncId != sourceSyncId ||
        anchor.operationId != p['operationId']) {
      _bad('context');
    }
    final sameOperation = previous?.binding.operationId == p['operationId'];
    if (previous != null && !sameOperation && previous.abortion == null) {
      _bad('replay');
    }
    final prefix = sameOperation ? previous!.commands : <RenewalCommand>[];
    final suffix = <RenewalCommand>[];
    final prefixLength = prefix.length;
    if (previous != null &&
        (previous.binding.listId != listId ||
            previous.binding.sourceSyncId != sourceSyncId ||
            version < previous.version)) {
      _bad('replay');
    }
    var at = prefixLength;
    var count = 0;
    for (final page in pages) {
      if (++count > kRenewalLogMaxPages ||
          page.sourceSyncId != sourceSyncId ||
          page.operationId != p['operationId'] ||
          page.head != p['head'] ||
          page.height != p['height'] ||
          page.after != at) {
        _bad('page');
      }
      suffix.addAll(page.commands);
      at = prefixLength + suffix.length;
    }
    final total = prefixLength + suffix.length;
    RenewalCommand commandAt(int index) =>
        index < prefixLength ? prefix[index] : suffix[index - prefixLength];
    if (total == 0 ||
        total != p['height'] ||
        total > kRenewalLogMaxCommands ||
        commandAt(total - 1).hash != p['head'] ||
        anchor.height > total ||
        commandAt(anchor.height - 1).hash != anchor.head) {
      _bad('chain');
    }
    final b = RenewalBinding(
      listId: listId,
      operationId: p['operationId'] as String,
      sourceSyncId: sourceSyncId,
      targetSyncId: p['targetSyncId'] as String,
      revision: p['revision'] as int,
    );
    // Include all inputs used by historical signatures, roles, identity reuse,
    // participant coverage and current authority. Changes force a fresh replay.
    final trustIds =
        sourceRegistry.records.map((r) => r.deviceId).toSet().toList()..sort();
    final trust = canonicalJsonText({
      'registry': sourceRegistry.toJson(),
      'members': sourceView.members,
      'revoked': sourceView.revoked.toList()..sort(),
      'keys': {
        for (final id in trustIds)
          id: sourceView.linkedSigningKey(id) == null
              ? null
              : encodeBase64Url(sourceView.linkedSigningKey(id)!),
      },
    });
    final incremental =
        sameOperation &&
        previous!._trust == trust &&
        previous._replayIndex != null;
    final revoked = incremental ? {...previous._replayRevoked} : <String>{};
    Map<String, Object?>? state = incremental ? previous._projection : null;
    final replayIndex = incremental
        ? previous._replayIndex!
        : RenewalReplayIndex();
    // Take ownership before any await. Failed verification discards the cache;
    // no unverified suffix can become evidence in an older control.
    if (incremental) previous._replayIndex = null;
    final verifiedKeys = <String, String>{
      if (incremental) ...previous._verifiedKeys,
    };
    final recordsById = <String, List<DeviceRecord>>{};
    for (final r in sourceRegistry.records) {
      (recordsById[r.deviceId] ??= []).add(r);
    }
    final registryIds = sourceRegistry.records.map((r) => r.deviceId).toSet();
    final registryKeys = sourceRegistry.records
        .map((r) => encodeBase64Url(r.keys.signing))
        .toSet();
    var cas = incremental ? prefix.last.sourceVersion : 0;
    var bytes = incremental ? previous._projection['logBytes'] as int : 0;
    var replayed = 0;
    for (
      var position = incremental ? prefixLength : 0;
      position < total;
      position++
    ) {
      final c = commandAt(position);
      if ((position >= prefixLength &&
              previous != null &&
              c.sourceVersion < previous.version) ||
          c.sourceVersion <= cas ||
          c.sourceVersion >= version ||
          c.operationId != b.operationId ||
          c.sourceSyncId != sourceSyncId ||
          revoked.contains(c.signerDeviceId)) {
        _bad('order');
      }
      final linked = sourceView.linkedSigningKey(c.signerDeviceId);
      if (linked == null) _bad('signature');
      final key = encodeBase64Url(linked);
      // A private verified previous object binds the immutable prefix and its
      // keys. Recheck present linkage/role; only new signatures need Ed25519.
      if (position >= prefixLength ||
          previous!._verifiedKeys[c.signerDeviceId] != key) {
        await c.verify(binding: b, sourceView: sourceView, historical: true);
      }
      verifiedKeys[c.signerDeviceId] = key;
      final member = (recordsById[c.signerDeviceId] ?? [])
          .where(
            (r) =>
                r.deviceId == c.signerDeviceId &&
                encodeBase64Url(r.keys.signing) ==
                    encodeBase64Url(
                      sourceView.linkedSigningKey(c.signerDeviceId)!,
                    ),
          )
          .firstOrNull;
      if (member == null ||
          (![
                RenewalAction.ack,
                RenewalAction.resume,
                RenewalAction.capability,
              ].contains(c.action) &&
              member.kind != DeviceKind.mobile)) {
        _bad('authority');
      }
      if (c.newDeviceId != null &&
          (registryIds.contains(c.newDeviceId) ||
              registryKeys.contains(c.newSigningKey))) {
        _bad('identity_reused');
      }
      state = replayRenewalCommand(state, c, revoked, index: replayIndex);
      replayIndex.add(c);
      bytes += c.wireBytes;
      if (bytes > kRenewalLogMaxBytes) _bad('size');
      replayed++;
      cas = c.sourceVersion;
    }
    if (sourceView.members.any(
      (id) => !(state!['participants'] as List).contains(id),
    )) {
      _bad('participants_missing');
    }
    if (canonicalJsonText(state) != canonicalJsonText(p)) _bad('projection');
    final backing =
        prefix is _CommandPrefix && prefix._backing.length == prefixLength
        ? prefix._backing
        : prefix.toList();
    backing.addAll(suffix);
    final result = RenewalControl._(
      b,
      version,
      Map.unmodifiable(state!),
      _CommandPrefix(backing, total),
      sourceView,
      Map.unmodifiable(verifiedKeys),
      replayIndex.byHash,
      replayIndex,
      Set.unmodifiable(revoked),
      trust,
      replayed,
    );
    if (result.abortion != null &&
        previous?.abortion?.hash != result.abortion!.hash &&
        !result.abortion!.authorizedIn(sourceView)) {
      _bad('abort_authority');
    }
    return result;
  }

  bool authorizedIn(RegistryView view) =>
      abortion == null &&
      !needsRevalidation &&
      reservation.authorizedIn(view) &&
      !_revoked(reservation.signerDeviceId, view) &&
      [
        plan,
        ?ready,
        ...acknowledgements.entries
            .where((e) => !exclusions.containsKey(e.key))
            .map((e) => e.value),
        ...exclusions.values,
        ?preparation,
        ?confirmation,
      ].every((c) => c.authorizedIn(view) && !_revoked(c.signerDeviceId, view));
  bool destinationRevocationsSatisfied(
    RegistryView destinationView, {
    DeviceRegistry? destinationRegistry,
    RegistryView? sourceView,
  }) {
    final current = sourceView ?? _sourceView;
    final creator = destinationView.member(reservation.newDeviceId!);
    return destinationView.listId == binding.listId &&
        creator != null &&
        creator.kind == DeviceKind.mobile &&
        !destinationView.revoked.contains(creator.deviceId) &&
        encodeBase64Url(creator.signingKey) == reservation.newSigningKey &&
        identities.where((c) => _revoked(c.signerDeviceId, current)).every((c) {
          if (destinationRegistry == null ||
              destinationRegistry.listId != binding.listId) {
            return false;
          }
          if (c.targetSyncId == binding.targetSyncId) {
            return destinationView.explicitlyRevoked.contains(c.newDeviceId) &&
                destinationRegistry.records.every(
                  (r) =>
                      encodeBase64Url(r.keys.signing) != c.newSigningKey ||
                      (r.deviceId == c.newDeviceId &&
                          destinationView.explicitlyRevoked.contains(
                            r.deviceId,
                          )),
                );
          }
          return destinationRegistry.records.every(
            (r) =>
                r.deviceId != c.newDeviceId &&
                encodeBase64Url(r.keys.signing) != c.newSigningKey,
          );
        });
  }

  bool get participantsResolved => participants.every(
    (id) => acknowledgements.containsKey(id) || exclusions.containsKey(id),
  );
  bool canPrepareOrConfirm(
    RegistryView sourceView,
    RegistryView destinationView,
    String callerDeviceId, {
    DeviceRegistry? destinationRegistry,
  }) =>
      authorizedIn(sourceView) &&
      participantsResolved &&
      destinationRevocationsSatisfied(
        destinationView,
        destinationRegistry: destinationRegistry,
        sourceView: sourceView,
      ) &&
      acknowledgements.containsKey(callerDeviceId) &&
      !exclusions.containsKey(callerDeviceId) &&
      sourceView.member(callerDeviceId)?.kind == DeviceKind.mobile;
  bool canDeleteSource(
    RegistryView sourceView,
    String callerDeviceId, {
    RegistryView? destinationView,
    DeviceRegistry? destinationRegistry,
  }) =>
      authorizedIn(sourceView) &&
      participantsResolved &&
      confirmation != null &&
      confirmedVersion == version &&
      acknowledgements.containsKey(callerDeviceId) &&
      !exclusions.containsKey(callerDeviceId) &&
      sourceView.member(callerDeviceId)?.kind == DeviceKind.mobile &&
      (!identities.any((c) => _revoked(c.signerDeviceId, sourceView)) ||
          (destinationView != null &&
              destinationRevocationsSatisfied(
                destinationView,
                destinationRegistry: destinationRegistry,
                sourceView: sourceView,
              )));
  Map<String, Object?> toJson() => _map(jsonDecode(jsonEncode(_projection)));
}
