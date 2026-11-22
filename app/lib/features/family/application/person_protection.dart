part of 'family_controller.dart';

/// People represented by another active mobile in the verified registry.
Set<String> otherMobilePeople(RegistryView? view) => Set.unmodifiable({
  if (view != null)
    for (final id in view.members)
      if (id != view.me && view.member(id)!.kind == DeviceKind.mobile)
        if (view.member(id)!.personId case final String person) person,
});

ProtectedPersonReason protectionRegistryFailureReason(Object error) =>
    error is RegistryIdentityAmbiguousException
    ? ProtectedPersonReason.requesterAmbiguous
    : ProtectedPersonReason.registryUnavailable;

/// Request eligibility on the verified registry and the view built from it.
/// [candidateViews] shares candidate views across one evaluation.
Future<ProtectedPersonReason?> protectionRequestReason(
  VerifiedRegistry snapshot,
  String personId, {
  Map<String, Future<RegistryView>>? candidateViews,
}) async {
  final ProtectionRequestBlock? block;
  try {
    block = await protectionRequestBlock(
      registry: snapshot.registry,
      localView: snapshot.view,
      personId: personId,
      candidateViews: candidateViews,
    );
  } on Object catch (error) {
    return protectionRegistryFailureReason(error);
  }
  return switch (block) {
    null => null,
    ProtectionRequestBlock.registryUnavailable =>
      ProtectedPersonReason.registryUnavailable,
    ProtectionRequestBlock.notMobile => ProtectedPersonReason.requiresV2,
    ProtectionRequestBlock.recipientUnavailable =>
      ProtectedPersonReason.recipientUnavailable,
    ProtectionRequestBlock.requesterRevoked =>
      ProtectedPersonReason.requesterRevoked,
    ProtectionRequestBlock.requesterAmbiguous =>
      ProtectedPersonReason.requesterAmbiguous,
    ProtectionRequestBlock.requesterPending =>
      ProtectedPersonReason.requesterPending,
    ProtectionRequestBlock.noConfirmer => ProtectedPersonReason.noConfirmer,
  };
}

class _ProtectionContext {
  const _ProtectionContext(
    this.view,
    this.keys,
    this.slots,
    this.keyring, {
    this.registry,
    this.alone = false,
    this.ownHidden = const <String>{},
  });
  final RegistryView view;
  final DeviceKeys keys;
  final SlotSet slots;
  final SurpriseKeyring keyring;

  /// El registro verificado del que sale [view].
  final DeviceRegistry? registry;

  /// Excepción del móvil solo ([ownProtectionLifted]).
  final bool alone;

  /// Capa de pantalla ([ownHiddenPeople]).
  final Set<String> ownHidden;

  _ProtectionContext withKeyring(SurpriseKeyring next) => _ProtectionContext(
    view,
    keys,
    slots,
    next,
    registry: registry,
    alone: alone,
    ownHidden: ownHidden,
  );

  bool blocked(FamilyDoc doc, String person) => publicGiftsBlockedFor(
    common: doc,
    slots: slots,
    keyring: keyring,
    view: view,
    personId: person,
    alone: alone,
  );

  SurpriseKey requireKey(String person) {
    if (view.myPerson == person) {
      throw ProtectedPersonException(
        person,
        reason: ProtectedPersonReason.ownRequestsRestricted,
      );
    }
    if (!view.selfEntitled(person)) {
      throw ProtectedPersonException(
        person,
        reason: ProtectedPersonReason.noEntitlement,
      );
    }
    final key = keyring.sealingKeyFor(
      person,
      view.epoch,
      allowed: view.entitledDevices(person),
    );
    if (key == null) {
      throw ProtectedPersonException(
        person,
        reason: ProtectedPersonReason.missingEpochKey,
      );
    }
    return key;
  }

  Future<OpenedScope> open(String person) async {
    requireKey(person);
    final opened = await openScope(
      personId: person,
      slots: slots,
      keyring: keyring,
      view: view,
    );
    if (opened == null ||
        opened.unreadableWriters.isNotEmpty ||
        (slots.slotOf(person, view.me) != null &&
            !opened.parts.containsKey(view.me))) {
      throw ProtectedPersonException(
        person,
        reason: ProtectedPersonReason.unreadableSlot,
      );
    }
    return opened;
  }
}

/// Application actions use the v2 lock before the controller queue, in the
/// same order as sync. The UI imports family_controller.dart for this API.
extension PersonProtectionActions on FamilyController {
  Future<T> _protectionSerial<T>(Future<T> Function() action) => _protectionRef
      .read(v2FamilyLockProvider)
      .run(
        () => _serial(() async {
          await _recoverProtection();
          return action();
        }),
      );

  Future<void> _recoverProtection() async {
    if (!await _store.recoverProtectionOperation()) return;
    final saved = await _store.load();
    if (saved == null) return;
    _adopt(saved.identity, saved.key, saved.doc);
    _protectionState = AsyncData(
      FamilyState(
        doc: saved.doc,
        identity: saved.identity,
        otherDevicePeople: await _readOtherMobilePeople(saved.doc),
      ),
    );
  }

  /// Sync already holds the v2 lock. Also used before loading its local state.
  Future<void> recoverProtectionWithinLock() => _serial(_recoverProtection);

  Future<_ProtectionContext?> _protectionContext(FamilyDoc doc) async {
    if (!_store.supportsSecretScopes) return null;
    final registry = await _store.readVerifiedRegistry(doc);
    if (registry == null) return null;
    final identity = (await _current()).identity;
    final paired = identity?.paired ?? false;
    return _ProtectionContext(
      registry.view,
      registry.keys,
      await _store.readSlots(),
      await _protectionRef
          .read(deviceKeysStoreProvider)
          .readKeyring(doc.listId),
      registry: registry.registry,
      alone: ownProtectionLifted(view: registry.view, paired: paired),
      ownHidden: ownHiddenPeople(
        view: registry.view,
        selfRecipientId: identity?.selfRecipientId,
        paired: paired,
        formerSelf: identity?.formerSelf ?? const <String>{},
      ),
    );
  }

