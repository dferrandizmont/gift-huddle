// Móviles que hay que revisar a mano (ADR 0004, «Interfaz que necesita la fase
// 3»), y las acciones de la interfaz sobre ellos: aprobar uno, quitar uno y ver
// antes qué pasaría. La bandeja «Revisar móviles» y la hoja de cada móvil leen
// de aquí. Nada se aprueba en bloque: cada acción es de un solo móvil.
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/device_registry.dart';
import '../../family/data/family_store.dart';
import 'app_sync_v2_local.dart';
import 'family_device_actions.dart'
    show DeviceRemovalChangedException, kRecordChangedMessage;
import 'family_devices.dart' show FamilyDeviceRow;
import 'sync_controller.dart';
import 'v2_health_provider.dart';

export 'family_device_actions.dart' show DeviceRemovalChangedException;

/// Por qué hay que mirar un móvil antes de fiarse de él.
enum DeviceReviewReason {
  /// Recién llegado: su ficha aún no la ha aprobado ningún móvil activo.
  newcomer,

  /// Ha cambiado de persona y espera aprobación. Al aprobarlo podrá avalar a
  /// otros móviles desde ese momento.
  personChanged,

  /// Dejó de estar enlazado a este móvil al quitar otro (o al cambiar de
  /// persona): hay que confirmar de nuevo de quién es.
  orphan,

  /// Cuelga de un móvil revocado y ha confirmado a este: se confirma de
  /// vuelta.
  detached,

  /// Escritor congelado: mientras espere, no se compactan los borrados.
  frozen,
}

/// Un móvil por revisar.
class DeviceReviewItem {
  /// Crea el elemento.
  const DeviceReviewItem({
    required this.deviceId,
    required this.reason,
    this.personId,
    this.recordDigest,
    this.active = false,
    this.recordChanged = false,
    this.becauseOf,
  });

  /// Id del móvil.
  final String deviceId;

  /// Persona de su ficha, o null.
  final String? personId;

  /// Por qué se revisa.
  final DeviceReviewReason reason;

  /// La ficha que se enseña, para aprobar un huérfano que ya no sale en la
  /// vista.
  final String? recordDigest;

  /// Si ya es un móvil activo de la familia (sale en la lista de móviles).
  final bool active;

  /// Si su ficha no es la primera (cambió de persona alguna vez): aprobarla
  /// le da derecho a avalar a otros móviles, sea cual sea el motivo de la
  /// revisión.
  final bool recordChanged;

  /// Mientras la revocación de este móvil no esté guardada, el huérfano está
  /// solo «preparado»: no se enseña hasta que [becauseOf] (el móvil que se
  /// quita) esté revocado o con su revocación pendiente guardada.
  final String? becauseOf;

  /// Si aprobarlo le permite avalar a otros móviles (ficha con cambios).
  bool get canVouch =>
      recordChanged || reason == DeviceReviewReason.personChanged;

  /// Una copia ya definitiva (sin [becauseOf]).
  DeviceReviewItem withoutBecause() => DeviceReviewItem(
    deviceId: deviceId,
    reason: reason,
    personId: personId,
    recordDigest: recordDigest,
    active: active,
    recordChanged: recordChanged,
  );

  /// En JSON, para guardarlo cifrado.
  Map<String, Object?> toJson() => <String, Object?>{
    'd': deviceId,
    'r': reason.name,
    'g': ?recordDigest,
    'p': ?personId,
    if (recordChanged) 'q': true,
    'b': ?becauseOf,
  };

  /// Lee [toJson]; null si no se entiende.
  static DeviceReviewItem? fromJson(Map<String, Object?> json) {
    final id = json['d'];
    if (id is! String || id.isEmpty) return null;
    final digest = json['g'];
    final person = json['p'];
    final reason = json['r'];
    return DeviceReviewItem(
      deviceId: id,
      personId: person is String ? person : null,
      recordDigest: digest is String ? digest : null,
      reason: DeviceReviewReason.values.firstWhere(
        (r) => r.name == reason,
        orElse: () => DeviceReviewReason.orphan,
      ),
      recordChanged: json['q'] == true,
      becauseOf: json['b'] is String ? json['b'] as String : null,
    );
  }
}

/// Los móviles por revisar, sin repetir: cada móvil con el motivo más
/// importante.
class DeviceReview {
  /// Crea la bandeja.
  const DeviceReview(this.items);

