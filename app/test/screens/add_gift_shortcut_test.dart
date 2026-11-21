import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/layout/pane_scope.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/theme/regalos_shape.dart';
import 'package:regalos/features/gifts/presentation/gift_editor_screen.dart';
import 'package:regalos/features/lock/application/lock_controller.dart';

import '../helpers/memory_stores.dart';
import '../helpers/screens.dart';
import '../helpers/tablet.dart';

// El botón «Añadir regalo» de Personas y Ocasiones: abre el editor con la
// elección de persona arriba, sin ir antes a la persona.

final _button = find.widgetWithText(FloatingActionButton, 'Añadir regalo');
final _editor = find.byType(GiftEditorScreen);
final _sheet = find.byType(BottomSheet);

Future<List<Gift>> _gifts(WidgetTester tester, FakePhone phone) async =>
    (await familyState(tester, phone)).view.gifts;

/// Una familia con [people] y las ocasiones de Cataluña (cada persona con
/// cumpleaños tiene el suyo).
Future<void> _family(
  WidgetTester tester,
  FakePhone phone,
  List<Recipient> people,
) => tester.runAsync(() async {
  final c = familyOf(phone);
  await c.createFamily(deviceName: 'M');
  for (final p in people) {
    await c.upsertRecipient(p);
  }
  await c.seedDefaultOccasions('ES-CT');
  await c.ensureBirthdayOccasions();
  await phone.container.read(lockControllerProvider.notifier).skipSetup();
});

Recipient _person(
  String id,
  String name, {
  int color = 0,
  bool archived = false,
  int? month,
  int? day,
}) => Recipient(
  id: id,
  name: name,
  colorIndex: color,
  birthMonth: month,
  birthDay: day,
  archived: archived,
);

/// Abre la hoja de «Para quién» y devuelve los nombres que ofrece.
Future<List<String>> _offered(WidgetTester tester, List<String> names) async {
  await tester.tap(find.bySemanticsLabel(RegExp(r'^Para quién')).first);
  await settle(tester);
  final inSheet = [
    for (final n in names)
      if (find
          .descendant(of: _sheet, matching: find.text(n))
          .evaluate()
          .isNotEmpty)
        n,
  ];
  return inSheet;
}

