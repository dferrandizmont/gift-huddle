// Código de recuperación (R-b) y copia cifrada exportable (R-c). Dart puro.
// Cápsula remota v2: ADR 0007, implementada en recovery_capsule.dart; el
// formato v1 descrito aquí sigue siendo exclusivo de las copias anteriores.
// Decisión: docs/adr/0004-yo-sorpresas-revocar.md (recuperación R-a + R-b +
// R-c). El código E también se puede guardar en un fichero GHK v1 (abierto o
// con contraseña): ADR 0008, implementado en recovery_file.dart; abrirlo da
// `RecoveryCode(E)` y desde ahí todo es igual que con las palabras.
//
// Código: 32 bytes aleatorios generados en el móvil, que se enseñan como 24
// palabras BIP-39 de la lista **inglesa** (con su suma de control de 8 bits)
// o como texto de QR `gift-huddle-recovery:v1:<base64url(32 bytes ‖ suma)>`.
// Por qué la inglesa: es solo ASCII (sin tildes ni la ñ, que dan problemas al
// teclear y en NFKD), sus cuatro primeras letras ya identifican cada palabra,
// es la que acepta cualquier gestor de contraseñas o herramienta BIP-39, y
// tiene vectores de prueba públicos. Solo se usa la codificación de BIP-39
// (entropía ↔ palabras), no su derivación de semilla.
// Lista: `assets/recovery/bip39-english.txt` (MIT, trezor/python-mnemonic).
//
// Clave: Argon2id (RFC 9106, implementación en Dart puro de `cryptography`)
// con contraseña = los 32 bytes del código, sal aleatoria de 16 bytes y datos
// asociados "gift-huddle-recovery-v1". Parámetros por defecto: 19 MiB, 2
// pasadas, 1 hilo (el mínimo de OWASP), unos 0,25 s en un PC y del orden de
// 1 s en un móvil. El código ya tiene 256 bits de entropía, así que Argon2id
// es defensa en profundidad, no lo que lo hace seguro.
//
// Fichero (`.regalos` de copia):
//   "GHR" | 0x01 | uint16 BE = longitud de la cabecera | cabecera JSON |
//   nonce (12) | AES-256-GCM(deflate en bruto del JSON del contenido) +
//   etiqueta (16)
//   cabecera = JSON canónico {"k": "keys" | "backup",
//     "kdf": {"a": "argon2id", "m": KiB, "p": hilos, "t": pasadas},
//     "s": sal (base64url), "v": 1}
//   AAD del GCM = todo lo anterior al nonce.
// Contenido: {"v":1, "k": tipo, "l": listId, "fk": familyKey, "dev": id del
// móvil, "self": persona de «Yo» o null, "dk": claves del móvil, "sk":
// llavero de sorpresas} y, en el tipo "backup" (R-c), además "doc" (el
// documento común) y "slots" (los slots tal como están, cifrados).
//
// La copia nunca lleva la clave de las sorpresas de la persona de «Yo»: este
// móvil no la tiene, y aunque la tuviera se quita al sellar.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:meta/meta.dart';

import '../platform/task_runner.dart';

import 'access_policy.dart';
import 'device_keys.dart';
import 'envelope.dart'
    show
        EnvelopeException,
        FamilyKey,
        decodeBase64Url,
        encodeBase64Url,
        inflateWithLimit;
import 'exchange_file_names.dart';
import 'family_doc.dart';
import 'family_candidate.dart';
import 'family_key_bundle.dart';
import 'device_registry.dart';
import 'hlc.dart';
import 'key_bundle.dart';
import 'pairing_v2.dart' show SyncIdentityV2;
import 'recovery_locator.dart';
import 'protected_doc.dart' show parseSlotList;
import 'protected_envelope.dart' show SealedSlot;

part 'recovery_capsule.dart';

/// SHA-256 de la lista inglesa de BIP-39 (2048 palabras separadas por "\n",
/// con "\n" al final), la misma que la de bitcoin/bips.
const String kBip39EnglishSha256 =
    '2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda';

/// Ruta del asset con la lista de palabras.
const String kRecoveryWordlistAsset = 'assets/recovery/bip39-english.txt';

/// Palabras del código.
const int kRecoveryWordCount = 24;

const _entropyLength = 32;
const _qrPrefix = 'gift-huddle-recovery:v1:';
const _magic = [0x47, 0x48, 0x52]; // "GHR"
const _version = 1;
const _prefixLength = 6;
const _saltLength = 16;
const _nonceLength = 12;
const _macLength = 16;
const _kdfAssociated = 'gift-huddle-recovery-v1';

