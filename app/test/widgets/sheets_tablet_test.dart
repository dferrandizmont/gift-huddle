import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/layout/pane_scope.dart';
import 'package:regalos/core/widgets/choice_grid.dart';
import 'package:regalos/core/widgets/confirm_dialog.dart';
import 'package:regalos/core/widgets/regalos_snack_bar.dart';
import 'package:regalos/core/widgets/status_chip.dart';
import 'package:regalos/features/gifts/presentation/gift_editor_screen.dart';
import 'package:regalos/features/gifts/presentation/person_list_screen.dart';

import '../helpers/pump_app.dart';
import '../helpers/screens.dart';
import '../helpers/tablet.dart';
import 'motion_shared_test.dart' show moving;

// Tanda T4 del plan de tablet (la guía de diseño para tablet, §6): las hojas
// miden 560 y el editor 640, centrados en el área de contenido (la ventana
// menos el raíl); el velo cubre la ventana; los avisos miden 480 y los
// diálogos, 340. En el móvil, todo de lado a lado como siempre.

/// El área de contenido: el panel de la pestaña, que sigue debajo de la hoja.
// Con dos paneles hay más `PaneScope` dentro: el área es el primero. Los dos
// paneles se prueban en `test/app/two_pane_web_test.dart`; aquí, un panel.
Rect _area(WidgetTester tester) => tester.getRect(find.byType(PaneScope).first);

const _onePane = [kPhoneSize, kTabletPortrait];

final _sheet = find.byType(BottomSheet);
final _editor = find.byType(GiftEditorScreen);

/// Comprueba el rectángulo de la hoja abierta: 560 centrados en el área de
/// contenido y pegada abajo; en el móvil, de lado a lado.
void _expectSheet(WidgetTester tester, Size size) {
  final sheet = tester.getRect(_sheet);
  if (size == kPhoneSize) {
    expect(sheet.left, 0);
    expect(sheet.width, 390);
  } else {
    expect(sheet.width, 560);
    expect(sheet.center.dx, _area(tester).center.dx);
    // No es el centro de la ventana: el raíl empuja 40.
    expect(sheet.center.dx, size.width / 2 + 40);
  }
  expect(sheet.bottom, size.height);
}

/// Comprueba el rectángulo de la tarjeta del editor: 640 centrados en el área
/// de contenido, a 12 del borde superior y hasta abajo.
void _expectEditor(WidgetTester tester, Size size) {
  final card = tester.getRect(_editor);
  if (size == kPhoneSize) {
    expect(card.left, 0);
    expect(card.width, 390);
  } else {
    expect(card.width, 640);
    expect(card.center.dx, _area(tester).center.dx);
  }
  expect(card.top, 12);
  expect(card.bottom, size.height);
}

/// El rectángulo que pinta el aviso: su forma dentro de su `Material`.
Rect _snackRect(WidgetTester tester) {
  final material = find
      .descendant(of: find.byType(SnackBar), matching: find.byType(Material))
      .first;
  return tester
      .widget<Material>(material)
      .shape!
      .getOuterPath(tester.getRect(material), textDirection: TextDirection.ltr)
      .getBounds();
}

/// El velo de la ruta de arriba.
Rect _barrier(WidgetTester tester) =>
    tester.getRect(find.byType(ModalBarrier).last);

Future<void> _openPerson(WidgetTester tester) => tapText(tester, 'Aritz');

