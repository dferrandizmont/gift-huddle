import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/widgets/confirm_dialog.dart';
import 'package:regalos/features/family/application/self_recipient_provider.dart';
import 'package:regalos/features/settings/presentation/manage_screens.dart';

import '../helpers/memory_stores.dart';
import '../helpers/other_phone.dart';
import '../helpers/screens.dart';

const _tall = Size(390, 1500);
const _reason = 'Es la persona de este móvil.';

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.text('Ajustes').last);
  await settle(tester);
}

/// Elige de quién es este móvil (como la fila «Este móvil es de»).
Future<void> _choose(WidgetTester tester, FakePhone phone, String? id) =>
    tester.runAsync(
      () => phone.container.read(selfRecipientIdProvider.notifier).choose(id),
    );

/// La fila de gestionar de [name].
Finder _row(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(ManageRow));

/// El botón [label] («Archivar», «Recuperar» o «Eliminar») de la fila de
/// [name].
Finder _buttonFinder(String name, String label) => find.descendant(
  of: _row(name),
  matching: find.widgetWithText(TextButton, label),
);

bool _enabled(WidgetTester tester, String name, String label) =>
    tester.widget<TextButton>(_buttonFinder(name, label)).onPressed != null;

/// A la persona de un móvil de la familia no se la puede archivar ni eliminar
/// desde Ajustes › Personas ni desde Ajustes › Archivo.
void main() {
  screenTest(
    'la persona de este móvil tiene Archivar y Eliminar desactivados y una '
    'línea que dice por qué; las demás, no',
    (tester, phone) async {
      await seedSample(tester, phone);
      await _choose(tester, phone, 'nora');
      await pumpRegalos(tester, phone);
      await _openSettings(tester);
      await tapText(tester, 'Personas');

      // Solo la fila de Nora lo dice, también a quien usa lector de pantalla.
      expect(find.text(_reason), findsOneWidget);
      expect(
        find.descendant(of: _row('Nora'), matching: find.text(_reason)),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(r'^Nora\. .*Es la persona de este móvil\.$'),
        ),
        findsOneWidget,
      );
      expect(_enabled(tester, 'Nora', 'Archivar'), isFalse);
      expect(_enabled(tester, 'Nora', 'Eliminar'), isFalse);
      for (final other in ['Aritz', 'Leo']) {
        expect(_enabled(tester, other, 'Archivar'), isTrue, reason: other);
        expect(_enabled(tester, other, 'Eliminar'), isTrue, reason: other);
      }

      // Pulsarlos no pregunta ni cambia nada.
      await tester.tap(_buttonFinder('Nora', 'Eliminar'), warnIfMissed: false);
      await settle(tester);
      expect(find.byType(ConfirmDialog), findsNothing);
      await tester.tap(_buttonFinder('Nora', 'Archivar'), warnIfMissed: false);
      await settle(tester);
      expect(find.text('Nora'), findsOneWidget);
      final state = await familyState(tester, phone);
      expect(state.view.recipients.map((r) => r.id), contains('nora'));
      expect(
        state.view.gifts.where((g) => g.recipientId == 'nora'),
        isNotEmpty,
      );
      expect(tester.takeException(), isNull);

      // Editarla sí se puede.
      await tapText(tester, 'Nora');
      expect(find.text('Editar persona'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Nombre'),
        'Nora Martí',
      );
      await tapText(tester, 'Guardar');
      expect(find.text('Nora Martí'), findsOneWidget);
      expect(_enabled(tester, 'Nora Martí', 'Archivar'), isFalse);
      expect(tester.takeException(), isNull);
    },
    size: _tall,
  );

  screenTest(
    'si el móvil pasa a ser de otra persona o de nadie, el bloqueo la sigue',
    (tester, phone) async {
      await seedSample(tester, phone);
      await _choose(tester, phone, 'nora');
      await pumpRegalos(tester, phone);
      await _openSettings(tester);
      await tapText(tester, 'Personas');
      expect(_enabled(tester, 'Nora', 'Eliminar'), isFalse);

      await _choose(tester, phone, 'leo');
      await settle(tester);
      expect(find.text(_reason), findsOneWidget);
      expect(_enabled(tester, 'Nora', 'Archivar'), isTrue);
      expect(_enabled(tester, 'Nora', 'Eliminar'), isTrue);
      expect(_enabled(tester, 'Leo', 'Archivar'), isFalse);
      expect(_enabled(tester, 'Leo', 'Eliminar'), isFalse);

      await _choose(tester, phone, null);
      await settle(tester);
      expect(find.text(_reason), findsNothing);
      for (final name in ['Aritz', 'Nora', 'Leo']) {
        expect(_enabled(tester, name, 'Archivar'), isTrue, reason: name);
        expect(_enabled(tester, name, 'Eliminar'), isTrue, reason: name);
      }

      // Y ahora a Nora sí se la puede archivar.
      await tester.tap(find.bySemanticsLabel('Archivar Nora'));
      await settle(tester);
      expect(find.text('Nora'), findsNothing);
      expect(tester.takeException(), isNull);
    },
    size: _tall,
  );

  screenTest(
    'con la letra muy grande la línea cabe bajo el nombre y los botones '
    'siguen desactivados',
    (tester, phone) async {
      await seedSample(tester, phone);
      await _choose(tester, phone, 'nora');
      await pumpRegalos(tester, phone);
      await _openSettings(tester);
      await tapText(tester, 'Personas');
      expect(find.text(_reason), findsOneWidget);
      expect(_enabled(tester, 'Nora', 'Archivar'), isFalse);
      expect(_enabled(tester, 'Nora', 'Eliminar'), isFalse);
      expect(tester.takeException(), isNull);
    },
    size: _tall,
    textScale: 1.3,
  );

  screenTest(
    'en Archivo, a la persona de este móvil que otro móvil archivó se la '
    'puede recuperar, pero no eliminar',
    (tester, phone) async {
      await seedSample(tester, phone);
      await _choose(tester, phone, 'nora');
      await tester.runAsync(() => archivedElsewhere(phone, 'nora'));
      await pumpRegalos(tester, phone);
      await _openSettings(tester);
      await tapText(tester, 'Archivo');

      expect(find.text(_reason), findsOneWidget);
      expect(_enabled(tester, 'Nora', 'Recuperar'), isTrue);
      expect(_enabled(tester, 'Nora', 'Eliminar'), isFalse);
      await tester.tap(_buttonFinder('Nora', 'Eliminar'), warnIfMissed: false);
      await settle(tester);
      expect(find.byType(ConfirmDialog), findsNothing);

      await tester.tap(find.bySemanticsLabel('Recuperar Nora'));
      await settle(tester);
      expect(find.text('Nora'), findsNothing);
      final state = await familyState(tester, phone);
      expect(state.view.recipients.map((r) => r.id), contains('nora'));
      expect(tester.takeException(), isNull);
    },
    size: _tall,
  );
}
