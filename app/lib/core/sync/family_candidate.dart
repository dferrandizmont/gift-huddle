// Clave común por época: candidatas con audiencia inmutable y firma del
// creador, contexto de época y llavero común. Dart puro (sin Flutter).
// Decisión: docs/adr/0005-rotacion-clave-comun.md (lote B1, sección 3 y
// «Decisiones de B1»).
//
// - **Contexto de época** (`epochContext`): SHA-256 en hexadecimal de
//     "gift-huddle-epoch-context-v2" ‖ 0x00 ‖ JSON canónico de
//     {"l": lista, "m": [[móvil, resumen de su ficha], ...] (activos, por
//      id), "r": [revocados o ambiguos, por id], "sid": generación, "v": 2}
//   Sale solo de la vista verificada del registro ([RegistryView]). No
//   lleva el número de época: ese número suma el `seq` de revocados y
//   pendientes, que pueden publicar fichas nuevas sin que cambie quién
//   recibe la clave (revisión de seguridad, M1). Cada móvil lo recalcula desde
//   su vista; nunca lo acepta porque venga firmado.
// - **Candidata** ([FamilyCandidate]): un secreto aleatorio de 32 bytes con
//   su lista, generación, número de época (descriptivo), contexto, creador,
//   audiencia (los móviles que la conocen, con el resumen de su ficha) y la
//   firma del creador. La audiencia no cambia nunca.
// - **kid**: SHA-256 completo en hexadecimal de
//     "gift-huddle-family-kid-v1" ‖ 0x00 ‖ JSON canónico de
//     {"a", "c", "cr", "ctx", "e", "l", "s":"family", "sid", "v":1} ‖ 0x00 ‖
//     secreto
//   En hexadecimal, el orden de los textos es el de los bytes.
// - **Firma del creador** (M3): Ed25519 del creador sobre
//     "gift-huddle-family-candidate-v1" ‖ 0x00 ‖ JSON canónico de
//     {"a", "c", "cr", "ctx", "e", "kid", "l", "s":"family", "sid", "v":1}
//   Solo el creador puede acuñar una candidata a su nombre; quien reparte
//   solo puede reenviar las que ya existen. Se comprueba con la clave de la
//   ficha `cr` (un móvil del registro) al abrir el paquete v4.
// - **Llavero** ([FamilyKeyring]): abre por `kid` exacto; sella con la de
//   `kid` menor de las que valen según quien llama; históricas y
//   comprometidas abren y no sellan; una candidata con referencias nunca
//   sale. Guarda la procedencia (propia o recibida, de qué emisores) y
//   limita por creador las recibidas que ni sellan ni tienen referencias
//   (M2): un miembro no puede inundar el llavero y dejar fuera las buenas.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';

import 'access_policy.dart' show KeyScope, kMaxKeyAudience;
import 'device_keys.dart';
import 'device_registry.dart';
import 'envelope.dart' show decodeBase64Url, encodeBase64Url;

/// Versión del formato de [FamilyCandidate] y del llavero común.
const int kFamilyCandidateVersion = 1;

/// Versión del formato de [EpochDescriptor].
const int kEpochDescriptorVersion = 2;

/// Candidatas recibidas que ni sellan ni tienen referencias que se guardan
/// por creador. Pasado el cupo se desalojan solo las de ese creador.
const int kMaxIdleCandidatesPerCreator = 8;

/// Candidatas recibidas que ni sellan ni tienen referencias en total.
const int kMaxIdleFamilyCandidates = 64;

/// Tope duro del llavero: solo se alcanza con propias, sellables o
/// referenciadas (contrapresión).
const int kMaxFamilyCandidates = 256;

/// Referencias que admite una candidata del llavero.
const int kMaxCandidateReferences = 64;

/// Emisores que se recuerdan por candidata recibida.
const int kMaxCandidateSenders = 8;

/// Generación v2: 16 bytes en base64url (22 caracteres).
final RegExp kV2SyncIdPattern = RegExp(r'^[A-Za-z0-9_-]{22}$');

final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');
final RegExp _refPattern = RegExp(r'^[\x21-\x7e]{1,128}$');

const _contextDomain = 'gift-huddle-epoch-context-v2';
const _kidDomain = 'gift-huddle-family-kid-v1';
const _creatorDomain = 'gift-huddle-family-candidate-v1';
const _secretLength = 32;
const _digestLength = 32;
const _signatureLength = 64;

/// Una candidata o un llavero común que no vale.
class FamilyKeyException implements Exception {
  /// Crea el error.
  const FamilyKeyException(this.message);

  /// Qué pasó (sin claves).
  final String message;

  @override
  String toString() => 'FamilyKeyException: $message';
}

/// El llavero común no admite más candidatas propias, sellables o
/// referenciadas (contrapresión: quien llama conserva su trabajo y quita
/// referencias o poda con [FamilyKeyring.prune]).
class FamilyKeyringFullException extends FamilyKeyException {
  /// Crea el error.
  const FamilyKeyringFullException(super.message);
}

/// Se intentó quitar una candidata que aún tiene referencias.
class FamilyKeyReferencedException extends FamilyKeyException {
  /// Crea el error.
  const FamilyKeyReferencedException(super.message);
}

/// SHA-256 de [bytes] en hexadecimal minúscula.
String sha256Hex(List<int> bytes) => [
  for (final b in const DartSha256().hashSync(bytes).bytes)
    b.toRadixString(16).padLeft(2, '0'),
].join();

