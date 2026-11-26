import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/widgets/more_details.dart';
import 'package:regalos/core/widgets/sheet_frame.dart' show SwitchRow;
import 'package:regalos/features/gifts/presentation/gift_editor_screen.dart';

import '../helpers/memory_stores.dart';
import '../helpers/screens.dart';

// El editor de regalos deja a la vista lo esencial (regalo, para quién, quién
// regala, ocasión, estado y precio previsto, más encargo y sorpresa) y pliega
// lo opcional (precio real, tienda, enlace, talla y nota) en «Más detalles».

final _editor = find.byType(GiftEditorScreen);
final _more = find.byType(MoreDetails);
const _question = '¿Descartar los cambios?';

Finder _field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

bool _isOpen(WidgetTester tester) => tester.widget<MoreDetails>(_more).open;

Gift _gift(
  String id,
  String title, {
  String? store,
  String? url,
  String? note,
  String? size,
  int? actualCents,
}) => Gift(
  id: id,
  recipientId: 'aritz',
  title: title,
  status: GiftStatus.idea,
  rawStatus: 'idea',
  store: store,
  url: url,
  note: note,
  size: size,
  actualCents: actualCents,
  surprise: false,
  year: 2026,
);

Future<void> _seed(WidgetTester tester, FakePhone phone) async {
  await seedSample(tester, phone);
  await tester.runAsync(() async {
    final c = familyOf(phone);
    await c.upsertGift(_gift('mdl', 'Peonza lisa'));
    await c.upsertGift(_gift('mds', 'Cometa con tienda', store: 'Decathlon'));
    await c.upsertGift(
      _gift('mdn', 'Puzle con nota', note: 'Envolver en azul'),
    );
    await c.upsertGift(_gift('mdp', 'Patines con precio', actualCents: 2490));
  });
  await pumpRegalos(tester, phone);
}

Future<void> _newGift(WidgetTester tester, FakePhone phone) async {
  await _seed(tester, phone);
  await tester.tap(find.widgetWithText(FloatingActionButton, 'Añadir regalo'));
  await settle(tester);
  expect(find.text('Nuevo regalo'), findsOneWidget);
  await tester.tap(find.bySemanticsLabel(RegExp(r'^Para quién')).first);
  await settle(tester);
  await tester.tap(
    find.descendant(of: find.byType(BottomSheet), matching: find.text('Aritz')),
  );
  await settle(tester);
}

Future<void> _edit(WidgetTester tester, FakePhone phone, String title) async {
  await _seed(tester, phone);
  await tapText(tester, 'Aritz');
  await tapText(tester, title);
  expect(find.text('Editar regalo'), findsOneWidget);
}

Future<List<Gift>> _gifts(WidgetTester tester, FakePhone phone) async =>
    (await familyState(tester, phone)).view.gifts;

/// Una prueba con la pantalla muy alta: la lista del editor lleva todo montado
/// y no hace falta desplazarla para llegar a cada campo.
void _tall(
  String description,
  Future<void> Function(WidgetTester tester, FakePhone phone) body,
) => screenTest(description, body, size: const Size(390, 2600));

/// Como [_tall], con la plataforma en iOS (el gesto de borde solo existe ahí).
void _ios(
  String description,
  Future<void> Function(WidgetTester tester, FakePhone phone) body,
) => _tall(description, (tester, phone) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  try {
    await body(tester, phone);
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
});

