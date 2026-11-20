import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:regalos/core/platform/link_source.dart';
import 'package:regalos/core/platform/link_source_native.dart';
import 'package:regalos/features/sync/data/sync_config.dart';
import 'package:regalos/features/sync/invites/incoming_invite.dart';

class FakeLinks implements LinkSource {
  FakeLinks(this.initial);
  FutureOr<String?> initial;
  final controller = StreamController<String>.broadcast();
  @override
  FutureOr<String?> takeInitialLink() {
    final uri = initial;
    initial = null;
    return uri;
  }

  @override
  Stream<String> get links => controller.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('iOS consumes the plugin initial string once', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    const channel = MethodChannel('com.llfbandit.app_links/messages');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getInitialLink');
      return 'https://gifthuddle.app:443/i#AAAAAAAAAAAAAAAAAAAAAA';
    });
    final source = NativeLinkSource();
    expect(
      await source.takeInitialLink(),
      'https://gifthuddle.app:443/i#AAAAAAAAAAAAAAAAAAAAAA',
    );
    expect(await source.takeInitialLink(), isNull);
  });

  for (final streamFirst in [false, true]) {
    test(
      'async launch link deduplicates with stream, streamFirst=$streamFirst',
      () async {
        const id = 'AAAAAAAAAAAAAAAAAAAAAA';
        const uri = 'https://gifthuddle.app/i#$id';
        fakeAsync((async) {
          final initial = Completer<String?>();
          final links = FakeLinks(null)..initial = initial.future;
          final container = ProviderContainer(
            overrides: [linkSourceProvider.overrideWithValue(links)],
          );
          addTearDown(() async {
            container.dispose();
            await links.controller.close();
          });
          expect(container.read(incomingInviteProvider), isNull);
          if (streamFirst) {
            links.controller.add(uri);
          } else {
            initial.complete(uri);
          }
          async.flushMicrotasks();
          expect(container.read(incomingInviteProvider), id);
          container.read(incomingInviteProvider.notifier).consume();
          // A launch copy delayed well beyond the former three-second window.
          async.elapse(const Duration(minutes: 2));
          if (streamFirst) {
            initial.complete(uri);
          } else {
            links.controller.add(uri);
          }
          async.flushMicrotasks();
          expect(container.read(incomingInviteProvider), isNull);
          // Reconnection has one native owner; each following stream event is
          // a real tap, even for the same URI and without waiting.
          for (final tap in [
            uri,
            uri,
            'https://gifthuddle.app/i#BBBBBBBBBBBBBBBBBBBBBB',
          ]) {
            links.controller.add(tap);
            async.flushMicrotasks();
            expect(
              container.read(incomingInviteProvider),
              tap == uri ? id : 'BBBBBBBBBBBBBBBBBBBBBB',
            );
            container.read(incomingInviteProvider.notifier).consume();
          }
        });
      },
    );
  }

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
