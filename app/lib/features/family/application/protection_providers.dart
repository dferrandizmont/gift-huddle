import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/access_policy.dart';
import '../../../core/sync/device_registry.dart';
import '../../../core/sync/family_doc.dart';
import '../../../core/sync/model.dart';
import '../../../core/sync/pairing_v2.dart'
    show syncProtocolOf, kSyncProtocolV2;
import '../../../core/sync/protected_doc.dart';
import '../../../core/sync/protected_envelope.dart';
import '../../../core/sync/wish_plan.dart';
import '../../sync/application/sync_controller.dart'
    show localRegistryReadProvider, localRegistryViewProvider;
import '../../sync/data/sync_transport_v2.dart' show kV2MaxSlotsPerWriter;
import '../data/device_keys_store.dart';
import '../data/family_store.dart';
import 'family_controller.dart';

enum PersonProtectionStatus { unprotected, requested, active }

class GiftRecipientAccess {
  const GiftRecipientAccess({
    required this.recipient,
    required this.status,
    required this.canSelect,
    this.reason,
    this.canRequest = false,
    this.requestReason,
    this.viewerIsRecipient = false,
    this.canConfirm = false,
    this.canDeactivate = false,
  });
  final Recipient recipient;
  final PersonProtectionStatus status;
  final bool canSelect;
  final ProtectedPersonReason? reason;
  final bool canRequest;

  /// Why an unprotected recipient cannot have protection requested here.
  final ProtectedPersonReason? requestReason;

  /// Whether this phone is the one assigned to the recipient (display only).
  final bool viewerIsRecipient;
  final bool canConfirm;
  final bool canDeactivate;
  bool get isProtected => status != PersonProtectionStatus.unprotected;
}

/// Own requests are unavailable while the recipient's protection is on.
enum OwnGiftRequestState { allowed, protectionRestricted }

class PendingProtectedGift {
  const PendingProtectedGift(this.personId, this.gift, this.reason);
  final String personId;
  final Gift gift;
  final ProtectedPersonReason reason;
}

/// While async authorization is loading, remove gifts rather than reusing a
/// previous viewer's data. v1 has no slots but may carry a protection request.
/// [ownPeople] is the screen layer ([ownHiddenPeople]): never their gifts.
FamilyDoc safeCommonProjection(
  FamilyDoc common, {
  bool awaitingV2 = false,
  Set<String> ownPeople = const <String>{},
  Set<String> opened = const <String>{},
}) {
  // Solo cuentan las políticas que dicen «ocultar»: con la protección
  // desactivada (política publicada `hideOwnGifts: false`) los regalos
  // vuelven a verse (revisión de seguridad, lote 6, 3).
  final protected = {
    for (final e in publishedPolicies(common).entries)
      if (e.value.hideOwnGifts && !opened.contains(e.key)) e.key,
    ...ownPeople,
  };
  return FamilyDoc(
    listId: common.listId,
    collections: {
      ...common.collections,
      Collections.gifts: {
        for (final e
            in common.collections[Collections.gifts]?.entries ??
                const <MapEntry<String, SyncRecord>>[])
          if (!awaitingV2 && !protected.contains(e.value['recipientId']))
            e.key: e.value,
      },
    },
  );
}

/// La vista del registro para la capa de pantalla: la de este dispositivo.
/// En el móvil es [localRegistryViewProvider]. La web la sustituye por la
/// suya (su id y su persona, 1.0.6): su vista de siempre está anclada al
/// móvil que verifica las firmas, y con ella `accompanied` y `myPerson`
/// serían los de ese móvil.
final screenRegistryViewProvider = Provider<AsyncValue<RegistryView?>>(
  (ref) => ref.watch(localRegistryViewProvider),
);

