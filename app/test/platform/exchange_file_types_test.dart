import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/exchange_file_names.dart';

void main() {
  test('Android delegates links to plugins and keeps invitation App Links', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(
      manifest,
      matches(
        r'<meta-data\s+android:name="flutter_deeplinking_enabled"\s+'
        r'android:value="false"\s*/>',
      ),
    );
    expect(
      manifest,
      matches(
        r'<intent-filter android:autoVerify="true">\s*'
        r'<action android:name="android.intent.action.VIEW"/>\s*'
        r'<category android:name="android.intent.category.DEFAULT"/>\s*'
        r'<category android:name="android.intent.category.BROWSABLE"/>\s*'
        r'<data android:scheme="https" android:host="gifthuddle.app" '
        r'android:path="/i"/>',
      ),
    );
    final verifiedFilters = RegExp(
      r'<intent-filter android:autoVerify="true">(.*?)</intent-filter>',
      dotAll: true,
    ).allMatches(manifest.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ''));
    expect(verifiedFilters, isNotEmpty);
    for (final filter in verifiedFilters) {
      expect(
        RegExp(r'android:host="([^"]+)"')
            .allMatches(filter.group(1)!)
            .map((m) => m.group(1)),
        everyElement('gifthuddle.app'),
      );
    }
  });

  test('Android reuses its own task for Files and launcher intents', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync()
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
    final activity = RegExp(
      r'<activity\s+android:name=".MainActivity"(.*?)</activity>',
      dotAll: true,
    ).firstMatch(manifest)!.group(1)!;
    expect(activity, contains('android:launchMode="singleTask"'));
    expect(activity, contains('android:taskAffinity=""'));
    expect(activity, contains('android.intent.category.LAUNCHER'));
    expect(activity, contains('android.intent.action.VIEW'));
    expect(activity, contains('android.intent.action.SEND'));
    expect(
      activity,
      contains('orientation|keyboardHidden|keyboard|screenSize'),
    );
    expect(manifest, contains('android.permission.CAMERA'));
  });

  test('iOS associates only the current public invitation host', () {
    final entitlements = File('ios/Runner/Runner.entitlements')
        .readAsStringSync();
    expect(entitlements, contains('<string>applinks:gifthuddle.app</string>'));
    expect(
      RegExp(r'<string>(applinks:[^<]+)</string>')
          .allMatches(entitlements)
          .map((m) => m.group(1)),
      ['applinks:gifthuddle.app'],
    );
  });

  test('Android opens both extensions and receives new and legacy MIME types', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final filters = RegExp(
      r'<intent-filter\b[^>]*>(.*?)</intent-filter>',
      dotAll: true,
    ).allMatches(manifest).map((m) => m.group(1)!).toList();

    for (final action in ['VIEW', 'SEND']) {
      final mimeFilter = filters.singleWhere(
        (f) =>
            f.contains('android.intent.action.$action') &&
            f.contains('android:mimeType="$kExchangeMimeType"'),
      );
      expect(
        mimeFilter,
        contains('android:mimeType="application/octet-stream"'),
      );
      if (action == 'VIEW') {
        expect(mimeFilter, contains('android:scheme="content"'));
        expect(mimeFilter, isNot(contains('android:scheme="file"')));
      }
    }

    final pathFilter = filters.singleWhere(
      (f) =>
          f.contains('android.intent.action.VIEW') &&
          f.contains('android:pathPattern='),
    );
    expect(pathFilter, contains('android:scheme="content"'));
    expect(pathFilter, contains('android:host="*"'));
    expect(pathFilter, contains('android:mimeType="*/*"'));
    for (final extension in kExchangeFileExtensions) {
      for (final dots in ['', r'\..*', r'\..*\..*']) {
        // Android XML escapes a backslash twice; preserve multi-dot filenames.
        final pattern = '.*$dots\\$extension'.replaceAll(r'\', r'\\');
        expect(pathFilter, contains('android:pathPattern="$pattern"'));
      }
    }
  });

  test('iOS exports the new UTI and imports both legacy UTIs', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    String array(String key) => RegExp(
      '<key>$key</key>\\s*<array>(.*?)\\n\\t</array>',
      dotAll: true,
    ).firstMatch(plist)!.group(1)!;

    const uti = 'es.gifthuddle.app.exchange';
    const previousUti = 'app.gifthuddle.exchange';
    const legacyUti = 'com.dferrandizmont.regalos.envelope';
    final exported = array('UTExportedTypeDeclarations');
    expect(exported, contains('<string>$uti</string>'));
    expect(exported, contains('<string>public.data</string>'));
    expect(exported, contains('<key>public.filename-extension</key>'));
    expect(exported, contains('<string>gifthuddle</string>'));
    expect(exported, contains('<key>public.mime-type</key>'));
    expect(exported, contains('<string>$kExchangeMimeType</string>'));
    expect(exported, isNot(contains(legacyUti)));
    expect(exported, isNot(contains(previousUti)));

    final imported = array('UTImportedTypeDeclarations');
    final previousDeclaration = RegExp(
      r'<dict>\s*<key>UTTypeIdentifier</key>\s*'
      '<string>${RegExp.escape(previousUti)}</string>(.*?)</dict>',
      dotAll: true,
    ).firstMatch(imported)!.group(1)!;
    expect(previousDeclaration, contains('<string>public.data</string>'));
    expect(previousDeclaration, contains('<string>gifthuddle</string>'));
    expect(
      previousDeclaration,
      contains('<string>$kExchangeMimeType</string>'),
    );
    expect(imported, isNot(contains('<string>$uti</string>')));
    expect(imported, contains('<string>$legacyUti</string>'));
    expect(imported, contains('<string>regalos</string>'));
    expect(imported, contains('<string>application/octet-stream</string>'));
    final documents = array('CFBundleDocumentTypes');
    expect(documents, contains('<key>LSItemContentTypes</key>'));
    expect(documents, contains('<string>$uti</string>'));
    expect(documents, contains('<string>$previousUti</string>'));
    expect(documents, contains('<string>$legacyUti</string>'));
  });
}
