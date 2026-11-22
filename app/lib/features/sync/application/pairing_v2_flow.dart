// Emparejamiento v2 sobre las invitaciones del Worker (ADR 0004, fase 2b):
// compromiso, respuesta con nonce del invitado, revelación y código de seis
// cifras que se compara a los dos lados (`pairing_v2.dart`). Sirve igual para
// el QR «Está aquí» (el QR lleva el enlace de la invitación) y para el enlace
// «Está lejos»: en los dos casos solo viaja el id de la invitación, nunca una
// clave.
//
// Dart puro: la aplicación guarda lo que devuelve.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../../core/sync/device_keys.dart';
import '../../../core/sync/device_registry.dart';
import '../../../core/sync/envelope.dart';
import '../../../core/sync/envelope.dart' as env show open;
import '../../../core/sync/access_policy.dart' show livePeopleOf;
import '../../../core/sync/family_candidate.dart';
import '../../../core/sync/family_doc.dart';
import '../../../core/sync/family_envelope.dart';
import '../../../core/sync/family_key_bundle.dart';
import '../../../core/sync/key_bundle.dart';
import '../../../core/sync/pairing_v2.dart';
import '../data/sync_transport.dart';
import '../data/sync_transport_v2.dart';
import 'common_v2.dart' show CommonKeyState, commonWriterResolver, kCommonRef;
import 'common_v2_cutover.dart' show kCommonFormatLatest;
import 'sync_v2_engine.dart';
import 'v2_family_lock.dart';

/// Versión del paquete que entrega el anfitrión al aprobar: la aprobación
/// con checkpoint (ADR 0005, B7). La 3 (solo la clave y las revisiones, sin
/// compromiso del común) ya no se acepta.
const int kPairingPackageVersion = 4;

/// Si la web puede emparejarse con una familia que ya cortó al formato 2 del
/// común. Encendido con B5: `WebPairingGuest.enroll` guarda en la caja
/// [PairingV2Joined.commonKeys] y la marca de [PairingV2Joined.commonFormat]
/// (`webCommonInstall`). Apagado, ni el anfitrión aprueba ni el invitado web
/// instala con el formato 2, antes de crear ninguna credencial.
const bool kWebPairingCommonV2 = true;

/// Como mucho, cuántos paquetes v4 de la clave común lleva la aprobación.
const int kPairingMaxFamilyPackages = 4;

/// Las claves exactas de la aprobación v4.
const Set<String> _approvalKeys = {
  'v',
  'listId',
  'syncId',
  'inviteId',
  'transcriptHash',
  'hostRecord',
  'guestRecord',
  'minVersion',
  'commonCheckpointHash',
  'registryCheckpointHash',
  'minCommonFormat',
  'familyKeyPackages',
  'slotFloors',
  'sig',
};

const kWebPairingOrigin = String.fromEnvironment(
  'WEB_APP_ORIGIN',
  defaultValue: 'https://web.gifthuddle.app',
);

const _webPairingOrigins = {'https://web.gifthuddle.app'};

/// Strict mobile-side parser. A mobile invitation or arbitrary origin is refused.
class WebPairingQr {
  const WebPairingQr(this.inviteId, this.fingerprint);
  final String inviteId, fingerprint;
  static WebPairingQr parse(String value, {String origin = kWebPairingOrigin}) {
    final uri = Uri.tryParse(value);
    final base = Uri.parse(origin);
    final acceptedOrigins = _webPairingOrigins.contains(base.origin)
        ? _webPairingOrigins
        : {base.origin};
    // Check the raw authority too: Uri normalizes away an explicit :443.
    final authority = RegExp(r'^https://([^/?#]+)').firstMatch(value)?.group(1);
    if (uri == null ||
        uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        !acceptedOrigins.contains(uri.origin) ||
        authority != uri.host ||
        uri.path != '/w' ||
        uri.hasQuery ||
        uri.userInfo.isNotEmpty) {
      throw const PairingException('QR web no válido');
    }
    final parts = uri.fragment.split('.');
    if (parts.length != 2 ||
        parts.any((s) => !RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(s))) {
      throw const PairingException('QR web no válido');
    }
    try {
      for (final part in parts) {
        if (decodeBase64Url(part).length != 16 ||
            encodeBase64Url(decodeBase64Url(part)) != part) {
          throw const PairingException('QR web no válido');
        }
      }
    } on FormatException {
      throw const PairingException('QR web no válido');
    }
    return WebPairingQr(parts[0], parts[1]);
  }

  String url({String origin = kWebPairingOrigin}) =>
      '${Uri.parse(origin).origin}/w#$inviteId.$fingerprint';
}

/// Los móviles no entienden la misma versión de aprobación: hay que
/// actualizarlos antes de volver a empezar con otra invitación.
class PairingV2VersionMismatchException extends PairingException {
  /// Crea el error sin datos de la familia.
  const PairingV2VersionMismatchException()
    : super('versión de aprobación incompatible');
}

/// Lo que firma el anfitrión: "gift-huddle-pairing-approval-v4" ‖ 0 ‖ el
/// JSON canónico de toda la aprobación salvo la firma.
List<int> _approvalBytes(Map<String, Object?> package) => [
  ...utf8.encode('gift-huddle-pairing-approval-v4'),
  0,
  ...utf8.encode(
    canonicalJsonText({
      for (final e in package.entries)
        if (e.key != 'sig') e.key: e.value,
    }),
  ),
];

final _hash43 = RegExp(r'^[A-Za-z0-9_-]{43}$');

/// El común que se iba a aprobar no tiene en secreto los regalos de la
/// persona del móvil nuevo (1.0.6): no se aprueba.
class PairingCheckpointUnprotectedException extends PairingException {
  /// Crea el error.
  const PairingCheckpointUnprotectedException()
    : super('el común aprobado no protege a la persona del móvil nuevo');
}

final Set<String> _confirming = <String>{};

/// Si este proceso está aprobando ahora mismo al invitado [guestDeviceId]
/// ([PairingV2Host.confirm]): su marca de pendiente no es de un cierre.
bool pairingConfirmInProgress(String guestDeviceId) =>
    _confirming.contains(guestDeviceId);

