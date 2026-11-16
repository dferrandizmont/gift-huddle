import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:regalos/app/router.dart';

import '../helpers/screens.dart';

void main() {
  const documents = [
    'content://com.android.providers.downloads.documents/document/x.gifthuddle',
    'file:///storage/emulated/0/Download/x.gifthuddle',
  ];

  for (final location in documents) {
    for (final hasFamily in [false, true]) {
      screenTest('cold start at $location, family: $hasFamily', (
        tester,
        phone,
      ) async {
        tester.platformDispatcher.defaultRouteNameTestValue = location;
        if (hasFamily) {
          await bareFamily(tester, phone);
        }
        await pumpRegalos(tester, phone);

        final router = phone.container.read(routerProvider);
        expect(
          router.state.uri.toString(),
          hasFamily ? AppRoutes.people : AppRoutes.welcome,
        );
        expect(router.routerDelegate.currentConfiguration.isError, isFalse);
        expect(tester.takeException(), isNull);
        expect(
          find.bySemanticsLabel('Navegación principal'),
          hasFamily ? findsOneWidget : findsNothing,
        );
      });
    }

    screenTest('$location preserves the current screen and query', (
      tester,
      phone,
    ) async {
      await bareFamily(tester, phone);
      await pumpRegalos(tester, phone);
      final router = phone.container.read(routerProvider);
      const previous = '/settings/backup?from=files';
      router.go(previous);
      await settle(tester);

      // Emula el intent que Flutter entrega con la app ya abierta.
      await router.routeInformationProvider.didPushRouteInformation(
        RouteInformation(uri: Uri.parse(location)),
      );
      await settle(tester);

      expect(router.state.uri.toString(), previous);
      expect(router.routeInformationProvider.value.uri.toString(), previous);
      expect(router.routerDelegate.currentConfiguration.isError, isFalse);
      expect(find.bySemanticsLabel('Navegación principal'), findsOneWidget);
      expect(find.textContaining('GoException'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  screenTest('external schemes, authorities and unknown paths keep the route', (
    tester,
    phone,
  ) async {
    await bareFamily(tester, phone);
    await pumpRegalos(tester, phone);
    final router = phone.container.read(routerProvider);
    router.go(AppRoutes.occasions);
    await settle(tester);

    for (final location in [
      'other:///settings',
      '//other.example/settings',
      '/unknown',
      'https://gifthuddle.app/i#AAAAAAAAAAAAAAAAAAAAAA',
      'https://gifthuddle.app/s#encrypted-envelope',
      'https://gifthuddle.retired.example/i#AAAAAAAAAAAAAAAAAAAAAA',
      'https://gifthuddle.retired.example/s#encrypted-envelope',
    ]) {
      router.go(location);
      await settle(tester);
      expect(router.state.uri.toString(), AppRoutes.occasions);
      expect(router.routerDelegate.currentConfiguration.isError, isFalse);
      expect(tester.takeException(), isNull);
    }
  });

  screenTest(
    'routing exceptions fall back to home',
    (tester, phone) async {
      await bareFamily(tester, phone);
      await pumpRegalos(tester, phone);
      final router = phone.container.read(routerProvider);
      router.go(AppRoutes.settings);
      await settle(tester);
      expect(router.state.uri.toString(), AppRoutes.people);
      expect(router.routerDelegate.currentConfiguration.isError, isFalse);
      expect(find.bySemanticsLabel('Navegación principal'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    overrides: [
      routerProvider.overrideWith((ref) {
        final router = buildRouter(
          redirect: (context, state) {
            if (state.uri.path == AppRoutes.settings) {
              throw GoException('routing failure');
            }
            return null;
          },
        );
        ref.onDispose(router.dispose);
        return router;
      }),
    ],
  );
}
