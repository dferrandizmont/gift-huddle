import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/access_policy.dart';
import '../../../core/sync/device_registry.dart';
import '../../../core/sync/family_doc.dart';
import '../../../core/sync/model.dart';
import '../../../core/sync/pairing_v2.dart'
    show syncProtocolOf, kSyncProtocolV2;
import '../../../core/sync/protected_doc.dart';
import '../../../core/sync/protected_envelope.dart';
import '../../sync/application/sync_controller.dart'
    show localRegistryViewProvider;
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
    this.canConfirm = false,
    this.canDeactivate = false,
  });
  final Recipient recipient;
  final PersonProtectionStatus status;
  final bool canSelect;
  final ProtectedPersonReason? reason;
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
FamilyDoc safeCommonProjection(FamilyDoc common, {bool awaitingV2 = false}) {
  // Solo cuentan las políticas que dicen «ocultar»: con la protección
  // desactivada (política publicada `hideOwnGifts: false`) los regalos
  // vuelven a verse (revisión de seguridad, lote 6, 3).
  final protected = {
    for (final e in publishedPolicies(common).entries)
      if (e.value.hideOwnGifts) e.key,
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
  return projectAuthorized(
    common: family.doc,
    slots: slots,
    keyring: keyring,
    view: view,
    includeArchived: true,
    hiddenGiftIds: family.hiddenGiftIds,
    localScopes: local,
  );
});

/// The only application document intended for derived views.
final projectedFamilyDocProvider = Provider<FamilyDoc>((ref) {
  final family = ref.watch(familyControllerProvider).value;
  if (family == null) return FamilyDoc.empty('');
  final projected = ref.watch(authorizedProjectionProvider);
  // Never use AsyncValue.value here: it may retain an older viewer on refresh.
  if (!projected.isLoading && !projected.hasError && projected.value != null) {
    return projected.value!.doc;
  }
  return safeCommonProjection(
    family.doc,
    awaitingV2:
        ref.read(familyStoreProvider).supportsSecretScopes &&
        syncProtocolOf(family.doc) == kSyncProtocolV2,
  );
});

/// Fixed blocks have a person id only: no count, amount, or gift ids.
final secretBlocksProvider = Provider<List<SecretBlock>>((ref) {
  final projection = ref.watch(authorizedProjectionProvider);
  if (projection.isLoading || projection.hasError) return const [];
  final value = projection.value;
  if (value != null) return value.lockedBlocks;
  // Sin proyección (la web y v1): no hay claves ni slots, solo la política
  // publicada. Cada persona con «ocultar» enseña su bloque secreto de
  // tamaño fijo en vez de «0 regalos» (revisión de seguridad, lote 6, 3).
  final family = ref.watch(familyControllerProvider).value;
  if (family == null) return const [];
  final published = publishedPolicies(family.doc);
  final people = [
    for (final person in family.view.recipients)
      if (published[person.id]?.hideOwnGifts == true) person.id,
  ]..sort();
  return [for (final id in people) SecretBlock(id)];
});

final giftRecipientAccessProvider = FutureProvider<List<GiftRecipientAccess>>((
  ref,
) async {
  final family = ref.watch(familyControllerProvider).value;
  if (family == null) return const [];
  final projection = await ref.watch(authorizedProjectionProvider.future);
  final view = ref.read(familyStoreProvider).supportsSecretScopes
      ? await ref.watch(localRegistryViewProvider.future)
      : null;
  final keyring = view == null
      ? SurpriseKeyring.empty
      : await ref.read(deviceKeysStoreProvider).readKeyring(family.doc.listId);
  final slots = await ref.read(familyStoreProvider).readSlots();
  return [
    for (final person in FamilyView.fromDoc(family.doc).recipients)
      _accessFor(
        person,
        family.doc,
        projection,
        view,
        keyring,
        view == null ? null : slots.authenticatedPolicy(person.id, view),
      ),
  ];
});

GiftRecipientAccess _accessFor(
  Recipient person,
  FamilyDoc doc,
  AuthorizedProjection? projection,
  RegistryView? view,
  SurpriseKeyring keyring,
  PolicyState? authenticated,
) {
  final policy = projection?.policies[person.id];
  final blocked =
      policy?.hideOwnGifts ?? (publishedPolicy(doc, person.id) != null);
  if (!blocked) {
    return GiftRecipientAccess(
      recipient: person,
      status: PersonProtectionStatus.unprotected,
      canSelect: true,
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
