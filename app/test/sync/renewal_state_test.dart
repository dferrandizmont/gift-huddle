import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/renewal_protocol.dart';
import 'package:regalos/features/sync/application/renewal_api.dart';
import 'package:regalos/features/sync/application/renewal_state.dart';

void main() {
  test('journal view round-trip preserves waiting, full generation and explicit loss', () {
    final state = RenewalState(
      phase: RenewalPhase.transferring,
      retryAt: DateTime.utc(2026, 11, 15),
      generationFull: true,
      hasExplicitLoss: true,
      blockers: [RenewalBlocker.pendingResources],
      participants: [
        const RenewalParticipant(
          sourceDeviceId: 'aritz-phone',
          destinationDeviceId: 'aritz-new',
          phase: RenewalParticipantPhase.transferred,
        ),
        const RenewalParticipant(
          sourceDeviceId: 'nora-web',
          kind: RenewalParticipantKind.web,
          phase: RenewalParticipantPhase.pairing,
        ),
      ],
      actions: [RenewalUiAction.resume],
      pressure: [
        RenewalPressure(
          reason: RenewalReason.slots,
          used: 48,
          warnAt: 48,
          limit: 64,
        ),
      ],
    );
    final recovered = RenewalState.fromJson(
      jsonDecode(jsonEncode(state.toJson())),
    );
    expect(recovered.toJson(), state.toJson());
    expect(recovered.renewSuggested, isTrue);
    expect(recovered.waitingAt(DateTime.utc(2026, 11, 14)), isTrue);
    expect(recovered.waitingAt(DateTime.utc(2026, 11, 15)), isFalse);
    expect(recovered.generationFull, isTrue);
    expect(recovered.canClose, isFalse);
    expect(recovered.participants.last.phase, RenewalParticipantPhase.pairing);
  });

  test(
    'capacity projection distinguishes warning and permanent exhaustion',
    () {
      for (final (reason, warn, limit) in [
        (RenewalReason.credentials, 48, 64),
        (RenewalReason.declarations, 384, 512),
        (RenewalReason.registryRecords, 48, 64),
        (RenewalReason.signerVouches, 24, 32),
        (RenewalReason.recordSequence, 12, 16),
        (RenewalReason.slots, 48, 64),
      ]) {
        for (final used in [warn - 1, warn, warn + 1, limit]) {
          final p = RenewalPressure(
            reason: reason,
            used: used,
            warnAt: warn,
            limit: limit,
          );
          final s = RenewalState(pressure: [p]);
          expect(s.renewSuggested, used >= warn);
          expect(p.exhausted, used >= limit);
        }
      }
    },
  );

  test(
    'loss requires separate exceptional close confirmation, blockers still win',
    () {
      RenewalState state({bool accepted = false, bool blocked = false}) =>
          RenewalState(
            phase: RenewalPhase.readyToRetire,
            hasExplicitLoss: true,
            exceptionalCloseConfirmed: accepted,
            actions: [RenewalUiAction.close],
            blockers: blocked ? [RenewalBlocker.pendingResources] : [],
          );
      expect(state().canClose, isFalse);
      expect(state(accepted: true).canClose, isTrue);
      expect(state(accepted: true, blocked: true).canClose, isFalse);
    },
  );

  test(
    'future or corrupt journal projection fails closed instead of reset',
    () {
      final m = RenewalState().toJson();
      for (final broken in [
        {...m, 'v': 2},
        {...m, 'phase': 'unknown'},
        {
          ...m,
          'blockers': ['unknown'],
        },
        {...m, 'retryAt': -1},
        {...m, 'generationFull': null},
        {...m, 'exceptionalCloseConfirmed': true},
      ]) {
        expect(
          () => RenewalState.fromJson(broken),
          throwsA(isA<RenewalProtocolException>()),
        );
      }
      expect(
        () => RenewalState().actions.add(RenewalUiAction.close),
        throwsUnsupportedError,
      );
    },
  );

  test('reviewable close records individual losses without exposing secret inventory', () {
    const review = RenewalReview(
      token: 'local-journal-checkpoint',
      sourceSyncId: 'AQEBAQEBAQEBAQEBAQEBAQ',
      sourceVersion: 12,
    );
    final preview = RenewalClosePreview(
      review: review,
      blockers: [RenewalBlocker.unreadableSource],
      lostParticipantIds: ['nora-phone'],
      hasLostMaterial: true,
    );
    expect(preview.exceptional, isTrue);
    expect(preview.canClose, isFalse);
    expect(preview.lostParticipantIds, ['nora-phone']);
  });
}
