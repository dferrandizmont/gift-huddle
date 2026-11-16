part of 'recovery.dart';

/// Límites del binario completo y del JSON UTF-8, no de su base64 HTTP.
const int kRecoveryCapsuleMaxBytes = 1024 * 1024;
const int kRecoveryCapsuleMaxPlaintextBytes = 4 * 1024 * 1024;
const int kRecoveryCapsuleMaxHeaderBytes = 1024;
const int kRecoveryMaxActivePerIdentity = 1;
const int kRecoveryMaxActivePerList = 4;
const int kRecoveryMaxStoredBytes = 4 * 1024 * 1024;
const int kRecoveryMaxTemporaryBytes = 1024 * 1024;
const int kRecoveryMaxHttpBodyBytes = 1400832;
const int kRecoveryMaxControlBodyBytes = 4096;
const int kRecoveryMaxLifetimeIds = 256;
const int kRecoveryMaxReceipts = 512;
const int kRecoveryMaxRetiredVerifiers = 256;
const int kRecoveryReadsPerMinute = 30;
const int kRecoveryMutationsPerMinute = 6;
const int kRecoveryWritesPerDay = 24;
const int kRecoveryMaxRevision = 0x1fffffffffffff;
const String _capsuleKdfDomain = 'gift-huddle-recovery-capsule-v2';

Never _badCapsule() =>
    throw const RecoveryException('cápsula de recuperación no válida');

Map<String, Object?> _object(Object? value) {
  if (value is! Map) _badCapsule();
  try {
    return Map<String, Object?>.from(value);
  } catch (_) {
    _badCapsule();
  }
}

void _fields(Map<String, Object?> value, Set<String> fields) {
  if (value.length != fields.length || !value.keys.every(fields.contains)) {
    _badCapsule();
  }
}

int _revision(Object? value, {int min = 0}) {
  if (value is! int || value < min || value > kRecoveryMaxRevision) {
    _badCapsule();
  }
  return value;
}

String _id(Object? value) {
  if (value is! String || !kSyncIdPattern.hasMatch(value)) _badCapsule();
  return value;
}

bool _boolean(Object? value) {
  if (value is! bool) _badCapsule();
  return value;
}

/// Parte durable de CommonKeyState, sin cachés de bloqueo ni datos de usuario.
class RecoveryCommonKeys {
  RecoveryCommonKeys({
    required this.keyring,
    required this.revision,
    required this.lastKid,
  }) {
    _revision(revision);
    if (lastKid != null && keyring.entry(lastKid!) == null) _badCapsule();
  }

  final FamilyKeyring keyring;
  final int revision;
  final String? lastKid;

  Map<String, Object?> toJson() => {
    'keyring': keyring.toJson(),
    'revision': revision,
    'lastKid': lastKid,
  };

  factory RecoveryCommonKeys.fromJson(Object? raw) {
    final j = _object(raw);
    _fields(j, {'keyring', 'revision', 'lastKid'});
    final kid = j['lastKid'];
    if (kid != null && kid is! String) _badCapsule();
    return RecoveryCommonKeys(
      keyring: FamilyKeyring.fromJson(j['keyring']),
      revision: _revision(j['revision']),
      lastKid: kid as String?,
    );
  }
}

/// Intenciones y suelos durables. No incluye cachés de transporte que harían
/// saltarse la descarga inicial sobre una instalación vacía.
class RecoveryResumeState {
  RecoveryResumeState({
    required this.versionFloor,
    required this.hlc,
    this.slotRevisions = const {},
    this.minSlotRevisions = const {},
    this.knownMembers = const {},
    this.pendingRevocations = const {},
    this.pendingUnbackedRevocations = const {},
    this.revocationOperations = const {},
    this.keyPackageOutbox = const [],
    this.commonKeyOutbox = const [],
    this.commonFormatV2 = false,
    this.commonMigration = false,
    this.commonMigrationPut = false,
  });

  final int versionFloor;
  final Hlc hlc;
  final Map<String, int> slotRevisions;
  final Map<String, int> minSlotRevisions;
  final Set<String> knownMembers;
  final Set<String> pendingRevocations;
  final Set<String> pendingUnbackedRevocations;
  final Map<String, Map<String, Object?>> revocationOperations;
  final List<Map<String, Object?>> keyPackageOutbox;
  final List<Map<String, Object?>> commonKeyOutbox;
  final bool commonFormatV2;
  final bool commonMigration;
  final bool commonMigrationPut;

