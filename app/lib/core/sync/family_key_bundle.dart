// Paquetes de la clave común, formato v4 (`scope: family`). Dart puro.
// Decisión: docs/adr/0005-rotacion-clave-comun.md (lote B1, sección 3 y
// «Decisiones de B1»). Los paquetes v3 (sorpresas) siguen en key_bundle.dart,
// sin cambios.
//
// Formato (JSON, base64url canónico sin relleno en los campos binarios;
// exactamente estas claves, ni una más):
//   {"v":4,"l":lista,"sid":generación,"s":"family","e":época,
//    "ctx":contexto de la época,"kid":kid de la candidata,
//    "c":creador,"cr":resumen de la ficha del creador,
//    "cs":firma del creador(64),
//    "from":emisor,"fr":resumen de su ficha,"to":destinatario,"tr":el suyo,
//    "a":[[móvil, resumen de su ficha], ...] (audiencia, por id),
//    "epk":efímera X25519,"n":nonce(12),"ct":texto cifrado+etiqueta(48),
//    "sig":firma Ed25519 del emisor(64)}
//
// Cifrado (el mismo ECIES que v3, con otro dominio):
//   secreto = X25519(efímera, X25519 persistente del destinatario)
//             (rechazado si sale todo ceros: clave de orden bajo)
//   clave   = HKDF-SHA256(secreto, sal = epk ‖ pubDestinatario,
//                         info = "gift-huddle-key-bundle-v4", 32 bytes)
//   AES-256-GCM de los 32 bytes del secreto de la candidata, con
//   AAD = "gift-huddle-key-bundle-v4" ‖ 0x00 ‖ JSON canónico de
//         {a, c, cr, cs, ctx, e, fr, from, kid, l, s, sid, to, tr, v} ‖
//         epk ‖ pubDestinatario
// Firma del emisor: Ed25519 sobre AAD ‖ nonce ‖ texto cifrado ‖ etiqueta.
// Firma del creador (dentro del AAD): ver family_candidate.dart.
//
// Quien abre exige: lista y generación; que va a él (o a su web, con la
// vista de la raíz); emisor móvil activo con su ficha actual, y la del
// destinatario; que cada par (móvil, ficha) de la audiencia existe en el
// registro y la ficha del creador es de un móvil del registro con firma
// válida (M2, M3); la firma del emisor; X25519 sin orden bajo; GCM; secreto
// no nulo, y que el `kid` recalculado coincide.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:meta/meta.dart';

import 'access_policy.dart' show KeyScope, kMaxKeyAudience;
import 'device_keys.dart';
import 'device_registry.dart';
import 'envelope.dart' show encodeBase64Url;
import 'family_candidate.dart';
import 'key_bundle.dart' show KeyBundleException;

/// Versión del formato de los paquetes de la clave común.
const int kFamilyKeyBundleVersion = 4;

const _domain = 'gift-huddle-key-bundle-v4';
const _nonceLength = 12;
const _macLength = 16;
const _keyLength = 32;
const _jsonKeys = {
  'v',
  'l',
  'sid',
  's',
  'e',
  'ctx',
  'kid',
  'c',
  'cr',
  'cs',
  'from',
  'fr',
  'to',
  'tr',
  'a',
  'epk',
  'n',
  'ct',
  'sig',
};

/// Un paquete v4 de la clave común sellado.
class FamilyKeyBundle {
  FamilyKeyBundle._({
    required this.listId,
    required this.syncId,
    required this.epochNumber,
    required this.epochContext,
    required this.kid,
    required this.creator,
    required this.creatorRecord,
    required this.creatorSignature,
    required this.fromDevice,
    required this.senderRecord,
    required this.toDevice,
    required this.recipientRecord,
    required this.audience,
    required this.ephemeralPublicKey,
    required this.nonce,
    required this.ciphertext,
    required this.signature,
  });

  /// Lista.
  final String listId;

  /// Generación v2.
  final String syncId;

  /// Ámbito: siempre [KeyScope.family].
  String get scope => KeyScope.family;

  /// Época de la candidata (descriptiva).
  final int epochNumber;

  /// Contexto de la época de la candidata.
  final String epochContext;

  /// `kid` de la candidata.
  final String kid;

  /// Móvil que creó la candidata.
  final String creator;

  /// Resumen de la ficha del creador.
  final String creatorRecord;

  /// Firma del creador sobre la candidata.
  final Uint8List creatorSignature;

