import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/device_keys.dart' show DeviceKeys, kSyncIdPattern;
import '../../../core/sync/device_registry.dart';
import '../../../core/sync/access_policy.dart';
import '../../../core/sync/envelope.dart';
import '../../../core/sync/family_doc.dart';
import '../../../core/sync/hlc.dart';
import '../../../core/sync/model.dart' show Collections;
import '../../../core/sync/pairing_v2.dart' show SyncIdentityV2;
import '../../../core/sync/protected_doc.dart' show SlotSet;
import 'device_keys_store.dart';
import 'generation_storage.dart';
import 'storage.dart';
import 'storage_providers.dart';

const _identityKey = 'family.identity';
const _familyKeyKey = 'family.key';
const _localKeyKey = 'family.localKey';
const _docFile = 'family.doc';
const _registryFile = 'family.registry';
const _slotsFile = 'family.slots';
const _commonKeysFile = 'family.commonkeys';
const _retainedCommonsFile = 'family.retainedcommons';
const _scopePeopleKey = 'family.scopePeople';
const _syncV2Key = 'family.syncV2';
const _syncV2StateKey = 'family.syncV2State';
const _legacyV1Key = 'family.legacyV1';
const _v1ProofKey = 'family.v1ProofKey';
const _pendingV2Key = 'family.pendingV2';
const _orphansKey = 'family.orphans';
const _selfPersonChangeKey = 'family.selfPersonChange';
const _commonKeysMarkerKey = 'family.commonKeysMarker';
const _commonFormatFloorKey = 'family.commonFormatFloor';
const _retainedPendingKey = 'family.retainedPending';
const _magic = [0x52, 0x47, 0x44, 0x01]; // "RGD" + versión 1

/// Lo que vale una marca de formato mínimo que no se entiende: el formato 2
/// (el más alto que conoce esta versión).
const int kCommonFormatFloorUnknown = 2;
const _nonceLength = 12;
const _macLength = 16;
final _aad = utf8.encode('regalos-doc:v1');

/// No se puede leer lo guardado (clave local perdida, fichero dañado...).
class FamilyStoreException implements Exception {
  /// Crea el error.
  const FamilyStoreException(this.message);

  /// Qué ha pasado.
  final String message;

  @override
  String toString() => 'FamilyStoreException: $message';
}

/// Quién es este móvil dentro de la familia.
class FamilyIdentity {
  /// Crea la identidad.
  const FamilyIdentity({
    required this.listId,
    required this.node,
    required this.deviceName,
    this.peerName,
    this.paired = false,
    this.selfRecipientId,
  });

  /// Lee la identidad. Lanza [FormatException] si no es válida.
  factory FamilyIdentity.fromJson(Map<String, Object?> json) {
    final listId = json['listId'];
    final node = json['node'];
    final deviceName = json['deviceName'];
    if (listId is! String ||
        listId.isEmpty ||
        node is! String ||
        node.isEmpty ||
        deviceName is! String) {
      throw const FormatException('identidad no válida');
    }
    final peer = json['peerName'];
    final self = json['selfRecipientId'];
    return FamilyIdentity(
      listId: listId,
      node: node,
      deviceName: deviceName,
      peerName: peer is String ? peer : null,
      paired: json['paired'] == true,
      selfRecipientId: self is String && self.isNotEmpty ? self : null,
    );
  }

  /// Id de la lista de la familia.
  final String listId;

  /// Id de este dispositivo en el reloj lógico.
  final String node;

  /// Nombre de este móvil.
  final String deviceName;

  /// Nombre del otro móvil, si este se unió por QR.
  final String? peerName;

  /// Si ya hay otro móvil emparejado.
  final bool paired;

  /// «Yo»: el id estable de la persona dueña de este móvil, o null si no se
  /// ha elegido. Es local: nunca va al documento compartido, y nunca guarda
  /// el nombre ni el texto «Yo» (ADR 0004). Elegirla no da permisos.
  final String? selfRecipientId;

  /// Copia con cambios.
  FamilyIdentity copyWith({
    String? peerName,
    bool? paired,
    String? deviceName,
  }) => FamilyIdentity(
    listId: listId,
    node: node,
    deviceName: deviceName ?? this.deviceName,
    peerName: peerName ?? this.peerName,
    paired: paired ?? this.paired,
    selfRecipientId: selfRecipientId,
  );

  /// Copia con otra persona de «Yo» (null la quita).
  FamilyIdentity withSelfRecipient(String? recipientId) => FamilyIdentity(
    listId: listId,
    node: node,
    deviceName: deviceName,
    peerName: peerName,
    paired: paired,
    selfRecipientId: recipientId,
  );

  /// A JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'listId': listId,
    'node': node,
    'deviceName': deviceName,
    'peerName': peerName,
    'paired': paired,
    if (selfRecipientId != null) 'selfRecipientId': selfRecipientId,
  };
}

/// Todo lo que se guarda de una familia.
class StoredFamily {
  /// Crea el conjunto.
  const StoredFamily({
    required this.identity,
    required this.key,
    required this.doc,
  });

  /// Identidad de este móvil.
  final FamilyIdentity identity;

  /// Clave de la familia.
  final FamilyKey key;

  /// El documento.
  final FamilyDoc doc;
}

typedef VerifiedRegistry = ({
  DeviceRegistry registry,
  RegistryView view,
  DeviceKeys keys,
});

typedef LocalRegistryRead = ({
  bool hasV2Identity,
  VerifiedRegistry? snapshot,
  RegistryException? viewError,
});

/// Guardado local de la familia.
///
/// El documento va cifrado (AES-256-GCM) en un fichero privado con una clave
/// local distinta de la de la familia; esa clave, la identidad y la clave de
/// la familia van en el almacén seguro del sistema.
class FamilyStore {
  /// Crea el guardado sobre [secrets] y [files]. [deviceKeys] tiene que ser
  /// el mismo guardado de claves que usa el resto de la app: sus escrituras
  /// van en una sola cola, y con dos instancias purgar el llavero podría
  /// pisarse con guardarlo (revisión de seguridad, N5).
  FamilyStore({
    required SecretStore secrets,
    required FileStore files,
    required this._deviceKeys,
  }) : _secrets = GenerationSecretStore.active(secrets),
       _files = GenerationFileStore.active(files, secrets);

  final SecretStore _secrets;
  final FileStore _files;
  final DeviceKeysStore _deviceKeys;
  final AesGcm _aes = AesGcm.with256bits();
  int? _loadedActivation;
  Hlc? _recoveryHlc;

  Future<int> _activation() async =>
      (await GenerationDirectory.read((_secrets as GenerationSecretStore).root))
          ?.activation ??
      0;

  Future<T> _inGeneration<T>(Future<T> Function() task) =>
      (_secrets as GenerationSecretStore).inGeneration(task);

