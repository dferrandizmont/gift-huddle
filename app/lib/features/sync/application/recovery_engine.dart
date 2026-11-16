import 'dart:math' show max;

import '../../../core/sync/envelope.dart';
import '../../../core/sync/access_policy.dart';
import '../../../core/sync/family_doc.dart';
import '../../../core/sync/hlc.dart';
import '../../../core/sync/protected_doc.dart';
import '../../../core/sync/recovery.dart';
import '../../family/data/family_store.dart';
import '../../family/data/generation_store.dart';
import '../data/sync_transport_v2.dart';
import '../data/recovery_transport.dart' show knownRecoveryServerCodes;
import 'common_v2.dart';
import 'recovery_controller.dart';
import 'recovery_local_merge.dart';
import 'stored_sync_v2_local.dart';
import 'sync_v2_engine.dart';

/// Captures the normative inventory from a pinned generation under the family
/// lock. The capsule never substitutes references for local-only resources.
class RecoveryExporter {
  RecoveryExporter(this.generations, this.reader);
  final GenerationStore generations;
  final RecoveryReader reader;

  Future<bool> _hasOtherGeneration(String sid) async {
    for (final id in await generations.generationIds(
      includeRecoveryRetained: false,
    )) {
      if (id == sid) continue;
      final identity = await (await generations.open(id)).family.readSyncV2();
      // Recovery archives are aliases of this generation, not a renewal.
      if (identity?.syncId != sid) return true;
    }
    return false;
  }

  Future<RecoveryCapsulePayload> capture(String sid) async {
    final context = await generations.open(sid);
    final store = context.family;
    await store.assertWritable();
    final blockers = await store.recoveryBlockers();
    final otherGeneration = await _hasOtherGeneration(sid);
    if (blockers.person ||
        blockers.protection ||
        blockers.resources ||
        await store.readPendingV2() != null ||
        await store.readLegacyV1() != null ||
        await generations.journal.read() != null ||
        otherGeneration ||
        await store.recoveryActivationPending()) {
      throw const RecoveryIncomplete('transition_pending');
    }
    final identity = (await store.readSyncV2())!;
    final family = (await store.load())!;
    final keys = (await context.deviceKeys.read())!;
    final commonRaw = await store.readCommonKeys();
    if (commonRaw == null &&
        (await store.commonKeysMarked() ||
            await store.readCommonFormatFloor() >= 2)) {
      throw const RecoveryIncomplete('missing_common_keyring');
    }
    final common = commonRaw == null
        ? CommonKeyState()
        : CommonKeyState.fromJson(commonRaw);
    final state = V2SyncState.fromJson(await store.readSyncV2State());
    final proof = await store.readV1ProofKey();
    final floors = await store.readRecoveryRevisionFloors();
    var hlc =
        floors.hlc ??
        family.doc.maxStamp ??
        Hlc(millis: 0, counter: 0, node: identity.deviceId);
    void observe(FamilyDoc doc) {
      if (doc.maxStamp != null && doc.maxStamp! > hlc) hlc = doc.maxStamp!;
    }

    observe(family.doc);
    final scopes = await store.readRecoveryScopes();
    for (final scope in scopes.values) {
      observe(scope);
    }
    if (hlc.node != identity.deviceId) {
      final counter = hlc.counter + 1;
      hlc = Hlc(
        millis: hlc.millis + (counter > kMaxHlcCounter ? 1 : 0),
        counter: counter > kMaxHlcCounter ? 0 : counter,
        node: identity.deviceId,
      );
    }
    final revisions = <String, int>{};
    for (final e in floors.slots.entries) {
      final pair = e.key.split('/');
      if (pair[1] == identity.deviceId) revisions[pair[0]] = e.value;
    }
    for (final slot in (await store.readSlots()).all) {
      final h = slot.header;
      if (h.writer == identity.deviceId) {
        revisions[h.personId] = max(revisions[h.personId] ?? 0, h.revision);
      }
    }
    final transition = RecoveryTransitionState(
      v1Proof: proof == null
          ? null
          : RecoveryV1Proof(
              listId: (proof as Map)['l'] as String,
              key: FamilyKey.fromBase64Url(proof['k'] as String),
              sinceMillis: proof['s'] as int,
            ),
      legacyV1Pending: await store.readLegacyV1() != null,
      pendingV2: await store.readPendingV2() != null,
      personChangePending: blockers.person,
      protectionPending: blockers.protection,
      renewalPending:
          await generations.journal.read() != null || otherGeneration,
      localResourcesPending:
          blockers.resources || await store.recoveryActivationPending(),
    );
    if (transition.blocksPublication ||
        state.commonMigration ||
        state.commonMigrationPut ||
        state.version == null) {
      throw const RecoveryIncomplete('transition_pending');
    }
    final payload = RecoveryCapsulePayload(
      identity: identity,
      deviceName: family.identity.deviceName,
      peerName: family.identity.peerName,
      paired: family.identity.paired,
      personId: family.identity.selfRecipientId,
      deviceKeys: keys,
      familyKey: family.key,
      registry: (await store.readRegistry())!,
      commonKeys: RecoveryCommonKeys(
        keyring: common.keyring,
        revision: common.revision,
        lastKid: common.lastKid,
      ),
      surpriseKeys: await context.deviceKeys.readKeyring(identity.listId),
      commonKeysMarked: await store.commonKeysMarked(),
      commonFormatFloor: await store.readCommonFormatFloor(),
      resume: RecoveryResumeState(
        versionFloor: state.version!,
        hlc: hlc,
        slotRevisions: revisions,
        minSlotRevisions: state.minSlotRevisions,
        knownMembers: state.knownMembers,
        pendingRevocations: state.pendingRevocations,
        pendingUnbackedRevocations: state.pendingUnbackedRevocations,
        revocationOperations: state.revocationOperations,
        keyPackageOutbox: state.keyPackageOutbox,
        commonKeyOutbox: common.outbox,
        commonFormatV2: state.commonFormatV2,
        commonMigration: state.commonMigration,
        commonMigrationPut: state.commonMigrationPut,
      ),
      transition: transition,
    );
    // Full remote read proves local document/scopes can be reconstructed.
    final result = await reader.download(payload, const {}, null);
    final remote = result.installation;
    if (remote == null || result.incompleteReason != null) {
      throw RecoveryIncomplete(result.incompleteReason ?? 'incomplete_remote');
    }
    bool covered(FamilyDoc local, FamilyDoc remote) =>
        remote.merge(local).canonicalJson() == remote.canonicalJson();
    if (!covered(family.doc, remote.doc) ||
        scopes.entries.any(
          (e) =>
              e.key != payload.personId &&
              !covered(
                e.value,
                remote.scopes[e.key] ?? FamilyDoc.empty(identity.listId),
              ),
        )) {
      throw const RecoveryIncomplete('local_resources_pending');
    }
    // Keep local obligations and maxima even when a GET learns newer keys.
    return mergeRecoveryLocal(remote.payload, context);
  }
}

