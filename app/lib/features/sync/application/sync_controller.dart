import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/task_runner.dart';
import '../../../core/prefs/shared_preferences_provider.dart';
import '../../../core/sync/device_registry.dart';
import '../../../core/sync/envelope.dart';
import '../../../core/sync/family_doc.dart';
import '../../../core/sync/pairing_v2.dart';
import '../../../core/sync/recovery.dart';
import '../../family/application/family_controller.dart';
import '../../family/data/family_store.dart';
import '../../family/data/generation_store.dart';
import '../../family/data/recovery_store.dart';
import '../../family/domain/family_errors.dart';
import '../data/sync_config.dart';
import '../data/recovery_transport.dart';
import '../data/sync_transport.dart';
import '../data/sync_transport_v2.dart';
import '../domain/sync_keys.dart';
import '../domain/sync_status.dart';
import 'app_sync_v2_local.dart';
import 'common_v2_cutover.dart' show kCommonFormatLatest;
import 'family_device_actions.dart' as device_actions;
import 'family_devices.dart' show devicePersonIds, localView;
import 'family_devices.dart'
    as family_devices
    show leaveFamily, othersHaveAccess, removeDevice;
import 'family_snapshot.dart';
import 'generation_v2.dart';
import 'migration_v2.dart';
import 'pairing_v2_controller.dart'
    show syncReconnectNeededProvider, ensureV2FamilyWithinLock;
import 'peer_connected.dart';
import 'sync_v2_engine.dart';
import 'v2_health.dart';
import 'recovery_providers.dart';

/// Listas en las que la persona apagó la sincronización (preferencias). Por
/// defecto está encendida para cualquier lista.
const _offListsKey = 'sync.offLists';

/// Listas cuyo QR de emparejar se enseñó en este móvil y que siguen esperando
/// al segundo móvil (preferencias): `"<ms desde 1970>:<listId>"`.
const _peerWaitKey = 'sync.peerWait';

/// La invitación viva de este móvil (preferencias), como JSON
/// `{"l": listId, "i": id de la invitación, "e": caduca, en ms}`. La escribe
/// y la borra `InviteHostController`; aquí solo se mira si sigue viva.
const kActiveInviteKey = 'sync.activeInvite';

/// Listas que este móvil, sin nadie emparejado, subió solo para poder
/// invitar (preferencias). Mientras la marca siga puesta y no haya ni segundo
/// móvil ni invitación viva, la copia del servidor sobra y hay que borrarla;
/// se quita al borrarla o al emparejarse.
const _inviteCopyKey = 'sync.inviteCopy';

/// v2: `syncId` de la lista que este móvil, solo, subió para un
/// emparejamiento que acabó sin nadie nuevo (preferencias). Mientras siga
/// puesta, la copia del servidor sobra: se borra y se reintenta al arrancar
/// y al volver a primer plano (revisión de la fase 2b, hallazgo 14).
const _v2InviteCopyKey = 'sync.v2InviteCopy';

/// La sincronización no está lista para lo que se pide (apagada, sin
/// servidor, sin red...). [status] dice por qué.
class SyncNotReadyException implements Exception {
  /// Crea el error.
  const SyncNotReadyException(this.status);

  /// El estado en ese momento.
  final SyncStatus status;

  @override
  String toString() => 'SyncNotReadyException($status)';
}

class _Stale implements Exception {
  const _Stale();
}

class _FirstUploadTooLarge implements Exception {
  const _FirstUploadTooLarge();
}

class _ConflictLoop implements Exception {
  const _ConflictLoop();
}

/// Sincroniza la familia de este móvil con el servidor (ADR 0002).
///
/// Ciclo: `GET` → abrir, fusionar y `clock.receive` → `PUT` con `baseVersion`;
/// ante un `409` fusiona lo que devuelve y reintenta. Sube tras cada cambio
/// local (con un retardo para agrupar), al arrancar y al volver a primer plano,
/// y mientras la app está delante escucha el WebSocket. Sin red guarda en
/// local y reintenta con espera creciente. La fusión entrante pasa por
/// `FamilyController.mergeRemote`, que va en la misma cola que las ediciones.
///
/// Recovery enables automatic sync for a single phone through the durable
/// `remoteSyncEnabled` flag, including after restoration and restart. Other
/// families wait for a second phone (`paired`) before uploading or opening
/// a WebSocket. The other exceptions are for connecting that second phone:
/// - crear una invitación sube la lista una vez ([readyCredentials]): el
///   servidor la necesita para invitar;
/// - tras enseñar el QR de emparejar ([expectPeer]) mira, solo con `GET`, si
///   el otro móvil ya ha subido su primera copia. Si esa consulta falla (sin
///   red, `5xx`, `429`) no hay reintentos con espera creciente ni nada en
///   segundo plano: vuelve a [SyncPhase.waitingForPeer] y mira en el siguiente
///   sondeo, mientras la app esté delante.
///
/// Los móviles que ya estaban emparejados sincronizan como siempre.
class SyncController extends Notifier<SyncStatus> {
  SyncTransport? _transport;
  Timer? _debounce;
  Timer? _retry;
  Timer? _watchRetry;
  Timer? _peerPoll;
  StreamSubscription<SyncEvent>? _watch;
  _Lifecycle? _observer;

  bool _foreground = true;
  Future<void>? _running;
  bool _again = false;
  bool _claimingRecovery = false;

  String? _listId;
  FamilyKey? _key;
  SyncCredentials? _auth;
  int? _version;
  String? _synced;
  bool _hasUploaded = false;
  int _failures = 0;

  /// Si la familia ya tenía otro móvil emparejado la última vez que se miró.
  bool _wasPaired = false;

  /// Si el ciclo en marcha puede subir aunque no haya segundo móvil: lo pide
  /// quien va a crear una invitación.
  bool _inviteUpload = false;

  /// Si hay una invitación a medio crear (la lista ya se ha pedido subir y la
  /// invitación aún no está guardada).
  bool _inviting = false;

  /// Si el ciclo en marcha solo mira (`GET`) si ha entrado el móvil que leyó
  /// el QR: este móvil no tiene a nadie emparejado ni va a invitar.
  bool _pollOnly = false;
  int _watchFailures = 0;

  /// Si el WebSocket se cortó y al reabrirlo hay que ponerse al día.
  bool _catchUp = false;

  /// v2 (ADR 0004): las credenciales de este móvil en la lista v2 de la
  /// última vuelta, o null si la familia sigue en v1.
  V2Auth? _v2Auth;

  /// v2: hay un emparejamiento en marcha y la lista tiene que subir aunque
  /// este móvil todavía esté solo.
  bool _v2Pairing = false;

  /// v2: si ya se ha mirado en esta sesión la copia v1 que queda.
  bool _legacyChecked = false;

  /// v2: credenciales activas en el servidor que el registro de este móvil
  /// no respalda (para que la fase 3 las revoque).
  List<String> unbackedCredentials = const [];

  /// v2: el servidor dice que esta generación ha cruzado un aviso de
  /// `capacity` (fase 3: proponer renovar).
  bool renewSuggested = false;

  /// v2: la familia ya está en v2 (la última vuelta lo vio).
  bool get isV2 => _v2Auth != null;

  FamilyController get _family => ref.read(familyControllerProvider.notifier);

  SyncTiming get _timing => ref.read(syncTimingProvider);

  @override
  SyncStatus build() {
    final transport = ref.watch(syncTransportProvider);
    _transport = transport;
    if (transport == null) {
      return const SyncStatus.notConfigured();
    }
    ref.onDispose(_dispose);
    _observer = _Lifecycle(this);
    WidgetsBinding.instance.addObserver(_observer!);
    ref.listen<AsyncValue<FamilyState>>(familyControllerProvider, _onFamily);
    scheduleMicrotask(() {
      if (ref.mounted) {
        _onFamily(null, ref.read(familyControllerProvider));
      }
    });
    return const SyncStatus(SyncPhase.noFamily);
  }

  void _dispose() {
    _debounce?.cancel();
    _retry?.cancel();
    _watchRetry?.cancel();
    _peerPoll?.cancel();
    unawaited(_watch?.cancel());
    _watch = null;
    final observer = _observer;
    if (observer != null) {
      WidgetsBinding.instance.removeObserver(observer);
    }
  }

  // ------------------------------------------------------------- ajustes

  bool _isEnabled(String listId) {
    final off = ref.read(sharedPreferencesProvider).getStringList(_offListsKey);
    return off == null || !off.contains(listId);
  }

