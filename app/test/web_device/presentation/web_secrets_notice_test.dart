// La web con regalos en secreto (1.0.6, ADR 0009): los avisos según lo que
// puede hacer (volver a conectar, abrir el móvil, ordenador compartido, cambios
// descartados), la marca «Pendiente de tu móvil» y el aviso antes de olvidar
// este ordenador. Español e inglés, claro y oscuro, escritorio y móvil, con
// letra grande y sin movimiento.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/web_device/application/web_app_provider.dart';
import 'package:regalos/features/web_device/application/web_device_providers.dart';
import 'package:regalos/features/web_device/application/web_secrets.dart'
    show WebSecretsState;
import 'package:regalos/features/web_device/application/web_sync_engine.dart'
    show WebSyncStatus;
import 'package:regalos/features/web_device/presentation/web_secrets_notice.dart';
import 'package:regalos/features/web_device/presentation/web_settings_section.dart';
import 'package:regalos/features/web_device/presentation/web_status_strip.dart';

import '../../helpers/fonts.dart';
import 'gate_test_support.dart';

WebDeviceState _state({
  WebSecretsState secrets = WebSecretsState.off,
  int dropped = 0,
  int pending = 0,
  int held = 0,
  List<String> heldNames = const [],
}) => WebDeviceState(
  status: WebSyncStatus.confirmed,
  hasRoots: true,
  setAsideChanges: 0,
  persistenceDenied: false,
  secrets: secrets,
  droppedSecretChanges: dropped,
  pendingSecretGifts: pending,
  heldSecretChanges: held,
  heldInboxNames: heldNames,
);

/// Un estado que la prueba puede cambiar.
class _Holder extends Notifier<WebDeviceState> {
  @override
  WebDeviceState build() => _state();

  void set(WebDeviceState next) => state = next;
}

final _holder = NotifierProvider<_Holder, WebDeviceState>(_Holder.new);

List<Override> _overrides() => [
  webAppProvider.overrideWithValue(true),
  webDeviceStateProvider.overrideWith((ref) => ref.watch(_holder)),
];

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('es'),
  Size size = desktopSize,
  Brightness brightness = Brightness.light,
  bool reduce = false,
  double textScale = 1,
}) async {
  ProviderContainer? container;
  await pumpWeb(
    tester,
    Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: ProviderScope(
          overrides: _overrides(),
          child: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return Scaffold(body: SingleChildScrollView(child: child));
            },
          ),
        ),
      ),
    ),
    locale: locale,
    size: size,
    brightness: brightness,
    reduce: reduce,
  );
  return container!;
}

