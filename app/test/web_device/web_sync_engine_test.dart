import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/device_keys.dart';
import 'package:regalos/core/sync/key_bundle.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/family/data/storage_providers.dart';
import 'package:regalos/features/sync/application/recovery_providers.dart';
import 'package:regalos/features/sync/data/sync_config.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';
import 'package:regalos/features/sync/data/sync_transport_common.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';
import 'package:regalos/features/sync/application/sync_v2_engine.dart';
import 'package:regalos/features/sync/application/sync_controller.dart';
import 'package:regalos/features/web_device/application/web_sync_controller.dart';
import 'package:regalos/features/web_device/application/web_sync_engine.dart';
import 'package:regalos/features/web_device/data/web_family_store.dart';

import '../helpers/fake_worker_v2.dart' show kSlotBodyBytesForTesting;
import '../sync/v2_harness.dart';
import 'web_engine_support.dart';

FamilyDoc edit(FamilyDoc doc, String person, {String id = 'gift'}) => doc.set(
  HlcClock(node: 'web-edit', last: doc.maxStamp),
  Collections.gifts,
  id,
  {'recipientId': person, 'title': 'Libro'},
);

// Vault futures created during setup belong to the outer zone. Fake timers
// still control all engine deadlines, while microtasks run in their real zones.
class _FakeTimerClock {
  _FakeTimerClock(this.time, this.outer);
  final FakeAsync time;
  final Zone outer;
  DateTime now() => DateTime.utc(2026).add(time.elapsed);
  Future<void> elapse(Duration duration) async {
    time.elapse(duration);
    await outer.run(() => Future<void>.delayed(Duration.zero));
    time.elapse(Duration.zero);
    await outer.run(() => Future<void>.delayed(Duration.zero));
  }

  int get nonPeriodicTimerCount => time.nonPeriodicTimerCount;
  int get periodicTimerCount => time.periodicTimerCount;
}

Future<void> _withFakeTimers(Future<void> Function(_FakeTimerClock) body) {
  final outer = Zone.current;
  return fakeAsync(
    (time) => runZoned(
      () => body(_FakeTimerClock(time, outer)),
      zoneSpecification: ZoneSpecification(
        scheduleMicrotask: (self, parent, zone, callback) {
          outer.scheduleMicrotask(zone.bindCallback(callback));
        },
      ),
    ),
  );
}

