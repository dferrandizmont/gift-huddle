import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/widgets/filter_pill.dart';
import 'package:regalos/features/family/application/self_recipient_provider.dart';
import 'package:regalos/features/family/presentation/family_screen.dart';
import 'package:regalos/features/family/presentation/reparto_flight.dart';
import 'package:regalos/features/family/presentation/reparto_grid.dart';
import 'package:regalos/features/family/presentation/reparto_outside.dart';
import 'package:regalos/features/family/presentation/reparto_person_sheet.dart';
import 'package:regalos/features/family/presentation/reparto_sheet.dart';
import 'package:regalos/features/family/presentation/self_tag.dart';

import '../helpers/memory_stores.dart' show FakePhone;
import '../helpers/screens.dart';
import '../helpers/tablet.dart';
import 'family_grid_test.dart' show expectNoRoundShapes, openFamily;

// Tanda T7 del plan de tablet (la guía de diseño para tablet, §6): la
// rejilla de Reparto en una ventana ancha. Un solo panel, celdas de hasta
// 96 × 52 (120 × 56 desde 840 dp, tanda W2b del escritorio), nombres entre 160 y 220, la rejilla centrada y las hojas de 560
// centradas en el área de contenido. Por debajo de 600 dp, lo de siempre.

/// Ancho del raíl: el área de contenido empieza ahí.
const double kRail = 80;

/// El ancla [id] de la vista que se ve (una celda, un nombre, un avatar…).
Finder anchorOf(String id) =>
    find.byWidgetPredicate((w) => w is RepartoAnchor && w.id == id);

/// La celda de [recipientId] y [giverId] (lo que se pinta, no su zona táctil).
Finder cellOf(String recipientId, String giverId) =>
    anchorOf(repartoCellAnchor(recipientId, giverId));

/// Si el nombre de quien regala [name] va inclinado en la cabecera (el modo
/// compacto de la rejilla).
bool tilted(WidgetTester tester, String name) => tester
    .widgetList<Transform>(
      find.ancestor(of: find.text(name), matching: find.byType(Transform)),
    )
    .any((t) => t.transform.storage[1] != 0);

/// El desplazamiento horizontal de la rejilla (no el de los chips de ocasión).
bool _isHorizontalScroll(Widget w) =>
    w is SingleChildScrollView &&
    w.scrollDirection == Axis.horizontal &&
    w.key != kOccasionChipsKey;

/// Elige de quién es este móvil («Yo»).
Future<void> chooseSelf(
  WidgetTester tester,
  FakePhone phone,
  String? id,
) async {
  await tester.runAsync(
    () => phone.container.read(selfRecipientIdProvider.notifier).choose(id),
  );
  await settle(tester);
}

/// Añade [count] personas que regalan a las seis de la muestra.
Future<void> addGivers(WidgetTester tester, FakePhone phone, int count) =>
    tester.runAsync(() async {
      for (var i = 0; i < count; i++) {
        await familyOf(phone).upsertGiver(
          Giver(
            id: 'more$i',
            name: 'Familia ${i + 1}',
            colorIndex: i,
            householdPays: false,
            archived: false,
          ),
        );
      }
    });

const _givers = ['us', 'yayos', 'avis', 'marta', 'pere', 'anna'];
const _people = ['aritz', 'nora', 'leo'];

