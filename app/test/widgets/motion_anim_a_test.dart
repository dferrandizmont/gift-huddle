import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/motion/animated_rows.dart';
import 'package:regalos/core/motion/highlight_flash.dart';
import 'package:regalos/core/motion/move_slide.dart';
import 'package:regalos/core/motion/unfold_section.dart';

import '../helpers/pump_app.dart';

/// Una columna de filas de 50 de alto que se puede reordenar. [slotShift] se
/// suma al puesto de todas (cambia el puesto sin mover nada) y [onTap] recibe
/// el id de la fila tocada.
class _Rows extends StatelessWidget {
  const _Rows({required this.order, this.slotShift, this.onTap});

  final ValueNotifier<List<String>> order;
  final ValueNotifier<int>? slotShift;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([order, ?slotShift]),
    builder: (context, _) => Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        child: Column(
          children: [
            for (var i = 0; i < order.value.length; i++)
              MoveSlide(
                key: ValueKey(order.value[i]),
                slot: i + (slotShift?.value ?? 0),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap?.call(order.value[i]),
                  child: SizedBox(
                    height: 50,
                    width: 200,
                    child: Text(order.value[i]),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Las mismas filas dentro de `AnimatedRows`.
class _AnimatedColumn extends StatelessWidget {
  const _AnimatedColumn({required this.order});

  final ValueNotifier<List<String>> order;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<String>>(
    valueListenable: order,
    builder: (context, ids, _) => Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        child: SizedBox(
          width: 200,
          child: AnimatedRows(
            rows: [
              for (var i = 0; i < ids.length; i++)
                AnimatedRowItem(
                  id: ids[i],
                  child: MoveSlide(
                    slot: i,
                    child: SizedBox(height: 50, child: Text(ids[i])),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('MoveSlide', () {
    Future<ValueNotifier<List<String>>> open(
      WidgetTester tester, {
      bool? reduce,
      ValueNotifier<int>? slotShift,
      ValueChanged<String>? onTap,
    }) async {
      final order = ValueNotifier<List<String>>(['a', 'b', 'c']);
      addTearDown(order.dispose);
      await pumpThemed(
        tester,
        _Rows(order: order, slotShift: slotShift, onTap: onTap),
        disableAnimations: reduce,
        surfaceSize: const Size(300, 600),
      );
      return order;
    }

    double top(WidgetTester tester, String id) =>
        tester.getTopLeft(find.text(id)).dy;

    testWidgets(
      'al reordenar, la fila sale de donde estaba y llega a su sitio',
      (tester) async {
        final order = await open(tester);
        final settledA = top(tester, 'a');
        final settledC = top(tester, 'c');
        expect(settledC - settledA, closeTo(100, 0.1));

        order.value = ['c', 'a', 'b'];
        await tester.pump();
        // Ya en el primer fotograma, «c» se pinta donde estaba (dos puestos más
        // abajo) y no en su sitio nuevo.
        expect(top(tester, 'c'), closeTo(settledC, 1));
        expect(top(tester, 'a'), closeTo(settledA, 1));

        // El muelle arranca en el fotograma siguiente.
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 100));
        final mid = top(tester, 'c');
        expect(mid, lessThan(settledC));
        expect(mid, greaterThan(settledA));

        await tester.pumpAndSettle();
        expect(top(tester, 'c'), closeTo(settledA, 0.1));
        expect(top(tester, 'a'), closeTo(settledA + 50, 0.1));
        expect(top(tester, 'b'), closeTo(settledA + 100, 0.1));
        expect(tester.hasRunningAnimations, isFalse);
      },
    );

    testWidgets('si el puesto cambia pero la fila no se mueve, no viaja', (
      tester,
    ) async {
      final shift = ValueNotifier<int>(0);
      addTearDown(shift.dispose);
      await open(tester, slotShift: shift);
      final before = {
        for (final id in ['a', 'b', 'c']) id: top(tester, id),
      };
      // Todos los puestos cambian (+3) pero ninguna fila cambia de sitio.
      shift.value = 3;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      for (final id in ['a', 'b', 'c']) {
        expect(top(tester, id), closeTo(before[id]!, 0.1));
      }
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('con Reducir movimiento cambia de sitio sin viajar', (
      tester,
    ) async {
      final order = await open(tester, reduce: true);
      final settledA = top(tester, 'a');
      order.value = ['c', 'a', 'b'];
      await tester.pump();
      expect(top(tester, 'c'), closeTo(settledA, 0.1));
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpAndSettle();
    });

    testWidgets('la fila que viaja recibe los toques donde se ve', (
      tester,
    ) async {
      final taps = <String>[];
      final order = await open(tester, onTap: taps.add);
      final oldC = tester.getCenter(find.text('c'));
      order.value = ['c', 'a', 'b'];
      await tester.pump();
      // En el primer fotograma «c» se ve donde estaba (abajo del todo) aunque
      // la columna ya la maquetó arriba: el toque es de ella, y no de «b»,
      // que está maquetada ahí pero se ve más arriba.
      await tester.tapAt(Offset(oldC.dx + 20, oldC.dy));
      expect(taps, ['c']);
      await tester.pumpAndSettle();
    });

    testWidgets('invertir a mitad de viaje sigue sin saltar', (tester) async {
      final order = await open(tester);
      order.value = ['c', 'a', 'b'];
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 60));
      final mid = top(tester, 'c');
      // Se vuelve atrás con la fila a medio camino: parte de donde se ve.
      order.value = ['a', 'b', 'c'];
      await tester.pump();
      expect(top(tester, 'c'), closeTo(mid, 6));
      await tester.pumpAndSettle();
      expect(top(tester, 'c') - top(tester, 'a'), closeTo(100, 0.1));
    });
  });

  group('MoveSlide dentro de AnimatedRows', () {
    testWidgets(
      'una fila que entró no recorta al reordenarse: sale entera, sin cortes',
      (tester) async {
        final order = ValueNotifier<List<String>>(['a', 'b']);
        addTearDown(order.dispose);
        await pumpThemed(
          tester,
          _AnimatedColumn(order: order),
          surfaceSize: const Size(300, 600),
        );
        order.value = ['a', 'b', 'c'];
        await tester.pumpAndSettle();

        Iterable<Clip> clipsOf(String id) => tester
            .widgetList<ClipRect>(
              find.ancestor(of: find.text(id), matching: find.byType(ClipRect)),
            )
            .map((c) => c.clipBehavior);

        // La fila nueva ya no es «una fila que entra»: su recorte es neutro.
        expect(clipsOf('c'), everyElement(Clip.none));

        final settledA = tester.getTopLeft(find.text('a')).dy;
        order.value = ['c', 'a', 'b'];
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 40));
        // Viaja y se ve entera (no hay recorte).
        expect(tester.getTopLeft(find.text('c')).dy, greaterThan(settledA));
        expect(clipsOf('c'), everyElement(Clip.none));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.text('c')).dy, closeTo(settledA, 0.1));
        expect(tester.hasRunningAnimations, isFalse);
      },
    );
  });

  group('AnimatedRows', () {
    testWidgets(
      'las filas que salen no reciben toques ni aparecen para accesibilidad '
      'mientras se pliegan',
      (tester) async {
        final order = ValueNotifier<List<String>>(['a', 'b', 'c']);
        addTearDown(order.dispose);
        final taps = <String>[];
        await pumpThemed(
          tester,
          ValueListenableBuilder<List<String>>(
            valueListenable: order,
            builder: (context, ids, _) => Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 200,
                child: AnimatedRows(
                  rows: [
                    for (final id in ids)
                      AnimatedRowItem(
                        id: id,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => taps.add(id),
                          child: SizedBox(
                            height: 50,
                            child: Semantics(
                              label: 'fila $id',
                              child: Text(id),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          surfaceSize: const Size(300, 600),
        );
        order.value = ['a', 'c'];
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        // «b» sigue pintándose, plegándose, pero ya no recibe nada.
        expect(find.text('b'), findsOneWidget);
        final excluded = tester.widget<ExcludeSemantics>(
          find
              .ancestor(
                of: find.text('b'),
                matching: find.byType(ExcludeSemantics),
              )
              .first,
        );
        expect(excluded.excluding, isTrue);
        final stays = tester.widget<ExcludeSemantics>(
          find
              .ancestor(
                of: find.text('c'),
                matching: find.byType(ExcludeSemantics),
              )
              .first,
        );
        expect(stays.excluding, isFalse);
        await tester.tap(find.text('b'), warnIfMissed: false);
        expect(taps, isEmpty);
        await tester.pumpAndSettle();
        expect(find.text('b'), findsNothing);
      },
    );

    testWidgets(
      'una fila que sale con exitChildren enseña su último cambio y luego se '
      'pliega',
      (tester) async {
        final done = ValueNotifier<bool>(false);
        addTearDown(done.dispose);
        await pumpThemed(
          tester,
          ValueListenableBuilder<bool>(
            valueListenable: done,
            builder: (context, gone, _) => Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 200,
                child: AnimatedRows(
                  exitChildren: const {
                    'b': SizedBox(height: 50, child: Text('b hecho')),
                  },
                  rows: [
                    const AnimatedRowItem(
                      id: 'a',
                      child: SizedBox(height: 50, child: Text('a')),
                    ),
                    if (!gone)
                      const AnimatedRowItem(
                        id: 'b',
                        child: SizedBox(height: 50, child: Text('b')),
                      ),
                  ],
                ),
              ),
            ),
          ),
          surfaceSize: const Size(300, 600),
        );
        double heightOfRow() => tester
            .getSize(
              find
                  .ancestor(
                    of: find.text('b hecho'),
                    matching: find.byType(ClipRect),
                  )
                  .first,
            )
            .height;
        done.value = true;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        // Recibió el hijo nuevo y espera entera.
        expect(find.text('b'), findsNothing);
        expect(heightOfRow(), closeTo(50, 0.5));
        await tester.pump(const Duration(milliseconds: 330));
        expect(heightOfRow(), lessThan(50));
        await tester.pumpAndSettle();
        expect(find.text('b hecho'), findsNothing);
        expect(tester.hasRunningAnimations, isFalse);
      },
    );
  });

  group('UnfoldSection', () {
    Future<ValueNotifier<bool>> open(
      WidgetTester tester, {
      bool shown = false,
      bool? reduce,
    }) async {
      final show = ValueNotifier<bool>(shown);
      addTearDown(show.dispose);
      await pumpThemed(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (context, v, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                UnfoldSection(
                  show: v,
                  child: const SizedBox(
                    height: 80,
                    width: 200,
                    child: Text('campo'),
                  ),
                ),
                const SizedBox(height: 10, width: 200, key: ValueKey('pie')),
              ],
            ),
          ),
        ),
        disableAnimations: reduce,
        surfaceSize: const Size(300, 600),
      );
      return show;
    }

    double footTop(WidgetTester tester) =>
        tester.getTopLeft(find.byKey(const ValueKey('pie'))).dy;

    testWidgets('el primer fotograma ya está en su estado, sin animar', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('campo'), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets(
      'al aparecer crece con muelle, y al irse se pliega y se quita',
      (tester) async {
        final show = await open(tester);
        final closed = footTop(tester);

        show.value = true;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        final growing = footTop(tester);
        expect(growing, greaterThan(closed));
        expect(growing, lessThan(closed + 80));

        await tester.pumpAndSettle();
        expect(footTop(tester), closeTo(closed + 80, 0.5));
        expect(find.text('campo'), findsOneWidget);

        show.value = false;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expect(footTop(tester), lessThan(closed + 80));
        await tester.pumpAndSettle();
        expect(footTop(tester), closeTo(closed, 0.5));
        expect(find.text('campo'), findsNothing);
        expect(tester.hasRunningAnimations, isFalse);
      },
    );

    testWidgets('invertir a medias parte de lo que se ve, sin saltar', (
      tester,
    ) async {
      final show = await open(tester);
      final closed = footTop(tester);
      show.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 50));
      final mid = footTop(tester);
      expect(mid, greaterThan(closed + 2));
      expect(mid, lessThan(closed + 80));

      // Se pide ocultarlo con la altura a medias: el siguiente fotograma
      // arranca desde esa altura (con la velocidad que llevaba, que a lo
      // sumo la mueve unos píxeles), no desde el principio ni desde el final.
      show.value = false;
      await tester.pump();
      expect(footTop(tester), closeTo(mid, 6));
      await tester.pump(const Duration(milliseconds: 30));
      final folding = footTop(tester);
      expect(folding, lessThan(mid + 6));

      // Y otra vez a mostrar a medio plegar.
      show.value = true;
      await tester.pump();
      expect(footTop(tester), closeTo(folding, 6));
      await tester.pumpAndSettle();
      expect(footTop(tester), closeTo(closed + 80, 0.5));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('en reposo no recorta (por si lleva sombras o el foco)', (
      tester,
    ) async {
      final show = await open(tester);
      show.value = true;
      await tester.pumpAndSettle();
      final clip = tester.widget<ClipRect>(
        find
            .ancestor(of: find.text('campo'), matching: find.byType(ClipRect))
            .first,
      );
      expect(clip.clipBehavior, Clip.none);
    });

    testWidgets('con Reducir movimiento la altura salta y solo se funde', (
      tester,
    ) async {
      final show = await open(tester, reduce: true);
      final closed = footTop(tester);
      show.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(footTop(tester), closeTo(closed + 80, 0.5));
      final opacity = tester.widget<Opacity>(
        find.ancestor(of: find.text('campo'), matching: find.byType(Opacity)),
      );
      expect(opacity.opacity, lessThan(1));
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('HighlightFlash', () {
    Future<double> flashAndScroll(
      WidgetTester tester, {
      required bool reveal,
    }) async {
      final signal = HighlightSignal();
      addTearDown(signal.dispose);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await pumpThemed(
        tester,
        ListView(
          controller: controller,
          // ignore: deprecated_member_use
          cacheExtent: 5000,
          children: [
            for (var i = 0; i < 40; i++)
              SizedBox(
                height: 60,
                child: i == 30
                    ? HighlightFlash(
                        id: 'x',
                        signal: signal,
                        color: Colors.amber,
                        reveal: reveal,
                        child: const Text('fila 30'),
                      )
                    : Text('fila $i'),
              ),
          ],
        ),
        surfaceSize: const Size(300, 400),
      );
      signal.highlight('x');
      await tester.pumpAndSettle();
      return controller.offset;
    }

    testWidgets('con reveal lleva la lista hasta la fila fuera de la vista', (
      tester,
    ) async {
      expect(await flashAndScroll(tester, reveal: true), greaterThan(0));
    });

    testWidgets('con reveal en false ilumina sin mover la lista', (
      tester,
    ) async {
      expect(await flashAndScroll(tester, reveal: false), 0);
    });
  });
}
