import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:regalos/core/motion/success_mark.dart';
import 'package:regalos/features/sync/application/pairing_v2_controller.dart';
import 'package:regalos/features/sync/presentation/code_card.dart';
import 'package:regalos/features/sync/presentation/pairing_v2_guest_view.dart';
import 'package:regalos/features/sync/presentation/pairing_v2_host_view.dart';

import '../helpers/fake_haptics.dart';
import '../helpers/pump_app.dart';

/// El anfitrión de mentira: fija el estado y apunta lo que se le pide.
class _FakeHost extends PairingV2HostController {
  _FakeHost(this.initial);

  final PairingV2HostState initial;
  final List<String> calls = [];

  @override
  PairingV2HostState build() => initial;

  @override
  Future<void> start() async => calls.add('start');

  @override
  Future<void> confirm() async => calls.add('confirm');

  @override
  Future<void> confirmPerson() async => calls.add('confirmPerson');

  @override
  Future<void> confirmMigration() async => calls.add('confirmMigration');

  @override
  Future<void> cancel() async => calls.add('cancel');

  @override
  void dismiss() => calls.add('dismiss');

  /// Cambia el estado como lo haría el controlador de verdad.
  void set(PairingV2HostState next) => state = next;
}

/// El invitado de mentira.
class _FakeGuest extends PairingV2GuestController {
  _FakeGuest(this.initial);

  final PairingV2GuestState initial;
  final List<String> calls = [];

  @override
  PairingV2GuestState build() => initial;

  /// Cambia el estado como lo haría el controlador de verdad.
  void set(PairingV2GuestState next) => state = next;

  @override
  Future<void> begin(String inviteId, {String deviceName = ''}) async =>
      calls.add('begin:$inviteId');

  @override
  Future<void> confirmReplace() async => calls.add('confirmReplace');

  @override
  Future<void> choosePerson(String? personId) async =>
      calls.add('choose:$personId');

  @override
  void confirmCode() => calls.add('confirmCode');

  @override
  void cancel() => calls.add('cancel');

  @override
  void reset() => calls.add('reset');
}

const String _link = 'https://gifthuddle.app/i#AAAAAAAAAAAAAAAAAAAAAA';

