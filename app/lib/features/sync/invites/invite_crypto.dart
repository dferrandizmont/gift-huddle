// Criptografía de las invitaciones a distancia. Dart puro (sin Flutter).
// Decisión: docs/adr/0002-sincronizacion.md. Vector fijo:
// docs/adr/0002-vector-invitacion.json.
//
// Lo que el ADR fija:
// - par X25519 efímero en cada móvil (A ofrece el suyo antes de entregar nada);
// - código de verificación: HKDF(publicKeyA ‖ publicKeyB,
//   info = "gift-huddle-verify-v1") → 20 bits → 6 dígitos, que se enseña en los
//   dos móviles antes de que A entregue el paquete;
// - paquete {listId, familyKey, deviceNameA} cifrado con AES-256-GCM con una
//   clave derivada por HKDF del secreto compartido X25519.
//
// Lo que este fichero concreta (el ADR no lo dice):
// - HKDF es siempre HKDF-SHA256 (RFC 5869). El código usa sal vacía; la clave
//   del paquete usa sal "gift-huddle" e info "gift-huddle-invite-v1".
// - Los 20 bits son los 20 primeros bits de la salida (3 bytes), `b0 << 12 |
//   b1 << 4 | b2 >> 4`, y el código es ese número módulo 1.000.000 con ceros a
//   la izquierda.
// - Datos asociados del GCM: UTF-8 de `inviteId`, ‖ publicKeyA ‖ publicKeyB,
//   para que el paquete solo valga para esa invitación y esas dos claves.
// - Texto de salida: texto cifrado y etiqueta de 16 bytes juntos, más el
//   nonce de 12 bytes aparte.
// - Paquete: JSON `{"v":1,"l":listId,"k":familyKey(base64url),"n":nombreA}`.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../../core/sync/envelope.dart';
import '../../../core/sync/hkdf.dart';

const _verifyInfo = 'gift-huddle-verify-v1';
const _packageSalt = 'gift-huddle';
const _packageInfo = 'gift-huddle-invite-v1';
const _nonceLength = 12;
const _macLength = 16;
const _keyLength = 32;
final _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

/// Una invitación que no se puede abrir (paquete manipulado, clave que no
/// corresponde, formato roto).
class InviteCryptoException implements Exception {
  /// Crea el error.
  const InviteCryptoException(this.message);

  /// Qué pasó (sin claves).
  final String message;

  @override
  String toString() => 'InviteCryptoException: $message';
}

/// Par X25519 efímero.
class InviteKeyPair {
  InviteKeyPair._(this._pair, this.publicKey);

  final SimpleKeyPair _pair;

  /// Clave pública (32 bytes).
  final Uint8List publicKey;

  @override
  String toString() => 'InviteKeyPair(…)';
}

/// Lo que viaja dentro del paquete cifrado.
class InvitePackage {
  /// Crea el paquete.
  InvitePackage({
    required this.listId,
    required this.familyKey,
    required String deviceName,
  }) : deviceName = cleanDeviceName(deviceName);

  /// Id de la lista.
  final String listId;

  /// Clave de la familia.
  final FamilyKey familyKey;

  /// Nombre del móvil que invita.
  final String deviceName;
}

/// Limpia un nombre de móvil que viene de otro móvil (no es de fiar): quita
/// controles, marcas bidi y caracteres de ancho cero (categoría Unicode C, que
/// incluye U+202E, U+200B, U+2066 y U+FEFF), los separadores de línea y
/// párrafo y los rellenos invisibles del hangul, y recorta a 40 caracteres.
String cleanDeviceName(String name) {
  final clean = name
      .replaceAll(RegExp(r'[\p{C}  ㅤᅟᅠ]', unicode: true), '')
      .trim();
  final runes = clean.runes;
  return runes.length <= 40 ? clean : String.fromCharCodes(runes.take(40));
}

/// Operaciones de las invitaciones.
abstract final class InviteCrypto {
  static final X25519 _x25519 = X25519();
  static final AesGcm _aes = AesGcm.with256bits();

  /// Crea un par efímero. Con [seed] (32 bytes) es determinista: solo para
  /// pruebas y vectores fijos.
  static Future<InviteKeyPair> generateKeyPair({List<int>? seed}) async {
    final pair = seed == null
        ? await _x25519.newKeyPair()
        : await _x25519.newKeyPairFromSeed(seed);
    final public = await pair.extractPublicKey();
    return InviteKeyPair._(pair, Uint8List.fromList(public.bytes));
  }

  /// Código de verificación de 6 cifras de la pareja de claves públicas.
  static Future<String> verificationCode(
    List<int> publicKeyA,
    List<int> publicKeyB,
  ) async {
    _checkPublic(publicKeyA);
    _checkPublic(publicKeyB);
    final derived = await hkdfSha256(
      secretKey: SecretKey([...publicKeyA, ...publicKeyB]),
      info: utf8.encode(_verifyInfo),
      length: 3,
    );
    final b = await derived.extractBytes();
    final bits = (b[0] << 12) | (b[1] << 4) | (b[2] >> 4);
    return (bits % 1000000).toString().padLeft(6, '0');
  }

  /// El código con un espacio en medio, como se enseña («123 456»).
  static String formatCode(String code) =>
      code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;

