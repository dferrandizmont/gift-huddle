import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/layout/pane_selection.dart';
import 'package:regalos/core/theme/regalos_tokens.dart';
import 'package:regalos/core/widgets/budget_meter.dart';
import 'package:regalos/core/widgets/desktop_add_gift_button.dart';
import 'package:regalos/core/widgets/gift_row.dart';
import 'package:regalos/core/widgets/person_avatar.dart';
import 'package:regalos/core/widgets/screen_header.dart';
import 'package:regalos/core/widgets/stroke_icon.dart';
import 'package:regalos/features/gifts/presentation/gift_editor_screen.dart';
import 'package:regalos/features/gifts/presentation/person_list_screen.dart';
import 'package:regalos/features/occasions/presentation/occasion_detail_screen.dart';
import 'package:regalos/features/people/presentation/countdown_carousel.dart';
import 'package:regalos/features/people/presentation/people_screen.dart';

import '../helpers/screens.dart';

// La tanda 2b de la web de escritorio (la guía de diseño de escritorio, §2 y §4.6): Personas con dos paneles. La lista plana, el
// detalle con su botón en la cabecera y sus filas en columnas, la persona sin
// regalos, «Resumen» y la barra de presupuesto que no se anima al cambiar de
// persona. En el móvil, nada cambia.

const _laptop = Size(1536, 864);
const _narrowPanes = Size(1024, 768);

Finder _listRow(String name) =>
    find.descendant(of: find.byType(PeopleListPane), matching: find.text(name));

final _addGift = find.byKey(const ValueKey<String>('add-gift-header'));

/// La fila de regalo de [title].
Finder _giftRow(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(GiftRow));

/// Cuánto mide de ancho cada barra de presupuesto (la parte llena), en el
/// orden del árbol.
List<double> _fills(WidgetTester tester) => [
  for (final box in tester.widgetList<FractionallySizedBox>(
    find.descendant(
      of: find.byType(BudgetBar),
      matching: find.byType(FractionallySizedBox),
    ),
  ))
    box.widthFactor ?? 1,
];

