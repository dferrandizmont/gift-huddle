// Emparejamiento v2 (modelo) y formato de la migración v1 → v2. Dart puro.
// Decisión: docs/adr/0004-yo-sorpresas-revocar.md (fase 2a).
//
// Emparejar en v2 es intercambiar fichas y avales del registro de móviles,
// con un código corto que se compara en persona (compromiso y revelación,
// hallazgo 6 de la revisión de la fase 2a):
// 1. El móvil que ya está en la familia (anfitrión) enseña su oferta: la
//    lista, su ficha firmada y el compromiso de un nonce aleatorio que
//    guarda en secreto ([PairingHost]). La clave de la familia sigue
//    viajando como en v1 (QR en persona o invitación cifrada); aquí no va.
// 2. El invitado crea su ficha con sus claves persistentes (y una persona:
//    sin ella, solo marcándolo a propósito), avala la del anfitrión (la ha
//    visto en persona) y responde con las dos cosas y un nonce suyo.
// 3. El anfitrión comprueba la respuesta, acepta una sola y solo entonces
//    revela su nonce ([PairingReveal]). El invitado comprueba que casa con
//    el compromiso.
// 4. Los dos enseñan el mismo código de seis cifras ([pairingCode]), que
//    sale de las dos fichas y de los dos nonces. Cuando una persona confirma
//    en la pantalla del anfitrión que coincide y de quién es el móvil, lo
//    avala.
// Quien sustituya la respuesta del invitado tiene que elegir su ficha antes
// de conocer el nonce: acierta el código con una probabilidad de uno entre
// un millón, y no puede probar fichas sin conexión.
// «Emparejado» ya no es una marca local: es `RegistryView.paired`.
//
// Migración: no hay conversión en el servidor. Un móvil pasa su documento a
// v2 (misma lista, clave de la familia nueva, `syncId` aleatorio y un
// registro con solo su ficha) y los otros dos vuelven a emparejarse con él;
// al entrar fusionan su copia local de v1. Un móvil migrado no vuelve a v1.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';

import 'device_keys.dart';
import 'device_registry.dart';
import 'envelope.dart' show FamilyKey, decodeBase64Url, encodeBase64Url;
import 'family_doc.dart';
import 'hlc.dart';
import 'hmac.dart';
import 'model.dart' show Collections;

/// Versión del protocolo de sincronización con registro de móviles.
const int kSyncProtocolV2 = 2;

/// Id del registro de `meta` que marca el protocolo del documento.
const String kProtocolRecordId = 'protocol';

/// Campo de [kProtocolRecordId] con la versión del protocolo.
const String kProtocolVersionField = 'syncProtocol';

/// Bytes del nonce que el anfitrión compromete en su oferta.
const int kPairingNonceBytes = 32;

/// Un emparejamiento que no vale.
class PairingException implements Exception {
  /// Crea el error.
  const PairingException(this.message);

  /// Qué pasó (sin claves).
  final String message;

  @override
  String toString() => 'PairingException: $message';
}

/// Huella del QR web (ADR 0003 §5): 16 bytes de SHA-256 del dominio,
/// inviteId decodificado (16 bytes), Ed25519 y X25519, en base64url.
String webPairingFingerprint(
  String inviteId,
  List<int> signingPub,
  List<int> agreementPub,
) {
  final List<int> invite;
  try {
    invite = decodeBase64Url(inviteId);
  } on FormatException {
    throw const PairingException('invitación web no válida');
  }
  if (invite.length != 16 ||
      signingPub.length != 32 ||
      agreementPub.length != 32) {
    throw const PairingException('invitación web no válida');
  }
  return encodeBase64Url(
    const DartSha256()
        .hashSync([
          ...'gift-huddle web pairing v1'.codeUnits,
          0,
          ...invite,
          ...signingPub,
          ...agreementPub,
        ])
        .bytes
        .sublist(0, 16),
  );
}

List<int> _commitmentOf(DeviceRecord host, List<int> nonce) =>
    const DartSha256().hashSync([
      ...'gift-huddle-pairing-commit-v1'.codeUnits,
      0,
      ...decodeBase64Url(host.digest),
      ...nonce,
    ]).bytes;

Uint8List _bytes32(Object? value) {
  if (value is! String) throw const PairingException('formato no válido');
  final Uint8List bytes;
  try {
    bytes = decodeBase64Url(value);
  } on FormatException {
    throw const PairingException('formato no válido');
  }
  if (bytes.length != 32) throw const PairingException('formato no válido');
  return bytes;
}

/// Campo de la oferta que dice que el anfitrión elige la persona del móvil
/// nuevo (1.0.6). Sin él, un invitado 1.0.6 no entra: el anfitrión es de
/// una versión que deja entrar sin persona.
const String kHostPicksPersonField = 'hp';

