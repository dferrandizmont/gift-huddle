import 'dart:math';

import 'package:clock/clock.dart';

import '../../../core/sync/device_keys.dart';
import '../../../core/sync/device_registry.dart';
import '../../../core/sync/envelope.dart';
import '../../../core/sync/family_doc.dart';
import '../../../core/sync/family_candidate.dart' show FamilyKeyException;
import '../../../core/sync/model.dart' show Collections;
import '../../../core/sync/protected_doc.dart';
import '../../../core/sync/recovery.dart';
import '../../../core/sync/recovery_locator.dart';
import '../../../core/sync/wish_boundary.dart';
import '../../family/data/family_store.dart';
import '../../family/data/generation_store.dart';
import '../../family/data/recovery_store.dart';
import '../data/recovery_transport.dart';
import 'common_v2.dart';
import 'migration_v2.dart' show kLegacyV1MaxAge;

import 'recovery_local_merge.dart';
import 'sync_v2_engine.dart' show V2SyncState;

/// Implemented by the read-only engine adapter in 5.4. These methods may only
/// GET: no createList/PUT, no ordinary engine on an empty document. Verify the
/// current generation, renewal status, permissions, signatures, audiences and
/// contexts. Merge all local key provenance and durable obligations. Missing
/// packages are incomplete, never empty scopes. Each download call is one
/// resumable read; its cursor and bytes are saved before the next call.
abstract interface class RecoveryReader {
  Future<RecoveryCapsulePayload> verify(
    RecoveryCapsulePayload capsule,
    GenerationContext? local,
  );
  Future<RecoveryDownload> download(
    RecoveryCapsulePayload capsule,
    Map<String, Object?> progress,
    GenerationContext? local,
  );
}

class RecoveryIncomplete implements Exception {
  const RecoveryIncomplete(this.code);
  final String code;
}

class RecoveryDownload {
  const RecoveryDownload({
    required this.progress,
    this.installation,
    this.incompleteReason,
  });
  final Map<String, Object?> progress;
  final RecoveryInstallation? installation;
  final String? incompleteReason;
}

/// Only a fully verified coherent snapshot can produce this object. The
/// payload contains the updated keyrings, registry and merged resume maxima.
/// Slots have already been verified; local storage parsing is not verification.
class RecoveryInstallation {
  const RecoveryInstallation({
    required this.payload,
    required this.doc,
    required this.slots,
    required this.scopes,
  });
  final RecoveryCapsulePayload payload;
  final FamilyDoc doc;
  final SlotSet slots;
  final Map<String, FamilyDoc> scopes;

  Map<String, Object?> toJson() => {
    'payload': payload.toJson(),
    'doc': doc.toJson(),
    'slots': slots.toJson(),
    'scopes': {for (final e in scopes.entries) e.key: e.value.toJson()},
  };

  static Future<RecoveryInstallation> fromJson(Object? raw) async {
    final j = raw as Map;
    return RecoveryInstallation(
      payload: await RecoveryCapsulePayload.fromJson(j['payload']),
      doc: FamilyDoc.fromJson(Map<String, Object?>.from(j['doc'] as Map)),
      slots: SlotSet.fromLocalStoreJson(j['slots']),
      scopes: {
        for (final e in (j['scopes'] as Map).entries)
          e.key as String: FamilyDoc.fromJson(
            Map<String, Object?>.from(e.value as Map),
          ),
      },
    );
  }
}

/// The caller owns the family lock once across start/resume and suspends edits
/// until this returns. Startup must resume before exposing editable controllers
/// or processing Gone. No retries on transport errors; call resume with backoff.
class RecoveryController {
  RecoveryController({
    required this.store,
    required this.generations,
    required this.transport,
    required this.reader,
    this.onPhase,
    this.onClaimSent,
  });
  final RecoveryStore store;
  final GenerationStore generations;
  final RecoveryTransport transport;
  final RecoveryReader reader;
  final void Function(RecoveryPhase phase)? onPhase;
  final void Function()? onClaimSent;