/// Un código o una copia que no vale.
class RecoveryException implements Exception {
  /// Crea el error.
  const RecoveryException(this.message);

  /// Qué pasó (sin secretos).
  final String message;

  @override
  String toString() => 'RecoveryException: $message';
}

/// La lista de 2048 palabras de BIP-39.
class RecoveryWordlist {
  RecoveryWordlist._(this.words)
    : _index = {for (var i = 0; i < words.length; i++) words[i]: i};

  /// Lee el texto del asset (una palabra por línea). Lanza
  /// [RecoveryException] si no es exactamente la lista inglesa de BIP-39.
  factory RecoveryWordlist.parse(String text) {
    final words = [
      for (final line in const LineSplitter().convert(text))
        if (line.trim().isNotEmpty) line.trim(),
    ];
    final canonical = utf8.encode('${words.join('\n')}\n');
    final digest = const DartSha256().hashSync(canonical).bytes;
    final hex = [for (final b in digest) b.toRadixString(16).padLeft(2, '0')]
        .join();
    if (words.length != 2048 || hex != kBip39EnglishSha256) {
      throw const RecoveryException('lista de palabras no válida');
    }
    return RecoveryWordlist._(List.unmodifiable(words));
  }

  /// Las palabras, en orden.
  final List<String> words;

  final Map<String, int> _index;

  /// El índice de [word] (exacta, o sus primeras cuatro letras o más si solo
  /// encajan con una palabra), o null.
  int? indexOf(String word) {
    final exact = _index[word];
    if (exact != null || word.length < 4) return exact;
    int? found;
    for (var i = 0; i < words.length; i++) {
      if (words[i].startsWith(word)) {
        if (found != null) return null;
        found = i;
      }
    }
    return found;
  }
}

/// El código de recuperación: 32 bytes. Nunca aparece en `toString()`.
class RecoveryCode {
  /// Crea el código. Lanza [ArgumentError] si no tiene 32 bytes.
  RecoveryCode(List<int> entropy) : _entropy = Uint8List.fromList(entropy) {
    if (_entropy.length != _entropyLength) {
      throw ArgumentError.value(_entropy.length, 'entropy', 'deben ser 32');
    }
  }

  /// Un código nuevo y aleatorio.
  factory RecoveryCode.generate() =>
      RecoveryCode(secureRandomBytes(_entropyLength));

  final Uint8List _entropy;

  /// Copia de los 32 bytes.
  Uint8List get entropy => Uint8List.fromList(_entropy);

  static int _checksum(List<int> entropy) =>
      const DartSha256().hashSync(entropy).bytes[0];

  /// Las 24 palabras (BIP-39).
  List<String> toWords(RecoveryWordlist wordlist) {
    final bits = BigInt.parse(
      [
        for (final b in [..._entropy, _checksum(_entropy)])
          b.toRadixString(2).padLeft(8, '0'),
      ].join(),
      radix: 2,
    );
    return [
      for (var i = kRecoveryWordCount - 1; i >= 0; i--)
        wordlist.words[((bits >> (11 * i)) & BigInt.from(0x7FF)).toInt()],
    ];
  }

  /// Lee las 24 palabras (separadas por espacios o saltos de línea, sin
  /// importar mayúsculas). Lanza [RecoveryException] si sobra o falta una,
  /// si alguna no está en la lista o si la suma de control no cuadra.
  factory RecoveryCode.fromWords(String text, RecoveryWordlist wordlist) {
    final parts = text
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (parts.length != kRecoveryWordCount) {
      throw const RecoveryException('el código tiene 24 palabras');
    }
    var bits = BigInt.zero;
    for (final word in parts) {
      final index = wordlist.indexOf(word);
      if (index == null) {
        throw const RecoveryException('hay una palabra que no es del código');
      }
      bits = (bits << 11) | BigInt.from(index);
    }
    final bytes = Uint8List(_entropyLength + 1);
    for (var i = bytes.length - 1; i >= 0; i--) {
      bytes[i] = (bits & BigInt.from(0xFF)).toInt();
      bits >>= 8;
    }
    final entropy = bytes.sublist(0, _entropyLength);
    if (_checksum(entropy) != bytes[_entropyLength]) {
      throw const RecoveryException('el código no es correcto');
    }
    return RecoveryCode(entropy);
  }

  /// El texto del QR imprimible.
  String toQrText() =>
      '$_qrPrefix${encodeBase64Url([..._entropy, _checksum(_entropy)])}';

