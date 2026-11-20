import 'package:clock/clock.dart';

import '../domain/review_ports.dart';

class ReviewService {
  ReviewService({
    required this._preferences,
    required this._store,
    required bool isWeb,
    required bool isStoreBuild,
    required this._canPresent,
    required this._clock,
  }) : _enabled = !isWeb && isStoreBuild;

  static const _cooldown = Duration(days: 120);
  static const _maxRequests = 3;

  final ReviewPreferences _preferences;
  final StoreReview _store;
  final bool _enabled;
  final bool Function(String familyId) _canPresent;
  final Clock _clock;
  Future<void> _pending = Future<void>.value();

  /// Called only after a local transition to delivered is saved.
  Future<void> deliverySaved({
    required String familyId,
    required int before,
    required int after,
  }) => _run(() async {
    if (before != kReviewDeliveryTarget - 1 ||
        after != kReviewDeliveryTarget ||
        !_canPresent(familyId)) {
      return;
    }
    final history = await _preferences.readHistory();
    final last = history.lastRequestedAt;
    final requestedAt = _clock.now();
    if (history.count >= _maxRequests ||
        (last != null && requestedAt.difference(last) < _cooldown)) {
      return;
    }
    if (!await _store.isAvailable() || !_canPresent(familyId)) {
      return;
    }
    await _preferences.writeHistory((
      count: history.count + 1,
      lastRequestedAt: requestedAt,
    ));
    if (!_canPresent(familyId)) return;
    await _store.requestReview(canPresent: () => _canPresent(familyId));
  });

  Future<void> _run(Future<void> Function() action) {
    if (!_enabled) return Future<void>.value();
    return _pending = _pending.then((_) async {
      try {
        await action();
      } on Object {
        // A preference or store failure must not affect the gift or app.
      }
    });
  }
}
