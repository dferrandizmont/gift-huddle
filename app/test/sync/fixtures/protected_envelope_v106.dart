// Copia literal de lib/core/sync/protected_envelope.dart antes de los planes de
// deseos (1.0.7, fase 3); solo cambian los imports. No se edita: fija que un
// slot sin planes sale byte a byte como antes.
// Slots de sorpresas: la instantánea acumulativa que publica un móvil
// escritor de las sorpresas de una persona protegida. Dart puro.
// Decisión: docs/adr/0004-yo-sorpresas-revocar.md (fases 1 y 2a).
//
// Formato (bytes), de tamaño fijo para el mismo escritor y la misma persona:
//   cabecera:
//     "GHS" | 0x02 (versión) | época uint32 BE | revisión uint64 BE |
//     política: u8 (bit 0 = ocultar) | revisión de la política uint64 BE |
//     kid (8 bytes: qué clave candidata de la época lo selló) |
//     u8 + listId | u8 + personId | u8 + escritor   (UTF-8 ASCII)
//   nonce (12) | texto cifrado (kSlotPlainBytes) | etiqueta GCM (16) |
//   firma Ed25519 del escritor (64)
//
// - AAD del GCM = la cabecera entera: une lista, ámbito, época, escritor,
//   revisión, política y clave. Cambiar cualquiera de ellos rompe el GCM.
// - Firma = Ed25519("gift-huddle-slot-v2" ‖ 0x00 ‖ cabecera ‖ nonce ‖
//   texto cifrado ‖ etiqueta). Se comprueba sin la clave de sorpresas, así
//   que cualquier móvil (el de la persona protegida, o uno autorizado que
//   aún no tiene la clave) puede guardar y reenviar slots, quedarse solo con
//   los válidos y leer la política autenticada de la cabecera (N1).
// - La revisión no cuenta ediciones (M5): es el momento de sellar en
//   milisegundos, o la anterior más uno si el reloj no ha avanzado.
// - Texto en claro, siempre de kSlotPlainBytes: primero se comprime, después
//   se rellena y al final se cifra:
//     uint32 BE = longitud L | deflate en bruto (L bytes) | ceros
//   y lo comprimido es el JSON canónico de
//     {"cap": 2, "d": FamilyDoc del ámbito,
//      "s": {escritor: [época, revisión]}, "v": 2}
//   «s» dice qué slot de cada otro escritor estaba ya fusionado en esta
//   instantánea: con eso se sabe cuándo todos conocen una lápida y se puede
//   compactar sin que nada resucite. «cap» (desde la 1.0.6) anuncia que el
//   escritor sabe abrir slots de kMaxSlotGifts regalos; sin él (1.0.5 y
//   antes) solo abre hasta kLegacySlotGifts. Un 1.0.5 no mira esa clave.
// - Capacidad: kMaxSurpriseGifts regalos vivos por persona añadidos desde la
//   interfaz o al activar, más kMaxReconcileGifts de cupo propio para los
//   que mueve la reconciliación (N2); en total kMaxSlotGifts, mientras lo
//   comprimido quepa en el relleno. Solo se sellan más de kLegacySlotGifts
//   cuando todos los demás escritores con derecho anuncian «cap» 2
//   (slotGiftLimitFor); si no, los que sobran se quedan en local. Cada
//   regalo vivo, como mucho kMaxSurpriseGiftBytes, y el JSON entero, como
//   mucho kMaxSlotJsonBytes (M4). Lo mismo se exige al abrir que al sellar
//   (N3), con el límite que anuncia el propio slot.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:meta/meta.dart';

import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/device_keys.dart';
import 'package:regalos/core/sync/envelope.dart'
    show EnvelopeException, EnvelopeTooLargeException, inflateWithLimit;
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart' show Collections;

/// Regalos sorpresa vivos que caben por persona (decisión de producto): los
/// que se añaden desde la interfaz y los que se mueven al activar. Hasta la
/// 1.0.5 eran 50. `test/sync/protected_capacity_test.dart` mide que tantos
/// regalos normales caben con margen en [kSlotPlainBytes].
const int kMaxSurpriseGifts = 200;

/// Regalos vivos que admite un slot que anuncia «cap» 2 (desde la 1.0.6).
/// No hay garantía de que tantos quepan siempre: [fitScopeToSlot] deja
/// fuera lo que, comprimido, no cabe.
const int kMaxSlotGifts = 232;

