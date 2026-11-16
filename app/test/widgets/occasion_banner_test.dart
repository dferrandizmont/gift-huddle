import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/core/widgets/occasion_art.dart';
import 'package:regalos/core/widgets/occasion_banner.dart';

import '../helpers/pump_app.dart';

void main() {
  final themes = [
    ...OccasionTheme.all,
    OccasionTheme.custom(color: 'rose', icon: 'home'),
  ];

  for (final brightness in Brightness.values) {
    testWidgets('la cabecera pinta cada ocasión en ${brightness.name}', (
      tester,
    ) async {
      for (final theme in themes) {
        await pumpThemed(
          tester,
          SizedBox(
            width: 360,
            child: OccasionBanner(
              theme: theme,
              dark: brightness == Brightness.dark,
            ),
          ),
          brightness: brightness,
        );
        expect(tester.takeException(), isNull, reason: theme.id);
        final size = tester.getSize(find.byType(OccasionBanner));
        expect(size.width, 360);
        expect(size.height, closeTo(360 * kArtHeight / kArtWidth, 0.5));
      }
    });
  }

  testWidgets('la cabecera es solo dibujo: no lleva texto ni semántica', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpThemed(
      tester,
      OccasionBanner(theme: OccasionTheme.christmas, dark: false),
    );
    expect(
      find.descendant(
        of: find.byType(OccasionBanner),
        matching: find.byType(Text),
      ),
      findsNothing,
    );
    expect(tester.getSemantics(find.byType(OccasionBanner)).label, isEmpty);
    semantics.dispose();
  });
}
