import 'dart:async';

import 'package:cryptography/cryptography.dart'
    show SecretBoxAuthenticationError;
import 'package:flutter/foundation.dart';

import '../../../core/sync/pairing_v2.dart';
import '../../sync/application/pairing_v2_flow.dart' show kWebPairingOrigin;
import '../../sync/data/sync_transport.dart';
import '../../sync/data/sync_transport_v2.dart';
import '../data/guard_client.dart';
import '../presentation/web_gate_model.dart';
import 'pending_queue.dart';
import 'vault_service.dart';
import 'web_pairing_guest.dart';
import 'web_session_controller.dart';
import 'web_session_platform.dart';
import 'web_sync_engine.dart';

/// The sealed box opened correctly (the guard accepted the PIN) but its
/// integrity check failed: a box from before the check, or an entry that was
/// deleted or altered in IndexedDB. Not a wrong PIN and not a network error.
class VaultDamagedException implements Exception {
  const VaultDamagedException(this.cause);
  final Object cause;
  @override
  String toString() => 'VaultDamagedException: $cause';
}

/// Real gate actions. UI only subscribes to [view]; providers containing family
/// plaintext are created/disposed by the session hooks, never the outer shell.
class WebGateController extends ChangeNotifier implements WebGateActions {
  WebGateController({
    required this.vault,
    required SessionPlatform platform,
    required this.transport,
    required this.createContainer,
    required this.disposeContainer,
    this.cancelTransport,
    this.candidateChanged,
    SessionClock? clock,
    this.pairingOrigin = kWebPairingOrigin,
  }) {
    queue = PendingQueue(vault);
    session = WebSessionController(
      platform: platform,
      clock: clock,
      cover: () => _publish(const WebGateLocked()),
      cancelWork: _cancelWork,
      disposeContainer: disposeContainer,
      lockVault: vault.lock,
      unlockVault: _unlockVault,
      createContainer: () => createContainer(engine!),
      onStateChanged: _sessionChanged,
    );
  }
  final VaultService vault;
  final SyncV2Transport Function() transport;
  final void Function(WebSyncEngine) createContainer;
  final void Function() disposeContainer;
  final void Function()? cancelTransport, candidateChanged;
  final String pairingOrigin;
  late final PendingQueue queue;
  late final WebSessionController session;
  WebSyncEngine? engine;
  WebPairingGuest? guest;
  WebGateView view = const WebGateLocked();
  Timer? _poll;
  int _run = 0;
  bool _disposed = false;
  int unsentChanges = 0;
  bool _useHere = false;
  Duration? nextPairingPoll;
  bool _checkingPairing = false;
  bool _damaged = false;
  int _viewRevision = 0;
  bool get persistenceDenied => vault.persistenceGranted == false;
  int get lastUnlockFailedAttempts => vault.lastUnlockFailedAttempts;

  void _publish(WebGateView next) {
    if (_disposed) return;
    _viewRevision++;
    view = next;
    notifyListeners();
  }

  Future<void> initialize() async {
    final state = await vault.store.read();
    if (_disposed) return;
    if (state.current == null && state.pending == null) {
      session.state = WebSessionState.sinIdentidad;
      await restartPairing();
    } else {
      unsentChanges = (state.pending ?? state.current)!.entries.length;
      _publish(WebGateUnlock());
    }
  }

  void _sessionChanged() {
    switch (session.state) {
      case WebSessionState.abierta:
        _publish(const WebGateOpen());
      case WebSessionState.bloqueada:
        unawaited(_recoverIdentity());
      case WebSessionState.otraPestana:
        _publish(const WebGateOtherTab());
      case WebSessionState.suspendida:
        _publish(const WebGateSuspended());
      case WebSessionState.desconectada:
        _publish(WebGateDisconnected(unsentChanges: unsentChanges));
      case WebSessionState.sinIdentidad:
        unawaited(_recoverIdentity());
        break;
      case WebSessionState.desbloqueando:
        break;
    }
  }

  /// The durable box, including a pending enrollment, decides recovery. An
  /// enrollment interrupted before its local write has no identity to unlock.
  Future<void> _recoverIdentity() async {
    final generation = session.generation;
    final revision = _viewRevision;
    final stored = await vault.store.read();
    if (_disposed ||
        generation != session.generation ||
        revision != _viewRevision) {
      return;
    }
    if (stored.current == null && stored.pending == null) {
      session.state = WebSessionState.sinIdentidad;
      _publish(const WebGateConnectFailed(WebConnectFailure.network));
    } else {
      session.state = WebSessionState.bloqueada;
      // A damaged box stays damaged: do not loop back to a PIN that cannot work.
      _publish(_damaged ? const WebGateDamaged() : WebGateUnlock());
    }
  }

