import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/layout/content_gutter.dart';
import 'package:regalos/features/family/presentation/reparto_grid.dart';

import '../helpers/pump_app.dart';
import '../helpers/screens.dart';

// Retoques de la QA de la pre.32: el nombre de quien regala no se parte por la
// mitad (m1) y el botón «Añadir regalo» no tapa lo que hay debajo (m2, m3).

/// Anchura de la columna de quien regala en la rejilla de dos columnas.
const double _slot = 52;

/// Comprueba que ninguna palabra de lo pintado se parte: o cada palabra cabe
/// entera en [_slot], o el texto va en una línea con puntos suspensivos. Mide
/// con lo que de verdad pinta el párrafo (estilo, escala, negrita y idioma).
void expectNoWordBreak(WidgetTester tester, String name) {
  final text = tester.widget<Text>(find.text(name));
  final box = tester.getSize(find.byType(FittedGiverName));
  expect(box.width, lessThanOrEqualTo(_slot + 0.01));
  if (text.softWrap == false) {
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    return;
  }
  final paragraph = tester.renderObject<RenderParagraph>(find.text(name));
  for (final word in name.split(' ')) {
    final painter = TextPainter(
      text: TextSpan(text: word, style: paragraph.text.style),
      textDirection: paragraph.textDirection,
      textScaler: paragraph.textScaler,
      locale: paragraph.locale,
    )..layout();
    expect(
      painter.width,
      lessThanOrEqualTo(_slot + 0.01),
      reason: 'la palabra «$word» no cabe y se partiría',
    );
  }
}

void main() {
  for (final bold in [false, true]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final name in ['Grandparents', 'Nosaltres', 'Avis de Girona']) {
        testWidgets(
          'el nombre «$name» a letra $scale'
          '${bold ? ' con negrita de accesibilidad' : ''} no parte palabras',
          (tester) async {
            await pumpThemed(
              tester,
              Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(boldText: bold),
                  child: SizedBox(
                    width: _slot,
                    child: FittedGiverName(
                      name: name,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              textScale: scale,
            );
            expect(tester.takeException(), isNull);
            expectNoWordBreak(tester, name);
          },
        );
      }
    }
  }

  testWidgets('con sitio de sobra el nombre no cambia de tamaño', (
    tester,
  ) async {
    await pumpThemed(
      tester,
      const SizedBox(
        width: 120,
        child: FittedGiverName(
          name: 'Nosotros',
          style: TextStyle(fontSize: 12),
        ),
      ),
    );
    expect(tester.widget<Text>(find.text('Nosotros')).style!.fontSize, 12);
  });

  group('el botón «Añadir regalo»', () {
    Finder fab() => find.byType(FloatingActionButton);

    /// Lo que mide el relleno inferior de la lista de Personas.
    double listBottom(WidgetTester tester) => tester
        .widget<ContentListView>(find.byType(ContentListView).first)
        .padding
        .bottom;

    screenTest('en vertical va extendido y la lista deja su alto debajo', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      expect(tester.getSize(fab()).width, greaterThan(120));
      // El alto del botón y los 16 de margen más otros 16 de aire.
      expect(
        listBottom(tester),
        greaterThanOrEqualTo(tester.getSize(fab()).height + 32),
      );
    });

    screenTest('con letra al 130 % sigue extendido y el hueco lo cubre', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      expect(tester.getSize(fab()).width, greaterThan(120));
      expect(
        listBottom(tester),
        greaterThanOrEqualTo(tester.getSize(fab()).height + 32),
      );
    }, textScale: 1.3);

    screenTest('con letra al 200 % queda en solo icono y deja su hueco', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      expect(tester.getSize(fab()).width, lessThan(70));
      expect(
        listBottom(tester),
        greaterThanOrEqualTo(tester.getSize(fab()).height + 32),
      );
      // Sigue teniendo el nombre para quien usa el lector de pantalla.
      expect(find.bySemanticsLabel(RegExp('Añadir regalo')), findsWidgets);
    }, textScale: 2);

    screenTest('en horizontal queda en solo icono y deja su hueco', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      expect(tester.getSize(fab()).width, lessThan(70));
      expect(
        listBottom(tester),
        greaterThanOrEqualTo(tester.getSize(fab()).height + 32),
      );
    }, size: const Size(844, 390));

    screenTest('se encoge al bajar la lista y se extiende al volver arriba', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      final list = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axis == Axis.vertical,
      );
      expect(tester.getSize(fab()).width, greaterThan(120));
      await tester.drag(list.first, const Offset(0, -300));
      await settle(tester);
      expect(tester.getSize(fab()).width, lessThan(70));
      await tester.drag(list.first, const Offset(0, 600));
      await settle(tester);
      expect(tester.getSize(fab()).width, greaterThan(120));
    }, size: const Size(390, 600));

    screenTest('con muchos desplazamientos muy pequeños también se encoge y '
        'se extiende', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      final list = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axis == Axis.vertical,
      );
      expect(tester.getSize(fab()).width, greaterThan(120));
      final gesture = await tester.startGesture(tester.getCenter(list.first));
      // 200 pasos de medio píxel hacia abajo: ningún evento pasa de 1.
      for (var i = 0; i < 200; i++) {
        await gesture.moveBy(const Offset(0, -0.5));
      }
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.getSize(fab()).width, lessThan(70));
      // Y 80 pasos de medio píxel hacia arriba (40 px): sin llegar al inicio.
      for (var i = 0; i < 80; i++) {
        await gesture.moveBy(const Offset(0, 0.5));
      }
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.getSize(fab()).width, greaterThan(120));
      await gesture.up();
      await settle(tester);
    }, size: const Size(390, 600));
  });
}
