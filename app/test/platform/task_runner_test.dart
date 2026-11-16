import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/platform/task_runner.dart';
import 'package:regalos/core/platform/task_runner_inline.dart' as inline;

void main() {
  test(
    'native tasks execute in a different isolate and await async values',
    () async {
      final current = Isolate.current.hashCode;
      expect(await runTask(() => Isolate.current.hashCode), isNot(current));
      expect(await runTask(() async => 42), 42);
    },
  );
  test('inline tasks schedule asynchronously and propagate failures', () async {
    var ran = false;
    final task = inline.runTask(() {
      ran = true;
      return 42;
    });
    expect(ran, isFalse);
    expect(await task, 42);
    expect(await inline.runTask(() async => 7), 7);
    await expectLater(
      inline.runTask(() => throw const FormatException('bad')),
      throwsFormatException,
    );
    await expectLater(
      runTask(() => throw const FormatException('bad')),
      throwsFormatException,
    );
  });
}
