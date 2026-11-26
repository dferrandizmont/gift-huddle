import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:regalos/core/motion/success_mark.dart';
import 'package:regalos/core/sync/model.dart' show Recipient;
import 'package:regalos/features/family/application/family_controller.dart'
    show familyControllerProvider;
import 'package:regalos/features/family/application/family_providers.dart'
    show
        GiftRecipientAccess,
        PersonProtectionStatus,
        giftRecipientAccessProvider;
import 'package:regalos/features/family/application/self_person_gate.dart';
import 'package:regalos/features/sync/application/pairing_v2_controller.dart';
import 'package:regalos/features/sync/presentation/code_card.dart';
import 'package:regalos/features/sync/presentation/join_invite_screen.dart'
    show joinedBody;
import 'package:regalos/features/sync/presentation/pairing_v2_guest_view.dart';
import 'package:regalos/l10n/app_localizations.dart';
import 'package:regalos/features/sync/presentation/pairing_v2_host_view.dart';

import '../helpers/fake_haptics.dart';
import '../web_device/presentation/mobile_web_support.dart' show FakeFamily;
import '../helpers/fake_self_gate.dart';
import '../helpers/pump_app.dart';

/// El anfitrión de mentira: fija el estado y apunta lo que se le pide.
class _FakeHost extends PairingV2HostController {
  _FakeHost(this.initial);

  final PairingV2HostState initial;
  final List<String> calls = [];

  @override
  PairingV2HostState build() => initial;

  @override
  Future<void> choose() async => calls.add('choose');

  @override
  Future<void> start({required String guestPerson}) async =>
      calls.add('start:$guestPerson');

  @override
  Future<void> startForNewPerson(String name, {bool noGifts = false}) async =>
      calls.add('new:$name:$noGifts');

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

/// El acceso de [id] a sus regalos: protegido o no, y si solo regala.
GiftRecipientAccess _access(
  String id, {
  bool protected = false,
  bool noGifts = false,
}) => GiftRecipientAccess(
  recipient: Recipient(
    id: id,
    name: id,
    colorIndex: 0,
    archived: false,
    noGifts: noGifts,
  ),
  status: protected
      ? PersonProtectionStatus.active
      : PersonProtectionStatus.unprotected,
  canSelect: true,
);

/// Deja correr lo que se despliega o se pliega (el primer cuadro solo arranca
/// la animación).
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
}

FilledButton _continue(WidgetTester tester) => tester.widget<FilledButton>(
  find.byKey(const ValueKey('personPickerContinue')),
);

