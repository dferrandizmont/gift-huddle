import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:regalos/features/sync/data/sync_endpoint.dart';
import 'package:regalos/features/sync/data/sync_config.dart';

void main() {
  test('legacy default keeps API and invitations together', () {
    final endpoint = SyncEndpoint.parse('sync.example')!;
    expect(endpoint.base.toString(), 'https://sync.example');
    expect(endpoint.invitationOrigin, endpoint.base);
    expect(endpoint.invitationHost, endpoint.host);
    expect(SyncEndpoint.parse('http://localhost:8787')!.host, 'localhost:8787');
  });
  test(
    'invitation origin is independent of API, including provider overrides',
    () {
      final container = ProviderContainer(
        overrides: [
          syncHostProvider.overrideWithValue('https://sync.example'),
          invitationOriginProvider.overrideWithValue('https://gifthuddle.app'),
        ],
      );
      addTearDown(container.dispose);
      final endpoint = container.read(syncEndpointProvider)!;
      expect(endpoint.base.host, 'sync.example');
      expect(endpoint.invitationHost, 'gifthuddle.app');
    },
  );
  test('both configured origins reject unsafe addresses', () {
    for (final bad in [
      '',
      'http://example.com',
      'ftp://example.com',
      'https://a#key',
      'https://a?q=x',
      'https://key@a',
    ]) {
      expect(SyncEndpoint.parse(bad), isNull, reason: bad);
      if (bad.isNotEmpty) {
        expect(
          SyncEndpoint.parse('sync.example', invitationOrigin: bad),
          isNull,
        );
      }
    }
  });
  test('defaults are the Worker v2 and the public web origin', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final endpoint = container.read(syncEndpointProvider)!;
    expect(endpoint.base.toString(), 'https://sync.gifthuddle.app');
    expect(endpoint.invitationHost, 'gifthuddle.app');
    expect(kDefaultSyncHost, 'https://sync.gifthuddle.app');
    expect(kDefaultInvitationOrigin, 'https://gifthuddle.app');
  });
}