  void _cancelWork() {
    _run++;
    _poll?.cancel();
    _poll = null;
    nextPairingPoll = null;
    guest?.cancel();
    guest = null;
    engine?.stop();
    engine = null;
    cancelTransport?.call();
  }

  Future<void> _unlockVault(String pin) async {
    try {
      await vault.unlock(pin);
    } on FormatException catch (e) {
      throw VaultDamagedException(e);
    } on SecretBoxAuthenticationError catch (e) {
      throw VaultDamagedException(e);
    }
    await _prepareEngine();
  }

  Future<void> _prepareEngine() async {
    final captured = session.generation;
    final next = WebSyncEngine(
      transport: transport(),
      vault: vault,
      queue: queue,
      onChanged: () {
        if (session.accept(captured)) candidateChanged?.call();
      },
      onDisconnected: () {
        if (_disposed || captured != session.generation) return;
        session.disconnect();
        unawaited(_retained());
      },
    );
    engine = next;
    await next.sync();
    if (captured != session.generation || vault.status != VaultStatus.open) {
      next.stop();
      throw StateError('Web session invalidated');
    }
  }

  Future<void> _retained() async {
    final run = _run;
    final state = await vault.store.read();
    if (_disposed || run != _run) return;
    unsentChanges = (state.pending ?? state.current)?.entries.length ?? 0;
    _publish(WebGateDisconnected(unsentChanges: unsentChanges));
  }

  void _startEngine() {
    final current = engine;
    if (current != null && session.state == WebSessionState.abierta) {
      unawaited(current.start().catchError((Object _) {}));
    }
  }

  @override
  Future<void> submitPin(String pin) async {
    try {
      await session.unlock(pin, useHere: _useHere);
      _useHere = false;
      _startEngine();
    } on GuardException catch (e) {
      _guardError(e);
    } on VaultDamagedException {
      _damaged = true;
      _publish(const WebGateDamaged());
    } catch (_) {
      if (view is! WebGateDisconnected) _publish(WebGateUnlock());
    }
  }

  void _guardError(GuardException e) {
    if (e.disconnected) {
      vault.disconnect();
      session.disconnect();
      unawaited(_retained());
    } else if (e.failure == GuardFailure.suspended) {
      session.lock(next: WebSessionState.suspendida);
      session.state = WebSessionState.suspendida;
      _publish(const WebGateSuspended());
    } else {
      _publish(
        WebGateUnlock(
          wrongPin: e.failure == GuardFailure.wrongPin,
          attemptsLeft: e.left,
          retryAfter: e.retryAfter,
        ),
      );
    }
  }

  @override
  Future<void> useHere() async {
    // Transfer ownership now, but ask for the PIN afresh; no PIN is retained.
    session.platform.requestTakeover();
    if (session.state == WebSessionState.desconectada) {
      await _retained();
      return;
    }
    if (session.state == WebSessionState.sinIdentidad) {
      await restartPairing();
      return;
    }
    _useHere = true;
    _publish(WebGateUnlock());
  }

  @override
  Future<void> retry() async => _publish(WebGateUnlock());

  @override
  Future<void> restartPairing() async {
    if (vault.status == VaultStatus.open) {
      throw const WebOperationException('pairWhileOpen');
    }
    final existing = await vault.store.read();
    // Retained actions must never silently cross into a new family/identity.
    if (existing.current != null || existing.pending != null) {
      if (session.state == WebSessionState.desconectada) {
        await _retained();
      } else {
        session.state = WebSessionState.bloqueada;
        _publish(WebGateUnlock());
      }
      return;
    }
    _cancelWork();
    final run = _run;
    final next = await WebPairingGuest.create(transport: transport());
    if (_disposed || run != _run) {
      next.cancel();
      return;
    }
    guest = next;
    session.state = WebSessionState.sinIdentidad;
    _publish(WebGateConnect(url: next.qr.url(origin: pairingOrigin)));
    _schedule(run);
  }

  void _schedule(int run, [Duration? retryAfter]) {
    final next = guest;
    if (next == null || _disposed || run != _run) return;
    final random = next.pollDelay;
    final wait = retryAfter != null && retryAfter > random
        ? retryAfter
        : random;
    _poll?.cancel();
    nextPairingPoll = wait;
    _poll = Timer(wait, () => unawaited(checkPairing()));
  }

