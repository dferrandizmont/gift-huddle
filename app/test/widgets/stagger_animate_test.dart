import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/motion/stagger.dart';

import '../helpers/pump_app.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required bool animate}) => pumpThemed(
    tester,
    StaggerScope(
      animate: animate,
      child: const Column(
        children: [
          StaggerItem(index: 0, child: Text('uno')),
          StaggerItem(index: 1, child: Text('dos')),
        ],
      ),
    ),
  );

  testWidgets('con animate falso todo sale entero desde el primer '
      'fotograma', (tester) async {
    await pump(tester, animate: false);
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(StaggerScope),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('con animate (por defecto) entra escalonado', (tester) async {
    await pump(tester, animate: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      find.descendant(
        of: find.byType(StaggerScope),
        matching: find.byType(FadeTransition),
      ),
      findsWidgets,
    );
    await tester.pumpAndSettle();
  });
}
