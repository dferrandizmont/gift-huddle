import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/fresh_install.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/application/reparto_view_provider.dart';
import 'package:regalos/features/family/application/self_recipient_provider.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';
import 'package:regalos/features/family/data/secure_wipe.dart';
import 'package:regalos/features/lock/application/lock_controller.dart';
import 'package:regalos/features/review/application/review_providers.dart';
import 'package:regalos/features/review/application/review_service.dart';
import 'package:regalos/features/settings/application/appearance_provider.dart';
import 'package:regalos/features/settings/application/erase_all.dart';
import 'package:regalos/features/settings/application/locale_provider.dart';
import 'package:regalos/features/sync/application/sync_controller.dart';
import 'package:regalos/features/sync/data/sync_config.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';
import 'package:regalos/features/sync/domain/sync_keys.dart';
import 'package:regalos/features/sync/domain/sync_status.dart';

import '../helpers/fake_sync_server.dart';
import '../helpers/memory_stores.dart';
import '../helpers/pump_app.dart';
import '../review/review_service_test.dart' show FakeStoreReview;
import '../sync/sync_harness.dart' show eventually, kFastTiming, kTestHost;

/// Un almacén seguro que, cuando se le dice, falla al borrar una clave (como
/// el Keystore de Android cuando no responde).
class _StuckSecrets extends MemorySecretStore {
  bool stuck = false;

  @override
  Future<void> delete(String key) async {
    if (stuck) {
      throw StateError('el almacén seguro no responde');
    }
    await super.delete(key);
  }
}

/// Ficheros que, cuando se les dice, fallan al borrar (el disco).
class _StuckFiles extends MemoryFileStore {
  bool stuck = false;

  @override
  Future<void> delete(String name) async {
    if (stuck) {
      throw FileSystemException('no se puede borrar', name);
    }
    await super.delete(name);
  }
}

class _ReviewTrackingFiles extends MemoryFileStore {
  final reviewAccesses = <String>[];

  @override
  Future<Uint8List?> read(String name) {
    if (name == 'review.json') reviewAccesses.add('read');
    return super.read(name);
  }

  @override
  Future<void> writeAtomic(String name, Uint8List bytes) {
    if (name == 'review.json') reviewAccesses.add('write');
    return super.writeAtomic(name, bytes);
  }

  @override
  Future<void> delete(String name) {
    if (name == 'review.json') reviewAccesses.add('delete');
    return super.delete(name);
  }
}

