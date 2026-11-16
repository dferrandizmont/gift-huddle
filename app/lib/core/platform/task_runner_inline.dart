import 'dart:async';

/// Schedules the same operation without requiring browser workers.
Future<T> runTask<T>(FutureOr<T> Function() task) => Future<T>(task);
