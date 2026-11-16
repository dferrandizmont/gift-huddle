// Sobre común firmado (formato 2): el documento común cifrado con una
// candidata de la clave común y firmado por quien lo escribe. Dart puro.
// Decisión: docs/adr/0005-rotacion-clave-comun.md (lote B1, sección 3 y
// «Decisiones de B1»). El sobre simétrico de envelope.dart (formato 1) no
// cambia.
//
// Formato (bytes):
//   "RG" | 0x02 | uint16 BE = longitud de la cabecera | cabecera |
//   nonce (12) | texto cifrado AES-256-GCM | etiqueta (16) | firma (64)
// - Cabecera: JSON canónico (claves ordenadas, compacto) de
//     {"ctx": contexto de la época, "e": época, "kid": candidata,
//      "l": lista, "r": revisión, "s": "family", "sid": generación,
//      "v": 2, "w": escritor, "wr": resumen de la ficha del escritor}
//   Al abrir se exige que los bytes sean exactamente esa forma canónica
//   (sin claves repetidas, `1.0`, `1e0`, `-0`, escapes, espacios ni BOM).
// - AAD del GCM = los bytes desde "RG" hasta el final de la cabecera.
// - Clave AES-256 = HKDF-SHA256(secreto de la candidata, sal vacía,
//   info = "gift-huddle-common-v2" ‖ 0x00 ‖ kid en ASCII, 32 bytes): el
//   secreto de la candidata no se usa tal cual (revisión de seguridad, B7).
// - Firma = Ed25519("gift-huddle-common-v2" ‖ 0x00 ‖ todos los bytes
//   anteriores a la firma), con la clave del escritor.
// - Cuerpo = deflate en bruto del JSON de `FamilyDoc.toJson()`, como el
//   formato 1: HLC por campo, lápidas y campos desconocidos tal cual.
// - Límites antes de verificar, descifrar y descomprimir: el sobre entero,
//   como mucho kMaxEnvelopeBytes; la cabecera, kMaxFamilyHeaderBytes; lo
//   descomprimido, kMaxPlainBytes (sin reservar más).
// - La revisión identifica publicaciones del escritor; no sustituye los HLC
//   ni demuestra frescura.
//
// Quién puede escribir lo decide quien llama: pasa un resolvedor que, para
// el escritor y su ficha, devuelve la clave Ed25519 en la que confía (o
// null). Aquí no se deciden permisos. Sí se exige que el escritor esté en la
// audiencia de la candidata con esa ficha, al sellar y al abrir (B6).
//
// Queda para B3: un escritor activo que conoce una candidata puede publicar
// un común bien firmado que no se puede leer (con una candidata que solo
// tiene él, o basura cifrada con una buena). El motor no debe darlo por
// vacío ni sustituir con él lo que tiene.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:meta/meta.dart';

import 'access_policy.dart' show KeyScope;
import 'device_keys.dart';
import 'device_registry.dart' show KnownDevice;
import 'envelope.dart'
    show
        EnvelopeAuthException,
        EnvelopeException,
        EnvelopeFormatException,
        EnvelopeTooLargeException,
        EnvelopeWrongListException,
        inflateWithLimit,
        kMaxEnvelopeBytes,
        kMaxPlainBytes;
import 'family_candidate.dart';
import 'family_doc.dart';

/// Versión (formato) del sobre común firmado.
const int kFamilyEnvelopeVersion = 2;

/// Tamaño máximo de la cabecera del sobre común firmado (bytes).
const int kMaxFamilyHeaderBytes = 1024;

/// Revisión más alta de un sobre común (cabe en un entero de JavaScript).
const int kMaxFamilyRevision = 0x1FFFFFFFFFFFFF;

const _magic0 = 0x52; // R
const _magic1 = 0x47; // G
const _prefixLength = 5;
const _nonceLength = 12;
const _macLength = 16;
const _signatureLength = 64;
const _sigDomain = 'gift-huddle-common-v2';
const _headerKeys = {'ctx', 'e', 'kid', 'l', 'r', 's', 'sid', 'v', 'w', 'wr'};

