import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/features/sync/data/sync_transport_common.dart';

class FakeGuardCredential {
  FakeGuardCredential(this.syncId, this.deviceId, this.role);
  final String syncId, deviceId, role;
  bool revoked = false;
}

class FakeGuardVersion {
  FakeGuardVersion(this.version, this.tokenHash, this.verifier, this.secret);
  final int version;
  final String tokenHash, verifier, secret;
  bool same(FakeGuardVersion other) =>
      version == other.version &&
      tokenHash == other.tokenHash &&
      verifier == other.verifier &&
      secret == other.secret;
}

class FakeGuardState {
  FakeGuardVersion? current, pending;
  int failures = 0;
  int failedSince = 0;
  bool mustRotate = false, rotationRequired = false;
  DateTime? nextAttemptAt;
  bool suspended = false;
}

/// Reference state machine for lot 3. All requests are serialized like the
/// Durable Object's mutex. No plaintext proof/token is retained in state.
class FakeGuardServer {
  FakeGuardServer({required this.now});
  final DateTime Function() now;
  final credentials = <String, FakeGuardCredential>{};
  final guards = <String, FakeGuardState>{};
  final retiredLists = <String>{};
  Future<void> _tail = Future.value();
  Future<SyncResponse> send(
    String method,
    Uri uri, {
    Object? body,
    Map<String, String> headers = const {},
  }) {
    final result = _tail.then((_) => _handle(method, uri, body, headers));
    _tail = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  SyncResponse _response(
    int status, [
    Map<String, Object?> body = const {},
    Map<String, String> headers = const {},
  ]) => SyncResponse(
    status,
    headers,
    Uint8List.fromList(utf8.encode(jsonEncode(body))),
  );
  bool _constantTime(String a, String b) {
    final aa = decodeBase64Url(a), bb = decodeBase64Url(b);
    var difference = aa.length ^ bb.length;
    for (var i = 0; i < 32; i++) {
      difference |= (i < aa.length ? aa[i] : 0) ^ (i < bb.length ? bb[i] : 0);
    }
    return difference == 0;
  }

  Future<String> _hash(String encoded) async =>
      encodeBase64Url((await Sha256().hash(decodeBase64Url(encoded))).bytes);
  Future<SyncResponse> _handle(
    String method,
    Uri uri,
    Object? body,
    Map<String, String> headers,
  ) async {
    final path = uri.pathSegments;
    if (path.length != 6 ||
        path[0] != 'v2' ||
        path[1] != 'lists' ||
        path[3] != 'guards') {
      return _response(404);
    }
    final syncId = path[2], deviceId = path[4], route = path[5];
    final key = '$syncId/$deviceId';
    final j = Map<String, Object?>.from(body as Map);
    final retired = retiredLists.contains(syncId);
    if (route == 'open' && method == 'POST') {
      final state = guards[key];
      if (retired || state == null) return _response(404);
      final raw = j['proofs'];
      if (raw is! List || raw.isEmpty || raw.length > 2) return _response(400);
      final proofs = raw.cast<Map>();
      if (proofs.map((p) => p['version']).toSet().length != proofs.length) {
        return _response(400);
      }
      final matched = <(Map, FakeGuardVersion)>[];
      for (final proof in proofs) {
        for (final version in [state.current, state.pending]) {
          if (version != null &&
              version.version == proof['version'] &&
              _constantTime(
                await _hash(proof['guardToken'] as String),
                version.tokenHash,
              )) {
            matched.add((proof, version));
          }
        }
      }
      // Uniform 404 precedes counters, throttling and suspension.
      if (matched.isEmpty) return _response(404);
      final next = state.nextAttemptAt;
      if (next != null && now().isBefore(next)) {
        return _response(429, const {}, {
          'retry-after': ((next.difference(now()).inMilliseconds + 999) ~/ 1000)
              .toString(),
        });
      }
      if (state.suspended) return _response(423, {'error': 'guard_suspended'});
      state.nextAttemptAt = now().add(const Duration(seconds: 2));
      FakeGuardVersion? accepted;
      // Evaluate both; prefer current if both are valid. One request = one attempt.
      for (final (proof, version) in matched) {
        if (_constantTime(
          await _hash(proof['prueba'] as String),
          version.verifier,
        )) {
          accepted ??= version;
        }
      }
      if (accepted != null) {
        final failedSince = state.failedSince;
        state.failures = 0;
        state.failedSince = 0;
        state.mustRotate |= failedSince > 0;
        state.rotationRequired |= state.mustRotate;
        return _response(200, {
          'version': accepted.version,
          'b': accepted.secret,
          'failedSince': failedSince,
          'mustRotate': state.mustRotate,
        });
      }
      state.failedSince++;
      state.failures++;
      if (state.failures >= 10) {
        state.suspended = true;
        return _response(423, {'error': 'guard_suspended'});
      }
      return _response(403, {
        'error': 'wrong_pin',
        'left': 10 - state.failures,
      });
    }
    final bearer = headers['Authorization'];
    final auth = bearer == null ? null : credentials[bearer];
    if (auth == null || auth.revoked) return _response(401);
    if (retired) return _response(410);
    if (auth.syncId != syncId) return _response(403);
    if (route == 'resume' && method == 'POST') {
      if (auth.role != 'device') return _response(403);
      final state = guards[key];
      if (state == null) return _response(404);
      state.suspended = false;
      state.failures = 0;
      state.mustRotate = true;
      state.nextAttemptAt = null;
      return _response(200);
    }
    if (auth.role != 'web' || auth.deviceId != deviceId) return _response(403);
    if (route == 'prepare' && method == 'PUT') {
      final state = guards.putIfAbsent(key, FakeGuardState.new);
      final version = FakeGuardVersion(
        j['version'] as int,
        j['tokenHash'] as String,
        j['verifier'] as String,
        j['secret'] as String,
      );
      // Repeated prepare for either stored version cannot overwrite content.
      for (final existing in [state.current, state.pending]) {
        if (existing?.version == version.version) {
          return _response(existing!.same(version) ? 200 : 409);
        }
      }
      if (version.version != (state.current?.version ?? 0) + 1 ||
          state.pending != null) {
        return _response(409);
      }
      state.pending = version;
      return _response(200);
    }
    final state = guards[key];
    if (state == null) return _response(404);
    if (route == 'commit' && method == 'POST') {
      if (state.current?.version == j['version']) return _response(200);
      if (state.pending?.version != j['version']) return _response(409);
      state.current = state.pending;
      state.pending = null;
      state.mustRotate = false;
      state.rotationRequired = false;
      return _response(200);
    }
    if (route == 'cancel' && method == 'POST') {
      if (state.pending?.version == j['version']) state.pending = null;
      return _response(200, {'version': state.current?.version ?? 0});
    }
    return _response(404);
  }
}