  /// Lee [toQrText]. Lanza [RecoveryException] si no vale.
  factory RecoveryCode.fromQrText(String text) {
    final clean = text.trim();
    if (!clean.startsWith(_qrPrefix)) {
      throw const RecoveryException('no es un código de recuperación');
    }
    final Uint8List bytes;
    try {
      bytes = decodeBase64Url(clean.substring(_qrPrefix.length));
    } on FormatException {
      throw const RecoveryException('código dañado');
    }
    if (bytes.length != _entropyLength + 1) {
      throw const RecoveryException('código dañado');
    }
    final entropy = bytes.sublist(0, _entropyLength);
    if (_checksum(entropy) != bytes[_entropyLength]) {
      throw const RecoveryException('el código no es correcto');
    }
    return RecoveryCode(entropy);
  }

  @override
  String toString() => 'RecoveryCode(…)';
}

/// Parámetros de Argon2id. Al leer una copia se acotan, para que un fichero
/// hecho a mala fe no bloquee el móvil.
class RecoveryKdfParams {
  /// Crea los parámetros.
  const RecoveryKdfParams({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
  });

  /// Por defecto: 19 MiB, 2 pasadas, 1 hilo.
  static const RecoveryKdfParams standard = RecoveryKdfParams(
    memoryKiB: 19456,
    iterations: 2,
    parallelism: 1,
  );

  /// Memoria en KiB.
  final int memoryKiB;

  /// Pasadas.
  final int iterations;

  /// Hilos.
  final int parallelism;

  bool get _valid =>
      parallelism >= 1 &&
      parallelism <= 4 &&
      iterations >= 1 &&
      iterations <= 4 &&
      memoryKiB >= 8 * parallelism &&
      memoryKiB <= 64 * 1024;

  Map<String, Object?> _toJson() => <String, Object?>{
    'a': 'argon2id',
    'm': memoryKiB,
    'p': parallelism,
    't': iterations,
  };

  static RecoveryKdfParams _fromJson(Object? json) {
    if (json is! Map || json['a'] != 'argon2id') {
      throw const RecoveryException('derivación no soportada');
    }
    final m = json['m'];
    final t = json['t'];
    final p = json['p'];
    if (m is! int || t is! int || p is! int) {
      throw const RecoveryException('derivación no válida');
    }
    final params = RecoveryKdfParams(
      memoryKiB: m,
      iterations: t,
      parallelism: p,
    );
    if (!params._valid) {
      throw const RecoveryException('derivación fuera de rango');
    }
    return params;
  }
}

/// La clave que cifra la copia: Argon2id del código, en otro isolate (en la
/// web, en el mismo) para no congelar la interfaz. Los parámetros están
/// acotados a 64 MiB, 4 pasadas y 4 hilos (revisión de seguridad, B3).
Future<Uint8List> deriveRecoveryKey(
  RecoveryCode code,
  List<int> salt,
  RecoveryKdfParams params,
) async {
  if (!params._valid) {
    throw const RecoveryException('derivación fuera de rango');
  }
  final entropy = code.entropy;
  final saltCopy = Uint8List.fromList(salt);
  final memory = params.memoryKiB;
  final iterations = params.iterations;
  final parallelism = params.parallelism;
  return runTask(
    () => _argon2id(entropy, saltCopy, memory, iterations, parallelism),
  );
}

Future<Uint8List> _argon2id(
  Uint8List entropy,
  Uint8List salt,
  int memory,
  int iterations,
  int parallelism, [
  String associated = _kdfAssociated,
]) async {
  final key =
      await DartArgon2id(
        parallelism: parallelism,
        memory: memory,
        iterations: iterations,
        hashLength: 32,
        maxIsolates: 1,
      ).deriveKey(
        secretKey: SecretKey(entropy),
        nonce: salt,
        associatedData: utf8.encode(associated),
      );
  return Uint8List.fromList(await key.extractBytes());
}

/// Qué lleva una copia.
enum RecoveryKind {
  /// R-b: solo las claves (de la familia, del móvil y de sorpresas).
  keys,

  /// R-c: las claves, el documento común y los slots.
  backup,
}

/// El contenido de una copia de recuperación.
class RecoveryPayload {
  /// Crea el contenido. Con [RecoveryKind.backup] hacen falta [common] y
  /// [slots].
  RecoveryPayload({
    required this.kind,
    required this.listId,
    required this.familyKey,
    required this.deviceId,
    required this.selfRecipientId,
    required this.deviceKeys,
    required SurpriseKeyring surpriseKeys,
    this.common,
    this.slots,
  }) : surpriseKeys = selfRecipientId == null
           ? surpriseKeys
           : surpriseKeys.without(selfRecipientId) {
    if (kind == RecoveryKind.backup && (common == null || slots == null)) {
      throw ArgumentError('una copia completa lleva documento y slots');
    }
  }

