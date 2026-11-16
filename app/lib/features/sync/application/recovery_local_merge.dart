import 'dart:math';

import '../../../core/sync/access_policy.dart';
import '../../../core/sync/device_registry.dart';
import '../../../core/sync/family_candidate.dart';
import '../../../core/sync/family_doc.dart';
import '../../../core/sync/hlc.dart';
import '../../../core/sync/recovery.dart';
import '../../family/data/generation_store.dart';
import 'common_v2.dart';
import 'sync_v2_engine.dart' show V2SyncState;

List<Map<String, Object?>> _union(Iterable<Map<String, Object?>> values) =>
    {for (final value in values) canonicalJsonOf(value): value}.values.toList();

/// Preserve every signed declaration. Registry.merge normally has eviction
/// limits; recovery must stop instead of silently losing durable evidence.
Future<DeviceRegistry> unionRecoveryRegistry(
  DeviceRegistry a,
  DeviceRegistry b,
  RegistryAnchor anchor,
) async {
  final merged = await a.merge(b, anchor: anchor);
  final actual = merged.toLocalStoreJson();
  for (final field in [
    'records',
    'vouches',
    'revocations',
    'localTypeConflicts',
  ]) {
    final expected = <String>{
      for (final j in [a.toLocalStoreJson(), b.toLocalStoreJson()])
        for (final value in j[field] as List? ?? []) canonicalJsonOf(value),
    };
    final got = {
      for (final value in actual[field] as List? ?? []) canonicalJsonOf(value),
    };
    if (!got.containsAll(expected)) {
      throw const FormatException('recovery registry union exceeds limits');
    }
  }
  return merged;
}

FamilyKeyring unionRecoveryCommonKeys(FamilyKeyring a, FamilyKeyring b) {
  final entries = <String, Map<String, Object?>>{};
  for (final keyring in [a, b]) {
    for (final raw in keyring.toJson()['keys'] as List) {
      final entry = Map<String, Object?>.from(raw as Map);
      final kid = FamilyCandidate.fromJson(entry['c']).kid;
      final old = entries[kid];
      if (old == null) {
        entries[kid] = entry;
        continue;
      }
      if (canonicalJsonOf(old['c']) != canonicalJsonOf(entry['c'])) {
        throw const FormatException('conflicting recovery key provenance');
      }
      final senders = <String, AudienceMember>{};
      for (final source in [old, entry]) {
        for (final value in source['f'] as List? ?? []) {
          final sender = AudienceMember.fromJson(value);
          if (senders[sender.deviceId] != null &&
              senders[sender.deviceId]!.recordDigest != sender.recordDigest) {
            throw const FormatException(
              'conflicting recovery sender provenance',
            );
          }
          senders[sender.deviceId] = sender;
        }
      }
      entries[kid] = {
        'c': old['c'],
        'o': old['o'] == true || entry['o'] == true,
        'h': old['h'] == true || entry['h'] == true,
        'x': old['x'] == true || entry['x'] == true,
        'f': [
          for (final id in senders.keys.toList()..sort()) senders[id]!.toJson(),
        ],
        'r': {
          for (final source in [old, entry])
            ...((source['r'] as List?)?.cast<String>() ?? <String>[]),
        }.toList()..sort(),
      };
    }
  }
  return FamilyKeyring.fromJson({'v': 1, 'keys': entries.values.toList()});
}

