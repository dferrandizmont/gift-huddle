import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/envelope.dart';
import '../../family/application/family_controller.dart';
import '../../family/domain/family_errors.dart';
import '../application/family_snapshot.dart';
import '../data/sync_config.dart';
import '../data/sync_transport.dart';
import 'invite_crypto.dart';
import 'invite_link.dart';

/// En qué punto está quien entra con una invitación.
enum JoinPhase {
  /// Nada en marcha.
  idle,

  /// Este móvil ya tiene una lista con datos: hay que confirmar que se
  /// sustituye (igual que al unirse con QR).
  conflict,

  /// Pidiendo entrada.
  requesting,

  /// Pedida; esperando a que el otro móvil la acepte.
  waiting,

  /// Quien invitó ya ofreció su clave pública: los dos móviles enseñan el mismo
  /// código y las personas lo comparan. Hasta que quien invitó confirme no hay
  /// clave que recoger.
  compare,

  /// Entrando en la familia.
  joining,

  /// Dentro.
  joined,

  /// La persona dijo que el código no coincide: no se entró.
  mismatch,

  /// «La invitación ha caducado o no se ha aceptado».
  gone,

  /// La invitación ya la pidió otra persona.
  taken,

  /// No se pudo; mira [InviteGuestState.issue].
  failed,
}

/// Por qué falló.
enum JoinIssue {
  /// El texto no es un enlace de invitación de este servidor.
  badLink,

  /// Sin servidor configurado en esta versión.
  unavailable,

  /// El servidor no contesta.
  network,

  /// El paquete o la clave que ofreció el servidor no valen (manipulados, de
  /// orden bajo o de otra invitación).
  tampered,

  /// Cualquier otra cosa.
  unknown,
}

/// Estado de quien entra con una invitación.
@immutable
class InviteGuestState {
  /// Crea el estado.
  const InviteGuestState(
    this.phase, {
    this.hostName,
    this.code,
    this.issue,
    this.replaced = false,
  });

  /// Fase.
  final JoinPhase phase;

  /// Nombre del móvil que invitó (viene dentro del paquete cifrado).
  final String? hostName;

  /// Código de verificación de 6 cifras (sin formato), con
  /// [JoinPhase.compare].
  final String? code;

  /// Causa, solo con [JoinPhase.failed].
  final JoinIssue? issue;

  /// Con [JoinPhase.joined]: si se sustituyó otra lista.
  final bool replaced;
}

/// Quien entra: pide entrada con el enlace, ve el código en cuanto quien invitó
/// ofrece su clave pública, y recoge la clave cuando esa persona confirma que
/// los códigos coinciden.
class InviteGuestController extends Notifier<InviteGuestState> {
  Timer? _timer;
  InviteKeyPair? _pair;
  InvitePackage? _package;
  Uint8List? _offer;
  String? _inviteId;
  String _deviceName = '';
  String _pendingText = '';
  bool _polling = false;
  Stopwatch? _waited;
  int _run = 0;

  SyncTransport? get _transport => ref.read(syncTransportProvider);

  @override
  InviteGuestState build() {
    ref.onDispose(_stop);
    return const InviteGuestState(JoinPhase.idle);
  }

  void _stop() {
    _run++;
    _timer?.cancel();
    _timer = null;
  }

  void _set(
    JoinPhase phase, {
    JoinIssue? issue,
    String? hostName,
    String? code,
  }) {
    if (ref.mounted) {
      state = InviteGuestState(
        phase,
        issue: issue,
        hostName: hostName,
        code: code,
      );
    }
  }

  /// Pide entrada con el texto pegado (el enlace completo o el id).
  ///
  /// Si este móvil ya tiene una lista con datos y no se pide [replace], el
  /// estado pasa a [JoinPhase.conflict] y no se pide nada: la interfaz
  /// confirma y repite con `replace: true` (o con [confirmReplace]).
  Future<void> begin(
    String text, {
    required String deviceName,
    bool replace = false,
  }) async {
    _stop();
    final run = _run;
    _replace = replace;
    _deviceName = cleanDeviceName(deviceName);
    _offer = null;
    _package = null;
    _pendingText = text;
    final transport = _transport;
    final endpoint = ref.read(syncEndpointProvider);
    if (transport == null || endpoint == null) {
      _set(JoinPhase.failed, issue: JoinIssue.unavailable);
      return;
    }
    final String inviteId;
    try {
      inviteId = parseInvite(text, expectedHost: endpoint.invitationHost);
    } on InviteFormatException {
      _set(JoinPhase.failed, issue: JoinIssue.badLink);
      return;
    }
    final family = await familySnapshot(ref);
    if (run != _run) {
      return;
    }
    if (family.hasFamily && family.hasData && !replace) {
      _set(JoinPhase.conflict);
      return;
    }
    _set(JoinPhase.requesting);
    try {
      final pair = await InviteCrypto.generateKeyPair();
      await transport.requestJoin(
        inviteId,
        publicKey: pair.publicKey,
        deviceName: _deviceName,
      );
      if (run != _run) {
        return;
      }
      _pair = pair;
      _inviteId = inviteId;
    } on InviteTakenException {
      _set(JoinPhase.taken);
      return;
    } on InviteGoneException {
      _set(JoinPhase.gone);
      return;
    } on SyncTransportException catch (e) {
      _set(
        JoinPhase.failed,
        issue: e.failure == SyncFailure.network
            ? JoinIssue.network
            : JoinIssue.unknown,
      );
      return;
    }
    _set(JoinPhase.waiting);
    _startPolling(run);
  }

