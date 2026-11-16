// El bloqueo y el PIN en tablet (la guía de diseño para tablet, T5): el
// bloque va centrado, un poco por encima del centro, con las teclas del tamaño
// de siempre; con poco alto se queda arriba; en el móvil no cambia nada.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/features/lock/application/lock_controller.dart';
import 'package:regalos/features/lock/presentation/lock_screen.dart';
import 'package:regalos/features/lock/presentation/pin_pad.dart';
import 'package:regalos/features/lock/presentation/pin_setup_screen.dart';
import 'package:regalos/features/settings/presentation/pin_verify_screen.dart';

import '../helpers/memory_stores.dart';
import '../helpers/screens.dart';
import '../helpers/tablet.dart';

/// La app de muestra con PIN (1234), bloqueada.
Future<void> pumpLocked(WidgetTester tester, FakePhone phone) async {
  await seedSample(tester, phone, pin: true);
  await pumpRegalos(tester, phone);
  await tester.runAsync(
    () => phone.container.read(lockControllerProvider.notifier).lockNow(),
  );
  await settle(tester);
  expect(find.byType(LockScreen), findsOneWidget);
}

/// Pulsa los dígitos de [pin] en el teclado del PIN.
Future<void> typePin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(
      find.descendant(of: find.byType(PinPad), matching: find.text(digit)),
    );
    await tester.pump();
  }
}

/// El rectángulo del bloque del PIN (lo que se desplaza, con sus márgenes).
Rect blockRect(WidgetTester tester) => tester.getRect(
  find.descendant(
    of: find.byType(PinBlock),
    matching: find.byType(SingleChildScrollView),
  ),
);

/// El bloque está centrado a lo ancho de la ventana, un poco por encima del
/// centro del sitio que tiene (la pantalla, o lo que queda bajo la barra de
/// «volver»), y no es más ancho que en el móvil.
void expectCentered(WidgetTester tester, Size size) {
  final area = tester.getRect(find.byType(PinBlock));
  final block = blockRect(tester);
  expect(block.center.dx, closeTo(size.width / 2, 0.5));
  expect(block.width, lessThanOrEqualTo(PinBlock.maxWidth));
  // Entero a la vista.
  expect(block.top, greaterThan(area.top));
  expect(block.bottom, lessThan(area.bottom));
  expect(area.bottom, lessThanOrEqualTo(size.height));
  // Por encima del centro, pero no arriba del todo.
  expect(block.center.dy, lessThan(area.center.dy));
  expect(block.center.dy, greaterThan(area.top + area.height * 0.38));
}

/// Las doce teclas miden lo de siempre: 84 por 66.
void expectKeySize(WidgetTester tester) {
  final keys = find.descendant(
    of: find.byType(PinPad),
    matching: find.byType(InkWell),
  );
  expect(keys, findsWidgets);
  for (final element in keys.evaluate()) {
    expect(
      tester.getSize(find.byElementPredicate((e) => e == element)),
      const Size(84, 66),
    );
  }
  // Tres teclas y sus huecos: el teclado no se estira.
  expect(tester.getSize(find.byType(PinPad)).width, 3 * (84 + 12));
}

double dotsX(WidgetTester tester) => tester.getTopLeft(find.byType(PinDots)).dx;