  /// Sin nada que revisar.
  static const empty = DeviceReview(<DeviceReviewItem>[]);

  /// Los elementos, en orden de importancia.
  final List<DeviceReviewItem> items;

  /// Si no hay nada que revisar.
  bool get isEmpty => items.isEmpty;

  /// El elemento del móvil [deviceId], o null.
  DeviceReviewItem? of(String deviceId) {
    for (final item in items) {
      if (item.deviceId == deviceId) return item;
    }
    return null;
  }
}

/// El estado de la fila de un móvil en la lista.
enum FamilyDeviceStatus {
  /// Conectado, sin nada que revisar.
  active,

  /// Conectado pero sin persona.
  noPerson,

  /// Conectado, pero hay que confirmar de nuevo de quién es.
  reconfirm,

  /// Espera aprobación (recién llegado o ha cambiado de persona).
  pending,

  /// Escritor congelado.
  frozen,
}

/// Un móvil de la lista de Ajustes, con su estado.
class FamilyDeviceEntry {
  /// Crea la entrada.
  const FamilyDeviceEntry({
    required this.row,
    required this.status,
    this.review,
  });

  /// El móvil.
  final FamilyDeviceRow row;

  /// Su estado.
  final FamilyDeviceStatus status;

  /// Lo que hay que revisar de él, si algo.
  final DeviceReviewItem? review;

  /// Si es este móvil.
  bool get isSelf => row.isSelf;

  /// Si ya es un móvil activo de la familia.
  bool get isActive => status != FamilyDeviceStatus.pending;
}

/// La lista de móviles con su estado: los activos de [rows] (cada uno con lo
/// que haya que revisar) y, detrás, los que esperan aprobación.
List<FamilyDeviceEntry> familyDeviceEntries(
  List<FamilyDeviceRow> rows,
  DeviceReview review,
) {
  FamilyDeviceStatus statusOf(FamilyDeviceRow row, DeviceReviewItem? item) {
    if (item != null && !row.isSelf) {
      switch (item.reason) {
        case DeviceReviewReason.frozen:
          return FamilyDeviceStatus.frozen;
        case DeviceReviewReason.newcomer:
        case DeviceReviewReason.personChanged:
          return FamilyDeviceStatus.pending;
        case DeviceReviewReason.orphan:
        case DeviceReviewReason.detached:
          return FamilyDeviceStatus.reconfirm;
      }
    }
    if (!row.isSelf && row.personId == null) return FamilyDeviceStatus.noPerson;
    return FamilyDeviceStatus.active;
  }

  final known = {for (final r in rows) r.deviceId};
  return [
    for (final row in rows)
      FamilyDeviceEntry(
        row: row,
        status: statusOf(row, review.of(row.deviceId)),
        review: review.of(row.deviceId),
      ),
    for (final item in review.items)
      if (!known.contains(item.deviceId) &&
          (item.reason == DeviceReviewReason.newcomer ||
              item.reason == DeviceReviewReason.personChanged))
        FamilyDeviceEntry(
          row: FamilyDeviceRow(
            deviceId: item.deviceId,
            isSelf: false,
            personId: item.personId,
          ),
          status: FamilyDeviceStatus.pending,
          review: item,
        ),
  ];
}

/// Móviles que se quitaron al otro y quedaron sueltos (los huérfanos de
/// `RegistryChange.orphans`), guardados cifrados en el móvil hasta
/// confirmarlos: tras quitar un móvil dejan de salir en el registro, y solo
/// este aviso los recuerda. Sobreviven a cerrar la app; se vacían al salir de
/// la familia o al cambiar de lista.
class RememberedOrphans extends AsyncNotifier<List<DeviceReviewItem>> {
  FamilyStore get _store => ref.read(familyStoreProvider);

  // A qué lista y generación v2 pertenece lo que hay en memoria.
  String? _scope;

  @override
  Future<List<DeviceReviewItem>> build() async {
    // Salir de la familia, crear otra o renovar la generación cambia la vista
    // del registro: se vuelve a leer, y lo de otra lista o generación se
    // descarta.
    ref.watch(localRegistryViewProvider);
    final scope = await _store.orphanScope();
    _scope = scope;
    return [
      for (final raw in await _store.readOrphans())
        ?DeviceReviewItem.fromJson(raw),
    ];
  }

