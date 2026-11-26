// El editor de regalo en el panel del tablero de la web de escritorio, en el
// navegador de la persona de la web: elegirse a sí misma en «Para quién» no
// deja guardar un regalo (solo deseos), igual que en el móvil (ADR 0010): el
// panel se cierra y se abre el formulario de deseos con el borrador (título,
// ocasión, talla, enlace y descripción; nunca la nota ni los precios).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/app.dart';
import 'package:regalos/core/sync/wish.dart' show VisibleWishPatch;
import 'package:regalos/features/family/application/wish_providers.dart';
import 'package:regalos/features/family/application/wish_service.dart';
import 'package:regalos/features/gifts/presentation/gift_editor_screen.dart';
import 'package:regalos/features/gifts/presentation/wish_editor.dart'
    show WishEditor;
import 'package:regalos/features/web_board/application/gift_editor_panel.dart';
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

/// Un servicio de deseos que solo apunta lo que se crea.
class _Service implements WishService {
  final List<String> calls = [];

  @override
  bool get canSuggest => true;

  @override
  bool get canConvertPlan => true;

  @override
  Future<WishResult> createOwn(VisibleWishPatch patch) async {
    calls.add('create:${patch.title}');
    return const WishResult.ok();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(loadInter);

  final service = _Service();
  screenTest(
    'en el panel del tablero de 1280 × 800 con varias personas, elegirse a sí '
    'misma en «Para quién» cierra el panel y abre el deseo con el borrador, '
    'sin nota ni precios, y no guarda nada hasta «Guardar»',
    (tester, phone) async {
      service.calls.clear();
      await seedSample(tester, phone);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: phone.container,
          child: const RegalosApp(webSession: true),
        ),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey<String>('board-add-gift')));
      await settle(tester);
      expect(find.byType(GiftEditorScreen), findsOneWidget);
      expect(phone.container.read(giftEditorPanelProvider).isOpen, isTrue);

      await tester.enterText(
        find
            .descendant(
              of: find.byType(GiftEditorScreen),
              matching: find.byType(TextField),
            )
            .first,
        'Patines',
      );
      final note = find.byKey(const ValueKey<String>('gift-note'));
      await openMoreDetails(tester);
      await tester.scrollUntilVisible(
        note,
        200,
        scrollable: find
            .descendant(
              of: find.byType(GiftEditorScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.enterText(note, 'ya comprado, 80 €');
      await tester.scrollUntilVisible(
        find.bySemanticsLabel(RegExp(r'^Para quién')),
        -200,
        scrollable: find
            .descendant(
              of: find.byType(GiftEditorScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.bySemanticsLabel(RegExp(r'^Para quién')));
      await settle(tester);
      await tester.tap(find.text('Nora').last);
      await settle(tester);

      // El panel se cierra y el formulario no queda con la persona elegida.
      expect(phone.container.read(giftEditorPanelProvider).isOpen, isFalse);
      expect(find.byType(GiftEditorScreen), findsNothing);
      expect(find.text('Nuevo deseo'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find
                  .descendant(
                    of: find.byType(WishEditor),
                    matching: find.byType(TextField),
                  )
                  .first,
            )
            .controller!
            .text,
        'Patines',
      );
      expect(find.text('ya comprado, 80 €', skipOffstage: false), findsNothing);
      expect(find.textContaining('Previsto'), findsNothing);
      expect(service.calls, isEmpty);

      await tester.tap(find.text('Guardar'));
      await settle(tester);
      expect(service.calls, ['create:Patines']);
      expect(tester.takeException(), isNull);
    },
    size: const Size(1280, 800),
    overrides: <Override>[
      webAppProvider.overrideWithValue(true),
      webGateActionsProvider.overrideWithValue(FakeGateActions()),
      webDeviceStateProvider.overrideWithValue(_confirmed),
      wishServiceProvider.overrideWithValue(service),
      wishReaderProvider.overrideWithValue('nora'),
    ],
  );
}