/// Revoca en el registro de este móvil al invitado [guestDeviceId] que no
/// llegó a aprobarse (1.0.6: el emparejamiento falla en cerrado). No hace
/// nada si ya no está o ya está revocado.
Future<void> revokeUnapprovedGuest(
  SyncV2Local local,
  String guestDeviceId,
) async {
  final registry = await local.registry();
  final view = await registry.viewFor(
    me: local.identity.deviceId,
    mySigningKey: local.keys.publicKeys.signing,
    livePeople: livePeopleOf(await local.common()),
  );
  if (view.device(guestDeviceId) == null ||
      view.revoked.contains(guestDeviceId)) {
    return;
  }
  final me = registry.recordByDigest(view.self.recordDigest)!;
  await local.saveRegistry(
    await registry.withRevocation(
      await Revocation.create(
        keys: local.keys,
        by: me,
        deviceId: guestDeviceId,
      ),
      anchor: view.anchor,
    ),
  );
}

/// Lo que ve el anfitrión cuando el invitado ya ha respondido.
class PairingV2Answered {
  /// Crea el resultado.
  const PairingV2Answered({
    required this.code,
    required this.guestDeviceId,
    required this.guestPersonId,
  });

  /// El código de seis cifras.
  final String code;

  /// Móvil del invitado.
  final String guestDeviceId;

  /// Persona que eligió el invitado (null si lo marcó sin persona).
  final String? guestPersonId;
}

/// El emparejamiento v2 en el móvil que ya está en la familia.
class PairingV2Host {
  PairingV2Host._(
    this._transport,
    this._local,
    this._lock,
    this._session,
    this.inviteId,
  );

  /// Crea la lista si hace falta, publica la oferta y devuelve el
  /// emparejamiento en marcha.
  ///
  /// [v1Key] es la clave de la familia v1 que este móvil conserva tras
  /// migrar (`LegacyV1`): con ella la oferta lleva la prueba
  /// ([v1ListProof]) que deja entrar como «misma lista» a un móvil de v1 de
  /// esa lista (hallazgo 6). Sin ella, ninguno lo es.
  ///
  /// Con [hostPicksPerson] (móviles, 1.0.6) este móvil ya ha elegido para
  /// quién es el móvil nuevo ([guestPerson], o null para «alguien que no
  /// está en la lista»): la oferta lleva la marca y el servidor guarda la
  /// persona para dársela al invitado ([PairingHost.start]).
  static Future<PairingV2Host> start({
    required SyncV2Transport transport,
    required SyncV2Local local,
    required V2FamilyLock lock,
    void Function(String phase)? onPhase,
    WebPairingQr? web,
    String? guestPerson,
    FamilyKey? v1Key,
    bool inviteCopy = true,
    bool hostPicksPerson = false,
  }) => lock.run(() async {
    // B1: la web tras el corte se rechaza antes de crear nada.
    if (web != null) await _refuseWebAfterCut(local);
    final engine = SyncV2Engine(transport: transport, local: local);
    onPhase?.call('create');
    await engine.ensureCreated(inviteCopy: inviteCopy);
    onPhase?.call('sync');
    await engine.sync();
    onPhase?.call('registry');
    final registry = await local.registry();
    onPhase?.call('view');
    final view = await _viewOf(local, registry);
    onPhase?.call('session');
    final session = PairingHost.start(
      registry,
      view,
      expectWeb: web != null,
      inviteId: web?.inviteId,
      guestPerson: guestPerson,
      expectedFingerprint: web?.fingerprint,
      hostPicksPerson: hostPicksPerson && web == null,
    );
    onPhase?.call('invite');
    final offer = session.offer.toJson();
    if (v1Key != null && web == null) {
      offer[kV1ProofField] = encodeBase64Url(v1ListProof(v1Key, session.offer));
    }
    final ticket = await transport.createInvite(
      _authOf(local),
      offer,
      inviteId: web?.inviteId,
      guestPerson: guestPerson,
    );
    return PairingV2Host._(transport, local, lock, session, ticket.inviteId);
  });

  final SyncV2Transport _transport;
  final SyncV2Local _local;
  final V2FamilyLock _lock;
  final PairingHost _session;

  /// Id de la invitación (lo lleva el QR o el enlace).
  final String inviteId;

  /// Si este móvil eligió la persona del móvil nuevo ([start]).
  bool get hostPicksPerson => _session.hostPicksPerson;

  /// La persona que eligió este móvil, o null.
  String? get guestPerson => _session.guestPerson;

  /// Liveness while the host is comparing an already answered invitation.
  Future<void> ensureAlive() async {
    await _transport.getInvite(_authOf(_local), inviteId);
  }

  PairingV2Answered? _answered;

  /// Mira si el invitado ha respondido. Si sí, comprueba la respuesta, revela
  /// el nonce y devuelve el código; si no, null.
  ///
  /// Una respuesta que no vale gasta la única respuesta del servidor: se
  /// borra la invitación y se lanza [PairingException] (hay que empezar otra).
  Future<PairingV2Answered?> poll() async {
    final done = _answered;
    if (done != null) return done;
    final state = await _transport.getInvite(_authOf(_local), inviteId);
    if (state.answer == null) return null;
    final PairingReveal reveal;
    final PairingAnswer answer;
    try {
      answer = PairingAnswer.fromJson(state.answer);
      reveal = await _session.receive(answer);
      // Una persona que no existe aquí (desconocida o borrada) no se puede
      // avalar: ni se revela el código (hallazgo 3).
      final claimed = answer.guest.personId;
      if (claimed != null &&
          !livePeopleOf(await _local.common()).contains(claimed)) {
        throw const PairingException('esa persona no existe en la familia');
      }
    } on PairingException {
      await cancel();
      rethrow;
    }
    await _transport.revealInvite(_authOf(_local), inviteId, reveal.toJson());
    return _answered = PairingV2Answered(
      code: _session.code,
      guestDeviceId: answer.guest.deviceId,
      guestPersonId: answer.guest.personId,
    );
  }

