// «Cambiar fecha» en la cabecera de una ocasión de la web, con el editor de
// regalo abierto en el panel lateral y su campo con foco: el calendario no
// devuelve el foco al campo al cerrarse (confirmando o cancelando), vuelve al
// botón, y Tab sigue hacia «Editar ocasión».
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/app.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/widgets/header_button.dart';
import 'package:regalos/features/web_device/application/web_app_provider.dart';
import 'package:regalos/features/web_device/application/web_device_providers.dart';
import 'package:regalos/features/web_device/application/web_sync_engine.dart'
    show WebSyncStatus;

import '../helpers/fonts.dart';
import '../helpers/screens.dart';
import '../web_device/presentation/gate_test_support.dart';

const _confirmed = WebDeviceState(
  status: WebSyncStatus.confirmed,
  hasRoots: true,
  setAsideChanges: 0,
  persistenceDenied: false,
);

List<Override> _web() => [
  webAppProvider.overrideWithValue(true),
  webGateActionsProvider.overrideWithValue(FakeGateActions()),
  webDeviceStateProvider.overrideWithValue(_confirmed),
];

final _changeDate = find.byKey(const ValueKey<String>('board-change-date'));

/// Los elementos del foco primario y de sus ancestros.
List<Element> _focusChain() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return const [];
  final chain = <Element>[context as Element];
  context.visitAncestorElements((e) {
    chain.add(e);
    return true;
  });
  return chain;
}

bool _textHasFocus() => _focusChain().any((e) => e.widget is EditableText);

bool _focusIn(Element element) => _focusChain().contains(element);

void main() {
  setUpAll(loadInter);

  for (final confirm in [true, false]) {
    screenTest(
      'con el editor de regalo enfocado, ${confirm ? 'confirmar' : 'cancelar'} '
      'el calendario devuelve el foco a «Cambiar fecha»',
      (tester, phone) async {
        await seedSample(tester, phone);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: phone.container,
            child: const RegalosApp(webSession: true),
          ),
        );
        await settle(tester);
        phone.container.read(routerProvider).go('/occasions/seed-santa');
        await settle(tester);

        // El editor de regalo en el panel lateral, con el título enfocado.
        await tester.tap(
          find.byKey(const ValueKey<String>('board-occasion-add-gift')),
        );
        await settle(tester);
        final title = find.widgetWithText(TextField, 'Regalo').first;
        await tester.enterText(title, 'Bicicleta');
        await tester.pump();
        expect(_textHasFocus(), isTrue);

        final button = tester.element(_changeDate);
        await tester.tap(_changeDate);
        await settle(tester);
        expect(find.byType(DatePickerDialog), findsOneWidget);
        final buttons = find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(TextButton),
        );
        await tester.tap(confirm ? buttons.last : buttons.first);
        await settle(tester);

        expect(find.byType(DatePickerDialog), findsNothing);
        expect(_textHasFocus(), isFalse);
        expect(_focusIn(button), isTrue);
        // Tab sigue hacia «Editar ocasión».
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(_focusIn(button), isFalse);
        expect(_textHasFocus(), isFalse);
        final edit = find.byWidgetPredicate(
          (w) => w is HeaderIconButton && w.label == 'Editar ocasión',
        );
        expect(_focusIn(tester.element(edit)), isTrue);
      },
      size: const Size(1920, 1000),
      overrides: _web(),
    );
  }
}