/// Capa de pantalla (1.0.6): las personas cuyos regalos no pinta este móvil,
/// la suya mientras esté acompañado ([ownHiddenPeople]). Mientras el
/// registro carga o falla, también la de «Yo» si este móvil está emparejado
/// o conoce otros móviles: ante la duda, se oculta.
final ownHiddenPeopleProvider = Provider<Set<String>>((ref) {
  final family = ref.watch(familyControllerProvider).value;
  final identity = family?.identity;
  if (family == null || identity == null) return const <String>{};
  // La web (revisión final, M1): también las personas del móvil que la
  // conectó, por si ese móvil cambia de persona.
  final extra = ref.read(familyStoreProvider).screenExtraHiddenPeople;
  if (extra.isNotEmpty) {
    return {...ref.watch(_ownHiddenOfDevice), ...extra};
  }
  return ref.watch(_ownHiddenOfDevice);
});

final _ownHiddenOfDevice = Provider<Set<String>>((ref) {
  final family = ref.watch(familyControllerProvider).value;
  final identity = family?.identity;
  if (family == null || identity == null) return const <String>{};
  final registry = ref.watch(screenRegistryViewProvider);
  final fallback = ownHiddenPeople(
    view: null,
    selfRecipientId: identity.selfRecipientId,
    paired: identity.paired || family.otherDevicePeople.isNotEmpty,
    formerSelf: identity.formerSelf,
  );
  if (registry.isLoading || registry.hasError || !registry.hasValue) {
    return {
      ...fallback,
      if (registry.hasValue)
        ...ownHiddenPeople(
          view: registry.value,
          selfRecipientId: identity.selfRecipientId,
          paired: identity.paired,
          formerSelf: identity.formerSelf,
        ),
    };
  }
  final view = registry.value;
  if (view == null) return fallback;
  return ownHiddenPeople(
    view: view,
    selfRecipientId: identity.selfRecipientId,
    paired: identity.paired,
    formerSelf: identity.formerSelf,
  );
});

final authorizedProjectionProvider = FutureProvider<AuthorizedProjection?>((
  ref,
) async {
  final family = ref.watch(familyControllerProvider).value;
  if (!ref.read(familyStoreProvider).supportsSecretScopes) return null;
  final view = await ref.watch(localRegistryViewProvider.future);
  if (family == null || view == null) return null;
  final store = ref.read(familyStoreProvider);
  final slots = await store.readSlots();
  final keyring = await ref
      .read(deviceKeysStoreProvider)
      .readKeyring(family.doc.listId);
  final local = <String, FamilyDoc>{};
  for (final person in keyring.people) {
    if (!view.selfEntitled(person)) continue;
    final scope = await store.readScope(person);
    if (scope != null) local[person] = scope;
  }
  final identity = family.identity;
  return projectAuthorized(
    common: family.doc,
    slots: slots,
    keyring: keyring,
    view: view,
    includeArchived: true,
    hiddenGiftIds: family.hiddenGiftIds,
    localScopes: local,
    ownPeople: ownHiddenPeople(
      view: view,
      selfRecipientId: identity?.selfRecipientId,
      paired: identity?.paired ?? false,
      formerSelf: identity?.formerSelf ?? const <String>{},
    ),
    alone: ownProtectionLifted(view: view, paired: identity?.paired ?? false),
  );
});

/// La última proyección que se pintó y de quién era.
class _RetainedProjection {
  String? key;
  AuthorizedProjection? value;
}

final _retainedProjection = Provider<_RetainedProjection>(
  (ref) => _RetainedProjection(),
);

