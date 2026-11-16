// Móviles v2 en memoria para probar el ciclo (`SyncV2Engine`) y el
// emparejamiento contra el Worker falso, sin Flutter.
import 'dart:convert';
import 'dart:typed_data';

import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/device_keys.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/pairing_v2.dart';
import 'package:regalos/core/sync/protected_doc.dart';
import 'package:regalos/features/sync/application/common_v2.dart';
import 'package:regalos/features/sync/application/sync_v2_engine.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';

/// Lista de las pruebas v2.
const kV2List = 'list-v2';

/// `syncId` de las pruebas v2.
const kV2Sync = 'QUJDREVGR0hJSktMTU5PUA';

/// Un móvil v2 en memoria.
class MemoryV2Phone implements SyncV2Local {
  MemoryV2Phone._(
    this.identity,
    this.keys,
    this.node,
    this.familyKey,
    this.doc,
    this.reg,
    this.clock,
    this.person,
  );

  /// Crea un móvil con semillas fijas.
  static Future<MemoryV2Phone> create(
    String deviceId,
    String? person,
    int seed, {
    required FamilyKey familyKey,
    FamilyDoc? doc,
    String syncId = kV2Sync,
    bool migrated = false,
  }) async {
    final keys = await DeviceKeys.fromSeedsForTesting(
      agreementSeed: List<int>.filled(32, seed),
      signingSeed: List<int>.filled(32, seed + 100),
      serviceCredential: List<int>.filled(32, seed + 200),
    );
    final record = await DeviceRecord.create(
      keys: keys,
      listId: kV2List,
      deviceId: deviceId,
      personId: person,
    );
    return MemoryV2Phone._(
      SyncIdentityV2(listId: kV2List, deviceId: deviceId, syncId: syncId),
      keys,
      'node-$deviceId',
      familyKey,
      // Con [migrated], como tras `migrateToV2`: el documento lleva la marca
      // del protocolo (los demás la reciben al fusionar).
      migrated
          ? (doc ?? FamilyDoc.empty(kV2List)).set(
              HlcClock(node: 'node-$deviceId'),
              Collections.meta,
              kProtocolRecordId,
              {kProtocolVersionField: kSyncProtocolV2},
            )
          : doc ?? FamilyDoc.empty(kV2List),
      await DeviceRegistry.empty(kV2List).withRecord(record),
      HlcClock(node: 'node-$deviceId'),
      person,
    );
  }

  @override
  SyncIdentityV2 identity;

  @override
  final DeviceKeys keys;

  @override
  final String node;

  @override
  FamilyKey familyKey;

  /// El documento común.
  FamilyDoc doc;

  /// El registro.
  DeviceRegistry reg;

  /// El reloj del común.
  final HlcClock clock;

  /// Persona de «Yo».
  final String? person;

  /// Slots guardados.
  SlotSet slotSet = SlotSet.empty;

  /// Llavero.
  SurpriseKeyring keyring = SurpriseKeyring.empty;

  /// Ámbitos secretos.
  final Map<String, FamilyDoc> scopes = {};

  /// Estado de la sincronización.
  V2SyncState state = const V2SyncState();

  /// Cuántas veces se ha fusionado un común que llega.
  int merges = 0;

  /// Las credenciales de este móvil.
  V2Auth get auth => V2Auth(
    syncId: identity.syncId,
    deviceId: identity.deviceId,
    credential: keys.serviceCredential,
  );

  /// Su ficha actual.
  DeviceRecord get record =>
      reg.records.firstWhere((r) => r.deviceId == identity.deviceId);

  /// El registro visto desde aquí.
  Future<RegistryView> view() => reg.viewFor(
    me: identity.deviceId,
    mySigningKey: keys.publicKeys.signing,
    livePeople: livePeopleOf(doc),
  );

  /// Si esta versión puede empezar el corte al formato 2 (B4).
  bool commonV2Ready = false;

  /// Un ciclo sobre [transport].
  SyncV2Engine engine(SyncV2Transport transport) => SyncV2Engine(
    transport: transport,
    local: this,
    commonV2Ready: commonV2Ready,
  );

  /// Escribe una persona.
  void addPerson(String id, String name) {
    doc = doc.set(clock, Collections.recipients, id, {
      'name': name,
      'colorIndex': 0,
      'archived': false,
    });
  }

  /// Escribe un regalo público.
  void addGift(String id, String recipient, String title) {
    doc = doc.set(clock, Collections.gifts, id, {
      'recipientId': recipient,
      'title': title,
      'status': 'idea',
      'year': 2026,
    });
  }

  /// Los títulos de los regalos vivos.
  Set<String> get giftTitles => {
    for (final r
        in doc.collections[Collections.gifts]?.values ?? const <SyncRecord>[])
      if (!r.isDeleted) r['title'] as String,
  };

  @override
  Future<FamilyDoc> common() async => doc;

  @override
  Future<void> mergeCommon(FamilyDoc remote, {required String fromNode}) async {
    final max = remote.maxStamp;
    if (max != null) clock.receive(max);
    // Como `FamilyController.mergeRemote`: la marca v2 es monótona.
    doc = keepProtocolV2(before: doc, merged: doc.merge(remote), clock: clock);
    merges++;
  }

  @override
  Future<DeviceRegistry> registry() async => reg;