/// Decodifica base64url sin relleno y exige la forma canónica (la que
/// produce [encodeBase64Url]) y, si se da, la longitud. Null si no vale.
Uint8List? decodeCanonicalBase64Url(String text, {int? length}) {
  final Uint8List bytes;
  try {
    bytes = decodeBase64Url(text);
  } on FormatException {
    return null;
  }
  if ((length != null && bytes.length != length) ||
      encodeBase64Url(bytes) != text) {
    return null;
  }
  return bytes;
}

/// Si [text] es un resumen de ficha (32 bytes en base64url canónico).
bool isRecordDigest(String text) =>
    decodeCanonicalBase64Url(text, length: _digestLength) != null;

/// Si [text] es un `kid` o un contexto de época (64 hexadecimales).
bool isFamilyHash(String text) => _hex64.hasMatch(text);

/// Si [value] es un entero JSON válido en cualquier plataforma: un `int`
/// dentro de [min] y [max] (por defecto, los enteros exactos de JavaScript).
/// En la VM un `1.0` no es `int`; en dart2js `1.0` y `1` son el mismo
/// número y, como todo se vuelve a codificar en forma canónica para firmar
/// y para el AAD, da el mismo resultado. Los bytes de la cabecera del sobre
/// común se comparan con su forma canónica: ahí `1.0` se rechaza siempre.
bool isJsonInt(Object? value, {int min = 0, int max = 0x1FFFFFFFFFFFFF}) =>
    value is int && value >= min && value <= max;

// ------------------------------------------------------------- audiencia

/// Un móvil de la audiencia de una candidata: su id y el resumen de la
/// ficha con la que la conoce.
class AudienceMember implements Comparable<AudienceMember> {
  /// Crea el miembro. Lanza [FamilyKeyException] si no vale.
  AudienceMember(this.deviceId, this.recordDigest) {
    if (!kSyncIdPattern.hasMatch(deviceId) || !isRecordDigest(recordDigest)) {
      throw const FamilyKeyException('miembro de la audiencia no válido');
    }
  }

  /// Id del móvil.
  final String deviceId;

  /// Resumen de su ficha ([KnownDevice.recordDigest]).
  final String recordDigest;

  /// `[deviceId, recordDigest]`.
  List<String> toJson() => [deviceId, recordDigest];

  /// Lee [toJson]. Lanza [FamilyKeyException] si no vale.
  factory AudienceMember.fromJson(Object? json) {
    if (json is! List ||
        json.length != 2 ||
        json[0] is! String ||
        json[1] is! String) {
      throw const FamilyKeyException('miembro de la audiencia no válido');
    }
    return AudienceMember(json[0] as String, json[1] as String);
  }

  @override
  int compareTo(AudienceMember other) => deviceId.compareTo(other.deviceId);

  @override
  bool operator ==(Object other) =>
      other is AudienceMember &&
      other.deviceId == deviceId &&
      other.recordDigest == recordDigest;

  @override
  int get hashCode => Object.hash(deviceId, recordDigest);

  @override
  String toString() => 'AudienceMember($deviceId)';
}

/// La audiencia ordenada por id. Lanza [FamilyKeyException] si hay ids
/// repetidos, está vacía o pasa de [kMaxKeyAudience].
List<AudienceMember> canonicalAudience(Iterable<AudienceMember> members) {
  final sorted = members.toList()..sort();
  for (var i = 1; i < sorted.length; i++) {
    if (sorted[i - 1].deviceId == sorted[i].deviceId) {
      throw const FamilyKeyException('audiencia con móviles repetidos');
    }
  }
  if (sorted.isEmpty || sorted.length > kMaxKeyAudience) {
    throw const FamilyKeyException('audiencia no válida');
  }
  return List.unmodifiable(sorted);
}

/// Lee una audiencia en JSON y exige que ya venga en orden canónico.
List<AudienceMember> audienceFromJson(Object? json) {
  if (json is! List || json.length > kMaxKeyAudience) {
    throw const FamilyKeyException('audiencia no válida');
  }
  final members = [for (final m in json) AudienceMember.fromJson(m)];
  final canonical = canonicalAudience(members);
  for (var i = 0; i < members.length; i++) {
    if (members[i] != canonical[i]) {
      throw const FamilyKeyException('audiencia fuera de orden');
    }
  }
  return canonical;
}

// ------------------------------------------------------ contexto de época

/// Lo que sustenta una época vista desde un móvil: los activos con su ficha
/// actual y los revocados que cuentan. Su hash es el contexto ([context]).
/// No lleva el número de época (M1).
class EpochDescriptor {
  /// Crea el descriptor. Lanza [FamilyKeyException] si algo no vale.
  EpochDescriptor({
    required this.listId,
    required this.syncId,
    required Iterable<AudienceMember> members,
    required Iterable<String> revoked,
  }) : members = canonicalAudience(members),
       revoked = List.unmodifiable(revoked.toSet().toList()..sort()) {
    if (!kSyncIdPattern.hasMatch(listId) ||
        !kV2SyncIdPattern.hasMatch(syncId) ||
        this.revoked.length > kMaxRegistryRecords ||
        !this.revoked.every(kSyncIdPattern.hasMatch)) {
      throw const FamilyKeyException('descriptor de época no válido');
    }
  }

