import 'dart:convert';

import 'package:cryptography/dart.dart';
import 'package:clock/clock.dart';

import '../../../core/sync/device_keys.dart';
import '../../../core/sync/envelope.dart';
import '../../../core/sync/family_doc.dart';
import '../../../core/sync/recovery.dart';
import '../../../core/sync/recovery_locator.dart';
import '../../family/data/family_store.dart';
import '../../family/data/recovery_store.dart';
import '../data/recovery_transport.dart';
import '../data/sync_transport_v2.dart';
import 'recovery_controller.dart';
import 'recovery_engine.dart';

enum RecoveryReadiness {
  absent,
  prepared,
  confirmationPending,
  updatePending,
  needsAttention,
  transferred,
}

class RecoveryStatus {
  const RecoveryStatus(
    this.readiness, {
    this.cause,
    this.phase,
    this.claimSent = false,
    this.installationTransferred = false,
    this.canDismissFailure = false,
  });
  final RecoveryReadiness readiness;
  final String? cause;
  final RecoveryPhase? phase;
  final bool claimSent;

  /// Gate for the installed family's read-only mode, independent of progress.
  final bool installationTransferred;

  /// A closed maintenance failure, safe to dismiss without resolving an intent.
  final bool canDismissFailure;
  bool get hasPendingRestore => phase != null && phase != RecoveryPhase.active;
}

/// Caller holds the family lock. Exact ciphertext/CAS survive network failures;
/// no operation is prepared again after an ambiguous response.
class RecoveryMaintenance {
  RecoveryMaintenance({
    required this.store,
    required this.family,
    required this.exporter,
    required this.transport,
    required this.auth,
    this.minimumUpdateInterval = const Duration(hours: 4),
    DateTime Function()? now,
  }) : now = now ?? clock.now;
  final RecoveryStore store;
  final FamilyStore family;
  final RecoveryExporter exporter;
  final RecoveryTransport transport;
  final V2Auth auth;
  final Duration minimumUpdateInterval;
  final DateTime Function() now;
  String get sid => auth.syncId;

  Future<RecoveryStatus> status() async {
    if (await store.isTransferred(sid)) {
      return const RecoveryStatus(
        RecoveryReadiness.transferred,
        installationTransferred: true,
      );
    }
    final pending = await store.readMaintenance(sid);
    if (pending != null) {
      final intent = pending['intent'] as Map;
      return RecoveryStatus(
        intent['cause'] == null
            ? RecoveryReadiness.updatePending
            : RecoveryReadiness.needsAttention,
        cause: intent['cause'] as String?,
      );
    }
    final material = await store.readMaterial(sid);
    final failure = await store.readFailure(sid);
    if (failure != null) {
      return RecoveryStatus(
        RecoveryReadiness.needsAttention,
        cause: failure,
        canDismissFailure: true,
      );
    }
    if (material == null || material['retired'] == true) {
      return const RecoveryStatus(RecoveryReadiness.absent);
    }
    // Older installations recorded no proof of the word check. Treat that
    // uncertainty as unconfirmed too, without invalidating their remote code.
    if (material['wordsConfirmed'] != true) {
      return const RecoveryStatus(RecoveryReadiness.confirmationPending);
    }
    return RecoveryStatus(
      await family.recoveryDirty() != null
          ? RecoveryReadiness.updatePending
          : RecoveryReadiness.prepared,
    );
  }

  Future<void> create(RecoveryCode code) async {
    await queueNewCode(code, rotate: false);
    await resume();
  }

  Future<void> queueNewCode(RecoveryCode code, {required bool rotate}) async {
    final existing = await store.readMaintenance(sid);
    if (existing != null) {
      if ((existing['intent'] as Map)['entropy'] ==
          encodeBase64Url(code.entropy)) {
        return;
      }
      throw StateError('maintenance already pending');
    }
    final material = await store.readMaterial(sid);
    if (!rotate && material != null && material['retired'] != true) {
      throw StateError('recovery already configured');
    }
    await family.configureRecovery();
    await _prepare(
      rotate ? RecoveryMaintenanceKind.rotate : RecoveryMaintenanceKind.create,
      code: code,
    );
  }

  Future<void> rotate(RecoveryCode code) async {
    await queueNewCode(code, rotate: true);
    await resume();
  }