  Map<String, Object?> toJson() => {
    'versionFloor': versionFloor,
    'hlc': hlc.pack(),
    'slotRevisions': slotRevisions,
    'minSlotRevisions': minSlotRevisions,
    'knownMembers': knownMembers.toList()..sort(),
    'pendingRevocations': pendingRevocations.toList()..sort(),
    'pendingUnbackedRevocations': pendingUnbackedRevocations.toList()..sort(),
    'revocationOperations': revocationOperations,
    'keyPackageOutbox': keyPackageOutbox,
    'commonKeyOutbox': commonKeyOutbox,
    'commonFormatV2': commonFormatV2,
    'commonMigration': commonMigration,
    'commonMigrationPut': commonMigrationPut,
  };

  factory RecoveryResumeState.fromJson(Object? raw) {
    final j = _object(raw);
    _fields(j, {
      'versionFloor',
      'hlc',
      'slotRevisions',
      'minSlotRevisions',
      'knownMembers',
      'pendingRevocations',
      'pendingUnbackedRevocations',
      'revocationOperations',
      'keyPackageOutbox',
      'commonKeyOutbox',
      'commonFormatV2',
      'commonMigration',
      'commonMigrationPut',
    });
    String slotId(String value) {
      final parts = value.split('/');
      if (parts.length != 2) _badCapsule();
      _id(parts[0]);
      _id(parts[1]);
      return value;
    }

    Map<String, int> revisions(Object? v, {bool slots = false}) => {
      for (final e in _object(v).entries)
        (slots ? slotId(e.key) : _id(e.key)): _revision(e.value),
    };
    Set<String> ids(Object? v) {
      if (v is! List) _badCapsule();
      final result = {for (final id in v) _id(id)};
      if (canonicalJsonOf(result.toList()..sort()) != canonicalJsonOf(v)) {
        _badCapsule();
      }
      return result;
    }

    List<Map<String, Object?>> objects(Object? v) {
      if (v is! List) _badCapsule();
      return [for (final item in v) _object(item)];
    }

    if (j['hlc'] is! String) _badCapsule();
    return RecoveryResumeState(
      versionFloor: _revision(j['versionFloor']),
      hlc: Hlc.parse(j['hlc'] as String),
      slotRevisions: revisions(j['slotRevisions']),
      minSlotRevisions: revisions(j['minSlotRevisions'], slots: true),
      knownMembers: ids(j['knownMembers']),
      pendingRevocations: ids(j['pendingRevocations']),
      pendingUnbackedRevocations: ids(j['pendingUnbackedRevocations']),
      revocationOperations: {
        for (final e in _object(j['revocationOperations']).entries)
          _id(e.key): _object(e.value),
      },
      keyPackageOutbox: objects(j['keyPackageOutbox']),
      commonKeyOutbox: objects(j['commonKeyOutbox']),
      commonFormatV2: _boolean(j['commonFormatV2']),
      commonMigration: _boolean(j['commonMigration']),
      commonMigrationPut: _boolean(j['commonMigrationPut']),
    );
  }
}

/// Prueba de continuidad v1, sin permiso para seguir sincronizando en v1.
/// [sinceMillis] conserva la fecha original; restaurar nunca renueva su plazo.
class RecoveryV1Proof {
  RecoveryV1Proof({
    required this.listId,
    required this.key,
    required this.sinceMillis,
  }) {
    _id(listId);
    _revision(sinceMillis);
  }

  final String listId;
  final FamilyKey key;
  final int sinceMillis;

  Map<String, Object?> toJson() => {
    'v': 1,
    'listId': listId,
    'key': key.toBase64Url(),
    'since': sinceMillis,
  };

  factory RecoveryV1Proof.fromJson(Object? raw) {
    final j = _object(raw);
    _fields(j, {'v', 'listId', 'key', 'since'});
    if (j['v'] is! int || j['v'] != 1 || j['key'] is! String) _badCapsule();
    recoveryBytes32(j['key'] as String);
    return RecoveryV1Proof(
      listId: _id(j['listId']),
      key: FamilyKey.fromBase64Url(j['key'] as String),
      sinceMillis: _revision(j['since']),
    );
  }
}

/// Inventario capturado por el exportador bajo el cerrojo de familia.
/// Los diarios y recursos locales no caben en una cápsula remota: bloquean
/// su publicación hasta resolverlos. No se serializan diarios parciales.
class RecoveryTransitionState {
  const RecoveryTransitionState({
    this.v1Proof,
    this.legacyV1Pending = false,
    this.pendingV2 = false,
    this.personChangePending = false,
    this.protectionPending = false,
    this.renewalPending = false,
    this.localResourcesPending = false,
  });