  /// El usuario confirmó sustituir su lista: sigue con lo que se había pedido.
  Future<void> confirmReplace() async {
    if (_package != null) {
      await _join(replace: true, code: state.code);
    } else {
      await begin(_pendingText, deviceName: _deviceName, replace: true);
    }
  }

  void _startPolling(int run, {bool keepClock = false}) {
    final timing = ref.read(syncTimingProvider);
    if (!keepClock) {
      _waited = Stopwatch()..start();
    }
    _timer = Timer.periodic(timing.invitePoll, (_) => unawaited(_poll(run)));
  }

  Future<void> _poll(int run) async {
    final transport = _transport;
    final pair = _pair;
    final id = _inviteId;
    if (_polling ||
        run != _run ||
        transport == null ||
        pair == null ||
        id == null) {
      return;
    }
    if (_waited!.elapsed >= ref.read(syncTimingProvider).inviteTimeout) {
      _stop();
      _set(JoinPhase.gone);
      return;
    }
    _polling = true;
    try {
      final outcome = await transport.pollInviteResult(
        id,
        publicKey: pair.publicKey,
      );
      if (run != _run) {
        return;
      }
      switch (outcome) {
        case InvitePending(:final publicKeyA):
          if (publicKeyA != null) {
            await _onOffer(publicKeyA, pair);
          }
        case InviteGone():
          _stop();
          _set(JoinPhase.gone);
        case InviteApproved(:final approval):
          _stop();
          await _open(approval, pair, id);
      }
    } on SyncTransportException catch (e) {
      // Sin red o con límite: se vuelve a preguntar en el siguiente turno; con
      // un 429 se respeta el Retry-After del servidor.
      final wait = e.retryAfter;
      if (e.failure == SyncFailure.rateLimited && wait != null && run == _run) {
        _timer?.cancel();
        _timer = Timer(wait, () {
          if (run == _run) {
            _startPolling(run, keepClock: true);
          }
        });
      }
    } finally {
      _polling = false;
    }
  }

  /// Llega la oferta de quien invitó: se comprueba la clave, se calcula el
  /// código y se enseña. Si luego cambia la clave, el servidor está
  /// manipulando: se aborta.
  Future<void> _onOffer(Uint8List publicKeyA, InviteKeyPair pair) async {
    final known = _offer;
    if (known != null) {
      if (!_sameBytes(known, publicKeyA)) {
        _stop();
        _pair = null;
        _set(JoinPhase.failed, issue: JoinIssue.tampered);
      }
      return;
    }
    try {
      await InviteCrypto.checkPeer(pair, publicKeyA);
      final code = await InviteCrypto.verificationCode(
        publicKeyA,
        pair.publicKey,
      );
      _offer = Uint8List.fromList(publicKeyA);
      _set(JoinPhase.compare, code: code);
    } on InviteCryptoException {
      _stop();
      _pair = null;
      _set(JoinPhase.failed, issue: JoinIssue.tampered);
    }
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Quien invitó confirmó el código y subió el paquete: se abre con la clave
  /// pública que se enseñó y se entra.
  Future<void> _open(
    InviteApproval approval,
    InviteKeyPair pair,
    String id,
  ) async {
    if (!ref.mounted) {
      return;
    }
    final offer = _offer;
    if (offer == null) {
      // Clave entregada sin haber visto nunca la oferta: nadie comparó nada.
      _pair = null;
      _set(JoinPhase.failed, issue: JoinIssue.tampered);
      return;
    }
    final code = state.code;
    try {
      _package = await InviteCrypto.openPackage(
        mine: pair,
        theirPublicKey: offer,
        inviteId: id,
        ciphertext: approval.ciphertext,
        nonce: approval.nonce,
      );
    } on InviteCryptoException {
      _pair = null;
      _set(JoinPhase.failed, issue: JoinIssue.tampered);
      return;
    }
    await _join(replace: _replace, code: code);
  }

  bool _replace = false;

  /// Entra en la familia con la clave recogida.
  ///
  /// Si hay una lista con datos y no se pide [replace], el estado pasa a
  /// [JoinPhase.conflict] (por si cambió desde que se pidió).
  Future<void> _join({bool replace = false, String? code}) async {
    final package = _package;
    if (!ref.mounted || package == null || state.phase == JoinPhase.joining) {
      return;
    }
    _set(JoinPhase.joining, hostName: package.deviceName, code: code);
    try {
      final result = await ref
          .read(familyControllerProvider.notifier)
          .joinFamily(
            payload: PairingPayload(
              listId: package.listId,
              key: package.familyKey,
              deviceName: package.deviceName,
            ),
            deviceName: _deviceName,
            replace: replace,
          );
      _package = null;
      _pair = null;
      if (ref.mounted) {
        state = InviteGuestState(
          JoinPhase.joined,
          hostName: result.peerName,
          replaced: result.replacedFamily,
        );
      }
    } on FamilyConflictException {
      _set(JoinPhase.conflict, hostName: package.deviceName, code: code);
    } on Object {
      _set(JoinPhase.failed, issue: JoinIssue.unknown);
    }
  }

  /// «No coincide, cancelar»: no se entra. Quien invitó no confirmará.
  void reject() {
    _package = null;
    _offer = null;
    _pair = null;
    _stop();
    _set(JoinPhase.mismatch);
  }

  /// Vuelve al principio.
  void reset() {
    _package = null;
    _offer = null;
    _pair = null;
    _stop();
    _set(JoinPhase.idle);
  }
}

/// Quien entra con una invitación. Se libera al salir de la pantalla.
final inviteGuestProvider =
    NotifierProvider.autoDispose<InviteGuestController, InviteGuestState>(
      InviteGuestController.new,
    );
