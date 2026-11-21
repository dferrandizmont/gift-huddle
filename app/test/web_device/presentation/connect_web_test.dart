// «Conectar la web» desde el móvil: escanear el QR del navegador, elegir de
// quién es el ordenador y comparar el código. El anfitrión es un doble que
// apunta lo que se le pide.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/sharing/presentation/join_qr_screen.dart'
    show scannerBuilderProvider;
import 'package:regalos/features/sync/application/pairing_v2_controller.dart';
import 'package:regalos/features/web_device/presentation/connect_web_flow.dart';

import '../../helpers/fonts.dart';
import 'gate_test_support.dart' show l10nOf;
import 'mobile_web_support.dart';

/// Lo que lee el lector falso: la prueba lo llama para «escanear».
ValueChanged<String>? _scan;

Future<FakeHost> _open(
  WidgetTester tester, {
  Locale locale = const Locale('es'),
  Size size = phone375,
  Map<String, bool>? people,
}) async {
  final host = FakeHost();
  _scan = null;
  await pumpMobileWeb(
    tester,
    const ConnectWebScreen(),
    locale: locale,
    size: size,
    overrides: [
      familyControllerProvider.overrideWith(() => FakeFamily(people)),
      pairingV2HostProvider.overrideWith(() => host),
      scannerBuilderProvider.overrideWithValue((context, onCode) {
        _scan = onCode;
        return const ColoredBox(color: Colors.black);
      }),
    ],
  );
  return host;
}

Future<void> _scanCode(WidgetTester tester, String text) async {
  _scan!(text);
  await settleMobile(tester);
}

Future<void> _pickNora(WidgetTester tester) async {
  await _scanCode(tester, validWebQr);
  await tester.tap(find.text('Nora'));
  await settleMobile(tester);
}

