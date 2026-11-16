/// UI/engine boundary. Implemented by the next renewal-engine batch; this file
/// does not install providers, perform I/O or fall back to generation reset.
library;

import '../../../core/sync/renewal_protocol.dart';
import 'renewal_state.dart';

/// A preview is bound to a source CAS and an opaque local journal checkpoint.
/// The engine persists the checkpoint before returning it and rejects stale
/// confirmations. The token is local, never sent as an unsigned Worker field.
class RenewalReview {
  const RenewalReview({
    required this.token,
    required this.sourceSyncId,
    required this.sourceVersion,
    this.binding,
  });
  final String token;
  final String sourceSyncId;
  final int sourceVersion;
  final RenewalBinding? binding;
}

class RenewalPreview {
  RenewalPreview({
    required this.review,
    required this.state,
    required this.destinationFits,
  });
  final RenewalReview review;
  final RenewalState state;
  final bool destinationFits;
}

class RenewalClosePreview {
  RenewalClosePreview({
    required this.review,
    required Iterable<RenewalBlocker> blockers,
    required Iterable<String> lostParticipantIds,
    required this.hasLostMaterial,
  }) : blockers = Set.unmodifiable(blockers),
       lostParticipantIds = List.unmodifiable(lostParticipantIds);
  final RenewalReview review;
  final Set<RenewalBlocker> blockers;
  final List<String> lostParticipantIds;

  /// Only a loss flag is public. Detailed manifests remain encrypted and are
  /// shown solely to authorized readers by the reconnection/recovery flow.
  final bool hasLostMaterial;
  bool get exceptional => hasLostMaterial || lostParticipantIds.isNotEmpty;
  bool get canClose => blockers.isEmpty;
}

/// Commands carry explicit human confirmation of a concrete preview. The engine
/// serializes every operation with the family queue, runs generationStore.recover
/// first, persists intentions before network and rechecks all permissions.
abstract interface class RenewalApi {
  RenewalState get state;
  Stream<RenewalState> get changes;

  /// Fetch the log suffix and replay against current source trust. Persist
  /// complete commands, anchor and source CAS before exposing the projection.
  /// A missing control never cancels an observed operation. No implicit start.
  Future<void> refresh();
  Future<RenewalPreview> preview();

  /// User confirmed renewal of the exact reviewed inventory/participants.
  Future<void> start(RenewalReview confirmedReview);

  /// Reuses durable keys/commands; respects retryAt and never deletes old data.
  Future<void> resume();

  /// Opens in-person QR/code flow; pairing alone cannot create an ack.
  Future<void> reconnect(String sourceDeviceId);

  /// Confirms ONE participant as lost; no bulk exclusion, including revoked ids.
  Future<void> excludeParticipant({
    required RenewalReview confirmedReview,
    required String sourceDeviceId,
  });

  /// Explicit revalidation after revocation, revision + 1 and fresh receipts.
  Future<void> revisePlan(RenewalReview confirmedReview);

  /// Same remote operation and original source. Use prepareReplacement to
  /// atomically persist a fresh destination plus per-destination recovery data;
  /// never archive the operation to obtain another preparation. Reuse the
  /// selected secrets after recover(). Create its minimal remote base BEFORE
  /// replace; if CAS loses, read the winning control before deleting only our
  /// unreserved base. Preserve targets with transfers as recovery branches.
  /// If the destination creator is revoked, recover changes the phase and
  /// resets the active branch quota; it appends to the same signed log.
  /// Every command binds prev (null only for reserve). Obtain/persist a trusted
  /// mobile anchor; fetch pinned pages with getRenewalLogPage from the previous
  /// verified height and replay with RenewalControl.fromLog. A Worker head is
  /// insufficient as the first freshness anchor. Keep all accepted commands.
  Future<void> replaceDestination(RenewalReview confirmedReview);

  /// Signed cancellation only without transfers, acknowledged branches or a
  /// barrier. Persist and verify the remote tombstone before projecting idle;
  /// a missing control is never cancellation. Preserve local recovery contexts.
  /// verify must accept a NEW tombstone with current mobile authority; a valid
  /// historical signature or authorizedIn == false is not cancellation authority.
  Future<void> abort(RenewalReview confirmedReview);
  Future<RenewalClosePreview> previewClose();

  /// Rechecks final absorption/publication and current ETag before DELETE.
  /// acceptExplicitLoss is required for exceptional close, never inferred from
  /// participant absence. Pending material blocks normal close.
  /// Derive destinationView from the supplied destinationRegistry and pass BOTH
  /// to canPrepareOrConfirm/canDeleteSource. Same-target mappings need explicit
  /// signed revocation; old-target mappings forbid any record reusing the old
  /// id or signing key, including unlinked records. Check on every publication
  /// and reconnection as well as each close step. Persist the signed vetoes and
  /// source trust proofs in the destination context before DELETE/journal archive;
  /// transfer and verify them on later reconnections as permanent prohibitions.
  /// Persist ALL complete signed log commands, anchors, source registry/trust links
  /// and current signed revocations, not just the journal's references/digest.
  /// Apply current source revocations to every historical mapping on reconnection.
  /// Service revocations during renewal use the signed revoke log command;
  /// persist its registry counterpart too, publishing it when possible. The
  /// signed log event remains sufficient while the source registry is frozen.
  /// Capability changes also use signed log commands. A returning excluded
  /// participant signs resume; a GET only fences service close and proves no
  /// signed transition. Revalidate and collect fresh receipts after resume.
  /// Integration must prove restart/reconnection after source DELETE and reduced
  /// journal archive; this interface alone does not implement that durability.
  Future<void> close({
    required RenewalReview confirmedReview,
    bool acceptExplicitLoss = false,
  });
}

/// Recoverable application failure. Transport errors keep their original typed
/// retryAfter/conflict/Gone information; neither class triggers a context reset.
class RenewalReviewChangedException implements Exception {
  const RenewalReviewChangedException();
}
