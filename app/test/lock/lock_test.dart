import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/lock/application/lock_controller.dart';
import 'package:regalos/features/lock/data/pin_vault.dart';

import '../helpers/memory_stores.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakePhone phone;
  setUp(() => phone = FakePhone());
  tearDown(() => phone.dispose());

  ProviderContainer c() => phone.container;
  LockController lock() => c().read(lockControllerProvider.notifier);
  Future<AppLockState> state() => c().read(lockControllerProvider.future);

  group('PIN', () {
    test('se guarda un hash PBKDF2 con sal, no el PIN', () async {
      // Con las iteraciones reales, para comprobar el valor por defecto.
      final vault = PinVault(secrets: phone.secrets);
      await vault.setPin('4821');
      final stored = phone.secrets.values['lock.pin']!;
      expect(stored.contains('4821'), isFalse);
      expect(stored, contains('pbkdf2-sha256'));
      expect(stored, contains('"iter":200000'));
      expect(await vault.verify('4821'), isA<PinOk>());
      expect(await vault.verify('1234'), isA<PinWrong>());

      // Dos veces el mismo PIN dan otra sal y otro hash.
      final first = stored;
      await vault.setPin('4821');
      expect(phone.secrets.values['lock.pin'], isNot(first));
    });

    test('guarda la longitud en el mismo registro y la lee de vuelta', () async {
      final vault = PinVault(secrets: phone.secrets, iterations: 10);
      expect(await vault.pinLength(), isNull);
      for (final pin in ['1234', '12345', '123456']) {
        await vault.setPin(pin);
        expect(await vault.pinLength(), pin.length);
        expect(await vault.verify(pin), isA<PinOk>());
      }
      // Sigue habiendo una sola clave de PIN: la longitud va dentro.
      expect(phone.secrets.values.keys.where((k) => k.startsWith('lock.pin')), [
        'lock.pin',
      ]);
      // Un valor fuera de rango o un registro sin él se leen como «no se sabe».
      final record = phone.secrets.values['lock.pin']!;
      phone.secrets.values['lock.pin'] = record.replaceFirst(
        '"len":6',
        '"len":9',
      );
      expect(await vault.pinLength(), isNull);
      phone.secrets.values['lock.pin'] = record.replaceFirst('"len":6,', '');
      expect(await vault.pinLength(), isNull);
      expect(await vault.verify('123456'), isA<PinOk>());
      await vault.clear();
      expect(await vault.pinLength(), isNull);
    });

    test('solo valen de 4 a 6 dígitos', () async {
      final vault = PinVault(secrets: phone.secrets, iterations: 10);
      for (final bad in ['123', '1234567', 'abcd', '12 4', '']) {
        expect(isValidPin(bad), isFalse, reason: bad);
        await expectLater(vault.setPin(bad), throwsArgumentError);
      }
      expect(isValidPin('1234'), isTrue);
      expect(isValidPin('123456'), isTrue);
    });

    test('con el PIN equivocado no entra', () async {
      await lock().setPin('4821');
      await lock().lockNow();
      expect((await state()).locked, isTrue);

      expect(await lock().unlock('0000'), isA<PinWrong>());
      expect((await state()).locked, isTrue);
      expect(await lock().unlock('48210'), isA<PinWrong>());
      expect((await state()).locked, isTrue);

      expect(await lock().unlock('4821'), isA<PinOk>());
      expect((await state()).locked, isFalse);
    });

    test(
      'la espera crece tras los fallos y no deja probar durante ella',
      () async {
        await lock().setPin('4821');
        await lock().lockNow();
        final start = DateTime(2026, 11, 9, 10);
        await withClock(Clock.fixed(start), () async {
          for (var i = 1; i < kPinFreeAttempts; i++) {
            final r = await lock().unlock('0000') as PinWrong;
            expect(r.failures, i);
            expect(r.waitUntil, isNull);
            expect(r.attemptsLeft, kPinFreeAttempts - i);
          }
          final fifth = await lock().unlock('0000') as PinWrong;
          expect(fifth.waitUntil, start.add(const Duration(seconds: 30)));

          // Durante la espera ni el PIN bueno entra.
          final locked = await lock().unlock('4821');
          expect(locked, isA<PinLockedOut>());
          expect((await state()).locked, isTrue);
          expect((await state()).waitUntil, isNotNull);
        });

        // Pasada la espera, un nuevo fallo espera el doble.
        final later = start.add(const Duration(seconds: 31));
        await withClock(Clock.fixed(later), () async {
          final sixth = await lock().unlock('0000') as PinWrong;
          expect(sixth.waitUntil, later.add(const Duration(seconds: 60)));
        });
        expect(pinWaitAfter(7), const Duration(seconds: 120));
        expect(pinWaitAfter(100), kPinMaxWait);
        expect(pinWaitAfter(2), Duration.zero);

        // La espera sobrevive a reiniciar la app.
        await withClock(Clock.fixed(later), () async {
          phone.restart();
          final restarted = await state();
          expect(restarted.locked, isTrue);
          expect(restarted.waitUntil, isNotNull);
          expect(await lock().unlock('4821'), isA<PinLockedOut>());
        });

        // Al acertar se borran los fallos.
        final muchLater = later.add(const Duration(hours: 2));
        await withClock(Clock.fixed(muchLater), () async {
          expect(await lock().unlock('4821'), isA<PinOk>());
        });
        expect(phone.secrets.values.containsKey('lock.throttle'), isFalse);
      },
    );
  });

  test('adelantar o atrasar el reloj no salta la espera', () async {
    await lock().setPin('4821');
    await lock().lockNow();
    final start = DateTime(2026, 11, 9, 10);
    await withClock(Clock.fixed(start), () async {
      for (var i = 0; i < kPinFreeAttempts; i++) {
        await lock().unlock('0000');
      }
    });

    // Adelantar menos de la espera: sigue esperando.
    await withClock(
      Clock.fixed(start.add(const Duration(seconds: 10))),
      () async {
        expect(await lock().unlock('4821'), isA<PinLockedOut>());
      },
    );
    // Atrasar el reloj: sigue esperando y el PIN bueno no entra.
    await withClock(
      Clock.fixed(start.subtract(const Duration(hours: 2))),
      () async {
        expect(await lock().unlock('4821'), isA<PinLockedOut>());
        // Ni siquiera cuenta como intento: no hay fallo nuevo con fecha falsa.
        expect(await lock().unlock('0000'), isA<PinLockedOut>());
      },
    );
    // Aunque atrasado pase la hora del final de la espera original.
    await withClock(
      Clock.fixed(start.subtract(const Duration(seconds: 1))),
      () async => expect(await lock().unlock('4821'), isA<PinLockedOut>()),
    );
    // Con la hora buena y pasada la espera, entra.
    await withClock(
      Clock.fixed(start.add(const Duration(seconds: 31))),
      () async {
        expect(await lock().unlock('4821'), isA<PinOk>());
      },
    );
  });

  group('con un salto de la hora del sistema (reloj monotónico quieto)', () {
    late Duration mono;
    late FakePhone jumpy;
    setUp(() {
      mono = Duration.zero;
      jumpy = FakePhone(monotonic: () => mono);
    });
    tearDown(() => jumpy.dispose());

    LockController jLock() =>
        jumpy.container.read(lockControllerProvider.notifier);
    Future<AppLockState> jState() =>
        jumpy.container.read(lockControllerProvider.future);

    test(
      'adelantar la hora no da por cumplida la espera tras los fallos',
      () async {
        await jLock().setPin('4821');
        await jLock().lockNow();
        final start = DateTime(2026, 11, 9, 10);
        await withClock(Clock.fixed(start), () async {
          for (var i = 0; i < kPinFreeAttempts; i++) {
            await jLock().unlock('0000');
          }
        });
        // La hora salta una hora, pero el reloj monotónico solo avanzó 5 s.
        mono = const Duration(seconds: 5);
        await withClock(
          Clock.fixed(start.add(const Duration(hours: 1))),
          () async {
            expect(await jLock().unlock('4821'), isA<PinLockedOut>());
            expect((await jState()).locked, isTrue);
          },
        );
        // Cuando el monotónico también llega a los 30 s, se puede probar.
        mono = const Duration(seconds: 31);
        await withClock(
          Clock.fixed(start.add(const Duration(hours: 1))),
          () async {
            expect(await jLock().unlock('4821'), isA<PinOk>());
          },
        );
      },
    );

    test(
      'atrasar la hora poco no evita el rebloqueo tras 60 s fuera',
      () async {
        await jLock().setPin('4821');
        final t0 = DateTime(2026, 11, 9, 10);
        withClock(Clock.fixed(t0), jLock().appPaused);
        // Pasaron 60 s de verdad, pero la hora dice que solo 10.
        mono = const Duration(seconds: 60);
        withClock(
          Clock.fixed(t0.add(const Duration(seconds: 10))),
          jLock().appResumed,
        );
        expect((await jState()).locked, isTrue);
      },
    );

    test('una hora anterior a la de salida bloquea', () async {
      await jLock().setPin('4821');
      final t0 = DateTime(2026, 11, 9, 10);
      withClock(Clock.fixed(t0), jLock().appPaused);
      withClock(
        Clock.fixed(t0.subtract(const Duration(minutes: 5))),
        jLock().appResumed,
      );
      expect((await jState()).locked, isTrue);
    });

    test(
      '10 s fuera con la hora y el monotónico de acuerdo no bloquea',
      () async {
        await jLock().setPin('4821');
        final t0 = DateTime(2026, 11, 9, 10);
        withClock(Clock.fixed(t0), jLock().appPaused);
        mono = const Duration(seconds: 10);
        withClock(
          Clock.fixed(t0.add(const Duration(seconds: 10))),
          jLock().appResumed,
        );
        expect((await jState()).locked, isFalse);
      },
    );
  });

  group('cuándo se bloquea', () {
    test(
      'activado por defecto: pide crear el PIN y en frío arranca bloqueado',
      () async {
        final first = await state();
        expect(first.enabled, isTrue);
        expect(first.needsSetup, isTrue);
        expect(first.locked, isFalse);

        await lock().setPin('4821');
        expect((await state()).locked, isFalse);

        phone.restart();
        final cold = await state();
        expect(cold.pinSet, isTrue);
        expect(cold.locked, isTrue);
      },
    );

    test('pasa a segundo plano más de 30 s y se bloquea', () async {
      await lock().setPin('4821');
      final t0 = DateTime(2026, 11, 9, 10);
      withClock(Clock.fixed(t0), lock().appPaused);
      withClock(
        Clock.fixed(t0.add(const Duration(seconds: 31))),
        lock().appResumed,
      );
      expect((await state()).locked, isTrue);
    });

    test('30 s justos o menos no bloquea', () async {
      await lock().setPin('4821');
      final t0 = DateTime(2026, 11, 9, 10);
      withClock(Clock.fixed(t0), lock().appPaused);
      withClock(
        Clock.fixed(t0.add(const Duration(seconds: 30))),
        lock().appResumed,
      );
      expect((await state()).locked, isFalse);
    });

    test('sin PIN o con el bloqueo desactivado nunca bloquea', () async {
      final t0 = DateTime(2026, 11, 9, 10);
      await state();
      withClock(Clock.fixed(t0), lock().appPaused);
      withClock(
        Clock.fixed(t0.add(const Duration(minutes: 5))),
        lock().appResumed,
      );
      expect((await state()).locked, isFalse);

      await lock().skipSetup();
      expect((await state()).enabled, isFalse);
      phone.restart();
      final cold = await state();
      expect(cold.enabled, isFalse);
      expect(cold.locked, isFalse);
    });

    test('desactivar pide el PIN y lo borra', () async {
      await lock().setPin('4821');
      expect(await lock().disable('0000'), isA<PinWrong>());
      expect((await state()).enabled, isTrue);
      expect(await lock().disable('4821'), isA<PinOk>());
      final s = await state();
      expect(s.enabled, isFalse);
      expect(s.pinSet, isFalse);
      expect(phone.secrets.values.containsKey('lock.pin'), isFalse);
    });

    test('cambiar el PIN pide el anterior', () async {
      await lock().setPin('4821');
      expect(await lock().changePin('0000', '9999'), isA<PinWrong>());
      expect(await lock().changePin('4821', '9999'), isA<PinOk>());
      await lock().lockNow();
      expect(await lock().unlock('4821'), isA<PinWrong>());
      expect(await lock().unlock('9999'), isA<PinOk>());
    });
  });

  group('biometría', () {
    test('se activa solo si el móvil la tiene y funciona', () async {
      await lock().setPin('4821');
      phone.biometrics.available = false;
      expect(await lock().setBiometrics(true, reason: 'x'), isFalse);
      expect((await state()).biometrics, isFalse);

      phone.biometrics.available = true;
      expect(await lock().setBiometrics(true, reason: 'x'), isTrue);
      expect((await state()).biometrics, isTrue);
    });

    test('desbloquea y no sin biometría activada', () async {
      await lock().setPin('4821');
      await lock().lockNow();
      expect(await lock().unlockWithBiometrics('x'), isFalse);
      expect(phone.biometrics.prompts, 0);

      await lock().setBiometrics(true, reason: 'x');
      await lock().lockNow();
      phone.biometrics.succeeds = false;
      expect(await lock().unlockWithBiometrics('x'), isFalse);
      expect((await state()).locked, isTrue);
      phone.biometrics.succeeds = true;
      expect(await lock().unlockWithBiometrics('x'), isTrue);
      expect((await state()).locked, isFalse);
    });
  });
}
