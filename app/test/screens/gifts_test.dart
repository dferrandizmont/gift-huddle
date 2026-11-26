import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/model.dart';

import '../helpers/screens.dart';

Future<void> openAritz(WidgetTester tester) async {
  await tapText(tester, 'Aritz');
}

Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await settle(tester);
}

Future<Gift?> giftByTitle(
  WidgetTester tester,
  dynamic phone,
  String title,
) async {
  final state = await familyState(tester, phone);
  final found = state.view.gifts.where((g) => g.title == title);
  return found.isEmpty ? null : found.first;
}

void main() {
  const tall = Size(390, 1500);

  screenTest('el aviso de cambio de estado se va solo', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openAritz(tester);
    final box = find.bySemanticsLabel(RegExp(r'^Cambiar estado de '));
    await tester.tap(box.first);
    await settle(tester);
    expect(find.text('Deshacer'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    expect(find.text('Deshacer'), findsNothing);
  });

  screenTest('añadir un regalo y avanzar su estado, con deshacer y selector', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openAritz(tester);

    // Secciones por ocasión, con su fecha, y las etiquetas.
    expect(find.text('Tió'), findsOneWidget);
    expect(find.text('Reyes'), findsOneWidget);
    expect(find.text('24 dic'), findsOneWidget);
    expect(find.text('Sorpresa'), findsOneWidget);
    expect(find.text('Encargo'), findsOneWidget);
    expect(find.text('Lo pidió Aritz'), findsOneWidget);
    expect(find.text('Sin asignar'), findsOneWidget);
    // El importe y, debajo, lo previsto (el precio nunca se parte).
    expect(find.text(eur('49,99 €')), findsOneWidget);
    expect(find.text(eur('previsto 55 €')), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    expect(find.text('Nuevo regalo'), findsOneWidget);
    // Sin título no se guarda.
    await tapText(tester, 'Guardar');
    expect(find.text('Escribe qué regalo es.'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Regalo'),
      'Linterna frontal',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Previsto'), '12,50');
    await tapText(tester, 'Guardar');

    var gift = await giftByTitle(tester, phone, 'Linterna frontal');
    expect(gift, isNotNull);
    expect(gift!.recipientId, 'aritz');
    expect(gift.plannedCents, 1250);
    expect(gift.status, GiftStatus.idea);
    expect(gift.year, 2026);

    // Tocar la casilla avanza un estado y avisa.
    final label = 'Cambiar estado de Linterna frontal. Estado actual: Idea';
    await scrollTo(tester, find.text('Linterna frontal'));
    await tester.tap(find.bySemanticsLabel(label));
    await settle(tester);
    expect(find.text('Linterna frontal: Decidido'), findsOneWidget);
    gift = await giftByTitle(tester, phone, 'Linterna frontal');
    expect(gift!.status, GiftStatus.decided);

    // Deshacer lo devuelve.
    await tapText(tester, 'Deshacer');
    gift = await giftByTitle(tester, phone, 'Linterna frontal');
    expect(gift!.status, GiftStatus.idea);

    // Pulsación larga: el selector de los seis estados.
    await tester.longPress(find.bySemanticsLabel(label));
    await settle(tester);
    expect(find.text('Estado de Linterna frontal'), findsOneWidget);
    final sheet = find.byType(BottomSheet);
    for (final name in [
      'Idea',
      'Decidido',
      'Comprado',
      'Llegó',
      'Envuelto',
      'Entregado',
    ]) {
      expect(
        find.descendant(of: sheet, matching: find.text(name)),
        findsOneWidget,
      );
    }
    await tester.tap(
      find.descendant(of: sheet, matching: find.text('Envuelto')),
    );
    await settle(tester);
    gift = await giftByTitle(tester, phone, 'Linterna frontal');
    expect(gift!.status, GiftStatus.wrapped);

    // Envuelto avanza a entregado; un regalo entregado ya no avanza: abre el
    // selector.
    await tester.tap(
      find.bySemanticsLabel(
        'Cambiar estado de Linterna frontal. Estado actual: Envuelto',
      ),
    );
    await settle(tester);
    gift = await giftByTitle(tester, phone, 'Linterna frontal');
    expect(gift!.status, GiftStatus.delivered);
    await tester.tap(
      find.bySemanticsLabel(
        'Cambiar estado de Linterna frontal. Estado actual: Entregado',
      ),
    );
    await settle(tester);
    expect(find.text('Estado de Linterna frontal'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(find.text('Estado de Linterna frontal'), findsNothing);

    // Pulsación larga en el nombre (toda la fila): el mismo selector.
    await scrollTo(tester, find.text('Linterna frontal'));
    await tester.longPress(find.text('Linterna frontal'));
    await settle(tester);
    expect(find.text('Estado de Linterna frontal'), findsOneWidget);
  }, size: tall);

  screenTest('el editor guarda un encargo con una persona o con un nombre', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openAritz(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Regalo'), 'Cojín');
    await scrollTo(tester, find.text('Es un encargo: lo pidió alguien'));
    await tapText(tester, 'Es un encargo: lo pidió alguien');
    expect(find.text('Quién lo pidió'), findsOneWidget);
    // Por defecto, un nombre libre.
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre de quien lo pidió'),
      'Abuela Carme',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Nota del encargo'),
      'de color azul',
    );
    await scrollTo(tester, find.text('Es una sorpresa'));
    await tapText(tester, 'Es una sorpresa');
    await tapText(tester, 'Guardar');

    var gift = await giftByTitle(tester, phone, 'Cojín');
    expect(gift!.requestedBy, const RequestedByName('Abuela Carme'));
    expect(gift.requestNote, 'de color azul');
    expect(gift.surprise, isTrue);
    expect(find.text('Lo pidió Abuela Carme · de color azul'), findsOneWidget);

    // Se edita y se cambia a una persona de la lista.
    await scrollTo(tester, find.text('Cojín'));
    await tapText(tester, 'Cojín');
    expect(find.text('Editar regalo'), findsOneWidget);
    await scrollTo(tester, find.text('Quién lo pidió'));
    await tester.tap(find.text('Otra persona…'));
    await settle(tester);
    await tester.tap(find.text('Nora').last);
    await settle(tester);
    expect(
      find.widgetWithText(TextField, 'Nombre de quien lo pidió'),
      findsNothing,
    );
    await tapText(tester, 'Guardar');
    gift = await giftByTitle(tester, phone, 'Cojín');
    expect(gift!.requestedBy, const RequestedByRecipient('nora'));
  }, size: tall);

  screenTest('avisa de un posible duplicado al guardar', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await tapText(tester, 'Nora');
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Regalo'),
      'Puzle 48 piezas',
    );
    await tapText(tester, 'Guardar');
    expect(find.text('Posible duplicado'), findsOneWidget);
    expect(
      find.textContaining('Puede que este regalo ya esté en la lista'),
      findsOneWidget,
    );

    // Revisar vuelve al editor sin guardar.
    await tapText(tester, 'Revisar');
    expect(find.text('Nuevo regalo'), findsOneWidget);
    expect(await giftByTitle(tester, phone, 'Puzle 48 piezas'), isNull);

    // Guardar igualmente lo guarda.
    await tapText(tester, 'Guardar');
    await tapText(tester, 'Guardar igualmente');
    expect(await giftByTitle(tester, phone, 'Puzle 48 piezas'), isNotNull);
  }, size: tall);

  screenTest('borrar un regalo pide confirmación', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openAritz(tester);
    await tapText(tester, 'Patinete');
    await scrollTo(tester, find.text('Eliminar regalo'));
    await tapText(tester, 'Eliminar regalo');
    // Antes de borrar, siempre un diálogo; mientras está abierto no se ha
    // borrado nada.
    expect(find.text('¿Eliminar «Patinete»?'), findsOneWidget);
    expect(
      find.text('Se elimina también en los móviles de tu familia.'),
      findsOneWidget,
    );
    expect(await giftByTitle(tester, phone, 'Patinete'), isNotNull);

    await tapText(tester, 'Cancelar');
    expect(find.text('¿Eliminar «Patinete»?'), findsNothing);
    expect(await giftByTitle(tester, phone, 'Patinete'), isNotNull);

    await tapText(tester, 'Eliminar regalo');
    await tapText(tester, 'Eliminar');
    expect(await giftByTitle(tester, phone, 'Patinete'), isNull);
    // La fila se pliega después de confirmar y acaba quitándose.
    await tester.pumpAndSettle();
    expect(find.text('Patinete'), findsNothing);
  }, size: tall);

  screenTest('borrar un regalo: aviso con Deshacer y lápida al caducar', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openAritz(tester);
    await tapText(tester, 'Patinete');
    await scrollTo(tester, find.text('Eliminar regalo'));
    await tapText(tester, 'Eliminar regalo');
    await tapText(tester, 'Eliminar');
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('«Patinete» eliminado'), findsOneWidget);
    expect(find.text('Deshacer'), findsOneWidget);
    // Mientras el aviso está vivo la lápida no está escrita: el contenido
    // sigue en el documento y Deshacer lo devuelve.
    var state = await familyState(tester, phone);
    expect(state.hiddenGiftIds, {'g5'});
    expect(state.doc.record('gifts', 'g5')!.isDeleted, isFalse);
    expect(state.doc.record('gifts', 'g5')!['title'], 'Patinete');
    expect(await giftByTitle(tester, phone, 'Patinete'), isNull);
    expect(find.text('Patinete'), findsNothing);

    // Deshacer: el regalo vuelve tal cual, sin lápida.
    await tapText(tester, 'Deshacer');
    state = await familyState(tester, phone);
    expect(state.hiddenGiftIds, isEmpty);
    expect(await giftByTitle(tester, phone, 'Patinete'), isNotNull);
    expect(find.text('Patinete'), findsOneWidget);

    // Borrar otra vez y pasar la app a segundo plano: se escribe la lápida
    // y ya no hay Deshacer que valga.
    await tapText(tester, 'Patinete');
    await scrollTo(tester, find.text('Eliminar regalo'));
    await tapText(tester, 'Eliminar regalo');
    await tapText(tester, 'Eliminar');
    await flushDeletes(tester, phone);
    state = await familyState(tester, phone);
    expect(state.hiddenGiftIds, isEmpty);
    expect(state.doc.record('gifts', 'g5')!.isDeleted, isTrue);
    expect(state.doc.canonicalJson(), isNot(contains('Patinete')));
  }, size: tall);

  screenTest('los filtros: falta comprar, falta envolver y ocasión', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openAritz(tester);
    expect(find.text('Pijama de astronautas, talla 8'), findsOneWidget);

    await tapText(tester, 'Falta comprar');
    expect(find.text('Pijama de astronautas, talla 8'), findsNothing);
    expect(find.text('Estación de bomberos de bloques'), findsNothing);
    expect(find.text('Patinete'), findsOneWidget);
    expect(find.text('Bici de 20" con cambios'), findsOneWidget);

    await tapText(tester, 'Falta comprar');
    await tapText(tester, 'Falta envolver');
    expect(find.text('Pijama de astronautas, talla 8'), findsOneWidget);
    expect(find.text('Patinete'), findsNothing);
    await tapText(tester, 'Falta envolver');

    // Hoja de filtros: ocasión y quién regala.
    await tapText(tester, 'Filtros');
    expect(find.text('Filtrar regalos'), findsOneWidget);
    final sheet = find.byType(BottomSheet);
    await tester.tap(find.descendant(of: sheet, matching: find.text('Reyes')));
    await settle(tester);
    await tester.tap(
      find.descendant(of: sheet, matching: find.text('Nosotros')),
    );
    await settle(tester);
    await tapText(tester, 'Hecho');
    expect(find.bySemanticsLabel('Quitar filtro Reyes'), findsOneWidget);
    expect(find.text('Estación de bomberos de bloques'), findsOneWidget);
    expect(find.text('Patinete'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Quitar filtro Nosotros'));
    await settle(tester);
    expect(find.text('Patinete'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Quitar filtro Reyes'));
    await settle(tester);
    expect(find.text('Pijama de astronautas, talla 8'), findsOneWidget);
  }, size: tall);

  screenTest('la casilla de Leo pasa de comprado a llegó', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await tapText(tester, 'Leo');
    await tapLabel(tester, RegExp('Cambiar estado de Tren de madera'));
    // Leo tiene un regalo: ahora «Llegó».
    expect(find.text('Tren de madera: Llegó'), findsOneWidget);
    final state = await familyState(tester, phone);
    expect(state.view.gifts.where((g) => g.recipientId == 'leo').length, 1);
  }, size: tall);
}