/// La proyección que se pinta (1.0.6, QA m5): la nueva y, mientras se vuelve a
/// calcular (por ejemplo tras «Sincronizar ahora»), la última del mismo móvil
/// y la misma persona, para que las pantallas no se vacíen un segundo. Si
/// cambia quién mira (otra persona, otra lista, otro estado de ocultación) o
/// falla, no se reutiliza nada: nunca se enseña lo de otro espectador.
final _paintedProjectionProvider = Provider<AuthorizedProjection?>((ref) {
  final projected = ref.watch(authorizedProjectionProvider);
  final identity = ref.watch(familyControllerProvider).value?.identity;
  final own = ref.watch(ownHiddenPeopleProvider);
  final key = identity == null
      ? null
      : [
          identity.listId,
          identity.node,
          identity.selfRecipientId ?? '',
          ([...identity.formerSelf]..sort()).join(','),
          ([...own]..sort()).join(','),
        ].join('|');
  final retained = ref.read(_retainedProjection);
  if (!projected.isLoading && !projected.hasError) {
    final value = projected.value;
    retained
      ..key = value == null ? null : key
      ..value = value;
    return value;
  }
  if (projected.isLoading &&
      !projected.hasError &&
      key != null &&
      retained.key == key) {
    return retained.value;
  }
  return null;
});

/// The only application document intended for derived views.
final projectedFamilyDocProvider = Provider<FamilyDoc>((ref) {
  final family = ref.watch(familyControllerProvider).value;
  if (family == null) return FamilyDoc.empty('');
  // Nunca `AsyncValue.value` a pelo: podría conservar a otro espectador; la
  // última proyección solo se reutiliza si es del mismo móvil y persona.
  final projected = ref.watch(_paintedProjectionProvider);
  if (projected != null) return projected.doc;
  final store = ref.read(familyStoreProvider);
  return safeCommonProjection(
    family.doc,
    awaitingV2:
        store.supportsSecretScopes &&
        syncProtocolOf(family.doc) == kSyncProtocolV2,
    ownPeople: ref.watch(ownHiddenPeopleProvider),
    // La web (1.0.6): lo que abre ya viene en su documento.
    opened: store.openedSecretPeople ?? const <String>{},
  );
});

/// Los planes vivos de los deseos de las personas cuyo bloque abre este móvil
/// (ADR 0010), por id de deseo. Vacío en los móviles de la propia persona y
/// mientras no hay proyección: nunca hay un «cogido» que enseñar a quien no
/// puede abrir el bloque.
final projectedPlansByWishProvider = Provider<Map<String, List<WishPlan>>>(
  (ref) =>
      ref.watch(_paintedProjectionProvider)?.plansByWish ??
      const <String, List<WishPlan>>{},
);

/// Los regalos que la proyección autorizada ha creado a partir de planes.
final projectedPlanGiftIdsProvider = Provider<Set<String>>(
  (ref) => ref.watch(_paintedProjectionProvider)?.planGiftIds ?? const {},
);

/// Los deseos de [person] con el estado que les dan los planes
/// (`available`, `claimed`, `conflictingClaims`, `removedFromList`), solo si
/// este móvil puede abrir su bloque. En los móviles de la propia persona
/// siempre está vacío: sus proveedores nunca llevan esos estados.
final wishPlanRowsProvider = Provider.family<List<WishPlanRow>, String>(
  (ref, person) =>
      ref.watch(_paintedProjectionProvider)?.wishPlanRowsFor(person) ??
      const <WishPlanRow>[],
);

/// Solo la web (1.0.6, ADR 0009): los regalos con cambios que esperan a que
/// los recoja el móvil de su persona («Pendiente de tu móvil»).
final webPendingSecretGiftIdsProvider = Provider<Set<String>>((ref) {
  ref.watch(familyControllerProvider);
  return ref.read(familyStoreProvider).pendingSecretGiftIds;
});

