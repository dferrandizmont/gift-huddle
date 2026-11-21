import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/widgets/danger_button.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/gifts/presentation/gift_editor_screen.dart';

import '../helpers/memory_stores.dart';
import '../helpers/screens.dart';

// Cerrar el editor de regalos con cambios sin guardar pregunta antes de
// descartarlos; sin cambios, cierra sin preguntar.

const _libro = 'Libro de dinosaurios con solapas';
final _editor = find.byType(GiftEditorScreen);
final _title = find.widgetWithText(TextField, 'Regalo');
const _question = '¿Descartar los cambios?';

Future<void> _open(WidgetTester tester, FakePhone phone) async {
  await seedSample(tester, phone);
  await pumpRegalos(tester, phone);
  await tapText(tester, 'Aritz');
  await tapText(tester, _libro);
  expect(find.text('Editar regalo'), findsOneWidget);
}

/// Los títulos guardados: el editado no debe estar, el original sí.
Future<void> _expectNothingSaved(WidgetTester tester, FakePhone phone) async {
  final titles = (await familyState(
    tester,
    phone,
  )).view.gifts.map((g) => g.title);
  expect(titles, contains(_libro));
  expect(titles, isNot(contains('Otro título')));
}

/// Un guardado que espera a que la prueba lo suelte (y puede fallar).
class _SlowFamily extends FamilyController {
  static Completer<void> gate = Completer<void>();
  static bool fail = false;

  /// Solo se retiene el guardado cuando la prueba lo arma (la siembra también
  /// guarda regalos).
  static bool armed = false;

  @override
  Future<GiftWriteResult> upsertGiftResult(Gift gift, {Gift? original}) async {
    if (armed) await gate.future;
    if (armed && fail) {
      throw StateError('no se pudo guardar');
    }
    return super.upsertGiftResult(gift, original: original);
  }

  /// Si se arma, el borrado espera a [deleteGate].
  static Completer<void> deleteGate = Completer<void>();
  static bool deleteArmed = false;

  @override
  Future<bool> deleteGiftWithUndo(String id) async {
    if (deleteArmed) await deleteGate.future;
    return super.deleteGiftWithUndo(id);
  }
}

