import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/theme/regalos_shape.dart';
import 'package:regalos/core/theme/regalos_tokens.dart';
import 'package:regalos/core/widgets/choice_grid.dart';
import 'package:regalos/core/widgets/danger_button.dart';

import '../helpers/fonts.dart';
import '../helpers/screens.dart';

/// Un móvil estrecho y alto: todo cabe sin desplazar.
const _narrow = Size(360, 1500);

/// El botón (de cualquier tipo) que lleva [text].
Finder _button(String text) => find.ancestor(
  of: find.text(text),
  matching: find.bySubtype<ButtonStyleButton>(),
);

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.text('Ajustes').last);
  await settle(tester);
}

void main() {
  setUpAll(loadInter);

  for (final (screen, add) in const [
    ('Personas', 'Añadir persona'),
    ('Quién regala', 'Añadir quién regala'),
    ('Ocasiones', 'Nueva ocasión'),
  ]) {
    screenTest('Ajustes › $screen: el botón de añadir ocupa todo el ancho', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openSettings(tester);
      await tapText(tester, screen);
      final rect = tester.getRect(_button(add));
      // Los mismos márgenes que la lista: 16 a cada lado.
      expect(rect.left, 16);
      expect(rect.width, _narrow.width - 32);
      expect(tester.takeException(), isNull);
    }, size: _narrow);
  }

  screenTest('editor de regalo: «Borrar regalo» es un botón rojo a todo el '
      'ancho, como «Guardar»', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await tapText(tester, 'Aritz');
    await tapText(tester, 'Patinete');

    final delete = find.byType(DangerButton);
    expect(delete, findsOneWidget);
    expect(
      find.descendant(of: delete, matching: find.text('Borrar regalo')),
      findsOneWidget,
    );
    final deleteRect = tester.getRect(_button('Borrar regalo'));
    final saveRect = tester.getRect(_button('Guardar'));
    expect(deleteRect.width, _narrow.width - 32);
    expect(deleteRect.width, saveRect.width);
    expect(deleteRect.left, saveRect.left);

    final tokens = RegalosTokens.of(tester.element(delete));
    final style = tester
        .widget<OutlinedButton>(_button('Borrar regalo'))
        .style!;
    expect(style.foregroundColor!.resolve({}), tokens.danger);
    expect(style.side!.resolve({})!.color, tokens.danger);
    expect(
      style.shape!.resolve({}),
      const RoundedRectangleBorder(borderRadius: RegalosShape.button),
    );
    // Sin relleno: la acción principal sigue siendo «Guardar».
    expect(style.backgroundColor, isNull);

    // Sigue preguntando antes de borrar.
    await tapText(tester, 'Borrar regalo');
    expect(find.text('¿Borrar «Patinete»?'), findsOneWidget);
    await tapText(tester, 'Cancelar');
    expect(find.text('¿Borrar «Patinete»?'), findsNothing);
    expect(find.byType(DangerButton), findsOneWidget);
  }, size: _narrow);

  screenTest('editor de regalo: los seis estados van en tres columnas '
      'iguales', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await tapText(tester, 'Aritz');
    await tapText(tester, 'Patinete');

    final cells = find.descendant(
      of: find.byType(ChoiceGrid),
      matching: find.byType(InkWell),
    );
    expect(cells, findsNWidgets(6));
    final rects = [
      for (final element in cells.evaluate())
        tester.getRect(find.byWidget(element.widget)),
    ];
    for (final rect in rects) {
      expect(rect.width, moreOrLessEquals((328 - 16) / 3, epsilon: 0.01));
      expect(rect.height, rects.first.height);
    }
    expect({for (final r in rects) r.top.round()}, hasLength(2));

    // Elegir otro estado lo marca y se guarda con el regalo.
    await tapLabel(tester, 'Envuelto');
    await tapText(tester, 'Guardar');
    final state = await familyState(tester, phone);
    expect(
      state.view.gifts.firstWhere((g) => g.title == 'Patinete').status.name,
      'wrapped',
    );
    expect(tester.takeException(), isNull);
  }, size: _narrow);
}
