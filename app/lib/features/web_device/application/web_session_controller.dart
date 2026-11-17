import 'dart:async';

import '../data/guard_client.dart';
import 'web_session_platform.dart';

enum WebSessionState {
  sinIdentidad,
  bloqueada,
  desbloqueando,
  abierta,
  suspendida,
  desconectada,
  otraPestana,
}

abstract interface class SessionClock {
  DateTime now();
  void Function() schedule(Duration delay, void Function() callback);
}

class RealSessionClock implements SessionClock {
  @override
  DateTime now() => DateTime.now();
  @override
  void Function() schedule(Duration delay, void Function() callback) {
    final timer = Timer(delay, callback);
    return timer.cancel;
  }
}

/// Content is covered synchronously, then cancellation and invalidation happen,
/// then the injected session container is disposed. Callbacks from HTTP, socket
/// and crypto must use [accept] or [guardCallback].
class WebSessionController {
  WebSessionController({
    required this.platform,
    required this.cover,
    required this.cancelWork,
    required this.disposeContainer,
    required this.lockVault,
    required this.unlockVault,
    required this.createContainer,
    SessionClock? clock,
    bool hasIdentity = true,
    this.onStateChanged,
    this.onVisible,
    this.onHidden,
  }) : clock = clock ?? RealSessionClock(),
       state = hasIdentity
           ? WebSessionState.bloqueada
           : WebSessionState.sinIdentidad {
    _hidden = platform.hidden;
    if (_hidden) _hiddenAt = this.clock.now();
    _lifecycle = platform.lifecycle.listen(_onLifecycle);
    _takeovers = platform.takeoverRequests.listen((_) {
      if (_lease != null) lock();
    });
  }
  final SessionPlatform platform;
  final void Function()? onStateChanged;

  /// Called after visibility deadlines have been checked, only if still open.
  final void Function()? onVisible;
  final void Function()? onHidden;
  final SessionClock clock;
  final void Function() cover,
      cancelWork,
      disposeContainer,
      lockVault,
      createContainer;
  final Future<void> Function(String pin) unlockVault;
  WebSessionState state;
  int generation = 0;
  bool _disposed = false;
  SessionLease? _lease;
  late final StreamSubscription<SessionLifecycle> _lifecycle;
  late final StreamSubscription<void> _takeovers;
  void Function()? _timer;
  DateTime? _lastUse, _hiddenAt;
  bool _hidden = false;

  bool get visible => !_hidden && !platform.hidden;

  bool accept(int capturedGeneration) =>
      !_disposed &&
      capturedGeneration == generation &&
      state == WebSessionState.abierta;
  void Function(T) guardCallback<T>(void Function(T) callback) {
    final captured = generation;
    return (value) {
      if (accept(captured)) callback(value);
    };
  }

  /// `useHere` requests a takeover and queues for the real exclusive lock.
  /// Receiving a broadcast alone never grants access to the vault.
  Future<void> unlock(String pin, {bool useHere = false}) =>
      _open(pin, useHere: useHere);

  /// Enrollment must take the same exclusive lock as unlocking, before any
  /// guard or IndexedDB write. It remains cancelable by lifecycle deadlines.
  Future<void> enroll(String pin, Future<void> Function(String) action) =>
      _open(pin, enrollment: action);

