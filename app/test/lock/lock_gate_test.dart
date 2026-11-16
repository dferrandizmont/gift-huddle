import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/lock/application/lock_controller.dart';
import 'package:regalos/features/lock/presentation/lock_gate.dart';
import 'package:regalos/features/lock/presentation/lock_screen.dart';
import 'package:regalos/features/lock/presentation/pin_pad.dart';
import 'package:regalos/features/lock/presentation/pin_setup_screen.dart';
import 'package:regalos/l10n/app_localizations.dart';

import '../helpers/memory_stores.dart';

Future<void> pumpGate(
  WidgetTester tester,
  FakePhone phone, {
  Widget child = const Text('LA APP'),
}) async {
  tester.view
    ..physicalSize = const Size(390, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: phone.container,
      child: MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildTheme(AccentId.lavender.palette, Brightness.light),
        home: LockGate(child: child),
      ),
    ),
  );
  await settle(tester);
}

/// Deja acabar los futuros reales (cifrado, almacenes) y repinta.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump();
}

Future<void> typePin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.text(digit));
    await tester.pump();
  }
}

/// Almacén que falla al leer la configuración del bloqueo, como un Keystore
/// roto. Lanza una excepción que Riverpod no reintenta.
class LockFailingStore extends MemorySecretStore {
  bool failing = true;

  @override
  Future<String?> read(String key) async {
    if (failing && key == 'lock.config') {
      throw const FamilyStoreException('almacén roto');
    }
    return super.read(key);
  }
}