  /// Móvil que envía el paquete (firma).
  final String fromDevice;

  /// Resumen de la ficha del emisor al sellar.
  final String senderRecord;

  /// Dispositivo al que va.
  final String toDevice;

  /// Resumen de la ficha del destinatario al sellar.
  final String recipientRecord;

  /// Audiencia de la candidata, ordenada por id.
  final List<AudienceMember> audience;

  /// Clave pública X25519 efímera.
  final Uint8List ephemeralPublicKey;

  /// Nonce del GCM.
  final Uint8List nonce;

  /// Texto cifrado y etiqueta.
  final Uint8List ciphertext;

  /// Firma Ed25519 del emisor.
  final Uint8List signature;

  static final AesGcm _aes = AesGcm.with256bits();
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  /// Sella [candidate] para [toDevice], desde este móvil según [view].
  ///
  /// Solo reparte un móvil (no una web) activo, aprobado y no revocado que
  /// esté en la audiencia con su ficha actual y firme con sus claves, y solo
  /// a otro activo que también esté en ella con su ficha actual. Una
  /// candidata nunca amplía su audiencia: para incluir a alguien se crea
  /// otra. Lanza [KeyBundleException] si algo no cuadra.
  static Future<FamilyKeyBundle> seal({
    required DeviceKeys sender,
    required RegistryView view,
    required String syncId,
    required String toDevice,
    required FamilyCandidate candidate,
  }) async {
    final recipient = view.member(toDevice);
    final mine = candidate.audienceOf(view.me);
    final theirs = candidate.audienceOf(toDevice);
    if (view.self.kind != DeviceKind.mobile ||
        view.revokedByOthers ||
        !view.selfApproved ||
        candidate.listId != view.listId ||
        candidate.syncId != syncId ||
        toDevice == view.me ||
        recipient == null ||
        mine == null ||
        mine.recordDigest != view.self.recordDigest ||
        theirs == null ||
        theirs.recordDigest != recipient.recordDigest ||
        !constantTimeEquals(sender.publicKeys.signing, view.self.signingKey)) {
      throw const KeyBundleException(
        'ese dispositivo no puede recibir esta clave común',
      );
    }
    return _seal(
      sender: sender,
      candidate: candidate,
      fromDevice: view.me,
      senderRecord: view.self.recordDigest,
      toDevice: toDevice,
      recipientRecord: recipient.recordDigest,
      recipientAgreementKey: recipient.agreementKey,
    );
  }

  /// Los paquetes de [candidate] para todos los demás de su audiencia que
  /// siguen activos con la misma ficha según [view].
  static Future<List<FamilyKeyBundle>> sealForAudience({
    required DeviceKeys sender,
    required RegistryView view,
    required String syncId,
    required FamilyCandidate candidate,
  }) async => [
    for (final m in candidate.audience)
      if (m.deviceId != view.me &&
          view.member(m.deviceId)?.recordDigest == m.recordDigest)
        await seal(
          sender: sender,
          view: view,
          syncId: syncId,
          toDevice: m.deviceId,
          candidate: candidate,
        ),
  ];

  /// Sella con todo dado a mano, sin mirar el registro: SOLO para pruebas
  /// (vectores fijos y paquetes falsificados). Repetir un nonce o una
  /// efímera rompe el cifrado.
  @visibleForTesting
  static Future<FamilyKeyBundle> sealForTesting({
    required DeviceKeys sender,
    required FamilyCandidate candidate,
    required String fromDevice,
    required String senderRecord,
    required String toDevice,
    required String recipientRecord,
    required List<int> recipientAgreementKey,
    List<int>? ephemeralSeed,
    List<int>? nonce,
    List<int>? secretForTesting,
  }) => _seal(
    sender: sender,
    candidate: candidate,
    fromDevice: fromDevice,
    senderRecord: senderRecord,
    toDevice: toDevice,
    recipientRecord: recipientRecord,
    recipientAgreementKey: recipientAgreementKey,
    ephemeralSeed: ephemeralSeed,
    nonce: nonce,
    secret: secretForTesting,
  );