void main() {
  group('medidas de la rejilla en una ventana ancha', () {
    RepartoLayout wide(double width, int columns, {double scale = 1}) =>
        RepartoLayout(
          width: width,
          columns: columns,
          scaler: TextScaler.linear(scale),
          wide: true,
        );

    test('con tres que regalan las celdas miden 96 × 52, los nombres 220 y '
        'la rejilla queda centrada', () {
      // 720 y 1200 son el área de contenido de 800 y de 1280 (sin el raíl);
      // 672 y 1152, los anchos útiles del plan.
      for (final width in [672.0, 720.0, 1152.0, 1200.0]) {
        final l = wide(width, 3);
        expect(l.compact, isFalse, reason: '$width');
        expect(l.cellWidth, 96, reason: '$width');
        expect(l.cellHeight, 52, reason: '$width');
        expect(l.leftWidth, 220, reason: '$width');
        expect(l.rowHeight, 60);
        // Mismo margen a los dos lados.
        expect(
          l.pad,
          closeTo((width - 220 - 3 * 99) / 2, 0.001),
          reason: '$width',
        );
      }
    });

    test('con seis: a 720 las celdas se estrechan sin compactar y los nombres '
        'se quedan en 160; a 1200 siguen en 96 con los nombres a 220', () {
      final portrait = wide(720, 6);
      expect(portrait.compact, isFalse);
      expect(portrait.cellWidth, closeTo(85, 0.01));
      expect(portrait.cellHeight, 52);
      expect(portrait.leftWidth, closeTo(160, 0.001));
      expect(portrait.pad, closeTo(16, 0.001));

      final landscape = wide(1200, 6);
      expect(landscape.compact, isFalse);
      expect(landscape.cellWidth, 96);
      expect(landscape.cellHeight, 52);
      expect(landscape.leftWidth, 220);
      expect(landscape.pad, closeTo((1200 - 220 - 6 * 99) / 2, 0.001));
    });

    test('con nueve: a 720 entra el modo compacto (las de 68 no caben), con '
        'celdas de más de 44; a 1200 caben las de 96 sin compactar', () {
      final portrait = wide(720, 9);
      expect(portrait.compact, isTrue);
      expect(portrait.cellWidth, greaterThan(44));
      expect(portrait.cellWidth, lessThan(68));
      expect(portrait.cellHeight, 44);
      expect(portrait.leftWidth, 160);
      expect(portrait.headerHeight, 88);

      final landscape = wide(1200, 9);
      expect(landscape.compact, isFalse);
      expect(landscape.cellWidth, 96);
      expect(landscape.leftWidth, 220);
      expect(landscape.pad, closeTo((1200 - 220 - 9 * 99) / 2, 0.001));
    });

    test('a 800 dp caben siete que regalan sin compactar, y ocho ya no', () {
      final seven = wide(720, 7);
      expect(seven.compact, isFalse);
      expect(seven.cellWidth, greaterThanOrEqualTo(68));
      expect(wide(720, 8).compact, isTrue);
    });

    test('a cualquier ancho y con cualquier número de columnas la rejilla '
        'cabe, queda centrada y no pasa de sus topes', () {
      for (var width = 520.0; width <= 1400; width += 20) {
        for (var columns = 1; columns <= 14; columns++) {
          final l = wide(width, columns);
          final reason = '$width × $columns';
          final used = l.leftWidth + l.slot * columns;
          expect(l.pad, greaterThanOrEqualTo(16 - 0.001), reason: reason);
          // Lo que sobra se reparte igual a los dos lados.
          expect(l.pad * 2 + used, closeTo(width, 0.001), reason: reason);
          expect(l.cellWidth, lessThanOrEqualTo(96), reason: reason);
          expect(l.cellWidth, greaterThan(0), reason: reason);
          expect(l.cellHeight, lessThanOrEqualTo(52), reason: reason);
          expect(l.leftWidth, lessThanOrEqualTo(220 + 0.001), reason: reason);
          if (!l.compact) {
            expect(
              l.leftWidth,
              greaterThanOrEqualTo(160 - 0.001),
              reason: reason,
            );
            expect(
              l.cellWidth,
              greaterThanOrEqualTo(68 - 0.001),
              reason: reason,
            );
          }
          expect(
            l.barWidth,
            lessThanOrEqualTo(l.cellWidth - 8),
            reason: reason,
          );
        }
      }
    });

    test('con la letra grande la celda crece en alto, hasta un 25 %', () {
      expect(wide(720, 3, scale: 1.3).cellHeight, 52 * 1.25);
      expect(wide(720, 9, scale: 1.3).cellHeight, 44 * 1.25);
    });

    test('en el móvil las medidas son las de siempre, también si el ancho es '
        'grande (el móvil tumbado)', () {
      for (final width in [360.0, 390.0, 844.0]) {
        for (final columns in [1, 3, 4, 5, 6, 9]) {
          final l = RepartoLayout(
            width: width,
            columns: columns,
            scaler: TextScaler.noScaling,
          );
          final reason = '$width × $columns';
          expect(l.compact, columns >= 5, reason: reason);
          expect(l.pad, 16, reason: reason);
          expect(
            l.cellWidth,
            lessThanOrEqualTo(columns >= 5 ? 44 : 68),
            reason: reason,
          );
          expect(l.cellHeight, columns >= 5 ? 44 : 48, reason: reason);
          expect(
            l.leftWidth,
            closeTo(width - 32 - l.slot * columns, 0.001),
            reason: reason,
          );
          // La barra de comprados, la de hoy.
          expect(
            l.barWidth,
            (columns >= 5 ? 18.0 : 28.0).clamp(0, l.cellWidth - 8),
            reason: reason,
          );
        }
      }
    });
  });

  tabletScreenTest('la rejilla se centra en el área de contenido con celdas '
      'grandes, sin desplazamiento horizontal ni nada fuera de la ventana', (
    tester,
    phone,
    size,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openFamily(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(RepartoGrid), findsOneWidget);
    expect(find.byWidgetPredicate(_isHorizontalScroll), findsNothing);

    // Tres personas y seis que regalan: a 800 las celdas miden 85 × 52 y a
    // 1280 (dos paneles), 120 × 56.
    final expected = size == kTabletPortrait
        ? const Size(85, 52)
        : const Size(120, 56);
    for (final person in _people) {
      for (final giver in _givers) {
        final cell = tester.getRect(cellOf(person, giver));
        expect(cell.width, closeTo(expected.width, 0.01));
        expect(cell.height, expected.height);
        expect(cell.left, greaterThanOrEqualTo(kRail));
        expect(cell.right, lessThanOrEqualTo(size.width));
      }
    }
    // Centrada: el mismo margen a la izquierda del avatar que a la derecha de
    // la última celda (que va centrada en su hueco: 1,5 de holgura).
    final cells = [
      for (final giver in _givers) tester.getRect(cellOf('aritz', giver)),
    ]..sort((a, b) => a.left.compareTo(b.left));
    final left =
        tester.getRect(anchorOf(repartoAvatarAnchor('aritz'))).left - kRail;
    final right = size.width - cells.last.right;
    expect(right, closeTo(left, 2));
    expect(left, greaterThanOrEqualTo(16));
    // Las celdas, seguidas, con 3 de hueco.
    for (var i = 1; i < cells.length; i++) {
      expect(cells[i].left - cells[i - 1].right, closeTo(3, 0.01));
    }
    // La columna de nombres, entre 160 y 220 (entre 180 y 280 en dos paneles).
    final names =
        cells.first.left -
        tester.getRect(anchorOf(repartoAvatarAnchor('aritz'))).left;
    expect(names, greaterThanOrEqualTo(size == kTabletPortrait ? 160 : 180));
    expect(names, lessThanOrEqualTo(size == kTabletPortrait ? 222 : 282));
    // Sin modo compacto: los nombres de quienes regalan van rectos.
    expect(tilted(tester, 'Yayos de Terrassa'), isFalse);
    // Los chips de ocasión: en una sola columna (800), centrados como la
    // rejilla; con dos paneles (1280), empiezan donde empieza la rejilla (misma
    // columna que la cabecera).
    final pills = [
      for (final pill
          in find
              .descendant(
                of: find.byKey(kOccasionChipsKey),
                matching: find.byType(FilterPill),
              )
              .evaluate())
        tester.getRect(find.byElementPredicate((e) => e == pill)),
    ];
    expect(pills.length, greaterThan(2));
    if (size == kTabletPortrait) {
      expect(
        pills.first.left - kRail,
        closeTo(size.width - pills.last.right, 1),
        reason: 'chips centrados',
      );
      expect(pills.first.left - kRail, greaterThan(16));
    } else {
      final avatar = tester.getRect(anchorOf(repartoAvatarAnchor('aritz')));
      expect(
        pills.first.left,
        closeTo(avatar.left, 1),
        reason: 'con la rejilla',
      );
    }
    expectNoRoundShapes(tester, find.byType(RepartoGrid));
    expect(tester.takeException(), isNull);
  });

  tabletScreenTest('con nueve que regalan sigue cabiendo sin desplazamiento '
      'horizontal; a 800 dp entra el modo compacto', (
    tester,
    phone,
    size,
  ) async {
    await seedSample(tester, phone);
    await addGivers(tester, phone, 3);
    await pumpRegalos(tester, phone);
    await openFamily(tester);
    expect(tester.takeException(), isNull);
    expect(find.byWidgetPredicate(_isHorizontalScroll), findsNothing);
    for (final giver in [..._givers, 'more0', 'more1', 'more2']) {
      final cell = tester.getRect(cellOf('leo', giver));
      expect(cell.left, greaterThanOrEqualTo(kRail));
      expect(cell.right, lessThanOrEqualTo(size.width));
      if (size == kTabletPortrait) {
        expect(cell.width, greaterThan(44));
        expect(cell.width, lessThan(68));
        expect(cell.height, 44);
      } else {
        // Nueve en 1168 útiles con los nombres a 180: 106,8 × 56.
        expect(cell.width, closeTo((1168 - 180) / 9 - 3, 0.01));
        expect(cell.height, 56);
      }
    }
    // Con el modo compacto, los nombres de quienes regalan van inclinados.
    expect(tilted(tester, 'Yayos de Terrassa'), size == kTabletPortrait);
    expect(tester.takeException(), isNull);
  });

  tabletScreenTest(
    'con la letra al 130 % nada se desborda',
    (tester, phone, size) async {
      await seedSample(tester, phone);
      await chooseSelf(tester, phone, 'nora');
      await pumpRegalos(tester, phone);
      await openFamily(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(cellOf('aritz', 'us'));
      await settle(tester);
      expect(find.byKey(kRepartoSheetKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    sizes: const [kTabletPortrait],
    textScale: 1.3,
  );

  tabletScreenTest('en oscuro y con «Reducir movimiento» la rejilla y su hoja '
      'salen igual, sin traslaciones', (tester, phone, size) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openFamily(tester);
    expect(
      tester.getRect(cellOf('aritz', 'us')).height,
      size == kTabletPortrait ? 52 : 56,
    );
    await tester.tap(cellOf('aritz', 'us'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // La hoja ya está en su sitio (se funde, no sube).
    final sheet = tester.getRect(find.byKey(kRepartoSheetKey));
    expect(sheet.width, 560);
    expect(sheet.bottom, closeTo(size.height, 0.5));
    await settle(tester);
    expect(tester.getRect(find.byKey(kRepartoSheetKey)), sheet);
    // Girar con la hoja abierta tampoco lanza nada.
    await rotate(tester);
    await tester.pump();
    await settle(tester);
    expect(find.byKey(kRepartoSheetKey), findsOneWidget);
    expect(tester.getRect(find.byKey(kRepartoSheetKey)).width, 560);
    expect(tester.takeException(), isNull);
  }, brightness: Brightness.dark);

  group('hojas de Reparto', () {
    /// Que la hoja mide 560, está centrada en el área de contenido y llega
    /// abajo.
    void expectCentred(WidgetTester tester) {
      final window = windowSize(tester);
      final sheet = tester.getRect(find.byKey(kRepartoSheetKey));
      expect(sheet.width, 560);
      expect(
        sheet.center.dx,
        closeTo(kRail + (window.width - kRail) / 2, 0.01),
      );
      // El muelle deja la hoja a centésimas de su sitio.
      expect(sheet.bottom, closeTo(window.height, 0.5));
      expect(sheet.height, lessThanOrEqualTo(window.height * 0.82 + 0.01));
    }

    tabletScreenTest('la hoja de una celda mide 560, sube centrada en el área '
        'de contenido y el velo cubre también el raíl', (
      tester,
      phone,
      size,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openFamily(tester);
      await tester.tap(cellOf('aritz', 'us'));
      await settle(tester);
      expect(find.byKey(kRepartoSheetKey), findsOneWidget);
      expectCentred(tester);
      expectNoRoundShapes(tester, find.byKey(kRepartoSheetKey));
      expect(tester.takeException(), isNull);

      // Tocar el velo sobre el raíl (fuera de la hoja) la cierra.
      await tester.tapAt(Offset(kRail / 2, size.height - 30));
      await settle(tester);
      expect(find.byKey(kRepartoSheetKey), findsNothing);

      // Y tocar a un lado de la hoja, a su altura, también.
      await tester.tap(cellOf('nora', 'us'));
      await settle(tester);
      final sheet = tester.getRect(find.byKey(kRepartoSheetKey));
      await tester.tapAt(Offset(sheet.left - 20, sheet.center.dy));
      await settle(tester);
      expect(find.byKey(kRepartoSheetKey), findsNothing);
      expect(tester.takeException(), isNull);
    });

    tabletScreenTest('la ficha de una persona también mide 560 y va '
        'centrada', (tester, phone, size) async {
      await seedSample(tester, phone);
      await chooseSelf(tester, phone, 'nora');
      await pumpRegalos(tester, phone);
      await openFamily(tester);
      await tester.tap(
        find.bySemanticsLabel('Abrir la ficha de Nora (yo)').first,
      );
      await settle(tester);
      expect(find.byType(RepartoPersonSheet), findsOneWidget);
      expectCentred(tester);
      expect(
        find.descendant(
          of: find.byType(RepartoPersonSheet),
          matching: find.byType(SelfTag),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    tabletScreenTest('girar con la hoja abierta la deja abierta, con lo que '
        'tenía desplegado, y centrada en el área de contenido nueva', (
      tester,
      phone,
      size,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openFamily(tester);
      await tester.tap(cellOf('aritz', 'us'));
      await settle(tester);
      // Se despliega la fila para cambiar quién regala.
      await tester.tap(
        find
            .descendant(
              of: find.byKey(kRepartoSheetKey),
              matching: find.bySemanticsLabel(
                RegExp('^Quién regala: Nosotros'),
              ),
            )
            .first,
      );
      await settle(tester);
      final nobody = find.descendant(
        of: find.byKey(kRepartoSheetKey),
        matching: find.text('Nadie'),
      );
      expect(nobody, findsOneWidget);
      final sheet = tester.element(find.byKey(kRepartoSheetKey));

      await rotate(tester);
      // La hoja sigue al panel un fotograma después.
      await tester.pump();
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(kRepartoSheetKey), findsOneWidget);
      expect(tester.element(find.byKey(kRepartoSheetKey)), same(sheet));
      expect(nobody, findsOneWidget);
      expectCentred(tester);

      // Y de vuelta.
      await rotate(tester);
      await tester.pump();
      await settle(tester);
      expect(nobody, findsOneWidget);
      expectCentred(tester);
      expect(tester.takeException(), isNull);
    });

    tabletScreenTest('en el móvil la hoja va de lado a lado, como siempre', (
      tester,
      phone,
      size,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openFamily(tester);
      // Seis columnas: el modo compacto de hoy, pegado a los márgenes.
      expect(
        tester.getRect(cellOf('aritz', 'us')).width,
        lessThanOrEqualTo(44),
      );
      expect(tester.getRect(anchorOf(repartoAvatarAnchor('aritz'))).left, 16);
      await tester.tap(cellOf('aritz', 'us'));
      await settle(tester);
      final sheet = tester.getRect(find.byKey(kRepartoSheetKey));
      expect(sheet.left, 0);
      expect(sheet.width, size.width);
      expect(sheet.bottom, closeTo(size.height, 0.5));
      expect(tester.takeException(), isNull);
    }, sizes: const [kPhoneSize]);

    tabletScreenTest(
      'el móvil tumbado es compacto: ni celdas grandes ni hoja de 560',
      (tester, phone, size) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await openFamily(tester);
        expect(tester.takeException(), isNull);
        final cell = tester.getRect(cellOf('aritz', 'us'));
        expect(cell.width, lessThanOrEqualTo(44));
        expect(cell.height, 44);
        expect(tester.getRect(anchorOf(repartoAvatarAnchor('aritz'))).left, 16);
        await tester.tap(cellOf('aritz', 'us'));
        await settle(tester);
        expect(tester.getRect(find.byKey(kRepartoSheetKey)).width, size.width);
        expect(tester.takeException(), isNull);
      },
      sizes: const [Size(844, 390)],
    );
  });

  tabletScreenTest('«Yo» sale junto al nombre de la persona de este móvil, sin '
      'mover las filas', (tester, phone, size) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openFamily(tester);
    final name = find.descendant(
      of: anchorOf(repartoNameAnchor('nora')),
      matching: find.byType(Text),
    );
    final before = tester.getRect(name);
    await chooseSelf(tester, phone, 'nora');
    expect(find.byType(SelfTag), findsOneWidget);
    expect(tester.getRect(name), before);
    final tag = tester.getRect(find.byType(SelfTag));
    // Con la columna de nombres ancha cabe a la derecha, en su línea.
    expect(tag.left, greaterThan(before.right));
    expect(tag.left, lessThan(before.right + 10));
    expect(tag.center.dy, closeTo(before.center.dy, 3));
    expect(find.bySemanticsLabel('Abrir la ficha de Nora (yo)'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  tabletScreenTest('girar con la rejilla a la vista la recoloca sin perder el '
      'filtro, el desplazamiento ni el bloque desplegado', (
    tester,
    phone,
    size,
  ) async {
    await seedSample(tester, phone);
    await tester.runAsync(
      () => familyOf(phone).setRecipientInReparto('leo', false),
    );
    await pumpRegalos(tester, phone);
    await openFamily(tester, all: false);
    await tester.tap(
      find.descendant(
        of: find.byKey(kOccasionChipsKey),
        matching: find.text('Reyes'),
      ),
    );
    await settle(tester);
    // «Fuera del reparto», desplegado: no pasa de 560 de ancho.
    await tester.tap(find.byKey(kRepartoOutsideToggleKey));
    await settle(tester);
    final include = find.byKey(repartoIncludeKey('leo'));
    expect(include, findsOneWidget);
    final toggle = tester.getRect(find.byKey(kRepartoOutsideToggleKey));
    expect(toggle.width, lessThanOrEqualTo(560));
    expect(tester.getRect(include).right, lessThanOrEqualTo(toggle.left + 560));
    final grid = tester.state(find.byType(RepartoGrid));

    await rotate(tester);
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(tester.state(find.byType(RepartoGrid)), same(grid));
    expect(include, findsOneWidget);
    expect(find.textContaining('Para Reyes'), findsOneWidget);
    // Las celdas, con las medidas del tamaño nuevo.
    final rotated = windowSize(tester);
    expect(
      tester.getRect(cellOf('aritz', 'us')).width,
      closeTo(rotated == kTabletPortrait ? 85 : 120, 0.01),
    );
    expect(find.byKey(kRepartoFlightKey), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
