// La cabecera de la página de una persona (revisión del 26-11): al bajar por
// la lista la tarjeta de presupuesto, los filtros y el resumen se pliegan y
// queda el avatar con el nombre; al subir vuelven. Solo maquetación: nada
// cambia de comportamiento. El resumen de debajo del nombre se parte con el
// «·» siempre al final de línea, también con letra grande.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/layout/content_gutter.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/gifts/presentation/person_list_screen.dart';
import 'package:regalos/core/widgets/dot_line.dart';
import 'package:regalos/core/widgets/fold_box.dart';

import '../helpers/fonts.dart';
import '../helpers/memory_stores.dart' show FakePhone;
import '../helpers/screens.dart';
import '../widgets/dot_line_test.dart' show expectSeparatorsStayAtLineEnd;

Future<void> _openNoraWith(
  WidgetTester tester,
  FakePhone phone, {
  int extra = 12,
}) async {
  await seedSample(tester, phone);
  await tester.runAsync(() async {
    for (var i = 0; i < extra; i++) {
      await familyOf(phone).upsertGift(
        Gift(
          id: 'extra$i',
          recipientId: 'nora',
          title: 'Regalo de relleno $i',
          giverId: 'us',
          status: GiftStatus.idea,
          rawStatus: 'idea',
          plannedCents: 1000,
          surprise: false,
          year: 2026,
        ),
      );
    }
  });
  await pumpRegalos(tester, phone);
  await tester.ensureVisible(find.text('Nora').first);
  await tester.pump();
  await tapText(tester, 'Nora');
}

FoldBox _foldBox(WidgetTester tester) => tester.widget<FoldBox>(
  find.byWidgetPredicate((w) => w is FoldBox && w.key != null),
);

double _foldHeight(WidgetTester tester) =>
    tester.getSize(find.byKey(_foldBox(tester).key!)).height;

void main() {
  setUpAll(loadInter);

  screenTest('al bajar por la lista la cabecera se pliega y al subir vuelve', (
    tester,
    phone,
  ) async {
    await _openNoraWith(tester, phone);
    final box = _foldBox(tester);
    final open = _foldHeight(tester);
    expect(box.folded.value, 0);
    expect(open, greaterThan(100));
    expect(find.text('Filtros'), findsOneWidget);

    // Baja: se pliega (la tarjeta y los filtros dejan de verse).
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(box.folded.value, 1);
    expect(_foldHeight(tester), 0);
    // Plegada, no recibe toques ni lector de pantalla.
    expect(find.text('Filtros').hitTestable(), findsNothing);

    // Sube: vuelve.
    await tester.drag(find.byType(ListView).last, const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(box.folded.value, 0);
    expect(_foldHeight(tester), open);
    expect(tester.takeException(), isNull);
  });

  screenTest('el avatar y el nombre se quedan al plegarse', (
    tester,
    phone,
  ) async {
    await _openNoraWith(tester, phone);
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    // El nombre sigue en la cabecera, a la vista.
    expect(find.text('Nora').hitTestable(), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  screenTest('una lista que no se desplaza no se pliega', (
    tester,
    phone,
  ) async {
    await _openNoraWith(tester, phone, extra: 0);
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(_foldBox(tester).folded.value, 0);
  });

  screenTest(
    'con «Reducir movimiento» solo se funde: el alto nunca queda a medias',
    (tester, phone) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await _openNoraWith(tester, phone);
      final open = _foldHeight(tester);
      await tester.drag(find.byType(ListView).last, const Offset(0, -300));
      for (var ms = 0; ms < 200; ms += 25) {
        await tester.pump(const Duration(milliseconds: 25));
        final h = _foldHeight(tester);
        expect(h == open || h == 0, isTrue, reason: 'a los $ms ms: $h');
      }
      await tester.pumpAndSettle();
      expect(_foldBox(tester).folded.value, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final scale in [1.5, 2.0]) {
    screenTest(
      'el resumen de debajo del nombre se parte sin «·» al principio de '
      'línea con letra ×$scale',
      (tester, phone) async {
        await _openNoraWith(tester, phone, extra: 0);
        expect(find.byType(DotLine), findsWidgets);
        for (final text in tester.widgetList<Text>(
          find.descendant(
            of: find.byType(DotLine),
            matching: find.byType(Text),
          ),
        )) {
          expect((text.data ?? '').trimLeft().startsWith('·'), isFalse);
        }
        expectSeparatorsStayAtLineEnd(tester);
        expect(tester.takeException(), isNull);
      },
      textScale: scale,
    );
  }

  group('el «+» flotante', () {
    ContentFloatingButton fab(WidgetTester tester) => tester.widget(
      find.descendant(
        of: find.byType(PersonListScreen),
        matching: find.byType(ContentFloatingButton),
      ),
    );

    screenTest('se esconde al bajar, vuelve al subir y al llegar al final', (
      tester,
      phone,
    ) async {
      await _openNoraWith(tester, phone);
      expect(fab(tester).hidden, isFalse);
      await tester.drag(find.byType(ListView).last, const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(fab(tester).hidden, isTrue);
      await tester.drag(find.byType(ListView).last, const Offset(0, 60));
      await tester.pumpAndSettle();
      expect(fab(tester).hidden, isFalse);
      // Otra vez abajo y hasta el final: vuelve para poder pulsarlo.
      await tester.drag(find.byType(ListView).last, const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(fab(tester).hidden, isTrue);
      await tester.drag(find.byType(ListView).last, const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(fab(tester).hidden, isFalse);
      // Y arriba del todo.
      await tester.drag(find.byType(ListView).last, const Offset(0, -100));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).last, const Offset(0, 3000));
      await tester.pumpAndSettle();
      expect(fab(tester).hidden, isFalse);
      expect(tester.takeException(), isNull);
    });

    screenTest('una lista que no se desplaza no lo esconde', (
      tester,
      phone,
    ) async {
      await _openNoraWith(tester, phone, extra: 0);
      await tester.drag(find.byType(ListView).last, const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(fab(tester).hidden, isFalse);
    });

    screenTest('con navegación accesible no se esconde', (tester, phone) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await _openNoraWith(tester, phone);
      await tester.drag(find.byType(ListView).last, const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(fab(tester).hidden, isFalse);
    });

    screenTest('también en una tablet de un solo panel (800 de ancho)', (
      tester,
      phone,
    ) async {
      await _openNoraWith(tester, phone, extra: 20);
      await tester.drag(find.byType(ListView).last, const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(fab(tester).hidden, isTrue);
    }, size: const Size(800, 640));
  });

  screenTest('en tablet con dos paneles la cabecera no se pliega', (
    tester,
    phone,
  ) async {
    await _openNoraWith(tester, phone);
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(_foldBox(tester).folded.value, 0);
    expect(tester.takeException(), isNull);
  }, size: const Size(1280, 800));
}
