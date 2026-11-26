import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Android pasó a la app de Play de la cuenta Mainshai (2026-11-23); iOS no cambia.
  const androidId = 'es.gifthuddle.android';
  const iosId = 'es.gifthuddle.app';
  // Paquete de Play anterior: sus App Links siguen activos mientras queden
  // instalaciones por migrar.
  const previousAndroidId = 'es.gifthuddle.app';
  const uploadKey =
      'D3:6B:C9:55:46:E6:30:10:35:94:98:FD:87:36:FD:C6:16:D2:96:2A:E6:7E:76:CA:DE:23:EA:B1:74:DE:43:CE';

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
          'applicationId = if (legacyAppId) "app.gifthuddle" else "$androidId"',
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
    expect(identifiers.where((id) => id == iosId), hasLength(3));
    expect(identifiers.where((id) => id == '$iosId.RunnerTests'), hasLength(3));
  });

  test(
    'App Links identify only the Mainshai app',
    () {
      final assetLinks = jsonDecode(
        File('../web/public/.well-known/assetlinks.json').readAsStringSync(),
      ) as List<dynamic>;
      Map<String, dynamic> targetFor(String package) => assetLinks
          .map((s) => s['target'] as Map<String, dynamic>)
          .singleWhere((t) => t['package_name'] == package);
      List<String> fingerprintsOf(Map<String, dynamic> target) =>
          (target['sha256_cert_fingerprints'] as List<dynamic>).cast<String>();
      // Solo la app nueva (Daniel, 2026-11-23, QA 1.0.7 R3): con las dos, un
      // enlace de invitación abría el selector de Android con dos «Gift
      // Huddle», y la anterior no puede unirse a una familia 1.0.7.
      expect(assetLinks, hasLength(1));
      expect(
        assetLinks.map((s) => s['target']['package_name']),
        isNot(contains(previousAndroidId)),
      );

      // App nueva: la clave de firma de Play es la de subida (PEPK).
      expect(fingerprintsOf(targetFor(androidId)), [uploadKey]);

      final association = jsonDecode(
        File('../web/public/.well-known/apple-app-site-association')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      final details = association['applinks']['details'] as List<dynamic>;
      expect(details.single['appIDs'], ['4J74M2FPLP.$iosId']);
    },
    skip:
        !File('../web/public/.well-known/assetlinks.json').existsSync() ||
            !File('../web/public/.well-known/apple-app-site-association')
                .existsSync()
        ? 'needs ../web (not in this repository)'
        : false,
  );
}
