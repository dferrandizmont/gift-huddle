// El fichero `.regalos` de intercambio tras el corte al formato 2 del común
// (ADR 0005, lote B6). Dart puro (sin Flutter).
//
// Formato (todo en bytes):
//   "RX" | 0x01 | uint32 BE = longitud de la cabecera | cabecera JSON UTF-8 |
//   común firmado (sobre `RG 0x02`, `family_envelope.dart`)
//
// cabecera = {"kp": [paquetes v4], "l": lista, "rec": [fichas],
//             "sid": generación, "v": 1}
//
// El contenedor en sí no va firmado ni cifrado: cada parte se autentica
// sola. El común lo firma su escritor y va cifrado con una candidata; cada
// paquete v4 va cifrado con X25519 para un destinatario ya autorizado y
// firmado por su emisor. Las fichas son solo las que necesitan el común y
// los paquetes (escritor, creador y audiencia), firmadas por su móvil.
// Quien lo abre **no guarda nada del registro del fichero** (revisión de
// seguridad, A1-A3): decide con su vista local y usa esas fichas solo en
// memoria, y solo si son de un id que ya tiene enlazado con la misma clave.
// Ninguna clave viaja en claro ni envuelta con la `familyKey` de siempre.
//
// Es otro prefijo que el sobre de siempre (`RG 0x01`) y que el común (`RG
// 0x02`): una versión anterior de la app lo rechaza como «no es un sobre».
//
// No es la copia de recuperación (fase 3, lote 5): esa lleva el llavero, los
// contextos y la marca de formato bajo el código de recuperación, y tiene
// su propio formato.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'device_keys.dart' show kSyncIdPattern;
import 'envelope.dart';
import 'family_candidate.dart' show kV2SyncIdPattern;
import 'family_envelope.dart' show isFamilyEnvelope;
import 'family_key_bundle.dart' show FamilyKeyBundle;

/// Versión del contenedor de intercambio.
const int kExchangeFileVersion = 1;

/// Tamaño máximo de la cabecera (registro y paquetes).
const int kMaxExchangeHeaderBytes = 512 * 1024;

/// Paquetes que admite un fichero (uno por destinatario).
const int kMaxExchangePackages = 64;

/// Fichas que admite un fichero (escritor, creador y audiencia): tantas como
/// fichas admite un registro, para cubrir cualquier audiencia.
const int kMaxExchangeRecords = 64;

const _magic0 = 0x52; // R
const _magic1 = 0x58; // X
const _prefixLength = 7;
const _headerKeys = {'kp', 'l', 'rec', 'sid', 'v'};

/// El fichero es de otra generación de la lista (otra renovación).
class ExchangeGenerationException extends EnvelopeException {
  /// Crea el error.
  const ExchangeGenerationException(super.message);
}

/// Un `.regalos` de siempre (sin firma, con la `familyKey`) en una familia
/// que ya ha pasado al formato 2: no entra solo. Hay que volver a guardarlo
/// desde un móvil actualizado.
class ExchangeLegacyFileException extends EnvelopeFormatException {
  /// Crea el error.
  const ExchangeLegacyFileException(super.message);
}

/// Un fichero nuevo en un móvil que aún no ha pasado al formato 2: tiene que
/// sincronizar antes.
class ExchangeNotReadyException extends EnvelopeFormatException {
  /// Crea el error.
  const ExchangeNotReadyException(super.message);
}

/// Falta la clave común con la que se selló el fichero, o su escritor aún no
/// está confirmado en este móvil: no se ha fusionado nada. Con [kept], el
/// fichero se ha guardado aparte y se vuelve a probar en cada
/// sincronización; sin él, hay que sincronizar y volver a abrirlo.
class ExchangeMissingKeyException extends EnvelopeException {
  /// Crea el error.
  const ExchangeMissingKeyException(super.message, {this.kept = true});

  /// Si el fichero ha quedado guardado.
  final bool kept;
}

/// Lo escribió un móvil que ya no es de la familia (revocado): no entra.
class ExchangeRevokedWriterException extends EnvelopeException {
  /// Crea el error.
  const ExchangeRevokedWriterException(super.message);
}

/// Este móvil no puede guardar un fichero (pendiente de aprobar, revocado o
/// sin clave común que pueda repartir).
class ExchangeNotAllowedException implements Exception {
  /// Crea el error.
  const ExchangeNotAllowedException(this.message);

  /// Qué pasa.
  final String message;

  @override
  String toString() => 'ExchangeNotAllowedException: $message';
}

/// Si [bytes] empiezan como un fichero de intercambio. No valida.
bool isExchangeFile(Uint8List bytes) =>
    bytes.length >= 3 && bytes[0] == _magic0 && bytes[1] == _magic1;

/// Si [bytes] empiezan como el sobre de siempre (`RG 0x01`). No valida.
bool isLegacyEnvelope(Uint8List bytes) =>
    bytes.length >= 3 && bytes[0] == 0x52 && bytes[1] == 0x47 && bytes[2] == 1;

