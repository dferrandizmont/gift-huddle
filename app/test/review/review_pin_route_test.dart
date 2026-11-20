import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/platform/secure_screen.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/widgets/regalos_switch.dart';
import 'package:regalos/features/lock/application/lock_controller.dart';
import 'package:regalos/features/lock/presentation/pin_setup_screen.dart';
import 'package:regalos/features/review/application/review_providers.dart';
import 'package:regalos/features/settings/presentation/pin_verify_screen.dart';

import '../helpers/screens.dart';
import 'review_delivery_test.dart' show gift;

void main() {
  if (!kStoreBuild) {
    test(
      'review visibility on Settings PIN routes',
      () {},
      skip: 'Requires --dart-define=STORE_BUILD=true',
    );
    return;
  }

  for (final (action, pendingStoreCall) in [
    ('change', null),
    ('disable', null),
    ('enable', null),
    ('erase', null),
    ('erase', 'isAvailable'),
    ('erase', 'requestReview'),
  ]) {
    final erasing = action == 'erase';
    screenTest(
      switch (pendingStoreCall) {
        'isAvailable' => 'opening the PIN during availability blocks launch',
        'requestReview' =>
          'opening the PIN after dispatch does not retry the request',
        _ =>
          erasing
              ? 'a saved delivery cannot prompt over the PIN route for erase all'
              : 'a saved delivery cannot prompt over the PIN route to $action it',
      },
      (tester, phone) async {
        const channel = MethodChannel('dev.britannio.in_app_review');
        final storeCalls = <String>[];
        final storeReply = Completer<void>();
        addTearDown(() {
          if (!storeReply.isCompleted) storeReply.complete();
        });
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            storeCalls.add(call.method);
            if (call.method == pendingStoreCall) await storeReply.future;
            return call.method == 'isAvailable' ? true : null;
          },
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final enabling = action == 'enable';
        await seedSample(tester, phone, pin: !enabling);
        final family = familyOf(phone);
        final list = await familyState(tester, phone);
        final delivered = list.view.allGifts
            .where((gift) => gift.status == GiftStatus.delivered)
            .length;
        await tester.runAsync(() async {
          for (var count = delivered; count < 4; count++) {
            await family.upsertGift(
              gift('review-gift-$count', GiftStatus.delivered),
            );
          }
          await family.upsertGift(gift('review-gift-4', GiftStatus.bought));
        });
        await pumpRegalos(tester, phone);
        phone.container
            .read(routerProvider)
            .go(erasing ? '/settings' : '/settings/security');
        await settle(tester);
        final visibility = phone.container.read(reviewVisibilityProvider);
        expect(visibility.canPresent, isTrue);

        Future<void> deliverFifthGift() async {
          final saved = await tester.runAsync(
            () => family.setGiftStatus('review-gift-4', GiftStatus.delivered),
          );
          expect(saved, isTrue);
          await settle(tester);
        }

        final expectedCalls = [
          if (pendingStoreCall != null) 'isAvailable',
          if (pendingStoreCall == 'requestReview') 'requestReview',
        ];
        if (pendingStoreCall != null) {
          await deliverFifthGift();
          expect(storeCalls, expectedCalls);
          expect(
            phone.files.files.containsKey('review.json'),
            pendingStoreCall == 'requestReview',
          );
        }

        if (erasing) {
          final eraseAll = find.text('Borrar todo');
          await tester.ensureVisible(eraseAll);
          await tester.pump();
          await tapText(tester, 'Borrar todo');
          expect(find.text('¿Borrar todo?'), findsOneWidget);
          await tapText(tester, 'Continuar');
        } else if (action == 'change') {
          await tapText(tester, 'Cambiar PIN');
        } else {
          await tester.tap(
            find.byWidgetPredicate(
              (widget) =>
                  widget is RegalosSwitch &&
                  widget.semanticLabel == 'Bloqueo con PIN',
            ),
          );
          await settle(tester);
        }
        final pinRoute = find.byType(
          enabling ? PinSetupScreen : PinVerifyScreen,
        );
        expect(pinRoute, findsOneWidget);
        expect(visibility.canPresent, isFalse);

        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await tester.pump();
        for (final state in [
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await settle(tester);
        expect(pinRoute, findsOneWidget);
        expect(
          phone.container.read(lockControllerProvider).requireValue.locked,
          isFalse,
        );
        expect(visibility.canPresent, isFalse);

        if (pendingStoreCall == null) {
          await deliverFifthGift();
        } else {
          storeReply.complete();
          await settle(tester);
        }
        expect(
          phone.files.files.containsKey('review.json'),
          pendingStoreCall == 'requestReview',
        );
        expect(storeCalls, expectedCalls);

        Navigator.of(tester.element(pinRoute)).pop(false);
        expect(visibility.canPresent, isFalse);
        await settle(tester);
        expect(visibility.canPresent, isTrue);
        expect(storeCalls, expectedCalls);
      },
    );
  }
}