  /// Lee lo guardado, o `null` si es el primer arranque.
  ///
  /// Lanza [FamilyStoreException] si hay datos pero no se pueden leer.
  Future<StoredFamily?> load() => _inGeneration(() async {
    _loadedActivation = await _activation();
    if (!await isTransferred()) await finishSelfPersonChange();
    final rawIdentity = await _secrets.read(_identityKey);
    if (rawIdentity == null) {
      return null;
    }
    final FamilyIdentity identity;
    try {
      final json = jsonDecode(rawIdentity) as Map;
      identity = FamilyIdentity.fromJson(Map<String, Object?>.from(json));
    } catch (_) {
      throw const FamilyStoreException('identidad dañada');
    }
    final rawKey = await _secrets.read(_familyKeyKey);
    if (rawKey == null) {
      throw const FamilyStoreException('falta la clave de la familia');
    }
    final FamilyKey key;
    try {
      key = FamilyKey.fromBase64Url(rawKey);
    } catch (_) {
      throw const FamilyStoreException('clave de la familia dañada');
    }
    final bytes = await _files.read(_docFile);
    if (bytes == null && await _generationManaged()) {
      throw const FamilyStoreException('falta el documento de la generación');
    }
    var doc = FamilyDoc.empty(identity.listId);
    if (bytes != null) {
      final localKey = await _secrets.read(_localKeyKey);
      if (localKey == null) {
        throw const FamilyStoreException('falta la clave local');
      }
      final FamilyDoc read;
      try {
        read = FamilyDoc.fromJson(
          Map<String, Object?>.from(
            await _decrypt(bytes, localKey, _aad) as Map,
          ),
        );
      } on FormatException catch (e) {
        throw FamilyStoreException('documento dañado: ${e.message}');
      }
      // Un cambio de familia interrumpido puede dejar un documento de otra
      // lista: manda la identidad.
      if (read.listId == identity.listId) {
        doc = read;
      } else if (await _generationManaged()) {
        throw const FamilyStoreException('documento de otra generación');
      }
    }
    return StoredFamily(identity: identity, key: key, doc: doc);
  });

  /// Guarda el documento (cifrado y atómico).
  Future<void> saveDoc(FamilyDoc doc) => _inGeneration(() async {
    await assertWritable();
    final selector = _secrets as GenerationSecretStore;
    if (selector.syncId == null && !selector.fixedNamespace) {
      final activation = await _activation();
      if (_loadedActivation != null && _loadedActivation != activation) {
        throw StateError('active generation changed; reload the family');
      }
      _loadedActivation ??= activation;
    }
    final rawIdentity = await _secrets.read(_identityKey);
    if (await _generationManaged() &&
        rawIdentity != null &&
        (jsonDecode(rawIdentity) as Map)['listId'] != doc.listId) {
      throw const FamilyStoreException('documento de otra generación');
    }
    await _writeEncrypted(_docFile, _aad, utf8.encode(doc.canonicalJson()));
  });

  /// Web persists undo intents before acknowledging the action. Native keeps
  /// its existing in-memory undo lifecycle.
  bool get durableGiftDeletes => false;

  /// Restricted adapters own their storage and never run mobile recovery.
  bool get supportsRecovery => true;
  Future<void> saveGiftDeleteIntent(
    FamilyDoc before,
    FamilyDoc after,
    String id,
    Duration window,
  ) => throw UnsupportedError('durableGiftDeletes');
  Future<bool> undoGiftDeleteIntent(String id) =>
      throw UnsupportedError('durableGiftDeletes');

  /// A restricted adapter may retain an action apart from the visible candidate.
  /// Native saves always display precisely the document requested.
  FamilyDoc savedDoc(FamilyDoc requested) => requested;

  /// Cascades must include gifts hidden by an undoable deletion.
  Future<FamilyDoc> cascadeDoc(FamilyDoc displayed) async => displayed;

  /// Saves a cascade relative to its live input, including indirect writes.
  Future<void> saveCascadeDoc(FamilyDoc before, FamilyDoc after) =>
      saveDoc(after);

  /// Includes the web queue's HLCs even for actions excluded from its candidate.
  Hlc? latestStoredStamp(FamilyDoc doc) {
    final stamp = doc.maxStamp;
    return _recoveryHlc != null && (stamp == null || _recoveryHlc! > stamp)
        ? _recoveryHlc
        : stamp;
  }

  /// Rejected by the web adapter before mobile-only operations expose data.
  void requireMobileOperation(String operation) {}

