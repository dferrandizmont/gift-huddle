import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/motion/pop_in.dart';
import 'package:regalos/core/motion/stagger.dart';
import 'package:regalos/core/motion/state_switcher.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/core/widgets/empty_state.dart';
import 'package:regalos/core/widgets/regalos_switch.dart';
import 'package:regalos/core/widgets/stroke_icon.dart';

import '../helpers/pump_app.dart';

bool isIdentity(Matrix4 m) =>
    m.storage[0] == 1 && m.storage[5] == 1 && m.getTranslation().length == 0;

/// Los `Transform` de [of] que se mueven o escalan.
List<Transform> moving(WidgetTester tester, Finder of) => [
  for (final t in tester.widgetList<Transform>(
    find.descendant(of: of, matching: find.byType(Transform)),
  ))
    if (!isIdentity(t.transform)) t,
];

void main() {
  group('RegalosSwitch', () {
    final on = ValueNotifier<bool>(false);

    Future<void> pump(WidgetTester tester, {bool reduce = false}) async {
      on.value = false;
      await pumpThemed(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: on,
          builder: (_, value, _) =>
              RegalosSwitch(value: value, onChanged: (_) {}),
        ),
        disableAnimations: reduce,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('con movimiento tarda 375 ms (muelle), no 150', (tester) async {
      await pump(tester);
      on.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      // A los 160 ms el muelle sigue en marcha (con 150 ms ya habría acabado).
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('con «Reducir movimiento» se funde en 150 ms: ni corte ni '
        'muelle', (tester) async {
      await pump(tester, reduce: true);
      on.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      // A mitad de camino: sigue animando, no saltó de golpe.
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('StaggerItem', () {
    Widget scope({required int items}) => StaggerScope(
      child: Column(
        children: [
          for (var i = 0; i < items; i++)
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

    testWidgets('entran de arriba abajo, cada uno 24 ms después', (
      tester,
    ) async {
      await pumpThemed(tester, scope(items: 3));
      // Aún no ha arrancado: todos invisibles.
      expect(opacityOf(tester, 0), 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(opacityOf(tester, 0), greaterThan(opacityOf(tester, 1)));
      expect(opacityOf(tester, 1), greaterThan(opacityOf(tester, 2)));
      expect(moving(tester, find.byType(StaggerScope)), isNotEmpty);
      await tester.pumpAndSettle();
      expect(opacityOf(tester, 2), 1);
      expect(moving(tester, find.byType(StaggerScope)), isEmpty);
    });

    testWidgets('una entrada se ve una vez: lo que llega después sale entero', (
      tester,
    ) async {
      await pumpThemed(tester, scope(items: 1));
      await tester.pumpAndSettle();
      // Llegan datos nuevos: la fila nueva no se anima.
      await pumpThemed(tester, scope(items: 2));
      expect(find.byKey(const Key('i1')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(StaggerScope),
          matching: find.ancestor(
            of: find.byKey(const Key('i1')),
            matching: find.byType(FadeTransition),
          ),
        ),
        findsNothing,
      );
    });

    testWidgets('con «Reducir movimiento» solo se funde, sin retardo ni '
        'traslación', (tester) async {
      await pumpThemed(tester, scope(items: 3), disableAnimations: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      // Los tres a la vez (sin escalonado) y ninguno desplazado.
      final o = opacityOf(tester, 0);
      expect(o, inExclusiveRange(0, 1));
      expect(opacityOf(tester, 2), o);
      expect(moving(tester, find.byType(StaggerScope)), isEmpty);
      await tester.pump(const Duration(milliseconds: 150));
      expect(opacityOf(tester, 0), 1);
      await tester.pumpAndSettle();
    });
  });

  group('PopIn y estado vacío', () {
    testWidgets('PopIn parte de su escala ya en el primer fotograma', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        const PopIn(child: SizedBox(key: Key('x'), width: 40, height: 40)),
      );
      expect(
        moving(tester, find.byType(PopIn)).single.transform.storage[0],
        closeTo(0.9, 0.001),
      );
      await tester.pumpAndSettle();
      expect(moving(tester, find.byType(PopIn)), isEmpty);
    });

    testWidgets('PopIn con «Reducir movimiento» solo funde', (tester) async {
      await pumpThemed(
        tester,
        const PopIn(child: SizedBox(width: 40, height: 40)),
        disableAnimations: true,
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(moving(tester, find.byType(PopIn)), isEmpty);
      await tester.pumpAndSettle();
    });

    testWidgets('el icono del estado vacío es un cuadro de radio 8, no un '
        'círculo', (tester) async {
      await pumpThemed(
        tester,
        const EmptyState(
          icon: AppIcons.people,
          title: 'Nada aún',
          message: 'Aquí aparecerán.',
        ),
      );
      await tester.pumpAndSettle();
      final boxes = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(EmptyState),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((b) => b.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.color != null);
      expect(boxes, isNotEmpty);
      for (final d in boxes) {
        expect(d.shape, BoxShape.rectangle);
        expect(d.borderRadius, BorderRadius.circular(8));
      }
    });
  });

  group('StateSwitcher', () {
    Widget host(String key) => StateSwitcher(stateKey: key, child: Text(key));

    testWidgets('cruza dos contenidos con un fundido de 200 ms', (
      tester,
    ) async {
      await pumpThemed(tester, host('lista'));
      await pumpThemed(tester, host('vacío'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('lista'), findsOneWidget);
      expect(find.text('vacío'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('lista'), findsNothing);
      expect(find.text('vacío'), findsOneWidget);
    });

    testWidgets('con reducir, 150 ms', (tester) async {
      await pumpThemed(tester, host('lista'), disableAnimations: true);
      await pumpThemed(tester, host('vacío'), disableAnimations: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.text('lista'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('lista'), findsNothing);
    });
  });

  group('transición de pantallas de Android', () {
    Future<void> openSecond(WidgetTester tester, {required bool reduce}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(
            AccentId.lavender.palette,
            Brightness.light,
          ).copyWith(platform: TargetPlatform.android),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const Scaffold(body: Center(child: Text('Segunda'))),
                    ),
                  ),
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('la nueva entra desde el 25 % del ancho con muelle y la de '
        'debajo no retrocede', (tester) async {
      await openSecond(tester, reduce: false);
      final belowRest = tester.getCenter(find.text('Abrir')).dx;
      final belowSize = tester.getSize(find.text('Abrir'));
      await tester.tap(find.text('Abrir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final center = width / 2;
      // La nueva aún está a la derecha de su sitio, y no más allá del 25 %.
      final entering = tester.getCenter(find.text('Segunda')).dx;
      expect(entering, greaterThan(center));
      expect(entering, lessThanOrEqualTo(center + 0.25 * width));
      // La de debajo no retrocede: ni se mueve ni se encoge, solo se oscurece.
      expect(tester.getCenter(find.text('Abrir')).dx, belowRest);
      expect(tester.getSize(find.text('Abrir')), belowSize);

      await tester.pumpAndSettle();
      expect(tester.getCenter(find.text('Segunda')).dx, closeTo(center, 1));
    });

    testWidgets('volver dura 220 ms, sin muelle', (tester) async {
      await openSecond(tester, reduce: false);
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pump(const Duration(milliseconds: 160));
      expect(find.text('Segunda'), findsNothing);
    });

    testWidgets('con «Reducir movimiento» solo hay un fundido: nada se '
        'traslada', (tester) async {
      await openSecond(tester, reduce: true);
      await tester.tap(find.text('Abrir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      // Ya en su sitio, sin trasladarse, y la de debajo tampoco se mueve.
      expect(
        tester.getCenter(find.text('Segunda')).dx,
        closeTo(width / 2, 0.5),
      );
      expect(tester.getCenter(find.text('Abrir')).dx, closeTo(width / 2, 0.5));
      // Y se está fundiendo.
      expect(
        tester
            .widgetList<FadeTransition>(
              find.ancestor(
                of: find.text('Segunda'),
                matching: find.byType(FadeTransition),
              ),
            )
            .any((f) => f.opacity.value < 1),
        isTrue,
      );
      await tester.pumpAndSettle();
    });
  });
}