/// Regalos vivos que admite un slot sin «cap» (lo que abre un 1.0.5). Con
/// [kMaxSurpriseGiftBytes] por regalo, tantos siempre caben comprimidos.
const int kLegacySlotGifts = 64;

/// Capacidad que anuncian los slots que sella esta versión («cap»).
const int kSlotCapacity = 2;

/// Cupo propio de los regalos que mueve la reconciliación (los que alguien
/// escribió en público para la persona protegida): no gastan el de la
/// interfaz, así que la persona protegida no puede llenarlo (N2).
const int kMaxReconcileGifts = kMaxSlotGifts - kMaxSurpriseGifts;

/// Campo que marca, dentro del bloque secreto, un regalo que movió la
/// reconciliación (cuenta para [kMaxReconcileGifts]). No sale al publicar.
const String kMovedInField = 'movedIn';

/// Campo de un regalo del buzón de una web (1.0.6, ADR 0009): el regalo es
/// un alta de la web. El móvil que recoge el buzón lo quita al aplicarlo.
const String kWebNewField = 'webNew';

/// Registros (vivos y lápidas) que admite un buzón de una web: si trae más,
/// se rechaza entero.
const int kMaxWebInboxRecords = 40;

/// Lápidas que admite un buzón de una web.
const int kMaxWebInboxTombstones = 10;

/// Lápidas de webs que recoge un móvil en un día (UTC); lo demás espera.
const int kMaxWebTombstonesPerDay = 20;

/// Tamaño máximo del JSON canónico de un regalo vivo del bloque secreto. Con
/// [kLegacySlotGifts] regalos así, lo comprimido siempre cabe en el relleno.
const int kMaxSurpriseGiftBytes = 1900;

/// Tamaño máximo del JSON del slot sin comprimir: muy por debajo de lo que
/// se acepta al abrir, para que todo lo que se sella se pueda abrir (M4).
const int kMaxSlotJsonBytes = 1024 * 1024;

/// Tamaño fijo del texto en claro de un slot (128 KiB).
const int kSlotPlainBytes = 128 * 1024;

/// Revisión más alta de un slot (cabe en un entero de JavaScript).
const int kMaxSlotRevision = 0x1FFFFFFFFFFFFF;

const _magic = [0x47, 0x48, 0x53]; // "GHS"
const _version = 2;
const _kidLength = 8;
const _fixedHeader = 3 + 1 + 4 + 8 + 1 + 8 + _kidLength;
const _nonceLength = 12;
const _macLength = 16;
const _signatureLength = 64;
const _lengthPrefix = 4;
const _sigDomain = 'gift-huddle-slot-v2';

/// Base de los errores de los slots.
abstract class ProtectedEnvelopeException implements Exception {
  /// Crea el error.
  const ProtectedEnvelopeException(this.message);

  /// Qué pasó (sin claves).
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Bytes que no son un slot válido.
class SlotFormatException extends ProtectedEnvelopeException {
  /// Crea el error.
  const SlotFormatException(super.message);
}

/// Firma falsa, escritor desconocido, clave equivocada o bytes manipulados.
class SlotAuthException extends ProtectedEnvelopeException {
  /// Crea el error.
  const SlotAuthException(super.message);
}

/// El slot es de otra lista, persona, época o clave.
class SlotWrongScopeException extends ProtectedEnvelopeException {
  /// Crea el error.
  const SlotWrongScopeException(super.message);
}

/// Más de [kMaxSurpriseGifts] regalos sorpresa para una persona.
class SurpriseCapacityException extends ProtectedEnvelopeException {
  /// Crea el error.
  const SurpriseCapacityException(this.count)
    : super('caben $kMaxSurpriseGifts regalos sorpresa por persona');

  /// Regalos vivos que se intentaron guardar.
  final int count;
}

/// Un regalo del bloque secreto pasa de [kMaxSurpriseGiftBytes].
class SurpriseGiftTooLargeException extends ProtectedEnvelopeException {
  /// Crea el error.
  const SurpriseGiftTooLargeException(this.giftId)
    : super('un regalo sorpresa tiene demasiado texto');

  /// Id del regalo.
  final String giftId;
}

/// Lo comprimido no cabe en el tamaño fijo del slot.
class SurpriseSlotFullException extends ProtectedEnvelopeException {
  /// Crea el error.
  const SurpriseSlotFullException()
    : super('el bloque de sorpresas está lleno');
}

/// La versión de un slot: época y revisión. Se ordena por época y después
/// por revisión.
class SlotVersion implements Comparable<SlotVersion> {
  /// Crea la versión.
  const SlotVersion(this.epoch, this.revision);

