import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/family/presentation/reparto_flight.dart';
import 'package:regalos/features/family/presentation/reparto_fold.dart';
import 'package:regalos/features/family/presentation/reparto_grid.dart';
import 'package:regalos/features/family/presentation/reparto_occasion_view.dart';
import 'package:regalos/features/family/presentation/reparto_outside.dart';
import 'package:regalos/features/family/presentation/reparto_view_toggle.dart';
import 'package:regalos/features/family/presentation/self_tag.dart';

import '../helpers/screens.dart';
import '../helpers/tablet.dart';
import 'family_grid_tablet_test.dart' show anchorOf, cellOf, chooseSelf, kRail;
import 'family_grid_test.dart' show expectNoRoundShapes, openFamily;

// Tanda T7 del plan de tablet (la guía de diseño para tablet, §6): la vista
// por ocasión de Reparto en una ventana ancha (una columna de 640 en «medio»,
// dos columnas de tarjetas en «expandido»), cambiar quién regala, el vuelo
// entre la rejilla y la lista en los dos tamaños, y girar.

final _flight = find.byKey(kRepartoFlightKey);

/// Las personas de la muestra, en el orden en que salen (por nombre).
const _people = ['aritz', 'leo', 'nora'];

/// La tarjeta de la persona [id] (con su plegado).
Finder _card(String id) => find.byKey(ValueKey<String>('fold:$id'));

Future<void> _toOccasion(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Por ocasión'));
  await settle(tester);
}

Future<void> _toGrid(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Rejilla'));
  await settle(tester);
}

/// Los rectángulos de lo que viaja ahora mismo en la capa del vuelo: regalos,
/// nombres y avatares (cada uno, un `Positioned` con sus cuatro medidas).
List<Rect> _flyers(WidgetTester tester) => [
  for (final p in tester.widgetList<Positioned>(
    find.descendant(of: _flight, matching: find.byType(Positioned)),
  ))
    if (p.left != null && p.top != null && p.width != null && p.height != null)
      Rect.fromLTWH(p.left!, p.top!, p.width!, p.height!),
];

/// Los rectángulos de todas las anclas de la vista que se ve.
List<Rect> _anchors(WidgetTester tester) => [
  for (final e in find.byType(RepartoAnchor).evaluate())
    tester.getRect(find.byElementPredicate((x) => x == e)),
];

/// Si queda alguna ancla oculta (esperando un vuelo).
bool _anyHidden(WidgetTester tester) => tester
    .widgetList<FadeTransition>(
      find.descendant(
        of: find.byType(RepartoAnchor),
        matching: find.byType(FadeTransition),
      ),
    )
    .any((f) => f.opacity.value == 0);

