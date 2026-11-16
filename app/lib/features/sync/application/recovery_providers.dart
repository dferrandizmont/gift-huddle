import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/recovery.dart';
import '../../../core/sync/envelope.dart';
import '../../../core/sync/device_registry.dart';
import '../data/sync_transport.dart';
import '../../family/application/family_controller.dart';
import '../../family/data/device_keys_store.dart';
import '../../family/data/family_store.dart';
import '../../family/data/generation_store.dart';
import '../../family/data/recovery_store.dart';
import '../../family/data/recovery_wordlist_loader.dart';
import '../../web_device/application/web_app_provider.dart';
import '../data/recovery_transport.dart';
import '../data/sync_config.dart';
import '../data/sync_transport_common.dart';
import '../data/sync_transport_v2.dart';
import 'app_sync_v2_local.dart';
import 'pairing_v2_controller.dart';
import 'recovery_controller.dart';
import 'recovery_engine.dart';
import 'recovery_maintenance.dart';
import 'sync_controller.dart';
import 'sync_v2_engine.dart';

export 'recovery_maintenance.dart' show RecoveryReadiness, RecoveryStatus;
export '../../family/data/recovery_store.dart' show RecoveryPhase;

final recoverySupportedProvider = Provider<bool>(
  (ref) =>
      !ref.watch(webAppProvider) &&
      ref.watch(familyStoreProvider).supportsRecovery,
);

final recoveryTransportProvider = Provider<RecoveryTransport?>((ref) {
  if (!ref.watch(recoverySupportedProvider)) return null;
  final base = ref.watch(syncTransportProvider);
  if (base is! BaseSyncTransport) return null;
  return RecoveryClient(
    base: base.endpoint.base,
    sendRequest: (method, uri, {body, headers = const {}}) =>
        base.send(method, uri, body: body, headers: headers),
  );
});

final recoveryReaderProvider = Provider<RecoveryReader?>((ref) {
  if (!ref.watch(recoverySupportedProvider)) return null;
  final transport = ref.watch(syncV2TransportProvider);
  return transport == null
      ? null
      : EngineRecoveryReader(
          generations: ref.watch(generationStoreProvider),
          transport: transport,
        );
});

final recoveryControllerProvider = Provider<RecoveryController?>((ref) {
  if (!ref.watch(recoverySupportedProvider)) return null;
  final transport = ref.watch(recoveryTransportProvider);
  final reader = ref.watch(recoveryReaderProvider);
  if (transport == null || reader == null) return null;
  return RecoveryController(
    store: ref.watch(recoveryStoreProvider),
    generations: ref.watch(generationStoreProvider),
    transport: transport,
    reader: reader,
    onClaimSent: () {
      if (ref.mounted) {
        ref.read(recoveryApplicationProvider.notifier).reportClaimSent();
      }
    },
    onPhase: (phase) {
      if (ref.mounted) {
        ref.read(recoveryApplicationProvider.notifier).reportPhase(phase);
      }
    },
  );
});

/// Runs before FamilyController loads editable state. Uses only root stores and
/// the isolated reader; it cannot wait on FamilyController's own future.
Future<void> resumeRecoveryBeforeFamily(Ref ref) async {
  if (!ref.read(recoverySupportedProvider)) return;
  await ref.read(generationStoreProvider).recover();
  final store = ref.read(recoveryStoreProvider);
  final journal = await store.readRestore();
  if (journal == null) return;
  if (journal.phase == RecoveryPhase.active) {
    await store.clearCompletedRestoreGate();
    return;
  }
  final controller = ref.read(recoveryControllerProvider);
  if (controller == null) return;
  try {
    await ref.read(v2FamilyLockProvider).run(() => controller.resume());
  } on Object {
    // Durable intent remains; the normal foreground/backoff path resumes it.
  }
}

