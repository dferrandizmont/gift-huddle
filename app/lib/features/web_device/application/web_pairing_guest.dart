import 'dart:math';

import '../../../core/sync/device_keys.dart';
import '../../../core/sync/envelope.dart';
import '../../../core/sync/hlc.dart';
import '../../../core/sync/model.dart';
import '../../../core/sync/pairing_v2.dart';
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
    this.random,
  );
  static Future<WebPairingGuest> create({
    required SyncV2Transport transport,
    DateTime Function()? now,
    Random? random,
  }) async {
    final keys = await DeviceKeys.generate();
    final inviteId = encodeBase64Url(secureRandomBytes(16));
    final clock = now ?? DateTime.now;
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
      random ?? Random.secure(),
    );
  }

  final SyncV2Transport transport;
  final DeviceKeys keys;
  final WebPairingQr qr;
  final DateTime started;
  final DateTime Function() now;
  final Random random;
  PairingV2Guest? _guest;
  String? personId, code;
  bool confirmed = false, _cancelled = false;
  PairingV2Joined? joined;
  Duration get pollDelay => Duration(milliseconds: 5000 + random.nextInt(3001));
  void _check() {
    if (_cancelled) throw const PairingException('emparejamiento cancelado');
    if (joined == null &&
        now().difference(started) >= const Duration(minutes: 10)) {
      throw const InviteGoneException();
    }
  }

  void cancel() {
    _cancelled = true;
  }

  /// Null before an offer; a pre-offer 404 is explicitly not expiration.
  Future<void> poll() async {
    _check();
    if (_guest == null) {
      final V2InviteOffer got;
      try {
        got = await transport.getOffer(qr.inviteId, allowNotYet: true);
      } on V2OfferNotYetException {
        return;
      }
      _check();
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
      );
      _check();
      await guest.answer(personId: person);
      _check();
      personId = person;
      _guest = guest;
      return;
    }
    final guest = _guest!;
    if (code == null) {
      final value = await guest.code();
      _check();
      code = value;
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
