import 'dart:async';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';
import 'package:regalos/features/sync/domain/sync_keys.dart';

/// Servidor de sincronización falso, en memoria: imita las rutas del ADR 0002
/// (y el comportamiento de `server/src`): versiones, `409`, `304`, `404`,
/// verificador, invitaciones de un solo uso y WebSocket.
class FakeSyncServer {
  final Map<String, _ListRecord> _lists = {};
  final Map<String, _InviteRecord> _invites = {};
  int _inviteCounter = 0;

  /// Peticiones recibidas, por tipo (`get`, `put`, `delete`...).
  final Map<String, int> calls = {};

  /// `409` devueltos a un `PUT`.
  int conflicts = 0;

  /// Se llama al principio de cada `PUT` autenticado, antes de mirar la
  /// versión: sirve para que otro móvil escriba "a la vez".
  Future<void> Function(String syncId)? beforePut;

  /// Cambia la clave pública que ofreció quien invita tal como la ve quien
  /// entra (un servidor que manipula).
  Uint8List Function(Uint8List publicKeyA)? tamperOfferKey;

  /// Cambia la clave pública que ve quien invita (un servidor que se pone en
  /// medio).
  Uint8List Function(Uint8List publicKey)? tamperRequestKey;

  /// Un cliente conectado a este servidor. [offline] lo deja sin red.
  FakeSyncTransport connect() => FakeSyncTransport(this);

  /// Versión guardada de una lista, o `null`.
  int? versionOf(String syncId) => _lists[syncId]?.version;

  /// Si el servidor tiene la lista.
  bool hasList(String syncId) => _lists.containsKey(syncId);

  /// WebSocket abiertos sobre una lista.
  int watchers(String syncId) => _lists[syncId]?.watchers.length ?? 0;

  /// Invitaciones vivas.
  int get openInvites => _invites.length;

  /// Hace caducar todas las invitaciones.
  void expireInvites() {
    for (final invite in _invites.values) {
      invite.expiresAt = clock.now().subtract(const Duration(seconds: 1));
    }
  }

  /// Borra la lista como lo haría la caducidad de 400 días.
  void expireList(String syncId) => _drop(syncId);

  void _count(String what) => calls[what] = (calls[what] ?? 0) + 1;

  Future<bool> _verifies(_ListRecord list, SyncCredentials auth) async {
    final verifier = await SyncKeys.verifier(auth.authKey);
    return _same(list.verifier, verifier);
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  void _drop(String syncId) {
    final list = _lists.remove(syncId);
    _invites.removeWhere((_, invite) => invite.syncId == syncId);
    if (list != null) {
      for (final sink in List.of(list.watchers)) {
        sink.add(const SyncGoneEvent());
        unawaited(sink.close());
      }
      list.watchers.clear();
    }
  }

  _InviteRecord? _live(String inviteId) {
    final invite = _invites[inviteId];
    if (invite == null) {
      return null;
    }
    if (!invite.expiresAt.isAfter(clock.now())) {
      _invites.remove(inviteId);
      return null;
    }
    return invite;
  }
}

class _ListRecord {
  _ListRecord(this.verifier, this.envelope) : version = 1;

  final Uint8List verifier;
  Uint8List envelope;
  int version;
  final List<StreamController<SyncEvent>> watchers = [];
}

class _InviteRecord {
  _InviteRecord(this.syncId, this.expiresAt);

  final String syncId;
  DateTime expiresAt;
  InviteJoinRequest? request;
  Uint8List? offer;
  InviteApproval? approval;
}

/// El cliente de un móvil hacia [FakeSyncServer].
class FakeSyncTransport implements SyncTransport {
  FakeSyncTransport(this._server);

  final FakeSyncServer _server;

  /// Sin red: toda petición falla con [SyncFailure.network].
  bool offline = false;

  /// Si se da, todo `PUT` falla con este error (p. ej. un 413).
  SyncTransportException? putError;

  /// Si se da, todo `GET` falla con este error (p. ej. un 503 o un 429).
  SyncTransportException? getError;

  /// Si se da, todo `DELETE` de la lista falla con este error.
  SyncTransportException? deleteError;

  /// Si se da, crear una invitación falla con este error.
  SyncTransportException? inviteError;