  /// Época.
  final int epoch;

  /// Revisión.
  final int revision;

  @override
  int compareTo(SlotVersion other) => epoch != other.epoch
      ? epoch.compareTo(other.epoch)
      : revision.compareTo(other.revision);

  @override
  bool operator ==(Object other) =>
      other is SlotVersion &&
      other.epoch == epoch &&
      other.revision == revision;

  @override
  int get hashCode => Object.hash(epoch, revision);

  @override
  String toString() => 'e$epoch r$revision';
}

/// La cabecera de un slot (en claro, autenticada por la firma).
class SlotHeader {
  /// Crea la cabecera.
  const SlotHeader({
    required this.listId,
    required this.personId,
    required this.epoch,
    required this.writer,
    required this.revision,
    required this.policy,
    required this.kid,
  });

  /// Lista.
  final String listId;

  /// Persona protegida (el ámbito).
  final String personId;

  /// Época de la clave de sorpresas.
  final int epoch;

  /// Móvil que escribió el slot.
  final String writer;

  /// Revisión del escritor: el momento de sellar. No cuenta ediciones.
  final int revision;

  /// Política con la que escribió el escritor. Va firmada: se puede leer y
  /// comprobar sin la clave de sorpresas.
  final PolicyState policy;

  /// Qué clave de la época selló el slot ([SurpriseKey.kid]).
  final String kid;

  /// Época y revisión.
  SlotVersion get version => SlotVersion(epoch, revision);

  /// Los bytes de la cabecera (el AAD).
  Uint8List toBytes() {
    _check();
    final ids = [listId, personId, writer].map(ascii.encode).toList();
    final out = BytesBuilder(copy: false)
      ..add(_magic)
      ..addByte(_version);
    final fixed = ByteData(21)
      ..setUint32(0, epoch)
      ..setUint32(4, revision ~/ 0x100000000)
      ..setUint32(8, revision % 0x100000000)
      ..setUint8(12, policy.hideOwnGifts ? 1 : 0)
      ..setUint32(13, policy.rev ~/ 0x100000000)
      ..setUint32(17, policy.rev % 0x100000000);
    out
      ..add(fixed.buffer.asUint8List())
      ..add(_kidBytes(kid));
    for (final id in ids) {
      out
        ..addByte(id.length)
        ..add(id);
    }
    return out.toBytes();
  }

  static List<int> _kidBytes(String kid) => [
    for (var i = 0; i < _kidLength; i++)
      int.parse(kid.substring(2 * i, 2 * i + 2), radix: 16),
  ];

  void _check() {
    if (!kSyncIdPattern.hasMatch(listId) ||
        !kSyncIdPattern.hasMatch(personId) ||
        !kSyncIdPattern.hasMatch(writer)) {
      throw const SlotFormatException('identificador no válido');
    }
    if (epoch < 1 || epoch > 0xFFFFFFFF) {
      throw const SlotFormatException('época fuera de rango');
    }
    if (revision < 1 || revision > kMaxSlotRevision) {
      throw const SlotFormatException('revisión fuera de rango');
    }
    if (!RegExp(r'^[0-9a-f]{16}$').hasMatch(kid)) {
      throw const SlotFormatException('clave no válida');
    }
  }

  @override
  String toString() =>
      'SlotHeader($listId, $personId, e$epoch, $writer, r$revision)';
}

/// Lo que hay dentro de un slot abierto.
class OpenedSlot {
  /// Crea el contenido.
  const OpenedSlot({
    required this.header,
    required this.doc,
    required this.seen,
    this.cap = 1,
    this.foreignRecords = 0,
  });

  /// Registros que el escritor metió y que no son del ámbito (de otra
  /// persona u otra colección): al abrir se descartan. Un móvil no los
  /// escribe nunca; en el buzón de una web hacen que se rechace entero.
  final int foreignRecords;

  /// Cabecera.
  final SlotHeader header;

  /// Documento del ámbito: solo los regalos de la persona protegida (y sus
  /// lápidas). Lo que traiga de otra cosa se descarta al abrir.
  final FamilyDoc doc;

  /// Qué slot de cada otro escritor estaba fusionado en esta instantánea.
  final Map<String, SlotVersion> seen;

  /// Capacidad que anuncia el escritor: 1 sin «cap» (1.0.5 y antes, abre
  /// hasta [kLegacySlotGifts]) y [kSlotCapacity] desde la 1.0.6.
  final int cap;

