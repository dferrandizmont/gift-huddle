import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';
import 'package:regalos/features/sync/domain/sync_keys.dart';
import 'package:regalos/features/sync/domain/sync_status.dart';

import '../helpers/fake_sync_server.dart';
import 'sync_harness.dart';

/// Un cliente que puede dejar a medias un `GET` o un `DELETE`, para colocar
/// un ciclo de sincronización justo donde interesa.
class _GatedTransport extends FakeSyncTransport {
  _GatedTransport(super.server);

  Completer<void>? _getGate;
  Completer<void>? _deleteGate;

  /// Peticiones `GET` paradas en la puerta.
  int heldGets = 0;

  /// Peticiones `DELETE` paradas en la puerta.
  int heldDeletes = 0;

  void holdGets() => _getGate = Completer<void>();

  void releaseGets() {
    _getGate?.complete();
    _getGate = null;
  }

  void holdDeletes() => _deleteGate = Completer<void>();

  void releaseDeletes() {
    _deleteGate?.complete();
    _deleteGate = null;
  }

  @override
  Future<SyncGetResult> getList(
    SyncCredentials auth, {
    int? ifNoneMatch,
  }) async {
    final gate = _getGate;
    if (gate != null) {
      heldGets++;
      await gate.future;
    }
    return super.getList(auth, ifNoneMatch: ifNoneMatch);
  }

  @override
  Future<void> deleteList(SyncCredentials auth) async {
    final gate = _deleteGate;
    if (gate != null) {
      heldDeletes++;
      await gate.future;
    }
    return super.deleteList(auth);
  }
}

/// Revisión de seguridad: «Dejar de sincronizar» (y «Borrar todo») borra la
/// copia del servidor; ningún ciclo que estuviera en marcha, o que arranque
/// mientras tanto, puede volver a subirla después.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSyncServer server;
  late _GatedTransport transport;
  final phones = <SyncPhone>[];

  setUp(() {
    server = FakeSyncServer();
    transport = _GatedTransport(server);
  });

  tearDown(() {
    transport
      ..releaseGets()
      ..releaseDeletes();
    for (final p in phones) {
      p.dispose();
    }
    phones.clear();
  });

  Future<SyncPhone> pairedPhone() async {
    final p = await SyncPhone.create(server, transport: transport);
    phones.add(p);
    await p.createPairedFamily();
    return p;
  }

  test('un ciclo que ya había empezado cuando se apaga la sincronización no '
      'sube nada después', () async {
    final a = await pairedPhone();
    final syncId = await SyncKeys.syncId(a.family.familyKey!);

    // Un cambio local arranca un ciclo, que se queda a medias en su `GET`:
    // ya pasó la comprobación de «encendida».
    transport.holdGets();
    await a.putGift('g1', 'Pendiente de subir');
    await eventually(
      () => transport.heldGets == 1,
      reason: 'el ciclo a medias',
    );
    final puts = server.calls['put'];
    final version = server.versionOf(syncId);

    // Se apaga mientras tanto (lo primero que hace «Dejar de sincronizar»).
    final off = a.sync.setEnabled(false);
    await Future<void>.delayed(Duration.zero);
    transport.releaseGets();
    await off;

    expect(server.calls['put'], puts, reason: 'el ciclo no llega a subir');
    expect(server.versionOf(syncId), version);
    expect(a.status.phase, SyncPhase.disabled);
    // El cambio sigue en local y sube al volver a encender.
    await a.sync.setEnabled(true);
    expect(server.calls['put'], puts! + 1);
  });

  test('un ciclo que arranca durante «Dejar de sincronizar» no vuelve a subir '
      'la lista tras el DELETE', () async {
    final a = await pairedPhone();
    final syncId = await SyncKeys.syncId(a.family.familyKey!);
    // Hay algo pendiente de subir: el ciclo que arranque tendría qué enviar.
    await a.putGift('g1', 'Pendiente de subir');
    final puts = server.calls['put'];

    // El `DELETE` tarda (la red): mientras, arrancan más ciclos.
    transport.holdDeletes();
    final stop = a.sync.stopSyncing();
    // En el mismo instante, antes de que «Dejar de sincronizar» haya hecho
    // nada más que empezar.
    final first = a.sync.syncNow();
    await eventually(() => transport.heldDeletes == 1, reason: 'el DELETE');
    await first;
    // Y otro con el `DELETE` ya enviado, más un cambio local.
    await a.putGift('g2', 'Otro cambio');
    await a.sync.syncNow();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(server.calls['put'], puts, reason: 'nada sube durante el borrado');

    transport.releaseDeletes();
    await stop;
    expect(server.hasList(syncId), isFalse);
    expect(a.status.phase, SyncPhase.disabled);

    // Ni después: ni por el cierre 4404 del WebSocket ni por lo pendiente.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(server.hasList(syncId), isFalse);
    expect(server.calls['put'], puts);
    expect((await a.gift('g2'))!.title, 'Otro cambio');
  });

  test('si el servidor falla, «Dejar de sincronizar» deja la sincronización '
      'encendida como estaba y lo pendiente sube', () async {
    final a = await pairedPhone();
    final syncId = await SyncKeys.syncId(a.family.familyKey!);
    await a.putGift('g1', 'Pendiente de subir');

    transport.offline = true;
    await expectLater(
      a.sync.stopSyncing(),
      throwsA(isA<SyncTransportException>()),
    );
    transport.offline = false;
    await eventually(
      () => a.status.phase == SyncPhase.synced,
      reason: 'vuelve a sincronizar',
    );
    expect(server.hasList(syncId), isTrue);
  });
}