Future<void> _pumpHost(
  WidgetTester tester,
  _FakeHost host, {
  bool far = false,
}) async {
  await pumpThemed(
    tester,
    ProviderScope(
      overrides: [pairingV2HostProvider.overrideWith(() => host)],
      child: SingleChildScrollView(child: PairingV2HostView(far: far)),
    ),
    surfaceSize: const Size(390, 900),
  );
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _pumpGuest(
  WidgetTester tester,
  _FakeGuest guest, {
  VoidCallback? onDone,
  VoidCallback? onExit,
}) async {
  await pumpThemed(
    tester,
    ProviderScope(
      overrides: [pairingV2GuestProvider.overrideWith(() => guest)],
      child: SingleChildScrollView(
        child: PairingV2GuestView(
          inviteId: 'AAAAAAAAAAAAAAAAAAAAAA',
          onDone: onDone ?? () {},
          onExit: onExit ?? () {},
        ),
      ),
    ),
    surfaceSize: const Size(390, 900),
  );
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  group('anfitrión', () {
    testWidgets('al montarse empieza si estaba en reposo', (tester) async {
      final host = _FakeHost(const PairingV2HostState(PairingV2HostPhase.idle));
      await _pumpHost(tester, host);
      expect(host.calls, contains('start'));
      expect(find.text('Preparando la conexión…'), findsOneWidget);
    });

    testWidgets('esperando enseña el QR del enlace y el aviso de caducidad', (
      tester,
    ) async {
      final host = _FakeHost(
        const PairingV2HostState(PairingV2HostPhase.waiting, link: _link),
      );
      await _pumpHost(tester, host);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.textContaining('caduca a las 24 horas'), findsOneWidget);
      expect(host.calls, isNot(contains('start')));
    });

    testWidgets('«está lejos» enseña el enlace y un botón para compartirlo', (
      tester,
    ) async {
      final host = _FakeHost(
        const PairingV2HostState(PairingV2HostPhase.waiting, link: _link),
      );
      await _pumpHost(tester, host, far: true);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text(_link), findsOneWidget);
      expect(find.text('Compartir el enlace'), findsOneWidget);
      await tester.tap(find.text('Cancelar invitación'));
      await tester.pump();
      expect(host.calls, contains('cancel'));
    });

    testWidgets('comparar enseña el código y los dos botones llaman al '
        'controlador', (tester) async {
      final host = _FakeHost(
        const PairingV2HostState(
          PairingV2HostPhase.compare,
          link: _link,
          code: '030367',
        ),
      );
      await _pumpHost(tester, host);
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('030 367'), findsOneWidget);
      expect(find.text('Coinciden'), findsOneWidget);
      expect(find.text('No coinciden'), findsOneWidget);
      // Sin aviso si el otro móvil ya eligió persona.
      expect(
        find.textContaining('todavía no ha dicho de quién es'),
        findsNothing,
      );

      await tester.tap(find.text('Coinciden'));
      await tester.pump();
      expect(host.calls, contains('confirm'));
      await tester.tap(find.text('No coinciden'));
      await tester.pump();
      expect(host.calls, contains('cancel'));
    });

    testWidgets('si el otro móvil no ha elegido persona lo avisa y deja '
        '«Coinciden»', (tester) async {
      final host = _FakeHost(
        const PairingV2HostState(
          PairingV2HostPhase.compare,
          code: '030367',
          guestWithoutPerson: true,
        ),
      );
      await _pumpHost(tester, host);
      expect(
        find.textContaining('todavía no ha dicho de quién es'),
        findsOneWidget,
      );
      expect(find.text('Coinciden'), findsOneWidget);
    });

    testWidgets('hallazgo 3: si el otro móvil dice ser de alguien, se '
        'confirma aparte con su nombre; «No es suyo» cancela', (tester) async {
      final host = _FakeHost(
        const PairingV2HostState(
          PairingV2HostPhase.confirmPerson,
          code: '123456',
          guestPersonId: 'nora',
          guestPersonName: 'Nora',
        ),
      );
      await _pumpHost(tester, host);
      expect(find.text('Este móvil dice ser de Nora'), findsOneWidget);
      expect(find.text('Coinciden'), findsNothing);
      await tester.tap(find.text('Sí, es de Nora'));
      await tester.pump();
      expect(host.calls, contains('confirmPerson'));
      await tester.tap(find.text('No es suyo'));
      await tester.pump();
      expect(host.calls, contains('cancel'));
      // Mientras aprueba, el mismo paso sin botones.
      host.set(
        const PairingV2HostState(
          PairingV2HostPhase.approving,
          guestPersonId: 'nora',
          guestPersonName: 'Nora',
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Este móvil dice ser de Nora'), findsOneWidget);
      expect(find.text('Sí, es de Nora'), findsNothing);
    });

    testWidgets('hallazgo 8: pasar a la sincronización nueva se confirma en '
        'un diálogo antes de tocar nada', (tester) async {
      final host = _FakeHost(const PairingV2HostState(PairingV2HostPhase.idle));
      await _pumpHost(tester, host);
      host.set(const PairingV2HostState(PairingV2HostPhase.confirmMigration));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('¿Pasar a la sincronización nueva?'), findsOneWidget);
      expect(host.calls, isNot(contains('confirmMigration')));
      await tester.tap(find.text('Continuar'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(host.calls, contains('confirmMigration'));
      // Cancelar no migra y cierra.
      host.set(const PairingV2HostState(PairingV2HostPhase.idle));
      await tester.pump();
      host.set(const PairingV2HostState(PairingV2HostPhase.confirmMigration));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('Cancelar'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(host.calls.where((c) => c == 'confirmMigration'), hasLength(1));
      expect(host.calls, contains('dismiss'));
    });

    testWidgets('fallo y cancelación ofrecen volver a empezar', (tester) async {
      final host = _FakeHost(
        const PairingV2HostState(PairingV2HostPhase.cancelled),
      );
      await _pumpHost(tester, host);
      expect(find.textContaining('el código ya no sirve'), findsOneWidget);
      await tester.tap(find.text('Volver a empezar'));
      await tester.pump();
      expect(host.calls, contains('start'));
    });

    testWidgets('ronda 4: el anfitrión solo confirma que envió el acceso', (
      tester,
    ) async {
      final host = _FakeHost(const PairingV2HostState(PairingV2HostPhase.done));
      await _pumpHost(tester, host);
      expect(
        find.text(
          'Acceso enviado. El otro móvil tiene que terminar la conexión.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('al terminar sale el sello de éxito y no queda nada '
        'pendiente', (tester) async {
      final host = _FakeHost(const PairingV2HostState(PairingV2HostPhase.done));
      await _pumpHost(tester, host);
      expect(find.byType(SuccessMark), findsOneWidget);
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets(
      'al terminar vibra con éxito, una vez y con el sello (250 ms)',
      (tester) async {
        final fake = FakeHaptics();
        final host = _FakeHost(
          const PairingV2HostState(PairingV2HostPhase.done),
        );
        await pumpThemed(
          tester,
          ProviderScope(
            overrides: [
              pairingV2HostProvider.overrideWith(() => host),
              fake.provide,
            ],
            child: const SingleChildScrollView(child: PairingV2HostView()),
          ),
          surfaceSize: const Size(390, 900),
        );
        await tester.pump(const Duration(milliseconds: 600));
        expect(fake.log, ['success+250']);
      },
    );

    testWidgets('al aprobar, la tarjeta del código se marca como confirmada', (
      tester,
    ) async {
      final host = _FakeHost(
        const PairingV2HostState(PairingV2HostPhase.approving, code: '123456'),
      );
      await _pumpHost(tester, host);
      expect(
        tester
            .widget<VerificationCodeCard>(find.byType(VerificationCodeCard))
            .confirmed,
        isTrue,
      );
    });
  });

  group('invitado', () {
    testWidgets('una recuperación a medias se dice, no se queda en reposo', (
      tester,
    ) async {
      final guest = _FakeGuest(
        const PairingV2GuestState(
          PairingV2GuestPhase.failed,
          failureCode: 'restore_pending',
        ),
      );
      await _pumpGuest(tester, guest);
      expect(
        find.textContaining('Hay una recuperación a medias'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Reanúdala o cancélala antes de crear una familia'),
        findsOneWidget,
      );
      expect(
        find.text('No se ha podido completar. Inténtalo de nuevo.'),
        findsNothing,
      );
    });

    testWidgets('ronda 4: incompatibilidad pide actualizar los dos móviles', (
      tester,
    ) async {
      final guest = _FakeGuest(
        const PairingV2GuestState(
          PairingV2GuestPhase.failed,
          versionMismatch: true,
        ),
      );
      await _pumpGuest(tester, guest);
      expect(
        find.text(
          'Los dos móviles tienen que tener la última versión de Gift Huddle. '
          'Actualiza el que esté desfasado y vuelve a empezar.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('No se ha podido completar. Inténtalo de nuevo.'),
        findsNothing,
      );
    });

    testWidgets('abre la invitación al montarse', (tester) async {
      final guest = _FakeGuest(
        const PairingV2GuestState(PairingV2GuestPhase.idle),
      );
      await _pumpGuest(tester, guest);
      expect(guest.calls, contains('begin:AAAAAAAAAAAAAAAAAAAAAA'));
    });

    testWidgets('elegir persona: las de la lista y «Elegir después» con su '
        'aviso', (tester) async {
      final guest = _FakeGuest(
        const PairingV2GuestState(
          PairingV2GuestPhase.choosePerson,
          people: [PairingV2Person('a', 'Aritz'), PairingV2Person('n', 'Nora')],
        ),
      );
      await _pumpGuest(tester, guest);
      expect(find.text('¿De quién es este móvil?'), findsOneWidget);
      expect(
        find.textContaining('no abrirá las sorpresas hasta que elijas'),
        findsOneWidget,
      );
      await tester.tap(find.text('Nora'));
      await tester.pump();
      expect(guest.calls, contains('choose:n'));
      await tester.tap(find.text('Elegir después'));
      await tester.pump();
      expect(guest.calls, contains('choose:null'));
    });

    testWidgets('con persona premarcada sale primera y «Continuar» envía su '
        'id', (tester) async {
      final guest = _FakeGuest(
        const PairingV2GuestState(
          PairingV2GuestPhase.choosePerson,
          people: [
            PairingV2Person('a', 'Aritz'),
            PairingV2Person('n', 'Nora'),
            PairingV2Person('l', 'Leo'),
          ],
          selfId: 'n',
        ),
      );
      await _pumpGuest(tester, guest);
      expect(
        find.text(
          'Lo tenías marcado como de Nora. Confírmalo o elige a otra '
          'persona.',
        ),
        findsOneWidget,
      );
      // Nora va la primera de la lista y se ve marcada (visto dibujado).
      expect(
        tester.getTopLeft(find.text('Nora')).dy,
        lessThan(tester.getTopLeft(find.text('Aritz')).dy),
      );
      expect(find.byType(DrawnCheck), findsOneWidget);
      expect(find.text('Aritz'), findsOneWidget);
      expect(find.text('Leo'), findsOneWidget);
      await tester.tap(find.text('Continuar'));
      await tester.pump();
      expect(guest.calls.last, 'choose:n');
      // Las demás y «Elegir después» siguen disponibles.
      await tester.tap(find.text('Leo'));
      await tester.pump();
      expect(guest.calls, contains('choose:l'));
      await tester.tap(find.text('Elegir después'));
      await tester.pump();
      expect(guest.calls, contains('choose:null'));
    });

    testWidgets(
      'sin «Este móvil es de» no hay nada premarcado ni «Continuar»',
      (tester) async {
        final guest = _FakeGuest(
          const PairingV2GuestState(
            PairingV2GuestPhase.choosePerson,
            people: [
              PairingV2Person('a', 'Aritz'),
              PairingV2Person('n', 'Nora'),
            ],
          ),
        );
        await _pumpGuest(tester, guest);
        expect(find.byType(DrawnCheck), findsNothing);
        expect(find.text('Continuar'), findsNothing);
        expect(find.textContaining('El que tienes en la mano'), findsOneWidget);
      },
    );

    testWidgets('un «Este móvil es de» que no está en la familia nueva se '
        'ignora', (tester) async {
      final guest = _FakeGuest(
        const PairingV2GuestState(
          PairingV2GuestPhase.choosePerson,
          people: [PairingV2Person('a', 'Aritz'), PairingV2Person('n', 'Nora')],
          selfId: 'otra',
        ),
      );
      await _pumpGuest(tester, guest);
      expect(find.byType(DrawnCheck), findsNothing);
      expect(find.text('Continuar'), findsNothing);
      expect(find.textContaining('Lo tenías marcado'), findsNothing);
      expect(find.text('Aritz'), findsOneWidget);
    });

    testWidgets('sin personas conocidas solo se puede «Elegir después»', (
      tester,
    ) async {
      final guest = _FakeGuest(
        const PairingV2GuestState(PairingV2GuestPhase.choosePerson),
      );
      await _pumpGuest(tester, guest);
      expect(find.textContaining('no conoce a nadie'), findsOneWidget);
      expect(find.text('Elegir después'), findsOneWidget);
    });

    testWidgets('comparar enseña el código y los dos botones', (tester) async {
      final guest = _FakeGuest(
        const PairingV2GuestState(PairingV2GuestPhase.compare, code: '123456'),
      );
      await _pumpGuest(tester, guest);
      // Las cifras ruedan al aparecer.
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('123 456'), findsOneWidget);
      await tester.tap(find.text('Coinciden'));
      await tester.pump();
      expect(guest.calls, contains('confirmCode'));
      await tester.tap(find.text('No coinciden'));
      await tester.pump();
      expect(guest.calls, contains('cancel'));
    });

    testWidgets('al entrar avisa una sola vez', (tester) async {
      var done = 0;
      final guest = _FakeGuest(
        const PairingV2GuestState(
          PairingV2GuestPhase.waitingApproval,
          code: '123456',
        ),
      );
      await _pumpGuest(tester, guest, onDone: () => done++);
      expect(
        find.text('Esperando a que el otro móvil dé acceso…'),
        findsOneWidget,
      );
      guest.set(const PairingV2GuestState(PairingV2GuestPhase.done));
      await tester.pump(const Duration(milliseconds: 600));
      expect(done, 1);
    });

    testWidgets('invitación caducada: mensaje y salir', (tester) async {
      var exited = 0;
      final guest = _FakeGuest(
        const PairingV2GuestState(PairingV2GuestPhase.gone),
      );
      await _pumpGuest(tester, guest, onExit: () => exited++);
      expect(
        find.text('La invitación ha caducado o no se ha aceptado.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Volver a empezar'));
      expect(exited, 1);
    });
  });
}