  Future<void> retire() async {
    if ((await store.readMaterial(sid))?['retired'] == true) return;
    if ((await store.readMaintenance(sid))?['kind'] !=
        RecoveryMaintenanceKind.retire.name) {
      await _prepare(RecoveryMaintenanceKind.retire);
    }
    await resume();
  }

  Future<void> cancel() async {
    final record = await store.readMaintenance(sid);
    if (record == null) {
      await store.dismissFailure(sid);
      return;
    }
    final intent = Map<String, Object?>.from(record['intent'] as Map);
    if (record['kind'] == RecoveryMaintenanceKind.rotate.name &&
        intent['request'] != null) {
      // A lost commit response must not restore obsolete material and discard
      // the only delivery of an already active code. Listing is read-only; if
      // it fails the exact intent and its withheld words remain retryable.
      final code = RecoveryCode(decodeBase64Url(intent['entropy'] as String));
      final locator = await deriveRecoveryLocator(code);
      final rows = await _listRecoveries();
      for (final row in rows) {
        if (row.deviceId == auth.deviceId &&
            row.recoveryId == locator.recoveryId) {
          if (row.revision != intent['revision']) {
            throw const RecoveryIncomplete('capsule_revision_mismatch');
          }
          await store.advanceMaintenance(sid, record, {
            ...intent,
            'phase': 'finish',
          });
          await resume();
          return;
        }
      }
    }
    if (record['kind'] == RecoveryMaintenanceKind.retire.name &&
        intent['request'] != null) {
      // A lost DELETE response must not restore material already retired remotely.
      final old = intent['old'] as Map;
      final rows = await _listRecoveries();
      if (!rows.any(
        (row) =>
            row.deviceId == auth.deviceId &&
            row.recoveryId == old['recoveryId'],
      )) {
        await store.advanceMaintenance(sid, record, {
          ...intent,
          'phase': 'retired',
        });
        await resume();
        return;
      }
    }
    if (record['kind'] == RecoveryMaintenanceKind.create.name &&
        intent['request'] != null) {
      await store.advanceMaintenance(sid, record, {
        ...intent,
        'phase': 'cleanup',
        'closeCause': null,
      });
      await resume();
      return;
    }
    await store.closeMaintenance(sid, null);
  }

  /// Only remove this operation's unseen code, never another mobile's code.
  /// A failed cleanup keeps its durable phase so retry cannot create a clash.
  Future<void> _removeUnseenCreate(RecoveryLocator locator) async {
    final rows = await _listRecoveries();
    for (final row in rows) {
      if (row.deviceId == auth.deviceId &&
          row.recoveryId == locator.recoveryId) {
        final removed = await _send(
          RecoveryRequest(
            'DELETE',
            '/v2/lists/$sid/recoveries/${row.recoveryId}',
            headers: recoveryAuthHeaders(auth, row.revision),
          ),
        );
        _expect(removed, {204, 404});
      }
    }
  }

  Future<List<RecoveryMetadata>> _listRecoveries() async {
    final listed = await _send(
      RecoveryRequest(
        'GET',
        '/v2/lists/$sid/recoveries',
        headers: {'Authorization': auth.bearer},
      ),
    );
    _expect(listed, {200});
    final body = listed.body as Map;
    if (body['v'] != 2 || body['recoveries'] is! List) {
      throw const RecoveryIncomplete('invalid_response');
    }
    return (body['recoveries'] as List).map(RecoveryMetadata.fromJson).toList();
  }

  Future<void> _prepare(
    RecoveryMaintenanceKind kind, {
    RecoveryCode? code,
  }) async {
    await store.assertWritable(sid);
    final material = await store.readMaterial(sid);
    if (kind != RecoveryMaintenanceKind.create && material == null) {
      throw StateError('no recovery');
    }
    await store.prepareMaintenance(sid, kind, {
      'phase': 'capture',
      'source': sid,
      'operationId': encodeBase64Url(secureRandomBytes(16)),
      'entropy': code == null
          ? material!['entropy']
          : encodeBase64Url(code.entropy),
      'old': material,
    });
  }