/// A stale capsule cannot replace local obligations, keys, revisions or proof.
/// This supplements the remote reader's validation; it does not grant authority
/// to candidates or execute outboxes. All limits fail closed without pruning.
Future<RecoveryCapsulePayload> mergeRecoveryLocal(
  RecoveryCapsulePayload p,
  GenerationContext? local,
) async {
  if (local == null) return p;
  final family = await local.family.load();
  final identity = await local.family.readSyncV2();
  if (identity?.deviceId != p.identity.deviceId ||
      identity?.listId != p.identity.listId ||
      family?.identity.selfRecipientId != p.personId) {
    throw const FormatException('local recovery identity conflict');
  }
  final keys = await local.deviceKeys.read();
  if (keys == null ||
      canonicalJsonOf({...keys.toJson()}..remove('c')) !=
          canonicalJsonOf({...p.deviceKeys.toJson()}..remove('c'))) {
    throw const FormatException('local recovery keys conflict');
  }
  final state = V2SyncState.fromJson(await local.family.readSyncV2State());
  final commonRaw = await local.family.readCommonKeys();
  final common = commonRaw == null ? null : CommonKeyState.fromJson(commonRaw);
  final localKeys = await local.deviceKeys.readKeyring(p.identity.listId);
  final surprise = <String, SurpriseKey>{};
  for (final key in [...p.surpriseKeys.keys, ...localKeys.keys]) {
    if (key.personId == p.personId) continue;
    final id = '${key.personId}/${key.epoch}/${key.kid}';
    surprise[id] = surprise[id]?.withAudience(key.audience) ?? key;
  }
  final registry = await local.family.readRegistry();
  final anchor = RegistryAnchor(
    deviceId: p.identity.deviceId,
    signingKey: p.deviceKeys.publicKeys.signing,
  );
  final floors = await local.family.readRecoveryRevisionFloors();
  var hlc = p.resume.hlc;
  for (final value in [family?.doc.maxStamp, floors.hlc]) {
    if (value != null && value > hlc) hlc = value;
  }
  if (hlc.node != p.identity.deviceId) {
    final counter = hlc.counter + 1;
    hlc = Hlc(
      millis: hlc.millis + (counter > kMaxHlcCounter ? 1 : 0),
      counter: counter > kMaxHlcCounter ? 0 : counter,
      node: p.identity.deviceId,
    );
    // Includes the millis overflow check. Never wrap or reset a writer clock.
    hlc = Hlc.parse(hlc.pack());
  }
  final slots = {...p.resume.slotRevisions};
  for (final slot in (await local.family.readSlots()).all) {
    if (slot.header.writer == p.identity.deviceId) {
      slots[slot.header.personId] = max(
        slots[slot.header.personId] ?? 0,
        slot.header.revision,
      );
    }
  }
  for (final e in floors.slots.entries) {
    final parts = e.key.split('/');
    if (parts[1] == p.identity.deviceId) {
      slots[parts[0]] = max(slots[parts[0]] ?? 0, e.value);
    }
  }
  final minSlots = {...p.resume.minSlotRevisions};
  for (final e in state.minSlotRevisions.entries) {
    minSlots[e.key] = max(minSlots[e.key] ?? 0, e.value);
  }
  final ops = {...p.resume.revocationOperations};
  for (final e in state.revocationOperations.entries) {
    if (ops.containsKey(e.key) &&
        canonicalJsonOf(ops[e.key]) != canonicalJsonOf(e.value)) {
      throw const FormatException('conflicting revocation operation');
    }
    ops[e.key] = e.value;
  }
  final proof = await local.family.readV1ProofKey();
  final formatFloor = max(
    p.commonFormatFloor,
    await local.family.readCommonFormatFloor(),
  );
  final resume = RecoveryResumeState(
    versionFloor: max(p.resume.versionFloor, state.version ?? 0),
    hlc: hlc,
    slotRevisions: slots,
    minSlotRevisions: minSlots,
    knownMembers: {...p.resume.knownMembers, ...state.knownMembers},
    pendingRevocations: {
      ...p.resume.pendingRevocations,
      ...state.pendingRevocations,
    },
    pendingUnbackedRevocations: {
      ...p.resume.pendingUnbackedRevocations,
      ...state.pendingUnbackedRevocations,
    },
    revocationOperations: ops,
    keyPackageOutbox: _union([
      ...p.resume.keyPackageOutbox,
      ...state.keyPackageOutbox,
    ]),
    commonKeyOutbox: _union([...p.resume.commonKeyOutbox, ...?common?.outbox]),
    commonFormatV2:
        p.resume.commonFormatV2 || state.commonFormatV2 || formatFloor >= 2,
    commonMigration: p.resume.commonMigration || state.commonMigration,
    commonMigrationPut: p.resume.commonMigrationPut || state.commonMigrationPut,
  );
  final commonKeys = RecoveryCommonKeys(
    keyring: common == null
        ? p.commonKeys.keyring
        : unionRecoveryCommonKeys(p.commonKeys.keyring, common.keyring),
    revision: max(p.commonKeys.revision, common?.revision ?? 0),
    lastKid: common?.lastKid ?? p.commonKeys.lastKid,
  );
  final json = {
    ...p.toJson(),
    'registry':
        (registry == null
                ? p.registry
                : await unionRecoveryRegistry(p.registry, registry, anchor))
            .toLocalStoreJson(),
    'commonKeys': commonKeys.toJson(),
    'surpriseKeys': SurpriseKeyring(surprise.values).toJson(),
    'commonKeysMarked':
        p.commonKeysMarked || await local.family.commonKeysMarked(),
    'commonFormatFloor': formatFloor,
    'resume': resume.toJson(),
    'transition': {
      ...p.transition.toJson(),
      if (proof != null)
        'v1Proof': {
          'v': 1,
          'listId': (proof as Map)['l'],
          'key': proof['k'],
          'since': proof['s'],
        },
    },
  };
  return RecoveryCapsulePayload.fromJson(json);
}
