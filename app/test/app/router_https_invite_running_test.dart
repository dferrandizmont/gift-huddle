import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/platform/link_source.dart';
import 'package:regalos/features/sync/invites/incoming_invite.dart';

import '../helpers/screens.dart';
import '../platform/link_source_test.dart' show FakeLinks;

// F8: con la app abierta, un enlace de invitación https no enseña la pantalla
// roja del router: se queda donde está y el enlace lo recibe `app_links`.
void main() {
  const id = 'CCCCCCCCCCCCCCCCCCCCCC';
  final links = FakeLinks(null);

  for (final host in ['gifthuddle.app', 'gifthuddle.retired.example']) {
    screenTest(
      'una invitación https con la app abierta no cambia de pantalla y la recibe '
      'el receptor de enlaces solo acepta el host actual ($host)',
      (tester, phone) async {
        await bareFamily(tester, phone);
        await pumpRegalos(tester, phone);
        final router = phone.container.read(routerProvider);
        router.go(AppRoutes.occasions);
        await settle(tester);

        // El intent que Flutter entrega a go_router con la app en marcha.
        await router.routeInformationProvider.didPushRouteInformation(
          RouteInformation(uri: Uri.parse('https://$host/i#$id')),
        );
        await settle(tester);

        expect(router.state.uri.toString(), AppRoutes.occasions);
        expect(router.routerDelegate.currentConfiguration.isError, isFalse);
        expect(find.textContaining('GoException'), findsNothing);
        expect(find.textContaining('Page Not Found'), findsNothing);
        expect(tester.takeException(), isNull);

        // El mismo enlace llega por `app_links` y abre el flujo de invitación.
        // (La interfaz lo consume al abrir el flujo: se mira lo que recibe.)
        final received = <String?>[];
        final sub = phone.container.listen<String?>(
          incomingInviteProvider,
          (_, next) => received.add(next),
          fireImmediately: true,
        );
        addTearDown(sub.close);
        links.controller.add('https://$host/i#$id');
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        expect(
          received,
          host == 'gifthuddle.app' ? contains(id) : isNot(contains(id)),
        );
      },
      syncHost: null,
      overrides: [linkSourceProvider.overrideWithValue(links)],
    );
  }
}
