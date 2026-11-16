import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/widgets/screen_header.dart';
import 'package:regalos/core/widgets/section_header.dart';
import 'package:regalos/core/widgets/settings_row.dart';
import 'package:regalos/features/lock/application/lock_controller.dart';
import 'package:regalos/features/sharing/application/pairing_service.dart';
import 'package:regalos/features/sharing/presentation/share_screen.dart';
import 'package:regalos/features/sync/presentation/invite_screen.dart';

import '../helpers/memory_stores.dart';
import '../helpers/screens.dart';
import '../helpers/settings_column.dart';
import '../helpers/tablet.dart';

// Tanda T2 del plan de tablet (la guía de diseño para tablet, §6): Móviles de
// la familia, Copia de seguridad y la invitación van en una columna de 560
// centrada; en el móvil no cambia nada.

Finder _row(String title) => find.widgetWithText(SettingsRow, title);

Future<void> _openSection(WidgetTester tester, String row) async {
  await openSettingsTab(tester);
  await tapVisible(tester, _row(row));
}

/// Empareja el móvil de la prueba con otro que tiene la familia de muestra y
/// monta la app.
Future<void> _pairWithOwner(WidgetTester tester, FakePhone phone) async {
  final owner = FakePhone();
  addTearDown(owner.dispose);
  await seedSample(tester, owner);
  await tester.runAsync(() async {
    final qrText = await owner.container
        .read(pairingServiceProvider)
        .qrTextForPairing();
    await phone.container
        .read(pairingServiceProvider)
        .joinFromQr(qrText, deviceName: 'Móvil de Eva');
    await phone.container.read(lockControllerProvider.notifier).skipSetup();
  });
  await pumpRegalos(tester, phone);
}

/// La lista que se desplaza de la invitación (la cabecera queda fuera).
final _inviteList = find.descendant(
  of: find.byType(InviteScreen),
  matching: find.byType(Scrollable),
);

const _intro =
    'Crea un enlace para que otra persona se una a tu familia desde su '
    'móvil, sin estar delante.';

