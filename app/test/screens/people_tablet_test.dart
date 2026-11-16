import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/layout/pane_scope.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/widgets/gift_row.dart';
import 'package:regalos/core/widgets/occasion_countdown_card.dart';
import 'package:regalos/core/widgets/person_avatar.dart';
import 'package:regalos/core/widgets/screen_header.dart';
import 'package:regalos/features/gifts/presentation/person_list_screen.dart';
import 'package:regalos/features/lock/application/lock_controller.dart';
import 'package:regalos/features/occasions/presentation/occasion_detail_screen.dart';
import 'package:regalos/features/people/presentation/countdown_carousel.dart';
import 'package:regalos/features/people/presentation/people_screen.dart';

import '../helpers/memory_stores.dart';
import '../helpers/screens.dart';
import '../helpers/tablet.dart';
import '../widgets/motion_shared_test.dart' show moving;

// Tanda T3 del plan de tablet (la guía de diseño para tablet, §6): Personas
// y la lista de una persona en una columna de 640 centrada en el panel, con
// el carrusel de cuenta atrás enseñando dos tarjetas. En el móvil, nada.

/// La columna de las listas dentro del panel: 640 centrados o, si el panel es
/// más estrecho, el panel entero.
Rect _column(WidgetTester tester) {
  final pane = tester.getRect(find.byType(PaneScope));
  final width = math.min(640.0, pane.width);
  return Rect.fromLTWH(
    pane.left + (pane.width - width) / 2,
    pane.top,
    width,
    pane.height,
  );
}

final _cards = find.byType(OccasionCountdownCard);

/// La tarjeta de la fila de [name] en Personas.
Finder _personRow(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(InkWell)).first;

Occasion _occasion(String id, OccasionKind kind, int month, int day) =>
    Occasion(
      id: id,
      kind: kind,
      rawKind: kind.name,
      name: id,
      month: month,
      day: day,
      recurring: true,
      archived: false,
    );

/// Una familia con Aritz y solo las ocasiones de [occasions].
Future<void> _familyWith(
  WidgetTester tester,
  FakePhone phone,
  List<Occasion> occasions,
) => tester.runAsync(() async {
  final c = familyOf(phone);
  await c.createFamily(deviceName: 'M');
  await c.upsertRecipient(
    const Recipient(id: 'aritz', name: 'Aritz', colorIndex: 0, archived: false),
  );
  for (final occasion in occasions) {
    await c.upsertOccasion(occasion);
  }
  await phone.container.read(lockControllerProvider.notifier).skipSetup();
});

// Los tamaños con una sola columna de 640: el móvil y la tablet en vertical.
// A 1280 × 800 hay dos paneles y lo mismo se comprueba en
// `test/app/two_pane_web_test.dart`.
const _onePane = [kPhoneSize, kTabletPortrait];