/// Lo que enseña el anfitrión: su ficha y el compromiso de su nonce.
class PairingOffer {
  PairingOffer._(this.host, this.commitment, {this.hostPicksPerson = false});

  /// La ficha del anfitrión.
  final DeviceRecord host;

  /// SHA-256("gift-huddle-pairing-commit-v1" ‖ 0 ‖ resumen de la ficha ‖
  /// nonce): ata el nonce a la oferta sin enseñarlo.
  final Uint8List commitment;

  /// La marca [kHostPicksPersonField]: el anfitrión ha elegido para quién es
  /// el móvil nuevo y solo acepta una respuesta de esa persona. No va
  /// firmada: si alguien la quita o la cambia, solo consigue que el
  /// emparejamiento falle (el anfitrión comprueba la persona en
  /// [PairingHost.receive]).
  final bool hostPicksPerson;

  /// Lista.
  String get listId => host.listId;

  /// La oferta en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'v': kSyncProtocolV2,
    'host': host.toJson(),
    'c': encodeBase64Url(commitment),
    if (hostPicksPerson) kHostPicksPersonField: 1,
  };

  /// Lee [toJson] y comprueba la firma de la ficha. Lanza
  /// [PairingException] si no vale.
  static Future<PairingOffer> fromJson(Object? json) async {
    if (json is! Map || json['v'] != kSyncProtocolV2) {
      throw const PairingException('oferta no válida');
    }
    final DeviceRecord host;
    try {
      host = DeviceRecord.fromJson(json['host']);
    } on RegistryException {
      throw const PairingException('oferta no válida');
    }
    final commitment = _bytes32(json['c']);
    if (host.kind == DeviceKind.web || !await host.verify()) {
      throw const PairingException('la ficha del anfitrión no vale');
    }
    return PairingOffer._(
      host,
      commitment,
      hostPicksPerson: json[kHostPicksPersonField] == 1,
    );
  }
}

/// Campo de la oferta con la prueba de la clave v1 ([v1ListProof]).
const String kV1ProofField = 'p1';

/// Prueba de que el anfitrión de [offer] tiene la clave de la familia v1 de
/// su lista (revisión de la fase 2b, hallazgo 6): el `listId` es público y
/// no basta para decidir que es «la misma lista».
///
/// HMAC-SHA256 con la clave v1 sobre
/// "gift-huddle-pairing-v1-proof" ‖ 0 ‖ lista ‖ 0 ‖ resumen de la ficha del
/// anfitrión ‖ compromiso. Ata la prueba a esta oferta: copiada en otra (otra
/// ficha u otro nonce) no vale.
Uint8List v1ListProof(FamilyKey v1Key, PairingOffer offer) =>
    Uint8List.fromList(
      hmacSha256(v1Key.bytes, [
        ...'gift-huddle-pairing-v1-proof'.codeUnits,
        0,
        ...offer.listId.codeUnits,
        0,
        ...decodeBase64Url(offer.host.digest),
        ...offer.commitment,
      ]),
    );

/// Si [proof] (el campo [kV1ProofField] de la oferta, tal cual llegó) es la
/// prueba de [v1Key] para [offer]. Cualquier formato raro es `false`.
bool verifyV1ListProof(FamilyKey v1Key, PairingOffer offer, Object? proof) {
  if (proof is! String) return false;
  final List<int> got;
  try {
    got = decodeBase64Url(proof);
  } on FormatException {
    return false;
  }
  final want = v1ListProof(v1Key, offer);
  if (got.length != want.length) return false;
  var diff = 0;
  for (var i = 0; i < want.length; i++) {
    diff |= got[i] ^ want[i];
  }
  return diff == 0;
}

/// El nonce que revela el anfitrión cuando ya tiene la respuesta.
class PairingReveal {
  PairingReveal._(this.nonce);

  /// El nonce comprometido en la oferta.
  final Uint8List nonce;

  /// La revelación en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'v': kSyncProtocolV2,
    'n': encodeBase64Url(nonce),
  };

  /// Lee [toJson]. Lanza [PairingException] si no vale.
  factory PairingReveal.fromJson(Object? json) {
    if (json is! Map || json['v'] != kSyncProtocolV2) {
      throw const PairingException('revelación no válida');
    }
    return PairingReveal._(_bytes32(json['n']));
  }
}

/// El emparejamiento en el lado del anfitrión: guarda el nonce y acepta una
/// sola respuesta. Vive solo en memoria mientras dura el emparejamiento.
class PairingHost {
  PairingHost._(
    this.offer,
    this._nonce,
    this.expectWeb,
    this._inviteId,
    this._guestPerson,
    this._expectedFingerprint,
    this.hostPicksPerson,
  );

