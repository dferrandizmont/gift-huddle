import '../domain/review_ports.dart';

StoreReview createStoreReview() => _UnavailableStoreReview();

class _UnavailableStoreReview implements StoreReview {
  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<void> requestReview({required bool Function() canPresent}) async {}
}
