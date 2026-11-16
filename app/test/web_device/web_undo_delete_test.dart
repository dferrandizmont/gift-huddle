import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';
import 'package:regalos/features/web_device/application/web_sync_engine.dart';
import 'package:regalos/features/web_device/data/web_family_store.dart';

import 'web_engine_support.dart';

void main() {
  late WebHarness h;
  late DateTime time;
  late WebSyncEngine engine;
  ProviderContainer? container;
  Future<FamilyController> open({SyncV2Transport? transport}) async {
    engine = WebSyncEngine(
      transport: transport ?? h.client,
      vault: h.vault,
      queue: h.queue,
      now: () => time,
    );
    await engine.sync();
    container = ProviderContainer(
      overrides: [
        familyStoreProvider.overrideWithValue(WebFamilyStore(h.vault, engine)),
      ],
    );
    await container!.read(familyControllerProvider.future);
    return container!.read(familyControllerProvider.notifier);
  }

  void lock() {
    engine.stop();
    container?.dispose();
    container = null;
    h.vault.lock();
  }

  setUp(() async {
    h = WebHarness();
    await h.setup();
    h.engine.stop();
    await h.publish(
      doc: h.phone.doc.set(h.phone.clock, Collections.gifts, 'gift', {
        'surprise': false,
      }),
    );
    time = DateTime.utc(2026, 11, 13);
  });
  tearDown(() {
    engine.stop();
    container?.dispose();
    container = null;
    h.close();
  });
  test(
    'undo is durable during a GET lasting beyond the seven second window',
    () async {
      final arrived = Completer<void>(), release = Completer<void>();
      var delayGet = false;
      final transport = SyncV2Client(
        base: Uri.parse('https://sync.test'),
        sendRequest: (method, uri, {body, headers = const {}}) async {
          final response = await h.worker.send(
            method,
            uri,
            body: body,
            headers: headers,
          );
          if (delayGet &&
              method == 'GET' &&
              uri.path == '/v2/lists/${h.phone.auth.syncId}') {
            delayGet = false;
            arrived.complete();
            await release.future;
          }
          return response;
        },
      );
      final controller = await open(transport: transport);
      await controller.deleteGiftWithUndo('gift');
      delayGet = true;
      final sync = engine.sync();
      await arrived.future;
      time = time.add(const Duration(seconds: 2));
      final cancelled = Completer<void>();
      h.store.beforeWrite = () {
        if (!cancelled.isCompleted) cancelled.complete();
      };
      final undo = controller.undoDeleteGift('gift');
      try {
        // The ciphertext is removed while the GET is still waiting. An undo
        // serialized behind sync cannot reach this durable transaction.
        await cancelled.future.timeout(const Duration(seconds: 2));
        expect(await h.queue.entries(), isEmpty);
      } finally {
        h.store.beforeWrite = null;
        time = time.add(const Duration(seconds: 6));
        release.complete();
        await sync;
        expect(await undo, isTrue);
      }
      expect(h.worker.calls['PUT common'], isNull);
      expect(
        (await h.remote()).record(Collections.gifts, 'gift')!.isDeleted,
        isFalse,
      );
      lock();
      await h.vault.unlock('123456');
      await open();
      expect(await h.queue.entries(), isEmpty);
      expect(
        engine.candidate!.record(Collections.gifts, 'gift')!.isDeleted,
        isFalse,
      );
      expect(h.worker.calls['PUT common'], isNull);
    },
  );

  test('undo pressed behind an edit waiting on a slow GET is never outrun by expiry', () async {
    h.phone.addGift('b', 'nora', 'Libro');
    await h.publish();
    final arrived = Completer<void>(), release = Completer<void>();
    var delayGet = false;
    final transport = SyncV2Client(
      base: Uri.parse('https://sync.test'),
      sendRequest: (method, uri, {body, headers = const {}}) async {
        final response = await h.worker.send(
          method,
          uri,
          body: body,
          headers: headers,
        );
        if (delayGet &&
            method == 'GET' &&
            uri.path == '/v2/lists/${h.phone.auth.syncId}') {
          delayGet = false;
          arrived.complete();
          await release.future;
        }
        return response;
      },
    );
    final controller = await open(transport: transport);
    // Delete A, then a slow GET starts.
    expect(await controller.deleteGiftWithUndo('gift'), isTrue);
    delayGet = true;
    final sync = engine.sync();
    await arrived.future;
    // Edit B: it waits in the controller's queue behind the engine's GET.
    final edit = controller.setGiftStatus('b', GiftStatus.decided);
    time = time.add(const Duration(seconds: 2));
    final cancelled = Completer<void>();
    h.store.beforeWrite = () {
      if (!cancelled.isCompleted) cancelled.complete();
    };
    // Undo A within the window, queued after the edit of B.
    final undo = controller.undoDeleteGift('gift');
    try {
      await cancelled.future.timeout(const Duration(seconds: 2));
      expect(
        (await h.queue.entries()).where((e) => e.undoGiftId != null),
        isEmpty,
      );
    } finally {
      h.store.beforeWrite = null;
      // The window is over when the GET returns.
      time = time.add(const Duration(seconds: 6));
      release.complete();
      await sync;
    }
    expect(await edit, isTrue);
    expect(await undo, isTrue);
    await engine.sync();
    final remote = await h.remote();
    expect(remote.record(Collections.gifts, 'gift')!.isDeleted, isFalse);
    expect(remote.record(Collections.gifts, 'b')!['status'], 'decided');
    expect(await h.queue.entries(), isEmpty);
    final shown = container!.read(familyControllerProvider).requireValue.doc;
    expect(shown.record(Collections.gifts, 'gift')!.isDeleted, isFalse);
    expect(shown.record(Collections.gifts, 'b')!['status'], 'decided');
  });

  for (final cascade in ['recipient', 'requester', 'giver', 'occasion']) {
    for (final publishFirst in [false, true]) {
      test(
        '$cascade cascade includes an undoable gift after reopening (publish first: $publishFirst)',
        () async {
          await h.publish(
            doc: h.phone.doc
                .set(h.phone.clock, Collections.givers, 'giver', {
                  'name': 'Aritz',
                })
                .set(h.phone.clock, Collections.occasions, 'winter', {
                  'name': 'Invierno',
                })
                .set(h.phone.clock, Collections.gifts, 'gift', {
                  'giverId': 'giver',
                  'occasionId': 'winter',
                  'requestedBy': const RequestedByRecipient('aritz').toFields(),
                }),
          );
          var controller = await open();
          await controller.deleteGiftWithUndo('gift');
          // Also exercise restoration of durable intentions across sessions.
          lock();
          await h.vault.unlock('123456');
          controller = await open();
          // Sync may replace the snapshot before the controller reloads it.
          // Cascades must stamp their indirect changes after that live input.
          final remoteClock = HlcClock(
            node: 'phone',
            last: Hlc(
              millis: DateTime.now().millisecondsSinceEpoch + 1000,
              counter: 0,
              node: 'phone',
            ),
          );
          await h.publish(
            doc: h.phone.doc.set(remoteClock, Collections.gifts, 'gift', {
              'giverId': 'giver',
            }),
          );
          await engine.sync();
          switch (cascade) {
            case 'recipient':
              await controller.deleteRecipient('nora');
            case 'requester':
              await controller.deleteRecipient('aritz');
            case 'giver':
              await controller.deleteGiver('giver');
            case 'occasion':
              await controller.deleteOccasion('winter');
          }
          final entries = await h.queue.entries();
          expect(entries, hasLength(2));
          final action = entries.singleWhere(
            (entry) => entry.undoGiftId == null,
          );
          final giftDelta = action.delta.record(Collections.gifts, 'gift')!;
          if (cascade == 'recipient') {
            expect(giftDelta.isDeleted, isTrue);
          } else {
            final field = switch (cascade) {
              'requester' => 'requestedBy',
              'giver' => 'giverId',
              _ => 'occasionId',
            };
            expect(giftDelta.fields.keys, [field]);
            expect(giftDelta[field], isNull);
          }
          // Publish the cascade while the gift's independent intent still waits.
          if (publishFirst) await engine.sync();
          expect(await controller.undoDeleteGift('gift'), isTrue);
          await engine.sync();
          final remote = await h.remote();
          final gift = remote.record(Collections.gifts, 'gift')!;
          if (cascade == 'recipient') {
            expect(
              remote.record(Collections.recipients, 'nora')!.isDeleted,
              isTrue,
            );
            expect(gift.isDeleted, isTrue);
            expect(gift.hasTombstoneContent, isFalse);
          } else {
            expect(gift.isDeleted, isFalse);
            expect(gift['title'], 'Bufanda');
            expect(
              gift[switch (cascade) {
                'requester' => 'requestedBy',
                'giver' => 'giverId',
                _ => 'occasionId',
              }],
              isNull,
            );
          }
          expect(await h.queue.entries(), isEmpty);
        },
      );
    }
  }
  test('delete is durable immediately; lock/reopen restores undo and cancellation survives another reopen', () async {
    var controller = await open();
    expect(await controller.deleteGiftWithUndo('gift'), isTrue);
    final entry = (await h.queue.entries()).single;
    expect(entry.undoGiftId, 'gift');
    expect(entry.publishAfter, time.add(FamilyController.undoWindow));
    expect((await h.store.read()).current!.entries, hasLength(1));
    await engine.sync();
    expect(
      (await h.remote()).record(Collections.gifts, 'gift')!.isDeleted,
      isFalse,
    );
    lock();
    await h.vault.unlock('123456');
    controller = await open();
    expect(
      container!.read(familyControllerProvider).value!.view.gifts,
      isEmpty,
    );
    expect(await controller.undoDeleteGift('gift'), isTrue);
    expect(await h.queue.entries(), isEmpty);
    lock();
    time = time.add(const Duration(seconds: 8));
    for (final state in h.worker.guard.guards.values) {
      state.nextAttemptAt = null;
    }
    await h.vault.unlock('123456');
    await open();
    expect(
      container!.read(familyControllerProvider).value!.view.gifts,
      hasLength(1),
    );
    expect(
      (await h.remote()).record(Collections.gifts, 'gift')!.isDeleted,
      isFalse,
    );
  });
  test('another action publishes without leaking the undo intent; expiry after lock publishes its tombstone', () async {
    final controller = await open();
    await controller.deleteGiftWithUndo('gift');
    final before = engine.candidate!;
    await engine.save(
      before,
      before.set(
        HlcClock(node: 'web', last: before.maxStamp),
        Collections.recipients,
        'nora',
        {'name': 'Nora Nora'},
      ),
    );
    await engine.sync();
    expect(
      (await h.remote()).record(Collections.gifts, 'gift')!.isDeleted,
      isFalse,
    );
    expect(
      (await h.remote()).record(Collections.recipients, 'nora')!['name'],
      'Nora Nora',
    );
    expect((await h.queue.entries()).single.undoGiftId, 'gift');
    lock();
    time = time.add(const Duration(seconds: 8));
    await h.vault.unlock('123456');
    final reopened = await open();
    expect(await reopened.undoDeleteGift('gift'), isFalse);
    expect(
      (await h.remote()).record(Collections.gifts, 'gift')!.isDeleted,
      isTrue,
    );
    expect(await h.queue.entries(), isEmpty);
  });
  test('failed durable writes acknowledge neither deletion nor undo', () async {
    final controller = await open();
    h.store.beforeWrite = () => throw StateError('storage failure');
    await expectLater(controller.deleteGiftWithUndo('gift'), throwsStateError);
    expect(
      engine.candidate!.record(Collections.gifts, 'gift')!.isDeleted,
      isFalse,
    );
    expect(await h.queue.entries(), isEmpty);
    h.store.beforeWrite = null;
    expect(await controller.deleteGiftWithUndo('gift'), isTrue);
    h.store.beforeWrite = () => throw StateError('storage failure');
    await expectLater(controller.undoDeleteGift('gift'), throwsStateError);
    expect((await h.queue.entries()).single.undoGiftId, 'gift');
    h.store.beforeWrite = null;
  });
  test(
    'expired deletion is revalidated against protection arriving while locked',
    () async {
      final controller = await open();
      await controller.deleteGiftWithUndo('gift');
      lock();
      await h.publish(
        doc: h.phone.doc.set(h.phone.clock, Collections.policies, 'nora', {
          'hideOwnGifts': false,
        }),
      );
      time = time.add(const Duration(seconds: 8));
      await h.vault.unlock('123456');
      await open();
      expect((await h.queue.entries()).single.setAside, isTrue);
      expect(
        (await h.remote()).record(Collections.gifts, 'gift')!.isDeleted,
        isFalse,
      );
    },
  );
}
