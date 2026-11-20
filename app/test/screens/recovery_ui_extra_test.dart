// Segunda ronda del código de recuperación en la interfaz: las salidas de la
// lista traspasada, la recuperación a medias en la bienvenida, el PIN antes de
// enseñar, sustituir o quitar, cancelar según la fase y el bloqueo de capturas.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/widgets/settings_row.dart';
import 'package:regalos/features/lock/presentation/pin_pad.dart';
import 'package:regalos/features/recovery/presentation/recovery_restore_screen.dart';
import 'package:regalos/features/recovery/presentation/transferred_gate.dart';
import 'package:regalos/features/sync/application/recovery_providers.dart';

import '../helpers/screens.dart';
import 'recovery_ui_test.dart'
    show
        clipboardWrites,
        createUntilWords,
        display,
        fake,
        openRecover,
        openRecoveryRow,
        pasteAll,
        recoveryTest,
        spin,
        submit;
import 'settings_test.dart' show openSettings;

const _pendingNotClaimed = RecoveryStatus(
  RecoveryReadiness.needsAttention,
  phase: RecoveryPhase.needsAttention,
  cause: 'network',
);

const _pendingClaimed = RecoveryStatus(
  RecoveryReadiness.needsAttention,
  phase: RecoveryPhase.needsAttention,
  cause: 'missing_common_keyring',
  claimSent: true,
);

Future<void> typePin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.text(digit));
    await tester.pump();
  }
}

/// Da tiempo a lo real (comprobar el PIN, almacenes) y repinta.
Future<void> real(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await spin(tester, 4);
}

/// Los campos de las 24 palabras: solo los de la pantalla de recuperar, no el
/// buscador de la app que queda tapada debajo de la puerta.
Finder get _words => find.descendant(
  of: find.byType(RecoveryRestoreScreen),
  matching: find.byType(TextField),
);

