import 'dart:async';

import 'package:clock/clock.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/platform/camera_permission.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/features/sharing/presentation/qr_camera_scanner.dart';
import 'package:regalos/l10n/app_localizations.dart';

void main() {
  group('RepeatedCodeFilter', () {
    test(
      'da un código la primera vez y calla mientras siga delante de la cámara',
      () {
        final filter = RepeatedCodeFilter();
        var now = DateTime.utc(2026, 11, 12, 10);
        bool see(String code) =>
            withClock(Clock.fixed(now), () => filter.accept(code));

        expect(see('uno'), isTrue);
        // El lector avisa en cada fotograma: aunque pasen más de tres segundos
        // en total, mientras no deje de verlo no se repite.
        for (var i = 0; i < 20; i++) {
          now = now.add(const Duration(milliseconds: 400));
          expect(see('uno'), isFalse, reason: 'fotograma $i');
        }
      },
    );

    test('tras tres segundos sin verlo, el mismo código se vuelve a dar', () {
      final filter = RepeatedCodeFilter();
      var now = DateTime.utc(2026, 11, 12, 10);
      bool see(String code) =>
          withClock(Clock.fixed(now), () => filter.accept(code));

      expect(see('uno'), isTrue);
      now = now.add(const Duration(milliseconds: 2900));
      expect(see('uno'), isFalse);
      now = now.add(const Duration(seconds: 3));
      expect(see('uno'), isTrue);
    });

    test('un código distinto se da al momento', () {
      final filter = RepeatedCodeFilter();
      final now = DateTime.utc(2026, 11, 12, 10);
      bool see(String code) =>
          withClock(Clock.fixed(now), () => filter.accept(code));

      expect(see('uno'), isTrue);
      expect(see('dos'), isTrue);
      expect(see('dos'), isFalse);
      expect(see('uno'), isTrue);
    });
  });

  // F6: el permiso de cámara se pide una sola vez; si se deniega, se explica
  // sin volver a pedirlo (ni al volver a la app).
  testWidgets('con el permiso denegado explica y no vuelve a pedirlo', (
    tester,
  ) async {
    var requests = 0;
    var checks = 0;
    final denied = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: QrCameraScanner(
          onCode: (_) {},
          requestPermission: () async {
            requests++;
            return false;
          },
          checkPermission: () async {
            checks++;
            return false;
          },
          onDeniedChanged: denied.add,
          errorBuilder: (_) => const Text('Sin cámara'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Sin cámara'), findsOneWidget);
    expect(requests, 1);
    expect(denied, [true]);

    // Volver a la app mira el permiso (por si se dio en Ajustes) pero no lo
    // pide otra vez.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(requests, 1);
    expect(checks, 1);
    expect(find.text('Sin cámara'), findsOneWidget);
  });

  // 1.0.2: con el permiso sin contestar ya no se queda una caja negra para
  // siempre.
  testWidgets('mientras espera el permiso enseña un indicador, y sin '
      'respuesta a los 4 s mira el permiso y deja reintentar', (tester) async {
    final answer = Completer<bool>();
    await tester.pumpWidget(
      MaterialApp(
        home: QrCameraScanner(
          onCode: (_) {},
          requestPermission: () => answer.future,
          checkPermission: () async => false,
          errorBuilder: (_) => const Text('Sin cámara'),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(find.text('Sin cámara'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('waitingBuilder sustituye al indicador', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QrCameraScanner(
          onCode: (_) {},
          requestPermission: () => Completer<bool>().future,
          checkPermission: () async => false,
          waitingBuilder: (_) => const Text('Esperando'),
          errorBuilder: (_) => const Text('Sin cámara'),
        ),
      ),
    );
    expect(find.text('Esperando'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('el issueBuilder recibe el problema y reintenta o abre los '
      'ajustes', (tester) async {
    var requests = 0;
    var settings = 0;
    final outcomes = [
      CameraPermissionOutcome.permanentlyDenied,
      CameraPermissionOutcome.denied,
    ];
    final denied = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: QrCameraScanner(
          onCode: (_) {},
          requestPermissionStatus: () async => outcomes[requests++],
          checkPermission: () async => false,
          openSettings: () async {
            settings++;
            return true;
          },
          onDeniedChanged: denied.add,
          errorBuilder: (_) => const Text('Sin cámara'),
          issueBuilder: (context, issue, retry, openSettings) => Column(
            children: [
              Text('issue ${issue.name}'),
              TextButton(onPressed: retry, child: const Text('Reintentar')),
              TextButton(onPressed: openSettings, child: const Text('Ajustes')),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('issue permanentlyDenied'), findsOneWidget);
    await tester.tap(find.text('Ajustes'));
    await tester.pump();
    expect(settings, 1);
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    await tester.pump();
    expect(requests, 2);
    expect(find.text('issue denied'), findsOneWidget);
    expect(denied, [true]);
    await tester.pumpWidget(const SizedBox());
  });

  group('avisos de siempre', () {
    Widget app(Widget child, {bool reduce = false}) => MaterialApp(
      locale: const Locale('es'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildTheme(AccentId.lavender.palette, Brightness.dark),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
        child: child!,
      ),
      home: Scaffold(body: child),
    );

    AppLocalizations l10n(WidgetTester tester) =>
        AppLocalizations.of(tester.element(find.byType(Scaffold)));

    testWidgets(
      'iOS denial uses native status and offers settings without creating the scanner',
      (tester) async {
        const channel = MethodChannel('com.dferrandizmont.regalos/incoming');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final calls = <String>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return switch (call.method) {
            'requestCameraPermissionStatus' => 'permanentlyDenied',
            'openAppSettings' => true,
            'cameraPermission' => true,
            _ => false,
          };
        });
        addTearDown(() {
          messenger.setMockMethodCallHandler(channel, null);
        });
        await tester.pumpWidget(app(QrCameraScanner(onCode: (_) {})));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        final l = l10n(tester);
        expect(find.text(l.scannerRetry), findsNothing);
        await tester.tap(find.text(l.scannerOpenSettings));
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(calls, [
          'requestCameraPermissionStatus',
          'openAppSettings',
          'cameraPermission',
        ]);
        expect(find.text(l.scannerOpenSettings), findsNothing);
        expect(find.byType(QRView), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant({TargetPlatform.iOS}),
    );

    testWidgets('restricted camera explains Screen Time without actions', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          QrCameraScanner(
            onCode: (_) {},
            requestPermissionStatus: () async =>
                CameraPermissionOutcome.restricted,
            checkPermission: () async => false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final l = l10n(tester);
      expect(find.text(l.cameraRestricted), findsOneWidget);
      expect(find.text(l.scannerOpenSettings), findsNothing);
      expect(find.text(l.scannerRetry), findsNothing);
      expect(find.byType(QRView), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('mientras espera enseña un texto y un indicador, no negro', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          QrCameraScanner(
            onCode: (_) {},
            requestPermission: () => Completer<bool>().future,
            checkPermission: () async => false,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text(l10n(tester).scannerWaitingPermission), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('denegado: aviso con «Reintentar», que vuelve a preguntar', (
      tester,
    ) async {
      var requests = 0;
      await tester.pumpWidget(
        app(
          QrCameraScanner(
            onCode: (_) {},
            requestPermissionStatus: () async {
              requests++;
              return CameraPermissionOutcome.denied;
            },
            checkPermission: () async => false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final l = l10n(tester);
      expect(find.text(l.scannerDeniedTitle), findsOneWidget);
      expect(find.text(l.scannerDeniedBody), findsOneWidget);
      expect(find.text(l.scannerOpenSettings), findsNothing);
      await tester.tap(find.text(l.scannerRetry));
      await tester.pump();
      await tester.pump();
      expect(requests, 2);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('denegado para siempre: aviso con «Abrir ajustes»', (
      tester,
    ) async {
      var settings = 0;
      var requests = 0;
      await tester.pumpWidget(
        app(
          QrCameraScanner(
            onCode: (_) {},
            requestPermissionStatus: () async {
              requests++;
              return CameraPermissionOutcome.permanentlyDenied;
            },
            checkPermission: () async => false,
            openSettings: () async {
              settings++;
              return true;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final l = l10n(tester);
      expect(find.text(l.scannerBlockedTitle), findsOneWidget);
      expect(find.text(l.scannerBlockedBody), findsOneWidget);
      expect(find.text(l.scannerRetry), findsNothing);
      await tester.tap(find.text(l.scannerOpenSettings));
      await tester.pump();
      expect(settings, 1);
      expect(requests, 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('sin respuesta: aviso con «Reintentar»', (tester) async {
      var requests = 0;
      await tester.pumpWidget(
        app(
          QrCameraScanner(
            onCode: (_) {},
            requestPermissionStatus: () {
              requests++;
              return Completer<CameraPermissionOutcome>().future;
            },
            checkPermission: () async => false,
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final l = l10n(tester);
      expect(find.text(l.scannerFailedTitle), findsOneWidget);
      expect(find.text(l.scannerFailedBody), findsOneWidget);
      await tester.tap(find.text(l.scannerRetry));
      await tester.pump();
      expect(requests, 2);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('el aviso entra con un fundido, también con «Reducir '
        'movimiento»', (tester) async {
      for (final reduce in [false, true]) {
        await tester.pumpWidget(
          app(
            reduce: reduce,
            QrCameraScanner(
              onCode: (_) {},
              requestPermissionStatus: () async =>
                  CameraPermissionOutcome.denied,
              checkPermission: () async => false,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        final fade = tester.widget<Opacity>(find.byType(Opacity).first);
        expect(fade.opacity, lessThan(1));
        await tester.pump(const Duration(milliseconds: 700));
        expect(tester.widget<Opacity>(find.byType(Opacity).first).opacity, 1);
        await tester.pumpWidget(const SizedBox());
      }
    });
  });
}
