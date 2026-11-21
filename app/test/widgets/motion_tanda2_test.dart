import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/motion/animated_rows.dart';
import 'package:regalos/core/motion/card_sheet_route.dart';
import 'package:regalos/core/motion/fading_branch_container.dart';
import 'package:regalos/core/motion/page_physics.dart';
import 'package:regalos/core/motion/rolling_number.dart';
import 'package:regalos/core/motion/sheen.dart';
import 'package:regalos/core/widgets/confirm_dialog.dart';
import 'package:regalos/core/widgets/filter_pill.dart';
import 'package:regalos/core/widgets/person_avatar.dart';
import 'package:regalos/core/widgets/regalos_snack_bar.dart';

import '../helpers/pump_app.dart';

/// El mayor desvío de escala (respecto a 1) de los `Transform` que envuelven a
/// [finder].
double scaleDeviation(WidgetTester tester, Finder finder) {
  var worst = 0.0;
  for (final t in tester.widgetList<Transform>(
    find.ancestor(of: finder, matching: find.byType(Transform)),
  )) {
    final s = t.transform.storage[0];
    if ((s - 1).abs() > worst) {
      worst = (s - 1).abs();
    }
  }
  return worst;
}

void main() {
  group('diálogo de confirmación', () {
    Future<List<bool>> open(WidgetTester tester, {bool? reduce}) async {
      final results = <bool>[];
      await pumpThemed(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => results.add(
              await showRegalosConfirm(
                context,
                title: '¿Borrar «Patinete»?',
                body: 'Se elimina también en los móviles de tu familia.',
                confirmLabel: 'Borrar',
                cancelLabel: 'Cancelar',
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
        disableAnimations: reduce,
      );
      return results;
    }

    testWidgets('entra con escala de 1,08 a 1 y devuelve lo que se pulsa', (
      tester,
    ) async {
      final results = await open(tester);
      await tester.tap(find.text('abrir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final title = find.text('¿Borrar «Patinete»?');
      expect(title, findsOneWidget);
      // Todavía llegando: la escala pasa de 1 y no hay nada encogido.
      expect(scaleDeviation(tester, title), greaterThan(0.005));

      await tester.pumpAndSettle();
      expect(scaleDeviation(tester, title), lessThan(0.001));

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(results, [false]);
      expect(title, findsNothing);

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Borrar'));
      await tester.pumpAndSettle();
      expect(results, [false, true]);
    });

    testWidgets('toca fuera y se cierra sin borrar', (tester) async {
      final results = await open(tester);
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(results, [false]);
    });

    testWidgets('con «Reducir movimiento» solo se funde, en 150 ms', (
      tester,
    ) async {
      await open(tester, reduce: true);
      await tester.tap(find.text('abrir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final title = find.text('¿Borrar «Patinete»?');
      // Ni escala ni traslación: solo opacidad.
      expect(scaleDeviation(tester, title), 0);
      final fade = tester.widget<FadeTransition>(
        find.ancestor(of: title, matching: find.byType(FadeTransition)).first,
      );
      expect(fade.opacity.value, inInclusiveRange(0.2, 0.7));
      await tester.pump(const Duration(milliseconds: 100));
      expect(fade.opacity.value, 1);
    });
  });

  group('AnimatedRows', () {
    // Una lista de filas de 50 de alto que se cambia desde fuera.
    Future<ValueNotifier<(List<String>, Set<String>, bool)>> mount(
      WidgetTester tester, {
      required List<String> ids,
      bool? reduce,
      List<String>? gone,
    }) async {
      final state = ValueNotifier<(List<String>, Set<String>, bool)>((
        ids,
        const <String>{},
        false,
      ));
      addTearDown(state.dispose);
      await pumpThemed(
        tester,
        ValueListenableBuilder<(List<String>, Set<String>, bool)>(
          valueListenable: state,
          builder: (context, value, _) => SingleChildScrollView(
            child: AnimatedRows(
              deleted: value.$2,
              quiet: value.$3,
              onDeletedGone: gone?.add,
              rows: [
                for (final id in value.$1)
                  AnimatedRowItem(
                    id: id,
                    child: SizedBox(height: 50, child: Text(id)),
                  ),
              ],
            ),
          ),
        ),
        disableAnimations: reduce,
      );
      return state;
    }

    double heightOf(WidgetTester tester, String id) => tester
        .getSize(
          find
              .ancestor(of: find.text(id), matching: find.byType(ClipRect))
              .first,
        )
        .height;

    testWidgets('la fila que se va se pliega y luego se quita', (tester) async {
      final state = await mount(tester, ids: ['a', 'b', 'c']);
      expect(find.text('b'), findsOneWidget);
      state.value = (['a', 'c'], const <String>{}, false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      // A mitad del pliegue: sigue ahí, pero más baja.
      expect(find.text('b'), findsOneWidget);
      expect(heightOf(tester, 'b'), lessThan(50));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('b'), findsNothing);
      expect(find.text('c'), findsOneWidget);
    });

    testWidgets('la fila que llega se despliega con snap', (tester) async {
      final state = await mount(tester, ids: ['a']);
      state.value = (['a', 'n'], const <String>{}, false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('n'), findsOneWidget);
      expect(heightOf(tester, 'n'), lessThan(50));
      await tester.pumpAndSettle();
      expect(heightOf(tester, 'n'), 50);
    });

    testWidgets('si llega por sincronización solo se funde, sin desplegarse', (
      tester,
    ) async {
      final state = await mount(tester, ids: ['a']);
      state.value = (['a', 'n'], const <String>{}, true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final opacity = tester.widget<Opacity>(
        find.ancestor(of: find.text('n'), matching: find.byType(Opacity)).first,
      );
      expect(opacity.opacity, lessThan(1));
      // Ocupa su altura entera desde el primer fotograma.
      expect(
        tester
            .getSize(
              find
                  .ancestor(of: find.text('n'), matching: find.byType(SizedBox))
                  .first,
            )
            .height,
        50,
      );
    });

    testWidgets(
      'un borrado se tiñe de rojo claro y se desliza antes de plegar',
      (tester) async {
        final gone = <String>[];
        final state = await mount(tester, ids: ['a', 'b', 'c'], gone: gone);
        state.value = (['a', 'c'], const {'b'}, false);
        await tester.pump();
        // En los primeros 90 ms se tiñe; la altura aún no baja.
        await tester.pump(const Duration(milliseconds: 80));
        final tinted = find.ancestor(
          of: find.text('b'),
          matching: find.byWidgetPredicate(
            (w) => w is ColoredBox && w.color.a > 0.5 && w.color.r > 0.9,
          ),
        );
        expect(tinted, findsOneWidget);
        expect(heightOf(tester, 'b'), 50);
        // Luego se pliega y se desliza a la izquierda.
        await tester.pump(const Duration(milliseconds: 100));
        expect(heightOf(tester, 'b'), lessThan(50));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('b'), findsNothing);
        expect(gone, ['b']);
      },
    );

    testWidgets('con «Reducir movimiento» se funde sin cambiar de altura', (
      tester,
    ) async {
      final state = await mount(tester, ids: ['a', 'b', 'c'], reduce: true);
      state.value = (['a', 'c'], const {'b'}, false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expect(find.text('b'), findsOneWidget);
      expect(tester.getSize(find.text('b')).height, greaterThan(0));
      // Sin plegado: la fila conserva su altura y solo se apaga.
      expect(
        tester
            .getSize(
              find
                  .ancestor(of: find.text('b'), matching: find.byType(SizedBox))
                  .first,
            )
            .height,
        50,
      );
      final opacity = tester.widget<Opacity>(
        find.ancestor(of: find.text('b'), matching: find.byType(Opacity)).first,
      );
      expect(opacity.opacity, lessThan(1));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('b'), findsNothing);
    });

    testWidgets('si vuelve mientras se pliega (Deshacer), se queda', (
      tester,
    ) async {
      final state = await mount(tester, ids: ['a', 'b']);
      state.value = (['a'], const {'b'}, false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      state.value = (['a', 'b'], const <String>{}, false);
      await tester.pumpAndSettle();
      expect(find.text('b'), findsOneWidget);
      expect(heightOf(tester, 'b'), 50);
    });
  });

  group('RollingNumber', () {
    Widget number(int value, {bool fromEmpty = false}) => RollingNumber(
      value: value,
      rollFromEmpty: fromEmpty,
      style: const TextStyle(fontSize: 20),
    );

    testWidgets('de 43 a 44 solo rueda la última cifra', (tester) async {
      final value = ValueNotifier<int>(43);
      addTearDown(value.dispose);
      await pumpThemed(
        tester,
        ValueListenableBuilder<int>(
          valueListenable: value,
          builder: (_, v, _) => number(v),
        ),
      );
      expect(find.text('43'), findsOneWidget);
      value.value = 44;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // La cifra de las decenas no se mueve; en la de las unidades conviven
      // la que se va y la que llega.
      expect(find.text('4'), findsAtLeastNWidgets(2));
      expect(find.text('3'), findsOneWidget);
      expect(find.byType(FractionalTranslation), findsWidgets);
      await tester.pumpAndSettle();
      expect(find.text('44'), findsOneWidget);
    });

    testWidgets('la primera vez puede rodar desde vacío', (tester) async {
      await pumpThemed(tester, number(56, fromEmpty: true));
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byType(FractionalTranslation), findsWidgets);
      await tester.pumpAndSettle();
      expect(find.text('56'), findsOneWidget);
    });

    testWidgets('con «Reducir movimiento» las cifras se cruzan sin moverse', (
      tester,
    ) async {
      final value = ValueNotifier<int>(43);
      addTearDown(value.dispose);
      await pumpThemed(
        tester,
        ValueListenableBuilder<int>(
          valueListenable: value,
          builder: (_, v, _) => number(v),
        ),
        disableAnimations: true,
      );
      value.value = 44;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byType(FractionalTranslation), findsNothing);
      expect(find.byType(ShaderMask), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('44'), findsOneWidget);
    });

    testWidgets('RollingCount rueda solo el número dentro del texto', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        const RollingCount(
          text: '7 regalos',
          value: 7,
          style: TextStyle(fontSize: 14),
        ),
      );
      expect(find.text('7'), findsOneWidget);
      expect(find.text(' regalos'), findsOneWidget);
      expect(find.bySemanticsLabel('7 regalos'), findsOneWidget);
    });
  });

  group('Sheen', () {
    final band = find.byKey(const ValueKey('sheen-band'));

    testWidgets('una banda de luz cruza una vez', (tester) async {
      final key = GlobalKey<SheenState>();
      await pumpThemed(
        tester,
        Sheen(key: key, child: const SizedBox(width: 200, height: 60)),
      );
      expect(band, findsNothing);
      key.currentState!.play(delay: const Duration(milliseconds: 140));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Aún en el retardo de 140 ms.
      expect(band, findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
      expect(band, findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(band, findsNothing);
    });

    testWidgets('con «Reducir movimiento» no hay brillo', (tester) async {
      final key = GlobalKey<SheenState>();
      await pumpThemed(
        tester,
        Sheen(key: key, child: const SizedBox(width: 200, height: 60)),
        disableAnimations: true,
      );
      key.currentState!.play();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(band, findsNothing);
    });
  });

  group('pestañas', () {
    testWidgets('el contenido que llega se funde y no pierde su estado', (
      tester,
    ) async {
      final index = ValueNotifier<int>(0);
      addTearDown(index.dispose);
      await pumpThemed(
        tester,
        ValueListenableBuilder<int>(
          valueListenable: index,
          builder: (_, i, _) => FadingBranchContainer(
            currentIndex: i,
            children: const [
              _Counter(label: 'A'),
              _Counter(label: 'B'),
            ],
          ),
        ),
      );
      await tester.tap(find.text('A: 0'));
      await tester.pump();
      expect(find.text('A: 1'), findsOneWidget);

      index.value = 1;
      await tester.pump();
      // Recién llegada, la pestaña B está transparente y se funde en 100 ms.
      FadeTransition fadeOf(String text) => tester.widget<FadeTransition>(
        find
            .ancestor(
              of: find.text(text),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fadeOf('B: 0').opacity.value, lessThan(0.1));
      await tester.pump(const Duration(milliseconds: 75));
      expect(fadeOf('B: 0').opacity.value, inExclusiveRange(0.1, 0.9));
      await tester.pump(const Duration(milliseconds: 100));
      expect(fadeOf('B: 0').opacity.value, 1);

      // Al volver a A conserva su cuenta.
      index.value = 0;
      await tester.pumpAndSettle();
      expect(find.text('A: 1'), findsOneWidget);
    });
  });

  group('tarjeta del editor', () {
    Future<void> open(WidgetTester tester, {bool? reduce}) async {
      await pumpThemed(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showCardSheet<void>(
              context,
              builder: (_) => Scaffold(
                body: Column(
                  children: [
                    const CardSheetHandle(
                      child: SizedBox(
                        height: 80,
                        width: double.infinity,
                        child: Text('Cabecera'),
                      ),
                    ),
                    const Expanded(child: Text('Contenido')),
                  ],
                ),
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
        disableAnimations: reduce,
      );
    }

    testWidgets('sube desde abajo, deja 12 px arriba y no encoge la app', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('abrir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final early = tester.getTopLeft(find.text('Cabecera')).dy;
      await tester.pumpAndSettle();
      final end = tester.getTopLeft(find.text('Cabecera')).dy;
      expect(early, greaterThan(end + 100));
      // La tarjeta termina cerca de arriba (12 px de aire, más la barra de
      // estado).
      expect(end, lessThan(60));
      // Nada retrocede: la pantalla de debajo no lleva escala.
      expect(scaleDeviation(tester, find.text('abrir')), lessThan(0.001));
    });

    testWidgets('arrastrar la cabecera hacia abajo la cierra', (tester) async {
      await open(tester);
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.fling(find.text('Cabecera'), const Offset(0, 500), 1500);
      await tester.pumpAndSettle();
      expect(find.text('Contenido'), findsNothing);
    });

    testWidgets('un arrastre corto vuelve a su sitio', (tester) async {
      await open(tester);
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      final rest = tester.getTopLeft(find.text('Cabecera')).dy;
      final drag = await tester.startGesture(
        tester.getCenter(find.text('Cabecera')),
      );
      await drag.moveBy(const Offset(0, 60));
      await tester.pump();
      expect(
        tester.getTopLeft(find.text('Cabecera')).dy,
        greaterThan(rest + 30),
      );
      await drag.up();
      await tester.pumpAndSettle();
      expect(find.text('Contenido'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Cabecera')).dy, closeTo(rest, 0.5));
    });

    testWidgets('con «Reducir movimiento» se funde a pantalla completa', (
      tester,
    ) async {
      await open(tester, reduce: true);
      await tester.tap(find.text('abrir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final early = tester.getTopLeft(find.text('Cabecera')).dy;
      await tester.pumpAndSettle();
      final end = tester.getTopLeft(find.text('Cabecera')).dy;
      // No se traslada: está en su sitio desde el primer fotograma.
      expect(early, closeTo(end, 0.5));
    });
  });

  group('avisos', () {
    testWidgets('un aviso nuevo sustituye al anterior', (tester) async {
      await pumpThemed(
        tester,
        Builder(
          builder: (context) => Column(
            children: [
              TextButton(
                onPressed: () => showRegalosSnackBar(
                  context,
                  const SnackBar(content: Text('Primero')),
                ),
                child: const Text('uno'),
              ),
              TextButton(
                onPressed: () => showRegalosSnackBar(
                  context,
                  const SnackBar(content: Text('Segundo')),
                ),
                child: const Text('dos'),
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('uno'));
      await tester.pumpAndSettle();
      expect(find.text('Primero'), findsOneWidget);
      await tester.tap(find.text('dos'));
      await tester.pumpAndSettle();
      expect(find.text('Primero'), findsNothing);
      expect(find.text('Segundo'), findsOneWidget);
    });
  });

  group('filtro', () {
    testWidgets('al activarse el visto entra con el ancho (AnimatedSize)', (
      tester,
    ) async {
      final selected = ValueNotifier<bool>(false);
      addTearDown(selected.dispose);
      await pumpThemed(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: selected,
          builder: (_, on, _) =>
              FilterPill(label: 'Falta comprar', selected: on, onTap: () {}),
        ),
      );
      final before = tester.getSize(find.byType(FilterPill)).width;
      selected.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final mid = tester.getSize(find.byType(FilterPill)).width;
      await tester.pumpAndSettle();
      final after = tester.getSize(find.byType(FilterPill)).width;
      expect(after, greaterThan(before + 10));
      expect(mid, lessThan(after));
      expect(find.byType(AnimatedSize), findsOneWidget);
    });

    testWidgets('con «Reducir movimiento» el ancho no se anima', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        FilterPill(label: 'Falta comprar', selected: true, onTap: () {}),
        disableAnimations: true,
      );
      expect(find.byType(AnimatedSize), findsNothing);
    });
  });

  group('PersonAvatar', () {
    Container boxOf(WidgetTester tester) => tester.widget<Container>(
      find
          .descendant(
            of: find.byType(PersonAvatar),
            matching: find.byType(Container),
          )
          .first,
    );

    for (final size in [28.0, 46.0, 80.0]) {
      testWidgets('de $size es un cuadrado de radio 8 como máximo', (
        tester,
      ) async {
        await pumpThemed(
          tester,
          PersonAvatar(name: 'Aritz', colorIndex: 0, size: size),
        );
        final decoration = boxOf(tester).decoration! as BoxDecoration;
        expect(decoration.shape, BoxShape.rectangle);
        final radius = (decoration.borderRadius! as BorderRadius).topLeft.x;
        expect(radius, lessThanOrEqualTo(8));
        expect(radius, greaterThan(0));
        expect(tester.getSize(find.byType(PersonAvatar)), Size(size, size));
      });
    }

    testWidgets('mide lo mismo con el texto del sistema al 200 %', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        const PersonAvatar(name: 'Aritz', colorIndex: 0, size: 40),
        textScale: 2,
      );
      expect(tester.getSize(find.byType(PersonAvatar)), const Size(40, 40));
    });
  });

  group('física del carrusel', () {
    test('el asentamiento de página usa el muelle snap', () {
      const physics = RegalosPagePhysics();
      expect(physics.spring.stiffness, 520);
      expect(physics.spring.damping, 38);
    });

    test('con «Reducir movimiento» es un muelle sin rebote', () {
      const physics = RegalosPagePhysics(reduce: true);
      // Críticamente amortiguado: amortiguación = 2 raíz(rigidez · masa).
      final s = physics.spring;
      expect(s.damping * s.damping, closeTo(4 * s.stiffness * s.mass, 1));
    });
  });

  testWidgets('RecentlyDeleted apunta y quita ids', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(recentlyDeletedProvider.notifier);
    notifier.add('g1');
    expect(container.read(recentlyDeletedProvider), {'g1'});
    notifier.clear('g1');
    expect(container.read(recentlyDeletedProvider), isEmpty);
  });
}

class _Counter extends StatefulWidget {
  const _Counter({required this.label});

  final String label;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _taps = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => setState(() => _taps++),
    child: Center(child: Text('${widget.label}: $_taps')),
  );
}