void main() {
  setUpAll(loadInter);

  for (final size in [phone375, desktop1280]) {
    for (final locale in const ['es', 'ca', 'en']) {
      testWidgets(
        'los tres pasos caben sin desbordes · $locale · ${size.width.toInt()}',
        (tester) async {
          final host = await _open(tester, locale: Locale(locale), size: size);
          final l10n = l10nOf(tester);
          expect(find.text(l10n.connectWebIntro), findsOneWidget);
          expect(tester.takeException(), isNull);

          await _scanCode(tester, validWebQr);
          expect(find.text(l10n.connectWebWhoseTitle), findsOneWidget);
          expect(find.text('Aritz'), findsOneWidget);
          expect(tester.takeException(), isNull);

          await tester.tap(find.text('Nora'));
          await settleMobile(tester);
          expect(host.calls, contains('startWeb:nora'));
          host.push(const PairingV2HostState(PairingV2HostPhase.waiting));
          await settleMobile(tester);
          expect(find.text(l10n.connectWebWaiting), findsOneWidget);
          host.push(
            const PairingV2HostState(
              PairingV2HostPhase.compare,
              code: '123456',
              guestPersonId: 'nora',
              guestPersonName: 'Nora',
            ),
          );
          await settleMobile(tester);
          expect(find.text('123 456'), findsOneWidget);
          expect(find.text(l10n.connectWebCompareBody), findsOneWidget);
          expect(tester.takeException(), isNull);

          host.push(
            const PairingV2HostState(
              PairingV2HostPhase.failed,
              needsNewWebQr: true,
            ),
          );
          await settleMobile(tester);
          expect(find.text(l10n.connectWebNewQr), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  group('escanear', () {
    testWidgets('un QR válido pasa a elegir persona sin crear nada aún', (
      tester,
    ) async {
      final host = await _open(tester);
      await _scanCode(tester, validWebQr);
      expect(find.text('¿De quién es este ordenador?'), findsOneWidget);
      expect(find.text('Aritz'), findsOneWidget);
      expect(find.text('Nora'), findsOneWidget);
      expect(find.text('Leo'), findsOneWidget);
      // Ninguna oferta hasta tener el QR y la persona.
      expect(host.calls, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('un QR que no es el de la web avisa y no sigue', (
      tester,
    ) async {
      final host = await _open(tester);
      for (final bad in [
        mobileInviteQr,
        'hola',
        'https://otro.example.com/w#AAAAAAAAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAA',
        'https://web.gifthuddle.app/w#corto.corto',
      ]) {
        await _scanCode(tester, bad);
        expect(
          find.text(
            'Ese código no es el de la web de Gift Huddle. Escanea el que '
            'aparece en el ordenador.',
          ),
          findsOneWidget,
          reason: bad,
        );
        expect(find.text('¿De quién es este ordenador?'), findsNothing);
      }
      expect(host.calls, isEmpty);
      // Uno válido después sigue adelante y quita el aviso.
      await _scanCode(tester, validWebQr);
      expect(find.text('¿De quién es este ordenador?'), findsOneWidget);
      expect(find.textContaining('Ese código no es'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('las personas archivadas no se pueden elegir', (tester) async {
      await _open(tester, people: const {'Aritz': false, 'Nora': true});
      await _scanCode(tester, validWebQr);
      expect(find.text('Aritz'), findsOneWidget);
      expect(find.text('Nora'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('sin personas avisa de que hay que añadir una', (tester) async {
      await _open(tester, people: const {});
      await _scanCode(tester, validWebQr);
      expect(
        find.text(
          'Todavía no hay personas. Añade una persona antes de '
          'conectar la web.',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('emparejar', () {
    testWidgets('empieza con el QR y la persona elegida', (tester) async {
      final host = await _open(tester);
      await _pickNora(tester);
      expect(host.calls, ['dismiss', 'startWeb:nora']);
      expect(host.lastQr, validWebQr);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('«Coinciden» confirma y la persona se confirma sola', (
      tester,
    ) async {
      final host = await _open(tester);
      await _pickNora(tester);
      host.push(
        const PairingV2HostState(
          PairingV2HostPhase.compare,
          code: '030367',
          guestPersonId: 'nora',
          guestPersonName: 'Nora',
        ),
      );
      await settleMobile(tester);
      expect(find.text('030 367'), findsOneWidget);
      await tester.tap(find.text('Coinciden'));
      await settleMobile(tester);
      expect(host.calls.last, 'confirm');

      // El motor pasa a pedir confirmar la persona: la elegiste tú.
      host.push(
        const PairingV2HostState(
          PairingV2HostPhase.confirmPerson,
          code: '030367',
          guestPersonId: 'nora',
          guestPersonName: 'Nora',
        ),
      );
      await settleMobile(tester);
      expect(host.calls.last, 'confirmPerson');
      expect(find.text('Dando acceso al ordenador…'), findsOneWidget);

      host.push(const PairingV2HostState(PairingV2HostPhase.done));
      await settleMobile(tester);
      expect(find.text('Ordenador conectado'), findsOneWidget);
      expect(
        find.text('En el ordenador, elige un PIN para abrir Gift Huddle.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('si el ordenador responde como otra persona, se cancela', (
      tester,
    ) async {
      final host = await _open(tester);
      await _pickNora(tester);
      host.push(
        const PairingV2HostState(
          PairingV2HostPhase.confirmPerson,
          code: '030367',
          guestPersonId: 'leo',
          guestPersonName: 'Leo',
        ),
      );
      await settleMobile(tester);
      expect(host.calls, isNot(contains('confirmPerson')));
      expect(host.calls.last, 'cancel');
      expect(
        find.textContaining('Se ha cancelado la conexión y el código ya no sirve'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('«No coinciden» cancela la invitación', (tester) async {
      final host = await _open(tester);
      await _pickNora(tester);
      host.push(
        const PairingV2HostState(
          PairingV2HostPhase.compare,
          code: '030367',
          guestPersonId: 'nora',
          guestPersonName: 'Nora',
        ),
      );
      await settleMobile(tester);
      await tester.tap(find.text('No coinciden'));
      await settleMobile(tester);
      expect(host.calls.last, 'cancel');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('código caducado (invite_exists): pide otro QR y vuelve a '
        'escanear', (tester) async {
      final host = await _open(tester);
      await _pickNora(tester);
      host.push(
        const PairingV2HostState(
          PairingV2HostPhase.failed,
          needsNewWebQr: true,
        ),
      );
      await settleMobile(tester);
      expect(
        find.text(
          'Este código ya no vale. En el ordenador, pulsa «Empezar otra vez». '
          'Escanea el código nuevo con el móvil.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Escanear otro código'));
      await settleMobile(tester);
      expect(find.textContaining('abre web.gifthuddle.app'), findsOneWidget);
      // El nuevo QR se vuelve a leer y a preguntar la persona.
      await _scanCode(tester, validWebQr);
      expect(find.text('¿De quién es este ordenador?'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('un fallo al empezar se explica y deja escanear otra vez', (
      tester,
    ) async {
      final host = await _open(tester);
      host.startError = StateError('sin persona');
      await _pickNora(tester);
      expect(
        find.textContaining('No se ha podido conectar el ordenador'),
        findsOneWidget,
      );
      expect(find.text('Escanear otro código'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('sin red: lo dice con el texto de siempre', (tester) async {
      final host = await _open(tester);
      await _pickNora(tester);
      host.push(
        const PairingV2HostState(PairingV2HostPhase.failed, notReady: true),
      );
      await settleMobile(tester);
      expect(
        find.textContaining('tener la sincronización encendida'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });
  });
}