/// Reads through the production engine on isolated encrypted stores. Neither
/// validation nor download can create a list or publish an empty document.
class EngineRecoveryReader implements RecoveryReader {
  EngineRecoveryReader({required this.generations, required this.transport});
  final GenerationStore generations;
  final SyncV2Transport transport;

  Future<RecoveryInstallation> _read(
    RecoveryCapsulePayload p,
    GenerationContext? local,
  ) async {
    final target = generations.recoveryReader(p.identity.syncId);
    try {
      return await _readWorkspace(p, local);
    } finally {
      await target.family.clearRecoveryWorkspace();
    }
  }

  Future<RecoveryInstallation> _readWorkspace(
    RecoveryCapsulePayload p,
    GenerationContext? local,
  ) async {
    if (p.transition.blocksPublication ||
        p.resume.commonMigration ||
        p.resume.commonMigrationPut) {
      throw const RecoveryIncomplete('transition_pending');
    }
    p = await mergeRecoveryLocal(p, local);
    final target = generations.recoveryReader(p.identity.syncId);
    for (final person in (await target.family.readRecoveryScopes()).keys) {
      await target.family.deleteScope(person);
    }
    await target.deviceKeys.restoreReadWorkspace(p.deviceKeys);
    await target.deviceKeys.purgePerson(p.personId);
    await target.deviceKeys.saveKeyring(p.identity.listId, p.surpriseKeys);
    await target.family.saveFamily(
      StoredFamily(
        identity: FamilyIdentity(
          listId: p.identity.listId,
          node: p.identity.deviceId,
          deviceName: p.deviceName,
          selfRecipientId: p.personId,
          paired: p.paired,
          peerName: p.peerName,
        ),
        key: p.familyKey,
        doc: FamilyDoc.empty(p.identity.listId),
      ),
    );
    await target.family.saveSyncV2(p.identity);
    await target.family.saveRegistry(p.registry);
    await target.family.saveSlots(SlotSet.empty);
    await target.family.saveCommonKeys(
      CommonKeyState(
        keyring: p.commonKeys.keyring,
        revision: p.commonKeys.revision,
        lastKid: p.commonKeys.lastKid,
        outbox: p.resume.commonKeyOutbox,
      ).toJson(),
    );
    await target.family.raiseCommonFormatFloor(p.commonFormatFloor);
    if (p.commonKeysMarked) await target.family.markCommonKeys();
    await target.family.saveSyncV2State(
      V2SyncState(
        created: true,
        version: p.resume.versionFloor,
        minSlotRevisions: {
          ...p.resume.minSlotRevisions,
          for (final e in p.resume.slotRevisions.entries)
            '${e.key}/${p.identity.deviceId}': max(
              e.value,
              p.resume.minSlotRevisions['${e.key}/${p.identity.deviceId}'] ?? 0,
            ),
        },
        knownMembers: p.resume.knownMembers,
        pendingRevocations: p.resume.pendingRevocations,
        pendingUnbackedRevocations: p.resume.pendingUnbackedRevocations,
        revocationOperations: p.resume.revocationOperations,
        keyPackageOutbox: p.resume.keyPackageOutbox,
        commonFormatV2: p.resume.commonFormatV2,
      ).toJson(),
    );
    final adapter = StoredSyncV2Local(
      store: target.family,
      deviceKeys: target.deviceKeys,
      identity: p.identity,
      keys: p.deviceKeys,
      familyKey: p.familyKey,
    );
    final auth = V2Auth(
      syncId: p.identity.syncId,
      deviceId: p.identity.deviceId,
      credential: p.deviceKeys.serviceCredential,
    );
    try {
      final renewal = await transport.getRenewal(auth);
      if (renewal.renewal != null) {
        throw const RecoveryIncomplete('renewal_pending');
      }
      final outcome = await SyncV2Engine(
        transport: transport,
        local: adapter,
        readOnly: true,
        commonV2Ready: false,
      ).sync();
      if (!outcome.view.selfApproved || outcome.view.myPerson != p.personId) {
        throw const RecoveryIncomplete('person_changed');
      }
      final latestRenewal = await transport.getRenewal(auth);
      if (latestRenewal.renewal != null) {
        throw const RecoveryIncomplete('renewal_pending');
      }
      final common = (await adapter.readCommonKeys())!;
      final state = await adapter.readState();
      final scopes = <String, FamilyDoc>{};
      for (final person in outcome.view.livePeople) {
        if (!outcome.view.selfEntitled(person)) continue;
        final scope = await target.family.readScope(person);
        if (scope != null) scopes[person] = scope;
      }
      final surprises = {
        for (final key in p.surpriseKeys.keys)
          '${key.personId}/${key.epoch}/${key.kid}': key,
      };
      for (final key in (await adapter.updateKeyring((k) => k)).keys) {
        final id = '${key.personId}/${key.epoch}/${key.kid}';
        surprises[id] = surprises[id]?.withAudience(key.audience) ?? key;
      }
      final updated = await RecoveryCapsulePayload.fromJson({
        ...p.toJson(),
        'registry': (await adapter.registry()).toLocalStoreJson(),
        'commonKeys': RecoveryCommonKeys(
          keyring: unionRecoveryCommonKeys(
            p.commonKeys.keyring,
            common.keyring,
          ),
          revision: common.revision,
          lastKid: common.lastKid,
        ).toJson(),
        'surpriseKeys': SurpriseKeyring(surprises.values).toJson(),
        'commonFormatFloor': max(
          p.commonFormatFloor,
          await target.family.readCommonFormatFloor(),
        ),
        'commonKeysMarked':
            p.commonKeysMarked || await target.family.commonKeysMarked(),
        'resume': {
          ...p.resume.toJson(),
          'versionFloor': state.version,
          'commonFormatV2': p.resume.commonFormatV2 || state.commonFormatV2,
        },
      });
      return RecoveryInstallation(
        payload: updated,
        doc: await adapter.common(),
        slots: await adapter.slots(),
        scopes: scopes,
      );
    } on V2ForbiddenException catch (e) {
      throw RecoveryIncomplete(
        knownRecoveryServerCodes.contains(e.code) ? e.code : 'invalid_response',
      );
    } on V2RenewalGoneException {
      throw const RecoveryIncomplete('generation_gone');
    } on V2RecoveryIncompleteException catch (e) {
      throw RecoveryIncomplete(e.code);
    } on V2RevokedException {
      throw const RecoveryIncomplete('revoked');
    } on V2RollbackException {
      throw const RecoveryIncomplete('snapshot_rollback');
    } on V2ListGoneException {
      throw const RecoveryIncomplete('generation_gone');
    }
  }

  @override
  Future<RecoveryCapsulePayload> verify(
    RecoveryCapsulePayload capsule,
    GenerationContext? local,
  ) async => (await _read(capsule, local)).payload;

  @override
  Future<RecoveryDownload> download(
    RecoveryCapsulePayload capsule,
    Map<String, Object?> progress,
    GenerationContext? local,
  ) async => RecoveryDownload(
    progress: const {'verified': true},
    installation: await _read(capsule, local),
  );
}