  /// Empieza un emparejamiento con la ficha actual de este móvil.
  /// Con [expectWeb], fija el QR y la persona elegida antes de recibir la
  /// respuesta. Las tres restricciones son obligatorias y se comprueban
  /// antes de revelar el nonce. El flujo normal solo admite móviles.
  ///
  /// Con [hostPicksPerson] (móviles, 1.0.6) este móvil ha elegido para quién
  /// es el móvil nuevo: [guestPerson], que tiene que existir (quien no está
  /// en la lista se da de alta antes; «Nadie» es una persona que solo
  /// regala). La oferta lleva la marca [kHostPicksPersonField] y solo se
  /// acepta una respuesta con esa misma persona. Ningún móvil entra sin
  /// persona. No se fía de lo que compruebe el servidor: la aprobación
  /// firmada lleva también la persona ([kHostPicksPersonField]).
  static PairingHost start(
    DeviceRegistry registry,
    RegistryView view, {
    bool expectWeb = false,
    String? inviteId,
    String? guestPerson,
    String? expectedFingerprint,
    bool hostPicksPerson = false,
  }) {
    final host = registry.recordByDigest(view.self.recordDigest)!;
    if (host.kind == DeviceKind.web) {
      throw const PairingException('una web no puede invitar');
    }
    if (hostPicksPerson) {
      if (expectWeb) {
        throw const PairingException('la web ya fija su persona');
      }
      // 1.0.6: un móvil nuevo siempre entra con persona («Nadie» también es
      // una persona, que solo regala).
      if (guestPerson == null || !view.livePeople.contains(guestPerson)) {
        throw const PairingException('esa persona no existe en la familia');
      }
    }
    if (expectWeb) {
      if (inviteId == null ||
          guestPerson == null ||
          !view.livePeople.contains(guestPerson) ||
          expectedFingerprint == null) {
        throw const PairingException(
          'faltan los datos del QR web o su persona',
        );
      }
      // Valida el formato ahora; las claves del invitado se comprueban al recibir.
      webPairingFingerprint(inviteId, host.keys.signing, host.keys.agreement);
      try {
        if (decodeBase64Url(expectedFingerprint).length != 16) {
          throw const FormatException();
        }
      } on FormatException {
        throw const PairingException('huella web no válida');
      }
    }
    final nonce = secureRandomBytes(kPairingNonceBytes);
    return PairingHost._(
      PairingOffer._(
        host,
        Uint8List.fromList(_commitmentOf(host, nonce)),
        hostPicksPerson: hostPicksPerson,
      ),
      nonce,
      expectWeb,
      inviteId,
      guestPerson,
      expectedFingerprint,
      hostPicksPerson,
    );
  }

  /// La oferta que se enseña (QR).
  final PairingOffer offer;

  final Uint8List _nonce;

  /// Si esta sesión conecta una web con el QR y la persona fijados.
  final bool expectWeb;
  final String? _inviteId;
  final String? _guestPerson;
  final String? _expectedFingerprint;

  /// Si este móvil ha elegido la persona del móvil nuevo ([start]).
  final bool hostPicksPerson;

  /// La persona que eligió este móvil para el invitado (o para la web), o
  /// null.
  String? get guestPerson => _guestPerson;
  PairingAnswer? _answer;

  /// La respuesta recibida, o null.
  PairingAnswer? get answer => _answer;

  bool _checking = false;

  /// Recibe la respuesta del invitado y devuelve la revelación que hay que
  /// mandarle. Solo una: después de revelar el nonce, otra respuesta podría
  /// elegirse a propósito para que el código coincida.
  ///
  /// Antes de gastar la única respuesta comprueba la ficha del invitado y su
  /// aval a esta oferta (segunda revisión, N5): una respuesta rota no deja el
  /// emparejamiento inservible. Lanza [PairingException] si ya había una, si
  /// se está comprobando otra o si esta no vale (y entonces no la gasta).
  Future<PairingReveal> receive(PairingAnswer answer) async {
    if (_answer != null) {
      throw const PairingException('este emparejamiento ya tiene respuesta');
    }
    if (_checking) {
      throw const PairingException('ya se está comprobando una respuesta');
    }
    _checking = true;
    try {
      await _check(answer);
    } finally {
      _checking = false;
    }
    _answer = answer;
    return PairingReveal._(Uint8List.fromList(_nonce));
  }

