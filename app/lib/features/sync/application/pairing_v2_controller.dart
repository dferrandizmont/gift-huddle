// Emparejamiento v2 en la app: el anfitrión (QR «Está aquí» y enlace «Está
// lejos») y el invitado, con migración de v1 a v2 al empezar (ADR 0004).
// La interfaz solo lee estos estados y llama a sus métodos.
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/device/device_name.dart';
import '../../../core/sync/device_keys.dart';
import '../../../core/sync/device_registry.dart';
import '../../../core/sync/envelope.dart' show FamilyKey;
import '../../../core/sync/hlc.dart';
import '../../../core/sync/pairing_v2.dart';
import '../../family/application/family_controller.dart';
import '../../family/data/device_keys_store.dart';
import '../../family/data/family_store.dart';
import '../data/sync_config.dart';
import '../data/sync_transport.dart';
import '../data/sync_transport_v2.dart';
import '../data/sync_transport_common.dart';
import '../../web_device/data/guard_client.dart';
import '../../web_device/data/vault_crypto.dart';
import '../invites/invite_link.dart';
import 'app_sync_v2_local.dart';
import 'common_v2_cutover.dart' show kCommonFormatLatest;
import 'family_devices.dart' show leaveFamily, othersHaveAccess;
import 'family_snapshot.dart';
import 'generation_v2.dart';
import 'invite_poll_pacer.dart';
import 'migration_v2.dart';
import 'pairing_v2_flow.dart';
import 'recovery_providers.dart'
    show RecoveryApplicationException, requireNoPendingRestore;
import 'sync_controller.dart';
import 'sync_v2_engine.dart';

// Solo etiquetas de código y tipos: nunca el mensaje, la pila ni la respuesta.
String _failureCode(String phase, Object error) {
  final kind = error is SyncTransportException
      ? 'SyncTransportException.${error.failure.name}'
      : error.runtimeType.toString();
  final code = '$phase:$kind';
  debugPrint('pairingV2 $code');
  return code;
}

/// Si esta versión empareja en v2: hay servidor y cliente v2.
final pairingV2AvailableProvider = Provider<bool>(
  (ref) => ref.watch(syncV2TransportProvider) != null,
);

/// Si hay que avisar en Ajustes › Móviles de la familia de que hay que
/// volver a conectar los móviles: la familia sigue en v1 con otro móvil
/// emparejado, o ya migró pero queda alguno que escribió en v1 y no ha
/// vuelto a conectarse.
final syncReconnectNeededProvider = FutureProvider<bool>((ref) async {
  if (!ref.watch(pairingV2AvailableProvider)) return false;
  final fam = await ref.watch(familyControllerProvider.future);
  final identity = fam.identity;
  if (identity == null) return false;
  final store = ref.read(familyStoreProvider);
  final v2 = await store.readSyncV2();
  if (v2 == null) return identity.paired;
  return await store.readLegacyV1() != null;
});

/// Pasa la familia de este móvil a v2 si todavía está en v1 y devuelve lo
/// local de v2. Antes recoge los cambios pendientes de v1 (una vuelta, si
/// estaba emparejado) y guarda la clave v1 para fusionar lo que escriban
/// los que sigan en v1 y borrar después esa copia.
///
/// Todo pasa por un pendiente ([PendingV2]) escrito antes del documento: si
/// se corta, se termina con la misma clave nueva. Un documento que ya dice v2
/// sin identidad v2 (una migración cortada sin pendiente, o una marca que
/// llegó por la lista v1) estrena siempre clave: la que tiene el móvil la
/// conocen los de v1 (hallazgo 7).
Future<AppSyncV2Local> ensureV2Family(Ref ref) async {
  // La última vuelta v1 pide la misma cola al comprobar si ya hay v2.
  // Se espera antes de tomarla; dentro se vuelve a cargar todo el estado.
  final fam = await familySnapshot(ref);
  if (syncProtocolOf(fam.doc) == 1 && fam.identity?.paired == true) {
    await ref.read(syncControllerProvider.notifier).syncNow();
  }
  return ref
      .read(v2FamilyLockProvider)
      .run(() => ensureV2FamilyWithinLock(ref));
}

/// The caller owns v2FamilyLockProvider; this function never reacquires it.
Future<AppSyncV2Local> ensureV2FamilyWithinLock(Ref ref) async {
  await finishPendingV2(ref);
  final existing = await AppSyncV2Local.load(ref);
  if (existing != null) return existing;
  final store = ref.read(familyStoreProvider);
  final family = ref.read(familyControllerProvider.notifier);
  final keysStore = ref.read(deviceKeysStoreProvider);
  final fam = await familySnapshot(ref);
  final identity = fam.identity;
  final v1Key = family.familyKey;
  if (identity == null || v1Key == null) {
    throw StateError('no hay familia');
  }
  final protocol = syncProtocolOf(fam.doc);
  final keys = await keysStore.read() ?? await keysStore.create();
  if (protocol == 1) {
    final migration = await migrateToV2(
      v1Doc: fam.doc,
      clock: HlcClock(node: identity.node, last: fam.doc.maxStamp),
      keys: keys,
      deviceId: identity.node,
      personId: identity.selfRecipientId,
    );
    // Lo primero, la clave y el syncId nuevos: el documento con la marca va
    // después y la identidad v2, la última.
    await store.savePendingV2(
      PendingV2(
        key: migration.familyKey,
        syncId: migration.identity.syncId,
        fromV1: true,
      ).toJson(),
    );
    await store.saveRegistry(migration.registry);
    if (identity.paired) {
      await store.saveLegacyV1(
        LegacyV1(
          listId: identity.listId,
          key: v1Key,
          since: clock.now(),
          nodes: writerNodesOf(fam.doc),
        ).toJson(),
      );
      await store.saveV1ProofKey(null);
    } else {
      // Sin emparejar en v1 también pudo leer su QR otro móvil que este no
      // llegó a ver: la clave se guarda solo para probarla (hallazgo 6).
      await store.saveV1ProofKey({
        'l': identity.listId,
        'k': v1Key.toBase64Url(),
        's': clock.now().millisecondsSinceEpoch,
      });
    }
    await store.saveSyncV2State(const V2SyncState().toJson());
    // El documento con la marca va antes que la identidad v2: desde la marca
    // este móvil ya no habla en v1 (ver `SyncController`), y con la
    // identidad, en v2.
    await family.installV2(
      listId: identity.listId,
      node: identity.node,
      key: migration.familyKey,
      doc: migration.common,
    );
    await store.saveSyncV2(migration.identity);
    await store.savePendingV2(null);
  } else {
    // El documento dice v2 y no hay identidad ni pendiente: clave nueva
    // siempre, nunca la que tiene este móvil.
    await store.savePendingV2((await PendingV2.fresh(fromV1: true)).toJson());
    await finishPendingV2(ref);
  }
  final local = await AppSyncV2Local.load(ref);
  if (local == null) throw StateError('no se ha podido pasar a v2');
  return local;
}

