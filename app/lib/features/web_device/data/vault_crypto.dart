import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../../../core/sync/device_keys.dart' show canonicalHeaderBytes;
import '../../../core/sync/envelope.dart' show encodeBase64Url, decodeBase64Url;
import 'vault_pin_stub.dart' if (dart.library.js_interop) 'vault_pin_web.dart';
import 'vault_store.dart';

/// Public, bounded KDF parameters. Validate before doing any expensive work.
class VaultHeader {
  VaultHeader({
    required this.syncId,
    required this.deviceId,
    required this.salt,
    required this.guardToken,
    required this.guardVersion,
    this.iterations = 600000,
    this.format = 1,
  });
  final String syncId, deviceId;
  final List<int> salt, guardToken;
  final int guardVersion, iterations, format;
  void validate() {
    if (format != 1 ||
        iterations < 600000 ||
        iterations > 2000000 ||
        salt.length != 16 ||
        guardToken.length != 32 ||
        guardVersion < 1 ||
        syncId.isEmpty ||
        deviceId.isEmpty) {
      throw const FormatException('Invalid vault header');
    }
  }

  Map<String, Object?> toJson() => {
    'format': format,
    'syncId': syncId,
    'deviceId': deviceId,
    'salt': encodeBase64Url(salt),
    'guardToken': encodeBase64Url(guardToken),
    'guardVersion': guardVersion,
    'iterations': iterations,
  };
  factory VaultHeader.fromJson(Map<String, Object?> j) {
    final h = VaultHeader(
      syncId: j['syncId'] as String,
      deviceId: j['deviceId'] as String,
      salt: decodeBase64Url(j['salt'] as String),
      guardToken: decodeBase64Url(j['guardToken'] as String),
      guardVersion: j['guardVersion'] as int,
      iterations: j['iterations'] as int,
      format: j['format'] as int,
    );
    h.validate();
    return h;
  }
}

/// Ephemeral only: never serialize these values or include them in diagnostics.
class VaultDerivation {
  VaultDerivation(this.a, this.proof);
  final SecretKey a, proof;
}

class VaultCrypto {
  final _aes = AesGcm.with256bits();
  List<int> randomBytes(int count) {
    final random = Random.secure();
    return List<int>.generate(count, (_) => random.nextInt(256));
  }

  static bool validPin(String pin) {
    final normalized = normalizeNfc(pin);
    return RegExp(r'^\d{6,}$').hasMatch(normalized) ||
        (!RegExp(r'^\d+$').hasMatch(normalized) &&
            normalized.runes.length >= 8);
  }

  Future<SecretKey> deriveA(String pin, VaultHeader header) async {
    header.validate();
    if (!validPin(pin)) throw ArgumentError('Invalid PIN or passphrase');
    return pbkdf2(utf8.encode(normalizeNfc(pin)), header);
  }

  /// The expensive operation is separate so tests can observe its entry.
  Future<SecretKey> pbkdf2(List<int> pinBytes, VaultHeader header) => Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: header.iterations,
    bits: 256,
  ).deriveKey(secretKey: SecretKey(pinBytes), nonce: header.salt);

  Future<SecretKey> hkdf(SecretKey input, String info) => Hkdf(
    hmac: Hmac.sha256(),
    outputLength: 32,
  ).deriveKey(secretKey: input, nonce: const [], info: utf8.encode(info));
  Future<VaultDerivation> derive(String pin, VaultHeader header) async {
    final bigA = await deriveA(pin, header);
    return VaultDerivation(
      await hkdf(bigA, 'gift-huddle web vault-a v1'),
      await hkdf(bigA, 'gift-huddle web guard-proof v1'),
    );
  }

  Future<SecretKey> key(VaultDerivation derived, List<int> b) async {
    if (b.length != 32) throw const FormatException('Invalid guard secret');
    return hkdf(
      SecretKey([...await derived.a.extractBytes(), ...b]),
      'gift-huddle web vault v1',
    );
  }

  List<int> aad(VaultHeader header, String kind, String id) {
    header.validate();
    return canonicalHeaderBytes({
      'format': header.format,
      'syncId': header.syncId,
      'deviceId': header.deviceId,
      'guardVersion': header.guardVersion,
      'kind': kind,
      'id': id,
    });
  }

  /// Each call gets a fresh nonce, including rewrites of the same entry.
  Future<Map<String, Object?>> seal(
    Object? value,
    SecretKey key,
    VaultHeader header,
    String kind, [
    String id = '',
  ]) async {
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode(value)),
      secretKey: key,
      nonce: randomBytes(12),
      aad: aad(header, kind, id),
    );
    return {
      'nonce': encodeBase64Url(box.nonce),
      'ciphertext': encodeBase64Url(box.cipherText),
      'mac': encodeBase64Url(box.mac.bytes),
    };
  }

  Future<Object?> open(
    Map<String, Object?> box,
    SecretKey key,
    VaultHeader header,
    String kind, [
    String id = '',
  ]) async {
    final nonce = decodeBase64Url(box['nonce'] as String);
    final mac = decodeBase64Url(box['mac'] as String);
    if (nonce.length != 12 || mac.length != 16) {
      throw const FormatException('Invalid sealed entry');
    }
    final plain = await _aes.decrypt(
      SecretBox(
        decodeBase64Url(box['ciphertext'] as String),
        nonce: nonce,
        mac: Mac(mac),
      ),
      secretKey: key,
      aad: aad(header, kind, id),
    );
    return jsonDecode(utf8.decode(plain));
  }

  Future<String> hash(List<int> bytes) async =>
      encodeBase64Url((await Sha256().hash(bytes)).bytes);

  Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  Future<String> stateHash(VaultSet set) => hash(
    utf8.encode(
      jsonEncode(_canonical({'entries': set.entries, 'marks': set.marks})),
    ),
  );

  /// The authenticated checkpoint binds the complete ciphertext map and marks.
  /// Callers persist this box and those resources in one transaction.
  Future<VaultSet> sealSet(
    VaultSet set,
    VaultJson data,
    int counter,
    SecretKey key,
    VaultHeader header,
  ) async => VaultSet(
    header: set.header,
    entries: set.entries,
    marks: set.marks,
    box: await seal(
      {'data': data, 'counter': counter, 'stateHash': await stateHash(set)},
      key,
      header,
      'vault',
    ),
  );

  Future<({VaultJson data, int counter})> openSet(
    VaultSet set,
    SecretKey key,
    VaultHeader header,
  ) async {
    final payload = await open(set.box, key, header, 'vault');
    if (payload is! Map ||
        payload['data'] is! Map ||
        payload['counter'] is! int ||
        (payload['counter'] as int) < 0 ||
        payload['stateHash'] != await stateHash(set)) {
      throw const FormatException(
        'Vault integrity check failed: queue or marks changed',
      );
    }
    return (
      data: Map<String, Object?>.from(payload['data'] as Map),
      counter: payload['counter'] as int,
    );
  }
}
