import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/layout/pane_scope.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/core/widgets/gift_row.dart';
import 'package:regalos/core/widgets/regalos_nav_bar.dart';
import 'package:regalos/core/widgets/regalos_nav_rail.dart';
import 'package:regalos/core/widgets/stroke_icon.dart';

import '../helpers/screens.dart';
import '../helpers/tablet.dart';
import '../widgets/motion_shared_test.dart' show moving;

// Tanda T1 del plan de tablet (la guía de diseño para tablet, §6): barra
// inferior en compacto, raíl lateral desde 600 dp, y nada se pierde al girar.

final _rail = find.byType(RegalosNavRail);
final _bar = find.byType(RegalosNavBar);
// El área de contenido de la pestaña: el `PaneScope` de `AppShell`, el primero
// del árbol (con dos paneles hay más dentro de él).
final _pane = find.byType(PaneScope).first;
final _indicator = find.byKey(const ValueKey('nav-indicator'));

/// La etiqueta de un destino dentro de la navegación (raíl o barra), y no el
/// título de una pantalla que se llame igual.
Finder _destination(String label) => find.descendant(
  of: find.bySemanticsLabel('Navegación principal'),
  matching: find.text(label),
);

Future<void> _go(WidgetTester tester, String label) async {
  await tester.tap(_destination(label));
  await settle(tester);
}

/// El icono del destino [label].
Finder _iconOf(String label) => find.descendant(
  of: find.ancestor(of: _destination(label), matching: find.byType(InkWell)),
  matching: find.byType(StrokeIcon),
);

/// Comprueba que la ventana lleva raíl (y no barra) y que el área de contenido
/// es lo que queda a su derecha.
void _expectRail(WidgetTester tester) {
  final window = windowSize(tester);
  expect(_rail, findsOneWidget);
  expect(_bar, findsNothing);
  expect(
    tester.getRect(_rail),
    Rect.fromLTWH(0, 0, 80, window.height),
    reason: 'raíl a la izquierda, de arriba abajo',
  );
  expect(
    tester.getRect(_pane),
    Rect.fromLTWH(80, 0, window.width - 80, window.height),
    reason: 'el contenido ocupa el resto',
  );
}

/// Comprueba que la ventana lleva la barra inferior de siempre (y no raíl).
void _expectBar(WidgetTester tester) {
  final window = windowSize(tester);
  expect(_bar, findsOneWidget);
  expect(_rail, findsNothing);
  final bar = tester.getRect(_bar);
  expect(bar.left, 0);
  expect(bar.width, window.width);
  expect(bar.bottom, window.height);
  expect(
    tester.getRect(_pane),
    Rect.fromLTWH(0, 0, window.width, bar.top),
    reason: 'el contenido va de lado a lado, sobre la barra',
  );
}