  /// Cuándo (en ms desde que se creó el cliente) hizo cada petición
  /// [name]; para comprobar la espera creciente.
  final Map<String, List<int>> times = {};
  final Stopwatch _clock = Stopwatch()..start();

  void _enter(String what) {
    _server._count(what);
    (times[what] ??= []).add(_clock.elapsedMilliseconds);
    if (offline) {
      throw const SyncTransportException(SyncFailure.network, 'sin red');
    }
  }

  @override
  Future<SyncGetResult> getList(
    SyncCredentials auth, {
    int? ifNoneMatch,
  }) async {
    _enter('get');
    final failure = getError;
    if (failure != null) {
      throw failure;
    }
    await Future<void>.delayed(Duration.zero);
    final list = _server._lists[auth.syncId];
    if (list == null) {
      return const SyncGetNotFound();
    }
    if (!await _server._verifies(list, auth)) {
      throw const SyncTransportException(SyncFailure.unauthorized, '401');
    }
    if (ifNoneMatch == list.version) {
      return const SyncGetNotModified();
    }
    return SyncGetOk(version: list.version, envelope: list.envelope);
  }

  @override
  Future<SyncPutResult> putList(
    SyncCredentials auth, {
    required int? baseVersion,
    required Uint8List envelope,
  }) async {
    _enter('put');
    final failure = putError;
    if (failure != null) {
      throw failure;
    }
    await Future<void>.delayed(Duration.zero);
    final hook = _server.beforePut;
    if (hook != null) {
      await hook(auth.syncId);
    }
    final verifier = await SyncKeys.verifier(auth.authKey);
    final list = _server._lists[auth.syncId];
    if (list == null) {
      if (baseVersion != null) {
        return const SyncPutNotFound();
      }
      final created = _ListRecord(verifier, envelope);
      _server._lists[auth.syncId] = created;
      _notify(created);
      return const SyncPutOk(version: 1);
    }
    final ok = await _server._verifies(list, auth);
    if (baseVersion == null && !ok) {
      throw const SyncTransportException(SyncFailure.unauthorized, 'exists');
    }
    if (!ok) {
      throw const SyncTransportException(SyncFailure.unauthorized, '401');
    }
    if (baseVersion != list.version) {
      _server.conflicts++;
      return SyncPutConflict(version: list.version, envelope: list.envelope);
    }
    list
      ..version += 1
      ..envelope = envelope;
    _notify(list);
    return SyncPutOk(version: list.version);
  }

  void _notify(_ListRecord list) {
    for (final sink in list.watchers) {
      sink.add(SyncVersionEvent(list.version));
    }
  }

  @override
  Future<void> deleteList(SyncCredentials auth) async {
    _enter('delete');
    final failure = deleteError;
    if (failure != null) {
      throw failure;
    }
    final list = _server._lists[auth.syncId];
    if (list == null) {
      return;
    }
    if (!await _server._verifies(list, auth)) {
      throw const SyncTransportException(SyncFailure.unauthorized, '401');
    }
    _server._drop(auth.syncId);
  }

  @override
  Stream<SyncEvent> watch(SyncCredentials auth) {
    late StreamController<SyncEvent> controller;
    controller = StreamController<SyncEvent>(
      onListen: () async {
        _server._count('watch');
        final list = _server._lists[auth.syncId];
        if (offline) {
          controller.addError(
            const SyncTransportException(SyncFailure.network, 'sin red'),
          );
          await controller.close();
          return;
        }
        if (list == null || !await _server._verifies(list, auth)) {
          controller.addError(
            const SyncTransportException(SyncFailure.unauthorized, '401'),
          );
          await controller.close();
          return;
        }
        list.watchers.add(controller);
        controller.add(const SyncOpenEvent());
      },
      onCancel: () {
        _server._lists[auth.syncId]?.watchers.remove(controller);
      },
    );
    return controller.stream;
  }

  /// Corta a la fuerza los WebSocket abiertos de la lista (como una caída de
  /// red a medias).
  void dropSockets(String syncId) {
    final list = _server._lists[syncId];
    if (list == null) {
      return;
    }
    for (final sink in List.of(list.watchers)) {
      unawaited(sink.close());
    }
    list.watchers.clear();
  }

