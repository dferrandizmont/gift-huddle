import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/web_device/presentation/set_aside_notice.dart';
import 'package:regalos/features/web_device/presentation/web_gate_model.dart';
import 'package:regalos/features/web_device/presentation/web_settings_section.dart';

import '../../helpers/fonts.dart';
import 'gate_test_support.dart';

Widget _page(FakeGateActions actions, {bool denied = false, int aside = 0}) =>
    Scaffold(
      body: ListView(
        children: [
          SetAsideNotice(count: aside),
          WebSettingsSection(actions: actions, persistenceDenied: denied),
        ],
      ),
    );

Finder _fieldAt(int i) => find.byType(TextField).at(i);

/// El primer fotograma arranca la ruta (o su cierre); el segundo la deja correr.
Future<void> _route(WidgetTester tester, [int ms = 600]) async {
  await tester.pump();
  await tester.pump(Duration(milliseconds: ms));
}

void main() {
  setUpAll(loadInter);

  for (final size in [desktopSize, phoneSize]) {
    for (final locale in const ['es', 'ca', 'en']) {
      testWidgets(
        'la sección y el aviso caben · $locale · ${size.width.toInt()}',
        (tester) async {
          await pumpWeb(
            tester,
            _page(FakeGateActions(), denied: true, aside: 3),
            locale: Locale(locale),
            size: size,
          );
          expect(tester.takeException(), isNull);
          final l10n = l10nOf(tester);
          expect(find.text(l10n.webSettingsChangePin), findsOneWidget);
          expect(find.text(l10n.webSettingsLockNow), findsOneWidget);
          expect(find.text(l10n.webSettingsForget), findsOneWidget);
          expect(find.text(l10n.webSettingsPersistenceDenied), findsOneWidget);
          expect(find.text(l10n.webSetAsideNotice(3)), findsOneWidget);
        },
      );
    }
  }

  testWidgets('sin persistencia denegada no hay aviso del navegador', (
    tester,
  ) async {
    await pumpWeb(tester, _page(FakeGateActions()));
    expect(
      find.text(l10nOf(tester).webSettingsPersistenceDenied),
      findsNothing,
    );
    expect(find.textContaining('persona protegida'), findsNothing);
  });

  testWidgets('el aviso de cambios apartados usa el singular y el plural', (
    tester,
  ) async {
    await pumpWeb(tester, _page(FakeGateActions(), aside: 1));
    final l10n = l10nOf(tester);
    expect(find.text(l10n.webSetAsideNotice(1)), findsOneWidget);
    expect(find.textContaining('Hay 1 cambio que no se puede'), findsOneWidget);
    await pumpWeb(tester, _page(FakeGateActions(), aside: 4));
    expect(
      find.textContaining('Hay 4 cambios que no se pueden subir'),
      findsOneWidget,
    );
  });

  testWidgets('«Bloquear ahora» bloquea', (tester) async {
    final actions = FakeGateActions();
    await pumpWeb(tester, _page(actions));
    await tester.tap(find.text(l10nOf(tester).webSettingsLockNow));
    await tester.pump();
    expect(actions.calls, ['lock']);
  });

  group('olvidar este ordenador', () {
    testWidgets('exige confirmar: cancelar no hace nada, confirmar olvida', (
      tester,
    ) async {
      final actions = FakeGateActions();
      await pumpWeb(tester, _page(actions));
      final l10n = l10nOf(tester);

      await tester.tap(find.text(l10n.webSettingsForget));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(l10n.webSettingsForgetTitle), findsOneWidget);
      expect(find.text(l10n.webSettingsForgetBody), findsOneWidget);
      expect(actions.calls, isEmpty);

      await tester.tap(find.text(l10n.actionCancel));
      await _route(tester);
      expect(find.text(l10n.webSettingsForgetTitle), findsNothing);
      expect(actions.calls, isEmpty);

      await tester.tap(find.text(l10n.webSettingsForget));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text(l10n.webSettingsForgetConfirm));
      await _route(tester);
      expect(actions.calls, ['forgetComputer']);
    });

    testWidgets('tocar fuera del diálogo tampoco olvida', (tester) async {
      final actions = FakeGateActions();
      await pumpWeb(tester, _page(actions));
      await tester.tap(find.text(l10nOf(tester).webSettingsForget));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tapAt(const Offset(10, 10));
      await _route(tester);
      expect(actions.calls, isEmpty);
    });
  });

  group('cambiar el PIN', () {
    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.text(l10nOf(tester).webSettingsChangePin));
      // El primer fotograma arranca la ruta; el segundo la deja subir.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    testWidgets('un PIN nuevo que no vale o que no coincide no se envía', (
      tester,
    ) async {
      final actions = FakeGateActions();
      await pumpWeb(tester, _page(actions));
      final l10n = l10nOf(tester);
      await openSheet(tester);
      final save = find.text(l10n.actionSave);

      await tester.enterText(_fieldAt(0), 'actual123');
      await tester.enterText(_fieldAt(1), '123');
      await tester.enterText(_fieldAt(2), '123');
      await tester.tap(save);
      await tester.pump(const Duration(milliseconds: 300));
      expect(actions.calls, isEmpty);

      await tester.enterText(_fieldAt(1), '654321');
      await tester.enterText(_fieldAt(2), '654322');
      await tester.tap(save);
      await tester.pump(const Duration(milliseconds: 300));
      expect(actions.calls, isEmpty);
      expect(find.text(l10n.webGatePinMismatch), findsOneWidget);

      await tester.enterText(_fieldAt(0), '');
      await tester.enterText(_fieldAt(2), '654321');
      await tester.tap(save);
      await tester.pump(const Duration(milliseconds: 300));
      expect(actions.calls, isEmpty);
    });

    testWidgets('con el actual equivocado avisa y no se cierra', (
      tester,
    ) async {
      final actions = FakeGateActions()
        ..changeResult = WebPinChangeResult.wrongCurrent;
      await pumpWeb(tester, _page(actions));
      final l10n = l10nOf(tester);
      await openSheet(tester);
      await tester.enterText(_fieldAt(0), 'actual123');
      await tester.enterText(_fieldAt(1), '654321');
      await tester.enterText(_fieldAt(2), '654321');
      await tester.tap(find.text(l10n.actionSave));
      await tester.pump(const Duration(milliseconds: 300));
      expect(actions.calls, ['changePin:actual123:654321']);
      expect(find.text(l10n.webSettingsCurrentWrong), findsOneWidget);
      expect(find.text(l10n.webSettingsChangePinTitle), findsOneWidget);
    });

    testWidgets('cambiado: cierra la hoja y lo dice', (tester) async {
      final actions = FakeGateActions();
      await pumpWeb(tester, _page(actions));
      final l10n = l10nOf(tester);
      await openSheet(tester);
      await tester.enterText(_fieldAt(0), 'actual123');
      await tester.enterText(_fieldAt(1), 'una frase larga');
      await tester.enterText(_fieldAt(2), 'una frase larga');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _route(tester, 800);
      expect(actions.calls, ['changePin:actual123:una frase larga']);
      expect(find.text(l10n.webSettingsChangePinTitle), findsNothing);
      expect(find.text(l10n.webSettingsPinChanged), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });
  });
}
