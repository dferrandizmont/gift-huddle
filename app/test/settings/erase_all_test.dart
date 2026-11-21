import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/fresh_install.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/application/reparto_view_provider.dart';
import 'package:regalos/features/family/application/self_recipient_provider.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/family/data/secure_wipe.dart';
import 'package:regalos/features/lock/application/lock_controller.dart';
import 'package:regalos/features/review/application/review_providers.dart';
import 'package:regalos/features/review/application/review_service.dart';
import 'package:regalos/features/settings/application/appearance_provider.dart';
import 'package:regalos/features/settings/application/erase_all.dart';
import 'package:regalos/features/settings/application/locale_provider.dart';
import 'package:regalos/features/sharing/application/pairing_service.dart';
import 'package:regalos/features/sync/application/pairing_v2_controller.dart';
import 'package:regalos/features/sync/application/sync_controller.dart';
import 'package:regalos/features/sync/data/sync_config.dart';
import 'package:regalos/features/sync/data/sync_endpoint.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';
import 'package:regalos/features/sync/data/sync_transport_common.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';
import 'package:regalos/features/sync/domain/sync_keys.dart';
import 'package:regalos/features/sync/domain/sync_status.dart';

import '../helpers/fake_sync_server.dart';
import '../helpers/fake_worker_v2.dart';
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

class _RetiredV1Transport extends BaseSyncTransport {
  _RetiredV1Transport() : super(SyncEndpoint.parse('https://sync.test')!);

  final requests = <String>[];
  String responseBody = '<html>Gone</html>';

  @override
  Future<SyncResponse> send(
    String method,
    Uri uri, {
    SyncCredentials? auth,
    Object? body,
    Map<String, String> headers = const {},
  }) async {
    requests.add(method);
    return SyncResponse(
      410,
      const {},
      Uint8List.fromList(utf8.encode(responseBody)),
    );
  }

  @override
  Stream<SyncEvent> watch(SyncCredentials auth) => const Stream.empty();

  @override
  void close() {}
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
    SyncTransport? transport,
    SyncV2Transport? v2Transport,
    MemorySecretStore? secrets,
    MemoryFileStore? files,
    SyncTiming timing = kFastTiming,
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
          if (v2Transport != null)
            syncV2TransportProvider.overrideWithValue(v2Transport),
          syncTimingProvider.overrideWithValue(timing),
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

  test(
    'una familia recién creada se borra aunque el móvil esté sin red',
    () async {
      final transport = server.connect();
      final p = await newPhone(transport: transport);
      await familyOf(p).createFamilyWith(deviceName: 'Aritz', region: 'ES');
      transport.offline = true;
      final eraser = eraserOf(p);
      await eraser.eraseServerCopy();
      expect(server.calls, isEmpty);
      await eraser.eraseLocal();
      await expectFirstUse(p);
    },
  );

  test(
    'una copia v1 que quedó de una invitación se borra del servidor',
    () async {
      final p = await newPhone(transport: server.connect());
      await fill(p);
      final sync = p.container.read(syncControllerProvider.notifier);
      final auth = await sync.readyCredentials();
      sync.inviteSettled();
      expect(server.hasList(auth.syncId), isTrue);

      final eraser = eraserOf(p);
      await eraser.eraseServerCopy();
      expect(server.hasList(auth.syncId), isFalse);
      expect(server.calls['delete'], 1);
      await eraser.eraseLocal();
      await expectFirstUse(p);
    },
  );

  final prepareV2 = Provider(
    (ref) =>
        () => ensureV2Family(ref),
  );