/// «Borrar todo»: primero la copia del servidor (lo mismo que «Dejar de
/// sincronizar») y después todo lo de este móvil, que vuelve al primer uso.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSyncServer server;
  late Directory temp;
  final phones = <FakePhone>[];

  setUp(() {
    server = FakeSyncServer();
    temp = Directory.systemTemp.createTempSync('regalos_erase_');
  });

  tearDown(() {
    for (final p in phones) {
      p.dispose();
    }
    phones.clear();
    temp.deleteSync(recursive: true);
  });

  /// Un móvil con preferencias ya usadas y, si se da [transport], con
  /// servidor de sincronización.
  Future<FakePhone> newPhone({
    FakeSyncTransport? transport,
    MemorySecretStore? secrets,
    MemoryFileStore? files,
  }) async {
    final prefs = await mockPrefs({
      AppearanceNotifier.accentKey: 'sage',
      AppearanceNotifier.themeModeKey: 'dark',
      LocaleNotifier.localeKey: 'ca',
      RepartoViewNotifier.prefsKey: 'occasion',
    });
    final phone = FakePhone(
      prefs: prefs,
      temp: temp,
      secrets: secrets,
      files: files,
      syncHost: transport == null ? '' : null,
      extraOverrides: [
        if (transport != null) ...[
          syncHostProvider.overrideWithValue(kTestHost),
          // Las invitaciones, en el mismo origen que el servidor de pruebas.
          invitationOriginProvider.overrideWithValue(''),
          syncTransportProvider.overrideWithValue(transport),
          syncTimingProvider.overrideWithValue(kFastTiming),
        ],
      ],
    );
    phones.add(phone);
    // La marca de instalación, que pone el primer arranque (como main()).
    await phone.files.writeAtomic(kInstallMarkerFileName, Uint8List(0));
    // Arranca la sincronización, como hace main().
    phone.container.read(syncControllerProvider);
    return phone;
  }

  FamilyController familyOf(FakePhone p) =>
      p.container.read(familyControllerProvider.notifier);
  SyncStatus statusOf(FakePhone p) => p.container.read(syncControllerProvider);
  EraseAll eraserOf(FakePhone p) => p.container.read(eraseAllProvider);

  /// Una familia con una persona, un regalo, PIN, «Yo» y claves del móvil.
  Future<void> fill(FakePhone p, {bool paired = false}) async {
    final family = familyOf(p);
    await family.createFamily(deviceName: 'Móvil de prueba');
    await family.upsertRecipient(
      const Recipient(id: 'nora', name: 'Nora', colorIndex: 4, archived: false),
    );
    await family.upsertGift(
      const Gift(
        id: 'g1',
        recipientId: 'nora',
        title: 'Puzle de 48 piezas',
        status: GiftStatus.idea,
        rawStatus: 'idea',
        surprise: false,
        year: 2026,
      ),
    );
    await p.container.read(selfRecipientIdProvider.notifier).choose('nora');
    await p.container.read(deviceKeysStoreProvider).create();
    await p.container.read(lockControllerProvider.future);
    await p.container.read(lockControllerProvider.notifier).setPin('1234');
    if (paired) {
      await family.markPaired(peerName: 'Otro móvil');
      await eventually(
        () => statusOf(p).phase == SyncPhase.synced,
        reason: 'la primera sincronización',
      );
    }
  }

  Future<bool> hasFamily(FakePhone p) async =>
      (await p.container.read(familyControllerProvider.future)).hasFamily;

  /// Este móvil está como recién instalado.
  Future<void> expectFirstUse(FakePhone p) async {
    expect(await hasFamily(p), isFalse);
    expect(p.secrets.values, isEmpty, reason: 'el almacén seguro');
    expect(p.files.files.keys, [
      kInstallMarkerFileName,
    ], reason: 'el documento cifrado se va y la marca de instalación se queda');
    expect(p.secureWipes, 1, reason: 'se barre el almacén seguro entero');
    expect(p.prefs!.getKeys(), isEmpty);
    final lock = await p.container.read(lockControllerProvider.future);
    expect(lock.pinSet, isFalse);
    expect(lock.locked, isFalse);
    expect(lock.needsSetup, isTrue, reason: 'la próxima lista propone un PIN');
    expect(p.container.read(selfRecipientIdProvider), isNull);
    // Lo que venía de las preferencias vuelve a su valor de fábrica.
    final appearance = p.container.read(appearanceProvider);
    expect(appearance.themeMode, ThemeMode.system);
    expect(appearance.accent.name, isNot('sage'));
    expect(p.container.read(localeProvider), isNull);
    expect(p.container.read(repartoViewProvider), RepartoView.grid);
  }

  test('lo que se rellena en la prueba está de verdad guardado', () async {
    final p = await newPhone(transport: server.connect());
    await fill(p);
    expect(
      p.files.files.keys,
      unorderedEquals([kInstallMarkerFileName, kFamilyDocFileName]),
    );
    expect(
      p.secrets.values.keys,
      containsAll(<String>[
        'family.identity',
        'family.key',
        'family.localKey',
        'device.keys',
        'lock.pin',
        'lock.config',
      ]),
    );
    expect(p.container.read(appearanceProvider).themeMode, ThemeMode.dark);
    expect(p.container.read(localeProvider), const Locale('ca'));
  });

  test('con sincronización: borra la copia del servidor y todo lo de este '
      'móvil, que vuelve al primer uso', () async {
    final transport = server.connect();
    final p = await newPhone(transport: transport);
    await fill(p, paired: true);
    final syncId = await SyncKeys.syncId(familyOf(p).familyKey!);
    expect(server.hasList(syncId), isTrue);
    File('${temp.path}/regalos-2026-11-12-1000.regalos').writeAsStringSync('x');
    File('${temp.path}/otra-cosa.txt').writeAsStringSync('x');

    final eraser = eraserOf(p);
    expect(eraser.hasServerCopy, isTrue);
    await eraser.eraseServerCopy();
    expect(server.hasList(syncId), isFalse);
    expect(server.calls['delete'], 1);
    // Todavía no se ha tocado nada de este móvil.
    expect(await hasFamily(p), isTrue);

    await eraser.eraseLocal();
    await expectFirstUse(p);
    expect(statusOf(p).phase, SyncPhase.noFamily);
    expect(eraser.hasServerCopy, isFalse);
    // Los ficheros exportados se van; lo que no es de la app, no.
    expect(temp.listSync().map((e) => e.uri.pathSegments.last), [
      'otra-cosa.txt',
    ]);
    // Y no se vuelve a subir nada.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(server.hasList(syncId), isFalse);

    // Tras cerrar y abrir, sigue sin haber nada de antes.
    p.restart(temp: temp);
    expect(await hasFamily(p), isFalse);
  });

  test('sin red, el borrado del servidor falla y no cambia nada; se puede '
      'reintentar', () async {
    final transport = server.connect();
    final p = await newPhone(transport: transport);
    await fill(p, paired: true);
    final syncId = await SyncKeys.syncId(familyOf(p).familyKey!);
    final secrets = Map<String, String>.of(p.secrets.values);

    transport.offline = true;
    final eraser = eraserOf(p);
    await expectLater(
      eraser.eraseServerCopy(),
      throwsA(isA<SyncTransportException>()),
    );
    expect(await hasFamily(p), isTrue);
    expect(p.secrets.values, secrets);
    expect(p.files.files.keys, contains(kFamilyDocFileName));
    expect(server.hasList(syncId), isTrue);
    expect(statusOf(p).phase, isNot(SyncPhase.disabled));

    // Vuelve la red: el reintento borra la copia.
    transport.offline = false;
    await eraser.eraseServerCopy();
    expect(server.hasList(syncId), isFalse);
    await eraser.eraseLocal();
    await expectFirstUse(p);
  });

  test('sin red se puede borrar solo este móvil: la copia del servidor se '
      'queda', () async {
    final transport = server.connect();
    final p = await newPhone(transport: transport);
    await fill(p, paired: true);
    final syncId = await SyncKeys.syncId(familyOf(p).familyKey!);

    transport.offline = true;
    final eraser = eraserOf(p);
    await expectLater(
      eraser.eraseServerCopy(),
      throwsA(isA<SyncTransportException>()),
    );
    await eraser.eraseLocal();
    await expectFirstUse(p);
    expect(server.hasList(syncId), isTrue);
    // Aunque vuelva la red, este móvil ya no habla con el servidor.
    transport.offline = false;
    final calls = Map<String, int>.of(server.calls);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(server.calls, calls);
    expect(statusOf(p).phase, SyncPhase.noFamily);
  });

  test('con la sincronización ya apagada, un fallo del servidor no la '
      'enciende', () async {
    final transport = server.connect();
    final p = await newPhone(transport: transport);
    await fill(p, paired: true);
    await p.container.read(syncControllerProvider.notifier).setEnabled(false);
    expect(statusOf(p).phase, SyncPhase.disabled);

    transport.offline = true;
    await expectLater(
      eraserOf(p).eraseServerCopy(),
      throwsA(isA<SyncTransportException>()),
    );
    expect(statusOf(p).phase, SyncPhase.disabled);
  });

  test('con un solo móvil también pide el borrado al servidor, por si quedó '
      'la copia de una invitación', () async {
    final transport = server.connect();
    final p = await newPhone(transport: transport);
    await fill(p);
    expect(server.calls['delete'], isNull);
    final eraser = eraserOf(p);
    expect(eraser.hasServerCopy, isTrue);
    await eraser.eraseServerCopy();
    expect(server.calls['delete'], 1);
    await eraser.eraseLocal();
    await expectFirstUse(p);
  });

  test('sin servidor de sincronización solo borra lo de este móvil', () async {
    final p = await newPhone();
    await fill(p);
    final eraser = eraserOf(p);
    expect(eraser.hasServerCopy, isFalse);
    await eraser.eraseServerCopy();
    expect(await hasFamily(p), isTrue);
    await eraser.eraseLocal();
    await expectFirstUse(p);
  });

  test('después de borrar todo se puede empezar otra lista, que no hereda '
      'nada y sobrevive a cerrar la app', () async {
    final p = await newPhone();
    await fill(p);
    final oldList = (await p.container.read(familyControllerProvider.future))
        .listId;
    await eraserOf(p).eraseLocal();

    await familyOf(p).createFamily(deviceName: 'Otra vez');
    final fresh = await p.container.read(familyControllerProvider.future);
    expect(fresh.hasFamily, isTrue);
    expect(fresh.listId, isNot(oldList));
    expect(fresh.view.recipients, isEmpty);
    expect(fresh.view.gifts, isEmpty);
    // La marca de instalación sigue: el siguiente arranque en iPhone no se
    // toma por el primero y no vacía el llavero con la lista nueva dentro.
    expect(p.files.files.keys, contains(kInstallMarkerFileName));
    p.restart(temp: temp);
    expect(
      await clearKeychainOnFreshInstall(
        prefs: p.prefs!,
        files: p.files,
        wipeSecureStorage: p.container.read(secureStorageWipeProvider),
        isIOS: true,
      ),
      isFalse,
    );
    final again = await p.container.read(familyControllerProvider.future);
    expect(again.listId, fresh.listId);
  });

  test(
    'borrar todo no accede a un historial de valoración inexistente',
    () async {
      final files = _ReviewTrackingFiles();
      final p = await newPhone(files: files);
      await fill(p);

      await eraserOf(p).eraseLocal();

      expect(files.reviewAccesses, isEmpty);
      expect(files.files, isNot(contains('review.json')));
      await expectFirstUse(p);
    },
  );

  for (final (count, daysSinceLastRequest, limit) in [
    (1, 0, 'el plazo de 120 días'),
    (3, 121, 'el máximo de tres peticiones'),
  ]) {
    test('borrar todo conserva $limit al crear otra familia', () async {
      final files = _ReviewTrackingFiles();
      final p = await newPhone(files: files);
      final now = DateTime.utc(2026, 11, 20);
      final lastRequestedAt = now.subtract(
        Duration(days: daysSinceLastRequest),
      );
      final history = (count: count, lastRequestedAt: lastRequestedAt);
      await fill(p);
      final oldList = (await p.container.read(familyControllerProvider.future))
          .listId!;
      final preferences = p.container.read(localReviewPreferencesProvider);
      await preferences.writeHistory(history);
      final original = files.files['review.json'];
      expect(original, isNotNull);
      files.reviewAccesses.clear();

      await eraserOf(p).eraseLocal();
      expect(files.reviewAccesses, isEmpty);
      expect(files.files['review.json'], same(original));
      await p.prefs!.reload();
      expect(p.prefs!.getKeys(), isEmpty);

      await familyOf(p).createFamily(deviceName: 'Otra vez');
      p.restart(temp: temp);
      final fresh = await p.container.read(familyControllerProvider.future);
      expect(fresh.listId, isNot(oldList));
      expect(files.reviewAccesses, isEmpty);
      final restartedPreferences = p.container.read(
        localReviewPreferencesProvider,
      );
      final store = FakeStoreReview();
      await ReviewService(
        preferences: restartedPreferences,
        store: store,
        isWeb: false,
        isStoreBuild: true,
        canPresent: (id) => id == fresh.listId,
        clock: Clock.fixed(now),
      ).deliverySaved(familyId: fresh.listId!, before: 4, after: 5);

      expect(store.requests, 0);
      expect(await restartedPreferences.readHistory(), history);
    });
  }

  test('si el almacén seguro falla al borrar las claves una a una, lo demás '
      'se borra igual y la app queda sin familia', () async {
    final secrets = _StuckSecrets();
    final p = await newPhone(secrets: secrets);
    await fill(p);
    File('${temp.path}/regalos-2026-11-12-1000.regalos').writeAsStringSync('x');

    secrets.stuck = true;
    await expectLater(eraserOf(p).eraseLocal(), throwsStateError);

    // El error sale, pero no queda nada: el barrido del almacén seguro, el
    // documento, las preferencias y los ficheros exportados se hicieron.
    await expectFirstUse(p);
    expect(temp.listSync(), isEmpty);
    // Tras cerrar y abrir, sigue sin haber nada de antes.
    secrets.stuck = false;
    p.restart(temp: temp);
    expect(await hasFamily(p), isFalse);
  });

  test('si falla el disco al borrar el documento, el almacén seguro se barre '
      'igual: sin sus claves el documento ya no se puede leer', () async {
    final files = _StuckFiles();
    final p = await newPhone(files: files);
    await fill(p);
    File('${temp.path}/regalos-2026-11-12-1000.regalos').writeAsStringSync('x');

    files.stuck = true;
    await expectLater(
      eraserOf(p).eraseLocal(),
      throwsA(isA<FileSystemException>()),
    );

    expect(p.secureWipes, 1);
    expect(p.secrets.values, isEmpty, reason: 'ni claves ni PIN');
    expect(p.prefs!.getKeys(), isEmpty);
    expect(temp.listSync(), isEmpty);
    expect(await hasFamily(p), isFalse);
    final lock = await p.container.read(lockControllerProvider.future);
    expect(lock.pinSet, isFalse);
  });

  test(
    'un regalo que esperaba su «Deshacer» no reaparece ni rompe nada',
    () async {
      final p = await newPhone();
      await fill(p);
      expect(await familyOf(p).deleteGiftWithUndo('g1'), isTrue);
      await eraserOf(p).eraseLocal();
      await familyOf(p).flushPendingDeletes();
      await expectFirstUse(p);
    },
  );
}
