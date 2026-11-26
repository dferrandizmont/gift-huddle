// Sobres cifrados y emparejamiento por QR. Dart puro (sin Flutter).
// Decisión: docs/adr/0001-compartir-sin-servidor.md.
//
// Formato del sobre (todo en bytes):
//   "RG" | 0x01 | uint16 BE = longitud de la cabecera | cabecera JSON UTF-8 |
//   nonce (12) | texto cifrado AES-256-GCM + etiqueta (16)
// AAD del GCM = los bytes desde "RG" hasta el final de la cabecera.
// Cuerpo = deflate en bruto (sin cabecera zlib) del JSON UTF-8 del documento,
// para que el navegador lo abra con DecompressionStream('deflate-raw').
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';

import 'exchange_file_names.dart';

/// Marcador provisional del dominio de los enlaces; se cambiará al tener dominio.
const kShareHost = 'regalos.example';

/// Tamaño máximo de un sobre (bytes).
const kMaxEnvelopeBytes = 2 * 1024 * 1024;

/// Tamaño máximo del documento descomprimido (bytes).
const kMaxPlainBytes = 8 * 1024 * 1024;

const _keyLength = 32;
const _nonceLength = 12;
const _macLength = 16;
const _version = 1;

/// Versión exterior del sobre que escribe 1.0.7 al exportar un fichero
/// `.gifthuddle` sin el formato 2 del común (el 2 es el sobre común firmado,
/// `family_envelope.dart`). 1.0.6 rechaza cualquier versión que no sea la 1
/// en [peekHeader] y en [open], antes de fusionar nada. 1.0.7 sigue leyendo
/// la 1 (ficheros anteriores) y la 3 solo cuando quien llama lo pide con
/// `acceptFileVersion` (los ficheros compartidos), nunca en la sincronización.
const kFileEnvelopeVersion = 3;
const _magic0 = 0x52; // R
const _magic1 = 0x47; // G
const _prefixLength = 5;
const _pairPrefix = 'regalos-pair:v1:';
const _maxNameChars = 40;
final _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

/// Máximo de caracteres del texto de emparejamiento tras el prefijo.
const _maxPairBodyChars = 4096;

// ---------------------------------------------------------------- errores