  test(
    'borra la copia v1 que subió el otro móvil aunque caducara el sondeo',
    () async {
      final a = await newPhone(transport: server.connect());
      await fill(a);
      final qr = await a.container
          .read(pairingServiceProvider)
          .qrTextForPairing();
      await a.container.read(syncControllerProvider.notifier).syncNow();
      final syncId = await SyncKeys.syncId(familyOf(a).familyKey!);
      expect(server.hasList(syncId), isFalse);
      a.restart(temp: temp);

      final b = await newPhone(transport: server.connect());
      await b.container
          .read(pairingServiceProvider)
          .joinFromQr(qr, deviceName: 'Nora');
      await eventually(() => statusOf(b).phase == SyncPhase.synced);
      expect(server.hasList(syncId), isTrue);
      b.restart(temp: temp);

      final later = clock.now().add(const Duration(days: 4));
      await withClock(Clock.fixed(later), () async {
        final reads = server.calls['get'];
        await a.container.read(syncControllerProvider.notifier).syncNow();
        expect(a.prefs!.getStringList('sync.peerWait'), isNull);
        expect(server.calls['get'], reads);
        expect((await familyOf(a).future).paired, isFalse);

        a.restart(temp: temp);
        await a.container.read(syncControllerProvider.notifier).syncNow();
        await eraserOf(a).eraseServerCopy();
        expect(server.calls['delete'], 1);
        expect(server.hasList(syncId), isFalse);
        await eraserOf(a).eraseLocal();
        await expectFirstUse(a);
      });
    },
  );

  test(
    'una familia v2 nunca publicada se borra tras el 404 del Worker',
    () async {
      final worker = FakeWorkerV2();
      final p = await newPhone(
        transport: server.connect(),
        v2Transport: worker.client(),
      );
      await fill(p);
      final local = await p.container.read(prepareV2)();
      expect(worker.hasList(local.identity.syncId), isFalse);
      expect(worker.calls, isEmpty);
      worker.tamper = (method, uri, response) {
        expect(method, 'GET');
        expect(uri.path, '/v2/lists/${local.identity.syncId}');
        expect(response.status, 404);
        expect(response.json(), {'error': 'not_found'});
        // La respuesta ya es definitiva, aunque después falle la red.
        worker.offline = true;
        return response;
      };

      final eraser = eraserOf(p);
      await eraser.eraseServerCopy();
      expect(worker.calls, {'GET list': 1});
      expect(server.calls, isEmpty);
      await eraser.eraseLocal();
      await expectFirstUse(p);
    },
  );

  test('al actualizar se borra la copia v1 aunque la versión anterior ya '
      'había quitado la fecha del sondeo', () async {
    final a = await newPhone(transport: server.connect());
    await fill(a);
    final qr = await a.container
        .read(pairingServiceProvider)
        .qrTextForPairing();
    await a.container.read(syncControllerProvider.notifier).syncNow();
    final syncId = await SyncKeys.syncId(familyOf(a).familyKey!);

    // El QR se mostró en una versión que solo guardaba la fecha del sondeo.
    await a.prefs!.remove('sync.sharedQr');
    await a.prefs!.remove('sync.peerWait');
    a.restart(temp: temp);

    // El invitado usa el QR después de que el anfitrión dejara de sondear.
    final b = await newPhone(transport: server.connect());
    await b.container
        .read(pairingServiceProvider)
        .joinFromQr(qr, deviceName: 'Nora');
    await eventually(() => statusOf(b).phase == SyncPhase.synced);
    expect(server.hasList(syncId), isTrue);
    b.restart(temp: temp);

    await a.container.read(syncControllerProvider.notifier).syncNow();
    expect((await familyOf(a).future).paired, isFalse);
    expect(a.prefs!.getStringList('sync.peerWait'), isNull);
    await eraserOf(a).eraseServerCopy();
    expect(server.calls['delete'], 1);
    expect(server.hasList(syncId), isFalse);
  });

