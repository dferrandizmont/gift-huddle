import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/web_device/presentation/web_gate.dart';
import 'package:regalos/features/web_device/presentation/web_gate_model.dart';
import 'package:regalos/l10n/app_localizations.dart';

import '../../helpers/fonts.dart';
import 'gate_test_support.dart';

const _url =
    'https://web.gifthuddle.app/w#AAAAAAAAAAAAAAAAAAAAAA.BBBBBBBBBBBBBBBBBBBBBA';

Widget _gate(WebGateView view, FakeGateActions actions) => WebGate(
  view: view,
  actions: actions,
  child: const Center(child: Text('La app')),
);

Finder _fieldAt(int i) => find.byType(TextField).at(i);

typedef _Expect = String Function(AppLocalizations);

void main() {
  setUpAll(loadInter);

  group('cada estado se pinta sin desbordes', () {
    // Cada estado y un texto que tiene que verse.
    final states = <(String, WebGateView, _Expect)>[
      (
        'connect',
        const WebGateConnect(url: _url),
        (l) => l.webGateConnectTitle,
      ),
      (
        'comparing',
        const WebGateComparing(code: '482915'),
        (l) => l.webGateCompareTitle,
      ),
      (
        'failed expired',
        const WebGateConnectFailed(WebConnectFailure.expired),
        (l) => l.webGateFailedExpired,
      ),
      (
        'failed mismatch',
        const WebGateConnectFailed(WebConnectFailure.codeMismatch),
        (l) => l.webGateFailedMismatch,
      ),
      (
        'failed rejected',
        const WebGateConnectFailed(WebConnectFailure.rejected),
        (l) => l.webGateFailedRejected,
      ),
      (
        'failed network',
        const WebGateConnectFailed(WebConnectFailure.network),
        (l) => l.webGateFailedNetwork,
      ),
      (
        'choosePin',
        const WebGateChoosePin(personName: 'Nora'),
        (l) => l.webGateChoosePinTitle('Nora'),
      ),
      ('unlock', const WebGateUnlock(), (l) => l.webGateUnlockTitle),
      (
        'unlock wrong',
        const WebGateUnlock(wrongPin: true, attemptsLeft: 3),
        (l) => '${l.webGateWrongPin} ${l.webGateAttemptsLeft(3)}',
      ),
      (
        'unlock wait',
        const WebGateUnlock(
          wrongPin: true,
          attemptsLeft: 1,
          retryAfter: Duration(seconds: 8),
        ),
        (l) => l.webGateWait(8),
      ),
      ('suspended', const WebGateSuspended(), (l) => l.webGateSuspendedTitle),
      (
        'disconnected',
        const WebGateDisconnected(),
        (l) => l.webGateDisconnectedTitle,
      ),
      (
        'disconnected unsent',
        const WebGateDisconnected(unsentChanges: 3),
        (l) => l.webGateDisconnectedUnsent(3),
      ),
      ('otherTab', const WebGateOtherTab(), (l) => l.webGateOtherTabTitle),
      ('damaged', const WebGateDamaged(), (l) => l.webGateDamagedTitle),
      (
        'damaged phone hint',
        const WebGateDamaged(),
        (l) => l.webGateDamagedPhoneHint,
      ),
      ('locked', const WebGateLocked(), (l) => l.appTitle),
      ('open', const WebGateOpen(), (_) => 'La app'),
    ];

    for (final size in [desktopSize, phoneSize]) {
      for (final locale in const ['es', 'ca', 'en']) {
        for (final (name, view, expected) in states) {
          testWidgets('$name · $locale · ${size.width.toInt()}', (
            tester,
          ) async {
            await pumpWeb(
              tester,
              _gate(view, FakeGateActions()),
              locale: Locale(locale),
              size: size,
            );
            expect(tester.takeException(), isNull);
            expect(find.text(expected(l10nOf(tester))), findsOneWidget);
            await unmount(tester);
          });
        }
      }
    }

    testWidgets('oscuro y letra grande a 375 px, sin desbordes', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final view in const <WebGateView>[
        WebGateConnect(url: _url),
        WebGateChoosePin(personName: 'Aritz'),
        WebGateDisconnected(unsentChanges: 2),
        WebGateDamaged(),
      ]) {
        await pumpWeb(
          tester,
          _gate(view, FakeGateActions()),
          size: phoneSize,
          brightness: Brightness.dark,
        );
        expect(tester.takeException(), isNull);
      }
      await unmount(tester);
    });
  });

  group('elegir el PIN: precaución al emparejar', () {
    for (final size in [desktopSize, phoneSize]) {
      for (final locale in const ['es', 'ca', 'en']) {
        testWidgets(
          'la línea y el botón de reiniciar están · $locale · ${size.width.toInt()}',
          (tester) async {
            await pumpWeb(
              tester,
              _gate(
                const WebGateChoosePin(personName: 'Nora'),
                FakeGateActions(),
              ),
              locale: Locale(locale),
              size: size,
            );
            expect(tester.takeException(), isNull);
            final l10n = l10nOf(tester);
            expect(find.text(l10n.webGateChoosePinCheck), findsOneWidget);
            expect(find.text(l10n.webGateStartAgain), findsOneWidget);
            await unmount(tester);
          },
        );
      }
    }

    testWidgets('«Empezar otra vez» pide confirmar y solo entonces reinicia', (
      tester,
    ) async {
      final actions = FakeGateActions();
      await pumpWeb(
        tester,
        _gate(const WebGateChoosePin(personName: 'Nora'), actions),
      );
      final l10n = l10nOf(tester);
      await tester.ensureVisible(find.text(l10n.webGateStartAgain));
      await tester.tap(find.text(l10n.webGateStartAgain));
      await tester.pump(const Duration(milliseconds: 700));
      expect(actions.calls, isEmpty);
      expect(find.text(l10n.webGateRestartTitle), findsOneWidget);
      expect(find.text(l10n.webGateRestartBody), findsOneWidget);

      // Cancelar vuelve al formulario sin reiniciar.
      await tester.tap(find.text(l10n.actionCancel));
      await tester.pump(const Duration(milliseconds: 700));
      expect(actions.calls, isEmpty);
      expect(find.text(l10n.webGateChoosePinCheck), findsOneWidget);

      await tester.ensureVisible(find.text(l10n.webGateStartAgain));
      await tester.tap(find.text(l10n.webGateStartAgain));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(find.text(l10n.webGateRestartConfirm));
      await tester.pump(const Duration(milliseconds: 700));
      expect(actions.calls, ['restartPairing']);
      await unmount(tester);
    });
  });

  group('conectar y comparar', () {
    testWidgets('enseña el QR, los pasos y el código en dos grupos de tres', (
      tester,
    ) async {
      final actions = FakeGateActions();
      await pumpWeb(tester, _gate(const WebGateConnect(url: _url), actions));
      final l10n = l10nOf(tester);
      expect(find.text(l10n.webGateStepOpenApp), findsOneWidget);
      expect(find.text(l10n.webGateConnectStep2), findsOneWidget);
      expect(find.text(l10n.webGateConnectStep3), findsOneWidget);
      expect(find.text(l10n.webGateConnectWaiting), findsOneWidget);
      expect(find.bySemanticsLabel(l10n.showQrLabel), findsOneWidget);

      await pumpWeb(
        tester,
        _gate(const WebGateComparing(code: '482915'), actions),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('482 915'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('«Empezar otra vez» reinicia el emparejamiento', (
      tester,
    ) async {
      final actions = FakeGateActions();
      await pumpWeb(
        tester,
        _gate(const WebGateConnectFailed(WebConnectFailure.expired), actions),
      );
      await tester.tap(find.text(l10nOf(tester).webGateStartAgain));
      await tester.pump();
      expect(actions.calls, ['restartPairing']);
      await unmount(tester);
    });
  });

  group('elegir el PIN', () {
    testWidgets('un PIN que no vale no se envía; uno que vale y coincide, sí', (
      tester,
    ) async {
      final actions = FakeGateActions();
      await pumpWeb(
        tester,
        _gate(const WebGateChoosePin(personName: 'Nora'), actions),
      );
      final l10n = l10nOf(tester);
      final button = find.text(l10n.webGateContinue);

      // Cinco cifras: corto.
      await tester.enterText(_fieldAt(0), '12345');
      await tester.enterText(_fieldAt(1), '12345');
      await tester.tap(button);
      await tester.pump(const Duration(milliseconds: 300));
      expect(actions.calls, isEmpty);

      // Siete caracteres que no son una frase: corto también.
      await tester.enterText(_fieldAt(0), 'abc1234');
      await tester.enterText(_fieldAt(1), 'abc1234');
      await tester.tap(button);
      await tester.pump(const Duration(milliseconds: 300));
      expect(actions.calls, isEmpty);

      // Vale, pero no coincide.
      await tester.enterText(_fieldAt(0), '123456');
      await tester.enterText(_fieldAt(1), '123457');
      await tester.tap(button);
      await tester.pump(const Duration(milliseconds: 300));
      expect(actions.calls, isEmpty);
      expect(find.text(l10n.webGatePinMismatch), findsOneWidget);

      // Coincide.
      await tester.enterText(_fieldAt(1), '123456');
      await tester.tap(button);
      await tester.pump(const Duration(milliseconds: 300));
      expect(actions.calls, ['choosePin:123456']);
      await unmount(tester);
    });

    testWidgets('una frase de 8 caracteres vale y Enter la envía', (
      tester,
    ) async {
      final actions = FakeGateActions();
      await pumpWeb(
        tester,
        _gate(const WebGateChoosePin(personName: 'Leo'), actions),
      );
      await tester.enterText(_fieldAt(0), 'tres gatos');
      await tester.enterText(_fieldAt(1), 'tres gatos');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(actions.calls, ['choosePin:tres gatos']);
      await unmount(tester);
    });

    testWidgets('el campo está oculto y «Mostrar» lo enseña', (tester) async {
      await pumpWeb(
        tester,
        _gate(const WebGateChoosePin(personName: 'Aritz'), FakeGateActions()),
      );
      final l10n = l10nOf(tester);
      bool obscured() => tester.widget<TextField>(_fieldAt(0)).obscureText;
      expect(obscured(), isTrue);
      await tester.tap(find.text(l10n.webGatePinShow).first);
      await tester.pump();
      expect(obscured(), isFalse);
      expect(find.text(l10n.webGatePinHide), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('dice la regla, la pista y de quién es el ordenador', (
      tester,
    ) async {
      await pumpWeb(
        tester,
        _gate(const WebGateChoosePin(personName: 'Nora'), FakeGateActions()),
      );
      final l10n = l10nOf(tester);
      expect(find.text('Este ordenador es de Nora'), findsOneWidget);
      expect(find.text(l10n.webGatePinRule), findsOneWidget);
      expect(find.text(l10n.webGatePinSameHint), findsOneWidget);
      await unmount(tester);
    });
  });

  group('desbloquear', () {
    testWidgets('Enter envía; con el campo vacío no envía nada', (
      tester,
    ) async {
      final actions = FakeGateActions();
      await pumpWeb(tester, _gate(const WebGateUnlock(), actions));
      await tester.tap(_fieldAt(0));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(actions.calls, isEmpty);

      await tester.enterText(_fieldAt(0), 'miPin123');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(actions.calls, ['submitPin:miPin123']);
      await unmount(tester);
    });

    testWidgets('el botón envía', (tester) async {
      final actions = FakeGateActions();
      await pumpWeb(tester, _gate(const WebGateUnlock(), actions));
      await tester.enterText(_fieldAt(0), '246810');
      await tester.tap(find.text(l10nOf(tester).webGateUnlock));
      await tester.pump();
      expect(actions.calls, ['submitPin:246810']);
      await unmount(tester);
    });

    testWidgets(
      'un PIN erróneo vacía el campo y dice cuántos intentos quedan',
      (tester) async {
        final actions = FakeGateActions();
        await pumpWeb(
          tester,
          _gate(const WebGateUnlock(attemptsLeft: 5), actions),
        );
        final l10n = l10nOf(tester);
        expect(find.text(l10n.webGateAttemptsLeft(5)), findsOneWidget);
        await tester.enterText(_fieldAt(0), 'equivocado');

        await pumpWeb(
          tester,
          _gate(const WebGateUnlock(wrongPin: true, attemptsLeft: 4), actions),
        );
        expect(
          find.text('${l10n.webGateWrongPin} ${l10n.webGateAttemptsLeft(4)}'),
          findsOneWidget,
        );
        expect(tester.widget<TextField>(_fieldAt(0)).controller!.text, isEmpty);
        await unmount(tester);
      },
    );

    testWidgets('la cuenta atrás deshabilita el botón hasta llegar a cero', (
      tester,
    ) async {
      final actions = FakeGateActions();
      await pumpWeb(
        tester,
        _gate(const WebGateUnlock(retryAfter: Duration(seconds: 3)), actions),
      );
      final l10n = l10nOf(tester);
      final button = find.widgetWithText(FilledButton, l10n.webGateUnlock);
      expect(find.text(l10n.webGateWait(3)), findsOneWidget);
      expect(tester.widget<FilledButton>(button).onPressed, isNull);

      // Ni Enter envía durante la espera.
      await tester.enterText(_fieldAt(0), '246810');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(actions.calls, isEmpty);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text(l10n.webGateWait(2)), findsOneWidget);
      expect(tester.widget<FilledButton>(button).onPressed, isNull);

      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Espera'), findsNothing);
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);

      await tester.tap(button);
      await tester.pump();
      expect(actions.calls, ['submitPin:246810']);
      await unmount(tester);
    });
  });

  group('suspendida, otra pestaña y desconectada', () {
    testWidgets('suspendida: pasos y «Probar otra vez»', (tester) async {
      final actions = FakeGateActions();
      await pumpWeb(tester, _gate(const WebGateSuspended(), actions));
      final l10n = l10nOf(tester);
      expect(find.text(l10n.webGateSuspendedStep3), findsOneWidget);
      await tester.tap(find.text(l10n.webGateRetry));
      await tester.pump();
      expect(actions.calls, ['retry']);
      await unmount(tester);
    });

    testWidgets('otra pestaña: «Usar aquí»', (tester) async {
      final actions = FakeGateActions();
      await pumpWeb(tester, _gate(const WebGateOtherTab(), actions));
      await tester.tap(find.text(l10nOf(tester).webGateUseHere));
      await tester.pump();
      expect(actions.calls, ['useHere']);
      await unmount(tester);
    });

    testWidgets('desconectada: «Conectar otra vez»', (tester) async {
      final actions = FakeGateActions();
      await pumpWeb(tester, _gate(const WebGateDisconnected(), actions));
      await tester.tap(find.text(l10nOf(tester).webGateReconnect));
      await tester.pump();
      expect(actions.calls, ['reconnect']);
      await unmount(tester);
    });

    testWidgets('desconectada: borrar los datos pide confirmar', (
      tester,
    ) async {
      final actions = FakeGateActions();
      await pumpWeb(
        tester,
        _gate(const WebGateDisconnected(unsentChanges: 2), actions),
      );
      final l10n = l10nOf(tester);
      await tester.tap(find.text(l10n.webGateErase));
      await tester.pump(const Duration(milliseconds: 600));
      expect(actions.calls, isEmpty);
      expect(find.text(l10n.webGateEraseTitle), findsOneWidget);
      expect(find.text(l10n.webGateEraseBodyUnsent), findsOneWidget);

      // Cancelar vuelve y no borra nada.
      await tester.tap(find.text(l10n.actionCancel));
      await tester.pump(const Duration(milliseconds: 600));
      expect(actions.calls, isEmpty);
      expect(find.text(l10n.webGateDisconnectedTitle), findsOneWidget);

      await tester.tap(find.text(l10n.webGateErase));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text(l10n.actionDelete));
      await tester.pump();
      expect(actions.calls, ['eraseComputer']);
      await unmount(tester);
    });
  });

  group('datos dañados', () {
    testWidgets('borrar pide confirmar y solo entonces llama a eraseComputer', (
      tester,
    ) async {
      final actions = FakeGateActions();
      await pumpWeb(tester, _gate(const WebGateDamaged(), actions));
      final l10n = l10nOf(tester);
      expect(find.text(l10n.webGateDamagedBody), findsOneWidget);
      await tester.tap(find.text(l10n.webGateErase));
      await tester.pump(const Duration(milliseconds: 600));
      expect(actions.calls, isEmpty);
      expect(find.text(l10n.webGateEraseTitle), findsOneWidget);

      // Cancelar vuelve y no borra nada.
      await tester.tap(find.text(l10n.actionCancel));
      await tester.pump(const Duration(milliseconds: 600));
      expect(actions.calls, isEmpty);
      expect(find.text(l10n.webGateDamagedTitle), findsOneWidget);

      await tester.tap(find.text(l10n.webGateErase));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text(l10n.actionDelete));
      await tester.pump();
      expect(actions.calls, ['eraseComputer']);
      await unmount(tester);
    });
  });

  group('tapa y sesión abierta', () {
    testWidgets('bloquear tapa de golpe y quita la app del árbol', (
      tester,
    ) async {
      final actions = FakeGateActions();
      await pumpWeb(tester, _gate(const WebGateOpen(), actions));
      expect(find.text('La app'), findsOneWidget);

      await pumpWeb(
        tester,
        _gate(const WebGateLocked(), actions),
        settle: Duration.zero,
      );
      // Un solo fotograma: la app ya no está y la tapa ya se ve entera.
      await tester.pump();
      expect(find.text('La app'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      final l10n = l10nOf(tester);
      expect(find.text(l10n.appTitle), findsOneWidget);
      final fade = tester.widget<FadeTransition>(
        find
            .ancestor(
              of: find.text(l10n.appTitle),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fade.opacity.value, 1);
      await unmount(tester);
    });

    testWidgets('al desbloquear, la tapa se va con un fundido', (tester) async {
      final actions = FakeGateActions();
      await pumpWeb(tester, _gate(const WebGateLocked(), actions));
      await pumpWeb(
        tester,
        _gate(const WebGateUnlock(), actions),
        settle: Duration.zero,
      );
      await tester.pump(const Duration(milliseconds: 60));
      // A mitad de camino la tapa sigue (su marca) y el desbloqueo ya está
      // debajo; al terminar, solo queda el desbloqueo.
      final l10n = l10nOf(tester);
      expect(find.text(l10n.webGateUnlockTitle), findsOneWidget);
      expect(find.text(l10n.appTitle), findsNWidgets(2));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(l10n.appTitle), findsOneWidget);
      await unmount(tester);
    });
  });

  group('movimiento', () {
    testWidgets('sin movimiento reducido el paso nuevo se desliza', (
      tester,
    ) async {
      final xs = await _titleXDuringSwitch(tester, reduce: false);
      expect(xs.mid, isNot(closeTo(xs.end, 0.5)));
      await unmount(tester);
    });

    testWidgets('con movimiento reducido el paso nuevo solo se funde', (
      tester,
    ) async {
      final xs = await _titleXDuringSwitch(tester, reduce: true);
      expect(xs.mid, closeTo(xs.end, 0.01));
      await unmount(tester);
    });

    testWidgets('el PIN erróneo hace temblar el campo, salvo con reducido', (
      tester,
    ) async {
      for (final reduce in [false, true]) {
        final actions = FakeGateActions();
        await pumpWeb(
          tester,
          _gate(const WebGateUnlock(), actions),
          reduce: reduce,
        );
        final before = tester.getTopLeft(find.byType(TextField)).dx;
        await pumpWeb(
          tester,
          _gate(const WebGateUnlock(wrongPin: true), actions),
          reduce: reduce,
          settle: Duration.zero,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        final during = tester.getTopLeft(find.byType(TextField)).dx;
        if (reduce) {
          expect(during, closeTo(before, 0.01));
        } else {
          expect(during, isNot(closeTo(before, 0.5)));
        }
        await unmount(tester);
      }
    });
  });
}

/// La x del título del paso nuevo a mitad de la transición y al final.
Future<({double mid, double end})> _titleXDuringSwitch(
  WidgetTester tester, {
  required bool reduce,
}) async {
  final actions = FakeGateActions();
  await pumpWeb(
    tester,
    _gate(const WebGateConnect(url: _url), actions),
    reduce: reduce,
  );
  await pumpWeb(
    tester,
    _gate(const WebGateComparing(code: '123456'), actions),
    reduce: reduce,
    settle: Duration.zero,
  );
  await tester.pump(const Duration(milliseconds: 60));
  final title = find.text('Comprueba el código');
  final mid = tester.getTopLeft(title).dx;
  await tester.pump(const Duration(seconds: 1));
  final end = tester.getTopLeft(title).dx;
  return (mid: mid, end: end);
}