void main() {
  test('el carrusel enseña dos tarjetas desde 640 de ancho, de 300 a 360', () {
    // El móvil y el panel de lista: una, con la siguiente asomando.
    expect(CountdownCarousel.perViewFor(390), 1);
    expect(CountdownCarousel.cardWidthFor(390), closeTo(331.1, 0.01));
    expect(CountdownCarousel.perViewFor(639), 1);
    // La columna de 640: dos de 300 con 8 entre ellas y 16 a cada lado.
    expect(CountdownCarousel.perViewFor(640), 2);
    expect(CountdownCarousel.cardWidthFor(640), 300);
    expect(16 + 300 + 8 + 300 + 16, 640);
    // El detalle de 720 y el tope de 360.
    expect(CountdownCarousel.cardWidthFor(720), 340);
    expect(CountdownCarousel.cardWidthFor(760), 360);
  });

  group('Personas', () {
    tabletScreenTest(
      'la cabecera, la cuenta atrás y las filas van en la columna de 640; en '
      'el móvil, de lado a lado',
      (tester, phone, size) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        final column = _column(tester);
        if (size == kPhoneSize) {
          expect(column.left, 0);
          expect(column.width, 390);
        } else {
          expect(column.width, 640);
          expect(column.center.dx, 80 + (size.width - 80) / 2);
        }

        final header = tester.getRect(find.byType(ScreenHeader));
        expect(header.left, column.left);
        expect(header.right, column.right);

        final carousel = tester.getRect(find.byType(CountdownCarousel));
        expect(carousel.left, column.left);
        expect(carousel.right, column.right);

        for (final name in ['Aritz', 'Nora', 'Leo']) {
          final row = tester.getRect(_personRow(name));
          expect(row.left, column.left + 16, reason: name);
          expect(row.right, column.right - 16, reason: name);
        }
        expect(tester.takeException(), isNull);
      },
      sizes: _onePane,
    );

    tabletScreenTest(
      'la cuenta atrás enseña dos tarjetas enteras de 300 y marca las dos',
      (tester, phone, size) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        final column = _column(tester);
        final first = tester.getRect(_cards.at(0));
        final second = tester.getRect(_cards.at(1));
        expect(first.left, column.left + 16);
        expect(first.width, 300);
        expect(second.left, first.right + 8);
        expect(second.width, 300);
        expect(second.right, column.right - 16);
        expect(first.height, second.height);
        // La tercera no asoma: queda fuera del visor.
        final pager = tester.getRect(find.byType(PageView));
        expect(pager.right, lessThanOrEqualTo(column.right));
        expect(find.bySemanticsLabel('Ocasiones 1 y 2 de 6'), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp(r'^Ocasión \d')), findsNothing);
      },
      sizes: const [kTabletPortrait],
    );

    tabletScreenTest(
      'se desliza de una en una hasta enseñar las dos últimas, y vuelve',
      (tester, phone, size) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        for (var i = 2; i <= 5; i++) {
          await tester.drag(find.byType(PageView), const Offset(-300, 0));
          await settle(tester);
          expect(
            find.bySemanticsLabel('Ocasiones $i y ${i + 1} de 6'),
            findsOneWidget,
          );
        }
        // Ya no hay más: las dos últimas se quedan.
        await tester.drag(find.byType(PageView), const Offset(-300, 0));
        await settle(tester);
        expect(find.bySemanticsLabel('Ocasiones 5 y 6 de 6'), findsOneWidget);
        expect(find.text('267'), findsOneWidget);
        await tester.drag(find.byType(PageView), const Offset(300, 0));
        await settle(tester);
        expect(find.bySemanticsLabel('Ocasiones 4 y 5 de 6'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      sizes: const [kTabletPortrait],
    );

    tabletScreenTest(
      'el paralaje sigue: el dibujo se retrasa en la tarjeta que sale y en la '
      'que entra, no en la que se queda a la vista',
      (tester, phone, size) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        // En reposo, las dos a la vista con el dibujo en su sitio.
        expect(moving(tester, _cards.at(0)), isEmpty);
        expect(moving(tester, _cards.at(1)), isEmpty);

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(PageView)),
        );
        await gesture.moveBy(const Offset(-30, 0));
        await gesture.moveBy(const Offset(-120, 0));
        await tester.pump();
        // A media página: la primera sale, la segunda sigue a la vista y la
        // tercera entra.
        expect(moving(tester, _cards.at(0)), isNotEmpty);
        expect(moving(tester, _cards.at(1)), isEmpty);
        expect(moving(tester, _cards.at(2)), isNotEmpty);
        await gesture.up();
        await settle(tester);
        expect(moving(tester, _cards.at(1)), isEmpty);
      },
      sizes: const [kTabletPortrait],
    );

    tabletScreenTest(
      'con dos ocasiones caben las dos y no hay indicadores; con una, la '
      'tarjeta mide lo mismo y queda al principio',
      (tester, phone, size) async {
        await _familyWith(tester, phone, [
          _occasion('reyes', OccasionKind.kings, 1, 6),
          _occasion('tio', OccasionKind.tio, 12, 24),
        ]);
        await pumpRegalos(tester, phone);
        final column = _column(tester);
        expect(_cards, findsNWidgets(2));
        expect(tester.getRect(_cards.at(0)).left, column.left + 16);
        expect(tester.getRect(_cards.at(1)).right, column.right - 16);
        expect(find.bySemanticsLabel(RegExp(r'^Ocasi\S+ \d')), findsNothing);
        // No hay adónde deslizar.
        await tester.drag(find.byType(PageView), const Offset(-300, 0));
        await settle(tester);
        expect(tester.getRect(_cards.at(0)).left, column.left + 16);

        await tester.runAsync(() => familyOf(phone).deleteOccasion('tio'));
        await settle(tester);
        expect(_cards, findsOneWidget);
        final only = tester.getRect(_cards);
        expect(only.left, column.left + 16);
        expect(only.width, 300);
        expect(tester.takeException(), isNull);
      },
      sizes: const [kTabletPortrait],
    );

    tabletScreenTest(
      'la tarjeta de cuenta atrás sigue creciendo hasta el detalle: la ventana '
      'con un panel, el panel de detalle con dos (T11)',
      (tester, phone, size) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        final twoPanes = size.width >= 840;
        // Con dos paneles, el destino es el panel de detalle (el de la lista
        // de la persona elegida) y lo de fuera no se mueve.
        final detailBefore = twoPanes
            ? tester.getRect(find.byType(PersonListScreen))
            : null;
        // Con un panel, el carrusel; con dos (escritorio ancho), la tarjeta de
        // la columna «Resumen».
        final outside = twoPanes
            ? find.byType(SummaryColumn)
            : find.byType(CountdownCarousel);
        final carouselBefore = tester.getRect(outside);
        await tester.tap(_cards.first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        // En pleno vuelo: el número de la tarjeta, el del detalle (oculto) y
        // el que vuela.
        expect(find.text('45'), findsNWidgets(3));
        expect(find.byType(OccasionDetailScreen), findsOneWidget);
        if (twoPanes) {
          // La lista no cambia de sitio ni de tamaño durante el vuelo.
          expect(tester.getRect(outside), carouselBefore);
          // El detalle ya se maqueta en el panel, no en la ventana.
          expect(
            tester.getRect(find.byType(OccasionDetailScreen)),
            detailBefore,
          );
        }
        await tester.pumpAndSettle();
        // Con dos paneles la tarjeta de la lista sigue a la vista.
        expect(find.text('45'), findsNWidgets(twoPanes ? 2 : 1));
        expect(find.bySemanticsLabel('Volver a Personas'), findsOneWidget);
        final header = tester.getRect(
          find.descendant(
            of: find.byType(OccasionDetailScreen),
            matching: find.byType(ScreenHeader),
          ),
        );
        if (twoPanes) {
          // Termina exactamente en el rectángulo del panel de detalle, con la
          // lista (y el raíl) a la vista y quietos.
          final detail = tester.getRect(find.byType(OccasionDetailScreen));
          expect(detail, detailBefore);
          expect(detail.left, greaterThan(80));
          expect(header.center.dx, closeTo(detail.center.dx, 0.5));
          expect(tester.getRect(outside), carouselBefore);
        } else {
          // El detalle ocupa la ventana (crece por encima del raíl) y su
          // contenido, 640 centrados en ella.
          expect(header.width, 640);
          expect(header.center.dx, size.width / 2);
        }

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(OccasionDetailScreen), findsNothing);
        expect(_cards, findsWidgets);
        expect(tester.takeException(), isNull);
      },
      sizes: const [kTabletPortrait, Size(1700, 1000)],
    );
  });

  group('la lista de una persona', () {
    tabletScreenTest(
      'cabecera, presupuesto, filtros y filas en la columna, y el «+» a 16 '
      'de su borde derecho',
      (tester, phone, size) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tapText(tester, 'Aritz');
        final column = _column(tester);

        final header = tester.getRect(find.byType(ScreenHeader));
        expect(header.left, column.left);
        expect(header.right, column.right);

        final budget = tester.getRect(
          find.bySemanticsLabel(RegExp('^Gastado: ')).first,
        );
        expect(budget.left, greaterThanOrEqualTo(column.left + 16));
        expect(budget.right, lessThanOrEqualTo(column.right - 16));

        final filters = tester.getRect(find.text('Filtros'));
        expect(filters.left, greaterThan(column.left));
        expect(filters.right, lessThan(column.right));

        for (final row in find.byType(GiftRow).evaluate()) {
          final rect = tester.getRect(find.byElementPredicate((e) => e == row));
          expect(rect.left, column.left);
          expect(rect.right, column.right);
        }

        final add = tester.getRect(find.byType(FloatingActionButton));
        expect(add.right, column.right - 16);
        expect(add.size, const Size(56, 56));
        expect(tester.takeException(), isNull);
      },
      sizes: _onePane,
    );

    tabletScreenTest('la lista se desplaza también arrastrando por el margen', (
      tester,
      phone,
      size,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tapText(tester, 'Aritz');
      final column = _column(tester);
      final list = find.descendant(
        of: find.byType(PersonListScreen),
        matching: find.byType(ListView),
      );
      final rect = tester.getRect(list);
      // La lista ocupa el panel entero; la columna es su relleno.
      expect(rect.left, lessThan(column.left));
      expect(rect.right, greaterThan(column.right));
    }, sizes: const [kTabletPortrait]);

    tabletScreenTest('el avatar sigue volando de la fila a la cabecera', (
      tester,
      phone,
      size,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      List<double> avatarSizes() => [
        for (final a in tester.widgetList<PersonAvatar>(
          find.byType(PersonAvatar),
        ))
          a.size,
      ];
      await tester.tap(find.text('Aritz'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // En vuelo, un avatar de un tamaño entre el de la fila (52) y el de la
      // cabecera (46).
      final sizes = avatarSizes();
      expect(sizes.any((s) => s != 52 && s != 46), isTrue, reason: '$sizes');
      await settle(tester);
      expect(avatarSizes().where((s) => s == 46), isNotEmpty);
      expect(tester.takeException(), isNull);
    }, sizes: _onePane);

    screenTest(
      'girar con un filtro puesto no pierde nada y la columna se recoloca',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tapText(tester, 'Aritz');
        await tapText(tester, 'Falta comprar');
        expect(find.text('Pijama de astronautas, talla 8'), findsNothing);
        expect(find.text('Patinete'), findsOneWidget);
        final state = tester.state(find.byType(PersonListScreen));

        await rotate(tester);
        await settle(tester);
        expect(windowSize(tester), kTabletLandscape);
        expect(tester.state(find.byType(PersonListScreen)), same(state));
        expect(find.text('Pijama de astronautas, talla 8'), findsNothing);
        expect(find.text('Patinete'), findsOneWidget);
        // Con dos paneles la lista de la persona es el detalle: a la derecha
        // de la lista y su filete, sin «+» flotante (el botón va en la
        // cabecera).
        final detail = tester.getRect(find.byType(PersonListScreen));
        expect(
          detail.left,
          closeTo(tester.getRect(find.byType(PeopleListPane)).right + 1, 0.01),
        );
        expect(detail.right, 1280);
        expect(
          tester.getRect(find.byType(ScreenHeader).last).left,
          detail.left,
        );
        expect(find.byType(FloatingActionButton), findsNothing);
        expect(
          find.byKey(const ValueKey<String>('add-gift-header')),
          findsOneWidget,
        );

        await rotate(tester);
        await settle(tester);
        final column = _column(tester);
        expect(column.left, 80 + 40);
        expect(tester.getRect(find.byType(ScreenHeader)).left, column.left);
        expect(find.text('Patinete'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      size: kTabletPortrait,
    );
  });

  group('en oscuro, con la letra al 130 % y con «Reducir movimiento»', () {
    screenTest(
      'Personas y la lista de una persona, sin desbordes a 800 × 1280',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        expect(tester.takeException(), isNull);
        final column = _column(tester);
        expect(tester.getRect(_cards.at(1)).right, column.right - 16);
        await tester.drag(find.byType(PageView), const Offset(-300, 0));
        await settle(tester);
        await tapText(tester, 'Aritz');
        expect(find.byType(PersonListScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      size: kTabletPortrait,
      textScale: 1.3,
      brightness: Brightness.dark,
    );

    tabletScreenTest(
      'con «Reducir movimiento» el carrusel no mueve ni escala nada',
      (tester, phone, size) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(PageView)),
        );
        await gesture.moveBy(const Offset(-30, 0));
        await gesture.moveBy(const Offset(-170, 0));
        await tester.pump();
        expect(moving(tester, find.byType(PageView)), isEmpty);
        await gesture.up();
        await settle(tester);
        expect(find.bySemanticsLabel('Ocasiones 2 y 3 de 6'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      sizes: const [kTabletPortrait],
    );
  });
}