  final RecoveryV1Proof? v1Proof;
  final bool legacyV1Pending;
  final bool pendingV2;
  final bool personChangePending;
  final bool protectionPending;
  final bool renewalPending;
  final bool localResourcesPending;

  bool get blocksPublication =>
      legacyV1Pending ||
      pendingV2 ||
      personChangePending ||
      protectionPending ||
      renewalPending ||
      localResourcesPending;

  Map<String, Object?> toJson() => {
    'v': 1,
    'v1Proof': v1Proof?.toJson(),
    'legacyV1Pending': legacyV1Pending,
    'pendingV2': pendingV2,
    'personChangePending': personChangePending,
    'protectionPending': protectionPending,
    'renewalPending': renewalPending,
    'localResourcesPending': localResourcesPending,
  };

  factory RecoveryTransitionState.fromJson(Object? raw) {
    final j = _object(raw);
    _fields(j, {
      'v',
      'v1Proof',
      'legacyV1Pending',
      'pendingV2',
      'personChangePending',
      'protectionPending',
      'renewalPending',
      'localResourcesPending',
    });
    if (j['v'] is! int || j['v'] != 1) _badCapsule();
    return RecoveryTransitionState(
      v1Proof: j['v1Proof'] == null
          ? null
          : RecoveryV1Proof.fromJson(j['v1Proof']),
      legacyV1Pending: _boolean(j['legacyV1Pending']),
      pendingV2: _boolean(j['pendingV2']),
      personChangePending: _boolean(j['personChangePending']),
      protectionPending: _boolean(j['protectionPending']),
      renewalPending: _boolean(j['renewalPending']),
      localResourcesPending: _boolean(j['localResourcesPending']),
    );
  }
}

/// Cápsula remota v2. No contiene documentos ni slots y no se puede construir
/// a partir de un RecoveryPayload v1 sin aportar el estado v2 que falta.
class RecoveryCapsulePayload {
  RecoveryCapsulePayload({
    required this.identity,
    required this.deviceName,
    required this.peerName,
    required this.paired,
    required this.personId,
    required this.deviceKeys,
    required this.familyKey,
    required this.registry,
    required this.commonKeys,
    required SurpriseKeyring surpriseKeys,
    required this.commonKeysMarked,
    required this.commonFormatFloor,
    required this.resume,
    required this.transition,
  }) : surpriseKeys = personId == null
           ? surpriseKeys
           : surpriseKeys.without(personId);

  final SyncIdentityV2 identity;
  final String deviceName;
  final String? peerName;
  final bool paired;
  final String? personId;
  final DeviceKeys deviceKeys;
  final FamilyKey familyKey;
  final DeviceRegistry registry;
  final RecoveryCommonKeys commonKeys;
  final SurpriseKeyring surpriseKeys;
  final bool commonKeysMarked;
  final int commonFormatFloor;
  final RecoveryResumeState resume;
  final RecoveryTransitionState transition;

  RegistryAnchor get anchor => RegistryAnchor(
    deviceId: identity.deviceId,
    signingKey: deviceKeys.publicKeys.signing,
  );

  Map<String, Object?> toJson() => {
    'v': 2,
    'kind': 'capsule',
    'identity': identity.toJson(),
    'deviceName': deviceName,
    'peerName': peerName,
    'paired': paired,
    'personId': personId,
    'deviceKeys': deviceKeys.toJson(),
    'familyKey': familyKey.toBase64Url(),
    'registry': registry.toLocalStoreJson(),
    'anchor': {
      'deviceId': anchor.deviceId,
      'signingKey': encodeBase64Url(anchor.signingKey),
    },
    'commonKeys': commonKeys.toJson(),
    'surpriseKeys': surpriseKeys.toJson(),
    'commonKeysMarked': commonKeysMarked,
    'commonFormatFloor': commonFormatFloor,
    'resume': resume.toJson(),
    'transition': transition.toJson(),
  };