  /// Política con la que escribió el escritor (autenticada).
  PolicyState get policy => header.policy;
}

/// Un slot sellado: opaco para quien no tiene la clave de sorpresas.
class SealedSlot {
  SealedSlot._(this.bytes, this.header, this._headerLength);

  /// Los bytes del slot (no se modifican).
  final Uint8List bytes;

  /// La cabecera leída (sin autenticar hasta [verifySignature] u [open]).
  final SlotHeader header;

  final int _headerLength;

  static final AesGcm _aes = AesGcm.with256bits();

  /// Tamaño total de un slot con esta cabecera.
  static int sizeFor(SlotHeader header) =>
      header.toBytes().length +
      _nonceLength +
      kSlotPlainBytes +
      _macLength +
      _signatureLength;

  /// Lee la estructura de un slot sin clave. Lanza [SlotFormatException].
  static SealedSlot parse(List<int> input) {
    final bytes = Uint8List.fromList(input);
    if (bytes.length < _fixedHeader + 3) {
      throw const SlotFormatException('slot truncado');
    }
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) {
        throw const SlotFormatException('no es un slot de sorpresas');
      }
    }
    if (bytes[3] != _version) {
      throw SlotFormatException('versión ${bytes[3]} no soportada');
    }
    final data = ByteData.sublistView(bytes);
    final epoch = data.getUint32(4);
    final high = data.getUint32(8);
    final low = data.getUint32(12);
    final flags = data.getUint8(16);
    final policyHigh = data.getUint32(17);
    final policyLow = data.getUint32(21);
    if (high > 0x1FFFFF || policyHigh > 0x1FFFFF || flags > 1) {
      throw const SlotFormatException('cabecera fuera de rango');
    }
    final kid = [
      for (var i = 25; i < 25 + _kidLength; i++)
        bytes[i].toRadixString(16).padLeft(2, '0'),
    ].join();
    var offset = _fixedHeader;
    final ids = <String>[];
    for (var i = 0; i < 3; i++) {
      if (offset >= bytes.length) {
        throw const SlotFormatException('slot truncado');
      }
      final length = bytes[offset];
      offset += 1;
      if (offset + length > bytes.length) {
        throw const SlotFormatException('slot truncado');
      }
      try {
        ids.add(ascii.decode(bytes.sublist(offset, offset + length)));
      } on FormatException {
        throw const SlotFormatException('identificador no válido');
      }
      offset += length;
    }
    final header = SlotHeader(
      listId: ids[0],
      personId: ids[1],
      epoch: epoch,
      writer: ids[2],
      revision: high * 0x100000000 + low,
      policy: PolicyState(
        hideOwnGifts: flags == 1,
        rev: policyHigh * 0x100000000 + policyLow,
      ),
      kid: kid,
    );
    header._check();
    final expected =
        offset + _nonceLength + kSlotPlainBytes + _macLength + _signatureLength;
    if (bytes.length != expected) {
      throw const SlotFormatException('tamaño de slot no válido');
    }
    return SealedSlot._(bytes, header, offset);
  }

  /// Cifra y firma la instantánea [doc] del ámbito de [key], con la política
  /// [policy] en la cabecera y [seen] (qué slots de otros lleva fusionados).
  ///
  /// [doc] solo puede tener la colección de regalos, y todos sus regalos
  /// vivos deben ser de `key.personId`. El slot anuncia [kSlotCapacity].
  /// Lanza [SurpriseCapacityException] con más de [kMaxSlotGifts] regalos
  /// vivos (quien publica ajusta antes al límite de los demás escritores con
  /// [fitScopeToSlot] y [slotGiftLimitFor]),
  /// [SurpriseGiftTooLargeException] si uno pasa de
  /// [kMaxSurpriseGiftBytes] y [SurpriseSlotFullException] si el JSON pasa
  /// de [kMaxSlotJsonBytes] o lo comprimido no cabe. Antes de devolverlo lo
  /// vuelve a abrir: nunca sale un slot que no se pueda abrir.
  static Future<SealedSlot> seal({
    required DeviceKeys writerKeys,
    required String writer,
    required int revision,
    required SurpriseKey key,
    required PolicyState policy,
    required FamilyDoc doc,
    Map<String, SlotVersion> seen = const <String, SlotVersion>{},
  }) => _seal(
    writerKeys: writerKeys,
    writer: writer,
    revision: revision,
    key: key,
    policy: policy,
    doc: doc,
    seen: seen,
  );

  /// Igual que [seal] con el nonce dado: SOLO para pruebas y vectores fijos.
  @visibleForTesting
  static Future<SealedSlot> sealForTesting({
    required DeviceKeys writerKeys,
    required String writer,
    required int revision,
    required SurpriseKey key,
    required PolicyState policy,
    required FamilyDoc doc,
    required List<int> nonce,
    Map<String, SlotVersion> seen = const <String, SlotVersion>{},
  }) => _seal(
    writerKeys: writerKeys,
    writer: writer,
    revision: revision,
    key: key,
    policy: policy,
    doc: doc,
    seen: seen,
    nonce: nonce,
  );

  static Future<SealedSlot> _seal({
    required DeviceKeys writerKeys,
    required String writer,
    required int revision,
    required SurpriseKey key,
    required PolicyState policy,
    required FamilyDoc doc,
    required Map<String, SlotVersion> seen,
    List<int>? nonce,
  }) async {
    final header = SlotHeader(
      listId: doc.listId,
      personId: key.personId,
      epoch: key.epoch,
      writer: writer,
      revision: revision,
      policy: policy,
      kid: key.kid,
    );
    final headerBytes = header.toBytes();
    _checkScopeDoc(doc, key.personId);
    final n = nonce ?? secureRandomBytes(_nonceLength);
    if (n.length != _nonceLength) {
      throw ArgumentError.value(n.length, 'nonce', 'debe tener 12 bytes');
    }
    final compressed = _compressedBody(doc, seen);
    if (compressed == null) {
      throw const SurpriseSlotFullException();
    }
    final plain = Uint8List(kSlotPlainBytes);
    ByteData.sublistView(plain).setUint32(0, compressed.length);
    plain.setRange(
      _lengthPrefix,
      _lengthPrefix + compressed.length,
      compressed,
    );
    final box = await _aes.encrypt(
      plain,
      secretKey: SecretKey(key.bytes),
      nonce: n,
      aad: headerBytes,
    );
    final body = BytesBuilder(copy: false)
      ..add(headerBytes)
      ..add(n)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    final unsigned = body.toBytes();
    final signature = await writerKeys.sign(_signedMessage(unsigned));
    final bytes = Uint8List.fromList([...unsigned, ...signature]);
    final slot = SealedSlot._(bytes, header, headerBytes.length);
    // Lo que se publica tiene que poder abrirse.
    await slot.open(
      expectedListId: doc.listId,
      key: key,
      signingKey: writerKeys.publicKeys.signing,
    );
    return slot;
  }

  /// Lo comprimido del cuerpo, o null si no cabe.
  static List<int>? _compressedBody(
    FamilyDoc doc,
    Map<String, SlotVersion> seen,
  ) {
    final json = _bodyJson(doc, seen);
    if (json.length > kMaxSlotJsonBytes) return null;
    final compressed = Deflate(json).getBytes();
    if (compressed.length > kSlotPlainBytes - _lengthPrefix) return null;
    return compressed;
  }

  /// Bytes de lo comprimido (sin el tope del relleno), o infinito si el
  /// JSON pasa de [kMaxSlotJsonBytes].
  static double _compressedBytes(FamilyDoc doc, Map<String, SlotVersion> seen) {
    final json = _bodyJson(doc, seen);
    if (json.length > kMaxSlotJsonBytes) return double.infinity;
    return Deflate(json).getBytes().length.toDouble();
  }

  static List<int> _bodyJson(FamilyDoc doc, Map<String, SlotVersion> seen) =>
      utf8.encode(
        canonicalJsonOf(<String, Object?>{
          'cap': kSlotCapacity,
          'd': doc.toJson(),
          's': <String, Object?>{
            for (final e in seen.entries)
              e.key: <int>[e.value.epoch, e.value.revision],
          },
          'v': _version,
        }),
      );

  /// Si la firma es del escritor, con su clave pública [signingKey]. No
  /// necesita la clave de sorpresas.
  Future<bool> verifySignature(List<int> signingKey) => verifyDeviceSignature(
    message: _signedMessage(
      Uint8List.sublistView(bytes, 0, bytes.length - _signatureLength),
    ),
    signature: Uint8List.sublistView(bytes, bytes.length - _signatureLength),
    signingPublicKey: signingKey,
  );

  /// Abre el slot.
  ///
  /// Comprueba la lista, la persona, la época y la clave esperadas, la firma
  /// con [signingKey] (la del escritor de la cabecera) y el GCM con [key].
  /// Lo de dentro tiene que cumplir los mismos límites que al sellar. Lanza
  /// [ProtectedEnvelopeException] si algo falla.
  Future<OpenedSlot> open({
    required String expectedListId,
    required SurpriseKey key,
    required List<int> signingKey,
  }) async {
    if (header.listId != expectedListId) {
      throw const SlotWrongScopeException('el slot es de otra lista');
    }
    if (header.personId != key.personId ||
        header.epoch != key.epoch ||
        header.kid != key.kid) {
      throw const SlotWrongScopeException('el slot es de otro ámbito o época');
    }
    if (!await verifySignature(signingKey)) {
      throw const SlotAuthException('firma no válida');
    }
    final nonceEnd = _headerLength + _nonceLength;
    final macStart = bytes.length - _signatureLength - _macLength;
    final List<int> plain;
    try {
      plain = await _aes.decrypt(
        SecretBox(
          Uint8List.sublistView(bytes, nonceEnd, macStart),
          nonce: Uint8List.sublistView(bytes, _headerLength, nonceEnd),
          mac: Mac(
            Uint8List.sublistView(bytes, macStart, macStart + _macLength),
          ),
        ),
        secretKey: SecretKey(key.bytes),
        aad: Uint8List.sublistView(bytes, 0, _headerLength),
      );
    } on SecretBoxAuthenticationError {
      throw const SlotAuthException('clave equivocada o slot manipulado');
    }
    final padded = Uint8List.fromList(plain);
    final length = ByteData.sublistView(padded).getUint32(0);
    if (length > kSlotPlainBytes - _lengthPrefix) {
      throw const SlotFormatException('relleno no válido');
    }
    final Uint8List json;
    try {
      json = inflateWithLimit(
        Uint8List.sublistView(padded, _lengthPrefix, _lengthPrefix + length),
      );
    } on EnvelopeTooLargeException {
      throw const SlotFormatException('slot demasiado grande');
    } on EnvelopeException {
      throw const SlotFormatException('slot dañado');
    }
    if (json.length > kMaxSlotJsonBytes) {
      throw const SlotFormatException('slot demasiado grande');
    }
    try {
      final raw = jsonDecode(utf8.decode(json));
      if (raw is! Map ||
          raw['v'] != _version ||
          raw['d'] is! Map ||
          raw['s'] is! Map) {
        throw const SlotFormatException('contenido no válido');
      }
      final doc = FamilyDoc.fromJson(
        Map<String, Object?>.from(raw['d'] as Map),
      );
      if (doc.listId != header.listId) {
        throw const SlotWrongScopeException('documento de otra lista');
      }
      final cap = _capOf(raw['cap']);
      final scope = scopeDocOnly(doc, header.personId);
      var foreign = 0;
      for (final entry in doc.collections.entries) {
        foreign += entry.key == Collections.gifts
            ? entry.value.length -
                  (scope.collections[Collections.gifts]?.length ?? 0)
            : entry.value.length;
      }
      try {
        _checkScopeDoc(
          scope,
          header.personId,
          maxLive: cap >= kSlotCapacity ? kMaxSlotGifts : kLegacySlotGifts,
        );
      } on ProtectedEnvelopeException {
        // Lo que no se podría sellar tampoco se acepta al abrir (N3).
        throw const SlotFormatException('contenido fuera de los límites');
      }
      return OpenedSlot(
        header: header,
        doc: scope,
        seen: _seenOf(raw['s'] as Map),
        cap: cap,
        foreignRecords: foreign,
      );
    } on ProtectedEnvelopeException {
      rethrow;
    } on FormatException {
      throw const SlotFormatException('contenido dañado');
    }
  }

  /// «cap» del JSON: 1 si no está (1.0.5), un entero positivo si está.
  static int _capOf(Object? raw) {
    if (raw == null) return 1;
    if (raw is! int || raw < 1) {
      throw const SlotFormatException('contenido no válido');
    }
    return raw;
  }

  static Map<String, SlotVersion> _seenOf(Map<Object?, Object?> raw) {
    final out = <String, SlotVersion>{};
    for (final e in raw.entries) {
      final key = e.key;
      final value = e.value;
      if (key is! String ||
          !kSyncIdPattern.hasMatch(key) ||
          value is! List ||
          value.length != 2 ||
          value[0] is! int ||
          value[1] is! int) {
        throw const SlotFormatException('contenido no válido');
      }
      out[key] = SlotVersion(value[0] as int, value[1] as int);
    }
    return Map.unmodifiable(out);
  }

  static List<int> _signedMessage(Uint8List unsigned) => [
    ...utf8.encode(_sigDomain),
    0,
    ...unsigned,
  ];

  static void _checkScopeDoc(
    FamilyDoc doc,
    String personId, {
    int maxLive = kMaxSlotGifts,
  }) {
    for (final name in doc.collections.keys) {
      if (name != Collections.gifts) {
        throw ArgumentError.value(
          name,
          'doc',
          'un slot solo guarda regalos de la persona protegida',
        );
      }
    }
    final gifts = doc.collections[Collections.gifts] ?? const {};
    var live = 0;
    for (final record in gifts.values) {
      if (record.isDeleted) continue;
      if (record['recipientId'] != personId) {
        throw ArgumentError.value(
          record.id,
          'doc',
          'un regalo del slot es de otra persona',
        );
      }
      if (surpriseRecordBytes(record) > kMaxSurpriseGiftBytes) {
        throw SurpriseGiftTooLargeException(record.id);
      }
      live++;
    }
    if (live > maxLive) {
      throw SurpriseCapacityException(live);
    }
  }
}