  Future<FamilyView> _authorizedView(
    FamilyDoc doc, {
    FamilyDoc? policySource,
    bool includePending = false,
  }) async {
    final effectiveDoc = policySource == null
        ? doc
        : FamilyDoc(
            listId: doc.listId,
            collections: {
              ...doc.collections,
              Collections.policies:
                  policySource.collections[Collections.policies] ?? const {},
            },
          );
    final ctx = await _protectionContext(effectiveDoc);
    if (ctx == null) {
      // 1.0.6: sin contexto de protección, la vista de los diálogos y
      // resúmenes sigue la misma regla que la pantalla. Un v2 sin registro
      // legible no enseña ningún regalo; un v1 oculta además los de la
      // persona de este móvil si está emparejado.
      final current = await _current();
      final identity = current.identity;
      if (_store.supportsSecretScopes &&
          (await _store.readSyncV2() != null ||
              syncProtocolOf(effectiveDoc) == kSyncProtocolV2)) {
        return FamilyView.fromDoc(_withoutGiftsFor(effectiveDoc, null));
      }
      final own = ownHiddenPeople(
        view: null,
        selfRecipientId: identity?.selfRecipientId,
        paired:
            (identity?.paired ?? false) ||
            current.otherDevicePeople.isNotEmpty,
        formerSelf: identity?.formerSelf ?? const <String>{},
      );
      return FamilyView.fromDoc(
        _withoutGiftsFor(FamilyState._safeStateDoc(effectiveDoc), own),
      );
    }
    return (await _projectAuthorized(
      effectiveDoc,
      ctx,
      includePending: includePending,
    )).view;
  }

  // [doc] sin los regalos para [people], o sin ninguno con null.
  FamilyDoc _withoutGiftsFor(FamilyDoc doc, Set<String>? people) {
    if (people != null && people.isEmpty) return doc;
    return FamilyDoc(
      listId: doc.listId,
      collections: {
        ...doc.collections,
        Collections.gifts: {
          if (people != null)
            for (final e
                in doc.collections[Collections.gifts]?.entries ??
                    const <MapEntry<String, SyncRecord>>[])
              if (!people.contains(e.value['recipientId'])) e.key: e.value,
        },
      },
    );
  }

  Future<AuthorizedProjection> _projectAuthorized(
    FamilyDoc doc,
    _ProtectionContext ctx, {
    bool includePending = false,
  }) async {
    final local = <String, FamilyDoc>{};
    for (final person in ctx.keyring.people) {
      if (!ctx.view.selfEntitled(person)) continue;
      var scope = await _store.readScope(person);
      if (includePending) {
        final pending = await _store.readOverflow(person);
        if (pending.isNotEmpty) {
          final pendingDoc = _recordsDoc(doc.listId, pending);
          scope = scope?.merge(pendingDoc) ?? pendingDoc;
        }
      }
      if (scope != null) local[person] = scope;
    }
    return projectAuthorized(
      common: doc,
      slots: ctx.slots,
      keyring: ctx.keyring,
      view: ctx.view,
      localScopes: local,
      ownPeople: ctx.ownHidden,
      alone: ctx.alone,
    );
  }

  // Persist the common and authorized scope edits together so recovery can
  // replay them after an interrupted delete. For scopes without a current
  // sealing key, the local edits can be sealed when sync receives that key.
  Future<bool> _saveProtectedCascade(
    FamilyDoc before,
    FamilyDoc after,
    FamilyDoc Function(FamilyDoc, HlcClock) changeGifts,
  ) async {
    final ctx = await _protectionContext(before);
    if (ctx == null) return false;
    var slots = ctx.slots;
    final scopes = <String, Map<String, Object?>>{};
    for (final person in ctx.keyring.people) {
      final opened = await openScope(
        personId: person,
        slots: ctx.slots,
        keyring: ctx.keyring,
        view: ctx.view,
      );
      if (opened == null) continue;
      final scope = (await _store.readScope(person) ?? opened.doc).merge(
        opened.doc,
      );
      final pending = await _store.readOverflow(person);
      final withPending = scope.merge(_recordsDoc(before.listId, pending));
      final clock = HlcClock(
        node: ctx.view.me,
        last: _store.latestStoredStamp(withPending),
      );
      var changed = changeGifts(scope, clock);
      final changedPending = changeGifts(withPending, clock);
      if (identical(changed, scope) && identical(changedPending, withPending)) {
        continue;
      }
      final remaining = [
        for (final record in pending)
          if (changedPending.record(Collections.gifts, record.id)
              case final SyncRecord updated when !updated.isDeleted)
            updated,
      ];
      if (opened.unreadableWriters.isEmpty) {
        try {
          final published = await publishScope(
            slots: slots,
            opened: opened,
            view: ctx.view,
            writerKeys: ctx.keys,
            keyring: ctx.keyring,
            policy: opened.effective(publishedPolicy(before, person)),
            doc: changed,
            nowMillis: DateTime.now().millisecondsSinceEpoch,
          );
          final (next, rejected) = await slots.merge([
            published.slot,
          ], view: ctx.view);
          if (rejected == 0) {
            slots = next;
            changed = published.scope;
          }
        } on SlotPublishBlockedException {
          // Keep the authorized local edit until the scope can be sealed.
        }
      }
      scopes[person] = {
        'scope': changed.toJson(),
        'overflow': _recordsDoc(before.listId, remaining).toJson(),
      };
    }
    if (scopes.isEmpty) return false;
    final first = scopes.entries.first;
    scopes.remove(first.key);
    await _store.saveProtectionOperation({
      'list': after.listId,
      'person': first.key,
      ...first.value,
      'common': after.toJson(),
      'slots': slots.toJson(),
      if (scopes.isNotEmpty) 'additionalScopes': scopes,
    });
    await _store.recoverProtectionOperation();
    return true;
  }

