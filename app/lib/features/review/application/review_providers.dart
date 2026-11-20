import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/secure_screen.dart';
import '../../family/application/family_controller.dart';
import '../../family/data/storage_providers.dart';
import '../../lock/application/lock_controller.dart';
import '../../recovery/application/recovery_hold.dart';
import '../data/local_review_preferences.dart';
import '../data/store_review_stub.dart'
    if (dart.library.io) '../data/store_review_native.dart';
import 'review_service.dart';

bool get isStoreReviewEnabled =>
    kStoreBuild &&
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

class ReviewVisibility {
  bool isLockGateClear = false;
  int _openPinRoutes = 0;

  bool get canPresent => isLockGateClear && _openPinRoutes == 0;

  void trackPinRoute(TransitionRoute<void> route) {
    _openPinRoutes++;
    // The popped route stays visible until its exit transition finishes.
    unawaited(
      route.completed.then((_) {
        _openPinRoutes--;
      }),
    );
  }
}

final reviewVisibilityProvider = Provider<ReviewVisibility>(
  (_) => ReviewVisibility(),
);

final localReviewPreferencesProvider = Provider<LocalReviewPreferences>(
  (ref) => LocalReviewPreferences(ref.watch(fileStoreProvider)),
);

final reviewServiceProvider = Provider<ReviewService>((ref) {
  final visibility = ref.watch(reviewVisibilityProvider);

  bool isCurrentFamily(String familyId) {
    if (!ref.mounted) return false;
    final family = ref.read(familyControllerProvider);
    return !family.isLoading && family.asData?.value.listId == familyId;
  }

  return ReviewService(
    preferences: ref.watch(localReviewPreferencesProvider),
    store: createStoreReview(),
    isWeb: kIsWeb,
    isStoreBuild: isStoreReviewEnabled,
    clock: clock,
    canPresent: (familyId) {
      if (!visibility.canPresent ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
          !isCurrentFamily(familyId)) {
        return false;
      }
      final lock = ref.read(lockControllerProvider);
      if (lock.isLoading) return false;
      final lockState = lock.asData?.value;
      return lockState != null &&
          !lockState.locked &&
          !lockState.needsSetup &&
          !ref.read(recoveryHoldProvider).value;
    },
  );
});
