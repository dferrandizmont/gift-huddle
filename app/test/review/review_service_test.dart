import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:regalos/features/review/application/review_service.dart';
import 'package:regalos/features/review/domain/review_ports.dart';

void main() {
  late DateTime now;
  late FakeReviewPreferences preferences;
  late FakeStoreReview store;
  late bool canPresent;
  late bool isCurrentFamily;

  ReviewService service({bool isWeb = false, bool isStoreBuild = true}) =>
      ReviewService(
        preferences: preferences,
        store: store,
        isWeb: isWeb,
        isStoreBuild: isStoreBuild,
        canPresent: (_) => canPresent && isCurrentFamily,
        clock: Clock(() => now),
      );

  setUp(() {
    now = DateTime.utc(2026, 11, 20);
    preferences = FakeReviewPreferences();
    store = FakeStoreReview();
    canPresent = true;
    isCurrentFamily = true;
  });

  test('only the exact transition from four to five can request', () async {
    final review = service();
    await review.deliverySaved(familyId: 'a', before: 3, after: 4);
    await review.deliverySaved(familyId: 'a', before: 3, after: 5);
    await review.deliverySaved(familyId: 'a', before: 4, after: 6);
    await review.deliverySaved(familyId: 'a', before: 5, after: 6);
    expect(store.requests, 0);
    expect(preferences.reads, 0);
    expect(preferences.writes, 0);
    await review.deliverySaved(familyId: 'a', before: 4, after: 5);
    expect(store.requests, 1);
  });

  test('the 120-day cooldown is shared by families on the device', () async {
    final review = service();
    await review.deliverySaved(familyId: 'a', before: 4, after: 5);
    final first = now;
    now = first.add(const Duration(days: 120, seconds: -1));
    await review.deliverySaved(familyId: 'b', before: 4, after: 5);
    expect(store.requests, 1);
    expect(preferences.history.lastRequestedAt, first);
    expect(store.availabilityChecks, 1);

    now = first.add(const Duration(days: 120));
    await service().deliverySaved(familyId: 'c', before: 4, after: 5);
    expect(store.requests, 2);
    expect(preferences.history.lastRequestedAt, now);
  });

  test('at most three requests survive service restarts', () async {
    for (final family in ['a', 'b', 'c', 'd']) {
      await service().deliverySaved(familyId: family, before: 4, after: 5);
      now = now.add(const Duration(days: 121));
    }
    expect(store.requests, 3);
    expect(preferences.history.count, 3);
    expect(store.availabilityChecks, 3);
  });

  test('reads history before checking availability', () async {
    final order = <String>[];
    preferences.onHistoryRead = () => order.add('read');
    store.onCheck = () => order.add('available');
    preferences.onHistoryWrite = () => order.add('write');
    store.onRequest = () => order.add('request');

    await service().deliverySaved(familyId: 'a', before: 4, after: 5);

    expect(order, ['read', 'available', 'write', 'request']);
  });

  test('concurrent crossings use one device request', () async {
    final review = service();
    await Future.wait([
      review.deliverySaved(familyId: 'a', before: 4, after: 5),
      review.deliverySaved(familyId: 'b', before: 4, after: 5),
    ]);
    expect(store.requests, 1);
    expect(preferences.history.count, 1);
  });

  test('web and non-store builds skip storage and the store', () async {
    for (final review in [service(isWeb: true), service(isStoreBuild: false)]) {
      await review.deliverySaved(familyId: 'a', before: 4, after: 5);
    }
    expect(preferences.reads, 0);
    expect(preferences.writes, 0);
    expect(store.availabilityChecks, 0);
    expect(store.requests, 0);
  });

  test('an unavailable store reads history but does not write it', () async {
    store.available = false;
    final review = service();
    await review.deliverySaved(familyId: 'a', before: 4, after: 5);
    expect(store.availabilityChecks, 1);
    expect(store.requests, 0);
    expect(preferences.reads, 1);
    expect(preferences.writes, 0);

    store.available = true;
    await review.deliverySaved(familyId: 'a', before: 4, after: 5);
    expect(store.requests, 1);
  });

  test(
    'does not request if the app locks during the availability check',
    () async {
      store.onCheck = () => canPresent = false;
      await service().deliverySaved(familyId: 'a', before: 4, after: 5);
      expect(store.availabilityChecks, 1);
      expect(store.requests, 0);
      expect(preferences.reads, 1);
      expect(preferences.writes, 0);
    },
  );

  test('a queued delivery from an erased family skips storage', () async {
    final delivery = service().deliverySaved(
      familyId: 'a',
      before: 4,
      after: 5,
    );
    isCurrentFamily = false;
    await delivery;
    expect(preferences.reads, 0);
    expect(preferences.writes, 0);
    expect(store.availabilityChecks, 0);
  });

  test('a PIN shown while reading history prevents the request', () async {
    preferences.onHistoryRead = () => canPresent = false;
    await service().deliverySaved(familyId: 'a', before: 4, after: 5);
    expect(store.availabilityChecks, 1);
    expect(store.requests, 0);
    expect(preferences.reads, 1);
    expect(preferences.writes, 0);
  });

  test('history is saved before the store request', () async {
    store.onRequest = () {
      expect(preferences.reads, 1);
      expect(preferences.writes, 1);
      expect(preferences.history, (count: 1, lastRequestedAt: now));
    };
    await service().deliverySaved(familyId: 'a', before: 4, after: 5);
    expect(store.requests, 1);
  });

  test(
    'a failed history write skips the request and leaves quota intact',
    () async {
      final review = service();
      preferences.onHistoryWrite = () => throw StateError('Write failed');
      await review.deliverySaved(familyId: 'a', before: 4, after: 5);
      expect(store.requests, 0);
      expect(preferences.history.count, 0);

      preferences.onHistoryWrite = null;
      await review.deliverySaved(familyId: 'a', before: 4, after: 5);
      expect(store.requests, 1);
      expect(preferences.history, (count: 1, lastRequestedAt: now));
    },
  );

  test('a PIN shown while saving history blocks store dispatch', () async {
    preferences.onHistoryWrite = () => canPresent = false;
    await service().deliverySaved(familyId: 'a', before: 4, after: 5);
    expect(store.requests, 0);
    expect(preferences.history, (count: 1, lastRequestedAt: now));
  });
}

class FakeReviewPreferences implements ReviewPreferences {
  ReviewHistory history = (count: 0, lastRequestedAt: null);
  int reads = 0;
  int writes = 0;
  void Function()? onHistoryRead;
  void Function()? onHistoryWrite;

  @override
  Future<ReviewHistory> readHistory() async {
    reads++;
    onHistoryRead?.call();
    return history;
  }

  @override
  Future<void> writeHistory(ReviewHistory value) async {
    onHistoryWrite?.call();
    history = value;
    writes++;
  }
}

class FakeStoreReview implements StoreReview {
  bool available = true;
  int availabilityChecks = 0;
  int requests = 0;
  void Function()? onCheck;
  void Function()? onRequest;

  @override
  Future<bool> isAvailable() async {
    availabilityChecks++;
    onCheck?.call();
    return available;
  }

  @override
  Future<void> requestReview({required bool Function() canPresent}) async {
    if (!canPresent()) return;
    requests++;
    onRequest?.call();
  }
}
