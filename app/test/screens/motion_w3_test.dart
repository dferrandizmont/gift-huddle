// La pasada de movimiento de W3: indicadores del carrusel que siguen al dedo,
// fundido del borde del visor en el panel de lista, tercera columna
// escalonada, vuelo del avatar con dos paneles y cambio de pestaña.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/app.dart';
import 'package:regalos/core/motion/fading_branch_container.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/core/widgets/person_avatar.dart';
import 'package:regalos/core/widgets/screen_header.dart';
import 'package:regalos/features/people/presentation/countdown_carousel.dart';
import 'package:regalos/features/people/presentation/people_screen.dart';

import '../helpers/screens.dart';

const _desktop = Size(1280, 800);
const _desktopWide = Size(1760, 1000);

Color _dot(WidgetTester tester, int i) {
  final box = tester.widget<DecoratedBox>(
    find.byKey(ValueKey<String>('carousel-dot-$i')),
  );
  return (box.decoration as BoxDecoration).color!;
}

/// La opacidad más baja entre los `Opacity` y `FadeTransition` por encima de
/// [target].
double _minOpacity(WidgetTester tester, Finder target) {
  var lowest = 1.0;
  for (final o in tester.widgetList<Opacity>(
    find.ancestor(of: target, matching: find.byType(Opacity)),
  )) {
    if (o.opacity < lowest) {
      lowest = o.opacity;
    }
  }
  for (final f in tester.widgetList<FadeTransition>(
    find.ancestor(of: target, matching: find.byType(FadeTransition)),
  )) {
    if (f.opacity.value < lowest) {
      lowest = f.opacity.value;
    }
  }
  return lowest;
}

