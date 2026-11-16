import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prefs/shared_preferences_provider.dart';
import '../../family/application/family_controller.dart';
import '../application/sync_controller.dart';
import '../data/sync_config.dart';
import '../data/sync_transport.dart';
import 'invite_crypto.dart';
import 'invite_link.dart';

const _activeInviteKey = kActiveInviteKey;

/// En qué punto está la invitación que crea este móvil.
enum InvitePhase {
  /// No hay invitación.
  idle,

  /// Creándola en el servidor.
  creating,

  /// Creada; nadie ha abierto el enlace todavía.
  waiting,

  /// Alguien pidió entrar: hay que aceptar o rechazar.
  request,

  /// Subiendo la aprobación.
  approving,

  /// Aceptada: la clave ya viaja cifrada hacia el otro móvil.
  approved,

  /// Rechazada o cancelada.
  rejected,

  /// Caducó (24 h) o el servidor ya no la tiene.
  expired,

  /// No se pudo; mira [InviteHostState.issue].
  failed,
}

/// Por qué falló.
enum InviteHostIssue {
  /// Sin servidor, sincronización apagada o sin red al crear.
  notReady,

  /// El servidor no contesta.
  network,

  /// Cualquier otra cosa.
  unknown,
}

/// Estado de la invitación que crea este móvil.
@immutable
class InviteHostState {
  /// Crea el estado.
  const InviteHostState(
    this.phase, {
    this.inviteId,
    this.link,
    this.expiresAt,
    this.guestName,
    this.code,
    this.issue,
  });

  /// Fase.
  final InvitePhase phase;

  /// Id de la invitación.
  final String? inviteId;

  /// Enlace para compartir (`https://<host>/i#<id>`).
  final String? link;

  /// Cuándo caduca.
  final DateTime? expiresAt;

  /// Nombre del móvil que pide entrar (no es de fiar: lo escribe el otro).
  final String? guestName;

  /// Código de verificación de 6 cifras (sin formato).
  final String? code;

  /// Causa, solo con [InvitePhase.failed].
  final InviteHostIssue? issue;

  /// Copia con otra fase y, si se da, otra causa (sin ella, se quita).
  InviteHostState copyWith(InvitePhase phase, {InviteHostIssue? issue}) =>
      InviteHostState(
        phase,
        inviteId: inviteId,
        link: link,
        expiresAt: expiresAt,
        guestName: guestName,
        code: code,
        issue: issue,
      );

  /// Si hay una invitación viva (creada y sin resolver).
  bool get active =>
      phase == InvitePhase.waiting ||
      phase == InvitePhase.request ||
      phase == InvitePhase.approving;
}

/// Quien invita: crea la invitación, ve la petición y la aprueba o rechaza.
///
/// Vive mientras la app: la invitación sigue en el servidor 24 h, y la persona
/// puede salir de la pantalla y volver.
class InviteHostController extends Notifier<InviteHostState> {
  Timer? _poll;
  Timer? _expiry;
  StreamSubscription<SyncEvent>? _watch;
  InviteKeyPair? _pair;
  Uint8List? _guestKey;
  SyncCredentials? _auth;
  bool _checking = false;

  /// El borrado en marcha de la copia de una invitación que acabó sin nadie.
  Future<void>? _dropping;

  SyncTransport? get _transport => ref.read(syncTransportProvider);

  @override
  InviteHostState build() {
    ref.onDispose(_stop);
    scheduleMicrotask(() {
      if (ref.mounted) {
        unawaited(_restore());
      }
    });
    return const InviteHostState(InvitePhase.idle);
  }

  // ------------------------------------------------------------- crear

