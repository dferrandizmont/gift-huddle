// Un `lock.pin` guardado por una versión anterior (PBKDF2-HMAC-SHA256 de
// `cryptography`) se sigue abriendo con su PIN y rechaza otro: el hash lo
// calculó aparte Node (`crypto.pbkdf2Sync('482915', salt, 200000, 32,
// 'sha256')`), así que cambiar la derivación rompe esta prueba.
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride, kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/features/lock/data/pin_vault.dart';

import '../helpers/memory_stores.dart';

const _legacy =
    '{"v":1,"len":6,"alg":"pbkdf2-sha256","iter":200000,'
    '"salt":"AwoRGB8mLTQ7QklQV15lbA",'
    '"hash":"aC_nWZFH04WBqWnkL-oxc0k9CSi2nFxv5LPhumUcDBw"}';
const _channel = MethodChannel('com.dferrandizmont.regalos/pin_kdf');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a legacy lock.pin opens with its PIN and rejects another', () async {
    final secrets = MemorySecretStore()..values['lock.pin'] = _legacy;
    final vault = PinVault(secrets: secrets, useIsolate: false);
    expect(await vault.pinLength(), 6);
    expect(await vault.verify('482915'), isA<PinOk>());
    expect(await vault.verify('482916'), isA<PinWrong>());
  });

  test('mobile channel and Dart fallback accept the same PIN vector', () async {
    const pin = '000042';
    const expectedHex =
        'fe0f3887a197fb0450990cc6c1818d1a8758b5c8ec4f84f519fcea035b541b28';
    final salt = Uint8List.fromList([0xff, 0, 0x80, 1, 0x7f, 0, 0xff, 0xee]);
    final expected = Uint8List.fromList([
      for (var i = 0; i < expectedHex.length; i += 2)
        int.parse(expectedHex.substring(i, i + 2), radix: 16),
    ]);
    final secrets = MemorySecretStore()
      ..values['lock.pin'] = jsonEncode({
        'v': 1,
        'len': 6,
        'alg': 'pbkdf2-sha256',
        'iter': 200000,
        'salt': encodeBase64Url(salt),
        'hash': encodeBase64Url(expected),
      });
    final vault = PinVault(secrets: secrets);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(_channel, null);
      debugDefaultTargetPlatformOverride = null;
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    var calls = 0;
    var nativeResult = expected;
    var failNative = false;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls++;
      expect(call.method, 'derive');
      expect(call.arguments, {'pin': pin, 'salt': salt, 'rounds': 200000});
      if (failNative) throw PlatformException(code: 'pbkdf2_failed');
      return nativeResult;
    });
    expect(await vault.verify(pin), isA<PinOk>());
    nativeResult = Uint8List(expected.length);
    expect(await vault.verify(pin), isA<PinWrong>());
    failNative = true;
    expect(await vault.verify(pin), isA<PinOk>());
    expect(calls, 3);

    messenger.setMockMethodCallHandler(_channel, null);
    expect(await vault.verify(pin), isA<PinOk>());
  }, skip: kIsWeb);

  test(
    'an invalid native reply falls back to the legacy Dart derivation',
    () async {
      final secrets = MemorySecretStore()..values['lock.pin'] = _legacy;
      final vault = PinVault(secrets: secrets);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() {
        messenger.setMockMessageHandler(_channel.name, null);
        debugDefaultTargetPlatformOverride = null;
      });
      var calls = 0;
      messenger.setMockMessageHandler(_channel.name, (_) async {
        calls++;
        return ByteData(0);
      });

      expect(await vault.verify('482915'), isA<PinOk>());
      expect(calls, 1);
    },
    skip: kIsWeb,
  );
}