// ------------------------------------------------------------- anfitrión

/// En qué punto está el emparejamiento que ofrece este móvil.
enum PairingV2HostPhase {
  /// Nada en marcha.
  idle,

  /// La familia sigue en v1 con otros móviles conectados: pasarla a v2 no se
  /// puede deshacer y hay que confirmarlo antes
  /// ([PairingV2HostController.confirmMigration]; hallazgo 8).
  confirmMigration,

  /// Pasando a v2 si hace falta y creando la invitación.
  preparing,

  /// Enseñando el QR o el enlace; nadie ha respondido.
  waiting,

  /// El otro móvil ha respondido: hay que comparar el código.
  compare,

  /// Los códigos coinciden y el otro móvil dice ser de una persona: hay que
  /// confirmarlo aparte ([PairingV2HostController.confirmPerson]; hallazgo
  /// 3).
  confirmPerson,

  /// Publicando la ficha y aprobando.
  approving,

  /// El otro móvil ya puede entrar.
  done,

  /// «No coinciden», cancelado o caducado: la invitación ya no vale.
  cancelled,

  /// No se ha podido.
  failed,
}

/// Estado del emparejamiento del anfitrión.
@immutable
class PairingV2HostState {
  /// Crea el estado.
  const PairingV2HostState(
    this.phase, {
    this.link,
    this.code,
    this.guestWithoutPerson = false,
    this.guestPersonId,
    this.guestPersonName,
    this.notReady = false,
    this.failureCode,
    this.needsNewWebQr = false,
  });

  /// Fase.
  final PairingV2HostPhase phase;

  /// Enlace de la invitación (`https://<origen>/i#<id>`): lo lleva el QR y
  /// es lo que se comparte. No lleva ninguna clave.
  final String? link;

  /// El código de seis cifras (solo en [PairingV2HostPhase.compare] y
  /// después).
  final String? code;

  /// El otro móvil no ha elegido persona: la pantalla tiene que decirlo y
  /// confirmarlo a propósito (N2).
  final bool guestWithoutPerson;

  /// La persona que dice ser el otro móvil (id estable), o null.
  final String? guestPersonId;

  /// Su nombre en la copia de este móvil (para «Este móvil dice ser de…»).
  final String? guestPersonName;

  /// Falló porque no hay servidor, la sincronización está apagada o no hay
  /// red.
  final bool notReady;

  /// Diagnóstico sin datos de la familia, ids ni claves.
  final String? failureCode;

  /// invite_exists: ask the browser for a fresh QR, never retry this id.
  final bool needsNewWebQr;

  PairingV2HostState _as(PairingV2HostPhase next) => PairingV2HostState(
    next,
    link: link,
    code: code,
    guestWithoutPerson: guestWithoutPerson,
    guestPersonId: guestPersonId,
    guestPersonName: guestPersonName,
    failureCode: failureCode,
  );
}

/// El emparejamiento v2 que ofrece este móvil.
class PairingV2HostController extends Notifier<PairingV2HostState> {
  WebPairingQr? _webQr;
  String? _webPerson;
  PairingV2Host? _host;
  Timer? _timer;
  InvitePollPacer? _pacer;
  int _run = 0;

  /// Sube solo al empezar un emparejamiento ([_start]): una cancelación en
  /// vuelo se rinde si ha empezado otro, no si solo se ha cerrado la pantalla.
  int _starts = 0;

