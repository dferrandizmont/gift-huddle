// Avisos persistentes de Móviles de la familia a partir del estado v2 (fase 3,
// lote 3b): otro móvil quitó este, sorpresas en pausa, renovación sugerida, y
// las filas «Acceso sin respaldo» y «Baja a medias» con su carga, su éxito y su
// error de red. Las acciones de resolución son un doble que apunta lo que se le
// pide; el motor real se prueba en `test/sync`.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:regalos/core/motion/success_mark.dart';
import 'package:regalos/core/sync/device_registry.dart' show RegistryChange;
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/features/sharing/presentation/share_screen.dart';
import 'package:regalos/features/sync/application/family_device_actions.dart'
    as device_actions;
import 'package:regalos/features/sync/application/family_device_review.dart';
import 'package:regalos/features/sync/application/family_device_rows.dart';
import 'package:regalos/features/sync/application/family_devices.dart';
import 'package:regalos/features/sync/application/sync_controller.dart';
import 'package:regalos/features/sync/domain/sync_status.dart';
import 'package:regalos/features/sync/application/sync_v2_engine.dart'
    show UnbackedRevocation;
import 'package:regalos/features/sync/application/v2_health_provider.dart';
import 'package:regalos/features/sync/application/v2_resolution_actions.dart';
import 'package:regalos/l10n/app_localizations.dart';

import '../helpers/fake_sync_server.dart';
import '../sync/invite_approval_view_test.dart' show phoneSize;
import '../sync/sync_harness.dart';
import 'family_devices_list_test.dart' show markV2;

class _Resolution implements V2ResolutionActions {
  _Resolution(this._preview);

  final _Preview _preview;
  final calls = <String>[];

  /// Lo que devuelve retirar un acceso.
  UnbackedRevocation outcome = UnbackedRevocation.revoked;

  /// Se llama al terminar una operación bien: la real refresca el registro y
  /// `health` deja de listar el problema.
  void Function()? onSuccess;

  /// Cuántas llamadas fallan antes de que una funcione.
  int failures = 0;

  /// La próxima llamada se queda esperando hasta completar este completer.
  Future<void>? gate;

  Future<void> _go(String call) async {
    calls.add(call);
    await gate;
    if (failures > 0) {
      failures--;
      throw StateError('sin red');
    }
  }

  @override
  Future<UnbackedRevocation> revokeUnbackedCredential(
    String credentialId,
  ) async {
    await _go('revoke $credentialId');
    onSuccess?.call();
    return outcome;
  }

  @override
  Future<device_actions.RemovalPreview> previewDeparture(
    String deviceId,
  ) async => device_actions.RemovalPreview(
    selfWouldWait: _preview.selfWouldWait,
    orphans: const [],
  );

  @override
  Future<RegistryChange?> completeDeparture(
    String deviceId, {
    bool selfWaitAccepted = false,
  }) async {
    if (_preview.selfWouldWait && !selfWaitAccepted) {
      throw StateError('N7 sin aceptar');
    }
    await _go('depart $deviceId');
    onSuccess?.call();
    return null;
  }
}

class _Preview implements FamilyDeviceActions {
  bool selfWouldWait = false;

  @override
  Future<DeviceRemovalPreview> previewRemoval(String deviceId) async =>
      DeviceRemovalPreview(selfWouldWait: selfWouldWait);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// El estado v2 que ve la pantalla: las pruebas lo cambian como lo haría la
/// propia operación al refrescar el registro.
class _HealthState extends Notifier<V2Health> {
  @override
  V2Health build() => V2Health();

