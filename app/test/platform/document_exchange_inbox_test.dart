import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/platform/document_exchange_native.dart';

/// Revisión de seguridad: iOS guarda en `Documents/Inbox` una copia de cada
/// `.regalos` que se abre con la app. «Borrar todo» (`clearExports`) pide al
/// código nativo que la vacíe.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  final calls = <MethodCall>[];
  Object? nativeError;

  NativeDocumentExchange exchange() => NativeDocumentExchange(() async => temp);

  setUp(() {
    temp = Directory.systemTemp.createTempSync('regalos_inbox_');
    calls.clear();
    nativeError = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kIncomingChannel, (call) async {
          calls.add(call);
          final error = nativeError;
          if (error != null) {
            throw error;
          }
          return null;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kIncomingChannel, null);
    temp.deleteSync(recursive: true);
  });

  test('en iPhone, además de los exportados, vacía Inbox por el canal '
      'nativo', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    File('${temp.path}/regalos-2026-11-12-1000.regalos').writeAsStringSync('x');
    await exchange().clearExports();
    expect(calls.map((c) => c.method), ['clearInbox']);
    expect(calls.single.arguments, isNull);
    expect(temp.listSync(), isEmpty);
  });

  test('en iPhone la vacía aunque no haya carpeta temporal', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final broken = NativeDocumentExchange(
      () async => throw const FileSystemException('sin carpeta temporal'),
    );
    await broken.clearExports();
    expect(calls.map((c) => c.method), ['clearInbox']);
  });

  test('si el código nativo falla o no existe, no falla', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    nativeError = PlatformException(code: 'inbox_failed');
    await exchange().clearExports();
    expect(calls, hasLength(1));

    nativeError = MissingPluginException('sin código nativo');
    await exchange().clearExports();
    expect(calls, hasLength(2));
  });

  test('borra ambas extensiones en temporales y share_plus, sin tocar otros '
      'ficheros ni directorios', () async {
    final shared = Directory('${temp.path}/share_plus')..createSync();
    for (final folder in [temp, shared]) {
      for (final name in [
        'copy.gifthuddle',
        'old.regalos',
        'COPY.GIFTHUDDLE',
        'OLD.REGALOS',
      ]) {
        File('${folder.path}/$name').writeAsStringSync('encrypted');
      }
      File('${folder.path}/keep.txt').writeAsStringSync('keep');
      Directory('${folder.path}/keep.gifthuddle').createSync();
    }
    await exchange().clearExports();
    for (final folder in [temp, shared]) {
      expect(
        folder.listSync().whereType<File>().map((f) => f.uri.pathSegments.last),
        ['keep.txt'],
      );
      expect(Directory('${folder.path}/keep.gifthuddle').existsSync(), isTrue);
    }
  });

  test('en Android no hay Inbox: no se llama al código nativo', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    File('${temp.path}/regalos-2026-11-12-1000.regalos').writeAsStringSync('x');
    await exchange().clearExports();
    expect(calls, isEmpty);
    expect(temp.listSync(), isEmpty);
  });
}
