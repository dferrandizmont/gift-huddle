import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/sharing/application/pairing_service.dart';
import 'package:regalos/features/sync/application/sync_controller.dart';
import 'package:regalos/features/sync/data/sync_config.dart';
import 'package:regalos/features/sync/domain/sync_status.dart';

import '../helpers/fake_sync_server.dart';
import '../helpers/memory_stores.dart';
import '../helpers/pump_app.dart';

/// Host de pruebas: solo cuenta que haya uno; el servidor es el falso.
const kTestHost = 'sync.test';

/// Tiempos cortos para que las pruebas no esperen.
const kFastTiming = SyncTiming(
  debounce: Duration(milliseconds: 30),
  backoff: [Duration(milliseconds: 80), Duration(milliseconds: 240)],
  watchBackoff: [Duration(milliseconds: 40), Duration(milliseconds: 120)],
  invitePoll: Duration(milliseconds: 30),
  inviteHostPoll: Duration(milliseconds: 30),
  inviteTimeout: Duration(seconds: 3),
  peerPoll: Duration(milliseconds: 30),
);

/// Espera (en tiempo real) a que [condition] sea cierta.
Future<void> eventually(
  FutureOr<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 8),
  String reason = 'la condición',
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (await condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('Se agotó la espera de $reason');
}

/// Un móvil con la sincronización encendida contra [FakeSyncServer].
class SyncPhone {
  SyncPhone._(this.phone, this.transport);

  /// Crea un móvil conectado a [server].
  static Future<SyncPhone> create(
    FakeSyncServer server, {
    SyncTiming timing = kFastTiming,
    FakeSyncTransport? transport,
  }) async {
    final prefs = await mockPrefs();
    final t = transport ?? server.connect();
    final phone = FakePhone(
      prefs: prefs,
      syncHost: null,
      extraOverrides: [
        syncHostProvider.overrideWithValue(kTestHost),
        // Las invitaciones, en el mismo origen que el servidor de pruebas.
        invitationOriginProvider.overrideWithValue(''),
        syncTransportProvider.overrideWithValue(t),
        syncTimingProvider.overrideWithValue(timing),
      ],
    );
    final p = SyncPhone._(phone, t);
    // Arranca la sincronización, como hace main().
    phone.container.read(syncControllerProvider);
    return p;
  }

  /// El móvil de prueba.
  final FakePhone phone;

  /// Su cliente del servidor.
  final FakeSyncTransport transport;

  /// El contenedor de Riverpod.
  ProviderContainer get c => phone.container;

  /// La familia.
  FamilyController get family => c.read(familyControllerProvider.notifier);

  /// La sincronización.
  SyncController get sync => c.read(syncControllerProvider.notifier);

  /// Su estado.
  SyncStatus get status => c.read(syncControllerProvider);

  Future<FamilyState> _state() async =>
      c.read(familyControllerProvider).value ??
      await c.read(familyControllerProvider.future);

  /// Si ya hay familia en este móvil.
  Future<bool> hasFamily() async => (await _state()).hasFamily;

  /// El documento actual.
  Future<FamilyDoc> doc() async => (await _state()).doc;

  /// El documento en forma canónica, para comparar.
  Future<String> canonical() async => (await doc()).canonicalJson();

  /// La vista del documento.
  Future<FamilyView> view() async => (await _state()).view;

  /// Id de la lista.
  Future<String?> listId() async => (await _state()).listId;

  /// Crea la familia. Con un solo móvil no se sube nada: la sincronización
  /// queda a la espera del segundo.
  Future<void> createFamily([String name = 'Móvil A']) async {
    await family.createFamily(deviceName: name);
    await eventually(
      () => status.phase == SyncPhase.waitingForPeer,
      reason: 'la espera del segundo móvil',
    );
  }

  /// Crea la familia de un móvil que ya tiene otro emparejado (como los que
  /// sincronizaban antes de este cambio) y espera a que quede subida.
  Future<void> createPairedFamily([String name = 'Móvil A']) async {
    await family.createFamily(deviceName: name);
    await family.markPaired(peerName: 'Otro móvil');
    await eventually(
      () => status.phase == SyncPhase.synced,
      reason: 'la primera sincronización',
    );
  }

  /// Une este móvil a la familia de [other] con el QR de emparejar. Enseñar
  /// el QR pone a [other] a mirar si este móvil ya ha entrado.
  Future<void> joinFamilyOf(SyncPhone other, [String name = 'Móvil B']) async {
    final text = await other.c.read(pairingServiceProvider).qrTextForPairing();
    await c.read(pairingServiceProvider).joinFromQr(text, deviceName: name);
  }

  /// Un regalo de muestra.
  Future<void> putGift(
    String id,
    String title, {
    GiftStatus status = GiftStatus.idea,
    String? store,
    int? planned,
  }) => family.upsertGift(
    Gift(
      id: id,
      recipientId: 'aritz',
      title: title,
      status: status,
      rawStatus: status.name,
      store: store,
      plannedCents: planned,
      surprise: false,
      year: 2026,
    ),
  );

  /// Un regalo del documento, o `null`.
  Future<Gift?> gift(String id) async {
    final v = await view();
    for (final g in v.gifts) {
      if (g.id == id) {
        return g;
      }
    }
    return null;
  }

  void dispose() => phone.dispose();
}

/// Espera a que todos tengan el mismo documento.
Future<void> converge(List<SyncPhone> phones, {Duration? timeout}) =>
    eventually(
      () async {
        final first = await phones.first.canonical();
        for (final p in phones.skip(1)) {
          if (await p.canonical() != first) {
            return false;
          }
        }
        return true;
      },
      timeout: timeout ?? const Duration(seconds: 8),
      reason: 'que los móviles converjan',
    );
