import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('privacy: iOS camera explains all three QR uses in every locale', () {
    for (final locale in ['es', 'ca', 'en']) {
      final text = File('ios/Runner/$locale.lproj/InfoPlist.strings')
          .readAsStringSync();
      final camera = RegExp(r'"NSCameraUsageDescription" = "([^"]+)"')
          .firstMatch(text)!
          .group(1)!;
      expect(camera, contains('QR'));
      expect(camera, contains('web'));
      expect(
        camera,
        contains(
          locale == 'en'
              ? 'recovery'
              : locale == 'es'
              ? 'recuperación'
              : 'recuperació',
        ),
      );
    }
    expect(
      File('ios/Runner/Info.plist').readAsStringSync(),
      contains('recuperación'),
    );
  });
  test('privacy: the packaged iOS manifest declares linked device data, no tracking and required API reasons', () {
    final manifest = File('ios/Runner/PrivacyInfo.xcprivacy')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(manifest, contains('<key>NSPrivacyTracking</key>\n\t<false/>'));
    expect(
      manifest,
      contains('<key>NSPrivacyTrackingDomains</key>\n\t<array/>'),
    );
    for (final category in ['DeviceID', 'ProductInteraction']) {
      final declaration = RegExp(
        '<dict>\\s*<key>NSPrivacyCollectedDataType</key>\\s*'
        '<string>NSPrivacyCollectedDataType$category</string>(.*?)</dict>',
        dotAll: true,
      ).firstMatch(manifest);
      expect(declaration, isNotNull, reason: category);
      final data = declaration!.group(1)!;
      expect(
        data,
        matches(r'<key>NSPrivacyCollectedDataTypeLinked</key>\s*<true/>'),
      );
      expect(
        data,
        matches(r'<key>NSPrivacyCollectedDataTypeTracking</key>\s*<false/>'),
      );
      expect(
        data,
        matches(
          r'<key>NSPrivacyCollectedDataTypePurposes</key>\s*<array>\s*'
          r'<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>\s*</array>',
        ),
      );
    }
    expect(manifest, contains('CA92.1'));
    expect(manifest, contains('C617.1'));
    final project = File('ios/Runner.xcodeproj/project.pbxproj')
        .readAsStringSync();
    expect(
      RegExp('PrivacyInfo.xcprivacy in Resources').allMatches(project).length,
      greaterThanOrEqualTo(2),
    );
  });
}
