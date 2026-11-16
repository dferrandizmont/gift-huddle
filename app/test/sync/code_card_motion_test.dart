import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/motion/success_mark.dart';
import 'package:regalos/features/sync/presentation/code_card.dart';

import '../helpers/pump_app.dart';

/// Las cifras que ruedan se mueven con `FractionalTranslation`.
final _rolling = find.descendant(
  of: find.byType(VerificationCodeCard),
  matching: find.byType(FractionalTranslation),
);

void main() {
  Future<ValueNotifier<bool>> pump(
    WidgetTester tester, {
    bool reduce = false,
    bool confirmed = false,
  }) async {
    final notifier = ValueNotifier<bool>(confirmed);
    addTearDown(notifier.dispose);
    await pumpThemed(
      tester,
      ValueListenableBuilder<bool>(
        valueListenable: notifier,
        builder: (_, value, _) => VerificationCodeCard(
          label: 'Código de verificación',
          code: '123456',
          confirmed: value,
        ),
      ),
      disableAnimations: reduce,
    );
    return notifier;
  }

  group('VerificationCodeCard', () {
    testWidgets('las cifras ruedan desde vacío y acaban quietas', (
      tester,
    ) async {
      await pump(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      // A mitad de la rodadura las cifras se mueven y el número no está entero.
      expect(_rolling, findsWidgets);
      expect(find.text('123 456'), findsNothing);

      await tester.pumpAndSettle();
      expect(_rolling, findsNothing);
      expect(find.text('123 456'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('al confirmar se dibuja un visto en su hueco, sin mover el '
        'título', (tester) async {
      final confirmed = await pump(tester);
      await tester.pumpAndSettle();
      final title = find.text('Código de verificación');
      final rest = tester.getTopLeft(title);
      expect(find.byType(DrawnCheck), findsNothing);

      confirmed.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byType(DrawnCheck), findsOneWidget);
      expect(tester.getTopLeft(title), rest);

      await tester.pumpAndSettle();
      expect(find.byType(DrawnCheck), findsOneWidget);
      expect(tester.getTopLeft(title), rest);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('con «Reducir movimiento» las cifras no se desplazan y el '
        'visto aparece con un fundido', (tester) async {
      final confirmed = await pump(tester, reduce: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_rolling, findsNothing);

      confirmed.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byType(DrawnCheck), findsOneWidget);
      expect(_rolling, findsNothing);

      await tester.pumpAndSettle();
      expect(find.text('123 456'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
