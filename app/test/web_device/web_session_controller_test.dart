import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/web_device/application/web_session_controller.dart';
import 'package:regalos/features/web_device/application/web_session_platform.dart';
import 'package:regalos/features/web_device/data/guard_client.dart';

import 'test_support.dart';

void main() {
  late FakeSessionClock clock;
  late FakeSessionPlatform platform;
  late FakeLockHub hub;
  late WebSessionController session;
  late List<String> events;
  WebSessionController build(
    FakeSessionPlatform adapter, {
    Future<void> Function(String)? unlock,
  }) => WebSessionController(
    platform: adapter,
    clock: clock,
    cover: () => events.add('cover'),
    cancelWork: () => events.add('cancel'),
    lockVault: () => events.add('invalidate-vault'),
    disposeContainer: () => events.add('dispose'),
    createContainer: () => events.add('create'),
    unlockVault: unlock ?? (_) async {},
    onVisible: () => events.add('visible'),
    onHidden: () => events.add('hidden'),
  );
  setUp(() {
    clock = FakeSessionClock();
    hub = FakeLockHub();
    platform = FakeSessionPlatform(hub);
    events = [];
    session = build(platform);
  });
  tearDown(() => session.dispose());
  test('idle deadline uses real clock and activity extends it', () async {
    await session.unlock('123456');
    clock.elapse(const Duration(minutes: 14));
    session.activity();
    clock.elapse(const Duration(minutes: 14));
    expect(session.state, WebSessionState.abierta);
    clock.elapse(const Duration(minutes: 1));
    expect(session.state, WebSessionState.bloqueada);
    expect(events.sublist(events.length - 4), [
      'cover',
      'cancel',
      'invalidate-vault',
      'dispose',
    ]);
    expect(hub.owner, isNull);
  });
  test('hidden deadline checked on return when timers were frozen', () async {
    await session.unlock('123456');
    platform.life.add(SessionLifecycle.hidden);
    clock.elapse(const Duration(minutes: 5), timers: false);
    expect(session.state, WebSessionState.abierta);
    platform.life.add(SessionLifecycle.visible);
    expect(session.state, WebSessionState.bloqueada);
    expect(events, isNot(contains('visible')));
  });
  test('only a returning open session requests a visibility refresh', () async {
    expect(session.visible, isTrue);
    platform.life.add(SessionLifecycle.hidden);
    expect(session.visible, isFalse);
    platform.life.add(SessionLifecycle.visible);
    expect(session.visible, isTrue);
    expect(events, isEmpty);
    await session.unlock('123456');
    platform.life.add(SessionLifecycle.visible);
    expect(events.where((e) => e == 'visible'), isEmpty);
    platform.life.add(SessionLifecycle.hidden);
    clock.elapse(const Duration(minutes: 1));
    platform.life.add(SessionLifecycle.visible);
    platform.life.add(SessionLifecycle.visible);
    expect(session.state, WebSessionState.abierta);
    expect(events.where((e) => e == 'visible'), hasLength(1));
    expect(events.where((e) => e == 'hidden'), hasLength(1));
  });
  test(
    'hidden timer locks at five minutes; hidden activity does not extend',
    () async {
      await session.unlock('123456');
      platform.life.add(SessionLifecycle.hidden);
      clock.elapse(const Duration(minutes: 4));
      session.activity();
      clock.elapse(const Duration(minutes: 1));
      expect(session.state, WebSessionState.bloqueada);
    },
  );
  test(
    'frozen idle timers checked before accepting returning activity',
    () async {
      await session.unlock('123456');
      clock.elapse(const Duration(minutes: 16), timers: false);
      session.activity();
      expect(session.state, WebSessionState.bloqueada);
    },
  );
  test(
    'pagehide and all pageshow paths require PIN, including BFCache',
    () async {
      for (final event in [
        SessionLifecycle.pagehide,
        SessionLifecycle.pageshow,
        SessionLifecycle.pageshowPersisted,
      ]) {
        await session.unlock('123456');
        platform.life.add(event);
        expect(session.state, WebSessionState.bloqueada);
      }
    },
  );
  test('late HTTP and socket callbacks and stale timers are ignored', () async {
    await session.unlock('123456');
    final generation = session.generation;
    var delivered = 0;
    final callback = session.guardCallback<int>((_) => delivered++);
    final oldTimer = clock.jobs.last.callback;
    session.lock();
    await session.unlock('123456');
    callback(1);
    oldTimer();
    expect(delivered, 0);
    expect(session.accept(generation), isFalse);
    expect(session.state, WebSessionState.abierta);
  });
  test('late unlock response cannot open or create a container', () async {
    await session.dispose();
    platform = FakeSessionPlatform(hub);
    final response = Completer<void>();
    session = build(platform, unlock: (_) => response.future);
    final future = session.unlock('123456');
    await Future<void>.delayed(Duration.zero);
    session.lock();
    response.complete();
    await future;
    expect(session.state, WebSessionState.bloqueada);
    expect(events, isNot(contains('create')));
  });
  test('second tab cannot unlock; takeover waits for actual release', () async {
    await session.unlock('123456');
    var unlocked = false;
    final other = build(
      FakeSessionPlatform(hub),
      unlock: (_) async {
        unlocked = true;
      },
    );
    await other.unlock('123456');
    expect(other.state, WebSessionState.otraPestana);
    expect(unlocked, isFalse);
    hub.releaseGate = Completer<void>();
    final takeover = other.unlock('123456', useHere: true);
    await Future<void>.delayed(Duration.zero);
    expect(unlocked, isFalse);
    expect(other.state, WebSessionState.desbloqueando);
    hub.releaseGate!.complete();
    await takeover;
    expect(session.state, WebSessionState.bloqueada);
    expect(other.state, WebSessionState.abierta);
    expect(unlocked, isTrue);
    await other.dispose();
  });
  test('404 becomes disconnected and 423 suspended', () async {
    await session.dispose();
    platform = FakeSessionPlatform(hub);
    session = build(
      platform,
      unlock: (_) async =>
          throw const GuardException(GuardFailure.disconnected),
    );
    await expectLater(session.unlock('123456'), throwsA(isA<GuardException>()));
    expect(session.state, WebSessionState.desconectada);
    await session.dispose();
    platform = FakeSessionPlatform(hub);
    session = build(
      platform,
      unlock: (_) async => throw const GuardException(GuardFailure.suspended),
    );
    await expectLater(session.unlock('123456'), throwsA(isA<GuardException>()));
    expect(session.state, WebSessionState.suspendida);
  });

  for (final waitLock in [false, true]) {
    for (final visible in [false, true]) {
      for (final timers in [false, true]) {
        test(
          'hidden deadline during ${waitLock ? 'lock wait' : 'unlock'} '
          'visible=$visible timers=$timers never creates container',
          () async {
            await session.dispose();
            final response = Completer<void>();
            FakeSessionPlatform? owner;
            if (waitLock) {
              owner = FakeSessionPlatform(hub);
              await owner.acquire(wait: false);
            }
            platform = FakeSessionPlatform(hub);
            var calls = 0;
            session = build(
              platform,
              unlock: (_) {
                calls++;
                return response.future;
              },
            );
            events.clear();
            final opening = session.unlock('123456', useHere: waitLock);
            await Future<void>.delayed(Duration.zero);
            platform.life.add(SessionLifecycle.hidden);
            clock.elapse(const Duration(minutes: 5), timers: timers);
            if (visible) platform.life.add(SessionLifecycle.visible);
            if (owner != null) hub.release(owner);
            response.complete();
            await opening;
            expect(session.state, WebSessionState.bloqueada);
            expect(events, isNot(contains('create')));
            expect(calls, waitLock ? 0 : 1);
            expect(hub.owner, isNull);
            await owner?.dispose();
          },
        );
      }
    }
  }

  test('unlock completion preserves actual hidden start', () async {
    await session.dispose();
    platform = FakeSessionPlatform(hub)..hidden = true;
    final response = Completer<void>();
    session = build(platform, unlock: (_) => response.future);
    clock.elapse(const Duration(minutes: 1));
    final opening = session.unlock('123456');
    await Future<void>.delayed(Duration.zero);
    clock.elapse(const Duration(minutes: 3));
    response.complete();
    await opening;
    expect(session.state, WebSessionState.abierta);
    clock.elapse(const Duration(minutes: 1));
    expect(session.state, WebSessionState.bloqueada);
  });
}