/// Base de los errores al abrir o interpretar un sobre.
abstract class EnvelopeException implements Exception {
  const EnvelopeException(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Bytes que no son un sobre válido, o versión no soportada.
class EnvelopeFormatException extends EnvelopeException {
  const EnvelopeFormatException(super.message);
}

/// El sobre es de otra lista.
class EnvelopeWrongListException extends EnvelopeException {
  const EnvelopeWrongListException(super.message);
}

/// Clave equivocada o bytes manipulados.
class EnvelopeAuthException extends EnvelopeException {
  const EnvelopeAuthException(super.message);
}

/// Sobre o documento descomprimido por encima de los límites.
class EnvelopeTooLargeException extends EnvelopeException {
  const EnvelopeTooLargeException(super.message);
}

/// Texto de emparejamiento (QR) no válido.
class PairingFormatException implements Exception {
  const PairingFormatException(this.message);
  final String message;

  @override
  String toString() => 'PairingFormatException: $message';
}

// ------------------------------------------------------------- base64url

/// Base64url sin relleno.
String encodeBase64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

final _b64Chars = RegExp(r'^[A-Za-z0-9_-]*$');

/// Decodifica base64url sin relleno (estricto). Lanza [FormatException].
Uint8List decodeBase64Url(String text) {
  if (!_b64Chars.hasMatch(text) || text.length % 4 == 1) {
    throw const FormatException('base64url no válido');
  }
  final padded = text.padRight((text.length + 3) ~/ 4 * 4, '=');
  return Uint8List.fromList(base64Url.decode(padded));
}

// ------------------------------------------------------------------ clave

Uint8List _randomBytes(int n) {
  final rnd = Random.secure();
  return Uint8List.fromList(List<int>.generate(n, (_) => rnd.nextInt(256)));
}

/// Clave de la familia: 32 bytes. Nunca aparece en `toString()`.
class FamilyKey {
  FamilyKey(List<int> bytes) : _bytes = Uint8List.fromList(bytes) {
    if (_bytes.length != _keyLength) {
      throw ArgumentError.value(
        _bytes.length,
        'bytes',
        'la clave debe tener $_keyLength bytes',
      );
    }
  }

  factory FamilyKey.fromBase64Url(String text) {
    final Uint8List bytes;
    try {
      bytes = decodeBase64Url(text.trim());
    } on FormatException {
      throw ArgumentError.value('…', 'text', 'clave base64url no válida');
    }
    return FamilyKey(bytes);
  }

  final Uint8List _bytes;

  static Future<FamilyKey> generate() async =>
      FamilyKey(_randomBytes(_keyLength));

  /// Copia de los bytes de la clave.
  Uint8List get bytes => Uint8List.fromList(_bytes);

  String toBase64Url() => encodeBase64Url(_bytes);

  @override
  bool operator ==(Object other) {
    if (other is! FamilyKey) return false;
    var diff = 0;
    for (var i = 0; i < _keyLength; i++) {
      diff |= _bytes[i] ^ other._bytes[i];
    }
    return diff == 0;
  }

  @override
  // Constante a propósito: no se deriva nada de la clave. No sirve como clave
  // de mapa ni de conjunto.
  int get hashCode => 0;

  @override
  String toString() => 'FamilyKey(…)';
}

// ------------------------------------------------------------ emparejado

/// Contenido del QR de emparejamiento.
class PairingPayload {
  PairingPayload({
    required this.listId,
    required this.key,
    required String deviceName,
  }) : deviceName = _clip(deviceName);

  final String listId;
  final FamilyKey key;

  /// Como máximo 40 caracteres.
  final String deviceName;

  static String _clip(String name) {
    // Quita controles y marcas de formato/bidi (\p{C}, p. ej. U+202E).
    final clean = name.replaceAll(RegExp(r'\p{C}', unicode: true), '').trim();
    final runes = clean.runes;
    if (runes.length <= _maxNameChars) return clean;
    return String.fromCharCodes(runes.take(_maxNameChars));
  }

  /// `regalos-pair:v1:<base64url(JSON {"v":1,"l":..,"k":..,"n":..})>`
  String toQrText() {
    final json = jsonEncode(<String, Object?>{
      'v': 1,
      'l': listId,
      'k': key.toBase64Url(),
      'n': deviceName,
    });
    return '$_pairPrefix${encodeBase64Url(utf8.encode(json))}';
  }

  static final _ws = RegExp(r'\s+');

  /// Lanza [PairingFormatException] si el texto no es válido.
  static PairingPayload parse(String text) {
    final clean = text.trim();
    if (!clean.startsWith(_pairPrefix)) {
      throw const PairingFormatException('no es un código de emparejamiento');
    }
    if (clean.length - _pairPrefix.length > _maxPairBodyChars) {
      throw const PairingFormatException('código demasiado largo');
    }
    final body = clean.substring(_pairPrefix.length).replaceAll(_ws, '');
    try {
      final raw = jsonDecode(utf8.decode(decodeBase64Url(body)));
      if (raw is! Map || raw['v'] != 1) {
        throw const PairingFormatException('versión no soportada');
      }
      final l = raw['l'];
      final k = raw['k'];
      final n = raw['n'];
      if (l is! String || !_idPattern.hasMatch(l)) {
        throw const PairingFormatException('lista no válida');
      }
      if (k is! String || n is! String) {
        throw const PairingFormatException('campos no válidos');
      }
      return PairingPayload(
        listId: l,
        key: FamilyKey.fromBase64Url(k),
        deviceName: n,
      );
    } on PairingFormatException {
      rethrow;
    } on FormatException {
      throw const PairingFormatException('código dañado');
    } on ArgumentError {
      throw const PairingFormatException('clave no válida');
    }
  }
}

// ---------------------------------------------------------------- sobres

/// Cabecera en claro (autenticada, no cifrada).
class EnvelopeHeader {
  const EnvelopeHeader({
    required this.listId,
    required this.fromNode,
    required this.at,
    this.kind = 'family',
    this.version = _version,
  });

  final String listId;
  final String fromNode;

  /// Marca HLC de quien envía.
  final String at;
  final String kind;
  final int version;

  @override
  String toString() =>
      'EnvelopeHeader(list: $listId, from: $fromNode, at: $at, kind: $kind)';
}

/// Resultado de [open].
class OpenedEnvelope {
  const OpenedEnvelope({required this.header, required this.doc});
  final EnvelopeHeader header;
  final Map<String, Object?> doc;
}

Uint8List _headerBytes(EnvelopeHeader h) => Uint8List.fromList(
  utf8.encode(
    // Claves ordenadas alfabéticamente, JSON compacto.
    jsonEncode(<String, Object?>{
      'at': h.at,
      'from': h.fromNode,
      'kind': h.kind,
      'l': h.listId,
      'v': h.version,
    }),
  ),
);

final _aes = AesGcm.with256bits();

/// Crea un sobre cifrado.
Future<Uint8List> seal({
  required Map<String, Object?> doc,
  required String listId,
  required String fromNode,
  required String at,
  required FamilyKey key,
  int version = _version,
}) => sealWithNonceForTesting(
  doc: doc,
  listId: listId,
  fromNode: fromNode,
  at: at,
  key: key,
  nonce: _randomBytes(_nonceLength),
  version: version,
);

/// Igual que [seal] pero con nonce dado. SOLO para pruebas y vectores fijos:
/// reutilizar un nonce con la misma clave rompe AES-GCM.
Future<Uint8List> sealWithNonceForTesting({
  required Map<String, Object?> doc,
  required String listId,
  required String fromNode,
  required String at,
  required FamilyKey key,
  required List<int> nonce,
  int version = _version,
}) async {
  if (version != _version && version != kFileEnvelopeVersion) {
    throw ArgumentError.value(version, 'version');
  }
  if (!_idPattern.hasMatch(listId)) {
    throw ArgumentError.value(listId, 'listId', 'identificador no válido');
  }
  if (nonce.length != _nonceLength) {
    throw ArgumentError.value(nonce.length, 'nonce', 'debe tener 12 bytes');
  }
  final plain = utf8.encode(jsonEncode(doc));
  if (plain.length > kMaxPlainBytes) {
    throw const EnvelopeTooLargeException('documento demasiado grande');
  }
  final body = Deflate(plain).getBytes();
  final header = _headerBytes(
    EnvelopeHeader(
      listId: listId,
      fromNode: fromNode,
      at: at,
      version: version,
    ),
  );
  if (header.length > 0xFFFF) {
    throw const EnvelopeFormatException('cabecera demasiado larga');
  }
  final prefix = BytesBuilder(copy: false)
    ..add([_magic0, _magic1, version])
    ..add([header.length >> 8, header.length & 0xFF])
    ..add(header);
  final aad = prefix.toBytes();
  final box = await _aes.encrypt(
    body,
    secretKey: SecretKey(key.bytes),
    nonce: nonce,
    aad: aad,
  );
  final out = BytesBuilder(copy: false)
    ..add(aad)
    ..add(nonce)
    ..add(box.cipherText)
    ..add(box.mac.bytes);
  final bytes = out.toBytes();
  if (bytes.length > kMaxEnvelopeBytes) {
    throw const EnvelopeTooLargeException('sobre demasiado grande');
  }
  return bytes;
}

class _Parsed {
  _Parsed(this.header, this.aadEnd);
  final EnvelopeHeader header;
  final int aadEnd;
}

_Parsed _parse(Uint8List bytes, {bool acceptFileVersion = false}) {
  if (bytes.length > kMaxEnvelopeBytes) {
    throw const EnvelopeTooLargeException('sobre demasiado grande');
  }
  if (bytes.length < _prefixLength ||
      bytes[0] != _magic0 ||
      bytes[1] != _magic1) {
    throw const EnvelopeFormatException('no es un sobre de Regalos');
  }
  final version = bytes[2];
  if (version != _version &&
      !(acceptFileVersion && version == kFileEnvelopeVersion)) {
    throw EnvelopeFormatException('versión $version no soportada');
  }
  final hLen = (bytes[3] << 8) | bytes[4];
  final aadEnd = _prefixLength + hLen;
  if (hLen == 0 || bytes.length < aadEnd + _nonceLength + _macLength) {
    throw const EnvelopeFormatException('sobre truncado');
  }
  final Object? raw;
  try {
    raw = jsonDecode(utf8.decode(bytes.sublist(_prefixLength, aadEnd)));
  } on FormatException {
    throw const EnvelopeFormatException('cabecera dañada');
  }
  if (raw is! Map) throw const EnvelopeFormatException('cabecera dañada');
  final l = raw['l'];
  final from = raw['from'];
  final at = raw['at'];
  if (raw['v'] != version ||
      raw['kind'] != 'family' ||
      l is! String ||
      !_idPattern.hasMatch(l) ||
      from is! String ||
      at is! String) {
    throw const EnvelopeFormatException('cabecera no válida');
  }
  return _Parsed(
    EnvelopeHeader(listId: l, fromNode: from, at: at, version: version),
    aadEnd,
  );
}

/// Lee la cabecera sin clave (para saber de qué lista es). No autentica.
EnvelopeHeader peekHeader(Uint8List bytes, {bool acceptFileVersion = false}) =>
    _parse(bytes, acceptFileVersion: acceptFileVersion).header;

/// Abre un sobre. Primero autentica y descifra; después comprueba la lista,
/// de modo que cualquier byte manipulado da error de autenticación.
Future<OpenedEnvelope> open(
  Uint8List bytes, {
  required FamilyKey key,
  required String expectedListId,
  bool acceptFileVersion = false,
}) async {
  final parsed = _parse(bytes, acceptFileVersion: acceptFileVersion);
  final aad = Uint8List.sublistView(bytes, 0, parsed.aadEnd);
  final nonceEnd = parsed.aadEnd + _nonceLength;
  final macStart = bytes.length - _macLength;
  final List<int> body;
  try {
    body = await _aes.decrypt(
      SecretBox(
        Uint8List.sublistView(bytes, nonceEnd, macStart),
        nonce: Uint8List.sublistView(bytes, parsed.aadEnd, nonceEnd),
        mac: Mac(Uint8List.sublistView(bytes, macStart)),
      ),
      secretKey: SecretKey(key.bytes),
      aad: aad,
    );
  } on SecretBoxAuthenticationError {
    throw const EnvelopeAuthException('clave equivocada o sobre manipulado');
  }
  if (parsed.header.listId != expectedListId) {
    throw const EnvelopeWrongListException('el sobre es de otra lista');
  }
  final plain = _inflateLimited(Uint8List.fromList(body));
  final Object? doc;
  try {
    doc = jsonDecode(utf8.decode(plain));
  } on FormatException {
    throw const EnvelopeFormatException('documento dañado');
  }
  if (doc is! Map) throw const EnvelopeFormatException('documento no válido');
  return OpenedEnvelope(
    header: parsed.header,
    doc: Map<String, Object?>.from(doc),
  );
}

/// Memoria con tope: lanza antes de escribir más allá de [kMaxPlainBytes] y
/// nunca reserva más de ese tope.
class _CappedOutput extends OutputMemoryStream {
  _CappedOutput() : super(size: 1024);

  int _capacity = 1024;
  bool exceeded = false;

  void _room(int extra) {
    final need = length + extra;
    if (need > kMaxPlainBytes) {
      exceeded = true;
      throw const EnvelopeTooLargeException('documento demasiado grande');
    }
    if (need > _capacity) {
      _capacity = min(max(_capacity * 2, need), kMaxPlainBytes);
      reserve(_capacity);
    }
  }

  @override
  void writeByte(int value) {
    _room(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _room(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _room(stream.length);
    super.writeStream(stream);
  }

  @override
  void writeBackReference(int distance, int count) {
    _room(count);
    super.writeBackReference(distance, count);
  }
}

/// Descomprime deflate en bruto sin pasar de [kMaxPlainBytes]. Lanza
/// [EnvelopeTooLargeException] o [EnvelopeFormatException]. La usan también
/// los slots de sorpresas (`protected_envelope.dart`).
Uint8List inflateWithLimit(Uint8List compressed) => _inflateLimited(compressed);

Uint8List _inflateLimited(Uint8List compressed) {
  final out = _CappedOutput();
  try {
    // Sin throwOnError (en archive 4.6.0 no cambia nada): los fallos salen por
    // la excepción del flujo o por isFinished.
    final inflate = Inflate(compressed, output: out);
    if (!inflate.isFinished) {
      throw const EnvelopeFormatException('cuerpo comprimido truncado');
    }
  } on EnvelopeException {
    rethrow;
  } catch (_) {
    if (out.exceeded) {
      throw const EnvelopeTooLargeException('documento demasiado grande');
    }
    throw const EnvelopeFormatException('cuerpo comprimido dañado');
  }
  return out.getBytes();
}

// -------------------------------------------------------- formas de texto

/// `https://<host>/s#<base64url>`
String envelopeToLink(Uint8List envelope) =>
    'https://$kShareHost/s#${encodeBase64Url(envelope)}';

/// Acepta el enlace completo, solo el fragmento o el base64url suelto,
/// ignorando espacios y saltos de línea que meta una app de mensajería.
Uint8List parseShared(String text) {
  var s = text.replaceAll(RegExp(r'\s+'), '');
  final hash = s.indexOf('#');
  if (hash >= 0) {
    s = s.substring(hash + 1);
  } else if (s.contains('/') || s.contains(':')) {
    throw const EnvelopeFormatException('enlace sin sobre');
  }
  if (s.isEmpty) throw const EnvelopeFormatException('sobre vacío');
  if (s.length > kMaxEnvelopeBytes * 4 ~/ 3 + 4) {
    throw const EnvelopeTooLargeException('sobre demasiado grande');
  }
  try {
    return decodeBase64Url(s);
  } on FormatException {
    throw const EnvelopeFormatException('texto base64url no válido');
  }
}

/// `gift-huddle-AAAAMMDD-HHMM.gifthuddle`
String envelopeFileName(DateTime t) {
  String p(int n, int w) => n.toString().padLeft(w, '0');
  return 'gift-huddle-${p(t.year, 4)}${p(t.month, 2)}${p(t.day, 2)}'
      '-${p(t.hour, 2)}${p(t.minute, 2)}$kExchangeFileExtension';
}
