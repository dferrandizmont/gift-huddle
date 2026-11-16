import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'web_session_platform.dart';

SessionPlatform createSessionPlatform(String name, {web.LockManager? locks}) =>
    _BrowserSessionPlatform(name, locks: locks);

class _Lease implements SessionLease {
  _Lease(this.hold, this.released);
  final Completer<JSAny?> hold;
  final Future<JSAny?> released;
  @override
  Future<void> release() async {
    if (!hold.isCompleted) hold.complete(null);
    await released;
  }
}

class _BrowserSessionPlatform implements SessionPlatform {
  _BrowserSessionPlatform(this.name, {web.LockManager? locks})
    : locks = locks ?? web.window.navigator.locks,
      channel = web.BroadcastChannel(name) {
    void listen(
      web.EventTarget target,
      String name,
      void Function(web.Event) callback,
    ) {
      final listener = callback.toJS;
      target.addEventListener(name, listener);
      _remove.add(() => target.removeEventListener(name, listener));
    }

    listen(
      web.document,
      'visibilitychange',
      (_) => _life.add(
        web.document.hidden
            ? SessionLifecycle.hidden
            : SessionLifecycle.visible,
      ),
    );
    listen(web.window, 'pagehide', (_) => _life.add(SessionLifecycle.pagehide));
    listen(
      web.window,
      'pageshow',
      (event) => _life.add(
        (event as web.PageTransitionEvent).persisted
            ? SessionLifecycle.pageshowPersisted
            : SessionLifecycle.pageshow,
      ),
    );
    for (final event in ['pointerdown', 'keydown', 'input', 'wheel']) {
      listen(web.document, event, (_) => _life.add(SessionLifecycle.activity));
    }
    listen(channel, 'message', (event) {
      final data = (event as web.MessageEvent).data;
      if (data.isA<JSString>() && (data as JSString).toDart == 'use-here') {
        _takeover.add(null);
      }
    });
  }
  final String name;
  final web.LockManager locks;
  final web.BroadcastChannel channel;
  final _life = StreamController<SessionLifecycle>.broadcast(sync: true);
  final _takeover = StreamController<void>.broadcast(sync: true);
  final _remove = <void Function()>[];
  final _requests = <web.AbortController>{};
  final _leases = <_Lease>{};
  bool _disposed = false;
  @override
  bool get hidden => web.document.hidden;
  @override
  Stream<SessionLifecycle> get lifecycle => _life.stream;
  @override
  Stream<void> get takeoverRequests => _takeover.stream;
  @override
  void requestTakeover() => channel.postMessage('use-here'.toJS);
  @override
  Future<SessionLease?> acquire({required bool wait}) async {
    if (_disposed) throw StateError('Platform disposed');
    final granted = Completer<SessionLease?>();
    final hold = Completer<JSAny?>();
    final abort = web.AbortController();
    _requests.add(abort);
    late Future<JSAny?> released;
    _Lease? acquired;
    released = locks
        .request(
          name,
          wait
              ? web.LockOptions(signal: abort.signal)
              : web.LockOptions(ifAvailable: true),
          ((web.Lock? lock) {
            if (lock == null || _disposed) {
              granted.complete(null);
              return Future<JSAny?>.value(null).toJS;
            }
            final lease = _Lease(hold, released);
            acquired = lease;
            _leases.add(lease);
            granted.complete(lease);
            return hold.future.toJS;
          }).toJS,
        )
        .toDart;
    unawaited(
      released.then(
        (_) {
          _requests.remove(abort);
          _leases.remove(acquired);
        },
        onError: (Object error) {
          _requests.remove(abort);
          if (!granted.isCompleted) {
            granted.completeError(StateError('Web Lock unavailable'));
          }
        },
      ),
    );
    return granted.future;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    for (final remove in _remove) {
      remove();
    }
    for (final abort in _requests.toList()) {
      abort.abort();
    }
    for (final lease in _leases.toList()) {
      await lease.release();
    }
    channel.close();
    await _life.close();
    await _takeover.close();
  }
}