  /// Called after sync, on startup and after reconnect. Dirty intent is written
  /// by the real stores before key/registry/context/credential changes.
  Future<void> maintain() async {
    final pending = await store.readMaintenance(sid);
    final material = await store.readMaterial(sid);
    if (material == null || material['retired'] == true) {
      if (pending != null) await resume();
      return;
    }
    final identity = (await family.load())!.identity;
    if (identity.selfRecipientId != material['personId'] ||
        (await family.recoveryBlockers()).person) {
      if (pending?['kind'] == RecoveryMaintenanceKind.retire.name) {
        return resume();
      }
      final code = RecoveryCode(decodeBase64Url(material['entropy'] as String));
      final locator = await deriveRecoveryLocator(code);
      // Even an ambiguously accepted update may have raised the capsule CAS.
      final current = await _send(
        RecoveryRequest(
          'GET',
          '/v2/recoveries/${locator.recoveryId}',
          headers: {'X-Recovery-Cap': locator.readCap},
        ),
      );
      if (current.status == 404) {
        await store.finishMaintenance(sid, {'retired': true});
        await family.finishRecoveryPersonInvalidation();
        return;
      }
      _expect(current, {200});
      final capsule = RecoveryCapsule.fromJson(current.body);
      final revision = peekRecoveryCapsule(capsule.bytes).revision;
      await store.supersedeWithRetirement(sid, {
        'phase': 'capture',
        'source': sid,
        'operationId': encodeBase64Url(secureRandomBytes(16)),
        'entropy': material['entropy'],
        'old': {...material, 'revision': revision},
      });
      await resume();
      return;
    }
    if (pending != null) return resume();
    if (await family.recoveryDirty() != null) {
      final uploadedAt = material['uploadedAt'] as int?;
      if (uploadedAt != null &&
          now().millisecondsSinceEpoch - uploadedAt <
              minimumUpdateInterval.inMilliseconds) {
        return;
      }
      await _prepare(RecoveryMaintenanceKind.update);
      await resume();
    }
  }

  Future<RecoveryResponse> _send(RecoveryRequest request) async {
    await store.assertWritable(sid);
    final r = await transport.send(request);
    if (r.status == 403 && r.error == 'credential_replaced') {
      if (request.headers['Authorization']?.startsWith('Bearer ') == true) {
        await store.markTransferred(sid);
      } else {
        throw RecoveryTransportException(r.status, 'invalid_response');
      }
    }
    return r;
  }

  void _expect(RecoveryResponse r, Set<int> expected) {
    if (!expected.contains(r.status)) {
      throw RecoveryTransportException(r.status, r.error ?? 'invalid_response');
    }
  }

