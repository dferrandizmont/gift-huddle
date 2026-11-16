/// Persistable UI projection of the encrypted renewal journal. No gift data,
/// secret-scope counts, keys or clear resource commitments belong here.
library;

import '../../../core/sync/renewal_protocol.dart';

enum RenewalPhase {
  idle,
  proposed,
  preparing,
  reserved,
  publishingDestination,
  destinationReady,
  transferring,
  preparingClose,
  absorbingFinalSnapshot,
  readyToRetire,
  retired,
  recovery,
}

enum RenewalParticipantPhase {
  pending,
  pairing,
  transferring,
  transferred,
  needsAttention,
  explicitlyLost,
}

enum RenewalReason {
  credentials,
  declarations,
  registryRecords,
  signerVouches,
  recordSequence,
  slots,
  keyPackages,
  keyring,
}

enum RenewalBlocker {
  unconfirmedDevice,
  destinationTooSmall,
  destinationIncomplete,
  participantsPending,
  pendingResources,
  unreadableSource,
  missingKeys,
  pendingPublication,
  pendingImport,
  revalidationRequired,
  checkpointMissing,
  sourceGone,
  invalidControl,
  storageFailure,
  explicitLossConfirmationRequired,
}

enum RenewalUiAction {
  propose,
  start,
  resume,
  reconnect,
  excludeParticipant,
  replaceDestination,
  revisePlan,
  previewClose,
  close,
  abort,
}

/// These counters concern protocol capacity only, never gifts or secret scopes.
class RenewalPressure {
  RenewalPressure({
    required this.reason,
    required this.used,
    required this.warnAt,
    required this.limit,
  }) {
    if (used < 0 || warnAt < 1 || limit < warnAt) {
      throw const RenewalProtocolException('pressure');
    }
  }
  final RenewalReason reason;
  final int used;
  final int warnAt;
  final int limit;
  bool get suggested => used >= warnAt;
  bool get exhausted => used >= limit;

  Map<String, Object?> toJson() => {
    'reason': reason.name,
    'used': used,
    'warnAt': warnAt,
    'limit': limit,
  };
  factory RenewalPressure.fromJson(Map<String, Object?> m) => RenewalPressure(
    reason: _enum(RenewalReason.values, m['reason']),
    used: _int(m['used']),
    warnAt: _int(m['warnAt']),
    limit: _int(m['limit']),
  );
}

class RenewalParticipant {
  const RenewalParticipant({
    required this.sourceDeviceId,
    required this.phase,
    this.destinationDeviceId,
    this.kind = RenewalParticipantKind.mobile,
  });

  /// Stable source id distinguishes two devices owned by the same person.
  final String sourceDeviceId;
  final String? destinationDeviceId;
  final RenewalParticipantKind kind;
  final RenewalParticipantPhase phase;

  Map<String, Object?> toJson() => {
    'sourceDeviceId': sourceDeviceId,
    'destinationDeviceId': destinationDeviceId,
    'kind': kind.name,
    'phase': phase.name,
  };
  factory RenewalParticipant.fromJson(Map<String, Object?> m) =>
      RenewalParticipant(
        sourceDeviceId: _string(m['sourceDeviceId']),
        destinationDeviceId: m['destinationDeviceId'] == null
            ? null
            : _string(m['destinationDeviceId']),
        kind: _enum(RenewalParticipantKind.values, m['kind']),
        phase: _enum(RenewalParticipantPhase.values, m['phase']),
      );
}

enum RenewalParticipantKind { mobile, web }

/// The engine saves this under journal.data['view'], preserving other fields.
/// It recovers/reverifies the journal and source trust before granting actions;
/// persisted [actions] are presentation hints and never authorization.
class RenewalState {
  RenewalState({
    this.phase = RenewalPhase.idle,
    this.binding,
    this.sourceVersion,
    Iterable<RenewalParticipant> participants = const [],
    Iterable<RenewalPressure> pressure = const [],
    Iterable<RenewalBlocker> blockers = const [],
    Iterable<RenewalUiAction> actions = const [],
    this.retryAt,
    this.generationFull = false,
    this.hasExplicitLoss = false,
    this.exceptionalCloseConfirmed = false,
  }) : participants = List.unmodifiable(participants),
       pressure = List.unmodifiable(pressure),
       blockers = Set.unmodifiable(blockers),
       actions = Set.unmodifiable(actions) {
    if ((sourceVersion != null && sourceVersion! < 1) ||
        (retryAt != null && !retryAt!.isUtc) ||
        this.participants.map((p) => p.sourceDeviceId).toSet().length !=
            this.participants.length ||
        this.participants.length > kRenewalParticipants ||
        (exceptionalCloseConfirmed && !hasExplicitLoss)) {
      throw const RenewalProtocolException('view');
    }
  }