  @override
  PairingV2HostState build() {
    ref.onDispose(_stop);
    return const PairingV2HostState(PairingV2HostPhase.idle);
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Si hay un sondeo programado (las pruebas comprueban que se para).
  @visibleForTesting
  bool get polling => _timer?.isActive ?? false;

  /// Si empezar pasaría a v2 una familia v1 que tiene otros móviles
  /// conectados (lo que no se puede deshacer).
  Future<bool> _migrationNeedsConsent() async {
    final store = ref.read(familyStoreProvider);
    if (await store.readSyncV2() != null) return false;
    final identity = (await familySnapshot(ref)).identity;
    return identity != null && identity.paired;
  }

  /// Empieza (o vuelve a empezar) un emparejamiento. Si la familia sigue en
  /// v1 con otros móviles conectados, primero pide confirmación
  /// ([PairingV2HostPhase.confirmMigration]) y no toca nada.
  Future<void> start() {
    _webQr = null;
    _webPerson = null;
    return _start(migrationConfirmed: false);
  }

  /// Mobile UI: scan, choose a live person, then call this method. No offer is
  /// created until both QR and person have been supplied and validated.
  Future<void> startWeb(
    String qr, {
    required String guestPerson,
    String origin = kWebPairingOrigin,
  }) async {
    final parsed = WebPairingQr.parse(qr, origin: origin);
    final family = await familySnapshot(ref);
    if (!family.fullView.recipients.any((p) => p.id == guestPerson)) {
      throw const PairingException('esa persona no existe');
    }
    _webQr = parsed;
    _webPerson = guestPerson;
    await _start(migrationConfirmed: false);
  }

  /// Mobile credential only. The header is just a route identifier here;
  /// salt/token/version are not sent by GuardClient.resume.
  Future<void> resumeWebUnlock(String deviceId, {GuardClient? guard}) async {
    final local = await AppSyncV2Local.load(ref);
    if (local == null) throw StateError('no hay familia v2');
    final family = await familySnapshot(ref);
    final view = await local.registry().then(
      (r) => r.viewFor(
        me: local.identity.deviceId,
        mySigningKey: local.keys.publicKeys.signing,
        livePeople: family.fullView.recipients.map((r) => r.id).toSet(),
      ),
    );
    if (view.device(deviceId)?.kind != DeviceKind.web) {
      throw const PairingException('esa ficha no es web');
    }
    final rawTransport = ref.read(syncTransportProvider);
    final client =
        guard ??
        (rawTransport is BaseSyncTransport
            ? GuardClient(
                base: rawTransport.endpoint.base,
                send: (method, uri, {body, headers = const {}}) => rawTransport
                    .send(method, uri, body: body, headers: headers),
              )
            : throw StateError('no hay transporte de guarda'));
    await client.resume(
      VaultHeader(
        syncId: local.identity.syncId,
        deviceId: deviceId,
        salt: const [],
        guardToken: const [],
        guardVersion: 1,
      ),
      local.keys.serviceCredential,
    );
  }

  /// La clave v1 que este móvil conserva de [listId] tras migrar, o null: con
  /// ella la invitación prueba a los móviles de v1 que es su misma lista
  /// (hallazgo 6).
  Future<FamilyKey?> _legacyV1Key(String listId) async {
    final store = ref.read(familyStoreProvider);
    final raw = await store.readLegacyV1();
    if (raw != null) {
      try {
        final legacy = LegacyV1.fromJson(raw);
        if (legacy.listId == listId) return legacy.key;
      } on FormatException {
        // Se mira la de las pruebas.
      }
    }
    final proof = await store.readV1ProofKey();
    final since = proof is Map && proof['s'] is int
        ? DateTime.fromMillisecondsSinceEpoch(proof['s'] as int)
        : null;
    // Mismo plazo que `LegacyV1`; sin fecha, caducada.
    if (since == null || clock.now().difference(since) >= kLegacyV1MaxAge) {
      if (proof != null) await store.saveV1ProofKey(null);
      return null;
    }
    if (proof is Map && proof['l'] == listId && proof['k'] is String) {
      try {
        return FamilyKey.fromBase64Url(proof['k'] as String);
      } on ArgumentError {
        return null;
      }
    }
    return null;
  }

  /// «Continuar» en el aviso de pasar a la sincronización nueva.
  Future<void> confirmMigration() async {
    if (state.phase != PairingV2HostPhase.confirmMigration) return;
    await _start(migrationConfirmed: true);
  }

  Future<void> _start({required bool migrationConfirmed}) async {
    ref.read(familyStoreProvider).requireMobileOperation('invite');
    _starts++;
    final run = ++_run;
    _stop();
    final previous = _host;
    _host = null;
    if (previous != null) unawaited(previous.cancel());
    final transport = ref.read(syncV2TransportProvider);
    final endpoint = ref.read(syncEndpointProvider);
    if (transport == null || endpoint == null) {
      state = PairingV2HostState(
        PairingV2HostPhase.failed,
        notReady: true,
        failureCode: _failureCode('config', StateError('unavailable')),
      );
      return;
    }
    var phase = 'migration';
    final sync = ref.read(syncControllerProvider.notifier);
    try {
      if (!migrationConfirmed) {
        final ask = await _migrationNeedsConsent();
        if (run != _run || !ref.mounted) return;
        if (ask) {
          state = const PairingV2HostState(PairingV2HostPhase.confirmMigration);
          return;
        }
      }
      state = const PairingV2HostState(PairingV2HostPhase.preparing);
      sync.setV2Pairing(true);
      final local = await ensureV2Family(ref);
      final store = ref.read(familyStoreProvider);
      final view = await (await local.registry()).viewFor(
        me: local.identity.deviceId,
        mySigningKey: local.keys.publicKeys.signing,
        livePeople: const {},
      );
      final inviteCopy =
          !view.paired &&
          !await store.remoteSyncEnabled() &&
          !await store.recoveryActivationPending();
      if (inviteCopy) await sync.markV2InviteCopy(local.identity.syncId);
      final host = await PairingV2Host.start(
        transport: transport,
        local: local,
        lock: ref.read(v2FamilyLockProvider),
        onPhase: (next) => phase = next,
        web: _webQr,
        guestPerson: _webPerson,
        inviteCopy: inviteCopy,
        v1Key: await _legacyV1Key(local.identity.listId),
      );
      if (run != _run || !ref.mounted) {
        unawaited(host.cancel());
        return;
      }
      _host = host;
      // 1-2 s mientras se espera la respuesta. La ruta autenticada no cuenta
      // en el límite por invitación, pero sí en el de la credencial y en el
      // de la IP (que comparte con la web en casa): como mucho
      // [kInviteHostPollBudget] por minuto (la lectura y la revelación).
      _pacer = InvitePollPacer(
        base: ref.read(syncTimingProvider).inviteHostPoll,
        budget: kInviteHostPollBudget,
      );
      state = PairingV2HostState(
        PairingV2HostPhase.waiting,
        link: inviteLink(endpoint.invitationHost, host.inviteId),
      );
      _schedule(run);
    } on V2InviteConflictException catch (e) {
      sync.setV2Pairing(false);
      if (run != _run || !ref.mounted) return;
      state = PairingV2HostState(
        PairingV2HostPhase.failed,
        needsNewWebQr: e.code == 'invite_exists',
        failureCode: _failureCode(phase, e),
      );
    } on SyncTransportException catch (e) {
      sync.setV2Pairing(false);
      if (run != _run || !ref.mounted) return;
      state = PairingV2HostState(
        PairingV2HostPhase.failed,
        notReady: e.failure == SyncFailure.network,
        failureCode: _failureCode(phase, e),
      );
    } on Object catch (e) {
      sync.setV2Pairing(false);
      if (run != _run || !ref.mounted) return;
      state = PairingV2HostState(
        PairingV2HostPhase.failed,
        failureCode: _failureCode(phase, e),
      );
    }
  }

  void _schedule(int run, {bool limited = false, Duration? retryAfter}) {
    // Un sondeo viejo no toca el temporizador ni la cadencia del nuevo.
    if (run != _run || !ref.mounted) return;
    _timer?.cancel();
    final pacer = _pacer;
    final wait = pacer == null
        ? ref.read(syncTimingProvider).inviteHostPoll
        : limited
        ? pacer.limited(retryAfter)
        : pacer.next();
    _timer = Timer(wait, () {
      if (run != _run || !ref.mounted) return;
      unawaited(_check(run).catchError((Object _) {}));
    });
  }

  /// Mira ya si el otro móvil ha respondido (también lo hace solo, cada
  /// `SyncTiming.inviteHostPoll`).
  Future<void> check() => _check(_run);

  Future<void> _check(int run) async {
    final host = _host;
    if (host == null) return;
    if (state.phase == PairingV2HostPhase.compare ||
        state.phase == PairingV2HostPhase.confirmPerson) {
      try {
        _pacer?.sent();
        await host.ensureAlive();
        if (run != _run ||
            !ref.mounted ||
            (state.phase != PairingV2HostPhase.compare &&
                state.phase != PairingV2HostPhase.confirmPerson)) {
          return;
        }
        _pacer?.succeeded();
        _schedule(run);
      } on InviteGoneException catch (e) {
        if (run == _run &&
            ref.mounted &&
            (state.phase == PairingV2HostPhase.compare ||
                state.phase == PairingV2HostPhase.confirmPerson)) {
          _end(
            PairingV2HostPhase.cancelled,
            failureCode: _failureCode('poll', e),
          );
        }
      } on Object catch (e) {
        if (run != _run ||
            !ref.mounted ||
            (state.phase != PairingV2HostPhase.compare &&
                state.phase != PairingV2HostPhase.confirmPerson)) {
          return;
        }
        final limited =
            e is SyncTransportException && e.failure == SyncFailure.rateLimited;
        _schedule(
          run,
          limited: limited,
          retryAfter: limited ? e.retryAfter : null,
        );
      }
      return;
    }
    if (state.phase != PairingV2HostPhase.waiting) return;
    try {
      _pacer?.sent();
      final answered = await host.poll();
      if (run != _run || !ref.mounted) return;
      _pacer?.succeeded();
      if (answered == null) {
        _schedule(run);
        return;
      }
      final person = answered.guestPersonId;
      String? name;
      if (person != null) {
        final fam = await familySnapshot(ref);
        for (final r in fam.fullView.recipients) {
          if (r.id == person) name = r.name;
        }
        if (run != _run || !ref.mounted) return;
        if (name == null) {
          // `poll` ya rechaza a quien no existe; por si se borró entre medias.
          await host.cancel();
          _end(
            PairingV2HostPhase.failed,
            failureCode: _failureCode(
              'person',
              const PairingException('persona ausente'),
            ),
          );
          return;
        }
      }
      state = PairingV2HostState(
        PairingV2HostPhase.compare,
        link: state.link,
        code: answered.code,
        guestWithoutPerson: person == null,
        guestPersonId: person,
        guestPersonName: name,
      );
      _schedule(run);
    } on InviteGoneException catch (e) {
      // De una invitación vieja: la nueva no se toca.
      if (run != _run || !ref.mounted) return;
      _end(PairingV2HostPhase.cancelled, failureCode: _failureCode('poll', e));
    } on PairingException catch (e) {
      if (run != _run || !ref.mounted) return;
      // La respuesta no valía (o era de una persona que no existe) y la
      // invitación ya está borrada.
      _end(PairingV2HostPhase.failed, failureCode: _failureCode('poll', e));
    } on Object catch (e) {
      if (run == _run && ref.mounted) {
        state = PairingV2HostState(
          state.phase,
          link: state.link,
          failureCode: _failureCode('poll', e),
        );
      }
      final limited =
          e is SyncTransportException && e.failure == SyncFailure.rateLimited;
      if (run == _run && ref.mounted) {
        _schedule(
          run,
          limited: limited,
          retryAfter: limited ? e.retryAfter : null,
        );
      }
    }
  }

  /// «Coinciden». Si el otro móvil dice ser de alguien, antes hay que
  /// confirmarlo aparte ([confirmPerson]); si no, da acceso al otro móvil.
  Future<void> confirm() async {
    if (_host == null || state.phase != PairingV2HostPhase.compare) return;
    if (state.guestPersonId != null) {
      state = state._as(PairingV2HostPhase.confirmPerson);
      return;
    }
    await _approve(confirmedPersonId: null);
  }

  /// «Sí, es de…»: da acceso al otro móvil como de esa persona.
  Future<void> confirmPerson() async {
    if (_host == null || state.phase != PairingV2HostPhase.confirmPerson) {
      return;
    }
    await _approve(confirmedPersonId: state.guestPersonId);
  }

  Future<void> _approve({required String? confirmedPersonId}) async {
    final host = _host!;
    final run = _run;
    final current = state;
    _stop();
    state = current._as(PairingV2HostPhase.approving);
    try {
      await host.confirm(
        guestWithoutPerson: current.guestWithoutPerson,
        confirmedPersonId: confirmedPersonId,
      );
      if (run != _run || !ref.mounted) return;
      await ref.read(familyControllerProvider.notifier).markPaired();
      _host = null;
      _end(PairingV2HostPhase.done, code: current.code);
      if (ref.mounted) ref.invalidate(localRegistryViewProvider);
      unawaited(ref.read(syncControllerProvider.notifier).resumeAfterPairing());
    } on Object catch (e) {
      if (run != _run || !ref.mounted) return;
      await host.cancel();
      _end(PairingV2HostPhase.failed, failureCode: _failureCode('approve', e));
    }
  }

  /// «No coinciden», «No es suyo» o cerrar: la invitación se borra y no se
  /// reintenta con la misma oferta.
  Future<void> cancel() => _cancel(PairingV2HostPhase.cancelled);

  Future<void> _cancel(PairingV2HostPhase endAs) async {
    final host = _host;
    _host = null;
    final starts = _starts;
    final run = ++_run;
    _stop();
    if (host != null) await host.cancel();
    // Mientras se borraba ha empezado otro emparejamiento: ni su estado ni su
    // lista son de este. Cerrar la pantalla, en cambio, no lo detiene.
    if (starts != _starts || !ref.mounted) return;
    final sync = ref.read(syncControllerProvider.notifier)..setV2Pairing(false);
    if (run == _run) state = PairingV2HostState(endAs);
    // Sin nadie nuevo, la lista que subió para invitar no se queda en el
    // servidor (hallazgo 14).
    if (host != null) await sync.dropV2InviteCopy();
  }

  /// Vuelve a reposo (al cerrar la pantalla).
  void dismiss() {
    if (_host != null) {
      unawaited(_cancel(PairingV2HostPhase.idle));
    } else {
      _run++;
    }
    if (ref.mounted) state = const PairingV2HostState(PairingV2HostPhase.idle);
  }

  /// Termina el emparejamiento. Si acaba sin nadie nuevo ([dropCopy] y no
  /// [PairingV2HostPhase.done]), la lista que subió para invitar se borra
  /// del servidor si este móvil sigue solo (hallazgo 14).
  void _end(
    PairingV2HostPhase phase, {
    String? code,
    String? failureCode,
    bool dropCopy = true,
  }) {
    _stop();
    final sync = ref.read(syncControllerProvider.notifier)..setV2Pairing(false);
    state = PairingV2HostState(phase, code: code, failureCode: failureCode);
    if (dropCopy && phase != PairingV2HostPhase.done) {
      unawaited(sync.dropV2InviteCopy());
    }
  }
}

/// El emparejamiento v2 que ofrece este móvil.
final pairingV2HostProvider =
    NotifierProvider<PairingV2HostController, PairingV2HostState>(
      PairingV2HostController.new,
    );

// ---------------------------------------------------------------- invitado

/// En qué punto está el emparejamiento de este móvil como invitado.
enum PairingV2GuestPhase {
  /// Nada en marcha.
  idle,

