import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/monotonic.dart';
import '../../family/data/storage.dart';
import '../../family/data/storage_providers.dart';
import '../data/biometrics.dart';
import '../data/pin_vault.dart';

/// Tiempo en segundo plano a partir del cual se vuelve a pedir el PIN.
const Duration kLockAfterBackground = Duration(seconds: 30);

const _configKey = 'lock.config';

/// Estado del bloqueo.
class AppLockState {
  /// Crea el estado.
  const AppLockState({
    required this.pinSet,
    required this.enabled,
    required this.biometrics,
    required this.locked,
    this.waitUntil,
    this.pinLength,
  });

  /// Si hay un PIN guardado.
  final bool pinSet;

  /// Si el bloqueo está activado. Lo está por defecto; solo se desactiva si
  /// el usuario lo pide.
  final bool enabled;

  /// Si se puede desbloquear con huella o rostro.
  final bool biometrics;

  /// Si ahora hay que desbloquear.
  final bool locked;

  /// Hasta cuándo hay que esperar tras demasiados fallos.
  final DateTime? waitUntil;

  /// Longitud del PIN, si se guardó con él; `null` con un PIN antiguo.
  final int? pinLength;

  /// Si falta crear el PIN: bloqueo activado y sin PIN.
  bool get needsSetup => enabled && !pinSet;

  /// Copia con cambios.
  AppLockState copyWith({
    bool? pinSet,
    bool? enabled,
    bool? biometrics,
    bool? locked,
    DateTime? waitUntil,
    bool clearWait = false,
    int? pinLength,
    bool clearPinLength = false,
  }) => AppLockState(
    pinSet: pinSet ?? this.pinSet,
    enabled: enabled ?? this.enabled,
    biometrics: biometrics ?? this.biometrics,
    locked: locked ?? this.locked,
    waitUntil: clearWait ? null : (waitUntil ?? this.waitUntil),
    pinLength: clearPinLength ? null : (pinLength ?? this.pinLength),
  );
}

/// Controlador del bloqueo por PIN o biometría.
///
/// Arranca bloqueado si hay PIN (siempre en frío). Se vuelve a bloquear al
/// volver de más de 30 segundos en segundo plano.
class LockController extends AsyncNotifier<AppLockState> {
  DateTime? _pausedAt;

  /// Reloj monotónico al pasar a segundo plano. Junto con la hora del
  /// sistema: si alguien la atrasa a mano mientras la app está fuera, el
  /// tiempo monotónico delata que pasó más de lo que dice el reloj.
  Duration? _pausedMono;

  /// Si la huella automática ya se pidió en este bloqueo. Vive aquí y no en
  /// la pantalla: en iOS el diálogo del sistema deja la app `inactive`, la
  /// cubierta destruye `LockScreen` y al volver se crea otra, que no debe
  /// volver a pedirla. Solo se reinicia al pasar a bloqueado.
  bool _autoBiometricSpent = false;

  PinVault get _vault => ref.read(pinVaultProvider);
  SecretStore get _secrets => ref.read(secretStoreProvider);

  @override
  Future<AppLockState> build() async {
    final config = await _readConfig();
    final pinSet = await _vault.isSet();
    final enabled = config.enabled ?? true;
    return AppLockState(
      pinSet: pinSet,
      enabled: enabled,
      biometrics: config.biometrics && pinSet,
      locked: enabled && pinSet,
      waitUntil: await _vault.waitUntil(),
      pinLength: pinSet ? await _vault.pinLength() : null,
    );
  }

  Future<AppLockState> _current() => future;

  Future<({bool? enabled, bool biometrics})> _readConfig() async {
    final raw = await _secrets.read(_configKey);
    if (raw == null) {
      return (enabled: null, biometrics: false);
    }
    try {
      final json = jsonDecode(raw) as Map;
      return (
        enabled: json['enabled'] as bool?,
        biometrics: json['biometrics'] == true,
      );
    } on Object {
      return (enabled: null, biometrics: false);
    }
  }

  Future<void> _writeConfig({
    required bool enabled,
    required bool biometrics,
  }) => _secrets.write(
    _configKey,
    jsonEncode(<String, Object?>{'enabled': enabled, 'biometrics': biometrics}),
  );

  /// Crea o cambia el PIN y activa el bloqueo. Deja la app desbloqueada.
  Future<void> setPin(String pin) async {
    final current = await _current();
    await _vault.setPin(pin);
    await _writeConfig(enabled: true, biometrics: current.biometrics);
    state = AsyncData(
      current.copyWith(
        pinSet: true,
        enabled: true,
        locked: false,
        clearWait: true,
        pinLength: pin.length,
      ),
    );
  }

  /// Cambia el PIN si [oldPin] es correcto.
  Future<PinCheck> changePin(String oldPin, String newPin) async {
    final check = await _vault.verify(oldPin);
    if (check is PinOk) {
      await setPin(newPin);
    } else {
      await _refreshWait();
    }
    return check;
  }

  /// Quien empieza a usar la app puede dejar el PIN para más tarde.
  Future<void> skipSetup() async {
    final current = await _current();
    await _writeConfig(enabled: false, biometrics: false);
    state = AsyncData(current.copyWith(enabled: false, locked: false));
  }

  /// Desactiva el bloqueo si [pin] es correcto: borra el PIN.
  Future<PinCheck> disable(String pin) async {
    final check = await _vault.verify(pin);
    if (check is PinOk) {
      final current = await _current();
      await _vault.clear();
      await _writeConfig(enabled: false, biometrics: false);
      state = AsyncData(
        current.copyWith(
          pinSet: false,
          enabled: false,
          biometrics: false,
          locked: false,
          clearWait: true,
          clearPinLength: true,
        ),
      );
    } else {
      await _refreshWait();
    }
    return check;
  }