/// «Borrar regalo» va al final de la lista en la hoja: se baja hasta él.
Future<void> _reveal(WidgetTester tester, Finder button) async {
  if (button.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      button,
      200,
      scrollable: find
          .descendant(
            of: find.byType(GiftEditorScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  await tester.ensureVisible(button);
}

/// Si el botón responde (en la hoja se baja antes hasta «Borrar regalo»).
Future<bool> _enabledAfterReveal(WidgetTester tester, Finder button) async {
  await _reveal(tester, button);
  return _enabled(tester, button);
}

bool _enabled(WidgetTester tester, Finder button) {
  final w = tester.widget(button);
  return w is DangerButton
      ? w.onPressed != null
      : (w as FilledButton).onPressed != null;
}

void main() {
  group('guardar y borrar no se solapan', () {
    final sheet = [familyControllerProvider.overrideWith(_SlowFamily.new)];
    final dialog = [
      ...sheet,
      giftEditorAsDialogProvider.overrideWithValue(true),
    ];
    final del = find.descendant(
      of: find.byType(GiftEditorScreen),
      matching: find.byType(DangerButton),
    );
    final save = find.descendant(
      of: find.byType(GiftEditorScreen),
      matching: find.widgetWithText(FilledButton, 'Guardar'),
    );

    for (final desktop in [false, true]) {
      final label = desktop ? 'diálogo de escritorio' : 'hoja';
      final size = desktop ? const Size(1536, 864) : const Size(390, 844);
      final overrides = desktop ? dialog : sheet;

      screenTest(
        '$label: mientras se guarda, «Borrar regalo» no responde',
        (tester, phone) async {
          _SlowFamily.armed = false;
          _SlowFamily.deleteArmed = false;
          await _open(tester, phone);
          await _reveal(tester, del);
          expect(await _enabledAfterReveal(tester, del), isTrue);
          _SlowFamily.gate = Completer<void>();
          _SlowFamily.fail = true;
          _SlowFamily.armed = true;
          await tester.tap(save);
          await tester.pump();
          // En la hoja los campos ni se pintan mientras se guarda; en el diálogo
          // el botón sigue a la vista, pero apagado.
          expect(del.evaluate().isEmpty || !_enabled(tester, del), isTrue);
          _SlowFamily.gate.complete();
          await settle(tester);
          // El guardado falló: el borrado vuelve a estar disponible.
          expect(await _enabledAfterReveal(tester, del), isTrue);
        },
        size: size,
        overrides: overrides,
      );

      screenTest(
        '$label: mientras se borra, «Guardar» no responde',
        (tester, phone) async {
          _SlowFamily.armed = false;
          _SlowFamily.deleteArmed = false;
          await _open(tester, phone);
          await _reveal(tester, del);
          _SlowFamily.deleteGate = Completer<void>();
          _SlowFamily.deleteArmed = true;
          await tester.tap(del);
          await settle(tester);
          await tester.tap(find.widgetWithText(FilledButton, 'Borrar').last);
          await tester.pump();
          expect(_enabled(tester, save), isFalse);
          expect(await _enabledAfterReveal(tester, del), isFalse);
          _SlowFamily.deleteArmed = false;
          _SlowFamily.deleteGate.complete();
          await settle(tester);
          expect(_editor, findsNothing);
        },
        size: size,
        overrides: overrides,
      );
    }
  });

  group('guardando, pedir cerrar no hace nada', () {
    final overrides = [familyControllerProvider.overrideWith(_SlowFamily.new)];

    Future<void> startSave(WidgetTester tester, FakePhone phone) async {
      _SlowFamily.armed = false;
      await _open(tester, phone);
      _SlowFamily.gate = Completer<void>();
      _SlowFamily.fail = false;
      _SlowFamily.armed = true;
      await tester.enterText(_title, 'Otro título');
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pump();
    }

    Future<void> askToClose(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Cerrar'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
    }

    screenTest('si el guardado falla, el borrador sigue ahí', (
      tester,
      phone,
    ) async {
      await startSave(tester, phone);
      await askToClose(tester);
      expect(find.text(_question), findsNothing);
      expect(_editor, findsOneWidget);
      _SlowFamily.fail = true;
      _SlowFamily.gate.complete();
      await settle(tester);
      expect(_editor, findsOneWidget);
      expect(find.text('Otro título'), findsOneWidget);
    }, overrides: overrides);

    screenTest(
      'si termina, se cierra una sola vez (no la pantalla de debajo)',
      (tester, phone) async {
        await startSave(tester, phone);
        await askToClose(tester);
        _SlowFamily.gate.complete();
        await settle(tester);
        expect(_editor, findsNothing);
        // La pantalla de la persona sigue debajo, con el regalo guardado.
        expect(find.text('Otro título'), findsOneWidget);
      },
      overrides: overrides,
    );
  });

  group('flecha de volver', () {
    screenTest('sin cambios cierra sin preguntar', (tester, phone) async {
      await _open(tester, phone);
      await tester.tap(find.bySemanticsLabel('Cerrar'));
      await settle(tester);
      expect(find.text(_question), findsNothing);
      expect(_editor, findsNothing);
    });

    screenTest('con cambios pregunta; «Seguir editando» conserva lo escrito', (
      tester,
      phone,
    ) async {
      await _open(tester, phone);
      await tester.enterText(_title, 'Otro título');
      await tester.tap(find.bySemanticsLabel('Cerrar'));
      await settle(tester);
      expect(find.text(_question), findsOneWidget);
      expect(find.text('Descartar'), findsOneWidget);
      expect(find.text('Seguir editando'), findsOneWidget);

      await tapText(tester, 'Seguir editando');
      expect(find.text(_question), findsNothing);
      expect(_editor, findsOneWidget);
      expect(find.text('Otro título'), findsOneWidget);
    });

    screenTest('«Descartar» cierra y no guarda nada', (tester, phone) async {
      await _open(tester, phone);
      await tester.enterText(_title, 'Otro título');
      await tester.tap(find.bySemanticsLabel('Cerrar'));
      await settle(tester);
      await tapText(tester, 'Descartar');
      expect(_editor, findsNothing);
      expect(find.text(_question), findsNothing);
      await _expectNothingSaved(tester, phone);
    });

    screenTest('si se deshace el cambio a mano ya no pregunta', (
      tester,
      phone,
    ) async {
      await _open(tester, phone);
      await tester.enterText(_title, 'Otro título');
      await tester.enterText(_title, _libro);
      await tester.tap(find.bySemanticsLabel('Cerrar'));
      await settle(tester);
      expect(find.text(_question), findsNothing);
      expect(_editor, findsNothing);
    });
  });

  group('gesto o botón de volver del sistema', () {
    screenTest('sin cambios vuelve sin preguntar', (tester, phone) async {
      await _open(tester, phone);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text(_question), findsNothing);
      expect(_editor, findsNothing);
    });

    screenTest('con cambios pregunta y, al descartar, vuelve', (
      tester,
      phone,
    ) async {
      await _open(tester, phone);
      await tester.enterText(_title, 'Otro título');
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text(_question), findsOneWidget);
      expect(_editor, findsOneWidget);
      await tapText(tester, 'Descartar');
      expect(_editor, findsNothing);
      await _expectNothingSaved(tester, phone);
    });

    screenTest('tocar fuera del diálogo de aviso equivale a seguir editando', (
      tester,
      phone,
    ) async {
      await _open(tester, phone);
      await tester.enterText(_title, 'Otro título');
      await tester.binding.handlePopRoute();
      await settle(tester);
      await tester.tapAt(const Offset(4, 4));
      await settle(tester);
      expect(find.text(_question), findsNothing);
      expect(_editor, findsOneWidget);
    });
  });

  screenTest('Esc con cambios también pregunta', (tester, phone) async {
    await _open(tester, phone);
    await tester.enterText(_title, 'Otro título');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.text(_question), findsOneWidget);
  });

  screenTest('arrastrar la hoja hacia abajo con cambios pregunta y, al seguir '
      'editando, la hoja vuelve a su sitio', (tester, phone) async {
    await _open(tester, phone);
    await tester.enterText(_title, 'Otro título');
    final top = tester.getTopLeft(_editor).dy;
    await tester.fling(find.text('Editar regalo'), const Offset(0, 600), 2000);
    await settle(tester);
    expect(find.text(_question), findsOneWidget);
    await tapText(tester, 'Seguir editando');
    expect(_editor, findsOneWidget);
    expect(tester.getTopLeft(_editor).dy, closeTo(top, 0.5));
  });

  screenTest('guardar cierra sin preguntar', (tester, phone) async {
    await _open(tester, phone);
    await tester.enterText(_title, 'Otro título');
    await tapText(tester, 'Guardar');
    await settle(tester);
    expect(find.text(_question), findsNothing);
    expect(_editor, findsNothing);
  });
}
