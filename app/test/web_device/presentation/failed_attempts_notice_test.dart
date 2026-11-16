// Aviso de intentos fallidos desde la última vez, dentro de la app abierta.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/web_device/application/web_app_provider.dart';
import 'package:regalos/features/web_device/application/web_device_providers.dart';
import 'package:regalos/features/web_device/application/web_sync_engine.dart'
    show WebSyncStatus;
import 'package:regalos/features/web_device/presentation/web_status_strip.dart';

import '../../helpers/fonts.dart';
import 'gate_test_support.dart';

WebDeviceState _state(int failed) => WebDeviceState(
  status: WebSyncStatus.confirmed,
  hasRoots: true,
  setAsideChanges: 0,
  persistenceDenied: false,
  lastUnlockFailedAttempts: failed,
);

Widget _page(FakeGateActions actions, int failed) => ProviderScope(
  overrides: [
    webAppProvider.overrideWithValue(true),
    webGateActionsProvider.overrideWithValue(actions),
    webDeviceStateProvider.overrideWithValue(_state(failed)),
  ],
  child: const Scaffold(
    body: Column(
      children: [
        WebStatusStrip(),
        Expanded(child: SizedBox()),
      ],
    ),
  ),
);

Finder _fieldAt(int i) => find.byType(TextField).at(i);

Future<void> _route(WidgetTester tester, [int ms = 600]) async {
  await tester.pump();
  await tester.pump(Duration(milliseconds: ms));
}

void main() {
  setUpAll(loadInter);

  for (final size in [desktopSize, phoneSize]) {
    for (final locale in const ['es', 'ca', 'en']) {
      for (final count in const [1, 3]) {
        testWidgets(
          'el aviso cabe con $count · $locale · ${size.width.toInt()}',
          (tester) async {
            await pumpWeb(
              tester,
              _page(FakeGateActions(), count),
              locale: Locale(locale),
              size: size,
            );
            expect(tester.takeException(), isNull);
            final l10n = l10nOf(tester);
            expect(
              find.text(l10n.webFailedAttemptsNotice(count)),
              findsOneWidget,
            );
            expect(find.text(l10n.webSettingsChangePin), findsOneWidget);
            expect(find.text(l10n.actionUnderstood), findsOneWidget);
          },
        );
      }
    }
  }

  testWidgets('singular y plural en español', (tester) async {
    await pumpWeb(tester, _page(FakeGateActions(), 1));
    expect(
      find.textContaining('Hubo 1 intento fallido de desbloquear'),
      findsOneWidget,
    );
    await pumpWeb(tester, _page(FakeGateActions(), 3));
    expect(
      find.textContaining('Hubo 3 intentos fallidos de desbloquear'),
      findsOneWidget,
    );
  });

  testWidgets('con 0 no sale', (tester) async {
    await pumpWeb(tester, _page(FakeGateActions(), 0));
    final l10n = l10nOf(tester);
    expect(find.textContaining('intento'), findsNothing);
    expect(find.text(l10n.actionUnderstood), findsNothing);
    expect(find.text(l10n.webSettingsChangePin), findsNothing);
  });

  testWidgets('«Entendido» lo cierra y no vuelve a salir en la sesión', (
    tester,
  ) async {
    final actions = FakeGateActions();
    final container = ProviderContainer(
      overrides: [
        webAppProvider.overrideWithValue(true),
        webGateActionsProvider.overrideWithValue(actions),
        webDeviceStateProvider.overrideWithValue(_state(2)),
      ],
    );
    addTearDown(container.dispose);
    Widget strip(Key key) => UncontrolledProviderScope(
      container: container,
      child: Scaffold(
        body: Column(
          children: [
            WebStatusStrip(key: key),
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
    );
    await pumpWeb(tester, strip(const ValueKey('a')));
    final l10n = l10nOf(tester);
    expect(find.text(l10n.webFailedAttemptsNotice(2)), findsOneWidget);
    await tester.tap(find.text(l10n.actionUnderstood));
    await _route(tester, 700);
    expect(find.text(l10n.webFailedAttemptsNotice(2)), findsNothing);
    // Montar la franja de nuevo (otra pantalla) no lo trae de vuelta.
    await pumpWeb(tester, strip(const ValueKey('b')), size: phoneSize);
    expect(find.text(l10n.webFailedAttemptsNotice(2)), findsNothing);
    expect(actions.calls, isEmpty);
  });

  testWidgets('«Cambiar PIN» abre la hoja y, cambiado, cierra el aviso', (
    tester,
  ) async {
    final actions = FakeGateActions();
    await pumpWeb(tester, _page(actions, 3));
    final l10n = l10nOf(tester);
    await tester.tap(find.text(l10n.webSettingsChangePin));
    await _route(tester);
    expect(find.text(l10n.webSettingsChangePinTitle), findsOneWidget);
    await tester.enterText(_fieldAt(0), 'actual123');
    await tester.enterText(_fieldAt(1), 'una frase larga');
    await tester.enterText(_fieldAt(2), 'una frase larga');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _route(tester, 800);
    expect(actions.calls, ['changePin:actual123:una frase larga']);
    expect(find.text(l10n.webSettingsChangePinTitle), findsNothing);
    expect(find.text(l10n.webFailedAttemptsNotice(3)), findsNothing);
    await tester.pump(const Duration(seconds: 6));
  });
}
