import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/device/device_name.dart' show isLegacyDeviceName;
import '../../../core/sync/envelope.dart';
import '../../../core/sync/device_registry.dart';
import '../../../core/sync/access_policy.dart';
import '../../../core/sync/access_policy.dart' as protection_policy;
import '../../../core/sync/device_keys.dart';
import '../../../core/sync/device_names.dart';
import '../../../core/sync/protected_doc.dart';
import '../../../core/sync/protected_doc.dart' as protection_model;
import '../../../core/sync/protected_envelope.dart';
import '../../../core/sync/family_doc.dart';
import '../../../core/sync/hlc.dart';
import '../../../core/sync/model.dart';
import '../../../core/sync/wish.dart';
import '../../../core/sync/wish_author.dart';
import '../../../core/sync/wish_boundary.dart';
import '../../../core/sync/wish_plan.dart';
import '../../../core/sync/pairing_v2.dart'
    show keepProtocolV2, kSyncProtocolV2, syncProtocolOf;
import '../../review/application/review_providers.dart';
import '../../review/domain/review_ports.dart';
import '../data/family_store.dart';
import '../data/device_keys_store.dart';
import '../data/recovery_store.dart';
import '../../sync/application/app_sync_v2_local.dart'
    show v2FamilyLockProvider;
import '../../sync/application/family_device_review.dart';
import '../../sync/application/recovery_providers.dart'
    show
        recoverySupportedProvider,
        resumeRecoveryBeforeFamily,
        requireNoPendingRestore;
import '../../sync/application/sync_controller.dart'
    show localRegistryReadProvider;
import '../../sync/data/sync_transport_v2.dart' show kV2MaxSlotsPerWriter;
import '../../sync/application/sync_v2_engine.dart' show V2SyncState;
import '../domain/delete_impact.dart';
import '../domain/family_errors.dart';
import 'occasion_names.dart';
import 'remote_change.dart';
import 'self_person_change.dart';

export 'self_person_change.dart';
export '../domain/delete_impact.dart' show DeleteImpactChanged;
export '../domain/family_errors.dart'
    show GiftWriteResult, GiverPersonNeedsPublicAdd;

part 'person_protection.dart';

const _uuid = Uuid();

typedef _GiftWriteOutcome = ({GiftWriteResult result, String? savedId});

/// Reintentos de los providers: Riverpod reintenta lo que falla, pero un
/// guardado ilegible (`FamilyStoreException`) no se arregla repitiendo.
Duration? familyRetry(int retryCount, Object error) {
  if (error is FamilyStoreException || retryCount >= 3) {
    return null;
  }
  return Duration(milliseconds: 200 * (1 << retryCount));
}

/// Estado de la familia en este móvil.
class FamilyState {
  /// Crea el estado de una familia.
  FamilyState({
    required this.doc,
    required this.identity,
    this.hiddenGiftIds = const <String>{},
    this.protectionRevision = 0,
    this.otherDevicePeople = const <String>{},
    bool authorized = false,
    this.plansByWish = const <String, List<WishPlan>>{},
    Set<String> planGiftIds = const <String>{},
  }) : _authorized = authorized,
       view = FamilyView.fromDoc(
         authorized ? doc : _safeStateDoc(doc),
         hiddenGiftIds: hiddenGiftIds,
         plansByWish: plansByWish,
         planGiftIds: planGiftIds,
       );

  /// Primer arranque: todavía no hay familia.
  FamilyState.noFamily()
    : doc = FamilyDoc.empty(''),
      view = _emptyView,
      hiddenGiftIds = const <String>{},
      protectionRevision = 0,
      otherDevicePeople = const <String>{},
      plansByWish = const <String, List<WishPlan>>{},
      _authorized = false,
      identity = null;

  static final FamilyView _emptyView = FamilyView.fromDoc(FamilyDoc.empty(''));

  /// El documento.
  final FamilyDoc doc;
  final bool _authorized;

  /// Los planes vivos de los deseos que este móvil puede ver, por id de deseo
  /// (ADR 0010). Vacío en los móviles de la propia persona.
  final Map<String, List<WishPlan>> plansByWish;

  static FamilyDoc _safeStateDoc(FamilyDoc doc) {
    // Solo se ocultan las personas cuya política publicada dice «ocultar»
    // (también un registro roto o una lápida): tras desactivar la protección
    // sus regalos vuelven a verse (revisión de seguridad, lote 6, 3).
    final protected = {
      for (final e in publishedPolicies(doc).entries)
        if (e.value.hideOwnGifts) e.key,
    };
    if (protected.isEmpty) return doc;
    return FamilyDoc(
      listId: doc.listId,
      collections: {
        ...doc.collections,
        Collections.gifts: {
          for (final e
              in doc.collections[Collections.gifts]?.entries ??
                  const <MapEntry<String, SyncRecord>>[])
            if (!protected.contains(e.value['recipientId'])) e.key: e.value,
        },
      },
    );
  }

  /// El documento visto como listas tipadas: sin lo borrado ni las personas
  /// y quien regala archivados, de todos los años.
  final FamilyView view;

  /// Identidad de este móvil, o `null` si todavía no hay familia.
  final FamilyIdentity? identity;

  /// Si ya hay una familia en este móvil.
  bool get hasFamily => identity != null;

  /// Si hay otro móvil emparejado.
  bool get paired => identity?.paired ?? false;

  /// Id de la lista, o `null` si no hay familia.
  String? get listId => identity?.listId;

  /// De qué móvil de la familia es dueña la persona [recipientId], o `null`
  /// si de ninguno. A una persona con móvil no se la puede archivar ni
  /// eliminar (ni en la pantalla ni en el controlador).
  ///
  /// - **Este móvil:** es «Yo» (`identity.selfRecipientId`, ADR 0004).
  /// - **Otro dispositivo de la familia:** [otherDevicePeople].
  DevicePersonOwner? devicePersonOwner(String recipientId) {
    if (identity?.selfRecipientId == recipientId) {
      return DevicePersonOwner.thisDevice;
    }
    if (otherDevicePeople.contains(recipientId)) {
      return DevicePersonOwner.otherDevice;
    }
    return null;
  }

  /// Si la persona [recipientId] es dueña de un móvil de la familia: el
  /// único predicado que deciden la pantalla de gestionar personas y el
  /// controlador para no archivarla ni eliminarla.
  bool isDevicePerson(String recipientId) =>
      devicePersonOwner(recipientId) != null;

  /// Las personas dueñas de los **otros** móviles conectados de la familia.
  final Set<String> otherDevicePeople;

  /// Si el documento tiene algún registro (borrado o no).
  bool get hasData =>
      doc.collections.values.any((records) => records.isNotEmpty);

  /// Regalos que el usuario acaba de borrar y esperan a que caduque el aviso
  /// con «Deshacer»: ya no se ven, pero su lápida aún no está escrita (el
  /// contenido sigue en [doc], en memoria).
  final Set<String> hiddenGiftIds;

  /// Local protected writes also need an upload when the common is unchanged.
  /// This in-memory signal carries no gift content or count.
  final int protectionRevision;

  /// El documento con todo, también lo archivado (para gestionar archivados).
  FamilyView get fullView => FamilyView.fromDoc(
    _authorized ? doc : _safeStateDoc(doc),
    includeArchived: true,
    hiddenGiftIds: hiddenGiftIds,
    plansByWish: plansByWish,
    planGiftIds: view.planGiftIds,
  );

  /// Copia con otro documento, identidad o regalos a la espera de borrarse.
  FamilyState copyWith({
    FamilyDoc? doc,
    FamilyIdentity? identity,
    Set<String>? hiddenGiftIds,
    int? protectionRevision,
    Set<String>? otherDevicePeople,
  }) => FamilyState(
    doc: doc ?? this.doc,
    identity: identity ?? this.identity,
    hiddenGiftIds: hiddenGiftIds ?? this.hiddenGiftIds,
    protectionRevision: protectionRevision ?? this.protectionRevision,
    otherDevicePeople: otherDevicePeople ?? this.otherDevicePeople,
    authorized: _authorized,
    plansByWish: plansByWish,
    planGiftIds: view.planGiftIds,
  );
}

/// Lo que devuelve unirse a una familia.
class JoinResult {
  /// Crea el resultado.
  const JoinResult({required this.peerName, required this.replacedFamily});

  /// Nombre del móvil que mostró el QR.
  final String peerName;

  /// Si se sustituyó otra familia.
  final bool replacedFamily;
}

/// Controlador de la familia: guarda, edita y mezcla el documento.
///
/// Todas las operaciones de escritura van una detrás de otra y guardan en
/// disco antes de cambiar el estado.
class FamilyController extends AsyncNotifier<FamilyState> {
  HlcClock? _clock;
  FamilyKey? _key;
  Future<void> _tail = Future<void>.value();
  bool _recipientPurgePending = false;

  FamilyStore get _store => ref.read(familyStoreProvider);
  Ref get _protectionRef => ref;
  set _protectionState(AsyncValue<FamilyState> value) => state = value;

  @override
  Future<FamilyState> build() async {
    final supportsRecovery = ref.read(recoverySupportedProvider);
    if (supportsRecovery) await resumeRecoveryBeforeFamily(ref);
    final writable = await _canMaintainStorage();
    if (writable) await _store.recoverProtectionOperation();
    final stored = await _store.load();
    _recipientPurgePending = false;
    if (stored == null) {
      _clock = null;
      _key = null;
      return FamilyState.noFamily();
    }
    _dropPending();
    _adopt(stored.identity, stored.key, stored.doc);
    if (supportsRecovery) {
      final recoveryFloor = (await _store.readRecoveryRevisionFloors()).hlc;
      if (recoveryFloor != null && recoveryFloor > _clock!.last) {
        _clock = HlcClock(node: stored.identity.node, last: recoveryFloor);
      }
    }
    ref.onDispose(_dropPending);
    // Las lápidas de versiones anteriores conservaban el contenido de lo
    // borrado: se vuelven a borrar con el reloj de ahora (así el vaciado gana
    // por marca, también en los móviles antiguos) y se guarda el resultado.
    var doc = stored.doc;
    final dirty = doc.tombstonesWithContent();
    for (final (collection, id) in dirty) {
      doc = doc.delete(_clock!, collection, id);
    }
    if (_store.supportsSecretScopes) {
      doc = doc.tombstoneWishesForDeletedRecipients();
    }
    if (!identical(doc, stored.doc) && writable) {
      await _store.saveDoc(doc);
      doc = _store.savedDoc(doc);
    }
    // Recovery and pairing may need this snapshot while holding the v2 lock.
    // The next locked write can replay cleanup from the saved tombstones.
    _recipientPurgePending =
        _store.supportsSecretScopes && _hasDeletedRecipients(doc);
    return FamilyState(
      doc: doc,
      identity: stored.identity,
      otherDevicePeople: await _readOtherActiveDevicePeople(doc),
    );
  }