  Future<void> _check(PairingAnswer answer) async {
    final host = offer.host;
    final guest = answer.guest;
    final vouch = answer.vouchForHost;
    if (expectWeb) {
      if (guest.kind != DeviceKind.web ||
          guest.personId != _guestPerson ||
          !constantTimeEquals(
            decodeBase64Url(
              webPairingFingerprint(
                _inviteId!,
                guest.keys.signing,
                guest.keys.agreement,
              ),
            ),
            decodeBase64Url(_expectedFingerprint!),
          )) {
        throw const PairingException('la respuesta no corresponde a esa web');
      }
    } else if (guest.kind != DeviceKind.mobile) {
      throw const PairingException('este flujo solo conecta móviles');
    } else if (hostPicksPerson &&
        (guest.personId == null || !answer.hostPicksPerson)) {
      // Un invitado 1.0.5: responde sin persona («Elegir después», el de una
      // instalación nueva) o sin la marca (QA 1.0.6, m1). No se gasta la
      // respuesta y no se aprueba: el otro móvil tiene que actualizarse.
      throw const PairingGuestOutdatedException();
    } else if (guest.personId == null) {
      // 1.0.6: ningún móvil entra sin persona (también un invitado viejo que
      // responde «Elegir después»). No se gasta la única respuesta.
      throw const PairingException('el móvil nuevo no tiene persona');
    } else if (hostPicksPerson && guest.personId != _guestPerson) {
      // Una respuesta con la marca cambiada por el camino: no se gasta la
      // única respuesta. (Un 1.0.5 que eligió otra persona, o la misma, no
      // lleva la marca y ya ha salido arriba: B1.)
      throw const PairingException('la respuesta no es de la persona elegida');
    }
    if (guest.listId != host.listId ||
        guest.deviceId == host.deviceId ||
        !await guest.verify()) {
      throw const PairingException('la ficha del móvil nuevo no vale');
    }
    if (vouch.by != guest.deviceId ||
        vouch.byRecord != guest.digest ||
        vouch.deviceId != host.deviceId ||
        vouch.recordDigest != host.digest ||
        vouch.listId != host.listId ||
        !await vouch.verify(guest.keys.signing)) {
      throw const PairingException('el aval no es para esta oferta');
    }
  }

  /// El resumen de lo intercambiado en persona ([pairingTranscriptHash])
  /// para la invitación [inviteId]. Lanza [StateError] sin respuesta.
  String transcriptHash(String inviteId) {
    final answer = _answer;
    if (answer == null) throw StateError('todavía no hay respuesta');
    return pairingTranscriptHash(
      inviteId: inviteId,
      offer: offer,
      answer: answer,
      hostNonce: _nonce,
    );
  }

  /// El código que enseña el anfitrión. Lanza [StateError] sin respuesta.
  String get code {
    final answer = _answer;
    if (answer == null) throw StateError('todavía no hay respuesta');
    return pairingCode(offer.host, answer.guest, _nonce, answer.guestNonce);
  }
}

/// El invitado que respondió es de una versión que no entiende que el
/// anfitrión elija la persona (1.0.5): tiene que actualizarse antes de
/// emparejar.
class PairingGuestOutdatedException extends PairingException {
  /// Crea el error.
  const PairingGuestOutdatedException()
    : super('el otro móvil necesita actualizarse');
}

/// Lo que responde el invitado: su ficha, su aval a la del anfitrión y un
/// nonce suyo.
class PairingAnswer {
  PairingAnswer._(
    this.guest,
    this.vouchForHost,
    this.guestNonce, {
    this.hostPicksPerson = true,
  });

  /// Si el invitado entiende la marca [kHostPicksPersonField] (1.0.6): un
  /// invitado 1.0.5 no la manda y rechazaría la aprobación con esa marca
  /// después de que el Worker cree su credencial (una credencial fantasma,
  /// revisión de seguridad, B1). El anfitrión que eligió la persona no
  /// gasta la respuesta de un invitado así. No va firmada: quitarla solo
  /// impide emparejar, y ponerla a un invitado viejo deja lo de antes.
  final bool hostPicksPerson;

  /// La ficha del invitado.
  final DeviceRecord guest;

  /// El aval del invitado a la ficha del anfitrión.
  final Vouch vouchForHost;

  /// Nonce aleatorio del invitado (32 bytes), que entra en el código junto
  /// con el del anfitrión, como en la comparación numérica de Bluetooth
  /// (segunda revisión, N5): el código no depende solo de lo que elige uno.
  final Uint8List guestNonce;

  /// Si el invitado no ha elegido persona (lo ha marcado a propósito: ver
  /// [joinPairing]). La pantalla del anfitrión tiene que decirlo claramente;
  /// [acceptPairing] lo exige.
  bool get withoutPerson => guest.personId == null;

  /// La respuesta en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'v': kSyncProtocolV2,
    'guest': guest.toJson(),
    'vouch': vouchForHost.toJson(),
    'gn': encodeBase64Url(guestNonce),
    if (hostPicksPerson) kHostPicksPersonField: 1,
  };

  /// Lee [toJson] (se comprueba en [PairingHost.receive] y en
  /// [acceptPairing]). Lanza [PairingException] si el formato no vale.
  factory PairingAnswer.fromJson(Object? json) {
    if (json is! Map || json['v'] != kSyncProtocolV2) {
      throw const PairingException('respuesta no válida');
    }
    try {
      return PairingAnswer._(
        DeviceRecord.fromJson(json['guest']),
        Vouch.fromJson(json['vouch']),
        _bytes32(json['gn']),
        hostPicksPerson: json[kHostPicksPersonField] == 1,
      );
    } on RegistryException {
      throw const PairingException('respuesta no válida');
    }
  }
}