  /// El descriptor de la vista [view] para la generación [syncId]: sus
  /// activos (con este móvil, y las webs confirmadas) y sus revocados.
  factory EpochDescriptor.ofView(RegistryView view, {required String syncId}) =>
      EpochDescriptor(
        listId: view.listId,
        syncId: syncId,
        members: [
          for (final id in view.members)
            AudienceMember(id, view.member(id)!.recordDigest),
        ],
        revoked: view.revoked,
      );

  /// Lista.
  final String listId;

  /// Generación v2.
  final String syncId;

  /// Activos con su ficha actual, por id.
  final List<AudienceMember> members;

  /// Revocados (y ambiguos), por id.
  final List<String> revoked;

  Map<String, Object?> _fields() => <String, Object?>{
    'l': listId,
    'm': [for (final m in members) m.toJson()],
    'r': revoked,
    'sid': syncId,
    'v': kEpochDescriptorVersion,
  };

  /// El contexto de la época: SHA-256 con dominio del JSON canónico.
  late final String context = sha256Hex([
    ...utf8.encode(_contextDomain),
    0,
    ...canonicalHeaderBytes(_fields()),
  ]);

  /// El descriptor en JSON (canónico).
  Map<String, Object?> toJson() => _fields();

  /// Lee [toJson]. Lanza [FamilyKeyException] si no vale o no es canónico.
  factory EpochDescriptor.fromJson(Object? json) {
    if (json is! Map ||
        json.length != 5 ||
        json['v'] != kEpochDescriptorVersion) {
      throw const FamilyKeyException('descriptor de época no válido');
    }
    final l = json['l'];
    final sid = json['sid'];
    final r = json['r'];
    if (l is! String ||
        sid is! String ||
        r is! List ||
        !r.every((x) => x is String)) {
      throw const FamilyKeyException('descriptor de época no válido');
    }
    final revoked = r.cast<String>();
    final d = EpochDescriptor(
      listId: l,
      syncId: sid,
      members: audienceFromJson(json['m']),
      revoked: revoked,
    );
    if (d.revoked.length != revoked.length) {
      throw const FamilyKeyException('descriptor de época no válido');
    }
    for (var i = 0; i < revoked.length; i++) {
      if (d.revoked[i] != revoked[i]) {
        throw const FamilyKeyException('descriptor de época no válido');
      }
    }
    return d;
  }
}

/// El contexto de la época que ve [view] en la generación [syncId].
String epochContextOf(RegistryView view, {required String syncId}) =>
    EpochDescriptor.ofView(view, syncId: syncId).context;

// -------------------------------------------------------------- candidata

/// Una clave común candidata de una época, firmada por su creador. Nunca
/// aparece en `toString()`.
class FamilyCandidate {
  FamilyCandidate._({
    required this.listId,
    required this.syncId,
    required this.epochNumber,
    required this.epochContext,
    required this.creator,
    required this.creatorRecord,
    required this.audience,
    required Uint8List secret,
    required this.kid,
    required Uint8List creatorSignature,
  }) // Los campos privados no pueden ser parámetros con nombre.
    // ignore: prefer_initializing_formals
    : _secret = secret,
       // ignore: prefer_initializing_formals
       _creatorSignature = creatorSignature;

  /// Rehace una candidata ya firmada (de un paquete o del almacén): recalcula
  /// el `kid` y comprueba los campos, pero **no verifica al creador** (ni su
  /// firma ni su ficha: eso lo hace `FamilyKeyBundle.open`, o quien llame a
  /// [verifyCreator] con la clave del nodo enlazado). Lo que salga de aquí
  /// sin esa comprobación no debe entrar en el llavero como recibido (B6 y
  /// B7: ficheros `.regalos` y checkpoint al emparejar). Lanza [FamilyKeyException] si algo
  /// no vale: ids, época, contexto, secreto (32 bytes y no todo ceros),
  /// creador en la audiencia con su ficha, firma de 64 bytes.
  factory FamilyCandidate.signed({
    required String listId,
    required String syncId,
    required int epochNumber,
    required String epochContext,
    required String creator,
    required String creatorRecord,
    required Iterable<AudienceMember> audience,
    required List<int> secret,
    required List<int> creatorSignature,
  }) {
    final sorted = canonicalAudience(audience);
    checkFamilyKeyHeader(
      listId: listId,
      syncId: syncId,
      epochNumber: epochNumber,
      epochContext: epochContext,
      creator: creator,
      creatorRecord: creatorRecord,
      audience: sorted,
    );
    if (secret.length != _secretLength || secret.every((b) => b == 0)) {
      throw const FamilyKeyException('secreto no válido');
    }
    if (creatorSignature.length != _signatureLength) {
      throw const FamilyKeyException('firma del creador no válida');
    }
    return FamilyCandidate._(
      listId: listId,
      syncId: syncId,
      epochNumber: epochNumber,
      epochContext: epochContext,
      creator: creator,
      creatorRecord: creatorRecord,
      audience: sorted,
      secret: Uint8List.fromList(secret),
      kid: familyKidOf(
        listId: listId,
        syncId: syncId,
        epochNumber: epochNumber,
        epochContext: epochContext,
        creator: creator,
        creatorRecord: creatorRecord,
        audience: sorted,
        secret: secret,
      ),
      creatorSignature: Uint8List.fromList(creatorSignature),
    );
  }

