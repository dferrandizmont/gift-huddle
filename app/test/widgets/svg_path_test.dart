import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/licenses.dart';
import 'package:regalos/core/widgets/svg_path.dart';
import 'package:regalos/core/widgets/tabler_icons.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseSvgPath', () {
    test('líneas, relativas y cierre', () {
      final b = parseSvgPath('M2 2L10 2v8h-8z').getBounds();
      expect(b, const Rect.fromLTRB(2, 2, 10, 10));
    });

    test('H, V y comandos pegados a números', () {
      final b = parseSvgPath('M1,1H5V4h-1.5').getBounds();
      expect(b, const Rect.fromLTRB(1, 1, 5, 4));
    });

    test(
      'un arco de media circunferencia llega al punto y cabe en su caja',
      () {
        final path = parseSvgPath('M4 12a8 8 0 0 1 16 0');
        final b = path.getBounds();
        expect(b.left, closeTo(4, 0.01));
        expect(b.right, closeTo(20, 0.01));
        expect(b.top, closeTo(4, 0.1)); // barrido horario: pasa por arriba
        expect(b.bottom, closeTo(12, 0.01));
      },
    );

    test('curvas cúbicas y suaves', () {
      final b = parseSvgPath('M0 0c2 0 4 2 4 4s2 4 4 4').getBounds();
      expect(b.right, closeTo(8, 0.01));
      expect(b.bottom, closeTo(8, 0.01));
    });

    test('un comando desconocido falla en alto', () {
      expect(() => parseSvgPath('M0 0X1 1'), throwsFormatException);
      expect(() => parseSvgPath('M0 0L'), throwsFormatException);
    });
  });

  group('iconos de Tabler', () {
    test('los datos coinciden con los .svg de assets/icons/tabler', () {
      for (final entry in kTablerIconData.entries) {
        final svg = File('assets/icons/tabler/${entry.key}.svg')
            .readAsStringSync();
        final ds = RegExp(r'<path d="([^"]+)"')
            .allMatches(svg)
            .map((m) => m.group(1)!)
            // El primero de cada archivo es el marco vacío de Tabler.
            .where((d) => d != 'M0 0h24v24H0z')
            .toList();
        expect(entry.value, ds, reason: entry.key);
      }
    });

    test('cada icono se dibuja dentro de la rejilla de 24', () {
      final builders = {
        'gift': tablerGift,
        'cake': tablerCake,
        'balloon': tablerBalloon,
        'snowflake': tablerSnowflake,
        'christmas-tree': tablerChristmasTree,
        'deer': tablerDeer,
        'crown': tablerCrown,
        'star': tablerStar,
        'chess-king': tablerChessKing,
        'fingerprint': tablerFingerprint,
        'backspace': tablerBackspace,
        'layout-grid': tablerLayoutGrid,
        'list': tablerList,
        'alert-triangle': tablerAlertTriangle,
      };
      expect(builders.keys.toSet(), kTablerIconData.keys.toSet());
      for (final e in builders.entries) {
        final path = Path();
        e.value(path);
        final b = path.getBounds();
        expect(b.isEmpty, isFalse, reason: e.key);
        expect(b.left, greaterThanOrEqualTo(0), reason: e.key);
        expect(b.top, greaterThanOrEqualTo(0), reason: e.key);
        expect(b.right, lessThanOrEqualTo(24.01), reason: e.key);
        expect(b.bottom, lessThanOrEqualTo(24.01), reason: e.key);
        // Se puede pedir otra vez (el trazo se guarda).
        final again = Path();
        e.value(again);
        expect(again.getBounds(), b, reason: e.key);
      }
    });

    test('la licencia de Tabler está en el registro de licencias', () async {
      registerAppLicenses();
      final texts = <String>[];
      await for (final entry in LicenseRegistry.licenses) {
        if (entry.packages.contains('Tabler Icons')) {
          texts.add(entry.paragraphs.map((p) => p.text).join('\n'));
        }
      }
      expect(texts, isNotEmpty);
      expect(texts.join(), contains('Paweł Kuna'));
      expect(texts.join(), contains('MIT License'));
    });
  });
}