  /// Leyendo la invitación.
  opening,

  /// Este móvil tiene otra familia con datos: hay que confirmar que se
  /// sustituye ([PairingV2GuestController.confirmReplace]).
  confirmReplace,

  /// Hay que elegir de quién es este móvil (N2), o «Elegir después».
  choosePerson,

  /// Esperando a que el otro móvil revele su parte del código.
  waitingCode,

  /// Hay que comparar el código con el del otro móvil.
  compare,

  /// Coinciden: esperando a que el otro móvil dé acceso.
  waitingApproval,

  /// Dentro de la familia.
  done,

  /// «No coinciden» o cancelado.
  cancelled,

  /// La invitación ya no existe o ya la ha usado otro móvil.
  gone,

  /// No se ha podido; [PairingV2GuestState.notReady] dice si es la red.
  failed,
}

/// Una persona que se puede elegir como «Yo» al entrar.
@immutable
class PairingV2Person {
  /// Crea la persona.
  const PairingV2Person(this.id, this.name);

  /// Id estable.
  final String id;

  /// Nombre (de la copia local de este móvil).
  final String name;
}

/// Estado del invitado.
@immutable
class PairingV2GuestState {
  /// Crea el estado.
  const PairingV2GuestState(
    this.phase, {
    this.code,
    this.people = const [],
    this.selfId,
    this.notReady = false,
    this.versionMismatch = false,
    this.failureCode,
    this.leftoverDevice = false,
  });