  // Lo recordado, si sigue siendo de esta lista y generación; si no, nada.
  Future<List<DeviceReviewItem>> _current() async {
    final loaded = state.value ?? await future;
    final scope = await _store.orphanScope();
    if (scope != _scope) {
      _scope = scope;
      return const <DeviceReviewItem>[];
    }
    return loaded;
  }

  Future<void> _set(List<DeviceReviewItem> next) async {
    await _store.saveOrphans([for (final o in next) o.toJson()]);
    state = AsyncData(next);
  }

  /// Apunta los huérfanos de un cambio (y los guarda).
  Future<void> remember(Iterable<DeviceReviewItem> orphans) async {
    final fresh = {for (final o in orphans) o.deviceId: o};
    final current = await _current();
    await _set([
      for (final o in current)
        if (!fresh.containsKey(o.deviceId)) o,
      ...fresh.values,
    ]);
  }

  /// Ya está resuelto (aprobado o quitado).
  Future<void> forget(String deviceId) async {
    final current = await _current();
    if (current.any((o) => o.deviceId == deviceId)) {
      await _set([
        for (final o in current)
          if (o.deviceId != deviceId) o,
      ]);
    }
  }

  /// La revocación de [removed] ya está guardada: sus huérfanos preparados
  /// pasan a ser definitivos.
  Future<void> commit(String removed) async {
    final current = await _current();
    if (current.any((o) => o.becauseOf == removed)) {
      await _set([
        for (final o in current)
          if (o.becauseOf == removed) o.withoutBecause() else o,
      ]);
    }
  }

  /// La revocación de [removed] no llegó a guardarse: se descartan los
  /// huérfanos que se habían preparado por ella.
  Future<void> discard(String removed) async {
    final current = await _current();
    if (current.any((o) => o.becauseOf == removed)) {
      await _set([
        for (final o in current)
          if (o.becauseOf != removed) o,
      ]);
    }
  }
}

/// Los huérfanos recordados.
final rememberedOrphansProvider =
    AsyncNotifierProvider<RememberedOrphans, List<DeviceReviewItem>>(
      RememberedOrphans.new,
    );

/// Los móviles que son escritores congelados (`OpenedScope.frozenWriters`).
final frozenDeviceIdsProvider = Provider<Set<String>>(
  (ref) => ref.watch(v2HealthProvider).value?.frozenWriterDeviceIds ?? const {},
);