  /// Una persona ha confirmado que los dos códigos coinciden y de quién es el
  /// móvil: publica su ficha y los dos avales, reparte las claves de
  /// sorpresa que le tocan y aprueba con la aprobación firmada del estado
  /// exacto que queda en el servidor (B7, [_package]): el checkpoint del
  /// común y del registro, la clave para abrirlo cifrada para su clave
  /// persistente y las revisiones de los slots que este móvil conoce
  /// (pendiente 13).
  ///
  /// Lanza [PairingException] si no hay respuesta, si el invitado no tiene
  /// persona y no se pasa [guestWithoutPerson], o si tiene persona y
  /// [confirmedPersonId] no es ella (alguien tiene que haber visto aparte de
  /// quién dice ser el móvil, hallazgo 3) o ya no existe.
  ///
  /// [beforePublish] se llama dentro del cerrojo, con la ficha y los avales
  /// del invitado ya guardados y antes de la sincronización que fija el
  /// checkpoint: la aplicación pone ahí en secreto los regalos de la persona
  /// del móvil nuevo (1.0.6). Si lanza, no se aprueba nada.
  ///
  /// [verifyCheckpoint] recibe en cada intento el común exacto que se va a
  /// aprobar (abierto con las claves de este móvil) y, si devuelve false, no
  /// se aprueba. [onPending] se llama antes de guardar la ficha del invitado
  /// y [onSettled] cuando la aprobación ha entrado o el invitado ya está
  /// revocado: entre medias, un cierre deja la marca para que la aplicación
  /// lo revoque ([revokeUnapprovedGuest]).
  ///
  /// Si algo falla antes de que el servidor acepte la aprobación, el
  /// invitado queda revocado en el registro de este móvil (falla en
  /// cerrado: su ficha avalada no se queda como un móvil más).
  Future<void> confirm({
    bool guestWithoutPerson = false,
    String? confirmedPersonId,
    Future<void> Function()? beforePublish,
    Future<bool> Function(FamilyDoc common)? verifyCheckpoint,
    Future<void> Function(String guestDeviceId)? onPending,
    Future<void> Function()? onSettled,
  }) => _lock.run(() async {
    if (_answered == null) {
      throw const PairingException('todavía no hay respuesta');
    }
    // B1 y M2: antes de publicar la ficha y los avales del invitado.
    if (_session.expectWeb) await _refuseWebAfterCut(_local);
    final state = await _transport.getInvite(_authOf(_local), inviteId);
    if (!state.canApprove) {
      throw const PairingException(
        'hoy ya no caben más dispositivos nuevos en la familia',
      );
    }
    final registry = await _local.registry();
    final view = await _viewOf(_local, registry);
    final change = await acceptPairing(
      registry: registry,
      view: view,
      myKeys: _local.keys,
      session: _session,
      guestWithoutPerson: guestWithoutPerson,
      confirmedPersonId: confirmedPersonId,
    );
    final guest = _session.answer!.guest.deviceId;
    _confirming.add(guest);
    if (onPending != null) await onPending(guest);
    await _local.saveRegistry(change.registry);
    try {
      if (beforePublish != null) await beforePublish();
      final engine = SyncV2Engine(transport: _transport, local: _local);
      var rewritten = false;
      for (var attempt = 0; ; attempt++) {
        final out = await engine.sync();
        final published = out.published;
        if (published == null) {
          throw const PairingException('no se sabe qué hay en el servidor');
        }
        final (package, claim, common) = await _package(
          out,
          guest,
          published,
        );
        if (verifyCheckpoint != null && !await verifyCheckpoint(common)) {
          throw const PairingCheckpointUnprotectedException();
        }
        final V2WriteResult approved;
        try {
          approved = await _transport.approveInvite(
            _authOf(_local),
            inviteId,
            version: out.version,
            package: package,
            role: _session.expectWeb ? 'web' : 'device',
            checkpoint: claim,
          );
        } on V2InviteConflictException catch (e) {
          // B3: lo guardado no se serializa como aquí (base64url no
          // canónico, un registro raro). Una vez: se reescribe con lo mismo
          // y se vuelve a aprobar sobre la versión nueva.
          if (e.code != 'checkpoint_mismatch' || rewritten) rethrow;
          rewritten = true;
          // El registro verificado y fusionado de este móvil, en su JSON
          // limpio; nunca lo que diga el servidor tal cual.
          await _transport.putList(
            _authOf(_local),
            version: out.version,
            body: V2SnapshotUpload(
              common: published.common,
              registry: (await _local.registry()).toJson(),
              keyPackages: published.keyPackages,
            ),
          );
          continue;
        }
        switch (approved) {
          case V2WriteOk():
            final state = await _local.readState();
            await _local.saveState(state.copyWith(version: approved.version));
            if (onSettled != null) await onSettled();
            return;
          case V2WriteStale():
            if (attempt >= 3) {
              throw const SyncTransportException(
                SyncFailure.server,
                'la lista cambia demasiado deprisa',
              );
            }
          case V2WriteNotFound():
            throw const V2ListGoneException();
        }
      }
    } on Object {
      // Falla en cerrado: el invitado no se queda avalado aquí. Si la
      // aprobación llegó a entrar sin que llegara la respuesta, tendrá que
      // volver a emparejar.
      await revokeUnapprovedGuest(_local, guest);
      if (onSettled != null) await onSettled();
      rethrow;
    } finally {
      _confirming.remove(guest);
    }
  });

