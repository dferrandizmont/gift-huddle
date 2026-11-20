import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const appId = 'es.gifthuddle.app';

  test(
    'Android defaults to the new ID and opts into the bridge ID and manifest',
    () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(
        gradle,
        contains(
          'val legacyAppId = project.findProperty("legacyAppId") == "true"',
        ),
      );
      expect(
        gradle,
        contains(
          'applicationId = if (legacyAppId) "app.gifthuddle" else "$appId"',
        ),
      );
      expect(gradle, contains('namespace = "com.dferrandizmont.regalos"'));
      expect(
        gradle,
        matches(
          r'sourceSets\.getByName\("main"\)\s*\{\s*'
          r'manifest\.srcFile\(if \(legacyAppId\) '
          r'"src/legacy/AndroidManifest.xml" else "src/main/AndroidManifest.xml"\)',
        ),
      );
    },
  );

  test(
    'bridge retains common Android settings and only the launcher filter',
    () {
      String readManifest(String source) =>
          File('android/app/src/$source/AndroidManifest.xml')
              .readAsStringSync()
              .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

      final normal = readManifest('main');
      final legacy = readManifest('legacy');
      expect(normal, contains('android:label="Gift Huddle"'));
      expect(legacy, contains('android:label="Gift Huddle (antigua)"'));

      final filters = RegExp(r'<intent-filter\b[^>]*>[\s\S]*?</intent-filter>');
      final legacyFilters = filters.allMatches(legacy).toList();
      expect(legacyFilters, hasLength(1));
      expect(
        legacyFilters.single.group(0),
        contains('android.intent.action.MAIN'),
      );
      expect(
        legacyFilters.single.group(0),
        contains('android.intent.category.LAUNCHER'),
      );
      expect(legacy, isNot(contains('android:autoVerify')));
      expect(legacy, isNot(contains('android.intent.action.VIEW')));
      expect(legacy, isNot(contains('android.intent.action.SEND')));

      // Evita que la copia puente pierda permisos, protección de datos u otras
      // opciones comunes cuando se cambie el manifiesto normal.
      final common = normal.replaceAllMapped(filters, (match) {
        final filter = match.group(0)!;
        return filter.contains('android.intent.action.MAIN') ? filter : '';
      });
      String compact(String xml) => xml.replaceAll(RegExp(r'\s+'), '');
      expect(
        compact(legacy.replaceFirst('Gift Huddle (antigua)', 'Gift Huddle')),
        compact(common),
      );
    },
  );

  test('all iOS build configurations use the new bundle identifiers', () {
    final project = File('ios/Runner.xcodeproj/project.pbxproj')
        .readAsStringSync();
    final identifiers = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);')
        .allMatches(project)
        .map((match) => match.group(1)!)
        .toList();
    expect(identifiers, hasLength(6));
    expect(identifiers.where((id) => id == appId), hasLength(3));
    expect(identifiers.where((id) => id == '$appId.RunnerTests'), hasLength(3));
  });

  test(
    'App Links identify the new app with the Play and upload keys',
    () {
      final assetLinks = jsonDecode(
        File('../web/public/.well-known/assetlinks.json').readAsStringSync(),
      ) as List<dynamic>;
      final target = assetLinks.single['target'] as Map<String, dynamic>;
      expect(target['package_name'], appId);
      final fingerprints = (target['sha256_cert_fingerprints'] as List<dynamic>)
          .cast<String>();
      // La firma de apps de Google Play y la de subida, sin marcadores.
      expect(fingerprints, hasLength(2));
      for (final f in fingerprints) {
        expect(f, matches(RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$')));
      }

      final association = jsonDecode(
        File('../web/public/.well-known/apple-app-site-association')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      final details = association['applinks']['details'] as List<dynamic>;
      expect(details.single['appIDs'], ['4J74M2FPLP.$appId']);
    },
    skip:
        !File('../web/public/.well-known/assetlinks.json').existsSync() ||
            !File('../web/public/.well-known/apple-app-site-association')
                .existsSync()
        ? 'needs ../web (not in this repository)'
        : false,
  );
}