  /// Verifica sin aceptar la pérdida silenciosa de firmas/claves corruptas.
  static Future<RecoveryCapsulePayload> fromJson(Object? raw) async {
    try {
      final j = _object(raw);
      _fields(j, {
        'v',
        'kind',
        'identity',
        'deviceName',
        'peerName',
        'paired',
        'personId',
        'deviceKeys',
        'familyKey',
        'registry',
        'anchor',
        'commonKeys',
        'surpriseKeys',
        'commonKeysMarked',
        'commonFormatFloor',
        'resume',
        'transition',
      });
      if (j['v'] is! int || j['v'] != 2 || j['kind'] != 'capsule') {
        _badCapsule();
      }
      final identity = SyncIdentityV2.fromJson(j['identity']);
      final keys = await DeviceKeys.fromJson(_object(j['deviceKeys']));
      final a = _object(j['anchor']);
      _fields(a, {'deviceId', 'signingKey'});
      if (a['deviceId'] != identity.deviceId ||
          a['signingKey'] != encodeBase64Url(keys.publicKeys.signing)) {
        _badCapsule();
      }
      final anchor = RegistryAnchor(
        deviceId: identity.deviceId,
        signingKey: keys.publicKeys.signing,
      );
      final registry = await DeviceRegistry.fromLocalStoreJson(
        j['registry'],
        anchor: anchor,
      );
      if (registry.listId != identity.listId ||
          canonicalJsonOf(registry.toLocalStoreJson()) !=
              canonicalJsonOf(j['registry'])) {
        _badCapsule();
      }
      final person = j['personId'];
      if (person != null) _id(person);
      final view = await registry.viewFor(
        me: identity.deviceId,
        mySigningKey: keys.publicKeys.signing,
        livePeople: {
          for (final r in registry.records)
            if (r.personId != null) r.personId!,
        },
      );
      final member = view.member(identity.deviceId);
      if (member == null ||
          view.revokedByOthers ||
          !view.selfApproved ||
          member.kind != DeviceKind.mobile ||
          member.personId != person ||
          encodeBase64Url(member.agreementKey) !=
              encodeBase64Url(keys.publicKeys.agreement)) {
        _badCapsule();
      }
      final surprises = SurpriseKeyring.fromJson(j['surpriseKeys']);
      if (person != null && surprises.keys.any((k) => k.personId == person)) {
        _badCapsule();
      }
      final common = RecoveryCommonKeys.fromJson(j['commonKeys']);
      if (common.keyring.candidates.any(
        (c) => c.listId != identity.listId || c.syncId != identity.syncId,
      )) {
        _badCapsule();
      }
      final floor = _revision(j['commonFormatFloor'], min: 1);
      if (floor > 2 ||
          j['deviceName'] is! String ||
          (j['peerName'] != null && j['peerName'] is! String)) {
        _badCapsule();
      }
      final resume = RecoveryResumeState.fromJson(j['resume']);
      final transition = RecoveryTransitionState.fromJson(j['transition']);
      if (transition.v1Proof != null &&
          transition.v1Proof!.listId != identity.listId) {
        _badCapsule();
      }
      for (final packet in resume.keyPackageOutbox) {
        final parsed = KeyBundle.fromJson(packet);
        if (parsed.listId != identity.listId ||
            canonicalJsonOf(parsed.toJson()) != canonicalJsonOf(packet)) {
          _badCapsule();
        }
      }
      for (final packet in resume.commonKeyOutbox) {
        final parsed = FamilyKeyBundle.fromJson(packet);
        if (parsed.listId != identity.listId ||
            parsed.syncId != identity.syncId ||
            canonicalJsonOf(parsed.toJson()) != canonicalJsonOf(packet)) {
          _badCapsule();
        }
      }
      for (final operation in resume.revocationOperations.values) {
        final parsed = await DeviceRegistry.fromJsonVerified(
          operation,
          anchor: anchor,
        );
        if (parsed.listId != identity.listId ||
            canonicalJsonOf(parsed.toJson()) != canonicalJsonOf(operation)) {
          _badCapsule();
        }
      }
      if (resume.hlc.node != identity.deviceId ||
          (floor == 2 && !resume.commonFormatV2) ||
          (resume.commonMigrationPut && !resume.commonFormatV2)) {
        _badCapsule();
      }
      final payload = RecoveryCapsulePayload(
        identity: identity,
        deviceName: j['deviceName'] as String,
        peerName: j['peerName'] as String?,
        paired: _boolean(j['paired']),
        personId: person as String?,
        deviceKeys: keys,
        familyKey: FamilyKey.fromBase64Url(j['familyKey'] as String),
        registry: registry,
        commonKeys: common,
        surpriseKeys: surprises,
        commonKeysMarked: _boolean(j['commonKeysMarked']),
        commonFormatFloor: floor,
        resume: resume,
        transition: transition,
      );
      if (canonicalJsonOf(payload.toJson()) != canonicalJsonOf(j)) {
        _badCapsule();
      }
      return payload;
    } on RecoveryException {
      rethrow;
    } catch (_) {
      _badCapsule();
    }
  }
}

