import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/sharing/presentation/qr_camera_scanner.dart';

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
}