  /// Publishes only a request. It never creates keys or moves gifts. A phone
  /// with entitlement confirms it through activateProtection (or on sync).
  Future<void> requestProtection(String personId) async {
    try {
      await _protectionSerial(() async {
        final current = await _requireFamily();
        _store.requireMobileOperation('requestProtection');
        final LocalRegistryRead registry;
        try {
          registry = await _store.readLocalRegistry(current.doc);
        } on RegistryException catch (error) {
          throw ProtectedPersonException(
            personId,
            reason: protectionRegistryFailureReason(error),
          );
        } on FamilyStoreException {
          throw ProtectedPersonException(
            personId,
            reason: ProtectedPersonReason.registryUnavailable,
          );
        } on DeviceKeysStoreException {
          throw ProtectedPersonException(
            personId,
            reason: ProtectedPersonReason.registryUnavailable,
          );
        }
        final snapshot = registry.snapshot;
        if (snapshot == null) {
          throw ProtectedPersonException(
            personId,
            reason:
                registry.hasV2Identity ||
                    syncProtocolOf(current.doc) == kSyncProtocolV2
                ? ProtectedPersonReason.registryUnavailable
                : ProtectedPersonReason.requiresV2,
          );
        }
        final reason = await protectionRequestReason(snapshot, personId);
        if (reason != null) {
          throw ProtectedPersonException(personId, reason: reason);
        }
        final slots = await _store.readSlots();
        final next = protection_policy.requestProtection(
          current.doc,
          _clock!,
          personId,
          authenticated: slots.authenticatedPolicy(personId, snapshot.view),
        );
        await _store.saveDoc(next);
        _protectionState = AsyncData(current.copyWith(doc: next));
      });
    } on ProtectedPersonException catch (error) {
      final ref = _protectionRef;
      if (error.reason == ProtectedPersonReason.registryUnavailable &&
          ref.mounted) {
        ref.container.invalidate(localRegistryReadProvider);
      }
      rethrow;
    }
  }

  Future<void> activateProtection(String personId) =>
      _protectionSerial(() => _transitionProtection(personId, true));

  /// Como [activateProtection], para quien ya tiene el cerrojo v2 (nunca
  /// [_protectionSerial] desde ahí: se bloquearía).
  Future<void> activateProtectionWithinLock(String personId) =>
      _serial(() async {
        await _recoverProtection();
        await _transitionProtection(personId, true);
      });

  /// QA 1.0.6, M1 (B1 y B2 de la revisión de seguridad): antes de estrenar una
  /// generación sin nadie, con la vista de la que se deja, quién podrá volver
  /// a sellarse ([planAloneRestore]). Para quien ya tiene el cerrojo v2. Sin
  /// registro legible o ante cualquier fallo, nada.
  Future<AloneRestorePlan> planAloneRestoreWithinLock() => _serial(() async {
    try {
      await _recoverProtection();
      final current = await _current();
      final identity = current.identity;
      if (identity == null) return AloneRestorePlan.none;
      final ctx = await _protectionContext(current.doc);
      if (ctx == null) return AloneRestorePlan.none;
      return planAloneRestore(
        view: ctx.view,
        held: {
          ...ctx.keyring.people,
          ...(await _store.readRecoveryScopes()).keys,
        },
        selfRecipientId: identity.selfRecipientId,
        formerSelf: identity.formerSelf,
      );
    } on Object {
      return AloneRestorePlan.none;
    }
  });

  /// QA 1.0.6, M1: ya estrenada la generación sin nadie, vuelve a sellar para
  /// este móvil, con una clave nueva cuya audiencia es solo él, las sorpresas
  /// de los demás que ya tenía en su copia local y que permite [plan]
  /// ([othersToRestoreWhenAlone]). Nunca las de su propia persona. Para quien
  /// ya tiene el cerrojo v2. De mejor esfuerzo y sin lanzar (B3): lo que no
  /// sale se arregla al volver a conectar otro móvil, como antes.
  Future<void> restoreOthersSecretsWhenAloneWithinLock(AloneRestorePlan plan) =>
      _serial(() async {
        if (plan.people.isEmpty) return;
        final Set<String> people;
        try {
          await _recoverProtection();
          final current = await _current();
          final identity = current.identity;
          if (identity == null) return;
          final ctx = await _protectionContext(current.doc);
          if (ctx == null) return;
          people = othersToRestoreWhenAlone(
            common: current.doc,
            view: ctx.view,
            slots: ctx.slots,
            keyring: ctx.keyring,
            localScopes: (await _store.readRecoveryScopes()).keys,
            paired: identity.paired,
            plan: plan,
          );
        } on Object {
          return;
        }
        for (final person in people.toList()..sort()) {
          try {
            await _transitionProtection(person, true);
          } on Object {
            continue;
          }
        }
      });

  /// Antes de invitar al móvil de [personId] (1.0.6), de mejor esfuerzo:
  /// pone en secreto sus regalos si este móvil tiene derecho y aún no lo
  /// están. No lanza: el intento que cuenta es [protectForPairingWithinLock].
  Future<void> protectBeforeInvite(String personId) async {
    try {
      await _protectionSerial(() async {
        final current = await _requireFamily();
        final ctx = await _protectionContext(current.doc);
        if (ctx == null ||
            ctx.view.myPerson == personId ||
            nothingToProtectFor(current.doc, personId) ||
            !ctx.view.selfEntitled(personId)) {
          return;
        }
        if (ctx.slots.authenticatedPolicy(personId, ctx.view)?.hideOwnGifts ==
                true &&
            publishedPolicy(current.doc, personId)?.hideOwnGifts == true) {
          return;
        }
        await _transitionProtection(personId, true);
      });
    } on ProtectedPersonException {
      // Lo vuelve a intentar antes de aprobar.
    } on SlotPublishBlockedException {
      // Igual.
    }
  }

  /// Antes de aprobar un móvil nuevo para [personId] (1.0.6), dentro del
  /// cerrojo v2 y con su ficha ya en el registro: pone en secreto los
  /// regalos para esa persona, para que el común que fija el checkpoint no
  /// lleve ninguno vivo. Si este móvil es de [personId] (conecta su segundo
  /// móvil) no hay a quién ocultar nada y no hace nada. Si no lo consigue,
  /// lanza [PairingProtectionException] y no se aprueba.
  Future<void> protectForPairingWithinLock(String personId) =>
      _serial(() async {
        await _recoverProtection();
        final current = await _requireFamily();
        final ctx = await _protectionContext(current.doc);
        if (ctx == null) throw PairingProtectionException(personId);
        if (ctx.view.myPerson == personId) return;
        // Quien solo regala no tiene regalos que ocultar.
        if (nothingToProtectFor(current.doc, personId)) return;
        if (ctx.slots.authenticatedPolicy(personId, ctx.view)?.hideOwnGifts !=
                true ||
            publishedPolicy(current.doc, personId)?.hideOwnGifts != true) {
          try {
            await _transitionProtection(personId, true);
          } on ProtectedPersonException {
            throw PairingProtectionException(personId);
          } on SlotPublishBlockedException {
            throw PairingProtectionException(personId);
          }
        }
        final latest = await _current();
        final after = await _protectionContext(latest.doc);
        final policy = after?.slots.authenticatedPolicy(personId, after.view);
        if (after == null ||
            policy?.hideOwnGifts != true ||
            publishedPolicy(latest.doc, personId)?.hideOwnGifts != true) {
          throw PairingProtectionException(personId);
        }
      });

