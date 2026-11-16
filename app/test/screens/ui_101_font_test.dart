import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/widgets/regalos_nav_bar.dart';
import 'package:regalos/core/widgets/stroke_icon.dart';
import 'package:regalos/features/family/presentation/reparto_grid.dart';

import '../helpers/fonts.dart';
import '../helpers/pump_app.dart';

// Retoques de la 1.0.1 con letra grande: los nombres de quien regala en la
// rejilla de Reparto se entienden (m1) y las cuatro etiquetas de la barra
// inferior miden lo mismo (m4).

const _locales = <String, List<String>>{
  'es': ['Abuelos', 'Nosotros', 'Avis de Girona'],
  'ca': ['Avis', 'Nosaltres', 'Avis de Girona'],
  'en': ['Grandparents', 'Us', 'Aunt Marta'],
};

Giver _giver(int i, String name) => Giver(
  id: 'g$i',
  name: name,
  colorIndex: i,
  householdPays: false,
  archived: false,
);

Widget _grid(List<String> names, {double width = 390, int people = 1}) =>
    SizedBox(
      width: width,
      height: 800,
      child: CustomScrollView(
        slivers: [
          RepartoGrid(
            recipients: [
              for (var i = 0; i < people; i++)
                Recipient(
                  id: 'p$i',
                  name: 'Aritz $i',
                  colorIndex: 0,
                  birthMonth: 3,
                  birthDay: 14,
                  birthYear: 2019,
                  archived: false,
                ),
            ],
            givers: [
              for (var i = 0; i < names.length; i++) _giver(i, names[i]),
            ],
            stats: const <String, RepartoCellStats>{},
            duplicateCells: const <String>{},
            marks: const <String, List<String>>{},
            bumps: RepartoBumps(),
            onOpenCell: (recipient, giver, from, color) {},
            onOpenPerson: (recipient, from) {},
            onInclude: (recipient) {},
          ),
        ],
      ),
    );