Future<RecoveryMaintenance?> recoveryMaintenanceWithinLock(Ref ref) async {
  if (!ref.read(recoverySupportedProvider)) return null;
  final family = ref.read(familyStoreProvider);
  final identity = await family.readSyncV2();
  final keys = await ref.read(deviceKeysStoreProvider).read();
  final transport = ref.read(recoveryTransportProvider);
  final reader = ref.read(recoveryReaderProvider);
  if (identity == null || keys == null || transport == null || reader == null) {
    return null;
  }
  return RecoveryMaintenance(
    store: ref.read(recoveryStoreProvider),
    family: family,
    exporter: RecoveryExporter(ref.read(generationStoreProvider), reader),
    transport: transport,
    auth: V2Auth(
      syncId: identity.syncId,
      deviceId: identity.deviceId,
      credential: keys.serviceCredential,
    ),
  );
}

class RecoveryApplicationException implements Exception {
  const RecoveryApplicationException(this.code, {this.retryable = false});
  final String code;
  final bool retryable;
}

/// Check under the family lock before changing family or pairing credentials.
Future<void> requireNoPendingRestore(Ref ref) async {
  if (!ref.read(recoverySupportedProvider)) return;
  final journal = await ref.read(recoveryStoreProvider).readRestore();
  if (journal != null && journal.phase != RecoveryPhase.active) {
    throw const RecoveryApplicationException('restore_pending');
  }
}

/// Deliberately returned by create/rotate only. Never put words/QR in provider
/// state; refresh/rebuild/restart cannot reveal an existing code.
class RecoveryCodeDisplay {
  RecoveryCodeDisplay(this.words, this.qrText);
  final List<String> words;
  final String qrText;
}

class RecoveryApplication extends Notifier<RecoveryStatus> {
  @override
  RecoveryStatus build() {
    if (ref.watch(recoverySupportedProvider)) {
      scheduleMicrotask(() {
        if (ref.mounted) unawaited(refresh());
      });
    }
    return const RecoveryStatus(RecoveryReadiness.absent);
  }

  void reportPhase(RecoveryPhase phase) {
    state = RecoveryStatus(
      RecoveryReadiness.updatePending,
      phase: phase,
      claimSent: phase == RecoveryPhase.locating ? false : state.claimSent,
      installationTransferred: state.installationTransferred,
    );
  }

  void reportClaimSent() {
    state = RecoveryStatus(
      state.readiness,
      cause: state.cause,
      phase: state.phase,
      claimSent: true,
      installationTransferred: state.installationTransferred,
      canDismissFailure: state.canDismissFailure,
    );
  }

  void _failure(RecoveryReadiness readiness, String cause) {
    state = RecoveryStatus(
      readiness,
      cause: cause,
      phase: state.phase,
      claimSent: state.claimSent,
      installationTransferred:
          state.installationTransferred ||
          readiness == RecoveryReadiness.transferred,
    );
  }