  static Future<FamilyKeyBundle> _seal({
    required DeviceKeys sender,
    required FamilyCandidate candidate,
    required String fromDevice,
    required String senderRecord,
    required String toDevice,
    required String recipientRecord,
    required List<int> recipientAgreementKey,
    List<int>? ephemeralSeed,
    List<int>? nonce,
    List<int>? secret,
  }) async {
    final header = _Header(
      listId: candidate.listId,
      syncId: candidate.syncId,
      epochNumber: candidate.epochNumber,
      epochContext: candidate.epochContext,
      kid: candidate.kid,
      creator: candidate.creator,
      creatorRecord: candidate.creatorRecord,
      creatorSignature: candidate.creatorSignature,
      fromDevice: fromDevice,
      senderRecord: senderRecord,
      toDevice: toDevice,
      recipientRecord: recipientRecord,
      audience: candidate.audience,
    )..check();
    final n = nonce ?? secureRandomBytes(_nonceLength);
    if (n.length != _nonceLength) {
      throw const KeyBundleException('nonce no válido');
    }
    final ephemeral = await X25519().newKeyPairFromSeed(
      ephemeralSeed ?? secureRandomBytes(32),
    );
    final epk = Uint8List.fromList((await ephemeral.extractPublicKey()).bytes);
    final SecretKey shared;
    try {
      shared = await x25519Agree(ephemeral, recipientAgreementKey);
    } on DeviceKeyException {
      throw const KeyBundleException(
        'clave pública del destinatario no válida',
      );
    }
    final aad = header.aad(epk, recipientAgreementKey);
    final box = await _aes.encrypt(
      secret ?? candidate.secret,
      secretKey: await _wrapKey(shared, epk, recipientAgreementKey),
      nonce: n,
      aad: aad,
    );
    final ciphertext = Uint8List.fromList([
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
    final signature = await sender.sign([...aad, ...n, ...ciphertext]);
    return header.bundle(epk, Uint8List.fromList(n), ciphertext, signature);
  }

  /// Abre el paquete y devuelve la candidata.
  ///
  /// [registry] es el registro verificado del que sale [view]: con él se
  /// comprueba que cada par (móvil, ficha) de la audiencia existe y que la
  /// ficha del creador es de un móvil, con la clave del nodo enlazado desde
  /// el ancla de [view] para ese id ([RegistryView.linkedSigningKey]: vale
  /// también un revocado al que se llega) y con cuya clave vale la firma
  /// del creador. No decide si la candidata sirve para sellar: eso es
  /// [FamilyKeyring.forSealingIn]. Lanza [KeyBundleException] si algo falla.
  Future<FamilyCandidate> open({
    required DeviceKeys mine,
    required RegistryView view,
    required DeviceRegistry registry,
    required String syncId,
  }) async {
    final header = _Header.of(this)..check();
    if (listId != view.listId ||
        registry.listId != view.listId ||
        this.syncId != syncId) {
      throw const KeyBundleException('el paquete es de otra lista');
    }
    final sender = view.member(fromDevice);
    final recipient = view.member(toDevice);
    if (sender == null ||
        sender.kind != DeviceKind.mobile ||
        recipient == null ||
        fromDevice == toDevice) {
      throw const KeyBundleException('el emisor no es de la familia');
    }
    if (toDevice != view.me &&
        (recipient.kind != DeviceKind.web ||
            view.self.kind != DeviceKind.mobile ||
            view.revokedByOthers)) {
      throw const KeyBundleException('el paquete es para otro dispositivo');
    }
    if (senderRecord != sender.recordDigest ||
        recipientRecord != recipient.recordDigest) {
      throw const KeyBundleException(
        'el paquete es de otro estado del registro',
      );
    }
    final myPublic = mine.publicKeys.agreement;
    if (!constantTimeEquals(myPublic, recipient.agreementKey)) {
      throw const KeyBundleException('las claves no son las de la ficha');
    }
    for (final m in audience) {
      if (registry.recordByDigest(m.recordDigest)?.deviceId != m.deviceId) {
        throw const KeyBundleException(
          'la audiencia tiene fichas que el registro no conoce',
        );
      }
    }
    // El creador tiene que ser el móvil enlazado desde el ancla de [view]
    // con ese id: la ficha `cr` tiene que existir, ser de un móvil y llevar
    // la misma clave de firma que el nodo enlazado. Una ficha autofirmada
    // sin aval (otro id, o el de un miembro con otras claves) no sirve (R1).
    final creatorFicha = registry.recordByDigest(creatorRecord);
    final linkedKey = view.linkedSigningKey(creator);
    if (creatorFicha == null ||
        creatorFicha.deviceId != creator ||
        creatorFicha.kind != DeviceKind.mobile ||
        linkedKey == null ||
        !constantTimeEquals(linkedKey, creatorFicha.keys.signing)) {
      throw const KeyBundleException('el creador no es un móvil del registro');
    }
    final aad = header.aad(ephemeralPublicKey, myPublic);
    final signed = await verifyDeviceSignature(
      message: [...aad, ...nonce, ...ciphertext],
      signature: signature,
      signingPublicKey: sender.signingKey,
    );
    if (!signed) throw const KeyBundleException('firma no válida');
    final SecretKey shared;
    try {
      shared = await mine.agree(ephemeralPublicKey);
    } on DeviceKeyException {
      throw const KeyBundleException('clave efímera no válida');
    }
    final List<int> plain;
    try {
      plain = await _aes.decrypt(
        SecretBox(
          ciphertext.sublist(0, ciphertext.length - _macLength),
          nonce: nonce,
          mac: Mac(ciphertext.sublist(ciphertext.length - _macLength)),
        ),
        secretKey: await _wrapKey(shared, ephemeralPublicKey, myPublic),
        aad: aad,
      );
    } on SecretBoxAuthenticationError {
      throw const KeyBundleException('el paquete no se puede abrir');
    }
    final FamilyCandidate candidate;
    try {
      candidate = FamilyCandidate.signed(
        listId: listId,
        syncId: this.syncId,
        epochNumber: epochNumber,
        epochContext: epochContext,
        creator: creator,
        creatorRecord: creatorRecord,
        audience: audience,
        secret: plain,
        creatorSignature: creatorSignature,
      );
    } on FamilyKeyException {
      throw const KeyBundleException('secreto no válido');
    }
    if (!constantTimeEquals(utf8.encode(candidate.kid), utf8.encode(kid))) {
      throw const KeyBundleException('el kid no es el de la clave');
    }
    if (!await candidate.verifyCreator(creatorFicha.keys.signing)) {
      throw const KeyBundleException('firma del creador no válida');
    }
    return candidate;
  }

  /// El paquete en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'v': kFamilyKeyBundleVersion,
    'l': listId,
    'sid': syncId,
    's': scope,
    'e': epochNumber,
    'ctx': epochContext,
    'kid': kid,
    'c': creator,
    'cr': creatorRecord,
    'cs': encodeBase64Url(creatorSignature),
    'from': fromDevice,
    'fr': senderRecord,
    'to': toDevice,
    'tr': recipientRecord,
    'a': [for (final m in audience) m.toJson()],
    'epk': encodeBase64Url(ephemeralPublicKey),
    'n': encodeBase64Url(nonce),
    'ct': encodeBase64Url(ciphertext),
    'sig': encodeBase64Url(signature),
  };

  /// Si [json] dice ser un paquete v4 (para separarlo de los v3).
  static bool isV4(Object? json) =>
      json is Map && json['v'] == kFamilyKeyBundleVersion;

  /// Lee [toJson]. Lanza [KeyBundleException] si no vale (también con
  /// claves de más o de menos). No autentica: eso lo hace [open].
  factory FamilyKeyBundle.fromJson(Map<String, Object?> json) {
    if (json['v'] != kFamilyKeyBundleVersion) {
      throw const KeyBundleException('versión no soportada');
    }
    if (json['s'] != KeyScope.family) {
      throw const KeyBundleException('no es un paquete de la clave común');
    }
    if (json.length != _jsonKeys.length ||
        !json.keys.every(_jsonKeys.contains)) {
      throw const KeyBundleException('paquete con campos desconocidos');
    }
    final l = json['l'];
    final sid = json['sid'];
    final e = json['e'];
    final ctx = json['ctx'];
    final kid = json['kid'];
    final c = json['c'];
    final cr = json['cr'];
    final from = json['from'];
    final fr = json['fr'];
    final to = json['to'];
    final tr = json['tr'];
    final a = json['a'];
    if (l is! String ||
        sid is! String ||
        !isJsonInt(e, min: 1, max: 0xFFFFFFFF) ||
        ctx is! String ||
        kid is! String ||
        c is! String ||
        cr is! String ||
        from is! String ||
        fr is! String ||
        to is! String ||
        tr is! String ||
        a is! List ||
        a.length > kMaxKeyAudience) {
      throw const KeyBundleException('paquete no válido');
    }
    Uint8List bin(String key, int length) {
      final value = json[key];
      final bytes = value is String
          ? decodeCanonicalBase64Url(value, length: length)
          : null;
      if (bytes == null) throw const KeyBundleException('paquete no válido');
      return bytes;
    }

    final epk = bin('epk', 32);
    final n = bin('n', _nonceLength);
    final ct = bin('ct', _keyLength + _macLength);
    final sig = bin('sig', 64);
    final cs = bin('cs', 64);
    final List<AudienceMember> members;
    try {
      members = audienceFromJson(a);
    } on FamilyKeyException {
      throw const KeyBundleException('cabecera del paquete no válida');
    }
    final header = _Header(
      listId: l,
      syncId: sid,
      epochNumber: e! as int,
      epochContext: ctx,
      kid: kid,
      creator: c,
      creatorRecord: cr,
      creatorSignature: cs,
      fromDevice: from,
      senderRecord: fr,
      toDevice: to,
      recipientRecord: tr,
      audience: members,
    )..check();
    return header.bundle(epk, n, ct, sig);
  }

  /// Copia con otros campos, SOLO para pruebas de manipulación (no
  /// comprueba nada).
  @visibleForTesting
  FamilyKeyBundle copyForTesting({
    String? listId,
    String? syncId,
    int? epochNumber,
    String? epochContext,
    String? kid,
    String? creator,
    String? creatorRecord,
    List<int>? creatorSignature,
    String? fromDevice,
    String? senderRecord,
    String? toDevice,
    String? recipientRecord,
    List<AudienceMember>? audience,
    List<int>? ephemeralPublicKey,
    List<int>? nonce,
    List<int>? ciphertext,
    List<int>? signature,
  }) => FamilyKeyBundle._(
    listId: listId ?? this.listId,
    syncId: syncId ?? this.syncId,
    epochNumber: epochNumber ?? this.epochNumber,
    epochContext: epochContext ?? this.epochContext,
    kid: kid ?? this.kid,
    creator: creator ?? this.creator,
    creatorRecord: creatorRecord ?? this.creatorRecord,
    creatorSignature: Uint8List.fromList(
      creatorSignature ?? this.creatorSignature,
    ),
    fromDevice: fromDevice ?? this.fromDevice,
    senderRecord: senderRecord ?? this.senderRecord,
    toDevice: toDevice ?? this.toDevice,
    recipientRecord: recipientRecord ?? this.recipientRecord,
    audience: audience ?? this.audience,
    ephemeralPublicKey: Uint8List.fromList(
      ephemeralPublicKey ?? this.ephemeralPublicKey,
    ),
    nonce: Uint8List.fromList(nonce ?? this.nonce),
    ciphertext: Uint8List.fromList(ciphertext ?? this.ciphertext),
    signature: Uint8List.fromList(signature ?? this.signature),
  );

  /// Vuelve a firmar el paquete tal como está (cabecera ya manipulada), SOLO
  /// para pruebas: como emisor con [sender] y, si se da, como creador con
  /// [creator]. Así una manipulación llega hasta el AAD del GCM.
  @visibleForTesting
  Future<FamilyKeyBundle> resignForTesting({
    required DeviceKeys sender,
    required List<int> recipientAgreementKey,
    DeviceKeys? creator,
  }) async {
    final cs = creator == null
        ? creatorSignature
        : await creator.sign(
            familyCandidateStatement(
              listId: listId,
              syncId: syncId,
              epochNumber: epochNumber,
              epochContext: epochContext,
              creator: this.creator,
              creatorRecord: creatorRecord,
              audience: audience,
              kid: kid,
            ),
          );
    final header = _Header.of(copyForTesting(creatorSignature: cs));
    final aad = header.aad(ephemeralPublicKey, recipientAgreementKey);
    final sig = await sender.sign([...aad, ...nonce, ...ciphertext]);
    return header.bundle(ephemeralPublicKey, nonce, ciphertext, sig);
  }

  /// Si la firma del emisor vale con [senderSigningKey] (la de la ficha
  /// `fr`) para el destinatario con [recipientAgreementKey] (la de `tr`),
  /// sin abrir nada: sirve para no volver a subir paquetes ajenos que nadie
  /// puede abrir (ADR 0005, B3). No dice si el destinatario lo abrirá.
  Future<bool> verifySender({
    required List<int> senderSigningKey,
    required List<int> recipientAgreementKey,
  }) async {
    try {
      final aad = (_Header.of(
        this,
      )..check()).aad(ephemeralPublicKey, recipientAgreementKey);
      return await verifyDeviceSignature(
        message: [...aad, ...nonce, ...ciphertext],
        signature: signature,
        signingPublicKey: senderSigningKey,
      );
    } on KeyBundleException {
      return false;
    } on DeviceKeyException {
      return false;
    }
  }

  static Future<SecretKey> _wrapKey(
    SecretKey shared,
    List<int> epk,
    List<int> recipientPublic,
  ) => _hkdf.deriveKey(
    secretKey: shared,
    nonce: [...epk, ...recipientPublic],
    info: utf8.encode(_domain),
  );
}

class _Header {
  _Header({
    required this.listId,
    required this.syncId,
    required this.epochNumber,
    required this.epochContext,
    required this.kid,
    required this.creator,
    required this.creatorRecord,
    required this.creatorSignature,
    required this.fromDevice,
    required this.senderRecord,
    required this.toDevice,
    required this.recipientRecord,
    required this.audience,
  });