void main() {
  screenTest(
    'Personas: el botón abre el editor, sin persona marcada, y no guarda sin '
    'elegirla',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      expect(_button, findsOneWidget);
      // Rectángulo de radio 8, no una píldora ni un círculo.
      final fab = tester.widget<FloatingActionButton>(_button);
      expect(
        (fab.shape! as RoundedRectangleBorder).borderRadius,
        RegalosShape.fab,
      );
      final before = (await _gifts(tester, phone)).length;

      await tester.tap(_button);
      await settle(tester);
      expect(find.text('Nuevo regalo'), findsOneWidget);
      // «Para quién» arriba del todo y vacío (hay tres personas).
      final person = find.bySemanticsLabel(RegExp(r'^Para quién'));
      expect(person, findsOneWidget);
      expect(
        tester.getTopLeft(person).dy,
        lessThan(
          tester.getTopLeft(find.widgetWithText(TextField, 'Regalo')).dy,
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Regalo'),
        'Bicicleta',
      );
      await tapText(tester, 'Guardar');
      expect(find.text('Elige para quién es el regalo.'), findsOneWidget);
      expect(_editor, findsOneWidget);
      expect((await _gifts(tester, phone)).length, before);

      // Elegida la persona, el aviso se va y el regalo se guarda en ella.
      await tester.tap(person);
      await settle(tester);
      await tester.tap(
        find.descendant(of: _sheet, matching: find.text('Nora')),
      );
      await settle(tester);
      expect(find.text('Elige para quién es el regalo.'), findsNothing);
      await tapText(tester, 'Guardar');
      expect(_editor, findsNothing);

      final saved = (await _gifts(
        tester,
        phone,
      )).firstWhere((g) => g.title == 'Bicicleta');
      expect(saved.recipientId, 'nora');
      // El aviso lleva a la lista de Nora, donde está el regalo.
      expect(find.text('Regalo añadido a la lista de Nora'), findsOneWidget);
      await tapText(tester, 'Ver');
      expect(find.text('Bicicleta'), findsOneWidget);
      expect(find.text('Nora'), findsWidgets);
    },
  );

  screenTest('con una sola persona, ya viene elegida', (tester, phone) async {
    await _family(tester, phone, [_person('aritz', 'Aritz')]);
    await pumpRegalos(tester, phone);
    await tester.tap(_button);
    await settle(tester);
    expect(
      find.bySemanticsLabel(RegExp(r'^Para quién, Aritz')),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Regalo'),
      'Puzle de 500 piezas',
    );
    await tapText(tester, 'Guardar');
    expect(_editor, findsNothing);
    final saved = (await _gifts(tester, phone)).single;
    expect(saved.recipientId, 'aritz');
  });

  screenTest('las personas archivadas no se ofrecen', (tester, phone) async {
    await _family(tester, phone, [
      _person('aritz', 'Aritz'),
      _person('nora', 'Nora', color: 4),
      _person('leo', 'Leo', color: 3, archived: true),
    ]);
    await pumpRegalos(tester, phone);
    await tester.tap(_button);
    await settle(tester);
    final offered = await _offered(tester, ['Aritz', 'Nora', 'Leo']);
    expect(offered, ['Aritz', 'Nora']);
  });

  screenTest('cambiar de persona quita el cumpleaños de otra', (
    tester,
    phone,
  ) async {
    await _family(tester, phone, [
      _person('aritz', 'Aritz', month: 3, day: 14),
      _person('nora', 'Nora', color: 4, month: 6, day: 12),
    ]);
    await pumpRegalos(tester, phone);
    await tester.tap(_button);
    await settle(tester);

    Future<void> choose(String label, String name) async {
      await tester.tap(find.bySemanticsLabel(RegExp('^$label(,|\n|\$)')).first);
      await settle(tester);
      await tester.tap(
        find.descendant(of: _sheet, matching: find.text(name)).first,
      );
      await settle(tester);
    }

    await choose('Para quién', 'Aritz');
    await choose('Ocasión', 'Cumpleaños de Aritz');
    expect(
      find.bySemanticsLabel(RegExp(r'^Ocasión, Cumpleaños de Aritz')),
      findsOneWidget,
    );
    // Con otra persona, el cumpleaños de Aritz ya no pega.
    await choose('Para quién', 'Nora');
    expect(
      find.bySemanticsLabel(RegExp(r'^Ocasión, Sin ocasión')),
      findsOneWidget,
    );

    // Una ocasión que no es de nadie se queda al cambiar.
    await choose('Ocasión', 'Reyes');
    await choose('Para quién', 'Aritz');
    expect(find.bySemanticsLabel(RegExp(r'^Ocasión, Reyes')), findsOneWidget);
  });

  screenTest('Ocasiones: el botón está y, sin personas, invita a crear una', (
    tester,
    phone,
  ) async {
    await _family(tester, phone, const []);
    await pumpRegalos(tester, phone);
    // Personas vacía: no hay botón, queda «Añadir persona».
    expect(_button, findsNothing);
    await tapText(tester, 'Ocasiones');
    expect(_button, findsOneWidget);

    await tester.tap(_button);
    await settle(tester);
    expect(
      find.text('Añade primero a la persona que recibirá el regalo.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Regalo'),
      'Un libro',
    );
    await tapText(tester, 'Guardar');
    expect(find.text('Elige para quién es el regalo.'), findsOneWidget);
    expect(_editor, findsOneWidget);

    // Crea la primera persona con la hoja de siempre y queda elegida.
    await tapText(tester, 'Añadir persona');
    await tester.enterText(find.widgetWithText(TextField, 'Nombre'), 'Nora');
    await tester.tap(
      find.descendant(of: _sheet, matching: find.text('Guardar')),
    );
    await settle(tester);
    expect(find.bySemanticsLabel(RegExp(r'^Para quién, Nora')), findsOneWidget);
    expect(find.text('Elige para quién es el regalo.'), findsNothing);
    await tapText(tester, 'Guardar');
    expect(_editor, findsNothing);
    final saved = (await _gifts(tester, phone)).single;
    expect(saved.title, 'Un libro');
    expect(saved.recipientId, isNotEmpty);
  });

  tabletScreenTest(
    'en tablet el botón se queda a 16 del borde de la columna de 640',
    (tester, phone, size) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      final pane = tester.getRect(find.byType(PaneScope));
      final button = tester.getRect(_button);
      expect(button.right, pane.center.dx + 320 - 16);
      expect(button.bottom, lessThanOrEqualTo(size.height - 16));
      await tester.tap(_button);
      await settle(tester);
      // El editor es la tarjeta de 640 centrada.
      expect(tester.getSize(_editor).width, 640);
    },
    // A 1280 × 800 hay dos paneles y el «+» es el del detalle de la persona
    // (`test/app/two_pane_web_test.dart`).
    sizes: const [kTabletPortrait],
  );
}