  /// Crea y firma una candidata con todo dado. [creatorKeys] firma como
  /// [creator]; no se mira el registro (para eso, [generate]). Lanza
  /// [FamilyKeyException] si algo no vale.
  static Future<FamilyCandidate> create({
    required String listId,
    required String syncId,
    required int epochNumber,
    required String epochContext,
    required String creator,
    required String creatorRecord,
    required Iterable<AudienceMember> audience,
    required List<int> secret,
    required DeviceKeys creatorKeys,
  }) async {
    final sorted = canonicalAudience(audience);
    checkFamilyKeyHeader(
      listId: listId,
      syncId: syncId,
      epochNumber: epochNumber,
      epochContext: epochContext,
      creator: creator,
      creatorRecord: creatorRecord,
      audience: sorted,
    );
    final kid = familyKidOf(
      listId: listId,
      syncId: syncId,
      epochNumber: epochNumber,
      epochContext: epochContext,
      creator: creator,
      creatorRecord: creatorRecord,
      audience: sorted,
      secret: secret,
    );
    final signature = await creatorKeys.sign(
      familyCandidateStatement(
        listId: listId,
        syncId: syncId,
        epochNumber: epochNumber,
        epochContext: epochContext,
        creator: creator,
        creatorRecord: creatorRecord,
        audience: sorted,
        kid: kid,
      ),
    );
    return FamilyCandidate.signed(
      listId: listId,
      syncId: syncId,
      epochNumber: epochNumber,
      epochContext: epochContext,
      creator: creator,
      creatorRecord: creatorRecord,
      audience: sorted,
      secret: secret,
      creatorSignature: signature,
    );
  }

  /// Crea una candidata nueva y aleatoria para la época que ve [view]: el
  /// creador es este móvil (firma con [keys]) y la audiencia, todos los
  /// activos con su ficha actual (también los que aún no la han recogido).
  ///
  /// Solo la crea un móvil activo, aprobado y no revocado, y [keys] tienen
  /// que ser las de su ficha: una web con la vista de su raíz no puede
  /// (revisión de seguridad, B1). Lanza [FamilyKeyException] si no.
  static Future<FamilyCandidate> generate(
    RegistryView view, {
    required DeviceKeys keys,
    required String syncId,
  }) async {
    if (view.self.kind != DeviceKind.mobile ||
        view.revokedByOthers ||
        !view.selfApproved ||
        !constantTimeEquals(keys.publicKeys.signing, view.self.signingKey)) {
      throw const FamilyKeyException(
        'este dispositivo no puede crear la clave común',
      );
    }
    final descriptor = EpochDescriptor.ofView(view, syncId: syncId);
    return create(
      listId: view.listId,
      syncId: syncId,
      epochNumber: view.epoch,
      epochContext: descriptor.context,
      creator: view.me,
      creatorRecord: view.self.recordDigest,
      audience: descriptor.members,
      secret: secureRandomBytes(_secretLength),
      creatorKeys: keys,
    );
  }

  /// Lista.
  final String listId;

  /// Generación v2.
  final String syncId;

  /// Ámbito: siempre [KeyScope.family].
  String get scope => KeyScope.family;

  /// Número de la época al crearla (descriptivo: no decide nada).
  final int epochNumber;

  /// Contexto de la época ([EpochDescriptor.context]).
  final String epochContext;

  /// Móvil que la creó (y la firma).
  final String creator;

  /// Resumen de la ficha del creador al crearla.
  final String creatorRecord;

  /// Móviles que la conocen, con su ficha, ordenados por id. Inmutable.
  final List<AudienceMember> audience;

  final Uint8List _secret;

  final Uint8List _creatorSignature;

  /// Identificador público (SHA-256 completo en hexadecimal).
  final String kid;

  /// Copia del secreto.
  Uint8List get secret => Uint8List.fromList(_secret);

  /// Copia de la firma del creador.
  Uint8List get creatorSignature => Uint8List.fromList(_creatorSignature);

  /// Si la firma del creador vale con [signingKey] (la clave de la ficha
  /// [creatorRecord]).
  Future<bool> verifyCreator(List<int> signingKey) => verifyDeviceSignature(
    message: familyCandidateStatement(
      listId: listId,
      syncId: syncId,
      epochNumber: epochNumber,
      epochContext: epochContext,
      creator: creator,
      creatorRecord: creatorRecord,
      audience: audience,
      kid: kid,
    ),
    signature: _creatorSignature,
    signingPublicKey: signingKey,
  );

  /// La audiencia de [deviceId], o null si no la conoce.
  AudienceMember? audienceOf(String deviceId) {
    for (final m in audience) {
      if (m.deviceId == deviceId) return m;
    }
    return null;
  }

  /// Si la audiencia es exactamente la de los activos de [view], con sus
  /// fichas actuales: nadie de la audiencia ha perdido el derecho (revocado,
  /// pendiente, ambiguo o con otra ficha) y nadie con derecho falta.
  bool audienceMatches(RegistryView view) {
    final members = view.members;
    if (members.length != audience.length) return false;
    for (var i = 0; i < members.length; i++) {
      if (audience[i].deviceId != members[i] ||
          audience[i].recordDigest != view.member(members[i])!.recordDigest) {
        return false;
      }
    }
    return true;
  }

  /// El predicado básico para sellar con ella desde [view]: es de esta
  /// lista y generación, del contexto actual y su audiencia es la de ahora.
  /// El número de época no cuenta (M1). Quien llama añade lo demás y el
  /// llavero excluye las históricas y comprometidas.
  bool sealableIn(RegistryView view, {required String syncId}) =>
      listId == view.listId &&
      this.syncId == syncId &&
      epochContext == epochContextOf(view, syncId: syncId) &&
      audienceMatches(view);

