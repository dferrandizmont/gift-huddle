import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/widgets/filter_pill.dart';
import 'package:regalos/features/family/application/reparto_view_provider.dart';
import 'package:regalos/features/family/presentation/family_screen.dart';
import 'package:regalos/features/family/presentation/reparto_flight.dart';
import 'package:regalos/features/family/presentation/reparto_grid.dart';
import 'package:regalos/features/family/presentation/reparto_occasion_view.dart';
import 'package:regalos/features/family/presentation/reparto_sheet.dart';

import '../helpers/screens.dart';
import 'family_grid_test.dart' show openFamily;
import 'family_grid_tablet_test.dart' show addGivers, anchorOf, cellOf, kRail;

// Tanda W2b del escritorio (la guía de diseño de escritorio, §2.2): la
// rejilla de Reparto crece con el ancho, la entrada de la cuadrícula en onda
// (al abrir, al cambiar el filtro y al volver de la lista) y el filtro que
// acompaña al cambio de vista.
void main() {
  const desktop = Size(1536, 864);
  const huge = Size(2560, 1440);
  const phoneSize = Size(390, 844);

  const people = ['aritz', 'nora', 'leo'];

  /// La tarjeta (con su plegado) de la persona [id] en la lista por ocasión.
  Finder card(String id) => find.byKey(ValueKey<String>('fold:$id'));

  /// La opacidad más baja de las que envuelven [finder].
  double lowestOpacityOf(WidgetTester tester, Finder finder) {
    var lowest = 1.0;
    for (final o in tester.widgetList<Opacity>(
      find.ancestor(of: finder, matching: find.byType(Opacity)),
    )) {
      if (o.opacity < lowest) {
        lowest = o.opacity;
      }
    }
    return lowest;
  }

  bool selected(WidgetTester tester, String label) => tester
      .widget<FilterPill>(
        find.descendant(
          of: find.byKey(kOccasionChipsKey),
          matching: find.widgetWithText(FilterPill, label),
        ),
      )
      .selected;

  Future<void> pickChip(WidgetTester tester, String label) async {
    final chip = find.descendant(
      of: find.byKey(kOccasionChipsKey),
      matching: find.widgetWithText(FilterPill, label),
    );
    await tester.ensureVisible(chip);
    await tester.pump();
    await tester.tap(chip);
    await settle(tester);
  }

  Future<void> toOccasion(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('Por ocasión'));
    await settle(tester);
  }

  Future<void> toGrid(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('Rejilla'));
    await settle(tester);
  }

  group('la rejilla crece con el ancho', () {
    const givers = ['us', 'yayos', 'avis', 'marta', 'pere', 'anna'];

    /// Las celdas de Aritz de [ids], de izquierda a derecha.
    List<Rect> row(WidgetTester tester, Iterable<String> ids) =>
        [for (final id in ids) tester.getRect(cellOf('aritz', id))]
          ..sort((a, b) => a.left.compareTo(b.left));

    screenTest(
      'a 1536 las celdas miden 190 × 78,4 y los nombres 210, y la rejilla llena la columna',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await openFamily(tester);
        expect(tester.takeException(), isNull);
        final cells = row(tester, givers);
        for (final cell in cells) {
          expect(cell.width, closeTo(190, 0.01));
          expect(cell.height, closeTo(78.4, 0.01));
        }
        final avatar = tester.getRect(anchorOf(repartoAvatarAnchor('aritz')));
        // Las celdas llenan la columna de 1400 (1368 sin márgenes): los nombres
        // son lo que queda; la celda va centrada en su hueco.
        expect(
          cells.first.left - avatar.left,
          closeTo(1368 - 6 * 193 + 1.5, 0.01),
        );
        expect(cells.last.right - avatar.left, closeTo(1368 - 1.5, 0.01));
        expect(tester.takeException(), isNull);
      },
      size: desktop,
    );

    screenTest(
      'a 2560 las celdas son mayores de 96 y la rejilla queda centrada',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await openFamily(tester);
        expect(tester.takeException(), isNull);
        final cells = row(tester, givers);
        expect(cells.first.width, greaterThan(96));
        expect(cells.first.width, closeTo(190, 0.01));
        expect(cells.first.height, closeTo(78.4, 0.01));
        final avatar = tester.getRect(anchorOf(repartoAvatarAnchor('aritz')));
        // El bloque de 1400, centrado en el área de contenido (sin el raíl):
        // a la izquierda, 16 más lo que sobra a cada lado.
        expect(
          avatar.left - kRail,
          closeTo(16 + (huge.width - kRail - 1400) / 2, 1),
          reason: 'centrada',
        );
        expect(cells.last.right - avatar.left, lessThanOrEqualTo(1400));
      },
      size: huge,
    );

    screenTest('con doce que regalan la rejilla no pasa de 1400', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await addGivers(tester, phone, 6);
      await pumpRegalos(tester, phone);
      await openFamily(tester);
      expect(tester.takeException(), isNull);
      final cells = row(tester, [
        ...givers,
        for (var i = 0; i < 6; i++) 'more$i',
      ]);
      expect(cells, hasLength(12));
      final avatar = tester.getRect(anchorOf(repartoAvatarAnchor('aritz')));
      expect(cells.last.right - avatar.left, lessThanOrEqualTo(1400));
      expect(cells.last.right - avatar.left, greaterThan(1000));
      expect(avatar.left - kRail, closeTo(huge.width - cells.last.right, 3));
      expect(tester.takeException(), isNull);
    }, size: huge);

    screenTest('a 390 las medidas son las de siempre', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openFamily(tester);
      expect(tester.takeException(), isNull);
      // Seis columnas en un móvil: modo compacto, hasta 44 de ancho y 44 de
      // alto, sin ninguna celda grande.
      for (final cell in row(tester, givers)) {
        expect(cell.width, lessThanOrEqualTo(44));
        expect(cell.height, 44);
      }
    }, size: phoneSize);

    test('RepartoLayout: sin desktop no cambia nada y con desktop no se pasa '
        'de 1400', () {
      RepartoLayout layout(double width, int n, {bool desktop = false}) =>
          RepartoLayout(
            width: width,
            columns: n,
            scaler: TextScaler.noScaling,
            wide: true,
            desktop: desktop,
          );
      // Una ventana media: 116 × 52 a 720 (el tope sube con el ancho de 96 a
      // 120), nombres 220.
      final medium = layout(720, 3);
      expect(medium.cellWidth, closeTo(116, 0.01));
      expect(medium.cellHeight, 52);
      expect(medium.leftWidth, 220);
      // Escritorio.
      final d = layout(1456, 6, desktop: true);
      expect(d.cellWidth, 190);
      expect(d.cellHeight, closeTo(78.4, 0.001));
      expect(d.leftWidth, closeTo(1368 - 6 * 193, 0.001));
      final huge = layout(2480, 6, desktop: true);
      expect(huge.cellWidth, 190);
      expect(huge.width, 2480);
      // La rejilla (nombres + celdas) cabe en 1400 y el bloque de 1400 está
      // centrado (la rejilla, a su izquierda).
      final used = huge.leftWidth + huge.slot * 6;
      expect(used, lessThanOrEqualTo(1400));
      expect(huge.pad, closeTo(16 + (2480 - 1400) / 2, 0.001));
      final many = layout(2480, 14, desktop: true);
      expect(
        many.leftWidth + many.slot * 14,
        lessThanOrEqualTo(RepartoLayout.desktopMaxWidth),
      );
    });

    screenTest('la lista por ocasión va en dos columnas a 1536 y en tres a '
        '2560', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openFamily(tester, all: false);
      await toOccasion(tester);
      expect(find.byType(RepartoOccasionView), findsOneWidget);
      final lefts = {for (final id in people) tester.getRect(card(id)).left};
      expect(lefts.length, 2);
      final widths = {for (final id in people) tester.getRect(card(id)).width};
      expect(widths.single, inInclusiveRange(360, 560));
    }, size: desktop);

    screenTest('a 2560 la lista por ocasión usa tres columnas de 360 a 560', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openFamily(tester, all: false);
      await toOccasion(tester);
      final rects = [for (final id in people) tester.getRect(card(id))];
      expect({for (final r in rects) r.left}.length, 3);
      for (final r in rects) {
        expect(r.width, inInclusiveRange(360, 560));
      }
      final spread = rects.last.right - rects.first.left;
      expect(spread, lessThanOrEqualTo(1400));
    }, size: huge);
  });

  group('la entrada de la cuadrícula', () {
    screenTest('al abrir, las celdas y los nombres entran en onda y se '
        'asientan', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.tap(find.text('Reparto').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      expect(find.byType(RepartoCellIntro), findsWidgets);
      final first = cellOf('aritz', 'us');
      final lastCell = cellOf('leo', 'anna');
      final leo = find.text('Leo');
      // A mitad de camino: la primera celda va por delante de la última
      // (onda en diagonal) y ni la última celda ni el nombre de una fila
      // posterior han llegado.
      expect(
        lowestOpacityOf(tester, first),
        greaterThan(lowestOpacityOf(tester, lastCell)),
      );
      expect(lowestOpacityOf(tester, lastCell), lessThan(1));
      expect(lowestOpacityOf(tester, leo), lessThan(1));
      final duringCell = tester.getTopLeft(lastCell).dy;
      final duringName = tester.getTopLeft(leo).dy;

      await settle(tester);
      expect(lowestOpacityOf(tester, first), 1);
      expect(lowestOpacityOf(tester, lastCell), 1);
      expect(lowestOpacityOf(tester, leo), 1);
      expect(duringCell, greaterThan(tester.getTopLeft(lastCell).dy));
      expect(duringName, greaterThan(tester.getTopLeft(leo).dy));
      expect(tester.takeException(), isNull);
    });

    screenTest('con «Reducir movimiento» solo se funde en 150 ms, sin '
        'desplazamiento', (tester, phone) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.tap(find.text('Reparto').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final lastCell = cellOf('leo', 'anna');
      expect(lowestOpacityOf(tester, lastCell), lessThan(1));
      final during = tester.getTopLeft(lastCell);
      await tester.pump(const Duration(milliseconds: 200));
      expect(lowestOpacityOf(tester, lastCell), 1);
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.getTopLeft(lastCell), during, reason: 'no se desplaza');
    });

    screenTest('cambiar el filtro vuelve a lanzar la entrada', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.tap(find.text('Reparto').last);
      await settle(tester);
      final lastCell = cellOf('leo', 'anna');
      expect(lowestOpacityOf(tester, lastCell), 1);

      final chip = find.descendant(
        of: find.byKey(kOccasionChipsKey),
        matching: find.widgetWithText(FilterPill, 'Reyes'),
      );
      await tester.ensureVisible(chip);
      await tester.pump();
      await tester.tap(chip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(lowestOpacityOf(tester, lastCell), lessThan(1));
      expect(lowestOpacityOf(tester, find.text('Leo')), lessThan(1));
      await settle(tester);
      expect(lowestOpacityOf(tester, lastCell), 1);
      expect(lowestOpacityOf(tester, find.text('Leo')), 1);
      expect(tester.takeException(), isNull);
    });

    screenTest('se puede tocar una celda mientras entra', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.tap(find.text('Reparto').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(lowestOpacityOf(tester, cellOf('aritz', 'us')), lessThan(1));
      await tester.tap(cellOf('aritz', 'us'), warnIfMissed: false);
      await settle(tester);
      expect(find.byKey(kRepartoSheetKey), findsOneWidget);
    });

    screenTest('no se repite al reconstruir sin motivo (datos que llegan)', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.tap(find.text('Reparto').last);
      await settle(tester);
      // Llega una persona que regala nueva, como de una sincronización.
      await addGivers(tester, phone, 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      for (final person in people) {
        for (final giver in ['us', 'yayos', 'anna']) {
          expect(
            lowestOpacityOf(tester, cellOf(person, giver)),
            1,
            reason: '$person/$giver',
          );
        }
      }
      expect(lowestOpacityOf(tester, find.text('Leo')), 1);
      await settle(tester);
    });
  });

  group('el filtro al cambiar de vista', () {
    screenTest('entrando en la lista por primera vez sale la ocasión más '
        'cercana y, sin tocar nada, la cuadrícula enseña «Todas»', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await phone.prefs!.setString(RepartoViewNotifier.prefsKey, 'occasion');
      await pumpRegalos(tester, phone);
      await tester.tap(find.text('Reparto').last);
      await settle(tester);
      expect(find.byType(RepartoOccasionView), findsOneWidget);
      expect(find.text('24 de diciembre'), findsWidgets);

      await toGrid(tester);
      expect(selected(tester, 'Todas'), isTrue);
      expect(find.text('Todas las ocasiones'), findsOneWidget);
    });

    screenTest('una pestaña elegida a mano en la lista filtra la cuadrícula', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await phone.prefs!.setString(RepartoViewNotifier.prefsKey, 'occasion');
      await pumpRegalos(tester, phone);
      await tester.tap(find.text('Reparto').last);
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byKey(kRepartoOccasionTabsKey),
          matching: find.text('Reyes'),
        ),
      );
      await settle(tester);
      expect(find.text('6 de enero'), findsWidgets);

      await toGrid(tester);
      expect(selected(tester, 'Reyes'), isTrue);
      expect(selected(tester, 'Todas'), isFalse);
    });

    screenTest('un filtro elegido a mano en la cuadrícula se conserva en los '
        'dos sentidos', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.tap(find.text('Reparto').last);
      await settle(tester);
      await pickChip(tester, 'Reyes');

      await toOccasion(tester);
      expect(find.text('6 de enero'), findsWidgets);
      await toGrid(tester);
      expect(selected(tester, 'Reyes'), isTrue);

      // Y otra vez: ir y volver sin tocar nada no lo mueve.
      await toOccasion(tester);
      await toGrid(tester);
      expect(selected(tester, 'Reyes'), isTrue);

      // Volver a «Todas» a mano también se respeta al ir y volver.
      await pickChip(tester, 'Todas');
      await toOccasion(tester);
      await toGrid(tester);
      expect(selected(tester, 'Todas'), isTrue);
    });
  });
}
