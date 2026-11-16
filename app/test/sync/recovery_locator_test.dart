import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/recovery.dart';
import 'package:regalos/core/sync/recovery_locator.dart';

void main() {
  final rid = encodeBase64Url(List.filled(32, 7));
  final fails = throwsA(isA<RecoveryException>());

  test('authenticated discovery contains only emergency deletion metadata', () {
    for (final state in RecoveryMetadataState.values) {
      final row = RecoveryMetadata(
        deviceId: 'nora-phone',
        recoveryId: rid,
        revision: 12,
        state: state,
      );
      expect(row.toJson(), {
        'deviceId': 'nora-phone',
        'recoveryId': rid,
        'revision': 12,
        'state': state.name,
      });
      expect(RecoveryMetadata.fromJson(row.toJson()).toJson(), row.toJson());
    }
  });

  test('discovery rejects secrets, missing fields and unsupported states', () {
    final row = RecoveryMetadata(
      deviceId: 'nora-phone',
      recoveryId: rid,
      revision: 1,
      state: RecoveryMetadataState.active,
    ).toJson();
    for (final field in row.keys) {
      expect(
        () => RecoveryMetadata.fromJson({...row}..remove(field)),
        fails,
        reason: field,
      );
    }
    for (final entry in {
      'deviceId': '',
      'recoveryId': '$rid=',
      'revision': 0,
      'state': 'future',
      'readVerifier': rid,
      'capsule': 'secret',
    }.entries) {
      expect(
        () => RecoveryMetadata.fromJson({...row, entry.key: entry.value}),
        fails,
        reason: entry.key,
      );
    }
    for (final revision in [-1, 1.5, 0x20000000000000, null]) {
      expect(
        () => RecoveryMetadata.fromJson({...row, 'revision': revision}),
        fails,
      );
    }
  });

  test(
    'lookup values reject noncanonical base64 and stay domain separated',
    () async {
      final locator = await deriveRecoveryLocator(
        RecoveryCode(List.filled(32, 7)),
      );
      expect({
        locator.recoveryId,
        locator.readCap,
        locator.readVerifier,
      }, hasLength(3));
      final noncanonical = '${'A' * 42}B';
      for (final value in ['$rid=', rid.substring(1), noncanonical, '*' * 43]) {
        expect(() => recoveryBytes32(value), fails);
      }
    },
  );
}
