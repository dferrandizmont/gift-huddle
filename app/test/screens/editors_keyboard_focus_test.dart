// Tras cerrar un selector de fecha o un desplegable en los editores de regalo,
// persona y ocasión, ningún campo de texto recupera el foco (el teclado no se
// abre solo y tapa el formulario: fallo m5 de la QA de la 1.0.4) y el foco
// queda en el control que lo abrió, de modo que el siguiente Tab sigue desde
// él y no desde el principio del formulario.
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/widgets/picker_field.dart';
import 'package:regalos/core/widgets/release_text_focus.dart';
import 'package:regalos/features/family/presentation/occasion_sheet.dart';
import 'package:regalos/features/family/presentation/person_sheet.dart';
import 'package:regalos/features/gifts/presentation/gift_editor_screen.dart';

import '../helpers/pump_app.dart';
import '../helpers/screens.dart';

/// Los elementos del foco primario y de sus ancestros.
List<Element> _focusChain() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return const [];
  final chain = <Element>[context as Element];
  context.visitAncestorElements((e) {
    chain.add(e);
    return true;
  });
  return chain;
}

/// Si el foco está en un campo de texto (el teclado se abriría).
bool _textHasFocus() => _focusChain().any((e) => e.widget is EditableText);

/// Si el foco está en [element] o dentro de él.
bool _focusIn(Element element) => _focusChain().contains(element);

/// El botón de confirmar del selector de fecha: el último de sus botones.
final Finder _dialogConfirm = find
    .descendant(of: find.byType(Dialog), matching: find.byType(TextButton))
    .last;

/// El botón de cancelar del selector de fecha: el primero de sus botones.
final Finder _dialogCancel = find
    .descendant(of: find.byType(Dialog), matching: find.byType(TextButton))
    .first;

