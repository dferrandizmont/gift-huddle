import 'dart:async';
import 'dart:isolate';

Future<T> runTask<T>(FutureOr<T> Function() task) => Isolate.run(task);
