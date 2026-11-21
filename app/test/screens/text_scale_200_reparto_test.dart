import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/family/presentation/giver_picker.dart';
import 'package:regalos/features/family/presentation/reparto_outside.dart';
import 'package:regalos/features/family/presentation/reparto_person_sheet.dart';
import 'package:regalos/features/family/presentation/reparto_sheet.dart';
import 'package:regalos/features/family/presentation/reparto_view_toggle.dart';

import '../helpers/fonts.dart';
import '../helpers/screens.dart';

// Letra al 200 % en móviles estrechos: en Reparto (rejilla y lista, cabecera,
// filtros, hojas de persona y de regalo) y en la barra inferior, ningún texto
// se corta con «…» ni se parte una palabra a mitad. Se repite en es, ca y en.

/// Un texto que no cabe como debería.
class TextProblem {
  TextProblem(this.kind, this.text, this.detail);

  final String kind;
  final String text;
  final String detail;

  @override
  String toString() => '$kind «$text» $detail';
}

/// Los títulos de regalo: los escribe la persona, pueden ser de cualquier
/// largo y acaban en «…» a propósito (el valor entero está en la hoja).
const _giftTitles = <String>{
  'Pijama de astronautas, talla 8',
  'Libro de dinosaurios con solapas',
  'Estación de bomberos de bloques',
  'Bici de 20" con cambios',
  'Puzle de 48 piezas',
  'Cocinita de madera',
  'Libro de cuentos',
};

/// Los nombres de quien regala: solo se admite el «…» en la cabecera girada
/// de las columnas de la rejilla (con el nombre entero en su aviso). En un
/// chip de quien regala NO: ahí se leen enteros.
const _giverNames = <String>{
  'Nosotros',
  'Nosaltres',
  'Us',
  'Yayos de Terrassa',
  'Avis de Girona',
  'Tía Marta y Jordi',
  'Tío Pere',
  'Padrina Anna',
};

/// La cabecera de columna de quien regala va girada: en vertical
/// (`RotatedBox`, letra grande) o inclinada (`Transform`, columnas estrechas).
bool _inRotatedBox(RenderObject ro) {
  for (RenderObject? p = ro.parent; p != null; p = p.parent) {
    if (p is RenderRotatedBox || p is RenderTransform) {
      return true;
    }
  }
  return false;
}

/// Recorre el árbol de pintura buscando textos con «…» efectivo o con una
/// palabra más ancha que su caja (que se partiría a mitad).
///
/// [ellipsisOk] son nombres de persona que el test declara a propósito como
/// «pueden acabar en …» (un nombre de usuario sin límite de largo).
List<TextProblem> findTextProblems(
  WidgetTester tester,
  Size screen, {
  Set<String> ellipsisOk = const <String>{},
}) {
  bool allowed(String text, RenderParagraph ro) =>
      _giftTitles.contains(text) ||
      ellipsisOk.contains(text) ||
      (_giverNames.contains(text) && _inRotatedBox(ro));

  final out = <TextProblem>[];
  final bounds = Offset.zero & screen;

  void visit(RenderObject ro) {
    if (ro is RenderOffstage && ro.offstage) {
      return;
    }
    if (ro is RenderParagraph && ro.attached && ro.hasSize) {
      final text = ro.text.toPlainText().replaceAll('￼', '').trim();
      if (text.isNotEmpty) {
        final rect = MatrixUtils.transformRect(
          ro.getTransformTo(null),
          Offset.zero & ro.size,
        );
        final visible = rect.overlaps(bounds) && !rect.isEmpty;
        if (visible) {
          if (ro.didExceedMaxLines && !allowed(text, ro)) {
            out.add(TextProblem('elipsis', text, 'en ${rect.size}'));
          }
          final style = ro.text.style;
          for (final word in text.split(RegExp(r'\s+'))) {
            if (word.isEmpty) {
              continue;
            }
            final painter = TextPainter(
              text: TextSpan(text: word, style: style),
              textDirection: TextDirection.ltr,
              textScaler: ro.textScaler,
              locale: ro.locale,
            )..layout();
            // Más ancha que la caja que la contiene: se partiría.
            if (painter.width > ro.size.width + 0.5 &&
                !ro.didExceedMaxLines &&
                !allowed(text, ro)) {
              out.add(
                TextProblem(
                  'palabra partida',
                  text,
                  '«$word» mide ${painter.width.toStringAsFixed(1)} en '
                      '${ro.size.width.toStringAsFixed(1)}',
                ),
              );
            }
            painter.dispose();
          }
        }
      }
    }
    ro.visitChildren(visit);
  }

  visit(tester.binding.renderViews.first);
  return out;
}

const _tabLabels = <String, List<String>>{
  'es': ['Personas', 'Reparto', 'Ocasiones', 'Ajustes'],
  'ca': ['Persones', 'Repartiment', 'Ocasions', 'Ajustos'],
  'en': ['People', 'Who gives', 'Occasions', 'Settings'],
};

const _grid = <String, String>{
  'es': 'Rejilla',
  'ca': 'Quadrícula',
  'en': 'Grid',
};

const _occasion = <String, String>{
  'es': 'Por ocasión',
  'ca': 'Per ocasió',
  'en': 'By occasion',
};

