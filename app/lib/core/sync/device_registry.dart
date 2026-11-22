// Registro firmado de móviles de la familia. Dart puro.
// Decisión: docs/adr/0004-yo-sorpresas-revocar.md (fase 2a).
//
// El registro es un conjunto de declaraciones firmadas que se fusiona por
// unión (conmutativa, asociativa e idempotente mientras quepa):
// - **Ficha** (`DeviceRecord`): «soy el móvil D, estas son mis claves
//   públicas y mi persona es Q», firmada por el propio móvil. Cambiar de
//   persona es una ficha nueva con `seq` mayor; la que vale es la de `seq`
//   más alto.
// - **Aval** (`Vouch`): «el móvil V, con su ficha RV, confirma la ficha R de
//   D», firmado por V. Va ligado al resumen de la ficha avalada (claves,
//   persona y `seq`: una ficha nueva necesita avales nuevos) y al de la ficha
//   del avalista (hallazgo 5: para las sorpresas de P solo cuenta si V no era
//   de P, ni estaba sin persona, cuando avaló). Nadie se avala a sí mismo.
// - **Revocación** (`Revocation`): «el móvil V, con su ficha RV, revoca a
//   D», firmada por V. Es definitiva: un id revocado no vuelve.
//
// No hay un móvil raíz. Cada móvil lee el registro desde su propio punto de
// vista (`RegistryView`), con él mismo como ancla:
// - **De la familia** son los móviles a los que llega una cadena de avales
//   que empieza en él y no pasa por un revocado (al revocado se llega, pero
//   lo que avala no cuenta: segunda revisión de la fase 2a, N1). El
//   emparejamiento en persona crea dos avales, uno en cada sentido.
// - **Revocados:** los que revoca cualquier móvil que alguna vez fue de la
//   familia, contando la cadena sin mirar revocaciones (aunque después lo
//   revoquen a él: revocar gana). Un móvil no
//   acepta su propia revocación para decidir en quién confía (así un móvil
//   robado no deja a los demás sin familia), pero la enseña
//   (`revokedByOthers`).
// - **Activos:** de la familia, no revocados, y con su ficha actual avalada
//   por otro activo.
// - **Con derecho a las sorpresas de P** (un solo predicado para recibir la
//   clave, escribir slots y autenticar la política): activo, con una persona
//   que existe y que no es P, y cuya ficha actual avala otro móvil que
//   también tiene ese derecho y que, al avalar, no era de P ni estaba sin
//   persona; la cadena empieza en este móvil, que nunca es de P. El móvil de
//   P (o uno sin persona) no tiene la clave: para guardar y reenviar slots
//   (`relayable`) solo comprueba que el escritor es activo y su persona no
//   es P.
// - **Época:** 1 + revocados + cambios de ficha. Solo sube. Cada revocación o
//   cambio de persona abre una época, y con ella se rotan las claves.
// - Si dos fichas avaladas dan claves distintas al mismo id, o un móvil
//   firma dos fichas distintas con el mismo `seq` más alto (N6), ese id deja
//   de resolverse (falla en cerrado).
// - **Solo entra lo verificado** (revisión de la fase 2a, hallazgo 4): una
//   ficha, con su firma; un aval o una revocación, solo si su firma es de la
//   ficha del firmante que cita y que ya está en el registro (y el aval, de
//   una ficha avalada que también está). Así el registro se lee sin volver a
//   comprobar firmas (hallazgo 9).
// - **Topes y basura:** cupos por móvil (fichas por id, avales y
//   revocaciones por firmante) y topes globales. Con un ancla (el móvil que
//   guarda el registro), cuando no cabe se desaloja primero lo que no está
//   enlazado con él por una cadena de avales: la basura no ocupa el sitio de
//   lo de la familia, y una revocación de un móvil enlazado siempre entra.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';

import 'device_keys.dart';
import 'envelope.dart' show decodeBase64Url, encodeBase64Url;

/// Versión del formato del registro.
const int kRegistryVersion = 2;

/// Fichas que admite un registro (todas las versiones de todos los móviles).
const int kMaxRegistryRecords = 64;

/// Avales que admite un registro.
const int kMaxRegistryVouches = 256;

/// Revocaciones que admite un registro.
const int kMaxRegistryRevocations = 64;

/// `seq` más alto de una ficha: como mucho 15 cambios de persona por móvil.
/// La época suma los cambios de ficha, así que esto también acota cuánto
/// puede inflarla un móvil (hallazgo 7).
const int kMaxDeviceSeq = 16;

/// Fichas que admite un mismo id de móvil (versiones y claves distintas).
const int kMaxRecordsPerDevice = 16;

/// Avales que puede firmar un mismo móvil.
const int kMaxVouchesPerSigner = 32;

/// Revocaciones que puede firmar un mismo móvil.
const int kMaxRevocationsPerSigner = 32;

const _recordDomain = 'gift-huddle-device-v2';
const _vouchDomain = 'gift-huddle-vouch-v2';
const _revocationDomain = 'gift-huddle-revoke-v2';

/// Una declaración del registro que no vale o un registro que no cabe.
class RegistryException implements Exception {
  /// Crea el error.
  const RegistryException(this.message);

  /// Qué pasó (sin claves).
  final String message;

  @override
  String toString() => 'RegistryException: $message';
}

/// El ancla tiene fichas incompatibles de móvil y web con la misma clave.
class RegistryIdentityAmbiguousException extends RegistryException {
  const RegistryIdentityAmbiguousException()
    : super('este dispositivo tiene fichas de móvil y web');
}

List<int> _signed(String domain, Map<String, Object?> fields) => [
  ...utf8.encode(domain),
  0,
  ...canonicalHeaderBytes(fields),
];

Uint8List _bytesOf(Object? value, int length) {
  if (value is! String) throw const RegistryException('declaración no válida');
  final Uint8List bytes;
  try {
    bytes = decodeBase64Url(value);
  } on FormatException {
    throw const RegistryException('declaración no válida');
  }
  if (bytes.length != length) {
    throw const RegistryException('declaración no válida');
  }
  return bytes;
}

String _idOf(Object? value) {
  if (value is! String || !kSyncIdPattern.hasMatch(value)) {
    throw const RegistryException('identificador no válido');
  }
  return value;
}

/// Tipo firmado de la identidad; los móviles omiten `k` en el formato v2.
enum DeviceKind { mobile, web }

/// La ficha de un dispositivo, firmada por él mismo.
class DeviceRecord {
  DeviceRecord._({
    required this.listId,
    required this.deviceId,
    required this.keys,
    required this.personId,
    required this.seq,
    required this.kind,
    required this.signature,
  }) : digest = encodeBase64Url(
         const DartSha256().hashSync([
           ..._message(listId, deviceId, keys, personId, seq, kind),
           ...signature,
         ]).bytes,
       );

  /// Lista.
  final String listId;

  /// Id del móvil.
  final String deviceId;

  /// Sus claves públicas.
  final DevicePublicKeys keys;

  /// La persona dueña del móvil, o null si aún no la tiene.
  final String? personId;

  /// Versión de la ficha: sube al cambiar de persona.
  final int seq;

  /// Capacidad de la identidad, inmutable incluso entre fichas históricas.
  final DeviceKind kind;

  /// Firma Ed25519 del propio móvil.
  final Uint8List signature;

  /// Resumen de la ficha (SHA-256 de lo firmado y la firma, en base64url):
  /// lo que citan los avales y los paquetes de claves.
  final String digest;

  static List<int> _message(
    String listId,
    String deviceId,
    DevicePublicKeys keys,
    String? personId,
    int seq,
    DeviceKind kind,
  ) => _signed(_recordDomain, <String, Object?>{
    'd': deviceId,
    'e': encodeBase64Url(keys.signing),
    if (kind == DeviceKind.web) 'k': 'web',
    'l': listId,
    'n': seq,
    'p': personId,
    'v': kRegistryVersion,
    'x': encodeBase64Url(keys.agreement),
  });

  static void _check(String listId, String deviceId, String? person, int seq) {
    if (!kSyncIdPattern.hasMatch(listId) ||
        !kSyncIdPattern.hasMatch(deviceId) ||
        (person != null && !kSyncIdPattern.hasMatch(person)) ||
        seq < 1 ||
        seq > kMaxDeviceSeq) {
      throw const RegistryException('ficha no válida');
    }
  }

  /// Crea y firma la ficha de este móvil.
  static Future<DeviceRecord> create({
    required DeviceKeys keys,
    required String listId,
    required String deviceId,
    required String? personId,
    int seq = 1,
    DeviceKind kind = DeviceKind.mobile,
  }) async {
    _check(listId, deviceId, personId, seq);
    return DeviceRecord._(
      listId: listId,
      deviceId: deviceId,
      keys: keys.publicKeys,
      personId: personId,
      seq: seq,
      kind: kind,
      signature: await keys.sign(
        _message(listId, deviceId, keys.publicKeys, personId, seq, kind),
      ),
    );
  }

  /// Si la firma es de la clave de la propia ficha.
  Future<bool> verify() => verifyDeviceSignature(
    message: _message(listId, deviceId, keys, personId, seq, kind),
    signature: signature,
    signingPublicKey: keys.signing,
  );

  /// La ficha en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'v': kRegistryVersion,
    'l': listId,
    'd': deviceId,
    'e': encodeBase64Url(keys.signing),
    'x': encodeBase64Url(keys.agreement),
    'p': personId,
    'n': seq,
    if (kind == DeviceKind.web) 'k': 'web',
    'sig': encodeBase64Url(signature),
  };

  /// Lee [toJson] sin comprobar la firma. Lanza [RegistryException].
  factory DeviceRecord.fromJson(Object? json) {
    if (json is! Map || json['v'] != kRegistryVersion) {
      throw const RegistryException('ficha no válida');
    }
    final person = json['p'];
    final seq = json['n'];
    if ((person != null && person is! String) ||
        seq is! int ||
        (json.containsKey('k') && json['k'] != 'web')) {
      throw const RegistryException('ficha no válida');
    }
    final listId = _idOf(json['l']);
    final deviceId = _idOf(json['d']);
    _check(listId, deviceId, person as String?, seq);
    return DeviceRecord._(
      listId: listId,
      deviceId: deviceId,
      keys: DevicePublicKeys(
        agreement: _bytesOf(json['x'], 32),
        signing: _bytesOf(json['e'], 32),
      ),
      personId: person,
      seq: seq,
      kind: json.containsKey('k') ? DeviceKind.web : DeviceKind.mobile,
      signature: _bytesOf(json['sig'], 64),
    );
  }
}

