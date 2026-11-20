import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/theme/gift_status.dart';
import 'package:regalos/core/theme/regalos_motion.dart';
import 'package:regalos/core/theme/regalos_shape.dart';
import 'package:regalos/core/theme/regalos_tokens.dart';
import 'package:regalos/core/widgets/choice_grid.dart';
import 'package:regalos/core/widgets/gift_status_l10n.dart';
import 'package:regalos/core/widgets/status_checkbox.dart';
import 'package:regalos/features/family/presentation/occasion_sheet.dart';
import 'package:regalos/l10n/app_localizations.dart';

import '../helpers/fonts.dart';
import '../helpers/pump_app.dart';

/// Las celdas de la rejilla, en orden de lectura.
final Finder _cells = find.descendant(
  of: find.byType(ChoiceGrid),
  matching: find.byType(InkWell),
);

/// Comprueba que la rejilla tiene [columns] columnas del mismo ancho, que las
/// celdas de una fila miden lo mismo de alto y que ningún nombre se corta, se
/// sale de su celda ni parte una palabra. Con [maxLines], que ninguno pasa de
/// esas líneas (a 18 px cada una, con la letra a su tamaño).
void _expectTidyGrid(
  WidgetTester tester, {
  required int columns,
  int? maxLines,
}) {
  final rects = [
    for (final element in _cells.evaluate())
      tester.getRect(find.byWidget(element.widget)),
  ];
  final width = rects.first.width;
  for (final rect in rects) {
    expect(rect.width, moreOrLessEquals(width, epsilon: 0.01));
  }
  expect({for (final r in rects) r.left.round()}, hasLength(columns));
  final gridWidth = tester.getSize(find.byType(ChoiceGrid)).width;
  expect(
    width,
    moreOrLessEquals(
      (gridWidth - ChoiceGrid.gap * (columns - 1)) / columns,
      epsilon: 0.01,
    ),
  );
  final heights = <int, Set<int>>{};
  for (final rect in rects) {
    heights.putIfAbsent(rect.top.round(), () => {}).add(rect.height.round());
    expect(rect.height, greaterThanOrEqualTo(ChoiceGrid.minCellHeight));
  }
  for (final row in heights.entries) {
    expect(row.value, hasLength(1), reason: 'fila en y=${row.key}');
  }
  for (final element in _cells.evaluate()) {
    final cell = find.byWidget(element.widget);
    final text = find.descendant(of: cell, matching: find.byType(Text));
    final label = tester.widget<Text>(text).data!;
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)),
    );
    expect(paragraph.didExceedMaxLines, isFalse, reason: label);
    if (maxLines != null) {
      expect(
        paragraph.size.height,
        lessThanOrEqualTo(18.0 * maxLines + 0.5),
        reason: label,
      );
    }
    // La palabra más larga cabe entera en el ancho que tiene el nombre.
    expect(
      paragraph.getMinIntrinsicWidth(double.infinity),
      lessThanOrEqualTo(paragraph.constraints.maxWidth + 0.01),
      reason: label,
    );
    final cellRect = tester.getRect(cell);
    final textRect = tester.getRect(text);
    expect(cellRect.contains(textRect.topLeft), isTrue, reason: label);
    expect(
      cellRect.inflate(0.01).contains(textRect.bottomRight),
      isTrue,
      reason: label,
    );
  }
}

Future<void> _openOccasionSheet(
  WidgetTester tester, {
  required Locale locale,
  double width = 360,
  double textScale = 1,
  bool? disableAnimations,
}) async {
  await pumpThemed(
    tester,
    Builder(
      builder: (context) => FilledButton(
        onPressed: () => showOccasionSheet(context),
        child: const Text('+'),
      ),
    ),
    locale: locale,
    textScale: textScale,
    disableAnimations: disableAnimations,
    surfaceSize: Size(width, 1500),
  );
  await withClock(Clock.fixed(DateTime(2026, 11, 9, 10)), () async {
    await tester.tap(find.text('+'));
    await tester.pumpAndSettle();
  });
}

/// El selector de estado del editor de regalo, suelto.
Widget _statusGrid({GiftStatus? selected, ValueChanged<GiftStatus>? onTap}) =>
    Builder(
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return ChoiceGrid(
          leadingSize: 16,
          leadingGap: 5,
          items: [
            for (final status in GiftStatus.values)
              ChoiceGridItem(
                label: status.label(l10n),
                leading: (color, chosen) => StatusGlyph(
                  status: status,
                  size: 16,
                  stroke: chosen ? color : null,
                ),
                selected: status == selected,
                onTap: () => onTap?.call(status),
              ),
          ],
        );
      },
    );