/// El contenido de un fichero de intercambio, sin autenticar: quien lo
/// recibe verifica el registro, abre los paquetes y comprueba el común.
class ExchangeFile {
  /// Crea el fichero. Lanza [EnvelopeFormatException] si algo no vale.
  ExchangeFile({
    required this.listId,
    required this.syncId,
    required List<Map<String, Object?>> records,
    required List<Map<String, Object?>> packages,
    required this.common,
  }) : records = List.unmodifiable(records),
       packages = List.unmodifiable(packages) {
    if (records.length > kMaxExchangeRecords ||
        packages.length > kMaxExchangePackages) {
      throw const EnvelopeTooLargeException(
        'el fichero lleva demasiadas fichas o paquetes',
      );
    }
    if (!kSyncIdPattern.hasMatch(listId) ||
        !kV2SyncIdPattern.hasMatch(syncId) ||
        !packages.every(FamilyKeyBundle.isV4) ||
        !isFamilyEnvelope(common)) {
      throw const EnvelopeFormatException('fichero no válido');
    }
  }

  /// Lista.
  final String listId;

  /// Generación v2.
  final String syncId;

  /// Las fichas que necesitan el común y los paquetes (`DeviceRecord.toJson`),
  /// sin verificar.
  final List<Map<String, Object?>> records;

  /// Los paquetes v4 de la candidata del común para su audiencia.
  final List<Map<String, Object?>> packages;

  /// El común firmado (formato 2).
  final Uint8List common;

  /// En bytes. Lanza [EnvelopeTooLargeException] si no cabe.
  Uint8List encode() {
    final header = utf8.encode(
      jsonEncode(<String, Object?>{
        'kp': packages,
        'l': listId,
        'rec': records,
        'sid': syncId,
        'v': kExchangeFileVersion,
      }),
    );
    final total = _prefixLength + header.length + common.length;
    if (header.length > kMaxExchangeHeaderBytes || total > kMaxEnvelopeBytes) {
      throw const EnvelopeTooLargeException('el fichero no cabe');
    }
    final out = BytesBuilder(copy: false)
      ..addByte(_magic0)
      ..addByte(_magic1)
      ..addByte(kExchangeFileVersion)
      ..add((ByteData(4)..setUint32(0, header.length)).buffer.asUint8List())
      ..add(header)
      ..add(common);
    return out.toBytes();
  }

  /// Lee [encode] sin autenticar nada. Lanza [EnvelopeTooLargeException] si
  /// no cabe y [EnvelopeFormatException] si no es un fichero de intercambio
  /// o es de una versión posterior.
  factory ExchangeFile.parse(Uint8List bytes) {
    if (bytes.length > kMaxEnvelopeBytes) {
      throw const EnvelopeTooLargeException('fichero demasiado grande');
    }
    if (!isExchangeFile(bytes)) {
      throw const EnvelopeFormatException('no es un fichero de intercambio');
    }
    if (bytes[2] != kExchangeFileVersion) {
      throw EnvelopeFormatException(
        'versión ${bytes[2]} del fichero no soportada: hay que actualizar',
      );
    }
    if (bytes.length < _prefixLength) {
      throw const EnvelopeFormatException('fichero truncado');
    }
    final hLen = ByteData.sublistView(bytes, 3, _prefixLength).getUint32(0);
    if (hLen == 0 || hLen > kMaxExchangeHeaderBytes) {
      throw const EnvelopeFormatException('cabecera no válida');
    }
    final end = _prefixLength + hLen;
    if (bytes.length <= end) {
      throw const EnvelopeFormatException('fichero truncado');
    }
    final Object? raw;
    try {
      raw = jsonDecode(
        utf8.decode(Uint8List.sublistView(bytes, _prefixLength, end)),
      );
    } on FormatException {
      throw const EnvelopeFormatException('cabecera dañada');
    }
    if (raw is! Map ||
        raw.length != _headerKeys.length ||
        !raw.keys.every(_headerKeys.contains) ||
        raw['v'] != kExchangeFileVersion ||
        raw['l'] is! String ||
        raw['sid'] is! String ||
        raw['rec'] is! List ||
        raw['kp'] is! List) {
      throw const EnvelopeFormatException('cabecera no válida');
    }
    final kp = raw['kp'] as List;
    final rec = raw['rec'] as List;
    if (kp.length > kMaxExchangePackages || rec.length > kMaxExchangeRecords) {
      throw const EnvelopeTooLargeException(
        'el fichero lleva demasiadas fichas o paquetes',
      );
    }
    if (!kp.every((p) => p is Map) || !rec.every((r) => r is Map)) {
      throw const EnvelopeFormatException('paquetes o fichas no válidos');
    }
    return ExchangeFile(
      listId: raw['l'] as String,
      syncId: raw['sid'] as String,
      records: [for (final r in rec) Map<String, Object?>.from(r as Map)],
      packages: [for (final p in kp) Map<String, Object?>.from(p as Map)],
      common: Uint8List.fromList(Uint8List.sublistView(bytes, end)),
    );
  }
}