  Future<void> _writeEncrypted(
    String file,
    List<int> aad,
    List<int> plain,
  ) async {
    await assertWritable();
    if (file == _registryFile || file == _commonKeysFile) {
      Object? material(Object? raw) {
        if (raw is! Map || file != _commonKeysFile) return raw;
        return Map<String, Object?>.from(raw)
          ..remove('r')
          ..remove('b');
      }

      if (canonicalJsonOf(material(await _readEncrypted(file, aad))) !=
          canonicalJsonOf(material(jsonDecode(utf8.decode(plain))))) {
        await (_secrets as GenerationSecretStore).markRecoveryDirty();
      }
    }
    final localKey = await _localKey();
    final box = await _aes.encrypt(
      plain,
      secretKey: SecretKey(decodeBase64Url(localKey)),
      aad: aad,
    );
    final out = BytesBuilder(copy: false)
      ..add(_magic)
      ..add(box.nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    await _files.writeAtomic(file, out.toBytes());
  }

  /// Lo guardado en [file] ya descifrado (JSON), o null si no existe.
  Future<Object?> _readEncrypted(String file, List<int> aad) async {
    final bytes = await _files.read(file);
    if (bytes == null) return null;
    final localKey = await _secrets.read(_localKeyKey);
    if (localKey == null) {
      throw const FamilyStoreException('falta la clave local');
    }
    return _decrypt(bytes, localKey, aad);
  }

  // ------------------------------------------- sorpresas y registro (ADR 0004)

  static List<int> _scopeAad(String kind, String personId) =>
      utf8.encode('regalos-$kind:v1:$personId');

  static String _scopeFile(String kind, String personId) {
    if (!kSyncIdPattern.hasMatch(personId)) {
      throw const FamilyStoreException('persona no válida');
    }
    return 'family.$kind.$personId';
  }

  Future<Set<String>> _scopePeople() async {
    final raw = await _secrets.read(_scopePeopleKey);
    if (raw == null) return <String>{};
    try {
      return {for (final p in jsonDecode(raw) as List) p as String};
    } catch (_) {
      throw const FamilyStoreException('índice de ámbitos dañado');
    }
  }

  Future<void> _rememberScopePerson(String personId) async {
    final people = await _scopePeople();
    if (people.add(personId)) {
      await _secrets.write(
        _scopePeopleKey,
        jsonEncode(people.toList()..sort()),
      );
    }
  }

  Future<FamilyDoc?> _readScopeFile(String kind, String personId) async {
    final json = await _readEncrypted(
      _scopeFile(kind, personId),
      _scopeAad(kind, personId),
    );
    if (json == null) return null;
    try {
      return FamilyDoc.fromJson(Map<String, Object?>.from(json as Map));
    } catch (_) {
      throw const FamilyStoreException('copia de sorpresas dañada');
    }
  }

  /// Guarda la copia local, cifrada, del ámbito de sorpresas de [personId]
  /// (la instantánea acumulativa de este móvil).
  Future<void> saveScope(String personId, FamilyDoc scope) =>
      _inGeneration(() async {
        final file = _scopeFile('scope', personId);
        await _rememberScopePerson(personId);
        await _writeEncrypted(
          file,
          _scopeAad('scope', personId),
          utf8.encode(scope.canonicalJson()),
        );
      });

  /// La copia local del ámbito de sorpresas de [personId], o null.
  Future<FamilyDoc?> readScope(String personId) =>
      _inGeneration(() async => _readScopeFile('scope', personId));

  /// Complete local scopes for recovery union, including locally queued bytes.
  Future<Map<String, FamilyDoc>> readRecoveryScopes() =>
      _inGeneration(() async {
        final result = <String, FamilyDoc>{};
        for (final person in await _scopePeople()) {
          var scope = await readScope(person);
          final overflow = await _readScopeFile('overflow', person);
          if (overflow != null) scope = scope?.merge(overflow) ?? overflow;
          if (scope != null) result[person] = scope;
        }
        return result;
      });

  /// Guarda en este móvil, cifrados, los regalos que la protección quitó del
  /// documento común y no cupieron en el bloque secreto
  /// (`ProtectionTransition.overflow`): se suman a los que ya hubiera, para
  /// que su contenido no se pierda (revisión de seguridad, N2 y N4).
  Future<void> saveOverflow(String personId, List<SyncRecord> records) =>
      _inGeneration(() async {
        if (records.isEmpty) return;
        final file = _scopeFile('overflow', personId);
        final previous =
            await _readScopeFile('overflow', personId) ??
            FamilyDoc.empty(await _listId());
        final merged = previous.merge(
          FamilyDoc(
            listId: previous.listId,
            collections: {
              Collections.gifts: {for (final r in records) r.id: r},
            },
          ),
        );
        await _rememberScopePerson(personId);
        await _writeEncrypted(
          file,
          _scopeAad('overflow', personId),
          utf8.encode(merged.canonicalJson()),
        );
      });

  /// Los regalos guardados con [saveOverflow] para [personId].
  Future<List<SyncRecord>> readOverflow(String personId) =>
      _inGeneration(() async {
        final doc = await _readScopeFile('overflow', personId);
        final gifts = doc?.collections[Collections.gifts] ?? const {};
        return [for (final id in gifts.keys.toList()..sort()) gifts[id]!];
      });

  /// Replaces the local pending set after a successful retry, without leaving
  /// tombstones that would prevent another capacity retry of the same id.
  Future<void> replaceOverflow(String personId, List<SyncRecord> records) =>
      _inGeneration(() async {
        await _rememberScopePerson(personId);
        await _writeEncrypted(
          _scopeFile('overflow', personId),
          _scopeAad('overflow', personId),
          utf8.encode(
            FamilyDoc(
              listId: await _listId(),
              collections: {
                Collections.gifts: {for (final r in records) r.id: r},
              },
            ).canonicalJson(),
          ),
        );
      });

  /// One encrypted write-ahead record. Callers hold the family v2 lock and
  /// controller queue until recovery has finished; no intermediate common is
  /// eligible for sync. This is local storage, not a wire format.
  Future<void> saveProtectionOperation(Map<String, Object?> operation) =>
      _inGeneration(
        () async => _writeEncrypted(
          'family.protection',
          utf8.encode('regalos-protection:v1'),
          utf8.encode(jsonEncode(operation)),
        ),
      );

  Future<bool> recoverProtectionOperation() async {
    // The external durable gift queue (web adapter) owns its encrypted
    // candidate and journal. It never uses this mobile filesystem.
    if (!supportsSecretScopes) return false;
    return _inGeneration(_recoverProtectionOperation);
  }

  Future<bool> _recoverProtectionOperation() async {
    final raw = await _readEncrypted(
      'family.protection',
      utf8.encode('regalos-protection:v1'),
    );
    if (raw == null) return false;
    final op = Map<String, Object?>.from(raw as Map);
    final person = op['person'] as String;
    // Outbox before keys; replaying is idempotent even after a partial write.
    if (op['keys'] != null) {
      final state = Map<String, Object?>.from(
        await readSyncV2State() as Map? ?? {},
      );
      final bundles = <String, Object?>{};
      for (final b in [...?state['o'] as List?, ...?op['bundles'] as List?]) {
        bundles[jsonEncode(b)] = b;
      }
      state['o'] = bundles.values.toList();
      await saveSyncV2State(state);
      final added = SurpriseKeyring.fromJson(op['keys']);
      await _deviceKeys.updateKeyring(op['list'] as String, (current) {
        var merged = current;
        for (final key in added.keys) {
          merged = merged.withKey(
            key,
            registryEpoch: op['epoch'] as int,
            allowed: (op['allowed'] as List).cast<String>(),
          );
        }
        return merged;
      });
    }
    await saveScope(
      person,
      FamilyDoc.fromJson(Map<String, Object?>.from(op['scope'] as Map)),
    );
    final additional = op['additionalScopes'] as Map? ?? const {};
    for (final entry in additional.entries) {
      final extra = Map<String, Object?>.from(entry.value as Map);
      await saveScope(
        entry.key as String,
        FamilyDoc.fromJson(Map<String, Object?>.from(extra['scope'] as Map)),
      );
      await replaceOverflow(
        entry.key as String,
        FamilyDoc.fromJson(Map<String, Object?>.from(extra['overflow'] as Map))
            .collections[Collections.gifts]!
            .values
            .toList(),
      );
    }
    await replaceOverflow(
      person,
      FamilyDoc.fromJson(Map<String, Object?>.from(op['overflow'] as Map))
          .collections[Collections.gifts]!
          .values
          .toList(),
    );
    await saveSlots(SlotSet.fromLocalStoreJson(op['slots']));
    final state = Map<String, Object?>.from(
      await readSyncV2State() as Map? ?? {},
    );
    state['p'] = {...?state['p'] as List?, person, ...additional.keys}.toList();
    await saveSyncV2State(state);
    await saveDoc(
      FamilyDoc.fromJson(Map<String, Object?>.from(op['common'] as Map)),
    );
    await _files.delete('family.protection');
    return true;
  }

  /// The external gift queue already guards and projects its public candidate;
  /// it cannot open mobile surprise storage. Existing adapters advertise that
  /// queue through durableGiftDeletes.
  bool get supportsSecretScopes => !durableGiftDeletes;

  /// Borra de este móvil la copia local del ámbito de [personId] y lo que
  /// hubiera guardado con [saveOverflow].
  Future<void> deleteScope(String personId) => _inGeneration(() async {
    await _files.delete(_scopeFile('scope', personId));
    await _files.delete(_scopeFile('overflow', personId));
  });

  Future<String> _listId() async {
    final raw = await _secrets.read(_identityKey);
    if (raw == null) throw const FamilyStoreException('no hay familia');
    try {
      return FamilyIdentity.fromJson(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      ).listId;
    } catch (_) {
      throw const FamilyStoreException('identidad dañada');
    }
  }

  /// Guarda el registro de móviles (cifrado con la clave local: no es
  /// secreto, pero así nadie lo cambia en el disco).
  Future<void> saveRegistry(DeviceRegistry registry) => _inGeneration(
    () async => _writeEncrypted(
      _registryFile,
      utf8.encode('regalos-registry:v1'),
      utf8.encode(jsonEncode(registry.toLocalStoreJson())),
    ),
  );

  /// El registro de móviles guardado, o null. Las fichas se vuelven a
  /// comprobar al leer. Con [anchor] (el de la vista de este móvil, si ya la
  /// tiene: `RegistryView.anchor`), lo que no quepa se ajusta igual que al
  /// fusionar, desalojando antes lo que no está enlazado con él (segunda
  /// revisión, N8).
  Future<DeviceRegistry?> readRegistry({RegistryAnchor? anchor}) =>
      _inGeneration(() async {
        final json = await _readEncrypted(
          _registryFile,
          utf8.encode('regalos-registry:v1'),
        );
        if (json == null) return null;
        try {
          return await DeviceRegistry.fromLocalStoreJson(json, anchor: anchor);
        } on RegistryException {
          throw const FamilyStoreException('registro de móviles dañado');
        }
      });

  /// Loads the signed registry and its view anchored to this device and list.
  Future<VerifiedRegistry?> readVerifiedRegistry(FamilyDoc doc) async =>
      (await readLocalRegistry(doc)).snapshot;

  /// Distinguishes a v1 installation from a v2 identity missing its registry.
  Future<LocalRegistryRead> readLocalRegistry(FamilyDoc doc) =>
      supportsSecretScopes
      ? _inGeneration(() => _readLocalRegistry(doc))
      : _readLocalRegistry(doc);

  Future<LocalRegistryRead> _readLocalRegistry(FamilyDoc doc) async {
    final v2 = await readSyncV2();
    if (v2 == null) {
      return (hasV2Identity: false, snapshot: null, viewError: null);
    }
    const unavailable = (hasV2Identity: true, snapshot: null, viewError: null);
    if (v2.listId != doc.listId) return unavailable;
    final keys = await _deviceKeys.read();
    if (keys == null) return unavailable;
    final signing = keys.publicKeys.signing;
    final registry = await readRegistry(
      anchor: RegistryAnchor(deviceId: v2.deviceId, signingKey: signing),
    );
    if (registry == null) {
      return (
        hasV2Identity: true,
        snapshot: null,
        viewError: const RegistryException('este móvil no está en el registro'),
      );
    }
    if (registry.listId != doc.listId) return unavailable;
    final view = await registry.viewFor(
      me: v2.deviceId,
      mySigningKey: signing,
      livePeople: livePeopleOf(doc),
    );
    return (
      hasV2Identity: true,
      snapshot: (registry: registry, view: view, keys: keys),
      viewError: null,
    );
  }

  /// Guarda los slots de sorpresas (ya verificados) que tiene este móvil.
  Future<void> saveSlots(SlotSet slots) => _inGeneration(
    () async => _writeEncrypted(
      _slotsFile,
      utf8.encode('regalos-slots:v1'),
      utf8.encode(jsonEncode(slots.toJson())),
    ),
  );

  /// Los slots guardados con [saveSlots] (vacío si no hay).
  Future<SlotSet> readSlots() => _inGeneration(() async {
    final json = await _readEncrypted(
      _slotsFile,
      utf8.encode('regalos-slots:v1'),
    );
    if (json == null) return SlotSet.empty;
    try {
      return SlotSet.fromLocalStoreJson(json);
    } catch (_) {
      throw const FamilyStoreException('slots de sorpresas dañados');
    }
  });

  /// Guarda lo que recuerda el ciclo de la clave común (ADR 0005, B3):
  /// llavero común, intención de reparto y revisión, en una sola escritura
  /// atómica cifrada con la clave local. JSON opaco para el almacén.
  Future<void> saveCommonKeys(Map<String, Object?> json) => _inGeneration(
    () async => _writeEncrypted(
      _commonKeysFile,
      utf8.encode('regalos-commonkeys:v1'),
      utf8.encode(jsonEncode(json)),
    ),
  );

  /// Lo guardado con [saveCommonKeys], o null.
  Future<Object?> readCommonKeys() => _inGeneration(
    () async =>
        _readEncrypted(_commonKeysFile, utf8.encode('regalos-commonkeys:v1')),
  );

  /// Durable recovery floors, consumed by the 5.4 publisher before allocating
  /// a new revision. Unlike slot caches they survive removal of a slot.
  Future<({Map<String, int> slots, Hlc? hlc})> readRecoveryRevisionFloors() =>
      _inGeneration(() async {
        final raw = await _readEncrypted(
          'family.recoveryFloors',
          utf8.encode('gift-huddle-recovery-floors-v1'),
        );
        if (raw == null) return (slots: <String, int>{}, hlc: null);
        final j = raw as Map;
        if (j['v'] != 1) throw const FormatException('invalid recovery floors');
        final slots = <String, int>{};
        for (final e in (j['slots'] as Map).entries) {
          final id = e.key as String;
          final n = e.value;
          if (id.split('/').length != 2 ||
              !id.split('/').every(kSyncIdPattern.hasMatch) ||
              n is! int ||
              n < 0 ||
              n > 0x1fffffffffffff) {
            throw const FormatException('invalid recovery floors');
          }
          slots[id] = n;
        }
        _recoveryHlc = j['hlc'] == null ? null : Hlc.parse(j['hlc'] as String);
        return (slots: slots, hlc: _recoveryHlc);
      });

  Future<void> raiseRecoveryRevisionFloors(
    Map<String, int> slots, {
    Hlc? hlc,
  }) => _inGeneration(
    () => GenerationStorageQueue.on(_secrets, 'recoveryFloors').run(() async {
      final old = await readRecoveryRevisionFloors();
      final merged = {...old.slots};
      for (final e in slots.entries) {
        if (e.key.split('/').length != 2 ||
            !e.key.split('/').every(kSyncIdPattern.hasMatch) ||
            e.value < 0 ||
            e.value > 0x1fffffffffffff) {
          throw const FormatException('invalid recovery floor');
        }
        merged[e.key] = max(merged[e.key] ?? 0, e.value);
      }
      final stamp = old.hlc == null
          ? hlc
          : hlc == null || old.hlc! > hlc
          ? old.hlc
          : hlc;
      await _writeEncrypted(
        'family.recoveryFloors',
        utf8.encode('gift-huddle-recovery-floors-v1'),
        utf8.encode(
          jsonEncode({'v': 1, 'slots': merged, 'hlc': stamp?.pack()}),
        ),
      );
    }),
  );

  Future<bool> remoteSyncEnabled() => _inGeneration(
    () async => await _secrets.read('family.remoteSyncEnabled') == 'true',
  );

  /// Capture before load(), which can finish a person-change journal.
  Future<({bool person, bool protection, bool resources})>
  recoveryBlockers() => _inGeneration(() async {
    final pendingRetained = await _pendingRetained();
    var resources =
        (await readOrphans()).isNotEmpty || pendingRetained.isNotEmpty;
    if (pendingRetained.isEmpty) {
      final retained = await readRetainedCommons();
      resources |=
          retained is List && retained.any((r) => r is Map && r['b'] == true);
    }
    for (final person in await _scopePeople()) {
      // Keep the await out of bool |=: dart2wasm emits an invalid stack type.
      final overflow = await readOverflow(person);
      resources = resources | overflow.isNotEmpty;
    }
    return (
      person:
          await _secrets.read(_selfPersonChangeKey) != null ||
          await _secrets.read('family.recoveryPersonInvalidation') == 'true',
      protection: await _files.read('family.protection') != null,
      resources: resources,
    );
  });

  Future<void> configureRecovery() =>
      _inGeneration(() => _secrets.write('family.recoveryConfigured', 'true'));
  Future<String?> recoveryDirty() =>
      _inGeneration(() => _secrets.read('family.recoveryDirty'));
  Future<void> clearRecoveryDirty(String? expected) => _inGeneration(() async {
    if (await _secrets.read('family.recoveryDirty') == expected) {
      await _secrets.delete('family.recoveryDirty');
    }
  });
  Future<void> finishRecoveryPersonInvalidation() =>
      _inGeneration(() => _secrets.delete('family.recoveryPersonInvalidation'));
  Future<void> setRecoveryActivationPending(bool value) => _inGeneration(
    () => value
        ? _secrets.write('family.recoveryActivation', 'true')
        : _secrets.delete('family.recoveryActivation'),
  );
  Future<bool> recoveryActivationPending() => _inGeneration(
    () async => await _secrets.read('family.recoveryActivation') == 'true',
  );

  Future<void> prepareRecoveryCode(String entropy, {required bool rotate}) =>
      _inGeneration(
        () => _secrets.write(
          'family.recoverySetup',
          jsonEncode({'entropy': entropy, 'rotate': rotate}),
        ),
      );
  Future<Map<String, Object?>?> readRecoverySetup() => _inGeneration(() async {
    final raw = await _secrets.read('family.recoverySetup');
    return raw == null
        ? null
        : Map<String, Object?>.from(jsonDecode(raw) as Map);
  });
  Future<void> clearRecoverySetup() =>
      _inGeneration(() => _secrets.delete('family.recoverySetup'));
  Future<Object?> readRecoverySlotCache() => _inGeneration(
    () => _readEncrypted(
      'family.recoverySlotCache',
      utf8.encode('recovery-slot-cache-v1'),
    ),
  );
  Future<void> saveRecoverySlotCache(Map<String, Object?> cache) =>
      _inGeneration(
        () => _writeEncrypted(
          'family.recoverySlotCache',
          utf8.encode('recovery-slot-cache-v1'),
          utf8.encode(jsonEncode(cache)),
        ),
      );
  Future<Object?> readRecoveryBootstrap() => _inGeneration(
    () => _readEncrypted(
      'family.recoveryBootstrap',
      utf8.encode('recovery-bootstrap-v1'),
    ),
  );
  Future<void> saveRecoveryBootstrap(Map<String, Object?> upload) =>
      _inGeneration(
        () => _writeEncrypted(
          'family.recoveryBootstrap',
          utf8.encode('recovery-bootstrap-v1'),
          utf8.encode(jsonEncode(upload)),
        ),
      );

  Future<void> enableRemoteSync() => _inGeneration(() async {
    await assertWritable();
    await _secrets.write('family.remoteSyncEnabled', 'true');
  });

  Future<Map<String, String>?> pendingInviteAcknowledgement() =>
      _inGeneration(() async {
        final raw = await _secrets.read('family.pendingInviteAcknowledgement');
        return raw == null
            ? null
            : Map<String, String>.from(jsonDecode(raw) as Map);
      });

  Future<void> savePendingInviteAcknowledgement(Map<String, String>? value) =>
      _inGeneration(() async {
        if (value == null) {
          await _secrets.delete('family.pendingInviteAcknowledgement');
        } else {
          await _secrets.write(
            'family.pendingInviteAcknowledgement',
            jsonEncode(value),
          );
        }
      });

  Future<void> disableRemoteSync() => _inGeneration(() async {
    await assertWritable();
    await _secrets.delete('family.remoteSyncEnabled');
  });

  Future<bool> recoveryRemovalPending() => _inGeneration(
    () async => await _secrets.read('family.recoveryRemovalPending') == 'true',
  );

  Future<void> setRecoveryRemovalPending(bool pending) =>
      _inGeneration(() async {
        await assertWritable();
        if (pending) {
          await _secrets.write('family.recoveryRemovalPending', 'true');
        } else {
          await _secrets.delete('family.recoveryRemovalPending');
        }
      });

  Future<bool> isTransferred() => _inGeneration(() async {
    return await _secrets.read('family.transferred') == 'true';
  });

  Future<void> markTransferred() => _inGeneration(() async {
    final scoped = _secrets as GenerationSecretStore;
    final identity = await readSyncV2();
    if (identity == null) {
      throw StateError('transferred requires a v2 identity');
    }
    await scoped.root.write(
      '${await scoped.prefix()}family.transferred',
      'true',
    );
  });

  /// Call when queued work executes, while holding the family lock.
  Future<void> assertWritable() async {
    await (_secrets as GenerationSecretStore).assertWritable();
  }

  /// Guarda los comunes remotos retenidos sin fusionar (JSON opaco) y borra
  /// los bytes que se escribieron para un retenido que no ha entrado en el
  /// índice (ver [saveRetainedBytes]).
  Future<void> saveRetainedCommons(List<Object?> json) =>
      _inGeneration(() async {
        await _writeEncrypted(
          _retainedCommonsFile,
          utf8.encode('regalos-retainedcommons:v1'),
          utf8.encode(jsonEncode(json)),
        );
        await _dropOrphanBytes(_hashesOf(json));
      });

  /// Lo guardado con [saveRetainedCommons], o null. Antes borra los bytes
  /// huérfanos de un cierre entre escribirlos y apuntarlos en el índice.
  Future<Object?> readRetainedCommons() => _inGeneration(() async {
    final raw = await _readEncrypted(
      _retainedCommonsFile,
      utf8.encode('regalos-retainedcommons:v1'),
    );
    await _dropOrphanBytes(_hashesOf(raw));
    return raw;
  });

  static Set<String> _hashesOf(Object? index) => {
    if (index is List)
      for (final e in index)
        if (e is Map && e['h'] is String && e['b'] == true) e['h'] as String,
  };

  /// Los hashes cuyos bytes se están escribiendo (diario en el almacén
  /// seguro): el almacén de ficheros no se puede listar, así que un fichero
  /// de retenido solo se escribe después de apuntarlo aquí.
  Future<Set<String>> _pendingRetained() async {
    final raw = await _secrets.read(_retainedPendingKey);
    if (raw == null) return {};
    try {
      final list = jsonDecode(raw);
      if (await _generationManaged() &&
          (list is! List ||
              list.any(
                (h) => h is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(h),
              ))) {
        throw const FormatException('diario de retenidos dañado');
      }
      return {
        if (list is List)
          for (final h in list)
            if (h is String) h,
      };
    } on FormatException {
      if (await _generationManaged()) {
        throw const FamilyStoreException('diario de retenidos dañado');
      }
      return {};
    }
  }

  Future<void> _dropOrphanBytes(Set<String> indexed) async {
    final pending = await _pendingRetained();
    if (pending.isEmpty) return;
    for (final hash in pending.difference(indexed)) {
      await _files.delete(_retainedBytesFile(hash));
    }
    await _secrets.delete(_retainedPendingKey);
  }

  /// Si ya se guardó alguna vez la clave común (marca en el almacén seguro):
  /// sin ella, que falte `family.commonkeys` no es un primer arranque.
  Future<bool> commonKeysMarked() => _inGeneration(
    () async => await _secrets.read(_commonKeysMarkerKey) != null,
  );

  /// Pone la marca de [commonKeysMarked].
  Future<void> markCommonKeys() =>
      _inGeneration(() async => _secrets.write(_commonKeysMarkerKey, '1'));

  /// Borra el estado de la clave común y su marca (B7: un invitado que entra
  /// sin el corte no hereda un llavero de un intento anterior).
  Future<void> clearCommonKeys() => _inGeneration(() async {
    if (await _generationManaged() &&
        (await commonKeysMarked() ||
            await _files.read(_commonKeysFile) != null)) {
      throw const FamilyStoreException(
        'llavero referenciado por una generación',
      );
    }
    await _files.delete(_commonKeysFile);
    await _secrets.delete(_commonKeysMarkerKey);
  });

  /// Deshace lo que escribió una instalación de emparejamiento que se cortó
  /// antes del documento (B7, B2): el llavero común y su marca, el estado de
  /// la sincronización v2 y el registro. La identidad y el documento no se
  /// tocan (no llegaron a escribirse).
  Future<void> discardPairingInstall() => _inGeneration(() async {
    await clearCommonKeys();
    await _secrets.delete(_syncV2StateKey);
    await _files.delete(_registryFile);
  });

  /// La marca irreversible del formato mínimo del común de esta familia
  /// (ADR 0005, B4), en el almacén seguro y fuera del documento, del estado
  /// de la sincronización y de las copias: 1 si no hay. Una marca que no se
  /// entiende cuenta como la más alta conocida (nunca se rebaja por un
  /// fallo de lectura).
  Future<int> readCommonFormatFloor() => _inGeneration(() async {
    final raw = await _secrets.read(_commonFormatFloorKey);
    if (raw == null) return 1;
    final n = int.tryParse(raw);
    return n == null || n < 2 ? kCommonFormatFloorUnknown : n;
  });

  /// Sube la marca de [readCommonFormatFloor] a [format]; nunca la baja.
  Future<void> raiseCommonFormatFloor(int format) => _inGeneration(() async {
    if (format <= await readCommonFormatFloor()) return;
    await _secrets.write(_commonFormatFloorKey, '$format');
  });

  static String _retainedBytesFile(String hash) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      throw const FamilyStoreException('común retenido no válido');
    }
    return 'family.retained.$hash';
  }

  static List<int> _retainedAad(String hash) =>
      utf8.encode('regalos-retainedcommon:v1:$hash');

  /// Guarda los bytes de un común retenido en su propio fichero cifrado.
  /// Primero lo apunta en el diario: si se cierra antes de que el índice lo
  /// recoja, la próxima lectura o escritura del índice lo borra.
  Future<void> saveRetainedBytes(String hash, Uint8List bytes) =>
      _inGeneration(() async {
        final file = _retainedBytesFile(hash);
        final pending = await _pendingRetained();
        if (pending.add(hash)) {
          await _secrets.write(
            _retainedPendingKey,
            jsonEncode(pending.toList()..sort()),
          );
        }
        await _writeEncrypted(file, _retainedAad(hash), [
          ...utf8.encode(jsonEncode(encodeBase64Url(bytes))),
        ]);
      });

  /// Los bytes de un común retenido, o null.
  Future<Uint8List?> readRetainedBytes(String hash) => _inGeneration(() async {
    final raw = await _readEncrypted(
      _retainedBytesFile(hash),
      _retainedAad(hash),
    );
    if (raw == null) return null;
    if (raw is! String) {
      throw const FamilyStoreException('común retenido dañado');
    }
    return decodeBase64Url(raw);
  });

  /// Borra los bytes de un común retenido.
  Future<void> deleteRetainedBytes(String hash) =>
      _inGeneration(() async => _files.delete(_retainedBytesFile(hash)));

  /// Los hashes de todos los ficheros de retenidos: los del índice y los del
  /// diario (huérfanos de un cierre a medias).
  Future<Set<String>> _retainedHashes() async {
    final all = await _pendingRetained();
    try {
      all.addAll(
        _hashesOf(
          await _readEncrypted(
            _retainedCommonsFile,
            utf8.encode('regalos-retainedcommons:v1'),
          ),
        ),
      );
    } on FamilyStoreException {
      // Sin la clave local, solo los del diario.
    }
    return all;
  }

  /// Si hay una familia guardada en la generación activa. Solo lee: no
  /// termina cambios pendientes ni reanuda nada (a diferencia de [load]).
  Future<bool> hasFamily() =>
      _inGeneration(() async => await _secrets.read(_identityKey) != null);

  /// La persona de «Yo» guardada, o null (también sin familia).
  Future<String?> readSelfRecipient() => _inGeneration(() async {
    final raw = await _secrets.read(_identityKey);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map;
      return FamilyIdentity.fromJson(Map<String, Object?>.from(json))
          .selfRecipientId;
    } catch (_) {
      throw const FamilyStoreException('identidad dañada');
    }
  });

  /// Guarda la persona de «Yo» (null la quita) en la identidad guardada.
  ///
  /// Antes quita del llavero las claves de sorpresa de esa persona y borra la
  /// copia local de su ámbito: el móvil de alguien nunca guarda las de sus
  /// propias sorpresas (revisión de seguridad, M7 y requisito 4). Quien llama
  /// debe además soltar lo que tenga en memoria y publicar el cambio en el
  /// registro de móviles (`changePerson`), que exige la aprobación de otro
  /// móvil y abre una época. Lanza [FamilyStoreException] si todavía no hay
  /// familia.
  Future<void> saveSelfRecipient(String? recipientId) =>
      _inGeneration(() async {
        final raw = await _secrets.read(_identityKey);
        if (raw == null) {
          throw const FamilyStoreException('no hay familia');
        }
        final FamilyIdentity identity;
        try {
          identity = FamilyIdentity.fromJson(
            Map<String, Object?>.from(jsonDecode(raw) as Map),
          );
        } catch (_) {
          throw const FamilyStoreException('identidad dañada');
        }
        // El almacén de claves recuerda la persona de «Yo»: desde ahora no
        // guarda claves suyas, tampoco de un llavero leído antes (hallazgo 11).
        await _deviceKeys.purgePerson(recipientId);
        if (recipientId != null) await deleteScope(recipientId);
        await saveIdentity(identity.withSelfRecipient(recipientId));
      });

  /// Intención en el almacén seguro, antes de purgar ni cambiar identidad o
  /// registro. El controlador mantiene el cerrojo v2 durante todo el cambio.
  Future<void> prepareSelfPersonChange({
    required String? personId,
    required DeviceRegistry registry,
    required List<Map<String, Object?>> orphans,
  }) => _inGeneration(() async {
    if (await _secrets.read('family.recoveryConfigured') == 'true') {
      await _secrets.write('family.recoveryPersonInvalidation', 'true');
    }
    final identity = await readSyncV2();
    if (identity != null) {
      final scoped = _secrets as GenerationSecretStore;
      final workspace = GenerationSecretStore.pinned(
        scoped.root,
        'recovery.read.${identity.syncId}.',
        recoveryStaging: true,
      );
      await FamilyStore(
        secrets: workspace,
        files: GenerationFileStore(
          (_files as GenerationFileStore).root,
          workspace,
        ),
        deviceKeys: DeviceKeysStore(workspace),
      ).clearRecoveryWorkspace();
    }
    await _secrets.write(
      _selfPersonChangeKey,
      jsonEncode({
        'scope': await orphanScope(),
        'person': personId,
        'registry': registry.toJson(),
        'orphans': orphans,
      }),
    );
  });

  /// Recuperación idempotente al arrancar, antes de exponer la familia.
  /// Orden: intención → purgar claves/ámbito y guardar identidad local →
  /// recordar huérfanos → registro → borrar intención. Un cierre nunca deja
  /// la ficha nueva junto a claves de sus propias sorpresas. La exclusión
  /// persistente del llavero impide reintroducirlas desde una copia anterior.
  /// Devuelve false si no había intención, para no invalidar vistas en carga
  /// durante una vuelta ordinaria sin recuperación.
  Future<bool> finishSelfPersonChange() => _inGeneration(() async {
    final raw = await _secrets.read(_selfPersonChangeKey);
    if (raw == null) return false;
    final pending = jsonDecode(raw) as Map;
    final scope = await orphanScope();
    if (scope == null || pending['scope'] != scope) {
      await _secrets.delete(_selfPersonChangeKey);
      return true;
    }
    final identity = (await readSyncV2())!;
    final keys = await _deviceKeys.read();
    if (keys == null) {
      throw const FamilyStoreException('faltan claves del móvil');
    }
    final anchor = RegistryAnchor(
      deviceId: identity.deviceId,
      signingKey: keys.publicKeys.signing,
    );
    final operation = await DeviceRegistry.fromJsonVerified(
      pending['registry'],
      anchor: anchor,
    );
    await saveSelfRecipient(pending['person'] as String?);
    final remembered = {
      for (final o in await readOrphans()) o['d']: o,
      for (final o in pending['orphans'] as List)
        (o as Map)['d']: Map<String, Object?>.from(o),
    };
    await saveOrphans(remembered.values.toList());
    final registry = await readRegistry(anchor: anchor);
    await saveRegistry(
      registry == null
          ? operation
          : await registry.merge(operation, anchor: anchor),
    );
    await _secrets.delete(_selfPersonChangeKey);
    return true;
  });

  /// La identidad v2 de este móvil (ADR 0004), o null si sigue en v1. Una
  /// identidad guardada que no se entiende es un error: nunca se vuelve a v1
  /// en silencio.
  Future<SyncIdentityV2?> readSyncV2() => _inGeneration(() async {
    final raw = await _secrets.read(_syncV2Key);
    if (raw == null) return null;
    try {
      return SyncIdentityV2.fromJson(jsonDecode(raw));
    } on FormatException {
      throw const FamilyStoreException('identidad v2 dañada');
    }
  });

  /// Guarda la identidad v2.
  Future<void> saveSyncV2(SyncIdentityV2 identity) => _inGeneration(() async {
    final scoped = _secrets as GenerationSecretStore;
    final directory = await GenerationDirectory.read(scoped.root);
    if (directory != null && !scoped.recoveryStaging) {
      final entry = directory.entries[identity.syncId];
      if (entry == null ||
          identity.listId != entry.listId ||
          await scoped.prefix() !=
              (directory.storagePrefixes[identity.syncId] ??
                  (entry.legacy ? '' : 'generation.${identity.syncId}.'))) {
        throw const FamilyStoreException('identidad de otra generación');
      }
    }
    await _secrets.write(_syncV2Key, jsonEncode(identity.toJson()));
  });

  /// Lo que recuerda la sincronización v2 entre vueltas (JSON opaco para
  /// el almacén), o null.
  Future<Object?> readSyncV2State() => _inGeneration(() async {
    final raw = await _secrets.read(_syncV2StateKey);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      if (await _generationManaged()) {
        throw const FamilyStoreException('estado de generación dañado');
      }
      return null;
    }
  });

  /// Guarda lo que recuerda la sincronización v2.
  Future<void> saveSyncV2State(Map<String, Object?> json) => _inGeneration(
    () async => _secrets.write(_syncV2StateKey, jsonEncode(json)),
  );

  /// A qué lista y generación v2 pertenecen los móviles sueltos guardados:
  /// `listId/syncId` de la identidad v2 de ahora, o null si no hay. Salir de
  /// la familia y volver a crearla deja el mismo `listId` pero otro `syncId`.
  Future<String?> orphanScope() => _inGeneration(() async {
    final id = await readSyncV2();
    return id == null ? null : '${id.listId}/${id.syncId}';
  });

  /// Los móviles sueltos tras quitar otro, pendientes de confirmar uno a uno
  /// (cada uno con su id de móvil y la ficha que se enseñó), cifrados en el
  /// almacén seguro. Solo valen para la lista y la generación v2 actuales: si
  /// no hay identidad v2 o es otra, se olvidan.
  Future<List<Map<String, Object?>>> readOrphans() => _inGeneration(() async {
    final raw = await _secrets.read(_orphansKey);
    if (raw == null) return const [];
    try {
      final json = jsonDecode(raw);
      final scope = await orphanScope();
      if (json is Map && scope != null && json['l'] == scope) {
        final items = json['o'];
        if (items is List) {
          if (await _generationManaged() && items.any((item) => item is! Map)) {
            throw const FormatException('móviles pendientes dañados');
          }
          return [
            for (final item in items)
              if (item is Map) Map<String, Object?>.from(item),
          ];
        }
      }
    } on Object {
      // Ilegible o de otra lista: se olvida.
    }
    if (await _generationManaged()) {
      throw const FamilyStoreException(
        'móviles pendientes de otra generación o dañados',
      );
    }
    await _secrets.delete(_orphansKey);
    return const [];
  });

  /// Guarda (o con una lista vacía borra) los móviles sueltos pendientes.
  Future<void> saveOrphans(List<Map<String, Object?>> orphans) =>
      _inGeneration(() async {
        final scope = await orphanScope();
        if (orphans.isEmpty || scope == null) {
          await _secrets.delete(_orphansKey);
          return;
        }
        await _secrets.write(
          _orphansKey,
          jsonEncode(<String, Object?>{'l': scope, 'o': orphans}),
        );
      });

  /// La clave y la lista de v1 que quedan tras migrar, mientras la copia v1
  /// del servidor no se haya borrado (JSON opaco), o null.
  Future<Object?> readLegacyV1() => _inGeneration(() async {
    final raw = await _secrets.read(_legacyV1Key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      if (await _generationManaged()) {
        throw const FamilyStoreException('archivo v1 dañado');
      }
      return null;
    }
  });

  /// Guarda (o con null borra) lo que queda de v1.
  Future<void> saveLegacyV1(Map<String, Object?>? json) => _inGeneration(
    () async => json == null
        ? _secrets.delete(_legacyV1Key)
        : _secrets.write(_legacyV1Key, jsonEncode(json)),
  );

  /// La clave v1 de un móvil que migró sin estar emparejado en v1 (JSON
  /// opaco `{"l": lista, "k": clave}`), o null. Solo sirve para que sus
  /// invitaciones prueben la clave v1 (hallazgo 6): no hay copia v1 que
  /// fusionar ni que retirar, así que no va en [readLegacyV1].
  Future<Object?> readV1ProofKey() => _inGeneration(() async {
    final raw = await _secrets.read(_v1ProofKey);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      if (await _generationManaged()) {
        throw const FamilyStoreException('clave histórica dañada');
      }
      return null;
    }
  });

  /// Guarda (o con null borra) la clave v1 para las pruebas.
  Future<void> saveV1ProofKey(Map<String, Object?>? json) => _inGeneration(
    () async => json == null
        ? _secrets.delete(_v1ProofKey)
        : _secrets.write(_v1ProofKey, jsonEncode(json)),
  );

  /// La generación v2 a medio instalar (clave de la familia y `syncId` que
  /// se van a usar, JSON opaco), o null. Se escribe antes de tocar el
  /// documento o la clave y se borra al guardar la identidad v2: una
  /// migración o una renovación que se corta se termina con lo mismo, nunca
  /// con la clave que había (hallazgo 7).
  Future<Object?> readPendingV2() => _inGeneration(() async {
    final raw = await _secrets.read(_pendingV2Key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      if (await _generationManaged()) {
        throw const FamilyStoreException('instalación pendiente dañada');
      }
      return null;
    }
  });

  /// Guarda (o con null borra) la generación v2 a medio instalar.
  Future<void> savePendingV2(Map<String, Object?>? json) =>
      _inGeneration(() async {
        if (json != null && await _generationManaged()) {
          if (json['reset'] == true ||
              (json['sid'] != null &&
                  json['sid'] != (await readSyncV2())?.syncId)) {
            throw const FamilyStoreException(
              'usa el diario para cambiar de generación',
            );
          }
        }
        if (json == null) {
          await _secrets.delete(_pendingV2Key);
        } else {
          await _secrets.write(_pendingV2Key, jsonEncode(json));
        }
      });

  /// Guarda solo la identidad.
  Future<void> saveIdentity(FamilyIdentity identity) => _inGeneration(
    () async => _secrets.write(_identityKey, jsonEncode(identity.toJson())),
  );

  /// Guarda una familia entera. La identidad va la última: es la que hace
  /// que la familia exista.
  Future<void> saveFamily(StoredFamily family) => _inGeneration(() async {
    if (await _generationManaged()) {
      final rawIdentity = await _secrets.read(_identityKey);
      final key = await _secrets.read(_familyKeyKey);
      final previous = rawIdentity == null
          ? null
          : FamilyIdentity.fromJson(
              Map<String, Object?>.from(jsonDecode(rawIdentity) as Map),
            );
      if ((key != null && key != family.key.toBase64Url()) ||
          (previous != null &&
              (previous.listId != family.identity.listId ||
                  previous.node != family.identity.node))) {
        throw const FamilyStoreException(
          'instala la identidad en otra generación',
        );
      }
    }
    await saveDoc(family.doc);
    await _secrets.write(_familyKeyKey, family.key.toBase64Url());
    await saveIdentity(family.identity);
  });

  /// Borra todo lo guardado, incluida la clave local y las claves del
  /// móvil y de sorpresas (son de esta familia). Primero los secretos y la
  /// identidad al final: si se corta a medias no quedan secretos huérfanos.
  /// Rechaza generaciones conservadas: «Borrar todo» confirmado debe usar
  /// GenerationStore.eraseAllConfirmed antes del reset del controlador.
  Future<void> clear() => _inGeneration(() async {
    if (await _generationManaged()) {
      throw const FamilyStoreException(
        'generación conservada para recuperación',
      );
    }
    await _files.delete('family.protection');
    // Los bytes de los comunes retenidos, antes de perder la clave local que
    // abre su índice.
    for (final hash in await _retainedHashes()) {
      await _files.delete(_retainedBytesFile(hash));
    }
    await _secrets.delete(_retainedPendingKey);
    for (final key in [
      'family.remoteSyncEnabled',
      'family.recoveryRemovalPending',
      'family.pendingInviteAcknowledgement',
      'family.recoveryConfigured',
      'family.recoveryDirty',
      'family.recoverySetup',
      'family.recoveryActivation',
      'family.recoveryPersonInvalidation',
    ]) {
      await _secrets.delete(key);
    }
    await _files.delete('family.recoveryBootstrap');
    await _files.delete('family.recoverySlotCache');
    await _files.delete('family.recoveryFloors');
    await _deviceKeys.clear();
    await _secrets.delete(_familyKeyKey);
    await _secrets.delete(_legacyV1Key);
    await _secrets.delete(_v1ProofKey);
    await _secrets.delete(_pendingV2Key);
    await _secrets.delete(_orphansKey);
    await _secrets.delete(_syncV2StateKey);
    await _secrets.delete(_selfPersonChangeKey);
    await _secrets.delete(_commonKeysMarkerKey);
    await _secrets.delete(_commonFormatFloorKey);
    await _secrets.delete(_syncV2Key);
    await _secrets.delete(_localKeyKey);
    for (final person in await _scopePeople()) {
      await deleteScope(person);
    }
    await _secrets.delete(_scopePeopleKey);
    await _files.delete(_slotsFile);
    await _files.delete(_commonKeysFile);
    await _files.delete(_retainedCommonsFile);
    await _files.delete(_registryFile);
    await _files.delete(_docFile);
    await _secrets.delete(_identityKey);
  });

  /// Inventory before a confirmed full wipe. Read encrypted indexes before
  /// deleting anything, so an interrupted wipe can replay the saved inventory
  /// even after the platform secure store has been swept.
  Future<({Set<String> secrets, Set<String> files})>
  confirmedEraseInventory() => _inGeneration(() async {
    final prefix = await (_secrets as GenerationSecretStore).prefix();
    final people = await _scopePeople();
    final hashes = await _retainedHashes();
    return (
      secrets: {
        for (final key in [
          _identityKey,
          _familyKeyKey,
          _localKeyKey,
          _scopePeopleKey,
          _syncV2Key,
          _syncV2StateKey,
          _legacyV1Key,
          _v1ProofKey,
          _pendingV2Key,
          _orphansKey,
          _selfPersonChangeKey,
          _commonKeysMarkerKey,
          _commonFormatFloorKey,
          _retainedPendingKey,
          'family.remoteSyncEnabled',
          'family.recoveryRemovalPending',
          'family.pendingInviteAcknowledgement',
          'family.recoveryConfigured',
          'family.recoveryDirty',
          'family.recoverySetup',
          'family.recoveryActivation',
          'family.recoveryPersonInvalidation',
          'family.transferred',
          kDeviceKeysSecret,
          kSurpriseKeysSecret,
        ])
          '$prefix$key',
      },
      files: {
        for (final name in [
          _docFile,
          _registryFile,
          _slotsFile,
          _commonKeysFile,
          _retainedCommonsFile,
          'family.recoveryFloors',
          'family.recoveryBootstrap',
          'family.recoverySlotCache',
          'family.protection',
          for (final person in people) ...[
            _scopeFile('scope', person),
            _scopeFile('overflow', person),
          ],
          for (final hash in hashes) _retainedBytesFile(hash),
        ])
          '$prefix$name',
      },
    );
  });

  Future<bool> _generationManaged() =>
      (_secrets as GenerationSecretStore).managed;

  /// Erase an isolated reader/staging namespace, never an installed family.
  /// Root writes bypass gates intentionally: cleanup must work after a claim.
  Future<void> clearRecoveryWorkspace() => _inGeneration(() async {
    final scoped = _secrets as GenerationSecretStore;
    if (!scoped.recoveryStaging) throw StateError('not recovery staging');
    final prefix = await scoped.prefix();
    final directory = await GenerationDirectory.read(scoped.root);
    if (directory != null &&
        directory.entries.keys.any(
          (id) =>
              (directory.storagePrefixes[id] ??
                  (directory.entries[id]!.legacy ? '' : 'generation.$id.')) ==
              prefix,
        )) {
      return;
    }
    final inventory = await confirmedEraseInventory();
    final rootFiles = (_files as GenerationFileStore).root;
    for (final key in inventory.secrets) {
      await scoped.root.delete(key);
    }
    final files = {...inventory.files};
    if (rootFiles is ListableFileStore) {
      files.addAll(
        (await rootFiles.listNames()).where((n) => n.startsWith(prefix)),
      );
    }
    for (final file in files) {
      await rootFiles.delete(file);
    }
  });

  Future<bool> recoveryPersonInvalidationPending() => _inGeneration(
    () async =>
        await _secrets.read('family.recoveryPersonInvalidation') != null,
  );

  Future<String> _localKey() async {
    // An existing key is immutable within the pinned generation. Only its
    // creation needs the shared queue, with a second read under the lock.
    final existing = await _secrets.read(_localKeyKey);
    if (existing != null) return existing;
    return GenerationStorageQueue.on(_secrets, 'familyLocalKey').run(() async {
      final existing = await _secrets.read(_localKeyKey);
      if (existing != null) {
        return existing;
      }
      if (await _generationManaged()) {
        for (final file in [
          _docFile,
          _registryFile,
          _slotsFile,
          _commonKeysFile,
          _retainedCommonsFile,
          'family.protection',
          for (final person in await _scopePeople()) ...[
            _scopeFile('scope', person),
            _scopeFile('overflow', person),
          ],
        ]) {
          if (await _files.read(file) != null) {
            throw const FamilyStoreException(
              'falta la clave local de la generación',
            );
          }
        }
      }
      final random = Random.secure();
      final fresh = encodeBase64Url(
        List<int>.generate(32, (_) => random.nextInt(256)),
      );
      await _secrets.write(_localKeyKey, fresh);
      return fresh;
    });
  }

  Future<Object?> _decrypt(
    Uint8List bytes,
    String localKey,
    List<int> aad,
  ) async {
    if (bytes.length < _magic.length + _nonceLength + _macLength) {
      throw const FamilyStoreException('documento truncado');
    }
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) {
        throw const FamilyStoreException('documento no reconocido');
      }
    }
    final nonceEnd = _magic.length + _nonceLength;
    final macStart = bytes.length - _macLength;
    try {
      final plain = await _aes.decrypt(
        SecretBox(
          Uint8List.sublistView(bytes, nonceEnd, macStart),
          nonce: Uint8List.sublistView(bytes, _magic.length, nonceEnd),
          mac: Mac(Uint8List.sublistView(bytes, macStart)),
        ),
        secretKey: SecretKey(decodeBase64Url(localKey)),
        aad: aad,
      );
      return jsonDecode(utf8.decode(plain));
    } on SecretBoxAuthenticationError {
      throw const FamilyStoreException(
        'no se puede descifrar el documento (clave local perdida)',
      );
    } on FormatException catch (e) {
      throw FamilyStoreException('documento dañado: ${e.message}');
    }
  }
}

/// El guardado de la familia, sobre los almacenes de la app.
final familyStoreProvider = Provider<FamilyStore>(
  (ref) => FamilyStore(
    secrets: ref.watch(secretStoreProvider),
    files: ref.watch(fileStoreProvider),
    deviceKeys: ref.watch(deviceKeysStoreProvider),
  ),
);
