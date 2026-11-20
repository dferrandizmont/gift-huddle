// El primer uso y el QR en tablet (la guía de diseño para tablet, T6): una
// columna de 520 con cabecera, pasos y botones; la cámara en un cuadro de 480
// como mucho (a la izquierda del texto en horizontal); el QR de 320; en el
// móvil no cambia nada.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/layout/window_class.dart';
import 'package:regalos/core/motion/step_segments.dart';
import 'package:regalos/features/lock/presentation/pin_pad.dart';
import 'package:regalos/features/lock/presentation/pin_setup_screen.dart';
import 'package:regalos/features/sharing/presentation/join_qr_screen.dart';
import 'package:regalos/features/sharing/presentation/scan_viewfinder.dart';

import '../helpers/memory_stores.dart';
import '../helpers/screens.dart';
import '../helpers/settings_column.dart' show tapVisible;
import '../helpers/tablet.dart';
import 'first_run_test.dart' show addPerson;

/// Los bordes de una columna de [width] centrada en una ventana de [size].
({double left, double right}) columnOf(Size size, double width) =>
    (left: (size.width - width) / 2, right: (size.width + width) / 2);

/// Todo lo que encuentra [finder] cae dentro de la columna de [width].
void expectInColumn(
  WidgetTester tester,
  Size size,
  Finder finder, {
  double width = RegalosLayout.onboardingColumn,
  String? reason,
}) {
  final column = columnOf(size, width);
  expect(finder, findsWidgets, reason: reason);
  for (final element in finder.evaluate()) {
    final rect = tester.getRect(find.byElementPredicate((e) => e == element));
    expect(
      rect.left,
      greaterThanOrEqualTo(column.left - 0.01),
      reason: '$reason: $rect',
    );
    expect(
      rect.right,
      lessThanOrEqualTo(column.right + 0.01),
      reason: '$reason: $rect',
    );
  }
}

/// Todos los botones a la vista caben en la columna del primer uso.
void expectButtonsInColumn(WidgetTester tester, Size size, String step) {
  final column = columnOf(size, RegalosLayout.onboardingColumn);
  final buttons = find.bySubtype<ButtonStyleButton>();
  expect(buttons, findsWidgets, reason: step);
  for (final element in buttons.evaluate()) {
    final rect = tester.getRect(find.byElementPredicate((e) => e == element));
    expect(
      rect.left,
      greaterThanOrEqualTo(column.left),
      reason: '$step: $rect',
    );
    expect(rect.right, lessThanOrEqualTo(column.right), reason: '$step: $rect');
  }
}

/// La cabecera (indicador de pasos) y el título del paso van en la columna.
void expectStep(WidgetTester tester, Size size, String title) {
  expect(find.text(title), findsOneWidget);
  expectInColumn(tester, size, find.text(title), reason: title);
  expectInColumn(tester, size, find.byType(StepSegments), reason: title);
  expectButtonsInColumn(tester, size, title);
  expect(tester.takeException(), isNull, reason: title);
}

/// Un lector de pruebas que cuenta cuántas veces se crea: si girar reinicia la
/// cámara, se nota.
class _CountingScanner extends StatefulWidget {
  const _CountingScanner({required this.onCode});

  final ValueChanged<String> onCode;

  static int created = 0;

  @override
  State<_CountingScanner> createState() => _CountingScannerState();
}