  Future<T> _action<T>(Future<T> Function() task) async {
    if (!ref.read(recoverySupportedProvider)) {
      throw const RecoveryApplicationException('not_configured');
    }
    try {
      return await task();
    } on RecoveryIncomplete catch (e) {
      _failure(RecoveryReadiness.needsAttention, e.code);
      throw RecoveryApplicationException(e.code);
    } on RecoverySourceException catch (e) {
      _failure(RecoveryReadiness.needsAttention, e.code);
      throw RecoveryApplicationException(e.code);
    } on SyncTransportException catch (e) {
      final retryable = {
        SyncFailure.network,
        SyncFailure.server,
        SyncFailure.rateLimited,
      }.contains(e.failure);
      _failure(
        retryable
            ? RecoveryReadiness.updatePending
            : RecoveryReadiness.needsAttention,
        e.failure.name,
      );
      throw RecoveryApplicationException(e.failure.name, retryable: retryable);
    } on V2TransferredException {
      _failure(RecoveryReadiness.transferred, 'transferred');
      throw const RecoveryApplicationException('transferred');
    } on V2ForbiddenException catch (e) {
      final cause = knownRecoveryServerCodes.contains(e.code)
          ? e.code
          : 'invalid_response';
      final transferred = cause == 'credential_replaced';
      _failure(
        transferred
            ? RecoveryReadiness.transferred
            : RecoveryReadiness.needsAttention,
        cause,
      );
      throw RecoveryApplicationException(cause);
    } on StateError catch (e) {
      throw RecoveryApplicationException(
        e.message == 'transferred' ? 'transferred' : 'operation_pending',
      );
    } on FormatException {
      throw const RecoveryApplicationException('unsupported_or_invalid_data');
    } on RecoveryException {
      throw const RecoveryApplicationException('invalid_code_or_capsule');
    } on RecoveryTransportException catch (e) {
      final retryable = e.retryable;
      _failure(
        e.code == 'credential_replaced'
            ? RecoveryReadiness.transferred
            : retryable
            ? RecoveryReadiness.updatePending
            : RecoveryReadiness.needsAttention,
        e.code,
      );
      throw RecoveryApplicationException(e.code, retryable: retryable);
    } on RecoveryApplicationException {
      rethrow;
    } on Object {
      _failure(RecoveryReadiness.needsAttention, 'local_or_unsupported_state');
      throw const RecoveryApplicationException('local_or_unsupported_state');
    }
  }

  Future<RecoveryCodeDisplay> createCode() => _newCode(false);
  Future<RecoveryCodeDisplay> rotateCode() => _newCode(true);

  Future<RecoveryCodeDisplay> _newCode(bool rotate) => _action(() async {
    if (ref.read(recoveryTransportProvider) == null ||
        ref.read(recoveryReaderProvider) == null) {
      throw const RecoveryApplicationException('not_configured');
    }
    final code = RecoveryCode.generate();
    await ref.read(v2FamilyLockProvider).run(() async {
      final family = ref.read(familyStoreProvider);
      final existingIdentity = await family.readSyncV2();
      if (existingIdentity != null) {
        final journal = ref.read(recoveryStoreProvider);
        final pending = await journal.readMaintenance(existingIdentity.syncId);
        if (pending != null) {
          throw const RecoveryApplicationException('operation_pending');
        }
        final material = await journal.readMaterial(existingIdentity.syncId);
        final configured = material != null && material['retired'] != true;
        if (rotate && !configured) {
          throw const RecoveryApplicationException('not_configured');
        }
        if (!rotate && configured) {
          throw const RecoveryApplicationException('already_configured');
        }
      }
      // One owner of the non-reentrant lock, including v1 migration.
      if (await family.readRecoverySetup() != null) {
        throw const RecoveryApplicationException('setup_pending');
      }
      await family.prepareRecoveryCode(
        encodeBase64Url(code.entropy),
        rotate: rotate,
      );
      await family.setRecoveryActivationPending(true);
      final local = await ensureV2FamilyWithinLock(ref);
      await ref.read(generationStoreProvider).adoptCurrent();
      await family.enableRemoteSync();
      final maintenance = (await recoveryMaintenanceWithinLock(ref))!;
      await maintenance.queueNewCode(code, rotate: rotate);
      await family.clearRecoverySetup();
      final transport = ref.read(syncV2TransportProvider);
      if (transport == null) {
        throw const RecoveryApplicationException('not_configured');
      }
      final engine = SyncV2Engine(transport: transport, local: local);
      await engine.ensureCreated();
      await engine.sync();
      await family.setRecoveryActivationPending(false);
      await maintenance.resume();
      state = await maintenance.status();
      if (state.readiness != RecoveryReadiness.confirmationPending) {
        throw RecoveryApplicationException(
          state.cause ?? 'publication_pending',
          retryable: state.readiness == RecoveryReadiness.updatePending,
        );
      }
    });
    unawaited(ref.read(syncControllerProvider.notifier).resumeAfterPairing());
    final display = await takeCreatedCode();
    if (display == null) {
      throw RecoveryApplicationException(state.cause ?? 'publication_pending');
    }
    return display;
  });