void main() {
  late FakePhone phone;
  setUp(() => phone = FakePhone());
  tearDown(() => phone.dispose());

  testWidgets('si falla la lectura del bloqueo, falla cerrado y reintenta', (
    tester,
  ) async {
    final store = LockFailingStore();
    final broken = FakePhone(secrets: store);
    addTearDown(broken.dispose);
    await tester.runAsync(
      () => broken.container
          .read(familyControllerProvider.notifier)
          .createFamily(deviceName: 'A'),
    );
    await pumpGate(tester, broken);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('LA APP'), findsNothing);

    store.failing = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pump(); // empieza la lectura nueva
    await settle(tester);
    expect(find.text('Reintentar'), findsNothing);
    // Ya se lee el bloqueo: sin PIN toca crearlo, y la app sigue tapada.
    expect(find.byType(PinSetupScreen), findsOneWidget);
    expect(find.text('LA APP'), findsNothing);
  });

  testWidgets('sin familia no hay nada que proteger', (tester) async {
    await pumpGate(tester, phone);
    expect(find.text('LA APP'), findsOneWidget);
    expect(find.byType(PinSetupScreen), findsNothing);
  });

  testWidgets('con familia y sin PIN pide crearlo, repetirlo, y entra', (
    tester,
  ) async {
    await tester.runAsync(
      () => phone.container
          .read(familyControllerProvider.notifier)
          .createFamily(deviceName: 'A'),
    );
    await pumpGate(tester, phone);
    expect(find.byType(PinSetupScreen), findsOneWidget);
    expect(find.text('Crea un PIN'), findsOneWidget);
    // La app sigue montada pero oculta.
    expect(find.text('LA APP'), findsNothing);

    await typePin(tester, '4821');
    await tester.tap(find.text('Continuar'));
    await tester.pump();
    expect(find.text('Repite el PIN'), findsOneWidget);
    await typePin(tester, '4821');
    await tester.tap(find.text('Guardar PIN'));
    await settle(tester);
    // El móvil de prueba tiene huella: se ofrece y se deja para luego.
    expect(find.text('¿Activar huella o rostro?'), findsOneWidget);
    expect(find.text('LA APP'), findsNothing);
    await tester.tap(find.text('Ahora no'));
    await settle(tester);
    expect(find.text('LA APP'), findsOneWidget);
    // La pantalla del PIN se va con un fundido de 375 ms, no de golpe.
    await tester.pumpAndSettle();
    expect(find.byType(PinSetupScreen), findsNothing);
    final state = await tester.runAsync(
      () => phone.container.read(lockControllerProvider.future),
    );
    expect(state!.biometrics, isFalse);
    expect(state.pinLength, 4);
    expect(phone.biometrics.prompts, 0);
  });

  testWidgets('al crear el PIN se puede activar la huella', (tester) async {
    await tester.runAsync(
      () => phone.container
          .read(familyControllerProvider.notifier)
          .createFamily(deviceName: 'A'),
    );
    await pumpGate(tester, phone);
    await typePin(tester, '482193');
    await tester.tap(find.text('Continuar'));
    await tester.pump();
    await typePin(tester, '482193');
    await tester.tap(find.text('Guardar PIN'));
    await settle(tester);
    expect(find.text('¿Activar huella o rostro?'), findsOneWidget);
    await tester.tap(find.text('Activar'));
    await settle(tester);
    await settle(tester);
    expect(find.text('LA APP'), findsOneWidget);
    final state = await tester.runAsync(
      () => phone.container.read(lockControllerProvider.future),
    );
    expect(state!.biometrics, isTrue);
    expect(state.pinLength, 6);
    expect(phone.biometrics.prompts, 1);
  });

  testWidgets('sin huella en el móvil no se ofrece nada al crear el PIN', (
    tester,
  ) async {
    phone.biometrics.available = false;
    await tester.runAsync(
      () => phone.container
          .read(familyControllerProvider.notifier)
          .createFamily(deviceName: 'A'),
    );
    await pumpGate(tester, phone);
    await typePin(tester, '4821');
    await tester.tap(find.text('Continuar'));
    await tester.pump();
    await typePin(tester, '4821');
    await tester.tap(find.text('Guardar PIN'));
    await settle(tester);
    expect(find.text('¿Activar huella o rostro?'), findsNothing);
    expect(find.text('LA APP'), findsOneWidget);
  });

  testWidgets('dos PIN distintos vuelven a empezar', (tester) async {
    await tester.runAsync(
      () => phone.container
          .read(familyControllerProvider.notifier)
          .createFamily(deviceName: 'A'),
    );
    await pumpGate(tester, phone);
    await typePin(tester, '4821');
    await tester.tap(find.text('Continuar'));
    await tester.pump();
    await typePin(tester, '1111');
    await tester.tap(find.text('Guardar PIN'));
    await tester.pump();
    expect(
      find.text('Los PIN no coinciden. Inténtalo de nuevo.'),
      findsOneWidget,
    );
    // El título viejo se va con un fundido.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Crea un PIN'), findsOneWidget);
  });

  testWidgets('pasar a repetir el PIN cruza el título con un fundido y no '
      'deja nada pendiente', (tester) async {
    await tester.runAsync(
      () => phone.container
          .read(familyControllerProvider.notifier)
          .createFamily(deviceName: 'A'),
    );
    await pumpGate(tester, phone);
    final keypad = tester.getTopLeft(find.text('5'));
    await typePin(tester, '4821');
    await tester.tap(find.text('Continuar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // A mitad del cambio salen y entran los dos títulos.
    expect(find.text('Crea un PIN'), findsOneWidget);
    expect(find.text('Repite el PIN'), findsOneWidget);
    expect(tester.getTopLeft(find.text('5')).dx, keypad.dx);
    await tester.pumpAndSettle();
    expect(find.text('Crea un PIN'), findsNothing);
    expect(find.text('Repite el PIN'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('"Ahora no" deja entrar sin bloqueo', (tester) async {
    await tester.runAsync(
      () => phone.container
          .read(familyControllerProvider.notifier)
          .createFamily(deviceName: 'A'),
    );
    await pumpGate(tester, phone);
    await tester.tap(find.text('Ahora no'));
    await settle(tester);
    expect(find.text('LA APP'), findsOneWidget);
  });

  group('con PIN', () {
    setUp(() async {
      await phone.container
          .read(familyControllerProvider.notifier)
          .createFamily(deviceName: 'A');
      await phone.container
          .read(lockControllerProvider.notifier)
          .setPin('4821');
      phone.restart(); // arranque en frío
    });

    testWidgets('en frío arranca bloqueado; PIN malo no entra, bueno sí', (
      tester,
    ) async {
      await pumpGate(tester, phone);
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.text('LA APP'), findsNothing);

      // PIN con su longitud guardada: sin botón, se comprueba al completarlo.
      expect(find.text('Desbloquear'), findsNothing);
      await typePin(tester, '0000');
      await settle(tester);
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.textContaining('PIN incorrecto'), findsOneWidget);

      await typePin(tester, '4821');
      await settle(tester);
      expect(find.text('LA APP'), findsOneWidget);
    });

    testWidgets('vuelve a bloquear tras más de 30 s en segundo plano', (
      tester,
    ) async {
      await pumpGate(tester, phone);
      await typePin(tester, '4821');
      await settle(tester);
      expect(find.text('LA APP'), findsOneWidget);

      final t0 = DateTime(2026, 11, 9, 10);
      withClock(Clock.fixed(t0), () {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      });
      // Con 10 s fuera, sigue abierta.
      withClock(Clock.fixed(t0.add(const Duration(seconds: 10))), () {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      });
      await tester.pump();
      expect(find.text('LA APP'), findsOneWidget);

      withClock(Clock.fixed(t0), () {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      });
      withClock(Clock.fixed(t0.add(const Duration(seconds: 45))), () {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      });
      await tester.pump();
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.text('LA APP'), findsNothing);
    });

    testWidgets('los puntos son tantos como cifras tiene el PIN', (
      tester,
    ) async {
      await pumpGate(tester, phone);
      final dots = find.descendant(
        of: find.byType(PinDots),
        matching: find.byType(Container),
      );
      expect(dots, findsNWidgets(4));
    });

    testWidgets('un PIN de 4 no pide más cifras ni botón; el error no cambia', (
      tester,
    ) async {
      await pumpGate(tester, phone);
      await typePin(tester, '1111');
      await settle(tester);
      expect(find.textContaining('PIN incorrecto'), findsOneWidget);
      expect(find.textContaining('4 intentos'), findsOneWidget);
    });

    testWidgets('con la huella activada, el diálogo salta solo y una vez', (
      tester,
    ) async {
      await phone.container
          .read(lockControllerProvider.notifier)
          .setBiometrics(true, reason: 'x');
      expect(phone.biometrics.prompts, 1);
      phone.biometrics
        ..prompts = 0
        ..succeeds = false;
      phone.restart();
      await pumpGate(tester, phone);
      await settle(tester);
      expect(phone.biometrics.prompts, 1);
      expect(find.byType(LockScreen), findsOneWidget);
      // Reconstruir la pantalla sin que "aparezca" de nuevo no repite.
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(phone.biometrics.prompts, 1);

      // Si sale bien, entra sin teclear.
      phone.biometrics.succeeds = true;
      phone.restart();
      await pumpGate(tester, phone);
      await settle(tester);
      expect(phone.biometrics.prompts, 2);
      expect(find.text('LA APP'), findsOneWidget);
    });

    testWidgets('sin huella activada no salta ningún diálogo', (tester) async {
      await pumpGate(tester, phone);
      await settle(tester);
      expect(phone.biometrics.prompts, 0);
    });

    group('ciclo de vida del diálogo de huella', () {
      Future<void> enableBiometricsFailing() async {
        await phone.container
            .read(lockControllerProvider.notifier)
            .setBiometrics(true, reason: 'x');
        phone.biometrics
          ..prompts = 0
          ..succeeds = false;
        phone.restart();
      }

      void lifecycle(WidgetTester tester, AppLifecycleState state) =>
          tester.binding.handleAppLifecycleStateChanged(state);

      const platforms = TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      });
      {
        testWidgets(
          'inactive -> resumed con el diálogo no lo repite y deja el teclado',
          variant: platforms,
          (tester) async {
            await enableBiometricsFailing();
            await pumpGate(tester, phone);
            await settle(tester);
            expect(phone.biometrics.prompts, 1);

            // El diálogo del sistema deja la app inactiva. En iOS la
            // cubierta sustituye a la pantalla de bloqueo, que se destruye;
            // en Android `inactive` no tapa (persiana, captura, diálogos) y
            // la pantalla de bloqueo sigue.
            lifecycle(tester, AppLifecycleState.inactive);
            await tester.pump();
            expect(
              find.byType(LockScreen),
              defaultTargetPlatform == TargetPlatform.android
                  ? findsOneWidget
                  : findsNothing,
            );
            expect(find.text('LA APP'), findsNothing);

            // Se cancela o falla: la app vuelve y se crea otra pantalla.
            lifecycle(tester, AppLifecycleState.resumed);
            await tester.pump();
            await settle(tester);
            expect(find.byType(LockScreen), findsOneWidget);
            expect(phone.biometrics.prompts, 1, reason: 'sin bucle de huella');

            // Otra vuelta del ciclo tampoco la repite.
            lifecycle(tester, AppLifecycleState.inactive);
            await tester.pump();
            lifecycle(tester, AppLifecycleState.resumed);
            await tester.pump();
            await settle(tester);
            expect(phone.biometrics.prompts, 1);

            // El teclado del PIN sigue disponible.
            await typePin(tester, '4821');
            await settle(tester);
            expect(find.text('LA APP'), findsOneWidget);
            expect(phone.biometrics.prompts, 1);
          },
        );

        testWidgets(
          'la huella solo se vuelve a pedir con su botón',
          variant: platforms,
          (tester) async {
            final semantics = tester.ensureSemantics();
            await enableBiometricsFailing();
            await pumpGate(tester, phone);
            await settle(tester);
            expect(phone.biometrics.prompts, 1);

            lifecycle(tester, AppLifecycleState.inactive);
            await tester.pump();
            lifecycle(tester, AppLifecycleState.resumed);
            await tester.pump();
            await settle(tester);
            expect(phone.biometrics.prompts, 1);

            await tester.tap(find.bySemanticsLabel('Usar huella o rostro'));
            await settle(tester);
            expect(phone.biometrics.prompts, 2);
            semantics.dispose();
          },
        );
      }

      testWidgets('un bloqueo nuevo vuelve a pedir la huella automática', (
        tester,
      ) async {
        await enableBiometricsFailing();
        await pumpGate(tester, phone);
        await settle(tester);
        expect(phone.biometrics.prompts, 1);

        phone.biometrics.succeeds = true;
        await tester.runAsync(
          () => phone.container
              .read(lockControllerProvider.notifier)
              .unlockWithBiometrics('x'),
        );
        await settle(tester);
        expect(find.text('LA APP'), findsOneWidget);
        expect(phone.biometrics.prompts, 2);
        // Acaba el fundido de salida de la pantalla de bloqueo.
        await tester.pumpAndSettle();

        phone.biometrics.succeeds = false;
        await tester.runAsync(
          () => phone.container.read(lockControllerProvider.notifier).lockNow(),
        );
        await settle(tester);
        await settle(tester);
        expect(find.byType(LockScreen), findsOneWidget);
        expect(phone.biometrics.prompts, 3);
      });
    });

    testWidgets('al bloquear se descarta el aviso del regalo', (tester) async {
      await pumpGate(
        tester,
        phone,
        child: const Scaffold(body: Text('LA APP')),
      );
      await typePin(tester, '4821');
      await settle(tester);
      expect(find.text('LA APP'), findsOneWidget);
      // El candado espera 80 ms a la ola de los puntos y se va en 375 ms:
      // hasta que acaba, su `Scaffold` también pintaría el aviso.
      await tester.pumpAndSettle();

      final messenger = ScaffoldMessenger.of(
        tester.element(find.text('LA APP')),
      );
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Bicicleta: Comprado'),
          duration: Duration(seconds: 4),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Bicicleta: Comprado'), findsOneWidget);

      await tester.runAsync(
        () => phone.container.read(lockControllerProvider.notifier).lockNow(),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.text('Bicicleta: Comprado'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Bicicleta: Comprado'), findsNothing);
    });

    testWidgets('atrasar la hora fuera de la app no evita el rebloqueo', (
      tester,
    ) async {
      await pumpGate(tester, phone);
      await typePin(tester, '4821');
      await settle(tester);
      expect(find.text('LA APP'), findsOneWidget);

      final t0 = DateTime(2026, 11, 9, 10);
      withClock(Clock.fixed(t0), () {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      });
      withClock(Clock.fixed(t0.subtract(const Duration(hours: 3))), () {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      });
      await tester.pump();
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.text('LA APP'), findsNothing);
    });

    final platforms = const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    });

    testWidgets(
      'desbloquear con PIN e inactive->resumed dentro de los 80 ms no deja velo',
      variant: platforms,
      (tester) async {
        await pumpGate(tester, phone);
        await typePin(tester, '4821');
        // Esperar al desbloqueo efectivo y a que arranque la espera del PIN.
        await tester.pump();
        await tester.pump();
        // Mientras dura la espera de 80 ms el fundido no ha arrancado.
        expect(find.byType(LockScreen), findsOneWidget);
        final opacityWhileWaiting = tester.widget<Opacity>(
          find.ancestor(
            of: find.text('LA APP'),
            matching: find.byType(Opacity),
          ).first,
        ).opacity;
        expect(opacityWhileWaiting, 0.4);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.text('LA APP'), findsOneWidget);
        expect(find.byType(LockScreen), findsNothing);
        expect(tester.hasRunningAnimations, isFalse);
        for (final o in tester.widgetList<Opacity>(find.byType(Opacity))) {
          expect(o.opacity, 1.0);
        }
      },
    );

    testWidgets(
      'desbloquear con PIN y paused->resumed a mitad del fundido no deja velo',
      variant: platforms,
      (tester) async {
        await pumpGate(tester, phone);
        await typePin(tester, '4821');
        // Esperar al desbloqueo efectivo y a que arranque la espera del PIN.
        await tester.pump();
        await tester.pump();
        // Comprobación de la espera del PIN antes de arrancar el ticker.
        expect(find.byType(LockScreen), findsOneWidget);
        final opacityWhileWaiting = tester.widget<Opacity>(
          find.ancestor(
            of: find.text('LA APP'),
            matching: find.byType(Opacity),
          ).first,
        ).opacity;
        expect(opacityWhileWaiting, 0.4);
        // Arrancar el ticker y avanzar otro intervalo: fundido a mitad.
        await tester.pump(const Duration(milliseconds: 80));
        await tester.pump(const Duration(milliseconds: 40));
        final opacityMid = tester.widget<Opacity>(
          find.ancestor(
            of: find.text('LA APP'),
            matching: find.byType(Opacity),
          ).first,
        ).opacity;
        expect(opacityMid, greaterThan(0.4));
        expect(opacityMid, lessThan(1.0));
        expect(find.byType(LockScreen), findsOneWidget);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        // La app queda cubierta durante más de un segundo.
        await tester.pump(const Duration(seconds: 1, milliseconds: 100));
        expect(find.text('LA APP'), findsNothing);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.text('LA APP'), findsOneWidget);
        expect(find.byType(LockScreen), findsNothing);
        expect(tester.hasRunningAnimations, isFalse);
        for (final o in tester.widgetList<Opacity>(find.byType(Opacity))) {
          expect(o.opacity, 1.0);
        }
      },
    );

    testWidgets(
      'la red de seguridad deja la app limpia si el fundido se atasca',
      (tester) async {
        tester.view
          ..physicalSize = const Size(390, 900)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final gateKey = GlobalKey();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: phone.container,
            child: MaterialApp(
              locale: const Locale('es'),
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              theme: buildTheme(AccentId.lavender.palette, Brightness.light),
              home: TickerMode(
                enabled: true,
                child: LockGate(key: gateKey, child: const Text('LA APP')),
              ),
            ),
          ),
        );
        await settle(tester);

        await typePin(tester, '4821');
        await settle(tester);
        await tester.pump();

        // Suspender el ticker preservando el estado del fundido.
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: phone.container,
            child: MaterialApp(
              locale: const Locale('es'),
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              theme: buildTheme(AccentId.lavender.palette, Brightness.light),
              home: TickerMode(
                enabled: false,
                child: LockGate(key: gateKey, child: const Text('LA APP')),
              ),
            ),
          ),
        );
        await tester.pump();

        // Deja pasar el temporizador de 80 ms: con el ticker suspendido no
        // avanza el fundido.
        await tester.pump(const Duration(milliseconds: 90));

        // Deja pasar el temporizador de 80 ms: con el ticker suspendido no
        // avanza el fundido.
        await tester.pump(const Duration(milliseconds: 90));
        // Estado intermedio: persiste antes del límite de 1 s.
        expect(find.byType(LockScreen), findsOneWidget);

        // Vence el segundo: la red de seguridad limpia aunque siga suspendido.
        await tester.pump(const Duration(seconds: 1, milliseconds: 100));
        await tester.pump();
        expect(find.text('LA APP'), findsOneWidget);
        expect(find.byType(LockScreen), findsNothing);
        expect(tester.hasRunningAnimations, isFalse);
        for (final o in tester.widgetList<Opacity>(find.byType(Opacity))) {
          expect(o.opacity, 1.0);
        }
      },
    );

    testWidgets(
      'un bloqueo nuevo a mitad del fundido cancela y permite desbloquear después',
      variant: platforms,
      (tester) async {
        await pumpGate(tester, phone);
        await typePin(tester, '4821');
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        await tester.pump(const Duration(milliseconds: 40));
        expect(find.byType(LockScreen), findsOneWidget);

        await tester.runAsync(
          () => phone.container.read(lockControllerProvider.notifier).lockNow(),
        );
        await tester.pump();
        await tester.pump();
        // El fundido se cancela: vuelve a mostrarse la pantalla de bloqueo.
        expect(find.byType(LockScreen), findsOneWidget);
        expect(find.text('LA APP'), findsNothing);

        // Desbloqueo posterior funciona.
        await typePin(tester, '4821');
        await settle(tester);
        await tester.pumpAndSettle();
        expect(find.text('LA APP'), findsOneWidget);
        expect(find.byType(LockScreen), findsNothing);
        expect(tester.hasRunningAnimations, isFalse);
      },
    );

    testWidgets(
      'desmontar con temporizadores pendientes no lanza excepción',
      (tester) async {
        await pumpGate(tester, phone);
        await typePin(tester, '4821');
        await tester.pump();
        await tester.pump();
        // Temporizadores pendientes (80 ms y red de seguridad).
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        // Si llega aquí, no hubo excepción.
        expect(true, isTrue);
      },
    );
  });

  group('con un PIN antiguo sin longitud guardada', () {
    setUp(() async {
      await phone.container
          .read(familyControllerProvider.notifier)
          .createFamily(deviceName: 'A');
      await phone.container
          .read(lockControllerProvider.notifier)
          .setPin('4821');
      final record =
          jsonDecode(phone.secrets.values['lock.pin']!) as Map<String, Object?>;
      expect(record['len'], 4);
      record.remove('len');
      phone.secrets.values['lock.pin'] = jsonEncode(record);
      phone.restart();
    });

    testWidgets('mantiene el botón «Desbloquear» y seis puntos', (
      tester,
    ) async {
      await pumpGate(tester, phone);
      expect(find.text('Desbloquear'), findsOneWidget);
      final dots = find.descendant(
        of: find.byType(PinDots),
        matching: find.byType(Container),
      );
      expect(dots, findsNWidgets(6));
      await typePin(tester, '4821');
      await settle(tester);
      // Cuatro cifras no bastan para comprobarlo solo: hay que pulsar el botón.
      expect(find.byType(LockScreen), findsOneWidget);
      await tester.tap(find.text('Desbloquear'));
      await settle(tester);
      expect(find.text('LA APP'), findsOneWidget);
    });
  });
}