/// Fixed blocks have a person id only: no count, amount, or gift ids.
///
/// La decisión de ocultar es síncrona (1.0.6, QA M2): mientras la proyección
/// carga (por ejemplo un fotograma al girar) o falla, no se vuelve a «no hay
/// bloques», que pintaba un instante la ficha normal de quien no debe ver sus
/// regalos; se usa la política publicada y la persona de este móvil.
final secretBlocksProvider = Provider<List<SecretBlock>>((ref) {
  final projection = ref.watch(_paintedProjectionProvider);
  if (projection != null) return projection.lockedBlocks;
  // Sin proyección (la web y v1, o aún no hay): no hay claves ni slots, solo
  // la política publicada. Cada persona con «ocultar» enseña su bloque secreto
  // de tamaño fijo en vez de «0 regalos» (revisión de seguridad, lote 6, 3).
  final family = ref.watch(familyControllerProvider).value;
  if (family == null) return const [];
  final published = publishedPolicies(family.doc);
  final own = ref.watch(ownHiddenPeopleProvider);
  // La web (1.0.6): lo que abre no es un bloque.
  final opened =
      ref.read(familyStoreProvider).openedSecretPeople ?? const <String>{};
  // El bloque fijo de la propia persona (ADR 0010, decisión 5) no depende de
  // lo que haya dentro ni de si la persona está archivada: sale de la capa de
  // pantalla.
  final people = [
    for (final person in family.view.allRecipientsById.values)
      if ((published[person.id]?.hideOwnGifts == true &&
              !opened.contains(person.id)) ||
          own.contains(person.id))
        person.id,
  ]..sort();
  return [for (final id in people) SecretBlock(id)];
});

final giftRecipientAccessProvider = FutureProvider<List<GiftRecipientAccess>>((
  ref,
) async {
  final family = ref.watch(familyControllerProvider).value;
  if (family == null) return const [];
  final store = ref.read(familyStoreProvider);
  // Share the projection's verified snapshot for policy and eligibility.
  VerifiedRegistry? snapshot;
  ProtectedPersonReason? registryFailure;
  if (store.supportsSecretScopes) {
    try {
      final registry = await ref.watch(localRegistryReadProvider.future);
      snapshot = registry.snapshot;
      if (snapshot == null &&
          (registry.hasV2Identity ||
              syncProtocolOf(family.doc) == kSyncProtocolV2)) {
        registryFailure = ProtectedPersonReason.registryUnavailable;
      }
    } on Object catch (error) {
      registryFailure = protectionRegistryFailureReason(error);
    }
  }
  final view = snapshot?.view;
  final projection = view != null
      ? await ref.watch(authorizedProjectionProvider.future)
      : null;
  final keyring = view == null
      ? SurpriseKeyring.empty
      : await ref.read(deviceKeysStoreProvider).readKeyring(family.doc.listId);
  final slots = view == null ? SlotSet.empty : await store.readSlots();
  final candidateViews = <String, Future<RegistryView>>{};
  final own = ref.watch(ownHiddenPeopleProvider);
  final opened = store.openedSecretPeople;
  if (opened != null) {
    // La web (1.0.6, ADR 0009): las personas que abre se eligen si puede
    // escribir su buzón; si no, «hazlo desde el móvil».
    final writable = store.writableSecretPeople;
    final base = await Future.wait([
      for (final person in FamilyView.fromDoc(family.doc).recipients)
        _accessFor(
          person,
          family.doc,
          projection,
          snapshot,
          keyring,
          null,
          registryFailure,
          candidateViews,
          ownHidden: own.contains(person.id),
        ),
    ]);
    return [
      for (final access in base)
        if (!opened.contains(access.recipient.id) ||
            own.contains(access.recipient.id))
          access
        else
          GiftRecipientAccess(
            recipient: access.recipient,
            status: PersonProtectionStatus.active,
            canSelect: writable.contains(access.recipient.id),
            reason: writable.contains(access.recipient.id)
                ? null
                : ProtectedPersonReason.webUseMobile,
          ),
    ];
  }
  return Future.wait([
    for (final person in FamilyView.fromDoc(family.doc).recipients)
      _accessFor(
        person,
        family.doc,
        projection,
        snapshot,
        keyring,
        view == null ? null : slots.authenticatedPolicy(person.id, view),
        registryFailure,
        candidateViews,
        ownHidden: own.contains(person.id),
      ),
  ]);
});