  /// La aprobación firmada (ADR 0005, §6 y B7) del estado exacto [published]
  /// que hay en el servidor en `out.version`, bajo la cola de la familia, y
  /// los hashes del checkpoint que el Worker copia con el mismo `If-Match`.
  ///
  /// Antes de firmar, este móvil autentica lo que aprueba: abre el común con
  /// sus claves (nunca firma «lo que diga el siguiente GET») y busca el
  /// reparto de su candidata al invitado. Tras el corte (un común en formato
  /// 2) entrega el paquete v4 de esa candidata y el formato mínimo 2, y ya
  /// no sella la `familyKey` en v3. Sin corte, la `familyKey` en v3 como
  /// hasta ahora. Lanza [PairingException] (antes de aprobar: no queda
  /// ninguna credencial) si no puede.
  Future<(Map<String, Object?>, V2CheckpointClaim, FamilyDoc)> _package(
    V2SyncOutcome out,
    String guest,
    V2Published published,
  ) async {
    late final FamilyDoc approvedCommon;
    final view = out.view;
    final registry = await _local.registry();
    final floor = await _local.commonFormatFloor();
    final format2 = isFamilyEnvelope(published.common);
    if (floor >= kCommonFormatLatest && !format2) {
      throw const PairingException(
        'el servidor ofrece un común del formato 1 tras el corte',
      );
    }
    if (format2 && _session.expectWeb && !kWebPairingCommonV2) {
      throw const PairingException(
        'la web todavía no sigue el formato 2 del común',
      );
    }
    final List<Map<String, Object?>> familyKeyPackages;
    if (format2) {
      final keys = await _local.readCommonKeys();
      final String kid;
      try {
        final opened = await openFamilyEnvelope(
          published.common,
          expectedListId: view.listId,
          expectedSyncId: _local.identity.syncId,
          resolveWriter: commonWriterResolver(view, registry),
          keyring: (keys ?? CommonKeyState()).keyring,
        );
        kid = opened.header.kid;
        approvedCommon = opened.doc;
      } on EnvelopeException {
        throw const PairingException(
          'este móvil no puede abrir el común que aprobaría',
        );
      }
      final me = _local.identity.deviceId;
      familyKeyPackages = [
        for (final p in published.keyPackages)
          if (FamilyKeyBundle.isV4(p) && p['to'] == guest && p['kid'] == kid) p,
      ]..sort((a, b) => (a['from'] == me ? 0 : 1) - (b['from'] == me ? 0 : 1));
      if (familyKeyPackages.isEmpty) {
        throw const PairingException(
          'la clave común todavía no está repartida al móvil nuevo',
        );
      }
      if (familyKeyPackages.length > kPairingMaxFamilyPackages) {
        familyKeyPackages.removeRange(
          kPairingMaxFamilyPackages,
          familyKeyPackages.length,
        );
      }
    } else {
      try {
        final opened = await env.open(
          published.common,
          key: _local.familyKey,
          expectedListId: view.listId,
        );
        approvedCommon = FamilyDoc.fromJson(opened.doc);
      } on EnvelopeException {
        throw const PairingException(
          'este móvil no puede abrir el común que aprobaría',
        );
      }
      final bundle = await KeyBundle.sealFamilyKey(
        sender: _local.keys,
        view: view,
        toDevice: guest,
        epoch: view.epoch,
        familyKey: _local.familyKey,
        commonFormatV2: floor >= kCommonFormatLatest,
      );
      familyKeyPackages = [bundle.toJson()];
    }
    final commonHash = pairingCheckpointHash(
      'common',
      encodeBase64Url(published.common),
    );
    final registryHash = pairingCheckpointHash(
      'registry',
      canonicalJsonText(published.registry),
    );
    final slots = await _local.slots();
    final answer = _session.answer!;
    final package = <String, Object?>{
      'v': kPairingPackageVersion,
      'listId': view.listId,
      'syncId': _local.identity.syncId,
      'inviteId': inviteId,
      'transcriptHash': _session.transcriptHash(inviteId),
      'hostRecord': _session.offer.host.digest,
      'guestRecord': answer.guest.digest,
      // La versión que deja la aprobación (la credencial sube una).
      'minVersion': out.version + 1,
      'commonCheckpointHash': commonHash,
      'registryCheckpointHash': registryHash,
      'minCommonFormat': format2 ? kCommonFormatLatest : 1,
      'familyKeyPackages': familyKeyPackages,
      'slotFloors': {
        for (final s in slots.all)
          '${s.header.personId}/${s.header.writer}': s.header.revision,
      },
      // 1.0.6: la persona que eligió este móvil, firmada (el invitado la
      // exige: la marca de la oferta no va firmada).
      if (_session.hostPicksPerson && _session.guestPerson != null)
        kHostPicksPersonField: _session.guestPerson,
    };
    package['sig'] = encodeBase64Url(
      await _local.keys.sign(_approvalBytes(package)),
    );
    return (
      package,
      V2CheckpointClaim(common: commonHash, registry: registryHash),
      approvedCommon,
    );
  }

  /// Cancela la invitación («No coinciden», cerrar o caducar).
  Future<void> cancel() async {
    try {
      await _transport.deleteInvite(_authOf(_local), inviteId);
    } on Object {
      // Caduca sola en 24 h.
    }
  }
}

/// Lo que recibe el invitado al quedar dentro.
class PairingV2Joined {
  /// Crea el resultado.
  const PairingV2Joined({
    required this.identity,
    required this.familyKey,
    required this.registry,
    required this.minSlotRevisions,
    required this.minVersion,
    required this.common,
    required this.hostDeviceId,
    required this.snapshot,
    required this.hostAnchor,
    this.commonFormat = 1,
    this.commonKeys,
  });

  /// El documento común del checkpoint que aprobó el anfitrión (la base,
  /// ADR 0005, §6), para instalarlo y fusionar con él la copia local de v1
  /// si la había (`mergeLocalV1IntoV2`). Lo que haya después en el servidor
  /// se fusiona en la primera vuelta.
  final FamilyDoc common;

  /// El formato mínimo del común, firmado en la aprobación: con 2, este
  /// móvil nace con la marca irreversible y nunca abre un formato 1.
  final int commonFormat;

  /// Con el formato 2, el llavero común con la candidata del checkpoint
  /// (abierta del paquete v4 y referenciada como la del común). Se guarda
  /// antes de instalar.
  final CommonKeyState? commonKeys;

  /// Móvil del anfitrión.
  final String hostDeviceId;
  final RegistryAnchor hostAnchor;
  final V2Snapshot snapshot;

  /// Identidad v2 de este móvil.
  final SyncIdentityV2 identity;

  /// La clave de la familia (abierta del paquete v3 del anfitrión). Con el
  /// formato 2 no viaja: es una clave local aleatoria que no abre nada.
  final FamilyKey familyKey;

  /// El registro, ya con la ficha y los avales de los dos.
  final DeviceRegistry registry;

  /// Revisiones de slot que el anfitrión ya conocía (pendiente 13).
  final Map<String, int> minSlotRevisions;

