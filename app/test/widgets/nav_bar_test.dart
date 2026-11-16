import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/core/widgets/regalos_nav_bar.dart';
import 'package:regalos/core/widgets/stroke_icon.dart';

import '../helpers/fonts.dart';
import '../helpers/pump_app.dart';

void main() {
  // Con Inter de verdad: en Ahem las etiquetas no caben y se encogen.
  setUpAll(loadInter);

  Future<void> pumpBar(
    WidgetTester tester, {
    int selected = 0,
    ValueChanged<int>? onSelected,
    Brightness brightness = Brightness.light,
    double textScale = 1,
    String familyLabel = 'Reparto',
  }) async {
    await pumpThemed(
      tester,
      RegalosNavBar(
        semanticLabel: 'Navegación principal',
        selectedIndex: selected,
        onSelected: onSelected ?? (_) {},
        destinations: [
          const NavDestination(icon: AppIcons.people, label: 'Personas'),
          NavDestination(icon: AppIcons.family, label: familyLabel),
          const NavDestination(icon: AppIcons.occasions, label: 'Ocasiones'),
          const NavDestination(icon: AppIcons.settings, label: 'Ajustes'),
        ],
      ),
      brightness: brightness,
      textScale: textScale,
    );
  }

  /// El recuadro pastel que se desliza detrás del icono del destino activo.
  final indicator = find.byKey(const ValueKey('nav-indicator'));

  /// El centro horizontal del destino [i] de [count] en una barra de 390.
  double centerOf(int i, int count) => 390 / count * (i + 0.5);

  for (final brightness in Brightness.values) {
    testWidgets(
      'el destino activo lleva un recuadro pastel de radio 8 detrás del icono '
      'y no hay raya (${brightness.name})',
      (tester) async {
        await pumpBar(tester, selected: 1, brightness: brightness);
        final t = RegalosTokens.of(tester.element(find.byType(RegalosNavBar)));
        // Ya no hay línea de tinta sobre el destino.
        expect(find.byKey(const ValueKey('nav-line-Reparto')), findsNothing);
        // 64 × 30, centrado sobre el destino activo y sobre su icono.
        final rect = tester.getRect(indicator);
        expect(rect.width, 64);
        expect(rect.height, 30);
        expect(rect.center.dx, closeTo(centerOf(1, 4), 0.5));
        final icon = tester.getRect(
          find.descendant(
            of: find.ancestor(
              of: find.text('Reparto'),
              matching: find.byType(InkWell),
            ),
            matching: find.byType(StrokeIcon),
          ),
        );
        expect(rect.center.dx, closeTo(icon.center.dx, 0.5));
        expect(rect.center.dy, closeTo(icon.center.dy, 0.5));
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
        // Etiqueta en negrita y en tinta; el resto, no.
        final style = tester.widget<Text>(find.text('Reparto')).style!;
        expect(style.fontWeight, FontWeight.w600);
        expect(style.fontSize, 12);
        expect(style.color, t.ink);
        final other = tester.widget<Text>(find.text('Personas')).style!;
        expect(other.fontWeight, FontWeight.w500);
        expect(other.color, t.textSecondary);
      },
    );
  }

  testWidgets('cada destino mide al menos 44 px y se puede tocar entero', (
    tester,
  ) async {
    final taps = <int>[];
    await pumpBar(tester, onSelected: taps.add);
    for (final label in ['Personas', 'Reparto', 'Ocasiones', 'Ajustes']) {
      final item = find.ancestor(
        of: find.text(label),
        matching: find.byType(InkWell),
      );
      final size = tester.getSize(item);
      expect(size.width, greaterThanOrEqualTo(44), reason: label);
      expect(size.height, greaterThanOrEqualTo(44), reason: label);
    }
    await tester.tap(find.text('Ocasiones'));
    // Un toque en la esquina del destino también cuenta.
    final item = tester.getRect(
      find.ancestor(of: find.text('Ajustes'), matching: find.byType(InkWell)),
    );
    await tester.tapAt(item.topCenter + const Offset(0, 4));
    expect(taps, [2, 3]);
  });

  testWidgets('la barra mide 68 px y el recuadro se desliza al otro destino', (
    tester,
  ) async {
    int selected = 0;
    late StateSetter set;
    await pumpThemed(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          set = setState;
          return RegalosNavBar(
            semanticLabel: 'Navegación principal',
            selectedIndex: selected,
            onSelected: (i) => setState(() => selected = i),
            destinations: const [
              NavDestination(icon: AppIcons.people, label: 'Personas'),
              NavDestination(icon: AppIcons.family, label: 'Reparto'),
            ],
          );
        },
      ),
    );
    expect(tester.getSize(find.byType(RegalosNavBar)).height, 68);
    expect(tester.getRect(indicator).center.dx, closeTo(centerOf(0, 2), 0.5));
    await tester.tap(find.text('Reparto'));
    // A mitad del muelle el recuadro va entre los dos destinos.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final mid = tester.getRect(indicator).center.dx;
    expect(mid, greaterThan(centerOf(0, 2) + 1));
    expect(mid, lessThan(centerOf(1, 2) + 1));
    await tester.pumpAndSettle();
    expect(tester.getRect(indicator).center.dx, closeTo(centerOf(1, 2), 0.5));
    set(() {});
  });

  testWidgets('con «Reducir movimiento» no hay deslizamiento: se funde', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpBar(tester, selected: 1);
    final t = RegalosTokens.of(tester.element(find.byType(RegalosNavBar)));
    expect(indicator, findsNothing);
    // El recuadro del destino activo está pintado en su sitio.
    bool pill(String label) {
      final box = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.ancestor(
            of: find.text(label),
            matching: find.byType(InkWell),
          ),
          matching: find.byType(AnimatedContainer),
        ),
      );
      return (box.decoration! as BoxDecoration).color == t.fill;
    }

    expect(pill('Reparto'), isTrue);
    expect(pill('Personas'), isFalse);
    // Se funde en 150 ms.
    final box = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.ancestor(
          of: find.text('Reparto'),
          matching: find.byType(InkWell),
        ),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(box.duration, RegalosMotion.fade);
  });

  testWidgets('el activo se lee como seleccionado para los lectores', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpBar(tester, selected: 1);
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
    handle.dispose();
  });

  testWidgets('un nombre largo como «Who gives what» cabe sin desbordar', (
    tester,
  ) async {
    await pumpBar(
      tester,
      familyLabel: 'Who gives what',
      textScale: 1.3,
      selected: 1,
    );
    expect(tester.takeException(), isNull);
  });
}