  Future<void> _writeEnabled(String listId, bool enabled) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final off = {...?prefs.getStringList(_offListsKey)};
    if (enabled) {
      off.remove(listId);
    } else {
      off.add(listId);
    }
    await prefs.setStringList(_offListsKey, off.toList());
  }

  /// Tras emparejar otro móvil (en los dos lados): quien conecta dos móviles
  /// quiere que se sincronicen, así que si la lista de ahora tenía la
  /// sincronización apagada (p. ej. tras «Dejar de sincronizar») se vuelve a
  /// encender, y se hace una vuelta. Lee la lista de la familia, no `_listId`:
  /// en el invitado la familia acaba de cambiar.
  Future<void> resumeAfterPairing() async {
    final listId = (await ref.read(familyControllerProvider.future))
        .identity
        ?.listId;
    if (!ref.mounted) return;
    if (listId != null && !_isEnabled(listId)) {
      await _writeEnabled(listId, true);
      if (!ref.mounted) return;
      if (listId == _listId && state.phase == SyncPhase.disabled) {
        state = SyncStatus(SyncPhase.idle, lastSyncAt: state.lastSyncAt);
      }
    }
    await syncNow();
  }

  /// Drain the old principal before an explicit claim. Its old WebSocket must
  /// not interpret our own credential replacement as another phone's transfer.
  Future<void> suspendForRecovery() async {
    _claimingRecovery = true;
    _again = false;
    _resetSession();
    await _running;
    if (ref.mounted) _resetSession();
  }

  void finishRecoveryClaim() => _claimingRecovery = false;

  /// Completes a durable code removal while holding v2FamilyLockProvider.
  /// Returns true after retiring the remote list and selecting a local generation.
  Future<bool> finishRecoveryRemovalWithinLock() async {
    final store = ref.read(familyStoreProvider);
    final local = await AppSyncV2Local.load(ref);
    final transport = ref.read(syncV2TransportProvider);
    if (local == null || transport == null) throw SyncNotReadyException(state);
    final recovery = ref.read(recoveryStoreProvider);
    if ((await recovery.readMaterial(local.identity.syncId))?['retired'] !=
        true) {
      final pending = await recovery.readMaintenance(local.identity.syncId);
      if (pending == null || (pending['intent'] as Map)['cause'] != null) {
        await store.setRecoveryRemovalPending(false);
      }
      return false;
    }
    final auth = V2Auth(
      syncId: local.identity.syncId,
      deviceId: local.identity.deviceId,
      credential: local.keys.serviceCredential,
    );
    for (var attempt = 0; attempt < 3; attempt++) {
      final got = await transport.getList(auth);
      if (got is V2GetOk) {
        if (got.snapshot.devices.any(
          (d) => !d.revoked && d.deviceId != auth.deviceId,
        )) {
          await store.disableRemoteSync();
          await store.setRecoveryRemovalPending(false);
          return false;
        }
        final deleted = await transport.deleteList(
          auth,
          version: got.snapshot.version,
        );
        if (deleted is V2WriteStale) continue;
      }
      // A lost DELETE response is resolved by the next GET returning missing.
      _resetSession();
      _v2Auth = null;
      await startNewGenerationV2(ref);
      if (ref.mounted) {
        ref.invalidate(localRegistryViewProvider);
        state = SyncStatus(
          SyncPhase.waitingForPeer,
          lastSyncAt: state.lastSyncAt,
        );
      }
      return true;
    }
    throw const SyncTransportException(
      SyncFailure.server,
      'removal contention',
    );
  }

  /// Retire an already synchronized copy once only this credential remains.
  /// Called under the family lock, after merging all observed server changes.
  /// Any uncertain membership, recovery or revocation keeps the remote copy.
  Future<bool> _retireUnsharedListWithinLock(
    AppSyncV2Local local,
    V2SyncOutcome outcome,
  ) async {
    if (outcome.hasOtherActiveCredential ||
        outcome.rejectedSlots > 0 ||
        outcome.frozenPeople.isNotEmpty) {
      return false;
    }
    try {
      final store = ref.read(familyStoreProvider);
      final pending = await local.readState();
      if (_v2Pairing ||
          !pending.created ||
          pending.version == null ||
          pending.pendingRevocations.isNotEmpty ||
          pending.pendingUnbackedRevocations.isNotEmpty ||
          pending.revocationOperations.isNotEmpty ||
          pending.ignoredSlots.values.any(
            (slot) => slot.reason == IgnoredSlotReason.unreadable,
          ) ||
          await store.remoteSyncEnabled() ||
          await store.recoveryActivationPending() ||
          await store.recoveryRemovalPending() ||
          await store.readRecoverySetup() != null ||
          await store.pendingInviteAcknowledgement() != null) {
        return false;
      }
      final recovery = ref.read(recoveryStoreProvider);
      final material = await recovery.readMaterial(local.identity.syncId);
      if ((material != null && material['retired'] != true) ||
          await recovery.readMaintenance(local.identity.syncId) != null) {
        return false;
      }
      final view = await (await local.registry()).viewFor(
        me: local.identity.deviceId,
        mySigningKey: local.keys.publicKeys.signing,
        livePeople: const {},
      );
      if (view.pending.isNotEmpty || view.revokedByOthers) return false;
      final transport = ref.read(syncV2TransportProvider)!;
      final auth = V2Auth(
        syncId: local.identity.syncId,
        deviceId: local.identity.deviceId,
        credential: local.keys.serviceCredential,
      );
      final got = await transport.getList(auth);
      if (got is V2GetOk) {
        // Do not delete updates we have not merged, or a newly approved peer.
        if (got.snapshot.version != outcome.version ||
            got.snapshot.devices.any(
              (d) => !d.revoked && d.deviceId != auth.deviceId,
            )) {
          return false;
        }
        if (_v2Pairing) return false;
        final deleted = await transport.deleteList(
          auth,
          version: got.snapshot.version,
          automaticRetirement: true,
        );
        if (deleted is! V2WriteOk) return false;
      } else if (got is! V2GetNotFound) {
        return false;
      }
      // A lost DELETE response is retried from persisted sync state; a missing
      // old copy completes the same transition without creating it again.
      _resetSession();
      _v2Auth = null;
      await startNewGenerationV2(ref);
      if (ref.mounted) {
        ref.invalidate(localRegistryViewProvider);
        state = SyncStatus(
          SyncPhase.waitingForPeer,
          lastSyncAt: state.lastSyncAt,
        );
      }
      return true;
    } on Object {
      // Cleanup must not change the result of a completed sync or revocation.
      // Keep persisted state so the next round can reconcile a lost response.
      return false;
    }
  }

  /// Enciende o apaga la sincronización de la lista de este móvil.
  Future<void> setEnabled(bool enabled) async {
    final listId = _listId;
    if (_transport == null || listId == null) {
      return;
    }
    await _writeEnabled(listId, enabled);
    if (enabled) {
      state = SyncStatus(SyncPhase.idle, lastSyncAt: state.lastSyncAt);
      await syncNow();
    } else {
      await _running;
      _resetSession();
      state = SyncStatus(SyncPhase.disabled, lastSyncAt: state.lastSyncAt);
    }
  }

  /// «Dejar de sincronizar»: borra la copia del servidor (`DELETE`) y apaga la
  /// sincronización. Lanza [SyncTransportException] si el servidor no responde
  /// (y no apaga nada: se puede repetir).
  ///
  /// Otro móvil de la familia que siga sincronizando volverá a subir la lista
  /// al ver el `404` o el cierre 4404 del WebSocket (ADR 0002, caducidad).
  ///
  /// En v2 (ADR 0004), con otros móviles en la familia, este móvil **sale de
  /// la familia** ([leaveFamily]): revoca su credencial y deja la lista a los
  /// demás, también desde «Borrar todo». Solo se borra la lista entera del
  /// servidor si este es el último móvil con acceso (hallazgo 2: borrarla con
  /// otros dentro los dejaba sin salida, porque su syncId no vuelve). Después
  /// este móvil estrena una generación propia sin otros móviles
  /// ([startNewGenerationV2]): para volver hay que conectarlo otra vez.
  Future<void> stopSyncing() async {
    final transport = _transport;
    if (transport == null || _listId == null) {
      return;
    }
    await _running;
    final listId = _listId;
    if (listId == null) {
      return;
    }
    final v2 = await AppSyncV2Local.load(ref);
    // Fuera de la familia (o sin sincronizar) ya no hay invitaciones que
    // tengan que probar la clave v1 (hallazgo 6).
    await ref.read(familyStoreProvider).saveV1ProofKey(null);
    if (!ref.mounted) {
      return;
    }
    final v2Transport = ref.read(syncV2TransportProvider);
    if (v2 != null && v2Transport != null) {
      final wasOn = _isEnabled(listId);
      await _writeEnabled(listId, false);
      _resetSession();
      state = SyncStatus(SyncPhase.disabled, lastSyncAt: state.lastSyncAt);
      try {
        final alone = !await family_devices.othersHaveAccess(
          transport: v2Transport,
          local: v2,
        );
        if (alone) {
          await _stopV2(v2, v2Transport);
        } else {
          await family_devices.leaveFamily(transport: v2Transport, local: v2);
        }
      } on SyncTransportException catch (e) {
        // Sin acceso ya (este móvil salió en un intento anterior que se
        // cortó, o lo revocaron): está fuera, y se sigue.
        if (e.failure != SyncFailure.unauthorized) {
          if (wasOn) {
            await setEnabled(true);
          }
          rethrow;
        }
      }
      _v2Auth = null;
      await startNewGenerationV2(ref);
      if (ref.mounted) ref.invalidate(localRegistryViewProvider);
      return;
    }
    // Primero se apaga, antes de pedir las credenciales: al borrar la lista
    // el servidor cierra el WebSocket con 4404 y, con la sincronización
    // encendida, se volvería a subir; y un ciclo que arranque desde aquí ya
    // la ve apagada y no sube nada después del `DELETE`.
    final before = state;
    // «Borrar todo» también pasa por aquí con la sincronización ya apagada:
    // si falla, se queda apagada como estaba.
    final wasEnabled = _isEnabled(listId);
    await _writeEnabled(listId, false);
    final SyncCredentials? auth;
    try {
      auth = await _credentials();
    } on Object {
      if (wasEnabled) {
        await _writeEnabled(listId, true);
      }
      rethrow;
    }
    if (auth == null || _listId != listId) {
      if (wasEnabled) {
        await _writeEnabled(listId, true);
      }
      return;
    }
    _resetSession();
    state = SyncStatus(SyncPhase.disabled, lastSyncAt: before.lastSyncAt);
    try {
      await transport.deleteList(auth);
    } on SyncTransportException {
      if (wasEnabled) {
        await setEnabled(true);
      }
      rethrow;
    }
  }

  // ------------------------------------------- a la espera del segundo móvil

  /// Desde cuándo espera [listId] a que entre el móvil que leyó su QR, o
  /// `null` si no se ha enseñado.
  DateTime? _peerWaitSince(String listId) {
    final entries = ref
        .read(sharedPreferencesProvider)
        .getStringList(_peerWaitKey);
    for (final entry in entries ?? const <String>[]) {
      final cut = entry.indexOf(':');
      if (cut > 0 && entry.substring(cut + 1) == listId) {
        final ms = int.tryParse(entry.substring(0, cut));
        return ms == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
      }
    }
    return null;
  }

  /// Si [listId] sigue esperando al móvil que leyó su QR.
  bool _awaitsPeer(String listId) {
    final since = _peerWaitSince(listId);
    return since != null && clock.now().difference(since) < _timing.peerWait;
  }

  /// Apunta que [listId] espera desde [since], o lo borra con `null`.
  Future<void> _writePeerWait(String listId, DateTime? since) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final entries = [
      for (final entry in prefs.getStringList(_peerWaitKey) ?? const <String>[])
        if (!entry.endsWith(':$listId')) entry,
      if (since != null) '${since.millisecondsSinceEpoch}:$listId',
    ];
    if (entries.isEmpty) {
      await prefs.remove(_peerWaitKey);
    } else {
      await prefs.setStringList(_peerWaitKey, entries);
    }
  }

  /// Este móvil acaba de enseñar su QR de emparejar.
  ///
  /// El QR no avisa de que lo han leído. Desde ahora, y durante
  /// [SyncTiming.peerWait], este móvil mira (solo `GET`) si el otro ya ha
  /// subido su primera copia: al verla queda emparejado y empieza a
  /// sincronizar. Mientras tanto sigue sin subir nada y sin WebSocket. No hace
  /// nada sin servidor, sin familia o si ya hay otro móvil emparejado.
  Future<void> expectPeer() async {
    if (_transport == null) {
      return;
    }
    try {
      final identity = (await familySnapshot(ref)).identity;
      if (identity == null || identity.paired || !ref.mounted) {
        return;
      }
      await _writePeerWait(identity.listId, clock.now());
    } on Object {
      // Sin la marca solo se pierde la comprobación automática: el QR se
      // enseña igual.
      return;
    }
    if (ref.mounted) {
      unawaited(syncNow());
    }
  }

  /// Programa la siguiente consulta del sondeo, solo con la app delante y
  /// dentro de [SyncTiming.peerPollFor]. [atLeast] alarga la espera (el
  /// `Retry-After` de un `429`).
  void _schedulePeerPoll(String listId, {Duration? atLeast}) {
    _peerPoll?.cancel();
    _peerPoll = null;
    final since = _peerWaitSince(listId);
    if (!_foreground ||
        since == null ||
        clock.now().difference(since) >= _timing.peerPollFor) {
      return;
    }
    final every = _timing.peerPoll;
    final delay = atLeast != null && atLeast > every ? atLeast : every;
    _peerPoll = Timer(delay, () {
      _peerPoll = null;
      unawaited(syncNow());
    });
  }

  /// Si [listId] tiene puesta la marca de «subida solo para invitar».
  bool _hasInviteCopy(String listId) =>
      ref
          .read(sharedPreferencesProvider)
          .getStringList(_inviteCopyKey)
          ?.contains(listId) ??
      false;

  /// Pone o quita la marca de «subida solo para invitar» de [listId].
  Future<void> _writeInviteCopy(String listId, bool pending) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final lists = {...?prefs.getStringList(_inviteCopyKey)};
    if (!(pending ? lists.add(listId) : lists.remove(listId))) {
      return;
    }
    if (lists.isEmpty) {
      await prefs.remove(_inviteCopyKey);
    } else {
      await prefs.setStringList(_inviteCopyKey, lists.toList()..sort());
    }
  }

  /// Si [listId] tiene una invitación viva (guardada y sin caducar).
  bool _hasLiveInvite(String listId) {
    final raw = ref.read(sharedPreferencesProvider).getString(kActiveInviteKey);
    if (raw == null) {
      return false;
    }
    try {
      final json = jsonDecode(raw);
      return json is Map &&
          json['l'] == listId &&
          json['e'] is int &&
          clock.now().millisecondsSinceEpoch < (json['e'] as int);
    } on FormatException {
      return false;
    }
  }

  /// Quien invita avisa de que ha terminado de crear la invitación (guardada
  /// o fallida): hasta entonces no se da por sobrante la copia recién subida.
  void inviteSettled() => _inviting = false;

  /// Al arrancar y al volver a primer plano: si quedó en el servidor la copia
  /// de una invitación que ya no vive (caducó con la app cerrada, no se pudo
  /// borrar en su momento o falló al crearla), se borra ahora.
  void _sweepInviteCopy() {
    final listId = _listId;
    if (listId != null &&
        !_v2Pairing &&
        ref.read(sharedPreferencesProvider).getString(_v2InviteCopyKey) !=
            null) {
      unawaited(dropV2InviteCopy(onlyMarked: true));
    }
    if (listId == null ||
        _transport == null ||
        isV2 ||
        _inviting ||
        !_hasInviteCopy(listId) ||
        _hasLiveInvite(listId)) {
      return;
    }
    unawaited(dropInviteCopy());
  }

  /// Borra del servidor la copia cifrada que subió una invitación que acabó
  /// (caducada, rechazada, cancelada o fallida) sin emparejar a nadie: con un
  /// solo móvil no debe quedar nada allí. No hace nada si ya hay otro móvil
  /// emparejado, que es quien necesita esa copia.
  ///
  /// Antes de borrar mira (`GET` condicional) si lo que hay en el servidor
  /// sigue siendo lo que subió este móvil: si otro móvil ya ha escrito ahí, la
  /// lista es suya también y no se borra (revisión de seguridad, N7). Entre
  /// esa consulta y el borrado queda una ventana mínima que solo cierra el
  /// servidor con un `DELETE` condicional (fase 2b).
  ///
  /// No lanza: si el servidor no responde, la marca de pendiente se queda y
  /// se reintenta al arrancar o al volver a primer plano. Dos llamadas a la
  /// vez comparten un solo borrado.
  Future<void> dropInviteCopy() => _droppingCopy ??= _dropInviteCopy()
      .whenComplete(() => _droppingCopy = null);

  Future<void>? _droppingCopy;

  Future<void> _dropInviteCopy() async {
    final transport = _transport;
    if (transport == null) {
      return;
    }
    try {
      await _running;
      final identity = (await familySnapshot(ref)).identity;
      if (identity == null || !ref.mounted) {
        return;
      }
      final listId = identity.listId;
      if (identity.paired) {
        await _writeInviteCopy(listId, false);
        return;
      }
      final auth = await _credentials();
      final key = _family.familyKey;
      if (auth == null || key == null) {
        return;
      }
      // Pendiente hasta que se confirme: si esto se corta, se reintenta.
      await _writeInviteCopy(listId, true);
      final got = await transport.getList(auth, ifNoneMatch: _version);
      switch (got) {
        case SyncGetNotFound():
          break;
        case SyncGetNotModified():
          await transport.deleteList(auth);
        case SyncGetOk():
          await _mergeEnvelope(got.envelope, key, listId);
          _version = got.version;
          if ((await familySnapshot(ref)).identity?.paired ?? false) {
            // Otro móvil ya usa esta lista: se queda, y se sincroniza.
            await _writeInviteCopy(listId, false);
            return;
          }
          await transport.deleteList(auth);
      }
      await _writeInviteCopy(listId, false);
    } on Object {
      return;
    }
    _version = null;
    _synced = null;
    _hasUploaded = false;
    if (ref.mounted && state.phase == SyncPhase.synced && !_wasPaired) {
      // Ya no hay nada en el servidor: vuelve a ser un solo móvil.
      state = SyncStatus(
        SyncPhase.waitingForPeer,
        lastSyncAt: state.lastSyncAt,
      );
    }
  }

  /// v2: un emparejamiento que ofrecía este móvil acabó sin nadie nuevo
  /// (cancelado, «No coinciden», caducado o fallido al aprobar). Si este
  /// móvil sigue solo en su registro, la lista que subió para invitar sobra
  /// en el servidor: se borra (`DELETE` condicional) y, como su `syncId` ya
  /// no vuelve, se estrena aquí una generación nueva sin subir nada
  /// (revisión de la fase 2b, hallazgo 14). Con otro móvil en el registro,
  /// o en el servidor, no se toca.
  ///
  /// No lanza: si falla (sin red), la marca se queda y se reintenta al
  /// arrancar y al volver a primer plano. [onlyMarked]: solo si la marca
  /// sigue puesta para la generación actual (el reintento).
  Future<void> dropV2InviteCopy({bool onlyMarked = false}) =>
      _droppingV2Copy ??= _dropV2InviteCopy(onlyMarked: onlyMarked)
          .whenComplete(() => _droppingV2Copy = null);

  Future<void>? _droppingV2Copy;

  /// Persist before uploading: a killed invitation can be cleaned on next launch,
  /// including after the server has already expired its temporary copy.
  Future<void> markV2InviteCopy(String syncId) =>
      ref.read(sharedPreferencesProvider).setString(_v2InviteCopyKey, syncId);

  Future<void> _dropV2InviteCopy({required bool onlyMarked}) async {
    final transport = ref.read(syncV2TransportProvider);
    if (transport == null) return;
    final prefs = ref.read(sharedPreferencesProvider);
    var generationChanged = false;
    try {
      await ref.read(v2FamilyLockProvider).run(() async {
        // Otro emparejamiento ya ha empezado: la lista le hace falta.
        if (_v2Pairing || !ref.mounted) return;
        final local = await AppSyncV2Local.load(ref);
        final marked = prefs.getString(_v2InviteCopyKey);
        if (local == null || (onlyMarked && marked != local.identity.syncId)) {
          await prefs.remove(_v2InviteCopyKey);
          return;
        }
        final me = local.identity.deviceId;
        final view = await (await local.registry()).viewFor(
          me: me,
          mySigningKey: local.keys.publicKeys.signing,
          livePeople: const {},
        );
        final pending = await local.readState();
        if (view.paired ||
            await ref.read(familyStoreProvider).remoteSyncEnabled() ||
            await ref.read(familyStoreProvider).recoveryActivationPending() ||
            view.pending.isNotEmpty ||
            pending.pendingRevocations.isNotEmpty ||
            pending.revocationOperations.isNotEmpty) {
          await prefs.remove(_v2InviteCopyKey);
          return;
        }
        // Si ya estaba apuntada, un intento anterior pudo borrarla y cortarse
        // antes de estrenar generación: su `syncId` ya no vale.
        final retrying = marked == local.identity.syncId;
        // Apuntada antes de hablar con el servidor: si se corta, se reintenta.
        await prefs.setString(_v2InviteCopyKey, local.identity.syncId);
        final auth = V2Auth(
          syncId: local.identity.syncId,
          deviceId: me,
          credential: local.keys.serviceCredential,
        );
        var gone = false;
        for (var attempt = 0; attempt < 3 && !gone; attempt++) {
          final got = await transport.getList(auth);
          if (got is V2GetNotFound) {
            // Nunca llegó a subir: no hay nada que borrar ni generación que
            // estrenar.
            if (!retrying) {
              await prefs.remove(_v2InviteCopyKey);
              return;
            }
            gone = true;
          } else if (got is V2GetOk) {
            if (got.snapshot.devices.any(
              (d) => d.deviceId != me && !d.revoked,
            )) {
              // Otro móvil ya tiene credencial aquí: la lista es suya también.
              await prefs.remove(_v2InviteCopyKey);
              return;
            }
            final deleted = await transport.deleteList(
              auth,
              version: got.snapshot.version,
            );
            gone = deleted is! V2WriteStale;
          } else {
            return;
          }
        }
        if (!gone) return;
        _closeWatch();
        _v2Auth = null;
        await startNewGenerationV2(ref);
        generationChanged = true;
        await prefs.remove(_v2InviteCopyKey);
      });
    } on Object {
      return;
    }
    // Clearing an obsolete invitation marker leaves the registry unchanged.
    // Invalidating it can cancel an in-flight review read during startup.
    if (generationChanged && ref.mounted) {
      ref.invalidate(localRegistryViewProvider);
    }
  }

  // ---------------------------------------------------------- credenciales

  /// Las credenciales de la lista de este móvil, o `null` si no hay familia.
  Future<SyncCredentials?> credentials() => _credentials();

  Future<SyncCredentials?> _credentials() async {
    final fam = await familySnapshot(ref);
    final identity = fam.identity;
    final key = _family.familyKey;
    if (identity == null || key == null) {
      return null;
    }
    final cached = _auth;
    if (cached != null && cached.listId == identity.listId && _key == key) {
      return cached;
    }
    final auth = SyncCredentials(
      listId: identity.listId,
      syncId: await SyncKeys.syncId(key),
      authKey: await SyncKeys.authKey(key),
    );
    _auth = auth;
    _key = key;
    return auth;
  }

  /// Las credenciales de la lista, una vez que la lista ya está en el servidor
  /// y al día (para crear invitaciones). Lanza [SyncNotReadyException] si la
  /// sincronización está apagada, sin servidor o sin red.
  ///
  /// Invitar es justo para conectar el segundo móvil: aunque todavía no haya
  /// ninguno emparejado, aquí la lista sube (el servidor la necesita para
  /// crear la invitación). Lo que se edite después espera a que alguien entre.
  Future<SyncCredentials> readyCredentials() async {
    if (_transport == null || _listId == null || !state.active) {
      throw SyncNotReadyException(state);
    }
    // Desde aquí y hasta `inviteSettled` hay una invitación a medio crear.
    _inviting = true;
    final identity = (await familySnapshot(ref)).identity;
    if (identity != null && !identity.paired) {
      // Si después nadie entra, esta copia sobra: queda apuntada antes de
      // subirla, para que no se pierda de vista aunque la app se cierre.
      await _writeInviteCopy(identity.listId, true);
    }
    _inviteUpload = true;
    try {
      await syncNow();
    } finally {
      _inviteUpload = false;
    }
    final auth = await _credentials();
    if (auth == null || state.phase != SyncPhase.synced) {
      throw SyncNotReadyException(state);
    }
    return auth;
  }

  // ----------------------------------------------------------- disparadores

  void _onFamily(
    AsyncValue<FamilyState>? previous,
    AsyncValue<FamilyState> next,
  ) {
    final fam = next.value;
    if (fam == null) {
      return;
    }
    unawaited(ref.read(recoveryApplicationProvider.notifier).refresh());
    final listId = fam.identity?.listId;
    final key = _family.familyKey;
    final changedFamily =
        listId != _listId ||
        (listId != null && key != null && _key != null && _key != key);
    final paired = fam.identity?.paired ?? false;
    final becamePaired = paired && !_wasPaired;
    _wasPaired = paired;
    if (changedFamily) {
      _listId = listId;
      _resetSession();
      if (listId == null) {
        state = const SyncStatus(SyncPhase.noFamily);
        return;
      }
      if (!_isEnabled(listId)) {
        state = const SyncStatus(SyncPhase.disabled);
        return;
      }
      state = const SyncStatus(SyncPhase.idle);
      unawaited(syncNow());
      _sweepInviteCopy();
      return;
    }
    if (listId == null || state.phase == SyncPhase.disabled) {
      return;
    }
    if (becamePaired) {
      // Ya hay segundo móvil (leyó el QR, entró con la invitación o llegó un
      // fichero suyo): la sincronización empieza ya, sin el retardo.
      unawaited(syncNow());
      return;
    }
    final before = previous?.value?.doc;
    if (before == null ||
        !identical(before, fam.doc) ||
        previous?.value?.protectionRevision != fam.protectionRevision) {
      _scheduleUpload();
    }
  }

  void _scheduleUpload() {
    _debounce?.cancel();
    _debounce = Timer(_timing.debounce, () {
      _debounce = null;
      unawaited(syncNow());
    });
  }

  void _resetSession() {
    _debounce?.cancel();
    _debounce = null;
    _retry?.cancel();
    _retry = null;
    _peerPoll?.cancel();
    _peerPoll = null;
    _closeWatch();
    _version = null;
    _synced = null;
    _hasUploaded = false;
    _auth = null;
    _key = _family.familyKey;
    _failures = 0;
  }

  void _onForeground() {
    _foreground = true;
    _legacyChecked = false;
    if (state.active) {
      unawaited(syncNow());
    }
    _sweepInviteCopy();
  }

  void _onBackground() {
    _foreground = false;
    _peerPoll?.cancel();
    _peerPoll = null;
    _closeWatch();
    if (!_wasPaired) {
      // Sin segundo móvil no hay nada que enviar: en segundo plano no queda
      // ni un reintento ni una consulta pendiente.
      _retry?.cancel();
      _retry = null;
      _debounce?.cancel();
      _debounce = null;
      return;
    }
    // Lo pendiente sale ya: el sistema puede dormir la app en cualquier
    // momento.
    if (_debounce != null && state.active) {
      _debounce?.cancel();
      _debounce = null;
      unawaited(syncNow());
    }
  }

  // ------------------------------------------------------------------ ciclo

  /// Sincroniza ya y completa cuando acaba (sin lanzar errores: el resultado
  /// queda en el estado). Si hay un ciclo en marcha, pide otra vuelta y
  /// espera a que acabe.
  Future<void> syncNow() {
    if (_claimingRecovery) return Future<void>.value();
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    return _running = _loop().whenComplete(() => _running = null);
  }

  Future<void> _loop() async {
    var ok = true;
    do {
      _again = false;
      ok = await _once();
    } while (_again && ok && ref.mounted && !_claimingRecovery);
  }

  /// Un ciclo completo. Devuelve `false` si falló.
  Future<bool> _once() async {
    if (_transport == null || !ref.mounted) {
      return true;
    }
    _debounce?.cancel();
    _debounce = null;
    _retry?.cancel();
    _retry = null;
    _peerPoll?.cancel();
    _peerPoll = null;
    final restore = await ref.read(recoveryStoreProvider).readRestore();
    if (!ref.mounted) return true;
    if (restore != null && restore.phase != RecoveryPhase.active) {
      if (restore.phase == RecoveryPhase.needsAttention) {
        _fail(SyncIssue.unreadable);
        return false;
      }
      await resumeRecoveryBeforeFamily(ref);
      if (!ref.mounted) return true;
      final current = await ref.read(recoveryStoreProvider).readRestore();
      if (current?.phase != RecoveryPhase.active) {
        _fail(SyncIssue.server, retry: true);
        return false;
      }
      ref.invalidate(familyControllerProvider);
    }
    final SyncCredentials? auth;
    final FamilyKey? key;
    final FamilyState fam;
    try {
      fam = await familySnapshot(ref);
      auth = await _credentials();
      key = _family.familyKey;
    } on Object {
      _fail(SyncIssue.unknown);
      return false;
    }
    final identity = fam.identity;
    if (identity == null || auth == null || key == null) {
      state = const SyncStatus(SyncPhase.noFamily);
      return true;
    }
    if (!_isEnabled(identity.listId)) {
      state = SyncStatus(SyncPhase.disabled, lastSyncAt: state.lastSyncAt);
      return true;
    }
    try {
      // También la recuperación y la carga deben ver una generación completa:
      // el invitado puede estar sustituyendo la identidad y las claves.
      final v2Result = await ref
          .read(familyControllerProvider.notifier)
          .withRecoveredSelfPersonChange(() async {
            await finishPendingV2(ref);
            var local = await AppSyncV2Local.load(ref);
            if (local == null &&
                await ref
                    .read(familyStoreProvider)
                    .recoveryActivationPending()) {
              local = await ensureV2FamilyWithinLock(ref);
              await ref.read(generationStoreProvider).adoptCurrent();
            }
            if (!ref.mounted) return true;
            if (local == null) return null;
            return _onceV2(local);
          });
      if (v2Result != null) return v2Result;
    } on Object {
      _fail(SyncIssue.unknown);
      return false;
    }
    if (!ref.mounted) return true;
    _v2Auth = null;
    if (syncProtocolOf(fam.doc) == kSyncProtocolV2) {
      // Una migración a medias (el documento ya es de v2 y falta la
      // identidad): este móvil ya no habla en v1. Se termina al emparejar.
      _closeWatch();
      state = SyncStatus(
        SyncPhase.waitingForPeer,
        lastSyncAt: state.lastSyncAt,
      );
      return true;
    }
    final listId = identity.listId;
    // Solo sube quien ya tiene otro móvil emparejado o quien va a crear una
    // invitación. Quien enseñó su QR mira si el otro ha entrado, sin subir.
    final upload = identity.paired || _inviteUpload;
    _pollOnly = !upload;
    if (!upload && !_awaitsPeer(listId)) {
      // Un solo móvil: ni una petición. Si la espera del QR ya caducó, su
      // marca se borra: no queda apuntado para siempre que se enseñó.
      if (_peerWaitSince(listId) != null) {
        await _writePeerWait(listId, null);
      }
      _closeWatch();
      state = SyncStatus(
        SyncPhase.waitingForPeer,
        lastSyncAt: state.lastSyncAt,
      );
      return true;
    }
    if (upload && state.phase != SyncPhase.syncing) {
      state = state.copyWith(phase: SyncPhase.syncing);
    }
    try {
      await _exchange(auth, key, identity, upload: upload);
      if (!ref.mounted) {
        return true;
      }
      _failures = 0;
      final paired = (await familySnapshot(ref)).identity?.paired ?? false;
      if (paired) {
        // Con un segundo móvil, la copia del servidor ya no sobra.
        await _writeInviteCopy(listId, false);
      }
      if (paired && _peerWaitSince(listId) != null) {
        // El otro móvil ya entró: la espera sobra.
        await _writePeerWait(listId, null);
        if (!identity.paired && ref.mounted) {
          // Lo ha visto este ciclo: el móvil que enseñó el QR lo dice.
          ref
              .read(peerConnectedProvider.notifier)
              .announce((await familySnapshot(ref)).identity?.peerName);
        }
      }
      if (paired || upload) {
        state = SyncStatus(SyncPhase.synced, lastSyncAt: clock.now());
      } else {
        state = SyncStatus(
          SyncPhase.waitingForPeer,
          lastSyncAt: state.lastSyncAt,
        );
        _schedulePeerPoll(listId);
      }
      // El WebSocket, solo con un segundo móvil.
      if (paired) {
        _ensureWatch();
      }
      return true;
    } on _Stale {
      return true;
    } on SyncTransportException catch (e) {
      _onTransportFailure(e);
    } on ImportClockDriftException {
      _fail(SyncIssue.clockDrift);
    } on EnvelopeTooLargeException {
      _fail(SyncIssue.tooLarge);
    } on EnvelopeException {
      _fail(SyncIssue.unreadable);
    } on _FirstUploadTooLarge {
      _fail(SyncIssue.firstUploadTooLarge);
    } on _ConflictLoop {
      _fail(SyncIssue.server, retry: true);
    } on Object {
      _fail(SyncIssue.unknown, retry: true);
    }
    return false;
  }

  // ------------------------------------------------------------------- v2

  /// v2: un emparejamiento empieza o acaba. Mientras dura, la lista sube
  /// aunque este móvil esté solo (el servidor la necesita para invitar).
  void setV2Pairing(bool pairing) => _v2Pairing = pairing;

  /// Una vuelta v2 (ADR 0004): instantánea atómica, reconciliación y subida
  /// condicional ([SyncV2Engine]). Con un solo móvil en el registro no habla
  /// con el servidor, salvo durante un emparejamiento o una revocación pendiente.
  // El llamador mantiene v2FamilyLockProvider durante toda la vuelta.
  Future<bool> _onceV2(AppSyncV2Local local) async {
    final transport = ref.read(syncV2TransportProvider);
    if (transport == null) {
      state = const SyncStatus(SyncPhase.notConfigured);
      return true;
    }
    _pollOnly = false;
    final auth = V2Auth(
      syncId: local.identity.syncId,
      deviceId: local.identity.deviceId,
      credential: local.keys.serviceCredential,
    );
    if (_v2Auth?.syncId != auth.syncId) {
      _closeWatch();
    }
    _v2Auth = auth;
    // El motor guarda el registro antes de pasos que pueden fallar: si la
    // vuelta llegó a empezar y no terminó bien, la vista se vuelve a leer
    // igual (en `finally`).
    var registryTouched = false;
    try {
      if (await ref.read(familyStoreProvider).isTransferred()) {
        _stopTransferred();
        return true;
      }
      final store = ref.read(familyStoreProvider);
      final acknowledgement = await store.pendingInviteAcknowledgement();
      if (acknowledgement != null) {
        try {
          if (acknowledgement['syncId'] == auth.syncId) {
            await transport.releaseInviteCheckpoint(
              acknowledgement['inviteId']!,
              credential: local.keys.serviceCredential,
            );
          }
          await store.savePendingInviteAcknowledgement(null);
        } on V2ForbiddenException {
          // This credential belongs to an expired invitation, not necessarily
          // to an invalid list. It must not gate ordinary synchronization.
          await store.savePendingInviteAcknowledgement(null);
        } on SyncTransportException catch (error) {
          if (error.failure == SyncFailure.unauthorized) {
            await store.savePendingInviteAcknowledgement(null);
          }
          // Network/server/rate limits keep the receipt for a later round.
        }
      }
      if (await store.recoveryRemovalPending()) {
        try {
          final maintenance = await recoveryMaintenanceWithinLock(ref);
          final recovery = ref.read(recoveryStoreProvider);
          final pending = await recovery.readMaintenance(auth.syncId);
          final retired =
              (await recovery.readMaterial(auth.syncId))?['retired'] == true;
          if (maintenance == null ||
              (!retired &&
                  pending?['kind'] != RecoveryMaintenanceKind.retire.name)) {
            await store.setRecoveryRemovalPending(false);
          } else {
            await maintenance.retire();
            if (await finishRecoveryRemovalWithinLock()) return true;
          }
        } on Object catch (error) {
          if ((error is RecoveryTransportException && error.retryable) ||
              (error is SyncTransportException &&
                  const {
                    SyncFailure.network,
                    SyncFailure.server,
                    SyncFailure.rateLimited,
                  }.contains(error.failure)) ||
              error is V2TransferredException ||
              (error is V2ForbiddenException &&
                  error.code == 'credential_replaced')) {
            rethrow;
          }
          await store.setRecoveryRemovalPending(false);
        }
      }
      final registry = await local.registry();
      final view = await registry.viewFor(
        me: auth.deviceId,
        mySigningKey: local.keys.publicKeys.signing,
        livePeople: const {},
      );
      final pending = await local.readState();
      if (view.revokedByOthers || (pending.health?.revokedByOthers ?? false)) {
        await _markRemoved(local);
        return true;
      }
      if (!view.paired &&
          !await ref.read(familyStoreProvider).remoteSyncEnabled() &&
          !await ref.read(familyStoreProvider).recoveryActivationPending() &&
          !_v2Pairing &&
          pending.pendingRevocations.isEmpty &&
          pending.pendingUnbackedRevocations.isEmpty &&
          pending.revocationOperations.isEmpty) {
        if (!pending.created) {
          _closeWatch();
          state = SyncStatus(
            SyncPhase.waitingForPeer,
            lastSyncAt: state.lastSyncAt,
          );
          return true;
        }
        // A previously uploaded copy may have newer membership or content.
        // Merge it before considering retirement, even with no local peer.
      }
      if (state.phase != SyncPhase.syncing) {
        state = state.copyWith(phase: SyncPhase.syncing);
      }
      final setup = await ref.read(familyStoreProvider).readRecoverySetup();
      if (setup != null) {
        final maintenance = await recoveryMaintenanceWithinLock(ref);
        if (maintenance != null) {
          await maintenance.queueNewCode(
            RecoveryCode(decodeBase64Url(setup['entropy'] as String)),
            rotate: setup['rotate'] as bool,
          );
          await ref.read(familyStoreProvider).clearRecoverySetup();
        }
      }
      final engine = SyncV2Engine(transport: transport, local: local);
      final familyStore = ref.read(familyStoreProvider);
      if (await familyStore.recoveryPersonInvalidationPending()) {
        await _maintainRecoveryWithinLock();
        if (await familyStore.recoveryPersonInvalidationPending()) {
          state = SyncStatus(SyncPhase.idle, lastSyncAt: state.lastSyncAt);
          return true;
        }
      }
      registryTouched = true;
      await engine.ensureCreated();
      final out = await engine.sync();
      if (await familyStore.recoveryActivationPending()) {
        await familyStore.enableRemoteSync();
        await familyStore.setRecoveryActivationPending(false);
      }
      await _maintainRecoveryWithinLock();
      if (!ref.mounted) return true;
      if (await _retireUnsharedListWithinLock(local, out)) return true;
      _version = out.version;
      unbackedCredentials = out.unbackedCredentials;
      renewSuggested = out.renewSuggested;
      // Slots que no cupieron en el PUT: otra vuelta en seguida.
      if (out.morePending) _again = true;
      _failures = 0;
      // Terminada la vuelta, el registro puede haber cambiado (otro móvil
      // entró o salió): se vuelve a leer, una vez por vuelta.
      registryTouched = false;
      ref.invalidate(localRegistryViewProvider);
      state = SyncStatus(SyncPhase.synced, lastSyncAt: clock.now());
      if (out.view.paired || await familyStore.remoteSyncEnabled()) {
        _ensureWatch();
        if (!_legacyChecked) {
          _legacyChecked = true;
          unawaited(_retireLegacyV1(local, force: false));
        }
      }
      return true;
    } on V2TransferredException {
      _stopTransferred();
      return true;
    } on V2RevokedException {
      await _markRemoved(local);
      return true;
    } on V2ListGoneException {
      // La lista ya no está en el servidor (la borró el último móvil o
      // caducó): este móvil estrena una
      // generación propia, sin otros móviles, y se queda esperando a volver
      // a conectar uno en persona (hallazgo 2). No se pierde nada local.
      _closeWatch();
      _v2Auth = null;
      try {
        await startNewGenerationV2(ref);
      } on Object {
        _fail(SyncIssue.unknown, retry: true);
        return false;
      }
      if (!ref.mounted) return true;
      ref.invalidate(localRegistryViewProvider);
      state = SyncStatus(
        SyncPhase.waitingForPeer,
        lastSyncAt: state.lastSyncAt,
      );
      return true;
    } on V2RollbackException {
      _fail(SyncIssue.server, retry: true);
    } on V2GenerationFullException {
      // Para siempre en este syncId: hace falta renovar (fase 3).
      renewSuggested = true;
      _fail(SyncIssue.server);
    } on SyncTransportException catch (e) {
      if (e.failure == SyncFailure.unauthorized) {
        _fail(SyncIssue.auth, retry: true);
        return false;
      }
      _onTransportFailure(e);
    } on V2ForbiddenException catch (e) {
      if (e.code == 'revoked') {
        await _markRemoved(local);
        return true;
      }
      if (e.code == 'credential_replaced') {
        await local.markSyncTransferred();
        _stopTransferred();
        return true;
      }
      _fail(SyncIssue.server, retry: true);
    } on V2CommonFormatException {
      // B4: el servidor pide otro formato del común (hay que actualizar).
      // La interfaz (lote 6) le dará su propio aviso.
      _fail(SyncIssue.unreadable);
    } on ImportClockDriftException {
      _fail(SyncIssue.clockDrift);
    } on EnvelopeTooLargeException {
      _fail(SyncIssue.tooLarge);
    } on EnvelopeException {
      _fail(SyncIssue.unreadable);
    } on Object {
      _fail(SyncIssue.unknown, retry: true);
    } finally {
      if (registryTouched && ref.mounted) {
        ref.invalidate(localRegistryViewProvider);
      }
    }
    return false;
  }

  /// La copia v1 que queda tras migrar: se fusiona lo que hayan escrito los
  /// móviles que siguen en v1 y se borra del servidor cuando todos los que
  /// escribieron en ella están en el registro v2 (o con [force], «Dejar de
  /// sincronizar»). No lanza: si falla, se mira en la siguiente sesión.
  Future<void> _maintainRecoveryWithinLock() async {
    try {
      await (await recoveryMaintenanceWithinLock(ref))?.maintain();
      await ref.read(recoveryApplicationProvider.notifier).refresh();
    } on Object catch (error) {
      if (ref.mounted) {
        await ref
            .read(recoveryApplicationProvider.notifier)
            .reportMaintenanceFailure(error);
      }
    }
  }

  Future<bool> _retireLegacyV1(
    AppSyncV2Local local, {
    required bool force,
  }) async {
    final v1 = _transport;
    final store = ref.read(familyStoreProvider);
    try {
      final raw = await store.readLegacyV1();
      if (raw == null || v1 == null) return true;
      final legacy = LegacyV1.fromJson(raw);
      final result = await retireV1(
        transport: v1,
        legacy: legacy,
        registry: await local.registry(),
        force: force,
        // B4: tras el corte al formato 2 la copia v1 ya no se absorbe.
        closed: await local.commonFormatFloor() >= kCommonFormatLatest,
        absorb: (v1Doc) async {
          // Comprueba los dos protocolos antes de fusionar (lanza si no).
          mergeLocalV1IntoV2(v2Doc: await local.common(), localV1: v1Doc);
          await _family.mergeRemote(v1Doc, fromNode: local.node);
        },
      );
      if (result == V1Retirement.retired) {
        await store.saveLegacyV1(null);
        if (ref.mounted) ref.invalidate(syncReconnectNeededProvider);
      }
      return true;
    } on Object {
      return false;
    }
  }

  /// v2: este móvil sale de la familia (revoca su propia credencial, retira
  /// sus slots y deja de sincronizar) sin borrar la lista para los demás.
  /// Lo local se queda. Lanza [SyncTransportException] si el servidor no
  /// responde (y la sincronización vuelve a quedar como estaba).
  Future<void> leaveFamily() => stopSyncing();

  /// v2: quita el móvil [deviceId] de la familia (registro firmado y
  /// servidor) y devuelve los huérfanos que hay que confirmar (fase 3).
  /// Lanza [SyncNotReadyException] si la familia no está en v2. Va dentro del
  /// cerrojo v2, como una vuelta.
  ///
  /// [rememberOrphans] anota los huérfanos antes de guardar nada ni hablar
  /// con la red (ver `family_devices.removeDevice`). Si [selfWaitAccepted] es
  /// falso, N7 se comprueba dentro del mismo cerrojo que calcula y guarda la
  /// revocación, y si este móvil volvería a esperar aprobación lanza
  /// [device_actions.DeviceRemovalChangedException] sin cambiar nada.
  Future<RegistryChange> removeDevice(
    String deviceId, {
    Future<void> Function(List<KnownDevice> orphans)? rememberOrphans,
    bool selfWaitAccepted = true,
  }) async {
    await _running;
    return ref.read(v2FamilyLockProvider).run(() async {
      final v2 = await AppSyncV2Local.load(ref);
      final transport = ref.read(syncV2TransportProvider);
      if (v2 == null || transport == null) {
        throw SyncNotReadyException(state);
      }
      try {
        if (!selfWaitAccepted &&
            (await device_actions.previewRemoval(
              local: v2,
              deviceId: deviceId,
            )).selfWouldWait) {
          throw const device_actions.DeviceRemovalChangedException();
        }
        V2SyncOutcome? outcome;
        final change = await family_devices.removeDevice(
          transport: transport,
          local: v2,
          deviceId: deviceId,
          rememberOrphans: rememberOrphans,
          onSynced: (out) => outcome = out,
        );
        if (outcome != null) await _retireUnsharedListWithinLock(v2, outcome!);
        return change;
      } finally {
        if (ref.mounted) ref.invalidate(localRegistryViewProvider);
      }
    });
  }

  /// v2: qué pasaría al quitar [deviceId], sin hacerlo: si este móvil
  /// volvería a esperar aprobación (N7: es el único activo que aprobó su
  /// ficha actual) y qué huérfanos habría que confirmar. Lanza
  /// [SyncNotReadyException] si la familia no está en v2.
  Future<device_actions.RemovalPreview> previewRemoveDevice(
    String deviceId,
  ) async {
    await _running;
    return ref.read(v2FamilyLockProvider).run(() async {
      final v2 = await AppSyncV2Local.load(ref);
      if (v2 == null) throw SyncNotReadyException(state);
      return device_actions.previewRemoval(local: v2, deviceId: deviceId);
    });
  }

  /// v2: este móvil aprueba a [deviceId] (un pendiente, un huérfano, un
  /// escritor congelado o uno que nos avaló y cuelga de un revocado), uno a
  /// uno, y publica el registro. Solo la persona lo decide en la pantalla:
  /// nada aprueba en bloque. [recordDigest] es la ficha mostrada, para un
  /// huérfano que ya no sale en la vista (ver [device_actions.approveFamilyDevice]).
  /// Lanza [SyncNotReadyException] si la familia no está en v2 y
  /// [RegistryException] si ese móvil no se puede aprobar.
  Future<RegistryChange> approveDevice(
    String deviceId, {
    String? recordDigest,
  }) async {
    final transport = ref.read(syncV2TransportProvider);
    await _running;
    try {
      return await ref.read(v2FamilyLockProvider).run(() async {
        final v2 = await AppSyncV2Local.load(ref);
        if (v2 == null || transport == null) {
          throw SyncNotReadyException(state);
        }
        return device_actions.approveFamilyDevice(
          transport: transport,
          local: v2,
          deviceId: deviceId,
          recordDigest: recordDigest,
        );
      });
    } finally {
      if (ref.mounted) ref.invalidate(localRegistryViewProvider);
    }
  }

  /// «Dejar de sincronizar» en v2: `DELETE` condicional con la versión que
  /// se acaba de leer, y la copia v1 que quedara.
  Future<void> _stopV2(AppSyncV2Local local, SyncV2Transport transport) async {
    final auth = V2Auth(
      syncId: local.identity.syncId,
      deviceId: local.identity.deviceId,
      credential: local.keys.serviceCredential,
    );
    for (var attempt = 0; attempt < 3; attempt++) {
      final got = await transport.getList(auth);
      if (got is! V2GetOk) break;
      final deleted = await transport.deleteList(
        auth,
        version: got.snapshot.version,
      );
      if (deleted is! V2WriteStale) break;
    }
    await _retireLegacyV1(local, force: true);
  }

  void _onTransportFailure(SyncTransportException e) {
    switch (e.failure) {
      case SyncFailure.network:
        if (_backToWaiting()) {
          return;
        }
        _failures++;
        state = SyncStatus(SyncPhase.offline, lastSyncAt: state.lastSyncAt);
        _scheduleRetry(_timing.backoffFor(_failures));
      case SyncFailure.unauthorized:
        _fail(SyncIssue.auth);
      case SyncFailure.tooLarge:
        _fail(SyncIssue.tooLarge);
      case SyncFailure.rateLimited:
        _fail(SyncIssue.rateLimited, retry: true, wait: e.retryAfter);
      case SyncFailure.server:
      case SyncFailure.protocol:
        _fail(SyncIssue.server, retry: true);
    }
  }

  void _fail(SyncIssue issue, {bool retry = false, Duration? wait}) {
    if (!ref.mounted || (retry && _backToWaiting(wait: wait))) {
      return;
    }
    state = SyncStatus(
      SyncPhase.error,
      lastSyncAt: state.lastSyncAt,
      issue: issue,
    );
    if (retry) {
      _failures++;
      final backoff = _timing.backoffFor(_failures);
      _scheduleRetry(wait != null && wait > backoff ? wait : backoff);
    }
  }

  /// Un fallo pasajero (sin red, `5xx`, `429`) mientras este móvil, sin nadie
  /// emparejado, solo miraba si había entrado el que leyó su QR: no es «sin
  /// conexión» ni un error, porque no hay nada que enviar. Vuelve a
  /// [SyncPhase.waitingForPeer] sin reintentos con espera creciente; la
  /// siguiente consulta es la del sondeo, solo con la app delante. Devuelve
  /// `false` si no es el caso.
  bool _backToWaiting({Duration? wait}) {
    if (!_pollOnly || _wasPaired) {
      return false;
    }
    if (ref.mounted) {
      state = SyncStatus(
        SyncPhase.waitingForPeer,
        lastSyncAt: state.lastSyncAt,
      );
      final listId = _listId;
      if (listId != null) {
        _schedulePeerPoll(listId, atLeast: wait);
      }
    }
    return true;
  }

  void _scheduleRetry(Duration delay) {
    _retry?.cancel();
    _retry = Timer(delay, () {
      _retry = null;
      unawaited(syncNow());
    });
  }

  /// Baja, fusiona y sube. Con [upload] a `false` (un móvil que enseñó su QR
  /// y aún no tiene a nadie emparejado) solo baja: sube si lo que encuentra es
  /// la primera copia del otro móvil, que lo deja emparejado.
  Future<void> _exchange(
    SyncCredentials auth,
    FamilyKey key,
    FamilyIdentity identity, {
    required bool upload,
  }) async {
    final transport = _transport!;
    final listId = identity.listId;
    var conflicts = 0;
    var needGet = true;
    var mayUpload = upload;
    while (true) {
      if (needGet) {
        final got = await transport.getList(auth, ifNoneMatch: _version);
        switch (got) {
          case SyncGetOk():
            await _mergeEnvelope(got.envelope, key, listId);
            _version = got.version;
          case SyncGetNotModified():
            break;
          case SyncGetNotFound():
            _version = null;
            _synced = null;
        }
        needGet = false;
      }
      if (!mayUpload) {
        final now = await familySnapshot(ref);
        if (now.identity?.listId != listId) {
          throw const _Stale();
        }
        if (!(now.identity?.paired ?? false)) {
          return;
        }
        mayUpload = true;
      }
      final doc = await _doc(listId);
      final canonical = doc.canonicalJson();
      if (_synced == canonical) {
        return;
      }
      final envelope = await _sealOffThread(doc, identity, key);
      // Si la sincronización se apagó a mitad de ciclo («Dejar de
      // sincronizar», «Borrar todo»), este ciclo ya no sube: su `PUT` podría
      // llegar después del `DELETE` y dejar otra vez la lista en el servidor.
      if (!_isEnabled(listId)) {
        throw const _Stale();
      }
      final SyncPutResult put;
      try {
        put = await transport.putList(
          auth,
          baseVersion: _version,
          envelope: envelope,
        );
      } on SyncTransportException catch (e) {
        // El servidor admite como mucho 256 KiB en una primera subida.
        if (_version == null && e.failure == SyncFailure.tooLarge) {
          throw const _FirstUploadTooLarge();
        }
        rethrow;
      }
      switch (put) {
        case SyncPutOk():
          _version = put.version;
          _synced = canonical;
          _hasUploaded = true;
          return;
        case SyncPutConflict():
          if (++conflicts > _timing.maxConflicts) {
            throw const _ConflictLoop();
          }
          final merge = await _mergeEnvelope(put.envelope, key, listId);
          _version = put.version;
          // No sobrescribir el `_synced = null` que marca la subida forzada
          // (cuando el sobre viene de otro móvil y aún no hemos subido).
          if (merge.same && !merge.forceUpload) {
            _synced = (await _doc(listId)).canonicalJson();
          }
        case SyncPutNotFound():
          if (++conflicts > _timing.maxConflicts) {
            throw const _ConflictLoop();
          }
          _version = null;
          _synced = null;
      }
    }
  }

  /// El documento actual, o `_Stale` si la familia cambió durante el ciclo.
  Future<FamilyDoc> _doc(String listId) async {
    final fam = await familySnapshot(ref);
    if (fam.identity?.listId != listId) {
      throw const _Stale();
    }
    return fam.doc;
  }

  /// Abre el sobre del servidor, lo fusiona con lo local y devuelve si lo
  /// fusionado es idéntico a lo que hay en el servidor (nada que subir) y si
  /// la subida forzada está activa.
  Future<({bool same, bool forceUpload})> _mergeEnvelope(
    Uint8List envelope,
    FamilyKey key,
    String listId,
  ) async {
    final fam = await familySnapshot(ref);
    final identity = fam.identity;
    await _doc(listId);
    final opened = await _openOffThread(envelope, key.bytes, listId);
    final FamilyDoc remote;
    try {
      remote = FamilyDoc.fromJson(opened.doc);
    } on FormatException {
      throw const EnvelopeFormatException('documento no válido');
    }
    final wasPaired = identity?.paired ?? false;
    final fromOther = identity != null && opened.fromNode != identity.node;
    await _family.mergeRemote(remote, fromNode: opened.fromNode);
    final merged = await _doc(listId);
    final same = merged.canonicalJson() == remote.canonicalJson();
    // El primer sobre de otro móvil marca el emparejado en este móvil; para
    // que el otro móvil también se entere (sobre todo por el servidor), este
    // sube su propio sobre aunque el documento no haya cambiado.
    final forceUpload = fromOther && (!_hasUploaded || !wasPaired);
    if (forceUpload) {
      _synced = null;
    } else if (same) {
      _synced = merged.canonicalJson();
    }
    return (same: same, forceUpload: forceUpload);
  }

  // -------------------------------------------------------------- WebSocket

  void _ensureWatch() {
    final auth = _auth;
    final transport = _transport;
    final v2Auth = _v2Auth;
    final v2 = ref.read(syncV2TransportProvider);
    if (!_foreground || _watch != null || _claimingRecovery) {
      return;
    }
    final Stream<SyncEvent> events;
    if (v2Auth != null && v2 != null) {
      events = v2.watch(v2Auth);
    } else if (auth != null && transport != null) {
      events = transport.watch(auth);
    } else {
      return;
    }
    _watchRetry?.cancel();
    _watchRetry = null;
    _watch = events.listen(
      (event) async {
        if (event is SyncOpenEvent) {
          // Conexión buena: se reinicia la espera y, si venía de un corte,
          // se pide lo que se haya podido perder mientras no escuchaba.
          _watchFailures = 0;
          if (_catchUp && state.active) {
            _catchUp = false;
            unawaited(syncNow());
          }
          return;
        }
        _watchFailures = 0;
        if (event is SyncVersionEvent &&
            (_version == null || event.version > _version!)) {
          unawaited(syncNow());
        } else if (event is SyncTransferredEvent) {
          await ref.read(familyStoreProvider).markTransferred();
          if (!ref.mounted) return;
          _stopTransferred();
        } else if (event is SyncRevokedEvent) {
          // v2: han revocado este móvil. Deja de escuchar y de subir.
          _closeWatch();
          await ref.read(v2FamilyLockProvider).run(() async {
            final local = await AppSyncV2Local.load(ref);
            if (local != null && local.identity.syncId == v2Auth?.syncId) {
              await _markRemoved(local);
            }
          });
        } else if (event is SyncGoneEvent && isV2) {
          _closeWatch();
          state = SyncStatus(SyncPhase.disabled, lastSyncAt: state.lastSyncAt);
        } else if (event is SyncGoneEvent && state.active) {
          // La lista ya no está en el servidor: se vuelve a subir.
          _version = null;
          _synced = null;
          unawaited(syncNow());
        }
      },
      onError: (Object _) => _onWatchEnded(),
      onDone: _onWatchEnded,
      cancelOnError: true,
    );
  }

  void _onWatchEnded() {
    _watch = null;
    if (!ref.mounted || !_foreground || !state.active) {
      return;
    }
    _watchFailures++;
    _catchUp = true;
    _watchRetry?.cancel();
    _watchRetry = Timer(_timing.watchBackoffFor(_watchFailures), () {
      _watchRetry = null;
      _ensureWatch();
    });
  }

  void _stopTransferred() {
    _again = false;
    _resetSession();
    state = SyncStatus(SyncPhase.disabled, lastSyncAt: state.lastSyncAt);
    unawaited(ref.read(recoveryApplicationProvider.notifier).refresh());
  }

  /// Conserva el motivo también si el servicio cortó antes de bajar la firma.
  /// No renueva la generación: el aviso y la copia local sobreviven al cierre.
  Future<void> _markRemoved(AppSyncV2Local local) async {
    _again = false;
    _resetSession();
    _v2Auth = null;
    final saved = await local.readState();
    if (!(saved.health?.revokedByOthers ?? false)) {
      await local.saveState(
        saved.copyWith(
          health: V2Health.fromJson({
            ...?saved.health?.toJson(),
            'revoked': true,
            'revocationConfirmed': true,
          }),
        ),
      );
    }
    if (!ref.mounted) return;
    ref.invalidate(localRegistryViewProvider);
    state = SyncStatus(SyncPhase.removed, lastSyncAt: state.lastSyncAt);
  }

  void _closeWatch() {
    _watchRetry?.cancel();
    _watchRetry = null;
    final watch = _watch;
    _watch = null;
    if (watch != null) {
      unawaited(watch.cancel());
    }
  }
}