void main() {
  // Con Inter de verdad; en Ahem cada letra mide lo que su alto.
  setUpAll(loadInter);

  group('cabecera de Reparto con letra grande', () {
    for (final entry in _locales.entries) {
      for (final scale in [1.0, 1.5, 2.0]) {
        testWidgets('${entry.key} a letra $scale: cada nombre se lee entero, '
            'sin partir palabras ni desbordar', (tester) async {
          await pumpThemed(
            tester,
            _grid(entry.value),
            locale: Locale(entry.key),
            textScale: scale,
            surfaceSize: const Size(390, 800),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (final name in entry.value) {
            final finder = find.text(name);
            expect(finder, findsOneWidget, reason: name);
            final paragraph = tester.renderObject<RenderParagraph>(finder);
            // El texto tiene todas sus palabras enteras: o cabe sin «…», o
            // (letra normal) es el nombre en horizontal de siempre.
            expect(paragraph.didExceedMaxLines, isFalse, reason: name);
            final style = paragraph.text.style!;
            for (final word in name.split(' ')) {
              final painter = TextPainter(
                text: TextSpan(text: word, style: style),
                textDirection: TextDirection.ltr,
                textScaler: paragraph.textScaler,
              )..layout();
              // Nunca más ancha que el sitio que le dan (la columna, o el
              // alto de la cabecera si va en vertical).
              final room = paragraph.size.width;
              expect(
                painter.width,
                lessThanOrEqualTo(room + 0.5),
                reason: 'la palabra «$word» no cabe y se partiría',
              );
            }
          }
          final vertical = find.byType(RotatedBox);
          if (scale >= 2) {
            // Con letra al 200 % los nombres van en vertical, uno por
            // columna y dentro de su columna de 71.
            expect(vertical, findsNWidgets(entry.value.length));
          }
          if (scale > 1) {
            for (final box in tester.widgetList(vertical)) {
              expect(
                tester.getSize(find.byWidget(box)).width,
                lessThanOrEqualTo(71),
              );
            }
          }
          if (scale == 1) {
            expect(vertical, findsNothing);
          }
        });
      }
    }

    testWidgets('una palabra que no cabe va en una sola línea con «…», sin '
        'partirse; si todas caben, dos líneas', (tester) async {
      const long = 'Supercalifragilisticexpialidocious Tia';
      await pumpThemed(
        tester,
        _grid(const [long, 'Us', 'Anna Maria']),
        locale: const Locale('en'),
        textScale: 2,
        surfaceSize: const Size(390, 800),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final longText = tester.widget<Text>(find.text(long));
      expect(longText.maxLines, 1);
      expect(longText.softWrap, isFalse);
      expect(longText.overflow, TextOverflow.ellipsis);
      expect(tester.widget<Text>(find.text('Anna Maria')).maxLines, 2);
      // El nombre entero sigue en el aviso.
      expect(
        tester.widgetList<Tooltip>(find.byType(Tooltip)).map((t) => t.message),
        contains(long),
      );
      // Y la cabecera no pasa de 220.
      final header = tester.renderObject<RenderSliver>(
        find.byType(SliverPersistentHeader),
      );
      expect(header.geometry!.paintExtent, lessThanOrEqualTo(220));
    });

    for (final entry in _locales.entries) {
      testWidgets('${entry.key} en una ventana de 320 y letra 2.0: sin '
          'desbordar y con los nombres en una línea girada', (tester) async {
        await pumpThemed(
          tester,
          _grid(entry.value, width: 320),
          locale: Locale(entry.key),
          textScale: 2,
          surfaceSize: const Size(320, 800),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final name in entry.value) {
          final text = tester.widget<Text>(find.text(name));
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(name),
          );
          expect(paragraph.didExceedMaxLines, isFalse, reason: name);
          // Ninguna palabra más ancha que el sitio que tiene.
          for (final word in name.split(' ')) {
            final painter = TextPainter(
              text: TextSpan(text: word, style: paragraph.text.style),
              textDirection: TextDirection.ltr,
              textScaler: paragraph.textScaler,
            )..layout();
            expect(
              painter.width,
              lessThanOrEqualTo(paragraph.size.width + 0.5),
            );
          }
          expect(text.maxLines, anyOf(1, 2));
        }
        expect(find.byType(RotatedBox), findsNWidgets(entry.value.length));
      });
    }

    test('medir una vez: con los mismos datos no se vuelve a medir', () {
      final layout = RepartoLayout(
        width: 390,
        columns: 3,
        scaler: const TextScaler.linear(2),
      );
      const style = TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
      const names = ['CachéUnoXXXXXXXX', 'CachéDosXXXXXXXX', 'Tres'];
      final before = fitGiverNamesMeasurements;
      final a = fitGiverNames(
        layout: layout,
        names: names,
        style: style,
        scaler: const TextScaler.linear(2),
        direction: TextDirection.ltr,
      );
      expect(fitGiverNamesMeasurements, before + 1);
      final b = fitGiverNames(
        layout: layout,
        names: names,
        style: style,
        scaler: const TextScaler.linear(2),
        direction: TextDirection.ltr,
      );
      expect(fitGiverNamesMeasurements, before + 1);
      expect(b.headerHeight, a.headerHeight);
      expect(b.nameLines, a.nameLines);
      // Otro estilo o otra escala sí miden de nuevo.
      fitGiverNames(
        layout: layout,
        names: names,
        style: style.copyWith(fontSize: 13),
        scaler: const TextScaler.linear(2),
        direction: TextDirection.ltr,
      );
      expect(fitGiverNamesMeasurements, before + 2);
    });

    testWidgets('al desplazar la rejilla no se vuelve a medir', (tester) async {
      await pumpThemed(
        tester,
        _grid(const ['Cache Scroll Abuelos', 'Us', 'Tia'], people: 14),
        locale: const Locale('en'),
        textScale: 2,
        surfaceSize: const Size(390, 800),
      );
      await tester.pumpAndSettle();
      final before = fitGiverNamesMeasurements;
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(fitGiverNamesMeasurements, before);
    });

    testWidgets('el nombre entero sigue en el aviso de la columna', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        _grid(_locales['en']!),
        locale: const Locale('en'),
        textScale: 2,
        surfaceSize: const Size(390, 800),
      );
      await tester.pumpAndSettle();
      final tips = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .toSet();
      expect(tips, containsAll(_locales['en']!));
    });

    testWidgets('la cabecera crece con la letra y no pasa de 220', (
      tester,
    ) async {
      final heights = <double>[];
      for (final scale in [1.0, 1.5, 2.0, 3.0]) {
        await pumpThemed(
          tester,
          _grid(_locales['en']!),
          locale: const Locale('en'),
          textScale: scale,
          surfaceSize: const Size(390, 800),
        );
        await tester.pumpAndSettle();
        final header = tester.renderObject<RenderSliver>(
          find.byType(SliverPersistentHeader),
        );
        heights.add(header.geometry!.paintExtent);
      }
      expect(heights[2], greaterThan(heights[0]));
      expect(heights.last, lessThanOrEqualTo(220));
      expect(tester.takeException(), isNull);
    });
  });

  group('barra inferior con letra grande', () {
    Future<void> pumpBar(
      WidgetTester tester,
      String locale,
      double scale,
      List<String> labels, {
      Size size = const Size(390, 844),
    }) => pumpThemed(
      tester,
      RegalosNavBar(
        semanticLabel: 'nav',
        selectedIndex: 1,
        onSelected: (_) {},
        destinations: [
          NavDestination(icon: AppIcons.people, label: labels[0]),
          NavDestination(icon: AppIcons.family, label: labels[1]),
          NavDestination(icon: AppIcons.occasions, label: labels[2]),
          NavDestination(icon: AppIcons.settings, label: labels[3]),
        ],
      ),
      locale: Locale(locale),
      textScale: scale,
      surfaceSize: size,
    );

    const labels = <String, List<String>>{
      'es': ['Personas', 'Reparto', 'Ocasiones', 'Ajustes'],
      'ca': ['Persones', 'Repartiment', 'Ocasions', 'Ajustos'],
      'en': ['People', 'Who gives', 'Occasions', 'Settings'],
    };

    for (final entry in labels.entries) {
      for (final scale in [1.0, 1.5, 2.0]) {
        testWidgets('${entry.key} a letra $scale: las cuatro etiquetas miden '
            'lo mismo y caben enteras', (tester) async {
          await pumpBar(tester, entry.key, scale, entry.value);
          expect(tester.takeException(), isNull);
          final sizes = <double>{};
          for (final label in entry.value) {
            final text = tester.widget<Text>(find.text(label));
            sizes.add(text.style!.fontSize!);
            // Entera: sin puntos suspensivos y dentro de su destino.
            final item = find.ancestor(
              of: find.text(label),
              matching: find.byType(InkWell),
            );
            final box = tester.getRect(item);
            final glyphs = tester.getRect(find.text(label));
            expect(glyphs.left, greaterThanOrEqualTo(box.left - 0.5));
            expect(glyphs.right, lessThanOrEqualTo(box.right + 0.5));
          }
          // Mismo tamaño de fuente en las cuatro, seleccionada o no.
          expect(sizes.length, 1, reason: '$sizes');
          // Y el tamaño efectivo (con el FittedBox) también es el mismo.
          final heights = {
            for (final label in entry.value)
              tester.getSize(find.text(label)).height.roundToDouble(),
          };
          expect(heights.length, 1, reason: '$heights');
        });
      }
    }

    // Ventana estrecha y letra muy grande: el tamaño común basta para que
    // quepan las cuatro; ninguna se encoge o se corta por su cuenta.
    for (final entry in labels.entries) {
      for (final width in [320.0, 280.0]) {
        for (final scale in [2.0, 3.0]) {
          testWidgets('${entry.key} en $width de ancho a letra $scale: mismo '
              'tamaño en las cuatro y ninguna cortada', (tester) async {
            await pumpBar(
              tester,
              entry.key,
              scale,
              entry.value,
              size: Size(width, 700),
            );
            expect(tester.takeException(), isNull);
            final sizes = <double>{};
            for (final label in entry.value) {
              final text = tester.widget<Text>(find.text(label));
              sizes.add(text.style!.fontSize!);
              final paragraph = tester.renderObject<RenderParagraph>(
                find.text(label),
              );
              expect(paragraph.didExceedMaxLines, isFalse, reason: label);
              final item = tester.getRect(
                find.ancestor(
                  of: find.text(label),
                  matching: find.byType(InkWell),
                ),
              );
              final glyphs = tester.getRect(find.text(label));
              expect(glyphs.left, greaterThanOrEqualTo(item.left - 0.5));
              expect(glyphs.right, lessThanOrEqualTo(item.right + 0.5));
            }
            expect(sizes.length, 1, reason: '$sizes');
            // Sin FittedBox: nadie reduce por su cuenta.
            expect(find.byType(FittedBox), findsNothing);
          });
        }
      }
    }

    testWidgets('con letra normal el tamaño sigue siendo 12', (tester) async {
      await pumpBar(tester, 'es', 1, labels['es']!);
      expect(tester.widget<Text>(find.text('Reparto')).style!.fontSize, 12);
    });
  });
}
