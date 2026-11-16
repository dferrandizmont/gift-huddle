import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/features/web_device/application/vault_service.dart';
import 'package:regalos/features/web_device/application/web_session_controller.dart';
import 'package:regalos/features/web_device/application/web_session_platform.dart';
import 'package:regalos/features/web_device/data/guard_client.dart';
import 'package:regalos/features/web_device/data/vault_crypto.dart';
import 'package:regalos/features/web_device/data/vault_store.dart';
import 'package:regalos/features/sync/data/sync_transport_common.dart';

import 'fake_guard_server.dart';

/// Protocol/crash tests avoid repeating the expensive KDF. Real KDF is tested
/// independently against the fixed vector in vault_crypto_test.dart.
class FastTestCrypto extends VaultCrypto {
  @override
  Future<SecretKey> deriveA(String pin, VaultHeader header) async {
    header.validate();
    if (!VaultCrypto.validPin(pin)) throw ArgumentError('Invalid PIN');
    return SecretKey(
      (await Sha256().hash([...utf8.encode(pin), ...header.salt])).bytes,
    );
  }
}

class VaultHarness {
  DateTime time = DateTime.utc(2026);
  late final server = FakeGuardServer(now: () => time);
  final store = MemoryVaultStore();
  String? failRoute;
  bool failAfter = false;
  String? rejectRoute;
  final requests = <String>[];
  final credential = List<int>.filled(32, 42);
  late final client = GuardClient(
    base: Uri.parse('https://example.test'),
    send: (method, uri, {body, headers = const {}}) async {
      requests.add(uri.path.split('/').last);
      if (uri.path.endsWith('/$rejectRoute')) {
        return SyncResponse(
          403,
          const {},
          utf8.encode('{"error":"forbidden"}'),
        );
      }
      if (uri.path.endsWith('/$failRoute') && !failAfter) {
        throw StateError('Cut before $failRoute');
      }
      final result = await server.send(
        method,
        uri,
        body: body,
        headers: headers,
      );
      if (uri.path.endsWith('/$failRoute') && failAfter) {
        throw StateError('Cut after $failRoute');
      }
      return result;
    },
  );
  late final service = newService();
  VaultHarness() {
    server.credentials['Bearer ${encodeBase64Url(credential)}'] =
        FakeGuardCredential('AAAAAAAAAAAAAAAAAAAAAA', 'bbbbbbbbbb', 'web');
  }
  VaultService newService() => VaultService(
    store: store,
    guard: client,
    crypto: FastTestCrypto(),
    persist: () async => false,
  );
  Future<void> enroll() => service.enroll(
    pin: '123456',
    syncId: 'AAAAAAAAAAAAAAAAAAAAAA',
    deviceId: 'bbbbbbbbbb',
    data: {
      'credential': encodeBase64Url(credential),
      'familyKey': encodeBase64Url(List.filled(32, 9)),
      'roots': <Object?>[],
      'snapshot': <String, Object?>{},
    },
  );
  void advance() {
    time = time.add(const Duration(seconds: 2));
  }
}

class FakeSessionClock implements SessionClock {
  DateTime time = DateTime.utc(2026);
  final jobs =
      <({DateTime at, void Function() callback, List<bool> cancelled})>[];
  @override
  DateTime now() => time;
  @override
  void Function() schedule(Duration delay, void Function() callback) {
    final cancelled = [false];
    jobs.add((at: time.add(delay), callback: callback, cancelled: cancelled));
    return () {
      cancelled[0] = true;
    };
  }

  void elapse(Duration duration, {bool timers = true}) {
    time = time.add(duration);
    if (!timers) return;
    for (final job in List.of(jobs)) {
      if (!job.cancelled[0] && !job.at.isAfter(time)) {
        job.cancelled[0] = true;
        job.callback();
      }
    }
  }
}

class FakeLockHub {
  Completer<void>? releaseGate;
  FakeSessionPlatform? owner;
  final platforms = <FakeSessionPlatform>[];
  Completer<void> changed = Completer<void>();
  void release(FakeSessionPlatform platform) {
    if (identical(owner, platform)) {
      owner = null;
      changed.complete();
      changed = Completer<void>();
    }
  }
}

class _FakeLease implements SessionLease {
  _FakeLease(this.platform);
  final FakeSessionPlatform platform;
  @override
  Future<void> release() async {
    if (platform.hub.releaseGate case final gate?) await gate.future;
    platform.hub.release(platform);
  }
}

class FakeSessionPlatform implements SessionPlatform {
  FakeSessionPlatform(this.hub) {
    hub.platforms.add(this);
  }
  final FakeLockHub hub;
  @override
  bool hidden = false;
  final life = StreamController<SessionLifecycle>.broadcast(sync: true);
  final takeover = StreamController<void>.broadcast(sync: true);
  @override
  Stream<SessionLifecycle> get lifecycle => life.stream;
  @override
  Stream<void> get takeoverRequests => takeover.stream;
  @override
  Future<SessionLease?> acquire({required bool wait}) async {
    while (hub.owner != null) {
      if (!wait) return null;
      await hub.changed.future;
    }
    hub.owner = this;
    return _FakeLease(this);
  }

  @override
  void requestTakeover() {
    for (final platform in hub.platforms) {
      if (!identical(platform, this)) platform.takeover.add(null);
    }
  }

  @override
  Future<void> dispose() async {
    hub.release(this);
    hub.platforms.remove(this);
    await life.close();
    await takeover.close();
  }
}