class _Lifecycle with WidgetsBindingObserver {
  _Lifecycle(this._controller);

  final SyncController _controller;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _controller._onForeground();
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _controller._onBackground();
      case AppLifecycleState.inactive:
        break;
    }
  }
}

// ------------------------------------------------- cifrado fuera del hilo

class _Opened {
  const _Opened(this.fromNode, this.doc);

  final String fromNode;
  final Map<String, Object?> doc;
}

/// Descifra y descomprime fuera del hilo de la interfaz.
Future<_Opened> _openOffThread(
  Uint8List bytes,
  Uint8List keyBytes,
  String listId,
) => runTask(() async {
  final opened = await open(
    bytes,
    key: FamilyKey(keyBytes),
    expectedListId: listId,
  );
  return _Opened(opened.header.fromNode, opened.doc);
});

/// Comprime y cifra fuera del hilo de la interfaz.
Future<Uint8List> _sealOffThread(
  FamilyDoc doc,
  FamilyIdentity identity,
  FamilyKey key,
) {
  final json = doc.toJson();
  final listId = identity.listId;
  final node = identity.node;
  final at = doc.maxStamp?.pack() ?? '';
  final keyBytes = key.bytes;
  return runTask(
    () => seal(
      doc: json,
      listId: listId,
      fromNode: node,
      at: at,
      key: FamilyKey(keyBytes),
    ),
  );
}