  /// Cifra el paquete para quien pidió entrar. [mine] es el par de quien
  /// aprueba (A) y [theirPublicKey] la clave pública de quien entra (B).
  /// Devuelve el texto cifrado con su etiqueta y el nonce; la clave pública
  /// de A que hay que subir con ellos es `mine.publicKey`.
  static Future<({Uint8List ciphertext, Uint8List nonce})> sealPackage({
    required InviteKeyPair mine,
    required List<int> theirPublicKey,
    required String inviteId,
    required InvitePackage package,
    List<int>? nonce,
  }) async {
    _checkPublic(theirPublicKey);
    final n = nonce ?? _randomBytes(_nonceLength);
    if (n.length != _nonceLength) {
      throw ArgumentError.value(n.length, 'nonce', 'debe tener 12 bytes');
    }
    final key = await _packageKey(mine, theirPublicKey);
    final plain = utf8.encode(
      jsonEncode(<String, Object?>{
        'v': 1,
        'l': package.listId,
        'k': package.familyKey.toBase64Url(),
        'n': package.deviceName,
      }),
    );
    final box = await _aes.encrypt(
      plain,
      secretKey: key,
      nonce: n,
      aad: _aad(inviteId, mine.publicKey, theirPublicKey),
    );
    return (
      ciphertext: Uint8List.fromList([...box.cipherText, ...box.mac.bytes]),
      nonce: Uint8List.fromList(n),
    );
  }

  /// Abre el paquete que subió A. [mine] es el par de B y [theirPublicKey] la
  /// clave pública de A que trae la aprobación.
  ///
  /// Lanza [InviteCryptoException] si no se puede abrir.
  static Future<InvitePackage> openPackage({
    required InviteKeyPair mine,
    required List<int> theirPublicKey,
    required String inviteId,
    required List<int> ciphertext,
    required List<int> nonce,
  }) async {
    _checkPublic(theirPublicKey);
    if (nonce.length != _nonceLength || ciphertext.length <= _macLength) {
      throw const InviteCryptoException('paquete mal formado');
    }
    final key = await _packageKey(mine, theirPublicKey);
    final List<int> plain;
    try {
      plain = await _aes.decrypt(
        SecretBox(
          ciphertext.sublist(0, ciphertext.length - _macLength),
          nonce: nonce,
          mac: Mac(ciphertext.sublist(ciphertext.length - _macLength)),
        ),
        secretKey: key,
        // Aquí A es la otra parte: sus claves van primero, como al cifrar.
        aad: _aad(inviteId, theirPublicKey, mine.publicKey),
      );
    } on SecretBoxAuthenticationError {
      throw const InviteCryptoException('el paquete no se puede abrir');
    }
    try {
      final json = jsonDecode(utf8.decode(plain));
      if (json is! Map || json['v'] != 1) {
        throw const InviteCryptoException('versión no soportada');
      }
      final l = json['l'];
      final k = json['k'];
      final n = json['n'];
      if (l is! String ||
          !_idPattern.hasMatch(l) ||
          k is! String ||
          n is! String) {
        throw const InviteCryptoException('paquete no válido');
      }
      final familyKey = FamilyKey.fromBase64Url(k);
      return InvitePackage(listId: l, familyKey: familyKey, deviceName: n);
    } on InviteCryptoException {
      rethrow;
    } on FormatException {
      throw const InviteCryptoException('paquete dañado');
    } on ArgumentError {
      throw const InviteCryptoException('clave no válida');
    }
  }

  /// Comprueba que [theirPublicKey] es una clave X25519 válida para [mine]:
  /// 32 bytes y secreto compartido que no sale todo ceros (clave de orden
  /// bajo). Lanza [InviteCryptoException] si no.
  static Future<void> checkPeer(
    InviteKeyPair mine,
    List<int> theirPublicKey,
  ) async {
    _checkPublic(theirPublicKey);
    await _shared(mine, theirPublicKey);
  }

  /// Para los vectores: el secreto compartido en claro.
  static Future<Uint8List> sharedSecretForTesting(
    InviteKeyPair mine,
    List<int> theirPublicKey,
  ) async => Uint8List.fromList(
    await (await _shared(mine, theirPublicKey)).extractBytes(),
  );

  /// Para los vectores: la clave AES derivada en claro.
  static Future<Uint8List> packageKeyForTesting(
    InviteKeyPair mine,
    List<int> theirPublicKey,
  ) async => Uint8List.fromList(
    await (await _packageKey(mine, theirPublicKey)).extractBytes(),
  );

  // ---------------------------------------------------------------- interno

  static Future<SecretKey> _shared(
    InviteKeyPair mine,
    List<int> theirPublicKey,
  ) async {
    final secret = await _x25519.sharedSecretKey(
      keyPair: mine._pair,
      remotePublicKey: SimplePublicKey(
        theirPublicKey,
        type: KeyPairType.x25519,
      ),
    );
    final bytes = await secret.extractBytes();
    // Un punto de orden pequeño da un secreto de ceros: no es de nadie.
    if (bytes.every((b) => b == 0)) {
      throw const InviteCryptoException('clave pública no válida');
    }
    return secret;
  }

  static Future<SecretKey> _packageKey(
    InviteKeyPair mine,
    List<int> theirPublicKey,
  ) async => hkdfSha256(
    secretKey: await _shared(mine, theirPublicKey),
    nonce: utf8.encode(_packageSalt),
    info: utf8.encode(_packageInfo),
  );

  static List<int> _aad(
    String inviteId,
    List<int> publicA,
    List<int> publicB,
  ) => [...utf8.encode(inviteId), ...publicA, ...publicB];

  static void _checkPublic(List<int> key) {
    if (key.length != _keyLength) {
      throw const InviteCryptoException('clave pública no válida');
    }
  }

  static Uint8List _randomBytes(int n) {
    final rnd = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => rnd.nextInt(256)));
  }
}
