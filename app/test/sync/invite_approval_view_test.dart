import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/motion/success_mark.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/core/widgets/regalos_switch.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/sharing/presentation/share_screen.dart';
import 'package:regalos/features/sync/invites/invite_guest.dart';
import 'package:regalos/features/sync/invites/invite_host.dart';
import 'package:regalos/features/sync/presentation/invite_approval_view.dart';
import 'package:regalos/features/sync/presentation/invite_screen.dart';
import 'package:regalos/features/sync/presentation/join_invite_screen.dart';
import 'package:regalos/l10n/app_localizations.dart';

import '../helpers/fake_sync_server.dart';
import '../helpers/memory_stores.dart';
import '../helpers/pump_app.dart';
import 'sync_harness.dart';

/// La pantalla [home] con el tema, los idiomas y el contenedor del móvil.
Widget screenApp(ProviderContainer container, Widget home) =>
    UncontrolledProviderScope(
      container: container,
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
        home: home,
      ),
    );

void phoneSize(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(390, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('pantalla de aprobación', () {
    testWidgets(
      'enseña quién quiere unirse, el código y el aviso de compararlo',
      (tester) async {
        var accepted = 0;
        var rejected = 0;
        await pumpThemed(
          tester,
          SingleChildScrollView(
            child: InviteApprovalView(
              guestName: 'Marta',
              code: '030367',
              onAccept: () => accepted++,
              onReject: () => rejected++,
            ),
          ),
        );
        expect(find.text('Marta quiere unirse'), findsOneWidget);
        // Las cifras ruedan al aparecer.
        await tester.pump(const Duration(milliseconds: 900));
        expect(find.text('030 367'), findsOneWidget);
        expect(
          find.text('Compara este código con el que ve la otra persona.'),
          findsOneWidget,
        );
        expect(find.text('Código de verificación'), findsOneWidget);

        await tester.tap(find.text('Rechazar'));
        expect(rejected, 1);
        expect(accepted, 0);
        await tester.tap(find.text('Los códigos coinciden, dar acceso'));
        expect(accepted, 1);
      },
    );

    testWidgets('mientras sube la aprobación los botones no responden', (
      tester,
    ) async {
      var accepted = 0;
      await pumpThemed(
        tester,
        SingleChildScrollView(
          child: InviteApprovalView(
            guestName: 'Marta',
            code: '123456',
            busy: true,
            onAccept: () => accepted++,
            onReject: () {},
          ),
        ),
      );
      await tester.tap(
        find.text('Los códigos coinciden, dar acceso'),
        warnIfMissed: false,
      );
      expect(accepted, 0);
    });

    testWidgets('con un nombre larguísimo y letra grande no se desborda', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        SingleChildScrollView(
          child: InviteApprovalView(
            guestName: 'M' * 40,
            code: '000001',
            onAccept: () {},
            onReject: () {},
          ),
        ),
        textScale: 1.6,
        surfaceSize: const Size(320, 700),
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('000 001'), findsOneWidget);
    });
  });

  group('pantallas contra el servidor falso', () {
    testWidgets(
      'Invitar a alguien: crear, esperar, ver la petición con el código y dar acceso',
      (tester) async {
        phoneSize(tester);
        final server = FakeSyncServer();
        late SyncPhone a;
        late SyncPhone b;
        await tester.runAsync(() async {
          a = await SyncPhone.create(server);
          await a.createFamily();
          b = await SyncPhone.create(server);
        });
        addTearDown(a.dispose);
        addTearDown(b.dispose);
        await tester.pumpWidget(screenApp(a.c, const InviteScreen()));
        await tester.pump();
        expect(find.text('Crear enlace e invitar'), findsOneWidget);
        expect(find.textContaining('no lleva ninguna clave'), findsOneWidget);

        await tester.runAsync(() async {
          await tester.tap(find.text('Crear enlace e invitar'));
          await eventually(() => a.c.read(inviteHostProvider).link != null);
        });
        await tester.pump();
        expect(find.text('Esperando a que abran el enlace'), findsOneWidget);
        final link = a.c.read(inviteHostProvider).link!;

        final sub = b.c.listen(inviteGuestProvider, (_, _) {});
        addTearDown(sub.close);
        await tester.runAsync(() async {
          await b.c
              .read(inviteGuestProvider.notifier)
              .begin(link, deviceName: 'Marta');
          await eventually(() => a.c.read(inviteHostProvider).code != null);
        });
        await tester.pump();
        expect(find.text('Marta quiere unirse'), findsOneWidget);
        final code = a.c.read(inviteHostProvider).code!;
        await tester.pump(const Duration(milliseconds: 900));
        expect(
          find.text('${code.substring(0, 3)} ${code.substring(3)}'),
          findsOneWidget,
        );
        // B ve el mismo código antes de que A confirme.
        await tester.runAsync(
          () => eventually(
            () => b.c.read(inviteGuestProvider).phase == JoinPhase.compare,
          ),
        );
        expect(b.c.read(inviteGuestProvider).code, code);

        await tester.runAsync(() async {
          await tester.tap(find.text('Los códigos coinciden, dar acceso'));
          await eventually(
            () => a.c.read(inviteHostProvider).phase == InvitePhase.approved,
          );
        });
        await tester.pump();
        expect(find.text('Invitación aceptada'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('Móviles de la familia: tarjeta de estado sin interruptor, Sincronizar ahora, '
        'Dejar de sincronizar en una hoja y Encender', (tester) async {
      phoneSize(tester);
      final server = FakeSyncServer();
      late SyncPhone a;
      await tester.runAsync(() async {
        a = await SyncPhone.create(server);
        await a.createFamily();
        await a.c
            .read(familyControllerProvider.notifier)
            .markPaired(peerName: 'Móvil de Nora');
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      addTearDown(a.dispose);
      await tester.pumpWidget(screenApp(a.c, const ShareScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Todo al día'), findsOneWidget);
      expect(
        find.text('Sincronizado ahora. Cifrado de extremo a extremo.'),
        findsOneWidget,
      );
      expect(find.text('Móvil de Nora'), findsOneWidget);
      // Ni interruptor ni pantalla de Sincronización.
      expect(find.byType(RegalosSwitch), findsNothing);
      expect(find.byType(Switch), findsNothing);
      expect(find.text('Sincronizar automáticamente'), findsNothing);
      // El sello solo rebota cuando la persona pide sincronizar.
      expect(find.byType(SuccessMark), findsNothing);

      await tester.runAsync(() async {
        await tester.tap(find.bySemanticsLabel('Sincronizar ahora'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(SuccessMark), findsOneWidget);
      expect(find.text('Todo al día'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));

      // «Dejar de sincronizar» está en Más opciones y se confirma en la hoja.
      expect(find.text('Dejar de sincronizar'), findsNothing);
      await tester.tap(find.text('Más opciones'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Cómo se protege la lista'), findsOneWidget);
      await tester.tap(find.text('Dejar de sincronizar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('¿Dejar de sincronizar?'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Dejar de sincronizar').last);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Sincronización apagada'), findsOneWidget);
      expect(find.text('Sincronización apagada.'), findsOneWidget);

      // El aviso se va solo (si siguiera, el siguiente lo retiraría desde
      // `runAsync` y su cierre quedaría para después de la prueba).
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 3));
      }
      expect(find.byType(SnackBar), findsNothing);

      // Sin interruptor, se vuelve a encender desde la tarjeta.
      await tester.runAsync(() async {
        await tester.tap(find.text('Encender'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Sincronización apagada'), findsNothing);
      expect(find.text('Todo al día'), findsOneWidget);
      // Deja irse los avisos antes de desmontar la app de la prueba.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 3));
      }
      expect(find.byType(SnackBar), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'Sincronización con un solo móvil: a la espera del segundo y sin peticiones',
      (tester) async {
        phoneSize(tester);
        final server = FakeSyncServer();
        late SyncPhone a;
        await tester.runAsync(() async {
          a = await SyncPhone.create(server);
          await a.createFamily();
        });
        addTearDown(a.dispose);
        await tester.pumpWidget(screenApp(a.c, const ShareScreen()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
        expect(find.text('Solo en este móvil'), findsOneWidget);
        expect(
          find.text('Empezará cuando emparejes otro móvil'),
          findsOneWidget,
        );
        expect(find.text('Todo al día'), findsNothing);
        expect(find.text('No se ha podido sincronizar'), findsNothing);
        // Solo está este móvil en la lista, y ni interruptor ni un «Sincronizar
        // ahora» que no haría nada.
        expect(find.text('Conectado a esta familia'), findsNothing);
        expect(find.byType(RegalosSwitch), findsNothing);
        expect(find.bySemanticsLabel('Sincronizar ahora'), findsNothing);
        expect(find.text('Conectar otro móvil'), findsOneWidget);

        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump();
        expect(
          find.text('Empezará cuando emparejes otro móvil'),
          findsOneWidget,
        );
        expect(server.calls, isEmpty);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'Móviles de la familia sin servidor: solo en este móvil y sin interruptor',
      (tester) async {
        phoneSize(tester);
        late FakePhone phone;
        await tester.runAsync(
          () async => phone = FakePhone(prefs: await mockPrefs()),
        );
        addTearDown(phone.dispose);
        await tester.pumpWidget(
          screenApp(phone.container, const ShareScreen()),
        );
        await tester.pump();
        expect(find.text('Solo en este móvil'), findsOneWidget);
        expect(find.byType(RegalosSwitch), findsNothing);
        expect(find.text('Sincronizar automáticamente'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'Unirme con un enlace: un texto que no es un enlace da un error claro',
      (tester) async {
        phoneSize(tester);
        final server = FakeSyncServer();
        late SyncPhone b;
        await tester.runAsync(() async => b = await SyncPhone.create(server));
        addTearDown(b.dispose);
        await tester.pumpWidget(screenApp(b.c, const JoinInviteScreen()));
        await tester.pump();
        await tester.enterText(find.byType(TextField).first, 'hola');
        await tester.runAsync(() async {
          await tester.tap(find.text('Pedir entrada'));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
        expect(
          find.text('Este texto no es un enlace de invitación de Gift Huddle.'),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}
