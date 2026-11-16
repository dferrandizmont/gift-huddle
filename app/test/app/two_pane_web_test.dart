import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/layout/pane_scope.dart';
import 'package:regalos/core/layout/pane_selection.dart';
import 'package:regalos/core/layout/two_pane.dart' show PaneEntrance;
import 'package:regalos/core/layout/window_class.dart';
import 'package:regalos/core/theme/regalos_tokens.dart';
import 'package:regalos/core/motion/rolling_number.dart';
import 'package:regalos/core/widgets/desktop_add_gift_button.dart';
import 'package:regalos/core/widgets/focus_ring.dart';
import 'package:regalos/core/widgets/occasion_countdown_card.dart';
import 'package:regalos/core/widgets/pointer_surface.dart';
import 'package:regalos/core/widgets/person_avatar.dart';
import 'package:regalos/core/widgets/screen_header.dart';
import 'package:regalos/features/gifts/presentation/gift_editor_screen.dart';
import 'package:regalos/features/gifts/presentation/person_list_screen.dart';
import 'package:regalos/features/people/presentation/countdown_carousel.dart';
import 'package:regalos/features/occasions/presentation/occasion_detail_screen.dart';
import 'package:regalos/features/occasions/presentation/occasions_screen.dart';
import 'package:regalos/features/people/presentation/people_screen.dart';

import '../helpers/memory_stores.dart';
import '../helpers/screens.dart';
import '../helpers/tablet.dart';

// Los dos paneles de Personas (la guía de diseño de escritorio, §2 y
// tanda W1): lista a la izquierda y la lista de la persona elegida a la
// derecha, con la selección en la URL, desde 840 de ancho en cualquier
// plataforma; desde 1680, la tercera columna con las próximas ocasiones.
// Por debajo de 840 (móvil y tablet en vertical) nada cambia.

const _desktop = Size(1280, 800);
const _desktopWide = Size(1700, 1000);
const _huge = Size(2560, 1300);

/// La ruta en la que está el router ahora mismo.
String _path(FakePhone phone) => phone.container
    .read(routerProvider)
    .routeInformationProvider
    .value
    .uri
    .path;

/// La fila de [name] en el panel de lista.
Finder _row(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(InkWell)).first;

/// El panel de lista (primer hijo de `TwoPane`), el de detalle y el área
/// completa de la pestaña, medidos en la ventana.
Rect _listPane(WidgetTester tester) =>
    tester.getRect(find.byType(PeopleListPane));
Rect _detailPane(WidgetTester tester) =>
    tester.getRect(find.byType(PersonListScreen));

final _cards = find.byType(CountdownCarousel);

/// El botón «Añadir regalo» de la cabecera del detalle de escritorio.
final _addGift = find.byKey(const ValueKey<String>('add-gift-header'));

// El editor de regalo es un diálogo solo en la web; en una tablet de 1280 es la
// tarjeta de 640 (diseño D).
final _webOn = [giftEditorAsDialogProvider.overrideWithValue(true)];

