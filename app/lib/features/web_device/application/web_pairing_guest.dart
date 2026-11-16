import 'dart:math';

import '../../../core/sync/device_keys.dart';
import '../../../core/sync/envelope.dart';
import '../../../core/sync/hlc.dart';
import '../../../core/sync/model.dart';
import '../../../core/sync/pairing_v2.dart';
import '../../sync/application/invite_poll_pacer.dart';
import '../../sync/application/pairing_v2_flow.dart';
import '../../sync/data/sync_transport.dart';
import '../../sync/data/sync_transport_v2.dart';
import 'vault_service.dart';
import 'web_common.dart' show webCommonInstall;
import 'web_sync_engine.dart';

/// In-memory identity until the user chooses a PIN after approval. Polling is
/// driven by the gate so cancellation never leaves an autonomous task alive.
class WebPairingGuest {
  WebPairingGuest._(
    this.transport,
    this.keys,
    this.qr,
    this.started,
    this.now,
    this.pacer,
    this.elapsed,
  );

  /// Cuánto vale el QR de la web desde que se enseña.
  static const Duration lifetime = Duration(minutes: 10);

  /// Antes de la oferta se pregunta cada 1-2 s durante este tiempo; después,
  /// cada 3-4 s: esos 404 cuentan en el límite por IP del Worker.
  static const Duration fastOfferPolling = Duration(minutes: 2);

  /// [pacer] decide la espera entre sondeos (1-2 s con el presupuesto por
  /// invitación del Worker); [random] solo se usa si no se da [pacer].
  /// [now] es la hora de pared (caducidad); [elapsed], el reloj monótono de
  /// las esperas (el mismo que el de [pacer] si se dan los dos).
  static Future<WebPairingGuest> create({
    required SyncV2Transport transport,
    DateTime Function()? now,
    Random? random,
    InvitePollPacer? pacer,
    Duration Function()? elapsed,
  }) async {
    final keys = await DeviceKeys.generate();
    final inviteId = encodeBase64Url(secureRandomBytes(16));
    final clock = now ?? DateTime.now;
    final monotonic = elapsed ?? monotonicElapsed();
    return WebPairingGuest._(
      transport,
      keys,
      WebPairingQr(
        inviteId,
        webPairingFingerprint(
          inviteId,
          keys.publicKeys.signing,
          keys.publicKeys.agreement,
        ),
      ),
      clock(),
      clock,
      pacer ??
          InvitePollPacer(
            random: random ?? Random.secure(),
            elapsed: monotonic,
          ),
      monotonic,
    );
  }

  final SyncV2Transport transport;
  final DeviceKeys keys;
  final WebPairingQr qr;
  final DateTime started;
  final DateTime Function() now;

  /// Reloj monótono desde que se creó este QR.
  final Duration Function() elapsed;

  /// La cadencia de los sondeos y la cuenta de peticiones a la invitación.
  final InvitePollPacer pacer;
  PairingV2Guest? _guest;

  /// La oferta ya leída y comprobada cuya respuesta no ha llegado al Worker
  /// (un 429 o un corte): se reintenta la misma respuesta, sin volver a pedir
  /// la oferta ni crear otra.
  PairingV2Guest? _answering;
  String? _answeringPerson;
  String? personId, code;
  bool confirmed = false, _cancelled = false;
  PairingV2Joined? joined;
  DateTime? _offerExpiresAt;

  /// La espera hasta el siguiente sondeo normal: 1-2 s, dentro del
  /// presupuesto de la invitación; sin oferta tras [fastOfferPolling], 3-4 s.
  Duration get pollDelay =>
      (waitingForOffer && elapsed() >= fastOfferPolling) || comparing
      ? pacer.next(
          base: const Duration(seconds: 3),
          spread: const Duration(seconds: 1),
        )
      : pacer.next();

  /// Con el código a la vista y sin confirmar: solo se mira cada 3-4 s si el
  /// móvil sigue ahí (para decir «cancelado» si lo canceló).
  bool get comparing => code != null && !confirmed && joined == null;

  /// Todavía no ha leído la oferta (el móvil no ha escaneado).
  bool get waitingForOffer => _guest == null && _answering == null;

  /// Lo que queda de la vida del QR (cero si ya pasó).
  Duration get remainingLifetime {
    final left = lifetime - now().difference(started);
    return left.isNegative ? Duration.zero : left;
  }

  /// Si el Worker ya ha registrado la credencial de esta web (aprobación
  /// recibida): un fallo después deja una «Web» que hay que quitar en el
  /// móvil.
  bool get approved => _guest?.approved ?? false;

