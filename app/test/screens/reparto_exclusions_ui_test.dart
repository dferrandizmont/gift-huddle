import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/reparto_view_provider.dart';
import 'package:regalos/features/family/presentation/family_screen.dart';
import 'package:regalos/features/family/presentation/reparto_grid.dart';
import 'package:regalos/features/family/presentation/reparto_occasion_view.dart';
import 'package:regalos/features/family/presentation/reparto_outside.dart';
import 'package:regalos/features/family/presentation/reparto_person_sheet.dart';
import 'package:regalos/features/family/presentation/reparto_sheet.dart';

import '../helpers/memory_stores.dart' show FakePhone;
import '../helpers/screens.dart';
import 'family_grid_test.dart' show expectNoRoundShapes, openFamily;

/// Excluir del reparto: la ficha de la persona, la franja gris de la ocasión
/// excluida, el bloque «Fuera del reparto» y la vista por ocasión.
void main() {
  const tall = Size(390, 1500);

  /// Las etiquetas que de verdad llegan al lector de pantalla.
  List<String> semanticLabels(WidgetTester tester) {
    final out = <String>[];
    void visit(SemanticsNode n) {
      out.add(n.label);
      n.visitChildren((c) {
        visit(c);
        return true;
      });
    }

    visit(tester.getSemantics(find.byType(MaterialApp).first));
    return out;
  }

  Future<void> openPersonSheet(WidgetTester tester, String name) async {
    await tester.tap(find.bySemanticsLabel('Abrir la ficha de $name').first);
    await settle(tester);
  }

  /// Cierra la hoja tocando el velo, arriba.
  Future<void> closeSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(195, 20));
    await settle(tester);
  }

  Future<Recipient> person(
    WidgetTester tester,
    FakePhone phone,
    String id,
  ) async {
    final state = await familyState(tester, phone);
    return state.view.recipientsById[id]!;
  }

  Future<void> run(WidgetTester tester, Future<void> Function() body) async {
    await tester.runAsync(body);
    await settle(tester);
  }

  screenTest(
    'tocar el nombre abre la ficha con «Sale en el reparto» y una casilla por '
    'ocasión; quitarlo manda a la persona a «Fuera del reparto» sin borrar nada',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openFamily(tester);
      expect(find.byType(RepartoGrid), findsOneWidget);
      expect(find.byKey(kRepartoOutsideToggleKey), findsNothing);
      final giftsBefore = (await familyState(tester, phone)).view.gifts.length;

      await openPersonSheet(tester, 'Aritz');
      expect(find.byKey(kRepartoSheetKey), findsOneWidget);
      expect(find.text('Sale en el reparto'), findsOneWidget);
      expect(find.text('Le regaláis en'), findsOneWidget);
      expect(find.byKey(repartoOccasionBoxKey('seed-kings')), findsOneWidget);
      expect(find.byKey(repartoOccasionBoxKey(kBirthdaysKey)), findsOneWidget);

      await tester.tap(find.byKey(kRepartoInRepartoKey));
      await settle(tester);
      expect((await person(tester, phone, 'aritz')).inReparto, isFalse);
      await closeSheet(tester);

      // Su fila ya no está y aparece el bloque, plegado.
      expect(find.bySemanticsLabel('Abrir la ficha de Aritz'), findsNothing);
      expect(find.text('Fuera del reparto · 1'), findsOneWidget);
      expect(find.byKey(repartoIncludeKey('aritz')), findsNothing);

      // Nada se borra: los regalos siguen en la lista.
      expect((await familyState(tester, phone)).view.gifts.length, giftsBefore);

      // Se despliega y vuelve a incluirla: la fila regresa y el bloque se va.
      await tester.tap(find.byKey(kRepartoOutsideToggleKey));
      await settle(tester);
      expect(find.byKey(repartoIncludeKey('aritz')), findsOneWidget);
      expect(find.text('Volver a incluir'), findsOneWidget);
      await tester.tap(find.byKey(repartoIncludeKey('aritz')));
      await settle(tester);
      expect((await person(tester, phone, 'aritz')).inReparto, isTrue);
      expect(find.bySemanticsLabel('Abrir la ficha de Aritz'), findsWidgets);
      expect(find.byKey(kRepartoOutsideToggleKey), findsNothing);
      expect(tester.takeException(), isNull);
    },
    size: tall,
  );

  screenTest(
    'una ocasión excluida es una franja gris lisa, no un hueco con «+»; en '
    '«Todas» la persona sigue y bajo su nombre pone «Sin Reyes»',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openFamily(tester);

      await openPersonSheet(tester, 'Aritz');
      await tester.tap(find.byKey(repartoOccasionBoxKey('seed-kings')));
      await settle(tester);
      expect(
        (await person(tester, phone, 'aritz')).skipsOccasion('seed-kings'),
        isTrue,
      );
      await closeSheet(tester);

      // «Todas»: sigue saliendo, con la nota bajo el nombre y sin franja.
      expect(find.text('Sin Reyes'), findsOneWidget);
      expect(find.bySemanticsLabel('No le regaláis en Reyes'), findsNothing);
      expect(find.bySemanticsLabel('Abrir la ficha de Aritz'), findsWidgets);

      // Con Reyes filtrado, la fila de Aritz es la franja.
      final reyes = find.descendant(
        of: find.byKey(kOccasionChipsKey),
        matching: find.text('Reyes'),
      );
      await tester.ensureVisible(reyes);
      await tester.tap(reyes);
      await settle(tester);
      expect(find.bySemanticsLabel('No le regaláis en Reyes'), findsOneWidget);
      expect(find.text('Sin Reyes'), findsNothing);
      // Es una franja: no hay celdas de Aritz que tocar ni «+» en su fila.
      expect(
        semanticLabels(tester).where((l) => l.contains('para Aritz')),
        isEmpty,
      );
      // Y la franja abre la ficha.
      await tester.tap(find.bySemanticsLabel('No le regaláis en Reyes'));
      await settle(tester);
      expect(find.byKey(kRepartoSheetKey), findsOneWidget);
      expect(find.text('Le regaláis en'), findsOneWidget);

      // Volver a marcar Reyes quita la franja.
      await tester.tap(find.byKey(repartoOccasionBoxKey('seed-kings')));
      await settle(tester);
      await closeSheet(tester);
      expect(find.bySemanticsLabel('No le regaláis en Reyes'), findsNothing);
      expect(find.text('Sin Reyes'), findsNothing);
      expect(tester.takeException(), isNull);
    },
    size: tall,
  );

  screenTest('en la vista por ocasión, quien se salta la ocasión no tiene tarjeta y sale '
      'aparte; quien está fuera del reparto no sale', (tester, phone) async {
    await seedSample(tester, phone);
    await run(tester, () async {
      await familyOf(phone)
          .setRecipientSkipOccasion('aritz', 'seed-kings', skip: true);
      await familyOf(phone).setRecipientInReparto('leo', false);
    });
    await phone.prefs!.setString(RepartoViewNotifier.prefsKey, 'occasion');
    await pumpRegalos(tester, phone);
    await openFamily(tester, all: false);
    expect(find.byType(RepartoOccasionView), findsOneWidget);

    final reyesTab = find.descendant(
      of: find.byKey(kRepartoOccasionTabsKey),
      matching: find.text('Reyes'),
    );
    await tester.ensureVisible(reyesTab);
    await tester.tap(reyesTab);
    await settle(tester);

    expect(find.text('No les regaláis en Reyes'), findsOneWidget);
    // Aritz sale solo en el grupo; Leo no sale en ningún sitio.
    expect(find.bySemanticsLabel('Abrir la ficha de Aritz'), findsOneWidget);
    expect(find.bySemanticsLabel('Abrir la ficha de Leo'), findsNothing);
    expect(find.bySemanticsLabel('Abrir la ficha de Nora'), findsOneWidget);

    // El chip abre su ficha.
    await tester.tap(find.bySemanticsLabel('Abrir la ficha de Aritz'));
    await settle(tester);
    expect(find.byKey(kRepartoSheetKey), findsOneWidget);
    expect(find.byKey(kRepartoInRepartoKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, size: tall);

  screenTest(
    '«Fuera del reparto»: avatar cuadrado de tamaño fijo y botón con radio 8 '
    'como máximo, nada de píldoras ni elipses',
    (tester, phone) async {
      await seedSample(tester, phone);
      await run(tester, () async {
        await familyOf(phone).setRecipientInReparto('aritz', false);
        await familyOf(phone).setRecipientInReparto('leo', false);
      });
      await pumpRegalos(tester, phone);
      await openFamily(tester);
      expect(find.text('Fuera del reparto · 2'), findsOneWidget);
      await tester.tap(find.byKey(kRepartoOutsideToggleKey));
      await settle(tester);

      final block = find.byType(OutsideBlock);
      expect(find.text('Volver a incluir'), findsNWidgets(2));
      for (final avatar in tester.widgetList<RepartoAvatar>(
        find.descendant(of: block, matching: find.byType(RepartoAvatar)),
      )) {
        final size = tester.getSize(find.byWidget(avatar));
        expect(size.width, size.height, reason: 'cuadrado, no elipse');
        expect(size.width, avatar.size);
      }
      expectNoRoundShapes(tester, block);
      // Los botones se tocan con 44 de alto.
      expect(
        tester.getSize(find.byKey(repartoIncludeKey('aritz'))).height,
        greaterThanOrEqualTo(44),
      );
      expect(tester.takeException(), isNull);
    },
    size: tall,
  );

  screenTest(
    'con «Reducir movimiento» excluir y volver a incluir solo funde y no '
    'rompe nada',
    (tester, phone) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openFamily(tester);

      await openPersonSheet(tester, 'Nora');
      await tester.tap(find.byKey(kRepartoInRepartoKey));
      await settle(tester);
      await closeSheet(tester);
      expect(find.text('Fuera del reparto · 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Abrir la ficha de Nora'), findsNothing);

      await tester.tap(find.byKey(kRepartoOutsideToggleKey));
      await settle(tester);
      await tester.tap(find.byKey(repartoIncludeKey('nora')));
      await settle(tester);
      expect(find.bySemanticsLabel('Abrir la ficha de Nora'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
    size: tall,
  );
}