  for (final publishV2 in [false, true]) {
    final v2Outcome = publishV2 ? 'DELETE v2 correcto' : '404 v2';
    test('tras $v2Outcome, un fallo al retirar la v1 se puede '
        'reintentar tras reiniciar', () async {
      final transport = server.connect();
      final worker = FakeWorkerV2();
      final p = await newPhone(
        transport: transport,
        v2Transport: worker.client(),
      );
      await fill(p, paired: true);
      final oldSyncId = await SyncKeys.syncId(familyOf(p).familyKey!);
      final local = await p.container.read(prepareV2)();
      if (publishV2) {
        final controller = p.container.read(syncControllerProvider.notifier);
        controller.setV2Pairing(true);
        await controller.syncNow();
      }
      final v2Key = familyOf(p).familyKey;
      final store = p.container.read(familyStoreProvider);
      final legacy = await store.readLegacyV1();
      expect(legacy, isNotNull);
      expect(worker.hasList(local.identity.syncId), publishV2);
      expect(server.hasList(oldSyncId), isTrue);

      transport.offline = true;
      await expectLater(
        eraserOf(p).eraseServerCopy(),
        throwsA(
          isA<SyncTransportException>().having(
            (error) => error.failure,
            'failure',
            SyncFailure.network,
          ),
        ),
      );
      expect(worker.hasList(local.identity.syncId), isFalse);
      expect(worker.calls['DELETE list'] ?? 0, publishV2 ? 1 : 0);
      expect(await store.readLegacyV1(), legacy);
      expect((await store.readSyncV2())!.syncId, local.identity.syncId);
      expect(familyOf(p).familyKey, v2Key);

      p.restart(temp: temp);
      await p.container.read(syncControllerProvider.notifier).syncNow();
      transport.offline = false;
      transport.deleteError = const SyncTransportException(
        SyncFailure.server,
        '503',
      );
      final eraser = eraserOf(p);
      await expectLater(
        eraser.eraseServerCopy(),
        throwsA(
          isA<SyncTransportException>().having(
            (error) => error.failure,
            'failure',
            SyncFailure.server,
          ),
        ),
      );
      expect(server.hasList(oldSyncId), isTrue);
      expect(
        await p.container.read(familyStoreProvider).readLegacyV1(),
        legacy,
      );
      transport.deleteError = null;
      await eraser.eraseServerCopy();
      expect(server.hasList(oldSyncId), isFalse);
      expect(
        await p.container.read(familyStoreProvider).readLegacyV1(),
        isNull,
      );
      await eraser.eraseLocal();
      await expectFirstUse(p);
    });
  }

  for (final (method, status, responseBody) in [
    ('GET', 403, '{"error":"forbidden_role"}'),
    ('DELETE', 409, '{"error":"renewal_close_pending"}'),
    ('GET', 404, '<html>Not Found</html>'),
    ('DELETE', 404, '{"error":"wrong_route"}'),
    ('GET', 401, '<html>Unauthorized</html>'),
    ('GET', 410, '{"error":"gone"}'),
    ('DELETE', 401, '{"error":"unauthorized","extra":true}'),
    ('DELETE', 410, ''),
    ('POST', 401, '<html>Unauthorized</html>'),
    ('POST', 410, '{"error":"gone"}'),
  ]) {
    test(
      'Dejar de sincronizar conserva el estado tras $method $status inesperado',
      () async {
        final worker = FakeWorkerV2();
        String? stoppedPath;
        final p = await newPhone(
          transport: server.connect(),
          v2Transport: SyncV2Client(
            base: Uri.parse('https://sync.test'),
            openSocket: worker.socket,
            sendRequest: (verb, uri, {body, headers = const {}}) async {
              if (verb == method && uri.path == stoppedPath) {
                return SyncResponse(
                  status,
                  const {},
                  Uint8List.fromList(utf8.encode(responseBody)),
                );
              }
              return worker.send(verb, uri, body: body, headers: headers);
            },
          ),
        );
        await fill(p);
        final local = await p.container.read(prepareV2)();
        final store = p.container.read(familyStoreProvider);
        await store.enableRemoteSync();
        final controller = p.container.read(syncControllerProvider.notifier);
        await controller.syncNow();
        final before = statusOf(p);
        expect(before.phase, SyncPhase.synced);
        final id = local.identity.syncId;
        final key = familyOf(p).familyKey;
        final proof = await store.readV1ProofKey();
        expect(proof, isNotNull);
        final revoking = method == 'POST';
        if (revoking) {
          worker.addCredentialForTesting(id, 'nora-phone', Uint8List(32));
        }
        stoppedPath = '/v2/lists/$id${revoking ? '/revoke' : ''}';

        await expectLater(
          controller.stopSyncing(),
          throwsA(
            isA<SyncTransportException>().having(
              (error) => error.failure,
              'failure',
              SyncFailure.server,
            ),
          ),
        );
        expect(statusOf(p), same(before));
        expect((await store.readSyncV2())!.syncId, id);
        expect(familyOf(p).familyKey, key);
        expect(await store.readV1ProofKey(), proof);
        expect(worker.hasList(id), isTrue);
        stoppedPath = null;
        if (revoking) {
          final deviceId = local.identity.deviceId;
          expect(worker.devicesOf(id)[deviceId], isFalse);
          expect(server.calls['delete'], isNull);
          await controller.stopSyncing();
          expect(worker.devicesOf(id), {deviceId: true, 'nora-phone': false});
          expect((await store.readSyncV2())!.syncId, isNot(id));
        } else {
          await controller.syncNow();
          expect(statusOf(p).phase, SyncPhase.synced);
        }
      },
    );
  }