/// El aval de un móvil a la ficha de otro.
class Vouch {
  Vouch._({
    required this.listId,
    required this.deviceId,
    required this.recordDigest,
    required this.by,
    required this.byRecord,
    required this.signature,
  });

  /// Lista.
  final String listId;

  /// Móvil avalado.
  final String deviceId;

  /// Resumen de la ficha avalada.
  final String recordDigest;

  /// Móvil que avala.
  final String by;

  /// Resumen de la ficha de quien avala cuando avaló (hallazgo 5).
  final String byRecord;

  /// Firma Ed25519 de quien avala.
  final Uint8List signature;

  static List<int> _message(
    String listId,
    String deviceId,
    String digest,
    String by,
    String byRecord,
  ) => _signed(_vouchDomain, <String, Object?>{
    'br': byRecord,
    'by': by,
    'd': deviceId,
    'l': listId,
    'r': digest,
    'v': kRegistryVersion,
  });

  /// El móvil de [voucher] (su ficha actual), con sus claves [keys], avala
  /// [record]. Lanza [RegistryException] si se avala a sí mismo, si las
  /// fichas son de listas distintas o si [keys] no son las de [voucher].
  static Future<Vouch> create({
    required DeviceKeys keys,
    required DeviceRecord voucher,
    required DeviceRecord record,
  }) async {
    if (voucher.deviceId == record.deviceId) {
      throw const RegistryException('nadie se avala a sí mismo');
    }
    if (voucher.listId != record.listId ||
        !constantTimeEquals(voucher.keys.signing, keys.publicKeys.signing)) {
      throw const RegistryException('aval no válido');
    }
    final by = voucher.deviceId;
    return Vouch._(
      listId: record.listId,
      deviceId: record.deviceId,
      recordDigest: record.digest,
      by: by,
      byRecord: voucher.digest,
      signature: await keys.sign(
        _message(
          record.listId,
          record.deviceId,
          record.digest,
          by,
          voucher.digest,
        ),
      ),
    );
  }

  /// Si la firma es de [signingKey] (la clave de firma de quien avala).
  Future<bool> verify(List<int> signingKey) => verifyDeviceSignature(
    message: _message(listId, deviceId, recordDigest, by, byRecord),
    signature: signature,
    signingPublicKey: signingKey,
  );

  /// El aval en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'v': kRegistryVersion,
    'l': listId,
    'd': deviceId,
    'r': recordDigest,
    'by': by,
    'br': byRecord,
    'sig': encodeBase64Url(signature),
  };

  /// Lee [toJson] sin comprobar la firma. Lanza [RegistryException].
  factory Vouch.fromJson(Object? json) {
    if (json is! Map || json['v'] != kRegistryVersion) {
      throw const RegistryException('aval no válido');
    }
    final by = _idOf(json['by']);
    final deviceId = _idOf(json['d']);
    if (by == deviceId) throw const RegistryException('aval no válido');
    return Vouch._(
      listId: _idOf(json['l']),
      deviceId: deviceId,
      recordDigest: encodeBase64Url(_bytesOf(json['r'], 32)),
      by: by,
      byRecord: encodeBase64Url(_bytesOf(json['br'], 32)),
      signature: _bytesOf(json['sig'], 64),
    );
  }
}

/// La revocación de un móvil.
class Revocation {
  Revocation._({
    required this.listId,
    required this.deviceId,
    required this.by,
    required this.byRecord,
    required this.signature,
  });

  /// Lista.
  final String listId;

  /// Móvil revocado.
  final String deviceId;

  /// Móvil que revoca.
  final String by;

  /// Resumen de la ficha de quien revoca cuando revocó.
  final String byRecord;

  /// Firma Ed25519 de quien revoca.
  final Uint8List signature;

  static List<int> _message(
    String listId,
    String deviceId,
    String by,
    String byRecord,
  ) => _signed(_revocationDomain, <String, Object?>{
    'br': byRecord,
    'by': by,
    'd': deviceId,
    'l': listId,
    'v': kRegistryVersion,
  });

  /// El móvil de [by] (su ficha actual), con sus claves [keys], revoca a
  /// [deviceId].
  static Future<Revocation> create({
    required DeviceKeys keys,
    required DeviceRecord by,
    required String deviceId,
  }) async {
    if (!kSyncIdPattern.hasMatch(deviceId) ||
        by.deviceId == deviceId ||
        !constantTimeEquals(by.keys.signing, keys.publicKeys.signing)) {
      throw const RegistryException('revocación no válida');
    }
    return Revocation._(
      listId: by.listId,
      deviceId: deviceId,
      by: by.deviceId,
      byRecord: by.digest,
      signature: await keys.sign(
        _message(by.listId, deviceId, by.deviceId, by.digest),
      ),
    );
  }

  Future<bool> _verify(List<int> signingKey) => verifyDeviceSignature(
    message: _message(listId, deviceId, by, byRecord),
    signature: signature,
    signingPublicKey: signingKey,
  );

  /// La revocación en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'v': kRegistryVersion,
    'l': listId,
    'd': deviceId,
    'by': by,
    'br': byRecord,
    'sig': encodeBase64Url(signature),
  };

  /// Lee [toJson] sin comprobar la firma. Lanza [RegistryException].
  factory Revocation.fromJson(Object? json) {
    if (json is! Map || json['v'] != kRegistryVersion) {
      throw const RegistryException('revocación no válida');
    }
    final by = _idOf(json['by']);
    final deviceId = _idOf(json['d']);
    if (by == deviceId) throw const RegistryException('revocación no válida');
    return Revocation._(
      listId: _idOf(json['l']),
      deviceId: deviceId,
      by: by,
      byRecord: encodeBase64Url(_bytesOf(json['br'], 32)),
      signature: _bytesOf(json['sig'], 64),
    );
  }
}

/// Lo que este móvil sabe de otro de la familia. Solo sale del registro
/// ([RegistryView]): nadie más puede crear una.
class KnownDevice {
  KnownDevice._(DeviceRecord record)
    : deviceId = record.deviceId,
      signingKey = record.keys.signing,
      agreementKey = record.keys.agreement,
      personId = record.personId,
      kind = record.kind,
      recordDigest = record.digest;

  /// Id del móvil.
  final String deviceId;

  /// Clave pública Ed25519.
  final Uint8List signingKey;

  /// Clave pública X25519.
  final Uint8List agreementKey;

  /// Persona dueña del móvil, o null si no tiene.
  final String? personId;

  /// Tipo de la identidad verificada.
  final DeviceKind kind;

  /// Resumen de su ficha actual: los paquetes de claves van ligados a él.
  final String recordDigest;
}

// Un «nodo» es un móvil con unas claves concretas: id ‖ 0 ‖ clave de firma.
String _nodeOf(String deviceId, List<int> signingKey) =>
    '$deviceId\u0000${encodeBase64Url(signingKey)}';

String _recordNode(DeviceRecord record) =>
    _nodeOf(record.deviceId, record.keys.signing);

String _idOfNode(String node) => node.substring(0, node.indexOf('\u0000'));

/// El móvil desde el que se guarda el registro: su id y su clave de firma de
/// verdad. Con él se distingue lo enlazado (cadena de avales desde él) de la
/// basura cuando el registro no cabe.
class RegistryAnchor {
  /// Crea el ancla.
  const RegistryAnchor({required this.deviceId, required this.signingKey});

  /// Id de este móvil.
  final String deviceId;

  /// Su clave pública de firma.
  final List<int> signingKey;

  String get _node => _nodeOf(deviceId, signingKey);
}

/// Una declaración ya verificada, con el nodo que la firmó.
class _Signed<T> {
  const _Signed(this.value, this.signer, this.signature);

  final T value;
  final String signer;
  final String signature;
}

/// El registro de móviles de una lista. Inmutable, y todo lo que tiene está
/// verificado.
class DeviceRegistry {
  DeviceRegistry._(
    this.listId,
    this._records,
    this._vouches,
    this._revocations, [
    this._typeConflicts = const <String>{},
  ]);

  /// Un registro vacío.
  factory DeviceRegistry.empty(String listId) {
    if (!kSyncIdPattern.hasMatch(listId)) {
      throw const RegistryException('lista no válida');
    }
    return DeviceRegistry._(listId, const {}, const {}, const {});
  }

  /// Lista.
  final String listId;

  // Memoria local de identidades enlazadas que mezclaron tipos. No viaja en
  // el registro compartido: una marca sin firmas recibida de la red no vale.
  final Set<String> _typeConflicts;

  // Por resumen; por (nodo que avala, resumen avalado); por (nodo que revoca,
  // móvil revocado). Un firmante que firma dos veces lo mismo no ocupa dos
  // sitios.
  final Map<String, DeviceRecord> _records;
  final Map<String, _Signed<Vouch>> _vouches;
  final Map<String, _Signed<Revocation>> _revocations;

  /// Todas las fichas, ordenadas.
  List<DeviceRecord> get records => [
    for (final k in _records.keys.toList()..sort()) _records[k]!,
  ];

  /// Todos los avales, ordenados.
  List<Vouch> get vouches => [
    for (final k in _vouches.keys.toList()..sort()) _vouches[k]!.value,
  ];

  /// Todas las revocaciones, ordenadas.
  List<Revocation> get revocations => [
    for (final k in _revocations.keys.toList()..sort()) _revocations[k]!.value,
  ];

  /// La ficha con ese resumen, o null.
  DeviceRecord? recordByDigest(String digest) => _records[digest];

