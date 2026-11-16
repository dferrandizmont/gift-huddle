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
import '../../../core/sync/pairing_v2.dart'
    show keepProtocolV2, kSyncProtocolV2, syncProtocolOf;
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
    show localRegistryViewProvider;
import '../../sync/data/sync_transport_v2.dart' show kV2MaxSlotsPerWriter;
import '../domain/family_errors.dart';
import 'occasion_names.dart';
import 'remote_change.dart';
import 'self_person_change.dart';

export 'self_person_change.dart';

part 'person_protection.dart';

const _uuid = Uuid();

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
    bool authorized = false,
  }) : _authorized = authorized,
       view = FamilyView.fromDoc(
         authorized ? doc : _safeStateDoc(doc),
         hiddenGiftIds: hiddenGiftIds,
       );

  /// Primer arranque: todavía no hay familia.
  FamilyState.noFamily()
    : doc = FamilyDoc.empty(''),
      view = _emptyView,
      hiddenGiftIds = const <String>{},
      protectionRevision = 0,
      _authorized = false,
      identity = null;

  static final FamilyView _emptyView = FamilyView.fromDoc(FamilyDoc.empty(''));

  /// El documento.
  final FamilyDoc doc;
  final bool _authorized;

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
  /// - **Otro móvil de la familia:** [otherDevicePeople], que hoy está vacío.
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
  ///
  /// PENDIENTE (fase 2b/3): hoy siempre está vacío, porque la app no lo sabe
  /// de forma fiable. La identidad solo guarda el nombre del móvil con el
  /// que se emparejó (`peerName`), no su persona, y el registro firmado de
  /// móviles (`core/sync/device_registry.dart`) todavía no llega a este
  /// estado. Cuando llegue, esto devuelve el `personId` de la ficha de cada
  /// móvil activo de `RegistryView` que no sea este, y lo demás ya funciona.
  Set<String> get otherDevicePeople => const <String>{};

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
  );

  /// Copia con otro documento, identidad o regalos a la espera de borrarse.
  FamilyState copyWith({
    FamilyDoc? doc,
    FamilyIdentity? identity,
    Set<String>? hiddenGiftIds,
    int? protectionRevision,
  }) => FamilyState(
    doc: doc ?? this.doc,
    identity: identity ?? this.identity,
    hiddenGiftIds: hiddenGiftIds ?? this.hiddenGiftIds,
    protectionRevision: protectionRevision ?? this.protectionRevision,
    authorized: _authorized,
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

  FamilyStore get _store => ref.read(familyStoreProvider);
  Ref get _protectionRef => ref;
  set _protectionState(AsyncValue<FamilyState> value) => state = value;

  @override
  Future<FamilyState> build() async {
    final supportsRecovery = ref.read(recoverySupportedProvider);
    var writable = true;
    if (supportsRecovery) {
      await resumeRecoveryBeforeFamily(ref);
      final restoring = await ref.read(recoveryStoreProvider).readRestore();
      writable =
          !await _store.isTransferred() &&
          (restoring == null || restoring.phase == RecoveryPhase.active);
    }
    if (writable) await _store.recoverProtectionOperation();
    final stored = await _store.load();
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
    if (dirty.isNotEmpty && writable) {
      await _store.saveDoc(doc);
      doc = _store.savedDoc(doc);
    }
    return FamilyState(doc: doc, identity: stored.identity);
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

  /// A web snapshot replaces the visible candidate without generating a local
  /// action. Shares ordering with edits and adopts its latest logical clock.
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
    if (max != null) _clock!.receive(max);
    state = AsyncData(
      current.copyWith(doc: stored.doc, identity: stored.identity),
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
  }) => _serial(() async {
    final current = await _current();
    await requireNoPendingRestore(ref);
    final existing = current.identity;
    final same =
        existing != null && existing.listId == listId && existing.node == node;
    final identity = same
        ? existing.copyWith(
            peerName: peerName,
            paired: paired || existing.paired,
          )
        : FamilyIdentity(
            listId: listId,
            node: node,
            deviceName: deviceName.trim(),
            peerName: peerName,
            paired: paired,
          );
    await _store.saveFamily(
      StoredFamily(identity: identity, key: key, doc: doc),
    );
    _adopt(identity, key, doc);
    state = AsyncData(FamilyState(doc: doc, identity: identity));
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
    if (identity == null || !identity.paired) {
      return;
    }
    final next = identity.copyWith(paired: false);
    await _store.saveIdentity(next);
    state = AsyncData(current.copyWith(identity: next));
  });

  /// Cambia el nombre con que este móvil se presenta a los demás. Vacío no
  /// hace nada.
  Future<void> setDeviceName(String name) => _serial(() async {
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
            await _store.saveSelfRecipient(personId);
            state = AsyncData(
              current.copyWith(identity: identity.withSelfRecipient(personId)),
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

  /// Recupera un cambio de «Yo» bajo el cerrojo v2 y la cola de escrituras,
  /// actualiza también la identidad en memoria y relee sus vistas derivadas.
  /// Ejecuta después [transaction] sin soltar el cerrojo: la carga local y
  /// la siguiente operación no pueden intercalarse con otro cambio de «Yo».
  /// [transaction] puede usar la cola de escrituras, pero no tomar el cerrojo.
  Future<T> withRecoveredSelfPersonChange<T>(
    Future<T> Function() transaction,
  ) => ref.read(v2FamilyLockProvider).run(() async {
    await _serial(_finishSelfPersonChange);
    return transaction();
  });

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
          if (identity.selfRecipientId != person) {
            state = AsyncData(
              current.copyWith(identity: identity.withSelfRecipient(person)),
            );
          }
        }
        // Estas vistas observan FamilyController. Invalidarlas por el
        // contenedor evita declarar una dependencia circular desde su Ref.
        ref.container.invalidate(localRegistryViewProvider);
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
    state = AsyncData(FamilyState.noFamily());
  });

  /// Mezcla un documento recibido de otro móvil y guarda el resultado.
  ///
  /// Lanza [ImportClockDriftException] si el reloj del otro móvil va más de
  /// un día adelantado, y [NoFamilyException] si todavía no hay familia.
  Future<ImportSummary> mergeRemote(
    FamilyDoc remote, {
    required String fromNode,
  }) => _serial(() async {
    _store.requireMobileOperation('import');
    final current = await _requireFamily();
    final identity = current.identity!;
    final remoteMax = remote.maxStamp;
    if (remoteMax != null) {
      // Antes de tocar nada: si el otro móvil va muy adelantado se rechaza.
      try {
        _clock!.receive(remoteMax);
      } on HlcDriftException catch (e) {
        throw ImportClockDriftException(ahead: e.lead);
      }
    }
    var merged = current.doc.merge(remote);
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
    final changed = merged.canonicalJson() != current.doc.canonicalJson();
    final next = changed ? current.copyWith(doc: merged) : current;
    final summary = ImportSummary.between(
      await _authorizedView(current.doc, policySource: merged),
      await _authorizedView(merged),
      docChanged: changed,
    );
    if (changed) {
      await _store.saveDoc(merged);
    }
    var nextState = next;
    final fromOther = fromNode != identity.node;
    if (fromOther && !identity.paired) {
      final paired = identity.copyWith(paired: true);
      await _store.saveIdentity(paired);
      nextState = nextState.copyWith(identity: paired);
    }
    if (changed) {
      // Lo que llega de fuera se anima en silencio (sin celebración).
      ref.read(remoteChangeProvider.notifier).bump();
    }
    state = AsyncData(nextState);
    return summary;
  });

  Future<FamilyState> _requireFamily() async {
    await _store.assertWritable();
    await _recoverProtection();
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
  }) => _serial(() async {
    final current = await _requireFamily();
    final before = cascade ? await _store.cascadeDoc(current.doc) : current.doc;
    if (!identical(before, current.doc)) {
      final latest = _store.latestStoredStamp(before);
      if (latest != null && latest > _clock!.last) _clock!.receive(latest);
    }
    final next = change(before, _clock!);
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
  });

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
  Future<void> upsertRecipient(Recipient recipient) => _commit((doc, clock) {
    if (recipient.archived) {
      _refuseArchivingDevicePerson(doc, recipient.id);
    }
    return _withRecipient(doc, clock, recipient);
  });

  /// Lanza [DevicePersonException] si [id] es de una persona que existe, es
  /// dueña de un móvil de la familia (`FamilyState.isDevicePerson`) y todavía
  /// no está archivada. Recuperarla, o tocar a una que ya llegó archivada,
  /// no lanza.
  void _refuseArchivingDevicePerson(FamilyDoc doc, String id) {
    final record = doc.record(Collections.recipients, id);
    if (record == null || record.isDeleted || record['archived'] == true) {
      return;
    }
    _refuseDevicePerson(id);
  }

  void _refuseDevicePerson(String id) {
    final owner = state.value?.devicePersonOwner(id);
    if (owner != null) {
      throw DevicePersonException(recipientId: id, owner: owner);
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
    return next;
  }

  /// Da de alta o cambia a alguien que regala.
  Future<void> upsertGiver(Giver giver) => _commit(
    (doc, clock) => _writeChanged(
      doc,
      clock,
      Collections.givers,
      giver.id,
      giver.toFields(),
    ),
  );

  /// Da de alta o cambia una ocasión.
  Future<void> upsertOccasion(Occasion occasion) => _commit(
    (doc, clock) => _writeChanged(
      doc,
      clock,
      Collections.occasions,
      occasion.id,
      occasion.toFields(),
    ),
  );

  /// Da de alta o cambia un regalo. Con [original], solo aplica los campos
  /// que el editor cambió desde que se abrió, sobre el documento actual.
  /// Los demás conservan tanto su valor como su sello, aunque lleguen cambios
  /// remotos mientras se edita o se espera en la cola de escrituras.
  ///
  /// Devuelve `false` si no se guardó porque el regalo ya estaba eliminado o
  /// su persona ya no existe (otro móvil lo borró mientras se editaba): no se
  /// escribe nada. `true` si se guardó o si no había nada que cambiar.
  Future<bool> upsertGift(Gift gift, {Gift? original}) async {
    assert(original == null || original.id == gift.id);
    final fields = gift.toFields();
    if (original != null) {
      final before = original.toFields();
      fields.removeWhere(
        (key, value) => canonicalJsonOf(value) == canonicalJsonOf(before[key]),
      );
    }
    var refused = false;
    final saved = await _protectionSerial(() async {
      final current = await _requireFamily();
      final context = await _protectionContext(current.doc);
      if (context != null) {
        return _upsertProtectedAware(current, context, gift, fields, original);
      }
      final doc = current.doc;
      final clock = _clock!;
      if (_isDeletedRecord(doc, Collections.recipients, gift.recipientId) ||
          _isDeletedRecord(doc, Collections.gifts, gift.id)) {
        refused = true;
        return false;
      }
      // Even without v2 credentials a requested policy fails closed.
      if (_store.supportsSecretScopes) {
        final slots = await _store.readSlots();
        final keyring = await ref
            .read(deviceKeysStoreProvider)
            .readKeyring(doc.listId);
        for (final person in {
          gift.recipientId,
          doc.record(Collections.gifts, gift.id)?['recipientId'],
        }) {
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
      final next = _writeChanged(
        doc,
        clock,
        Collections.gifts,
        gift.id,
        fields,
        onlyExisting: original != null,
      );
      if (identical(next, doc)) return true;
      await _store.saveDoc(next);
      state = AsyncData(current.copyWith(doc: _store.savedDoc(next)));
      return true;
    });
    return saved && !refused;
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
      _commit((doc, clock) {
        if (archived) {
          _refuseArchivingDevicePerson(doc, id);
        }
        return _writeChanged(doc, clock, Collections.recipients, id, {
          'archived': archived,
        }, onlyExisting: true);
      });

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
  /// nombre, notas ni fecha), y también todos sus regalos, de todos los años,
  /// y su ocasión de cumpleaños. Si era quien había pedido otros regalos, ese
  /// dato se borra de ellos. No hace nada si no existe o ya está eliminada.
  ///
  /// Lanza [DevicePersonException] (y no escribe nada) si es la persona de
  /// un móvil de la familia.
  Future<void> deleteRecipient(String id) => _commit((doc, clock) {
    if (_isGone(doc, Collections.recipients, id)) {
      return doc;
    }
    _refuseDevicePerson(id);
    var next = doc;
    for (final record in _live(doc, Collections.gifts)) {
      if (record['recipientId'] == id) {
        next = next.delete(clock, Collections.gifts, record.id);
        continue;
      }
      final by = RequestedBy.fromFields(record['requestedBy']);
      if (by is RequestedByRecipient && by.recipientId == id) {
        // Quien lo pidió ya no existe: el regalo se queda sin ese dato.
        next = next.setChanged(clock, Collections.gifts, record.id, {
          'requestedBy': null,
        });
      }
    }
    for (final record in _live(doc, Collections.occasions)) {
      if (record['kind'] == OccasionKind.birthday.name &&
          record['recipientId'] == id) {
        next = next.delete(clock, Collections.occasions, record.id);
      }
    }
    return next.delete(clock, Collections.recipients, id);
  }, cascade: true);

  /// Elimina a alguien que regala para siempre: su registro pasa a lápida.
  /// Sus regalos no se borran: se quedan sin quién regala. No hace nada si no
  /// existe o ya está eliminado.
  Future<void> deleteGiver(String id) => _commit((doc, clock) {
    if (_isGone(doc, Collections.givers, id)) {
      return doc;
    }
    var next = doc;
    for (final record in _live(doc, Collections.gifts)) {
      if (record['giverId'] == id) {
        next = next.setChanged(clock, Collections.gifts, record.id, {
          'giverId': null,
        });
      }
    }
    return next.delete(clock, Collections.givers, id);
  }, cascade: true);

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
