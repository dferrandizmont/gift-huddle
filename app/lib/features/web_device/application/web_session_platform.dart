import 'web_session_platform_stub.dart'
    if (dart.library.js_interop) 'web_session_platform_web.dart'
    as platform;

enum SessionLifecycle {
  hidden,
  visible,
  pagehide,
  pageshow,
  pageshowPersisted,
  activity,
}

abstract interface class SessionLease {
  /// Completes only once the exclusive lock really has been released.
  Future<void> release();
}

abstract interface class SessionPlatform {
  bool get hidden;
  Stream<SessionLifecycle> get lifecycle;
  Stream<void> get takeoverRequests;
  Future<SessionLease?> acquire({required bool wait});
  void requestTakeover();
  Future<void> dispose();
}

SessionPlatform createSessionPlatform({String name = 'gift-huddle-vault'}) =>
    platform.createSessionPlatform(name);