  final RenewalPhase phase;
  final RenewalBinding? binding;
  final int? sourceVersion;
  final List<RenewalParticipant> participants;
  final List<RenewalPressure> pressure;
  final Set<RenewalBlocker> blockers;
  final Set<RenewalUiAction> actions;

  /// Persist Retry-After as an absolute UTC instant. Waiting never clears work.
  final DateTime? retryAt;

  /// Permanent exhaustion affects the refused operation, not every source write.
  final bool generationFull;
  final bool hasExplicitLoss;
  final bool exceptionalCloseConfirmed;
  bool get renewSuggested => generationFull || pressure.any((p) => p.suggested);
  bool waitingAt(DateTime now) => retryAt != null && now.isBefore(retryAt!);

  /// UI convenience only. Engine independently rechecks trust, CAS and journal.
  bool get canClose =>
      phase == RenewalPhase.readyToRetire &&
      actions.contains(RenewalUiAction.close) &&
      blockers.isEmpty &&
      (!hasExplicitLoss || exceptionalCloseConfirmed);

  Map<String, Object?> toJson() => {
    'v': 1,
    'phase': phase.name,
    'binding': binding?.toJson(),
    'sourceVersion': sourceVersion,
    'participants': participants.map((p) => p.toJson()).toList(),
    'pressure': pressure.map((p) => p.toJson()).toList(),
    'blockers': blockers.map((b) => b.name).toList()..sort(),
    'actions': actions.map((a) => a.name).toList()..sort(),
    'retryAt': retryAt?.millisecondsSinceEpoch,
    'generationFull': generationFull,
    'hasExplicitLoss': hasExplicitLoss,
    'exceptionalCloseConfirmed': exceptionalCloseConfirmed,
  };

  /// Corrupt/future views require recovery; never silently become an idle state.
  factory RenewalState.fromJson(Object? raw) {
    final m = _map(raw);
    if (m['v'] != 1 || m['v'] is! int) {
      throw const RenewalProtocolException('view_version');
    }
    return RenewalState(
      phase: _enum(RenewalPhase.values, m['phase']),
      binding: m['binding'] == null
          ? null
          : RenewalBinding.fromJson(m['binding']),
      sourceVersion: m['sourceVersion'] == null
          ? null
          : _int(m['sourceVersion']),
      participants: _list(m['participants'])
          .map((p) => RenewalParticipant.fromJson(_map(p))),
      pressure: _list(m['pressure'])
          .map((p) => RenewalPressure.fromJson(_map(p))),
      blockers: _list(m['blockers'])
          .map((b) => _enum(RenewalBlocker.values, b)),
      actions: _list(m['actions']).map((a) => _enum(RenewalUiAction.values, a)),
      retryAt: m['retryAt'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              _int(m['retryAt']),
              isUtc: true,
            ),
      generationFull: _bool(m['generationFull']),
      hasExplicitLoss: _bool(m['hasExplicitLoss']),
      exceptionalCloseConfirmed: _bool(m['exceptionalCloseConfirmed']),
    );
  }
}

Never _bad() => throw const RenewalProtocolException('view');
Map<String, Object?> _map(Object? v) =>
    v is Map && v.keys.every((k) => k is String)
    ? Map<String, Object?>.from(v)
    : _bad();
List<Object?> _list(Object? v) => v is List ? List<Object?>.from(v) : _bad();
String _string(Object? v) => v is String && v.isNotEmpty ? v : _bad();
int _int(Object? v) => v is int && v >= 0 && v <= 9007199254740991 ? v : _bad();
bool _bool(Object? v) => v is bool ? v : _bad();
T _enum<T extends Enum>(List<T> values, Object? v) =>
    values.where((e) => e.name == v).firstOrNull ?? _bad();