/// Regalos vivos que puede sellar un escritor, según lo que anuncian los
/// slots abiertos de los demás escritores con derecho ([peers]; null si de
/// alguno no hay slot abierto). Solo se pasa de [kLegacySlotGifts] si todos
/// anuncian [kSlotCapacity]: un 1.0.5 no abriría un slot más grande, y uno
/// que aún no ha publicado o no se ha podido leer podría ser un 1.0.5.
int slotGiftLimitFor(Iterable<OpenedSlot?> peers) =>
    peers.every((p) => p != null && p.cap >= kSlotCapacity)
    ? kMaxSlotGifts
    : kLegacySlotGifts;

/// Qué parte del relleno de un slot ocupa [doc] comprimido (0 vacío, 1
/// lleno; más de 1 si no cabe). Para el medidor «casi lleno» de la interfaz.
double slotUsage(
  FamilyDoc doc, {
  Map<String, SlotVersion> seen = const <String, SlotVersion>{},
}) =>
    SealedSlot._compressedBytes(doc, seen) / (kSlotPlainBytes - _lengthPrefix);

/// Si [doc] cabe en un slot de [maxLive] regalos vivos (sin cifrar nada). Lo
/// usa la reconciliación para no dejar nunca un ámbito que no se pueda
/// sellar.
bool scopeFitsInSlot(
  FamilyDoc doc,
  String personId, {
  Map<String, SlotVersion> seen = const <String, SlotVersion>{},
  int maxLive = kMaxSlotGifts,
}) {
  try {
    SealedSlot._checkScopeDoc(doc, personId, maxLive: maxLive);
  } on ProtectedEnvelopeException {
    return false;
  } on ArgumentError {
    return false;
  }
  return SealedSlot._compressedBody(doc, seen) != null;
}