  /// Fase.
  final PairingV2GuestPhase phase;

  /// Falló después de que el otro móvil diera acceso (B7, M3): este móvil ha
  /// abandonado esa credencial y puede volver a intentarlo, pero en la
  /// familia queda un dispositivo que no se usará y que el otro móvil tiene
  /// que quitar (Ajustes › Móviles de la familia). La interfaz lo dirá.

  /// El código de seis cifras.
  final String? code;

  /// Personas que este móvil ya conoce de esa misma lista (si tenía una
  /// copia de v1). Vacío: solo se puede «Elegir después».
  final List<PairingV2Person> people;

  /// De quién era ya este móvil («Este móvil es de»,
  /// `FamilyIdentity.selfRecipientId`), si esa persona está en [people]: la
  /// pantalla la enseña ya elegida para confirmarla. `null`: sin nadie
  /// marcado, o marcado pero que no está en la familia a la que se une.
  final String? selfId;

  /// Falló por la red o sin servidor.
  final bool notReady;

  /// Ambos móviles deben actualizarse antes de volver a emparejar.
  final bool versionMismatch;

  /// Diagnóstico sin datos de la familia, ids ni claves.
  final String? failureCode;

  /// Ver el constructor.
  final bool leftoverDevice;
}

/// El emparejamiento v2 de este móvil como invitado.
class PairingV2GuestController extends Notifier<PairingV2GuestState> {
  PairingV2Guest? _guest;
  Timer? _timer;
  InvitePollPacer? _pacer;
  int _run = 0;
  String _deviceId = '';
  String? _inviteId;
  bool _sameList = false;

  /// «Sustituir y unirme» confirmado: la familia de este móvil se sustituye
  /// solo al quedar dentro de la nueva ([_install]), nunca antes (hallazgo 5).
  bool _replacing = false;

