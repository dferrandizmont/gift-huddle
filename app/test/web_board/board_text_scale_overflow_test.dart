// El tablero «Hoy» de la web no desborda con la letra al 200 % en los
// tamaños de portátil y de escritorio habituales.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/app.dart';
import 'package:regalos/features/family/presentation/reparto_grid.dart';
import 'package:regalos/features/web_board/presentation/board_sidebar.dart';
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

void main() {
  setUpAll(loadInter);

  const sizes = <Size>[
    Size(1280, 800),
    Size(1366, 768),
    Size(1440, 900),
    Size(1920, 1080),
  ];

  for (final size in sizes) {
    for (final scale in const [1.0, 2.0]) {
      screenTest(
        'Hoy sin desbordes a ${size.width.toInt()} × ${size.height.toInt()} '
        'con la letra al ${(scale * 100).toInt()} %',
        (tester, phone) async {
          // Se juntan todos los errores de pintado (no solo el primero) para
          // ver cada desborde con su widget.
          final errors = <String>[];
          final previous = FlutterError.onError;
          FlutterError.onError = (d) =>
              errors.add(d.toDiagnosticsNode().toStringDeep());
          try {
            await seedSample(tester, phone);
            await tester.pumpWidget(
              UncontrolledProviderScope(
                container: phone.container,
                child: const RegalosApp(webSession: true),
              ),
            );
            await settle(tester);
            final sidebar = find.byType(BoardSidebar);
            expect(sidebar, findsOneWidget);
            // «Nueva persona» va al final de una lista desplazable: se lleva
            // a la vista para que se construya y se mida.
            final addPerson = find.descendant(
              of: sidebar,
              matching: find.text('Nueva persona'),
            );
            await tester.ensureVisible(addPerson);
            await settle(tester);
            expect(addPerson, findsOneWidget);
            expect(errors, isEmpty, reason: 'Hoy');
            // Las otras secciones de la barra lateral y una persona.
            for (final section in const [
              'Reparto',
              'Ocasiones',
              'Ajustes',
              'Aritz',
            ]) {
              await tester.tap(
                find
                    .descendant(of: sidebar, matching: find.text(section))
                    .first,
              );
              await settle(tester);
              if (section == 'Reparto') {
                expect(find.byType(RepartoGrid), findsOneWidget);
              }
              expect(errors, isEmpty, reason: section);
            }
          } finally {
            FlutterError.onError = previous;
          }
        },
        size: size,
        textScale: scale,
        overrides: _web(),
      );
    }
  }
}
