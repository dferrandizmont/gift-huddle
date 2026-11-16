import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/layout/pane_scope.dart';
import 'package:regalos/core/layout/window_class.dart';
import 'package:regalos/core/widgets/countdown_card.dart';
import 'package:regalos/core/widgets/regalos_switch.dart';
import 'package:regalos/core/widgets/screen_header.dart';
import 'package:regalos/core/widgets/section_header.dart';
import 'package:regalos/core/widgets/settings_row.dart';
import 'package:regalos/features/settings/presentation/manage_screens.dart';
import 'package:regalos/features/settings/presentation/settings_screen.dart';

import '../helpers/memory_stores.dart';
import '../helpers/pump_app.dart';
import '../helpers/screens.dart';
import '../helpers/settings_column.dart';
import '../helpers/tablet.dart';

// Tanda T2 del plan de tablet (la guía de diseño para tablet, §6): Ajustes y
// sus apartados van en una columna de 560 centrada en el área de contenido;
// en el móvil no cambia nada.

/// Los apartados de Ajustes que abren una pantalla: la fila y el título.
const _sections = <(String, String)>[
  ('Personas', 'Personas'),
  ('Quién regala', 'Quién regala'),
  ('Ocasiones', 'Ocasiones'),
  ('Archivo', 'Archivo'),
  ('Bloqueo', 'Bloqueo'),
  ('Apariencia', 'Apariencia'),
  ('Móviles de la familia', 'Móviles de la familia'),
  ('Copia de seguridad', 'Copia de seguridad'),
  ('Código de recuperación', 'Código de recuperación'),
  ('Acerca de Gift Huddle', 'Acerca de'),
];

Finder _row(String title) => find.widgetWithText(SettingsRow, title);

/// La familia de muestra con Leo archivado, para que Archivo tenga algo.
Future<void> _seed(
  WidgetTester tester,
  FakePhone phone, {
  int extraPeople = 0,
}) async {
  await seedSample(tester, phone, extraPeople: extraPeople);
  await tester.runAsync(
    () => familyOf(phone).archiveRecipient('leo', archived: true),
  );
}

Future<void> _back(WidgetTester tester) => tapLabel(tester, 'Volver a Ajustes');

/// Abre cada apartado, comprueba que va en la columna y vuelve.
Future<void> _walk(
  WidgetTester tester, {
  void Function(String title)? inside,
}) async {
  for (final (row, title) in _sections) {
    await tapVisible(tester, _row(row));
    expect(
      find.descendant(
        of: find.byType(ScreenHeader),
        matching: find.text(title),
      ),
      findsOneWidget,
      reason: 'se abre $title',
    );
    expectColumnScreen(tester);
    inside?.call(title);
    await _back(tester);
    expect(find.text('Compartir y copia'), findsOneWidget, reason: 'vuelve');
  }
}

ScrollPosition _scroll(WidgetTester tester, Type screen) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(screen),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