  /// Crea una invitación nueva y empieza a esperar la petición.
  ///
  /// El estado queda en [InvitePhase.failed] si la sincronización no está
  /// lista (apagada, sin servidor, sin red).
  Future<void> create() async {
    if (state.phase == InvitePhase.creating || state.active) {
      return;
    }
    state = const InviteHostState(InvitePhase.creating);
    // Si se está borrando la copia de la invitación anterior, primero acaba:
    // ese borrado se llevaría por delante la lista y la invitación nuevas.
    await _dropping;
    if (!ref.mounted) {
      return;
    }
    final transport = _transport;
    final endpoint = ref.read(syncEndpointProvider);
    if (transport == null || endpoint == null) {
      state = const InviteHostState(
        InvitePhase.failed,
        issue: InviteHostIssue.notReady,
      );
      return;
    }
    final sync = ref.read(syncControllerProvider.notifier);
    // Si la lista ya ha subido y la invitación no llega a crearse, esa copia
    // sobra en el servidor: se borra en el mismo fallo.
    var uploaded = false;
    try {
      final auth = await sync.readyCredentials();
      uploaded = true;
      final ticket = await transport.createInvite(auth);
      if (!ref.mounted) {
        return;
      }
      state = InviteHostState(
        InvitePhase.waiting,
        inviteId: ticket.inviteId,
        link: inviteLink(endpoint.invitationHost, ticket.inviteId),
        expiresAt: ticket.expiresAt,
      );
      await _persist(auth.listId);
      uploaded = false;
      _begin(auth);
    } on SyncNotReadyException {
      _fail(InviteHostIssue.notReady);
    } on SyncTransportException catch (e) {
      _fail(
        e.failure == SyncFailure.network
            ? InviteHostIssue.network
            : InviteHostIssue.unknown,
      );
    } on Object {
      _fail(InviteHostIssue.unknown);
    } finally {
      sync.inviteSettled();
      if (uploaded && ref.mounted) {
        _dropCopy();
      }
    }
  }

  void _fail(InviteHostIssue issue) {
    if (ref.mounted) {
      state = InviteHostState(InvitePhase.failed, issue: issue);
    }
  }

  /// Pide borrar del servidor la copia cifrada que subió una invitación que
  /// no ha emparejado a nadie (si ya hay otro móvil emparejado no se toca).
  /// Una invitación nueva espera a que este borrado acabe.
  void _dropCopy() {
    final dropping = ref.read(syncControllerProvider.notifier).dropInviteCopy();
    _dropping = dropping;
    unawaited(
      dropping.whenComplete(() {
        if (identical(_dropping, dropping)) {
          _dropping = null;
        }
      }),
    );
  }

  // --------------------------------------------------------- vigilancia

  void _begin(SyncCredentials auth) {
    _stop();
    _auth = auth;
    final transport = _transport;
    if (transport == null) {
      return;
    }
    final timing = ref.read(syncTimingProvider);
    // El WebSocket avisa al momento; el sondeo lento es la red de seguridad
    // (el servidor limita las peticiones por IP a las rutas de invitación).
    _watch = transport
        .watch(auth)
        .listen(
          (event) {
            if (event is SyncJoinRequestEvent) {
              unawaited(_check());
            }
          },
          onError: (Object _) {},
          cancelOnError: true,
        );
    _poll = Timer.periodic(timing.inviteHostPoll, (_) => unawaited(_check()));
    final expires = state.expiresAt;
    if (expires != null) {
      final left = expires.difference(clock.now());
      _expiry = Timer(left.isNegative ? Duration.zero : left, () {
        if (state.active && ref.mounted) {
          _end(InvitePhase.expired);
        }
      });
    }
    unawaited(_check());
  }

  void _stop() {
    _poll?.cancel();
    _poll = null;
    _expiry?.cancel();
    _expiry = null;
    final watch = _watch;
    _watch = null;
    if (watch != null) {
      unawaited(watch.cancel());
    }
  }

  void _end(InvitePhase phase) {
    _stop();
    _pair = null;
    _guestKey = null;
    unawaited(_clearPersisted());
    if (ref.mounted) {
      state = InviteHostState(phase);
      // La invitación acabó sin que nadie entrara: la copia cifrada que subió
      // al crearla se borra del servidor.
      _dropCopy();
    }
  }