  bool _hasDeletedRecipients(FamilyDoc doc) =>
      doc.collections[Collections.recipients]?.values.any(
        (record) => record.isDeleted,
      ) ??
      false;

  Future<bool> _canMaintainStorage() async {
    if (!ref.read(recoverySupportedProvider)) return true;
    final restoring = await ref.read(recoveryStoreProvider).readRestore();
    return !await _store.isTransferred() &&
        (restoring == null || restoring.phase == RecoveryPhase.active);
  }

  // The common is already durable and visible. Retry failed cleanup under
  // the family lock before another write. Startup can replay it from disk.
  Future<void> _purgeRecipientScopes(FamilyDoc doc) async {
    if (!_store.supportsSecretScopes || !_hasDeletedRecipients(doc)) {
      _recipientPurgePending = false;
      return;
    }
    _recipientPurgePending = true;
    if (!await _canMaintainStorage()) return;
    await _store.purgeDeletedRecipientScopes(doc);
    _recipientPurgePending = false;
  }

  Future<void> _resumeRecipientPurge() async {
    if (!_recipientPurgePending) return;
    final doc = state.value?.doc;
    if (doc != null) await _purgeRecipientScopes(doc);
  }

  Future<Set<String>> _readOtherActiveDevicePeople(FamilyDoc doc) async {
    try {
      return otherActiveDevicePeople(
        await _store.readDevicePersonView(doc),
        excludingDevice: (await _store.readSyncV2())?.deviceId,
      );
    } on RegistryException {
      // Display metadata only: archiving and deleting verify it afresh
      // (_refuseDevicePerson), so a mixed identity cannot block the family.
      return const {};
    } on FamilyStoreException {
      return const {};
    } on DeviceKeysStoreException {
      return const {};
    }
  }

  /// La clave de la familia, o `null` si no hay familia. Nunca va en el
  /// estado.
  FamilyKey? get familyKey {
    _store.requireMobileOperation('familyKeyExport');
    return _key;
  }

  void _adopt(FamilyIdentity identity, FamilyKey key, FamilyDoc doc) {
    _key = key;
    _clock = HlcClock(node: identity.node, last: _store.latestStoredStamp(doc));
  }

  /// Ejecuta [action] cuando acaben las escrituras anteriores.
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  // Public-only edits can normally run during sync. If a previous command
  // left cleanup pending, release the write queue before taking the v2 lock.
  Future<T> _serialCommonWrite<T>(Future<T> Function() action) async {
    await _current();
    final result = await _serial<({T value})?>(() async {
      if (_recipientPurgePending) return null;
      return (value: await action());
    });
    if (result == null) return _protectionSerial(action);
    return result.value;
  }

  Future<FamilyState> _current() async => state.value ?? await future;

  Future<T> _changeFamily<T>(Future<T> Function() action) =>
      _serial(_current).then(
        (_) => ref
            .read(v2FamilyLockProvider)
            .run(
              () => _serial(() async {
                await requireNoPendingRestore(ref);
                return action();
              }),
            ),
      );

  /// Adopts the stored candidate and its latest logical clock in edit order.
  Future<void> reloadStoredCandidate() => _serial(() async {
    if (!ref.mounted) return;
    final current = await _current();
    if (!ref.mounted) return;
    final stored = await _store.load();
    if (stored == null || !ref.mounted) return;
    _key = stored.key;
    final max = _store.latestStoredStamp(stored.doc);
    if (_clock == null || current.identity?.node != stored.identity.node) {
      _clock = HlcClock(node: stored.identity.node);
    }
    if (max != null && max > _clock!.last) _clock!.receive(max);
    final otherPeople = await _readOtherActiveDevicePeople(stored.doc);
    if (!ref.mounted) return;
    state = AsyncData(
      current.copyWith(
        doc: stored.doc,
        identity: stored.identity,
        otherDevicePeople: otherPeople,
      ),
    );
  });

  // ------------------------------------------------------------- familia

  /// Crea una familia nueva: lista, clave y nodo propios.
  ///
  /// Lanza [FamilyAlreadyExistsException] si ya hay una con datos.
  Future<void> createFamily({required String deviceName}) =>
      _changeFamily(() async {
        final current = await _current();
        if (current.hasFamily && current.hasData) {
          throw const FamilyAlreadyExistsException();
        }
        final key = await FamilyKey.generate();
        final identity = FamilyIdentity(
          listId: _uuid.v4(),
          node: HlcClock.newNode(),
          deviceName: deviceName.trim(),
        );
        final doc = FamilyDoc.empty(identity.listId);
        await _store.saveFamily(
          StoredFamily(identity: identity, key: key, doc: doc),
        );
        _adopt(identity, key, doc);
        state = AsyncData(FamilyState(doc: doc, identity: identity));
      });

  /// Crea una familia nueva con todo lo del primer uso ya dentro: personas,
  /// quien regala y ocasiones.
  ///
  /// Se guarda y se publica de una vez: el estado pasa de «sin familia» a la
  /// familia completa sin pasos intermedios. Si se fuera creando y rellenando
  /// por partes, la app saldría del primer uso (la ruta reacciona en cuanto
  /// hay familia) y enseñaría Personas a medio rellenar mientras acaban de
  /// guardarse las demás escrituras.
  ///
  /// Lanza [FamilyAlreadyExistsException] si ya hay una con datos.
  Future<void> createFamilyWith({
    required String deviceName,
    List<Recipient> recipients = const [],
    List<Giver> givers = const [],
    List<Occasion> occasions = const [],
    required String region,
    Set<OccasionKind>? kinds,
  }) => _changeFamily(() async {
    final current = await _current();
    if (current.hasFamily && current.hasData) {
      throw const FamilyAlreadyExistsException();
    }
    final key = await FamilyKey.generate();
    final identity = FamilyIdentity(
      listId: _uuid.v4(),
      node: HlcClock.newNode(),
      deviceName: deviceName.trim(),
    );
    final clock = HlcClock(node: identity.node);
    var doc = FamilyDoc.empty(identity.listId);
    for (final recipient in recipients) {
      doc = _withRecipient(doc, clock, recipient);
    }
    for (final giver in givers) {
      doc = _writeChanged(
        doc,
        clock,
        Collections.givers,
        giver.id,
        giver.toFields(),
      );
    }
    for (final occasion in occasions) {
      doc = _writeChanged(
        doc,
        clock,
        Collections.occasions,
        occasion.id,
        occasion.toFields(),
      );
    }
    doc = _withSeedOccasions(doc, clock, region, kinds);
    await _store.saveFamily(
      StoredFamily(identity: identity, key: key, doc: doc),
    );
    _adopt(identity, key, doc);
    state = AsyncData(FamilyState(doc: doc, identity: identity));
  });

  /// Une este móvil a la familia de un QR ya interpretado.
  ///
  /// Si hay otra familia con datos y no se pide [replace], lanza
  /// [FamilyConflictException]; lo mismo si la lista es la misma pero la clave
  /// del QR es otra. Si lista y clave coinciden, solo se marca emparejado.
  ///
  /// Un móvil que ya está en v2 no entra nunca por un QR o una invitación de
  /// v1, ni sustituyendo: lanza [V1PairingOnV2Exception] sin tocar nada
  /// (revisión de la fase 2b, hallazgo 13).
  Future<JoinResult> joinFamily({
    required PairingPayload payload,
    String deviceName = '',
    bool replace = false,
  }) => _changeFamily(() async {
    final current = await _current();
    final existing = current.identity;
    if (existing != null &&
        (syncProtocolOf(current.doc) == kSyncProtocolV2 ||
            await _store.readSyncV2() != null)) {
      throw const V1PairingOnV2Exception();
    }
    // Misma lista y misma clave: es el mismo grupo, solo se marca emparejado.
    // Misma lista con otra clave se trata como otra familia (pide `replace`).
    if (existing != null &&
        existing.listId == payload.listId &&
        _key == payload.key) {
      final identity = existing.copyWith(
        peerName: payload.deviceName,
        paired: true,
      );
      await _store.saveFamily(
        StoredFamily(identity: identity, key: payload.key, doc: current.doc),
      );
      _adopt(identity, payload.key, current.doc);
      state = AsyncData(current.copyWith(identity: identity));
      return JoinResult(peerName: payload.deviceName, replacedFamily: false);
    }
    final replaces = existing != null && current.hasData;
    if (replaces && !replace) {
      throw FamilyConflictException(existingListId: existing.listId);
    }
    final identity = FamilyIdentity(
      listId: payload.listId,
      node: HlcClock.newNode(),
      deviceName: deviceName.trim(),
      peerName: payload.deviceName,
      paired: true,
    );
    final doc = FamilyDoc.empty(identity.listId);
    await _store.saveFamily(
      StoredFamily(identity: identity, key: payload.key, doc: doc),
    );
    _adopt(identity, payload.key, doc);
    state = AsyncData(FamilyState(doc: doc, identity: identity));
    return JoinResult(peerName: payload.deviceName, replacedFamily: replaces);
  });