  /// La ficha de [deviceId] con el `seq` más alto entre las firmadas con
  /// [signingKey], o null si no existe o hay tipos incompatibles.
  DeviceRecord? _current(String deviceId, List<int> signingKey) {
    if (_mixedKinds(_records, _nodeOf(deviceId, signingKey), _typeConflicts)) {
      return null;
    }
    return _latest(deviceId, signingKey);
  }

  // También se usa para sumar secuencias de identidades ambiguas, sin
  // resolverlas ni concederles autoridad.
  DeviceRecord? _latest(String deviceId, List<int> signingKey) {
    DeviceRecord? best;
    for (final r in _records.values) {
      if (r.deviceId != deviceId ||
          !constantTimeEquals(r.keys.signing, signingKey)) {
        continue;
      }
      if (best == null ||
          r.seq > best.seq ||
          (r.seq == best.seq && r.digest.compareTo(best.digest) > 0)) {
        best = r;
      }
    }
    return best;
  }

  static bool _mixedKinds(
    Map<String, DeviceRecord> records,
    String node, [
    Set<String> conflicts = const <String>{},
  ]) {
    if (conflicts.contains(node)) return true;
    // La identidad es id + Ed25519. Cambiar X25519 no cambia quién firma.
    DeviceKind? kind;
    for (final record in records.values) {
      if (_recordNode(record) != node) continue;
      if (kind != null && kind != record.kind) return true;
      kind = record.kind;
    }
    return false;
  }

  static bool _mayDeclare(
    Map<String, DeviceRecord> records,
    String digest, [
    Set<String> conflicts = const <String>{},
  ]) {
    final record = records[digest];
    return record != null &&
        record.kind == DeviceKind.mobile &&
        !_mixedKinds(records, _recordNode(record), conflicts);
  }

  // ------------------------------------------------------------ verificar

  /// El nodo de la ficha [byRecord] de [by] en [records] si su clave
  /// verifica la firma, o null.
  static Future<String?> _signerOf(
    Map<String, DeviceRecord> records,
    String by,
    String byRecord,
    Future<bool> Function(List<int> signingKey) verify,
  ) async {
    final record = records[byRecord];
    if (record == null ||
        record.deviceId != by ||
        !_mayDeclare(records, byRecord)) {
      return null;
    }
    return await verify(record.keys.signing) ? _recordNode(record) : null;
  }

  static Future<_Signed<Vouch>?> _checkVouch(
    Map<String, DeviceRecord> records,
    String listId,
    Vouch vouch,
  ) async {
    if (vouch.listId != listId) return null;
    final target = records[vouch.recordDigest];
    if (target == null || target.deviceId != vouch.deviceId) return null;
    final signer = await _signerOf(
      records,
      vouch.by,
      vouch.byRecord,
      vouch.verify,
    );
    if (signer == null) return null;
    return _Signed(vouch, signer, encodeBase64Url(vouch.signature));
  }

  static Future<_Signed<Revocation>?> _checkRevocation(
    Map<String, DeviceRecord> records,
    String listId,
    Revocation revocation,
  ) async {
    if (revocation.listId != listId) return null;
    final signer = await _signerOf(
      records,
      revocation.by,
      revocation.byRecord,
      revocation._verify,
    );
    if (signer == null) return null;
    return _Signed(revocation, signer, encodeBase64Url(revocation.signature));
  }

  // Por (ficha de quien avala, ficha avalada): el mismo móvil puede avalar
  // la misma ficha desde dos fichas suyas, y cuentan distinto (hallazgo 5).
  static String _vouchKey(_Signed<Vouch> v) =>
      '${v.value.byRecord}\u0001${v.value.recordDigest}';

  static String _revocationKey(_Signed<Revocation> r) =>
      '${r.signer}\u0001${r.value.deviceId}';

  // Dos firmas distintas de lo mismo y del mismo firmante: se queda la menor,
  // para que todos acaben igual.
  static void _put<T>(
    Map<String, _Signed<T>> into,
    String key,
    _Signed<T> value,
  ) {
    final current = into[key];
    if (current == null || value.signature.compareTo(current.signature) < 0) {
      into[key] = value;
    }
  }

  // ----------------------------------------------------------- añadir

  /// El registro con [record]. Lanza [RegistryException] si la firma no
  /// vale, es de otra lista o no cabe.
  Future<DeviceRegistry> withRecord(
    DeviceRecord record, {
    RegistryAnchor? anchor,
  }) => withDeclarations(records: [record], anchor: anchor);

  /// El registro con [vouch]. Lanza [RegistryException] si no se puede
  /// verificar contra una ficha de quien avala que ya esté en el registro,
  /// si la ficha avalada no está o si no cabe.
  Future<DeviceRegistry> withVouch(Vouch vouch, {RegistryAnchor? anchor}) =>
      withDeclarations(vouches: [vouch], anchor: anchor);

  /// El registro con [revocation]. Lanza [RegistryException] si no se puede
  /// verificar contra una ficha de quien revoca o si no cabe.
  Future<DeviceRegistry> withRevocation(
    Revocation revocation, {
    RegistryAnchor? anchor,
  }) => withDeclarations(revocations: [revocation], anchor: anchor);

  /// El registro con todas esas declaraciones a la vez (una ficha y su aval
  /// se comprueban juntos). Cada una tiene que verificarse y caber; si no,
  /// lanza [RegistryException] y no cambia nada. Con [anchor], para hacer
  /// sitio se desaloja antes la basura (lo no enlazado con él).
  Future<DeviceRegistry> withDeclarations({
    Iterable<DeviceRecord> records = const <DeviceRecord>[],
    Iterable<Vouch> vouches = const <Vouch>[],
    Iterable<Revocation> revocations = const <Revocation>[],
    RegistryAnchor? anchor,
  }) async {
    final recs = <String, DeviceRecord>{..._records};
    for (final record in records) {
      if (recs.containsKey(record.digest)) continue;
      if (record.listId != listId || !await record.verify()) {
        throw const RegistryException('ficha no válida');
      }
      recs[record.digest] = record;
    }
    final vs = <String, _Signed<Vouch>>{..._vouches};
    final wantedVouches = <String>[];
    for (final vouch in vouches) {
      final signed = await _checkVouch(recs, listId, vouch);
      if (signed == null) throw const RegistryException('aval no válido');
      final key = _vouchKey(signed);
      wantedVouches.add(key);
      _put(vs, key, signed);
    }
    final revs = <String, _Signed<Revocation>>{..._revocations};
    final wantedRevocations = <String>[];
    for (final revocation in revocations) {
      final signed = await _checkRevocation(recs, listId, revocation);
      if (signed == null) {
        throw const RegistryException('revocación no válida');
      }
      final key = _revocationKey(signed);
      wantedRevocations.add(key);
      _put(revs, key, signed);
    }
    final out = _fit(listId, recs, vs, revs, anchor: anchor, existing: this);
    if (records.any((r) => !out._records.containsKey(r.digest)) ||
        wantedVouches.any((k) => !out._vouches.containsKey(k)) ||
        wantedRevocations.any((k) => !out._revocations.containsKey(k))) {
      throw const RegistryException('el registro está lleno');
    }
    return out;
  }

  /// La unión con [other] (que, como todo registro, ya está verificado). Lo
  /// que no quepa se descarta sin error, empezando por lo que no está
  /// enlazado con [anchor]. Solo lanza [RegistryException] si es de otra lista.
  Future<DeviceRegistry> merge(
    DeviceRegistry other, {
    RegistryAnchor? anchor,
  }) async {
    if (other.listId != listId) {
      throw const RegistryException('registro de otra lista');
    }
    final vs = <String, _Signed<Vouch>>{..._vouches};
    other._vouches.forEach((k, v) => _put(vs, k, v));
    final revs = <String, _Signed<Revocation>>{..._revocations};
    other._revocations.forEach((k, v) => _put(revs, k, v));
    return _fit(
      listId,
      {..._records, ...other._records},
      vs,
      revs,
      anchor: anchor,
      existing: this,
      conflicts: {..._typeConflicts, ...other._typeConflicts},
    );
  }

  /// Los nodos a los que llega una cadena de avales desde [start], con
  /// [start]. Un nodo cuyo id está en [stop] se alcanza, pero lo que avala no
  /// se sigue (segunda revisión de la fase 2a, N1: lo que cuelga de un
  /// revocado no está enlazado). Sin [stop] no mira revocaciones.
  static Set<String> _linkedNodes(
    String start,
    Map<String, DeviceRecord> records,
    Map<String, _Signed<Vouch>> vouches, {
    Set<String> stop = const <String>{},
    Set<String> conflicts = const <String>{},
  }) {
    if (_mixedKinds(records, start, conflicts)) return <String>{};
    final bySigner = <String, List<String>>{};
    for (final v in vouches.values) {
      if (!_mayDeclare(records, v.value.byRecord, conflicts)) continue;
      final target = records[v.value.recordDigest];
      if (target == null) continue;
      (bySigner[v.signer] ??= <String>[]).add(_recordNode(target));
    }
    final linked = <String>{start};
    final queue = <String>[start];
    while (queue.isNotEmpty) {
      final node = queue.removeLast();
      if (node != start && stop.contains(_idOfNode(node))) continue;
      for (final next in bySigner[node] ?? const <String>[]) {
        if (linked.add(next)) queue.add(next);
      }
    }
    return linked;
  }

  /// Los móviles revocados para quien ve [everLinked] (los nodos que alguna
  /// vez fueron de la familia, sin mirar revocaciones): los que revoca
  /// cualquiera de ellos, si también lo fueron. Sin [except] (el que mira,
  /// que no acepta su propia revocación para decidir en quién confía).
  static Set<String> _revokedIn(
    Set<String> everLinked,
    Map<String, _Signed<Revocation>> revocations, {
    required String except,
  }) {
    final ids = {for (final n in everLinked) _idOfNode(n)};
    return {
      for (final r in revocations.values)
        if (everLinked.contains(r.signer) &&
            ids.contains(r.value.deviceId) &&
            r.value.deviceId != except)
          r.value.deviceId,
    };
  }