Future<GiftRecipientAccess> _accessFor(
  Recipient person,
  FamilyDoc doc,
  AuthorizedProjection? projection,
  VerifiedRegistry? snapshot,
  SurpriseKeyring keyring,
  PolicyState? authenticated,
  ProtectedPersonReason? registryFailure,
  Map<String, Future<RegistryView>> candidateViews, {
  bool ownHidden = false,
}) async {
  final base = await _baseAccessFor(
    person,
    doc,
    projection,
    snapshot,
    keyring,
    authenticated,
    registryFailure,
    candidateViews,
  );
  if (!ownHidden) return base;
  // Capa de pantalla (1.0.6): en el móvil de esta persona no se elige ni se
  // ve nada suyo, tenga o no política. Solo otro móvil puede cambiarlo. La
  // petición de su protección sigue como siempre.
  return GiftRecipientAccess(
    recipient: base.recipient,
    status: base.status,
    canSelect: false,
    reason: ProtectedPersonReason.ownGiftsHidden,
    canRequest: base.canRequest,
    requestReason: base.requestReason,
    viewerIsRecipient: true,
    canConfirm: base.canConfirm,
    canDeactivate: false,
  );
}

Future<GiftRecipientAccess> _baseAccessFor(
  Recipient person,
  FamilyDoc doc,
  AuthorizedProjection? projection,
  VerifiedRegistry? snapshot,
  SurpriseKeyring keyring,
  PolicyState? authenticated,
  ProtectedPersonReason? registryFailure,
  Map<String, Future<RegistryView>> candidateViews,
) async {
  final view = snapshot?.view;
  final policy = projection?.policies[person.id];
  final blocked =
      policy?.hideOwnGifts ?? (publishedPolicy(doc, person.id) != null);
  final viewerIsRecipient = view?.myPerson == person.id;
  if (registryFailure != null) {
    return GiftRecipientAccess(
      recipient: person,
      status: blocked
          ? PersonProtectionStatus.requested
          : PersonProtectionStatus.unprotected,
      canSelect: false,
      reason: registryFailure,
      requestReason: registryFailure,
    );
  }
  if (!blocked) {
    final requestReason = snapshot == null
        ? ProtectedPersonReason.requiresV2
        : await protectionRequestReason(
            snapshot,
            person.id,
            candidateViews: candidateViews,
          );
    return GiftRecipientAccess(
      recipient: person,
      status: PersonProtectionStatus.unprotected,
      canSelect: true,
      canRequest: requestReason == null,
      requestReason: requestReason,
      viewerIsRecipient: viewerIsRecipient,
    );
  }
  final status =
      authenticated?.hideOwnGifts == true && policy?.hideOwnGifts == true
      ? PersonProtectionStatus.active
      : PersonProtectionStatus.requested;
  ProtectedPersonReason? reason;
  if (view == null) {
    reason = ProtectedPersonReason.requiresV2;
  } else if (view.myPerson == person.id) {
    reason = ProtectedPersonReason.ownRequestsRestricted;
  } else if (!view.selfEntitled(person.id)) {
    reason = ProtectedPersonReason.noEntitlement;
  } else if (keyring.sealingKeyFor(
        person.id,
        view.epoch,
        allowed: view.entitledDevices(person.id),
      ) ==
      null) {
    reason = ProtectedPersonReason.missingEpochKey;
  } else if (projection
          ?.openedScopes[person.id]
          ?.unreadableWriters
          .isNotEmpty ==
      true) {
    reason = ProtectedPersonReason.unreadableSlot;
  }
  return GiftRecipientAccess(
    recipient: person,
    status: status,
    canSelect: reason == null,
    reason: reason,
    viewerIsRecipient: viewerIsRecipient,
    canConfirm:
        view?.selfEntitled(person.id) == true &&
        status == PersonProtectionStatus.requested,
    canDeactivate: reason == null && authenticated != null,
  );
}

