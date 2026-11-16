import 'dart:convert';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart' show DartHmac, DartPbkdf2, DartSha256;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/monotonic.dart';
import '../../../core/platform/task_runner.dart';
import '../../../core/sync/envelope.dart';
import '../../family/data/storage.dart';
import '../../family/data/storage_providers.dart';

/// Iteraciones de PBKDF2-HMAC-SHA256. Mínimo exigido: 200.000.
const int kPinIterations = 200000;

/// Fallos seguidos a partir de los cuales hay que esperar.
const int kPinFreeAttempts = 5;

/// Primera espera, tras el quinto fallo. Se duplica con cada fallo más.
const Duration kPinFirstWait = Duration(seconds: 30);

/// Espera máxima.
const Duration kPinMaxWait = Duration(hours: 1);

const _pinKey = 'lock.pin';
const _throttleKey = 'lock.throttle';

/// Dígitos mínimos y máximos de un PIN.
const int kPinMinDigits = 4;
const int kPinMaxDigits = 6;
final _pinPattern = RegExp('^[0-9]{$kPinMinDigits,$kPinMaxDigits}\$');

/// Si [pin] vale como PIN: de 4 a 6 dígitos.
bool isValidPin(String pin) => _pinPattern.hasMatch(pin);

/// Resultado de comprobar un PIN.
sealed class PinCheck {
  const PinCheck();
}

/// El PIN es correcto.
final class PinOk extends PinCheck {
  /// Crea el resultado.
  const PinOk();
}

/// El PIN es incorrecto.
final class PinWrong extends PinCheck {
  /// Crea el resultado.
  const PinWrong({required this.failures, this.waitUntil});

  /// Fallos seguidos hasta ahora.
  final int failures;

  /// Hasta cuándo hay que esperar, si ya toca esperar.
  final DateTime? waitUntil;

  /// Intentos que quedan antes de empezar a esperar.
  int get attemptsLeft => max(0, kPinFreeAttempts - failures);
}

/// Hay que esperar antes de volver a intentarlo: ni se comprobó el PIN.
final class PinLockedOut extends PinCheck {
  /// Crea el resultado.
  const PinLockedOut({required this.waitUntil});

  /// Hasta cuándo.
  final DateTime waitUntil;
}

/// Espera tras [failures] fallos seguidos, o cero si aún no toca esperar.
Duration pinWaitAfter(int failures) {
  if (failures < kPinFreeAttempts) {
    return Duration.zero;
  }
  final exponent = min(failures - kPinFreeAttempts, 20);
  final seconds = kPinFirstWait.inSeconds * (1 << exponent);
  return Duration(seconds: min(seconds, kPinMaxWait.inSeconds));
}

/// Guarda del PIN: solo un hash PBKDF2-HMAC-SHA256 con sal aleatoria, en el
/// almacén seguro, y los fallos seguidos con su espera.
class PinVault {
  /// Crea la guarda. [iterations] y [useIsolate] son para pruebas.
  PinVault({
    required this._secrets,
    this.iterations = kPinIterations,
    this.useIsolate = true,
    this._monotonic = systemMonotonicNow,
  });

  final SecretStore _secrets;

  /// Reloj que no se mueve al cambiar la hora del sistema.
  final MonotonicNow _monotonic;

  /// Último origen de espera visto en este proceso: cuándo (en tiempo
  /// monotónico) empezó y cuánto dura. Cubre adelantar la hora del sistema
  /// mientras la app sigue abierta; tras un reinicio solo vale la hora.
  Duration? _waitStartedAt;
  Duration _waitLength = Duration.zero;

  /// Iteraciones con las que se hashea un PIN nuevo.
  final int iterations;

  /// Si se hashea fuera del hilo de la interfaz.
  final bool useIsolate;

  /// Si hay un PIN guardado.
  Future<bool> isSet() async => await _secrets.read(_pinKey) != null;

  /// Longitud del PIN guardado, o `null` si no hay PIN o es un registro
  /// antiguo que no la guardó (entonces la pantalla de bloqueo sigue
  /// pidiendo pulsar «Desbloquear»).
  Future<int?> pinLength() async {
    final raw = await _secrets.read(_pinKey);
    if (raw == null) {
      return null;
    }
    try {
      final len = (jsonDecode(raw) as Map)['len'];
      return len is int && len >= kPinMinDigits && len <= kPinMaxDigits
          ? len
          : null;
    } on Object {
      return null;
    }
  }

  /// Guarda un PIN nuevo. Lanza [ArgumentError] si no son 4-6 dígitos.
  Future<void> setPin(String pin) async {
    if (!isValidPin(pin)) {
      throw ArgumentError.value('…', 'pin', 'el PIN son de 4 a 6 dígitos');
    }
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final hash = await _derive(pin, salt, iterations);
    await _secrets.write(
      _pinKey,
      jsonEncode(<String, Object?>{
        'v': 1,
        // Longitud del PIN: solo sirve para saber cuándo comprobarlo al
        // teclearlo; la comprobación sigue siendo el hash con su sal.
        'len': pin.length,
        'alg': 'pbkdf2-sha256',
        'iter': iterations,
        'salt': encodeBase64Url(salt),
        'hash': encodeBase64Url(hash),
      }),
    );
    await _secrets.delete(_throttleKey);
  }

