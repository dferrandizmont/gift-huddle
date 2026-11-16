import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:regalos/core/platform/monotonic.dart';
import 'package:regalos/core/prefs/shared_preferences_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/data/secure_wipe.dart';
import 'package:regalos/features/family/data/storage.dart';
import 'package:regalos/features/family/data/storage_providers.dart';
import 'package:regalos/features/lock/data/biometrics.dart';
import 'package:regalos/features/lock/data/pin_vault.dart';
import 'package:regalos/features/sharing/application/share_service.dart';
import 'package:regalos/features/sync/data/sync_config.dart';

import 'dart:io';

/// Almacén seguro en memoria.
class MemorySecretStore implements ErasableSecretStore {
  final Map<String, String> values = {};
  @override
  Future<void> eraseAllSecrets() async => values.clear();

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Ficheros en memoria.
class MemoryFileStore implements ListableFileStore {
  /// [writeDelay] hace que guardar tarde, como el disco de verdad.
  MemoryFileStore({this.writeDelay = Duration.zero});

  final Duration writeDelay;
  final Map<String, Uint8List> files = {};
  @override
  Future<List<String>> listNames() async => files.keys.toList();

  @override
  Future<Uint8List?> read(String name) async => files[name];

  @override
  Future<void> writeAtomic(String name, Uint8List bytes) async {
    if (writeDelay > Duration.zero) {
      await Future<void>.delayed(writeDelay);
    }
    files[name] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> delete(String name) async => files.remove(name);
}

/// Biometría simulada.
class FakeBiometrics implements BiometricAuthenticator {
  FakeBiometrics({this.available = true, this.succeeds = true});

  bool available;
  bool succeeds;
  int prompts = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return succeeds;
  }
}

Duration _monotonicFromClock() =>
    Duration(milliseconds: clock.now().millisecondsSinceEpoch);

/// Un «móvil» de prueba: sus propios almacenes y su propio contenedor.
class FakePhone {
  FakePhone({
    Directory? temp,
    MemorySecretStore? secrets,
    MemoryFileStore? files,
    this.prefs,
    this.extraOverrides = const <Override>[],
    this.syncHost = '',
    Duration writeDelay = Duration.zero,
    MonotonicNow? monotonic,
  }) : monotonic = monotonic ?? _monotonicFromClock,
       secrets = secrets ?? MemorySecretStore(),
       files = files ?? MemoryFileStore(writeDelay: writeDelay),
       biometrics = FakeBiometrics() {
    container = _build(temp);
  }

  /// Preferencias simuladas, para las pruebas que montan la app entera.
  final SharedPreferences? prefs;

  /// Más sustituciones de providers (por ejemplo, el lector de QR).
  final List<Override> extraOverrides;

  /// El servidor de sincronización: vacío por defecto, para que ninguna
  /// prueba hable con el de verdad (`kDefaultSyncHost`). `null` si
  /// [extraOverrides] ya trae el suyo.
  final String? syncHost;

  /// Reloj monotónico del móvil. Por defecto sigue a `clock.now()`, así que
  /// las pruebas que mueven la hora con `withClock` también lo mueven; las
  /// que prueban un salto de la hora del sistema pasan uno propio, quieto.
  final MonotonicNow monotonic;

  final MemorySecretStore secrets;
  final MemoryFileStore files;
  final FakeBiometrics biometrics;
  late ProviderContainer container;

  /// Cuántas veces se ha vaciado entero el almacén seguro.
  int secureWipes = 0;

  ProviderContainer _build(Directory? temp) => ProviderContainer(
    retry: familyRetry,
    overrides: [
      if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs!),
      ...extraOverrides,
      if (syncHost != null) syncHostProvider.overrideWithValue(syncHost!),
      secretStoreProvider.overrideWithValue(secrets),
      fileStoreProvider.overrideWithValue(files),
      // Vaciar el almacén seguro («Borrar todo») vacía el de memoria.
      secureStorageWipeProvider.overrideWithValue(() async {
        secureWipes++;
        secrets.values.clear();
      }),
      biometricAuthenticatorProvider.overrideWithValue(biometrics),
      monotonicNowProvider.overrideWithValue(monotonic),
      // Pocas vueltas y sin hilo aparte: las pruebas no esperan al PBKDF2 real.
      pinVaultProvider.overrideWithValue(
        PinVault(
          secrets: secrets,
          iterations: 1000,
          useIsolate: false,
          monotonic: monotonic,
        ),
      ),
      if (temp != null)
        tempDirectoryProvider.overrideWithValue(() async => temp),
    ],
  );

  /// Simula cerrar la app y abrirla otra vez con lo guardado.
  void restart({Directory? temp}) {
    container.dispose();
    container = _build(temp);
  }

  void dispose() => container.dispose();
}