/// La parte de [doc] que cabe en un slot y los regalos vivos que se quedan
/// fuera (N3).
///
/// Lo normal es que quepa todo. Si al fusionar varios escritores hay más de
/// [maxLive] vivos (cada uno llenó el suyo sin red, o algún otro escritor es
/// un 1.0.5: [slotGiftLimitFor]) o lo comprimido no cabe, este escritor
/// sella los que caben, por orden: primero los de la interfaz por id y
/// después los que movió la reconciliación. Los demás siguen en su copia
/// local y en los slots de quien los escribió, y vuelven a entrar cuando
/// haya sitio; publicar nunca se bloquea por eso. Lanza
/// [SurpriseSlotFullException] solo si ni las lápidas caben.
(FamilyDoc, List<String>) fitScopeToSlot(
  FamilyDoc doc,
  String personId, {
  Map<String, SlotVersion> seen = const <String, SlotVersion>{},
  int maxLive = kMaxSlotGifts,
}) {
  if (scopeFitsInSlot(doc, personId, seen: seen, maxLive: maxLive)) {
    return (doc, const []);
  }
  final gifts = doc.collections[Collections.gifts] ?? const {};
  final dead = <String, SyncRecord>{
    for (final r in gifts.values)
      if (r.isDeleted) r.id: r,
  };
  final live =
      [
        for (final r in gifts.values)
          if (!r.isDeleted &&
              r['recipientId'] == personId &&
              surpriseRecordBytes(r) <= kMaxSurpriseGiftBytes)
            r,
      ]..sort((a, b) {
        final am = a[kMovedInField] == true ? 1 : 0;
        final bm = b[kMovedInField] == true ? 1 : 0;
        return am != bm ? am.compareTo(bm) : a.id.compareTo(b.id);
      });
  FamilyDoc withFirst(int n) => FamilyDoc(
    listId: doc.listId,
    collections: {
      Collections.gifts: {...dead, for (final r in live.take(n)) r.id: r},
    },
  );
  bool fits(int n) =>
      scopeFitsInSlot(withFirst(n), personId, seen: seen, maxLive: maxLive);
  if (!fits(0)) throw const SurpriseSlotFullException();
  // Búsqueda binaria de un n que cabe: con hasta kMaxSlotGifts, ir de uno en
  // uno comprimiría el bloque entero cientos de veces. DEFLATE no garantiza
  // que con menos regalos lo comprimido no crezca, así que puede quedar fuera
  // alguno que habría cabido; lo que se devuelve siempre está comprobado (y
  // el sellado lo vuelve a comprobar), y lo que queda fuera sigue en local.
  var low = 0;
  var high = live.length < maxLive ? live.length : maxLive;
  while (low < high) {
    final mid = (low + high + 1) ~/ 2;
    if (fits(mid)) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  final kept = {for (final r in live.take(low)) r.id};
  return (
    withFirst(low),
    [
      for (final r in gifts.values)
        if (!r.isDeleted && !kept.contains(r.id)) r.id,
    ]..sort(),
  );
}

/// Bytes del JSON canónico de un registro (sus campos con sus marcas).
int surpriseRecordBytes(SyncRecord record) => utf8
    .encode(
      canonicalJsonOf(<String, Object?>{
        for (final e in record.fields.entries)
          e.key: <Object?>[e.value.value, e.value.stamp.pack()],
      }),
    )
    .length;

/// Añade (o edita) un regalo sorpresa desde la interfaz.
///
/// Lanza [SurpriseCapacityException] si ya hay [kMaxSurpriseGifts] regalos
/// vivos de la interfaz y es uno nuevo (los que movió la reconciliación
/// tienen su propio cupo y no cuentan, N2), y
/// [SurpriseGiftTooLargeException] si el regalo pasa de
/// [kMaxSurpriseGiftBytes]. El bloque nunca crece por encima.
FamilyDoc addSurpriseGift(
  FamilyDoc scope,
  HlcClock scopeClock,
  String giftId,
  Map<String, Object?> fields,
) {
  final existing = scope.record(Collections.gifts, giftId);
  final isNew = existing == null || existing.isDeleted;
  if (isNew && liveOwnSurpriseGifts(scope) >= kMaxSurpriseGifts) {
    throw SurpriseCapacityException(liveOwnSurpriseGifts(scope) + 1);
  }
  final next = scope.setChanged(scopeClock, Collections.gifts, giftId, {
    for (final e in fields.entries)
      if (e.key != kMovedInField) e.key: e.value,
  });
  final record = next.record(Collections.gifts, giftId);
  if (record != null &&
      !record.isDeleted &&
      surpriseRecordBytes(record) > kMaxSurpriseGiftBytes) {
    throw SurpriseGiftTooLargeException(giftId);
  }
  return next;
}

/// [doc] con solo los regalos de [personId] y las lápidas. Se usa al abrir
/// un slot: un escritor no puede colar nada más en el ámbito.
FamilyDoc scopeDocOnly(FamilyDoc doc, String personId) {
  final gifts = doc.collections[Collections.gifts] ?? const {};
  return FamilyDoc(
    listId: doc.listId,
    collections: {
      Collections.gifts: {
        for (final record in gifts.values)
          if (record.isDeleted || record['recipientId'] == personId)
            record.id: record,
      },
    },
  );
}

Iterable<SyncRecord> _liveGifts(FamilyDoc scopeDoc) =>
    (scopeDoc.collections[Collections.gifts]?.values ?? const <SyncRecord>[])
        .where((r) => !r.isDeleted);

/// Regalos vivos de un documento de ámbito.
int liveSurpriseGifts(FamilyDoc scopeDoc) => _liveGifts(scopeDoc).length;

/// Regalos vivos que cuentan para el cupo de la interfaz
/// ([kMaxSurpriseGifts]): todos menos los que movió la reconciliación.
int liveOwnSurpriseGifts(FamilyDoc scopeDoc) =>
    _liveGifts(scopeDoc).where((r) => r[kMovedInField] != true).length;

/// Regalos vivos que movió la reconciliación ([kMaxReconcileGifts]).
int liveMovedInGifts(FamilyDoc scopeDoc) =>
    _liveGifts(scopeDoc).where((r) => r[kMovedInField] == true).length;