  /// Pasa esta familia a v2 (ADR 0004) o la instala desde un emparejamiento
  /// v2: guarda [doc] y la clave de la familia [key] con la identidad de
  /// lista [listId] y nodo [node]. Si ya había una familia de la misma lista
  /// con ese nodo conserva su nombre y su «Yo»; [doc] ya trae fusionado lo
  /// que había (`migrateToV2` o `mergeLocalV1IntoV2`).
  Future<void> installV2({
    required String listId,
    required String node,
    required FamilyKey key,
    required FamilyDoc doc,
    String deviceName = '',
    String? peerName,
    bool paired = false,
    bool setSelfRecipient = false,
    String? selfRecipientId,
  }) => _serial(() async {
    final current = await _current();
    await requireNoPendingRestore(ref);
    final existing = current.identity;
    final same =
        existing != null && existing.listId == listId && existing.node == node;
    var identity = same
        ? existing.copyWith(
            peerName: peerName,
            paired: paired || existing.paired,
            // El nombre que la persona envió al unirse gana al anterior.
            deviceName: deviceName.trim().isEmpty ? null : deviceName.trim(),
          )
        : FamilyIdentity(
            listId: listId,
            node: node,
            deviceName: deviceName.trim(),
            peerName: peerName,
            paired: paired,
          );
    // Al unirse a una invitación 1.0.6, «Este móvil es de» es la persona que
    // eligió quien invita (la de la ficha firmada), también si es nadie.
    if (setSelfRecipient) {
      identity = identity.withSelfRecipient(selfRecipientId);
    }
    final reconciled = reconcileGiverCopies(
      doc,
      HlcClock(node: node, last: doc.maxStamp),
    );
    await _store.saveFamily(
      StoredFamily(identity: identity, key: key, doc: reconciled),
    );
    // El almacén de claves recuerda la persona: nunca guarda las de sus
    // propias sorpresas (M7).
    if (setSelfRecipient) await _store.saveSelfRecipient(selfRecipientId);
    _adopt(identity, key, reconciled);
    state = AsyncData(FamilyState(doc: reconciled, identity: identity));
  });

  /// Marca esta familia como emparejada con otro móvil y guarda cómo se llama.
  ///
  /// Lo usa quien invita al aprobar una invitación: desde ese momento el otro
  /// móvil tiene la clave, aunque todavía no haya subido nada. [peerName] es
  /// el nombre que escribió el otro móvil; vacío no cambia el que había.
  Future<void> markPaired({String? peerName}) => _serial(() async {
    final current = await _current();
    final identity = current.identity;
    if (identity == null) {
      return;
    }
    final name = peerName?.trim() ?? '';
    final next = identity.copyWith(
      peerName: name.isEmpty ? null : name,
      paired: true,
    );
    if (next.paired == identity.paired && next.peerName == identity.peerName) {
      return;
    }
    await _store.saveIdentity(next);
    state = AsyncData(current.copyWith(identity: next));
  });

  /// Marca esta familia como sin otros móviles: tras salir de ella o al
  /// estrenar una generación v2 (un `syncId` nuevo), hasta volver a
  /// conectar otro móvil.
  Future<void> markUnpaired() => _serial(() async {
    final current = await _current();
    final identity = current.identity;
    if (identity == null || (!identity.paired && identity.formerSelf.isEmpty)) {
      return;
    }
    // Una generación sin nadie: ni emparejado ni personas de antes que
    // ocultar (1.0.6; ya se purgaron).
    final next = identity.copyWith(paired: false).withFormerSelf(const {});
    await _store.saveIdentity(next);
    state = AsyncData(current.copyWith(identity: next));
  });

  /// Cambia el nombre con que este móvil se presenta a los demás. Vacío no
  /// hace nada.
  Future<void> setDeviceName(String name) => _serialCommonWrite(() async {
    final current = await _current();
    final identity = current.identity;
    final clean = name.trim();
    if (identity == null || clean.isEmpty || clean == identity.deviceName) {
      return;
    }
    final next = identity.copyWith(deviceName: clean);
    await _store.saveIdentity(next);
    final doc = await _store.readSyncV2() == null
        ? current.doc
        : withDeviceName(current.doc, _clock!, next.node, clean);
    if (!identical(doc, current.doc)) await _store.saveDoc(doc);
    state = AsyncData(current.copyWith(identity: next, doc: doc));
  });

  /// Publish missing names for existing installations on their next v2 cycle.
  /// Caller holds the family lock before publishing a v2 snapshot.
  Future<void> publishDeviceNameWithinLock() => _serial(() async {
    final current = await _requireFamily();
    final identity = current.identity!;
    if (isLegacyDeviceName(identity.deviceName)) return;
    final doc = withDeviceName(
      current.doc,
      _clock!,
      identity.node,
      identity.deviceName,
    );
    if (identical(doc, current.doc)) return;
    await _store.saveDoc(doc);
    state = AsyncData(current.copyWith(doc: doc));
  });

  /// Dice de quién es este móvil («Yo», ADR 0004): [recipientId] es el id
  /// estable de una persona de la familia, o `null` para quitarla.
  ///
  /// Es local: no toca el documento ni viaja a otros móviles, y no da
  /// permisos. Al elegir a alguien, el guardado quita antes del llavero sus
  /// claves de sorpresa (revisión de seguridad, M7). No hace nada si no hay
  /// familia o si [recipientId] no es de una persona que exista (eliminada o
  /// desconocida).
  Future<void> setSelfRecipient(String? recipientId) => _serial(() async {
    final current = await _current();
    final identity = current.identity;
    if (identity == null) {
      return;
    }
    if (recipientId == null) {
      if (identity.selfRecipientId == null) {
        return;
      }
    } else if (_isGone(current.doc, Collections.recipients, recipientId)) {
      return;
    }
    await _store.saveSelfRecipient(recipientId);
    state = AsyncData(
      current.copyWith(identity: identity.withSelfRecipient(recipientId)),
    );
  });

  /// Cambia «Yo» y los permisos v2. Vive aquí porque este controlador posee
  /// la identidad local en memoria; toma primero el cerrojo v2 y después su
  /// cola habitual, como sincronización. No necesita conexión para guardar.
  /// La interfaz debe usar este método en lugar de [setSelfRecipient].
  Future<ChangeSelfPersonResult> changeSelfPerson(String? personId) =>
      withRecoveredSelfPersonChange(
        () => _serial(() async {
          _store.requireMobileOperation('changePerson');
          final current = await _current();
          final identity = current.identity;
          if (identity == null ||
              (personId != null &&
                  !livePeopleOf(current.doc).contains(personId))) {
            return ChangeSelfPersonResult.unchanged;
          }
          final v2 = await _store.readSyncV2();
          if (v2 == null) {
            if (identity.selfRecipientId == personId) {
              return ChangeSelfPersonResult.unchanged;
            }
            // 1.0.6: emparejado, la persona de antes sigue oculta aquí (en
            // v1 nadie aprueba el cambio): un regalo público tardío para
            // ella no vuelve a verse.
            var base = identity;
            final old = identity.selfRecipientId;
            if (old != null && identity.paired) {
              base = identity.withFormerSelf({...identity.formerSelf, old});
              await _store.saveIdentity(base);
            }
            await _store.saveSelfRecipient(personId);
            state = AsyncData(
              current.copyWith(identity: base.withSelfRecipient(personId)),
            );
            return ChangeSelfPersonResult.localOnly;
          }
          final keys = (await ref.read(deviceKeysStoreProvider).read())!;
          final anchor = RegistryAnchor(
            deviceId: v2.deviceId,
            signingKey: keys.publicKeys.signing,
          );
          final registry = (await _store.readRegistry(anchor: anchor))!;
          final view = await registry.viewFor(
            me: v2.deviceId,
            mySigningKey: keys.publicKeys.signing,
            livePeople: livePeopleOf(current.doc),
          );
          // Choque 6 (1.0.6): un móvil solo no tiene a nadie que apruebe su
          // ficha nueva. Si su ficha nunca ha salido de este móvil (sin lista
          // en el servidor, ni sincronización ni recuperación), se sustituye
          // por una primera ficha con la persona nueva: vale sin aprobación y
          // nadie puede tener la anterior para hacerla ambigua.
          if (await _ownRecordNeverLeft(view, identity)) {
            if (view.myPerson == personId && view.selfApproved) {
              await _assignSelfLocally(current, identity, personId);
              return ChangeSelfPersonResult.unchanged;
            }
            final fresh = await DeviceRegistry.empty(v2.listId).withRecord(
              await DeviceRecord.create(
                keys: keys,
                listId: v2.listId,
                deviceId: v2.deviceId,
                personId: personId,
              ),
            );
            await _store.prepareSelfPersonChange(
              personId: personId,
              registry: fresh,
              orphans: const [],
              replaceRegistry: true,
            );
            await _finishSelfPersonChange();
            return ChangeSelfPersonResult.localOnly;
          }
          // 1.0.6: hasta que otro apruebe la ficha nueva, la persona de antes
          // sigue oculta aquí (y se purga si este móvil se queda solo). Va en
          // la misma intención que el cambio.
          final old = identity.selfRecipientId ?? view.myPerson;
          final RegistryChange change;
          try {
            change = await changePerson(
              registry: registry,
              view: view,
              myKeys: keys,
              personId: personId,
            );
          } on RegistryException catch (e) {
            if (e.message == 'este móvil ya no puede cambiar de persona') {
              throw const SelfPersonSequenceExhaustedException();
            }
            rethrow;
          }
          if (!change.rotates) {
            state = AsyncData(current.copyWith(identity: identity));
            return ChangeSelfPersonResult.unchanged;
          }
          await _store.prepareSelfPersonChange(
            personId: personId,
            registry: change.registry,
            formerSelf: old != null && old != personId ? old : null,
            orphans: [
              for (final d in change.orphans)
                DeviceReviewItem(
                  deviceId: d.deviceId,
                  personId: d.personId,
                  reason: DeviceReviewReason.orphan,
                  recordDigest: d.recordDigest,
                  recordChanged:
                      (registry.recordByDigest(d.recordDigest)?.seq ?? 1) > 1,
                ).toJson(),
            ],
          );
          await _finishSelfPersonChange();
          return ChangeSelfPersonResult.pendingApproval;
        }),
      );

  // La identidad local con [personId] cuando la ficha ya lo dice.
  Future<void> _assignSelfLocally(
    FamilyState current,
    FamilyIdentity identity,
    String? personId,
  ) async {
    if (identity.selfRecipientId == personId) return;
    await _store.saveSelfRecipient(personId);
    state = AsyncData(
      current.copyWith(identity: identity.withSelfRecipient(personId)),
    );
  }