  /// Tipo de copia.
  final RecoveryKind kind;

  /// Lista.
  final String listId;

  /// Clave de la familia.
  final FamilyKey familyKey;

  /// Id de este móvil (el nodo del reloj).
  final String deviceId;

  /// La persona de «Yo» de este móvil, o null.
  final String? selfRecipientId;

  /// Claves de este móvil.
  final DeviceKeys deviceKeys;

  /// Claves de sorpresa (nunca las de [selfRecipientId]).
  final SurpriseKeyring surpriseKeys;

  /// Documento común (solo en [RecoveryKind.backup]).
  final FamilyDoc? common;

  /// Slots tal como están, cifrados (solo en [RecoveryKind.backup]). Al
  /// restaurar se verifican con `SlotSet.verified` antes de usarlos.
  final List<SealedSlot>? slots;

  Map<String, Object?> _toJson() => <String, Object?>{
    'v': _version,
    'k': kind.name,
    'l': listId,
    'fk': familyKey.toBase64Url(),
    'dev': deviceId,
    'self': selfRecipientId,
    'dk': deviceKeys.toJson(),
    'sk': surpriseKeys.toJson(),
    if (kind == RecoveryKind.backup) 'doc': common!.toJson(),
    if (kind == RecoveryKind.backup)
      'slots': [for (final s in slots!) encodeBase64Url(s.bytes)],
  };

  static Future<RecoveryPayload> _fromJson(
    Object? json,
    RecoveryKind expected,
  ) async {
    if (json is! Map || json['v'] != _version || json['k'] != expected.name) {
      throw const RecoveryException('copia no válida');
    }
    final l = json['l'];
    final fk = json['fk'];
    final dev = json['dev'];
    final self = json['self'];
    final dk = json['dk'];
    if (l is! String ||
        !kSyncIdPattern.hasMatch(l) ||
        fk is! String ||
        dev is! String ||
        dev.isEmpty ||
        (self != null && self is! String) ||
        dk is! Map) {
      throw const RecoveryException('copia no válida');
    }
    try {
      FamilyDoc? common;
      List<SealedSlot>? slots;
      if (expected == RecoveryKind.backup) {
        final doc = json['doc'];
        if (doc is! Map) throw const FormatException('documento');
        common = FamilyDoc.fromJson(Map<String, Object?>.from(doc));
        if (common.listId != l) throw const FormatException('lista');
        slots = parseSlotList(json['slots']);
      }
      return RecoveryPayload(
        kind: expected,
        listId: l,
        familyKey: FamilyKey.fromBase64Url(fk),
        deviceId: dev,
        selfRecipientId: self as String?,
        deviceKeys: await DeviceKeys.fromJson(Map<String, Object?>.from(dk)),
        surpriseKeys: SurpriseKeyring.fromJson(json['sk']),
        common: common,
        slots: slots,
      );
    } on RecoveryException {
      rethrow;
    } catch (_) {
      throw const RecoveryException('copia dañada');
    }
  }
}

/// Cifra [payload] con el código.
Future<Uint8List> sealRecovery(
  RecoveryPayload payload,
  RecoveryCode code, {
  RecoveryKdfParams params = RecoveryKdfParams.standard,
}) => _sealRecovery(payload, code, params: params);

/// Igual que [sealRecovery] con la sal y el nonce dados: SOLO para pruebas y
/// vectores fijos.
@visibleForTesting
Future<Uint8List> sealRecoveryForTesting(
  RecoveryPayload payload,
  RecoveryCode code, {
  required RecoveryKdfParams params,
  required List<int> salt,
  required List<int> nonce,
}) => _sealRecovery(payload, code, params: params, salt: salt, nonce: nonce);