  /// La candidata en JSON (contiene el secreto).
  Map<String, Object?> toJson() => <String, Object?>{
    'v': kFamilyCandidateVersion,
    'l': listId,
    'sid': syncId,
    's': scope,
    'e': epochNumber,
    'ctx': epochContext,
    'kid': kid,
    'c': creator,
    'cr': creatorRecord,
    'a': [for (final m in audience) m.toJson()],
    'cs': encodeBase64Url(_creatorSignature),
    'k': encodeBase64Url(_secret),
  };

  static const _jsonKeys = {
    'v',
    'l',
    'sid',
    's',
    'e',
    'ctx',
    'kid',
    'c',
    'cr',
    'a',
    'cs',
    'k',
  };

  /// Lee [toJson] y recalcula el `kid`. Lanza [FamilyKeyException] si no
  /// vale o si el `kid` guardado no coincide. No comprueba la firma del
  /// creador ([verifyCreator]).
  factory FamilyCandidate.fromJson(Object? json) {
    if (json is! Map ||
        json.length != _jsonKeys.length ||
        !json.keys.every(_jsonKeys.contains) ||
        json['v'] != kFamilyCandidateVersion ||
        json['s'] != KeyScope.family) {
      throw const FamilyKeyException('candidata no válida');
    }
    final l = json['l'];
    final sid = json['sid'];
    final e = json['e'];
    final ctx = json['ctx'];
    final kid = json['kid'];
    final c = json['c'];
    final cr = json['cr'];
    final cs = json['cs'];
    final k = json['k'];
    if (l is! String ||
        sid is! String ||
        !isJsonInt(e) ||
        ctx is! String ||
        kid is! String ||
        c is! String ||
        cr is! String ||
        cs is! String ||
        k is! String) {
      throw const FamilyKeyException('candidata no válida');
    }
    final secret = decodeCanonicalBase64Url(k, length: _secretLength);
    final signature = decodeCanonicalBase64Url(cs, length: _signatureLength);
    if (secret == null || signature == null) {
      throw const FamilyKeyException('candidata no válida');
    }
    final candidate = FamilyCandidate.signed(
      listId: l,
      syncId: sid,
      epochNumber: e! as int,
      epochContext: ctx,
      creator: c,
      creatorRecord: cr,
      audience: audienceFromJson(json['a']),
      secret: secret,
      creatorSignature: signature,
    );
    if (candidate.kid != kid) {
      throw const FamilyKeyException('kid no válido');
    }
    return candidate;
  }

  @override
  String toString() => 'FamilyCandidate(e$epochNumber, ${kid.substring(0, 8)})';
}

/// Comprueba los campos públicos de una candidata (sin el secreto). Lanza
/// [FamilyKeyException] si alguno no vale o si el creador no está en
/// [audience] con [creatorRecord].
void checkFamilyKeyHeader({
  required String listId,
  required String syncId,
  required int epochNumber,
  required String epochContext,
  required String creator,
  required String creatorRecord,
  required List<AudienceMember> audience,
}) {
  final creatorEntry = [
    for (final m in audience)
      if (m.deviceId == creator) m,
  ];
  if (!kSyncIdPattern.hasMatch(listId) ||
      !kV2SyncIdPattern.hasMatch(syncId) ||
      !isJsonInt(epochNumber, min: 1, max: 0xFFFFFFFF) ||
      !isFamilyHash(epochContext) ||
      !kSyncIdPattern.hasMatch(creator) ||
      !isRecordDigest(creatorRecord) ||
      creatorEntry.length != 1 ||
      creatorEntry.single.recordDigest != creatorRecord) {
    throw const FamilyKeyException('cabecera de la candidata no válida');
  }
}

Map<String, Object?> _publicFields({
  required String listId,
  required String syncId,
  required int epochNumber,
  required String epochContext,
  required String creator,
  required String creatorRecord,
  required List<AudienceMember> audience,
}) => <String, Object?>{
  'a': [for (final m in audience) m.toJson()],
  'c': creator,
  'cr': creatorRecord,
  'ctx': epochContext,
  'e': epochNumber,
  'l': listId,
  's': KeyScope.family,
  'sid': syncId,
  'v': kFamilyCandidateVersion,
};

/// El `kid` de una candidata: SHA-256 completo en hexadecimal (ver la
/// cabecera del fichero).
String familyKidOf({
  required String listId,
  required String syncId,
  required int epochNumber,
  required String epochContext,
  required String creator,
  required String creatorRecord,
  required List<AudienceMember> audience,
  required List<int> secret,
}) => sha256Hex([
  ...utf8.encode(_kidDomain),
  0,
  ...canonicalHeaderBytes(
    _publicFields(
      listId: listId,
      syncId: syncId,
      epochNumber: epochNumber,
      epochContext: epochContext,
      creator: creator,
      creatorRecord: creatorRecord,
      audience: audience,
    ),
  ),
  0,
  ...secret,
]);