  Future<void> _check() async {
    final auth = _auth;
    final transport = _transport;
    final id = state.inviteId;
    if (_checking || auth == null || transport == null || id == null) {
      return;
    }
    if (state.phase != InvitePhase.waiting) {
      return;
    }
    final expires = state.expiresAt;
    if (expires != null && !clock.now().isBefore(expires)) {
      _end(InvitePhase.expired);
      return;
    }
    _checking = true;
    try {
      final request = await transport.getInviteRequest(auth, id);
      if (request == null ||
          !ref.mounted ||
          state.phase != InvitePhase.waiting) {
        return;
      }
      if (request.publicKey.length != 32) {
        // Una clave que no es X25519: se rechaza sin molestar a la persona.
        await reject();
        return;
      }
      final pair = await InviteCrypto.generateKeyPair();
      try {
        // Una clave de orden bajo da un secreto de ceros: no se atiende.
        await InviteCrypto.checkPeer(pair, request.publicKey);
      } on InviteCryptoException {
        await reject();
        return;
      }
      final code = await InviteCrypto.verificationCode(
        pair.publicKey,
        request.publicKey,
      );
      if (!ref.mounted || state.phase != InvitePhase.waiting) {
        return;
      }
      // Se ofrece la clave pública para que el otro móvil calcule el mismo
      // código. Hasta que la persona confirme no se entrega nada más.
      await transport.offerInvite(auth, id, pair.publicKey);
      if (!ref.mounted || state.phase != InvitePhase.waiting) {
        return;
      }
      _pair = pair;
      _guestKey = request.publicKey;
      state = InviteHostState(
        InvitePhase.request,
        inviteId: id,
        link: state.link,
        expiresAt: expires,
        guestName: cleanDeviceName(request.deviceName),
        code: code,
      );
    } on InviteGoneException {
      if (state.phase == InvitePhase.waiting) {
        _end(InvitePhase.expired);
      }
    } on SyncTransportException catch (e) {
      // Sin red o con límite: se vuelve a mirar en el siguiente aviso. Si el
      // servidor no acepta la oferta, la invitación no sirve.
      if (e.failure != SyncFailure.network &&
          e.failure != SyncFailure.rateLimited &&
          e.failure != SyncFailure.server &&
          state.phase == InvitePhase.waiting) {
        await reject();
        _fail(InviteHostIssue.unknown);
      }
    } finally {
      _checking = false;
    }
  }

  // ---------------------------------------------------------- decidir

  /// Da acceso tras comparar el código: cifra la clave de la familia para el
  /// otro móvil y la sube. Solo en [InvitePhase.request], cuando la oferta ya
  /// está en el servidor y la persona confirmó que los códigos coinciden.
  Future<void> approve() async {
    final current = state;
    final pair = _pair;
    final guestKey = _guestKey;
    final auth = _auth;
    final transport = _transport;
    final id = current.inviteId;
    final key = ref.read(familyControllerProvider.notifier).familyKey;
    final identity = ref.read(familyControllerProvider).value?.identity;
    if (current.phase != InvitePhase.request ||
        pair == null ||
        guestKey == null ||
        auth == null ||
        transport == null ||
        id == null ||
        key == null ||
        identity == null) {
      return;
    }
    state = current.copyWith(InvitePhase.approving);
    try {
      final sealed = await InviteCrypto.sealPackage(
        mine: pair,
        theirPublicKey: guestKey,
        inviteId: id,
        package: InvitePackage(
          listId: identity.listId,
          familyKey: key,
          deviceName: identity.deviceName,
        ),
      );
      await transport.approveInvite(
        auth,
        id,
        InviteApproval(ciphertext: sealed.ciphertext, nonce: sealed.nonce),
      );
      _stop();
      _pair = null;
      _guestKey = null;
      await _clearPersisted();
      if (ref.mounted) {
        // Desde ahora el otro móvil tiene la clave: este queda emparejado
        // aunque el otro todavía no haya subido nada.
        await ref
            .read(familyControllerProvider.notifier)
            .markPaired(peerName: current.guestName);
      }
      if (ref.mounted) {
        state = InviteHostState(
          InvitePhase.approved,
          guestName: current.guestName,
          code: current.code,
        );
      }
    } on InviteGoneException {
      _end(InvitePhase.expired);
    } on InviteCryptoException {
      await reject();
      _fail(InviteHostIssue.unknown);
    } on SyncTransportException catch (e) {
      // Se puede volver a pulsar Aceptar.
      if (ref.mounted) {
        state = current.copyWith(
          InvitePhase.request,
          issue: e.failure == SyncFailure.network
              ? InviteHostIssue.network
              : InviteHostIssue.unknown,
        );
      }
    }
  }