  Future<RecoveryJournal> start(
    RecoveryCode code, {
    bool replaceExisting = false,
  }) async {
    final previous = await store.readRestore();
    if (previous != null && previous.phase != RecoveryPhase.active) {
      if (replaceExisting &&
          previous.phase == RecoveryPhase.needsAttention &&
          previous.data['reason'] == 'different_family' &&
          previous.data['entropy'] == encodeBase64Url(code.entropy)) {
        await store.saveRestore(
          previous.next(
            RecoveryPhase.values.byName(
              previous.data['resumePhase'] as String? ?? 'located',
            ),
            {'replaceExisting': true, 'reason': null},
          ),
        );
        return resume();
      }
      throw StateError('recovery already exists');
    }
    final locator = await deriveRecoveryLocator(code);
    final j = RecoveryJournal(
      operationId: encodeBase64Url(secureRandomBytes(16)),
      phase: RecoveryPhase.locating,
      data: {
        'entropy': encodeBase64Url(code.entropy),
        'recoveryId': locator.recoveryId,
        'source': await generations.recoverySource(
          replaceExisting: replaceExisting,
        ),
        'replaceExisting': replaceExisting,
      },
    );
    await store.saveRestore(j);
    return resume();
  }

  /// Caller owns the same family lock as start/resume. Abandoning never rolls
  /// back a remote claim or deletes a namespace already selected by activation.
  Future<void> abandon() => abandonLocal(store, generations);

  static Future<void> abandonLocal(
    RecoveryStore store,
    GenerationStore generations,
  ) async {
    final j = await store.readRestore();
    if (j != null) {
      var raw = j.data['payload'];
      if (raw == null && j.data['capsule'] != null) {
        try {
          final capsule = RecoveryCapsule.fromJson(j.data['capsule']);
          raw = (await openRecoveryCapsule(
            capsule.bytes,
            RecoveryCode(decodeBase64Url(j.data['entropy'] as String)),
            expectedRevision: peekRecoveryCapsule(capsule.bytes).revision,
          )).toJson();
        } on FormatException {
          /* No verified workspace to locate. */
        } on RecoveryException {
          /* Invalid capsules never create a workspace. */
        }
      }
      if (raw != null) {
        final p = await RecoveryCapsulePayload.fromJson(raw);
        if (j.claimSent) {
          // An ambiguous claim may already have retired this installation.
          final local = await generations.recoveryLocal(p.identity.syncId);
          final keys = await local?.deviceKeys.read();
          final claimed = j.data['claimedPayload'] as Map?;
          final claimedCredential = (claimed?['deviceKeys'] as Map?)?['c'];
          if (keys == null ||
              encodeBase64Url(keys.serviceCredential) != claimedCredential) {
            await store.markTransferred(p.identity.syncId);
          } else if (j.phase == RecoveryPhase.installPrepared) {
            // Activation committed before the crash. Preserve maintenance
            // material for this installed principal before dropping the intent.
            await store.completeRestore(j, p.identity.syncId, {
              'entropy': j.data['entropy'],
              'recoveryId': j.data['recoveryId'],
              'revision': j.data['receiptRevision'],
              'receiptRevision': j.data['receiptRevision'],
              'personId': p.personId,
            });
          }
        }
        await generations
            .recoveryReader(p.identity.syncId)
            .family
            .clearRecoveryWorkspace();
      }
      await generations
          .recoveryStaging(j.operationId)
          .family
          .clearRecoveryWorkspace();
    }
    await store.abandonRestore();
  }

  Future<RecoveryResponse> _send(RecoveryRequest request) =>
      transport.send(request);

  /// Shared hook for HTTP/WS integration in 5.4; persist before cancelling
  /// queued work. Only these exact authenticated signals indicate transfer.
  Future<bool> handleRejection(
    String sid, {
    int? status,
    String? error,
    int? socketCode,
    String? socketReason,
  }) async {
    if ((status == 403 && error == 'credential_replaced') ||
        (socketCode == 4410 && socketReason == 'credential_replaced')) {
      await store.markTransferred(sid);
      return true;
    }
    return false;
  }

  void _ok(RecoveryResponse r) {
    if (r.status != 200) {
      throw RecoveryTransportException(r.status, r.error ?? 'invalid_response');
    }
  }