  Future<void> resume() async {
    for (var step = 0; step < 8; step++) {
      final record = await store.readMaintenance(sid);
      if (record == null) return;
      final kind = RecoveryMaintenanceKind.values.byName(
        record['kind'] as String,
      );
      var intent = Map<String, Object?>.from(record['intent'] as Map);
      Future<void> advance(Map<String, Object?> fields) async {
        intent = {...intent, ...fields}..remove('cause');
        await store.advanceMaintenance(sid, record, intent);
      }

      final old = intent['old'] as Map?;
      final code = RecoveryCode(decodeBase64Url(intent['entropy'] as String));
      final locator = await deriveRecoveryLocator(code);
      try {
        switch (intent['phase']) {
          case 'cleanup':
            await _removeUnseenCreate(locator);
            await store.closeMaintenance(sid, intent['closeCause'] as String?);
            return;
          case 'capture':
            if (kind == RecoveryMaintenanceKind.retire) {
              await advance({
                'phase': 'send',
                'request': RecoveryRequest(
                  'DELETE',
                  '/v2/lists/$sid/recoveries/${old!['recoveryId']}',
                  headers: recoveryAuthHeaders(auth, old['revision'] as int),
                ).toJson(),
              });
              continue;
            }
            final token = await family.recoveryDirty();
            final payload = await exporter.capture(sid);
            final fingerprint = encodeBase64Url(
              const DartSha256()
                  .hashSync(
                    utf8.encode(
                      canonicalJsonOf(recoveryMaterialSnapshot(payload)),
                    ),
                  )
                  .bytes,
            );
            if (kind == RecoveryMaintenanceKind.update &&
                old?['fingerprint'] == fingerprint) {
              await store.finishMaintenance(
                sid,
                Map<String, Object?>.from(old!),
              );
              await family.clearRecoveryDirty(token);
              return;
            }
            final rotating = kind == RecoveryMaintenanceKind.rotate;
            final revision = kind == RecoveryMaintenanceKind.create || rotating
                ? 1
                : (old!['revision'] as int) + 1;
            final capsule = await sealRecoveryCapsule(
              payload,
              code,
              revision: revision,
            );
            final body = <String, Object?>{
              'v': 2,
              if (!rotating) 'deviceId': auth.deviceId,
              'readVerifier': locator.readVerifier,
              'capsule': encodeBase64Url(capsule),
              if (rotating) ...{
                'operationId': intent['operationId'],
                'newRecoveryId': locator.recoveryId,
              },
            };
            final request = RecoveryRequest(
              rotating ? 'POST' : 'PUT',
              '/v2/lists/$sid/recoveries/${rotating ? old!['recoveryId'] : locator.recoveryId}${rotating ? '/rotation' : ''}',
              headers: {
                ...recoveryAuthHeaders(
                  auth,
                  kind == RecoveryMaintenanceKind.create
                      ? 0
                      : old!['revision'] as int,
                ),
                if (kind == RecoveryMaintenanceKind.create)
                  'X-Recovery-Operation': intent['operationId'] as String,
              },
              body: body,
            );
            await advance({
              'phase': 'send',
              'request': request.toJson(),
              'revision': revision,
              'fingerprint': fingerprint,
              'dirty': token,
              'personId': payload.personId,
            });
          case 'send':
            final r = await _send(RecoveryRequest.fromJson(intent['request']));
            if (kind == RecoveryMaintenanceKind.retire && r.status == 412) {
              // Re-list ownership, then re-read the authenticated capsule CAS.
              final listed = await _send(
                RecoveryRequest(
                  'GET',
                  '/v2/lists/$sid/recoveries',
                  headers: {'Authorization': auth.bearer},
                ),
              );
              _expect(listed, {200});
              final current = await _send(
                RecoveryRequest(
                  'GET',
                  '/v2/recoveries/${locator.recoveryId}',
                  headers: {'X-Recovery-Cap': locator.readCap},
                ),
              );
              if (current.status == 404) {
                await advance({'phase': 'retired'});
              } else {
                _expect(current, {200});
                final capsule = RecoveryCapsule.fromJson(current.body);
                final header = peekRecoveryCapsule(capsule.bytes);
                if (header.recoveryId != locator.recoveryId ||
                    current.headers['etag'] != '"${header.revision}"') {
                  throw const RecoveryIncomplete('capsule_verification_failed');
                }
                await openRecoveryCapsule(
                  capsule.bytes,
                  code,
                  expectedRevision: header.revision,
                );
                await advance({
                  'phase': 'capture',
                  'old': {...old!, 'revision': header.revision},
                });
              }
              continue;
            }
            // A replaced capsule has no write receipt: after an ambiguous
            // response verify the exact published bytes with GET.
            _expect(
              r,
              kind == RecoveryMaintenanceKind.retire
                  ? {204, 404}
                  : kind == RecoveryMaintenanceKind.update
                  ? {200, 412}
                  : {200, 201},
            );
            // Durable receipt precedes GET verification (or rotation commit).
            await advance({
              'phase': kind == RecoveryMaintenanceKind.retire
                  ? 'retired'
                  : 'verify',
              'receipt': r.toJson(),
            });
          case 'verify':
            final r = await _send(
              RecoveryRequest(
                'GET',
                '/v2/recoveries/${locator.recoveryId}',
                headers: {'X-Recovery-Cap': locator.readCap},
              ),
            );
            _expect(r, {200});
            final capsule = RecoveryCapsule.fromJson(r.body);
            final revision = intent['revision'] as int;
            final header = peekRecoveryCapsule(capsule.bytes);
            if (kind == RecoveryMaintenanceKind.update &&
                (header.revision != revision ||
                    encodeBase64Url(capsule.bytes) !=
                        RecoveryRequest.fromJson(intent['request'])
                            .body!['capsule'])) {
              if (header.recoveryId != locator.recoveryId ||
                  r.headers['etag'] != '"${header.revision}"') {
                throw const RecoveryIncomplete('capsule_verification_failed');
              }
              final opened = await openRecoveryCapsule(
                capsule.bytes,
                code,
                expectedRevision: header.revision,
              );
              if (opened.identity.syncId != sid ||
                  opened.identity.deviceId != auth.deviceId) {
                throw const RecoveryIncomplete('identity_changed');
              }
              await advance({
                'phase': 'capture',
                'old': {...old!, 'revision': header.revision},
              });
              continue;
            }
            if (header.recoveryId != locator.recoveryId ||
                header.revision != revision ||
                r.headers['etag'] != '"$revision"') {
              throw const RecoveryIncomplete('capsule_revision_mismatch');
            }
            final opened = await openRecoveryCapsule(
              capsule.bytes,
              code,
              expectedRevision: revision,
            );
            final expected = RecoveryRequest.fromJson(intent['request'])
                .body!['capsule'];
            if (encodeBase64Url(capsule.bytes) != expected ||
                opened.identity.syncId != sid) {
              throw const RecoveryIncomplete('capsule_verification_failed');
            }
            await advance({
              'phase': kind == RecoveryMaintenanceKind.rotate
                  ? 'commit'
                  : 'finish',
            });
          case 'commit':
            final r = await _send(
              RecoveryRequest(
                'POST',
                '/v2/lists/$sid/recoveries/${old!['recoveryId']}/rotation/${intent['operationId']}/commit',
                headers: recoveryAuthHeaders(auth, old['revision'] as int),
                body: const {'v': 2},
              ),
            );
            _expect(r, {200});
            await advance({'phase': 'finish', 'commitReceipt': r.toJson()});
          case 'finish':
            await store.finishMaintenance(sid, {
              'entropy': intent['entropy'],
              'recoveryId': locator.recoveryId,
              'revision': intent['revision'],
              'fingerprint': intent['fingerprint'],
              'personId': intent['personId'],
              'uploadedAt': now().millisecondsSinceEpoch,
              if (kind == RecoveryMaintenanceKind.create ||
                  kind == RecoveryMaintenanceKind.rotate)
                'wordsConfirmed': false,
            });
            await family.clearRecoveryDirty(intent['dirty'] as String?);
            return;
          case 'retired':
            await store.finishMaintenance(sid, {'retired': true});
            await family.finishRecoveryPersonInvalidation();
            return;
          default:
            throw const FormatException('invalid maintenance phase');
        }
      } on RecoveryIncomplete catch (e) {
        if ((kind == RecoveryMaintenanceKind.create ||
                kind == RecoveryMaintenanceKind.rotate) &&
            intent['phase'] != 'cleanup') {
          if (kind == RecoveryMaintenanceKind.create &&
              intent['request'] != null) {
            await advance({'phase': 'cleanup', 'closeCause': e.code});
            continue;
          }
          await store.closeMaintenance(sid, e.code);
          return;
        }
        await store.advanceMaintenance(sid, record, {
          ...intent,
          'cause': e.code,
        });
        return;
      } on RecoveryTransportException catch (e) {
        if (e.code == 'credential_replaced' || e.retryable) rethrow;
        if (intent['phase'] == 'cleanup') {
          await store.advanceMaintenance(sid, record, {
            ...intent,
            'cause': e.code,
          });
          return;
        }
        if (kind == RecoveryMaintenanceKind.create &&
            intent['request'] != null &&
            !const {
              'unauthorized',
              'revoked',
              'mobile_required',
            }.contains(e.code)) {
          await advance({'phase': 'cleanup', 'closeCause': e.code});
          continue;
        }
        if (const {
              'recovery_rotation_expired',
              'recovery_rotation_cancelled',
              'recovery_retired',
              'not_found',
            }.contains(e.code) ||
            kind == RecoveryMaintenanceKind.create ||
            kind == RecoveryMaintenanceKind.rotate) {
          final candidateRead =
              kind == RecoveryMaintenanceKind.rotate &&
              intent['phase'] == 'verify';
          final retired =
              !candidateRead &&
              (e.code == 'recovery_retired' || e.code == 'not_found');
          await store.closeMaintenance(sid, e.code, retired: retired);
          if (retired && kind == RecoveryMaintenanceKind.retire) {
            await family.finishRecoveryPersonInvalidation();
          }
          return;
        }
        await store.advanceMaintenance(sid, record, {
          ...intent,
          'cause': e.code,
        });
        return;
      }
    }
  }
}

/// Counters protect the restored writer, but a full remote read refreshes them.
/// Changing ordinary data must not consume one of the capsule write slots.
Map<String, Object?> recoveryMaterialSnapshot(RecoveryCapsulePayload payload) {
  final j = payload.toJson();
  j['resume'] = {...payload.resume.toJson()}
    ..remove('versionFloor')
    ..remove('hlc')
    ..remove('slotRevisions');
  j['commonKeys'] = {...payload.commonKeys.toJson()}..remove('revision');
  return j;
}