  /// Probe before requesting PIN/biometrics; leaves the delivery untouched.
  Future<bool> hasCodeDisplay() async {
    if (!ref.read(recoverySupportedProvider)) return false;
    final identity = await ref.read(familyStoreProvider).readSyncV2();
    return identity != null &&
        await ref.read(recoveryStoreProvider).hasCodeDisplay(identity.syncId);
  }

  /// Consume only after the user has passed PIN/biometric verification.
  Future<RecoveryCodeDisplay?> takeCreatedCode() async {
    if (!ref.read(recoverySupportedProvider)) return null;
    final wordlist = await loadRecoveryWordlist();
    final identity = await ref.read(familyStoreProvider).readSyncV2();
    if (identity == null) return null;
    final entropy = await ref
        .read(recoveryStoreProvider)
        .takeCodeDisplay(identity.syncId);
    if (entropy == null) return null;
    final code = RecoveryCode(decodeBase64Url(entropy));
    await refresh();
    return RecoveryCodeDisplay(code.toWords(wordlist), code.toQrText());
  }

  /// Called after the word check succeeds, with this flow's one-time display.
  Future<void> confirmCreatedCode(RecoveryCodeDisplay display) =>
      _action(() async {
        await ref.read(v2FamilyLockProvider).run(() async {
          final identity = await ref.read(familyStoreProvider).readSyncV2();
          if (identity == null) {
            throw const RecoveryApplicationException('not_configured');
          }
          final code = RecoveryCode.fromQrText(display.qrText);
          await ref
              .read(recoveryStoreProvider)
              .confirmCode(identity.syncId, encodeBase64Url(code.entropy));
          await _refresh();
        });
      });

  /// Advisory for the removal dialog. Includes web credentials. The operation
  /// rechecks the server under CAS. Falls back to known local access offline;
  /// never changes recovery status, resumes local work or queues a removal.
  Future<bool> removalStopsRemoteSync() async {
    var stops = true;
    try {
      if (!ref.read(recoverySupportedProvider)) return stops;
      final store = ref.read(familyStoreProvider);
      final identity = await store.readSyncV2();
      if (identity == null) return stops;
      final cached = V2SyncState.fromJson(await store.readSyncV2State());
      final departed = cached.health?.departedDevices ?? const <String>{};
      bool other(String id) =>
          id != identity.deviceId && !departed.contains(id);
      stops =
          !(cached.health?.unbackedCredentials.any(other) ?? false) &&
          !cached.pendingRevocations.any(other) &&
          !cached.pendingUnbackedRevocations.any(other);
      final keys = await ref.read(deviceKeysStoreProvider).read();
      if (keys == null) return stops;
      final registry = await store.readRegistry(
        anchor: RegistryAnchor(
          deviceId: identity.deviceId,
          signingKey: keys.publicKeys.signing,
        ),
      );
      if (registry != null) {
        final view = await registry.viewFor(
          me: identity.deviceId,
          mySigningKey: keys.publicKeys.signing,
          // Only membership matters here, not surprise entitlements.
          livePeople: const {},
        );
        stops =
            stops &&
            !view.members.any(other) &&
            !view.pending.any((d) => other(d.deviceId));
      }
      final transport = ref.read(syncV2TransportProvider);
      if (transport == null) return stops;
      final got = await transport.getList(
        V2Auth(
          syncId: identity.syncId,
          deviceId: identity.deviceId,
          credential: keys.serviceCredential,
        ),
      );
      if (got is V2GetOk) {
        return !got.snapshot.devices.any(
          (d) => !d.revoked && d.deviceId != identity.deviceId,
        );
      }
      if (got is V2GetNotFound) return true;
    } on Object {
      // This preview is advisory, including when local data cannot be read.
    }
    return stops;
  }

