import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/family/application/self_recipient_provider.dart';
import 'package:regalos/features/family/presentation/reparto_flight.dart';
import 'package:regalos/features/family/presentation/reparto_grid.dart';
import 'package:regalos/features/family/presentation/reparto_occasion_view.dart';
import 'package:regalos/features/family/presentation/reparto_person_sheet.dart';
import 'package:regalos/features/family/presentation/self_tag.dart';

import '../helpers/memory_stores.dart' show FakePhone;
import '../helpers/screens.dart';
import 'family_grid_test.dart' show expectNoRoundShapes, openFamily;

/// «Yo» en Reparto: la persona dueña de este móvil lleva su etiqueta en la
/// rejilla, en la lista por ocasión y en su ficha, sin cambiar el orden ni el
/// vuelo entre vistas.
void main() {
  const tall = Size(390, 1500);
  const names = ['Aritz', 'Nora', 'Leo'];

  Future<void> chooseSelf(
    WidgetTester tester,
    FakePhone phone,
    String? id,
  ) async {
    await tester.runAsync(
      () => phone.container.read(selfRecipientIdProvider.notifier).choose(id),
    );
    await settle(tester);
  }

  /// El nombre de la persona [id] en su fila de la rejilla o en la cabecera
  /// de su tarjeta (el que viaja en el cambio de vista).
  Finder nameOf(String id) => find.descendant(
    of: find.byWidgetPredicate(
      (w) => w is RepartoAnchor && w.id == repartoNameAnchor(id),
    ),
    matching: find.byType(Text),
  );

  /// Las opacidades de los `FadeTransition` que envuelven la etiqueta.
  Iterable<double> tagFades(WidgetTester tester) => tester
      .widgetList<FadeTransition>(
        find.ancestor(
          of: find.byType(SelfTag),
          matching: find.byType(FadeTransition),
        ),
      )
      .map((f) => f.opacity.value);

  /// Si la etiqueta «Yo» espera oculta (su nombre aún no ha llegado).
  bool tagHidden(WidgetTester tester) => tagFades(tester).any((o) => o == 0);

  /// Si la etiqueta «Yo» se ve del todo.
  bool tagShown(WidgetTester tester) => tagFades(tester).every((o) => o == 1);

  List<String> order(WidgetTester tester) => [...names]
    ..sort(
      (a, b) => tester
          .getTopLeft(find.text(a).first)
          .dy
          .compareTo(tester.getTopLeft(find.text(b).first).dy),
    );

  screenTest('sin elegir de quién es el móvil no hay ninguna etiqueta', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openFamily(tester);
    expect(find.byType(RepartoGrid), findsOneWidget);
    expect(find.byType(SelfTag), findsNothing);
    await tester.tap(find.bySemanticsLabel('Por ocasión'));
    await settle(tester);
    expect(find.byType(RepartoOccasionView), findsOneWidget);
    expect(find.byType(SelfTag), findsNothing);
    expect(tester.takeException(), isNull);
  }, size: tall);

  screenTest('la rejilla marca a la persona de este móvil con «Yo» a la '
      'derecha de su nombre si cabe, sin mover el nombre ni cambiar el '
      'orden', (tester, phone) async {
    await seedSample(tester, phone);
    // Con dos columnas hay sitio de sobra junto al nombre.
    await tester.runAsync(() async {
      for (final id in ['avis', 'marta', 'pere', 'anna']) {
        await familyOf(phone).archiveGiver(id);
      }
    });
    await pumpRegalos(tester, phone);
    await openFamily(tester);
    final before = order(tester);
    final nameAt = tester.getRect(nameOf('nora'));

    await chooseSelf(tester, phone, 'nora');
    expect(find.byType(SelfTag), findsOneWidget);
    expect(
      find.descendant(of: find.byType(SelfTag), matching: find.text('Yo')),
      findsOneWidget,
    );
    // El nombre sigue exactamente donde estaba y las filas, en su orden.
    final name = tester.getRect(nameOf('nora'));
    expect(name, nameAt);
    expect(order(tester), before);
    // La etiqueta, a su derecha y en su línea.
    final tag = tester.getRect(find.byType(SelfTag));
    expect(tag.left, greaterThan(name.right));
    expect(tag.left, lessThan(name.right + 10));
    expect(tag.center.dy, closeTo(name.center.dy, 3));
    // El lector de pantalla también lo dice.
    expect(find.bySemanticsLabel('Abrir la ficha de Nora (yo)'), findsWidgets);
    expect(find.bySemanticsLabel('Abrir la ficha de Aritz'), findsWidgets);
    expect(find.bySemanticsLabel('Abrir la ficha de Nora'), findsNothing);
    expectNoRoundShapes(tester, find.byType(RepartoGrid));
    expect(tester.takeException(), isNull);

    // Al quitar la elección, la etiqueta se va.
    await chooseSelf(tester, phone, null);
    expect(find.byType(SelfTag), findsNothing);
    expect(tester.getRect(nameOf('nora')), nameAt);
  }, size: tall);

  screenTest('con la rejilla estrecha (seis columnas) la etiqueta baja bajo el '
      'nombre, como «Sin Navidad», y nada se desborda', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openFamily(tester);
    final before = order(tester);
    final nameAt = tester.getRect(nameOf('nora'));
    final others = [
      tester.getRect(nameOf('aritz')),
      tester.getRect(nameOf('leo')),
    ];

    await chooseSelf(tester, phone, 'nora');
    expect(find.byType(SelfTag), findsOneWidget);
    final name = tester.getRect(nameOf('nora'));
    final tag = tester.getRect(find.byType(SelfTag));
    // El nombre no se mueve de lado ni cambia de tamaño; como mucho sube unos
    // píxeles para dejar sitio a la línea de debajo.
    expect(name.left, nameAt.left);
    expect(name.size, nameAt.size);
    expect((name.top - nameAt.top).abs(), lessThan(12));
    // La etiqueta, pegada al nombre: a su derecha o justo debajo.
    expect(tag.left, greaterThanOrEqualTo(name.left));
    expect(tag.top, lessThan(name.bottom + 6));
    expect(tag.bottom, greaterThan(name.top));
    // Las demás filas no se mueven y el orden es el mismo.
    expect(order(tester), before);
    expect([
      tester.getRect(nameOf('aritz')),
      tester.getRect(nameOf('leo')),
    ], others);
    expect(tester.takeException(), isNull);
  }, size: tall);

  screenTest('la lista por ocasión y la ficha de la persona también llevan '
      '«Yo»; la ficha de otra persona, no', (tester, phone) async {
    await seedSample(tester, phone);
    await chooseSelf(tester, phone, 'aritz');
    await pumpRegalos(tester, phone);
    await openFamily(tester, all: false);
    await tester.tap(find.bySemanticsLabel('Por ocasión'));
    await settle(tester);
    expect(find.byType(RepartoOccasionView), findsOneWidget);
    expect(find.byType(SelfTag), findsOneWidget);
    // En la cabecera de su tarjeta, a la derecha del nombre y en su línea.
    final name = tester.getRect(nameOf('aritz'));
    final tag = tester.getRect(find.byType(SelfTag));
    expect(tag.left, greaterThan(name.right));
    expect(tag.left, lessThan(name.right + 10));
    expect(tag.center.dy, closeTo(name.center.dy, 4));
    expect(tester.takeException(), isNull);

    // Su ficha.
    await tester.tap(
      find.bySemanticsLabel('Abrir la ficha de Aritz (yo)').first,
    );
    await settle(tester);
    expect(find.byType(RepartoPersonSheet), findsOneWidget);
    final inSheet = find.descendant(
      of: find.byType(RepartoPersonSheet),
      matching: find.byType(SelfTag),
    );
    expect(inSheet, findsOneWidget);
    final sheetName = tester.getRect(
      find.descendant(
        of: find.byType(RepartoPersonSheet),
        matching: find.text('Aritz'),
      ),
    );
    expect(tester.getRect(inSheet).left, greaterThan(sheetName.right));
    expect(tester.getRect(inSheet).center.dy, closeTo(sheetName.center.dy, 4));
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(195, 20));
    await settle(tester);

    // La de Nora no la lleva.
    await tester.tap(find.bySemanticsLabel('Abrir la ficha de Nora').first);
    await settle(tester);
    expect(find.byType(RepartoPersonSheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(RepartoPersonSheet),
        matching: find.byType(SelfTag),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  }, size: tall);

  screenTest('en una tarjeta con poco sitio la etiqueta baja bajo el nombre y '
      'nada se desborda', (tester, phone) async {
    await seedSample(tester, phone);
    // Nora no tiene regalos en la primera ocasión: su cabecera lleva además
    // «Nada en…» y el botón de añadir.
    await chooseSelf(tester, phone, 'nora');
    await pumpRegalos(tester, phone);
    await openFamily(tester, all: false);
    await tester.tap(find.bySemanticsLabel('Por ocasión'));
    await settle(tester);
    expect(find.byType(SelfTag), findsOneWidget);
    final name = tester.getRect(nameOf('nora'));
    final tag = tester.getRect(find.byType(SelfTag));
    expect(tag.left, greaterThanOrEqualTo(name.left));
    expect(tag.top, lessThan(name.bottom + 6));
    expect(tester.takeException(), isNull);
  }, size: tall);

  screenTest('en el cambio de vista la etiqueta no salta: espera oculta a que '
      'aterrice su nombre y se funde, a la ida y a la vuelta', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await chooseSelf(tester, phone, 'aritz');
    await pumpRegalos(tester, phone);
    await openFamily(tester, all: false);
    final inGrid = find.text('Aritz').evaluate().length;
    final gridTag = tester.getRect(find.byType(SelfTag));
    final gridName = tester.getRect(nameOf('aritz'));
    expect(tagShown(tester), isTrue);

    Future<void> midFlight() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 300));
    }

    // Ida: el nombre viaja como siempre (uno más en pantalla) y la etiqueta
    // de la tarjeta espera oculta, ya en su sitio.
    await tester.tap(find.bySemanticsLabel('Por ocasión'));
    await midFlight();
    expect(find.byKey(kRepartoFlightKey), findsOneWidget);
    expect(tagHidden(tester), isTrue);
    await settle(tester);
    expect(find.byKey(kRepartoFlightKey), findsNothing);
    expect(find.byType(SelfTag), findsOneWidget);
    expect(tagShown(tester), isTrue);
    final settled = find.text('Aritz').evaluate().length;
    final cardTag = tester.getRect(find.byType(SelfTag));
    final cardName = tester.getRect(nameOf('aritz'));
    expect(tester.takeException(), isNull);

    // Vuelta: igual, y nombre y etiqueta acaban donde estaban en la rejilla.
    await tester.tap(find.bySemanticsLabel('Rejilla'));
    await midFlight();
    expect(find.byKey(kRepartoFlightKey), findsOneWidget);
    expect(find.text('Aritz').evaluate().length, inGrid + 1);
    expect(tagHidden(tester), isTrue);
    await settle(tester);
    expect(find.text('Aritz').evaluate().length, inGrid);
    expect(find.byType(SelfTag), findsOneWidget);
    expect(tagShown(tester), isTrue);
    expect(tester.getRect(find.byType(SelfTag)), gridTag);
    expect(tester.getRect(nameOf('aritz')), gridName);
    expect(tester.takeException(), isNull);

    // Y otra vez a la lista: vuelven al mismo sitio de la tarjeta.
    await tester.tap(find.bySemanticsLabel('Por ocasión'));
    await settle(tester);
    expect(find.text('Aritz').evaluate().length, settled);
    expect(tester.getRect(find.byType(SelfTag)), cardTag);
    expect(tester.getRect(nameOf('aritz')), cardName);
    expect(tester.takeException(), isNull);
  }, size: tall);

  screenTest('con «Reducir movimiento» las vistas se funden y la etiqueta '
      'llega con su vista, sin esperar a ningún vuelo', (tester, phone) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await seedSample(tester, phone);
    await chooseSelf(tester, phone, 'aritz');
    await pumpRegalos(tester, phone);
    await openFamily(tester, all: false);
    await tester.tap(find.bySemanticsLabel('Por ocasión'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byKey(kRepartoFlightKey), findsNothing);
    expect(tagHidden(tester), isFalse);
    await settle(tester);
    expect(find.byType(SelfTag), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, size: tall);

  screenTest(
    'con la letra grande y en catalán la etiqueta sigue cabiendo',
    (tester, phone) async {
      tester.platformDispatcher.localesTestValue = const [Locale('ca', 'ES')];
      tester.platformDispatcher.localeTestValue = const Locale('ca', 'ES');
      await seedSample(tester, phone);
      await chooseSelf(tester, phone, 'aritz');
      await pumpRegalos(tester, phone);
      await tester.tap(find.text('Repartiment').last);
      await settle(tester);
      expect(find.byType(SelfTag), findsOneWidget);
      expect(
        find.descendant(of: find.byType(SelfTag), matching: find.text('Jo')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      // Su ficha, también.
      await tester.tap(
        find.bySemanticsLabel('Obre la fitxa de Aritz (jo)').first,
      );
      await settle(tester);
      expect(
        find.descendant(
          of: find.byType(RepartoPersonSheet),
          matching: find.byType(SelfTag),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    size: tall,
    textScale: 1.3,
  );
}
