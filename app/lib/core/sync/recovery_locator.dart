// Derivaciones de descubrimiento de ADR 0007. Sin Flutter ni transporte.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import 'envelope.dart' show encodeBase64Url, decodeBase64Url;
import 'recovery.dart' show RecoveryCode, RecoveryException;
import 'device_keys.dart' show kSyncIdPattern;

/// Solo metadatos del listado autenticado para móviles. No es un localizador
/// público ni contiene material de lectura o verificación.
enum RecoveryMetadataState { active, rotationPending }

class RecoveryMetadata {
  RecoveryMetadata({
    required this.deviceId,
    required this.recoveryId,
    required this.revision,
    required this.state,
  }) {
    recoveryBytes32(recoveryId);
    if (!kSyncIdPattern.hasMatch(deviceId) ||
        revision < 1 ||
        revision > 0x1fffffffffffff) {
      throw const RecoveryException('metadatos de recuperación no válidos');
    }
  }

  final String deviceId;
  final String recoveryId;
  final int revision;
  final RecoveryMetadataState state;

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    'recoveryId': recoveryId,
    'revision': revision,
    'state': state.name,
  };

  factory RecoveryMetadata.fromJson(Object? raw) {
    if (raw is! Map ||
        raw.length != 4 ||
        raw['deviceId'] is! String ||
        raw['recoveryId'] is! String ||
        raw['revision'] is! int ||
        !RecoveryMetadataState.values.any((s) => s.name == raw['state'])) {
      throw const RecoveryException('metadatos de recuperación no válidos');
    }
    return RecoveryMetadata(
      deviceId: raw['deviceId'] as String,
      recoveryId: raw['recoveryId'] as String,
      revision: raw['revision'] as int,
      state: RecoveryMetadataState.values.singleWhere(
        (s) => s.name == raw['state'],
      ),
    );
  }
}

/// Material de búsqueda/lectura; ninguno de estos valores cifra la cápsula.
class RecoveryLocator {
  RecoveryLocator._(this.recoveryId, this.readCap);

  final String recoveryId;
  final String readCap;

  /// El único material de autorización de lectura que guarda el Worker.
  String get readVerifier => recoveryReadVerifier(readCap);

  @override
  String toString() => 'RecoveryLocator(…)';
}

/// HKDF RFC 5869: etiquetas y sal exactas de ADR 0007.
Future<RecoveryLocator> deriveRecoveryLocator(RecoveryCode code) async {
  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  Future<String> expand(String label) async => encodeBase64Url(
    await (await hkdf.deriveKey(
      secretKey: SecretKey(code.entropy),
      nonce: utf8.encode('gift-huddle-recovery-hkdf-v2'),
      info: utf8.encode(label),
    )).extractBytes(),
  );
  return RecoveryLocator._(
    await expand('gift-huddle-recovery-id-v2'),
    await expand('gift-huddle-recovery-read-cap-v2'),
  );
}

/// Base64url canónico de 32 bytes (sin padding).
Uint8List recoveryBytes32(String text) {
  if (text.length != 43) {
    throw const RecoveryException('valor de recuperación no válido');
  }
  try {
    final bytes = decodeBase64Url(text);
    if (bytes.length == 32 && encodeBase64Url(bytes) == text) return bytes;
  } on FormatException {
    // Un único error sin material secreto.
  }
  throw const RecoveryException('valor de recuperación no válido');
}

String recoveryReadVerifier(String readCap) => encodeBase64Url(
  const DartSha256().hashSync([
    ...utf8.encode('gift-huddle-recovery-read-verifier-v2'),
    0,
    ...recoveryBytes32(readCap),
  ]).bytes,
);