void main() {
  tabletScreenTest(
    'Móviles de la familia va en la columna de 560 y todo se puede pulsar',
    (tester, phone, size) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openSection(tester, 'Móviles de la familia');

      expectColumnScreen(tester);
      // La tarjeta de estado y el botón, con sus márgenes de 16; las filas y
      // la cabecera «Conectados», de un borde a otro.
      expectFillsColumn(
        tester,
        find.ancestor(
          of: find.text('Solo en este móvil'),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && (w.properties.liveRegion ?? false),
          ),
        ),
        inset: 16,
        reason: 'tarjeta de estado',
      );
      expectFillsColumn(tester, find.byType(SectionHeader));
      expectFillsColumn(tester, find.byType(SettingsRow));
      expectFillsColumn(
        tester,
        find.widgetWithText(FilledButton, 'Conectar otro móvil'),
        inset: 16,
      );

      await tapVisible(tester, find.text('Conectar otro móvil'));
      expect(find.text('¿Dónde está el otro móvil?'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await settle(tester);
      expect(find.byType(BottomSheet), findsNothing);

      await tapVisible(tester, _row('Más opciones'));
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await settle(tester);
      expect(find.byType(BottomSheet), findsNothing);

      await tapLabel(tester, 'Volver a Ajustes');
      expect(find.text('Compartir y copia'), findsOneWidget);
    },
    sizes: const [kPhoneSize, kTabletPortrait],
  );

  tabletScreenTest(
    'con dos móviles, las filas de «Conectados» y «Enviar la lista ahora» '
    'van en la columna',
    (tester, phone, size) async {
      await _pairWithOwner(tester, phone);
      await _openSection(tester, 'Móviles de la familia');
      expectColumnScreen(tester);
      for (final title in [
        'Móvil de Eva',
        'Móvil de prueba',
        'Enviar la lista ahora',
        'Más opciones',
      ]) {
        expectFillsColumn(tester, _row(title), reason: title);
      }
    },
    sizes: const [kPhoneSize, kTabletPortrait],
  );

  tabletScreenTest(
    'Copia de seguridad va en la columna y sus filas se pueden pulsar',
    (tester, phone, size) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openSection(tester, 'Copia de seguridad');

      expectColumnScreen(tester);
      expect(find.byType(SettingsRow), findsNWidgets(2));
      expectFillsColumn(tester, find.byType(SettingsRow));
      expectFillsColumn(
        tester,
        find.textContaining('solo se abre en un móvil que ya esté conectado'),
        inset: 16,
      );

      await tapVisible(tester, _row('Recuperar una copia'));
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Pegar desde el portapapeles'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await settle(tester);
      expect(find.byType(BottomSheet), findsNothing);
      await tapLabel(tester, 'Volver a Ajustes');
      expect(find.text('Compartir y copia'), findsOneWidget);
    },
    sizes: const [kPhoneSize, kTabletPortrait],
  );

  tabletScreenTest(
    'la invitación («Está lejos») va en la columna, centrada en la ventana',
    (tester, phone, size) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openSection(tester, 'Móviles de la familia');
      await tapVisible(tester, find.text('Conectar otro móvil'));
      await tapText(tester, 'Está lejos');

      // Se abre por encima del marco: sin raíl, la columna se centra en la
      // ventana entera.
      expect(
        find.descendant(
          of: find.byType(ScreenHeader),
          matching: find.text('Invitar a alguien'),
        ),
        findsOneWidget,
      );
      expectColumnScreen(tester, rail: false, scrollable: _inviteList);
      expectFillsColumn(tester, find.text(_intro), inset: 20, rail: false);
      expectInsideColumn(
        tester,
        find.descendant(of: _inviteList, matching: find.byType(Text)),
        rail: false,
      );

      await tapLabel(tester, 'Volver a Móviles de la familia');
      expect(find.byType(InviteScreen), findsNothing);
      expectColumnScreen(tester);
    },
    sizes: const [kPhoneSize, kTabletPortrait],
  );

  tabletScreenTest(
    'con el texto al 130 % Compartir, la copia y la invitación no desbordan',
    (tester, phone, size) async {
      await _pairWithOwner(tester, phone);
      await _openSection(tester, 'Móviles de la familia');
      expectColumnScreen(tester);
      expectFillsColumn(tester, find.byType(SettingsRow));
      await tapVisible(tester, find.text('Conectar otro móvil'));
      await tapText(tester, 'Está lejos');
      expectColumnScreen(tester, rail: false, scrollable: _inviteList);
      await tapLabel(tester, 'Volver a Móviles de la familia');
      await tapLabel(tester, 'Volver a Ajustes');
      await tapVisible(tester, _row('Copia de seguridad'));
      expectColumnScreen(tester);
      expectFillsColumn(tester, find.byType(SettingsRow));
    },
    sizes: const [kTabletPortrait],
    textScale: 1.3,
  );

  tabletScreenTest(
    'en oscuro y con «Reducir movimiento» la columna es la misma',
    (tester, phone, size) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openSection(tester, 'Móviles de la familia');
      expectColumnScreen(tester);
      expectFillsColumn(tester, find.byType(SettingsRow));
      await tapVisible(tester, find.text('Conectar otro móvil'));
      await tapText(tester, 'Está lejos');
      expectColumnScreen(tester, rail: false, scrollable: _inviteList);
    },
    sizes: const [kTabletPortrait],
    brightness: Brightness.dark,
  );

  screenTest('girar con la invitación abierta la deja abierta y centrada', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await _openSection(tester, 'Móviles de la familia');
    await tapVisible(tester, find.text('Conectar otro móvil'));
    await tapText(tester, 'Está lejos');
    expect(settingsColumn(tester, rail: false).left, 120);
    final state = tester.state(find.byType(InviteScreen));

    await rotate(tester);
    await settle(tester);
    expect(tester.state(find.byType(InviteScreen)), same(state));
    expect(settingsColumn(tester, rail: false).left, 360);
    expectColumnScreen(tester, rail: false, scrollable: _inviteList);
    expectFillsColumn(tester, find.text(_intro), inset: 20, rail: false);

    // De vuelta en Móviles de la familia, ya en horizontal: con dos paneles va
    // a la derecha, en su columna de 640 a 72 px del filete del detalle (a
    // 1280 ya es un escritorio).
    await tapLabel(tester, 'Volver a Móviles de la familia');
    expect(find.byType(InviteScreen), findsNothing);
    expect(settingsColumn(tester).left, closeTo(561, 0.01));
    final header = tester.getRect(
      find.descendant(
        of: find.byType(ShareScreen),
        matching: find.byType(ScreenHeader),
      ),
    );
    expect(header.left, closeTo(settingsColumn(tester).left, 0.01));
    expect(header.width, 640);
  }, size: kTabletPortrait);
}