void main() {
  group('un regalo nuevo', () {
    _tall('lo esencial a la vista y lo opcional plegado', (
      tester,
      phone,
    ) async {
      await _newGift(tester, phone);
      for (final label in ['Regalo', 'Previsto']) {
        expect(_field(label), findsOneWidget, reason: label);
      }
      for (final label in ['Para quién', 'Quién regala', 'Ocasión']) {
        expect(
          find.bySemanticsLabel(RegExp('^$label')),
          findsWidgets,
          reason: label,
        );
      }
      expect(find.text('Estado'), findsOneWidget);
      // Encargo y sorpresa siguen a la vista: cambian cómo se enseña.
      expect(find.byType(SwitchRow), findsNWidgets(2));
      // Lo opcional, plegado.
      expect(find.text('Más detalles'), findsOneWidget);
      expect(_isOpen(tester), isFalse);
      for (final label in [
        'Precio real',
        'Tienda',
        'Enlace',
        'Talla o edad',
        'Nota',
      ]) {
        expect(_field(label), findsNothing, reason: label);
      }
      expect(tester.takeException(), isNull);
    });

    _tall('«Más detalles» se despliega animada y se pliega al volver '
        'a tocarla, sin perder lo escrito', (tester, phone) async {
      await _newGift(tester, phone);
      await tester.ensureVisible(find.text('Más detalles'));
      await tester.pump();
      final closed = tester.getSize(_more).height;
      await tester.tap(find.text('Más detalles'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      final mid = tester.getSize(_more).height;
      expect(mid, greaterThan(closed), reason: 'ya ha empezado a abrirse');
      await settle(tester);
      final open = tester.getSize(_more).height;
      expect(open, greaterThan(mid), reason: 'no salta: crece por el camino');
      expect(_isOpen(tester), isTrue);
      for (final label in [
        'Precio real',
        'Tienda',
        'Enlace',
        'Talla o edad',
        'Nota',
      ]) {
        expect(_field(label), findsOneWidget, reason: label);
      }
      await tester.ensureVisible(_field('Talla o edad'));
      await tester.enterText(_field('Talla o edad'), '8 años');
      await tester.enterText(_field('Enlace'), 'https://www.ikea.com/es/');
      await tester.pump();
      // Plegada, los campos ya no están ni los lee el lector de pantalla, y
      // la fila dice qué hay dentro.
      await tester.ensureVisible(find.text('Más detalles'));
      await tester.tap(find.text('Más detalles'));
      await settle(tester);
      expect(_isOpen(tester), isFalse);
      expect(_field('Talla o edad'), findsNothing);
      expect(find.text('Tienda · Enlace · Talla o edad'), findsOneWidget);
      expect(tester.getSize(_more).height, lessThan(open));
      // Abierta otra vez, lo escrito sigue ahí.
      await tester.tap(find.text('Más detalles'));
      await settle(tester);
      expect(
        tester.widget<TextField>(_field('Talla o edad')).controller!.text,
        '8 años',
      );
    });

    _tall('la fila es un botón con su estado para el lector de pantalla', (
      tester,
      phone,
    ) async {
      await _newGift(tester, phone);
      await tester.ensureVisible(find.text('Más detalles'));
      await tester.pump();
      Finder row() => find.bySemanticsLabel('Más detalles');
      expect(
        tester.getSemantics(row().first),
        isSemantics(
          isButton: true,
          hasTapAction: true,
          hasExpandedState: true,
          isExpanded: false,
        ),
      );
      await tester.tap(find.text('Más detalles'));
      await settle(tester);
      expect(
        tester.getSemantics(row().first),
        isSemantics(
          isButton: true,
          hasExpandedState: true,
          isExpanded: true,
        ),
      );
    });

    _tall('con movimiento reducido no salta de altura: se funde', (
      tester,
      phone,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await _newGift(tester, phone);
      await tester.ensureVisible(find.text('Más detalles'));
      await tester.pump();
      await tester.tap(find.text('Más detalles'));
      await settle(tester);
      expect(_isOpen(tester), isTrue);
      expect(_field('Enlace'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    _tall('guarda igual que antes: lo de dentro de «Más detalles» llega '
        'al regalo', (tester, phone) async {
      await _newGift(tester, phone);
      await tester.enterText(_field('Regalo'), 'Telescopio');
      await tester.enterText(_field('Previsto'), '30');
      await tester.ensureVisible(find.text('Más detalles'));
      await tester.tap(find.text('Más detalles'));
      await settle(tester);
      await tester.ensureVisible(_field('Precio real'));
      await tester.enterText(_field('Precio real'), '27,50');
      await tester.enterText(_field('Tienda'), 'Sol');
      await tester.enterText(_field('Enlace'), 'https://sol.example/p');
      await tester.enterText(_field('Talla o edad'), '8');
      await tester.enterText(_field('Nota'), 'En la caja grande');
      await tapText(tester, 'Guardar');
      expect(_editor, findsNothing);
      final saved = (await _gifts(
        tester,
        phone,
      )).firstWhere((g) => g.title == 'Telescopio');
      expect(saved.plannedCents, 3000);
      expect(saved.actualCents, 2750);
      expect(saved.store, 'Sol');
      expect(saved.url, 'https://sol.example/p');
      expect(saved.size, '8');
      expect(saved.note, 'En la caja grande');
    });

    _tall('sin abrir «Más detalles» también guarda, y sin título pide '
        'el título', (tester, phone) async {
      await _newGift(tester, phone);
      await tapText(tester, 'Guardar');
      expect(_editor, findsOneWidget);
      expect(find.text('Escribe qué regalo es.'), findsOneWidget);
      await tester.enterText(_field('Regalo'), 'Peluche');
      await tapText(tester, 'Guardar');
      expect(_editor, findsNothing);
      expect(
        (await _gifts(tester, phone)).where((g) => g.title == 'Peluche'),
        hasLength(1),
      );
    });

    _tall('un precio real que no vale abre «Más detalles» sola al '
        'guardar', (tester, phone) async {
      await _newGift(tester, phone);
      await tester.enterText(_field('Regalo'), 'Coche');
      await tester.ensureVisible(find.text('Más detalles'));
      await tester.tap(find.text('Más detalles'));
      await settle(tester);
      await tester.ensureVisible(_field('Precio real'));
      await tester.enterText(_field('Precio real'), '12 € 50 €');
      await tester.ensureVisible(find.text('Más detalles'));
      await tester.tap(find.text('Más detalles'));
      await settle(tester);
      expect(_isOpen(tester), isFalse);
      await tapText(tester, 'Guardar');
      expect(_editor, findsOneWidget);
      expect(_isOpen(tester), isTrue);
      expect(
        find.text('Escribe un importe, por ejemplo 12,50.'),
        findsOneWidget,
      );
    });
  });

  group('un regalo que se edita', () {
    _tall('sin datos opcionales, «Más detalles» sale plegada', (
      tester,
      phone,
    ) async {
      await _edit(tester, phone, 'Peonza lisa');
      expect(_isOpen(tester), isFalse);
      expect(_field('Tienda'), findsNothing);
    });

    for (final (title, label, value) in [
      ('Cometa con tienda', 'Tienda', 'Decathlon'),
      ('Puzle con nota', 'Nota', 'Envolver en azul'),
      ('Patines con precio', 'Precio real', '24,90'),
    ]) {
      _tall('con «$label» ya escrito, se abre sola', (tester, phone) async {
        await _edit(tester, phone, title);
        expect(_isOpen(tester), isTrue);
        expect(tester.widget<TextField>(_field(label)).controller!.text, value);
      });
    }

    _tall('abierta sola, guardar sin tocar nada no cambia el regalo y '
        'no pregunta al cerrar', (tester, phone) async {
      await _edit(tester, phone, 'Cometa con tienda');
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text(_question), findsNothing);
      expect(_editor, findsNothing);
    });

    _tall('plegar y abrir no cuenta como cambio', (tester, phone) async {
      await _edit(tester, phone, 'Peonza lisa');
      await tester.ensureVisible(find.text('Más detalles'));
      await tester.tap(find.text('Más detalles'));
      await settle(tester);
      await tester.ensureVisible(find.text('Más detalles'));
      await tester.tap(find.text('Más detalles'));
      await settle(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text(_question), findsNothing);
      expect(_editor, findsNothing);
    });
  });

  group('volver con cambios sin guardar', () {
    Future<void> swipe(WidgetTester tester) async {
      final gesture = await tester.startGesture(const Offset(3, 420));
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(80, 0));
      await gesture.up();
      await settle(tester);
    }

    _ios('el gesto de borde de iOS pregunta si hay cambios; seguir '
        'editando conserva lo escrito', (tester, phone) async {
      await _edit(tester, phone, 'Peonza lisa');
      await tester.enterText(_field('Regalo'), 'Otro título');
      await swipe(tester);
      expect(find.text(_question), findsOneWidget);
      await tester.tap(find.text('Seguir editando'));
      await settle(tester);
      expect(_editor, findsOneWidget);
      expect(find.text('Otro título'), findsOneWidget);
      await swipe(tester);
      await tester.tap(find.text('Descartar'));
      await settle(tester);
      expect(_editor, findsNothing);
      expect(
        (await _gifts(tester, phone)).map((g) => g.title),
        isNot(contains('Otro título')),
      );
    });

    _ios('sin cambios, el gesto de borde de iOS cierra sin preguntar', (
      tester,
      phone,
    ) async {
      await _edit(tester, phone, 'Peonza lisa');
      await swipe(tester);
      expect(find.text(_question), findsNothing);
      expect(_editor, findsNothing);
    });

    _ios('un arrastre corto desde el borde no cierra', (tester, phone) async {
      await _edit(tester, phone, 'Peonza lisa');
      final gesture = await tester.startGesture(const Offset(3, 420));
      await gesture.moveBy(const Offset(30, 0));
      await gesture.up();
      await settle(tester);
      expect(_editor, findsOneWidget);
    });

    _ios('el borde no estorba: un arrastre vertical desplaza la lista', (
      tester,
      phone,
    ) async {
      await _edit(tester, phone, 'Peonza lisa');
      tester.view.physicalSize = const Size(390, 700);
      await settle(tester);
      final scrollable = find
          .descendant(of: _editor, matching: find.byType(Scrollable))
          .first;
      final before = tester.state<ScrollableState>(scrollable).position.pixels;
      await tester.dragFrom(const Offset(3, 600), const Offset(0, -300));
      await settle(tester);
      expect(
        tester.state<ScrollableState>(scrollable).position.pixels,
        greaterThan(before),
      );
      expect(_editor, findsOneWidget);
    });

    _tall('en Android el borde no hace nada (lo recoge el sistema)', (
      tester,
      phone,
    ) async {
      await _edit(tester, phone, 'Peonza lisa');
      await swipe(tester);
      expect(_editor, findsOneWidget);
    });
  });
}