final ownGiftRequestStateProvider = FutureProvider<OwnGiftRequestState>((
  ref,
) async {
  final self = ref
      .watch(familyControllerProvider)
      .value
      ?.identity
      ?.selfRecipientId;
  if (self != null && ref.watch(ownHiddenPeopleProvider).contains(self)) {
    return OwnGiftRequestState.protectionRestricted;
  }
  final access = await ref.watch(giftRecipientAccessProvider.future);
  return access.any((a) => a.recipient.id == self && a.isProtected)
      ? OwnGiftRequestState.protectionRestricted
      : OwnGiftRequestState.allowed;
});

/// Includes transition overflow and records left out of the current writer's
/// sealed slot. It is never populated for a viewer without current entitlement.
final pendingProtectedGiftsProvider =
    FutureProvider<List<PendingProtectedGift>>((ref) async {
      if (!ref.read(familyStoreProvider).supportsSecretScopes) return const [];
      final family = ref.watch(familyControllerProvider).value;
      final projection = await ref.watch(authorizedProjectionProvider.future);
      final view = await ref.watch(localRegistryViewProvider.future);
      if (family == null || projection == null || view == null) return const [];
      final store = ref.read(familyStoreProvider);
      final slots = await store.readSlots();
      final keys = await ref
          .read(deviceKeysStoreProvider)
          .readKeyring(family.doc.listId);
      final raw = await store.readSyncV2State();
      final versions = raw is Map ? raw['s'] as Map? ?? {} : const {};
      final ownSlots = versions.keys
          .where((k) => (k as String).endsWith('/${view.me}'))
          .length;
      final deletedPeople = {
        for (final person
            in family.doc.collections[Collections.recipients]?.values ??
                const <SyncRecord>[])
          if (person.isDeleted) person.id,
      };
      final result = <PendingProtectedGift>[];
      for (final person in keys.people) {
        if (!view.selfEntitled(person)) continue;
        final pending = <String, SyncRecord>{
          for (final r in await store.readOverflow(person)) r.id: r,
        };
        final scope = await store.readScope(person);
        var reason = ProtectedPersonReason.blockFull;
        if (!versions.containsKey('$person/${view.me}')) {
          if (ownSlots >= kV2MaxSlotsPerWriter) {
            reason = ProtectedPersonReason.writerSlotsFull;
          } else if (versions.length >= kMaxSlotsPerList) {
            reason = ProtectedPersonReason.slotsFull;
          }
        }
        if (scope != null) {
          final opened = projection.openedScopes[person];
          final sealed = opened?.parts[view.me]?.doc;
          for (final r
              in scope.collections[Collections.gifts]?.values ??
                  const <SyncRecord>[]) {
            if (r.isDeleted) continue;
            if (reason != ProtectedPersonReason.blockFull ||
                sealed?.record(Collections.gifts, r.id) == null ||
                slots.slotOf(person, view.me) == null) {
              pending[r.id] = r;
            }
          }
        }
        final resolved = (scope ?? FamilyDoc.empty(family.doc.listId))
            .merge(
              projection.openedScopes[person]?.doc ??
                  FamilyDoc.empty(family.doc.listId),
            )
            .merge(
              FamilyDoc(
                listId: family.doc.listId,
                collections: {Collections.gifts: pending},
              ),
            );
        for (final record in pending.values) {
          final effective = resolved.record(Collections.gifts, record.id)!;
          if (effective.isDeleted) continue;
          final gift = Gift.fromRecord(effective, deletedPeople: deletedPeople);
          if (gift != null) {
            result.add(
              PendingProtectedGift(
                person,
                gift,
                surpriseRecordBytes(record) > kMaxSurpriseGiftBytes
                    ? ProtectedPersonReason.giftTooLarge
                    : reason,
              ),
            );
          }
        }
      }
      return result;
    });