void main() {
  tabletScreenTest('el bloqueo va centrado, con las teclas de siempre; un PIN '
      'erróneo tiembla y el correcto abre', (tester, phone, size) async {
    await pumpLocked(tester, phone);
    expectCentered(tester, size);
    expectKeySize(tester);
    expect(tester.takeException(), isNull);

    // PIN erróneo: avisa, y los puntos tiemblan como en el móvil.
    final rest = dotsX(tester);
    await typePin(tester, '0000');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.textContaining('PIN incorrecto'), findsOneWidget);
    var shift = 0.0;
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      shift = math.max(shift, (dotsX(tester) - rest).abs());
      expect(tester.widget<PinDots>(find.byType(PinDots)).count, 4);
    }
    expect(shift, greaterThan(6));
    await settle(tester);
    expect(tester.widget<PinDots>(find.byType(PinDots)).count, 0);
    expect(dotsX(tester), rest);
    // El mensaje no ha movido el bloque de su sitio.
    expectCentered(tester, size);

    // PIN correcto: la app aparece debajo.
    await typePin(tester, '1234');
    await settle(tester);
    expect(find.byType(LockScreen), findsNothing);
    expect(find.text('Aritz'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  tabletScreenTest(
    'con «Reducir movimiento» y en oscuro: no tiembla, tiñe los anillos y abre',
    (tester, phone, size) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpLocked(tester, phone);
      expectCentered(tester, size);
      final rest = dotsX(tester);
      await typePin(tester, '0000');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        expect(dotsX(tester), rest);
      }
      expect(tester.widget<PinDots>(find.byType(PinDots)).error, isTrue);
      await settle(tester);
      await typePin(tester, '1234');
      await settle(tester);
      expect(find.byType(LockScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
    brightness: Brightness.dark,
  );

  screenTest('en el móvil el bloqueo sigue arriba, a 50 del borde', (
    tester,
    phone,
  ) async {
    await pumpLocked(tester, phone);
    final block = blockRect(tester);
    expect(block.top, 0);
    expect(block.center.dx, kPhoneSize.width / 2);
    expect(
      tester
          .getTopLeft(
            find.descendant(
              of: find.byType(LockScreen),
              matching: find.text('Gift Huddle'),
            ),
          )
          .dy,
      50,
    );
    expectKeySize(tester);
  });

  screenTest(
    'con la ventana ancha pero de menos de 560 de alto se queda arriba y '
    'se puede desplazar',
    (tester, phone) async {
      await pumpLocked(tester, phone);
      expect(PinBlock.minHeight, 560);
      final block = blockRect(tester);
      expect(block.top, 0);
      expect(
        tester
            .getTopLeft(
              find.descendant(
                of: find.byType(LockScreen),
                matching: find.text('Gift Huddle'),
              ),
            )
            .dy,
        50,
      );
      // No cabe entero: se desplaza hasta la última fila de teclas.
      final scroll = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(PinBlock),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      await tester.drag(find.byType(PinBlock), const Offset(0, -300));
      await tester.pump();
      expect(scroll.position.pixels, greaterThan(0));
      expectKeySize(tester);
      expect(tester.takeException(), isNull);
      // Y el PIN sigue abriendo.
      await typePin(tester, '1234');
      await settle(tester);
      expect(find.byType(LockScreen), findsNothing);
    },
    // Ancha y no compacta (alto de 480 o más), pero de menos de 560.
    size: const Size(720, 490),
  );

  tabletScreenTest('girar a medio escribir no pierde los dígitos ni el sitio', (
    tester,
    phone,
    size,
  ) async {
    await pumpLocked(tester, phone);
    await typePin(tester, '12');
    expect(tester.widget<PinDots>(find.byType(PinDots)).count, 2);

    await rotate(tester);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.widget<PinDots>(find.byType(PinDots)).count, 2);
    expectCentered(tester, windowSize(tester));

    // Hasta el móvil (pantalla partida) y vuelta: mismo árbol, mismo estado.
    await setWindowSize(tester, kPhoneSize);
    expect(tester.takeException(), isNull);
    expect(tester.widget<PinDots>(find.byType(PinDots)).count, 2);
    expect(blockRect(tester).top, 0);
    await setWindowSize(tester, size);
    expectCentered(tester, size);

    await typePin(tester, '34');
    await settle(tester);
    expect(find.byType(LockScreen), findsNothing);
  });

  tabletScreenTest(
    'con el texto al 130 % el bloqueo no desborda',
    (tester, phone, size) async {
      await pumpLocked(tester, phone);
      expect(tester.takeException(), isNull);
      final block = blockRect(tester);
      expect(block.center.dx, closeTo(size.width / 2, 0.5));
      expect(block.width, lessThanOrEqualTo(PinBlock.maxWidth));
      await typePin(tester, '0000');
      await settle(tester);
      expect(find.textContaining('PIN incorrecto'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    sizes: const [kTabletPortrait],
    textScale: 1.3,
  );

  tabletScreenTest('pedir el PIN actual y crear uno nuevo también van '
      'centrados', (tester, phone, size) async {
    await seedSample(tester, phone, pin: true);
    await pumpRegalos(tester, phone);
    phone.container.read(routerProvider).go('/settings/security');
    await settle(tester);

    // Cambiar el PIN: primero pide el actual…
    await tapText(tester, 'Cambiar PIN');
    expect(find.byType(PinVerifyScreen), findsOneWidget);
    expect(find.text('Escribe tu PIN actual.'), findsOneWidget);
    expectCentered(tester, size);
    expectKeySize(tester);
    await typePin(tester, '0000');
    await tapText(tester, 'Continuar');
    expect(find.textContaining('PIN incorrecto'), findsOneWidget);
    expectCentered(tester, size);
    await typePin(tester, '1234');
    await tapText(tester, 'Continuar');

    // …y luego el nuevo, dos veces.
    expect(find.byType(PinSetupScreen), findsOneWidget);
    expect(find.text('Crea un PIN'), findsOneWidget);
    expectCentered(tester, size);
    expectKeySize(tester);
    // El botón no se estira: cabe en el bloque.
    expect(
      tester.getSize(find.widgetWithText(FilledButton, 'Continuar')).width,
      lessThanOrEqualTo(PinBlock.maxWidth),
    );
    await typePin(tester, '4321');
    await tapText(tester, 'Continuar');
    expect(find.text('Repite el PIN'), findsOneWidget);
    await typePin(tester, '4321');
    await tapText(tester, 'Guardar PIN');
    // Con huella en el móvil de prueba se ofrece activarla.
    expect(find.text('¿Activar huella o rostro?'), findsOneWidget);
    expectCentered(tester, size);
    await tapText(tester, 'Ahora no');
    expect(find.text('PIN cambiado.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
