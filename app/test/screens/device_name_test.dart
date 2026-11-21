import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/device/device_name.dart';
import 'package:regalos/features/sync/application/pairing_v2_controller.dart';
import 'package:regalos/features/sync/data/sync_config.dart';
import 'package:regalos/features/sync/presentation/join_invite_screen.dart';

import '../helpers/pump_app.dart';
import '../helpers/screens.dart';

class _NameGuest extends PairingV2GuestController {
  String? receivedName;

  @override
  PairingV2GuestState build() =>
      const PairingV2GuestState(PairingV2GuestPhase.idle);

  @override
  Future<void> begin(String inviteId, {String deviceName = ''}) async {
    receivedName = deviceName;
    state = const PairingV2GuestState(PairingV2GuestPhase.choosePerson);
  }

  @override
  void reset() {}
}

void main() {
  const channel = MethodChannel('com.dferrandizmont.regalos/incoming');
  const invite = 'https://gifthuddle.app/i#AAAAAAAAAAAAAAAAAAAAAA';

  for (final qr in [false, true]) {
    for (final typed in [null, 'Móvil de Nora', '']) {
      if (qr && typed == '') continue;
      final guest = _NameGuest();
      screenTest(
        'la bienvenida conserva el nombre al unirse '
        '(QR=$qr, nombre=$typed)',
        (tester, phone) async {
          await pumpRegalos(tester, phone);
          final field = find.widgetWithText(TextField, 'Nombre de este móvil');
          if (typed != null) await tester.enterText(field, typed);
          await tapWelcomeChoice(
            tester,
            qr ? 'Escanear el QR' : 'Unirme con un enlace',
          );
          if (qr) {
            final scanner = find.text('Leer invitación');
            await tester.ensureVisible(scanner);
            await tester.tap(scanner);
          } else {
            await tester.enterText(find.byType(TextField).first, invite);
            await tester.tap(find.text('Pedir entrada'));
          }
          await settle(tester);
          // Un nombre vacío en la bienvenida no se queda vacío al pegar el
          // enlace: el campo propone el modelo, visible y editable.
          final shared = typed == null || typed.isEmpty
              ? 'Pixel de Nora'
              : typed;
          expect(guest.receivedName, qr ? (typed ?? 'Pixel de Nora') : shared);
          await tester.pumpWidget(const SizedBox());
        },
        overrides: [
          suggestedDeviceNameProvider.overrideWith(
            (ref) async => 'Pixel de Nora',
          ),
          pairingV2AvailableProvider.overrideWithValue(true),
          pairingV2GuestProvider.overrideWith(() => guest),
        ],
        scanner: (context, onCode) => TextButton(
          onPressed: () => onCode(invite),
          child: const Text('Leer invitación'),
        ),
      );
    }
  }

  for (final edit in [null, 'Móvil de Nora']) {
    testWidgets(
      'un enlace que llega solo pide el nombre antes de abrir la invitación '
      '(editado: $edit)',
      (tester) async {
        final guest = _NameGuest();
        await pumpThemed(
          tester,
          ProviderScope(
            overrides: [
              syncHostProvider.overrideWithValue(''),
              suggestedDeviceNameProvider.overrideWith(
                (ref) async => 'Pixel de Nora',
              ),
              pairingV2AvailableProvider.overrideWithValue(true),
              pairingV2GuestProvider.overrideWith(() => guest),
            ],
            child: const JoinInviteScreen(initialInvite: invite),
          ),
        );
        await tester.pump();
        await tester.pump();
        // No se abre sola ni comparte el modelo sin que se vea.
        expect(guest.receivedName, isNull);
        final field = find.widgetWithText(TextField, 'Nombre de este móvil');
        expect(field, findsOneWidget);
        expect(find.text('Pixel de Nora'), findsOneWidget);
        if (edit != null) await tester.enterText(field, edit);
        await tester.tap(find.text('Pedir entrada'));
        await tester.pump();
        expect(guest.receivedName, edit ?? 'Pixel de Nora');
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'el nombre se toma al pulsar «Pedir entrada»: el vacío también vale aunque '
    'la sugerencia llegue después',
    (tester) async {
      final guest = _NameGuest();
      final suggestion = Completer<String>();
      await pumpThemed(
        tester,
        ProviderScope(
          overrides: [
            syncHostProvider.overrideWithValue(''),
            suggestedDeviceNameProvider.overrideWith(
              (ref) => suggestion.future,
            ),
            pairingV2AvailableProvider.overrideWithValue(true),
            pairingV2GuestProvider.overrideWith(() => guest),
          ],
          child: const JoinInviteScreen(initialInvite: invite),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Pedir entrada'));
      suggestion.complete('Pixel de Nora');
      await tester.pump();
      await tester.pump();
      expect(guest.receivedName, '');
      await tester.pumpWidget(const SizedBox());
    },
  );

  Future<void> pumpField(
    WidgetTester tester,
    TextEditingController controller, {
    String initial = '',
    String model = 'OnePlus NE2213',
    ValueChanged<String>? onConfirm,
  }) async {
    await pumpThemed(
      tester,
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          suggestedDeviceNameProvider.overrideWith((ref) async => model),
        ],
        child: Consumer(
          builder: (context, ref, _) => Material(
            child: Column(
              children: [
                DeviceNameField(controller: controller, initial: initial),
                TextButton(
                  onPressed: () =>
                      onConfirm?.call(deviceNameToSend(ref, controller.text)),
                  child: const Text('Confirmar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('nombre del móvil', () {
    testWidgets(
      'solo se envía el texto confirmado; vacío no recupera el modelo',
      (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        String? sent;
        await pumpField(tester, controller, onConfirm: (name) => sent = name);
        await tester.tap(find.text('Confirmar'));
        expect(sent, 'OnePlus NE2213');
        await tester.enterText(find.byType(TextField), 'Móvil de Nora');
        await tester.tap(find.text('Confirmar'));
        expect(sent, 'Móvil de Nora');
        await tester.enterText(find.byType(TextField), '');
        await tester.tap(find.text('Confirmar'));
        expect(sent, isEmpty);
      },
    );

    testWidgets('se propone el modelo y se puede cambiar', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpField(tester, controller);
      expect(controller.text, 'OnePlus NE2213');
      await tester.enterText(find.byType(TextField), 'Móvil de Ana');
      expect(controller.text, 'Móvil de Ana');
    });

    testWidgets('lo que ya escribió la persona no se pisa', (tester) async {
      final controller = TextEditingController(text: 'Pixel de Eva');
      addTearDown(controller.dispose);
      await pumpField(tester, controller);
      expect(controller.text, 'Pixel de Eva');
    });

    testWidgets('un nombre guardado se conserva, pero «Mi móvil» de versiones '
        'anteriores se sustituye por el modelo', (tester) async {
      final kept = TextEditingController();
      addTearDown(kept.dispose);
      await pumpField(tester, kept, initial: 'Pixel de Eva');
      expect(kept.text, 'Pixel de Eva');

      for (final legacy in kLegacyDeviceNames) {
        final replaced = TextEditingController();
        addTearDown(replaced.dispose);
        await pumpField(tester, replaced, initial: legacy);
        expect(replaced.text, 'OnePlus NE2213', reason: legacy);
      }
    });

    testWidgets('el nombre admite como mucho $kDeviceNameMaxChars caracteres', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpField(tester, controller, model: '');
      await tester.enterText(find.byType(TextField), 'x' * 60);
      expect(controller.text.length, kDeviceNameMaxChars);
    });

    test('isLegacyDeviceName reconoce los tres nombres por defecto', () {
      expect(isLegacyDeviceName('Mi móvil'), isTrue);
      expect(isLegacyDeviceName('My phone'), isTrue);
      expect(isLegacyDeviceName(' El meu mòbil '), isTrue);
      expect(isLegacyDeviceName('Móvil de Ana'), isFalse);
    });

    test(
      'readDeviceModel lee el modelo del código nativo y aguanta que falte',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'deviceModel');
          return '  OnePlus NE2213 ';
        });
        expect(await readDeviceModel(), 'OnePlus NE2213');
        messenger.setMockMethodCallHandler(channel, null);
        // Sin código nativo (pruebas, escritorio): vacío, sin lanzar.
        expect(await readDeviceModel(), '');
      },
    );
  });

  screenTest('la bienvenida propone el nombre del móvil y manda el que se '
      'escribe, no un texto traducido', (tester, phone) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'deviceModel' ? 'Pixel 8' : null,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await pumpRegalos(tester, phone);
    await tester.pump();
    await tester.pump();
    final field = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Nombre de este móvil'),
    );
    expect(field.controller!.text, 'Pixel 8');
  });
}