/// Lo que hay que revisar a mano, ahora: pendientes (recién llegados o
/// cambiados de persona), los que cuelgan de un revocado y nos avalaron, los
/// huérfanos recordados de un cambio reciente y los escritores congelados. Se
/// vuelve a leer con el registro.
///
/// No se deduce de la vista «quién no tiene derecho a qué»: en una familia de
/// tres móviles emparejados con normalidad, cada móvil ve al tercero sin
/// avalar por sí mismo, y avisar de eso siempre sería ruido. Solo se revisa lo
/// que el modelo señala (pendientes, `detached`, `RegistryChange.orphans`).
final deviceReviewProvider = FutureProvider<DeviceReview>((ref) async {
  final view = await ref.watch(localRegistryViewProvider.future);
  // Se lee también sin familia v2: así lo de una familia que ya no está se
  // descarta.
  final remembered = await ref.watch(rememberedOrphansProvider.future);
  if (view == null) return DeviceReview.empty;
  await ref.watch(v2HealthProvider.future);
  final frozen = ref.watch(frozenDeviceIdsProvider);
  final local = await AppSyncV2Local.load(ref);
  final registry = await local?.registry();
  final syncState = await local?.readState();
  // Los huérfanos «preparados» solo valen si su revocación
  // quedó guardada (en el registro o como intención pendiente).
  bool revocationSaved(String id) =>
      view.revoked.contains(id) ||
      (syncState?.pendingRevocations.contains(id) ?? false) ||
      (syncState?.revocationOperations.containsKey(id) ?? false);
  bool changed(String digest) =>
      (registry?.recordByDigest(digest)?.seq ?? 1) > 1;

  final byId = <String, DeviceReviewItem>{};
  void add(DeviceReviewItem item) =>
      byId.putIfAbsent(item.deviceId, () => item);

  for (final id in frozen) {
    final d = view.device(id);
    if (d != null && id != view.me) {
      add(
        DeviceReviewItem(
          deviceId: id,
          personId: d.personId,
          reason: DeviceReviewReason.frozen,
          recordDigest: d.recordDigest,
          active: view.member(id) != null,
          recordChanged: changed(d.recordDigest),
        ),
      );
    }
  }
  for (final d in view.pending) {
    final seq = registry?.recordByDigest(d.recordDigest)?.seq ?? 1;
    add(
      DeviceReviewItem(
        deviceId: d.deviceId,
        personId: d.personId,
        reason: seq > 1
            ? DeviceReviewReason.personChanged
            : DeviceReviewReason.newcomer,
        recordDigest: d.recordDigest,
      ),
    );
  }
  for (final d in view.detached) {
    add(
      DeviceReviewItem(
        deviceId: d.deviceId,
        personId: d.personId,
        reason: DeviceReviewReason.detached,
        recordDigest: d.recordDigest,
        recordChanged: changed(d.recordDigest),
      ),
    );
  }
  for (final o in remembered) {
    // Uno que se revocó después está resuelto. Los demás siguen hasta que se
    // aprueben o se quiten, estén o no ya en el registro (si no se aprueban,
    // no recuperan el derecho a las sorpresas de los demás).
    if (view.revoked.contains(o.deviceId)) continue;
    final because = o.becauseOf;
    if (because != null && !revocationSaved(because)) continue;
    // Si ya está en el registro con otra ficha (publicó una nueva), la que se
    // enseña y se avala es la actual, no la que se recordó.
    final current = view.device(o.deviceId);
    add(
      DeviceReviewItem(
        deviceId: o.deviceId,
        personId: current != null ? current.personId : o.personId,
        reason: o.reason,
        recordDigest: current?.recordDigest ?? o.recordDigest,
        active: view.member(o.deviceId) != null,
        recordChanged: current != null
            ? changed(current.recordDigest)
            : o.recordChanged,
      ),
    );
  }
  return DeviceReview(byId.values.toList());
});

/// Qué pasaría al quitar un móvil.
class DeviceRemovalPreview {
  /// Crea la vista previa.
  const DeviceRemovalPreview({
    required this.selfWouldWait,
    this.orphans = const <DeviceReviewItem>[],
  });

  /// Si este móvil volvería a esperar aprobación (N7).
  final bool selfWouldWait;

  /// Los que quedarían sueltos y habría que confirmar.
  final List<DeviceReviewItem> orphans;
}

/// La ficha del móvil ya no es la que se enseñó: hay que volver a mirarla
/// antes de aprobar.
class DeviceRecordChangedException implements Exception {
  /// Crea el error.
  const DeviceRecordChangedException();

  @override
  String toString() => 'DeviceRecordChangedException';
}

/// El móvil se quitó en este móvil (su revocación está guardada y ya no sale
/// en la lista), pero el servidor no respondió: su acceso se corta en cuanto
/// haya conexión. Los huérfanos ya están anotados en la bandeja.
class DeviceRemovalPendingException implements Exception {
  /// Crea el error.
  const DeviceRemovalPendingException(this.orphans);

  /// Los que quedaron sueltos y hay que confirmar.
  final List<DeviceReviewItem> orphans;

  @override
  String toString() => 'DeviceRemovalPendingException';
}

/// Lo que la interfaz hace sobre los móviles de la familia. La implementación
/// real va por [SyncController] (dentro del cerrojo v2); las pruebas de
/// widgets la sustituyen.
abstract class FamilyDeviceActions {
  /// Qué pasaría al quitar [deviceId].
  Future<DeviceRemovalPreview> previewRemoval(String deviceId);

  /// Quita [deviceId] y devuelve los huérfanos a confirmar uno a uno.
  /// [selfWaitAccepted] es si la persona ya aceptó el aviso de que este móvil
  /// volvería a esperar aprobación; si se vuelve a comprobar justo antes y
  /// hace falta ese aviso sin haberlo aceptado, lanza
  /// [DeviceRemovalChangedException]. Lanza [DeviceRemovalPendingException]
  /// si se quitó aquí pero falta cortar su acceso en el servidor.
  Future<List<DeviceReviewItem>> remove(
    String deviceId, {
    bool selfWaitAccepted = false,
  });