  Future<void> retireCode() => _action(() async {
    final sync = ref.read(syncControllerProvider.notifier);
    await sync.suspendForRecovery();
    try {
      await ref.read(v2FamilyLockProvider).run(() async {
        final maintenance = await recoveryMaintenanceWithinLock(ref);
        if (maintenance == null) {
          throw const RecoveryApplicationException('not_configured');
        }
        await ref.read(familyStoreProvider).setRecoveryRemovalPending(true);
        await maintenance.retire();
        state = await maintenance.status();
        await sync.finishRecoveryRemovalWithinLock();
      });
    } finally {
      sync.finishRecoveryClaim();
      unawaited(sync.syncNow());
    }
  });

  /// Cancels maintenance, preserving the installed code unless a rotation
  /// already committed remotely. In that case, completes its one-time delivery
  /// ([hasCodeDisplay]/[takeCreatedCode]). Ambiguous creates are removed remotely.
  Future<void> cancelMaintenance() => _action(() async {
    await ref.read(v2FamilyLockProvider).run(() async {
      final maintenance = await recoveryMaintenanceWithinLock(ref);
      if (maintenance == null) {
        throw const RecoveryApplicationException('not_configured');
      }
      await maintenance.cancel();
      await _clearCancelledRemoval();
      state = await maintenance.status();
    });
  });

  /// Dismiss a closed maintenance failure (see [RecoveryStatus.canDismissFailure]).
  /// Pending maintenance/restore must be resolved or cancelled first. Refreshes
  /// to absent/prepared according to the remaining installed material.
  Future<void> dismissFailure() => _action(() async {
    await ref.read(v2FamilyLockProvider).run(() async {
      await requireNoPendingRestore(ref);
      final identity = await ref.read(familyStoreProvider).readSyncV2();
      if (identity != null) {
        await ref.read(recoveryStoreProvider).dismissFailure(identity.syncId);
        await _clearCancelledRemoval();
      }
      await _refresh();
    });
  });

  Future<void> _clearCancelledRemoval() async {
    final family = ref.read(familyStoreProvider);
    final identity = await family.readSyncV2();
    if (identity == null) return;
    final recovery = ref.read(recoveryStoreProvider);
    final pending = await recovery.readMaintenance(identity.syncId);
    if (pending?['kind'] != RecoveryMaintenanceKind.retire.name &&
        (await recovery.readMaterial(identity.syncId))?['retired'] != true) {
      await family.setRecoveryRemovalPending(false);
    }
  }

  Future<void> refresh() async {
    try {
      await _refresh();
    } on Object {
      if (ref.mounted) {
        _failure(
          RecoveryReadiness.needsAttention,
          'local_or_unsupported_state',
        );
      }
    }
  }

  Future<void> _refresh() async {
    if (!ref.read(recoverySupportedProvider)) return;
    final transferred = await ref.read(familyStoreProvider).isTransferred();
    if (!ref.mounted) return;
    state = RecoveryStatus(
      state.readiness,
      cause: state.cause,
      phase: state.phase,
      claimSent: state.claimSent,
      installationTransferred: transferred,
      canDismissFailure: state.canDismissFailure,
    );
    final journal = await ref.read(recoveryStoreProvider).readRestore();
    if (!ref.mounted) return;
    if (journal != null && journal.phase != RecoveryPhase.active) {
      state = RecoveryStatus(
        journal.phase == RecoveryPhase.needsAttention
            ? RecoveryReadiness.needsAttention
            : RecoveryReadiness.updatePending,
        phase: journal.phase,
        cause: journal.data['reason'] as String?,
        claimSent: journal.claimSent,
        installationTransferred: transferred,
      );
      return;
    }
    if (transferred) {
      if (ref.mounted) {
        state = const RecoveryStatus(
          RecoveryReadiness.transferred,
          installationTransferred: true,
        );
      }
      return;
    }
    if (!ref.mounted) return;
    final maintenance = await recoveryMaintenanceWithinLock(ref);
    if (maintenance != null) {
      final next = await maintenance.status();
      if (ref.mounted) state = next;
    } else if (ref.mounted) {
      state = const RecoveryStatus(RecoveryReadiness.absent);
    }
  }