  /// Borra el PIN y los fallos.
  Future<void> clear() async {
    await _secrets.delete(_pinKey);
    await _secrets.delete(_throttleKey);
  }

  /// Hasta cuándo hay que esperar, o `null` si se puede intentar.
  Future<DateTime?> waitUntil() async {
    final (_, until, last) = await _readThrottle();
    return _pendingWait(until, last);
  }

  /// Comprueba un PIN. Con espera pendiente no lo comprueba.
  Future<PinCheck> verify(String pin) async {
    final raw = await _secrets.read(_pinKey);
    if (raw == null) {
      return const PinWrong(failures: 0);
    }
    var (failures, until, last) = await _readThrottle();
    final pending = _pendingWait(until, last);
    if (pending != null) {
      return PinLockedOut(waitUntil: pending);
    }
    final bool matches;
    try {
      final json = jsonDecode(raw) as Map;
      final salt = decodeBase64Url(json['salt'] as String);
      final expected = decodeBase64Url(json['hash'] as String);
      final hash = isValidPin(pin)
          ? await _derive(pin, salt, json['iter'] as int)
          : const <int>[];
      matches = _constantTimeEquals(hash, expected);
    } on Object {
      return PinWrong(failures: failures);
    }
    if (matches) {
      _waitStartedAt = null;
      await _secrets.delete(_throttleKey);
      return const PinOk();
    }
    failures += 1;
    final wait = pinWaitAfter(failures);
    until = wait == Duration.zero ? null : clock.now().add(wait);
    _waitStartedAt = wait == Duration.zero ? null : _monotonic();
    _waitLength = wait;
    await _secrets.write(
      _throttleKey,
      jsonEncode(<String, Object?>{
        'failures': failures,
        'until': until?.millisecondsSinceEpoch,
        'last': clock.now().millisecondsSinceEpoch,
      }),
    );
    return PinWrong(failures: failures, waitUntil: until);
  }

  /// Hasta cuándo sigue la espera, o `null` si ya pasó.
  ///
  /// Si el reloj está antes del último fallo (alguien lo atrasó a mano para
  /// que el siguiente fallo caiga en el pasado), la espera sigue en pie.
  DateTime? _pendingWait(DateTime? until, DateTime? last) {
    if (until == null) {
      return null;
    }
    final now = clock.now();
    if (until.isAfter(now)) {
      return until;
    }
    if (last != null && now.isBefore(last)) {
      return last;
    }
    // La hora dice que ya pasó: si el reloj monotónico no, alguien adelantó
    // la hora del sistema para saltarse la espera.
    final startedAt = _waitStartedAt;
    if (startedAt != null) {
      final left = _waitLength - (_monotonic() - startedAt);
      if (left > Duration.zero) {
        return now.add(left);
      }
    }
    return null;
  }

  Future<(int, DateTime?, DateTime?)> _readThrottle() async {
    final raw = await _secrets.read(_throttleKey);
    if (raw == null) {
      return (0, null, null);
    }
    try {
      final json = jsonDecode(raw) as Map;
      final failures = json['failures'] as int;
      final until = json['until'] as int?;
      final last = json['last'] as int?;
      return (
        failures,
        until == null ? null : DateTime.fromMillisecondsSinceEpoch(until),
        last == null ? null : DateTime.fromMillisecondsSinceEpoch(last),
      );
    } on Object {
      return (0, null, null);
    }
  }

  Future<List<int>> _derive(String pin, List<int> salt, int rounds) =>
      _deriveHash(pin, salt, rounds, useIsolate: useIsolate);
}

/// Hashea fuera del hilo de la interfaz (los 200.000 giros tardan).
Future<List<int>> _deriveHash(
  String pin,
  List<int> salt,
  int rounds, {
  required bool useIsolate,
}) => useIsolate
    ? runTask(() => _pbkdf2(pin, salt, rounds))
    : _pbkdf2(pin, salt, rounds);

Future<List<int>> _pbkdf2(String pin, List<int> salt, int rounds) async {
  // La clase concreta, sin el `Pbkdf2` abstracto: en wasm, dart2wasm deja
  // sin destino su `deriveKey` (ver lib/core/sync/hkdf.dart). Mismos bytes.
  final key = await DartPbkdf2(
    macAlgorithm: const DartHmac(DartSha256()),
    iterations: rounds,
    bits: 256,
  ).deriveKey(secretKey: SecretKey(utf8.encode(pin)), nonce: salt);
  return key.extractBytes();
}

bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// La guarda del PIN. Las pruebas la sustituyen por una más rápida.
final pinVaultProvider = Provider<PinVault>(
  (ref) => PinVault(
    secrets: ref.watch(secretStoreProvider),
    monotonic: ref.watch(monotonicNowProvider),
  ),
);