/// No hay en el llavero la candidata con la que se selló: el sobre se
/// conserva, no es un documento vacío.
class EnvelopeMissingKeyException extends EnvelopeException {
  /// Crea el error.
  const EnvelopeMissingKeyException(super.message);
}

/// Quien llama no reconoce al escritor (o su ficha) del sobre.
class EnvelopeUnknownWriterException extends EnvelopeException {
  /// Crea el error.
  const EnvelopeUnknownWriterException(super.message);
}

/// La clave Ed25519 en la que confía quien llama para [writer] con la ficha
/// [writerRecord], o null si no lo acepta.
typedef FamilyWriterResolver = FutureOr<List<int>?> Function(
  String writer,
  String writerRecord,
);

/// La cabecera de un sobre común firmado (en claro, autenticada).
class FamilyEnvelopeHeader {
  /// Crea la cabecera. Lanza [EnvelopeFormatException] si no vale.
  FamilyEnvelopeHeader({
    required this.listId,
    required this.syncId,
    required this.epochNumber,
    required this.epochContext,
    required this.kid,
    required this.writer,
    required this.writerRecord,
    required this.revision,
  }) {
    if (!kSyncIdPattern.hasMatch(listId) ||
        !kV2SyncIdPattern.hasMatch(syncId) ||
        !isJsonInt(epochNumber, min: 1, max: 0xFFFFFFFF) ||
        !isFamilyHash(epochContext) ||
        !isFamilyHash(kid) ||
        !kSyncIdPattern.hasMatch(writer) ||
        !isRecordDigest(writerRecord) ||
        !isJsonInt(revision, max: kMaxFamilyRevision)) {
      throw const EnvelopeFormatException('cabecera no válida');
    }
  }

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

  /// `kid` de la candidata con la que se selló.
  final String kid;

  /// Dispositivo que lo escribe (firma).
  final String writer;

  /// Resumen de la ficha del escritor al sellar.
  final String writerRecord;

  /// Revisión de las publicaciones del escritor.
  final int revision;

  List<int> _bytes() => canonicalHeaderBytes(<String, Object?>{
    'ctx': epochContext,
    'e': epochNumber,
    'kid': kid,
    'l': listId,
    'r': revision,
    's': KeyScope.family,
    'sid': syncId,
    'v': kFamilyEnvelopeVersion,
    'w': writer,
    'wr': writerRecord,
  });

  @override
  String toString() =>
      'FamilyEnvelopeHeader(e$epochNumber, w: $writer, r: $revision)';
}

/// Resultado de [openFamilyEnvelope].
class OpenedFamilyEnvelope {
  /// Crea el resultado.
  const OpenedFamilyEnvelope({
    required this.header,
    required this.doc,
    required this.candidate,
  });

  /// Cabecera autenticada.
  final FamilyEnvelopeHeader header;

  /// El documento común.
  final FamilyDoc doc;

  /// La candidata con la que se abrió.
  final FamilyCandidate candidate;
}

final _aes = AesGcm.with256bits();
final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

Future<SecretKey> _contentKey(FamilyCandidate candidate) => _hkdf.deriveKey(
  secretKey: SecretKey(candidate.secret),
  nonce: const <int>[],
  info: [...utf8.encode(_sigDomain), 0, ...utf8.encode(candidate.kid)],
);

bool _writerInAudience(FamilyCandidate c, String writer, String record) =>
    c.audienceOf(writer)?.recordDigest == record;

/// Si [bytes] empiezan como un sobre común firmado (formato 2). No valida.
bool isFamilyEnvelope(Uint8List bytes) =>
    bytes.length >= _prefixLength &&
    bytes[0] == _magic0 &&
    bytes[1] == _magic1 &&
    bytes[2] == kFamilyEnvelopeVersion;

