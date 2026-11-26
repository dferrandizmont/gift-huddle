import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../family/application/family_controller.dart';
import '../presentation/web_gate_model.dart';
import 'web_secrets.dart';
import 'web_sync_engine.dart';

/// Overridden only inside the unlocked session's container.
final webGateActionsProvider = Provider<WebGateActions>(
  (ref) => throw StateError('No web session'),
);
final webSyncEngineProvider = Provider<WebSyncEngine>(
  (ref) => throw StateError('No web session'),
);

class WebDeviceState {
  const WebDeviceState({
    required this.status,
    required this.hasRoots,
    required this.setAsideChanges,
    required this.persistenceDenied,
    this.activity = WebSyncActivity.idle,
    this.lastUnlockFailedAttempts = 0,
    this.secrets = WebSecretsState.off,
    this.pendingSecretGifts = 0,
    this.heldSecretChanges = 0,
    this.droppedSecretChanges = 0,
    this.heldInboxNames = const <String>[],
    this.heldPlanChanges = 0,
    this.rejectedSecretRecipientDeletes = 0,
    this.rejectedDevicePersonNames = const [],
  });

  /// Wish plans kept in the queue because another phone of the family does
  /// not understand them yet («Actualiza los demás móviles», ADR 0010).
  final int heldPlanChanges;

  /// What the web can do with secret gifts now (1.0.6, ADR 0009): the
  /// screens show «vuelve a conectar…», «abre la app en tu móvil…» or the
  /// shared-computer notice from here.
  final WebSecretsState secrets;

  /// Secret gifts with changes waiting for the phone («Pendiente de tu
  /// móvil»). Also the warning before «Olvidar este ordenador».
  final int pendingSecretGifts;

  /// Secret changes kept in the queue while the surprises are closed.
  final int heldSecretChanges;

  /// Secret changes dropped in this session because their gift is gone.
  final int droppedSecretChanges;

  /// Names of the people whose change box the server has not accepted yet
  /// (it is retried by itself).
  final List<String> heldInboxNames;

  /// Whether the idle lock is the short one (5 minutes).
  bool get secretsOpen => secrets == WebSecretsState.open;
  final WebSyncStatus status;
  final bool hasRoots, persistenceDenied;
  final int setAsideChanges;
  final int rejectedSecretRecipientDeletes;
  final List<String> rejectedDevicePersonNames;

  /// Uploading / offline hint for the status line (read-only).
  final WebSyncActivity activity;

  /// Wrong PINs since the last correct unlock, as reported on opening.
  final int lastUnlockFailedAttempts;
}

/// Whether the "failed attempts" notice was already dismissed in this unlocked
/// session. It lives in the session container, so a new unlock starts fresh.
class WebFailedAttemptsDismissed extends Notifier<bool> {
  @override
  bool build() => false;

  /// Hides the notice for the rest of the session.
  void dismiss() => state = true;
}

final webFailedAttemptsDismissedProvider =
    NotifierProvider<WebFailedAttemptsDismissed, bool>(
      WebFailedAttemptsDismissed.new,
    );

/// Batch 5b can watch this for the pending/re-pair, set-aside and persistence
/// notices. Family candidates also notify when only the registry has changed.
final webDeviceStateProvider = Provider<WebDeviceState>((ref) {
  ref.watch(familyControllerProvider);
  final engine = ref.watch(webSyncEngineProvider);
  return WebDeviceState(
    status: engine.status,
    hasRoots: engine.hasRoots,
    setAsideChanges: engine.setAsideCount,
    rejectedSecretRecipientDeletes: engine.rejectedSecretRecipientDeletes,
    rejectedDevicePersonNames: engine.rejectedDevicePersonNames,
    persistenceDenied: engine.vault.persistenceGranted == false,
    activity: engine.activity,
    lastUnlockFailedAttempts: engine.vault.lastUnlockFailedAttempts,
    secrets: engine.secrets.state,
    pendingSecretGifts: engine.pendingSecretGiftIds.length,
    heldSecretChanges: engine.heldSecretCount,
    droppedSecretChanges: engine.discardedSecretCount,
    heldPlanChanges: engine.heldPlanCount,
    heldInboxNames: [
      for (final id in engine.heldInboxPeople)
        ?ref
            .watch(familyControllerProvider)
            .value
            ?.fullView
            .recipientsById[id]
            ?.name,
    ]..sort(),
  );
});