void main() {
  group('la lista de personas, plana', () {
    screenTest('a 1536 las filas miden 64, sin borde ni flecha, y la elegida '
        'lleva su recuadro', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      final list = tester.getRect(find.byType(PeopleListPane));
      final rows = [
        for (final name in ['Aritz', 'Leo', 'Nora'])
          tester.getRect(
            find
                .ancestor(of: _listRow(name), matching: find.byType(InkWell))
                .first,
          ),
      ];
      for (final row in rows) {
        expect(row.height, 60);
        expect(row.left, list.left + 8);
        expect(row.right, list.right - 8);
      }
      expect(rows[1].top - rows[0].top, 64);
      expect(rows[2].top - rows[1].top, 64);
      // Sin flecha a la derecha de cada fila.
      expect(
        find.descendant(
          of: find.byType(SelectionScope),
          matching: find.byType(StrokeIcon),
        ),
        findsNothing,
      );
      // Avatares de 36.
      final avatars = tester.widgetList<PersonAvatar>(
        find.descendant(
          of: find.byType(PeopleListPane),
          matching: find.byType(PersonAvatar),
        ),
      );
      expect(avatars.map((a) => a.size).toSet(), {36.0});
      // Con el nombre en 15 y los datos en 13.
      final name = tester.widget<Text>(_listRow('Aritz'));
      expect(name.style!.fontSize, 15);
      expect(name.style!.fontWeight, FontWeight.w600);
      expect(tester.takeException(), isNull);
    }, size: _laptop);

    screenTest('entre 1280 y 1600 la próxima ocasión es una fila de 56 y no '
        'hay carrusel ni columna', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      expect(find.byType(CountdownCarousel), findsNothing);
      expect(find.byType(SummaryColumn), findsNothing);
      final row = find.byType(UpcomingOccasionRow);
      expect(row, findsOneWidget);
      expect(tester.getRect(row).height, 56);
      // Tocarla abre la ocasión.
      await tester.tap(row);
      await settle(tester);
      expect(find.byType(OccasionDetailScreen), findsOneWidget);
    }, size: _laptop);
  });

  group('el detalle de una persona', () {
    screenTest('«Añadir regalo» es un botón relleno en la cabecera y no hay '
        '«+» flotante', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(_addGift, findsOneWidget);
      expect(tester.widget(_addGift), isA<DesktopAddGiftButton>());
      // Relleno pastel del acento con texto tinta, como «Guardar».
      final fill = tester.widget<FilledButton>(
        find.descendant(of: _addGift, matching: find.byType(FilledButton)),
      );
      final t = RegalosTokens.of(tester.element(_addGift));
      expect(fill.style!.backgroundColor!.resolve({}), t.fill);
      expect(fill.style!.foregroundColor!.resolve({}), t.onFill);
      final header = tester.getRect(
        find.descendant(
          of: find.byType(PersonListScreen),
          matching: find.byType(ScreenHeader),
        ),
      );
      final add = tester.getRect(_addGift);
      expect(add.top, greaterThanOrEqualTo(header.top));
      expect(add.bottom, lessThanOrEqualTo(header.bottom));
      expect(add.right, lessThan(header.right));
      // El «Editar» queda a su derecha.
      final edit = tester.getRect(find.bySemanticsLabel('Editar persona'));
      expect(edit.left, greaterThanOrEqualTo(add.right));
      await tester.tap(_addGift);
      await settle(tester);
      expect(find.byType(GiftEditorScreen), findsOneWidget);
    }, size: _laptop);

    screenTest('las filas van en columnas: título, quién regala, precio y '
        'estado', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      final row = _giftRow('Pijama de astronautas, talla 8');
      final box = tester.getRect(row);
      expect(box.width, greaterThanOrEqualTo(720));
      Rect cell(Finder finder) =>
          tester.getRect(find.descendant(of: row, matching: finder).first);
      final title = cell(find.text('Pijama de astronautas, talla 8'));
      final giver = cell(find.text('Nosotros'));
      final price = cell(find.textContaining('24'));
      final status = cell(find.text('Llegó'));
      expect(title.left, lessThan(giver.left));
      expect(giver.right, lessThan(price.left));
      expect(price.right, lessThan(status.left));
      // El precio, a la derecha de su columna de 96; el estado, en la de 120.
      expect(status.left - 16, closeTo(box.right - 16 - 8 - 120, 1));
      expect(price.right, closeTo(status.left - 16 - 0, 12));
      // Todo centrado en la altura de la fila.
      expect(giver.center.dy, closeTo(box.center.dy, 2));
      expect(price.center.dy, closeTo(box.center.dy, 2));
      expect(tester.takeException(), isNull);
    }, size: _laptop);

    screenTest('con el panel de menos de 720 las filas son las de siempre', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      final row = _giftRow('Pijama de astronautas, talla 8');
      expect(tester.getRect(row).width, lessThan(720));
      Rect cell(Finder finder) =>
          tester.getRect(find.descendant(of: row, matching: finder).first);
      // Quién regala va debajo del título.
      expect(
        cell(find.text('Nosotros')).top,
        greaterThan(cell(find.text('Pijama de astronautas, talla 8')).top),
      );
    }, size: _narrowPanes);

    screenTest('la última fila es «Añadir regalo» en línea y abre el editor', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      final inline = find.descendant(
        of: find.descendant(
          of: find.byType(PersonListScreen),
          matching: find.byType(ListView),
        ),
        matching: find.text('Añadir regalo'),
      );
      expect(inline, findsOneWidget);
      final last = tester.getRect(find.text('Patinete'));
      await tester.ensureVisible(inline);
      expect(tester.getRect(inline).top, greaterThan(last.top));
      await tester.tap(inline);
      await settle(tester);
      expect(find.byType(GiftEditorScreen), findsOneWidget);
    }, size: _laptop);

    screenTest('una persona sin regalos: sin presupuesto ni filtros y un '
        'bloque arriba a la izquierda', (tester, phone) async {
      await seedSample(tester, phone, extraPeople: 1);
      await pumpRegalos(tester, phone);
      await tester.tap(_listRow('Extra 1'));
      await settle(tester);
      final detail = find.byType(PersonListScreen);
      expect(
        find.descendant(of: detail, matching: find.byType(BudgetMeter)),
        findsNothing,
      );
      expect(
        find.descendant(of: detail, matching: find.text('Filtros')),
        findsNothing,
      );
      final title = find.descendant(
        of: detail,
        matching: find.text('Aún no hay regalos para Extra 1'),
      );
      expect(title, findsOneWidget);
      // A 32 de la cabecera, pegado a la izquierda de la columna y no
      // centrado en el panel.
      final header = tester.getRect(
        find.descendant(of: detail, matching: find.byType(ScreenHeader)),
      );
      final text = tester.getRect(title);
      expect(text.top, closeTo(header.bottom + 32, 6));
      expect(text.left, closeTo(header.left + 16, 0.5));
      expect(
        find.descendant(
          of: detail,
          matching: find.widgetWithText(FilledButton, 'Añadir regalo'),
        ),
        findsNWidgets(2),
      );
      // Sus tres próximas ocasiones, como botones.
      final occasions = find.descendant(
        of: detail,
        matching: find.byType(OutlinedButton),
      );
      expect(occasions, findsNWidgets(3));
      final first = tester.widget<Text>(
        find.descendant(of: occasions.first, matching: find.byType(Text)).first,
      );
      final name = first.data!.split(' · ').first;
      await tester.tap(occasions.first);
      await settle(tester);
      // El editor se abre con la ocasión puesta.
      expect(find.byType(GiftEditorScreen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(GiftEditorScreen),
          matching: find.text(name),
        ),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    }, size: _laptop);

    screenTest('con una persona sin regalos el bloque no está en el centro del '
        'panel', (tester, phone) async {
      await seedSample(tester, phone, extraPeople: 1);
      await pumpRegalos(tester, phone);
      await tester.tap(_listRow('Extra 1'));
      await settle(tester);
      final pane = tester.getRect(find.byType(PersonListScreen));
      final title = tester.getRect(
        find.text('Aún no hay regalos para Extra 1'),
      );
      expect(title.center.dy, lessThan(pane.top + pane.height / 3));
      expect(title.center.dx, lessThan(pane.center.dx));
    }, size: _laptop);
  });

  group('cambiar de persona', () {
    screenTest('la barra de presupuesto no se anima al montarse con otra '
        'persona', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.tap(_listRow('Nora'));
      // En el primer fotograma ya está en su sitio, sin recorrer nada.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      final early = _fills(tester);
      expect(early, isNotEmpty);
      await settle(tester);
      expect(_fills(tester), early);
    }, size: _laptop);

    screenTest('el avatar de la lista y la cabecera acaban en unos 200 ms', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.tap(_listRow('Nora'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      // Pasados 200 ms ningún avatar sigue escalándose.
      for (final avatar in find.byType(PersonAvatar).evaluate()) {
        final scales = [
          for (final t in tester.widgetList<Transform>(
            find.ancestor(
              of: find.byElementPredicate((e) => e == avatar),
              matching: find.byType(Transform),
            ),
          ))
            t.transform.storage[0],
        ];
        expect(scales.where((s) => s != 1), isEmpty, reason: '$scales');
      }
      await settle(tester);
    }, size: _laptop);
  });

  group('en el móvil nada cambia', () {
    screenTest('las filas de persona tienen flecha y 76 de alto, el carrusel '
        'sigue y la lista lleva su «+»', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      expect(find.byType(CountdownCarousel), findsOneWidget);
      expect(find.byType(UpcomingOccasionRow), findsNothing);
      final row = tester.getRect(
        find
            .ancestor(of: find.text('Aritz'), matching: find.byType(InkWell))
            .first,
      );
      expect(row.height, greaterThanOrEqualTo(76));
      await tapText(tester, 'Aritz');
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(_addGift, findsNothing);
      // La fila de regalo sigue en una sola columna.
      final gift = _giftRow('Pijama de astronautas, talla 8');
      expect(
        tester
            .getRect(find.descendant(of: gift, matching: find.text('Nosotros')))
            .top,
        greaterThan(
          tester
              .getRect(
                find.descendant(
                  of: gift,
                  matching: find.text('Pijama de astronautas, talla 8'),
                ),
              )
              .top,
        ),
      );
    });

    screenTest('una persona sin regalos conserva su estado vacío centrado y '
        'el presupuesto', (tester, phone) async {
      await seedSample(tester, phone, extraPeople: 1);
      await pumpRegalos(tester, phone);
      await tapText(tester, 'Extra 1');
      expect(find.text('Aún no hay regalos para Extra 1'), findsOneWidget);
      expect(find.byType(BudgetMeter), findsWidgets);
      expect(find.text('Filtros'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });
  });
}
