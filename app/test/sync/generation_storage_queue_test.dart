import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/family/data/generation_storage.dart';

import '../helpers/memory_stores.dart';

void main() {
  testWidgets('an idle shared queue can be used outside its creation zone', (
    tester,
  ) async {
    final secrets = MemorySecretStore();
    final queue = GenerationStorageQueue.on(secrets, 'startup');
    // Startup constructs nested journal queues under the widget zone, then
    // consumes them during real async storage work. No fake pump is available.
    for (var i = 0; i < 2; i++) {
      final reopened = GenerationStorageQueue.on(secrets, 'startup');
      expect(reopened, same(queue));
      expect(
        await tester.runAsync(
          () =>
              reopened.run(() async => 42).timeout(const Duration(seconds: 1)),
        ),
        42,
      );
    }
  });

  test('queued tasks remain serialized after a failure', () async {
    final queue = GenerationStorageQueue.on(MemorySecretStore(), 'writes');
    final gate = Completer<void>();
    final started = <int>[];
    final first = queue.run<void>(() async {
      started.add(1);
      await gate.future;
      throw StateError('write failed');
    });
    final failure = expectLater(first, throwsStateError);
    final second = queue.run(() async {
      started.add(2);
      return 2;
    });
    final third = queue.run(() async {
      started.add(3);
      return 3;
    });
    await Future<void>.delayed(Duration.zero);
    expect(started, [1]);
    gate.complete();
    await failure;
    expect(await second, 2);
    expect(await third, 3);
    expect(started, [1, 2, 3]);
    expect(await queue.run(() async => 4), 4);
  });

  test('a task enqueued by a running task waits for it to finish', () async {
    final queue = GenerationStorageQueue.on(MemorySecretStore(), 'writes');
    final gate = Completer<void>();
    final started = <int>[];
    late Future<void> nested;
    final first = queue.run<void>(() async {
      started.add(1);
      nested = queue.run<void>(() async => started.add(2));
      await gate.future;
    });
    await Future<void>.delayed(Duration.zero);
    expect(started, [1]);
    gate.complete();
    await first;
    await nested;
    expect(started, [1, 2]);
  });
}
