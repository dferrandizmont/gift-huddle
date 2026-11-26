import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(LicenseRegistry.reset);

  test('las fuentes web no se registran en la app nativa', () async {
    registerAppLicenses();
    await for (final entry in LicenseRegistry.licenses) {
      expect(entry.packages, isNot(contains(startsWith('Noto '))));
    }
  }, skip: kIsWeb);

  test('registra los avisos OFL de las fuentes web desde los assets', () async {
    registerWebFallbackFontLicenses();
    final notices = <String, List<String>>{};
    await for (final entry in LicenseRegistry.licenses) {
      for (final package in entry.packages.where(
        (name) => name.startsWith('Noto '),
      )) {
        final text = entry.paragraphs
            .map((paragraph) => paragraph.text)
            .join('\n');
        (notices[package] ??= []).add(text);
      }
    }

    const copyrights = {
      'Noto Color Emoji': 'Copyright 2021 Google Inc.',
      'Noto Sans Arabic': 'The Noto Project Authors',
      'Noto Sans HK': 'Copyright 2014-2021 Adobe',
      'Noto Sans JP': 'Copyright 2014-2021 Adobe',
      'Noto Sans KR': 'Copyright 2014-2021 Adobe',
      'Noto Sans SC': 'Copyright 2014-2021 Adobe',
      'Noto Sans TC': 'Copyright 2014-2021 Adobe',
      'Noto fallback fonts': 'Noto Sans Hebrew',
    };
    expect(notices.keys, unorderedEquals(copyrights.keys));
    for (final MapEntry(key: family, value: copyright) in copyrights.entries) {
      expect(notices[family], hasLength(1), reason: family);
      expect(notices[family]!.single, contains(copyright), reason: family);
      expect(
        notices[family]!.single,
        contains('SIL OPEN FONT LICENSE Version 1.1'),
        reason: family,
      );
    }
  });
}