  /// La versión que creó la aprobación.
  final int minVersion;
}

/// El emparejamiento v2 en el móvil que entra.
class PairingV2Guest {
  PairingV2Guest._(
    this._transport,
    this.inviteId,
    this.offer,
    this._keys,
    this._deviceId,
    this.kind, {
    this.onRequest,
    this.assignedPerson,
  });

  /// Lee la oferta de la invitación y comprueba la ficha del anfitrión.
  ///
  /// [deviceIdFor] recibe la lista de la oferta y si el anfitrión ha probado
  /// tener [v1Key], la clave v1 de este móvil (hallazgo 6): solo entonces es
  /// «la misma lista». El `listId` solo no prueba nada: es público.
  static Future<PairingV2Guest> open({
    required SyncV2Transport transport,
    required String inviteId,
    required DeviceKeys keys,
    required String Function(String listId, bool v1Proven) deviceIdFor,
    FamilyKey? v1Key,
    void Function()? onRequest,
  }) async {
    onRequest?.call();
    final got = await transport.getOffer(inviteId);
    final offer = await PairingOffer.fromJson(got.offer);
    final proven =
        v1Key != null &&
        verifyV1ListProof(v1Key, offer, (got.offer! as Map)[kV1ProofField]);
    return PairingV2Guest._(
      transport,
      inviteId,
      offer,
      keys,
      deviceIdFor(offer.listId, proven),
      DeviceKind.mobile,
      onRequest: onRequest,
      assignedPerson: offer.hostPicksPerson ? got.guestPerson : null,
    );
  }

  /// Si el anfitrión ha elegido de quién es este móvil (marca
  /// [kHostPicksPersonField] de la oferta, 1.0.6). Sin ella, el anfitrión es
  /// de una versión que deja entrar sin persona y un móvil 1.0.6 no entra.
  bool get hostPicksPerson => offer.hostPicksPerson;

  /// La persona que eligió el anfitrión (id estable), o null («alguien que
  /// no está en la lista», o sin marca). La da el servidor: si la cambiara,
  /// el anfitrión rechaza la respuesta.
  final String? assignedPerson;

  final SyncV2Transport _transport;

  /// La invitación.
  final String inviteId;

  /// La oferta del anfitrión (verificada).
  final PairingOffer offer;
  final DeviceKeys _keys;
  final String _deviceId;
  final DeviceKind kind;

  /// Se llama antes de cada petición a la invitación: quien sondea lleva la
  /// cuenta para no pasar del límite del Worker (`InvitePollPacer`).
  final void Function()? onRequest;

  /// Web uses the already fetched offer: no second offer request or identity.
  static PairingV2Guest forWeb({
    required SyncV2Transport transport,
    required String inviteId,
    required PairingOffer offer,
    required DeviceKeys keys,
    required String deviceId,
    void Function()? onRequest,
  }) => PairingV2Guest._(
    transport,
    inviteId,
    offer,
    keys,
    deviceId,
    DeviceKind.web,
    onRequest: onRequest,
  );
  PairingJoin? _join;

  /// La respuesta preparada y todavía sin aceptar por el Worker.
  PairingJoin? _prepared;
  String? _preparedPerson;
  bool _preparedWithoutPerson = false;
  bool _approved = false;
  bool _answerSent = false, _withdrawRequested = false;
  Future<void>? _withdrawal;
  bool _withdrawGone = false;
  V2WithdrawInvite? _withdrawInvite;

  /// Best effort, once per attempt. A late answer retries a pre-answer 404.
  Future<void> withdraw({V2WithdrawInvite? send}) {
    _withdrawInvite ??= send;
    _withdrawRequested = true;
    if (!_answerSent) return Future<void>.value();
    return _withdrawal ??= _withdraw();
  }

  Future<void> _withdrawAfterAnswer() async {
    await withdraw();
    // A 404 may have been decided before the answer was accepted, even if
    // its response arrived afterwards. Retry once after both requests settle.
    if (_withdrawGone) {
      _withdrawGone = false;
      _withdrawal = null;
      await withdraw();
    }
  }

  Future<void> _withdraw() async {
    try {
      onRequest?.call();
      final send = _withdrawInvite;
      final V2InviteWithdrawal result;
      if (send == null) {
        result = await _transport
            .withdrawInvite(inviteId, credential: _keys.serviceCredential)
            .timeout(const Duration(seconds: 2));
        if (result == V2InviteWithdrawal.alreadyApproved) {
          await _revokeApprovedWeb(_transport);
        }
      } else {
        // The polling connection may already be closed. Cleanup must use the
        // sender's separate client, with two seconds for each of three steps.
        result = await send(
          inviteId,
          credential: _keys.serviceCredential,
          onAlreadyApproved: _revokeApprovedWeb,
        ).timeout(const Duration(seconds: 6));
      }
      if (result == V2InviteWithdrawal.alreadyApproved) _approved = true;
      _withdrawGone = result == V2InviteWithdrawal.gone;
    } on Object {
      // Network loss/page termination remains best effort.
    }
  }

  Future<void> _revokeApprovedWeb(SyncV2Transport transport) async {
    _approved = true;
    if (kind != DeviceKind.web) return;
    try {
      onRequest?.call();
      final outcome = await transport
          .pollInviteResult(inviteId, credential: _keys.serviceCredential)
          .timeout(const Duration(seconds: 2));
      if (outcome is! V2InviteApproved) return;
      await transport
          .revoke(
            V2Auth(
              syncId: outcome.syncId,
              deviceId: _deviceId,
              credential: _keys.serviceCredential,
            ),
            _deviceId,
          )
          .timeout(const Duration(seconds: 2));
    } on Object {
      // Approval is real, but cancellation must never wait for or surface
      // network/server failures while trying to remove the unused credential.
    }
  }

  /// Si el servidor ya ha dado la aprobación: la credencial de servicio de
  /// este móvil está registrada en la lista aunque no se llegue a instalar.
  bool get approved => _approved;