  // Si la ficha de este móvil nunca ha salido de él: no hay otro
  // dispositivo en el registro, no se ha emparejado, no hay lista en el
  // servidor y ni la sincronización ni la recuperación están puestas.
  Future<bool> _ownRecordNeverLeft(
    RegistryView view,
    FamilyIdentity identity,
  ) async {
    if (!view.alone || identity.paired) return false;
    // La creación de la lista pudo entrar aunque se perdiera la respuesta:
    // su intención se guarda antes de enviarla (createSent).
    final sync = V2SyncState.fromJson(await _store.readSyncV2State());
    if (sync.created || sync.createSent) return false;
    if (await _store.remoteSyncEnabled()) return false;
    if (await _store.recoveryConfigured()) return false;
    return true;
  }

  /// «¿Quién eres?» (1.0.6), antes de invitar a otro dispositivo: este
  /// móvil es de [personId] ([changeSelfPerson]; en un móvil solo cuya ficha
  /// no ha salido de él, sin aprobación).
  Future<ChangeSelfPersonResult> answerWhoAreYou(String personId) =>
      changeSelfPerson(personId);

  /// «No estoy en la lista» o, con [noGifts], «Nadie» (quien regala y no
  /// recibe: una persona de verdad marcada [Recipient.noGifts], para que el
  /// móvil tenga todos sus derechos): da de alta a [name] y este móvil pasa
  /// a ser suyo ([answerWhoAreYou]). Devuelve su id y el resultado.
  Future<(String, ChangeSelfPersonResult)> answerWhoAreYouNew(
    String name, {
    bool noGifts = false,
    int? colorIndex,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(name, 'name');
    final family = await future;
    final id = _uuid.v4();
    await upsertRecipient(
      Recipient(
        id: id,
        name: trimmed,
        colorIndex: colorIndex ?? family.fullView.recipients.length,
        archived: false,
        noGifts: noGifts,
        inReparto: !noGifts,
      ),
    );
    return (id, await answerWhoAreYou(id));
  }

  /// Recupera un cambio de «Yo» bajo el cerrojo v2 y la cola de escrituras,
  /// actualiza también la identidad en memoria y relee sus vistas derivadas.
  /// Ejecuta después [transaction] sin soltar el cerrojo: la carga local y
  /// la siguiente operación no pueden intercalarse con otro cambio de «Yo».
  /// [transaction] puede usar la cola de escrituras, pero no tomar el cerrojo.
  Future<T> withRecoveredSelfPersonChange<T>(
    Future<T> Function() transaction,
  ) async {
    await _current();
    return ref.read(v2FamilyLockProvider).run(() async {
      await _serial(_finishSelfPersonChange);
      return transaction();
    });
  }

  // Solo dentro de la cola de escrituras y del cerrojo v2.
  Future<void> _finishSelfPersonChange() async {
    final current = await _current();
    // Un fallo puede haber persistido parte del cambio: refrescar también
    // entonces. Si no había intención, las vistas en carga siguen su curso.
    var touched = true;
    try {
      touched = await _store.finishSelfPersonChange();
    } finally {
      if (touched) {
        final identity = current.identity;
        if (identity != null) {
          final person = await _store.readSelfRecipient();
          final former = await _store.readFormerSelf();
          if (identity.selfRecipientId != person ||
              former.length != identity.formerSelf.length ||
              !former.containsAll(identity.formerSelf)) {
            state = AsyncData(
              current.copyWith(
                identity: identity
                    .withSelfRecipient(person)
                    .withFormerSelf(former),
              ),
            );
          }
        }
        // Estas vistas observan FamilyController. Invalidarlas por el
        // contenedor evita declarar una dependencia circular desde su Ref.
        ref.container.invalidate(localRegistryReadProvider);
        ref.container.invalidate(rememberedOrphansProvider);
      }
    }
  }

  /// Borra todo lo guardado en este móvil y vuelve al estado sin familia.
  ///
  /// Para salir de un guardado que no se puede leer y para «Borrar todo» de
  /// Ajustes. Los regalos que esperaban su «Deshacer» se olvidan: ya no hay
  /// documento en el que escribir su lápida.
  Future<void> resetLocalData() => _serial(() async {
    _dropPending();
    await _store.clear();
    _clock = null;
    _key = null;
    _recipientPurgePending = false;
    state = AsyncData(FamilyState.noFamily());
  });

  /// Mezcla un documento recibido de otro móvil y guarda el resultado.
  ///
  /// Lanza [ImportClockDriftException] si el reloj del otro móvil va más de
  /// un día adelantado, y [NoFamilyException] si todavía no hay familia.
  Future<ImportSummary> mergeRemote(
    FamilyDoc remote, {
    required String fromNode,
  }) async {
    await _current();
    return ref
        .read(v2FamilyLockProvider)
        .run(() => mergeRemoteWithinLock(remote, fromNode: fromNode));
  }

  /// The v2 engine and signed file import already hold the family lock.
  Future<ImportSummary> mergeRemoteWithinLock(
    FamilyDoc remote, {
    required String fromNode,
  }) => _serial(() async {
    _store.requireMobileOperation('import');
    final current = await _requireFamily();
    final identity = current.identity!;
    // Frontera de los deseos (ADR 0010): del común que llega no entra nada
    // privado de los planes ni un deseo mal formado.
    remote = remote.wishBoundary();
    final remoteMax = remote.maxStamp;
    if (remoteMax != null) {
      // Antes de tocar nada: si el otro móvil va muy adelantado se rechaza.
      try {
        _clock!.receive(remoteMax);
      } on HlcDriftException catch (e) {
        throw ImportClockDriftException(ahead: e.lead);
      }
    }
    var merged = current.doc.merge(remote).normalizedWishes();
    // Una lápida que el otro móvil aún llena de contenido (un móvil antiguo,
    // o una edición suya posterior al borrado) se borra otra vez con el reloj
    // de ahora: así el vaciado gana por marca en cualquier versión y los dos
    // documentos acaban siendo iguales.
    for (final (collection, id) in current.doc.staleTombstonesIn(
      remote,
      merged,
    )) {
      merged = merged.delete(_clock!, collection, id);
    }
    // Una familia v2 no vuelve a v1 por lo que llega (hallazgo 1).
    merged = keepProtocolV2(
      before: current.doc,
      merged: merged,
      clock: _clock!,
    );
    merged = reconcileGiverCopies(merged, _clock!);
    final changed = merged.canonicalJson() != current.doc.canonicalJson();
    final summary = ImportSummary.between(
      await _authorizedView(current.doc, policySource: merged),
      await _authorizedView(merged),
      docChanged: changed,
    );
    var next = current;
    if (changed) {
      await _store.saveDoc(merged);
      next = current.copyWith(doc: _store.savedDoc(merged));
      // Lo que llega de fuera se anima en silencio (sin celebración).
      ref.read(remoteChangeProvider.notifier).bump();
      state = AsyncData(next);
    }
    await _purgeRecipientScopes(merged);
    final fromOther = fromNode != identity.node;
    if (fromOther && !identity.paired) {
      final paired = identity.copyWith(paired: true);
      await _store.saveIdentity(paired);
      state = AsyncData(next.copyWith(identity: paired));
    }
    return summary;
  });

  Future<FamilyState> _requireFamily() async {
    await _store.assertWritable();
    await _recoverProtection();
    await _resumeRecipientPurge();
    final current = await _current();
    if (!current.hasFamily) {
      throw const NoFamilyException();
    }
    return current;
  }

  // ------------------------------------------------------ altas y cambios

  /// Escribe en el documento y guarda. [change] devuelve el mismo documento
  /// si no hay nada que cambiar.
  Future<bool> _commit(
    FamilyDoc Function(FamilyDoc doc, HlcClock clock) change, {
    bool cascade = false,
  }) => _serialCommonWrite(() => _commitNow(change, cascade: cascade));

  Future<bool> _commitNow(
    FutureOr<FamilyDoc> Function(FamilyDoc doc, HlcClock clock) change, {
    bool cascade = false,
  }) async {
    final current = await _requireFamily();
    final before = cascade ? await _store.cascadeDoc(current.doc) : current.doc;
    if (!identical(before, current.doc)) {
      final latest = _store.latestStoredStamp(before);
      if (latest != null && latest > _clock!.last) _clock!.receive(latest);
    }
    final next = await change(before, _clock!);
    if (identical(next, before)) {
      return false;
    }
    if (cascade) {
      await _store.saveCascadeDoc(before, next);
    } else {
      await _store.saveDoc(next);
    }
    state = AsyncData(current.copyWith(doc: _store.savedDoc(next)));
    return true;
  }

  /// Da de alta o cambia una persona. Solo se escriben los campos que
  /// cambian, y si cambia su fecha de cumpleaños también la de su ocasión.
  /// En el alta se aceptan `inReparto` y `skipOccasions`. En una persona ya
  /// existente se conservan explícitamente los valores Y sellos guardados de
  /// ambos, aunque [recipient] traiga otros valores (o los predeterminados).
  /// Para cambiarlos usa [setRecipientInReparto] y [setRecipientSkipOccasion].
  /// Así un editor abierto antes de una sincronización no pisa sus cambios.
  ///
  /// Lanza [DevicePersonException] (y no escribe nada) si con esto se
  /// archivaría a la persona de un móvil de la familia.
  Future<void> upsertRecipient(Recipient recipient) => _protectionSerial(
    () => _commitNow((doc, clock) async {
      if (recipient.archived) {
        await _refuseArchivingDevicePerson(doc, recipient.id);
      }
      return _withRecipient(doc, clock, recipient);
    }),
  );

  /// Lanza [DevicePersonException] si [id] es de una persona que existe, es
  /// dueña de un móvil de la familia (`FamilyState.isDevicePerson`) y todavía
  /// no está archivada. Recuperarla, o tocar a una que ya llegó archivada,
  /// no lanza.
  Future<void> _refuseArchivingDevicePerson(FamilyDoc doc, String id) async {
    final record = doc.record(Collections.recipients, id);
    if (record == null || record.isDeleted || record['archived'] == true) {
      return;
    }
    await _refuseDevicePerson(doc, id);
  }

  Future<void> _refuseDevicePerson(FamilyDoc doc, String id) async {
    final registry = await _store.readDevicePersonView(doc);
    final device = (await _store.readSyncV2())?.deviceId;
    final selfId = (await _current()).identity?.selfRecipientId;
    final registrySelf = device == null || device == registry?.me
        ? registry?.myPerson
        : registry?.member(device)?.personId;
    final owner = selfId == id || registrySelf == id
        ? DevicePersonOwner.thisDevice
        : otherActiveDevicePeople(
            registry,
            excludingDevice: device,
          ).contains(id)
        ? DevicePersonOwner.otherDevice
        : null;
    if (owner != null) {
      throw DevicePersonException(recipientId: id, owner: owner);
    }
    if (registry == null &&
        (device != null || syncProtocolOf(doc) == kSyncProtocolV2)) {
      throw ProtectedPersonException(
        id,
        reason: ProtectedPersonReason.registryUnavailable,
      );
    }
  }

  /// Incluye o saca a una persona de Reparto sin archivar ni borrar nada.
  /// No hace nada si la persona no existe o está borrada.
  Future<void> setRecipientInReparto(String id, bool inReparto) => _commit(
    (doc, clock) => _writeChanged(doc, clock, Collections.recipients, id, {
      'inReparto': inReparto,
    }, onlyExisting: true),
  );

  /// Cambia una sola ocasión (id estable, nunca el nombre traducido).
  /// `skip: false` conserva una lápida con HLC: no se elimina la entrada,
  /// para que una exclusión antigua no reaparezca al sincronizar.
  /// No hace nada si el id de ocasión no existe o su registro está borrado.
  Future<void> setRecipientSkipOccasion(
    String id,
    String occasionKey, {
    required bool skip,
  }) => _commit((doc, clock) {
    final occasion = doc.record(Collections.occasions, occasionKey);
    if (occasion == null || Occasion.fromRecord(occasion) == null) return doc;
    return _writeChanged(doc, clock, Collections.recipients, id, {
      Recipient.skipOccasionField(occasionKey): skip,
    }, onlyExisting: true);
  });

  FamilyDoc _withRecipient(FamilyDoc doc, HlcClock clock, Recipient recipient) {
    final fields = recipient.toFields();
    if (doc.record(Collections.recipients, recipient.id) != null) {
      // Un editor puede reconstruir Recipient con los valores por defecto.
      // Conservamos en doc inReparto y TODAS las entradas skipOccasions,
      // incluidas las lápidas false, sin volver a sellarlas ni materializar
      // los valores por defecto de documentos antiguos.
      fields.removeWhere(
        (key, _) =>
            key == 'inReparto' ||
            key.startsWith(Recipient.skipOccasionFieldPrefix),
      );
    }
    var next = _writeChanged(
      doc,
      clock,
      Collections.recipients,
      recipient.id,
      fields,
    );
    final month = recipient.birthMonth;
    final day = recipient.birthDay;
    if (month != null && day != null) {
      for (final occasion in FamilyView.fromDoc(next).occasions) {
        if (occasion.kind == OccasionKind.birthday &&
            occasion.recipientId == recipient.id &&
            (occasion.month != month || occasion.day != day)) {
          next = _writeChanged(
            next,
            clock,
            Collections.occasions,
            occasion.id,
            {'month': month, 'day': day},
          );
        }
      }
    }
    final previous = doc.record(Collections.recipients, recipient.id);
    if (previous?['name'] != recipient.name ||
        previous?['colorIndex'] != recipient.colorIndex) {
      return reconcileGiverCopies(next, clock, onlyPersonId: recipient.id);
    }
    return next;
  }

  /// Da de alta o cambia a alguien que regala.
  /// El vínculo se cambia únicamente con [linkGiver] y [unlinkGiver].
  Future<void> upsertGiver(Giver giver) => _commit((doc, clock) {
    final record = doc.record(Collections.givers, giver.id);
    if (record?.isDeleted == true ||
        (record == null && giver.id.startsWith(Giver.personIdPrefix))) {
      return doc;
    }
    final fields = giver.toFields()..remove(Giver.recipientIdField);
    if (record?[Giver.recipientIdField] is String) {
      fields
        ..remove('name')
        ..remove('colorIndex');
    }
    return _writeChanged(doc, clock, Collections.givers, giver.id, fields);
  });

  /// Links a giver only if its current link matches [expectedPersonId].
  /// A null expectation requires an unlinked giver.
  Future<bool> linkGiver(
    String giverId,
    String recipientId, {
    String? expectedPersonId,
  }) => _commit((doc, clock) {
    final view = FamilyView.fromDoc(doc);
    final person = view.allRecipientsById[recipientId];
    final giver = view.giversByOriginalId[giverId];
    if (person == null ||
        giver == null ||
        giver.recipientId != expectedPersonId) {
      return doc;
    }
    return doc.setChanged(clock, Collections.givers, giverId, {
      Giver.recipientIdField: recipientId,
      'name': person.name,
      'colorIndex': person.colorIndex,
    });
  });

  /// Clears the expected link and returns the name preserved on the giver.
  /// Returns null if the giver is gone or its link has changed.
  Future<String?> unlinkGiver(
    String giverId, {
    required String expectedPersonId,
  }) async {
    String? retainedName;
    await _commit((doc, clock) {
      final giver = FamilyView.fromDoc(doc).giversByOriginalId[giverId];
      if (giver == null || giver.recipientId != expectedPersonId) return doc;
      retainedName = giver.name;
      return doc.setChanged(clock, Collections.givers, giverId, {
        Giver.recipientIdField: null,
        'name': giver.name,
        'colorIndex': giver.colorIndex,
      });
    });
    return retainedName;
  }

  /// Da de alta o cambia una ocasión. Con [original], aplica solo los campos
  /// que el editor cambió desde que se abrió, sobre el documento actual.
  /// Para cambiar el presupuesto de una ocasión existente, pasa [original]
  /// o usa [setOccasionBudget].
  Future<void> upsertOccasion(Occasion occasion, {Occasion? original}) =>
      _commit((doc, clock) {
        assert(original == null || original.id == occasion.id);
        final fields = occasion.toFields();
        if (original != null) {
          if (_isGone(doc, Collections.occasions, occasion.id)) return doc;
          final before = original.toFields();
          fields.removeWhere(
            (key, value) =>
                canonicalJsonOf(value) == canonicalJsonOf(before[key]),
          );
        }
        final budgetEdited =
            original != null && fields.containsKey(Occasion.budgetField);
        final exists = doc.record(Collections.occasions, occasion.id) != null;
        if (exists) {
          fields.remove(Occasion.budgetField);
        }
        final next = _writeChanged(
          doc,
          clock,
          Collections.occasions,
          occasion.id,
          fields,
        );
        // Un cambio explícito de presupuesto lleva un sello incluso para null.
        return budgetEdited
            ? next.set(clock, Collections.occasions, occasion.id, {
                Occasion.budgetField: occasion.budgetCents,
              })
            : next;
      });

  /// Cambia solo el presupuesto de una ocasión existente. `null` lo quita
  /// con un sello propio, aunque el documento local aún no tenga el campo.
  Future<void> setOccasionBudget(String id, int? cents) =>
      _commit((doc, clock) {
        final budgetCents = Occasion.checkedBudgetCents(cents);
        if (_isGone(doc, Collections.occasions, id)) return doc;
        return doc.set(clock, Collections.occasions, id, {
          Occasion.budgetField: budgetCents,
        });
      });

  /// Da de alta o cambia un regalo. Con [original], solo aplica los campos
  /// que el editor cambió desde que se abrió, sobre el documento actual.
  /// Los demás conservan tanto su valor como su sello, aunque lleguen cambios
  /// remotos mientras se edita o se espera en la cola de escrituras.
  ///
  /// Devuelve `false` si el regalo ya está eliminado, su persona ya no existe
  /// o la pareja final de destinatario y quien regala es inválida. La pareja
  /// se valida en el alta y cuando cambia uno de los dos roles. Devuelve
  /// `true` si se guardó o si no había nada que cambiar.
  Future<bool> upsertGift(Gift gift, {Gift? original}) async =>
      await upsertGiftResult(gift, original: original) == GiftWriteResult.saved;

  /// Like [upsertGift], but says why a save was rejected.
  Future<GiftWriteResult> upsertGiftResult(Gift gift, {Gift? original}) =>
      _upsertGift(gift, original: original);

  /// Saves a form and confirms its People choice in the same protected edit.
  /// Throws [GiverPersonNeedsPublicAdd] if a protected gift needs a public
  /// giver. Retry explicitly after [addPersonAsGiver].
  Future<GiftWriteResult> upsertGiftWithGiverPerson(
    Gift gift,
    String giverPersonId, {
    Gift? original,
  }) => _upsertGift(gift, original: original, giverPersonId: giverPersonId);

  Future<GiftWriteResult> _upsertGift(
    Gift gift, {
    Gift? original,
    String? giverPersonId,
  }) {
    assert(original == null || original.id == gift.id);
    final fields = gift.toFields();
    if (original != null) {
      final before = original.toFields();
      fields.removeWhere(
        (key, value) => canonicalJsonOf(value) == canonicalJsonOf(before[key]),
      );
    }
    return _protectionSerial(() async {
      return _writeGiftFields(
        await _requireFamily(),
        gift,
        fields,
        original,
        giverPersonId: giverPersonId,
      );
    });
  }

  /// Updates only the gift's `giverId` field. Null leaves it unassigned.
  Future<GiftWriteResult> setGiftGiver(String giftId, String? giverId) =>
      _assignGiftGiver(giftId, {'giverId': giverId});

  /// Resolves the person's giver against the current gift and protection
  /// state and updates only the gift's `giverId` field. A public gift can
  /// restore or create its giver as part of the edit.
  /// A protected gift without an active link throws [GiverPersonNeedsPublicAdd].
  Future<GiftWriteResult> assignPersonAsGiver(
    String giftId,
    String recipientId,
  ) => _assignGiftGiver(giftId, {}, giverPersonId: recipientId);

  Future<GiftWriteResult> _assignGiftGiver(
    String giftId,
    Map<String, Object?> fields, {
    String? giverPersonId,
  }) => _protectionSerial(() async {
    final current = await _requireFamily();
    if (current.hiddenGiftIds.contains(giftId)) {
      return GiftWriteResult.giftUnavailable;
    }
    final record =
        await _secretGift(giftId) ??
        current.doc.record(Collections.gifts, giftId);
    if (record == null) return GiftWriteResult.giftUnavailable;
    if (record.isDeleted) return GiftWriteResult.giftDeleted;
    final gift = Gift.fromRecord(record);
    if (gift == null) return GiftWriteResult.giftUnavailable;
    return _writeGiftFields(
      current,
      gift,
      fields,
      gift,
      giverPersonId: giverPersonId,
    );
  });

  Future<GiftWriteResult> _writeGiftFields(
    FamilyState current,
    Gift gift,
    Map<String, Object?> fields,
    Gift? original, {
    String? giverPersonId,
  }) async {
    // Quien solo regala no recibe regalos (1.0.6): ni nuevos ni movidos a
    // él. Un regalo que ya era suyo se puede seguir editando.
    final target = fields['recipientId'];
    if (target is String &&
        target != original?.recipientId &&
        receivesNoGifts(current.doc, target)) {
      return GiftWriteResult.recipientUnavailable;
    }
    final context = await _protectionContext(current.doc);
    final checkReview =
        isStoreReviewEnabled &&
        fields['status'] == GiftStatus.delivered.name &&
        await _matchesDeliveredCount(
          current,
          context,
          gift.id,
          kReviewDeliveryTarget - 1,
          targetDelivered: false,
        );
    final outcome = context != null
        ? await _upsertProtectedAware(
            current,
            context,
            gift,
            fields,
            original,
            giverPersonId: giverPersonId,
          )
        : await _upsertCommonGift(
            current,
            gift,
            fields,
            original,
            giverPersonId: giverPersonId,
          );
    final savedId = outcome.savedId;
    if (checkReview && savedId != null) {
      await _reviewDeliverySaved(current.listId!, savedId, context != null);
    }
    return outcome.result;
  }

  Future<_GiftWriteOutcome> _upsertCommonGift(
    FamilyState current,
    Gift gift,
    Map<String, Object?> fields,
    Gift? original, {
    required String? giverPersonId,
  }) async {
    final doc = current.doc;
    final previous = doc.record(Collections.gifts, gift.id);
    final recipientId =
        fields['recipientId'] as String? ??
        previous?['recipientId'] as String? ??
        gift.recipientId;
    if (previous?.isDeleted == true) {
      return (result: GiftWriteResult.giftDeleted, savedId: null);
    }
    if (original != null && previous == null) {
      return (result: GiftWriteResult.giftUnavailable, savedId: null);
    }
    if (_isDeletedRecord(doc, Collections.recipients, recipientId)) {
      return (result: GiftWriteResult.recipientUnavailable, savedId: null);
    }
    // Even without v2 credentials a requested policy fails closed.
    if (_store.supportsSecretScopes) {
      final slots = await _store.readSlots();
      final keyring = await ref
          .read(deviceKeysStoreProvider)
          .readKeyring(doc.listId);
      for (final person in {recipientId, previous?['recipientId']}) {
        if (person is String &&
            (publishedPolicy(doc, person) != null ||
                slots.people.contains(person) ||
                keyring.people.contains(person))) {
          throw ProtectedPersonException(
            person,
            reason: ProtectedPersonReason.requiresV2,
          );
        }
      }
    }
    final (result, prepared) = _prepareGiftGiver(
      doc,
      recipientId,
      fields,
      previous: previous,
      giverPersonId: giverPersonId,
      protected: false,
    );
    if (result != GiftWriteResult.saved) return (result: result, savedId: null);
    final next = prepared.setChanged(
      _clock!,
      Collections.gifts,
      gift.id,
      fields,
    );
    if (!identical(next, doc)) {
      await _store.saveDoc(next);
      state = AsyncData(current.copyWith(doc: _store.savedDoc(next)));
    }
    return (result: GiftWriteResult.saved, savedId: gift.id);
  }

  /// Runs inside the protection queue after resolving the real recipient.
  (GiftWriteResult, FamilyDoc) _prepareGiftGiver(
    FamilyDoc doc,
    String recipientId,
    Map<String, Object?> fields, {
    required SyncRecord? previous,
    required String? giverPersonId,
    required bool protected,
  }) {
    if (giverPersonId != null) {
      final view = FamilyView.fromDoc(doc);
      final person = view.allRecipientsById[giverPersonId];
      if (person == null) return (GiftWriteResult.giverPersonUnavailable, doc);
      if (person.archived) return (GiftWriteResult.giverPersonArchived, doc);
      if (person.id == recipientId) return (GiftWriteResult.invalidPair, doc);
      final existing = view.giverForPerson(person.id);
      if (existing != null && !existing.archived) {
        fields['giverId'] = existing.id;
        return (GiftWriteResult.saved, doc);
      }
      if (protected) throw GiverPersonNeedsPublicAdd(person.id);
      final giver = existing ?? _newPersonGiver(doc, person);
      fields['giverId'] = giver.id;
      final next = doc.setChanged(
        _clock!,
        Collections.givers,
        giver.id,
        existing == null ? giver.toFields() : {'archived': false},
      );
      return (GiftWriteResult.saved, next);
    }
    final oldId = previous?['giverId'];
    final id = fields.containsKey('giverId') ? fields['giverId'] : oldId;
    final selectingGiver = previous == null || id != oldId;
    if (id is! String ||
        (!selectingGiver && recipientId == previous['recipientId'])) {
      return (GiftWriteResult.saved, doc);
    }
    final record = doc.record(Collections.givers, id);
    final giver = record == null ? null : Giver.fromRecord(record);
    if (giver == null) return (GiftWriteResult.giverUnavailable, doc);
    if (giver.recipientId == recipientId) {
      return (GiftWriteResult.invalidPair, doc);
    }
    if (selectingGiver && giver.archived) {
      return (GiftWriteResult.giverArchived, doc);
    }
    return (GiftWriteResult.saved, doc);
  }

  Giver _newPersonGiver(FamilyDoc doc, Recipient person) => Giver(
    id: Giver.nextPersonGiverId(doc, person.id),
    name: person.name,
    colorIndex: person.colorIndex,
    householdPays: false,
    archived: false,
    recipientId: person.id,
  );

  /// Explicitly adds or restores a person's public giver without editing gifts.
  /// Returns its original record, or null if the person is unavailable.
  Future<Giver?> addPersonAsGiver(String personId) async {
    Giver? result;
    await _commit((doc, clock) {
      final view = FamilyView.fromDoc(doc);
      final person = view.allRecipientsById[personId];
      if (person == null || person.archived) return doc;
      final existing = view.giverForPerson(personId);
      final giver = existing ?? _newPersonGiver(doc, person);
      final next = existing == null
          ? doc.setChanged(
              clock,
              Collections.givers,
              giver.id,
              giver.toFields(),
            )
          : doc.setChanged(clock, Collections.givers, giver.id, {
              'archived': false,
            });
      result = Giver.fromRecord(next.record(Collections.givers, giver.id)!)!
          .withPersonDetails(person);
      return next;
    });
    return result;
  }

  Future<bool> _matchesDeliveredCount(
    FamilyState family,
    _ProtectionContext? context,
    String giftId,
    int expectedCount, {
    required bool targetDelivered,
  }) async {
    if (context == null && syncProtocolOf(family.doc) == kSyncProtocolV2) {
      return false;
    }
    try {
      final delivered = context == null
          ? family.view.allGifts
                .where((gift) => gift.status == GiftStatus.delivered)
                .map((gift) => gift.id)
          : _deliveredGiftIds(
              (await _projectAuthorized(family.doc, context)).doc,
              family.hiddenGiftIds,
            );
      var count = 0;
      var foundGift = false;
      for (final id in delivered) {
        if (++count > expectedCount) return false;
        if (id == giftId) {
          if (!targetDelivered) return false;
          foundGift = true;
        }
      }
      return count == expectedCount && foundGift == targetDelivered;
    } on Object {
      return false;
    }
  }

  static Iterable<String> _deliveredGiftIds(
    FamilyDoc doc,
    Set<String> hiddenGiftIds,
  ) sync* {
    for (final record
        in doc.collections[Collections.gifts]?.values ?? const <SyncRecord>[]) {
      if (record['status'] != GiftStatus.delivered.name ||
          hiddenGiftIds.contains(record.id)) {
        continue;
      }
      final gift = Gift.fromRecord(record);
      if (gift != null &&
          !_isDeletedRecord(doc, Collections.recipients, gift.recipientId)) {
        yield gift.id;
      }
    }
  }

  Future<void> _reviewDeliverySaved(
    String familyId,
    String giftId,
    bool hasProtectionContext,
  ) async {
    try {
      final current = state.asData?.value;
      if (current == null || current.listId != familyId) return;
      final context = hasProtectionContext
          ? await _protectionContext(current.doc)
          : null;
      if ((hasProtectionContext && context == null) ||
          !await _matchesDeliveredCount(
            current,
            context,
            giftId,
            kReviewDeliveryTarget,
            targetDelivered: true,
          ) ||
          !ref.mounted) {
        return;
      }
      unawaited(
        ref
            .read(reviewServiceProvider)
            .deliverySaved(
              familyId: familyId,
              before: kReviewDeliveryTarget - 1,
              after: kReviewDeliveryTarget,
            ),
      );
    } on Object {
      // Rating is optional even after the gift has been saved.
    }
  }

  /// Cambia el estado de un regalo. Devuelve `false` (y no escribe nada) si
  /// el regalo no existe o ya está eliminado.
  Future<bool> setGiftStatus(String id, GiftStatus status) async {
    if (!_store.supportsSecretScopes) {
      var exists = true;
      await _commit((doc, clock) {
        if (!_isAlive(doc, Collections.gifts, id)) {
          exists = false;
          return doc;
        }
        return _writeChanged(doc, clock, Collections.gifts, id, {
          'status': status.name,
        }, onlyExisting: true);
      });
      return exists;
    }
    final record = await _protectionSerial<SyncRecord?>(() async {
      final current = await _requireFamily();
      return await _secretGift(id) ?? current.doc.record(Collections.gifts, id);
    });
    if (record != null && !record.isDeleted) {
      final original = Gift.fromRecord(record);
      if (original == null) return false;
      final updated = Gift.fromRecord(
        SyncRecord(
          id: id,
          fields: {
            ...record.fields,
            'status': FieldValue(
              value: status.name,
              stamp: record.fields.values.first.stamp,
            ),
          },
        ),
      )!;
      return upsertGift(updated, original: original);
    }
    return false;
  }

  /// Archiva (o recupera, con `archived: false`) a una persona.
  ///
  /// Lanza [DevicePersonException] (y no escribe nada) al archivar a la
  /// persona de un móvil de la familia. Recuperarla siempre se puede.
  Future<void> archiveRecipient(String id, {bool archived = true}) =>
      _protectionSerial(
        () => _commitNow((doc, clock) async {
          if (archived) {
            await _refuseArchivingDevicePerson(doc, id);
          }
          return _writeChanged(doc, clock, Collections.recipients, id, {
            'archived': archived,
          }, onlyExisting: true);
        }),
      );

  /// Archiva (o recupera) a alguien que regala.
  Future<void> archiveGiver(String id, {bool archived = true}) =>
      _archive(Collections.givers, id, archived);

  /// Archiva (o recupera) una ocasión.
  Future<void> archiveOccasion(String id, {bool archived = true}) =>
      _archive(Collections.occasions, id, archived);

  Future<void> _archive(String collection, String id, bool archived) => _commit(
    (doc, clock) => _writeChanged(doc, clock, collection, id, {
      'archived': archived,
    }, onlyExisting: true),
  );

  /// Borra un regalo (queda una lápida). No hace nada si no existe.
  Future<void> deleteGift(String id) async {
    if (await _deleteSecretGift(id)) return;
    await _commit((doc, clock) {
      final record = doc.record(Collections.gifts, id);
      if (record == null || record.isDeleted) {
        return doc;
      }
      return doc.delete(clock, Collections.gifts, id);
    });
  }

  // ------------------------------------------- borrar un regalo con Deshacer

  /// Cuánto dura el aviso con «Deshacer» tras borrar un regalo; hasta que
  /// caduca no se escribe la lápida.
  static const Duration undoWindow = Duration(seconds: 7);

  /// Cuánto se ve el aviso: menos que [undoWindow], para que «Deshacer» no
  /// se pueda pulsar cuando ya no hace nada.
  static const Duration undoNoticeDuration = Duration(seconds: 5);

  final Map<String, Timer> _pending = <String, Timer>{};
  _FlushOnBackground? _flushObserver;

  /// Quita un regalo de la vista y deja la escritura de su lápida para
  /// cuando caduque [undoWindow] (o la app pase a segundo plano). Mientras
  /// tanto el contenido sigue en memoria y [undoDeleteGift] lo devuelve tal
  /// cual. Devuelve `false` si el regalo no existe o ya estaba eliminado.
  Future<bool> deleteGiftWithUndo(String id) {
    if (!_store.supportsSecretScopes) return _deletePublicGiftWithUndo(id);
    return _deleteGiftWithProtection(id);
  }

  Future<bool> _deletePublicGiftWithUndo(String id) {
    final result = _serial(() => _deleteGiftWithUndo(id));
    if (_store.durableGiftDeletes) {
      _deleteIntents[id] = result;
      unawaited(
        result.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
          if (identical(_deleteIntents[id], result)) _deleteIntents.remove(id);
        }),
      );
    }
    return result;
  }

  /// Intenciones de borrado duraderas cuya escritura aún no terminó.
  /// «Deshacer» espera solo a la de su regalo, no a toda la cola [_serial].
  final Map<String, Future<bool>> _deleteIntents = <String, Future<bool>>{};

  Future<bool> _deleteGiftWithUndo(String id) async {
    final current = await _requireFamily();
    if (!_isAlive(current.doc, Collections.gifts, id) ||
        _pending.containsKey(id)) {
      return false;
    }
    if (_store.durableGiftDeletes) {
      final deleted = current.doc.delete(_clock!, Collections.gifts, id);
      await _store.saveGiftDeleteIntent(current.doc, deleted, id, undoWindow);
      state = AsyncData(current.copyWith(doc: _store.savedDoc(deleted)));
      return true;
    }
    _pending[id] = Timer(undoWindow, () => unawaited(_commitPending(id)));
    _observeLifecycle();
    state = AsyncData(
      current.copyWith(hiddenGiftIds: {...current.hiddenGiftIds, id}),
    );
    return true;
  }

  /// Devuelve el regalo que se acaba de borrar si su lápida aún no se
  /// escribió. Devuelve `false` si ya era tarde.
  Future<bool> undoDeleteGift(String id) async {
    if (_store.durableGiftDeletes) {
      // La cancelación va directa a la cola cifrada, fuera de [_serial]: una
      // edición que espera a la red no puede dejar vencer antes la intención.
      final intent = _deleteIntents[id];
      if (intent != null) {
        try {
          await intent;
        } on Object {
          // Sin intención duradera no hay nada que cancelar.
        }
      }
      final undone = await _store.undoGiftDeleteIntent(id);
      if (undone) {
        // Solo la vista va en orden con las demás escrituras.
        await _serial(() async {
          if (!ref.mounted) return;
          final current = await _current();
          if (!ref.mounted) return;
          state = AsyncData(
            current.copyWith(doc: _store.savedDoc(current.doc)),
          );
        });
      }
      return undone;
    }
    return _serial(() => _undoPendingDelete(id));
  }

  Future<bool> _undoPendingDelete(String id) async {
    final timer = _pending.remove(id);
    if (timer == null) {
      return false;
    }
    timer.cancel();
    final current = await _current();
    state = AsyncData(
      current.copyWith(hiddenGiftIds: {...current.hiddenGiftIds}..remove(id)),
    );
    return true;
  }

  /// Escribe ya las lápidas de los regalos que esperan: al pasar la app a
  /// segundo plano o al volver, para que cerrarla no deje el borrado a medias.
  Future<void> flushPendingDeletes() async {
    for (final id in _pending.keys.toList()) {
      await _commitPending(id);
    }
  }

  Future<void> _commitPending(String id) => _protectionSerial(() async {
    final timer = _pending.remove(id);
    if (timer == null) {
      return;
    }
    timer.cancel();
    final deletedSecret = await _deleteSecretGiftNow(id);
    final current = await _current();
    var doc = current.doc;
    if (!deletedSecret && _isAlive(doc, Collections.gifts, id)) {
      doc = doc.delete(_clock!, Collections.gifts, id);
      await _store.saveDoc(doc);
      doc = _store.savedDoc(doc);
    }
    state = AsyncData(
      current.copyWith(
        doc: doc,
        hiddenGiftIds: {...current.hiddenGiftIds}..remove(id),
      ),
    );
  });

  void _observeLifecycle() {
    if (_flushObserver != null) {
      return;
    }
    try {
      final observer = _FlushOnBackground(this);
      WidgetsBinding.instance.addObserver(observer);
      _flushObserver = observer;
    } on Object {
      // Sin motor de widgets (pruebas de lógica): solo manda el temporizador.
    }
  }

  void _dropPending() {
    for (final timer in _pending.values) {
      timer.cancel();
    }
    _pending.clear();
    final observer = _flushObserver;
    if (observer != null) {
      WidgetsBinding.instance.removeObserver(observer);
      _flushObserver = null;
    }
  }

  /// Elimina a una persona para siempre: su registro pasa a lápida (sin
  /// nombre, notas ni fecha), y también todos sus regalos, sus deseos y su
  /// ocasión de cumpleaños. Si era quien había pedido otros regalos, ese
  /// dato se borra de ellos. No hace nada si no existe o ya está eliminada.
  ///
  /// Lanza [DevicePersonException] (y no escribe nada) si es la persona de
  /// un móvil de la familia.
  Future<void> deleteRecipient(String id, {DeleteImpact? expectedImpact}) =>
      _deleteWithCascade(
        id,
        DeleteImpact.ofRecipient,
        expectedImpact: expectedImpact,
        person: true,
      );

  /// Deletes one original giver record and clears its gift assignments.
  /// This is the unit displayed by a row in Settings and Archive.
  /// Pass the impact shown in the dialog as [expectedImpact]. A changed set
  /// raises [DeleteImpactChanged] before either the common or a scope is saved.
  /// A reader without wish-plan support can block the cascade with
  /// [WishPlanError.devicesNeedUpdate].
  Future<void> deleteGiverAlias(String id, {DeleteImpact? expectedImpact}) =>
      _deleteWithCascade(
        id,
        DeleteImpact.ofGiverAlias,
        expectedImpact: expectedImpact,
      );

  /// Deletes one original giver record. See [deleteGiverAlias].
  Future<void> deleteGiver(String id) => deleteGiverAlias(id);

  /// Deletes every alias in a grouped column after confirming its impact.
  Future<void> deleteGiverColumn(
    String id, {
    required DeleteImpact expectedImpact,
  }) => _deleteWithCascade(
    id,
    DeleteImpact.ofGiverColumn,
    expectedImpact: expectedImpact,
  );

  /// The gifts, requests, birthday and giver history relevant to confirmation.
  Future<DeleteImpact> recipientDeleteImpact(String id) =>
      _deleteImpact(id, DeleteImpact.ofRecipient, person: true);

  /// The record and gifts that can be named in an original row's confirmation.
  Future<DeleteImpact> giverAliasDeleteImpact(String id) =>
      _deleteImpact(id, DeleteImpact.ofGiverAlias);

  /// The aliases and gifts that can be named in a grouped column's confirmation.
  Future<DeleteImpact> giverColumnDeleteImpact(String id) =>
      _deleteImpact(id, DeleteImpact.ofGiverColumn);

  Future<DeleteImpact> _deleteImpact(
    String id,
    DeleteImpact Function(FamilyView, String) impactOf, {
    bool person = false,
  }) => _protectionSerial(() async {
    final current = await _current();
    final doc = await _store.cascadeDoc(current.doc);
    final impact = impactOf(
      await _authorizedView(doc, includePending: true),
      id,
    );
    return impact.withPlans(
      await _affectedPlanIds(doc, person ? id : null, {
        if (!person) id,
        for (final giver in impact.affectedAliases) giver.id,
      }),
    );
  });

  // See the latest authorized impact inside the same queue as the write.
  Future<void> _deleteWithCascade(
    String id,
    DeleteImpact Function(FamilyView, String) impactOf, {
    required DeleteImpact? expectedImpact,
    bool person = false,
  }) => _protectionSerial(() async {
    final current = await _requireFamily();
    final before = await _store.cascadeDoc(current.doc);
    final collection = person ? Collections.recipients : Collections.givers;
    final impact = impactOf(
      await _authorizedView(before, includePending: true),
      id,
    );
    final aliases = {
      if (!person) id,
      for (final giver in impact.affectedAliases) giver.id,
    };
    final withPlans = impact.withPlans(
      await _affectedPlanIds(before, person ? id : null, aliases),
    );
    if (expectedImpact != null && !expectedImpact.matches(withPlans)) {
      throw DeleteImpactChanged(withPlans);
    }
    if (_isGone(before, collection, id)) return;
    if (person) await _refuseDevicePerson(before, id);
    final clock = HlcClock(node: _clock!.node, last: _clock!.last);
    final latest = _store.latestStoredStamp(before);
    if (latest != null && latest > clock.last) clock.receive(latest);
    // A live giver can have gift references before all its required fields
    // have arrived. Its id may be absent from the confirmation view
    // (see `aliases` above).
    FamilyDoc changeGifts(FamilyDoc doc, HlcClock clock) =>
        _cascadeGiftReferences(doc, clock, person ? id : null, aliases);
    var next = changeGifts(before, clock);
    if (person) {
      // Preserve the person's last name and color in their giver history.
      next = reconcileGiverCopies(next, clock, onlyPersonId: id);
      for (final record in _live(before, Collections.occasions)) {
        if (record['kind'] == OccasionKind.birthday.name &&
            record['recipientId'] == id) {
          next = next.delete(clock, Collections.occasions, record.id);
        }
      }
      next = next.deleteRecipientWithWishes(clock, id);
    }
    for (final alias in aliases) {
      next = next.delete(clock, collection, alias);
    }
    // A protected cascade can be replayed from its journal after an error.
    if (person && _store.supportsSecretScopes) _recipientPurgePending = true;
    final protected = await _saveProtectedCascade(before, next, changeGifts);
    if (!protected) await _store.saveCascadeDoc(before, next);
    _clock = clock;
    state = AsyncData(
      current.copyWith(
        doc: _store.savedDoc(next),
        protectionRevision: current.protectionRevision + (protected ? 1 : 0),
      ),
    );
    if (person) await _purgeRecipientScopes(next);
  });

  FamilyDoc _cascadeGiftReferences(
    FamilyDoc doc,
    HlcClock clock,
    String? personId,
    Set<String> aliases,
  ) {
    var next = doc;
    for (final record in _live(doc, Collections.gifts)) {
      if (personId != null && record['recipientId'] == personId) {
        next = next.delete(clock, Collections.gifts, record.id);
        continue;
      }
      final by = RequestedBy.fromFields(record['requestedBy']);
      final fields = <String, Object?>{
        if (personId != null &&
            by is RequestedByRecipient &&
            by.recipientId == personId)
          'requestedBy': null,
        if (aliases.contains(record['giverId'])) 'giverId': null,
      };
      if (fields.isNotEmpty) {
        next = next.setChanged(clock, Collections.gifts, record.id, fields);
      }
    }
    // Wish plans (ADR 0010) live in the secret scopes and get the same
    // treatment: a deleted person's plans are deleted; a deleted giver is
    // cleared from the plans that name it.
    if (personId != null) {
      next = tombstoneRecipientWishPlans(next, clock, personId);
    }
    for (final record in _live(next, ScopeCollections.wishPlans)) {
      if (aliases.contains(record['giverId'])) {
        next = next.setChanged(clock, ScopeCollections.wishPlans, record.id, {
          'giverId': null,
        });
      }
    }
    return next;
  }

  /// Elimina una ocasión para siempre: su registro pasa a lápida. Sus regalos
  /// no se borran: se quedan sin ocasión (siguen con su persona). No hace
  /// nada si no existe o ya está eliminada.
  Future<void> deleteOccasion(String id) => _commit((doc, clock) {
    if (_isGone(doc, Collections.occasions, id)) {
      return doc;
    }
    var next = doc;
    for (final record in _live(doc, Collections.gifts)) {
      if (record['occasionId'] == id) {
        next = next.setChanged(clock, Collections.gifts, record.id, {
          'occasionId': null,
        });
      }
    }
    return next.delete(clock, Collections.occasions, id);
  }, cascade: true);

  // ------------------------------------------------------- primer uso

  /// Crea las ocasiones de serie: las fijas que elija el usuario y un
  /// cumpleaños por cada persona con fecha.
  ///
  /// [kinds] son las fijas elegidas (Tió, Papá Noel, Reyes); sin ellas, las
  /// que se proponen para [region] (`ES`, `ES-CT`...). Los ids son fijos
  /// (`seed-tio`...), así que si dos móviles lo hacen no se duplican, y lo
  /// que ya existe no se toca.
  ///
  /// No guardan nombre (`name` vacío): cada móvil lo pone en su idioma al
  /// mostrarlas, según el tipo y, en los cumpleaños, la persona.
  Future<void> seedDefaultOccasions(
    String region, {
    Set<OccasionKind>? kinds,
  }) => _commit((doc, clock) => _withSeedOccasions(doc, clock, region, kinds));

  FamilyDoc _withSeedOccasions(
    FamilyDoc doc,
    HlcClock clock,
    String region,
    Set<OccasionKind>? kinds,
  ) {
    final chosen = kinds ?? suggestedOccasionKinds(region);
    var next = doc;
    final fixed = <(OccasionKind, int, int)>[
      (OccasionKind.tio, 12, 24),
      (OccasionKind.santa, 12, 25),
      (OccasionKind.kings, 1, 6),
    ];
    for (final (kind, month, day) in fixed) {
      if (!chosen.contains(kind)) {
        continue;
      }
      next = _createOccasion(
        next,
        clock,
        Occasion(
          id: 'seed-${kind.name}',
          kind: kind,
          rawKind: kind.name,
          name: kSeedOccasionName,
          month: month,
          day: day,
          recurring: true,
          archived: false,
        ),
      );
    }
    return _addBirthdays(next, clock);
  }

  /// Crea la ocasión de cumpleaños de cada persona con fecha que todavía no
  /// la tenga.
  Future<void> ensureBirthdayOccasions() =>
      _commit((doc, clock) => _addBirthdays(doc, clock));

  FamilyDoc _addBirthdays(FamilyDoc doc, HlcClock clock) {
    var next = doc;
    final view = FamilyView.fromDoc(doc);
    for (final recipient in view.recipients) {
      final month = recipient.birthMonth;
      final day = recipient.birthDay;
      if (month == null || day == null || recipient.archived) {
        continue;
      }
      final hasOne = view.occasions.any(
        (o) => o.kind == OccasionKind.birthday && o.recipientId == recipient.id,
      );
      if (hasOne) {
        continue;
      }
      next = _createOccasion(
        next,
        clock,
        Occasion(
          id: 'birthday-${recipient.id}',
          kind: OccasionKind.birthday,
          rawKind: OccasionKind.birthday.name,
          name: kSeedOccasionName,
          month: month,
          day: day,
          recurring: true,
          recipientId: recipient.id,
          archived: false,
        ),
      );
    }
    return next;
  }

  /// Crea la ocasión solo si no existe ya un registro con ese id.
  FamilyDoc _createOccasion(FamilyDoc doc, HlcClock clock, Occasion occasion) {
    if (doc.record(Collections.occasions, occasion.id) != null) {
      return doc;
    }
    return _writeChanged(
      doc,
      clock,
      Collections.occasions,
      occasion.id,
      occasion.toFields(),
    );
  }
}

