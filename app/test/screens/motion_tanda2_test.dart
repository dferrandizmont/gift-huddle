import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/model.dart';

import 'package:regalos/features/gifts/application/person_completion.dart';

import '../helpers/fake_haptics.dart';
import '../helpers/screens.dart';

/// Tanda 2 de movimiento en las pantallas: persona completa, borrar con
/// diálogo y el editor como tarjeta.
///
/// Hoy es el 9 de noviembre de 2026. En la muestra, Nora tiene dos regalos de
/// Navidad que no son ideas: «Cocinita» (envuelta) y «Puzle» (decidido). Al
/// comprar el puzle, queda completa.
const _puzle = 'Puzle de 48 piezas';
const _puzleLabel = 'Cambiar estado de $_puzle. Estado actual: Decidido';

final _ripple = find.byKey(const ValueKey('completion-ripple'));
final _seal = find.byKey(const ValueKey('completion-seal'));

Future<void> _openNora(WidgetTester tester) async {
  await tapText(tester, 'Nora');
}

/// Deja que se guarde (futuros reales) y avanza [ms] de reloj de la prueba.
Future<void> _afterSave(WidgetTester tester, int ms) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump();
  await tester.pump(Duration(milliseconds: ms));
}

void main() {
  final fake = FakeHaptics();
  setUp(fake.calls.clear);

  screenTest('al completar a una persona con la casilla, la celebración sale', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await _openNora(tester);
    expect(find.bySemanticsLabel(RegExp('1 de 2 comprados')), findsOneWidget);
    expect(_seal, findsNothing);

    await tester.tap(find.bySemanticsLabel(_puzleLabel));
    await tester.pump();
    await _afterSave(tester, 400);

    // En marcha: la onda del anillo, el sello y la háptica de logro.
    expect(_ripple, findsOneWidget);
    expect(_seal, findsOneWidget);
    // La casilla y, con el sello, el éxito (que anula la de la casilla).
    expect(fake.log, ['light+160', 'success+250']);
    expect(fake.calls.last.supersede, isTrue);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(_ripple, findsNothing);
    expect(_seal, findsOneWidget);
    expect(find.textContaining('Todo comprado para'), findsOneWidget);
  }, overrides: [fake.provide]);

  screenTest('si la completa un cambio que llega de fuera, no se celebra', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await _openNora(tester);

    // Sin pasar por la casilla ni el editor: llega como una sincronización.
    await tester.runAsync(
      () => familyOf(phone).setGiftStatus('g6', GiftStatus.bought),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_ripple, findsNothing);
    expect(fake.calls, isEmpty);

    // El sello aparece (con un fundido) y el subtítulo cambia.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(_ripple, findsNothing);
    expect(_seal, findsOneWidget);
    expect(find.textContaining('Todo comprado para'), findsOneWidget);
  }, overrides: [fake.provide]);

  screenTest('con «Reducir movimiento» no hay onda, pero sí sello y háptica', (
    tester,
    phone,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await _openNora(tester);

    await tester.tap(find.bySemanticsLabel(_puzleLabel));
    await tester.pump();
    await _afterSave(tester, 100);
    expect(_ripple, findsNothing);
    expect(fake.log, ['light+0', 'success+0']);

    await tester.pump(const Duration(milliseconds: 400));
    expect(_ripple, findsNothing);
    expect(_seal, findsOneWidget);
  }, overrides: [fake.provide]);

  screenTest('deshacer lo comprado quita el sello', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await _openNora(tester);

    await tester.tap(find.bySemanticsLabel(_puzleLabel));
    await tester.pump();
    await _afterSave(tester, 2000);
    await tester.pumpAndSettle();
    expect(_seal, findsOneWidget);

    await tapText(tester, 'Deshacer');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('1 de 2 comprados')), findsOneWidget);
    // El sello se va con su fundido y deja de pintarse.
    expect(_seal, findsNothing);
  });

  screenTest('Personas enseña el sello en la fila de quien está completo', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    // Aritz y Leo ya están completos; Nora no.
    final seals = tester.widgetList<AnimatedOpacity>(
      find.ancestor(
        of: find.byKey(const ValueKey('mini-seal')),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(seals.map((s) => s.opacity).toList()..sort(), [0.0, 1.0, 1.0]);
  });

  screenTest('borrar desde el editor pregunta y luego pliega la fila', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await tapText(tester, 'Aritz');
    await tapText(tester, 'Patinete');
    await tester.scrollUntilVisible(
      find.text('Borrar regalo'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
    await tapText(tester, 'Borrar regalo');
    expect(find.text('¿Borrar «Patinete»?'), findsOneWidget);

    // Confirmar: el dato se borra al momento, la tarjeta baja y la fila se
    // pliega (se quita de la lista cuando acaba).
    await tester.tap(find.text('Borrar').last);
    await _afterSave(tester, 120);
    expect(
      (await familyState(
        tester,
        phone,
      )).view.gifts.where((g) => g.title == 'Patinete'),
      isEmpty,
    );
    await tester.pumpAndSettle();
    expect(find.text('Patinete'), findsNothing);
    expect(find.text('Nuevo regalo'), findsNothing);
  }, size: const Size(390, 1500));

  screenTest('el editor sube como tarjeta y guardar la cierra', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await tapText(tester, 'Aritz');
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    // A mitad de la subida la tarjeta está más abajo que arriba del todo.
    final mid = tester.getTopLeft(find.text('Nuevo regalo')).dy;
    await tester.pump(const Duration(milliseconds: 600));
    final end = tester.getTopLeft(find.text('Nuevo regalo')).dy;
    expect(mid, greaterThan(end));
    await tester.enterText(
      find.widgetWithText(TextField, 'Regalo'),
      'Linterna',
    );
    await tapText(tester, 'Guardar');
    await tester.pumpAndSettle();
    expect(find.text('Nuevo regalo'), findsNothing);
    expect(find.text('Linterna'), findsOneWidget);
  }, size: const Size(390, 1500));

  screenTest('completa: las ideas no cuentan y decidido sigue pendiente', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    final read = phone.container.read;
    // Nora: el puzle (decidido) pendiente y la cocinita (envuelta) comprada.
    final nora = read(personCompletionProvider('nora'));
    expect(nora.bought, 1);
    expect(nora.total, 2);
    expect(nora.complete, isFalse);
    expect(nora.occasion?.id, 'seed-santa');
    // Aritz: el libro de Tió es solo una idea y no cuenta; queda el pijama
    // (llegó), así que está completo.
    final aritz = read(personCompletionProvider('aritz'));
    expect(aritz.total, 1);
    expect(aritz.complete, isTrue);
    expect(aritz.occasion?.id, 'seed-tio');
    // Sin regalos que no sean ideas no hay nada que completar.
    expect(read(personCompletionProvider('nadie')).complete, isFalse);
  });
}