  test('un 403 inesperado deja que se suba la edición pendiente sin '
      'pulsar Sincronizar ahora', () async {
    final worker = FakeWorkerV2();
    final p = await newPhone(
      transport: server.connect(),
      v2Transport: worker.client(),
      timing: const SyncTiming(debounce: Duration(seconds: 1)),
    );
    await fill(p);
    final local = await p.container.read(prepareV2)();
    final id = local.identity.syncId;
    final store = p.container.read(familyStoreProvider);
    await store.enableRemoteSync();
    final controller = p.container.read(syncControllerProvider.notifier);
    await controller.syncNow();
    final before = worker.calls['PUT list'] ?? 0;

    worker.tamper = (method, uri, response) {
      if (method != 'GET' || uri.path != '/v2/lists/$id') return response;
      worker.tamper = null;
      return SyncResponse(
        403,
        const {},
        Uint8List.fromList(utf8.encode('{"error":"forbidden_role"}')),
      );
    };
    await familyOf(p).upsertRecipient(
      const Recipient(id: 'leo', name: 'Leo', colorIndex: 3, archived: false),
    );
    await expectLater(
      controller.stopSyncing(),
      throwsA(
        isA<SyncTransportException>().having(
          (error) => error.failure,
          'failure',
          SyncFailure.server,
        ),
      ),
    );
    expect(worker.calls['PUT list'] ?? 0, before);
    await eventually(
      () => (worker.calls['PUT list'] ?? 0) == before + 1,
      reason: 'subida automática de la edición pendiente',
    );
    await eventually(() => statusOf(p).phase == SyncPhase.synced);
  });

  for (final (method, status, code) in [
    ('GET', 403, 'revoked'),
    ('GET', 403, 'credential_replaced'),
    ('GET', 401, 'unauthorized'),
    ('GET', 410, 'retired'),
    ('DELETE', 410, 'retired'),
  ]) {
    test('retira la copia v1 tras $method $status $code', () async {
      final worker = FakeWorkerV2();
      final p = await newPhone(
        transport: server.connect(),
        v2Transport: worker.client(),
      );
      await fill(p, paired: true);
      final oldSyncId = await SyncKeys.syncId(familyOf(p).familyKey!);
      final local = await p.container.read(prepareV2)();
      final id = local.identity.syncId;
      final store = p.container.read(familyStoreProvider);
      final controller = p.container.read(syncControllerProvider.notifier);
      controller.setV2Pairing(true);
      await controller.syncNow();
      expect(server.hasList(oldSyncId), isTrue);
      expect(await store.readLegacyV1(), isNotNull);

      var matched = false;
      worker.tamper = (verb, uri, response) {
        if (verb != method || uri.path != '/v2/lists/$id') return response;
        matched = true;
        return SyncResponse(
          status,
          const {},
          Uint8List.fromList(utf8.encode(jsonEncode({'error': code}))),
        );
      };
      await controller.stopSyncing();
      expect(matched, isTrue);
      expect(statusOf(p).phase, SyncPhase.disabled);
      expect(server.calls['delete'], 1);
      expect(server.hasList(oldSyncId), isFalse);
      expect(await store.readLegacyV1(), isNull);
      expect((await store.readSyncV2())!.syncId, isNot(id));
    });
  }