void main() {
  group('indicadores del carrusel', () {
    screenTest('siguen al dedo durante el arrastre, sin saltar', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      final tokens = RegalosTokens.of(
        tester.element(find.byType(PeopleScreen)),
      );
      // En reposo: el primero encendido, el segundo apagado.
      expect(_dot(tester, 0), tokens.ink);
      expect(_dot(tester, 1), tokens.track);

      final drag = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      var previous = 0.0;
      // Cada paso del dedo enciende el siguiente un poco más y apaga el
      // anterior otro poco: valores intermedios, nunca un salto de golpe.
      for (var step = 0; step < 10; step++) {
        await drag.moveBy(const Offset(-30, 0));
        await tester.pump(const Duration(milliseconds: 16));
        final next = _dot(tester, 1);
        final lit =
            (next.r - tokens.track.r).abs() /
            ((tokens.ink.r - tokens.track.r).abs());
        expect(lit, greaterThanOrEqualTo(previous));
        expect(lit - previous, lessThan(0.5), reason: 'paso $step');
        previous = lit;
      }
      expect(previous, greaterThan(0));
      expect(previous, lessThan(1));
      expect(_dot(tester, 0), isNot(tokens.ink));
      expect(_dot(tester, 0), isNot(tokens.track));
      await drag.up();
      await settle(tester);
      expect(_dot(tester, 1), tokens.ink);
      expect(_dot(tester, 0), tokens.track);
    });

    test('la cobertura de un punto es lo que cubre la ventana de tarjetas', () {
      // Una tarjeta a la vista, entre la 1 y la 2.
      expect(carouselDotCoverage(0, 0.5, 1), closeTo(0.5, 1e-9));
      expect(carouselDotCoverage(1, 0.5, 1), closeTo(0.5, 1e-9));
      expect(carouselDotCoverage(2, 0.5, 1), 0);
      // Dos a la vez: la ventana [0, 2) enciende los dos primeros.
      expect(carouselDotCoverage(0, 0, 2), 1);
      expect(carouselDotCoverage(1, 0, 2), 1);
      expect(carouselDotCoverage(2, 0, 2), 0);
    });
  });

  group('borde del visor del carrusel', () {
    screenTest(
      'en el panel de lista de dos paneles (por debajo del escritorio) la '
      'tarjeta que asoma se funde hacia el fondo',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        final fade = find.byKey(const ValueKey<String>('carousel-edge-fade'));
        expect(fade, findsOneWidget);
        final list = tester.getRect(find.byType(PeopleListPane));
        final shade = tester.getRect(fade);
        // Pegado al filete de la derecha del panel y dentro de él.
        expect(shade.right, closeTo(list.right, 0.5));
        expect(shade.width, lessThanOrEqualTo(32));
      },
      // Desde 1280 la próxima ocasión es una fila, no un carrusel.
      size: const Size(1100, 800),
    );

    screenTest('en el móvil no hay fundido: nada cambia', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      expect(
        find.byKey(const ValueKey<String>('carousel-edge-fade')),
        findsNothing,
      );
    });
  });

  group('tercera columna', () {
    screenTest(
      'entra con su panel (el último, a los 80 ms) al montarse con los paneles',
      (tester, phone) async {
        await seedSample(tester, phone);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: phone.container,
            child: const RegalosApp(),
          ),
        );
        final column = find.byType(SummaryColumn);
        // Hasta que llegan los datos y se monta la columna.
        for (var i = 0; i < 80 && column.evaluate().isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(column, findsOneWidget);
        final title = find.descendant(
          of: column,
          matching: find.text('Resumen'),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          _minOpacity(tester, title),
          lessThan(1),
          reason: 'la columna y su título todavía están entrando',
        );
        await settle(tester);
        expect(_minOpacity(tester, title), 1);
        expect(tester.takeException(), isNull);
      },
      size: _desktopWide,
    );
  });

  group('cabeceras de dos paneles', () {
    screenTest('el título del detalle cae a la altura del de la lista', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      final headers = find.byType(ScreenHeader);
      expect(headers, findsAtLeastNWidgets(2));
      double titleTop(Finder header, String text) => tester
          .getTopLeft(
            find.descendant(of: header, matching: find.text(text)).first,
          )
          .dy;
      final list = titleTop(headers.first, 'Personas');
      final detail = titleTop(headers.at(1), 'Aritz');
      expect(detail, closeTo(list, 0.5));
    }, size: _desktop);
  });

  group('avatar con dos paneles', () {
    Finder row(String name) => find.descendant(
      of: find.byType(PeopleListPane),
      matching: find.text(name),
    );

    screenTest(
      'al elegir otra persona no hay vuelo: la cabecera nunca se queda sin '
      'avatar y entra de 0,92 a 1',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        final before = find.byType(PersonAvatar).evaluate().length;
        await tester.tap(row('Nora'));
        await tester.pump();
        for (final ms in [1, 40, 60]) {
          await tester.pump(Duration(milliseconds: ms));
          expect(
            find.byType(PersonAvatar).evaluate().length,
            lessThanOrEqualTo(before + 1),
            reason:
                'ningún avatar viaja encima de la lista (sin capa de vuelo)',
          );
        }
        // El de la cabecera del detalle ya existe y asienta su escala.
        final header = find.descendant(
          of: find.byType(ScreenHeader).at(1),
          matching: find.byType(PersonAvatar),
        );
        expect(header, findsOneWidget);
        double scale() => tester
            .widgetList<Transform>(
              find.ancestor(of: header, matching: find.byType(Transform)),
            )
            .map((t) => t.transform.storage[0])
            .fold<double>(1, (a, b) => a * b);
        expect(scale(), inExclusiveRange(0.92, 1));
        await settle(tester);
        expect(scale(), closeTo(1, 1e-9));
        expect(find.byType(PersonAvatar).evaluate().length, before);
        expect(tester.takeException(), isNull);
      },
      size: _desktop,
    );

    screenTest('con «Reducir movimiento» el avatar no escala', (
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
      await tester.tap(row('Nora'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      final header = find.descendant(
        of: find.byType(ScreenHeader).at(1),
        matching: find.byType(PersonAvatar),
      );
      final scales = tester
          .widgetList<Transform>(
            find.ancestor(of: header, matching: find.byType(Transform)),
          )
          .map((t) => t.transform.storage[0]);
      expect(scales.where((s) => s != 1), isEmpty);
      await settle(tester);
    }, size: _desktop);
  });

  group('cambio de pestaña', () {
    screenTest(
      'volver a Personas no repite su entrada: ni sube ni se escalona',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tapText(tester, 'Reparto');
        await settle(tester);
        await tapText(tester, 'Personas');
        // El fundido de la pestaña dura 150 ms; una entrada escalonada
        // repetida seguiría a los 300 ms.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final nora = find.descendant(
          of: find.byType(PeopleListPane),
          matching: find.text('Nora'),
        );
        expect(_minOpacity(tester, nora), 1);
        // Sin traslación de la pestaña entera.
        final shift = tester
            .widgetList<Transform>(
              find.ancestor(of: nora, matching: find.byType(Transform)),
            )
            .map((t) => t.transform.getTranslation().y.abs())
            .fold<double>(0, (a, b) => a + b);
        expect(shift, 0);
      },
    );
  });

  group('hoja de persona de Reparto', () {
    Future<void> open(WidgetTester tester) async {
      await tapText(tester, 'Reparto');
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Abrir la ficha de Aritz').first);
      await tester.pump();
    }

    screenTest('sus opciones entran escalonadas', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await open(tester);
      await tester.pump(const Duration(milliseconds: 160));
      final first = find.text('Sale en el reparto');
      final last = find.textContaining('Abrir la lista de');
      expect(first, findsOneWidget);
      // A mitad de la entrada unas opciones van por delante de otras.
      final early = _minOpacity(tester, first);
      final late = last.evaluate().isEmpty ? 0.0 : _minOpacity(tester, last);
      expect(early, lessThan(1));
      expect(late, lessThan(early + 0.0001));
      await settle(tester);
      expect(_minOpacity(tester, first), closeTo(1, 0.001));
      expect(tester.takeException(), isNull);
    });

    screenTest('con «Reducir movimiento» solo se funden, sin subir', (
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
      await open(tester);
      await settle(tester);
      final shift = tester
          .widgetList<Transform>(
            find.ancestor(
              of: find.text('Sale en el reparto'),
              matching: find.byType(Transform),
            ),
          )
          .map((t) => t.transform.getTranslation().y.abs())
          .fold<double>(0, (a, b) => a + b);
      expect(shift, 0);
    });
  });

  group('contenedor de pestañas', () {
    Future<void> pump(WidgetTester tester, int index, {bool reduce = false}) =>
        tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(disableAnimations: reduce),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: FadingBranchContainer(
                currentIndex: index,
                children: const [Text('A'), Text('B')],
              ),
            ),
          ),
        );

    double shift(WidgetTester tester, String text) => tester
        .widgetList<Transform>(
          find.ancestor(of: find.text(text), matching: find.byType(Transform)),
        )
        .map((t) => t.transform.getTranslation().y)
        .fold<double>(0, (a, b) => a + b);

    double opacity(WidgetTester tester, String text) => tester
        .widgetList<FadeTransition>(
          find.ancestor(
            of: find.text(text),
            matching: find.byType(FadeTransition),
          ),
        )
        .map((f) => f.opacity.value)
        .fold<double>(1, (a, b) => a * b);

    testWidgets('la pestaña que llega se funde en 100 ms y no sube', (
      tester,
    ) async {
      await pump(tester, 0);
      expect(shift(tester, 'A'), 0, reason: 'la primera aparece sin nada');
      await pump(tester, 1);
      await tester.pump(const Duration(milliseconds: 40));
      expect(opacity(tester, 'B'), inExclusiveRange(0, 1));
      expect(shift(tester, 'B'), 0, reason: 'ya no sube 6 px');
      await tester.pump(const Duration(milliseconds: 70));
      expect(opacity(tester, 'B'), 1, reason: 'a los 110 ms ya acabó');
      await tester.pumpAndSettle();
      expect(shift(tester, 'B'), 0);
    });

    testWidgets('con «Reducir movimiento» solo se funde, en 150 ms', (
      tester,
    ) async {
      await pump(tester, 0, reduce: true);
      await pump(tester, 1, reduce: true);
      await tester.pump(const Duration(milliseconds: 40));
      expect(opacity(tester, 'B'), inExclusiveRange(0, 1));
      expect(shift(tester, 'B'), 0);
      await tester.pump(const Duration(milliseconds: 70));
      expect(opacity(tester, 'B'), inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
    });

    testWidgets('cambiar el tamaño de la ventana no la anima', (tester) async {
      await pump(tester, 1);
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(900, 600);
      addTearDown(tester.view.reset);
      await tester.pump();
      expect(opacity(tester, 'B'), 1);
      expect(shift(tester, 'B'), 0);
    });
  });
}
