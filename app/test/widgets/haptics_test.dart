import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/motion/haptics.dart';
import 'package:regalos/core/prefs/shared_preferences_provider.dart';

import '../helpers/pump_app.dart';

/// Lo que llega al sistema: el nombre de cada `HapticFeedback` pedido.
class RecordingDriver extends HapticDriver {
  final List<String> taps = <String>[];

  @override
  Future<void> selectionClick() async => taps.add('selection');

  @override
  Future<void> lightImpact() async => taps.add('light');

  @override
  Future<void> mediumImpact() async => taps.add('medium');

  @override
  Future<void> heavyImpact() async => taps.add('heavy');
}

void main() {
  late RecordingDriver driver;
  late Duration now;
  late bool enabled;
  late Haptics haptics;

  setUp(() {
    driver = RecordingDriver();
    now = Duration.zero;
    enabled = true;
    haptics = Haptics(enabled: () => enabled, driver: driver, now: () => now);
  });
  tearDown(() => haptics.dispose());

  /// Avanza el reloj del servicio y el de los temporizadores a la vez.
  Future<void> advance(WidgetTester tester, int ms) async {
    now += Duration(milliseconds: ms);
    await tester.pump(Duration(milliseconds: ms));
  }

  group('niveles', () {
    test('los tres sueltos van a su HapticFeedback', () {
      haptics.selection();
      now += kHapticMinGap;
      haptics.light();
      now += kHapticMinGap;
      haptics.medium();
      expect(driver.taps, ['selection', 'light', 'medium']);
    });

    testWidgets('éxito: ligero y medio, que sube', (tester) async {
      haptics.success();
      expect(driver.taps, ['light']);
      await advance(tester, 100);
      expect(driver.taps, ['light', 'medium']);
    });

    testWidgets('aviso: dos medios seguidos', (tester) async {
      haptics.warning();
      await advance(tester, 130);
      expect(driver.taps, ['medium', 'medium']);
    });

    testWidgets('error: fuerte, fuerte y un eco ligero', (tester) async {
      haptics.error();
      expect(driver.taps, ['heavy']);
      await advance(tester, 100);
      expect(driver.taps, ['heavy', 'heavy']);
      await advance(tester, 100);
      expect(driver.taps, ['heavy', 'heavy', 'light']);
    });

    test('cada nivel tiene su patrón', () {
      expect(Haptics.patternOffsets.keys, HapticLevel.values);
    });
  });

  group('antirrebote', () {
    test('dos vibraciones en menos de 80 ms: suena solo la primera', () {
      haptics.selection();
      now += const Duration(milliseconds: 79);
      haptics.medium();
      expect(driver.taps, ['selection']);
    });

    test('pasados 80 ms vuelve a sonar', () {
      haptics.selection();
      now += const Duration(milliseconds: 80);
      haptics.medium();
      expect(driver.taps, ['selection', 'medium']);
    });

    testWidgets('mientras suena un patrón no entra otra', (tester) async {
      haptics.error();
      await advance(tester, 120);
      haptics.light();
      expect(driver.taps, ['heavy', 'heavy']);
      // El patrón dura 180 ms y el hueco son otros 80.
      await advance(tester, 140);
      haptics.light();
      expect(driver.taps, ['heavy', 'heavy', 'light', 'light']);
    });

    testWidgets('una con espera se mide cuando le toca, no al pedirla', (
      tester,
    ) async {
      haptics.light(after: const Duration(milliseconds: 160));
      // Pedida ya, pero esta suena al momento y ocupa el hueco.
      await advance(tester, 100);
      haptics.selection();
      expect(driver.taps, ['selection']);
      await advance(tester, 60);
      // Llega a los 160 ms: 60 ms después de la otra, dentro del hueco.
      expect(driver.taps, ['selection']);
    });
  });

  group('espera y prioridad', () {
    testWidgets('con `after` suena pasado ese tiempo', (tester) async {
      haptics.medium(after: kHapticSpringArrival);
      expect(driver.taps, isEmpty);
      await advance(tester, 159);
      expect(driver.taps, isEmpty);
      await advance(tester, 1);
      expect(driver.taps, ['medium']);
    });

    testWidgets('`supersede` anula las que esperan', (tester) async {
      haptics.light(after: kHapticSpringArrival);
      haptics.play(HapticLevel.medium, after: kHapticSeal, supersede: true);
      await advance(tester, 300);
      expect(driver.taps, ['medium']);
    });

    testWidgets('al liberar el servicio no queda nada pendiente', (
      tester,
    ) async {
      haptics.success(after: const Duration(milliseconds: 300));
      haptics.dispose();
      await advance(tester, 500);
      expect(driver.taps, isEmpty);
    });
  });

  group('ajuste', () {
    test('apagado no suena nada', () {
      enabled = false;
      haptics
        ..selection()
        ..error();
      expect(driver.taps, isEmpty);
    });

    testWidgets('apagarlo mientras espera la silencia', (tester) async {
      haptics.light(after: kHapticSpringArrival);
      enabled = false;
      await advance(tester, 200);
      expect(driver.taps, isEmpty);
    });

    testWidgets('encendido de serie y guardado en preferencias', (
      tester,
    ) async {
      final prefs = await mockPrefs();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      expect(container.read(hapticsEnabledProvider), isTrue);
      container.read(hapticsEnabledProvider.notifier).set(enabled: false);
      expect(container.read(hapticsEnabledProvider), isFalse);
      expect(prefs.getBool(kHapticsEnabledKey), isFalse);
      // Lo guardado se lee al volver a abrir la app.
      final again = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(again.dispose);
      expect(again.read(hapticsEnabledProvider), isFalse);
    });

    testWidgets('«Reducir movimiento» no las apaga: solo quita la espera', (
      tester,
    ) async {
      late BuildContext context;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(context.hapticArrival, Duration.zero);
      expect(context.hapticSeal, Duration.zero);
      // Sin `ProviderScope` el servicio sencillo sigue encendido.
      expect(context.haptics, isA<Haptics>());
    });
  });
}
