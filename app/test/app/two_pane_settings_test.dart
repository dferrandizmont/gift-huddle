import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/layout/pane_scope.dart';
import 'package:regalos/core/layout/pane_selection.dart';
import 'package:regalos/core/theme/regalos_tokens.dart';
import 'package:regalos/core/widgets/screen_header.dart';
import 'package:regalos/core/widgets/section_header.dart';
import 'package:regalos/core/widgets/settings_row.dart';
import 'package:regalos/core/widgets/stroke_icon.dart';
import 'package:regalos/features/settings/presentation/about_screen.dart';
import 'package:regalos/features/settings/presentation/appearance_screen.dart';
import 'package:regalos/features/settings/presentation/manage_screens.dart';
import 'package:regalos/features/settings/presentation/settings_screen.dart';
import 'package:regalos/features/settings/presentation/settings_sections.dart';
import 'package:regalos/features/sharing/presentation/backup_screen.dart';
import 'package:regalos/features/sharing/presentation/share_screen.dart';
import 'package:regalos/features/sync/presentation/invite_screen.dart';

import '../helpers/memory_stores.dart';
import '../helpers/screens.dart';
import '../helpers/settings_column.dart';
import '../helpers/tablet.dart';

// Los dos paneles de Ajustes (la guía de diseño de escritorio, §2.2 y
// tanda W2a): los apartados a la izquierda (el primero, elegido al entrar) y
// cada apartado a la derecha, en su columna (640 a 72 px del filete en
// escritorio, 560 y 95 px en tablet) y sin flecha de volver, con la selección
// en la URL. Por debajo de 840 de ancho nada cambia.

const _desktop = Size(1280, 800);
const _huge = Size(2560, 1300);

/// La ruta en la que está el router ahora mismo.
String _path(FakePhone phone) => phone.container
    .read(routerProvider)
    .routeInformationProvider
    .value
    .uri
    .path;

/// La fila de [title] en el panel de lista.
Finder _row(String title) => find.descendant(
  of: find.byType(SettingsScreen),
  matching: find.widgetWithText(SettingsRow, title),
);

Rect _listPane(WidgetTester tester) =>
    tester.getRect(find.byType(SettingsScreen));

bool _selected(WidgetTester tester, Pattern label) =>
    tester
        .getSemantics(find.bySemanticsLabel(label).first)
        .getSemanticsData()
        .flagsCollection
        .isSelected ==
    Tristate.isTrue;

Future<void> _seed(WidgetTester tester, FakePhone phone) async {
  await seedSample(tester, phone);
  await tester.runAsync(
    () => familyOf(phone).archiveRecipient('leo', archived: true),
  );
}