  /// Call after the UI confirms that all past gifts will become public.
  Future<void> deactivateProtection(String personId) =>
      _protectionSerial(() => _transitionProtection(personId, false));

  Future<void> _transitionProtection(String person, bool activate) async {
    _store.requireMobileOperation('personProtection');
    final current = await _requireFamily();
    var ctx = await _protectionContext(current.doc);
    if (ctx == null) {
      throw ProtectedPersonException(
        person,
        reason: ProtectedPersonReason.requiresV2,
      );
    }
    if (!ctx.view.selfEntitled(person)) {
      throw ProtectedPersonException(
        person,
        reason: ctx.view.myPerson == person
            ? ProtectedPersonReason.ownRequestsRestricted
            : ProtectedPersonReason.noEntitlement,
      );
    }
    SurpriseKeyShare? share;
    if (activate &&
        ctx.keyring.sealingKeyFor(
              person,
              ctx.view.epoch,
              allowed: ctx.view.entitledDevices(person),
            ) ==
            null) {
      share = await createSurpriseKey(
        personId: person,
        keyring: ctx.keyring,
        view: ctx.view,
        keys: ctx.keys,
      );
      ctx = ctx.withKeyring(share.keyring);
    }
    final key = ctx.requireKey(person);
    final opened = await ctx.open(person);
    if (!activate && opened.authenticatedPolicy == null) {
      throw ProtectedPersonException(
        person,
        reason: ProtectedPersonReason.protectionPending,
      );
    }
    var scope =
        (await _store.readScope(person) ?? FamilyDoc.empty(current.doc.listId))
            .merge(opened.doc);
    final pending = await _store.readOverflow(person);
    // Deactivation publishes the local leftovers too; none may silently stay
    // behind while the UI says all past gifts are now public.
    if (!activate) {
      scope = scope.merge(_recordsDoc(current.doc.listId, pending));
    }
    final scopeClock = HlcClock(
      node: ctx.view.me,
      last: _store.latestStoredStamp(scope),
    );
    var common = current.doc;
    final resolvedDeletes = <String>{};
    if (!activate) {
      // Publishing changes ids. Commit this person's Undo intentions in the
      // same durable transition, before deriving any public destination ids.
      for (final id in _pending.keys) {
        final secret = scope.record(Collections.gifts, id);
        final public = common.record(Collections.gifts, id);
        if (secret?['recipientId'] != person &&
            public?['recipientId'] != person) {
          continue;
        }
        scope = scope.delete(scopeClock, Collections.gifts, id);
        if (public != null && !public.isDeleted) {
          common = common.delete(_clock!, Collections.gifts, id);
        }
        resolvedDeletes.add(id);
      }
    }
    final result = activate
        ? protection_model.activateProtection(
            common: common,
            scope: scope,
            key: key,
            publicClock: _clock!,
            scopeClock: scopeClock,
            authenticated: opened.authenticatedPolicy,
          )
        : protection_model.deactivateProtection(
            common: common,
            scope: scope,
            key: key,
            publicClock: _clock!,
            scopeClock: scopeClock,
            authenticated: opened.authenticatedPolicy,
          );
    var nextScope = result.scope;
    final capacityOverflow = <SyncRecord>[];
    if (activate) {
      // Activation is an editor action: reserve the reconciliation allowance
      // for late writes from older phones, not for the initial migration.
      final records = result.scope.collections[Collections.gifts] ?? const {};
      final live = records.values.where((r) => !r.isDeleted).toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      final excess = live.skip(kMaxSurpriseGifts).map((r) => r.id).toSet();
      capacityOverflow.addAll(live.where((r) => excess.contains(r.id)));
      nextScope = _recordsDoc(
        current.doc.listId,
        records.values.where((r) => !excess.contains(r.id)),
      );
    }
    await _saveProtected(ctx, person, result.common, nextScope, result.policy, [
      ...(activate ? pending : <SyncRecord>[]),
      ...result.overflow,
      ...capacityOverflow,
    ], share: share);
    if (resolvedDeletes.isNotEmpty) {
      for (final id in resolvedDeletes) {
        _pending.remove(id)?.cancel();
      }
      final latest = await _current();
      _protectionState = AsyncData(
        latest.copyWith(
          hiddenGiftIds: {...latest.hiddenGiftIds}..removeAll(resolvedDeletes),
        ),
      );
    }
  }

  FamilyDoc _recordsDoc(String list, Iterable<SyncRecord> records) => FamilyDoc(
    listId: list,
    collections: {
      Collections.gifts: {for (final r in records) r.id: r},
    },
  );

  // Resolve local edits against deletions before publishScope can compact
  // their tombstones. Keep complete, field-merged pending values otherwise.
  List<SyncRecord> _livePending(FamilyDoc scope, List<SyncRecord> pending) {
    final merged = scope.merge(_recordsDoc(scope.listId, pending));
    return [
      for (final id in pending.map((r) => r.id).toSet())
        if (!merged.record(Collections.gifts, id)!.isDeleted)
          merged.record(Collections.gifts, id)!,
    ];
  }

