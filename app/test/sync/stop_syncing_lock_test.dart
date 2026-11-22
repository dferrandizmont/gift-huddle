// «Dejar de sincronizar» estrena la generación nueva dentro del cerrojo v2
// (como la migración y la instalación del invitado): el pendiente se escribe
// y se termina con el cerrojo tomado, una vuelta de sincronización que llega
// en medio espera, y la generación queda completa (sin pendiente, con otro
// syncId y el documento en v2).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/prefs/shared_preferences_provider.dart';
import 'package:regalos/core/sync/pairing_v2.dart'
    show kSyncProtocolV2, syncProtocolOf;
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/family/data/generation_store.dart';
import 'package:regalos/features/sync/application/app_sync_v2_local.dart'
    show v2FamilyLockProvider;
import 'package:regalos/features/sync/application/pairing_v2_controller.dart';
import 'package:regalos/features/sync/application/sync_controller.dart';
import 'package:regalos/features/sync/application/v2_family_lock.dart';
import 'package:regalos/features/sync/data/sync_config.dart';

import '../helpers/fake_sync_server.dart';
import '../helpers/host_person.dart';
import '../helpers/fake_worker_v2.dart';
import '../helpers/memory_stores.dart';
import '../helpers/pump_app.dart';
import 'sync_harness.dart';

const _inLock = #insideV2FamilyLock;

/// The real lock, marking the zone of each transaction so a write can tell
/// whether it happens inside one.
class _ZoneLock extends V2FamilyLock {
  @override
  Future<T> run<T>(Future<T> Function() transaction) =>
      super.run(() => runZoned(transaction, zoneValues: {_inLock: true}));
}

/// Secrets that pause once, right after writing a given key, and note
/// whether that write ran inside the v2 lock.
class _GatedSecrets extends MemorySecretStore {
  (String, Completer<void>, Completer<void>)? pauseAfter;

  /// For each write of `family.pendingV2`: whether it ran inside the lock.
  final pendingWrites = <bool>[];

  @override
  Future<void> write(String key, String value) async {
    if (key == 'family.pendingV2') {
      pendingWrites.add(Zone.current[_inLock] == true);
    }
    await super.write(key, value);
    final gate = pauseAfter;
    if (gate != null && gate.$1 == key) {
      pauseAfter = null;
      gate.$2.complete();
      await gate.$3.future;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stopSyncing starts the new generation under the v2 lock; a sync '
      'round in the middle waits and the generation completes', () async {
    final worker = FakeWorkerV2();
    final secrets = _GatedSecrets();
    final a = FakePhone(
      prefs: await mockPrefs(),
      secrets: secrets,
      syncHost: null,
      extraOverrides: [
        v2FamilyLockProvider.overrideWithValue(_ZoneLock()),
        syncHostProvider.overrideWithValue(kTestHost),
        invitationOriginProvider.overrideWithValue(''),
        syncTransportProvider.overrideWithValue(FakeSyncServer().connect()),
        syncV2TransportProvider.overrideWithValue(worker.client()),
        syncTimingProvider.overrideWithValue(kFastTiming),
      ],
    );
    addTearDown(a.dispose);
    a.container.read(syncControllerProvider);
    a.container.read(sharedPreferencesProvider);
    final fam = a.container.read(familyControllerProvider.notifier);
    await a.container.read(familyControllerProvider.future);
    await fam.createFamily(deviceName: 'Aritz');
    await hostWithPerson(a);
    final host = a.container.read(pairingV2HostProvider.notifier);
    await host.start(guestPerson: kGuestGiver);
    host.dismiss();
    final store = a.container.read(familyStoreProvider);
    final old = (await store.readSyncV2())!;
    // The unmanaged path (no generation journal): PendingV2 + finishPendingV2.
    expect(
      await a.container.read(generationStoreProvider).activeSyncId(),
      isNull,
    );
    final sync = a.container.read(syncControllerProvider.notifier);

    // Pause right after the pending generation is saved.
    final saved = Completer<void>();
    final release = Completer<void>();
    secrets.pauseAfter = ('family.pendingV2', saved, release);
    final stopping = sync.stopSyncing();
    await saved.future;
    // A sync round arrives now: it waits for the lock.
    final round = sync.syncNow();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    release.complete();
    await stopping;
    await round;
    // Every pending generation (stopSyncing's and any a racing round
    // starts when it finds the list gone) was written inside the lock.
    expect(secrets.pendingWrites, isNotEmpty);
    expect(secrets.pendingWrites, everyElement(isTrue));
    expect(await store.readPendingV2(), isNull);
    final now = (await store.readSyncV2())!;
    expect(now.syncId, isNot(old.syncId), reason: 'a new generation');
    expect(
      syncProtocolOf(a.container.read(familyControllerProvider).value!.doc),
      kSyncProtocolV2,
    );
  });
}