void main() {
  setUpAll(loadInter);

  const sizes = <String, Size>{
    '360x800': Size(360, 800),
    '320x640': Size(320, 640),
  };

  for (final lang in ['ca', 'es', 'en']) {
    for (final entry in sizes.entries) {
      screenTest(
        '$lang ${entry.key} a letra 2.0: Reparto (rejilla y lista), hojas y '
        'barra inferior sin textos cortados',
        (tester, phone) async {
          tester.platformDispatcher.localesTestValue = [Locale(lang)];
          tester.platformDispatcher.localeTestValue = Locale(lang);
          await seedSample(tester, phone);
          await pumpRegalos(tester, phone);
          final screen = entry.value;
          final found = <String, List<TextProblem>>{};
          void check(String where) {
            final e = tester.takeException();
            final problems = findTextProblems(tester, screen);
            if (e != null) {
              problems.add(
                TextProblem(
                  'excepcion',
                  e is FlutterError
                      ? e.diagnostics.map((d) => d.toStringDeep()).join(' // ')
                      : e.toString(),
                  '',
                ),
              );
            }
            if (problems.isNotEmpty) {
              found[where] = problems;
            }
          }

          // Baja la pantalla de a poco y comprueba cada trozo.
          Future<void> scrollAll(String where) async {
            final scrollable = find
                .byWidgetPredicate(
                  (w) => w is Scrollable && w.axis == Axis.vertical,
                )
                .first;
            for (var i = 1; i <= 6; i++) {
              await tester.drag(
                scrollable,
                Offset(0, -screen.height * 0.5),
                warnIfMissed: false,
              );
              await tester.pump(const Duration(milliseconds: 400));
              check('$where-scroll$i');
            }
            await tester.drag(
              scrollable,
              Offset(0, screen.height * 6),
              warnIfMissed: false,
            );
            await settle(tester);
          }

          // Con letra grande y una ventana baja lo que se busca puede quedar por
          // debajo del borde: se baja hasta verlo.
          Future<void> reveal(Finder finder) async {
            final scrollable = find
                .byWidgetPredicate(
                  (w) => w is Scrollable && w.axis == Axis.vertical,
                )
                .first;
            for (var i = 0; i < 12 && finder.evaluate().isEmpty; i++) {
              await tester.drag(
                scrollable,
                const Offset(0, -200),
                warnIfMissed: false,
              );
              await tester.pump(const Duration(milliseconds: 300));
            }
          }

          check('inicio');
          await tester.tap(find.text(_tabLabels[lang]![1]).last);
          await settle(tester);
          check('reparto-rejilla');

          // Hoja de una celda, con el selector de quién regala desplegado.
          final cell = find.bySemanticsLabel(
            RegExp(r' (para|per a|for) (Aritz|Nora|Leo): \d'),
          );
          await reveal(cell);
          expect(cell, findsWidgets);
          await tester.ensureVisible(cell.first);
          await tester.pump();
          await tester.tap(cell.first);
          await settle(tester);
          expect(find.byKey(kRepartoSheetKey), findsOneWidget);
          check('hoja-celda');
          final sheetChip = find.descendant(
            of: find.byKey(kRepartoSheetKey),
            matching: find.byType(GiverChip),
          );
          if (sheetChip.evaluate().isNotEmpty) {
            await tester.tap(sheetChip.first, warnIfMissed: false);
            await settle(tester);
            check('hoja-celda-selector');
          }
          await tester.binding.handlePopRoute();
          await settle(tester);

          // Hoja de los regalos sin quién regala.
          final unassigned = find.textContaining(
            RegExp('sense qui|sin quién|sin asignar|unassigned'),
          );
          if (unassigned.evaluate().isNotEmpty) {
            await tester.tap(unassigned.first, warnIfMissed: false);
            await settle(tester);
            check('hoja-sin-quien');
            await tester.binding.handlePopRoute();
            await settle(tester);
          }

          await scrollAll('rejilla');

          // Lista por ocasión.
          await tester.tap(find.bySemanticsLabel(_occasion[lang]!));
          await settle(tester);
          check('reparto-lista');

          // Ficha de persona.
          final openers = find.bySemanticsLabel(
            RegExp('^(Abrir la ficha|Obrir la fitxa|Open)'),
          );
          await reveal(openers);
          expect(openers, findsWidgets);
          await tester.ensureVisible(openers.first);
          await tester.pump();
          await tester.tap(openers.first);
          await settle(tester);
          check('ficha-persona');
          expect(find.byKey(kRepartoInRepartoKey), findsOneWidget);
          // Pasa a «fuera del reparto» y se ve la sección plegable.
          await tester.tap(find.byKey(kRepartoInRepartoKey));
          await settle(tester);
          check('ficha-persona-fuera');
          await tester.binding.handlePopRoute();
          await settle(tester);
          check('reparto-lista-2');
          final listChip = find.byType(GiverChip);
          if (listChip.evaluate().isNotEmpty) {
            await tester.tap(listChip.first, warnIfMissed: false);
            await settle(tester);
            check('lista-selector');
            await tester.tap(listChip.first, warnIfMissed: false);
            await settle(tester);
          }
          await scrollAll('lista-2');

          await tester.tap(find.bySemanticsLabel(_grid[lang]!));
          await settle(tester);
          check('reparto-rejilla-2');
          expect(find.byKey(kRepartoViewToggleKey), findsOneWidget);
          final toggle = find.byKey(kRepartoOutsideToggleKey);
          await tester.scrollUntilVisible(
            toggle,
            200,
            scrollable: find
                .byWidgetPredicate(
                  (w) => w is Scrollable && w.axis == Axis.vertical,
                )
                .first,
          );
          await tester.pump();
          await tester.tap(toggle);
          await settle(tester);
          check('fuera-del-reparto');
          await scrollAll('fuera');

          final report = StringBuffer();
          found.forEach((where, list) {
            report.writeln('== $where');
            for (final p in list) {
              report.writeln('  $p');
            }
          });
          // ignore: avoid_print
          print('[$lang ${entry.key}]\n$report');
          expect(found, isEmpty, reason: report.toString());
        },
        size: entry.value,
        textScale: 2,
      );
    }
  }
}