  Future<ProtectedPersonReason?> _saveProtected(
    _ProtectionContext ctx,
    String person,
    FamilyDoc common,
    FamilyDoc scope,
    PolicyState policy,
    List<SyncRecord> pending, {
    SurpriseKeyShare? share,
    SlotSet? preparedSlots,
    Map<String, Map<String, Object?>> additionalScopes = const {},
  }) async {
    final opened = await ctx.open(person);
    final resolvedPending = _livePending(scope.merge(opened.doc), pending);
    // All writes go into this phone's slot; nobody rewrites another writer.
    final result = await publishScope(
      slots: preparedSlots ?? ctx.slots,
      opened: opened,
      view: ctx.view,
      writerKeys: ctx.keys,
      keyring: ctx.keyring,
      policy: policy,
      doc: scope,
      nowMillis: DateTime.now().millisecondsSinceEpoch,
    );
    final (slots, rejected) = await (preparedSlots ?? ctx.slots).merge([
      result.slot,
    ], view: ctx.view);
    var reason = result.leftOut.isNotEmpty
        ? ProtectedPersonReason.blockFull
        : null;
    if (rejected != 0) reason = ProtectedPersonReason.slotsFull;
    final v2state = await _store.readSyncV2State();
    // slotVersions represents resources actually known at the service; local
    // padding slots cannot make a full writer look like a published one.
    final versions = v2state is Map ? v2state['s'] as Map? ?? {} : const {};
    final own = versions.keys
        .where((k) => (k as String).endsWith('/${ctx.view.me}'))
        .length;
    if (!versions.containsKey('$person/${ctx.view.me}')) {
      if (own >= kV2MaxSlotsPerWriter) {
        reason = ProtectedPersonReason.writerSlotsFull;
      }
      if (versions.length >= kMaxSlotsPerList) {
        reason = ProtectedPersonReason.slotsFull;
      }
    }
    final leftovers = _recordsDoc(common.listId, resolvedPending);
    await _store.saveProtectionOperation({
      'list': common.listId,
      'person': person,
      'epoch': ctx.view.epoch,
      'allowed': ctx.view.entitledDevices(person).toList(),
      'common': common.toJson(),
      'scope': result.scope.toJson(),
      'overflow': leftovers.toJson(),
      'slots': slots.toJson(),
      if (additionalScopes.isNotEmpty) 'additionalScopes': additionalScopes,
      if (share != null) 'keys': SurpriseKeyring([share.key]).toJson(),
      if (share != null) 'bundles': [for (final b in share.bundles) b.toJson()],
    });
    await _store.recoverProtectionOperation();
    final current = await _current();
    _protectionState = AsyncData(
      current.copyWith(
        doc: common,
        protectionRevision: current.protectionRevision + 1,
      ),
    );
    return reason;
  }

  Future<_GiftWriteOutcome> _upsertProtectedAware(
    FamilyState current,
    _ProtectionContext ctx,
    Gift gift,
    Map<String, Object?> fields,
    Gift? original, {
    Set<String> confirmed = const {},
    String? giverPersonId,
  }) async {
    var doc = current.doc;
    final previous = doc.record(Collections.gifts, gift.id);
    String? source;
    SyncRecord? secret;
    for (final person in ctx.keyring.people) {
      if (!ctx.view.selfEntitled(person)) continue;
      final scope = await openScope(
        personId: person,
        slots: ctx.slots,
        keyring: ctx.keyring,
        view: ctx.view,
      );
      final local = await _store.readScope(person);
      final record = await _localSecretRecord(
        doc.listId,
        person,
        gift.id,
        scope,
        local,
      );
      if (record != null) {
        source = person;
        secret = record;
        break;
      }
    }
    if ((secret ?? previous)?.isDeleted == true) {
      return (result: GiftWriteResult.giftDeleted, savedId: null);
    }
    if (secret == null && original != null && previous == null) {
      return (result: GiftWriteResult.giftUnavailable, savedId: null);
    }
    // An editor that did not change recipientId must preserve a remote move.
    // Authorization follows the record being written, never the stale form.
    final person =
        fields['recipientId'] as String? ??
        secret?['recipientId'] as String? ??
        previous?['recipientId'] as String? ??
        gift.recipientId;
    if (_isDeletedRecord(doc, Collections.recipients, person)) {
      return (result: GiftWriteResult.recipientUnavailable, savedId: null);
    }
    final previousPerson = previous?['recipientId'];
    // Capa de pantalla (1.0.6): este móvil no escribe regalos para su
    // persona mientras esté acompañado, ni mueve los que no ve.
    for (final involved in {
      person,
      ?source,
      if (previousPerson is String) previousPerson,
    }) {
      if (ctx.ownHidden.contains(involved)) {
        throw ProtectedPersonException(
          involved,
          reason: ProtectedPersonReason.ownGiftsHidden,
        );
      }
    }
    final blocked = {
      person,
      ?source,
      if (previousPerson is String) previousPerson,
    }.where((involved) => ctx.blocked(doc, involved)).toList();
    for (final involved in blocked) {
      ctx.requireKey(involved);
    }
    final (result, prepared) = _prepareGiftGiver(
      doc,
      person,
      fields,
      previous: secret ?? previous,
      giverPersonId: giverPersonId,
      protected: source != null || blocked.isNotEmpty,
    );
    if (result != GiftWriteResult.saved) return (result: result, savedId: null);
    for (final involved in blocked) {
      if (!confirmed.contains(involved) &&
          ctx.slots.authenticatedPolicy(involved, ctx.view)?.hideOwnGifts !=
              true) {
        // A cached key can make an editor writable while the activation is
        // still only requested. Confirm and move the old gifts before signing
        // that policy in the writer's slot.
        await _transitionProtection(involved, true);
        final latest = await _current();
        final refreshed = (await _protectionContext(latest.doc))!;
        return _upsertProtectedAware(
          latest,
          refreshed,
          gift,
          fields,
          original,
          confirmed: {...confirmed, involved},
          giverPersonId: giverPersonId,
        );
      }
    }
    doc = prepared;
    if (source != null && source != person) {
      return _relocateProtectedGift(
        current,
        ctx,
        source,
        person,
        fields,
        secret!,
      );
    }
    if (previousPerson is String &&
        previousPerson != person &&
        ctx.blocked(doc, previousPerson)) {
      ctx.requireKey(previousPerson);
      return _relocateProtectedGift(
        current,
        ctx,
        previousPerson,
        person,
        fields,
        previous!,
      );
    }
    if (!ctx.blocked(doc, person)) {
      if (previous?.isDeleted == true) {
        return (result: GiftWriteResult.giftDeleted, savedId: null);
      }
      if (original != null && previous == null) {
        return (result: GiftWriteResult.giftUnavailable, savedId: null);
      }
      final next = addPublicGift(
        common: doc,
        clock: _clock!,
        slots: ctx.slots,
        keyring: ctx.keyring,
        view: ctx.view,
        giftId: gift.id,
        fields: fields,
        alone: ctx.alone,
      );
      if (!identical(next, current.doc)) {
        await _store.saveDoc(next);
        _protectionState = AsyncData(current.copyWith(doc: next));
      }
      return (result: GiftWriteResult.saved, savedId: gift.id);
    }
    ctx.requireKey(person);
    final opened = await ctx.open(person);
    var scope = (await _store.readScope(person) ?? FamilyDoc.empty(doc.listId))
        .merge(opened.doc);
    final pending = await _store.readOverflow(person);
    final pendingRecord = pending.where((r) => r.id == gift.id).firstOrNull;
    if (secret == null &&
        previous?.isDeleted == true &&
        pendingRecord == null) {
      return (result: GiftWriteResult.giftDeleted, savedId: null);
    }
    if (original != null &&
        secret == null &&
        previous == null &&
        pendingRecord == null) {
      return (result: GiftWriteResult.giftUnavailable, savedId: null);
    }
    final beforeEdit = scope;
    final secretClock = HlcClock(
      node: ctx.view.me,
      last: _store.latestStoredStamp(scope),
    );
    if (doc.maxStamp != null) secretClock.receive(doc.maxStamp!);
    if (previous != null && !previous.isDeleted) {
      scope = scope.merge(_recordsDoc(doc.listId, [previous]));
    }
    if (pendingRecord != null) {
      scope = scope.merge(_recordsDoc(doc.listId, [pendingRecord]));
    }
    var nextCommon = doc;
    if (previous != null && !previous.isDeleted) {
      nextCommon = doc.delete(_clock!, Collections.gifts, gift.id);
    }
    ProtectedPersonReason? failure;
    FamilyDoc candidate;
    try {
      candidate = addSurpriseGift(scope, secretClock, gift.id, fields);
      if (liveSurpriseGifts(candidate) > kMaxSurpriseGifts ||
          !scopeFitsInSlot(candidate, person)) {
        throw const SurpriseSlotFullException();
      }
    } on ProtectedEnvelopeException catch (error) {
      failure = error is SurpriseGiftTooLargeException
          ? ProtectedPersonReason.giftTooLarge
          : ProtectedPersonReason.blockFull;
      candidate = scope.setChanged(
        secretClock,
        Collections.gifts,
        gift.id,
        fields,
      );
    }
    if (failure != null) {
      final record = candidate.record(Collections.gifts, gift.id)!;
      // Keep the previous shared value in the slot and the complete edited
      // record locally until retry succeeds.
      await _saveProtected(
        ctx,
        person,
        nextCommon,
        beforeEdit,
        opened.effective(publishedPolicy(doc, person)),
        [...pending.where((r) => r.id != gift.id), record],
      );
      throw ProtectedPersonException(
        person,
        reason: failure,
        savedLocally: true,
      );
    }
    final reason = await _saveProtected(
      ctx,
      person,
      nextCommon,
      candidate,
      opened.effective(publishedPolicy(doc, person)),
      pending.where((r) => r.id != gift.id).toList(),
    );
    if (reason != null) {
      // Una entrega guardada solo en local no pide valoración.
      throw ProtectedPersonException(
        person,
        reason: reason,
        savedLocally: true,
      );
    }
    return (result: GiftWriteResult.saved, savedId: gift.id);
  }