  /// Aprueba [deviceId] (uno solo), con la ficha [recordDigest] que se
  /// enseñó. Lanza [DeviceRecordChangedException] si ya no es esa.
  Future<void> approve(String deviceId, {String? recordDigest});
}

class _SyncDeviceActions implements FamilyDeviceActions {
  _SyncDeviceActions(this._ref);

  final Ref _ref;

  SyncController get _sync => _ref.read(syncControllerProvider.notifier);

  RememberedOrphans get _memory =>
      _ref.read(rememberedOrphansProvider.notifier);

  Future<List<DeviceReviewItem>> _orphans(Iterable<KnownDevice> devices) async {
    final registry = await (await AppSyncV2Local.load(_ref))?.registry();
    return [
      for (final d in devices)
        DeviceReviewItem(
          deviceId: d.deviceId,
          personId: d.personId,
          reason: DeviceReviewReason.orphan,
          recordDigest: d.recordDigest,
          recordChanged:
              (registry?.recordByDigest(d.recordDigest)?.seq ?? 1) > 1,
        ),
    ];
  }

  @override
  Future<DeviceRemovalPreview> previewRemoval(String deviceId) async {
    final p = await _sync.previewRemoveDevice(deviceId);
    return DeviceRemovalPreview(
      selfWouldWait: p.selfWouldWait,
      orphans: await _orphans(p.orphans),
    );
  }

  // Lo que ya se hizo no se desdice por no poder limpiar la memoria de
  // huérfanos: se reintenta una vez y, si sigue fallando, se deja en el
  // registro de depuración (la bandeja volverá a preguntar, y aprobar o
  // quitar es idempotente).
  Future<void> _tidy(Future<void> Function() step) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await step();
        return;
      } on Object catch (e) {
        if (attempt == 1) debugPrint('huérfanos: no se pudo limpiar ($e)');
      }
    }
  }

  @override
  Future<List<DeviceReviewItem>> remove(
    String deviceId, {
    bool selfWaitAccepted = false,
  }) async {
    var remembered = const <DeviceReviewItem>[];
    final List<DeviceReviewItem> orphans;
    try {
      final change = await _sync.removeDevice(
        deviceId,
        // N7 se comprueba dentro del mismo cerrojo que guarda la revocación.
        selfWaitAccepted: selfWaitAccepted,
        // Antes de guardar o hablar con la red, como «preparados»: no se
        // enseñan hasta que la revocación quede guardada.
        rememberOrphans: (devices) async {
          remembered = [
            for (final o in await _orphans(devices))
              DeviceReviewItem(
                deviceId: o.deviceId,
                personId: o.personId,
                reason: o.reason,
                recordDigest: o.recordDigest,
                recordChanged: o.recordChanged,
                becauseOf: deviceId,
              ),
          ];
          await _memory.remember(remembered);
        },
      );
      orphans = await _orphans(change.orphans);
    } on Object {
      // Si la revocación se guardó aquí y solo falló el corte del servidor
      // (se reintenta con la siguiente vuelta), el móvil ya está quitado.
      RegistryView? view;
      try {
        view = await _ref.read(localRegistryViewProvider.future);
      } on Object {
        view = null;
      }
      if (view != null && view.revoked.contains(deviceId)) {
        await _tidy(() => _memory.forget(deviceId));
        await _tidy(() => _memory.commit(deviceId));
        throw DeviceRemovalPendingException(remembered);
      }
      // No llegó a guardarse: lo preparado se descarta.
      await _tidy(() => _memory.discard(deviceId));
      rethrow;
    }
    await _tidy(() => _memory.forget(deviceId));
    await _tidy(() => _memory.remember(orphans));
    return orphans;
  }

  @override
  Future<void> approve(String deviceId, {String? recordDigest}) async {
    try {
      await _sync.approveDevice(deviceId, recordDigest: recordDigest);
    } on RegistryException catch (e) {
      if (e.message == kRecordChangedMessage) {
        throw const DeviceRecordChangedException();
      }
      rethrow;
    }
    // El aval ya está guardado: limpiar la memoria no cambia el resultado.
    await _tidy(() => _memory.forget(deviceId));
  }
}

/// Las acciones de la interfaz sobre los móviles de la familia.
final familyDeviceActionsProvider = Provider<FamilyDeviceActions>(
  _SyncDeviceActions.new,
);