  /// Ajusta el registro a los cupos y topes. El orden de preferencia es: lo
  /// enlazado con [anchor] antes que lo que no; dentro de eso, lo que ya
  /// estaba en [existing] antes que lo nuevo; y en empate, por clave. Sin
  /// ancla nada está enlazado, así que lo nuevo es lo que no entra.
  ///
  /// «Enlazado» no pasa por un revocado (N1): su ficha y los avales que
  /// llegan a él se conservan (hacen falta para que su revocación cuente),
  /// pero lo que avala él, y lo que solo cuelga de eso, va con la basura,
  /// aunque lo avalara antes de que lo revocaran.
  static DeviceRegistry _fit(
    String listId,
    Map<String, DeviceRecord> records,
    Map<String, _Signed<Vouch>> vouches,
    Map<String, _Signed<Revocation>> revocations, {
    required RegistryAnchor? anchor,
    required DeviceRegistry existing,
    Set<String> conflicts = const <String>{},
  }) {
    conflicts = {...existing._typeConflicts, ...conflicts};
    // W1 y tipo inmutable: tampoco declaraciones que entraron antes de
    // recibir una ficha histórica incompatible pueden contar o proteger
    // nada del desalojo. La ficha web sí se conserva y puede ser avalada.
    vouches = {
      for (final e in vouches.entries)
        if (_mayDeclare(records, e.value.value.byRecord, conflicts))
          e.key: e.value,
    };
    revocations = {
      for (final e in revocations.entries)
        if (_mayDeclare(records, e.value.value.byRecord, conflicts))
          e.key: e.value,
    };
    // Qué revocaciones cuentan se decide sin mirar revocaciones; qué está
    // enlazado, sin pasar por los revocados.
    final revoked = anchor == null
        ? const <String>{}
        : _revokedIn(
            _linkedNodes(anchor._node, records, vouches, conflicts: conflicts),
            revocations,
            except: anchor.deviceId,
          );
    final linked = anchor == null
        ? const <String>{}
        : _linkedNodes(
            anchor._node,
            records,
            vouches,
            stop: revoked,
            conflicts: conflicts,
          );
    // El ancla es una identidad fijada localmente incluso cuando su propio
    // conflicto impide iniciar la cadena. Retener su prueba no da autoridad.
    final retainedLinked = {...linked, if (anchor != null) anchor._node};
    conflicts.addAll(
      retainedLinked.where((node) => _mixedKinds(records, node)),
    );
    bool trusted(String node) =>
        linked.contains(node) && !revoked.contains(_idOfNode(node));
    List<String> ordered(Iterable<String> keys, int Function(String) rank) =>
        keys.toList()..sort((a, b) {
          final byRank = rank(a).compareTo(rank(b));
          return byRank != 0 ? byRank : a.compareTo(b);
        });

    // Primero N1, después reservas: una identidad no enlazada se admite o
    // desaloja entera. Nunca gana sitio por haber autofirmado ambos tipos.
    int recordRank(String digest) =>
        (retainedLinked.contains(_recordNode(records[digest]!)) ? 0 : 2) +
        (existing._records.containsKey(digest) ? 0 : 1);
    final recordOrder = ordered(records.keys, recordRank);
    final keptRecords = <String, DeviceRecord>{};
    final perId = <String, int>{};
    final requiredVouches = <String>{};

    // Una ruta por nodo enlazado según N1 (llega al revocado, pero no sigue
    // lo que avala él), para conservar la evidencia de revocaciones y
    // testigos. Lo que solo cuelga de un revocado no tiene ruta: ni una
    // revocación emitida por esa rama ni una dirigida a ella reserva nada.
    Map<String, List<String>> proofPaths() {
      final paths = <String, List<String>>{};
      if (anchor == null) return paths;
      paths[anchor._node] = [];
      final queue = <String>[anchor._node];
      final edges = ordered(vouches.keys, (_) => 0);
      for (var i = 0; i < queue.length; i++) {
        final node = queue[i];
        if (node != anchor._node && revoked.contains(_idOfNode(node))) {
          continue;
        }
        for (final key in edges) {
          final v = vouches[key]!;
          if (v.signer != node) continue;
          final target = _recordNode(records[v.value.recordDigest]!);
          if (paths.containsKey(target)) continue;
          paths[target] = [...paths[node]!, key];
          queue.add(target);
        }
      }
      return paths;
    }

    final livePaths = proofPaths();
    Set<String> pathRecords(Iterable<String> keys) => {
      for (final key in keys) ...{
        vouches[key]!.value.byRecord,
        vouches[key]!.value.recordDigest,
      },
    };
    bool reserve(Set<String> digests, [Set<String> proof = const {}]) {
      final all = {...digests, ...pathRecords(proof)};
      if ({...keptRecords.keys, ...all}.length > kMaxRegistryRecords) {
        return false;
      }
      for (final digest in all) {
        keptRecords[digest] = records[digest]!;
      }
      requiredVouches.addAll(proof);
      return true;
    }

    // La ficha auténtica del ancla va antes que cualquier otra reserva.
    if (anchor != null) {
      final own = recordOrder.where(
        (d) => _recordNode(records[d]!) == anchor._node,
      );
      if (own.isNotEmpty) {
        final latest = own.reduce(
          (a, b) => records[a]!.seq >= records[b]!.seq ? a : b,
        );
        reserve({latest});
      }
    }
    final evidenceTargets = <String>{};
    for (final key in ordered(
      revocations.keys,
      (k) => trusted(revocations[k]!.signer) ? 0 : 1,
    )) {
      final r = revocations[key]!;
      final targets = livePaths.keys.where(
        (n) => _idOfNode(n) == r.value.deviceId,
      );
      if (!livePaths.containsKey(r.signer) ||
          targets.isEmpty ||
          evidenceTargets.contains(r.value.deviceId)) {
        continue;
      }
      final proof = {...livePaths[r.signer]!, ...livePaths[targets.first]!};
      if (reserve({r.value.byRecord}, proof)) {
        evidenceTargets.add(r.value.deviceId);
      }
    }

    final witnesses = <String, Map<DeviceKind, String>>{};
    for (final digest in recordOrder) {
      final record = records[digest]!;
      final node = _recordNode(record);
      if (!retainedLinked.contains(node)) continue;
      final kinds = witnesses[node] ??= <DeviceKind, String>{};
      final previous = kinds[record.kind];
      if (previous == null || record.seq > records[previous]!.seq) {
        kinds[record.kind] = digest;
      }
    }
    // Fuera del cupo ordinario por id. Primero una ficha (la más reciente)
    // de cada identidad enlazada con marca o con tipos mezclados, con su ruta
    // viva: así conserva fichas y su marca nunca se poda (abajo). Después el
    // segundo testigo de las que mezclan tipos. Si el tope global no deja
    // guardar ambos, la marca impide resolver la identidad al reintroducirla.
    final conflicted = witnesses.entries
        .where((e) => conflicts.contains(e.key) || e.value.length > 1)
        .toList();
    for (final entry in conflicted) {
      final latest = entry.value.values.reduce((a, b) {
        final bySeq = records[a]!.seq.compareTo(records[b]!.seq);
        return bySeq > 0 || (bySeq == 0 && a.compareTo(b) > 0) ? a : b;
      });
      reserve({latest}, {...?livePaths[entry.key]});
    }
    for (final entry in conflicted.where((e) => e.value.length > 1)) {
      reserve(entry.value.values.toSet(), {...?livePaths[entry.key]});
    }
    // Las demás fichas enlazadas tienen su cupo ordinario de 16 por id.
    for (final digest in recordOrder) {
      if (keptRecords.length >= kMaxRegistryRecords) break;
      if (keptRecords.containsKey(digest)) continue;
      final record = records[digest]!;
      if (!retainedLinked.contains(_recordNode(record))) continue;
      final count = perId[record.deviceId] ?? 0;
      if (count >= kMaxRecordsPerDevice) continue;
      perId[record.deviceId] = count + 1;
      keptRecords[digest] = record;
    }
    // Las reservas también ocupan espacio frente a la basura del mismo id.
    final totalPerId = <String, int>{};
    for (final r in keptRecords.values) {
      totalPerId[r.deviceId] = (totalPerId[r.deviceId] ?? 0) + 1;
    }
    final unlinked = <String, List<String>>{};
    for (final digest in recordOrder) {
      final node = _recordNode(records[digest]!);
      if (!retainedLinked.contains(node) && !keptRecords.containsKey(digest)) {
        (unlinked[node] ??= []).add(digest);
      }
    }
    for (final group in unlinked.values) {
      final id = records[group.first]!.deviceId;
      if (keptRecords.length + group.length > kMaxRegistryRecords ||
          (totalPerId[id] ?? 0) + group.length > kMaxRecordsPerDevice) {
        continue;
      }
      for (final digest in group) {
        keptRecords[digest] = records[digest]!;
      }
      totalPerId[id] = (totalPerId[id] ?? 0) + group.length;
    }

    // Avales: solo de fichas que siguen; cupo por firmante y tope global.
    // Lo que avala un revocado va con la basura.
    int vouchRank(String key) =>
        (requiredVouches.contains(key)
            ? -2
            : trusted(vouches[key]!.signer)
            ? 0
            : 2) +
        (existing._vouches.containsKey(key) ? 0 : 1);
    final keptVouches = <String, _Signed<Vouch>>{};
    final perVoucher = <String, int>{};
    for (final key in ordered(
      vouches.keys.where(
        (k) =>
            keptRecords.containsKey(vouches[k]!.value.recordDigest) &&
            keptRecords.containsKey(vouches[k]!.value.byRecord),
      ),
      vouchRank,
    )) {
      if (keptVouches.length >= kMaxRegistryVouches) break;
      final signer = vouches[key]!.signer;
      final count = perVoucher[signer] ?? 0;
      if (count >= kMaxVouchesPerSigner) continue;
      perVoucher[signer] = count + 1;
      keptVouches[key] = vouches[key]!;
    }

    // Revocaciones. Cuentan las de un firmante que alguna vez fue de la
    // familia a un móvil que también lo fue, con lo que queda después de
    // ajustar fichas y avales (lo mismo que verá [viewFor]). De las que
    // revocan a un mismo móvil basta una (la «primera»): va antes que nada y
    // no gasta el cupo de su firmante (4b), así que una revocación que cuenta
    // siempre cabe: hay como mucho una por id y no hay más ids que fichas.
    // Después, las demás que cuentan; la basura, al final.
    final everLinked = anchor == null
        ? const <String>{}
        : _linkedNodes(
            anchor._node,
            keptRecords,
            keptVouches,
            conflicts: conflicts,
          );
    final everIds = {for (final n in everLinked) _idOfNode(n)};
    final candidates = revocations.keys
        .where((k) => keptRecords.containsKey(revocations[k]!.value.byRecord))
        .toList();
    bool counts(String key) =>
        everLinked.contains(revocations[key]!.signer) &&
        everIds.contains(revocations[key]!.value.deviceId);
    int fresh(String key) => existing._revocations.containsKey(key) ? 0 : 1;
    int byTrusted(String key) => trusted(revocations[key]!.signer) ? 0 : 1;
    final firstForTarget = <String, String>{};
    for (final key in ordered(
      candidates.where(counts),
      (k) => byTrusted(k) * 2 + fresh(k),
    )) {
      firstForTarget.putIfAbsent(revocations[key]!.value.deviceId, () => key);
    }
    final firsts = firstForTarget.values.toSet();
    int revocationRank(String key) {
      if (firsts.contains(key)) return 0;
      if (!counts(key)) return 6 + fresh(key);
      return 2 + byTrusted(key) * 2 + fresh(key);
    }

    final keptRevocations = <String, _Signed<Revocation>>{};
    final perRevoker = <String, int>{};
    for (final key in ordered(candidates, revocationRank)) {
      if (keptRevocations.length >= kMaxRegistryRevocations) break;
      if (firsts.contains(key)) {
        keptRevocations[key] = revocations[key]!;
        continue;
      }
      final signer = revocations[key]!.signer;
      final count = perRevoker[signer] ?? 0;
      if (count >= kMaxRevocationsPerSigner) continue;
      perRevoker[signer] = count + 1;
      keptRevocations[key] = revocations[key]!;
    }
    // Marcas locales, con cota: como mucho una por identidad y 64 en total.
    // Se podan las de identidades que ni están enlazadas ni conservan fichas.
    // Orden: enlazadas con fichas (nunca más de 64, así que una identidad
    // enlazada en conflicto nunca se rehabilita), el ancla sin fichas, otras
    // enlazadas sin fichas y, al final, las que solo conservan fichas.
    final keptNodes = {for (final r in keptRecords.values) _recordNode(r)};
    int markRank(String node) {
      final isLinked = retainedLinked.contains(node);
      final hasRecords = keptNodes.contains(node);
      final group = isLinked && hasRecords
          ? 0
          : anchor != null && node == anchor._node
          ? 1
          : isLinked
          ? 2
          : 3;
      return group * 2 + (existing._typeConflicts.contains(node) ? 0 : 1);
    }

    final marks = ordered(
      conflicts.where(
        (n) => retainedLinked.contains(n) || keptNodes.contains(n),
      ),
      markRank,
    ).take(kMaxRegistryRecords).toSet();
    return DeviceRegistry._(
      listId,
      Map.unmodifiable(keptRecords),
      Map.unmodifiable(keptVouches),
      Map.unmodifiable(keptRevocations),
      Set.unmodifiable(marks),
    );
  }