  Future<_GiftWriteOutcome> _relocateProtectedGift(
    FamilyState current,
    _ProtectionContext ctx,
    String source,
    String recipientId,
    Map<String, Object?> fields,
    SyncRecord record,
  ) async {
    final opened = await ctx.open(source);
    var scope = (await _store.readScope(source) ?? opened.doc).merge(
      opened.doc,
    );
    scope = scope.merge(_recordsDoc(current.doc.listId, [record]));
    final sourcePending = await _store.readOverflow(source);
    scope = scope.merge(
      _recordsDoc(
        current.doc.listId,
        sourcePending.where((r) => r.id == record.id),
      ),
    );
    if (scope.record(Collections.gifts, record.id)!.isDeleted) {
      return (result: GiftWriteResult.giftDeleted, savedId: null);
    }
    final clock = HlcClock(
      node: ctx.view.me,
      last: _store.latestStoredStamp(scope),
    );
    if (current.doc.maxStamp != null) clock.receive(current.doc.maxStamp!);
    final edited = scope
        .setChanged(clock, Collections.gifts, record.id, fields)
        .record(Collections.gifts, record.id)!;
    // An id cannot be reused after a tombstone, including moves between two
    // secret scopes. All writers derive the same destination id and preserve
    // field stamps so concurrent edits still converge.
    final id = publishedGiftId(
      listId: current.doc.listId,
      personId: source,
      giftId: record.id,
      salt: '${record[kPublishSaltField] ?? ''}\u0000recipient:$recipientId',
      rev: opened.authenticatedPolicy?.rev ?? 0,
    );
    final moved = SyncRecord(
      id: id,
      fields: {
        for (final e in edited.fields.entries)
          if (e.key != kPublishSaltField && e.key != kMovedInField)
            e.key: e.value,
      },
    );
    var common = current.doc;
    if (common.record(Collections.gifts, record.id)?.isDeleted == false) {
      common = common.delete(_clock!, Collections.gifts, record.id);
    }
    var slots = ctx.slots;
    final additional = <String, Map<String, Object?>>{};
    ProtectedPersonReason? failure;
    if (ctx.blocked(common, recipientId)) {
      final target = recipientId;
      final targetOpened = await ctx.open(target);
      var targetScope = (await _store.readScope(target) ?? targetOpened.doc)
          .merge(targetOpened.doc);
      final candidate = targetScope.merge(_recordsDoc(common.listId, [moved]));
      final overflow = _livePending(
        targetScope,
        await _store.readOverflow(target),
      );
      if (liveSurpriseGifts(candidate) > kMaxSurpriseGifts ||
          surpriseRecordBytes(moved) > kMaxSurpriseGiftBytes ||
          !scopeFitsInSlot(candidate, target)) {
        overflow.add(moved);
        failure = surpriseRecordBytes(moved) > kMaxSurpriseGiftBytes
            ? ProtectedPersonReason.giftTooLarge
            : ProtectedPersonReason.blockFull;
      } else {
        targetScope = candidate;
      }
      final published = await publishScope(
        slots: slots,
        opened: targetOpened,
        view: ctx.view,
        writerKeys: ctx.keys,
        keyring: ctx.keyring,
        policy: targetOpened.effective(publishedPolicy(common, target)),
        doc: targetScope,
        nowMillis: DateTime.now().millisecondsSinceEpoch,
      );
      final merged = await slots.merge([published.slot], view: ctx.view);
      slots = merged.$1;
      if (merged.$2 != 0) failure = ProtectedPersonReason.slotsFull;
      additional[target] = {
        'scope': published.scope.toJson(),
        'overflow': _recordsDoc(common.listId, overflow).toJson(),
      };
    } else {
      // publicGiftsBlockedFor above is the same guard used by addPublicGift.
      common = common.merge(_recordsDoc(common.listId, [moved]));
      final stamp = common.maxStamp;
      if (stamp != null) _clock!.receive(stamp);
    }
    final reason = await _saveProtected(
      ctx,
      source,
      common,
      scope.delete(clock, Collections.gifts, record.id),
      opened.effective(publishedPolicy(current.doc, source)),
      sourcePending.where((r) => r.id != record.id).toList(),
      preparedSlots: slots,
      additionalScopes: additional,
    );
    if (failure != null) {
      throw ProtectedPersonException(
        recipientId,
        reason: failure,
        savedLocally: true,
      );
    }
    // Keep a local move successful without using it to request a review
    // when there is no capacity to publish the source scope.
    return (result: GiftWriteResult.saved, savedId: reason == null ? id : null);
  }