/// Lo que firma el creador de una candidata (ver la cabecera del fichero).
List<int> familyCandidateStatement({
  required String listId,
  required String syncId,
  required int epochNumber,
  required String epochContext,
  required String creator,
  required String creatorRecord,
  required List<AudienceMember> audience,
  required String kid,
}) => [
  ...utf8.encode(_creatorDomain),
  0,
  ...canonicalHeaderBytes({
    ..._publicFields(
      listId: listId,
      syncId: syncId,
      epochNumber: epochNumber,
      epochContext: epochContext,
      creator: creator,
      creatorRecord: creatorRecord,
      audience: audience,
    ),
    'kid': kid,
  }),
];

// ---------------------------------------------------------------- llavero

/// Una candidata del llavero con su estado local.
class FamilyKeyEntry {
  FamilyKeyEntry._(
    this.candidate, {
    required this.own,
    required List<AudienceMember> senders,
    required this.historical,
    required this.compromised,
    required Set<String> references,
  }) : senders = List.unmodifiable(senders),
       references = Set.unmodifiable(references);

  /// La candidata.
  final FamilyCandidate candidate;

  /// Si la creó (o la importó) este dispositivo.
  final bool own;

  /// Quién se la ha enviado (emisor y su ficha), ordenados por id; como
  /// mucho [kMaxCandidateSenders].
  final List<AudienceMember> senders;

  /// Histórica: abre lo ya publicado pero no sella (p. ej. la legacy).
  final bool historical;

  /// Comprometida: abre pero no sella.
  final bool compromised;

  /// Quién la necesita todavía (un sobre pendiente, una copia retenida, una
  /// operación a medias...): mientras tenga alguna no sale del llavero.
  final Set<String> references;

  /// Si puede sellar (sin mirar la vista: eso lo decide quien llama).
  bool get usable => !historical && !compromised;

  FamilyKeyEntry _copy({
    bool? own,
    List<AudienceMember>? senders,
    bool? historical,
    bool? compromised,
    Set<String>? references,
  }) => FamilyKeyEntry._(
    candidate,
    own: own ?? this.own,
    senders: senders ?? this.senders,
    historical: historical ?? this.historical,
    compromised: compromised ?? this.compromised,
    references: references ?? this.references,
  );

  Map<String, Object?> _toJson() => <String, Object?>{
    'c': candidate.toJson(),
    if (own) 'o': true,
    if (senders.isNotEmpty) 'f': [for (final s in senders) s.toJson()],
    if (historical) 'h': true,
    if (compromised) 'x': true,
    if (references.isNotEmpty) 'r': references.toList()..sort(),
  };
}

/// Las claves comunes de este dispositivo. Inmutable: cada cambio devuelve
/// otro llavero.
class FamilyKeyring {
  FamilyKeyring._(Map<String, FamilyKeyEntry> entries)
    : _entries = Map.unmodifiable(entries);

  /// El llavero vacío.
  static final FamilyKeyring empty = FamilyKeyring._(const {});

  final Map<String, FamilyKeyEntry> _entries;

  /// Las entradas, ordenadas por `kid`.
  List<FamilyKeyEntry> get entries => [
    for (final kid in _entries.keys.toList()..sort()) _entries[kid]!,
  ];

  /// Las candidatas, ordenadas por `kid`.
  List<FamilyCandidate> get candidates => [
    for (final e in entries) e.candidate,
  ];

  /// Cuántas candidatas hay.
  int get length => _entries.length;

  /// La entrada de [kid], o null.
  FamilyKeyEntry? entry(String kid) => _entries[kid];

  /// La candidata para abrir algo sellado con [kid]: tiene que coincidir
  /// exactamente la lista, la generación, la época y el contexto (el `kid`
  /// ya los liga). Las históricas y las comprometidas también abren. Null si
  /// no está.
  FamilyCandidate? forOpening({
    required String listId,
    required String syncId,
    required int epochNumber,
    required String epochContext,
    required String kid,
  }) {
    final c = _entries[kid]?.candidate;
    if (c == null ||
        c.listId != listId ||
        c.syncId != syncId ||
        c.epochNumber != epochNumber ||
        c.epochContext != epochContext) {
      return null;
    }
    return c;
  }

  /// Las candidatas del contexto [epochContext], ordenadas por `kid`.
  List<FamilyCandidate> candidatesOf(String epochContext) => [
    for (final c in candidates)
      if (c.epochContext == epochContext) c,
  ];

  /// La candidata con la que sellar en el contexto [epochContext]: de las
  /// que no son históricas ni comprometidas y cumplen [valid] (audiencia
  /// entera con derecho, paquetes válidos: lo decide quien llama), la de
  /// `kid` menor. Null si no hay ninguna (toca crear otra). El número de
  /// época no cuenta (M1).
  FamilyCandidate? forSealing({
    required String epochContext,
    required bool Function(FamilyCandidate candidate) valid,
  }) {
    for (final e in entries) {
      final c = e.candidate;
      if (e.usable && c.epochContext == epochContext && valid(c)) return c;
    }
    return null;
  }

  /// La candidata con la que sella este dispositivo desde [view]:
  /// [forSealing] con el contexto actual y [FamilyCandidate.sealableIn],
  /// más lo que añada [extra].
  FamilyCandidate? forSealingIn(
    RegistryView view, {
    required String syncId,
    bool Function(FamilyCandidate candidate)? extra,
  }) => forSealing(
    epochContext: epochContextOf(view, syncId: syncId),
    valid: (c) =>
        c.sealableIn(view, syncId: syncId) && (extra == null || extra(c)),
  );

