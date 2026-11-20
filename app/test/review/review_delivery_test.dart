import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/fresh_install.dart';
import 'package:regalos/core/platform/secure_screen.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/pairing_v2.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/application/family_providers.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/review/application/review_providers.dart';
import 'package:regalos/features/review/application/review_service.dart';
import 'package:regalos/features/review/data/local_review_preferences.dart';
import 'package:regalos/features/review/data/store_review_native.dart';

import '../helpers/memory_stores.dart';
import '../sync/protected_harness.dart' as protection;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.britannio.in_app_review');

  group('review after saving a gift', () {
    late DateTime now;
    late ReviewService review;
    late FakePhone phone;
    late FamilyController family;
    late _FailingGiftFiles files;
    late int requests;
    late Future<void> Function()? onRequest;

    setUp(() async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      requests = 0;
      now = DateTime.utc(2026, 11, 20);
      onRequest = null;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'isAvailable') return true;
        expect(call.method, 'requestReview');
        expect(files.reviewWrites, requests + 1);
        expect(files.files, contains('review.json'));
        requests++;
        await onRequest?.call();
        return null;
      });
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      files = _FailingGiftFiles();
      review = ReviewService(
        preferences: LocalReviewPreferences(files),
        store: createStoreReview(),
        isWeb: false,
        isStoreBuild: true,
        canPresent: (_) => true,
        clock: Clock(() => now),
      );
      phone = FakePhone(
        files: files,
        extraOverrides: [reviewServiceProvider.overrideWithValue(review)],
      );
      addTearDown(phone.dispose);
      family = phone.container.read(familyControllerProvider.notifier);
      await family.createFamily(deviceName: 'Aritz');
      await family.upsertRecipient(
        const Recipient(
          id: 'aritz',
          name: 'Aritz',
          colorIndex: 0,
          archived: false,
        ),
      );
      for (var i = 0; i < 6; i++) {
        await family.upsertGift(gift('gift-$i', GiftStatus.bought));
      }
      for (var i = 0; i < 4; i++) {
        expect(
          await family.setGiftStatus('gift-$i', GiftStatus.delivered),
          isTrue,
        );
      }
      expect(requests, 0);
      expect(files.reviewReads, 0);
      expect(files.files, isNot(contains('review.json')));
    });

    Future<void> drainReview() =>
        review.deliverySaved(familyId: '', before: 0, after: 0);

    Future<String?> storedStatus(String id) async {
      final stored = await phone.container.read(familyStoreProvider).load();
      return stored?.doc.record(Collections.gifts, id)?['status'] as String?;
    }

    for (final viaMerge in [false, true]) {
      final source = viaMerge ? 'merging' : 'loading';
      test(
        '$source five delivered gifts leaves review storage untouched',
        () async {
          final store = phone.container.read(familyStoreProvider);
          final stored = (await store.load())!;
          const remoteNode = 'other-device';
          final clock = HlcClock(node: remoteNode, last: stored.doc.maxStamp);
          final remote = stored.doc.set(clock, Collections.gifts, 'gift-4', {
            'status': GiftStatus.delivered.name,
          });
          if (viaMerge) {
            await family.mergeRemote(remote, fromNode: remoteNode);
          } else {
            await store.saveDoc(remote);
          }
          await drainReview();
          expect(requests, 0);
          expect(files.reviewReads, 0);
          expect(files.reviewWrites, 0);
          expect(files.files, isNot(contains('review.json')));

          phone.restart();
          await phone.container.read(familyControllerProvider.future);
          expect(await storedStatus('gift-4'), 'delivered');
          expect(requests, 0);
          expect(files.reviewReads, 0);
          expect(files.reviewWrites, 0);

          family = phone.container.read(familyControllerProvider.notifier);
          expect(
            await family.setGiftStatus('gift-4', GiftStatus.bought),
            isTrue,
          );
          expect(await storedStatus('gift-4'), 'bought');
          expect(
            await family.setGiftStatus('gift-4', GiftStatus.delivered),
            isTrue,
          );
          await drainReview();
          expect(await storedStatus('gift-4'), 'delivered');
          expect(files.reviewWrites, 1);
          expect(requests, 1);
        },
      );
    }

    for (final action in [
      'status action',
      'gift edit',
      'gift edit with People',
    ]) {
      test(
        'the fifth persisted delivery from the $action requests once',
        () async {
          expect(
            await family.setGiftStatus('missing', GiftStatus.delivered),
            isFalse,
          );
          await drainReview();
          expect(requests, 0);

          final delivery = gift('gift-4', GiftStatus.delivered);
          final original = gift('gift-4', GiftStatus.bought);
          if (action == 'gift edit with People') {
            await family.upsertRecipient(
              const Recipient(
                id: 'nora',
                name: 'Nora',
                colorIndex: 1,
                archived: false,
              ),
            );
          }
          final saved = switch (action) {
            'status action' => await family.setGiftStatus(
              delivery.id,
              delivery.status,
            ),
            'gift edit' => await family.upsertGift(
              delivery,
              original: original,
            ),
            _ =>
              await family.upsertGiftWithGiverPerson(
                    delivery,
                    'nora',
                    original: original,
                  ) ==
                  GiftWriteResult.saved,
          };
          expect(saved, isTrue);
          await drainReview();
          expect(requests, 1);
          expect(jsonDecode(utf8.decode(files.files['review.json']!)), {
            'count': 1,
            'lastRequestedAt': now.toIso8601String(),
          });

          now = now.add(const Duration(days: 120));
          final reads = files.reviewReads;
          expect(
            await family.setGiftStatus('gift-5', GiftStatus.delivered),
            isTrue,
          );
          await drainReview();
          expect(requests, 1);
          expect(files.reviewReads, reads);
          expect(files.reviewWrites, 1);
        },
      );
    }

    for (final failSecondSave in [false, true]) {
      final outcome = failSecondSave ? 'failed' : 'successful';
      test('a $outcome second save leaves the first review pending', () async {
        final started = Completer<void>();
        final reply = Completer<void>();
        onRequest = () {
          if (!started.isCompleted) started.complete();
          return reply.future;
        };
        addTearDown(() {
          if (!reply.isCompleted) reply.complete();
        });

        expect(
          await family.setGiftStatus('gift-4', GiftStatus.delivered),
          isTrue,
        );
        await started.future;
        expect(files.files, contains('review.json'));

        files.failNextSave = failSecondSave;
        final second = family.setGiftStatus('gift-5', GiftStatus.delivered);
        if (failSecondSave) {
          await expectLater(second, throwsA(isA<FileSystemException>()));
        } else {
          expect(await second, isTrue);
        }
        expect(await storedStatus('gift-4'), 'delivered');
        expect(
          await storedStatus('gift-5'),
          failSecondSave ? 'bought' : 'delivered',
        );
        expect(reply.isCompleted, isFalse);
        expect(requests, 1);

        reply.complete();
        await drainReview();
        expect(files.reviewWrites, 1);
        expect(requests, 1);
      });
    }

    test('a failed fifth save leaves review storage untouched', () async {
      files.failNextSave = true;
      await expectLater(
        family.setGiftStatus('gift-4', GiftStatus.delivered),
        throwsA(isA<FileSystemException>()),
      );
      await drainReview();
      expect(requests, 0);
      expect(files.reviewReads, 0);
      expect(files.reviewWrites, 0);
    });

    test('a v2 delivery without authorization skips review storage', () async {
      final store = phone.container.read(familyStoreProvider);
      final stored = (await store.load())!;
      final clock = HlcClock(
        node: stored.identity.node,
        last: stored.doc.maxStamp,
      );
      await store.saveDoc(
        stored.doc.set(clock, Collections.meta, kProtocolRecordId, {
          kProtocolVersionField: kSyncProtocolV2,
        }),
      );

      phone.restart();
      final current = await phone.container.read(
        familyControllerProvider.future,
      );
      family = phone.container.read(familyControllerProvider.notifier);
      expect(syncProtocolOf(current.doc), kSyncProtocolV2);
      expect(
        await phone.container.read(authorizedProjectionProvider.future),
        isNull,
      );
      expect(phone.container.read(familyStateProvider)!.view.allGifts, isEmpty);

      expect(
        await family.setGiftStatus('gift-4', GiftStatus.delivered),
        isTrue,
      );
      await drainReview();
      expect(await storedStatus('gift-4'), 'delivered');
      expect(requests, 0);
      expect(files.reviewReads, 0);
      expect(files.reviewWrites, 0);
    });

    test(
      'reassigning a giver preserves a remote status and skips review',
      () async {
        await family.upsertGiver(
          const Giver(
            id: 'nora',
            name: 'Nora',
            colorIndex: 1,
            householdPays: false,
            archived: false,
          ),
        );
        final store = phone.container.read(familyStoreProvider);
        final stored = (await store.load())!;
        const remoteNode = 'other-device';
        final clock = HlcClock(node: remoteNode, last: stored.doc.maxStamp);
        final delivered = stored.doc.set(clock, Collections.gifts, 'gift-4', {
          'status': GiftStatus.delivered.name,
        });
        await family.mergeRemote(delivered, fromNode: remoteNode);
        final stale = phone.container
            .read(familyControllerProvider)
            .requireValue
            .view
            .allGifts
            .firstWhere((gift) => gift.id == 'gift-4');
        final bought = delivered.set(clock, Collections.gifts, stale.id, {
          'status': GiftStatus.bought.name,
        });
        await family.mergeRemote(bought, fromNode: remoteNode);

        expect(
          await family.setGiftGiver(stale.id, 'nora'),
          GiftWriteResult.saved,
        );
        await drainReview();
        final saved = (await store.load())!.doc.record(
          Collections.gifts,
          stale.id,
        )!;
        expect(saved['giverId'], 'nora');
        expect(
          saved.fields['status'],
          bought.record(Collections.gifts, stale.id)!.fields['status'],
        );
        expect(requests, 0);
        expect(files.reviewReads, 0);
        expect(files.reviewWrites, 0);
      },
    );

    test(
      'counts authorized gifts when an editor moves the fifth delivery',
      () async {
        await family.resetLocalData();
        final shared = await protection.Family.create();
        final member = shared.aritz;
        final store = phone.container.read(familyStoreProvider);
        final keys = phone.container.read(deviceKeysStoreProvider);
        final clock = HlcClock(node: member.id);
        final doc = protection.commonWithPeople(clock).set(
          clock,
          Collections.meta,
          kProtocolRecordId,
          {kProtocolVersionField: kSyncProtocolV2},
        );
        await keys.restore(member.keys);
        await store.saveFamily(
          StoredFamily(
            identity: FamilyIdentity(
              listId: doc.listId,
              node: member.id,
              deviceName: 'Aritz',
              paired: true,
              selfRecipientId: member.self,
            ),
            key: await FamilyKey.generate(),
            doc: doc,
          ),
        );
        await store.saveSyncV2(
          SyncIdentityV2(
            listId: doc.listId,
            deviceId: member.id,
            syncId: 'AAAAAAAAAAAAAAAAAAAAAA',
          ),
        );
        await store.saveRegistry(shared.registry);
        await keys.saveKeyring(doc.listId, shared.authorizedKeyring);
        phone.restart();
        family = phone.container.read(familyControllerProvider.notifier);
        await family.activateProtection('nora');
        for (var i = 0; i < 4; i++) {
          await family.upsertGift(
            gift(
              'gift-$i',
              GiftStatus.delivered,
              recipientId: i == 0 ? 'nora' : 'leo',
            ),
          );
        }
        final fifth = gift('gift-4', GiftStatus.bought, recipientId: 'nora');
        await family.upsertGift(fifth);
        expect(files.reviewReads, 0);

        expect(
          await family.upsertGift(
            gift(fifth.id, GiftStatus.delivered, recipientId: 'leo'),
            original: fifth,
          ),
          isTrue,
        );
        await drainReview();
        expect(requests, 1);
        expect(files.reviewWrites, 1);
      },
    );

    test(
      'a platform exception from the store leaves both saves intact',
      () async {
        onRequest = () async => throw PlatformException(code: 'review_failed');

        expect(
          await family.setGiftStatus('gift-4', GiftStatus.delivered),
          isTrue,
        );
        await drainReview();
        expect(
          await family.setGiftStatus('gift-5', GiftStatus.delivered),
          isTrue,
        );
        await drainReview();

        expect(await storedStatus('gift-4'), 'delivered');
        expect(await storedStatus('gift-5'), 'delivered');
        expect(files.reviewWrites, 1);
        expect(requests, 1);
      },
    );

    test(
      'redelivering the fifth gift can request again after 120 days',
      () async {
        Future<void> deliverFifth() async {
          expect(
            await family.setGiftStatus('gift-4', GiftStatus.delivered),
            isTrue,
          );
          await drainReview();
        }

        await deliverFifth();
        final firstRequest = now;
        expect(files.reviewWrites, 1);

        now = firstRequest.add(const Duration(days: 119));
        expect(await family.setGiftStatus('gift-4', GiftStatus.bought), isTrue);
        await deliverFifth();
        expect(files.reviewWrites, 1);

        now = firstRequest.add(const Duration(days: 120));
        expect(await family.setGiftStatus('gift-4', GiftStatus.bought), isTrue);
        await deliverFifth();
        expect(requests, 2);
        expect(files.reviewWrites, 2);
        expect(jsonDecode(utf8.decode(files.files['review.json']!)), {
          'count': 2,
          'lastRequestedAt': now.toIso8601String(),
        });
      },
    );
  }, skip: !kStoreBuild ? 'Requires --dart-define=STORE_BUILD=true' : false);
}

class _FailingGiftFiles extends MemoryFileStore {
  bool failNextSave = false;
  int reviewReads = 0;
  int reviewWrites = 0;

  @override
  Future<Uint8List?> read(String name) {
    if (name == 'review.json') reviewReads++;
    return super.read(name);
  }

  @override
  Future<void> writeAtomic(String name, Uint8List bytes) async {
    if (name == 'review.json') reviewWrites++;
    if (failNextSave && name == kFamilyDocFileName) {
      failNextSave = false;
      throw FileSystemException('Gift save failed', name);
    }
    await super.writeAtomic(name, bytes);
  }
}

Gift gift(String id, GiftStatus status, {String recipientId = 'aritz'}) => Gift(
  id: id,
  recipientId: recipientId,
  title: 'Book',
  status: status,
  rawStatus: status.name,
  surprise: false,
  year: 2026,
);
