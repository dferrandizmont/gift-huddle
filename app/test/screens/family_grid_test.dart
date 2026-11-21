import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/widgets/picker_field.dart';
import 'package:regalos/features/family/presentation/family_screen.dart';
import 'package:regalos/features/family/presentation/reparto_grid.dart';
import 'package:regalos/features/family/presentation/reparto_sheet.dart';
import 'package:regalos/features/people/presentation/people_screen.dart';

import '../helpers/screens.dart';

/// El desplazamiento horizontal de la rejilla (no el de los chips de ocasión).
bool _isHorizontalScroll(Widget w) =>
    w is SingleChildScrollView &&
    w.scrollDirection == Axis.horizontal &&
    w.key != kOccasionChipsKey;

/// Abre Reparto. Por defecto enseña la ocasión más cercana; con [all] pasa a
/// «Todas», que es lo que miran casi todas estas pruebas.
Future<void> openFamily(WidgetTester tester, {bool all = true}) async {
  await tester.tap(find.text('Reparto').last);
  await settle(tester);
  if (all && find.text('Todas').evaluate().isNotEmpty) {
    await tester.tap(find.text('Todas'));
    await settle(tester);
  }
}

/// Que nada de lo que hay bajo [root] sea una píldora, una elipse ni tenga
/// un radio mayor de 8. Los círculos solo valen como puntos de color (10 px
/// como mucho).
void expectNoRoundShapes(WidgetTester tester, Finder root) {
  const max = 8.0;
  void radius(BorderRadiusGeometry? r, String what) {
    if (r is BorderRadius) {
      for (final c in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
        expect(c.x, lessThanOrEqualTo(max), reason: what);
        expect(c.y, lessThanOrEqualTo(max), reason: what);
      }
    }
  }

  for (final w in tester.widgetList<DecoratedBox>(
    find.descendant(of: root, matching: find.byType(DecoratedBox)),
  )) {
    final d = w.decoration;
    if (d is! BoxDecoration) {
      continue;
    }
    radius(d.borderRadius, 'DecoratedBox $d');
    if (d.shape == BoxShape.circle) {
      final size = tester.getSize(find.byWidget(w));
      expect(
        size.width,
        size.height,
        reason: 'un punto es un círculo, no una elipse',
      );
      expect(size.width, lessThanOrEqualTo(10), reason: 'solo puntos de color');
    }
  }
  for (final w in tester.widgetList<ClipRRect>(
    find.descendant(of: root, matching: find.byType(ClipRRect)),
  )) {
    radius(w.borderRadius, 'ClipRRect');
  }
  for (final w in tester.widgetList<Material>(
    find.descendant(of: root, matching: find.byType(Material)),
  )) {
    final s = w.shape;
    if (s is RoundedRectangleBorder) {
      radius(s.borderRadius, 'Material');
    }
    expect(s is StadiumBorder || s is CircleBorder, isFalse);
  }
  for (final a in tester.widgetList<RepartoAvatar>(
    find.descendant(of: root, matching: find.byType(RepartoAvatar)),
  )) {
    final size = tester.getSize(find.byWidget(a));
    expect(size.width, size.height, reason: 'avatar cuadrado de tamaño fijo');
  }
}

/// Un control de la hoja por su etiqueta (la rejilla de detrás repite los
/// nombres).
Finder _inSheet(String label) => find.descendant(
  of: find.byKey(kRepartoSheetKey),
  matching: find.bySemanticsLabel(label),
);

