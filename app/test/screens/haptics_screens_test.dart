import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/motion/haptics.dart';
import 'package:regalos/core/widgets/choice_grid.dart';
import 'package:regalos/core/widgets/filter_pill.dart';
import 'package:regalos/core/widgets/regalos_nav_bar.dart';
import 'package:regalos/core/widgets/regalos_nav_rail.dart';
import 'package:regalos/core/widgets/stroke_icon.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/lock/application/lock_controller.dart';
import 'package:regalos/core/sync/model.dart';

import '../helpers/fake_haptics.dart';
import '../helpers/memory_stores.dart';
import '../helpers/pump_app.dart';
import '../helpers/screens.dart';
import '../lock/lock_gate_test.dart' show pumpGate, typePin;
import 'family_grid_test.dart' show openFamily;

/// Las vibraciones en las pantallas, con el servicio simulado
/// (la guía de movimiento, «Vibraciones»).
void main() {
  setUp(() => _shared.calls.clear());

  group('casilla de un regalo', () {
    screenTest('avanzar de estado: ligera cuando el sector termina de barrer', (
      tester,
      phone,
    ) async {
      final fake = _shared;
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tapText(tester, 'Aritz');
      const title = 'Estación de bomberos de bloques';
      await tester.scrollUntilVisible(
        find.text(title),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester);
      expect(fake.calls, isEmpty);

      await tester.tap(
        find.bySemanticsLabel(
          'Cambiar estado de $title. Estado actual: Comprado',
        ),
      );
      await tester.pump();
      expect(
        fake.calls.map((c) => '${c.level.name}+${c.after.inMilliseconds}'),
        ['light+160'],
      );
    }, overrides: [hapticsProvider.overrideWithValue(_shared)]);
  });

  group('barra y raíl', () {
    Future<void> pumpWith(
      WidgetTester tester,
      FakeHaptics fake,
      Widget Function(void Function(int)) build, {
      bool? disableAnimations,
    }) => pumpThemed(
      tester,
      ProviderScope(overrides: [fake.provide], child: build((_) {})),
      disableAnimations: disableAnimations,
    );

    const destinations = [
      NavDestination(icon: AppIcons.people, label: 'Personas'),
      NavDestination(icon: AppIcons.family, label: 'Reparto'),
      NavDestination(icon: AppIcons.occasions, label: 'Ocasiones'),
      NavDestination(icon: AppIcons.settings, label: 'Ajustes'),
    ];

    for (final rail in [false, true]) {
      final name = rail ? 'el raíl' : 'la barra';

      testWidgets('$name: cambiar de destino vibra con un clic cuando llega', (
        tester,
      ) async {
        final fake = FakeHaptics();
        var picked = -1;
        await pumpWith(
          tester,
          fake,
          (_) => rail
              ? RegalosNavRail(
                  semanticLabel: 'Navegación',
                  selectedIndex: 0,
                  destinations: destinations,
                  onSelected: (i) => picked = i,
                )
              : RegalosNavBar(
                  semanticLabel: 'Navegación',
                  selectedIndex: 0,
                  destinations: destinations,
                  onSelected: (i) => picked = i,
                ),
        );
        // Tocar el destino activo no vibra.
        await tester.tap(find.text('Personas'));
        await tester.pump();
        expect(picked, 0);
        expect(fake.calls, isEmpty);

        await tester.tap(find.text('Ocasiones'));
        await tester.pump();
        expect(picked, 2);
        expect(fake.calls, hasLength(1));
        expect(fake.calls.single.level, HapticLevel.selection);
        expect(fake.calls.single.after, kHapticSpringArrival);
      });

      testWidgets('$name: con «Reducir movimiento» vibra al momento', (
        tester,
      ) async {
        final fake = FakeHaptics();
        await pumpWith(
          tester,
          fake,
          (_) => rail
              ? RegalosNavRail(
                  semanticLabel: 'Navegación',
                  selectedIndex: 0,
                  destinations: destinations,
                  onSelected: (_) {},
                )
              : RegalosNavBar(
                  semanticLabel: 'Navegación',
                  selectedIndex: 0,
                  destinations: destinations,
                  onSelected: (_) {},
                ),
          disableAnimations: true,
        );
        await tester.tap(find.text('Reparto'));
        await tester.pump();
        expect(fake.calls.single.after, Duration.zero);
      });
    }
  });

  group('celdas y pastillas', () {
    testWidgets('ChoiceGrid: elegir otra celda vibra; la elegida, no', (
      tester,
    ) async {
      final fake = FakeHaptics();
      var taps = 0;
      await pumpThemed(
        tester,
        ProviderScope(
          overrides: [fake.provide],
          child: ChoiceGrid(
            items: [
              ChoiceGridItem(
                label: 'Uno',
                leading: (_, _) => const SizedBox.square(dimension: 16),
                selected: true,
                onTap: () => taps++,
              ),
              ChoiceGridItem(
                label: 'Dos',
                leading: (_, _) => const SizedBox.square(dimension: 16),
                selected: false,
                onTap: () => taps++,
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('Uno'));
      await tester.pump();
      expect(fake.calls, isEmpty);
      await tester.tap(find.text('Dos'));
      await tester.pump();
      expect(taps, 2);
      expect(fake.levels, [HapticLevel.selection]);
      expect(fake.calls.single.after, Duration.zero);
    });

    testWidgets('FilterPill: vibra al tocar; la que solo abre una hoja, no', (
      tester,
    ) async {
      final fake = FakeHaptics();
      await pumpThemed(
        tester,
        ProviderScope(
          overrides: [fake.provide],
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilterPill(label: 'Comprar', onTap: () {}),
              FilterPill(label: 'Filtros', haptic: false, onTap: () {}),
              FilterPill(
                label: 'Todas',
                selected: true,
                solid: true,
                onTap: () {},
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('Comprar'));
      await tester.pump();
      expect(fake.levels, [HapticLevel.selection]);
      await tester.tap(find.text('Filtros'));
      await tester.tap(find.text('Todas'));
      await tester.pump();
      expect(fake.levels, [HapticLevel.selection]);
    });
  });

  group('PIN', () {
    late FakePhone phone;
    late FakeHaptics fake;

    setUp(() async {
      fake = FakeHaptics();
      phone = FakePhone(extraOverrides: [fake.provide]);
      await phone.container
          .read(familyControllerProvider.notifier)
          .createFamily(deviceName: 'A');
      await phone.container
          .read(lockControllerProvider.notifier)
          .setPin('4821');
      phone.restart();
    });
    tearDown(() => phone.dispose());

    testWidgets('un PIN equivocado vibra con el patrón de error, una vez', (
      tester,
    ) async {
      await pumpGate(tester, phone);
      await typePin(tester, '0000');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(fake.levels, [HapticLevel.error]);
    });
  });

  group('Reparto', () {
    screenTest(
      'los regalos aterrizan: una sola vibración por vuelo, aunque sean muchos',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await openFamily(tester, all: false);
        final fake = _shared..calls.clear();

        await tester.tap(find.bySemanticsLabel('Por ocasión'));
        await settle(tester);
        // Aterrizan varios y suena una sola, ligera.
        expect(fake.levels, [HapticLevel.light]);

        await tester.tap(find.bySemanticsLabel('Rejilla'));
        await settle(tester);
        expect(fake.levels, [HapticLevel.light, HapticLevel.light]);
      },
      size: const Size(390, 1500),
      overrides: [hapticsProvider.overrideWithValue(_shared)],
    );
  });

  group('persona completa', () {
    const puzle =
        'Cambiar estado de Puzle de 48 piezas. Estado actual: Decidido';

    screenTest(
      'la acción del usuario que la completa: éxito con el sello, que manda',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tapText(tester, 'Nora');
        final fake = _shared..calls.clear();

        await tester.tap(find.bySemanticsLabel(puzle));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final last = fake.calls.last;
        expect(last.level, HapticLevel.success);
        expect(last.after, kHapticSeal);
        expect(last.supersede, isTrue);
        await settle(tester);
      },
      inlineDocumentTasks: true,
      overrides: [hapticsProvider.overrideWithValue(_shared)],
    );

    screenTest('si la completa un cambio que llega de fuera, no vibra', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tapText(tester, 'Nora');
      final fake = _shared..calls.clear();

      await tester.runAsync(
        () => familyOf(phone).setGiftStatus('g6', GiftStatus.bought),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(fake.calls, isEmpty);
    }, overrides: [hapticsProvider.overrideWithValue(_shared)]);
  });

  group('Ajustes › Apariencia', () {
    screenTest(
      'el interruptor «Vibraciones» está encendido de serie, se apaga y se '
      'guarda; «Reducir movimiento» no lo toca',
      (tester, phone) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tapText(tester, 'Ajustes');
        await tapText(tester, 'Apariencia');
        expect(find.text('Vibraciones'), findsOneWidget);
        expect(phone.container.read(hapticsEnabledProvider), isTrue);

        await tester.scrollUntilVisible(
          find.text('Vibraciones'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.bySemanticsLabel('Vibraciones'));
        await settle(tester);
        expect(phone.container.read(hapticsEnabledProvider), isFalse);
        expect(phone.prefs!.getBool(kHapticsEnabledKey), isFalse);
      },
    );
  });
}

/// El servicio simulado que comparten las pruebas de pantalla (cada una lo
/// vacía al empezar).
final FakeHaptics _shared = FakeHaptics();
