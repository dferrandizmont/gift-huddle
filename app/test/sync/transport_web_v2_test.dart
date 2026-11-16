import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/features/sync/application/pairing_v2_flow.dart';
import 'package:regalos/features/sync/application/v2_family_lock.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';
import 'package:regalos/features/sync/data/sync_transport_common.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';

import '../web_device/web_engine_support.dart';
import 'v2_harness.dart';

void main() {
  final auth = V2Auth(
    syncId: kV2Sync,
    deviceId: 'web-device',
    credential: Uint8List(32),
  );
  test(
    'PUT common has exactly one field and a strong conditional ETag',
    () async {
      final client = SyncV2Client(
        base: Uri.parse('https://sync.test'),
        sendRequest: (method, uri, {body, headers = const {}}) async {
          expect(method, 'PUT');
          expect(uri.path, '/v2/lists/$kV2Sync/common');
          expect(body, {'common': 'AQID'});
          expect(headers['If-Match'], '"7"');
          expect(headers['Authorization'], auth.bearer);
          return SyncResponse(200, {
            'etag': '"8"',
          }, Uint8List.fromList(utf8.encode('{"version":8}')));
        },
      );
      expect(
        await client.putCommon(
          auth,
          version: 7,
          common: Uint8List.fromList([1, 2, 3]),
        ),
        isA<V2WriteOk>().having((r) => r.version, 'version', 8),
      );
    },
  );
  for (final testCase in [
    (403, 'forbidden_role'),
    (409, 'invite_exists'),
    (400, 'role_mismatch'),
    (400, 'person_mismatch'),
  ]) {
    test('classified web protocol failure ${testCase.$2}', () async {
      final client = SyncV2Client(
        base: Uri.parse('https://sync.test'),
        sendRequest: (method, uri, {body, headers = const {}}) async =>
            SyncResponse(
              testCase.$1,
              {},
              Uint8List.fromList(
                utf8.encode(jsonEncode({'error': testCase.$2})),
              ),
            ),
      );
      final matcher = switch (testCase.$1) {
        403 => isA<V2ForbiddenException>().having(
          (e) => e.code,
          'code',
          testCase.$2,
        ),
        409 => isA<V2InviteConflictException>().having(
          (e) => e.code,
          'code',
          testCase.$2,
        ),
        _ => isA<V2PairingMismatchException>().having(
          (e) => e.code,
          'code',
          testCase.$2,
        ),
      };
      await expectLater(client.createInvite(auth, {}), throwsA(matcher));
    });
  }
  test(
    'common stale response and missing precondition preserve registry/slots',
    () async {
      final h = WebHarness();
      await h.setup();
      addTearDown(h.close);
      final registry = jsonEncode(h.worker.registryOf(kV2Sync));
      final version = h.worker.versionOf(kV2Sync)!;
      final stale = await h.client.putCommon(
        h.engine.auth,
        version: version - 1,
        common: Uint8List(0),
      );
      expect(
        stale,
        isA<V2WriteStale>().having((r) => r.current, 'current', version),
      );
      final bad = await h.worker.send(
        'PUT',
        Uri.parse('https://sync.test/v2/lists/$kV2Sync/common'),
        headers: {'Authorization': h.engine.auth.bearer},
        body: {'common': 'AQID'},
      );
      expect(bad.status, 428);
      final extra = await h.worker.send(
        'PUT',
        Uri.parse('https://sync.test/v2/lists/$kV2Sync/common'),
        headers: {
          'Authorization': h.engine.auth.bearer,
          'If-Match': '"$version"',
        },
        body: {'common': 'AQID', 'registry': {}},
      );
      expect(extra.status, 400);
      expect(jsonEncode(h.worker.registryOf(kV2Sync)), registry);
    },
  );
  test(
    'global invite id cannot be replaced by another list or person',
    () async {
      final h = WebHarness();
      await h.setup(approve: false);
      addTearDown(h.close);
      final second = await MemoryV2Phone.create(
        'nora-phone',
        'nora',
        3,
        familyKey: await FamilyKey.generate(),
        migrated: true,
        syncId: encodeBase64Url(List.filled(16, 2)),
      );
      second.addPerson('leo', 'Leo');
      second.addPerson('nora', 'Nora');
      await expectLater(
        PairingV2Host.start(
          transport: h.client,
          local: second,
          lock: V2FamilyLock(),
          web: h.guest.qr,
          guestPerson: 'leo',
        ),
        throwsA(
          isA<V2InviteConflictException>().having(
            (e) => e.code,
            'reservation',
            'invite_exists',
          ),
        ),
      );
    },
  );
  test(
    'malformed guestPerson fails; old device role defaults to device',
    () async {
      final h = WebHarness();
      await h.setup();
      addTearDown(h.close);
      h.worker.tamper = (method, uri, r) {
        if (uri.path != '/v2/lists/$kV2Sync' || method != 'GET') return r;
        final body = r.json();
        for (final device in body['devices'] as List) {
          (device as Map).remove('role');
        }
        return SyncResponse(
          200,
          r.headers,
          Uint8List.fromList(utf8.encode(jsonEncode(body))),
        );
      };
      expect(
        (await h.client.getList(h.phone.auth) as V2GetOk).snapshot.devices
            .every((d) => d.role == 'device'),
        isTrue,
      );
      h.worker.tamper = (method, uri, r) {
        if (!uri.path.endsWith('/offer')) return r;
        return SyncResponse(
          200,
          r.headers,
          Uint8List.fromList(
            utf8.encode(jsonEncode({...r.json(), 'guestPerson': 42})),
          ),
        );
      };
      await expectLater(
        h.client.getOffer(h.guest.qr.inviteId),
        throwsA(isA<SyncTransportException>()),
      );
    },
  );
}