  /// A different v2 family stops before claim with cause `different_family`.
  /// After confirmation, repeat the same code with [replaceExisting] true.
  /// Existing v1 data requires that flag too (`existing_v1_family`).
  Future<void> restoreWords(String words, {bool replaceExisting = false}) =>
      _action(
        () async => _restore(
          RecoveryCode.fromWords(words, await loadRecoveryWordlist()),
          replaceExisting: replaceExisting,
        ),
      );

  /// Same replacement confirmation contract as [restoreWords].
  Future<void> restoreQr(String text, {bool replaceExisting = false}) =>
      _action(
        () => _restore(
          RecoveryCode.fromQrText(text),
          replaceExisting: replaceExisting,
        ),
      );

  Future<void> _restore(
    RecoveryCode code, {
    required bool replaceExisting,
  }) async {
    final controller = ref.read(recoveryControllerProvider);
    if (controller == null) {
      throw const RecoveryApplicationException('not_configured');
    }
    final sync = ref.read(syncControllerProvider.notifier);
    await sync.suspendForRecovery();
    late RecoveryJournal journal;
    try {
      journal = await ref
          .read(v2FamilyLockProvider)
          .run(() => controller.start(code, replaceExisting: replaceExisting));
    } on Object {
      // Resume the durable restore through the normal foreground/backoff path.
      sync.finishRecoveryClaim();
      unawaited(sync.syncNow());
      rethrow;
    }
    sync.finishRecoveryClaim();
    await _afterRestore(journal);
  }

  /// Discards local restore staging under the family lock. A confirmed remote
  /// claim is not undone; its retired installation stays read-only and can
  /// itself be recovered again using the code.
  Future<void> abandon() => _action(() async {
    final controller = ref.read(recoveryControllerProvider);
    final sync = ref.read(syncControllerProvider.notifier);
    await sync.suspendForRecovery();
    try {
      await ref
          .read(v2FamilyLockProvider)
          .run(
            () => controller == null
                ? RecoveryController.abandonLocal(
                    ref.read(recoveryStoreProvider),
                    ref.read(generationStoreProvider),
                  )
                : controller.abandon(),
          );
    } finally {
      sync.finishRecoveryClaim();
    }
    ref.invalidate(familyControllerProvider);
    await ref.read(familyControllerProvider.future);
    await refresh();
    unawaited(sync.resumeAfterPairing());
  });

  /// A maintenance failure belongs to recovery status, not the sync round.
  Future<void> reportMaintenanceFailure(Object error) async {
    try {
      await _action<void>(() => Future<void>.error(error));
    } on RecoveryApplicationException {
      /* Status was set by _action. */
    }
  }

  Future<void> retry() => _action(() async {
    final controller = ref.read(recoveryControllerProvider);
    final journal = await ref.read(recoveryStoreProvider).readRestore();
    if (controller != null &&
        journal != null &&
        journal.phase != RecoveryPhase.active) {
      final result = await ref
          .read(v2FamilyLockProvider)
          .run(() => controller.retryIncomplete());
      await _afterRestore(result);
    } else {
      await ref.read(syncControllerProvider.notifier).syncNow();
      await refresh();
    }
  });

  Future<void> _afterRestore(RecoveryJournal journal) async {
    if (journal.phase == RecoveryPhase.active) {
      ref.invalidate(familyStoreProvider);
      ref.invalidate(deviceKeysStoreProvider);
      ref.invalidate(familyControllerProvider);
      await ref.read(familyControllerProvider.future);
      unawaited(ref.read(syncControllerProvider.notifier).resumeAfterPairing());
    }
    await refresh();
  }
}

final recoveryApplicationProvider =
    NotifierProvider<RecoveryApplication, RecoveryStatus>(
      RecoveryApplication.new,
    );
final recoveryStatusProvider = Provider<RecoveryStatus>(
  (ref) => ref.watch(recoveryApplicationProvider),
);
