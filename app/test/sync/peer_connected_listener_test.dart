import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/features/sync/application/peer_connected.dart';
import 'package:regalos/features/sync/presentation/peer_connected_listener.dart';
import 'package:regalos/l10n/app_localizations.dart';

/// El aviso «Se ha conectado otro móvil» del móvil que enseñó el QR.
void main() {
  Future<ProviderContainer> pumpListener(
    WidgetTester tester, {
    Locale locale = const Locale('es'),
  }) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          locale: locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildTheme(AccentId.lavender.palette, Brightness.light),
          builder: (context, child) => PeerConnectedListener(
            navigatorKey: navigatorKey,
            child: child ?? const SizedBox(),
          ),
          home: const Scaffold(body: SizedBox.expand()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'sin nombre dice que se ha conectado otro móvil y se da por visto',
    (tester) async {
      final container = await pumpListener(tester);
      expect(find.byType(SnackBar), findsNothing);

      container.read(peerConnectedProvider.notifier).announce(null);
      await tester.pumpAndSettle();

      expect(find.text('Se ha conectado otro móvil'), findsOneWidget);
      expect(container.read(peerConnectedProvider), isNull);
    },
  );

  testWidgets('con nombre, lo dice', (tester) async {
    final container = await pumpListener(tester);
    container.read(peerConnectedProvider.notifier).announce(' Móvil de Nora ');
    await tester.pumpAndSettle();
    expect(
      find.text('Se ha conectado otro móvil: Móvil de Nora'),
      findsOneWidget,
    );
  });

  testWidgets('en catalán y en inglés', (tester) async {
    var container = await pumpListener(tester, locale: const Locale('ca'));
    container.read(peerConnectedProvider.notifier).announce(null);
    await tester.pumpAndSettle();
    expect(find.text("S'ha connectat un altre mòbil"), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    container = await pumpListener(tester, locale: const Locale('en'));
    container.read(peerConnectedProvider.notifier).announce('Leo');
    await tester.pumpAndSettle();
    expect(find.text('Another phone has connected: Leo'), findsOneWidget);
  });
}