  /// Claves de este móvil para la familia nueva. Al sustituir son nuevas y
  /// viven solo en memoria hasta [_install]: si se cancela, nada ha cambiado.
  DeviceKeys? _keys;
  String? _replaced;
  String _confirmedDeviceName = '';

  @override
  PairingV2GuestState build() {
    ref.onDispose(() => _timer?.cancel());
    return const PairingV2GuestState(PairingV2GuestPhase.idle);
  }

  /// Abre la invitación [inviteId] (del QR o del enlace). [deviceName] solo
  /// lleva el nombre ya escrito o aceptado en un campo; no propone el modelo.
  Future<void> begin(String inviteId, {String deviceName = ''}) {
    ref.read(familyStoreProvider).requireMobileOperation('pairMobile');
    _confirmedDeviceName = deviceName;
    return _open(inviteId, replacing: false);
  }

  Future<void> _open(String inviteId, {required bool replacing}) async {
    final run = ++_run;
    _timer?.cancel();
    _replacing = replacing;
    _guest = null;
    final transport = ref.read(syncV2TransportProvider);
    if (transport == null) {
      state = PairingV2GuestState(
        PairingV2GuestPhase.failed,
        notReady: true,
        failureCode: _failureCode('config', StateError('unavailable')),
      );
      return;
    }
    _inviteId = inviteId;
    state = const PairingV2GuestState(PairingV2GuestPhase.opening);
    var phase = 'keys';
    try {
      await ref
          .read(v2FamilyLockProvider)
          .run(() => requireNoPendingRestore(ref));
      final keysStore = ref.read(deviceKeysStoreProvider);
      // Una instalación de otro emparejamiento que quedó a medias se termina
      // o se deshace antes (B7: si se deshace, la credencial se cambia).
      await ref.read(v2FamilyLockProvider).run(() async {
        await requireNoPendingRestore(ref);
        await finishPendingV2(ref);
      });
      var keys = replacing
          ? await DeviceKeys.generate()
          : await ref.read(v2FamilyLockProvider).run(() async {
              await requireNoPendingRestore(ref);
              return await keysStore.read() ?? await keysStore.create();
            });
      phase = 'family';
      final fam = await familySnapshot(ref);
      final identity = fam.identity;
      // Un móvil que ya está en v2 nunca es «la misma lista» de nadie: entrar
      // en otra familia v2 es siempre sustituir la suya, con confirmación y
      // limpieza (hallazgo 6).
      final alreadyV2 =
          identity != null &&
          (syncProtocolOf(fam.doc) == kSyncProtocolV2 ||
              await ref.read(familyStoreProvider).readSyncV2() != null);
      if (!replacing && !alreadyV2) {
        // B7 (resto de M3): la credencial de servicio de un móvil que no
        // está en ninguna lista v2 no la usa nadie. Se estrena una para cada
        // emparejamiento: una aprobación que no llegó a instalarse
        // (cancelar, cerrar la app o fallar después) nunca deja
        // `credential_exists` al volver a intentarlo.
        keys = await ref.read(v2FamilyLockProvider).run(() async {
          await requireNoPendingRestore(ref);
          await rotateServiceCredential(ref);
          return (await keysStore.read())!;
        });
      }
      final v1Key = replacing || alreadyV2
          ? null
          : ref.read(familyControllerProvider.notifier).familyKey;
      phase = 'offer';
      var sameList = false;
      var deviceId = '';
      // 1-2 s, con el presupuesto de la invitación: la oferta, la respuesta
      // y cada sondeo cuentan en el límite público del Worker.
      final pacer = InvitePollPacer(
        base: ref.read(syncTimingProvider).invitePoll,
      );
      final guest = await PairingV2Guest.open(
        transport: transport,
        inviteId: inviteId,
        keys: keys,
        v1Key: v1Key,
        onRequest: pacer.sent,
        deviceIdFor: (listId, v1Proven) {
          // El `listId` es público: solo cuenta si el anfitrión ha probado
          // tener la clave v1 de este móvil (hallazgo 6).
          sameList =
              v1Key != null &&
              v1Proven &&
              identity != null &&
              identity.listId == listId;
          return deviceId = identity != null && sameList
              ? identity.node
              : HlcClock.newNode();
        },
      );
      // Una apertura vieja no pisa lo de la que está en marcha.
      if (run != _run || !ref.mounted) return;
      _sameList = sameList;
      _deviceId = deviceId;
      _guest = guest;
      _pacer = pacer;
      _keys = keys;
      if (!replacing &&
          !_sameList &&
          identity != null &&
          (fam.hasData || alreadyV2)) {
        state = const PairingV2GuestState(PairingV2GuestPhase.confirmReplace);
        return;
      }
      _askPerson(fam);
    } on RecoveryApplicationException catch (e) {
      _set(
        run,
        PairingV2GuestState(PairingV2GuestPhase.failed, failureCode: e.code),
      );
    } on InviteGoneException catch (e) {
      _guestFailure(run, phase, e, gone: true);
    } on SyncTransportException catch (e) {
      _set(
        run,
        PairingV2GuestState(
          PairingV2GuestPhase.failed,
          notReady: e.failure == SyncFailure.network,
          failureCode: _failureCode(phase, e),
        ),
      );
    } on Object catch (e) {
      _guestFailure(run, phase, e);
    }
  }

  void _guestFailure(
    int run,
    String phase,
    Object error, {
    bool gone = false,
    bool leftover = false,
  }) {
    _set(
      run,
      PairingV2GuestState(
        gone ? PairingV2GuestPhase.gone : PairingV2GuestPhase.failed,
        versionMismatch: error is PairingV2VersionMismatchException,
        notReady:
            error is SyncTransportException &&
            error.failure == SyncFailure.network,
        failureCode: _failureCode(phase, error),
        leftoverDevice: leftover,
      ),
    );
  }