/// Lo que guarda el invitado al aceptar una oferta.
class PairingJoin {
  /// Crea el resultado.
  const PairingJoin({
    required this.registry,
    required this.answer,
    required this.offer,
  });

  /// El registro del invitado: su ficha, la del anfitrión y su aval.
  final DeviceRegistry registry;

  /// Lo que hay que hacer llegar al anfitrión.
  final PairingAnswer answer;

  /// La oferta que aceptó (con el compromiso del anfitrión).
  final PairingOffer offer;

  /// El código que enseña el invitado cuando llega la revelación. Lanza
  /// [PairingException] si el nonce no casa con el compromiso de la oferta.
  String codeFor(PairingReveal reveal) {
    if (!constantTimeEquals(
      _commitmentOf(offer.host, reveal.nonce),
      offer.commitment,
    )) {
      throw const PairingException('la revelación no casa con la oferta');
    }
    return pairingCode(
      offer.host,
      answer.guest,
      reveal.nonce,
      answer.guestNonce,
    );
  }

  /// El resumen de lo intercambiado ([pairingTranscriptHash]) con la
  /// revelación [reveal], que tiene que casar con el compromiso (si no,
  /// [PairingException]).
  String transcriptHash(String inviteId, PairingReveal reveal) {
    codeFor(reveal);
    return pairingTranscriptHash(
      inviteId: inviteId,
      offer: offer,
      answer: answer,
      hostNonce: reveal.nonce,
    );
  }
}

/// JSON canónico: claves ordenadas y `jsonEncode`, sin espacios. Es el que
/// firma la aprobación y el que hashea el checkpoint del registro (el Worker
/// lo reproduce con `JSON.stringify` sobre las claves ordenadas).
String canonicalJsonText(Object? value) => jsonEncode(_sortedJson(value));

Object? _sortedJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _sortedJson(value[key])};
  }
  if (value is List) return [for (final item in value) _sortedJson(item)];
  return value;
}

String _domainHash(String domain, List<int> body) => encodeBase64Url(
  const DartSha256().hashSync([...utf8.encode(domain), 0, ...body]).bytes,
);

/// Resumen de lo intercambiado en persona (ADR 0005, B7): liga la
/// invitación, la oferta (ficha del anfitrión y compromiso), la respuesta
/// (ficha y nonce del invitado) y la revelación (nonce del anfitrión).
/// SHA-256("gift-huddle-pairing-transcript-v1" ‖ 0 ‖ JSON canónico) en
/// base64url. La aprobación firmada lo lleva: una aprobación de otra
/// invitación, de otra respuesta o de otra revelación no casa.
String pairingTranscriptHash({
  required String inviteId,
  required PairingOffer offer,
  required PairingAnswer answer,
  required List<int> hostNonce,
}) => _domainHash(
  'gift-huddle-pairing-transcript-v1',
  utf8.encode(
    canonicalJsonText({
      'i': inviteId,
      'l': offer.listId,
      'h': offer.host.digest,
      'c': encodeBase64Url(offer.commitment),
      'g': answer.guest.digest,
      'gn': encodeBase64Url(answer.guestNonce),
      'n': encodeBase64Url(hostNonce),
    }),
  ),
);

/// Hash de una parte del checkpoint del emparejamiento (ADR 0005, B7):
/// SHA-256("gift-huddle-pairing-checkpoint-`part`-v1" ‖ 0 ‖ texto exacto)
/// en base64url. [part] es `common` (el texto base64url del común) o
/// `registry` (el registro en [canonicalJsonText]). El Worker calcula lo
/// mismo al copiarlo; el invitado lo comprueba con la aprobación firmada.
String pairingCheckpointHash(String part, String text) {
  if (part != 'common' && part != 'registry') {
    throw ArgumentError.value(part, 'part');
  }
  return _domainHash(
    'gift-huddle-pairing-checkpoint-$part-v1',
    utf8.encode(text),
  );
}