  Future<void> _open(
    String pin, {
    bool useHere = false,
    Future<void> Function(String)? enrollment,
  }) async {
    if (_disposed ||
        state == WebSessionState.desbloqueando ||
        state == WebSessionState.abierta) {
      return;
    }
    if (state == WebSessionState.desconectada ||
        state == WebSessionState.sinIdentidad && enrollment == null) {
      return;
    }
    state = WebSessionState.desbloqueando;
    final captured = ++generation;
    _lastUse = null;
    if (_hidden) _hiddenAt ??= clock.now();
    _arm();
    try {
      if (useHere) platform.requestTakeover();
      final lease = await platform.acquire(wait: useHere);
      if (_disposed || captured != generation) {
        await lease?.release();
        return;
      }
      if (_expired()) {
        await lease?.release();
        lock();
        return;
      }
      if (lease == null) {
        state = WebSessionState.otraPestana;
        _timer?.call();
        onStateChanged?.call();
        return;
      }
      _lease = lease;
      await (enrollment ?? unlockVault)(pin);
      if (_disposed || captured != generation) return;
      if (_expired()) {
        lock();
        return;
      }
      createContainer();
      state = WebSessionState.abierta;
      _lastUse = clock.now();
      _arm();
      onStateChanged?.call();
    } catch (e) {
      if (_disposed || captured != generation) return;
      lock();
      if (e is GuardException) {
        if (e.disconnected) state = WebSessionState.desconectada;
        if (e.failure == GuardFailure.suspended) {
          state = WebSessionState.suspendida;
        }
      }
      onStateChanged?.call();
      rethrow;
    }
  }

  void activity() {
    if (state != WebSessionState.abierta || _hidden) return;
    if (_expired()) {
      lock();
      return;
    }
    _lastUse = clock.now();
    _arm();
  }

  bool _expired() {
    final now = clock.now();
    return (_lastUse != null &&
            now.difference(_lastUse!) >= const Duration(minutes: 15)) ||
        (_hiddenAt != null &&
            now.difference(_hiddenAt!) >= const Duration(minutes: 5));
  }

  bool get _active =>
      state == WebSessionState.abierta ||
      state == WebSessionState.desbloqueando;

  void _arm() {
    _timer?.call();
    if (!_active) return;
    final now = clock.now();
    DateTime? deadline = _lastUse?.add(const Duration(minutes: 15));
    if (_hiddenAt != null) {
      final hiddenDeadline = _hiddenAt!.add(const Duration(minutes: 5));
      if (deadline == null || hiddenDeadline.isBefore(deadline)) {
        deadline = hiddenDeadline;
      }
    }
    if (deadline == null) return;
    final captured = generation;
    _timer = clock.schedule(deadline.difference(now), () {
      if (_disposed || captured != generation || !_active) return;
      if (_expired()) {
        lock();
      } else {
        _arm();
      }
    });
  }

  void _onLifecycle(SessionLifecycle event) {
    switch (event) {
      case SessionLifecycle.pagehide:
      case SessionLifecycle.pageshow:
      case SessionLifecycle.pageshowPersisted:
        lock();
      case SessionLifecycle.hidden:
        _hidden = true;
        _hiddenAt ??= clock.now();
        if (state == WebSessionState.abierta) onHidden?.call();
        if (_active) {
          if (_expired()) {
            lock();
          } else {
            _arm();
          }
        }
      case SessionLifecycle.visible:
        final wasHidden = _hidden;
        _hidden = false;
        if (_active && _expired()) {
          lock();
        }
        _hiddenAt = null;
        _arm();
        if (wasHidden && state == WebSessionState.abierta) onVisible?.call();
      case SessionLifecycle.activity:
        activity();
    }
  }

  void lock({WebSessionState next = WebSessionState.bloqueada}) {
    if (_disposed) return;
    cover();
    // All cleanup still runs if one integration hook fails.
    try {
      cancelWork();
    } finally {
      generation++;
      _timer?.call();
      _timer = null;
      try {
        lockVault();
      } finally {
        try {
          disposeContainer();
        } finally {
          final lease = _lease;
          _lease = null;
          if (lease != null) unawaited(lease.release());
          if (state != WebSessionState.sinIdentidad &&
              state != WebSessionState.desconectada &&
              state != WebSessionState.suspendida) {
            state = next;
          }
          onStateChanged?.call();
        }
      }
    }
  }

  void disconnect() {
    lock(next: WebSessionState.desconectada);
    state = WebSessionState.desconectada;
  }

  Future<void> dispose() async {
    lock();
    _disposed = true;
    await _lifecycle.cancel();
    await _takeovers.cancel();
    await platform.dispose();
  }
}