void main() {
  void checkGrid(WidgetTester tester) {
    expect(tester.takeException(), isNull);
    // Tres personas en filas y seis regaladores en columnas.
    for (final name in ['Aritz', 'Nora', 'Leo']) {
      expect(find.text(name), findsOneWidget);
    }
    for (final name in [
      'Nosotros',
      'Yayos de Terrassa',
      'Avis de Girona',
      'Tía Marta y Jordi',
      'Tío Pere',
      'Padrina Anna',
    ]) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    // Los regalos sin quién regala no tienen columna.
    expect(find.text('Sin asignar'), findsNothing);
    // Sin desplazamiento horizontal.
    expect(find.byWidgetPredicate(_isHorizontalScroll), findsNothing);
    // Nada se sale por la derecha de los 390 px.
    for (final name in ['Aritz', 'Nora', 'Leo']) {
      expect(tester.getTopRight(find.text(name)).dx, lessThanOrEqualTo(390));
    }
    final cells = find.bySemanticsLabel(RegExp(r' para (Aritz|Nora|Leo): '));
    expect(cells, findsNWidgets(18));
    for (final e in cells.evaluate()) {
      final r = tester.getRect(find.byElementPredicate((x) => x == e));
      expect(r.right, lessThanOrEqualTo(390 - 16 + 0.5));
      expect(r.left, greaterThanOrEqualTo(0));
    }
  }

  screenTest('la rejilla cabe a 390 px con tres personas y seis regaladores', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openFamily(tester);
    checkGrid(tester);

    // Número, importe y estado en la celda; la vacía se marca.
    expect(
      find.bySemanticsLabel(
        eur(
          'Nosotros para Aritz: 2 regalos, 73,99 €, todo comprado, para Tió, Reyes',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        eur(
          'Yayos de Terrassa para Aritz: 1 regalo, 180 €, algo pendiente, para Reyes',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Padrina Anna para Aritz: nada todavía, añadir regalo',
      ),
      findsOneWidget,
    );
    // El regalo sin quién regala de Aritz no es una celda: sale bajo su nombre.
    expect(find.bySemanticsLabel(RegExp('Sin asignar para')), findsNothing);
    expect(find.bySemanticsLabel('1 sin asignar'), findsOneWidget);

    // Banner y celdas del posible duplicado.
    expect(
      find.textContaining('Posible duplicado: «Puzle de 48 piezas» para Nora'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        RegExp('Avis de Girona para Nora: .*posible duplicado'),
      ),
      findsOneWidget,
    );

    // La leyenda: tres estados.
    expect(find.text('Nada'), findsOneWidget);
    expect(find.text('Por comprar'), findsOneWidget);
    expect(find.text('Todo comprado'), findsOneWidget);
    expect(find.text('Algo pendiente'), findsNothing);
    // Y la fila de totales: «Total» y cuántos regalos trae cada quien.
    expect(find.text('Total'), findsOneWidget);
    expect(find.bySemanticsLabel('Nosotros: 4 regalos'), findsOneWidget);
    expect(find.bySemanticsLabel('Tío Pere: 1 regalo'), findsOneWidget);
  }, size: const Size(390, 1500));

  screenTest('dos alias de Nora abren una sola celda con todos sus regalos', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await tester.runAsync(() async {
      final c = familyOf(phone);
      await c.linkGiver('us', 'nora');
      await c.linkGiver('marta', 'nora');
    });
    await pumpRegalos(tester, phone);
    await openFamily(tester, all: false);
    await tester.tap(find.text('Todas'));
    await settle(tester);

    final cell = find.bySemanticsLabel(RegExp(r'^Nora para Aritz: 3 regalos'));
    expect(cell, findsOneWidget);
    await tester.tap(cell);
    await settle(tester);
    final sheet = find.byKey(kRepartoSheetKey);
    for (final title in [
      'Pijama de astronautas, talla 8',
      'Libro de dinosaurios con solapas',
      'Estación de bomberos de bloques',
    ]) {
      expect(
        find.descendant(of: sheet, matching: find.text(title)),
        findsOneWidget,
      );
    }
  }, size: const Size(390, 1500));

  screenTest(
    'la rejilla no se rompe con el texto al 130 %',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openFamily(tester);
      checkGrid(tester);
    },
    size: const Size(390, 1900),
    textScale: 1.3,
  );

  screenTest('nada es una píldora, una elipse ni pasa de radio 8', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openFamily(tester);
    expectNoRoundShapes(tester, find.byType(CustomScrollView));
    expect(find.byType(RepartoAvatar), findsNWidgets(3));
    for (final a in tester.widgetList(find.byType(RepartoAvatar))) {
      expect(tester.getSize(find.byWidget(a)), const Size(22, 22));
    }

    await tester.tap(
      find.bySemanticsLabel(RegExp('^Nosotros para Aritz: 2 regalos')),
    );
    await settle(tester);
    expectNoRoundShapes(tester, find.byKey(kRepartoSheetKey));
    await tester.tap(
      find.bySemanticsLabel(RegExp('^Quién regala: Nosotros')).first,
    );
    await settle(tester);
    expectNoRoundShapes(tester, find.byKey(kRepartoSheetKey));
  }, size: const Size(390, 1500));

  screenTest('con seis personas que reciben sigue sin desplazarse a lo ancho', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone, extraPeople: 3);
    await pumpRegalos(tester, phone);
    await openFamily(tester);
    expect(tester.takeException(), isNull);
    expect(find.byWidgetPredicate(_isHorizontalScroll), findsNothing);
    expect(find.text('Extra 3'), findsOneWidget);
  }, size: const Size(390, 1500));

  screenTest(
    'con muchas personas solo se desplaza en vertical y la cabecera queda fija',
    (tester, phone) async {
      await seedSample(tester, phone, extraPeople: 10);
      await tester.runAsync(() async {
        for (var i = 0; i < 6; i++) {
          await familyOf(phone).upsertGiver(
            Giver(
              id: 'more$i',
              name: 'Más $i',
              colorIndex: i,
              householdPays: false,
              archived: false,
            ),
          );
        }
      });
      await pumpRegalos(tester, phone);
      await openFamily(tester);
      expect(tester.takeException(), isNull);
      // Doce columnas: nada se desborda ni se desplaza en horizontal.
      expect(find.byWidgetPredicate(_isHorizontalScroll), findsNothing);
      // Con tantas columnas, la cabecera lleva solo la inicial (y el nombre
      // completo en la ayuda).
      final header = find.byTooltip('Nosotros');
      final before = tester.getTopLeft(header);
      expect(before.dx, lessThan(390));
      final top = tester.getTopLeft(find.byType(CustomScrollView)).dy;
      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(scrollable.position.axis, Axis.vertical);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pump();
      // La rejilla ha subido, pero la cabecera se ha quedado pegada arriba
      // del todo (88 px de alto) y no se ha movido a los lados.
      expect(scrollable.position.pixels, greaterThan(300));
      final after = tester.getTopLeft(header);
      expect(after.dx, before.dx);
      expect(after.dy - top, lessThan(88));
      expect(tester.takeException(), isNull);
    },
    size: const Size(390, 700),
  );

  screenTest('tocar una celda con regalos abre una hoja con esos regalos', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openFamily(tester);
    await tester.tap(
      find.bySemanticsLabel(RegExp('^Nosotros para Aritz: 2 regalos')),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
    final sheet = find.byKey(kRepartoSheetKey);
    expect(sheet, findsOneWidget);
    for (final text in [
      'Pijama de astronautas, talla 8',
      'Estación de bomberos de bloques',
    ]) {
      expect(
        find.descendant(of: sheet, matching: find.text(text)),
        findsOneWidget,
      );
    }
    expect(find.text('Patinete'), findsNothing);
    expect(find.text('Bici de 20" con cambios'), findsNothing);
    expect(find.text('Añadir regalo'), findsOneWidget);
    // La hoja crece desde la celda y acaba abajo, a todo lo ancho.
    final rect = tester.getRect(sheet);
    expect(rect.right, closeTo(390, 0.5));
    expect(rect.bottom, closeTo(1500, 1));
  }, size: const Size(390, 1500));

  screenTest('la hoja se cierra con atrás, con el velo y arrastrando', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openFamily(tester);
    final cell = find.bySemanticsLabel(
      RegExp('^Nosotros para Aritz: 2 regalos'),
    );

    await tester.tap(cell);
    await settle(tester);
    expect(find.byKey(kRepartoSheetKey), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byKey(kRepartoSheetKey), findsNothing);
    expect(cell, findsOneWidget);

    await tester.tap(cell);
    await settle(tester);
    await tester.tapAt(const Offset(195, 40));
    await settle(tester);
    expect(find.byKey(kRepartoSheetKey), findsNothing);

    await tester.tap(cell);
    await settle(tester);
    await tester.fling(
      find.descendant(
        of: find.byKey(kRepartoSheetKey),
        matching: find.text('Aritz'),
      ),
      const Offset(0, 400),
      1500,
    );
    await settle(tester);
    expect(find.byKey(kRepartoSheetKey), findsNothing);
    expect(tester.takeException(), isNull);
  }, size: const Size(390, 1500));

  screenTest(
    'tocar una celda vacía abre la hoja y «Regalo nuevo» el editor con persona y quien regala',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openFamily(tester);
      await tester.tap(
        find.bySemanticsLabel(
          'Padrina Anna para Aritz: nada todavía, añadir regalo',
        ),
      );
      await settle(tester);
      expect(
        find.text('Aún no hay regalos de Padrina Anna para Aritz'),
        findsOneWidget,
      );
      // Aritz tiene un regalo sin quién regala: se puede dar desde aquí.
      expect(find.text('Patinete'), findsOneWidget);
      expect(find.text('Sin asignar'), findsWidgets);
      await tester.tap(find.text('Añadir regalo de Padrina Anna'));
      await settle(tester);
      expect(find.text('Nuevo regalo'), findsOneWidget);
      final dropdowns = find.byType(PickerField<String>);
      expect(
        find.descendant(of: dropdowns.at(0), matching: find.text('Aritz')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dropdowns.at(1),
          matching: find.text('Padrina Anna'),
        ),
        findsOneWidget,
      );
    },
    size: const Size(390, 1500),
  );

  screenTest('«1 sin quién» abre los regalos sin quién regala de la persona', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openFamily(tester);
    await tester.tap(find.bySemanticsLabel('1 sin asignar'));
    await settle(tester);
    expect(find.text('Sin asignar'), findsWidgets);
    expect(find.text('Patinete'), findsOneWidget);
    expect(find.text('Sin asignar'), findsWidgets);
  }, size: const Size(390, 1500));

  screenTest('cambiar quién regala desde la hoja reasigna el regalo y las '
      'celdas cuentan lo nuevo', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openFamily(tester);
    await tester.tap(
      find.bySemanticsLabel(RegExp('^Nosotros para Aritz: 2 regalos')),
    );
    await settle(tester);

    // El chip de la primera fila despliega la fila de quién regala.
    await tester.tap(
      find.bySemanticsLabel(RegExp('^Quién regala: Nosotros')).first,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_inSheet('Tío Pere'), findsOneWidget);
    expect(_inSheet('Nadie'), findsOneWidget);
    await settle(tester);

    await tester.tap(_inSheet('Tío Pere'));
    await settle(tester);
    await settle(tester);
    expect(tester.takeException(), isNull);
    final state = await familyState(tester, phone);
    final moved = state.view.gifts.where(
      (g) => g.giverId == 'pere' && g.recipientId == 'aritz',
    );
    expect(moved, hasLength(1));

    // Cerrada la hoja, la rejilla enseña el reparto nuevo.
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(
      find.bySemanticsLabel(RegExp('^Nosotros para Aritz: 1 regalo,')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('^Tío Pere para Aritz: 1 regalo,')),
      findsOneWidget,
    );
  }, size: const Size(390, 1500));

  screenTest('dar un regalo sin quién regala desde su hoja', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openFamily(tester);
    await tester.tap(find.bySemanticsLabel('1 sin asignar'));
    await settle(tester);
    await tester.tap(
      find.bySemanticsLabel(RegExp('^Quién regala: Sin asignar')).first,
    );
    await settle(tester);
    await tester.tap(_inSheet('Tío Pere'));
    await settle(tester);
    await settle(tester);
    final state = await familyState(tester, phone);
    expect(
      state.view.gifts.firstWhere((g) => g.title == 'Patinete').giverId,
      'pere',
    );
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.bySemanticsLabel('1 sin asignar'), findsNothing);
  }, size: const Size(390, 1500));

  screenTest('con «Reducir movimiento» la hoja solo se funde, en 150 ms', (
    tester,
    phone,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openFamily(tester);
    await tester.tap(
      find.bySemanticsLabel(RegExp('^Nosotros para Aritz: 2 regalos')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    // Ya está en su sitio final (no viaja desde la celda): solo cambia la
    // opacidad.
    expect(
      tester.getRect(find.byKey(kRepartoSheetKey)).bottom,
      closeTo(1500, 1),
    );
    await tester.pump(const Duration(milliseconds: 160));
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  }, size: const Size(390, 1500));

  screenTest('«Revisar» lleva a la lista de la persona del duplicado', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openFamily(tester);
    await tapText(tester, 'Revisar');
    expect(find.text('Cocinita de madera'), findsOneWidget);
    final state = await familyState(tester, phone);
    expect(
      state.view.gifts.where((g) => g.status == GiftStatus.delivered),
      isNotEmpty,
    );
  }, size: const Size(390, 1500));

  screenTest(
    'sin personas ni quien regala, la rejilla enseña el estado vacío',
    (tester, phone) async {
      await bareFamily(tester, phone);
      await pumpRegalos(tester, phone);
      await openFamily(tester);
      expect(find.text('Faltan personas'), findsOneWidget);
    },
  );

  screenTest('desde la hoja, «Ver la lista» abre la lista y atrás vuelve a '
      'Reparto', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openFamily(tester);
    final cell = find.bySemanticsLabel(
      RegExp('^Nosotros para Aritz: 2 regalos'),
    );
    await tester.tap(cell);
    await settle(tester);
    await tester.tap(find.text('Ver la lista de Aritz'));
    await settle(tester);
    expect(find.byKey(kRepartoSheetKey), findsNothing);
    expect(find.bySemanticsLabel('Quitar filtro Nosotros'), findsOneWidget);
    expect(find.text('Pijama de astronautas, talla 8'), findsOneWidget);
    expect(find.text('Estación de bomberos de bloques'), findsOneWidget);
    expect(find.text('Patinete'), findsNothing);
    expect(find.text('Bici de 20" con cambios'), findsNothing);

    // (d) Mientras la lista está abierta desde Reparto, la barra marca
    // «Reparto» como destino seleccionado.
    final repartoNav = find.bySemanticsLabel('Reparto');
    expect(
      tester
          .getSemantics(repartoNav)
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );

    // (a) Atrás del sistema vuelve a Reparto.
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(cell, findsOneWidget);

    // (b) Cubrir también el botón «Revisar».
    await tapText(tester, 'Revisar');
    await settle(tester);
    expect(find.text('Cocinita de madera'), findsOneWidget);
    // Se abrió desde Reparto: el botón no puede decir «Personas».
    expect(find.bySemanticsLabel('Volver a Personas'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Volver a Reparto'));
    await settle(tester);
    expect(cell, findsOneWidget);

    // (c) Tras volver, tocar «Personas» muestra PeopleScreen (sin lista duplicada).
    await tester.tap(find.text('Personas').last);
    await settle(tester);
    expect(find.byType(PeopleScreen), findsOneWidget);
  }, size: const Size(390, 1500));
}