  // --------------------------------------------------------- invitaciones

  @override
  Future<InviteTicket> createInvite(SyncCredentials auth) async {
    _enter('createInvite');
    final failure = inviteError;
    if (failure != null) {
      throw failure;
    }
    final list = _server._lists[auth.syncId];
    if (list == null) {
      throw const SyncTransportException(SyncFailure.protocol, '404');
    }
    if (!await _server._verifies(list, auth)) {
      throw const SyncTransportException(SyncFailure.unauthorized, '401');
    }
    final raw = Uint8List(16);
    final n = ++_server._inviteCounter;
    for (var i = 0; i < 16; i++) {
      raw[i] = (n * 31 + i * 7 + 5) & 0xFF;
    }
    final inviteId = encodeBase64Url(raw);
    final expires = clock.now().add(const Duration(hours: 24));
    _server._invites[inviteId] = _InviteRecord(auth.syncId, expires);
    return InviteTicket(inviteId: inviteId, expiresAt: expires);
  }

  @override
  Future<InviteJoinRequest?> getInviteRequest(
    SyncCredentials auth,
    String inviteId,
  ) async {
    _enter('getInvite');
    final invite = _server._live(inviteId);
    if (invite == null || invite.syncId != auth.syncId) {
      throw const InviteGoneException();
    }
    final request = invite.request;
    if (request == null) {
      return null;
    }
    final tamper = _server.tamperRequestKey;
    return tamper == null
        ? request
        : InviteJoinRequest(
            publicKey: tamper(request.publicKey),
            deviceName: request.deviceName,
          );
  }

  @override
  Future<void> offerInvite(
    SyncCredentials auth,
    String inviteId,
    Uint8List publicKeyA,
  ) async {
    _enter('offer');
    final invite = _server._live(inviteId);
    if (invite == null || invite.syncId != auth.syncId) {
      throw const InviteGoneException();
    }
    if (invite.request == null || invite.offer != null) {
      throw const SyncTransportException(SyncFailure.protocol, '409');
    }
    invite.offer = Uint8List.fromList(publicKeyA);
  }

  @override
  Future<void> approveInvite(
    SyncCredentials auth,
    String inviteId,
    InviteApproval approval,
  ) async {
    _enter('approve');
    final invite = _server._live(inviteId);
    if (invite == null || invite.syncId != auth.syncId) {
      throw const InviteGoneException();
    }
    if (invite.offer == null || invite.approval != null) {
      throw const SyncTransportException(SyncFailure.protocol, '409');
    }
    invite.approval = approval;
  }

  @override
  Future<void> rejectInvite(SyncCredentials auth, String inviteId) async {
    _enter('reject');
    final invite = _server._live(inviteId);
    if (invite != null && invite.syncId == auth.syncId) {
      _server._invites.remove(inviteId);
    }
  }

  @override
  Future<void> requestJoin(
    String inviteId, {
    required Uint8List publicKey,
    required String deviceName,
  }) async {
    _enter('join');
    final invite = _server._live(inviteId);
    if (invite == null) {
      throw const InviteGoneException();
    }
    if (invite.request != null) {
      throw const InviteTakenException();
    }
    invite.request = InviteJoinRequest(
      publicKey: publicKey,
      deviceName: deviceName,
    );
    final list = _server._lists[invite.syncId];
    if (list != null) {
      for (final sink in list.watchers) {
        sink.add(const SyncJoinRequestEvent());
      }
    }
  }

  @override
  Future<InviteOutcome> pollInviteResult(
    String inviteId, {
    required Uint8List publicKey,
  }) async {
    _enter('result');
    final invite = _server._live(inviteId);
    final request = invite?.request;
    if (invite == null ||
        request == null ||
        !FakeSyncServer._same(request.publicKey, publicKey)) {
      return const InviteGone();
    }
    final offer = invite.offer;
    final approval = invite.approval;
    if (offer == null || approval == null) {
      final tamper = _server.tamperOfferKey;
      return InvitePending(
        publicKeyA: offer == null
            ? null
            : (tamper == null ? offer : tamper(offer)),
      );
    }
    _server._invites.remove(inviteId);
    return InviteApproved(approval);
  }
}
