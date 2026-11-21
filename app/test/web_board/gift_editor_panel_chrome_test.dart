// El editor de regalo en el panel de la web de escritorio: campos de 52 de
// alto y «Eliminar regalo» como botón de texto rojo a la izquierda del pie.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/app.dart';
import 'package:regalos/core/theme/regalos_tokens.dart';
import 'package:regalos/core/widgets/danger_button.dart';
import 'package:regalos/features/gifts/presentation/gift_editor_screen.dart';
import 'package:regalos/features/web_device/application/web_app_provider.dart';
import 'package:regalos/features/web_device/application/web_device_providers.dart';
import 'package:regalos/features/web_device/application/web_sync_engine.dart'
    show WebSyncStatus;

import '../helpers/fonts.dart';
import '../helpers/memory_stores.dart';
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

Future<void> _openEditor(WidgetTester tester, FakePhone phone) async {
  await seedSample(tester, phone);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: phone.container,
      child: const RegalosApp(webSession: true),
    ),
  );
  await settle(tester);
  await tester.tap(find.text('Patinete').first);
  await settle(tester);
  expect(find.byType(GiftEditorScreen), findsOneWidget);
}

void main() {
  setUpAll(loadInter);

  screenTest(
    'los campos del editor del panel miden 52 de alto, como los de la hoja',
    (tester, phone) async {
      await _openEditor(tester, phone);
      final fields = find.descendant(
        of: find.byType(GiftEditorScreen),
        matching: find.byType(InputDecorator),
      );
      expect(fields, findsWidgets);
      for (final element in fields.evaluate()) {
        final decorator = element.widget as InputDecorator;
        // La nota es de varias líneas: solo las de una línea miden 52.
        if ((decorator.decoration.labelText ?? '') == 'Nota') {
          continue;
        }
        expect(
          tester.getSize(find.byWidget(decorator)).height,
          52,
          reason: decorator.decoration.labelText,
        );
      }
      expect(tester.takeException(), isNull);
    },
    size: const Size(1920, 960),
    overrides: _web(),
  );

  screenTest(
    '«Eliminar regalo» es un botón de texto rojo a la izquierda de «Cancelar» y '
    '«Guardar»; pregunta y, si se cancela, no borra',
    (tester, phone) async {
      await _openEditor(tester, phone);
      final delete = find.byType(DangerButton);
      expect(delete, findsOneWidget);
      final button = find.descendant(
        of: delete,
        matching: find.byType(TextButton),
      );
      expect(button, findsOneWidget);
      // Sin relleno ni borde, en el rojo de peligro del tema.
      final style = tester.widget<TextButton>(button).style!;
      final tokens = RegalosTokens.of(tester.element(delete));
      expect(style.foregroundColor!.resolve({}), tokens.danger);
      expect(style.backgroundColor, isNull);
      expect(style.side, isNull);
      expect(
        find.descendant(of: delete, matching: find.byType(OutlinedButton)),
        findsNothing,
      );
      // A la izquierda, separado de «Cancelar» y «Guardar» (a la derecha).
      final deleteRect = tester.getRect(delete);
      final cancelRect = tester.getRect(find.text('Cancelar'));
      final saveRect = tester.getRect(
        find.widgetWithText(FilledButton, 'Guardar'),
      );
      expect(deleteRect.right, lessThan(cancelRect.left - 40));
      expect(cancelRect.right, lessThan(saveRect.left));
      expect(
        deleteRect.center.dy,
        moreOrLessEquals(saveRect.center.dy, epsilon: 1),
      );

      await tester.tap(delete);
      await settle(tester);
      expect(find.text('¿Eliminar «Patinete»?'), findsOneWidget);
      await tester.tap(find.text('Cancelar').last);
      await settle(tester);
      expect(find.text('¿Eliminar «Patinete»?'), findsNothing);
      // Sigue el editor y el regalo.
      expect(find.byType(GiftEditorScreen), findsOneWidget);
      expect(find.text('Patinete'), findsWidgets);
      final state = await familyState(tester, phone);
      expect(state.view.gifts.any((g) => g.title == 'Patinete'), isTrue);
      expect(tester.takeException(), isNull);
    },
    size: const Size(1920, 960),
    overrides: _web(),
  );

  // El pie a 1536 × 900 en los tres idiomas: «Eliminar regalo» en una sola línea,
  // a la izquierda y en la misma fila que «Cancelar» y «Guardar».
  for (final (locale, delete, cancel, save) in const [
    ('es', 'Eliminar regalo', 'Cancelar', 'Guardar'),
    ('ca', 'Eliminar el regal', 'Cancel·lar', 'Desar'),
    ('en', 'Delete gift', 'Cancel', 'Save'),
  ]) {
    screenTest(
      'el pie del panel ($locale) lleva «$delete» en una línea, en la fila de '
      '«$cancel» y «$save»',
      (tester, phone) async {
        tester.platformDispatcher.localesTestValue = [Locale(locale)];
        tester.platformDispatcher.localeTestValue = Locale(locale);
        await seedSample(tester, phone);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: phone.container,
            child: const RegalosApp(webSession: true),
          ),
        );
        await settle(tester);
        await tester.tap(find.text('Patinete').first);
        await settle(tester);
        final text = find.descendant(
          of: find.byType(DangerButton),
          matching: find.text(delete),
        );
        expect(text, findsOneWidget);
        // Una línea: el alto del texto es el de «$save».
        expect(
          tester.getSize(text).height,
          tester.getSize(find.text(save).last).height,
        );
        final deleteRect = tester.getRect(find.byType(DangerButton));
        final saveRect = tester.getRect(
          find.widgetWithText(FilledButton, save),
        );
        expect(deleteRect.center.dy, moreOrLessEquals(saveRect.center.dy));
        expect(
          deleteRect.right,
          lessThan(tester.getRect(find.text(cancel)).left),
        );
        expect(tester.takeException(), isNull);
      },
      size: const Size(1536, 900),
      overrides: _web(),
    );
  }

  // Si no caben juntos (texto al 200 %), «Eliminar regalo» pasa a una fila
  // propia encima en vez de partirse.
  screenTest(
    'con el texto al 200 % «Eliminar regalo» sube a su propia fila, sin partirse',
    (tester, phone) async {
      // Al 200 % la barra lateral y la franja de ocasiones del tablero de al
      // lado desbordan (no son del editor): aquí solo se mira el pie.
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        if (!details.toString().contains('overflowed')) {
          previous?.call(details);
        }
      };
      addTearDown(() => FlutterError.onError = previous);
      await _openEditor(tester, phone);
      final text = find.descendant(
        of: find.byType(DangerButton),
        matching: find.text('Eliminar regalo'),
      );
      final line = tester.getSize(text).height;
      expect(line, tester.getSize(find.text('Guardar').last).height);
      final deleteRect = tester.getRect(find.byType(DangerButton));
      final saveRect = tester.getRect(
        find.widgetWithText(FilledButton, 'Guardar'),
      );
      expect(deleteRect.bottom, lessThanOrEqualTo(saveRect.top));
      expect(find.byType(DangerButton), findsOneWidget);
    },
    size: const Size(1536, 900),
    textScale: 2,
    overrides: _web(),
  );
}
