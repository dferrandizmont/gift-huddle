import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('fuente Inter', () {
    const fonts = [
      'assets/fonts/inter/Inter-Regular.ttf',
      'assets/fonts/inter/Inter-Medium.ttf',
      'assets/fonts/inter/Inter-SemiBold.ttf',
      'assets/fonts/inter/Inter-Bold.ttf',
    ];

    test('los cuatro pesos van como TTF dentro de la app', () async {
      for (final path in fonts) {
        final data = await rootBundle.load(path);
        expect(data.lengthInBytes, greaterThan(100000), reason: path);
        // Cabecera de TrueType (0x00010000).
        expect(data.buffer.asUint8List(data.offsetInBytes, 4), const [
          0x00,
          0x01,
          0x00,
          0x00,
        ], reason: path);
      }
    });

    test('la licencia OFL de Inter está en el registro de licencias', () async {
      registerAppLicenses();
      final texts = <String>[];
      await for (final entry in LicenseRegistry.licenses) {
        if (entry.packages.contains('Inter')) {
          texts.add(entry.paragraphs.map((p) => p.text).join('\n'));
        }
      }
      expect(texts, isNotEmpty);
      expect(texts.join(), contains('SIL OPEN FONT LICENSE Version 1.1'));
      expect(texts.join(), contains('The Inter Project Authors'));
    });
  });
}
