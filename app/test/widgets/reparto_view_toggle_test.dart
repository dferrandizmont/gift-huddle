import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/features/family/application/reparto_view_provider.dart';
import 'package:regalos/features/family/presentation/reparto_view_toggle.dart';

import '../helpers/pump_app.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final brightness in Brightness.values) {
    for (final reduce in [false, true]) {
      testWidgets('la opción elegida va con selection y un borde a 3:1 '
          '(${brightness.name}, reducir movimiento: $reduce)', (tester) async {
        await pumpThemed(
          tester,
          RepartoViewToggle(view: RepartoView.grid, onChanged: (_) {}),
          brightness: brightness,
          disableAnimations: reduce,
        );
        final t = RegalosTokens.of(
          tester.element(find.byType(RepartoViewToggle)),
        );
        final container = tester.widget<DecoratedBox>(
          find.byKey(kRepartoViewToggleKey),
        );
        final surface = (container.decoration as BoxDecoration).color!;
        expect(surface, t.surface);
        // El indicador (o, con «Reducir movimiento», el botón elegido).
        final indicator = reduce
            ? tester
                  .widgetList<AnimatedContainer>(
                    find.descendant(
                      of: find.byKey(kRepartoViewToggleKey),
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .map((c) => c.decoration! as BoxDecoration)
                  .firstWhere((d) => d.color == t.selection)
            : (tester
                      .widget<DecoratedBox>(
                        find.byKey(
                          const ValueKey<String>('repartoViewIndicator'),
                        ),
                      )
                      .decoration
                  as BoxDecoration);
        expect(indicator.color, t.selection);
        final border = (indicator.border! as Border).top.color;
        expect(border, t.selectionEdge);
        expect(
          _contrast(border, surface),
          greaterThanOrEqualTo(3),
          reason: 'borde del elegido sobre la superficie',
        );
      });
    }
  }
}
