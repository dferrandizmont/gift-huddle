import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/motion/delivered_sweep.dart';
import 'package:regalos/core/motion/pop_in.dart';
import 'package:regalos/core/motion/rolling_number.dart';
import 'package:regalos/core/motion/shared_axis_switcher.dart';
import 'package:regalos/core/motion/sheen.dart';
import 'package:regalos/core/motion/stagger.dart';
import 'package:regalos/core/motion/step_segments.dart';
import 'package:regalos/core/motion/success_mark.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/core/widgets/budget_meter.dart';
import 'package:regalos/core/widgets/regalos_nav_bar.dart';
import 'package:regalos/core/widgets/stroke_icon.dart';
import 'package:regalos/features/occasions/presentation/occasion_garland.dart';
import 'package:regalos/features/sharing/presentation/scan_viewfinder.dart';

import '../helpers/pump_app.dart';
import 'motion_shared_test.dart' show moving;

/// La menor escala de los `Transform` dentro de [of] (1 si ninguno encoge).
double minScale(WidgetTester tester, Finder of) {
  var best = 1.0;
  for (final t in tester.widgetList<Transform>(
    find.descendant(of: of, matching: find.byType(Transform)),
  )) {
    best = math.min(best, t.transform.storage[0]);
  }
  return best;
}

