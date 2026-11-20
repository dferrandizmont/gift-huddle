import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/platform/camera_permission.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.dferrandizmont.regalos/incoming');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'iOS checks, requests and opens settings through the native channel',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return call.method == 'requestCameraPermissionStatus'
            ? 'granted'
            : true;
      });
      expect(await hasCameraPermission(), isTrue);
      expect(await requestCameraPermission(), isTrue);
      expect(
        await requestCameraPermissionStatus(),
        CameraPermissionOutcome.granted,
      );
      expect(await openCameraSettings(), isTrue);
      expect(calls, [
        'cameraPermission',
        'requestCameraPermission',
        'requestCameraPermissionStatus',
        'openAppSettings',
      ]);
    },
  );

  test('iOS maps a blocked camera to permanently denied', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'requestCameraPermissionStatus'
          ? 'permanentlyDenied'
          : false,
    );
    expect(await hasCameraPermission(), isFalse);
    expect(
      await requestCameraPermissionStatus(),
      CameraPermissionOutcome.permanentlyDenied,
    );
  });

  test('iOS distinguishes restrictions from app settings denial', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => 'restricted');
    expect(
      await requestCameraPermissionStatus(),
      CameraPermissionOutcome.restricted,
    );
  });

  test('missing status API falls back to the boolean request', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'requestCameraPermissionStatus') {
        throw MissingPluginException();
      }
      return false;
    });
    expect(
      await requestCameraPermissionStatus(),
      CameraPermissionOutcome.denied,
    );
  });

  test('missing native channel preserves test/desktop fallbacks', () async {
    expect(await hasCameraPermission(), isTrue);
    expect(await requestCameraPermission(), isTrue);
    expect(
      await requestCameraPermissionStatus(),
      CameraPermissionOutcome.granted,
    );
    expect(await openCameraSettings(), isFalse);
  });

  test('interrupted request is cancelled', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'interrupted'),
    );
    expect(
      await requestCameraPermissionStatus(),
      CameraPermissionOutcome.cancelled,
    );
  });
}