/// Sella [doc] con [candidate] y lo firma con [signer] como [writer] (su
/// ficha en el registro: id, resumen y clave de firma), con la revisión
/// [revision]. Lanza [EnvelopeTooLargeException] si no cabe y
/// [EnvelopeFormatException] si la cabecera no vale, el documento es de
/// otra lista, [signer] no es la clave de [writer] o [writer] no está en la
/// audiencia de [candidate] con esa ficha.
Future<Uint8List> sealFamilyEnvelope({
  required FamilyDoc doc,
  required FamilyCandidate candidate,
  required KnownDevice writer,
  required int revision,
  required DeviceKeys signer,
}) async {
  if (!constantTimeEquals(signer.publicKeys.signing, writer.signingKey)) {
    throw const EnvelopeFormatException('la firma no es la del escritor');
  }
  return sealFamilyEnvelopeForTesting(
    doc: doc,
    candidate: candidate,
    writer: writer.deviceId,
    writerRecord: writer.recordDigest,
    revision: revision,
    signer: signer,
    nonce: secureRandomBytes(_nonceLength),
  );
}

/// Igual que [sealFamilyEnvelope] con todo dado y sin comprobar la clave del
/// firmante. SOLO para pruebas y vectores fijos: repetir un nonce con la
/// misma clave rompe AES-GCM. Con [bodyForTesting] se cifra ese cuerpo
/// comprimido en vez del documento.
@visibleForTesting
Future<Uint8List> sealFamilyEnvelopeForTesting({
  required FamilyDoc doc,
  required FamilyCandidate candidate,
  required String writer,
  required String writerRecord,
  required int revision,
  required DeviceKeys signer,
  required List<int> nonce,
  List<int>? bodyForTesting,
}) async {
  if (nonce.length != _nonceLength) {
    throw ArgumentError.value(nonce.length, 'nonce', 'debe tener 12 bytes');
  }
  if (doc.listId != candidate.listId) {
    throw const EnvelopeFormatException('el documento es de otra lista');
  }
  if (!_writerInAudience(candidate, writer, writerRecord)) {
    throw const EnvelopeFormatException(
      'el escritor no conoce esa clave común',
    );
  }
  final header = FamilyEnvelopeHeader(
    listId: candidate.listId,
    syncId: candidate.syncId,
    epochNumber: candidate.epochNumber,
    epochContext: candidate.epochContext,
    kid: candidate.kid,
    writer: writer,
    writerRecord: writerRecord,
    revision: revision,
  )._bytes();
  if (header.length > kMaxFamilyHeaderBytes) {
    throw const EnvelopeFormatException('cabecera demasiado larga');
  }
  final plain = utf8.encode(jsonEncode(doc.toJson()));
  if (plain.length > kMaxPlainBytes) {
    throw const EnvelopeTooLargeException('documento demasiado grande');
  }
  final body = bodyForTesting ?? Deflate(plain).getBytes();
  if (_prefixLength +
          header.length +
          _nonceLength +
          body.length +
          _macLength +
          _signatureLength >
      kMaxEnvelopeBytes) {
    throw const EnvelopeTooLargeException('sobre demasiado grande');
  }
  final aad =
      (BytesBuilder(copy: false)
            ..add(const [_magic0, _magic1, kFamilyEnvelopeVersion])
            ..add([header.length >> 8, header.length & 0xFF])
            ..add(header))
          .toBytes();
  final box = await _aes.encrypt(
    body,
    secretKey: await _contentKey(candidate),
    nonce: nonce,
    aad: aad,
  );
  final unsigned =
      (BytesBuilder(copy: false)
            ..add(aad)
            ..add(nonce)
            ..add(box.cipherText)
            ..add(box.mac.bytes))
          .toBytes();
  final signature = await signer.sign(familyEnvelopeSignedMessage(unsigned));
  return (BytesBuilder(copy: false)
        ..add(unsigned)
        ..add(signature))
      .toBytes();
}

/// Lo que firma el escritor: dominio ‖ 0x00 ‖ [unsigned] (todos los bytes
/// del sobre anteriores a la firma).
List<int> familyEnvelopeSignedMessage(List<int> unsigned) => [
  ...utf8.encode(_sigDomain),
  0,
  ...unsigned,
];