void main() {
  late WebHarness h;
  late SyncResponse snapshot;
  setUp(() async {
    h = WebHarness();
    await h.setup();
    snapshot = await h.worker.send(
      'GET',
      h.client.base.resolve('/v2/lists/$kV2Sync'),
      headers: {
        'Authorization': 'Bearer ${encodeBase64Url(h.engine.auth.credential)}',
      },
    );
  });
  tearDown(() => h.close());

  test('a live socket gets only one backup read per 60 idle seconds', () async {
    await _withFakeTimers((time) async {
      final notices = StreamController<SyncEvent>();
      var reads = 0;
      final engine = WebSyncEngine(
        transport: SyncV2Client(
          base: h.client.base,
          sendRequest: (method, uri, {body, headers = const {}}) {
            if (method == 'GET' && uri.path == '/v2/lists/$kV2Sync') reads++;
            return Future.value(snapshot);
          },
          openSocket: (_, _) => notices.stream,
        ),
        vault: h.vault,
        queue: h.queue,
        commonV2Ready: false,
        now: time.now,
      );
      engine.start();
      await time.elapse(Duration.zero);
      notices.add(const SyncOpenEvent());
      await time.elapse(Duration.zero);
      final initial = reads;
      expect(initial, greaterThan(0));
      await time.elapse(const Duration(seconds: 30));
      notices.add(const SyncAliveEvent());
      await time.elapse(const Duration(seconds: 29));
      expect(reads, initial);
      await time.elapse(const Duration(seconds: 1));
      expect(reads, initial + 1);
      await time.elapse(const Duration(seconds: 60));
      expect(reads, initial + 2);
      engine.stop();
      notices.close();
      await time.elapse(const Duration(minutes: 5));
      expect(reads, initial + 2);
      expect(time.nonPeriodicTimerCount + time.periodicTimerCount, 0);
    });
  });

  test(
    'backup never queues behind a slow sync and stops with the session',
    () async {
      await _withFakeTimers((time) async {
        final notices = StreamController<SyncEvent>();
        final release = Completer<void>();
        var hold = false;
        var reads = 0;
        final engine = WebSyncEngine(
          transport: SyncV2Client(
            base: h.client.base,
            sendRequest: (method, uri, {body, headers = const {}}) async {
              if (method == 'GET' && uri.path == '/v2/lists/$kV2Sync') {
                reads++;
                if (hold) await release.future;
              }
              return Future.value(snapshot);
            },
            openSocket: (_, _) => notices.stream,
          ),
          vault: h.vault,
          queue: h.queue,
          commonV2Ready: false,
          now: time.now,
        );
        engine.start();
        await time.elapse(Duration.zero);
        final initial = reads;
        await time.elapse(const Duration(seconds: 59));
        hold = true;
        engine.sync();
        await time.elapse(Duration.zero);
        expect(reads, initial + 1);
        await time.elapse(const Duration(minutes: 3));
        expect(reads, initial + 1);
        hold = false;
        release.complete();
        await time.elapse(Duration.zero);
        await time.elapse(const Duration(seconds: 59));
        expect(reads, initial + 1);
        await time.elapse(const Duration(seconds: 1));
        expect(reads, initial + 2);
        engine.stop();
        notices.close();
        await time.elapse(const Duration(minutes: 3));
        expect(reads, initial + 2);
        expect(time.nonPeriodicTimerCount + time.periodicTimerCount, 0);
      });
    },
  );

  test('hidden tab performs no backup, socket-event or retry GET', () async {
    await _withFakeTimers((time) async {
      var visible = true;
      var reads = 0;
      var fail = false;
      final notices = StreamController<SyncEvent>();
      final engine = WebSyncEngine(
        transport: SyncV2Client(
          base: h.client.base,
          sendRequest: (method, uri, {body, headers = const {}}) {
            if (method == 'GET') reads++;
            if (fail) {
              throw const SyncTransportException(
                SyncFailure.network,
                'offline',
              );
            }
            return Future.value(snapshot);
          },
          openSocket: (_, _) => notices.stream,
        ),
        vault: h.vault,
        queue: h.queue,
        commonV2Ready: false,
        now: time.now,
        isVisible: () => visible,
      );
      engine.start();
      await time.elapse(Duration.zero);
      final initial = reads;
      visible = false;
      notices.add(const SyncOpenEvent());
      notices.add(const SyncVersionEvent(999));
      await time.elapse(const Duration(minutes: 3));
      expect(reads, initial);
      visible = true;
      fail = true;
      engine.requestSync();
      await time.elapse(Duration.zero);
      expect(reads, initial + 1);
      visible = false;
      await time.elapse(const Duration(minutes: 3));
      expect(reads, initial + 1);
      engine.stop();
      notices.close();
      await time.elapse(Duration.zero);
      expect(time.nonPeriodicTimerCount + time.periodicTimerCount, 0);
    });
  });

  for (final failure in [SyncFailure.network, SyncFailure.rateLimited]) {
    test('direct sync retries $failure and restores the idle backup', () async {
      await _withFakeTimers((time) async {
        final notices = StreamController<SyncEvent>();
        var reads = 0;
        var fail = false;
        final engine = WebSyncEngine(
          transport: SyncV2Client(
            base: h.client.base,
            sendRequest: (method, uri, {body, headers = const {}}) async {
              reads++;
              if (fail) {
                throw SyncTransportException(
                  failure,
                  'offline',
                  retryAfter: failure == SyncFailure.rateLimited
                      ? const Duration(seconds: 90)
                      : null,
                );
              }
              return snapshot;
            },
            openSocket: (_, _) => notices.stream,
          ),
          vault: h.vault,
          queue: h.queue,
          commonV2Ready: false,
          now: time.now,
        );
        engine.start();
        await time.elapse(Duration.zero);
        expect(reads, 1);
        fail = true;
        Object? error;
        engine.sync().catchError((Object e) {
          error = e;
        });
        await time.elapse(Duration.zero);
        expect(error, isA<SyncTransportException>());
        expect(reads, 2);
        final delay = failure == SyncFailure.rateLimited ? 90 : 5;
        await time.elapse(Duration(seconds: delay - 1));
        expect(reads, 2);
        await time.elapse(const Duration(seconds: 1));
        expect(reads, 3);
        // The automatic retry consumes the next backoff step only once.
        fail = false;
        final nextDelay = failure == SyncFailure.rateLimited ? 90 : 15;
        await time.elapse(Duration(seconds: nextDelay - 1));
        expect(reads, 3);
        await time.elapse(const Duration(seconds: 1));
        expect(reads, 4);
        await time.elapse(const Duration(seconds: 59));
        expect(reads, 4);
        await time.elapse(const Duration(seconds: 1));
        expect(reads, 5);
        engine.stop();
        notices.close();
        await time.elapse(const Duration(minutes: 5));
        expect(reads, 5);
        expect(time.nonPeriodicTimerCount + time.periodicTimerCount, 0);
      });
    });
  }

  test(
    'hidden tab skips a GET queued while visible and resumes once',
    () async {
      await _withFakeTimers((time) async {
        var visible = true;
        var reads = 0;
        var hold = false;
        final release = Completer<void>();
        final sockets = <StreamController<SyncEvent>>[];
        final engine = WebSyncEngine(
          transport: SyncV2Client(
            base: h.client.base,
            sendRequest: (method, uri, {body, headers = const {}}) async {
              reads++;
              if (hold) await release.future;
              return snapshot;
            },
            openSocket: (_, _) {
              final socket = StreamController<SyncEvent>();
              sockets.add(socket);
              return socket.stream;
            },
          ),
          vault: h.vault,
          queue: h.queue,
          commonV2Ready: false,
          now: time.now,
          isVisible: () => visible,
        );
        engine.start();
        await time.elapse(Duration.zero);
        expect(reads, 1);
        hold = true;
        engine.sync();
        await time.elapse(Duration.zero);
        expect(reads, 2);
        engine.requestSync(); // Waits in _serial behind the held response.
        await time.elapse(Duration.zero);
        visible = false;
        engine.suspend();
        expect(sockets.single.hasListener, isFalse);
        hold = false;
        release.complete();
        await time.elapse(const Duration(minutes: 4));
        engine.sync();
        engine.requestSync();
        await time.elapse(Duration.zero);
        expect(reads, 2);
        expect(sockets, hasLength(1));
        visible = true;
        engine.resume();
        await time.elapse(Duration.zero);
        expect(sockets, hasLength(2));
        expect(reads, 3);
        sockets.last.add(const SyncOpenEvent());
        await time.elapse(Duration.zero);
        expect(reads, 3);
        engine.stop();
        for (final socket in sockets) {
          socket.close();
        }
        await time.elapse(const Duration(minutes: 5));
        expect(time.nonPeriodicTimerCount + time.periodicTimerCount, 0);
      });
    },
  );

  test(
    'Retry-After survives queued reads, hide/show and socket versions',
    () async {
      await _withFakeTimers((time) async {
        var visible = true;
        var reads = 0;
        var limited = false;
        final release = Completer<void>();
        final sockets = <StreamController<SyncEvent>>[];
        final errors = <Object>[];
        final engine = WebSyncEngine(
          transport: SyncV2Client(
            base: h.client.base,
            sendRequest: (method, uri, {body, headers = const {}}) async {
              reads++;
              if (limited) {
                limited = false;
                await release.future;
                return SyncResponse(429, {'retry-after': '90'}, Uint8List(0));
              }
              return snapshot;
            },
            openSocket: (_, _) {
              final socket = StreamController<SyncEvent>();
              sockets.add(socket);
              return socket.stream;
            },
          ),
          vault: h.vault,
          queue: h.queue,
          commonV2Ready: false,
          now: time.now,
          isVisible: () => visible,
          onError: errors.add,
        );
        engine.start();
        await time.elapse(Duration.zero);
        expect(reads, 1);
        limited = true;
        engine.requestSync();
        await time.elapse(Duration.zero);
        expect(reads, 2);
        engine.requestSync(); // Already queued when the first GET fails.
        await time.elapse(Duration.zero);
        release.complete();
        await time.elapse(Duration.zero);
        expect(errors, hasLength(1));
        expect(errors.single, isA<SyncTransportException>());
        expect(reads, 2);

        visible = false;
        engine.suspend();
        await time.elapse(const Duration(seconds: 1));
        visible = true;
        engine.resume();
        await time.elapse(Duration.zero);
        sockets.last.add(const SyncOpenEvent());
        sockets.last.add(const SyncVersionEvent(999));
        engine.sync();
        engine.requestSync();
        await time.elapse(Duration.zero);
        expect(reads, 2);
        expect(time.nonPeriodicTimerCount, 1);
        await time.elapse(const Duration(seconds: 60));
        expect(reads, 2);
        sockets.last.add(const SyncVersionEvent(999));
        await time.elapse(const Duration(seconds: 28));
        expect(reads, 2);
        expect(time.nonPeriodicTimerCount, 1);
        await time.elapse(const Duration(seconds: 1));
        expect(reads, 3); // A single GET at the original 90-second deadline.
        await time.elapse(Duration.zero);
        expect(reads, 3);
        engine.requestSync(); // Success cleared the deadline.
        await time.elapse(Duration.zero);
        expect(reads, 4);
        engine.stop();
        for (final socket in sockets) {
          socket.close();
        }
        await time.elapse(const Duration(minutes: 5));
        expect(reads, 4);
        expect(time.nonPeriodicTimerCount + time.periodicTimerCount, 0);
      });
    },
  );

  test('errors back off and respect Retry-After for every request', () async {
    await _withFakeTimers((time) async {
      var reads = 0;
      var failure = SyncFailure.network;
      var fail = false;
      final notices = StreamController<SyncEvent>();
      final engine = WebSyncEngine(
        transport: SyncV2Client(
          base: h.client.base,
          sendRequest: (method, uri, {body, headers = const {}}) {
            if (method == 'GET') reads++;
            if (fail) {
              throw SyncTransportException(
                failure,
                'offline',
                retryAfter: failure == SyncFailure.rateLimited
                    ? const Duration(seconds: 90)
                    : null,
              );
            }
            return Future.value(snapshot);
          },
          openSocket: (_, _) => notices.stream,
        ),
        vault: h.vault,
        queue: h.queue,
        commonV2Ready: false,
        now: time.now,
      );
      engine.start();
      await time.elapse(Duration.zero);
      final initial = reads;
      fail = true;
      await time.elapse(const Duration(seconds: 60));
      expect(reads, initial + 1);
      await time.elapse(const Duration(seconds: 4));
      expect(reads, initial + 1);
      await time.elapse(const Duration(seconds: 1));
      expect(reads, initial + 2);
      await time.elapse(const Duration(seconds: 14));
      expect(reads, initial + 2);
      await time.elapse(const Duration(seconds: 1));
      expect(reads, initial + 3);
      fail = false;
      engine.requestSync();
      await time.elapse(Duration.zero);
      expect(reads, initial + 3);
      await time.elapse(const Duration(seconds: 44));
      expect(reads, initial + 3);
      await time.elapse(const Duration(seconds: 1));
      expect(reads, initial + 4);
      await time.elapse(const Duration(seconds: 59));
      expect(reads, initial + 4);
      fail = true;
      failure = SyncFailure.rateLimited;
      await time.elapse(const Duration(seconds: 1));
      expect(reads, initial + 5);
      await time.elapse(const Duration(seconds: 89));
      expect(reads, initial + 5);
      await time.elapse(const Duration(seconds: 1));
      expect(reads, initial + 6);
      engine.stop();
      notices.close();
      await time.elapse(const Duration(minutes: 5));
      expect(reads, initial + 6);
      expect(time.nonPeriodicTimerCount + time.periodicTimerCount, 0);
    });
  });

  test('a version received during an older GET queues another read', () async {
    final notices = StreamController<SyncEvent>();
    final arrived = Completer<void>();
    final release = Completer<void>();
    final changed = Completer<void>();
    var hold = false;
    late final WebSyncEngine engine;
    engine = WebSyncEngine(
      transport: SyncV2Client(
        base: h.client.base,
        sendRequest: (method, uri, {body, headers = const {}}) async {
          final response = await h.worker.send(
            method,
            uri,
            body: body,
            headers: headers,
          );
          if (hold && method == 'GET' && uri.path == '/v2/lists/$kV2Sync') {
            hold = false;
            arrived.complete();
            await release.future;
          }
          return response;
        },
        openSocket: (_, _) => notices.stream,
      ),
      vault: h.vault,
      queue: h.queue,
      commonV2Ready: false,
      refreshInterval: const Duration(hours: 1),
      onChanged: () {
        if (!changed.isCompleted &&
            engine.candidate?.record(Collections.gifts, 'gift')?['title'] ==
                'Libro') {
          changed.complete();
        }
      },
    );
    addTearDown(() async {
      engine.stop();
      await notices.close();
    });
    await engine.start();
    hold = true;
    final reading = engine.requestSync();
    await arrived.future;
    h.phone.doc = h.phone.doc.set(h.phone.clock, Collections.gifts, 'gift', {
      'title': 'Libro',
    });
    await SyncV2Engine(transport: h.client, local: h.phone).sync();
    notices.add(SyncVersionEvent(h.worker.versionOf(kV2Sync)!));
    await Future<void>.delayed(Duration.zero);
    release.complete();
    await reading;
    await changed.future.timeout(const Duration(seconds: 2));
    expect(engine.version, h.worker.versionOf(kV2Sync));
  });
  test('web startup and recovery providers never access mobile stores or transports', () async {
    final c = ProviderContainer(
      overrides: [
        familyStoreProvider.overrideWithValue(
          WebFamilyStore(h.vault, h.engine),
        ),
        secretStoreProvider.overrideWith(
          (ref) => throw StateError('mobile secrets'),
        ),
        fileStoreProvider.overrideWith(
          (ref) => throw StateError('mobile files'),
        ),
        syncTransportProvider.overrideWith(
          (ref) => throw StateError('mobile transport'),
        ),
        syncV2TransportProvider.overrideWith(
          (ref) => throw StateError('mobile v2 transport'),
        ),
      ],
    );
    addTearDown(c.dispose);
    expect((await c.read(familyControllerProvider.future)).hasFamily, isTrue);
    expect(c.read(recoveryTransportProvider), isNull);
    expect(c.read(recoveryReaderProvider), isNull);
    expect(c.read(recoveryControllerProvider), isNull);
    final probe = FutureProvider<void>((ref) async {
      await resumeRecoveryBeforeFamily(ref);
      expect(await recoveryMaintenanceWithinLock(ref), isNull);
    });
    await c.read(probe.future);
    final recovery = c.read(recoveryApplicationProvider.notifier);
    await recovery.refresh();
    expect(await recovery.takeCreatedCode(), isNull);
    for (final action in [
      recovery.createCode,
      recovery.rotateCode,
      recovery.retireCode,
      recovery.abandon,
      recovery.retry,
    ]) {
      await expectLater(
        action(),
        throwsA(
          isA<RecoveryApplicationException>().having(
            (e) => e.code,
            'code',
            'not_configured',
          ),
        ),
      );
    }
    expect(c.read(recoveryStatusProvider).readiness, RecoveryReadiness.absent);
    h.vault.lock();
    await expectLater(
      c.read(familyStoreProvider).assertWritable(),
      throwsStateError,
    );
  });

  test('unverifiable registry preserves pinned roots and local history for a later good snapshot', () async {
    final roots = jsonEncode(h.vault.opened.data['roots']);
    final local = jsonEncode(h.vault.opened.data['registryLocal']);
    final bad = Map<String, Object?>.from(h.phone.reg.toJson())
      ..['l'] = 'BBBBBBBBBBBBBBBBBBBBBB';
    await h.publish(registry: bad);
    await h.engine.sync();
    expect(h.engine.status, WebSyncStatus.pending);
    expect(jsonEncode(h.vault.opened.data['roots']), roots);
    expect(jsonEncode(h.vault.opened.data['registryLocal']), local);
    await h.publish();
    await h.engine.sync();
    expect(h.engine.status, WebSyncStatus.confirmed);
    expect(h.engine.hasRoots, isTrue);
  });

  test('UI receives the candidate when its whole action is set aside; mobile actions throw', () async {
    await h.publish(
      doc: h.phone.doc.set(h.phone.clock, Collections.policies, 'nora', {
        'hideOwnGifts': false,
      }),
    );
    await h.engine.sync();
    final store = WebFamilyStore(h.vault, h.engine);
    final c = ProviderContainer(
      overrides: [
        familyStoreProvider.overrideWithValue(store),
        syncControllerProvider.overrideWith(() => WebSyncController(h.engine)),
      ],
    );
    addTearDown(c.dispose);
    await c.read(familyControllerProvider.future);
    await c
        .read(familyControllerProvider.notifier)
        .upsertGift(
          const Gift(
            id: 'gift',
            recipientId: 'nora',
            title: 'Libro',
            status: GiftStatus.idea,
            rawStatus: 'idea',
            surprise: false,
            year: 2026,
          ),
        );
    expect(
      c
          .read(familyControllerProvider)
          .value!
          .doc
          .record(Collections.gifts, 'gift')!['title'],
      'Bufanda',
    );
    expect((await h.queue.entries()).single.setAside, isTrue);
    final reopenedStore = WebFamilyStore(h.vault, h.engine);
    final stored = (await reopenedStore.load())!;
    expect(
      reopenedStore.latestStoredStamp(stored.doc),
      (await h.queue.entries()).single.delta.maxStamp,
    );
    final sync = c.read(syncControllerProvider.notifier);
    await expectLater(
      sync.leaveFamily(),
      throwsA(isA<WebOperationException>()),
    );
    await expectLater(
      sync.removeDevice('aritz-phone'),
      throwsA(isA<WebOperationException>()),
    );
    await expectLater(
      sync.readyCredentials(),
      throwsA(isA<WebOperationException>()),
    );
  });

  test('original recipient remains checked after a remote move removed it from the gift', () async {
    final before = h.engine.candidate!;
    await h.engine.save(
      before,
      before.setChanged(
        HlcClock(node: 'web', last: before.maxStamp),
        Collections.gifts,
        'gift',
        {'title': 'Libro'},
      ),
    );
    var remote = h.phone.doc.set(h.phone.clock, Collections.gifts, 'gift', {
      'recipientId': 'leo',
    });
    remote = remote.set(h.phone.clock, Collections.policies, 'nora', {
      'hideOwnGifts': false,
    });
    await h.publish(doc: remote);
    await h.engine.sync();
    expect((await h.queue.entries()).single.setAside, isTrue);
    expect(h.worker.calls['PUT common'], isNull);
  });

  test('slots disappearing never remove a durable blocked mark, even after reopening', () async {
    final out = BytesBuilder()
      ..add([0x47, 0x48, 0x53, 0x02])
      ..add(List.filled(29, 0));
    for (final id in [kV2List, 'nora', 'aritz-phone']) {
      out
        ..addByte(id.length)
        ..add(ascii.encode(id));
    }
    out.add(List.filled(kSlotBodyBytesForTesting, 0));
    await h.publish(
      slots: [
        V2SlotChange(
          personId: 'nora',
          deviceId: 'aritz-phone',
          data: out.takeBytes(),
        ),
      ],
    );
    await h.engine.sync();
    expect(await h.queue.blockedPeople(), contains('nora'));
    await h.publish(
      slots: [
        const V2SlotChange(
          personId: 'nora',
          deviceId: 'aritz-phone',
          data: null,
        ),
      ],
    );
    await h.engine.sync();
    final before = h.engine.candidate!;
    await h.engine.save(before, edit(before, 'nora'));
    await h.engine.sync();
    expect((await h.queue.entries()).single.setAside, isTrue);
    expect(h.worker.calls['PUT common'], isNull);
    expect(h.worker.slotVersions(kV2Sync), isEmpty);
    h.vault.lock();
    await h.vault.unlock('123456');
    expect(await h.queue.blockedPeople(), contains('nora'));
  });

  test(
    'revoked first root switches to an already pinned active mobile',
    () async {
      final keys = await DeviceKeys.generate();
      final b = await DeviceRecord.create(
        keys: keys,
        listId: kV2List,
        deviceId: 'nora-phone',
        personId: 'nora',
      );
      final a = h.phone.record;
      final w = h.phone.reg.records.firstWhere((r) => r.kind == DeviceKind.web);
      var registry = await h.phone.reg.withDeclarations(
        records: [b],
        vouches: [
          await Vouch.create(keys: h.phone.keys, voucher: a, record: b),
          await Vouch.create(keys: keys, voucher: b, record: a),
          await Vouch.create(keys: keys, voucher: b, record: w),
        ],
        anchor: (await h.phone.view()).anchor,
      );
      await h.publish(registry: registry.toJson());
      await h.engine.sync();
      expect((h.vault.opened.data['roots'] as List).length, 2);
      final revocation = await Revocation.create(
        keys: keys,
        by: b,
        deviceId: a.deviceId,
      );
      registry = await registry.withRevocation(
        revocation,
        anchor: RegistryAnchor(
          deviceId: b.deviceId,
          signingKey: keys.publicKeys.signing,
        ),
      );
      await h.publish(registry: registry.toJson());
      await h.engine.sync();
      expect(h.engine.status, WebSyncStatus.confirmed);
      expect(h.engine.view!.me, 'nora-phone');
      expect(
        (h.vault.opened.data['roots'] as List).single['deviceId'],
        'nora-phone',
      );
    },
  );

  test('new signed web record without a mobile vouch is pending and does not upload', () async {
    final original = h.engine.candidate!;
    await h.engine.save(original, edit(original, 'nora'));
    final record = await DeviceRecord.create(
      keys: h.guest.keys,
      listId: kV2List,
      deviceId: h.guest.joined!.identity.deviceId,
      personId: 'leo',
      seq: 2,
      kind: DeviceKind.web,
    );
    final reg = await h.phone.reg.withRecord(
      record,
      anchor: (await h.phone.view()).anchor,
    );
    await h.publish(registry: reg.toJson());
    await h.engine.sync();
    expect(h.engine.status, WebSyncStatus.pending);
    expect(h.worker.calls['PUT common'], isNull);
    expect(await h.queue.entries(), hasLength(1));
  });

  test(
    'applies only a valid family key package directed to this web',
    () async {
      final nextKey = await FamilyKey.generate();
      final bundle = await KeyBundle.sealFamilyKey(
        sender: h.phone.keys,
        view: await h.phone.view(),
        toDevice: h.guest.joined!.identity.deviceId,
        epoch: (await h.phone.view()).epoch,
        familyKey: nextKey,
      );
      final bytes = await seal(
        doc: h.phone.doc.toJson(),
        listId: kV2List,
        fromNode: 'aritz-phone',
        at: '2026-11-13T12:00:00Z',
        key: nextKey,
      );
      await h.client.putList(
        h.phone.auth,
        version: h.worker.versionOf(kV2Sync)!,
        body: V2SnapshotUpload(
          common: bytes,
          registry: h.phone.reg.toJson(),
          keyPackages: [bundle.toJson()],
        ),
      );
      await h.engine.sync();
      expect(h.vault.opened.data['familyKey'], nextKey.toBase64Url());
      expect(h.engine.candidate!.canonicalJson(), h.phone.doc.canonicalJson());
    },
  );

  test('only PUT common; no registry, packages or slots; remote snapshot and real ack', () async {
    final reg = jsonEncode(h.worker.registryOf(kV2Sync));
    final puts = h.worker.calls['PUT list'];
    final before = h.engine.candidate!;
    await h.engine.save(before, edit(before, 'nora'));
    expect(await h.queue.entries(), hasLength(1));
    expect((h.vault.opened.data['snapshot'] as Map)['common'], isNotNull);
    expect(
      (await h.remote()).record(Collections.gifts, 'gift')!['title'],
      'Bufanda',
    );
    await h.engine.sync();
    expect(
      (await h.remote()).record(Collections.gifts, 'gift')!['title'],
      'Libro',
    );
    expect(await h.queue.entries(), isEmpty);
    expect(h.worker.calls['PUT list'], puts);
    expect(h.worker.calls['PUT common'], 1);
    expect(jsonEncode(h.worker.registryOf(kV2Sync)), reg);
    expect(h.worker.slotVersions(kV2Sync), isEmpty);
  });

  for (final tombstone in [false, true]) {
    test(
      'policy false or tombstone blocks an entire action ($tombstone)',
      () async {
        var doc = h.phone.doc.set(h.phone.clock, Collections.policies, 'nora', {
          'hideOwnGifts': false,
        });
        if (tombstone) {
          doc = doc.delete(h.phone.clock, Collections.policies, 'nora');
        }
        await h.publish(doc: doc);
        await h.engine.sync();
        final before = h.engine.candidate!;
        var next = edit(before, 'nora');
        next = next.set(
          HlcClock(node: 'web-edit', last: next.maxStamp),
          Collections.occasions,
          'occasion',
          {'name': 'Invierno'},
        );
        await h.engine.save(before, next);
        await h.engine.sync();
        final entries = await h.queue.entries();
        expect(entries.single.setAside, isTrue);
        expect(
          h.engine.candidate!.record(Collections.occasions, 'occasion'),
          isNull,
        );
        expect(h.worker.calls['PUT common'], isNull);
        expect(await h.queue.blockedPeople(), contains('nora'));
      },
    );
  }

  test('moving an existing gift to a blocked person and editing away from one are apart', () async {
    await h.publish(
      doc: h.phone.doc.set(h.phone.clock, Collections.policies, 'leo', {
        'hideOwnGifts': false,
      }),
    );
    await h.engine.sync();
    final before = h.engine.candidate!;
    await h.engine.save(before, edit(before, 'leo'));
    expect((await h.queue.entries()).single.setAside, isTrue);
    // Now the old person is blocked; moving out must not launder its contents.
    await h.publish(
      doc: h.phone.doc.set(h.phone.clock, Collections.policies, 'nora', {
        'hideOwnGifts': false,
      }),
    );
    await h.engine.sync();
    await h.engine.save(
      h.engine.candidate!,
      edit(h.engine.candidate!, 'aritz'),
    );
    expect((await h.queue.entries()).every((e) => e.setAside), isTrue);
    expect(
      h.engine.candidate!.record(Collections.gifts, 'gift')!['recipientId'],
      'nora',
    );
  });

  test(
    '412 with a new protection reconstructs without the whole pending action',
    () async {
      final before = h.engine.candidate!;
      await h.engine.save(before, edit(before, 'nora'));
      h.worker.beforePut = (_) async {
        await h.publish(
          doc: h.phone.doc.set(h.phone.clock, Collections.policies, 'nora', {
            'hideOwnGifts': false,
          }),
        );
      };
      await h.engine.sync();
      expect((await h.queue.entries()).single.setAside, isTrue);
      expect(
        h.worker.calls['PUT common'],
        1,
        reason: 'only the stale attempt, never a retry with gift',
      );
      expect(
        (await h.remote()).record(Collections.gifts, 'gift')!['title'],
        'Bufanda',
      );
    },
  );

  test('no roots is pending and cannot publish', () async {
    await h.vault.saveData({...h.vault.opened.data, 'roots': <Object?>[]});
    final before = h.engine.candidate!;
    await h.engine.save(before, edit(before, 'nora'));
    await h.engine.sync();
    expect(h.engine.status, WebSyncStatus.pending);
    expect(h.worker.calls['PUT common'], isNull);
    expect(await h.queue.entries(), hasLength(1));
  });

  test('registry revocation disconnects without deleting encrypted pending changes', () async {
    final before = h.engine.candidate!;
    await h.engine.save(before, edit(before, 'nora'));
    final change = await revokeDevice(
      registry: h.phone.reg,
      view: await h.phone.view(),
      myKeys: h.phone.keys,
      deviceId: h.guest.joined!.identity.deviceId,
    );
    await h.publish(registry: change.registry.toJson());
    await h.engine.sync();
    expect(h.engine.status, WebSyncStatus.disconnected);
    expect((await h.store.read()).current!.entries, hasLength(1));
    expect(h.worker.calls['PUT common'], isNull);
  });

  test('socket 4401 disconnects; callbacks after stop never publish', () async {
    await h.engine.start();
    final before = h.engine.candidate!;
    await h.engine.save(before, edit(before, 'nora'));
    await h.client.revoke(h.phone.auth, h.guest.joined!.identity.deviceId);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(h.engine.status, WebSyncStatus.disconnected);
    expect((await h.store.read()).current!.entries, hasLength(1));
  });

  test(
    'network cut after PUT retains delta until a real confirmed receipt',
    () async {
      final before = h.engine.candidate!;
      await h.engine.save(before, edit(before, 'nora'));
      h.worker.tamper = (method, uri, response) {
        if (method == 'PUT' && uri.path.endsWith('/common')) {
          throw StateError('cut after write');
        }
        return response;
      };
      await expectLater(h.engine.sync(), throwsStateError);
      expect(await h.queue.entries(), hasLength(1));
      h.worker.tamper = null;
      await h.engine.sync();
      expect(await h.queue.entries(), isEmpty);
    },
  );

  group('activity (status line hint)', () {
    test('idle when nothing waits; uploading while admitted entries are '
        'unconfirmed; idle again once acked', () async {
      expect(h.engine.activity, WebSyncActivity.idle);
      final before = h.engine.candidate!;
      await h.engine.save(before, edit(before, 'nora'));
      expect(h.engine.activity, WebSyncActivity.uploading);
      h.worker.tamper = (method, uri, response) {
        if (method == 'PUT' && uri.path.endsWith('/common')) {
          throw StateError('cut after write');
        }
        return response;
      };
      await expectLater(h.engine.sync(), throwsStateError);
      expect(h.engine.activity, WebSyncActivity.uploading);
      h.worker.tamper = null;
      await h.engine.sync();
      expect(h.engine.activity, WebSyncActivity.idle);
    });

    test('a network failure reads offline and clears on the next success; '
        'onChanged fires on each change', () async {
      var changes = 0;
      var instant = DateTime.utc(2026);
      final engine = WebSyncEngine(
        transport: h.client,
        vault: h.vault,
        queue: h.queue,
        onChanged: () => changes++,
        now: () => instant,
      );
      addTearDown(engine.stop);
      h.worker.offline = true;
      await engine.requestSync();
      expect(engine.activity, WebSyncActivity.offline);
      expect(changes, 1);
      h.worker.offline = false;
      instant = instant.add(const Duration(seconds: 5));
      await engine.requestSync();
      expect(engine.activity, WebSyncActivity.idle);
      expect(changes, greaterThanOrEqualTo(2));
    });

    test('a revoked list is disconnected, never offline', () async {
      await h.client.revoke(h.phone.auth, h.guest.joined!.identity.deviceId);
      await h.engine.sync().catchError((Object _) {});
      expect(h.engine.status, WebSyncStatus.disconnected);
      expect(h.engine.activity, isNot(WebSyncActivity.offline));
    });
  });

  test(
    'cancellation during encryption/network cannot publish or ack late',
    () async {
      final before = h.engine.candidate!;
      await h.engine.save(before, edit(before, 'nora'));
      final arrived = Completer<void>(), release = Completer<void>();
      h.worker.beforePut = (_) async {
        arrived.complete();
        await release.future;
      };
      final sync = h.engine.sync();
      await arrived.future;
      h.engine.stop();
      h.vault.lock();
      release.complete();
      await expectLater(sync, throwsStateError);
      expect((await h.store.read()).current!.entries, hasLength(1));
    },
  );

  test('FamilyController deletion indirects become one delta and UI sees candidate', () async {
    final doc = h.phone.doc
        .set(h.phone.clock, Collections.occasions, 'winter', {
          'name': 'Invierno',
        })
        .set(h.phone.clock, Collections.gifts, 'gift', {
          'occasionId': 'winter',
        });
    await h.publish(doc: doc);
    await h.engine.sync();
    final store = WebFamilyStore(h.vault, h.engine);
    final container = ProviderContainer(
      overrides: [familyStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    await container.read(familyControllerProvider.future);
    await container
        .read(familyControllerProvider.notifier)
        .deleteOccasion('winter');
    final entries = await h.queue.entries();
    expect(entries, hasLength(1));
    expect(
      entries.single.delta.record(Collections.occasions, 'winter')!.isDeleted,
      isTrue,
    );
    expect(
      entries.single.delta.record(Collections.gifts, 'gift')!.fields.keys,
      ['occasionId'],
    );
    expect(
      entries.single.delta.record(Collections.gifts, 'gift')!['occasionId'],
      isNull,
    );
    await expectLater(
      store.saveSelfRecipient('nora'),
      throwsA(isA<WebOperationException>()),
    );
    await expectLater(store.clear(), throwsA(isA<WebOperationException>()));
    expect(
      () => container.read(familyControllerProvider.notifier).familyKey,
      throwsA(isA<WebOperationException>()),
    );
  });
}