void main() {
  group('la barra con el recuadro elástico (O)', () {
    final indicator = find.byKey(const ValueKey('nav-indicator'));
    double centerOf(int i) => 390 / 4 * (i + 0.5);

    late StateSetter set;
    var selected = 0;

    Future<void> pumpBar(WidgetTester tester, {bool reduce = false}) async {
      selected = 0;
      await pumpThemed(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return RegalosNavBar(
              semanticLabel: 'Navegación',
              selectedIndex: selected,
              onSelected: (_) {},
              destinations: const [
                NavDestination(icon: AppIcons.people, label: 'Uno'),
                NavDestination(icon: AppIcons.family, label: 'Dos'),
                NavDestination(icon: AppIcons.occasions, label: 'Tres'),
                NavDestination(icon: AppIcons.settings, label: 'Cuatro'),
              ],
            );
          },
        ),
        disableAnimations: reduce,
      );
    }

    testWidgets('se estira hacia el destino, se recoge al llegar y nunca '
        'cambia de alto', (tester) async {
      await pumpBar(tester);
      final rest = tester.getRect(indicator);
      expect(rest.width, 64);
      set(() => selected = 3);
      await tester.pump();
      var widest = 0.0;
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final r = tester.getRect(indicator);
        widest = math.max(widest, r.width);
        expect(r.height, 30);
      }
      // A mitad de camino cubre buena parte de la distancia entre destinos.
      expect(widest, greaterThan(64 + 60));
      await tester.pumpAndSettle();
      final end = tester.getRect(indicator);
      expect(end.width, closeTo(64, 0.01));
      expect(end.center.dx, closeTo(centerOf(3), 0.5));
    });

    testWidgets('el borde de delante sale antes que el de atrás, a un lado '
        'y a otro', (tester) async {
      await pumpBar(tester);
      final left0 = tester.getRect(indicator).left;
      final right0 = tester.getRect(indicator).right;
      set(() => selected = 2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      var r = tester.getRect(indicator);
      // Va a la derecha: sale el borde derecho; el izquierdo espera 70 ms.
      expect(r.right, greaterThan(right0 + 5));
      expect(r.left, closeTo(left0, 0.01));
      await tester.pumpAndSettle();

      final left2 = tester.getRect(indicator).left;
      final right2 = tester.getRect(indicator).right;
      set(() => selected = 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      r = tester.getRect(indicator);
      // Va a la izquierda: sale el borde izquierdo.
      expect(r.left, lessThan(left2 - 5));
      expect(r.right, closeTo(right2, 0.01));
      await tester.pumpAndSettle();
    });

    testWidgets('si se toca otro destino a mitad de camino, parte de donde '
        'está', (tester) async {
      await pumpBar(tester);
      set(() => selected = 3);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final mid = tester.getRect(indicator).center.dx;
      set(() => selected = 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      // Sin salto: el centro sigue cerca de donde estaba.
      expect((tester.getRect(indicator).center.dx - mid).abs(), lessThan(25));
      await tester.pumpAndSettle();
      expect(tester.getRect(indicator).center.dx, closeTo(centerOf(1), 0.5));
    });

    testWidgets('con «Reducir movimiento» no hay recuadro que viaje', (
      tester,
    ) async {
      await pumpBar(tester, reduce: true);
      expect(indicator, findsNothing);
      set(() => selected = 2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(indicator, findsNothing);
      await tester.pumpAndSettle();
    });
  });

  group('el presupuesto que cuenta (P)', () {
    late StateSetter set;
    var spent = '72,94 €';
    var fraction = 0.5;

    Future<void> pumpMeter(WidgetTester tester, {bool reduce = false}) async {
      spent = '72,94 €';
      fraction = 0.5;
      await pumpThemed(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return SizedBox(
              width: 200,
              child: BudgetMeter(
                label: 'Esta casa',
                valueText: (spent: spent, planned: '145 €', ofWord: 'de'),
                fraction: fraction,
                semanticLabel: 'Barra',
              ),
            );
          },
        ),
        disableAnimations: reduce,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('la cifra gastada rueda solo en las columnas que cambian', (
      tester,
    ) async {
      await pumpMeter(tester);
      expect(
        find.descendant(
          of: find.byType(BudgetMeter),
          matching: find.byType(RollingNumber),
        ),
        findsOneWidget,
      );
      set(() => spent = '81,94 €');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      // Rueda: hay una columna con dos cifras (la vieja y la nueva) a la vez.
      expect(find.text('7'), findsOneWidget);
      expect(find.text('8'), findsWidgets);
      // Las columnas que no cambian se quedan quietas, con su cifra.
      expect(find.text('9'), findsWidgets);
      await tester.pumpAndSettle();
      expect(find.text('7'), findsNothing);
      expect(find.text('81,94 €'), findsOneWidget);
    });

    testWidgets('cuando la barra crece, una banda de luz la recorre con 120 ms '
        'de retardo', (tester) async {
      await pumpMeter(tester);
      final band = find.byKey(const ValueKey('sheen-band'));
      expect(band, findsNothing);
      set(() => fraction = 0.9);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      // Aún espera sus 120 ms.
      expect(band, findsNothing);
      await tester.pump(const Duration(milliseconds: 160));
      expect(band, findsOneWidget);
      await tester.pumpAndSettle();
      expect(band, findsNothing);

      // Si mengua, no hay brillo.
      set(() => fraction = 0.3);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(band, findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('con «Reducir movimiento» no hay brillo y la cifra se funde', (
      tester,
    ) async {
      await pumpMeter(tester, reduce: true);
      set(() {
        spent = '81,94 €';
        fraction = 0.9;
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('sheen-band')), findsNothing);
      expect(moving(tester, find.byType(BudgetMeter)), isEmpty);
      await tester.pumpAndSettle();
    });
  });

  group('la fila que da luz (P)', () {
    late StateSetter set;
    var delivered = false;
    var armed = false;
    var consumed = 0;

    Future<void> pumpRow(WidgetTester tester, {bool reduce = false}) async {
      delivered = false;
      armed = false;
      consumed = 0;
      await pumpThemed(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return DeliveredSweep(
              delivered: delivered,
              consumeArm: () {
                consumed++;
                final was = armed;
                armed = false;
                return was;
              },
              color: const Color(0xFFD8D2F8),
              child: const SizedBox(width: 300, height: 60),
            );
          },
        ),
        disableAnimations: reduce,
      );
    }

    final sweep = find.byKey(const ValueKey('delivered-sweep'));
    final sweepFill = find.descendant(
      of: sweep,
      matching: find.byType(ColoredBox),
    );

    testWidgets('al entregar por una acción del usuario, el pastel barre la '
        'fila desde la izquierda y se apaga', (tester) async {
      await pumpRow(tester);
      expect(sweep, findsNothing);
      armed = true;
      set(() => delivered = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      // En el primer 30 % (390 ms) el ancho crece.
      final early = tester.getSize(sweepFill).width;
      expect(early, greaterThan(0));
      expect(early, lessThan(300));
      await tester.pump(const Duration(milliseconds: 360));
      expect(tester.getSize(sweepFill).width, closeTo(300, 1));
      // Luego la opacidad baja de 0,9 a 0.
      final colorAt = tester
          .widget<ColoredBox>(
            find.descendant(of: sweep, matching: find.byType(ColoredBox)),
          )
          .color
          .a;
      expect(colorAt, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 1000));
      expect(sweep, findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('si el cambio llegó por sincronización (sin armar) no hace '
        'nada', (tester) async {
      await pumpRow(tester);
      set(() => delivered = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(consumed, 1);
      expect(sweep, findsNothing);
    });

    testWidgets('con «Reducir movimiento» no hay barrido', (tester) async {
      await pumpRow(tester, reduce: true);
      armed = true;
      set(() => delivered = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(sweep, findsNothing);
    });
  });

  group('StaggerScope.replay (desbloqueo en cascada, Q)', () {
    Widget scope() => StaggerScope(
      child: Column(
        children: [
          for (var i = 0; i < 3; i++)
            StaggerItem(
              index: i,
              child: SizedBox(key: Key('i$i'), width: 40, height: 20),
            ),
        ],
      ),
    );

    double opacityOf(WidgetTester tester, int i) => tester
        .widget<FadeTransition>(
          find
              .ancestor(
                of: find.byKey(Key('i$i')),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;

    testWidgets(
      'vuelve a lanzar la entrada con el retardo base y acaba entera',
      (tester) async {
        await pumpThemed(tester, scope());
        await tester.pumpAndSettle();
        expect(opacityOf(tester, 0), 1);
        StaggerScope.replayVisible(delay: const Duration(milliseconds: 140));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        // Todavía en el retardo base: nada se ve aún.
        expect(opacityOf(tester, 0), 0);
        expect(opacityOf(tester, 2), 0);
        await tester.pump(const Duration(milliseconds: 220));
        expect(opacityOf(tester, 0), greaterThan(opacityOf(tester, 2)));
        expect(moving(tester, find.byType(StaggerScope)), isNotEmpty);
        await tester.pumpAndSettle();
        expect(opacityOf(tester, 2), 1);
        expect(moving(tester, find.byType(StaggerScope)), isEmpty);
      },
    );

    testWidgets('no toca una pantalla que no se ve (animaciones paradas)', (
      tester,
    ) async {
      await pumpThemed(tester, TickerMode(enabled: true, child: scope()));
      await tester.pumpAndSettle();
      await pumpThemed(tester, TickerMode(enabled: false, child: scope()));
      StaggerScope.replayVisible(delay: const Duration(milliseconds: 140));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(opacityOf(tester, 0), 1);
    });

    testWidgets('con «Reducir movimiento» no hay cascada', (tester) async {
      await pumpThemed(tester, scope(), disableAnimations: true);
      await tester.pumpAndSettle();
      StaggerScope.replayVisible(delay: const Duration(milliseconds: 140));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(opacityOf(tester, 0), 1);
    });
  });

  group('SuccessMark y PopIn con retardo (L)', () {
    testWidgets('el cuadro de radio 8 rebota desde 0,8 a los 60 ms y el visto '
        'se dibuja después', (tester) async {
      await pumpThemed(tester, const SuccessMark());
      final box = find.descendant(
        of: find.byType(SuccessMark),
        matching: find.byType(Container),
      );
      final deco = tester.widget<Container>(box.first).decoration!;
      expect((deco as BoxDecoration).borderRadius, RegalosShape.chip);
      expect(tester.getSize(box.first), const Size(64, 64));
      // Antes de los 60 ms, invisible y a 0,8.
      await tester.pump(const Duration(milliseconds: 20));
      final fade = tester.widget<Opacity>(
        find
            .descendant(
              of: find.byType(SuccessMark),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(fade.opacity, 0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(minScale(tester, find.byType(SuccessMark)), lessThan(1.0));
      await tester.pump(const Duration(milliseconds: 150));
      final check = find.byType(CustomPaint);
      expect(check, findsWidgets);
      await tester.pumpAndSettle();
      expect(moving(tester, find.byType(SuccessMark)), isEmpty);
    });

    testWidgets('en pequeño mide 32', (tester) async {
      await pumpThemed(tester, const SuccessMark(size: 32));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(
          find
              .descendant(
                of: find.byType(SuccessMark),
                matching: find.byType(Container),
              )
              .first,
        ),
        const Size(32, 32),
      );
    });

    testWidgets('con «Reducir movimiento» no hay Transform que escale', (
      tester,
    ) async {
      await pumpThemed(tester, const SuccessMark(), disableAnimations: true);
      await tester.pump(const Duration(milliseconds: 90));
      expect(moving(tester, find.byType(SuccessMark)), isEmpty);
      await tester.pumpAndSettle();
    });

    testWidgets('PopIn con retardo se queda quieto y oculto hasta su turno', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        const PopIn(
          from: 0.8,
          delay: Duration(milliseconds: 200),
          child: SizedBox(key: Key('x'), width: 20, height: 20),
        ),
      );
      Opacity fade() => tester.widget<Opacity>(
        find
            .ancestor(
              of: find.byKey(const Key('x')),
              matching: find.byType(Opacity),
            )
            .first,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(fade().opacity, 0);
      await tester.pump(const Duration(milliseconds: 150));
      expect(fade().opacity, greaterThan(0));
      await tester.pumpAndSettle();
      expect(fade().opacity, 1);
    });
  });

  group('el eje compartido y el indicador del primer uso (M)', () {
    late StateSetter set;
    var step = 0;

    Future<void> pumpSteps(WidgetTester tester, {bool reduce = false}) async {
      step = 0;
      await pumpThemed(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return SharedAxisSwitcher(
              index: step,
              child: Text('Paso $step', key: ValueKey('t$step')),
            );
          },
        ),
        disableAnimations: reduce,
      );
    }

    double dx(WidgetTester tester, String text) =>
        tester.getTopLeft(find.text(text)).dx;

    testWidgets('el que se va se desplaza 24 px hacia atrás y se funde; el '
        'que llega viene de +24', (tester) async {
      await pumpSteps(tester);
      final rest = dx(tester, 'Paso 0');
      set(() => step = 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(find.text('Paso 0'), findsOneWidget);
      expect(find.text('Paso 1'), findsOneWidget);
      // Sale hacia la izquierda; entra desde la derecha.
      expect(dx(tester, 'Paso 0'), lessThan(rest));
      expect(dx(tester, 'Paso 1'), greaterThan(rest));
      expect(dx(tester, 'Paso 1') - rest, lessThanOrEqualTo(24.5));
      expect(rest - dx(tester, 'Paso 0'), lessThanOrEqualTo(24.5));
      // El de salida se funde en 150-180 ms.
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Paso 0'), findsNothing);
      await tester.pumpAndSettle();
      expect(dx(tester, 'Paso 1'), closeTo(rest, 0.01));

      // Al volver, al revés.
      set(() => step = 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(dx(tester, 'Paso 1'), greaterThan(rest));
      expect(dx(tester, 'Paso 0'), lessThan(rest));
      await tester.pumpAndSettle();
    });

    testWidgets('con «Reducir movimiento» se cruzan sin desplazarse', (
      tester,
    ) async {
      await pumpSteps(tester, reduce: true);
      final rest = dx(tester, 'Paso 0');
      set(() => step = 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('Paso 0'), findsOneWidget);
      expect(dx(tester, 'Paso 0'), rest);
      expect(dx(tester, 'Paso 1'), rest);
      expect(moving(tester, find.byType(SharedAxisSwitcher)), isEmpty);
      await tester.pumpAndSettle();
    });

    testWidgets('los segmentos son rectos, de 4 px y radio 2, y su relleno '
        'escala desde la izquierda', (tester) async {
      var filled = 1;
      late StateSetter setFilled;
      await pumpThemed(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            setFilled = setState;
            return SizedBox(
              width: 300,
              child: StepSegments(
                count: 3,
                filled: filled,
                semanticLabel: 'Paso',
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      final scales = find.descendant(
        of: find.byType(StepSegments),
        matching: find.byType(Transform),
      );
      expect(scales, findsNWidgets(3));
      expect(tester.getSize(find.byType(ClipRRect).first).height, 4);
      expect(
        tester.widget<ClipRRect>(find.byType(ClipRRect).first).borderRadius,
        BorderRadius.circular(2),
      );
      double fill(int i) =>
          tester.widget<Transform>(scales.at(i)).transform.storage[0];
      expect(fill(0), 1);
      expect(fill(1), 0);
      setFilled(() => filled = 2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(fill(1), inExclusiveRange(0, 1.01));
      await tester.pumpAndSettle();
      expect(fill(1), 1);
      // Se vacía en 180 ms.
      setFilled(() => filled = 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(fill(1), inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 120));
      expect(fill(1), 0);
    });

    testWidgets('con «Reducir movimiento» los segmentos solo cambian de '
        'color', (tester) async {
      await pumpThemed(
        tester,
        const SizedBox(
          width: 300,
          child: StepSegments(count: 3, filled: 2, semanticLabel: 'Paso'),
        ),
        disableAnimations: true,
      );
      await tester.pumpAndSettle();
      expect(moving(tester, find.byType(StepSegments)), isEmpty);
    });
  });

  group('el visor del lector (L)', () {
    test('traduce las esquinas de la imagen a las del visor (cover)', () {
      // Imagen 400 × 800 en un visor de 200 × 200: escala 0,5 y recorte
      // vertical de 100 px por arriba y por abajo.
      final rect = ScanViewfinder.codeRect(
        corners: const [
          Offset(100, 300),
          Offset(300, 300),
          Offset(300, 500),
          Offset(100, 500),
        ],
        image: const Size(400, 800),
        view: const Size(200, 200),
      );
      expect(rect, const Rect.fromLTRB(50, 50, 150, 150));
    });

    test('desconfía de lo que cae fuera del visor o no tiene 4 esquinas', () {
      const view = Size(200, 200);
      expect(
        ScanViewfinder.codeRect(
          corners: const [Offset(0, 0), Offset(1, 1)],
          image: const Size(400, 400),
          view: view,
        ),
        isNull,
      );
      expect(
        ScanViewfinder.codeRect(
          corners: const [
            Offset(900, 900),
            Offset(1000, 900),
            Offset(1000, 1000),
            Offset(900, 1000),
          ],
          image: const Size(400, 400),
          view: view,
        ),
        isNull,
      );
      expect(
        ScanViewfinder.plausible(const Rect.fromLTWH(95, 95, 4, 4), view),
        isFalse,
      );
    });

    testWidgets('las cuatro esquinas viajan hasta el código con snap y pasan '
        'a pastel', (tester) async {
      final key = GlobalKey<ScanViewfinderState>();
      await pumpThemed(
        tester,
        SizedBox(width: 300, height: 300, child: ScanViewfinder(key: key)),
      );
      final painter = find.descendant(
        of: find.byType(ScanViewfinder),
        matching: find.byType(CustomPaint),
      );
      Color color() =>
          ((tester.widget<CustomPaint>(painter.first).painter!) as dynamic)
                  .color
              as Color;
      Rect box() =>
          ((tester.widget<CustomPaint>(painter.first).painter!) as dynamic).rect
              as Rect;
      // En reposo: un cuadro de 200 centrado, en blanco.
      expect(
        box(),
        Rect.fromCenter(
          center: const Offset(150, 150),
          width: 200,
          height: 200,
        ),
      );
      expect(color(), Colors.white);
      expect(key.currentState!.locked, isFalse);

      key.currentState!.lock(const Rect.fromLTWH(110, 110, 80, 80));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final mid = box();
      expect(mid.width, lessThan(200));
      expect(mid.width, greaterThan(90));
      await tester.pumpAndSettle();
      // El código ampliado 5 px por cada lado.
      expect(box(), const Rect.fromLTRB(105, 105, 195, 195));
      expect(color(), isNot(Colors.white));

      key.currentState!.reset();
      await tester.pump();
      expect(color(), Colors.white);
      expect(key.currentState!.locked, isFalse);
    });

    testWidgets('sin rectángulo de fiar, solo se cierran un 8 % hacia el '
        'centro', (tester) async {
      final key = GlobalKey<ScanViewfinderState>();
      await pumpThemed(
        tester,
        SizedBox(width: 300, height: 300, child: ScanViewfinder(key: key)),
      );
      key.currentState!.lock(null);
      await tester.pumpAndSettle();
      final painter = find.descendant(
        of: find.byType(ScanViewfinder),
        matching: find.byType(CustomPaint),
      );
      final rect =
          ((tester.widget<CustomPaint>(painter.first).painter!) as dynamic).rect
              as Rect;
      expect(rect.width, closeTo(200 * 0.92, 0.5));
      expect(rect.center, const Offset(150, 150));
    });

    testWidgets('con «Reducir movimiento» las esquinas no viajan', (
      tester,
    ) async {
      final key = GlobalKey<ScanViewfinderState>();
      await pumpThemed(
        tester,
        SizedBox(width: 300, height: 300, child: ScanViewfinder(key: key)),
        disableAnimations: true,
      );
      key.currentState!.lock(const Rect.fromLTWH(110, 110, 80, 80));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final painter = find.descendant(
        of: find.byType(ScanViewfinder),
        matching: find.byType(CustomPaint),
      );
      final rect =
          ((tester.widget<CustomPaint>(painter.first).painter!) as dynamic).rect
              as Rect;
      expect(rect.width, 200);
      await tester.pumpAndSettle();
    });

    test('la hoja de éxito sube al 70 % del muelle, o a los 150 ms', () {
      expect(
        ScanViewfinder.followUp(reduce: false).inMilliseconds,
        inInclusiveRange(260, 264),
      );
      expect(ScanViewfinder.followUp(reduce: true).inMilliseconds, 150);
    });
  });

  group('la guirnalda que se dibuja (K)', () {
    test('seis piezas, 40 ms entre una y otra, 600 ms cada una', () {
      expect(GarlandPieces.count, 6);
      expect(GarlandPieces.total.inMilliseconds, 5 * 40 + 600);
      // A los 300 ms la primera va por delante de la última.
      const at = Duration(milliseconds: 300);
      expect(
        GarlandPieces.progress(0, at),
        greaterThan(GarlandPieces.progress(5, at)),
      );
      expect(GarlandPieces.progress(0, Duration.zero), 0);
      expect(GarlandPieces.progress(5, GarlandPieces.total), 1);
    });

    testWidgets('empieza vacía, se dibuja a los ~205 ms y acaba entera', (
      tester,
    ) async {
      final t = RegalosTokens.of(
        // Se necesita un contexto con el tema para las pinturas.
        await _tokensContext(tester),
      );
      await pumpThemed(
        tester,
        DrawnGarland(motif: GarlandMotif.kings, tokens: t),
      );
      List<double> pieces() {
        final painter = tester
            .widget<CustomPaint>(
              find
                  .descendant(
                    of: find.byType(DrawnGarland),
                    matching: find.byType(CustomPaint),
                  )
                  .first,
            )
            .painter!;
        return (painter as dynamic).pieces() as List<double>;
      }

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(pieces().every((p) => p == 0), isTrue);
      await tester.pump(const Duration(milliseconds: 250));
      final mid = pieces();
      expect(mid.first, greaterThan(0));
      expect(mid.first, greaterThan(mid.last));
      await tester.pumpAndSettle();
      expect(pieces().every((p) => p == 1), isTrue);
    });

    testWidgets('con «Reducir movimiento» aparece entera', (tester) async {
      final t = RegalosTokens.of(await _tokensContext(tester));
      await pumpThemed(
        tester,
        DrawnGarland(motif: GarlandMotif.birthday, tokens: t),
        disableAnimations: true,
      );
      final painter = tester
          .widget<CustomPaint>(
            find
                .descendant(
                  of: find.byType(DrawnGarland),
                  matching: find.byType(CustomPaint),
                )
                .first,
          )
          .painter!;
      expect(
        ((painter as dynamic).pieces() as List<double>).every((p) => p == 1),
        isTrue,
      );
    });
  });

  testWidgets('Sheen sigue sin pintar nada en reposo', (tester) async {
    await pumpThemed(
      tester,
      const Sheen(child: SizedBox(width: 50, height: 10)),
    );
    expect(find.byKey(const ValueKey('sheen-band')), findsNothing);
  });
}

/// Un contexto con el tema «Tareas», para leer los tokens.
Future<BuildContext> _tokensContext(WidgetTester tester) async {
  await pumpThemed(tester, const SizedBox(key: Key('ctx')));
  return tester.element(find.byKey(const Key('ctx')));
}