class _Parsed {
  _Parsed(this.header, this.aadEnd);
  final FamilyEnvelopeHeader header;
  final int aadEnd;
}

_Parsed _parse(Uint8List bytes) {
  if (bytes.length > kMaxEnvelopeBytes) {
    throw const EnvelopeTooLargeException('sobre demasiado grande');
  }
  if (bytes.length < _prefixLength ||
      bytes[0] != _magic0 ||
      bytes[1] != _magic1) {
    throw const EnvelopeFormatException('no es un sobre de Regalos');
  }
  if (bytes[2] != kFamilyEnvelopeVersion) {
    throw EnvelopeFormatException('versión ${bytes[2]} no soportada');
  }
  final hLen = (bytes[3] << 8) | bytes[4];
  if (hLen > kMaxFamilyHeaderBytes) {
    throw const EnvelopeFormatException('cabecera demasiado larga');
  }
  final aadEnd = _prefixLength + hLen;
  if (hLen == 0 ||
      bytes.length < aadEnd + _nonceLength + _macLength + _signatureLength) {
    throw const EnvelopeFormatException('sobre truncado');
  }
  final headerBytes = Uint8List.sublistView(bytes, _prefixLength, aadEnd);
  final Object? raw;
  try {
    raw = jsonDecode(utf8.decode(headerBytes));
  } on FormatException {
    throw const EnvelopeFormatException('cabecera dañada');
  }
  if (raw is! Map ||
      raw.length != _headerKeys.length ||
      !raw.keys.every(_headerKeys.contains) ||
      raw['v'] != kFamilyEnvelopeVersion ||
      raw['s'] != KeyScope.family) {
    throw const EnvelopeFormatException('cabecera no válida');
  }
  final l = raw['l'];
  final sid = raw['sid'];
  final e = raw['e'];
  final ctx = raw['ctx'];
  final kid = raw['kid'];
  final w = raw['w'];
  final wr = raw['wr'];
  final r = raw['r'];
  if (l is! String ||
      sid is! String ||
      !isJsonInt(e) ||
      ctx is! String ||
      kid is! String ||
      w is! String ||
      wr is! String ||
      !isJsonInt(r)) {
    throw const EnvelopeFormatException('cabecera no válida');
  }
  final header = FamilyEnvelopeHeader(
    listId: l,
    syncId: sid,
    epochNumber: e! as int,
    epochContext: ctx,
    kid: kid,
    writer: w,
    writerRecord: wr,
    revision: r! as int,
  );
  // Lo que se firma y autentica es la forma canónica: cualquier otra forma
  // de escribir lo mismo (claves repetidas, 1.0, escapes...) no se acepta.
  if (!constantTimeEquals(header._bytes(), headerBytes)) {
    throw const EnvelopeFormatException('cabecera no canónica');
  }
  return _Parsed(header, aadEnd);
}

/// Lee la cabecera sin autenticar nada (para saber de qué lista, escritor y
/// `kid` es). Lanza [EnvelopeException] si no es un sobre común firmado.
FamilyEnvelopeHeader peekFamilyEnvelope(Uint8List bytes) =>
    _parse(bytes).header;

/// Comprueba la estructura, la lista, la generación y la firma del escritor
/// sin descifrar (sirve para guardar o reenviar sin la clave) y devuelve la
/// cabecera autenticada.
///
/// Lanza [EnvelopeWrongListException] si es de otra lista o generación,
/// [EnvelopeUnknownWriterException] si [resolveWriter] no acepta al
/// escritor, [EnvelopeAuthException] si la firma no vale, y
/// [EnvelopeFormatException] o [EnvelopeTooLargeException] si los bytes no
/// valen.
Future<FamilyEnvelopeHeader> verifyFamilyEnvelope(
  Uint8List bytes, {
  required String expectedListId,
  required String expectedSyncId,
  required FamilyWriterResolver resolveWriter,
}) async => (await _verified(
  bytes,
  expectedListId: expectedListId,
  expectedSyncId: expectedSyncId,
  resolveWriter: resolveWriter,
)).header;