  Future<RecoveryCapsule> _get(RecoveryLocator locator) async {
    final r = await _send(
      RecoveryRequest(
        'GET',
        '/v2/recoveries/${locator.recoveryId}',
        headers: {'X-Recovery-Cap': locator.readCap},
      ),
    );
    _ok(r);
    final c = RecoveryCapsule.fromJson(r.body);
    final h = peekRecoveryCapsule(c.bytes);
    if (h.recoveryId != locator.recoveryId ||
        r.headers['etag'] != '"${h.revision}"') {
      throw const FormatException('invalid recovery response');
    }
    return c;
  }

  void _sameIdentity(RecoveryCapsulePayload a, RecoveryCapsulePayload b) {
    if (canonicalJsonOf(a.identity.toJson()) !=
            canonicalJsonOf(b.identity.toJson()) ||
        a.personId != b.personId ||
        a.familyKey.toBase64Url() != b.familyKey.toBase64Url()) {
      throw const RecoveryIncomplete('identity_changed');
    }
    if (canonicalJsonOf(a.deviceKeys.toJson()) !=
        canonicalJsonOf(b.deviceKeys.toJson())) {
      if (canonicalJsonOf({...a.deviceKeys.toJson()}..remove('c')) ==
          canonicalJsonOf({...b.deviceKeys.toJson()}..remove('c'))) {
        throw const RecoveryIncomplete('credential_replaced');
      }
      throw const RecoveryIncomplete('identity_changed');
    }
  }

  Future<RecoveryJournal> resume() async {
    var j = (await store.readRestore())!;
    // Bound progress; never spin on network/CAS/incomplete responses.
    for (var step = 0; step < 64; step++) {
      onPhase?.call(j.phase);
      if (j.claimSent) onClaimSent?.call();
      if (j.phase == RecoveryPhase.active ||
          j.phase == RecoveryPhase.needsAttention) {
        return j;
      }
      try {
        j = await _step(j);
      } on RecoveryIncomplete catch (e) {
        if (e.code == 'credential_replaced') {
          // The reader can lose its credential between discovery and GET.
          // Keep this a recovery operation, never poison an installed sid.
          final code = RecoveryCode(
            decodeBase64Url(j.data['entropy'] as String),
          );
          final locator = await deriveRecoveryLocator(code);
          final current = await _get(locator);
          final opened = await openRecoveryCapsule(
            current.bytes,
            code,
            expectedRevision: peekRecoveryCapsule(current.bytes).revision,
          );
          final next = RecoveryJournal(
            operationId: encodeBase64Url(secureRandomBytes(16)),
            phase: RecoveryPhase.located,
            data: {
              'entropy': j.data['entropy'],
              'recoveryId': j.data['recoveryId'],
              'source': j.data['source'],
              'replaceExisting': j.data['replaceExisting'],
              'claimSent': j.claimSent,
              'capsule': current.toJson(),
              'payload': opened.toJson(),
            },
          );
          await generations
              .recoveryStaging(j.operationId)
              .family
              .clearRecoveryWorkspace();
          await store.restartRestore(j, next);
          j = next;
          continue;
        }
        j = (await store.readRestore())!;
        j = j.next(RecoveryPhase.needsAttention, {
          'reason': e.code,
          'resumePhase': j.phase.name,
        });
        await store.saveRestore(j);
        return j;
      } on RecoverySourceException catch (e) {
        j = (await store.readRestore())!;
        j = j.next(RecoveryPhase.needsAttention, {
          'reason': e.code,
          'resumePhase': j.phase.name,
        });
        await store.saveRestore(j);
        return j;
      } on FormatException {
        j = j.next(RecoveryPhase.needsAttention, {
          'reason': 'unsupported_or_invalid_data',
          'resumePhase': j.phase.name,
        });
        await store.saveRestore(j);
        return j;
      } on RecoveryException {
        j = j.next(RecoveryPhase.needsAttention, {
          'reason': 'invalid_capsule',
          'resumePhase': j.phase.name,
        });
        await store.saveRestore(j);
        return j;
      } on RecoveryTransportException catch (e) {
        if (e.retryable) rethrow;
        j = (await store.readRestore())!;
        j = j.next(RecoveryPhase.needsAttention, {
          'reason': e.code,
          'resumePhase': j.phase.name,
        });
        await store.saveRestore(j);
        return j;
      } on Object catch (e) {
        if (e is! FamilyKeyException &&
            e is! RegistryException &&
            e is! CommonStateException) {
          rethrow;
        }
        j = (await store.readRestore())!;
        j = j.next(RecoveryPhase.needsAttention, {
          'reason': 'unsupported_local_context',
          'resumePhase': j.phase.name,
        });
        await store.saveRestore(j);
        return j;
      }
    }
    return j;
  }