void main() {
  group('raíl o barra según la ventana', () {
    tabletScreenTest(
      'por debajo de 600 dp, la barra de siempre; desde 600, raíl a la '
      'izquierda y ninguna barra abajo',
      (tester, phone, size) async {
        await bareFamily(tester, phone);
        await pumpRegalos(tester, phone);
        expect(find.bySemanticsLabel('Navegación principal'), findsOneWidget);
        for (final label in ['Personas', 'Reparto', 'Ocasiones', 'Ajustes']) {
          expect(_destination(label), findsOneWidget, reason: label);
        }
        if (size == kPhoneSize) {
          _expectBar(tester);
          expect(PaneScope.widthOf(tester.element(_bar)), 390);
        } else {
          _expectRail(tester);
        }
        // Dentro del panel, el ancho es el del área de contenido.
        final inside = tester.element(find.text('Aún no hay personas'));
        expect(
          PaneScope.widthOf(inside),
          size == kPhoneSize ? 390 : size.width - 80,
        );
        expect(PaneScope.roleOf(inside), PaneRole.single);
        expect(tester.takeException(), isNull);
      },
      sizes: kLayoutSizes,
    );

    screenTest(
      'el móvil en horizontal (alto menor de 480) sigue con la barra',
      (tester, phone) async {
        await bareFamily(tester, phone);
        await pumpRegalos(tester, phone);
        _expectBar(tester);
      },
      size: const Size(844, 390),
    );

    screenTest('media pantalla de 600 dp ya lleva raíl; con 599, barra', (
      tester,
      phone,
    ) async {
      await bareFamily(tester, phone);
      await pumpRegalos(tester, phone);
      _expectRail(tester);
      await setWindowSize(tester, const Size(599, 900));
      await settle(tester);
      _expectBar(tester);
    }, size: const Size(600, 900));

    screenTest('sin familia no hay raíl: el primer uso ocupa la ventana', (
      tester,
      phone,
    ) async {
      await pumpRegalos(tester, phone);
      expect(find.text('Te damos la bienvenida a Gift Huddle'), findsOneWidget);
      expect(_rail, findsNothing);
      expect(_bar, findsNothing);
    }, size: kTabletLandscape);
  });

  group('navegar con el raíl', () {
    tabletScreenTest('cada destino abre su rama y el recuadro viaja hasta su '
        'icono', (tester, phone, size) async {
      await bareFamily(tester, phone);
      await pumpRegalos(tester, phone);
      expect(find.text('Aún no hay personas'), findsOneWidget);

      Future<void> open(String label, String expected) async {
        await _go(tester, label);
        expect(find.text(expected), findsOneWidget, reason: label);
        final box = tester.getRect(_indicator);
        final icon = tester.getRect(_iconOf(label));
        expect(box.size, const Size(56, 30), reason: label);
        expect(box.center.dx, closeTo(icon.center.dx, 0.5), reason: label);
        expect(box.center.dy, closeTo(icon.center.dy, 0.5), reason: label);
        _expectRail(tester);
        expect(tester.takeException(), isNull, reason: label);
      }

      await open('Reparto', 'Nadie ha apuntado regalos');
      await open('Ocasiones', 'Sin ocasiones');
      await open('Ajustes', 'Apariencia');
      await open('Personas', 'Aún no hay personas');
    });

    tabletScreenTest('el recuadro se estira en vertical al cambiar de rama', (
      tester,
      phone,
      size,
    ) async {
      await bareFamily(tester, phone);
      await pumpRegalos(tester, phone);
      final rest = tester.getRect(_indicator);
      await tester.tap(_destination('Ajustes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final mid = tester.getRect(_indicator);
      expect(mid.height, greaterThan(rest.height + 30));
      expect(mid.width, rest.width);
      expect(mid.left, rest.left);
      await settle(tester);
      expect(tester.getRect(_indicator).height, closeTo(30, 0.01));
    });

    tabletScreenTest('tocar el destino activo vuelve a su primera pantalla', (
      tester,
      phone,
      size,
    ) async {
      await bareFamily(tester, phone);
      await pumpRegalos(tester, phone);
      await _go(tester, 'Ajustes');
      await tapText(tester, 'Apariencia');
      expect(find.text('Vista previa'), findsOneWidget);
      _expectRail(tester);

      await _go(tester, 'Ajustes');
      expect(find.text('Vista previa'), findsNothing);
      expect(find.text('Apariencia'), findsOneWidget);
    }, sizes: const [kTabletPortrait]);

    tabletScreenTest('cada rama conserva su pila al cambiar de pestaña', (
      tester,
      phone,
      size,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _go(tester, 'Ajustes');
      await tapText(tester, 'Apariencia');
      expect(find.text('Vista previa'), findsOneWidget);

      await _go(tester, 'Personas');
      expect(find.text('Vista previa'), findsNothing);
      await tapText(tester, 'Nora');
      expect(find.text('Cocinita de madera'), findsOneWidget);

      await _go(tester, 'Ajustes');
      expect(find.text('Vista previa'), findsOneWidget);
      await _go(tester, 'Personas');
      expect(find.text('Cocinita de madera'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    tabletScreenTest('la pantalla de segundo nivel se abre junto al raíl y se '
        'vuelve con la flecha', (tester, phone, size) async {
      await bareFamily(tester, phone);
      await pumpRegalos(tester, phone);
      await _go(tester, 'Ajustes');
      await tapText(tester, 'Apariencia');
      // El raíl sigue a la vista y la pantalla no lo pisa.
      _expectRail(tester);
      expect(
        tester.getRect(find.text('Vista previa')).left,
        greaterThanOrEqualTo(80),
      );
      await tester.tap(find.bySemanticsLabel('Volver a Ajustes'));
      await settle(tester);
      expect(find.text('Vista previa'), findsNothing);
      expect(find.text('Apariencia'), findsOneWidget);
    }, sizes: const [kTabletPortrait]);

    tabletScreenTest(
      'la pantalla nueva entra desde el 25 % del área de contenido, no de '
      'la ventana',
      (tester, phone, size) async {
        await bareFamily(tester, phone);
        await pumpRegalos(tester, phone);
        await _go(tester, 'Ajustes');
        await tester.tap(find.text('Apariencia'));
        // El primer fotograma de la ruta: aún no ha avanzado (sin dejar pasar
        // el tiempo, hasta que el router la monte).
        for (
          var i = 0;
          i < 5 && find.text('Vista previa').evaluate().isEmpty;
          i++
        ) {
          await tester.pump();
        }
        final start = tester.getRect(find.text('Vista previa')).left;
        await settle(tester);
        final end = tester.getRect(find.text('Vista previa')).left;
        expect(start - end, closeTo(0.25 * (size.width - 80), 0.01));
      },
      sizes: const [kTabletPortrait],
    );
  });

  group('girar y cambiar el tamaño de la ventana', () {
    tabletScreenTest('girar con una pantalla de segundo nivel abierta no la '
        'cierra ni la vuelve a montar', (tester, phone, size) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _go(tester, 'Ajustes');
      await tapText(tester, 'Apariencia');
      final screen = tester.element(find.text('Vista previa'));
      final pane = tester.state(_pane);

      await rotate(tester);
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(windowSize(tester), Size(size.height, size.width));
      _expectRail(tester);
      // La misma pantalla, no una nueva: el elemento es el de antes.
      expect(tester.element(find.text('Vista previa')), same(screen));
      expect(tester.state(_pane), same(pane));
      // El recuadro sigue sobre Ajustes y no ha viajado.
      expect(
        tester.getRect(_indicator).center.dy,
        closeTo(tester.getRect(_iconOf('Ajustes')).center.dy, 0.5),
      );

      // Y de vuelta.
      await rotate(tester);
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(tester.element(find.text('Vista previa')), same(screen));
      await tester.tap(find.bySemanticsLabel('Volver a Ajustes'));
      await settle(tester);
      expect(find.text('Vista previa'), findsNothing);
    }, sizes: const [kTabletPortrait]);

    tabletScreenTest('girar conserva la pila de las otras ramas y la posición '
        'de la lista', (tester, phone, size) async {
      await seedSample(tester, phone, extraPeople: 24);
      await pumpRegalos(tester, phone);
      await _go(tester, 'Ajustes');
      await tapText(tester, 'Apariencia');
      await _go(tester, 'Personas');

      // La lista de Personas, desplazada.
      final list = find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first;
      await tester.drag(list, const Offset(0, -240));
      await settle(tester);
      final scrollable = tester.state<ScrollableState>(list);
      final offset = scrollable.position.pixels;
      expect(offset, greaterThan(100));

      // Al girar se cruza el corte de los dos paneles (840): la lista pasa de
      // una página a otra y es otra lista, pero recuerda dónde estaba.
      await rotate(tester);
      await settle(tester);
      expect(tester.takeException(), isNull);
      _expectRail(tester);
      expect(
        tester.state<ScrollableState>(list).position.pixels,
        offset,
        reason: 'la posición de la lista tras girar',
      );
      await rotate(tester);
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(
        tester.state<ScrollableState>(list).position.pixels,
        offset,
        reason: 'y tras volver a girar',
      );

      await _go(tester, 'Ajustes');
      expect(find.text('Vista previa'), findsOneWidget);
    });

    screenTest('pasar de móvil a tablet y volver (pantalla partida) cambia la '
        'barra por el raíl sin desmontar nada', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _go(tester, 'Ajustes');
      await tapText(tester, 'Apariencia');
      await _go(tester, 'Personas');
      await tapText(tester, 'Nora');
      expect(find.text('Cocinita de madera'), findsOneWidget);
      _expectBar(tester);
      // La fila de regalo pasa a columnas desde 720 de ancho (el escritorio):
      // por dentro es otro árbol, pero ella misma no se desmonta.
      final screen = tester.element(find.byType(GiftRow).first);
      final pane = tester.state(_pane);

      for (final size in [kTabletPortrait, kTabletLandscape]) {
        await setWindowSize(tester, size);
        // Cruzar el corte no anima nada: el raíl está en el primer fotograma,
        // con el recuadro ya en su sitio.
        _expectRail(tester);
        final box = tester.getRect(_indicator);
        expect(
          box.center.dy,
          closeTo(tester.getRect(_iconOf('Personas')).center.dy, 0.5),
        );
        await settle(tester);
        _expectRail(tester);
        expect(tester.getRect(_indicator), box);
        expect(tester.takeException(), isNull, reason: sizeLabel(size));
        expect(tester.element(find.byType(GiftRow).first), same(screen));
        expect(tester.state(_pane), same(pane));
      }

      // La otra rama sigue donde estaba.
      await _go(tester, 'Ajustes');
      expect(find.text('Vista previa'), findsOneWidget);
      await _go(tester, 'Personas');

      await setWindowSize(tester, kPhoneSize);
      _expectBar(tester);
      final box = tester.getRect(_indicator);
      await settle(tester);
      _expectBar(tester);
      expect(tester.getRect(_indicator), box);
      expect(tester.takeException(), isNull);
      expect(tester.element(find.byType(GiftRow).first), same(screen));
      expect(tester.state(_pane), same(pane));
      // En la barra, el recuadro vuelve a estar sobre Personas.
      expect(
        tester.getRect(_indicator).center.dx,
        closeTo(tester.getRect(_iconOf('Personas')).center.dx, 0.5),
      );
    });
  });

  group('lectura de pantalla, texto grande, oscuro y «Reducir movimiento»', () {
    tabletScreenTest('los cuatro destinos se leen como botones y el activo, '
        'como seleccionado', (tester, phone, size) async {
      await bareFamily(tester, phone);
      await pumpRegalos(tester, phone);
      await _go(tester, 'Ocasiones');
      for (final label in ['Personas', 'Reparto', 'Ocasiones', 'Ajustes']) {
        final node = find.descendant(
          of: _rail,
          matching: find.bySemanticsLabel(label),
        );
        expect(
          tester.getSemantics(node),
          matchesSemantics(
            label: label,
            isButton: true,
            isSelected: label == 'Ocasiones',
            hasSelectedState: true,
            hasTapAction: true,
          ),
          reason: label,
        );
      }
    });

    tabletScreenTest('los destinos miden 72 × 56 o más', (
      tester,
      phone,
      size,
    ) async {
      await bareFamily(tester, phone);
      await pumpRegalos(tester, phone);
      final zones = find.descendant(of: _rail, matching: find.byType(InkWell));
      expect(zones, findsNWidgets(4));
      for (final e in zones.evaluate()) {
        final zone = tester.getSize(find.byWidget(e.widget));
        expect(zone.width, 72);
        expect(zone.height, greaterThanOrEqualTo(56));
      }
    });

    tabletScreenTest(
      'con el texto al 130 % las cuatro ramas caben junto al raíl sin '
      'desbordes',
      (tester, phone, size) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        expect(tester.takeException(), isNull);
        for (final label in ['Reparto', 'Ocasiones', 'Ajustes', 'Personas']) {
          await _go(tester, label);
          expect(tester.takeException(), isNull, reason: label);
          _expectRail(tester);
        }
      },
      sizes: const [kTabletPortrait],
      textScale: 1.3,
    );

    tabletScreenTest('en oscuro el raíl usa el fondo y el pastel del tema', (
      tester,
      phone,
      size,
    ) async {
      await bareFamily(tester, phone);
      await pumpRegalos(tester, phone);
      final t = RegalosTokens.of(tester.element(_rail));
      expect(Theme.of(tester.element(_rail)).brightness, Brightness.dark);
      expect(
        tester
            .widget<Material>(
              find.descendant(of: _rail, matching: find.byType(Material)),
            )
            .color,
        t.bg,
      );
      final deco =
          tester
                  .widget<DecoratedBox>(
                    find.descendant(
                      of: _indicator,
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect(deco.color, t.selection);
      expect(deco.borderRadius, RegalosShape.chip);
      await _go(tester, 'Reparto');
      expect(tester.takeException(), isNull);
    }, brightness: Brightness.dark);

    tabletScreenTest('con «Reducir movimiento» el recuadro no viaja y nada se '
        'traslada ni escala en el raíl', (tester, phone, size) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      await bareFamily(tester, phone);
      await pumpRegalos(tester, phone);
      final t = RegalosTokens.of(tester.element(_rail));
      expect(_indicator, findsNothing);

      bool lit(String label) {
        final box = tester.widget<AnimatedContainer>(
          find.descendant(
            of: find.ancestor(
              of: _destination(label),
              matching: find.byType(InkWell),
            ),
            matching: find.byType(AnimatedContainer),
          ),
        );
        return (box.decoration! as BoxDecoration).color == t.selection;
      }

      expect(lit('Personas'), isTrue);
      await tester.tap(_destination('Ajustes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expect(moving(tester, _rail), isEmpty);
      await settle(tester);
      expect(lit('Ajustes'), isTrue);
      expect(lit('Personas'), isFalse);
      expect(find.text('Apariencia'), findsOneWidget);

      // Girar tampoco mueve nada.
      await rotate(tester);
      expect(moving(tester, _rail), isEmpty);
      await settle(tester);
      _expectRail(tester);
      expect(lit('Ajustes'), isTrue);
    });
  });
}