/// El registro de móviles de la familia v2 visto desde este móvil (lectura
/// verificada de lo local, ADR 0004), o null si la familia sigue en v1 o no
/// hay familia v2 local. Una sola lectura de la que derivan
/// [devicePersonIdsProvider] y la lista de móviles de Ajustes.
///
/// Se vuelve a leer cuando cambia la familia y cuando se invalida a mano:
/// al terminar una vuelta de sincronización v2 (solo ahí, no en cada fase),
/// al quitar un móvil, al salir y al terminar un emparejamiento. No depende
/// de `syncControllerProvider` (que la invalida).
final localRegistryViewProvider = FutureProvider<RegistryView?>((ref) async {
  await ref.watch(familyControllerProvider.future);
  final v2 = await AppSyncV2Local.load(ref);
  if (v2 == null) return null;
  return localView(v2);
});

/// Las personas con un móvil activo en la familia (ADR 0004): no se pueden
/// archivar ni eliminar. En v2 salen del registro de móviles (también este
/// móvil); en v1, solo la persona de «Yo» de este móvil.
final devicePersonIdsProvider = FutureProvider<Set<String>>((ref) async {
  final fam = await ref.watch(familyControllerProvider.future);
  final self = fam.identity?.selfRecipientId;
  final view = await ref.watch(localRegistryViewProvider.future);
  if (view == null) return {?self};
  return devicePersonIds(view);
});

/// Si [recipientId] tiene un móvil activo en la familia.
final isDevicePersonProvider = FutureProvider.family<bool, String>(
  (ref, recipientId) async =>
      (await ref.watch(devicePersonIdsProvider.future)).contains(recipientId),
);

/// La sincronización de este móvil.
final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(
  SyncController.new,
);
