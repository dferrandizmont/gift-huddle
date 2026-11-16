import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/tablet.dart';
import 'appearance_test.dart' show mountAppearance;

/// Posición horizontal (−1 a 1) del recuadro que se desliza en el selector de
/// tema.
double _boxX(WidgetTester tester) => tester
    .widget<FractionallySizedBox>(find.byKey(const ValueKey('theme-box')))
    .alignment
    .resolve(TextDirection.ltr)
    .x;

BoxDecoration _ringOf(WidgetTester tester, String accent) =>
    tester
            .widget<DecoratedBox>(find.byKey(ValueKey('swatch-ring-$accent')))
            .decoration
        as BoxDecoration;

void main() {
  group('Apariencia: movimiento', () {
    testWidgets('el recuadro del tema viaja con muelle hasta el segmento', (
      tester,
    ) async {
      await mountAppearance(tester);
      expect(_boxX(tester), -1);

      await tester.tap(find.text('Dark'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final mid = _boxX(tester);
      expect(mid, greaterThan(-1));
      expect(mid, lessThan(1));

      await tester.pumpAndSettle();
      expect(_boxX(tester), 1);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('en la vista ancha (dos paneles) el recuadro también viaja', (
      tester,
    ) async {
      await mountAppearance(tester, size: kTabletLandscape);
      expect(_boxX(tester), -1);

      await tester.tap(find.text('Light'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(_boxX(tester), inExclusiveRange(-1, 0));
      await tester.pumpAndSettle();
      expect(_boxX(tester), 0);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('el color elegido hace crecer su anillo y suelta el anterior', (
      tester,
    ) async {
      await mountAppearance(tester);
      expect(_ringOf(tester, 'lavender').boxShadow, isNotNull);
      expect(_ringOf(tester, 'sage').boxShadow, isNull);

      await tester.tap(find.bySemanticsLabel('Sage'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      // A mitad de camino el anillo del nuevo ya existe pero no está entero.
      final growing = _ringOf(tester, 'sage').boxShadow!;
      expect(growing.last.spreadRadius, inExclusiveRange(0, 5));

      await tester.pumpAndSettle();
      expect(_ringOf(tester, 'sage').boxShadow!.last.spreadRadius, 5);
      expect(_ringOf(tester, 'lavender').boxShadow, isNull);
    });

    testWidgets('con «Reducir movimiento», saltar de un extremo al otro no '
        'enciende el segmento del medio', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await mountAppearance(tester);
      double fill(int i) =>
          tester.widget<Opacity>(find.byKey(ValueKey('theme-fill-$i'))).opacity;
      expect(fill(0), 1);

      await tester.tap(find.text('Dark'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expect(fill(1), 0);
      expect(fill(0), inExclusiveRange(0, 1));
      expect(fill(2), inExclusiveRange(0, 1));
      // El que se va y el que llega suman uno: se cruzan, no parpadean.
      expect(fill(0) + fill(2), closeTo(1, 0.01));
      await tester.pumpAndSettle();
      expect(fill(2), 1);
      expect(fill(0), 0);
    });

    testWidgets('con «Reducir movimiento» el anillo no crece: solo cambia su '
        'alfa', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await mountAppearance(tester);
      await tester.tap(find.bySemanticsLabel('Sage'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final shadows = _ringOf(tester, 'sage').boxShadow!;
      // El tamaño del anillo ya es el definitivo...
      expect(shadows.last.spreadRadius, 5);
      // ...y solo su color está a medio camino.
      expect(shadows.last.color.a, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(_ringOf(tester, 'sage').boxShadow!.last.color.a, 1);
    });

    testWidgets('con «Reducir movimiento» el recuadro no viaja y no quedan '
        'animaciones', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await mountAppearance(tester);
      expect(find.byKey(const ValueKey('theme-box')), findsNothing);

      await tester.tap(find.text('Dark'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
      // El color elegido sigue marcado.
      expect(_ringOf(tester, 'lavender').boxShadow, isNotNull);
    });
  });
}
