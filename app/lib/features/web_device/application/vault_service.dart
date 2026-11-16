import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../../core/sync/envelope.dart';
import '../data/guard_client.dart';
import '../data/vault_crypto.dart';
import '../data/vault_store.dart';

/// Plaintext lives only in an open session. `data` contains DeviceKeys seeds,
/// familyKey, pinned public roots and the remote snapshot (never a merged doc).
class OpenVault {
  OpenVault(this.header, this.data, this.key, this.counter);
  final VaultHeader header;
  final VaultJson data;
  final SecretKey key;
  final int counter;
  List<int> get credential => decodeBase64Url(data['credential'] as String);
}

enum VaultStatus { locked, open, suspended, disconnected }

class VaultService {
  VaultService({
    required this.store,
    required this.guard,
    VaultCrypto? crypto,
    this.persist = requestVaultPersistence,
    this.revokeSelf,
  }) : crypto = crypto ?? VaultCrypto();
  final VaultStore store;
  final GuardClient guard;
  final VaultCrypto crypto;
  final Future<bool> Function() persist;

  /// Lot 3: revoke own credential (also removes guard), before local erasure.
  final Future<void> Function(OpenVault vault)? revokeSelf;
  OpenVault? _opened;
  OpenVault get opened => _opened ?? (throw StateError('Vault locked'));
  VaultStatus status = VaultStatus.locked;
  bool? persistenceGranted;
  int lastUnlockFailedAttempts = 0;
  int _generation = 0;
  Future<void> _tail = Future.value();

