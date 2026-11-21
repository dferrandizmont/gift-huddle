// La versión web dentro de la app: aviso de apartados y estado de guardado en
// la pantalla principal, Ajustes reducidos con «Este ordenador», rutas que no
// existen en la web, marco de escritorio y aviso claro ante una acción que la
// web no hace.
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/l10n/app_localizations.dart';
import 'package:regalos/app/app.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/widgets/regalos_nav_rail.dart';
import 'package:regalos/features/settings/application/locale_provider.dart';
import 'package:regalos/features/web_board/application/web_board.dart';
import 'package:regalos/features/web_device/application/web_app_provider.dart';
import 'package:regalos/features/web_device/application/web_device_providers.dart';
import 'package:regalos/features/web_device/application/web_sync_engine.dart'
    show WebOperationException, WebSyncActivity, WebSyncStatus;
import 'package:regalos/features/web_device/presentation/web_desktop_frame.dart';
import 'package:regalos/features/web_device/presentation/web_operation_guard.dart';
import 'package:regalos/features/web_device/presentation/web_status_strip.dart';

import '../../helpers/fonts.dart';
import '../../helpers/memory_stores.dart';
import '../../helpers/screens.dart';
import 'gate_test_support.dart';

const _confirmed = WebDeviceState(
  status: WebSyncStatus.confirmed,
  hasRoots: true,
  setAsideChanges: 0,
  persistenceDenied: false,
);

List<Override> _web({
  WebDeviceState state = _confirmed,
  FakeGateActions? actions,
}) => [
  webAppProvider.overrideWithValue(true),
  // Estas pruebas miran el diseño por bandas; el tablero «Hoy» tiene las suyas
  // (`test/web_board/`).
  webBoardEnabledProvider.overrideWithValue(false),
  webGateActionsProvider.overrideWithValue(actions ?? FakeGateActions()),
  webDeviceStateProvider.overrideWithValue(state),
];

/// Monta la app como la web: sin el bloqueo del móvil, con la familia de
/// muestra ya sembrada.
Future<void> _mountWeb(WidgetTester tester, FakePhone phone) async {
  await seedSample(tester, phone);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: phone.container,
      child: const RegalosApp(webSession: true),
    ),
  );
  await settle(tester);
}

const _sizes = [Size(375, 812), Size(1280, 800)];