/// Clave de cifrado con parámetros fijos y dominio diferente al fichero R-c.
Future<Uint8List> deriveRecoveryCapsuleKey(RecoveryCode code, List<int> salt) {
  if (salt.length != 16) _badCapsule();
  final entropy = code.entropy;
  final s = Uint8List.fromList(salt);
  return runTask(() => _argon2id(entropy, s, 19456, 2, 1, _capsuleKdfDomain));
}

/// Cabecera validada antes de gastar Argon2 o descomprimir.
class RecoveryCapsuleHeader {
  RecoveryCapsuleHeader._(
    this.recoveryId,
    this.revision,
    this.salt,
    this.aadEnd,
  );
  final String recoveryId;
  final int revision;
  final Uint8List salt;
  final int aadEnd;
}

RecoveryCapsuleHeader peekRecoveryCapsule(Uint8List bytes) {
  try {
    if (bytes.length > kRecoveryCapsuleMaxBytes ||
        bytes.length < 35 ||
        bytes[0] != 0x47 ||
        bytes[1] != 0x48 ||
        bytes[2] != 0x52 ||
        bytes[3] != 2) {
      _badCapsule();
    }
    final length = (bytes[4] << 8) | bytes[5];
    final end = 6 + length;
    if (length > kRecoveryCapsuleMaxHeaderBytes || bytes.length < end + 28) {
      _badCapsule();
    }
    final text = utf8.decode(Uint8List.sublistView(bytes, 6, end));
    final h = _object(jsonDecode(text));
    _fields(h, {'k', 'kdf', 'rid', 'r', 's', 'v'});
    if (h['v'] is! int ||
        h['v'] != 2 ||
        h['k'] != 'capsule' ||
        canonicalJsonOf(h) != text ||
        canonicalJsonOf(h['kdf']) !=
            canonicalJsonOf(RecoveryKdfParams.standard._toJson())) {
      _badCapsule();
    }
    final rid = h['rid'] as String;
    recoveryBytes32(rid);
    final salt = decodeBase64Url(h['s'] as String);
    if (salt.length != 16 || encodeBase64Url(salt) != h['s']) _badCapsule();
    return RecoveryCapsuleHeader._(rid, _revision(h['r'], min: 1), salt, end);
  } on RecoveryException {
    rethrow;
  } catch (_) {
    _badCapsule();
  }
}

Future<Uint8List> sealRecoveryCapsule(
  RecoveryCapsulePayload payload,
  RecoveryCode code, {
  required int revision,
}) => _sealCapsule(payload, code, revision: revision);

@visibleForTesting
Future<Uint8List> sealRecoveryCapsuleForTesting(
  RecoveryCapsulePayload payload,
  RecoveryCode code, {
  required int revision,
  required List<int> salt,
  required List<int> nonce,
}) => _sealCapsule(payload, code, revision: revision, salt: salt, nonce: nonce);