/// Abre la lista de Aritz y la desplaza hasta que se vea el regalo [title]
/// (en el móvil y en horizontal queda por debajo de la pantalla).
Future<void> _openPersonAt(WidgetTester tester, String title) async {
  await _openPerson(tester);
  await tester.scrollUntilVisible(
    find.text(title),
    120,
    scrollable: find
        .descendant(
          of: find.byType(PersonListScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await settle(tester);
}

Future<void> _openNewGift(WidgetTester tester) async {
  await _openPerson(tester);
  await tester.tap(find.byType(FloatingActionButton));
  await settle(tester);
  expect(find.text('Nuevo regalo'), findsOneWidget);
}

/// Desplaza la lista del editor hasta que se vea [finder].
Future<void> _scrollEditorTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    120,
    scrollable: find
        .descendant(of: _editor, matching: find.byType(Scrollable))
        .first,
  );
  await settle(tester);
}

void main() {
  group('hojas', () {
    tabletScreenTest(
      'la hoja de edición mide 560, va centrada en el área de contenido y su '
      'velo cubre el raíl; tocar el velo la cierra',
      (tester, phone, size) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tapLabel(tester, 'Añadir persona');
        expect(find.widgetWithText(TextField, 'Nombre'), findsOneWidget);
        _expectSheet(tester, size);
        expect(_barrier(tester), Offset.zero & size);

        // El velo, sobre el raíl (o arriba a la izquierda en el móvil).
        await tester.tapAt(const Offset(40, 300));
        await settle(tester);
        expect(_sheet, findsNothing);
        expect(tester.takeException(), isNull);
      },
      sizes: _onePane,
    );

    tabletScreenTest(
      'la hoja de filtros mide 560 y lleva tres rejillas, como el editor',
      (tester, phone, size) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openPerson(tester);
        await tapText(tester, 'Filtros');
        expect(find.text('Filtrar regalos'), findsOneWidget);
        _expectSheet(tester, size);

        final grids = find.descendant(
          of: _sheet,
          matching: find.byType(ChoiceGrid),
        );
        expect(grids, findsNWidgets(3));
        expect(
          find.descendant(of: _sheet, matching: find.byType(StatusChip)),
          findsNothing,
        );
        // Las rejillas ocupan el ancho de la hoja menos sus márgenes.
        final sheet = tester.getRect(_sheet);
        for (final grid in grids.evaluate()) {
          final rect = tester.getRect(
            find.byElementPredicate((e) => e == grid),
          );
          expect(rect.left, sheet.left + 16);
          expect(rect.right, sheet.right - 16);
        }

        // Sin filtros, la elegida de cada grupo es «cualquiera».
        Finder cell(String label) =>
            find.descendant(of: _sheet, matching: find.bySemanticsLabel(label));
        expect(
          tester.getSemantics(cell('Todas')).flagsCollection.isSelected,
          Tristate.isTrue,
        );
        await tester.tap(
          find.descendant(of: _sheet, matching: find.text('Reyes')),
        );
        await settle(tester);
        expect(
          tester.getSemantics(cell('Reyes')).flagsCollection.isSelected,
          Tristate.isTrue,
        );
        expect(
          tester.getSemantics(cell('Todas')).flagsCollection.isSelected,
          Tristate.isFalse,
        );
        await tester.tap(
          find.descendant(of: _sheet, matching: find.text('Envuelto')),
        );
        await settle(tester);
        await tapText(tester, 'Hecho');
        expect(find.bySemanticsLabel('Quitar filtro Reyes'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      sizes: _onePane,
    );

    tabletScreenTest(
      'la hoja de estado (pulsación larga) mide 560 y lleva la rejilla de '
      'los seis estados',
      (tester, phone, size) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openPersonAt(tester, 'Patinete');
        await tester.longPress(find.text('Patinete'));
        await settle(tester);
        expect(find.text('Estado de Patinete'), findsOneWidget);
        _expectSheet(tester, size);
        expect(_barrier(tester), Offset.zero & size);

        expect(
          find.descendant(of: _sheet, matching: find.byType(ChoiceGrid)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: _sheet, matching: find.byType(StatusChip)),
          findsNothing,
        );
        for (final name in [
          'Idea',
          'Decidido',
          'Comprado',
          'Llegó',
          'Envuelto',
          'Entregado',
        ]) {
          expect(
            find.descendant(of: _sheet, matching: find.text(name)),
            findsOneWidget,
          );
        }
        // Tres columnas de 44 de alto como mínimo: dos filas.
        final idea = tester.getRect(
          find.descendant(of: _sheet, matching: find.bySemanticsLabel('Idea')),
        );
        final wrapped = tester.getRect(
          find.descendant(
            of: _sheet,
            matching: find.bySemanticsLabel('Envuelto'),
          ),
        );
        expect(idea.height, greaterThanOrEqualTo(44));
        expect(wrapped.top, greaterThan(idea.bottom));
        expect(wrapped.width, idea.width);

        await tester.tap(
          find.descendant(of: _sheet, matching: find.text('Envuelto')),
        );
        await settle(tester);
        expect(_sheet, findsNothing);
        expect(
          find.bySemanticsLabel(
            'Cambiar estado de Patinete. Estado actual: Envuelto',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
      sizes: _onePane,
    );

    tabletScreenTest(
      'con «Reducir movimiento» la hoja no se desliza y mide lo mismo',
      (tester, phone, size) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openPerson(tester);
        await tester.tap(find.text('Filtros'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        _expectSheet(tester, size);
        expect(moving(tester, _sheet), isEmpty);
        await settle(tester);
        _expectSheet(tester, size);
      },
      sizes: _onePane,
    );
  });

  group('editor de regalo', () {
    tabletScreenTest(
      'la tarjeta mide 640, sube a 12 del borde y va centrada en el área de '
      'contenido; el velo cubre el raíl y tocarlo no la cierra',
      (tester, phone, size) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openPerson(tester);
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        // Sube desde abajo: a medio camino sigue por debajo de su sitio.
        expect(moving(tester, find.byType(Overlay).first), isNotEmpty);
        await settle(tester);
        _expectEditor(tester, size);
        expect(_barrier(tester), Offset.zero & size);

        await tester.tapAt(const Offset(40, 300));
        await settle(tester);
        if (size != kPhoneSize) {
          expect(find.text('Nuevo regalo'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
      sizes: _onePane,
    );

    tabletScreenTest(
      'un selector abierto desde el editor se centra en el mismo panel',
      (tester, phone, size) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openNewGift(tester);
        await tapLabel(tester, RegExp('^Para quién'));
        _expectSheet(tester, size);
        await tester.tap(
          find.descendant(of: _sheet, matching: find.text('Nora')),
        );
        await settle(tester);
        expect(_sheet, findsNothing);
        expect(find.bySemanticsLabel('Para quién, Nora'), findsOneWidget);
        _expectEditor(tester, size);
        expect(tester.takeException(), isNull);
      },
      sizes: _onePane,
    );

    screenTest(
      'girar con el editor a medio escribir conserva lo escrito y lo elegido, '
      'y la tarjeta se recoloca',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openNewGift(tester);
        await tester.enterText(
          find.widgetWithText(TextField, 'Regalo'),
          'Bici nueva',
        );
        await tester.tap(
          find.descendant(of: _editor, matching: find.text('Comprado')),
        );
        await settle(tester);
        final state = tester.state(_editor);
        _expectEditor(tester, kTabletPortrait);

        await rotate(tester);
        await settle(tester);
        expect(windowSize(tester), kTabletLandscape);
        expect(tester.state(_editor), same(state));
        expect(find.text('Bici nueva'), findsOneWidget);
        expect(
          tester
              .getSemantics(
                find.descendant(
                  of: _editor,
                  matching: find.bySemanticsLabel('Comprado'),
                ),
              )
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );
        _expectEditor(tester, kTabletLandscape);

        await rotate(tester);
        await settle(tester);
        expect(find.text('Bici nueva'), findsOneWidget);
        _expectEditor(tester, kTabletPortrait);
        expect(tester.takeException(), isNull);
      },
      size: kTabletPortrait,
    );

    tabletScreenTest(
      'con el teclado abierto el campo activo queda a la vista',
      (tester, phone, size) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openNewGift(tester);
        final note = find.widgetWithText(TextField, 'Nota');
        await _scrollEditorTo(tester, note);

        // Como en el aparato: primero se toca el campo y después sube el
        // teclado.
        const keyboard = 360.0;
        await tester.showKeyboard(note);
        tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
        addTearDown(tester.view.resetViewInsets);
        await tester.pump();
        await settle(tester);
        final field = tester.getRect(note);
        expect(field.bottom, lessThanOrEqualTo(size.height - keyboard));
        expect(field.top, greaterThanOrEqualTo(12));
        // «Guardar» también queda sobre el teclado.
        expect(
          tester.getRect(find.text('Guardar')).bottom,
          lessThanOrEqualTo(size.height - keyboard),
        );
        expect(tester.takeException(), isNull);
      },
      sizes: _onePane,
    );
  });

  group('diálogos', () {
    tabletScreenTest(
      'el de confirmación mide 340 y va centrado en la ventana',
      (tester, phone, size) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openPersonAt(tester, 'Patinete');
        await tapText(tester, 'Patinete');
        await _scrollEditorTo(tester, find.text('Borrar regalo'));
        await tapText(tester, 'Borrar regalo');
        expect(find.text('¿Borrar «Patinete»?'), findsOneWidget);
        final dialog = tester.getRect(
          find
              .descendant(
                of: find.byType(ConfirmDialog),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(dialog.width, size == kPhoneSize ? 326 : 340);
        expect(dialog.center.dx, size.width / 2);
        await tapText(tester, 'Cancelar');
        expect(tester.takeException(), isNull);
      },
      sizes: _onePane,
    );

    tabletScreenTest('el de «Posible duplicado» no pasa de 340', (
      tester,
      phone,
      size,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tapText(tester, 'Nora');
      await tester.tap(find.byType(FloatingActionButton));
      await settle(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Regalo'),
        'Puzle 48 piezas',
      );
      await tapText(tester, 'Guardar');
      expect(find.text('Posible duplicado'), findsOneWidget);
      final dialog = tester.getRect(
        find
            .descendant(
              of: find.byType(RegalosDialogSurface),
              matching: find.byType(Material),
            )
            .first,
      );
      // El diálogo de la app: 340 como mucho y, en el móvil, de margen a
      // margen (32 por lado), como el de borrar.
      expect(dialog.width, size == kPhoneSize ? 326 : 340);
      expect(dialog.center.dx, size.width / 2);
      await tapText(tester, 'Revisar');
      expect(tester.takeException(), isNull);
    }, sizes: _onePane);
  });

  group('avisos', () {
    tabletScreenTest(
      'miden 480 y van abajo, centrados en el área de contenido; en el '
      'móvil, de lado a lado con su margen',
      (tester, phone, size) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openPersonAt(tester, 'Patinete');
        await tapLabel(tester, RegExp('^Cambiar estado de Patinete'));
        expect(find.text('Deshacer'), findsOneWidget);
        final bar = _snackRect(tester);
        if (size == kPhoneSize) {
          expect(bar.left, 15);
          expect(bar.right, 375);
        } else {
          expect(bar.width, 480);
          expect(bar.center.dx, _area(tester).center.dx);
          expect(bar.bottom, lessThan(size.height));
          expect(bar.bottom, greaterThan(size.height - 40));
        }
        // «Deshacer» sigue dentro de lo que se pinta y se puede pulsar.
        final undo = tester.getRect(find.text('Deshacer'));
        expect(undo.left, greaterThan(bar.left));
        expect(undo.right, lessThan(bar.right));
        await tapText(tester, 'Deshacer');
        expect(
          find.bySemanticsLabel(
            RegExp('^Cambiar estado de Patinete. Estado actual: Idea'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
      sizes: _onePane,
    );

    tabletScreenTest(
      'junto al raíl, el hueco de su izquierda deja pasar los toques',
      (tester, phone, size) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openPersonAt(tester, 'Patinete');
        await tapLabel(tester, RegExp('^Cambiar estado de Patinete'));
        final bar = _snackRect(tester);
        final host = tester.getRect(
          find
              .descendant(
                of: find.byType(SnackBar),
                matching: find.byType(Material),
              )
              .first,
        );
        // El aviso que centra el `Scaffold` es un raíl más ancho; a su
        // izquierda no hay nada que pintar ni que tocar.
        expect(host.width, 560);
        expect(host.center.dx, size.width / 2);
        expect(bar.left, host.left + 80);
        final result = tester.hitTestOnBinding(
          Offset(host.left + 40, bar.center.dy),
        );
        final material = tester.renderObject(
          find
              .descendant(
                of: find.byType(SnackBar),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(result.path.map((e) => e.target), isNot(contains(material)));
      },
      sizes: const [kTabletPortrait],
    );

    tabletScreenTest(
      'el de «borrado», que sale al cerrarse el editor, también va centrado '
      'en el área de contenido',
      (tester, phone, size) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openPersonAt(tester, 'Patinete');
        await tapText(tester, 'Patinete');
        await _scrollEditorTo(tester, find.text('Borrar regalo'));
        await tapText(tester, 'Borrar regalo');
        await tapText(tester, 'Borrar');
        expect(find.text('«Patinete» borrado'), findsOneWidget);
        final bar = _snackRect(tester);
        expect(bar.width, 480);
        expect(bar.center.dx, _area(tester).center.dx);
        expect(tester.takeException(), isNull);
      },
      sizes: const [kTabletPortrait],
    );

    screenTest('girar con un aviso a la vista no lanza nada y sigue centrado', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openPersonAt(tester, 'Patinete');
      await tapLabel(tester, RegExp('^Cambiar estado de Patinete'));
      expect(find.text('Deshacer'), findsOneWidget);
      await rotate(tester);
      await tester.pump();
      expect(tester.takeException(), isNull);
      final bar = _snackRect(tester);
      expect(bar.width, 480);
      expect(bar.center.dx, _area(tester).center.dx);
      await settle(tester);
    }, size: kTabletPortrait);

    tabletWidgetTest(
      'fuera de las pestañas (una ruta con su propio Scaffold) mide 480 y se '
      'centra en ella; en una ventana compacta no se toca',
      (tester, size) async {
        late BuildContext context;
        await pumpThemed(
          tester,
          Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
          surfaceSize: size,
        );
        const original = SnackBar(content: Text('Aviso'));
        final wide = regalosSnackBar(context, original);
        expect(wide.width, 480);
        expect(wide.shape, isNull);
        expect(wide.content, same(original.content));
        // Quien ya dio sus medidas las conserva.
        const sized = SnackBar(content: Text('Aviso'), width: 300);
        expect(regalosSnackBar(context, sized), same(sized));

        showRegalosSnackBar(context, original);
        await tester.pumpAndSettle();
        final bar = _snackRect(tester);
        expect(bar.width, 480);
        expect(bar.center.dx, size.width / 2);

        // Compacto: el mismo aviso, sin tocar.
        await setWindowSize(tester, kPhoneSize);
        expect(regalosSnackBar(context, original), same(original));
      },
    );
  });
}
