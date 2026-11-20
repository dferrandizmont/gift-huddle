import 'package:in_app_review/in_app_review.dart';

import '../domain/review_ports.dart';

StoreReview createStoreReview() => _NativeStoreReview();

class _NativeStoreReview implements StoreReview {
  @override
  Future<bool> isAvailable() => InAppReview.instance.isAvailable();

  @override
  Future<void> requestReview({required bool Function() canPresent}) async {
    if (!canPresent()) return;
    // Android's plugin prepares and launches the review in one call. A PIN
    // can appear during native preparation, when Dart can no longer cancel
    // the request. The Google Play sheet is system UI with no app data.
    await InAppReview.instance.requestReview();
  }
}
