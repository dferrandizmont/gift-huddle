import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../family/application/family_controller.dart';
import 'lock_controller.dart';

/// Content that LockGate must show over the app, excluding lifecycle privacy.
enum LockGateContent { none, loading, error, setup, locked }

/// Shared by the lock UI and external navigation so a pending PIN without a
/// family never blocks onboarding. Recovery can defer the PIN setup screen.
LockGateContent lockGateContent({
  required AsyncValue<FamilyState> family,
  required AsyncValue<AppLockState> lock,
  required bool recoveryHeld,
}) {
  if (family.isLoading || lock.isLoading) return LockGateContent.loading;
  if (lock.hasError) return LockGateContent.error;
  final current = lock.value;
  if (family.value?.hasFamily != true || current == null || !current.enabled) {
    return LockGateContent.none;
  }
  if (current.needsSetup) {
    return recoveryHeld ? LockGateContent.none : LockGateContent.setup;
  }
  return current.locked ? LockGateContent.locked : LockGateContent.none;
}
