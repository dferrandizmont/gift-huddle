import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:regalos/core/platform/link_source.dart';
import 'package:regalos/core/platform/link_source_native.dart';
import 'package:regalos/features/sync/data/sync_config.dart';
import 'package:regalos/features/sync/invites/incoming_invite.dart';

class FakeLinks implements LinkSource {
  FakeLinks(this.initial);
  String? initial;
  final controller = StreamController<String>.broadcast();
  @override
  String? takeInitialLink() {
    final uri = initial;
    initial = null;
    return uri;
  }

  @override
  Stream<String> get links => controller.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native events retain explicit ports until invitation validation',
    () async {
      const channel = 'com.llfbandit.app_links/events';
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final listening = Completer<void>();
      messenger.setMockMethodCallHandler(const MethodChannel(channel), (
        call,
      ) async {
        if (call.method == 'listen') listening.complete();
        return null;
      });
      final container = ProviderContainer(
        overrides: [linkSourceProvider.overrideWithValue(NativeLinkSource())],
      );
      addTearDown(() async {
        container.dispose();
        await Future<void>.delayed(Duration.zero);
        messenger.setMockMethodCallHandler(const MethodChannel(channel), null);
      });
      expect(container.read(incomingInviteProvider), isNull);
      await listening.future;
      const id = 'AAAAAAAAAAAAAAAAAAAAAA';
      for (final host in ['gifthuddle.app', 'gifthuddle.retired.example']) {
        for (final port in [':443', '']) {
          container.read(incomingInviteProvider.notifier).consume();
          ServicesBinding.instance.channelBuffers.push(
            channel,
            const StandardMethodCodec().encodeSuccessEnvelope(
              'https://$host$port/i#$id',
            ),
            (_) {},
          );
          await Future<void>.delayed(Duration.zero);
          expect(
            container.read(incomingInviteProvider),
            host == 'gifthuddle.app' && port.isEmpty ? id : isNull,
          );
        }
      }
    },
  );

  test(
    'invitation is consumed before routing and uses the public origin',
    () async {
      const id = 'AAAAAAAAAAAAAAAAAAAAAA';
      final links = FakeLinks('https://gifthuddle.app/i#$id');
      final container = ProviderContainer(
        overrides: [
          linkSourceProvider.overrideWithValue(links),
          syncHostProvider.overrideWithValue('sync.example'),
          invitationOriginProvider.overrideWithValue('gifthuddle.app'),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await links.controller.close();
      });
      expect(container.read(incomingInviteProvider), id);
      expect(links.takeInitialLink(), isNull);
      container.read(incomingInviteProvider.notifier).consume();
      links.controller.add('https://sync.example/i#$id');
      await Future<void>.delayed(Duration.zero);
      expect(container.read(incomingInviteProvider), isNull);
      links.controller.add('https://gifthuddle.app/i#$id');
      await Future<void>.delayed(Duration.zero);
      expect(container.read(incomingInviteProvider), id);
    },
  );

  test(
    'by default invitations open only from the current public host',
    () async {
      const id = 'BBBBBBBBBBBBBBBBBBBBBB';
      final links = FakeLinks('https://sync.gifthuddle.app/i#$id');
      final container = ProviderContainer(
        overrides: [linkSourceProvider.overrideWithValue(links)],
      );
      addTearDown(() async {
        container.dispose();
        await links.controller.close();
      });
      // The API host is not the invitation origin.
      expect(container.read(incomingInviteProvider), isNull);
      for (final host in ['gifthuddle.app', 'gifthuddle.retired.example']) {
        container.read(incomingInviteProvider.notifier).consume();
        links.controller.add('https://$host/i#$id');
        await Future<void>.delayed(Duration.zero);
        expect(
          container.read(incomingInviteProvider),
          host == 'gifthuddle.app' ? id : isNull,
        );
      }
    },
  );

  for (final host in ['gifthuddle.app', 'gifthuddle.retired.example']) {
    test(
      'rejects explicit :443 from $host on initial and live links',
      () async {
        const id = 'AAAAAAAAAAAAAAAAAAAAAA';
        final links = FakeLinks('https://$host:443/i#$id');
        final container = ProviderContainer(
          overrides: [linkSourceProvider.overrideWithValue(links)],
        );
        addTearDown(() async {
          container.dispose();
          await links.controller.close();
        });
        expect(container.read(incomingInviteProvider), isNull);
        links.controller.add('https://$host:443/i#$id');
        await Future<void>.delayed(Duration.zero);
        expect(container.read(incomingInviteProvider), isNull);
        links.controller.add('https://$host/i#$id');
        await Future<void>.delayed(Duration.zero);
        expect(
          container.read(incomingInviteProvider),
          host == 'gifthuddle.app' ? id : isNull,
        );
      },
    );

    test('cold invitation from $host', () async {
      const id = 'AAAAAAAAAAAAAAAAAAAAAA';
      final links = FakeLinks('https://$host/i#$id');
      final container = ProviderContainer(
        overrides: [linkSourceProvider.overrideWithValue(links)],
      );
      addTearDown(() async {
        container.dispose();
        await links.controller.close();
      });
      expect(
        container.read(incomingInviteProvider),
        host == 'gifthuddle.app' ? id : isNull,
      );
    });
  }
}
