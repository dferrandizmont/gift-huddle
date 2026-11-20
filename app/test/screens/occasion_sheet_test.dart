import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/widgets/regalos_switch.dart';
import 'package:regalos/core/widgets/stroke_icon.dart';
import 'package:regalos/features/family/presentation/occasion_sheet.dart';

import '../helpers/pump_app.dart';

/// Abre la hoja de ocasión con el reloj en el 9 de noviembre de 2026 y deja
/// en [result] lo que devuelva.
class _Harness {
  Occasion? result;
  bool closed = false;

  Future<void> open(
    WidgetTester tester, {
    Occasion? initial,
    String? initialName,
  }) async {
    await pumpThemed(
      tester,
      Builder(
        builder: (context) => FilledButton(
          onPressed: () async {
            result = await showOccasionSheet(
              context,
              initial: initial,
              initialName: initialName,
            );
            closed = true;
          },
          child: const Text('Abrir'),
        ),
      ),
      surfaceSize: const Size(390, 1500),
    );
    await withClock(Clock.fixed(DateTime(2026, 11, 9, 10)), () async {
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
    });
  }
}

Future<void> _tapLabel(WidgetTester tester, String label) async {
  final finder = find.bySemanticsLabel(label).first;
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// El botón de confirmar del selector de fecha: el último de sus botones.
final Finder _dialogConfirm = find
    .descendant(of: find.byType(Dialog), matching: find.byType(TextButton))
    .last;

String _name(WidgetTester tester) => tester
    .widget<TextField>(find.widgetWithText(TextField, 'Nombre'))
    .controller!
    .text;

/// Una prueba con el reloj en el 9 de noviembre de 2026.
void clockedTest(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(
    description,
    (tester) =>
        withClock(Clock.fixed(DateTime(2026, 11, 9, 10)), () => body(tester)),
  );
}

void main() {
  final today = Clock.fixed(DateTime(2026, 11, 9, 10));

  clockedTest('el editor abre el calendario en la fecha archivada de 2024', (
    tester,
  ) async {
    final h = _Harness();
    await h.open(
      tester,
      initial: const Occasion(
        id: 'vieja',
        kind: OccasionKind.wedding,
        rawKind: 'wedding',
        name: 'Boda de Leo',
        month: 5,
        day: 2,
        year: 2024,
        recurring: false,
        archived: true,
      ),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, '2 de mayo'));
    await tester.pumpAndSettle();
    final picker = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(picker.initialDate, DateTime(2024, 5, 2));
    expect(tester.takeException(), isNull);
  });

  clockedTest('al crear, lo primero es elegir el tipo en una lista con icono', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final h = _Harness();
    await h.open(tester);
    expect(find.text('Nueva ocasión'), findsOneWidget);
    expect(find.text('Tipo de ocasión'), findsOneWidget);
    for (final label in [
      'Tió',
      'Navidad',
      'Reyes',
      'Año Nuevo Chino',
      'Boda',
      'Aniversario',
      'Sant Jordi',
      'San Valentín',
      'Bautizo o nacimiento',
      'Comunión',
      'Graduación o fin de curso',
      'Otra',
    ]) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
    // Cada tipo lleva su icono y no hay cumpleaños entre ellos.
    expect(find.byIcon(Icons.cake_outlined), findsNothing);
    // Tió, Navidad, Reyes, Año Nuevo Chino y Boda llevan icono de trazo.
    expect(find.byIcon(Icons.diamond_outlined), findsNothing);
    expect(find.byType(StrokeIcon), findsNWidgets(5));
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    expect(find.byIcon(Icons.church_outlined), findsOneWidget);
    expect(find.byIcon(Icons.school_outlined), findsOneWidget);
    // Ninguno elegido todavía.
    expect(_name(tester), isEmpty);
    semantics.dispose();
  });

  clockedTest('un tipo con fecha fija rellena el nombre y la fecha', (
    tester,
  ) async {
    final h = _Harness();
    await h.open(tester);
    await withClock(today, () => _tapLabel(tester, 'Sant Jordi'));
    expect(_name(tester), 'Sant Jordi');
    expect(find.text('23 de abril'), findsOneWidget);

    await withClock(today, () => _tapLabel(tester, 'San Valentín'));
    expect(_name(tester), 'San Valentín');
    expect(find.text('14 de febrero'), findsOneWidget);

    await withClock(today, () => _tapLabel(tester, 'Navidad'));
    expect(_name(tester), 'Navidad');
    expect(find.text('25 de diciembre'), findsOneWidget);

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    final o = h.result!;
    expect(o.kind, OccasionKind.santa);
    expect(o.rawKind, 'santa');
    expect((o.month, o.day), (12, 25));
    expect(o.recurring, isTrue);
    expect(o.year, isNull);
    expect(o.color, isNull);
    expect(o.icon, isNull);
  });

  clockedTest('el Año Nuevo Chino se calcula solo y no se puede cambiar', (
    tester,
  ) async {
    final h = _Harness();
    await h.open(tester);
    await withClock(today, () => _tapLabel(tester, 'Año Nuevo Chino'));
    expect(_name(tester), 'Año Nuevo Chino');
    // Hoy es el 9 de noviembre de 2026: el próximo cae el 6 de febrero.
    expect(find.text('6 de febrero'), findsOneWidget);
    expect(
      find.text('La fecha cambia cada año y se calcula sola.'),
      findsOneWidget,
    );
    // El botón de la fecha está apagado y no hay interruptor de «se repite».
    final button = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('6 de febrero'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Se repite cada año'), findsNothing);

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    final o = h.result!;
    expect(o.kind, OccasionKind.chineseNewYear);
    expect((o.month, o.day), (2, 6));
    expect(o.recurring, isTrue);
  });

  clockedTest('una boda no se repite y pide la fecha', (tester) async {
    final h = _Harness();
    await h.open(tester);
    await withClock(today, () => _tapLabel(tester, 'Boda'));
    expect(_name(tester), 'Boda');
    expect(find.text('Elegir fecha'), findsOneWidget);
    // Sin fecha no guarda.
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(h.closed, isFalse);
    expect(find.text('Elige una fecha.'), findsOneWidget);
    // Un aniversario, en cambio, se repite cada año.
    await withClock(today, () => _tapLabel(tester, 'Aniversario'));
    expect(_name(tester), 'Aniversario');
    final repeat = tester.widget<RegalosSwitch>(find.byType(RegalosSwitch));
    expect(repeat.value, isTrue);
    await withClock(today, () => _tapLabel(tester, 'Boda'));
    expect(
      tester.widget<RegalosSwitch>(find.byType(RegalosSwitch)).value,
      isFalse,
    );
  });

  clockedTest(
    'el nombre que escribe la persona no se pisa al cambiar de tipo',
    (tester) async {
      final h = _Harness();
      await h.open(tester);
      await withClock(today, () => _tapLabel(tester, 'Comunión'));
      expect(_name(tester), 'Comunión');
      await tester.enterText(
        find.widgetWithText(TextField, 'Nombre'),
        'Comunión de Nora',
      );
      await withClock(
        today,
        () => _tapLabel(tester, 'Graduación o fin de curso'),
      );
      expect(_name(tester), 'Comunión de Nora');
    },
  );

  clockedTest('«Otra» deja elegir nombre, color e icono', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = _Harness();
    await h.open(tester);
    // Sin «Otra» elegida no hay colores ni iconos.
    expect(find.text('Color'), findsNothing);
    expect(find.text('Icono'), findsNothing);
    await withClock(today, () => _tapLabel(tester, 'Otra'));
    expect(_name(tester), isEmpty);
    expect(find.text('Color'), findsOneWidget);
    expect(find.text('Icono'), findsOneWidget);
    // Ocho colores y doce iconos con nombre.
    for (final c in [
      'Lavanda',
      'Salvia',
      'Melocotón',
      'Cielo',
      'Rosa',
      'Mantequilla',
      'Turquesa',
      'Pizarra',
    ]) {
      expect(find.bySemanticsLabel(c), findsOneWidget, reason: c);
    }
    for (final i in [
      'Estrella',
      'Corazón',
      'Casa',
      'Viaje',
      'Escuela',
      'Mascota',
      'Bebé',
      'Trabajo',
      'Música',
      'Deporte',
      'Flor',
      'Fiesta',
    ]) {
      expect(find.bySemanticsLabel(i), findsOneWidget, reason: i);
    }

    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre'),
      'Excursión',
    );
    await _tapLabel(tester, 'Turquesa');
    await _tapLabel(tester, 'Música');
    await tester.tap(find.text('Elegir fecha'));
    await tester.pumpAndSettle();
    await tester.tap(_dialogConfirm);
    await tester.pumpAndSettle();
    expect(find.text('9 de noviembre'), findsOneWidget);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    final o = h.result!;
    expect(o.kind, OccasionKind.custom);
    expect(o.rawKind, 'custom');
    expect(o.name, 'Excursión');
    expect(o.color, 'teal');
    expect(o.icon, 'music');
    expect((o.month, o.day), (11, 9));
    semantics.dispose();
  });

  clockedTest('sin elegir tipo se guarda como «Otra»', (tester) async {
    final h = _Harness();
    await h.open(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Nombre'), 'Mudanza');
    await tester.tap(find.text('Elegir fecha'));
    await tester.pumpAndSettle();
    await tester.tap(_dialogConfirm);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    final o = h.result!;
    expect(o.kind, OccasionKind.custom);
    expect(o.name, 'Mudanza');
    expect(o.recurring, isTrue);
    // Sin elegir color ni icono no se guarda ninguno: sale el de serie.
    expect(o.color, isNull);
    expect(o.icon, isNull);
  });

  clockedTest('al editar sale elegido su tipo y se conserva si no se toca', (
    tester,
  ) async {
    const original = Occasion(
      id: 'k',
      kind: OccasionKind.kings,
      rawKind: 'kings',
      name: 'Reyes',
      month: 1,
      day: 6,
      recurring: true,
      archived: false,
    );
    final h = _Harness();
    await h.open(tester, initial: original);
    expect(find.text('Editar ocasión'), findsOneWidget);
    expect(_name(tester), 'Reyes');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(h.result, equals(original));
  });

  clockedTest('un tipo que esta versión no conoce se conserva al editar', (
    tester,
  ) async {
    const future = Occasion(
      id: 'f',
      kind: OccasionKind.custom,
      rawKind: 'futureKind',
      name: 'Algo nuevo',
      month: 3,
      day: 3,
      recurring: true,
      archived: false,
      color: 'sky',
      icon: 'trip',
    );
    final h = _Harness();
    await h.open(tester, initial: future);
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre'),
      'Otro nombre',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    final o = h.result!;
    expect(o.rawKind, 'futureKind');
    expect(o.name, 'Otro nombre');
    expect(o.color, 'sky');
    expect(o.icon, 'trip');
  });

  clockedTest('un cumpleaños no ofrece tipos ni deja cambiar la fecha', (
    tester,
  ) async {
    const birthday = Occasion(
      id: 'b',
      kind: OccasionKind.birthday,
      rawKind: 'birthday',
      name: 'Cumpleaños de Nora',
      month: 6,
      day: 12,
      recurring: true,
      recipientId: 'nora',
      archived: false,
    );
    final h = _Harness();
    await h.open(tester, initial: birthday);
    expect(find.text('Tipo de ocasión'), findsNothing);
    expect(
      find.text('La fecha sale del cumpleaños de la persona.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(h.result, equals(birthday));
  });

  clockedTest('una ocasión de serie se enseña con su nombre y, sin tocarlo, '
      'se guarda sin nombre', (tester) async {
    const seeded = Occasion(
      id: 'seed-kings',
      kind: OccasionKind.kings,
      rawKind: 'kings',
      name: '',
      month: 1,
      day: 6,
      recurring: true,
      archived: false,
    );
    final h = _Harness();
    await h.open(tester, initial: seeded, initialName: 'Reyes');
    expect(_name(tester), 'Reyes');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(h.result!.name, '');
    expect(h.result!.kind, OccasionKind.kings);
  });

  clockedTest('una ocasión de serie renombrada guarda el nombre nuevo', (
    tester,
  ) async {
    const seeded = Occasion(
      id: 'seed-kings',
      kind: OccasionKind.kings,
      rawKind: 'kings',
      name: '',
      month: 1,
      day: 6,
      recurring: true,
      archived: false,
    );
    final h = _Harness();
    await h.open(tester, initial: seeded, initialName: 'Reyes');
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre'),
      'Reyes en casa de los yayos',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(h.result!.name, 'Reyes en casa de los yayos');
  });

  clockedTest('al crear una ocasión con el nombre de su tipo no se guarda el '
      'texto traducido', (tester) async {
    final h = _Harness();
    await h.open(tester);
    await tester.tap(find.bySemanticsLabel('Boda').first);
    await tester.pumpAndSettle();
    expect(_name(tester), 'Boda');
    await tester.tap(find.text('Elegir fecha'));
    await tester.pumpAndSettle();
    await tester.tap(_dialogConfirm);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(h.result!.kind, OccasionKind.wedding);
    expect(h.result!.name, '');
  });

  group('presupuesto', () {
    const withBudget = Occasion(
      id: 'navidad',
      kind: OccasionKind.santa,
      rawKind: 'santa',
      name: 'Navidad',
      month: 12,
      day: 25,
      recurring: true,
      archived: false,
      budgetCents: 50000,
    );
    final field = find.byKey(const ValueKey<String>('occasion-budget-field'));
    String text(WidgetTester tester) =>
        tester.widget<TextField>(field).controller!.text;

    clockedTest('es opcional: vacío no pone ninguno', (tester) async {
      final h = _Harness();
      await h.open(tester);
      expect(find.text('Presupuesto (opcional)'), findsOneWidget);
      await withClock(today, () => _tapLabel(tester, 'Navidad'));
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(h.result!.budgetCents, isNull);
    });

    clockedTest('al crear, se lee como el precio de un regalo', (tester) async {
      final h = _Harness();
      await h.open(tester);
      await withClock(today, () => _tapLabel(tester, 'Navidad'));
      expect(
        tester.widget<TextField>(field).keyboardType,
        const TextInputType.numberWithOptions(decimal: true),
      );
      await tester.enterText(field, '1.250,5');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(h.result!.budgetCents, 125050);
    });

    clockedTest('pegar un presupuesto valida el cambio entero', (tester) async {
      final h = _Harness();
      await h.open(tester, initial: withBudget);
      for (final value in ['1', '12', '12,', '12,5', '12,50']) {
        await tester.enterText(field, value);
        expect(text(tester), value);
      }

      var clipboard = '12a50';
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.getData'
            ? <String, Object?>{'text': clipboard}
            : null,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final editable = tester.state<EditableTextState>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
      final controller = tester.widget<TextField>(field).controller!;
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      final beforePaste = controller.value;
      await editable.pasteText(SelectionChangedCause.keyboard);
      expect(controller.value, beforePaste);

      clipboard = '12 € 50 €';
      await editable.pasteText(SelectionChangedCause.keyboard);
      expect(text(tester), clipboard);
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(h.closed, isFalse);
      expect(
        find.text('Escribe un importe, por ejemplo 12,50.'),
        findsOneWidget,
      );

      clipboard = '12\u202f345,67 €';
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
      await editable.pasteText(SelectionChangedCause.keyboard);
      expect(text(tester), clipboard);
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(h.result!.budgetCents, 1234567);
    });

    clockedTest('al cambiar una ocasión con presupuesto se ve, se cambia y '
        'se quita', (tester) async {
      final h = _Harness();
      await h.open(tester, initial: withBudget);
      expect(text(tester), '500');
      await tester.enterText(field, '650,50');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(h.result!.budgetCents, 65050);
      expect(h.result!.id, 'navidad');

      final other = _Harness();
      await other.open(tester, initial: withBudget);
      await tester.enterText(field, '');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(other.closed, isTrue);
      expect(other.result!.budgetCents, isNull);
    });

    clockedTest('sin tocarlo se conserva', (tester) async {
      final h = _Harness();
      await h.open(tester, initial: withBudget);
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(h.result, equals(withBudget));
    });

    clockedTest('un importe que no vale avisa y no guarda', (tester) async {
      final h = _Harness();
      await h.open(tester, initial: withBudget);
      await tester.enterText(field, '12,345,6');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(h.closed, isFalse);
      expect(
        find.text('Escribe un importe, por ejemplo 12,50.'),
        findsOneWidget,
      );
      await tester.enterText(field, '12');
      await tester.pumpAndSettle();
      expect(find.text('Escribe un importe, por ejemplo 12,50.'), findsNothing);
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(h.result!.budgetCents, 1200);
    });

    clockedTest(
      'un importe negativo o fuera de rango no guarda ni envía nada',
      (tester) async {
        final h = _Harness();
        await h.open(tester, initial: withBudget);
        for (final bad in ['-5', '99999999999', '1,2,3']) {
          await tester.enterText(field, bad);
          await tester.tap(find.text('Guardar'));
          await tester.pumpAndSettle();
          expect(h.closed, isFalse, reason: bad);
          expect(h.result, isNull, reason: bad);
          expect(
            find.text('Escribe un importe, por ejemplo 12,50.'),
            findsOneWidget,
            reason: bad,
          );
        }
        // El máximo, el mismo que el del precio de un regalo, sí vale.
        await tester.enterText(field, '10000000');
        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();
        expect(h.result!.budgetCents, kMaxCents);
      },
    );

    clockedTest('también un cumpleaños lleva el campo', (tester) async {
      const birthday = Occasion(
        id: 'birthday-aritz',
        kind: OccasionKind.birthday,
        rawKind: 'birthday',
        name: 'Cumpleaños de Aritz',
        month: 3,
        day: 14,
        recurring: true,
        archived: false,
        recipientId: 'aritz',
      );
      final h = _Harness();
      await h.open(tester, initial: birthday);
      expect(field, findsOneWidget);
      await tester.enterText(field, '80');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(h.result!.budgetCents, 8000);
      expect(h.result!.kind, OccasionKind.birthday);
    });
  });

  clockedTest('con el texto al 130 % la lista de tipos no desborda', (
    tester,
  ) async {
    final h = _Harness();
    await pumpThemed(
      tester,
      Builder(
        builder: (context) => FilledButton(
          onPressed: () => showOccasionSheet(context),
          child: const Text('Abrir'),
        ),
      ),
      textScale: 1.3,
      surfaceSize: const Size(360, 1500),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'al abrir');
    await _tapLabel(tester, 'Otra');
    expect(tester.takeException(), isNull);
    expect(h.result, isNull);
  });
}
