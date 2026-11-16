import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/theme/occasion_theme.dart';
import 'package:regalos/core/widgets/occasion_icons.dart';
import 'package:regalos/core/widgets/occasion_stroke_icons.dart';
import 'package:regalos/core/widgets/stroke_icon.dart';
import 'package:regalos/core/widgets/tabler_icons.dart';

import '../helpers/pump_app.dart';

void main() {
  group('iconos de ocasión de trazo propio', () {
    test(
      'los datos coinciden con los SVG de referencia',
      () {
        for (final entry in kOccasionStrokeIconData.entries) {
          final svg = File(
            'test/fixtures/occasion_icons/${entry.key}.svg',
          ).readAsStringSync();
          // Mismo marco que Tabler: 24, trazo 2, extremos y uniones redondos.
          expect(svg, contains('viewBox="0 0 24 24"'), reason: entry.key);
          expect(svg, contains('stroke-width="2"'), reason: entry.key);
          expect(svg, contains('stroke-linecap="round"'), reason: entry.key);
          expect(svg, contains('stroke-linejoin="round"'), reason: entry.key);
          final ds = RegExp(r'<path d="([^"]+)"')
              .allMatches(svg)
              .map((m) => m.group(1)!)
              .toList();
          expect(entry.value, ds, reason: entry.key);
        }
      },
    );

    test('cada icono se dibuja dentro de la rejilla de 24', () {
      final builders = {
        'tio-a': occasionIconTio,
        'santa-a': occasionIconSanta,
        'cny-a': occasionIconChineseNewYear,
        'wedding-b': occasionIconWedding,
      };
      expect(builders.keys.toSet(), kOccasionStrokeIconData.keys.toSet());
      for (final e in builders.entries) {
        final path = Path();
        e.value(path);
        final b = path.getBounds();
        expect(b.isEmpty, isFalse, reason: e.key);
        // Con el trazo de 2 (un 1 a cada lado) sigue dentro de los 24.
        expect(b.left, greaterThanOrEqualTo(1), reason: e.key);
        expect(b.top, greaterThanOrEqualTo(1), reason: e.key);
        expect(b.right, lessThanOrEqualTo(23.01), reason: e.key);
        expect(b.bottom, lessThanOrEqualTo(23.01), reason: e.key);
      }
    });

    test('los cinco tipos del encargo usan trazo y no los de Material', () {
      expect(occasionKindStrokeIcon(OccasionKind.tio), occasionIconTio);
      expect(occasionKindStrokeIcon(OccasionKind.santa), occasionIconSanta);
      expect(occasionKindStrokeIcon(OccasionKind.kings), tablerCrown);
      expect(
        occasionKindStrokeIcon(OccasionKind.chineseNewYear),
        occasionIconChineseNewYear,
      );
      expect(occasionKindStrokeIcon(OccasionKind.wedding), occasionIconWedding);
    });

    test('el resto de tipos sigue con su icono y «Otra» con el elegido', () {
      for (final kind in OccasionKind.values) {
        final hasOwn = occasionKindStrokeIcon(kind) != null;
        expect(
          hasOwn,
          const {
            OccasionKind.tio,
            OccasionKind.santa,
            OccasionKind.kings,
            OccasionKind.chineseNewYear,
            OccasionKind.wedding,
          }.contains(kind),
          reason: kind.name,
        );
      }
      expect(occasionKindIcon(OccasionKind.birthday), Icons.cake_outlined);
      // El nombre guardado de un icono de «Otra» sigue valiendo.
      for (final entry in kOccasionIcons.entries) {
        expect(
          occasionKindIcon(OccasionKind.custom, customIcon: entry.key),
          entry.value,
          reason: entry.key,
        );
      }
      expect(
        occasionKindIcon(OccasionKind.custom, customIcon: 'no-existe'),
        kOccasionIcons[kDefaultOccasionIcon],
      );
      expect(occasionKindIcon(OccasionKind.custom), kOccasionIcons['star']);
    });
  });

  group('OccasionKindIcon', () {
    testWidgets('pinta trazo para los tipos con icono propio', (tester) async {
      for (final kind in [
        OccasionKind.tio,
        OccasionKind.santa,
        OccasionKind.kings,
        OccasionKind.chineseNewYear,
        OccasionKind.wedding,
      ]) {
        await pumpThemed(tester, OccasionKindIcon(kind, size: 20));
        expect(find.byType(StrokeIcon), findsOneWidget, reason: kind.name);
        expect(find.byType(Icon), findsNothing, reason: kind.name);
        expect(tester.getSize(find.byType(StrokeIcon)), const Size(20, 20));
      }
    });

    testWidgets('pinta el de Material para los demás', (tester) async {
      await pumpThemed(tester, const OccasionKindIcon(OccasionKind.birthday));
      expect(find.byType(StrokeIcon), findsNothing);
      expect(tester.widget<Icon>(find.byType(Icon)).icon, Icons.cake_outlined);
      await pumpThemed(
        tester,
        const OccasionKindIcon(OccasionKind.custom, customIcon: 'music'),
      );
      expect(
        tester.widget<Icon>(find.byType(Icon)).icon,
        kOccasionIcons['music'],
      );
    });
  });
}