void main() {
  group('lista traspasada: salidas', () {
    recoveryTest(
      '«Recuperar con mi código» abre las palabras por encima de la puerta',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tester.tap(find.text('Recuperar con mi código'));
        await tester.pump();
        await spin(tester, 6);
        expect(find.text('Recuperar la lista'), findsNWidgets(2));
        expect(_words, findsNWidgets(24));
        // Atrás vuelve a la pantalla de solo lectura.
        await tester.tap(find.bySemanticsLabel('Atrás'));
        await settle(tester);
        expect(_words, findsNothing);
        expect(
          find.descendant(
            of: find.byType(TransferredScreen),
            matching: find.text('Esta lista se ha pasado a otro móvil'),
          ),
          findsOneWidget,
        );
      },
      initial: const RecoveryStatus(RecoveryReadiness.transferred),
    );

    recoveryTest('«Borrar todo de este móvil» pide confirmación', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.tap(find.text('Borrar todo de este móvil'));
      await settle(tester);
      expect(find.text('¿Borrar todo?'), findsOneWidget);
      expect(find.text('Continuar'), findsOneWidget);
    }, initial: const RecoveryStatus(RecoveryReadiness.transferred));
  });

  group('recuperación a medias en la bienvenida', () {
    recoveryTest(
      'avisa, no deja crear ni unirse y reanuda en la pantalla de recuperar',
      (tester, phone) async {
        await pumpRegalos(tester, phone);
        expect(find.text('Hay una recuperación en curso'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Empezar'),
              )
              .onPressed,
          isNull,
        );
        final resume = find.text('Reanudar');
        await tester.ensureVisible(resume);
        await tester.pump();
        await tester.tap(resume);
        await settle(tester);
        // Se ve el estado real, no el formulario.
        expect(_words, findsNothing);
      },
      initial: _pendingNotClaimed,
    );

    recoveryTest(
      'cancelar antes de la reclamación: texto de datos temporales',
      (tester, phone) async {
        await pumpRegalos(tester, phone);
        final cancel = find.text('Cancelar la recuperación');
        await tester.ensureVisible(cancel);
        await tester.pump();
        await tester.tap(cancel);
        await settle(tester);
        expect(find.textContaining('datos temporales'), findsOneWidget);
        expect(find.textContaining('ya se ha pasado'), findsNothing);
        await tester.tap(find.text('Cancelar recuperación'));
        await settle(tester);
        expect(fake.calls, contains('abandon'));
        expect(find.text('Hay una recuperación en curso'), findsNothing);
      },
      initial: _pendingNotClaimed,
    );

    recoveryTest('cancelar después de la reclamación: dice que no se deshace', (
      tester,
      phone,
    ) async {
      await pumpRegalos(tester, phone);
      final cancel = find.text('Cancelar la recuperación');
      await tester.ensureVisible(cancel);
      await tester.pump();
      await tester.tap(cancel);
      await settle(tester);
      expect(find.textContaining('cancelar no lo deshace'), findsOneWidget);
      expect(find.textContaining('datos temporales'), findsNothing);
    }, initial: _pendingClaimed);

    recoveryTest(
      'salir de la pantalla de recuperar a medias pregunta y no pierde nada',
      (tester, phone) async {
        await pumpRegalos(tester, phone);
        final resume = find.text('Reanudar');
        await tester.ensureVisible(resume);
        await tester.pump();
        await tester.tap(resume);
        await settle(tester);
        await tester.tap(find.bySemanticsLabel('Atrás'));
        await settle(tester);
        expect(find.text('¿Salir de la recuperación?'), findsOneWidget);
        await tester.tap(find.text('Seguir aquí'));
        await settle(tester);
        expect(fake.calls, isNot(contains('abandon')));
        await tester.tap(find.bySemanticsLabel('Atrás'));
        await settle(tester);
        await tester.tap(find.text('Salir'));
        await settle(tester);
        // Vuelve a la bienvenida, con el aviso todavía.
        expect(find.text('Hay una recuperación en curso'), findsOneWidget);
        expect(fake.calls, isNot(contains('abandon')));
      },
      initial: _pendingNotClaimed,
    );

    recoveryTest(
      'una recuperación que sigue al abrir se puede reanudar o cancelar',
      (tester, phone) async {
        await pumpRegalos(tester, phone);
        final resume = find.text('Reanudar');
        await tester.ensureVisible(resume);
        await tester.pump();
        await tester.tap(resume);
        await spin(tester, 10);
        expect(find.text('Recuperando la lista'), findsOneWidget);
        expect(find.text('Reanudar'), findsOneWidget);
        expect(find.text('Cancelar la recuperación'), findsOneWidget);
      },
      initial: const RecoveryStatus(
        RecoveryReadiness.updatePending,
        phase: RecoveryPhase.downloading,
        claimSent: true,
      ),
    );
  });

  group('PIN o huella', () {
    recoveryTest('las palabras guardadas no se consumen hasta pasar el PIN', (
      tester,
      phone,
    ) async {
      fake.reclaim = display;
      await seedSample(tester, phone, pin: true);
      await pumpRegalos(tester, phone);
      await openRecoveryRow(tester);
      await tester.tap(find.text('Crear código de recuperación'));
      await real(tester);
      // Se sabe que hay palabras, sin consumirlas.
      expect(fake.calls, contains('has'));
      await tester.tap(find.text('Continuar'));
      await real(tester);
      expect(
        find.text('Escribe tu PIN para ver las palabras.'),
        findsOneWidget,
      );
      expect(fake.calls, isNot(contains('take')));
      // El PIN guardado tiene cuatro dígitos: tanto el dibujo como la
      // etiqueta usan esa longitud antes de mostrar las palabras.
      expect(
        tester
            .widget<Row>(
              find.descendant(
                of: find.byType(PinDots),
                matching: find.byType(Row),
              ),
            )
            .children,
        hasLength(4),
      );
      expect(find.bySemanticsLabel('PIN: 0 de 4 dígitos'), findsOneWidget);
      await typePin(tester, '1234');
      expect(find.bySemanticsLabel('PIN: 4 de 4 dígitos'), findsOneWidget);
      await typePin(tester, '5');
      expect(find.bySemanticsLabel('PIN: 4 de 4 dígitos'), findsOneWidget);
      await tester.tap(find.text('Continuar'));
      await real(tester);
      await settle(tester);
      expect(fake.calls, contains('take'));
      expect(find.text('Tus 24 palabras'), findsOneWidget);
    });

    recoveryTest('sustituir la lista de este móvil pide el PIN', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone, pin: true);
      await pumpRegalos(tester, phone);
      phone.container.read(routerProvider).go(AppRoutes.recover);
      await settle(tester);
      await pasteAll(tester, display.words.join(' '));
      fake.restoreFinal = const RecoveryStatus(
        RecoveryReadiness.needsAttention,
        phase: RecoveryPhase.needsAttention,
        cause: 'different_family',
      );
      await tester.tap(submit);
      await spin(tester, 10);
      expect(find.text('¿Sustituir la lista de este móvil?'), findsOneWidget);
      expect(
        find.textContaining('se conserva en el móvil, pero deja de verse'),
        findsOneWidget,
      );
      fake.restoreFinal = const RecoveryStatus(RecoveryReadiness.prepared);
      await tester.tap(find.text('Sustituir').last);
      await real(tester);
      expect(
        find.text('Escribe tu PIN para sustituir la lista de este móvil.'),
        findsOneWidget,
      );
      expect(fake.calls, ['words']);
      await typePin(tester, '1234');
      await tester.tap(find.text('Continuar'));
      await real(tester);
      await spin(tester, 10);
      expect(fake.calls, ['words', 'words+replace']);
    });

    recoveryTest('quitar el código pide el PIN después de confirmar', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone, pin: true);
      await pumpRegalos(tester, phone);
      await openRecoveryRow(tester);
      await tapText(tester, 'Quitar el código');
      await tapText(tester, 'Quitar código');
      await real(tester);
      expect(
        find.text('Escribe tu PIN para quitar el código.'),
        findsOneWidget,
      );
      expect(fake.calls, isNot(contains('retire')));
      await typePin(tester, '1234');
      await tester.tap(find.text('Continuar'));
      await real(tester);
      await settle(tester);
      expect(fake.calls, contains('retire'));
    }, initial: const RecoveryStatus(RecoveryReadiness.prepared));
  });

  group('pegar y cancelar', () {
    recoveryTest('pegar las 24 palabras vacía el portapapeles', (
      tester,
      phone,
    ) async {
      await pumpRegalos(tester, phone);
      await openRecover(tester);
      await pasteAll(tester, display.words.join(' '));
      expect(find.text('24 de 24 palabras'), findsOneWidget);
      expect(clipboardWrites, ['']);
    });

    recoveryTest('una preparación atascada se cancela con confirmación', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openSettings(tester);
      final row = find.widgetWithText(SettingsRow, 'Código de recuperación');
      await tester.ensureVisible(row);
      await tester.pump();
      await tester.tap(row);
      await spin(tester);
      expect(find.text('Cancelar la preparación'), findsOneWidget);
      await tester.tap(find.text('Cancelar la preparación'));
      await spin(tester);
      expect(find.text('¿Cancelar la preparación del código?'), findsOneWidget);
      await tester.tap(find.text('Cancelar preparación'));
      await spin(tester, 8);
      expect(fake.calls, contains('cancelMaintenance'));
    }, initial: const RecoveryStatus(RecoveryReadiness.updatePending));

    recoveryTest(
      'una recuperación a medias se cancela desde el estado de Ajustes',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await openRecoveryRow(tester);
        expect(find.text('Cancelar la recuperación'), findsOneWidget);
        await tester.tap(find.text('Cancelar la recuperación'));
        await settle(tester);
        expect(find.textContaining('cancelar no lo deshace'), findsOneWidget);
        await tester.tap(find.text('Cancelar recuperación'));
        await settle(tester);
        expect(fake.calls, contains('abandon'));
      },
      initial: _pendingClaimed,
    );
  });

  group('bloqueo de capturas', () {
    recoveryTest('en Android se bloquea solo mientras se ven las palabras', (
      tester,
      phone,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.dferrandizmont.regalos/incoming'),
        (call) async {
          calls.add('${call.method}:${call.arguments}');
          return null;
        },
      );
      try {
        await createUntilWords(tester, phone);
        expect(calls, contains('setSecure:true'));
        expect(calls.where((c) => c == 'setSecure:false'), isEmpty);
        // El QR también está bajo el bloqueo y el aviso no dice nada raro.
        expect(find.textContaining('no puede bloquear'), findsNothing);
        await tapText(tester, 'Ya las he guardado');
        final asked = RegExp(r'\d+')
            .allMatches(
              tester
                  .widgetList<Text>(find.textContaining('Escribe las palabras'))
                  .first
                  .data!,
            )
            .map((m) => int.parse(m[0]!))
            .toList();
        for (var i = 0; i < 3; i++) {
          await tester.enterText(
            find.byType(TextField).at(i),
            display.words[asked[i] - 1],
          );
        }
        await tapText(tester, 'Comprobar');
        // Al salir de las palabras, se quita.
        expect(calls.last, 'setSecure:false');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    recoveryTest('en iPhone el aviso dice que no se pueden bloquear', (
      tester,
      phone,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await createUntilWords(tester, phone);
        expect(find.textContaining('no puede bloquear'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('puerta: recuperar desde la lista traspasada', () {
    const transferred = RecoveryStatus(
      RecoveryReadiness.transferred,
      installationTransferred: true,
    );

    recoveryTest(
      'la puerta sigue con el progreso y los errores, y se quita al acabar',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tester.tap(find.text('Recuperar con mi código'));
        await settle(tester);
        await pasteAll(tester, display.words.join(' '));
        fake.holdRestore = Completer<void>();
        fake.restoreFinal = const RecoveryStatus(
          RecoveryReadiness.needsAttention,
          phase: RecoveryPhase.needsAttention,
          cause: 'not_found',
          installationTransferred: true,
        );
        await tester.tap(submit);
        await spin(tester, 10);
        // Las fases ponen «actualización pendiente»: la puerta no se retira.
        expect(find.text('Recuperando la lista'), findsOneWidget);
        // Un error terminal mantiene la puerta y se ve en su pantalla.
        fake.holdRestore!.complete();
        await spin(tester, 10);
        expect(find.text('Ese código no abre ninguna lista'), findsOneWidget);
        // Otro intento con éxito quita la puerta y deja ver la app.
        fake.restoreFinal = const RecoveryStatus(RecoveryReadiness.prepared);
        fake.holdRestore = null;
        await tester.tap(find.text('Escribir otro código'));
        await spin(tester, 8);
        await pasteAll(tester, display.words.join(' '));
        await tester.tap(submit);
        await spin(tester, 14);
        expect(find.byType(TransferredScreen), findsNothing);
        expect(find.byType(FloatingActionButton).hitTestable(), findsWidgets);
      },
      initial: transferred,
    );

    recoveryTest('otra familia desde la puerta pregunta dentro de la puerta', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.tap(find.text('Recuperar con mi código'));
      await settle(tester);
      await pasteAll(tester, display.words.join(' '));
      fake.restoreFinal = const RecoveryStatus(
        RecoveryReadiness.needsAttention,
        phase: RecoveryPhase.needsAttention,
        cause: 'different_family',
        installationTransferred: true,
      );
      await tester.tap(submit);
      await spin(tester, 12);
      expect(find.text('¿Sustituir la lista de este móvil?'), findsOneWidget);
    }, initial: transferred);

    recoveryTest(
      'el botón atrás del sistema vuelve a la lista traspasada y luego sale',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        final exits = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'SystemNavigator.pop') {
              exits.add(call.method);
            }
            return null;
          },
        );
        await tester.tap(find.text('Recuperar con mi código'));
        await settle(tester);
        expect(_words, findsNWidgets(24));
        await tester.binding.handlePopRoute();
        await settle(tester);
        expect(_words, findsNothing);
        expect(exits, isEmpty);
        // Ya en la pantalla de solo lectura, atrás sale de la app.
        await tester.binding.handlePopRoute();
        await settle(tester);
        expect(exits, ['SystemNavigator.pop']);
      },
      initial: transferred,
    );
  });

  group('atrás con una ruta apilada bajo la puerta', () {
    recoveryTest(
      'el atrás del sistema es de la puerta y no saca las rutas de debajo',
      (tester, phone) async {
        await seedSample(tester, phone);
        // En un móvil real, el despachador de atrás del router ya está
        // registrado en el binding cuando nace la puerta: aquí se registra
        // antes de montar la app para que el orden sea el peor.
        final router = phone.container.read(routerProvider);
        WidgetsBinding.instance.addObserver(
          router.backButtonDispatcher as RootBackButtonDispatcher,
        );
        addTearDown(
          () => WidgetsBinding.instance.removeObserver(
            router.backButtonDispatcher as RootBackButtonDispatcher,
          ),
        );
        await pumpRegalos(tester, phone);
        final exits = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'SystemNavigator.pop') {
              exits.add(call.method);
            }
            return null;
          },
        );
        // Ajustes › Código de recuperación: una ruta apilada en la app.
        await openRecoveryRow(tester);
        final stacked = router.routerDelegate.currentConfiguration.uri
            .toString();
        expect(router.canPop(), isTrue);
        // Mientras se mira, la lista se pasa a otro móvil: sale la puerta.
        fake.push(const RecoveryStatus(RecoveryReadiness.transferred));
        await settle(tester);
        expect(find.byType(TransferredScreen), findsOneWidget);
        await tester.tap(find.text('Recuperar con mi código'));
        await settle(tester);
        expect(find.byType(TextField), findsNWidgets(24));
        // Atrás cierra las palabras...
        await tester.binding.handlePopRoute();
        await settle(tester);
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(TransferredScreen), findsOneWidget);
        expect(exits, isEmpty);
        // ...y no ha tocado la ruta de debajo.
        expect(router.canPop(), isTrue);
        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          stacked,
        );
        // Ya en la pantalla de solo lectura, atrás sale de la app y deja la
        // ruta de debajo donde estaba.
        await tester.binding.handlePopRoute();
        await settle(tester);
        expect(exits, ['SystemNavigator.pop']);
        expect(router.canPop(), isTrue);
        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          stacked,
        );
      },
    );
  });

  group('«necesita atención» tiene salida', () {
    recoveryTest(
      'un fallo cerrado se descarta con «Entendido»',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await openRecoveryRow(tester);
        expect(find.text('Hay que revisar el código'), findsOneWidget);
        expect(find.text('Reintentar'), findsNothing);
        await tester.tap(find.text('Entendido'));
        await settle(tester);
        expect(fake.calls, contains('dismiss'));
        expect(find.text('Crear código de recuperación'), findsOneWidget);
      },
      initial: const RecoveryStatus(
        RecoveryReadiness.needsAttention,
        cause: 'recovery_retired',
        canDismissFailure: true,
      ),
    );

    recoveryTest(
      'tras cancelar una preparación con palabras pendientes se pide el PIN '
      'antes de verlas',
      (tester, phone) async {
        fake.reclaim = display;
        await seedSample(tester, phone, pin: true);
        await pumpRegalos(tester, phone);
        await openSettings(tester);
        final row = find.widgetWithText(SettingsRow, 'Código de recuperación');
        await tester.ensureVisible(row);
        await tester.pump();
        await tester.tap(row);
        await spin(tester);
        await tester.tap(find.text('Cancelar la preparación'));
        await spin(tester);
        await tester.tap(find.text('Cancelar preparación'));
        await real(tester);
        await spin(tester, 8);
        expect(fake.calls, contains('cancelMaintenance'));
        expect(fake.calls, contains('has'));
        // Se abre la pantalla de crear, sin consumir las palabras.
        expect(find.text('Continuar'), findsOneWidget);
        expect(fake.calls, isNot(contains('take')));
        await tester.tap(find.text('Continuar'));
        await real(tester);
        expect(
          find.text('Escribe tu PIN para ver las palabras.'),
          findsOneWidget,
        );
        expect(fake.calls, isNot(contains('take')));
      },
      initial: const RecoveryStatus(RecoveryReadiness.updatePending),
    );
  });

  group('bloqueo de capturas, tercera ronda', () {
    recoveryTest(
      'el bloqueo se pide al abrir recuperar y dura toda la pantalla',
      (tester, phone) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final calls = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('com.dferrandizmont.regalos/incoming'),
          (call) async {
            calls.add('${call.method}:${call.arguments}');
            return null;
          },
        );
        try {
          await pumpRegalos(tester, phone);
          await openRecover(tester);
          expect(calls.where((c) => c.startsWith('setSecure')), [
            'setSecure:true',
          ]);
          expect(find.byType(TextField), findsNWidgets(24));
          await tester.tap(find.bySemanticsLabel('Atrás'));
          await settle(tester);
          expect(calls.last, 'setSecure:false');
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });
}