  /// Confirms installation: the Worker erases the invitation, its encrypted
  /// package and its checkpoint. Retry transient delivery failures.
  Future<void> releaseCheckpoint() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        onRequest?.call();
        await _transport.releaseInviteCheckpoint(
          inviteId,
          credential: _keys.serviceCredential,
        );
        return;
      } on Object {
        if (attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 100 * (attempt + 1)),
          );
        }
      }
    }
    // The app also queues the acknowledgement durably; old clients retain
    // the 24-hour expiry as a fallback if every delivery fails.
  }

  String? _code;
  bool _confirmed = false;

  /// La lista a la que se entra.
  String get listId => offer.listId;

  /// Responde con la ficha de este móvil y su persona (N2: sin persona solo
  /// con [withoutPerson]). Lanza [PairingException] o
  /// [InviteTakenException] si otro respondió antes.
  Future<void> answer({String? personId, bool withoutPerson = false}) async {
    if (_join != null) {
      throw const PairingException('ya se ha respondido');
    }
    // Un reintento (tras un 429 o un corte) manda la misma respuesta: el
    // mismo transcript, nunca otro.
    final prepared = _prepared;
    if (prepared != null &&
        (_preparedPerson != personId ||
            _preparedWithoutPerson != withoutPerson)) {
      throw const PairingException('la respuesta ya es de otra persona');
    }
    final join =
        prepared ??
        await joinPairing(
          offer: offer,
          keys: _keys,
          deviceId: _deviceId,
          personId: personId,
          withoutPerson: withoutPerson,
          kind: kind,
        );
    _prepared = join;
    _preparedPerson = personId;
    _preparedWithoutPerson = withoutPerson;
    final verifier = await _keys.serviceCredentialVerifier();
    if (_withdrawRequested) {
      throw const PairingException('emparejamiento cancelado');
    }
    onRequest?.call();
    _answerSent = true;
    try {
      await _transport.answerInvite(
        inviteId,
        answer: join.answer.toJson(),
        verifier: verifier,
      );
      _join = join;
    } finally {
      if (_withdrawRequested) unawaited(_withdrawAfterAnswer());
    }
  }

  /// El código, en cuanto el anfitrión revela su nonce (null antes). Lanza
  /// [PairingException] si la revelación no casa con la oferta (alguien en
  /// medio) e [InviteGoneException] si la invitación ya no existe.
  Future<String?> code() async {
    final join = _join;
    if (join == null) throw const PairingException('todavía no hay respuesta');
    if (_code != null) return _code;
    final outcome = await _poll();
    final reveal = switch (outcome) {
      V2InvitePending() => outcome.reveal,
      V2InviteApproved() => outcome.reveal,
      V2InviteGone() => throw const InviteGoneException(),
    };
    if (reveal == null) return null;
    return _code = join.codeFor(PairingReveal.fromJson(reveal));
  }

  /// Mira si la invitación sigue viva mientras se comparan los códigos (sin
  /// confirmar todavía): lanza [InviteGoneException] si el anfitrión la
  /// canceló o ya no está. No cambia nada más.
  Future<void> ensureAlive() async {
    if (_join == null) throw const PairingException('todavía no hay respuesta');
    final outcome = await _poll();
    if (outcome is V2InviteGone) throw const InviteGoneException();
  }

  /// La persona ha visto que los dos códigos coinciden.
  void confirmCode() {
    if (_code == null) throw const PairingException('todavía no hay código');
    _confirmed = true;
  }

  Future<V2InviteOutcome> _poll() {
    onRequest?.call();
    return _transport.pollInviteResult(
      inviteId,
      credential: _keys.serviceCredential,
    );
  }

  /// Recoge la aprobación (null si todavía no la hay o si el servidor no da
  /// el checkpoint): ADR 0005, §6 y B7.
  ///
  /// 1. Comprueba la firma con la clave del anfitrión de la oferta (la que
  ///    autenticó el código en persona), y que la aprobación es de esta
  ///    lista, generación, invitación, transcript y fichas.
  /// 2. Descarga el checkpoint y exige los dos hashes exactos firmados.
  /// 3. Verifica el registro del checkpoint y lo fusiona con el suyo.
  /// 4. Abre su paquete: el v4 de la candidata del común con el formato 2,
  ///    o la `familyKey` en v3 sin el corte.
  /// 5. Autentica y abre el común del checkpoint: es la base que se instala.
  /// 6. Lee la instantánea actual solo para no aceptar una versión anterior a
  ///    la aprobada; lo que traiga se fusiona en la primera vuelta.
  ///
  /// Un servidor que retiene el checkpoint deja el emparejamiento pendiente
  /// (null), nunca instalado con otra base. Lanza [PairingException] si el
  /// código no se ha confirmado aquí o si algo no casa.
  Future<PairingV2Joined?> finish() async {
    final join = _join;
    if (join == null || _code == null || !_confirmed) {
      throw const PairingException('el código no se ha confirmado');
    }
    final outcome = await _poll();
    if (outcome is V2InviteGone) throw const InviteGoneException();
    if (outcome is! V2InviteApproved) return null;
    // Desde aquí la credencial de este móvil ya está registrada en la lista:
    // un fallo definitivo la deja colgada (M3, ver [approved]).
    _approved = true;
    // La revelación tiene que ser la misma con la que se enseñó el código.
    final reveal = PairingReveal.fromJson(outcome.reveal);
    if (join.codeFor(reveal) != _code) {
      throw const PairingException('la revelación ha cambiado');
    }
    final package = outcome.package;
    if (package['v'] != kPairingPackageVersion) {
      throw const PairingV2VersionMismatchException();
    }
    final approval = await _checkApproval(package, join, reveal, outcome);

    // 2. El checkpoint exacto.
    onRequest?.call();
    final checkpoint = await _transport.getInviteCheckpoint(
      inviteId,
      credential: _keys.serviceCredential,
    );
    if (checkpoint == null) return null;
    if (!constantTimeEquals(
          utf8.encode(pairingCheckpointHash('common', checkpoint.common)),
          utf8.encode(approval.commonHash),
        ) ||
        !constantTimeEquals(
          utf8.encode(pairingCheckpointHash('registry', checkpoint.registry)),
          utf8.encode(approval.registryHash),
        )) {
      throw const PairingException('el checkpoint no es el aprobado');
    }

    // 3. El registro aprobado.
    final anchor = RegistryAnchor(
      deviceId: kind == DeviceKind.web ? offer.host.deviceId : _deviceId,
      signingKey: kind == DeviceKind.web
          ? offer.host.keys.signing
          : _keys.publicKeys.signing,
    );
    final DeviceRegistry registry;
    try {
      registry = await join.registry.merge(
        await DeviceRegistry.fromJsonVerified(
          jsonDecode(checkpoint.registry),
          anchor: anchor,
        ),
        anchor: anchor,
      );
    } on RegistryException {
      throw const PairingException('registro no válido');
    } on FormatException {
      throw const PairingException('registro no válido');
    }
    // Las personas no hacen falta para abrir la clave ni el común (el
    // contexto de la época no depende de ellas).
    final view = await registry.viewFor(
      me: anchor.deviceId,
      mySigningKey: anchor.signingKey,
      livePeople: livePeopleOf(FamilyDoc.empty(offer.listId)),
    );
    final host = view.member(offer.host.deviceId);
    if (host == null || host.recordDigest != offer.host.digest) {
      throw const PairingException('el anfitrión no me ha avalado');
    }
    if (kind == DeviceKind.web &&
        (view.revokedByOthers ||
            webStatusIn(view, _deviceId) != WebDeviceStatus.confirmed ||
            view.member(_deviceId)?.recordDigest != join.answer.guest.digest)) {
      throw const PairingException('la web no está avalada por el anfitrión');
    }

    // 4 y 5. La clave y la base.
    final Uint8List bytes;
    try {
      bytes = decodeBase64Url(checkpoint.common);
    } on FormatException {
      throw const PairingException('documento común no válido');
    }
    if (encodeBase64Url(bytes) != checkpoint.common ||
        isFamilyEnvelope(bytes) != (approval.commonFormat >= 2)) {
      throw const PairingException('documento común no válido');
    }
    final FamilyKey familyKey;
    final FamilyDoc common;
    CommonKeyState? commonKeys;
    if (approval.commonFormat >= 2) {
      if (kind == DeviceKind.web && !kWebPairingCommonV2) {
        throw const PairingException(
          'la web todavía no sigue el formato 2 del común',
        );
      }
      (common, commonKeys) = await _openFormat2(
        bytes,
        approval.packages,
        view: view,
        registry: registry,
        syncId: outcome.syncId,
      );
      // No viaja ninguna `familyKey`: la de este móvil es local y no abre
      // nada (nunca se abre un formato 1 con la marca).
      familyKey = await FamilyKey.generate();
    } else {
      (common, familyKey) = await _openFormat1(
        bytes,
        approval.packages,
        view: view,
      );
    }
    if (syncProtocolOf(common) != kSyncProtocolV2) {
      throw const PairingException('el documento común no es de v2');
    }

    // 6. Nada de lo que diga el servidor fuera del checkpoint entra aquí
    // (M1): la instantánea de partida (la que guarda la web en su caja) es
    // el checkpoint verificado con el suelo de versión firmado, sin
    // paquetes ni dispositivos. Los slots que conocía el anfitrión salen de
    // sus suelos firmados (la web los usa como testigo de quién está
    // protegido), con versión 0: nunca se leen. La primera vuelta lee lo actual, lo
    // verifica y lo fusiona, y rechaza una versión anterior a ese suelo.
    final identity = SyncIdentityV2(
      listId: offer.listId,
      deviceId: _deviceId,
      syncId: outcome.syncId,
    );
    final snap = V2Snapshot(
      version: approval.minVersion,
      common: bytes,
      registry: jsonDecode(checkpoint.registry),
      keyPackages: const [],
      slots: [
        for (final key in approval.slotFloors.keys.toList()..sort())
          if (key.indexOf('/') case final i when i > 0)
            V2SlotRef(
              personId: key.substring(0, i),
              deviceId: key.substring(i + 1),
              version: 0,
            ),
      ],
      devices: const [],
      minCommonFormat: approval.commonFormat,
    );
    return PairingV2Joined(
      common: common,
      hostDeviceId: offer.host.deviceId,
      hostAnchor: RegistryAnchor(
        deviceId: offer.host.deviceId,
        signingKey: offer.host.keys.signing,
      ),
      snapshot: snap,
      identity: identity,
      familyKey: familyKey,
      registry: registry,
      minVersion: approval.minVersion,
      minSlotRevisions: approval.slotFloors,
      commonFormat: approval.commonFormat,
      commonKeys: commonKeys,
    );
  }

  /// Paso 1: la forma exacta, la firma del anfitrión de la oferta y que es
  /// de esta lista, generación, invitación, transcript y fichas.
  Future<_Approval> _checkApproval(
    Map<String, Object?> package,
    PairingJoin join,
    PairingReveal reveal,
    V2InviteApproved outcome,
  ) async {
    const bad = PairingException('aprobación sin autenticar');
    // 1.0.6: la persona que eligió el anfitrión va firmada en la aprobación
    // ([kHostPicksPersonField]); es la única clave opcional.
    final picked = package.containsKey(kHostPicksPersonField);
    if (package.length != _approvalKeys.length + (picked ? 1 : 0) ||
        !package.keys.every(
          (k) => _approvalKeys.contains(k) || k == kHostPicksPersonField,
        )) {
      throw bad;
    }
    final sig = package['sig'];
    final minVersion = package['minVersion'];
    final format = package['minCommonFormat'];
    final packages = package['familyKeyPackages'];
    final floors = package['slotFloors'];
    final cc = package['commonCheckpointHash'];
    final rc = package['registryCheckpointHash'];
    if (sig is! String ||
        minVersion is! int ||
        minVersion < 1 ||
        (format != 1 && format != kCommonFormatLatest) ||
        packages is! List ||
        packages.isEmpty ||
        packages.length > kPairingMaxFamilyPackages ||
        packages.any((p) => p is! Map) ||
        floors is! Map ||
        floors.entries.any(
          (e) => e.key is! String || e.value is! int || (e.value as int) < 0,
        ) ||
        cc is! String ||
        !_hash43.hasMatch(cc) ||
        rc is! String ||
        !_hash43.hasMatch(rc)) {
      throw bad;
    }
    try {
      if (!await verifyDeviceSignature(
        message: _approvalBytes(package),
        signature: decodeBase64Url(sig),
        signingPublicKey: offer.host.keys.signing,
      )) {
        throw bad;
      }
    } on FormatException {
      throw bad;
    }
    // Firmada por el anfitrión: ahora, ¿es de este emparejamiento?
    if (package['listId'] != offer.listId ||
        package['syncId'] != outcome.syncId ||
        package['inviteId'] != inviteId ||
        package['hostRecord'] != offer.host.digest ||
        package['guestRecord'] != join.answer.guest.digest ||
        package['transcriptHash'] != join.transcriptHash(inviteId, reveal)) {
      throw const PairingException('la aprobación es de otro emparejamiento');
    }
    // 1.0.6: un móvil entra solo con la persona que eligió el anfitrión y
    // que este firma: así se sabe que la marca de la oferta era suya y que
    // protegió el común antes de aprobar (una marca añadida por el camino a
    // la oferta de un anfitrión viejo no llega firmada).
    if (kind == DeviceKind.mobile &&
        (assignedPerson == null ||
            package[kHostPicksPersonField] != assignedPerson)) {
      throw const PairingV2VersionMismatchException();
    }
    return _Approval(
      minVersion: minVersion,
      commonFormat: format! as int,
      commonHash: cc,
      registryHash: rc,
      packages: [for (final p in packages) Map<String, Object?>.from(p as Map)],
      slotFloors: {
        for (final e in floors.entries) e.key as String: e.value as int,
      },
    );
  }

  /// Sin el corte: la `familyKey` en v3 del anfitrión abre el común.
  Future<(FamilyDoc, FamilyKey)> _openFormat1(
    Uint8List bytes,
    List<Map<String, Object?>> packages, {
    required RegistryView view,
  }) async {
    if (packages.length != 1) {
      throw const PairingException('paquete no válido');
    }
    final KeyBundle bundle;
    final FamilyKey familyKey;
    try {
      bundle = KeyBundle.fromJson(packages.single);
      if (bundle.fromDevice != offer.host.deviceId ||
          bundle.toDevice != _deviceId) {
        throw const PairingException('el paquete no es del anfitrión');
      }
      familyKey = await bundle.openFamilyKey(mine: _keys, view: view);
    } on KeyBundleException {
      throw const PairingException('la clave de la familia no se abre');
    }
    try {
      final opened = await env.open(
        bytes,
        key: familyKey,
        expectedListId: offer.listId,
      );
      return (FamilyDoc.fromJson(opened.doc), familyKey);
    } on EnvelopeException {
      throw const PairingException('documento común no válido');
    } on FormatException {
      throw const PairingException('documento común no válido');
    }
  }

  /// Tras el corte: el paquete v4 de la candidata del común (verificado
  /// como cualquier otro: emisor, audiencia, creador enlazado y `kid`) y el
  /// común firmado por un miembro activo. Devuelve la base y el llavero con
  /// esa candidata referenciada como la del común.
  Future<(FamilyDoc, CommonKeyState)> _openFormat2(
    Uint8List bytes,
    List<Map<String, Object?>> packages, {
    required RegistryView view,
    required DeviceRegistry registry,
    required String syncId,
  }) async {
    final String kid;
    try {
      kid = peekFamilyEnvelope(bytes).kid;
    } on EnvelopeException {
      throw const PairingException('documento común no válido');
    }
    bool sealable(FamilyCandidate c) => c.sealableIn(view, syncId: syncId);
    var keyring = FamilyKeyring.empty;
    // B4: los que no abren se saltan; hace falta al menos uno válido.
    for (final raw in packages) {
      try {
        final bundle = FamilyKeyBundle.fromJson(raw);
        if (bundle.toDevice != _deviceId || bundle.kid != kid) continue;
        final candidate = await bundle.open(
          mine: _keys,
          view: view,
          registry: registry,
          syncId: syncId,
        );
        keyring = keyring.withReceivedCandidate(
          candidate,
          from: bundle.fromDevice,
          fromRecord: bundle.senderRecord,
          sealable: sealable,
          wanted: {kid},
        );
      } on KeyBundleException {
        continue;
      } on FamilyKeyException {
        continue;
      }
    }
    if (keyring.entry(kid) == null) {
      throw const PairingException('la clave común no se abre');
    }
    final FamilyDoc doc;
    try {
      doc = (await openFamilyEnvelope(
        bytes,
        expectedListId: offer.listId,
        expectedSyncId: syncId,
        resolveWriter: commonWriterResolver(view, registry),
        keyring: keyring,
      )).doc;
    } on EnvelopeException {
      throw const PairingException('documento común no válido');
    }
    return (
      doc,
      CommonKeyState(
        keyring: keyring.withReference(kid, kCommonRef),
        lastKid: kid,
      ),
    );
  }
}