/// El invitado acepta [offer]: crea su ficha con sus claves persistentes
/// [keys] y avala al anfitrión. [personId] es la persona que ha elegido; no
/// le da ningún permiso hasta que otro móvil la apruebe.
///
/// Sin persona hay que decirlo a propósito ([withoutPerson]; segunda
/// revisión, N2): su aval al anfitrión se firma sin persona y no cuenta para
/// ninguna sorpresa, así que si después elige «Yo» tendrá que volver a
/// avalar a los demás (lo pide [changePerson] en sus huérfanos). Lanza
/// [PairingException] si [personId] es null y [withoutPerson] no.
Future<PairingJoin> joinPairing({
  required PairingOffer offer,
  required DeviceKeys keys,
  required String deviceId,
  required String? personId,
  bool withoutPerson = false,
  DeviceKind kind = DeviceKind.mobile,
}) async {
  if (deviceId == offer.host.deviceId) {
    throw const PairingException('ese id ya es el del anfitrión');
  }
  if (personId == null && !withoutPerson) {
    throw const PairingException('el móvil nuevo no ha elegido persona');
  }
  final DeviceRecord mine;
  final Vouch vouch;
  try {
    mine = await DeviceRecord.create(
      keys: keys,
      listId: offer.listId,
      deviceId: deviceId,
      personId: personId,
      kind: kind,
    );
    vouch = await Vouch.create(keys: keys, voucher: mine, record: offer.host);
  } on RegistryException catch (e) {
    throw PairingException(e.message);
  }
  return PairingJoin(
    registry: await DeviceRegistry.empty(offer.listId).withDeclarations(
      records: [mine, offer.host],
      vouches: [if (kind == DeviceKind.mobile) vouch],
      anchor: RegistryAnchor(
        deviceId: kind == DeviceKind.web ? offer.host.deviceId : deviceId,
        signingKey: kind == DeviceKind.web
            ? offer.host.keys.signing
            : keys.publicKeys.signing,
      ),
    ),
    answer: PairingAnswer._(mine, vouch, secureRandomBytes(kPairingNonceBytes)),
    offer: offer,
  );
}

/// El anfitrión acepta la respuesta de [session] después de que una persona
/// compare el código ([PairingHost.code]) con el del invitado y confirme en
/// su pantalla de quién es el móvil nuevo: añade su ficha y los dos avales.
///
/// Lanza [PairingException] si no hay respuesta, si la oferta no es de la
/// ficha actual de este móvil, si la ficha o el aval del invitado no valen,
/// si el aval no es de la ficha actual de este móvil, o si el id ya existe
/// con otras claves o está revocado.
///
/// Un invitado sin persona solo entra con [guestWithoutPerson]: la persona
/// que confirma en la pantalla del anfitrión tiene que ver que ese móvil no
/// es de nadie (segunda revisión, N2). Uno con persona solo entra si
/// [confirmedPersonId] es esa misma persona, que la pantalla del anfitrión
/// enseña aparte («Este móvil dice ser de…»), y si existe en la familia
/// (hallazgo 3 de la revisión de la fase 2b).
Future<RegistryChange> acceptPairing({
  required DeviceRegistry registry,
  required RegistryView view,
  required DeviceKeys myKeys,
  required PairingHost session,
  bool guestWithoutPerson = false,
  String? confirmedPersonId,
}) async {
  final answer = session.answer;
  if (answer == null) {
    throw const PairingException('todavía no hay respuesta');
  }
  if (answer.withoutPerson && !guestWithoutPerson) {
    throw const PairingException('el móvil nuevo no tiene persona');
  }
  // Hallazgo 3: quien está con los dos móviles ha visto a quién dice ser el
  // nuevo y lo ha confirmado aparte; y esa persona existe (ni desconocida ni
  // borrada).
  final claimed = answer.guest.personId;
  if (claimed != null) {
    if (claimed != confirmedPersonId) {
      throw const PairingException('nadie ha confirmado de quién es el móvil');
    }
    if (!view.livePeople.contains(claimed)) {
      throw const PairingException('esa persona no existe en la familia');
    }
  }
  if (session.offer.host.digest != view.self.recordDigest) {
    throw const PairingException('la oferta no es de la ficha actual');
  }
  final guest = answer.guest;
  final vouch = answer.vouchForHost;
  if (guest.listId != registry.listId || !await guest.verify()) {
    throw const PairingException('la ficha del móvil nuevo no vale');
  }
  if (vouch.by != guest.deviceId ||
      vouch.byRecord != guest.digest ||
      vouch.deviceId != view.me ||
      vouch.recordDigest != view.self.recordDigest ||
      vouch.listId != registry.listId) {
    throw const PairingException('el aval no es para este móvil');
  }
  if (!await vouch.verify(guest.keys.signing)) {
    throw const PairingException('el aval del móvil nuevo no vale');
  }
  for (final known in [view.member(guest.deviceId), ...view.pending]) {
    if (known != null &&
        known.deviceId == guest.deviceId &&
        (known.kind != guest.kind ||
            !constantTimeEquals(known.signingKey, guest.keys.signing))) {
      throw const PairingException('ese id ya existe con otras claves');
    }
  }
  if (guest.deviceId == view.me || view.revoked.contains(guest.deviceId)) {
    throw const PairingException('ese móvil no se puede emparejar');
  }
  try {
    return RegistryChange(
      registry: await registry.withDeclarations(
        records: [guest],
        vouches: [
          await Vouch.create(
            keys: myKeys,
            voucher: registry.recordByDigest(view.self.recordDigest)!,
            record: guest,
          ),
          if (guest.kind == DeviceKind.mobile) vouch,
        ],
        anchor: view.anchor,
      ),
      rotates: false,
    );
  } on RegistryException catch (e) {
    throw PairingException(e.message);
  }
}

