import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/widgets/filter_pill.dart';
import 'package:regalos/features/family/application/reparto_view_provider.dart';
import 'package:regalos/features/family/presentation/family_screen.dart';
import 'package:regalos/features/family/presentation/reparto_flight.dart';
import 'package:regalos/features/family/presentation/reparto_grid.dart';
import 'package:regalos/features/family/presentation/reparto_occasion_view.dart';
import 'package:regalos/features/family/presentation/reparto_outside.dart';
import 'package:regalos/features/family/presentation/reparto_view_toggle.dart';

import '../helpers/screens.dart';
import 'family_grid_test.dart' show expectNoRoundShapes, openFamily;

/// Las dos vistas de Reparto: la rejilla (B) y la lista por ocasión (C), el
/// conmutador, el vuelo de los regalos entre ellas y «Reducir movimiento».
void main() {
  const tall = Size(390, 1500);

  Future<void> toOccasion(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('Por ocasión'));
    await settle(tester);
  }

  Future<void> toGrid(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('Rejilla'));
    await settle(tester);
  }

  bool chipSelected(WidgetTester tester, String label) => tester
      .widget<FilterPill>(
        find.descendant(
          of: find.byKey(kOccasionChipsKey),
          matching: find.widgetWithText(FilterPill, label),
        ),
      )
      .selected;

  screenTest(
    'el conmutador alterna la rejilla y la lista por ocasión y recuerda la '
    'elección',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openFamily(tester, all: false);
      expect(find.byKey(kRepartoViewToggleKey), findsOneWidget);
      expect(find.byType(RepartoGrid), findsOneWidget);
      expect(find.byType(RepartoOccasionView), findsNothing);

      await toOccasion(tester);
      expect(find.byType(RepartoOccasionView), findsOneWidget);
      expect(find.byType(RepartoGrid), findsNothing);
      expect(phone.prefs!.getString(RepartoViewNotifier.prefsKey), 'occasion');
      // La franja de la ocasión más cercana: el Tió, con su cuenta atrás.
      expect(find.text('24 de diciembre'), findsOneWidget);
      expect(find.text('Faltan 45 días'), findsOneWidget);
      // Las personas sin regalos ese día lo dicen y dejan añadir.
      expect(find.text('Nada en Tió'), findsNWidgets(2));
      expect(find.text('Añadir'), findsNWidgets(2));
      expect(find.text('Cuántos paquetes abre cada uno'), findsOneWidget);

      await toGrid(tester);
      expect(find.byType(RepartoGrid), findsOneWidget);
      expect(phone.prefs!.getString(RepartoViewNotifier.prefsKey), 'grid');
    },
    size: tall,
  );

  screenTest('la vista recordada es la que abre al arrancar', (
    tester,
    phone,
  ) async {
    await phone.prefs!.setString(RepartoViewNotifier.prefsKey, 'occasion');
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openFamily(tester, all: false);
    expect(find.byType(RepartoOccasionView), findsOneWidget);
    expect(find.byType(RepartoGrid), findsNothing);
    expect(tester.takeException(), isNull);
  }, size: tall);

  screenTest('las pestañas de ocasión de la lista miden 56 de alto', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openFamily(tester, all: false);
    await toOccasion(tester);
    final tabs = tester.getRect(find.byKey(kRepartoOccasionTabsKey));
    expect(tabs.height, 56);
    // Cada pestaña llena el alto de la banda: es el área que se pulsa.
    final reyes = find.descendant(
      of: find.byKey(kRepartoOccasionTabsKey),
      matching: find.ancestor(
        of: find.text('Reyes'),
        matching: find.byType(GestureDetector),
      ),
    );
    expect(tester.getSize(reyes.first).height, 56);
    expect(tester.takeException(), isNull);
  }, size: tall);

  screenTest('la lista abre la ocasión filtrada y la rejilla vuelve con la '
      'que se estaba viendo', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openFamily(tester, all: false);
    final reyes = find.widgetWithText(FilterPill, 'Reyes');
    await tester.ensureVisible(reyes);
    await tester.pump();
    await tester.tap(reyes);
    await settle(tester);

    await toOccasion(tester);
    expect(find.text('6 de enero'), findsOneWidget);
    expect(find.text('24 de diciembre'), findsNothing);

    // Otra pestaña; al volver, la rejilla queda filtrada por esa.
    await tester.tap(
      find.descendant(
        of: find.byKey(kRepartoOccasionTabsKey),
        matching: find.text('Navidad'),
      ),
    );
    await settle(tester);
    expect(find.text('25 de diciembre'), findsOneWidget);
    await toGrid(tester);
    expect(chipSelected(tester, 'Navidad'), isTrue);
    expect(chipSelected(tester, 'Reyes'), isFalse);
  }, size: tall);

  screenTest('cambiar quién regala en la lista guarda el cambio', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openFamily(tester, all: false);
    await toOccasion(tester);
    expect(find.text('Libro de dinosaurios con solapas'), findsOneWidget);

    await tester.tap(
      find.bySemanticsLabel(RegExp('^Quién regala: Tía Marta y Jordi')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // La fila de chips se despliega en línea, con todas las opciones.
    expect(find.text('Yayos de Terrassa'), findsOneWidget);
    expect(find.text('Nadie'), findsOneWidget);
    await tester.tap(find.text('Yayos de Terrassa'));
    // El chip cambia de forma, la fila se pliega y entonces se guarda.
    await settle(tester);
    await settle(tester);

    final state = await familyState(tester, phone);
    final yayos = state.view.givers.firstWhere(
      (g) => g.name == 'Yayos de Terrassa',
    );
    expect(
      state.view.gifts
          .firstWhere((g) => g.title.startsWith('Libro de dinosaurios'))
          .giverId,
      yayos.id,
    );
    expect(find.text('Yayos de Terrassa'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, size: tall);

  screenTest(
    'Por ocasión omite el regalo del alias archivado en tarjeta y total',
    (tester, phone) async {
      await seedSample(tester, phone);
      await tester.runAsync(() async {
        final controller = familyOf(phone);
        await controller.linkGiver('us', 'leo');
        await controller.linkGiver('marta', 'leo');
        await controller.archiveGiver('marta');
      });
      await pumpRegalos(tester, phone);
      await openFamily(tester, all: false);
      await toOccasion(tester);
      expect(find.text('Pijama de astronautas, talla 8'), findsOneWidget);
      expect(find.text('Libro de dinosaurios con solapas'), findsNothing);
      expect(find.text('1 regalo'), findsWidgets);
      expect(find.text('2 regalos'), findsNothing);
    },
    size: tall,
  );

  screenTest('los regalos vuelan de su celda a su fila y no se admite otro '
      'cambio mientras viajan', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openFamily(tester, all: false);
    const title = 'Pijama de astronautas, talla 8';
    expect(find.text(title), findsNothing);

    await tester.tap(find.bySemanticsLabel('Por ocasión'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 300));
    // A mitad del vuelo: su fila (aún oculta) y el trozo que viaja.
    expect(find.text(title), findsNWidgets(2));
    // Un toque al conmutador a mitad de vuelo no cambia nada.
    await tester.tap(find.bySemanticsLabel('Rejilla'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(RepartoOccasionView), findsOneWidget);

    await settle(tester);
    expect(find.text(title), findsOneWidget);
    expect(find.byType(RepartoGrid), findsNothing);
    expect(tester.takeException(), isNull);

    // Y de vuelta, la celda recibe sus regalos (la rejilla sigue en «Todas»:
    // nadie eligió ocasión).
    await toGrid(tester);
    expect(chipSelected(tester, 'Todas'), isTrue);
    expect(
      find.bySemanticsLabel(RegExp(r'^Nosotros para Aritz: \d regalos?')),
      findsOneWidget,
    );
    expect(find.text(title), findsNothing);
    expect(tester.takeException(), isNull);
  }, size: tall);

  screenTest('los nombres y avatares de quienes reciben también viajan de su '
      'fila a su tarjeta y de vuelta', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openFamily(tester, all: false);

    // En la rejilla, cada nombre sale una vez.
    final inGrid = find.text('Nora').evaluate().length;
    expect(inGrid, greaterThan(0));

    await tester.tap(find.bySemanticsLabel('Por ocasión'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 300));
    // A mitad del vuelo, el nombre que viaja se suma al de la tarjeta, que
    // sigue oculto hasta que aterriza.
    final flying = find.text('Nora').evaluate().length;
    final hidden = tester
        .widgetList<FadeTransition>(
          find.ancestor(
            of: find.text('Nora'),
            matching: find.byType(FadeTransition),
          ),
        )
        .where((f) => f.opacity.value == 0)
        .length;
    expect(hidden, 1, reason: 'el destino espera a que aterrice el nombre');
    await settle(tester);
    final settled = find.text('Nora').evaluate().length;
    expect(flying, settled + 1);
    expect(
      tester
          .widgetList<FadeTransition>(
            find.ancestor(
              of: find.text('Nora'),
              matching: find.byType(FadeTransition),
            ),
          )
          .where((f) => f.opacity.value == 0),
      isEmpty,
    );
    expect(tester.takeException(), isNull);

    // Y de vuelta, el nombre regresa a su fila.
    await tester.tap(find.bySemanticsLabel('Rejilla'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Nora').evaluate().length, inGrid + 1);
    await settle(tester);
    expect(find.text('Nora').evaluate().length, inGrid);
    expect(tester.takeException(), isNull);
  }, size: tall);

  group('con la rejilla en «Todas»', () {
    const title = 'Pijama de astronautas, talla 8';
    final flight = find.byKey(kRepartoFlightKey);
    // Las celdas con regalos de la rejilla.
    // Por su widget y no por el árbol de semántica, que se salta lo que aún
    // no se ve.
    final filledLabel = RegExp(r' para \S+: \d+ regalos?,');
    Finder filled() => find.byWidgetPredicate(
      (w) => w is Semantics && filledLabel.hasMatch(w.properties.label ?? ''),
    );

    /// La opacidad más baja de las que envuelven a [f].
    double lowestOpacity(WidgetTester tester, Finder f) {
      var lowest = 1.0;
      for (final o in tester.widgetList<Opacity>(
        find.ancestor(of: f, matching: find.byType(Opacity)),
      )) {
        if (o.opacity < lowest) {
          lowest = o.opacity;
        }
      }
      return lowest;
    }

    /// Si la celda [cell] espera oculta a que aterrice su regalo.
    bool awaitsFlight(WidgetTester tester, Finder cell) => tester
        .widgetList<FadeTransition>(
          find.descendant(of: cell, matching: find.byType(FadeTransition)),
        )
        .any((f) => f.opacity.value == 0);

    screenTest('de la rejilla a la lista vuelan regalos, nombres y avatares, '
        'y la rejilla que se va no se monta de nuevo ni repite su entrada', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openFamily(tester, all: false);
      expect(chipSelected(tester, 'Todas'), isTrue);
      final grid = tester.state(find.byType(RepartoGrid));

      await tester.tap(find.bySemanticsLabel('Por ocasión'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      // Los vuelos han salido: el regalo, el nombre y el avatar.
      expect(flight, findsOneWidget);
      expect(
        find.descendant(of: flight, matching: find.text(title)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: flight, matching: find.text('Nora')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: flight, matching: find.byType(RepartoAvatar)),
        findsWidgets,
      );
      // La rejilla que se va es la misma (no se ha montado otra) y sus
      // nombres siguen enteros: solo se funde con toda la vista.
      expect(tester.state(find.byType(RepartoGrid)), same(grid));
      final nameInGrid = find.descendant(
        of: find.byType(RepartoGrid),
        matching: find.text('Nora'),
      );
      expect(nameInGrid, findsOneWidget);
      expect(lowestOpacity(tester, nameInGrid), 1);
      // La fila de destino espera oculta a su regalo.
      final row = find.descendant(
        of: find.byType(RepartoOccasionView),
        matching: find.text(title),
      );
      expect(
        tester
            .widgetList<FadeTransition>(
              find.ancestor(of: row, matching: find.byType(FadeTransition)),
            )
            .where((f) => f.opacity.value == 0),
        isNotEmpty,
      );

      await settle(tester);
      expect(flight, findsNothing);
      expect(find.text(title), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, size: tall);

    screenTest('de la lista a la rejilla ninguna celda con regalos aparece '
        'quieta: las que reciben un vuelo esperan ocultas y las demás entran '
        'escalonadas', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openFamily(tester, all: false);
      final cells = filled().evaluate().length;
      expect(cells, greaterThan(2));
      await toOccasion(tester);
      final list = tester.state(find.byType(RepartoOccasionView));

      await tester.tap(find.bySemanticsLabel('Rejilla'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      // La rejilla sigue en «Todas» y los vuelos han salido.
      expect(chipSelected(tester, 'Todas'), isTrue);
      expect(flight, findsOneWidget);
      expect(
        find.descendant(of: flight, matching: find.text(title)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: flight, matching: find.text('Nora')),
        findsOneWidget,
      );
      // La lista que se va es la misma (conserva su sitio mientras se funde).
      expect(tester.state(find.byType(RepartoOccasionView)), same(list));

      // Cada celda con regalos, o espera a su vuelo, o está entrando.
      expect(filled().evaluate().length, cells);
      var waiting = 0;
      var entering = 0;
      for (var i = 0; i < cells; i++) {
        final cell = filled().at(i);
        if (awaitsFlight(tester, cell)) {
          waiting++;
        } else {
          expect(
            lowestOpacity(tester, cell),
            lessThan(1),
            reason: 'la celda $i aparece quieta',
          );
          entering++;
        }
      }
      expect(waiting, greaterThan(0));
      expect(entering, greaterThan(0));

      await settle(tester);
      expect(flight, findsNothing);
      for (var i = 0; i < cells; i++) {
        expect(awaitsFlight(tester, filled().at(i)), isFalse);
        expect(lowestOpacity(tester, filled().at(i)), 1);
      }
      expect(tester.takeException(), isNull);
    }, size: tall);
  });

  screenTest('la lista por ocasión acaba con «Fuera del reparto · N»: se '
      'despliega y «Volver a incluir» devuelve la tarjeta', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await tester.runAsync(
      () => familyOf(phone).setRecipientInReparto('leo', false),
    );
    await phone.prefs!.setString(RepartoViewNotifier.prefsKey, 'occasion');
    await pumpRegalos(tester, phone);
    await openFamily(tester, all: false);
    expect(find.byType(RepartoOccasionView), findsOneWidget);

    // Sin tarjeta de Leo y con el bloque plegado al final.
    expect(find.bySemanticsLabel('Abrir la ficha de Leo'), findsNothing);
    final toggle = find.byKey(kRepartoOutsideToggleKey);
    await tester.ensureVisible(toggle);
    await tester.pump();
    expect(find.text('Fuera del reparto · 1'), findsOneWidget);
    expect(find.byKey(repartoIncludeKey('leo')), findsNothing);

    await tester.tap(toggle);
    await settle(tester);
    expect(find.text('Volver a incluir'), findsOneWidget);
    expectNoRoundShapes(tester, find.byType(OutsideBlock));

    await tester.tap(find.byKey(repartoIncludeKey('leo')));
    await settle(tester);
    expect(find.byKey(kRepartoOutsideToggleKey), findsNothing);
    expect(find.bySemanticsLabel('Abrir la ficha de Leo'), findsWidgets);
    expect(tester.takeException(), isNull);

    // Y si sale de nuevo, su tarjeta se pliega y pasa al bloque.
    await driveAsync(
      tester,
      () => familyOf(phone).setRecipientInReparto('leo', false),
    );
    await settle(tester);
    expect(find.bySemanticsLabel('Abrir la ficha de Leo'), findsNothing);
    expect(find.text('Fuera del reparto · 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, size: tall);

  screenTest('con «Reducir movimiento» no vuela nada: las vistas se funden en '
      '150 ms', (tester, phone) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openFamily(tester, all: false);

    await tester.tap(find.bySemanticsLabel('Por ocasión'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    // La fila ya está ahí y solo hay una (no hay trozo que vuele).
    expect(find.text('Pijama de astronautas, talla 8'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 160));
    expect(find.byType(RepartoGrid), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);

    await tester.tap(find.bySemanticsLabel('Rejilla'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 160));
    expect(find.byType(RepartoOccasionView), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  }, size: tall);

  screenTest('nada es una píldora ni una elipse en la lista ni en el '
      'conmutador', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openFamily(tester, all: false);
    await toOccasion(tester);
    expectNoRoundShapes(tester, find.byType(RepartoOccasionView));
    expectNoRoundShapes(tester, find.byKey(kRepartoViewToggleKey));
    // Con la fila de chips desplegada también.
    await tester.tap(
      find.bySemanticsLabel(RegExp('^Quién regala: Tía Marta y Jordi')),
    );
    await settle(tester);
    expectNoRoundShapes(tester, find.byType(RepartoOccasionView));
  }, size: tall);

  group('celdas de la rejilla', () {
    test('con 3 o 4 columnas no pasan de 68 × 48, aunque la pantalla sea '
        'ancha', () {
      for (final width in [360.0, 390.0, 600.0, 900.0]) {
        for (final columns in [1, 2, 3, 4]) {
          final layout = RepartoLayout(
            width: width,
            columns: columns,
            scaler: TextScaler.noScaling,
          );
          expect(layout.cellWidth, lessThanOrEqualTo(68), reason: '$width');
          expect(layout.cellHeight, lessThanOrEqualTo(48), reason: '$width');
          expect(layout.compact, isFalse);
        }
      }
    });

    test('con cinco o seis columnas el modo compacto no pasa de 44 × 44', () {
      for (final columns in [5, 6]) {
        final layout = RepartoLayout(
          width: 390,
          columns: columns,
          scaler: TextScaler.noScaling,
        );
        expect(layout.compact, isTrue);
        expect(layout.cellWidth, lessThanOrEqualTo(44));
        expect(layout.cellHeight, lessThanOrEqualTo(44));
      }
    });
  });
}