/// La aprobación v4 ya comprobada.
class _Approval {
  const _Approval({
    required this.minVersion,
    required this.commonFormat,
    required this.commonHash,
    required this.registryHash,
    required this.packages,
    required this.slotFloors,
  });

  final int minVersion;
  final int commonFormat;
  final String commonHash;
  final String registryHash;
  final List<Map<String, Object?>> packages;
  final Map<String, int> slotFloors;
}

/// B1: tras el corte una web no se empareja hasta B5 ([kWebPairingCommonV2]);
/// se para antes de publicar ninguna ficha, aval ni reparto.
Future<void> _refuseWebAfterCut(SyncV2Local local) async {
  if (!kWebPairingCommonV2 &&
      await local.commonFormatFloor() >= kCommonFormatLatest) {
    throw const PairingException(
      'la web todavía no sigue el formato 2 del común',
    );
  }
}

V2Auth _authOf(SyncV2Local local) => V2Auth(
  syncId: local.identity.syncId,
  deviceId: local.identity.deviceId,
  credential: Uint8List.fromList(local.keys.serviceCredential),
);

Future<RegistryView> _viewOf(
  SyncV2Local local,
  DeviceRegistry registry,
) async => registry.viewFor(
  me: local.identity.deviceId,
  mySigningKey: local.keys.publicKeys.signing,
  livePeople: livePeopleOf(await local.common()),
);