  /// Capacity leftovers stay local; retry never falls back to the common.
  Future<void> retryPendingProtectedGifts(String person) =>
      _protectionSerial(() => _retryPendingWithinLock(person));

  /// [retryPendingProtectedGifts] for whoever already holds the v2 lock (the
  /// reconciliation). With [onlyIfProgress], nothing is resealed unless at
  /// least one pending gift now fits.
  Future<bool> _retryPendingWithinLock(
    String person, {
    bool onlyIfProgress = false,
  }) async {
    final current = await _requireFamily();
    final ctx = await _protectionContext(current.doc);
    if (ctx == null) {
      throw ProtectedPersonException(
        person,
        reason: ProtectedPersonReason.requiresV2,
      );
    }
    final opened = await ctx.open(person);
    var scope =
        (await _store.readScope(person) ?? FamilyDoc.empty(current.doc.listId))
            .merge(opened.doc);
    final remaining = <SyncRecord>[];
    for (final record in _livePending(
      scope,
      await _store.readOverflow(person),
    )) {
      final candidate = scope.merge(_recordsDoc(current.doc.listId, [record]));
      if (liveSurpriseGifts(candidate) <= kMaxSurpriseGifts &&
          surpriseRecordBytes(record) <= kMaxSurpriseGiftBytes &&
          scopeFitsInSlot(candidate, person)) {
        scope = candidate;
      } else {
        remaining.add(record);
      }
    }
    if (onlyIfProgress &&
        remaining.length ==
            _livePending(scope, await _store.readOverflow(person)).length) {
      return false;
    }
    await _saveProtected(
      ctx,
      person,
      current.doc,
      scope,
      opened.effective(publishedPolicy(current.doc, person)),
      remaining,
    );
    return true;
  }

  Future<SyncRecord?> _secretGift(String id) async {
    final current = await _requireFamily();
    final ctx = await _protectionContext(current.doc);
    if (ctx == null) return null;
    for (final person in ctx.keyring.people) {
      if (!ctx.view.selfEntitled(person)) continue;
      final opened = await openScope(
        personId: person,
        slots: ctx.slots,
        keyring: ctx.keyring,
        view: ctx.view,
      );
      if (opened == null) continue;
      final local = await _store.readScope(person);
      final record = await _localSecretRecord(
        current.doc.listId,
        person,
        id,
        opened,
        local,
      );
      if (record != null && !record.isDeleted) return record;
    }
    final public = current.doc.record(Collections.gifts, id);
    final person = public?['recipientId'];
    if (public != null &&
        !public.isDeleted &&
        person is String &&
        ctx.blocked(current.doc, person)) {
      ctx.requireKey(person);
      return public;
    }
    return null;
  }

  Future<SyncRecord?> _localSecretRecord(
    String listId,
    String person,
    String giftId,
    OpenedScope? opened,
    FamilyDoc? local,
  ) async {
    var scope = opened?.doc ?? FamilyDoc.empty(listId);
    if (local != null) scope = scope.merge(local);
    final pending = (await _store.readOverflow(person))
        .where((r) => r.id == giftId);
    if (pending.isNotEmpty) scope = scope.merge(_recordsDoc(listId, pending));
    return scope.record(Collections.gifts, giftId);
  }

  Future<bool> _deleteSecretGift(String id) =>
      _protectionSerial(() => _deleteSecretGiftNow(id));

  Future<bool> _deleteSecretGiftNow(String id) async {
    final record = await _secretGift(id);
    if (record == null) return false;
    final current = await _requireFamily();
    final ctx = (await _protectionContext(current.doc))!;
    final person = record['recipientId'] as String;
    final opened = await ctx.open(person);
    final scope = (await _store.readScope(person) ?? opened.doc).merge(
      opened.doc,
    );
    await _saveProtected(
      ctx,
      person,
      current.doc.record(Collections.gifts, id)?.isDeleted == false
          ? current.doc.delete(_clock!, Collections.gifts, id)
          : current.doc,
      scope.delete(
        HlcClock(node: ctx.view.me, last: _store.latestStoredStamp(scope)),
        Collections.gifts,
        id,
      ),
      opened.effective(publishedPolicy(current.doc, person)),
      (await _store.readOverflow(person)).where((r) => r.id != id).toList(),
    );
    return true;
  }

  Future<bool> _deleteGiftWithProtection(String id) async {
    final result = await _protectionSerial<bool?>(() async {
      if (await _secretGift(id) == null) return null;
      if (_pending.containsKey(id)) return false;
      _pending[id] = Timer(
        FamilyController.undoWindow,
        () => unawaited(_commitPending(id)),
      );
      _observeLifecycle();
      final current = await _current();
      _protectionState = AsyncData(
        current.copyWith(hiddenGiftIds: {...current.hiddenGiftIds, id}),
      );
      return true;
    });
    if (result != null) return result;
    return _deletePublicGiftWithUndo(id);
  }

