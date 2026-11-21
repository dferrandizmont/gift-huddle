import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/layout/pane_selection.dart';
import 'package:regalos/core/layout/two_pane.dart';
import 'package:regalos/core/theme/occasion_theme.dart';
import 'package:regalos/core/theme/regalos_tokens.dart';
import 'package:regalos/core/widgets/desktop_add_gift_button.dart';
import 'package:regalos/core/widgets/screen_header.dart';
import 'package:regalos/features/occasions/application/occasion_rows.dart';
import 'package:regalos/features/family/presentation/family_screen.dart';
import 'package:regalos/features/family/presentation/reparto_flight.dart';
import 'package:regalos/features/gifts/presentation/gift_editor_screen.dart';
import 'package:regalos/features/occasions/presentation/budget_screen.dart';
import 'package:regalos/features/occasions/presentation/occasion_detail_screen.dart';
import 'package:regalos/features/occasions/presentation/occasion_garland.dart';
import 'package:regalos/features/occasions/presentation/occasions_screen.dart';

import '../helpers/screens.dart';
import '../screens/family_grid_tablet_test.dart' show anchorOf, cellOf, kRail;
import '../screens/family_grid_test.dart' show openFamily;

// Tanda 2c de la web de escritorio (la guía de diseño de escritorio,
// §2 y §4.5): Ocasiones con filas planas y el pastel de la ocasión, cuatro
// casillas en fila y «Añadir regalo» en la cabecera; la guirnalda sin capas
// fuera de pantalla; y Reparto con la cabecera alineada con la rejilla.

const _desktop = Size(1280, 800);
const _huge = Size(2560, 1300);

Future<void> _openOccasions(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.bySemanticsLabel('Navegación principal'),
      matching: find.text('Ocasiones'),
    ),
  );
  await settle(tester);
  expect(find.byType(OccasionsScreen), findsOneWidget);
}

/// La fila de [title] en el panel de lista.
Finder _row(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(InkWell)).first;

SelectionScope _scope(WidgetTester tester) =>
    tester.widget<SelectionScope>(find.byType(SelectionScope));

/// Un `Canvas` que apunta lo que se le pide.
class _RecordingCanvas implements ui.Canvas {
  final List<Invocation> calls = <Invocation>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    return null;
  }

  Iterable<Invocation> named(Symbol name) =>
      calls.where((c) => c.memberName == name);
}

/// Pinta la guirnalda de [motif] en un lienzo que lo apunta todo.
_RecordingCanvas _paintGarland(WidgetTester tester, {Animation<double>? draw}) {
  final garland = OccasionGarland(
    motif: GarlandMotif.kings,
    color: const Color(0xFF336699),
    background: const Color(0xFFFFFFFF),
    draw: draw,
  );
  final box =
      (garland.build(
            tester.element(find.byType(Scaffold).first),
          ) as ExcludeSemantics).child!
          as SizedBox;
  final custom = box.child! as CustomPaint;
  final canvas = _RecordingCanvas();
  custom.painter!.paint(canvas, const Size(300, 28));
  return canvas;
}

