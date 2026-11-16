import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/features/web_device/presentation/web_gate_model.dart';
import 'package:regalos/l10n/app_localizations.dart';

/// Un motor falso: apunta lo que la interfaz le pide.
class FakeGateActions implements WebGateActions {
  final List<String> calls = <String>[];
  WebPinChangeResult changeResult = WebPinChangeResult.changed;

  @override
  Future<void> restartPairing() async => calls.add('restartPairing');

  @override
  Future<void> submitPin(String pin) async => calls.add('submitPin:$pin');

  @override
  Future<void> choosePin(String pin) async => calls.add('choosePin:$pin');

  @override
  Future<void> useHere() async => calls.add('useHere');

  @override
  Future<void> retry() async => calls.add('retry');

  @override
  Future<void> reconnect() async => calls.add('reconnect');

  @override
  Future<void> eraseComputer() async => calls.add('eraseComputer');

  @override
  Future<void> lock() async => calls.add('lock');

  @override
  Future<WebPinChangeResult> changePin(String current, String next) async {
    calls.add('changePin:$current:$next');
    return changeResult;
  }

  @override
  Future<void> forgetComputer() async => calls.add('forgetComputer');
}

const Size desktopSize = Size(1280, 800);
const Size phoneSize = Size(375, 812);

/// Monta [home] con el tema, los idiomas y, si se pide, «Reducir movimiento».
/// Llamarla otra vez con otro [home] actualiza el árbol en su sitio.
Future<void> pumpWeb(
  WidgetTester tester,
  Widget home, {
  Locale locale = const Locale('es'),
  Size size = desktopSize,
  bool reduce = false,
  Brightness brightness = Brightness.light,
  Duration settle = const Duration(milliseconds: 700),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildTheme(AccentId.lavender.palette, brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
        child: child!,
      ),
      home: home,
    ),
  );
  // Los indicadores de espera no paran: nada de `pumpAndSettle`.
  if (settle > Duration.zero) {
    await tester.pump(settle);
  }
}

/// Desmonta el árbol (cancela los temporizadores de la puerta).
Future<void> unmount(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox.shrink());

/// Los textos del idioma que está montado.
AppLocalizations l10nOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Material).first));