Future<Uint8List> _sealCapsule(
  RecoveryCapsulePayload payload,
  RecoveryCode code, {
  required int revision,
  List<int>? salt,
  List<int>? nonce,
}) async {
  _revision(revision, min: 1);
  if (payload.resume.commonMigration ||
      payload.resume.commonMigrationPut ||
      payload.transition.blocksPublication) {
    throw const RecoveryException('transición pendiente de completar');
  }
  final plain = utf8.encode(canonicalJsonOf(payload.toJson()));
  if (plain.length > kRecoveryCapsuleMaxPlaintextBytes) _badCapsule();
  final compressed = Deflate(plain).getBytes();
  final locator = await deriveRecoveryLocator(code);
  final s = salt ?? secureRandomBytes(16);
  final n = nonce ?? secureRandomBytes(12);
  if (s.length != 16 || n.length != 12) _badCapsule();
  final header = utf8.encode(
    canonicalJsonOf({
      'k': 'capsule',
      'kdf': RecoveryKdfParams.standard._toJson(),
      'rid': locator.recoveryId,
      'r': revision,
      's': encodeBase64Url(s),
      'v': 2,
    }),
  );
  final aad = [
    0x47,
    0x48,
    0x52,
    2,
    header.length >> 8,
    header.length & 255,
    ...header,
  ];
  if (header.length > kRecoveryCapsuleMaxHeaderBytes ||
      aad.length + 28 + compressed.length > kRecoveryCapsuleMaxBytes) {
    _badCapsule();
  }
  await RecoveryCapsulePayload.fromJson(jsonDecode(utf8.decode(plain)));
  final key = await deriveRecoveryCapsuleKey(code, s);
  final box = await AesGcm.with256bits().encrypt(
    compressed,
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

Future<RecoveryCapsulePayload> openRecoveryCapsule(
  Uint8List bytes,
  RecoveryCode code, {
  required int expectedRevision,
}) async {
  if (bytes.length > kRecoveryCapsuleMaxBytes) _badCapsule();
  bytes = Uint8List.fromList(bytes);
  final h = peekRecoveryCapsule(bytes);
  _revision(expectedRevision, min: 1);
  final locator = await deriveRecoveryLocator(code);
  if (h.revision != expectedRevision || h.recoveryId != locator.recoveryId) {
    _badCapsule();
  }
  final key = await deriveRecoveryCapsuleKey(code, h.salt);
  try {
    final compressed = await AesGcm.with256bits().decrypt(
      SecretBox(
        Uint8List.sublistView(bytes, h.aadEnd + 12, bytes.length - 16),
        nonce: Uint8List.sublistView(bytes, h.aadEnd, h.aadEnd + 12),
        mac: Mac(Uint8List.sublistView(bytes, bytes.length - 16)),
      ),
      secretKey: SecretKey(key),
      aad: Uint8List.sublistView(bytes, 0, h.aadEnd),
    );
    final plain = _inflateCapsule(Uint8List.fromList(compressed));
    final text = utf8.decode(plain);
    final json = jsonDecode(text);
    if (canonicalJsonOf(json) != text) _badCapsule();
    return await RecoveryCapsulePayload.fromJson(json);
  } on RecoveryException {
    rethrow;
  } catch (_) {
    _badCapsule();
  }
}

/// Representación HTTP, validada antes de decodificar un base64 arbitrario.
class RecoveryCapsule {
  RecoveryCapsule(Uint8List bytes) : bytes = Uint8List.fromList(bytes) {
    peekRecoveryCapsule(this.bytes);
  }

  final Uint8List bytes;

  Map<String, Object?> toJson() {
    final h = peekRecoveryCapsule(bytes);
    return {
      'v': 2,
      'recoveryId': h.recoveryId,
      'revision': h.revision,
      'capsule': encodeBase64Url(bytes),
    };
  }

  factory RecoveryCapsule.fromJson(Object? raw) {
    try {
      final j = _object(raw);
      _fields(j, {'v', 'recoveryId', 'revision', 'capsule'});
      final encoded = j['capsule'];
      if (j['v'] is! int ||
          j['v'] != 2 ||
          encoded is! String ||
          encoded.length > (kRecoveryCapsuleMaxBytes * 4 + 2) ~/ 3) {
        _badCapsule();
      }
      final capsule = RecoveryCapsule(decodeBase64Url(encoded));
      if (encodeBase64Url(capsule.bytes) != encoded) _badCapsule();
      final h = peekRecoveryCapsule(capsule.bytes);
      if (j['recoveryId'] != h.recoveryId ||
          _revision(j['revision'], min: 1) != h.revision) {
        _badCapsule();
      }
      return capsule;
    } on RecoveryException {
      rethrow;
    } catch (_) {
      _badCapsule();
    }
  }
}

// Tope independiente de R-c/sobres: comprobar cada escritura y referencia
// DEFLATE antes de reservar memoria (archive puede envolver la excepción).
class _CapsuleOutput extends OutputMemoryStream {
  _CapsuleOutput() : super(size: 1024);
  int _capacity = 1024;

  void _room(int extra) {
    final need = length + extra;
    if (need > kRecoveryCapsuleMaxPlaintextBytes) _badCapsule();
    if (need > _capacity) {
      final doubled = _capacity * 2;
      _capacity = need > doubled ? need : doubled;
      if (_capacity > kRecoveryCapsuleMaxPlaintextBytes) {
        _capacity = kRecoveryCapsuleMaxPlaintextBytes;
      }
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

Uint8List _inflateCapsule(Uint8List compressed) {
  final output = _CapsuleOutput();
  final inflate = Inflate(compressed, output: output);
  if (!inflate.isFinished) _badCapsule();
  return output.getBytes();
}