  /// «Borrar todo»: quita el PIN, sus fallos y la configuración del bloqueo
  /// sin pedir el PIN, y deja el bloqueo como recién instalado (activado y
  /// sin PIN: la próxima lista volverá a proponer crearlo).
  Future<void> reset() async {
    await _vault.clear();
    await _secrets.delete(_configKey);
    _pausedAt = null;
    _pausedMono = null;
    _autoBiometricSpent = false;
    state = const AsyncData(
      AppLockState(
        pinSet: false,
        enabled: true,
        biometrics: false,
        locked: false,
      ),
    );
  }

  /// Comprueba el PIN y, si es correcto, desbloquea.
  Future<PinCheck> unlock(String pin) async {
    final check = await _vault.verify(pin);
    final current = await _current();
    switch (check) {
      case PinOk():
        state = AsyncData(current.copyWith(locked: false, clearWait: true));
      case PinWrong(:final waitUntil):
        state = AsyncData(
          waitUntil == null
              ? current.copyWith(clearWait: true)
              : current.copyWith(waitUntil: waitUntil),
        );
      case PinLockedOut(:final waitUntil):
        state = AsyncData(current.copyWith(waitUntil: waitUntil));
    }
    return check;
  }

  /// Reclama la huella automática de este bloqueo: `true` solo la primera vez
  /// desde que se bloqueó. Después, la huella solo sale con su botón.
  bool takeAutoBiometric() {
    if (_autoBiometricSpent) {
      return false;
    }
    _autoBiometricSpent = true;
    return true;
  }

  /// Pide huella o rostro y, si salen bien, desbloquea. [reason] es el
  /// texto del sistema, ya traducido.
  Future<bool> unlockWithBiometrics(String reason) async {
    final current = await _current();
    if (!current.biometrics || !current.locked) {
      return false;
    }
    final ok = await ref
        .read(biometricAuthenticatorProvider)
        .authenticate(reason);
    if (ok) {
      state = AsyncData(current.copyWith(locked: false, clearWait: true));
    }
    return ok;
  }

  /// Pide huella o rostro para confirmar algo delicado con la app ya abierta
  /// («Borrar todo»). No cambia el bloqueo. `false` si no hay PIN, si la
  /// biometría no está activada, o si se cancela o falla: entonces quien
  /// llama pide el PIN. [reason] es el texto del sistema, ya traducido.
  Future<bool> confirmWithBiometrics(String reason) async {
    final current = await _current();
    if (!current.pinSet || !current.biometrics) {
      return false;
    }
    return ref.read(biometricAuthenticatorProvider).authenticate(reason);
  }

  /// Activa o desactiva la biometría. Al activarla comprueba que el móvil la
  /// tiene y que funciona ([reason] es el texto del sistema).
  Future<bool> setBiometrics(bool enabled, {required String reason}) async {
    final current = await _current();
    if (!current.pinSet) {
      return false;
    }
    if (enabled) {
      final auth = ref.read(biometricAuthenticatorProvider);
      if (!await auth.isAvailable() || !await auth.authenticate(reason)) {
        return false;
      }
    }
    await _writeConfig(enabled: current.enabled, biometrics: enabled);
    state = AsyncData(current.copyWith(biometrics: enabled));
    return true;
  }

  /// Si el móvil puede usar huella o rostro.
  Future<bool> biometricsAvailable() =>
      ref.read(biometricAuthenticatorProvider).isAvailable();

  /// Bloquea ya.
  Future<void> lockNow() async {
    final current = await _current();
    if (current.enabled && current.pinSet) {
      _autoBiometricSpent = false;
      state = AsyncData(current.copyWith(locked: true));
    }
  }

  /// La app pasó a segundo plano.
  void appPaused() {
    if (_pausedAt == null) {
      _pausedAt = clock.now();
      _pausedMono = ref.read(monotonicNowProvider)();
    }
  }

  /// La app volvió a primer plano: se bloquea si estuvo fuera más de 30 s.
  ///
  /// El tiempo fuera es el mayor de la hora del sistema y del reloj
  /// monotónico, y una hora anterior a la de salida también bloquea: atrasar
  /// el reloj a mano no evita el rebloqueo.
  void appResumed() {
    final pausedAt = _pausedAt;
    final pausedMono = _pausedMono;
    _pausedAt = null;
    _pausedMono = null;
    final current = state.value;
    if (pausedAt == null || current == null) {
      return;
    }
    final now = clock.now();
    final byClock = now.difference(pausedAt);
    final byMono = pausedMono == null
        ? Duration.zero
        : ref.read(monotonicNowProvider)() - pausedMono;
    final away = byClock > byMono ? byClock : byMono;
    if (current.enabled &&
        current.pinSet &&
        !current.locked &&
        (now.isBefore(pausedAt) || away > kLockAfterBackground)) {
      _autoBiometricSpent = false;
      state = AsyncData(current.copyWith(locked: true));
    }
  }

  Future<void> _refreshWait() async {
    final current = await _current();
    final wait = await _vault.waitUntil();
    state = AsyncData(
      wait == null
          ? current.copyWith(clearWait: true)
          : current.copyWith(waitUntil: wait),
    );
  }
}

/// El bloqueo de la app.
final lockControllerProvider =
    AsyncNotifierProvider<LockController, AppLockState>(LockController.new);
