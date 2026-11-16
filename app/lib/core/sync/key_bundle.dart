// Paquetes de claves: una clave simétrica cifrada para la clave pública
// X25519 persistente de un móvil y firmada por quien la envía. Dart puro.
// Decisión: docs/adr/0004-yo-sorpresas-revocar.md (fases 1 y 2a).
//
// Formato (JSON, base64url sin relleno en los campos binarios):
//   {"v":3,"l":listId,"s":ámbito,"e":época,"from":emisor,"to":destinatario,
//    "fr":resumen de la ficha del emisor,"tr":resumen de la del destinatario,
//    "a":[móviles que conocen la clave, ordenados],
//    "epk":clave efímera X25519,"n":nonce(12),"c":texto cifrado+etiqueta(48),
//    "sig":firma Ed25519(64)}
//
// Cifrado (ECIES sobre X25519):
//   secreto = X25519(efímera del emisor, X25519 persistente del destinatario)
//   (rechazado si sale todo ceros: clave de orden bajo)
//   clave   = HKDF-SHA256(secreto, sal = epk ‖ pubDestinatario,
//                         info = "gift-huddle-key-bundle-v3", 32 bytes)
//   AES-256-GCM de los 32 bytes de la clave, con
//   AAD     = "gift-huddle-key-bundle-v3" ‖ 0x00 ‖ JSON canónico de
//             {a, e, fr, from, l, s, to, tr, v} ‖ epk ‖ pubDestinatario
// Firma: Ed25519 del emisor sobre AAD ‖ nonce ‖ texto cifrado.
//
// El paquete va ligado al estado del registro de móviles (requisito 5): cita
// la ficha del emisor y la del destinatario, y quien abre exige que las dos
// sean las actuales en su registro, que el emisor siga activo (un revocado
// resuelve a null) y que la época no sea mayor que la del registro. Un
// paquete de sorpresas, además, solo se cifra para, y solo se acepta de, un
// móvil con derecho a esas sorpresas (`RegistryView.entitled`).
//
// La audiencia (`a`) son los móviles que conocen la clave, firmada: solo se
// sella con una candidata cuya audiencia sigue entera con derecho, así que
// una clave repartida desde otro estado del registro con la misma época no
// llega a usarse si la conoce un revocado (hallazgo 7). En la fase 2b, antes
// de abrir paquetes se fusiona el registro de la instantánea.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:meta/meta.dart';

import 'access_policy.dart';
import 'device_keys.dart';
import 'device_registry.dart';
import 'envelope.dart' show FamilyKey, decodeBase64Url, encodeBase64Url;

const _domain = 'gift-huddle-key-bundle-v3';
const _version = 3;
const _nonceLength = 12;
const _macLength = 16;
const _keyLength = 32;
const _digestLength = 32;
const _v3FamilyClosed =
    'la vía v3 de la clave común está cerrada: va en paquetes v4';

/// Un paquete que no se puede crear o abrir.
class KeyBundleException implements Exception {
  /// Crea el error.
  const KeyBundleException(this.message);

  /// Qué pasó (sin claves).
  final String message;

  @override
  String toString() => 'KeyBundleException: $message';
}

/// Un paquete de claves sellado.
class KeyBundle {
  KeyBundle._({
    required this.listId,
    required this.scope,
    required this.epoch,
    required this.fromDevice,
    required this.toDevice,
    required this.senderRecord,
    required this.recipientRecord,
    required this.audience,
    required this.ephemeralPublicKey,
    required this.nonce,
    required this.ciphertext,
    required this.signature,
  });

  /// Lista.
  final String listId;

  /// Ámbito: [KeyScope.family] o [KeyScope.surprise].
  final String scope;

  /// Época de la clave.
  final int epoch;

  /// Móvil que la envía (firma).
  final String fromDevice;

  /// Móvil al que va.
  final String toDevice;

  /// Resumen de la ficha del emisor en el registro al sellar.
  final String senderRecord;

  /// Resumen de la ficha del destinatario en el registro al sellar.
  final String recipientRecord;

  /// Móviles que conocen la clave (con el emisor y el destinatario),
  /// ordenados.
  final List<String> audience;

  /// Clave pública X25519 efímera del emisor.
  final Uint8List ephemeralPublicKey;

  /// Nonce del GCM.
  final Uint8List nonce;

  /// Texto cifrado y etiqueta.
  final Uint8List ciphertext;