  /// Si ya ha pasado la vida del QR (o la que dio la oferta): una invitación
  /// que desaparece antes es que el móvil la canceló.
  bool get expired {
    final at = now();
    final offerEnd = _offerExpiresAt;
    return at.difference(started) >= lifetime ||
        (offerEnd != null && !offerEnd.isAfter(at));
  }

  /// Si el siguiente sondeo hablaría con el Worker.
  bool get needsNetwork => !_cancelled && joined == null;

  void _check() {
    if (_cancelled) throw const PairingException('emparejamiento cancelado');
    if (joined == null && now().difference(started) >= lifetime) {
      throw const InviteGoneException();
    }
  }

  void cancel() {
    _cancelled = true;
  }

  /// Null before an offer; a pre-offer 404 is explicitly not expiration.
  Future<void> poll() async {
    _check();
    final answering = _answering;
    if (_guest == null && answering != null) {
      // La misma respuesta otra vez (tras un 429 o un corte).
      await answering.answer(personId: _answeringPerson);
      _check();
      personId = _answeringPerson;
      _guest = answering;
      _answering = null;
      return;
    }
    if (_guest == null) {
      final V2InviteOffer got;
      try {
        got = await transport.getOffer(qr.inviteId, allowNotYet: true);
      } on V2OfferNotYetException {
        // Antes de existir la invitación el Worker no la cuenta.
        return;
      }
      // Desde aquí cada petición cuenta en el límite de la invitación.
      pacer.sent();
      _check();
      _offerExpiresAt = got.expiresAt;
      if (!got.expiresAt.isAfter(now())) throw const InviteGoneException();
      final person = got.guestPerson;
      if (person == null || person.isEmpty) {
        throw const PairingException('falta la persona de la web');
      }
      final offer = await PairingOffer.fromJson(got.offer);
      final guest = PairingV2Guest.forWeb(
        transport: transport,
        inviteId: qr.inviteId,
        offer: offer,
        keys: keys,
        deviceId: HlcClock.newNode(),
        onRequest: pacer.sent,
      );
      _check();
      _answering = guest;
      _answeringPerson = person;
      await guest.answer(personId: person);
      _check();
      personId = person;
      _guest = guest;
      _answering = null;
      return;
    }
    final guest = _guest!;
    if (code == null) {
      final value = await guest.code();
      _check();
      code = value;
    } else if (!confirmed && joined == null) {
      // Comparando: ¿sigue viva la invitación?
      await guest.ensureAlive();
      _check();
    } else if (confirmed && joined == null) {
      final result = await guest.finish();
      _check();
      if (result != null) {
        final record = result.common.record(Collections.recipients, personId!);
        if (record == null || record.isDeleted || record['name'] is! String) {
          throw const PairingException('la persona ya no existe');
        }
        joined = result;
      }
    }
  }

  void confirmCode() {
    _check();
    if (code == null) throw const PairingException('todavía no hay código');
    _guest!.confirmCode();
    confirmed = true;
  }

  String get personName =>
      joined!.common.record(Collections.recipients, personId!)!['name']
          as String;

  Future<void> enroll(VaultService vault, String pin) async {
    _check();
    final result = joined;
    if (result == null || !confirmed) {
      throw const PairingException('aprobación pendiente');
    }
    await vault.enroll(
      pin: pin,
      syncId: result.identity.syncId,
      deviceId: result.identity.deviceId,
      // La caja nace del checkpoint verificado (B7, M1). Tras el corte,
      // `webCommonInstall` (B5) le pone la marca, el llavero del checkpoint
      // y la base sellada solo en local en `snapshot.common`; antes del
      // corte devuelve el mapa tal cual.
      data: await webCommonInstall(
        {
          'listId': result.identity.listId,
          'personId': personId,
          'credential': encodeBase64Url(keys.serviceCredential),
          'deviceKeys': keys.toJson(),
          'familyKey': result.familyKey.toBase64Url(),
          'roots': [rootJson(result.hostAnchor)],
          'snapshot': snapshotJson(result.snapshot),
          'registryLocal': result.registry.toLocalStoreJson(),
        },
        commonFormat: result.commonFormat,
        commonKeys: result.commonKeys,
        common: result.common,
        keys: keys,
        deviceId: result.identity.deviceId,
        registry: result.registry,
        root: result.hostAnchor,
        syncId: result.identity.syncId,
      ),
    );
    // B7: la caja ya tiene la base; la copia del Worker sobra.
    await _guest?.releaseCheckpoint();
    _check();
  }
}
