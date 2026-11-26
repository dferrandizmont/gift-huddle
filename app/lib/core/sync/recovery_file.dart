// Fichero de recuperación GHK v1: guarda solo el código de recuperación E
// (32 bytes, ADR 0007) en un fichero, abierto o protegido con contraseña.
// Especificación: docs/adr/0008-codigo-en-fichero.md. Vectores normativos:
// docs/adr/0008-vector-fichero.json (tool/recovery_file_vectors.py). Dart puro.
//
// Abierta (por defecto):
//   47 48 4B 01 | uint16BE(len(h)) | h = {"k":"recovery-file-open","v":1} |
//   E[32] | check[8]
//   check = SHA-256(UTF8("gift-huddle-recovery-file-open-v1") ‖ 00 ‖ E)[0..8]
// Protegida:
//   47 48 4B 01 | uint16BE(len(h)) | h = {"k":"recovery-file","kdf":{"a":
//   "argon2id","m":65536,"p":1,"t":3},"s":<sal>,"v":1} | nonce[12] |
//   AES-256-GCM(E)[32] | tag[16]
//   clave = Argon2id(UTF8(P), sal, AD = "gift-huddle-recovery-file-v1"),
//   AAD del GCM = todo hasta el final de la cabecera.
//
// La contraseña P llega YA normalizada a NFC (lo hace la plataforma, ver
// `DocumentExchange.normalizeNfc`). Aquí no se recorta ni se cambia nada.
//
// Lectura estricta, todo antes de derivar: tope de 512 bytes, magia exacta,
// versión 1 (otra → [RecoveryFileFailure.newerVersion]), cabecera de 1 a 256
// bytes en UTF-8 estricto, objeto JSON con los campos y tipos exactos que al
// re-serializar canónicamente da los mismos bytes, perfil de Argon2 exacto,
// sal base64url canónica de 16 bytes y longitud total exacta. Cualquier fallo
// anterior a Argon2 (también la suma de control de la variante abierta) es
// [RecoveryFileFailure.notRecoveryFile]; uno del GCM,
// [RecoveryFileFailure.damagedOrWrongPassword].
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:meta/meta.dart';

import '../platform/task_runner.dart';
import 'device_keys.dart' show constantTimeEquals, secureRandomBytes;
import 'envelope.dart' show decodeBase64Url, encodeBase64Url;
import 'family_doc.dart' show canonicalJsonOf;
import 'recovery.dart' show RecoveryCode;

/// Lo más que puede medir un fichero de recuperación. La plataforma rechaza
/// lo que pase de aquí sin leerlo entero.
const int kRecoveryFileMaxBytes = 512;

/// Lo más que puede medir su cabecera JSON.
const int kRecoveryFileMaxHeaderBytes = 256;

/// Versión del contenedor que escribe esta app (1.0.7). 1.0.6 solo lee la 1
/// y da `newerVersion` ante esta, antes de leer nada más.
const int kRecoveryFileVersion = 2;

/// Versión que escribía 1.0.6. 1.0.7 todavía la lee.
const int kRecoveryFileVersionLegacy = 1;

/// Perfil de Argon2id de la variante protegida. Es **exacto**: el lector
/// rechaza cualquier otro. Si la medición del ADR 0008 lo pide, se cambia a
/// t = 2 aquí (y en el script de vectores) antes de publicar.
const int kRecoveryFileKdfMemoryKiB = 65536;

/// Pasadas de Argon2id (ver [kRecoveryFileKdfMemoryKiB]).
const int kRecoveryFileKdfIterations = 3;

/// Hilos de Argon2id (ver [kRecoveryFileKdfMemoryKiB]).
const int kRecoveryFileKdfParallelism = 1;

/// Longitud mínima de una contraseña nueva, en runas tras NFC.
const int kRecoveryPasswordMinRunes = 15;

/// Longitud máxima de una contraseña nueva, en runas tras NFC.
const int kRecoveryPasswordMaxRunes = 128;

const _magic = [0x47, 0x48, 0x4B]; // "GHK"
const _prefixLength = 6;
const _entropyLength = 32;
const _checkLength = 8;
const _saltLength = 16;
const _nonceLength = 12;
const _tagLength = 16;
const _kindOpen = 'recovery-file-open';
const _kindProtected = 'recovery-file';
const _kdfAssociated = 'gift-huddle-recovery-file-v1';
const _checkDomain = 'gift-huddle-recovery-file-open-v1';