  /// B7, M3: la aprobación llegó pero no se va a instalar (fallo definitivo
  /// antes de empezar a instalar). La credencial ya está registrada en la
  /// lista: se cambia la guardada por otra (es aleatoria e independiente de
  /// la ficha) para que volver a emparejar no dé `credential_exists`.
  /// Devuelve si queda un dispositivo fantasma en la familia.
  Future<bool> _abandonCredential(PairingV2Guest guest, String phase) async {
    if (phase != 'approval' || !guest.approved) return false;
    final keys = _keys;
    if (keys != null) {
      try {
        await ref
            .read(v2FamilyLockProvider)
            .run(
              () => rotateServiceCredential(ref, used: keys.serviceCredential),
            );
      } on Object catch (e) {
        _failureCode('abandon', e);
      }
    }
    return true;
  }

  void _set(int run, PairingV2GuestState next) {
    if (run == _run && ref.mounted) state = next;
  }

  void _askPerson(FamilyState fam) {
    final people = _sameList
        ? [
            for (final r in fam.fullView.recipients)
              PairingV2Person(r.id, r.name),
          ]
        : const <PairingV2Person>[];
    // La identidad de este móvil sigue intacta hasta `_install`: de ahí sale
    // «Este móvil es de». Solo vale si esa persona está en la lista.
    final self = fam.identity?.selfRecipientId;
    state = PairingV2GuestState(
      PairingV2GuestPhase.choosePerson,
      people: people,
      selfId: self != null && people.any((p) => p.id == self) ? self : null,
    );
  }

  /// Sí, sustituir la familia de este móvil por la de la invitación. La
  /// pantalla ya ha pedido el PIN o la biometría (hallazgo 5). No se borra
  /// nada todavía: la invitación se vuelve a abrir con claves nuevas en
  /// memoria, y lo de este móvil se sustituye solo cuando el otro móvil le
  /// ha dado acceso y el paquete se ha abierto ([_install]). Cancelar o
  /// fallar antes deja este móvil como estaba.
  Future<void> confirmReplace() async {
    final inviteId = _inviteId;
    if (state.phase != PairingV2GuestPhase.confirmReplace || inviteId == null) {
      return;
    }
    await _open(inviteId, replacing: true);
  }

  /// Responde con la persona elegida ([personId]) o, con null, sin persona
  /// («Elegir después», que la pantalla tiene que dejar claro: N2).
  Future<void> choosePerson(String? personId) async {
    final guest = _guest;
    if (guest == null || state.phase != PairingV2GuestPhase.choosePerson) {
      return;
    }
    final run = _run;
    try {
      await guest.answer(personId: personId, withoutPerson: personId == null);
      _set(run, const PairingV2GuestState(PairingV2GuestPhase.waitingCode));
      _schedule(run);
    } on InviteTakenException catch (e) {
      _guestFailure(run, 'answer', e, gone: true);
    } on InviteGoneException catch (e) {
      _guestFailure(run, 'answer', e, gone: true);
    } on Object catch (e) {
      _guestFailure(run, 'answer', e);
    }
  }

  void _schedule(int run, {bool limited = false, Duration? retryAfter}) {
    // Un sondeo viejo no toca el temporizador ni la cadencia del nuevo.
    if (run != _run || !ref.mounted) return;
    _timer?.cancel();
    final pacer = _pacer;
    final wait = pacer == null
        ? ref.read(syncTimingProvider).invitePoll
        : limited
        ? pacer.limited(retryAfter)
        : pacer.next();
    _timer = Timer(wait, () {
      if (run != _run || !ref.mounted) return;
      unawaited(_tick(run).catchError((Object _) {}));
    });
  }

  /// Si hay un sondeo programado (las pruebas comprueban que se para).
  @visibleForTesting
  bool get polling => _timer?.isActive ?? false;

  /// Sondea ya, sin esperar al temporizador (las pruebas de carreras).
  @visibleForTesting
  Future<void> pollNow() => _tick(_run);

  Future<void> _tick(int run) async {
    final guest = _guest;
    if (guest == null || run != _run || !ref.mounted) return;
    var phase = state.phase == PairingV2GuestPhase.waitingCode
        ? 'reveal'
        : 'approval';
    try {
      switch (state.phase) {
        case PairingV2GuestPhase.waitingCode:
          final code = await guest.code();
          if (run != _run || !ref.mounted) return;
          _pacer?.succeeded();
          if (code == null) {
            _schedule(run);
          } else {
            _set(
              run,
              PairingV2GuestState(PairingV2GuestPhase.compare, code: code),
            );
          }
        case PairingV2GuestPhase.waitingApproval:
          final joined = await guest.finish();
          if (run != _run || !ref.mounted) return;
          _pacer?.succeeded();
          if (joined == null) {
            _schedule(run);
          } else {
            phase = 'install';
            await ref.read(v2FamilyLockProvider).run(() => _install(joined));
            // Installation is complete: acknowledge removal of the whole invitation.
            unawaited(guest.releaseCheckpoint());
            if (ref.mounted) ref.invalidate(localRegistryViewProvider);
            unawaited(
              ref.read(syncControllerProvider.notifier).resumeAfterPairing(),
            );
            _set(
              run,
              PairingV2GuestState(PairingV2GuestPhase.done, code: state.code),
            );
          }
        default:
          return;
      }
    } on InviteGoneException catch (e) {
      // Lo de un intento viejo no toca el actual (ni sus claves).
      if (run != _run || !ref.mounted) return;
      final leftover = await _abandonCredential(guest, phase);
      _guestFailure(run, phase, e, gone: true, leftover: leftover);
    } on PairingException catch (e) {
      if (run != _run || !ref.mounted) return;
      // La revelación no casa con la oferta (alguien en medio), o la
      // aprobación o el checkpoint no valen.
      final leftover = await _abandonCredential(guest, phase);
      _guestFailure(run, phase, e, leftover: leftover);
    } on SyncTransportException catch (e) {
      if (run != _run || !ref.mounted) return;
      _set(
        run,
        PairingV2GuestState(
          state.phase,
          code: state.code,
          failureCode: _failureCode(phase, e),
        ),
      );
      final limited = e.failure == SyncFailure.rateLimited;
      if (run == _run && ref.mounted) {
        _schedule(run, limited: limited, retryAfter: e.retryAfter);
      }
    } on Object catch (e) {
      if (run != _run || !ref.mounted) return;
      final leftover = await _abandonCredential(guest, phase);
      _guestFailure(run, phase, e, leftover: leftover);
    }
  }