/// El código de seis cifras que enseñan los dos móviles al emparejarse:
/// SHA-256("gift-huddle-pairing-code-v3" ‖ 0 ‖ ficha del anfitrión ‖ ficha
/// del invitado ‖ nonce del anfitrión ‖ nonce del invitado), los 4 primeros
/// bytes módulo un millón. Solo coincide si los dos ven las mismas fichas y
/// los mismos nonces; el del anfitrión no se conoce hasta que la respuesta ya
/// está fijada (hallazgo 6), y el del invitado lo elige él (N5).
String pairingCode(
  DeviceRecord host,
  DeviceRecord guest,
  List<int> hostNonce,
  List<int> guestNonce,
) {
  final hash = const DartSha256().hashSync([
    ...'gift-huddle-pairing-code-v3'.codeUnits,
    0,
    ...decodeBase64Url(host.digest),
    ...decodeBase64Url(guest.digest),
    ...hostNonce,
    ...guestNonce,
  ]).bytes;
  final n = ByteData.sublistView(Uint8List.fromList(hash)).getUint32(0);
  return (n % 1000000).toString().padLeft(6, '0');
}

// ------------------------------------------------------- migración v1 → v2

/// La identidad de sincronización de un móvil en v2.
class SyncIdentityV2 {
  /// Crea la identidad. Lanza [ArgumentError] si algo no vale.
  SyncIdentityV2({
    required this.listId,
    required this.deviceId,
    required this.syncId,
    this.migratedFromV1 = false,
  }) {
    if (!kSyncIdPattern.hasMatch(listId) ||
        !kSyncIdPattern.hasMatch(deviceId) ||
        !RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(syncId)) {
      throw ArgumentError('identidad v2 no válida');
    }
  }

  /// Lista (la misma que en v1).
  final String listId;

  /// Id de este móvil en el registro.
  final String deviceId;

  /// Dirección de la lista en el servidor: 16 bytes aleatorios en base64url.
  /// Es estable y no se deriva de la clave de la familia, así que rotar la
  /// clave no cambia de lista.
  final String syncId;

  /// Si esta familia viene de una lista v1.
  final bool migratedFromV1;

  /// Un `syncId` nuevo y aleatorio.
  static String newSyncId() => encodeBase64Url(secureRandomBytes(16));

  /// `{"v":2,"l":...,"d":...,"sid":...,"from":1?}`.
  Map<String, Object?> toJson() => <String, Object?>{
    'v': kSyncProtocolV2,
    'l': listId,
    'd': deviceId,
    'sid': syncId,
    if (migratedFromV1) 'from': 1,
  };

  /// Lee [toJson]. Lanza [FormatException] si no vale o es de otra versión
  /// (no hay degradación: un v2 no se lee como v1 ni al revés).
  factory SyncIdentityV2.fromJson(Object? json) {
    if (json is! Map || json['v'] != kSyncProtocolV2) {
      throw const FormatException('identidad v2 no válida');
    }
    final l = json['l'];
    final d = json['d'];
    final sid = json['sid'];
    if (l is! String || d is! String || sid is! String) {
      throw const FormatException('identidad v2 no válida');
    }
    try {
      return SyncIdentityV2(
        listId: l,
        deviceId: d,
        syncId: sid,
        migratedFromV1: json['from'] == 1,
      );
    } on ArgumentError {
      throw const FormatException('identidad v2 no válida');
    }
  }
}

/// El protocolo que marca [doc]: 1 si no dice nada, 1 o [kSyncProtocolV2]
/// si dice uno de esos, y null si dice cualquier otra cosa (una versión que
/// este móvil no conoce, o algo que no es un número). Acotado a lo conocido
/// (hallazgo 14): una marca inventada no puede dejar a nadie fuera.
int? syncProtocolOf(FamilyDoc doc) {
  final record = doc.record(Collections.meta, kProtocolRecordId);
  if (record == null || record.isDeleted) return 1;
  final value = record[kProtocolVersionField];
  if (value == null) return 1;
  // Solo enteros (N4): `2.0` es igual a 2 pero no es un `int`.
  return value is int && (value == 1 || value == kSyncProtocolV2)
      ? value
      : null;
}

/// Una familia recién pasada a v2 en el móvil que hace la migración.
class MigrationV2 {
  /// Crea el resultado.
  const MigrationV2({
    required this.identity,
    required this.common,
    required this.familyKey,
    required this.registry,
  });

  /// Identidad v2 de este móvil.
  final SyncIdentityV2 identity;

  /// El documento común, con la marca del protocolo.
  final FamilyDoc common;