/// Variante del fichero.
enum RecoveryFileVariant {
  /// E en claro con suma de control: equivale a las palabras impresas.
  open,

  /// E cifrada con una contraseña.
  protected,
}

/// Por qué no se pudo abrir un fichero. La interfaz lo traduce.
enum RecoveryFileFailure {
  /// No es un fichero de recuperación válido (cualquier fallo antes de
  /// Argon2, también un fichero abierto dañado).
  notRecoveryFile,

  /// Es de una versión más nueva: hay que actualizar la app.
  newerVersion,

  /// Contraseña incorrecta o fichero dañado (indistinguibles a propósito).
  damagedOrWrongPassword,
}

/// Un fichero de recuperación que no se pudo abrir. Nunca lleva secretos.
class RecoveryFileException implements Exception {
  /// Crea el error.
  const RecoveryFileException(this.failure);

  /// El motivo.
  final RecoveryFileFailure failure;

  @override
  String toString() => 'RecoveryFileException(${failure.name})';
}

Never _invalid() =>
    throw const RecoveryFileException(RecoveryFileFailure.notRecoveryFile);

/// Detector barato por la magia «GHK» (de cualquier versión), para enviar el
/// fichero al flujo de recuperación antes del importador de sobres. No valida
/// nada más: eso lo hace [parseRecoveryFile].
bool isRecoveryFile(List<int> bytes) =>
    bytes.length >= _magic.length &&
    bytes[0] == _magic[0] &&
    bytes[1] == _magic[1] &&
    bytes[2] == _magic[2];

/// Un fichero ya validado, listo para abrir. Trabaja sobre su propia copia de
/// los bytes.
class RecoveryFile {
  RecoveryFile._(this.variant, this._bytes, this._aadEnd, this._salt);

  /// La variante.
  final RecoveryFileVariant variant;

  final Uint8List _bytes;
  final int _aadEnd;
  final Uint8List? _salt;

  /// Si hace falta contraseña para abrirlo.
  bool get needsPassword => variant == RecoveryFileVariant.protected;

  @override
  String toString() => 'RecoveryFile(${variant.name})';
}