class _CountingScannerState extends State<_CountingScanner> {
  @override
  void initState() {
    super.initState();
    _CountingScanner.created++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

Widget _scanner(BuildContext context, ValueChanged<String> onCode) =>
    _CountingScanner(onCode: onCode);

/// El cuadro de reposo del visor, en las coordenadas de la cámara.
Rect viewfinderRect(WidgetTester tester) =>
    ((tester
                    .widget<CustomPaint>(
                      find
                          .descendant(
                            of: find.byType(ScanViewfinder),
                            matching: find.byType(CustomPaint),
                          )
                          .first,
                    )
                    .painter!)
                as dynamic)
            .rect
        as Rect;

void main() {
  tabletScreenTest('los cinco pasos van en una columna de 520 y ningún botón '
      'es más ancho', (tester, phone, size) async {
    await pumpRegalos(tester, phone);
    final column = columnOf(size, RegalosLayout.onboardingColumn);

    // 1. Bienvenida.
    expectStep(tester, size, 'Te damos la bienvenida a Gift Huddle');
    expect(find.text('Paso 1 de 5'), findsOneWidget);
    expectInColumn(tester, size, find.text('Paso 1 de 5'));
    final start = tester.getRect(find.widgetWithText(FilledButton, 'Empezar'));
    // El botón ocupa la columna menos sus márgenes de 20, centrado.
    expect(start.left, column.left + 20);
    expect(start.right, column.right - 20);
    expectInColumn(
      tester,
      size,
      find.widgetWithText(TextField, 'Nombre de este móvil'),
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre de este móvil'),
      'Tablet de Ana',
    );
    await tapText(tester, 'Empezar');

    // 2. Personas.
    expectStep(tester, size, '¿A quién le regaláis?');
    await addPerson(tester, 'Aritz', relation: 'Hijo');
    await addPerson(tester, 'Nora');
    expectStep(tester, size, '¿A quién le regaláis?');
    expectInColumn(tester, size, find.text('Aritz'));
    final next = tester.getRect(find.widgetWithText(FilledButton, 'Siguiente'));
    expect(next.left, column.left + 20);
    expect(next.right, column.right - 20);
    await tapText(tester, 'Siguiente');

    // 3. Quién regala.
    expectStep(tester, size, '¿Quién regala?');
    await tapLabel(tester, 'Añadir Abuelos');
    expectStep(tester, size, '¿Quién regala?');
    await tapText(tester, 'Siguiente');

    // 4. Ocasiones.
    expectStep(tester, size, '¿Cuándo hay regalos?');
    expectInColumn(tester, size, find.byType(CheckboxListTile));
    await tapText(tester, 'Siguiente');

    // 5. PIN: crear uno abre el teclado centrado; se deja para luego.
    expectStep(tester, size, 'Protege los regalos');
    final create = tester.getRect(
      find.widgetWithText(FilledButton, 'Crear PIN'),
    );
    expect(create.left, column.left + 20);
    expect(create.right, column.right - 20);
    await tapText(tester, 'Crear PIN');
    expect(find.byType(PinSetupScreen), findsOneWidget);
    final block = tester.getRect(
      find.descendant(
        of: find.byType(PinBlock),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    expect(block.center.dx, closeTo(size.width / 2, 0.5));
    expect(block.width, lessThanOrEqualTo(PinBlock.maxWidth));
    expect(block.center.dy, lessThan(size.height / 2));
    await tapText(tester, 'Ahora no');
    expect(find.byType(PinSetupScreen), findsNothing);
    expectStep(tester, size, 'Protege los regalos');
    await tapText(tester, 'Ahora no');

    // Ya en Personas, con lo elegido.
    expect(find.text('Te damos la bienvenida a Gift Huddle'), findsNothing);
    final state = await familyState(tester, phone);
    expect(state.identity!.deviceName, 'Tablet de Ana');
    expect(state.view.recipients.map((r) => r.name), ['Aritz', 'Nora']);
    expect(tester.takeException(), isNull);
  });

  tabletScreenTest(
    'con el texto al 130 % los pasos no desbordan',
    (tester, phone, size) async {
      await pumpRegalos(tester, phone);
      expectStep(tester, size, 'Te damos la bienvenida a Gift Huddle');
      await tapText(tester, 'Empezar');
      await addPerson(tester, 'Nora');
      expectStep(tester, size, '¿A quién le regaláis?');
      await tapText(tester, 'Siguiente');
      expectStep(tester, size, '¿Quién regala?');
      await tapText(tester, 'Siguiente');
      expectStep(tester, size, '¿Cuándo hay regalos?');
      await tapText(tester, 'Siguiente');
      expectStep(tester, size, 'Protege los regalos');
    },
    sizes: const [kTabletPortrait],
    textScale: 1.3,
  );

  tabletScreenTest('el eje compartido entre pasos no cambia; con «Reducir '
      'movimiento» nada se mueve', (tester, phone, size) async {
    await pumpRegalos(tester, phone);
    final title = find.text('Te damos la bienvenida a Gift Huddle');
    final rest = tester.getTopLeft(title).dx;
    await tester.tap(find.text('Empezar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    // El paso que se va sale hacia atrás, 24 px como mucho.
    expect(title, findsOneWidget);
    expect(tester.getTopLeft(title).dx, lessThan(rest));
    expect(tester.getTopLeft(title).dx, greaterThanOrEqualTo(rest - 24));
    await tester.pumpAndSettle();
    expect(title, findsNothing);
    final people = find.text('¿A quién le regaláis?');
    final peopleRest = tester.getTopLeft(people).dx;
    expect(
      peopleRest,
      columnOf(size, RegalosLayout.onboardingColumn).left + 20,
    );

    // Con «Reducir movimiento», al volver nada se desplaza.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    if (people.evaluate().isNotEmpty) {
      expect(tester.getTopLeft(people).dx, peopleRest);
    }
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(title).dx, closeTo(rest, 0.01));
  });

  tabletScreenTest('girar a mitad del primer uso conserva el paso y lo '
      'escrito', (tester, phone, size) async {
    await pumpRegalos(tester, phone);
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre de este móvil'),
      'Tablet de Ana',
    );
    await tapText(tester, 'Empezar');
    await addPerson(tester, 'Nora');

    await rotate(tester);
    await tester.pump();
    expect(tester.takeException(), isNull);
    final turned = windowSize(tester);
    expectStep(tester, turned, '¿A quién le regaláis?');
    expect(find.text('Nora'), findsOneWidget);

    // Hasta el ancho del móvil y vuelta.
    await setWindowSize(tester, kPhoneSize);
    expect(tester.takeException(), isNull);
    expect(find.text('Nora'), findsOneWidget);
    expect(tester.getTopLeft(find.text('¿A quién le regaláis?')).dx, 20);
    await setWindowSize(tester, size);
    expectStep(tester, size, '¿A quién le regaláis?');

    // Al volver a la bienvenida, el nombre sigue escrito.
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text('Tablet de Ana'), findsOneWidget);
  });

  screenTest('en el móvil el primer uso ocupa todo el ancho, como siempre', (
    tester,
    phone,
  ) async {
    await pumpRegalos(tester, phone);
    final start = tester.getRect(find.widgetWithText(FilledButton, 'Empezar'));
    expect(start.left, 20);
    expect(start.right, kPhoneSize.width - 20);
    final segments = tester.getRect(find.byType(StepSegments));
    expect(segments.left, 48);
    expect(segments.right, kPhoneSize.width - 16);
    await tapText(tester, 'Empezar');
    await addPerson(tester, 'Nora');
    final next = tester.getRect(find.widgetWithText(FilledButton, 'Siguiente'));
    expect(next.left, 20);
    expect(next.right, kPhoneSize.width - 20);
    expect(next.bottom, kPhoneSize.height - 12);
  });

  group('«Escanear el QR»', () {
    tabletScreenTest(
      'la cámara va en un cuadro de 480 como mucho: centrado con el texto '
      'debajo en vertical y a la izquierda del texto en horizontal',
      (tester, phone, size) async {
        _CountingScanner.created = 0;
        await pumpRegalos(tester, phone);
        await tapWelcomeChoice(tester, 'Escanear el QR');
        expect(tester.takeException(), isNull);
        final expanded = WindowClass.fromSize(size) == WindowClass.expanded;
        final camera = tester.getRect(find.byType(_CountingScanner));
        final field = tester.getRect(
          find.widgetWithText(TextField, 'Nombre de este móvil'),
        );
        final intro = tester.getRect(
          find.text('Apunta la cámara al código QR del otro móvil.'),
        );
        final header = tester.getRect(find.text('Escanear el QR'));

        // Un cuadro: nunca más de 480 de lado.
        expect(camera.width, camera.height);
        expect(camera.width, lessThanOrEqualTo(JoinQrScreen.cameraMaxSide));
        expect(camera.width, greaterThanOrEqualTo(JoinQrScreen.cameraMinSide));
        // Entero a la vista, bajo la cabecera.
        expect(camera.top, greaterThan(header.bottom));
        expect(camera.bottom, lessThan(size.height));

        if (expanded) {
          // Cámara a la izquierda y texto a la derecha, en una columna de 720.
          final column = columnOf(size, RegalosLayout.detailMaxWidth);
          expect(camera.left, column.left + 20);
          expect(intro.left, greaterThan(camera.right));
          expect(field.left, greaterThan(camera.right));
          expect(field.right, column.right - 20);
          expect(field.width, greaterThanOrEqualTo(260));
          expect(intro.top, camera.top);
          expectInColumn(
            tester,
            size,
            find.text('Escanear el QR'),
            width: RegalosLayout.detailMaxWidth,
          );
        } else {
          // Cámara de 480 centrada y el texto debajo, en la columna de 520.
          expect(camera.width, JoinQrScreen.cameraMaxSide);
          expect(camera.center.dx, size.width / 2);
          expect(intro.top, greaterThan(camera.bottom));
          expect(field.top, greaterThan(intro.bottom));
          expect(field.left, camera.left);
          expect(field.right, camera.right);
          expectInColumn(tester, size, find.text('Escanear el QR'));
        }

        // El visor no se deforma: sus esquinas son un cuadrado de 200 en el
        // centro de la cámara.
        final finder = tester.getRect(find.byType(ScanViewfinder));
        expect(finder, camera);
        final rest = viewfinderRect(tester);
        expect(rest.size, const Size(200, 200));
        expect(rest.center, camera.size.center(Offset.zero));
      },
      scanner: _scanner,
    );

    tabletScreenTest(
      'girar no reinicia la cámara ni pierde el nombre, y el visor sigue '
      'cuadrado y centrado',
      (tester, phone, size) async {
        _CountingScanner.created = 0;
        await pumpRegalos(tester, phone);
        await tapWelcomeChoice(tester, 'Escanear el QR');
        expect(_CountingScanner.created, 1);
        await tester.enterText(
          find.widgetWithText(TextField, 'Nombre de este móvil'),
          'Tablet de Eva',
        );
        final viewfinder = tester.state<ScanViewfinderState>(
          find.byType(ScanViewfinder),
        );
        // Con las esquinas cerradas (se acaba de leer un código).
        viewfinder.lock(null);
        await tester.pumpAndSettle();

        for (final next in [
          Size(size.height, size.width),
          kPhoneSize,
          // El móvil en horizontal: compacto, la cámara ocupa lo que queda.
          const Size(844, 390),
          size,
        ]) {
          await setWindowSize(tester, next);
          await tester.pump();
          expect(tester.takeException(), isNull, reason: '$next');
          // La misma cámara y el mismo visor: ni uno ni otro se han vuelto a
          // crear.
          expect(_CountingScanner.created, 1, reason: '$next');
          expect(
            tester.state<ScanViewfinderState>(find.byType(ScanViewfinder)),
            same(viewfinder),
            reason: '$next',
          );
          expect(viewfinder.locked, isTrue);
          expect(find.text('Tablet de Eva'), findsOneWidget, reason: '$next');
          // Las esquinas siguen siendo un cuadrado en el centro de la cámara,
          // cerrado un 8 %.
          final camera = tester.getSize(find.byType(_CountingScanner));
          final corners = viewfinderRect(tester);
          expect(corners.width, closeTo(corners.height, 0.01));
          expect(corners.center.dx, closeTo(camera.width / 2, 0.01));
          expect(corners.center.dy, closeTo(camera.height / 2, 0.01));
          final side = camera.shortestSide < 200 ? camera.shortestSide : 200.0;
          expect(corners.width, closeTo(side * 0.92, 0.5), reason: '$next');
        }
      },
      scanner: _scanner,
    );

    screenTest(
      'en el móvil la cámara ocupa lo que queda bajo el nombre, como siempre',
      (tester, phone) async {
        await pumpRegalos(tester, phone);
        await tapWelcomeChoice(tester, 'Escanear el QR');
        final camera = tester.getRect(find.byType(_CountingScanner));
        final field = tester.getRect(
          find.widgetWithText(TextField, 'Nombre de este móvil'),
        );
        final intro = tester.getRect(
          find.text('Apunta la cámara al código QR del otro móvil.'),
        );
        // Frase en la cabecera, campo y cámara, de arriba abajo.
        expect(intro.bottom, lessThan(field.top));
        expect(field.left, 16);
        expect(field.right, kPhoneSize.width - 16);
        expect(camera.top, greaterThan(field.bottom));
        expect(camera.left, 16);
        expect(camera.right, kPhoneSize.width - 16);
        expect(camera.bottom, kPhoneSize.height - 16);
        expect(viewfinderRect(tester).size, const Size(200, 200));
      },
      scanner: _scanner,
    );
  });

  tabletScreenTest('«Unirme con un enlace» va en la columna de 520', (
    tester,
    phone,
    size,
  ) async {
    await pumpRegalos(tester, phone);
    await tapWelcomeChoice(tester, 'Unirme con un enlace');
    expect(tester.takeException(), isNull);
    final column = columnOf(size, RegalosLayout.onboardingColumn);
    final ask = tester.getRect(
      find.widgetWithText(FilledButton, 'Pedir entrada'),
    );
    expect(ask.left, column.left + 20);
    expect(ask.right, column.right - 20);
    expectInColumn(tester, size, find.byType(TextField));
    expectInColumn(tester, size, find.text('Unirme con un enlace'));
    expectInColumn(tester, size, find.bySemanticsLabel('Atrás'));

    // Girar conserva lo pegado.
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre de este móvil'),
      'Tablet de Eva',
    );
    await rotate(tester);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Tablet de Eva'), findsOneWidget);
    expectInColumn(tester, windowSize(tester), find.byType(TextField));
  }, scanner: _scanner);

  screenTest('en el móvil «Unirme con un enlace» ocupa todo el ancho', (
    tester,
    phone,
  ) async {
    await pumpRegalos(tester, phone);
    await tapWelcomeChoice(tester, 'Unirme con un enlace');
    final ask = tester.getRect(
      find.widgetWithText(FilledButton, 'Pedir entrada'),
    );
    expect(ask.left, 20);
    expect(ask.right, kPhoneSize.width - 20);
  });

  group('el QR de «Conectar otro móvil»', () {
    Future<void> showQr(WidgetTester tester, FakePhone phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      phone.container.read(routerProvider).go('/settings/share');
      await settle(tester);
      // En el móvil girado (844×390) la fila queda bajo la barra inferior:
      // se lleva a la vista antes de pulsarla.
      await tapVisible(tester, find.text('Conectar otro móvil'));
      await tapVisible(tester, find.text('Está aquí'));
      expect(find.byType(QrImageView), findsOneWidget);
    }

    tabletScreenTest('mide 320 y va centrado en su hoja', (
      tester,
      phone,
      size,
    ) async {
      await showQr(tester, phone);
      expect(tester.takeException(), isNull);
      final qr = tester.getRect(find.byType(QrImageView));
      expect(qr.size, const Size(320, 320));
      final sheet = tester.getRect(find.byType(BottomSheet));
      expect(qr.center.dx, closeTo(sheet.center.dx, 0.5));
      // Entero a la vista, con su aviso y el botón de cerrar.
      expect(qr.top, greaterThan(0));
      expect(tester.getRect(find.text('Cerrar')).bottom, lessThan(size.height));
      expect(find.textContaining('No hagas captura'), findsOneWidget);

      // Al girar sigue midiendo 320.
      await rotate(tester);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(QrImageView)), const Size(320, 320));
    });

    screenTest('en el móvil mide 260, como siempre', (tester, phone) async {
      await showQr(tester, phone);
      expect(tester.getSize(find.byType(QrImageView)), const Size(260, 260));
    }, size: const Size(390, 1500));

    screenTest(
      'el móvil en horizontal es compacto: 260 aunque la ventana sea ancha',
      (tester, phone) async {
        await showQr(tester, phone);
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(QrImageView)), const Size(260, 260));
      },
      size: const Size(844, 390),
    );
  });
}