  factory _Header.of(FamilyKeyBundle b) => _Header(
    listId: b.listId,
    syncId: b.syncId,
    epochNumber: b.epochNumber,
    epochContext: b.epochContext,
    kid: b.kid,
    creator: b.creator,
    creatorRecord: b.creatorRecord,
    creatorSignature: b.creatorSignature,
    fromDevice: b.fromDevice,
    senderRecord: b.senderRecord,
    toDevice: b.toDevice,
    recipientRecord: b.recipientRecord,
    audience: b.audience,
  );

  final String listId;
  final String syncId;
  final int epochNumber;
  final String epochContext;
  final String kid;
  final String creator;
  final String creatorRecord;
  final Uint8List creatorSignature;
  final String fromDevice;
  final String senderRecord;
  final String toDevice;
  final String recipientRecord;
  final List<AudienceMember> audience;

  /// Lanza [KeyBundleException] si la cabecera no vale: campos, audiencia
  /// canónica y emisor, destinatario y creador en ella con sus fichas.
  void check() {
    try {
      final sorted = canonicalAudience(audience);
      for (var i = 0; i < sorted.length; i++) {
        if (sorted[i] != audience[i]) {
          throw const FamilyKeyException('orden');
        }
      }
      checkFamilyKeyHeader(
        listId: listId,
        syncId: syncId,
        epochNumber: epochNumber,
        epochContext: epochContext,
        creator: creator,
        creatorRecord: creatorRecord,
        audience: audience,
      );
    } on FamilyKeyException {
      throw const KeyBundleException('cabecera del paquete no válida');
    }
    bool listed(String id, String digest) =>
        audience.any((m) => m.deviceId == id && m.recordDigest == digest);
    if (!isFamilyHash(kid) ||
        creatorSignature.length != 64 ||
        !kSyncIdPattern.hasMatch(fromDevice) ||
        !kSyncIdPattern.hasMatch(toDevice) ||
        fromDevice == toDevice ||
        !listed(fromDevice, senderRecord) ||
        !listed(toDevice, recipientRecord)) {
      throw const KeyBundleException('cabecera del paquete no válida');
    }
  }