  /// Called by sync while it owns the lock, after reading the verified
  /// registry/slots. Confirms requests and moves late public gifts safely.
  Future<bool> reconcileProtectedPeopleWithinLock() => _serial(() async {
    await _recoverProtection();
    var changed = false;
    var current = await _requireFamily();
    var ctx = await _protectionContext(current.doc);
    if (ctx == null) return false;
    // 1.0.6: aprobada la ficha nueva, ya no hay persona de antes que ocultar.
    final identity = current.identity;
    if (identity != null &&
        identity.formerSelf.isNotEmpty &&
        ctx.view.selfApproved &&
        ctx.view.myPerson == identity.selfRecipientId) {
      final cleared = identity.withFormerSelf(const {});
      await _store.saveIdentity(cleared);
      current = current.copyWith(identity: cleared);
      _protectionState = AsyncData(current);
      ctx = await _protectionContext(current.doc);
      if (ctx == null) return false;
    }
    final otherPeople = otherMobilePeople(ctx.view);
    if (otherPeople.length != current.otherDevicePeople.length ||
        !otherPeople.containsAll(current.otherDevicePeople)) {
      _protectionState = AsyncData(
        current.copyWith(otherDevicePeople: otherPeople),
      );
    }
    // 1.0.6: toda persona con un dispositivo en la familia tiene sus regalos
    // en secreto. La activa cualquier móvil con derecho, sin esperar a que
    // nadie la pida; una desactivación firmada desde otro móvil se respeta
    // (ya hay registro de su política).
    for (final person in peopleToAutoProtect(
      current.doc,
      ctx.view,
      slots: ctx.slots,
    )) {
      try {
        await _transitionProtection(person, true);
        changed = true;
      } on ProtectedPersonException {
        // Sin clave o sin poder abrir el bloque: lo intenta la próxima vuelta
        // u otro móvil con derecho; mientras, la capa de pantalla oculta.
      } on SlotPublishBlockedException {
        // Igual.
      }
      ctx = await _protectionContext((await _current()).doc);
      if (ctx == null) return changed;
    }
    // La propia persona, si nadie lo ha hecho aún: pide la protección para
    // que la confirme un móvil con derecho (también uno 1.0.5, que confirma
    // solo). Sin nadie que pueda confirmarla no publica nada.
    if (await _requestOwnProtection(ctx!)) changed = true;
    for (final person in {
      ...publishedPolicies(current.doc).keys,
      ...ctx.keyring.people,
    }) {
      if (!ctx!.view.selfEntitled(person)) continue;
      final common = (await _current()).doc;
      final policy = ctx.slots.authenticatedPolicy(person, ctx.view);
      if (ctx.blocked(common, person) &&
          (policy == null || !policy.hideOwnGifts)) {
        await _transitionProtection(person, true);
        changed = true;
      } else {
        final opened = await openScope(
          personId: person,
          slots: ctx.slots,
          keyring: ctx.keyring,
          view: ctx.view,
        );
        if (opened == null || opened.unreadableWriters.isNotEmpty) continue;
        final scope = (await _store.readScope(person) ?? opened.doc).merge(
          opened.doc,
        );
        final pending = await _store.readOverflow(person);
        final livePending = _livePending(scope, pending);
        final key = ctx.keyring.sealingKeyFor(
          person,
          ctx.view.epoch,
          allowed: ctx.view.entitledDevices(person),
        );
        if (key == null) {
          continue;
        }
        var result = reconcileProtection(
          common: common,
          scope: scope,
          opened: opened,
          key: key,
          publicClock: _clock!,
          scopeClock: HlcClock(
            node: ctx.view.me,
            last: _store.latestStoredStamp(scope),
          ),
        );
        final overflow = [...result.overflow];
        // The model bounds each batch. Finish all public batches before the
        // engine can send any common, including more than eight late gifts.
        while (result.policy.hideOwnGifts &&
            (result.common.collections[Collections.gifts]?.values ??
                    const <SyncRecord>[])
                .any((r) => !r.isDeleted && r['recipientId'] == person)) {
          result = reconcileProtection(
            common: result.common,
            scope: result.scope,
            opened: opened,
            key: key,
            publicClock: _clock!,
            scopeClock: HlcClock(
              node: ctx.view.me,
              last: result.scope.maxStamp,
            ),
          );
          overflow.addAll(result.overflow);
        }
        if (result.common.canonicalJson() != common.canonicalJson() ||
            result.scope.canonicalJson() != scope.canonicalJson() ||
            _recordsDoc(common.listId, pending).canonicalJson() !=
                _recordsDoc(common.listId, livePending).canonicalJson()) {
          await _saveProtected(
            ctx,
            person,
            result.common,
            result.scope,
            result.policy,
            [...livePending, ...overflow],
          );
          changed = true;
        }
      }
      ctx = await _protectionContext((await _current()).doc);
    }
    // Lo que no cupo en el bloque y quedó guardado aquí (`saveOverflow`) se
    // vuelve a intentar solo, por si ahora cabe (otra versión con un tope
    // mayor, o se ha borrado algo). Sin avance no se vuelve a sellar nada.
    for (final person in ctx?.keyring.people ?? const <String>[]) {
      if (!ctx!.view.selfEntitled(person)) continue;
      if ((await _store.readOverflow(person)).isEmpty) continue;
      try {
        if (await _retryPendingWithinLock(person, onlyIfProgress: true)) {
          changed = true;
        }
      } on ProtectedPersonException {
        // Sigue pendiente; la hoja de pendientes lo explica.
      } on SlotPublishBlockedException {
        // Igual.
      }
    }
    return changed;
  });

  Future<bool> _requestOwnProtection(_ProtectionContext ctx) async {
    final view = ctx.view;
    final mine = view.myPerson;
    final registry = ctx.registry;
    if (mine == null ||
        registry == null ||
        nothingToProtectFor((await _current()).doc, mine) ||
        view.self.kind != DeviceKind.mobile ||
        !view.selfApproved ||
        view.revokedByOthers ||
        !view.accompanied(mine)) {
      return false;
    }
    final current = await _current();
    if (current.doc.record(Collections.policies, mine) != null ||
        ctx.slots.authenticatedPolicy(mine, view) != null) {
      return false;
    }
    final reason = await protectionRequestReason((
      registry: registry,
      view: view,
      keys: ctx.keys,
    ), mine);
    if (reason != null) return false;
    final next = protection_policy.requestProtection(
      current.doc,
      _clock!,
      mine,
      authenticated: null,
    );
    if (identical(next, current.doc)) return false;
    await _store.saveDoc(next);
    _protectionState = AsyncData(current.copyWith(doc: next));
    return true;
  }
}

/// No se han podido poner en secreto los regalos de [personId] antes de
/// aprobar su móvil nuevo: no se aprueba (1.0.6).
class PairingProtectionException implements Exception {
  /// Crea el error.
  const PairingProtectionException(this.personId);

  /// La persona del móvil nuevo.
  final String personId;

  @override
  String toString() => 'PairingProtectionException';
}
