import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/platform/document_exchange.dart';
import 'package:regalos/core/platform/document_exchange_native.dart';

/// ADR 0008: el canal nativo del fichero de recuperación (selector para
/// guardar y abrir, NFC) y el borrado de sus temporales.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  final calls = <MethodCall>[];
  late Future<Object?> Function(MethodCall) native;

  NativeDocumentExchange exchange() => NativeDocumentExchange(() async => temp);

  setUp(() {
    temp = Directory.systemTemp.createTempSync('regalos_recovery_');
    calls.clear();
    native = (_) async => null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kIncomingChannel, (call) {
          calls.add(call);
          return native(call);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kIncomingChannel, null);
    temp.deleteSync(recursive: true);
  });

  Matcher pickerFails(DocumentPickerFailure f) => throwsA(
    isA<DocumentPickerException>().having((e) => e.failure, 'failure', f),
  );

  test('save sends the bytes and returns what was read back', () async {
    final bytes = Uint8List.fromList([0x47, 0x48, 0x4B, 1]);
    native = (call) async => call.arguments['bytes'];
    final back = await exchange().saveWithPicker(
      bytes,
      'gift-huddle-recuperacion-20261116-0905.gifthuddle',
      maxReadBytes: 512,
    );
    expect(back, bytes);
    final call = calls.single;
    expect(call.method, 'saveDocument');
    expect(call.arguments['name'], startsWith('gift-huddle-recuperacion'));
    expect(call.arguments['mime'], 'application/vnd.gifthuddle');
    expect(call.arguments['maxReadBytes'], 512);
  });

  test('a cancelled picker is null, not an error', () async {
    expect(await exchange().openWithPicker(maxBytes: 512), isNull);
    expect(calls.single.method, 'openDocument');
    expect(calls.single.arguments, {'maxBytes': 512});
    expect(
      await exchange().saveWithPicker(
        Uint8List(1),
        'a.gifthuddle',
        maxReadBytes: 512,
      ),
      isNull,
    );
  });

  test('native errors are typed', () async {
    for (final (code, failure) in [
      ('too_large', DocumentPickerFailure.tooLarge),
      ('busy', DocumentPickerFailure.busy),
      ('unavailable', DocumentPickerFailure.unavailable),
      ('read_failed', DocumentPickerFailure.unreadable),
      ('write_failed', DocumentPickerFailure.unreadable),
    ]) {
      native = (_) async => throw PlatformException(code: code);
      await expectLater(
        exchange().openWithPicker(maxBytes: 512),
        pickerFails(failure),
      );
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kIncomingChannel, null);
    await expectLater(
      exchange().normalizeNfc('x'),
      pickerFails(DocumentPickerFailure.unavailable),
    );
  });

  test('a file name with a path is refused before the channel', () {
    expect(
      () => exchange().saveWithPicker(Uint8List(1), '../x', maxReadBytes: 512),
      throwsArgumentError,
    );
    expect(calls, isEmpty);
  });

  test('NFC goes through the platform', () async {
    native = (call) async => 'ñ';
    expect(await exchange().normalizeNfc('ñ'), 'ñ');
    expect(calls.single.method, 'normalizeNfc');
    expect(calls.single.arguments, 'ñ');
  });

  test('clearing removes recovery temporaries, not envelope copies', () async {
    final own = Directory('${temp.path}/recovery')..createSync();
    File('${own.path}/r.gifthuddle').writeAsBytesSync([0x47, 0x48, 0x4B, 1]);
    final shared = Directory('${temp.path}/share_plus')..createSync();
    final recoveryCopy = File('${shared.path}/r.gifthuddle')
      ..writeAsBytesSync([0x47, 0x48, 0x4B, 1, 0, 0]);
    final envelopeCopy = File('${shared.path}/e.gifthuddle')
      ..writeAsBytesSync([0x52, 0x47, 1]);
    await exchange().clearRecoveryShares();
    expect(own.existsSync(), isFalse);
    expect(recoveryCopy.existsSync(), isFalse);
    expect(envelopeCopy.existsSync(), isTrue);
  });

  test('«Borrar todo» also clears them', () async {
    final own = Directory('${temp.path}/recovery')..createSync();
    File('${own.path}/r.gifthuddle').writeAsBytesSync([0x47, 0x48, 0x4B, 1]);
    await exchange().clearExports();
    expect(own.existsSync(), isFalse);
  });

  test('on iPhone the startup sweep asks native code to remove the picker '
      'export (tmp/recovery-export, outside Dart temp)', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await exchange().clearRecoveryShares();
    expect(calls.map((c) => c.method), ['clearRecoveryExport']);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    await exchange().clearRecoveryShares();
    expect(calls, isEmpty);
  });

  group('compartir', () {
    const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
    final sharedPaths = <String>[];

    setUp(() {
      sharedPaths.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(shareChannel, (call) async {
            sharedPaths.addAll(
              ((call.arguments as Map)['paths'] as List).cast<String>(),
            );
            return 'dev.fluttercommunity.plus/share/unavailable';
          });
    });

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(shareChannel, null),
    );

    test('one folder per share; an old timer never deletes a newer one '
        'with the same name', () async {
      const name = 'gift-huddle-recuperacion-20261116-0905.gifthuddle';
      final first = NativeDocumentExchange(
        () async => temp,
        recoveryShareRetention: const Duration(milliseconds: 50),
      );
      final copy = File('${temp.path}/share_plus/$name')
        ..createSync(recursive: true)
        ..writeAsBytesSync([0x47, 0x48, 0x4B, 1]);
      await first.shareRecoveryFile(
        Uint8List.fromList([0x47, 0x48, 0x4B, 1, 1]),
        name,
        text: 'x',
      );
      final second = NativeDocumentExchange(
        () async => temp,
        recoveryShareRetention: const Duration(milliseconds: 400),
      );
      await second.shareRecoveryFile(
        Uint8List.fromList([0x47, 0x48, 0x4B, 1, 2]),
        name,
        text: 'x',
      );
      expect(sharedPaths, hasLength(2));
      expect(sharedPaths[0], isNot(sharedPaths[1]));
      expect(File(sharedPaths[0]).readAsBytesSync().last, 1);
      expect(File(sharedPaths[1]).readAsBytesSync().last, 2);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(File(sharedPaths[0]).existsSync(), isFalse);
      expect(File(sharedPaths[1]).existsSync(), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(File(sharedPaths[1]).existsSync(), isFalse);
      // Different instances do not share the counter, so the first one
      // already removed the share_plus copy; within one instance it waits.
      expect(copy.existsSync(), isFalse);
    });

    test(
      'within one exchange the share_plus copy waits for the last share',
      () async {
        const name = 'a.gifthuddle';
        final ex = NativeDocumentExchange(
          () async => temp,
          recoveryShareRetention: const Duration(milliseconds: 100),
        );
        final copy = File('${temp.path}/share_plus/$name')
          ..createSync(recursive: true)
          ..writeAsBytesSync([0x47, 0x48, 0x4B, 1]);
        await ex.shareRecoveryFile(
          Uint8List.fromList([0x47, 0x48, 0x4B]),
          name,
          text: 'x',
        );
        await Future<void>.delayed(const Duration(milliseconds: 60));
        await ex.shareRecoveryFile(
          Uint8List.fromList([0x47, 0x48, 0x4B]),
          name,
          text: 'x',
        );
        await Future<void>.delayed(const Duration(milliseconds: 70));
        expect(File(sharedPaths[0]).existsSync(), isFalse);
        expect(
          copy.existsSync(),
          isTrue,
          reason: 'second share still in its margin',
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(copy.existsSync(), isFalse);
      },
    );
  });
}
