import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/features/sync/domain/sync_keys.dart';

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List _unhex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);

void main() {
  final vector = jsonDecode(
    File('../docs/adr/0002-vector-invitacion.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final input = vector['entrada']! as Map<String, Object?>;
  final output = vector['salida']! as Map<String, Object?>;
  final familyKey = FamilyKey(_unhex(input['familyKey']! as String));

  test(
    'authKey = HKDF(familyKey, "gift-huddle", "sync-auth-v1"): vector fijo',
    () async {
      expect(_hex(await SyncKeys.authKey(familyKey)), output['authKey']);
    },
  );

  test('el verificador es SHA-256(authKey)', () async {
    final auth = await SyncKeys.authKey(familyKey);
    expect(_hex(await SyncKeys.verifier(auth)), output['authVerifier']);
  });

  test('syncId = base64url(HKDF(familyKey, "gift-huddle", "sync-id-v1", 16)): vector fijo', () async {
    final id = await SyncKeys.syncId(familyKey);
    expect(id, output['syncId']);
    expect(id.length, 22);
    expect(RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(id), isTrue);
  });

  test('el syncId no se parece al listId ni a la authKey', () async {
    final id = await SyncKeys.syncId(familyKey);
    expect(id, isNot(input['listId']));
    expect(encodeBase64Url(await SyncKeys.authKey(familyKey)), isNot(id));
  });

  test('otra clave da otro syncId y otra authKey', () async {
    final other = await FamilyKey.generate();
    expect(
      await SyncKeys.syncId(other),
      isNot(await SyncKeys.syncId(familyKey)),
    );
    expect(
      await SyncKeys.authKey(other),
      isNot(await SyncKeys.authKey(familyKey)),
    );
  });
}