Future<_Parsed> _verified(
  Uint8List bytes, {
  required String expectedListId,
  required String expectedSyncId,
  required FamilyWriterResolver resolveWriter,
}) async {
  final parsed = _parse(bytes);
  final h = parsed.header;
  if (h.listId != expectedListId || h.syncId != expectedSyncId) {
    throw const EnvelopeWrongListException('el sobre es de otra lista');
  }
  final signingKey = await resolveWriter(h.writer, h.writerRecord);
  if (signingKey == null) {
    throw const EnvelopeUnknownWriterException('escritor no reconocido');
  }
  final sigStart = bytes.length - _signatureLength;
  final ok = await verifyDeviceSignature(
    message: familyEnvelopeSignedMessage(
      Uint8List.sublistView(bytes, 0, sigStart),
    ),
    signature: Uint8List.sublistView(bytes, sigStart),
    signingPublicKey: signingKey,
  );
  if (!ok) throw const EnvelopeAuthException('firma no válida');
  return parsed;
}

/// Abre un sobre común firmado: [verifyFamilyEnvelope], busca en [keyring]
/// la candidata exacta (lista, generación, época, contexto y `kid`), exige
/// que el escritor esté en su audiencia con su ficha, descifra, descomprime
/// con tope y lee el `FamilyDoc`, que tiene que ser de la misma lista.
///
/// Además de los errores de [verifyFamilyEnvelope], lanza
/// [EnvelopeMissingKeyException] si falta la candidata (el sobre se
/// conserva) y [EnvelopeAuthException] si el escritor no la conoce o el GCM
/// no cuadra.
Future<OpenedFamilyEnvelope> openFamilyEnvelope(
  Uint8List bytes, {
  required String expectedListId,
  required String expectedSyncId,
  required FamilyWriterResolver resolveWriter,
  required FamilyKeyring keyring,
}) async {
  final parsed = await _verified(
    bytes,
    expectedListId: expectedListId,
    expectedSyncId: expectedSyncId,
    resolveWriter: resolveWriter,
  );
  final h = parsed.header;
  final candidate = keyring.forOpening(
    listId: h.listId,
    syncId: h.syncId,
    epochNumber: h.epochNumber,
    epochContext: h.epochContext,
    kid: h.kid,
  );
  if (candidate == null) {
    throw const EnvelopeMissingKeyException('falta la clave común del sobre');
  }
  if (!_writerInAudience(candidate, h.writer, h.writerRecord)) {
    throw const EnvelopeAuthException(
      'el escritor no conoce la clave común del sobre',
    );
  }
  final nonceEnd = parsed.aadEnd + _nonceLength;
  final macStart = bytes.length - _signatureLength - _macLength;
  final List<int> body;
  try {
    body = await _aes.decrypt(
      SecretBox(
        Uint8List.sublistView(bytes, nonceEnd, macStart),
        nonce: Uint8List.sublistView(bytes, parsed.aadEnd, nonceEnd),
        mac: Mac(Uint8List.sublistView(bytes, macStart, macStart + _macLength)),
      ),
      secretKey: await _contentKey(candidate),
      aad: Uint8List.sublistView(bytes, 0, parsed.aadEnd),
    );
  } on SecretBoxAuthenticationError {
    throw const EnvelopeAuthException('clave equivocada o sobre manipulado');
  }
  final plain = inflateWithLimit(Uint8List.fromList(body));
  final FamilyDoc doc;
  try {
    final json = jsonDecode(utf8.decode(plain));
    if (json is! Map<String, Object?>) {
      throw const EnvelopeFormatException('documento no válido');
    }
    doc = FamilyDoc.fromJson(json);
  } on FormatException {
    throw const EnvelopeFormatException('documento no válido');
  }
  if (doc.listId != h.listId) {
    throw const EnvelopeWrongListException('el documento es de otra lista');
  }
  return OpenedFamilyEnvelope(header: h, doc: doc, candidate: candidate);
}