void main() {
  setUpAll(loadInter);

  for (final size in _sizes) {
    final label = '${size.width.toInt()}';

    screenTest(
      'pantalla principal: aviso de cambios apartados y «Guardado» · $label',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        expect(
          find.textContaining('Hay 2 cambios que no se pueden subir'),
          findsOneWidget,
        );
        expect(find.text('Guardado'), findsOneWidget);
        expect(
          find.text('Pendiente de confirmación desde un móvil'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
      size: size,
      overrides: _web(
        state: const WebDeviceState(
          status: WebSyncStatus.confirmed,
          hasRoots: true,
          setAsideChanges: 2,
          persistenceDenied: false,
        ),
      ),
    );

    screenTest(
      'sin confirmar: lo dice y no hay aviso de apartados · $label',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        expect(
          find.text('Pendiente de confirmación desde un móvil'),
          findsOneWidget,
        );
        expect(find.text('Guardado'), findsNothing);
        expect(find.textContaining('que no se pueden subir'), findsNothing);
        expect(tester.takeException(), isNull);
      },
      size: size,
      overrides: _web(
        state: const WebDeviceState(
          status: WebSyncStatus.pending,
          hasRoots: true,
          setAsideChanges: 0,
          persistenceDenied: false,
        ),
      ),
    );

    screenTest(
      'Ajustes en la web: sin móviles, compartir, copia ni protecciones, y '
      'con «Este ordenador» · $label',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        await tapText(tester, 'Ajustes');
        // Lo que sí hay.
        expect(find.text('Este ordenador'), findsOneWidget);
        expect(find.text('Cambiar PIN'), findsOneWidget);
        expect(find.text('Bloquear ahora'), findsOneWidget);
        expect(find.text('Olvidar este ordenador'), findsOneWidget);
        expect(find.text('Idioma'), findsOneWidget);
        expect(find.text('Apariencia'), findsOneWidget);
        expect(find.text('Familia'), findsOneWidget);
        // Ko-fi ya no está en la app, tampoco en la web.
        expect(find.textContaining('Ko-fi'), findsNothing);
        // Lo que no aplica.
        expect(find.text('Móviles de la familia'), findsNothing);
        expect(find.text('Copia de seguridad'), findsNothing);
        expect(find.text('Bloqueo'), findsNothing);
        expect(find.text('Este móvil es de'), findsNothing);
        expect(find.text('Borrar todo'), findsNothing);
        expect(find.text('Este móvil'), findsNothing);
        expect(tester.takeException(), isNull);
      },
      size: size,
      overrides: _web(),
    );

    screenTest('en el móvil (sin web) Ajustes sigue igual · $label', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: phone.container,
          child: const RegalosApp(webSession: true),
        ),
      );
      await settle(tester);
      await tapText(tester, 'Ajustes');
      expect(find.text('Móviles de la familia'), findsOneWidget);
      expect(find.text('Copia de seguridad'), findsOneWidget);
      expect(find.text('Este móvil es de'), findsOneWidget);
      expect(find.text('Este ordenador'), findsNothing);
      expect(find.text('Guardado'), findsNothing);
    }, size: size);
  }

  for (final size in _sizes) {
    for (final code in const ['ca', 'en']) {
      screenTest(
        'Ajustes y estado en $code caben y no enseñan lo oculto · '
        '${size.width.toInt()}',
        (tester, phone) async {
          await _mountWeb(tester, phone);
          phone.container.read(localeProvider.notifier).setLocale(Locale(code));
          await settle(tester);
          final l10n = AppLocalizations.of(
            tester.element(find.byType(Scaffold).first),
          );
          expect(find.text(l10n.webSyncSaved), findsOneWidget);
          expect(find.text(l10n.webSetAsideNotice(2)), findsOneWidget);
          await tapText(tester, l10n.navSettings);
          expect(find.text(l10n.webSettingsChangePin), findsOneWidget);
          expect(find.text(l10n.webSettingsForget), findsOneWidget);
          expect(find.text(l10n.settingsShare), findsNothing);
          expect(find.text(l10n.settingsBackup), findsNothing);
          expect(find.text(l10n.settingsSecurity), findsNothing);
          expect(find.text(l10n.settingsSelf), findsNothing);
          expect(find.text(l10n.eraseAllTitle), findsNothing);
          expect(tester.takeException(), isNull);
        },
        size: size,
        overrides: _web(
          state: const WebDeviceState(
            status: WebSyncStatus.confirmed,
            hasRoots: true,
            setAsideChanges: 2,
            persistenceDenied: false,
          ),
        ),
      );
    }
  }

  screenTest(
    'las rutas de compartir, copia y bloqueo de la web vuelven a Ajustes',
    (tester, phone) async {
      await _mountWeb(tester, phone);
      final router = phone.container.read(routerProvider);
      for (final path in const [
        '/settings/share',
        '/settings/backup',
        '/settings/security',
      ]) {
        router.go(path);
        await settle(tester);
        expect(find.text('Este ordenador'), findsOneWidget, reason: path);
        expect(find.text('Copia de seguridad'), findsNothing, reason: path);
        expect(find.text('Móviles de la familia'), findsNothing, reason: path);
      }
    },
    size: const Size(1280, 800),
    overrides: _web(),
  );

  group('marco de escritorio', () {
    screenTest(
      'a 1600 px la app ocupa toda la ventana (sin marco) y el raíl, a la '
      'izquierda',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        expect(find.byType(WebDesktopFrame), findsOneWidget);
        final rail = find.byType(RegalosNavRail);
        expect(rail, findsOneWidget);
        expect(tester.getTopLeft(rail).dx, 0);
        expect(tester.getSize(rail).width, 80);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1600, 900),
      overrides: _web(),
    );

    screenTest(
      'a 2600 px la escala es 1,2 y la composición (1880 lógicos) se centra '
      'con el raíl en su sitio',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        expect(find.byType(WebDesktopFrame), findsOneWidget);
        final rail = find.byType(RegalosNavRail);
        expect(rail, findsOneWidget);
        // 2600 / 1,2 = 2166,67 lógicos; márgenes de (2166,67 - 1880) / 2 =
        // 143,33 lógicos, que son 172 píxeles.
        expect(tester.getTopLeft(rail).dx, closeTo(172, 0.5));
        expect(tester.getSize(rail).width, 80);
        expect(tester.takeException(), isNull);
      },
      size: const Size(2600, 1000),
      overrides: _web(),
    );

    screenTest(
      'a 1280 px ocupa toda la ventana (patrón de tablet)',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        expect(tester.getTopLeft(find.byType(RegalosNavRail)).dx, 0);
      },
      size: const Size(1280, 800),
      overrides: _web(),
    );

    screenTest(
      'a 375 px se ve como el móvil: barra inferior y sin raíl',
      (tester, phone) async {
        await _mountWeb(tester, phone);
        expect(find.byType(RegalosNavRail), findsNothing);
        expect(find.text('Ajustes'), findsOneWidget);
      },
      size: const Size(375, 812),
      overrides: _web(),
    );
  });

  group('la línea de estado', () {
    for (final size in [phoneSize, desktopSize]) {
      for (final locale in const ['es', 'ca', 'en']) {
        testWidgets(
          'cada estado cabe y se lee · $locale · ${size.width.toInt()}',
          (tester) async {
            for (final indicator in WebSyncIndicator.values.where(
              (i) => i != WebSyncIndicator.hidden,
            )) {
              await pumpWeb(
                tester,
                Scaffold(
                  body: Column(children: [WebSyncLine(indicator: indicator)]),
                ),
                locale: Locale(locale),
                size: size,
              );
              final l10n = l10nOf(tester);
              final text = switch (indicator) {
                WebSyncIndicator.saving => l10n.webGateSaving,
                WebSyncIndicator.saved => l10n.webSyncSaved,
                WebSyncIndicator.offline => l10n.webSyncOffline,
                WebSyncIndicator.awaitingConfirm => l10n.webSyncAwaitingConfirm,
                WebSyncIndicator.hidden => '',
              };
              expect(find.text(text), findsOneWidget);
              expect(tester.takeException(), isNull);
            }
          },
        );
      }
    }

    test('qué estado corresponde al del motor', () {
      WebDeviceState of(
        WebSyncStatus s, [
        WebSyncActivity a = WebSyncActivity.idle,
      ]) => WebDeviceState(
        status: s,
        hasRoots: true,
        setAsideChanges: 0,
        persistenceDenied: false,
        activity: a,
      );
      expect(
        webSyncIndicatorOf(of(WebSyncStatus.confirmed)),
        WebSyncIndicator.saved,
      );
      expect(
        webSyncIndicatorOf(of(WebSyncStatus.confirmed), saving: true),
        WebSyncIndicator.saving,
      );
      expect(
        webSyncIndicatorOf(
          of(WebSyncStatus.confirmed, WebSyncActivity.uploading),
        ),
        WebSyncIndicator.saving,
      );
      expect(
        webSyncIndicatorOf(
          of(WebSyncStatus.confirmed, WebSyncActivity.offline),
          saving: true,
        ),
        WebSyncIndicator.offline,
      );
      expect(
        webSyncIndicatorOf(of(WebSyncStatus.pending, WebSyncActivity.offline)),
        WebSyncIndicator.awaitingConfirm,
      );
      expect(
        webSyncIndicatorOf(of(WebSyncStatus.pending), saving: true),
        WebSyncIndicator.awaitingConfirm,
      );
    });

    test(
      'desconectada (revocada o lista borrada) no se pinta sin conexión',
      () {
        for (final a in WebSyncActivity.values) {
          final indicator = webSyncIndicatorOf(
            WebDeviceState(
              status: WebSyncStatus.disconnected,
              hasRoots: true,
              setAsideChanges: 0,
              persistenceDenied: false,
              activity: a,
            ),
          );
          expect(indicator, WebSyncIndicator.hidden);
          expect(indicator, isNot(WebSyncIndicator.offline));
        }
      },
    );

    testWidgets('la línea oculta no pinta nada', (tester) async {
      await pumpWeb(
        tester,
        const Scaffold(
          body: Column(
            children: [WebSyncLine(indicator: WebSyncIndicator.hidden)],
          ),
        ),
        locale: const Locale('es'),
        size: phoneSize,
      );
      expect(find.byType(Text), findsNothing);
    });
  });

  group('acciones que la web no hace', () {
    testWidgets('una WebOperationException sin recoger sale como aviso claro', (
      tester,
    ) async {
      tester.view
        ..physicalSize = desktopSize
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final previous = PlatformDispatcher.instance.onError;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            webAppProvider.overrideWithValue(true),
            webBoardEnabledProvider.overrideWithValue(false),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('es'),
            theme: buildTheme(AccentId.lavender.palette, Brightness.light),
            home: const WebOperationGuard(
              child: Scaffold(body: SizedBox.expand()),
            ),
          ),
        ),
      );
      final handler = PlatformDispatcher.instance.onError!;
      expect(
        handler(const WebOperationException('invite'), StackTrace.empty),
        isTrue,
      );
      await tester.pump();
      expect(
        find.text(
          'Esto no se puede hacer desde el ordenador. Hazlo desde un móvil.',
        ),
        findsOneWidget,
      );
      // Otro error no se traga.
      expect(handler(StateError('otro'), StackTrace.empty), isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(PlatformDispatcher.instance.onError, previous);
    });

    testWidgets('fuera de la web no engancha nada', (tester) async {
      final previous = PlatformDispatcher.instance.onError;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: const WebOperationGuard(child: SizedBox())),
        ),
      );
      expect(PlatformDispatcher.instance.onError, previous);
    });
  });
}
