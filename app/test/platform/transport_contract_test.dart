import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/features/sync/data/sync_endpoint.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';
import 'package:regalos/features/sync/data/sync_transport_common.dart';

class FakeTransport extends BaseSyncTransport {
  FakeTransport() : super(SyncEndpoint.parse('sync.example')!);
  SyncResponse next = SyncResponse(304, {}, Uint8List(0));
  late String method;
  late Uri sentUri;
  late Map<String, String> headers;
  Object? body;
  @override
  Future<SyncResponse> send(
    String method,
    Uri uri, {
    SyncCredentials? auth,
    Object? body,
    Map<String, String> headers = const {},
  }) async {
    this.method = method;
    sentUri = uri;
    this.headers = headers;
    this.body = body;
    return next;
  }

  @override
  Stream<SyncEvent> watch(SyncCredentials auth) => const Stream.empty();
  @override
  void close() {}
  void reply(
    int status, [
    Object? body,
    Map<String, String> headers = const {},
  ]) {
    next = SyncResponse(
      status,
      headers,
      Uint8List.fromList(body == null ? [] : utf8.encode(jsonEncode(body))),
    );
  }
}

void main() {
  final auth = SyncCredentials(
    listId: 'private',
    syncId: 'opaque',
    authKey: Uint8List(32),
  );
  late FakeTransport transport;
  setUp(() => transport = FakeTransport());
  test(
    'shared HTTP contract preserves 304, conditional requests and 409',
    () async {
      expect(
        await transport.getList(auth, ifNoneMatch: 7),
        isA<SyncGetNotModified>(),
      );
      expect(transport.sentUri.path, '/v1/lists/opaque');
      expect(transport.headers['If-None-Match'], '"7"');
      transport.reply(409, {
        'version': 8,
        'envelope': encodeBase64Url([1, 2]),
      });
      final conflict = await transport.putList(
        auth,
        baseVersion: 7,
        envelope: Uint8List(0),
      ) as SyncPutConflict;
      expect(conflict.version, 8);
      expect(conflict.envelope, [1, 2]);
      transport.reply(409, {'error': 'exists'});
      await expectLater(
        transport.putList(auth, baseVersion: null, envelope: Uint8List(0)),
        throwsA(
          isA<SyncTransportException>().having(
            (e) => e.failure,
            'failure',
            SyncFailure.unauthorized,
          ),
        ),
      );
    },
  );
  test('rate limit and malformed JSON have the same typed failures', () async {
    transport.reply(429, null, {'retry-after': '60'});
    await expectLater(
      transport.getList(auth),
      throwsA(
        isA<SyncTransportException>().having(
          (e) => e.retryAfter,
          'retry',
          const Duration(seconds: 60),
        ),
      ),
    );
    transport.reply(200, ['bad']);
    await expectLater(
      transport.getList(auth),
      throwsA(
        isA<SyncTransportException>().having(
          (e) => e.failure,
          'failure',
          SyncFailure.protocol,
        ),
      ),
    );
    transport.reply(409);
    await expectLater(
      transport.requestJoin(
        'invite',
        publicKey: Uint8List(32),
        deviceName: 'Aritz',
      ),
      throwsA(isA<InviteTakenException>()),
    );
  });
}
