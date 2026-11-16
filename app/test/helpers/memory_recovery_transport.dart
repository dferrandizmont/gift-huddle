import 'dart:convert';

import 'package:cryptography/dart.dart';
import 'package:regalos/core/sync/device_keys.dart' show kSyncIdPattern;
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_doc.dart' show canonicalJsonOf;
import 'package:regalos/core/sync/recovery.dart';
import 'package:regalos/core/sync/recovery_locator.dart';
import 'package:regalos/features/sync/data/recovery_transport.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';

/// In-memory HTTP-contract fake. Independent of the Worker implementation.
/// Keeps retired IDs/verifiers and exact operation receipts across requests.
/// Tests may reopen a controller using the same fake to model a durable server.
class MemoryRecoveryTransport implements RecoveryTransport {
  MemoryRecoveryTransport({DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  final _assigned = <String, Set<String>>{};
  final _historyReservations = <String, int>{};
  final _mutations = <String, (int, int)>{};
  final _writes = <String, (int, int)>{};
  (int, int)? _reads;
  final _devices = <String, Map<String, _Principal>>{};
  final _rows = <String, _Row>{};
  final _retiredIds = <String>{};
  final _retiredCredentials = <String>{};
  final _creates = <String, _Receipt>{};
  final _deletes = <String, (String, String, int)>{};
  final _rotations = <String, _Rotation>{};

  Future<void> register(V2Auth auth, {bool mobile = true}) async {
    final verifier = await recoveryCredentialVerifier(auth.credential);
    if (_retiredCredentials.contains(verifier)) {
      throw StateError('retired credential');
    }
    (_devices[auth.syncId] ??= {})[auth.deviceId] = _Principal(
      auth.deviceId,
      verifier,
      mobile,
    );
  }

  void revoke(String sid, String deviceId) {
    _devices[sid]?[deviceId]?.revoked = true;
    for (final e in _rows.entries.toList()) {
      if (e.value.sid == sid && e.value.deviceId == deviceId) {
        if (e.value.rotation != null) {
          _closeRotation(e.value.rotation!, 'recovery_rotation_cancelled');
        }
        _rows.remove(e.key);
        _retiredIds.add(e.key);
      }
    }
  }

  RecoveryResponse _response(int status, [Object? body, int? revision]) =>
      RecoveryResponse(
        status,
        body: body,
        headers: {
          'cache-control': 'no-store',
          'content-type': 'application/json',
          if (revision != null) 'etag': '"$revision"',
          if (status == 429) 'retry-after': '60',
        },
      );

  void _charge(
    String sid, {
    bool daily = true,
    int history = 0,
    String? allocate,
  }) {
    final now = _now().toUtc().millisecondsSinceEpoch;
    final minute = now ~/ 60000;
    final day = now ~/ 86400000;
    final mutations = _mutations[sid]?.$1 == minute ? _mutations[sid]!.$2 : 0;
    final writes = _writes[sid]?.$1 == day ? _writes[sid]!.$2 : 0;
    if (mutations >= kRecoveryMutationsPerMinute ||
        (daily && writes >= kRecoveryWritesPerDay)) {
      _fail(429, 'rate_limited');
    }
    final reserved = _historyReservations[sid] ?? 0;
    if (reserved + history > kRecoveryMaxReceipts ||
        (allocate != null &&
            (_assigned[sid]?.length ?? 0) >= kRecoveryMaxLifetimeIds)) {
      _fail(409, 'recovery_history_full');
    }
    _mutations[sid] = (minute, mutations + 1);
    if (daily) _writes[sid] = (day, writes + 1);
    _historyReservations[sid] = reserved + history;
    if (allocate != null) (_assigned[sid] ??= {}).add(allocate);
  }

  Never _fail(int status, String code) =>
      throw RecoveryTransportException(status, code);
  void _fields(Map<String, Object?> body, Set<String> fields) {
    if (body['v'] != 2 ||
        body.length != fields.length ||
        !body.keys.every(fields.contains)) {
      _fail(400, 'invalid_recovery');
    }
  }

  String _bytes32(Object? raw) {
    try {
      recoveryBytes32(raw as String);
      return raw;
    } on Object {
      _fail(400, 'invalid_recovery');
    }
  }

  String _operation(Object? raw) {
    if (raw is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(raw) ||
        encodeBase64Url(decodeBase64Url(raw)) != raw) {
      _fail(400, 'invalid_recovery');
    }
    return raw;
  }

  int _cas(RecoveryRequest r) {
    final raw = r.headers['If-Match'];
    if (raw == null) _fail(428, 'precondition_required');
    if (!RegExp(r'^"(0|[1-9][0-9]*)"$').hasMatch(raw)) {
      _fail(400, 'invalid_recovery');
    }
    final n = int.tryParse(raw.substring(1, raw.length - 1));
    if (n == null || n > kRecoveryMaxRevision) _fail(400, 'invalid_recovery');
    return n;
  }

  Future<String?> _verifier(RecoveryRequest r) async {
    final bearer = r.headers['Authorization'];
    if (bearer == null || !bearer.startsWith('Bearer ')) return null;
    final value = _bytes32(bearer.substring(7));
    return recoveryCredentialVerifier(recoveryBytes32(value));
  }

  Future<_Principal> _auth(RecoveryRequest r, String sid) async {
    final verifier = await _verifier(r);
    final all = _devices[sid]?.values ?? <_Principal>[];
    for (final d in all) {
      if (d.verifier == verifier || d.retired.contains(verifier)) {
        if (d.revoked) _fail(403, 'revoked');
        if (d.retired.contains(verifier)) _fail(403, 'credential_replaced');
        if (!d.mobile) _fail(403, 'mobile_required');
        return d;
      }
    }
    _fail(401, 'unauthorized');
  }

  _Row _readable(RecoveryRequest r, String rid) {
    final row = _rows[rid];
    final cap = r.headers['X-Recovery-Cap'];
    if (row == null || cap == null) _fail(404, 'not_found');
    final d = _devices[row.sid]?[row.deviceId];
    if (d == null ||
        d.revoked ||
        !d.mobile ||
        recoveryReadVerifier(cap) != row.readVerifier) {
      _fail(404, 'not_found');
    }
    return row;
  }

  String _capsule(Object? raw, String rid, int revision) {
    if (revision < 1 || revision > kRecoveryMaxRevision) {
      _fail(409, 'recovery_history_full');
    }
    if (raw is String &&
        raw.length > ((kRecoveryCapsuleMaxBytes + 2) ~/ 3) * 4) {
      _fail(413, 'recovery_too_large');
    }
    try {
      if (raw is! String) _fail(400, 'invalid_recovery');
      if (decodeBase64Url(raw).length > kRecoveryCapsuleMaxBytes) {
        _fail(413, 'recovery_too_large');
      }
      final c = RecoveryCapsule.fromJson({
        'v': 2,
        'recoveryId': rid,
        'revision': revision,
        'capsule': raw,
      });
      return encodeBase64Url(c.bytes);
    } on RecoveryTransportException {
      rethrow;
    } on Object {
      _fail(400, 'invalid_recovery');
    }
  }

  String _fingerprint(RecoveryRequest r, int cas) => encodeBase64Url(
    const DartSha256()
        .hashSync(
          utf8.encode(
            canonicalJsonOf({'body': r.body, 'expectedRevision': cas}),
          ),
        )
        .bytes,
  );

  void _capsuleSyntax(Object? raw, String rid) {
    if (raw is! String) _fail(400, 'invalid_recovery');
    // Size/header checks are independent of resource existence and CAS. In
    // particular, an altered replay CAS must reach receipt fingerprinting.
    final bytes = decodeBase64Url(raw);
    if (bytes.length > kRecoveryCapsuleMaxBytes) {
      _fail(413, 'recovery_too_large');
    }
    _capsule(raw, rid, peekRecoveryCapsule(bytes).revision);
  }

  Map<String, Object?> _ack(
    String rid,
    int revision, {
    String? operation,
    String? deviceId,
  }) => {
    'v': 2,
    'recoveryId': rid,
    'revision': revision,
    'operationId': ?operation,
    'deviceId': ?deviceId,
  };

  @override
  Future<RecoveryResponse> send(RecoveryRequest request) async {
    const names = {
      'authorization': 'Authorization',
      'if-match': 'If-Match',
      'x-recovery-cap': 'X-Recovery-Cap',
      'x-recovery-operation': 'X-Recovery-Operation',
    };
    final normalized = RecoveryRequest(
      request.method,
      request.path,
      body: request.body,
      headers: {
        for (final e in request.headers.entries)
          names[e.key.toLowerCase()] ?? e.key: e.value,
      },
    );
    try {
      return await _send(normalized);
    } on RecoveryTransportException catch (e) {
      return _response(e.status, {'error': e.code});
    } on Object {
      return _response(400, {'error': 'invalid_recovery'});
    }
  }

  Future<RecoveryResponse> _send(RecoveryRequest r) async {
    for (final e in _rows.entries.toList()) {
      final rotation = e.value.rotation;
      if (rotation != null && !_now().isBefore(_rotations[rotation]!.expires)) {
        expireRotation(e.key);
      }
    }
    // One implicit source IP in this in-memory HTTP harness. The real Worker
    // obtains its key from the connection, never a capability or recovery id.
    if (r.path.startsWith('/v2/recoveries/')) {
      final minute = _now().toUtc().millisecondsSinceEpoch ~/ 60000;
      final reads = _reads?.$1 == minute ? _reads!.$2 : 0;
      if (reads >= kRecoveryReadsPerMinute) _fail(429, 'rate_limited');
      _reads = (minute, reads + 1);
    }
    final body = r.body ?? <String, Object?>{};
    final size = utf8.encode(jsonEncode(body)).length;
    final limit =
        r.method == 'PUT' || (r.method == 'POST' && !r.path.endsWith('/commit'))
        ? kRecoveryMaxHttpBodyBytes
        : kRecoveryMaxControlBodyBytes;
    if (size > limit) _fail(413, 'recovery_too_large');
    if ((r.method == 'GET' || r.method == 'DELETE') && r.body != null) {
      _fail(400, 'invalid_recovery');
    }
    final parts = r.path.split('/');
    if (parts.length < 4 || parts[1] != 'v2') _fail(400, 'invalid_recovery');
    if (parts[2] == 'recoveries') {
      final rid = _bytes32(parts[3]);
      final cap = r.headers['X-Recovery-Cap'];
      _bytes32(cap);
      final isClaim =
          r.method == 'POST' && parts.length == 5 && parts[4] == 'claim';
      if (!(r.method == 'GET' && parts.length == 4) && !isClaim) {
        _fail(400, 'invalid_recovery');
      }
      if (isClaim) {
        _fields(body, {'v', 'operationId', 'newCredentialVerifier', 'capsule'});
        _operation(body['operationId']);
        _bytes32(body['newCredentialVerifier']);
        _cas(r);
        _capsuleSyntax(body['capsule'], rid);
      }
      final row = _readable(r, rid);
      if (r.method == 'GET' && parts.length == 4) {
        return _response(200, {
          ..._ack(rid, row.revision),
          'capsule': row.capsule,
        }, row.revision);
      }
      if (r.method != 'POST' || parts.length != 5 || parts[4] != 'claim') {
        _fail(400, 'invalid_recovery');
      }
      if (row.candidate) _fail(409, 'recovery_not_active');
      final verifier = await _verifier(r);
      final device = _devices[row.sid]![row.deviceId]!;
      final op = body['operationId'];
      final receipt = row.claim;
      if (receipt != null &&
          receipt.verifier == verifier &&
          receipt.operation == op) {
        if (receipt.fingerprint != _fingerprint(r, _cas(r))) {
          _fail(409, 'recovery_operation_conflict');
        }
        return receipt.response;
      }
      if (device.retired.contains(verifier)) _fail(403, 'credential_replaced');
      if (device.verifier != verifier) _fail(401, 'unauthorized');
      _fields(body, {'v', 'operationId', 'newCredentialVerifier', 'capsule'});
      final operation = _operation(op);
      final cas = _cas(r);
      if (row.revision != cas) _fail(412, 'precondition_failed');
      final next = _bytes32(body['newCredentialVerifier']);
      if (_retiredCredentials.contains(next) ||
          _devices[row.sid]!.values.any((d) => d.verifier == next)) {
        _fail(409, 'recovery_credential_conflict');
      }
      final capsule = _capsule(body['capsule'], rid, cas + 1);
      if (_devices[row.sid]!.values.fold<int>(
            0,
            (n, d) => n + d.retired.length,
          ) >=
          kRecoveryMaxRetiredVerifiers) {
        _fail(409, 'recovery_history_full');
      }
      _charge(row.sid);
      // All validation precedes the single conceptual server transaction.
      final response = _response(
        200,
        _ack(rid, cas + 1, operation: operation, deviceId: row.deviceId),
        cas + 1,
      );
      device.retired.add(device.verifier);
      _retiredCredentials.add(device.verifier);
      device.verifier = next;
      if (row.rotation != null) {
        _closeRotation(row.rotation!, 'recovery_rotation_cancelled');
        row.rotation = null;
      }
      row.capsule = capsule;
      row.revision++;
      row.claim = _Receipt(
        operation,
        verifier!,
        _fingerprint(r, cas),
        response,
      );
      return response;
    }
    if (parts[2] != 'lists' || parts.length < 5 || parts[4] != 'recoveries') {
      _fail(400, 'invalid_recovery');
    }
    final sid = _operation(parts[3]);
    final listRead = parts.length == 5 && r.method == 'GET';
    final resourceWrite =
        parts.length == 6 && (r.method == 'PUT' || r.method == 'DELETE');
    final prepare =
        parts.length == 7 && r.method == 'POST' && parts[6] == 'rotation';
    final commit =
        parts.length == 9 &&
        r.method == 'POST' &&
        parts[6] == 'rotation' &&
        parts[8] == 'commit';
    if (!listRead && !resourceWrite && !prepare && !commit) {
      _fail(400, 'invalid_recovery');
    }
    if (!listRead) {
      final rid = _bytes32(parts[5]);
      _cas(r);
      if (r.method == 'PUT') {
        _fields(body, {'v', 'deviceId', 'readVerifier', 'capsule'});
        if (body['deviceId'] is! String ||
            !kSyncIdPattern.hasMatch(body['deviceId'] as String)) {
          _fail(400, 'invalid_recovery');
        }
        _bytes32(body['readVerifier']);
        _capsuleSyntax(body['capsule'], rid);
        if (_cas(r) == 0) _operation(r.headers['X-Recovery-Operation']);
      } else if (prepare) {
        _fields(body, {
          'v',
          'operationId',
          'newRecoveryId',
          'readVerifier',
          'capsule',
        });
        _operation(body['operationId']);
        _bytes32(body['readVerifier']);
        _capsuleSyntax(body['capsule'], _bytes32(body['newRecoveryId']));
      } else if (commit) {
        _fields(body, {'v'});
        _operation(parts[7]);
      }
    }
    final principal = await _auth(r, sid);
    if (parts.length == 5 && r.method == 'GET') {
      return _response(200, {
        'v': 2,
        'recoveries': [
          for (final e in _rows.entries)
            if (e.value.sid == sid &&
                !e.value.candidate &&
                !_devices[sid]![e.value.deviceId]!.revoked)
              RecoveryMetadata(
                deviceId: e.value.deviceId,
                recoveryId: e.key,
                revision: e.value.revision,
                state: e.value.rotation == null
                    ? RecoveryMetadataState.active
                    : RecoveryMetadataState.rotationPending,
              ).toJson(),
        ],
      });
    }
    if (parts.length < 6) _fail(400, 'invalid_recovery');
    final rid = _bytes32(parts[5]);
    final row = _rows[rid];
    final cas = _cas(r);
    if (r.method == 'PUT' && parts.length == 6) {
      _fields(body, {'v', 'deviceId', 'readVerifier', 'capsule'});
      if (body['deviceId'] != principal.deviceId) _fail(403, 'mobile_required');
      final readVerifier = _bytes32(body['readVerifier']);
      final op = cas == 0 ? _operation(r.headers['X-Recovery-Operation']) : '';
      final key = '$sid/$rid/$op';
      final receipt = _creates[key];
      if (cas == 0 &&
          receipt != null &&
          receipt.verifier == principal.verifier) {
        if (receipt.fingerprint != _fingerprint(r, cas)) {
          _fail(409, 'recovery_operation_conflict');
        }
        return receipt.response;
      }
      if (_retiredIds.contains(rid)) _fail(409, 'recovery_retired');
      if ((row?.revision ?? 0) != cas) _fail(412, 'precondition_failed');
      if (row != null &&
          (row.sid != sid ||
              row.deviceId != principal.deviceId ||
              row.readVerifier != readVerifier ||
              row.candidate)) {
        _fail(409, 'recovery_operation_conflict');
      }
      if (row == null) {
        if (_rows.values.any(
          (e) =>
              e.sid == sid && e.deviceId == principal.deviceId && !e.candidate,
        )) {
          _fail(409, 'recovery_exists');
        }
        if (_rows.values.where((e) => e.sid == sid && !e.candidate).length >=
            4) {
          _fail(409, 'recovery_limit');
        }
      }
      final capsule = _capsule(body['capsule'], rid, cas + 1);
      _charge(
        sid,
        history: row == null ? 3 : 0,
        allocate: row == null ? rid : null,
      );
      final next =
          row ?? _Row(sid, principal.deviceId, readVerifier, capsule, 0);
      if (next.rotation != null) {
        _closeRotation(next.rotation!, 'recovery_rotation_cancelled');
        next.rotation = null;
      }
      next.capsule = capsule;
      next.revision = cas + 1;
      _rows[rid] = next;
      final response = _response(
        cas == 0 ? 201 : 200,
        _ack(rid, cas + 1),
        cas + 1,
      );
      if (cas == 0) {
        _creates[key] = _Receipt(
          op,
          principal.verifier,
          _fingerprint(r, cas),
          response,
        );
      }
      return response;
    }
    if (r.method == 'DELETE' && parts.length == 6) {
      final deleted = _deletes[rid];
      if (deleted != null &&
          deleted.$1 == sid &&
          deleted.$2 == principal.deviceId) {
        if (deleted.$3 != cas) _fail(412, 'precondition_failed');
        return _response(204);
      }
      if (row == null || row.sid != sid || row.candidate) {
        _fail(404, 'not_found');
      }
      if (row.revision != cas) _fail(412, 'precondition_failed');
      _charge(sid, daily: false);
      _deletes[rid] = (sid, principal.deviceId, cas);
      if (row.rotation != null) {
        _closeRotation(row.rotation!, 'recovery_rotation_cancelled');
      }
      _rows.remove(rid);
      _retiredIds.add(rid);
      return _response(204);
    }
    if (r.method != 'POST' || parts.length < 7 || parts[6] != 'rotation') {
      _fail(400, 'invalid_recovery');
    }
    final op = _operation(
      parts.length == 7
          ? body['operationId']
          : parts.length == 9 && parts[8] == 'commit'
          ? parts[7]
          : null,
    );
    final rotationKey = '$rid/$op';
    final previous = _rotations[rotationKey];
    if (previous != null && previous.verifier == principal.verifier) {
      if (parts.length == 7) {
        if (previous.fingerprint != _fingerprint(r, cas)) {
          _fail(409, 'recovery_operation_conflict');
        }
        if (previous.closed != null) _fail(409, previous.closed!);
        return previous.committed ?? previous.prepared;
      }
      _fields(body, {'v'});
      if (cas != previous.cas) _fail(409, 'recovery_operation_conflict');
      if (previous.closed != null) _fail(409, previous.closed!);
      if (previous.committed != null) return previous.committed!;
    }
    if (row == null || row.sid != sid) _fail(404, 'not_found');
    if (row.deviceId != principal.deviceId || row.candidate) {
      _fail(403, 'mobile_required');
    }
    if (row.revision != cas) _fail(412, 'precondition_failed');
    if (parts.length == 7) {
      _fields(body, {
        'v',
        'operationId',
        'newRecoveryId',
        'readVerifier',
        'capsule',
      });
      if (_rows.values.any((e) => e.sid == sid && e.rotation != null)) {
        _fail(409, 'recovery_operation_conflict');
      }
      final nextId = _bytes32(body['newRecoveryId']);
      final readVerifier = _bytes32(body['readVerifier']);
      if (_rows.containsKey(nextId) || _retiredIds.contains(nextId)) {
        _fail(409, 'recovery_retired');
      }
      final capsule = _capsule(body['capsule'], nextId, 1);
      _charge(sid, history: 4, allocate: nextId);
      final response = _response(201, _ack(nextId, 1, operation: op), 1);
      _rows[nextId] = _Row(sid, principal.deviceId, readVerifier, capsule, 1)
        ..candidate = true;
      row.rotation = rotationKey;
      _rotations[rotationKey] = _Rotation(
        principal.verifier,
        _fingerprint(r, cas),
        cas,
        nextId,
        response,
        _now().add(const Duration(hours: 24)),
      );
      return response;
    }
    if (previous == null) _fail(409, 'recovery_operation_conflict');
    _fields(body, {'v'});
    _charge(sid, daily: false);
    _rows[previous.nextId]!.candidate = false;
    _rows.remove(rid);
    _retiredIds.add(rid);
    return previous.committed = _response(
      200,
      _ack(previous.nextId, 1, operation: op),
      1,
    );
  }

  void _closeRotation(String key, String code) {
    final rotation = _rotations[key]!;
    rotation.closed = code;
    _rows.remove(rotation.nextId);
    _retiredIds.add(rotation.nextId);
  }

  /// Model the Worker's 24-hour candidate expiry without waiting in tests.
  void expireRotation(String rid) {
    final key = _rows[rid]?.rotation;
    if (key != null) {
      _closeRotation(key, 'recovery_rotation_expired');
      _rows[rid]!.rotation = null;
    }
  }
}

class _Principal {
  _Principal(this.deviceId, this.verifier, this.mobile);
  final String deviceId;
  String verifier;
  final bool mobile;
  bool revoked = false;
  final retired = <String>{};
}

class _Row {
  _Row(this.sid, this.deviceId, this.readVerifier, this.capsule, this.revision);
  final String sid, deviceId, readVerifier;
  String capsule;
  int revision;
  bool candidate = false;
  String? rotation;
  _Receipt? claim;
}

class _Receipt {
  _Receipt(this.operation, this.verifier, this.fingerprint, this.response);
  final String operation, verifier, fingerprint;
  final RecoveryResponse response;
}

class _Rotation {
  _Rotation(
    this.verifier,
    this.fingerprint,
    this.cas,
    this.nextId,
    this.prepared,
    this.expires,
  );
  final String verifier, fingerprint, nextId;
  final int cas;
  final RecoveryResponse prepared;
  final DateTime expires;
  RecoveryResponse? committed;
  String? closed;
}