void main() {
  setUpAll(loadInter);

  for (final locale in const [Locale('es'), Locale('ca'), Locale('en')]) {
    testWidgets('tipos de ocasión a 360 dp en $locale: dos columnas iguales '
        'y ningún nombre cortado', (tester) async {
      await _openOccasionSheet(tester, locale: locale);
      expect(tester.takeException(), isNull);
      expect(_cells, findsNWidgets(12));
      _expectTidyGrid(tester, columns: 2, maxLines: 2);
      // Con dos líneas como mucho, todas las filas miden lo mismo.
      expect(
        {
          for (final element in _cells.evaluate())
            tester.getSize(find.byWidget(element.widget)).height,
        },
        {ChoiceGrid.minCellHeight},
      );
    });

    testWidgets('estados del regalo a 328 dp en $locale: tres columnas '
        'iguales y ningún nombre cortado', (tester) async {
      await pumpThemed(
        tester,
        SizedBox(width: 328, child: _statusGrid(selected: GiftStatus.bought)),
        locale: locale,
        surfaceSize: const Size(360, 600),
      );
      expect(tester.takeException(), isNull);
      expect(_cells, findsNWidgets(6));
      _expectTidyGrid(tester, columns: 3, maxLines: 2);
    });
  }

  testWidgets('en una pantalla muy estrecha los estados pasan a dos columnas '
      'en vez de partir palabras', (tester) async {
    await pumpThemed(
      tester,
      SizedBox(width: 288, child: _statusGrid(selected: GiftStatus.bought)),
      surfaceSize: const Size(320, 600),
    );
    expect(tester.takeException(), isNull);
    _expectTidyGrid(tester, columns: 2, maxLines: 1);
  });

  testWidgets('con sitio de sobra los tipos van en tres columnas', (
    tester,
  ) async {
    await _openOccasionSheet(tester, locale: const Locale('es'), width: 600);
    expect(tester.takeException(), isNull);
    _expectTidyGrid(tester, columns: 3);
  });

  testWidgets('con la letra muy grande baja de columnas en vez de partir '
      'palabras', (tester) async {
    await _openOccasionSheet(tester, locale: const Locale('es'), textScale: 2);
    expect(tester.takeException(), isNull);
    _expectTidyGrid(tester, columns: 1);
  });

  testWidgets('las celdas son rectángulos de radio 8 y la elegida se rellena '
      'con el acento', (tester) async {
    final semantics = tester.ensureSemantics();
    await _openOccasionSheet(tester, locale: const Locale('es'));
    final tokens = RegalosTokens.of(tester.element(find.byType(ChoiceGrid)));

    BoxDecoration decorationOf(String label) =>
        tester
                .widget<AnimatedContainer>(
                  find
                      .ancestor(
                        of: find.text(label),
                        matching: find.byType(AnimatedContainer),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;

    for (final container in tester.widgetList<AnimatedContainer>(
      find.descendant(
        of: find.byType(ChoiceGrid),
        matching: find.byType(AnimatedContainer),
      ),
    )) {
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.borderRadius, RegalosShape.chip);
      expect(decoration.color!.a, 0);
    }
    expect(RegalosShape.chipRadius, lessThanOrEqualTo(8));

    final before = tester.getRect(find.bySemanticsLabel('Reyes'));
    await tester.tap(find.bySemanticsLabel('Reyes'));
    await tester.pump();
    // El relleno va con muelle: a medio camino sigue animándose.
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();

    expect(decorationOf('Reyes').color, tokens.selection);
    expect(decorationOf('Reyes').borderRadius, RegalosShape.chip);
    expect(decorationOf('Boda').color!.a, 0);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Reyes')),
      matchesSemantics(
        label: 'Reyes',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );
    // Elegir no mueve nada: la celda mide lo mismo.
    expect(tester.getRect(find.bySemanticsLabel('Reyes')), before);
    semantics.dispose();
  });

  testWidgets('con «Reducir movimiento» elegir es un fundido de 150 ms', (
    tester,
  ) async {
    GiftStatus? chosen;
    await pumpThemed(
      tester,
      StatefulBuilder(
        builder: (context, setState) => SizedBox(
          width: 328,
          child: _statusGrid(
            selected: chosen,
            onTap: (status) => setState(() => chosen = status),
          ),
        ),
      ),
      disableAnimations: true,
      surfaceSize: const Size(360, 600),
    );
    final cells = find.descendant(
      of: find.byType(ChoiceGrid),
      matching: find.byType(AnimatedContainer),
    );
    for (final cell in tester.widgetList<AnimatedContainer>(cells)) {
      expect(cell.duration, RegalosMotion.fade);
      expect(cell.curve, Curves.linear);
    }
    for (final text in tester.widgetList<AnimatedDefaultTextStyle>(
      find.descendant(
        of: find.byType(ChoiceGrid),
        matching: find.byType(AnimatedDefaultTextStyle),
      ),
    )) {
      expect(text.duration, RegalosMotion.fade);
    }
    await tester.tap(find.text('Envuelto'));
    await tester.pump();
    // Nada escala: el adorno solo se funde.
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.descendant(
        of: find.byType(ChoiceGrid),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
    await tester.pumpAndSettle();
    expect(chosen, GiftStatus.wrapped);
    expect(tester.takeException(), isNull);
  });
}