  /// El llavero con [candidate] como propia (la creó o la importó este
  /// dispositivo; con [historical], p. ej. la legacy). Las propias siempre
  /// caben salvo el tope duro ([FamilyKeyringFullException]). Volver a
  /// añadirla nunca desmarca la histórica.
  FamilyKeyring withOwnCandidate(
    FamilyCandidate candidate, {
    bool historical = false,
  }) {
    final known = _entries[candidate.kid];
    if (known != null) {
      if (known.own && (!historical || known.historical)) return this;
      return _with(
        candidate.kid,
        known._copy(own: true, historical: known.historical || historical),
      );
    }
    if (_entries.length >= kMaxFamilyCandidates) {
      throw const FamilyKeyringFullException(
        'no caben más claves comunes en el llavero',
      );
    }
    return _with(
      candidate.kid,
      FamilyKeyEntry._(
        candidate,
        own: true,
        senders: const [],
        historical: historical,
        compromised: false,
        references: const {},
      ),
    );
  }

  /// El llavero con [candidate] recibida de [from] (con su ficha
  /// [fromRecord]).
  ///
  /// Solo debe recibir el resultado de `FamilyKeyBundle.open` (o de una
  /// importación que haya verificado igual al creador): aquí no se comprueba
  /// la firma del creador ni su ficha, y el cupo va por creador porque ahí
  /// está autenticado. (B6 y B7 tienen que respetarlo.)
  ///
  /// Las recibidas sin referencias que no están en [wanted] (los `kid` que
  /// quien llama necesita, p. ej. los de sobres pendientes que ha visto con
  /// `peekFamilyEnvelope`) tienen cupo por creador
  /// ([kMaxIdleCandidatesPerCreator]), sellen o no (R4), y en total
  /// ([kMaxIdleFamilyCandidates]). Pasado el cupo se desalojan solo las de
  /// ese creador (o, por el total, las del creador que más tiene): primero
  /// las que no sellan según [sealable] y, dentro de cada grupo, de `kid`
  /// mayor a menor; puede que la desalojada sea la recién llegada. Las
  /// propias, las referenciadas y las buscadas no se desalojan nunca (R3).
  /// Lanza [FamilyKeyringFullException] si se llega al tope duro con
  /// candidatas que no se pueden desalojar.
  FamilyKeyring withReceivedCandidate(
    FamilyCandidate candidate, {
    required String from,
    required String fromRecord,
    required bool Function(FamilyCandidate candidate) sealable,
    Set<String> wanted = const {},
  }) {
    final sender = AudienceMember(from, fromRecord);
    final known = _entries[candidate.kid];
    if (known != null) {
      if (known.senders.any((s) => s.deviceId == from) ||
          known.senders.length >= kMaxCandidateSenders) {
        return this;
      }
      return _with(
        candidate.kid,
        known._copy(senders: [...known.senders, sender]..sort()),
      );
    }
    final next = FamilyKeyring._({
      ..._entries,
      candidate.kid: FamilyKeyEntry._(
        candidate,
        own: false,
        senders: [sender],
        historical: false,
        compromised: false,
        references: const {},
      ),
    })._evict(sealable, wanted, creator: candidate.creator);
    if (next.length > kMaxFamilyCandidates) {
      throw const FamilyKeyringFullException(
        'no caben más claves comunes en el llavero',
      );
    }
    return next;
  }

  /// Si [e] se puede desalojar: recibida, sin referencias y no buscada.
  static bool _evictable(FamilyKeyEntry e, Set<String> wanted) =>
      !e.own && e.references.isEmpty && !wanted.contains(e.candidate.kid);

  FamilyKeyring _evict(
    bool Function(FamilyCandidate) sealable,
    Set<String> wanted, {
    required String creator,
  }) {
    // Por creador, en orden de salida: al final las que se quedan antes
    // (las que sellan, y de ellas la de kid menor, que es la que se usa).
    final byCreator = <String, List<FamilyKeyEntry>>{};
    for (final e in entries) {
      if (_evictable(e, wanted)) {
        (byCreator[e.candidate.creator] ??= []).add(e);
      }
    }
    for (final list in byCreator.values) {
      list.sort((a, b) {
        final sa = sealable(a.candidate);
        final sb = sealable(b.candidate);
        if (sa != sb) return sa ? 1 : -1;
        return b.candidate.kid.compareTo(a.candidate.kid);
      });
    }
    final drop = <String>{};
    void trim(String who, int keep) {
      final list = byCreator[who]!;
      while (list.length > keep) {
        drop.add(list.removeAt(0).candidate.kid);
      }
    }

    if (byCreator.containsKey(creator)) {
      trim(creator, kMaxIdleCandidatesPerCreator);
    }
    var total = byCreator.values.fold<int>(0, (n, l) => n + l.length);
    while (total > kMaxIdleFamilyCandidates) {
      final biggest = (byCreator.keys.toList()..sort()).reduce(
        (a, b) => byCreator[b]!.length > byCreator[a]!.length ? b : a,
      );
      trim(biggest, byCreator[biggest]!.length - 1);
      total--;
    }
    if (drop.isEmpty) return this;
    return FamilyKeyring._(
      {..._entries}..removeWhere((k, _) => drop.contains(k)),
    );
  }

  /// El llavero con [kid] marcada como histórica (abre y no sella).
  FamilyKeyring markHistorical(String kid) =>
      _update(kid, (e) => e._copy(historical: true));

  /// El llavero con [kid] marcada como comprometida (abre y no sella).
  FamilyKeyring markCompromised(String kid) =>
      _update(kid, (e) => e._copy(compromised: true));

