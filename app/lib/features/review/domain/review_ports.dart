typedef ReviewHistory = ({int count, DateTime? lastRequestedAt});

const kReviewDeliveryTarget = 5;

abstract interface class ReviewPreferences {
  Future<ReviewHistory> readHistory();
  Future<void> writeHistory(ReviewHistory history);
}

abstract interface class StoreReview {
  Future<bool> isAvailable();

  /// Rechecks visibility immediately before invoking the platform.
  Future<void> requestReview({required bool Function() canPresent});
}