/// Escribe las lápidas pendientes cuando la app pasa a segundo plano o vuelve.
class _FlushOnBackground with WidgetsBindingObserver {
  _FlushOnBackground(this._controller);

  final FamilyController _controller;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(_controller.flushPendingDeletes());
      case AppLifecycleState.inactive:
        break;
    }
  }
}

/// Si el registro existe y no es una lápida.
bool _isAlive(FamilyDoc doc, String collection, String id) {
  final record = doc.record(collection, id);
  return record != null && !record.isDeleted;
}

/// Si el registro existe y es una lápida.
bool _isDeletedRecord(FamilyDoc doc, String collection, String id) =>
    doc.record(collection, id)?.isDeleted ?? false;

/// Si el registro no existe o ya es una lápida.
bool _isGone(FamilyDoc doc, String collection, String id) {
  final record = doc.record(collection, id);
  return record == null || record.isDeleted;
}

/// Los registros vivos (no lápidas) de una colección.
Iterable<SyncRecord> _live(FamilyDoc doc, String collection) => [
  for (final record
      in doc.collections[collection]?.values ?? const <SyncRecord>[])
    if (!record.isDeleted) record,
];

/// Escribe en un registro solo los campos de [fields] cuyo valor cambia, con
/// `FamilyDoc.setChanged`. Si no cambia nada devuelve el mismo [doc]. Con
/// [onlyExisting], un registro que no existe o está borrado no se toca.
FamilyDoc _writeChanged(
  FamilyDoc doc,
  HlcClock clock,
  String collection,
  String id,
  Map<String, Object?> fields, {
  bool onlyExisting = false,
}) {
  if (onlyExisting) {
    final current = doc.record(collection, id);
    if (current == null || current.isDeleted) {
      return doc;
    }
  }
  return doc.setChanged(clock, collection, id, fields);
}

/// Controlador de la familia.
final familyControllerProvider =
    AsyncNotifierProvider<FamilyController, FamilyState>(FamilyController.new);