  /// Si tiene las mismas declaraciones y memoria local de tipos que [other].
  bool sameAs(DeviceRegistry other) =>
      listId == other.listId &&
      _sameKeys(_records, other._records) &&
      _sameKeys(_vouches, other._vouches) &&
      _sameKeys(_revocations, other._revocations) &&
      _typeConflicts.length == other._typeConflicts.length &&
      _typeConflicts.containsAll(other._typeConflicts);

  static bool _sameKeys(Map<String, Object> a, Map<String, Object> b) =>
      a.length == b.length && a.keys.every(b.containsKey);

  /// El registro en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'v': kRegistryVersion,
    'l': listId,
    'records': [for (final r in records) r.toJson()],
    'vouches': [for (final v in vouches) v.toJson()],
    'revocations': [for (final r in revocations) r.toJson()],
  };

  /// Solo para el almacén local autenticado. Las marcas sobreviven incluso
  /// si el tope global obliga a perder testigos. No son declaraciones
  /// firmadas y nunca se publican ni se aceptan desde el JSON compartido.
  Map<String, Object?> toLocalStoreJson() => {
    ...toJson(),
    'localTypeConflicts': _typeConflicts.toList()..sort(),
  };

  /// Lee exclusivamente [toLocalStoreJson] del almacén local autenticado.
  /// También acepta registros antiguos, que no llevaban marcas.
  static Future<DeviceRegistry> fromLocalStoreJson(
    Object? json, {
    RegistryAnchor? anchor,
  }) async {
    final conflicts = <String>{};
    if (json is Map && json.containsKey('localTypeConflicts')) {
      final nodes = json['localTypeConflicts'];
      if (nodes is! List) {
        throw const RegistryException('registro local no válido');
      }
      for (final node in nodes) {
        if (node is! String) {
          throw const RegistryException('conflicto no válido');
        }
        final parts = node.split('\u0000');
        if (parts.length != 2) {
          throw const RegistryException('conflicto no válido');
        }
        conflicts.add(_nodeOf(_idOf(parts[0]), _bytesOf(parts[1], 32)));
      }
    }
    return _readVerified(json, anchor: anchor, conflicts: conflicts);
  }

  /// Lee [toJson] comprobando cada declaración: las fichas con su firma, y
  /// los avales y las revocaciones contra una ficha presente; lo que no
  /// verifica o está mal formado se descarta, sin invalidar el resto. Lanza
  /// [RegistryException] si el formato del registro no vale o trae más de lo
  /// que cabe (eso, antes de comprobar ninguna firma).
  static Future<DeviceRegistry> fromJsonVerified(
    Object? json, {
    RegistryAnchor? anchor,
  }) => _readVerified(json, anchor: anchor);

  static Future<DeviceRegistry> _readVerified(
    Object? json, {
    RegistryAnchor? anchor,
    Set<String> conflicts = const <String>{},
  }) async {
    if (json is! Map ||
        json['v'] != kRegistryVersion ||
        json['records'] is! List ||
        json['vouches'] is! List ||
        json['revocations'] is! List) {
      throw const RegistryException('registro no válido');
    }
    final records = json['records'] as List;
    final vouches = json['vouches'] as List;
    final revocations = json['revocations'] as List;
    // Los topes, antes de comprobar ninguna firma.
    if (records.length > kMaxRegistryRecords ||
        vouches.length > kMaxRegistryVouches ||
        revocations.length > kMaxRegistryRevocations) {
      throw const RegistryException('el registro no cabe');
    }
    final empty = DeviceRegistry.empty(_idOf(json['l']));
    final listId = empty.listId;
    // Una entrada rota se salta: no invalida el resto (hallazgo 10).
    T? parsed<T>(T Function() read) {
      try {
        return read();
      } on RegistryException {
        return null;
      }
    }

    final recs = <String, DeviceRecord>{};
    for (final r in records) {
      final record = parsed(() => DeviceRecord.fromJson(r));
      if (record != null && record.listId == listId && await record.verify()) {
        recs[record.digest] = record;
      }
    }
    final vs = <String, _Signed<Vouch>>{};
    for (final v in vouches) {
      final vouch = parsed(() => Vouch.fromJson(v));
      if (vouch == null) continue;
      final signed = await _checkVouch(recs, listId, vouch);
      if (signed != null) _put(vs, _vouchKey(signed), signed);
    }
    final revs = <String, _Signed<Revocation>>{};
    for (final r in revocations) {
      final revocation = parsed(() => Revocation.fromJson(r));
      if (revocation == null) continue;
      final signed = await _checkRevocation(recs, listId, revocation);
      if (signed != null) _put(revs, _revocationKey(signed), signed);
    }
    return _fit(
      listId,
      recs,
      vs,
      revs,
      anchor: anchor,
      existing: empty,
      conflicts: conflicts,
    );
  }

  // ------------------------------------------------------------- leer

  /// Lee el registro desde el punto de vista del móvil [me], cuya clave de
  /// firma es [mySigningKey] (la suya de verdad, no la que diga el registro).
  /// [livePeople] son las personas que existen en el documento común.
  ///
  /// No comprueba firmas: todo lo que hay en el registro ya se verificó al
  /// entrar (hallazgo 9). Lanza [RegistryException] si el registro no tiene
  /// la ficha de [me] o su identidad mezcla tipos de dispositivo.
  /// [me] y [mySigningKey] también pueden ser los de una raíz móvil pública
  /// fijada por la web: no necesitan pertenecer al dispositivo local (W2).
  Future<RegistryView> viewFor({
    required String me,
    required List<int> mySigningKey,
    required Set<String> livePeople,
  }) async {
    final mine = _current(me, mySigningKey);
    if (mine == null) {
      if (_mixedKinds(_records, _nodeOf(me, mySigningKey), _typeConflicts)) {
        throw const RegistryIdentityAmbiguousException();
      }
      throw const RegistryException('este móvil no está en el registro');
    }
    final myNode = _recordNode(mine);
    final keyOf = <String, List<int>>{
      for (final r in _records.values) _recordNode(r): r.keys.signing,
    };
    // 1. Alguna vez de la familia (sin mirar revocaciones): solo sirve para
    // decidir qué revocaciones cuentan (revocar gana).
    final everLinked = _linkedNodes(
      myNode,
      _records,
      _vouches,
      conflicts: _typeConflicts,
    );
    // 2. Revocaciones de cualquiera que alguna vez fue de la familia a un
    // móvil que también lo fue. La mía no cambia en quién confío.
    final revokedIds = _revokedIn(everLinked, _revocations, except: me);
    final selfRevoked = _revocations.values.any(
      (r) => everLinked.contains(r.signer) && r.value.deviceId == me,
    );
    // 3. De la familia ahora: la cadena de avales desde mí no pasa por un
    // revocado (segunda revisión, N1). Al revocado se llega (es él), pero lo
    // que cuelga de él no cuenta para pendientes, época ni ambigüedad, ni
    // ocupa sitio en el registro: un ladrón revocado no puede añadir nada.
    final linked = _linkedNodes(
      myNode,
      _records,
      _vouches,
      stop: revokedIds,
      conflicts: _typeConflicts,
    );
    bool trusted(String node) =>
        linked.contains(node) && !revokedIds.contains(_idOfNode(node));
    // Resumen avalado -> fichas de quien lo avaló (cuando avaló), solo de
    // avalistas de la familia que no están revocados.
    final vouched = <String, Set<String>>{};
    for (final v in _vouches.values) {
      if (!trusted(v.signer)) continue;
      (vouched[v.value.recordDigest] ??= <String>{}).add(v.value.byRecord);
    }
    // 4. Un id con dos claves distintas no se resuelve; tampoco uno con dos
    // fichas distintas del mismo `seq` más alto (N6): no se sabe cuál vale.
    final keysById = <String, Set<String>>{};
    for (final node in linked) {
      (keysById[_idOfNode(node)] ??= <String>{}).add(node);
    }
    final ambiguous = {
      for (final e in keysById.entries)
        if (e.value.any(
              (node) => _mixedKinds(_records, node, _typeConflicts),
            ) ||
            e.value.length > 1 ||
            _tiedTop(e.key, keyOf[e.value.single]!))
          e.key,
    };
    // Mi id con otras claves (alguien de la familia ha avalado una ficha que
    // se hace pasar por mí), o dos fichas mías del mismo `seq`: no cambia
    // quién soy yo, pero se avisa igual que si me hubieran revocado
    // (hallazgo 8).
    final myIdTaken = ambiguous.remove(me);
    // Revocados que cuentan para la época: los de la familia de ahora (o el
    // propio revocado, que es a donde se llega) y los que revoca alguien de
    // la familia de ahora. Lo que un revocado revoque entre lo suyo, no.
    final revoked = {
      for (final id in revokedIds)
        if (keysById.containsKey(id)) id,
      for (final r in _revocations.values)
        if (trusted(r.signer) && revokedIds.contains(r.value.deviceId))
          r.value.deviceId,
    };
    // 5. Activos: ficha actual avalada por otro activo; yo soy el ancla.
    final current = <String, DeviceRecord>{me: mine};
    for (final id in keysById.keys) {
      if (id == me || ambiguous.contains(id) || revokedIds.contains(id)) {
        continue;
      }
      current[id] = _current(id, keyOf[keysById[id]!.single]!)!;
    }
    // [cleanFor]: para las sorpresas de esa persona, un aval solo cuenta si
    // quien avaló no era de ella ni estaba sin persona cuando avaló
    // (hallazgo 5): si no, un móvil de Nora que luego pasa a ser «de Leo» y
    // lo aprueban arrastraría los avales que dio siendo de Nora.
    bool vouchedBy(Set<String> out, DeviceRecord record, String? cleanFor) =>
        (vouched[record.digest] ?? const <String>{}).any((digest) {
          final then = _records[digest]!;
          final voucher = then.deviceId;
          return voucher != record.deviceId &&
              out.contains(voucher) &&
              _recordNode(then) == _recordNode(current[voucher]!) &&
              (cleanFor == null ||
                  (then.personId != null && then.personId != cleanFor));
        });
    Set<String> closure(
      bool Function(DeviceRecord record) allowed, {
      String? cleanFor,
    }) {
      final out = <String>{me};
      var more = true;
      while (more) {
        more = false;
        for (final record in current.values) {
          if (out.contains(record.deviceId) || !allowed(record)) continue;
          if (vouchedBy(out, record, cleanFor)) {
            out.add(record.deviceId);
            more = true;
          }
        }
      }
      return out;
    }

    final active = closure((_) => true);
    // 6. Época: 1 + revocados + ambiguos + cambios de ficha, de la familia
    // de ahora (N1).
    var epoch = 1 + revoked.length + ambiguous.length;
    for (final nodes in keysById.values) {
      var seq = 1;
      for (final node in nodes) {
        final top = _latest(_idOfNode(node), keyOf[node]!)!.seq;
        if (top > seq) seq = top;
      }
      epoch += seq - 1;
    }
    // 7. Los que solo cuelgan de un revocado y han avalado mi ficha actual:
    // me han confirmado ellos a mí (por ejemplo, el que revocó al que nos
    // unía). No cuentan para nada; la interfaz pide confirmarlos de vuelta.
    final detached = <String, DeviceRecord>{};
    final everById = <String, Set<String>>{};
    for (final node in everLinked) {
      (everById[_idOfNode(node)] ??= <String>{}).add(node);
    }
    for (final v in _vouches.values) {
      final id = _idOfNode(v.signer);
      if (v.value.recordDigest != mine.digest ||
          id == me ||
          linked.contains(v.signer) ||
          !everLinked.contains(v.signer) ||
          revokedIds.contains(id) ||
          _mixedKinds(_records, v.signer, _typeConflicts) ||
          everById[id]!.length > 1 ||
          _tiedTop(id, keyOf[v.signer]!)) {
        continue;
      }
      final record = _current(id, keyOf[v.signer]!)!;
      if (v.value.byRecord == record.digest) {
        detached[id] = record;
      }
    }
    bool personOk(String? person) =>
        person != null &&
        kSyncIdPattern.hasMatch(person) &&
        livePeople.contains(person);
    // Las revocaciones firmadas, aparte de los ids solo ambiguos (B6, M1).
    final explicitlyRevoked = Set<String>.unmodifiable(revoked);
    // Webs propias (1.0.6, ADR 0009): activas, de la persona de este móvil y
    // cuya ficha actual avaló este móvil siendo ya de esa persona. Solo las
    // evalúa este móvil, con sus propios avales.
    final ownWebs = <String>{
      if (mine.kind == DeviceKind.mobile && personOk(mine.personId))
        for (final id in active)
          if (current[id]!.kind == DeviceKind.web &&
              current[id]!.personId == mine.personId &&
              (vouched[current[id]!.digest] ?? const <String>{}).any((digest) {
                final then = _records[digest]!;
                return then.deviceId == me &&
                    _recordNode(then) == myNode &&
                    then.personId == mine.personId;
              }))
            id,
    };
    return RegistryView._(
      registry: this,
      listId: listId,
      me: me,
      epoch: epoch,
      revokedByOthers: selfRevoked || myIdTaken,
      selfRevoked: selfRevoked,
      explicitlyRevoked: explicitlyRevoked,
      ownWebIds: Set.unmodifiable(ownWebs),
      revoked: Set.unmodifiable({...explicitlyRevoked, ...ambiguous}),
      everMembers: Set.unmodifiable(everById.keys),
      active: {for (final id in active) id: KnownDevice._(current[id]!)},
      pending: {
        for (final record in current.values)
          if (!active.contains(record.deviceId))
            record.deviceId: KnownDevice._(record),
      },
      detached: {
        for (final e in detached.entries) e.key: KnownDevice._(e.value),
      },
      livePeople: Set.unmodifiable(livePeople),
      personOk: personOk,
      // La primera ficha (la del emparejamiento) vale sin más; una posterior
      // (cambio de persona), solo cuando la avala un móvil que ahora es
      // activo (N7): ni un revocado ni un pendiente aprueban a nadie. Si se
      // revoca después al único que la avaló, este móvil vuelve a esperar
      // aprobación (la interfaz debe avisar antes de revocarlo).
      selfApproved:
          mine.seq == 1 ||
          (vouched[mine.digest] ?? const <String>{}).any((digest) {
            final then = _records[digest]!;
            return then.deviceId != me &&
                active.contains(then.deviceId) &&
                _recordNode(then) == _recordNode(current[then.deviceId]!);
          }),
      // La clave de firma de cada id enlazado desde este móvil sin
      // ambigüedad (también los revocados, a los que se llega): con ella se
      // reconoce al creador de una clave común (ADR 0005, B1, R1).
      linkedSigningKeys: Map.unmodifiable(<String, Uint8List>{
        for (final e in keysById.entries)
          if (e.key != me && !ambiguous.contains(e.key) && e.value.length == 1)
            e.key: Uint8List.fromList(keyOf[e.value.single]!),
        me: Uint8List.fromList(mine.keys.signing),
      }),
      cleanFor: (personId) => closure(
        (record) =>
            record.kind == DeviceKind.mobile &&
            active.contains(record.deviceId) &&
            personOk(record.personId) &&
            record.personId != personId,
        cleanFor: personId,
      ),
    );
  }

  /// Si [deviceId], con la clave [signingKey], tiene dos fichas distintas
  /// del mismo `seq` más alto (N6).
  bool _tiedTop(String deviceId, List<int> signingKey) {
    final top = _current(deviceId, signingKey);
    if (top == null) return false;
    return _records.values.any(
      (r) =>
          r.deviceId == deviceId &&
          r.seq == top.seq &&
          r.digest != top.digest &&
          constantTimeEquals(r.keys.signing, signingKey),
    );
  }
}

