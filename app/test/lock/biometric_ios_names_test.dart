import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/lock/application/lock_controller.dart';
import 'package:regalos/features/lock/data/biometrics.dart';
import 'package:regalos/features/lock/presentation/pin_pad.dart';
import 'package:regalos/l10n/app_localizations.dart';

import '../helpers/memory_stores.dart';
import '../helpers/screens.dart'
    as screens
    show screenTest, seedSample, pumpRegalos, tapText, settle;
import '../screens/settings_test.dart' show openSettings;
import 'lock_gate_test.dart' show pumpGate, settle, typePin;

// En iOS los textos de la biometría nombran lo que tiene el dispositivo (Face
// ID o Touch ID); en Android, o si no se sabe, siguen diciendo «huella o
// rostro». El tipo se inyecta con `FakeBiometrics.kindOverride`.

class _Auth extends LocalAuthentication {
  _Auth(this.types);

  final List<BiometricType> types;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => types;
}

void main() {
  late FakePhone phone;
  setUp(() => phone = FakePhone());
  tearDown(() => phone.dispose());

  Future<void> createPinUntilOffer(WidgetTester tester) async {
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
  }

  group('oferta tras crear el PIN', () {
    testWidgets('Face ID', (tester) async {
      phone.biometrics.kindOverride = BiometricKind.face;
      await createPinUntilOffer(tester);
      expect(find.text('¿Activar Face ID?'), findsOneWidget);
      expect(
        find.text('Cualquier persona que tenga la cara registrada en Face ID podrá abrir la app.'),
        findsOneWidget,
      );
      expect(find.text('¿Activar huella o rostro?'), findsNothing);
    });

    testWidgets('Touch ID', (tester) async {
      phone.biometrics.kindOverride = BiometricKind.fingerprint;
      await createPinUntilOffer(tester);
      expect(find.text('¿Activar Touch ID?'), findsOneWidget);
      expect(
        find.text(
          'Cualquier persona que tenga una huella registrada en Touch ID podrá abrir la app.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('sin saber el tipo, el texto genérico de siempre', (
      tester,
    ) async {
      await createPinUntilOffer(tester);
      expect(find.text('¿Activar huella o rostro?'), findsOneWidget);
      expect(find.textContaining('Face ID'), findsNothing);
      expect(find.textContaining('Touch ID'), findsNothing);
    });
  });

  group('pantalla de bloqueo', () {
    Future<void> lockedWithBiometrics(WidgetTester tester) async {
      await tester.runAsync(() async {
        await phone.container
            .read(familyControllerProvider.notifier)
            .createFamily(deviceName: 'A');
        final lock = phone.container.read(lockControllerProvider.notifier);
        await lock.setPin('4821');
        await lock.setBiometrics(true, reason: 'x');
      });
      phone.restart();
      // La huella automática falla: queda el teclado con su botón.
      phone.biometrics.succeeds = false;
      await pumpGate(tester, phone);
      await settle(tester);
      await settle(tester);
    }

    testWidgets('Face ID: botón y pista propios', (tester) async {
      final semantics = tester.ensureSemantics();
      phone.biometrics.kindOverride = BiometricKind.face;
      await lockedWithBiometrics(tester);
      expect(find.bySemanticsLabel('Usar Face ID'), findsOneWidget);
      expect(find.text('Toca el botón de Face ID para desbloquear la app'), findsOneWidget);
      expect(find.bySemanticsLabel('Usar huella o rostro'), findsNothing);
      expect(find.byType(PinPad), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('Touch ID', (tester) async {
      final semantics = tester.ensureSemantics();
      phone.biometrics.kindOverride = BiometricKind.fingerprint;
      await lockedWithBiometrics(tester);
      expect(find.bySemanticsLabel('Usar Touch ID'), findsOneWidget);
      expect(find.text('Toca el botón de Touch ID para desbloquear la app'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('genérico en Android o sin saberlo', (tester) async {
      final semantics = tester.ensureSemantics();
      await lockedWithBiometrics(tester);
      expect(find.bySemanticsLabel('Usar huella o rostro'), findsOneWidget);
      expect(find.text('Toca el botón de la huella para desbloquear'), findsOneWidget);
      semantics.dispose();
    });
  });

  group('Ajustes › Bloqueo', () {
    screens.screenTest(
      'Face ID nombra el interruptor y no dice «huella o rostro»',
      (tester, phone) async {
        phone.biometrics.kindOverride = BiometricKind.face;
        await screens.seedSample(tester, phone, pin: true);
        await screens.pumpRegalos(tester, phone);
        await openSettings(tester);
        await screens.tapText(tester, 'Bloqueo');
        expect(find.bySemanticsLabel('Face ID'), findsOneWidget);
        expect(find.bySemanticsLabel('Huella o rostro'), findsNothing);
      },
      size: const Size(390, 1500),
    );

    screens.screenTest('Touch ID', (tester, phone) async {
      phone.biometrics.kindOverride = BiometricKind.fingerprint;
      await screens.seedSample(tester, phone, pin: true);
      await screens.pumpRegalos(tester, phone);
      await openSettings(tester);
      await screens.tapText(tester, 'Bloqueo');
      expect(find.bySemanticsLabel('Touch ID'), findsOneWidget);
    }, size: const Size(390, 1500));
  });

  test('los textos de iOS existen en los tres idiomas', () async {
    for (final code in ['es', 'ca', 'en']) {
      final l10n = await AppLocalizations.delegate.load(Locale(code));
      expect(l10n.lockBiometricNamed('Face ID'), contains('Face ID'));
      expect(l10n.lockBiometricHintNamed('Touch ID'), contains('Touch ID'));
      expect(l10n.pinBiometricOfferTitleNamed('Face ID'), contains('Face ID'));
      expect(
        l10n.securityBiometricsFailedNamed('Face ID'),
        contains('Face ID'),
      );
      expect(l10n.lockBiometricNoticeFace, contains('Face ID'));
      expect(l10n.lockBiometricNoticeTouch, contains('Touch ID'));
      expect(l10n.securityBiometricsUnavailableIos, contains('Touch ID'));
    }
  });

  group('LocalAuthBiometrics.kind', () {
    Future<BiometricKind> kindOn(
      TargetPlatform platform,
      List<BiometricType> types,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        return await LocalAuthBiometrics(_Auth(types)).kind();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    test('en iOS distingue Face ID y Touch ID', () async {
      expect(
        await kindOn(TargetPlatform.iOS, [BiometricType.face]),
        BiometricKind.face,
      );
      expect(
        await kindOn(TargetPlatform.iOS, [BiometricType.fingerprint]),
        BiometricKind.fingerprint,
      );
      expect(await kindOn(TargetPlatform.iOS, []), BiometricKind.generic);
    });

    test('en Android siempre es genérico', () async {
      expect(
        await kindOn(TargetPlatform.android, [BiometricType.face]),
        BiometricKind.generic,
      );
    });
  });

  group('el tipo se refresca con la app abierta', () {
    testWidgets('cada bloqueo vuelve a mirarlo', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.runAsync(() async {
        await phone.container
            .read(familyControllerProvider.notifier)
            .createFamily(deviceName: 'A');
        final lock = phone.container.read(lockControllerProvider.notifier);
        await lock.setPin('4821');
        await lock.setBiometrics(true, reason: 'x');
      });
      phone.restart();
      phone.biometrics.succeeds = false;
      await pumpGate(tester, phone);
      await settle(tester);
      await settle(tester);
      expect(find.bySemanticsLabel('Usar huella o rostro'), findsOneWidget);

      // Se entra con el PIN, se da de alta Face ID con la app abierta y se
      // vuelve a bloquear.
      await typePin(tester, '4821');
      await settle(tester);
      expect(find.text('LA APP'), findsOneWidget);
      // La pantalla de bloqueo se desmonta al acabar la animación de
      // desbloqueo: el siguiente bloqueo monta una nueva.
      await tester.pumpAndSettle();
      expect(find.byType(PinPad), findsNothing);
      phone.biometrics.kindOverride = BiometricKind.face;
      await tester.runAsync(
        () => phone.container.read(lockControllerProvider.notifier).lockNow(),
      );
      for (var i = 0; i < 4; i++) {
        await settle(tester);
      }
      expect(find.bySemanticsLabel('Usar Face ID'), findsOneWidget);
      semantics.dispose();
    });

    screens.screenTest('activar la biometría en Seguridad lo refresca', (
      tester,
      phone,
    ) async {
      await screens.seedSample(tester, phone, pin: true);
      await screens.pumpRegalos(tester, phone);
      expect(
        await tester.runAsync(
          () => phone.container.read(biometricKindProvider.future),
        ),
        BiometricKind.generic,
      );
      phone.biometrics.kindOverride = BiometricKind.face;
      await openSettings(tester);
      await screens.tapText(tester, 'Bloqueo');
      await tester.tap(find.bySemanticsLabel('Face ID'));
      await screens.settle(tester);
      expect(
        await tester.runAsync(
          () => phone.container.read(biometricKindProvider.future),
        ),
        BiometricKind.face,
      );
    }, size: const Size(390, 1500));
  });
}