  /// Exposed for deterministic integration checks; production uses 5–8s jitter.
  Future<void> checkPairing() async {
    final next = guest;
    final run = _run;
    if (next == null || _checkingPairing) return;
    _poll?.cancel();
    _checkingPairing = true;
    try {
      await next.poll();
      if (_disposed || run != _run) return;
      if (next.joined != null) {
        _publish(WebGateChoosePin(personName: next.personName));
        return;
      }
      if (next.code != null) _publish(WebGateComparing(code: next.code!));
      _schedule(run);
    } on InviteGoneException {
      _pairingFailed(run, WebConnectFailure.expired);
    } on PairingException {
      _pairingFailed(run, WebConnectFailure.codeMismatch);
    } on SyncTransportException catch (e) {
      if (_disposed || run != _run) return;
      if (e.failure == SyncFailure.rateLimited) {
        _schedule(run, e.retryAfter);
      } else {
        _pairingFailed(run, WebConnectFailure.network);
      }
    } catch (_) {
      _pairingFailed(run, WebConnectFailure.rejected);
    } finally {
      _checkingPairing = false;
    }
  }

  void _pairingFailed(int run, WebConnectFailure reason) {
    if (_disposed || run != _run) return;
    _cancelWork();
    _publish(WebGateConnectFailed(reason));
  }

  /// Existing comparison pane receives these callbacks. Approval alone never
  /// substitutes for the browser user's explicit numeric comparison.
  Future<void> confirmCode() async {
    guest?.confirmCode();
    await checkPairing();
  }

  Future<void> rejectCode() async =>
      _pairingFailed(_run, WebConnectFailure.codeMismatch);
  @override
  Future<void> choosePin(String pin) async {
    final next = guest;
    if (next?.joined == null) return;
    try {
      await session.enroll(pin, (value) async {
        await next!.enroll(vault, value);
        await _prepareEngine();
      });
      if (session.state == WebSessionState.abierta) {
        guest = null;
        _startEngine();
      }
    } on GuardException catch (e) {
      await _recoverIdentity();
      if (session.state != WebSessionState.sinIdentidad) _guardError(e);
    } catch (_) {
      await _recoverIdentity();
    }
  }

  @override
  Future<void> reconnect() async {
    // The existing erase action includes explicit confirmation. Reconnecting
    // must never silently erase or move retained changes to a new identity.
    _publish(
      WebGateDisconnected(unsentChanges: unsentChanges, confirmErase: true),
    );
  }

  @override
  Future<void> eraseComputer() async {
    final generation = session.generation;
    // A disconnected/locked tab has no session lease. Erasure still needs the
    // same Web Lock, so it cannot race another tab's queue or PIN transaction.
    final lease = await session.platform.acquire(wait: false);
    if (_disposed || generation != session.generation) {
      await lease?.release();
      return;
    }
    if (lease == null) {
      _publish(const WebGateOtherTab());
      return;
    }
    try {
      _cancelWork();
      disposeContainer();
      await vault.forget(localOnly: true);
      session.state = WebSessionState.sinIdentidad;
      unsentChanges = 0;
      _damaged = false;
    } finally {
      await lease.release();
    }
    if (!_disposed) await restartPairing();
  }

  @override
  Future<void> lock() async {
    session.lock();
    await _recoverIdentity();
  }

  @override
  Future<WebPinChangeResult> changePin(String current, String next) async {
    if (session.state != WebSessionState.abierta) {
      return WebPinChangeResult.failed;
    }
    try {
      await vault.unlock(current);
      await vault.changePin(next);
      return WebPinChangeResult.changed;
    } on GuardException catch (e) {
      if (e.failure == GuardFailure.wrongPin) {
        return WebPinChangeResult.wrongCurrent;
      }
      if (vault.status != VaultStatus.open) {
        session.lock();
        await _recoverIdentity();
      }
      if (e.disconnected || e.failure == GuardFailure.suspended) _guardError(e);
      return WebPinChangeResult.failed;
    } catch (_) {
      if (vault.status != VaultStatus.open) {
        session.lock();
        await _recoverIdentity();
      }
      return WebPinChangeResult.failed;
    }
  }

  @override
  Future<void> forgetComputer() async {
    // Self-revocation closes the socket before HTTP can complete. Stop its
    // subscription first, without invalidating the vault or releasing the lease.
    _publish(const WebGateLocked());
    engine?.stop();
    engine = null;
    disposeContainer();
    try {
      await vault.forget();
    } catch (_) {
      session.lock();
      await _recoverIdentity();
      rethrow;
    }
    session.lock(next: WebSessionState.sinIdentidad);
    session.state = WebSessionState.sinIdentidad;
    await restartPairing();
  }

  Future<void> close() async {
    _disposed = true;
    _cancelWork();
    await session.dispose();
    super.dispose();
  }
}
