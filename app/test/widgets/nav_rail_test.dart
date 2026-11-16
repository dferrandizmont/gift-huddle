import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/core/widgets/regalos_nav_bar.dart';
import 'package:regalos/core/widgets/regalos_nav_rail.dart';
import 'package:regalos/core/widgets/stroke_icon.dart';

import '../helpers/pump_app.dart';
import '../helpers/tablet.dart';
import 'motion_shared_test.dart' show moving;

void main() {
  const labels = ['Personas', 'Reparto', 'Ocasiones', 'Ajustes'];

  List<NavDestination> destinations({String familyLabel = 'Reparto'}) => [
    const NavDestination(icon: AppIcons.people, label: 'Personas'),
    NavDestination(icon: AppIcons.family, label: familyLabel),
    const NavDestination(icon: AppIcons.occasions, label: 'Ocasiones'),
    const NavDestination(icon: AppIcons.settings, label: 'Ajustes'),
  ];

  Future<void> pumpRail(
    WidgetTester tester, {
    int selected = 0,
    ValueChanged<int>? onSelected,
    Brightness brightness = Brightness.light,
    double textScale = 1,
    String familyLabel = 'Reparto',
    bool? reduce,
    Size size = kTabletPortrait,
  }) => pumpThemed(
    tester,
    RegalosNavRail(
      semanticLabel: 'Navegación principal',
      selectedIndex: selected,
      onSelected: onSelected ?? (_) {},
      destinations: destinations(familyLabel: familyLabel),
    ),
    brightness: brightness,
    textScale: textScale,
    disableAnimations: reduce,
    surfaceSize: size,
  );

  /// El raíl con el destino activo en un `StatefulBuilder`, para cambiarlo.
  Future<StateSetter> pumpSwitchable(
    WidgetTester tester,
    int Function() selected, {
    bool? reduce,
  }) async {
    late StateSetter set;
    await pumpThemed(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          set = setState;
          return RegalosNavRail(
            semanticLabel: 'Navegación principal',
            selectedIndex: selected(),
            onSelected: (_) {},
            destinations: destinations(),
          );
        },
      ),
      disableAnimations: reduce,
      surfaceSize: kTabletPortrait,
    );
    return set;
  }

  final rail = find.byType(RegalosNavRail);

  /// El recuadro pastel que viaja detrás del icono del destino activo.
  final indicator = find.byKey(const ValueKey('nav-indicator'));

  /// La zona táctil de un destino.
  Finder zone(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(InkWell));

  Finder iconOf(String label) =>
      find.descendant(of: zone(label), matching: find.byType(StrokeIcon));

  for (final brightness in Brightness.values) {
    testWidgets('mide 80, lleva un filete hacia el contenido y el destino '
        'activo tiene un recuadro pastel de 56 × 30 y radio 8 '
        '(${brightness.name})', (tester) async {
      await pumpRail(tester, selected: 1, brightness: brightness);
      final t = RegalosTokens.of(tester.element(rail));
      final railRect = tester.getRect(rail);
      expect(railRect.width, 80);
      expect(railRect.height, kTabletPortrait.height);
      // Fondo de la pantalla y filete de 1 px en el lado del contenido.
      expect(
        tester
            .widget<Material>(
              find.descendant(of: rail, matching: find.byType(Material)),
            )
            .color,
        t.bg,
      );
      final borders = [
        for (final box in tester.widgetList<DecoratedBox>(
          find.descendant(of: rail, matching: find.byType(DecoratedBox)),
        ))
          if ((box.decoration as BoxDecoration).border
              case final BorderDirectional border)
            border,
      ];
      expect(borders, hasLength(1));
      expect(borders.single.end, BorderSide(color: t.separator));
      expect(borders.single.start, BorderSide.none);

      // Los destinos: 72 × 56, a 16 del borde superior y separados 10.
      for (var i = 0; i < labels.length; i++) {
        final rect = tester.getRect(zone(labels[i]));
        expect(rect.size, const Size(72, 56), reason: labels[i]);
        expect(rect.top, 16 + i * 66.0, reason: labels[i]);
        expect(rect.center.dx, railRect.center.dx, reason: labels[i]);
      }

      // El recuadro, sobre el icono del destino activo.
      final rect = tester.getRect(indicator);
      expect(rect.size, const Size(56, 30));
      final icon = tester.getRect(iconOf('Reparto'));
      expect(rect.center.dx, closeTo(icon.center.dx, 0.5));
      expect(rect.center.dy, closeTo(icon.center.dy, 0.5));
      expect(icon.size, const Size(22, 22));
      // Pastel del acento y esquinas de 8, nunca una píldora.
      final deco =
          tester
                  .widget<DecoratedBox>(
                    find.descendant(
                      of: indicator,
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect(deco.color, t.fill);
      expect(deco.borderRadius, RegalosShape.chip);

      // Etiqueta de 12 en negrita y en tinta; el resto, no.
      final style = tester.widget<Text>(find.text('Reparto')).style!;
      expect(style.fontWeight, FontWeight.w600);
      expect(style.fontSize, 12);
      expect(style.color, t.ink);
      final other = tester.widget<Text>(find.text('Personas')).style!;
      expect(other.fontWeight, FontWeight.w500);
      expect(other.color, t.textSecondary);
      // La etiqueta va debajo del recuadro, dentro de su destino.
      final label = tester.getRect(find.text('Reparto'));
      expect(label.top, greaterThanOrEqualTo(rect.bottom));
      expect(
        label.bottom,
        lessThanOrEqualTo(tester.getRect(zone('Reparto')).bottom),
      );
    });
  }

  testWidgets('cada destino se puede tocar entero', (tester) async {
    final taps = <int>[];
    await pumpRail(tester, onSelected: taps.add);
    await tester.tap(find.text('Ocasiones'));
    // Un toque en la esquina de la zona táctil también cuenta.
    final rect = tester.getRect(zone('Ajustes'));
    await tester.tapAt(rect.topLeft + const Offset(2, 2));
    await tester.tapAt(rect.bottomRight - const Offset(2, 2));
    // El activo también avisa: así vuelve a su primera pantalla.
    await tester.tap(find.text('Personas'));
    expect(taps, [2, 3, 3, 0]);
  });

  testWidgets('el recuadro viaja en vertical: se estira hacia el destino, se '
      'recoge al llegar y nunca cambia de ancho', (tester) async {
    var selected = 0;
    final set = await pumpSwitchable(tester, () => selected);
    final rest = tester.getRect(indicator);
    expect(rest.height, 30);
    set(() => selected = 3);
    await tester.pump();
    var tallest = 0.0;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final r = tester.getRect(indicator);
      tallest = math.max(tallest, r.height);
      expect(r.width, 56);
      expect(r.left, rest.left);
    }
    // A mitad de camino cubre buena parte de la distancia entre destinos.
    expect(tallest, greaterThan(30 + 60));
    await tester.pumpAndSettle();
    final end = tester.getRect(indicator);
    expect(end.height, closeTo(30, 0.01));
    expect(end.top, closeTo(rest.top + 3 * 66, 0.01));
    expect(
      end.center.dy,
      closeTo(tester.getRect(iconOf('Ajustes')).center.dy, 0.5),
    );
  });

  testWidgets('el borde de delante sale antes que el de atrás, hacia abajo y '
      'hacia arriba', (tester) async {
    var selected = 0;
    final set = await pumpSwitchable(tester, () => selected);
    final top0 = tester.getRect(indicator).top;
    final bottom0 = tester.getRect(indicator).bottom;
    set(() => selected = 2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    var r = tester.getRect(indicator);
    // Va hacia abajo: sale el borde de abajo; el de arriba espera 70 ms.
    expect(r.bottom, greaterThan(bottom0 + 5));
    expect(r.top, closeTo(top0, 0.01));
    await tester.pumpAndSettle();

    final top2 = tester.getRect(indicator).top;
    final bottom2 = tester.getRect(indicator).bottom;
    set(() => selected = 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    r = tester.getRect(indicator);
    // Va hacia arriba: sale el borde de arriba.
    expect(r.top, lessThan(top2 - 5));
    expect(r.bottom, closeTo(bottom2, 0.01));
    await tester.pumpAndSettle();
    expect(tester.getRect(indicator).top, closeTo(top0, 0.01));
  });

  testWidgets('si se toca otro destino a mitad de camino, parte desde donde '
      'está', (tester) async {
    var selected = 0;
    final set = await pumpSwitchable(tester, () => selected);
    set(() => selected = 3);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final mid = tester.getRect(indicator);
    set(() => selected = 1);
    await tester.pump();
    // El primer fotograma del viaje nuevo es el último del anterior.
    final next = tester.getRect(indicator);
    expect(next.top, closeTo(mid.top, 0.01));
    expect(next.bottom, closeTo(mid.bottom, 0.01));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(indicator).center.dy,
      closeTo(tester.getRect(iconOf('Reparto')).center.dy, 0.5),
    );
  });

  testWidgets('con «Reducir movimiento» el recuadro no viaja: cada destino lo '
      'funde en 150 ms y nada se traslada ni escala', (tester) async {
    var selected = 1;
    final set = await pumpSwitchable(tester, () => selected, reduce: true);
    final t = RegalosTokens.of(tester.element(rail));
    expect(indicator, findsNothing);

    AnimatedContainer box(String label) => tester.widget<AnimatedContainer>(
      find.descendant(
        of: zone(label),
        matching: find.byType(AnimatedContainer),
      ),
    );
    bool lit(String label) =>
        (box(label).decoration! as BoxDecoration).color == t.fill;

    expect(lit('Reparto'), isTrue);
    expect(lit('Personas'), isFalse);
    expect(box('Reparto').duration, RegalosMotion.fade);
    expect(
      (box('Reparto').decoration! as BoxDecoration).borderRadius,
      RegalosShape.chip,
    );

    set(() => selected = 3);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    expect(moving(tester, rail), isEmpty);
    await tester.pumpAndSettle();
    expect(lit('Ajustes'), isTrue);
    expect(lit('Reparto'), isFalse);
    expect(indicator, findsNothing);
  });

  testWidgets('el activo se lee como seleccionado para los lectores', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpRail(tester, selected: 1);
    expect(find.bySemanticsLabel('Navegación principal'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Reparto')),
      matchesSemantics(
        label: 'Reparto',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Personas')),
      matchesSemantics(
        label: 'Personas',
        isButton: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('con el texto al 130 % los destinos crecen todos igual, el '
      'recuadro sigue sobre su icono y una etiqueta larga se encoge sin '
      'cortarse ni desbordar', (tester) async {
    await pumpRail(
      tester,
      familyLabel: 'Repartiment',
      textScale: 1.3,
      selected: 3,
    );
    expect(tester.takeException(), isNull);
    final heights = {
      for (final label in ['Personas', 'Repartiment', 'Ocasiones', 'Ajustes'])
        tester.getSize(zone(label)).height,
    };
    expect(heights, hasLength(1));
    expect(heights.single, greaterThan(56));
    final rect = tester.getRect(indicator);
    final icon = tester.getRect(iconOf('Ajustes'));
    expect(rect.size, const Size(56, 30));
    expect(rect.center.dy, closeTo(icon.center.dy, 0.5));
    // Las etiquetas no se salen de su zona táctil.
    for (final label in ['Personas', 'Repartiment', 'Ocasiones', 'Ajustes']) {
      final text = tester.getRect(find.text(label));
      final area = tester.getRect(zone(label));
      expect(text.left, greaterThanOrEqualTo(area.left - 0.01), reason: label);
      expect(text.right, lessThanOrEqualTo(area.right + 0.01), reason: label);
      expect(text.bottom, lessThanOrEqualTo(area.bottom + 0.01), reason: label);
    }
  });

  testWidgets('respeta los márgenes seguros de arriba y de su lado', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(left: 30, top: 24);
    addTearDown(tester.view.resetPadding);
    await pumpRail(tester, size: kTabletLandscape);
    final railRect = tester.getRect(rail);
    // 80 más el margen de la izquierda; los destinos, a 16 del de arriba.
    expect(railRect.width, 110);
    final first = tester.getRect(zone('Personas'));
    expect(first.top, 24 + 16);
    expect(first.left, railRect.left + 30 + 4);
    final rect = tester.getRect(indicator);
    expect(
      rect.center.dx,
      closeTo(tester.getRect(iconOf('Personas')).center.dx, 0.5),
    );
  });

  testWidgets('en un idioma de derecha a izquierda el filete queda a la '
      'izquierda', (tester) async {
    tester.view
      ..physicalSize = kTabletPortrait
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(AccentId.lavender.palette, Brightness.light),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Row(
              children: [
                RegalosNavRail(
                  semanticLabel: 'Navegación principal',
                  selectedIndex: 0,
                  onSelected: (_) {},
                  destinations: destinations(),
                ),
                const Expanded(child: SizedBox.expand()),
              ],
            ),
          ),
        ),
      ),
    );
    final railRect = tester.getRect(rail);
    expect(railRect.right, kTabletPortrait.width);
    expect(railRect.width, 80);
    final border = tester
        .widgetList<DecoratedBox>(
          find.descendant(of: rail, matching: find.byType(DecoratedBox)),
        )
        .map((box) => (box.decoration as BoxDecoration).border)
        .whereType<BorderDirectional>()
        .single;
    // El final de la fila es ahora la izquierda: el lado del contenido.
    expect(border.end.width, 1);
    expect(border.start, BorderSide.none);
    expect(tester.getRect(find.text('Personas')).center.dx, railRect.center.dx);
  });
}