  /// «Coinciden»: espera a que el otro móvil dé acceso.
  void confirmCode() {
    final guest = _guest;
    if (guest == null || state.phase != PairingV2GuestPhase.compare) return;
    guest.confirmCode();
    state = PairingV2GuestState(
      PairingV2GuestPhase.waitingApproval,
      code: state.code,
    );
    _schedule(_run);
  }

  /// «No coinciden» o cancelar: este móvil no usa la invitación.
  void cancel() {
    _run++;
    _timer?.cancel();
    _guest = null;
    state = const PairingV2GuestState(PairingV2GuestPhase.cancelled);
  }

  /// Vuelve a reposo.
  void reset() {
    _run++;
    _timer?.cancel();
    _guest = null;
    state = const PairingV2GuestState(PairingV2GuestPhase.idle);
  }

  Future<void> _leaveOldFamily() async {
    final transport = ref.read(syncV2TransportProvider);
    if (transport == null) return;
    try {
      final old = await AppSyncV2Local.load(ref);
      if (old == null) return;
      // Con otros dentro, sale (revoca su credencial y retira sus slots);
      // solo, borra su lista: no queda nadie que la use.
      Future<void> leave() async {
        if (await othersHaveAccess(transport: transport, local: old)) {
          await leaveFamily(transport: transport, local: old);
          return;
        }
        final auth = V2Auth(
          syncId: old.identity.syncId,
          deviceId: old.identity.deviceId,
          credential: old.keys.serviceCredential,
        );
        final got = await transport.getList(auth);
        if (got is V2GetOk) {
          await transport.deleteList(auth, version: got.snapshot.version);
        }
      }

      await leave().timeout(const Duration(seconds: 15));
    } on Object catch (e) {
      _failureCode('leave', e);
    }
  }

  Future<void> _install(PairingV2Joined joined) async {
    await requireNoPendingRestore(ref);
    final store = ref.read(familyStoreProvider);
    final family = ref.read(familyControllerProvider.notifier);
    if (_replacing) {
      // Si este móvil estaba en otra familia v2, sale de ella antes (de mejor
      // esfuerzo: sin red se sustituye igual) para no quedar allí como un
      // móvil activo que ya no existe.
      await _leaveOldFamily();
      // Ahora sí: dentro de la familia nueva, lo de este móvil se sustituye.
      // Se conserva el nombre del móvil y se guardan las claves nuevas.
      final name = (await familySnapshot(ref)).identity?.deviceName ?? '';
      await family.resetLocalData();
      await ref.read(deviceKeysStoreProvider).restore(_keys!);
      _replaced = name;
    }
    final fam = await familySnapshot(ref);
    final identity = fam.identity;
    final v1Key = family.familyKey;
    var doc = joined.common;
    if (_sameList && syncProtocolOf(fam.doc) == 1) {
      // Lo local de v1 entra en v2 sin perder nada.
      doc = mergeLocalV1IntoV2(v2Doc: joined.common, localV1: fam.doc);
    }
    // La clave y el syncId de la familia que entra, antes que nada; con el
    // formato mínimo firmado, para que un cierre a medias termine con la
    // marca (`finishPendingV2`, B7).
    final format2 = joined.commonFormat >= kCommonFormatLatest;
    await store.savePendingV2(
      PendingV2(
        key: joined.familyKey,
        syncId: joined.identity.syncId,
        fromV1: joined.identity.migratedFromV1,
        commonFormat: joined.commonFormat,
        pairing: true,
      ).toJson(),
    );
    await store.saveRegistry(joined.registry);
    // B7: las claves de la base aprobada, antes de instalar el documento.
    // Sin el corte no se hereda un llavero de otro intento (B2).
    if (format2) {
      await store.saveCommonKeys(joined.commonKeys!.toJson());
      await store.markCommonKeys();
    } else {
      await store.clearCommonKeys();
    }
    if (_sameList && identity != null && identity.paired && v1Key != null) {
      await store.saveLegacyV1(
        LegacyV1(
          listId: joined.identity.listId,
          key: v1Key,
          since: clock.now(),
          nodes: writerNodesOf(fam.doc),
        ).toJson(),
      );
    }
    await store.saveSyncV2State(
      V2SyncState(
        created: true,
        version: joined.minVersion,
        minSlotRevisions: joined.minSlotRevisions,
        commonFormatV2: format2,
      ).toJson(),
    );
    var deviceName = _confirmedDeviceName.isNotEmpty
        ? _confirmedDeviceName
        : identity?.deviceName ?? _replaced ?? '';
    if (isLegacyDeviceName(deviceName)) deviceName = '';
    await family.installV2(
      listId: joined.identity.listId,
      node: _deviceId,
      key: joined.familyKey,
      doc: doc,
      deviceName: deviceName,
      paired: true,
    );
    _replaced = null;
    // Tras el corte, nace con la marca irreversible antes de la identidad:
    // ninguna vuelta abre nunca un formato 1 (no se fía del mínimo del
    // servidor, que no va firmado).
    if (format2) await store.raiseCommonFormatFloor(joined.commonFormat);
    // Persist before completing the installation journal. A foreground sync
    // retries this acknowledgement if the immediate request/response is lost.
    await store.savePendingInviteAcknowledgement({
      'syncId': joined.identity.syncId,
      'inviteId': _inviteId!,
    });
    await store.saveSyncV2(joined.identity);
    await store.savePendingV2(null);
  }
}

/// El emparejamiento v2 de este móvil como invitado.
final pairingV2GuestProvider =
    NotifierProvider<PairingV2GuestController, PairingV2GuestState>(
      PairingV2GuestController.new,
    );
