import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/core/widgets/countdown_card.dart';
import 'package:regalos/core/widgets/occasion_countdown_card.dart';
import 'package:regalos/features/occasions/presentation/occasion_detail_screen.dart';
import 'package:regalos/features/settings/application/appearance_provider.dart';

import '../helpers/screens.dart';

Color? _cardColor(WidgetTester tester, Finder card) {
  final container = find
      .descendant(of: card, matching: find.byType(Container))
      .first;
  return (tester.widget<Container>(container).decoration! as BoxDecoration)
      .color;
}

Occasion _occasion(
  String id,
  OccasionKind kind,
  int month,
  int day, {
  bool recurring = true,
  int? year,
}) => Occasion(
  id: id,
  kind: kind,
  rawKind: kind.name,
  name: id,
  month: month,
  day: day,
  year: year,
  recurring: recurring,
  archived: false,
);

/// El botón de añadir regalo del detalle de la ocasión (Personas, debajo,
/// tiene el suyo).
final _detailAddButton = find.descendant(
  of: find.byType(OccasionDetailScreen),
  matching: find.byType(FloatingActionButton),
);

void main() {
  // Hoy es el 9 de noviembre de 2026. Las próximas ocasiones (6 en la muestra)
  // son Tió (45 días), Navidad (46), Reyes (58), cumpleaños de Aritz (125),
  // de Nora (215) y de Leo (267).
  const labels = [
    'Ocasión 1 de 6',
    'Ocasión 2 de 6',
    'Ocasión 3 de 6',
    'Ocasión 4 de 6',
    'Ocasión 5 de 6',
    'Ocasión 6 de 6',
  ];

  screenTest(
    'en el móvil cada tarjeta, también la primera y la última, se asienta con '
    'su borde izquierdo en el margen y el derecho dentro de la pantalla',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      const margin = 16.0;
      const width = 390.0;
      // La tarjeta que queda a la vista: la de más a la izquierda que no se
      // sale por ese lado.
      void expectSettled(int page) {
        final cards = find.byType(OccasionCountdownCard);
        final rects = [
          for (final e in cards.evaluate())
            tester.getRect(find.byWidget(e.widget)),
        ]..sort((a, b) => a.left.compareTo(b.left));
        final shown = rects.where((r) => r.left > -1).first;
        expect(shown.left, closeTo(margin, 0.5), reason: 'página $page');
        expect(
          shown.right,
          lessThanOrEqualTo(width - margin),
          reason: 'página $page',
        );
        // La anterior no asoma por la izquierda.
        for (final r in rects.where((r) => r.left < shown.left)) {
          expect(r.right, lessThanOrEqualTo(margin), reason: 'página $page');
        }
      }

      expectSettled(0);
      for (var page = 1; page < labels.length; page++) {
        await tester.fling(find.byType(PageView), const Offset(-250, 0), 1500);
        await settle(tester);
        expect(find.bySemanticsLabel(labels[page]), findsOneWidget);
        expectSettled(page);
      }
      // Ya no hay más: otro empujón la deja donde está.
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 3000);
      await settle(tester);
      expect(find.bySemanticsLabel(labels.last), findsOneWidget);
      expectSettled(labels.length - 1);
      // Y de vuelta a la primera.
      for (var page = labels.length - 2; page >= 0; page--) {
        await tester.fling(find.byType(PageView), const Offset(250, 0), 1500);
        await settle(tester);
        expectSettled(page);
      }
      expect(tester.takeException(), isNull);
    },
  );

  screenTest('el dibujo de la tarjeta que asoma no se sale de su tarjeta', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    // A medio arrastre la primera sale por la izquierda y su dibujo se
    // desplaza con el paralaje; la tarjeta lo recorta.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
    );
    await gesture.moveBy(const Offset(-30, 0));
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump();
    final first = find.byType(OccasionCountdownCard).first;
    final clip = tester.widget<Container>(
      find.descendant(of: first, matching: find.byType(Container)).first,
    );
    expect(clip.clipBehavior, Clip.hardEdge);
    await gesture.up();
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  screenTest('Personas enseña un carrusel con la más cercana primero', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);

    expect(find.byType(PageView), findsOneWidget);
    expect(find.bySemanticsLabel(labels[0]), findsOneWidget);
    // La primera tarjeta es la del Tió, a 45 días.
    final first = find.byType(OccasionCountdownCard).first;
    expect(
      find.descendant(of: first, matching: find.text('45')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: first, matching: find.text('días')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: first, matching: find.text('Tió')),
      findsOneWidget,
    );
    // Fecha y regalos comprados de la ocasión.
    expect(
      find.descendant(of: first, matching: find.text('24 de diciembre')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: first,
        matching: find.text('1 de 2 regalos comprados'),
      ),
      findsOneWidget,
    );
    // La siguiente asoma por el borde derecho, sin caber entera.
    final second = find.byType(OccasionCountdownCard).at(1);
    final rect = tester.getRect(second);
    expect(rect.left, lessThan(390));
    expect(rect.left, greaterThan(300));
    expect(rect.right, greaterThan(390));
    // Un indicador por página: seis ocasiones en la muestra.
    expect(find.bySemanticsLabel(RegExp(r'^Ocasión \d de 6$')), findsOneWidget);
    // El cumpleaños de Nora, a 215 días, antes fuera del horizonte, ahora sale.
    // (El carrusel construye las tarjetas al deslizar.)
    var swipes = 0;
    while (find.textContaining('Cumpleaños de Nora').evaluate().isEmpty &&
        swipes < 6) {
      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await settle(tester);
      swipes++;
    }
    expect(find.textContaining('Cumpleaños de Nora'), findsOneWidget);
    expect(find.text('215'), findsOneWidget);
  });

  screenTest(
    'las tarjetas del carrusel miden al menos 156 y las de persona 92, '
    'con un segmento por regalo',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      for (final card in find.byType(OccasionCountdownCard).evaluate()) {
        final h = tester
            .getSize(find.byElementPredicate((e) => e == card))
            .height;
        expect(h, greaterThanOrEqualTo(156));
      }
      final first = tester.getRect(find.byType(OccasionCountdownCard).first);
      expect(first.left, 16);
      expect(first.width, closeTo(332, 1));
      final segments =
          find.byKey(const ValueKey('segment-full')).evaluate().length +
          find.byKey(const ValueKey('segment-empty')).evaluate().length;
      expect(segments, greaterThan(0));
    },
  );

  screenTest('se desliza en horizontal y los indicadores siguen la página', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    final pager = tester.widget<PageView>(find.byType(PageView));
    expect(pager.scrollDirection, Axis.horizontal);

    for (var i = 1; i < 6; i++) {
      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await settle(tester);
      expect(find.bySemanticsLabel(labels[i]), findsOneWidget);
    }
    // Y la vista vuelve hacia atrás.
    await tester.drag(find.byType(PageView), const Offset(300, 0));
    await settle(tester);
    expect(find.bySemanticsLabel(labels[4]), findsOneWidget);
  });

  screenTest('tocar una tarjeta abre su ocasión', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await tester.tap(find.byType(OccasionCountdownCard).first);
    await settle(tester);
    expect(find.byType(OccasionDetailScreen), findsOneWidget);
    expect(find.text('Tió'), findsWidgets);
    expect(find.text('Por persona'), findsOneWidget);

    // Se abrió desde Personas: el atrás vuelve allí, no a Ocasiones.
    expect(find.bySemanticsLabel('Volver a Personas'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(OccasionCountdownCard), findsWidgets);
    expect(find.byType(OccasionDetailScreen), findsNothing);

    // Y con el botón de volver.
    await tester.tap(find.byType(OccasionCountdownCard).first);
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Volver a Personas'));
    await settle(tester);
    expect(find.byType(OccasionCountdownCard), findsWidgets);
  });

  // La tarjeta de la ocasión se convierte en su detalle (momento K).
  group('la tarjeta crece hasta el detalle', () {
    /// Las opacidades de lo que envuelve al número del detalle.
    Iterable<double> detailNumberOpacities(WidgetTester tester) => [
      for (final o in tester.widgetList<Opacity>(
        find.ancestor(
          of: find.descendant(
            of: find.byType(CountdownCard),
            matching: find.text('45'),
          ),
          matching: find.byType(Opacity),
        ),
      ))
        o.opacity,
    ];

    screenTest('el número vuela de la tarjeta a la cabecera y la cabecera real '
        'aparece al acabar', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.tap(find.byType(OccasionCountdownCard).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      // En pleno vuelo: el de la tarjeta, el del detalle (oculto) y el que
      // vuela entre los dos.
      expect(find.text('45'), findsNWidgets(3));
      expect(detailNumberOpacities(tester), contains(0));
      expect(find.byType(OccasionDetailScreen), findsOneWidget);
      // La superficie del detalle aún no pinta su fondo ni el botón de añadir.
      expect(_detailAddButton, findsNothing);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('45'), findsNWidgets(3));
      await tester.pumpAndSettle();
      // Acabado el viaje queda la cabecera real, sin el número que volaba.
      expect(find.text('45'), findsOneWidget);
      expect(detailNumberOpacities(tester), everyElement(1));
      expect(_detailAddButton, findsOneWidget);
      expect(find.text('Por persona'), findsOneWidget);
    });

    screenTest('el número cambia de tamaño de letra durante el vuelo', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.tap(find.byType(OccasionCountdownCard).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final sizes = <double>{
        for (final t in tester.widgetList<Text>(find.text('45')))
          t.style!.fontSize!,
      };
      // La de la tarjeta (60), la del detalle (56) y una intermedia o igual.
      expect(sizes.length, greaterThanOrEqualTo(2));
      await tester.pumpAndSettle();
    });

    screenTest('al volver, todo al revés: el detalle se funde y la tarjeta '
        'queda como estaba', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      final rest = tester.getRect(find.byType(OccasionCountdownCard).first);
      await tester.tap(find.byType(OccasionCountdownCard).first);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      // Vuela de vuelta: el número del detalle ya no se pinta.
      expect(detailNumberOpacities(tester), contains(0));
      expect(find.text('45'), findsNWidgets(3));
      await tester.pump(const Duration(milliseconds: 220));
      await tester.pumpAndSettle();
      expect(find.byType(OccasionDetailScreen), findsNothing);
      expect(tester.getRect(find.byType(OccasionCountdownCard).first), rest);
      expect(find.text('45'), findsOneWidget);
    });

    screenTest('con «Reducir movimiento» no vuela nada: fundido de 150 ms', (
      tester,
      phone,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.tap(find.byType(OccasionCountdownCard).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      // La tarjeta y el detalle; el número no vuela (no hay un tercero) y el
      // detalle pinta su fondo y su botón de añadir desde el principio.
      expect(find.text('45'), findsNWidgets(2));
      expect(_detailAddButton, findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(OccasionDetailScreen), findsOneWidget);
    });
  });

  screenTest('con una sola ocasión no hay carrusel ni indicadores', (
    tester,
    phone,
  ) async {
    await bareFamily(tester, phone);
    await tester.runAsync(() async {
      final c = familyOf(phone);
      await c.upsertRecipient(
        const Recipient(
          id: 'aritz',
          name: 'Aritz',
          colorIndex: 0,
          archived: false,
        ),
      );
      await c.upsertOccasion(_occasion('reyes', OccasionKind.kings, 1, 6));
    });
    await pumpRegalos(tester, phone);
    expect(find.byType(OccasionCountdownCard), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
    expect(find.bySemanticsLabel(RegExp(r'^Ocasión \d de')), findsNothing);
    expect(find.text('58'), findsOneWidget);
  });

  screenTest('una ocasión que pasó ayer ya no sale al día siguiente', (
    tester,
    phone,
  ) async {
    await bareFamily(tester, phone);
    await tester.runAsync(() async {
      final c = familyOf(phone);
      await c.upsertRecipient(
        const Recipient(
          id: 'aritz',
          name: 'Aritz',
          colorIndex: 0,
          archived: false,
        ),
      );
      // La comunión fue ayer (8 de noviembre) y no se repite; la boda es hoy.
      await c.upsertOccasion(
        _occasion(
          'comunion',
          OccasionKind.communion,
          11,
          8,
          recurring: false,
          year: 2026,
        ),
      );
      await c.upsertOccasion(
        _occasion(
          'boda',
          OccasionKind.wedding,
          11,
          9,
          recurring: false,
          year: 2026,
        ),
      );
      await c.upsertOccasion(_occasion('reyes', OccasionKind.kings, 1, 6));
    });
    await pumpRegalos(tester, phone);
    expect(find.byType(OccasionCountdownCard), findsNWidgets(2));
    expect(find.text('comunion'), findsNothing);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('boda'), findsOneWidget);
  });

  screenTest('cada tarjeta lleva el color de su ocasión y el interruptor lo '
      'apaga', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    Finder card(String title) => find.byWidgetPredicate(
      (w) => w is OccasionCountdownCard && w.title == title,
    );
    final expected = <String, Color>{
      'Tió': OccasionTheme.tio.palette.pastel,
      'Navidad': OccasionTheme.christmas.palette.pastel,
      'Reyes': OccasionTheme.kings.palette.pastel,
      'Cumpleaños de Aritz': OccasionTheme.birthday.palette.pastel,
      'Cumpleaños de Nora': OccasionTheme.birthday.palette.pastel,
      'Cumpleaños de Leo': OccasionTheme.birthday.palette.pastel,
    };
    // Las tarjetas se construyen según se desliza.
    Future<void> check(Color? Function(String) colorFor) async {
      var swipes = 0;
      // Siempre desde la primera página.
      for (var i = 0; i < 6; i++) {
        await tester.drag(find.byType(PageView), const Offset(300, 0));
        await settle(tester);
      }
      for (final title in expected.keys) {
        while (card(title).evaluate().isEmpty) {
          await tester.drag(find.byType(PageView), const Offset(-300, 0));
          await settle(tester);
          expect(++swipes, lessThan(12));
        }
        expect(_cardColor(tester, card(title)), colorFor(title), reason: title);
      }
    }

    await check((title) => expected[title]);

    phone.container
        .read(appearanceProvider.notifier)
        .setOccasionThemes(enabled: false);
    await settle(tester);
    final standard = AccentId.lavender.palette.pastel;
    await check((_) => standard);
    // El carrusel sigue igual: solo cambia el color.
    expect(find.byType(PageView), findsOneWidget);
  });

  screenTest(
    'aguanta el texto al 130 % en 360 px, claro y oscuro',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      expect(tester.takeException(), isNull);
      expect(find.byType(PageView), findsOneWidget);
      await tester.drag(find.byType(PageView), const Offset(-250, 0));
      await settle(tester);
      expect(tester.takeException(), isNull);
    },
    size: const Size(360, 900),
    textScale: 1.3,
    brightness: Brightness.dark,
  );
}