void main() {
  group('a 1280 × 800', () {
    screenTest('lista y detalle a la vez, con la primera persona elegida', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      expect(find.byType(PeopleListPane), findsOneWidget);
      expect(find.byType(PersonListScreen), findsOneWidget);
      // La primera de la lista (por nombre) y su dirección.
      expect(_path(phone), '/people/aritz');
      final detail = find.descendant(
        of: find.byType(PersonListScreen),
        matching: find.text('Aritz'),
      );
      expect(detail, findsOneWidget);
      expect(find.text('Pijama de astronautas, talla 8'), findsOneWidget);
      // Tres paneles de ventana: el del raíl y la pestaña, la lista y el
      // detalle, uno al lado del otro (80 de raíl, 408 de lista, 1 de filete).
      final list = _listPane(tester);
      final pane = _detailPane(tester);
      expect(list.left, 80);
      expect(list.width, closeTo(408, 0.01));
      expect(pane.left, closeTo(80 + 408 + 1, 0.01));
      expect(pane.right, 1280);
      expect(list.top, pane.top);
      expect(find.byType(PaneScope), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    }, size: _desktop);

    screenTest('el detalle no lleva flecha de volver y «Añadir regalo» es el '
        'de la persona elegida', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      expect(find.bySemanticsLabel('Volver a Personas'), findsNothing);
      // Una sola cabecera lleva el título de la persona, sin el «Personas»
      // pequeño de encima.
      final header = find.descendant(
        of: find.byType(PersonListScreen),
        matching: find.byType(ScreenHeader),
      );
      expect(header, findsOneWidget);
      expect(
        find.descendant(of: header, matching: find.text('Personas')),
        findsNothing,
      );
      // Sin «+» flotante: «Añadir regalo» va en la cabecera, relleno, junto a
      // «Editar».
      expect(find.byType(FloatingActionButton), findsNothing);
      final add = tester.getRect(_addGift);
      final headerRect = tester.getRect(header);
      expect(add.right, lessThan(headerRect.right));
      expect(add.top, greaterThanOrEqualTo(headerRect.top));
      expect(add.bottom, lessThanOrEqualTo(headerRect.bottom));
      await tester.tap(_addGift);
      await settle(tester);
      expect(find.text('Nuevo regalo'), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(Scaffold).last,
          matching: find.text('Aritz'),
        ),
        findsWidgets,
      );
    }, size: _desktop);

    screenTest('tocar otra persona cambia la URL y el detalle, sin apilar', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.tap(_row('Nora'));
      await settle(tester);
      expect(_path(phone), '/people/nora');
      expect(find.byType(PersonListScreen), findsOneWidget);
      expect(find.text('Cocinita de madera'), findsOneWidget);
      expect(find.text('Pijama de astronautas, talla 8'), findsNothing);
      await tester.tap(_row('Leo'));
      await settle(tester);
      expect(_path(phone), '/people/leo');
      expect(find.byType(PersonListScreen), findsOneWidget);
      // No se apilaron ni Nora ni Leo: debajo de la lista de Leo no hay otra
      // montada, ni siquiera fuera de la vista.
      expect(
        find.byType(PersonListScreen, skipOffstage: false),
        findsOneWidget,
      );
      expect(find.byType(PeopleListPane, skipOffstage: false), findsOneWidget);
      // El atrás del sistema es la salida de la app, no un paso atrás por
      // las personas tocadas: la pantalla se queda como está.
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(_path(phone), '/people/leo');
      expect(find.byType(PersonListScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, size: _desktop);

    screenTest('la fila elegida se marca como seleccionada', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      bool selected(String name) =>
          tester
              .getSemantics(find.bySemanticsLabel(RegExp('^$name\\.')).first)
              .getSemanticsData()
              .flagsCollection
              .isSelected ==
          Tristate.isTrue;
      expect(selected('Aritz'), isTrue);
      expect(selected('Nora'), isFalse);
      await tester.tap(_row('Nora'));
      await settle(tester);
      expect(selected('Aritz'), isFalse);
      expect(selected('Nora'), isTrue);
    }, size: _desktop);

    screenTest('el detalle cambia con un fundido de 120 ms y sin traslación; '
        'la lista no se mueve; los avatares no vuelan', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      final before = tester.getRect(_row('Leo'));
      await tester.tap(_row('Nora'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      // A mitad del cambio solo está la persona que llega (la que se va
      // desaparece en el acto), medio fundida y sin desplazarse.
      expect(find.byType(PersonListScreen), findsOneWidget);
      final fade = tester.widget<FadeTransition>(
        find
            .ancestor(
              of: find.byType(PersonListScreen),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fade.opacity.value, inExclusiveRange(0, 1));
      final shift = tester
          .widgetList<Transform>(
            find.ancestor(
              of: find.byType(PersonListScreen),
              matching: find.byType(Transform),
            ),
          )
          .map((t) => t.transform.getTranslation().y.abs())
          .fold<double>(0, (a, b) => a + b);
      expect(shift, 0);
      expect(tester.getRect(_row('Leo')), before);
      // Ningún avatar de tamaño intermedio: nada vuela entre la fila y la
      // cabecera.
      final sizes = [
        for (final a in tester.widgetList<PersonAvatar>(
          find.byType(PersonAvatar),
        ))
          a.size,
      ];
      expect(sizes.every((s) => s == 36 || s == 46), isTrue, reason: '$sizes');
      await settle(tester);
      expect(find.byType(PersonListScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, size: _desktop);

    screenTest('con «Reducir movimiento» el detalle solo se funde', (
      tester,
      phone,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.tap(_row('Nora'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final fading = tester.widgetList<FadeTransition>(
        find.ancestor(
          of: find.byType(PersonListScreen),
          matching: find.byType(FadeTransition),
        ),
      );
      expect(fading, isNotEmpty);
      await settle(tester);
      expect(_path(phone), '/people/nora');
      expect(tester.takeException(), isNull);
    }, size: _desktop);

    screenTest('la lista son filas planas de 64 y la próxima ocasión va en una '
        'fila de 56 sobre ella, sin carrusel', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      final list = _listPane(tester);
      final header = tester.getRect(find.byType(ScreenHeader).first);
      expect(header.left, list.left);
      expect(header.right, list.right);
      expect(_cards, findsNothing);
      expect(find.byType(SummaryColumn), findsNothing);
      expect(find.byType(UpcomingOccasionRow), findsOneWidget);
      final next = tester.getRect(find.byType(UpcomingOccasionRow));
      expect(next.height, 56);
      expect(next.left, list.left + 8);
      expect(next.right, list.right - 8);
      // Las personas: filas de 64 de paso, sin flecha, con el avatar de 36.
      final rows = [
        for (final name in ['Aritz', 'Leo', 'Nora']) tester.getRect(_row(name)),
      ];
      for (final row in rows) {
        expect(row.height, 60);
        expect(row.left, list.left + 8);
        expect(row.right, list.right - 8);
      }
      expect(rows[1].top - rows[0].top, 64);
      expect(rows[2].top - rows[1].top, 64);
      expect(rows[0].top, greaterThan(next.bottom));
      expect(
        find.descendant(
          of: find.byType(PeopleListPane),
          matching: find.byWidgetPredicate(
            (w) => w is PersonAvatar && w.size == 36,
          ),
        ),
        findsNWidgets(3),
      );
      expect(
        find.descendant(
          of: find.byType(PeopleListPane),
          matching: find.byType(PageView),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    }, size: _desktop);

    screenTest('el detalle usa todo su panel (791 de ancho, menos de 880)', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      final pane = _detailPane(tester);
      expect(pane.width, 791);
      final header = tester.getRect(
        find.descendant(
          of: find.byType(PersonListScreen),
          matching: find.byType(ScreenHeader),
        ),
      );
      expect(header.width, 791);
    }, size: _desktop);

    screenTest('estrechar la ventana: la persona que puso la app vuelve a '
        'Personas y la que eligió el usuario se queda con su flecha', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      expect(_path(phone), '/people/aritz');
      await setWindowSize(tester, kTabletPortrait);
      await settle(tester);
      expect(_path(phone), '/people');
      expect(find.byType(PersonListScreen), findsNothing);
      expect(find.byType(PeopleListPane), findsOneWidget);
      // De vuelta ancho: la misma persona, otra vez por defecto.
      await setWindowSize(tester, _desktop);
      await settle(tester);
      expect(_path(phone), '/people/aritz');
      expect(find.byType(PersonListScreen), findsOneWidget);

      // Ahora la elige el usuario.
      await tester.tap(_row('Nora'));
      await settle(tester);
      await setWindowSize(tester, kTabletPortrait);
      await settle(tester);
      expect(_path(phone), '/people/nora');
      expect(find.byType(PersonListScreen), findsOneWidget);
      expect(find.byType(PeopleListPane), findsNothing);
      expect(find.bySemanticsLabel('Volver a Personas'), findsOneWidget);
      await setWindowSize(tester, _desktop);
      await settle(tester);
      expect(_path(phone), '/people/nora');
      expect(find.byType(PeopleListPane), findsOneWidget);
      expect(find.byType(PersonListScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, size: _desktop);

    screenTest('volver a Personas lleva a la última persona abierta', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.tap(_row('Leo'));
      await settle(tester);
      await tapText(tester, 'Ajustes');
      await tapText(tester, 'Personas');
      // La rama conserva su pila: sigue en Leo.
      expect(_path(phone), '/people/leo');
      // Tocar de nuevo la pestaña activa vuelve a su raíz, que elige a la
      // última abierta.
      await tester.tap(find.text('Personas').first);
      await settle(tester);
      expect(_path(phone), '/people/leo');
    }, size: _desktop);

    screenTest('una hoja abierta desde la lista mide 560 y se centra en la '
        'pestaña, no en el panel de lista', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tapLabel(tester, 'Añadir persona');
      final sheet = tester.getRect(find.byType(BottomSheet));
      expect(sheet.width, 560);
      // El área de contenido: de 80 (el raíl) a 1280.
      expect(sheet.center.dx, 80 + 1200 / 2);
      expect(sheet.bottom, 800);
    }, size: _desktop);

    screenTest(
      'el editor abierto desde el detalle es un diálogo que usa su '
      'panel si mide menos de 880 y se centra en él',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tester.tap(_addGift);
        await settle(tester);
        final card = tester.getRect(find.byType(GiftEditorScreen));
        final pane = _detailPane(tester);
        expect(card.width, closeTo(pane.width < 880 ? pane.width : 880, 0.5));
        expect(card.center.dx, closeTo(pane.center.dx, 0.5));
        // Un diálogo: a un 10 % del borde superior y con el alto de su
        // contenido, no una hoja hasta abajo.
        expect(card.top, closeTo(80, 0.5));
        expect(card.bottom, lessThanOrEqualTo(800 - 24 + 0.5));
        // La lista de personas sigue donde estaba, a la vista.
        expect(_listPane(tester).left, 80);
      },
      size: _desktop,
      overrides: _webOn,
    );

    screenTest('el aviso de cambiar de estado mide 480 y sale abajo', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tapLabel(tester, RegExp('^Cambiar estado de Patinete'));
      expect(find.text('Deshacer'), findsOneWidget);
      // Lo que pinta el aviso: su forma dentro de su `Material`.
      final material = find
          .descendant(
            of: find.byType(SnackBar),
            matching: find.byType(Material),
          )
          .first;
      final bar = tester
          .widget<Material>(material)
          .shape!
          .getOuterPath(
            tester.getRect(material),
            textDirection: TextDirection.ltr,
          )
          .getBounds();
      expect(bar.width, 480);
      // Centrado en el área de contenido (de 80 a 1280), no en un panel.
      expect(bar.center.dx, closeTo(80 + 1200 / 2, 0.5));
      expect(bar.bottom, lessThanOrEqualTo(800));
      await settle(tester);
    }, size: _desktop);

    screenTest('sin personas, el vacío de siempre y sin detalle', (
      tester,
      phone,
    ) async {
      await bareFamily(tester, phone);
      await pumpRegalos(tester, phone);
      expect(find.text('Aún no hay personas'), findsOneWidget);
      expect(find.byType(PersonListScreen), findsNothing);
      expect(_path(phone), '/people');
      expect(find.byType(PaneScope), findsOneWidget);
    }, size: _desktop);
  });

  group('desde 1680', () {
    screenTest('la tercera columna es «Resumen»: la próxima ocasión como '
        'tarjeta, las demás en filas de 56 y el presupuesto abajo', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      expect(find.byType(SummaryColumn), findsOneWidget);
      expect(_cards, findsNothing);
      expect(find.byType(UpcomingOccasionRow), findsNWidgets(5));
      final column = tester.getRect(find.byType(SummaryColumn));
      expect(column.right, 1700);
      expect(
        find.descendant(
          of: find.byType(SummaryColumn),
          matching: find.text('Resumen'),
        ),
        findsOneWidget,
      );
      expect(find.text('Próximas ocasiones'), findsNothing);
      // La lista, el detalle y la columna, de izquierda a derecha.
      final list = _listPane(tester);
      final detail = _detailPane(tester);
      expect(list.right, lessThan(detail.left));
      expect(detail.right, lessThan(column.left));
      // La próxima ocasión, una tarjeta de 112 con la cifra de 44.
      final card = find.descendant(
        of: find.byType(SummaryColumn),
        matching: find.byType(OccasionCountdownCard),
      );
      expect(card, findsOneWidget);
      final first = tester.getRect(card);
      expect(first.height, 112);
      expect(first.left, column.left + 16);
      expect(first.right, column.right - 16);
      final number = tester.widget<Text>(
        find.descendant(
          of: find.descendant(of: card, matching: find.byType(RollingNumber)),
          matching: find.byType(Text),
        ),
      );
      expect(number.style!.fontSize, 44);
      // El resto, filas de 56 debajo, una detrás de otra.
      final rows = find.byType(UpcomingOccasionRow);
      for (var i = 0; i < 5; i++) {
        final row = tester.getRect(rows.at(i));
        expect(row.height, 56);
        expect(row.top, greaterThanOrEqualTo(first.bottom));
        if (i > 0) {
          expect(row.top, tester.getRect(rows.at(i - 1)).bottom);
        }
      }
      // El presupuesto de la casa, abajo del todo.
      final budget = find.descendant(
        of: find.byType(SummaryColumn),
        matching: find.text('La casa · total'),
      );
      expect(budget, findsOneWidget);
      expect(
        tester.getRect(budget).top,
        greaterThan(tester.getRect(rows.last).bottom),
      );
      expect(tester.takeException(), isNull);
    }, size: _desktopWide);

    screenTest('con 2560 de ancho el contenido del detalle se queda en 880', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      final detail = _detailPane(tester);
      final header = tester.getRect(
        find.descendant(
          of: find.byType(PersonListScreen),
          matching: find.byType(ScreenHeader),
        ),
      );
      expect(header.width, 880);
      expect(header.center.dx, closeTo(detail.center.dx, 0.01));
      expect(tester.takeException(), isNull);
    }, size: _huge);

    screenTest(
      '«Añadir regalo» va en la cabecera del detalle, a la izquierda de '
      'la columna',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        expect(find.byType(FloatingActionButton), findsNothing);
        final add = tester.getRect(_addGift);
        final column = tester.getRect(find.byType(SummaryColumn));
        expect(add.right, lessThan(column.left));
      },
      size: _desktopWide,
    );
  });

  group('el editor de regalo a dos columnas', () {
    /// Abre el editor con «Añadir regalo» del detalle.
    Future<void> openEditor(WidgetTester tester) async {
      await tester.tap(_addGift);
      await settle(tester);
      expect(find.byType(GiftEditorScreen), findsOneWidget);
    }

    /// El rectángulo del campo o título [text] dentro del editor.
    Rect at(WidgetTester tester, String text) => tester.getRect(
      find
          .descendant(
            of: find.byType(GiftEditorScreen),
            matching: find.text(text),
          )
          .first,
    );

    void expectTwoColumns(WidgetTester tester) {
      final left = [
        for (final t in ['Para quién', 'Quién regala', 'Ocasión', 'Estado'])
          at(tester, t),
      ];
      final right = [
        for (final t in ['Precio', 'Tienda', 'Enlace', 'Talla o edad'])
          at(tester, t),
      ];
      // Cada grupo en su columna: la derecha empieza a la derecha de toda la
      // izquierda, y los dos grupos arrancan arriba.
      final leftEdge = left.map((r) => r.right).reduce((a, b) => a > b ? a : b);
      for (final r in right) {
        expect(r.left, greaterThan(leftEdge - 1));
      }
      expect(
        (right.first.top - left.first.top).abs(),
        lessThan(120),
        reason: 'las dos columnas arrancan arriba',
      );
      // Los de la derecha van uno debajo de otro.
      for (var i = 1; i < right.length; i++) {
        expect(right[i].top, greaterThan(right[i - 1].top));
      }
    }

    screenTest(
      'a 1536 × 864 el diálogo mide 880, el formulario va en dos columnas y '
      '«Guardar» está a la vista',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await openEditor(tester);
        final card = tester.getRect(find.byType(GiftEditorScreen));
        expect(card.width, 880);
        expect(card.center.dx, closeTo(_detailPane(tester).center.dx, 0.5));
        expectTwoColumns(tester);
        // «Guardar» sin desplazarse: dentro de la ventana y de la tarjeta.
        final save = tester.getRect(
          find.descendant(
            of: find.byType(GiftEditorScreen),
            matching: find.byType(FilledButton),
          ),
        );
        expect(save.bottom, lessThanOrEqualTo(864));
        expect(save.top, greaterThan(card.top));
        // Y la columna de la derecha, entera a la vista (sin desplazarse).
        expect(at(tester, 'Talla o edad').bottom, lessThan(save.top));
        expect(tester.takeException(), isNull);
      },
      size: const Size(1536, 864),
      overrides: _webOn,
    );

    screenTest(
      'a 1280 × 800 también va en dos columnas (el diálogo, del ancho '
      'de su panel)',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await openEditor(tester);
        expect(
          tester.getRect(find.byType(GiftEditorScreen)).width,
          closeTo(_detailPane(tester).width, 0.5),
        );
        expectTwoColumns(tester);
        expect(tester.takeException(), isNull);
      },
      size: _desktop,
      overrides: _webOn,
    );

    screenTest(
      'con la letra al 130 % y en oscuro no se desborda',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await openEditor(tester);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1536, 864),
      textScale: 1.3,
      brightness: Brightness.dark,
    );

    screenTest(
      'por debajo de 1280 (1279 de ancho) sigue en una columna de 640',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await openEditor(tester);
        expect(tester.getRect(find.byType(GiftEditorScreen)).width, 640);
        // Todo en una columna: «Precio» por debajo de «Estado».
        expect(at(tester, 'Precio').top, greaterThan(at(tester, 'Estado').top));
        expect(
          at(tester, 'Precio').left,
          closeTo(at(tester, 'Estado').left, 1),
        );
      },
      size: const Size(1279, 800),
    );

    for (final size in [kPhoneSize, kTabletPortrait]) {
      screenTest('${sizeLabel(size)} no cambia: una columna', (
        tester,
        phone,
      ) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tapText(tester, 'Aritz');
        await tester.tap(find.byType(FloatingActionButton));
        await settle(tester);
        final card = tester.getRect(find.byType(GiftEditorScreen));
        expect(card.width, size == kPhoneSize ? 390 : 640);
        expect(at(tester, 'Precio').top, greaterThan(at(tester, 'Estado').top));
        expect(
          at(tester, 'Precio').left,
          closeTo(at(tester, 'Estado').left, 1),
        );
      }, size: size);
    }
  });

  group('«Añadir regalo» del detalle', () {
    screenTest('a 2560 va en la cabecera, dentro de la columna del detalle', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      final header = tester.getRect(
        find.descendant(
          of: find.byType(PersonListScreen),
          matching: find.byType(ScreenHeader),
        ),
      );
      final add = tester.getRect(_addGift);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(add.right, lessThanOrEqualTo(header.right));
      expect(add.left, greaterThan(header.center.dx));
      expect(add.height, 48);
    }, size: _huge);

    screenTest('a 1280 también, y es un botón relleno', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(tester.widget(_addGift), isA<DesktopAddGiftButton>());
      expect(tester.getRect(_addGift).right, lessThan(1280 - 16));
    }, size: _desktop);
  });

  group('teclado en Personas', () {
    screenTest('↑ y ↓ cambian de persona y no pasan de los extremos', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      expect(_path(phone), '/people/aritz');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await settle(tester);
      expect(_path(phone), '/people/aritz');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await settle(tester);
      expect(_path(phone), '/people/leo');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await settle(tester);
      expect(_path(phone), '/people/nora');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await settle(tester);
      expect(_path(phone), '/people/nora');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await settle(tester);
      expect(_path(phone), '/people/leo');
      expect(find.byType(PersonListScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, size: _desktop);

    screenTest(
      'N abre «Nuevo regalo» para la persona elegida y Esc lo cierra',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await settle(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
        await settle(tester);
        expect(find.byType(GiftEditorScreen), findsOneWidget);
        expect(find.text('Nuevo regalo'), findsWidgets);
        // La persona elegida, Leo, viene marcada.
        expect(
          find.descendant(
            of: find.byType(GiftEditorScreen),
            matching: find.text('Leo'),
          ),
          findsOneWidget,
        );
        // El diálogo se centra en el panel de detalle.
        expect(
          tester.getRect(find.byType(GiftEditorScreen)).center.dx,
          closeTo(_detailPane(tester).center.dx, 0.5),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(tester);
        expect(find.byType(GiftEditorScreen), findsNothing);
        expect(_path(phone), '/people/leo');
        expect(tester.takeException(), isNull);
      },
      size: _desktop,
    );

    screenTest('Esc también cierra una hoja de las de siempre', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tapLabel(tester, 'Añadir persona');
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.byType(BottomSheet), findsNothing);
    }, size: _desktop);

    screenTest(
      'con un campo de texto abierto, las flechas y la N no cambian de '
      'persona ni abren el editor',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        // La hoja de «Añadir persona» tiene un campo con el foco.
        await tapLabel(tester, 'Añadir persona');
        await tester.enterText(find.byType(TextField).first, 'x');
        await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(find.byType(GiftEditorScreen), findsNothing);
        expect(_path(phone), '/people/aritz');
      },
      size: _desktop,
    );

    screenTest('Tab enseña el foco y hacer clic lo quita', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      final ring = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is FocusRingPainter,
      );
      Rect? rect() =>
          (tester.widget<CustomPaint>(ring).painter! as FocusRingPainter).rect;
      expect(rect(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump();
      expect(rect(), isNotNull, reason: 'con teclado, el filete');
      await tester.tap(find.text('Nora').first);
      await tester.pump();
      await tester.pump();
      expect(rect(), isNull, reason: 'con el ratón, nada');
    }, size: _desktop);
  });

  group('ratón', () {
    screenTest(
      'al pasar el ratón por una fila se tiñe al instante con la tinta (7 %) y '
      'se destiñe en 120 ms',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        final row = find.ancestor(
          of: find.text('Nora'),
          matching: find.byType(PointerSurface),
        );
        Color tint() {
          final box = find.descendant(
            of: row.first,
            matching: find.byType(AnimatedContainer),
          );
          final decoration =
              tester.widget<AnimatedContainer>(box.first).decoration!
                  as BoxDecoration;
          return decoration.color!;
        }

        expect(tint().a, 0);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(find.text('Nora')));
        await tester.pump();
        // Entra en el mismo fotograma.
        await tester.pump(const Duration(milliseconds: 1));
        expect(tint().a, closeTo(0.07, 0.005));
        expect(
          tester
              .widget<AnimatedContainer>(
                find
                    .descendant(
                      of: row.first,
                      matching: find.byType(AnimatedContainer),
                    )
                    .first,
              )
              .duration,
          Duration.zero,
        );
        await mouse.moveTo(const Offset(1000, 600));
        await tester.pump();
        // La salida dura 120 ms; la entrada, nada.
        expect(
          tester
              .widget<AnimatedContainer>(
                find
                    .descendant(
                      of: row.first,
                      matching: find.byType(AnimatedContainer),
                    )
                    .first,
              )
              .duration,
          const Duration(milliseconds: 120),
        );
        await tester.pump(const Duration(milliseconds: 130));
        expect(tint().a, 0);
      },
      size: _desktop,
    );

    screenTest(
      'en oscuro el tinte es del 12 %',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        final box = find.descendant(
          of: find
              .ancestor(
                of: find.text('Nora'),
                matching: find.byType(PointerSurface),
              )
              .first,
          matching: find.byType(AnimatedContainer),
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(find.text('Nora')));
        await tester.pump(const Duration(milliseconds: 130));
        final decoration =
            tester.widget<AnimatedContainer>(box.first).decoration!
                as BoxDecoration;
        expect(decoration.color!.a, closeTo(0.12, 0.005));
      },
      size: _desktop,
      brightness: Brightness.dark,
    );

    screenTest('los botones de icono llevan ayuda con su texto accesible', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      expect(find.byTooltip('Añadir persona'), findsOneWidget);
      expect(find.byTooltip('Editar persona'), findsOneWidget);
      // «Añadir regalo» ya no es un botón de icono: lleva su texto.
      expect(_addGift, findsOneWidget);
    }, size: _desktop);
  });

  group('entrada escalonada', () {
    // La entrada del panel que lleva [screen]: la opacidad que pinta.
    double opacity(WidgetTester tester, Type screen) {
      final entrance = find.ancestor(
        of: find.byType(screen),
        matching: find.byType(PaneEntrance),
      );
      return tester
          .widget<FadeTransition>(
            find
                .descendant(
                  of: entrance.first,
                  matching: find.byType(FadeTransition),
                )
                .first,
          )
          .opacity
          .value;
    }

    Future<void> openOccasionsTab(WidgetTester tester) async {
      await tester.tap(
        find.descendant(
          of: find.bySemanticsLabel('Navegación principal'),
          matching: find.text('Ocasiones'),
        ),
      );
      // Hasta que el router monta la pestaña.
      for (
        var i = 0;
        i < 6 && find.byType(OccasionsScreen).evaluate().isEmpty;
        i++
      ) {
        await tester.pump();
      }
      // La entrada arranca en el fotograma siguiente.
      await tester.pump(const Duration(milliseconds: 1));
    }

    screenTest(
      'al entrar en una pestaña la lista llega primero, el detalle 40 ms '
      'después',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await openOccasionsTab(tester);
        await tester.pump(const Duration(milliseconds: 100));
        final list = opacity(tester, OccasionsScreen);
        final detail = opacity(tester, OccasionDetailScreen);
        expect(list, greaterThan(0));
        expect(list, lessThan(1));
        expect(detail, lessThan(list), reason: 'el detalle va por detrás');
        await settle(tester);
        expect(opacity(tester, OccasionsScreen), 1);
        expect(opacity(tester, OccasionDetailScreen), 1);
        expect(tester.takeException(), isNull);
      },
      size: _desktop,
    );

    screenTest('con «Reducir movimiento» solo se funden, a la vez', (
      tester,
      phone,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openOccasionsTab(tester);
      await tester.pump(const Duration(milliseconds: 75));
      final list = opacity(tester, OccasionsScreen);
      expect(list, greaterThan(0));
      expect(list, lessThan(1));
      expect(opacity(tester, OccasionDetailScreen), list);
      await tester.pump(const Duration(milliseconds: 100));
      expect(opacity(tester, OccasionsScreen), 1);
    }, size: _desktop);

    screenTest(
      'cambiar el tamaño de la ventana no anima nada, ni se repite al volver '
      'a la pestaña',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await openOccasionsTab(tester);
        await settle(tester);
        await setWindowSize(tester, const Size(1500, 800));
        expect(opacity(tester, OccasionsScreen), 1);
        expect(opacity(tester, OccasionDetailScreen), 1);
        // De Ocasiones a Personas y otra vez a Ocasiones: no se repite.
        await tapText(tester, 'Personas');
        await openOccasionsTab(tester);
        await tester.pump(const Duration(milliseconds: 60));
        expect(opacity(tester, OccasionsScreen), 1);
        expect(opacity(tester, OccasionDetailScreen), 1);
      },
      size: _desktop,
    );
  });

  group('barra de desplazamiento', () {
    screenTest(
      'el tema la deja fina, con el borde de control y más marcada al pasar el ratón',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        final context = tester.element(find.byType(PeopleListPane));
        final theme = Theme.of(context);
        final t = RegalosTokens.of(context);
        expect(theme.scrollbarTheme.thickness!.resolve({}), 6);
        final thumb = theme.scrollbarTheme.thumbColor!;
        expect(thumb.resolve({}), t.outline);
        final hover = thumb.resolve({WidgetState.hovered})!;
        expect(hover, isNot(t.outline));
        // Al pasar el ratón se acerca al texto: más contraste con el fondo.
        expect(
          (hover.computeLuminance() - t.bg.computeLuminance()).abs(),
          greaterThan(
            (t.outline.computeLuminance() - t.bg.computeLuminance()).abs(),
          ),
        );
      },
      size: _desktop,
    );
  });

  group('por debajo de 840 todo sigue en un panel', () {
    tabletScreenTest(
      'un solo panel: Personas sin detalle, sin tercera columna y sin '
      'cambiar de ruta',
      (tester, phone, size) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        expect(_path(phone), '/people');
        expect(find.byType(PeopleListPane), findsOneWidget);
        expect(find.byType(PersonListScreen), findsNothing);
        expect(find.byType(SummaryColumn), findsNothing);
        expect(_cards, findsOneWidget);
        expect(find.byType(PaneScope), findsOneWidget);
        expect(find.byType(FloatingActionButton), findsOneWidget);
        // Tocar una persona abre su lista encima, con flecha de volver.
        await tapText(tester, 'Nora');
        expect(_path(phone), '/people/nora');
        expect(find.byType(PersonListScreen), findsOneWidget);
        expect(find.bySemanticsLabel('Volver a Personas'), findsOneWidget);
        await tester.tap(find.bySemanticsLabel('Volver a Personas'));
        await settle(tester);
        expect(_path(phone), '/people');
      },
      sizes: const [kPhoneSize, kTabletPortrait],
    );
  });

  group('la selección de Personas', () {
    const ids = ['aritz', 'leo', 'nora'];

    test('con un panel, /people se queda donde está', () {
      final selection = PaneSelection();
      expect(selection.redirectPeople('/people', ids), isNull);
      selection.dispose();
    });

    test('con dos paneles, /people lleva a la primera, y luego a la última '
        'abierta', () {
      final selection = PaneSelection()..twoPanes.value = true;
      expect(selection.redirectPeople('/people', ids), '/people/aritz');
      expect(selection.autoPerson, 'aritz');
      // Una persona de la URL se anota; la elegida por el usuario no es de
      // la app.
      selection.userChose('nora');
      expect(selection.redirectPeople('/people/nora', ids), isNull);
      expect(selection.autoPerson, isNull);
      expect(selection.redirectPeople('/people', ids), '/people/nora');
      // Si ya no existe, la primera.
      expect(selection.redirectPeople('/people', ['leo']), '/people/leo');
      // Sin personas no hay a dónde llevar.
      expect(selection.redirectPeople('/people', const []), isNull);
      selection.dispose();
    });

    test('al estrechar, la persona de la app vuelve a la lista y la del '
        'usuario se queda', () {
      final selection = PaneSelection()..twoPanes.value = true;
      selection.redirectPeople('/people', ids);
      selection.twoPanes.value = false;
      expect(selection.redirectPeople('/people/aritz', ids), '/people');
      expect(selection.autoPerson, isNull);

      selection.twoPanes.value = true;
      selection.redirectPeople('/people', ids);
      selection.userChose('leo');
      selection.twoPanes.value = false;
      expect(selection.redirectPeople('/people/leo', ids), isNull);
      selection.dispose();
    });

    test('otras rutas no se tocan', () {
      final selection = PaneSelection()..twoPanes.value = true;
      expect(selection.redirectPeople('/family', ids), isNull);
      expect(selection.redirectPeople('/occasions/budget', ids), isNull);
      expect(selection.redirectPeople('/people/aritz/extra', ids), isNull);
      selection.dispose();
    });
  });

  group('puntos de corte y medidas', () {
    test('los cortes de escritorio son 1280 y 1600', () {
      expect(RegalosLayout.isDesktop(1279.9), isFalse);
      expect(RegalosLayout.isDesktop(1280), isTrue);
      expect(RegalosLayout.isDesktopWide(1599.9), isFalse);
      expect(RegalosLayout.isDesktopWide(1600), isTrue);
      expect(WindowClass.fromSize(const Size(1280, 720)).usesTwoPanes, isTrue);
      expect(WindowClass.fromSize(const Size(839, 900)).usesTwoPanes, isFalse);
    });

    test('lista de 360 a 420, columna de 320 a 360, detalle de 720 u 880', () {
      expect(RegalosLayout.listPaneWidth(760), 340);
      expect(RegalosLayout.listPaneWidth(760, desktop: true), 360);
      expect(
        RegalosLayout.listPaneWidth(1200, desktop: true),
        closeTo(408, 0.01),
      );
      expect(RegalosLayout.listPaneWidth(2480, desktop: true), 420);
      expect(RegalosLayout.asideWidth(1600), 320);
      expect(RegalosLayout.asideWidth(1800), 360);
      expect(RegalosLayout.asideWidth(2320), 360);
      expect(RegalosLayout.detailMaxWidthFor(1279), 720);
      expect(RegalosLayout.detailMaxWidthFor(1280), 880);
    });
  });
}