  /// El llavero con la referencia [ref] en [kid] (p. ej. el sobre común
  /// pendiente, una copia retenida, una intención de reparto). Lanza
  /// [FamilyKeyException] si pasa de [kMaxCandidateReferences].
  FamilyKeyring withReference(String kid, String ref) {
    if (!_refPattern.hasMatch(ref)) {
      throw const FamilyKeyException('referencia no válida');
    }
    return _update(kid, (e) {
      if (e.references.contains(ref)) return e;
      if (e.references.length >= kMaxCandidateReferences) {
        throw const FamilyKeyException('demasiadas referencias');
      }
      return e._copy(references: {...e.references, ref});
    });
  }

  /// El llavero sin la referencia [ref] en [kid].
  FamilyKeyring withoutReference(String kid, String ref) =>
      _update(kid, (e) => e._copy(references: {...e.references}..remove(ref)));

  /// El llavero sin [kid]. Lanza [FamilyKeyReferencedException] si aún
  /// tiene referencias.
  FamilyKeyring without(String kid) {
    final e = _entries[kid];
    if (e == null) return this;
    if (e.references.isNotEmpty) {
      throw const FamilyKeyReferencedException(
        'esa clave común todavía se necesita',
      );
    }
    return FamilyKeyring._({..._entries}..remove(kid));
  }

  /// El llavero sin las candidatas que no cumplen [keep], salvo las que
  /// tienen referencias: esas se quedan siempre.
  FamilyKeyring prune(bool Function(FamilyKeyEntry entry) keep) =>
      FamilyKeyring._({
        for (final e in _entries.entries)
          if (e.value.references.isNotEmpty || keep(e.value)) e.key: e.value,
      });

  /// Poda las recibidas sin referencias, que no están en [wanted], cuyo
  /// creador está revocado en [view] **y** cuyos emisores lo están todos
  /// (R2): una clave auténtica de antes de la revocación que reenvía un
  /// miembro honrado se queda, porque puede hacer falta para abrir lo ya
  /// publicado. Las propias se quedan siempre.
  FamilyKeyring pruneRevoked(
    RegistryView view, {
    Set<String> wanted = const {},
  }) => prune(
    (e) =>
        !_evictable(e, wanted) ||
        !(view.revoked.contains(e.candidate.creator) &&
            e.senders.isNotEmpty &&
            e.senders.every((s) => view.revoked.contains(s.deviceId))),
  );

  FamilyKeyring _with(String kid, FamilyKeyEntry entry) =>
      FamilyKeyring._({..._entries, kid: entry});

  FamilyKeyring _update(
    String kid,
    FamilyKeyEntry Function(FamilyKeyEntry entry) change,
  ) {
    final e = _entries[kid];
    if (e == null) {
      throw const FamilyKeyException('esa clave común no está en el llavero');
    }
    final next = change(e);
    return identical(next, e) ? this : _with(kid, next);
  }

  /// `{"v":1,"keys":[...]}`, ordenado por `kid` (contiene secretos).
  Map<String, Object?> toJson() => <String, Object?>{
    'v': kFamilyCandidateVersion,
    'keys': [for (final e in entries) e._toJson()],
  };

  static const _entryKeys = {'c', 'o', 'f', 'h', 'x', 'r'};

  /// Lee [toJson]. Lanza [FamilyKeyException] si no vale (también con
  /// `kid` repetidos, entradas sin procedencia o por encima de los topes).
  factory FamilyKeyring.fromJson(Object? json) {
    if (json is! Map ||
        json.length != 2 ||
        json['v'] != kFamilyCandidateVersion ||
        json['keys'] is! List) {
      throw const FamilyKeyException('llavero común no válido');
    }
    final raw = json['keys'] as List;
    if (raw.length > kMaxFamilyCandidates) {
      throw const FamilyKeyException('llavero común no válido');
    }
    final entries = <String, FamilyKeyEntry>{};
    for (final item in raw) {
      if (item is! Map || !item.keys.every(_entryKeys.contains)) {
        throw const FamilyKeyException('llavero común no válido');
      }
      final o = item['o'] ?? false;
      final f = item['f'] ?? const <Object?>[];
      final h = item['h'] ?? false;
      final x = item['x'] ?? false;
      final r = item['r'] ?? const <Object?>[];
      if (o is! bool ||
          f is! List ||
          f.length > kMaxCandidateSenders ||
          h is! bool ||
          x is! bool ||
          r is! List ||
          r.length > kMaxCandidateReferences ||
          !r.every((ref) => ref is String && _refPattern.hasMatch(ref))) {
        throw const FamilyKeyException('llavero común no válido');
      }
      final senders = f.isEmpty
          ? const <AudienceMember>[]
          : audienceFromJson(f);
      if (!o && senders.isEmpty) {
        throw const FamilyKeyException('llavero común no válido');
      }
      final candidate = FamilyCandidate.fromJson(item['c']);
      if (entries.containsKey(candidate.kid)) {
        throw const FamilyKeyException('llavero común no válido');
      }
      entries[candidate.kid] = FamilyKeyEntry._(
        candidate,
        own: o,
        senders: senders,
        historical: h,
        compromised: x,
        references: r.cast<String>().toSet(),
      );
    }
    return FamilyKeyring._(entries);
  }

  @override
  String toString() => 'FamilyKeyring(${_entries.length} claves)';
}