  test('un 410 v1 con HTML conserva la retirada pendiente tras perder '
      'el acceso v2, hasta recibir gone del Worker', () async {
    final worker = FakeWorkerV2();
    final transport = _RetiredV1Transport();
    final p = await newPhone(
      transport: transport,
      v2Transport: worker.client(),
    );
    await fill(p);
    final controller = p.container.read(syncControllerProvider.notifier);
    await controller.setEnabled(false);
    await familyOf(p).markPaired(peerName: 'Nora');
    final local = await p.container.read(prepareV2)();
    final id = local.identity.syncId;
    final store = p.container.read(familyStoreProvider);
    expect(await store.readLegacyV1(), isNotNull);
    worker.tamper = (method, uri, response) =>
        method == 'GET' && uri.path == '/v2/lists/$id'
        ? SyncResponse(
            403,
            const {},
            Uint8List.fromList(utf8.encode('{"error":"revoked"}')),
          )
        : response;

    await expectLater(
      controller.stopSyncing(),
      throwsA(
        isA<SyncTransportException>().having(
          (error) => error.failure,
          'failure',
          SyncFailure.server,
        ),
      ),
    );
    expect(transport.requests, ['GET']);
    expect(await store.readLegacyV1(), isNotNull);
    expect((await store.readSyncV2())!.syncId, id);
    expect(statusOf(p).phase, SyncPhase.disabled);

    transport.responseBody = '{"error":"gone"}';
    await controller.stopSyncing();
    expect(transport.requests, ['GET', 'GET']);
    expect(await store.readLegacyV1(), isNull);
    expect((await store.readSyncV2())!.syncId, isNot(id));
    expect(statusOf(p).phase, SyncPhase.disabled);
  });

  test('un 403 revoked permite borrar este móvil', () async {
    final worker = FakeWorkerV2();
    final p = await newPhone(
      transport: server.connect(),
      v2Transport: worker.client(),
    );
    await fill(p);
    await p.container.read(pairingV2HostProvider.notifier).start();
    final local = await p.container.read(prepareV2)();
    final syncId = local.identity.syncId;
    worker.tamper = (method, uri, response) =>
        method == 'GET' && uri.path == '/v2/lists/$syncId'
        ? SyncResponse(
            403,
            const {},
            Uint8List.fromList(utf8.encode('{"error":"revoked"}')),
          )
        : response;

    final eraser = eraserOf(p);
    await eraser.eraseServerCopy();
    expect(worker.hasList(syncId), isTrue);
    expect(worker.calls['DELETE list'], isNull);
    await eraser.eraseLocal();
    await expectFirstUse(p);
  });

  test('una credencial v2 sustituida permite borrar este móvil', () async {
    final worker = FakeWorkerV2();
    final p = await newPhone(
      transport: server.connect(),
      v2Transport: worker.client(),
    );
    await fill(p);
    await p.container.read(pairingV2HostProvider.notifier).start();
    final local = await p.container.read(prepareV2)();
    final id = local.identity;
    final replacement = await local.keys.withNewServiceCredential();
    worker.replaceRecoveryCredential(
      id.syncId,
      id.deviceId,
      encodeBase64Url(await replacement.serviceCredentialVerifier()),
    );

    final eraser = eraserOf(p);
    await eraser.eraseServerCopy();
    expect(worker.hasList(id.syncId), isTrue);
    expect(worker.calls['DELETE list'], isNull);
    await eraser.eraseLocal();
    await expectFirstUse(p);
  });

  test('una invitación v2 con un solo móvil conserva el aviso sin red y '
      'permite borrar la copia al reintentar', () async {
    final worker = FakeWorkerV2();
    final p = await newPhone(
      transport: server.connect(),
      v2Transport: worker.client(),
    );
    await fill(p);
    await p.container.read(pairingV2HostProvider.notifier).start();
    expect(
      p.container.read(pairingV2HostProvider).phase,
      PairingV2HostPhase.waiting,
    );
    final syncId =
        (await p.container.read(familyStoreProvider).readSyncV2())!.syncId;
    expect(worker.hasList(syncId), isTrue);

    final eraser = eraserOf(p);
    worker.offline = true;
    await expectLater(
      eraser.eraseServerCopy(),
      throwsA(
        isA<SyncTransportException>().having(
          (error) => error.failure,
          'failure',
          SyncFailure.network,
        ),
      ),
    );
    expect(await hasFamily(p), isTrue);
    expect(worker.hasList(syncId), isTrue);

    worker.offline = false;
    worker.tamper = (method, uri, response) =>
        method == 'GET' && uri.path == '/v2/lists/$syncId'
        ? SyncResponse(503, const {}, Uint8List(0))
        : response;
    await expectLater(
      eraser.eraseServerCopy(),
      throwsA(
        isA<SyncTransportException>().having(
          (error) => error.failure,
          'failure',
          SyncFailure.server,
        ),
      ),
    );
    expect(worker.hasList(syncId), isTrue);

    worker.tamper = null;
    await eraser.eraseServerCopy();
    expect(worker.hasList(syncId), isFalse);
    expect(worker.calls['DELETE list'], 1);
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