void _set(ProviderContainer c, WebDeviceState s) =>
    c.read(_holder.notifier).set(s);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  setUpAll(loadInter);

  group('avisos de los regalos en secreto', () {
    testWidgets('sin nada que decir no ocupan sitio', (tester) async {
      await _pump(tester, const WebStatusStrip());
      expect(find.byType(WebSecretsNotice), findsOneWidget);
      expect(
        tester.getSize(find.byType(WebSecretsNotice)).height,
        0,
        reason: 'ni un hueco',
      );
    });

    testWidgets('cada estado dice lo suyo y se puede volver a quitar', (
      tester,
    ) async {
      final c = await _pump(tester, const WebSecretsNotice());
      final l10n = l10nOf(tester);

      _set(c, _state(secrets: WebSecretsState.reconnect));
      await _settle(tester);
      expect(find.text(l10n.webSecretsReconnect), findsOneWidget);
      // Es un problema, no un aviso que se cierre.
      expect(find.text(l10n.actionUnderstood), findsNothing);

      _set(c, _state(secrets: WebSecretsState.waitingKeys));
      await _settle(tester);
      expect(find.text(l10n.webSecretsReconnect), findsNothing);
      expect(find.text(l10n.webSecretsWaitingPhone), findsOneWidget);

      _set(c, _state(secrets: WebSecretsState.open));
      await _settle(tester);
      expect(find.text(l10n.webSecretsWaitingPhone), findsNothing);
      expect(find.text(l10n.webSecretsSharedComputer), findsOneWidget);
      await tester.tap(find.text(l10n.actionUnderstood));
      await _settle(tester);
      expect(find.text(l10n.webSecretsSharedComputer), findsNothing);

      // Sin nada abierto no hay aviso de ordenador compartido.
      _set(c, _state());
      await _settle(tester);
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('los cambios descartados se cuentan, se cierran y un descarte '
        'nuevo vuelve a avisar', (tester) async {
      final c = await _pump(tester, const WebSecretsNotice());
      final l10n = l10nOf(tester);
      _set(c, _state(dropped: 1));
      await _settle(tester);
      expect(find.text(l10n.webSecretsDropped(1)), findsOneWidget);
      await tester.tap(find.text(l10n.actionUnderstood));
      await _settle(tester);
      expect(find.text(l10n.webSecretsDropped(1)), findsNothing);
      _set(c, _state(dropped: 3));
      await _settle(tester);
      expect(find.text(l10n.webSecretsDropped(3)), findsOneWidget);
    });

    testWidgets('el buzón retenido por el servidor dice para quién y que se '
        'reintenta solo', (tester) async {
      final c = await _pump(tester, const WebSecretsNotice());
      final l10n = l10nOf(tester);
      _set(c, _state(heldNames: ['Leo', 'Nora']));
      await _settle(tester);
      expect(find.text(l10n.webSecretsHeld('Leo, Nora')), findsOneWidget);
      expect(find.textContaining('Se vuelve a intentar solo.'), findsOneWidget);
      _set(c, _state());
      await _settle(tester);
      expect(find.textContaining('Se vuelve a intentar solo.'), findsNothing);
    });

    testWidgets('fuera de la web no sale nada', (tester) async {
      await pumpWeb(
        tester,
        ProviderScope(
          overrides: [
            webAppProvider.overrideWithValue(false),
            webDeviceStateProvider.overrideWithValue(
              _state(secrets: WebSecretsState.reconnect),
            ),
          ],
          child: const Scaffold(body: WebSecretsNotice()),
        ),
      );
      expect(find.byType(TextButton), findsNothing);
      expect(find.textContaining('móvil'), findsNothing);
    });

    for (final size in [desktopSize, phoneSize]) {
      for (final locale in const ['es', 'en']) {
        for (final brightness in Brightness.values) {
          for (final variant in const [
            (big: false, reduce: false),
            (big: true, reduce: false),
            (big: false, reduce: true),
          ]) {
            testWidgets(
              'caben los cuatro a la vez · $locale ${brightness.name} '
              '${size.width.toInt()}${variant.big ? ' x2' : ''}'
              '${variant.reduce ? ' sin movimiento' : ''}',
              (tester) async {
                final c = await _pump(
                  tester,
                  const WebSecretsNotice(),
                  locale: Locale(locale),
                  size: size,
                  brightness: brightness,
                  reduce: variant.reduce,
                  textScale: variant.big ? 2 : 1,
                );
                // Estados que no se dan a la vez de verdad (el aviso de
                // conexión y el de claves), para medir lo más alto posible.
                _set(c, _state(secrets: WebSecretsState.open, dropped: 4));
                await _settle(tester);
                final l10n = l10nOf(tester);
                expect(
                  find.text(l10n.webSecretsSharedComputer),
                  findsOneWidget,
                );
                expect(find.text(l10n.webSecretsDropped(4)), findsOneWidget);
                expect(tester.takeException(), isNull);
                _set(c, _state(secrets: WebSecretsState.reconnect));
                await _settle(tester);
                expect(find.text(l10n.webSecretsReconnect), findsOneWidget);
                expect(tester.takeException(), isNull);
              },
            );
          }
        }
      }
    }
  });

  group('antes de olvidar este ordenador', () {
    Widget page(FakeGateActions actions, {int pending = 0}) => Scaffold(
      body: ListView(
        children: [
          WebSettingsSection(actions: actions, pendingSecretChanges: pending),
        ],
      ),
    );

    for (final locale in const ['es', 'en']) {
      testWidgets('con cambios sin recoger, el diálogo lo avisa · $locale', (
        tester,
      ) async {
        final actions = FakeGateActions();
        await pumpWeb(
          tester,
          page(actions, pending: 2),
          locale: Locale(locale),
        );
        final l10n = l10nOf(tester);
        await tester.tap(find.text(l10n.webSettingsForget));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text(l10n.webSettingsForgetTitle), findsOneWidget);
        expect(find.textContaining(l10n.webSettingsForgetBody), findsOneWidget);
        expect(
          find.textContaining(l10n.webForgetPendingSecrets),
          findsOneWidget,
        );
        // Sigue pidiendo confirmación.
        expect(actions.calls, isNot(contains('forgetComputer')));
        await tester.tap(find.text(l10n.webSettingsForgetConfirm));
        await tester.pump();
        expect(actions.calls, ['forgetComputer']);
      });
    }

    testWidgets('sin cambios sin recoger, el diálogo es el de siempre', (
      tester,
    ) async {
      await pumpWeb(tester, page(FakeGateActions()));
      final l10n = l10nOf(tester);
      await tester.tap(find.text(l10n.webSettingsForget));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text(l10n.webSettingsForgetBody), findsOneWidget);
      expect(find.textContaining(l10n.webForgetPendingSecrets), findsNothing);
    });
  });
}
