import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/app/root_navigator.dart';
import 'package:regalos/core/platform/link_source.dart';
import 'package:regalos/core/platform/link_source_native.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/lock/application/lock_controller.dart';
import 'package:regalos/features/lock/presentation/lock_screen.dart';
import 'package:regalos/features/lock/presentation/pin_setup_screen.dart';
import 'package:regalos/features/sync/application/pairing_v2_controller.dart';
import 'package:regalos/features/sync/invites/incoming_invite.dart';
import 'package:regalos/features/sync/presentation/join_invite_screen.dart';
import 'package:regalos/features/sync/presentation/pairing_v2_guest_view.dart';

import '../helpers/screens.dart';
import '../platform/link_source_test.dart' show FakeLinks;

/// El enlace que llega solo no abre la invitación: antes se ve el nombre de
/// este móvil y se pulsa «Pedir entrada».
Future<void> _ask(WidgetTester tester) async {
  await tester.tap(find.text('Pedir entrada'));
  await settle(tester);
}

class DelayedFamily extends FamilyController {
  final ready = Completer<FamilyState>();

  @override
  Future<FamilyState> build() => ready.future;
}

class TestLock extends LockController {
  TestLock({this.locked = false, this.setup = false});
  final bool locked;
  final bool setup;

  @override
  Future<AppLockState> build() async => AppLockState(
    pinSet: !setup,
    enabled: true,
    biometrics: false,
    locked: locked,
  );

  void release() => state = AsyncData(
    AppLockState(pinSet: true, enabled: true, biometrics: false, locked: false),
  );
}

class RecordingGuest extends PairingV2GuestController {
  final calls = <String>[];

  @override
  // 1.0.6: el que entra ya no elige persona; un paso con el código basta para
  // que la pantalla se asiente (la espera lleva un indicador que no acaba).
  PairingV2GuestState build() => const PairingV2GuestState(
    PairingV2GuestPhase.compare,
    code: '123456',
  );

  @override
  Future<void> begin(String inviteId, {String deviceName = ''}) async {
    calls.add('begin:$inviteId');
  }

  @override
  void reset() => calls.add('reset');
}