/// Abre [sheet] desde un botón.
Future<void> _open(
  WidgetTester tester,
  Future<Object?> Function(BuildContext context) sheet,
) async {
  await pumpThemed(
    tester,
    Builder(
      builder: (context) => FilledButton(
        onPressed: () => sheet(context),
        child: const Text('Abrir'),
      ),
    ),
    surfaceSize: const Size(390, 1500),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

/// El botón «Elegir fecha» (su elemento, que sigue siendo el mismo aunque el
/// texto cambie).
Element _dateButton(WidgetTester tester) => tester.element(
  find.ancestor(
    of: find.text('Elegir fecha'),
    matching: find.byType(OutlinedButton),
  ),
);

/// Tras cerrar el calendario: ningún campo de texto con foco, el foco en el
/// botón de fecha y el Tab siguiente sigue desde él (no vuelve al nombre).
Future<void> _expectBackOnDateButton(
  WidgetTester tester,
  Element button,
  Finder name,
) async {
  expect(find.byType(DatePickerDialog), findsNothing);
  expect(_textHasFocus(), isFalse);
  expect(_focusIn(button), isTrue);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pump();
  expect(_focusIn(button), isFalse, reason: 'Tab avanza desde el botón');
  expect(
    _focusIn(tester.element(name)),
    isFalse,
    reason: 'no vuelve al nombre',
  );
}

void main() {
  testWidgets('ocasión: tras elegir la fecha, el nombre no recupera el foco', (
    tester,
  ) async {
    await withClock(Clock.fixed(DateTime(2026, 11, 9, 10)), () async {
      await _open(tester, (c) => showOccasionSheet(c));
      final name = find.widgetWithText(TextField, 'Nombre');
      await tester.enterText(name, 'Excursión');
      await tester.pump();
      expect(_textHasFocus(), isTrue);
      final button = _dateButton(tester);

      await tester.tap(find.text('Elegir fecha'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(_dialogConfirm);
      await tester.pumpAndSettle();

      await _expectBackOnDateButton(tester, button, name);
    });
  });

  testWidgets('ocasión: cancelar el selector tampoco devuelve el foco', (
    tester,
  ) async {
    await withClock(Clock.fixed(DateTime(2026, 11, 9, 10)), () async {
      await _open(tester, (c) => showOccasionSheet(c));
      final name = find.widgetWithText(TextField, 'Nombre');
      await tester.enterText(name, 'Excursión');
      await tester.pump();
      final button = _dateButton(tester);
      await tester.tap(find.text('Elegir fecha'));
      await tester.pumpAndSettle();
      await tester.tap(_dialogCancel);
      await tester.pumpAndSettle();
      await _expectBackOnDateButton(tester, button, name);
    });
  });

  for (final confirm in [true, false]) {
    testWidgets(
      'persona: tras ${confirm ? 'elegir' : 'cancelar'} la fecha, el nombre no '
      'recupera el foco y Tab sigue desde el botón',
      (tester) async {
        await withClock(Clock.fixed(DateTime(2026, 11, 9, 10)), () async {
          await _open(tester, (c) => showPersonSheet(c, defaultColorIndex: 0));
          // «Nombre» lleva el foco al abrir (autofocus).
          expect(_textHasFocus(), isTrue);
          final name = find.widgetWithText(TextField, 'Nombre');
          final button = _dateButton(tester);

          await tester.ensureVisible(find.text('Elegir fecha'));
          await tester.tap(find.text('Elegir fecha'));
          await tester.pumpAndSettle();
          expect(find.byType(DatePickerDialog), findsOneWidget);
          await tester.tap(confirm ? _dialogConfirm : _dialogCancel);
          await tester.pumpAndSettle();

          await _expectBackOnDateButton(tester, button, name);
        });
      },
    );
  }

  testWidgets('releaseTextFocus pasa el foco al control indicado, o lo suelta '
      'sin él, y no toca otros focos', (tester) async {
    final field = FocusNode();
    final button = FocusNode();
    addTearDown(field.dispose);
    addTearDown(button.dispose);
    await pumpThemed(
      tester,
      Column(
        children: [
          TextField(focusNode: field),
          TextButton(
            focusNode: button,
            onPressed: () {},
            child: const Text('B'),
          ),
        ],
      ),
    );
    field.requestFocus();
    await tester.pump();
    releaseTextFocus(to: button);
    await tester.pump();
    expect(button.hasPrimaryFocus, isTrue);

    // Un botón enfocado no es un campo de texto: no se toca.
    releaseTextFocus();
    await tester.pump();
    expect(button.hasPrimaryFocus, isTrue);

    field.requestFocus();
    await tester.pump();
    releaseTextFocus();
    await tester.pump();
    expect(_textHasFocus(), isFalse);
  });

  screenTest(
    'regalo: tras elegir en un desplegable, el título no recupera el foco y '
    'Tab sigue desde el desplegable',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.tap(
        find.widgetWithText(FloatingActionButton, 'Añadir regalo'),
      );
      await settle(tester);
      expect(find.byType(GiftEditorScreen), findsOneWidget);

      final title = find.widgetWithText(TextField, 'Regalo');
      final titleElement = tester.element(title);
      await tester.enterText(title, 'Bicicleta');
      await tester.pump();
      expect(_textHasFocus(), isTrue);

      final giver = find.byWidgetPredicate(
        (w) => w is PickerField<String> && w.label == 'Quién regala',
      );
      await tester.ensureVisible(giver);
      await tester.pump();
      final field = tester.element(giver);
      await tester.tap(giver);
      await settle(tester);
      final sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget);
      await tester.tap(
        find.descendant(of: sheet, matching: find.byType(InkWell)).first,
      );
      await settle(tester);

      expect(sheet, findsNothing);
      expect(_textHasFocus(), isFalse);
      // El foco queda en el propio desplegable «Quién regala».
      expect(_focusIn(field), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_focusIn(field), isFalse);
      expect(_focusIn(titleElement), isFalse);
    },
  );

  screenTest(
    'regalo: elegir «Para quién» con el título vacío no abre el teclado',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.tap(
        find.widgetWithText(FloatingActionButton, 'Añadir regalo'),
      );
      await settle(tester);
      expect(find.byType(GiftEditorScreen), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Regalo'))
            .controller!
            .text,
        isEmpty,
      );

      final title = tester.element(find.widgetWithText(TextField, 'Regalo'));
      final who = find.byWidgetPredicate(
        (w) => w is PickerField<String> && w.label == 'Para quién',
      );
      final whoElement = tester.element(who);
      await tester.tap(who);
      await settle(tester);
      final sheet = find.byType(BottomSheet);
      await tester.tap(find.descendant(of: sheet, matching: find.text('Nora')));
      await settle(tester);

      expect(sheet, findsNothing);
      expect(
        find.bySemanticsLabel(RegExp(r'^Para quién, Nora')),
        findsOneWidget,
      );
      expect(_textHasFocus(), isFalse);
      // El foco vuelve a «Para quién» (no al contenedor del editor) y el
      // siguiente Tab llega a «Regalo».
      expect(_focusIn(whoElement), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_focusIn(whoElement), isFalse);
      expect(_focusIn(title), isTrue);
    },
  );
}