  /// Shares ordering with queue writes, PIN changes and confirmations.
  Future<T> serial<T>(Future<T> Function() action) {
    final generation = _generation;
    final result = _tail.then((_) async {
      _check(generation);
      return action();
    });
    _tail = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  void _check(int generation) {
    if (generation != _generation) throw StateError('Session invalidated');
  }

  void lock() {
    _generation++;
    _opened = null;
    if (status == VaultStatus.open) status = VaultStatus.locked;
  }

  /// Lot 4 also calls this for a revoked registry view or socket 4401/4404.
  /// Ciphertext and pending changes remain until explicit forget.
  void disconnect() {
    lock();
    status = VaultStatus.disconnected;
  }

  void _error(Object e) {
    if (e is GuardException) {
      if (e.disconnected) {
        lock();
        status = VaultStatus.disconnected;
      }
      if (e.failure == GuardFailure.suspended) {
        lock();
        status = VaultStatus.suspended;
      }
    }
  }

  Future<
    ({
      VaultHeader header,
      VaultDerivation derivation,
      List<int> b,
      SecretKey key,
    })
  >
  _new(String pin, String syncId, String deviceId, int version) async {
    final h = VaultHeader(
      syncId: syncId,
      deviceId: deviceId,
      salt: crypto.randomBytes(16),
      guardToken: crypto.randomBytes(32),
      guardVersion: version,
    );
    final derived = await crypto.derive(pin, h);
    final b = crypto.randomBytes(32);
    return (
      header: h,
      derivation: derived,
      b: b,
      key: await crypto.key(derived, b),
    );
  }

  Future<void> _prepare(
    VaultHeader h,
    VaultDerivation d,
    List<int> b,
    List<int> credential,
  ) async => guard.prepare(
    h,
    credential,
    tokenHash: await crypto.hash(h.guardToken),
    verifier: await crypto.hash(await d.proof.extractBytes()),
    b: b,
  );

  /// prepare -> durable pending -> commit -> promote. No durable set before
  /// prepare: an interruption there is deliberately an aborted enrollment.
  Future<void> enroll({
    required String pin,
    required String syncId,
    required String deviceId,
    required VaultJson data,
  }) => serial(() async {
    final generation = _generation;
    if ((await store.read()).current != null ||
        (await store.read()).pending != null) {
      throw StateError('Identity already exists');
    }
    final fresh = await _new(pin, syncId, deviceId, 1);
    final credential = decodeBase64Url(data['credential'] as String);
    try {
      _check(generation);
      await _prepare(fresh.header, fresh.derivation, fresh.b, credential);
      final set = await crypto.sealSet(
        VaultSet(header: fresh.header.toJson(), box: const {}),
        data,
        0,
        fresh.key,
        fresh.header,
      );
      _check(generation);
      await store.writePending(set);
      persistenceGranted = await persist();
      _check(generation);
      await guard.commit(fresh.header, credential);
      _check(generation);
      await store.promotePending();
      _check(generation);
      _opened = OpenVault(fresh.header, cloneVaultJson(data), fresh.key, 0);
      status = VaultStatus.open;
    } catch (e) {
      if (generation == _generation) _error(e);
      rethrow;
    }
  });

  Future<OpenVault> unlock(String pin) => serial(() async {
    final generation = _generation;
    final state = await store.read();
    final sets = [
      if (state.current != null) state.current!,
      if (state.pending != null) state.pending!,
    ];
    if (sets.isEmpty) throw StateError('No identity');
    // Validate *all* headers before deriving even the first one.
    final headers = sets.map((s) => VaultHeader.fromJson(s.header)).toList();
    if (headers.any(
          (h) =>
              h.syncId != headers.first.syncId ||
              h.deviceId != headers.first.deviceId,
        ) ||
        (headers.length == 2 &&
            headers.last.guardVersion != headers.first.guardVersion + 1)) {
      throw const FormatException('Inconsistent vault sets');
    }
    try {
      final derived = <VaultDerivation>[];
      final proofs = <GuardProof>[];
      for (final h in headers) {
        final d = await crypto.derive(pin, h);
        derived.add(d);
        proofs.add(
          GuardProof(
            h.guardVersion,
            h.guardToken,
            await d.proof.extractBytes(),
          ),
        );
      }
      _check(generation);
      final response = await guard.open(headers.first, proofs);
      _check(generation);
      final index = headers.indexWhere(
        (h) => h.guardVersion == response.version,
      );
      final h = headers[index];
      final key = await crypto.key(derived[index], response.b);
      final payload = await crypto.openSet(sets[index], key, h);
      var opened = OpenVault(h, payload.data, key, payload.counter);
      lastUnlockFailedAttempts = response.failedSince;
      _check(generation);
      if (state.pending != null) {
        if (identical(sets[index], state.pending)) {
          await guard.commit(h, opened.credential);
          _check(generation);
          await store.promotePending();
        } else {
          await guard.cancel(headers.last, opened.credential);
          _check(generation);
          await store.deletePending();
        }
      }
      _check(generation);
      if (response.mustRotate || response.failedSince > 0) {
        // Keep the provisional identity private until the old capability dies.
        _opened = null;
        status = VaultStatus.locked;
        opened = await _changePin(pin, opened);
      }
      _check(generation);
      _opened = opened;
      status = VaultStatus.open;
      return opened;
    } catch (e) {
      if (generation == _generation) _error(e);
      rethrow;
    }
  });

  Future<void> changePin(String pin) => serial(() async {
    final result = await _changePin(pin, opened);
    _opened = result;
  });

  Future<OpenVault> _changePin(String pin, OpenVault old) async {
    final generation = _generation;
    final state = await store.read();
    if (state.pending != null) {
      throw StateError('Recover pending PIN change first');
    }
    final current = state.current!;
    await _verify(current, old);
    final fresh = await _new(
      pin,
      old.header.syncId,
      old.header.deviceId,
      old.header.guardVersion + 1,
    );
    final entries = <String, VaultJson>{};
    for (final entry in current.entries.entries) {
      final value = await crypto.open(
        entry.value,
        old.key,
        old.header,
        'queue',
        entry.key,
      );
      entries[entry.key] = await crypto.seal(
        value,
        fresh.key,
        fresh.header,
        'queue',
        entry.key,
      );
    }
    final marks = current.marks == null
        ? null
        : await crypto.seal(
            await crypto.open(current.marks!, old.key, old.header, 'blocked'),
            fresh.key,
            fresh.header,
            'blocked',
          );
    final pending = await crypto.sealSet(
      VaultSet(
        header: fresh.header.toJson(),
        box: const {},
        entries: entries,
        marks: marks,
      ),
      old.data,
      old.counter + 1,
      fresh.key,
      fresh.header,
    );
    _check(generation);
    await store.writePending(pending);
    try {
      _check(generation);
      await _prepare(fresh.header, fresh.derivation, fresh.b, old.credential);
      _check(generation);
      await guard.commit(fresh.header, old.credential);
      _check(generation);
      await store.promotePending();
      _check(generation);
      return OpenVault(fresh.header, old.data, fresh.key, old.counter + 1);
    } catch (e) {
      if (generation == _generation) {
        try {
          final currentVersion = await guard.cancel(
            fresh.header,
            old.credential,
          );
          _check(generation);
          // A lost commit response may mean the new version is already live.
          // Never delete the only working local set in that case.
          if (currentVersion != old.header.guardVersion) {
            throw StateError('Guard changed');
          }
          _check(generation);
          await store.transaction((state) {
            _check(generation);
            if (state.current?.header['guardVersion'] !=
                    old.header.guardVersion ||
                state.pending?.header['guardVersion'] !=
                    fresh.header.guardVersion) {
              throw StateError('Vault changed during PIN cleanup');
            }
            return VaultState(current: state.current);
          });
          _check(generation);
        } catch (_) {
          if (generation == _generation) lock();
        }
        _error(e);
      }
      rethrow;
    }
  }

  Future<void> _verify(VaultSet set, OpenVault open) async {
    final payload = await crypto.openSet(set, open.key, open.header);
    if (payload.counter != open.counter) {
      throw const FormatException(
        'Vault integrity check failed: stale counter',
      );
    }
  }

  /// Must be called under serial(), including for reads during an open session.
  Future<VaultSet> readCurrent() async {
    final state = await store.read();
    if (state.pending != null) {
      throw StateError('Recover pending PIN change first');
    }
    final current = state.current!;
    await _verify(current, opened);
    return current;
  }

  Future<void> replaceCurrent(
    VaultSet previous,
    VaultSet next, {
    VaultJson? data,
  }) async {
    final generation = _generation;
    final open = opened;
    await _verify(previous, open);
    final contents = cloneVaultJson(data ?? open.data);
    final sealed = await crypto.sealSet(
      next,
      contents,
      open.counter + 1,
      open.key,
      open.header,
    );
    _check(generation);
    await store.transaction((state) {
      _check(generation);
      if (state.pending != null ||
          jsonEncode(state.current?.toJson()) !=
              jsonEncode(previous.toJson())) {
        throw StateError('Vault changed during transaction');
      }
      return VaultState(current: sealed);
    });
    _check(generation);
    _opened = OpenVault(open.header, contents, open.key, open.counter + 1);
  }

  /// Replaces the encrypted identity/remote snapshot, keeping queue and marks.
  /// Lot 4 supplies only a coherent remote snapshot and its authenticated roots.
  Future<void> saveData(VaultJson data) => serial(() async {
    final current = await readCurrent();
    await replaceCurrent(current, current, data: data);
  });

  /// localOnly is an explicit local erasure when the credential is unavailable.
  /// A disconnected computer can always erase its retained ciphertext.
  Future<void> forget({bool localOnly = false}) => serial(() async {
    final generation = _generation;
    final original = jsonEncode((await store.read()).toJson());
    _check(generation);
    final hook = revokeSelf;
    if (!localOnly && status != VaultStatus.disconnected) {
      if (hook == null) throw StateError('Self-revocation hook required');
      await hook(opened);
    }
    _check(generation);
    await store.transaction((state) {
      _check(generation);
      if (jsonEncode(state.toJson()) != original) {
        throw StateError('Vault changed during self-revocation');
      }
      return VaultState();
    });
    _check(generation);
    lock();
    status = VaultStatus.locked;
  });
}