Future<void> _pumpHost(
  WidgetTester tester,
  _FakeHost host, {
  bool far = false,
  FakeGate? gate,
  List<GiftRecipientAccess> access = const [],
}) async {
  await pumpThemed(
    tester,
    ProviderScope(
      overrides: [
        pairingV2HostProvider.overrideWith(() => host),
        selfPersonGateActionsProvider.overrideWithValue(gate ?? FakeGate()),
        giftRecipientAccessProvider.overrideWith((ref) async => access),
        selfPersonGateProvider.overrideWith(
          (ref) async => const SelfPersonGate(suggestedName: 'Aritz'),
        ),
      ],
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
    testWidgets('al montarse, si estaba en reposo, pide elegir la persona '
        '(1.0.6)', (tester) async {
      final host = _FakeHost(const PairingV2HostState(PairingV2HostPhase.idle));
      await _pumpHost(tester, host);
      expect(host.calls, contains('choose'));
      expect(host.calls.where((c) => c.startsWith('start')), isEmpty);
      expect(find.text('Preparando la conexión…'), findsOneWidget);
    });

    for (final far in [false, true]) {
      testWidgets('1.0.6: quien invita elige para quién es el móvil nuevo '
          '(${far ? 'enlace' : 'QR'}): tocar marca, el aviso se lee y '
          '«Continuar» empieza', (tester) async {
        final host = _FakeHost(
          const PairingV2HostState(
            PairingV2HostPhase.choosePerson,
            people: [
              PairingV2Person('nora', 'Nora'),
              PairingV2Person('leo', 'Leo'),
            ],
            selfPersonId: 'leo',
          ),
        );
        await _pumpHost(tester, host, far: far);
        expect(find.text('¿Para quién es el móvil nuevo?'), findsOneWidget);
        // Sin elegir nada, «Continuar» está apagado.
        expect(_continue(tester).onPressed, isNull);
        await tester.tap(find.text('Nora'));
        await _settle(tester);
        // Nada empieza al tocar: antes, el aviso.
        expect(host.calls.where((c) => c.startsWith('start')), isEmpty);
        expect(
          find.text(
            'Los regalos para Nora pasan a estar en secreto: dejarán de verse '
            'en su móvil.',
          ),
          findsOneWidget,
        );
        expect(find.byType(DrawnCheck), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('personPickerContinue')),
        );
        await tester.tap(find.byKey(const ValueKey('personPickerContinue')));
        await tester.pump();
        expect(host.calls, contains('start:nora'));
      });

      testWidgets('1.0.6: la persona de este móvil no recibe el aviso, ni '
          'quien ya tiene sus regalos en secreto o solo regala '
          '(${far ? 'enlace' : 'QR'})', (tester) async {
        final host = _FakeHost(
          const PairingV2HostState(
            PairingV2HostPhase.choosePerson,
            people: [
              PairingV2Person('nora', 'Nora'),
              PairingV2Person('leo', 'Leo'),
              PairingV2Person('aritz', 'Aritz'),
            ],
            selfPersonId: 'leo',
          ),
        );
        await _pumpHost(
          tester,
          host,
          far: far,
          access: [
            _access('nora', protected: true),
            _access('aritz', noGifts: true),
          ],
        );
        for (final name in ['Nora', 'Leo', 'Aritz']) {
          await tester.tap(find.text(name));
          await _settle(tester);
          expect(find.textContaining('pasan a estar en secreto'), findsNothing);
          expect(_continue(tester).onPressed, isNotNull, reason: name);
        }
      });

      testWidgets('1.0.6: «No está en la lista» y «Nadie» piden el nombre '
          '(${far ? 'enlace' : 'QR'}); el aviso solo sale con el primero', (
        tester,
      ) async {
        final host = _FakeHost(
          const PairingV2HostState(
            PairingV2HostPhase.choosePerson,
            people: [PairingV2Person('nora', 'Nora')],
            selfPersonId: 'leo',
          ),
        );
        await _pumpHost(tester, host, far: far);
        expect(find.byType(TextField), findsNothing);
        await tester.ensureVisible(find.text('No está en la lista'));
        await tester.tap(find.text('No está en la lista'));
        await _settle(tester);
        expect(find.byType(TextField), findsOneWidget);
        // Sin nombre no se sigue.
        expect(_continue(tester).onPressed, isNull);
        await tester.enterText(find.byType(TextField), 'Aritz');
        await tester.pump();
        expect(
          find.text(
            'Los regalos para Aritz pasan a estar en secreto: dejarán de '
            'verse en su móvil.',
          ),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('personPickerContinue')),
        );
        await tester.tap(find.byKey(const ValueKey('personPickerContinue')));
        await tester.pump();
        expect(host.calls, contains('new:Aritz:false'));

        await tester.ensureVisible(find.text('Nadie: solo regala'));
        await tester.tap(find.text('Nadie: solo regala'));
        await _settle(tester);
        expect(find.textContaining('pasan a estar en secreto'), findsNothing);
        expect(_continue(tester).onPressed, isNull);
        await tester.enterText(find.byType(TextField), 'Leo');
        await _settle(tester);
        await tester.ensureVisible(
          find.byKey(const ValueKey('personPickerContinue')),
        );
        await tester.tap(find.byKey(const ValueKey('personPickerContinue')));
        await tester.pump();
        expect(host.calls, contains('new:Leo:true'));
        expect(host.calls.where((c) => c == 'start:null'), isEmpty);
      });

      testWidgets('1.0.6: sin persona en este móvil, antes «¿Quién eres?» '
          '(${far ? 'enlace' : 'QR'}), con las tres salidas', (tester) async {
        final host = _FakeHost(
          const PairingV2HostState(
            PairingV2HostPhase.choosePerson,
            people: [PairingV2Person('nora', 'Nora')],
          ),
        );
        final gate = FakeGate();
        await _pumpHost(tester, host, far: far, gate: gate);
        await tester.pump();
        expect(find.text('¿Quién eres?'), findsOneWidget);
        await tester.tap(find.text('Nora'));
        await _settle(tester);
        expect(gate.calls, isEmpty, reason: 'tocar solo marca');
        await tester.tap(find.byKey(const ValueKey('personPickerContinue')));
        await tester.pump();
        expect(gate.calls, contains('choose:nora'));
        expect(host.calls, contains('choose'), reason: 'vuelve a la lista');
        // Propone el nombre de la bienvenida.
        await tester.ensureVisible(find.text('No estoy en la lista'));
        await tester.tap(find.text('No estoy en la lista'));
        await _settle(tester);
        expect(find.widgetWithText(TextField, 'Aritz'), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('personPickerContinue')),
        );
        await tester.tap(find.byKey(const ValueKey('personPickerContinue')));
        await tester.pump();
        expect(gate.calls, contains('notOnList:Aritz'));
        await tester.ensureVisible(find.text('Nadie'));
        await tester.tap(find.text('Nadie'));
        await _settle(tester);
        await tester.ensureVisible(
          find.byKey(const ValueKey('personPickerContinue')),
        );
        await tester.tap(find.byKey(const ValueKey('personPickerContinue')));
        await tester.pump();
        expect(gate.calls, contains('nobody:Aritz'));
        expect(host.calls.where((c) => c.startsWith('start')), isEmpty);
      });
    }

    testWidgets('1.0.6: con la persona elegida aquí, el código dice de quién '
        'es y se aprueba sin otro paso', (tester) async {
      final host = _FakeHost(
        const PairingV2HostState(
          PairingV2HostPhase.compare,
          code: '123456',
          hostPicked: true,
          guestPersonId: 'nora',
          guestPersonName: 'Nora',
        ),
      );
      await _pumpHost(tester, host);
      expect(find.text('Vas a conectar el móvil de Nora.'), findsOneWidget);
      expect(find.text('¿El otro móvil es de Nora?'), findsNothing);
      host.set(
        const PairingV2HostState(
          PairingV2HostPhase.approving,
          code: '123456',
          hostPicked: true,
          guestPersonId: 'nora',
          guestPersonName: 'Nora',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Vas a conectar el móvil de Nora.'), findsOneWidget);
      expect(find.text('¿El otro móvil es de Nora?'), findsNothing);
    });

    testWidgets('1.0.6: los fallos de persona y de protección tienen su '
        'texto', (tester) async {
      final host = _FakeHost(
        const PairingV2HostState(
          PairingV2HostPhase.failed,
          protectFailed: true,
          guestPersonName: 'Nora',
        ),
      );
      await _pumpHost(tester, host);
      expect(
        find.textContaining(
          'No se han podido poner en secreto los regalos '
          'para Nora',
        ),
        findsOneWidget,
      );
      host.set(
        const PairingV2HostState(
          PairingV2HostPhase.failed,
          needsSelfPerson: true,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.text(
          'Antes de conectar otro dispositivo, di de quién es este móvil.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('1.0.6: un invitado 1.0.5 dice que el otro móvil tiene que '
        'actualizar; un fallo al aprobar dice que ha quedado quitado', (
      tester,
    ) async {
      final host = _FakeHost(
        const PairingV2HostState(
          PairingV2HostPhase.failed,
          guestOutdated: true,
        ),
      );
      await _pumpHost(tester, host);
      expect(
        find.text('El otro móvil necesita actualizar Gift Huddle para unirse.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'No se ha podido conectar el otro móvil. Inténtalo de nuevo.',
        ),
        findsNothing,
      );
      host.set(
        const PairingV2HostState(
          PairingV2HostPhase.failed,
          approveFailed: true,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.textContaining('Ha quedado quitado'), findsOneWidget);
      expect(find.textContaining('volver a conectarse'), findsOneWidget);
      expect(find.textContaining('sigue ocultando'), findsOneWidget);
      host.set(
        const PairingV2HostState(
          PairingV2HostPhase.failed,
          protectFailed: true,
          approveFailed: true,
          guestPersonName: 'Nora',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.textContaining('Ese móvil ha quedado quitado'),
        findsOneWidget,
      );
      expect(find.textContaining('volver a conectarse'), findsOneWidget);
      expect(find.textContaining('sigue ocultando'), findsOneWidget);
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
      expect(host.calls.where((c) => c.startsWith('start')), isEmpty);
      expect(host.calls, isNot(contains('choose')));
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

      await tester.tap(find.text('Coinciden'));
      await tester.pump();
      expect(host.calls, contains('confirm'));
      await tester.tap(find.text('No coinciden'));
      await tester.pump();
      expect(host.calls, contains('cancel'));
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
      expect(find.text('¿El otro móvil es de Nora?'), findsOneWidget);
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
      expect(find.text('¿El otro móvil es de Nora?'), findsOneWidget);
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
      expect(
        find.textContaining('se ha cancelado y ya no sirve'),
        findsOneWidget,
      );
      await tester.tap(find.text('Volver a empezar'));
      await tester.pump();
      expect(host.calls, contains('choose'));
    });

    testWidgets('ronda 4: el anfitrión solo confirma que envió el acceso', (
      tester,
    ) async {
      final host = _FakeHost(const PairingV2HostState(PairingV2HostPhase.done));
      await _pumpHost(tester, host);
      expect(
        find.text(
          'Acceso enviado. El otro móvil tiene que completar la conexión.',
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
        find.text('No se ha podido completar la conexión. Inténtalo de nuevo.'),
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
        find.text('No se ha podido completar la conexión. Inténtalo de nuevo.'),
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

    testWidgets('1.0.6: el móvil que entra no elige persona: si el flujo '
        'llegara a ese paso, solo espera', (tester) async {
      final guest = _FakeGuest(
        const PairingV2GuestState(
          PairingV2GuestPhase.choosePerson,
          people: [PairingV2Person('n', 'Nora')],
        ),
      );
      await _pumpGuest(tester, guest);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Nora'), findsNothing);
      expect(find.text('Elegir después'), findsNothing);
      expect(find.text('¿De quién es este móvil?'), findsNothing);
    });

    testWidgets('1.0.6: con persona asignada por quien invita, la espera lo '
        'dice en una nota aparte', (tester) async {
      final guest = _FakeGuest(
        const PairingV2GuestState(
          PairingV2GuestPhase.waitingCode,
          hostAssigned: true,
          assignedPersonId: 'n',
        ),
      );
      await _pumpGuest(tester, guest);
      expect(
        find.text(
          'Quien te invita ha elegido de quién es este móvil. Lo verás al '
          'entrar.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Cuando el otro móvil responda, verás aquí un código para comparar.',
        ),
        findsOneWidget,
      );
      expect(find.text('Cancelar'), findsOneWidget);
    });

    testWidgets('1.0.6: la hoja final dice de quién es el móvil y que no verá '
        'sus regalos; sin la lista, la frase de siempre', (tester) async {
      await pumpThemed(
        tester,
        ProviderScope(
          overrides: [
            pairingV2GuestProvider.overrideWith(
              () => _FakeGuest(
                const PairingV2GuestState(
                  PairingV2GuestPhase.done,
                  hostAssigned: true,
                  assignedPersonId: 'nora',
                ),
              ),
            ),
            familyControllerProvider.overrideWith(
              () => FakeFamily(null, 'nora'),
            ),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              // Solo para repintar cuando carga la familia.
              ref.watch(familyControllerProvider);
              return Text(
                joinedBody(ref, AppLocalizations.of(context)),
                key: const ValueKey('body'),
              );
            },
          ),
        ),
      );
      // Mientras la familia carga, la frase de siempre.
      expect(
        find.text('Ya estás en la familia. La lista llegará en unos segundos.'),
        findsOneWidget,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text(
          'Ya estás en la familia. Este móvil es de Nora: aquí no verás los '
          'regalos para Nora.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('sin persona asignada, la espera no lleva la nota', (
      tester,
    ) async {
      final guest = _FakeGuest(
        const PairingV2GuestState(PairingV2GuestPhase.waitingCode),
      );
      await _pumpGuest(tester, guest);
      expect(find.textContaining('ha elegido de quién es'), findsNothing);
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