Future<Uint8List> _sealRecovery(
  RecoveryPayload payload,
  RecoveryCode code, {
  required RecoveryKdfParams params,
  List<int>? salt,
  List<int>? nonce,
}) async {
  final s = salt ?? secureRandomBytes(_saltLength);
  final n = nonce ?? secureRandomBytes(_nonceLength);
  if (s.length != _saltLength || n.length != _nonceLength) {
    throw ArgumentError('sal de 16 bytes y nonce de 12');
  }
  final header = utf8.encode(
    canonicalJsonOf(<String, Object?>{
      'k': payload.kind.name,
      'kdf': params._toJson(),
      's': encodeBase64Url(s),
      'v': _version,
    }),
  );
  final aad = Uint8List.fromList([
    ..._magic,
    _version,
    header.length >> 8,
    header.length & 0xFF,
    ...header,
  ]);
  final key = await deriveRecoveryKey(code, s, params);
  final body = Deflate(utf8.encode(canonicalJsonOf(payload._toJson())))
      .getBytes();
  final box = await AesGcm.with256bits().encrypt(
    body,
    secretKey: SecretKey(key),
    nonce: n,
    aad: aad,
  );
  return Uint8List.fromList([
    ...aad,
    ...n,
    ...box.cipherText,
    ...box.mac.bytes,
  ]);
}

/// El tipo de una copia, sin abrirla. Lanza [RecoveryException].
RecoveryKind peekRecoveryKind(Uint8List bytes) => _parse(bytes).kind;

/// Abre una copia con el código. Lanza [RecoveryException] si el código no
/// es el suyo, si está manipulada o si no es una copia.
Future<RecoveryPayload> openRecovery(Uint8List bytes, RecoveryCode code) async {
  final parsed = _parse(bytes);
  final key = await deriveRecoveryKey(code, parsed.salt, parsed.params);
  final nonceEnd = parsed.aadEnd + _nonceLength;
  final macStart = bytes.length - _macLength;
  final List<int> body;
  try {
    body = await AesGcm.with256bits().decrypt(
      SecretBox(
        Uint8List.sublistView(bytes, nonceEnd, macStart),
        nonce: Uint8List.sublistView(bytes, parsed.aadEnd, nonceEnd),
        mac: Mac(Uint8List.sublistView(bytes, macStart)),
      ),
      secretKey: SecretKey(key),
      aad: Uint8List.sublistView(bytes, 0, parsed.aadEnd),
    );
  } on SecretBoxAuthenticationError {
    throw const RecoveryException('código equivocado o copia manipulada');
  }
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(inflateWithLimit(Uint8List.fromList(body))));
  } on EnvelopeException {
    throw const RecoveryException('copia dañada');
  } on FormatException {
    throw const RecoveryException('copia dañada');
  }
  return RecoveryPayload._fromJson(json, parsed.kind);
}

/// `gift-huddle-copia-AAAAMMDD-HHMM.gifthuddle`
String recoveryFileName(DateTime t) {
  String p(int n, int w) => n.toString().padLeft(w, '0');
  return 'gift-huddle-copia-${p(t.year, 4)}${p(t.month, 2)}${p(t.day, 2)}'
      '-${p(t.hour, 2)}${p(t.minute, 2)}$kExchangeFileExtension';
}

class _ParsedRecovery {
  _ParsedRecovery(this.kind, this.params, this.salt, this.aadEnd);
  final RecoveryKind kind;
  final RecoveryKdfParams params;
  final Uint8List salt;
  final int aadEnd;
}

_ParsedRecovery _parse(Uint8List bytes) {
  if (bytes.length < _prefixLength + _nonceLength + _macLength) {
    throw const RecoveryException('no es una copia de recuperación');
  }
  for (var i = 0; i < _magic.length; i++) {
    if (bytes[i] != _magic[i]) {
      throw const RecoveryException('no es una copia de recuperación');
    }
  }
  if (bytes[3] != _version) {
    throw const RecoveryException('versión de copia no soportada');
  }
  final length = (bytes[4] << 8) | bytes[5];
  final aadEnd = _prefixLength + length;
  if (length == 0 || bytes.length < aadEnd + _nonceLength + _macLength) {
    throw const RecoveryException('copia truncada');
  }
  try {
    final raw = jsonDecode(utf8.decode(bytes.sublist(_prefixLength, aadEnd)));
    if (raw is! Map || raw['v'] != _version) {
      throw const RecoveryException('copia no válida');
    }
    final kind = RecoveryKind.values.where((k) => k.name == raw['k']);
    final s = raw['s'];
    if (kind.isEmpty || s is! String) {
      throw const RecoveryException('copia no válida');
    }
    final salt = decodeBase64Url(s);
    if (salt.length != _saltLength) {
      throw const RecoveryException('copia no válida');
    }
    return _ParsedRecovery(
      kind.single,
      RecoveryKdfParams._fromJson(raw['kdf']),
      salt,
      aadEnd,
    );
  } on RecoveryException {
    rethrow;
  } on FormatException {
    throw const RecoveryException('copia dañada');
  }
}