/// Lleva el vuelo hasta su último fotograma y devuelve dónde estaba cada
/// cosa justo antes de retirarse la capa.
Future<List<Rect>> _flyToTheEnd(WidgetTester tester) async {
  var last = <Rect>[];
  for (var i = 0; i < 200 && _flight.evaluate().isNotEmpty; i++) {
    last = _flyers(tester);
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(_flight, findsNothing, reason: 'el vuelo termina');
  return last;
}

/// Que cada cosa que voló acabó exactamente encima de un ancla de la vista
/// nueva (su celda, su fila, su nombre o su avatar). Se mira con la vista ya
/// en reposo: al aterrizar, las celdas rebotan.
void _expectLanded(WidgetTester tester, List<Rect> flyers) {
  expect(flyers, isNotEmpty);
  final anchors = _anchors(tester);
  for (final flyer in flyers) {
    expect(
      anchors.any(
        (a) =>
            (a.left - flyer.left).abs() < 0.5 &&
            (a.top - flyer.top).abs() < 0.5 &&
            (a.width - flyer.width).abs() < 0.5 &&
            (a.height - flyer.height).abs() < 0.5,
      ),
      isTrue,
      reason: 'el vuelo que acaba en $flyer no aterriza en ningún ancla',
    );
  }
}

void main() {
  tabletScreenTest('la lista por ocasión va en una columna de 640 en vertical '
      'y en dos columnas de tarjetas en horizontal, con la franja y las '
      'casillas a lo ancho', (tester, phone, size) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openFamily(tester, all: false);
    await _toOccasion(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(RepartoOccasionView), findsOneWidget);

    final content = size.width - kRail;
    // Por orden de la lista: Aritz, Leo y Nora.
    final cards = [for (final id in _people) tester.getRect(_card(id))];
    // La franja de la ocasión (su recuadro de color, sin el margen).
    final band = tester.getRect(
      find
          .ancestor(
            of: find.text('24 de diciembre'),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    if (size == kTabletPortrait) {
      // Una columna de 640 centrada (608 con sus márgenes de 16).
      final left = kRail + (content - 640) / 2 + 16;
      for (final card in cards) {
        expect(card.left, closeTo(left, 0.01));
        expect(card.width, closeTo(608, 0.01));
      }
      expect(cards[1].top, greaterThanOrEqualTo(cards[0].bottom));
      expect(cards[2].top, greaterThanOrEqualTo(cards[1].bottom));
      expect(band.left, closeTo(left, 0.01));
      expect(band.width, closeTo(608, 0.01));
    } else {
      // Dos columnas de 560, con 12 entre ellas, centradas.
      final left = kRail + (content - (2 * 560 + 12 + 32)) / 2 + 16;
      expect(cards[0].left, closeTo(left, 0.01));
      expect(cards[1].left, closeTo(left + 560 + 12, 0.01));
      expect(cards[2].left, closeTo(left, 0.01));
      for (final card in cards) {
        expect(card.width, closeTo(560, 0.01));
        expect(card.right, lessThanOrEqualTo(size.width - 16));
      }
      // Se alternan: la primera de cada columna, a la misma altura; la
      // tercera, bajo la primera.
      expect(cards[1].top, cards[0].top);
      expect(cards[2].top, greaterThanOrEqualTo(cards[0].bottom));
      // La franja, a lo ancho de las dos.
      expect(band.left, closeTo(left, 0.01));
      expect(band.right, closeTo(cards[1].right, 0.01));
    }
    // Las casillas de «cuántos paquetes»: 140 cada una, en una fila.
    final packets = [
      for (final name in ['Aritz', 'Nora', 'Leo'])
        tester.getRect(find.bySemanticsLabel(RegExp('^$name: ')).first),
    ];
    for (final packet in packets) {
      expect(packet.width, closeTo(140, 0.01));
      expect(packet.top, packets.first.top);
    }
    expect(packets.first.left, closeTo(band.left, 0.01));
    // Las pestañas empiezan con la columna.
    final tabs = tester.getRect(find.byKey(kRepartoOccasionTabsKey));
    expect(tabs.left, closeTo(band.left - 16, 0.01));
    expect(tabs.width, closeTo(size == kTabletPortrait ? 640 : 1164, 0.01));
    expectNoRoundShapes(tester, find.byType(RepartoOccasionView));
    expect(tester.takeException(), isNull);
  });

  tabletScreenTest('cambiar quién regala en la lista guarda el cambio', (
    tester,
    phone,
    size,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openFamily(tester, all: false);
    await _toOccasion(tester);
    await tester.tap(
      find.bySemanticsLabel(RegExp('^Quién regala: Tía Marta y Jordi')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Nadie'), findsOneWidget);
    await tester.tap(find.text('Yayos de Terrassa'));
    await settle(tester);
    await settle(tester);
    final state = await familyState(tester, phone);
    expect(
      state.view.gifts
          .firstWhere((g) => g.title.startsWith('Libro de dinosaurios'))
          .giverId,
      'yayos',
    );
    expect(tester.takeException(), isNull);
  });

  tabletScreenTest('el vuelo entre la rejilla y la lista acaba en su sitio a '
      'la ida (cada regalo en su fila) y a la vuelta (en su celda), con los '
      'nombres y los avatares', (tester, phone, size) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openFamily(tester, all: false);
    const title = 'Pijama de astronautas, talla 8';

    // Ida.
    await tester.tap(find.bySemanticsLabel('Por ocasión'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(_flight, findsOneWidget);
    expect(
      find.descendant(of: _flight, matching: find.text(title)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _flight, matching: find.text('Nora')),
      findsOneWidget,
    );
    expect(_anyHidden(tester), isTrue);
    // Un toque al conmutador a mitad de vuelo no cambia nada.
    await tester.tap(find.bySemanticsLabel('Rejilla'));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(RepartoOccasionView), findsOneWidget);
    final arrived = await _flyToTheEnd(tester);
    await settle(tester);
    _expectLanded(tester, arrived);
    expect(_anyHidden(tester), isFalse);
    expect(find.text(title), findsOneWidget);
    expect(find.byType(RepartoGrid), findsNothing);
    expect(tester.takeException(), isNull);

    // Vuelta.
    await tester.tap(find.bySemanticsLabel('Rejilla'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(_flight, findsOneWidget);
    final landed = await _flyToTheEnd(tester);
    await settle(tester);
    _expectLanded(tester, landed);
    // Algún regalo ha llegado a la celda de «Nosotros para Aritz».
    final cell = tester.getRect(cellOf('aritz', 'us'));
    expect(landed.any((r) => (r.center - cell.center).distance < 0.5), isTrue);
    expect(_anyHidden(tester), isFalse);
    expect(find.byType(RepartoGrid), findsOneWidget);
    expect(find.text(title), findsNothing);
    expect(tester.takeException(), isNull);
  });

  tabletScreenTest('girar a mitad de vuelo lo acaba en el acto: no queda '
      'ninguna capa, nada se queda oculto y el conmutador vuelve a '
      'responder', (tester, phone, size) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openFamily(tester, all: false);

    await tester.tap(find.bySemanticsLabel('Por ocasión'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 120));
    expect(_flight, findsOneWidget);
    expect(_anyHidden(tester), isTrue);

    await rotate(tester);
    // La capa ya no pinta nada en el fotograma del giro y se retira en el
    // siguiente.
    expect(_flyers(tester), isEmpty);
    await tester.pump();
    expect(_flight, findsNothing);
    expect(_anyHidden(tester), isFalse);
    expect(tester.takeException(), isNull);
    await settle(tester);
    expect(_flight, findsNothing);
    expect(find.byType(RepartoOccasionView), findsOneWidget);
    expect(find.byType(RepartoGrid), findsNothing);
    expect(_anyHidden(tester), isFalse);

    // El conmutador no se ha quedado bloqueado: vuelve a la rejilla, con su
    // vuelo, ya en la ventana girada.
    await tester.tap(find.bySemanticsLabel('Rejilla'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(_flight, findsOneWidget);
    final back = await _flyToTheEnd(tester);
    await settle(tester);
    _expectLanded(tester, back);
    expect(find.byType(RepartoGrid), findsOneWidget);
    expect(_anyHidden(tester), isFalse);
    expect(tester.takeException(), isNull);
  });

  tabletScreenTest('girar con la lista abierta conserva la pestaña, la fila '
      'desplegada y las tarjetas (no se montan de nuevo), y el vuelo de vuelta '
      'sigue saliendo', (tester, phone, size) async {
    await seedSample(tester, phone);
    await chooseSelf(tester, phone, 'aritz');
    await pumpRegalos(tester, phone);
    await openFamily(tester, all: false);
    await _toOccasion(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(kRepartoOccasionTabsKey),
        matching: find.text('Reyes'),
      ),
    );
    await settle(tester);
    expect(find.text('6 de enero'), findsOneWidget);
    await tester.tap(
      find.bySemanticsLabel(RegExp('^Quién regala: Yayos de Terrassa')),
    );
    await settle(tester);
    expect(find.text('Nadie'), findsOneWidget);
    final view = tester.state(find.byType(RepartoOccasionView));
    final cards = [
      for (final id in _people) tester.state<State<FoldTransition>>(_card(id)),
    ];
    final columnsBefore = {
      for (final id in _people) tester.getRect(_card(id)).left,
    }.length;

    await rotate(tester);
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(tester.state(find.byType(RepartoOccasionView)), same(view));
    for (final (i, id) in _people.indexed) {
      expect(tester.state<State<FoldTransition>>(_card(id)), same(cards[i]));
    }
    expect(find.text('6 de enero'), findsOneWidget);
    expect(find.text('Nadie'), findsOneWidget);
    expect(_flight, findsNothing);
    // El número de columnas es el del tamaño nuevo.
    final columnsAfter = {
      for (final id in _people) tester.getRect(_card(id)).left,
    }.length;
    expect(columnsBefore, size == kTabletPortrait ? 1 : 2);
    expect(columnsAfter, size == kTabletPortrait ? 2 : 1);
    // «Yo» sigue en la tarjeta de Aritz.
    expect(find.byType(SelfTag), findsOneWidget);

    // De vuelta a la rejilla, con su vuelo, y «Yo» acaba junto a su nombre.
    await tester.tap(find.bySemanticsLabel('Rejilla'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(_flight, findsOneWidget);
    final back = await _flyToTheEnd(tester);
    await settle(tester);
    _expectLanded(tester, back);
    expect(find.byType(RepartoGrid), findsOneWidget);
    expect(_anyHidden(tester), isFalse);
    final name = tester.getRect(
      find.descendant(
        of: anchorOf(repartoNameAnchor('aritz')),
        matching: find.byType(Text),
      ),
    );
    final tag = tester.getRect(find.byType(SelfTag));
    expect(tag.left, greaterThan(name.right));
    expect(tag.center.dy, closeTo(name.center.dy, 3));
    expect(tester.takeException(), isNull);
  });

  tabletScreenTest('«Yo» espera oculta a su nombre durante el vuelo y se '
      'funde al llegar, a la ida y a la vuelta', (tester, phone, size) async {
    await seedSample(tester, phone);
    await chooseSelf(tester, phone, 'aritz');
    await pumpRegalos(tester, phone);
    await openFamily(tester, all: false);
    Iterable<double> fades() => tester
        .widgetList<FadeTransition>(
          find.ancestor(
            of: find.byType(SelfTag),
            matching: find.byType(FadeTransition),
          ),
        )
        .map((f) => f.opacity.value);
    expect(find.byType(SelfTag), findsOneWidget);
    expect(fades().every((o) => o == 1), isTrue);

    for (final label in ['Por ocasión', 'Rejilla']) {
      await tester.tap(find.bySemanticsLabel(label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_flight, findsOneWidget, reason: label);
      expect(fades().any((o) => o == 0), isTrue, reason: label);
      await settle(tester);
      expect(_flight, findsNothing, reason: label);
      expect(find.byType(SelfTag), findsOneWidget, reason: label);
      expect(fades().every((o) => o == 1), isTrue, reason: label);
      expect(tester.takeException(), isNull);
    }
  });

  tabletScreenTest('quien sale del reparto se pliega sin que las demás '
      'tarjetas salten de columna, y «Fuera del reparto» no se estira', (
    tester,
    phone,
    size,
  ) async {
    await seedSample(tester, phone, extraPeople: 1);
    await pumpRegalos(tester, phone);
    await openFamily(tester, all: false);
    await _toOccasion(tester);
    // En Reyes hay regalos para Aritz, Nora y Leo: al salir Aritz siguen
    // quedando tarjetas.
    await tester.tap(
      find.descendant(
        of: find.byKey(kRepartoOccasionTabsKey),
        matching: find.text('Reyes'),
      ),
    );
    await settle(tester);
    expect(_card('aritz'), findsOneWidget);
    final before = {
      for (final id in ['nora', 'leo', 'extra0'])
        id: tester.getRect(_card(id)).left,
    };

    await tester.runAsync(
      () => familyOf(phone).setRecipientInReparto('aritz', false),
    );
    await settle(tester);
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(_card('aritz'), findsNothing);
    for (final id in before.keys) {
      expect(tester.getRect(_card(id)).left, before[id], reason: id);
    }

    final toggle = find.byKey(kRepartoOutsideToggleKey);
    await tester.ensureVisible(toggle);
    await settle(tester);
    await tester.tap(toggle);
    await settle(tester);
    final include = find.byKey(repartoIncludeKey('aritz'));
    expect(include, findsOneWidget);
    await tester.ensureVisible(include);
    await settle(tester);
    final block = tester.getRect(toggle);
    expect(block.width, lessThanOrEqualTo(560));
    expect(tester.getRect(include).right, lessThanOrEqualTo(block.left + 560));

    // Al volver a incluirla, su tarjeta vuelve y las demás siguen en su sitio.
    await tester.tap(include);
    await settle(tester);
    await settle(tester);
    expect(_card('aritz'), findsOneWidget);
    for (final id in before.keys) {
      expect(tester.getRect(_card(id)).left, before[id], reason: id);
    }
    expect(tester.takeException(), isNull);
  });

  tabletScreenTest(
    'con la letra al 130 % nada se desborda en la lista por ocasión',
    (tester, phone, size) async {
      await seedSample(tester, phone);
      await chooseSelf(tester, phone, 'nora');
      await pumpRegalos(tester, phone);
      await openFamily(tester, all: false);
      await _toOccasion(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.bySemanticsLabel(RegExp('^Quién regala: Tía Marta y Jordi')),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
    },
    sizes: const [kTabletPortrait],
    textScale: 1.3,
  );

  tabletScreenTest('en oscuro y con «Reducir movimiento» las vistas se funden: '
      'no vuela nada', (tester, phone, size) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openFamily(tester, all: false);
    await tester.tap(find.bySemanticsLabel('Por ocasión'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(_flight, findsNothing);
    expect(_anyHidden(tester), isFalse);
    await settle(tester);
    expect(find.byType(RepartoOccasionView), findsOneWidget);
    await rotate(tester);
    await settle(tester);
    expect(tester.takeException(), isNull);
    await _toGrid(tester);
    expect(find.byType(RepartoGrid), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, brightness: Brightness.dark);

  tabletScreenTest(
    'en el móvil la lista por ocasión es la de siempre: una columna de lado '
    'a lado y casillas de tres en tres',
    (tester, phone, size) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openFamily(tester, all: false);
      await _toOccasion(tester);
      for (final id in _people) {
        final card = tester.getRect(_card(id));
        expect(card.left, 16);
        expect(card.width, size.width - 32);
      }
      final packet = tester.getRect(
        find.bySemanticsLabel(RegExp('^Aritz: ')).first,
      );
      expect(packet.left, 16);
      expect(packet.width, closeTo((size.width - 32 - 16) / 3, 0.01));
      expect(tester.getRect(find.byKey(kRepartoOccasionTabsKey)).left, 0);
      expect(find.byKey(kRepartoViewToggleKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    sizes: const [kPhoneSize],
  );
}