/// Valida [bytes] con todas las reglas de lectura del ADR 0008 sin derivar
/// nada. Lanza [RecoveryFileException].
RecoveryFile parseRecoveryFile(List<int> bytes) {
  if (bytes.length > kRecoveryFileMaxBytes || !isRecoveryFile(bytes)) {
    _invalid();
  }
  final copy = Uint8List.fromList(bytes);
  if (copy.length < 4) _invalid();
  final fileVersion = copy[3];
  if (fileVersion != kRecoveryFileVersion &&
      fileVersion != kRecoveryFileVersionLegacy) {
    throw const RecoveryFileException(RecoveryFileFailure.newerVersion);
  }
  if (copy.length < _prefixLength) _invalid();
  final length = (copy[4] << 8) | copy[5];
  final aadEnd = _prefixLength + length;
  if (length == 0 ||
      length > kRecoveryFileMaxHeaderBytes ||
      copy.length < aadEnd) {
    _invalid();
  }
  final Map<String, Object?> header;
  try {
    final headerBytes = Uint8List.sublistView(copy, _prefixLength, aadEnd);
    final raw = jsonDecode(utf8.decode(headerBytes));
    // Bytes exactos, no texto: un BOM u otra rareza que el decodificador
    // trague no pasa.
    if (raw is! Map<String, Object?> ||
        !_sameBytes(utf8.encode(canonicalJsonOf(raw)), headerBytes)) {
      _invalid();
    }
    header = raw;
  } on FormatException {
    _invalid();
  }
  final v = header['v'];
  if (v is! int || v != fileVersion) _invalid();
  switch (header['k']) {
    case _kindOpen:
      _fields(header, const {'k', 'v'});
      if (copy.length != aadEnd + _entropyLength + _checkLength) _invalid();
      final entropyEnd = aadEnd + _entropyLength;
      if (!constantTimeEquals(
        Uint8List.sublistView(copy, entropyEnd),
        _check(Uint8List.sublistView(copy, aadEnd, entropyEnd)),
      )) {
        _invalid();
      }
      return RecoveryFile._(RecoveryFileVariant.open, copy, aadEnd, null);
    case _kindProtected:
      _fields(header, const {'k', 'kdf', 's', 'v'});
      final kdf = header['kdf'];
      if (kdf is! Map<String, Object?>) _invalid();
      _fields(kdf, const {'a', 'm', 'p', 't'});
      final m = kdf['m'];
      final p = kdf['p'];
      final t = kdf['t'];
      if (kdf['a'] != 'argon2id' ||
          m is! int ||
          p is! int ||
          t is! int ||
          m != kRecoveryFileKdfMemoryKiB ||
          p != kRecoveryFileKdfParallelism ||
          t != kRecoveryFileKdfIterations) {
        _invalid();
      }
      final s = header['s'];
      if (s is! String) _invalid();
      final Uint8List salt;
      try {
        salt = decodeBase64Url(s);
      } on FormatException {
        _invalid();
      }
      if (salt.length != _saltLength || encodeBase64Url(salt) != s) _invalid();
      if (copy.length != aadEnd + _nonceLength + _entropyLength + _tagLength) {
        _invalid();
      }
      return RecoveryFile._(RecoveryFileVariant.protected, copy, aadEnd, salt);
    default:
      _invalid();
  }
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void _fields(Map<String, Object?> value, Set<String> fields) {
  if (value.length != fields.length || !value.keys.every(fields.contains)) {
    _invalid();
  }
}

Uint8List _check(List<int> entropy) => Uint8List.fromList(
  const DartSha256()
      .hashSync([...utf8.encode(_checkDomain), 0, ...entropy])
      .bytes
      .sublist(0, _checkLength),
);

Uint8List _prefix(String header) {
  final h = utf8.encode(header);
  return Uint8List.fromList([
    ..._magic,
    kRecoveryFileVersion,
    h.length >> 8,
    h.length & 0xFF,
    ...h,
  ]);
}

String _protectedHeader(List<int> salt) => canonicalJsonOf(<String, Object?>{
  'k': _kindProtected,
  'kdf': <String, Object?>{
    'a': 'argon2id',
    'm': kRecoveryFileKdfMemoryKiB,
    'p': kRecoveryFileKdfParallelism,
    't': kRecoveryFileKdfIterations,
  },
  's': encodeBase64Url(salt),
  'v': kRecoveryFileVersion,
});

/// Abre la variante abierta. Lanza [RecoveryFileException].
RecoveryCode openOpenRecoveryFile(RecoveryFile file) {
  if (file.variant != RecoveryFileVariant.open) _invalid();
  final b = file._bytes;
  final entropy = Uint8List.sublistView(
    b,
    file._aadEnd,
    file._aadEnd + _entropyLength,
  );
  final check = Uint8List.sublistView(b, file._aadEnd + _entropyLength);
  if (!constantTimeEquals(check, _check(entropy))) _invalid();
  return RecoveryCode(entropy);
}

/// La clave de la variante protegida: Argon2id de [nfcPassword] (ya en NFC)
/// con el perfil fijo, en otro isolate (en la web, en el mismo). Cuesta unos
/// segundos y 64 MiB: la aplicación lanza una sola a la vez.
Future<Uint8List> deriveRecoveryFileKey(String nfcPassword, List<int> salt) {
  if (salt.length != _saltLength) _invalid();
  final password = Uint8List.fromList(utf8.encode(nfcPassword));
  final s = Uint8List.fromList(salt);
  return runTask(() => _argon2id(password, s));
}

Future<Uint8List> _argon2id(Uint8List password, Uint8List salt) async {
  final key =
      await DartArgon2id(
        parallelism: kRecoveryFileKdfParallelism,
        memory: kRecoveryFileKdfMemoryKiB,
        iterations: kRecoveryFileKdfIterations,
        hashLength: 32,
        maxIsolates: 1,
      ).deriveKey(
        secretKey: SecretKey(password),
        nonce: salt,
        associatedData: utf8.encode(_kdfAssociated),
      );
  return Uint8List.fromList(await key.extractBytes());
}

/// Cómo se deriva la clave: [deriveRecoveryFileKey] salvo en pruebas.
typedef RecoveryFileKeyDeriver = Future<Uint8List> Function(
  String nfcPassword,
  List<int> salt,
);

/// La sal de un fichero protegido (para derivar con [deriveRecoveryFileKey]).
Uint8List recoveryFileSalt(RecoveryFile file) {
  final salt = file._salt;
  if (salt == null) _invalid();
  return Uint8List.fromList(salt);
}

/// Abre la variante protegida con una clave ya derivada (sin Argon2). Lanza
/// [RecoveryFileException] con [RecoveryFileFailure.damagedOrWrongPassword]
/// si el GCM no cuadra.
Future<RecoveryCode> openRecoveryFileWithKey(
  RecoveryFile file,
  List<int> key,
) async {
  if (file.variant != RecoveryFileVariant.protected) _invalid();
  final b = file._bytes;
  final nonceEnd = file._aadEnd + _nonceLength;
  final tagStart = b.length - _tagLength;
  final List<int> plain;
  try {
    plain = await AesGcm.with256bits().decrypt(
      SecretBox(
        Uint8List.sublistView(b, nonceEnd, tagStart),
        nonce: Uint8List.sublistView(b, file._aadEnd, nonceEnd),
        mac: Mac(Uint8List.sublistView(b, tagStart)),
      ),
      secretKey: SecretKey(key),
      aad: Uint8List.sublistView(b, 0, file._aadEnd),
    );
  } on SecretBoxAuthenticationError {
    throw const RecoveryFileException(
      RecoveryFileFailure.damagedOrWrongPassword,
    );
  }
  if (plain.length != _entropyLength) {
    throw const RecoveryFileException(
      RecoveryFileFailure.damagedOrWrongPassword,
    );
  }
  return RecoveryCode(plain);
}

/// Abre la variante protegida con su contraseña (ya en NFC): deriva y abre.
Future<RecoveryCode> openProtectedRecoveryFile(
  RecoveryFile file,
  String nfcPassword, {
  RecoveryFileKeyDeriver derive = deriveRecoveryFileKey,
}) async {
  final key = await derive(nfcPassword, recoveryFileSalt(file));
  return openRecoveryFileWithKey(file, key);
}

/// Un fichero recién sellado y lo justo para comprobar su relectura sin un
/// segundo Argon2. La clave nunca sale de aquí.
class SealedRecoveryFile {
  SealedRecoveryFile._(this.bytes, this.variant, this._key);

  /// Los bytes que se escriben.
  final Uint8List bytes;

  /// La variante.
  final RecoveryFileVariant variant;

  final Uint8List? _key;

  /// Abre [readBack] (lo que se leyó del destino) con la clave de este
  /// sellado y devuelve su código. Lanza [RecoveryFileException].
  Future<RecoveryCode> reopen(List<int> readBack) async {
    final file = parseRecoveryFile(readBack);
    if (file.variant != variant) _invalid();
    return variant == RecoveryFileVariant.open
        ? openOpenRecoveryFile(file)
        : openRecoveryFileWithKey(file, _key!);
  }

  @override
  String toString() => 'SealedRecoveryFile(${variant.name})';
}

/// Sella la variante abierta (no pasa por Argon2).
SealedRecoveryFile sealOpenRecoveryFile(RecoveryCode code) {
  final entropy = code.entropy;
  final prefix = _prefix(
    canonicalJsonOf(<String, Object?>{
      'k': _kindOpen,
      'v': kRecoveryFileVersion,
    }),
  );
  return SealedRecoveryFile._(
    Uint8List.fromList([...prefix, ...entropy, ..._check(entropy)]),
    RecoveryFileVariant.open,
    null,
  );
}

/// Sella la variante protegida con [nfcPassword] (ya en NFC; las reglas de
/// creación las aplica antes [checkRecoveryPassword]). Sal y nonce nuevos.
Future<SealedRecoveryFile> sealProtectedRecoveryFile(
  RecoveryCode code,
  String nfcPassword, {
  RecoveryFileKeyDeriver derive = deriveRecoveryFileKey,
}) => _sealProtected(code, nfcPassword, derive: derive);

/// Igual que [sealProtectedRecoveryFile] con sal y nonce dados: SOLO para
/// pruebas y vectores fijos.
@visibleForTesting
Future<SealedRecoveryFile> sealProtectedRecoveryFileForTesting(
  RecoveryCode code,
  String nfcPassword, {
  required List<int> salt,
  required List<int> nonce,
}) => _sealProtected(code, nfcPassword, salt: salt, nonce: nonce);

Future<SealedRecoveryFile> _sealProtected(
  RecoveryCode code,
  String nfcPassword, {
  List<int>? salt,
  List<int>? nonce,
  RecoveryFileKeyDeriver derive = deriveRecoveryFileKey,
}) async {
  final s = salt ?? secureRandomBytes(_saltLength);
  final n = nonce ?? secureRandomBytes(_nonceLength);
  if (s.length != _saltLength || n.length != _nonceLength) {
    throw ArgumentError('sal de 16 bytes y nonce de 12');
  }
  final aad = _prefix(_protectedHeader(s));
  final key = await derive(nfcPassword, s);
  if (key.length != 32) throw ArgumentError('clave de 32 bytes');
  final box = await AesGcm.with256bits().encrypt(
    code.entropy,
    secretKey: SecretKey(key),
    nonce: n,
    aad: aad,
  );
  return SealedRecoveryFile._(
    Uint8List.fromList([...aad, ...n, ...box.cipherText, ...box.mac.bytes]),
    RecoveryFileVariant.protected,
    key,
  );
}

// ------------------------------------------------------------ contraseña

/// Por qué no vale una contraseña nueva. La interfaz lo traduce. Solo se
/// aplica al crear: un fichero ya emitido se abre con su contraseña siempre.
enum RecoveryPasswordProblem {
  /// Menos de [kRecoveryPasswordMinRunes] caracteres.
  tooShort,

  /// Más de [kRecoveryPasswordMaxRunes] caracteres.
  tooLong,

  /// Un carácter o un bloque repetido («aaaa…», «abcabc…»).
  repeated,

  /// Solo números.
  onlyDigits,

  /// Una fila, una columna o una secuencia de teclado o del abecedario.
  keyboardSequence,

  /// Contiene el nombre de la app.
  containsAppName,

  /// Es una frase frecuente de la lista local.
  common,

  /// Las dos entradas no coinciden.
  mismatch,
}

/// Comprueba una contraseña nueva ([nfcPassword] ya en NFC). Devuelve null
/// si vale. Sin red ni descargas: patrones y una lista corta local en es, ca
/// y en. La longitud es un filtro, no una garantía.
RecoveryPasswordProblem? checkRecoveryPassword(String nfcPassword) {
  final runes = nfcPassword.runes.length;
  if (runes < kRecoveryPasswordMinRunes) {
    return RecoveryPasswordProblem.tooShort;
  }
  if (runes > kRecoveryPasswordMaxRunes) {
    return RecoveryPasswordProblem.tooLong;
  }
  final lower = _fold(nfcPassword.toLowerCase());
  final compact = lower.replaceAll(RegExp(r'\s+'), '');
  // Solo espacios o tabuladores: un carácter repetido.
  if (compact.isEmpty || _isRepeated(lower) || _isRepeated(compact)) {
    return RecoveryPasswordProblem.repeated;
  }
  final digitsOnly = compact.replaceAll(RegExp(r'[\-_.,/·]'), '');
  if (digitsOnly.isNotEmpty && RegExp(r'^[0-9]+$').hasMatch(digitsOnly)) {
    return RecoveryPasswordProblem.onlyDigits;
  }
  if (_isKeyboardSequence(compact)) {
    return RecoveryPasswordProblem.keyboardSequence;
  }
  final letters = lower.replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (letters.contains('gifthuddle')) {
    return RecoveryPasswordProblem.containsAppName;
  }
  final words = letters.replaceAll(RegExp(r'[0-9]'), '');
  if (words.isNotEmpty &&
      (_commonPhrases.contains(words) ||
          _commonPhrases.contains(letters) ||
          _isRepeated(words))) {
    return RecoveryPasswordProblem.common;
  }
  return null;
}

/// Comprueba las dos entradas de una contraseña nueva (ambas ya en NFC).
RecoveryPasswordProblem? checkNewRecoveryPassword(
  String nfcFirst,
  String nfcSecond,
) {
  final problem = checkRecoveryPassword(nfcFirst);
  if (problem != null) return problem;
  return nfcFirst == nfcSecond ? null : RecoveryPasswordProblem.mismatch;
}

/// Quita tildes, diéresis y cedillas de las letras latinas habituales en es,
/// ca y en, para comparar patrones y frases.
String _fold(String text) {
  const from = 'áàâäãåéèêëíìîïóòôöõúùûüñçýÿ';
  const to = 'aaaaaaeeeeiiiiooooouuuuncyy';
  final out = StringBuffer();
  for (final r in text.runes) {
    final c = String.fromCharCode(r);
    final i = from.indexOf(c);
    out.write(i < 0 ? c : to[i]);
  }
  return out.toString();
}

/// Un bloque (de uno o más caracteres) repetido al menos dos veces.
bool _isRepeated(String s) {
  final r = s.runes.toList();
  for (var period = 1; period * 2 <= r.length; period++) {
    var ok = true;
    for (var i = period; i < r.length && ok; i++) {
      ok = r[i] == r[i - period];
    }
    if (ok) return true;
  }
  return false;
}

const _sequences = [
  'abcdefghijklmnopqrstuvwxyz',
  '01234567890',
  'qwertyuiopasdfghjklzxcvbnm',
  'azertyuiopqsdfghjklmwxcvbn',
  'qwertzuiopasdfghjklyxcvbnm',
  '1qaz2wsx3edc4rfv5tgb6yhn7ujm8ik9ol0p',
  'qazwsxedcrfvtgbyhnujmikolp',
  '!@#\$%^&*()_+',
  '!"·\$%&/()=?¿',
];

/// Casi toda la cadena va de tecla en tecla vecina (en un sentido u otro) de
/// una fila, columna o del abecedario: como mucho dos saltos sueltos.
bool _isKeyboardSequence(String s) {
  final r = s.runes.map(String.fromCharCode).toList();
  if (r.length < 2) return false;
  var jumps = 0;
  for (var i = 1; i < r.length; i++) {
    if (!_neighbours(r[i - 1], r[i])) jumps++;
    if (jumps > 2) return false;
  }
  return true;
}

bool _neighbours(String a, String b) {
  for (final line in _sequences) {
    final i = line.indexOf(a);
    if (i < 0) continue;
    if ((i + 1 < line.length && line[i + 1] == b) ||
        (i > 0 && line[i - 1] == b)) {
      return true;
    }
  }
  return false;
}

/// Frases frecuentes en es, ca y en (de al menos 15 letras, sin espacios,
/// tildes ni números). Escrita para la app; no se descarga nada.
const _commonPhrases = {
  // en
  'correcthorsebatterystaple',
  'thequickbrownfoxjumpsoverthelazydog',
  'iloveyouforever',
  'iloveyousomuch',
  'iloveyoubaby',
  'iloveyoumorethananything',
  'mypasswordissecure',
  'thisismypassword',
  'thisisapassword',
  'thisismysecretpassword',
  'letmeinletmein',
  'passwordpassword',
  'mysecretpassword',
  'supersecretpassword',
  'changemeplease',
  'merrychristmas',
  'merrychristmasandhappynewyear',
  'happynewyear',
  'happybirthday',
  'onetwothreefourfive',
  'iwanttobelieve',
  'maytheforcebewithyou',
  'tobeornottobe',
  'tobeornottobethatisthequestion',
  'giftlistpassword',
  'christmasgifts',
  'christmaspresents',
  'familygiftlist',
  'myfamilypassword',
  'recoverypassword',
  'recoveryfilepassword',
  // es
  'contrasenasegura',
  'estaesmicontrasena',
  'esmicontrasena',
  'micontrasenasecreta',
  'micontrasenaessegura',
  'contrasenacontrasena',
  'teamoparasiempre',
  'tequieromucho',
  'tequieroparasiempre',
  'felizcumpleanos',
  'feliznavidad',
  'feliznavidadyprosperoanonuevo',
  'felizanonuevo',
  'unodostrescuatrocinco',
  'nosotrosregalos',
  'listaderegalos',
  'regalosdenavidad',
  'regalosdereyes',
  'losreyesmagos',
  'enunlugardelamancha',
  'micontrasenaderecuperacion',
  'contrasenaderecuperacion',
  'hastaelinfinitoymasalla',
  'quelafuerzateacompane',
  // ca
  'contrasenyasegura',
  'aquestaesmevacontrasenya',
  'lamevacontrasenya',
  'lamevacontrasenyasecreta',
  'contrasenyacontrasenya',
  'testimoperasempre',
  'testimomolt',
  'bonnadal',
  'bonnadalibonanynou',
  'bonaniversari',
  'feliccumpleanys',
  'unduestresquatrecinc',
  'llistaderegals',
  'regalsdenadal',
  'regalsdereis',
  'elsreismags',
  'contrasenyaderecuperacio',
};