  /// Rechaza la petición (o cancela la invitación): muere en el servidor.
  Future<void> reject() async {
    final auth = _auth;
    final id = state.inviteId;
    final transport = _transport;
    if (auth == null || id == null || transport == null || !state.active) {
      return;
    }
    try {
      await transport.rejectInvite(auth, id);
    } on SyncTransportException {
      // Si no llega, caduca sola a las 24 h.
    }
    _end(InvitePhase.rejected);
  }

  /// Vuelve al principio tras ver un resultado (aceptada, rechazada,
  /// caducada, error).
  void dismiss() {
    if (!state.active && state.phase != InvitePhase.creating) {
      state = const InviteHostState(InvitePhase.idle);
    }
  }

  // ------------------------------------------------------- persistencia

  Future<void> _persist(String listId) async {
    final s = state;
    if (s.inviteId == null || s.expiresAt == null) {
      return;
    }
    await ref
        .read(sharedPreferencesProvider)
        .setString(
          _activeInviteKey,
          jsonEncode(<String, Object?>{
            'l': listId,
            'i': s.inviteId,
            'e': s.expiresAt!.millisecondsSinceEpoch,
          }),
        );
  }

  Future<void> _clearPersisted() =>
      ref.read(sharedPreferencesProvider).remove(_activeInviteKey);

  /// Recupera la invitación viva tras cerrar y abrir la app.
  Future<void> _restore() async {
    final endpoint = ref.read(syncEndpointProvider);
    if (endpoint == null || _transport == null) {
      return;
    }
    final raw = ref.read(sharedPreferencesProvider).getString(_activeInviteKey);
    if (raw == null) {
      return;
    }
    try {
      final json = jsonDecode(raw);
      if (json is! Map) {
        return;
      }
      final listId = json['l'];
      final id = json['i'];
      final ms = json['e'];
      if (listId is! String || id is! String || ms is! int || !isInviteId(id)) {
        await _clearPersisted();
        return;
      }
      final expires = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
      if (!clock.now().isBefore(expires)) {
        // Caducó con la app cerrada: se olvida, y la copia que subió se
        // borra del servidor (si no, se quedaría allí hasta que caducara
        // sola, más de un año después; revisión de seguridad, N8).
        await _clearPersisted();
        if (ref.mounted) {
          _dropCopy();
        }
        return;
      }
      final auth = await ref
          .read(syncControllerProvider.notifier)
          .credentials();
      if (!ref.mounted || state.phase != InvitePhase.idle) {
        return;
      }
      if (auth == null ||
          auth.listId != listId ||
          !clock.now().isBefore(expires)) {
        await _clearPersisted();
        return;
      }
      state = InviteHostState(
        InvitePhase.waiting,
        inviteId: id,
        link: inviteLink(endpoint.invitationHost, id),
        expiresAt: expires,
      );
      _begin(auth);
    } on FormatException {
      await _clearPersisted();
    }
  }
}

/// La invitación que crea este móvil.
final inviteHostProvider =
    NotifierProvider<InviteHostController, InviteHostState>(
      InviteHostController.new,
    );
