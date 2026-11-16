import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/web_device/presentation/web_gate.dart';
import 'package:regalos/features/web_device/presentation/web_gate_model.dart';

import '../../helpers/fonts.dart';
import 'gate_test_support.dart';

Widget _gate(
  WebGateView view,
  FakeGateActions actions, {
  Future<void> Function()? onConfirm,
  Future<void> Function()? onReject,
}) => WebGate(
  view: view,
  actions: actions,
  onConfirmCode: onConfirm ?? () async {},
  onRejectCode: onReject ?? () async {},
  child: const SizedBox.shrink(),
);

void main() {
  setUpAll(loadInter);

  group('comparar el código', () {
    testWidgets('sin confirmar: dos botones separados y sin «esperando»', (
      tester,
    ) async {
      final actions = FakeGateActions();
      await pumpWeb(
        tester,
        _gate(const WebGateComparing(code: '482915'), actions),
      );
      final l10n = l10nOf(tester);
      final match = find.widgetWithText(FilledButton, l10n.pairingV2Match);
      final noMatch = find.widgetWithText(
        OutlinedButton,
        l10n.pairingV2NoMatch,
      );
      expect(match, findsOneWidget);
      expect(noMatch, findsOneWidget);
      expect(find.text(l10n.webGateCompareWaiting), findsNothing);
      expect(find.text(l10n.webGateCompareConfirmed), findsNothing);
      expect(find.text(l10n.webGateStartAgain), findsOneWidget);

      final a = tester.getRect(match);
      final b = tester.getRect(noMatch);
      expect(
        b.top - a.bottom,
        greaterThanOrEqualTo(8),
        reason: 'los botones no pueden ir pegados',
      );
      expect(a.overlaps(b), isFalse);
      await unmount(tester);
    });

    testWidgets('confirmado: sin botones, con el aviso y la espera', (
      tester,
    ) async {
      final actions = FakeGateActions();
      await pumpWeb(
        tester,
        _gate(const WebGateComparing(code: '482915', confirmed: true), actions),
      );
      final l10n = l10nOf(tester);
      expect(find.text(l10n.pairingV2Match), findsNothing);
      expect(find.text(l10n.pairingV2NoMatch), findsNothing);
      expect(find.text(l10n.webGateCompareConfirmed), findsOneWidget);
      expect(find.text(l10n.webGateCompareWaiting), findsOneWidget);
      expect(find.text(l10n.webGateStartAgain), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('al pulsar «Coinciden» con la acción aún pendiente ya se '
        've el estado confirmado', (tester) async {
      final actions = FakeGateActions();
      final pending = Completer<void>();
      var confirmed = 0;
      await pumpWeb(
        tester,
        _gate(
          const WebGateComparing(code: '482915'),
          actions,
          onConfirm: () {
            confirmed++;
            return pending.future;
          },
        ),
      );
      final l10n = l10nOf(tester);
      await tester.tap(find.text(l10n.pairingV2Match));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(confirmed, 1);
      expect(find.text(l10n.pairingV2Match), findsNothing);
      expect(find.text(l10n.webGateCompareConfirmed), findsOneWidget);
      expect(find.text(l10n.webGateCompareWaiting), findsOneWidget);
      pending.complete();
      await tester.pump();
      await unmount(tester);
    });

    testWidgets('si la acción falla, vuelven los botones', (tester) async {
      final actions = FakeGateActions();
      await pumpWeb(
        tester,
        _gate(
          const WebGateComparing(code: '482915'),
          actions,
          onConfirm: () async => throw StateError('falló'),
        ),
      );
      final l10n = l10nOf(tester);
      await tester.tap(find.text(l10n.pairingV2Match));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(l10n.pairingV2Match), findsOneWidget);
      expect(find.text(l10n.webGateCompareConfirmed), findsNothing);
      await unmount(tester);
    });

    testWidgets('«No coinciden» llama al motor', (tester) async {
      final actions = FakeGateActions();
      var rejected = 0;
      await pumpWeb(
        tester,
        _gate(
          const WebGateComparing(code: '482915'),
          actions,
          onReject: () async => rejected++,
        ),
      );
      await tester.tap(find.text(l10nOf(tester).pairingV2NoMatch));
      await tester.pump();
      expect(rejected, 1);
      await unmount(tester);
    });

    testWidgets('con «Reducir movimiento» el cambio también se hace', (
      tester,
    ) async {
      final actions = FakeGateActions();
      await pumpWeb(
        tester,
        _gate(const WebGateComparing(code: '482915'), actions),
        reduce: true,
      );
      await pumpWeb(
        tester,
        _gate(const WebGateComparing(code: '482915', confirmed: true), actions),
        reduce: true,
      );
      final l10n = l10nOf(tester);
      expect(find.text(l10n.pairingV2Match), findsNothing);
      expect(find.text(l10n.webGateCompareConfirmed), findsOneWidget);
      await unmount(tester);
    });
  });

  group('fallo: el móvil canceló', () {
    testWidgets('tiene su texto y «Empezar otra vez»', (tester) async {
      final actions = FakeGateActions();
      await pumpWeb(
        tester,
        _gate(const WebGateConnectFailed(WebConnectFailure.cancelled), actions),
      );
      final l10n = l10nOf(tester);
      expect(find.text(l10n.webGateFailedCancelled), findsOneWidget);
      expect(find.text(l10n.webGateFailedExpired), findsNothing);
      await tester.tap(find.text(l10n.webGateStartAgain));
      await tester.pump();
      expect(actions.calls, contains('restartPairing'));
      await unmount(tester);
    });
  });
}