  List<int> headerBytes() => canonicalHeaderBytes(<String, Object?>{
    'a': [for (final m in audience) m.toJson()],
    'c': creator,
    'cr': creatorRecord,
    'cs': encodeBase64Url(creatorSignature),
    'ctx': epochContext,
    'e': epochNumber,
    'fr': senderRecord,
    'from': fromDevice,
    'kid': kid,
    'l': listId,
    's': KeyScope.family,
    'sid': syncId,
    'to': toDevice,
    'tr': recipientRecord,
    'v': kFamilyKeyBundleVersion,
  });

  List<int> aad(List<int> epk, List<int> recipientPublic) => [
    ...utf8.encode(_domain),
    0,
    ...headerBytes(),
    ...epk,
    ...recipientPublic,
  ];

  FamilyKeyBundle bundle(
    Uint8List epk,
    Uint8List nonce,
    Uint8List ciphertext,
    Uint8List signature,
  ) => FamilyKeyBundle._(
    listId: listId,
    syncId: syncId,
    epochNumber: epochNumber,
    epochContext: epochContext,
    kid: kid,
    creator: creator,
    creatorRecord: creatorRecord,
    creatorSignature: Uint8List.fromList(creatorSignature),
    fromDevice: fromDevice,
    senderRecord: senderRecord,
    toDevice: toDevice,
    recipientRecord: recipientRecord,
    audience: List.unmodifiable(audience),
    ephemeralPublicKey: epk,
    nonce: nonce,
    ciphertext: ciphertext,
    signature: signature,
  );
}
