import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Los permisos de iOS (cámara, Face ID) salen en el idioma del móvil: cada
/// idioma de la app tiene su `InfoPlist.strings` registrado en el proyecto.
void main() {
  const langs = ['es', 'ca', 'en'];
  const keys = ['NSCameraUsageDescription', 'NSFaceIDUsageDescription'];

  Map<String, String> read(String lang) {
    final text = File('ios/Runner/$lang.lproj/InfoPlist.strings')
        .readAsStringSync();
    return {
      for (final m in RegExp(
        r'^"([^"]+)"\s*=\s*"([^"]*)";',
        multiLine: true,
      ).allMatches(text))
        m.group(1)!: m.group(2)!,
    };
  }

  test('cada idioma traduce los dos permisos, sin dejarlos vacíos', () {
    for (final lang in langs) {
      final strings = read(lang);
      expect(strings.keys.toSet(), keys.toSet(), reason: lang);
      for (final v in strings.values) {
        expect(v.trim(), isNotEmpty, reason: lang);
      }
    }
    // Y no son el mismo texto copiado en los tres.
    for (final k in keys) {
      expect({for (final l in langs) read(l)[k]}.length, 3, reason: k);
    }
  });

  test('Info.plist declara las claves y los tres idiomas', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    for (final k in keys) {
      expect(plist, contains('<key>$k</key>'));
    }
    final loc = RegExp(
      r'<key>CFBundleLocalizations</key>\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(plist);
    expect(loc, isNotNull);
    for (final l in langs) {
      expect(loc!.group(1), contains('<string>$l</string>'));
    }
  });

  test('el proyecto de Xcode registra las traducciones', () {
    final pbx = File('ios/Runner.xcodeproj/project.pbxproj')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(
      RegExp(r'knownRegions = \(([^)]*)\);').firstMatch(pbx)!.group(1),
      allOf(contains('es,'), contains('ca,'), contains('en,')),
    );
    for (final l in langs) {
      expect(pbx, contains('path = $l.lproj/InfoPlist.strings;'));
    }
    // El grupo de variantes y su paso por «Resources».
    final group = RegExp(
      r'(\w{24}) /\* InfoPlist.strings \*/ = \{\s*isa = PBXVariantGroup;',
    ).firstMatch(pbx);
    expect(group, isNotNull);
    final id = group!.group(1)!;
    expect(
      pbx,
      contains('fileRef = $id /* InfoPlist.strings */;'),
      reason: 'build file',
    );
    expect(pbx, contains('$id /* InfoPlist.strings */,'), reason: 'grupo');
    // Todos los identificadores nuevos son únicos.
    final defs = RegExp(
      r'^\t\t(\w{24}) /\*',
      multiLine: true,
    ).allMatches(pbx).map((m) => m.group(1)!).toList();
    expect(defs.toSet().length, defs.length);
  });
}