/// El registro leído desde un móvil: quién es de la familia y quién tiene
/// derecho a qué.
class RegistryView {
  RegistryView._({
    required this.registry,
    required this.listId,
    required this.me,
    required this.epoch,
    required this.revokedByOthers,
    required this.selfRevoked,
    required this.explicitlyRevoked,
    required this._ownWebIds,
    required this.revoked,
    required this.everMembers,
    required this._active,
    required this._pending,
    required this._detached,
    required this.livePeople,
    required this._personOk,
    required this.selfApproved,
    required this._cleanFor,
    required this._linkedSigningKeys,
  });

  final Set<String> _ownWebIds;

  /// Las webs de la persona de este móvil (1.0.6, ADR 0009): activas, con la
  /// misma persona que este móvil y cuya ficha actual avaló este móvil siendo
  /// ya de esa persona (la emparejó o la reconfirmó). Este móvil les entrega
  /// las claves de las sorpresas de los demás y recoge lo que escriben en su
  /// buzón. Vacía si este móvil no tiene la ficha aprobada o lo han revocado.
  /// No cambia [entitled], [relayable] ni nada de las sorpresas: una web
  /// nunca es escritora ni destinataria en esos predicados.
  List<KnownDevice> ownWebs() => [
    if (selfApproved && !revokedByOthers && self.kind == DeviceKind.mobile)
      for (final id in _ownWebIds.toList()..sort()) _active[id]!,
  ];

