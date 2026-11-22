// Las pantallas de unirse con persona (1.0.6) en las cuatro variaciones que
// piden las normas de diseño: español e inglés, claro y oscuro, letra grande y
// «Reducir movimiento». Cada una se monta, se recorre y no desborda.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/model.dart' show Recipient;
import 'package:regalos/features/family/application/family_providers.dart'
    show
        GiftRecipientAccess,
        PersonProtectionStatus,
        giftRecipientAccessProvider;
import 'package:regalos/features/family/application/self_person_gate.dart';
import 'package:regalos/features/sync/application/pairing_v2_controller.dart';
import 'package:regalos/core/widgets/soft_note.dart' show SoftNote;
import 'package:regalos/features/sync/presentation/pairing_v2_guest_view.dart';
import 'package:regalos/features/sync/presentation/pairing_v2_host_view.dart';
import 'package:regalos/features/sync/presentation/who_are_you_step.dart';

import '../helpers/fake_self_gate.dart';
import '../helpers/fonts.dart';
import '../helpers/pump_app.dart';

import 'package:regalos/l10n/app_localizations.dart';

class _Host extends PairingV2HostController {
  _Host(this.initial);

  final PairingV2HostState initial;

  @override
  PairingV2HostState build() => initial;

  @override
  Future<void> choose() async {}

  @override
  Future<void> start({required String guestPerson}) async {}

  @override
  Future<void> startForNewPerson(String name, {bool noGifts = false}) async {}

  @override
  void dismiss() {}

  void set(PairingV2HostState next) => state = next;
}

class _Guest extends PairingV2GuestController {
  _Guest(this.initial);

  final PairingV2GuestState initial;

  @override
  PairingV2GuestState build() => initial;

  @override
  Future<void> begin(String inviteId, {String deviceName = ''}) async {}

  @override
  void reset() {}
}

/// Una variación de pantalla: idioma, brillo, letra y movimiento.
class _Variant {
  const _Variant(this.locale, this.brightness, this.textScale, this.reduce);

  final String locale;
  final Brightness brightness;
  final double textScale;
  final bool reduce;

  @override
  String toString() =>
      '$locale ${brightness.name} x$textScale${reduce ? ' sin movimiento' : ''}';
}

const _variants = [
  _Variant('es', Brightness.light, 1, false),
  _Variant('es', Brightness.dark, 1, false),
  _Variant('en', Brightness.light, 1, false),
  _Variant('en', Brightness.dark, 1, false),
  _Variant('es', Brightness.light, 2, false),
  _Variant('en', Brightness.dark, 2, false),
  _Variant('es', Brightness.light, 1, true),
  _Variant('en', Brightness.dark, 1, true),
];

Future<void> _pump(
  WidgetTester tester,
  _Variant v,
  Widget child, {
  List<Override> overrides = const [],
  bool settle = true,
}) async {
  await pumpThemed(
    tester,
    ProviderScope(
      overrides: [
        selfPersonGateActionsProvider.overrideWithValue(FakeGate()),
        selfPersonGateProvider.overrideWith(
          (ref) async => const SelfPersonGate(suggestedName: 'Aritz'),
        ),
        giftRecipientAccessProvider.overrideWith(
          (ref) async => [
            GiftRecipientAccess(
              recipient: const Recipient(
                id: 'nora',
                name: 'Nora',
                colorIndex: 0,
                archived: false,
              ),
              status: PersonProtectionStatus.unprotected,
              canSelect: true,
            ),
          ],
        ),
        ...overrides,
      ],
      child: SingleChildScrollView(child: child),
    ),
    locale: Locale(v.locale),
    brightness: v.brightness,
    textScale: v.textScale,
    disableAnimations: v.reduce,
    surfaceSize: const Size(390, 900),
  );
  await tester.pump();
  // Con un indicador de espera no hay nada que asentar: el tiempo corre solo.
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 600));
  }
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold)));

void main() {
  setUpAll(loadInter);

  for (final v in _variants) {
    group('$v', () {
      testWidgets('«Para quién es el móvil nuevo»: elegir, aviso y continuar', (
        tester,
      ) async {
        await _pump(
          tester,
          v,
          const PairingV2HostView(),
          overrides: [
            pairingV2HostProvider.overrideWith(
              () => _Host(
                const PairingV2HostState(
                  PairingV2HostPhase.choosePerson,
                  people: [
                    PairingV2Person('nora', 'Nora'),
                    PairingV2Person('leo', 'Leo'),
                  ],
                  selfPersonId: 'leo',
                ),
              ),
            ),
          ],
        );
        expect(find.text(_l10n(tester).inviteForTitle), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Nora'));
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.textContaining('Nora'), findsWidgets);
        // El aviso de que sus regalos pasan a estar en secreto es una nota suave,
        // no un aviso de error.
        expect(find.byType(SoftNote), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byKey(const ValueKey('notOnList')));
        await tester.tap(find.byKey(const ValueKey('notOnList')));
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('«¿Quién eres?» con las tres salidas', (tester) async {
        await _pump(
          tester,
          v,
          WhoAreYouStep(
            people: const [PairingV2Person('nora', 'Nora')],
            onAnswered: () {},
          ),
        );
        expect(find.text('Nora'), findsOneWidget);
        await tester.ensureVisible(find.byKey(const ValueKey('nobody')));
        await tester.tap(find.byKey(const ValueKey('nobody')));
        await tester.pump();
        await tester.pumpAndSettle();
        // Propone el nombre de la bienvenida.
        expect(find.widgetWithText(TextField, 'Aritz'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('comparar con la persona elegida y el fallo de protección', (
        tester,
      ) async {
        final host = _Host(
          const PairingV2HostState(
            PairingV2HostPhase.compare,
            code: '123456',
            hostPicked: true,
            guestPersonId: 'nora',
            guestPersonName: 'Nora',
          ),
        );
        await _pump(
          tester,
          v,
          const PairingV2HostView(),
          overrides: [pairingV2HostProvider.overrideWith(() => host)],
        );
        expect(
          find.text(_l10n(tester).pairingV2HostCompareFor('Nora')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        host.set(
          const PairingV2HostState(
            PairingV2HostPhase.failed,
            protectFailed: true,
            guestPersonName: 'Nora',
          ),
        );
        await tester.pump();
        await tester.pumpAndSettle();
        expect(
          find.text(_l10n(tester).pairingV2ProtectFailed('Nora')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('el móvil que entra espera con su persona asignada', (
        tester,
      ) async {
        await _pump(
          tester,
          v,
          PairingV2GuestView(
            inviteId: 'AAAAAAAAAAAAAAAAAAAAAA',
            onDone: () {},
            onExit: () {},
          ),
          settle: false,
          overrides: [
            pairingV2GuestProvider.overrideWith(
              () => _Guest(
                const PairingV2GuestState(
                  PairingV2GuestPhase.waitingCode,
                  hostAssigned: true,
                  assignedPersonId: 'nora',
                ),
              ),
            ),
          ],
        );
        expect(find.text(_l10n(tester).pairingV2GuestAssigned), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }
}