  /// Explicit retry after missing resources/unsupported contexts are resolved.
  Future<RecoveryJournal> retryIncomplete() async {
    final j = (await store.readRestore())!;
    if (j.phase != RecoveryPhase.needsAttention) return resume();
    await store.saveRestore(
      j.next(RecoveryPhase.values.byName(j.data['resumePhase'] as String)),
    );
    return resume();
  }

  Future<RecoveryJournal> _step(RecoveryJournal j) async {
    final code = RecoveryCode(decodeBase64Url(j.data['entropy'] as String));
    final locator = await deriveRecoveryLocator(code);
    if (j.phase == RecoveryPhase.locating) {
      final c = await _get(locator);
      final next = j.next(RecoveryPhase.located, {'capsule': c.toJson()});
      await store.saveRestore(next);
      return next;
    }
    var payload = await RecoveryCapsulePayload.fromJson(
      j.data['payload'] ??
          (await openRecoveryCapsule(
            RecoveryCapsule.fromJson(j.data['capsule']).bytes,
            code,
            expectedRevision: (j.data['capsule'] as Map)['revision'] as int,
          )).toJson(),
    );
    final sid = payload.identity.syncId;
    if (payload.transition.blocksPublication ||
        payload.resume.commonMigration ||
        payload.resume.commonMigrationPut) {
      throw const RecoveryIncomplete('transition_pending');
    }
    final local = await generations.recoveryLocal(sid);
    late RecoveryJournal next;
    switch (j.phase) {
      case RecoveryPhase.located:
        j = await _checkSource(j, sid);
        final source = j.data['source'] as Map;
        if (source['active'] != null &&
            source['active'] != sid &&
            j.data['replaceExisting'] != true) {
          throw const RecoveryIncomplete('different_family');
        }
        // The durable located phase is the intent for the authenticated GET.
        final verified = await reader.verify(payload, local);
        _sameIdentity(payload, verified);
        payload = await mergeRecoveryLocal(
          await RecoveryCapsulePayload.fromJson(verified.toJson()),
          local,
        );
        next = j.next(RecoveryPhase.verified, {'payload': payload.toJson()});
      case RecoveryPhase.verified:
        j = await _checkSource(j, sid);
        final keys = await payload.deviceKeys.withNewServiceCredential();
        final changed = {...payload.toJson(), 'deviceKeys': keys.toJson()};
        final claimed = await RecoveryCapsulePayload.fromJson(changed);
        final revision = (j.data['capsule'] as Map)['revision'] as int;
        final bytes = await sealRecoveryCapsule(
          claimed,
          code,
          revision: revision + 1,
        );
        final request = RecoveryRequest(
          'POST',
          '/v2/recoveries/${locator.recoveryId}/claim',
          headers: {
            'Authorization':
                'Bearer ${encodeBase64Url(payload.deviceKeys.serviceCredential)}',
            'X-Recovery-Cap': locator.readCap,
            'If-Match': '"$revision"',
          },
          body: {
            'v': 2,
            'operationId': j.operationId,
            'newCredentialVerifier': encodeBase64Url(
              await keys.serviceCredentialVerifier(),
            ),
            'capsule': encodeBase64Url(bytes),
          },
        );
        next = j.next(RecoveryPhase.claimPrepared, {
          'request': request.toJson(),
          'claimedPayload': claimed.toJson(),
        });
      case RecoveryPhase.claimPrepared:
        // A prepared request alone does not imply transfer. Persist the point
        // where POST may reach the service before attempting any network I/O.
        if (!j.claimSent) {
          j = j.next(j.phase, {'claimSent': true});
          await store.saveRestore(j);
          onClaimSent?.call();
        }
        final request = RecoveryRequest.fromJson(j.data['request']);
        final r = await _send(request);
        if (r.status == 412 ||
            (r.status == 403 && r.error == 'credential_replaced')) {
          final current = await _get(locator);
          final opened = await openRecoveryCapsule(
            current.bytes,
            code,
            expectedRevision: peekRecoveryCapsule(current.bytes).revision,
          );
          final own = await RecoveryCapsulePayload.fromJson(
            j.data['claimedPayload'],
          );
          if (canonicalJsonOf(opened.deviceKeys.toJson()) ==
              canonicalJsonOf(own.deviceKeys.toJson())) {
            // Recognition is not permission to skip current-service validation.
            _sameIdentity(own, opened);
            await reader.verify(opened, local);
            next = j.next(RecoveryPhase.claimConfirmed, {
              'payload': opened.toJson(),
              'receiptRevision': peekRecoveryCapsule(current.bytes).revision,
            });
          } else {
            // Another claimant changes only the service credential. Re-open
            // and validate it through the read-only engine before a new claim.
            _sameIdentity(
              await RecoveryCapsulePayload.fromJson({
                ...payload.toJson(),
                'deviceKeys': opened.deviceKeys.toJson(),
              }),
              opened,
            );
            if (canonicalJsonOf(
                  {...payload.deviceKeys.toJson()}..remove('c'),
                ) !=
                canonicalJsonOf({...opened.deviceKeys.toJson()}..remove('c'))) {
              throw const RecoveryIncomplete('identity_changed');
            }
            next = j.next(RecoveryPhase.located, {
              'capsule': current.toJson(),
              'payload': opened.toJson(),
            });
          }
        } else {
          _ok(r);
          final body = r.body as Map;
          final expected = (j.data['capsule'] as Map)['revision'] as int;
          if (body['v'] != 2 ||
              body['recoveryId'] != locator.recoveryId ||
              body['operationId'] != j.operationId ||
              body['deviceId'] != payload.identity.deviceId ||
              body['revision'] != expected + 1 ||
              r.headers['etag'] != '"${expected + 1}"') {
            throw const FormatException('invalid claim receipt');
          }
          next = j.next(RecoveryPhase.claimConfirmed, {
            'receipt': r.toJson(),
            'receiptRevision': body['revision'],
            'payload': j.data['claimedPayload'],
          });
        }
      case RecoveryPhase.claimConfirmed:
        // Save receipt before any further download. Re-read latest capsule:
        // ordinary updates can have advanced beyond an idempotent receipt.
        final current = await _get(locator);
        final opened = await openRecoveryCapsule(
          current.bytes,
          code,
          expectedRevision: peekRecoveryCapsule(current.bytes).revision,
        );
        _sameIdentity(payload, opened);
        if (peekRecoveryCapsule(current.bytes).revision <
            (j.data['receiptRevision'] as int)) {
          throw const RecoveryIncomplete('capsule_rollback');
        }
        next = j.next(RecoveryPhase.downloading, {
          'currentPayload': opened.toJson(),
          'progress': <String, Object?>{},
        });
      case RecoveryPhase.downloading:
        final current = await RecoveryCapsulePayload.fromJson(
          j.data['currentPayload'],
        );
        final result = await reader.download(
          current,
          Map<String, Object?>.from(j.data['progress'] as Map),
          local,
        );
        next = j.next(RecoveryPhase.downloading, {'progress': result.progress});
        if (result.installation != null) {
          _sameIdentity(payload, result.installation!.payload);
          next = next.next(RecoveryPhase.installPrepared, {
            'installation': result.installation!.toJson(),
          });
        }
        await store.saveRestore(next);
        if (result.incompleteReason != null) {
          throw RecoveryIncomplete(result.incompleteReason!);
        }
        return next;
      case RecoveryPhase.installPrepared:
        j = await _checkSource(j, sid);
        final installation = await RecoveryInstallation.fromJson(
          j.data['installation'],
        );
        _sameIdentity(payload, installation.payload);
        await _install(j, installation, local);
        // The recovered credential is installed in another namespace. Old
        // pinned handles remain read-only after the global restore gate opens.
        final previousKeys = await local?.deviceKeys.read();
        if (previousKeys != null &&
            encodeBase64Url(previousKeys.serviceCredential) !=
                encodeBase64Url(
                  installation.payload.deviceKeys.serviceCredential,
                )) {
          await store.markTransferred(sid);
        }
        await generations.activateRecovery(
          operationId: j.operationId,
          syncId: sid,
          source: Map<String, Object?>.from(j.data['source'] as Map),
        );
        await store.completeRestore(j, sid, {
          'entropy': j.data['entropy'],
          'recoveryId': locator.recoveryId,
          'receiptRevision': j.data['receiptRevision'],
          'revision': j.data['receiptRevision'],
          'personId': payload.personId,
        });
        return (await store.readRestore())!;
      default:
        throw StateError('invalid recovery phase');
    }
    await store.saveRestore(next);
    return next;
  }