  /// The verified snapshot this view was built from.
  final DeviceRegistry registry;

  /// Lista.
  final String listId;

  /// Este móvil.
  final String me;

  /// Época del registro: 1 + revocados + cambios de ficha, de la familia de
  /// ahora (lo que solo cuelga de un revocado no la sube; N1).
  final int epoch;

  /// Si algún móvil de la familia ha revocado a este. No cambia en quién
  /// confía este móvil, pero la aplicación debe avisar y dejar de publicar.
  final bool revokedByOthers;

  /// A verified family revocation of this device, excluding an ambiguous id.
  final bool selfRevoked;

  /// Móviles revocados (o con dos claves, o dos fichas del mismo `seq`, para
  /// el mismo id) de la familia de ahora, o revocados por alguien de ella.
  final Set<String> revoked;

  /// Solo los de [revoked] con una revocación firmada, sin los que solo son
  /// ambiguos (ADR 0005, B6, M1 de la revisión de seguridad): un revocado que después se hace
  /// ambiguo (otra ficha con su clave) sigue aquí. Una revocación no se
  /// deshace.
  final Set<String> explicitlyRevoked;

  /// Móviles enlazados alguna vez por avales firmados, incluidos huérfanos.
  /// Su ausencia actual no autoriza revocar su credencial del servicio.
  final Set<String> everMembers;

  /// Personas que existen.
  final Set<String> livePeople;

  final Map<String, KnownDevice> _active;
  final Map<String, KnownDevice> _pending;
  final Map<String, KnownDevice> _detached;
  final bool Function(String?) _personOk;

  /// Si la ficha actual de este móvil cuenta para él mismo: es la primera,
  /// o es una posterior (cambió de persona) que avala un móvil activo (N7).
  final bool selfApproved;
  final Set<String> Function(String) _cleanFor;
  final Map<String, Uint8List> _linkedSigningKeys;

  /// La clave de firma con la que [deviceId] está enlazado desde este móvil
  /// (activo, pendiente o revocado al que se llega por avales), o null si no
  /// está enlazado o su id es ambiguo (dos claves, dos fichas del mismo
  /// `seq`, tipos mezclados). No dice nada de permisos: sirve para
  /// reconocer a quién pertenece una firma (ADR 0005, B1, R1).
  Uint8List? linkedSigningKey(String deviceId) {
    final key = _linkedSigningKeys[deviceId];
    return key == null ? null : Uint8List.fromList(key);
  }

  final Map<String, Set<String>> _entitled = {};

  /// La persona de este móvil según su ficha, o null.
  String? get myPerson => _active[me]!.personId;

  /// La ficha de este móvil.
  KnownDevice get self => _active[me]!;

  /// Este móvil como ancla del registro (para añadir y fusionar).
  RegistryAnchor get anchor =>
      RegistryAnchor(deviceId: me, signingKey: self.signingKey);

  /// Los móviles activos de la familia (también este), por id.
  List<String> get members => _active.keys.toList()..sort();

  /// Móviles de la familia cuya ficha actual aún no ha avalado un activo
  /// (recién llegados o que han cambiado de persona): esperan aprobación.
  /// Lo que solo cuelga de un revocado no está (N1).
  List<KnownDevice> get pending => [
    for (final id in _pending.keys.toList()..sort()) _pending[id]!,
  ];

  /// Móviles que solo cuelgan de uno revocado y que han avalado la ficha
  /// actual de este: por ejemplo, el que revocó al único que los unía y ha
  /// confirmado a este como huérfano. No cuentan para nada (ni son de la
  /// familia, ni pendientes, ni suben la época); la interfaz pide
  /// confirmarlos de vuelta, uno a uno ([approveDevice]), o revocarlos.
  List<KnownDevice> get detached => [
    for (final id in _detached.keys.toList()..sort()) _detached[id]!,
  ];

  /// «Emparejado»: hay algún otro móvil activo en la familia.
  bool get paired => _active.length > 1;

  /// Las personas que existen y tienen algún dispositivo activo o pendiente
  /// (móvil o web), también la de este. Es la lista de personas cuya
  /// protección se activa sola (1.0.6): en el móvil de cada una no se ve
  /// ningún regalo para ella.
  Set<String> get devicePeople => {
    for (final d in [..._active.values, ..._pending.values])
      if (d.personId case final String person when _validPerson(person)) person,
  };

  // Las fichas de los demás dispositivos, en cualquier estado (también
  // revocados, huérfanos o colgados de un revocado): para la capa de pantalla
  // cuenta haber tenido compañía en esta generación, no solo tenerla ahora.
  Iterable<DeviceRecord> get _otherRecords =>
      registry.records.where((r) => r.deviceId != me);

  /// Si en este registro hay otro dispositivo cuya persona no es [personId]:
  /// entonces este móvil no pinta los regalos para [personId] (capa de
  /// pantalla, 1.0.6). Cuentan todas sus fichas, también las de dispositivos
  /// revocados: quitar a los demás no destapa nada; solo estrenar una
  /// generación sin nadie ([alone]) lo levanta. Con solo dispositivos de
  /// [personId] (dos móviles de la misma persona) no está acompañado.
  bool accompanied(String? personId) =>
      _otherRecords.any((r) => r.personId != personId);

  /// Si en este registro no hay ninguna ficha de otro dispositivo, ni
  /// siquiera revocada: una generación que este móvil acaba de estrenar o un
  /// móvil que nunca se ha conectado a otro.
  bool get alone => _otherRecords.isEmpty;

  /// El móvil activo [deviceId], o null (desconocido, revocado o pendiente).
  KnownDevice? member(String deviceId) => _active[deviceId];

  /// El móvil [deviceId], activo o pendiente, o null (desconocido o
  /// revocado).
  KnownDevice? device(String deviceId) =>
      _active[deviceId] ?? _pending[deviceId];

  bool _validPerson(String personId) =>
      kSyncIdPattern.hasMatch(personId) && livePeople.contains(personId);

  // Este móvil puede tener derecho a las sorpresas de [personId]: su persona
  // existe y no es esa. Solo entonces tiene una cadena limpia desde sí.
  bool _canHoldKey(String personId) =>
      self.kind == DeviceKind.mobile &&
      _personOk(myPerson) &&
      myPerson != personId;

  // Cualquier activo que no sea de [personId]: lo laxo, para guardar y
  // reenviar slots sin abrirlos.
  Set<String> _laxFor(String personId) => {
    for (final d in _active.values)
      if (d.kind == DeviceKind.mobile &&
          d.deviceId != me &&
          _personOk(d.personId) &&
          d.personId != personId)
        d.deviceId,
  };

  Set<String> _entitledFor(String personId) =>
      _entitled.putIfAbsent(personId, () {
        if (self.kind == DeviceKind.web || !_validPerson(personId)) {
          return const <String>{};
        }
        // Con derecho: solo cuentan los que avalo yo o avala alguien con
        // derecho (cadena limpia desde este móvil).
        if (_canHoldKey(personId)) return _cleanFor(personId);
        // El móvil de la persona protegida no tiene cadena limpia (empieza en
        // él), pero lo laxo solo puede engañarle a él: como mucho se cree que
        // la protección está quitada y escribe regalos públicos para sí, que la
        // reconciliación vuelve a ocultar (N2).
        if (myPerson == personId) return _laxFor(personId);
        // Sin persona, o con la persona borrada: no hay cadena limpia y nada
        // autentica la política, así que oculta (hallazgo 3b).
        return const <String>{};
      });

  final Map<String, Set<String>> _relay = {};

  Set<String> _relayFor(String personId) => _relay.putIfAbsent(personId, () {
    if (self.kind == DeviceKind.web || !_validPerson(personId)) {
      return const <String>{};
    }
    if (_canHoldKey(personId)) return _cleanFor(personId);
    return _laxFor(personId);
  });

  /// El único predicado estricto de las sorpresas: el móvil [deviceId] si
  /// puede recibir la clave de las sorpresas de [protectedPersonId], escribir
  /// sus slots y autenticar su política, o null.
  KnownDevice? entitled(String deviceId, String protectedPersonId) =>
      _entitledFor(protectedPersonId).contains(deviceId)
      ? _active[deviceId]
      : null;

  /// El móvil [deviceId] si este móvil debe guardar y reenviar sus slots de
  /// [protectedPersonId], o null. Para quien puede tener la clave es lo
  /// mismo que [entitled]; para el móvil de la persona protegida o uno sin
  /// persona es laxo (cualquier activo que no sea de esa persona), porque no
  /// los abre y no autentican nada (hallazgo 3b).
  KnownDevice? relayable(String deviceId, String protectedPersonId) =>
      _relayFor(protectedPersonId).contains(deviceId)
      ? _active[deviceId]
      : null;

  /// Si este móvil tiene derecho a las sorpresas de [protectedPersonId]: no
  /// lo han revocado, su persona existe y no es esa, y su ficha vale
  /// ([selfApproved]). Cambiar de persona en este móvil no basta: hasta que
  /// otro lo apruebe no crea claves, no abre el bloque ni publica. (Que los
  /// demás le den la clave es otra cosa: eso lo decide cada uno con
  /// [entitled] desde su propio registro.)
  bool selfEntitled(String protectedPersonId) =>
      !revokedByOthers &&
      selfApproved &&
      entitled(me, protectedPersonId) != null;

