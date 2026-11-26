// «Conectar la web» desde el móvil: escanear el QR del navegador y comparar
// el código. Desde la 1.0.6 la web hereda la persona de este móvil y no se
// pregunta de quién es. El anfitrión es un doble que apunta lo que se le pide.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/application/self_person_gate.dart';
import 'package:regalos/features/sharing/presentation/join_qr_screen.dart'
    show scannerBuilderProvider;
import 'package:regalos/features/sync/application/pairing_v2_controller.dart';
import 'package:regalos/features/web_device/presentation/connect_web_flow.dart';

import '../../helpers/fake_self_gate.dart';
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
  String? self = 'nora',
  FakeGate? gate,
  List<Override> extra = const <Override>[],
}) async {
  final host = FakeHost();
  _scan = null;
  await pumpMobileWeb(
    tester,
    const ConnectWebScreen(),
    locale: locale,
    size: size,
    overrides: [
      ...extra,
      familyControllerProvider.overrideWith(() => FakeFamily(people, self)),
      pairingV2HostProvider.overrideWith(() => host),
      if (gate != null) selfPersonGateActionsProvider.overrideWithValue(gate),
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
}

/// Pone [text] en el portapapeles simulado.
void _clipboard(WidgetTester tester, String text) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => call.method == 'Clipboard.getData'
        ? <String, Object?>{'text': text}
        : null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
}

void main() {
  setUpAll(loadInter);

  group('pegar el código del QR (solo fuera de la tienda)', () {
    testWidgets('con el botón, el texto pasa por la misma validación y '
        'conecta', (tester) async {
      _clipboard(tester, validWebQr);
      final host = await _open(
        tester,
        extra: [pasteWebQrAllowedProvider.overrideWithValue(true)],
      );
      final l10n = l10nOf(tester);
      expect(find.text(l10n.connectWebPasteCode), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('connectWebPaste')));
      await settleMobile(tester);
      expect(host.calls, contains('startWeb:nora'));
    });

    testWidgets('un texto que no es el QR de la web se rechaza como en el '
        'escáner', (tester) async {
      _clipboard(tester, 'https://example.test/i#otra-cosa');
      final host = await _open(
        tester,
        extra: [pasteWebQrAllowedProvider.overrideWithValue(true)],
      );
      final l10n = l10nOf(tester);
      await tester.tap(find.byKey(const ValueKey<String>('connectWebPaste')));
      await settleMobile(tester);
      expect(find.text(l10n.connectWebScanInvalid), findsOneWidget);
      expect(host.calls.where((c) => c.startsWith('startWeb')), isEmpty);
    });

    testWidgets('en la versión de tienda no hay botón ni camino', (
      tester,
    ) async {
      _clipboard(tester, validWebQr);
      final host = await _open(
        tester,
        extra: [pasteWebQrAllowedProvider.overrideWithValue(false)],
      );
      expect(
        find.byKey(const ValueKey<String>('connectWebPaste')),
        findsNothing,
      );
      expect(find.text(l10nOf(tester).connectWebPasteCode), findsNothing);
      expect(host.calls, isEmpty);
    });
  });

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
          expect(find.text(l10n.whoAreYouTitle), findsNothing);
          expect(host.calls, contains('startWeb:nora'));
          expect(tester.takeException(), isNull);
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
          // B9: avalar la web le entrega los regalos en secreto de los demás.
          expect(find.text(l10n.webApproveSecretsNotice), findsOneWidget);
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
    testWidgets('1.0.6: un QR válido empieza con la persona de este móvil, '
        'sin preguntar', (tester) async {
      final host = await _open(tester);
      expect(host.calls, isEmpty);
      await _scanCode(tester, validWebQr);
      expect(find.text('¿De quién es este ordenador?'), findsNothing);
      expect(host.calls, ['dismiss', 'startWeb:nora']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('1.0.6: sin persona en este móvil, antes «¿Quién eres?»; '
        'no se empieza hasta responder', (tester) async {
      final gate = FakeGate();
      final host = await _open(tester, self: null, gate: gate);
      await _scanCode(tester, validWebQr);
      expect(find.text('¿Quién eres?'), findsOneWidget);
      expect(find.text('¿De quién es este ordenador?'), findsNothing);
      expect(host.calls, isEmpty);
      // «Continuar» espera a que se elija algo.
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('personPickerContinue')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Nora'));
      await settleMobile(tester);
      await tester.tap(find.byKey(const ValueKey('personPickerContinue')));
      await settleMobile(tester);
      expect(gate.calls, ['choose:nora']);
      expect(host.calls, ['dismiss', 'startWeb:null']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('1.0.6: «¿Quién eres?» tiene «No estoy en la lista» y '
        '«Nadie», ambos con nombre', (tester) async {
      final gate = FakeGate();
      await _open(tester, self: null, gate: gate);
      await _scanCode(tester, validWebQr);
      await tester.tap(find.text('No estoy en la lista'));
      await settleMobile(tester);
      await tester.enterText(find.byType(TextField), 'Zed');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('personPickerContinue')));
      await settleMobile(tester);
      expect(gate.calls, ['notOnList:Zed']);
      await tester.pumpWidget(const SizedBox());
    });

    for (final (size, keyboard) in [
      (const Size(375, 667), 260.0),
      (const Size(390, 844), 336.0),
    ]) {
      testWidgets('1.0.7 (iOS M1): con el teclado abierto, «Continuar» queda '
          'por encima de él · ${size.width.toInt()}', (tester) async {
        await _open(tester, self: null, gate: FakeGate(), size: size);
        await _scanCode(tester, validWebQr);
        await tester.tap(find.text('No estoy en la lista'));
        await settleMobile(tester);
        tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
        addTearDown(tester.view.resetViewInsets);
        await settleMobile(tester);
        final next = find.byKey(const ValueKey('personPickerContinue'));
        expect(
          tester.getRect(next).bottom,
          lessThanOrEqualTo(size.height - keyboard),
        );
        await tester.enterText(find.byType(TextField), 'Marta');
        await settleMobile(tester);
        expect(
          tester.getRect(next).bottom,
          lessThanOrEqualTo(size.height - keyboard),
        );
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('1.0.7 (m8): un nombre que ya está en la lista pregunta '
        '«¿Eres tú?» y «Soy yo» elige a esa persona', (tester) async {
      final gate = FakeGate();
      await _open(tester, self: null, gate: gate);
      await _scanCode(tester, validWebQr);
      await tester.tap(find.text('No estoy en la lista'));
      await settleMobile(tester);
      await tester.enterText(find.byType(TextField), ' leo ');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('personPickerContinue')));
      await settleMobile(tester);
      expect(
        find.text('Ya hay alguien llamado Leo en la lista'),
        findsOneWidget,
      );
      expect(gate.calls, isEmpty, reason: 'todavía no se ha creado nada');
      await tester.tap(find.text('Soy yo'));
      await settleMobile(tester);
      expect(gate.calls, ['choose:leo']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('QA 1.0.7 M1: con el teclado abierto, el nombre y «Continuar» '
        'quedan por encima, en vertical y en horizontal', (tester) async {
      for (final (size, keyboard) in const [
        (phone375, 300.0),
        (Size(812, 375), 180.0),
      ]) {
        await _open(tester, self: null, gate: FakeGate(), size: size);
        await _scanCode(tester, validWebQr);
        await tester.ensureVisible(find.byKey(const ValueKey('nobody')));
        await tester.tap(find.byKey(const ValueKey('nobody')));
        await settleMobile(tester);
        tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
        await settleMobile(tester);
        final top = size.height - keyboard;
        expect(tester.getRect(find.byType(TextField)).bottom, lessThan(top));
        final next = find.byKey(const ValueKey('personPickerContinue'));
        await tester.ensureVisible(next);
        await settleMobile(tester);
        expect(tester.getRect(next).bottom, lessThanOrEqualTo(top));
        tester.view.resetViewInsets();
        await tester.pumpWidget(const SizedBox());
      }
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
      }
      expect(host.calls, isEmpty);
      // Uno válido después sigue adelante y quita el aviso.
      await _scanCode(tester, validWebQr);
      expect(host.calls, ['dismiss', 'startWeb:nora']);
      expect(find.textContaining('Ese código no es'), findsNothing);
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
        find.textContaining(
          'Se ha cancelado la conexión y el código ya no sirve',
        ),
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
      // El nuevo QR se vuelve a leer y empieza otra vez.
      await _scanCode(tester, validWebQr);
      expect(host.calls.where((c) => c == 'startWeb:nora'), hasLength(2));
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