  /// Firma Ed25519 del emisor.
  final Uint8List signature;

  static final AesGcm _aes = AesGcm.with256bits();
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  /// Sella un paquete con todo dado a mano, sin mirar el registro: SOLO para
  /// pruebas (vectores fijos y paquetes falsificados). Repetir un nonce o una
  /// efímera rompe el cifrado.
  @visibleForTesting
  static Future<KeyBundle> sealForTesting({
    required DeviceKeys sender,
    required String fromDevice,
    required String toDevice,
    required String senderRecord,
    required String recipientRecord,
    required List<int> recipientAgreementKey,
    required String listId,
    required String scope,
    required int epoch,
    required List<int> key,
    List<String>? audience,
    List<int>? ephemeralSeed,
    List<int>? nonce,
  }) => _seal(
    sender: sender,
    fromDevice: fromDevice,
    toDevice: toDevice,
    senderRecord: senderRecord,
    recipientRecord: recipientRecord,
    recipientAgreementKey: recipientAgreementKey,
    listId: listId,
    scope: scope,
    epoch: epoch,
    key: key,
    audience: audience ?? [fromDevice, toDevice],
    ephemeralSeed: ephemeralSeed,
    nonce: nonce,
  );

  static Future<KeyBundle> _seal({
    required DeviceKeys sender,
    required String fromDevice,
    required String toDevice,
    required String senderRecord,
    required String recipientRecord,
    required List<int> recipientAgreementKey,
    required String listId,
    required String scope,
    required int epoch,
    required List<int> key,
    required Iterable<String> audience,
    List<int>? ephemeralSeed,
    List<int>? nonce,
  }) async {
    final sorted = audience.toSet().toList()..sort();
    _checkHeader(
      listId,
      scope,
      epoch,
      fromDevice,
      toDevice,
      senderRecord,
      recipientRecord,
      sorted,
    );
    if (key.length != _keyLength) {
      throw const KeyBundleException('la clave debe tener 32 bytes');
    }
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
    final aad = _aad(
      listId,
      scope,
      epoch,
      fromDevice,
      toDevice,
      senderRecord,
      recipientRecord,
      sorted,
      epk,
      recipientAgreementKey,
    );
    final box = await _aes.encrypt(
      key,
      secretKey: await _wrapKey(shared, epk, recipientAgreementKey),
      nonce: n,
      aad: aad,
    );
    final ciphertext = Uint8List.fromList([
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
    final signature = await sender.sign([...aad, ...n, ...ciphertext]);
    return KeyBundle._(
      listId: listId,
      scope: scope,
      epoch: epoch,
      fromDevice: fromDevice,
      toDevice: toDevice,
      senderRecord: senderRecord,
      recipientRecord: recipientRecord,
      audience: List.unmodifiable(sorted),
      ephemeralPublicKey: epk,
      nonce: Uint8List.fromList(n),
      ciphertext: ciphertext,
      signature: signature,
    );
  }

  /// Cifra la clave de sorpresas [key] para el móvil [toDevice].
  ///
  /// Lanza [KeyBundleException] si este móvil o el destinatario no tienen
  /// derecho a esas sorpresas según [view] (es de la persona protegida, no
  /// tiene persona, está revocado o pendiente, o nadie con derecho lo ha
  /// avalado), si la clave es de una época que el registro no ha abierto, o
  /// si su audiencia no incluye a los dos o tiene a alguien sin derecho
  /// (hallazgo 7).
  static Future<KeyBundle> sealSurpriseKey({
    required DeviceKeys sender,
    required RegistryView view,
    required String toDevice,
    required SurpriseKey key,
  }) {
    final recipient = view.entitled(toDevice, key.personId);
    if (!view.selfEntitled(key.personId) ||
        recipient == null ||
        toDevice == view.me ||
        key.epoch > view.epoch ||
        !key.audience.contains(view.me) ||
        !key.audience.contains(toDevice) ||
        !key.sealableFor(view.entitledDevices(key.personId).toSet())) {
      throw const KeyBundleException(
        'ese móvil no puede recibir esta clave de sorpresas',
      );
    }
    return _seal(
      sender: sender,
      fromDevice: view.me,
      toDevice: toDevice,
      senderRecord: view.self.recordDigest,
      recipientRecord: recipient.recordDigest,
      recipientAgreementKey: recipient.agreementKey,
      listId: view.listId,
      scope: KeyScope.surprise(key.personId),
      epoch: key.epoch,
      key: key.bytes,
      audience: key.audience,
    );
  }

  /// Los paquetes de [key] para todos los demás móviles con derecho.
  static Future<List<KeyBundle>> sealSurpriseKeyForAll({
    required DeviceKeys sender,
    required RegistryView view,
    required SurpriseKey key,
  }) async => [
    for (final device in view.entitledDevices(key.personId))
      if (device != view.me)
        await sealSurpriseKey(
          sender: sender,
          view: view,
          toDevice: device,
          key: key,
        ),
  ];

  /// Cifra la `familyKey` de la época [epoch] para otro móvil activo de la
  /// familia (rotación); su audiencia son los activos que ve este móvil.
  /// Lanza [KeyBundleException] si no lo es.
  ///
  /// Con [commonFormatV2] (el interruptor de la clave común por época de la
  /// familia, ADR 0005, B3) la vía v3 `scope: family` está cerrada: la
  /// clave común viaja en paquetes v4 (`FamilyKeyBundle`) y esto lanza
  /// [KeyBundleException].
  static Future<KeyBundle> sealFamilyKey({
    required DeviceKeys sender,
    required RegistryView view,
    required String toDevice,
    required int epoch,
    required FamilyKey familyKey,
    bool commonFormatV2 = false,
  }) {
    if (commonFormatV2) throw const KeyBundleException(_v3FamilyClosed);
    final recipient = view.member(toDevice);
    if (recipient == null ||
        view.self.kind == DeviceKind.web ||
        toDevice == view.me ||
        view.revokedByOthers ||
        epoch > view.epoch) {
      throw const KeyBundleException(
        'ese móvil no puede recibir la clave de la familia',
      );
    }
    return _seal(
      sender: sender,
      fromDevice: view.me,
      toDevice: toDevice,
      senderRecord: view.self.recordDigest,
      recipientRecord: recipient.recordDigest,
      recipientAgreementKey: recipient.agreementKey,
      listId: view.listId,
      scope: KeyScope.family,
      epoch: epoch,
      key: familyKey.bytes,
      audience: view.members,
    );
  }

  /// Abre un paquete de la `familyKey`. El emisor tiene que ser un móvil
  /// activo de la familia según [view]. Lanza [KeyBundleException] si el
  /// ámbito no es [KeyScope.family] o si algo falla (ver [_open]).
  /// Una web puede usar la vista de su raíz móvil fijada: el destinatario
  /// es [toDevice], activo en esa vista, con las claves de [mine]. Si la
  /// raíz tiene [RegistryView.revokedByOthers], debe escoger otra raíz.
  /// Con [commonFormatV2] la vía v3 está cerrada (ver [sealFamilyKey]).
  Future<FamilyKey> openFamilyKey({
    required DeviceKeys mine,
    required RegistryView view,
    bool commonFormatV2 = false,
  }) async {
    if (commonFormatV2) throw const KeyBundleException(_v3FamilyClosed);
    if (scope != KeyScope.family) {
      throw const KeyBundleException('no es un paquete de la familia');
    }
    final sender = view.member(fromDevice);
    final recipient = view.member(toDevice);
    if (sender == null ||
        sender.kind == DeviceKind.web ||
        recipient == null ||
        fromDevice == toDevice) {
      throw const KeyBundleException('el emisor no es de la familia');
    }
    if (toDevice != view.me &&
        (recipient.kind != DeviceKind.web ||
            view.self.kind != DeviceKind.mobile ||
            view.revokedByOthers)) {
      throw const KeyBundleException('el paquete es para otro móvil');
    }
    return FamilyKey(
      await _open(mine: mine, view: view, sender: sender, recipient: recipient),
    );
  }

  /// Abre el paquete con las claves de este móvil.
  ///
  /// Comprueba, por este orden: que va a este móvil y es de su lista, que la
  /// época no es mayor que la del registro, que las fichas citadas son las
  /// actuales del emisor y de este móvil, la firma con la clave del emisor
  /// que da el registro, el secreto X25519 y el GCM. Devuelve los 32 bytes
  /// de la clave. Lanza [KeyBundleException] si algo falla.
  Future<Uint8List> _open({
    required DeviceKeys mine,
    required RegistryView view,
    required KnownDevice sender,
    KnownDevice? recipient,
  }) async {
    final target = recipient ?? view.self;
    if (sender.kind == DeviceKind.web) {
      throw const KeyBundleException('una web no puede emitir claves');
    }
    if (toDevice != target.deviceId) {
      throw const KeyBundleException('el paquete es para otro móvil');
    }
    if (listId != view.listId) {
      throw const KeyBundleException('el paquete es de otra lista');
    }
    if (epoch > view.epoch) {
      throw const KeyBundleException(
        'el paquete es de una época que el registro no ha abierto',
      );
    }
    if (senderRecord != sender.recordDigest ||
        recipientRecord != target.recordDigest) {
      throw const KeyBundleException(
        'el paquete es de otro estado del registro',
      );
    }
    final myPublic = mine.publicKeys.agreement;
    if (!constantTimeEquals(myPublic, target.agreementKey)) {
      throw const KeyBundleException('las claves no son las de la ficha');
    }
    final aad = _aad(
      listId,
      scope,
      epoch,
      fromDevice,
      toDevice,
      senderRecord,
      recipientRecord,
      audience,
      ephemeralPublicKey,
      myPublic,
    );
    final signed = await verifyDeviceSignature(
      message: [...aad, ...nonce, ...ciphertext],
      signature: signature,
      signingPublicKey: sender.signingKey,
    );
    if (!signed) {
      throw const KeyBundleException('firma no válida');
    }
    final SecretKey shared;
    try {
      shared = await mine.agree(ephemeralPublicKey);
    } on DeviceKeyException {
      throw const KeyBundleException('clave efímera no válida');
    }
    try {
      final plain = await _aes.decrypt(
        SecretBox(
          ciphertext.sublist(0, ciphertext.length - _macLength),
          nonce: nonce,
          mac: Mac(ciphertext.sublist(ciphertext.length - _macLength)),
        ),
        secretKey: await _wrapKey(shared, ephemeralPublicKey, myPublic),
        aad: aad,
      );
      if (plain.length != _keyLength) {
        throw const KeyBundleException('paquete no válido');
      }
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw const KeyBundleException('el paquete no se puede abrir');
    }
  }

  /// Abre un paquete de sorpresas y devuelve la clave.
  ///
  /// El emisor y este móvil tienen que tener derecho a esas sorpresas según
  /// [view]: la persona protegida podría mandar una clave que conoce para
  /// leer o falsificar el bloque (A1), y un móvil suyo registrado como de
  /// otra persona no tiene derecho mientras no lo avale alguien que sí (M6).
  Future<SurpriseKey> openSurpriseKey({
    required DeviceKeys mine,
    required RegistryView view,
  }) async {
    final person = KeyScope.personOf(scope);
    if (person == null) {
      throw const KeyBundleException('no es un paquete de sorpresas');
    }
    final sender = view.entitled(fromDevice, person);
    if (sender == null || fromDevice == view.me || !view.selfEntitled(person)) {
      throw const KeyBundleException(
        'esta clave de sorpresas no se puede aceptar',
      );
    }
    final bytes = await _open(mine: mine, view: view, sender: sender);
    return SurpriseKey(
      personId: person,
      epoch: epoch,
      bytes: bytes,
      audience: audience,
    );
  }

  /// El paquete en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'v': _version,
    'l': listId,
    's': scope,
    'e': epoch,
    'from': fromDevice,
    'to': toDevice,
    'fr': senderRecord,
    'tr': recipientRecord,
    'a': audience,
    'epk': encodeBase64Url(ephemeralPublicKey),
    'n': encodeBase64Url(nonce),
    'c': encodeBase64Url(ciphertext),
    'sig': encodeBase64Url(signature),
  };

  /// Lee [toJson]. Lanza [KeyBundleException] si no vale. No autentica: eso
  /// lo hacen [openSurpriseKey] y [openFamilyKey].
  factory KeyBundle.fromJson(Map<String, Object?> json) {
    if (json['v'] != _version) {
      throw const KeyBundleException('versión no soportada');
    }
    final l = json['l'];
    final s = json['s'];
    final e = json['e'];
    final from = json['from'];
    final to = json['to'];
    final fr = json['fr'];
    final tr = json['tr'];
    final a = json['a'];
    if (l is! String ||
        s is! String ||
        e is! int ||
        from is! String ||
        to is! String ||
        fr is! String ||
        tr is! String ||
        a is! List ||
        a.length > kMaxKeyAudience ||
        !a.every((x) => x is String)) {
      throw const KeyBundleException('paquete no válido');
    }
    final audience = a.cast<String>();
    _checkHeader(l, s, e, from, to, fr, tr, audience);
    try {
      final epk = decodeBase64Url(json['epk'] as String);
      final n = decodeBase64Url(json['n'] as String);
      final c = decodeBase64Url(json['c'] as String);
      final sig = decodeBase64Url(json['sig'] as String);
      if (epk.length != 32 ||
          n.length != _nonceLength ||
          c.length != _keyLength + _macLength ||
          sig.length != 64) {
        throw const KeyBundleException('paquete no válido');
      }
      return KeyBundle._(
        listId: l,
        scope: s,
        epoch: e,
        fromDevice: from,
        toDevice: to,
        senderRecord: fr,
        recipientRecord: tr,
        audience: List.unmodifiable(audience),
        ephemeralPublicKey: epk,
        nonce: n,
        ciphertext: c,
        signature: sig,
      );
    } on KeyBundleException {
      rethrow;
    } catch (_) {
      throw const KeyBundleException('paquete no válido');
    }
  }

  /// Copia con otros campos, SOLO para pruebas de manipulación.
  @visibleForTesting
  KeyBundle copyForTesting({
    String? scope,
    int? epoch,
    String? fromDevice,
    String? toDevice,
    String? senderRecord,
    String? recipientRecord,
    List<String>? audience,
    List<int>? ephemeralPublicKey,
    List<int>? ciphertext,
    List<int>? signature,
  }) => KeyBundle._(
    listId: listId,
    scope: scope ?? this.scope,
    epoch: epoch ?? this.epoch,
    fromDevice: fromDevice ?? this.fromDevice,
    toDevice: toDevice ?? this.toDevice,
    senderRecord: senderRecord ?? this.senderRecord,
    recipientRecord: recipientRecord ?? this.recipientRecord,
    audience: audience ?? this.audience,
    ephemeralPublicKey: Uint8List.fromList(
      ephemeralPublicKey ?? this.ephemeralPublicKey,
    ),
    nonce: nonce,
    ciphertext: Uint8List.fromList(ciphertext ?? this.ciphertext),
    signature: Uint8List.fromList(signature ?? this.signature),
  );

  static Future<SecretKey> _wrapKey(
    SecretKey shared,
    List<int> epk,
    List<int> recipientPublic,
  ) => _hkdf.deriveKey(
    secretKey: shared,
    nonce: [...epk, ...recipientPublic],
    info: utf8.encode(_domain),
  );

  static List<int> _aad(
    String listId,
    String scope,
    int epoch,
    String from,
    String to,
    String senderRecord,
    String recipientRecord,
    List<String> audience,
    List<int> epk,
    List<int> recipientPublic,
  ) => [
    ...utf8.encode(_domain),
    0,
    ...canonicalHeaderBytes(<String, Object?>{
      'a': audience,
      'e': epoch,
      'fr': senderRecord,
      'from': from,
      'l': listId,
      's': scope,
      'to': to,
      'tr': recipientRecord,
      'v': _version,
    }),
    ...epk,
    ...recipientPublic,
  ];

  static void _checkHeader(
    String listId,
    String scope,
    int epoch,
    String from,
    String to,
    String senderRecord,
    String recipientRecord,
    List<String> audience,
  ) {
    var sorted = true;
    for (var i = 1; i < audience.length; i++) {
      if (audience[i - 1].compareTo(audience[i]) >= 0) sorted = false;
    }
    if (!kSyncIdPattern.hasMatch(listId) ||
        !kSyncIdPattern.hasMatch(from) ||
        !kSyncIdPattern.hasMatch(to) ||
        !KeyScope.isValid(scope) ||
        !_isDigest(senderRecord) ||
        !_isDigest(recipientRecord) ||
        epoch < 1 ||
        epoch > 0xFFFFFFFF ||
        !sorted ||
        audience.length > kMaxKeyAudience ||
        !audience.every(kSyncIdPattern.hasMatch) ||
        !audience.contains(from) ||
        !audience.contains(to)) {
      throw const KeyBundleException('cabecera del paquete no válida');
    }
  }

  static bool _isDigest(String text) {
    try {
      return decodeBase64Url(text).length == _digestLength;
    } on FormatException {
      return false;
    }
  }
}