void main() {
  group('Ocasiones a 1280 × 800', () {
    screenTest('la fila elegida lleva el pastel de su ocasión y Presupuesto, '
        'el del acento', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openOccasions(tester);
      final tio = (await familyState(
        tester,
        phone,
      )).view.occasions.firstWhere((o) => o.id == 'seed-tio');
      final palette = OccasionTheme.forOccasion(tio).palette;
      final scope = _scope(tester);
      expect(scope.selectedId, 'seed-tio');
      expect(scope.fill, palette.pastel);
      expect(scope.border, palette.tinta);

      // «Presupuesto» no es una ocasión: el pastel y la tinta del acento.
      final t = RegalosTokens.of(tester.element(find.byType(SelectionScope)));
      await tester.tap(find.text('Presupuesto de la casa').first);
      await settle(tester);
      expect(_scope(tester).selectedId, kBudgetRowId);
      expect(_scope(tester).fill, t.selection);
      expect(_scope(tester).border, t.ink);
      expect(tester.takeException(), isNull);
    }, size: _desktop);

    screenTest(
      'en oscuro, la tinta oscura de la ocasión',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openOccasions(tester);
        final tio = (await familyState(
          tester,
          phone,
        )).view.occasions.firstWhere((o) => o.id == 'seed-tio');
        final palette = OccasionTheme.forOccasion(tio).palette;
        // El 12 % de su tinta (como el ratón), más el borde de 1 px.
        expect(_scope(tester).fill, palette.tintaD.withValues(alpha: 0.12));
        expect(_scope(tester).border, palette.tintaD);
      },
      size: _desktop,
      brightness: Brightness.dark,
    );

    screenTest('las filas son planas y «Presupuesto» tiene el mismo inset de '
        '8 que ellas y que Personas y Ajustes', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openOccasions(tester);
      final list = tester.getRect(find.byType(OccasionsScreen));
      final budget = tester.getRect(_row('Presupuesto de la casa'));
      expect(budget.left, list.left + 8);
      expect(budget.right, list.right - 8);
      for (final title in ['Tió', 'Navidad', 'Reyes']) {
        final row = tester.getRect(_row(title));
        expect(row.left, list.left + 8, reason: title);
        expect(row.right, list.right - 8, reason: title);
        // Planas: de 60 a 80 (la misma que la de Personas), no las tarjetas de 165 de antes, y sin guirnalda
        // ni borde de tarjeta (la guirnalda se queda en el detalle).
        expect(row.height, inInclusiveRange(60, 80), reason: title);
      }
      expect(
        find.descendant(
          of: find.byType(OccasionsScreen),
          matching: find.byType(OccasionGarland),
        ),
        findsNothing,
      );
      // Sin flecha en «Presupuesto».
      expect(
        find.descendant(
          of: _row('Presupuesto de la casa'),
          matching: find.byType(Icon),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    }, size: _desktop);

    screenTest('«Añadir regalo» va en la cabecera del detalle y no hay «+» '
        'flotante', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openOccasions(tester);
      expect(find.byType(FloatingActionButton), findsNothing);
      final header = find.descendant(
        of: find.byType(OccasionDetailScreen),
        matching: find.byType(ScreenHeader),
      );
      final add = find.descendant(
        of: header,
        matching: find.widgetWithText(FilledButton, 'Añadir regalo'),
      );
      expect(add, findsOneWidget);
      // Junto a «Editar», a su izquierda y en la misma línea.
      final edit = tester.getRect(find.byTooltip('Editar ocasión'));
      final button = tester.getRect(add);
      expect(button.right, lessThanOrEqualTo(edit.left + 1));
      expect(button.center.dy, closeTo(edit.center.dy, 4));
      // Abre el editor con la ocasión puesta.
      await tester.tap(add);
      await settle(tester);
      expect(find.byType(GiftEditorScreen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(GiftEditorScreen),
          matching: find.text('Tió'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }, size: _desktop);

    screenTest('las cuatro casillas de resumen van en una fila que llena la '
        'columna', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openOccasions(tester);
      final tiles = [
        for (final k in ['ideas', 'decided', 'arrive', 'wrap'])
          tester.getRect(find.byKey(ValueKey<String>('tile-$k'))),
      ];
      final header = tester.getRect(
        find.descendant(
          of: find.byType(OccasionDetailScreen),
          matching: find.byType(ScreenHeader),
        ),
      );
      for (final tile in tiles) {
        expect(tile.top, tiles.first.top);
        expect(tile.width, closeTo(tiles.first.width, 0.01));
      }
      for (var i = 1; i < tiles.length; i++) {
        expect(tiles[i].left - tiles[i - 1].right, closeTo(10, 0.01));
      }
      // Sin huecos: de lado a lado de la columna, con su margen de 16.
      expect(tiles.first.left, closeTo(header.left + 16, 0.01));
      expect(tiles.last.right, closeTo(header.right - 16, 0.01));
      expect(find.text('por envolver'), findsOneWidget);
      expect(find.text('por llegar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, size: _desktop);

    screenTest('una ocasión sin regalos: el bloque arriba y a la izquierda, '
        'sin ceros ni secciones vacías', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openOccasions(tester);
      final state = await familyState(tester, phone);
      final used = {for (final g in state.view.gifts) g.occasionId};
      final empty = state.view.occasions.firstWhere(
        (o) => !used.contains(o.id),
      );
      phone.container.read(routerProvider).go('/occasions/${empty.id}');
      await settle(tester);
      final text = find.text('Todavía no hay regalos para esta ocasión.');
      expect(text, findsOneWidget);
      final header = tester.getRect(
        find.descendant(
          of: find.byType(OccasionDetailScreen),
          matching: find.byType(ScreenHeader),
        ),
      );
      final rect = tester.getRect(text);
      // A la izquierda, en el margen de la columna.
      expect(rect.left, closeTo(header.left + 16, 0.01));
      expect(rect.top, lessThan(header.bottom + 200));
      // Su botón, y nada de casillas con ceros ni de «Cada persona».
      // El de la cabecera y el del bloque: el mismo botón.
      expect(
        find.widgetWithText(DesktopAddGiftButton, 'Añadir regalo'),
        findsNWidgets(2),
      );
      expect(find.byKey(const ValueKey<String>('tile-wrap')), findsNothing);
      expect(find.text('Por persona'), findsNothing);
      expect(tester.takeException(), isNull);
    }, size: _desktop);
  });

  group('Ocasiones a 2560 × 1300', () {
    screenTest('el detalle va en su columna y las casillas la llenan', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openOccasions(tester);
      final pane = tester.getRect(find.byType(OccasionDetailScreen));
      final detail = find.byType(OccasionDetailScreen);
      final column = detailColumnWidth(
        tester.element(
          find.descendant(of: detail, matching: find.byType(ScreenHeader)),
        ),
      );
      expect(column, greaterThanOrEqualTo(880));
      final header = tester.getRect(
        find.descendant(of: detail, matching: find.byType(ScreenHeader)),
      );
      expect(header.width, closeTo(column, 0.01));
      expect(header.center.dx, closeTo(pane.center.dx, 0.01));
      final first = tester.getRect(find.byKey(const ValueKey('tile-ideas')));
      final last = tester.getRect(find.byKey(const ValueKey('tile-wrap')));
      expect(first.left, closeTo(header.left + 16, 0.01));
      expect(last.right, closeTo(header.right - 16, 0.01));
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(tester.takeException(), isNull);
    }, size: _huge);

    screenTest('Presupuesto: «Por persona» y «Por ocasión» una al lado de la '
        'otra', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openOccasions(tester);
      await tester.tap(find.text('Presupuesto de la casa').first);
      await settle(tester);
      expect(find.byType(BudgetScreen), findsOneWidget);
      final person = tester.getRect(find.text('Por persona'));
      final occasion = tester.getRect(find.text('Por ocasión'));
      expect(occasion.top, closeTo(person.top, 0.01));
      expect(occasion.left, greaterThan(person.right));
      expect(tester.takeException(), isNull);
    }, size: _huge);
  });

  group('sin cambios en el móvil', () {
    screenTest('el móvil: «+» flotante, filas de tarjeta y dos casillas', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openOccasions(tester);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      // La tarjeta de Reyes, con su guirnalda.
      expect(
        find.descendant(
          of: find.byType(OccasionsScreen),
          matching: find.byType(OccasionGarland),
        ),
        findsWidgets,
      );
      await tester.tap(_row('Reyes'));
      await settle(tester);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Añadir regalo'), findsNothing);
      expect(find.byKey(const ValueKey('tile-ideas')), findsNothing);
      expect(find.text('por envolver'), findsOneWidget);
      expect(find.text('por llegar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('la guirnalda no abre capas fuera de pantalla', () {
    screenTest('ni entera ni a medio dibujar', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      for (final draw in <Animation<double>?>[
        null,
        const AlwaysStoppedAnimation<double>(0.3),
        const AlwaysStoppedAnimation<double>(0.6),
        const AlwaysStoppedAnimation<double>(1),
      ]) {
        final canvas = _paintGarland(tester, draw: draw);
        expect(
          canvas.named(#saveLayer),
          isEmpty,
          reason: 'draw=${draw?.value}',
        );
        expect(canvas.named(#drawPath), isNotEmpty);
      }
    });

    screenTest('el alfa va en el color: línea y rombos al 50 %, iconos al '
        '62 %', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      final canvas = _paintGarland(tester);
      final paints = [
        for (final c in canvas.named(#drawPath))
          c.positionalArguments[1] as Paint,
      ];
      // Los rombos (un solo trazado) y tres iconos.
      expect(paints, hasLength(4));
      expect(paints.first.color.a, closeTo(0.5, 0.01));
      for (final icon in paints.skip(1)) {
        expect(icon.color.a, closeTo(0x9E / 255, 0.01));
      }
      final line =
          canvas.named(#drawLine).single.positionalArguments[2] as Paint;
      expect(line.shader, isNotNull);
    });

    screenTest('en pantalla, sin Opacity ni ShaderMask bajo la guirnalda', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openOccasions(tester);
      final garland = find.byType(OccasionGarland, skipOffstage: false);
      expect(garland, findsWidgets);
      for (final type in [Opacity, ShaderMask, BackdropFilter]) {
        expect(
          find.descendant(
            of: garland,
            matching: find.byType(type),
            skipOffstage: false,
          ),
          findsNothing,
          reason: '$type',
        );
      }
    }, size: _desktop);
  });

  group('Reparto: la cabecera va alineada con la rejilla', () {
    screenTest('a 2560, título, filtros y conmutador dentro de la columna de '
        'la rejilla', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openFamily(tester);
      expect(tester.takeException(), isNull);
      final avatar = tester.getRect(anchorOf(repartoAvatarAnchor('aritz')));
      final cells = [
        for (final id in ['us', 'yayos', 'avis', 'marta', 'pere', 'anna'])
          tester.getRect(cellOf('aritz', id)),
      ]..sort((a, b) => a.left.compareTo(b.left));
      final title = tester.getRect(
        find.descendant(
          of: find.byType(ScreenHeader),
          matching: find.text('Reparto'),
        ),
      );
      final toggle = tester.getRect(find.bySemanticsLabel('Rejilla'));
      final toggle2 = tester.getRect(find.bySemanticsLabel('Por ocasión'));
      final chips = tester.getRect(find.byKey(kOccasionChipsKey));
      final pills = tester.getRect(find.text('Todas'));
      // El título empieza donde empieza la rejilla (el avatar de la primera
      // fila) y el conmutador acaba donde acaba la última celda.
      expect(title.left, closeTo(avatar.left, 3));
      expect(
        [toggle.right, toggle2.right].reduce((a, b) => a > b ? a : b),
        closeTo(cells.last.right, 12),
      );
      // Los filtros, a la izquierda de la rejilla y no centrados.
      expect(pills.left, closeTo(avatar.left + 16, 20));
      expect(chips.width, greaterThan(0));
      // Nada de título pegado al raíl con la rejilla en el centro.
      expect(title.left - kRail, greaterThan(300));
      expect(tester.takeException(), isNull);
    }, size: _huge);

    screenTest('a 1280 sigue ocupando lo que da la rejilla', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openFamily(tester);
      final avatar = tester.getRect(anchorOf(repartoAvatarAnchor('aritz')));
      final title = tester.getRect(
        find.descendant(
          of: find.byType(ScreenHeader),
          matching: find.text('Reparto'),
        ),
      );
      expect(title.left, closeTo(avatar.left, 3));
      expect(tester.takeException(), isNull);
    }, size: _desktop);

    screenTest('en el móvil, la cabecera como siempre', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openFamily(tester);
      final title = tester.getRect(
        find.descendant(
          of: find.byType(ScreenHeader),
          matching: find.text('Reparto'),
        ),
      );
      expect(title.left, 16);
      expect(tester.takeException(), isNull);
    });
  });
}
