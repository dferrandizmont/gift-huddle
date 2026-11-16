import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/recovery.dart';
import 'package:regalos/core/sync/recovery_locator.dart';
import 'package:regalos/features/sync/data/recovery_transport.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';

import '../helpers/memory_recovery_transport.dart';

void main() {
  final vector = jsonDecode(
    File('../docs/adr/0007-vector-recuperacion.json').readAsStringSync(),
  ) as Map;
  late RecoveryCapsulePayload payload;
  late RecoveryCode code;
  late RecoveryLocator locator;
  late V2Auth auth;
  late MemoryRecoveryTransport server;
  String op(int n) => encodeBase64Url(List.filled(16, n));
  setUpAll(() async {
    payload = await RecoveryCapsulePayload.fromJson(vector['payload']);
    final hex = vector['entropyHex'] as String;
    code = RecoveryCode(
      Uint8List.fromList([
        for (var i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ]),
    );
    locator = await deriveRecoveryLocator(code);
    auth = V2Auth(
      syncId: payload.identity.syncId,
      deviceId: payload.identity.deviceId,
      credential: payload.deviceKeys.serviceCredential,
    );
  });
  RecoveryRequest create() => RecoveryRequest(
    'PUT',
    '/v2/lists/${auth.syncId}/recoveries/${locator.recoveryId}',
    headers: {...recoveryAuthHeaders(auth, 0), 'X-Recovery-Operation': op(1)},
    body: {
      'v': 2,
      'deviceId': auth.deviceId,
      'readVerifier': locator.readVerifier,
      'capsule': vector['capsule'],
    },
  );
  RecoveryRequest get({String? cap}) => RecoveryRequest(
    'GET',
    '/v2/recoveries/${locator.recoveryId}',
    headers: {'X-Recovery-Cap': cap ?? locator.readCap},
  );
  setUp(() async {
    server = MemoryRecoveryTransport();
    await server.register(auth);
  });

  test('create and delete receipts, CAS, roles and retired ids', () async {
    final request = create();
    final first = await server.send(request);
    expect(first.status, 201);
    expect(first.headers['etag'], '"1"');
    expect(first.headers['cache-control'], 'no-store');
    expect((await server.send(request)).toJson(), first.toJson());
    expect(
      (await server.send(
        RecoveryRequest(
          request.method,
          request.path,
          headers: request.headers,
          body: {...request.body!, 'deviceId': op(2)},
        ),
      )).status,
      403,
    );
    final listed = await server.send(
      RecoveryRequest(
        'GET',
        '/v2/lists/${auth.syncId}/recoveries',
        headers: {'Authorization': auth.bearer},
      ),
    );
    final rows = (listed.body as Map)['recoveries'] as List;
    expect(rows, hasLength(1));
    expect((rows.single as Map).keys.toSet(), {
      'deviceId',
      'recoveryId',
      'revision',
      'state',
    });
    final deleted = RecoveryRequest(
      'DELETE',
      request.path,
      headers: recoveryAuthHeaders(auth, 1),
    );
    expect((await server.send(deleted)).status, 204);
    expect((await server.send(deleted)).status, 204);
    expect(
      (await server.send(
        RecoveryRequest(
          'DELETE',
          request.path,
          headers: recoveryAuthHeaders(auth, 2),
        ),
      )).status,
      412,
    );
    expect((await server.send(get())).status, 404);
    expect(
      (await server.send(request)).toJson(),
      first.toJson(),
    ); // receipt does not resurrect
    expect((await server.send(get())).status, 404);
    final web = V2Auth(
      syncId: auth.syncId,
      deviceId: op(6),
      credential: Uint8List.fromList(List.filled(32, 6)),
    );
    await server.register(web, mobile: false);
    expect(
      (await server.send(
        RecoveryRequest(
          'GET',
          '/v2/lists/${auth.syncId}/recoveries',
          headers: {'Authorization': web.bearer},
        ),
      )).error,
      'mobile_required',
    );
  });

  test('claim receipt precedence, exact-body conflict, stale receipt and revocation', () async {
    await server.send(create());
    final keys = await payload.deviceKeys.withNewServiceCredential();
    final next = await RecoveryCapsulePayload.fromJson({
      ...payload.toJson(),
      'deviceKeys': keys.toJson(),
    });
    final bytes = await sealRecoveryCapsule(next, code, revision: 2);
    final claim = RecoveryRequest(
      'POST',
      '/v2/recoveries/${locator.recoveryId}/claim',
      headers: {
        ...recoveryAuthHeaders(auth, 1),
        'X-Recovery-Cap': locator.readCap,
      },
      body: {
        'v': 2,
        'operationId': op(7),
        'newCredentialVerifier': encodeBase64Url(
          await keys.serviceCredentialVerifier(),
        ),
        'capsule': encodeBase64Url(bytes),
      },
    );
    final receipt = await server.send(claim);
    expect(receipt.status, 200);
    expect((await server.send(claim)).toJson(), receipt.toJson());
    expect(
      (await server.send(
        RecoveryRequest(
          claim.method,
          claim.path,
          headers: {...claim.headers, 'If-Match': '"2"'},
          body: claim.body,
        ),
      )).error,
      'recovery_operation_conflict',
    );
    final conflict = await server.send(
      RecoveryRequest(
        claim.method,
        claim.path,
        headers: claim.headers,
        body: {
          ...claim.body!,
          'newCredentialVerifier': encodeBase64Url(List.filled(32, 10)),
        },
      ),
    );
    expect(conflict.error, 'recovery_operation_conflict');
    expect(
      (await server.send(
        RecoveryRequest(
          claim.method,
          claim.path,
          headers: claim.headers,
          body: {...claim.body!, 'operationId': op(8)},
        ),
      )).error,
      'credential_replaced',
    );
    expect(
      (await server.send(
        RecoveryRequest(
          claim.method,
          claim.path,
          headers: {
            ...claim.headers,
            'X-Recovery-Cap': encodeBase64Url(List.filled(32, 10)),
          },
          body: claim.body,
        ),
      )).error,
      'not_found',
    );
    final currentAuth = V2Auth(
      syncId: auth.syncId,
      deviceId: auth.deviceId,
      credential: keys.serviceCredential,
    );
    final updated = await sealRecoveryCapsule(next, code, revision: 3);
    expect(
      (await server.send(
        RecoveryRequest(
          'PUT',
          create().path,
          headers: recoveryAuthHeaders(currentAuth, 2),
          body: {...create().body!, 'capsule': encodeBase64Url(updated)},
        ),
      )).status,
      200,
    );
    expect((await server.send(claim)).toJson(), receipt.toJson());
    expect(((await server.send(get())).body as Map)['revision'], 3);
    server.revoke(auth.syncId, auth.deviceId);
    expect((await server.send(claim)).error, 'not_found');
    expect((await server.send(get())).headers, isNot(contains('etag')));
  });

  test('rotation candidate, terminal prepare/commit receipts, cancellation and expiry', () async {
    await server.send(create());
    final newCode = RecoveryCode(Uint8List.fromList(List.filled(32, 42)));
    final nextLocator = await deriveRecoveryLocator(newCode);
    final bytes = await sealRecoveryCapsule(payload, newCode, revision: 1);
    final prepare = RecoveryRequest(
      'POST',
      '${create().path}/rotation',
      headers: recoveryAuthHeaders(auth, 1),
      body: {
        'v': 2,
        'operationId': op(2),
        'newRecoveryId': nextLocator.recoveryId,
        'readVerifier': nextLocator.readVerifier,
        'capsule': encodeBase64Url(bytes),
      },
    );
    expect((await server.send(prepare)).status, 201);
    final candidate = await server.send(
      RecoveryRequest(
        'GET',
        '/v2/recoveries/${nextLocator.recoveryId}',
        headers: {'X-Recovery-Cap': nextLocator.readCap},
      ),
    );
    expect(candidate.status, 200);
    final candidateClaim = RecoveryRequest(
      'POST',
      '/v2/recoveries/${nextLocator.recoveryId}/claim',
      headers: {
        ...recoveryAuthHeaders(auth, 1),
        'X-Recovery-Cap': nextLocator.readCap,
      },
      body: {
        'v': 2,
        'operationId': op(3),
        'newCredentialVerifier': encodeBase64Url(List.filled(32, 12)),
        'capsule': encodeBase64Url(
          await sealRecoveryCapsule(payload, newCode, revision: 2),
        ),
      },
    );
    expect((await server.send(candidateClaim)).error, 'recovery_not_active');
    final commit = RecoveryRequest(
      'POST',
      '${create().path}/rotation/${op(2)}/commit',
      headers: recoveryAuthHeaders(auth, 1),
      body: {'v': 2},
    );
    final committed = await server.send(commit);
    expect(committed.status, 200);
    expect((await server.send(commit)).toJson(), committed.toJson());
    expect((await server.send(prepare)).toJson(), committed.toJson());
    expect((await server.send(get())).error, 'not_found');
    // Reopen the scenario for the two terminal states.
    for (final expires in [false, true]) {
      server = MemoryRecoveryTransport();
      await server.register(auth);
      await server.send(create());
      await server.send(prepare);
      if (expires) {
        server.expireRotation(locator.recoveryId);
      } else {
        final newer = await sealRecoveryCapsule(payload, code, revision: 2);
        await server.send(
          RecoveryRequest(
            'PUT',
            create().path,
            headers: recoveryAuthHeaders(auth, 1),
            body: {...create().body!, 'capsule': encodeBase64Url(newer)},
          ),
        );
      }
      final expected = expires
          ? 'recovery_rotation_expired'
          : 'recovery_rotation_cancelled';
      expect((await server.send(prepare)).error, expected);
      expect((await server.send(commit)).error, expected);
      expect(
        (await server.send(
          RecoveryRequest(
            'POST',
            prepare.path,
            headers: prepare.headers,
            body: {
              ...prepare.body!,
              'readVerifier': encodeBase64Url(List.filled(32, 99)),
            },
          ),
        )).error,
        'recovery_operation_conflict',
      );
    }
  });

  test(
    'syntax errors precede lookup, while wrong capability is uniform 404',
    () async {
      final path = '/v2/recoveries/${locator.recoveryId}/claim';
      final bad = RecoveryRequest(
        'POST',
        path,
        headers: {'X-Recovery-Cap': locator.readCap},
        body: {'v': 2},
      );
      expect((await server.send(bad)).status, 400);
      await server.send(create());
      expect((await server.send(bad)).status, 400);
      final hidden = await server.send(
        get(cap: encodeBase64Url(List.filled(32, 55))),
      );
      expect(hidden.status, 404);
      expect(hidden.headers, isNot(contains('etag')));
      final missingCas = await server.send(
        RecoveryRequest(
          'DELETE',
          create().path,
          headers: {'Authorization': auth.bearer},
        ),
      );
      expect(missingCas.status, 428);
    },
  );

  test(
    'traffic quota returns Retry-After without changing the capsule',
    () async {
      var now = DateTime.utc(2026, 11, 15);
      server = MemoryRecoveryTransport(now: () => now);
      await server.register(auth);
      await server.send(create());
      for (var n = 0; n < kRecoveryReadsPerMinute; n++) {
        expect((await server.send(get())).status, 200);
      }
      final limited = await server.send(get());
      expect(limited.status, 429);
      expect(limited.headers['retry-after'], '60');
      expect(limited.headers, isNot(contains('etag')));
      now = now.add(const Duration(minutes: 1));
      expect(((await server.send(get())).body as Map)['revision'], 1);
    },
  );
}