  @override
  Future<void> saveRegistry(DeviceRegistry registry) async => reg = registry;

  @override
  Future<SlotSet> slots() async => slotSet;

  @override
  Future<void> saveSlots(SlotSet slots) async => slotSet = slots;

  @override
  Future<SurpriseKeyring> updateKeyring(
    SurpriseKeyring Function(SurpriseKeyring current) update,
  ) async {
    var next = update(keyring);
    if (person != null) next = next.without(person!);
    return keyring = next;
  }

  @override
  Future<FamilyDoc?> readScope(String personId) async => scopes[personId];

  @override
  Future<void> saveScope(String personId, FamilyDoc scope) async =>
      scopes[personId] = scope;

  @override
  Future<void> deleteScope(String personId) async => scopes.remove(personId);

  @override
  Future<V2SyncState> readState() async => state;

  /// Si es verdadero, guardar el estado falla (para probar cortes a medias).
  bool failSaveState = false;

  /// Si devuelve verdadero, ese guardado del estado falla (un cierre justo
  /// en ese punto).
  bool Function(V2SyncState next)? failSaveStateIf;

  @override
  Future<void> saveState(V2SyncState state) async {
    if (failSaveState || (failSaveStateIf?.call(state) ?? false)) {
      throw StateError('no se puede guardar el estado');
    }
    this.state = state;
  }

  /// Lo guardado de la clave común, como en el disco (texto JSON): cada
  /// lectura lo vuelve a leer, como tras reiniciar.
  String? commonKeysJson;

  /// Los comunes retenidos, como en el disco.
  String? retainedJson;

  /// Si es verdadero, guardar la clave común falla (cierre a medias).
  bool failSaveCommonKeys = false;

  /// Si no es null, falla el guardado número [failCommonKeySaveAt] de la
  /// clave común (contando desde que se creó el móvil): un cierre en ese
  /// punto exacto.
  int? failCommonKeySaveAt;

  /// Cuántas veces se ha guardado la clave común.
  int commonKeySaves = 0;

  /// La marca del almacén seguro de que ya se guardó la clave común.
  bool commonKeysMarker = false;

  /// Los bytes de cada común retenido, como ficheros aparte.
  final Map<String, Uint8List> retainedFiles = {};

  /// Si es verdadero, guardar el índice de retenidos falla.
  bool failSaveRetained = false;

  /// La clave común guardada (vacía si no hay).
  CommonKeyState get commonKeys => commonKeysJson == null
      ? CommonKeyState()
      : CommonKeyState.fromJson(jsonDecode(commonKeysJson!));

  /// Enciende el interruptor de la clave común por época, con la marca
  /// irreversible (B4: el interruptor ya no va sin ella).
  void enableCommonV2() {
    state = state.copyWith(commonFormatV2: true);
    formatFloor = 2;
  }

  @override
  Future<CommonKeyState?> readCommonKeys() async =>
      commonKeysJson == null ? null : commonKeys;

  @override
  Future<void> saveCommonKeys(CommonKeyState state) async {
    if (failSaveCommonKeys || commonKeySaves + 1 == failCommonKeySaveAt) {
      throw StateError('no se puede guardar la clave común');
    }
    commonKeySaves++;
    commonKeysJson = jsonEncode(state.toJson());
  }

  @override
  Future<bool> commonKeysMarked() async => commonKeysMarker;

  @override
  Future<void> markCommonKeys() async => commonKeysMarker = true;

  /// La marca irreversible del formato mínimo (B4), como en el almacén
  /// seguro.
  int formatFloor = 1;

  /// Si es verdadero, subir la marca falla (cierre justo antes).
  bool failRaiseFloor = false;

  @override
  Future<int> commonFormatFloor() async => formatFloor;

  @override
  Future<void> raiseCommonFormatFloor(int format) async {
    if (failRaiseFloor) throw StateError('no se puede guardar la marca');
    if (format > formatFloor) formatFloor = format;
  }

  @override
  Future<List<RetainedCommon>> readRetainedCommons() async => [
    if (retainedJson != null)
      for (final item in jsonDecode(retainedJson!) as List)
        RetainedCommon.fromJson(item),
  ];

  @override
  Future<void> saveRetainedCommons(List<RetainedCommon> retained) async {
    if (failSaveRetained) throw StateError('no se puede guardar el índice');
    retainedJson = jsonEncode([for (final r in retained) r.toJson()]);
  }

  @override
  Future<Uint8List?> readRetainedBytes(String hash) async =>
      retainedFiles[hash];

  @override
  Future<void> saveRetainedBytes(String hash, Uint8List bytes) async =>
      retainedFiles[hash] = Uint8List.fromList(bytes);

  @override
  Future<void> deleteRetainedBytes(String hash) async =>
      retainedFiles.remove(hash);
}

/// Avala entre sí las fichas de [phones] y deja el mismo registro en todos.
Future<void> vouchAll(List<MemoryV2Phone> phones) async {
  var registry = DeviceRegistry.empty(kV2List);
  for (final p in phones) {
    registry = await registry.merge(p.reg);
  }
  for (final by in phones) {
    for (final other in phones) {
      if (by == other) continue;
      registry = await registry.withVouch(
        await Vouch.create(
          keys: by.keys,
          voucher: by.record,
          record: other.record,
        ),
      );
    }
  }
  for (final p in phones) {
    p.reg = registry;
  }
}