  /// La clave de la familia nueva (época 1 de v2): la de v1 la tenían
  /// móviles que ya no se sabe quiénes son.
  final FamilyKey familyKey;

  /// El registro, con solo la ficha de este móvil.
  final DeviceRegistry registry;
}

/// Pasa a v2 la familia de este móvil. Antes hay que haber recogido los
/// cambios pendientes de v1; después, los otros móviles se emparejan con
/// este y la lista v1 se retira del servidor.
///
/// Lanza [StateError] si [v1Doc] no es de v1.
Future<MigrationV2> migrateToV2({
  required FamilyDoc v1Doc,
  required HlcClock clock,
  required DeviceKeys keys,
  required String deviceId,
  required String? personId,
}) async {
  if (syncProtocolOf(v1Doc) != 1) {
    throw StateError('la familia no está en v1');
  }
  final record = await DeviceRecord.create(
    keys: keys,
    listId: v1Doc.listId,
    deviceId: deviceId,
    personId: personId,
  );
  return MigrationV2(
    identity: SyncIdentityV2(
      listId: v1Doc.listId,
      deviceId: deviceId,
      syncId: SyncIdentityV2.newSyncId(),
      migratedFromV1: true,
    ),
    common: v1Doc.set(clock, Collections.meta, kProtocolRecordId, {
      kProtocolVersionField: kSyncProtocolV2,
    }),
    familyKey: await FamilyKey.generate(),
    registry: await DeviceRegistry.empty(v1Doc.listId).withRecord(record),
  );
}

/// Un móvil que se une a la familia ya migrada fusiona su copia local de v1
/// en el documento de v2 (misma lista, mismos ids: fusión por campo de
/// siempre; lo que v2 borró sigue borrado). Lanza [StateError] si [v2Doc] no
/// es de v2 o [localV1] no es de v1, y [ArgumentError] si son de otra lista.
///
/// La marca del protocolo de [localV1] no entra (hallazgo 1 de la revisión
/// de la fase 2b): quien tenga la clave v1 no puede bajar la marca del
/// documento v2 con un `meta/protocol` más nuevo o con una lápida.
FamilyDoc mergeLocalV1IntoV2({
  required FamilyDoc v2Doc,
  required FamilyDoc localV1,
}) {
  if (syncProtocolOf(v2Doc) != kSyncProtocolV2) {
    throw StateError('el documento de destino no es de v2');
  }
  if (syncProtocolOf(localV1) != 1) {
    throw StateError('la copia local no es de v1');
  }
  return v2Doc.merge(withoutProtocolMark(localV1));
}

/// [doc] sin el registro de la marca del protocolo (ni su lápida). Es lo que
/// se fusiona de una copia v1 en una familia v2.
FamilyDoc withoutProtocolMark(FamilyDoc doc) {
  final meta = doc.collections[Collections.meta];
  if (meta == null || !meta.containsKey(kProtocolRecordId)) return doc;
  return FamilyDoc(
    listId: doc.listId,
    collections: {
      ...doc.collections,
      Collections.meta: {...meta}..remove(kProtocolRecordId),
    },
  );
}

/// La marca es monótona en un móvil v2: si [before] era de v2 y [merged] ya
/// no lo dice (otro móvil la escribió con 1 o con algo que no es un número),
/// se vuelve a escribir 2 con el reloj de ahora, que gana por marca, y la
/// siguiente subida repara el común de todos. Una lápida de la marca no se
/// puede deshacer (los borrados son finales): se deja como está, y
/// [syncProtocolOf] la lee como 1, que un móvil v2 sigue aceptando.
FamilyDoc keepProtocolV2({
  required FamilyDoc before,
  required FamilyDoc merged,
  required HlcClock clock,
}) {
  if (syncProtocolOf(before) != kSyncProtocolV2 ||
      syncProtocolOf(merged) == kSyncProtocolV2) {
    return merged;
  }
  final mark = merged.record(Collections.meta, kProtocolRecordId);
  if (mark != null && mark.isDeleted) return merged;
  return merged.set(clock, Collections.meta, kProtocolRecordId, {
    kProtocolVersionField: kSyncProtocolV2,
  });
}

/// Si un documento que llega se puede fusionar en el de este móvil sin
/// degradar. Lo decide la identidad local, no la marca del documento propio
/// (que llega de los demás y se podría falsificar; hallazgo 14): un móvil en
/// v2 ([local] no nulo) solo acepta documentos de v2 por la sincronización
/// (los de v1, solo con [mergeLocalV1IntoV2], a propósito); uno que aún no
/// ha migrado acepta v1 y v2. Una versión desconocida no entra nunca.
bool acceptsProtocol({
  required SyncIdentityV2? local,
  required FamilyDoc incoming,
}) {
  final version = syncProtocolOf(incoming);
  if (version == null) return false;
  return local == null || version == kSyncProtocolV2;
}
