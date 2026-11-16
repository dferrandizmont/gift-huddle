import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/core/widgets/gift_segments.dart';

import '../helpers/pump_app.dart';

void main() {
  const ink = Color(0xFF4B3FB0);

  Color colorOf(WidgetTester tester, Finder f) =>
      (tester.widget<Container>(f).decoration! as BoxDecoration).color!;

  testWidgets('un segmento por regalo y se rellenan los comprados', (
    tester,
  ) async {
    await pumpThemed(
      tester,
      const SizedBox(
        width: 200,
        child: GiftSegments(total: 5, done: 2, color: ink),
      ),
    );
    final full = find.byKey(const ValueKey('segment-full'));
    final empty = find.byKey(const ValueKey('segment-empty'));
    expect(full, findsNWidgets(2));
    expect(empty, findsNWidgets(3));
    final t = RegalosTokens.of(tester.element(find.byType(GiftSegments)));
    expect(colorOf(tester, full.first), ink);
    expect(colorOf(tester, empty.first), t.track);
    // Todos miden lo mismo y 5 de alto.
    expect(tester.getSize(full.first).height, RegalosSizes.segmentHeight);
    expect(tester.getSize(full.first).width, tester.getSize(empty.first).width);
  });

  testWidgets('todo comprado rellena todos y ninguno comprado, ninguno', (
    tester,
  ) async {
    await pumpThemed(
      tester,
      const SizedBox(
        width: 200,
        child: GiftSegments(total: 3, done: 3, color: ink),
      ),
    );
    expect(find.byKey(const ValueKey('segment-full')), findsNWidgets(3));
    expect(find.byKey(const ValueKey('segment-empty')), findsNothing);
  });
}