void main() {
  const id = 'AAAAAAAAAAAAAAAAAAAAAA';
  final delayed = DelayedFamily();
  final cold = FakeLinks('https://gifthuddle.app/i#$id');
  final coldGuest = RecordingGuest();
  screenTest(
    'cold invite survives delayed family load and welcome redirect',
    (tester, phone) async {
      addTearDown(cold.controller.close);
      await pumpRegalos(tester, phone);
      expect(phone.container.read(incomingInviteProvider), id);
      expect(find.byType(JoinInviteScreen), findsNothing);
      final lock = phone.container.read(lockControllerProvider).requireValue;
      expect(lock.needsSetup, isTrue);
      expect(lock.pinSet, isFalse);
      delayed.ready.complete(FamilyState.noFamily());
      await settle(tester);
      expect(phone.container.read(routerProvider).state.uri.path, '/welcome');
      expect(find.byType(JoinInviteScreen), findsOneWidget);
      expect(coldGuest.calls, isEmpty);
      expect(find.text('Nombre de este móvil'), findsOneWidget);
      await _ask(tester);
      expect(coldGuest.calls, ['begin:$id']);
      expect(phone.container.read(incomingInviteProvider), isNull);
      await settle(tester);
      expect(find.byType(JoinInviteScreen), findsOneWidget);
    },
    syncHost: null,
    overrides: [
      familyControllerProvider.overrideWith(() => delayed),
      linkSourceProvider.overrideWithValue(cold),
      pairingV2AvailableProvider.overrideWithValue(true),
      pairingV2GuestProvider.overrideWith(() => coldGuest),
    ],
  );

  for (final action in ['unlock', 'set PIN', 'skip setup']) {
    final setup = action != 'unlock';
    final lock = TestLock(locked: !setup, setup: setup);
    final links = FakeLinks('https://gifthuddle.app/i#$id');
    final guest = RecordingGuest();
    screenTest(
      'invite waits for $action',
      (tester, phone) async {
        addTearDown(links.controller.close);
        await tester.runAsync(
          () => familyOf(phone).createFamily(deviceName: 'M'),
        );
        await pumpRegalos(tester, phone);
        expect(phone.container.read(incomingInviteProvider), id);
        expect(find.byType(JoinInviteScreen), findsNothing);
        if (!setup) expect(find.byType(LockScreen), findsOneWidget);
        if (setup) expect(find.byType(PinSetupScreen), findsOneWidget);
        await tester.pump(const Duration(minutes: 10));
        expect(find.byType(JoinInviteScreen), findsNothing);
        expect(phone.container.read(incomingInviteProvider), id);
        if (setup) {
          await tester.runAsync(
            () => action == 'set PIN' ? lock.setPin('1234') : lock.skipSetup(),
          );
        } else {
          lock.release();
        }
        await settle(tester);
        expect(find.byType(JoinInviteScreen), findsOneWidget);
        expect(phone.container.read(incomingInviteProvider), isNull);
        phone.container.read(routerProvider).pop();
        await settle(tester);
        expect(find.byType(JoinInviteScreen), findsNothing);
      },
      syncHost: null,
      overrides: [
        lockControllerProvider.overrideWith(() => lock),
        linkSourceProvider.overrideWithValue(links),
        pairingV2AvailableProvider.overrideWithValue(true),
        pairingV2GuestProvider.overrideWith(() => guest),
      ],
    );
  }

  final androidGuest = RecordingGuest();
  screenTest(
    'Android cold stream invite opens with the real fresh-install lock state',
    (tester, phone) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      // Android delivers the cold-start intent through the native event stream.
      // Queue it before mounting, just as the plugin does on launch.
      ServicesBinding.instance.channelBuffers.push(
        'com.llfbandit.app_links/events',
        const StandardMethodCodec().encodeSuccessEnvelope(
          'https://gifthuddle.app/i#$id',
        ),
        (_) {},
      );
      await pumpRegalos(tester, phone);
      expect(
        phone.container.read(familyControllerProvider).requireValue.hasFamily,
        isFalse,
      );
      expect(
        phone.container.read(lockControllerProvider).requireValue.needsSetup,
        isTrue,
      );
      expect(find.byType(JoinInviteScreen), findsOneWidget);
      expect(androidGuest.calls, isEmpty);
      await _ask(tester);
      expect(androidGuest.calls, ['begin:$id']);
      expect(phone.container.read(incomingInviteProvider), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
    syncHost: null,
    overrides: [
      linkSourceProvider.overrideWithValue(NativeLinkSource()),
      pairingV2AvailableProvider.overrideWithValue(true),
      pairingV2GuestProvider.overrideWith(() => androidGuest),
    ],
  );

  for (final manual in [false, true]) {
    for (final nextId in [id, 'BBBBBBBBBBBBBBBBBBBBBB']) {
      final links = FakeLinks(manual ? null : 'https://gifthuddle.app/i#$id');
      final guest = RecordingGuest();
      screenTest(
        'v2 ignores ${nextId == id ? 'same' : 'different'} invite while joining (manual: $manual)',
        (tester, phone) async {
          addTearDown(links.controller.close);
          await pumpRegalos(tester, phone);
          if (manual) {
            rootNavigatorKey.currentState!.push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const JoinInviteScreen(initialInvite: id),
              ),
            );
            await settle(tester);
          }
          await _ask(tester);
          final view = tester.state(find.byType(PairingV2GuestView));
          final pairing = phone.container.read(pairingV2GuestProvider);
          expect(guest.calls, ['begin:$id']);
          links.controller.add('https://gifthuddle.app/i#$nextId');
          await settle(tester);
          expect(
            find.byType(JoinInviteScreen, skipOffstage: false),
            findsOneWidget,
          );
          expect(tester.state(find.byType(PairingV2GuestView)), same(view));
          expect(phone.container.read(pairingV2GuestProvider), same(pairing));
          expect(guest.calls, ['begin:$id']);
          expect(phone.container.read(incomingInviteProvider), isNull);

          phone.container.read(routerProvider).pop();
          // A tap during the outgoing transition must not mount another view
          // before the old view's dispose has reset the shared controller.
          links.controller.add('https://gifthuddle.app/i#$nextId');
          await settle(tester);
          expect(
            find.byType(JoinInviteScreen, skipOffstage: false),
            findsNothing,
          );
          expect(guest.calls, ['begin:$id', 'reset']);

          // The user can explicitly tap again after closing the current join.
          links.controller.add('https://gifthuddle.app/i#$nextId');
          await settle(tester);
          expect(
            find.byType(JoinInviteScreen, skipOffstage: false),
            findsOneWidget,
          );
          expect(guest.calls, ['begin:$id', 'reset']);
          await _ask(tester);
          expect(guest.calls, ['begin:$id', 'reset', 'begin:$nextId']);
        },
        syncHost: null,
        overrides: [
          linkSourceProvider.overrideWithValue(links),
          pairingV2AvailableProvider.overrideWithValue(true),
          pairingV2GuestProvider.overrideWith(() => guest),
        ],
      );
    }
  }
}