void main() {
  tabletScreenTest(
    'Ajustes va en una columna de 560 centrada, con el valor junto al título',
    (tester, phone, size) async {
      await _seed(tester, phone);
      await pumpRegalos(tester, phone);
      await openSettingsTab(tester);

      final column = settingsColumn(tester);
      if (size == kPhoneSize) {
        expect(column.left, 0);
        expect(column.width, 390, reason: 'el móvil sigue de lado a lado');
      } else {
        expect(column.width, 560);
      }
      expectColumnScreen(tester);
      // Todas las filas y las cabeceras de grupo, de un borde a otro de la
      // columna: las que se ven al entrar…
      expect(
        find.byType(SettingsRow).evaluate().length,
        greaterThanOrEqualTo(8),
      );
      expectFillsColumn(tester, find.byType(SettingsRow));
      expectFillsColumn(tester, find.byType(SectionHeader));

      // El valor queda a la derecha de su fila, dentro de la columna.
      for (final (row, value) in const [
        ('Personas', '2'),
        ('Quién regala', '6'),
        ('Archivo', '1'),
        ('Este móvil es de', 'Nadie'),
        ('Idioma', 'Sistema'),
      ]) {
        final title = tester.getRect(
          find.descendant(of: _row(row), matching: find.text(row)),
        );
        final shown = tester.getRect(
          find.descendant(of: _row(row), matching: find.text(value)),
        );
        expect(title.left, greaterThanOrEqualTo(column.left), reason: row);
        expect(shown.right, lessThan(column.right), reason: row);
        expect(
          shown.right - title.left,
          lessThan(RegalosLayout.formColumn),
          reason: 'el valor de $row, junto a su título',
        );
      }

      // …y las del final de la lista.
      final position = _scroll(tester, SettingsScreen);
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      expect(_row('Borrar todo'), findsOneWidget);
      expect(_row('Acerca de Gift Huddle'), findsOneWidget);
      expectFillsColumn(tester, find.byType(SettingsRow));
      expectFillsColumn(tester, find.byType(SectionHeader));
    },
    // Con dos paneles la lista de apartados mide la de su panel (ver
    // `two_pane_settings_test.dart`).
    sizes: const [kPhoneSize, kTabletPortrait],
  );

  tabletScreenTest(
    'las filas que abren una hoja o un diálogo se siguen pudiendo pulsar',
    (tester, phone, size) async {
      await _seed(tester, phone);
      await pumpRegalos(tester, phone);
      await openSettingsTab(tester);

      await tapVisible(tester, _row('Este móvil es de'));
      expect(find.text('¿De quién es este móvil?'), findsOneWidget);
      await tester.tap(
        find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.text('Nora'),
            )
            .first,
      );
      await settleSaved(tester);
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        find.descendant(
          of: _row('Este móvil es de'),
          matching: find.text('Nora'),
        ),
        findsOneWidget,
      );

      await tapVisible(tester, _row('Idioma'));
      expect(find.byType(BottomSheet), findsOneWidget);
      await tapText(tester, 'Català');
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Ajustos'), findsWidgets);
      await tapVisible(tester, find.widgetWithText(SettingsRow, 'Idioma'));
      await tapText(tester, 'Español');

      await tapVisible(tester, _row('Borrar todo'));
      expect(find.text('¿Borrar todo?'), findsOneWidget);
      await tapText(tester, 'Cancelar');
      expect(find.text('¿Borrar todo?'), findsNothing);
      if (size == kTabletLandscape) {
        // Con dos paneles, las filas miden su panel de lista (con 8 px de
        // margen); el apartado elegido va a la derecha.
        final list = tester.getRect(find.byType(SettingsScreen));
        for (final element in find.byType(SettingsRow).evaluate()) {
          final rect = tester.getRect(
            find.byElementPredicate((e) => e == element),
          );
          expect(rect.left, closeTo(list.left + 8, 0.01));
          expect(rect.right, closeTo(list.right - 8, 0.01));
        }
      } else {
        expectFillsColumn(tester, find.byType(SettingsRow));
      }
    },
    sizes: kLayoutSizes,
  );

  tabletScreenTest(
    'cada apartado de Ajustes va en la columna y se vuelve con la flecha',
    (tester, phone, size) async {
      await _seed(tester, phone);
      await pumpRegalos(tester, phone);
      await openSettingsTab(tester);

      await _walk(
        tester,
        inside: (title) {
          switch (title) {
            case 'Personas':
              expect(find.byType(ManageRow), findsNWidgets(2));
              expectFillsColumn(tester, find.byType(ManageRow));
              // El botón de añadir, a todo el ancho de la columna con sus
              // márgenes, y no de la ventana.
              expectFillsColumn(
                tester,
                find.widgetWithText(FilledButton, 'Añadir persona'),
                inset: 16,
              );
            case 'Quién regala':
              expect(find.byType(ManageRow), findsNWidgets(6));
              expectFillsColumn(tester, find.byType(ManageRow));
            case 'Ocasiones':
              expectFillsColumn(tester, find.byType(ManageRow));
            case 'Archivo':
              expectFillsColumn(tester, find.byType(SectionHeader));
              expect(find.byType(ManageRow), findsOneWidget);
              expectFillsColumn(tester, find.byType(ManageRow));
            case 'Bloqueo':
              expect(find.byType(SettingsRow), findsNWidgets(3));
              expectFillsColumn(tester, find.byType(SettingsRow));
              expectInsideColumn(tester, find.byType(RegalosSwitch));
            case 'Apariencia':
              expectFillsColumn(tester, find.byType(SectionHeader));
              expectInsideColumn(tester, find.byType(RegalosSwitch));
              expectInsideColumn(tester, find.byType(CountdownCard));
              expectInsideColumn(tester, find.text('Lavanda'));
              expectInsideColumn(tester, find.text('Mantequilla'));
            case 'Móviles de la familia':
              expectFillsColumn(tester, find.byType(SettingsRow));
              expectFillsColumn(tester, find.byType(SectionHeader));
              expectFillsColumn(
                tester,
                find.widgetWithText(FilledButton, 'Conectar otro móvil'),
                inset: 16,
              );
            case 'Copia de seguridad':
              expect(find.byType(SettingsRow), findsNWidgets(2));
              expectFillsColumn(tester, find.byType(SettingsRow));
            case 'Acerca de':
              expectFillsColumn(tester, find.byType(SettingsRow));
              expect(
                tester.getRect(find.text('Gift Huddle')).left,
                settingsColumn(tester).left + 16,
              );
              expectInsideColumn(
                tester,
                find.textContaining('Sin cuentas ni publicidad'),
              );
          }
        },
      );
    },
    // Con dos paneles no hay flecha: ver `two_pane_settings_test.dart`.
    sizes: const [kPhoneSize, kTabletPortrait],
  );

  tabletScreenTest(
    'con el texto al 130 % ningún apartado desborda',
    (tester, phone, size) async {
      await _seed(tester, phone);
      await pumpRegalos(tester, phone);
      await openSettingsTab(tester);
      expectFillsColumn(tester, find.byType(SettingsRow));
      await _walk(tester);
    },
    sizes: const [kTabletPortrait],
    textScale: 1.3,
  );

  tabletScreenTest(
    'en oscuro y con «Reducir movimiento» la columna es la misma',
    (tester, phone, size) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      await _seed(tester, phone);
      await pumpRegalos(tester, phone);
      await openSettingsTab(tester);
      expectFillsColumn(tester, find.byType(SettingsRow));
      await _walk(tester);
    },
    sizes: const [kPhoneSize, kTabletPortrait],
    brightness: Brightness.dark,
  );

  screenTest('los márgenes de la columna también desplazan la lista', (
    tester,
    phone,
  ) async {
    await _seed(tester, phone);
    await pumpRegalos(tester, phone);
    await openSettingsTab(tester);
    final position = _scroll(tester, SettingsScreen);
    expect(position.maxScrollExtent, greaterThan(0));
    expect(position.pixels, 0);
    // Fuera de la columna (empieza en 160), en el margen izquierdo.
    expect(settingsColumn(tester).left, 160);
    await tester.dragFrom(const Offset(120, 500), const Offset(0, -120));
    await settle(tester);
    expect(position.pixels, greaterThan(0));
    // Una ventana de tablet de 800 de ancho y poco alto: una columna, con la
    // lista más larga que la ventana.
  }, size: const Size(800, 700));

  screenTest(
    'girar con un apartado abierto conserva la pantalla y su posición',
    (tester, phone) async {
      await _seed(tester, phone, extraPeople: 24);
      await pumpRegalos(tester, phone);
      await openSettingsTab(tester);
      await tapVisible(tester, _row('Personas'));
      expectColumnScreen(tester);
      expect(settingsColumn(tester).left, 160);

      final position = _scroll(tester, ManageScreen);
      position.jumpTo(180);
      await tester.pump();
      final list = find.descendant(
        of: find.byType(ManageScreen),
        matching: find.byType(Scrollable),
      );
      final state = tester.state(list.first);

      await rotate(tester);
      await settle(tester);
      expect(windowSize(tester), kTabletLandscape);
      expect(find.byType(ManageScreen), findsOneWidget);
      expect(tester.state(list.first), same(state));
      expect(_scroll(tester, ManageScreen).pixels, 180);
      // Con dos paneles, la columna va a la izquierda del panel de detalle
      // (de 489 a 1280, escritorio), a 72 px del filete: empieza en 561.
      expect(settingsColumn(tester).left, closeTo(561, 0.01));
      expectFillsColumn(tester, find.byType(ManageRow));

      await rotate(tester);
      await settle(tester);
      expect(_scroll(tester, ManageScreen).pixels, 180);
      expect(settingsColumn(tester).left, 160);
      expectFillsColumn(tester, find.byType(ManageRow));
      _scroll(tester, ManageScreen).jumpTo(0);
      await tester.pump();
      expectColumnScreen(tester);
      await _back(tester);
      expectFillsColumn(tester, find.byType(SettingsRow));
    },
    size: kTabletPortrait,
  );

  group('norma 2: las filas miden su panel, no la ventana', () {
    const long =
        'Un nombre larguísimo que no cabe de ninguna manera en media fila '
        'de Ajustes ni aunque la ventana sea de tablet en horizontal';

    Future<void> pumpIn(
      WidgetTester tester,
      Size size,
      double width,
      Widget child, {
      bool pane = false,
    }) => pumpThemed(
      tester,
      SizedBox(
        width: width,
        child: pane ? PaneScope(child: child) : child,
      ),
      surfaceSize: size,
    );

    testWidgets('el valor de una fila ocupa como mucho media columna, también '
        'en una ventana ancha', (tester) async {
      await pumpIn(
        tester,
        kTabletLandscape,
        RegalosLayout.formColumn,
        SettingsRow(title: 'Este móvil es de', value: long, onTap: () {}),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.text(long)).width,
        lessThanOrEqualTo(RegalosLayout.formColumn / 2),
      );
      expect(
        tester.getSize(find.text('Este móvil es de')).width,
        greaterThan(60),
        reason: 'el título conserva su sitio',
      );
    });

    testWidgets('en el móvil el valor sigue ocupando media ventana', (
      tester,
    ) async {
      await pumpIn(
        tester,
        kPhoneSize,
        390,
        SettingsRow(title: 'Este móvil es de', value: long, onTap: () {}),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.text(long)).width, 195);
    });

    testWidgets('dentro de un panel, la fila y la cabecera miden el panel', (
      tester,
    ) async {
      await pumpIn(
        tester,
        kTabletLandscape,
        400,
        SettingsRow(title: 'Idioma', value: long, onTap: () {}),
        pane: true,
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.text(long)).width, 200);

      await pumpIn(
        tester,
        kTabletLandscape,
        400,
        const SectionHeader(title: 'Reyes', trailing: long),
        pane: true,
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.text(long)).width, closeTo(220, 0.01));
    });

    testWidgets('sin panel, la cabecera mide la ventana, como antes', (
      tester,
    ) async {
      await pumpIn(
        tester,
        kPhoneSize,
        390,
        const SectionHeader(title: 'Reyes', trailing: long),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.text(long)).width, closeTo(214.5, 0.01));
    });
  });
}
