// La cadencia de los sondeos de una invitación: 1-2 s con azar, nunca más de
// 25 peticiones en 60 s seguidos y, tras un 429, Retry-After (hasta 60 s) o 2,
// 4, 8… 30 s, que ninguna otra espera se salta. Todo con un reloj monótono:
// cambiar la hora del sistema no cambia nada. Reloj falso y azar con semilla.
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/sync/application/invite_poll_pacer.dart';

void main() {
  late Duration elapsed;
  InvitePollPacer pacer({int? budget = kInvitePollBudget}) => InvitePollPacer(
    budget: budget,
    random: Random(7),
    elapsed: () => elapsed,
  );
  setUp(() => elapsed = Duration.zero);

  test('normal waits are 1-2 s with jitter', () {
    final p = pacer();
    final waits = {for (var i = 0; i < 50; i++) p.next().inMilliseconds};
    expect(waits.every((w) => w >= 1000 && w <= 2000), isTrue);
    expect(waits.length, greaterThan(10), reason: 'jitter');
  });

  test('a different cadence for one wait (3-4 s)', () {
    final p = pacer();
    for (var i = 0; i < 20; i++) {
      final w = p.next(
        base: const Duration(seconds: 3),
        spread: const Duration(seconds: 1),
      );
      expect(w.inMilliseconds, inInclusiveRange(3000, 4000));
    }
  });

  test('never more than 25 requests to the invitation in any rolling 60 s, '
      'over a 10-minute wait with two requests per poll', () {
    final p = pacer();
    final sent = <Duration>[];
    while (elapsed < const Duration(minutes: 10)) {
      elapsed += p.next();
      // A poll may make two requests (the result and the checkpoint).
      for (var i = 0; i < 2; i++) {
        p.sent();
        sent.add(elapsed);
      }
    }
    for (final t in sent) {
      final inWindow = sent.where((s) => s >= t && s - t < kInvitePollWindow);
      expect(inWindow.length, lessThanOrEqualTo(kInvitePollBudget));
    }
    expect(sent.length, greaterThan(9 * 20), reason: 'it keeps polling');
  });

  test('the budget only slows down once it is spent', () {
    final p = pacer();
    for (var i = 0; i < 23; i++) {
      p.sent();
    }
    expect(p.next(), lessThanOrEqualTo(const Duration(seconds: 2)));
    p.sent();
    expect(p.next(), greaterThan(const Duration(seconds: 59)));
    elapsed += const Duration(seconds: 61);
    expect(p.next(), lessThanOrEqualTo(const Duration(seconds: 2)));
  });

  test('429: Retry-After wins; without it 2, 4, 8, 16, 30 s with jitter, '
      'and a success resets the doubling', () {
    final p = pacer(budget: null);
    expect(p.limited(const Duration(seconds: 45)), const Duration(seconds: 45));
    final p2 = pacer(budget: null);
    final waits = <int>[];
    for (var i = 0; i < 6; i++) {
      waits.add(p2.limited().inMilliseconds);
      elapsed += const Duration(minutes: 1); // past each deadline
    }
    for (final (i, base) in [2000, 4000, 8000, 16000].indexed) {
      expect(waits[i], inInclusiveRange(base, base * 5 ~/ 4));
    }
    expect(waits[4], 30000);
    expect(waits[5], 30000);
    p2.succeeded();
    expect(p2.limited().inMilliseconds, inInclusiveRange(2000, 2500));
  });

  test('Retry-After is clamped to 60 s', () {
    final p = pacer(budget: null);
    expect(p.limited(const Duration(minutes: 10)), const Duration(seconds: 60));
  });

  test('item 1: soon() and next() never skip a Retry-After deadline', () {
    final p = pacer();
    expect(p.soon(), Duration.zero);
    expect(p.limited(const Duration(seconds: 60)), const Duration(seconds: 60));
    // Before the deadline: what is left of it, not 1-2 s.
    expect(p.soon(), const Duration(seconds: 60));
    expect(p.next(), const Duration(seconds: 60));
    elapsed += const Duration(seconds: 45);
    expect(p.soon(), const Duration(seconds: 15));
    expect(p.next(), const Duration(seconds: 15));
    // After it: normal again.
    elapsed += const Duration(seconds: 16);
    expect(p.soon(), Duration.zero);
    expect(p.next().inMilliseconds, inInclusiveRange(1000, 2000));
  });

  test('item 6: windows follow the monotonic clock only', () {
    // The pacer has no wall clock: moving the system time changes nothing.
    final p = pacer();
    for (var i = 0; i < 24; i++) {
      p.sent();
    }
    final wait = p.next();
    expect(wait, greaterThan(const Duration(seconds: 59)));
    expect(wait, lessThanOrEqualTo(const Duration(seconds: 61)));
    // Requests only leave the window as monotonic time passes.
    elapsed += const Duration(seconds: 30);
    expect(p.inWindow, 24);
    expect(p.next(), greaterThan(const Duration(seconds: 29)));
    elapsed += const Duration(seconds: 31);
    expect(p.inWindow, 0);
  });

  test('the default monotonic source never goes back', () {
    final source = monotonicElapsed();
    final a = source();
    final b = source();
    expect(b >= a, isTrue);
  });

  test(
    'item 6: with the budget full and a 429 deadline, moving the wall '
    'clock back or forward changes neither the accounting nor the backoff',
    () {
      final wall = DateTime.utc(2026, 11, 16, 12);
      final p = pacer();
      for (var i = 0; i < 25; i++) {
        p.sent();
        elapsed += const Duration(milliseconds: 400);
      }
      p.limited(const Duration(seconds: 30));
      elapsed += const Duration(seconds: 5);
      (int, Duration, Duration, Duration) snapshot() => (
        p.inWindow,
        p.retryRemaining,
        p.soon(),
        p.next(base: Duration.zero, spread: Duration.zero),
      );
      final before = withClock(Clock.fixed(wall), snapshot);
      expect(before.$1, 25);
      expect(before.$2, const Duration(seconds: 25));
      for (final shift in [
        const Duration(hours: -1),
        const Duration(hours: 1),
      ]) {
        final after = withClock(Clock.fixed(wall.add(shift)), snapshot);
        expect(after, before, reason: 'wall clock moved by $shift');
      }
      // Only monotonic time frees the window and ends the backoff.
      elapsed += const Duration(seconds: 60);
      expect(p.inWindow, 0);
      expect(p.retryRemaining, Duration.zero);
    },
  );
}
