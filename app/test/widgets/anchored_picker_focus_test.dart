// Foco al salir de un desplegable anclado con Tab o Mayús+Tab: el valor se
// aplica primero y el foco se mueve cuando el formulario lo ha incorporado, y
// «Idioma» devuelve el foco a su propia fila.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/widgets/picker_field.dart';
import 'package:regalos/core/widgets/settings_row.dart';
import 'package:regalos/features/settings/presentation/language_row.dart';

import '../helpers/pump_app.dart';

const _desktop = Size(1536, 900);

const _options = [
  PickerOption(value: 'a', label: 'Una persona'),
  PickerOption(value: 'other', label: 'Otra persona…'),
];

bool _focusedIn(String key) {
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

/// Un campo «Quién lo pidió» con un campo de texto que aparece (o desaparece)
/// según lo elegido, entre dos campos fijos.
Future<void> _pumpForm(
  WidgetTester tester, {
  required bool extraAppearsOnOther,
}) async {
  await pumpThemed(
    tester,
    _Form(extraAppearsOnOther: extraAppearsOnOther),
    surfaceSize: _desktop,
  );
}

class _Form extends StatefulWidget {
  const _Form({required this.extraAppearsOnOther});

  final bool extraAppearsOnOther;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  String _value = 'a';

  @override
  Widget build(BuildContext context) {
    // Con «Otra persona…» aparece el campo del nombre; o, al revés, es el campo
    // de «Detalle» el que se quita.
    final showExtra = widget.extraAppearsOnOther
        ? _value == 'other'
        : _value != 'other';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const TextField(key: ValueKey<String>('before')),
          PickerField<String>(
            label: 'Quién lo pidió',
            value: _value,
            options: _options,
            onChanged: (v) => setState(() => _value = v),
          ),
          if (showExtra) const TextField(key: ValueKey<String>('extra')),
          const TextField(key: ValueKey<String>('after')),
        ],
      ),
    );
  }
}

Future<void> _openAndTab(WidgetTester tester, {bool shift = false}) async {
  await tester.tap(
    find.byType(PickerField<String>),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
  await tester.pump();
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Tab con un campo que aparece al elegir cae en ese campo, no '
      'salta al de después', (tester) async {
    await _pumpForm(tester, extraAppearsOnOther: true);
    expect(find.byKey(const ValueKey<String>('extra')), findsNothing);
    await _openAndTab(tester);
    expect(find.byKey(const ValueKey<String>('extra')), findsOneWidget);
    expect(_focusedIn('extra'), isTrue);
    expect(_focusedIn('after'), isFalse);
  });

  testWidgets('Tab con un campo que desaparece al elegir sigue en el que '
      'queda detrás, sin errores', (tester) async {
    await _pumpForm(tester, extraAppearsOnOther: false);
    expect(find.byKey(const ValueKey<String>('extra')), findsOneWidget);
    await _openAndTab(tester);
    expect(find.byKey(const ValueKey<String>('extra')), findsNothing);
    expect(_focusedIn('after'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Mayús+Tab sigue yendo al campo anterior', (tester) async {
    await _pumpForm(tester, extraAppearsOnOther: true);
    await _openAndTab(tester, shift: true);
    expect(_focusedIn('before'), isTrue);
  });

  group('Idioma', () {
    final before = FocusNode(debugLabel: 'before-row');
    final after = FocusNode(debugLabel: 'after-row');

    Future<void> pumpRows(WidgetTester tester) async {
      final rows = await scopeWith(
        Column(
          children: [
            SettingsRow(
              key: const ValueKey<String>('before-row'),
              title: 'Antes',
              focusNode: before,
              onTap: () {},
            ),
            const LanguageRow(),
            SettingsRow(
              key: const ValueKey<String>('after-row'),
              title: 'Después',
              focusNode: after,
              onTap: () {},
            ),
          ],
        ),
      );
      await pumpThemed(tester, rows, surfaceSize: _desktop);
    }

    Future<void> openFromOtherRow(WidgetTester tester) async {
      // Otra fila tiene el foco; se abre «Idioma» con el ratón.
      before.requestFocus();
      await tester.pump();
      await tester.tap(find.text('Idioma'), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(find.text('Español'), findsOneWidget);
    }

    testWidgets('abierto con el ratón desde otra fila, Tab pasa a la fila de '
        'después de «Idioma»', (tester) async {
      await pumpRows(tester);
      await openFromOtherRow(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(after.hasPrimaryFocus, isTrue);
    });

    testWidgets('Mayús+Tab pasa a la fila de antes de «Idioma»', (
      tester,
    ) async {
      await pumpRows(tester);
      await openFromOtherRow(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(before.hasPrimaryFocus, isTrue);
    });

    testWidgets('Escape devuelve el foco a la fila de «Idioma», no a la otra', (
      tester,
    ) async {
      await pumpRows(tester);
      await openFromOtherRow(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(before.hasPrimaryFocus, isFalse);
      expect(after.hasPrimaryFocus, isFalse);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'LanguageRow');
    });
  });
}