void main() {
  group('a 1280 × 800', () {
    screenTest('lista y detalle a la vez, con el primer apartado elegido', (
      tester,
      phone,
    ) async {
      await _seed(tester, phone);
      await pumpRegalos(tester, phone);
      await openSettingsTab(tester);
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(ManagePeopleScreen), findsOneWidget);
      expect(_path(phone), '/settings/people');
      expect(_selected(tester, RegExp(r'^Personas\.')), isTrue);
      expect(_selected(tester, RegExp(r'^Apariencia\.')), isFalse);
      // La lista a la izquierda (80 de raíl, 408, 1 de filete).
      final list = _listPane(tester);
      expect(list.left, 80);
      expect(list.width, closeTo(408, 0.01));
      expect(find.byType(PaneScope), findsNWidgets(3));
      // Sin flecha de volver ni el «Ajustes» de encima en el apartado.
      expect(find.bySemanticsLabel('Volver a Ajustes'), findsNothing);
      final header = find.descendant(
        of: find.byType(ManagePeopleScreen),
        matching: find.byType(ScreenHeader),
      );
      expect(header, findsOneWidget);
      expect(
        find.descendant(of: header, matching: find.text('Ajustes')),
        findsNothing,
      );
      // El apartado, en su columna de 640 alineada a la izquierda del panel
      // de detalle, a 72 px del filete (no centrada).
      final pane = tester.getRect(find.byType(ManagePeopleScreen));
      final column = tester.getRect(header);
      expect(column.width, 640);
      expect(column.left, closeTo(pane.left + 72, 0.01));
      // Las filas de la lista van con 8 px de margen, como las de Personas y
      // Ocasiones.
      expect(
        tester.getRect(_row('Apariencia')).left,
        closeTo(list.left + 8, 0.01),
      );
      expect(tester.takeException(), isNull);
    }, size: _desktop);

    screenTest('tocar otro apartado cambia la URL y el detalle, sin apilar', (
      tester,
      phone,
    ) async {
      await _seed(tester, phone);
      await pumpRegalos(tester, phone);
      await openSettingsTab(tester);
      await tester.tap(_row('Apariencia'));
      await settle(tester);
      expect(_path(phone), '/settings/appearance');
      expect(find.byType(AppearanceScreen), findsOneWidget);
      expect(find.byType(ManagePeopleScreen), findsNothing);
      expect(find.text('Vista previa'), findsOneWidget);
      expect(_selected(tester, RegExp(r'^Apariencia\.')), isTrue);
      expect(_selected(tester, RegExp(r'^Personas\.')), isFalse);
      // La lista no se ha movido y no hay nada apilado debajo.
      expect(find.byType(SettingsScreen, skipOffstage: false), findsOneWidget);
      expect(
        find.byType(AppearanceScreen, skipOffstage: false),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Volver a Ajustes'), findsNothing);
      // El atrás del sistema sale de la app: se queda como está.
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(_path(phone), '/settings/appearance');
      await tester.ensureVisible(_row('Acerca de Gift Huddle'));
      await tester.pump();
      await tester.tap(_row('Acerca de Gift Huddle'));
      await settle(tester);
      expect(_path(phone), '/settings/about');
      expect(find.byType(AboutScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, size: _desktop);

    screenTest('cada apartado se abre en el detalle, en su columna de 640', (
      tester,
      phone,
    ) async {
      await _seed(tester, phone);
      await pumpRegalos(tester, phone);
      await openSettingsTab(tester);
      for (final row in [
        'Personas',
        'Quién regala',
        'Ocasiones',
        'Archivo',
        'Bloqueo',
        'Apariencia',
        'Móviles de la familia',
        'Copia de seguridad',
        'Acerca de Gift Huddle',
      ]) {
        await tester.ensureVisible(_row(row));
        await tester.pump();
        await tester.tap(_row(row));
        await settle(tester);
        final header = find.descendant(
          of: find.byType(Scaffold).last,
          matching: find.byType(ScreenHeader),
        );
        expect(header, findsOneWidget, reason: row);
        expect(tester.getRect(header).width, 640, reason: row);
        expect(
          find.bySemanticsLabel(RegExp('^Volver a ')),
          findsNothing,
          reason: row,
        );
        expect(tester.takeException(), isNull, reason: row);
      }
    }, size: _desktop);

    screenTest('cambiar el tema repinta los dos paneles', (
      tester,
      phone,
    ) async {
      await _seed(tester, phone);
      await pumpRegalos(tester, phone);
      await openSettingsTab(tester);
      await tester.tap(_row('Apariencia'));
      await settle(tester);
      Brightness of(Type screen) =>
          Theme.of(tester.element(find.byType(screen))).brightness;
      expect(of(SettingsScreen), Brightness.light);
      expect(of(AppearanceScreen), Brightness.light);
      await tester.tap(find.text('Oscuro').first);
      await settle(tester);
      expect(of(SettingsScreen), Brightness.dark);
      expect(of(AppearanceScreen), Brightness.dark);
      expect(
        Theme.of(tester.element(find.bySemanticsLabel('Navegación principal')))
            .brightness,
        Brightness.dark,
      );
      expect(tester.takeException(), isNull);
    }, size: _desktop);

    screenTest('Móviles de la familia, la copia y la invitación en dos '
        'paneles', (tester, phone) async {
      await _seed(tester, phone);
      await pumpRegalos(tester, phone);
      await openSettingsTab(tester);
      await tester.tap(_row('Móviles de la familia'));
      await settle(tester);
      expect(find.byType(ShareScreen), findsOneWidget);
      Finder inDetail(Finder f) =>
          find.descendant(of: find.byType(ShareScreen), matching: f);
      expectFillsColumn(tester, inDetail(find.byType(SettingsRow)));
      expectFillsColumn(tester, inDetail(find.byType(SectionHeader)));
      expectFillsColumn(
        tester,
        inDetail(find.widgetWithText(FilledButton, 'Conectar otro móvil')),
        inset: 16,
      );
      // La invitación se abre por encima del marco: la columna se centra en
      // la ventana entera, y el apartado vuelve a su sitio al cerrarla.
      await tapVisible(tester, find.text('Conectar otro móvil'));
      await tapText(tester, 'Está lejos');
      expect(find.byType(InviteScreen), findsOneWidget);
      final invite = tester.getRect(
        find.descendant(
          of: find.byType(InviteScreen),
          matching: find.byType(ScreenHeader),
        ),
      );
      expect(invite.width, 560);
      expect(invite.center.dx, closeTo(640, 0.01));
      await tapLabel(tester, 'Volver a Móviles de la familia');
      expect(find.byType(InviteScreen), findsNothing);
      expect(find.byType(ShareScreen), findsOneWidget);
      expect(_path(phone), '/settings/share');
      // Copia de seguridad: dos filas.
      await tester.tap(_row('Copia de seguridad'));
      await settle(tester);
      expect(find.byType(BackupScreen), findsOneWidget);
      final rows = find.descendant(
        of: find.byType(BackupScreen),
        matching: find.byType(SettingsRow),
      );
      expect(rows, findsNWidgets(2));
      expectFillsColumn(tester, rows);
      expect(tester.takeException(), isNull);
    }, size: _desktop);

    screenTest('los márgenes de la columna del detalle también desplazan su '
        'lista', (tester, phone) async {
      await seedSample(tester, phone, extraPeople: 24);
      await pumpRegalos(tester, phone);
      await openSettingsTab(tester);
      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(ManagePeopleScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
      // El margen izquierdo del detalle: la columna empieza a 72 px del filete.
      expect(
        settingsColumn(tester).left,
        closeTo(
          tester.getRect(find.byType(ManagePeopleScreen)).left + 72,
          0.01,
        ),
      );
      await tester.dragFrom(const Offset(540, 500), const Offset(0, -120));
      await settle(tester);
      expect(scrollable.position.pixels, greaterThan(0));
    }, size: _desktop);

    screenTest('la fila del apartado elegido pierde el filete y las demás '
        'siguen con el suyo', (tester, phone) async {
      await _seed(tester, phone);
      await pumpRegalos(tester, phone);
      await openSettingsTab(tester);
      // Las filas del panel van con 8 px de margen a cada lado.
      final list = _listPane(tester);
      final row = tester.getRect(_row('Quién regala'));
      expect(row.left, list.left + 8);
      expect(row.right, list.right - 8);
      expect(tester.widget<SettingsRow>(_row('Personas')).selected, isTrue);
      expect(
        tester.widget<SettingsRow>(_row('Quién regala')).selected,
        isFalse,
      );
    }, size: _desktop);

    screenTest('estrechar la ventana: el apartado que puso la app vuelve a la '
        'lista y el que eligió el usuario se queda con su flecha', (
      tester,
      phone,
    ) async {
      await _seed(tester, phone);
      await pumpRegalos(tester, phone);
      await openSettingsTab(tester);
      expect(_path(phone), '/settings/people');
      await setWindowSize(tester, kTabletPortrait);
      await settle(tester);
      expect(_path(phone), '/settings');
      expect(find.byType(ManagePeopleScreen), findsNothing);
      await setWindowSize(tester, _desktop);
      await settle(tester);
      expect(_path(phone), '/settings/people');
      await tester.tap(_row('Apariencia'));
      await settle(tester);
      await setWindowSize(tester, kTabletPortrait);
      await settle(tester);
      expect(_path(phone), '/settings/appearance');
      expect(find.bySemanticsLabel('Volver a Ajustes'), findsOneWidget);
      expect(find.byType(SettingsScreen), findsNothing);
      await setWindowSize(tester, _desktop);
      await settle(tester);
      expect(_path(phone), '/settings/appearance');
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, size: _desktop);
  });

  group('a 1536 × 864', () {
    screenTest('el apartado va en una columna de 640 a 72 px del filete', (
      tester,
      phone,
    ) async {
      await _seed(tester, phone);
      await pumpRegalos(tester, phone);
      await openSettingsTab(tester);
      await tester.tap(_row('Apariencia'));
      await settle(tester);
      final pane = tester.getRect(find.byType(AppearanceScreen));
      final header = tester.getRect(
        find.descendant(
          of: find.byType(AppearanceScreen),
          matching: find.byType(ScreenHeader),
        ),
      );
      // A la izquierda, no centrada: la columna de 640 empieza a 72 px del
      // filete y el resto del ancho queda a la derecha.
      expect(header.width, 640);
      expect(header.left, closeTo(pane.left + 72, 0.01));
      expect(pane.right - header.right, greaterThan(72));
      expect(settingsColumn(tester).left, closeTo(header.left, 0.01));
      // Las filas del apartado llenan la columna, con el mismo inset.
      expectFillsColumn(
        tester,
        find.descendant(
          of: find.byType(AppearanceScreen),
          matching: find.byType(SectionHeader),
        ),
      );
      expect(tester.takeException(), isNull);
    }, size: const Size(1536, 864));

    for (final brightness in Brightness.values) {
      screenTest(
        'la lista, con filas planas con inset de 8, sin flecha y la '
        'elegida con soft e ink (${brightness.name})',
        (tester, phone) async {
          await _seed(tester, phone);
          await pumpRegalos(tester, phone);
          await openSettingsTab(tester);
          final list = _listPane(tester);
          // Las filas, a 8 del borde del panel.
          for (final title in ['Personas', 'Quién regala', 'Apariencia']) {
            final row = tester.getRect(_row(title));
            expect(row.left, closeTo(list.left + 8, 0.01), reason: title);
            expect(row.right, closeTo(list.right - 8, 0.01), reason: title);
          }
          // La cabecera de cada grupo, con el texto a 16 del borde.
          final headers = find.descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(SectionHeader),
          );
          expect(headers, findsWidgets);
          for (final element in headers.evaluate()) {
            final title = find.descendant(
              of: find.byElementPredicate((e) => e == element),
              matching: find.byType(Text),
            );
            expect(
              tester.getRect(title.first).left,
              closeTo(list.left + 16, 0.01),
            );
          }
          // Sin flecha: solo queda el icono de la izquierda.
          expect(
            find.descendant(
              of: _row('Apariencia'),
              matching: find.byType(StrokeIcon),
            ),
            findsOneWidget,
          );
          // La elegida, con el relleno y el borde del tema (sin color propio).
          final t = RegalosTokens.of(
            tester.element(find.byType(SettingsScreen)),
          );
          final scope = tester.widget<SelectionScope>(
            find.descendant(
              of: find.byType(SettingsScreen),
              matching: find.byType(SelectionScope),
            ),
          );
          expect(scope.fill, t.soft);
          expect(scope.border, t.ink);
          expect(scope.selectedId, 'people');
          expect(tester.takeException(), isNull);
        },
        size: const Size(1536, 864),
        brightness: brightness,
      );
    }
  });

  group('en una tablet de 1279 × 800', () {
    screenTest('el apartado sigue en su columna de 560, a 95 px del filete', (
      tester,
      phone,
    ) async {
      await _seed(tester, phone);
      await pumpRegalos(tester, phone);
      await openSettingsTab(tester);
      final pane = tester.getRect(find.byType(ManagePeopleScreen));
      final header = tester.getRect(
        find.descendant(
          of: find.byType(ManagePeopleScreen),
          matching: find.byType(ScreenHeader),
        ),
      );
      expect(header.width, 560);
      expect(header.left, closeTo(pane.left + 95, 0.01));
    }, size: const Size(1279, 800));
  });

  group('a 2560 × 1300', () {
    screenTest('el apartado sigue en su columna de 640, a 72 px del filete '
        'del panel de detalle', (tester, phone) async {
      await _seed(tester, phone);
      await pumpRegalos(tester, phone);
      await openSettingsTab(tester);
      await tester.tap(_row('Apariencia'));
      await settle(tester);
      final pane = tester.getRect(find.byType(AppearanceScreen));
      expect(pane.width, greaterThan(1500));
      final header = tester.getRect(
        find.descendant(
          of: find.byType(AppearanceScreen),
          matching: find.byType(ScreenHeader),
        ),
      );
      expect(header.width, 640);
      expect(header.left, closeTo(pane.left + 72, 0.01));
    }, size: _huge);
  });

  group('en la web', () {
    test('los apartados de la web no llevan seguridad, compartir ni copia', () {
      expect(settingsSectionIds(web: true), isNot(contains('security')));
      expect(settingsSectionIds(web: true), isNot(contains('share')));
      expect(settingsSectionIds(web: true), isNot(contains('backup')));
      expect(
        settingsSectionIds(web: false),
        containsAll(settingsSectionIds(web: true)),
      );
    });

    test('con dos paneles, /settings lleva a un apartado que se ve', () {
      final selection = PaneSelection()..twoPanes.value = true;
      final ids = settingsSectionIds(web: true);
      expect(
        selection.redirectTab(PaneTab.settings, '/settings', ids),
        '/settings/people',
      );
      // Un último apartado que la web no tiene no se elige.
      selection.choose(PaneTab.settings, 'share');
      expect(
        selection.redirectTab(PaneTab.settings, '/settings', ids),
        '/settings/people',
      );
      selection.choose(PaneTab.settings, 'appearance');
      expect(
        selection.redirectTab(PaneTab.settings, '/settings', ids),
        '/settings/appearance',
      );
      selection.dispose();
    });
  });

  group('teclado', () {
    screenTest('↑ y ↓ cambian de apartado, hasta el primero y el último', (
      tester,
      phone,
    ) async {
      await _seed(tester, phone);
      await pumpRegalos(tester, phone);
      await openSettingsTab(tester);
      expect(_path(phone), '/settings/people');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await settle(tester);
      expect(_path(phone), '/settings/people');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await settle(tester);
      expect(_path(phone), '/settings/givers');
      for (var i = 0; i < 12; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await settle(tester);
      expect(_path(phone), '/settings/about');
      expect(find.byType(AboutScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, size: _desktop);

    screenTest('Intro pasa el foco al detalle', (tester, phone) async {
      await _seed(tester, phone);
      await pumpRegalos(tester, phone);
      await openSettingsTab(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      final focus = FocusManager.instance.primaryFocus;
      expect(focus, isNotNull);
      expect(PaneScope.roleOf(focus!.context!), PaneRole.detail);
    }, size: _desktop);
  });

  group('sin cambios por debajo de 840', () {
    for (final size in [kPhoneSize, kTabletPortrait]) {
      screenTest('${sizeLabel(size)}: la lista y, aparte, cada apartado con su '
          'flecha', (tester, phone) async {
        await _seed(tester, phone);
        await pumpRegalos(tester, phone);
        await openSettingsTab(tester);
        expect(_path(phone), '/settings');
        expect(find.byType(PaneScope), findsOneWidget);
        expect(find.byType(ManagePeopleScreen), findsNothing);
        expectColumnScreen(tester);
        await tapVisible(tester, _row('Apariencia'));
        expect(_path(phone), '/settings/appearance');
        expect(find.byType(AppearanceScreen), findsOneWidget);
        expect(find.byType(SettingsScreen), findsNothing);
        expect(find.bySemanticsLabel('Volver a Ajustes'), findsOneWidget);
        await tester.tap(find.bySemanticsLabel('Volver a Ajustes'));
        await settle(tester);
        expect(_path(phone), '/settings');
        expect(tester.takeException(), isNull);
      }, size: size);
    }
  });
}