  void set(V2Health health) => state = health;
}

final _healthState = NotifierProvider<_HealthState, V2Health>(_HealthState.new);

class _RemovedSync extends SyncController {
  @override
  SyncStatus build() => const SyncStatus(SyncPhase.removed);
}

const _self = FamilyDeviceRow(
  deviceId: 'a',
  isSelf: true,
  personId: 'aritz',
  deviceName: 'Pixel de Aritz',
);
const _nora = FamilyDeviceRow(deviceId: 'n', isSelf: false, personId: 'nora');

late List<String> _routes;

Future<(_Resolution, _Preview)> _open(
  WidgetTester tester,
  V2Health health, {
  bool reduceMotion = false,
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  phoneSize(tester);
  _routes = [];
  late SyncPhone a;
  await tester.runAsync(() async {
    a = await SyncPhone.create(FakeSyncServer());
    await a.createFamily('Pixel de Aritz');
    for (final name in ['Aritz', 'Nora', 'Leo']) {
      await a.family.upsertRecipient(
        Recipient(
          id: name.toLowerCase(),
          name: name,
          colorIndex: 0,
          archived: false,
        ),
      );
    }
    await markV2(a);
  });
  addTearDown(a.dispose);
  final preview = _Preview();
  final resolution = _Resolution(preview);
  a.c.read(_healthState.notifier).set(health);
  resolution.onSuccess = () => a.c.read(_healthState.notifier).set(V2Health());
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const ShareScreen()),
      GoRoute(
        path: '/join',
        builder: (_, _) {
          _routes.add('/join');
          return const Scaffold(body: Text('pantalla de unirse'));
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: a.c,
      child: ProviderScope(
        overrides: [
          if (health.revokedByOthers)
            syncControllerProvider.overrideWith(_RemovedSync.new),
          familyDeviceRowsProvider.overrideWith(
            (ref) async => [
              _self,
              if (!ref.watch(_healthState).revokedByOthers) _nora,
            ],
          ),
          deviceReviewProvider.overrideWith((ref) async => DeviceReview.empty),
          v2HealthProvider.overrideWith((ref) async => ref.watch(_healthState)),
          v2ResolutionActionsProvider.overrideWithValue(resolution),
          familyDeviceActionsProvider.overrideWithValue(preview),
        ],
        child: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 900),
            disableAnimations: reduceMotion,
            textScaler: TextScaler.linear(textScale),
          ),
          child: MaterialApp.router(
            locale: const Locale('es'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildTheme(AccentId.lavender.palette, brightness),
            routerConfig: router,
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  return (resolution, preview);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).first);
  await tester.tap(find.text(text).first);
  await _settle(tester);
}

void main() {
  group('avisos de arriba', () {
    testWidgets('otro móvil quitó este: explica, no es un fallo de conexión '
        'y lleva a conectar otra vez', (tester) async {
      await _open(
        tester,
        V2Health(revokedByOthers: true, frozenPeople: const ['nora']),
      );
      expect(
        find.text('Han quitado este móvil de la familia'),
        findsOneWidget,
      );
      expect(find.textContaining('siguen en este móvil'), findsOneWidget);
      expect(find.textContaining('conéctalo de nuevo en persona'), findsOneWidget);
      // Lo congelado es consecuencia de esto: no sale aparte.
      expect(find.textContaining('Sorpresas en pausa'), findsNothing);
      // No se confunde con un fallo de conexión.
      expect(find.text('Sin conexión'), findsNothing);
      expect(find.text('No se pudo sincronizar'), findsNothing);
      expect(
        find.text('El servidor no acepta la clave de esta familia.'),
        findsNothing,
      );
      expect(find.text('Todo al día'), findsNothing);
      expect(find.text('Nora'), findsNothing);
      expect(find.text('1'), findsOneWidget);
      await _tapText(tester, 'Conectar otra vez');
      expect(_routes, ['/join']);
      expect(find.text('pantalla de unirse'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('sorpresas en pausa: nombra a las personas y abre '
        '«Revisar móviles»', (tester) async {
      await _open(tester, V2Health(frozenPeople: const ['nora', 'leo', 'x']));
      expect(find.text('Sorpresas en pausa para Leo y Nora'), findsOneWidget);
      expect(find.textContaining('No se ha perdido nada'), findsOneWidget);
      expect(
        find.text('Han quitado este móvil de la familia'),
        findsNothing,
      );
      await _tapText(tester, 'Revisar móviles');
      // La bandeja está vacía: dice que todo está revisado.
      expect(find.text('Todo revisado'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('sin nombres conocidos, el título es genérico', (tester) async {
      await _open(tester, V2Health(frozenPeople: const ['borrada']));
      expect(find.text('Sorpresas en pausa'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('renovar pronto es solo una nota discreta, sin botón', (
      tester,
    ) async {
      await _open(tester, V2Health(renewSuggested: true));
      expect(find.text('Conviene renovar la lista pronto'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('sin nada que avisar no sale ningún aviso', (tester) async {
      await _open(tester, V2Health());
      expect(find.textContaining('Sorpresas en pausa'), findsNothing);
      expect(find.textContaining('Han quitado este'), findsNothing);
      expect(find.text('Por resolver'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('los avisos también salen en modo oscuro y sin movimiento', (
      tester,
    ) async {
      await _open(
        tester,
        V2Health(
          revokedByOthers: true,
          unbackedCredentials: const ['cred-1234567890'],
        ),
        reduceMotion: true,
        brightness: Brightness.dark,
      );
      expect(find.text('Conectar otra vez'), findsOneWidget);
      expect(find.text('Acceso sin identificar'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('acceso sin respaldo', () {
    testWidgets('pide confirmación, carga, celebra y se pliega', (
      tester,
    ) async {
      final (resolution, _) = await _open(
        tester,
        V2Health(unbackedCredentials: const ['cred-1234567890']),
      );
      expect(find.text('Por resolver'), findsOneWidget);
      expect(find.text('Acceso sin identificar'), findsOneWidget);
      expect(find.text('Referencia: cred-123'), findsOneWidget);

      await _tapText(tester, 'Retirar acceso');
      expect(find.text('¿Retirar este acceso?'), findsOneWidget);
      expect(resolution.calls, isEmpty);

      // Cancelar no retira nada.
      await _tapText(tester, 'Cancelar');
      expect(resolution.calls, isEmpty);

      await _tapText(tester, 'Retirar acceso');
      // El botón del diálogo y el de la fila se llaman igual: el diálogo va
      // encima.
      await tester.tap(find.text('Retirar acceso').last);
      await tester.pump();
      expect(resolution.calls, ['revoke cred-1234567890']);
      await _settle(tester);
      expect(find.text('Acceso retirado'), findsOneWidget);
      expect(find.byType(SuccessMark), findsOneWidget);

      // Se queda un instante a la vista y luego se pliega.
      await tester.pump(const Duration(seconds: 2));
      await _settle(tester);
      expect(find.text('Acceso sin identificar'), findsNothing);
      expect(find.text('Por resolver'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('mientras carga enseña el estado y no deja repetir', (
      tester,
    ) async {
      final (resolution, _) = await _open(
        tester,
        V2Health(unbackedCredentials: const ['cred-1']),
      );
      final gate = Completer<void>();
      resolution.gate = gate.future;
      await _tapText(tester, 'Retirar acceso');
      await tester.tap(find.text('Retirar acceso').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Un momento'), findsOneWidget);
      expect(find.text('Retirar acceso'), findsNothing);
      gate.complete();
      await _settle(tester);
      expect(find.text('Acceso retirado'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await _settle(tester);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('error de red: lo dice y «Reintentar» lo completa', (
      tester,
    ) async {
      final (resolution, _) = await _open(
        tester,
        V2Health(unbackedCredentials: const ['cred-1']),
      );
      resolution.failures = 1;
      await _tapText(tester, 'Retirar acceso');
      await tester.tap(find.text('Retirar acceso').last);
      await _settle(tester);
      expect(
        find.text(
          'No se ha podido completar. Comprueba la conexión e inténtalo de '
          'nuevo.',
        ),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);
      // Reintentar no vuelve a preguntar: ya se confirmó la intención.
      await _tapText(tester, 'Reintentar');
      expect(find.text('¿Retirar este acceso?'), findsNothing);
      expect(resolution.calls, ['revoke cred-1', 'revoke cred-1']);
      expect(find.text('Acceso retirado'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await _settle(tester);
      await tester.pumpWidget(const SizedBox());
    });
  });

  for (final outcome in [
    UnbackedRevocation.alreadyResolved,
    UnbackedRevocation.keptBecauseBacked,
    UnbackedRevocation.knownMember,
  ]) {
    testWidgets('si no se corta nada ($outcome), no dice que se retiró', (
      tester,
    ) async {
      final (resolution, _) = await _open(
        tester,
        V2Health(unbackedCredentials: const ['cred-1']),
      );
      resolution.outcome = outcome;
      await _tapText(tester, 'Retirar acceso');
      await tester.tap(find.text('Retirar acceso').last);
      await _settle(tester);
      expect(resolution.calls, ['revoke cred-1']);
      expect(find.text('Ya no hace falta quitar este acceso.'), findsOneWidget);
      expect(find.text('Acceso retirado'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      await _settle(tester);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('si falla la operación no se anuncia nada: error y reintento', (
    tester,
  ) async {
    final (resolution, _) = await _open(
      tester,
      V2Health(unbackedCredentials: const ['cred-1']),
    );
    resolution.failures = 1;
    await _tapText(tester, 'Retirar acceso');
    await tester.tap(find.text('Retirar acceso').last);
    await _settle(tester);
    expect(find.text('Acceso retirado'), findsNothing);
    expect(find.text('Ya no hace falta quitar este acceso.'), findsNothing);
    expect(find.text('Reintentar'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('si health quita el id al terminar, la fila se queda hasta '
      'que venza el tiempo', (tester) async {
    await _open(tester, V2Health(unbackedCredentials: const ['cred-1']));
    await _tapText(tester, 'Retirar acceso');
    await tester.tap(find.text('Retirar acceso').last);
    // La operación ya refrescó el estado: `health` no lista el acceso.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Acceso retirado'), findsOneWidget);
    expect(find.text('Acceso sin identificar'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Acceso retirado'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    expect(find.text('Acceso retirado'), findsNothing);
    expect(find.text('Acceso sin identificar'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('si health quita el id mientras carga, sigue el estado de '
      'carga', (tester) async {
    final (resolution, _) = await _open(
      tester,
      V2Health(departedDevices: const ['n']),
    );
    final gate = Completer<void>();
    resolution.gate = gate.future;
    await _tapText(tester, 'Completar la baja');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Un momento'), findsOneWidget);
    // Otra vuelta refresca el estado y el móvil deja de figurar a medias.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShareScreen)),
    );
    container.read(_healthState.notifier).set(V2Health());
    await _settle(tester);
    expect(find.text('Un momento'), findsOneWidget);
    expect(find.text('Baja a medias: Nora'), findsOneWidget);
    gate.complete();
    await _settle(tester);
    expect(find.text('Baja completada'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('con el texto muy grande, resultado y carga crecen y no se '
      'recortan', (tester) async {
    final (resolution, _) = await _open(
      tester,
      V2Health(unbackedCredentials: const ['cred-1']),
      textScale: 2,
    );
    // Una ventana alta: el diálogo de confirmar, que no es de esta prueba,
    // con el texto al doble no cabe en una pantalla de teléfono.
    tester.view.physicalSize = const Size(390, 2600);
    await _settle(tester);
    resolution.outcome = UnbackedRevocation.knownMember;
    final gate = Completer<void>();
    resolution.gate = gate.future;
    await _tapText(tester, 'Retirar acceso');
    await tester.tap(find.text('Retirar acceso').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    gate.complete();
    await _settle(tester);
    final text = find.text('Ya no hace falta quitar este acceso.');
    expect(text, findsOneWidget);
    // Ocupa varias líneas, más que los 48 de antes, y nada se desborda.
    expect(tester.getSize(text).height, greaterThan(48));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    await tester.pumpWidget(const SizedBox());
  });

  group('baja a medias', () {
    testWidgets('«Completar la baja» llama a la acción y celebra', (
      tester,
    ) async {
      final (resolution, _) = await _open(
        tester,
        V2Health(departedDevices: const ['n']),
      );
      expect(find.text('Baja a medias: Nora'), findsOneWidget);
      await _tapText(tester, 'Completar la baja');
      expect(resolution.calls, ['depart n']);
      expect(find.text('Baja completada'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await _settle(tester);
      expect(find.text('Baja a medias: Nora'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('si este móvil volvería a esperar, avisa antes (N7)', (
      tester,
    ) async {
      final (resolution, preview) = await _open(
        tester,
        V2Health(departedDevices: const ['n']),
      );
      preview.selfWouldWait = true;
      await _tapText(tester, 'Completar la baja');
      expect(
        find.text('Tu móvil volverá a esperar aprobación'),
        findsOneWidget,
      );
      expect(resolution.calls, isEmpty);
      await _tapText(tester, 'Cancelar');
      expect(resolution.calls, isEmpty);
      expect(find.text('Completar la baja'), findsOneWidget);

      await _tapText(tester, 'Completar la baja');
      await _tapText(tester, 'Quitar igualmente');
      expect(resolution.calls, ['depart n']);
      await tester.pump(const Duration(seconds: 2));
      await _settle(tester);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('error de red: «Reintentar»', (tester) async {
      final (resolution, _) = await _open(
        tester,
        V2Health(departedDevices: const ['n']),
      );
      resolution.failures = 1;
      await _tapText(tester, 'Completar la baja');
      expect(find.text('Reintentar'), findsOneWidget);
      await _tapText(tester, 'Reintentar');
      expect(find.text('Baja completada'), findsOneWidget);
      expect(resolution.calls, ['depart n', 'depart n']);
      await tester.pump(const Duration(seconds: 2));
      await _settle(tester);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