  Future<RecoveryJournal> _checkSource(RecoveryJournal j, String sid) async {
    // This source comparison relies on every family installation going through
    // requireNoPendingRestore under the family lock: FamilyController's create,
    // join and installV2 paths, and PairingV2GuestController._install. Keep those
    // gates even when installing the same identity; the snapshot alone cannot
    // authorize changes to the family while this restore is pending.
    // Activation may already have committed before its completion receipt.
    if (await generations.isRecoveryActive(j.operationId, sid)) return j;
    final captured = Map<String, Object?>.from(j.data['source'] as Map);
    final current = await generations.recoverySource(replaceExisting: true);
    if (canonicalJsonOf(captured) == canonicalJsonOf(current)) return j;
    final authorized =
        j.data['replaceExisting'] == true ||
        (captured['replaceV1'] == true &&
            current['replaceV1'] == true &&
            captured['v1ListId'] == current['v1ListId'] &&
            captured['v1Node'] == current['v1Node']);
    if (!authorized) throw const RecoveryIncomplete('different_family');
    final next = j.next(j.phase, {'source': current});
    await store.saveRestore(next);
    return next;
  }

  Future<void> _install(
    RecoveryJournal j,
    RecoveryInstallation i,
    GenerationContext? local,
  ) async {
    final p = await mergeRecoveryLocal(i.payload, local);
    if (i.doc.listId != p.identity.listId ||
        i.scopes.values.any((d) => d.listId != i.doc.listId) ||
        i.scopes.containsKey(p.personId) ||
        p.transition.blocksPublication ||
        p.resume.commonMigration ||
        p.resume.commonMigrationPut) {
      throw const RecoveryIncomplete('incomplete_installation');
    }
    var doc = i.doc;
    var registry = p.registry;
    var slots = i.slots;
    var floor = p.commonFormatFloor;
    var marked = p.commonKeysMarked;
    var hlc = p.resume.hlc;
    final floors = {
      for (final e in p.resume.slotRevisions.entries)
        '${e.key}/${p.identity.deviceId}': e.value,
    };
    if (local != null) {
      final oldIdentity = await local.family.readSyncV2();
      if (oldIdentity?.deviceId != p.identity.deviceId) {
        throw const RecoveryIncomplete('local_identity_conflict');
      }
      final old = await local.family.load();
      if (old != null) doc = doc.merge(old.doc);
      final oldRegistry = await local.family.readRegistry();
      if (oldRegistry != null) {
        registry = await unionRecoveryRegistry(
          registry,
          oldRegistry,
          RegistryAnchor(
            deviceId: p.identity.deviceId,
            signingKey: p.deviceKeys.publicKeys.signing,
          ),
        );
      }
      final localSlots = await local.family.readSlots();
      final view = await registry.viewFor(
        me: p.identity.deviceId,
        mySigningKey: p.deviceKeys.publicKeys.signing,
        livePeople: {
          for (final r
              in (doc.collections[Collections.recipients] ?? {}).values)
            if (!r.isDeleted) r.id,
        },
      );
      slots = (await slots.merge(localSlots.all, view: view)).$1;
      for (final slot in localSlots.all) {
        final h = slot.header;
        final key = '${h.personId}/${h.writer}';
        floors[key] = max(floors[key] ?? 0, h.revision);
      }
      floor = max(floor, await local.family.readCommonFormatFloor());
      // Keep the await out of bool |=: dart2wasm emits an invalid stack type.
      final localMarked = await local.family.commonKeysMarked();
      marked = marked | localMarked;
      final previous = await local.family.readRecoveryRevisionFloors();
      for (final e in previous.slots.entries) {
        floors[e.key] = max(floors[e.key] ?? 0, e.value);
      }
      if (previous.hlc != null && previous.hlc! > hlc) hlc = previous.hlc!;
    }
    // Frontera de los deseos (ADR 0010): lo recuperado entra en su única forma
    // y sin nada privado de los planes.
    doc = doc.wishBoundary();
    final retired = {
      for (final record
          in (doc.collections[Collections.recipients] ?? {}).values)
        if (record.isDeleted) record.id,
    };
    // The public clock floor comes only from public data (security review,
    // B1): the stamps of the private scopes never raise it. The scopes keep
    // their own stamps (the scope clock starts from the restored scope).
    final maxStamp = doc.maxStamp;
    if (maxStamp != null && maxStamp > hlc) hlc = maxStamp;
    for (final slot in slots.all) {
      final h = slot.header;
      final key = '${h.personId}/${h.writer}';
      floors[key] = max(floors[key] ?? 0, h.revision);
    }
    final target = generations.recoveryStaging(j.operationId);
    await target.deviceKeys.restore(p.deviceKeys);
    await target.deviceKeys.purgePerson(p.personId);
    await target.deviceKeys.saveKeyring(p.identity.listId, p.surpriseKeys);
    await target.family.saveFamily(
      StoredFamily(
        identity: FamilyIdentity(
          listId: p.identity.listId,
          node: p.identity.deviceId,
          deviceName: p.deviceName,
          peerName: p.peerName,
          paired: p.paired,
          selfRecipientId: p.personId,
        ),
        key: p.familyKey,
        doc: doc,
      ),
    );
    await target.family.saveSyncV2(p.identity);
    await target.family.saveRegistry(registry);
    await target.family.saveSlots(slots.withoutPeople(retired));
    final scopes = {...i.scopes};
    if (local != null) {
      for (final e in (await local.family.readRecoveryScopes()).entries) {
        if (e.key != p.personId) {
          scopes[e.key] = scopes[e.key]?.merge(e.value) ?? e.value;
        }
      }
    }
    for (final e in scopes.entries) {
      if (!retired.contains(e.key)) {
        await target.family.saveScope(e.key, e.value);
      }
    }
    await target.family.saveCommonKeys(
      CommonKeyState(
        keyring: p.commonKeys.keyring,
        revision: p.commonKeys.revision,
        lastKid: p.commonKeys.lastKid,
        outbox: p.resume.commonKeyOutbox,
      ).toJson(),
    );
    await target.family.saveSyncV2State(
      V2SyncState(
        created: true,
        version: p.resume.versionFloor,
        minSlotRevisions: {
          ...p.resume.minSlotRevisions,
          for (final e in floors.entries)
            e.key: max(e.value, p.resume.minSlotRevisions[e.key] ?? 0),
        },
        knownMembers: p.resume.knownMembers,
        pendingRevocations: p.resume.pendingRevocations,
        pendingUnbackedRevocations: p.resume.pendingUnbackedRevocations,
        revocationOperations: p.resume.revocationOperations,
        keyPackageOutbox: p.resume.keyPackageOutbox,
        commonFormatV2: p.resume.commonFormatV2 || floor >= 2,
      ).toJson(),
    );
    await target.family.raiseCommonFormatFloor(floor);
    if (marked) await target.family.markCommonKeys();
    final proof = p.transition.v1Proof;
    final proofExpired =
        proof != null &&
        clock.now().difference(
              DateTime.fromMillisecondsSinceEpoch(proof.sinceMillis),
            ) >=
            kLegacyV1MaxAge;
    await target.family.saveV1ProofKey(
      proof == null || proofExpired
          ? null
          : {
              'l': proof.listId,
              'k': proof.key.toBase64Url(),
              's': proof.sinceMillis,
            },
    );
    await target.family.raiseRecoveryRevisionFloors(floors, hlc: hlc);
    await target.family.enableRemoteSync();
    await target.family.configureRecovery();
  }
}
