import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/widgets/anchored_picker.dart';
import 'package:regalos/core/widgets/picker_field.dart';

import '../helpers/pump_app.dart';

const _desktop = Size(1536, 900);
const _phone = Size(390, 844);

const _options = [
  PickerOption(value: 'none', label: 'Sin ocasión'),
  PickerOption(value: 'a', label: 'Reyes', group: 'Fiestas'),
  PickerOption(value: 'b', label: 'Tió', group: 'Fiestas'),
  PickerOption(value: 'x', label: 'Navidad', group: 'Fiestas', enabled: false),
  PickerOption(value: 'c', label: 'Cumpleaños de Aritz', group: 'Cumpleaños'),
  PickerOption(value: 'd', label: 'Cumpleaños de Nora', group: 'Cumpleaños'),
];

/// Un campo en [alignment] de una ventana de [surface] (de -1, arriba, a 1,
/// abajo), de 420 de ancho y metido en un panel que lo desplaza.
Future<ValueNotifier<String>> pumpField(
  WidgetTester tester, {
  Size surface = _desktop,
  Alignment alignment = Alignment.topCenter,
  List<PickerOption<String>> options = _options,
  String initial = 'a',
  bool reduce = false,
  double panelWidth = 420,
}) async {
  final value = ValueNotifier<String>(initial);
  await pumpThemed(
    tester,
    SizedBox(
      width: surface.width,
      height: surface.height,
      child: Align(
        alignment: alignment,
        child: SizedBox(
          width: panelWidth,
          child: SingleChildScrollView(
            child: ValueListenableBuilder<String>(
              valueListenable: value,
              builder: (context, v, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: PickerField<String>(
                  label: 'Ocasión',
                  value: v,
                  options: options,
                  onChanged: (n) => value.value = n,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    surfaceSize: surface,
    disableAnimations: reduce,
  );
  addTearDown(value.dispose);
  return value;
}

Future<void> clickField(WidgetTester tester) async {
  await tester.tap(
    find.byType(PickerField<String>),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pumpAndSettle();
}

Finder get panel => find.byKey(kAnchoredPickerKey);

String? focusedLabel(WidgetTester tester) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  final texts = <String>[];
  void visit(Element e) {
    if (e.widget is Text) texts.add((e.widget as Text).data ?? '');
    e.visitChildren(visit);
  }

  (context as Element).visitChildren(visit);
  return texts.isEmpty ? null : texts.first;
}

void main() {
  testWidgets('a 1536x900 con ratón abre un desplegable bajo el campo, no '
      'una hoja', (tester) async {
    await pumpField(tester);
    await clickField(tester);

    expect(find.byType(BottomSheet), findsNothing);
    expect(panel, findsOneWidget);
    final field = tester.getRect(find.byType(PickerField<String>));
    final box = tester.getRect(panel);
    // Mismo ancho y justo debajo.
    expect(box.left, closeTo(field.left, 0.5));
    expect(box.width, closeTo(field.width, 0.5));
    expect(box.top, closeTo(field.bottom + 4, 0.5));
    // Agrupado, con cabecera y contador, y con la elegida marcada.
    expect(find.text('Fiestas'), findsOneWidget);
    expect(find.text('Cumpleaños'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('con el campo abajo se abre encima y cabe en la ventana', (
    tester,
  ) async {
    await pumpField(tester, alignment: Alignment.bottomCenter);
    await clickField(tester);

    final field = tester.getRect(find.byType(PickerField<String>));
    final box = tester.getRect(panel);
    expect(box.bottom, closeTo(field.top - 4, 0.5));
    expect(box.top, greaterThanOrEqualTo(8));
    expect(box.bottom, lessThanOrEqualTo(_desktop.height - 8));
  });

  testWidgets('una lista larga pasa de 400 como mucho, se desplaza y abre con '
      'la elegida a la vista', (tester) async {
    final long = [
      for (var i = 0; i < 24; i++)
        PickerOption(value: 'p$i', label: 'Persona $i'),
    ];
    await pumpField(tester, options: long, initial: 'p20');
    await clickField(tester);

    final box = tester.getRect(panel);
    expect(box.height, lessThanOrEqualTo(400));
    final chosen = tester.getRect(
      find.descendant(of: panel, matching: find.text('Persona 20')),
    );
    expect(chosen.top, greaterThanOrEqualTo(box.top));
    expect(chosen.bottom, lessThanOrEqualTo(box.bottom));
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      contains('Anchored'),
    );
    expect(find.byType(Scrollbar), findsOneWidget);
  });

  testWidgets('no se sale del panel lateral: se recorta a su zona visible', (
    tester,
  ) async {
    // Un panel a la derecha de la ventana, con el campo en su borde.
    await pumpField(tester, alignment: Alignment.centerRight, panelWidth: 360);
    await clickField(tester);

    final box = tester.getRect(panel);
    final field = tester.getRect(find.byType(PickerField<String>));
    expect(box.left, greaterThanOrEqualTo(field.left - 0.5));
    expect(box.right, lessThanOrEqualTo(_desktop.width - 8));
    expect(box.right, lessThanOrEqualTo(field.right + 0.5));
  });

  testWidgets('al abrir enfoca la elegida; flechas saltan cabeceras y '
      'opciones apagadas; Intro elige y el foco vuelve al campo', (
    tester,
  ) async {
    final value = await pumpField(tester);
    await clickField(tester);

    expect(focusedLabel(tester), 'Reyes');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focusedLabel(tester), 'Tió');
    // «Navidad» está apagada: salta a la de la otra sección.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focusedLabel(tester), 'Cumpleaños de Aritz');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(focusedLabel(tester), 'Tió');
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(focusedLabel(tester), 'Cumpleaños de Nora');
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(focusedLabel(tester), 'Sin ocasión');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(value.value, 'b');
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'PickerField');
  });

  testWidgets('Espacio elige la enfocada', (tester) async {
    final value = await pumpField(tester);
    await clickField(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(value.value, 'none');
  });

  testWidgets('Escape cierra sin elegir y devuelve el foco al campo', (
    tester,
  ) async {
    final value = await pumpField(tester);
    await clickField(tester);
    expect(panel, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(value.value, 'a');
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'PickerField');
  });

  /// Tres campos seguidos; el desplegable se abre en el del medio.
  Future<ValueNotifier<String>> pumpThree(WidgetTester tester) async {
    final value = ValueNotifier<String>('a');
    addTearDown(value.dispose);
    await pumpThemed(
      tester,
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const TextField(key: ValueKey<String>('before')),
            ValueListenableBuilder<String>(
              valueListenable: value,
              builder: (context, v, _) => PickerField<String>(
                label: 'Ocasión',
                value: v,
                options: _options,
                onChanged: (n) => value.value = n,
              ),
            ),
            const TextField(key: ValueKey<String>('after')),
          ],
        ),
      ),
      surfaceSize: _desktop,
    );
    return value;
  }

  bool focusedIn(String key) {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return false;
    var found = false;
    focused.visitAncestorElements((e) {
      if (e.widget.key == ValueKey<String>(key)) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  testWidgets('Tab elige la enfocada, cierra y pasa al campo siguiente', (
    tester,
  ) async {
    final value = await pumpThree(tester);
    await clickField(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(value.value, 'b');
    expect(focusedIn('after'), isTrue);
  });

  testWidgets('Mayús+Tab elige la enfocada, cierra y vuelve al campo '
      'anterior', (tester) async {
    final value = await pumpThree(tester);
    await clickField(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(value.value, 'b');
    expect(focusedIn('before'), isTrue);
  });

  testWidgets('un clic fuera lo cierra sin elegir', (tester) async {
    final value = await pumpField(tester);
    await clickField(tester);
    expect(panel, findsOneWidget);

    await tester.tapAt(const Offset(1400, 700), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(value.value, 'a');
  });

  testWidgets('un clic en una opción la elige y cierra', (tester) async {
    final value = await pumpField(tester);
    await clickField(tester);
    await tester.tap(
      find.descendant(of: panel, matching: find.text('Cumpleaños de Nora')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(value.value, 'd');
  });

  testWidgets('elegida con el ratón, el campo no se queda con el foco (ni con '
      'su filete)', (tester) async {
    final value = await pumpField(tester);
    await clickField(tester);
    await tester.tap(
      find.descendant(of: panel, matching: find.text('Cumpleaños de Nora')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(value.value, 'd');
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      isNot('PickerField'),
    );
    expect(
      tester.widget<InputDecorator>(find.byType(InputDecorator)).isFocused,
      isFalse,
    );
  });

  testWidgets('elegida con el teclado, el foco vuelve al campo', (
    tester,
  ) async {
    final value = await pumpField(tester);
    await clickField(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(value.value, isNot('a'));
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'PickerField');
  });

  testWidgets('una opción apagada no se elige', (tester) async {
    final value = await pumpField(tester);
    await clickField(tester);
    await tester.tap(
      find.descendant(of: panel, matching: find.text('Navidad')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    expect(value.value, 'a');
  });

  for (final reduce in [false, true]) {
    testWidgets(
      reduce
          ? 'con «Reducir movimiento» solo se funde'
          : 'entra con una escala leve desde el borde del campo',
      (tester) async {
        await pumpField(tester, reduce: reduce);
        await tester.tap(
          find.byType(PickerField<String>),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        final moving = tester.getTopLeft(panel);
        await tester.pumpAndSettle();
        final settled = tester.getTopLeft(panel);

        if (reduce) {
          expect(moving, settled);
        } else {
          // Crece desde el centro de su borde de arriba: antes de asentarse el
          // borde izquierdo está más adentro y el de arriba no se ha movido.
          expect(moving.dx, greaterThan(settled.dx));
          expect(moving.dy, closeTo(settled.dy, 0.01));
        }
      },
    );
  }

  testWidgets('semántica de menú con la etiqueta del campo y la opción '
      'elegida anunciada', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpField(tester);
    await clickField(tester);

    expect(
      tester.getSemantics(find.bySemanticsLabel('Ocasión').last),
      isSemantics(label: 'Ocasión'),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Reyes').last),
      isSemantics(
        label: 'Reyes',
        hasCheckedState: true,
        isChecked: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Tió').last),
      isSemantics(label: 'Tió', hasCheckedState: true, isChecked: false),
    );
    handle.dispose();
  });

  testWidgets('a 390x844 sigue la hoja inferior, también con ratón', (
    tester,
  ) async {
    await pumpField(tester, surface: _phone);
    await clickField(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(panel, findsNothing);
  });

  testWidgets('a 1536x900 con el dedo sigue la hoja inferior', (tester) async {
    await pumpField(tester);
    await tester.tap(find.byType(PickerField<String>));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(panel, findsNothing);
  });

  testWidgets('el campo se ve abierto mientras dura el desplegable', (
    tester,
  ) async {
    await pumpField(tester);
    InputDecorator decorator() =>
        tester.widget<InputDecorator>(find.byType(InputDecorator));
    expect(decorator().isFocused, isFalse);
    await clickField(tester);
    expect(decorator().isFocused, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(decorator().isFocused, isFalse);
  });

  testWidgets('flecha arriba en la primera opción se queda donde está: Inicio, '
      'arriba e Intro elige la primera, no la que estaba elegida', (
    tester,
  ) async {
    final value = await pumpField(tester);
    await clickField(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(focusedLabel(tester), 'Sin ocasión');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(value.value, 'none');
  });

  testWidgets('si el campo se desmonta con el desplegable abierto (otro '
      'diseño al cambiar la ventana), se cierra sin elegir ni fallar', (
    tester,
  ) async {
    var picked = '';
    tester.view
      ..physicalSize = _desktop
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpThemed(
      tester,
      LayoutBuilder(
        builder: (context, box) {
          final field = PickerField<String>(
            label: 'Ocasión',
            value: 'a',
            options: _options,
            onChanged: (v) => picked = v,
          );
          // Pasa de una columna a dos al ensancharse: otro árbol, otro campo.
          return MediaQuery.sizeOf(context).width > 1500
              ? Row(children: [Expanded(child: field)])
              : Column(children: [field]);
        },
      ),
      surfaceSize: const Size(1400, 900),
    );
    await clickField(tester);
    expect(panel, findsOneWidget);

    tester.view.physicalSize = _desktop;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(panel, findsNothing);
    expect(picked, '');
  });

  testWidgets('sigue al campo cuando el panel se desplaza y se cierra si '
      'deja de verse', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await pumpThemed(
      tester,
      SizedBox(
        width: 420,
        height: 500,
        child: SingleChildScrollView(
          controller: controller,
          child: Column(
            children: [
              const SizedBox(height: 100),
              PickerField<String>(
                label: 'Ocasión',
                value: 'a',
                options: _options,
                onChanged: (_) {},
              ),
              const SizedBox(height: 1200),
            ],
          ),
        ),
      ),
      surfaceSize: _desktop,
    );
    await clickField(tester);
    final field = find.byType(PickerField<String>);
    expect(
      tester.getRect(panel).top,
      closeTo(tester.getRect(field).bottom + 4, 0.5),
    );

    controller.jumpTo(40);
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    expect(
      tester.getRect(panel).top,
      closeTo(tester.getRect(field).bottom + 4, 0.5),
    );

    controller.jumpTo(600);
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
  });

  testWidgets('con el campo cerca del pie del panel se abre encima y no pasa '
      'sobre lo que queda fuera de su zona visible', (tester) async {
    await pumpThemed(
      tester,
      SizedBox(
        width: 420,
        height: 900,
        child: Column(
          children: [
            SizedBox(
              height: 400,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 300),
                    PickerField<String>(
                      label: 'Ocasión',
                      value: 'a',
                      options: _options,
                      onChanged: (_) {},
                    ),
                    const SizedBox(height: 300),
                  ],
                ),
              ),
            ),
            // El pie fijo del editor: «Borrar», «Cancelar», «Guardar».
            const SizedBox(height: 100, key: ValueKey('footer')),
          ],
        ),
      ),
      surfaceSize: _desktop,
    );
    await clickField(tester);

    final viewport = tester.getRect(find.byType(SingleChildScrollView).first);
    final box = tester.getRect(panel);
    final field = tester.getRect(find.byType(PickerField<String>));
    expect(box.bottom, closeTo(field.top - 4, 0.5));
    expect(box.top, greaterThanOrEqualTo(viewport.top));
    expect(box.bottom, lessThanOrEqualTo(viewport.bottom));
  });

  testWidgets('si una reconstrucción quita el campo (sin scroll ni cambio de '
      'ventana), el desplegable se cierra y su Future completa con null', (
    tester,
  ) async {
    final show = ValueNotifier<bool>(true);
    addTearDown(show.dispose);
    const fieldKey = ValueKey('campo');
    await pumpThemed(
      tester,
      ValueListenableBuilder<bool>(
        valueListenable: show,
        builder: (context, on, _) => on
            ? SizedBox(
                width: 420,
                child: PickerField<String>(
                  key: fieldKey,
                  label: 'Ocasión',
                  value: 'a',
                  options: _options,
                  onChanged: (_) {},
                ),
              )
            : const SizedBox(width: 420, height: 52),
      ),
      surfaceSize: _desktop,
    );
    // Un ratón conectado y el desplegable abierto directamente.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    String? result = 'sin cerrar';
    var completed = false;
    final anchor = tester.element(find.byKey(fieldKey));
    unawaited(
      showAnchoredPicker<String>(
        anchor,
        label: 'Ocasión',
        options: _options,
        selected: 'a',
      ).then((v) {
        result = v;
        completed = true;
      }),
    );
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);

    show.value = false;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(panel, findsNothing);
    expect(completed, isTrue);
    expect(result, isNull);
  });

  /// Un panel de [viewport] de alto con el campo a [fieldTop] dentro, y un pie
  /// fijo de 100 debajo, arriba de una ventana de 1536x900.
  Future<void> pumpPanel(
    WidgetTester tester, {
    required double viewport,
    required double fieldTop,
  }) => pumpThemed(
    tester,
    SizedBox(
      width: 420,
      height: 900,
      child: Column(
        children: [
          SizedBox(
            height: viewport,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(height: fieldTop),
                  PickerField<String>(
                    label: 'Ocasión',
                    value: 'a',
                    options: _options,
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: 300),
                ],
              ),
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    ),
    surfaceSize: _desktop,
  );

  testWidgets('en un viewport de 400 con el campo a 200 no pisa el pie: se '
      'ajusta al lado con más sitio y la lista se desplaza', (tester) async {
    await pumpPanel(tester, viewport: 400, fieldTop: 200);
    await clickField(tester);

    final view = tester.getRect(find.byType(SingleChildScrollView).first);
    final box = tester.getRect(panel);
    final field = tester.getRect(find.byType(PickerField<String>));
    // Debajo solo quedan unos 144: se abre encima, dentro del viewport.
    expect(box.bottom, closeTo(field.top - 4, 0.5));
    expect(box.top, greaterThanOrEqualTo(view.top));
    expect(box.bottom, lessThanOrEqualTo(view.bottom));
    expect(box.height, greaterThanOrEqualTo(150));
  });

  testWidgets('un diálogo muy bajo no deja ni 3 filas: se sale del viewport '
      'hacia el lado con más sitio, sin salir de la ventana', (tester) async {
    await pumpPanel(tester, viewport: 150, fieldTop: 40);
    await clickField(tester);

    final view = tester.getRect(find.byType(SingleChildScrollView).first);
    final box = tester.getRect(panel);
    expect(box.bottom, greaterThan(view.bottom));
    expect(box.top, greaterThanOrEqualTo(8));
    expect(box.bottom, lessThanOrEqualTo(_desktop.height - 8));
  });
}