  /// Los móviles con derecho a las sorpresas de [protectedPersonId],
  /// ordenados (su número es público: uno por slot).
  List<String> entitledDevices(String protectedPersonId) =>
      _entitledFor(protectedPersonId).toList()..sort();
}

enum ProtectionRequestBlock {
  registryUnavailable,
  notMobile,
  recipientUnavailable,
  requesterRevoked,
  requesterAmbiguous,
  requesterPending,
  noConfirmer,
}

/// Returns the reason a request cannot be made, or null if a mobile could
/// confirm it. [localView] must come from this verified [registry] snapshot.
/// Pass an empty [candidateViews] map to share candidate views across the
/// recipients in one evaluation of [localView].
Future<ProtectionRequestBlock?> protectionRequestBlock({
  required DeviceRegistry registry,
  required RegistryView localView,
  required String personId,
  Map<String, Future<RegistryView>>? candidateViews,
}) async {
  if (!identical(localView.registry, registry)) {
    return ProtectionRequestBlock.registryUnavailable;
  }
  if (localView.self.kind != DeviceKind.mobile) {
    return ProtectionRequestBlock.notMobile;
  }
  if (!localView._validPerson(personId)) {
    return ProtectionRequestBlock.recipientUnavailable;
  }
  if (localView.selfRevoked) return ProtectionRequestBlock.requesterRevoked;
  if (localView.revokedByOthers) {
    return ProtectionRequestBlock.requesterAmbiguous;
  }
  if (!localView.selfApproved) return ProtectionRequestBlock.requesterPending;
  if (localView.selfEntitled(personId)) return null;

  final views = candidateViews ?? <String, Future<RegistryView>>{};
  for (final id in localView.members) {
    final candidate = localView.member(id)!;
    final person = candidate.personId;
    if (id == localView.me ||
        candidate.kind != DeviceKind.mobile ||
        person == null ||
        person == personId ||
        !localView._validPerson(person)) {
      continue;
    }
    try {
      final view = await views.putIfAbsent(
        id,
        () => registry.viewFor(
          me: id,
          mySigningKey: candidate.signingKey,
          livePeople: localView.livePeople,
        ),
      );
      if (view.selfEntitled(personId)) return null;
    } on RegistryException {
      continue;
    }
  }
  return ProtectionRequestBlock.noConfirmer;
}

/// Estado de una identidad web desde una raíz móvil fijada.
enum WebDeviceStatus { confirmed, pending, revoked, unknown }

/// Consulta desde la vista de una raíz móvil de confianza, creada con
/// [DeviceRegistry.viewFor] y el id y la clave públicos de esa raíz (no los
/// de la web). No elige raíces ni altera la vista. Un miembro histórico
/// huérfano queda sin confirmar; [RegistryView.revokedByOthers] indica que
/// quien llama debe cambiar de raíz antes de usarla para publicar.
WebDeviceStatus webStatusIn(RegistryView view, String webDeviceId) {
  if (view.self.kind != DeviceKind.mobile || view.me == webDeviceId) {
    throw const RegistryException('la web necesita una raíz móvil externa');
  }
  if (view.revoked.contains(webDeviceId)) return WebDeviceStatus.revoked;
  final device = view.device(webDeviceId);
  if (device != null) {
    if (device.kind != DeviceKind.web) return WebDeviceStatus.unknown;
    return view.member(webDeviceId) != null
        ? WebDeviceStatus.confirmed
        : WebDeviceStatus.pending;
  }
  return view.everMembers.contains(webDeviceId)
      ? WebDeviceStatus.pending
      : WebDeviceStatus.unknown;
}

/// Lo que cambia en el registro y lo que hay que hacer después.
class RegistryChange {
  /// Crea el cambio.
  const RegistryChange({
    required this.registry,
    required this.rotates,
    this.orphans = const <KnownDevice>[],
  });

  /// El registro nuevo.
  final DeviceRegistry registry;

  /// Si abre una época: hay que rotar la `familyKey` y las claves de
  /// sorpresa, y volver a sellar los slots.
  final bool rotates;

  /// Móviles que eran de la familia (o tenían derecho a las sorpresas de
  /// alguien) para este móvil y, después del cambio, ya no: solo los unía lo
  /// que se ha quitado. Nunca se avalan solos (revisión de la fase 2a,
  /// hallazgo 1): la interfaz pide confirmarlos uno a uno ([approveDevice])
  /// o revocarlos. Como los ve este móvil antes del cambio.
  ///
  /// Al cambiar de persona ([changePerson]) también van los miembros que,
  /// después del cambio, este móvil no ve con derecho a las sorpresas de
  /// alguna persona que no es la suya, aunque antes tampoco los viera así:
  /// sus avales de antes no valen para eso (por ejemplo, los dio sin persona;
  /// segunda revisión, N2). Volver a avalarlos desde la ficha nueva lo
  /// arregla.
  final List<KnownDevice> orphans;
}

/// Los móviles que [before] veía activos o con derecho y [after] ya no (sin
/// [except], este móvil ni los revocados).
List<KnownDevice> _orphansBetween(
  RegistryView before,
  RegistryView after, {
  Set<String> except = const <String>{},
}) => [
  for (final id in before.members)
    if (id != before.me &&
        !except.contains(id) &&
        !after.revoked.contains(id) &&
        (after.member(id) == null ||
            before.livePeople.any(
              (p) =>
                  before.entitled(id, p) != null &&
                  after.entitled(id, p) == null,
            )))
      before.member(id)!,
];

/// Los miembros a los que [after] no ve con derecho a las sorpresas de
/// alguna persona viva que no es la suya (N2). Solo si este móvil tiene una
/// persona que existe: sin ella no avala a nadie para las sorpresas, y
/// volver a avalar no arreglaría nada.
List<KnownDevice> _unvouchedMembers(RegistryView after) => [
  if (after._personOk(after.myPerson))
    for (final id in after.members)
      if (id != after.me &&
          after.member(id)!.kind == DeviceKind.mobile &&
          after._personOk(after.member(id)!.personId) &&
          after.livePeople.any(
            (p) =>
                p != after.member(id)!.personId &&
                after.entitled(id, p) == null,
          ))
        after.member(id)!,
];

/// Este móvil aprueba [record], la ficha de otro móvil (lo confirma una
/// persona en la pantalla: «este móvil es de Q»). Lanza [RegistryException]
/// si la ficha no vale, si el móvil está revocado o si es él mismo.
Future<RegistryChange> approveDevice({
  required DeviceRegistry registry,
  required RegistryView view,
  required DeviceKeys myKeys,
  required DeviceRecord record,
}) async {
  if (record.deviceId == view.me) {
    throw const RegistryException('nadie se avala a sí mismo');
  }
  if (view.revoked.contains(record.deviceId)) {
    throw const RegistryException('ese móvil está revocado');
  }
  return RegistryChange(
    registry: await registry.withDeclarations(
      records: [record],
      vouches: [
        await Vouch.create(
          keys: myKeys,
          voucher: registry.recordByDigest(view.self.recordDigest)!,
          record: record,
        ),
      ],
      anchor: view.anchor,
    ),
    rotates: false,
  );
}

/// Este móvil revoca a [deviceId]. Abre una época.
///
/// No avala a nadie (hallazgo 1): un móvil que solo estaba unido a la familia
/// por el revocado (lo emparejó él, o lo emparejó alguien que solo él
/// confirmó) queda en [RegistryChange.orphans], y la interfaz pide
/// confirmarlo o revocarlo.
Future<RegistryChange> revokeDevice({
  required DeviceRegistry registry,
  required RegistryView view,
  required DeviceKeys myKeys,
  required String deviceId,
}) async {
  final out = await registry.withRevocation(
    await Revocation.create(
      keys: myKeys,
      by: registry.recordByDigest(view.self.recordDigest)!,
      deviceId: deviceId,
    ),
    anchor: view.anchor,
  );
  final after = await out.viewFor(
    me: view.me,
    mySigningKey: myKeys.publicKeys.signing,
    livePeople: view.livePeople,
  );
  return RegistryChange(
    registry: out,
    rotates: true,
    orphans: _orphansBetween(view, after, except: {deviceId}),
  );
}

/// Este móvil cambia de persona: publica una ficha nueva (`seq` + 1) que los
/// avales anteriores ya no cubren. Hasta que otro móvil la apruebe queda
/// pendiente y sin derecho a nada; abre una época (rotación), y quien lo
/// llama debe purgar el llavero, la copia local del ámbito de [personId] y
/// lo que tenga en memoria.
///
/// Los avales que este móvil dio siguen valiendo para quién es de la familia;
/// para las sorpresas de una persona, solo si cuando los dio no era de ella
/// (hallazgo 5). Los que dejan de tener derecho a ojos de este móvil, y los
/// que con la ficha nueva no tienen derecho a las sorpresas de alguien que
/// no es su persona (por ejemplo, porque este móvil los avaló sin persona;
/// N2), van en [RegistryChange.orphans], para confirmarlos otra vez.
Future<RegistryChange> changePerson({
  required DeviceRegistry registry,
  required RegistryView view,
  required DeviceKeys myKeys,
  required String? personId,
}) async {
  final mine = registry._records[view.self.recordDigest]!;
  if (mine.personId == personId) {
    return RegistryChange(registry: registry, rotates: false);
  }
  if (mine.seq >= kMaxDeviceSeq) {
    throw const RegistryException('este móvil ya no puede cambiar de persona');
  }
  final out = await registry.withRecord(
    await DeviceRecord.create(
      keys: myKeys,
      listId: registry.listId,
      deviceId: view.me,
      personId: personId,
      seq: mine.seq + 1,
      kind: mine.kind,
    ),
    anchor: view.anchor,
  );
  final after = await out.viewFor(
    me: view.me,
    mySigningKey: myKeys.publicKeys.signing,
    livePeople: view.livePeople,
  );
  final lost = _orphansBetween(view, after);
  return RegistryChange(
    registry: out,
    rotates: true,
    orphans: [
      ...lost,
      for (final d in _unvouchedMembers(after))
        if (!lost.any((o) => o.deviceId == d.deviceId)) d,
    ],
  );
}
