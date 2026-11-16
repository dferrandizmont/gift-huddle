import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/widgets/filter_pill.dart';
import 'package:regalos/features/family/presentation/family_screen.dart';
import 'package:regalos/features/family/presentation/reparto_flight.dart';

import '../helpers/screens.dart';

/// El filtro de ocasión de Reparto arranca en «Todas» y la columna de nombres
/// y avatares de la rejilla entra y se refresca con animación.
void main() {
  const tall = Size(390, 1500);

  bool selected(WidgetTester tester, String label) => tester
      .widget<FilterPill>(
        find.descendant(
          of: find.byKey(kOccasionChipsKey),
          matching: find.widgetWithText(FilterPill, label),
        ),
      )
      .selected;

  Future<void> pick(WidgetTester tester, String label) async {
    final chip = find.descendant(
      of: find.byKey(kOccasionChipsKey),
      matching: find.widgetWithText(FilterPill, label),
    );
    await tester.ensureVisible(chip);
    await tester.pump();
    await tester.tap(chip);
  }

  /// La opacidad más baja de las que envuelven el texto [name].
  double lowestOpacity(WidgetTester tester, String name) {
    var lowest = 1.0;
    for (final o in tester.widgetList<Opacity>(
      find.ancestor(of: find.text(name), matching: find.byType(Opacity)),
    )) {
      if (o.opacity < lowest) {
        lowest = o.opacity;
      }
    }
    return lowest;
  }

  group('filtro de ocasión por defecto', () {
    screenTest('con una lista nueva sale «Todas»', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.tap(find.text('Reparto').last);
      await settle(tester);
      expect(selected(tester, 'Todas'), isTrue);
      expect(selected(tester, 'Tió'), isFalse);
      expect(find.text('Todas las ocasiones'), findsOneWidget);
    }, size: tall);

    screenTest('con un cumpleaños como ocasión más cercana sigue en «Todas»', (
      tester,
      phone,
    ) async {
      // El 10 de marzo, lo más cercano es el cumpleaños de Aritz (14 de marzo).
      await withClock(Clock.fixed(DateTime(2027, 3, 10, 10)), () async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tester.tap(find.text('Reparto').last);
        await settle(tester);
        expect(selected(tester, 'Todas'), isTrue);
        expect(selected(tester, 'Cumpleaños'), isFalse);
        expect(find.text('Para los cumpleaños'), findsNothing);
        expect(find.text('Todas las ocasiones'), findsOneWidget);
      });
    }, size: tall);

    screenTest('lo que se elige se recuerda al ir a la lista y volver, pero '
        'ir y volver sin elegir no cambia «Todas»', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.tap(find.text('Reparto').last);
      await settle(tester);

      // Sin elegir: ir a la lista por ocasión y volver deja «Todas».
      await tester.tap(find.bySemanticsLabel('Por ocasión'));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Rejilla'));
      await settle(tester);
      expect(selected(tester, 'Todas'), isTrue);

      // Eligiendo Reyes, la ocasión se mantiene al volver.
      await pick(tester, 'Reyes');
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Por ocasión'));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Rejilla'));
      await settle(tester);
      expect(selected(tester, 'Reyes'), isTrue);
    }, size: tall);
  });

  group('los nombres de «Recibe» entran con animación', () {
    screenTest('al entrar en la pantalla, nombre y avatar suben escalonados y '
        'se asientan', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.tap(find.text('Reparto').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byType(RepartoRowIntro), findsWidgets);
      // A los 60 ms, la primera fila aún no ha terminado de aparecer y las
      // siguientes, con su retraso, menos todavía.
      expect(lowestOpacity(tester, 'Nora'), lessThan(1));
      expect(lowestOpacity(tester, 'Leo'), lessThan(1));
      final during = tester.getTopLeft(find.text('Leo')).dy;

      await settle(tester);
      expect(lowestOpacity(tester, 'Aritz'), 1);
      expect(lowestOpacity(tester, 'Leo'), 1);
      final after = tester.getTopLeft(find.text('Leo')).dy;
      expect(during, greaterThan(after), reason: 'sube mientras entra');
      expect(tester.takeException(), isNull);
    }, size: tall);

    screenTest('con «Reducir movimiento» solo se funde, sin mover el nombre', (
      tester,
      phone,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.tap(find.text('Reparto').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(lowestOpacity(tester, 'Leo'), lessThan(1));
      final during = tester.getTopLeft(find.text('Leo')).dy;
      // Dura 150 ms: a los 200 ms ya está entero.
      await tester.pump(const Duration(milliseconds: 200));
      expect(lowestOpacity(tester, 'Leo'), 1);
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.getTopLeft(find.text('Leo')).dy, during);
      expect(tester.takeException(), isNull);
    }, size: tall);

    screenTest('al cambiar de ocasión en el filtro, los nombres se refrescan '
        'con el mismo muelle que las celdas', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.tap(find.text('Reparto').last);
      await settle(tester);
      expect(lowestOpacity(tester, 'Leo'), 1);

      await pick(tester, 'Reyes');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(lowestOpacity(tester, 'Leo'), lessThan(1));
      await settle(tester);
      expect(lowestOpacity(tester, 'Leo'), 1);
      expect(find.text('Leo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, size: tall);

    screenTest('al volver de la lista por ocasión no hay un fotograma quieto: '
        'nada de la fila se ve antes de que llegue su nombre', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.tap(find.text('Reparto').last);
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Por ocasión'));
      await settle(tester);

      await tester.tap(find.bySemanticsLabel('Rejilla'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      // A mitad de camino, el nombre de la rejilla espera oculto y el que
      // viaja ocupa su sitio: nunca hay un nombre de la rejilla a medias.
      final hidden = tester
          .widgetList<FadeTransition>(
            find.ancestor(
              of: find.text('Nora'),
              matching: find.byType(FadeTransition),
            ),
          )
          .where((f) => f.opacity.value == 0);
      expect(hidden, isNotEmpty);
      await settle(tester);
      expect(lowestOpacity(tester, 'Nora'), 1);
      expect(find.text('Nora'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, size: tall);
  });
}
